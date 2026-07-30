//! Allocation-free ICMP Echo parsing and encoding.

use crate::ipv4::internet_checksum;

pub const TYPE_ECHO_REPLY: u8 = 0;
pub const TYPE_ECHO_REQUEST: u8 = 8;
pub const ECHO_CODE: u8 = 0;
pub const ECHO_HEADER_LENGTH: usize = 8;

const TYPE_OFFSET: usize = 0;
const CODE_OFFSET: usize = 1;
const CHECKSUM_OFFSET: usize = 2;
const IDENTIFIER_OFFSET: usize = 4;
const SEQUENCE_OFFSET: usize = 6;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EchoKind {
    Reply,
    Request,
}

impl EchoKind {
    const fn icmp_type(self) -> u8 {
        match self {
            Self::Reply => TYPE_ECHO_REPLY,
            Self::Request => TYPE_ECHO_REQUEST,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    Truncated { available: usize },
    UnsupportedType(u8),
    NonZeroCode(u8),
    InvalidChecksum,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    OutputTooSmall { required: usize, available: usize },
    MessageTooLong(usize),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EchoPacket<'a> {
    bytes: &'a [u8],
    kind: EchoKind,
}

impl<'a> EchoPacket<'a> {
    pub fn parse(bytes: &'a [u8]) -> Result<Self, ParseError> {
        if bytes.len() < ECHO_HEADER_LENGTH {
            return Err(ParseError::Truncated {
                available: bytes.len(),
            });
        }

        let kind = match bytes[TYPE_OFFSET] {
            TYPE_ECHO_REPLY => EchoKind::Reply,
            TYPE_ECHO_REQUEST => EchoKind::Request,
            other => return Err(ParseError::UnsupportedType(other)),
        };
        if bytes[CODE_OFFSET] != ECHO_CODE {
            return Err(ParseError::NonZeroCode(bytes[CODE_OFFSET]));
        }
        if internet_checksum(bytes) != 0 {
            return Err(ParseError::InvalidChecksum);
        }

        Ok(Self { bytes, kind })
    }

    pub fn kind(self) -> EchoKind {
        self.kind
    }

    pub fn checksum(self) -> u16 {
        read_u16(self.bytes, CHECKSUM_OFFSET)
    }

    pub fn identifier(self) -> u16 {
        read_u16(self.bytes, IDENTIFIER_OFFSET)
    }

    pub fn sequence(self) -> u16 {
        read_u16(self.bytes, SEQUENCE_OFFSET)
    }

    pub fn payload(self) -> &'a [u8] {
        &self.bytes[ECHO_HEADER_LENGTH..]
    }

    pub fn bytes(self) -> &'a [u8] {
        self.bytes
    }
}

pub fn encode_echo(
    kind: EchoKind,
    identifier: u16,
    sequence: u16,
    payload: &[u8],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    let length = ECHO_HEADER_LENGTH + payload.len();
    if length > usize::from(u16::MAX) {
        return Err(EncodeError::MessageTooLong(length));
    }
    if output.len() < length {
        return Err(EncodeError::OutputTooSmall {
            required: length,
            available: output.len(),
        });
    }

    let message = &mut output[..length];
    message[..ECHO_HEADER_LENGTH].fill(0);
    message[TYPE_OFFSET] = kind.icmp_type();
    write_u16(message, IDENTIFIER_OFFSET, identifier);
    write_u16(message, SEQUENCE_OFFSET, sequence);
    message[ECHO_HEADER_LENGTH..].copy_from_slice(payload);
    let checksum = internet_checksum(message);
    write_u16(message, CHECKSUM_OFFSET, checksum);
    Ok(length)
}

pub fn encode_echo_reply(request: EchoPacket<'_>, output: &mut [u8]) -> Result<usize, EncodeError> {
    encode_echo(
        EchoKind::Reply,
        request.identifier(),
        request.sequence(),
        request.payload(),
        output,
    )
}

fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_be_bytes([bytes[offset], bytes[offset + 1]])
}

