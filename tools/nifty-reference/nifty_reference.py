#!/usr/bin/env python3
"""Run one redacted DFM-56U/pppd reference call to the Nifty access point."""

from __future__ import annotations

import getpass
import os
import re
import selectors
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

ACCESS_NUMBER = "0570-077-705"
DEVICE = Path("/dev/ttyACM0")
TOTAL_LIMIT_SECONDS = 120
NETWORK_OBSERVATION_SECONDS = 30
PASSWORD_ALPHABET = set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    "#$&'()*,.-/:;<=>[]^_`{|}~!"
)


def validate_id(value: str) -> None:
    if not (
        len(value) == 8
        and value[:3].isascii()
        and value[:3].isalpha()
        and value[3:].isascii()
        and value[3:].isdigit()
    ):
        raise ValueError("@nifty ID must have the form abc12345")


def validate_password(value: str) -> None:
    if not 6 <= len(value) <= 24:
        raise ValueError("@nifty login password must be 6 to 24 characters")
    if any(character not in PASSWORD_ALPHABET for character in value):
        raise ValueError("@nifty login password contains an unsupported character")


def redact(line: str, peer_id: str, password: str) -> str:
    line = line.replace(peer_id, "<nifty-id>")
    line = line.replace(password, "<password>")
    line = re.sub(
        r"(\[(?:PAP|CHAP) (?:AuthReq|Response)\b).*?(\])",
        r"\1 <payload redacted>\2",
        line,
    )
    return line


def ppp_options(peer_id: str, password: str, chat_script: Path) -> str:
    options = [
        str(DEVICE),
        "115200",
        "modem",
        "lock",
        "nocrtscts",
        "noauth",
        "noipdefault",
        "ipcp-accept-local",
        "ipcp-accept-remote",
        "usepeerdns",
        "noccp",
        "novj",
        "novjccomp",
        "nopcomp",
        "noaccomp",
        "refuse-eap",
        "refuse-mschap",
        "refuse-mschap-v2",
        "maxfail",
        "1",
        "lcp-echo-interval",
        "10",
        "lcp-echo-failure",
        "3",
        "user",
        peer_id,
        "password",
        password,
        "connect",
        f"/usr/sbin/chat -f {shlex.quote(str(chat_script))}",
    ]
    return "\n".join(shlex.quote(option) for option in options) + "\n"


def main() -> int:
    if os.geteuid() != 0:
        print("run as root so pppd can open /dev/ttyACM0", file=sys.stderr)
        return 2
    if not DEVICE.exists():
        print(f"{DEVICE} is absent; attach the DFM-56U to WSL2 first", file=sys.stderr)
        return 2

    print(
        f"WARNING: this makes one charged PSTN call to Nifty {ACCESS_NUMBER}.\n"
        "No automatic redial is enabled. Type DIAL to continue: ",
        end="",
        flush=True,
    )
    if sys.stdin.readline().rstrip("\r\n") != "DIAL":
        print("charged call cancelled", file=sys.stderr)
        return 2

    peer_id = input("@nifty ID: ")
    password = getpass.getpass("Login password (hidden): ")
    try:
        validate_id(peer_id)
        validate_password(password)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2

    script_dir = Path(__file__).resolve().parent
    chat_script = script_dir / "nifty-connect.chat"
    output_dir = script_dir.parent.parent / "build" / "hardware-tests" / "nifty-reference"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / time.strftime("pppd-%Y%m%d-%H%M%S.redacted.log")

    subprocess.run(
        ["systemctl", "disable", "--now", "mgetty.service"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["systemctl", "stop", "ndm24-ppp-server.service"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    process = subprocess.Popen(
        ["/usr/sbin/pppd", "file", "/dev/stdin", "nodetach", "debug"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    process.stdin.write(ppp_options(peer_id, password, chat_script))
    process.stdin.close()

    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    started = time.monotonic()
    network_opened_at: float | None = None
    exit_reason = "pppd exited"

    try:
        with output_path.open("x", encoding="utf-8", newline="\n") as report:
            while process.poll() is None:
                now = time.monotonic()
                if now - started >= TOTAL_LIMIT_SECONDS:
                    exit_reason = "120 second hard limit"
                    process.send_signal(signal.SIGTERM)
                    break
                if (
                    network_opened_at is not None
                    and now - network_opened_at >= NETWORK_OBSERVATION_SECONDS
                ):
                    exit_reason = "30 second PPP observation complete"
                    process.send_signal(signal.SIGTERM)
                    break

                for key, _ in selector.select(timeout=0.25):
                    line = key.fileobj.readline()
                    if not line:
                        continue
                    safe = redact(line, peer_id, password)
                    print(safe, end="")
                    report.write(safe)
                    report.flush()
                    if "local  IP address" in safe:
                        network_opened_at = network_opened_at or time.monotonic()

            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                exit_reason += "; SIGKILL required"
                process.kill()
                process.wait(timeout=5)

            for line in process.stdout:
                safe = redact(line, peer_id, password)
                print(safe, end="")
                report.write(safe)
            report.write(f"\nreference runner: {exit_reason}; exit={process.returncode}\n")
    finally:
        password = "\0" * len(password)
        peer_id = "\0" * len(peer_id)

    print(f"redacted local report: {output_path}")
    print("pppd terminated; DTR was dropped. Confirm that the modem is on-hook.")
    return 0 if network_opened_at is not None else 1


if __name__ == "__main__":
    raise SystemExit(main())
