mod labels;
mod peer;
mod qusb2snes;
mod trace;

use std::path::PathBuf;
use std::time::Duration;

use anyhow::Result;
use clap::{Parser, Subcommand, ValueEnum};
use ndm24_protocol::{
    MODEM_MAILBOX_COMMAND_CLEAR_TRACE, MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
    MODEM_MAILBOX_COMMAND_INITIALIZE, MODEM_MAILBOX_COMMAND_QUICK_TEST,
    MODEM_MAILBOX_COMMAND_RESUME_TRACE,
};

#[derive(Debug, Parser)]
#[command(about = "NDM24 hardware, QUsb2Snes, and trace test tools")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
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
enum MailboxCommand {
    Initialize,
    QuickTest,
    ClearTrace,
    FreezeTrace,
    ResumeTrace,
}

impl MailboxCommand {
    fn value(self) -> u8 {
        match self {
            Self::Initialize => MODEM_MAILBOX_COMMAND_INITIALIZE,
            Self::QuickTest => MODEM_MAILBOX_COMMAND_QUICK_TEST,
            Self::ClearTrace => MODEM_MAILBOX_COMMAND_CLEAR_TRACE,
            Self::FreezeTrace => MODEM_MAILBOX_COMMAND_FREEZE_TRACE,
            Self::ResumeTrace => MODEM_MAILBOX_COMMAND_RESUME_TRACE,
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    match Cli::parse().command {
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
