use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail, ensure};
use ndm24_protocol::{
    DiagnosticSnapshot, DriverState, MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
    MODEM_MAILBOX_COMMAND_BINARY_PRBS_RECEIVE, MODEM_MAILBOX_COMMAND_BINARY_PRBS_TRANSMIT,
    MODEM_SESSION_RESULT_CONNECT, MODEM_SESSION_RESULT_OK,
};
use serde::Serialize;

use crate::connect_test::{at_arguments, normalize_hardware_revision};
use crate::peer::PeerModem;
use crate::prbs::{self, PrbsOutcome};
use crate::qusb2snes;

const DTE_BAUD: u32 = 115_200;
const SEED: u16 = 0xace1;
const SETUP_TIMEOUT_FRAMES: u16 = 600;
const DIAL_TIMEOUT_FRAMES: u16 = 4_500;

#[derive(Debug, Serialize)]
struct DirectionReport {
    direction: &'static str,
    expected_length: u32,
    host_bit_exact: bool,
    sfc: PrbsOutcome,
    elapsed_seconds: f64,
    payload_bits_per_second: f64,
}

#[derive(Debug, Serialize)]
struct SpeedTestReport {
    schema_version: u8,
    test_id: String,
    started_unix_seconds: u64,
    hardware_revision: String,
    speed_bps: u32,
    transfer_length: u32,
    requested_soak_seconds: u64,
    completed_soak_seconds: u64,
    peer_port: String,
    peer_connect_line: Option<String>,
    peer_transcript: Vec<String>,
    passed: bool,
    failure: Option<String>,
    initial_snapshot: Option<DiagnosticSnapshot>,
    connected_snapshot: Option<DiagnosticSnapshot>,
    final_snapshot: Option<DiagnosticSnapshot>,
    transfers: Vec<DirectionReport>,
}

pub async fn run(
    websocket: &str,
    labels: &Path,
    port_name: &str,
    hardware_revision: &str,
    speed: u32,
    length: u32,
    soak_seconds: u64,
    output_root: &Path,
) -> Result<PathBuf> {
    ensure!(length != 0, "transfer length must be non-zero");
    let peer_carrier = carrier(speed)?;
    let started_unix_seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_secs();
    let (revision_slug, revision_label) = normalize_hardware_revision(hardware_revision)?;
    let test_id =
        format!("unix-{started_unix_seconds}-revision-{revision_slug}-{speed}bps-speed-test");
    let output_dir = output_root.join(&test_id);
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("create test output {}", output_dir.display()))?;

    let mut report = SpeedTestReport {
        schema_version: 1,
        test_id,
        started_unix_seconds,
        hardware_revision: revision_label,
        speed_bps: speed,
        transfer_length: length,
        requested_soak_seconds: soak_seconds,
        completed_soak_seconds: 0,
        peer_port: port_name.to_owned(),
        peer_connect_line: None,
        peer_transcript: Vec::new(),
        passed: false,
        failure: None,
        initial_snapshot: None,
        connected_snapshot: None,
        final_snapshot: None,
        transfers: Vec::new(),
    };

    let mut peer = PeerModem::open(port_name, DTE_BAUD)?;
    let test_result = Box::pin(run_connected(
        websocket,
        labels,
        &mut peer,
        peer_carrier,
        speed,
        length,
        soak_seconds,
        &mut report,
    ))
    .await;
    let restore_result = Box::pin(restore(websocket, labels, &mut peer)).await;
    report.peer_transcript = peer.transcript().to_vec();
    report.final_snapshot = qusb2snes::read_snapshot(websocket, labels).await.ok();
    report.failure = test_result
        .as_ref()
        .err()
        .map(|error| format!("{error:#}"))
        .or_else(|| {
            restore_result
                .as_ref()
                .err()
                .map(|error| format!("test passed but restore failed: {error:#}"))
        });
    report.passed = report.failure.is_none();

    let report_path = output_dir.join("speed-test.json");
    fs::write(&report_path, serde_json::to_vec_pretty(&report)?)
        .with_context(|| format!("write speed test report {}", report_path.display()))?;
    test_result?;
    restore_result?;
    Ok(report_path)
}