fn write_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    const ODD_PAYLOAD: &[u8] = b"NDM24";
    const REQUEST: &[u8] = &[
        0x08, 0x00, 0x16, 0x54, 0x12, 0x34, 0x00, 0x01, b'N', b'D', b'M', b'2', b'4',
    ];
    const REPLY: &[u8] = &[
        0x00, 0x00, 0x1e, 0x54, 0x12, 0x34, 0x00, 0x01, b'N', b'D', b'M', b'2', b'4',
    ];

    #[test]
    fn known_odd_length_request_parses() {
        let packet = EchoPacket::parse(REQUEST).unwrap();
        assert_eq!(packet.kind(), EchoKind::Request);
        assert_eq!(packet.checksum(), 0x1654);
        assert_eq!(packet.identifier(), 0x1234);
        assert_eq!(packet.sequence(), 1);
        assert_eq!(packet.payload(), ODD_PAYLOAD);
        assert_eq!(packet.bytes(), REQUEST);
    }

    #[test]
    fn request_and_reply_match_known_checksums() {
        let mut request = [0xcc; REQUEST.len()];
        let request_length =
            encode_echo(EchoKind::Request, 0x1234, 1, ODD_PAYLOAD, &mut request).unwrap();
        assert_eq!(request_length, REQUEST.len());
        assert_eq!(request, REQUEST);

        let parsed = EchoPacket::parse(&request).unwrap();
        let mut reply = [0xcc; REPLY.len()];
        let reply_length = encode_echo_reply(parsed, &mut reply).unwrap();
        assert_eq!(reply_length, REPLY.len());
        assert_eq!(reply, REPLY);
        assert_eq!(EchoPacket::parse(&reply).unwrap().kind(), EchoKind::Reply);
    }

    #[test]
    fn empty_payload_round_trips() {
        let mut output = [0; ECHO_HEADER_LENGTH];
        let length = encode_echo(EchoKind::Reply, 0xabcd, 0x5678, &[], &mut output).unwrap();
        assert_eq!(length, ECHO_HEADER_LENGTH);
        let packet = EchoPacket::parse(&output).unwrap();
        assert_eq!(packet.identifier(), 0xabcd);
        assert_eq!(packet.sequence(), 0x5678);
        assert!(packet.payload().is_empty());
    }

    #[test]
    fn parser_rejects_invalid_messages() {
        assert_eq!(
            EchoPacket::parse(&REQUEST[..ECHO_HEADER_LENGTH - 1]),
            Err(ParseError::Truncated {
                available: ECHO_HEADER_LENGTH - 1
            })
        );

        let mut unsupported = REQUEST.to_vec();
        unsupported[TYPE_OFFSET] = 3;
        assert_eq!(
            EchoPacket::parse(&unsupported),
            Err(ParseError::UnsupportedType(3))
        );

        let mut nonzero_code = REQUEST.to_vec();
        nonzero_code[CODE_OFFSET] = 1;
        assert_eq!(
            EchoPacket::parse(&nonzero_code),
            Err(ParseError::NonZeroCode(1))
        );

        let mut bad_checksum = REQUEST.to_vec();
        *bad_checksum.last_mut().unwrap() ^= 1;
        assert_eq!(
            EchoPacket::parse(&bad_checksum),
            Err(ParseError::InvalidChecksum)
        );
    }

    #[test]
    fn encoder_reports_capacity_and_length_errors() {
        let mut short = [0; ECHO_HEADER_LENGTH - 1];
        assert_eq!(
            encode_echo(EchoKind::Request, 0, 0, &[], &mut short),
            Err(EncodeError::OutputTooSmall {
                required: ECHO_HEADER_LENGTH,
                available: ECHO_HEADER_LENGTH - 1,
            })
        );

        let oversized = vec![0; usize::from(u16::MAX)];
        assert_eq!(
            encode_echo(EchoKind::Request, 0, 0, &oversized, &mut []),
            Err(EncodeError::MessageTooLong(
                usize::from(u16::MAX) + ECHO_HEADER_LENGTH
            ))
        );
    }
}
