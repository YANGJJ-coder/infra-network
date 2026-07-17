import hashlib
import hmac
import json
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from status.status_server import HK_NODE_ID, StatusState, create_server, homepage_html


REPORT_KEY = b"0123456789abcdef0123456789abcdef"
NOW = datetime(2026, 7, 17, 1, 30, tzinfo=timezone.utc)
HK_METRICS = {
    "timestamp": "2026-07-17T01:30:00Z",
    "hostname": "C20260716105537",
    "uptime": "up 1 day",
    "load_1m": 0.1,
    "load_5m": 0.2,
    "load_15m": 0.3,
    "cpu_usage_percent": 2.5,
    "memory_used_percent": 40.0,
    "disk_used_percent": 20,
    "docker_running": 1,
    "docker_unhealthy": 0,
    "xui_status": "running",
    "vnstat_month_total": 1024,
}


def signature(timestamp: str, body: bytes, key: bytes = REPORT_KEY) -> str:
    return hmac.new(key, timestamp.encode() + b"\n" + body, hashlib.sha256).hexdigest()


class StatusServerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.state = StatusState(str(Path(self.directory.name) / "hk-report.json"), REPORT_KEY, now=lambda: NOW)
        self.server = create_server(self.state, summary=lambda: {"timestamp": "2026-07-17T01:30:00Z", "cpu_usage_percent": 1.0})
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.directory.cleanup()

    def post_report(self, metrics=HK_METRICS, key=REPORT_KEY):
        body = json.dumps(metrics, separators=(",", ":")).encode()
        timestamp = NOW.strftime("%Y-%m-%dT%H:%M:%SZ")
        request = Request(
            self.base_url + "/api/node-reports/hk",
            data=body,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "X-HomeStream-Node": HK_NODE_ID,
                "X-HomeStream-Timestamp": timestamp,
                "X-HomeStream-Signature": signature(timestamp, body, key),
            },
        )
        return urlopen(request)

    def get_summary(self):
        with urlopen(self.base_url + "/api/server-summary?refresh=1") as response:
            self.assertEqual("no-store", response.headers["Cache-Control"])
            return json.load(response)

    def test_valid_hk_report_is_persisted_and_added_to_summary(self):
        with self.post_report() as response:
            self.assertEqual(204, response.status)
        summary = self.get_summary()
        self.assertEqual(1.0, summary["cpu_usage_percent"])
        self.assertEqual(1.0, summary["nodes"]["us"]["cpu_usage_percent"])
        self.assertEqual("fresh", summary["nodes"]["hk"]["status"])
        self.assertEqual(HK_NODE_ID, summary["nodes"]["hk"]["node_id"])
        self.assertEqual(2.5, summary["nodes"]["hk"]["metrics"]["cpu_usage_percent"])

    def test_bad_signature_does_not_replace_last_hk_report(self):
        with self.assertRaises(HTTPError) as captured:
            self.post_report(key=b"wrong-key-wrong-key-wrong-key-1234")
        self.assertEqual(401, captured.exception.code)
        self.assertEqual("unavailable", self.get_summary()["nodes"]["hk"]["status"])

    def test_expired_hk_report_is_stale(self):
        with self.post_report() as response:
            self.assertEqual(204, response.status)
        self.state.now = lambda: NOW + timedelta(seconds=1801)
        self.assertEqual("stale", self.get_summary()["nodes"]["hk"]["status"])

    def test_homepage_contains_refresh_control_and_never_fetches_hk_directly(self):
        html = homepage_html()
        self.assertIn('id="refresh"', html)
        self.assertIn('/api/server-summary?refresh=', html)
        self.assertNotIn('/api/node-reports/hk', html)


if __name__ == "__main__":
    unittest.main()
