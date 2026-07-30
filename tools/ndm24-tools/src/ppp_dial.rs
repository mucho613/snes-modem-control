use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use ndm24_protocol::{
    DriverState, MODEM_MAILBOX_COMMAND_AT_TRANSACTION, MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START,
    MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP, MODEM_SESSION_RESULT_CONNECT, MODEM_SESSION_RESULT_OK,
};

use crate::connect_test::{NDM24_SETUP_COMMANDS, at_arguments};
use crate::qusb2snes;

pub(crate) const SETUP_TIMEOUT_FRAMES: u16 = 300;
pub(crate) const DIAL_TIMEOUT_FRAMES: u16 = 3_900;

pub async fn run(
    websocket: &str,
    labels: &Path,
    setup_timeout: Duration,
    dial_timeout: Duration,
) -> Result<()> {
    let initial = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        initial.driver_state == DriverState::Ready,
        "SFC Modem driver is {:?}, expected Ready",
        initial.driver_state
    );

    for command in NDM24_SETUP_COMMANDS {
        transact(
            websocket,
            labels,
            command,
            MODEM_SESSION_RESULT_OK,
            SETUP_TIMEOUT_FRAMES,
            setup_timeout,
        )
        .await
        .with_context(|| format!("configure NDM24 with {command}"))?;
        println!("{command}: OK");
    }

    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START,
        setup_timeout,
    )
    .await
    .context("enable PPP receive before dialing")?;

    let dial_result = transact(
        websocket,
        labels,
        "ATDT0",
        MODEM_SESSION_RESULT_CONNECT,
        DIAL_TIMEOUT_FRAMES,
        dial_timeout,
    )
    .await;

    if let Err(error) = dial_result {
        let cleanup = qusb2snes::mailbox_command(
            websocket,
            labels,
            MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP,
            setup_timeout,
        )
        .await;
        return match cleanup {
            Ok(()) => Err(error).context("dial NDM24; PPP receive was stopped"),
            Err(cleanup_error) => Err(error).context(format!(
                "dial NDM24; stopping PPP receive also failed: {cleanup_error:#}"
            )),
        };
    }

    println!("ATDT0: CONNECT");
    Ok(())
}

async fn transact(
    websocket: &str,
    labels: &Path,
    command: &str,
    expected_result: u8,
    timeout_frames: u16,
    host_timeout: Duration,
) -> Result<()> {
    let arguments = at_arguments(command.as_bytes(), expected_result, timeout_frames)?;
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
        "NDM24 returned result {}, expected {}",
        outcome.result,
        expected_result
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_hardware_tested_timeouts() {
        assert_eq!(SETUP_TIMEOUT_FRAMES, 300);
        assert_eq!(DIAL_TIMEOUT_FRAMES, 3_900);
    }

    #[test]
    fn setup_sequence_restores_speaker_setting_after_factory_defaults() {
        assert_eq!(
            NDM24_SETUP_COMMANDS,
            ["AT&F", "ATM0", "AT%B2400", "ATS7=60", "ATX3"]
        );
    }
}
