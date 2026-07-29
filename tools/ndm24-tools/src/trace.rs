use std::fs;
use std::path::Path;

use anyhow::{Context, Result, ensure};
use ndm24_protocol::{PollKind, receive_decision};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Fixture {
    name: String,
    source: String,
    samples: Vec<Sample>,
}

#[derive(Debug, Deserialize)]
struct Sample {
    kind: PollKind,
    data_report: u16,
    status_report: u16,
    expected_discard_reason: u8,
}

pub fn verify_fixture(path: &Path) -> Result<()> {
    let source =
        fs::read_to_string(path).with_context(|| format!("read fixture {}", path.display()))?;
    let fixture: Fixture = toml::from_str(&source).context("parse trace fixture")?;
    for (index, sample) in fixture.samples.iter().enumerate() {
        let actual = receive_decision(sample.kind, sample.data_report, sample.status_report);
        ensure!(
            actual == sample.expected_discard_reason,
            "sample {index} expected discard reason {}, got {actual}",
            sample.expected_discard_reason
        );
    }
    println!(
        "verified {} samples from {} ({})",
        fixture.samples.len(),
        fixture.name,
        fixture.source
    );
    Ok(())
}
