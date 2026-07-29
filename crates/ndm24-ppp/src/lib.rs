//! Reference implementation of the asynchronous PPP framing used above the
//! NDM24 byte transport.
//!
//! RFC 1662 framing and the allocation-free LCP packet codec live here.
//! Authentication, IPCP, and network-layer protocols remain separate state
//! machines.

use std::mem;

pub mod lcp;

pub const FLAG_SEQUENCE: u8 = 0x7e;
pub const CONTROL_ESCAPE: u8 = 0x7d;
pub const TRANSPARENCY_XOR: u8 = 0x20;
pub const DEFAULT_ACCM: u32 = u32::MAX;

pub const INITIAL_FCS16: u16 = 0xffff;
pub const GOOD_FCS16: u16 = 0xf0b8;
const FCS16_POLYNOMIAL_REVERSED: u16 = 0x8408;

pub const DEFAULT_MRU: usize = 1_500;
pub const UNCOMPRESSED_HEADER_LENGTH: usize = 4;
pub const FCS16_LENGTH: usize = 2;
pub const MINIMUM_FRAME_WITH_FCS_LENGTH: usize = 4;
pub const DEFAULT_MAX_UNESCAPED_FRAME_LENGTH: usize =
    UNCOMPRESSED_HEADER_LENGTH + DEFAULT_MRU + FCS16_LENGTH;

/// Updates the RFC 1662 16-bit FCS with one octet.
///
/// The bitwise form is deliberately used instead of the RFC lookup table so
/// the same operation can be ported directly to 65816 assembly.
pub fn update_fcs16(mut fcs: u16, octet: u8) -> u16 {
    fcs ^= u16::from(octet);
    for _ in 0..8 {
        fcs = if fcs & 1 != 0 {
            (fcs >> 1) ^ FCS16_POLYNOMIAL_REVERSED
        } else {
            fcs >> 1
        };
    }
    fcs
}

pub fn fcs16(octets: &[u8]) -> u16 {
    octets.iter().copied().fold(INITIAL_FCS16, update_fcs16)
}

pub fn transmitted_fcs16(frame: &[u8]) -> u16 {
    fcs16(frame) ^ u16::MAX
}

pub fn append_fcs16(frame: &mut Vec<u8>) {
    let fcs = transmitted_fcs16(frame);
    frame.extend_from_slice(&fcs.to_le_bytes());
}

pub fn has_valid_fcs16(frame_with_fcs: &[u8]) -> bool {
    fcs16(frame_with_fcs) == GOOD_FCS16
}

fn accm_contains(accm: u32, octet: u8) -> bool {
    octet < 0x20 && accm & (1_u32 << octet) != 0
}

fn must_escape(octet: u8, send_accm: u32) -> bool {
    octet == FLAG_SEQUENCE || octet == CONTROL_ESCAPE || accm_contains(send_accm, octet)
}

/// Encodes one unescaped PPP frame.
///
/// `frame` contains Address, Control, Protocol, and Information, but excludes
/// Flag Sequences and the FCS. A fresh opening Flag is always emitted.
pub fn encode_async(frame: &[u8], send_accm: u32) -> Vec<u8> {
    let mut unescaped = Vec::with_capacity(frame.len() + FCS16_LENGTH);
    unescaped.extend_from_slice(frame);
    append_fcs16(&mut unescaped);

    let mut encoded = Vec::with_capacity(unescaped.len() * 2 + 2);
    encoded.push(FLAG_SEQUENCE);
    for octet in unescaped {
        if must_escape(octet, send_accm) {
            encoded.push(CONTROL_ESCAPE);
            encoded.push(octet ^ TRANSPARENCY_XOR);
        } else {
            encoded.push(octet);
        }
    }
    encoded.push(FLAG_SEQUENCE);
    encoded
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncoderStage {
    OpeningFlag,
    Frame,
    FcsLow,
    FcsHigh,
    ClosingFlag,
    Complete,
}

/// Allocation-free, restartable asynchronous PPP encoder.
///
/// The caller may inspect the next wire octet with [`Self::peek`] and must
/// call [`Self::advance`] only after the transport accepted that octet. This
/// mirrors an SFC producer waiting for room in the NDM24 TX ring.
#[derive(Debug)]
pub struct AsyncEncoder<'a> {
    frame: &'a [u8],
    send_accm: u32,
    position: usize,
    fcs: u16,
    stage: EncoderStage,
    escape_second: bool,
}

impl<'a> AsyncEncoder<'a> {
    pub fn new(frame: &'a [u8], send_accm: u32) -> Self {
        Self {
            frame,
            send_accm,
            position: 0,
            fcs: INITIAL_FCS16,
            stage: EncoderStage::OpeningFlag,
            escape_second: false,
        }
    }

