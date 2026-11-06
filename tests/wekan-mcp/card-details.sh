#!/usr/bin/env bash
# wekan-mcp get_card_details contract (cf-106 C07, 2026/2026-11-cf-106-feat-
# coord-fixes).
#
# Pins chunks/C07.md AC1-AC2 + the doc half of AC5 for the single-card preload
# read: the tool exists and stays read-only, its response key set is EXACTLY
# the documented one (so a key can neither go missing nor sneak in), checklist
# items carry {title, finished}, dependency lines carry {to_id, type, color},
# the slug stack follows C01's newest-last rule through the ONE parser and is
# pinned in its RULED pair shape, and get_card + _slim_card stay byte-identical
# so existing consumers and the tools.sh shape pins do not churn.
#
# Statics + pure-helper exec only (the dependencies.sh convention): no server,
# no network. The live-fire legs stay USER-owned (the deployed :v87 build has
# neither this tool nor preload_board).
#
# AC trace: t1[AC1 existence + read-only + get_card untouched]
# t2[AC2 key-set + sub-shapes] t3[AC2 slug-stack wiring through the single
# parser + the ruled legacy/pairing shapes] t4[AC5 doc home: one Card details
# block section repo-wide + the tool row] t5[the fail-the-call ruling on the
# per-checklist items route — DECISIONS 2026-11-04 (C06 N1), inherited by C07].
#
# cf-106 C07 test round (2026-11-04, agent-test) — t3's OPEN leg is now closed
# by the coordinator's ruling (round 2): the stack carries a legacy bare value as
# its single entry, `current_slug == slug_stack[-1]` always, and an empty stack
# never sits under a non-empty current_slug. t3 asserts the ruled value shapes
# (bare value, prose, stack + legacy line where the newest entry wins,
# unset/empty/blank as []), and the pair at the response level: both keys start
# as ([], None), every later value comes from a `_slug*` parser, and both keys
# are parsed off the identical field expression. That last half is pinned
# statically on the AST — calling the tool needs a board, so the live-fire pair
# check stays user-owned (the parser-level half, which the tool delegates to in
# full, is asserted by running the real helpers). The checker now runs against
# fabricated copies too (raw current_slug read, split field reads), so neither
# arm is vacuous; slug-stack.sh S1 pins the same ruling on the parsers themselves.
#
# Red posture (wave 3, 2026-11-05): t1-t5 are green against the shipped tree —
# the dev round landed the fail-the-call (a failed checklist-items route raises
# per the DECISIONS 2026-11-04 ruling, inherited from C06), so t5 pins a
# shipped behaviour, not a designed red: its executed half runs the tool offline
# and distinguishes a failed items read from a genuinely empty checklist, and
# its mechanism half bans the swallow shapes with a swallow-free /tmp copy as
# the green-side control and four fabricated degradations (swallow, or-empty,
# fold-to-empty guard, drop-the-checklist guard) plus the legal typed-guard
# spelling as the controls. Nothing here fails on a harness fault.
#
# Usage:
#   bash tests/wekan-mcp/card-details.sh          # t1..t5
#   bash tests/wekan-mcp/card-details.sh t2 t3    # subset
#   WEKAN_SERVER=<path> bash tests/wekan-mcp/card-details.sh t3   # exercise the
#       parser arms against a scratch copy of server.py (non-vacuity probe)
#   WEKAN_SERVER=<path> bash tests/wekan-mcp/card-details.sh t5   # run the
#       fail-the-call arms against a scratch copy (green-side probe)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SERVER="${WEKAN_SERVER:-containers/wekan-mcp/wekan_mcp/server.py}"
SKILL="skills/wekan-mcp/SKILL.md"
SHAPES="skills/wekan-mcp/references/call-shapes.md"
PIN_BASE="${CF106_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-5]$ ]] || fail "unknown check id '$a' (expected t1..t5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$SERVER" ] || fail "harness: $SERVER missing (repo layout fault, not a C07 red)"

TMP=$(mktemp -d /tmp/opencode/card-details-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# --- t1: existence, read-only registration, get_card untouched -----------------
if want t1; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys
src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "get_card_details" not in funcs:
    print("t1: get_card_details is not defined in server.py — cf-106 C07 has not landed the single-card preload read (designed red, not a harness fault)")
    sys.exit(1)
fn = funcs["get_card_details"]
kinds = []
for d in fn.decorator_list:
    if isinstance(d, ast.Attribute) and d.attr == "tool" and isinstance(d.value, ast.Name) and d.value.id == "mcp":
        kinds.append("mcp.tool")
    if isinstance(d, ast.Name) and d.id == "_write_tool":
        kinds.append("_write_tool")
if "_write_tool" in kinds or "mcp.tool" not in kinds:
    print(f"t1: get_card_details decorators {kinds or 'none'} — it must be a bare @mcp.tool read (a _write_tool registration would put a read into the write tier and drop it from the readonly list)")
    sys.exit(1)
argn = [a.arg for a in fn.args.args]
if argn != ["board_id", "card_id"]:
    print(f"t1: get_card_details args {argn}, want (board_id, card_id)"); sys.exit(1)
body = ast.get_source_segment(src, fn) or ""
write_verbs = [v for v in ('".post(', '".patch(', '".delete(', "requests.delete", "method=\"POST\"", "method=\"PATCH\"") if v in body]
if write_verbs:
    print(f"t1: get_card_details contains a write verb {write_verbs} — the tool is read-only (AC1)")
    sys.exit(1)
if "list_checklists" in body or "get_checklist(" in body:
    print("t1: get_card_details fans out through other TOOLS — compose from the client/routes, not by calling sibling tools (the MCP-facing contract)")
    sys.exit(1)
print("ok")
PY
  then fail "t1[cf-106 C07 AC1]: the get_card_details existence/read-only contract is not satisfied (reason above)"; fi
  # get_card + _slim_card byte-identical to the plan base: extract the two
  # source segments from both revisions and compare them.
  if ! python3 - "$SERVER" "$PIN_BASE" <<'PY'
import ast, subprocess, sys
path, base = sys.argv[1], sys.argv[2]
cur = open(path).read()
try:
    old = subprocess.run(["git", "show", f"{base}:{path}"], capture_output=True, text=True, check=True).stdout
except subprocess.CalledProcessError:
    print(f"t1: base ref {base} has no {path} — cannot pin the byte-unchanged contract (harness: set CF106_BASE)")
    sys.exit(1)
def segs(text):
    tree = ast.parse(text)
    return {n.name: ast.get_source_segment(text, n) for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name in ("get_card", "_slim_card")}
c, o = segs(cur), segs(old)
for name in ("get_card", "_slim_card"):
    if name not in c or name not in o:
        print(f"t1: {name} disappeared from one side of the diff (base vs HEAD) — the projection has to stay")
        sys.exit(1)
    if c[name] != o[name]:
        print(f"t1: {name}'s projection changed vs {base} — C07 is additive: get_card stays byte-identical so existing consumers and the tools.sh shape pins do not churn")
        sys.exit(1)
print("ok")
PY
  then fail "t1[cf-106 C07 AC1]: get_card / _slim_card are not byte-identical to $PIN_BASE (reason above)"; fi
  ok "t1[cf-106 C07 AC1]: get_card_details exists as a bare @mcp.tool read with (board_id, card_id), no write verb, no sibling-tool fan-out, and get_card + _slim_card are byte-unchanged"
fi

# --- t2: the response key set, EXACT -------------------------------------------
if want t2; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys
KEYS = {"id", "card_number", "title", "description", "list_id", "swimlane_id",
        "archived", "sort", "parent_id", "label_ids", "labels", "custom_fields",
        "slug_stack", "current_slug", "checklists", "dependencies"}
src = open(sys.argv[1]).read()
tree = ast.parse(src)
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "get_card_details"), None)
if fn is None:
    print("t2: get_card_details is not defined yet — the documented response cannot be checked (designed red before C07 dev)")
    sys.exit(1)
