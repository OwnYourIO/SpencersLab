#!/usr/bin/env bash
# wekan-mcp cf-96 dependency/preload/label-surface contract
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C01).
#
# Pins chunks/C01.md "## Tests" + AC2 + AC4: the five Red Strings dependency
# tools 1:1 to the RESEARCH 1.3 routes, the preload_board one-call export
# reshape, the set_card_labels bulk wrapper (AD-74), the _slim_card
# passthroughs, and the create_card parent_id two-step — plus the doc-parity
# re-stamp the same commit must carry. The tools.sh re-pin of the registry
# arithmetic (17+21/38) and the README/SKILL count lines land in C01's dev
# commit (doc-parity pins are never red between commits, DECISIONS
# convention); THIS file is the designed-red contract the dev implements to,
# named here because the assertions below ARE the interface.
#
# Pinned response-shape names (C01 T2/T3 interface): preload_board returns
# keys {"board_id","swimlanes","lists","cards"? no — grouped: "swimlanes"
# (each with "lists", each with "cards"), "dependencies", "label_names",
# "field_names"}; EVERY per-card dict EXACTLY {id, card_number, label_ids,
# slug, archived, sort, parent_id, checklists}; set_card_labels args (board_id,
# card_ids, add_label_ids=None, remove_label_ids=None); create_card's parent_id
# is the TRAILING parameter after default_checked.
#
# AC trace: t1[C01 AC2 — dep signatures, 7-type client gate, upsert doc,
# DESTRUCTIVE mark, registration kinds] t2[AC2 — preload reshape contract
# incl. archived-flagged-not-dropped + no title/description] t3[AC2 —
# set_card_labels bulk shape + ≤500 cap + board-label validation] t4[AC2 —
# _slim_card passthroughs + list_cards_in_list stays strip-accurate] t5[AC2 —
# create_card two-step, non-rollback, OQ1 negative: no auto-edge] t6[AC4 —
# docs re-stamped, evidence stamps source-only 2026-11, nothing live-claimed]
# t7[AC3 — wekan.py byte-unchanged (tools.sh t8 posture)]
# t8[C11 AC1 — _slim_rule 7-key capture projection: extras + enabled ride the
#     route documents un-reshaped, get_rule/list_rules stay plain @mcp.tool
#     (readonly tier), docstrings re-stamped. GREEN ON ARRIVAL after C11 dev
#     lands (red at the pre-C11 tree — the four-key projection structurally
#     cannot answer the schema-2 capture, RESEARCH F5).
#
# Red posture: t1–t5 are DESIGNED RED at authoring — verified 2026-11-01:
# none of the seven new names exists in server.py; every red names the
# missing tool/shape, never a harness fault. t6 red until the same-commit
# re-stamp; t7 green at base, HOLD (turns red the moment dev edits wekan.py).
#
# AC trace (cf-106 C06): t9[AC1/AC4 — one request carries `checklists`, the
# standard-five + legacy Research vocabulary, {title, finished} items, docstring
# enumerates the sets] t10[AC2/AC4 — title beside id on swimlane and list
# entries, empty groups unemitted, sort-field re-ordering, no description key]
# t11[AC3 + review N1 — swimlane_titles optional, None = every swimlane, a real
# filter branch, unknown title = the documented empty grouping with NO raise on
# the filter path, and a malformed non-dict export answer FAILS the call (the
# boards degrade law's present-but-failed branch needs a failed call: an empty
# grouping is contractually an empty board, so a pickup walk would mark
# no-cards, write the no-op marker and archive silently)].
# t11's fail-the-call leg is DESIGNED RED until C06 round 2 replaces the
# `doc = {}` swallow (landed in ec31b2e50 — GREEN at this tree); the compliant
# fixture (filter kept + guarded transport raise) proves the leg is satisfiable,
# and preload-filter-raise.py proves the raise ban is scoped to the filter path
# rather than blanket.
#
# cf-106 C07 test round (2026-11-04, agent-test) — leg re-pinned from cf-96-era
# literals: t6's "38 typed tools" / "full, 38 tools" / "all 38 tools" greps and
# its 31/30 stale-enumeration negatives now compare the docs against the count
# read out of server.py (tests/wekan-mcp/registry-parity.py), so the leg asserts
# doc↔registry parity instead of a third hard-coded number and cannot be reddened
# by a sanctioned +1 that docs followed. Its red at this tree is real:
# skills/wekan-api/SKILL.md still calls the surface "38-tool" (C07's AC6 gap).
#
# cf-106 C06 test round (2026-11-04, agent-test; reviewer N1 + N2): t11's raise
# ban was blanket (any Raise in preload_board), which over-implemented AC3 and is
# what pushed the round-1 dev into swallowing a malformed export answer into the
# empty grouping — contractually identical to an empty board, so a pickup walk
# would mark no-cards, write the no-op marker and archive. The ban is now scoped
# to the filter arm and t11 additionally requires the malformed answer to fail
# the call. t2's card-key arm is `all` (a compliant map no longer masks a decoy
# carrying `title`) and its stale "seven fields" wording says eight. No assertion
# vocabulary elsewhere changed; the fixture fabricator now fails loudly (a
# non-matching anchor used to build a copy identical to the compliant source).
#
# Statics-only by design (D8 / DECISIONS convention): AST + grep over the
# source, no server, no network. The live round-trip is the C10 runbook's
# user probe.
#
# Usage:
#   bash tests/wekan-mcp/dependencies.sh            # t1..t11
#   bash tests/wekan-mcp/dependencies.sh t2 t5      # subset
#   CF96_BASE=<ref> bash tests/wekan-mcp/dependencies.sh t7
#   WEKAN_SERVER=<path> bash tests/wekan-mcp/dependencies.sh t11   # re-derive an
#       arm against a patched copy of server.py (out-of-tree proof of satisfiability)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SERVER="${WEKAN_SERVER:-containers/wekan-mcp/wekan_mcp/server.py}"
WEKAN_PY="containers/wekan-mcp/wekan_mcp/wekan.py"
README="containers/wekan-mcp/README.md"
SKILL_MCP="skills/wekan-mcp/SKILL.md"
SHAPES="skills/wekan-mcp/references/call-shapes.md"
SKILL_API="skills/wekan-api/SKILL.md"
PIN_BASE="${CF96_BASE:-$(git merge-base main HEAD)}"
PARITY="tests/wekan-mcp/registry-parity.py"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8 9 10 11; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[01])$ ]] || fail "unknown check id '$a' (expected t1..t11)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$SERVER" ] || fail "harness: $SERVER missing (repo layout fault, not a C01 red)"
[ -f "$PARITY" ] || fail "harness: $PARITY missing (repo layout fault, not a C01 red)"

# Doc↔registry parity compares against the LIVE registry (exit 2 from the helper
# is a harness fault, never a contract red), so a sanctioned +1 cannot leave a
# suite green on prose that no longer describes server.py.
read -r REG_READS REG_WRITES REG_TOTAL < <(python3 "$PARITY" counts "$SERVER") \
  || fail "harness: $PARITY could not read the registry out of $SERVER"

