# Phase 7：Smart Routing（智能分流）

> 本文定义 Personal Network Infrastructure 下 HomeStream 的智能分流设计；当前节点规范名称为 `HS-US-01-Bandwagon`，不改变其既有运维资产标识或运行配置。

## 交付边界

Phase 7.2 起，Nextin/Mihomo/Stash 使用服务端 HomeStream Config Generator 发布的完整 Rule Mode 配置。路由模板保存在仓库中，但客户端不再分别导入节点订阅与规则模板。

- [Nextin 配置](../templates/nextin-smart-routing.yaml)
- [Mihomo 配置](../templates/mihomo-smart-routing.yaml)
- [Stash 配置](../templates/stash-smart-routing.yaml)
- [Shadowrocket 配置](../templates/shadowrocket-smart-routing.conf)

生成器只读取 3X-UI 本机 Clash 节点 YAML，并注入本文件的 DNS、Fake-IP、代理组与规则。最终订阅 URL 为高熵随机路径，客户端只维护这一条 URL；不包含独立模板覆写步骤。

## 使用方式

### Nextin

只导入 Phase 7.2 部署脚本输出的最终 HTTPS URL，选择 **Rule**。不要导入 3X-UI `/sub/*`，也不要配置“订阅模板覆写”。

### Mihomo

将 `mihomo-smart-routing.yaml` 与现有 VLESS 订阅合并为一个 Profile，或由支持覆写的客户端把其中的 `dns`、`proxy-groups`、`rule-providers`、`rules` 合并到现有 Profile。保持 `mode: rule`，并在 `PROXY` 组选择已导入节点。

### Shadowrocket

先导入现有订阅/节点，再导入 `shadowrocket-smart-routing.conf`，令已导入节点的策略名为 `PROXY`，模式选“配置/规则”，不要选全局代理。该文件为 Shadowrocket 原生 `RULE-SET` 格式。

### Stash

导入现有 VLESS 节点或订阅后，导入 `stash-smart-routing.yaml` 作为配置/覆写，在 `PROXY` 策略组选择该节点，模式选 **Rule**。Stash 使用 Remote DNS，不使用系统 DNS 兜底。

## 路由顺序与覆盖原则

规则从上到下匹配，排序不可调换：

1. 广告规则集 `REJECT`。
2. 明确的国外服务 `PROXY`：OpenAI/ChatGPT、Claude/Anthropic、Google/Gemini、GitHub、Docker Hub、HuggingFace、Cloudflare AI、YouTube、Netflix、Disney+、Apple TV+、Prime Video、Reddit、X、Telegram。
3. LAN、私网、`*.local`、国内域名集合和 `GEOIP,CN` `DIRECT`。
4. 未命中 `MATCH/FINAL` 一律 `PROXY`。

Apple TV+ 的 `PROXY` 位于 Apple 中国 `DIRECT` 之前，因此不会因 Apple 中国服务规则而误直连。Tencent 规则集覆盖 QQ、微信；`cn` 聚合规则集覆盖企业微信、GitCode 等中国服务，并有 `gitcode.com` 的单条显式直连保护。

## 客户端验证清单

必须在客户端已连接、Rule Mode 已启用后手工执行。以下验证不写服务器，也不把“网页打开”误记为流媒体播放成功。

| 目标 | 预期策略 | 观察方式 |
|---|---|---|
| `baidu.com` | DIRECT | 客户端连接日志显示 `DIRECT` |
| `qq.com` | DIRECT | 客户端连接日志显示 `DIRECT` |
| `jd.com` | DIRECT | 客户端连接日志显示 `DIRECT` |
| `taobao.com` | DIRECT | 客户端连接日志显示 `DIRECT` |
| `chatgpt.com` / `api.openai.com` | PROXY | 客户端连接日志显示 `PROXY` |
| `github.com` | PROXY | 客户端连接日志显示 `PROXY` |
| `youtube.com` | PROXY | 客户端连接日志显示 `PROXY` |
| `netflix.com` | PROXY | 客户端连接日志显示 `PROXY`；另以登录后的实际播放验收 |

可使用浏览器分别访问上述域名；策略结论以客户端连接日志/规则命中为准。运行 [validation/run-performance.sh](validation/run-performance.sh) 仅能记录国外链路时延，不能代替 `DIRECT/PROXY` 规则命中检查。

## Apple TV

Apple TV 使用同一份 Rule Mode 逻辑，不允许全局代理：优先导入 Nextin tvOS 模板或 Stash 配置，在 `PROXY` 选择现有节点。YouTube、Netflix、Disney+、Apple TV+ 命中 `PROXY`，其余国内与私网流量仍遵循 `DIRECT`。内容播放仍依赖账号地区、版权库和服务风控。
