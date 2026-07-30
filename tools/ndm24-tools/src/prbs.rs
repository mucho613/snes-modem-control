use anyhow::{Result, ensure};
use serde::Serialize;

const LFSR_FEEDBACK: u16 = 0xb400;

#[derive(Debug, Clone)]
pub struct Prbs16 {
    state: u16,
}

impl Prbs16 {
    pub fn new(seed: u16) -> Result<Self> {
        ensure!(seed != 0, "PRBS seed must be non-zero");
        Ok(Self { state: seed })
    }
}

impl Iterator for Prbs16 {
    type Item = u8;

    fn next(&mut self) -> Option<Self::Item> {
        let byte = self.state as u8;
        let lsb = self.state & 1;
        self.state >>= 1;
        if lsb != 0 {
            self.state ^= LFSR_FEEDBACK;
        }
        Some(byte)
    }
}

pub fn bytes(seed: u16, length: usize) -> Result<Vec<u8>> {
    Ok(Prbs16::new(seed)?.take(length).collect())
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct PrbsOutcome {
    pub processed: u32,
    pub mismatch_count: u32,
    pub first_mismatch: Option<u32>,
    pub expected: u8,
    pub actual: u8,
    pub start_frame: u32,
    pub end_frame: u32,
}

impl PrbsOutcome {
    pub fn decode(output: &[u8]) -> Result<Self> {
        ensure!(output.len() >= 22, "PRBS mailbox output is truncated");
        let first = read_u32(output, 8);
        Ok(Self {
            processed: read_u32(output, 0),
            mismatch_count: read_u32(output, 4),
            first_mismatch: (first != u32::MAX).then_some(first),
            expected: output[12],
            actual: output[13],
            start_frame: read_u32(output, 14),
            end_frame: read_u32(output, 18),
        })
    }

    pub fn frame_delta(&self) -> u32 {
        self.end_frame.wrapping_sub(self.start_frame)
    }
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(
        bytes[offset..offset + 4]
            .try_into()
            .expect("checked length"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_the_65816_lfsr_sequence() {
        assert_eq!(
            bytes(0xace1, 12).unwrap(),
            [
                0xe1, 0x70, 0x38, 0x9c, 0x4e, 0x27, 0x13, 0x89, 0xc4, 0x62, 0xb1, 0x58
            ]
        );
    }

    #[test]
    fn supports_the_full_certification_transfer_length() {
        let data = bytes(1, 65_536).unwrap();
        assert_eq!(data.len(), 65_536);
        assert_ne!(&data[..256], &data[256..512]);
    }

    #[test]
    fn rejects_the_locked_up_lfsr_seed() {
        assert!(Prbs16::new(0).is_err());
    }

    #[test]
    fn decodes_no_mismatch_and_wrapping_frame_counter() {
        let mut output = [0u8; 22];
        output[0..4].copy_from_slice(&65_536u32.to_le_bytes());
        output[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
        output[14..18].copy_from_slice(&u32::MAX.to_le_bytes());
        output[18..22].copy_from_slice(&1u32.to_le_bytes());
        let decoded = PrbsOutcome::decode(&output).unwrap();
        assert_eq!(decoded.processed, 65_536);
        assert_eq!(decoded.first_mismatch, None);
        assert_eq!(decoded.frame_delta(), 2);
    }
}
