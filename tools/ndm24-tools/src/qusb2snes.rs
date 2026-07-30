use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail, ensure};
use futures_util::{SinkExt, StreamExt};
use ndm24_protocol::{
    DiagnosticSnapshot, MODEM_DIAG_SNAPSHOT_SEQUENCE, MODEM_DIAGNOSTIC_SIZE, MODEM_MAILBOX_MAGIC,
    MODEM_MAILBOX_OFFSET_BLOCK_SIZE, MODEM_MAILBOX_OFFSET_COMMAND,
    MODEM_MAILBOX_OFFSET_HOST_SEQUENCE, MODEM_MAILBOX_OFFSET_PROCESSED_SEQUENCE,
    MODEM_MAILBOX_OFFSET_RESULT, MODEM_MAILBOX_OFFSET_STATUS, MODEM_MAILBOX_SIZE,
    MODEM_MAILBOX_STATUS_FAILED, MODEM_MAILBOX_STATUS_PASSED, MODEM_MAILBOX_VERSION,
    MODEM_RING_STORAGE_SIZE, MODEM_TRACE_EVENT_SIZE, MODEM_TRACE_SIZE, PPP_DIAG_SNAPSHOT_SEQUENCE,
    PPP_DIAGNOSTIC_SIZE, PppDiagnosticSnapshot, TraceEvent,
};
use serde::{Deserialize, Serialize};
use tokio::net::TcpStream;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream, connect_async, tungstenite::Message};

use crate::labels::{read_labels, wram_to_usb2snes};

type Socket = WebSocketStream<MaybeTlsStream<TcpStream>>;

#[derive(Debug, Serialize)]
#[serde(rename_all = "PascalCase")]
struct Request<'a> {
    opcode: &'a str,
    space: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    flags: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    operands: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct Response {
    results: Vec<String>,
}

struct Client {
    socket: Socket,
    device: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct MailboxOutcome {
    pub sequence: u32,
    pub result: u16,
    pub output: Vec<u8>,
}

#[derive(Debug, Clone, Serialize)]
pub struct FrameRateReport {
    pub elapsed_seconds: f64,
    pub start_frame: u32,
    pub end_frame: u32,
    pub frame_delta: u32,
    pub frames_per_second: f64,
    pub start_unix_seconds: u32,
    pub end_unix_seconds: u32,
    pub start_subsecond: u32,
    pub end_subsecond: u32,
    pub clock_elapsed_seconds: f64,
}

impl Client {
    async fn connect(websocket: &str) -> Result<Self> {
        let (mut socket, _) = connect_async(websocket)
            .await
            .with_context(|| format!("connect to QUsb2Snes at {websocket}"))?;
        send_request(&mut socket, "Name", vec!["snes-modem-control".to_owned()]).await?;
        let devices = tokio::time::timeout(
            Duration::from_secs(10),
            request_response(&mut socket, "DeviceList", vec![]),
        )
        .await
        .context("timed out waiting for QUsb2Snes device list")??;
        let device = devices
            .iter()
            .find(|name| {
                let upper = name.to_ascii_uppercase();
                upper.contains("SD2SNES") || upper.contains("FXPAK")
            })
            .or_else(|| devices.first())
            .context("QUsb2Snes reported no devices")?
            .clone();
        send_request(&mut socket, "Attach", vec![device.clone()]).await?;
        Ok(Self { socket, device })
    }

    async fn read_address(&mut self, offset: usize, size: usize) -> Result<Vec<u8>> {
        tokio::time::timeout(
            Duration::from_secs(10),
            read_address(&mut self.socket, offset, size),
        )
        .await
        .context("timed out reading FXPAK PRO address")?
    }

    async fn execute_address(&mut self, offset: usize, data: &[u8]) -> Result<()> {
        write_binary_request_with_flags(
            &mut self.socket,
            "PutAddress",
            offset,
            data,
            Some(vec!["SETX".to_owned()]),
        )
        .await
    }
}

const FXPAK_EXECUTION_SCRATCH: usize = 0x3f_0000;

pub async fn monitor(
    websocket: &str,
    label_path: &Path,
    interval: Duration,
    once: bool,
) -> Result<()> {
    let labels = read_labels(label_path)?;
    let state = labels
        .get("modemState")
        .copied()
        .context("label file does not contain modemState")?;
    let offset = wram_to_usb2snes(state)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);

