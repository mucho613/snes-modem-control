use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, ensure};
use ndm24_protocol::{
    DiagnosticSnapshot, DriverState, MODEM_MAILBOX_COMMAND_CLEAR_TRACE, MODEM_SESSION_RESULT_OK,
};
use serde::Serialize;

use crate::connect_test::{normalize_hardware_revision, restore_peer};
use crate::identification_test::{self, IdentificationRecord};
use crate::peer::{PeerModem, PeerResponse};
use crate::qusb2snes;

const DTE_BAUD: u32 = 115_200;
const SPEEDS: [u32; 6] = [2_400, 4_800, 7_200, 9_600, 12_000, 14_400];
const NDM24_PREFIX_COMMANDS: [&str; 2] = ["AT&F", "ATM0"];
const NDM24_MODE_COMMANDS: [&str; 2] = ["AT%C0", "AT\\N3"];
const NDM24_RESTORE_COMMANDS: [&str; 3] = ["AT&F", "ATM0", "AT%B2400"];
const PEER_QUERY_COMMANDS: [&str; 5] = ["ATI", "ATI3", "AT+MS=?", "AT+MS?", "AT+GCAP"];

#[derive(Debug, Serialize)]
struct SpeedProbeReport {
    schema_version: u8,
    test_id: String,
    started_unix_seconds: u64,
    hardware_revision: String,
    peer_model: String,
    peer_port: String,
    dte_baud: u32,
    passed: bool,
    failure: Option<String>,
    candidate_speeds_bps: Vec<u32>,
    accepted_speeds_bps: Vec<u32>,
    peer_responses: Vec<PeerResponse>,
    peer_transcript: Vec<String>,
    ndm24_commands: Vec<IdentificationRecord>,
    initial_snapshot: Option<DiagnosticSnapshot>,
    final_snapshot: Option<DiagnosticSnapshot>,
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
    let test_id = format!("unix-{started_unix_seconds}-revision-{revision_slug}-speed-probe");
    let output_dir = output_root.join(&test_id);
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("create test output {}", output_dir.display()))?;

    let mut report = SpeedProbeReport {
        schema_version: 1,
        test_id,
        started_unix_seconds,
        hardware_revision: revision_label,
        peer_model: "I-O DATA DFM-56U / Conexant CX93001".to_owned(),
        peer_port: port_name.to_owned(),
        dte_baud: DTE_BAUD,
        passed: false,
        failure: None,
        candidate_speeds_bps: SPEEDS.to_vec(),
        accepted_speeds_bps: Vec::new(),
        peer_responses: Vec::new(),
        peer_transcript: Vec::new(),
        ndm24_commands: Vec::new(),
        initial_snapshot: None,
        final_snapshot: None,
    };

    let mut peer = PeerModem::open(port_name, DTE_BAUD)?;
    let test_result = run_probe(websocket, labels, &mut peer, &mut report).await;
    let ndm24_restore_result = restore_ndm24(websocket, labels, &mut report).await;
    let peer_restore_result = restore_peer(&mut peer);
    report.peer_transcript = peer.transcript().to_vec();
    report.final_snapshot = qusb2snes::read_snapshot(websocket, labels).await.ok();

    if let Err(error) = &test_result {
        report.failure = Some(format!("{error:#}"));
    } else if let Err(error) = &ndm24_restore_result {
        report.failure = Some(format!("probe passed but NDM24 restore failed: {error:#}"));
    } else if let Err(error) = &peer_restore_result {
        report.failure = Some(format!("probe passed but peer restore failed: {error:#}"));
    } else {
        report.passed = true;
    }

    let report_path = output_dir.join("speed-probe.json");
    fs::write(&report_path, serde_json::to_vec_pretty(&report)?)
        .with_context(|| format!("write speed probe report {}", report_path.display()))?;

    test_result?;
    ndm24_restore_result?;
    peer_restore_result?;
    ensure!(report.passed, "speed capability probe did not pass");
    Ok(report_path)
}

async fn run_probe(
    websocket: &str,
    labels: &Path,
    peer: &mut PeerModem,
    report: &mut SpeedProbeReport,
) -> Result<()> {
    peer.command("ATZ", Duration::from_secs(5))?;
    peer.command("ATE0", Duration::from_secs(5))?;
    for command in PEER_QUERY_COMMANDS {
        report
            .peer_responses
            .push(peer.query(command, Duration::from_secs(5))?);
    }

    let initial = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        initial.driver_state == DriverState::Ready,
        "SFC modem driver is {:?}, expected Ready",
        initial.driver_state
    );
    report.initial_snapshot = Some(initial);

    for command in NDM24_PREFIX_COMMANDS {
        probe_ndm24_command(websocket, labels, command, report).await?;
        ensure!(
            report.ndm24_commands.last().unwrap().result == MODEM_SESSION_RESULT_OK as u16,
            "required NDM24 command {command} was rejected"
        );
    }
    for speed in SPEEDS {
        let command = format!("AT%B{speed}");
        probe_ndm24_command(websocket, labels, &command, report).await?;
        if report.ndm24_commands.last().unwrap().result == MODEM_SESSION_RESULT_OK as u16 {
            report.accepted_speeds_bps.push(speed);
        }
    }
    for command in NDM24_MODE_COMMANDS {
        probe_ndm24_command(websocket, labels, command, report).await?;
    }
    Ok(())
}

async fn restore_ndm24(
    websocket: &str,
    labels: &Path,
    report: &mut SpeedProbeReport,
) -> Result<()> {
    for command in NDM24_RESTORE_COMMANDS {
        probe_ndm24_command(websocket, labels, command, report)
            .await
            .with_context(|| format!("restore NDM24 with {command}"))?;
        ensure!(
            report.ndm24_commands.last().unwrap().result == MODEM_SESSION_RESULT_OK as u16,
            "NDM24 restore command {command} was rejected"
        );
    }
    Ok(())
}

async fn probe_ndm24_command(
    websocket: &str,
    labels: &Path,
    command: &str,
    report: &mut SpeedProbeReport,
) -> Result<()> {
    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
        Duration::from_secs(5),
    )
    .await?;
    let before = qusb2snes::read_snapshot(websocket, labels).await?;
    let record = identification_test::transact(websocket, labels, command, &before).await?;
    report.ndm24_commands.push(record);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probes_full_v32bis_speed_ladder() {
        assert_eq!(SPEEDS, [2_400, 4_800, 7_200, 9_600, 12_000, 14_400]);
    }

    #[test]
    fn restore_is_non_persistent_and_returns_to_2400() {
        assert_eq!(NDM24_RESTORE_COMMANDS, ["AT&F", "ATM0", "AT%B2400"]);
        assert!(
            NDM24_RESTORE_COMMANDS
                .iter()
                .all(|command| !command.contains("&W"))
        );
    }
}