card = None
for n in ast.walk(fn):
    if isinstance(n, ast.Dict):
        ks = {k.value for k in n.keys if isinstance(k, ast.Constant) and isinstance(k.value, str)}
        if len(ks & KEYS) >= 10:
            card = ks
            break
if card is None:
    print("t2: no response dict literal carrying the documented card keys — the tool returns something else (or builds its payload outside a literal the suite can read)")
    sys.exit(1)
missing, extra = sorted(KEYS - card), sorted(card - KEYS)
if missing or extra:
    print(f"t2: response key set drift — missing {missing}, unexpected {extra}; the documented set is EXACT ({sorted(KEYS)})")
    sys.exit(1)
items = []
for n in ast.walk(fn):
    if isinstance(n, ast.Dict):
        ks = {k.value for k in n.keys if isinstance(k, ast.Constant) and isinstance(k.value, str)}
        if ks >= {"title", "finished"} and ks - {"title", "finished"} == set():
            items.append(ks)
if not items:
    print("t2: no checklist-item projection with EXACTLY {title, finished} — item titles are the point of the read (get_checklist proves they are readable)")
    sys.exit(1)
deps = None
for n in ast.walk(fn):
    if isinstance(n, ast.Dict):
        ks = {k.value for k in n.keys if isinstance(k, ast.Constant) and isinstance(k.value, str)}
        if ks >= {"to_id", "type", "color"}:
            deps = ks
if deps is None:
    print("t2: no dependency-line projection carrying {to_id, type, color} — the card's own dependency lines are part of the block")
    sys.exit(1)
if deps - {"to_id", "type", "color"}:
    print(f"t2: dependency projection carries extra keys {sorted(deps)} — want EXACTLY to_id/type/color")
    sys.exit(1)
print("ok")
PY
  then fail "t2[cf-106 C07 AC2]: the get_card_details response shape contract is not satisfied (reason above)"; fi
  ok "t2[cf-106 C07 AC2]: the response key set is EXACTLY the documented sixteen, checklist items project to {title, finished}, dependency lines to {to_id, type, color}"
fi

# --- t3: the slug stack rides C01's single parser, newest last ------------------
# Shipped as a file so the fabricated control copies run the SAME arms as the
# live module (the create-list.sh check-registration.py discipline).
cat >"$TMP/read-shape.py" <<'PY'
import ast, sys, typing

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
fn = funcs.get("get_card_details")
if fn is None:
    print("t3: get_card_details is not defined yet (designed red before C07 dev)")
    sys.exit(1)
body = ast.get_source_segment(src, fn) or ""
if "slug_stack" not in body or "current_slug" not in body:
    print("t3: get_card_details does not emit slug_stack + current_slug — the C01 stack is what lets the run read the current slug without a second round-trip")
    sys.exit(1)
delegates = [ast.unparse(n) for n in ast.walk(fn)
             if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id.startswith("_slug")]
if not delegates:
    print("t3: get_card_details parses the combined slug value inline — C01's Notes forbid a second parser; the module-level _slug* helper is the single authority")
    sys.exit(1)
# Behavioural half: exec ALL module-level _slug* defs into ONE namespace, not one
# helper per namespace. The isolated shape (one exec per function) NameErrors on a
# helper that delegates to its sibling, so it silently FORCES the two-walk shape
# and penalises the cf-96 single-implementation law the same ticket invokes; the
# shared namespace is shape-neutral — green whether the scalar helper has its own
# line-walk or delegates to the stack parser.
parsers = [n for n in tree.body if isinstance(n, ast.FunctionDef)
           and n.name.startswith("_slug")]
