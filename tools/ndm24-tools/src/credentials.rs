use std::io::{self, Write};
use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use ndm24_protocol::{
    MODEM_MAILBOX_COMMAND_PAP_CREDENTIALS_CLEAR, MODEM_MAILBOX_COMMAND_PAP_PASSWORD_SET,
    MODEM_MAILBOX_COMMAND_PAP_PEER_ID_SET,
};
use zeroize::Zeroizing;

use crate::qusb2snes;

const NIFTY_ID_LENGTH: usize = 8;
const NIFTY_PASSWORD_MINIMUM_LENGTH: usize = 6;
const NIFTY_PASSWORD_MAXIMUM_LENGTH: usize = 24;

const FLAG_PEER_ID: u8 = 0x01;
const FLAG_PASSWORD: u8 = 0x02;
const FLAG_TRANSIENT: u8 = 0x04;
const REQUIRED_FLAGS: u8 = FLAG_PEER_ID | FLAG_PASSWORD | FLAG_TRANSIENT;

pub(crate) struct PapCredentials {
    peer_id: Zeroizing<String>,
    password: Zeroizing<String>,
}

impl PapCredentials {
    pub(crate) fn prompt() -> Result<Self> {
        let mut peer_id = Zeroizing::new(String::new());
        print!("@nifty ID: ");
        io::stdout().flush().context("flush @nifty ID prompt")?;
        io::stdin()
            .read_line(&mut peer_id)
            .context("read @nifty ID")?;
        truncate_line_ending(&mut peer_id);

        let password = Zeroizing::new(
            rpassword::prompt_password("Login password (hidden): ")
                .context("read masked @nifty login password")?,
        );
        Self::new(peer_id, password)
    }

    fn new(peer_id: Zeroizing<String>, password: Zeroizing<String>) -> Result<Self> {
        validate_nifty_id(peer_id.as_bytes())?;
        validate_nifty_password(password.as_bytes())?;
        Ok(Self { peer_id, password })
    }

    pub(crate) async fn upload(
        &self,
        websocket: &str,
        labels: &Path,
        timeout: Duration,
    ) -> Result<()> {
        qusb2snes::mailbox_command_with_arguments(
            websocket,
            labels,
            MODEM_MAILBOX_COMMAND_PAP_CREDENTIALS_CLEAR,
            &[],
            timeout,
        )
        .await
        .context("clear staged PAP credentials")?;

        let result = self.upload_fields(websocket, labels, timeout).await;
        if let Err(error) = result {
            let cleanup = qusb2snes::mailbox_command_with_arguments(
                websocket,
                labels,
                MODEM_MAILBOX_COMMAND_PAP_CREDENTIALS_CLEAR,
                &[],
                timeout,
            )
            .await;
            return match cleanup {
                Ok(_) => Err(error).context("credential upload failed; SFC staging was cleared"),
                Err(cleanup_error) => Err(error).context(format!(
                    "credential upload failed and SFC cleanup also failed: {cleanup_error:#}"
                )),
            };
        }

        let snapshot = qusb2snes::read_ppp_snapshot(websocket, labels).await?;
        ensure!(
            snapshot.pap_credential_flags & REQUIRED_FLAGS == REQUIRED_FLAGS
                && snapshot.pap_peer_id_length as usize == self.peer_id.len()
                && snapshot.pap_password_length as usize == self.password.len(),
            "SFC did not confirm complete transient PAP credential staging"
        );
        Ok(())
    }

    async fn upload_fields(&self, websocket: &str, labels: &Path, timeout: Duration) -> Result<()> {
        let mut peer_id = Zeroizing::new(Vec::with_capacity(1 + self.peer_id.len()));
        peer_id.push(self.peer_id.len() as u8);
        peer_id.extend_from_slice(self.peer_id.as_bytes());
        qusb2snes::mailbox_command_with_arguments(
            websocket,
            labels,
            MODEM_MAILBOX_COMMAND_PAP_PEER_ID_SET,
            &peer_id,
            timeout,
        )
        .await
        .context("stage PAP Peer-ID")?;

        let mut password = Zeroizing::new(Vec::with_capacity(1 + self.password.len()));
        password.push(self.password.len() as u8);
        password.extend_from_slice(self.password.as_bytes());
        qusb2snes::mailbox_command_with_arguments(
            websocket,
            labels,
            MODEM_MAILBOX_COMMAND_PAP_PASSWORD_SET,
            &password,
            timeout,
        )
        .await
        .context("stage PAP password")?;
        Ok(())
    }
}

fn truncate_line_ending(value: &mut String) {
    if value.ends_with('\n') {
        value.pop();
        if value.ends_with('\r') {
            value.pop();
        }
    }
}

fn validate_nifty_id(value: &[u8]) -> Result<()> {
    ensure!(
        value.len() == NIFTY_ID_LENGTH
            && value[..3].iter().all(u8::is_ascii_alphabetic)
            && value[3..].iter().all(u8::is_ascii_digit),
        "@nifty ID must have the form abc12345 (three ASCII letters and five digits)"
    );
    Ok(())
}

fn validate_nifty_password(value: &[u8]) -> Result<()> {
    ensure!(
        (NIFTY_PASSWORD_MINIMUM_LENGTH..=NIFTY_PASSWORD_MAXIMUM_LENGTH).contains(&value.len()),
        "@nifty login password must be 6 to 24 bytes"
    );
    if let Some(byte) = value.iter().copied().find(|byte| {
        !(byte.is_ascii_alphanumeric() || b"#$&'()*,.-/:;<=>[]^_`{|}~!".contains(byte))
    }) {
        bail!("@nifty login password contains an unsupported byte (0x{byte:02x})");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_official_nifty_id_shape() {
        assert!(validate_nifty_id(b"abc12345").is_ok());
        assert!(validate_nifty_id(b"ABc12345").is_ok());
        assert!(validate_nifty_id(b"abcd1234").is_err());
        assert!(validate_nifty_id(b"abc1234x").is_err());
    }

    #[test]
    fn validates_documented_login_password_alphabet() {
        assert!(validate_nifty_password(b"Ab1#$!").is_ok());
        assert!(validate_nifty_password(b"abcdef").is_ok());
        assert!(validate_nifty_password(b"abcde").is_err());
        assert!(validate_nifty_password(b"abcde?").is_err());
        assert!(validate_nifty_password("abcdeあ".as_bytes()).is_err());
    }

    #[test]
    fn removes_only_a_terminal_line_ending() {
        let mut value = String::from("abc12345\r\n");
        truncate_line_ending(&mut value);
        assert_eq!(value, "abc12345");
    }
}
