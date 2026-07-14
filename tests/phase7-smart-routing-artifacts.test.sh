#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

for file in \
  templates/nextin-smart-routing.yaml \
  templates/mihomo-smart-routing.yaml \
  templates/stash-smart-routing.yaml \
  templates/shadowrocket-smart-routing.conf \
  docs/SmartRouting.md \
  docs/RuleSets.md \
  docs/DNS.md; do
  [[ -s "$root/$file" ]] || { echo "missing required artifact: $file" >&2; exit 1; }
done

for file in \
  templates/nextin-smart-routing.yaml \
  templates/mihomo-smart-routing.yaml \
  templates/stash-smart-routing.yaml; do
  ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$root/$file"
  grep -Fq 'mode: rule' "$root/$file"
  grep -Fq 'RULE-SET,ads,REJECT' "$root/$file"
  grep -Fq 'RULE-SET,openai,PROXY' "$root/$file"
  grep -Fq 'RULE-SET,apple-tvplus,PROXY' "$root/$file"
  grep -Fq 'RULE-SET,cn,DIRECT' "$root/$file"
  grep -Fq 'GEOIP,CN,DIRECT,no-resolve' "$root/$file"
  grep -Fq 'MATCH,PROXY' "$root/$file"
  grep -Fq 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/' "$root/$file"
done

grep -Fq 'enhanced-mode: fake-ip' "$root/templates/nextin-smart-routing.yaml"
grep -Fq 'enhanced-mode: fake-ip' "$root/templates/mihomo-smart-routing.yaml"
grep -Fq 'dns-server = https://doh.pub/dns-query, https://dns.alidns.com/dns-query, https://cloudflare-dns.com/dns-query, https://dns.google/dns-query' "$root/templates/shadowrocket-smart-routing.conf"
grep -Fq 'RULE-SET,https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/AppleTV/AppleTV.list,PROXY' "$root/templates/shadowrocket-smart-routing.conf"
grep -Fq 'FINAL,PROXY' "$root/templates/shadowrocket-smart-routing.conf"

for domain in baidu qq jd taobao; do
  grep -Fq "$domain" "$root/docs/SmartRouting.md"
done
for domain in chatgpt openai github youtube netflix; do
  grep -Fq "$domain" "$root/docs/SmartRouting.md"
done

grep -Fq '不修改服务器' "$root/docs/SmartRouting.md"
grep -Fq 'MetaCubeX/meta-rules-dat' "$root/docs/RuleSets.md"
grep -Fq 'Remote DNS' "$root/docs/DNS.md"

# All remote rule URLs are live at validation time. The local profile keeps only
# these upstream references and never copies or maintains their domain payload.
while IFS= read -r url; do
  curl -fsSIL --max-time 20 "$url" >/dev/null
done < <(rg -o --no-filename 'https://raw\.githubusercontent\.com/[^, }\"]+' \
  "$root/templates/nextin-smart-routing.yaml" \
  "$root/templates/mihomo-smart-routing.yaml" \
  "$root/templates/stash-smart-routing.yaml" \
  "$root/templates/shadowrocket-smart-routing.conf" | sort -u)
