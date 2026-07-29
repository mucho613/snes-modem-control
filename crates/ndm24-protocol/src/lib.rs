mod generated;

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};

pub use generated::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum DriverState {
    Off = MODEM_STATE_OFF,
    Resetting = MODEM_STATE_RESETTING,
    Probing = MODEM_STATE_PROBING,
    Ready = MODEM_STATE_READY,
    Error = MODEM_STATE_ERROR,
}

impl TryFrom<u8> for DriverState {
    type Error = anyhow::Error;

    fn try_from(value: u8) -> Result<Self> {
        match value {
            MODEM_STATE_OFF => Ok(Self::Off),
            MODEM_STATE_RESETTING => Ok(Self::Resetting),
            MODEM_STATE_PROBING => Ok(Self::Probing),
            MODEM_STATE_READY => Ok(Self::Ready),
            MODEM_STATE_ERROR => Ok(Self::Error),
            _ => bail!("unknown modem state {value}"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiagnosticSnapshot {
    pub snapshot_sequence: u32,
    pub driver_state: DriverState,
    pub flags: u8,
    pub last_error: u8,
    pub last_discard_reason: u8,
    pub poll_tick: bool,
    pub trace_frozen: bool,
    pub rx_read_index: u8,
    pub rx_write_index: u8,
    pub tx_read_index: u8,
    pub tx_write_index: u8,
    pub last_rx_byte: u8,
    pub last_tx_byte: u8,
    pub last_data_report: u16,
    pub last_status_report: u16,
    pub trace_next_sequence: u32,
    pub rx_accepted: u32,
    pub rx_discarded: u32,
    pub tx_bytes: u32,
    pub rx_overflow: u32,
    pub tx_overflow: u32,
    pub poll_limit: u32,
    pub timeout: u32,
    pub reinitialize: u32,
    pub trace_overwritten: u32,
    pub reset_start_frame: u32,
}

impl DiagnosticSnapshot {
    pub fn decode(data: &[u8]) -> Result<Self> {
        ensure!(
            data.len() >= MODEM_DIAGNOSTIC_SIZE,
            "diagnostic block is {} bytes; expected at least {}",
            data.len(),
            MODEM_DIAGNOSTIC_SIZE
        );
        ensure!(
            data[MODEM_DIAG_MAGIC..MODEM_DIAG_MAGIC + 4] == MODEM_DIAGNOSTIC_MAGIC,
            "diagnostic magic does not match NDM2"
        );
        ensure!(
            read_u16(data, MODEM_DIAG_VERSION)? == MODEM_DIAGNOSTIC_VERSION,
            "unsupported diagnostic ABI version"
        );
        ensure!(
            read_u16(data, MODEM_DIAG_SIZE)? as usize == MODEM_DIAGNOSTIC_SIZE,
            "diagnostic size field does not match the generated ABI"
        );

        let sequence = read_u32(data, MODEM_DIAG_SNAPSHOT_SEQUENCE)?;
        ensure!(sequence & 1 == 0, "diagnostic snapshot is being updated");

        Ok(Self {
            snapshot_sequence: sequence,
            driver_state: data[MODEM_DIAG_DRIVER_STATE].try_into()?,
            flags: data[MODEM_DIAG_FLAGS],
            last_error: data[MODEM_DIAG_LAST_ERROR],
            last_discard_reason: data[MODEM_DIAG_LAST_DISCARD_REASON],
            poll_tick: data[MODEM_DIAG_POLL_TICK] != 0,
            trace_frozen: data[MODEM_DIAG_TRACE_FROZEN] != 0,
            rx_read_index: data[MODEM_DIAG_RX_READ_INDEX],
            rx_write_index: data[MODEM_DIAG_RX_WRITE_INDEX],
            tx_read_index: data[MODEM_DIAG_TX_READ_INDEX],
            tx_write_index: data[MODEM_DIAG_TX_WRITE_INDEX],
            last_rx_byte: data[MODEM_DIAG_LAST_RX_BYTE],
            last_tx_byte: data[MODEM_DIAG_LAST_TX_BYTE],
            last_data_report: read_u16(data, MODEM_DIAG_LAST_DATA_REPORT)?,
            last_status_report: read_u16(data, MODEM_DIAG_LAST_STATUS_REPORT)?,
            trace_next_sequence: read_u32(data, MODEM_DIAG_TRACE_NEXT_SEQUENCE)?,
            rx_accepted: read_u32(data, MODEM_DIAG_RX_ACCEPTED)?,
            rx_discarded: read_u32(data, MODEM_DIAG_RX_DISCARDED)?,
            tx_bytes: read_u32(data, MODEM_DIAG_TX_BYTES)?,
            rx_overflow: read_u32(data, MODEM_DIAG_RX_OVERFLOW)?,
            tx_overflow: read_u32(data, MODEM_DIAG_TX_OVERFLOW)?,
            poll_limit: read_u32(data, MODEM_DIAG_POLL_LIMIT)?,
            timeout: read_u32(data, MODEM_DIAG_TIMEOUT)?,
            reinitialize: read_u32(data, MODEM_DIAG_REINITIALIZE)?,
            trace_overwritten: read_u32(data, MODEM_DIAG_TRACE_OVERWRITTEN)?,
            reset_start_frame: read_u32(data, MODEM_DIAG_RESET_START_FRAME)?,
        })
    }

    pub fn rx_used(&self) -> u8 {
        self.rx_write_index.wrapping_sub(self.rx_read_index)
    }

    pub fn tx_used(&self) -> u8 {
        self.tx_write_index.wrapping_sub(self.tx_read_index)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TraceEvent {
    pub sequence: u32,
    pub frame: u32,
    pub kind: u8,
    pub state: u8,
    pub reason: u8,
    pub flags: u8,
    pub data_report: u16,
    pub status_report: u16,
}

impl TraceEvent {
    pub fn decode(data: &[u8]) -> Result<Self> {
        ensure!(
            data.len() >= MODEM_TRACE_EVENT_SIZE,
            "trace event is truncated"
        );
        Ok(Self {
            sequence: read_u32(data, 0)?,
            frame: read_u32(data, 4)?,
            kind: data[8],
            state: data[9],
            reason: data[10],
            flags: data[11],
            data_report: read_u16(data, 12)?,
            status_report: read_u16(data, 14)?,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PollKind {
    Full16,
    Transfer9,
}

pub fn receive_decision(kind: PollKind, data_report: u16, status_report: u16) -> u8 {
    if kind == PollKind::Full16 {
        return MODEM_DISCARD_FULL_REPORT;
    }
    if status_report.to_le_bytes()[1] & MODEM_STATUS_READY_MASK as u8 == 0 {
        return MODEM_DISCARD_STATUS_NOT_READY;
    }
    if data_report.to_le_bytes()[0] & MODEM_RX_PRESENT_MASK as u8 == 0 {
        return MODEM_DISCARD_NO_DATA;
    }
    MODEM_DISCARD_NONE
}

pub fn receive_is_accepted(kind: PollKind, data_report: u16, status_report: u16) -> bool {
    receive_decision(kind, data_report, status_report) == MODEM_DISCARD_NONE
}

fn read_u16(data: &[u8], offset: usize) -> Result<u16> {
    let bytes: [u8; 2] = data
        .get(offset..offset + 2)
        .context("u16 field is outside the input")?
        .try_into()
        .expect("slice length was checked");
    Ok(u16::from_le_bytes(bytes))
}

fn read_u32(data: &[u8], offset: usize) -> Result<u32> {
    let bytes: [u8; 4] = data
        .get(offset..offset + 4)
        .context("u32 field is outside the input")?
        .try_into()
        .expect("slice length was checked");
    Ok(u32::from_le_bytes(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_report_never_delivers_a_byte() {
        assert_eq!(
            receive_decision(PollKind::Full16, 0x0d80, 0x4000),
            MODEM_DISCARD_FULL_REPORT
        );
    }

    #[test]
    fn nine_bit_report_requires_status_and_present_bits() {
        assert_eq!(
            receive_decision(PollKind::Transfer9, 0x0d80, 0x0000),
            MODEM_DISCARD_STATUS_NOT_READY
        );
        assert_eq!(
            receive_decision(PollKind::Transfer9, 0x0d00, 0x4000),
            MODEM_DISCARD_NO_DATA
        );
        assert!(receive_is_accepted(PollKind::Transfer9, 0x0d80, 0x4000));
    }
}
