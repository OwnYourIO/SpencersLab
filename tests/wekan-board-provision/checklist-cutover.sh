#!/usr/bin/env bash
# cutover process artifacts — provision engine schema-2, provision skill,
# board-rules v2 artifact (MODIFY ONLY — never run live)
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C08).
#
# Pins chunks/C08.md "## Tests": re-pinned-leg-shaped checks for the grew
# engine spec (Research: Parallel label ensure, checklist spec constants),
# the NEW schema-2 fixture legs (drifted → exactly ONE update_createcard_
# checklists action naming the v2 artifact; matching → zero; schema-1 →
# UNVERIFIABLE runbook note and zero checklist actions), the engine↔artifact
# item-list equality, the skill-text pins (backup gate, human-executed
# import wording, Research: Parallel, schema-2 capture), and the artifact
# itself (five extras, OQ13 check posture, Single Session LAST).
#
# ENGINE JSON CONTRACT for schema 2 (dev implements to this — fixed here
# because the assertions below are the interface, same posture as the
# sibling surface.sh): snapshots gain "schema": "wekan-board-snapshot/2"
# plus top-level "checklist_extras": {<checklist name>: {"items": [names],
# "checked": [names]}}; the new action shape is
#   {"action":"update_createcard_checklists", "artifact":<path>, …}
# with the artifact path naming the ticket folder's board-rules-v12.65.json.
# The runbook note for schema-1 snapshots may ride stderr OR the --format
# text stream — but NEVER inside the JSON array (idempotence: a note is not
# an action).
#
# The surface.sh re-pin of the spec-text legs lands in C08's dev commit
# (same-commit doc-parity); THIS file is self-contained and adds no legs to
# surface.sh, so the plan-Commands regression line never reads this ticket's
# designed reds.
#
# AC trace: t1[C08 AC1 — schema-1 behavior stays action-clean + UNVERIFIABLE
# note; py_compile] t2[AC1/T1c — drifted schema-2 fixture → EXACTLY one
# update_createcard_checklists naming the artifact] t3[AC1 — matching extras
# → zero actions] t4[AC2 — Research: Parallel ensure only when the snapshot
# lacks the label, case-insensitive] t5[AC4 — engine spec constants byte-
# equal to C07's landed skill text] t6[C08 T2/AC3 — skill text pins incl.
# the never-agent-applies negative and the persisted :v87 degrade note]
# t7[AC4 — artifact validity + five extras + OQ13 check posture + v1-copy
# equality] t8[AC4 — engine↔artifact item-list equality (drift fails loudly)]
# t9[C11 — the schema-2 capture path executable end-to-end: skill step 1 names
#     get_rule AND server.py::_slim_rule passes the checklist extras through
#     (one leg, reddens where the contract is consumed; GREEN ON ARRIVAL after
#     C11 dev lands — RESEARCH F5's defect pinned away)].
#
# Red posture: t1–t8 (except the flagged HOLD sub-legs) DESIGNED RED at
# authoring 2026-11-01 — the engine hard-rejects schema 2 (verified: exit 2
# "want wekan-board-snapshot/1"), the artifact does not exist, the skill
# carries no checklist spec. The reds name those surfaces, never a harness
# fault. The HOLD sub-legs (schema-1 action-set cleanliness, engine offline-
# ness, :v87 degrade note) are green now.
#
# Usage:
#   bash tests/wekan-board-provision/checklist-cutover.sh           # t1..t9
#   bash tests/wekan-board-provision/checklist-cutover.sh t2 t7     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ENGINE="scripts/provision-board.py"
SERVER="containers/wekan-mcp/wekan_mcp/server.py"
SKILL="skills/wekan-board-provision/SKILL.md"
SRC_BOARDS=".rulesync/skills/boards/SKILL.md"
FXDIR="tests/wekan-board-provision/fixtures"
FX_LIVE="$FXDIR/ai-dev-live-2026-10-31.json"
FX_FULL="$FXDIR/ai-dev-full-provisioned.json"
FX_DRIFT="$FXDIR/ai-dev-schema2-drift.json"
FX_MATCH="$FXDIR/ai-dev-schema2-matching.json"
FX_NOLABEL="$FXDIR/ai-dev-schema2-no-parallel-label.json"
FX_CASE="$FXDIR/ai-dev-schema2-labelcase.json"
ARTIFACT=".agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json"
V1=".agents/plans/2026/2026-10-dep-wekan-v12-upgrade/board-rules-v12.64.json"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8 9; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-9]$ ]] || fail "unknown check id '$a' (expected t1..t9)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/cf96-cutover-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# Fixture self-validation before blaming dev (sibling-suite law).
for fx in "$FX_DRIFT" "$FX_MATCH" "$FX_NOLABEL" "$FX_CASE"; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$fx" \
    || fail "harness: $fx is not valid JSON — the test data itself is broken (report, do not blame dev)"
