#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

STACK=/opt/docker/stacks/reverse-proxy
REVERSE_PROXY=/opt/docker/configs/reverse-proxy
GENERATOR=/opt/docker/configs/config-generator
CUSTOM_CONFIG=/opt/docker/configs/custom-rules
CUSTOM_DATA=/opt/docker/data/custom-rules
BACKUPS=/opt/docker/backups/custom-rules
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CADDYFILE="$REVERSE_PROXY/Caddyfile"
AUTH_FILE="$CUSTOM_CONFIG/custom-rules-auth.caddy"

for file in \
  generator/config_generator.py generator/requirements.txt generator/Dockerfile \
  custom_rules/__init__.py custom_rules/server.py custom_rules/store.py custom_rules/validation.py custom_rules/Dockerfile \
  templates/nextin-smart-routing.yaml templates/nextin-ios-template.yaml templates/nextin-iphone-us-hk.yaml \
  caddy/phase7.2.Caddyfile docker/phase7.2-reverse-proxy.compose.yml; do
  [[ -s "$SOURCE_DIR/$file" ]] || { echo "Missing deployment source: $file" >&2; exit 1; }
done
[[ -s /opt/docker/data/3x-ui/x-ui.db ]] || { echo 'Missing 3X-UI database.' >&2; exit 1; }
[[ -s "$GENERATOR/additional-proxies.yaml" ]] || { echo 'Missing managed additional proxy source.' >&2; exit 1; }
[[ -s "$GENERATOR/runtime.env" ]] || { echo 'Missing config-generator runtime environment.' >&2; exit 1; }
[[ -s "$STACK/.env" ]] || { echo 'Missing reverse-proxy runtime environment.' >&2; exit 1; }

install -d -o root -g root -m 0750 "$REVERSE_PROXY" "$GENERATOR" "$CUSTOM_CONFIG" "$CUSTOM_DATA" "$BACKUPS"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/$stamp-custom-rules"
install -d -o root -g root -m 0700 "$backup"
[[ ! -e "$STACK/compose.yml" ]] || cp -a "$STACK/compose.yml" "$backup/compose.yml.before"
[[ ! -e "$CADDYFILE" ]] || cp -a "$CADDYFILE" "$backup/Caddyfile.before"
[[ ! -e "$GENERATOR" ]] || cp -a "$GENERATOR" "$backup/config-generator.before"
[[ ! -e "$CUSTOM_CONFIG" ]] || cp -a "$CUSTOM_CONFIG" "$backup/custom-rules-config.before"
[[ ! -e "$CUSTOM_DATA" ]] || cp -a "$CUSTOM_DATA" "$backup/custom-rules-data.before"

install -m 0644 -o root -g root "$SOURCE_DIR/generator/config_generator.py" "$GENERATOR/config_generator.py"
install -m 0644 -o root -g root "$SOURCE_DIR/generator/requirements.txt" "$GENERATOR/requirements.txt"
install -m 0644 -o root -g root "$SOURCE_DIR/generator/Dockerfile" "$GENERATOR/Dockerfile"
rm -rf "$GENERATOR/custom_rules"
install -d -o root -g root -m 0755 "$GENERATOR/custom_rules"
for file in __init__.py server.py store.py validation.py; do
  install -m 0644 -o root -g root "$SOURCE_DIR/custom_rules/$file" "$GENERATOR/custom_rules/$file"
done
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-smart-routing.yaml" "$GENERATOR/nextin-runtime-template.yaml"
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-ios-template.yaml" "$GENERATOR/ios-template.yaml"
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-iphone-us-hk.yaml" "$GENERATOR/iphone-us-hk.yaml"

install -m 0644 -o root -g root "$SOURCE_DIR/custom_rules/Dockerfile" "$CUSTOM_CONFIG/Dockerfile"
for file in __init__.py server.py store.py validation.py; do
  install -m 0644 -o root -g root "$SOURCE_DIR/custom_rules/$file" "$CUSTOM_CONFIG/$file"
