use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail, ensure};
use clap::{Parser, Subcommand};
use serde::Deserialize;
use sha2::{Digest, Sha256};

#[derive(Debug, Parser)]
#[command(about = "Windows-native build and generation tasks for snes-modem-control")]
struct Cli {
    #[command(subcommand)]
    command: Task,
}

#[derive(Debug, Subcommand)]
enum Task {
    Generate {
        #[arg(long)]
        check: bool,
    },
    Rom {
        #[arg(long)]
        smoke: bool,
        #[arg(long, conflicts_with = "smoke")]
        font_test: bool,
    },
    Deploy {
        #[arg(long)]
        smoke: bool,
        #[arg(long, conflicts_with = "smoke")]
        font_test: bool,
        #[arg(long, default_value = "ws://localhost:23074")]
        websocket: String,
        #[arg(long, default_value = "/snes-modem-control.sfc")]
        remote_path: String,
    },
    Check,
    Bootstrap,
}

#[derive(Debug, Deserialize)]
struct SpecFile {
    spec: SpecInfo,
    protocol: BTreeMap<String, toml::Value>,
    driver: BTreeMap<String, toml::Value>,
    terminal: BTreeMap<String, toml::Value>,
    diagnostic: Diagnostic,
    ppp_diagnostic: PppDiagnostic,
    mailbox: Mailbox,
    states: BTreeMap<String, u8>,
    flags: BTreeMap<String, u8>,
    discard_reasons: BTreeMap<String, u8>,
    trace_events: BTreeMap<String, u8>,
    mailbox_commands: BTreeMap<String, u8>,
    mailbox_status: BTreeMap<String, u8>,
}

#[derive(Debug, Deserialize)]
struct SpecInfo {
    name: String,
    version: u16,
}

#[derive(Debug, Deserialize)]
struct Diagnostic {
    magic: Vec<u8>,
    version: u16,
    size: usize,
    trace_event_size: usize,
    trace_capacity: usize,
    trace_size: usize,
    fields: Vec<Field>,
}

#[derive(Debug, Deserialize)]
struct PppDiagnostic {
    magic: Vec<u8>,
    version: u16,
    size: usize,
    fields: Vec<Field>,
}

#[derive(Debug, Deserialize)]
struct Mailbox {
    magic: Vec<u8>,
    version: u16,
    size: usize,
    argument_size: usize,
    fields: Vec<Field>,
}

#[derive(Debug, Deserialize)]
struct Field {
    name: String,
    offset: usize,
    size: usize,
    #[serde(rename = "type")]
    field_type: String,
    description: String,
}

#[derive(Debug, Deserialize)]
struct FontSource {
    source_url: String,
    source_file: String,
    readme_file: String,
    commit: String,
    sha256_lf: String,
    readme_sha256_canonical_lf: String,
    author: String,
    license: String,
    provenance: String,
}

#[derive(Debug, Clone, Copy)]
enum RomProfile {
    Normal,
    Smoke,
    FontTest,
}

impl RomProfile {
    fn from_flags(smoke: bool, font_test: bool) -> Self {
        if smoke {
            Self::Smoke
        } else if font_test {
            Self::FontTest
        } else {
            Self::Normal
        }
    }

    fn output_directory(self) -> &'static str {
        match self {
            Self::Normal => "build/normal",
            Self::Smoke => "build/smoke",
            Self::FontTest => "build/font-test",
        }
    }

    fn assembler_define(self) -> Option<&'static str> {
        match self {
            Self::Normal => None,
            Self::Smoke => Some("MODEM_SMOKE_TEST"),
            Self::FontTest => Some("MODEM_FONT_TEST"),
        }
    }
}

#[derive(Debug, Deserialize)]
struct ToolchainFile {
    cc65: Cc65Platforms,
}

#[derive(Debug, Deserialize)]
struct Cc65Platforms {
    windows_x86_64: ToolchainArchive,
}

#[derive(Debug, Deserialize)]
struct ToolchainArchive {
    snapshot_date: String,
    url: String,
    sha256: String,
}

fn main() -> Result<()> {
    let root = workspace_root()?;
    match Cli::parse().command {
        Task::Generate { check } => generate(&root, check),
        Task::Rom { smoke, font_test } => {
            build_rom(&root, RomProfile::from_flags(smoke, font_test))
        }
        Task::Deploy {
            smoke,
            font_test,
            websocket,
            remote_path,
        } => {
            let profile = RomProfile::from_flags(smoke, font_test);
            build_rom(&root, profile)?;
            let rom = root
                .join(profile.output_directory())
                .join("modem-control.sfc");
            run(Command::new("cargo")
                .current_dir(&root)
                .args(["run", "--package", "ndm24-tools", "--", "deploy"])
                .arg(&rom)
                .args(["--websocket", &websocket, "--remote-path", &remote_path]))
        }
        Task::Check => {
            generate(&root, true)?;
            run(Command::new("cargo")
                .args(["test", "--workspace"])
                .current_dir(&root))?;
            build_rom(&root, RomProfile::Normal)?;
            build_rom(&root, RomProfile::Smoke)?;
            build_rom(&root, RomProfile::FontTest)
        }
        Task::Bootstrap => bootstrap(&root),
    }
}

