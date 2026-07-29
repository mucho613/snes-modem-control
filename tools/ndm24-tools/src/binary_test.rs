use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, ensure};
use ndm24_protocol::{
    DiagnosticSnapshot, DriverState, MODEM_FLAG_POLL_LIMIT, MODEM_FLAG_RX_OVERFLOW,
    MODEM_FLAG_TIMEOUT, MODEM_FLAG_TX_OVERFLOW, MODEM_MAILBOX_ARGUMENT_SIZE,
    MODEM_MAILBOX_COMMAND_AT_TRANSACTION, MODEM_MAILBOX_COMMAND_BINARY_RECEIVE,
    MODEM_MAILBOX_COMMAND_BINARY_TRANSMIT, MODEM_SESSION_RESULT_CONNECT,
    MODEM_SESSION_RESULT_NO_CARRIER, MODEM_SESSION_RESULT_OK, TraceEvent,
};
use serde::Serialize;

use crate::connect_test::{at_arguments, normalize_hardware_revision, restore_peer};
use crate::peer::PeerModem;
use crate::qusb2snes;

const DTE_BAUD: u32 = 115_200;
const SETUP_TIMEOUT_FRAMES: u16 = 300;
const DIAL_TIMEOUT_FRAMES: u16 = 3_900;
const DISCONNECT_TIMEOUT_FRAMES: u16 = 900;
const DATA_TIMEOUT: Duration = Duration::from_secs(15);
const BINARY_CHUNK_MAX_LENGTH: usize = MODEM_MAILBOX_ARGUMENT_SIZE - 1;
const LINE_BITS_PER_BYTE: u64 = 10;
const LINE_BAUD: u64 = 2_400;
const RX_SETTLE_MARGIN: Duration = Duration::from_millis(100);

#[derive(Debug, Serialize)]
struct BinaryReceiveChunk {
    expected: Vec<u8>,
    pending_ring_before_drain: Vec<u8>,
    mailbox_received: Vec<u8>,
}

#[derive(Debug, Serialize)]
struct BinaryTestReport {
    schema_version: u8,
    test_id: String,
    started_unix_seconds: u64,
    hardware_revision: String,
    peer_model: String,
    peer_port: String,
    dte_baud: u32,
    line_modulation: String,
    passed: bool,
    failure: Option<String>,
    peer_connect_line: Option<String>,
    peer_transcript: Vec<String>,
    peer_post_connect_drain: Vec<u8>,
    expected_pattern: Vec<u8>,
    sfc_to_peer_received: Vec<u8>,
    peer_to_sfc_received: Vec<u8>,
    peer_to_sfc_chunks: Vec<BinaryReceiveChunk>,
    post_dtr_rx_before_parser: Vec<u8>,
    initial_snapshot: Option<DiagnosticSnapshot>,
    connected_snapshot: Option<DiagnosticSnapshot>,
    transfer_snapshot: Option<DiagnosticSnapshot>,
    final_snapshot: Option<DiagnosticSnapshot>,
    transfer_trace: Vec<TraceEvent>,
}

pub async fn run(
    websocket: &str,
    labels: &Path,
    port_name: &str,
    hardware_revision: &str,
    output_root: &Path,
) -> Result<PathBuf> {
    let started_unix_seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_secs();
    let (revision_slug, revision_label) = normalize_hardware_revision(hardware_revision)?;
    let test_id = format!("unix-{started_unix_seconds}-revision-{revision_slug}");
    let output_dir = output_root.join(&test_id);
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("create test output {}", output_dir.display()))?;

    let mut report = BinaryTestReport {
        schema_version: 2,
        test_id,
        started_unix_seconds,
        hardware_revision: revision_label,
        peer_model: "I-O DATA DFM-56U / Conexant CX93001".to_owned(),
        peer_port: port_name.to_owned(),
        dte_baud: DTE_BAUD,
        line_modulation: "V.22bis 2400 bps".to_owned(),
        passed: false,
        failure: None,
        peer_connect_line: None,
        peer_transcript: Vec::new(),
        peer_post_connect_drain: Vec::new(),
        expected_pattern: pattern(),
        sfc_to_peer_received: Vec::new(),
        peer_to_sfc_received: Vec::new(),
        peer_to_sfc_chunks: Vec::new(),
        post_dtr_rx_before_parser: Vec::new(),
        initial_snapshot: None,
        connected_snapshot: None,
        transfer_snapshot: None,
        final_snapshot: None,
        transfer_trace: Vec::new(),
    };

    let mut peer = PeerModem::open(port_name, DTE_BAUD)?;
    let test_result = run_connected(websocket, labels, &mut peer, &mut report).await;
    let restore_result = restore_peer(&mut peer);
    report.peer_transcript = peer.transcript().to_vec();

    if let Err(error) = &test_result {
        report.failure = Some(format!("{error:#}"));
    } else if let Err(error) = &restore_result {
        report.failure = Some(format!("test passed but peer restore failed: {error:#}"));
    } else {
        report.passed = true;
    }

    report.final_snapshot = qusb2snes::read_snapshot(websocket, labels).await.ok();
    let report_path = output_dir.join("binary-pattern-test.json");
    fs::write(&report_path, serde_json::to_vec_pretty(&report)?)
        .with_context(|| format!("write test report {}", report_path.display()))?;

    test_result?;
    restore_result?;
    ensure!(report.passed, "binary pattern test did not pass");
    Ok(report_path)
}

