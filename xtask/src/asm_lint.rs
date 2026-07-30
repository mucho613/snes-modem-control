use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Profile {
    Normal,
    Smoke,
    FontTest,
}

impl Profile {
    pub const ALL: [Self; 3] = [Self::Normal, Self::Smoke, Self::FontTest];

    fn name(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Smoke => "smoke",
            Self::FontTest => "font-test",
        }
    }

    fn defines(self) -> BTreeSet<&'static str> {
        match self {
            Self::Normal => BTreeSet::new(),
            Self::Smoke => BTreeSet::from(["MODEM_SMOKE_TEST"]),
            Self::FontTest => BTreeSet::from(["MODEM_FONT_TEST"]),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Width {
    Eight,
    Sixteen,
}

impl Width {
    fn bits(self) -> u8 {
        match self {
            Self::Eight => 8,
            Self::Sixteen => 16,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum StackItem {
    A(Width),
    X(Width),
    Y(Width),
    Status { a: Width, i: Width },
    Bank,
    DirectPage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct RuntimeState {
    a: Width,
    i: Width,
    stack: Vec<StackItem>,
    calls: Vec<CallFrame>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CallFrame {
    return_index: usize,
    stack: Vec<StackItem>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Abi {
    a: Width,
    i: Width,
}

#[derive(Debug, Clone)]
struct Location {
    path: PathBuf,
    line: usize,
}

#[derive(Debug, Clone)]
struct Statement {
    location: Location,
    text: String,
    mnemonic: String,
    operand: String,
    asm_a: Option<Width>,
    asm_i: Option<Width>,
}

#[derive(Debug, Clone)]
struct Procedure {
    name: String,
    location: Location,
    statements: Vec<Statement>,
    abi: Option<Abi>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Diagnostic {
    pub path: PathBuf,
    pub line: usize,
    pub column: usize,
    pub profile: &'static str,
    pub message: String,
}

impl Diagnostic {
    fn new(location: &Location, profile: Profile, message: impl Into<String>) -> Self {
        Self {
            path: location.path.clone(),
            line: location.line,
            column: 1,
            profile: profile.name(),
            message: message.into(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Options {
    pub enforce_policy: bool,
}

pub fn run(root: &Path, audit: bool) -> Result<()> {
    let diagnostics = lint_workspace(
        root,
        Options {
            enforce_policy: true,
        },
    )?;
    let mut grouped = BTreeMap::<(PathBuf, usize, usize, String), BTreeSet<&str>>::new();
    for diagnostic in &diagnostics {
        grouped
            .entry((
                diagnostic.path.clone(),
                diagnostic.line,
                diagnostic.column,
                diagnostic.message.clone(),
            ))
            .or_default()
            .insert(diagnostic.profile);
    }
    for ((path, line, column, message), profiles) in &grouped {
        let path = path.strip_prefix(root).unwrap_or(path);
        println!(
            "{}:{}:{}: error[asm-width:{}]: {}",
            path.display(),
            line,
            column,
            profiles.iter().copied().collect::<Vec<_>>().join(","),
            message
        );
    }
    if diagnostics.is_empty() {
        println!("65816 width lint passed");
        return Ok(());
    }
    if audit {
        println!(
            "65816 width lint audit found {} unique violation(s) across {} profile result(s)",
            grouped.len(),
            diagnostics.len(),
        );
        Ok(())
    } else {
        bail!(
            "65816 width lint failed with {} unique violation(s) across {} profile result(s)",
            grouped.len(),
            diagnostics.len(),
        )
    }
}

pub fn lint_workspace(root: &Path, options: Options) -> Result<Vec<Diagnostic>> {
    let mut paths = Vec::new();
    collect_sources(&root.join("src"), &mut paths)?;
    paths.sort();

    let mut diagnostics = BTreeSet::new();
    for profile in Profile::ALL {
        let mut procedures = Vec::new();
        for path in &paths {
            let source =
                fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
            procedures.extend(parse_procedures(
                path,
                &source,
                profile,
                options,
                &mut diagnostics,
            ));
        }
        analyze_procedures(profile, &procedures, &mut diagnostics);
    }
    Ok(diagnostics.into_iter().collect())
}

fn collect_sources(directory: &Path, output: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(directory).with_context(|| format!("read {}", directory.display()))? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_sources(&path, output)?;
        } else if matches!(
            path.extension().and_then(|extension| extension.to_str()),
            Some("asm" | "inc")
        ) {
            output.push(path);
        }
    }
    Ok(())
}

fn parse_procedures(
    path: &Path,
    source: &str,
    profile: Profile,
    options: Options,
    diagnostics: &mut BTreeSet<Diagnostic>,
) -> Vec<Procedure> {
    let active_lines = active_lines(source, profile);
    let mut procedures = Vec::new();
    let mut current: Option<Procedure> = None;
    let mut asm_a = None;
    let mut asm_i = None;
    let mut entry_a = None;
    let mut entry_i = None;
    let mut seen_body = false;
    let in_utility = path.ends_with(Path::new("macro/utility.asm"));

    for (line_index, active) in active_lines.into_iter().enumerate() {
        if !active {
            continue;
        }
        let line_number = line_index + 1;
        let original = source.lines().nth(line_index).unwrap_or_default();
        let code = strip_comment(original).trim();
        if code.is_empty() {
            continue;
        }

        if let Some(name) = code.strip_prefix(".proc ").map(str::trim) {
            if current.is_some() {
                diagnostics.insert(Diagnostic::new(
                    &Location {
                        path: path.to_path_buf(),
                        line: line_number,
                    },
                    profile,
                    "nested .proc is not supported",
                ));
                continue;
            }
            current = Some(Procedure {
                name: name.to_owned(),
                location: Location {
                    path: path.to_path_buf(),
                    line: line_number,
                },
                statements: Vec::new(),
                abi: None,
            });
            asm_a = None;
            asm_i = None;
            entry_a = None;
            entry_i = None;
            seen_body = false;
            continue;
        }
        if code == ".endproc" {
            if let Some(mut procedure) = current.take() {
                procedure.abi = match (entry_a, entry_i) {
                    (Some(a), Some(i)) => Some(Abi { a, i }),
                    _ => {
                        diagnostics.insert(Diagnostic::new(
                            &procedure.location,
                            profile,
                            "procedure must declare .a8/.a16 and .i8/.i16 at entry",
                        ));
                        None
                    }
                };
                procedures.push(procedure);
            }
            continue;
        }

        let Some(procedure) = current.as_mut() else {
            continue;
        };
        let location = Location {
            path: path.to_path_buf(),
            line: line_number,
        };
        let (mnemonic, operand) = split_statement(code);
        let lower = mnemonic.to_ascii_lowercase();

        if let Some(width) = accumulator_directive(&lower) {
            asm_a = Some(width);
            if !seen_body && entry_a.is_none() {
                entry_a = Some(width);
            } else if options.enforce_policy {
                diagnostics.insert(Diagnostic::new(
                    &location,
                    profile,
                    "bare accumulator-width directive is forbidden outside procedure ABI; use a width macro or width assert",
                ));
            }
        } else if let Some(width) = index_directive(&lower) {
            asm_i = Some(width);
            if !seen_body && entry_i.is_none() {
                entry_i = Some(width);
            } else if options.enforce_policy {
                diagnostics.insert(Diagnostic::new(
                    &location,
                    profile,
                    "bare index-width directive is forbidden outside procedure ABI; use a width macro or width assert",
                ));
            }
        } else if !lower.starts_with('.') && !is_label(code) {
            seen_body = true;
        }

        if options.enforce_policy
            && !in_utility
            && matches!(lower.as_str(), "rep" | "sep" | "plp" | "xce")
        {
            diagnostics.insert(Diagnostic::new(
                &location,
                profile,
                format!("bare {lower} is forbidden; use the width-safe macro"),
            ));
        }
        if options.enforce_policy && lower == "rti" {
            diagnostics.insert(Diagnostic::new(
                &location,
                profile,
                "RTI is only permitted in a modeled interrupt procedure",
            ));
        }

        let statement = Statement {
            location,
            text: code.to_owned(),
            mnemonic: lower.clone(),
            operand: operand.to_owned(),
            asm_a,
            asm_i,
        };
        procedure.statements.push(statement);

        match lower.as_str() {
            "m8" => asm_a = Some(Width::Eight),
            "m16" => asm_a = Some(Width::Sixteen),
            "i8" => asm_i = Some(Width::Eight),
            "i16" => asm_i = Some(Width::Sixteen),
            "mi8" => {
                asm_a = Some(Width::Eight);
                asm_i = Some(Width::Eight);
            }
            "mi16" => {
                asm_a = Some(Width::Sixteen);
                asm_i = Some(Width::Sixteen);
            }
            "assert_m8_i8" => {
                asm_a = Some(Width::Eight);
                asm_i = Some(Width::Eight);
            }
            "assert_m8_i16" => {
                asm_a = Some(Width::Eight);
                asm_i = Some(Width::Sixteen);
            }
            "assert_m16_i8" => {
                asm_a = Some(Width::Sixteen);
                asm_i = Some(Width::Eight);
            }
            "assert_m16_i16" => {
                asm_a = Some(Width::Sixteen);
                asm_i = Some(Width::Sixteen);
            }
            _ => {}
        }
    }

    procedures
}

fn active_lines(source: &str, profile: Profile) -> Vec<bool> {
    #[derive(Clone, Copy)]
    struct Conditional {
        parent_active: bool,
        condition: bool,
        in_else: bool,
    }

    let defines = profile.defines();
    let mut stack = Vec::<Conditional>::new();
    let mut active = true;
    let mut output = Vec::new();
    for line in source.lines() {
        let code = strip_comment(line).trim();
        if let Some(symbol) = code.strip_prefix(".ifdef ").map(str::trim) {
            let condition = defines.contains(symbol);
            stack.push(Conditional {
                parent_active: active,
                condition,
                in_else: false,
            });
            active &= condition;
            output.push(false);
        } else if let Some(symbol) = code.strip_prefix(".ifndef ").map(str::trim) {
            let condition = !defines.contains(symbol);
            stack.push(Conditional {
                parent_active: active,
                condition,
                in_else: false,
            });
            active &= condition;
            output.push(false);
        } else if code == ".else" {
            if let Some(conditional) = stack.last_mut() {
                conditional.in_else = true;
                active = conditional.parent_active && !conditional.condition;
            }
            output.push(false);
        } else if code == ".endif" {
            if let Some(conditional) = stack.pop() {
                active = conditional.parent_active;
            }
            output.push(false);
        } else {
            output.push(active);
        }
    }
    output
}

fn analyze_procedures(
    profile: Profile,
    procedures: &[Procedure],
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    let abis: BTreeMap<_, _> = procedures
        .iter()
        .filter_map(|procedure| procedure.abi.map(|abi| (procedure.name.as_str(), abi)))
        .collect();
    for procedure in procedures {
        let Some(abi) = procedure.abi else {
            continue;
        };
        analyze_procedure(profile, procedure, abi, &abis, diagnostics);
    }
}

fn analyze_procedure(
    profile: Profile,
    procedure: &Procedure,
    abi: Abi,
    abis: &BTreeMap<&str, Abi>,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    if procedure.statements.is_empty() {
        return;
    }
    let labels = collect_labels(&procedure.statements);
    let anonymous = collect_anonymous_labels(&procedure.statements);
    let initial = RuntimeState {
        a: abi.a,
        i: abi.i,
        stack: Vec::new(),
        calls: Vec::new(),
    };
    let mut states: Vec<Vec<RuntimeState>> = vec![Vec::new(); procedure.statements.len()];
    states[0].push(initial.clone());
    let mut queue = VecDeque::from([(0_usize, initial)]);

    while let Some((index, input)) = queue.pop_front() {
        let statement = &procedure.statements[index];
        validate_statement_width(profile, statement, &input, abis, diagnostics);
        if matches!(statement.mnemonic.as_str(), "rts" | "rtl") {
            handle_return(
                profile,
                procedure,
                abi,
                statement,
                input,
                &mut states,
                &mut queue,
                diagnostics,
            );
            continue;
        }
        let Some(mut output) = transfer(profile, statement, input, diagnostics) else {
            continue;
        };
        if matches!(statement.mnemonic.as_str(), "jsr" | "jsl")
            && let Some(target) = resolve_target(index, &statement.operand, &labels, &anonymous)
        {
            let return_index = index + 1;
            output.calls.push(CallFrame {
                return_index,
                stack: output.stack.clone(),
            });
            merge_state(
                profile,
                &procedure.statements,
                target,
                output,
                &mut states,
                &mut queue,
                diagnostics,
            );
            continue;
        }
        for successor in successors(index, &procedure.statements, &labels, &anonymous) {
            merge_state(
                profile,
                &procedure.statements,
                successor,
                output.clone(),
                &mut states,
                &mut queue,
                diagnostics,
            );
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn handle_return(
    profile: Profile,
    procedure: &Procedure,
    abi: Abi,
    statement: &Statement,
    mut state: RuntimeState,
    states: &mut [Vec<RuntimeState>],
    queue: &mut VecDeque<(usize, RuntimeState)>,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    if let Some(frame) = state.calls.pop() {
        if state.stack != frame.stack {
            diagnostics.insert(Diagnostic::new(
                &statement.location,
                profile,
                format!(
                    "local return has unbalanced stack: expected {:?} but found {:?}",
                    frame.stack, state.stack
                ),
            ));
            return;
        }
        merge_state(
            profile,
            &procedure.statements,
            frame.return_index,
            state,
            states,
            queue,
            diagnostics,
        );
        return;
    }

    if !state.stack.is_empty() {
        diagnostics.insert(Diagnostic::new(
            &statement.location,
            profile,
            format!("return leaves stack items behind: {:?}", state.stack),
        ));
    }
    if state.a != abi.a || state.i != abi.i {
        diagnostics.insert(Diagnostic::new(
            &statement.location,
            profile,
            format!(
                "return ABI requires A{}/I{} but control flow has A{}/I{}",
                abi.a.bits(),
                abi.i.bits(),
                state.a.bits(),
                state.i.bits()
            ),
        ));
    }
}

fn merge_state(
    profile: Profile,
    statements: &[Statement],
    successor: usize,
    incoming: RuntimeState,
    states: &mut [Vec<RuntimeState>],
    queue: &mut VecDeque<(usize, RuntimeState)>,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    if successor >= states.len() {
        return;
    }
    if states[successor]
        .iter()
        .any(|existing| existing == &incoming)
    {
        return;
    }
    if let Some(existing) = states[successor]
        .iter()
        .find(|existing| existing.calls == incoming.calls)
    {
        diagnostics.insert(Diagnostic::new(
                &statements[successor].location,
                profile,
                format!(
                    "control-flow merge has incompatible width/stack states: incoming {} versus existing {}",
                    render_state(&incoming),
                    render_state(existing)
                ),
            ));
        return;
    }
    states[successor].push(incoming.clone());
    queue.push_back((successor, incoming));
}

fn validate_statement_width(
    profile: Profile,
    statement: &Statement,
    state: &RuntimeState,
    abis: &BTreeMap<&str, Abi>,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    if accumulator_immediate(&statement.mnemonic, &statement.operand) {
        if statement.asm_a != Some(state.a) {
            diagnostics.insert(Diagnostic::new(
                &statement.location,
                profile,
                format!(
                    "{} immediate is encoded as A{} but runtime A is {}",
                    statement.mnemonic.to_ascii_uppercase(),
                    statement.asm_a.map_or(0, Width::bits),
                    state.a.bits()
                ),
            ));
        }
    }
    if index_immediate(&statement.mnemonic, &statement.operand) && statement.asm_i != Some(state.i)
    {
        diagnostics.insert(Diagnostic::new(
            &statement.location,
            profile,
            format!(
                "{} immediate is encoded as I{} but runtime index width is {}",
                statement.mnemonic.to_ascii_uppercase(),
                statement.asm_i.map_or(0, Width::bits),
                state.i.bits()
            ),
        ));
    }
    if matches!(statement.mnemonic.as_str(), "jsr" | "jsl") {
        let target = normalize_target(&statement.operand);
        if !target.starts_with('@')
            && let Some(callee) = abis.get(target)
            && (callee.a != state.a || callee.i != state.i)
        {
            diagnostics.insert(Diagnostic::new(
                &statement.location,
                profile,
                format!(
                    "call to {target} requires A{}/I{} but caller has A{}/I{}",
                    callee.a.bits(),
                    callee.i.bits(),
                    state.a.bits(),
                    state.i.bits()
                ),
            ));
        }
    }
}

fn transfer(
    profile: Profile,
    statement: &Statement,
    mut state: RuntimeState,
    diagnostics: &mut BTreeSet<Diagnostic>,
) -> Option<RuntimeState> {
    match statement.mnemonic.as_str() {
        "m8" => state.a = Width::Eight,
        "m16" => state.a = Width::Sixteen,
        "i8" => state.i = Width::Eight,
        "i16" => state.i = Width::Sixteen,
        "mi8" => {
            state.a = Width::Eight;
            state.i = Width::Eight;
        }
        "mi16" => {
            state.a = Width::Sixteen;
            state.i = Width::Sixteen;
        }
        "assert_m8_i8" => assert_state(
            profile,
            statement,
            &state,
            Abi {
                a: Width::Eight,
                i: Width::Eight,
            },
            diagnostics,
        ),
        "assert_m8_i16" => assert_state(
            profile,
            statement,
            &state,
            Abi {
                a: Width::Eight,
                i: Width::Sixteen,
            },
            diagnostics,
        ),
        "assert_m16_i8" => assert_state(
            profile,
            statement,
            &state,
            Abi {
                a: Width::Sixteen,
                i: Width::Eight,
            },
            diagnostics,
        ),
        "assert_m16_i16" => assert_state(
            profile,
            statement,
            &state,
            Abi {
                a: Width::Sixteen,
                i: Width::Sixteen,
            },
            diagnostics,
        ),
        "rep" | "sep" => {
            apply_status_immediate(&statement.mnemonic, &statement.operand, &mut state)
        }
        "pha" => state.stack.push(StackItem::A(state.a)),
        "phx" => state.stack.push(StackItem::X(state.i)),
        "phy" => state.stack.push(StackItem::Y(state.i)),
        "php" => state.stack.push(StackItem::Status {
            a: state.a,
            i: state.i,
        }),
        "phb" => state.stack.push(StackItem::Bank),
        "phd" => state.stack.push(StackItem::DirectPage),
        "pla" => {
            let width = state.a;
            pop_expected(
                profile,
                statement,
                &mut state,
                StackItem::A(width),
                diagnostics,
            );
        }
        "plx" => {
            let width = state.i;
            pop_expected(
                profile,
                statement,
                &mut state,
                StackItem::X(width),
                diagnostics,
            );
        }
        "ply" => {
            let width = state.i;
            pop_expected(
                profile,
                statement,
                &mut state,
                StackItem::Y(width),
                diagnostics,
            );
        }
        "plb" => pop_expected(profile, statement, &mut state, StackItem::Bank, diagnostics),
        "pld" => pop_expected(
            profile,
            statement,
            &mut state,
            StackItem::DirectPage,
            diagnostics,
        ),
        "plp" => match state.stack.pop() {
            Some(StackItem::Status { a, i }) => {
                state.a = a;
                state.i = i;
            }
            actual => {
                diagnostics.insert(Diagnostic::new(
                    &statement.location,
                    profile,
                    format!("PLP does not match saved status; stack top is {actual:?}"),
                ));
            }
        },
        "plp_m8_i8" => restore_status(
            profile,
            statement,
            &mut state,
            Abi {
                a: Width::Eight,
                i: Width::Eight,
            },
            diagnostics,
        ),
        "plp_m8_i16" => restore_status(
            profile,
            statement,
            &mut state,
            Abi {
                a: Width::Eight,
                i: Width::Sixteen,
            },
            diagnostics,
        ),
        "plp_m16_i8" => restore_status(
            profile,
            statement,
            &mut state,
            Abi {
                a: Width::Sixteen,
                i: Width::Eight,
            },
            diagnostics,
        ),
        "plp_m16_i16" => restore_status(
            profile,
            statement,
            &mut state,
            Abi {
                a: Width::Sixteen,
                i: Width::Sixteen,
            },
            diagnostics,
        ),
        "rti" | "stp" => return None,
        _ => {}
    }
    Some(state)
}

fn assert_state(
    profile: Profile,
    statement: &Statement,
    state: &RuntimeState,
    expected: Abi,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    if state.a != expected.a || state.i != expected.i {
        diagnostics.insert(Diagnostic::new(
            &statement.location,
            profile,
            format!(
                "width assert expects A{}/I{} but control flow has A{}/I{}",
                expected.a.bits(),
                expected.i.bits(),
                state.a.bits(),
                state.i.bits()
            ),
        ));
    }
}

fn restore_status(
    profile: Profile,
    statement: &Statement,
    state: &mut RuntimeState,
    expected: Abi,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    match state.stack.pop() {
        Some(StackItem::Status { a, i }) if a == expected.a && i == expected.i => {
            state.a = a;
            state.i = i;
        }
        actual => {
            diagnostics.insert(Diagnostic::new(
                &statement.location,
                profile,
                format!(
                    "status restore expects saved A{}/I{} but stack top is {actual:?}",
                    expected.a.bits(),
                    expected.i.bits()
                ),
            ));
        }
    }
}

fn pop_expected(
    profile: Profile,
    statement: &Statement,
    state: &mut RuntimeState,
    expected: StackItem,
    diagnostics: &mut BTreeSet<Diagnostic>,
) {
    let actual = state.stack.pop();
    if actual.as_ref() != Some(&expected) {
        diagnostics.insert(Diagnostic::new(
            &statement.location,
            profile,
            format!("stack pop expects {expected:?} but found {actual:?}"),
        ));
    }
}

fn apply_status_immediate(mnemonic: &str, operand: &str, state: &mut RuntimeState) {
    let Some(value) = parse_immediate(operand) else {
        return;
    };
    let set = mnemonic == "sep";
    if value & 0x20 != 0 {
        state.a = if set { Width::Eight } else { Width::Sixteen };
    }
    if value & 0x10 != 0 {
        state.i = if set { Width::Eight } else { Width::Sixteen };
    }
}

fn successors(
    index: usize,
    statements: &[Statement],
    labels: &BTreeMap<String, usize>,
    anonymous: &[usize],
) -> Vec<usize> {
    let statement = &statements[index];
    let next = index + 1;
    match statement.mnemonic.as_str() {
        "rts" | "rtl" | "rti" | "stp" => Vec::new(),
        "bra" | "brl" | "jmp" | "jml" => {
            resolve_target(index, &statement.operand, labels, anonymous)
                .into_iter()
                .collect()
        }
        "bcc" | "bcs" | "beq" | "bmi" | "bne" | "bpl" | "bvc" | "bvs" => {
            let mut output = Vec::new();
            if next < statements.len() {
                output.push(next);
            }
            if let Some(target) = resolve_target(index, &statement.operand, labels, anonymous)
                && !output.contains(&target)
            {
                output.push(target);
            }
            output
        }
        _ if next < statements.len() => vec![next],
        _ => Vec::new(),
    }
}

fn collect_labels(statements: &[Statement]) -> BTreeMap<String, usize> {
    statements
        .iter()
        .enumerate()
        .filter_map(|(index, statement)| {
            label_name(&statement.text)
                .filter(|name| !name.is_empty())
                .map(|name| (name.to_owned(), index))
        })
        .collect()
}

fn collect_anonymous_labels(statements: &[Statement]) -> Vec<usize> {
    statements
        .iter()
        .enumerate()
        .filter_map(|(index, statement)| (statement.text.trim() == ":").then_some(index))
        .collect()
}

fn resolve_target(
    index: usize,
    operand: &str,
    labels: &BTreeMap<String, usize>,
    anonymous: &[usize],
) -> Option<usize> {
    let target = normalize_target(operand);
    if let Some(suffix) = target.strip_prefix(':') {
        if suffix.chars().all(|character| character == '+') {
            return anonymous
                .iter()
                .copied()
                .filter(|candidate| *candidate > index)
                .nth(suffix.len().saturating_sub(1));
        }
        if suffix.chars().all(|character| character == '-') {
            return anonymous
                .iter()
                .copied()
                .filter(|candidate| *candidate < index)
                .rev()
                .nth(suffix.len().saturating_sub(1));
        }
    }
    labels.get(target).copied()
}

fn normalize_target(operand: &str) -> &str {
    operand
        .split_once(',')
        .map_or(operand, |(target, _)| target)
        .trim()
}

fn render_state(state: &RuntimeState) -> String {
    format!(
        "A{}/I{} stack={:?}",
        state.a.bits(),
        state.i.bits(),
        state.stack
    )
}

fn strip_comment(line: &str) -> &str {
    line.split_once(';').map_or(line, |(code, _)| code)
}

fn split_statement(code: &str) -> (&str, &str) {
    let code = code.trim();
    if is_label(code) {
        return (code, "");
    }
    code.split_once(char::is_whitespace)
        .map_or((code, ""), |(mnemonic, operand)| (mnemonic, operand.trim()))
}

fn is_label(code: &str) -> bool {
    code.ends_with(':')
}

fn label_name(code: &str) -> Option<&str> {
    code.trim().strip_suffix(':')
}

fn accumulator_directive(mnemonic: &str) -> Option<Width> {
    match mnemonic {
        ".a8" => Some(Width::Eight),
        ".a16" => Some(Width::Sixteen),
        _ => None,
    }
}

fn index_directive(mnemonic: &str) -> Option<Width> {
    match mnemonic {
        ".i8" => Some(Width::Eight),
        ".i16" => Some(Width::Sixteen),
        _ => None,
    }
}

fn accumulator_immediate(mnemonic: &str, operand: &str) -> bool {
    operand.trim_start().starts_with('#')
        && matches!(
            mnemonic,
            "adc" | "and" | "bit" | "cmp" | "eor" | "lda" | "ora" | "sbc"
        )
}

fn index_immediate(mnemonic: &str, operand: &str) -> bool {
    operand.trim_start().starts_with('#') && matches!(mnemonic, "cpx" | "cpy" | "ldx" | "ldy")
}

fn parse_immediate(operand: &str) -> Option<u8> {
    let value = operand.trim().strip_prefix('#')?.trim();
    if let Some(hex) = value.strip_prefix('$') {
        u8::from_str_radix(hex, 16).ok()
    } else {
        value.parse().ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lint(source: &str) -> Vec<Diagnostic> {
        let path = Path::new("fixture.asm");
        let mut diagnostics = BTreeSet::new();
        let procedures = parse_procedures(
            path,
            source,
            Profile::Normal,
            Options {
                enforce_policy: true,
            },
            &mut diagnostics,
        );
        analyze_procedures(Profile::Normal, &procedures, &mut diagnostics);
        diagnostics.into_iter().collect()
    }

    fn messages(source: &str) -> Vec<String> {
        lint(source)
            .into_iter()
            .map(|diagnostic| diagnostic.message)
            .collect()
    }

    #[test]
    fn accepts_fixed_abi_width_macros_and_balanced_stack() {
        let diagnostics = lint(
            r#"
.proc valid
  .a8
  .i16
  pha
  m16
  lda #$1234
  m8
  pla
  rts
.endproc
"#,
        );
        assert!(diagnostics.is_empty(), "{diagnostics:#?}");
    }

    #[test]
    fn detects_the_real_immediate_desynchronization_pattern() {
        let messages = messages(
            r#"
.proc broken
  .a8
  .i16
  rep #$20
  .a16
  lda #$0001
  beq :+
  sep #$20
  .a8
  jmp @failed
:
  cmp #$0001
@failed:
  m8
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("CMP immediate is encoded as A8"))
        );
    }

    #[test]
    fn rejects_incompatible_branch_merge() {
        let messages = messages(
            r#"
.proc merge
  .a8
  .i16
  beq @wide
  bra @join
@wide:
  m16
@join:
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("control-flow merge"))
        );
    }

    #[test]
    fn rejects_call_abi_mismatch() {
        let messages = messages(
            r#"
.proc caller
  .a8
  .i16
  jsr callee
  rts
.endproc
.proc callee
  .a16
  .i16
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("call to callee requires A16/I16"))
        );
    }

    #[test]
    fn rejects_width_dependent_stack_mismatch() {
        let messages = messages(
            r#"
.proc stack
  .a16
  .i16
  pha
  m8
  pla
  m16
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("stack pop expects A(Eight)"))
        );
    }

    #[test]
    fn validates_status_restore_macro_against_saved_width() {
        let messages = messages(
            r#"
.proc status
  .a8
  .i16
  php
  mi16
  plp_m16_i16
  mi8
  i16
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("status restore expects saved A16/I16"))
        );
    }

    #[test]
    fn rejects_bare_width_operations_and_midprocedure_directives() {
        let messages = messages(
            r#"
.proc policy
  .a8
  .i16
  rep #$20
  .a16
  plp
  xce
  rts
.endproc
"#,
        );
        assert!(messages.iter().any(|message| message.contains("bare rep")));
        assert!(messages.iter().any(|message| message.contains("bare plp")));
        assert!(messages.iter().any(|message| message.contains("bare xce")));
        assert!(
            messages
                .iter()
                .any(|message| message.contains("bare accumulator-width directive"))
        );
    }

    #[test]
    fn profile_filter_exposes_smoke_only_error() {
        let source = r#"
.proc conditional
  .a8
  .i16
  .ifdef MODEM_SMOKE_TEST
  rep #$20
  .endif
  rts
.endproc
"#;
        let path = Path::new("fixture.asm");
        let mut normal_diagnostics = BTreeSet::new();
        let normal = parse_procedures(
            path,
            source,
            Profile::Normal,
            Options {
                enforce_policy: true,
            },
            &mut normal_diagnostics,
        );
        analyze_procedures(Profile::Normal, &normal, &mut normal_diagnostics);
        assert!(normal_diagnostics.is_empty());

        let mut smoke_diagnostics = BTreeSet::new();
        let smoke = parse_procedures(
            path,
            source,
            Profile::Smoke,
            Options {
                enforce_policy: true,
            },
            &mut smoke_diagnostics,
        );
        analyze_procedures(Profile::Smoke, &smoke, &mut smoke_diagnostics);
        assert!(
            smoke_diagnostics
                .iter()
                .any(|diagnostic| diagnostic.message.contains("bare rep"))
        );
    }

    #[test]
    fn width_assert_is_checked_against_control_flow() {
        let messages = messages(
            r#"
.proc assertion
  .a8
  .i16
  assert_m16_i16
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("width assert expects A16/I16"))
        );
    }

    #[test]
    fn follows_local_subroutine_calls_into_width_asserts() {
        let messages = messages(
            r#"
.proc local_call
  .a8
  .i16
  jsr @helper
  rts

@helper:
  assert_m16_i16
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("width assert expects A16/I16"))
        );
    }

    #[test]
    fn keeps_local_subroutine_return_contexts_separate() {
        let messages = messages(
            r#"
.proc repeated_local_call
  .a8
  .i16
  jsr @helper
  jsr @helper
  rts

@helper:
  assert_m8_i16
  rts
.endproc
"#,
        );
        assert!(messages.is_empty(), "{messages:?}");
    }

    #[test]
    fn rejects_return_width_that_differs_from_entry_abi() {
        let messages = messages(
            r#"
.proc changed_return
  .a8
  .i16
  m16
  rts
.endproc
"#,
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("return ABI requires A8/I16"))
        );
    }
}
