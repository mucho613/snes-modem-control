//! Allocation-free DNS query encoding and minimal A-record response parsing.

pub const HEADER_LENGTH: usize = 12;
pub const TYPE_A: u16 = 1;
pub const CLASS_IN: u16 = 1;
pub const MAX_LABEL_LENGTH: usize = 63;
pub const MAX_NAME_LENGTH: usize = 253;

const FLAG_RESPONSE: u16 = 0x8000;
const FLAG_RECURSION_DESIRED: u16 = 0x0100;
const FLAG_TRUNCATED: u16 = 0x0200;
const OPCODE_MASK: u16 = 0x7800;
const RESPONSE_CODE_MASK: u16 = 0x000f;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    EmptyName,
    NameTooLong(usize),
    EmptyLabel,
    LabelTooLong(usize),
    NonAscii,
    InvalidCharacter(u8),
    OutputTooSmall { required: usize, available: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    Truncated,
    IdentifierMismatch { expected: u16, received: u16 },
    NotResponse,
    UnsupportedOpcode(u8),
    TruncatedResponse,
    ResponseCode(u8),
    NoQuestion,
    NoAnswer,
    MalformedName,
    NoIpv4Answer,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AResponse {
    pub response_code: u8,
    pub answer_count: u16,
    pub address: [u8; 4],
}

pub fn encode_a_query(
    identifier: u16,
    name: &str,
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    let name = name.strip_suffix('.').unwrap_or(name);
    if name.is_empty() {
        return Err(EncodeError::EmptyName);
    }
    if name.len() > MAX_NAME_LENGTH {
        return Err(EncodeError::NameTooLong(name.len()));
    }
    if !name.is_ascii() {
        return Err(EncodeError::NonAscii);
    }

    let mut encoded_name_length = 1;
    for label in name.split('.') {
        if label.is_empty() {
            return Err(EncodeError::EmptyLabel);
        }
        if label.len() > MAX_LABEL_LENGTH {
            return Err(EncodeError::LabelTooLong(label.len()));
        }
        if let Some(byte) = label
            .bytes()
            .find(|byte| !byte.is_ascii_alphanumeric() && *byte != b'-')
        {
            return Err(EncodeError::InvalidCharacter(byte));
        }
        encoded_name_length += 1 + label.len();
    }

    let required = HEADER_LENGTH + encoded_name_length + 4;
    if output.len() < required {
        return Err(EncodeError::OutputTooSmall {
            required,
            available: output.len(),
        });
    }

    let packet = &mut output[..required];
    packet.fill(0);
    write_u16(packet, 0, identifier);
    write_u16(packet, 2, FLAG_RECURSION_DESIRED);
    write_u16(packet, 4, 1);

    let mut offset = HEADER_LENGTH;
    for label in name.split('.') {
        packet[offset] = label.len() as u8;
        offset += 1;
        packet[offset..offset + label.len()].copy_from_slice(label.as_bytes());
        offset += label.len();
    }
    packet[offset] = 0;
    offset += 1;
    write_u16(packet, offset, TYPE_A);
    write_u16(packet, offset + 2, CLASS_IN);
    Ok(required)
}

pub fn parse_a_response(identifier: u16, bytes: &[u8]) -> Result<AResponse, ParseError> {
    if bytes.len() < HEADER_LENGTH {
        return Err(ParseError::Truncated);
    }
    let received_identifier = read_u16(bytes, 0);
    if received_identifier != identifier {
        return Err(ParseError::IdentifierMismatch {
            expected: identifier,
            received: received_identifier,
        });
    }

    let flags = read_u16(bytes, 2);
    if flags & FLAG_RESPONSE == 0 {
        return Err(ParseError::NotResponse);
    }
    let opcode = ((flags & OPCODE_MASK) >> 11) as u8;
    if opcode != 0 {
        return Err(ParseError::UnsupportedOpcode(opcode));
    }
    if flags & FLAG_TRUNCATED != 0 {
        return Err(ParseError::TruncatedResponse);
    }
    let response_code = (flags & RESPONSE_CODE_MASK) as u8;
    if response_code != 0 {
        return Err(ParseError::ResponseCode(response_code));
    }

    let question_count = read_u16(bytes, 4);
    if question_count == 0 {
        return Err(ParseError::NoQuestion);
    }
    let answer_count = read_u16(bytes, 6);
    if answer_count == 0 {
        return Err(ParseError::NoAnswer);
    }

    let mut offset = HEADER_LENGTH;
    for _ in 0..question_count {
        offset = skip_name(bytes, offset)?;
        offset = offset.checked_add(4).ok_or(ParseError::Truncated)?;
        if offset > bytes.len() {
            return Err(ParseError::Truncated);
        }
    }

    for _ in 0..answer_count {
        offset = skip_name(bytes, offset)?;
        if bytes.len().saturating_sub(offset) < 10 {
            return Err(ParseError::Truncated);
        }
        let record_type = read_u16(bytes, offset);
        let class = read_u16(bytes, offset + 2);
        let data_length = usize::from(read_u16(bytes, offset + 8));
        offset += 10;
        if bytes.len().saturating_sub(offset) < data_length {
            return Err(ParseError::Truncated);
        }
        if record_type == TYPE_A && class == CLASS_IN && data_length == 4 {
            return Ok(AResponse {
                response_code,
                answer_count,
                address: [
                    bytes[offset],
                    bytes[offset + 1],
                    bytes[offset + 2],
                    bytes[offset + 3],
                ],
            });
        }
        offset += data_length;
    }

    Err(ParseError::NoIpv4Answer)
}

fn skip_name(bytes: &[u8], mut offset: usize) -> Result<usize, ParseError> {
    loop {
        let length = *bytes.get(offset).ok_or(ParseError::Truncated)?;
        if length == 0 {
            return Ok(offset + 1);
        }
        if length & 0xc0 == 0xc0 {
            let second = *bytes.get(offset + 1).ok_or(ParseError::Truncated)?;
            let pointer = (usize::from(length & 0x3f) << 8) | usize::from(second);
            if pointer >= bytes.len() {
                return Err(ParseError::MalformedName);
            }
            return Ok(offset + 2);
        }
        if length & 0xc0 != 0 || usize::from(length) > MAX_LABEL_LENGTH {
            return Err(ParseError::MalformedName);
        }
        offset += 1 + usize::from(length);
        if offset > bytes.len() {
            return Err(ParseError::Truncated);
        }
    }
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

    const IDENTIFIER: u16 = 0x4e44;

    fn example_response() -> Vec<u8> {
        vec![
            0x4e, 0x44, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x07, b'e',
            b'x', b'a', b'm', b'p', b'l', b'e', 0x03, b'c', b'o', b'm', 0x00, 0x00, 0x01, 0x00,
            0x01, 0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, 0x00, 0x04, 93, 184,
            216, 34,
        ]
    }

    #[test]
    fn encodes_example_a_query() {
        let mut output = [0xcc; 64];
        let length = encode_a_query(IDENTIFIER, "example.com", &mut output).unwrap();
        assert_eq!(length, 29);
        assert_eq!(
            &output[..length],
            &[
                0x4e, 0x44, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, b'e',
                b'x', b'a', b'm', b'p', b'l', b'e', 0x03, b'c', b'o', b'm', 0x00, 0x00, 0x01, 0x00,
                0x01,
            ]
        );
        assert!(output[length..].iter().all(|byte| *byte == 0xcc));
    }

    #[test]
    fn validates_query_names_and_capacity() {
        assert_eq!(
            encode_a_query(IDENTIFIER, "", &mut [0; 64]),
            Err(EncodeError::EmptyName)
        );
        assert_eq!(
            encode_a_query(IDENTIFIER, "bad..name", &mut [0; 64]),
            Err(EncodeError::EmptyLabel)
        );
        assert_eq!(
            encode_a_query(IDENTIFIER, "é.example", &mut [0; 64]),
            Err(EncodeError::NonAscii)
        );
        assert_eq!(
            encode_a_query(IDENTIFIER, "bad_name", &mut [0; 64]),
            Err(EncodeError::InvalidCharacter(b'_'))
        );
        assert_eq!(
            encode_a_query(IDENTIFIER, "example.com", &mut [0; 28]),
            Err(EncodeError::OutputTooSmall {
                required: 29,
                available: 28
            })
        );
    }

    #[test]
    fn parses_compressed_a_response() {
        assert_eq!(
            parse_a_response(IDENTIFIER, &example_response()),
            Ok(AResponse {
                response_code: 0,
                answer_count: 1,
                address: [93, 184, 216, 34],
            })
        );
    }

    #[test]
    fn skips_non_a_answers_before_the_first_a_record() {
        let mut response = example_response();
        response[7] = 2;
        let answer = response.split_off(29);
        response.extend_from_slice(&[
            0xc0, 0x0c, 0x00, 0x1c, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, 0x00, 0x10, 0, 1, 0, 2, 0,
            3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8,
        ]);
        response.extend_from_slice(&answer);
        assert_eq!(
            parse_a_response(IDENTIFIER, &response).unwrap().address,
            [93, 184, 216, 34]
        );
    }

    #[test]
    fn rejects_uncorrelated_error_and_malformed_responses() {
        let response = example_response();
        assert!(matches!(
            parse_a_response(0x1234, &response),
            Err(ParseError::IdentifierMismatch { .. })
        ));

        let mut error = response.clone();
        error[3] = 0x83;
        assert_eq!(
            parse_a_response(IDENTIFIER, &error),
            Err(ParseError::ResponseCode(3))
        );

        let mut malformed = response;
        malformed[29] = 0xff;
        malformed[30] = 0xff;
        assert_eq!(
            parse_a_response(IDENTIFIER, &malformed),
            Err(ParseError::MalformedName)
        );
    }
}
