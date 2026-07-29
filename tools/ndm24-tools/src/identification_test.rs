use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, ensure};
use ndm24_protocol::{
    DiagnosticSnapshot, DriverState, MODEM_FLAG_RX_OVERFLOW, MODEM_FLAG_TIMEOUT,
    MODEM_FLAG_TX_OVERFLOW, MODEM_MAILBOX_ARGUMENT_SIZE, MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
    MODEM_MAILBOX_COMMAND_BINARY_RECEIVE, MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
    MODEM_MAILBOX_COMMAND_FREEZE_TRACE, MODEM_MAILBOX_COMMAND_RESUME_TRACE,
    MODEM_SESSION_RESULT_BUSY, MODEM_SESSION_RESULT_CONNECT, MODEM_SESSION_RESULT_ERROR,
    MODEM_SESSION_RESULT_NO_CARRIER, MODEM_SESSION_RESULT_NO_DIALTONE, MODEM_SESSION_RESULT_OK,
    MODEM_TRACE_RX_ACCEPTED, TraceEvent,
};
use serde::Serialize;

use crate::connect_test::at_arguments;
use crate::qusb2snes;

const QUERY_TIMEOUT_FRAMES: u16 = 600;
const HOST_TIMEOUT: Duration = Duration::from_secs(15);
const BINARY_CHUNK_MAX_LENGTH: usize = MODEM_MAILBOX_ARGUMENT_SIZE - 1;
const IDENTIFICATION_COMMANDS: &[&str] = &[
    "ATI", "ATI0", "ATI1", "ATI2", "ATI3", "ATI4", "ATI5", "ATI6", "ATI7", "ATI8", "ATI9",
    "AT+GMI", "AT+GMM", "AT+GMR", "AT+GSN", "AT+GCAP",
];

#[derive(Debug, Serialize)]
struct IdentificationReport {
    schema_version: u8,
    test_id: String,
    started_unix_seconds: u64,
    hardware_revision: String,
    passed: bool,
    failure: Option<String>,
    failure_capture: Option<IdentificationFailureCapture>,
    commands: Vec<IdentificationRecord>,
    initial_snapshot: DiagnosticSnapshot,
    final_snapshot: Option<DiagnosticSnapshot>,
}

#[derive(Debug, Serialize)]
struct IdentificationFailureCapture {
    command: String,
    error: String,
    snapshot_before: DiagnosticSnapshot,
    snapshot_after: Option<DiagnosticSnapshot>,
    rx_accepted_delta: Option<u32>,
    tx_bytes_delta: Option<u32>,
    raw_response_from_available_trace: Vec<u8>,
    pending_rx: Vec<u8>,
    trace: Vec<TraceEvent>,
}

#[derive(Debug, Serialize)]
struct IdentificationRecord {
    command: String,
    result: u16,
    result_name: String,
    raw_response: Vec<u8>,
    lines: Vec<String>,
    information_lines: Vec<String>,
    rx_discarded_before: u32,
    rx_discarded_after: u32,
    poll_budget_yield_before: u32,
    poll_budget_yield_after: u32,
    trace_overwritten: u32,
    pending_rx_after_quiet: Vec<u8>,
    trace: Vec<TraceEvent>,
}