if not parsers:
    print("t3: no module-level _slug* parser carrying the [<slug>](<link>) scan exists to reuse")
    sys.exit(1)
ns = {"Optional": typing.Optional}
for n in parsers:
    try:
        exec(ast.get_source_segment(src, n), ns)
    except Exception as exc:  # a helper that cannot run offline is a harness fact, not a contract pass
        print(f"t3: helper {n.name} could not be defined offline ({exc})")
        sys.exit(1)
stack_name = next((n.name for n in parsers
                   if isinstance(ns[n.name]("[old](u1)\n[new](u2)"), (list, tuple))), None)
if stack_name is None:
    print("t3: no _slug* helper returns the ordered stack (a list) — slug_stack needs a list-valued parser; the single-value helper stays for current_slug")
    sys.exit(1)
stack = ns[stack_name]
single_names = [n.name for n in parsers if n.name != stack_name
                and not isinstance(ns[n.name]("[only](u)"), (list, tuple))]
if not single_names:
    print("t3: no scalar _slug* helper resolves the current slug — current_slug must ride the same authority, not an inline read")
    sys.exit(1)

# The ruled value shapes (coord ruling, cf-106 C07 round 2): a value with no
# bracket pair is a ONE-entry stack of itself, a bare line inside a bracketed
# stack is not an entry, and only a missing/blank value is the empty stack.
SHAPES = [("[old](u1)\n[new](u2)", ["old", "new"]),
          ("[a](u1)\n[b](u2)\n[c](u3)", ["a", "b", "c"]),
          ("cf-1-x", ["cf-1-x"]),
          ("just prose, no brackets", ["just prose, no brackets"]),
          ("cf-1-x\n", ["cf-1-x"]),
          ("[a](u1)\n[b](u2)\nlegacy-bare-line", ["a", "b"]),
          ("legacy-bare\n[a](u1)", ["a"]),
          ("[a](u1)\nnotes without brackets", ["a"]),
          ("[old](u1)\n[old](u2)", ["old", "old"]),
          (None, []), ("", []), ("   \n \n", [])]
for value, want in SHAPES:
    got = list(stack(value))
    if got != want:
        print(f"t3: {stack_name}({value!r}) -> {got}, want {want} — the ruled stack shape (C01 AC3 newest-LAST + the cf-106 C07 legacy ruling)")
        sys.exit(1)

# No-drift arm, now in its ruled form: for EVERY value the current slug equals
# the stack's last entry, and an empty stack never sits under a non-empty
# current_slug. The pre-ruling shape (bare legacy value: stack [], current_slug
# non-empty) reddens here, as does any pair that drifts.
for value in [v for v, _ in SHAPES] + ["[only](u)", "[a](u1)\n", "[bad(unclosed", "  ", "\n"]:
    entries = list(stack(value))
    for name in single_names:
        got = ns[name](value)
        if got != (entries[-1] if entries else None):
            print(f"t3: {name}({value!r}) -> {got!r} but {stack_name} -> {entries} — current_slug and slug_stack disagree on the newest entry (C01 AC3 + the cf-106 C07 ruling)")
            sys.exit(1)
        if not entries and got is not None:
            print(f"t3: {name}({value!r}) -> {got!r} over an empty slug_stack — a card never reports a current slug with no stack behind it (ruled cf-106 C07)")
            sys.exit(1)

# Response-level half of the same ruling, pinned on get_card_details' own
# assignments: the pair starts together ([], None), every later value of it comes
# from a _slug* parser (never a raw field read), and both keys are parsed from
# the identical expression so they cannot describe two different reads.
assigned = {}
sites = []
for n in ast.walk(fn):
    if isinstance(n, ast.Assign):
        pairs = [(t, n.value) for t in n.targets]
    elif isinstance(n, ast.AnnAssign):
        pairs = [(n.target, n.value)]
    else:
        continue
    for t, v in pairs:
        if isinstance(t, ast.Name) and t.id in ("slug_stack", "current_slug") and v is not None:
            sites.append((n.lineno, t.id, v))
for _, key, value in sorted(sites, key=lambda s: s[0]):
    assigned.setdefault(key, []).append(value)
for key, shape in (("slug_stack", "an empty list"), ("current_slug", "None")):
    vals = assigned.get(key) or []
    if not vals:
        print(f"t3: get_card_details never assigns {key} — the response pair is not built here")
        sys.exit(1)
    first = vals[0]
    starts_empty = (key == "slug_stack" and isinstance(first, ast.List) and not first.elts) or \
                   (key == "current_slug" and isinstance(first, ast.Constant) and first.value is None)
    if not starts_empty:
        print(f"t3: {key} is first assigned {ast.unparse(first)} instead of {shape} — an unset slug field must yield the pair ([], None), never a half-populated response (ruled cf-106 C07)")
        sys.exit(1)
    for v in vals[1:]:
        if not (isinstance(v, ast.Call) and isinstance(v.func, ast.Name) and v.func.id.startswith("_slug")):
            print(f"t3: {key} is assigned {ast.unparse(v)} — each side of the pair must come from a _slug* parser, never a raw read of the field value (C01 single authority)")
            sys.exit(1)
reads = {key: {ast.unparse(v.args[0]) for v in assigned[key] if isinstance(v, ast.Call) and v.args}
         for key in ("slug_stack", "current_slug")}
if reads["slug_stack"] and reads["current_slug"] and reads["slug_stack"] != reads["current_slug"]:
    print(f"t3: the pair is parsed from different values — slug_stack reads {sorted(reads['slug_stack'])}, "
          f"current_slug reads {sorted(reads['current_slug'])}; the two keys can then describe different fields (ruled cf-106 C07)")
    sys.exit(1)
