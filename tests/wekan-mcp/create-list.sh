#!/usr/bin/env bash
# wekan-mcp create_list contract (2026/2026-10-cf-68-feat-wekan-mcp-create-list,
# C01): the 14th @_write_tool tool — pinned signature, the three REST legs
# (create POST, position-gated reposition move, read-back hydration GET) with
# their non-failing failure arms, the READ_ONLY/_write_tool privilege gate
# staying byte-stable, the zero-diff posture on existing tools, and the
# doc-surface count-parity greps (26->27 at authoring, re-pinned to 31 by
# cf-89 v102 — the four v102 tools land with that flip, cf-68 precedent).
#
# Contract source: chunks/C01.md "## Tests" and "## Acceptance criteria".
# AC trace: t1[AC4] t2[AC5+AC7] t3[AC6] t4[AC2] t5[AC5 gate + D4].
#
# Statics-only by design (DECISIONS Conventions — same posture as tools.sh and
# skill-surface.sh): ast + greps, no fastmcp import, no network, no pytest
# harness. Assertions cite server.py function names, never line numbers.
#
# Red before C01's dev lands: t1/t2/t5 on the absent create_list, t3 on the
# 26-count docs, t4 via the siblings' re-pinned 31 counts. Every red names
# not-yet-implemented behavior, never a harness fault.
#
# CF68_BASE=<ref> re-points the base blob the byte-pins and the additive-hunk
# pin diff against (default: merge-base of main and HEAD — the pre-ticket
# state; pass the pre-chunk commit if main legitimately moved server.py since).
#
# Usage:
#   bash tests/wekan-mcp/create-list.sh            # t1..t5
#   bash tests/wekan-mcp/create-list.sh t1 t2      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SERVER="containers/wekan-mcp/wekan_mcp/server.py"
WEKAN_PY="containers/wekan-mcp/wekan_mcp/wekan.py"
README="containers/wekan-mcp/README.md"
SKILL_MCP="skills/wekan-mcp/SKILL.md"
CALLS="skills/wekan-mcp/references/call-shapes.md"
SKILL_API="skills/wekan-api/SKILL.md"
TOOLS_SUITE="tests/wekan-mcp/tools.sh"
SURFACE_SUITE="tests/wekan-mcp/skill-surface.sh"
BASE="${CF68_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

git rev-parse --verify "$BASE" >/dev/null 2>&1 \
  || fail "harness: base ref '$BASE' does not resolve (CF68_BASE=<ref>)"

TMP=$(mktemp -d /tmp/opencode/create-list-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

git show "$BASE:$SERVER" >"$TMP/server.base.py" || fail "harness: $SERVER missing at $BASE"

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected t1..t5)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# t1 validates registration against the live file; t5's red-green probe reuses
# the exact same checker against a scratch copy — one implementation, so the
# probe cannot drift from what it claims to falsify.
cat >"$TMP/check-registration.py" <<'PY'
import ast, sys

tree = ast.parse(open(sys.argv[1]).read())
fns = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'create_list']

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

if len(fns) != 1:
    bad(f'create_list registration: {len(fns)} top-level definitions in server.py, expected exactly one (not yet implemented, or duplicated)')
fn = fns[0]
if len(fn.decorator_list) != 1:
    bad(f'create_list registration: {len(fn.decorator_list)} decorators, expected exactly the one _write_tool gate (D4)')
d = fn.decorator_list[0]
if not (isinstance(d, ast.Name) and d.id == '_write_tool'):
    bad(f'create_list registration: decorator is {ast.unparse(d)!r}, expected the Name _write_tool — @mcp.tool would register the write tool on the readonly tier too (D4)')
args = [a.arg for a in fn.args.args]
if args != ['board_id', 'title', 'swimlane_id', 'position']:
    bad(f'create_list registration: params are {args}, expected the pinned board_id/title/swimlane_id/position order (D1: title, not list_title)')
ann = [ast.unparse(a.annotation) for a in fn.args.args if a.annotation is not None]
if ann != ['str', 'str', 'Optional[str]', 'Optional[int]']:
    bad(f'create_list registration: annotations are {ann}, expected str/str/Optional[str]/Optional[int] (pinned Interface)')