done
PYTHONPATH="$SOURCE_DIR" python3 - <<PY
from custom_rules.store import CustomRuleStore
CustomRuleStore("$CUSTOM_DATA/custom-rules.db")
PY
chown root:root "$CUSTOM_DATA/custom-rules.db"
chmod 0640 "$CUSTOM_DATA/custom-rules.db"

initial_password=''
if [[ ! -s "$AUTH_FILE" ]]; then
  initial_password=$(openssl rand -base64 24 | tr -d '\n')
  hash=$(docker exec bwg-subscription-proxy caddy hash-password --plaintext "$initial_password")
  {
    printf 'basic_auth bcrypt {\n'
    printf '    admin %s\n' "$hash"
    printf '}\n'
  } | install -m 0600 -o root -g root /dev/stdin "$AUTH_FILE"
fi

source "$GENERATOR/runtime.env"
[[ "${CONFIG_GENERATOR_PATH:-}" =~ ^/configs/[0-9a-f]{64}\.yaml$ ]] || { echo 'Invalid config generator path.' >&2; exit 1; }
[[ "${IPHONE_SLIM_PATH:-}" =~ ^/iphone/[0-9a-f]{64}\.yaml$ ]] || { echo 'Invalid iPhone slim path.' >&2; exit 1; }
IOS_TEMPLATE_PATH="/templates/${CONFIG_GENERATOR_PATH#/configs/}"
install -m 0640 -o root -g root "$SOURCE_DIR/docker/phase7.2-reverse-proxy.compose.yml" "$STACK/compose.yml"
sed -e "s|__CONFIG_GENERATOR_PATH__|$CONFIG_GENERATOR_PATH|g" \
    -e "s|__IPHONE_SLIM_PATH__|$IPHONE_SLIM_PATH|g" \
    -e "s|__IOS_TEMPLATE_PATH__|$IOS_TEMPLATE_PATH|g" \
    "$SOURCE_DIR/caddy/phase7.2.Caddyfile" | install -m 0640 -o root -g root /dev/stdin "$CADDYFILE"

{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf 'cp -a %q %q\n' "$backup/compose.yml.before" "$STACK/compose.yml"
  printf 'cp -a %q %q\n' "$backup/Caddyfile.before" "$CADDYFILE"
  printf 'rm -rf %q %q %q\n' "$GENERATOR" "$CUSTOM_CONFIG" "$CUSTOM_DATA"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/config-generator.before" "$backup/config-generator.before" "$GENERATOR"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/custom-rules-config.before" "$backup/custom-rules-config.before" "$CUSTOM_CONFIG"
  printf '[[ ! -e %q ]] || cp -a %q %q\n' "$backup/custom-rules-data.before" "$backup/custom-rules-data.before" "$CUSTOM_DATA"
  printf 'cd %q\n' "$STACK"
  printf '%s\n' 'docker compose up -d --force-recreate'
} | install -m 0700 -o root -g root /dev/stdin "$backup/restore.sh"

source "$STACK/.env"
docker run --rm -v "$CADDYFILE:/etc/caddy/Caddyfile:ro" -v "$AUTH_FILE:/etc/caddy/custom-rules-auth.caddy:ro" "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
cd "$STACK"
docker compose config >/dev/null
docker compose up -d --build --force-recreate
healthy=false
for attempt in $(seq 1 20); do
  if curl --fail --silent --show-error http://127.0.0.1:3012/api/v1/rule-types >/dev/null; then
    healthy=true
    break
  fi
  sleep 1
done
[[ "$healthy" == true ]] || { echo 'Custom Rules service did not become healthy.' >&2; exit 1; }
printf 'Custom Rules deployed. URL: https://status.jijunyang.com/manage-status-page/custom-rules/\nRollback: %s/restore.sh\n' "$backup"
if [[ -n "$initial_password" ]]; then
  printf 'Initial Basic Auth username: admin\nInitial Basic Auth password: %s\n' "$initial_password"
fi