print("ok")
PY

if want t3; then
  if ! python3 "$TMP/read-shape.py" "$SERVER" >"$TMP/live.out" 2>&1; then
    cat "$TMP/live.out" >&2
    fail "t3[cf-106 C07 AC2]: the slug-stack wiring contract is not satisfied (reason above)"
  fi

  # Controls on the same checker: current_slug taken raw off the field, and the
  # two keys parsed off different expressions. Both are the shapes the ruling
  # forbids; each must redden, and by its own arm.
  ctl_red() {  # $1 = control name, $2 = needle naming the arm that must bite
    if python3 "$TMP/read-shape.py" "$TMP/m-$1.py" >"$TMP/m-$1.out" 2>&1; then
      fail "t3[cf-106 C07 AC2]: control '$1' passes the checker — that arm no longer bites (non-vacuity)"
    fi
    if ! grep -qF -- "$2" "$TMP/m-$1.out"; then
      fail "t3[cf-106 C07 AC2]: control '$1' was caught by the wrong arm: $(head -1 "$TMP/m-$1.out")"
    fi
  }
  grep -qF -- 'current_slug = _slug_from_combined_value(entry.get("value"))' "$SERVER" \
    || fail "t3[AC2]: harness — the current_slug parse line is not where the control builder expects it in $SERVER"
  sed "s|current_slug = _slug_from_combined_value(entry.get(\"value\"))|current_slug = entry.get(\"value\")|" \
    "$SERVER" >"$TMP/m-raw-current.py"
  sed "s|current_slug = _slug_from_combined_value(entry.get(\"value\"))|current_slug = _slug_from_combined_value(card.get(\"title\"))|" \
    "$SERVER" >"$TMP/m-split-read.py"
  if cmp -s "$SERVER" "$TMP/m-raw-current.py"; then
    fail "t3[AC2]: the raw-read control copy is identical to $SERVER (harness fault)"
  fi
  if cmp -s "$SERVER" "$TMP/m-split-read.py"; then
    fail "t3[AC2]: the split-read control copy is identical to $SERVER (harness fault)"
  fi
  ctl_red raw-current "raw read"
  ctl_red split-read "different values"

  ok "t3[cf-106 C07 AC2]: slug_stack/current_slug are emitted through the single module-level parser, that parser yields the C01 newest-last stack in the ruled shapes (legacy bare value = one-entry stack, stack+legacy line = newest wins, unset/empty/blank = []), every value of the pair comes from a _slug* parser on one shared read of the field with ([], None) as its unset shape, and two fabricated copies (raw current_slug read, split reads) each reddening the intended arm"
fi

# --- t4: the doc home — one Card details block section + the tool row ----------
# The "exactly one home" half is repo-wide (round 2 N6): a second file that owns
# a Card details block section — a second prose schema a later round would read
# as normative — reddens here, the same shape as skill-surface.sh t3's
# grep-rlF sole-home arm.
if want t4; then
  [ -f "$SKILL" ] || fail "t4[cf-106 C07 AC5]: $SKILL missing — the card block format has exactly one doc home and it is this file"
  block_homes() {  # $1 = tree root to scan, repo-wide by default
    grep -rlE '^#{2,3}[^#]*Card details block' --include='*.md' \
      --exclude-dir=.git --exclude-dir=node_modules "$1" 2>/dev/null || true
  }
  homes=$(block_homes .)
  if [ "$(printf '%s\n' "$homes" | grep -c .)" -ne 1 ] || [ "$(printf '%s\n' "$homes" | head -1)" != "./$SKILL" ]; then
    fail "t4[cf-106 C07 AC5]: files owning a 'Card details block' section repo-wide: $(printf '%s ' $homes) — AC5 wants exactly one, and it is $SKILL (a second prose home is a second schema the plugin formatter can drift from)"
  fi
  # Non-vacuity: the same scan over a tree that carries a second home must find
  # two — a repo-wide grep that silently matches nothing is the failure mode of
  # every sole-home pin.
  mkdir -p "$TMP/tree/skills/wekan-mcp"
  printf '## Card details block schema\n\nexample\n' >"$TMP/tree/skills/wekan-mcp/SKILL.md"
  printf '### Card details block\n\na second prose home\n' >"$TMP/tree/dup-home.md"
  [ "$(block_homes "$TMP/tree" | grep -c .)" -eq 2 ] \
    || fail "t4[cf-106 C07 AC5]: NEGATIVE CONTROL FAILED — the sole-home scan misses a fabricated second home (the repo-wide arm is decoration)"
  if ! python3 - "$SKILL" "$SHAPES" <<'PY'
import re, sys
skill, shapes = sys.argv[1], sys.argv[2]
text = open(skill).read()
heads = re.findall(r"(?m)^#{2,3}[^\n]*Card details block[^\n]*$", text)
if len(heads) != 1:
    print(f"skills/wekan-mcp/SKILL.md has {len(heads)} 'Card details block' sections — AC5 wants exactly one normative home (the plugin formatter mirrors its bytes)")
    sys.exit(1)
if "get_card_details" not in text:
    print("skills/wekan-mcp/SKILL.md never names get_card_details — the tool surface and the schema live in this file")
    sys.exit(1)
row = [l for l in open(shapes).read().splitlines() if "get_card_details" in l]
if not row:
    print("skills/wekan-mcp/references/call-shapes.md has no get_card_details row (the stamped call-shapes ledger is the caller's contract)")
    sys.exit(1)
if re.search(r"L\d+", row[0]):
    print("the get_card_details call-shape row carries a line-number reference — the ledger pins signatures, not line numbers")
    sys.exit(1)
