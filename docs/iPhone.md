# iPhone（Shadowrocket）

## 导入

当前阶段没有公网 HTTPS 订阅，使用安全保存的 VLESS 链接导入：打开 Shadowrocket，点击右上角 `+`，选择从剪贴板导入或手动添加 VLESS 节点。节点为 `VLESS + TCP`，TLS 与 Reality 均关闭。

## 推荐设置

1. 导入后先点击节点测速，再连接。
2. 路由模式先用“配置”或“代理”；若仅做连通性排查，临时使用“全局代理”，完成后切回规则模式。
3. DNS 使用 Shadowrocket 的加密 DNS/DoH 配置；不要关闭 IPv6，先分别测试 IPv4 与 IPv6 网络。
4. 开启按需连接或小组件快捷开关；自动更新订阅在公网 HTTPS 订阅上线后再启用。

## 验收

在蜂窝网络与 Wi-Fi 各测试一次：ChatGPT、OpenAI API、Claude、Gemini、GitHub、YouTube 和流媒体 App。任何平台/账号的地区限制仍以服务商政策为准。