fn workspace_root() -> Result<PathBuf> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest
        .parent()
        .map(Path::to_path_buf)
        .context("xtask must be located directly below the workspace root")
}

fn read_spec(root: &Path) -> Result<SpecFile> {
    let source =
        fs::read_to_string(root.join("spec/ndm24.toml")).context("read spec/ndm24.toml")?;
    let spec: SpecFile = toml::from_str(&source).context("parse spec/ndm24.toml")?;
    validate_spec(&spec)?;
    Ok(spec)
}

fn validate_spec(spec: &SpecFile) -> Result<()> {
    ensure!(
        spec.diagnostic.magic.len() == 4,
        "diagnostic magic must be 4 bytes"
    );
    ensure!(
        spec.mailbox.magic.len() == 4,
        "mailbox magic must be 4 bytes"
    );
    ensure!(
        spec.ppp_diagnostic.magic.len() == 4,
        "PPP diagnostic magic must be 4 bytes"
    );
    validate_fields(&spec.diagnostic.fields, spec.diagnostic.size, "diagnostic")?;
    validate_fields(
        &spec.ppp_diagnostic.fields,
        spec.ppp_diagnostic.size,
        "PPP diagnostic",
    )?;
    validate_fields(&spec.mailbox.fields, spec.mailbox.size, "mailbox")?;
    ensure!(
        spec.diagnostic.trace_event_size * spec.diagnostic.trace_capacity
            == spec.diagnostic.trace_size,
        "trace size does not match event size times capacity"
    );
    validate_terminal(&spec.terminal)?;
    Ok(())
}

fn validate_terminal(terminal: &BTreeMap<String, toml::Value>) -> Result<()> {
    let columns = scalar_value(terminal, "columns", "terminal")?;
    let rows = scalar_value(terminal, "rows", "terminal")?;
    let queue_storage_size = scalar_value(terminal, "queue_storage_size", "terminal")?;
    let queue_capacity = scalar_value(terminal, "queue_capacity", "terminal")?;
    let render_budget = scalar_value(terminal, "render_budget", "terminal")?;
    let tilemap_mask = scalar_value(terminal, "tilemap_mask", "terminal")?;
    let palette_background = scalar_value(terminal, "palette_background", "terminal")?;
    let palette_foreground = scalar_value(terminal, "palette_foreground", "terminal")?;
    let palette_unused_2 = scalar_value(terminal, "palette_unused_2", "terminal")?;
    let palette_unused_3 = scalar_value(terminal, "palette_unused_3", "terminal")?;

    ensure!(
        columns.is_power_of_two(),
        "terminal columns must be a power of two"
    );
    ensure!(
        queue_storage_size == 256,
        "terminal queue storage must be 256 bytes for 8-bit indices"
    );
    ensure!(
        queue_capacity.checked_add(1) == Some(queue_storage_size),
        "terminal queue capacity must reserve one byte to distinguish full from empty"
    );
    ensure!(
        render_budget > 0 && render_budget <= queue_capacity,
        "terminal render budget must be between 1 and queue capacity"
    );
    ensure!(
        columns.checked_mul(rows) == tilemap_mask.checked_add(1),
        "terminal tilemap mask must cover exactly columns times rows entries"
    );
    ensure!(
        [
            palette_background,
            palette_foreground,
            palette_unused_2,
            palette_unused_3
        ]
        .into_iter()
        .all(|color| color <= 0x7fff),
        "terminal palette colors must be 15-bit BGR values"
    );
    Ok(())
}

fn scalar_value(values: &BTreeMap<String, toml::Value>, name: &str, group: &str) -> Result<usize> {
    let value = values
        .get(name)
        .with_context(|| format!("{group}.{name} is missing"))?
        .as_integer()
        .with_context(|| format!("{group}.{name} must be an integer"))?;
    usize::try_from(value).with_context(|| format!("{group}.{name} must be non-negative"))
}

fn validate_fields(fields: &[Field], size: usize, block_name: &str) -> Result<()> {
    let mut previous_end = 0;
    for field in fields {
        ensure!(
            field.offset >= previous_end,
            "{block_name} fields overlap at {}",
            field.name
        );
        ensure!(
            field.offset + field.size <= size,
            "{block_name} field {} exceeds block size",
            field.name
        );
        previous_end = field.offset + field.size;
    }
    Ok(())
}

