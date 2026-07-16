#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

for file in \
  scripts/bwg-phase7.2-config-generator.sh \
  caddy/phase7.2.Caddyfile \
  docker/phase7.2-reverse-proxy.compose.yml \
  generator/Dockerfile \
  generator/config_generator.py \
  generator/requirements.txt; do
  [[ -s "$root/$file" ]] || { echo "missing required artifact: $file" >&2; exit 1; }
done

grep -Fq 'openssl rand -hex 32' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'install -m 0600' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'config-generator' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'subClashEnable' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'docker restart 3x-ui' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq '127.0.0.1:3011' "$root/caddy/phase7.2.Caddyfile"
grep -Fq '__CONFIG_GENERATOR_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'handle_path __CONFIG_GENERATOR_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq '__IPHONE_SLIM_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'handle @iphone_slim' "$root/caddy/phase7.2.Caddyfile"
grep -Fq '__IOS_TEMPLATE_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'templates/nextin-ios-template.yaml' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'templates/nextin-iphone-us-hk.yaml' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'IPHONE_SLIM_PATH' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'ios-template.yaml' "$root/docker/phase7.2-reverse-proxy.compose.yml"
grep -Fq -- '--ios-slim-template' "$root/docker/phase7.2-reverse-proxy.compose.yml"
[[ -s "$root/templates/nextin-ios-template.yaml" ]]
grep -Fq 'network_mode: host' "$root/docker/phase7.2-reverse-proxy.compose.yml"

printf 'phase7_2_config_generator_artifacts_ok\n'