# --- t1: the five dependency tools (C01 T1) --------------------------------------
if want t1; then
  if ! python3 - "$SERVER" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)

def dec_kind(fn):
    for d in fn.decorator_list:
        if isinstance(d, ast.Attribute) and d.attr == "tool" \
           and isinstance(d.value, ast.Name) and d.value.id == "mcp":
            return "read"
        if isinstance(d, ast.Name) and d.id == "_write_tool":
            return "write"
    return None

funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def seg(name):
    fn = funcs.get(name)
    if fn is None:
        print(f"t1: {name} is not defined in server.py yet — the cf-96 C01 T1 dependency block has not landed (designed red before C01 dev, not a harness fault)")
        sys.exit(1)
    return ast.get_source_segment(src, fn)

# registration kinds: 2 bare reads, 3 writes through _write_tool ONLY
for n in ("list_board_dependencies", "list_card_dependencies"):
    if n not in funcs:
        print(f"t1: {n} is not defined in server.py yet — the cf-96 C01 T1 dependency block has not landed (designed red before C01 dev, not a harness fault)")
        sys.exit(1)
    if dec_kind(funcs[n]) != "read":
        print(f"t1: {n} must be registered as a bare @mcp.tool READ (present on every tier)"); sys.exit(1)
WRITE3 = ("add_card_dependency", "edit_card_dependency", "remove_card_dependency")
for n in WRITE3:
    kind = dec_kind(funcs[n]) if n in funcs else None
    if kind != "write":
        print(f"t1: {n} must register through _write_tool (readonly tier hides writes by construction), kind seen: {kind}"); sys.exit(1)
    if "mcp.tool" in seg(n):
        print(f"t1: {n} body re-registers outside _write_tool — the AC2 negative pin"); sys.exit(1)

def args(name):
    return [(a.arg, ast.unparse(a.annotation) if a.annotation else None) for a in funcs[name].args.args]

a = args("list_board_dependencies"); 
if [x[0] for x in a] != ["board_id"]:
    print(f"t1: list_board_dependencies args {[x[0] for x in a]}, want (board_id)"); sys.exit(1)
a = args("list_card_dependencies")
if [x[0] for x in a] != ["board_id", "card_id"]:
    print(f"t1: list_card_dependencies args {[x[0] for x in a]}, want (board_id, card_id)"); sys.exit(1)
for n in ("add_card_dependency", "edit_card_dependency"):
    a = args(n)
    if [x[0] for x in a] != ["board_id", "card_id", "target_card_id", "type", "color", "icon"]:
        print(f"t1: {n} args {[x[0] for x in a]}, want (board_id, card_id, target_card_id, type, color, icon) with the last three Optional defaults — C01 T1 pinned signature"); sys.exit(1)
    defaults = [ast.unparse(d) for d in funcs[n].args.defaults]
    if defaults[-3:] != ["None", "None", "None"]:
        print(f"t1: {n} must default type/color/icon to None (server defaults own the values), got {defaults}"); sys.exit(1)
a = args("remove_card_dependency")
if [x[0] for x in a] != ["board_id", "card_id", "target_card_id"]:
    print(f"t1: remove_card_dependency args {[x[0] for x in a]}, want (board_id, card_id, target_card_id)"); sys.exit(1)

# routes 1:1 to RESEARCH 1.3 (the pinned REST surface — nothing invented)
b = seg("list_board_dependencies")
if "/api/boards/{board_id}/dependencies" not in b or ".get(" not in b:
    print("t1: list_board_dependencies must GET /api/boards/{board_id}/dependencies (RESEARCH 1.3 board-wide route)"); sys.exit(1)
b = seg("list_card_dependencies")
if "/api/boards/{board_id}/cards/{card_id}/dependencies" not in b or ".get(" not in b:
    print("t1: list_card_dependencies must GET the one-card route (RESEARCH 1.3)"); sys.exit(1)
b = seg("add_card_dependency")
if "/api/boards/{board_id}/cards/{card_id}/dependencies" not in b or ".post(" not in b:
    print("t1: add_card_dependency must POST the card dependencies route"); sys.exit(1)
if '"cardId"' not in b:
    print("t1: add_card_dependency body must carry the pinned key \"cardId\""); sys.exit(1)
if "dependsOn" not in b:
    print("t1: add_card_dependency must document/accept the dependsOn body alias (RESEARCH 1.3)"); sys.exit(1)
# client-side 7-type validation BEFORE the request (create_label color-gate posture)
TYPES = ["related-to", "blocks", "is-blocked-by", "fixes", "is-fixed-by", "duplicates", "is-duplicated-by"]
missing = [t for t in TYPES if t not in src]
if missing:
    print(f"t1: the 7-type dependency list is incomplete in server.py — missing {missing} (C01 T1 client-side validation mirrors models/metadata/dependencies.js)"); sys.exit(1)
post_at = b.find(".post(")
rejected_before = (0 <= b.find("WekanError") < post_at) or re.search(r"_validate_[a-z_]*\(.*\)[^\n]*\n.*\.post\(", b)
if post_at == -1 or not rejected_before:
    print("t1: add_card_dependency must reject an unknown type (WekanError or a _validate_* helper) BEFORE the POST — the create_label color-gate posture (AC2)"); sys.exit(1)
d = ast.get_docstring(funcs["add_card_dependency"]) or ""
if "upsert" not in d.lower() or "duplicat" not in d.lower():
    print("t1: add_card_dependency docstring must document the UPSERT semantics (repeat-add UPDATES, never duplicates) — C01 T1"); sys.exit(1)
b = seg("edit_card_dependency")
if "/dependencies/{target_card_id}" not in b or ".put(" not in b:
    print("t1: edit_card_dependency must PUT /api/boards/{board_id}/cards/{card_id}/dependencies/{target_card_id}"); sys.exit(1)
b = seg("remove_card_dependency")
if "/dependencies/{target_card_id}" not in b or ".delete(" not in b:
    print("t1: remove_card_dependency must DELETE the target-scoped route"); sys.exit(1)
d = ast.get_docstring(funcs["remove_card_dependency"]) or ""
if "DESTRUCTIVE" not in d:
    print("t1: remove_card_dependency docstring must carry the DESTRUCTIVE marking (third destructive op — docstring-marked like remove_rule/delete_checklist_item)"); sys.exit(1)
print("ok: t1 — five dependency tools, pinned signatures, pinned routes, 7-type gate before POST, upsert doc, DESTRUCTIVE mark, writes only via _write_tool")
PY
  then fail "t1[C01 AC2]: the dependency-tools contract is not satisfied (reason above)"; fi
  ok "t1[C01 AC2]: five dependency tools registered per the RESEARCH 1.3 route map with client-side 7-type validation"
fi

# --- t2: preload_board — the one-call export reshape (C01 T2) --------------------
if want t2; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "preload_board" not in funcs:
    print("t2: preload_board is not defined in server.py yet — the cf-96 C01 T2 preload tool has not landed (designed red before C01 dev, not a harness fault)")
    sys.exit(1)
fn = funcs["preload_board"]
for d in fn.decorator_list:
    if isinstance(d, ast.Name) and d.id == "_write_tool":
        print("t2: preload_board is a READ (bare @mcp.tool) — registered via _write_tool it would vanish from the readonly tier"); sys.exit(1)
