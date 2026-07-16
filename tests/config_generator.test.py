import unittest
import sqlite3
import sys
import tempfile
import types
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

from generator.config_generator import build_config, build_ios_slim_config, extract_proxies, fetch_source_config, read_single_sub_id, validate_config


FIXED_TIME = datetime(2026, 7, 14, 13, 52, 18, tzinfo=timezone.utc)
TEMPLATE = {
    "mode": "rule",
    "dns": {"enable": True, "enhanced-mode": "fake-ip"},
    "proxy-groups": [{"name": "PROXY", "type": "select", "include-all-proxies": True}],
    "rule-providers": {"openai": {"type": "http"}, "baidu": {"type": "http"}, "netflix": {"type": "http"}},
    "rules": [
        "RULE-SET,openai,AI-US",
        "RULE-SET,claude,AI-US",
        "RULE-SET,anthropic,AI-US",
        "RULE-SET,gemini,AI-US",
        "RULE-SET,perplexity,AI-US",
        "RULE-SET,netflix,PROXY",
        "RULE-SET,baidu,DIRECT",
        "MATCH,PROXY",
    ],
}
PROXY = {"name": "node-a", "type": "vless", "server": "example.test", "port": 443}


class ConfigGeneratorTests(unittest.TestCase):
    def test_ios_slim_config_keeps_fake_ip_two_nodes_and_no_remote_rules(self):
        template = {
            "mode": "rule",
            "dns": {"enable": True, "enhanced-mode": "fake-ip"},
            "x-proxy-allowlist": ["HS-US-01-Bandwagon", "HS-HK-01-Lisa"],
            "proxy-groups": [{"name": "PROXY", "type": "select", "proxies": ["HS-US-01-Bandwagon", "HS-HK-01-Lisa", "DIRECT"]}],
            "rules": ["DOMAIN-SUFFIX,local,DIRECT", "MATCH,PROXY"],
        }

        config = build_ios_slim_config(
            template,
            [
                {**PROXY, "name": "HS-US-01-Bandwagon"},
                {**PROXY, "name": "HS-HK-01-Lisa"},
            ],
            FIXED_TIME,
        )

        self.assertEqual(["HS-HK-01-Lisa", "HS-US-01-Bandwagon"], [item["name"] for item in config["proxies"]])
        self.assertEqual("fake-ip", config["dns"]["enhanced-mode"])
        self.assertNotIn("rule-providers", config)
        self.assertNotIn("AUTO", [group["name"] for group in config["proxy-groups"]])
        self.assertNotIn("AI-US", [group["name"] for group in config["proxy-groups"]])
    def test_build_injects_sorted_nodes_and_required_metadata(self):
        config = build_config(TEMPLATE, [{**PROXY, "name": "node-z"}, PROXY], FIXED_TIME)

        self.assertEqual(["node-a", "node-z"], [item["name"] for item in config["proxies"]])
        self.assertEqual(1, config["x-config-version"])
        self.assertEqual("2026-07-14T13:52:18Z", config["x-generated-at"])
        self.assertEqual("ConfigGenerator", config["x-generator"])
        self.assertRegex(config["x-template-sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(config["x-proxies-sha256"], r"^[0-9a-f]{64}$")

    def test_node_change_only_changes_proxy_hash(self):
        first = build_config(TEMPLATE, [PROXY], FIXED_TIME)
        second = build_config(TEMPLATE, [{**PROXY, "name": "node-b"}], FIXED_TIME)

        self.assertEqual(first["x-template-sha256"], second["x-template-sha256"])
        self.assertNotEqual(first["x-proxies-sha256"], second["x-proxies-sha256"])

    def test_source_node_endpoints_are_preserved(self):
        config = build_config(
            TEMPLATE,
            [{**PROXY, "server": "sub.jijunyang.com"}, {**PROXY, "name": "external", "server": "jp.example"}],
            FIXED_TIME,
        )

        servers = {item["name"]: item["server"] for item in config["proxies"]}
        self.assertEqual("sub.jijunyang.com", servers["node-a"])
        self.assertEqual("jp.example", servers["external"])

    def test_http_rule_providers_are_served_from_the_subscription_domain(self):
        template = {
            **TEMPLATE,
            "rule-providers": {
                "openai": {"type": "http", "url": "https://upstream.example/openai.yaml", "proxy": "PROXY"},
                "local": {"type": "file", "path": "./local.yaml"},
            },
        }

        config = build_config(template, [PROXY], FIXED_TIME)

        self.assertEqual("https://sub.jijunyang.com/rules/openai.yaml", config["rule-providers"]["openai"]["url"])
        self.assertNotIn("proxy", config["rule-providers"]["openai"])
        self.assertEqual("file", config["rule-providers"]["local"]["type"])

    def test_ios_template_is_nextin_local_and_has_no_remote_rule_provider(self):
        template = (Path(__file__).parents[1] / "templates" / "nextin-ios-template.yaml").read_text(encoding="utf-8")

        self.assertIn("mode: subscription-template", template)
        self.assertIn("proxies: []", template)
        self.assertNotIn("rule-providers:", template)
        self.assertIn("DOMAIN-SUFFIX,chatgpt.com,PROXY", template)

    def test_validation_rejects_missing_explicit_routing_contract(self):
        invalid = {**TEMPLATE, "proxies": [PROXY], "rules": ["MATCH,PROXY"]}

        with self.assertRaisesRegex(ValueError, "RULE-SET,openai,AI-US"):
            validate_config(invalid)

    def test_validation_accepts_the_formal_ai_us_routing_contract(self):
        formal_ai_us = {
            **TEMPLATE,
            "proxies": [{**PROXY, "name": "HS-US-01-Bandwagon"}, {**PROXY, "name": "HS-HK-01-Lisa"}],
            "rules": [
                "RULE-SET,openai,AI-US",
                "RULE-SET,claude,AI-US",
                "RULE-SET,anthropic,AI-US",
                "RULE-SET,gemini,AI-US",
                "RULE-SET,perplexity,AI-US",
                "RULE-SET,netflix,PROXY",
                "RULE-SET,baidu,DIRECT",
                "MATCH,PROXY",
            ],
        }

        validate_config(formal_ai_us)

    def test_read_single_sub_id_uses_only_enabled_client(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "x-ui.db"
            with sqlite3.connect(database) as connection:
                connection.execute("create table clients (enable integer, sub_id text)")
                connection.execute("insert into clients values (1, 'only-enabled-id')")
                connection.execute("insert into clients values (0, 'disabled-id')")

            self.assertEqual("only-enabled-id", read_single_sub_id(str(database)))

    def test_read_single_sub_id_rejects_zero_or_multiple_enabled_clients(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "x-ui.db"
            with sqlite3.connect(database) as connection:
                connection.execute("create table clients (enable integer, sub_id text)")

            with self.assertRaisesRegex(ValueError, "exactly one"):
                read_single_sub_id(str(database))

    def test_extract_proxies_rejects_missing_and_duplicate_nodes(self):
        with self.assertRaisesRegex(ValueError, "no proxies"):
            extract_proxies({})
        with self.assertRaisesRegex(ValueError, "duplicate"):
            extract_proxies({"proxies": [PROXY, PROXY]})

    def test_extract_proxies_only_returns_3x_ui_nodes(self):
        source = {"proxies": [PROXY], "rules": ["MATCH,DIRECT"], "dns": {"enable": False}}

        self.assertEqual([PROXY], extract_proxies(source))

    def test_script_entrypoint_is_after_builder_definition(self):
        source = (Path(__file__).parents[1] / "generator" / "config_generator.py").read_text(encoding="utf-8")

        self.assertGreater(source.index('if __name__ == "__main__":'), source.index("def build_config("))

    def test_3x_ui_source_request_uses_public_subscription_host(self):
        class Response:
            def read(self):
                return b"proxies: []\n"

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

        yaml_module = types.SimpleNamespace(safe_load=lambda _body: {"proxies": []})
        with patch.dict(sys.modules, {"yaml": yaml_module}), patch(
            "generator.config_generator.urllib.request.urlopen", return_value=Response()
        ) as open_url:
            fetch_source_config("http://127.0.0.1:2096/clash/example", 10)

        request = open_url.call_args.args[0]
        self.assertEqual("sub.jijunyang.com", request.get_header("Host"))

    def test_routing_template_uses_nextin_compatible_fake_ip_dns(self):
        template = (Path(__file__).parents[1] / "templates" / "nextin-smart-routing.yaml").read_text(encoding="utf-8")

        self.assertIn("enhanced-mode: fake-ip", template)
        self.assertIn("https://dns.alidns.com/dns-query", template)
        self.assertIn("fallback-filter:", template)
        self.assertNotIn("proxy-server-nameserver:", template)
        self.assertEqual(29, template.count("proxy: PROXY"))

    def test_formal_template_routes_only_named_ai_services_to_single_us_group(self):
        template = (Path(__file__).parents[1] / "templates" / "nextin-smart-routing.yaml").read_text(encoding="utf-8")

        self.assertIn("  - name: AI-US\n    type: select\n    proxies:\n      - HS-US-01-Bandwagon", template)
        self.assertNotIn("HS-SG-01-Akile", template)
        for rule in (
            "RULE-SET,openai,AI-US",
            "RULE-SET,claude,AI-US",
            "RULE-SET,anthropic,AI-US",
            "RULE-SET,gemini,AI-US",
            "RULE-SET,perplexity,AI-US",
        ):
            self.assertIn(rule, template)
        self.assertIn(
            'gemini: {type: http, behavior: domain, format: yaml, interval: 86400, path: ./rules/gemini.yaml, url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Gemini/Gemini.yaml", proxy: PROXY}',
            template,
        )
        self.assertIn(
            'perplexity: {type: http, behavior: domain, format: yaml, interval: 86400, path: ./rules/perplexity.yaml, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/perplexity.yaml", proxy: PROXY}',
            template,
        )
        for rule in (
            "RULE-SET,youtube,PROXY",
            "RULE-SET,netflix,PROXY",
            "RULE-SET,disney,PROXY",
            "RULE-SET,apple-tvplus,PROXY",
            "RULE-SET,primevideo,PROXY",
        ):
            self.assertIn(rule, template)


if __name__ == "__main__":
    unittest.main()
