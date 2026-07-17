#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

for file in \
  status/hk_reporter.py \
  status/status_server.py \
  scripts/bwg-hk-status-dashboard.sh \
  scripts/hs-hk-status-reporter.sh; do
  [[ -s "$root/$file" ]] || { echo "missing required artifact: $file" >&2; exit 1; }
done

grep -Fq 'OnUnitActiveSec=600' "$root/scripts/hs-hk-status-reporter.sh"
grep -Fq 'X-HomeStream-Signature' "$root/status/hk_reporter.py"
grep -Fq 'api/node-reports/hk' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'Cache-Control "no-store"' "$root/caddy/phase7.2.Caddyfile"
grep -Fq 'hk-status-report.env' "$root/scripts/bwg-hk-status-dashboard.sh"
grep -Fq 'status/status_server.py' "$root/scripts/bwg-hk-status-dashboard.sh"
grep -Fq 'for attempt in $(seq 1 20)' "$root/scripts/bwg-hk-status-dashboard.sh"
grep -Fq 'docker compose --project-directory "$STACK" up -d --force-recreate caddy' "$root/scripts/bwg-hk-status-dashboard.sh"
grep -Fq 'install -m 0600' "$root/scripts/hs-hk-status-reporter.sh"
grep -Fq '127.0.0.1' "$root/status/status_server.py"
! grep -Fq 'REPORT_KEY=' "$root/status/hk_reporter.py"
! grep -Fq '54917' "$root/scripts/hs-hk-status-reporter.sh"

printf 'hk_status_artifacts_ok\n'
