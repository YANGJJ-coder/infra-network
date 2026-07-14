# Phase 7：DNS 与 Fake-IP

## 目标

避免把代理域名交给本地系统 DNS 明文解析，同时让国内直连域名使用中国 DoH。所有配置都排除了 `system` DNS 兜底。

## Nextin / Mihomo

`nextin-smart-routing.yaml` 与 `mihomo-smart-routing.yaml` 均启用：

```yaml
enhanced-mode: fake-ip
respect-rules: true
```

代理域名返回 `198.18.0.0/16` Fake-IP，由客户端按规则处理真实连接；全局 DNS 为 Cloudflare/Google DoH，并以 `#PROXY` 绑定到 `PROXY` 策略。`proxy-server-nameserver` 只负责解析代理服务器本身。`geosite:cn,private,apple-cn,microsoft@cn` 则使用腾讯/阿里 DoH（`doh.pub`、`dns.alidns.com`）直连解析。广告类别返回 `rcode://success`，不发起外部解析。

`*.lan`、`*.local`、STUN、NTP、Windows 连通性探测进入 Fake-IP filter，避免局域网发现、时间同步和网络探测被 Fake-IP 破坏。

## Shadowrocket / Stash

这两份交付采用 **Remote DNS** 路径：只配置 HTTPS DoH（国内为腾讯/阿里，国际为 Cloudflare/Google），不允许回落到系统 DNS。Stash 官方文档说明 `nameserver` 支持 DoH，且请求直接送往指定 DNS 服务；因此保留加密 DoH 而不是 `system`。Shadowrocket 同样只声明四个 DoH 服务器并设定 `dns-direct-system = false`。

Stash 的 `fake-ip-filter` 仅列出不应使用 Fake-IP 的协议/连通性域名；不依赖未在当前官方文档中确认的强制 Fake-IP 配置项。即使客户端版本不启用 Fake-IP，Remote DNS 仍会保持加密查询、不会使用系统 DNS 兜底。

## 验证

1. 打开客户端日志，访问 `chatgpt.com`，应显示 `PROXY`，且 DNS 不应出现本地系统 resolver。
2. 访问 `baidu.com`，应显示 `DIRECT`，DNS 命中腾讯/阿里 DoH 策略。
3. 访问局域网设备或 `*.local`，应为真实 IP，不应得到 `198.18.0.0/16`。
4. 使用外部 DNS leak 测试页时，以连接状态下的实际结果记录；不要仅凭系统 resolver 列表宣称没有泄漏。
