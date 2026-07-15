# Phase 5：HTTPS 公网订阅

> HomeStream 的历史部署阶段记录。本文中的服务器、端口、域名和服务商信息均为既有运行事实；当前节点规范名称为 `HS-US-01-Bandwagon`，其运维资产标识仍为 `bwg-usca6-01` / BandwagonHost USCA_6。

## 架构

`sub.jijunyang.com` 的 A 记录为 `80.251.216.245`，Cloudflare 设为 DNS only。Caddy 只代理 `/sub/*` 到宿主机回环绑定的 3X-UI 面板端口；其它所有路径固定返回 `404`。3X-UI 面板继续仅经 SSH Tunnel 访问。

## 交付路径

- Stack：`/opt/docker/stacks/reverse-proxy/compose.yml`
- 项目变量：`/opt/docker/stacks/reverse-proxy/.env`（0600）
- Caddyfile：`/opt/docker/configs/reverse-proxy/Caddyfile`
- 证书与 Caddy 数据：`/opt/docker/data/reverse-proxy`
- 日志：`/opt/docker/logs/reverse-proxy`
- 回滚：`/opt/docker/backups/reverse-proxy/<UTC 时间戳>/restore.sh`

## 安全约束

- 访问日志跳过 `/sub/*`，避免订阅 ID 写入访问日志。
- `2053/tcp` 保持回环监听，UFW 不开放。
- 公网只新增 `80/tcp`、`443/tcp`；VLESS 保持 `50835/tcp`。
- 客户端订阅地址固定为 `https://sub.jijunyang.com/sub/<现有订阅ID>`；验收输出只显示脱敏地址。

## PHASE5-001 修复

原 `extra_hosts: host.docker.internal:host-gateway` 在 Caddy 容器内解析为 Docker bridge 网关 `172.17.0.1`，但 3X-UI 的 `2053` 仅绑定到宿主机 `127.0.0.1`，导致 `/sub/*` 返回 `502`。

修复采用 Caddy `network_mode: host`，并删除 `ports` 与 `extra_hosts`。3X-UI 面板保持回环监听；订阅服务另以 `127.0.0.1:2096:2096` 仅映射到宿主机回环地址。

修复验证结果在本次部署完成后记录；Caddy Admin API 保持默认本机监听，未挂载 Docker socket 或非必要宿主机目录。

## 已发现 Bug：PHASE5-002

网络修复后，Caddy 到 `127.0.0.1:2053` 已连通，但该端口的 `/sub/<ID>` 返回 `404`。只读检查确认 3X-UI 的真实订阅服务监听在容器内 `2096`，`2053` 是面板端口，不提供订阅路由。

Phase 5.2 已授权将 `2096` 仅映射至宿主机 `127.0.0.1`，然后 Caddy 通过 host network 代理 `127.0.0.1:2096`。不会使用容器 IP，也不会在 UFW 中开放 2096。

验证完成：本机 `127.0.0.1:2096/sub/<ID>` 与公网 HTTPS 订阅均返回 `200`；HTTP 跳转、404 路径隔离、证书、VLESS、UUID、订阅逻辑数据和面板回环绑定均保持正确。PHASE5-001 与 PHASE5-002 已关闭，Phase 5 冻结。

## 管理后台

```bash
ssh -L 12053:127.0.0.1:2053 yjj@80.251.216.245
```
