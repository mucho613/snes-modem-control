//! RFC 1994 CHAP packet handling and the MD5 response algorithm.
//!
//! Authentication material is borrowed from the caller and is never retained
//! in an error or diagnostic value.

const HEADER_LENGTH: usize = 4;
pub const MD5_VALUE_LENGTH: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Code {
    Challenge = 1,
    Response = 2,
    Success = 3,
    Failure = 4,
}

impl Code {
    fn from_u8(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::Challenge),
            2 => Some(Self::Response),
            3 => Some(Self::Success),
            4 => Some(Self::Failure),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TruncatedHeader,
    InvalidLength,
    TruncatedPacket,
    UnsupportedCode,
    MissingValueLength,
    TruncatedValue,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    FieldTooLong,
    OutputTooSmall,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Packet<'a> {
    pub code: Code,
    pub identifier: u8,
    pub data: &'a [u8],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValuePacket<'a> {
    pub value: &'a [u8],
    pub name: &'a [u8],
}

impl<'a> Packet<'a> {
    pub fn parse(input: &'a [u8]) -> Result<Self, ParseError> {
        if input.len() < HEADER_LENGTH {
            return Err(ParseError::TruncatedHeader);
        }
        let length = usize::from(u16::from_be_bytes([input[2], input[3]]));
        if length < HEADER_LENGTH {
            return Err(ParseError::InvalidLength);
        }
        if length > input.len() {
            return Err(ParseError::TruncatedPacket);
        }
        let code = Code::from_u8(input[0]).ok_or(ParseError::UnsupportedCode)?;
        Ok(Self {
            code,
            identifier: input[1],
            data: &input[HEADER_LENGTH..length],
        })
    }

    pub fn value_packet(&self) -> Result<ValuePacket<'a>, ParseError> {
        if self.data.is_empty() {
            return Err(ParseError::MissingValueLength);
        }
        let value_length = usize::from(self.data[0]);
        if 1 + value_length > self.data.len() {
            return Err(ParseError::TruncatedValue);
        }
        Ok(ValuePacket {
            value: &self.data[1..1 + value_length],
            name: &self.data[1 + value_length..],
        })
    }
}

pub fn encode_response(
    identifier: u8,
    name: &[u8],
    digest: [u8; MD5_VALUE_LENGTH],
    output: &mut [u8],
) -> Result<usize, EncodeError> {
    if name.len() > u8::MAX as usize {
        return Err(EncodeError::FieldTooLong);
    }
    let length = HEADER_LENGTH + 1 + MD5_VALUE_LENGTH + name.len();
    if length > u16::MAX as usize {
        return Err(EncodeError::FieldTooLong);
    }
    if output.len() < length {
        return Err(EncodeError::OutputTooSmall);
    }
    output[0] = Code::Response as u8;
    output[1] = identifier;
    output[2..4].copy_from_slice(&(length as u16).to_be_bytes());
    output[4] = MD5_VALUE_LENGTH as u8;
    output[5..5 + MD5_VALUE_LENGTH].copy_from_slice(&digest);
    output[5 + MD5_VALUE_LENGTH..length].copy_from_slice(name);
    Ok(length)
}

/// RFC 1994 section 4.1: MD5(Identifier || Secret || Challenge Value).
pub fn response_digest(identifier: u8, secret: &[u8], challenge: &[u8]) -> [u8; 16] {
    let mut md5 = Md5::new();
    md5.update(&[identifier]);
    md5.update(secret);
    md5.update(challenge);
    md5.finalize()
}

struct Md5 {
    state: [u32; 4],
    length_bytes: u64,
    buffer: [u8; 64],
    buffered: usize,
}

impl Md5 {
    fn new() -> Self {
        Self {
            state: [0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476],
            length_bytes: 0,
            buffer: [0; 64],
            buffered: 0,
        }
    }

    fn update(&mut self, mut input: &[u8]) {
        self.length_bytes = self.length_bytes.wrapping_add(input.len() as u64);
        if self.buffered != 0 {
            let count = (64 - self.buffered).min(input.len());
            self.buffer[self.buffered..self.buffered + count].copy_from_slice(&input[..count]);
            self.buffered += count;
            input = &input[count..];
            if self.buffered == 64 {
                let block = self.buffer;
                self.compress(&block);
                self.buffered = 0;
            }
            if input.is_empty() {
                return;
            }
        }
        while input.len() >= 64 {
            let block: &[u8; 64] = input[..64].try_into().expect("exact MD5 block");
            self.compress(block);
            input = &input[64..];
        }
        self.buffer[..input.len()].copy_from_slice(input);
        self.buffered = input.len();
    }

    fn finalize(mut self) -> [u8; 16] {
        let bit_length = self.length_bytes.wrapping_mul(8);
        let mut padding = [0_u8; 72];
        padding[0] = 0x80;
        let padding_length = if self.buffered < 56 {
            56 - self.buffered
        } else {
            120 - self.buffered
        };
        self.update(&padding[..padding_length]);
        self.update(&bit_length.to_le_bytes());
        debug_assert_eq!(self.buffered, 0);

        let mut output = [0_u8; 16];
        for (chunk, word) in output.chunks_exact_mut(4).zip(self.state) {
            chunk.copy_from_slice(&word.to_le_bytes());
        }
        output
    }

