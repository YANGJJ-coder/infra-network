#!/usr/bin/env python3
"""Collect local HK host metrics and send one authenticated report to US."""

import hashlib
import hmac
import json
import os
import subprocess
from datetime import datetime, timezone
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


def collect_metrics() -> dict:
    load_1m, load_5m, load_15m, *_ = open("/proc/loadavg", encoding="utf-8").read().split()
    memory_line = next(line for line in command("free").splitlines() if line.startswith("Mem:"))
    _, total_memory, used_memory, *_ = memory_line.split()
    docker_names = command("docker", "ps", "--format", "{{.Names}}").splitlines()
    xui_name = next((name for name in docker_names if "3x-ui" in name), "")
    traffic = {"vnstat_month_total": 0}
    try:
        vnstat = json.loads(command("vnstat", "--json", "m"))
        interface = next((item for item in vnstat.get("interfaces", []) if item.get("name") == "eth0"), {})
        month = (interface.get("traffic", {}).get("month") or [{}])[-1]
        traffic["vnstat_month_total"] = int(month.get("rx", 0)) + int(month.get("tx", 0))
    except (json.JSONDecodeError, KeyError, StopIteration, ValueError):
        pass
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
