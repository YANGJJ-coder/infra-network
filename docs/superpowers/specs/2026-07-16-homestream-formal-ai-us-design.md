# HomeStream 正式订阅 AI-US 固定分流设计

## 目标

正式 Generator 的 AI 服务流量固定使用 `HS-US-01-Bandwagon`，同时保持正式订阅只含 `HS-US-01-Bandwagon` 和 `HS-HK-01-Lisa`。

## 设计

在 `nextin-smart-routing.yaml` 新增单成员选择组 `AI-US`，唯一成员为 `HS-US-01-Bandwagon`。OpenAI/ChatGPT、Claude/Anthropic、Gemini 与 Perplexity 的规则在既有通用 `PROXY` 规则之前命中 `AI-US`。

OpenAI/ChatGPT 使用既有 `openai` provider；Claude/Anthropic 使用既有 `claude` 与 `anthropic` providers；Gemini 和 Perplexity 分别新增独立 HTTP provider。Gemini provider 使用 blackmatrix7 的 Gemini 规则，Perplexity provider 使用 MetaCubeX 的 Perplexity 规则。

## 不变项

- DNS、Fake-IP、正式订阅 URL 与 Generator 的节点装配逻辑不变。
- 生产节点仅限 `HS-US-01-Bandwagon`、`HS-HK-01-Lisa`；不得出现 `HS-SG-01-Akile`。
- Netflix、Disney+、YouTube、Prime Video、Apple TV+ 等流媒体规则继续指向 `PROXY`。
- 现有非 AI 规则与 provider URL 不修改。

## 验证

测试先验证现有产物没有 `AI-US`、AI 仍指向 `PROXY`，再验证最小改动后的生成产物。生产部署前后采集结构化摘要，并仅允许 `AI-US` 组、AI provider、AI 规则和生成元数据时间/模板哈希变化。