fn generate(root: &Path, check: bool) -> Result<()> {
    let spec = read_spec(root)?;
    let (font_source, font) = load_font8x8(root)?;
    let outputs = [
        (
            root.join("src/modem/generated.inc"),
            render_assembly(&spec)?,
        ),
        (
            root.join("crates/ndm24-protocol/src/generated.rs"),
            render_rust(&spec)?,
        ),
        (
            root.join("docs/generated/diagnostic-abi.md"),
            render_markdown(&spec),
        ),
        (
            root.join("src/terminal/generated-font.inc"),
            render_font_assembly(&font_source),
        ),
    ];

    for (path, content) in outputs {
        if check {
            let current = fs::read_to_string(&path)
                .with_context(|| format!("generated file is missing: {}", path.display()))?;
            ensure!(
                current == content,
                "{} is out of date; run `cargo xtask generate`",
                path.display()
            );
        } else {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(&path, content)
                .with_context(|| format!("write generated file {}", path.display()))?;
            println!("generated {}", path.strip_prefix(root)?.display());
        }
    }
    let sfc_font = generate_sfc_font(&font);
    let palette = generate_palette(&spec)?;
    let preview = generate_font_preview(&sfc_font, &palette)?;
    let binary_outputs = [
        (root.join("assets/font.bin"), sfc_font),
        (root.join("assets/palette.bin"), palette),
        (root.join("docs/generated/font-preview.png"), preview),
    ];
    for (path, content) in binary_outputs {
        sync_generated_bytes(root, &path, &content, check)?;
    }
    Ok(())
}

const FONT_TEST_LINES: &[&[u8]] = &[
    b" !\"#$%&'()*+,-./",
    b"0123456789:;<=>?",
    b"@ABCDEFGHIJKLMNO",
    b"PQRSTUVWXYZ[\\]^_",
    b"`abcdefghijklmno",
    b"pqrstuvwxyz{|}~",
    b"",
    b"0O 1Il| 2Z 5S 6G 8B 9g",
    b"AT%B2400 ATS10=14",
    b"192.168.100.255",
    b"!@#$%^&*()[]{}\\|;:'\",.<>/?",
    b"font8x8 / Public Domain",
];

fn load_font8x8(root: &Path) -> Result<(FontSource, [[u8; 8]; 128])> {
    let directory = root.join("third_party/font8x8");
    let metadata = fs::read_to_string(directory.join("SOURCE.toml"))
        .context("read third_party/font8x8/SOURCE.toml")?;
    let metadata: FontSource = toml::from_str(&metadata).context("parse font8x8 SOURCE.toml")?;
    ensure!(
        metadata.license == "Public Domain",
        "font8x8 license metadata changed unexpectedly"
    );
    ensure!(
        metadata.provenance.contains("Marcel Sondaar")
            && metadata
                .provenance
                .contains("International Business Machines"),
        "font8x8 provenance metadata is incomplete"
    );

    let source_path = directory.join(&metadata.source_file);
    let source = canonical_text(
        &fs::read_to_string(&source_path)
            .with_context(|| format!("read {}", source_path.display()))?,
    );
    let actual_hash = format!("{:x}", Sha256::digest(source.as_bytes()));
    ensure!(
        actual_hash == metadata.sha256_lf,
        "font8x8 source hash mismatch: expected {}, got {actual_hash}",
        metadata.sha256_lf
    );
    ensure!(
        source.contains("License: Public Domain"),
        "font8x8 source is missing its Public Domain declaration"
    );
    let readme_path = directory.join(&metadata.readme_file);
    let readme = canonical_text(
        &fs::read_to_string(&readme_path)
            .with_context(|| format!("read {}", readme_path.display()))?,
    );
    let readme_hash = format!("{:x}", Sha256::digest(readme.as_bytes()));
    ensure!(
        readme_hash == metadata.readme_sha256_canonical_lf,
        "font8x8 README hash mismatch: expected {}, got {readme_hash}",
        metadata.readme_sha256_canonical_lf
    );
    ensure!(
        readme.contains("Author: Daniel Hepper")
            && readme.contains("License: Public Domain")
            && readme.contains("Marcel Sondaar")
            && readme.contains("International Business Machines"),
        "font8x8 README is missing its author, license, or provenance"
    );
    Ok((metadata, parse_font8x8_basic(&source)?))
}

fn canonical_text(source: &str) -> String {
    let normalized = source.replace("\r\n", "\n");
    format!("{}\n", normalized.trim_end_matches('\n'))
}

fn parse_font8x8_basic(source: &str) -> Result<[[u8; 8]; 128]> {
    let mut glyphs = [[0_u8; 8]; 128];
    let mut seen = [false; 128];

    for line in source.lines() {
        let Some(marker) = line.find("// U+") else {
            continue;
        };
        let codepoint_text = line
            .get(marker + 5..marker + 9)
            .context("font8x8 source has a truncated Unicode marker")?;
        let codepoint = usize::from_str_radix(codepoint_text, 16)
            .with_context(|| format!("invalid font8x8 codepoint {codepoint_text}"))?;
        ensure!(codepoint < 128, "font8x8 basic codepoint is out of range");
        ensure!(
            !seen[codepoint],
            "duplicate font8x8 codepoint U+{codepoint:04X}"
        );

        let start = line.find('{').context("font8x8 glyph row is missing `{`")?;
        let end = line[start + 1..]
            .find('}')
            .map(|offset| start + 1 + offset)
            .context("font8x8 glyph row is missing `}`")?;
        let values = line[start + 1..end]
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| {
                let hexadecimal = value
                    .strip_prefix("0x")
                    .or_else(|| value.strip_prefix("0X"))
                    .with_context(|| format!("font8x8 value is not hexadecimal: {value}"))?;
                u8::from_str_radix(hexadecimal, 16)
                    .with_context(|| format!("invalid font8x8 byte: {value}"))
            })
            .collect::<Result<Vec<_>>>()?;
        ensure!(
            values.len() == 8,
            "font8x8 U+{codepoint:04X} must contain exactly eight rows"
        );
        glyphs[codepoint].copy_from_slice(&values);
        seen[codepoint] = true;
    }

    ensure!(
        seen.into_iter().all(|present| present),
        "font8x8 basic source does not define all 128 codepoints"
    );
    Ok(glyphs)
}

