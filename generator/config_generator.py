#!/usr/bin/env python3
"""Build deterministic complete Mihomo configurations from 3X-UI nodes."""

import copy
import argparse
import hashlib
import json
import re
import sqlite3
import sys
import urllib.request
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from custom_rules.validation import render_rule, validate_rule


REQUIRED_RULES = (
    "RULE-SET,openai,AI-US",
    "RULE-SET,claude,AI-US",
    "RULE-SET,anthropic,AI-US",
    "RULE-SET,gemini,AI-US",
    "RULE-SET,perplexity,AI-US",
    "RULE-SET,netflix,PROXY",
    "RULE-SET,baidu,DIRECT",
    "MATCH,PROXY",
)
AI_US_RULES = REQUIRED_RULES[:5]

PUBLIC_RULES_BASE_URL = "https://sub.jijunyang.com/rules"
RULE_FILE_PATTERN = re.compile(r"^/rules/([a-z0-9-]+)\.yaml$")


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def read_single_sub_id(db_path: str) -> str:
    database_uri = Path(db_path).resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(database_uri, uri=True) as connection:
        rows = connection.execute(
            "select sub_id from clients where enable = 1 and sub_id is not null and sub_id != ''"
        ).fetchall()
    if len(rows) != 1:
        raise ValueError("expected exactly one enabled subscription client")
    return rows[0][0]


def read_enabled_custom_rules(db_path: str | None) -> list[dict]:
    if not db_path:
        return []
    database_uri = Path(db_path).resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(database_uri, uri=True) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            """select id, rule_type, content, policy
            from custom_rules where enabled=1 order by sort_order asc, id asc"""
        ).fetchall()
    return [dict(row) for row in rows]


def extract_proxies(source_config: dict) -> list[dict]:
    proxies = source_config.get("proxies")
    if not isinstance(proxies, list) or not proxies:
        raise ValueError("3X-UI source configuration has no proxies")
    if not all(isinstance(proxy, dict) and proxy.get("name") for proxy in proxies):
        raise ValueError("3X-UI source configuration has invalid proxies")
    names = [proxy["name"] for proxy in proxies]
    if len(set(names)) != len(names):
        raise ValueError("3X-UI source configuration has duplicate proxy names")
    return proxies


def load_yaml(path: str) -> dict:
    import yaml

    with open(path, "r", encoding="utf-8") as handle:
        document = yaml.safe_load(handle)
    if not isinstance(document, dict):
        raise ValueError("YAML document must be a mapping")
    return document


def load_additional_proxies(path: str) -> list[dict]:
    """Load an explicitly mounted production node source."""
    return extract_proxies(load_yaml(path))


def merge_proxies(*proxy_sets: list[dict]) -> list[dict]:
    """Combine independent node sources under the existing name-uniqueness contract."""
    return extract_proxies({"proxies": [proxy for proxy_set in proxy_sets for proxy in proxy_set]})