defs = [ast.unparse(x) for x in fn.args.defaults]
if defs != ['None', 'None']:
    bad(f'create_list registration: defaults are {defs}, expected (None, None) — swimlane_id and position are the optional tail (D2)')
if fn.returns is None or ast.unparse(fn.returns) != 'dict':
    bad(f'create_list registration: return annotation is {ast.unparse(fn.returns) if fn.returns is not None else None!r}, expected dict')
PY

# --- t1: registration + pinned signature (C01 AC4) ----------------------------
if want t1; then
  python3 "$TMP/check-registration.py" "$SERVER" \
    || fail "t1: the create_list registration contract is violated (C01 AC4 — reason above)"
  ok "t1: exactly one top-level create_list, decorated @_write_tool, params board_id/title/swimlane_id/position Optional[str]=None/Optional[int]=None, returns dict (C01 AC4)"
fi

# --- t2: behavior literals + gate integrity + zero-diff (C01 AC5, AC7) --------
if want t2; then
  git diff --quiet "$BASE" -- "$WEKAN_PY" \
    || fail "t2: $WEKAN_PY changed since $BASE — C01 rides the existing _wekan helpers, it must not edit the client (plan out-of-scope, AC7 byte-pin like tools.sh t8)"

  if python3 - "$SERVER" "$TMP/server.base.py" "$BASE" <<'PY'
import ast, re, subprocess, sys

path, base_file, base_ref = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
base_src = open(base_file).read()
tree = ast.parse(src)

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

fns = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'create_list']
if len(fns) != 1:
    bad(f't2: create_list is defined {len(fns)} times — no body to pin behavior on yet (C01 AC5)')
fn = fns[0]
fn_src = ast.get_source_segment(src, fn) or ''

parents = {}
for node in ast.walk(tree):
    for child in ast.iter_child_nodes(node):
        parents[child] = node

def call_nodes(attr):
    out = []
    for node in ast.walk(fn):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                and node.func.attr == attr and isinstance(node.func.value, ast.Name) \
                and node.func.value.id == '_wekan':
            out.append(node)
    return out

posts = call_nodes('post')
gets = call_nodes('get')

# 1) create leg: the pinned v12.64 lists.js route, via the shared client.
if 'f"/api/boards/{board_id}/lists"' not in fn_src:
    bad('t2: the create leg must POST the pinned literal f"/api/boards/{board_id}/lists" (v12.64 lists.js create route, plan Interface)')
if not any('/move' not in (ast.get_source_segment(src, c) or '') for c in posts):
    bad('t2: no create POST call site survived — every _wekan.post in create_list looks like the move leg (C01 AC5)')

# 2) swimlane wire keys: every write conditional on a bare-truthy swimlane_id.
key_nodes = []
for node in ast.walk(fn):
    if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant) \
            and node.slice.value in ('swimlaneId', 'toSwimlaneId'):
        key_nodes.append(node)
    elif isinstance(node, ast.Dict):
        for k in node.keys:
            if isinstance(k, ast.Constant) and k.value in ('swimlaneId', 'toSwimlaneId'):
                key_nodes.append(node)
                break
if not key_nodes:
    bad('t2: neither swimlaneId nor toSwimlaneId is ever written — the create body must carry swimlaneId and the move body toSwimlaneId when swimlane_id is given (plan Interface)')
for node in key_nodes:
    p, gated = node, False
    while p is not None and p is not fn:
        if isinstance(p, (ast.If, ast.IfExp)) and ast.unparse(p.test) == 'swimlane_id':
            gated = True
            break
        p = parents.get(p)
    if not gated:
        bad('t2: a swimlaneId/toSwimlaneId write sits outside a truthy `if swimlane_id:` branch — omitting the argument must defer to WeKan\'s default (board first) swimlane, never send an empty key (C01 AC5)')
for wire in ('"swimlaneId"', '"toSwimlaneId"'):
    if wire not in fn_src:
        bad(f't2: the wire key {wire} never appears — the create body takes it conditionally and the move body too (plan Interface)')

# 3) move leg: gated on position, carries position, never crosses boards.
move_posts = [c for c in posts if '/move' in (ast.get_source_segment(src, c) or '')]
if len(move_posts) != 1:
    bad(f't2: {len(move_posts)} _wekan.post calls hitting a /move route, expected exactly one — POST .../lists/{{list id}}/move without toBoardId is the only same-board reposition leg on v12.64 (D2)')
