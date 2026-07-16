# HomeStream Formal AI-US Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让正式订阅中的指定 AI 服务固定命中 `HS-US-01-Bandwagon`，不改变其余生产行为。

**Architecture:** 模板定义唯一的 `AI-US` 单成员组并把 AI 规则定向到该组；Generator 继续仅合并 3X-UI US 源和正式附加 HK 源。测试同时约束节点集合、AI 规则、流媒体规则和不变的 DNS/Fake-IP。

**Tech Stack:** Python 3 `unittest`、PyYAML、Mihomo YAML、Bash、Docker Compose。

## Global Constraints

- 正式节点仅为 `HS-US-01-Bandwagon` 与 `HS-HK-01-Lisa`，禁止 `HS-SG-01-Akile`。
- DNS、Fake-IP、订阅 URL、节点装配及既有非 AI 规则/provider URL 不变。
- 流媒体规则继续逐字使用 `PROXY`。
- AI-US 成员仅为 `HS-US-01-Bandwagon`。

---

### Task 1: 建立 AI-US 产物契约

**Files:**
- Modify: `tests/config_generator.test.py`
- Test: `tests/config_generator.test.py`

**Interfaces:**
- Consumes: `build_config(template, proxies, generated_at)`
- Produces: 对 `proxy-groups`、`rule-providers` 与 `rules` 的生成产物断言。

- [ ] **Step 1: 写入失败测试**

```python
def test_formal_template_routes_only_named_ai_services_to_single_us_group(self):
    template = load_yaml(str(Path(__file__).parents[1] / "templates" / "nextin-smart-routing.yaml"))
    config = build_config(template, [US_PROXY, HK_PROXY], FIXED_TIME)
    self.assertEqual(["HS-US-01-Bandwagon"], groups["AI-US"]["proxies"])
    self.assertEqual("AI-US", rule_target(config, "openai"))
```

- [ ] **Step 2: 运行并确认失败**

Run: `PYTHONPATH=. python3 tests/config_generator.test.py`

Expected: FAIL，因为当前模板不存在 `AI-US` 且 AI 规则为 `PROXY`。

- [ ] **Step 3: 最小实现**

在 `templates/nextin-smart-routing.yaml` 增加 `AI-US`、Gemini/Perplexity provider，并仅改 AI 规则目标。

- [ ] **Step 4: 运行契约测试**

Run: `PYTHONPATH=. python3 tests/config_generator.test.py`

Expected: PASS。

### Task 2: 部署并对比正式订阅

**Files:**
- Modify: `templates/nextin-smart-routing.yaml`
- Modify: `tests/config_generator.test.py`

**Interfaces:**
- Consumes: 正式 Generator 的 `/configs/<id>.yaml`。
- Produces: 部署前后结构化摘要和仅允许变更的 diff。

- [ ] **Step 1: 执行本地全量相关验证**

Run: `PYTHONPATH=. python3 tests/config_generator.test.py && bash tests/phase7.2-config-generator-artifacts.test.sh && bash tests/phase7-smart-routing-artifacts.test.sh`

Expected: exit 0。

- [ ] **Step 2: 部署正式 Generator**

Run: `ssh root@80.251.216.245 'cd <deployed-source> && ./scripts/bwg-phase7.2-config-generator.sh'`

Expected: Docker Compose 重建成功，正式 URL 保持不变。

- [ ] **Step 3: 结构化 diff**

比较部署前后节点、策略组、AI 规则、流媒体规则、DNS/Fake-IP 与正式 URL；拒绝任何非 AI-US/AI-provider/AI-rule/元数据变更。

- [ ] **Step 4: 提交**

```bash
git add templates/nextin-smart-routing.yaml tests/config_generator.test.py docs/superpowers/specs/2026-07-16-homestream-formal-ai-us-design.md docs/superpowers/plans/2026-07-16-homestream-formal-ai-us.md
git commit -m "feat: route formal AI services through US node"
```