argn = [a.arg for a in fn.args.args]
if argn != ["board_id", "swimlane_titles"]:
    print(f"t2: preload_board args {argn}, want (board_id, swimlane_titles) - cf-106 C06 adds the optional swimlane filter (red before C06 dev)"); sys.exit(1)
b = ast.get_source_segment(src, fn)

if "/api/boards/{board_id}/export" not in b:
    print("t2: preload_board must GET /api/boards/{board_id}/export — ONE call (RESEARCH 2.2); no per-card fan-out"); sys.exit(1)
if "attachments" not in b or "false" not in b:
    print("t2: the export call must pass attachments=false — base64 payloads are a MUST-skip for preload (RESEARCH S11)"); sys.exit(1)
if "fields" not in b:
    print("t2: the export call must trim sections via ?fields= (unselected sections arrive as empty arrays — S11-exportFields)"); sys.exit(1)
for sec in ("board-header", "labels", "custom-fields", "dependencies", "sort", "checklists"):
    if sec not in b:
        print(f"t2: the fields= vocabulary must include '{sec}' (C01 T2 trimmed section list)"); sys.exit(1)

# Per-card key set EXACTLY the eight pinned fields: find every card-map dict
# literal by anchor keys and assert each one's full key set — an extra "title" or
# a dropped "sort" fails here (the AC2 "EXACTLY" wording is the contract). The
# quantifier is `all`, not `any`: with `any`, one compliant map masks a decoy map
# carrying `title` (cf-106 C06 review N2).
KEYS = {"id", "card_number", "label_ids", "slug", "archived", "sort", "parent_id", "checklists"}
card_dicts = []
for n in ast.walk(fn):
    if isinstance(n, ast.Dict):
        ks = {k.value for k in n.keys if isinstance(k, ast.Constant) and isinstance(k.value, str)}
        if {"card_number", "parent_id"} <= ks:
            card_dicts.append(ks)
if not card_dicts:
    print("t2: no card-map dict literal carrying card_number + parent_id inside preload_board — the pinned per-card reshape (id/card_number/label_ids/slug/archived/sort/parent_id/checklists) has not landed"); sys.exit(1)
if not all(ks == KEYS for ks in card_dicts):
    off = sorted({tuple(sorted(ks)) for ks in card_dicts if ks != KEYS})
    print(f"t2: card map(s) {[' '.join(k) for k in off]}, want EVERY card map EXACTLY {sorted(KEYS)} (C01 T2 field set — titles/descriptions are NOT carried, per-card field set is pinned exactly)"); sys.exit(1)
if '"description"' in b:
    print("t2: preload_board must not carry descriptions — the payload drops them (C01 T2)"); sys.exit(1)

# archived: FLAGGED, never silently dropped — no conditional filtering on
# archived inside the tool (the flag is c.get(...); an If/comp-if on archived
# would drop cards in the tool instead of at the consumer).
def refs_archived(node):
    return "archived" in ast.unparse(node)
for n in ast.walk(fn):
    if isinstance(n, ast.If) and refs_archived(n.test):
        print("t2: preload_board filters on archived in an if — archived cards must be FLAGGED and stay in the payload; pickup-side filtering belongs to the consumer (C05)"); sys.exit(1)
    if isinstance(n, (ast.ListComp, ast.DictComp, ast.GeneratorExp)):
        for g in ast.walk(n):
            if isinstance(g, ast.comprehension) and any(refs_archived(iff) for iff in g.ifs):
                print("t2: preload_board drops archived cards in a comprehension filter — flag-not-drop contract violated (C01 AC2)"); sys.exit(1)

# the grouped map + the board's edge lines + name maps (pinned response keys)
for key in ("\"swimlanes\"", "\"lists\"", "\"cards\"", "\"dependencies\"", "\"label_names\"", "\"field_names\""):
    if key not in b:
        print(f"t2: the preload response must carry the pinned key {key} (swimlane→list→cards grouping + dependency lines + label/field name maps — C01 T2 contract)"); sys.exit(1)

d = ast.get_docstring(fn) or ""
if "customFields" not in b and "custom_fields" not in b:
    print("t2: slug must be extracted from the card's customFields entries (C01 T2 — the board's slug field id selects the value)"); sys.exit(1)
if "slug" not in d or ("[" not in d and "link" not in d.lower()):
    print("t2: preload_board docstring must document the combined [<slug>](<link>) value parsing (bracketed text; bare value passes through)"); sys.exit(1)
if "linked" not in d.lower():
    print("t2: preload_board docstring must state that linked cards are excluded by the exporter itself (S11 — documented, not filtered here)"); sys.exit(1)
print("ok: t2 — preload_board: one export call, attachments=false + fields trim, every card map the exact 8-key set, no title/description, flag-not-drop archived, grouped map + dependencies + name maps")
PY
  then fail "t2[C01 AC2]: the preload_board reshape contract is not satisfied (reason above)"; fi
  ok "t2[C01 AC2 + cf-106 C06]: preload_board one-call export reshape contract satisfied (the trim carries checklists, the card map is the 8-key set, the signature carries the swimlane filter)"
fi

# --- t3: set_card_labels — the bulk route wrapper (C01 T3, AD-74) -----------------
if want t3; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "set_card_labels" not in funcs:
    print("t3: set_card_labels is not defined in server.py yet — the cf-96 C01 T3 label tool (AD-74) has not landed (designed red before C01 dev)")
    sys.exit(1)
fn = funcs["set_card_labels"]
kind = None
for d in fn.decorator_list:
    if isinstance(d, ast.Name) and d.id == "_write_tool":
        kind = "write"
if kind != "write":
    print("t3: set_card_labels is a WRITE and must register through _write_tool (readonly tier hides it by construction)"); sys.exit(1)
argn = [a.arg for a in fn.args.args]
if argn[:2] != ["board_id", "card_ids"]:
    print(f"t3: set_card_labels must start (board_id, card_ids, ...) — board_id required per house style, got {argn}"); sys.exit(1)
if argn != ["board_id", "card_ids", "add_label_ids", "remove_label_ids"]:
    print(f"t3: set_card_labels args {argn}, want (board_id, card_ids, add_label_ids=None, remove_label_ids=None)"); sys.exit(1)
b = ast.get_source_segment(src, fn)
if "/api/boards/{board_id}/cards/labels" not in b or ".post(" not in b:
    print("t3: set_card_labels must POST the upstream bulk route /api/boards/{board_id}/cards/labels (RESEARCH 2.1/S9)"); sys.exit(1)
for key in ('"cardIds"', '"addLabelIds"', '"removeLabelIds"'):
    if key not in b:
        print(f"t3: the bulk body must carry the pinned key {key}"); sys.exit(1)
if "500" not in src or b.find(".post(") == -1:
    print("t3: set_card_labels must enforce the ≤500 card cap client-side (the route's own bound — document AND gate it) — the '500' constant is not reachable in server.py or the bulk POST is missing"); sys.exit(1)