mv = move_posts[0]
mv_src = ast.get_source_segment(src, mv) or ''
if not re.search(r'/api/boards/\{board_id\}/lists/\{[^}]+\}/move', mv_src):
    bad('t2: the move leg does not POST the pinned .../lists/{id}/move route (v12.64 lists.js)')
if '"toBoardId"' in fn_src:
    bad('t2: create_list sends toBoardId — the cross-board branch is not the same-board reposition leg (chunks/C01 Notes for dev)')
gate = None
p = mv
while p is not None and p is not fn:
    if isinstance(p, ast.If) and ast.unparse(p.test) == 'position is not None':
        gate = p
        break
    p = parents.get(p)
if gate is None:
    bad('t2: the move POST is not reached under an `if position is not None:` gate — append-at-end must stay the no-position behavior (C01 AC5)')
# Pinned on the whole gate block, not the call segment: the repo style builds
# the json_body dict on lines ahead of the call (see create_card), so a
# compliant move body would be invisible to a call-site-only grep.
if '"position"' not in (ast.get_source_segment(src, gate) or ''):
    bad('t2: the `if position is not None:` block never builds a "position" key — the move leg body must carry it (0-based from the left among the board\'s live lists, plan Interface)')

# 4) hydration leg: exactly one single-list GET.
hydrations = [c for c in gets
              if re.search(r'/api/boards/\{board_id\}/lists/\{', ast.get_source_segment(src, c) or '')]
if len(hydrations) != 1:
    bad(f't2: {len(hydrations)} single-list GET hydration calls in create_list, expected exactly one — GET .../lists/{{id}} is the read-back source (D3, list_lists precedent)')

# 5) both secondary legs wrapped, arms non-raising, arms distinct.
def wekan_try(node):
    p = node
    while p is not None and p is not fn:
        if isinstance(p, ast.Try) and any(
                (isinstance(h.type, ast.Name) and h.type.id == 'WekanError')
                or (isinstance(h.type, ast.Tuple) and any(getattr(t, 'id', None) == 'WekanError' for t in h.type.elts))
                for h in p.handlers):
            return p
        p = parents.get(p)
    return None

tw_mv, tw_hy = wekan_try(mv), wekan_try(hydrations[0])
if tw_mv is None:
    bad('t2: the move leg is not wrapped in a WekanError-catching try — a failed reposition must never fail the create (D2, create_card default_checked precedent)')
if tw_hy is None:
    bad('t2: the hydration GET is not wrapped in a WekanError-catching try — read-back failure degrades the echoed fields to null (D3, list_lists precedent)')
if tw_mv is tw_hy:
    bad('t2: move and hydration share one try arm — each failure mode must report on its own (C01 AC5)')
for name, tw in (('move', tw_mv), ('hydration', tw_hy)):
    for h in tw.handlers:
        if any(isinstance(n, ast.Raise) for n in ast.walk(h)):
            bad(f't2: the {name} arm re-raises WekanError — both secondary legs report, never propagate (C01 AC5)')
mv_handler = ' '.join(ast.unparse(h.body) for h in tw_mv.handlers)
if 'position' not in mv_handler:
    bad('t2: the move arm records nothing about the position outcome — failure must be captured into positioned/position_error (C01 AC5)')

# 6) pinned response surface (D3): hydrated fields + outcome flags.
for key in ('"positioned"', '"position_error"', '"swimlane_id"', '"sort"'):
    if key not in fn_src:
        bad(f't2: the response field {key} is absent — the hydrated shape is {{id, title, swimlane_id, sort, positioned}} plus position_error on a failed reposition (D3, plan Interface)')

# 7) module-level invariants: transport stays in the client, env stays closed.
if re.search(r'\bhttpx\b', src):
    bad('t2: server.py now imports or uses httpx — HTTP transport lives in WekanClient (wekan.py is byte-pinned; plan out-of-scope)')
env_now = set(re.findall(r'os\.environ\.get\(\s*["\']([A-Z_]+)["\']', src))
env_base = set(re.findall(r'os\.environ\.get\(\s*["\']([A-Z_]+)["\']', base_src))
if env_now - env_base:
    bad(f't2: new os.environ reads in server.py: {sorted(env_now - env_base)} (C01 AC5 — no new env)')