fn generate_sfc_font(glyphs: &[[u8; 8]; 128]) -> Vec<u8> {
    let mut output = vec![0_u8; 256 * 16];
    for (codepoint, glyph) in glyphs.iter().enumerate().take(0x7f).skip(0x20) {
        let destination = codepoint * 16;
        for row in 0..8 {
            // font8x8 stores the leftmost pixel in bit 0. SNES bitplanes store
            // it in bit 7, so every row is reversed into plane 0.
            output[destination + row * 2] = glyph[row].reverse_bits();
            output[destination + row * 2 + 1] = 0;
        }
    }
    output
}

fn generate_palette(spec: &SpecFile) -> Result<Vec<u8>> {
    let mut output = vec![0_u8; 512];
    for (index, name) in [
        "palette_background",
        "palette_foreground",
        "palette_unused_2",
        "palette_unused_3",
    ]
    .into_iter()
    .enumerate()
    {
        let color = u16::try_from(scalar_value(&spec.terminal, name, "terminal")?)?;
        output[index * 2..index * 2 + 2].copy_from_slice(&color.to_le_bytes());
    }
    Ok(output)
}

fn generate_font_preview(font: &[u8], palette: &[u8]) -> Result<Vec<u8>> {
    const SCALE: usize = 4;
    const COLUMNS: usize = 32;
    ensure!(
        font.len() == 4096,
        "font preview requires 4096-byte SFC font data"
    );
    ensure!(
        palette.len() == 512,
        "font preview requires 512-byte CGRAM data"
    );
    let background = decode_bgr555(u16::from_le_bytes([palette[0], palette[1]]));
    let foreground = decode_bgr555(u16::from_le_bytes([palette[2], palette[3]]));
    let width = COLUMNS * 8;
    let height = FONT_TEST_LINES.len() * 8;
    let mut pixels = vec![0_u8; width * height * 3];
    for pixel in pixels.chunks_exact_mut(3) {
        pixel.copy_from_slice(&background);
    }

    for (row, line) in FONT_TEST_LINES.iter().enumerate() {
        for (column, &codepoint) in line.iter().enumerate() {
            ensure!(column < COLUMNS, "font preview line exceeds 32 columns");
            let tile = usize::from(codepoint) * 16;
            for glyph_y in 0..8 {
                let plane = font[tile + glyph_y * 2];
                for glyph_x in 0..8 {
                    if plane & (0x80 >> glyph_x) == 0 {
                        continue;
                    }
                    let pixel = ((row * 8 + glyph_y) * width + column * 8 + glyph_x) * 3;
                    pixels[pixel..pixel + 3].copy_from_slice(&foreground);
                }
            }
        }
    }

    let scaled_width = width * SCALE;
    let scaled_height = height * SCALE;
    let mut scaled = vec![0_u8; scaled_width * scaled_height * 3];
    for y in 0..scaled_height {
        for x in 0..scaled_width {
            let source = ((y / SCALE) * width + x / SCALE) * 3;
            let destination = (y * scaled_width + x) * 3;
            scaled[destination..destination + 3].copy_from_slice(&pixels[source..source + 3]);
        }
    }

    let mut output = Vec::new();
    {
        let mut encoder = png::Encoder::new(
            &mut output,
            u32::try_from(scaled_width)?,
            u32::try_from(scaled_height)?,
        );
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder
            .write_header()
            .context("write font preview PNG header")?;
        writer
            .write_image_data(&scaled)
            .context("write font preview PNG pixels")?;
    }
    Ok(output)
}

fn decode_bgr555(color: u16) -> [u8; 3] {
    let expand = |component: u16| u8::try_from((component * 255 + 15) / 31).unwrap();
    [
        expand(color & 0x1f),
        expand((color >> 5) & 0x1f),
        expand((color >> 10) & 0x1f),
    ]
}

fn render_font_assembly(source: &FontSource) -> String {
    let mut output = generated_banner(";");
    output.push_str(".export fontTestScreen, fontAttribution\n\n");
    output.push_str("fontTestScreen:\n");
    for line in FONT_TEST_LINES {
        write_assembly_bytes(&mut output, line);
        output.push_str(".byte $0A\n");
    }
    output.push_str(".byte $00\n\nfontAttribution:\n");
    let attribution = format!(
        "font8x8 by {}; {}; derived from Marcel Sondaar and IBM public-domain VGA fonts; commit {}; {}",
        source.author, source.license, source.commit, source.source_url
    );
    write_assembly_bytes(&mut output, attribution.as_bytes());
    output.push_str(".byte $00\n");
    output
}

