#!/usr/bin/env bash
# wekan-mcp tool-surface contract (2026/2026-10-feat-board-coord-intake, C01):
# the 20->25 registry (13 reads + 12 writes on the re-cut base; the "27 tools"
# in the re-cut launch was verified false — D22 says trust the grep), the five
# pinned names/shapes of chunks/C01.md "Pinned tool interface", the _slim_card
# additions, and README + skills/wekan-api parity with the new surface.
#
# Contract source: chunks/C01.md "## Tests". AC trace:
# t1[AC1] t2[AC2+AC3] t3[AC4] t4[AC4] t5[AC5] t6[AC6] t8[AC6 + plan Commands
# regression]. The chunk's t7 is the cross-chunk generalization of
# tests/services/dev-mcp-fleet.sh t7 (D24, M2 pin prep) — it lives in THAT
# script and gates via `bash tests/services/dev-mcp-fleet.sh t7`.
#
# t9 is the post-plan Design H ① extension (user-approved 2026-10-25,
# RESEARCH.md): create_card's optional default_checked parameter, its bounded
# poll of the rules-created checklist, the v9.99-verified item-check route,
# the per-checklist outcome surfacing, and the README/SKILL doc parity for
# it. Registry arithmetic stays pinned by t2 (13 reads + 13 writes); wekan.py
# and the login suite stay byte-pinned by t8.
#
# Statics-only by design (D8): the image has no pytest harness and none is
# introduced; the live 25-tool round-trip is user acceptance after M1-M3.
#
# Red before C01 (registry is 11 reads + 9 writes, _slim_card has no
# card_number/custom_fields, docs say 20); green after. t1, t6 and t8 are
# green at the base already — regression gates, not new-behavior gates.
#
# C01_BASE=<ref> re-points the wekan.py / login-suite unchanged-pin (default:
# the re-cut base 5e35ba6da — the login-mint client C01 must build on but not
# touch, D23); review may pass the pre-chunk commit.
#
# Usage:
#   bash tests/wekan-mcp/tools.sh              # t1..t6 + t8 + t9
#   bash tests/wekan-mcp/tools.sh t2 t4        # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SERVER="containers/wekan-mcp/wekan_mcp/server.py"
WEKAN_PY="containers/wekan-mcp/wekan_mcp/wekan.py"
README="containers/wekan-mcp/README.md"
SKILL_API="skills/wekan-api/SKILL.md"
LOGIN_TESTS="tests/containers/wekan-mcp-login.sh"
PIN_BASE="${C01_BASE:-5e35ba6da}"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 8 9; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-6]|8|9)$ ]] || fail "unknown test id '$a' (expected t1..t6, t8 or t9; t7 is tests/services/dev-mcp-fleet.sh)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: py_compile both modules (C01 AC1) -------------------------------------
if want t1; then
  if python3 -m py_compile "$SERVER" "$WEKAN_PY"; then
    ok "t1: python3 -m py_compile passes for $SERVER and $WEKAN_PY (C01 AC1)"
  else
    fail "t1: python3 -m py_compile failed"
  fi
fi

# --- t2: registry arithmetic + pinned names + no new env (C01 AC2+AC3) --------
if want t2; then
  if python3 - "$SERVER" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)

READS = 13
WRITES = 13
NEW = ['list_custom_fields', 'get_custom_field', 'create_custom_field',
       'set_card_custom_field', 'add_checklist_item', 'delete_checklist_item']
BASE20 = ['list_boards', 'get_board', 'list_lists', 'list_swimlanes',
          'list_cards_in_list', 'get_card', 'list_comments', 'list_checklists',
          'get_checklist', 'list_rules', 'get_rule', 'create_card',
          'update_card', 'move_card', 'add_comment', 'add_checklist',
          'toggle_checklist_item', 'create_rule', 'update_rule', 'remove_rule']

def dec_name(d):
    if isinstance(d, ast.Attribute) and d.attr == 'tool' and isinstance(d.value, ast.Name) and d.value.id == 'mcp':
        return 'mcp.tool'
    if isinstance(d, ast.Name) and d.id == '_write_tool':
        return '_write_tool'
    return None

