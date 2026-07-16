import sqlite3
import tempfile
import unittest
from pathlib import Path

from custom_rules.store import CustomRuleStore
from custom_rules.validation import RuleValidationError, render_rule, validate_rule


class CustomRulesTests(unittest.TestCase):
    def test_validate_and_render_supported_rules(self):
        self.assertEqual(
            "DOMAIN-SUFFIX,chatgpt.com,DIRECT",
            render_rule(validate_rule("DOMAIN-SUFFIX", "chatgpt.com", "DIRECT")),
        )
        self.assertEqual(
            "IP-CIDR,203.0.113.0/24,REJECT,no-resolve",
            render_rule(validate_rule("IP-CIDR", "203.0.113.0/24", "REJECT")),
        )

    def test_rejects_unapproved_type_and_rule_injection(self):
        with self.assertRaisesRegex(RuleValidationError, "unsupported rule type"):
            validate_rule("GEOSITE", "openai", "AI-US")
        with self.assertRaisesRegex(RuleValidationError, "must not contain commas"):
            validate_rule("DOMAIN", "safe.example,DIRECT", "PROXY")

    def test_store_persists_enabled_rules_in_priority_order(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "custom-rules.db"
            store = CustomRuleStore(str(database))
            later = store.create("DOMAIN", "later.example", "PROXY", True, "later")
            first = store.create("DOMAIN-SUFFIX", "first.example", "DIRECT", True, "first")
            disabled = store.create("DOMAIN", "off.example", "REJECT", False, "off")

            store.replace_order([first["id"], later["id"], disabled["id"]])

            self.assertEqual(
                ["DOMAIN-SUFFIX,first.example,DIRECT", "DOMAIN,later.example,PROXY"],
                [item["rendered_rule"] for item in store.list_enabled()],
            )

            with sqlite3.connect(database) as connection:
                self.assertEqual("delete", connection.execute("pragma journal_mode").fetchone()[0])

    def test_store_edits_searches_toggles_and_deletes_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            store = CustomRuleStore(str(Path(directory) / "custom-rules.db"))
            created = store.create("DOMAIN", "example.com", "PROXY", True, "first note")

            updated = store.update(
                created["id"],
                rule_type="DOMAIN-SUFFIX",
                content="example.com",
                policy="DIRECT",
                enabled=False,
                remark="updated note",
                revision=created["revision"],
            )

            self.assertFalse(updated["enabled"])
            self.assertEqual("DOMAIN-SUFFIX,example.com,DIRECT", updated["rendered_rule"])
            self.assertEqual([updated["id"]], [item["id"] for item in store.list_rules(query="updated")])
            self.assertEqual([], store.list_enabled())

            store.delete(updated["id"], revision=updated["revision"])
            self.assertEqual([], store.list_rules())


if __name__ == "__main__":
    unittest.main()
