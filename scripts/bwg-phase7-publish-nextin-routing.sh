#!/usr/bin/env bash
set -Eeuo pipefail

STACK=/opt/docker/stacks/reverse-proxy
CONFIG=/opt/docker/configs/reverse-proxy
STATIC="$CONFIG/static/configs"
BACKUPS=/opt/docker/backups/reverse-proxy
SOURCE=${1:-/tmp/nextin-smart-routing.yaml}
TARGET="$STATIC/nextin-smart-routing.yaml"
IMAGE='caddy:2.10.2-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d'
DOMAIN=sub.jijunyang.com
URL="https://${DOMAIN}/configs/nextin-smart-routing.yaml"

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -s "$SOURCE" ]] || { echo "Missing routing YAML: $SOURCE" >&2; exit 1; }
[[ -s /tmp/phase5-Caddyfile ]] || { echo 'Missing /tmp/phase5-Caddyfile.' >&2; exit 1; }
[[ -s /tmp/phase5-reverse-proxy.compose.yml ]] || { echo 'Missing /tmp/phase5-reverse-proxy.compose.yml.' >&2; exit 1; }
grep -Fqx 'x-nextin:' "$SOURCE"
grep -Fqx '  mode: subscription-template' "$SOURCE"
grep -Fqx 'mode: rule' "$SOURCE"

docker run --rm -v /tmp/phase5-Caddyfile:/etc/caddy/Caddyfile:ro "$IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose -f /tmp/phase5-reverse-proxy.compose.yml --env-file "$STACK/.env" config >/dev/null

for dir in "$STATIC" "$BACKUPS"; do
  install -d -o root -g root -m 0755 "$dir"
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/$stamp-phase7-configs"
install -d -o root -g root -m 0700 "$backup"
for file in "$STACK/compose.yml" "$CONFIG/Caddyfile" "$TARGET"; do
  [[ ! -e "$file" ]] || cp -a "$file" "$backup/$(basename "$file").before"
done

install -m 0644 -o root -g root "$SOURCE" "$TARGET"
install -m 0640 -o root -g root /tmp/phase5-Caddyfile "$CONFIG/Caddyfile"
install -m 0640 -o root -g root /tmp/phase5-reverse-proxy.compose.yml "$STACK/compose.yml"

cat >"$backup/restore.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
cp -a "$backup/compose.yml.before" "$STACK/compose.yml"
cp -a "$backup/Caddyfile.before" "$CONFIG/Caddyfile"
if [[ -e "$backup/nextin-smart-routing.yaml.before" ]]; then
  cp -a "$backup/nextin-smart-routing.yaml.before" "$TARGET"
else
  rm -f "$TARGET"
fi
cd "$STACK"
docker compose up -d --force-recreate caddy
EOF
chmod 0700 "$backup/restore.sh"

cd "$STACK"
docker compose config >/dev/null
docker compose up -d --force-recreate caddy
docker compose ps caddy

curl -fsSIL --max-time 20 "$URL" | grep -Eqi '^content-type: application/(x-)?yaml'
curl -fsSL --max-time 20 "$URL" | cmp -s "$TARGET" -
curl -fsSI --max-time 20 "https://${DOMAIN}/sub/" >/dev/null || true
printf 'Published %s\nRollback: %s/restore.sh\n' "$URL" "$backup"
