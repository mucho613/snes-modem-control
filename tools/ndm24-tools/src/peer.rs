use std::io::{Read, Write};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};

pub struct PeerModem {
    port: Box<dyn serialport::SerialPort>,
    transcript: Vec<String>,
}

impl PeerModem {
    pub fn open(port_name: &str, baud: u32) -> Result<Self> {
        let mut port = serialport::new(port_name, baud)
            .timeout(Duration::from_millis(100))
            .open()
            .with_context(|| format!("open serial port {port_name}"))?;
        port.write_data_terminal_ready(true)?;
        port.write_request_to_send(true)?;
        Ok(Self {
            port,
            transcript: Vec::new(),
        })
    }

    pub fn command(&mut self, command: &str, timeout: Duration) -> Result<()> {
        self.transcript.push(format!("TX {command}"));
        self.port.write_all(command.as_bytes())?;
        self.port.write_all(b"\r")?;
        wait_for_line_recorded(&mut *self.port, timeout, &mut self.transcript, |line| {
            line == "OK"
        })
        .map(|_| ())
    }

    pub fn wait_for_connect(&mut self, timeout: Duration) -> Result<String> {
        wait_for_line_recorded(&mut *self.port, timeout, &mut self.transcript, |line| {
            line.starts_with("CONNECT")
        })
    }

    pub fn set_dtr(&mut self, asserted: bool) -> Result<()> {
        self.transcript
            .push(format!("DTR {}", if asserted { "ON" } else { "OFF" }));
        self.port.write_data_terminal_ready(asserted)?;
        Ok(())
    }

    pub fn write_data(&mut self, data: &[u8]) -> Result<()> {
        self.transcript
            .push(format!("DATA TX {} bytes", data.len()));
        self.port.write_all(data)?;
        self.port.flush()?;
        Ok(())
    }

    pub fn read_data_exact(&mut self, length: usize, timeout: Duration) -> Result<Vec<u8>> {
        let deadline = Instant::now() + timeout;
        let mut data = Vec::with_capacity(length);
        let mut buffer = [0u8; 256];
        while data.len() < length && Instant::now() < deadline {
            let remaining = length - data.len();
            let read_length = remaining.min(buffer.len());
            match self.port.read(&mut buffer[..read_length]) {
                Ok(0) => {}
                Ok(count) => data.extend_from_slice(&buffer[..count]),
                Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {}
                Err(error) => return Err(error.into()),
            }
        }
        if data.len() != length {
            bail!(
                "timed out after receiving {} of {length} data bytes",
                data.len()
            );
        }
        self.transcript
            .push(format!("DATA RX {} bytes", data.len()));
        Ok(data)
    }

    pub fn drain_data_until_quiet(
        &mut self,
        quiet: Duration,
        maximum: Duration,
    ) -> Result<Vec<u8>> {
        let deadline = Instant::now() + maximum;
        let mut quiet_deadline = Instant::now() + quiet;
        let mut data = Vec::new();
        let mut buffer = [0u8; 256];
        while Instant::now() < deadline && Instant::now() < quiet_deadline {
            match self.port.read(&mut buffer) {
                Ok(0) => {}
                Ok(count) => {
                    data.extend_from_slice(&buffer[..count]);
                    quiet_deadline = Instant::now() + quiet;
                }
                Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {}
                Err(error) => return Err(error.into()),
            }
        }
        self.transcript
            .push(format!("DATA DRAIN {} bytes", data.len()));
        Ok(data)
    }

    pub fn transcript(&self) -> &[String] {
        &self.transcript
    }
}

pub fn run(port_name: &str, baud: u32, command_timeout: Duration) -> Result<()> {
    let mut port = serialport::new(port_name, baud)
        .timeout(Duration::from_millis(100))
        .open()
        .with_context(|| format!("open serial port {port_name}"))?;

    for command in ["ATZ\r", "ATE0\r", "ATS0=1\r"] {
        port.write_all(command.as_bytes())?;
        wait_for_result(&mut *port, command_timeout)?;
    }

    eprintln!("peer modem armed for auto-answer; waiting for CONNECT");
    wait_for_connect(&mut *port, command_timeout)?;
    eprintln!("carrier connected; echoing bytes until disconnect");

    let mut buffer = [0u8; 1024];
    loop {
        match port.read(&mut buffer) {
            Ok(0) => {}
            Ok(count) => port.write_all(&buffer[..count])?,
            Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {}
            Err(error) => return Err(error.into()),
        }
    }
}

fn wait_for_result(port: &mut dyn serialport::SerialPort, timeout: Duration) -> Result<()> {
    wait_for_line(port, timeout, |line| line == "OK").map(|_| ())
}

fn wait_for_connect(port: &mut dyn serialport::SerialPort, timeout: Duration) -> Result<()> {
    wait_for_line(port, timeout, |line| line.starts_with("CONNECT")).map(|_| ())
}

fn wait_for_line(
    port: &mut dyn serialport::SerialPort,
    timeout: Duration,
    predicate: impl Fn(&str) -> bool,
) -> Result<String> {
    let deadline = Instant::now() + timeout;
    let mut line = Vec::new();
    let mut byte = [0u8; 1];
    while Instant::now() < deadline {
        match port.read(&mut byte) {
            Ok(1) if byte[0] == b'\r' || byte[0] == b'\n' => {
                if line.is_empty() {
                    continue;
                }
                let text = String::from_utf8_lossy(&line).trim().to_owned();
                line.clear();
                if predicate(&text) {
                    return Ok(text);
                }
            }
            Ok(1) => line.push(byte[0]),
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {}
            Err(error) => return Err(error.into()),
        }
    }
    bail!("timed out waiting for modem result code")
}

fn wait_for_line_recorded(
    port: &mut dyn serialport::SerialPort,
    timeout: Duration,
    transcript: &mut Vec<String>,
    predicate: impl Fn(&str) -> bool,
) -> Result<String> {
    let deadline = Instant::now() + timeout;
    let mut line = Vec::new();
    let mut byte = [0u8; 1];
    while Instant::now() < deadline {
        match port.read(&mut byte) {
            Ok(1) if byte[0] == b'\r' || byte[0] == b'\n' => {
                if line.is_empty() {
                    continue;
                }
                let text = String::from_utf8_lossy(&line).trim().to_owned();
                line.clear();
                transcript.push(format!("RX {text}"));
                if predicate(&text) {
                    return Ok(text);
                }
            }
            Ok(1) => line.push(byte[0]),
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {}
            Err(error) => return Err(error.into()),
        }
    }
    bail!("timed out waiting for modem result code")
}
