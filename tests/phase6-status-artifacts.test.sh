#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

for file in \
  docker/phase6-status.compose.yml \
  caddy/phase6.Caddyfile \
  scripts/bwg-phase6-status-dashboard.sh \
  scripts/bwg-status-summary.sh \
  docs/Phase6-Status-Dashboard.md; do
  [[ -s "$root/$file" ]] || { echo "missing required artifact: $file" >&2; exit 1; }
done

grep -Fq '127.0.0.1:3001:3001' "$root/docker/phase6-status.compose.yml"
grep -Fq "('127.0.0.1',3010)" "$root/scripts/bwg-phase6-status-dashboard.sh"
grep -Fq 'restart: unless-stopped' "$root/docker/phase6-status.compose.yml"
grep -Fq 'status.jijunyang.com' "$root/caddy/phase6.Caddyfile"
grep -Fq '/api/server-summary' "$root/caddy/phase6.Caddyfile"
grep -Fq '127.0.0.1:3001' "$root/scripts/bwg-phase6-status-dashboard.sh"
grep -Fq 'vnstat_month_total' "$root/scripts/bwg-status-summary.sh"
grep -Fq '不提供写操作' "$root/docs/Phase6-Status-Dashboard.md"
grep -Fq 'if ($i ~ /^id\./)' "$root/scripts/bwg-status-summary.sh"
grep -Fq 'sqlite3.connect' "$root/scripts/bwg-status-summary.sh"
grep -Fq 'date -u -d "$cert_end" +%s' "$root/scripts/bwg-status-summary.sh"
! grep -Fq 'sed -i ' "$root/scripts/bwg-phase6-status-dashboard.sh"
grep -Fq 'docker compose --project-directory "$CADDY_STACK" up -d --force-recreate' "$root/scripts/bwg-phase6-status-dashboard.sh"
