#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy only the candidate generator.  The existing formal generator and its
# /sub/<formal-id> route are intentionally neither copied nor recreated.
STACK=/opt/docker/stacks/candidate-generator
CONFIG=/opt/docker/configs/candidate-generator
PROXY_CONFIG=/opt/docker/configs/reverse-proxy
BACKUPS=/opt/docker/backups/candidate-generator
DOMAIN=sub.jijunyang.com
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_ADDITIONAL="$SOURCE_DIR/runtime/additional-proxies.yaml"
RUNTIME_ENV="$CONFIG/candidate-runtime.env"

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
for file in generator/config_generator.py generator/requirements.txt generator/Dockerfile templates/nextin-smart-routing.yaml docker/candidate-generator.compose.yml caddy/candidate.Caddyfile.snippet; do
  [[ -s "$SOURCE_DIR/$file" ]] || { echo "Missing deployment source: $file" >&2; exit 1; }
done
[[ -s "$RUNTIME_ADDITIONAL" ]] || { echo "Missing candidate runtime file: $RUNTIME_ADDITIONAL" >&2; exit 1; }
[[ -s "$PROXY_CONFIG/Caddyfile" ]] || { echo 'Missing active Caddyfile.' >&2; exit 1; }
docker inspect bwg-subscription-proxy >/dev/null
CADDY_IMAGE=$(docker inspect --format '{{.Config.Image}}' bwg-subscription-proxy)

install -d -o root -g root -m 0750 "$STACK" "$CONFIG" "$BACKUPS"
if [[ ! -s "$RUNTIME_ENV" ]]; then
  printf 'CANDIDATE_PATH=/sub/candidate/%s\n' "$(openssl rand -hex 32)" | install -m 0600 -o root -g root /dev/stdin "$RUNTIME_ENV"
fi
source "$RUNTIME_ENV"
[[ "$CANDIDATE_PATH" =~ ^/sub/candidate/[0-9a-f]{64}$ ]] || { echo 'Invalid candidate path.' >&2; exit 1; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/$stamp-phase8-candidate-subscription"
install -d -o root -g root -m 0700 "$backup"
cp -a "$PROXY_CONFIG/Caddyfile" "$backup/Caddyfile.before"
[[ ! -e "$STACK/compose.yml" ]] || cp -a "$STACK/compose.yml" "$backup/compose.yml.before"
[[ ! -e "$CONFIG" ]] || cp -a "$CONFIG" "$backup/config.before"

install -m 0644 -o root -g root "$SOURCE_DIR/generator/config_generator.py" "$CONFIG/config_generator.py"
install -m 0644 -o root -g root "$SOURCE_DIR/generator/requirements.txt" "$CONFIG/requirements.txt"
install -m 0644 -o root -g root "$SOURCE_DIR/generator/Dockerfile" "$CONFIG/Dockerfile"
install -m 0640 -o root -g root "$SOURCE_DIR/templates/nextin-smart-routing.yaml" "$CONFIG/nextin-runtime-template.yaml"
install -m 0600 -o root -g root "$RUNTIME_ADDITIONAL" "$CONFIG/additional-proxies.yaml"
install -m 0640 -o root -g root "$SOURCE_DIR/docker/candidate-generator.compose.yml" "$STACK/compose.yml"

snippet="$backup/candidate.Caddyfile.snippet"
sed "s|__CANDIDATE_PATH__|$CANDIDATE_PATH|g" "$SOURCE_DIR/caddy/candidate.Caddyfile.snippet" | install -m 0600 -o root -g root /dev/stdin "$snippet"
grep -Fq '# HomeStream Candidate Subscription' "$PROXY_CONFIG/Caddyfile" && { echo 'Candidate route already installed; use its rollback first.' >&2; exit 1; }
awk -v snippet="$snippet" '
  BEGIN { while ((getline line < snippet) > 0) block = block line "\n"; close(snippet) }
  /^[[:space:]]*@subscription path \/sub\/\*/ && !inserted { print "    # HomeStream Candidate Subscription"; printf "%s", block; inserted = 1 }
  { print }
  END { if (!inserted) exit 1 }
' "$backup/Caddyfile.before" | install -m 0640 -o root -g root /dev/stdin "$PROXY_CONFIG/Caddyfile"

docker run --rm -v "$PROXY_CONFIG/Caddyfile:/etc/caddy/Caddyfile:ro" "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
cd "$STACK"
docker compose config >/dev/null
docker compose up -d --build --force-recreate
# Caddyfile is a single-file bind mount.  Reload through the host-networked
# admin API so Caddy reads the current host file instead of its original inode.
docker run --rm --network host -v "$PROXY_CONFIG/Caddyfile:/etc/caddy/Caddyfile:ro" "$CADDY_IMAGE" caddy reload --address 127.0.0.1:2019 --config /etc/caddy/Caddyfile --adapter caddyfile

cat > "$backup/restore.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
docker compose -f "$STACK/compose.yml" down
cp -a "$backup/Caddyfile.before" "$PROXY_CONFIG/Caddyfile"
docker run --rm --network host -v "$PROXY_CONFIG/Caddyfile:/etc/caddy/Caddyfile:ro" "$CADDY_IMAGE" caddy reload --address 127.0.0.1:2019 --config /etc/caddy/Caddyfile --adapter caddyfile
EOF
chmod 0700 "$backup/restore.sh"

printf 'Candidate subscription URL: https://%s%s\nRollback: %s/restore.sh\n' "$DOMAIN" "$CANDIDATE_PATH" "$backup"
