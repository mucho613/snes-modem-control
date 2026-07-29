//! Allocation-free RFC 1334 Password Authentication Protocol packet codec.
//!
//! PAP credentials are carried in plaintext on the link. Callers should not
//! include packet data in ordinary diagnostics or logs.

pub const PROTOCOL: u16 = 0xc023;
pub const HEADER_LENGTH: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Code {
    AuthenticateRequest = 1,
    AuthenticateAck = 2,
    AuthenticateNak = 3,
}

impl Code {
    pub fn from_octet(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::AuthenticateRequest),
            2 => Some(Self::AuthenticateAck),
            3 => Some(Self::AuthenticateNak),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    HeaderTruncated {
        actual_length: usize,
    },
    InvalidLength {
        declared_length: usize,
        available_length: usize,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DataParseError {
    WrongCode {
        actual: u8,
    },
    PeerIdLengthMissing,
    PeerIdTruncated {
        declared_length: usize,
        available_length: usize,
    },
    PasswordLengthMissing,
    PasswordTruncated {
        declared_length: usize,
        available_length: usize,
    },
    MessageLengthMissing,
    MessageTruncated {
        declared_length: usize,
        available_length: usize,
    },
    TrailingData {
        trailing_length: usize,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    FieldTooLong { field: Field, length: usize },
    InvalidReplyCode { actual: Code },
    PacketTooLong { data_length: usize },
    OutputTooSmall { required: usize, available: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Field {
    PeerId,
    Password,
    Message,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Packet<'a> {
    pub code: u8,
    pub identifier: u8,
    pub data: &'a [u8],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AuthenticateRequest<'a> {
    pub peer_id: &'a [u8],
    pub password: &'a [u8],
}

impl<'a> Packet<'a> {
    /// Parses one PAP packet from a PPP Information field.
    ///
    /// Octets after the declared Length are padding and are ignored.
    pub fn parse(input: &'a [u8]) -> Result<Self, ParseError> {
        if input.len() < HEADER_LENGTH {
            return Err(ParseError::HeaderTruncated {
                actual_length: input.len(),
            });
        }

        let declared_length = usize::from(u16::from_be_bytes([input[2], input[3]]));
        if declared_length < HEADER_LENGTH || declared_length > input.len() {
            return Err(ParseError::InvalidLength {
                declared_length,
                available_length: input.len(),
            });
        }

        Ok(Self {
            code: input[0],
            identifier: input[1],
            data: &input[HEADER_LENGTH..declared_length],
        })
    }

    pub fn known_code(&self) -> Option<Code> {
        Code::from_octet(self.code)
    }

    pub fn authenticate_request(&self) -> Result<AuthenticateRequest<'a>, DataParseError> {
        if self.known_code() != Some(Code::AuthenticateRequest) {
            return Err(DataParseError::WrongCode { actual: self.code });
        }

        let (&peer_id_length, remaining) = self
            .data
            .split_first()
            .ok_or(DataParseError::PeerIdLengthMissing)?;
        let peer_id_length = usize::from(peer_id_length);
        if remaining.len() < peer_id_length {
            return Err(DataParseError::PeerIdTruncated {
                declared_length: peer_id_length,
                available_length: remaining.len(),
            });
        }
        let (peer_id, remaining) = remaining.split_at(peer_id_length);

        let (&password_length, remaining) = remaining
            .split_first()
            .ok_or(DataParseError::PasswordLengthMissing)?;
        let password_length = usize::from(password_length);
        if remaining.len() < password_length {
            return Err(DataParseError::PasswordTruncated {
                declared_length: password_length,
                available_length: remaining.len(),
            });
        }
        let (password, trailing) = remaining.split_at(password_length);
        if !trailing.is_empty() {
            return Err(DataParseError::TrailingData {
                trailing_length: trailing.len(),
            });
        }

        Ok(AuthenticateRequest { peer_id, password })
    }

    pub fn reply_message(&self) -> Result<&'a [u8], DataParseError> {
        if !matches!(
            self.known_code(),
            Some(Code::AuthenticateAck | Code::AuthenticateNak)
        ) {
            return Err(DataParseError::WrongCode { actual: self.code });
        }

        let (&message_length, remaining) = self
            .data
            .split_first()
            .ok_or(DataParseError::MessageLengthMissing)?;
        let message_length = usize::from(message_length);
        if remaining.len() < message_length {
            return Err(DataParseError::MessageTruncated {
                declared_length: message_length,
                available_length: remaining.len(),
            });
        }
        let (message, trailing) = remaining.split_at(message_length);
        if !trailing.is_empty() {
            return Err(DataParseError::TrailingData {
                trailing_length: trailing.len(),
            });
        }
        Ok(message)
    }
}

pub fn encode_authenticate_request(
    identifier: u8,
    peer_id: &[u8],
    password: &[u8],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    require_u8_length(Field::PeerId, peer_id)?;
    require_u8_length(Field::Password, password)?;

    let data_length = 2_usize
        .checked_add(peer_id.len())
        .and_then(|length| length.checked_add(password.len()))
        .ok_or(EncodeError::PacketTooLong {
            data_length: usize::MAX,
        })?;
    let required = packet_length(data_length, output.len())?;

    output[0] = Code::AuthenticateRequest as u8;
    output[1] = identifier;
    output[2..4].copy_from_slice(&(required as u16).to_be_bytes());
    output[4] = peer_id.len() as u8;
    let peer_id_end = 5 + peer_id.len();
    output[5..peer_id_end].copy_from_slice(peer_id);
    output[peer_id_end] = password.len() as u8;
    output[peer_id_end + 1..required].copy_from_slice(password);
    Ok(required)
}

pub fn encode_reply(
    code: Code,
    identifier: u8,
    message: &[u8],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    if !matches!(code, Code::AuthenticateAck | Code::AuthenticateNak) {
        return Err(EncodeError::InvalidReplyCode { actual: code });
    }
    require_u8_length(Field::Message, message)?;

    let data_length = 1 + message.len();
    let required = packet_length(data_length, output.len())?;
    output[0] = code as u8;
    output[1] = identifier;
    output[2..4].copy_from_slice(&(required as u16).to_be_bytes());
    output[4] = message.len() as u8;
    output[5..required].copy_from_slice(message);
    Ok(required)
}

fn require_u8_length(field: Field, value: &[u8]) -> Result<(), EncodeError> {
    if value.len() > usize::from(u8::MAX) {
        return Err(EncodeError::FieldTooLong {
            field,
            length: value.len(),
        });
    }
    Ok(())
}

fn packet_length(data_length: usize, available: usize) -> Result<usize, EncodeError> {
    let required = HEADER_LENGTH
        .checked_add(data_length)
        .filter(|length| *length <= usize::from(u16::MAX))
        .ok_or(EncodeError::PacketTooLong { data_length })?;
    if available < required {
        return Err(EncodeError::OutputTooSmall {
            required,
            available,
        });
    }
    Ok(required)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authenticate_request_round_trips() {
        let mut encoded = [0; 32];
        let length =
            encode_authenticate_request(0x2a, b"ndm24", b"ndm24-test", &mut encoded).unwrap();
        assert_eq!(
            &encoded[..length],
            b"\x01\x2a\x00\x15\x05ndm24\x0andm24-test"
        );

        let packet = Packet::parse(&encoded[..length]).unwrap();
        assert_eq!(packet.known_code(), Some(Code::AuthenticateRequest));
        assert_eq!(packet.identifier, 0x2a);
        assert_eq!(
            packet.authenticate_request().unwrap(),
            AuthenticateRequest {
                peer_id: b"ndm24",
                password: b"ndm24-test",
            }
        );
    }

    #[test]
    fn ack_and_nak_messages_round_trip() {
        for (code, message) in [
            (Code::AuthenticateAck, b"Welcome".as_slice()),
            (Code::AuthenticateNak, b"Denied".as_slice()),
        ] {
            let mut encoded = [0; 32];
            let length = encode_reply(code, 7, message, &mut encoded).unwrap();
            let packet = Packet::parse(&encoded[..length]).unwrap();
            assert_eq!(packet.known_code(), Some(code));
            assert_eq!(packet.identifier, 7);
            assert_eq!(packet.reply_message().unwrap(), message);
        }
    }

    #[test]
    fn packet_length_is_big_endian_and_padding_is_ignored() {
        let packet = Packet::parse(&[2, 9, 0, 6, 1, b'Y', 0xaa, 0xbb]).unwrap();
        assert_eq!(packet.identifier, 9);
        assert_eq!(packet.reply_message().unwrap(), b"Y");
    }

    #[test]
    fn packet_rejects_truncated_header_and_invalid_lengths() {
        assert_eq!(
            Packet::parse(&[1, 2, 0]),
            Err(ParseError::HeaderTruncated { actual_length: 3 })
        );
        assert_eq!(
            Packet::parse(&[1, 2, 0, 3]),
            Err(ParseError::InvalidLength {
                declared_length: 3,
                available_length: 4,
            })
        );
        assert_eq!(
            Packet::parse(&[1, 2, 0, 8, 0]),
            Err(ParseError::InvalidLength {
                declared_length: 8,
                available_length: 5,
            })
        );
    }

    #[test]
    fn request_rejects_each_truncated_or_extra_field() {
        assert_eq!(
            Packet::parse(&[1, 1, 0, 4]).unwrap().authenticate_request(),
            Err(DataParseError::PeerIdLengthMissing)
        );
        assert_eq!(
            Packet::parse(&[1, 1, 0, 7, 3, b'a', b'b'])
                .unwrap()
                .authenticate_request(),
            Err(DataParseError::PeerIdTruncated {
                declared_length: 3,
                available_length: 2,
            })
        );
        assert_eq!(
            Packet::parse(&[1, 1, 0, 6, 1, b'a'])
                .unwrap()
                .authenticate_request(),
            Err(DataParseError::PasswordLengthMissing)
        );
        assert_eq!(
            Packet::parse(&[1, 1, 0, 8, 1, b'a', 2, b'x'])
                .unwrap()
                .authenticate_request(),
            Err(DataParseError::PasswordTruncated {
                declared_length: 2,
                available_length: 1,
            })
        );
        assert_eq!(
            Packet::parse(&[1, 1, 0, 9, 1, b'a', 1, b'x', 0])
                .unwrap()
                .authenticate_request(),
            Err(DataParseError::TrailingData { trailing_length: 1 })
        );
    }

    #[test]
    fn reply_rejects_wrong_code_and_invalid_message_fields() {
        let request = Packet::parse(&[1, 1, 0, 6, 0, 0]).unwrap();
        assert_eq!(
            request.reply_message(),
            Err(DataParseError::WrongCode { actual: 1 })
        );
        let empty = Packet::parse(&[2, 1, 0, 4]).unwrap();
        assert_eq!(
            empty.reply_message(),
            Err(DataParseError::MessageLengthMissing)
        );
        let truncated = Packet::parse(&[2, 1, 0, 6, 2, b'x']).unwrap();
        assert_eq!(
            truncated.reply_message(),
            Err(DataParseError::MessageTruncated {
                declared_length: 2,
                available_length: 1,
            })
        );
        let trailing = Packet::parse(&[2, 1, 0, 7, 1, b'x', 0]).unwrap();
        assert_eq!(
            trailing.reply_message(),
            Err(DataParseError::TrailingData { trailing_length: 1 })
        );
    }

    #[test]
    fn encoder_reports_field_and_output_limits() {
        let too_long = [0; 256];
        assert_eq!(
            encode_authenticate_request(1, &too_long, b"x", &mut [0; 512]),
            Err(EncodeError::FieldTooLong {
                field: Field::PeerId,
                length: 256,
            })
        );
        assert_eq!(
            encode_reply(Code::AuthenticateAck, 1, &too_long, &mut [0; 512]),
            Err(EncodeError::FieldTooLong {
                field: Field::Message,
                length: 256,
            })
        );
        assert_eq!(
            encode_authenticate_request(1, b"id", b"pw", &mut [0; 8]),
            Err(EncodeError::OutputTooSmall {
                required: 10,
                available: 8,
            })
        );
    }

    #[test]
    fn reply_encoder_rejects_request_code() {
        assert_eq!(
            encode_reply(
                Code::AuthenticateRequest,
                1,
                b"",
                &mut [0; HEADER_LENGTH + 1],
            ),
            Err(EncodeError::InvalidReplyCode {
                actual: Code::AuthenticateRequest,
            })
        );
    }
}
