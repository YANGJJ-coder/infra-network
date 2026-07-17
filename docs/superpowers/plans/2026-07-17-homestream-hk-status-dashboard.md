# HomeStream HK Status Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a signed 600-second HK reporter and a two-node public HomeStream status page without exposing an HK metrics endpoint.

**Architecture:** HK posts a compact signed JSON report over HTTPS to the existing US status service. US validates and persists the latest report, then returns it with its local summary under additive `nodes.us` and `nodes.hk` fields. The public page renders both cards and refreshes only its cached US API view.

**Tech Stack:** Python 3 standard library, Bash, systemd, Caddy, Docker, unittest, shell artifact tests.

## Global Constraints

- Node is exactly `HS-HK-01-Lisa`; report period is exactly 600 seconds.
- HK has no new listener or public status endpoint.
- HMAC key files are `0600`, never in Git, test fixtures, logs, or process arguments.
- Preserve original top-level US summary keys and all Custom Rules/Generator Caddy routes.
- HK reports older than 1,800 seconds are stale.

---

### Task 1: Test the signed-report contract

**Files:**
- Create: `status/__init__.py`
- Create: `status/status_server.py`
- Create: `tests/status_server.test.py`

- [ ] **Step 1: Write failing tests**

```python
def test_valid_hk_report_is_persisted_and_added_to_summary():
    response = post_signed_report(server, payload, key)
    assert response.status == 204
    assert get_summary(server)["nodes"]["hk"]["status"] == "fresh"

def test_bad_signature_does_not_replace_last_hk_report():
    response = post_report(server, payload, signature="bad")
    assert response.status == 401
```

- [ ] **Step 2: Run RED test**

Run: `PYTHONPATH=. python3 tests/status_server.test.py`

Expected: import failure because `status.status_server` does not exist.

- [ ] **Step 3: Implement minimum receiver**

Implement `StatusState`, `validate_report`, `make_handler`, and `create_server`. Require exact HK node ID, 32-byte HMAC key, five-minute timestamp window, a 16 KiB body limit, JSON object payload, and atomic persistence.

- [ ] **Step 4: Run GREEN test**

Run: `PYTHONPATH=. python3 tests/status_server.test.py`

Expected: all receiver tests pass.

### Task 2: Test the public two-card page and cache behavior

**Files:**
- Modify: `status/status_server.py`
- Modify: `tests/status_server.test.py`

- [ ] **Step 1: Write failing tests**

```python
def test_summary_preserves_us_fields_and_exposes_hk_freshness():
    summary = state.summary({"cpu_usage_percent": 2.5})
    assert summary["cpu_usage_percent"] == 2.5
    assert summary["nodes"]["us"]["cpu_usage_percent"] == 2.5
    assert summary["nodes"]["hk"]["status"] == "unavailable"

def test_homepage_contains_refresh_control_and_does_not_fetch_hk_directly():
    html = homepage_html()
    assert 'id="refresh"' in html
    assert '/api/node-reports/hk' not in html
```

- [ ] **Step 2: Run RED test**

Run: `PYTHONPATH=. python3 tests/status_server.test.py`

Expected: assertions fail before the additive node structure and new HTML exist.

- [ ] **Step 3: Implement minimum response/page behavior**

Keep the original US JSON keys; add `nodes.us`, `nodes.hk`, HK `age_seconds`, and fresh/stale/unavailable status. Make `/` render two cards and use a cache-busting GET to `/api/server-summary`; response API headers use `Cache-Control: no-store`.

- [ ] **Step 4: Run GREEN test**

Run: `PYTHONPATH=. python3 tests/status_server.test.py`

Expected: all tests pass.

### Task 3: Test and add HK sender/deployment assets

**Files:**
- Create: `status/hk_reporter.py`
- Create: `scripts/bwg-hk-status-dashboard.sh`
- Create: `scripts/hs-hk-status-reporter.sh`
- Create: `tests/hk_status_artifacts.test.sh`
- Modify: `caddy/phase7.2.Caddyfile`
- Modify: `docs/Phase6-Status-Dashboard.md`

- [ ] **Step 1: Write failing artifact tests**

```bash
grep -Fq 'OnUnitActiveSec=600' scripts/hs-hk-status-reporter.sh
grep -Fq 'X-HomeStream-Signature' status/hk_reporter.py
grep -Fq '/api/node-reports/hk' caddy/phase7.2.Caddyfile
grep -Fq 'no-store' caddy/phase7.2.Caddyfile
```

- [ ] **Step 2: Run RED test**

Run: `bash tests/hk_status_artifacts.test.sh`

Expected: fail because sender/deployer assets do not exist.

- [ ] **Step 3: Implement sender/deployer assets**

`hk_reporter.py` must collect only local operational metrics and POST a signed report. `hs-hk-status-reporter.sh` must install a root-only config, oneshot service, and `OnUnitActiveSec=600` timer. `bwg-hk-status-dashboard.sh` must back up US state, install the Python receiver, create the US secret only when absent, validate Caddy, and restart only the status service/Caddy.

- [ ] **Step 4: Run GREEN tests**

Run: `bash tests/hk_status_artifacts.test.sh && bash tests/phase6-status-artifacts.test.sh && bash tests/custom_rules_artifacts.test.sh`

Expected: all artifact tests pass.

### Task 4: Validate and deploy

**Files:**
- Modify: `tests/status_server.test.py`
- Modify: `tests/hk_status_artifacts.test.sh`

- [ ] **Step 1: Run complete local verification**

Run:

```bash
PYTHONPATH=. python3 tests/status_server.test.py
PYTHONPATH=. python3 tests/config_generator.test.py
PYTHONPATH=. python3 tests/custom_rules.test.py
PYTHONPATH=. python3 tests/custom_rules_http.test.py
bash tests/hk_status_artifacts.test.sh
bash tests/phase6-status-artifacts.test.sh
bash tests/custom_rules_artifacts.test.sh
bash tests/phase7.2-config-generator-artifacts.test.sh
git diff --check
```

- [ ] **Step 2: Deploy US then HK**

Copy only audited assets to temporary root-owned directories. Run US deploy first, copy its generated key into HK's 0600 environment file through stdin, install the HK reporter, start its service once, then enable its 600-second timer.

- [ ] **Step 3: Verify live boundaries**

Prove Caddy configuration, Custom Rules route, US status service, HK timer, one accepted signed report, US/HK API node structure, homepage refresh control, and that HK has no new listening socket.

- [ ] **Step 4: Commit and push**

```bash
git add status scripts caddy/phase7.2.Caddyfile docs/Phase6-Status-Dashboard.md tests
git commit -m "feat: add HK status reporting dashboard"
git push -u origin codex/hk-status-dashboard
```
