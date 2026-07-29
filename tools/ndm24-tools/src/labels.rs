use std::collections::HashMap;
use std::fs;
use std::path::Path;

use anyhow::{Context, Result};

pub fn read_labels(path: &Path) -> Result<HashMap<String, u32>> {
    let source =
        fs::read_to_string(path).with_context(|| format!("read label file {}", path.display()))?;
    let mut labels = HashMap::new();
    for line in source.lines() {
        let mut parts = line.split_whitespace();
        let Some(kind) = parts.next() else {
            continue;
        };
        if kind != "al" {
            continue;
        }
        let Some(address) = parts.next() else {
            continue;
        };
        let Some(name) = parts.next() else {
            continue;
        };
        let name = name.trim_start_matches('.');
        let address = u32::from_str_radix(address.trim_start_matches('$'), 16)
            .with_context(|| format!("invalid address for label {name}"))?;
        labels.insert(name.to_owned(), address);
    }
    Ok(labels)
}

pub fn wram_to_usb2snes(address: u32) -> Result<usize> {
    let offset = address
        .checked_sub(0x7e_0000)
        .context("label is not in SNES WRAM bank 7E")?;
    Ok(0xf5_0000 + offset as usize)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_wram_address() {
        assert_eq!(wram_to_usb2snes(0x7e_1234).unwrap(), 0xf5_1234);
    }
}