    pub fn stage(&self) -> EncoderStage {
        self.stage
    }

    pub fn is_complete(&self) -> bool {
        self.stage == EncoderStage::Complete
    }

    /// Returns the next wire octet without changing encoder state.
    pub fn peek(&self) -> Option<u8> {
        match self.stage {
            EncoderStage::OpeningFlag | EncoderStage::ClosingFlag => Some(FLAG_SEQUENCE),
            EncoderStage::Frame | EncoderStage::FcsLow | EncoderStage::FcsHigh => {
                let octet = self.logical_octet();
                if must_escape(octet, self.send_accm) {
                    Some(if self.escape_second {
                        octet ^ TRANSPARENCY_XOR
                    } else {
                        CONTROL_ESCAPE
                    })
                } else {
                    Some(octet)
                }
            }
            EncoderStage::Complete => None,
        }
    }

    /// Commits the octet returned by [`Self::peek`].
    pub fn advance(&mut self) {
        match self.stage {
            EncoderStage::OpeningFlag => {
                self.stage = if self.frame.is_empty() {
                    EncoderStage::FcsLow
                } else {
                    EncoderStage::Frame
                };
            }
            EncoderStage::Frame | EncoderStage::FcsLow | EncoderStage::FcsHigh => {
                let octet = self.logical_octet();
                if must_escape(octet, self.send_accm) && !self.escape_second {
                    self.escape_second = true;
                    return;
                }
                self.escape_second = false;
                self.finish_logical_octet(octet);
            }
            EncoderStage::ClosingFlag => self.stage = EncoderStage::Complete,
            EncoderStage::Complete => {}
        }
    }

    /// Offers wire octets to a fallible sink until it refuses one or the
    /// frame completes. Refused octets remain pending.
    pub fn pump(&mut self, mut accept: impl FnMut(u8) -> bool) -> usize {
        let mut accepted = 0;
        while let Some(octet) = self.peek() {
            if !accept(octet) {
                break;
            }
            self.advance();
            accepted += 1;
        }
        accepted
    }

    fn logical_octet(&self) -> u8 {
        match self.stage {
            EncoderStage::Frame => self.frame[self.position],
            EncoderStage::FcsLow => (self.fcs ^ u16::MAX).to_le_bytes()[0],
            EncoderStage::FcsHigh => (self.fcs ^ u16::MAX).to_le_bytes()[1],
            _ => unreachable!("stage has no logical octet"),
        }
    }

