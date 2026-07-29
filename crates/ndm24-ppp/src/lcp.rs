//! Allocation-free RFC 1661 Link Control Protocol packet codec.

pub const PROTOCOL: u16 = 0xc021;
pub const HEADER_LENGTH: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Code {
    ConfigureRequest = 1,
    ConfigureAck = 2,
    ConfigureNak = 3,
    ConfigureReject = 4,
    TerminateRequest = 5,
    TerminateAck = 6,
    CodeReject = 7,
    ProtocolReject = 8,
    EchoRequest = 9,
    EchoReply = 10,
    DiscardRequest = 11,
}

impl Code {
    pub fn from_octet(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::ConfigureRequest),
            2 => Some(Self::ConfigureAck),
            3 => Some(Self::ConfigureNak),
            4 => Some(Self::ConfigureReject),
            5 => Some(Self::TerminateRequest),
            6 => Some(Self::TerminateAck),
            7 => Some(Self::CodeReject),
            8 => Some(Self::ProtocolReject),
            9 => Some(Self::EchoRequest),
            10 => Some(Self::EchoReply),
            11 => Some(Self::DiscardRequest),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum OptionType {
    MaximumReceiveUnit = 1,
    AsyncControlCharacterMap = 2,
    AuthenticationProtocol = 3,
    QualityProtocol = 4,
    MagicNumber = 5,
    ProtocolFieldCompression = 7,
    AddressControlFieldCompression = 8,
}

impl OptionType {
    pub fn from_octet(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::MaximumReceiveUnit),
            2 => Some(Self::AsyncControlCharacterMap),
            3 => Some(Self::AuthenticationProtocol),
            4 => Some(Self::QualityProtocol),
            5 => Some(Self::MagicNumber),
            7 => Some(Self::ProtocolFieldCompression),
            8 => Some(Self::AddressControlFieldCompression),
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
pub enum EncodeError {
    DataTooLong { data_length: usize },
    OutputTooSmall { required: usize, available: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Packet<'a> {
    pub code: u8,
    pub identifier: u8,
    pub data: &'a [u8],
}

impl<'a> Packet<'a> {
    /// Parses one LCP packet from a PPP Information field.
    ///
    /// Octets after the declared Length are padding and are intentionally
    /// ignored, as required by RFC 1661 section 5.
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

    pub fn configuration_options(&self) -> ConfigurationOptions<'a> {
        ConfigurationOptions {
            remaining: self.data,
            failed: false,
        }
    }

    /// Configure-Ack is valid only when Identifier and Options exactly match
    /// the Configure-Request that it acknowledges.
    pub fn exactly_acknowledges(&self, identifier: u8, options: &[u8]) -> bool {
        self.known_code() == Some(Code::ConfigureAck)
            && self.identifier == identifier
            && self.data == options
    }
}

pub fn encode_into(
    code: u8,
    identifier: u8,
    data: &[u8],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    let required = HEADER_LENGTH
        .checked_add(data.len())
        .filter(|length| *length <= usize::from(u16::MAX))
        .ok_or(EncodeError::DataTooLong {
            data_length: data.len(),
        })?;
    if output.len() < required {
        return Err(EncodeError::OutputTooSmall {
            required,
            available: output.len(),
        });
    }

    output[0] = code;
    output[1] = identifier;
    output[2..4].copy_from_slice(&(required as u16).to_be_bytes());
    output[4..required].copy_from_slice(data);
    Ok(required)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OptionParseError {
    HeaderTruncated {
        remaining_length: usize,
    },
    InvalidLength {
        option_type: u8,
        declared_length: usize,
        remaining_length: usize,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConfigurationOption<'a> {
    pub option_type: u8,
    pub data: &'a [u8],
    pub encoded: &'a [u8],
}

impl ConfigurationOption<'_> {
    pub fn known_type(&self) -> Option<OptionType> {
        OptionType::from_octet(self.option_type)
    }
}

#[derive(Debug, Clone)]
pub struct ConfigurationOptions<'a> {
    remaining: &'a [u8],
    failed: bool,
}

impl<'a> Iterator for ConfigurationOptions<'a> {
    type Item = Result<ConfigurationOption<'a>, OptionParseError>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.failed || self.remaining.is_empty() {
            return None;
        }
        if self.remaining.len() < 2 {
            self.failed = true;
            return Some(Err(OptionParseError::HeaderTruncated {
                remaining_length: self.remaining.len(),
            }));
        }

        let option_type = self.remaining[0];
        let declared_length = usize::from(self.remaining[1]);
        if declared_length < 2 || declared_length > self.remaining.len() {
            self.failed = true;
            return Some(Err(OptionParseError::InvalidLength {
                option_type,
                declared_length,
                remaining_length: self.remaining.len(),
            }));
        }

