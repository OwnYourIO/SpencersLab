#!/usr/bin/env bash
# wekan-mcp create_list contract (2026/2026-10-cf-68-feat-wekan-mcp-create-list,
# C01): the 14th @_write_tool tool — pinned signature, the three REST legs
# (create POST, position-gated reposition move, read-back hydration GET) with
# their non-failing failure arms, the READ_ONLY/_write_tool privilege gate
# staying byte-stable, the AC7 deploy-block landing posture, and the
# doc-surface count-parity greps (26->27 at authoring, 31 by cf-89 v102, 38 by
# cf-96 C01 — and since cf-106 C07 no literal at all: t3 compares the docs to
# the count read out of server.py, see below).
#
# Contract source: chunks/C01.md "## Tests" and "## Acceptance criteria".
# AC trace: t1[AC4] t2[AC5+AC7] t3[AC6] t4[AC2] t5[AC5 gate + D4].
#
# cf-106 C07 test round (2026-11-04, agent-test) — two legs re-pinned from
# cf-96-era spellings: t3's "38 typed tools" / "full, 38 tools" / "all 38 tools"
# greps became the shared registry-parity helper (claims + rows) plus arms
# derived from the live count, so a sanctioned +1 (get_card_details) cannot
# redden a doc-parity gate that asserted nothing about the docs, and a doc that
# deleted its count cannot slip past a claims-only scan. And t2's AC7 whole-file
# hunk-count pin is now the content assertion the cf-96 wording was always
# proxying: the coordinator ruled a literal count unsatisfiable on a branch
# where a second ticket edits server.py (cf-106 does — 17 hunks), so what is
# pinned is the landing itself — one module-level create_list under the WRITE
# TOOLS banner, its create/move legs carried by no other def, and its region
# byte-identical to the block already at the base (one added block, if it is new
# there). The leg-scatter and region-edit copies keep both arms non-vacuous.
# t4 is transitively red through tools.sh's t5 only while that leg is red.
#
# Statics-only by design (DECISIONS Conventions — same posture as tools.sh and
# skill-surface.sh): ast + greps, no fastmcp import, no network, no pytest
# harness. Assertions cite server.py function names, never line numbers
# (t2's AC7 arm resolves the def with ast and reports its region, so the
# numbers in its message are derived, never hard-coded).
#
# Red before C01's dev lands: t1/t2/t5 on the absent create_list, t3 on the
# 26-count docs, t4 via the siblings' re-pinned 31 counts. Every red names
# not-yet-implemented behavior, never a harness fault.
#
# CF68_BASE=<ref> re-points the base blob the byte-pins and the block-landing
# pin diff against (default: merge-base of main and HEAD — the pre-ticket
# state; pass the pre-chunk commit if main legitimately moved server.py since).
#
# Usage:
#   bash tests/wekan-mcp/create-list.sh            # t1..t5
#   bash tests/wekan-mcp/create-list.sh t1 t2      # subset
#   WEKAN_SERVER=<path> bash tests/wekan-mcp/create-list.sh t3   # re-derive the
#       doc-parity arms against a scratch copy of server.py (non-vacuity probe)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SERVER="${WEKAN_SERVER:-containers/wekan-mcp/wekan_mcp/server.py}"
WEKAN_PY="containers/wekan-mcp/wekan_mcp/wekan.py"
README="containers/wekan-mcp/README.md"
SKILL_MCP="skills/wekan-mcp/SKILL.md"
CALLS="skills/wekan-mcp/references/call-shapes.md"
SKILL_API="skills/wekan-api/SKILL.md"
TOOLS_SUITE="tests/wekan-mcp/tools.sh"
SURFACE_SUITE="tests/wekan-mcp/skill-surface.sh"
PARITY="tests/wekan-mcp/registry-parity.py"
BASE="${CF68_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

git rev-parse --verify "$BASE" >/dev/null 2>&1 \
  || fail "harness: base ref '$BASE' does not resolve (CF68_BASE=<ref>)"

