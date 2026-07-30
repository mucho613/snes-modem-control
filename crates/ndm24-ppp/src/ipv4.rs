//! Allocation-free IPv4 packet parsing and encoding.
//!
//! The parser accepts variable-length IPv4 headers and exposes fragmentation
//! metadata without reassembling fragments. The initial encoder emits the
//! 20-byte header used by the SFC client.

pub const VERSION: u8 = 4;
pub const MINIMUM_IHL_WORDS: u8 = 5;
pub const MINIMUM_HEADER_LENGTH: usize = MINIMUM_IHL_WORDS as usize * 4;
pub const MAXIMUM_HEADER_LENGTH: usize = 60;
pub const PROTOCOL_ICMP: u8 = 1;
pub const PROTOCOL_TCP: u8 = 6;
pub const PROTOCOL_UDP: u8 = 17;

pub const FLAG_RESERVED: u16 = 0x8000;
pub const FLAG_DONT_FRAGMENT: u16 = 0x4000;
pub const FLAG_MORE_FRAGMENTS: u16 = 0x2000;
pub const FRAGMENT_OFFSET_MASK: u16 = 0x1fff;

const VERSION_IHL_OFFSET: usize = 0;
const DSCP_ECN_OFFSET: usize = 1;
const TOTAL_LENGTH_OFFSET: usize = 2;
const IDENTIFICATION_OFFSET: usize = 4;
const FLAGS_FRAGMENT_OFFSET: usize = 6;
const TTL_OFFSET: usize = 8;
const PROTOCOL_OFFSET: usize = 9;
const HEADER_CHECKSUM_OFFSET: usize = 10;
const SOURCE_OFFSET: usize = 12;
const DESTINATION_OFFSET: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TruncatedMinimumHeader,
    UnsupportedVersion(u8),
    InvalidHeaderLength(u8),
    TruncatedHeader {
        header_length: usize,
        available: usize,
    },
    TotalLengthSmallerThanHeader {
        total_length: usize,
        header_length: usize,
    },
    TruncatedPacket {
        total_length: usize,
        available: usize,
    },
    InvalidHeaderChecksum,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    OutputTooSmall { required: usize, available: usize },
    PacketTooLong(usize),
    ReservedFlagSet,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub dscp_ecn: u8,
    pub identification: u16,
    pub flags_fragment_offset: u16,
    pub ttl: u8,
    pub protocol: u8,
    pub source: [u8; 4],
    pub destination: [u8; 4],
}

