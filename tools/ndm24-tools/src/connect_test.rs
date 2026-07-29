use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, ensure};
use ndm24_protocol::{
    DiagnosticSnapshot, MODEM_FLAG_RX_OVERFLOW, MODEM_FLAG_TIMEOUT, MODEM_FLAG_TX_OVERFLOW,
    MODEM_MAILBOX_COMMAND_AT_TRANSACTION, MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
    MODEM_MAILBOX_COMMAND_FREEZE_TRACE, MODEM_MAILBOX_COMMAND_RESUME_TRACE,
    MODEM_SESSION_RESULT_CONNECT, MODEM_SESSION_RESULT_NO_CARRIER, MODEM_SESSION_RESULT_OK,
    TraceEvent,
};
use serde::Serialize;

use crate::peer::PeerModem;
use crate::qusb2snes;

const DTE_BAUD: u32 = 115_200;
const SETUP_TIMEOUT_FRAMES: u16 = 300;
const DIAL_TIMEOUT_FRAMES: u16 = 3_900;
const DISCONNECT_TIMEOUT_FRAMES: u16 = 900;
pub(crate) const NDM24_SETUP_COMMANDS: [&str; 5] = ["AT&F", "ATM0", "AT%B2400", "ATS7=60", "ATX3"];

#[derive(Debug, Serialize)]
struct TransactionRecord {
    command: String,
    expected_result: u8,
    mailbox_result: u16,
    rx_discarded_before: u32,
    rx_discarded_after: u32,
    snapshot: DiagnosticSnapshot,
    trace: Vec<TraceEvent>,
}

#[derive(Debug, Serialize)]
struct TraceCapture {
    label: String,
    snapshot: Option<DiagnosticSnapshot>,
    trace: Vec<TraceEvent>,
}

#[derive(Debug, Serialize)]
struct ConnectTestReport {
    schema_version: u8,
    test_id: String,
    started_unix_seconds: u64,
    hardware_revision: String,
    peer_model: String,
    peer_port: String,
    dte_baud: u32,
    line_modulation: String,
    hold_seconds: u64,
    passed: bool,
    failure: Option<String>,
    peer_connect_line: Option<String>,
    peer_transcript: Vec<String>,
    initial_snapshot: Option<DiagnosticSnapshot>,
    connected_rx_before_disconnect: Vec<u8>,
    post_dtr_rx_before_parser: Vec<u8>,
    transactions: Vec<TransactionRecord>,
    failure_capture: Option<TraceCapture>,
    final_snapshot: Option<DiagnosticSnapshot>,
}

pub async fn run(
    websocket: &str,
    labels: &Path,
    port_name: &str,
    hardware_revision: &str,
    output_root: &Path,
    hold_seconds: u64,
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

    let mut report = ConnectTestReport {
        schema_version: 4,
        test_id,
        started_unix_seconds,
        hardware_revision: revision_label,
        peer_model: "I-O DATA DFM-56U / Conexant CX93001".to_owned(),
        peer_port: port_name.to_owned(),
        dte_baud: DTE_BAUD,
        line_modulation: "V.22bis 2400 bps".to_owned(),
        hold_seconds,
        passed: false,
        failure: None,
        peer_connect_line: None,
        peer_transcript: Vec::new(),
        initial_snapshot: None,
        connected_rx_before_disconnect: Vec::new(),
        post_dtr_rx_before_parser: Vec::new(),
        transactions: Vec::new(),
        failure_capture: None,
        final_snapshot: None,
    };

    let mut peer = PeerModem::open(port_name, DTE_BAUD)?;
    let test_result = run_connected(websocket, labels, hold_seconds, &mut peer, &mut report).await;

    let restore_result = restore_peer(&mut peer);
    report.peer_transcript = peer.transcript().to_vec();

    if let Err(error) = &test_result {
        report.failure = Some(format!("{error:#}"));
        report.failure_capture = capture_failure(websocket, labels).await.ok();
    } else if let Err(error) = &restore_result {
        report.failure = Some(format!("test passed but peer restore failed: {error:#}"));
    } else {
        report.passed = true;
    }

    report.final_snapshot = qusb2snes::read_snapshot(websocket, labels).await.ok();
    let report_path = output_dir.join("connect-test.json");
    fs::write(&report_path, serde_json::to_vec_pretty(&report)?)
        .with_context(|| format!("write test report {}", report_path.display()))?;

    test_result?;
    restore_result?;
    ensure!(report.passed, "connect test did not pass");
    Ok(report_path)
}