async fn run_connected(
    websocket: &str,
    labels: &Path,
    peer: &mut PeerModem,
    report: &mut BinaryTestReport,
) -> Result<()> {
    for command in [
        "ATZ",
        "ATE0",
        "AT&D2",
        "AT&K0",
        "AT+MS=V22B,0,2400,2400,2400,2400",
        "ATS0=1",
    ] {
        peer.command(command, Duration::from_secs(5))
            .with_context(|| format!("configure DFM-56U with {command}"))?;
    }

    let initial = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        initial.driver_state == DriverState::Ready,
        "SFC modem driver is {:?}, expected Ready",
        initial.driver_state
    );
    report.initial_snapshot = Some(initial);

    for command in ["AT&F", "AT%B2400", "ATS7=60", "ATX3"] {
        run_at(
            websocket,
            labels,
            command.as_bytes(),
            MODEM_SESSION_RESULT_OK,
            SETUP_TIMEOUT_FRAMES,
            Duration::from_secs(10),
        )
        .await
        .with_context(|| format!("configure NDM24 with {command}"))?;
    }
    run_at(
        websocket,
        labels,
        b"ATDT0",
        MODEM_SESSION_RESULT_CONNECT,
        DIAL_TIMEOUT_FRAMES,
        Duration::from_secs(75),
    )
    .await
    .context("dial NDM24")?;

    let connect_line = peer
        .wait_for_connect(Duration::from_secs(90))
        .context("DFM-56U did not report CONNECT")?;
    report.peer_connect_line = Some(connect_line);
    report.peer_post_connect_drain =
        peer.drain_data_until_quiet(Duration::from_millis(150), Duration::from_secs(1))?;

    let connected = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        connected.driver_state == DriverState::Connected,
        "SFC modem driver is {:?}, expected Connected",
        connected.driver_state
    );
    report.connected_snapshot = Some(connected);

    let expected = pattern();
    for chunk in expected.chunks(BINARY_CHUNK_MAX_LENGTH) {
        sfc_transmit_chunk(websocket, labels, chunk).await?;
        wait_for_tx_empty(websocket, labels, DATA_TIMEOUT).await?;
    }
    report.sfc_to_peer_received = peer.read_data_exact(expected.len(), DATA_TIMEOUT)?;

    for chunk in expected.chunks(BINARY_CHUNK_MAX_LENGTH) {
        peer.write_data(chunk)?;
        tokio::time::sleep(rx_settle_time(chunk.len())).await;
        let pending_ring_before_drain = qusb2snes::read_pending_rx(websocket, labels).await?;
        let received = drain_sfc_bytes(websocket, labels, chunk.len(), DATA_TIMEOUT).await?;
        report.peer_to_sfc_chunks.push(BinaryReceiveChunk {
            expected: chunk.to_vec(),
            pending_ring_before_drain,
            mailbox_received: received.clone(),
        });
        report.peer_to_sfc_received.extend_from_slice(&received);
    }

    let transfer_snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
    validate_snapshot(&transfer_snapshot)?;
    ensure!(
        transfer_snapshot.rx_read_index == transfer_snapshot.rx_write_index,
        "binary RX drain left bytes in the SFC ring"
    );
    ensure!(
        transfer_snapshot.tx_read_index == transfer_snapshot.tx_write_index,
        "binary TX left bytes in the SFC ring"
    );
    report.transfer_snapshot = Some(transfer_snapshot);

    qusb2snes::mailbox_command(
        websocket,
        labels,
        ndm24_protocol::MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
        Duration::from_secs(5),
    )
    .await?;
    report.transfer_trace = qusb2snes::read_trace_events(websocket, labels).await?;
    qusb2snes::mailbox_command(
        websocket,
        labels,
        ndm24_protocol::MODEM_MAILBOX_COMMAND_RESUME_TRACE,
        Duration::from_secs(5),
    )
    .await?;

    peer.set_dtr(false)?;
    thread::sleep(Duration::from_secs(1));
    report.post_dtr_rx_before_parser = qusb2snes::read_pending_rx(websocket, labels).await?;
    run_at(
        websocket,
        labels,
        &[],
        MODEM_SESSION_RESULT_NO_CARRIER,
        DISCONNECT_TIMEOUT_FRAMES,
        Duration::from_secs(20),
    )
    .await
    .context("wait for NDM24 NO CARRIER")?;

    let final_snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
    validate_snapshot(&final_snapshot)?;
    ensure!(
        final_snapshot.driver_state == DriverState::Ready,
        "SFC modem driver is {:?}, expected Ready after disconnect",
        final_snapshot.driver_state
    );
    ensure!(
        final_snapshot.rx_read_index == final_snapshot.rx_write_index,
        "disconnect parser left bytes in the SFC RX ring"
    );
    report.final_snapshot = Some(final_snapshot);
    ensure!(
        report.sfc_to_peer_received == expected,
        "SFC to peer binary pattern mismatch"
    );
    ensure!(
        report.peer_to_sfc_received == expected,
        "peer to SFC binary pattern mismatch"
    );
    Ok(())
}

