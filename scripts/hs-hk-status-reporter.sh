#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ $# -eq 2 ]] || { echo 'Usage: hs-hk-status-reporter.sh <source-dir> <key-file>' >&2; exit 1; }

SOURCE_DIR=$(cd "$1" && pwd)
KEY_FILE=$2
ROOT=/opt/homestream/status-reporter
ENV_FILE="$ROOT/report.env"

[[ -s "$SOURCE_DIR/status/hk_reporter.py" ]] || { echo 'Missing HK reporter source.' >&2; exit 1; }
[[ -s "$KEY_FILE" ]] || { echo 'Missing report key file.' >&2; exit 1; }
REPORT_KEY=$(tr -d '\r\n' < "$KEY_FILE")
[[ ${#REPORT_KEY} -ge 32 ]] || { echo 'Report key is too short.' >&2; exit 1; }

install -d -o root -g root -m 0700 "$ROOT"
install -m 0700 -o root -g root "$SOURCE_DIR/status/hk_reporter.py" "$ROOT/hk_reporter.py"
{
  printf 'REPORT_URL=https://status.jijunyang.com/api/node-reports/hk\n'
  printf 'REPORT_KEY=%s\n' "$REPORT_KEY"
} | install -m 0600 -o root -g root /dev/stdin "$ENV_FILE"

cat >/etc/systemd/system/homestream-hk-status-reporter.service <<'UNIT'
[Unit]
Description=HomeStream HK signed status reporter
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=oneshot
EnvironmentFile=/opt/homestream/status-reporter/report.env
ExecStart=/usr/bin/python3 /opt/homestream/status-reporter/hk_reporter.py
User=root
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/opt/homestream/status-reporter
UNIT

cat >/etc/systemd/system/homestream-hk-status-reporter.timer <<'UNIT'
[Unit]
Description=Run HomeStream HK status reporter every 600 seconds
[Timer]
OnBootSec=2min
OnUnitActiveSec=600
RandomizedDelaySec=30
Persistent=true
Unit=homestream-hk-status-reporter.service
[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl start homestream-hk-status-reporter.service
systemctl enable --now homestream-hk-status-reporter.timer
systemctl is-active --quiet homestream-hk-status-reporter.timer