def fetch_source_config(url: str, timeout_seconds: int) -> dict:
    import yaml

    request = urllib.request.Request(
        url,
        headers={"Accept": "application/yaml", "Host": "sub.jijunyang.com"},
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        document = yaml.safe_load(response.read())
    if not isinstance(document, dict):
        raise ValueError("3X-UI returned an invalid Clash YAML document")
    return document


def render_yaml(config: dict) -> bytes:
    import yaml

    return yaml.safe_dump(config, allow_unicode=True, sort_keys=False).encode("utf-8")


def generate_document(
    template_path: str,
    db_path: str,
    timeout_seconds: int = 10,
    additional_proxies_path: str | None = None,
    custom_rules_db_path: str | None = None,
) -> bytes:
    sub_id = read_single_sub_id(db_path)
    source = fetch_source_config(f"http://127.0.0.1:2096/clash/{sub_id}", timeout_seconds)
    proxies = extract_proxies(source)
    if additional_proxies_path:
        proxies = merge_proxies(proxies, load_additional_proxies(additional_proxies_path))
    config = build_config(
        load_yaml(template_path),
        proxies,
        datetime.now(timezone.utc),
        custom_rules=read_enabled_custom_rules(custom_rules_db_path),
    )
    return render_yaml(config)


def build_ios_slim_config(template: dict, proxies: list[dict], generated_at: datetime) -> dict:
    """Build a Nextin iPhone profile with only explicitly allowed live nodes."""
    config = copy.deepcopy(template)
    allowed_names = config.pop("x-proxy-allowlist", [])
    if not isinstance(allowed_names, list) or not allowed_names or not all(isinstance(name, str) for name in allowed_names):
        raise ValueError("iPhone template must declare a proxy allowlist")
    available = {proxy["name"]: copy.deepcopy(proxy) for proxy in proxies}
    missing = [name for name in allowed_names if name not in available]
    if missing:
        raise ValueError(f"iPhone template nodes unavailable: {', '.join(missing)}")
    selected_proxies = sorted((available[name] for name in allowed_names), key=lambda item: item["name"])
    config["proxies"] = selected_proxies
    config["x-config-version"] = 1
    config["x-generated-at"] = generated_at.strftime("%Y-%m-%dT%H:%M:%SZ")
    config["x-generator"] = "ConfigGenerator-iPhoneSlim"
    config["x-template-sha256"] = canonical_sha256(template)
    config["x-proxies-sha256"] = canonical_sha256(selected_proxies)
    validate_ios_slim_config(config, allowed_names)
    return config


def validate_ios_slim_config(config: dict, allowed_names: list[str]) -> None:
    if config.get("mode") != "rule":
        raise ValueError("iPhone generated configuration must use rule mode")
    if config.get("dns", {}).get("enhanced-mode") != "fake-ip":
        raise ValueError("iPhone generated configuration must enable fake-ip")
    if config.get("rule-providers"):
        raise ValueError("iPhone generated configuration must not include rule providers")
    if [proxy.get("name") for proxy in config.get("proxies", [])] != sorted(allowed_names):
        raise ValueError("iPhone generated configuration has unexpected proxies")
    groups = config.get("proxy-groups", [])
    if len(groups) != 1 or groups[0].get("name") != "PROXY" or groups[0].get("type") != "select":
        raise ValueError("iPhone generated configuration must contain one manual PROXY group")
    group_nodes = groups[0].get("proxies", [])
    if group_nodes != [*allowed_names, "DIRECT"]:
        raise ValueError("iPhone PROXY group must expose only selected nodes and DIRECT")
    rules = config.get("rules", [])
    if not rules or rules[-1] != "MATCH,PROXY":
        raise ValueError("iPhone generated configuration must end with MATCH,PROXY")


def generate_ios_slim_document(
    template_path: str,
    db_path: str,
    timeout_seconds: int = 10,
    additional_proxies_path: str | None = None,
) -> bytes:
    sub_id = read_single_sub_id(db_path)
    source = fetch_source_config(f"http://127.0.0.1:2096/clash/{sub_id}", timeout_seconds)
    proxies = extract_proxies(source)
    if additional_proxies_path:
        proxies = merge_proxies(proxies, load_additional_proxies(additional_proxies_path))
    config = build_ios_slim_config(load_yaml(template_path), proxies, datetime.now(timezone.utc))
    return render_yaml(config)


class GeneratorHandler(BaseHTTPRequestHandler):
    template_path = ""
    db_path = ""
    ios_template_path = "/etc/bwg-config-generator/ios-template.yaml"
    ios_slim_template_path = "/etc/bwg-config-generator/iphone-us-hk.yaml"
    additional_proxies_path: str | None = None
    custom_rules_db_path: str | None = None

    def do_GET(self) -> None:
        if self.path.startswith("/iphone/"):
            self.serve_ios_slim_config()
            return
        if self.path.startswith("/templates/"):
            self.serve_ios_template()
            return
        rule_match = RULE_FILE_PATTERN.fullmatch(self.path)
        if rule_match:
            self.serve_rule_provider(rule_match.group(1))
            return
        if self.path != "/":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            document = generate_document(
                self.template_path,
                self.db_path,
                additional_proxies_path=self.additional_proxies_path,
                custom_rules_db_path=self.custom_rules_db_path,
            )
        except Exception as error:
            print(f"generation failed: {type(error).__name__}", file=sys.stderr, flush=True)
            self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, type(error).__name__)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/yaml; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(document)))
        self.end_headers()
        self.wfile.write(document)

    def serve_ios_slim_config(self) -> None:
        try:
            document = generate_ios_slim_document(
                self.ios_slim_template_path,
                self.db_path,
                additional_proxies_path=self.additional_proxies_path,
            )
        except Exception as error:
            print(f"iPhone generation failed: {type(error).__name__}", file=sys.stderr, flush=True)
            self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, type(error).__name__)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/yaml; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(document)))
        self.end_headers()
        self.wfile.write(document)

    def serve_ios_template(self) -> None:
        try:
            document = open(self.ios_template_path, "rb").read()
            if not document:
                raise ValueError("empty iOS template")
        except Exception as error:
            print(f"iOS template failed: {type(error).__name__}", file=sys.stderr, flush=True)
            self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, type(error).__name__)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/yaml; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(document)))
        self.end_headers()
        self.wfile.write(document)

    def serve_rule_provider(self, provider_name: str) -> None:
        try:
            template = load_yaml(self.template_path)
            provider = template.get("rule-providers", {}).get(provider_name, {})
            url = provider.get("url")
            if provider.get("type") != "http" or not isinstance(url, str) or not url.startswith("https://"):
                raise ValueError("invalid rule provider")
            request = urllib.request.Request(url, headers={"Accept": "application/yaml"})
            with urllib.request.urlopen(request, timeout=20) as response:
                document = response.read()
            if not document:
                raise ValueError("empty rule provider")
        except Exception as error:
            print(f"rule provider failed: {provider_name} {type(error).__name__}", file=sys.stderr, flush=True)
            self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, type(error).__name__)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/yaml; charset=utf-8")
        self.send_header("Cache-Control", "public, max-age=3600")
        self.send_header("Content-Length", str(len(document)))
        self.end_headers()
        self.wfile.write(document)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def serve(
    template_path: str,
    db_path: str,
    port: int = 3011,
    additional_proxies_path: str | None = None,
    ios_slim_template_path: str | None = None,
    custom_rules_db_path: str | None = None,
) -> None:
    GeneratorHandler.template_path = template_path
    GeneratorHandler.db_path = db_path
    GeneratorHandler.additional_proxies_path = additional_proxies_path
    GeneratorHandler.custom_rules_db_path = custom_rules_db_path
    if ios_slim_template_path:
        GeneratorHandler.ios_slim_template_path = ios_slim_template_path
    ThreadingHTTPServer(("127.0.0.1", port), GeneratorHandler).serve_forever()