done

run_engine() { # run_engine <out-name> <fixture> — stdout captured, exit tolerated
  local name="$1" fx="$2"
  python3 "$ENGINE" --fixture "$fx" --format json >"$TMP/$name.out" 2>"$TMP/$name.err"
}

# The 11 stage names as C07 LANDED them in the boards skill (authority text).
extract_skill_stages() {
  python3 - "$SRC_BOARDS" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?ms)^\s*- \*\*Lifecycle\*\*(.*?)(?=^\s*- \*\*|^#|\Z)", text)
run = None
if m:
    for mm in re.finditer(r"(?:`[^`]+`\s*\|?\s*){3,}", m.group(0)):
        run = re.findall(r"`([^`]+)`", mm.group(0))
        break
if run is None:
    print("MISSING")
    sys.exit(1)
sys.stdout.write(json.dumps(run))
PY
}

# --- t1: schema-1 legs stay clean + the UNVERIFIABLE note (C08 T1c / AC1) -----------
if want t1; then
  python3 -m py_compile "$ENGINE" || fail "t1[C08 AC1]: py_compile of $ENGINE failed — dev broke the engine's syntax"
  for fx in "$FX_LIVE" "$FX_FULL"; do
    run_engine s1 "$fx" || { cat "$TMP/s1.err" >&2; fail "t1[C08 AC1]: engine nonzero on schema-1 fixture $fx — schema 1 must keep working UNCHANGED"; }
    if ! python3 - "$TMP/s1.out" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
assert isinstance(got, list) and all(isinstance(a, dict) for a in got), "JSON array contract broken"
if any(a.get("action") == "update_createcard_checklists" for a in got):
    print("a checklist action appeared for a SCHEMA-1 snapshot — against schema 1 the engine prints the spec as a runbook NOTE, never an action (idempotence law, C08 T1c)"); sys.exit(1)
PY
    then fail "t1[C08 AC1/T1c]: schema-1 action cleanliness broken on $fx (reason above)"; fi
    # the runbook note: stderr or --format text must carry the unverifiable
    # statement (designed red until dev: today the engine says nothing about
    # checklists at all).
    python3 "$ENGINE" --fixture "$fx" --format text >"$TMP/t1txt.out" 2>"$TMP/t1txt.err" || { cat "$TMP/t1txt.err" >&2; fail "t1: engine nonzero (text format) on $fx"; }
    grep -qiE 'unverifi' "$TMP/t1txt.err" "$TMP/t1txt.out" \
      || fail "t1[C08 T1c]: neither stderr nor the text output of a schema-1 run names the checklist spec as UNVERIFIABLE — schema-1 snapshots must get the runbook note (and still zero checklist actions) (designed red before C08 dev)"
  done
  ok "t1[C08 AC1]: schema-1 stays action-clean, compiles, and grows the UNVERIFIABLE runbook note"
fi