post_at = b.find(".post(")
cap_before_send = (0 <= b.find("WekanError") < post_at) or "_validate_" in b[:post_at] or "500" in b[:post_at]
if not cap_before_send:
    print("t3: the >500 rejection must happen BEFORE the bulk POST (validate-before-send posture, C01 T3)"); sys.exit(1)
if "labels" not in b or ".get(" not in b:
    print("t3: set_card_labels must validate the label ids against the board before the bulk POST (read the board's labels — the route's own board-membership gate stays the authority)"); sys.exit(1)
d = ast.get_docstring(fn) or ""
if "no-op" not in d.lower() and "no op" not in d.lower():
    print("t3: set_card_labels docstring must state that an absent list is a no-op (add-only / remove-only calls are legal — C01 T3)"); sys.exit(1)
print("ok: t3 — set_card_labels: bulk route + pinned body keys, board_id-led args, ≤500 gate before POST, board-label validation, no-op docstring")
PY
  then fail "t3[C01 AC2]: the set_card_labels contract is not satisfied (reason above)"; fi
  ok "t3[C01 AC2]: set_card_labels bulk-shape contract satisfied"
fi

# --- t4: _slim_card passthroughs + by-list strip-accuracy (C01 T4) ----------------
if want t4; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def seg(name):
    return ast.get_source_segment(src, funcs[name])
if "_slim_card" not in funcs:
    print("t4: _slim_card disappeared from server.py"); sys.exit(1)
s = seg("_slim_card")
if '"card_dependencies"' not in s or "cardDependencies" not in s:
    print("t4: _slim_card must pass card_dependencies through from the wire key cardDependencies — today silently dropped (RESEARCH 2.1, C01 T4 — not landed yet if this is red)")
    sys.exit(1)
if '"parent_id"' not in s or "parentId" not in s:
    print("t4: _slim_card must pass parent_id through from the wire key parentId (C01 T4)"); sys.exit(1)
lic = seg("list_cards_in_list")
if "/api/cards/" in lic:
    print("t4: list_cards_in_list must NOT gain per-card /api/cards/ fetches to compensate — it stays the strip-accurate by-list read (C01 T4)"); sys.exit(1)
d = ast.get_docstring(funcs["list_cards_in_list"]) or ""
if "projection" not in d.lower():
    print("t4: list_cards_in_list docstring must keep documenting the by-list projection strip"); sys.exit(1)
print("ok: t4 — _slim_card carries card_dependencies + parent_id; list_cards_in_list stays strip-accurate (no N+1 fetch)")
PY
  then fail "t4[C01 AC2]: the passthrough contract is not satisfied (reason above)"; fi
  ok "t4[C01 AC2]: _slim_card passthroughs + by-list strip-accuracy hold"
fi

# --- t5: create_card parent_id — two-step, OQ1 parentId-only (C01 T5) -------------
if want t5; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "create_card" not in funcs:
    print("t5: create_card disappeared"); sys.exit(1)
cc = funcs["create_card"]
argn = [a.arg for a in cc.args.args]
if argn[-1] != "parent_id":
    print(f"t5: create_card must end with the optional trailing parent_id parameter (after default_checked), got {argn} — the C01 T5 two-step has not landed"); sys.exit(1)
ann = ast.unparse(cc.args.args[-1].annotation) if cc.args.args[-1].annotation else None
if ann != "Optional[str]":
    print(f"t5: parent_id must be Optional[str], got {ann}"); sys.exit(1)
if ast.unparse(cc.args.defaults[-1]) != "None":
    print("t5: parent_id must default to None (absent = the create behaves exactly as today)"); sys.exit(1)
b = ast.get_source_segment(src, cc)
if '_validate_default_checked(' not in b:
    print("t5: the existing default_checked validation leg must survive the parent_id extension (regression)"); sys.exit(1)
if '"parentId"' not in b or '.put(' not in b:
    print("t5: parent_id must ride the two-step create→PUT /api/boards/{board_id}/cards/{card_id} body parentId (RESEARCH S9 — the single-card POST does not honor a body parentId)"); sys.exit(1)
if "/api/boards/{board_id}/cards/{card_id}" not in b:
    print("t5: the PUT target must be the single-card route /api/boards/{board_id}/cards/{card_id} (S9)"); sys.exit(1)
if "parent_id_set" not in b:
    print("t5: a failed PUT must surface parent_id_set: false + reason in the response (the default_checked outcome-surfacing posture)"); sys.exit(1)
if ".delete(" in b:
    print("t5: create_card must never roll the card back on a parent_id failure — a delete call inside it breaks the non-rollback contract (C01 T5)"); sys.exit(1)
# OQ1 negative pin: parentId-only — no Red Strings edge drawn automatically
if "/api/boards/{board_id}/dependencies" in b or "card_dependency(" in b or "_wekan.post(f\"/api/boards/{board_id}/cards/{card_id}/dependencies" in b:
    print("t5: create_card REFERENCES the dependency routes — the OQ1 ruling makes parent_id the ONLY follow-up representation (no automatic edge creation; the AC2 negative pin)"); sys.exit(1)
d = ast.get_docstring(cc) or ""
if "parentId" not in b and "parent" not in d.lower():
    print("t5: create_card docstring must document the parent_id lineage semantics (two-step rationale + failure surfacing)"); sys.exit(1)
print("ok: t5 — create_card parent_id: trailing Optional[str], create→PUT parentId, parent_id_set surfaced, no rollback, no auto dependency edge (OQ1)")
PY
  then fail "t5[C01 AC2]: the create_card parent_id contract is not satisfied (reason above)"; fi
  ok "t5[C01 AC2]: create_card parent_id two-step + OQ1 negative pin hold"
fi

# --- t6: doc re-stamp parity (C01 T6 + AC4) ----------------------------------------
if want t6; then
  python3 "$PARITY" claims "$SERVER" "$README" "$SKILL_MCP" "$SHAPES" "$SKILL_API" \
    || fail "t6[C01 AC4]: a tool-count claim in README/SKILL/call-shapes/wekan-api no longer matches the live registry — the cf-96-era 38/31 literals here reddened on cf-106 C07's sanctioned +1 while asserting nothing the sibling suites' parity gate does not (reason above)"
  if ! python3 - "$README" "$SKILL_MCP" "$SHAPES" "$SKILL_API" "$REG_TOTAL" <<'PY'
import re, sys

readme, skill, shapes, api = (open(p).read() for p in sys.argv[1:5])
REG_TOTAL = int(sys.argv[5])
def bad(m):
    print(f"t6: {m} — the C01 docs re-stamp (README/skill/call-shapes) must land in the SAME commit as the tools (DECISIONS doc-parity convention)")
    sys.exit(1)

NEW = ["list_board_dependencies", "list_card_dependencies", "add_card_dependency",
       "edit_card_dependency", "remove_card_dependency", "preload_board", "set_card_labels"]

for n in NEW:
    if n not in readme:
        bad(f"README tool section is missing {n}")

# tier table counts (both full tiers) + the write-surface list + the
# intentionally-omitted note staying true with dependencies NOT omitted
if skill.count(f"full, {REG_TOTAL} tools") < 2:
    bad(f"the wekan-mcp SKILL tier table must state 'full, {REG_TOTAL} tools' on both full tiers (dev-boards + gpu admin)")
