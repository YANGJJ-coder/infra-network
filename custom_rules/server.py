import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from custom_rules.store import CustomRuleStore
from custom_rules.validation import ALLOWED_POLICIES, ALLOWED_RULE_TYPES, RuleValidationError


INDEX_HTML = """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>HomeStream Custom Rules</title><style>
:root{color-scheme:dark;font-family:ui-sans-serif,system-ui;background:#0b1220;color:#e5e7eb}body{max-width:1200px;margin:0 auto;padding:28px}h1{margin:0}.hint{color:#94a3b8}.card{background:#111c31;border:1px solid #263754;border-radius:10px;padding:18px;margin-top:18px}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}label{display:grid;gap:5px;color:#cbd5e1;font-size:13px}input,select,button{font:inherit;border-radius:6px;border:1px solid #415675;padding:8px;background:#0b1220;color:#e5e7eb}button{cursor:pointer;background:#1d4ed8;border:0}button.secondary{background:#334155}button.danger{background:#b91c1c}button:disabled{opacity:.45;cursor:not-allowed}table{width:100%;border-collapse:collapse;margin-top:12px}th,td{text-align:left;padding:10px 8px;border-bottom:1px solid #263754;vertical-align:top;font-size:14px}.actions{display:flex;gap:6px;flex-wrap:wrap}.status{min-height:22px;color:#fbbf24}@media(max-width:850px){.grid{grid-template-columns:1fr 1fr}table{font-size:12px}.remark{display:none}}</style></head>
<body><h1>Custom Rules</h1><p class="hint">已保存的启用规则会在下一次“正式完整订阅”刷新时生效；优先级高于 AI-US。</p>
<section class="card"><form id="rule-form"><input id="id" type="hidden"><input id="revision" type="hidden"><div class="grid"><label>规则类型<select id="rule_type"></select></label><label>内容<input id="content" required maxlength="255" placeholder="chatgpt.com 或 203.0.113.0/24"></label><label>策略<select id="policy"></select></label><label>启用<select id="enabled"><option value="true">启用</option><option value="false">禁用</option></select></label><label>备注<input id="remark" maxlength="255" placeholder="可选"></label></div><p class="actions"><button type="submit">保存规则</button><button class="secondary" id="reset-button" type="button">新增规则</button></p></form><div class="status" id="status"></div></section>
<section class="card"><label>搜索<input id="search" placeholder="按内容或备注搜索"></label><table><thead><tr><th>优先级</th><th>规则</th><th>策略</th><th>状态</th><th class="remark">备注</th><th>创建/修改时间</th><th>操作</th></tr></thead><tbody id="rules"></tbody></table></section>
<script>
const state={rules:[]};const $=id=>document.getElementById(id);const api=path=>`api/v1/${path}`;
function show(message,error=false){$('status').textContent=message;$('status').style.color=error?'#fca5a5':'#86efac'}
async function request(path,options={}){const response=await fetch(api(path),{headers:{'Content-Type':'application/json'},...options});const body=response.status===204?{}:await response.json();if(!response.ok)throw new Error(body.error||`HTTP ${response.status}`);return body}
function clearForm(){$('id').value='';$('revision').value='';$('rule-form').reset();$('enabled').value='true'}
function escape(value){const node=document.createElement('span');node.textContent=value;return node.innerHTML}
function render(){const query=encodeURIComponent($('search').value);request(`rules?q=${query}`).then(data=>{state.rules=data.rules;const rows=data.rules.map((rule,index)=>`<tr><td>${index+1}</td><td><code>${escape(rule.rendered_rule)}</code></td><td>${escape(rule.policy)}</td><td>${rule.enabled?'启用':'禁用'}</td><td class="remark">${escape(rule.remark)}</td><td>${rule.created_at}<br>${rule.updated_at}</td><td><div class="actions"><button data-action="edit" data-id="${rule.id}">编辑</button><button class="secondary" data-action="toggle" data-id="${rule.id}">${rule.enabled?'禁用':'启用'}</button><button class="secondary" data-action="up" data-id="${rule.id}" ${index===0?'disabled':''}>上移</button><button class="secondary" data-action="down" data-id="${rule.id}" ${index===data.rules.length-1?'disabled':''}>下移</button><button class="danger" data-action="delete" data-id="${rule.id}">删除</button></div></td></tr>`).join('');$('rules').innerHTML=rows||'<tr><td colspan="7" class="hint">暂无规则</td></tr>'}).catch(error=>show(error.message,true))}
async function save(event){event.preventDefault();const payload={rule_type:$('rule_type').value,content:$('content').value,policy:$('policy').value,enabled:$('enabled').value==='true',remark:$('remark').value};try{if($('id').value){payload.revision=Number($('revision').value);await request(`rules/${$('id').value}`,{method:'PATCH',body:JSON.stringify(payload)});show('规则已更新')}else{await request('rules',{method:'POST',body:JSON.stringify(payload)});show('规则已新增')}clearForm();render()}catch(error){show(error.message,true)}}
async function action(event){const button=event.target.closest('button[data-action]');if(!button)return;const rule=state.rules.find(item=>item.id===Number(button.dataset.id));try{if(button.dataset.action==='edit'){$('id').value=rule.id;$('revision').value=rule.revision;$('rule_type').value=rule.rule_type;$('content').value=rule.content;$('policy').value=rule.policy;$('enabled').value=String(rule.enabled);$('remark').value=rule.remark;return}if(button.dataset.action==='delete'){if(!confirm(`删除 ${rule.rendered_rule}？`))return;await request(`rules/${rule.id}?revision=${rule.revision}`,{method:'DELETE'});show('规则已删除')}else if(button.dataset.action==='toggle'){await request(`rules/${rule.id}`,{method:'PATCH',body:JSON.stringify({...rule,enabled:!rule.enabled})});show('规则状态已更新')}else{const index=state.rules.indexOf(rule),target=button.dataset.action==='up'?index-1:index+1;const ids=state.rules.map(item=>item.id);[ids[index],ids[target]]=[ids[target],ids[index]];await request('rules/order',{method:'PUT',body:JSON.stringify({ids})});show('规则顺序已更新')}render()}catch(error){show(error.message,true)}}
async function initialize(){const types=await request('rule-types');$('rule_type').innerHTML=types.rule_types.map(value=>`<option>${value}</option>`).join('');$('policy').innerHTML=types.policies.map(value=>`<option>${value}</option>`).join('');$('rule-form').addEventListener('submit',save);$('reset-button').addEventListener('click',clearForm);$('search').addEventListener('input',render);$('rules').addEventListener('click',action);clearForm();render()}initialize().catch(error=>show(error.message,true));
</script></body></html>"""


class RuleAdminHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._send_html(INDEX_HTML)
            return
        if parsed.path == "/api/v1/rule-types":
            self._send_json({"rule_types": ALLOWED_RULE_TYPES, "policies": ALLOWED_POLICIES})
            return
        if parsed.path == "/api/v1/rules":
            query = parse_qs(parsed.query).get("q", [""])[0]
            self._send_json({"rules": self.server.store.list_rules(query=query)})
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if self.path != "/api/v1/rules":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            payload = self._read_json()
            rule = self.server.store.create(
                payload["rule_type"], payload["content"], payload["policy"], bool(payload["enabled"]), payload.get("remark", "")
            )
        except (KeyError, TypeError, ValueError, RuleValidationError) as error:
            self._send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return
        self._send_json({"rule": rule}, HTTPStatus.CREATED)

    def do_PATCH(self) -> None:
        rule_id = self._rule_id()
        if rule_id is None:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            payload = self._read_json()
            rule = self.server.store.update(
                rule_id,
                rule_type=payload["rule_type"],
                content=payload["content"],
                policy=payload["policy"],
                enabled=bool(payload["enabled"]),
                remark=payload.get("remark", ""),
                revision=int(payload["revision"]),
            )
        except ValueError as error:
            self._send_json({"error": str(error)}, HTTPStatus.CONFLICT if "revision conflict" in str(error) else HTTPStatus.BAD_REQUEST)
            return
        except (KeyError, TypeError, RuleValidationError) as error:
            self._send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return
        self._send_json({"rule": rule})

    def do_DELETE(self) -> None:
        rule_id = self._rule_id()
        if rule_id is None:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            revision = int(parse_qs(urlparse(self.path).query)["revision"][0])
            self.server.store.delete(rule_id, revision=revision)
        except (KeyError, TypeError, ValueError) as error:
            self._send_json({"error": str(error)}, HTTPStatus.CONFLICT if "revision conflict" in str(error) else HTTPStatus.BAD_REQUEST)
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def do_PUT(self) -> None:
        if self.path != "/api/v1/rules/order":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            self.server.store.replace_order([int(rule_id) for rule_id in self._read_json()["ids"]])
        except (KeyError, TypeError, ValueError) as error:
            self._send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def _rule_id(self) -> int | None:
        parts = urlparse(self.path).path.split("/")
        if len(parts) != 5 or parts[:4] != ["", "api", "v1", "rules"]:
            return None
        try:
            return int(parts[4])
        except ValueError:
            return None

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length))

    def _send_html(self, body: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _send_json(self, body: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, _format: str, *_args: object) -> None:
        return


class RuleAdminServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], database_path: str):
        self.store = CustomRuleStore(database_path)
        super().__init__(address, RuleAdminHandler)


def create_server(database_path: str, port: int = 3012) -> RuleAdminServer:
    return RuleAdminServer(("127.0.0.1", port), database_path)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="HomeStream Custom Rules management service")
    parser.add_argument("database_path")
    parser.add_argument("--port", type=int, default=3012)
    arguments = parser.parse_args()
    create_server(arguments.database_path, arguments.port).serve_forever()
