//! Allocation-free RFC 1332 Internet Protocol Control Protocol packet codec.

pub mod client;

pub const PROTOCOL: u16 = 0x8021;
pub const IP_PROTOCOL: u16 = 0x0021;
pub const HEADER_LENGTH: usize = 4;
pub const IP_ADDRESS_OPTION_LENGTH: usize = 6;

pub type Ipv4Address = [u8; 4];

pub const UNSPECIFIED_ADDRESS: Ipv4Address = [0; 4];

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
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum OptionType {
    IpAddresses = 1,
    IpCompressionProtocol = 2,
    IpAddress = 3,
    PrimaryDnsServerAddress = 129,
    SecondaryDnsServerAddress = 131,
}

impl OptionType {
    pub fn from_octet(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::IpAddresses),
            2 => Some(Self::IpCompressionProtocol),
            3 => Some(Self::IpAddress),
            129 => Some(Self::PrimaryDnsServerAddress),
            131 => Some(Self::SecondaryDnsServerAddress),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TruncatedHeader,
    InvalidPacketLength(u16),
    TruncatedPacket { declared: usize, available: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    PacketTooLarge(usize),
    BufferTooSmall { required: usize, available: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Packet<'a> {
    pub code: u8,
    pub identifier: u8,
    pub data: &'a [u8],
}

impl<'a> Packet<'a> {
    pub fn parse(input: &'a [u8]) -> Result<Self, ParseError> {
        if input.len() < HEADER_LENGTH {
            return Err(ParseError::TruncatedHeader);
        }
        let declared = u16::from_be_bytes([input[2], input[3]]);
        if usize::from(declared) < HEADER_LENGTH {
            return Err(ParseError::InvalidPacketLength(declared));
        }
        if usize::from(declared) > input.len() {
            return Err(ParseError::TruncatedPacket {
                declared: usize::from(declared),
                available: input.len(),
            });
        }
        Ok(Self {
            code: input[0],
            identifier: input[1],
            data: &input[HEADER_LENGTH..usize::from(declared)],
        })
    }

    pub fn known_code(self) -> Option<Code> {
        Code::from_octet(self.code)
    }

    pub fn exactly_acknowledges(self, identifier: u8, options: &[u8]) -> bool {
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
    let length = HEADER_LENGTH + data.len();
    let encoded_length = u16::try_from(length).map_err(|_| EncodeError::PacketTooLarge(length))?;
    if output.len() < length {
        return Err(EncodeError::BufferTooSmall {
            required: length,
            available: output.len(),
        });
    }
    output[0] = code;
    output[1] = identifier;
    output[2..4].copy_from_slice(&encoded_length.to_be_bytes());
    output[4..length].copy_from_slice(data);
    Ok(length)
}

pub fn encode_ip_address_option(address: Ipv4Address) -> [u8; IP_ADDRESS_OPTION_LENGTH] {
    encode_address_option(OptionType::IpAddress, address)
}

pub fn encode_primary_dns_address_option(address: Ipv4Address) -> [u8; IP_ADDRESS_OPTION_LENGTH] {
    encode_address_option(OptionType::PrimaryDnsServerAddress, address)
}

pub fn encode_secondary_dns_address_option(address: Ipv4Address) -> [u8; IP_ADDRESS_OPTION_LENGTH] {
    encode_address_option(OptionType::SecondaryDnsServerAddress, address)
}

fn encode_address_option(
    option_type: OptionType,
    address: Ipv4Address,
) -> [u8; IP_ADDRESS_OPTION_LENGTH] {
    [
        option_type as u8,
        IP_ADDRESS_OPTION_LENGTH as u8,
        address[0],
        address[1],
        address[2],
        address[3],
    ]
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OptionParseError {
    TruncatedHeader { remaining: usize },
    InvalidLength(u8),
    TruncatedOption { declared: usize, remaining: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConfigurationOption<'a> {
    pub option_type: u8,
    pub data: &'a [u8],
    pub encoded: &'a [u8],
}

impl ConfigurationOption<'_> {
    pub fn known_type(self) -> Option<OptionType> {
        OptionType::from_octet(self.option_type)
    }

    pub fn ip_address(self) -> Option<Ipv4Address> {
        (self.known_type() == Some(OptionType::IpAddress) && self.data.len() == 4)
            .then(|| self.data.try_into().expect("length checked"))
    }

    pub fn primary_dns_address(self) -> Option<Ipv4Address> {
        (self.known_type() == Some(OptionType::PrimaryDnsServerAddress) && self.data.len() == 4)
            .then(|| self.data.try_into().expect("length checked"))
    }

    pub fn secondary_dns_address(self) -> Option<Ipv4Address> {
        (self.known_type() == Some(OptionType::SecondaryDnsServerAddress) && self.data.len() == 4)
            .then(|| self.data.try_into().expect("length checked"))
    }
}

pub struct ConfigurationOptions<'a> {
    remaining: &'a [u8],
}

impl<'a> Iterator for ConfigurationOptions<'a> {
    type Item = Result<ConfigurationOption<'a>, OptionParseError>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.remaining.is_empty() {
            return None;
        }
        if self.remaining.len() < 2 {
            let error = OptionParseError::TruncatedHeader {
                remaining: self.remaining.len(),
            };
            self.remaining = &[];
            return Some(Err(error));
        }
        let declared = usize::from(self.remaining[1]);
        if declared < 2 {
            let error = OptionParseError::InvalidLength(self.remaining[1]);
            self.remaining = &[];
            return Some(Err(error));
        }
        if declared > self.remaining.len() {
            let error = OptionParseError::TruncatedOption {
                declared,
                remaining: self.remaining.len(),
            };
            self.remaining = &[];
            return Some(Err(error));
        }
        let encoded = &self.remaining[..declared];
        self.remaining = &self.remaining[declared..];
        Some(Ok(ConfigurationOption {
            option_type: encoded[0],
            data: &encoded[2..],
            encoded,
        }))
    }
}

pub fn configuration_options(data: &[u8]) -> ConfigurationOptions<'_> {
    ConfigurationOptions { remaining: data }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packet_length_delimits_padding() {
        let packet = Packet::parse(&[1, 7, 0, 10, 3, 6, 10, 24, 0, 1, 0xaa]).unwrap();
        assert_eq!(packet.known_code(), Some(Code::ConfigureRequest));
        assert_eq!(packet.identifier, 7);
        assert_eq!(packet.data, [3, 6, 10, 24, 0, 1]);
    }

