#!/usr/bin/env python3
"""Collect local HK host metrics and send one authenticated report to US."""

import hashlib
import hmac
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


NODE_ID = "HS-HK-01-Lisa"


def command(*args: str) -> str:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10, check=False).stdout.strip()
    except FileNotFoundError:
        return ""


def docker_state(name: str) -> str:
    value = command("docker", "inspect", "-f", "{{.State.Status}}", name)
    return value or "unavailable"


def update_traffic_total(state_path: Path, interface: str, rx: int, tx: int) -> int:
    try:
        previous = json.loads(state_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        previous = {}
    if previous.get("interface") == interface:
        previous_rx = int(previous.get("rx", 0))
        previous_tx = int(previous.get("tx", 0))
        rx_delta = rx - previous_rx if rx >= previous_rx else rx
        tx_delta = tx - previous_tx if tx >= previous_tx else tx
        total = int(previous.get("total", 0)) + rx_delta + tx_delta
    else:
        total = rx + tx
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = state_path.with_name(f".{state_path.name}.tmp")
    temporary.write_text(json.dumps({"interface": interface, "rx": rx, "tx": tx, "total": total}), encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, state_path)
    return total


def current_interface_counters() -> tuple[str, int, int]:
    interface = command("sh", "-c", "ip -o -4 route show default | awk 'NR==1 {print $5}'")
    if not interface:
        raise RuntimeError("default network interface is unavailable")
    for line in Path("/proc/net/dev").read_text(encoding="utf-8").splitlines():
        if line.strip().startswith(f"{interface}:"):
            fields = line.split(":", 1)[1].split()
            return interface, int(fields[0]), int(fields[8])
    raise RuntimeError(f"network counters are unavailable for {interface}")


def collect_metrics() -> dict:
    load_1m, load_5m, load_15m, *_ = open("/proc/loadavg", encoding="utf-8").read().split()
    memory_line = next(line for line in command("free").splitlines() if line.startswith("Mem:"))
    _, total_memory, used_memory, *_ = memory_line.split()
    docker_names = command("docker", "ps", "--format", "{{.Names}}").splitlines()
    xui_name = next((name for name in docker_names if "3x-ui" in name), "")
    interface, rx, tx = current_interface_counters()
    traffic = {
        "vnstat_month_total": update_traffic_total(
            Path(os.environ.get("TRAFFIC_STATE_PATH", "/opt/homestream/status-reporter/traffic-state.json")), interface, rx, tx
        )
    }
    cpu_idle = command("sh", "-c", "LC_ALL=C top -bn1 | awk '/Cpu\\(s\\)/ {for (i=1;i<=NF;i++) if ($i ~ /^id/) {gsub(/,/, \".\", $(i-1)); print $(i-1); exit}}'")
    return {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "hostname": command("hostname", "-s"),
        "uptime": command("uptime", "-p"),
        "load_1m": float(load_1m),
        "load_5m": float(load_5m),
        "load_15m": float(load_15m),
        "cpu_usage_percent": round(100 - float(cpu_idle or 100), 1),
        "memory_used_percent": round(int(used_memory) * 100 / int(total_memory), 1),
        "disk_used_percent": int(command("sh", "-c", "df -P / | awk 'NR==2 {gsub(/%/, \"\", $5); print $5}'") or 0),
        "docker_running": len(docker_names),
        "docker_unhealthy": len(command("docker", "ps", "--filter", "health=unhealthy", "-q").splitlines()),
        "xui_status": docker_state(xui_name) if xui_name else "unavailable",
        **traffic,
    }


def send_report(url: str, key: bytes, metrics: dict) -> None:
    body = json.dumps(metrics, sort_keys=True, separators=(",", ":")).encode()
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    signature = hmac.new(key, timestamp.encode() + b"\n" + body, hashlib.sha256).hexdigest()
    request = Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-HomeStream-Node": NODE_ID,
            "X-HomeStream-Timestamp": timestamp,
            "X-HomeStream-Signature": signature,
        },
    )
    with urlopen(request, timeout=15) as response:
        if response.status != 204:
            raise RuntimeError(f"unexpected report response: {response.status}")


if __name__ == "__main__":
    report_url = os.environ["REPORT_URL"]
    report_key = os.environ["REPORT_KEY"].encode()
    if len(report_key) < 32:
        raise SystemExit("report key is too short")
    send_report(report_url, report_key, collect_metrics())