for n in NEW:
    if n not in skill:
        bad(f"SKILL surface list is missing {n}")
i = skill.lower().find("intentionally omitted")
if i < 0:
    bad("SKILL lost its intentionally-omitted note (C01 T6: the note must STAY — dependencies are NOT among the omissions)")
window = skill[i:i + 500].lower()
if "dependen" in window:
    bad("the intentionally-omitted window now names dependencies — wrong direction: the dependency tools SHIP, the omission list must stay dependency-free")

if f"all {REG_TOTAL} tools" not in shapes:
    bad(f"call-shapes.md header does not state the live registry count ({REG_TOTAL} tools)")
for n in NEW:
    rows = [l for l in shapes.splitlines() if re.match(rf"^\| `{n}` \|", l)]
    if len(rows) != 1:
        bad(f"call-shapes.md needs exactly one row for {n} (8-row table extension — C01 T6)")
        continue
    if "source-only 2026-11" not in rows[0]:
        bad(f"call-shapes.md row {n} must carry the evidence stamp 'source-only 2026-11' — nothing pre-C10 may claim live (AC4)")
    if "live probe" in rows[0]:
        bad(f"call-shapes.md row {n} claims a live probe — the routes were never agent-probed (no bearer); the C10 runbook upgrades the stamp AFTER the user probe")

if f"{REG_TOTAL} typed tools" not in api:
    bad(f"wekan-api SKILL does not state the live registry count ({REG_TOTAL} typed tools)")
print(f"ok: t6 — README + names, tier table {REG_TOTAL}x2, omitted-note intact, call-shapes rows stamped source-only 2026-11, wekan-api count current ({REG_TOTAL})")
PY
  then fail "t6[C01 AC4]: the documentation-parity re-stamp is not satisfied (reason above)"; fi
  ok "t6[C01 T6/AC4]: docs re-stamped to the live registry count ($REG_TOTAL tools) with honest source-only evidence stamps"
fi

# --- t7: wekan.py byte-unchanged (C01 AC3, tools.sh t8 posture) --------------------
if want t7; then
  git rev-parse --verify "$PIN_BASE" >/dev/null 2>&1 \
    || fail "harness: base ref '$PIN_BASE' does not resolve (CF96_BASE=<ref>)"
  git diff --quiet "$PIN_BASE" -- "$WEKAN_PY" \
    || fail "t7[C01 AC3]: $WEKAN_PY changed since $PIN_BASE — C01 rides the existing _wekan helpers and must not edit the login-mint client (pass CF96_BASE=<ref> if main legitimately moved it)"
  ok "t7[C01 AC3]: $WEKAN_PY byte-identical to $PIN_BASE (tools.sh t8 companion pin)"
fi

# --- t8: _slim_rule capture projection — the schema-2 keys (C11 T1 / AC1) ----------
if want t8; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
fn = funcs.get("_slim_rule")
if fn is None:
    print("t8: _slim_rule disappeared from server.py (layout fault, not a C11 red)"); sys.exit(1)
ret = next((n for n in ast.walk(fn) if isinstance(n, ast.Return)), None)
if ret is None or not isinstance(ret.value, ast.Dict):
    print("t8: _slim_rule must return a dict literal — the projection is pinned structurally (C11 T1)"); sys.exit(1)
d = ret.value
keys = [k.value for k in d.keys if isinstance(k, ast.Constant)]
WANT = {"id", "title", "trigger", "action", "extra_actions", "extra_triggers", "enabled"}
if set(keys) != WANT:
    print(f"t8: _slim_rule projects {sorted(keys)}, want EXACTLY {sorted(WANT)} (C11 T1 — the schema-2 capture contract keys)"); sys.exit(1)
WIRE = {"id": "_id", "title": "title", "trigger": "trigger", "action": "action",
        "extra_actions": "extraActions", "extra_triggers": "extraTriggers", "enabled": "enabled"}
for k, v in zip(d.keys, d.values):
    raw = (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
           and v.func.attr == "get" and isinstance(v.func.value, ast.Name)
           and v.func.value.id == "r"
           and v.args and isinstance(v.args[0], ast.Constant)
           and v.args[0].value == WIRE[k.value])
    if not raw:
        print(f"t8: key {k.value!r} must read r.get(\"{WIRE[k.value]}\") — the route value un-reshaped (C11 T1), got {ast.unparse(v)}"); sys.exit(1)
en = d.values[keys.index("enabled")]
if not (len(en.args) == 2 and isinstance(en.args[1], ast.Constant) and en.args[1].value is True):
    print("t8: enabled must be r.get(\"enabled\", True) — True ONLY when the route omits the field; a paused rule must read enabled: false (C11 T1, RESEARCH F6c)"); sys.exit(1)
for key in ("extra_actions", "extra_triggers"):
    v = d.values[keys.index(key)]
    if len(v.args) != 1:
        print(f"t8: {key} must pass through r.get(\"{WIRE[key]}\") with NO default — an omitted field reads None, never an invented empty list (the _slim_card parent_id posture; absence stays visibly absent)"); sys.exit(1)

def plain_read(name):
    f = funcs.get(name)
    if f is None:
        return False
    has = any(isinstance(x, ast.Attribute) and x.attr == "tool"
              and isinstance(x.value, ast.Name) and x.value.id == "mcp"
              for x in f.decorator_list)
    gated = any(isinstance(x, ast.Name) and x.id == "_write_tool" for x in f.decorator_list)
    return has and not gated
for name in ("get_rule", "list_rules"):
    if not plain_read(name):
        print(f"t8: {name} must stay a plain @mcp.tool READ — the READ-ONLY tier keeps exposing the rule projection (C11 T1 registration-unchanged duty)"); sys.exit(1)

d1 = ast.get_docstring(funcs["get_rule"]) or ""
if "checklist extras" not in d1 or "enabled" not in d1:
    print("t8: get_rule docstring must re-stamp to the full embedded trigger, action, checklist extras and enabled flag (C11 T1)"); sys.exit(1)
d2 = ast.get_docstring(funcs["list_rules"]) or ""
if "extra_actions" not in d2 or "enabled" not in d2:
    print("t8: list_rules docstring must carry the 7-key shape claim (C11 T1/T2 doc parity)"); sys.exit(1)
print("ok: t8 — _slim_rule EXACTLY the 7-key capture projection, raw r.get pass-throughs (no reshaping), enabled True-only-on-omission, get_rule/list_rules plain reads, docstrings re-stamped")
PY
  then fail "t8[C11 AC1]: the _slim_rule capture-projection contract is not satisfied (reason above)"; fi
  ok "t8[C11 AC1]: _slim_rule carries extra_actions/extra_triggers/enabled un-reshaped — the schema-2 capture path is executable"
fi

# --- t9/t10/t11: cf-106 C06 — the preload payload the pickup walk reasons with --
# One shipped checker, three modes, run against the real server source AND
# against synthetic sources (a compliant one and degraded ones) so each arm is
# proven satisfiable AND responsive — the cf-52 non-vacuity rule, kept while the
# live legs stay USER-owned (C06 AC7: all proof here is offline).
TMP="${TMP:-$(mktemp -d /tmp/opencode/wekan-deps-test.XXXXXX)}"
if want t9 || want t10 || want t11; then
cat >"$TMP/preloadshape.py" <<'PYEOF'
import ast, sys

