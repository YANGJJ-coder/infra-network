# 故障排查与验收清单

## 全量验收

- [ ] ChatGPT
- [ ] OpenAI API
- [ ] Claude
- [ ] Gemini
- [ ] GitHub
- [ ] YouTube
- [ ] Netflix
- [ ] Disney+
- [ ] Apple TV+
- [ ] Speedtest

## Mac 测速

```bash
curl -o /dev/null -s -w 'DNS:%{time_namelookup}\nTCP:%{time_connect}\nTLS:%{time_appconnect}\nTTFB:%{time_starttransfer}\nTOTAL:%{time_total}\n' https://api.openai.com
curl -o /dev/null -s -w 'TOTAL:%{time_total}\n' https://www.youtube.com
curl -o /dev/null -s -w 'TOTAL:%{time_total}\n' https://github.com
curl -o /dev/null -s -w 'TOTAL:%{time_total}\n' https://www.cloudflare.com/cdn-cgi/trace
```

## 常见问题

### 节点无法连接

确认客户端协议是 VLESS、传输为 TCP、端口为服务器当前 VLESS 端口、TLS/Reality 均关闭；不要使用面板端口 `2053`。

### 仅浏览器可访问

先确认系统代理开启；仍有应用直连时，验证节点后再启用 TUN。

### SSH Tunnel 无法打开后台

```bash
ssh -L 12053:127.0.0.1:2053 yjj@80.251.216.245
```

然后访问 `http://127.0.0.1:12053/<panel-path>`。面板端口不应加入 UFW。

### 没有公网订阅

这是当前架构的预期状态：未部署域名、HTTPS 或反向代理。保留 VLESS 链接，等待域名与 DNS 确定后再启用固定 HTTPS 订阅。
