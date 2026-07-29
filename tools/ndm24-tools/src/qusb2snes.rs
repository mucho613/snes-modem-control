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
    MODEM_TRACE_EVENT_SIZE, MODEM_TRACE_SIZE, TraceEvent,
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

impl Client {
    async fn connect(websocket: &str) -> Result<Self> {
        let (mut socket, _) = connect_async(websocket)
            .await
            .with_context(|| format!("connect to QUsb2Snes at {websocket}"))?;
        send_request(&mut socket, "Name", vec!["snes-modem-control".to_owned()]).await?;
        let devices = request_response(&mut socket, "DeviceList", vec![]).await?;
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
        let info = request_response(&mut socket, "Info", vec![])
            .await
            .context("verify QUsb2Snes attachment")?;
        ensure!(!info.is_empty(), "attached device returned no information");
        Ok(Self { socket, device })
    }

    async fn read_address(&mut self, offset: usize, size: usize) -> Result<Vec<u8>> {
        read_address(&mut self.socket, offset, size).await
    }

    async fn write_address(&mut self, offset: usize, data: &[u8]) -> Result<()> {
        write_binary_request(&mut self.socket, "PutAddress", offset, data).await
    }
}

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

pub async fn dump_trace(websocket: &str, label_path: &Path) -> Result<()> {
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
    for event in events {
        println!("{}", serde_json::to_string(&event)?);
    }
    Ok(())
}

pub async fn mailbox_command(
    websocket: &str,
    label_path: &Path,
    command: u8,
    timeout: Duration,
) -> Result<()> {
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
    let current = read_u32(&initial, MODEM_MAILBOX_OFFSET_HOST_SEQUENCE)?;
    let sequence = current.wrapping_add(1);

    client
        .write_address(offset + MODEM_MAILBOX_OFFSET_COMMAND, &[command])
        .await?;
    client
        .write_address(
            offset + MODEM_MAILBOX_OFFSET_HOST_SEQUENCE,
            &sequence.to_le_bytes(),
        )
        .await?;

    let started = Instant::now();
    loop {
        let mailbox = client.read_address(offset, MODEM_MAILBOX_SIZE).await?;
        validate_mailbox(&mailbox)?;
        let processed = read_u32(&mailbox, MODEM_MAILBOX_OFFSET_PROCESSED_SEQUENCE)?;
        let status = mailbox[MODEM_MAILBOX_OFFSET_STATUS];
        if processed == sequence
            && (status == MODEM_MAILBOX_STATUS_PASSED || status == MODEM_MAILBOX_STATUS_FAILED)
        {
            let result = read_u16(&mailbox, MODEM_MAILBOX_OFFSET_RESULT)?;
            ensure!(
                status == MODEM_MAILBOX_STATUS_PASSED,
                "SFC mailbox command failed with result 0x{result:04x}"
            );
            println!("mailbox command {command} passed (sequence {sequence})");
            return Ok(());
        }
        ensure!(
            started.elapsed() < timeout,
            "timed out waiting for mailbox command {command}"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
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
    println!(
        "uploaded {} bytes to {remote_path} and requested boot",
        data.len()
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
    loop {
        let first = client.read_address(offset, MODEM_DIAGNOSTIC_SIZE).await?;
        let first_sequence = read_u32(&first, MODEM_DIAG_SNAPSHOT_SEQUENCE)?;
        if first_sequence & 1 != 0 {
            tokio::task::yield_now().await;
            continue;
        }
        let second = client.read_address(offset, MODEM_DIAGNOSTIC_SIZE).await?;
        let second_sequence = read_u32(&second, MODEM_DIAG_SNAPSHOT_SEQUENCE)?;
        if second_sequence != first_sequence {
            tokio::task::yield_now().await;
            continue;
        }
        return DiagnosticSnapshot::decode(&second);
    }
}

async fn send_request(socket: &mut Socket, opcode: &str, operands: Vec<String>) -> Result<()> {
    let request = Request {
        opcode,
        space: "SNES",
        flags: None,
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

async fn write_binary_request(
    socket: &mut Socket,
    opcode: &str,
    offset: usize,
    data: &[u8],
) -> Result<()> {
    send_request(
        socket,
        opcode,
        vec![format!("{offset:x}"), format!("{:x}", data.len())],
    )
    .await?;
    send_binary_chunks(socket, data).await
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