fn rx_settle_time(length: usize) -> Duration {
    let line_milliseconds = (length as u64 * LINE_BITS_PER_BYTE * 1_000).div_ceil(LINE_BAUD);
    Duration::from_millis(line_milliseconds) + RX_SETTLE_MARGIN
}

async fn run_at(
    websocket: &str,
    labels: &Path,
    command: &[u8],
    expected_result: u8,
    timeout_frames: u16,
    host_timeout: Duration,
) -> Result<()> {
    let arguments = at_arguments(command, expected_result, timeout_frames)?;
    let outcome = qusb2snes::mailbox_command_with_arguments(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
        &arguments,
        host_timeout,
    )
    .await?;
    ensure!(
        outcome.result == expected_result as u16,
        "SFC returned result {}, expected {}",
        outcome.result,
        expected_result
    );
    Ok(())
}

async fn sfc_transmit_chunk(websocket: &str, labels: &Path, data: &[u8]) -> Result<()> {
    ensure!(
        !data.is_empty() && data.len() <= BINARY_CHUNK_MAX_LENGTH,
        "binary TX chunk length is invalid"
    );
    let mut arguments = Vec::with_capacity(data.len() + 1);
    arguments.push(data.len() as u8);
    arguments.extend_from_slice(data);
    let outcome = qusb2snes::mailbox_command_with_arguments(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_BINARY_TRANSMIT,
        &arguments,
        Duration::from_secs(5),
    )
    .await?;
    ensure!(
        outcome.result as usize == data.len(),
        "SFC queued {} of {} binary TX bytes",
        outcome.result,
        data.len()
    );
    Ok(())
}

async fn drain_sfc_bytes(
    websocket: &str,
    labels: &Path,
    length: usize,
    timeout: Duration,
) -> Result<Vec<u8>> {
    let deadline = Instant::now() + timeout;
    let mut data = Vec::with_capacity(length);
    while data.len() < length && Instant::now() < deadline {
        let outcome = qusb2snes::mailbox_command_with_arguments(
            websocket,
            labels,
            MODEM_MAILBOX_COMMAND_BINARY_RECEIVE,
            &[],
            Duration::from_secs(5),
        )
        .await?;
        let count = outcome.result as usize;
        ensure!(
            count <= BINARY_CHUNK_MAX_LENGTH && count <= outcome.output.len(),
            "SFC returned invalid binary RX length {count}"
        );
        data.extend_from_slice(&outcome.output[..count]);
        if count == 0 {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        ensure!(
            data.len() <= length,
            "SFC returned more binary RX bytes than requested"
        );
    }
    ensure!(
        data.len() == length,
        "timed out after receiving {} of {length} SFC bytes",
        data.len()
    );
    Ok(data)
}

async fn wait_for_tx_empty(websocket: &str, labels: &Path, timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
        if snapshot.tx_read_index == snapshot.tx_write_index {
            return Ok(());
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    ensure!(false, "timed out waiting for SFC TX ring to drain");
    Ok(())
}

fn validate_snapshot(snapshot: &DiagnosticSnapshot) -> Result<()> {
    let fatal_flags = MODEM_FLAG_POLL_LIMIT
        | MODEM_FLAG_RX_OVERFLOW
        | MODEM_FLAG_TX_OVERFLOW
        | MODEM_FLAG_TIMEOUT;
    ensure!(snapshot.last_error == 0, "SFC last_error is non-zero");
    ensure!(
        snapshot.flags & fatal_flags == 0,
        "SFC driver has fatal flags 0x{:02x}",
        snapshot.flags & fatal_flags
    );
    ensure!(snapshot.rx_overflow == 0, "SFC RX overflowed");
    ensure!(snapshot.tx_overflow == 0, "SFC TX overflowed");
    ensure!(snapshot.timeout == 0, "SFC transaction timed out");
    Ok(())
}

fn pattern() -> Vec<u8> {
    (0u8..=u8::MAX).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pattern_contains_every_byte_once() {
        let data = pattern();
        assert_eq!(data.len(), 256);
        for (index, byte) in data.into_iter().enumerate() {
            assert_eq!(byte as usize, index);
        }
    }

    #[test]
    fn receive_settle_time_covers_v22bis_line_time() {
        assert_eq!(rx_settle_time(31), Duration::from_millis(230));
        assert_eq!(rx_settle_time(8), Duration::from_millis(134));
    }
}
