use std::io::{Read, Write};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};

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