print("ok")
PY
  then fail "t4[cf-106 C07 AC5]: the card-block doc home contract is not satisfied (reason above)"; fi
  ok "t4[cf-106 C07 AC5]: $SKILL owns the only Card details block section repo-wide (a fabricated second home redden the scan), names the tool, and call-shapes.md carries a stamped line-number-free row"
fi

# --- t5: a failed checklist-items route fails the call (round 2 N4) -----------
# The C06 N1 ruling (DECISIONS 2026-11-04), which C07 inherits: an empty section
# must never stand in for a failed read. The hazard here is per-checklist — a
# card whose items route errors answers `items: []`, byte-identical to a
# checklist with no items, so the plugin appends a block that misstates the
# card's checklist state and its degrade arm (which can only fire on a call that
# ACTUALLY fails) never runs. Two halves, no server and no network:
#   (a) executed — get_card_details runs offline (module-level defs exec'd into
#       one shared namespace, the transport faked at the route level, the
#       receiver derived from the tool's own /api/ calls): a raising items route
#       must not answer the payload a genuinely empty checklist answers;
#   (b) mechanism — the swallow shapes are banned on the AST, with fabricated
#       sources on BOTH sides (the fixed real file must pass, each degraded shape
#       must redden its own arm), so the pin is satisfiable and responsive
#       without dictating the fix's spelling.
if want t5; then
  cat >"$TMP/fail-call.py" <<'PYEOF'
import ast, re, sys

path = sys.argv[1]
src = open(path).read()
tree = ast.parse(src)
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "get_card_details"), None)
if fn is None:
    print("get_card_details is not defined in " + path + " (designed red before C07 dev, not a harness fault)")
    sys.exit(1)

ITEMS = re.compile(r"checklists/\{")
bad = []
items_calls = [n for n in ast.walk(fn) if isinstance(n, ast.Call) and ITEMS.search(ast.unparse(n))]
if not items_calls:
    bad.append("no per-checklist items-route call in get_card_details — the pin cannot see how items are read, so the failed-read contract cannot be checked")

parents = {}
for n in ast.walk(fn):
    for c in ast.iter_child_nodes(n):
        parents[c] = n

def handlers_around(call):
    out, node = [], parents.get(call)
    while node is not None and node is not fn:
        if isinstance(node, ast.Try):
            out.extend(node.handlers)
        node = parents.get(node)
    return out

def emptyish(e):
    if isinstance(e, ast.Dict):
        return not e.keys
    if isinstance(e, (ast.List, ast.Tuple, ast.Set)):
        return not e.elts
    return isinstance(e, ast.Constant) and e.value in (None, "")

for call in items_calls:
    for h in handlers_around(call):
        rethrows = [r for r in ast.walk(h) if isinstance(r, ast.Raise)]
        if not rethrows:
            bad.append(f"the items route sits in a try/except whose handler never raises ({ast.unparse(h).splitlines()[0][:80]} …) — a failed items read becomes items: [], byte-identical to a checklist with no items; the call must fail so the caller's degrade arm can see it (cf-106 C06 N1 ruling, inherited by C07)")

for n in ast.walk(fn):
    if not isinstance(n, (ast.Assign, ast.AnnAssign)) or n.value is None:
        continue
    v = n.value
    if isinstance(v, ast.BoolOp) and isinstance(v.op, ast.Or) \
            and any(isinstance(x, ast.Call) and ITEMS.search(ast.unparse(x)) for x in v.values) \
            and any(emptyish(x) for x in v.values[1:]):
        tgt = ast.unparse(n.targets[0]) if isinstance(n, ast.Assign) else ast.unparse(n.target)
        bad.append(f"the items-route answer falls back to an empty container (`{tgt} = … or {{}}`) — a bodyless answer becomes items: [], the same silent-empty ≡ no-items hazard the swallow has (cf-106 C07 N4)")

items_targets = set()
for n in ast.walk(fn):
    if isinstance(n, (ast.Assign, ast.AnnAssign)) and n.value is not None and ITEMS.search(ast.unparse(n.value)):
        for t in (n.targets if isinstance(n, ast.Assign) else [n.target]):
            if isinstance(t, ast.Name):
                items_targets.add(t.id)

for n in ast.walk(fn):
    if not isinstance(n, ast.If):
        continue
    test = ast.unparse(n.test)
    if not any(name in test for name in items_targets):
        continue
    for st in n.body:
        # Only Assign/AnnAssign carry a target; a Raise here is the house
        # fail-the-call spelling (isinstance check + raise) and must stay legal,
        # so the other statement shapes get no target instead of a crash (R3-M1).
        if isinstance(st, ast.Assign):
            tgt, val = list(st.targets), st.value
        elif isinstance(st, ast.AnnAssign):
            tgt, val = [st.target], st.value
        else:
            tgt, val = [], None
        if val is not None and emptyish(val) \
                and any(isinstance(t, ast.Name) and t.id in items_targets for t in tgt):
            bad.append(f"the items-route answer is folded to an empty container by a guard ({test}) — a malformed or bodyless answer becomes items: [], the same silent-empty ≡ no-items hazard the swallow has (cf-106 C07 N4)")
        if isinstance(st, ast.Continue):
            bad.append(f"a guard on the items-route answer ({test}) drops the checklist from the block — a checklist the card carries but could not read then reads as a card without that checklist (cf-106 C07 N4)")

doc = ast.get_docstring(fn) or ""
OUTCOME = ("keeps", "stays", "continues", "ignored", "skips", "yields", "answers",
           "returns", "becomes", "degrad", "swallow", "left empty")
