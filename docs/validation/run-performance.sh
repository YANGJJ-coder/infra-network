#!/usr/bin/env bash
# 客户端性能采样。请在已连接当前 VLESS 节点且已启用 TUN 或系统代理的设备上运行。
# 用法：./run-performance.sh [采样次数]，默认 3 次。
set -euo pipefail

samples="${1:-3}"
if ! [[ "$samples" =~ ^[1-9][0-9]*$ ]]; then
  echo "采样次数必须为正整数" >&2
  exit 2
fi

targets=(
  "OpenAI API|https://api.openai.com"
  "GitHub|https://github.com"
  "GitHub API|https://api.github.com"
  "Cloudflare DNS|https://1.1.1.1"
  "Cloudflare|https://cloudflare.com"
  "Google|https://google.com"
)

printf '性能采样开始：%s；样本数：%s\n' "$(date -Iseconds)" "$samples"
printf '请确认本机流量已通过 VLESS；本脚本不改变系统或服务器配置。\n\n'

for item in "${targets[@]}"; do
  name="${item%%|*}"
  url="${item#*|}"
  printf '== %s (%s) ==\n' "$name" "$url"
  totals="0 0 0 0 0"
  for ((n=1; n<=samples; n++)); do
    line="$(curl --connect-timeout 10 --max-time 30 -o /dev/null -s -w '%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}' "$url" || true)"
    read -r code dns tcp tls ttfb total <<< "$line"
    if [[ -z "${total:-}" ]]; then
      printf 'sample=%s curl_failed\n' "$n"
      continue
    fi
    printf 'sample=%s code=%s DNS=%ss TCP=%ss TLS=%ss TTFB=%ss TOTAL=%ss\n' "$n" "$code" "$dns" "$tcp" "$tls" "$ttfb" "$total"
    totals="$(awk -v a="$totals" -v b="$dns $tcp $tls $ttfb $total" 'BEGIN {split(a,x," "); split(b,y," "); for(i=1;i<=5;i++) printf "%0.6f%s", x[i]+y[i], (i==5?"":" ")}')"
  done
  awk -v v="$totals" -v n="$samples" 'BEGIN {split(v,x," "); printf "平均值 DNS=%.6fs TCP=%.6fs TLS=%.6fs TTFB=%.6fs TOTAL=%.6fs\n\n", x[1]/n,x[2]/n,x[3]/n,x[4]/n,x[5]/n}'
done