# --- t2: drifted schema-2 → EXACTLY one update_createcard_checklists ------------------
if want t2; then
  if ! run_engine drift "$FX_DRIFT"; then
    grep -q "snapshot/1" "$TMP/drift.err" \
      && fail "t2[C08 T1c]: the engine still hard-rejects wekan-board-snapshot/2 ('$FX_DRIFT' refused: $(head -1 "$TMP/drift.err")) — schema-2 support is C08 T1c's first task (designed red before C08 dev, not a harness fault)" \
      || { cat "$TMP/drift.err" >&2; fail "t2: engine nonzero on the drifted schema-2 fixture (reason above)"; }
  fi
  if ! python3 - "$TMP/drift.out" "$ARTIFACT" <<'PY'
import json, sys
try:
    got = json.load(open(sys.argv[1]))
except Exception:
    print("engine schema-2 stdout is not the JSON action array"); sys.exit(1)
cc = [a for a in got if a.get("action") == "update_createcard_checklists"]
if len(cc) != 1:
    print(f"the drifted fixture must yield EXACTLY ONE update_createcard_checklists action, got {len(cc)} (full plan: {json.dumps(got)[:400]})"); sys.exit(1)
blob = json.dumps(cc[0])
if "board-rules-v12.65.json" not in blob:
    print(f"the action must NAME the v2 artifact path (C08 T1c: naming the artifact is part of the runbook render); got {blob[:200]}"); sys.exit(1)
PY
  then fail "t2[C08 AC1]: the drifted-schema-2 leg failed (reason above)"; fi
  ok "t2[C08 AC1/T1c]: drifted schema-2 snapshot -> exactly one update_createcard_checklists action naming the v2 artifact"
fi

# --- t3: matching schema-2 → zero actions (the applied-state fixture) -----------------
if want t3; then
  run_engine match "$FX_MATCH" \
    || { grep -q "snapshot/1" "$TMP/match.err" \
      && fail "t3[C08 AC1]: engine still rejects wekan-board-snapshot/2 ('$(head -1 "$TMP/match.err")') — schema-2 support is C08 T1c (designed red before C08 dev, not a harness fault)" \
      || { cat "$TMP/match.err" >&2; fail "t3: engine nonzero on the matching schema-2 fixture (reason above)"; }; }
  if ! python3 - "$TMP/match.out" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
if got:
    print(f"the fully-applied schema-2 fixture produced {len(got)} actions: {json.dumps(got)[:300]} — zero actions once applied (C08 T1c)"); sys.exit(1)
PY
  then fail "t3[C08 AC1]: the zero-actions leg failed (reason above)"; fi
  ok "t3[C08 AC1]: matching extras + present label -> zero actions (idempotent applied state)"
fi

# --- t4: Research: Parallel ensure only when absent; case-insensitive (AC2) -----------
if want t4; then
  run_engine nolabel "$FX_NOLABEL" \
    || { grep -q "snapshot/1" "$TMP/nolabel.err" \
      && fail "t4[C08 AC2]: engine rejects wekan-board-snapshot/2 — schema-2 support (C08 T1c) has not landed; the label-ensure legs are designed red until then" \
      || { cat "$TMP/nolabel.err" >&2; fail "t4[C08 AC2]: engine nonzero on the label-absent schema-2 fixture (reason above)"; }; }
  run_engine casey "$FX_CASE" \
    || { grep -q "snapshot/1" "$TMP/casey.err" \
      && fail "t4[C08 AC2]: engine rejects wekan-board-snapshot/2 — schema-2 support (C08 T1c) has not landed; the label-ensure legs are designed red until then" \
      || { cat "$TMP/casey.err" >&2; fail "t4[C08 AC2]: engine nonzero on the lowercase-label fixture (reason above)"; }; }
  if ! python3 - "$TMP/nolabel.out" "$TMP/casey.out" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