impl Header {
    pub const fn new(protocol: u8, source: [u8; 4], destination: [u8; 4]) -> Self {
        Self {
            dscp_ecn: 0,
            identification: 0,
            flags_fragment_offset: 0,
            ttl: 64,
            protocol,
            source,
            destination,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Packet<'a> {
    bytes: &'a [u8],
    header_length: usize,
}

impl<'a> Packet<'a> {
    pub fn parse(bytes: &'a [u8]) -> Result<Self, ParseError> {
        if bytes.len() < MINIMUM_HEADER_LENGTH {
            return Err(ParseError::TruncatedMinimumHeader);
        }

        let version_ihl = bytes[VERSION_IHL_OFFSET];
        let version = version_ihl >> 4;
        if version != VERSION {
            return Err(ParseError::UnsupportedVersion(version));
        }

        let ihl_words = version_ihl & 0x0f;
        if ihl_words < MINIMUM_IHL_WORDS {
            return Err(ParseError::InvalidHeaderLength(ihl_words));
        }
        let header_length = usize::from(ihl_words) * 4;
        if bytes.len() < header_length {
            return Err(ParseError::TruncatedHeader {
                header_length,
                available: bytes.len(),
            });
        }

        let total_length = usize::from(read_u16(bytes, TOTAL_LENGTH_OFFSET));
        if total_length < header_length {
            return Err(ParseError::TotalLengthSmallerThanHeader {
                total_length,
                header_length,
            });
        }
        if bytes.len() < total_length {
            return Err(ParseError::TruncatedPacket {
                total_length,
                available: bytes.len(),
            });
        }
        if internet_checksum(&bytes[..header_length]) != 0 {
            return Err(ParseError::InvalidHeaderChecksum);
        }

        Ok(Self {
            bytes: &bytes[..total_length],
            header_length,
        })
    }

    pub fn header_length(self) -> usize {
        self.header_length
    }

    pub fn total_length(self) -> usize {
        self.bytes.len()
    }

    pub fn dscp_ecn(self) -> u8 {
        self.bytes[DSCP_ECN_OFFSET]
    }

    pub fn identification(self) -> u16 {
        read_u16(self.bytes, IDENTIFICATION_OFFSET)
    }

    pub fn flags_fragment_offset(self) -> u16 {
        read_u16(self.bytes, FLAGS_FRAGMENT_OFFSET)
    }

    pub fn dont_fragment(self) -> bool {
        self.flags_fragment_offset() & FLAG_DONT_FRAGMENT != 0
    }

    pub fn more_fragments(self) -> bool {
        self.flags_fragment_offset() & FLAG_MORE_FRAGMENTS != 0
    }

    pub fn fragment_offset(self) -> u16 {
        self.flags_fragment_offset() & FRAGMENT_OFFSET_MASK
    }

    pub fn is_fragmented(self) -> bool {
        self.more_fragments() || self.fragment_offset() != 0
    }

    pub fn ttl(self) -> u8 {
        self.bytes[TTL_OFFSET]
    }

    pub fn protocol(self) -> u8 {
        self.bytes[PROTOCOL_OFFSET]
    }

    pub fn header_checksum(self) -> u16 {
        read_u16(self.bytes, HEADER_CHECKSUM_OFFSET)
    }

    pub fn source(self) -> [u8; 4] {
        read_address(self.bytes, SOURCE_OFFSET)
    }

    pub fn destination(self) -> [u8; 4] {
        read_address(self.bytes, DESTINATION_OFFSET)
    }

    pub fn options(self) -> &'a [u8] {
        &self.bytes[MINIMUM_HEADER_LENGTH..self.header_length]
    }

    pub fn payload(self) -> &'a [u8] {
        &self.bytes[self.header_length..]
    }

    pub fn bytes(self) -> &'a [u8] {
        self.bytes
    }
}

/// Computes the one's-complement checksum used by IPv4, ICMP, UDP, and TCP.
///
/// An odd trailing byte is treated as the high byte of the final 16-bit word.
/// A valid buffer that already includes its checksum evaluates to zero.
pub fn internet_checksum(bytes: &[u8]) -> u16 {
    let mut sum = 0_u32;
    let mut chunks = bytes.chunks_exact(2);
    for word in &mut chunks {
        sum += u32::from(u16::from_be_bytes([word[0], word[1]]));
    }
    if let [last] = chunks.remainder() {
        sum += u32::from(*last) << 8;
    }
    while sum > u32::from(u16::MAX) {
        sum = (sum & u32::from(u16::MAX)) + (sum >> 16);
    }
    !(sum as u16)
}