pub fn normalize_hardware_revision(revision: &str) -> Result<(String, String)> {
    match revision.trim().to_ascii_uppercase().as_str() {
        "A" => Ok(("a".to_owned(), "A (early)".to_owned())),
        "B" => Ok(("b".to_owned(), "B (late)".to_owned())),
        _ => anyhow::bail!("hardware revision must be A or B"),
    }
}

async fn run_connected(
    websocket: &str,
    labels: &Path,
    hold_seconds: u64,
    peer: &mut PeerModem,
    report: &mut ConnectTestReport,
) -> Result<()> {
    for command in [
        "ATZ",
        "ATE0",
        "AT&D2",
        "AT+MS=V22B,0,2400,2400,2400,2400",
        "ATS0=1",
    ] {
        peer.command(command, Duration::from_secs(5))
            .with_context(|| format!("configure DFM-56U with {command}"))?;
    }

    let initial = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        initial.driver_state == ndm24_protocol::DriverState::Ready,
        "SFC modem driver is {:?}, expected Ready",
        initial.driver_state
    );
    report.initial_snapshot = Some(initial);

    for command in NDM24_SETUP_COMMANDS {
        let record = transact(
            websocket,
            labels,
            command.as_bytes(),
            MODEM_SESSION_RESULT_OK,
            SETUP_TIMEOUT_FRAMES,
            Duration::from_secs(10),
            command,
        )
        .await?;
        report.transactions.push(record);
    }

    let dial = transact(
        websocket,
        labels,
        b"ATDT0",
        MODEM_SESSION_RESULT_CONNECT,
        DIAL_TIMEOUT_FRAMES,
        Duration::from_secs(75),
        "ATDT0",
    )
    .await?;
    report.transactions.push(dial);

    let connect_line = peer
        .wait_for_connect(Duration::from_secs(90))
        .context("DFM-56U did not report CONNECT")?;
    report.peer_connect_line = Some(connect_line);

    thread::sleep(Duration::from_secs(hold_seconds));
    report.connected_rx_before_disconnect = qusb2snes::read_pending_rx(websocket, labels).await?;
    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
        Duration::from_secs(5),
    )
    .await?;
    peer.set_dtr(false)?;
    thread::sleep(Duration::from_secs(1));
    report.post_dtr_rx_before_parser = qusb2snes::read_pending_rx(websocket, labels).await?;

    let disconnect = transact_without_trace_clear(
        websocket,
        labels,
        &[],
        MODEM_SESSION_RESULT_NO_CARRIER,
        DISCONNECT_TIMEOUT_FRAMES,
        Duration::from_secs(20),
        "<wait NO CARRIER>",
    )
    .await?;
    report.transactions.push(disconnect);

    let final_snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
    let fatal_flags = MODEM_FLAG_RX_OVERFLOW | MODEM_FLAG_TX_OVERFLOW | MODEM_FLAG_TIMEOUT;
    ensure!(final_snapshot.last_error == 0, "SFC last_error is non-zero");
    ensure!(
        final_snapshot.flags & fatal_flags == 0,
        "SFC driver has fatal flags 0x{:02x}",
        final_snapshot.flags & fatal_flags
    );
    ensure!(final_snapshot.rx_overflow == 0, "SFC RX overflowed");
    ensure!(final_snapshot.tx_overflow == 0, "SFC TX overflowed");
    ensure!(final_snapshot.timeout == 0, "SFC transaction timed out");
    ensure!(
        final_snapshot.rx_read_index == final_snapshot.rx_write_index,
        "AT parser left bytes in the RX ring"
    );
    report.final_snapshot = Some(final_snapshot);
    Ok(())
}

async fn transact(
    websocket: &str,
    labels: &Path,
    command: &[u8],
    expected_result: u8,
    timeout_frames: u16,
    host_timeout: Duration,
    label: &str,
) -> Result<TransactionRecord> {
    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
        Duration::from_secs(5),
    )
    .await?;
    transact_without_trace_clear(
        websocket,
        labels,
        command,
        expected_result,
        timeout_frames,
        host_timeout,
        label,
    )
    .await
}

