mod binary_test;
mod connect_test;
mod identification_test;
mod labels;
mod peer;
mod ppp_dial;
mod qusb2snes;
mod trace;

use std::net::Ipv4Addr;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Result, ensure};
use clap::{Parser, Subcommand, ValueEnum};
use ndm24_protocol::{
    MODEM_MAILBOX_COMMAND_AT_TRANSACTION, MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
    MODEM_MAILBOX_COMMAND_FREEZE_TRACE, MODEM_MAILBOX_COMMAND_ICMP_ECHO_REQUEST,
    MODEM_MAILBOX_COMMAND_INITIALIZE, MODEM_MAILBOX_COMMAND_NTP_REQUEST,
    MODEM_MAILBOX_COMMAND_PPP_CLOSE, MODEM_MAILBOX_COMMAND_PPP_OPEN,
    MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START, MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP,
    MODEM_MAILBOX_COMMAND_PPP_SELF_TEST, MODEM_MAILBOX_COMMAND_QUICK_TEST,
    MODEM_MAILBOX_COMMAND_RESUME_TRACE, MODEM_SESSION_RESULT_CONNECT,
    MODEM_SESSION_RESULT_NO_CARRIER, MODEM_SESSION_RESULT_OK,
};

#[derive(Debug, Parser)]
#[command(about = "NDM24 hardware, QUsb2Snes, and trace test tools")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Identify {
        #[arg(long, default_value = "B")]
        revision: String,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value = "build/hardware-tests")]
        output: PathBuf,
    },
    BinaryTest {
        #[arg(long, default_value = "B")]
        revision: String,
        #[arg(long, default_value = "COM5")]
        port: String,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value = "build/hardware-tests")]
        output: PathBuf,
    },
    ConnectTest {
        #[arg(long, default_value = "B")]
        revision: String,
        #[arg(long, default_value = "COM5")]
        port: String,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value = "build/hardware-tests")]
        output: PathBuf,
        #[arg(long, default_value_t = 10)]
        hold_seconds: u64,
    },
    At {
        command: String,
        #[arg(long, value_enum, default_value_t = AtExpectedResult::Ok)]
        expect: AtExpectedResult,
        #[arg(long, default_value_t = 300)]
        timeout_frames: u16,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 10)]
        timeout_seconds: u64,
    },
    PppDial {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 15)]
        setup_timeout_seconds: u64,
        #[arg(long, default_value_t = 75)]
        dial_timeout_seconds: u64,
    },
    PppClose {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 10)]
        timeout_seconds: u64,
    },
    PppOpen {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 30)]
        timeout_seconds: u64,
    },
    Monitor {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 250)]
        interval_ms: u64,
        #[arg(long)]
        once: bool,
    },
    PppMonitor {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 250)]
        interval_ms: u64,
        #[arg(long)]
        once: bool,
    },
    FrameRate {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 10)]
        seconds: u64,
    },
    InputMonitor {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/normal/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 50)]
        interval_ms: u64,
        #[arg(long, default_value_t = 15)]
        seconds: u64,
    },
    NtpRequest {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 20)]
        timeout_seconds: u64,
    },
    IcmpEcho {
        #[arg(default_value = "1.1.1.1")]
        address: Ipv4Addr,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 15)]
        timeout_seconds: u64,
    },
    DnsQuery {
        #[arg(default_value = "example.com")]
        name: String,
        #[arg(long, default_value = "1.1.1.1")]
        resolver: Ipv4Addr,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 20)]
        timeout_seconds: u64,
    },
    PendingRx {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
    },
    Peer {
        #[arg(long)]
        port: String,
        #[arg(long, default_value_t = 115_200)]
        baud: u32,
        #[arg(long, default_value_t = 30)]
        command_timeout_seconds: u64,
    },
    Trace {
        #[arg(value_name = "FIXTURE")]
        fixture: PathBuf,
    },
    TraceLive {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
    },
    Test {
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 60)]
        timeout_seconds: u64,
    },
    Mailbox {
        #[arg(value_enum)]
        command: MailboxCommand,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "build/smoke/modem-control.lbl")]
        labels: PathBuf,
        #[arg(long, default_value_t = 60)]
        timeout_seconds: u64,
    },
    Deploy {
        #[arg(value_name = "ROM")]
        rom: PathBuf,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "/snes-modem-control.sfc")]
        remote_path: String,
    },
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum AtExpectedResult {
    Ok,
    Connect,
    NoCarrier,
}

