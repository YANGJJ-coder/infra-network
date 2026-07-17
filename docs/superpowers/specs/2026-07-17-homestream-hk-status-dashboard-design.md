# HomeStream HK Status Dashboard Design

## Goal

在 `https://status.jijunyang.com/` 的公开状态页并列显示 `HS-US-01-Bandwagon` 与正式节点 `HS-HK-01-Lisa` 的资源状态。HK 每 600 秒主动上报；页面“立即刷新”只刷新 US 本地汇总和已保存的 HK 最近上报，不会由浏览器或 US 反向探测 HK。

## Scope and constraints

- HK 节点固定为 `HS-HK-01-Lisa`（`38.175.193.231`）；不接入 PENDING 的 HGC 节点或 SG 节点。
- HK 不新增监听端口、公开指标页面、面板、Docker API 或数据库访问。
- 上报目标为 US 的 `POST /api/node-reports/hk`；请求体使用 HMAC-SHA256 和 UTC 时间戳认证。
- 上报密钥只保存在 US `/opt/docker/configs/status/hk-status-report.env` 与 HK `/opt/homestream/status-reporter/report.env`，均为 `0600`，绝不进入 Git、日志或命令行输出。
- HK 的 systemd timer 每 10 分钟运行一次；首次启动后也会立即上报一次。
- US 接收端将最后成功 HK 报告原子写入 `/opt/docker/data/status/hk-report.json`。报告超过 1,800 秒视为 stale；缺失或验签失败显示 unavailable。
- 既有 US 顶层 `/api/server-summary` 字段保持不变；新增 `nodes.us` 和 `nodes.hk`，供新版首页使用。
- 首页刷新按钮添加 cache-busting 查询参数，并只请求 `/api/server-summary`；API 发送 `Cache-Control: no-store`。

## Components and flow

1. HK `homesstream-hk-status-reporter.service` 调用只读采集器，生成 CPU、内存、磁盘、负载、运行时间、Docker、3X-UI 与网络流量摘要。
2. HK 采集器用共享密钥对 `timestamp + "\\n" + JSON body` 计算 HMAC-SHA256，并通过 HTTPS POST 发往 US。
3. US 状态服务验证 `X-HomeStream-Node`、`X-HomeStream-Timestamp`、`X-HomeStream-Signature`、时间窗口和 JSON schema；仅接受 `HS-HK-01-Lisa`。
4. US 将通过验证的报告原子写盘。GET 汇总执行既有 US 采集器，读取保存的 HK 报告并计算 fresh/stale/unavailable。
5. 首页将两份指标渲染为独立卡片，显示 HK 报告的上报时间和状态；点击“立即刷新”只重绘当前缓存视图。

## Failure handling and rollback

- HK 上报失败只导致 HK 卡片过期，不影响 US 指标、状态页、订阅、Caddy 或 Custom Rules。
- US 拒绝任何超时、节点名不匹配、签名错误、过大或格式非法的报告，并且不把其写盘。
- US 部署前备份状态服务、Caddyfile 与状态数据；HK 部署前备份 systemd unit、timer、脚本和环境文件。
- 回滚 US 会恢复状态服务/Caddyfile；回滚 HK 会移除 reporter unit、timer 与其私有目录，不触及 3X-UI、Reality、SSH、UFW 或订阅配置。

## Acceptance criteria

- 首页同时显示 US 与 HK，HK 上报间隔为 600 秒。
- 点击“立即刷新”后请求仅为 US 状态 API，不会对 HK 发起网络探测。
- 正确签名的 HK 报告出现在 `nodes.hk`；错误签名或过期报告不被视为 fresh。
- US 原有 `/api/server-summary` 顶层字段与 Custom Rules 路由继续可用。
- 所有本地测试、Caddy 校验、US/HK service-timer 健康检查和一次真实 HK 上报均通过。
