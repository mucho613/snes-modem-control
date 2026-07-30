use std::io::{self, Write};
use std::net::Ipv4Addr;
use std::path::Path;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use ndm24_protocol::{
    DriverState, MODEM_MAILBOX_COMMAND_PAP_CREDENTIALS_CLEAR, MODEM_MAILBOX_COMMAND_PPP_OPEN,
    MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START, MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP,
    MODEM_SESSION_RESULT_CONNECT, MODEM_SESSION_RESULT_OK,
};

use crate::credentials::PapCredentials;
use crate::{ppp_dial, qusb2snes};

const ACCESS_NUMBER: &str = "0570077705";
const DNS_TEST_NAME: &str = "example.com";
const TOTAL_CALL_WORKFLOW_LIMIT: Duration = Duration::from_secs(105);
const HOLD_LIMIT: Duration = Duration::from_secs(10 * 60);
const CLEANUP_LIMIT: Duration = Duration::from_secs(15);
const SETUP_TIMEOUT: Duration = Duration::from_secs(15);
const DIAL_TIMEOUT: Duration = Duration::from_secs(60);
const NETWORK_TIMEOUT: Duration = Duration::from_secs(30);
const DNS_TIMEOUT: Duration = Duration::from_secs(20);

const SETUP_COMMANDS: [&str; 5] = ["AT&F", "ATM0", "AT%B2400", "ATS7=60", "ATX4"];

pub(crate) async fn run(websocket: &str, labels: &Path, hold: bool) -> Result<()> {
    confirm_charged_call()?;
    let credentials = PapCredentials::prompt()?;

    let workflow_limit = if hold {
        TOTAL_CALL_WORKFLOW_LIMIT + HOLD_LIMIT
    } else {
        TOTAL_CALL_WORKFLOW_LIMIT
    };
    let workflow = run_once(websocket, labels, &credentials, hold);
    let result = tokio::time::timeout(workflow_limit, workflow).await;

    let cleanup = tokio::time::timeout(CLEANUP_LIMIT, cleanup(websocket, labels)).await;
    match cleanup {
        Ok(Ok(())) => {}
        Ok(Err(error)) => eprintln!("WARNING: post-call cleanup failed: {error:#}"),
        Err(_) => eprintln!(
            "WARNING: post-call cleanup exceeded 15 seconds; verify that NDM24 is on-hook"
        ),
    }

    match result {
        Ok(result) => result,
        Err(_) => bail!(
            "Nifty call workflow exceeded {} seconds and was cancelled; verify that NDM24 is on-hook",
            workflow_limit.as_secs()
        ),
    }
}

async fn run_once(
    websocket: &str,
    labels: &Path,
    credentials: &PapCredentials,
    hold: bool,
) -> Result<()> {
    let initial = qusb2snes::read_snapshot(websocket, labels).await?;
    ensure!(
        initial.driver_state == DriverState::Ready,
        "SFC Modem driver is {:?}, expected Ready",
        initial.driver_state
    );

    for command in SETUP_COMMANDS {
        ppp_dial::transact(
            websocket,
            labels,
            command,
            MODEM_SESSION_RESULT_OK,
            ppp_dial::SETUP_TIMEOUT_FRAMES,
            SETUP_TIMEOUT,
        )
        .await
        .with_context(|| format!("configure NDM24 with {command}"))?;
        println!("{command}: OK");
    }

    credentials
        .upload(websocket, labels, SETUP_TIMEOUT)
        .await
        .context("stage transient PPP authentication credentials")?;
    println!("PPP authentication credentials staged in transient WRAM");

    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_PPP_OPEN,
        SETUP_TIMEOUT,
    )
    .await
    .context("enable local LCP establishment")?;
    qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START,
        SETUP_TIMEOUT,
    )
    .await
    .context("enable PPP receive")?;

    let dial = format!("ATDT{ACCESS_NUMBER}");
    ppp_dial::transact(
        websocket,
        labels,
        &dial,
        MODEM_SESSION_RESULT_CONNECT,
        ppp_dial::DIAL_TIMEOUT_FRAMES,
        DIAL_TIMEOUT,
    )
    .await
    .context("dial Nifty access point")?;
    println!("Nifty access point: CONNECT");

    let snapshot = qusb2snes::wait_ppp_network_opened(websocket, labels, NETWORK_TIMEOUT).await?;
    let resolver = snapshot.ipcp_primary_dns_address;
    ensure!(
        resolver != [0, 0, 0, 0],
        "IPCP opened without a primary DNS address"
    );
    let authentication = if snapshot.lcp_peer_flags & 0x10 != 0 {
        "CHAP-MD5"
    } else {
        "PAP"
    };
    println!(
        "PPP opened with {authentication}; primary DNS {}",
        Ipv4Addr::from(resolver)
    );

    let dns = qusb2snes::dns_query(websocket, labels, resolver, DNS_TEST_NAME, DNS_TIMEOUT)
        .await
        .context("perform the single permitted DNS A query")?;
    println!(
        "DNS A {} = {}",
        DNS_TEST_NAME,
        Ipv4Addr::from(dns.dns_answer_address)
    );
    if hold {
        hold_connection().await?;
    }
    Ok(())
}