path, mode = sys.argv[1], sys.argv[2]
fname = sys.argv[3] if len(sys.argv) > 3 else "preload_board"
src = open(path).read()
tree = ast.parse(src)
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == fname), None)
if fn is None:
    print(f"{fname} is not defined in {path} (designed red before C06 dev, not a harness fault)")
    sys.exit(1)
body = ast.get_source_segment(src, fn) or ast.unparse(fn)
doc = ast.get_docstring(fn) or ""
STD = ["Services", "Type", "Model(s)", "Lifecycle", "Human in the Loop"]
LEGACY = "Research"

def dicts_with(keys):
    out = []
    for n in ast.walk(fn):
        if isinstance(n, ast.Dict):
            ks = {k.value for k in n.keys if isinstance(k, ast.Constant) and isinstance(k.value, str)}
            if keys <= ks:
                out.append(ks)
    return out

bad = []
if mode == "checklists":
    if "checklists" not in body:
        bad.append("the export call never names the `checklists` section — checklist state cannot ride the single request")
    if any("checklist" in ast.unparse(n).lower() and "get_checklist" in ast.unparse(n) for n in ast.walk(fn) if isinstance(n, ast.Call)):
        bad.append("the tool fans out to a checklist endpoint — C06 keeps this ONE request (the OQ3 budget ruling)")
    vocabs = []
    # The vocabulary may live at module level (a named constant is the cleaner
    # shape) — what the contract requires is that the set is spelled out and
    # that the TOOL filters by it.
    for n in list(ast.walk(tree)) + list(ast.walk(fn)):
        if isinstance(n, (ast.Set, ast.List, ast.Tuple)):
            consts = {e.value for e in n.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)}
            if all(s in consts for s in STD) and LEGACY in consts:
                vocabs.append(consts)
    if not vocabs:
        bad.append("no literal checklist vocabulary naming the five standard checklists + 'Research' — the filter set is a documented contract, not an implicit one")
    filtered = False
    for n in ast.walk(fn):
        if isinstance(n, ast.Compare) and any(isinstance(op, ast.In) for op in n.ops):
            left, right = ast.unparse(n.left).lower(), ast.unparse(n.comparators[0])
            if ("title" in left or "name" in left) and ("std" in right.upper() or "checklist" in right.upper() or "keep" in right.upper()):
                filtered = True
        if isinstance(n, ast.comprehension) and "title" in ast.unparse(n).lower() and "checklist" in ast.unparse(n).lower():
            filtered = True
    if not filtered:
        bad.append("the vocabulary is never used in a membership test — every checklist on the board would ride the payload (C06's 'improve / filter' half)")
    item_dicts = dicts_with({"title", "finished"})
    if not item_dicts:
        bad.append("no checklist-item projection carrying {title, finished} — item state is what the kickoff consumption reads")
    for ks in item_dicts:
        if ks - {"title", "finished"}:
            bad.append(f"checklist-item projection carries extra keys {sorted(ks)} — want EXACTLY title + finished")
    if "legacy" not in (body + doc).lower():
        bad.append("neither the code nor the docstring mentions the legacy checklist spelling (the 8-item Lifecycle variant must be recognised, not guessed)")
    for tok in ("checklists",) + tuple(STD):
        if tok not in doc:
            bad.append(f"the docstring never names '{tok}' — AC1 wants the docstring to enumerate the field set and the checklist filter set")
elif mode == "titles":
    lanes = dicts_with({"id", "lists"})
    if not lanes:
        bad.append("no swimlane entry literal carrying {id, lists} — titles must sit next to the ids (C06 AC2)")
    if not any("title" in ks for ks in lanes):
        bad.append("swimlane entries carry id but no title — the consumer's membership tests would still need a list_lists round-trip")
    lists = dicts_with({"id", "cards"})
    if not lists:
        bad.append("no list entry literal carrying {id, cards}")
    if not any("title" in ks for ks in lists):
        bad.append("list entries carry id but no title")
    comp_ifs = [g for n in ast.walk(fn) if isinstance(n, (ast.ListComp, ast.DictComp, ast.GeneratorExp))
                for g in ast.walk(n) if isinstance(g, ast.comprehension) and g.ifs]
    if_statements = [n for n in ast.walk(fn) if isinstance(n, ast.If)]
    empty_guard = any("lists" in ast.unparse(n.test) or "cards" in ast.unparse(n.test) for n in if_statements) \
        or any(("lists" in ast.unparse(g.ifs[0]) or "cards" in ast.unparse(g.ifs[0])) for g in comp_ifs)
    if not empty_guard:
        bad.append("no emptiness guard on the grouped entries — empty lists/swimlanes must not be emitted (the cf-96 posture C06 keeps)")
    for n in ast.walk(fn):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "sorted":
            key_txt = " ".join(ast.unparse(kw.value) for kw in n.keywords)
            if "sort" not in key_txt:
                bad.append(f"sorted(...) without the board's sort field as the key ({key_txt or 'no key'}) — the payload keeps the board's own order")
    if '"description"' in body or "'description'" in body:
        bad.append("a description key appears in the preload body — the payload stays description-free (AC4)")
