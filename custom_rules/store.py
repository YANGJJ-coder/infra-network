import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from custom_rules.validation import render_rule, validate_rule


SCHEMA = """
create table if not exists custom_rules (
  id integer primary key,
  rule_type text not null,
  content text not null,
  policy text not null,
  enabled integer not null check (enabled in (0, 1)),
  remark text not null default '',
  sort_order integer not null,
  revision integer not null default 1,
  created_at text not null,
  updated_at text not null,
  unique (rule_type, content)
);
"""


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class CustomRuleStore:
    def __init__(self, database_path: str):
        self.database_path = database_path
        Path(database_path).parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute("pragma journal_mode=delete")
            connection.execute("pragma foreign_keys=on")
            connection.executescript(SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        connection.execute("pragma busy_timeout=5000")
        return connection

    def create(self, rule_type: str, content: str, policy: str, enabled: bool, remark: str) -> dict:
        rule = validate_rule(rule_type, content, policy)
        remark = remark.strip()
        if "\n" in remark or "\r" in remark:
            raise ValueError("remark must be one line")
        now = utc_now()
        with self._connect() as connection:
            sort_order = connection.execute("select coalesce(max(sort_order), 0) + 100 from custom_rules").fetchone()[0]
            cursor = connection.execute(
                """insert into custom_rules
                (rule_type, content, policy, enabled, remark, sort_order, revision, created_at, updated_at)
                values (?, ?, ?, ?, ?, ?, 1, ?, ?)""",
                (rule.rule_type, rule.content, rule.policy, int(enabled), remark, sort_order, now, now),
            )
            row = connection.execute("select * from custom_rules where id=?", (cursor.lastrowid,)).fetchone()
        return self._serialize(row)

    def list_enabled(self) -> list[dict]:
        with self._connect() as connection:
            rows = connection.execute(
                "select * from custom_rules where enabled=1 order by sort_order asc, id asc"
            ).fetchall()
        return [self._serialize(row) for row in rows]

    def list_rules(self, query: str = "") -> list[dict]:
        query = query.strip()
        with self._connect() as connection:
            if query:
                escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
                rows = connection.execute(
                    """select * from custom_rules
                    where content like ? escape '\\' or remark like ? escape '\\'
                    order by sort_order asc, id asc""",
                    (f"%{escaped}%", f"%{escaped}%"),
                ).fetchall()
            else:
                rows = connection.execute("select * from custom_rules order by sort_order asc, id asc").fetchall()
        return [self._serialize(row) for row in rows]

    def update(
        self,
        rule_id: int,
        *,
        rule_type: str,
        content: str,
        policy: str,
        enabled: bool,
        remark: str,
        revision: int,
    ) -> dict:
        rule = validate_rule(rule_type, content, policy)
        remark = remark.strip()
        if "\n" in remark or "\r" in remark:
            raise ValueError("remark must be one line")
        with self._connect() as connection:
            cursor = connection.execute(
                """update custom_rules
                set rule_type=?, content=?, policy=?, enabled=?, remark=?, revision=revision+1, updated_at=?
                where id=? and revision=?""",
                (rule.rule_type, rule.content, rule.policy, int(enabled), remark, utc_now(), rule_id, revision),
            )
            if cursor.rowcount != 1:
                raise ValueError("rule revision conflict")
            row = connection.execute("select * from custom_rules where id=?", (rule_id,)).fetchone()
        return self._serialize(row)

    def delete(self, rule_id: int, *, revision: int) -> None:
        with self._connect() as connection:
            cursor = connection.execute("delete from custom_rules where id=? and revision=?", (rule_id, revision))
            if cursor.rowcount != 1:
                raise ValueError("rule revision conflict")

    def replace_order(self, ids: list[int]) -> None:
        with self._connect() as connection:
            existing_ids = [row[0] for row in connection.execute("select id from custom_rules order by id")]
            if sorted(ids) != existing_ids or len(ids) != len(set(ids)):
                raise ValueError("order must contain every rule exactly once")
            now = utc_now()
            for index, rule_id in enumerate(ids, start=1):
                connection.execute(
                    "update custom_rules set sort_order=?, revision=revision+1, updated_at=? where id=?",
                    (index * 100, now, rule_id),
                )

    @staticmethod
    def _serialize(row: sqlite3.Row) -> dict:
        result = dict(row)
        result["enabled"] = bool(result["enabled"])
        result["rendered_rule"] = render_rule(validate_rule(result["rule_type"], result["content"], result["policy"]))
        return result
