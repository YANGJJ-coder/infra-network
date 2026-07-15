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

for file in \
  scripts/bwg-phase8-candidate-subscription.sh \
  caddy/candidate.Caddyfile.snippet \
  docker/candidate-generator.compose.yml; do
  [[ -s "$root/$file" ]] || { echo "missing candidate artifact: $file" >&2; exit 1; }
done

grep -Fq 'openssl rand -hex 32' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'install -m 0600' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'config-generator' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'subClashEnable' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'docker restart 3x-ui' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq '127.0.0.1:3011' "$root/caddy/phase7.2.Caddyfile"
grep -Fq '__CONFIG_GENERATOR_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'handle_path __CONFIG_GENERATOR_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq '__IOS_TEMPLATE_PATH__' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'templates/nextin-ios-template.yaml' "$root/scripts/bwg-phase7.2-config-generator.sh"
grep -Fq 'ios-template.yaml' "$root/docker/phase7.2-reverse-proxy.compose.yml"
[[ -s "$root/templates/nextin-ios-template.yaml" ]]
grep -Fq 'network_mode: host' "$root/docker/phase7.2-reverse-proxy.compose.yml"
grep -Fq '__CANDIDATE_PATH__' "$root/caddy/candidate.Caddyfile.snippet"
grep -Fq '127.0.0.1:3012' "$root/caddy/candidate.Caddyfile.snippet"
grep -Fq 'handle_path __CANDIDATE_PATH__' "$root/caddy/candidate.Caddyfile.snippet"
grep -Fq 'candidate-generator' "$root/docker/candidate-generator.compose.yml"
grep -Fq -- '--candidate-groups' "$root/docker/candidate-generator.compose.yml"
grep -Fq 'additional-proxies.yaml' "$root/docker/candidate-generator.compose.yml"
grep -Fq 'openssl rand -hex 32' "$root/scripts/bwg-phase8-candidate-subscription.sh"
grep -Fq 'caddy reload' "$root/scripts/bwg-phase8-candidate-subscription.sh"
grep -Fq -- '--address 127.0.0.1:2019' "$root/scripts/bwg-phase8-candidate-subscription.sh"
grep -Fq 'candidate-runtime.env' "$root/scripts/bwg-phase8-candidate-subscription.sh"

printf 'phase7_2_config_generator_artifacts_ok\n'
