import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from custom_rules.server import INDEX_HTML, create_server


class CustomRulesHttpTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.server = create_server(str(Path(self.directory.name) / "custom-rules.db"))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.directory.cleanup()

    def request(self, method, path, body=None):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        headers = {"Content-Type": "application/json"} if body is not None else {}
        connection.request(method, path, body=json.dumps(body) if body is not None else None, headers=headers)
        response = connection.getresponse()
        payload = response.read()
        connection.close()
        return response.status, response.getheader("Content-Type"), payload

    def test_serves_management_page_and_rule_type_contract(self):
        status, content_type, page = self.request("GET", "/")
        self.assertEqual(200, status)
        self.assertIn("text/html", content_type)
        self.assertIn(b"Custom Rules", page)

        status, content_type, document = self.request("GET", "/api/v1/rule-types")
        self.assertEqual(200, status)
        self.assertIn("application/json", content_type)
        self.assertEqual("DOMAIN-SUFFIX", json.loads(document)["rule_types"][1])

    def test_management_page_keeps_the_form_reset_method_available(self):
        self.assertIn('id="reset-button"', INDEX_HTML)
        self.assertIn("$('reset-button').addEventListener", INDEX_HTML)
        self.assertNotIn('id="reset"', INDEX_HTML)

    def test_creates_searches_and_toggles_a_rule(self):
        status, _, document = self.request(
            "POST",
            "/api/v1/rules",
            {"rule_type": "DOMAIN", "content": "example.com", "policy": "PROXY", "enabled": True, "remark": "example"},
        )
        self.assertEqual(201, status)
        rule = json.loads(document)["rule"]

        status, _, document = self.request("GET", "/api/v1/rules?q=example")
        self.assertEqual(200, status)
        self.assertEqual([rule["id"]], [item["id"] for item in json.loads(document)["rules"]])

        status, _, document = self.request(
            "PATCH",
            f"/api/v1/rules/{rule['id']}",
            {**rule, "enabled": False},
        )
        self.assertEqual(200, status)
        self.assertFalse(json.loads(document)["rule"]["enabled"])

    def test_reorders_and_deletes_rules(self):
        first = json.loads(self.request("POST", "/api/v1/rules", {"rule_type": "DOMAIN", "content": "one.example", "policy": "DIRECT", "enabled": True, "remark": ""})[2])["rule"]
        second = json.loads(self.request("POST", "/api/v1/rules", {"rule_type": "DOMAIN", "content": "two.example", "policy": "PROXY", "enabled": True, "remark": ""})[2])["rule"]

        status, _, _ = self.request("PUT", "/api/v1/rules/order", {"ids": [second["id"], first["id"]]})
        self.assertEqual(204, status)
        rules = json.loads(self.request("GET", "/api/v1/rules")[2])["rules"]
        self.assertEqual([second["id"], first["id"]], [item["id"] for item in rules])

        status, _, _ = self.request("DELETE", f"/api/v1/rules/{rules[0]['id']}?revision={rules[0]['revision']}")
        self.assertEqual(204, status)


if __name__ == "__main__":
    unittest.main()