    #[test]
    fn packet_rejects_bad_lengths() {
        assert_eq!(Packet::parse(&[1, 1, 0]), Err(ParseError::TruncatedHeader));
        assert_eq!(
            Packet::parse(&[1, 1, 0, 3]),
            Err(ParseError::InvalidPacketLength(3))
        );
        assert_eq!(
            Packet::parse(&[1, 1, 0, 10, 3, 6]),
            Err(ParseError::TruncatedPacket {
                declared: 10,
                available: 6
            })
        );
    }

    #[test]
    fn options_are_borrowed_and_validated() {
        let encoded = [3, 6, 10, 24, 0, 1, 2, 4, 0, 0];
        let options = configuration_options(&encoded)
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(options[0].known_type(), Some(OptionType::IpAddress));
        assert_eq!(options[0].ip_address(), Some([10, 24, 0, 1]));
        assert_eq!(
            options[1].known_type(),
            Some(OptionType::IpCompressionProtocol)
        );
    }

    #[test]
    fn malformed_options_stop_the_iterator() {
        assert!(matches!(
            configuration_options(&[3]).next(),
            Some(Err(OptionParseError::TruncatedHeader { remaining: 1 }))
        ));
        assert!(matches!(
            configuration_options(&[3, 1]).next(),
            Some(Err(OptionParseError::InvalidLength(1)))
        ));
        assert!(matches!(
            configuration_options(&[3, 6, 10]).next(),
            Some(Err(OptionParseError::TruncatedOption {
                declared: 6,
                remaining: 3
            }))
        ));
    }

    #[test]
    fn encoder_builds_network_order_packet() {
        let data = encode_ip_address_option([10, 24, 0, 2]);
        let mut output = [0; 10];
        let length = encode_into(Code::ConfigureRequest as u8, 9, &data, &mut output).unwrap();
        assert_eq!(length, 10);
        assert_eq!(output, [1, 9, 0, 10, 3, 6, 10, 24, 0, 2]);
    }
}