async fn run_connected(
    websocket: &str,
    labels: &Path,
    peer: &mut PeerModem,
    peer_carrier: &str,
    speed: u32,
    length: u32,
    soak_seconds: u64,
    report: &mut SpeedTestReport,
) -> Result<()> {
    wait_for_driver_state(
        websocket,
        labels,
        DriverState::Ready,
        Duration::from_secs(20),
    )
    .await?;
    let initial = qusb2snes::read_snapshot(websocket, labels).await?;
    report.initial_snapshot = Some(initial);

    for command in [
        "ATZ".to_owned(),
        "ATE0".to_owned(),
        "AT&D2".to_owned(),
        "AT&K0".to_owned(),
        "AT%C0".to_owned(),
        "AT\\N3".to_owned(),
        "ATW2".to_owned(),
        format!("AT+MS={peer_carrier},0,{speed},{speed},{speed},{speed}"),
        "ATS0=1".to_owned(),
    ] {
        peer.command(&command, Duration::from_secs(5))
            .with_context(|| format!("configure DFM-56U with {command}"))?;
    }

    for command in [
        "AT&F".to_owned(),
        "ATM0".to_owned(),
        "AT%C0".to_owned(),
        "AT\\N3".to_owned(),
        format!("AT%B{speed}"),
        "ATS7=60".to_owned(),
        "ATX3".to_owned(),
    ] {
        run_at(
            websocket,
            labels,
            command.as_bytes(),
            MODEM_SESSION_RESULT_OK,
            SETUP_TIMEOUT_FRAMES,
            Duration::from_secs(15),
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
        Duration::from_secs(90),
    )
    .await
    .context("dial NDM24")?;
    let connect = peer
        .wait_for_connect(Duration::from_secs(90))
        .context("DFM-56U did not report CONNECT")?;
    ensure!(
        connect
            .split_whitespace()
            .any(|part| part == speed.to_string()),
        "DFM-56U negotiated a different line speed: {connect}"
    );
    report.peer_connect_line = Some(connect);
    let _ = peer.drain_data_until_quiet(Duration::from_millis(150), Duration::from_secs(1))?;

    let connected = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        connected.driver_state == DriverState::Connected,
        "SFC modem driver is {:?}, expected Connected",
        connected.driver_state
    );
    report.connected_snapshot = Some(connected);

    report
        .transfers
        .push(Box::pin(transmit_test(websocket, labels, peer, speed, length)).await?);
    report
        .transfers
        .push(Box::pin(receive_test(websocket, labels, peer, speed, length)).await?);
    if soak_seconds != 0 {
        let started = Instant::now();
        while started.elapsed() < Duration::from_secs(soak_seconds) {
            let snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
            ensure!(
                snapshot.driver_state == DriverState::Connected,
                "carrier soak lost connection after {} seconds",
                started.elapsed().as_secs()
            );
            report.completed_soak_seconds = started.elapsed().as_secs();
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
        report.completed_soak_seconds = soak_seconds;
    }
    Ok(())
}

async fn transmit_test(
    websocket: &str,
    labels: &Path,
    peer: &PeerModem,
    speed: u32,
    length: u32,
) -> Result<DirectionReport> {
    let expected = prbs::bytes(SEED, length as usize)?;
    let mut port = peer.clone_port()?;
    let timeout = transfer_timeout(speed, length);
    let reader =
        tokio::task::spawn_blocking(move || read_exact_timeout(&mut *port, length, timeout));
    let started = Instant::now();
    let outcome = prbs_mailbox(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_BINARY_PRBS_TRANSMIT,
        length,
        speed,
        timeout,
    )
    .await?;
    let received = reader.await.context("join peer reader")??;
    let elapsed = started.elapsed().as_secs_f64();
    ensure!(
        outcome.processed == length,
        "SFC transmitted only {} bytes",
        outcome.processed
    );
    ensure!(
        received == expected,
        "SFC-to-peer PRBS data was not bit-exact"
    );
    validate_throughput(speed, length, elapsed)?;
    Ok(DirectionReport {
        direction: "sfc-to-peer",
        expected_length: length,
        host_bit_exact: true,
        sfc: outcome,
        elapsed_seconds: elapsed,
        payload_bits_per_second: length as f64 * 8.0 / elapsed,
    })
}

async fn receive_test(
    websocket: &str,
    labels: &Path,
    peer: &PeerModem,
    speed: u32,
    length: u32,
) -> Result<DirectionReport> {
    let data = prbs::bytes(SEED, length as usize)?;
    let mut port = peer.clone_port()?;
    let timeout = transfer_timeout(speed, length);
    let writer = tokio::task::spawn_blocking(move || -> Result<()> {
        std::thread::sleep(Duration::from_millis(250));
        for chunk in data.chunks(64) {
            port.write_all(chunk)?;
            port.flush()?;
            std::thread::sleep(Duration::from_secs_f64(
                chunk.len() as f64 * 10.0 / speed as f64,
            ));
        }
        Ok(())
    });
    let started = Instant::now();
    let outcome = prbs_mailbox(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_BINARY_PRBS_RECEIVE,
        length,
        speed,
        timeout,
    )
    .await?;
    writer.await.context("join peer writer")??;
    let elapsed = started.elapsed().as_secs_f64();
    ensure!(
        outcome.processed == length,
        "SFC received only {} bytes",
        outcome.processed
    );
    ensure!(
        outcome.mismatch_count == 0,
        "peer-to-SFC PRBS had {} mismatches; first={:?}, expected={:02x}, actual={:02x}",
        outcome.mismatch_count,
        outcome.first_mismatch,
        outcome.expected,
        outcome.actual
    );
    validate_throughput(speed, length, elapsed)?;
    Ok(DirectionReport {
        direction: "peer-to-sfc",
        expected_length: length,
        host_bit_exact: true,
        sfc: outcome,
        elapsed_seconds: elapsed,
        payload_bits_per_second: length as f64 * 8.0 / elapsed,
    })
}

async fn prbs_mailbox(
    websocket: &str,
    labels: &Path,
    command: u8,
    length: u32,
    speed: u32,
    timeout: Duration,
) -> Result<PrbsOutcome> {
    let mut arguments = Vec::with_capacity(7);
    arguments.extend_from_slice(&length.to_le_bytes());
    arguments.extend_from_slice(&SEED.to_le_bytes());
    arguments.push(
        u8::try_from(speed / 600)
            .context("speed pacing does not fit in one byte")?
            .max(1),
    );
    let outcome =
        qusb2snes::mailbox_command_with_arguments(websocket, labels, command, &arguments, timeout)
            .await?;
    PrbsOutcome::decode(&outcome.output)
}

async fn run_at(
    websocket: &str,
    labels: &Path,
    command: &[u8],
    expected: u8,
    timeout_frames: u16,
    timeout: Duration,
) -> Result<()> {
    let arguments = at_arguments(command, expected, timeout_frames)?;
    let outcome = qusb2snes::mailbox_command_with_arguments(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
        &arguments,
        timeout,
    )
    .await?;
    ensure!(
        outcome.result == expected as u16,
        "unexpected NDM24 result {}",
        outcome.result
    );
    Ok(())
}

async fn restore(websocket: &str, labels: &Path, peer: &mut PeerModem) -> Result<()> {
    peer.set_dtr(false)?;
    tokio::time::sleep(Duration::from_millis(750)).await;
    peer.set_dtr(true)?;
    tokio::time::sleep(Duration::from_secs(2)).await;
    peer.command("ATZ", Duration::from_secs(5))?;
    if wait_for_driver_state(
        websocket,
        labels,
        DriverState::Ready,
        Duration::from_secs(8),
    )
    .await
    .is_err()
    {
        qusb2snes::mailbox_command(
            websocket,
            labels,
            ndm24_protocol::MODEM_MAILBOX_COMMAND_INITIALIZE,
            Duration::from_secs(5),
        )
        .await?;
        wait_for_driver_state(
            websocket,
            labels,
            DriverState::Ready,
            Duration::from_secs(12),
        )
        .await?;
    }
    for command in ["AT&F", "ATM0", "AT%B2400"] {
        run_at(
            websocket,
            labels,
            command.as_bytes(),
            MODEM_SESSION_RESULT_OK,
            SETUP_TIMEOUT_FRAMES,
            Duration::from_secs(15),
        )
        .await
        .with_context(|| format!("restore NDM24 with {command}"))?;
    }
    Ok(())
}

async fn wait_for_driver_state(
    websocket: &str,
    labels: &Path,
    expected: DriverState,
    timeout: Duration,
) -> Result<()> {
    let deadline = Instant::now() + timeout;
    loop {
        let snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
        if snapshot.driver_state == expected {
            return Ok(());
        }
        ensure!(
            Instant::now() < deadline,
            "timed out waiting for SFC modem state {expected:?}; observed {:?}",
            snapshot.driver_state
        );
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
}

fn carrier(speed: u32) -> Result<&'static str> {
    match speed {
        2_400 => Ok("V22B"),
        4_800 | 9_600 => Ok("V32"),
        7_200 | 12_000 | 14_400 => Ok("V32B"),
        _ => bail!("unsupported test speed {speed}"),
    }
}

fn transfer_timeout(speed: u32, length: u32) -> Duration {
    Duration::from_secs_f64((length as f64 * 40.0 / speed as f64 + 20.0).max(30.0))
}

fn validate_throughput(speed: u32, length: u32, elapsed: f64) -> Result<()> {
    let payload_rate = length as f64 * 8.0 / elapsed;
    ensure!(
        payload_rate >= speed as f64 * 0.25 && payload_rate <= speed as f64 * 1.05,
        "measured payload throughput {payload_rate:.1} bit/s is inconsistent with {speed} bit/s"
    );
    Ok(())
}

fn read_exact_timeout(
    port: &mut dyn serialport::SerialPort,
    length: u32,
    timeout: Duration,
) -> Result<Vec<u8>> {
    let deadline = Instant::now() + timeout;
    let mut data = Vec::with_capacity(length as usize);
    let mut buffer = [0u8; 512];
    while data.len() < length as usize && Instant::now() < deadline {
        let remaining = length as usize - data.len();
        let chunk_length = remaining.min(buffer.len());
        match port.read(&mut buffer[..chunk_length]) {
            Ok(0) => {}
            Ok(count) => data.extend_from_slice(&buffer[..count]),
            Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {}
            Err(error) => return Err(error.into()),
        }
    }
    ensure!(
        data.len() == length as usize,
        "peer received {} of {length} bytes",
        data.len()
    );
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_modulation_mapping_covers_the_ladder() {
        assert_eq!(carrier(2_400).unwrap(), "V22B");
        assert_eq!(carrier(4_800).unwrap(), "V32");
        assert_eq!(carrier(7_200).unwrap(), "V32B");
        assert_eq!(carrier(9_600).unwrap(), "V32");
        assert_eq!(carrier(12_000).unwrap(), "V32B");
        assert_eq!(carrier(14_400).unwrap(), "V32B");
        assert!(carrier(19_200).is_err());
    }

    #[test]
    fn transfer_timeout_scales_with_data_and_speed() {
        assert!(transfer_timeout(2_400, 65_536) > transfer_timeout(14_400, 65_536));
        assert!(transfer_timeout(14_400, 65_536) > transfer_timeout(14_400, 4_096));
    }
}
