import hashlib
import hmac
import json
import os
import tempfile
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


HK_NODE_ID = "HS-HK-01-Lisa"
MAX_BODY_BYTES = 16 * 1024
MAX_REPORT_AGE_SECONDS = 300
STALE_AFTER_SECONDS = 1800


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def parse_timestamp(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def homepage_html() -> str:
    return """<!doctype html><html lang=\"zh-CN\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>HomeStream Network Status</title><style>body{font:16px system-ui;background:#0b1220;color:#e5e7eb;max-width:1120px;margin:40px auto;padding:0 20px}h1{margin-bottom:4px}.nodes{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:18px;margin:24px 0}.node{background:#111c31;border:1px solid #263754;border-radius:12px;padding:18px}.node h2{margin:0 0 4px}.state{color:#94a3b8;min-height:22px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:14px}.card{background:#172033;border-radius:9px;padding:12px}.v{font-size:21px;font-weight:700;color:#7dd3fc}button{font:inherit;padding:8px 12px;background:#1d4ed8;color:white;border:0;border-radius:6px;cursor:pointer}a{color:#7dd3fc}.links{display:flex;gap:18px}@media(max-width:520px){.nodes{grid-template-columns:1fr}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}</style><h1>HomeStream Network Status</h1><p id=\"state\" class=\"state\">加载中…</p><button id=\"refresh\" type=\"button\">立即刷新</button><main class=\"nodes\"><section class=\"node\"><h2>US · HS-US-01-Bandwagon</h2><div id=\"us\" class=\"grid\"></div></section><section class=\"node\"><h2>HK · HS-HK-01-Lisa</h2><p id=\"hk-state\" class=\"state\"></p><div id=\"hk\" class=\"grid\"></div></section></main><p class=\"links\"><a href=\"/status/production\">查看 13 项监控明细与可用率</a><a href=\"/manage-status-page\">管理员登录</a></p><script>const $=id=>document.getElementById(id);const gb=n=>typeof n==='number'?(n/1024/1024/1024).toFixed(2)+' GB':'不可用';const cards=x=>[['CPU',x.cpu_usage_percent+'%'],['内存',x.memory_used_percent+'%'],['磁盘',x.disk_used_percent+'%'],['本月流量',gb(x.vnstat_month_total)],['Docker',x.docker_running+' 个容器'],['运行时间',x.uptime],['3X-UI',x.xui_status],['更新时间',x.timestamp]].map(([k,v])=>'<div class=card><div>'+k+'</div><div class=v>'+v+'</div></div>').join('');async function load(){const r=await fetch('/api/server-summary?refresh='+Date.now(),{cache:'no-store'});if(!r.ok)throw Error('指标暂不可用');const x=await r.json();$('us').innerHTML=cards(x.nodes.us);const h=x.nodes.hk;$('hk').innerHTML=h.metrics?cards(h.metrics):'<div class=card>暂未收到 HK 上报</div>';$('hk-state').textContent='状态：'+h.status+(h.age_seconds==null?'':'；上报距今 '+h.age_seconds+' 秒');$('state').textContent='US 本地指标与 HK 最近上报；页面刷新不会直接探测 HK。更新时间 '+x.timestamp}function refresh(){load().catch(e=>$('state').textContent=e.message)}$('refresh').addEventListener('click',refresh);refresh()</script></html>"""


class StatusState:
    def __init__(self, state_path: str, report_key: bytes, now=utc_now):
        if len(report_key) < 32:
            raise ValueError("report key must contain at least 32 bytes")
        self.state_path = Path(state_path)
        self.report_key = report_key
        self.now = now

    def accept_report(self, headers, body: bytes) -> None:
        if len(body) > MAX_BODY_BYTES:
            raise ValueError("report body is too large")
        node_id = headers.get("X-HomeStream-Node", "")
        timestamp = headers.get("X-HomeStream-Timestamp", "")
        signature = headers.get("X-HomeStream-Signature", "")
        if node_id != HK_NODE_ID:
            raise PermissionError("unexpected node")
        try:
            sent_at = parse_timestamp(timestamp)
        except ValueError as error:
            raise PermissionError("invalid report timestamp") from error
        if abs((self.now() - sent_at).total_seconds()) > MAX_REPORT_AGE_SECONDS:
            raise PermissionError("report timestamp outside acceptance window")
        expected = hmac.new(self.report_key, timestamp.encode() + b"\n" + body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature):
            raise PermissionError("invalid report signature")
        try:
            metrics = json.loads(body)
        except json.JSONDecodeError as error:
            raise ValueError("report body is not JSON") from error
        required = {"timestamp", "hostname", "cpu_usage_percent", "memory_used_percent", "disk_used_percent", "docker_running", "docker_unhealthy", "xui_status", "vnstat_month_total"}
        if not isinstance(metrics, dict) or not required.issubset(metrics):
            raise ValueError("report schema is incomplete")
        self._write({"node_id": node_id, "received_at": self.now().strftime("%Y-%m-%dT%H:%M:%SZ"), "metrics": metrics})

    def node_summary(self) -> dict:
        record = self._read()
        if not record:
            return {"node_id": HK_NODE_ID, "status": "unavailable", "age_seconds": None, "metrics": None}
        try:
            received_at = parse_timestamp(record["received_at"])
            age_seconds = max(0, int((self.now() - received_at).total_seconds()))
            metrics = record["metrics"]
        except (KeyError, TypeError, ValueError):
            return {"node_id": HK_NODE_ID, "status": "unavailable", "age_seconds": None, "metrics": None}
        return {
            "node_id": HK_NODE_ID,
            "status": "fresh" if age_seconds <= STALE_AFTER_SECONDS else "stale",
            "age_seconds": age_seconds,
            "metrics": metrics,
        }

    def summary(self, us_summary: dict) -> dict:
        result = dict(us_summary)
        result["nodes"] = {"us": dict(us_summary), "hk": self.node_summary()}
        return result

    def _read(self) -> dict | None:
        try:
            with self.state_path.open(encoding="utf-8") as file:
                return json.load(file)
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            return None

    def _write(self, value: dict) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_path = tempfile.mkstemp(prefix=".hk-report-", dir=self.state_path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as file:
                json.dump(value, file, separators=(",", ":"))
                file.flush()
                os.fsync(file.fileno())
            os.chmod(temporary_path, 0o640)
            os.replace(temporary_path, self.state_path)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)


def make_handler():
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                self._send(HTTPStatus.OK, homepage_html().encode(), "text/html; charset=utf-8")
                return
            if path == "/api/server-summary":
                try:
                    body = json.dumps(self.server.state.summary(self.server.summary()), separators=(",", ":")).encode()
                except Exception:
                    self._send(HTTPStatus.SERVICE_UNAVAILABLE, b'{"error":"summary_unavailable"}', "application/json; charset=utf-8")
                    return
                self._send(HTTPStatus.OK, body, "application/json; charset=utf-8")
                return
            self.send_error(HTTPStatus.NOT_FOUND)

        def do_POST(self):
            if urlparse(self.path).path != "/api/node-reports/hk":
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            try:
                length = int(self.headers.get("Content-Length", "-1"))
                if length < 0 or length > MAX_BODY_BYTES:
                    raise ValueError("invalid content length")
                self.server.state.accept_report(self.headers, self.rfile.read(length))
            except PermissionError:
                self._send(HTTPStatus.UNAUTHORIZED, b'{"error":"unauthorized"}', "application/json; charset=utf-8")
                return
            except ValueError:
                self._send(HTTPStatus.BAD_REQUEST, b'{"error":"invalid_report"}', "application/json; charset=utf-8")
                return
            self.send_response(HTTPStatus.NO_CONTENT)
            self.end_headers()

        def _send(self, status: HTTPStatus, body: bytes, content_type: str):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format, *_args):
            return

    return Handler


class StatusServer(ThreadingHTTPServer):
    def __init__(self, state: StatusState, summary, port: int = 3010):
        self.state = state
        self.summary = summary
        super().__init__(("127.0.0.1", port), make_handler())


def create_server(state: StatusState, summary, port: int = 0) -> StatusServer:
    return StatusServer(state, summary, port)


def command_summary(command_path: str) -> dict:
    import subprocess

    result = subprocess.run([command_path], check=True, capture_output=True, text=True, timeout=12)
    return json.loads(result.stdout)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="HomeStream US status service")
    parser.add_argument("--state-path", required=True)
    parser.add_argument("--key-path", required=True)
    parser.add_argument("--summary-command", required=True)
    parser.add_argument("--port", type=int, default=3010)
    arguments = parser.parse_args()
    key = Path(arguments.key_path).read_bytes().strip()
    create_server(StatusState(arguments.state_path, key), lambda: command_summary(arguments.summary_command), arguments.port).serve_forever()