/// Encodes a packet with a 20-byte IPv4 header into caller-provided storage.
pub fn encode_packet(
    header: Header,
    payload: &[u8],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    let total_length = MINIMUM_HEADER_LENGTH + payload.len();
    if total_length > usize::from(u16::MAX) {
        return Err(EncodeError::PacketTooLong(total_length));
    }
    if output.len() < total_length {
        return Err(EncodeError::OutputTooSmall {
            required: total_length,
            available: output.len(),
        });
    }
    if header.flags_fragment_offset & FLAG_RESERVED != 0 {
        return Err(EncodeError::ReservedFlagSet);
    }

    let packet = &mut output[..total_length];
    packet[..MINIMUM_HEADER_LENGTH].fill(0);
    packet[VERSION_IHL_OFFSET] = (VERSION << 4) | MINIMUM_IHL_WORDS;
    packet[DSCP_ECN_OFFSET] = header.dscp_ecn;
    write_u16(packet, TOTAL_LENGTH_OFFSET, total_length as u16);
    write_u16(packet, IDENTIFICATION_OFFSET, header.identification);
    write_u16(packet, FLAGS_FRAGMENT_OFFSET, header.flags_fragment_offset);
    packet[TTL_OFFSET] = header.ttl;
    packet[PROTOCOL_OFFSET] = header.protocol;
    packet[SOURCE_OFFSET..SOURCE_OFFSET + 4].copy_from_slice(&header.source);
    packet[DESTINATION_OFFSET..DESTINATION_OFFSET + 4].copy_from_slice(&header.destination);

    let checksum = internet_checksum(&packet[..MINIMUM_HEADER_LENGTH]);
    write_u16(packet, HEADER_CHECKSUM_OFFSET, checksum);
    packet[MINIMUM_HEADER_LENGTH..].copy_from_slice(payload);
    Ok(total_length)
}

fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_be_bytes([bytes[offset], bytes[offset + 1]])
}

fn write_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_be_bytes());
}

fn read_address(bytes: &[u8], offset: usize) -> [u8; 4] {
    bytes[offset..offset + 4]
        .try_into()
        .expect("address range has a fixed length")
}

#[cfg(test)]
mod tests {
    use super::*;

    const SOURCE: [u8; 4] = [192, 168, 0, 1];
    const DESTINATION: [u8; 4] = [192, 168, 0, 199];

    fn example_header() -> Header {
        Header {
            dscp_ecn: 0,
            identification: 0,
            flags_fragment_offset: FLAG_DONT_FRAGMENT,
            ttl: 64,
            protocol: PROTOCOL_UDP,
            source: SOURCE,
            destination: DESTINATION,
        }
    }

    #[test]
    fn checksum_matches_a_known_ipv4_header() {
        let bytes = [
            0x45, 0x00, 0x00, 0x73, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00, 0xc0, 0xa8,
            0x00, 0x01, 0xc0, 0xa8, 0x00, 0xc7,
        ];
        assert_eq!(internet_checksum(&bytes), 0xb861);

        let mut with_checksum = bytes;
        with_checksum[10..12].copy_from_slice(&0xb861_u16.to_be_bytes());
        assert_eq!(internet_checksum(&with_checksum), 0);
    }

    #[test]
    fn minimum_header_packet_round_trips_and_ignores_trailing_storage() {
        let payload = [0x5a; 95];
        let mut output = [0xcc; 128];
        let length = encode_packet(example_header(), &payload, &mut output).unwrap();
        assert_eq!(length, 0x73);
        assert_eq!(
            &output[..MINIMUM_HEADER_LENGTH],
            &[
                0x45, 0x00, 0x00, 0x73, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0xb8, 0x61, 0xc0, 0xa8,
                0x00, 0x01, 0xc0, 0xa8, 0x00, 0xc7,
            ]
        );

        let packet = Packet::parse(&output).unwrap();
        assert_eq!(packet.total_length(), length);
        assert_eq!(packet.header_length(), MINIMUM_HEADER_LENGTH);
        assert_eq!(packet.dscp_ecn(), 0);
        assert_eq!(packet.identification(), 0);
        assert!(packet.dont_fragment());
        assert!(!packet.is_fragmented());
        assert_eq!(packet.ttl(), 64);
        assert_eq!(packet.protocol(), PROTOCOL_UDP);
        assert_eq!(packet.header_checksum(), 0xb861);
        assert_eq!(packet.source(), SOURCE);
        assert_eq!(packet.destination(), DESTINATION);
        assert!(packet.options().is_empty());
        assert_eq!(packet.payload(), payload);
        assert_eq!(packet.bytes(), &output[..length]);
    }

