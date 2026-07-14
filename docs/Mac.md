# Mac（Mihomo / Clash Verge Rev）

## 当前服务器接入方式

当前没有公网 HTTPS 订阅。先从安全位置取得 VLESS 链接后，在 Clash Verge Rev 的 `Profiles` 中用“从剪贴板导入”或手动添加节点。不要把面板 SSH 隧道地址当作公网订阅地址。

## 推荐设置

1. 在 `Profiles` 导入 VLESS + TCP 节点，选择 `VLESS-TCP-Main`。
2. 首次连通先开启“系统代理”，模式选“规则”。
3. 浏览器、ChatGPT、Claude、Gemini、GitHub 验证通过后，再安装应用要求的 Service Mode 并开启 TUN。
4. TUN 开启后确认 DNS 使用客户端内置 DNS；不要在 macOS 中手填服务器 IP 作为 DNS。
5. 在 Settings 启用开机启动与“启动后恢复系统代理”。

## 验收

```bash
curl -I https://chatgpt.com
curl -I https://api.openai.com
curl -I https://github.com
curl -I https://www.youtube.com
```

系统代理主要覆盖遵循系统代理的应用；TUN 通过虚拟网卡覆盖不遵循系统代理的程序。先验证节点可用，再打开 TUN，避免错误配置造成全机断网。