pub async fn run(
    websocket: &str,
    labels: &Path,
    hardware_revision: &str,
    output_root: &Path,
) -> Result<PathBuf> {
    let started_unix_seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_secs();
    let revision_slug = hardware_revision
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>();
    let test_id = format!("unix-{started_unix_seconds}-revision-{revision_slug}-identification");
    let output_dir = output_root.join(&test_id);
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("create test output {}", output_dir.display()))?;

    let initial_snapshot = qusb2snes::read_snapshot(websocket, labels).await?;
    validate_ready_snapshot(&initial_snapshot)?;

    let mut commands = Vec::with_capacity(IDENTIFICATION_COMMANDS.len());
    let mut failure = None;
    let mut failure_capture = None;
    for command in IDENTIFICATION_COMMANDS {
        qusb2snes::mailbox_command(
            websocket,
            labels,
            MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
            Duration::from_secs(5),
        )
        .await?;
        let before = qusb2snes::read_snapshot(websocket, labels).await?;
        match transact(websocket, labels, command, &before).await {
            Ok(record) => commands.push(record),
            Err(error) => {
                let error = format!("{error:#}");
                failure = Some(format!("{command}: {error}"));
                failure_capture =
                    Some(capture_failed_command(websocket, labels, command, error, before).await);
                break;
            }
        }
    }

    let final_snapshot = qusb2snes::read_snapshot(websocket, labels).await.ok();
    if failure.is_none() {
        failure = match final_snapshot.as_ref() {
            Some(snapshot) => validate_ready_snapshot(snapshot)
                .err()
                .map(|error| format!("final validation: {error:#}")),
            None => Some("final validation: could not read final diagnostic snapshot".to_owned()),
        };
    }
    let report = IdentificationReport {
        schema_version: 3,
        test_id,
        started_unix_seconds,
        hardware_revision: hardware_revision.to_owned(),
        passed: failure.is_none(),
        failure: failure.clone(),
        failure_capture,
        commands,
        initial_snapshot,
        final_snapshot,
    };
    let report_path = output_dir.join("at-identification.json");
    fs::write(&report_path, serde_json::to_vec_pretty(&report)?)
        .with_context(|| format!("write identification report {}", report_path.display()))?;
    Ok(report_path)
}

async fn transact(
    websocket: &str,
    labels: &Path,
    command: &str,
    before: &DiagnosticSnapshot,
) -> Result<IdentificationRecord> {
    let arguments = at_arguments(command.as_bytes(), 0, QUERY_TIMEOUT_FRAMES)?;
    let outcome = qusb2snes::mailbox_command_with_arguments(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
        &arguments,
        HOST_TIMEOUT,
    )
    .await
    .with_context(|| format!("query NDM24 with {command}"))?;

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
    tokio::time::sleep(Duration::from_millis(100)).await;
    let pending_rx_after_quiet = qusb2snes::read_pending_rx(websocket, labels).await?;

    ensure!(
        snapshot.driver_state == DriverState::Ready,
        "{command} left the driver in {:?}",
        snapshot.driver_state
    );
    ensure!(
        snapshot.rx_discarded == before.rx_discarded,
        "{command} discarded received bytes"
    );
    ensure!(
        snapshot.trace_overwritten == 0,
        "{command} response exceeded trace capacity"
    );

    let mut raw_response = accepted_bytes(&trace);
    let pending_at_freeze = snapshot.rx_used() as usize;
    ensure!(
        pending_at_freeze <= pending_rx_after_quiet.len(),
        "{command} RX ring shrank after trace freeze"
    );
    raw_response.extend_from_slice(&pending_rx_after_quiet[pending_at_freeze..]);
    let drained = drain_pending_rx(websocket, labels, pending_rx_after_quiet.len()).await?;
    ensure!(
        drained == pending_rx_after_quiet,
        "{command} trailing RX drain did not match the observed ring"
    );
    let lines = response_lines(&raw_response);
    let terminal_result = result_name(outcome.result);
    let mut information_lines = lines.clone();
    if information_lines
        .first()
        .is_some_and(|line| line.eq_ignore_ascii_case(command))
    {
        information_lines.remove(0);
    }
    if information_lines
        .last()
        .is_some_and(|line| line.eq_ignore_ascii_case(terminal_result))
    {
        information_lines.pop();
    }

    Ok(IdentificationRecord {
        command: command.to_owned(),
        result: outcome.result,
        result_name: terminal_result.to_owned(),
        raw_response,
        lines,
        information_lines,
        rx_discarded_before: before.rx_discarded,
        rx_discarded_after: snapshot.rx_discarded,
        poll_budget_yield_before: before.poll_budget_yield,
        poll_budget_yield_after: snapshot.poll_budget_yield,
        trace_overwritten: snapshot.trace_overwritten,
        pending_rx_after_quiet,
        trace,
    })
}