    loop {
        let snapshot = read_stable_snapshot(&mut client, offset).await?;
        println!("{}", serde_json::to_string(&snapshot)?);
        if once {
            return Ok(());
        }
        tokio::time::sleep(interval).await;
    }
}

pub async fn ppp_monitor(
    websocket: &str,
    label_path: &Path,
    interval: Duration,
    once: bool,
) -> Result<()> {
    let labels = read_labels(label_path)?;
    let state = labels
        .get("pppDiagnosticState")
        .copied()
        .context("label file does not contain pppDiagnosticState")?;
    let offset = wram_to_usb2snes(state)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);

    loop {
        let snapshot = read_stable_ppp_snapshot(&mut client, offset).await?;
        println!("{}", serde_json::to_string(&snapshot)?);
        if once {
            return Ok(());
        }
        tokio::time::sleep(interval).await;
    }
}

pub async fn measure_frame_rate(
    websocket: &str,
    label_path: &Path,
    duration: Duration,
) -> Result<FrameRateReport> {
    ensure!(!duration.is_zero(), "frame-rate duration must be non-zero");
    let labels = read_labels(label_path)?;
    let frame_counter = labels
        .get("frameCounter")
        .copied()
        .context("label file does not contain frameCounter")?;
    let offset = wram_to_usb2snes(frame_counter)?;
    let clock_unix_seconds = labels
        .get("clockUnixSeconds")
        .copied()
        .context("label file does not contain clockUnixSeconds")?;
    let clock_offset = wram_to_usb2snes(clock_unix_seconds)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);

    let start_frame = read_stable_u32(&mut client, offset).await?;
    let (start_unix_seconds, start_subsecond) =
        read_stable_clock(&mut client, clock_offset).await?;
    let started = Instant::now();
    tokio::time::sleep(duration).await;
    let end_frame = read_stable_u32(&mut client, offset).await?;
    let (end_unix_seconds, end_subsecond) = read_stable_clock(&mut client, clock_offset).await?;
    let elapsed_seconds = started.elapsed().as_secs_f64();
    let frame_delta = end_frame.wrapping_sub(start_frame);
    let clock_elapsed_seconds = f64::from(end_unix_seconds.wrapping_sub(start_unix_seconds))
        + (f64::from(end_subsecond) - f64::from(start_subsecond)) / 4_294_967_296.0;

    Ok(FrameRateReport {
        elapsed_seconds,
        start_frame,
        end_frame,
        frame_delta,
        frames_per_second: f64::from(frame_delta) / elapsed_seconds,
        start_unix_seconds,
        end_unix_seconds,
        start_subsecond,
        end_subsecond,
        clock_elapsed_seconds,
    })
}

