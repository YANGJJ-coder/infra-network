# BandwagonHost / infra-network 最终架构（V1.0）

## 定位

这是长期可维护、可复制、可恢复、可扩展的个人网络基础设施，不是单一代理服务。目标客户端包括 ChatGPT、OpenAI API、Claude、Gemini、GitHub、日常网络访问和流媒体设备；未来可接入 Reality、WireGuard、住宅 IP 与多 VPS。

## 固定职责

```text
3X-UI 节点数据
    -> Config Generator
    -> 完整 Mihomo YAML
    -> https://sub.jijunyang.com/configs/<随机高熵 ID>.yaml
    -> Nextin / Mihomo / Stash / Shadowrocket / Apple TV
```

- 3X-UI 仅负责 UUID、端口、Client、Inbound 与订阅节点数据。
- Config Generator 是唯一客户端配置发布器：合并 3X-UI 节点与固定模板，输出 proxies、proxy-groups、rule-providers、rules、DNS、Fake-IP、版本和哈希。
- 3X-UI 不负责规则、DNS、Proxy Group、Fake-IP 或智能分流。
- 每个客户端只维护一个高熵订阅 URL；后续增加 VPS、Reality、WireGuard、住宅 IP 或规则时，只更新服务端。

## 安全与版本控制

- 禁止公开或提交 UUID、管理员密码、SQLite、SSH Key、Token、证书、备份、日志、`.env`、实际订阅 ID 或高熵订阅路径。
- `infra-network` 是唯一基础设施仓库；不得与 `mes_web` 混放。
- 所有变更必须使用 `FEATURE-YYYYMMDD-XX`、`BUG-YYYYMMDD-XX` 或 `ARCH-YYYYMMDD-XX` 编号，并记录原因、风险、回滚和验证。

## Dashboard

Dashboard 是只读运维中心，展示服务器、Docker、3X-UI、HTTPS、Subscription、CPU、Memory、Disk、Traffic、Certificate、Backup、OpenAI、GitHub、YouTube 状态；它不是 3X-UI 登录入口，也不提供写操作。

## 冻结规则与当前范围

所有既有服务器 Phase（Phase 1 至 Phase 5）均已冻结。除已编号的生产 Bug 外，禁止改动生产服务器。

当前只允许：建立本仓库、迁移非敏感资产、实现 Config Generator、完成只读 Dashboard。任何其他服务器功能都必须先经过新的 Architecture/Phase 设计、实施、审查和冻结流程。
