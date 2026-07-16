from dataclasses import dataclass
from ipaddress import ip_network
import re


ALLOWED_RULE_TYPES = (
    "DOMAIN",
    "DOMAIN-SUFFIX",
    "DOMAIN-KEYWORD",
    "IP-CIDR",
    "IP-CIDR6",
    "PROCESS-NAME",
    "GEOIP",
)
ALLOWED_POLICIES = ("DIRECT", "PROXY", "AI-US", "REJECT")


class RuleValidationError(ValueError):
    pass


@dataclass(frozen=True)
class RuleSpec:
    rule_type: str
    content: str
    policy: str


def validate_rule(rule_type: str, content: str, policy: str) -> RuleSpec:
    if rule_type not in ALLOWED_RULE_TYPES:
        raise RuleValidationError("unsupported rule type")
    if policy not in ALLOWED_POLICIES:
        raise RuleValidationError("unsupported policy")
    if not isinstance(content, str):
        raise RuleValidationError("content must be text")
    content = content.strip()
    if not content:
        raise RuleValidationError("content is required")
    if any(character in content for character in (",", "\n", "\r")):
        raise RuleValidationError("content must not contain commas or line breaks")
    if rule_type in ("IP-CIDR", "IP-CIDR6"):
        network = ip_network(content, strict=True)
        expected_version = 4 if rule_type == "IP-CIDR" else 6
        if network.version != expected_version:
            raise RuleValidationError("CIDR version does not match rule type")
        content = str(network)
    elif rule_type == "GEOIP":
        if not re.fullmatch(r"[A-Za-z]{2}", content):
            raise RuleValidationError("GEOIP content must be a two-letter country code")
        content = content.upper()
    elif any(character.isspace() for character in content):
        raise RuleValidationError("content must not contain whitespace")
    return RuleSpec(rule_type=rule_type, content=content, policy=policy)


def render_rule(rule: RuleSpec) -> str:
    suffix = ",no-resolve" if rule.rule_type in ("IP-CIDR", "IP-CIDR6", "GEOIP") else ""
    return f"{rule.rule_type},{rule.content},{rule.policy}{suffix}"
