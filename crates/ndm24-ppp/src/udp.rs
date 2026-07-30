//! Allocation-free UDP datagram parsing and encoding for IPv4.

use crate::ipv4::PROTOCOL_UDP;

pub const HEADER_LENGTH: usize = 8;

const SOURCE_PORT_OFFSET: usize = 0;
const DESTINATION_PORT_OFFSET: usize = 2;
const LENGTH_OFFSET: usize = 4;
const CHECKSUM_OFFSET: usize = 6;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TruncatedHeader { available: usize },
    InvalidLength(usize),
    TruncatedDatagram { length: usize, available: usize },
    InvalidChecksum,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    OutputTooSmall { required: usize, available: usize },
    DatagramTooLong(usize),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Datagram<'a> {
    bytes: &'a [u8],
    checksum_present: bool,
}

impl<'a> Datagram<'a> {
    pub fn parse(
        source: [u8; 4],
        destination: [u8; 4],
        bytes: &'a [u8],
    ) -> Result<Self, ParseError> {
        if bytes.len() < HEADER_LENGTH {
            return Err(ParseError::TruncatedHeader {
                available: bytes.len(),
            });
        }

        let length = usize::from(read_u16(bytes, LENGTH_OFFSET));
        if length < HEADER_LENGTH {
            return Err(ParseError::InvalidLength(length));
        }
        if bytes.len() < length {
            return Err(ParseError::TruncatedDatagram {
                length,
                available: bytes.len(),
            });
        }

        let bytes = &bytes[..length];
        let checksum_present = read_u16(bytes, CHECKSUM_OFFSET) != 0;
        if checksum_present && udp_checksum_sum(source, destination, bytes) != u16::MAX {
            return Err(ParseError::InvalidChecksum);
        }

        Ok(Self {
            bytes,
            checksum_present,
        })
    }

    pub fn source_port(self) -> u16 {
        read_u16(self.bytes, SOURCE_PORT_OFFSET)
    }

    pub fn destination_port(self) -> u16 {
        read_u16(self.bytes, DESTINATION_PORT_OFFSET)
    }

    pub fn length(self) -> usize {
        self.bytes.len()
    }

    pub fn checksum(self) -> u16 {
        read_u16(self.bytes, CHECKSUM_OFFSET)
    }

    pub fn checksum_present(self) -> bool {
        self.checksum_present
    }

    pub fn payload(self) -> &'a [u8] {
        &self.bytes[HEADER_LENGTH..]
    }

    pub fn bytes(self) -> &'a [u8] {
        self.bytes
    }
}

pub fn encode_datagram(
    source_address: [u8; 4],
    destination_address: [u8; 4],
    source_port: u16,
    destination_port: u16,
    payload: &[u8],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    let length = HEADER_LENGTH + payload.len();
    if length > usize::from(u16::MAX) {
        return Err(EncodeError::DatagramTooLong(length));
    }
    if output.len() < length {
        return Err(EncodeError::OutputTooSmall {
            required: length,
            available: output.len(),
        });
    }

    let datagram = &mut output[..length];
    datagram[..HEADER_LENGTH].fill(0);
    write_u16(datagram, SOURCE_PORT_OFFSET, source_port);
    write_u16(datagram, DESTINATION_PORT_OFFSET, destination_port);
    write_u16(datagram, LENGTH_OFFSET, length as u16);
    datagram[HEADER_LENGTH..].copy_from_slice(payload);

    let sum = udp_checksum_sum(source_address, destination_address, datagram);
    let mut checksum = !sum;
    if checksum == 0 {
        checksum = u16::MAX;
    }
    write_u16(datagram, CHECKSUM_OFFSET, checksum);
    Ok(length)
}

fn udp_checksum_sum(source: [u8; 4], destination: [u8; 4], datagram: &[u8]) -> u16 {
    let mut sum = 0_u32;
    add_bytes(&mut sum, &source);
    add_bytes(&mut sum, &destination);
    sum += u32::from(PROTOCOL_UDP);
    sum += datagram.len() as u32;
    add_bytes(&mut sum, datagram);
    fold_sum(sum)
}

fn add_bytes(sum: &mut u32, bytes: &[u8]) {
    let mut chunks = bytes.chunks_exact(2);
    for word in &mut chunks {
        *sum += u32::from(u16::from_be_bytes([word[0], word[1]]));
    }
    if let [last] = chunks.remainder() {
        *sum += u32::from(*last) << 8;
    }
}