# 8) AC7 zero-diff: exactly one additive hunk against the pre-ticket base.
diff = subprocess.run(['git', 'diff', base_ref, '--', path], capture_output=True, text=True).stdout
hunks = [l for l in diff.splitlines() if l.startswith('@@')]
if len(hunks) != 1:
    bad(f't2: server.py diff vs base has {len(hunks)} hunks, expected exactly one — create_list lands as a single additive hunk in the WRITE TOOLS section (AC7)')
removed = [l for l in diff.splitlines() if l.startswith('-') and not l.startswith('---')]
if removed:
    bad(f't2: server.py diff removes lines ({removed[:3]!r}) — existing tool bodies must stay untouched (AC7)')
PY
  then
    ok "t2: create legs pinned (conditional swimlaneId, position-gated move without toBoardId, hydration GET), non-raising distinct arms, positioned/position_error/sort/swimlane_id surfaced, no httpx, no new env, wekan.py byte-identical, one additive server.py hunk (C01 AC5+AC7)"
  else
    fail "t2: the create_list behavior/gate contract is violated (C01 AC5+AC7 — reason above)"
fi
fi

# --- t3: doc parity across the four surfaces (C01 AC6) -------------------------
if want t3; then
  grep -qF '31 typed tools' "$README" \
    || fail "t3: $README does not state the 31-tool surface (C01 AC6)"
  rows=$(awk '/^## Tools exposed/{f=1; next} /^## /{if (f) exit} f && /^\| `[a-z_]+` \|/{n++} END{print n+0}' "$README")
  [ "$rows" -eq 31 ] \
    || fail "t3: $README Tools-exposed table has $rows tool rows, expected 31 (create_list row missing, or the table drifted; C01 AC6)"
  grep -qE '^\| `create_list` \|' "$README" \
    || fail "t3: the $README Tools table has no create_list row (C01 AC6)"

  n=$(grep -cF 'full, 31 tools' "$SKILL_MCP" || true)
  [ "$n" -eq 2 ] \
    || fail "t3: $SKILL_MCP tier table has $n 'full, 31 tools' cells, expected 2 — dev-boards and admin-global-wekan flip, readonly stays 'none' (C01 AC6)"
  if grep -qF 'full, 26 tools' "$SKILL_MCP"; then
    fail "t3: $SKILL_MCP still says 'full, 26 tools' somewhere (C01 AC6)"
  fi
  git show "$BASE:$SKILL_MCP" | grep -F '| `readonly-global-wekan` |' >"$TMP/ro.base" || true
  grep -F '| `readonly-global-wekan` |' "$SKILL_MCP" >"$TMP/ro.now" || true
  cmp -s "$TMP/ro.base" "$TMP/ro.now" \
    || fail "t3: the readonly tier row changed — the _write_tool gate is the whole privilege story, its row must stay byte-identical (D4, C01 AC6)"

  grep -qF 'all 31 tools' "$CALLS" \
    || fail "t3: $CALLS header does not say 'all 31 tools' (C01 AC6)"
  n=$(grep -cE '^\|\s*`create_list`\s*\|' "$CALLS" || true)
  [ "$n" -eq 1 ] \
    || fail "t3: $CALLS has $n create_list rows, expected exactly 1 (C01 AC6)"
  grep -E '^\|\s*`create_list`\s*\|' "$CALLS" | grep -qF 'source-only' \
    || fail "t3: the create_list call-shapes row carries no source-only evidence stamp — the live probe is post-merge/user-owned (D7, C01 AC6)"

  grep -qF '31 typed tools' "$SKILL_API" \
    || fail "t3: $SKILL_API does not say 31 typed tools (C01 AC6)"
  if grep -qF '26 typed tools' "$SKILL_API"; then
    fail "t3: $SKILL_API still says 26 typed tools (C01 AC6)"
  fi
  if grep -qF '25-tool surface' "$SKILL_API"; then
    fail "t3: $SKILL_API still carries the stale 'full 25-tool surface' line — FRICTION 2026-10-29 named exactly this missed-parity trap (C01 AC6)"
  fi
  python3 - "$SKILL_API" <<'PY' || fail "t3: create_list is not enumerated in the $SKILL_API Write bullet (C01 AC6)"