        let (encoded, remaining) = self.remaining.split_at(declared_length);
        self.remaining = remaining;
        Some(Ok(ConfigurationOption {
            option_type,
            data: &encoded[2..],
            encoded,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_empty_configure_request() {
        let packet = Packet::parse(&[1, 0x2a, 0, 4]).unwrap();
        assert_eq!(packet.known_code(), Some(Code::ConfigureRequest));
        assert_eq!(packet.identifier, 0x2a);
        assert!(packet.data.is_empty());
        assert_eq!(packet.configuration_options().count(), 0);
    }

    #[test]
    fn packet_length_uses_network_byte_order_and_ignores_padding() {
        let packet = Packet::parse(&[1, 7, 0, 4, 0xaa, 0xbb]).unwrap();
        assert_eq!(packet.identifier, 7);
        assert!(packet.data.is_empty());
    }

    #[test]
    fn rejects_truncated_and_invalid_packet_lengths() {
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
            Packet::parse(&[1, 2, 0, 5]),
            Err(ParseError::InvalidLength {
                declared_length: 5,
                available_length: 4,
            })
        );
    }

    #[test]
    fn preserves_unknown_code_for_code_reject() {
        let packet = Packet::parse(&[0xfe, 1, 0, 4]).unwrap();
        assert_eq!(packet.code, 0xfe);
        assert_eq!(packet.known_code(), None);
    }

    #[test]
    fn iterates_known_and_unknown_configuration_options_without_copying() {
        let input = [
            1, 9, 0, 20, // Configure-Request
            1, 4, 0x05, 0xdc, // MRU 1500
            2, 6, 0xff, 0xff, 0xff, 0xff, // ACCM
            7, 2, // PFC
            0xfe, 4, 0xaa, 0xbb, // unknown
        ];
        let packet = Packet::parse(&input).unwrap();
        let options = packet
            .configuration_options()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();

        assert_eq!(options.len(), 4);
        assert_eq!(
            options[0].known_type(),
            Some(OptionType::MaximumReceiveUnit)
        );
        assert_eq!(options[0].data, &[0x05, 0xdc]);
        assert_eq!(
            options[1].known_type(),
            Some(OptionType::AsyncControlCharacterMap)
        );
        assert_eq!(options[1].data, &[0xff, 0xff, 0xff, 0xff]);
        assert_eq!(
            options[2].known_type(),
            Some(OptionType::ProtocolFieldCompression)
        );
        assert!(options[2].data.is_empty());
        assert_eq!(options[3].known_type(), None);
        assert_eq!(options[3].encoded, &[0xfe, 4, 0xaa, 0xbb]);
    }

    #[test]
    fn option_iterator_stops_after_the_first_malformed_option() {
        let packet = Packet::parse(&[1, 1, 0, 9, 1, 4, 5, 0xdc, 7]).unwrap();
        let mut options = packet.configuration_options();
        assert!(options.next().unwrap().is_ok());
        assert_eq!(
            options.next(),
            Some(Err(OptionParseError::HeaderTruncated {
                remaining_length: 1
            }))
        );
        assert_eq!(options.next(), None);
    }

    #[test]
    fn rejects_zero_one_and_overlong_option_lengths() {
        for (encoded, declared_length) in [(&[1, 0][..], 0), (&[1, 1][..], 1), (&[1, 4, 0][..], 4)]
        {
            let packet_bytes = [
                &[1, 1, 0, (HEADER_LENGTH + encoded.len()) as u8][..],
                encoded,
            ]
            .concat();
            let packet = Packet::parse(&packet_bytes).unwrap();
            assert_eq!(
                packet.configuration_options().next(),
                Some(Err(OptionParseError::InvalidLength {
                    option_type: 1,
                    declared_length,
                    remaining_length: encoded.len(),
                }))
            );
        }
    }

    #[test]
    fn allocation_free_encoder_round_trips() {
        let options = [1, 4, 0x05, 0xdc, 7, 2];
        let mut output = [0xcc; 16];
        let length =
            encode_into(Code::ConfigureRequest as u8, 0x33, &options, &mut output).unwrap();
        assert_eq!(length, 10);
        assert_eq!(&output[..length], &[1, 0x33, 0, 10, 1, 4, 5, 0xdc, 7, 2]);
        assert_eq!(output[length], 0xcc);

        let packet = Packet::parse(&output[..length]).unwrap();
        assert_eq!(packet.data, options);
    }

    #[test]
    fn encoder_reports_output_and_u16_length_limits() {
        assert_eq!(
            encode_into(1, 1, &[1, 2], &mut [0; 5]),
            Err(EncodeError::OutputTooSmall {
                required: 6,
                available: 5,
            })
        );
        assert_eq!(
            encode_into(1, 1, &vec![0; usize::from(u16::MAX) - 3], &mut []),
            Err(EncodeError::DataTooLong {
                data_length: usize::from(u16::MAX) - 3,
            })
        );
    }

    #[test]
    fn configure_ack_requires_exact_identifier_and_options() {
        let packet = Packet::parse(&[2, 7, 0, 8, 1, 4, 5, 0xdc]).unwrap();
        assert!(packet.exactly_acknowledges(7, &[1, 4, 5, 0xdc]));
        assert!(!packet.exactly_acknowledges(8, &[1, 4, 5, 0xdc]));
        assert!(!packet.exactly_acknowledges(7, &[1, 4, 5, 0xdb]));
    }
}
