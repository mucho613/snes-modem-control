//! Allocation-free NTPv4 client request and server response codec.

pub const PACKET_LENGTH: usize = 48;
pub const SERVER_PORT: u16 = 123;
pub const UNIX_EPOCH_OFFSET_SECONDS: u32 = 2_208_988_800;

const LI_SHIFT: u8 = 6;
const VERSION_SHIFT: u8 = 3;
const VERSION_MASK: u8 = 0x07;
const MODE_MASK: u8 = 0x07;

const MODE_CLIENT: u8 = 3;
const MODE_SERVER: u8 = 4;
const LEAP_UNSYNCHRONIZED: u8 = 3;

const STRATUM_OFFSET: usize = 1;
const POLL_OFFSET: usize = 2;
const PRECISION_OFFSET: usize = 3;
const ROOT_DELAY_OFFSET: usize = 4;
const ROOT_DISPERSION_OFFSET: usize = 8;
const REFERENCE_ID_OFFSET: usize = 12;
const REFERENCE_TIMESTAMP_OFFSET: usize = 16;
const ORIGINATE_TIMESTAMP_OFFSET: usize = 24;
const RECEIVE_TIMESTAMP_OFFSET: usize = 32;
const TRANSMIT_TIMESTAMP_OFFSET: usize = 40;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    OutputTooSmall { required: usize, available: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseError {
    Truncated {
        available: usize,
    },
    UnsupportedVersion(u8),
    UnexpectedMode(u8),
    KissOfDeath([u8; 4]),
    InvalidStratum(u8),
    Unsynchronized,
    OriginateTimestampMismatch {
        expected: Timestamp,
        received: Timestamp,
    },
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Timestamp {
    seconds: u32,
    fraction: u32,
}

impl Timestamp {
    pub const ZERO: Self = Self {
        seconds: 0,
        fraction: 0,
    };

    pub const fn new(seconds: u32, fraction: u32) -> Self {
        Self { seconds, fraction }
    }

    pub const fn seconds(self) -> u32 {
        self.seconds
    }

    pub const fn fraction(self) -> u32 {
        self.fraction
    }

    pub const fn raw(self) -> u64 {
        ((self.seconds as u64) << 32) | self.fraction as u64
    }

    pub const fn unix_seconds(self) -> Option<u32> {
        self.seconds.checked_sub(UNIX_EPOCH_OFFSET_SECONDS)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ServerResponse {
    leap_indicator: u8,
    version: u8,
    stratum: u8,
    poll: i8,
    precision: i8,
    root_delay: u32,
    root_dispersion: u32,
    reference_id: [u8; 4],
    reference_timestamp: Timestamp,
    originate_timestamp: Timestamp,
    receive_timestamp: Timestamp,
    transmit_timestamp: Timestamp,
}

impl ServerResponse {
    pub fn parse(bytes: &[u8], expected_originate: Timestamp) -> Result<Self, ResponseError> {
        if bytes.len() < PACKET_LENGTH {
            return Err(ResponseError::Truncated {
                available: bytes.len(),
            });
        }

        let first = bytes[0];
        let leap_indicator = first >> LI_SHIFT;
        let version = (first >> VERSION_SHIFT) & VERSION_MASK;
        let mode = first & MODE_MASK;
        let stratum = bytes[STRATUM_OFFSET];
        let reference_id = read_array(bytes, REFERENCE_ID_OFFSET);
        let originate_timestamp = read_timestamp(bytes, ORIGINATE_TIMESTAMP_OFFSET);

        if !(3..=4).contains(&version) {
            return Err(ResponseError::UnsupportedVersion(version));
        }
        if mode != MODE_SERVER {
            return Err(ResponseError::UnexpectedMode(mode));
        }
        if stratum == 0 {
            return Err(ResponseError::KissOfDeath(reference_id));
        }
        if stratum > 15 {
            return Err(ResponseError::InvalidStratum(stratum));
        }
        if leap_indicator == LEAP_UNSYNCHRONIZED {
            return Err(ResponseError::Unsynchronized);
        }
        if originate_timestamp != expected_originate {
            return Err(ResponseError::OriginateTimestampMismatch {
                expected: expected_originate,
                received: originate_timestamp,
            });
        }

        Ok(Self {
            leap_indicator,
            version,
            stratum,
            poll: bytes[POLL_OFFSET] as i8,
            precision: bytes[PRECISION_OFFSET] as i8,
            root_delay: read_u32(bytes, ROOT_DELAY_OFFSET),
            root_dispersion: read_u32(bytes, ROOT_DISPERSION_OFFSET),
            reference_id,
            reference_timestamp: read_timestamp(bytes, REFERENCE_TIMESTAMP_OFFSET),
            originate_timestamp,
            receive_timestamp: read_timestamp(bytes, RECEIVE_TIMESTAMP_OFFSET),
            transmit_timestamp: read_timestamp(bytes, TRANSMIT_TIMESTAMP_OFFSET),
        })
    }

    pub const fn leap_indicator(self) -> u8 {
        self.leap_indicator
    }

    pub const fn version(self) -> u8 {
        self.version
    }

    pub const fn stratum(self) -> u8 {
        self.stratum
    }

    pub const fn poll(self) -> i8 {
        self.poll
    }

    pub const fn precision(self) -> i8 {
        self.precision
    }

    pub const fn root_delay(self) -> u32 {
        self.root_delay
    }

    pub const fn root_dispersion(self) -> u32 {
        self.root_dispersion
    }

    pub const fn reference_id(self) -> [u8; 4] {
        self.reference_id
    }

    pub const fn reference_timestamp(self) -> Timestamp {
        self.reference_timestamp
    }

    pub const fn originate_timestamp(self) -> Timestamp {
        self.originate_timestamp
    }

    pub const fn receive_timestamp(self) -> Timestamp {
        self.receive_timestamp
    }

    pub const fn transmit_timestamp(self) -> Timestamp {
        self.transmit_timestamp
    }
}

pub fn encode_client_request(
    transmit_timestamp: Timestamp,
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    if output.len() < PACKET_LENGTH {
        return Err(EncodeError::OutputTooSmall {
            required: PACKET_LENGTH,
            available: output.len(),
        });
    }

    let packet = &mut output[..PACKET_LENGTH];
    packet.fill(0);
    packet[0] = (4 << VERSION_SHIFT) | MODE_CLIENT;
    write_timestamp(packet, TRANSMIT_TIMESTAMP_OFFSET, transmit_timestamp);
    Ok(PACKET_LENGTH)
}

fn read_timestamp(bytes: &[u8], offset: usize) -> Timestamp {
    Timestamp::new(read_u32(bytes, offset), read_u32(bytes, offset + 4))
}

fn write_timestamp(bytes: &mut [u8], offset: usize, timestamp: Timestamp) {
    write_u32(bytes, offset, timestamp.seconds());
    write_u32(bytes, offset + 4, timestamp.fraction());
}

fn read_array(bytes: &[u8], offset: usize) -> [u8; 4] {
    [
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
    ]
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_be_bytes(read_array(bytes, offset))
}

fn write_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    const COOKIE: Timestamp = Timestamp::new(0x4e44_4d24, 1);
    const SERVER_TRANSMIT: Timestamp = Timestamp::new(0xe8fe_6f80, 0x8000_0000);

    #[test]
    fn client_request_is_zeroed_and_carries_the_cookie() {
        let mut output = [0xcc; PACKET_LENGTH + 4];
        let length = encode_client_request(COOKIE, &mut output).unwrap();

        assert_eq!(length, PACKET_LENGTH);
        assert_eq!(output[0], 0x23);
        assert!(
            output[1..TRANSMIT_TIMESTAMP_OFFSET]
                .iter()
                .all(|byte| *byte == 0)
        );
        assert_eq!(read_timestamp(&output, TRANSMIT_TIMESTAMP_OFFSET), COOKIE);
        assert_eq!(&output[PACKET_LENGTH..], &[0xcc; 4]);
    }

    #[test]
    fn parses_correlated_server_response_and_delimits_extensions() {
        let mut bytes = [0xcc; PACKET_LENGTH + 8];
        bytes[..PACKET_LENGTH].fill(0);
        bytes[0] = 0x24;
        bytes[STRATUM_OFFSET] = 2;
        bytes[POLL_OFFSET] = 6;
        bytes[PRECISION_OFFSET] = (-20_i8) as u8;
        write_u32(&mut bytes, ROOT_DELAY_OFFSET, 0x0001_8000);
        write_u32(&mut bytes, ROOT_DISPERSION_OFFSET, 0x0000_4000);
        bytes[REFERENCE_ID_OFFSET..REFERENCE_ID_OFFSET + 4].copy_from_slice(b"GPS\0");
        write_timestamp(
            &mut bytes,
            REFERENCE_TIMESTAMP_OFFSET,
            Timestamp::new(0xe8fe_6f00, 0),
        );
        write_timestamp(&mut bytes, ORIGINATE_TIMESTAMP_OFFSET, COOKIE);
        write_timestamp(
            &mut bytes,
            RECEIVE_TIMESTAMP_OFFSET,
            Timestamp::new(0xe8fe_6f7f, 0xf000_0000),
        );
        write_timestamp(&mut bytes, TRANSMIT_TIMESTAMP_OFFSET, SERVER_TRANSMIT);

        let response = ServerResponse::parse(&bytes, COOKIE).unwrap();
        assert_eq!(response.leap_indicator(), 0);
        assert_eq!(response.version(), 4);
        assert_eq!(response.stratum(), 2);
        assert_eq!(response.poll(), 6);
        assert_eq!(response.precision(), -20);
        assert_eq!(response.root_delay(), 0x0001_8000);
        assert_eq!(response.root_dispersion(), 0x0000_4000);
        assert_eq!(response.reference_id(), *b"GPS\0");
        assert_eq!(response.originate_timestamp(), COOKIE);
        assert_eq!(response.transmit_timestamp(), SERVER_TRANSMIT);
        assert_eq!(
            response.transmit_timestamp().unix_seconds(),
            Some(1_700_000_000)
        );
    }

    #[test]
    fn rejects_bad_server_state_and_uncorrelated_response() {
        let mut bytes = [0; PACKET_LENGTH];
        bytes[0] = 0x24;
        bytes[STRATUM_OFFSET] = 1;
        write_timestamp(&mut bytes, ORIGINATE_TIMESTAMP_OFFSET, COOKIE);

        bytes[0] = 0x14;
        assert_eq!(
            ServerResponse::parse(&bytes, COOKIE),
            Err(ResponseError::UnsupportedVersion(3 - 1))
        );

        bytes[0] = 0x23;
        assert_eq!(
            ServerResponse::parse(&bytes, COOKIE),
            Err(ResponseError::UnexpectedMode(MODE_CLIENT))
        );

        bytes[0] = 0x24;
        bytes[STRATUM_OFFSET] = 0;
        bytes[REFERENCE_ID_OFFSET..REFERENCE_ID_OFFSET + 4].copy_from_slice(b"RATE");
        assert_eq!(
            ServerResponse::parse(&bytes, COOKIE),
            Err(ResponseError::KissOfDeath(*b"RATE"))
        );

        bytes[STRATUM_OFFSET] = 16;
        assert_eq!(
            ServerResponse::parse(&bytes, COOKIE),
            Err(ResponseError::InvalidStratum(16))
        );

        bytes[0] = 0xe4;
        bytes[STRATUM_OFFSET] = 1;
        assert_eq!(
            ServerResponse::parse(&bytes, COOKIE),
            Err(ResponseError::Unsynchronized)
        );

        bytes[0] = 0x24;
        let received = Timestamp::new(COOKIE.seconds(), 2);
        write_timestamp(&mut bytes, ORIGINATE_TIMESTAMP_OFFSET, received);
        assert_eq!(
            ServerResponse::parse(&bytes, COOKIE),
            Err(ResponseError::OriginateTimestampMismatch {
                expected: COOKIE,
                received,
            })
        );
    }

    #[test]
    fn reports_short_buffers_and_pre_unix_timestamps() {
        let mut short = [0; PACKET_LENGTH - 1];
        assert_eq!(
            encode_client_request(COOKIE, &mut short),
            Err(EncodeError::OutputTooSmall {
                required: PACKET_LENGTH,
                available: PACKET_LENGTH - 1,
            })
        );
        assert_eq!(
            ServerResponse::parse(&short, COOKIE),
            Err(ResponseError::Truncated {
                available: PACKET_LENGTH - 1,
            })
        );
        assert_eq!(
            Timestamp::new(UNIX_EPOCH_OFFSET_SECONDS - 1, 0).unix_seconds(),
            None
        );
        assert_eq!(
            Timestamp::new(UNIX_EPOCH_OFFSET_SECONDS, 0).unix_seconds(),
            Some(0)
        );
    }
}
