# Phase 4 验证规范

## 约束

本阶段仅采样、检查和记录。不得修改 Ubuntu、Docker、SSH、UFW、Fail2ban、BBR、3X-UI、VLESS、UUID 或端口；发现问题必须记录后等待确认。

## 执行边界

- VPS 出口基线：通过 SSH 在服务器上只读执行网络与资源采样，验证服务器的公网出口和容器健康。
- 客户端端到端：必须在已连接 VLESS 的 Mac、iPhone、iPad、Apple TV 上人工执行。VPS 本地 curl 不能替代此项。
- 任何 AI、流媒体服务均以登录后真实使用结果为准；HTTP 通达、DNS 正常或 curl 成功不能替代服务验收。

## 客户端性能命令

在 Mac 上确认 Clash Verge Rev/Mihomo 已启用 TUN 或系统代理后执行：

```bash
cd /Users/yjj/Documents/BandwagonHost/docs/validation
chmod +x run-performance.sh
./run-performance.sh 3
```

脚本采样 OpenAI API、GitHub、GitHub API、Cloudflare、Google，每目标默认 3 次并输出均值。不向 API 发送认证请求；OpenAI 返回 `421`、`401` 或 `403` 时，时延仍可作为网络采样，但不代表 API 鉴权成功。

## 人工验收清单

### AI 与开发

- [ ] ChatGPT：登录、发起并收到一次对话回复
- [ ] OpenAI API：使用自己的 API Key 完成一次实际请求
- [ ] Codex：登录并完成一次联网/模型请求
- [ ] Claude：登录并完成一次对话
- [ ] Gemini：登录并完成一次对话
- [ ] GitHub Copilot：在已授权 IDE 中完成一次建议或聊天
- [ ] GitHub：网页与 `api.github.com` 均可访问

### 流媒体与音乐

- [ ] YouTube：可播放视频
- [ ] Netflix：可登录并播放目标内容
- [ ] Disney+：可登录并播放目标内容
- [ ] Apple TV+：可登录并播放目标内容
- [ ] Spotify（可选）：可播放
- [ ] Apple Music（可选）：可播放

记录时必须写入日期、设备、客户端模式（系统代理/TUN/Apple TV App）和实际错误信息；不要将未测试项写为通过。

## Bug 流程

1. 在 `Acceptance.md` 或 `ProductionAcceptance.md` 记录症状、时间和复现条件。
2. 只读收集日志和状态，分析根因与影响范围。
3. 给出最小修复方案及其可能影响。
4. 等待确认；未确认前不修改服务器。
