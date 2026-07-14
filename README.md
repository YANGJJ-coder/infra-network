# infra-network

个人网络基础设施的版本控制仓库。

## V1.0 边界

- 既有生产服务器 Phase 已冻结；仅编号的生产 Bug 可修改。
- 3X-UI 仅管理节点、客户端和订阅源；不管理 DNS、规则或分流策略。
- Config Generator 是唯一客户端配置发布器，客户端长期只使用一个高熵 URL：`/configs/<random-id>.yaml`。
- Dashboard 仅提供只读运维状态，不暴露订阅标识、UUID、Token、密钥、数据库或管理员信息。

## 目录

- `docker/`：Compose 定义
- `caddy/`：Caddy 配置模板
- `generator/`：Config Generator
- `templates/`：Mihomo / Nextin / Stash / Shadowrocket 规则模板
- `scripts/`：历史部署、验证与运维脚本
- `tests/`：本地验证
- `docs/`：架构、阶段、验收与排障文档

## 安全

禁止提交 `.env`、UUID、订阅 ID、Token、SSH Key、数据库、证书、备份和日志。部署时所有运行时值仅保存在服务器受限权限文件中。

## 当前状态

`ARCH-20260714-01`：建立独立仓库与安全基线；不对生产服务器执行部署或配置变更。
