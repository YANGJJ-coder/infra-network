# Mac Studio（Nextin）生产验证

> 当前生产节点的规范业务名称为 `HS-US-01-Bandwagon`；本报告中的 BandwagonHost 与 `bwg-usca6-01` 均为保留的历史运维资产标识。

## 结论

**Function Acceptance：PASS**
**Reliability Observation：Pending**

本轮严格未改动 VPS、3X-UI、UUID、VLESS、Docker、DNS、HTTPS、订阅或任何服务器配置。Nextin 安装、正式 HTTPS 订阅导入、VLESS + TCP 节点连接、ChatGPT Web、OpenAI 网络与当前生产环境通信均已完成真实功能验收。YouTube/流媒体、DNS Leak、Sleep/Wake、Auto Launch 与连续 24 小时稳定性属于长期稳定性观察，不构成功能验收失败。

当前 ChatGPT 会话已确认运行于：

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

因此，客户端基本通信链路已完成生产验证；剩余项目属于长期稳定性观察，不属于功能失败。

## 验证边界

- 执行时间：2026-07-14 13:50–13:51 CST
- 服务端：完全冻结；本报告期间无 SSH、KiwiVM、3X-UI、Docker、DNS、HTTPS、订阅端或任何服务器配置写入。
- 客户端：仅做本机读取、HTTPS 请求、浏览器可达性检查与临时 `git clone`（已删除临时目录）。
- 指定正式订阅：`https://sub.jijunyang.com/configs/<随机高熵路径>.yaml`
- 禁止项遵守情况：未使用手工 VLESS 链接进行导入或测试。

## 环境与版本

| 项目 | 实测值 |
|---|---|
| 硬件 | Mac Studio，Apple M4 Max，36 GB 内存 |
| macOS | macOS 26.5.1（Build 25F80） |
| Nextin | 1.2.2 |
| Nextin 进程 | `Nextin` 与 `ProxyTunnel` 正在运行 |
| 活动网络扩展 | `utun9`，地址 `198.18.0.1` |
| 当前公网出口 | `80.251.216.245` |
| 系统 HTTP/HTTPS Proxy | Wi-Fi 显示 Enabled: No；流量由网络扩展隧道承载，不能据此判为未代理 |

## 订阅与连接状态

| 项目 | 结果 | 证据/说明 |
|---|---|---|
| 正式 HTTPS 订阅可取 | PASS | 对指定 URL 的只读 GET：HTTP 200，`text/plain`，156 bytes，0.513s |
| Nextin 已启动 | PASS | 本机 `Nextin`/`ProxyTunnel` 进程存在 |
| 正式订阅已导入 Nextin | PASS | 当前 ChatGPT 会话经 Nextin、正式 HTTPS 订阅与 BandwagonHost 的生产通信链路确认 |
| 订阅更新 | Pending | 后续作为订阅持续可用性观察项 |
| 连接 | PASS | 网络扩展 `utun9` 运行，公网出口为 `80.251.216.245` |
| 断开 | 待人工验证 | 本轮未切换客户端连接，避免干扰现有会话 |
| 重连 | 待人工验证 | 同上 |

## 可达性与真实客户端操作

| 项目 | 结果 | 证据 |
|---|---|---|
| ChatGPT Web | PASS | Chrome 实测打开 `https://chatgpt.com/`，页面标题 `ChatGPT` |
| Claude Web | 待人工验证 | 实测到达 `https://claude.ai/login`；未登录，不把登录页当作产品会话 PASS |
| Gemini Web | PASS | Chrome 实测打开 `https://gemini.google.com/`，页面标题 `Google Gemini` |
| GitHub Web | PASS | Chrome 实测打开 `https://github.com/`，页面标题正常 |
| GitHub `git clone` | Pending | 已有单次成功快照；持续克隆稳定性归入 Reliability Observation |
| YouTube 页面 | PASS | Chrome 已实际加载 `https://www.youtube.com/` |
| YouTube 1080p 实际播放 | 待人工验证 | 未开始视频播放，未伪造播放质量 |
| YouTube 4K 实际播放 | 待人工验证 | 同上 |
| Netflix 实际播放 | 待人工验证 | 需要已登录账户、受版权保护内容和人工画面确认 |
| Disney+ 实际播放 | 待人工验证 | 同上 |
| Apple Music 实际播放 | 待人工验证 | 需要已登录账户和人工音频确认 |

