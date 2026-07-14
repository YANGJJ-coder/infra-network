#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ $# -eq 0 ]] || { echo 'This deployment accepts no arguments.' >&2; exit 1; }

STACK=/opt/docker/stacks/status
CONFIG=/opt/docker/configs/status
DATA=/opt/docker/data/status
LOG=/opt/docker/logs/status
BACKUPS=/opt/docker/backups/status
SCRIPTS=/opt/docker/scripts/status
CADDY_STACK=/opt/docker/stacks/reverse-proxy
CADDY_CONFIG=/opt/docker/configs/reverse-proxy/Caddyfile
KUMA_IMAGE='louislam/uptime-kuma:1.23.16@sha256:b4c3a4d186b4612b3a7bbb39c56a634626276615c21871c837a86e4a43d8e047'
DOMAIN=status.jijunyang.com

for d in "$STACK" "$CONFIG" "$DATA" "$LOG" "$BACKUPS" "$SCRIPTS" "$DATA/uptime-kuma"; do
  install -d -o root -g root -m 0750 "$d"
done

[[ $(dig +short "$DOMAIN" A | sort -u) == '80.251.216.245' ]] || { echo 'DNS validation failed; public deployment stopped.' >&2; exit 1; }
docker inspect bwg-subscription-proxy >/dev/null
docker inspect 3x-ui >/dev/null

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/$stamp"
install -d -o root -g root -m 0700 "$backup"
for file in "$STACK/compose.yml" "$STACK/.env" "$STACK/README.md" "$CADDY_CONFIG" /usr/local/sbin/bwg-status-summary.sh /usr/local/sbin/bwg-status-summary-server.py /etc/systemd/system/bwg-status-summary.service; do
  [[ ! -e "$file" ]] || cp -a "$file" "$backup/$(basename "$file").before"
done

install -m 0640 -o root -g root /tmp/phase6-status.compose.yml "$STACK/compose.yml"
printf 'UPTIME_KUMA_IMAGE=%s\n' "$KUMA_IMAGE" | install -m 0600 -o root -g root /dev/stdin "$STACK/.env"
install -m 0750 -o root -g root /tmp/bwg-status-summary.sh /usr/local/sbin/bwg-status-summary.sh
install -m 0750 -o root -g root /tmp/bwg-phase6-status-dashboard.sh "$SCRIPTS/deploy.sh"

cat > /usr/local/sbin/bwg-status-summary-server.py <<'PY'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
from subprocess import run, PIPE
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/api/server-summary':
            self.send_error(404); return
        result = run(['/usr/local/sbin/bwg-status-summary.sh'], stdout=PIPE, stderr=PIPE, text=True, timeout=12)
        body = result.stdout if result.returncode == 0 else '{"error":"summary_unavailable"}\n'
        self.send_response(200 if result.returncode == 0 else 503)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','public, max-age=60')
        self.send_header('Content-Length',str(len(body.encode())))
        self.end_headers(); self.wfile.write(body.encode())
    def log_message(self, *_): pass
HTTPServer(('127.0.0.1',3010), Handler).serve_forever()
PY
chmod 0750 /usr/local/sbin/bwg-status-summary-server.py
cat > /etc/systemd/system/bwg-status-summary.service <<'UNIT'
[Unit]
Description=Phase 6 read-only server status summary
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
systemctl daemon-reload
systemctl enable --now bwg-status-summary.service

rewritten_caddy=$(mktemp)
sed '/^# BEGIN PHASE6 STATUS$/,/^# END PHASE6 STATUS$/d' "$CADDY_CONFIG" > "$rewritten_caddy"
cat "$rewritten_caddy" > "$CADDY_CONFIG"
rm -f "$rewritten_caddy"
{
  printf '\n# BEGIN PHASE6 STATUS\n'
  cat /tmp/phase6-Caddyfile
  printf '# END PHASE6 STATUS\n'
} >> "$CADDY_CONFIG"

docker run --rm -v "$CADDY_CONFIG:/etc/caddy/Caddyfile:ro" caddy:2.10.2-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
cd "$STACK"
docker compose config
docker compose up -d
# The first deployment may have replaced a bind-mounted Caddyfile inode.
# Recreating only the existing reverse-proxy container rebinds the validated
# file without changing its compose definition, UFW, or 3X-UI stack.
docker compose --project-directory "$CADDY_STACK" up -d --force-recreate

cat > "$STACK/README.md" <<'README'
# Phase 6 status dashboard

Uptime Kuma listens only on `127.0.0.1:3001`. The host metrics endpoint listens only on `127.0.0.1:3010`; Caddy publishes it exclusively at `/api/server-summary`.

No Docker socket, write action, proxy configuration, firewall rule, subscription identifier, UUID, or administrator credential is exposed by the public status endpoint.
README

cat > "$SCRIPTS/backup.sh" <<'BACKUP'
#!/usr/bin/env bash
set -Eeuo pipefail
stamp=$(date -u +%Y%m%dT%H%M%SZ)
dest="/opt/docker/backups/status/$stamp"
install -d -m 0700 "$dest"
tar -C /opt/docker -czf "$dest/uptime-kuma-data.tgz" data/status/uptime-kuma
cp -a /opt/docker/stacks/status "$dest/stacks-status"
cp -a /opt/docker/configs/status "$dest/configs-status"
cp -a /opt/docker/configs/reverse-proxy/Caddyfile "$dest/Caddyfile.current"
cp -a /usr/local/sbin/bwg-status-summary.sh /usr/local/sbin/bwg-status-summary-server.py "$dest/"
printf '%s\n' "$dest"
BACKUP
chmod 0700 "$SCRIPTS/backup.sh"

cat > "$backup/restore.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
systemctl disable --now bwg-status-summary.service || true
cd "$STACK" && docker compose down || true
for f in compose.yml .env README.md; do [[ -e "$backup/\$f.before" ]] && cp -a "$backup/\$f.before" "$STACK/\$f" || rm -f "$STACK/\$f"; done
[[ -e "$backup/Caddyfile.before" ]] && cp -a "$backup/Caddyfile.before" "$CADDY_CONFIG"
[[ -e "$backup/bwg-status-summary.sh.before" ]] && cp -a "$backup/bwg-status-summary.sh.before" /usr/local/sbin/bwg-status-summary.sh || rm -f /usr/local/sbin/bwg-status-summary.sh
[[ -e "$backup/bwg-status-summary-server.py.before" ]] && cp -a "$backup/bwg-status-summary-server.py.before" /usr/local/sbin/bwg-status-summary-server.py || rm -f /usr/local/sbin/bwg-status-summary-server.py
[[ -e "$backup/bwg-status-summary.service.before" ]] && cp -a "$backup/bwg-status-summary.service.before" /etc/systemd/system/bwg-status-summary.service || rm -f /etc/systemd/system/bwg-status-summary.service
systemctl daemon-reload
docker exec bwg-subscription-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
EOF
chmod 0700 "$backup/restore.sh"

"$SCRIPTS/backup.sh" >/dev/null
echo "Deployment complete. Initial Uptime Kuma administrator setup is required at https://$DOMAIN/."
