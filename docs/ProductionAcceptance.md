# BandwagonHost Phase 4 生产验收报告

报告时间：2026-07-14（Asia/Shanghai）
结论：**Phase 4 的 Mac Studio（Nextin）Function Acceptance：PASS；Reliability Observation：Pending。**

> 当前节点规范业务名称为 `HS-US-01-Bandwagon`。本报告保留原始运维资产标识 `bwg-usca6-01`、BandwagonHost 与历史运行结果，二者指向同一 BandwagonHost USCA_6 节点。

## 已验证的服务器状态

| 域 | 结果 |
|---|---|
| 系统 | `bwg-usca6-01`；Ubuntu 24.04.4 LTS；内核 `6.8.0-117-generic` |
| Docker | `3x-ui` 正在运行；重启策略 `unless-stopped`；Docker 与 containerd 均为 `active` |
| 端口 | 容器面板仅 `127.0.0.1:2053`；VLESS 为 `50835/tcp` |
| SSH | Root 为密钥登录策略（`without-password` 即 `prohibit-password`）；公钥认证开启；密码和键盘交互认证关闭 |
| UFW | 入站仅允许 `22/tcp` 与 `50835/tcp`，面板端口未开放 |
| Fail2ban | `sshd` jail 正常；当前无失败或封禁 |
| BBR | 已启用 |
| 资源 | CPU、内存、磁盘和磁盘 IO 均无压力，详细数据见 [Performance.md](validation/Performance.md) |
| 日志 | `/opt/docker/logs/3x-ui` 存在且可读；容器日志未见 panic/fatal。`syslog backend disabled` 为当前容器日志中的配置性提示，未观察到服务中断。 |

## 网络与服务基线

VPS 出口对 OpenAI、GitHub、Cloudflare、Google 的 3 次平均时延已采集，见 [性能基线](validation/Performance.md)。这不证明 VLESS 客户端链路或任一需登录服务的可用性。

## 客户端与业务验收

Mac Studio（Apple Silicon）上的 Nextin 已通过功能验收：正式 HTTPS 订阅导入、VLESS + TCP 节点连接、ChatGPT Web、OpenAI 网络及当前生产环境通信均已真实验证。

```text
Mac Studio
↓
Nextin
↓
正式 HTTPS 订阅
↓
HS-US-01-Bandwagon
（运维资产：BandwagonHost / `bwg-usca6-01`）
```

因此客户端基本通信链路已完成生产验证。YouTube/流媒体、DNS Leak、Sleep/Wake、Auto Launch、GitHub Clone 与 24 小时稳定性均归入 Reliability Observation，当前状态为 Pending，不属于功能失败。Mac 以外的 iPhone、iPad、Apple TV 验收仍按 [验收清单](validation/Acceptance.md) 记录。

Apple TV 的当前候选与实测步骤见 [AppleTV.md](AppleTV.md)。官方页面显示 Shadowrocket 与 Stash 都提供 tvOS 版本；当前服务器没有公网订阅，所以 Apple TV 采用手动节点导入进行验收。

## Phase 4.1 修复记录

`BUG-20260714-01` 已修复：3X-UI stack 已具有项目级 `.env`，Docker Compose 不再依赖临时 Shell 环境。完整根因、修改路径和生命周期验证结果见 [Acceptance.md](validation/Acceptance.md)。

## 验收结论

| 范围 | 状态 |
|---|---|
| Phase 1 | ✅ Frozen |
| Phase 1.5 | ✅ Frozen |
| Phase 2 | ✅ Frozen |
| Phase 3 | ✅ Frozen |
| Phase 4 | ✅ PASS（Function） |
| Reliability Observation | Running / Pending |

Mac Studio（Nextin）：**PASS（Function）**；**Pending（Reliability）**。稳定性观察是持续运行记录，不回溯为功能验收失败。