TMP=$(mktemp -d /tmp/opencode/create-list-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# The base copy always comes from the repo path, never from WEKAN_SERVER: a
# scratch-copy probe overrides only the working-tree side of the byte-pins.
git show "$BASE:containers/wekan-mcp/wekan_mcp/server.py" >"$TMP/server.base.py" \
  || fail "harness: containers/wekan-mcp/wekan_mcp/server.py missing at $BASE"

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

# Doc parity compares against the LIVE registry (exit 2 = harness fault), so a
# sanctioned +1 cannot leave a doc that quietly disagrees with server.py.
read -r REG_READS REG_WRITES REG_TOTAL < <(python3 "$PARITY" counts "$SERVER") \
  || fail "harness: $PARITY could not read the registry out of $SERVER"

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

# t2's behavior/gate/landing checker, shipped as a file so the fabricated
# controls run the SAME arms as the live file (the check-registration.py /
# t5 red-green discipline: one implementation, so a probe cannot drift from
# what it claims to falsify).
cat >"$TMP/check-behavior.py" <<'PY'
import ast, difflib, re, sys

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

# 8) AC7 landing — CONTENT, not a hunk count (re-pinned cf-106 C07, coordinator
# ruling on the cf-96 AC7 wording). The count was only ever a proxy for "one
# reviewable deploy block", and a whole-file count cannot survive a branch where
# another ticket also edits server.py (cf-106 C02/C06/C07 all do). So pin the
# block by what it is: one module-level def, under the WRITE TOOLS banner,
# carrying its own provisioning legs with no sibling def carrying them, landing
# as one contiguous region the base->working comparison never touches inside —
# byte-identical to the block already at the base, or one added block there.
lines = src.split('\n')
base_lines = base_src.split('\n')
start = min([fn.lineno] + [d.lineno for d in fn.decorator_list])
end = fn.end_lineno
region = '\n'.join(lines[start - 1:end])
try:
    base_tree = ast.parse(base_src)
except SyntaxError:
    base_tree = None
base_fn = next((n for n in base_tree.body
                if isinstance(n, ast.FunctionDef) and n.name == 'create_list'), None) if base_tree else None

banner = [i + 1 for i, l in enumerate(lines) if l.startswith('#') and 'WRITE TOOLS' in l]
if not banner:
    bad('t2[AC7]: server.py has no WRITE TOOLS banner — the section AC7 names the landing position is gone (harness fault)')
if start < banner[-1]:
    bad(f't2[AC7]: create_list (line {start}) does not sit below the WRITE TOOLS banner (line {banner[-1]}) '
        f'— AC7 lands the write tool in the WRITE TOOLS section')

# Region analysis is content-based (base blob vs the working copy), not
# `git diff`-based: a scratch control copy is not in git, and an arm that only
# evaluates against the tracked file is vacuous for every fabricated copy.
if base_fn is not None:
    b_start = min([base_fn.lineno] + [d.lineno for d in base_fn.decorator_list])
    if '\n'.join(base_lines[b_start - 1:base_fn.end_lineno]) != region:
        bad('t2[AC7]: the create_list deploy block is not byte-identical to the block already at the base '
            f'(region lines {start}-{end}) — the reviewed deploy block must stay untouched on this branch')

ops = difflib.SequenceMatcher(None, base_lines, lines, autojunk=False).get_opcodes()
overlap = [o for o in ops if o[0] != 'equal' and (o[3] + 1) <= end and o[4] >= start]
if base_fn is not None:
    if overlap:
        bad(f't2[AC7]: {len(overlap)} changed region(s) of the base->working diff touch the create_list '
            f'landing (lines {start}-{end}) — the reviewed deploy block must stay byte-identical (AC7)')
elif len(overlap) != 1 or overlap[0][0] != 'insert' \
        or '\n'.join(lines[overlap[0][3]:overlap[0][4]]).strip() != region.strip():
    bad(f't2[AC7]: create_list does not land as ONE contiguous added block (region {start}-{end}; '
        f'{len(overlap)} changed region(s) touch it: {[(o[0], o[3] + 1, o[4]) for o in overlap]}) '
        f'— AC7 wants one reviewable deploy block, not legs spread over the file')


def routes(node):
    """(verb, route-with-placeholders) for every _wekan.<verb>(route, ...) call."""
    out = []
    for c in ast.walk(node):
        if not (isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
                and isinstance(c.func.value, ast.Name) and c.func.value.id == '_wekan'
                and c.func.attr in ('get', 'post', 'put', 'delete') and c.args):
            continue
        arg = c.args[0]
        if isinstance(arg, ast.JoinedStr):
            parts = [v.value if isinstance(v, ast.Constant) and isinstance(v.value, str) else '{}'
                     for v in arg.values]
        elif isinstance(arg, ast.Constant) and isinstance(arg.value, str):
            parts = [arg.value]
        else:
            continue
        out.append((c.func.attr, ''.join(parts)))
    return out


# Route norms come out of routes() with every interpolated id replaced by {}, so
# these literals are exact matches, not substring greps.
LEGS = [('post', lambda r: r == '/api/boards/{}/lists', 'the createList POST'),
        ('post', lambda r: r.startswith('/api/boards/{}/lists/') and r.endswith('/move'),
         'the position-gated /move POST'),
        ('get', lambda r: r == '/api/boards/{}/lists/{}', 'the single-list read-back GET')]
mine = routes(fn)
for verb, pred, label in LEGS:
    if not any(v == verb and pred(r) for v, r in mine):
        bad(f't2[AC7]: {label} no longer sits inside the create_list body — the provisioning legs must live '
            f'in the one reviewed deploy block (AC7)')
# Exclusivity is pinned for the WRITE legs only: list_lists legitimately GETs the
# same list routes, so a GET-based exclusivity claim would be false.
for verb, pred, label in LEGS[:2]:
    holders = [n.name for n in tree.body
               if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
               and any(v == verb and pred(r) for v, r in routes(n))]
    if holders != ['create_list']:
        bad(f't2[AC7]: {label} is held by {holders} — create_list scattered its legs into another def '
            f'(AC7: one reviewable deploy block)')
PY

# Control copies for t2's AC7 landing arm, built from the live source so they
# cannot drift from it; a mutation that no longer applies is a harness fault
# (exit 2), never a silent pass.
cat >"$TMP/mutate-create-list.py" <<'PY'
import sys

src = open(sys.argv[1]).read()
lines = src.split('\n')
banner = next((i for i, l in enumerate(lines) if l.startswith('#') and 'WRITE TOOLS' in l), None)
if banner is None:
    print('control sibling-legs: no WRITE TOOLS banner in the live source (harness fault)'); sys.exit(2)
probe = '''

def _cf106_scatter_probe(board_id: str, list_id: str) -> dict:
    _wekan.post(f"/api/boards/{board_id}/lists", json_body={"title": "x"})
    _wekan.post(f"/api/boards/{board_id}/lists/{list_id}/move", json_body={"position": 1})
    return _wekan.get(f"/api/boards/{board_id}/lists/{list_id}")'''
out = {}
out['sibling-legs'] = '\n'.join(lines[:banner + 1] + [probe] + lines[banner + 1:])

target = '    list_id = resp.get("_id")'
if lines.count(target) != 1:
    print('control region-edit: the create_list _id read is not unique in the live source (harness fault)'); sys.exit(2)
out['region-edit'] = '\n'.join(l for l in lines if l != target)

names = list(out)
for name in names:
    if out[name] == src:
        print(f'control {name}: mutation was a no-op against the live source (harness fault)'); sys.exit(2)
for i, name in enumerate(names):
    open(sys.argv[2 + i], 'w').write(out[name])
print(' '.join(names))
PY

# --- t1: registration + pinned signature (C01 AC4) ----------------------------
if want t1; then
  python3 "$TMP/check-registration.py" "$SERVER" \
    || fail "t1: the create_list registration contract is violated (C01 AC4 — reason above)"
  ok "t1: exactly one top-level create_list, decorated @_write_tool, params board_id/title/swimlane_id/position Optional[str]=None/Optional[int]=None, returns dict (C01 AC4)"
fi

# --- t2: behavior literals + gate integrity + AC7 landing (C01 AC5, AC7) -------
if want t2; then
  git diff --quiet "$BASE" -- "$WEKAN_PY" \
    || fail "t2: $WEKAN_PY changed since $BASE — C01 rides the existing _wekan helpers, it must not edit the client (plan out-of-scope, AC7 byte-pin like tools.sh t8)"

  python3 "$TMP/check-behavior.py" "$SERVER" "$TMP/server.base.py" "$BASE" \
    || fail "t2: the create_list behavior/gate contract is violated (C01 AC5+AC7 — reason above)"

  # Fabricated controls on the same checker: a copy that scatters create_list's
  # POST legs into a second module-level def, and a copy that edits one line
  # inside the landed deploy block. Each must redden, at the named arm.
  python3 "$TMP/mutate-create-list.py" "$SERVER" "$TMP/m-sibling-legs.py" "$TMP/m-region-edit.py" >/dev/null \
    || fail "t2[AC7]: a control copy could not be built from $SERVER (harness fault)"
  ctl_red() {
    if python3 "$TMP/check-behavior.py" "$TMP/m-$1.py" "$TMP/server.base.py" "$BASE" >"$TMP/m-$1.out" 2>&1; then
      fail "t2[AC7]: control '$1' passes the checker — the AC7 landing arm no longer bites (non-vacuity)"
    fi
    if ! grep -qF -- "$2" "$TMP/m-$1.out"; then
      fail "t2[AC7]: control '$1' was caught by the wrong arm: $(head -1 "$TMP/m-$1.out")"
    fi
  }
  ctl_red sibling-legs "scattered"
  # The region-edit control pins the byte-identity arm, which only exists when
  # the base already carries the block. On a base that predates create_list the
  # block's own content is what lands, so byte-identity is inapplicable there
  # (and the one-added-block branch is what the live run pins instead).
  if grep -qE '^def create_list\(' "$TMP/server.base.py"; then
    ctl_red region-edit "byte-identical"
  else
    printf 'note: t2: base %s predates create_list — no byte-identity control to run there\n' "$BASE" >&2
  fi

  ok "t2: create legs pinned (conditional swimlaneId, position-gated move without toBoardId, hydration GET), non-raising distinct arms, positioned/position_error/sort/swimlane_id surfaced, no httpx, no new env, wekan.py byte-identical, and create_list lands as one contiguous deploy region under the WRITE TOOLS banner, byte-identical to the base (one added block on a base that predates it) and carried by no other def — plus the fabricated copies (legs scattered into a sibling def; one line edited inside the region, where that byte arm applies) each reddening the intended arm (C01 AC5+AC7)"
fi

# --- t3: doc parity across the four surfaces (C01 AC6) -------------------------
if want t3; then
  python3 "$PARITY" claims "$SERVER" "$README" "$SKILL_MCP" "$CALLS" "$SKILL_API" \
    || fail "t3: a tool-count claim across README/SKILL/call-shapes/wekan-api no longer matches the registry ($REG_TOTAL = $REG_READS reads + $REG_WRITES writes) — the cf-68 parity greps compared three hard-coded numbers; parity means doc↔server.py (C01 AC6; reason above)"
  python3 "$PARITY" rows "$SERVER" "$README" "$CALLS" \
    || fail "t3: README's Tools-exposed table and the call-shapes ledger must carry exactly one row per registered tool name (C01 AC6 — missing row = undocumented tool, duplicate/unregistered name = drift; reason above)"
  grep -qE '^\| `create_list` \|' "$README" \
    || fail "t3: the $README Tools table has no create_list row (C01 AC6)"

  n=$(grep -cF "full, $REG_TOTAL tools" "$SKILL_MCP" || true)
  [ "$n" -eq 2 ] \
    || fail "t3: $SKILL_MCP tier table has $n 'full, $REG_TOTAL tools' cells, expected 2 — dev-boards and admin-global-wekan flip, readonly stays 'none' (C01 AC6)"
  git show "$BASE:$SKILL_MCP" | grep -F '| `readonly-global-wekan` |' >"$TMP/ro.base" || true
  grep -F '| `readonly-global-wekan` |' "$SKILL_MCP" >"$TMP/ro.now" || true
  cmp -s "$TMP/ro.base" "$TMP/ro.now" \
    || fail "t3: the readonly tier row changed — the _write_tool gate is the whole privilege story, its row must stay byte-identical (D4, C01 AC6)"

  n=$(grep -cE '^\|\s*`create_list`\s*\|' "$CALLS" || true)
  [ "$n" -eq 1 ] \
    || fail "t3: $CALLS has $n create_list rows, expected exactly 1 (C01 AC6)"
  grep -E '^\|\s*`create_list`\s*\|' "$CALLS" | grep -qF 'source-only' \
    || fail "t3: the create_list call-shapes row carries no source-only evidence stamp — the live probe is post-merge/user-owned (D7, C01 AC6)"

  for f in "$README" "$SKILL_MCP" "$CALLS" "$SKILL_API"; do
    grep -Eq "($REG_TOTAL typed tools|full, $REG_TOTAL tools|all $REG_TOTAL tools)" "$f" \
      || fail "t3: $f states no tool count at all — dropping the count would slip past a claims-only scan, so the count must be present and equal $REG_TOTAL (C01 AC6)"
  done
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
  ok "t3: README ($REG_TOTAL + create_list row), wekan-mcp SKILL tiers (two $REG_TOTAL cells, readonly byte-stable), call-shapes (one stamped create_list row) and wekan-api SKILL all agree with the live registry ($REG_TOTAL = $REG_READS reads + $REG_WRITES writes) at name level, and no other tool count survives in the four docs (C01 AC6)"
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