elif mode == "filter":
    argn = [a.arg for a in fn.args.args]
    if argn[:2] != ["board_id", "swimlane_titles"]:
        bad.append(f"signature is {argn}, want (board_id, swimlane_titles) — C06's payload-bound filter")
    defaults = fn.args.defaults
    if not defaults:
        bad.append("swimlane_titles has no default — the documented default is every swimlane")
    elif ast.unparse(defaults[-1]) not in ("None", "[]", "list()", "tuple()"):
        bad.append(f"swimlane_titles defaults to {ast.unparse(defaults[-1])}, want None (all swimlanes)")
    if len([n for n in ast.walk(fn) if isinstance(n, ast.Name) and n.id == "swimlane_titles"]) < 2:
        bad.append("swimlane_titles is never used in the body — the filter argument is decorative")
    if_statements = [n for n in ast.walk(fn) if isinstance(n, ast.If)]
    comp_ifs = [g for n in ast.walk(fn) if isinstance(n, (ast.ListComp, ast.DictComp, ast.GeneratorExp))
                for g in ast.walk(n) if isinstance(g, ast.comprehension) and g.ifs]
    filter_site = any("swimlane_titles" in ast.unparse(n.test) for n in if_statements) \
        or any("swimlane_titles" in ast.unparse(g.ifs[0]) for g in comp_ifs) \
        or any("swimlane_titles" in ast.unparse(kw.value) for n in ast.walk(fn) if isinstance(n, ast.Call) for kw in n.keywords)
    if not filter_site:
        bad.append("no filter branch keyed on swimlane_titles — the argument cannot bound the payload")
    # AC3's "no error" rule belongs to the FILTER arm only: an unknown/empty/None
    # swimlane title must yield the documented empty grouping. A malformed
    # transport answer is a different arm — and there failing the call is
    # REQUIRED below (cf-106 C06 review N1: the swallow-into-empty-grouping shape
    # is the hazard). So the ban is scoped to raises reachable from the
    # swimlane_titles path: unconditional in the body, under a title-keyed guard,
    # or about titles.
    parents = {}
    for n in ast.walk(fn):
        for c in ast.iter_child_nodes(n):
            parents[c] = n

    def filter_path(r):
        if parents.get(r) is fn:
            return True  # unconditional in the body: fires on the unknown-title call too
        node = parents.get(r)
        while node is not None and node is not fn:
            if isinstance(node, ast.If) and "swimlane_titles" in ast.unparse(node.test):
                return True
            if isinstance(node, (ast.ListComp, ast.DictComp, ast.GeneratorExp, ast.SetComp)) and any(
                    "swimlane_titles" in ast.unparse(i) for i in node.ifs):
                return True
            node = parents.get(node)
        return False

    raises = [n for n in ast.walk(fn) if isinstance(n, ast.Raise)]
    banned_nodes = [r for r in raises if filter_path(r) or "swimlane" in ast.unparse(r).lower()]
    banned = [ast.unparse(r).replace("\n", " ") for r in banned_nodes]
    if banned:
        bad.append(f"the swimlane_titles filter arm raises ({banned}) — an unknown swimlane title must yield the documented empty grouping, not an error (AC3)")
    # N1 mechanism pin (C06 round 2), two halves. A malformed / bodyless export
    # answer must never be folded into the empty grouping: an empty grouping is
    # contractually identical to an empty board, so a pickup walk would conclude
    # "no claimable cards", write the no-op marker and archive the session
    # silently. The boards degrade law (present-but-failed: one retry, then the
    # per-list fallbacks) can only fire on a call that ACTUALLY fails.
    def emptyish(e):
        if isinstance(e, ast.Dict):
            return not e.keys
        if isinstance(e, (ast.List, ast.Tuple, ast.Set)):
            return not e.elts
        return isinstance(e, ast.Constant) and e.value in (None, "")

    def transport_call(v):
        if isinstance(v, ast.Call):
            return True
        if isinstance(v, ast.BoolOp):
            return any(transport_call(x) for x in v.values)
        return False

    ans_assigns = [n for n in ast.walk(fn) if isinstance(n, (ast.Assign, ast.AnnAssign))
                   and n.value is not None and transport_call(n.value)
                   and "/export" in ast.unparse(n.value)]
    if not ans_assigns:
        bad.append("no export-route call assignment in preload_board — the answer the N1 pin guards cannot be identified")
    answer = next((n.targets[0].id for n in ans_assigns
                   if n.targets and isinstance(n.targets[0], ast.Name)), None)
    if answer:
        for n in ans_assigns:
            if isinstance(n.value, ast.BoolOp) and isinstance(n.value.op, ast.Or) \
                    and any(emptyish(v) for v in n.value.values[1:]):
                bad.append(f"the export answer falls back to an empty container (`{answer} = … or {{}}`) — a bodyless or malformed export body becomes the empty grouping, which is indistinguishable from an empty board; the call must fail so the degrade law's present-but-failed branch runs (cf-106 C06 N1)")
        for n in if_statements:
            test = ast.unparse(n.test)
            if "isinstance" not in test or "dict" not in test:
                continue
            for st in n.body:
                if isinstance(st, ast.Assign):
                    tgt, val = st.targets, st.value
                elif isinstance(st, ast.AnnAssign):
                    tgt, val = [st.target], st.value
                else:
                    continue
                if val is None:
                    continue
                if any(isinstance(t, ast.Name) and t.id == answer for t in tgt) and emptyish(val):
                    bad.append(f"the malformed-answer guard reassigns `{answer}` to an empty container — silent-empty ≡ empty-board: a pickup walk would mark no-cards, write the no-op marker and archive; a non-dict export answer must fail the call (cf-106 C06 N1)")
    failure_signal = any(r not in banned_nodes for r in raises) or any(
        isinstance(n.func, ast.Name)
        and any(tok in n.func.id.lower() for tok in ("error", "raise", "fail", "abort", "invalid", "malformed"))
        and answer is not None and any(answer in ast.unparse(a) for a in n.args)
        for n in ast.walk(fn) if isinstance(n, ast.Call))
    if not failure_signal:
        bad.append("no failure signal for a malformed export answer (a guarded raise, or a failure-signalling call over the answer such as _embedded_error) — the boards degrade law cannot see a call that answers with the empty grouping (cf-106 C06 N1)")
    if "swimlane" not in doc.lower() or not any(w in doc.lower() for w in ("all", "every", "default")):
        bad.append("the docstring does not state the default (every swimlane) — AC3's documented default is part of the contract")
else:
    print(f"unknown mode {mode}"); sys.exit(2)

if bad:
    print("; ".join(bad))
    sys.exit(1)
PYEOF

cat >"$TMP/preload-compliant.py" <<'PYEOF'
from typing import Optional

STD = {"Services", "Type", "Model(s)", "Lifecycle", "Human in the Loop", "Research"}


def preload_board(board_id: str, swimlane_titles: Optional[list[str]] = None) -> dict:
    """One export request. Each card carries id, card_number, label_ids, slug,
    archived, sort, parent_id and checklists. Checklists are filtered to the
    standard checklists (Services, Type, Model(s), Lifecycle, Human in the Loop)
    plus the legacy Research spelling; every swimlane by default, and an
    unknown swimlane title yields an empty grouping. A malformed (non-dict)
    export answer fails the call — an empty grouping must stay distinguishable
    from an empty board."""
    doc = client.get("/api/boards/{board_id}/export",
                     params={"attachments": "false",
                             "fields": "board-header,labels,custom-fields,dependencies,sort,checklists"})
    if not isinstance(doc, dict):
        raise ValueError("wekan export answer is not a dict")
    keep = [c for c in doc.get("checklists", [])
            if c.get("title") in STD or len(c.get("tasks", [])) == 8]
    items = {c.get("_id"): [{"title": t.get("title"), "finished": bool(t.get("done"))}
                            for t in c.get("tasks", [])] for c in keep}
    cards = [{ "id": c.get("_id"), "card_number": c.get("cardNumber"),
               "label_ids": c.get("labelIds", []), "slug": slug_of(c),
               "archived": c.get("archived", False), "sort": c.get("sort"),
               "parent_id": c.get("parentId"),
               "checklists": [{"id": x.get("_id"), "title": x.get("title"),
                               "items": items.get(x.get("_id"), [])} for x in keep] }
              for c in sorted(doc["cards"], key=lambda c: (c.get("sort") or 0))]
    lists = [{"id": l.get("_id"), "title": l.get("title"),
              "cards": [c for c in cards if c["id"] in {x for x in ids_of(l)}]} for l in doc.get("lists", [])]
    swimlanes = [{"id": s.get("_id"), "title": s.get("title"),
                  "lists": [l for l in lists if l["id"] in {x.get("_id") for x in s.get("lists", [])}]}
                 for s in doc.get("swimlanes", [])]
    if swimlane_titles is not None:
        swimlanes = [s for s in swimlanes if s["title"] in swimlane_titles]
    return {"board_id": board_id, "swimlanes": [s for s in swimlanes if s["lists"]],
            "lists": [l for l in lists if l["cards"]],
            "dependencies": [], "label_names": {}, "field_names": {}}
