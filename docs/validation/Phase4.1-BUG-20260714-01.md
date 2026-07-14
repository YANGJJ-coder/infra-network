# Phase 4.1：BUG-20260714-01 修复记录

## 原因

`/opt/docker/stacks/3x-ui/compose.yml` 通过 `${PANEL_PORT}` 和 `${VLESS_PORT}` 定义端口。初始部署脚本将两个固定值保存为 `/opt/docker/configs/3x-ui/.env`，并在首次部署时显式传入 `--env-file`；但日常直接运行 `docker compose` 时，Compose 只会自动发现 stack 目录的 `.env`，不会自动读取配置目录，因此出现变量未设置和无效端口插值错误。

## 修复方案

新增项目级文件：

```text
/opt/docker/stacks/3x-ui/.env
```

该文件以 `root:root`、`0600` 保存，内容由已存在的固定变量源复制而来。SHA-256 与原 `/opt/docker/configs/3x-ui/.env` 一致；没有改动端口值、`compose.yml`、数据库、UUID、入站或客户端。

同时新增：

```text
/opt/docker/stacks/3x-ui/README.md
```

其中说明 `.env` 的用途、权限和无 Shell `export` 的日常操作方式。

## 验证结果

在 `/opt/docker/stacks/3x-ui` 中，下列命令均成功执行且未出现变量错误：

```bash
docker compose config
docker compose ps
docker compose down
docker compose up -d
docker compose restart
docker compose pull
docker compose logs
```

`down`/`up -d` 是 Compose 的规定生命周期操作，因而容器 ID 改变；绑定挂载的 `/opt/docker/data/3x-ui` 未删除。当前检查确认：

- 预期 UUID 仍恰好存在 1 条；
- 已启用的 VLESS 入站 `50835/tcp` 仍恰好存在 1 条；
- 客户端与入站关联仍为 1 条，订阅 ID 仍存在；
- 原管理员账户仍存在且密码记录非空；使用现有管理员密码通过本机回环面板认证；
- 3X-UI 设置哈希、镜像摘要、端口映射和 `unless-stopped` 重启策略保持不变。

数据库文件的原始字节 SHA-256 在容器重新启动后发生变化；因此不将“字节完全相同”作为结论。逻辑数据与实际面板认证、VLESS 入站均已复核通过，未发现数据丢失或配置漂移。

## 使用边界

`docker compose` 的无参数项目发现机制以当前目录（及其父目录）为边界。标准操作为：

```bash
cd /opt/docker/stacks/3x-ui
docker compose ps
```

在其它任意目录，Docker Compose 本身必须显式给出项目文件；这与环境变量无关：

```bash
docker compose -f /opt/docker/stacks/3x-ui/compose.yml \
  --project-directory /opt/docker/stacks/3x-ui ps
```

两种方式均不需要 `export` 或人工提供端口变量。