impl AtExpectedResult {
    fn value(self) -> u8 {
        match self {
            Self::Ok => MODEM_SESSION_RESULT_OK,
            Self::Connect => MODEM_SESSION_RESULT_CONNECT,
            Self::NoCarrier => MODEM_SESSION_RESULT_NO_CARRIER,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Ok => "OK",
            Self::Connect => "CONNECT",
            Self::NoCarrier => "NO CARRIER",
        }
    }
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum MailboxCommand {
    Initialize,
    QuickTest,
    ClearTrace,
    FreezeTrace,
    ResumeTrace,
    PppSelfTest,
    PppReceiveStart,
    PppReceiveStop,
    PppClose,
    PppOpen,
    NtpRequest,
    IcmpEchoRequest,
}

impl MailboxCommand {
    fn value(self) -> u8 {
        match self {
            Self::Initialize => MODEM_MAILBOX_COMMAND_INITIALIZE,
            Self::QuickTest => MODEM_MAILBOX_COMMAND_QUICK_TEST,
            Self::ClearTrace => MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
            Self::FreezeTrace => MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
            Self::ResumeTrace => MODEM_MAILBOX_COMMAND_RESUME_TRACE,
            Self::PppSelfTest => MODEM_MAILBOX_COMMAND_PPP_SELF_TEST,
            Self::PppReceiveStart => MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START,
            Self::PppReceiveStop => MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP,
            Self::PppClose => MODEM_MAILBOX_COMMAND_PPP_CLOSE,
            Self::PppOpen => MODEM_MAILBOX_COMMAND_PPP_OPEN,
            Self::NtpRequest => MODEM_MAILBOX_COMMAND_NTP_REQUEST,
            Self::IcmpEchoRequest => MODEM_MAILBOX_COMMAND_ICMP_ECHO_REQUEST,
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    match Cli::parse().command {
        Command::Identify {
            revision,
            websocket,
            labels,
            output,
        } => {
            let report = identification_test::run(&websocket, &labels, &revision, &output).await?;
            println!("AT identification report saved at {}", report.display());
            Ok(())
        }
        Command::BinaryTest {
            revision,
            port,
            websocket,
            labels,
            output,
        } => {
            let report = binary_test::run(&websocket, &labels, &port, &revision, &output).await?;
            println!("binary pattern test passed; report {}", report.display());
            Ok(())
        }
        Command::ConnectTest {
            revision,
            port,
            websocket,
            labels,
            output,
            hold_seconds,
        } => {
            let report =
                connect_test::run(&websocket, &labels, &port, &revision, &output, hold_seconds)
                    .await?;
            println!("connect test passed; report {}", report.display());
            Ok(())
        }
        Command::At {
            command,
            expect,
            timeout_frames,
            websocket,
            labels,
            timeout_seconds,
        } => {
            let arguments =
                connect_test::at_arguments(command.as_bytes(), expect.value(), timeout_frames)?;
            let outcome = qusb2snes::mailbox_command_with_arguments(
                &websocket,
                &labels,
                MODEM_MAILBOX_COMMAND_AT_TRANSACTION,
                &arguments,
                Duration::from_secs(timeout_seconds),
            )
            .await?;
            ensure!(
                outcome.result == expect.value() as u16,
                "NDM24 returned result {}, expected {}",
                outcome.result,
                expect.name()
            );
            let display_command = if command.is_empty() {
                "<wait>"
            } else {
                &command
            };
            println!("{display_command}: {}", expect.name());
            Ok(())
        }
        Command::PppDial {
            websocket,
            labels,
            setup_timeout_seconds,
            dial_timeout_seconds,
        } => {
            ppp_dial::run(
                &websocket,
                &labels,
                Duration::from_secs(setup_timeout_seconds),
                Duration::from_secs(dial_timeout_seconds),
            )
            .await
        }
        Command::PppClose {
            websocket,
            labels,
            timeout_seconds,
        } => {
            let snapshot =
                qusb2snes::ppp_close(&websocket, &labels, Duration::from_secs(timeout_seconds))
                    .await?;
            println!("{}", serde_json::to_string(&snapshot)?);
            println!(
                "LCP closed: local_term_requests={}, matching_acks={}, timeouts={}",
                snapshot.lcp_local_terminate_request_count,
                snapshot.lcp_local_terminate_ack_count,
                snapshot.lcp_local_terminate_timeout_count
            );
            Ok(())
        }
        Command::PppOpen {
            websocket,
            labels,
            timeout_seconds,
        } => {
            let snapshot =
                qusb2snes::ppp_open(&websocket, &labels, Duration::from_secs(timeout_seconds))
                    .await?;
            println!("{}", serde_json::to_string(&snapshot)?);
            println!("LCP opened");
            Ok(())
        }
        Command::Monitor {
            websocket,
            labels,
            interval_ms,
            once,
        } => {
            qusb2snes::monitor(
                &websocket,
                &labels,
                Duration::from_millis(interval_ms),
                once,
            )
            .await
        }
        Command::PppMonitor {
            websocket,
            labels,
            interval_ms,
            once,
        } => {
            qusb2snes::ppp_monitor(
                &websocket,
                &labels,
                Duration::from_millis(interval_ms),
                once,
            )
            .await
        }
        Command::InputMonitor {
            websocket,
            labels,
            interval_ms,
            seconds,
        } => {
            qusb2snes::input_monitor(
                &websocket,
                &labels,
                Duration::from_millis(interval_ms),
                Duration::from_secs(seconds),
            )
            .await
        }
        Command::FrameRate {
            websocket,
            labels,
            seconds,
        } => {
            let report =
                qusb2snes::measure_frame_rate(&websocket, &labels, Duration::from_secs(seconds))
                    .await?;
            println!("{}", serde_json::to_string(&report)?);
            Ok(())
        }
        Command::NtpRequest {
            websocket,
            labels,
            timeout_seconds,
        } => {
            let snapshot =
                qusb2snes::ntp_request(&websocket, &labels, Duration::from_secs(timeout_seconds))
                    .await?;
            println!("{}", serde_json::to_string(&snapshot)?);
            println!(
                "NTP response: unix_seconds={}, stratum={}, version={}",
                snapshot.ntp_unix_seconds, snapshot.ntp_stratum, snapshot.ntp_version
            );
            Ok(())
        }
        Command::IcmpEcho {
            address,
            websocket,
            labels,
            timeout_seconds,
        } => {
            let snapshot = qusb2snes::icmp_echo(
                &websocket,
                &labels,
                address.octets(),
                Duration::from_secs(timeout_seconds),
            )
            .await?;
            println!("{}", serde_json::to_string(&snapshot)?);
            println!(
                "ICMP Echo reply from {}: identifier=0x{:04x}, sequence={}, rtt_frames={}",
                address,
                snapshot.icmp_request_identifier,
                snapshot.icmp_request_sequence,
                snapshot.icmp_request_rtt_frames
            );
            Ok(())
        }
        Command::DnsQuery {
            name,
            resolver,
            websocket,
            labels,
            timeout_seconds,
        } => {
            let snapshot = qusb2snes::dns_query(
                &websocket,
                &labels,
                resolver.octets(),
                &name,
                Duration::from_secs(timeout_seconds),
            )
            .await?;
            let answer = Ipv4Addr::from(snapshot.dns_answer_address);
            println!("{}", serde_json::to_string(&snapshot)?);
            println!(
                "DNS A {name} = {answer} via {resolver}: transaction=0x{:04x}, answers={}, rtt_frames={}",
                snapshot.dns_transaction_id, snapshot.dns_answer_count, snapshot.dns_rtt_frames
            );
            Ok(())
        }
        Command::PendingRx { websocket, labels } => {
            let bytes = qusb2snes::read_pending_rx(&websocket, &labels).await?;
            println!("{}", serde_json::to_string(&bytes)?);
            Ok(())
        }
        Command::Peer {
            port,
            baud,
            command_timeout_seconds,
        } => peer::run(&port, baud, Duration::from_secs(command_timeout_seconds)),
        Command::Trace { fixture } => trace::verify_fixture(&fixture),
        Command::TraceLive { websocket, labels } => {
            qusb2snes::dump_trace(&websocket, &labels).await
        }
        Command::Test {
            websocket,
            labels,
            timeout_seconds,
        } => {
            qusb2snes::mailbox_command(
                &websocket,
                &labels,
                MODEM_MAILBOX_COMMAND_QUICK_TEST,
                Duration::from_secs(timeout_seconds),
            )
            .await
        }
        Command::Mailbox {
            command,
            websocket,
            labels,
            timeout_seconds,
        } => {
            qusb2snes::mailbox_command(
                &websocket,
                &labels,
                command.value(),
                Duration::from_secs(timeout_seconds),
            )
            .await
        }
        Command::Deploy {
            rom,
            websocket,
            remote_path,
        } => qusb2snes::upload_and_boot(&websocket, &rom, &remote_path).await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_lcp_mailbox_commands_use_distinct_generated_values() {
        assert_eq!(
            MailboxCommand::PppClose.value(),
            MODEM_MAILBOX_COMMAND_PPP_CLOSE
        );
        assert_eq!(
            MailboxCommand::PppOpen.value(),
            MODEM_MAILBOX_COMMAND_PPP_OPEN
        );
        assert_ne!(
            MODEM_MAILBOX_COMMAND_PPP_CLOSE,
            MODEM_MAILBOX_COMMAND_PPP_OPEN
        );
    }

    #[test]
    fn parses_local_lcp_control_commands() {
        assert!(matches!(
            Cli::try_parse_from(["ndm24-tools", "ppp-close"])
                .unwrap()
                .command,
            Command::PppClose { .. }
        ));
        assert!(matches!(
            Cli::try_parse_from(["ndm24-tools", "ppp-open"])
                .unwrap()
                .command,
            Command::PppOpen { .. }
        ));
    }
}
