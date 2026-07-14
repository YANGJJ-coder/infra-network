#!/usr/bin/env bash
set -Eeuo pipefail

STACK=/opt/docker/stacks/reverse-proxy
CONFIG=/opt/docker/configs/reverse-proxy
DATA=/opt/docker/data/reverse-proxy
LOG=/opt/docker/logs/reverse-proxy
BACKUPS=/opt/docker/backups/reverse-proxy
DOMAIN=sub.jijunyang.com
IMAGE='caddy:2.10.2-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d'

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
for d in "$STACK" "$CONFIG" "$DATA" "$LOG" "$BACKUPS"; do
  install -d -o root -g root -m 0750 "$d"
done

dns=$(dig +short @1.1.1.1 "$DOMAIN" A | sort -u)
[[ "$dns" == '80.251.216.245' ]] || { echo "DNS validation failed: ${dns:-empty}" >&2; exit 1; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/$stamp"
install -d -o root -g root -m 0700 "$backup"
for file in "$STACK/compose.yml" "$STACK/.env" "$CONFIG/Caddyfile" "$STACK/README.md"; do
  [[ ! -e "$file" ]] || cp -a "$file" "$backup/$(basename "$file").before"
done

printf 'CADDY_IMAGE=%s\n' "$IMAGE" | install -m 0600 -o root -g root /dev/stdin "$STACK/.env"
install -m 0640 -o root -g root /tmp/phase5-reverse-proxy.compose.yml "$STACK/compose.yml"
install -m 0640 -o root -g root /tmp/phase5-Caddyfile "$CONFIG/Caddyfile"
printf '%s\n' '# 3X-UI HTTPS subscription reverse proxy' '' 'Only /sub/* is published. The 3X-UI panel remains loopback-only.' | install -m 0640 -o root -g root /dev/stdin "$STACK/README.md"

cat > "$backup/restore.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$STACK"
docker compose down || true
for file in compose.yml .env; do
  if [[ -e "$backup/\$file.before" ]]; then cp -a "$backup/\$file.before" "$STACK/\$file"; else rm -f "$STACK/\$file"; fi
done
if [[ -e "$backup/Caddyfile.before" ]]; then cp -a "$backup/Caddyfile.before" "$CONFIG/Caddyfile"; else rm -f "$CONFIG/Caddyfile"; fi
ufw delete allow 80/tcp || true
ufw delete allow 443/tcp || true
EOF
chmod 0700 "$backup/restore.sh"

docker run --rm -v "$CONFIG/Caddyfile:/etc/caddy/Caddyfile:ro" "$IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
cd "$STACK"
docker compose config
docker compose down
docker compose up -d
docker compose ps
