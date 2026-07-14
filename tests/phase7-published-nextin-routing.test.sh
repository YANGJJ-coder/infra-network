#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
template="$root/templates/nextin-smart-routing.yaml"

ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$template"
grep -Fq 'mode: rule' "$template"
grep -Fq 'RULE-SET,openai,PROXY' "$template"
grep -Fq 'RULE-SET,baidu,DIRECT' "$template"
grep -Fq 'RULE-SET,netflix,PROXY' "$template"
! grep -Fq 'subscription-template' "$template"
! grep -Fq 'x-nextin:' "$template"

printf 'nextin_runtime_template_ok\n'
