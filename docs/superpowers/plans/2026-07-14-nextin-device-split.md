# Nextin Device Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the original 3X-UI node subscription usable while publishing a separate private, minimal Nextin template for iPhone and leaving Apple TV on global proxy mode.

**Architecture:** The original `/sub/<sub_id>` endpoint remains the immutable node source. The generator continues serving the desktop full configuration. A Caddy-gated random template route proxies to the generator, which returns a static Nextin `subscription-template` document without remote rule providers; iPhone binds it locally to the original node subscription.

**Tech Stack:** Python 3.13 stdlib generator, YAML, Caddy, Docker Compose, 3X-UI subscription.

## Global Constraints

- Do not modify the existing 3X-UI subscription identifier or the 3X-UI node database.
- iPhone template must not include remote rule providers.
- Apple TV uses the node subscription with global mode and no template.
- Desktop full configuration stays available at its existing random URL.

---

### Task 1: Add a minimal iPhone template endpoint

**Files:**
- Create: `configs/nextin-ios-template.yaml`
- Modify: `generator/config_generator.py`
- Modify: `tests/config_generator.test.py`

- [ ] **Step 1: Write a failing test**

```python
def test_ios_template_has_nextin_marker_and_no_rule_providers(self):
    template = load_yaml(IOS_TEMPLATE_PATH)
    assert template["x-nextin"]["mode"] == "subscription-template"
    assert "rule-providers" not in template
```

- [ ] **Step 2: Implement the static template handler**

```python
if self.path.startswith("/templates/"):
    self.serve_ios_template()
```

The handler reads `/etc/bwg-config-generator/nextin-ios-template.yaml`, returns YAML with `Cache-Control: no-store`, and has no upstream fetch.

- [ ] **Step 3: Verify locally**

Run: `PYTHONPATH=. python3 tests/config_generator.test.py -v`

Expected: all tests pass.

### Task 2: Publish the private template route

**Files:**
- Modify: `phase7.2-Caddyfile`
- Modify: `bwg-phase7.2-config-generator.sh`
- Test: `tests/phase7.2-config-generator-artifacts.test.sh`

- [ ] **Step 1: Add the Caddy placeholder route**

```caddyfile
handle __IOS_TEMPLATE_PATH__ {
    reverse_proxy http://127.0.0.1:3011
}
```

- [ ] **Step 2: Render `__IOS_TEMPLATE_PATH__` from the existing random configuration token**

The rendered path is `/templates/<same-random-token>.yaml`; Caddy is the access gate.

- [ ] **Step 3: Validate and deploy**

Run Caddy validation, rebuild only `config-generator`, recreate only `caddy`, then verify:

```bash
curl -fsS https://sub.jijunyang.com/templates/<token>.yaml
```

Expected: YAML has `x-nextin.mode: subscription-template` and no `rule-providers`.

### Task 3: Document device use and verify preserved source

**Files:**
- Modify: `docs/Phase7-Publish-Nextin.md`

- [ ] **Step 1: Add exact device instructions**

Document the original 3X-UI node URL as the iPhone and Apple TV source, the private template URL only for iPhone, and global mode for Apple TV.

- [ ] **Step 2: Verify original source remains unchanged**

```bash
curl -fsS -H 'Host: sub.jijunyang.com' http://127.0.0.1:2096/clash/<SUBSCRIPTION_ID>
```

Expected: response contains `VLESS-TCP-Main-yjj-main` and is not changed by this deployment.

- [ ] **Step 3: Final verification**

Run generator unit tests, Caddy validation, public template fetch, public desktop-config fetch, and source-subscription fetch.
