#!/usr/bin/env bash
set -euo pipefail

device="${1:-/dev/ttyACM0}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
chat_file="${script_dir}/ndm24-probe.chat"

if [[ ${EUID} -ne 0 ]]; then
  echo "probe-modem.sh must run as root" >&2
  exit 1
fi
if [[ ! -c "${device}" ]]; then
  echo "modem device was not found: ${device}" >&2
  exit 1
fi
if systemctl is-active --quiet ndm24-ppp-server.service; then
  echo "stop ndm24-ppp-server.service before probing the modem" >&2
  exit 1
fi

stty -F "${device}" 115200 raw -echo -crtscts clocal
exec 3<>"${device}"
/usr/sbin/chat -V -s -f "${chat_file}" <&3 >&3