def validate_config(config: dict) -> None:
    if not config.get("proxies"):
        raise ValueError("generated configuration has no proxies")
    if config.get("mode") != "rule":
        raise ValueError("generated configuration must use rule mode")
    if config.get("dns", {}).get("enhanced-mode") != "fake-ip":
        raise ValueError("generated configuration must enable fake-ip")

    rules = config.get("rules", [])
    for rule in REQUIRED_RULES:
        if rule not in rules:
            raise ValueError(f"generated configuration is missing {rule}")

    match_index = rules.index("MATCH,PROXY")
    for rule in REQUIRED_RULES[:-1]:
        if rules.index(rule) > match_index:
            raise ValueError(f"{rule} must precede MATCH,PROXY")


def normalize_custom_rules(custom_rules: list[dict]) -> list[dict]:
    normalized = []
    for item in custom_rules:
        rule = validate_rule(item["rule_type"], item["content"], item["policy"])
        normalized.append(
            {
                "id": item.get("id"),
                "rule_type": rule.rule_type,
                "content": rule.content,
                "policy": rule.policy,
                "rendered_rule": render_rule(rule),
            }
        )
    return normalized


def order_rules(base_rules: list[str], custom_rules: list[dict]) -> list[str]:
    ai_rules = [rule for rule in base_rules if rule in AI_US_RULES]
    if ai_rules != list(AI_US_RULES):
        raise ValueError("generated configuration is missing the complete AI-US routing contract")
    remaining_rules = [rule for rule in base_rules if rule not in AI_US_RULES]
    return [item["rendered_rule"] for item in custom_rules] + ai_rules + remaining_rules


def build_config(
    template: dict,
    proxies: list[dict],
    generated_at: datetime,
    custom_rules: list[dict] | None = None,
) -> dict:
    config = copy.deepcopy(template)
    normalized_custom_rules = normalize_custom_rules(custom_rules or [])
    sorted_proxies = sorted(copy.deepcopy(proxies), key=lambda item: item["name"])
    for provider_name, provider in config.get("rule-providers", {}).items():
        if provider.get("type") == "http" and provider.get("url"):
            provider["url"] = f"{PUBLIC_RULES_BASE_URL}/{provider_name}.yaml"
            provider.pop("proxy", None)
    config["proxies"] = sorted_proxies
    config["x-config-version"] = 1
    config["x-generated-at"] = generated_at.strftime("%Y-%m-%dT%H:%M:%SZ")
    config["x-generator"] = "ConfigGenerator"
    config["x-template-sha256"] = canonical_sha256(template)
    config["x-proxies-sha256"] = canonical_sha256(sorted_proxies)
    config["x-custom-rules-count"] = len(normalized_custom_rules)
    config["x-custom-rules-sha256"] = canonical_sha256(normalized_custom_rules)
    config["rules"] = order_rules(config.get("rules", []), normalized_custom_rules)
    validate_config(config)
    return config


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template_path")
    parser.add_argument("db_path")
    parser.add_argument("--port", type=int, default=3011)
    parser.add_argument("--additional-proxies")
    parser.add_argument("--ios-slim-template")
    parser.add_argument("--custom-rules-db")
    arguments = parser.parse_args()
    serve(
        arguments.template_path,
        arguments.db_path,
        arguments.port,
        arguments.additional_proxies,
        arguments.ios_slim_template,
        arguments.custom_rules_db,
    )
