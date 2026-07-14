#!/usr/bin/env bash
# Read-only host metrics collector for Phase 6.  It accepts no arguments.
set -Eeuo pipefail

json_string() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
safe() { "$@" 2>/dev/null || true; }
state() { docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || printf 'unavailable'; }

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hostname=$(hostname -s | json_string)
uptime=$(uptime -p 2>/dev/null | json_string)
read -r load_1m load_5m load_15m _ < /proc/loadavg
cpu_usage_percent=$(LC_ALL=C top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {gsub(/,/, "."); for (i=1;i<=NF;i++) if ($i ~ /^id\./) {printf "%.1f", 100-$(i-1); exit}}' || printf '0')
memory_used_percent=$(free | awk '/Mem:/ {printf "%.1f", $3*100/$2}')
disk_used_percent=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
docker_running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
docker_unhealthy=$(docker ps --filter health=unhealthy -q 2>/dev/null | wc -l | tr -d ' ')
caddy_status=$(state bwg-subscription-proxy | json_string)
xui_status=$(state 3x-ui | json_string)

subscription_path=$(python3 - <<'PY'
import sqlite3
try:
    conn = sqlite3.connect('file:/opt/docker/data/3x-ui/x-ui.db?mode=ro', uri=True)
    rows = conn.execute('select sub_id from clients where enable = 1 and sub_id is not null and sub_id != ""').fetchall()
    if len(rows) == 1:
        print('/sub/' + rows[0][0])
except Exception:
    pass
PY
)
if [[ -n "$subscription_path" ]]; then
  subscription_http_status=$(curl --max-time 8 -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:2096${subscription_path}" || printf '000')
else
  subscription_http_status='unavailable'
fi

certificate_expiry_days='unavailable'
cert_end=$(timeout 8 openssl s_client -connect status.jijunyang.com:443 -servername status.jijunyang.com </dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2- || true)
if [[ -n "$cert_end" ]]; then
  cert_end_epoch=$(date -u -d "$cert_end" +%s 2>/dev/null || true)
  if [[ -n "$cert_end_epoch" ]]; then
    certificate_expiry_days=$(( (cert_end_epoch - $(date -u +%s)) / 86400 ))
  fi
fi

read -r vnstat_month_rx vnstat_month_tx vnstat_month_total < <(vnstat --json m 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); x=next((i for i in d.get("interfaces",[]) if i.get("name")=="eth0"),{}); m=(x.get("traffic",{}).get("month") or [{}])[-1]; rx=int(m.get("rx",0)); tx=int(m.get("tx",0)); print(rx,tx,rx+tx)' 2>/dev/null || printf '0 0 0')
last_backup_time=$(find /opt/docker/backups -mindepth 1 -maxdepth 2 -type d -printf '%TY-%Tm-%TdT%TH:%TM:%TZ\n' 2>/dev/null | sort | tail -n1 || true)
[[ -n "$last_backup_time" ]] || last_backup_time='unavailable'

cat <<JSON
{"timestamp":"$timestamp","hostname":$hostname,"uptime":$uptime,"load_1m":$load_1m,"load_5m":$load_5m,"load_15m":$load_15m,"cpu_usage_percent":$cpu_usage_percent,"memory_used_percent":$memory_used_percent,"disk_used_percent":$disk_used_percent,"docker_running":$docker_running,"docker_unhealthy":$docker_unhealthy,"caddy_status":$caddy_status,"xui_status":$xui_status,"subscription_http_status":"$subscription_http_status","certificate_expiry_days":"$certificate_expiry_days","vnstat_month_rx":$vnstat_month_rx,"vnstat_month_tx":$vnstat_month_tx,"vnstat_month_total":$vnstat_month_total,"last_backup_time":"$last_backup_time"}
JSON
