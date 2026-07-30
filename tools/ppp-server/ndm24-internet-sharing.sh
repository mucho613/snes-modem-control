#!/usr/bin/env bash
set -euo pipefail

readonly PPP_INTERFACE="ppp0"
readonly CLIENT_ADDRESS="10.24.0.2"
readonly STATE_DIRECTORY="/run/ndm24-internet-sharing"
readonly FORWARD_STATE_FILE="${STATE_DIRECTORY}/ip-forward"
readonly EXTERNAL_INTERFACE_FILE="${STATE_DIRECTORY}/external-interface"
readonly RULE_COMMENT="ndm24-internet-sharing"
readonly IPTABLES="iptables-legacy"

if [[ ${EUID} -ne 0 ]]; then
  echo "ndm24-internet-sharing.sh must run as root" >&2
  exit 1
fi

find_external_interface() {
  ip -4 route show default |
    awk '$1 == "default" {
      for (field_index = 1; field_index <= NF; field_index++) {
        if ($field_index == "dev" && field_index < NF) {
          print $(field_index + 1)
          exit
        }
      }
    }'
}

read_external_interface() {
  if [[ -s "${EXTERNAL_INTERFACE_FILE}" ]]; then
    cat "${EXTERNAL_INTERFACE_FILE}"
  else
    find_external_interface
  fi
}

forward_out_rule() {
  local operation=$1
  local external_interface=$2
  "${IPTABLES}" -w "${operation}" FORWARD \
    -i "${PPP_INTERFACE}" -o "${external_interface}" \
    -s "${CLIENT_ADDRESS}/32" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
    -m comment --comment "${RULE_COMMENT}" \
    -j ACCEPT
}

forward_in_rule() {
  local operation=$1
  local external_interface=$2
  "${IPTABLES}" -w "${operation}" FORWARD \
    -i "${external_interface}" -o "${PPP_INTERFACE}" \
    -d "${CLIENT_ADDRESS}/32" \
    -m conntrack --ctstate ESTABLISHED,RELATED \
    -m comment --comment "${RULE_COMMENT}" \
    -j ACCEPT
}

masquerade_rule() {
  local operation=$1
  local external_interface=$2
  "${IPTABLES}" -w -t nat "${operation}" POSTROUTING \
    -s "${CLIENT_ADDRESS}/32" -o "${external_interface}" \
    -m comment --comment "${RULE_COMMENT}" \
    -j MASQUERADE
}

remove_rules() {
  local external_interface=$1
  while forward_out_rule -C "${external_interface}" >/dev/null 2>&1; do
    forward_out_rule -D "${external_interface}"
  done
  while forward_in_rule -C "${external_interface}" >/dev/null 2>&1; do
    forward_in_rule -D "${external_interface}"
  done
  while masquerade_rule -C "${external_interface}" >/dev/null 2>&1; do
    masquerade_rule -D "${external_interface}"
  done
}

start_sharing() {
  local external_interface
  local previous_external_interface=""
  external_interface=$(find_external_interface)
  if [[ -z "${external_interface}" ]]; then
    echo "could not find the IPv4 default-route interface" >&2
    exit 1
  fi

  install -d -o root -g root -m 0700 "${STATE_DIRECTORY}"
  if [[ ! -e "${FORWARD_STATE_FILE}" ]]; then
    cat /proc/sys/net/ipv4/ip_forward >"${FORWARD_STATE_FILE}"
  fi
  if [[ -s "${EXTERNAL_INTERFACE_FILE}" ]]; then
    previous_external_interface=$(cat "${EXTERNAL_INTERFACE_FILE}")
  fi
  if [[ -n "${previous_external_interface}" &&
    "${previous_external_interface}" != "${external_interface}" ]]; then
    remove_rules "${previous_external_interface}"
  fi
  printf '%s\n' "${external_interface}" >"${EXTERNAL_INTERFACE_FILE}"
  trap 'stop_sharing >/dev/null 2>&1 || true' ERR

  # Remove stale instances of this service's exact rules, then install one
  # copy at the front of FORWARD so the setup also works with a DROP policy.
  remove_rules "${external_interface}"
  forward_out_rule -I "${external_interface}"
  forward_in_rule -I "${external_interface}"
  masquerade_rule -A "${external_interface}"
  sysctl -q -w net.ipv4.ip_forward=1
  trap - ERR

  echo "NDM24 internet sharing enabled: ${PPP_INTERFACE} -> ${external_interface}"
}

stop_sharing() {
  local external_interface
  external_interface=$(read_external_interface)
  if [[ -n "${external_interface}" ]]; then
    remove_rules "${external_interface}"
  fi

  if [[ -s "${FORWARD_STATE_FILE}" ]]; then
    local previous_forwarding
    previous_forwarding=$(cat "${FORWARD_STATE_FILE}")
    case "${previous_forwarding}" in
      0|1)
        sysctl -q -w "net.ipv4.ip_forward=${previous_forwarding}"
        ;;
      *)
        echo "ignoring invalid saved ip_forward value" >&2
        ;;
    esac
  fi
  rm -f -- "${FORWARD_STATE_FILE}" "${EXTERNAL_INTERFACE_FILE}"
  rmdir -- "${STATE_DIRECTORY}" 2>/dev/null || true
  echo "NDM24 internet sharing disabled"
}

show_status() {
  local external_interface
  external_interface=$(read_external_interface)
  printf 'ip_forward=%s\n' "$(cat /proc/sys/net/ipv4/ip_forward)"
  printf 'ppp_interface=%s\n' "${PPP_INTERFACE}"
  printf 'external_interface=%s\n' "${external_interface:-unavailable}"
  if [[ -n "${external_interface}" ]] &&
    forward_out_rule -C "${external_interface}" >/dev/null 2>&1 &&
    forward_in_rule -C "${external_interface}" >/dev/null 2>&1 &&
    masquerade_rule -C "${external_interface}" >/dev/null 2>&1; then
    echo "sharing=active"
  else
    echo "sharing=inactive"
  fi
}

check_environment() {
  local external_interface
  external_interface=$(find_external_interface)
  if [[ -z "${external_interface}" ]]; then
    echo "could not find the IPv4 default-route interface" >&2
    exit 1
  fi
  "${IPTABLES}" -m conntrack -h >/dev/null
  "${IPTABLES}" -t nat -j MASQUERADE -h >/dev/null
  echo "NDM24 internet sharing prerequisites available: ${PPP_INTERFACE} -> ${external_interface}"
}

case "${1:-}" in
  check)
    check_environment
    ;;
  start)
    start_sharing
    ;;
  stop)
    stop_sharing
    ;;
  status)
    show_status
    ;;
  *)
    echo "usage: $0 {check|start|stop|status}" >&2
    exit 2
    ;;
esac