    fn finish_logical_octet(&mut self, octet: u8) {
        self.stage = match self.stage {
            EncoderStage::Frame => {
                self.fcs = update_fcs16(self.fcs, octet);
                self.position += 1;
                if self.position == self.frame.len() {
                    EncoderStage::FcsLow
                } else {
                    EncoderStage::Frame
                }
            }
            EncoderStage::FcsLow => EncoderStage::FcsHigh,
            EncoderStage::FcsHigh => EncoderStage::ClosingFlag,
            _ => unreachable!("stage has no logical octet"),
        };
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InvalidFrameReason {
    TooShort,
    EscapeBeforeFlag,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeEvent {
    /// Address, Control, Protocol, and Information with the FCS removed.
    Frame(Vec<u8>),
    FcsError {
        unescaped_length: usize,
    },
    InvalidFrame(InvalidFrameReason),
    Overflow {
        maximum_length: usize,
    },
}

#[derive(Debug)]
pub struct AsyncDecoder {
    receive_accm: u32,
    maximum_unescaped_length: usize,
    frame: Vec<u8>,
    synchronized: bool,
    escaped: bool,
    overflowed: bool,
}

impl Default for AsyncDecoder {
    fn default() -> Self {
        Self::new(DEFAULT_ACCM, DEFAULT_MAX_UNESCAPED_FRAME_LENGTH)
    }
}

impl AsyncDecoder {
    pub fn new(receive_accm: u32, maximum_unescaped_length: usize) -> Self {
        Self {
            receive_accm,
            maximum_unescaped_length,
            frame: Vec::with_capacity(maximum_unescaped_length),
            synchronized: false,
            escaped: false,
            overflowed: false,
        }
    }

    pub fn reset(&mut self) {
        self.frame.clear();
        self.synchronized = false;
        self.escaped = false;
        self.overflowed = false;
    }

    pub fn push(&mut self, octet: u8) -> Option<DecodeEvent> {
        if octet == FLAG_SEQUENCE {
            return self.finish_at_flag();
        }

        if !self.synchronized || self.overflowed {
            return None;
        }

        // RFC 1662 section 4.2 removes unescaped receive-ACCM controls before
        // FCS calculation. If one appears after an escape octet, the escape
        // remains pending for the next non-removed octet.
        if accm_contains(self.receive_accm, octet) {
            return None;
        }

        let decoded = if self.escaped {
            self.escaped = false;
            octet ^ TRANSPARENCY_XOR
        } else if octet == CONTROL_ESCAPE {
            self.escaped = true;
            return None;
        } else {
            octet
        };

        if self.frame.len() == self.maximum_unescaped_length {
            self.frame.clear();
            self.overflowed = true;
            return None;
        }
        self.frame.push(decoded);
        None
    }

    fn finish_at_flag(&mut self) -> Option<DecodeEvent> {
        if !self.synchronized {
            self.synchronized = true;
            self.frame.clear();
            self.escaped = false;
            self.overflowed = false;
            return None;
        }

        if self.escaped {
            self.frame.clear();
            self.escaped = false;
            self.overflowed = false;
            return Some(DecodeEvent::InvalidFrame(
                InvalidFrameReason::EscapeBeforeFlag,
            ));
        }

        if self.overflowed {
            self.frame.clear();
            self.overflowed = false;
            return Some(DecodeEvent::Overflow {
                maximum_length: self.maximum_unescaped_length,
            });
        }

        if self.frame.is_empty() {
            return None;
        }

        if self.frame.len() < MINIMUM_FRAME_WITH_FCS_LENGTH {
            self.frame.clear();
            return Some(DecodeEvent::InvalidFrame(InvalidFrameReason::TooShort));
        }

        if !has_valid_fcs16(&self.frame) {
            let unescaped_length = self.frame.len();
            self.frame.clear();
            return Some(DecodeEvent::FcsError { unescaped_length });
        }

        self.frame.truncate(self.frame.len() - FCS16_LENGTH);
        Some(DecodeEvent::Frame(mem::take(&mut self.frame)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const EMPTY_LCP_CONFIGURE_REQUEST: [u8; 8] = [0xff, 0x03, 0xc0, 0x21, 0x01, 0x01, 0x00, 0x04];

    fn decode_all(decoder: &mut AsyncDecoder, bytes: &[u8]) -> Vec<DecodeEvent> {
        bytes
            .iter()
            .filter_map(|octet| decoder.push(*octet))
            .collect()
    }

    #[test]
    fn fcs_matches_the_standard_crc16_x25_check_value() {
        assert_eq!(transmitted_fcs16(b"123456789"), 0x906e);
    }

    #[test]
    fn appended_fcs_reaches_the_rfc_good_value() {
        let mut frame = EMPTY_LCP_CONFIGURE_REQUEST.to_vec();
        append_fcs16(&mut frame);
        assert_eq!(&frame[8..], &[0xd1, 0xb5]);
        assert_eq!(fcs16(&frame), GOOD_FCS16);
        assert!(has_valid_fcs16(&frame));
    }

    #[test]
    fn default_accm_escapes_controls_flag_and_escape() {
        let encoded = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM);
        assert_eq!(
            encoded,
            [
                0x7e, 0xff, 0x7d, 0x23, 0xc0, 0x21, 0x7d, 0x21, 0x7d, 0x21, 0x7d, 0x20, 0x7d, 0x24,
                0xd1, 0xb5, 0x7e,
            ]
        );
    }

    #[test]
    fn streaming_encoder_matches_one_shot_encoding() {
        for send_accm in [0, DEFAULT_ACCM] {
            let expected = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, send_accm);
            let mut encoder = AsyncEncoder::new(&EMPTY_LCP_CONFIGURE_REQUEST, send_accm);
            let mut actual = Vec::new();
            assert_eq!(
                encoder.pump(|octet| {
                    actual.push(octet);
                    true
                }),
                expected.len()
            );
            assert!(encoder.is_complete());
            assert_eq!(actual, expected);
        }
    }

    #[test]
    fn streaming_encoder_resumes_after_every_backpressure_point() {
        let expected = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM);
        for capacity in 1..=expected.len() {
            let mut encoder = AsyncEncoder::new(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM);
            let mut actual = Vec::new();
            while !encoder.is_complete() {
                let mut remaining = capacity;
                let accepted = encoder.pump(|octet| {
                    if remaining == 0 {
                        return false;
                    }
                    remaining -= 1;
                    actual.push(octet);
                    true
                });
                assert!(accepted > 0);
            }
            assert_eq!(actual, expected, "capacity {capacity}");
        }
    }

    #[test]
    fn refused_octet_does_not_advance_encoder() {
        let mut encoder = AsyncEncoder::new(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM);
        let pending = encoder.peek();
        assert_eq!(encoder.pump(|_| false), 0);
        assert_eq!(encoder.peek(), pending);
        assert_eq!(encoder.stage(), EncoderStage::OpeningFlag);
    }

    #[test]
    fn streaming_encoder_handles_empty_and_maximum_frames() {
        for frame in [Vec::new(), {
            let mut frame = vec![0xff, 0x03, 0x00, 0x21];
            frame.extend((0..DEFAULT_MRU).map(|index| index as u8));
            frame
        }] {
            let expected = encode_async(&frame, DEFAULT_ACCM);
            let mut encoder = AsyncEncoder::new(&frame, DEFAULT_ACCM);
            let mut actual = Vec::new();
            while !encoder.is_complete() {
                let mut remaining = 7;
                encoder.pump(|octet| {
                    if remaining == 0 {
                        return false;
                    }
                    remaining -= 1;
                    actual.push(octet);
                    true
                });
            }
            assert_eq!(actual, expected);
        }
    }

    #[test]
    fn decoder_accepts_every_possible_input_split() {
        let encoded = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM);
        for split in 0..=encoded.len() {
            let mut decoder = AsyncDecoder::default();
            let mut events = decode_all(&mut decoder, &encoded[..split]);
            events.extend(decode_all(&mut decoder, &encoded[split..]));
            assert_eq!(
                events,
                [DecodeEvent::Frame(EMPTY_LCP_CONFIGURE_REQUEST.to_vec())],
                "split {split}"
            );
        }
    }

    #[test]
    fn decoder_ignores_noise_before_the_first_flag_and_empty_frames() {
        let mut stream = vec![0x41, 0x54, FLAG_SEQUENCE, FLAG_SEQUENCE];
        stream.extend_from_slice(&encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM));

        let events = decode_all(&mut AsyncDecoder::default(), &stream);
        assert_eq!(
            events,
            [DecodeEvent::Frame(EMPTY_LCP_CONFIGURE_REQUEST.to_vec())]
        );
    }

    #[test]
    fn receive_accm_removes_an_injected_unescaped_control() {
        let mut encoded = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, DEFAULT_ACCM);
        encoded.insert(1, 0x11);

        let events = decode_all(&mut AsyncDecoder::default(), &encoded);
        assert_eq!(
            events,
            [DecodeEvent::Frame(EMPTY_LCP_CONFIGURE_REQUEST.to_vec())]
        );
    }

