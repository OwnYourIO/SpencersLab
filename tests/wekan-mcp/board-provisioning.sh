#!/usr/bin/env bash
# wekan-mcp board-provisioning contract (2026/2026-10-cf-89-feat-wekan-mcp-
# board-provisioning, C01): the four v102 tools — update_board (title-only
# rename), create_swimlane (optional sort pass-through), create_label (25
# named colors validated client-side, bare-string id response),
# list_board_members (nine normalized role booleans, no username probe) —
# their pinned signatures, routes, HTTP-200-with-error-body guards, and the
# count-parity re-pin across README + the two skills + the sibling suites.
#
# Contract source: chunks/C01.md "## Tests" + "## Acceptance criteria".
# AC trace: t1[AC1] t2[AC2] t3[AC2+AC3] t4[AC4] t5[AC5] t6[AC6] t7[AC7].
#
# Grounding is upstream v12.65 (RESEARCH.md verdict; the card's "9.88.0"
# premise is superseded — DECISIONS 2026-10-30). The embedded-error guards
# asserted here defend the v9.88 low bound (HTTP 200 + serialized error
# body); the live v12.65 server answers real 4xx, so a correct tool needs
# BOTH the guard and an unsquashed status.
#
# Statics-only by design (D8 posture, cf-68 create-list.sh precedent): ast +
# greps, no fastmcp import, no network, no pytest harness. Assertions cite
# server.py function names, never line numbers. The board-admin live probe
# (AC9) is deliberately NOT scripted here — the TEST-wave agent runs the
# dev-boards create_rule/remove_rule never-fires pair and records the
# verdict in the Review notes + RESULT (no network in suites).
#
# Red before C01's dev lands: t1-t6 (registry still 13 reads + 14 writes,
# the four tools absent, docs still on the pre-v102 count). t7 inherits the
# sibling suites' flipped pins — red here with them (they land in this test
# wave), green when registry + docs land together (cf-68 precedent).
# wekan.py's byte-pin rides tools.sh t8 through t7, not re-implemented here.
#
# CF89_BASE=<ref> re-points the base blob the readonly-tier row pin diffs
# against (default: merge-base of main and HEAD — the pre-ticket state).
#
# Usage:
#   bash tests/wekan-mcp/board-provisioning.sh          # t1..t7
#   bash tests/wekan-mcp/board-provisioning.sh t1 t2    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SERVER="containers/wekan-mcp/wekan_mcp/server.py"
README="containers/wekan-mcp/README.md"
SKILL_MCP="skills/wekan-mcp/SKILL.md"
CALLS="skills/wekan-mcp/references/call-shapes.md"
SKILL_API="skills/wekan-api/SKILL.md"
TOOLS_SUITE="tests/wekan-mcp/tools.sh"
SURFACE_SUITE="tests/wekan-mcp/skill-surface.sh"
CREATELIST_SUITE="tests/wekan-mcp/create-list.sh"
BASE="${CF89_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

git rev-parse --verify "$BASE" >/dev/null 2>&1 \
  || fail "harness: base ref '$BASE' does not resolve (CF89_BASE=<ref>)"

TMP=$(mktemp -d /tmp/opencode/board-provisioning-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-7]$ ]] || fail "unknown test id '$a' (expected t1..t7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: registry arithmetic + registration decorators (C01 AC1) ---------------
if want t1; then
  if python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)

READS = 14
WRITES = 17
NEW_READS = ['list_board_members']
NEW_WRITES = ['update_board', 'create_swimlane', 'create_label']
BASE27 = ['list_boards', 'get_board', 'list_lists', 'list_swimlanes',
          'list_cards_in_list', 'get_card', 'list_comments', 'list_checklists',
          'get_checklist', 'list_rules', 'get_rule', 'list_custom_fields',
          'get_custom_field',
          'create_card', 'update_card', 'move_card', 'create_list',
          'add_comment', 'add_checklist', 'toggle_checklist_item',
          'add_checklist_item', 'delete_checklist_item', 'create_rule',
          'update_rule', 'remove_rule', 'create_custom_field',
          'set_card_custom_field']

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
    bad(f't1: {len(reads)} @mcp.tool reads, expected exactly {READS} (C01 AC1)')
