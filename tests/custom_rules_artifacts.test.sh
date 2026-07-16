#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

for file in \
  custom_rules/server.py \
  custom_rules/store.py \
  custom_rules/validation.py \
  custom_rules/Dockerfile \
  scripts/bwg-custom-rules.sh; do
  [[ -s "$root/$file" ]] || { echo "missing required artifact: $file" >&2; exit 1; }
done

grep -Fq 'bwg-custom-rules' "$root/docker/phase7.2-reverse-proxy.compose.yml"
grep -Fq '127.0.0.1:3012' "$root/caddy/phase7.2.Caddyfile"
grep -Fq '/manage-status-page/custom-rules/' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'custom-rules-auth.caddy' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'basic_auth bcrypt {' "$root/scripts/bwg-custom-rules.sh"
grep -Fq '/opt/docker/data/custom-rules:/var/lib/custom-rules:ro' "$root/docker/phase7.2-reverse-proxy.compose.yml"
grep -Fq -- '--custom-rules-db' "$root/docker/phase7.2-reverse-proxy.compose.yml"
grep -Fq 'caddy validate' "$root/scripts/bwg-custom-rules.sh"
grep -Fq 'restore.sh' "$root/scripts/bwg-custom-rules.sh"
grep -Fq 'for attempt in $(seq 1 20)' "$root/scripts/bwg-custom-rules.sh"
grep -Fq 'sleep 1' "$root/scripts/bwg-custom-rules.sh"

printf 'custom_rules_artifacts_ok\n'