    #[test]
    fn corrupted_frame_reports_fcs_error_and_resynchronizes() {
        let mut bad = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, 0);
        bad[4] ^= 0x01;
        let good = encode_async(&EMPTY_LCP_CONFIGURE_REQUEST, 0);
        bad.extend_from_slice(&good[1..]);

        let events = decode_all(&mut AsyncDecoder::new(0, 64), &bad);
        assert_eq!(
            events,
            [
                DecodeEvent::FcsError {
                    unescaped_length: 10
                },
                DecodeEvent::Frame(EMPTY_LCP_CONFIGURE_REQUEST.to_vec()),
            ]
        );
    }

    #[test]
    fn escape_immediately_before_flag_aborts_without_fcs_error() {
        let stream = [FLAG_SEQUENCE, 0xff, CONTROL_ESCAPE, FLAG_SEQUENCE];
        let events = decode_all(&mut AsyncDecoder::default(), &stream);
        assert_eq!(
            events,
            [DecodeEvent::InvalidFrame(
                InvalidFrameReason::EscapeBeforeFlag
            )]
        );
    }

    #[test]
    fn short_frame_is_invalid_but_not_an_fcs_error() {
        let stream = [FLAG_SEQUENCE, 0xff, 0x03, FLAG_SEQUENCE];
        let events = decode_all(&mut AsyncDecoder::default(), &stream);
        assert_eq!(
            events,
            [DecodeEvent::InvalidFrame(InvalidFrameReason::TooShort)]
        );
    }

    #[test]
    fn oversized_frame_is_discarded_until_the_next_flag() {
        let stream = [FLAG_SEQUENCE, 1, 2, 3, 4, 5, FLAG_SEQUENCE];
        let events = decode_all(&mut AsyncDecoder::new(0, 4), &stream);
        assert_eq!(events, [DecodeEvent::Overflow { maximum_length: 4 }]);
    }

    #[test]
    fn maximum_default_mru_round_trips() {
        let mut frame = vec![0xff, 0x03, 0x00, 0x21];
        frame.extend((0..DEFAULT_MRU).map(|index| index as u8));
        let encoded = encode_async(&frame, DEFAULT_ACCM);
        let events = decode_all(&mut AsyncDecoder::default(), &encoded);
        assert_eq!(events, [DecodeEvent::Frame(frame)]);
    }
}