fn write_assembly_bytes(output: &mut String, bytes: &[u8]) {
    for chunk in bytes.chunks(16) {
        output.push_str(".byte ");
        for (index, byte) in chunk.iter().enumerate() {
            if index != 0 {
                output.push(',');
            }
            output.push_str(&format!("${byte:02X}"));
        }
        output.push('\n');
    }
}

fn sync_generated_bytes(root: &Path, path: &Path, content: &[u8], check: bool) -> Result<()> {
    if check {
        let current = fs::read(path)
            .with_context(|| format!("generated file is missing: {}", path.display()))?;
        ensure!(
            current == content,
            "{} is out of date; run `cargo xtask generate`",
            path.display()
        );
    } else {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, content)
            .with_context(|| format!("write generated file {}", path.display()))?;
        println!("generated {}", path.strip_prefix(root)?.display());
    }
    Ok(())
}

fn render_assembly(spec: &SpecFile) -> Result<String> {
    let mut out = generated_banner(";");
    scalar_maps_asm(&mut out, "MODEM", &spec.protocol)?;
    scalar_maps_asm(&mut out, "MODEM", &spec.driver)?;
    scalar_maps_asm(&mut out, "TERMINAL", &spec.terminal)?;
    writeln(
        &mut out,
        &format!("MODEM_SPEC_VERSION = ${:04X}", spec.spec.version),
    );
    writeln(
        &mut out,
        &format!(
            "MODEM_DIAGNOSTIC_VERSION = ${:04X}",
            spec.diagnostic.version
        ),
    );
    writeln(
        &mut out,
        &format!("MODEM_DIAGNOSTIC_SIZE = ${:04X}", spec.diagnostic.size),
    );
    writeln(
        &mut out,
        &format!(
            "MODEM_TRACE_EVENT_SIZE = ${:04X}",
            spec.diagnostic.trace_event_size
        ),
    );
    writeln(
        &mut out,
        &format!(
            "MODEM_TRACE_CAPACITY = ${:04X}",
            spec.diagnostic.trace_capacity
        ),
    );
    writeln(
        &mut out,
        &format!("MODEM_TRACE_SIZE = ${:04X}", spec.diagnostic.trace_size),
    );
    for field in &spec.diagnostic.fields {
        writeln(
            &mut out,
            &format!(
                "MODEM_DIAG_{} = ${:04X}",
                screaming(&field.name),
                field.offset
            ),
        );
    }
    writeln(
        &mut out,
        &format!(
            "PPP_DIAGNOSTIC_VERSION = ${:04X}",
            spec.ppp_diagnostic.version
        ),
    );
    writeln(
        &mut out,
        &format!("PPP_DIAGNOSTIC_SIZE = ${:04X}", spec.ppp_diagnostic.size),
    );
    for field in &spec.ppp_diagnostic.fields {
        writeln(
            &mut out,
            &format!(
                "PPP_DIAG_{} = ${:04X}",
                screaming(&field.name),
                field.offset
            ),
        );
    }
    for field in &spec.mailbox.fields {
        writeln(
            &mut out,
            &format!(
                "MODEM_MAILBOX_OFFSET_{} = ${:04X}",
                screaming(&field.name),
                field.offset
            ),
        );
    }
    writeln(
        &mut out,
        &format!("MODEM_MAILBOX_VERSION = ${:04X}", spec.mailbox.version),
    );
    writeln(
        &mut out,
        &format!("MODEM_MAILBOX_SIZE = ${:04X}", spec.mailbox.size),
    );
    writeln(
        &mut out,
        &format!(
            "MODEM_MAILBOX_ARGUMENT_SIZE = ${:04X}",
            spec.mailbox.argument_size
        ),
    );
    byte_array_asm(&mut out, "MODEM_DIAGNOSTIC_MAGIC", &spec.diagnostic.magic);
    byte_array_asm(&mut out, "PPP_DIAGNOSTIC_MAGIC", &spec.ppp_diagnostic.magic);
    byte_array_asm(&mut out, "MODEM_MAILBOX_MAGIC", &spec.mailbox.magic);
    enum_map_asm(&mut out, "MODEM_STATE", &spec.states);
    enum_map_asm(&mut out, "MODEM_FLAG", &spec.flags);
    enum_map_asm(&mut out, "MODEM_DISCARD", &spec.discard_reasons);
    enum_map_asm(&mut out, "MODEM_TRACE", &spec.trace_events);
    enum_map_asm(&mut out, "MODEM_MAILBOX_COMMAND", &spec.mailbox_commands);
    enum_map_asm(&mut out, "MODEM_MAILBOX_STATUS", &spec.mailbox_status);
    Ok(out)
}