## DNS、系统代理与恢复能力

| 项目 | 结果 | 证据/说明 |
|---|---|---|
| DNS 隧道接管 | 部分 PASS | 主 resolver 位于 `utun9`；列出 `2606:4700:4700::1111`、`223.5.5.5`、`119.29.29.29`、`8.8.8.8` |
| DNS 泄漏 | 待人工验证 | 系统另有 en0/en1 的 scoped DNS；必须在连接状态下用 DNS leak 网页进行外部观测，不能仅由 resolver 列表下结论 |
| 系统代理开关 | 部分 PASS | Wi-Fi HTTP/HTTPS Proxy 均为 No；Nextin 网络扩展已建立，需人工切换 Nextin 开关并复查系统网络扩展/出口 |
| 睡眠唤醒恢复 | 待人工验证 | 未执行睡眠，避免中断当前使用 |
| 开机自启 | 待人工验证 | 本轮未重启；需重启后确认 Nextin 和 ProxyTunnel 自动运行及出口恢复 |
| 连续 24 小时稳定性 | Pending | 作为 Reliability Observation 持续记录，不影响 Function Acceptance：PASS |

## OpenAI 指定测速命令

执行命令（未携带 API Key）：

```bash
curl -sS -o /dev/null -w 'http=%{http_code} remote_ip=%{remote_ip} connect=%{time_connect}s total=%{time_total}s\n' --max-time 30 https://api.openai.com/v1/models
```

单次结果：`http=401 remote_ip=198.18.0.70 connect=0.002727s total=0.540548s`。

`401` 是未携带 API Key 时的预期鉴权响应，证明 HTTPS 到 OpenAI API 可达，不能代表 API 鉴权通过。

## 五轮测速平均值

每个目标连续执行 5 次 HTTPS `curl`；“总耗时”包含 DNS/TLS/首字节与完整请求，不等于纯网络 RTT。隧道 fake-IP 地址会显示为 `198.18.0.x`，因此未将其误报为公网服务端真实 IP。

| 目标 | 最终 HTTP 状态 | 平均连接耗时 | 平均总耗时 |
|---|---:|---:|---:|
| OpenAI `/v1/models` | 401 | 0.002s | 0.576s |
| GitHub API | 200 | 0.004s | 0.616s |
| Google `generate_204` | 204 | 0.003s | 0.523s |
| Cloudflare trace | 200 | 0.003s | 0.528s |
| YouTube `generate_204` | 204 | 0.005s | 0.536s |

## CPU 与内存

以下为客户端进程采样；“YouTube 播放时”没有启动真实视频，不能填写 PASS。

| 场景 | Nextin CPU / RSS | ProxyTunnel CPU / RSS | 结果 |
|---|---|---|---|
| 空闲/连接后（13:50 快照） | 3.1% / 191.2 MiB | 1.8% / 71.2 MiB | 已记录 |
| 三次连接后采样 | 0.0%、0.0%、0.1% / 192.5 MiB | 4.8%、4.0%、2.2% / 75.7 MiB | 已记录 |
| YouTube 实际播放时 | 待人工验证 | 待人工验证 | 未播放视频 |

## Reliability Observation（Pending）

以下项目继续以真实使用结果记录：连接/断开/重连、YouTube 1080p/4K、Netflix、Disney+、Apple TV+、Apple Music、GitHub Clone、DNS Leak、Sleep/Wake、Auto Launch、CPU/内存与连续 24 小时稳定性。它们是长期稳定性观察项，不改变本报告的 Function Acceptance：PASS。
