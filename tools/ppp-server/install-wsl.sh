#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "install-wsl.sh must run as root" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
peer_file="${script_dir}/ndm24-lcp"
chat_file="${script_dir}/ndm24-answer.chat"
service_file="${script_dir}/ndm24-ppp-server.service"
ntp_script="${script_dir}/ndm24-ntp-server.py"
ntp_test_file="${script_dir}/test_ndm24_ntp_server.py"
ntp_service_file="${script_dir}/ndm24-ntp-server.service"

for command_name in pppd chat python3 systemctl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "required command is missing: ${command_name}" >&2
    exit 1
  fi
done

python3 "${ntp_test_file}"

systemctl stop ndm24-ppp-server.service 2>/dev/null || true
systemctl disable ndm24-ppp-server.service 2>/dev/null || true
systemctl reset-failed ndm24-ppp-server.service 2>/dev/null || true
systemctl stop ndm24-ntp-server.service 2>/dev/null || true
systemctl disable ndm24-ntp-server.service 2>/dev/null || true
systemctl reset-failed ndm24-ntp-server.service 2>/dev/null || true

# This workstation previously used the same DFM-56U for a serial login.
# The user has retired that use, so prevent mgetty's Restart=always service
# from reclaiming ttyACM0 after the PPP server attaches it.
systemctl disable --now mgetty.service 2>/dev/null || true
systemctl reset-failed mgetty.service 2>/dev/null || true

install -d -o root -g root -m 0755 /etc/ppp/peers
install -o root -g root -m 0600 "${peer_file}" /etc/ppp/peers/ndm24-lcp
install -o root -g root -m 0600 "${chat_file}" /etc/ppp/ndm24-answer.chat
install -o root -g root -m 0644 \
  "${service_file}" /etc/systemd/system/ndm24-ppp-server.service
install -d -o root -g root -m 0755 /usr/local/lib/ndm24
install -o root -g root -m 0755 \
  "${ntp_script}" /usr/local/lib/ndm24/ndm24-ntp-server.py
install -o root -g root -m 0644 \
  "${ntp_service_file}" /etc/systemd/system/ndm24-ntp-server.service

pap_file=/etc/ppp/pap-secrets
pap_entry=$'ndm24\tndm24-server\tndm24-test\t10.24.0.2'
if [[ ! -e "${pap_file}" ]]; then
  install -o root -g root -m 0600 /dev/null "${pap_file}"
fi
if ! grep -Eq '^[[:space:]]*ndm24[[:space:]]+ndm24-server[[:space:]]+' \
  "${pap_file}"; then
  if [[ ! -e "${pap_file}.pre-ndm24" ]]; then
    cp --preserve=mode,ownership,timestamps \
      "${pap_file}" "${pap_file}.pre-ndm24"
  fi
  printf '\n# Closed pseudo-PSTN NDM24 test account\n%s\n' \
    "${pap_entry}" >>"${pap_file}"
fi
chown root:root "${pap_file}"
chmod 0600 "${pap_file}"

if [[ ! -e /var/log/ndm24-pppd.log ]]; then
  install -o root -g root -m 0600 /dev/null /var/log/ndm24-pppd.log
else
  chown root:root /var/log/ndm24-pppd.log
  chmod 0600 /var/log/ndm24-pppd.log
fi
systemctl daemon-reload

# Parse and resolve all options without opening the modem or starting a link.
# pppd only recognizes a serial-device token when that path currently exists;
# use /dev/null for this dry run so installation also works while USB is
# detached back to Windows.
dryrun_peer="$(mktemp /tmp/ndm24-lcp.XXXXXX)"
trap 'rm -f -- "${dryrun_peer}"' EXIT
sed 's#^/dev/ttyACM0$#/dev/null#' \
  /etc/ppp/peers/ndm24-lcp >"${dryrun_peer}"
pppd file "${dryrun_peer}" dryrun >/dev/null
rm -f -- "${dryrun_peer}"
trap - EXIT

echo "installed NDM24 PPP server configuration"
echo "service is installed but not enabled or started"
