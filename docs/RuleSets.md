# Phase 7：Rule Providers

## 来源与更新

主规则源为 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 的 `meta/geo/geosite/*.yaml`。该项目给 Mihomo 提供规则集，并明确给出 `cn`、广告、GeoIP/GeoSite 的使用示例。Claude 使用 [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) 的 Clash 规则集；Shadowrocket 使用同一项目的原生 `.list` 产物。

四个配置都以 `interval: 86400` 自动刷新。规则数据由上游维护，本项目不维护大规模域名清单。

## 当前配置集合

| 动作 | Rule Provider | 用途 |
|---|---|---|
| REJECT | `category-ads-all` | 成熟广告域名集合 |
| DIRECT | `private`、`cn` | 私网、LAN 和中国域名聚合 |
| DIRECT | `baidu`、`tencent`、`alibaba`、`jd` | 百度、腾讯（QQ/微信）、阿里/淘宝、京东 |
| DIRECT | `feishu`、`dingtalk`、`gitee` | 飞书、钉钉、Gitee |
| DIRECT | `apple-cn`、`microsoft@cn` | Apple 中国、Microsoft 中国 |
| PROXY | `openai`、`claude`、`anthropic` | ChatGPT/OpenAI、Claude/Anthropic |
| PROXY | `google`、`github`、`docker`、`huggingface` | Google/Gemini、GitHub、Docker Hub、HuggingFace |
| PROXY | `youtube`、`netflix`、`disney`、`apple-tvplus`、`primevideo` | 流媒体 |
| PROXY | `reddit`、`twitter`、`telegram` | Reddit、X、Telegram |

Cloudflare AI 仅以两个稳定服务后缀 `ai.cloudflare.com`、`workers.ai` 代理，避免把所有 Cloudflare 托管站点错误地强制代理。企业微信与 GitCode 由 `cn` 聚合集合覆盖；GitCode 另保留单条 `gitcode.com` 显式直连。其余中国服务不以手工域名方式维护。

## 数量快照（2026-07-14）

- Remote Rule Provider：27 个（MetaCubeX 26 个，Claude 1 个）。
- Rule Mode 路由语句：46 条（含 11 条 LAN/私网 CIDR、`GEOIP,CN` 与最终兜底）。
- 上游 YAML `payload` 总项：116,566 条；这个数会随上游自动更新，不是固定承诺。
- Shadowrocket 使用 21 个远程 `RULE-SET`，另有 8 条最小显式域名/GeoIP 规则；其格式不读取 Mihomo YAML，故改用上游原生 `.list`。

## 兼容性选择

Nextin 是 Mihomo 内核，官方文档确认其订阅模板支持完整 Clash/Mihomo YAML；其普通订阅覆写不支持 `GEOSITE`，故交付文件为订阅模板，使用远程 `RULE-SET` 而不是依赖 `GEOSITE`。Stash 官方规则集文档也支持 `domain + yaml` 的远程 Rule Provider，并支持后台静默更新。Shadowrocket 采用原生 `RULE-SET,<URL>,策略`。
