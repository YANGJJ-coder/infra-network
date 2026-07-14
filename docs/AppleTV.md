# Apple TV

## 当前推荐

优先使用 [Shadowrocket tvOS 版](https://apps.apple.com/us/app/shadowrocket/id932747118?platform=tv)。官方 App Store 页面确认其支持 Apple TV（要求 tvOS 17 或更高版本），近期官方版本说明也包含 tvOS 的 VLESS 支持。因此，它是当前手工导入 VLESS + TCP 节点的首选候选。

本机尚未实际导入或播放验证；下列步骤是待执行的真实验收流程，不能视为已通过。

## Shadowrocket 配置

1. 在 Apple TV 的 App Store 安装 Shadowrocket。
2. 在应用内手动新增节点，填写现有 VLESS 链接；不要填写 3X-UI 面板端口 `2053`。
3. 核对：协议 `VLESS`、传输 `TCP`、TLS `关闭`、Reality `关闭`、端口为当前 VLESS 入站端口。
4. 启用连接后，依次验证 YouTube、Netflix、Disney+、Apple TV+。

当前没有公网 HTTPS 订阅，因此不能把订阅 URL 作为 Apple TV 的验收前提；使用手动节点导入。

## Stash TV

[Stash](https://apps.apple.com/us/app/stash-rule-based-proxy/id1596063349?platform=tv) 同样提供 Apple TV 版（tvOS 17+），官方说明支持 Clash 配置和规则/DNS 管理。当前服务器没有公网订阅，也没有已验证的 Clash 配置产物，因此 Stash 只作为待测试的备选，不宣称已可直接导入当前 VLESS 链接。

## 验收记录

- [ ] Shadowrocket 已安装并可导入节点
- [ ] VLESS + TCP 已连接
- [ ] YouTube 可播放
- [ ] Netflix 可播放
- [ ] Disney+ 可播放
- [ ] Apple TV+ 可播放

内容可用性仍取决于账号地区、版权库和各服务风控；单一网站可打开不等同于流媒体已验收。
