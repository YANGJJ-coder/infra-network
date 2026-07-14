#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
config="$root/templates/mihomo-smart-routing.yaml"

provider_url() {
  ruby -ryaml -e 'puts YAML.load_file(ARGV.fetch(0)).fetch("rule-providers").fetch(ARGV.fetch(1)).fetch("url")' "$config" "$1"
}

assert_route() {
  local provider=$1 action=$2 target=$3 pattern=$4
  local line url payload
  line=$(rg -n --fixed-strings -- "- RULE-SET,${provider},${action}" "$config" | cut -d: -f1)
  [[ -n "$line" ]] || { echo "missing ${action} route for ${provider}" >&2; exit 1; }
  url=$(provider_url "$provider")
  payload=$(mktemp)
  curl -fsSL --max-time 20 "$url" -o "$payload"
  rg -qi -- "$pattern" "$payload" || {
    rm -f "$payload"
    echo "upstream ${provider} no longer contains ${target}" >&2
    exit 1
  }
  rm -f "$payload"
  printf '%s -> %s (%s, rule line %s)\n' "$target" "$action" "$provider" "$line"
}

assert_route baidu DIRECT baidu.com 'baidu\.com'
assert_route tencent DIRECT qq.com 'qq\.com'
assert_route jd DIRECT jd.com 'jd\.com'
assert_route alibaba DIRECT taobao.com 'taobao\.com'
assert_route cn DIRECT wecom.work 'wecom\.work'
assert_route cn DIRECT gitcode.com 'gitcode\.com'
assert_route openai PROXY chatgpt.com 'chatgpt\.com'
assert_route openai PROXY api.openai.com 'openai\.com'
assert_route github PROXY github.com 'github\.com'
assert_route youtube PROXY youtube.com 'youtube\.com'
assert_route netflix PROXY netflix.com 'netflix\.com'

apple_tv_line=$(rg -n --fixed-strings -- '- RULE-SET,apple-tvplus,PROXY' "$config" | cut -d: -f1)
apple_cn_line=$(rg -n --fixed-strings -- '- RULE-SET,apple-cn,DIRECT' "$config" | cut -d: -f1)
[[ "$apple_tv_line" -lt "$apple_cn_line" ]] || {
  echo 'Apple TV+ proxy rule must precede Apple China direct rule' >&2
  exit 1
}
printf 'apple-tvplus precedence -> PROXY before Apple China DIRECT\n'
