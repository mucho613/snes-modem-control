#!/usr/bin/env python3
"""Minimal NTPv4 server for the closed NDM24 pseudo-PSTN test network."""

import argparse
import errno
import logging
import socket
import struct
import time

NTP_PACKET_LENGTH = 48
NTP_UNIX_EPOCH_OFFSET = 2_208_988_800
NTP_DELEGATION_RETRY_LIMIT = 5
NTP_DELEGATION_RETRY_DELAY_SECONDS = 1.0


def ntp_timestamp(now: float) -> bytes:
    unix_seconds = int(now)
    fraction = int((now - unix_seconds) * (1 << 32)) & 0xFFFFFFFF
    return struct.pack("!II", unix_seconds + NTP_UNIX_EPOCH_OFFSET, fraction)


def build_response(request: bytes, received_at: float) -> bytes | None:
    if len(request) < NTP_PACKET_LENGTH:
        return None
    version = (request[0] >> 3) & 0x07
    mode = request[0] & 0x07
    if version not in (3, 4) or mode != 3:
        return None

    response = bytearray(NTP_PACKET_LENGTH)
    response[0] = (version << 3) | 4
    response[1] = 1
    response[2] = request[2]
    response[3] = 0xEC  # signed precision exponent -20
    response[8:12] = struct.pack("!I", 1 << 16)
    response[12:16] = b"LOCL"
    response[16:24] = ntp_timestamp(received_at)
    response[24:32] = request[40:48]
    response[32:40] = ntp_timestamp(received_at)
    response[40:48] = ntp_timestamp(time.time())
    return bytes(response)


def probe_existing_server(address: str, port: int) -> bool:
    cookie = struct.pack("!II", 0x4E444D24, int(time.monotonic()) & 0xFFFFFFFF)
    request = bytearray(NTP_PACKET_LENGTH)
    request[0] = 0x23
    request[40:48] = cookie
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(2)
        try:
            client.sendto(request, (address, port))
            response, _ = client.recvfrom(512)
        except (OSError, TimeoutError):
            return False
    if len(response) < NTP_PACKET_LENGTH:
        return False
    version = (response[0] >> 3) & 0x07
    mode = response[0] & 0x07
    return (
        version in (3, 4)
        and mode == 4
        and 1 <= response[1] <= 15
        and response[24:32] == cookie
    )


def bind_when_available(address: str, port: int) -> socket.socket | None:
    delegation_probe_failures = 0
    while True:
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            server.bind((address, port))
            return server
        except OSError as error:
            server.close()
            if error.errno == errno.EADDRNOTAVAIL:
                logging.info("waiting for PPP address %s", address)
                time.sleep(0.5)
                continue
            if error.errno == errno.EADDRINUSE:
                if probe_existing_server(address, port):
                    logging.info(
                        "compatible NTP daemon already owns %s:%d; delegating responses",
                        address,
                        port,
                    )
                    return None
                delegation_probe_failures += 1
                if delegation_probe_failures <= NTP_DELEGATION_RETRY_LIMIT:
                    logging.info(
                        "NTP port %s:%d is busy but the owner is not ready; "
                        "retrying delegation probe (%d/%d)",
                        address,
                        port,
                        delegation_probe_failures,
                        NTP_DELEGATION_RETRY_LIMIT,
                    )
                    time.sleep(NTP_DELEGATION_RETRY_DELAY_SECONDS)
                    continue
            raise


def serve(address: str, port: int, once: bool) -> None:
    server = bind_when_available(address, port)
    if server is None:
        while True:
            time.sleep(30)
            if not probe_existing_server(address, port):
                raise RuntimeError("delegated NTP daemon stopped responding")

    with server:
        logging.info("listening on %s:%d", address, port)
        while True:
            request, peer = server.recvfrom(512)
            received_at = time.time()
            response = build_response(request, received_at)
            if response is None:
                logging.warning("ignored invalid request from %s:%d", *peer)
                continue
            server.sendto(response, peer)
            cookie = request[40:48].hex()
            logging.info(
                "response to %s:%d cookie=%s unix_seconds=%d",
                peer[0],
                peer[1],
                cookie,
                int(received_at),
            )
            if once:
                return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="10.24.0.1")
    parser.add_argument("--port", type=int, default=123)
    parser.add_argument("--once", action="store_true")
    arguments = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    serve(arguments.bind, arguments.port, arguments.once)


if __name__ == "__main__":
    main()