hits = [x for x in a if x.get("action") == "create_label" and str(x.get("name","")).lower() == "research: parallel"]
if len(hits) != 1:
    print(f"label-absent snapshot must emit EXACTLY one create_label 'Research: Parallel', got {hits}"); sys.exit(1)
color = hits[0].get("color")
if not (isinstance(color, str) and color):
    print(f"the Research: Parallel ensure needs a non-empty string color (orange is the palette default; presence judged by NAME, color not pinned beyond validity) — got {color!r}"); sys.exit(1)
already = [x for x in b if x.get("action") == "create_label" and str(x.get("name","")).lower() == "research: parallel"]
if already:
    print(f"the snapshot already carries 'research: parallel' (lowercase) — matching is CASE-INSENSITIVE by name, yet the plan emits {already}"); sys.exit(1)
PY
  then fail "t4[C08 AC2]: the Research: Parallel ensure legs failed (reason above)"; fi
  ok "t4[C08 AC2]: Research: Parallel ensured only when absent, matched case-insensitively like the Provider labels"
fi

# --- t5: engine spec constants == C07's landed skill text (AC4) ------------------------
if want t5; then
  stages_json=$(extract_skill_stages) || true
  if [ "${stages_json:-MISSING}" = "MISSING" ]; then
    fail "t5[C08 AC4]: the boards skill (C07's landed text — the authority the engine copies) carries no pipe-delimited Lifecycle item list — C07 must land before C08's copy is checkable (wave order guards this; a red HERE at review time means the order was violated)"
  fi
  if ! python3 - "$ENGINE" "$stages_json" <<'PY'