    fn compress(&mut self, block: &[u8; 64]) {
        const S: [u32; 64] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20,
            5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
        ];
        const K: [u32; 64] = [
            0xd76a_a478,
            0xe8c7_b756,
            0x2420_70db,
            0xc1bd_ceee,
            0xf57c_0faf,
            0x4787_c62a,
            0xa830_4613,
            0xfd46_9501,
            0x6980_98d8,
            0x8b44_f7af,
            0xffff_5bb1,
            0x895c_d7be,
            0x6b90_1122,
            0xfd98_7193,
            0xa679_438e,
            0x49b4_0821,
            0xf61e_2562,
            0xc040_b340,
            0x265e_5a51,
            0xe9b6_c7aa,
            0xd62f_105d,
            0x0244_1453,
            0xd8a1_e681,
            0xe7d3_fbc8,
            0x21e1_cde6,
            0xc337_07d6,
            0xf4d5_0d87,
            0x455a_14ed,
            0xa9e3_e905,
            0xfcef_a3f8,
            0x676f_02d9,
            0x8d2a_4c8a,
            0xfffa_3942,
            0x8771_f681,
            0x6d9d_6122,
            0xfde5_380c,
            0xa4be_ea44,
            0x4bde_cfa9,
            0xf6bb_4b60,
            0xbebf_bc70,
            0x289b_7ec6,
            0xeaa1_27fa,
            0xd4ef_3085,
            0x0488_1d05,
            0xd9d4_d039,
            0xe6db_99e5,
            0x1fa2_7cf8,
            0xc4ac_5665,
            0xf429_2244,
            0x432a_ff97,
            0xab94_23a7,
            0xfc93_a039,
            0x655b_59c3,
            0x8f0c_cc92,
            0xffef_f47d,
            0x8584_5dd1,
            0x6fa8_7e4f,
            0xfe2c_e6e0,
            0xa301_4314,
            0x4e08_11a1,
            0xf753_7e82,
            0xbd3a_f235,
            0x2ad7_d2bb,
            0xeb86_d391,
        ];

        let mut words = [0_u32; 16];
        for (word, chunk) in words.iter_mut().zip(block.chunks_exact(4)) {
            *word = u32::from_le_bytes(chunk.try_into().expect("four-byte MD5 word"));
        }

        let [mut a, mut b, mut c, mut d] = self.state;
        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | (!b & d), i),
                16..=31 => ((d & b) | (!d & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | !d), (7 * i) % 16),
            };
            let next = a
                .wrapping_add(f)
                .wrapping_add(K[i])
                .wrapping_add(words[g])
                .rotate_left(S[i])
                .wrapping_add(b);
            a = d;
            d = c;
            c = b;
            b = next;
        }
        self.state[0] = self.state[0].wrapping_add(a);
        self.state[1] = self.state[1].wrapping_add(b);
        self.state[2] = self.state[2].wrapping_add(c);
        self.state[3] = self.state[3].wrapping_add(d);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(value: [u8; 16]) -> String {
        value.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    #[test]
    fn md5_matches_standard_vectors_across_padding_boundaries() {
        assert_eq!(
            hex(response_digest(0, b"", b"")),
            "93b885adfe0da089cdf634904fd59f71"
        );

        let mut md5 = Md5::new();
        md5.update(b"abc");
        assert_eq!(hex(md5.finalize()), "900150983cd24fb0d6963f7d28e17f72");

        let mut md5 = Md5::new();
        md5.update(&[b'a'; 56]);
        assert_eq!(hex(md5.finalize()), "3b0c8ac703f828b04c6c197006d17218");
    }

    #[test]
    fn parses_challenge_and_ignores_padding() {
        let bytes = [1, 0x20, 0, 9, 3, 0xaa, 0xbb, 0xcc, b'n', 0xff];
        let packet = Packet::parse(&bytes).unwrap();
        assert_eq!(packet.code, Code::Challenge);
        assert_eq!(packet.identifier, 0x20);
        assert_eq!(
            packet.value_packet().unwrap(),
            ValuePacket {
                value: &[0xaa, 0xbb, 0xcc],
                name: b"n"
            }
        );
    }

    #[test]
    fn encodes_response_with_rfc_digest() {
        let digest = response_digest(7, b"secret", b"challenge");
        assert_eq!(hex(digest), "35524f3f6d24a5b27d3a2ff77c7c5060");
        let mut output = [0_u8; 64];
        let length = encode_response(7, b"abc12345", digest, &mut output).unwrap();
        assert_eq!(length, 29);
        assert_eq!(&output[..5], &[2, 7, 0, 29, 16]);
        assert_eq!(&output[21..29], b"abc12345");
    }

    #[test]
    fn rejects_malformed_packets() {
        assert_eq!(Packet::parse(&[1, 2, 3]), Err(ParseError::TruncatedHeader));
        assert_eq!(Packet::parse(&[1, 2, 0, 3]), Err(ParseError::InvalidLength));
        assert_eq!(
            Packet::parse(&[1, 2, 0, 6, 2, 0xaa])
                .unwrap()
                .value_packet(),
            Err(ParseError::TruncatedValue)
        );
    }
}