    #[test]
    fn parser_accepts_options_and_odd_payload_length() {
        let mut bytes = [
            0x46,
            0x00,
            0x00,
            0x1b,
            0x12,
            0x34,
            0x20,
            0x01,
            0x20,
            PROTOCOL_ICMP,
            0x00,
            0x00,
            10,
            24,
            0,
            1,
            10,
            24,
            0,
            2,
            0x01,
            0x01,
            0x00,
            0x00,
            0xaa,
            0xbb,
            0xcc,
        ];
        let checksum = internet_checksum(&bytes[..24]);
        bytes[10..12].copy_from_slice(&checksum.to_be_bytes());

        let packet = Packet::parse(&bytes).unwrap();
        assert_eq!(packet.header_length(), 24);
        assert_eq!(packet.options(), [0x01, 0x01, 0x00, 0x00]);
        assert_eq!(packet.payload(), [0xaa, 0xbb, 0xcc]);
        assert!(packet.more_fragments());
        assert_eq!(packet.fragment_offset(), 1);
        assert!(packet.is_fragmented());
    }

    #[test]
    fn parser_rejects_invalid_boundaries_and_checksum() {
        assert_eq!(
            Packet::parse(&[0; MINIMUM_HEADER_LENGTH - 1]),
            Err(ParseError::TruncatedMinimumHeader)
        );

        let mut bytes = [0_u8; MINIMUM_HEADER_LENGTH];
        bytes[0] = 0x65;
        assert_eq!(
            Packet::parse(&bytes),
            Err(ParseError::UnsupportedVersion(6))
        );

        bytes[0] = 0x44;
        assert_eq!(
            Packet::parse(&bytes),
            Err(ParseError::InvalidHeaderLength(4))
        );

        bytes[0] = 0x46;
        assert_eq!(
            Packet::parse(&bytes),
            Err(ParseError::TruncatedHeader {
                header_length: 24,
                available: 20,
            })
        );

        bytes[0] = 0x45;
        write_u16(&mut bytes, TOTAL_LENGTH_OFFSET, 19);
        assert_eq!(
            Packet::parse(&bytes),
            Err(ParseError::TotalLengthSmallerThanHeader {
                total_length: 19,
                header_length: 20,
            })
        );

        write_u16(&mut bytes, TOTAL_LENGTH_OFFSET, 21);
        assert_eq!(
            Packet::parse(&bytes),
            Err(ParseError::TruncatedPacket {
                total_length: 21,
                available: 20,
            })
        );

        write_u16(&mut bytes, TOTAL_LENGTH_OFFSET, 20);
        assert_eq!(
            Packet::parse(&bytes),
            Err(ParseError::InvalidHeaderChecksum)
        );
    }

    #[test]
    fn encoder_reports_capacity_length_and_reserved_flag_errors() {
        let mut short = [0; MINIMUM_HEADER_LENGTH - 1];
        assert_eq!(
            encode_packet(example_header(), &[], &mut short),
            Err(EncodeError::OutputTooSmall {
                required: MINIMUM_HEADER_LENGTH,
                available: MINIMUM_HEADER_LENGTH - 1,
            })
        );

        let mut output = vec![0; usize::from(u16::MAX) + 1];
        assert_eq!(
            encode_packet(
                example_header(),
                &[0; 1],
                &mut output[..MINIMUM_HEADER_LENGTH]
            ),
            Err(EncodeError::OutputTooSmall {
                required: MINIMUM_HEADER_LENGTH + 1,
                available: MINIMUM_HEADER_LENGTH,
            })
        );
        assert_eq!(
            encode_packet(example_header(), &output[..usize::from(u16::MAX)], &mut []),
            Err(EncodeError::PacketTooLong(
                usize::from(u16::MAX) + MINIMUM_HEADER_LENGTH
            ))
        );

        let mut reserved = example_header();
        reserved.flags_fragment_offset = FLAG_RESERVED;
        assert_eq!(
            encode_packet(reserved, &[], &mut output),
            Err(EncodeError::ReservedFlagSet)
        );
    }
}
