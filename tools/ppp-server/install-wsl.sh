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

for command_name in pppd chat systemctl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "required command is missing: ${command_name}" >&2
    exit 1
  fi
done

systemctl stop ndm24-ppp-server.service 2>/dev/null || true
systemctl disable ndm24-ppp-server.service 2>/dev/null || true

install -d -o root -g root -m 0755 /etc/ppp/peers
install -o root -g root -m 0600 "${peer_file}" /etc/ppp/peers/ndm24-lcp
install -o root -g root -m 0600 "${chat_file}" /etc/ppp/ndm24-answer.chat
install -o root -g root -m 0644 \
  "${service_file}" /etc/systemd/system/ndm24-ppp-server.service

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
pppd call ndm24-lcp dryrun >/dev/null

echo "installed NDM24 PPP server configuration"
echo "service is installed but not enabled or started"