for sentence in re.split(r"(?<=[.;!?])\s+", doc):
    low = sentence.lower()
    if "item" in low and any(w in low for w in ("fail", "error", "unreadable", "unreachable")) \
            and any(w in low for w in OUTCOME) and any(w in low for w in ("empty", "no items", "none")):
        bad.append(f"the docstring promises a silent empty for a failed items route ({sentence.strip()[:120]!r}) — the documented behaviour is that the call fails; a caller cannot degrade on an answer that claims success (cf-106 C07 N4)")

if bad:
    print("; ".join(bad))
    sys.exit(1)
PYEOF

  cat >"$TMP/fix-copy.py" <<'PYEOF'
# Fabricate the green side from the real file: drop the items-route try/except
# and correct the docstring sentence that promises the swallow. If this copy
# cannot be fabricated, or the checker still rejects it, the pin is unsatisfiable.
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
ITEMS = re.compile(r"checklists/\{")

def has_items(node):
    return any(isinstance(c, ast.Call) and ITEMS.search(ast.unparse(c)) for c in ast.walk(node))


def emptyish(e):
    if isinstance(e, ast.Dict):
        return not e.keys
    if isinstance(e, (ast.List, ast.Tuple, ast.Set)):
        return not e.elts
    return isinstance(e, ast.Constant) and e.value in (None, "")

def strip(node):
    for field, value in ast.iter_fields(node):
        if isinstance(value, list):
            new = []
            for item in value:
                if isinstance(item, ast.Try) and has_items(item):
                    new.extend(item.body)
                else:
                    new.append(item)
                    strip(item)
            setattr(node, field, new)
        elif isinstance(value, ast.AST):
            strip(value)

strip(tree)
for n in ast.walk(tree):
    if isinstance(n, (ast.Assign, ast.AnnAssign)) and isinstance(n.value, ast.BoolOp) \
            and isinstance(n.value.op, ast.Or):
        calls = [x for x in n.value.values if isinstance(x, ast.Call) and ITEMS.search(ast.unparse(x))]
        if len(calls) == 1 and any(emptyish(x) for x in n.value.values if x is not calls[0]):
            n.value = calls[0]
fixed = 0
for n in ast.walk(tree):
    if isinstance(n, ast.Constant) and isinstance(n.value, str) and "items route fails" in n.value:
        n.value = re.sub(r"One checklist whose\s+items route fails[^.]*\.",
                         "A checklist whose items route fails fails the call: an empty item list\n    always means the checklist genuinely has no items.",
                         n.value)
        fixed += 1
ast.fix_missing_locations(tree)
open(sys.argv[2], "w").write(ast.unparse(tree))
if not fixed:
    print("fix-copy: no docstring sentence claiming the items-route swallow — nothing to fix on the doc side")
PYEOF

  # (a) the executed distinction, on the real file and on the fixed copy.
  cat >"$TMP/fail-call-exec.py" <<'PYEOF'
import ast, builtins, re, sys, types, typing

path = sys.argv[1]
src = open(path).read()
tree = ast.parse(src)


class WekanError(Exception):
    pass


class AnyLog:
    def __getattr__(self, _name):
        return lambda *a, **k: None


class FakeMCP:
    def tool(self, fn=None, *a, **k):
        return fn if callable(fn) else (lambda f: f)


ns = {"__name__": "wekan_mcp_offline", "WekanError": WekanError, "log": AnyLog(),
      "mcp": FakeMCP(), "_write_tool": lambda fn: fn, "Optional": typing.Optional}
skipped, invoked = [], []


class Stub:
    def __init__(self, name):
        self.name = name

    def __call__(self, *a, **k):
        if TRACK["on"]:
            invoked.append(self.name)
        return []

    def __getattr__(self, attr):
        if TRACK["on"]:
            invoked.append(f"{self.name}.{attr}")
        return Stub(f"{self.name}.{attr}")


TRACK = {"on": False}

for node in tree.body:
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        try:
            exec(ast.get_source_segment(src, node), ns)
        except Exception:  # the mcp/fastmcp deps are not installed in a pipeline session
            for alias in node.names:
                ns.setdefault(alias.asname or alias.name.split(".")[0], Stub(alias.name))
        continue
    if isinstance(node, (ast.Try, ast.If, ast.With, ast.For, ast.While, ast.Expr, ast.Match,
                         ast.FunctionDef, ast.AsyncFunctionDef)):
        continue  # module side effects: startup validation, __main__; defs come next
    try:
        exec(ast.get_source_segment(src, node), ns)
    except Exception as exc:
        skipped.append(f"{type(node).__name__}: {exc}")

# Registration is not what this leg pins, and the installed mcp stack is not
# available here: every tool def is exec'd against a decorator-neutral namespace.
ns["mcp"] = FakeMCP()
ns["_write_tool"] = lambda fn: fn
for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        try:
            exec(ast.get_source_segment(src, node), ns)
        except Exception as exc:
            skipped.append(f"{node.name}: {exc}")

tool = ns.get("get_card_details")
if not callable(tool):
    print(f"t5: get_card_details could not be defined offline ({'; '.join(skipped) or 'unknown reason'})")
    sys.exit(1)

target = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "get_card_details")


class FakeTransport:
    mode = "raise"

    def __init__(self):
        self.seen = []

    def get(self, route, *a, **k):
        self.seen.append(route)
        if route.endswith("/checklists"):
            return [{"_id": "cl-1", "title": "Lifecycle"}]
        if re.search(r"/checklists/[^/]+$", route):
            if self.mode == "raise":
                raise WekanError("checklist items route answered 500")
            return {"_id": "cl-1", "title": "Lifecycle", "items": []}
        if route.endswith("/custom-fields"):
            return []
        if re.search(r"/boards/[^/]+$", route):
            return {"_id": "B1", "labels": []}
        if "/api/cards/" in route:
            return {"_id": "C1", "cardNumber": 7, "title": "a card", "listId": "L1",
                    "archived": False, "sort": 10, "labelIds": [], "customFields": [],
                    "cardDependencies": []}
        raise AssertionError(f"offline transport has no answer for {route}")


