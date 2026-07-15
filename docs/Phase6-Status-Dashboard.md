# Phase 6：生产运维状态面板

> HomeStream 的历史部署阶段记录。本文中的服务器与运行信息保留既有资产事实；当前节点规范名称为 `HS-US-01-Bandwagon`，其运维资产标识仍为 `bwg-usca6-01` / BandwagonHost USCA_6。

地址为 `https://status.jijunyang.com`。Uptime Kuma 仅监听 `127.0.0.1:3001`，服务器指标服务仅监听 `127.0.0.1:3010`，均由既有 Caddy 反代；未新增 UFW 规则，未暴露 Docker Socket。

公开状态页只能查看状态；不提供写操作、重启、停止、更新、删除或自动修复。订阅 URL、订阅 ID、UUID、SSH 凭据和 3X-UI 管理信息不在页面、接口或日志中显示。

`/api/server-summary` 返回 CPU、内存、磁盘、负载、运行时间、Docker、Caddy、3X-UI、订阅 HTTP 状态、证书、vnStat 月流量及最近备份时间。流量为本机接口统计，仅供参考，以 KiwiVM 计费为准。

回滚脚本位于 `/opt/docker/backups/status/<UTC时间戳>/restore.sh`；常规备份命令为 `/opt/docker/scripts/status/backup.sh`。