import sys
text = open(sys.argv[1]).read()
start = text.find('- **Write**')
if start < 0:
    print('no Write bullet in wekan-api SKILL'); sys.exit(1)
rest = text[start + len('- **Write**'):]
end = rest.find('\n\n')
if 'create_list' not in (rest if end < 0 else rest[:end]):
    print('create_list missing from the Write enumeration window'); sys.exit(1)
PY
  ok "t3: README (31 + create_list row + 31 table rows), wekan-mcp SKILL tiers (two flips, readonly byte-stable), call-shapes (31 header + one stamped create_list row), wekan-api SKILL (31, create_list in Write bullet, no 25/26 residue) all agree (C01 AC6)"
fi

# --- t4: the flipped sibling suites stay the parity gate (C01 AC2) -------------
if want t4; then
  log=/tmp/opencode/create-list.tools.log
  if bash "$TOOLS_SUITE" >"$log" 2>&1; then
    ok "t4a: bash $TOOLS_SUITE is green with the pins at 31 (C01 AC2)"
  else
    tail -n 20 "$log" >&2
    fail "t4: $TOOLS_SUITE is not green — registry and doc pins must agree (log: $log)"
  fi
  log=/tmp/opencode/create-list.surface.log
  if bash "$SURFACE_SUITE" >"$log" 2>&1; then
    ok "t4b: bash $SURFACE_SUITE is green with the pins at 31 (C01 AC2)"
  else
    tail -n 20 "$log" >&2
    fail "t4: $SURFACE_SUITE is not green — call-shapes and the registry must agree (log: $log)"
  fi
fi

# --- t5: privilege gate byte-stable + red-green probe (C01 AC5, D4) ------------
if want t5; then
  python3 - "$SERVER" "$TMP/server.base.py" <<'PY' || fail "t5: the readonly gate drifted — write tools must never register when WEKAN_MCP_READ_ONLY is set (D4; reason above)"
import re, sys

src = open(sys.argv[1]).read()
base_src = open(sys.argv[2]).read()
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

pats = (
    ('READ_ONLY gate', re.compile(r'READ_ONLY = os\.environ\.get\("WEKAN_MCP_READ_ONLY", ""\)\.strip\(\)\.lower\(\) in \(\n(?:.*\n)*?\)\n')),
    ('_write_tool gate', re.compile(r'^_write_tool = .*$', re.M)),
)
for name, pat in pats:
    now, base = pat.findall(src), pat.findall(base_src)
    if len(now) != 1 or now != base:
        bad(f't5: the {name} line(s) are not exactly one occurrence byte-identical to base — D4 adds zero tier-specific code (found {len(now)})')
PY
  python3 "$TMP/check-registration.py" "$SERVER" \
    || fail "t5: create_list is not registered under _write_tool — the readonly tier must not get it (D4; reason above)"

  # The probe proves the registration pin is not vacuous: a scratch copy with
  # the decorator flipped to @mcp.tool must fail the very checker that passes
  # on the live file. The real file is opened read-only, never written.
  python3 - "$SERVER" "$TMP/scratch.py" <<'PY' || fail "t5: probe setup — could not build the scratch copy with the flipped decorator"
import sys
src = open(sys.argv[1]).read()
needle = '@_write_tool\ndef create_list('
if src.count(needle) != 1:
    print(f'expected one "{needle}" site, found {src.count(needle)}', file=sys.stderr)
    sys.exit(1)
open(sys.argv[2], 'w').write(src.replace(needle, '@mcp.tool\ndef create_list('))
PY
  if python3 "$TMP/check-registration.py" "$TMP/scratch.py" >/dev/null 2>&1; then
    fail "t5: red-green probe vacuous — a create_list decorated @mcp.tool still passed the registration check; the gate pin asserts nothing"
  fi
  ok "t5: READ_ONLY/_write_tool gate lines byte-identical to base, create_list registered under _write_tool, and the @mcp.tool scratch flip demonstrably fails registration (C01 AC5 gate, D4 readonly posture)"
fi

printf 'PASS: wekan-mcp create_list checks (%d ok)\n' "$checks"
