mod generated;

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};

pub use generated::*;

pub const MODEM_SESSION_RESULT_NONE: u8 = 0;
pub const MODEM_SESSION_RESULT_OK: u8 = 1;
pub const MODEM_SESSION_RESULT_ERROR: u8 = 2;
pub const MODEM_SESSION_RESULT_CONNECT: u8 = 3;
pub const MODEM_SESSION_RESULT_NO_CARRIER: u8 = 4;
pub const MODEM_SESSION_RESULT_BUSY: u8 = 5;
pub const MODEM_SESSION_RESULT_NO_DIALTONE: u8 = 6;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum DriverState {
    Off = MODEM_STATE_OFF,
    Resetting = MODEM_STATE_RESETTING,
    Probing = MODEM_STATE_PROBING,
    Ready = MODEM_STATE_READY,
    Error = MODEM_STATE_ERROR,
    AtCommand = MODEM_STATE_AT_COMMAND,
    Dialing = MODEM_STATE_DIALING,
    Connected = MODEM_STATE_CONNECTED,
    Disconnecting = MODEM_STATE_DISCONNECTING,
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
            MODEM_STATE_AT_COMMAND => Ok(Self::AtCommand),
            MODEM_STATE_DIALING => Ok(Self::Dialing),
            MODEM_STATE_CONNECTED => Ok(Self::Connected),
            MODEM_STATE_DISCONNECTING => Ok(Self::Disconnecting),
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
    #[serde(alias = "poll_limit")]
    pub poll_budget_yield: u32,
    pub timeout: u32,
    pub reinitialize: u32,
    pub trace_overwritten: u32,
    pub reset_start_frame: u32,
    pub terminal_dropped: u32,
    pub at_status: u8,
    pub at_expected_result: u8,
    pub session_last_result: u8,
    pub session_line_length: u8,
    pub at_start_frame: u32,
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
            poll_budget_yield: read_u32(data, MODEM_DIAG_POLL_BUDGET_YIELD)?,
            timeout: read_u32(data, MODEM_DIAG_TIMEOUT)?,
            reinitialize: read_u32(data, MODEM_DIAG_REINITIALIZE)?,
            trace_overwritten: read_u32(data, MODEM_DIAG_TRACE_OVERWRITTEN)?,
            reset_start_frame: read_u32(data, MODEM_DIAG_RESET_START_FRAME)?,
            terminal_dropped: read_u32(data, MODEM_DIAG_TERMINAL_DROPPED)?,
            at_status: data[MODEM_DIAG_AT_STATUS],
            at_expected_result: data[MODEM_DIAG_AT_EXPECTED_RESULT],
            session_last_result: data[MODEM_DIAG_SESSION_LAST_RESULT],
            session_line_length: data[MODEM_DIAG_SESSION_LINE_LENGTH],
            at_start_frame: read_u32(data, MODEM_DIAG_AT_START_FRAME)?,
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
pub struct PppDiagnosticSnapshot {
    pub snapshot_sequence: u32,
    pub receive_enabled: bool,
    pub receive_active: bool,
    pub frame_ready: bool,
    pub receive_last_event: u8,
    pub receive_last_invalid_reason: u8,
    pub decoder_flags: u8,
    pub transmit_active: bool,
    pub transmit_stage: u8,
    pub transmit_escape_second: bool,
    pub transmit_last_wire_byte: u8,
    pub last_protocol: u16,
    pub last_frame_length: u16,
    pub decoder_length: u16,
    pub decoder_fcs: u16,
    pub transmit_length: u16,
    pub transmit_position: u16,
    pub transmit_fcs: u16,
    pub receive_byte_count: u32,
    pub receive_frame_count: u32,
    pub receive_fcs_error_count: u32,
    pub receive_invalid_count: u32,
    pub receive_overflow_count: u32,
    pub receive_drain_budget_yield_count: u32,
    pub transmit_wire_byte_count: u32,
    pub transmit_frame_count: u32,
    pub transmit_backpressure_count: u32,
    pub transmit_abort_count: u32,
    pub lcp_state: u8,
    pub lcp_last_code: u8,
    pub lcp_last_identifier: u8,
    pub lcp_last_error: u8,
    pub lcp_request_identifier: u8,
    pub lcp_restart_remaining: u8,
    pub lcp_peer_flags: u8,
    pub lcp_pending_action: u8,
    pub lcp_packet_length: u16,
    pub lcp_peer_mru: u16,
    pub lcp_peer_accm: u32,
    pub lcp_receive_count: u32,
    pub lcp_timer_active: bool,
    pub lcp_deferred_request: bool,
    pub lcp_restart_deadline: u16,
    pub lcp_peer_magic: u32,
    pub carrier_loss_count: u32,
    pub carrier_tail_byte_count: u32,
    pub pap_state: u8,
    pub pap_last_code: u8,
    pub pap_last_identifier: u8,
    pub pap_last_error: u8,
    pub pap_request_identifier: u8,
    pub pap_next_identifier: u8,
    pub pap_restart_remaining: u8,
    pub pap_pending_action: u8,
    pub pap_timer_active: bool,
    pub pap_failure: u8,
    pub pap_packet_length: u16,
    pub pap_restart_deadline: u16,
    pub pap_receive_count: u32,
    pub pap_transmit_count: u32,
}

impl PppDiagnosticSnapshot {
    pub fn decode(data: &[u8]) -> Result<Self> {
        ensure!(
            data.len() >= PPP_DIAGNOSTIC_SIZE,
            "PPP diagnostic block is {} bytes; expected at least {}",
            data.len(),
            PPP_DIAGNOSTIC_SIZE
        );
        ensure!(
            data[PPP_DIAG_MAGIC..PPP_DIAG_MAGIC + 4] == PPP_DIAGNOSTIC_MAGIC,
            "PPP diagnostic magic does not match PPP1"
        );
        ensure!(
            read_u16(data, PPP_DIAG_VERSION)? == PPP_DIAGNOSTIC_VERSION,
            "unsupported PPP diagnostic ABI version"
        );
        ensure!(
            read_u16(data, PPP_DIAG_SIZE)? as usize == PPP_DIAGNOSTIC_SIZE,
            "PPP diagnostic size field does not match the generated ABI"
        );

        let sequence = read_u32(data, PPP_DIAG_SNAPSHOT_SEQUENCE)?;
        ensure!(
            sequence & 1 == 0,
            "PPP diagnostic snapshot is being updated"
        );

        Ok(Self {
            snapshot_sequence: sequence,
            receive_enabled: data[PPP_DIAG_RECEIVE_ENABLED] != 0,
            receive_active: data[PPP_DIAG_RECEIVE_ACTIVE] != 0,
            frame_ready: data[PPP_DIAG_FRAME_READY] != 0,
            receive_last_event: data[PPP_DIAG_RECEIVE_LAST_EVENT],
            receive_last_invalid_reason: data[PPP_DIAG_RECEIVE_LAST_INVALID_REASON],
            decoder_flags: data[PPP_DIAG_DECODER_FLAGS],
            transmit_active: data[PPP_DIAG_TRANSMIT_ACTIVE] != 0,
            transmit_stage: data[PPP_DIAG_TRANSMIT_STAGE],
            transmit_escape_second: data[PPP_DIAG_TRANSMIT_ESCAPE_SECOND] != 0,
            transmit_last_wire_byte: data[PPP_DIAG_TRANSMIT_LAST_WIRE_BYTE],
            last_protocol: read_u16(data, PPP_DIAG_LAST_PROTOCOL)?,
            last_frame_length: read_u16(data, PPP_DIAG_LAST_FRAME_LENGTH)?,
            decoder_length: read_u16(data, PPP_DIAG_DECODER_LENGTH)?,
            decoder_fcs: read_u16(data, PPP_DIAG_DECODER_FCS)?,
            transmit_length: read_u16(data, PPP_DIAG_TRANSMIT_LENGTH)?,
            transmit_position: read_u16(data, PPP_DIAG_TRANSMIT_POSITION)?,
            transmit_fcs: read_u16(data, PPP_DIAG_TRANSMIT_FCS)?,
            receive_byte_count: read_u32(data, PPP_DIAG_RECEIVE_BYTE_COUNT)?,
            receive_frame_count: read_u32(data, PPP_DIAG_RECEIVE_FRAME_COUNT)?,
            receive_fcs_error_count: read_u32(data, PPP_DIAG_RECEIVE_FCS_ERROR_COUNT)?,
            receive_invalid_count: read_u32(data, PPP_DIAG_RECEIVE_INVALID_COUNT)?,
            receive_overflow_count: read_u32(data, PPP_DIAG_RECEIVE_OVERFLOW_COUNT)?,
            receive_drain_budget_yield_count: read_u32(
                data,
                PPP_DIAG_RECEIVE_DRAIN_BUDGET_YIELD_COUNT,
            )?,
            transmit_wire_byte_count: read_u32(data, PPP_DIAG_TRANSMIT_WIRE_BYTE_COUNT)?,
            transmit_frame_count: read_u32(data, PPP_DIAG_TRANSMIT_FRAME_COUNT)?,
            transmit_backpressure_count: read_u32(data, PPP_DIAG_TRANSMIT_BACKPRESSURE_COUNT)?,
            transmit_abort_count: read_u32(data, PPP_DIAG_TRANSMIT_ABORT_COUNT)?,
            lcp_state: data[PPP_DIAG_LCP_STATE],
            lcp_last_code: data[PPP_DIAG_LCP_LAST_CODE],
            lcp_last_identifier: data[PPP_DIAG_LCP_LAST_IDENTIFIER],
            lcp_last_error: data[PPP_DIAG_LCP_LAST_ERROR],
            lcp_request_identifier: data[PPP_DIAG_LCP_REQUEST_IDENTIFIER],
            lcp_restart_remaining: data[PPP_DIAG_LCP_RESTART_REMAINING],
            lcp_peer_flags: data[PPP_DIAG_LCP_PEER_FLAGS],
            lcp_pending_action: data[PPP_DIAG_LCP_PENDING_ACTION],
            lcp_packet_length: read_u16(data, PPP_DIAG_LCP_PACKET_LENGTH)?,
            lcp_peer_mru: read_u16(data, PPP_DIAG_LCP_PEER_MRU)?,
            lcp_peer_accm: read_u32(data, PPP_DIAG_LCP_PEER_ACCM)?,
            lcp_receive_count: read_u32(data, PPP_DIAG_LCP_RECEIVE_COUNT)?,
            lcp_timer_active: data[PPP_DIAG_LCP_TIMER_ACTIVE] != 0,
            lcp_deferred_request: data[PPP_DIAG_LCP_DEFERRED_REQUEST] != 0,
            lcp_restart_deadline: read_u16(data, PPP_DIAG_LCP_RESTART_DEADLINE)?,
            lcp_peer_magic: read_u32(data, PPP_DIAG_LCP_PEER_MAGIC)?,
            carrier_loss_count: read_u32(data, PPP_DIAG_CARRIER_LOSS_COUNT)?,
            carrier_tail_byte_count: read_u32(data, PPP_DIAG_CARRIER_TAIL_BYTE_COUNT)?,
            pap_state: data[PPP_DIAG_PAP_STATE],
            pap_last_code: data[PPP_DIAG_PAP_LAST_CODE],
            pap_last_identifier: data[PPP_DIAG_PAP_LAST_IDENTIFIER],
            pap_last_error: data[PPP_DIAG_PAP_LAST_ERROR],
            pap_request_identifier: data[PPP_DIAG_PAP_REQUEST_IDENTIFIER],
            pap_next_identifier: data[PPP_DIAG_PAP_NEXT_IDENTIFIER],
            pap_restart_remaining: data[PPP_DIAG_PAP_RESTART_REMAINING],
            pap_pending_action: data[PPP_DIAG_PAP_PENDING_ACTION],
            pap_timer_active: data[PPP_DIAG_PAP_TIMER_ACTIVE] != 0,
            pap_failure: data[PPP_DIAG_PAP_FAILURE],
            pap_packet_length: read_u16(data, PPP_DIAG_PAP_PACKET_LENGTH)?,
            pap_restart_deadline: read_u16(data, PPP_DIAG_PAP_RESTART_DEADLINE)?,
            pap_receive_count: read_u32(data, PPP_DIAG_PAP_RECEIVE_COUNT)?,
            pap_transmit_count: read_u32(data, PPP_DIAG_PAP_TRANSMIT_COUNT)?,
        })
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

pub fn receive_decision(kind: PollKind, data_report: u16, _status_report: u16) -> u8 {
    let receive_present = data_report.to_le_bytes()[0] & MODEM_RX_PRESENT_MASK as u8
        == MODEM_RX_PRESENT_ASSERTED as u8;
    if !receive_present {
        return if kind == PollKind::Full16 {
            MODEM_DISCARD_FULL_REPORT
        } else {
            MODEM_DISCARD_NO_DATA
        };
    }
    MODEM_DISCARD_NONE
}

pub fn receive_is_accepted(kind: PollKind, data_report: u16, status_report: u16) -> bool {
    receive_decision(kind, data_report, status_report) == MODEM_DISCARD_NONE
}

pub fn transfer_requested(
    previous_receive_decision: u8,
    status_report: u16,
    transmit_pending: bool,
) -> bool {
    previous_receive_decision == MODEM_DISCARD_NONE
        || status_report.to_le_bytes()[1] & MODEM_STATUS_TRANSFER_HINT_MASK as u8 != 0
        || transmit_pending
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
    fn full_report_uses_present_bit_and_not_data2_status() {
        assert!(receive_is_accepted(PollKind::Full16, 0x4183, 0x4000));
        assert!(receive_is_accepted(PollKind::Full16, 0x4183, 0x0000));
    }

    #[test]
    fn full_report_rejects_absent_byte() {
        assert_eq!(
            receive_decision(PollKind::Full16, 0x4103, 0x4000),
            MODEM_DISCARD_FULL_REPORT
        );
    }

    #[test]
    fn nine_bit_report_uses_present_bit_and_not_data2_status() {
        assert_eq!(MODEM_RX_PRESENT_ASSERTED, MODEM_RX_PRESENT_MASK);
        assert_eq!(
            receive_decision(PollKind::Transfer9, 0x0d00, 0x4000),
            MODEM_DISCARD_NO_DATA
        );
        assert!(receive_is_accepted(PollKind::Transfer9, 0x0d80, 0x4000));
        assert!(receive_is_accepted(PollKind::Transfer9, 0x0d80, 0x0000));
    }

    #[test]
    fn accepted_receive_keeps_draining_after_data2_hint_falls() {
        assert!(transfer_requested(MODEM_DISCARD_NONE, 0x0000, false));
        assert!(transfer_requested(
            MODEM_DISCARD_NO_DATA,
            (MODEM_STATUS_TRANSFER_HINT_MASK as u16) << 8,
            false
        ));
        assert!(transfer_requested(MODEM_DISCARD_NO_DATA, 0x0000, true));
        assert!(!transfer_requested(MODEM_DISCARD_NO_DATA, 0x0000, false));
    }

    #[test]
    fn diagnostic_decodes_terminal_drop_counter() {
        let mut data = vec![0; MODEM_DIAGNOSTIC_SIZE];
        data[MODEM_DIAG_MAGIC..MODEM_DIAG_MAGIC + 4].copy_from_slice(&MODEM_DIAGNOSTIC_MAGIC);
        data[MODEM_DIAG_VERSION..MODEM_DIAG_VERSION + 2]
            .copy_from_slice(&MODEM_DIAGNOSTIC_VERSION.to_le_bytes());
        data[MODEM_DIAG_SIZE..MODEM_DIAG_SIZE + 2]
            .copy_from_slice(&(MODEM_DIAGNOSTIC_SIZE as u16).to_le_bytes());
        data[MODEM_DIAG_TERMINAL_DROPPED..MODEM_DIAG_TERMINAL_DROPPED + 4]
            .copy_from_slice(&0x1234_5678_u32.to_le_bytes());

        let snapshot = DiagnosticSnapshot::decode(&data).unwrap();
        assert_eq!(snapshot.terminal_dropped, 0x1234_5678);
    }

    #[test]
    fn diagnostic_serialized_name_accepts_legacy_poll_limit_alias() {
        let mut data = vec![0; MODEM_DIAGNOSTIC_SIZE];
        data[MODEM_DIAG_MAGIC..MODEM_DIAG_MAGIC + 4].copy_from_slice(&MODEM_DIAGNOSTIC_MAGIC);
        data[MODEM_DIAG_VERSION..MODEM_DIAG_VERSION + 2]
            .copy_from_slice(&MODEM_DIAGNOSTIC_VERSION.to_le_bytes());
        data[MODEM_DIAG_SIZE..MODEM_DIAG_SIZE + 2]
            .copy_from_slice(&(MODEM_DIAGNOSTIC_SIZE as u16).to_le_bytes());
        data[MODEM_DIAG_POLL_BUDGET_YIELD..MODEM_DIAG_POLL_BUDGET_YIELD + 4]
            .copy_from_slice(&7_u32.to_le_bytes());

        let snapshot = DiagnosticSnapshot::decode(&data).unwrap();
        let current = toml::to_string(&snapshot).unwrap();
        assert!(current.contains("poll_budget_yield = 7"));
        assert!(!current.contains("poll_limit"));

        let legacy = current.replace("poll_budget_yield = 7", "poll_limit = 7");
        let decoded: DiagnosticSnapshot = toml::from_str(&legacy).unwrap();
        assert_eq!(decoded.poll_budget_yield, 7);
    }

    #[test]
    fn ppp_diagnostic_decodes_versioned_snapshot() {
        let mut data = vec![0; PPP_DIAGNOSTIC_SIZE];
        data[PPP_DIAG_MAGIC..PPP_DIAG_MAGIC + 4].copy_from_slice(&PPP_DIAGNOSTIC_MAGIC);
        data[PPP_DIAG_VERSION..PPP_DIAG_VERSION + 2]
            .copy_from_slice(&PPP_DIAGNOSTIC_VERSION.to_le_bytes());
        data[PPP_DIAG_SIZE..PPP_DIAG_SIZE + 2]
            .copy_from_slice(&(PPP_DIAGNOSTIC_SIZE as u16).to_le_bytes());
        data[PPP_DIAG_SNAPSHOT_SEQUENCE..PPP_DIAG_SNAPSHOT_SEQUENCE + 4]
            .copy_from_slice(&8_u32.to_le_bytes());
        data[PPP_DIAG_RECEIVE_ENABLED] = 1;
        data[PPP_DIAG_FRAME_READY] = 1;
        data[PPP_DIAG_LAST_PROTOCOL..PPP_DIAG_LAST_PROTOCOL + 2]
            .copy_from_slice(&0xc021_u16.to_le_bytes());
        data[PPP_DIAG_RECEIVE_FRAME_COUNT..PPP_DIAG_RECEIVE_FRAME_COUNT + 4]
            .copy_from_slice(&0x1234_5678_u32.to_le_bytes());
        data[PPP_DIAG_TRANSMIT_BACKPRESSURE_COUNT..PPP_DIAG_TRANSMIT_BACKPRESSURE_COUNT + 4]
            .copy_from_slice(&7_u32.to_le_bytes());
        data[PPP_DIAG_LCP_STATE] = 6;
        data[PPP_DIAG_LCP_LAST_CODE] = 1;
        data[PPP_DIAG_LCP_LAST_IDENTIFIER] = 0x42;
        data[PPP_DIAG_LCP_PACKET_LENGTH..PPP_DIAG_LCP_PACKET_LENGTH + 2]
            .copy_from_slice(&10_u16.to_le_bytes());
        data[PPP_DIAG_LCP_PEER_MRU..PPP_DIAG_LCP_PEER_MRU + 2]
            .copy_from_slice(&1500_u16.to_le_bytes());
        data[PPP_DIAG_LCP_PEER_ACCM..PPP_DIAG_LCP_PEER_ACCM + 4]
            .copy_from_slice(&u32::MAX.to_le_bytes());
        data[PPP_DIAG_LCP_RECEIVE_COUNT..PPP_DIAG_LCP_RECEIVE_COUNT + 4]
            .copy_from_slice(&6_u32.to_le_bytes());
        data[PPP_DIAG_LCP_TIMER_ACTIVE] = 1;
        data[PPP_DIAG_LCP_DEFERRED_REQUEST] = 1;
        data[PPP_DIAG_LCP_RESTART_DEADLINE..PPP_DIAG_LCP_RESTART_DEADLINE + 2]
            .copy_from_slice(&0xff80_u16.to_le_bytes());
        data[PPP_DIAG_LCP_PEER_MAGIC..PPP_DIAG_LCP_PEER_MAGIC + 4]
            .copy_from_slice(&0x1234_5678_u32.to_le_bytes());
        data[PPP_DIAG_CARRIER_LOSS_COUNT..PPP_DIAG_CARRIER_LOSS_COUNT + 4]
            .copy_from_slice(&3_u32.to_le_bytes());
        data[PPP_DIAG_CARRIER_TAIL_BYTE_COUNT..PPP_DIAG_CARRIER_TAIL_BYTE_COUNT + 4]
            .copy_from_slice(&12_u32.to_le_bytes());
        data[PPP_DIAG_PAP_STATE] = 2;
        data[PPP_DIAG_PAP_LAST_CODE] = 2;
        data[PPP_DIAG_PAP_LAST_IDENTIFIER] = 9;
        data[PPP_DIAG_PAP_REQUEST_IDENTIFIER] = 9;
        data[PPP_DIAG_PAP_RESTART_REMAINING] = 8;
        data[PPP_DIAG_PAP_TIMER_ACTIVE] = 1;
        data[PPP_DIAG_PAP_PACKET_LENGTH..PPP_DIAG_PAP_PACKET_LENGTH + 2]
            .copy_from_slice(&5_u16.to_le_bytes());
        data[PPP_DIAG_PAP_RECEIVE_COUNT..PPP_DIAG_PAP_RECEIVE_COUNT + 4]
            .copy_from_slice(&2_u32.to_le_bytes());
        data[PPP_DIAG_PAP_TRANSMIT_COUNT..PPP_DIAG_PAP_TRANSMIT_COUNT + 4]
            .copy_from_slice(&1_u32.to_le_bytes());

        let snapshot = PppDiagnosticSnapshot::decode(&data).unwrap();
        assert_eq!(snapshot.snapshot_sequence, 8);
        assert!(snapshot.receive_enabled);
        assert!(snapshot.frame_ready);
        assert_eq!(snapshot.last_protocol, 0xc021);
        assert_eq!(snapshot.receive_frame_count, 0x1234_5678);
        assert_eq!(snapshot.transmit_backpressure_count, 7);
        assert_eq!(snapshot.lcp_state, 6);
        assert_eq!(snapshot.lcp_last_code, 1);
        assert_eq!(snapshot.lcp_last_identifier, 0x42);
        assert_eq!(snapshot.lcp_packet_length, 10);
        assert_eq!(snapshot.lcp_peer_mru, 1500);
        assert_eq!(snapshot.lcp_peer_accm, u32::MAX);
        assert_eq!(snapshot.lcp_receive_count, 6);
        assert!(snapshot.lcp_timer_active);
        assert!(snapshot.lcp_deferred_request);
        assert_eq!(snapshot.lcp_restart_deadline, 0xff80);
        assert_eq!(snapshot.lcp_peer_magic, 0x1234_5678);
        assert_eq!(snapshot.carrier_loss_count, 3);
        assert_eq!(snapshot.carrier_tail_byte_count, 12);
        assert_eq!(snapshot.pap_state, 2);
        assert_eq!(snapshot.pap_last_code, 2);
        assert_eq!(snapshot.pap_last_identifier, 9);
        assert_eq!(snapshot.pap_request_identifier, 9);
        assert_eq!(snapshot.pap_restart_remaining, 8);
        assert!(snapshot.pap_timer_active);
        assert_eq!(snapshot.pap_packet_length, 5);
        assert_eq!(snapshot.pap_receive_count, 2);
        assert_eq!(snapshot.pap_transmit_count, 1);
    }

    #[test]
    fn ppp_diagnostic_rejects_an_update_in_progress() {
        let mut data = vec![0; PPP_DIAGNOSTIC_SIZE];
        data[PPP_DIAG_MAGIC..PPP_DIAG_MAGIC + 4].copy_from_slice(&PPP_DIAGNOSTIC_MAGIC);
        data[PPP_DIAG_VERSION..PPP_DIAG_VERSION + 2]
            .copy_from_slice(&PPP_DIAGNOSTIC_VERSION.to_le_bytes());
        data[PPP_DIAG_SIZE..PPP_DIAG_SIZE + 2]
            .copy_from_slice(&(PPP_DIAGNOSTIC_SIZE as u16).to_le_bytes());
        data[PPP_DIAG_SNAPSHOT_SEQUENCE..PPP_DIAG_SNAPSHOT_SEQUENCE + 4]
            .copy_from_slice(&3_u32.to_le_bytes());

        assert!(PppDiagnosticSnapshot::decode(&data).is_err());
    }
}
