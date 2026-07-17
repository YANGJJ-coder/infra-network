import hashlib
import hmac
import json
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from status.hk_reporter import NODE_ID, command, send_report


class FakeResponse:
    status = 204

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class HkReporterTests(unittest.TestCase):
    def test_missing_optional_command_returns_empty_output(self):
        with patch("status.hk_reporter.subprocess.run", side_effect=FileNotFoundError):
            self.assertEqual("", command("vnstat", "--json", "m"))

    def test_report_uses_expected_node_and_hmac_header(self):
        key = b"0123456789abcdef0123456789abcdef"
        metrics = {"timestamp": "2026-07-17T01:30:00Z", "cpu_usage_percent": 2.5}
        with patch("status.hk_reporter.urlopen", return_value=FakeResponse()) as opened:
            with patch("status.hk_reporter.datetime") as clock:
                clock.now.return_value = datetime(2026, 7, 17, 1, 30, tzinfo=timezone.utc)
                send_report("https://status.example/api/node-reports/hk", key, metrics)
        request = opened.call_args.args[0]
        body = request.data
        timestamp = "2026-07-17T01:30:00Z"
        expected = hmac.new(key, timestamp.encode() + b"\n" + body, hashlib.sha256).hexdigest()
        self.assertEqual(NODE_ID, request.headers["X-homestream-node"])
        self.assertEqual(expected, request.headers["X-homestream-signature"])
        self.assertEqual(metrics, json.loads(body))


if __name__ == "__main__":
    unittest.main()