PYEOF

python3 - "$TMP/preload-compliant.py" "$TMP" <<'PY' || { echo "t9/t10/t11: the fixture fabricator itself failed (fixture fault — a broken fixture edit reads as a contract red)" >&2; exit 1; }
import sys
# Degraded copies: one degradation per copy, so each control reddens exactly one
# arm (and proves that arm is responsive, not decoration). Every edit is asserted
# to have applied — a silently non-matching replace would build a copy identical to
# the compliant source and the control would pass for the wrong reason.
text = open(sys.argv[1]).read()
tmp = sys.argv[2]

def sub(name, old, new):
    if text.count(old) != 1:
        sys.exit(f"fixture fault: {name} anchor found {text.count(old)} times (want 1)")
    out = text.replace(old, new)
    open(f"{tmp}/preload-{name}.py", "w").write(out)
    return out

FILTER_ARM = ('    if swimlane_titles is not None:\n'
              '        swimlanes = [s for s in swimlanes if s["title"] in swimlane_titles]')
TRANSPORT_GUARD = ('    if not isinstance(doc, dict):\n'
                   '        raise ValueError("wekan export answer is not a dict")')

sub("degraded-1", 'if c.get("title") in STD or len(c.get("tasks", [])) == 8', "if True")
sub("degraded-2", '"id": l.get("_id"), "title": l.get("title"),', '"id": l.get("_id"),')
# filter arm, raised unconditionally in the body (the filter branch is gone)
sub("degraded-3", FILTER_ARM, '    raise ValueError("unsupported filter")')
# filter arm, raise nested inside the title-keyed guard — the scoped ban must catch
# this shape too, so the ban is not just a "no raise at body level" rule
sub("filter-raise", FILTER_ARM,
    '    if swimlane_titles is not None:\n'
    '        raise ValueError(f"unsupported swimlane titles: {sorted(swimlane_titles)}")')
# the cf-106 C06 round-1 defect: a malformed export answer swallowed into the
# empty grouping — the positive leg must redden this, not the ban leg
sub("swallow", TRANSPORT_GUARD, '    if not isinstance(doc, dict):\n        doc = {}')
# the other swallow shape: a bodyless answer folded in at the call site
sub("orfallback", '"fields": "board-header,labels,custom-fields,dependencies,sort,checklists"})',
    '"fields": "board-header,labels,custom-fields,dependencies,sort,checklists"}) or {}')
PY

fi

if want t9; then
  python3 "$TMP/preloadshape.py" "$SERVER" checklists \
    || fail "t9[C06 AC1/AC4]: the preload checklist contract is not satisfied (reason above; designed red until C06 lands the checklists section in the one-request trim, the filter vocabulary and the {title, finished} item shape)"
  python3 "$TMP/preloadshape.py" "$TMP/preload-compliant.py" checklists \
    || fail "t9[C06]: NEGATIVE CONTROL FAILED — the shipped checker rejects a compliant preload (the arm above is unsatisfiable)"
  python3 "$TMP/preloadshape.py" "$TMP/preload-degraded-1.py" checklists >/dev/null 2>&1 \
    && fail "t9[C06]: NEGATIVE CONTROL FAILED — an unfiltered preload (every checklist rides the payload) still passes the checklist arms"
  ok "t9[C06 AC1]: the export trim carries \`checklists\` in the same single request, the standard five + legacy Research filter set is a named vocabulary wired through a membership test, items project to exactly {title, finished}, and the docstring enumerates the field set (compliant and degraded fixtures both behave)"
fi

if want t10; then
  python3 "$TMP/preloadshape.py" "$SERVER" titles \
    || fail "t10[C06 AC2/AC4]: the grouped-shape contract is not satisfied (reason above; designed red until swimlane/list entries carry titles with the empty-group posture kept)"
  python3 "$TMP/preloadshape.py" "$TMP/preload-compliant.py" titles \
    || fail "t10[C06]: NEGATIVE CONTROL FAILED — the checker rejects a compliant grouped payload"
  python3 "$TMP/preloadshape.py" "$TMP/preload-degraded-2.py" titles >/dev/null 2>&1 \
    && fail "t10[C06]: NEGATIVE CONTROL FAILED — a payload whose list entries carry no title still passes (the title pin is decoration)"
  ok "t10[C06 AC2/AC4]: swimlane and list entries carry title next to id, empty groups stay unemitted, any re-ordering goes through the board's sort field, and no description key appears"
fi

if want t11; then
  python3 "$TMP/preloadshape.py" "$SERVER" filter \
    || fail "t11[C06 AC3 + N1]: the swimlane_titles contract is not satisfied (reason above; the filter argument must be optional with every-swimlane as the documented default and must not raise for an unknown title, AND a malformed/non-dict export answer must fail the call — designed red until C06 round 2 replaces the empty-grouping swallow)"
  python3 "$TMP/preloadshape.py" "$TMP/preload-compliant.py" filter \
    || fail "t11[C06]: NEGATIVE CONTROL FAILED — the checker rejects a compliant swimlane_titles implementation (filter kept, transport guard raise kept): the N1 arm is unsatisfiable as written"
  python3 "$TMP/preloadshape.py" "$TMP/preload-degraded-3.py" filter >/dev/null 2>&1 \
    && fail "t11[C06]: NEGATIVE CONTROL FAILED — a tool that raises instead of filtering still passes the AC3 arms"
  python3 "$TMP/preloadshape.py" "$TMP/preload-filter-raise.py" filter >/dev/null 2>&1 \
    && fail "t11[C06]: NEGATIVE CONTROL FAILED — a raise nested inside the swimlane_titles guard passes the AC3 arms (the raise ban is not scoped to the filter path, or the scope test is broken)"
  python3 "$TMP/preloadshape.py" "$TMP/preload-swallow.py" filter >/dev/null 2>&1 \
    && fail "t11[C06 N1]: NEGATIVE CONTROL FAILED — a malformed export answer swallowed into the empty grouping still passes: the fail-the-call arm is decoration, and silent-empty ≡ empty-board (a pickup walk would mark no-cards, write the no-op marker and archive silently)"
  python3 "$TMP/preloadshape.py" "$TMP/preload-orfallback.py" filter >/dev/null 2>&1 \
    && fail "t11[C06 N1]: NEGATIVE CONTROL FAILED — an export answer with an \`or {}\` fallback still passes: the no-swallow half of the pin is decoration (a bodyless answer becomes the empty grouping)"
  ok "t11[C06 AC3 + N1]: swimlane_titles is optional, defaults to every swimlane, actually filters the grouping, yields the documented empty answer for an unknown title (no raise on the filter path), the docstring states the default, and a malformed non-dict export answer fails the call instead of returning the empty grouping (silent-empty ≡ empty-board is the hazard the degrade law must see)"
fi

printf 'PASS: wekan-mcp cf-96 dependency/preload/label-surface checks (%d ok)\n' "$checks"