transport = FakeTransport()
receivers = {n.func.value.id for n in ast.walk(target)
             if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
             and isinstance(n.func.value, ast.Name)
             and any("/api/" in ast.unparse(a) for a in n.args)}
if not receivers:
    print("t5: get_card_details makes no /api/ request through a plain name — the offline transport fake cannot attach (harness)")
    sys.exit(2)
for name in receivers:
    ns[name] = transport

for n in ast.walk(target):
    if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load) \
            and n.id not in ns and not hasattr(builtins, n.id):
        ns[n.id] = Stub(n.id)


def run(mode):
    transport.mode = mode
    try:
        return "ok", tool("B1", "C1")
    except Exception as exc:
        return "raised", f"{type(exc).__name__}: {exc}"


failed = run("raise")
empty = run("empty")
if not any(re.search(r"/checklists/[^/]+$", r) for r in transport.seen):
    print("t5: the tool never read the per-checklist items route, so the offline distinction cannot be made (harness)")
    sys.exit(2)
if invoked:
    print(f"t5: the offline namespace had to stub names the tool used ({sorted(set(invoked))}) — the leg cannot model this shape (harness)")
    sys.exit(2)

if failed[0] != "raised":
    print(f"t5: the items-route failure did not fail the call (it answered {failed[0]}: {repr(failed[1])[:200]}) — a card with an unreadable checklist and one with no items are indistinguishable in the block the run reads (cf-106 C07 N4: the C06 N1 fail-the-call ruling)")
    sys.exit(1)
if empty[0] != "ok":
    print(f"t5: a genuinely empty checklist failed the call ({empty[1]}) — the fix must fail on a failed read, not on an empty one")
    sys.exit(1)
if [c.get("items") for c in empty[1].get("checklists", [])] == [[]]:
    print("t5: ok — failed read raises, empty checklist reads")
else:
    print(f"t5: the empty-checklist leg did not answer items: [] ({empty[1].get('checklists')})")
    sys.exit(1)
PYEOF

  if ! python3 "$TMP/fail-call.py" "$SERVER" >"$TMP/t5-live.out" 2>&1; then
    cat "$TMP/t5-live.out" >&2
    fail "t5[cf-106 C07 N4]: a failed checklist-items route does not fail the call (reason above) — the C06 N1 ruling, inherited by C07, requires it to fail the call"
  fi
  if ! python3 "$TMP/fail-call-exec.py" "$SERVER" >"$TMP/t5-exec.out" 2>&1; then
    cat "$TMP/t5-exec.out" >&2
    fail "t5[cf-106 C07 N4]: the executed distinction does not hold offline (reason above) — a failed items read must not answer the payload an empty checklist answers"
  fi

  # Green side, fabricated from the real file: the same two checkers must pass
  # once the swallow is gone and the docstring stops promising it.
  if ! python3 "$TMP/fix-copy.py" "$SERVER" "$TMP/t5-fixed.py" 2>&1; then
    fail "t5[cf-106 C07 N4]: the green-side copy could not be fabricated from $SERVER (harness fault)"
  fi
  python3 "$TMP/fail-call.py" "$TMP/t5-fixed.py" >"$TMP/t5-fixed.out" 2>&1 \
    || { cat "$TMP/t5-fixed.out" >&2; fail "t5[cf-106 C07 N4]: NEGATIVE CONTROL FAILED — a get_card_details without the swallow (and with the matching docstring) still fails the pin: the arm is unsatisfiable as written"; }
  python3 "$TMP/fail-call-exec.py" "$TMP/t5-fixed.py" >"$TMP/t5-fixed-exec.out" 2>&1 \
    || { cat "$TMP/t5-fixed-exec.out" >&2; fail "t5[cf-106 C07 N4]: NEGATIVE CONTROL FAILED — the fixed copy does not fail the call offline: the executed leg is broken, not the tool"; }

  # Satisfiability on the LEGAL spelling at file level: a /tmp copy of $SERVER
  # carrying the typed isinstance-guard + raise (the R2-B2 fix the hardening
  # item ships) must pass both halves — the arm must accept the house
  # fail-the-call form, not only the current tree's shape.
  if ! python3 - "$SERVER" "$TMP/t5-guarded.py" <<'PYGUARD'
import re, sys
src = open(sys.argv[1]).read()
route = re.compile(r'full = _wekan\.get\(\s*f"/api/boards/\{board_id\}/cards/\{card_id\}/checklists/\{cl_id\}"\s*\)')
m = route.search(src)
if not m:
    print("guard-copy: the items-route read is not in the expected shape — cannot fabricate the guard copy (harness)")
    sys.exit(1)
# Insert the typed guard unless it already lands right after the items read.
# (A whole-source string test is wrong: other tools already use isinstance on
# a `full` of their own.) The target is written either way, so the checkers
# always have a file to run on.
rest = src[m.end():]
if rest.lstrip().startswith("if not isinstance(full, dict):"):
    open(sys.argv[2], "w").write(src)
    sys.exit(0)