pub async fn ntp_request(
    websocket: &str,
    label_path: &Path,
    timeout: Duration,
) -> Result<PppDiagnosticSnapshot> {
    const NTP_STATE_RECEIVED: u8 = 3;
    const NTP_STATE_FAILED: u8 = 4;

    let labels = read_labels(label_path)?;
    let state = labels
        .get("pppDiagnosticState")
        .copied()
        .context("label file does not contain pppDiagnosticState")?;
    let offset = wram_to_usb2snes(state)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);
    let before = read_stable_ppp_snapshot(&mut client, offset).await?;
    drop(client);

    mailbox_command_with_arguments(
        websocket,
        label_path,
        ndm24_protocol::MODEM_MAILBOX_COMMAND_NTP_REQUEST,
        &[],
        timeout,
    )
    .await?;

    let mut client = Client::connect(websocket).await?;
    let started = Instant::now();
    loop {
        let snapshot = read_stable_ppp_snapshot(&mut client, offset).await?;
        if snapshot.ntp_state == NTP_STATE_RECEIVED
            && snapshot.ntp_response_count != before.ntp_response_count
        {
            return Ok(snapshot);
        }
        if snapshot.ntp_state == NTP_STATE_FAILED {
            bail!(
                "NTP request failed: error=0x{:02x}, requests={}, responses={}, drops={}, timeouts={}",
                snapshot.ntp_last_error,
                snapshot.ntp_request_count,
                snapshot.ntp_response_count,
                snapshot.ntp_drop_count,
                snapshot.ntp_timeout_count
            );
        }
        ensure!(
            started.elapsed() < timeout,
            "timed out waiting for NTP response: state={}, requests={}, responses={}",
            snapshot.ntp_state,
            snapshot.ntp_request_count,
            snapshot.ntp_response_count
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

pub async fn icmp_echo(
    websocket: &str,
    label_path: &Path,
    destination: [u8; 4],
    timeout: Duration,
) -> Result<PppDiagnosticSnapshot> {
    const ICMP_REQUEST_STATE_RECEIVED: u8 = 3;
    const ICMP_REQUEST_STATE_FAILED: u8 = 4;

    let labels = read_labels(label_path)?;
    let state = labels
        .get("pppDiagnosticState")
        .copied()
        .context("label file does not contain pppDiagnosticState")?;
    let offset = wram_to_usb2snes(state)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);
    let before = read_stable_ppp_snapshot(&mut client, offset).await?;
    drop(client);

    mailbox_command_with_arguments(
        websocket,
        label_path,
        ndm24_protocol::MODEM_MAILBOX_COMMAND_ICMP_ECHO_REQUEST,
        &destination,
        timeout,
    )
    .await?;

    let mut client = Client::connect(websocket).await?;
    let started = Instant::now();
    loop {
        let snapshot = read_stable_ppp_snapshot(&mut client, offset).await?;
        if snapshot.icmp_request_state == ICMP_REQUEST_STATE_RECEIVED
            && snapshot.icmp_request_response_count != before.icmp_request_response_count
        {
            return Ok(snapshot);
        }
        if snapshot.icmp_request_state == ICMP_REQUEST_STATE_FAILED {
            bail!(
                "ICMP Echo failed: error=0x{:02x}, requests={}, responses={}, drops={}, timeouts={}",
                snapshot.icmp_request_last_error,
                snapshot.icmp_request_count,
                snapshot.icmp_request_response_count,
                snapshot.icmp_request_drop_count,
                snapshot.icmp_request_timeout_count
            );
        }
        ensure!(
            started.elapsed() < timeout,
            "timed out waiting for ICMP Echo reply: state={}, requests={}, responses={}",
            snapshot.icmp_request_state,
            snapshot.icmp_request_count,
            snapshot.icmp_request_response_count
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

pub async fn dns_query(
    websocket: &str,
    label_path: &Path,
    resolver: [u8; 4],
    name: &str,
    timeout: Duration,
) -> Result<PppDiagnosticSnapshot> {
    const DNS_STATE_RECEIVED: u8 = 3;
    const DNS_STATE_FAILED: u8 = 4;
    const SFC_DNS_MAXIMUM_NAME_LENGTH: usize = 27;

    ensure!(
        !name.ends_with('.'),
        "the SFC DNS mailbox expects a hostname without a trailing dot"
    );
    ensure!(
        name.len() <= SFC_DNS_MAXIMUM_NAME_LENGTH,
        "DNS name is {} bytes; the SFC DNS mailbox supports at most {}",
        name.len(),
        SFC_DNS_MAXIMUM_NAME_LENGTH
    );
    let mut encoded = [0_u8; 64];
    ndm24_ppp::dns::encode_a_query(0, name, &mut encoded)
        .map_err(|error| anyhow::anyhow!("invalid DNS name {name:?}: {error:?}"))?;

    let labels = read_labels(label_path)?;
    let state = labels
        .get("pppDiagnosticState")
        .copied()
        .context("label file does not contain pppDiagnosticState")?;
    let offset = wram_to_usb2snes(state)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);
    let before = read_stable_ppp_snapshot(&mut client, offset).await?;
    drop(client);

    let mut arguments = Vec::with_capacity(5 + name.len());
    arguments.extend_from_slice(&resolver);
    arguments.push(name.len() as u8);
    arguments.extend_from_slice(name.as_bytes());
    mailbox_command_with_arguments(
        websocket,
        label_path,
        ndm24_protocol::MODEM_MAILBOX_COMMAND_DNS_QUERY,
        &arguments,
        timeout,
    )
    .await?;

    let mut client = Client::connect(websocket).await?;
    let started = Instant::now();
    loop {
        let snapshot = read_stable_ppp_snapshot(&mut client, offset).await?;
        if snapshot.dns_state == DNS_STATE_RECEIVED
            && snapshot.dns_response_count != before.dns_response_count
        {
            return Ok(snapshot);
        }
        if snapshot.dns_state == DNS_STATE_FAILED {
            bail!(
                "DNS query failed: error=0x{:02x}, rcode={}, queries={}, responses={}, drops={}, timeouts={}",
                snapshot.dns_last_error,
                snapshot.dns_response_code,
                snapshot.dns_query_count,
                snapshot.dns_response_count,
                snapshot.dns_drop_count,
                snapshot.dns_timeout_count
            );
        }
        ensure!(
            started.elapsed() < timeout,
            "timed out waiting for DNS response: state={}, queries={}, responses={}",
            snapshot.dns_state,
            snapshot.dns_query_count,
            snapshot.dns_response_count
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

pub async fn dump_trace(websocket: &str, label_path: &Path) -> Result<()> {
    for event in read_trace_events(websocket, label_path).await? {
        println!("{}", serde_json::to_string(&event)?);
    }
    Ok(())
}

pub async fn read_trace_events(websocket: &str, label_path: &Path) -> Result<Vec<TraceEvent>> {
    let labels = read_labels(label_path)?;
    let state = labels
        .get("modemState")
        .copied()
        .context("label file does not contain modemState")?;
    let trace = labels
        .get("modemTrace")
        .copied()
        .context("label file does not contain modemTrace")?;
    let state_offset = wram_to_usb2snes(state)?;
    let offset = wram_to_usb2snes(trace)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);
    let deadline = Instant::now() + Duration::from_secs(2);
    let (snapshot, data) = loop {
        let before = read_stable_snapshot(&mut client, state_offset).await?;
        let data = client.read_address(offset, MODEM_TRACE_SIZE).await?;
        let after = read_stable_snapshot(&mut client, state_offset).await?;
        if before.trace_next_sequence == after.trace_next_sequence {
            break (after, data);
        }
        ensure!(
            Instant::now() < deadline,
            "trace kept changing while it was read; freeze it with `mailbox freeze-trace`"
        );
    };
    let mut events = data
        .chunks_exact(MODEM_TRACE_EVENT_SIZE)
        .map(TraceEvent::decode)
        .collect::<Result<Vec<_>>>()?;
    let available = snapshot.trace_next_sequence.min(256);
    events.retain(|event| {
        let distance = snapshot.trace_next_sequence.wrapping_sub(event.sequence);
        distance >= 1 && distance <= available
    });
    events.sort_by_key(|event| event.sequence);
    Ok(events)
}

pub async fn mailbox_command(
    websocket: &str,
    label_path: &Path,
    command: u8,
    timeout: Duration,
) -> Result<()> {
    let outcome =
        mailbox_command_with_arguments(websocket, label_path, command, &[], timeout).await?;
    println!(
        "mailbox command {command} passed (sequence {})",
        outcome.sequence
    );
    Ok(())
}

pub async fn mailbox_command_with_arguments(
    websocket: &str,
    label_path: &Path,
    command: u8,
    arguments: &[u8],
    timeout: Duration,
) -> Result<MailboxOutcome> {
    ensure!(
        arguments.len() <= ndm24_protocol::MODEM_MAILBOX_ARGUMENT_SIZE,
        "mailbox arguments are too long"
    );
    let labels = read_labels(label_path)?;
    let mailbox = labels
        .get("modemMailbox")
        .copied()
        .context("label file does not contain modemMailbox")?;
    let offset = wram_to_usb2snes(mailbox)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);

    let initial = client.read_address(offset, MODEM_MAILBOX_SIZE).await?;
    validate_mailbox(&initial)?;
    let current = read_u32(&initial, MODEM_MAILBOX_OFFSET_PROCESSED_SEQUENCE)?;
    let sequence = current.wrapping_add(1);

    let mut writes = arguments
        .iter()
        .copied()
        .enumerate()
        .map(|(index, byte)| {
            (
                mailbox + ndm24_protocol::MODEM_MAILBOX_OFFSET_ARGUMENTS as u32 + index as u32,
                byte,
            )
        })
        .collect::<Vec<_>>();
    writes.push((mailbox + MODEM_MAILBOX_OFFSET_COMMAND as u32, command));
    writes.extend(
        sequence
            .to_le_bytes()
            .into_iter()
            .enumerate()
            .map(|(index, byte)| {
                (
                    mailbox + MODEM_MAILBOX_OFFSET_HOST_SEQUENCE as u32 + index as u32,
                    byte,
                )
            }),
    );
    let payload = build_wram_write_payload(&writes)?;
    client
        .execute_address(FXPAK_EXECUTION_SCRATCH, &payload)
        .await?;

    let started = Instant::now();
    let mut completion_candidate: Option<Vec<u8>> = None;
    loop {
        let mailbox = client.read_address(offset, MODEM_MAILBOX_SIZE).await?;
        validate_mailbox(&mailbox)?;
        let processed = read_u32(&mailbox, MODEM_MAILBOX_OFFSET_PROCESSED_SEQUENCE)?;
        let status = mailbox[MODEM_MAILBOX_OFFSET_STATUS];
        if processed == sequence
            && (status == MODEM_MAILBOX_STATUS_PASSED || status == MODEM_MAILBOX_STATUS_FAILED)
        {
            if completion_candidate.as_ref() != Some(&mailbox) {
                completion_candidate = Some(mailbox);
                ensure!(
                    started.elapsed() < timeout,
                    "timed out stabilizing mailbox command {command}"
                );
                tokio::time::sleep(Duration::from_millis(10)).await;
                continue;
            }
            let result = read_u16(&mailbox, MODEM_MAILBOX_OFFSET_RESULT)?;
            ensure!(
                status == MODEM_MAILBOX_STATUS_PASSED,
                "SFC mailbox command failed with result 0x{result:04x}"
            );
            let output = read_stable_mailbox_output(websocket, offset).await?;
            return Ok(MailboxOutcome {
                sequence,
                result,
                output,
            });
        }
        completion_candidate = None;
        if started.elapsed() >= timeout {
            let host = read_u32(&mailbox, MODEM_MAILBOX_OFFSET_HOST_SEQUENCE)?;
            let result = read_u16(&mailbox, MODEM_MAILBOX_OFFSET_RESULT)?;
            bail!(
                "timed out waiting for mailbox command {command}: \
                 host_sequence={host}, processed_sequence={processed}, \
                 observed_command={}, status={status}, result=0x{result:04x}",
                mailbox[MODEM_MAILBOX_OFFSET_COMMAND]
            );
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

async fn read_stable_mailbox_output(websocket: &str, mailbox_offset: usize) -> Result<Vec<u8>> {
    let output_offset = mailbox_offset + ndm24_protocol::MODEM_MAILBOX_OFFSET_OUTPUT;
    let mut client = Client::connect(websocket).await?;
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        let first = client
            .read_address(output_offset, ndm24_protocol::MODEM_MAILBOX_ARGUMENT_SIZE)
            .await?;
        tokio::time::sleep(Duration::from_millis(10)).await;
        let second = client
            .read_address(output_offset, ndm24_protocol::MODEM_MAILBOX_ARGUMENT_SIZE)
            .await?;
        if first == second {
            return Ok(second);
        }
        ensure!(
            Instant::now() < deadline,
            "mailbox output did not stabilize"
        );
    }
}

async fn read_stable_u32(client: &mut Client, offset: usize) -> Result<u32> {
    let mut previous: Option<Vec<u8>> = None;
    for _ in 0..20 {
        let current = client.read_address(offset, size_of::<u32>()).await?;
        if previous.as_ref() == Some(&current) {
            return Ok(u32::from_le_bytes(
                current
                    .as_slice()
                    .try_into()
                    .context("stable u32 read returned the wrong length")?,
            ));
        }
        previous = Some(current);
    }
    bail!("u32 value at FXPAK offset 0x{offset:06x} did not stabilize")
}

async fn read_stable_clock(client: &mut Client, offset: usize) -> Result<(u32, u32)> {
    let mut previous: Option<Vec<u8>> = None;
    for _ in 0..20 {
        let current = client.read_address(offset, 8).await?;
        if previous.as_ref() == Some(&current) {
            let seconds = u32::from_le_bytes(
                current[0..4]
                    .try_into()
                    .context("clock seconds read returned the wrong length")?,
            );
            let subsecond = u32::from_le_bytes(
                current[4..8]
                    .try_into()
                    .context("clock fraction read returned the wrong length")?,
            );
            return Ok((seconds, subsecond));
        }
        previous = Some(current);
    }
    bail!("clock value at FXPAK offset 0x{offset:06x} did not stabilize")
}

pub async fn read_snapshot(websocket: &str, label_path: &Path) -> Result<DiagnosticSnapshot> {
    let labels = read_labels(label_path)?;
    let state = labels
        .get("modemState")
        .copied()
        .context("label file does not contain modemState")?;
    let offset = wram_to_usb2snes(state)?;
    let mut client = Client::connect(websocket).await?;
    read_stable_snapshot(&mut client, offset).await
}

pub async fn read_pending_rx(websocket: &str, label_path: &Path) -> Result<Vec<u8>> {
    let labels = read_labels(label_path)?;
    let state = labels
        .get("modemState")
        .copied()
        .context("label file does not contain modemState")?;
    let receive_buffer = labels
        .get("modemReceiveBuffer")
        .copied()
        .context("label file does not contain modemReceiveBuffer")?;
    let state_offset = wram_to_usb2snes(state)?;
    let buffer_offset = wram_to_usb2snes(receive_buffer)?;
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);
    let deadline = Instant::now() + Duration::from_secs(2);

    loop {
        let before = read_stable_snapshot(&mut client, state_offset).await?;
        let ring = client
            .read_address(buffer_offset, MODEM_RING_STORAGE_SIZE)
            .await?;
        let after = read_stable_snapshot(&mut client, state_offset).await?;
        if before.rx_read_index == after.rx_read_index
            && before.rx_write_index == after.rx_write_index
            && before.rx_accepted == after.rx_accepted
        {
            return Ok(pending_ring_bytes(
                &ring,
                after.rx_read_index,
                after.rx_write_index,
            ));
        }
        ensure!(
            Instant::now() < deadline,
            "RX ring kept changing while it was read"
        );
    }
}

pub async fn upload_and_boot(websocket: &str, rom_path: &Path, remote_path: &str) -> Result<()> {
    let data = fs::read(rom_path).with_context(|| format!("read ROM {}", rom_path.display()))?;
    ensure!(!data.is_empty(), "ROM is empty");
    let mut client = Client::connect(websocket).await?;
    eprintln!("attached to {}", client.device);
    send_request(
        &mut client.socket,
        "PutFile",
        vec![remote_path.to_owned(), format!("{:x}", data.len())],
    )
    .await?;
    send_binary_chunks(&mut client.socket, &data).await?;
    send_request(&mut client.socket, "Boot", vec![remote_path.to_owned()]).await?;
    let info = tokio::time::timeout(
        Duration::from_secs(15),
        request_response(&mut client.socket, "Info", vec![]),
    )
    .await
    .context("timed out waiting for FXPAK PRO to boot the uploaded ROM")??;
    verify_running_rom(&info, remote_path)?;
    println!(
        "uploaded {} bytes to {remote_path} and confirmed boot",
        data.len()
    );
    Ok(())
}

fn verify_running_rom(info: &[String], expected_path: &str) -> Result<()> {
    let running_path = info
        .get(2)
        .context("QUsb2Snes Info response does not contain the running ROM path")?
        .trim_end_matches('\0');
    ensure!(
        running_path.eq_ignore_ascii_case(expected_path),
        "FXPAK PRO is running {running_path:?}, expected {expected_path:?}"
    );
    Ok(())
}

fn validate_mailbox(data: &[u8]) -> Result<()> {
    ensure!(
        data.len() >= MODEM_MAILBOX_SIZE,
        "mailbox is shorter than its ABI size"
    );
    ensure!(
        data[..4] == MODEM_MAILBOX_MAGIC,
        "mailbox magic does not match NDMC"
    );
    ensure!(
        read_u16(data, ndm24_protocol::MODEM_MAILBOX_OFFSET_VERSION)? == MODEM_MAILBOX_VERSION,
        "unsupported mailbox ABI version"
    );
    ensure!(
        read_u16(data, MODEM_MAILBOX_OFFSET_BLOCK_SIZE)? as usize == MODEM_MAILBOX_SIZE,
        "mailbox size does not match the generated ABI"
    );
    Ok(())
}

async fn read_stable_snapshot(client: &mut Client, offset: usize) -> Result<DiagnosticSnapshot> {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        ensure!(
            Instant::now() < deadline,
            "diagnostic snapshot did not stabilize; confirm that the running ROM matches the label file and retry if diagnostics are changing rapidly"
        );
        let first = client
            .read_address(offset + MODEM_DIAG_SNAPSHOT_SEQUENCE, size_of::<u32>())
            .await?;
        let first_sequence = read_u32(&first, 0)?;
        if first_sequence & 1 != 0 {
            tokio::task::yield_now().await;
            continue;
        }

        let snapshot = client.read_address(offset, MODEM_DIAGNOSTIC_SIZE).await?;
        let snapshot_sequence = read_u32(&snapshot, MODEM_DIAG_SNAPSHOT_SEQUENCE)?;
        if snapshot_sequence != first_sequence {
            tokio::task::yield_now().await;
            continue;
        }

        let last = client
            .read_address(offset + MODEM_DIAG_SNAPSHOT_SEQUENCE, size_of::<u32>())
            .await?;
        let last_sequence = read_u32(&last, 0)?;
        if last_sequence != first_sequence {
            tokio::task::yield_now().await;
            continue;
        }
        return DiagnosticSnapshot::decode(&snapshot);
    }
}

async fn read_stable_ppp_snapshot(
    client: &mut Client,
    offset: usize,
) -> Result<PppDiagnosticSnapshot> {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        ensure!(
            Instant::now() < deadline,
            "PPP diagnostic snapshot did not stabilize; confirm that the running ROM matches the label file and retry if diagnostics are changing rapidly"
        );
        let first = client
            .read_address(offset + PPP_DIAG_SNAPSHOT_SEQUENCE, size_of::<u32>())
            .await?;
        let first_sequence = read_u32(&first, 0)?;
        if first_sequence & 1 != 0 {
            tokio::task::yield_now().await;
            continue;
        }

        let snapshot = client.read_address(offset, PPP_DIAGNOSTIC_SIZE).await?;
        let snapshot_sequence = read_u32(&snapshot, PPP_DIAG_SNAPSHOT_SEQUENCE)?;
        if snapshot_sequence != first_sequence {
            tokio::task::yield_now().await;
            continue;
        }

        let last = client
            .read_address(offset + PPP_DIAG_SNAPSHOT_SEQUENCE, size_of::<u32>())
            .await?;
        let last_sequence = read_u32(&last, 0)?;
        if last_sequence != first_sequence {
            tokio::task::yield_now().await;
            continue;
        }
        return PppDiagnosticSnapshot::decode(&snapshot);
    }
}

async fn send_request(socket: &mut Socket, opcode: &str, operands: Vec<String>) -> Result<()> {
    send_request_with_flags(socket, opcode, operands, None).await
}

async fn send_request_with_flags(
    socket: &mut Socket,
    opcode: &str,
    operands: Vec<String>,
    flags: Option<Vec<String>>,
) -> Result<()> {
    let request = Request {
        opcode,
        space: "SNES",
        flags,
        operands,
    };
    socket
        .send(Message::Text(serde_json::to_string(&request)?.into()))
        .await?;
    Ok(())
}

async fn request_response(
    socket: &mut Socket,
    opcode: &str,
    operands: Vec<String>,
) -> Result<Vec<String>> {
    send_request(socket, opcode, operands).await?;
    while let Some(message) = socket.next().await {
        match message? {
            Message::Text(text) => return Ok(serde_json::from_str::<Response>(&text)?.results),
            Message::Ping(payload) => socket.send(Message::Pong(payload)).await?,
            Message::Close(_) => bail!("QUsb2Snes closed the connection"),
            _ => {}
        }
    }
    bail!("QUsb2Snes connection ended before a response")
}

async fn read_address(socket: &mut Socket, offset: usize, size: usize) -> Result<Vec<u8>> {
    send_request(
        socket,
        "GetAddress",
        vec![format!("{offset:x}"), format!("{size:x}")],
    )
    .await?;
    let mut output = Vec::with_capacity(size);
    while output.len() < size {
        let message = socket
            .next()
            .await
            .context("QUsb2Snes ended while returning address data")??;
        match message {
            Message::Binary(bytes) => output.extend_from_slice(&bytes),
            Message::Ping(payload) => socket.send(Message::Pong(payload)).await?,
            Message::Close(_) => bail!("QUsb2Snes closed while returning address data"),
            Message::Text(text) => bail!("unexpected text response to GetAddress: {text}"),
            _ => {}
        }
    }
    output.truncate(size);
    Ok(output)
}

async fn write_binary_request_with_flags(
    socket: &mut Socket,
    opcode: &str,
    offset: usize,
    data: &[u8],
    flags: Option<Vec<String>>,
) -> Result<()> {
    send_request_with_flags(
        socket,
        opcode,
        vec![format!("{offset:x}"), format!("{:x}", data.len())],
        flags,
    )
    .await?;
    send_binary_chunks(socket, data).await
}

fn build_wram_write_payload(writes: &[(u32, u8)]) -> Result<Vec<u8>> {
    ensure!(!writes.is_empty(), "WRAM execution payload has no writes");
    let mut payload = Vec::with_capacity(6 * writes.len() + 6);
    payload.extend_from_slice(&[0x08, 0xe2, 0x20, 0x48]); // PHP; SEP #$20; PHA
    for &(address, value) in writes {
        ensure!(
            (0x7e_0000..=0x7f_ffff).contains(&address),
            "execution payload target 0x{address:06x} is outside SNES WRAM"
        );
        payload.extend_from_slice(&[0xa9, value, 0x8f]); // LDA #value; STA long
        payload.extend_from_slice(&address.to_le_bytes()[..3]);
    }
    payload.extend_from_slice(&[0x68, 0x28]); // PLA; PLP
    ensure!(
        payload.len() <= 0x100,
        "WRAM execution payload exceeds the FXPAK PRO 256-byte execution area"
    );
    Ok(payload)
}

async fn send_binary_chunks(socket: &mut Socket, data: &[u8]) -> Result<()> {
    for chunk in data.chunks(1024) {
        socket.send(Message::Binary(chunk.to_vec().into())).await?;
    }
    Ok(())
}

fn read_u16(data: &[u8], offset: usize) -> Result<u16> {
    let bytes: [u8; 2] = data
        .get(offset..offset + 2)
        .context("mailbox u16 field is outside the input")?
        .try_into()
        .expect("slice length was checked");
    Ok(u16::from_le_bytes(bytes))
}

fn read_u32(data: &[u8], offset: usize) -> Result<u32> {
    let bytes: [u8; 4] = data
        .get(offset..offset + 4)
        .context("mailbox u32 field is outside the input")?
        .try_into()
        .expect("slice length was checked");
    Ok(u32::from_le_bytes(bytes))
}

fn pending_ring_bytes(ring: &[u8], read_index: u8, write_index: u8) -> Vec<u8> {
    let mut output = Vec::with_capacity(write_index.wrapping_sub(read_index) as usize);
    let mut index = read_index;
    while index != write_index {
        output.push(ring[index as usize]);
        index = index.wrapping_add(1);
    }
    output
}

#[cfg(test)]
mod tests {
    use super::{
        MODEM_RING_STORAGE_SIZE, build_wram_write_payload, pending_ring_bytes, verify_running_rom,
    };

    #[test]
    fn running_rom_accepts_fxpak_nul_padding() {
        let info = vec![
            "1.11.0".to_owned(),
            "SD2SNES".to_owned(),
            "/snes-modem-control.sfc\0\0".to_owned(),
        ];

        verify_running_rom(&info, "/snes-modem-control.sfc").unwrap();
    }

    #[test]
    fn running_rom_rejects_the_fxpak_menu() {
        let info = vec![
            "1.11.0".to_owned(),
            "SD2SNES".to_owned(),
            "/sd2snes/m3nu.bin\0".to_owned(),
        ];

        let error = verify_running_rom(&info, "/snes-modem-control.sfc").unwrap_err();
        assert!(error.to_string().contains("/sd2snes/m3nu.bin"));
    }

    #[test]
    fn builds_register_preserving_wram_write_payload() {
        let payload = build_wram_write_payload(&[(0x7e_1234, 0x56)]).unwrap();
        assert_eq!(
            payload,
            [
                0x08, 0xe2, 0x20, 0x48, // PHP; SEP #$20; PHA
                0xa9, 0x56, 0x8f, 0x34, 0x12, 0x7e, // LDA #$56; STA $7E1234
                0x68, 0x28, // PLA; PLP
            ]
        );
    }

    #[test]
    fn rejects_execution_payload_outside_wram() {
        assert!(build_wram_write_payload(&[(0x00_1234, 0x56)]).is_err());
    }

    #[test]
    fn pending_rx_reconstructs_wrapped_ring() {
        let mut ring = vec![0; MODEM_RING_STORAGE_SIZE];
        ring[254] = b'A';
        ring[255] = b'B';
        ring[0] = b'C';
        assert_eq!(pending_ring_bytes(&ring, 254, 1), b"ABC");
    }
}
