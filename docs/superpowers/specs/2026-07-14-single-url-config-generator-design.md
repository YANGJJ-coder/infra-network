# 单一订阅 URL Config Generator 设计

## 目标

将 3X-UI 降为节点数据源，向客户端只发布一条高熵、不可猜测的完整 Mihomo YAML 订阅。Nextin、Mihomo 与 Stash 更新这一个 URL 时，节点、DNS、Fake-IP、代理组、规则集和路由规则一起更新。

## 边界

- 输入节点只能来自 VPS 本机的 3X-UI Clash 订阅接口：`127.0.0.1:2096/clash/<sub_id>`。
- 3X-UI 订阅 URL 不再直接向客户端发布。
- 不采用 Nextin 订阅模板覆写、客户端本地规则或双订阅模型。
- 第一期只生成 Mihomo/Nextin/Stash 兼容 YAML；Shadowrocket 原生订阅不纳入该产物。

## 架构

```text
3X-UI SQLite（只读） -> 读取唯一启用客户端 sub_id
                         |
                         v
127.0.0.1:2096/clash/<sub_id> -> Config Generator -> 完整 YAML
                                                        |
                                                        v
Caddy /configs/<256-bit-random-id>.yaml -> 客户端唯一订阅 URL
```

生成器在每次 HTTP 请求时读取 3X-UI Clash YAML，提取且仅提取 `proxies`。它将这些节点注入受版本控制的运行模板，再验证输出 YAML；不得将 3X-UI 返回的分组、规则或 DNS 透传到最终配置。

## 安全

- 公网路径使用 256-bit 随机 ID，保存在 root-only 的环境文件中。
- 3X-UI 订阅 ID 只保留在 VPS 本地，禁止写入 Caddy 日志、生成器日志、响应头、仓库或文档。
- Generator 仅监听 `127.0.0.1`；只有 Caddy 暴露最终随机路径。
- Caddy 对最终订阅路径关闭访问日志；其它 `/configs/*` 不再静态暴露。
- Generator 对上游失败、空节点、重复节点或 YAML 验证失败返回 503，绝不输出半成品或旧配置。

## 生成 YAML 元数据

在顶层加入：

```yaml
x-config-version: 1
x-generated-at: 2026-07-14T13:52:18Z
x-generator: ConfigGenerator
x-template-sha256: <template hash>
x-proxies-sha256: <canonical proxy-list hash>
```

`x-template-sha256` 对不含动态元数据和 `proxies` 的模板正文计算 SHA-256；`x-proxies-sha256` 对按节点名称排序、稳定序列化后的 `proxies` 计算 SHA-256。节点变化只改变后者；规则/DNS/组变化只改变前者。

## 路由合同

- `RULE-SET,openai,PROXY` 必须位于 `MATCH,PROXY` 之前。
- `RULE-SET,netflix,PROXY` 必须位于 `MATCH,PROXY` 之前。
- `RULE-SET,baidu,DIRECT` 必须位于 `GEOIP,CN,DIRECT` 与 `MATCH,PROXY` 之前。
- 最终 `MATCH` 只可指向 `PROXY`，不得作为 OpenAI、Netflix 或百度的实际命中规则。

## 部署与更新

部署脚本一次性生成随机 ID、安装 root-only generator 环境、systemd service、Caddy 路由和回滚脚本。客户端首次迁移到唯一 URL 后，后续仅使用客户端原生 Update；服务端不需要 cron，因为 Generator 每次请求都从本机 3X-UI 取得当前节点集合。

## 验收

1. 最终 URL 返回完整 YAML，含非空 `proxies`、元数据、DNS、Fake-IP、规则组、rule-providers 和 rules。
2. 不含 `x-nextin.mode: subscription-template`。
3. 修改模拟节点集合只改变 `x-proxies-sha256`；修改模板规则只改变 `x-template-sha256`。
4. Nextin 运行时日志/API 中：`chatgpt.com` 命中 OpenAI Rule、`baidu.com` 命中 DIRECT 规则、`netflix.com` 命中 Netflix Rule，三者均不得命中 MATCH。
5. `/sub/*` 和 3X-UI 管理面板继续保持现有行为；最终订阅 URL 之外的 `/configs/*` 返回 404。