reads, writes = [], []
for node in tree.body:
    if isinstance(node, ast.FunctionDef):
        for d in node.decorator_list:
            kind = dec_name(d)
            if kind == 'mcp.tool':
                reads.append(node.name)
            elif kind == '_write_tool':
                writes.append(node.name)

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

if len(reads) != READS:
    bad(f't2: {len(reads)} @mcp.tool reads, expected exactly {READS} (C01 AC2)')
if len(writes) != WRITES:
    bad(f't2: {len(writes)} @_write_tool writes, expected exactly {WRITES} (C01 AC2)')
all_tools = reads + writes
if len(set(all_tools)) != READS + WRITES:
    bad(f't2: registered names are {sorted(set(all_tools))}, expected exactly 26 distinct')
for name in NEW:
    if all_tools.count(name) != 1:
        bad(f't2: new tool {name!r} registered {all_tools.count(name)} times, expected exactly once (names are the C02/C03 contract, D2)')
missing = [n for n in BASE20 if n not in all_tools]
if missing:
    bad(f't2: existing tools lost from the registry: {missing} (C01 AC6)')

envs = set(re.findall(r'os\.environ\.get\(\s*["\']([A-Z_]+)["\']', src))
allowed = {'WEKAN_MCP_LOG_LEVEL', 'WEKAN_MCP_READ_ONLY', 'WEKAN_MCP_HOST', 'WEKAN_MCP_PORT'}
extra = envs - allowed
if extra:
    bad(f't2: new env vars read in server.py: {sorted(extra)} — C01 AC3 forbids new env vars (only {sorted(allowed)})')