fn render_rust(spec: &SpecFile) -> Result<String> {
    let mut out = generated_banner("//");
    scalar_maps_rust(&mut out, "MODEM", &spec.protocol)?;
    scalar_maps_rust(&mut out, "MODEM", &spec.driver)?;
    scalar_maps_rust(&mut out, "TERMINAL", &spec.terminal)?;
    writeln(
        &mut out,
        &format!("pub const MODEM_SPEC_VERSION: u16 = {};", spec.spec.version),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_DIAGNOSTIC_MAGIC: [u8; 4] = {:?};",
            spec.diagnostic.magic
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_DIAGNOSTIC_VERSION: u16 = {};",
            spec.diagnostic.version
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_DIAGNOSTIC_SIZE: usize = {};",
            spec.diagnostic.size
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_TRACE_EVENT_SIZE: usize = {};",
            spec.diagnostic.trace_event_size
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_TRACE_CAPACITY: usize = {};",
            spec.diagnostic.trace_capacity
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_TRACE_SIZE: usize = {};",
            spec.diagnostic.trace_size
        ),
    );
    for field in &spec.diagnostic.fields {
        writeln(
            &mut out,
            &format!(
                "pub const MODEM_DIAG_{}: usize = {};",
                screaming(&field.name),
                field.offset
            ),
        );
    }
    writeln(
        &mut out,
        &format!(
            "pub const PPP_DIAGNOSTIC_MAGIC: [u8; 4] = {:?};",
            spec.ppp_diagnostic.magic
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const PPP_DIAGNOSTIC_VERSION: u16 = {};",
            spec.ppp_diagnostic.version
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const PPP_DIAGNOSTIC_SIZE: usize = {};",
            spec.ppp_diagnostic.size
        ),
    );
    for field in &spec.ppp_diagnostic.fields {
        writeln(
            &mut out,
            &format!(
                "pub const PPP_DIAG_{}: usize = {};",
                screaming(&field.name),
                field.offset
            ),
        );
    }
    for field in &spec.mailbox.fields {
        writeln(
            &mut out,
            &format!(
                "pub const MODEM_MAILBOX_OFFSET_{}: usize = {};",
                screaming(&field.name),
                field.offset
            ),
        );
    }
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_MAILBOX_MAGIC: [u8; 4] = {:?};",
            spec.mailbox.magic
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_MAILBOX_VERSION: u16 = {};",
            spec.mailbox.version
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_MAILBOX_SIZE: usize = {};",
            spec.mailbox.size
        ),
    );
    writeln(
        &mut out,
        &format!(
            "pub const MODEM_MAILBOX_ARGUMENT_SIZE: usize = {};",
            spec.mailbox.argument_size
        ),
    );
    enum_map_rust(&mut out, "MODEM_STATE", &spec.states);
    enum_map_rust(&mut out, "MODEM_FLAG", &spec.flags);
    enum_map_rust(&mut out, "MODEM_DISCARD", &spec.discard_reasons);
    enum_map_rust(&mut out, "MODEM_TRACE", &spec.trace_events);
    enum_map_rust(&mut out, "MODEM_MAILBOX_COMMAND", &spec.mailbox_commands);
    enum_map_rust(&mut out, "MODEM_MAILBOX_STATUS", &spec.mailbox_status);
    Ok(out)
}

fn render_markdown(spec: &SpecFile) -> String {
    let mut out =
        String::from("<!-- Generated by `cargo xtask generate`; do not edit directly. -->\n\n");
    out.push_str(&format!("# {} diagnostic ABI\n\n", spec.spec.name));
    out.push_str(&format!(
        "ABI version: `{}`. Block size: `{}` bytes.\n\n",
        spec.diagnostic.version, spec.diagnostic.size
    ));
    out.push_str("| Offset | Size | Type | Field | Meaning |\n");
    out.push_str("|---:|---:|---|---|---|\n");
    for field in &spec.diagnostic.fields {
        out.push_str(&format!(
            "| `0x{:02X}` | {} | `{}` | `{}` | {} |\n",
            field.offset, field.size, field.field_type, field.name, field.description
        ));
    }
    out.push_str("\n## PPP Diagnostic ABI\n\n");
    out.push_str(&format!(
        "ABI version: `{}`. Block size: `{}` bytes.\n\n",
        spec.ppp_diagnostic.version, spec.ppp_diagnostic.size
    ));
    out.push_str("| Offset | Size | Type | Field | Meaning |\n");
    out.push_str("|---:|---:|---|---|---|\n");
    for field in &spec.ppp_diagnostic.fields {
        out.push_str(&format!(
            "| `0x{:02X}` | {} | `{}` | `{}` | {} |\n",
            field.offset, field.size, field.field_type, field.name, field.description
        ));
    }
    out.push_str("\n## Mailbox ABI\n\n");
    out.push_str(&format!(
        "ABI version: `{}`. Block size: `{}` bytes.\n\n",
        spec.mailbox.version, spec.mailbox.size
    ));
    out.push_str("| Offset | Size | Type | Field | Meaning |\n");
    out.push_str("|---:|---:|---|---|---|\n");
    for field in &spec.mailbox.fields {
        out.push_str(&format!(
            "| `0x{:02X}` | {} | `{}` | `{}` | {} |\n",
            field.offset, field.size, field.field_type, field.name, field.description
        ));
    }
    out
}

fn scalar_maps_asm(
    out: &mut String,
    prefix: &str,
    values: &BTreeMap<String, toml::Value>,
) -> Result<()> {
    for (name, value) in values {
        let value = value
            .as_integer()
            .with_context(|| format!("{name} must be an integer"))?;
        writeln(out, &format!("{prefix}_{} = ${value:04X}", screaming(name)));
    }
    Ok(())
}