fn fold_sum(mut sum: u32) -> u16 {
    while sum > u32::from(u16::MAX) {
        sum = (sum & u32::from(u16::MAX)) + (sum >> 16);
    }
    sum as u16
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

    const SOURCE: [u8; 4] = [10, 24, 0, 2];
    const DESTINATION: [u8; 4] = [10, 24, 0, 1];
    const ODD_PAYLOAD: &[u8] = b"NDM24";

    #[test]
    fn odd_payload_round_trips_with_pseudo_header_checksum() {
        let mut output = [0xcc; 32];
        let length =
            encode_datagram(SOURCE, DESTINATION, 49_152, 123, ODD_PAYLOAD, &mut output).unwrap();
        assert_eq!(length, HEADER_LENGTH + ODD_PAYLOAD.len());

        let datagram = Datagram::parse(SOURCE, DESTINATION, &output).unwrap();
        assert_eq!(datagram.source_port(), 49_152);
        assert_eq!(datagram.destination_port(), 123);
        assert_eq!(datagram.length(), length);
        assert!(datagram.checksum_present());
        assert_ne!(datagram.checksum(), 0);
        assert_eq!(datagram.payload(), ODD_PAYLOAD);
        assert_eq!(datagram.bytes(), &output[..length]);
    }

    #[test]
    fn parser_accepts_zero_checksum_and_delimits_trailing_storage() {
        let mut bytes = [
            0xc0, 0x00, 0x00, 0x7b, 0x00, 0x09, 0x00, 0x00, 0x5a, 0xcc, 0xcc,
        ];
        let datagram = Datagram::parse(SOURCE, DESTINATION, &bytes).unwrap();
        assert_eq!(datagram.length(), 9);
        assert!(!datagram.checksum_present());
        assert_eq!(datagram.checksum(), 0);
        assert_eq!(datagram.payload(), [0x5a]);
        assert_eq!(datagram.bytes(), &bytes[..9]);

        bytes[8] ^= 0xff;
        assert!(Datagram::parse(SOURCE, DESTINATION, &bytes).is_ok());
    }

    #[test]
    fn parser_rejects_invalid_boundaries_and_checksum() {
        assert_eq!(
            Datagram::parse(SOURCE, DESTINATION, &[0; HEADER_LENGTH - 1]),
            Err(ParseError::TruncatedHeader {
                available: HEADER_LENGTH - 1
            })
        );

        let mut invalid_length = [0; HEADER_LENGTH];
        write_u16(&mut invalid_length, LENGTH_OFFSET, HEADER_LENGTH as u16 - 1);
        assert_eq!(
            Datagram::parse(SOURCE, DESTINATION, &invalid_length),
            Err(ParseError::InvalidLength(HEADER_LENGTH - 1))
        );

        write_u16(&mut invalid_length, LENGTH_OFFSET, HEADER_LENGTH as u16 + 1);
        assert_eq!(
            Datagram::parse(SOURCE, DESTINATION, &invalid_length),
            Err(ParseError::TruncatedDatagram {
                length: HEADER_LENGTH + 1,
                available: HEADER_LENGTH
            })
        );

        let mut encoded = [0; 32];
        let length =
            encode_datagram(SOURCE, DESTINATION, 49_152, 123, ODD_PAYLOAD, &mut encoded).unwrap();
        encoded[length - 1] ^= 1;
        assert_eq!(
            Datagram::parse(SOURCE, DESTINATION, &encoded[..length]),
            Err(ParseError::InvalidChecksum)
        );
        assert_eq!(
            Datagram::parse(DESTINATION, SOURCE, &encoded[..length]),
            Err(ParseError::InvalidChecksum)
        );
    }

    #[test]
    fn encoder_reports_capacity_and_length_errors() {
        let mut short = [0; HEADER_LENGTH - 1];
        assert_eq!(
            encode_datagram(SOURCE, DESTINATION, 1, 2, &[], &mut short),
            Err(EncodeError::OutputTooSmall {
                required: HEADER_LENGTH,
                available: HEADER_LENGTH - 1,
            })
        );

        let oversized = vec![0; usize::from(u16::MAX)];
        assert_eq!(
            encode_datagram(SOURCE, DESTINATION, 1, 2, &oversized, &mut []),
            Err(EncodeError::DatagramTooLong(
                usize::from(u16::MAX) + HEADER_LENGTH
            ))
        );
    }
}
