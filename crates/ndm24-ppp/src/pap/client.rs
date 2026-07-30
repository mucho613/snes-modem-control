//! PAP client state machine for a peer authenticating itself to the server.

use super::{Code, DataParseError, EncodeError, Packet, ParseError, encode_authenticate_request};

pub const DEFAULT_MAX_AUTHENTICATE: u8 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Inactive,
    RequestPending,
    WaitingForReply,
    Opened,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    Rejected,
    RetryLimitExceeded,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IgnoreReason {
    Inactive,
    Packet(ParseError),
    UnsupportedCode { actual: u8 },
    IdentifierMismatch { expected: u8, actual: u8 },
    Data(DataParseError),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReceiveOutcome {
    Authenticated,
    Rejected,
    Ignored(IgnoreReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Client {
    state: State,
    next_identifier: u8,
    current_identifier: u8,
    attempts_remaining: u8,
    max_authenticate: u8,
    failure: Option<Failure>,
}

impl Default for Client {
    fn default() -> Self {
        Self::new(DEFAULT_MAX_AUTHENTICATE)
    }
}

impl Client {
    pub fn new(max_authenticate: u8) -> Self {
        assert!(max_authenticate > 0, "Max-Authenticate must be nonzero");
        Self {
            state: State::Inactive,
            next_identifier: 1,
            current_identifier: 0,
            attempts_remaining: 0,
            max_authenticate,
            failure: None,
        }
    }

    pub fn state(&self) -> State {
        self.state
    }

    pub fn current_identifier(&self) -> Option<u8> {
        (self.state == State::WaitingForReply).then_some(self.current_identifier)
    }

    pub fn attempts_remaining(&self) -> u8 {
        self.attempts_remaining
    }

    pub fn failure(&self) -> Option<Failure> {
        self.failure
    }

    /// Starts the authentication phase after LCP reaches Opened.
    ///
    /// When the peer did not negotiate PAP, no PAP exchange is needed and
    /// the authentication phase is immediately considered open.
    pub fn lower_up(&mut self, pap_required: bool) {
        self.attempts_remaining = self.max_authenticate;
        self.failure = None;
        self.state = if pap_required {
            State::RequestPending
        } else {
            State::Opened
        };
    }

    pub fn lower_down(&mut self) {
        self.state = State::Inactive;
        self.current_identifier = 0;
        self.attempts_remaining = 0;
        self.failure = None;
    }

    /// Builds the pending request without consuming its Identifier or retry
    /// budget. The caller must invoke [`Self::request_sent`] only after the
    /// shared PPP transmitter accepts the packet.
    pub fn build_pending_request(
        &self,
        peer_id: &[u8],
        password: &[u8],
        output: &mut [u8],
    ) -> Result<Option<usize>, EncodeError> {
        if self.state != State::RequestPending {
            return Ok(None);
        }
        encode_authenticate_request(self.next_identifier, peer_id, password, output).map(Some)
    }

    /// Commits a request accepted by the shared PPP transmitter.
    pub fn request_sent(&mut self) -> bool {
        if self.state != State::RequestPending {
            return false;
        }

        self.current_identifier = self.next_identifier;
        self.next_identifier = self.next_identifier.wrapping_add(1);
        self.attempts_remaining -= 1;
        self.state = State::WaitingForReply;
        true
    }

    /// Handles expiry of the Authenticate-Request restart timer.
    pub fn timeout(&mut self) -> bool {
        if self.state != State::WaitingForReply {
            return false;
        }

        if self.attempts_remaining == 0 {
            self.state = State::Failed;
            self.failure = Some(Failure::RetryLimitExceeded);
        } else {
            self.state = State::RequestPending;
        }
        true
    }

    pub fn receive(&mut self, input: &[u8]) -> ReceiveOutcome {
        if self.state != State::WaitingForReply {
            return ReceiveOutcome::Ignored(IgnoreReason::Inactive);
        }

        let packet = match Packet::parse(input) {
            Ok(packet) => packet,
            Err(error) => return ReceiveOutcome::Ignored(IgnoreReason::Packet(error)),
        };
        let code = match packet.known_code() {
            Some(code @ (Code::AuthenticateAck | Code::AuthenticateNak)) => code,
            _ => {
                return ReceiveOutcome::Ignored(IgnoreReason::UnsupportedCode {
                    actual: packet.code,
                });
            }
        };
        if packet.identifier != self.current_identifier {
            return ReceiveOutcome::Ignored(IgnoreReason::IdentifierMismatch {
                expected: self.current_identifier,
                actual: packet.identifier,
            });
        }
        if let Err(error) = packet.reply_message() {
            return ReceiveOutcome::Ignored(IgnoreReason::Data(error));
        }

        match code {
            Code::AuthenticateAck => {
                self.state = State::Opened;
                ReceiveOutcome::Authenticated
            }
            Code::AuthenticateNak => {
                self.state = State::Failed;
                self.failure = Some(Failure::Rejected);
                ReceiveOutcome::Rejected
            }
            Code::AuthenticateRequest => unreachable!(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PEER_ID: &[u8] = b"ndm24";
    const PASSWORD: &[u8] = b"ndm24-test";

    fn accept_pending(client: &mut Client) -> Vec<u8> {
        let mut request = [0; 64];
        let length = client
            .build_pending_request(PEER_ID, PASSWORD, &mut request)
            .unwrap()
            .unwrap();
        assert!(client.request_sent());
        request[..length].to_vec()
    }

    #[test]
    fn pap_requirement_starts_request_while_no_requirement_opens_immediately() {
        let mut client = Client::default();
        client.lower_up(true);
        assert_eq!(client.state(), State::RequestPending);
        assert_eq!(client.attempts_remaining(), DEFAULT_MAX_AUTHENTICATE);

        client.lower_down();
        client.lower_up(false);
        assert_eq!(client.state(), State::Opened);
    }

    #[test]
    fn transmitter_backpressure_does_not_consume_identifier_or_budget() {
        let mut client = Client::new(3);
        client.lower_up(true);

        let mut first = [0; 64];
        let first_length = client
            .build_pending_request(PEER_ID, PASSWORD, &mut first)
            .unwrap()
            .unwrap();
        let mut retried = [0; 64];
        let retried_length = client
            .build_pending_request(PEER_ID, PASSWORD, &mut retried)
            .unwrap()
            .unwrap();

        assert_eq!(&first[..first_length], &retried[..retried_length]);
        assert_eq!(first[1], 1);
        assert_eq!(client.state(), State::RequestPending);
        assert_eq!(client.attempts_remaining(), 3);
        assert_eq!(client.current_identifier(), None);
    }

    #[test]
    fn matching_ack_opens_and_wrong_identifier_is_ignored() {
        let mut client = Client::new(3);
        client.lower_up(true);
        let request = accept_pending(&mut client);
        assert_eq!(request[1], 1);
        assert_eq!(client.current_identifier(), Some(1));
        assert_eq!(client.attempts_remaining(), 2);

        assert_eq!(
            client.receive(&[2, 2, 0, 5, 0]),
            ReceiveOutcome::Ignored(IgnoreReason::IdentifierMismatch {
                expected: 1,
                actual: 2,
            })
        );
        assert_eq!(client.state(), State::WaitingForReply);
        assert_eq!(
            client.receive(&[2, 1, 0, 7, 2, b'O', b'K']),
            ReceiveOutcome::Authenticated
        );
        assert_eq!(client.state(), State::Opened);
    }

    #[test]
    fn matching_nak_fails_without_exposing_the_message() {
        let mut client = Client::new(3);
        client.lower_up(true);
        accept_pending(&mut client);

        assert_eq!(
            client.receive(&[3, 1, 0, 11, 6, b'D', b'e', b'n', b'i', b'e', b'd']),
            ReceiveOutcome::Rejected
        );
        assert_eq!(client.state(), State::Failed);
        assert_eq!(client.failure(), Some(Failure::Rejected));
    }

    #[test]
    fn timeout_reissues_with_a_new_identifier_then_exhausts_limit() {
        let mut client = Client::new(2);
        client.lower_up(true);

        let first = accept_pending(&mut client);
        assert_eq!(first[1], 1);
        assert_eq!(client.attempts_remaining(), 1);
        assert!(client.timeout());
        assert_eq!(client.state(), State::RequestPending);

        let second = accept_pending(&mut client);
        assert_eq!(second[1], 2);
        assert_eq!(client.attempts_remaining(), 0);
        assert!(client.timeout());
        assert_eq!(client.state(), State::Failed);
        assert_eq!(client.failure(), Some(Failure::RetryLimitExceeded));
    }

    #[test]
    fn malformed_or_unexpected_replies_are_ignored_without_state_change() {
        let mut client = Client::new(3);
        client.lower_up(true);
        accept_pending(&mut client);

        for malformed in [
            &[2, 1, 0][..],
            &[4, 1, 0, 4],
            &[2, 1, 0, 4],
            &[2, 1, 0, 6, 2, b'x'],
            &[2, 1, 0, 7, 1, b'x', 0],
        ] {
            assert!(matches!(
                client.receive(malformed),
                ReceiveOutcome::Ignored(_)
            ));
            assert_eq!(client.state(), State::WaitingForReply);
        }
    }

    #[test]
    fn lower_down_clears_active_and_failed_sessions() {
        let mut client = Client::new(1);
        client.lower_up(true);
        accept_pending(&mut client);
        client.receive(&[3, 1, 0, 5, 0]);
        assert_eq!(client.state(), State::Failed);

        client.lower_down();
        assert_eq!(client.state(), State::Inactive);
        assert_eq!(client.current_identifier(), None);
        assert_eq!(client.attempts_remaining(), 0);
        assert_eq!(client.failure(), None);
    }
}