fn scalar_maps_rust(
    out: &mut String,
    prefix: &str,
    values: &BTreeMap<String, toml::Value>,
) -> Result<()> {
    for (name, value) in values {
        let value = value
            .as_integer()
            .with_context(|| format!("{name} must be an integer"))?;
        writeln(
            out,
            &format!("pub const {prefix}_{}: usize = {value};", screaming(name)),
        );
    }
    Ok(())
}

fn enum_map_asm(out: &mut String, prefix: &str, values: &BTreeMap<String, u8>) {
    for (name, value) in values {
        writeln(out, &format!("{prefix}_{} = ${value:02X}", screaming(name)));
    }
}

fn enum_map_rust(out: &mut String, prefix: &str, values: &BTreeMap<String, u8>) {
    for (name, value) in values {
        writeln(
            out,
            &format!("pub const {prefix}_{}: u8 = {value};", screaming(name)),
        );
    }
}

fn byte_array_asm(out: &mut String, prefix: &str, bytes: &[u8]) {
    for (index, byte) in bytes.iter().enumerate() {
        writeln(out, &format!("{prefix}_{index} = ${byte:02X}"));
    }
}

fn generated_banner(comment: &str) -> String {
    format!("{comment} Generated by `cargo xtask generate`; do not edit directly.\n\n")
}

fn screaming(name: &str) -> String {
    name.to_ascii_uppercase().replace('-', "_")
}

fn writeln(out: &mut String, line: &str) {
    out.push_str(line);
    out.push('\n');
}

fn build_rom(root: &Path, profile: RomProfile) -> Result<()> {
    let tools = find_cc65(root)?;
    let out = root.join(profile.output_directory());
    if out.exists() {
        fs::remove_dir_all(&out)?;
    }
    fs::create_dir_all(&out)?;

    let mut sources = Vec::new();
    collect_asm(&root.join("src"), &mut sources)?;
    sources.sort();
    let mut objects = Vec::new();

    for source in sources {
        let relative = source.strip_prefix(root)?;
        let object = out.join(relative).with_extension("o");
        fs::create_dir_all(object.parent().expect("object has a parent"))?;
        let mut command = Command::new(&tools.ca65);
        command.current_dir(root).args(["--cpu", "65816", "-g"]);
        if let Some(define) = profile.assembler_define() {
            command.args(["-D", define]);
        }
        command.arg("-o").arg(&object).arg(&source);
        configure_cc65_command(&mut command, &tools)?;
        run(&mut command)?;
        objects.push(object);
    }

    let rom = out.join("modem-control.sfc");
    let mut link = Command::new(&tools.ld65);
    link.current_dir(root)
        .arg("--dbgfile")
        .arg(out.join("modem-control.dbg"))
        .arg("--mapfile")
        .arg(out.join("modem-control.map"))
        .arg("-Ln")
        .arg(out.join("modem-control.lbl"))
        .arg("-o")
        .arg(&rom)
        .arg("--config")
        .arg(root.join("modem-control.cfg"))
        .arg("--obj");
    link.args(objects);
    configure_cc65_command(&mut link, &tools)?;
    run(&mut link)?;
    ensure!(
        fs::metadata(&rom)?.len() == 131_072,
        "ROM has an unexpected size"
    );
    let rom_bytes = fs::read(&rom)?;
    ensure!(
        rom_bytes
            .windows(b"font8x8 by Daniel Hepper".len())
            .any(|window| window == b"font8x8 by Daniel Hepper"),
        "ROM does not contain the embedded font attribution"
    );
    println!("built {}", rom.strip_prefix(root)?.display());
    Ok(())
}

struct Cc65Tools {
    ca65: PathBuf,
    ld65: PathBuf,
    home: Option<PathBuf>,
}

fn find_cc65(root: &Path) -> Result<Cc65Tools> {
    let suffix = if cfg!(windows) { ".exe" } else { "" };
    let local = root.join(".tools/cc65/bin");
    let local_ca65 = local.join(format!("ca65{suffix}"));
    let local_ld65 = local.join(format!("ld65{suffix}"));
    if local_ca65.is_file() && local_ld65.is_file() {
        return Ok(Cc65Tools {
            ca65: local_ca65,
            ld65: local_ld65,
            home: Some(root.join(".tools/cc65")),
        });
    }
    if command_exists(&format!("ca65{suffix}")) && command_exists(&format!("ld65{suffix}")) {
        return Ok(Cc65Tools {
            ca65: PathBuf::from(format!("ca65{suffix}")),
            ld65: PathBuf::from(format!("ld65{suffix}")),
            home: None,
        });
    }
    bail!("cc65 was not found; run `cargo xtask bootstrap`")
}

fn configure_cc65_command(command: &mut Command, tools: &Cc65Tools) -> Result<()> {
    let Some(home) = &tools.home else {
        return Ok(());
    };
    let bin = home.join("bin");
    let mut paths = vec![bin];
    if let Some(existing) = env::var_os("PATH") {
        paths.extend(env::split_paths(&existing));
    }
    command.env("PATH", env::join_paths(paths)?);
    command.env("CC65_HOME", home);
    Ok(())
}

