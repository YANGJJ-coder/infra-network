# HomeStream 文档命名收口实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仅通过 Markdown 文档统一 Personal Network Infrastructure、HomeStream 与节点双层标识，不改变任何运行配置或业务逻辑。

**Architecture:** `Personal Network Infrastructure` 为顶层项目，`HomeStream` 为流媒体和智能分流子系统。当前美国节点在设计类文档中使用 `HS-US-01-Bandwagon`，并在首次出现处映射到运维资产标识 `bwg-usca6-01 / BandwagonHost USCA_6`；历史验收和部署事实保留其原始资产名称。

**Tech Stack:** Markdown、Git。

## Global Constraints

- 不修改 VPS、SSH、Docker、3X-UI、Xray、Caddy、订阅接口、节点 ID、UUID、IP、端口或任何运行逻辑。
- 不重命名仓库目录、运行目录、主机名、容器名、脚本名或配置文件。
- 架构、README、设计和规划文档使用规范项目、子系统与节点名称。
- 历史部署、验收和真实运行记录保留 `BandwagonHost` 与 `bwg-usca6-01`，不得改写历史事实。

---

### Task 1: 建立规范名称与资产映射

**Files:**
- Modify: `README.md`
- Modify: `docs/Architecture-V1.md`

- [x] 在 README 说明顶层项目、HomeStream 子系统和当前节点的双层标识。
- [x] 在架构文档中加入正式架构树、当前节点映射和未来节点命名语法。
- [x] 保持 Config Generator、规则、DNS、Fake-IP、Proxy Group 与订阅流程原有措辞和职责不变。

### Task 2: 统一面向设计与规划的文档标题

**Files:**
- Modify: `docs/changes/ARCH-20260714-01.md`
- Modify: `docs/Phase5-HTTPS-Subscription.md`
- Modify: `docs/Phase6-Status-Dashboard.md`
- Modify: `docs/Phase7-Publish-Nextin.md`
- Modify: `docs/SmartRouting.md`

- [x] 仅在标题或定位语句补充 Personal Network Infrastructure / HomeStream 上下文。
- [x] 不重写技术步骤、不替换资产标识、不改变命令、URL、IP 或端口。

### Task 3: 保持历史证据并补足双层标识

**Files:**
- Modify: `docs/ProductionAcceptance.md`
- Modify: `docs/validation/Acceptance.md`
- Modify: `docs/validation/MacStudio-Nextin-Validation.md`
- Modify: `docs/validation/Performance.md`

- [x] 保留报告标题、历史日期、运行结果和原始资产名。
- [x] 在首次涉及当前服务器的上下文中补充 `HS-US-01-Bandwagon` 映射，不修改任何证据内容。

### Task 4: 文档验证

**Files:**
- Verify: `README.md`
- Verify: `docs/**/*.md`

- [x] 用 `rg` 确认规范名称、节点映射、未来命名示例均存在。
- [x] 用 `git diff --check` 确认 Markdown 无空白错误。
- [x] 检查变更文件列表，确认没有 Docker、Caddy、脚本、生成器、模板、测试或运行配置文件。
