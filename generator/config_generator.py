#!/usr/bin/env python3
"""Build deterministic complete Mihomo configurations from 3X-UI nodes."""

import copy
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


REQUIRED_RULES = (
    "RULE-SET,openai,PROXY",
    "RULE-SET,netflix,PROXY",
    "RULE-SET,baidu,DIRECT",
    "MATCH,PROXY",
)

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


def generate_document(template_path: str, db_path: str, timeout_seconds: int = 10) -> bytes:
    sub_id = read_single_sub_id(db_path)
    source = fetch_source_config(f"http://127.0.0.1:2096/clash/{sub_id}", timeout_seconds)
    config = build_config(load_yaml(template_path), extract_proxies(source), datetime.now(timezone.utc))
    return render_yaml(config)


class GeneratorHandler(BaseHTTPRequestHandler):
    template_path = ""
    db_path = ""
    ios_template_path = "/etc/bwg-config-generator/ios-template.yaml"

    def do_GET(self) -> None:
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
            document = generate_document(self.template_path, self.db_path)
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


def serve(template_path: str, db_path: str, port: int = 3011) -> None:
    GeneratorHandler.template_path = template_path
    GeneratorHandler.db_path = db_path
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


def build_config(template: dict, proxies: list[dict], generated_at: datetime) -> dict:
    config = copy.deepcopy(template)
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
    validate_config(config)
    return config


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: config_generator.py TEMPLATE_PATH XUI_DB_PATH")
    serve(sys.argv[1], sys.argv[2])