fn command_exists(name: &str) -> bool {
    Command::new(name)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok()
}

fn collect_asm(directory: &Path, output: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(directory)? {
        let path = entry?.path();
        if path.is_dir() {
            collect_asm(&path, output)?;
        } else if path.extension().is_some_and(|extension| extension == "asm") {
            output.push(path);
        }
    }
    Ok(())
}

fn bootstrap(root: &Path) -> Result<()> {
    let local = root.join(".tools/cc65/bin");
    if local.join("ca65.exe").is_file() && local.join("ld65.exe").is_file() {
        println!("pinned cc65 is already installed in .tools/cc65");
        return Ok(());
    }
    ensure!(
        cfg!(all(windows, target_arch = "x86_64")),
        "automatic bootstrap currently supports 64-bit Windows only"
    );

    let config =
        fs::read_to_string(root.join("spec/toolchain.toml")).context("read spec/toolchain.toml")?;
    let config: ToolchainFile = toml::from_str(&config).context("parse spec/toolchain.toml")?;
    let archive = config.cc65.windows_x86_64;
    println!(
        "downloading cc65 Windows snapshot {}",
        archive.snapshot_date
    );

    let response = reqwest::blocking::Client::builder()
        .user_agent("snes-modem-control-xtask")
        .build()?
        .get(&archive.url)
        .send()
        .with_context(|| format!("download {}", archive.url))?
        .error_for_status()?;
    let bytes = response.bytes()?.to_vec();
    let actual_hash = format!("{:x}", Sha256::digest(&bytes));
    ensure!(
        actual_hash == archive.sha256.to_ascii_lowercase(),
        "cc65 archive hash mismatch: expected {}, got {actual_hash}",
        archive.sha256
    );

    let tools_directory = root.join(".tools");
    fs::create_dir_all(&tools_directory)?;
    let destination = tools_directory.join("cc65");
    ensure!(
        !destination.exists(),
        "{} exists but does not contain usable cc65 tools",
        destination.display()
    );
    let stage = tools_directory.join(format!("cc65-stage-{}", std::process::id()));
    ensure!(
        !stage.exists(),
        "bootstrap staging directory already exists"
    );
    fs::create_dir(&stage)?;

    let mut zip = zip::ZipArchive::new(io::Cursor::new(bytes)).context("open cc65 ZIP")?;
    for index in 0..zip.len() {
        let mut entry = zip.by_index(index)?;
        let relative = entry
            .enclosed_name()
            .context("cc65 ZIP contains an unsafe path")?
            .to_owned();
        let output = stage.join(relative);
        if entry.is_dir() {
            fs::create_dir_all(&output)?;
            continue;
        }
        if let Some(parent) = output.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = fs::File::create(&output)?;
        io::copy(&mut entry, &mut file)?;
    }

    fs::rename(&stage, &destination).context("activate bootstrapped cc65 directory")?;
    let tools = find_cc65(root)?;
    println!("installed {}", tools.ca65.display());
    Ok(())
}

fn run(command: &mut Command) -> Result<()> {
    println!("> {command:?}");
    let status = command.status().context("failed to start command")?;
    ensure!(status.success(), "command failed with {status}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn font8x8_generates_only_printable_ascii_in_plane_zero() {
        let root = workspace_root().unwrap();
        let (_, glyphs) = load_font8x8(&root).unwrap();
        let font = generate_sfc_font(&glyphs);

        assert_eq!(font.len(), 4096);
        for codepoint in 0..256 {
            for row in 0..8 {
                let plane_zero = font[codepoint * 16 + row * 2];
                let plane_one = font[codepoint * 16 + row * 2 + 1];
                let expected = if (0x20..=0x7e).contains(&codepoint) {
                    glyphs[codepoint][row].reverse_bits()
                } else {
                    0
                };
                assert_eq!(plane_zero, expected);
                assert_eq!(plane_one, 0);
            }
        }
    }

    #[test]
    fn font_test_specimen_contains_every_printable_ascii_byte() {
        let specimen = FONT_TEST_LINES[..6].concat();
        assert_eq!(specimen, (0x20_u8..=0x7e).collect::<Vec<_>>());
        assert!(FONT_TEST_LINES.iter().all(|line| line.len() <= 32));
        let queued_bytes = FONT_TEST_LINES
            .iter()
            .map(|line| line.len() + 1)
            .sum::<usize>();
        assert!(queued_bytes <= 255);
    }

    #[test]
    fn terminal_palette_is_black_and_dimmed_white() {
        let root = workspace_root().unwrap();
        let spec = read_spec(&root).unwrap();
        let palette = generate_palette(&spec).unwrap();
        assert_eq!(palette.len(), 512);
        assert_eq!(&palette[..8], &[0x00, 0x00, 0x7b, 0x6f, 0, 0, 0, 0]);
        assert_eq!(decode_bgr555(0x6f7b), [222, 222, 222]);
        assert!(palette[8..].iter().all(|&byte| byte == 0));
    }
}