if len(writes) != WRITES:
    bad(f't1: {len(writes)} @_write_tool writes, expected exactly {WRITES} (C01 AC1)')
all_tools = reads + writes
if len(set(all_tools)) != READS + WRITES:
    bad(f't1: registered names are {sorted(set(all_tools))}, expected exactly 31 distinct')
for name in NEW_WRITES:
    if all_tools.count(name) != 1 or writes.count(name) != 1:
        bad(f't1: {name!r} must be registered exactly once via @_write_tool — @mcp.tool would leak a v102 write onto the readonly tier')
for name in NEW_READS:
    if all_tools.count(name) != 1 or reads.count(name) != 1:
        bad(f't1: {name!r} must be registered exactly once via @mcp.tool')
missing = [n for n in BASE27 if n not in all_tools]
if missing:
    bad(f't1: pre-v102 tool(s) {missing} lost from the registry (C01 AC1)')
print('ok: t1 — 14 @mcp.tool + 17 @_write_tool == 31 distinct; update_board/create_swimlane/create_label registered once each under _write_tool (WEKAN_MCP_READ_ONLY hides them), list_board_members under @mcp.tool; all 27 pre-v102 names intact (C01 AC1)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't1: the v102 registry contract is not satisfied (reason printed above)'
  fi
fi

# --- t2: the four pinned signatures from AST (C01 AC2) --------------------------
if want t2; then
  if python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

funcs = {}
for n in tree.body:
    if isinstance(n, ast.FunctionDef):
        funcs.setdefault(n.name, []).append(n)

# (params, annotations, defaults) — verbatim from chunks/C01.md "## Interface";
# sort is Optional[int]=None (a finite 0 is a legal explicit sort), color is
# str default "green" (the server's own default, DECISIONS Q3).
PINNED = {
    'update_board': (['board_id', 'title'], ['str', 'str'], []),
    'create_swimlane': (['board_id', 'title', 'sort'], ['str', 'str', 'Optional[int]'], ['None']),
    'create_label': (['board_id', 'name', 'color'], ['str', 'str', 'str'], ["'green'"]),
    'list_board_members': (['board_id'], ['str'], []),
}
for name, (args, anns, defs) in PINNED.items():
    fns = funcs.get(name, [])
    if len(fns) != 1:
        bad(f't2: {name} defined {len(fns)} times, expected exactly one (C01 AC2)')
    fn = fns[0]
    got_args = [a.arg for a in fn.args.args]
    if got_args != args:
        bad(f't2: {name} params are {got_args}, expected {args} (pinned Interface)')
    got_anns = [ast.unparse(a.annotation) for a in fn.args.args if a.annotation is not None]
    if got_anns != anns:
        bad(f't2: {name} annotations are {got_anns}, expected {anns} (pinned Interface)')
    got_defs = [ast.unparse(x) for x in fn.args.defaults]
    if got_defs != defs:
        bad(f't2: {name} defaults are {got_defs}, expected {defs} (sort=None only-when-given, color defaults to the server green)')
    if fn.returns is None or ast.unparse(fn.returns) != 'dict':
        bad(f't2: {name} must be annotated -> dict (pinned Interface)')
print('ok: t2 — update_board(board_id,title) / create_swimlane(board_id,title,sort: Optional[int]=None) / create_label(board_id,name,color="green") / list_board_members(board_id), all -> dict (C01 AC2)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't2: the pinned v102 signatures are not satisfied (reason printed above)'
  fi
fi

# --- t3: pinned routes, 200-embedded-error guards, response shapes (C01 AC2+AC3)
if want t3; then
  if python3 - "$SERVER" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def code(name):
    # Route/shape pinning reads the CODE, docstring excluded: v12.65 stamp
    # prose legitimately spells the same paths (the "exactly once" counts are
    # about request legs, not mentions).
    fn = funcs.get(name)
    if fn is None:
        bad(f't3: {name!r} is not defined — no body to pin routes/guards on (C01 AC2/AC3)')
    s = ast.get_source_segment(src, fn) or ''
    if fn.body and isinstance(fn.body[0], ast.Expr) and isinstance(fn.body[0].value, ast.Constant):
        s = s.replace(ast.get_source_segment(src, fn.body[0]) or '', '', 1)
    return s

# update_board: dedicated title route only (bare PUT /api/boards/:id is 405
# upstream #5299 — building one out of POST+DELETE would reset the board).
b = code('update_board')
if b.count('/api/boards/{board_id}/title') != 1 or '.put(' not in b:
    bad('t3: update_board must PUT /api/boards/{board_id}/title exactly once — PUT …/title is the sanctioned rename route at v12.65 (RESEARCH §1)')
if '"title"' not in b:
    bad('t3: update_board must send the {"title": title} body (pinned)')
if '"_id"' not in b or not re.search(r'(!=|==)\s*board_id|board_id\s*(!=|==)', b):
    bad('t3: update_board guard must compare the response _id to board_id — never trust 200 (v9.88 low bound answers 200 + embedded error; v12.65 answers {"_id","title"})')
if 'WekanError' not in b:
    bad('t3: update_board must surface WekanError when the 200 body is an embedded error or loses _id')
if 'f"/api/boards/{board_id}"' not in b:
    bad('t3: update_board must hydrate via GET /api/boards/{board_id} (full board doc read-back; _slim_board is NOT widened)')
for key in ('"id"', '"title"', '"key"', '"color"', '"permission"', '"archived"', '"renamed"'):
    if key not in b:
        bad(f't3: update_board response must carry {key} (pinned hydrated echo {{id, title, key, color, permission, archived, renamed: true}}; a failed read-back nulls echo fields, never fails the rename)')

# create_swimlane: POST the collection, sort only when explicitly given.
fn = funcs.get('create_swimlane')
b = code('create_swimlane')
if b.count('/api/boards/{board_id}/swimlanes"') != 1 or '.post(' not in b:
    bad('t3: create_swimlane must POST /api/boards/{board_id}/swimlanes exactly once (pinned route, gate checkBoardWriteAccess at v12.65)')
if '"title"' not in b:
    bad('t3: create_swimlane create body must carry "title"')
gate = None
if fn is not None:
    for node in ast.walk(fn):
        if isinstance(node, (ast.If, ast.IfExp)) and re.search(r'sort is not None|isinstance\(\s*sort', ast.unparse(node.test)):
            gate = node
            break
if gate is None:
    bad('t3: create_swimlane must gate the "sort" body key behind an explicit None check — omitting sort defers to the server default max(live sort)+1, and a bare-truthy gate would silently drop the legal sort=0 (#3624)')
elif '"sort"' not in (ast.get_source_segment(src, gate) or ''):
    bad('t3: the sort gate block must build the "sort" body key (explicit finite sort is honored at v12.65)')
if '"_id"' not in b or 'WekanError' not in b:
    bad('t3: create_swimlane must treat a response without _id as a WekanError failure regardless of status (RESEARCH §2: the 9.88 fallback error body arrives at 200 and rides past the client check)')
if len(re.findall(r'swimlanes/\{', b)) != 1:
    bad('t3: create_swimlane must hydrate via exactly one SINGLE-swimlane GET …/swimlanes/{id} — the collection route projects sort away')
for key in ('"id"', '"title"', '"sort"'):
    if key not in b:
        bad(f't3: create_swimlane response must carry {key} (pinned hydrated {{id, title, sort}})')

# create_label: documented dict body form, bare-string id response branch.
b = code('create_label')
if b.count('/api/boards/{board_id}/labels') != 1 or '.put(' not in b:
    bad('t3: create_label must PUT /api/boards/{board_id}/labels exactly once (pinned route)')
for key in ('"label"', '"name"', '"color"'):
    if key not in b:
        bad(f't3: create_label must send the documented {key} key of {{"label": {{"name": …, "color": …}}}} — the string-form passthrough is NOT exposed (DECISIONS Q3)')
if not re.search(r'isinstance\([^)]*\bstr\b', b):
    bad('t3: create_label must branch on a str response — the handler returns the label id as a BARE JSON string (new or the existing id, (name,color)-idempotent)')
if 'WekanError' not in b:
    bad('t3: create_label must raise WekanError on a dict (embedded-error) response')
for key in ('"label_id"', '"name"', '"color"'):
    if key not in b:
        bad(f't3: create_label response must carry {key} (pinned {{label_id, name, color}})')

# list_board_members: board-doc GET, nine normalized booleans.
b = code('list_board_members')
if 'f"/api/boards/{board_id}"' not in b or '.get(' not in b:
    bad('t3: list_board_members must GET /api/boards/{board_id} — the board document is the members source (gate checkBoardAccess at v12.65)')
if '"_id"' not in b or '"members"' not in b or 'isinstance' not in b or 'WekanError' not in b:
    bad('t3: list_board_members must assert the board-doc shape (_id present, members a list) and raise WekanError on an embedded-error body')
for wire, snake in (('userId', 'user_id'), ('isAdmin', 'is_admin'), ('isActive', 'is_active'),
                    ('isNoComments', 'is_no_comments'), ('isCommentOnly', 'is_comment_only'),
                    ('isWorker', 'is_worker'), ('isNormalAssignedOnly', 'is_normal_assigned_only'),
                    ('isCommentAssignedOnly', 'is_comment_assigned_only'),
                    ('isReadOnly', 'is_read_only'), ('isReadAssignedOnly', 'is_read_assigned_only')):
    if f'"{wire}"' not in b or f'"{snake}"' not in b:
        bad(f't3: list_board_members must read the wire key "{wire}" and emit the normalized key "{snake}" (present=>true, absent=>false; grantedBy provenance omitted)')
for key in ('"board_id"', '"title"', '"members"', '"username"', '"username_resolution"'):
    if key not in b:
        bad(f't3: list_board_members response must carry {key} (username: null + the explicit site-admin resolution note — silent nulls are the documented anti-pattern)')

# _LABEL_COLORS: the exact 25 config/const.js names, identical v9.88 -> v12.65.
LABEL_COLORS = {'white', 'green', 'yellow', 'orange', 'red', 'purple', 'blue',
                'sky', 'lime', 'pink', 'black', 'silver', 'peachpuff',
                'crimson', 'plum', 'darkgreen', 'slateblue', 'magenta', 'gold',
                'navy', 'gray', 'saddlebrown', 'paleturquoise', 'mistyrose',
                'indigo'}
const = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for t in node.targets:
            if isinstance(t, ast.Name) and t.id == '_LABEL_COLORS':
                const = node
if const is None:
    bad('t3: module constant _LABEL_COLORS missing (the 25 named colors of config/const.js at v12.65)')
try:
    colors = set(ast.literal_eval(const.value))
except Exception:
    bad('t3: _LABEL_COLORS must be a literal tuple/list/set of strings')
if len(colors) != 25:
    bad(f't3: _LABEL_COLORS has {len(colors)} distinct names, expected 25')
if colors != LABEL_COLORS:
    bad(f't3: _LABEL_COLORS differs from the pinned set: extra={sorted(colors - LABEL_COLORS)} missing={sorted(LABEL_COLORS - colors)}')
if any('#' in c for c in colors):
    bad('t3: _LABEL_COLORS holds named colors only — hex is never stored server-side')
print('ok: t3 — routes/verbs/bodies pinned verbatim; guards assert _id==board_id, no-_id=>WekanError regardless of status, str-vs-dict label branch, board-doc members shape; hydrated response keys pinned; _LABEL_COLORS == the 25 config/const.js names incl. white, no hex (C01 AC2+AC3)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't3: the route/guard/response contract is not satisfied (reason printed above)'
  fi
fi

# --- t4: client-side color gate precedes the request (C01 AC4) ------------------
if want t4; then
  if python3 - "$SERVER" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
fn = funcs.get('create_label')
if fn is None:
    bad('t4: create_label is not defined (C01 AC4)')

puts = [n for n in ast.walk(fn) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
        and n.func.attr == 'put' and isinstance(n.func.value, ast.Name) and n.func.value.id == '_wekan']
if not puts:
    bad('t4: create_label never calls _wekan.put — no request leg to order the gate before')
first_put = min(n.lineno for n in puts)

# Membership gate form-agnostic: inline `color in _LABEL_COLORS` test or a
# validation helper call carrying color, both ahead of the PUT.
cmps = [n for n in ast.walk(fn) if isinstance(n, ast.Compare)
        and any(isinstance(op, (ast.In, ast.NotIn)) for op in n.ops)
        and '_LABEL_COLORS' in (ast.get_source_segment(src, n) or '')]
helpers = [n for n in ast.walk(fn) if isinstance(n, ast.Call)
           and 'color' in (ast.get_source_segment(src, n) or '')
           and re.search(r'validate|check|guard', ast.unparse(n.func))]
gate = [n for n in cmps + helpers if n.lineno < first_put]
if not gate:
    bad('t4: no _LABEL_COLORS membership test (or color-validation helper call) precedes the label PUT — an unknown or #rrggbb color must be rejected client-side BEFORE any request (card: "hex rejected with a clear tool error")')

raises = [n for n in ast.walk(fn) if isinstance(n, ast.Raise) and n.lineno < first_put]
if not raises:
    bad('t4: the pre-request rejection must raise before the PUT (no request has been issued, so nothing to unwind)')
named = [n for n in raises if '_LABEL_COLORS' in (ast.get_source_segment(src, n) or '')
         or re.search(r'allowed colors', ast.get_source_segment(src, n) or '', re.I)]
if not named:
    bad('t4: the rejection message must name the allowed colors (built from _LABEL_COLORS / "Allowed colors: …") — a bare "bad color" is not the pinned clear tool error')
print('ok: t4 — color gate (membership test or validator call) and an allowed-list-naming raise both precede the _wekan.put; a #AABBCC-style input never reaches a request (static ordering, C01 AC4)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't4: the client-side color-gate contract is not satisfied (reason printed above)'
  fi
fi

# --- t5: docstring stamps + gate/error semantics, no /api/users probe (C01 AC5) -
if want t5; then
  if python3 - "$SERVER" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def doc(name):
    fn = funcs.get(name)
    if fn is None:
        bad(f't5: {name!r} is not defined')
    d = ast.get_docstring(fn) or ''
    if not d:
        bad(f't5: {name} has no docstring — route facts must ride the tool (stamp discipline)')
    return d

NEW = ('update_board', 'create_swimlane', 'create_label', 'list_board_members')

# AC6 stamp discipline for code too: every new docstring names the grounded
# upstream version; the card's "9.88.0" form must not reappear.
for name in NEW:
    if 'v12.65' not in doc(name):
        bad(f't5: {name} docstring carries no v12.65 route stamp (grounding superseded the card premise — DECISIONS 2026-10-30)')
    if '9.88.0' in doc(name):
        bad(f't5: {name} docstring repeats the superseded "9.88.0" form (the tag is v9.88)')

u = doc('update_board')
for tok in ('checkBoardAdmin', '403', '404', 'cardNumber'):
    if tok not in u:
        bad(f't5: update_board docstring must state {tok} (gate at v12.65: member=>403 title unchanged, 404 board not found; the cardNumber counter lives in Counters and survives by construction)')
if not re.search(r'\bkey\b', u) or not re.search(r'REST-immutable|immutable', u):
    bad('t5: update_board docstring must note board key once: auto-assigned, REST-immutable (v12.65 #2449/#2450 — nobody builds a change-key wish from this tool)')

s = doc('create_swimlane')
for tok in ('checkBoardWriteAccess', '403', '404'):
    if tok not in s:
        bad(f't5: create_swimlane docstring must state {tok} (write-access gate + distinct 403-vs-404 semantics at v12.65)')

l = doc('create_label')
if not re.search(r'board.?admin', l, re.I) or not re.search(r'site.?admin', l, re.I):
    bad('t5: create_label docstring must state the board-admin-or-site-admin gate (inline gate, clean 401/403/404 at both bounds)')
if not re.search(r'idempot', l, re.I) or not re.search(r'second label', l, re.I):
    bad('t5: create_label docstring must document (name,color)-idempotency AND that the same name with a different color creates a SECOND label (getLabel matches both)')
for tok in ('403', '404'):
    if tok not in l:
        bad(f't5: create_label docstring must state {tok} semantics')

m = doc('list_board_members')
if 'checkBoardAccess' not in m:
    bad('t5: list_board_members docstring must state the checkBoardAccess gate')
for tok in ('403', '404'):
    if tok not in m:
        bad(f't5: list_board_members docstring must state {tok} semantics (404 board not found at both tags)')
if 'username_resolution' not in m or not re.search(r'site.?admin', m, re.I):
    bad('t5: list_board_members docstring must carry the username_resolution note: usernames ride site-admin-gated routes only')

# No username-lookup REQUEST anywhere in the new tools. Scoped to _wekan call
# sites: the pinned username_resolution NOTE text legitimately names the
# site-admin-only routes as documentation data — a probe would be noise at
# 12.65 and invisible at 9.88 (the v101 client cannot see those errors).
for name in NEW:
    fn = funcs[name]
    legs = [ast.get_source_segment(src, n) or '' for n in ast.walk(fn)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
            and n.func.attr in ('get', 'post', 'put', 'delete')
            and isinstance(n.func.value, ast.Name) and n.func.value.id == '_wekan']
    if any('/api/users' in leg for leg in legs):
        bad(f't5: {name} issues an /api/users request — no user-lookup probe is built (the bot is not site admin, DECISIONS Deferred)')
print('ok: t5 — all four docstrings carry v12.65 stamps, their pinned gate names, distinct 403/404 semantics, the (name,color) idempotency + second-label note, the cardNumber-survival note, the key-immutable note, and the username_resolution note; no new code touches /api/users (C01 AC5)')
PY
  then
    checks=$((checks + 1))
  else
    fail 't5: the docstring-semantics contract is not satisfied (reason printed above)'
  fi
fi

# --- t6: surface parity at 31 + zero stale-count residue (C01 AC6) --------------
if want t6; then
  grep -qF '31 typed tools' "$README" \
    || fail "t6: $README does not state the 31-tool surface (C01 AC6)"
  rows=$(awk '/^## Tools exposed/{f=1; next} /^## /{if (f) exit} f && /^\| `[a-z_]+` \|/{n++} END{print n+0}' "$README")
  [ "$rows" -eq 31 ] \
    || fail "t6: $README Tools-exposed table has $rows tool rows, expected 31 — the four v102 rows are missing or the table drifted (C01 AC6)"
  for n in update_board create_swimlane create_label list_board_members; do
    m=$(grep -cE "^\| \`$n\` \|" "$README" || true)
    [ "$m" -eq 1 ] || fail "t6: $README has $m $n rows, expected exactly 1 (C01 AC6)"
  done

  n=$(grep -cF 'full, 31 tools' "$SKILL_MCP" || true)
  [ "$n" -eq 2 ] \
    || fail "t6: $SKILL_MCP tier table has $n 'full, 31 tools' cells, expected 2 — dev-boards and admin-global-wekan flip, readonly stays 'none' (C01 AC6)"
  git show "$BASE:$SKILL_MCP" | grep -F '| `readonly-global-wekan` |' >"$TMP/ro.base" || true
  grep -F '| `readonly-global-wekan` |' "$SKILL_MCP" >"$TMP/ro.now" || true
  cmp -s "$TMP/ro.base" "$TMP/ro.now" \
    || fail "t6: the readonly tier row changed — the _write_tool gate is the whole privilege story, its row must stay byte-identical (C01 AC6)"

  grep -qF 'all 31 tools' "$CALLS" \
    || fail "t6: $CALLS header does not say 'all 31 tools' (C01 AC6)"
  for n in update_board create_swimlane create_label list_board_members; do
    r=$(grep -cE "^\|\s*\`$n\`\s*\|" "$CALLS" || true)
    [ "$r" -eq 1 ] || fail "t6: $CALLS has $r $n rows, expected exactly 1 (C01 AC6)"
    grep -E "^\|\s*\`$n\`\s*\|" "$CALLS" | grep -qF 'source-only' \
      || fail "t6: the $n call-shapes row carries no source-only evidence stamp — the live tools/list probe is post-merge/user-owned (wekan-mcp stamp discipline, C01 AC6)"
  done

  grep -qF '31 typed tools' "$SKILL_API" \
    || fail "t6: $SKILL_API does not say 31 typed tools (C01 AC6)"
  python3 - "$SKILL_API" <<'PY' || fail "t6: the four v102 names are not enumerated in the $SKILL_API Read/Write bullets (C01 AC6 — reason above)"
import sys
text = open(sys.argv[1]).read()
read_start = text.find('- **Read')
write_start = text.find('- **Write**')
if read_start < 0 or write_start < 0 or write_start < read_start:
    print('Read/Write enumeration bullets not found'); sys.exit(1)
read_window = text[read_start:write_start]
rest = text[write_start + len('- **Write**'):]
end = rest.find('\n\n')
write_window = rest if end < 0 else rest[:end]
errs = []
for n in ('list_board_members',):
    if n not in read_window:
        errs.append(f'{n} missing from the Read bullet')
for n in ('update_board', 'create_swimlane', 'create_label'):
    if n not in write_window:
        errs.append(f'{n} missing from the Write bullet')
if errs:
    print('; '.join(errs)); sys.exit(1)
PY

  # Repo-wide stale-count scan (cf-68 FRICTION: missed parity literals are the
  # classic trap). Split-digit patterns so the scan cannot match its own grep
  # text; plan-folder prose and historical notes legitimately keep the old
  # count, so .agents/plans/ is out of scope.
  residue=""
  for p in '2[7] typed tools' 'all 2[7] tools' 'full, 2[7] tools' '2[7]-tool'; do
    hits=$(grep -rn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.kilo -E "$p" . 2>/dev/null | grep -v '^\./\.agents/plans/' || true)
    [ -z "$hits" ] || residue="${residue}${hits}"$'\n'
  done
  [ -z "$residue" ] || fail "t6: stale 27-count residue outside plan folders:"$'\n'"$residue"

  ok "t6: README (31 typed tools, 31 table rows incl. four new rows), wekan-mcp SKILL tiers (two 31 cells, readonly row byte-stable), call-shapes (all 31 tools + four stamped rows), wekan-api SKILL (31 + four names in the Read/Write bullets) agree; zero stale 27-count literals repo-wide outside plan folders (C01 AC6)"
fi

# --- t7: sibling suites stay mutually consistent with the flips (C01 AC7) -------
# The 27->31 (now 31) pins live in three suites plus two skills plus README;
# this t is the cross-check that they moved together — a half-flipped surface
# fails here even if each file looks right alone.
if want t7; then
  for suite in "$TOOLS_SUITE" "$SURFACE_SUITE" "$CREATELIST_SUITE"; do
    log="/tmp/opencode/board-provisioning.$(basename "$suite" .sh).log"
    if bash "$suite" >"$log" 2>&1; then
      ok "t7: bash $suite green — registry, docs and test pins agree at 31 (C01 AC7)"
    else
      tail -n 20 "$log" >&2
      fail "t7: $suite is not green — the count-parity flip must be mutually consistent (log: $log)"
    fi
  done
fi

printf 'PASS: wekan-mcp board-provisioning checks (%d ok)\n' "$checks"
