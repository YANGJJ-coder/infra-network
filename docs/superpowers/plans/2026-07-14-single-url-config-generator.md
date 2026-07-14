# Single URL Config Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish one high-entropy HTTPS URL that returns a complete, validated Mihomo YAML assembled from the current 3X-UI Clash node subscription and the project routing template.

**Architecture:** A loopback-only Python HTTP service reads the only enabled 3X-UI `sub_id` from SQLite, downloads the local Clash YAML, replaces the template node list with the upstream `proxies`, calculates stable hashes, and validates the result. Caddy publishes only the secret path and proxies it to the service.

**Tech Stack:** Python 3 standard library, PyYAML, SQLite read-only URI, systemd, Docker Compose/Caddy, Bash tests.

## Global Constraints

- The public client URL is exactly one high-entropy random path; no query-token fallback is used.
- Never write `sub_id`, node credentials, UUIDs, or the random path to logs, tests, repository files, or response headers.
- Generator listens only on `127.0.0.1`.
- Upstream source is `127.0.0.1:2096/clash/<sub_id>`; clients never use `/sub/*`.
- Output has `x-config-version: 1`, UTC `x-generated-at`, `x-generator: ConfigGenerator`, `x-template-sha256`, and `x-proxies-sha256`.
- `chatgpt.com`, `baidu.com`, and `netflix.com` must have explicit pre-MATCH rules.

---

### Task 1: Define and test the pure YAML builder

**Files:**
- Create: `generator/config_generator.py`
- Create: `generator/requirements.txt`
- Create: `tests/config_generator.test.py`
- Modify: `configs/nextin-smart-routing.yaml`

**Interfaces:**
- Produces: `build_config(template: dict, proxies: list[dict], generated_at: datetime) -> dict`
- Produces: `canonical_sha256(value: object) -> str`
- Produces: `validate_config(config: dict) -> None`

- [ ] **Step 1: Write the failing builder tests**

```python
def test_build_config_injects_nodes_and_metadata(template, proxy):
    config = build_config(template, [proxy], FIXED_TIME)
    assert config['proxies'] == [proxy]
    assert config['x-config-version'] == 1
    assert config['x-generated-at'] == '2026-07-14T13:52:18Z'
    assert config['x-generator'] == 'ConfigGenerator'

def test_proxy_hash_changes_without_template_hash_change(template, proxy):
    one = build_config(template, [proxy], FIXED_TIME)
    two = build_config(template, [{**proxy, 'name': 'other'}], FIXED_TIME)
    assert one['x-template-sha256'] == two['x-template-sha256']
    assert one['x-proxies-sha256'] != two['x-proxies-sha256']
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `python3 -m unittest tests/config_generator.test.py -v`

Expected: FAIL because `generator.config_generator` does not exist.

- [ ] **Step 3: Implement the minimal pure builder**

```python
def canonical_sha256(value):
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(encoded).hexdigest()

def build_config(template, proxies, generated_at):
    config = copy.deepcopy(template)
    config['proxies'] = sorted(proxies, key=lambda item: item['name'])
    config['x-config-version'] = 1
    config['x-generated-at'] = generated_at.strftime('%Y-%m-%dT%H:%M:%SZ')
    config['x-generator'] = 'ConfigGenerator'
    config['x-template-sha256'] = canonical_sha256(template)
    config['x-proxies-sha256'] = canonical_sha256(config['proxies'])
    validate_config(config)
    return config
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `python3 -m unittest tests/config_generator.test.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add generator/config_generator.py generator/requirements.txt tests/config_generator.test.py configs/nextin-smart-routing.yaml
git commit -m "feat: add deterministic config builder"
```

### Task 2: Add source adapter and loopback HTTP endpoint

**Files:**
- Modify: `generator/config_generator.py`
- Create: `generator/config-generator.service`
- Modify: `tests/config_generator.test.py`

**Interfaces:**
- Produces: `read_single_sub_id(db_path: str) -> str`
- Produces: `fetch_clash_config(url: str, timeout_seconds: int) -> dict`
- Produces: `serve(bind_host: str, port: int, secret_path: str) -> None`

- [ ] **Step 1: Write failing source and HTTP tests**

```python
def test_read_single_sub_id_rejects_zero_or_multiple_enabled_clients(tmp_path):
    with pytest.raises(ValueError, match='exactly one'):
        read_single_sub_id(str(tmp_path / 'x-ui.db'))

def test_http_handler_rejects_wrong_path(server):
    status, _ = request(server, '/not-the-secret.yaml')
    assert status == 404
```

- [ ] **Step 2: Run targeted tests and verify RED**

Run: `python3 -m unittest tests/config_generator.test.py -v`

Expected: FAIL because source adapter and handler are missing.

