#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATUS_CONFIG=/opt/docker/configs/status
STATUS_DATA=/opt/docker/data/status
STATUS_BACKUPS=/opt/docker/backups/status
STATUS_SERVER=/usr/local/sbin/bwg-status-summary-server.py
STATUS_UNIT=/etc/systemd/system/bwg-status-summary.service
KEY_FILE="$STATUS_CONFIG/hk-status-report.env"
STACK=/opt/docker/stacks/reverse-proxy
GENERATOR=/opt/docker/configs/config-generator
REVERSE_PROXY=/opt/docker/configs/reverse-proxy
CADDYFILE="$REVERSE_PROXY/Caddyfile"

for file in status/__init__.py status/status_server.py caddy/phase7.2.Caddyfile; do
  [[ -s "$SOURCE_DIR/$file" ]] || { echo "Missing deployment source: $file" >&2; exit 1; }
done
[[ -s /usr/local/sbin/bwg-status-summary.sh ]] || { echo 'Missing US summary collector.' >&2; exit 1; }
[[ -s "$GENERATOR/runtime.env" ]] || { echo 'Missing config-generator runtime environment.' >&2; exit 1; }
[[ -s "$STACK/.env" ]] || { echo 'Missing reverse-proxy runtime environment.' >&2; exit 1; }

install -d -o root -g root -m 0750 "$STATUS_CONFIG" "$STATUS_DATA" "$STATUS_BACKUPS" "$REVERSE_PROXY"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$STATUS_BACKUPS/$stamp-hk-dashboard"
install -d -o root -g root -m 0700 "$backup"
for path in "$STATUS_SERVER" "$STATUS_UNIT" "$CADDYFILE" "$KEY_FILE" "$STATUS_DATA/hk-report.json"; do
  [[ ! -e "$path" ]] || cp -a "$path" "$backup/$(basename "$path").before"
done

install -m 0644 -o root -g root "$SOURCE_DIR/status/__init__.py" "$STATUS_CONFIG/__init__.py"
install -m 0644 -o root -g root "$SOURCE_DIR/status/status_server.py" "$STATUS_CONFIG/status_server.py"
if [[ ! -s "$KEY_FILE" ]]; then
  printf 'HK_REPORT_KEY=%s\n' "$(openssl rand -hex 32)" | install -m 0600 -o root -g root /dev/stdin "$KEY_FILE"
fi
chmod 0600 "$KEY_FILE"

cat >"$STATUS_SERVER" <<'PY'
#!/usr/bin/env python3
import sys
sys.path.insert(0, '/opt/docker/configs/status')
from status_server import StatusState, command_summary, create_server

key_line = open('/opt/docker/configs/status/hk-status-report.env', encoding='utf-8').read().strip()
key = key_line.split('=', 1)[1].encode() if key_line.startswith('HK_REPORT_KEY=') else key_line.encode()
create_server(
    StatusState('/opt/docker/data/status/hk-report.json', key),
    lambda: command_summary('/usr/local/sbin/bwg-status-summary.sh'),
    3010,
).serve_forever()
PY
chmod 0750 "$STATUS_SERVER"

cat >"$STATUS_UNIT" <<'UNIT'
[Unit]
Description=HomeStream US and HK status summary
After=network-online.target docker.service
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/sbin/bwg-status-summary-server.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
[Install]
WantedBy=multi-user.target
UNIT

source "$GENERATOR/runtime.env"
[[ "${CONFIG_GENERATOR_PATH:-}" =~ ^/configs/[0-9a-f]{64}\.yaml$ ]] || { echo 'Invalid config generator path.' >&2; exit 1; }
[[ "${IPHONE_SLIM_PATH:-}" =~ ^/iphone/[0-9a-f]{64}\.yaml$ ]] || { echo 'Invalid iPhone slim path.' >&2; exit 1; }
IOS_TEMPLATE_PATH="/templates/${CONFIG_GENERATOR_PATH#/configs/}"
sed -e "s|__CONFIG_GENERATOR_PATH__|$CONFIG_GENERATOR_PATH|g" \
    -e "s|__IPHONE_SLIM_PATH__|$IPHONE_SLIM_PATH|g" \
    -e "s|__IOS_TEMPLATE_PATH__|$IOS_TEMPLATE_PATH|g" \
    "$SOURCE_DIR/caddy/phase7.2.Caddyfile" | install -m 0640 -o root -g root /dev/stdin "$CADDYFILE"

{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/bwg-status-summary-server.py.before" "$backup/bwg-status-summary-server.py.before" "$STATUS_SERVER"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/bwg-status-summary.service.before" "$backup/bwg-status-summary.service.before" "$STATUS_UNIT"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/Caddyfile.before" "$backup/Caddyfile.before" "$CADDYFILE"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/hk-status-report.env.before" "$backup/hk-status-report.env.before" "$KEY_FILE"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/hk-report.json.before" "$backup/hk-report.json.before" "$STATUS_DATA/hk-report.json"
  printf '%s\n' 'systemctl daemon-reload' 'systemctl restart bwg-status-summary.service' 'cd /opt/docker/stacks/reverse-proxy' 'docker compose up -d --force-recreate caddy'
} | install -m 0700 -o root -g root /dev/stdin "$backup/restore.sh"

source "$STACK/.env"
docker run --rm -v "$CADDYFILE:/etc/caddy/Caddyfile:ro" -v /opt/docker/configs/custom-rules/custom-rules-auth.caddy:/etc/caddy/custom-rules-auth.caddy:ro "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl daemon-reload
systemctl restart bwg-status-summary.service
healthy=false
for attempt in $(seq 1 20); do
  if curl --fail --silent --show-error http://127.0.0.1:3010/api/server-summary >/dev/null; then
    healthy=true
    break
  fi
  sleep 1
done
[[ "$healthy" == true ]] || { echo 'US status service did not become healthy.' >&2; exit 1; }
docker compose --project-directory "$STACK" up -d --force-recreate caddy
printf 'US HK status dashboard deployed. Key file: %s\nRollback: %s/restore.sh\n' "$KEY_FILE" "$backup"