async fn hold_connection() -> Result<()> {
    println!(
        "Nifty connection held for experiments (maximum {} minutes).",
        HOLD_LIMIT.as_secs() / 60
    );
    println!("Run DNS, ICMP, or monitor commands in another terminal.");
    print!("Press Enter here or Ctrl+C to disconnect: ");
    io::stdout().flush().context("flush Nifty hold prompt")?;

    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut input = String::new();
        let result = io::stdin()
            .read_line(&mut input)
            .context("read Nifty hold prompt");
        let _ = sender.send(result);
    });

    let interrupt = tokio::signal::ctrl_c();
    tokio::pin!(interrupt);
    let deadline = tokio::time::Instant::now() + HOLD_LIMIT;
    loop {
        tokio::select! {
            result = &mut interrupt => {
                result.context("wait for Ctrl+C during Nifty hold")?;
                println!();
                println!("Ctrl+C received; disconnecting.");
                return Ok(());
            }
            _ = tokio::time::sleep(Duration::from_millis(100)) => {
                match receiver.try_recv() {
                    Ok(result) => {
                        result?;
                        println!("Disconnect requested.");
                        return Ok(());
                    }
                    Err(mpsc::TryRecvError::Disconnected) => {
                        bail!("Nifty hold input thread stopped unexpectedly");
                    }
                    Err(mpsc::TryRecvError::Empty) => {}
                }
                if tokio::time::Instant::now() >= deadline {
                    println!();
                    println!(
                        "Nifty hold safety limit of {} minutes reached; disconnecting.",
                        HOLD_LIMIT.as_secs() / 60
                    );
                    return Ok(());
                }
            }
        }
    }
}

async fn cleanup(websocket: &str, labels: &Path) -> Result<()> {
    let clear = qusb2snes::mailbox_command_with_arguments(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_PAP_CREDENTIALS_CLEAR,
        &[],
        Duration::from_secs(3),
    )
    .await;
    let close = qusb2snes::ppp_close(websocket, labels, Duration::from_secs(8)).await;
    if let Err(error) = &close {
        eprintln!("WARNING: graceful PPP close failed: {error:#}");
    }
    let stop = qusb2snes::mailbox_command(
        websocket,
        labels,
        MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP,
        Duration::from_secs(3),
    )
    .await;
    clear?;
    close?;
    stop?;
    Ok(())
}

fn confirm_charged_call() -> Result<()> {
    eprintln!(
        "WARNING: this makes one charged PSTN call to Nifty 0570-077-705. \
         There is no automatic redial."
    );
    print!("Type DIAL to continue: ");
    io::stdout()
        .flush()
        .context("flush call confirmation prompt")?;
    let mut confirmation = String::new();
    io::stdin()
        .read_line(&mut confirmation)
        .context("read call confirmation")?;
    ensure!(
        confirmation.trim_end_matches(['\r', '\n']) == "DIAL",
        "charged call cancelled"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_official_number_and_tone_detection() {
        assert_eq!(ACCESS_NUMBER, "0570077705");
        assert_eq!(SETUP_COMMANDS.last(), Some(&"ATX4"));
        assert!(!SETUP_COMMANDS.contains(&"ATX3"));
    }

    #[test]
    fn workflow_is_single_attempt_and_bounded() {
        assert_eq!(SETUP_COMMANDS[1], "ATM0");
        assert_eq!(DIAL_TIMEOUT, Duration::from_secs(60));
        assert_eq!(TOTAL_CALL_WORKFLOW_LIMIT, Duration::from_secs(105));
        assert_eq!(HOLD_LIMIT, Duration::from_secs(600));
        assert_eq!(
            TOTAL_CALL_WORKFLOW_LIMIT + CLEANUP_LIMIT,
            Duration::from_secs(120)
        );
        assert_eq!(
            TOTAL_CALL_WORKFLOW_LIMIT + HOLD_LIMIT + CLEANUP_LIMIT,
            Duration::from_secs(720)
        );
    }
}