- [ ] **Step 3: Implement fail-closed source adapter**

```python
def read_single_sub_id(db_path):
    uri = f'file:{urllib.parse.quote(db_path)}?mode=ro'
    with sqlite3.connect(uri, uri=True) as conn:
        rows = conn.execute("select sub_id from clients where enable = 1 and sub_id != ''").fetchall()
    if len(rows) != 1:
        raise ValueError('expected exactly one enabled subscription client')
    return rows[0][0]
```

The handler must return 503 without body details when upstream parsing, validation, or source lookup fails.

- [ ] **Step 4: Run targeted tests and verify GREEN**

Run: `python3 -m unittest tests/config_generator.test.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add generator/config_generator.py generator/config-generator.service tests/config_generator.test.py
git commit -m "feat: serve generated subscription locally"
```

### Task 3: Publish the secret Caddy route and deployment automation

**Files:**
- Create: `bwg-phase7.2-config-generator.sh`
- Create: `phase7.2-Caddyfile`
- Modify: `phase5-reverse-proxy.compose.yml`
- Create: `tests/phase7.2-config-generator-artifacts.test.sh`
- Modify: `docs/Phase7-Publish-Nextin.md`

**Interfaces:**
- Consumes: `/etc/bwg-config-generator.env` with `CONFIG_GENERATOR_PATH` and non-secret local generator options.
- Produces: `/usr/local/lib/bwg-config-generator/config_generator.py`
- Produces: `https://sub.jijunyang.com/configs/<random-id>.yaml`

- [ ] **Step 1: Write failing deployment-artifact tests**

```bash
rg -Fq 'secrets.token_hex(32)' bwg-phase7.2-config-generator.sh
rg -Fq '127.0.0.1:3011' generator/config-generator.service
rg -Fq 'reverse_proxy 127.0.0.1:3011' phase7.2-Caddyfile
! rg -Fq 'handle_path /configs/*' phase7.2-Caddyfile
```

- [ ] **Step 2: Run test and verify RED**

Run: `bash tests/phase7.2-config-generator-artifacts.test.sh`

Expected: FAIL because Phase 7.2 artifacts do not exist.

- [ ] **Step 3: Implement idempotent deployment script**

The script generates a 32-byte random path once, stores it mode `0600` in `/etc/bwg-config-generator.env`, validates Caddy and Python dependencies before changing services, backs up every replaced file, creates a restricted systemd unit, reloads it, updates Caddy, and prints the final URL exactly once only to the interactive operator.

- [ ] **Step 4: Run artifact test and verify GREEN**

Run: `bash tests/phase7.2-config-generator-artifacts.test.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bwg-phase7.2-config-generator.sh phase7.2-Caddyfile phase5-reverse-proxy.compose.yml tests/phase7.2-config-generator-artifacts.test.sh docs/Phase7-Publish-Nextin.md
git commit -m "feat: publish generated single subscription"
```

### Task 4: Validate live deployment and routing contracts

**Files:**
- Create: `tests/phase7.2-live-config-generator.test.sh`
- Modify: `docs/Phase7-Publish-Nextin.md`

**Interfaces:**
- Consumes: the root-only generated URL environment file on the VPS.
- Produces: live validation output without echoing the secret URL, subscription ID, UUID, or node credentials.

- [ ] **Step 1: Write the failing live-validation test**

```bash
python3 - "$body" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
assert data['x-config-version'] == 1
assert data['x-generator'] == 'ConfigGenerator'
assert data['proxies']
assert any(rule == 'RULE-SET,openai,PROXY' for rule in data['rules'])
assert any(rule == 'RULE-SET,baidu,DIRECT' for rule in data['rules'])
assert any(rule == 'RULE-SET,netflix,PROXY' for rule in data['rules'])
PY
```

- [ ] **Step 2: Run it before deployment and verify RED**

Run: `sudo /usr/local/sbin/bwg-phase7.2-live-validate`

Expected: FAIL because the final service is not deployed.

- [ ] **Step 3: Implement the validator and deploy**

Deploy with the generated Phase 7.2 script, request the final URL locally through Caddy, validate all metadata and the full YAML structure, then import that sole URL in Nextin.

- [ ] **Step 4: Verify runtime rule hits**

Use the Nextin controller `connections` API after requests to each host; assert that `chatgpt.com` has `rulePayload=openai`, `baidu.com` has a DIRECT rule payload, and `netflix.com` has `rulePayload=netflix`. No accepted record may have `rule=Match` for those hosts.

- [ ] **Step 5: Commit docs and tests**

```bash
git add tests/phase7.2-live-config-generator.test.sh docs/Phase7-Publish-Nextin.md
git commit -m "test: verify single subscription routing"
```
