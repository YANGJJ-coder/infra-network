# Phase 4 验收清单

验收采用两层口径：`Function Acceptance` 使用 `PASS`，`Reliability Observation` 使用 `Pending`。Mac Studio（Nextin）已连接当前生产环境并完成基本通信链路的功能验收；长期稳定性观察独立记录，不作为功能失败。

> 当前生产节点的规范业务名称为 `HS-US-01-Bandwagon`；历史验收证据中的 BandwagonHost、`bwg-usca6-01` 与实际运行数据均保留原样。

| 类别 | 项目 | 当前状态 | 验收证据要求 |
|---|---|---|---|
| 服务器 | 3X-UI 容器运行 | 通过 | `docker ps` 显示 `Up` |
| 服务器 | Docker/容器资源正常 | 通过 | `docker stats --no-stream` 资源快照 |
| 服务器 | SSH 仅密钥认证 | 通过 | `sshd -T`：root 禁用密码、`pubkeyauthentication yes`、密码/键盘交互关闭 |
| 服务器 | UFW 最小开放 | 通过 | 仅 `22/tcp`、`50835/tcp` |
| 服务器 | Fail2ban SSH jail | 通过 | `fail2ban-client status sshd` 正常 |
| 服务器 | BBR | 通过 | `net.ipv4.tcp_congestion_control = bbr` |
| 网络 | VPS 出口基线 | 通过 | [Performance.md](Performance.md) |
| Mac | Nextin 安装 | PASS（Function） | Mac Studio（Apple Silicon）已运行 Nextin 1.2.2 |
| Mac | 正式 HTTPS 订阅导入 | PASS（Function） | 当前 ChatGPT 会话确认经 Nextin、正式 HTTPS 订阅与 BandwagonHost 通信 |
| Mac | VLESS + TCP / 节点连接 | PASS（Function） | `utun9` 网络扩展运行，出口 `80.251.216.245` |
| Mac | ChatGPT Web / OpenAI 网络 / 当前生产环境通信 | PASS（Function） | ChatGPT Web 已加载；OpenAI `/v1/models` 未带 Key 返回预期 401 |
| Mac | YouTube / Netflix / Disney+ / Apple TV+ / Apple Music | Pending（Reliability） | 需要持续真实播放观察 |
| Mac | GitHub Clone / DNS Leak / Sleep-Wake / Auto Launch / 24h Stability | Pending（Reliability） | 需要持续真实使用观察 |
| iPhone | Shadowrocket VLESS + DNS/IPv6 | 待人工验证 | 连接成功、网络与 AI 实测 |
| iPad | Shadowrocket VLESS + DNS/IPv6 | 待人工验证 | 连接成功、网络与 AI 实测 |
| Apple TV | Shadowrocket tvOS VLESS + TCP | 待人工验证 | 实机导入、连接、四项流媒体播放 |
| AI | ChatGPT / OpenAI API / Codex / Claude / Gemini / Copilot | 待人工验证 | 登录和实际功能结果 |
| 流媒体 | Netflix / Disney+ / Apple TV+ / YouTube | 待人工验证 | 账号登录和实际播放 |

## 已记录 Bug

### BUG-20260714-01：Compose 日常命令缺少端口变量（已修复）

- **根因**：`compose.yml` 使用 `${PANEL_PORT}`、`${VLESS_PORT}`；初始脚本将固定值写入 `/opt/docker/configs/3x-ui/.env`，但 Docker Compose 默认只自动加载项目目录 `/opt/docker/stacks/3x-ui/.env`。因此直接运行 Compose 命令时变量未解析。
- **修复**：创建 `/opt/docker/stacks/3x-ui/.env`（`root:root`、`0600`），其内容与既有固定变量源 SHA-256 一致；新增 `/opt/docker/stacks/3x-ui/README.md` 说明变量与日常命令。未修改 `compose.yml`、端口、UUID、数据库或客户端配置。
- **验证**：`docker compose config`、`ps`、`down`、`up -d`、`restart`、`pull`、`logs` 均以退出码 `0` 完成，且未出现变量插值错误。
- **状态**：已修复并验证。