guard = (
    '        if not isinstance(full, dict):\n'
    '            raise WekanError("get_card_details: the checklist items route did not answer a dict")\n'
)
open(sys.argv[2], "w").write(src[:m.end()] + "\n" + guard + rest)
PYGUARD
  then
    fail "t5[cf-106 C07 R3-M1]: the guard-bearing copy could not be fabricated from $SERVER (harness fault)"
  fi
  python3 "$TMP/fail-call.py" "$TMP/t5-guarded.py" >"$TMP/t5-guarded.out" 2>&1 \
    || { cat "$TMP/t5-guarded.out" >&2; fail "t5[cf-106 C07 R3-M1]: the guard-bearing file is rejected by the mechanism half — the arm is unsatisfiable on the legal spelling"; }
  python3 "$TMP/fail-call-exec.py" "$TMP/t5-guarded.py" >"$TMP/t5-guarded-exec.out" 2>&1 \
    || { cat "$TMP/t5-guarded-exec.out" >&2; fail "t5[cf-106 C07 R3-M1]: the guard-bearing file does not fail the call offline — the executed half is broken on the legal spelling"; }

  # Degraded synthetics: each shape must redden its own arm, so no arm is
  # decoration and the ban is not spelled for one implementation only.
  python3 - "$TMP" <<'PYEOF'
import sys
tmp = sys.argv[1]
BASE = '''"""Synthetic get_card_details for the cf-106 C07 t5 arms."""


def get_card_details(board_id, card_id):
    """One card read with its checklists.

    A checklist whose items route fails fails the call: an empty item list
    always means the checklist genuinely has no items.
    """
    card = _wekan.get(f"/api/cards/{card_id}")
    checklists = []
    for header in _wekan.get(f"/api/boards/{board_id}/cards/{card_id}/checklists"):
        cl_id = header.get("_id")
__ITEMS_READ__
        checklists.append({"id": cl_id, "title": header.get("title"),
                           "items": [{"title": i.get("title"), "finished": bool(i.get("isFinished"))}
                                     for i in (full.get("items") or [])]})
    return {"id": card.get("_id"), "checklists": checklists}
'''
ROUTE = '_wekan.get(f"/api/boards/{board_id}/cards/{card_id}/checklists/{cl_id}")'
VARIANTS = {
    "swallow": f'        try:\n            full = {ROUTE}\n        except WekanError as exc:\n            log.warning("items unreadable: %s", exc)\n            full = {{}}',
    "or-empty": f'        full = {ROUTE} or {{}}',
    "guard-empty": f'        full = {ROUTE}\n        if not isinstance(full, dict):\n            full = {{}}',
    "guard-continue": f'        full = {ROUTE}\n        if not isinstance(full, dict):\n            continue',
}
for name, read in VARIANTS.items():
    open(f"{tmp}/s-{name}.py", "w").write(BASE.replace("__ITEMS_READ__", read))
# The house fail-the-call spelling (isinstance guard + raise): must PASS the
# checker — the R3-M1 fix is that the typed guard is a legal spelling, and a
# checker that still rejects it means the scan is over-strict again.
open(f"{tmp}/s-guard-raise.py", "w").write(
    BASE.replace("__ITEMS_READ__",
                 f'        full = {ROUTE}\n        if not isinstance(full, dict):\n            raise WekanError("items route did not answer a dict")'))
open(f"{tmp}/s-doc-swallow.py", "w").write(
    BASE.replace("__ITEMS_READ__", f"        full = {ROUTE}")
        .replace("always means the checklist genuinely has no items.",
                 "One checklist whose items route fails keeps the checklist with an empty item list."))
PYEOF
  ctl_red() {  # $1 = synthetic name, $2 = needle naming the arm that must bite
    if python3 "$TMP/fail-call.py" "$TMP/s-$1.py" >"$TMP/s-$1.out" 2>&1; then
      fail "t5[cf-106 C07 N4]: control '$1' passes the checker — that arm no longer bites (non-vacuity)"
    fi
    if ! grep -qF -- "$2" "$TMP/s-$1.out"; then
      fail "t5[cf-106 C07 N4]: control '$1' was caught by the wrong arm: $(head -1 "$TMP/s-$1.out")"
    fi
  }
  ctl_green() {  # $1 = control name: a LEGAL spelling that must pass the checker
    if ! python3 "$TMP/fail-call.py" "$TMP/s-$1.py" >"$TMP/s-$1.out" 2>&1; then
      cat "$TMP/s-$1.out" >&2
      fail "t5[cf-106 C07 R3-M1]: control '$1' fails the checker — the scan rejects a legal fail-the-call spelling (over-strict scan regressed)"
    fi
  }
  # The legal spelling must PASS the checker (R3-M1: the old scan crashed on a
  # Raise in the guard body and thereby banned the house fail-the-call form).
  if ! python3 "$TMP/fail-call.py" "$TMP/s-guard-raise.py" >"$TMP/s-guard-raise.out" 2>&1; then
    cat "$TMP/s-guard-raise.out" >&2
    fail "t5[cf-106 C07 R3-M1]: the typed isinstance-guard + raise spelling (the house fail-the-call form) is rejected by the mechanism half — the scan over-strictness is back"
  fi
  ctl_red swallow "handler never raises"
  ctl_red or-empty "falls back to an empty container"
  ctl_red guard-empty "folded to an empty container"
  ctl_red guard-continue "drops the checklist from the block"
  ctl_red doc-swallow "docstring promises a silent empty"
  ctl_green guard-raise

  ok "t5[cf-106 C07 N4/R3-M1]: a failed checklist-items route fails the call — executed offline (a raising items route never answers the payload an empty checklist answers) and pinned on the mechanism (no handler without a raise, no or-empty fallback, no guard folding the answer to empty or dropping the checklist, no docstring promising a silent empty), with the swallow-free copy of $SERVER passing every arm, five fabricated degradations each reddening its own arm, and the typed guard spelling accepted at synthetic AND file level"
fi

printf 'PASS: wekan-mcp get_card_details checks (%d ok)\n' "$checks"
