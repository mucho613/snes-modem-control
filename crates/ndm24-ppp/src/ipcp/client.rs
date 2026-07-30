//! RFC 1332 Configure negotiation used by the SFC IPCP client.

use super::{
    Code, ConfigurationOption, Ipv4Address, OptionParseError, OptionType, Packet,
    UNSPECIFIED_ADDRESS, configuration_options, encode_into, encode_ip_address_option,
    encode_primary_dns_address_option, encode_secondary_dns_address_option,
};

pub const DEFAULT_RESTART_INTERVAL_MS: u64 = 3_000;
pub const DEFAULT_MAX_CONFIGURE: u8 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum State {
    Closed = 0,
    Stopped = 3,
    RequestSent = 6,
    AckReceived = 7,
    AckSent = 8,
    Opened = 9,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct AddressConfiguration {
    pub local: Ipv4Address,
    pub peer: Ipv4Address,
    pub primary_dns: Ipv4Address,
    pub secondary_dns: Ipv4Address,
}

impl AddressConfiguration {
    pub fn is_usable(self) -> bool {
        self.local != UNSPECIFIED_ADDRESS && self.peer != UNSPECIFIED_ADDRESS
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    SendPacket(Vec<u8>),
    ThisLayerUp(AddressConfiguration),
    ThisLayerDown,
    ThisLayerFinished,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IgnoreReason {
    NotConfiguring,
    MalformedPacket(super::ParseError),
    MalformedOptions(OptionParseError),
    InvalidConfigureResponse,
    UnsupportedCode(u8),
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
    pub requested_local_address: Ipv4Address,
    pub preferred_peer_address: Ipv4Address,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            restart_interval_ms: DEFAULT_RESTART_INTERVAL_MS,
            max_configure: DEFAULT_MAX_CONFIGURE,
            requested_local_address: UNSPECIFIED_ADDRESS,
            preferred_peer_address: UNSPECIFIED_ADDRESS,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MachineError {
    PacketTooLarge(super::EncodeError),
}

#[derive(Debug)]
pub struct Client {
    state: State,
    settings: Settings,
    local_address: Ipv4Address,
    peer_address: Ipv4Address,
    primary_dns_address: Ipv4Address,
    secondary_dns_address: Ipv4Address,
    request_address_option: bool,
    request_primary_dns_option: bool,
    request_secondary_dns_option: bool,
    request_identifier: u8,
    next_identifier: u8,
    restart_remaining: u8,
    restart_deadline_ms: Option<u64>,
}

impl Client {
    pub fn new(settings: Settings) -> Self {
        Self {
            state: State::Closed,
            local_address: settings.requested_local_address,
            peer_address: settings.preferred_peer_address,
            primary_dns_address: UNSPECIFIED_ADDRESS,
            secondary_dns_address: UNSPECIFIED_ADDRESS,
            settings,
            request_address_option: true,
            request_primary_dns_option: true,
            request_secondary_dns_option: true,
            request_identifier: 0,
            next_identifier: 0,
            restart_remaining: 0,
            restart_deadline_ms: None,
        }
    }

    pub fn state(&self) -> State {
        self.state
    }

    pub fn addresses(&self) -> AddressConfiguration {
        AddressConfiguration {
            local: self.local_address,
            peer: self.peer_address,
            primary_dns: self.primary_dns_address,
            secondary_dns: self.secondary_dns_address,
        }
    }

    pub fn request_identifier(&self) -> u8 {
        self.request_identifier
    }

    pub fn restart_remaining(&self) -> u8 {
        self.restart_remaining
    }

    pub fn restart_deadline_ms(&self) -> Option<u64> {
        self.restart_deadline_ms
    }

    pub fn open(&mut self, now_ms: u64) -> Result<Transition, MachineError> {
        if self.state == State::Opened {
            return Ok(Transition::default());
        }
        self.state = State::RequestSent;
        self.local_address = self.settings.requested_local_address;
        self.peer_address = self.settings.preferred_peer_address;
        self.primary_dns_address = UNSPECIFIED_ADDRESS;
        self.secondary_dns_address = UNSPECIFIED_ADDRESS;
        self.request_address_option = true;
        self.request_primary_dns_option = true;
        self.request_secondary_dns_option = true;
        let packet = self.send_new_request(now_ms, true)?;
        Ok(Transition {
            actions: vec![Action::SendPacket(packet)],
            ignored: None,
        })
    }

    pub fn lower_down(&mut self) -> Transition {
        let was_open = self.state == State::Opened;
        self.state = State::Closed;
        self.local_address = self.settings.requested_local_address;
        self.peer_address = self.settings.preferred_peer_address;
        self.primary_dns_address = UNSPECIFIED_ADDRESS;
        self.secondary_dns_address = UNSPECIFIED_ADDRESS;
        self.request_address_option = true;
        self.request_primary_dns_option = true;
        self.request_secondary_dns_option = true;
        self.restart_deadline_ms = None;
        self.restart_remaining = 0;
        Transition {
            actions: if was_open {
                vec![Action::ThisLayerDown]
            } else {
                Vec::new()
            },
            ignored: None,
        }
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

    pub fn receive(&mut self, input: &[u8], now_ms: u64) -> Result<Transition, MachineError> {
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
            Some(Code::ConfigureRequest) => self.receive_configure_request(packet, now_ms),
            Some(Code::ConfigureAck) => self.receive_configure_ack(packet, now_ms),
            Some(Code::ConfigureNak) => self.receive_configure_nak(packet, now_ms),
            Some(Code::ConfigureReject) => self.receive_configure_reject(packet, now_ms),
            Some(code) => Ok(Transition {
                actions: Vec::new(),
                ignored: Some(IgnoreReason::UnsupportedCode(code as u8)),
            }),
            None => Ok(Transition {
                actions: Vec::new(),
                ignored: Some(IgnoreReason::UnsupportedCode(packet.code)),
            }),
        }
    }

    fn receive_configure_request(
        &mut self,
        packet: Packet<'_>,
        now_ms: u64,
    ) -> Result<Transition, MachineError> {
        let evaluation = match evaluate_peer_request(packet, self.settings.preferred_peer_address) {
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
        if let Some(address) = evaluation.peer_address {
            self.peer_address = address;
        }
        let mut actions = Vec::new();

        match (self.state, acceptable) {
            (State::RequestSent, true) | (State::AckSent, true) => self.state = State::AckSent,
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
            actions.push(Action::ThisLayerUp(self.addresses()));
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
        let local_options = self.local_options();
        if !packet.exactly_acknowledges(self.request_identifier, &local_options) {
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
                actions.push(Action::ThisLayerUp(self.addresses()));
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
        let mut accepted = false;
        for option in options {
            match option.known_type() {
                Some(OptionType::IpAddress) if self.request_address_option => {
                    let Some(address) = option
                        .ip_address()
                        .filter(|address| *address != UNSPECIFIED_ADDRESS)
                    else {
                        return Ok(invalid_response());
                    };
                    self.local_address = address;
                    accepted = true;
                }
                Some(OptionType::PrimaryDnsServerAddress) if self.request_primary_dns_option => {
                    let Some(address) = option
                        .primary_dns_address()
                        .filter(|address| *address != UNSPECIFIED_ADDRESS)
                    else {
                        return Ok(invalid_response());
                    };
                    self.primary_dns_address = address;
                    accepted = true;
                }
                Some(OptionType::SecondaryDnsServerAddress)
                    if self.request_secondary_dns_option =>
                {
                    let Some(address) = option
                        .secondary_dns_address()
                        .filter(|address| *address != UNSPECIFIED_ADDRESS)
                    else {
                        return Ok(invalid_response());
                    };
                    self.secondary_dns_address = address;
                    accepted = true;
                }
                _ => return Ok(invalid_response()),
            }
        }
        if !accepted {
            return Ok(invalid_response());
        }
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
        let options = match collect_options(packet.data) {
            Ok(options) => options,
            Err(error) => {
                return Ok(Transition {
                    actions: Vec::new(),
                    ignored: Some(IgnoreReason::MalformedOptions(error)),
                });
            }
        };
        if options.is_empty() || has_duplicate_types(&options) {
            return Ok(invalid_response());
        }
        for option in options {
            match option.known_type() {
                Some(OptionType::IpAddress)
                    if self.request_address_option
                        && option.encoded == encode_ip_address_option(self.local_address) =>
                {
                    self.request_address_option = false;
                }
                Some(OptionType::PrimaryDnsServerAddress)
                    if self.request_primary_dns_option
                        && option.encoded
                            == encode_primary_dns_address_option(self.primary_dns_address) =>
                {
                    self.request_primary_dns_option = false;
                    self.primary_dns_address = UNSPECIFIED_ADDRESS;
                }
                Some(OptionType::SecondaryDnsServerAddress)
                    if self.request_secondary_dns_option
                        && option.encoded
                            == encode_secondary_dns_address_option(self.secondary_dns_address) =>
                {
                    self.request_secondary_dns_option = false;
                    self.secondary_dns_address = UNSPECIFIED_ADDRESS;
                }
                _ => return Ok(invalid_response()),
            }
        }
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

    fn send_new_request(
        &mut self,
        now_ms: u64,
        reset_counter: bool,
    ) -> Result<Vec<u8>, MachineError> {
        self.request_identifier = self.allocate_identifier();
        self.restart_remaining = if reset_counter {
            self.settings.max_configure.saturating_sub(1)
        } else {
            self.restart_remaining.saturating_sub(1)
        };
        self.restart_deadline_ms = Some(now_ms.saturating_add(self.settings.restart_interval_ms));
        self.encode_request()
    }

    fn encode_request(&self) -> Result<Vec<u8>, MachineError> {
        encode_packet(
            Code::ConfigureRequest as u8,
            self.request_identifier,
            &self.local_options(),
        )
    }

    fn local_options(&self) -> Vec<u8> {
        let mut options = Vec::with_capacity(3 * super::IP_ADDRESS_OPTION_LENGTH);
        if self.request_address_option {
            options.extend_from_slice(&encode_ip_address_option(self.local_address));
        }
        if self.request_primary_dns_option {
            options.extend_from_slice(&encode_primary_dns_address_option(self.primary_dns_address));
        }
        if self.request_secondary_dns_option {
            options.extend_from_slice(&encode_secondary_dns_address_option(
                self.secondary_dns_address,
            ));
        }
        options
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
    peer_address: Option<Ipv4Address>,
}

#[derive(Debug)]
enum OptionDisposition {
    Ack,
    Nak(Vec<u8>),
    Reject,
}

fn evaluate_peer_request(
    packet: Packet<'_>,
    preferred_peer_address: Ipv4Address,
) -> Result<PeerEvaluation, OptionParseError> {
    let options = collect_options(packet.data)?;
    let duplicates = duplicate_type_map(&options);
    let mut peer_address = None;
    let mut dispositions = Vec::with_capacity(options.len());

    for option in &options {
        let disposition = if duplicates[usize::from(option.option_type)] {
            OptionDisposition::Reject
        } else {
            match option.known_type() {
                Some(OptionType::IpAddress) if option.data.len() == 4 => {
                    let address = option.ip_address().expect("length checked");
                    if address == UNSPECIFIED_ADDRESS
                        && preferred_peer_address != UNSPECIFIED_ADDRESS
                    {
                        OptionDisposition::Nak(
                            encode_ip_address_option(preferred_peer_address).to_vec(),
                        )
                    } else if address == UNSPECIFIED_ADDRESS {
                        OptionDisposition::Reject
                    } else {
                        peer_address = Some(address);
                        OptionDisposition::Ack
                    }
                }
                Some(OptionType::IpAddress) => {
                    if preferred_peer_address == UNSPECIFIED_ADDRESS {
                        OptionDisposition::Reject
                    } else {
                        OptionDisposition::Nak(
                            encode_ip_address_option(preferred_peer_address).to_vec(),
                        )
                    }
                }
                Some(
                    OptionType::IpAddresses
                    | OptionType::IpCompressionProtocol
                    | OptionType::PrimaryDnsServerAddress
                    | OptionType::SecondaryDnsServerAddress,
                )
                | None => OptionDisposition::Reject,
            }
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
        return Ok(PeerEvaluation {
            code: Code::ConfigureReject,
            data: options
                .iter()
                .zip(&dispositions)
                .filter(|(_, disposition)| matches!(disposition, OptionDisposition::Reject))
                .flat_map(|(option, _)| option.encoded.iter().copied())
                .collect(),
            peer_address: None,
        });
    }
    if has_nak {
        return Ok(PeerEvaluation {
            code: Code::ConfigureNak,
            data: dispositions
                .into_iter()
                .filter_map(|disposition| match disposition {
                    OptionDisposition::Nak(data) => Some(data),
                    _ => None,
                })
                .flatten()
                .collect(),
            peer_address: None,
        });
    }
    Ok(PeerEvaluation {
        code: Code::ConfigureAck,
        data: packet.data.to_vec(),
        peer_address,
    })
}

fn collect_options(data: &[u8]) -> Result<Vec<ConfigurationOption<'_>>, OptionParseError> {
    configuration_options(data).collect()
}

fn duplicate_type_map(options: &[ConfigurationOption<'_>]) -> [bool; 256] {
    let mut seen = [false; 256];
    let mut duplicates = [false; 256];
    for option in options {
        let index = usize::from(option.option_type);
        duplicates[index] |= seen[index];
        seen[index] = true;
    }
    duplicates
}

fn has_duplicate_types(options: &[ConfigurationOption<'_>]) -> bool {
    duplicate_type_map(options).into_iter().any(|value| value)
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

    const SETTINGS: Settings = Settings {
        restart_interval_ms: 3_000,
        max_configure: 10,
        requested_local_address: [0, 0, 0, 0],
        preferred_peer_address: [10, 24, 0, 1],
    };

    fn packet(action: &Action) -> &[u8] {
        match action {
            Action::SendPacket(packet) => packet,
            _ => panic!("action is not a packet"),
        }
    }

    #[test]
    fn pppd_transcript_negotiates_both_addresses() {
        let mut client = Client::new(SETTINGS);
        let opened = client.open(0).unwrap();
        assert_eq!(
            packet(&opened.actions[0]),
            [
                1, 1, 0, 22, 3, 6, 0, 0, 0, 0, 129, 6, 0, 0, 0, 0, 131, 6, 0, 0, 0, 0
            ]
        );

        let peer_request = [1, 11, 0, 10, 3, 6, 10, 24, 0, 1];
        let peer = client.receive(&peer_request, 20).unwrap();
        assert_eq!(client.state(), State::AckSent);
        assert_eq!(packet(&peer.actions[0]), [2, 11, 0, 10, 3, 6, 10, 24, 0, 1]);

        let local_nak = [
            3, 1, 0, 22, 3, 6, 10, 24, 0, 2, 129, 6, 1, 1, 1, 1, 131, 6, 1, 0, 0, 1,
        ];
        let nak = client.receive(&local_nak, 30).unwrap();
        assert_eq!(client.state(), State::AckSent);
        assert_eq!(
            packet(&nak.actions[0]),
            [
                1, 2, 0, 22, 3, 6, 10, 24, 0, 2, 129, 6, 1, 1, 1, 1, 131, 6, 1, 0, 0, 1,
            ]
        );

        let local_ack = [
            2, 2, 0, 22, 3, 6, 10, 24, 0, 2, 129, 6, 1, 1, 1, 1, 131, 6, 1, 0, 0, 1,
        ];
        let ack = client.receive(&local_ack, 40).unwrap();
        assert_eq!(client.state(), State::Opened);
        assert_eq!(
            ack.actions,
            [Action::ThisLayerUp(AddressConfiguration {
                local: [10, 24, 0, 2],
                peer: [10, 24, 0, 1],
                primary_dns: [1, 1, 1, 1],
                secondary_dns: [1, 0, 0, 1],
            })]
        );
        assert!(client.addresses().is_usable());
        assert_eq!(client.restart_deadline_ms(), None);
    }

    #[test]
    fn zero_peer_address_is_naked_to_the_fixture_address() {
        let mut client = Client::new(SETTINGS);
        client.open(0).unwrap();
        let response = client.receive(&[1, 8, 0, 10, 3, 6, 0, 0, 0, 0], 1).unwrap();
        assert_eq!(
            packet(&response.actions[0]),
            [3, 8, 0, 10, 3, 6, 10, 24, 0, 1]
        );
        assert_eq!(client.state(), State::RequestSent);
    }

    #[test]
    fn compression_unknown_and_duplicate_options_are_rejected() {
        for request in [
            vec![1, 4, 0, 8, 2, 4, 0, 0],
            vec![1, 4, 0, 7, 99, 3, 7],
            vec![1, 4, 0, 16, 3, 6, 10, 24, 0, 1, 3, 6, 10, 24, 0, 1],
        ] {
            let mut client = Client::new(SETTINGS);
            client.open(0).unwrap();
            let response = client.receive(&request, 1).unwrap();
            assert_eq!(packet(&response.actions[0])[0], Code::ConfigureReject as u8);
        }
    }

    #[test]
    fn ack_must_match_identifier_and_options_exactly() {
        let mut client = Client::new(SETTINGS);
        client.open(0).unwrap();
        for response in [
            vec![
                2, 2, 0, 22, 3, 6, 0, 0, 0, 0, 129, 6, 0, 0, 0, 0, 131, 6, 0, 0, 0, 0,
            ],
            vec![
                2, 1, 0, 22, 3, 6, 10, 24, 0, 2, 129, 6, 0, 0, 0, 0, 131, 6, 0, 0, 0, 0,
            ],
        ] {
            assert_eq!(
                client.receive(&response, 1).unwrap().ignored,
                Some(IgnoreReason::InvalidConfigureResponse)
            );
            assert_eq!(client.state(), State::RequestSent);
        }
    }

    #[test]
    fn timeout_reuses_identifier_then_stops() {
        let settings = Settings {
            max_configure: 2,
            ..SETTINGS
        };
        let mut client = Client::new(settings);
        client.open(0).unwrap();
        assert_eq!(client.request_identifier(), 1);
        assert_eq!(client.restart_remaining(), 1);

        let retry = client.poll_timeout(3_000).unwrap();
        assert_eq!(packet(&retry.actions[0])[1], 1);
        assert_eq!(client.restart_remaining(), 0);
        assert_eq!(client.state(), State::RequestSent);

        let stopped = client.poll_timeout(6_000).unwrap();
        assert_eq!(client.state(), State::Stopped);
        assert_eq!(stopped.actions, [Action::ThisLayerFinished]);
    }

    #[test]
    fn lower_down_clears_negotiated_addresses() {
        let mut client = Client::new(SETTINGS);
        client.local_address = [10, 24, 0, 2];
        client.peer_address = [10, 24, 0, 1];
        client.state = State::Opened;
        let transition = client.lower_down();
        assert_eq!(transition.actions, [Action::ThisLayerDown]);
        assert_eq!(client.state(), State::Closed);
        assert_eq!(
            client.addresses(),
            AddressConfiguration {
                local: [0, 0, 0, 0],
                peer: [10, 24, 0, 1],
                primary_dns: [0, 0, 0, 0],
                secondary_dns: [0, 0, 0, 0],
            }
        );
    }

    #[test]
    fn dns_options_can_be_rejected_independently() {
        let mut client = Client::new(SETTINGS);
        client.open(0).unwrap();
        let reject_primary = [4, 1, 0, 10, 129, 6, 0, 0, 0, 0];
        let next = client.receive(&reject_primary, 1).unwrap();
        assert_eq!(
            packet(&next.actions[0]),
            [1, 2, 0, 16, 3, 6, 0, 0, 0, 0, 131, 6, 0, 0, 0, 0]
        );

        let reject_secondary = [4, 2, 0, 10, 131, 6, 0, 0, 0, 0];
        let final_request = client.receive(&reject_secondary, 2).unwrap();
        assert_eq!(
            packet(&final_request.actions[0]),
            [1, 3, 0, 10, 3, 6, 0, 0, 0, 0]
        );
    }

    #[test]
    fn zero_dns_nak_is_invalid_but_zero_ack_can_converge() {
        let mut client = Client::new(SETTINGS);
        client.open(0).unwrap();
        let zero_nak = [3, 1, 0, 10, 129, 6, 0, 0, 0, 0];
        assert_eq!(
            client.receive(&zero_nak, 1).unwrap().ignored,
            Some(IgnoreReason::InvalidConfigureResponse)
        );

        let peer_request = [1, 11, 0, 10, 3, 6, 10, 24, 0, 1];
        client.receive(&peer_request, 2).unwrap();
        let address_nak = [3, 1, 0, 10, 3, 6, 10, 24, 0, 2];
        client.receive(&address_nak, 3).unwrap();
        let zero_ack = [
            2, 2, 0, 22, 3, 6, 10, 24, 0, 2, 129, 6, 0, 0, 0, 0, 131, 6, 0, 0, 0, 0,
        ];
        let ack = client.receive(&zero_ack, 4).unwrap();
        assert_eq!(
            ack.actions,
            [Action::ThisLayerUp(AddressConfiguration {
                local: [10, 24, 0, 2],
                peer: [10, 24, 0, 1],
                primary_dns: [0, 0, 0, 0],
                secondary_dns: [0, 0, 0, 0],
            })]
        );
    }
}