async fn transact_without_trace_clear(
    websocket: &str,
    labels: &Path,
    command: &[u8],
    expected_result: u8,
    timeout_frames: u16,
    host_timeout: Duration,
    label: &str,
) -> Result<TransactionRecord> {
    let before = qusb2snes::read_snapshot(websocket, labels).await?;
    let arguments = at_arguments(command, expected_result, timeout_frames)?;
    let outcome = qusb2snes::mailbox_command_with_arguments(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
        &arguments,
        host_timeout,
    )
    .await
    .with_context(|| format!("SFC AT transaction {label}"))?;
    ensure!(
        outcome.result == expected_result as u16,
        "SFC returned result {}, expected {}",
        outcome.result,
        expected_result
    );

    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
        Duration::from_secs(5),
    )
    .await?;
    let trace = qusb2snes::read_trace_events(websocket, labels).await?;
    let snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_RESUME_TRACE,
        Duration::from_secs(5),
    )
    .await?;

    Ok(TransactionRecord {
        command: label.to_owned(),
        expected_result,
        mailbox_result: outcome.result,
        rx_discarded_before: before.rx_discarded,
        rx_discarded_after: snapshot.rx_discarded,
        snapshot,
        trace,
    })
}

pub(crate) fn at_arguments(
    command: &[u8],
    expected_result: u8,
    timeout_frames: u16,
) -> Result<Vec<u8>> {
    let mut framed = command.to_vec();
    if !framed.is_empty() {
        framed.extend_from_slice(b"\r\n");
    }
    ensure!(framed.len() <= 28, "AT command exceeds mailbox capacity");

    let mut arguments = Vec::with_capacity(4 + framed.len());
    arguments.push(expected_result);
    arguments.extend_from_slice(&timeout_frames.to_le_bytes());
    arguments.push(framed.len() as u8);
    arguments.extend_from_slice(&framed);
    Ok(arguments)
}

pub(crate) fn restore_peer(peer: &mut PeerModem) -> Result<()> {
    peer.set_dtr(false)?;
    thread::sleep(Duration::from_millis(500));
    peer.set_dtr(true)?;
    thread::sleep(Duration::from_millis(500));
    peer.command("ATZ", Duration::from_secs(5))
}

async fn capture_failure(websocket: &str, labels: &Path) -> Result<TraceCapture> {
    let _ = qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
        Duration::from_secs(5),
    )
    .await;
    Ok(TraceCapture {
        label: "failure".to_owned(),
        snapshot: qusb2snes::read_snapshot(websocket, labels).await.ok(),
        trace: qusb2snes::read_trace_events(websocket, labels)
            .await
            .unwrap_or_default(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_framed_at_transaction_arguments() {
        let arguments = at_arguments(b"ATX3", MODEM_SESSION_RESULT_OK, 300).unwrap();
        assert_eq!(&arguments[..4], &[MODEM_SESSION_RESULT_OK, 0x2c, 0x01, 6]);
        assert_eq!(&arguments[4..], b"ATX3\r\n");
    }

    #[test]
    fn builds_empty_wait_transaction_arguments() {
        let arguments = at_arguments(&[], MODEM_SESSION_RESULT_NO_CARRIER, 900).unwrap();
        assert_eq!(
            arguments,
            vec![MODEM_SESSION_RESULT_NO_CARRIER, 0x84, 0x03, 0]
        );
    }

    #[test]
    fn reapplies_speaker_off_immediately_after_factory_defaults() {
        assert_eq!(&NDM24_SETUP_COMMANDS[..2], &["AT&F", "ATM0"]);
    }

    #[test]
    fn normalizes_supported_hardware_revisions() {
        assert_eq!(
            normalize_hardware_revision("a").unwrap(),
            ("a".to_owned(), "A (early)".to_owned())
        );
        assert_eq!(
            normalize_hardware_revision(" B ").unwrap(),
            ("b".to_owned(), "B (late)".to_owned())
        );
        assert!(normalize_hardware_revision("C").is_err());
    }
}