import ast, json, sys
want = json.loads(sys.argv[2])
tree = ast.parse(open(sys.argv[1]).read())
hits = []
for node in ast.walk(tree):
    if isinstance(node, ast.List):
        vals = [e.value for e in node.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        if vals == want and len(vals) == len(want):
            hits.append("list-constant")
if not hits:
    print(f"engine spec carries no 11-string list equal to C07's landed Lifecycle text — T1(b): the constants copy C07's FINAL item list, NEVER retype from memory; this equality is AC4's drift alarm (designed red before C08 dev, red here after C08 means a retype drifted)"); sys.exit(1)
print(f"ok — {len(hits)} engine list node(s) equal the 11-name spec (HITL may alias the same constant; the artifact-side equality leg proves both lists carry it)")
PY
  then fail "t5[C08 AC4]: the engine-spec equality pin failed (reason above)"; fi
  ok "t5[C08 AC4]: engine checklist spec constants equal C07's landed 11-item text (copy-not-retype proven)"
fi

# --- t6: skill text pins (C08 T2 / AC3) -------------------------------------------------
if want t6; then
  grep -qiE 'Research: Parallel' "$SKILL" \
    || fail "t6[C08 T2]: the provision skill never names the Research: Parallel label ensure (designed red before C08 dev — the spec section grows it)"
  grep -qE 'snapshot/2|schema 2|schema-2' "$SKILL" \
    || fail "t6[C08 T2]: step 1 (snapshot collection) does not document the schema-2 checklist-extras capture"
  grep -qiE 'backup' "$SKILL" \
    || fail "t6[C08 T2/AC3]: the apply step lost the backup gate — the owner takes a board backup BEFORE the rules import"
  grep -qiE 'human-executed|owner.*import|import.*owner|runs the import' "$SKILL" \
    || fail "t6[C08 T2/AC3]: the human-executed Import-JSON step is not stated (agents emit the recipe and stop — checklist extras are UI/Import-JSON-only, never REST)"
  grep -qiE 'v87' "$SKILL" \
    || fail "t6[C08 T2 HOLD]: the deployed-surface degrade note (:v87 create_label absence, retired by the C10 bump) vanished — the note stays until the bump lands"
  grep -qE 'board-rules-v12\.65\.json' "$SKILL" \
    || fail "t6[C08 T2]: the skill must point the human import at the ticket folder's board-rules-v12.65.json (the C08 artifact)"
  python3 - "$SKILL" <<'PY' || fail "t6[C08 AC3 negative]: the skill says or implies the AGENT applies checklist changes (reason above)"
import re, sys
text = open(sys.argv[1]).read()
flat = re.sub(r"\s+", " ", text)
for m in re.finditer(r"[^.]*checklist[^.]*", flat, re.I):
    s = m.group(0)
    if re.search(r"\bagent[s]? (will |can |should )?(applies?|updates?|imports?|edits?)\b", s, re.I):
        print(s[:160]); sys.exit(1)
print("ok")
PY
  ok "t6[C08 AC3/T2]: skill carries the checklist spec section, schema-2 capture, backup gate, human-executed import, v87 degrade, artifact pointer — and never says the agent applies"
fi

# --- t7: the v2 artifact itself (C08 T3 / AC4) -------------------------------------------
if want t7; then
  [ -f "$ARTIFACT" ] \
    || fail "t7[C08 T3]: $ARTIFACT does not exist yet — the v2 rules-import artifact is C08's third task (designed red before C08 dev; C10 step 7 hands it to the owner)"
  [ -f "$V1" ] || fail "harness: the v1 artifact $V1 is the Services/Type/Model(s) copy-source and must exist"
  if ! python3 - "$ARTIFACT" "$V1" "$SRC_BOARDS" <<'PY'
import json, re, sys

rules = json.load(open(sys.argv[1]))
assert isinstance(rules, list) and len(rules) == 1, f"artifact must be a one-rule list, got {rules if isinstance(rules,list) else type(rules)}"
rule = rules[0]
assert rule["title"].startswith("Std checklists + defaults"), f"rule title drifted: {rule['title']}"
assert rule["trigger"]["activityType"] == "createCard", "trigger must stay the createCard activity (v1 shape)"

acts = [rule["action"]] + list(rule.get("extraActions") or [])
adds = {a["checklistName"]: a["checklistItems"].split(",") for a in acts if a.get("actionType") == "addChecklistWithItems"}
checks = [a for a in acts if a.get("actionType") == "checkItem"]
assert set(adds) == {"Services", "Type", "Model(s)", "Lifecycle", "Human in the Loop"}, f"five checklist extras expected, got {sorted(adds)}"

v1 = json.load(open(sys.argv[2]))[0]
v1acts = [v1["action"]] + list(v1.get("extraActions") or [])
v1adds = {a["checklistName"]: a["checklistItems"].split(",") for a in v1acts if a.get("actionType") == "addChecklistWithItems"}
assert adds["Services"] == v1adds["Services"], "Services must be COPIED from v1 (15 items), not retyped"
assert len(adds["Services"]) == 15, f"Services has {len(adds['Services'])} items, want 15"
assert set(adds["Type"]) == {"feat","bug","debug","dep","refactor","chore","docs"}, "Type drifted from the 7"
assert adds["Model(s)"] == v1adds["Model(s)"], "Model(s) must be copied from v1"

text = open(sys.argv[3]).read()
m = re.search(r"(?ms)^\s*- \*\*Lifecycle\*\*(.*?)(?=^\s*- \*\*|^#|\Z)", text)
run = next((re.findall(r"`([^`]+)`", mm.group(0)) for mm in re.finditer(r"(?:`[^`]+`\s*\|?\s*){3,}", m.group(0))), None)
assert run and run[-1] == "Single Session" and len(run) == 11, f"C07 skill list unreadable or drifted (artifact equality is pinned against it): {run}"
assert adds["Lifecycle"] == run, f"artifact Lifecycle {adds['Lifecycle']} != C07's landed skill text {run} (AC4: byte-equal or drift fails loudly)"
assert adds["Human in the Loop"] == run, f"artifact HITL {adds['Human in the Loop']} != the same 11 names (OQ6: HITL mirrors Lifecycle exactly)"
assert run == ["Exploration","Agent Decides Research","Pre Research","Planning","Post Research",
               "Test Writing","Chunk Development","Chunk Review","Final Review","Deployment",
               "Single Session"], f"C07 landed list drifted from the plan's T1 order: {run}"

named = {c["checklistName"] for c in checks}
assert named == {"Model(s)"}, f"OQ13: ONLY Model(s) may arrive checked — checkItems found on {sorted(named)}"
assert all(c["checkItemName"] == "Qwen Flash" for c in checks), "the one checkItem is Model(s) → Qwen Flash"
print("ok")
PY
  then fail "t7[C08 AC4/T3]: the artifact pins failed (reason above)"; fi
  ok "t7[C08 AC4]: artifact valid — five extras, Services/Type/Model(s) copied from v1, Lifecycle+HITL byte-equal to C07's text, only Qwen Flash checked"
fi

# --- t8: engine↔artifact equality, one more angle (AC4) ---------------------------------
if want t8; then
  [ -f "$ARTIFACT" ] || fail "t8[C08 AC4]: no artifact yet to compare the engine against (same designed red as t7)"
  if ! python3 - "$ENGINE" "$ARTIFACT" <<'PY'
import ast, json, sys

tree = ast.parse(open(sys.argv[1]).read())
lists = []
for node in ast.walk(tree):
    if isinstance(node, ast.List):
        vals = [e.value for e in node.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        if len(vals) == 11:
            lists.append(vals)
if not lists:
    print("t8: the engine carries no 11-item spec constant — the equality pin needs the spec landed (C08 T1b; designed red before C08 dev)"); sys.exit(1)
rule = json.load(open(sys.argv[2]))[0]
acts = [rule["action"]] + list(rule.get("extraActions") or [])
adds = {a["checklistName"]: a["checklistItems"].split(",") for a in acts if a.get("actionType") == "addChecklistWithItems"}
for name in ("Lifecycle", "Human in the Loop"):
    if adds[name] not in lists:
        print(f"t8: the artifact's {name} list is not equal to ANY engine spec constant — engine and artifact drift (AC4 fails loudly by design)"); sys.exit(1)
print("ok")
PY
  then fail "t8[C08 AC4]: engine↔artifact equality failed (reason above)"; fi
  ok "t8[C08 AC4]: engine spec constants equal the artifact's Lifecycle and HITL item lists"
fi

# --- t9: the schema-2 capture path is executable end-to-end (C11 T4 / F5 defect) ---
if want t9; then
  if ! python3 - "$SKILL" "$SERVER" <<'PY'
import ast, re, sys

skill = open(sys.argv[1]).read()
m = re.search(r"(?ms)To capture schema.*?fall back to schema 1", skill)
if not m:
    print("t9: the provision skill's schema-2 capture paragraph is gone — step 1 must still name the capture route (C11 AC4: an edit there is a review FAIL)"); sys.exit(1)
if "get_rule" not in m.group(0):
    print("t9: the capture sentence no longer names get_rule as the schema-2 capture route (skill step 1)"); sys.exit(1)

src = open(sys.argv[2]).read()
tree = ast.parse(src)
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "_slim_rule"), None)
if fn is None:
    print("t9: _slim_rule missing from server.py"); sys.exit(1)
if "extraActions" not in ast.unparse(fn):
    print("t9: server.py::_slim_rule does not pass the checklist extras through — the capture route the skill advertises structurally cannot answer (RESEARCH F5's failure mode pinned away by this leg)"); sys.exit(1)
print("ok")
PY
  then fail "t9[C11]: the schema-2 capture path is not executable end-to-end (reason above)"; fi
  ok "t9[C11]: capture path pinned end-to-end — provision step 1 names get_rule AND _slim_rule passes extraActions through, one leg where the contract is consumed"
fi

printf 'PASS: cf-96 cutover artifact checks (%d ok)\n' "$checks"
