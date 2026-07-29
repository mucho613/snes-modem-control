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
    },
    Deploy {
        #[arg(long)]
        smoke: bool,
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
    diagnostic: Diagnostic,
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
        Task::Rom { smoke } => build_rom(&root, smoke),
        Task::Deploy {
            smoke,
            websocket,
            remote_path,
        } => {
            build_rom(&root, smoke)?;
            let rom = root
                .join(if smoke { "build/smoke" } else { "build/normal" })
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
            build_rom(&root, false)?;
            build_rom(&root, true)
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
    validate_fields(&spec.diagnostic.fields, spec.diagnostic.size, "diagnostic")?;
    validate_fields(&spec.mailbox.fields, spec.mailbox.size, "mailbox")?;
    ensure!(
        spec.diagnostic.trace_event_size * spec.diagnostic.trace_capacity
            == spec.diagnostic.trace_size,
        "trace size does not match event size times capacity"
    );
    Ok(())
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
    Ok(())
}

fn render_assembly(spec: &SpecFile) -> Result<String> {
    let mut out = generated_banner(";");
    scalar_maps_asm(&mut out, "MODEM", &spec.protocol)?;
    scalar_maps_asm(&mut out, "MODEM", &spec.driver)?;
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

fn build_rom(root: &Path, smoke: bool) -> Result<()> {
    let tools = find_cc65(root)?;
    let out = root.join(if smoke { "build/smoke" } else { "build/normal" });
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
        if smoke {
            command.args(["-D", "MODEM_SMOKE_TEST"]);
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
