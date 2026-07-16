#!/usr/bin/env bash
set -Eeuo pipefail

STACK=/opt/docker/stacks/reverse-proxy
CONFIG=/opt/docker/configs/reverse-proxy
GENERATOR=/opt/docker/configs/config-generator
BACKUPS=/opt/docker/backups/reverse-proxy
DATA=/opt/docker/data/reverse-proxy
LOG=/opt/docker/logs/reverse-proxy
DOMAIN=sub.jijunyang.com
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$GENERATOR/runtime.env"

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
for file in generator/config_generator.py generator/requirements.txt generator/Dockerfile templates/nextin-smart-routing.yaml templates/nextin-ios-template.yaml templates/nextin-iphone-us-hk.yaml caddy/phase7.2.Caddyfile docker/phase7.2-reverse-proxy.compose.yml; do
  [[ -s "$SOURCE_DIR/$file" ]] || { echo "Missing deployment source: $file" >&2; exit 1; }
done
[[ -s /opt/docker/data/3x-ui/x-ui.db ]] || { echo 'Missing 3X-UI database.' >&2; exit 1; }
[[ -s "$GENERATOR/additional-proxies.yaml" ]] || { echo 'Missing managed additional proxy source.' >&2; exit 1; }

install -d -o root -g root -m 0750 "$STACK" "$CONFIG" "$GENERATOR" "$BACKUPS" "$DATA" "$LOG"
if [[ ! -s "$ENV_FILE" ]]; then
  path="/configs/$(openssl rand -hex 32).yaml"
  printf 'CONFIG_GENERATOR_PATH=%s\n' "$path" | install -m 0600 -o root -g root /dev/stdin "$ENV_FILE"
fi
source "$ENV_FILE"
[[ "$CONFIG_GENERATOR_PATH" =~ ^/configs/[0-9a-f]{64}\.yaml$ ]] || { echo 'Invalid config generator path.' >&2; exit 1; }
if [[ -z "${IPHONE_SLIM_PATH:-}" ]]; then
  IPHONE_SLIM_PATH="/iphone/$(openssl rand -hex 32).yaml"
  printf 'IPHONE_SLIM_PATH=%s\n' "$IPHONE_SLIM_PATH" >> "$ENV_FILE"
fi
[[ "$IPHONE_SLIM_PATH" =~ ^/iphone/[0-9a-f]{64}\.yaml$ ]] || { echo 'Invalid iPhone slim path.' >&2; exit 1; }
IOS_TEMPLATE_PATH="/templates/${CONFIG_GENERATOR_PATH#/configs/}"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/$stamp-phase7.2-config-generator"
install -d -o root -g root -m 0700 "$backup"
for file in "$STACK/compose.yml" "$CONFIG/Caddyfile" "$GENERATOR"; do
  [[ ! -e "$file" ]] || cp -a "$file" "$backup/$(basename "$file").before"
done
cp -a /opt/docker/data/3x-ui/x-ui.db "$backup/x-ui.db.before"

python3 - <<'PY'
import sqlite3

path = '/opt/docker/data/3x-ui/x-ui.db'
with sqlite3.connect(path) as connection:
    for key, value in (('subClashEnable', 'true'), ('subClashEnableRouting', 'false')):
        result = connection.execute("update settings set value=? where key=?", (value, key))
        if result.rowcount == 0:
            connection.execute("insert into settings (key, value) values (?, ?)", (key, value))
PY
docker restart 3x-ui >/dev/null
for _ in $(seq 1 20); do
  docker exec 3x-ui /app/x-ui setting -show true >/dev/null 2>&1 && break
  sleep 1
done

install -m 0644 -o root -g root "$SOURCE_DIR/generator/config_generator.py" "$GENERATOR/config_generator.py"
install -m 0644 -o root -g root "$SOURCE_DIR/generator/requirements.txt" "$GENERATOR/requirements.txt"
install -m 0644 -o root -g root "$SOURCE_DIR/generator/Dockerfile" "$GENERATOR/Dockerfile"
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-smart-routing.yaml" "$GENERATOR/nextin-runtime-template.yaml"
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-ios-template.yaml" "$GENERATOR/ios-template.yaml"
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-iphone-us-hk.yaml" "$GENERATOR/iphone-us-hk.yaml"
install -m 0640 -o root -g root "$SOURCE_DIR/docker/phase7.2-reverse-proxy.compose.yml" "$STACK/compose.yml"
sed -e "s|__CONFIG_GENERATOR_PATH__|$CONFIG_GENERATOR_PATH|g" -e "s|__IPHONE_SLIM_PATH__|$IPHONE_SLIM_PATH|g" -e "s|__IOS_TEMPLATE_PATH__|$IOS_TEMPLATE_PATH|g" "$SOURCE_DIR/caddy/phase7.2.Caddyfile" | install -m 0640 -o root -g root /dev/stdin "$CONFIG/Caddyfile"

cat > "$backup/restore.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
cp -a "$backup/compose.yml.before" "$STACK/compose.yml"
cp -a "$backup/Caddyfile.before" "$CONFIG/Caddyfile"
cp -a "$backup/x-ui.db.before" /opt/docker/data/3x-ui/x-ui.db
docker restart 3x-ui >/dev/null
rm -rf "$GENERATOR"
[[ ! -e "$backup/config-generator.before" ]] || cp -a "$backup/config-generator.before" "$GENERATOR"
cd "$STACK"
docker compose up -d --force-recreate
EOF
chmod 0700 "$backup/restore.sh"

source "$STACK/.env"
docker run --rm -v "$CONFIG/Caddyfile:/etc/caddy/Caddyfile:ro" "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
cd "$STACK"
docker compose config >/dev/null
docker compose up -d --build --force-recreate
docker compose ps
printf 'Generated subscription URL: https://%s%s\niPhone slim URL: https://%s%s\niPhone template URL: https://%s%s\nRollback: %s/restore.sh\n' "$DOMAIN" "$CONFIG_GENERATOR_PATH" "$DOMAIN" "$IPHONE_SLIM_PATH" "$DOMAIN" "$IOS_TEMPLATE_PATH" "$backup"
