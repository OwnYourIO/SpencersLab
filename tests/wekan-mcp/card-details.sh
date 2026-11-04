#!/usr/bin/env bash
# wekan-mcp get_card_details contract (cf-106 C07, 2026/2026-11-cf-106-feat-
# coord-fixes).
#
# Pins chunks/C07.md AC1-AC2 + the doc half of AC5 for the single-card preload
# read: the tool exists and stays read-only, its response key set is EXACTLY
# the documented one (so a key can neither go missing nor sneak in), checklist
# items carry {title, finished}, dependency lines carry {to_id, type, color},
# the slug stack follows C01's newest-last rule through the ONE parser, and
# get_card + _slim_card stay byte-identical so existing consumers and the
# tools.sh shape pins do not churn.
#
# Statics + pure-helper exec only (the dependencies.sh convention): no server,
# no network. The live-fire legs stay USER-owned (the deployed :v87 build has
# neither this tool nor preload_board).
#
# AC trace: t1[AC1 existence + read-only + get_card untouched]
# t2[AC2 key-set + sub-shapes] t3[AC2 slug-stack wiring through the single
# parser] t4[AC5 doc home: one Card details block section + the tool row].
#
# Red posture: t1-t3 are DESIGNED RED at authoring — get_card_details does not
# exist in server.py, so every red names the missing tool/shape; t4 is red
# until the same commit documents it. Nothing here fails on a harness fault.
#
# Usage:
#   bash tests/wekan-mcp/card-details.sh          # t1..t4
#   bash tests/wekan-mcp/card-details.sh t2 t3    # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SERVER="containers/wekan-mcp/wekan_mcp/server.py"
SKILL="skills/wekan-mcp/SKILL.md"
SHAPES="skills/wekan-mcp/references/call-shapes.md"
PIN_BASE="${CF106_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-4]$ ]] || fail "unknown check id '$a' (expected t1..t4)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$SERVER" ] || fail "harness: $SERVER missing (repo layout fault, not a C07 red)"

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
if want t3; then
  if ! python3 - "$SERVER" <<'PY'
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
# Behavioural half: exec every module-level _slug* helper and require that SOME
# helper yields the ordered stack, newest last (C01 AC3 rule), with the single
# value equal to its last entry.
parsers = [n for n in tree.body if isinstance(n, ast.FunctionDef)
           and n.name.startswith("_slug") and "](" in (ast.get_source_segment(src, n) or "")]
if not parsers:
    print("t3: no module-level _slug* parser carrying the [<slug>](<link>) scan exists to reuse")
    sys.exit(1)
stacks = []
for n in parsers:
    ns = {"Optional": typing.Optional, "Optional_": typing.Optional}
    try:
        exec(ast.get_source_segment(src, n), ns)
        out = ns[n.name]("[old](u1)\n[new](u2)")
    except Exception as exc:  # a helper that cannot run offline is a harness fact, not a contract pass
        print(f"t3: helper {n.name} could not be exercised offline ({exc})")
        sys.exit(1)
    if isinstance(out, (list, tuple)):
        stacks.append((n.name, list(out)))
if not stacks:
    print("t3: no _slug* helper returns the ordered stack (a list) — slug_stack needs a list-valued parser; the single-value helper stays for current_slug")
    sys.exit(1)
name, vals = stacks[0]
if vals != ["old", "new"]:
    print(f"t3: {name}('[old](u1)\\n[new](u2)') -> {vals}, want ['old', 'new'] (C01's newest-last stack order)")
    sys.exit(1)
print("ok")
PY
  then fail "t3[cf-106 C07 AC2]: the slug-stack wiring contract is not satisfied (reason above)"; fi
  ok "t3[cf-106 C07 AC2]: slug_stack/current_slug are emitted through the single module-level parser, and that parser yields the C01 newest-last stack"
fi

# --- t4: the doc home — one Card details block section + the tool row ----------
if want t4; then
  [ -f "$SKILL" ] || fail "t4[cf-106 C07 AC5]: $SKILL missing — the card block format has exactly one doc home and it is this file"
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
  ok "t4[cf-106 C07 AC5]: skills/wekan-mcp/SKILL.md owns exactly one Card details block section, names the tool, and call-shapes.md carries a stamped line-number-free row"
fi

printf 'PASS: wekan-mcp get_card_details checks (%d ok)\n' "$checks"