print('ok: t2 — 13 @mcp.tool + 13 @_write_tool == 26 distinct names, the 6 new names registered once each, the base 20 intact, no new env vars (C01 AC2+AC3 + add_checklist_item extension)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't2: the tool-registry contract is not satisfied (reason printed above)'
  fi
fi

# --- t3: _slim_card gains card_number + custom_fields (C01 AC4) ---------------
if want t3; then
  if python3 - "$SERVER" <<'PY'
import ast, re, sys

tree = ast.parse(open(sys.argv[1]).read())
src = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def func(name):
    for n in tree.body:
        if isinstance(n, ast.FunctionDef) and n.name == name:
            return ast.get_source_segment(src, n)
    return None

slim = func('_slim_card')
if slim is None:
    bad('t3: _slim_card disappeared from server.py')
for key, wire in (('"card_number"', 'cardNumber'), ('"custom_fields"', 'customFields')):
    if key not in slim or wire not in slim:
        bad(f't3: _slim_card must emit {key} from the wire key {wire!r} (C01 AC4 — both already ride the /api/cards response, _slim_card was stripping them)')
if "'value'" not in slim and '"value"' not in slim:
    bad('t3: custom_fields must be slimmed to the pinned [{id, value}] entries, not the raw projection (interface shape)')

lic = None
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name == 'list_cards_in_list':
        lic = ast.get_docstring(n) or ''
if lic is None:
    bad('t3: list_cards_in_list disappeared')
if not re.search(r'card[ _]number', lic, re.I):
    bad('t3: list_cards_in_list docstring must document the projection caveat — card_number is None in the by-list response, use get_card (pinned interface)')
print('ok: t3 — _slim_card emits card_number + custom_fields as [{id, value}]; list_cards_in_list docstring carries the projection caveat (C01 AC4)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't3: the _slim_card contract is not satisfied (reason printed above)'
  fi
fi

# --- t4: pinned routes/verbs/bodies per research §1-2/§5 (C01 AC4) ------------
# grep-level contract only: the five new tool bodies must call exactly the
# v9.99-verified endpoints with the pinned JSON keys (no endpoint invented)
# and carry the two pinned docstring warnings.
if want t4; then
  if python3 - "$SERVER" <<'PY'
import ast, re, sys

path = sys.argv[1]
src = open(path).read()
tree = ast.parse(src)
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

funcs = {}
for n in tree.body:
    if isinstance(n, ast.FunctionDef):
        funcs[n.name] = n
def body(name):
    fn = funcs.get(name)
    if fn is None:
        bad(f't4: tool {name!r} is not defined')
    return ast.get_source_segment(src, fn)
def doc(name):
    return ast.get_docstring(funcs.get(name)) or ''

cf_path = '/api/boards/{board_id}/custom-fields'

b = body('list_custom_fields')
if cf_path not in b or '.get(' not in b:
    bad(f't4: list_custom_fields must GET {cf_path} (pinned route)')

b = body('get_custom_field')
if f'{cf_path}/{{custom_field_id}}' not in b or '.get(' not in b:
    bad(f't4: get_custom_field must GET {cf_path}/{{custom_field_id}}')
for wire, snake in (('showOnCard', 'show_on_card'), ('automaticallyOnCard', 'automatically_on_card'), ('alwaysOnCard', 'always_on_card')):
    if wire not in b or snake not in b:
        bad(f't4: get_custom_field must read the camelCase wire key {wire!r} and emit the pinned slimmed key {snake!r}')

b = body('create_custom_field')
if cf_path not in b or '.post(' not in b:
    bad(f't4: create_custom_field must POST {cf_path}')
for key in ('"name"', '"type"', '"settings"', '"showOnCard"', '"automaticallyOnCard"', '"showLabelOnMiniCard"', '"showSumAtTopOfList"'):
    if key not in b:
        bad(f't4: create_custom_field JSON body must carry the pinned key {key} (v9.99 create contract; settings is empty-object-defaulted, never the json.dumps string form)')
d = doc('create_custom_field')
if 'alwaysOnCard' not in d or not re.search(r'backfill|existing card', d, re.I):
    bad('t4: create_custom_field docstring MUST warn that v9.99 REST create ignores alwaysOnCard and does not backfill existing cards (research §1)')

b = body('set_card_custom_field')
if '/api/cards/{card_id}' not in b or 'listId' not in b:
    bad('t4: set_card_custom_field must first GET /api/cards/{card_id} and take its listId (pinned upsert flow)')
if not re.search(r'lists/\{[^}]+\}/cards/\{card_id\}/customFields/\{custom_field_id\}', b) or '.post(' not in b:
    bad('t4: the attached-field leg must POST the dedicated customFields value route (pinned)')
if not re.search(r'lists/\{[^}]+\}/cards/\{card_id\}', b) or '.put(' not in b or '"customFields"' not in b:
    bad('t4: the attach-if-missing leg must PUT the whole customFields array to /api/boards/{board_id}/lists/{list}/cards/{card_id} — the dedicated route silently no-ops on unattached fields (research §2)')
if '"attached"' not in b:
    bad('t4: set_card_custom_field must return the pinned {card_id, custom_field_id, value, attached} shape')
if 'race' not in doc('set_card_custom_field'):
    bad('t4: set_card_custom_field docstring must note the whole-array read-modify-write race (D3 trade-off, documented)')

b = body('add_checklist_item')
if '/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items' not in b or '.post(' not in b:
    bad('t4: add_checklist_item must POST /api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items (v9.99 checklistItems.js add route)')
if '"title"' not in b:
    bad('t4: add_checklist_item JSON body must carry the pinned key "title"')
if '"checklist_id"' not in b or '"id"' not in b:
    bad('t4: add_checklist_item must return the pinned {id, checklist_id, title} shape')

b = body('delete_checklist_item')
if '/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items/{item_id}' not in b or '.delete(' not in b:
    bad('t4: delete_checklist_item must DELETE the v9.99 checklist-items route (checklistItems.js ~L217, research §5)')
if '"deleted"' not in b:
    bad('t4: delete_checklist_item must return {deleted: true, item_id}')
print('ok: t4 — all five tools hit the pinned v9.99-verified routes with the pinned verbs/keys, and both docstring warnings are present (C01 AC4)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't4: the route-string contract is not satisfied (reason printed above)'
  fi
fi

# --- t5: README + wekan-api SKILL parity (C01 AC5) -----------------------------
if want t5; then
  if python3 - "$README" "$SKILL_API" <<'PY'
import sys

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

readme = open(sys.argv[1]).read()
skill = open(sys.argv[2]).read()

NEW = ['list_custom_fields', 'get_custom_field', 'create_custom_field',
       'set_card_custom_field', 'add_checklist_item', 'delete_checklist_item']

if '26 typed tools' not in readme:
    bad('t5: README must state the 26-tool surface (add_checklist_item extension)')
for stale in ('25 typed tools', '20 typed tools'):
    if stale in readme:
        bad(f't5: README still claims the stale tool count ({stale!r})')
for n in NEW:
    if n not in readme:
        bad(f't5: README tool list is missing {n}')
# The docker-build.yaml truth: :v<run_number> (immutable) + :<branch> (rolling).
# The VERSION-file semver story never existed — the claims are stale docs
# (FRICTION 2026-10-24), so they leave as negatives, not as rewritten prose.
for stale in ('bumped by CI', 'semver source of truth', ':latest', 'v<version>'):
    if stale in readme:
        bad(f't5: README still carries the stale semver/VERSION claim "{stale}" (docker-build.yaml publishes :v<run_number> + :<branch>)')
if 'run_number' not in readme:
    bad('t5: README must describe the actual tag scheme (:v<run_number> + :<branch>) it already links to')

if '26 typed tools' not in skill:
    bad('t5: wekan-api SKILL must say 26 typed tools')
for stale in ('25 typed tools', '20 typed tools', '20-tool'):
    if stale in skill:
        bad(f't5: wekan-api SKILL still claims the 20-tool surface ({stale!r})')
if 'two privilege tiers sharing one image' in skill:
    bad('t5: the SKILL still says all tiers share one WEKAN_TOKEN — dev boards login-mints from WEKAN_USERNAME/WEKAN_PASSWORD (D23 wiring)')
if 'WEKAN_USERNAME' not in skill:
    bad('t5: SKILL MCP section must name the login-mint credentials for the dev boards server')
for n in NEW:
    if n not in skill:
        bad(f't5: SKILL MCP tool list is missing {n}')
i = skill.find('intentionally omitted')
if i < 0:
    bad('t5: SKILL lost its intentionally-omitted note (the omitted-surface list must shrink, not vanish)')
window = skill[i:i + 400]
if 'custom field' in window.lower():
    bad('t5: custom fields are no longer on the omitted surface — 25 tools include the five custom-field/checklist-delete tools (C01 AC5)')
print('ok: t5 — README + wekan-api SKILL agree with the 25-tool surface, the login-mint wording landed, and the stale VERSION/semver claims are gone (C01 AC5)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't5: the documentation-parity contract is not satisfied (reason printed above)'
  fi
fi

# --- t6: the existing 20 tool names unchanged (C01 AC6) ------------------------
if want t6; then
  if python3 - "$SERVER" <<'PY'
import ast, sys

tree = ast.parse(open(sys.argv[1]).read())
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# The superset rule for C01's "regression-safe additions only": the names the
# fleet already consumes (gpu tiers, agents) may be added to but not renamed
# or dropped.
BASE20 = ['list_boards', 'get_board', 'list_lists', 'list_swimlanes',
          'list_cards_in_list', 'get_card', 'list_comments', 'list_checklists',
          'get_checklist', 'list_rules', 'get_rule', 'create_card',
          'update_card', 'move_card', 'add_comment', 'add_checklist',
          'toggle_checklist_item', 'create_rule', 'update_rule', 'remove_rule']
names = [n.name for n in tree.body if isinstance(n, ast.FunctionDef)]
dupes = sorted({n for n in names if names.count(n) > 1})
if dupes:
    bad(f't6: duplicate function definitions: {dupes}')
missing = [n for n in BASE20 if n not in names]
if missing:
    bad(f't6: base tool(s) {missing} no longer defined — C01 is additions-only (AC6)')
print('ok: t6 — all 20 base tool names still defined exactly once (superset check, C01 AC6)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't6: the superset check on the existing 20 tools failed (reason printed above)'
  fi
fi

# --- t8: login-mint regression (C01 AC6 + plan Commands regression line) -------
# wekan.py owns the credential lifecycle the fleet runs on (D23); C01 builds
# ON it, never IN it. The blob pin plus the green suite together prove the
# contract is intact — re-run the suite alone after merging main if the pin
# trips on an upstream wekan.py change.
if want t8; then
  if ! git diff --quiet "$PIN_BASE" -- "$WEKAN_PY" 2>/dev/null; then
    fail "t8: $WEKAN_PY changed since $PIN_BASE — C01 must not edit the login-mint client (D23; pass C01_BASE=<ref> if main legitimately moved it)"
  fi
  if ! git diff --quiet "$PIN_BASE" -- "$LOGIN_TESTS" 2>/dev/null; then
    fail "t8: $LOGIN_TESTS changed since $PIN_BASE — the contract suite C01 is gated against must itself stay untouched"
  fi
  ok "t8: $WEKAN_PY and $LOGIN_TESTS are byte-identical to $PIN_BASE (C01 touches neither)"

  login_log=/tmp/opencode/wekan-mcp-tools.login.log
  if bash "$LOGIN_TESTS" >"$login_log" 2>&1; then
    ok "t8: bash $LOGIN_TESTS is fully green (login-mint contract intact for the new tool build; log: $login_log)"
  else
    tail -n 20 "$login_log" >&2
    fail "t8: the login-mint regression suite failed (log: $login_log)"
  fi
fi

# --- t9: create_card default_checked (Design H ①, RESEARCH.md) ---------------
# The v9.99 createCard rules insert standard checklists asynchronously, so
# same-activity rules cannot be relied on to pre-check items (sequential but
# unordered dispatch). The contract: create_card gains an optional
# default_checked map that, inside the one awaited tool call, bounded-polls
# the rules-created checklist + its exact-title items and PUTs isFinished —
# routes pinned against server/models/checklistItems.js and checklists.js at
# tag v9.99 — and surfaces every per-checklist outcome in the response.
# No new tools (t2 arithmetic), no wekan.py edits (t8 byte-pin), no item
# creation (the rules own it), no unbounded waiting.
if want t9; then
  if python3 - "$SERVER" "$README" "$SKILL_API" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def seg(name):
    fn = funcs.get(name)
    if fn is None:
        bad(f't9: {name!r} is not defined in server.py')
    return ast.get_source_segment(src, fn)

# 1) create_card signature: default_checked is the trailing parameter,
#    Optional[dict] (dict keeps the FastMCP schema like create_rule's), None default.
cc = funcs.get('create_card')
if cc is None:
    bad('t9: create_card disappeared')
argnames = [a.arg for a in cc.args.args]
if argnames[-1] != 'default_checked':
    bad(f't9: create_card must end with the optional default_checked parameter, got {argnames}')
if not cc.args.defaults:
    bad('t9: default_checked must carry a default (defaults align to the tail args)')
dc_arg = cc.args.args[-1]
if ast.unparse(dc_arg.annotation) != 'Optional[dict]':
    bad(f't9: default_checked must be Optional[dict], got {ast.unparse(dc_arg.annotation)!r}')
if ast.unparse(cc.args.defaults[-1]) != 'None':
    bad('t9: default_checked must default to None (absent = existing create behavior unchanged)')

cc_src = seg('create_card')
if 'if default_checked:' not in cc_src:
    bad('t9: the defaults path must be gated on default_checked being truthy — None/empty keeps the unchanged {id, title} behavior')
if '"default_checked"' not in cc_src:
    bad('t9: create_card must surface the outcome under the pinned "default_checked" response key')
if '_apply_default_checked(' not in cc_src:
    bad('t9: create_card must delegate to _apply_default_checked (the outcome applier)')

# 2) helper: undecorated (registry stays 13+13 — t2), bounded poll, routes.
ap = funcs.get('_apply_default_checked')
if ap is None or ap.decorator_list:
    bad('t9: _apply_default_checked must exist as a PLAIN helper, not a registered tool (no 27th tool)')
ap_src = seg('_apply_default_checked')

consts = {}
for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant) \
            and isinstance(node.value.value, (int, float)) and not isinstance(node.value.value, bool):
        for tgt in node.targets:
            if isinstance(tgt, ast.Name) and 'POLL' in tgt.id:
                consts[tgt.id] = node.value.value
attempts = [v for k, v in consts.items() if k.endswith('POLL_ATTEMPTS')]
interval = [v for k, v in consts.items() if k.endswith('POLL_INTERVAL_S')]
if len(attempts) != 1 or len(interval) != 1:
    bad(f't9: need exactly _*_POLL_ATTEMPTS and _*_POLL_INTERVAL_S module constants, found {sorted(consts)}')
budget = attempts[0] * interval[0]
if not (2.0 <= budget <= 12.0):
    bad(f't9: poll budget {budget}s is not the bounded ~10s envelope (generous for the async rule cascade, never unbounded)')
if 'range(_DEFAULT_CHECKED_POLL_ATTEMPTS)' not in ap_src or 'time.sleep(_DEFAULT_CHECKED_POLL_INTERVAL_S)' not in ap_src:
    bad('t9: the poll must iterate range(<ATTEMPTS constant>) with time.sleep(<INTERVAL constant>) — a bounded budget, no while-True')
if re.search(r'while\s+True', ap_src):
    bad('t9: unbounded polling loop in _apply_default_checked')

list_route = '/api/boards/{board_id}/cards/{card_id}/checklists'
if f'{list_route}"' not in ap_src or '.get(' not in ap_src:
    bad(f't9: the poll must GET {list_route} (v9.99 checklists.js list route, projects {{_id, title}})')
if f'{list_route}/{{checklist_id}}"' not in ap_src:
    bad(f't9: item titles must come from GET {list_route}/{{checklist_id}} (the route embedding items inline)')
item_route = f'{list_route}/{{checklist_id}}/items/{{item_id}}'
if item_route not in ap_src or '.put(' not in ap_src:
    bad(f't9: the check must PUT {item_route} (v9.99 checklistItems.js L163-215 PUT route)')
if '"isFinished"' not in ap_src or 'True' not in ap_src:
    bad('t9: the check body must be {"isFinished": True} — v9.99 accepts isFinished on that PUT (checklistItems.js L195-200, direct.updateAsync: no activity, idempotent)')

# 3) exact-title matching, never create: drift must show as missing, and
#    item/checklist creation stays the board rules' job.
if '== checklist_title' not in ap_src:
    bad('t9: checklist lookup must match the title exactly')
if 'strip()' in ap_src or '.lower()' in ap_src:
    bad('t9: titles are byte-exact by contract — normalization would check a near-match silently')
if '.post(' in ap_src:
    bad('t9: default_checked may only CHECK items; creating missing checklists/items belongs to the createCard rules (duplication hazard)')

# 4) outcome surfacing: every wanted title lands in exactly one visible bucket.
ret = re.search(r'return\s*\{', ap_src)
if not ret:
    bad('t9: _apply_default_checked must return a dict')
for key in ('"checked"', '"missing"', '"failed"'):
    if key not in ap_src[ret.start():]:
        bad(f't9: the per-checklist outcome must carry the {key} bucket (silent failure is not acceptable; missing = never found within budget, failed = found but PUT rejected)')
cc_doc = ast.get_docstring(cc) or ''
if not re.search(r'bounded', cc_doc, re.I) or 'missing' not in cc_doc or 'rules' not in cc_doc:
    bad('t9: create_card docstring must explain the rules-async/bounded-poll contract and that missing outcomes are REPORTED, not raised (the card stays created)')

# 5) doc parity for the extension itself (counts are t5's job, unchanged).
if 'default_checked' not in open(sys.argv[2]).read():
    bad('t9: README create_card row must mention default_checked')
if 'default_checked' not in open(sys.argv[3]).read():
    bad('t9: wekan-api SKILL write-tool list must mention default_checked on create_card')

print('ok: t9 — create_card default_checked: trailing Optional[dict] param, bounded poll of the pinned v9.99 checklist/item routes with isFinished PUT, byte-exact titles, no item creation, checked/missing/failed surfaced, README+SKILL mention it')
PY
  then
    checks=$((checks + 1))
  else
    fail 't9: the default_checked contract is not satisfied (reason printed above)'
  fi
fi

printf 'PASS: wekan-mcp tools checks (%d ok)\n' "$checks"
