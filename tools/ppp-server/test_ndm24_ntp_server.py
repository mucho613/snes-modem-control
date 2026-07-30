#!/usr/bin/env python3

import errno
import importlib.util
from pathlib import Path
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).with_name("ndm24-ntp-server.py")
SPEC = importlib.util.spec_from_file_location("ndm24_ntp_server", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
SERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERVER)


class BusySocket:
    def bind(self, _address):
        raise OSError(errno.EADDRINUSE, "Address already in use")

    def close(self):
        pass


class BindWhenAvailableTests(unittest.TestCase):
    @mock.patch.object(SERVER.time, "sleep")
    @mock.patch.object(SERVER, "probe_existing_server", side_effect=[False, True])
    @mock.patch.object(SERVER.socket, "socket", side_effect=lambda *_args: BusySocket())
    def test_retries_until_existing_daemon_is_ready(
        self, socket_factory, probe, sleep
    ):
        result = SERVER.bind_when_available("10.24.0.1", 123)

        self.assertIsNone(result)
        self.assertEqual(socket_factory.call_count, 2)
        self.assertEqual(probe.call_count, 2)
        sleep.assert_called_once_with(SERVER.NTP_DELEGATION_RETRY_DELAY_SECONDS)

    @mock.patch.object(SERVER.time, "sleep")
    @mock.patch.object(SERVER, "probe_existing_server", return_value=False)
    @mock.patch.object(SERVER.socket, "socket", side_effect=lambda *_args: BusySocket())
    def test_rejects_incompatible_owner_after_retry_limit(
        self, socket_factory, probe, sleep
    ):
        with mock.patch.object(SERVER, "NTP_DELEGATION_RETRY_LIMIT", 1):
            with self.assertRaisesRegex(OSError, "Address already in use"):
                SERVER.bind_when_available("10.24.0.1", 123)

        self.assertEqual(socket_factory.call_count, 2)
        self.assertEqual(probe.call_count, 2)
        self.assertEqual(sleep.call_count, 1)


if __name__ == "__main__":
    unittest.main()
