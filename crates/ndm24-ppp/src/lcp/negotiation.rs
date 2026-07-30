//! RFC 1661 LCP establishment and peer-initiated termination reference
//! implementation.

use super::{
    Code, ConfigurationOption, EncodeError, OptionParseError, OptionType, Packet, ParseError,
    configuration_options, encode_into,
};

pub const DEFAULT_RESTART_INTERVAL_MS: u64 = 3_000;
pub const DEFAULT_MAX_CONFIGURE: u8 = 10;
pub const DEFAULT_MRU: u16 = 1_500;
pub const DEFAULT_ACCM: u32 = u32::MAX;
pub const PAP_PROTOCOL: u16 = 0xc023;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Closed,
    RequestSent,
    AckReceived,
    AckSent,
    Opened,
    Stopped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthenticationProtocol {
    Pap,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PeerConfiguration {
    /// Maximum PPP Information length the peer permits us to transmit.
    pub transmit_mru: u16,
    /// Control characters the peer requires us to escape on transmission.
    pub transmit_accm: u32,
    /// Authentication protocol the peer requires us to perform.
    pub authentication: Option<AuthenticationProtocol>,
    pub magic_number: Option<u32>,
}

impl Default for PeerConfiguration {
    fn default() -> Self {
        Self {
            transmit_mru: DEFAULT_MRU,
            transmit_accm: DEFAULT_ACCM,
            authentication: None,
            magic_number: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SfcPolicy {
    pub accept_pap: bool,
}

impl Default for SfcPolicy {
    fn default() -> Self {
        Self { accept_pap: true }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    SendPacket(Vec<u8>),
    ThisLayerUp(PeerConfiguration),
    ThisLayerDown,
    ThisLayerFinished,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IgnoreReason {
    MalformedPacket(ParseError),
    MalformedOptions(OptionParseError),
    InvalidConfigureResponse,
    UnsupportedCode(u8),
    NotConfiguring,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Transition {
    pub actions: Vec<Action>,
    pub ignored: Option<IgnoreReason>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    pub restart_interval_ms: u64,
    pub max_configure: u8,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            restart_interval_ms: DEFAULT_RESTART_INTERVAL_MS,
            max_configure: DEFAULT_MAX_CONFIGURE,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MachineError {
    InvalidLocalOptions(OptionParseError),
    PacketTooLarge(EncodeError),
}

#[derive(Debug, Clone)]
pub struct Machine {
    state: State,
    settings: Settings,
    local_options: Vec<u8>,
    request_identifier: u8,
    next_identifier: u8,
    restart_remaining: u8,
    restart_deadline_ms: Option<u64>,
    peer_configuration: Option<PeerConfiguration>,
}

impl Machine {
    pub fn new(local_options: &[u8], settings: Settings) -> Result<Self, MachineError> {
        validate_options(local_options).map_err(MachineError::InvalidLocalOptions)?;
        Ok(Self {
            state: State::Closed,
            settings,
            local_options: local_options.to_vec(),
            request_identifier: 0,
            next_identifier: 0,
            restart_remaining: 0,
            restart_deadline_ms: None,
            peer_configuration: None,
        })
    }

    pub fn state(&self) -> State {
        self.state
    }

    pub fn local_options(&self) -> &[u8] {
        &self.local_options
    }

    pub fn request_identifier(&self) -> u8 {
        self.request_identifier
    }

    pub fn restart_deadline_ms(&self) -> Option<u64> {
        self.restart_deadline_ms
    }

    pub fn open(&mut self, now_ms: u64) -> Result<Transition, MachineError> {
        if self.state == State::Opened {
            return Ok(Transition::default());
        }
        self.state = State::RequestSent;
        self.peer_configuration = None;
        let packet = self.send_new_request(now_ms, true)?;
        Ok(Transition {
            actions: vec![Action::SendPacket(packet)],
            ignored: None,
        })
    }

    pub fn lower_down(&mut self) -> Transition {
        let was_open = self.state == State::Opened;
        self.state = State::Closed;
        self.restart_deadline_ms = None;
        self.restart_remaining = 0;
        self.peer_configuration = None;
        Transition {
            actions: if was_open {
                vec![Action::ThisLayerDown]
            } else {
                Vec::new()
            },
            ignored: None,
        }
    }

    /// Build an RFC 1661 Protocol-Reject for an unrecognized PPP protocol.
    ///
    /// The rejected Protocol field is always present. Rejected-Information is
    /// truncated so the complete LCP packet fits the peer's negotiated MRU.
    pub fn reject_protocol(
        &mut self,
        protocol: u16,
        information: &[u8],
    ) -> Result<Transition, MachineError> {
        if self.state != State::Opened {
            return Ok(Transition {
                actions: Vec::new(),
                ignored: Some(IgnoreReason::NotConfiguring),
            });
        }

        let peer_mru = usize::from(
            self.peer_configuration
                .unwrap_or_default()
                .transmit_mru
                .max(6),
        );
        let information_length = information.len().min(peer_mru.saturating_sub(6));
        let mut rejected = Vec::with_capacity(2 + information_length);
        rejected.extend_from_slice(&protocol.to_be_bytes());
        rejected.extend_from_slice(&information[..information_length]);
        let identifier = self.allocate_identifier();

        Ok(Transition {
            actions: vec![Action::SendPacket(encode_packet(
                Code::ProtocolReject as u8,
                identifier,
                &rejected,
            )?)],
            ignored: None,
        })
    }

    pub fn poll_timeout(&mut self, now_ms: u64) -> Result<Transition, MachineError> {
        let Some(deadline) = self.restart_deadline_ms else {
            return Ok(Transition::default());
        };
        if now_ms < deadline {
            return Ok(Transition::default());
        }
        if !matches!(
            self.state,
            State::RequestSent | State::AckReceived | State::AckSent
        ) {
            self.restart_deadline_ms = None;
            return Ok(Transition::default());
        }
        if self.restart_remaining == 0 {
            self.state = State::Stopped;
            self.restart_deadline_ms = None;
            return Ok(Transition {
                actions: vec![Action::ThisLayerFinished],
                ignored: None,
            });
        }

        self.restart_remaining -= 1;
        if self.state == State::AckReceived {
            self.state = State::RequestSent;
        }
        self.restart_deadline_ms = Some(now_ms.saturating_add(self.settings.restart_interval_ms));
        Ok(Transition {
            actions: vec![Action::SendPacket(self.encode_request()?)],
            ignored: None,
        })
    }

    pub fn receive(
        &mut self,
        input: &[u8],
        now_ms: u64,
        policy: SfcPolicy,
    ) -> Result<Transition, MachineError> {
        if matches!(self.state, State::Closed | State::Stopped) {
            return Ok(Transition {
                actions: Vec::new(),
                ignored: Some(IgnoreReason::NotConfiguring),
            });
        }
        let packet = match Packet::parse(input) {
            Ok(packet) => packet,
            Err(error) => {
                return Ok(Transition {
                    actions: Vec::new(),
                    ignored: Some(IgnoreReason::MalformedPacket(error)),
                });
            }
        };

        match packet.known_code() {
            Some(Code::ConfigureRequest) => self.receive_configure_request(packet, now_ms, policy),
            Some(Code::ConfigureAck) => self.receive_configure_ack(packet, now_ms),
            Some(Code::ConfigureNak) => self.receive_configure_nak(packet, now_ms),
            Some(Code::ConfigureReject) => self.receive_configure_reject(packet, now_ms),
            Some(Code::TerminateRequest) => self.receive_terminate_request(packet),
            Some(Code::TerminateAck) => Ok(Transition::default()),
            None => self.receive_unknown_code(input, packet),
            Some(code) => Ok(Transition {
                actions: Vec::new(),
                ignored: Some(IgnoreReason::UnsupportedCode(code as u8)),
            }),
        }
    }

    fn receive_terminate_request(
        &mut self,
        packet: Packet<'_>,
    ) -> Result<Transition, MachineError> {
        let was_open = self.state == State::Opened;
        self.state = State::Stopped;
        self.restart_deadline_ms = None;
        self.restart_remaining = 0;
        self.peer_configuration = None;

        let mut actions = vec![Action::SendPacket(encode_packet(
            Code::TerminateAck as u8,
            packet.identifier,
            &[],
        )?)];
        if was_open {
            actions.push(Action::ThisLayerDown);
        }
        Ok(Transition {
            actions,
            ignored: None,
        })
    }

    fn receive_configure_request(
        &mut self,
        packet: Packet<'_>,
        now_ms: u64,
        policy: SfcPolicy,
    ) -> Result<Transition, MachineError> {
        let evaluation = match evaluate_peer_request(packet, policy) {
            Ok(evaluation) => evaluation,
            Err(error) => {
                return Ok(Transition {
                    actions: Vec::new(),
                    ignored: Some(IgnoreReason::MalformedOptions(error)),
                });
            }
        };
        let response = encode_packet(evaluation.code as u8, packet.identifier, &evaluation.data)?;
        let acceptable = evaluation.code == Code::ConfigureAck;
        if acceptable {
            self.peer_configuration = evaluation.configuration;
        }
        let mut actions = Vec::new();

        match (self.state, acceptable) {
            (State::RequestSent, true) | (State::AckSent, true) => {
                self.state = State::AckSent;
            }
            (State::AckReceived, true) => {
                self.state = State::Opened;
                self.restart_deadline_ms = None;
            }
            (State::Opened, true) => {
                actions.push(Action::ThisLayerDown);
                actions.push(Action::SendPacket(self.send_new_request(now_ms, true)?));
                self.state = State::AckSent;
            }
            (State::RequestSent, false) | (State::AckSent, false) => {
                self.state = State::RequestSent;
            }
            (State::AckReceived, false) => {}
            (State::Opened, false) => {
                actions.push(Action::ThisLayerDown);
                actions.push(Action::SendPacket(self.send_new_request(now_ms, true)?));
                self.state = State::RequestSent;
            }
            (State::Closed | State::Stopped, _) => unreachable!("checked before parsing"),
        }

        actions.push(Action::SendPacket(response));
        if self.state == State::Opened {
            let configuration = evaluation
                .configuration
                .expect("Configure-Ack has an accepted configuration");
            actions.push(Action::ThisLayerUp(configuration));
        }
        Ok(Transition {
            actions,
            ignored: None,
        })
    }

    fn receive_configure_ack(
        &mut self,
        packet: Packet<'_>,
        now_ms: u64,
    ) -> Result<Transition, MachineError> {
        if !packet.exactly_acknowledges(self.request_identifier, &self.local_options) {
            return Ok(invalid_response());
        }

        let mut actions = Vec::new();
        match self.state {
            State::RequestSent => {
                self.state = State::AckReceived;
                self.restart_remaining = self.settings.max_configure;
            }
            State::AckSent => {
                self.state = State::Opened;
                self.restart_remaining = self.settings.max_configure;
                self.restart_deadline_ms = None;
                actions.push(Action::ThisLayerUp(
                    self.peer_configuration.unwrap_or_default(),
                ));
            }
            State::AckReceived => {
                self.state = State::RequestSent;
                actions.push(Action::SendPacket(self.send_new_request(now_ms, false)?));
            }
            State::Opened => {
                actions.push(Action::ThisLayerDown);
                self.state = State::RequestSent;
                actions.push(Action::SendPacket(self.send_new_request(now_ms, false)?));
            }
            State::Closed | State::Stopped => unreachable!("checked before parsing"),
        }
        Ok(Transition {
            actions,
            ignored: None,
        })
    }

    fn receive_configure_nak(
        &mut self,
        packet: Packet<'_>,
        now_ms: u64,
    ) -> Result<Transition, MachineError> {
        if packet.identifier != self.request_identifier {
            return Ok(invalid_response());
        }
        let options = match collect_options(packet.data) {
            Ok(options) => options,
            Err(error) => {
                return Ok(Transition {
                    actions: Vec::new(),
                    ignored: Some(IgnoreReason::MalformedOptions(error)),
                });
            }
        };
        if has_duplicate_types(&options) {
            return Ok(invalid_response());
        }
        self.local_options = apply_nak(&self.local_options, &options);
        self.after_negative_response(now_ms)
    }

    fn receive_configure_reject(
        &mut self,
        packet: Packet<'_>,
        now_ms: u64,
    ) -> Result<Transition, MachineError> {
        if packet.identifier != self.request_identifier {
            return Ok(invalid_response());
        }
        let rejected = match collect_options(packet.data) {
            Ok(options) => options,
            Err(error) => {
                return Ok(Transition {
                    actions: Vec::new(),
                    ignored: Some(IgnoreReason::MalformedOptions(error)),
                });
            }
        };
        let Some(updated) = apply_reject(&self.local_options, &rejected) else {
            return Ok(invalid_response());
        };
        self.local_options = updated;
        self.after_negative_response(now_ms)
    }

    fn after_negative_response(&mut self, now_ms: u64) -> Result<Transition, MachineError> {
        let mut actions = Vec::new();
        let reset_counter = matches!(self.state, State::RequestSent | State::AckSent);
        match self.state {
            State::RequestSent | State::AckReceived => self.state = State::RequestSent,
            State::AckSent => self.state = State::AckSent,
            State::Opened => {
                actions.push(Action::ThisLayerDown);
                self.state = State::RequestSent;
            }
            State::Closed | State::Stopped => unreachable!("checked before parsing"),
        }
        actions.push(Action::SendPacket(
            self.send_new_request(now_ms, reset_counter)?,
        ));
        Ok(Transition {
            actions,
            ignored: None,
        })
    }

    fn receive_unknown_code(
        &mut self,
        input: &[u8],
        packet: Packet<'_>,
    ) -> Result<Transition, MachineError> {
        let peer_mru = usize::from(
            self.peer_configuration
                .unwrap_or_default()
                .transmit_mru
                .max(8),
        );
        let rejected_length = (super::HEADER_LENGTH + packet.data.len()).min(input.len());
        let maximum_data = peer_mru.saturating_sub(super::HEADER_LENGTH);
        let rejected = &input[..rejected_length.min(maximum_data)];
        let identifier = self.allocate_identifier();
        Ok(Transition {
            actions: vec![Action::SendPacket(encode_packet(
                Code::CodeReject as u8,
                identifier,
                rejected,
            )?)],
            ignored: None,
        })
    }

    fn send_new_request(
        &mut self,
        now_ms: u64,
        reset_counter: bool,
    ) -> Result<Vec<u8>, MachineError> {
        self.request_identifier = self.allocate_identifier();
        if reset_counter {
            self.restart_remaining = self.settings.max_configure.saturating_sub(1);
        } else {
            self.restart_remaining = self.restart_remaining.saturating_sub(1);
        }
        self.restart_deadline_ms = Some(now_ms.saturating_add(self.settings.restart_interval_ms));
        self.encode_request()
    }

    fn encode_request(&self) -> Result<Vec<u8>, MachineError> {
        encode_packet(
            Code::ConfigureRequest as u8,
            self.request_identifier,
            &self.local_options,
        )
    }

    fn allocate_identifier(&mut self) -> u8 {
        self.next_identifier = self.next_identifier.wrapping_add(1);
        self.next_identifier
    }
}

#[derive(Debug)]
struct PeerEvaluation {
    code: Code,
    data: Vec<u8>,
    configuration: Option<PeerConfiguration>,
}

#[derive(Debug)]
enum OptionDisposition {
    Ack,
    Nak(Vec<u8>),
    Reject,
}

fn evaluate_peer_request(
    packet: Packet<'_>,
    policy: SfcPolicy,
) -> Result<PeerEvaluation, OptionParseError> {
    let options = collect_options(packet.data)?;
    let duplicates = duplicate_type_map(&options);
    let mut configuration = PeerConfiguration::default();
    let mut dispositions = Vec::with_capacity(options.len());

    for option in &options {
        let disposition = if duplicates[usize::from(option.option_type)] {
            OptionDisposition::Reject
        } else {
            evaluate_option(option, policy, &mut configuration)
        };
        dispositions.push(disposition);
    }

    let has_reject = dispositions
        .iter()
        .any(|item| matches!(item, OptionDisposition::Reject));
    let has_nak = dispositions
        .iter()
        .any(|item| matches!(item, OptionDisposition::Nak(_)));

    if has_reject {
        let data = options
            .iter()
            .zip(dispositions.iter())
            .filter(|(_, disposition)| matches!(disposition, OptionDisposition::Reject))
            .flat_map(|(option, _)| option.encoded.iter().copied())
            .collect();
        return Ok(PeerEvaluation {
            code: Code::ConfigureReject,
            data,
            configuration: None,
        });
    }
    if has_nak {
        let data = dispositions
            .into_iter()
            .filter_map(|disposition| match disposition {
                OptionDisposition::Nak(replacement) => Some(replacement),
                _ => None,
            })
            .flatten()
            .collect();
        return Ok(PeerEvaluation {
            code: Code::ConfigureNak,
            data,
            configuration: None,
        });
    }

    Ok(PeerEvaluation {
        code: Code::ConfigureAck,
        data: packet.data.to_vec(),
        configuration: Some(configuration),
    })
}

fn evaluate_option(
    option: &ConfigurationOption<'_>,
    policy: SfcPolicy,
    configuration: &mut PeerConfiguration,
) -> OptionDisposition {
    match option.known_type() {
        Some(OptionType::MaximumReceiveUnit) if option.data.len() == 2 => {
            let value = u16::from_be_bytes([option.data[0], option.data[1]]);
            if value == 0 {
                OptionDisposition::Nak(vec![1, 4, 0x05, 0xdc])
            } else {
                configuration.transmit_mru = value;
                OptionDisposition::Ack
            }
        }
        Some(OptionType::MaximumReceiveUnit) => OptionDisposition::Nak(vec![1, 4, 0x05, 0xdc]),
        Some(OptionType::AsyncControlCharacterMap) if option.data.len() == 4 => {
            configuration.transmit_accm = u32::from_be_bytes([
                option.data[0],
                option.data[1],
                option.data[2],
                option.data[3],
            ]);
            OptionDisposition::Ack
        }
        Some(OptionType::AsyncControlCharacterMap) => {
            OptionDisposition::Nak(vec![2, 6, 0xff, 0xff, 0xff, 0xff])
        }
        Some(OptionType::AuthenticationProtocol)
            if policy.accept_pap && option.data == PAP_PROTOCOL.to_be_bytes() =>
        {
            configuration.authentication = Some(AuthenticationProtocol::Pap);
            OptionDisposition::Ack
        }
        Some(OptionType::AuthenticationProtocol) if policy.accept_pap => {
            OptionDisposition::Nak(vec![3, 4, 0xc0, 0x23])
        }
        Some(OptionType::MagicNumber) if option.data.len() == 4 => {
            let value = u32::from_be_bytes([
                option.data[0],
                option.data[1],
                option.data[2],
                option.data[3],
            ]);
            if value == 0 {
                OptionDisposition::Reject
            } else {
                configuration.magic_number = Some(value);
                OptionDisposition::Ack
            }
        }
        Some(
            OptionType::AuthenticationProtocol
            | OptionType::QualityProtocol
            | OptionType::MagicNumber
            | OptionType::ProtocolFieldCompression
            | OptionType::AddressControlFieldCompression,
        )
        | None => OptionDisposition::Reject,
    }
}

fn validate_options(data: &[u8]) -> Result<(), OptionParseError> {
    for option in configuration_options(data) {
        option?;
    }
    Ok(())
}

fn collect_options(data: &[u8]) -> Result<Vec<ConfigurationOption<'_>>, OptionParseError> {
    configuration_options(data).collect()
}

fn duplicate_type_map(options: &[ConfigurationOption<'_>]) -> [bool; 256] {
    let mut seen = [false; 256];
    let mut duplicate = [false; 256];
    for option in options {
        let index = usize::from(option.option_type);
        duplicate[index] |= seen[index];
        seen[index] = true;
    }
    duplicate
}

fn has_duplicate_types(options: &[ConfigurationOption<'_>]) -> bool {
    duplicate_type_map(options).into_iter().any(|value| value)
}

fn apply_nak(local: &[u8], suggestions: &[ConfigurationOption<'_>]) -> Vec<u8> {
    let mut output = Vec::with_capacity(local.len());
    for option in configuration_options(local).map(Result::unwrap) {
        if let Some(suggestion) = suggestions
            .iter()
            .find(|suggestion| suggestion.option_type == option.option_type)
        {
            output.extend_from_slice(suggestion.encoded);
        } else {
            output.extend_from_slice(option.encoded);
        }
    }
    output
}

fn apply_reject(local: &[u8], rejected: &[ConfigurationOption<'_>]) -> Option<Vec<u8>> {
    if rejected.is_empty() || has_duplicate_types(rejected) {
        return None;
    }
    let local_options = configuration_options(local)
        .collect::<Result<Vec<_>, _>>()
        .expect("local options were validated");
    if rejected.iter().any(|rejected_option| {
        !local_options
            .iter()
            .any(|local_option| local_option.encoded == rejected_option.encoded)
    }) {
        return None;
    }

    let mut output = Vec::with_capacity(local.len());
    for option in local_options {
        if !rejected
            .iter()
            .any(|rejected_option| rejected_option.encoded == option.encoded)
        {
            output.extend_from_slice(option.encoded);
        }
    }
    Some(output)
}

fn encode_packet(code: u8, identifier: u8, data: &[u8]) -> Result<Vec<u8>, MachineError> {
    let mut output = vec![0; super::HEADER_LENGTH + data.len()];
    encode_into(code, identifier, data, &mut output).map_err(MachineError::PacketTooLarge)?;
    Ok(output)
}

fn invalid_response() -> Transition {
    Transition {
        actions: Vec::new(),
        ignored: Some(IgnoreReason::InvalidConfigureResponse),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn packet(action: &Action) -> &[u8] {
        match action {
            Action::SendPacket(packet) => packet,
            _ => panic!("action is not a packet"),
        }
    }

    fn machine(local_options: &[u8]) -> Machine {
        Machine::new(local_options, Settings::default()).unwrap()
    }

    #[test]
    fn crossed_empty_requests_reach_opened() {
        let mut machine = machine(&[]);
        let opened = machine.open(100).unwrap();
        assert_eq!(packet(&opened.actions[0]), &[1, 1, 0, 4]);
        assert_eq!(machine.state(), State::RequestSent);

        let peer_request = machine
            .receive(&[1, 0x44, 0, 4], 200, SfcPolicy::default())
            .unwrap();
        assert_eq!(packet(&peer_request.actions[0]), &[2, 0x44, 0, 4]);
        assert_eq!(machine.state(), State::AckSent);

        let peer_ack = machine
            .receive(&[2, 1, 0, 4], 300, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::Opened);
        assert_eq!(
            peer_ack.actions,
            [Action::ThisLayerUp(PeerConfiguration::default())]
        );
        assert_eq!(machine.restart_deadline_ms(), None);
    }

    #[test]
    fn ack_received_then_peer_request_reaches_opened() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        machine
            .receive(&[2, 1, 0, 4], 10, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::AckReceived);

        let transition = machine
            .receive(&[1, 9, 0, 4], 20, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::Opened);
        assert_eq!(packet(&transition.actions[0]), &[2, 9, 0, 4]);
        assert!(matches!(
            transition.actions[1],
            Action::ThisLayerUp(PeerConfiguration { .. })
        ));
    }

    #[test]
    fn invalid_ack_is_silently_ignored() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(&[2, 2, 0, 4], 1, SfcPolicy::default())
            .unwrap();
        assert_eq!(
            transition.ignored,
            Some(IgnoreReason::InvalidConfigureResponse)
        );
        assert_eq!(machine.state(), State::RequestSent);
    }

    #[test]
    fn timeout_retransmits_same_identifier_then_finishes() {
        let mut machine = Machine::new(
            &[],
            Settings {
                restart_interval_ms: 100,
                max_configure: 2,
            },
        )
        .unwrap();
        machine.open(0).unwrap();
        assert!(machine.poll_timeout(99).unwrap().actions.is_empty());
        let retry = machine.poll_timeout(100).unwrap();
        assert_eq!(packet(&retry.actions[0]), &[1, 1, 0, 4]);
        assert_eq!(machine.request_identifier(), 1);

        let failed = machine.poll_timeout(200).unwrap();
        assert_eq!(failed.actions, [Action::ThisLayerFinished]);
        assert_eq!(machine.state(), State::Stopped);
    }

    #[test]
    fn conservative_policy_rejects_compression_before_nak_processing() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        let request = [
            1, 7, 0, 17, // header
            1, 4, 0x05, 0xdc, // MRU
            3, 5, 0xc2, 0x23, 5, // CHAP MD5, otherwise Nak PAP
            7, 2, // PFC, reject
            8, 2, // ACFC, reject
        ];
        let transition = machine.receive(&request, 1, SfcPolicy::default()).unwrap();
        assert_eq!(packet(&transition.actions[0]), &[4, 7, 0, 8, 7, 2, 8, 2]);
        assert_eq!(machine.state(), State::RequestSent);
    }

    #[test]
    fn policy_naks_chap_to_pap() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(&[1, 7, 0, 9, 3, 5, 0xc2, 0x23, 5], 1, SfcPolicy::default())
            .unwrap();
        assert_eq!(
            packet(&transition.actions[0]),
            &[3, 7, 0, 8, 3, 4, 0xc0, 0x23]
        );
    }

    #[test]
    fn accepted_peer_options_are_published_on_link_up() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        let request = [
            1, 7, 0, 24, // header
            1, 4, 0x02, 0x40, // MRU 576
            2, 6, 0, 0, 0, 0, // ACCM
            3, 4, 0xc0, 0x23, // PAP
            5, 6, 0x12, 0x34, 0x56, 0x78, // Magic
        ];
        let ack = machine.receive(&request, 1, SfcPolicy::default()).unwrap();
        let mut expected = request;
        expected[0] = 2;
        assert_eq!(packet(&ack.actions[0]), expected);
        let opened = machine
            .receive(&[2, 1, 0, 4], 2, SfcPolicy::default())
            .unwrap();
        assert_eq!(
            opened.actions,
            [Action::ThisLayerUp(PeerConfiguration {
                transmit_mru: 576,
                transmit_accm: 0,
                authentication: Some(AuthenticationProtocol::Pap),
                magic_number: Some(0x1234_5678),
            })]
        );
    }

    #[test]
    fn malformed_peer_option_is_silently_ignored() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(&[1, 2, 0, 7, 1, 4, 0], 1, SfcPolicy::default())
            .unwrap();
        assert!(transition.actions.is_empty());
        assert!(matches!(
            transition.ignored,
            Some(IgnoreReason::MalformedOptions(_))
        ));
    }

    #[test]
    fn nak_replaces_requested_option_and_changes_identifier() {
        let mut machine = machine(&[2, 6, 0xff, 0xff, 0xff, 0xff]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(&[3, 1, 0, 10, 2, 6, 0, 0, 0, 0], 1, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.local_options(), &[2, 6, 0, 0, 0, 0]);
        assert_eq!(
            packet(&transition.actions[0]),
            &[1, 2, 0, 10, 2, 6, 0, 0, 0, 0]
        );
    }

    #[test]
    fn reject_removes_exact_requested_option() {
        let mut machine = machine(&[2, 6, 0xff, 0xff, 0xff, 0xff]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(
                &[4, 1, 0, 10, 2, 6, 0xff, 0xff, 0xff, 0xff],
                1,
                SfcPolicy::default(),
            )
            .unwrap();
        assert!(machine.local_options().is_empty());
        assert_eq!(packet(&transition.actions[0]), &[1, 2, 0, 4]);
    }

    #[test]
    fn invalid_reject_does_not_change_request() {
        let mut machine = machine(&[2, 6, 0xff, 0xff, 0xff, 0xff]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(&[4, 1, 0, 10, 2, 6, 0, 0, 0, 0], 1, SfcPolicy::default())
            .unwrap();
        assert_eq!(
            transition.ignored,
            Some(IgnoreReason::InvalidConfigureResponse)
        );
        assert_eq!(machine.request_identifier(), 1);
    }

    #[test]
    fn opened_peer_request_restarts_both_directions() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        machine
            .receive(&[1, 9, 0, 4], 1, SfcPolicy::default())
            .unwrap();
        machine
            .receive(&[2, 1, 0, 4], 2, SfcPolicy::default())
            .unwrap();

        let transition = machine
            .receive(&[1, 10, 0, 4], 3, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::AckSent);
        assert_eq!(transition.actions[0], Action::ThisLayerDown);
        assert_eq!(packet(&transition.actions[1]), &[1, 2, 0, 4]);
        assert_eq!(packet(&transition.actions[2]), &[2, 10, 0, 4]);
    }

    #[test]
    fn protocol_reject_contains_protocol_and_truncates_to_peer_mru() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        machine
            .receive(&[1, 9, 0, 8, 1, 4, 0, 8], 1, SfcPolicy::default())
            .unwrap();
        machine
            .receive(&[2, 1, 0, 4], 2, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::Opened);

        let transition = machine
            .reject_protocol(0x8057, &[0xaa, 0xbb, 0xcc, 0xdd])
            .unwrap();
        assert_eq!(
            packet(&transition.actions[0]),
            &[8, 2, 0, 8, 0x80, 0x57, 0xaa, 0xbb]
        );
    }

    #[test]
    fn protocol_reject_is_phase_gated_by_lcp_opened() {
        let mut machine = machine(&[]);
        let transition = machine.reject_protocol(0x8057, &[1, 2]).unwrap();
        assert!(transition.actions.is_empty());
        assert_eq!(transition.ignored, Some(IgnoreReason::NotConfiguring));
    }

    #[test]
    fn unknown_code_is_rejected_with_the_length_delimited_packet() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();

        let transition = machine
            .receive(
                &[0x7f, 0x42, 0, 6, 0xaa, 0xbb, 0xcc],
                1,
                SfcPolicy::default(),
            )
            .unwrap();
        assert_eq!(
            packet(&transition.actions[0]),
            &[7, 2, 0, 10, 0x7f, 0x42, 0, 6, 0xaa, 0xbb]
        );
    }

    #[test]
    fn peer_terminate_request_is_acknowledged_before_layer_down() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        machine
            .receive(&[1, 9, 0, 4], 1, SfcPolicy::default())
            .unwrap();
        machine
            .receive(&[2, 1, 0, 4], 2, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::Opened);

        let transition = machine
            .receive(
                &[
                    5, 0x42, 0, 16, b'U', b's', b'e', b'r', b' ', b'r', b'e', b'q', b'u', b'e',
                    b's', b't',
                ],
                3,
                SfcPolicy::default(),
            )
            .unwrap();

        assert_eq!(machine.state(), State::Stopped);
        assert_eq!(machine.restart_deadline_ms(), None);
        assert_eq!(packet(&transition.actions[0]), &[6, 0x42, 0, 4]);
        assert_eq!(transition.actions[1], Action::ThisLayerDown);
    }

    #[test]
    fn terminate_ack_is_ignored_without_a_local_close() {
        let mut machine = machine(&[]);
        machine.open(0).unwrap();
        let transition = machine
            .receive(&[6, 0x31, 0, 4], 1, SfcPolicy::default())
            .unwrap();
        assert_eq!(machine.state(), State::RequestSent);
        assert_eq!(transition, Transition::default());
    }
}