async fn capture_failed_command(
    websocket: &str,
    labels: &Path,
    command: &str,
    error: String,
    snapshot_before: DiagnosticSnapshot,
) -> IdentificationFailureCapture {
    let _ = qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
        Duration::from_secs(5),
    )
    .await;
    let trace = qusb2snes::read_trace_events(websocket, labels)
        .await
        .unwrap_or_default();
    let pending_rx = qusb2snes::read_pending_rx(websocket, labels)
        .await
        .unwrap_or_default();
    let snapshot_after = qusb2snes::read_snapshot(websocket, labels).await.ok();
    let rx_accepted_delta = snapshot_after
        .as_ref()
        .map(|after| after.rx_accepted.wrapping_sub(snapshot_before.rx_accepted));
    let tx_bytes_delta = snapshot_after
        .as_ref()
        .map(|after| after.tx_bytes.wrapping_sub(snapshot_before.tx_bytes));

    IdentificationFailureCapture {
        command: command.to_owned(),
        error,
        snapshot_before,
        snapshot_after,
        rx_accepted_delta,
        tx_bytes_delta,
        raw_response_from_available_trace: accepted_bytes(&trace),
        pending_rx,
        trace,
    }
}

async fn drain_pending_rx(websocket: &str, labels: &Path, length: usize) -> Result<Vec<u8>> {
    let mut data = Vec::with_capacity(length);
    while data.len() < length {
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
            "SFC returned invalid trailing RX length {count}"
        );
        ensure!(count != 0, "SFC trailing RX drain stopped early");
        data.extend_from_slice(&outcome.output[..count]);
        ensure!(
            data.len() <= length,
            "SFC trailing RX drain returned too many bytes"
        );
    }
    Ok(data)
}

fn accepted_bytes(trace: &[TraceEvent]) -> Vec<u8> {
    trace
        .iter()
        .filter(|event| event.kind == MODEM_TRACE_RX_ACCEPTED)
        .map(|event| (event.data_report >> 8) as u8)
        .collect()
}

fn response_lines(raw: &[u8]) -> Vec<String> {
    raw.split(|byte| *byte == b'\r' || *byte == b'\n')
        .filter(|line| !line.is_empty())
        .map(|line| String::from_utf8_lossy(line).to_string())
        .collect()
}

fn result_name(result: u16) -> &'static str {
    match result as u8 {
        MODEM_SESSION_RESULT_OK => "OK",
        MODEM_SESSION_RESULT_ERROR => "ERROR",
        MODEM_SESSION_RESULT_CONNECT => "CONNECT",
        MODEM_SESSION_RESULT_NO_CARRIER => "NO CARRIER",
        MODEM_SESSION_RESULT_BUSY => "BUSY",
        MODEM_SESSION_RESULT_NO_DIALTONE => "NO DIALTONE",
        _ => "UNKNOWN",
    }
}

fn validate_ready_snapshot(snapshot: &DiagnosticSnapshot) -> Result<()> {
    let fatal_flags = MODEM_FLAG_RX_OVERFLOW | MODEM_FLAG_TX_OVERFLOW | MODEM_FLAG_TIMEOUT;
    ensure!(
        snapshot.driver_state == DriverState::Ready,
        "SFC modem driver is {:?}, expected Ready",
        snapshot.driver_state
    );
    ensure!(snapshot.last_error == 0, "SFC last_error is non-zero");
    ensure!(
        snapshot.flags & fatal_flags == 0,
        "SFC driver has fatal flags 0x{:02x}",
        snapshot.flags & fatal_flags
    );
    ensure!(
        snapshot.rx_read_index == snapshot.rx_write_index,
        "SFC RX ring is not empty"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconstructs_accepted_trace_bytes() {
        let trace = [
            TraceEvent {
                sequence: 0,
                frame: 0,
                kind: MODEM_TRACE_RX_ACCEPTED,
                state: 0,
                reason: 0,
                flags: 0,
                data_report: 0x4183,
                status_report: 0,
            },
            TraceEvent {
                sequence: 1,
                frame: 0,
                kind: 1,
                state: 0,
                reason: 0,
                flags: 0,
                data_report: 0x0080,
                status_report: 0,
            },
        ];
        assert_eq!(accepted_bytes(&trace), b"A");
    }

    #[test]
    fn splits_cr_lf_response_lines() {
        assert_eq!(
            response_lines(b"ATI\r\r\nNDM24\r\nOK\r\n"),
            ["ATI", "NDM24", "OK"]
        );
    }
}
