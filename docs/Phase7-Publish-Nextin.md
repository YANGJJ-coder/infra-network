# Phase 7.2：单一订阅 Config Generator

## 最终架构

3X-UI 只保存和输出节点。客户端不再订阅 `/sub/<sub_id>`，也不再使用 Nextin `subscription-template`。

```text
3X-UI Clash 节点 YAML（仅 VPS 回环）
  -> Config Generator
  -> https://sub.jijunyang.com/configs/<64-hex-random-id>.yaml
  -> Nextin / Mihomo / Stash
```

最终 URL 只在首次部署时向操作者输出一次。随机路径为 256 bit 熵，存放在 VPS 的 mode `0600` 文件，不写入仓库、文档、日志或客户端以外的系统。

## 生成内容

每次客户端更新 URL 时，Generator 都会读取当前唯一启用 3X-UI 客户端的 `sub_id`，从 `127.0.0.1:2096/clash/<sub_id>` 取回节点，并生成完整 YAML：

- 当前 `proxies`；
- `proxy-groups`；
- `rule-providers` 与 `rules`；
- DNS、Fake-IP；
- `x-config-version`、`x-generated-at`、`x-generator`；
- `x-template-sha256` 与 `x-proxies-sha256`。

上游无节点、多个启用订阅、节点重名、YAML 解析失败或配置合同不完整时，Generator 返回 `503`，绝不返回部分配置。

## 部署

将下列文件同目录上传到 VPS，例如 `/tmp/bwg-phase7.2`：

```text
bwg-phase7.2-config-generator.sh
phase7.2-Caddyfile
phase7.2-reverse-proxy.compose.yml
templates/nextin-smart-routing.yaml
generator/config_generator.py
generator/requirements.txt
generator/Dockerfile
```

以 root 执行：

```bash
cd /tmp/bwg-phase7.2
./bwg-phase7.2-config-generator.sh
```

脚本先备份原 Caddy/Compose/Generator 目录并验证 Caddy；部署失败可执行其输出的 `restore.sh`。它不改变 Ubuntu、3X-UI 节点、UUID、证书、DNS、UFW 或 SSH。

## 客户端迁移与验收

1. 在 Nextin 删除旧 `/sub/<sub_id>` 订阅与旧模板关联。
2. 仅导入脚本输出的最终 URL；模式保持 Rule。
3. 更新后检查顶层版本与两份 SHA-256 元数据。
4. 在 Nextin 连接日志/API 中验证：

| 域名 | 预期规则 | 预期策略 | 禁止结果 |
|---|---|---|---|
| `chatgpt.com` | `RULE-SET,openai` | `PROXY` | `MATCH` |
| `baidu.com` | `RULE-SET,baidu` | `DIRECT` | `MATCH` |
| `netflix.com` | `RULE-SET,netflix` | `PROXY` | `MATCH` |
