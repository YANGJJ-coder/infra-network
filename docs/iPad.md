# iPad（Shadowrocket）

iPad 与 iPhone 使用相同的 Shadowrocket 节点和流程：当前导入 VLESS 链接；未来 HTTPS 订阅上线后，替换为固定订阅 URL，无需重新建立节点。

## 建议

1. 先在 Wi-Fi 下连接并浏览 `https://api.openai.com`、`https://github.com`。
2. 在蜂窝数据下重复测试，排除运营商网络差异。
3. 规则模式用于日常使用；全局模式只用于故障定位。
4. 订阅自动更新必须等公网 HTTPS 订阅部署后才启用；当前 SSH Tunnel 内订阅不适用于移动设备长期自动更新。
