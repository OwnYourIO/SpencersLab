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
# itself (five extras, OQ13 check posture, the cf-124 generation:
# rules envelope, Services 19 = v1's 15 + the four fixed repo targets, Lifecycle/
# HITL the 13 names, Human in the Loop last).
#
# ENGINE JSON CONTRACT for schema 2 (dev implements to this — fixed here
# because the assertions below are the interface, same posture as the
# sibling surface.sh): snapshots gain "schema": "wekan-board-snapshot/2"
# plus top-level "checklist_extras": {<checklist name>: {"items": [names],
# "checked": [names]}}; the new action shape is
#   {"action":"update_createcard_checklists", "artifact":<path>, …}
# with the artifact path naming the ticket folder's board-rules-v12.77 file
# (cf-124 C01; the cf-106 re-pin of this contract said v12.65 — the pointer
# moves with the ticket that re-issued the vocabulary, per the
# per-generation re-issue law).
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
# AC trace (cf-106 C02 re-pin): t2[C02 AC6 — the drift action's artifact pointer
# must name a board-rules-v12.65 file inside the cf-106 folder; old-pointer and
# new-pointer controls] t3[C02 AC5 — zero actions against the Dense-vocabulary
# applied-state fixtures] t7[C02 AC6 — the Dense artifact's Model(s) four labels
# (v1 copy rejected), exactly one checkItem = Model(s) → Qwen Dense, retired label
# absent] t8[C02 AC5 — engine↔artifact equality now also on the Model(s)
# items/checked pair] t10[C02 AC1/AC3/AC5 — Model(s) vocabulary generation
# coherent across engine spec, applied-state fixtures and the drift alarm, with a
# fabricated-Dense positive control and a fabricated fifth-option negative
# control].
#
# Red posture: t1–t8 (except the flagged HOLD sub-legs) DESIGNED RED at
# authoring 2026-11-01 — the engine hard-rejects schema 2 (verified: exit 2
# "want wekan-board-snapshot/1"), the artifact does not exist, the skill
# carries no checklist spec. The reds name those surfaces, never a harness
# fault. The HOLD sub-legs (schema-1 action-set cleanliness, engine offline-
# ness, :v87 degrade note) are green now.
# Red posture (cf-106 C02 era, kept as history): t7/t8 red when the Dense
# artifact was absent; t2's pointer sub-leg, t3 and t10's engine/fixture/drift
# pins red while spec and fixtures sat on different generations; t1/t4/t5/t6/t9
# and t10's two controls green.
# Red posture (cf-124 C01 re-pin, current): the generation moved — ARTIFACT now
# names this ticket's board-rules-v12.77-13item.json envelope, so t7/t8 are
# designed red until C01 dev writes it; t2's pointer pin and the t5 Services
# split-law leg are designed red until C01 flips RULES_ARTIFACT/CHECKLIST_SPEC;
# t3/t6 are designed red until C01 lands (applied-state fixtures already moved
# to 19/13, the provision skill still carries the v12.65-dense pointer and the
# 11/15 counts); t1/t4/t9/t10 and the control legs stay green.
#
# Usage:
#   bash tests/wekan-board-provision/checklist-cutover.sh           # t1..t10
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
ARTIFACT=".agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/board-rules-v12.77-13item.json"
V1=".agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json"
# cf-124 C01 (D11): the createCard rule-extra artifact is re-issued per
# vocabulary generation, so the CURRENT-state artifact lives in the cf-124
# ticket folder (the cf-106 Dense file and the cf-96 v1 file stay as the
# applied history). Any `board-rules-v12.77*` name is accepted there — the
# folder is the pin, the suffix records the vocabulary.
ARTIFACT_DIR=".agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8 9 10; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t(1[0-9]|[1-9])$ ]] || fail "unknown check id '$a' (expected t1..t10)"
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
  cat >"$TMP/artifact_ptr.py" <<'PY'
# The drift action must point the human at the CURRENT-generation rule-extra
# artifact: a board-rules-v12.77 file inside the ticket folder that re-issued
# the vocabulary generation (cf-124 C01 moves engine pointer and runbook
# citation together). Written as a reusable checker so the fabricated controls
# below prove the pin is not vacuous.
import json, re, sys
payload = json.load(open(sys.argv[1]))
acts = payload if isinstance(payload, list) else [payload]
cc = [a for a in acts if a.get("action") == "update_createcard_checklists"]
if len(cc) != 1:
    print(f"exactly ONE update_createcard_checklists action expected, got {len(cc)}: {json.dumps(payload)[:300]}"); sys.exit(1)
path = cc[0].get("artifact")
if not isinstance(path, str):
    print(f"the action must carry an artifact path string, got {path!r}"); sys.exit(1)
if not re.search(r"board-rules-v12\.77[\w.-]*\.json", path):
    print(f"the artifact path must name the current-generation rules file (board-rules-v12.77*), got {path}"); sys.exit(1)
if not path.startswith(sys.argv[2] + "/"):
    print(f"the artifact must live in the ticket folder that re-issued this vocabulary "
          f"generation ({sys.argv[2]}/), got {path} — cf-124 C01 moves the engine pointer "
          f"and the boards runbook citation to the 13-item artifact together"); sys.exit(1)
print("ok")
PY
  if ! python3 "$TMP/artifact_ptr.py" "$TMP/drift.out" "$ARTIFACT_DIR"; then
    fail "t2[cf-124 C01]: the drifted schema-2 plan's artifact pointer failed the pins above — the engine pointer still names a previous generation's artifact (designed red until C01 dev re-points RULES_ARTIFACT at this ticket's board-rules-v12.77 file)"; fi
  # Non-vacuity controls for the pointer pin (the suite's own checker decides).
  # Every control is the ENGINE's own drift payload mutated in one way, never a
  # hand-written minimal dict: a fabricated payload could pass or fail for shape
  # reasons and would prove nothing about the real plan output.
  # POSITIVE: the real payload with only the artifact field rewritten to another
  # v12.77-generation name in the ticket folder — the pin accepts any name in that
  # generation, and the payload keeps its full drift list, so the checker is proven
  # satisfiable by genuine engine output (not merely by a name-shaped string).
  python3 - "$TMP/drift.out" "$TMP/ctl-good.json" <<'PPOS'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload, "no engine drift payload to derive the positive control from (harness fault)"
rewritten = []
for act in payload:
    if act.get("action") == "update_createcard_checklists":
        act = dict(act, artifact=".agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/board-rules-v12.77.json")
    rewritten.append(act)
json.dump(rewritten, open(sys.argv[2], "w"))
base = json.load(open(sys.argv[1]))
same = [a for a, b in zip(base, rewritten) if a is not b]
assert len(same) == 1 and set(same[0]) == set(base[0]), "positive control mutated more than the artifact field"
PPOS
  python3 "$TMP/artifact_ptr.py" "$TMP/ctl-good.json" "$ARTIFACT_DIR" >/dev/null 2>&1 \
    || fail "t2 control: the real engine payload with a v12.77 pointer into the ticket folder FAILED its own pin — the checker is broken (not the engine)"
  # NEGATIVES: one defect per arm, each a mutation of the real payload. A name-only
  # control would leave the count/type arms untested, so the missing-action,
  # duplicate-action, absent-artifact and previous-generation-pointer defects are
  # fed too (the stale-pointer arm is the one C01 must keep: a v12.65/cf-106 or
  # cf-96 pointer is the DEFECT this pin exists to catch, not a pass).
  cat >"$TMP/mutate.py" <<'PDEF'
# One defect per arm, each a single mutation of the engine's own drift payload.
import json, sys
payload, defect = json.load(open(sys.argv[1])), sys.argv[3]
out = []
for act in payload:
    if act.get("action") != "update_createcard_checklists":
        out.append(act); continue
    if defect == "stale":        # pointer at the applied, previous-generation cf-96 artifact
        act = dict(act, artifact=".agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json")
    elif defect == "prevgen":    # pointer at the just-superseded cf-106 Dense artifact
        act = dict(act, artifact=".agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json")
    elif defect == "oldgen":     # right folder, wrong version token in the name
        act = dict(act, artifact=".agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/board-rules-v12.65.json")
    elif defect == "noartifact": # the human is told nothing about what to import
        act = {k: v for k, v in act.items() if k != "artifact"}
    out.append(act)
if defect == "missing":          # the drift is reported with no import action at all
    out = [a for a in out if a.get("action") != "update_createcard_checklists"]
if defect == "double":           # two import actions for one drifted rule-extra set
    out = out + [a for a in payload if a.get("action") == "update_createcard_checklists"]
json.dump(out, open(sys.argv[2], "w"))
PDEF
  for defect in stale prevgen oldgen missing double noartifact; do
    python3 "$TMP/mutate.py" "$TMP/drift.out" "$TMP/ctl-$defect.json" "$defect" \
      || fail "t2 control: could not fabricate the '$defect' defect from the engine payload (harness fault)"
    python3 "$TMP/artifact_ptr.py" "$TMP/ctl-$defect.json" "$ARTIFACT_DIR" >/dev/null 2>&1 \
      && fail "t2 control: the fabricated '$defect' defect still PASSED the pointer pin — the guard is inert, fix the pin (not the engine)"
  done
  ok "t2[cf-124 C01/C08 AC1]: drifted schema-2 -> exactly one update_createcard_checklists naming a board-rules-v12.77 artifact inside the cf-124 folder, control-proven pointer pin with the stale/prev-gen/old-version negatives intact"
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
if not got:
    print("ok"); sys.exit(0)
drifts = [d for a in got if a.get("action") == "update_createcard_checklists" for d in (a.get("drift") or [])]
model = [d for d in drifts if d.startswith("Model(s)")]
if model:
    # The applied-state fixture carries the Dense Model(s) vocabulary the
    # engine spec still carries too — a Model(s) drift here would mean the two
    # sides forked on purpose (cf-106 C02 discipline, unchanged by cf-124).
    print(f"Model(s) vocabulary drift against the applied-state fixture: {model} — the "
          f"fixture and the engine's CHECKLIST_SPEC must read ONE Model(s) generation; "
          f"zero actions needs both sides agreeing (not a fixture fault)"); sys.exit(1)
print(f"the fully-applied schema-2 fixture produced {len(got)} actions: {json.dumps(got)[:300]} — zero actions once applied (C08 T1c); red now means the fixture or the spec is on the other checklist generation — the cf-124 C01 pair (fixture 19/13 + engine 19/13) lands together, designed red until then"); sys.exit(1)
PY
  then fail "t3[cf-124 C01/C08 AC1]: the zero-actions leg failed (reason above)"; fi
  ok "t3[cf-124 C01/C08 AC1]: matching extras (Services 19 + Lifecycle/HITL 13, Dense Model(s)) + present label -> zero actions (idempotent applied state)"
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
    print(f"engine spec carries no string list equal to the boards skill's landed Lifecycle text (13 names in the cf-124 generation) — T1(b): the constants copy the skill's FINAL item list, NEVER retype from memory; this equality is AC4's drift alarm (designed red before C01 dev, red here after C01 means a retype drifted)"); sys.exit(1)
print(f"ok — {len(hits)} engine list node(s) equal the 13-name spec (HITL may alias the same constant; the artifact-side equality leg proves both lists carry it)")
PY
  then fail "t5[C08 AC4]: the engine-spec equality pin failed (reason above)"; fi
  # cf-124 C01/D22: the Services half is the SPLIT law — folders derived from
  # ls services/ ∪ the fixed six extras, in order. This is the engine-side twin
  # of the rulesync-surface c11 Services exactness arm: folder drift reddens
  # HERE loudly, and a stale 15-item spec (the pre-cf-124 copy) reddens too.
  if ! python3 - "$ENGINE" <<'PY'
import ast, json, os, sys
tree = ast.parse(open(sys.argv[1]).read())
svc = None
for node in ast.walk(tree):
    if not isinstance(node, ast.Dict):
        continue
    for k, v in zip(node.keys, node.values):
        if isinstance(k, ast.Constant) and k.value == "Services" and isinstance(v, ast.Dict):
            for k2, v2 in zip(v.keys, v.values):
                if isinstance(k2, ast.Constant) and k2.value == "items" and isinstance(v2, ast.List):
                    vals = [e.value for e in v2.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                    if len(vals) == len(v2.elts):
                        svc = vals
folders = sorted(os.listdir("services"))
fixed = ["home-assistant", "agent context",
         "HomeAssistant", "Home-Assistant-Label-based-Features",
         "brother-ptouch-automation", "CuratedForest.com"]
if svc is None:
    print("no Services items list readable in the engine (spec shape moved — harness fault or C01 not landed)"); sys.exit(1)
if svc[:len(folders)] != folders:
    print(f"engine Services folder half is {svc[:len(folders)]}, want the live ls services/ folders first ({folders}) — the derived half must track the repo (D9 drift detector)"); sys.exit(1)
if svc[len(folders):] != fixed:
    print(f"engine Services extra half is {svc[len(folders):]}, want exactly the fixed six {fixed} in skill order — the extra set is fixed text, deliberately NOT folder-derived (cf-124 D22; a stale 15-item copy lands here as the missing four repo targets)"); sys.exit(1)
if len(svc) != len(folders) + 6:
    print(f"engine Services has {len(svc)} entries, want {len(folders)} folders + the fixed six"); sys.exit(1)
print("ok")
PY
  then fail "t5[cf-124 C01 AC5]: the engine Services split law failed (folders derived + extras fixed, 13+6=19) — designed red until C01 dev"; fi
  ok "t5[C08 AC4 + cf-124 C01 AC5]: engine checklist spec constants equal the skill's landed 13-item text, and Services is the split law — live folders ∪ the fixed six (a stale 15-item copy is the detected defect)"
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
  grep -qE 'board-rules-v12\.77' "$SKILL" \
    || fail "t6[cf-124 C01 T5]: the skill must point the human import at this ticket's board-rules-v12.77-13item.json (the current-generation artifact; D11 names it for the real pin) — designed red until C01 re-points it"
  # cf-124 C01 AC8: the hand-managed provision skill never regenerates, so a
  # missed CURRENT-state vocabulary place is PERMANENT drift. The counts are
  # swept outright (no historical reading exists for a wrong current count);
  # the v12.65-dense FILE may survive only inside an applied-history clause, so
  # the negative targets the CURRENT-pointer sentence, not any mention.
  grep -qE 'Services \(19' "$SKILL" \
    || fail "t6[cf-124 C01 AC8]: the provision skill's checklist-extras paragraph still counts the pre-cf-124 Services set — the spec section names Services (19 items) now (designed red before C01 dev)"
  grep -qE '13 stage names|13-item' "$SKILL" \
    || fail "t6[cf-124 C01 AC8]: the provision skill never names the 13-item Lifecycle generation (its vocabulary list re-derives from the landed boards text; designed red before C01 dev)"
  if grep -qE '11 stage names|11-item|Services \(15' "$SKILL"; then
    fail "t6[cf-124 C01 AC8 negative]: a stale 11-item vocabulary count survives in the hand-managed provision skill — it is a current-state surface (never regenerates), so the sweep must reach it (red until C01 dev, a drive-by regression after)"
  fi
  if python3 - "$SKILL" <<'PY'
import re, sys
t = re.sub(r"\s+", " ", open(sys.argv[1]).read())
# A v12.65-dense citation that is the CURRENT-generation pointer (not an
# applied-history note) is the stale state C01 removes. Exit 0 = defect found
# (the grep-style polarity of the sibling negative legs).
for m in re.finditer(r"v12\.65-dense", t):
    seg = t[max(0, m.start() - 260):m.end() + 40]
    if re.search(r"current[- ]generation|the artifact is re-issued|naming the .*import", seg, re.I) \
       and not re.search(r"applied history|stays as|history", seg, re.I):
        sys.exit(0)
sys.exit(1)
PY
  then fail "t6[cf-124 C01 AC8 negative]: the provision skill still points the CURRENT-generation import at the v12.65-dense artifact instead of the v12.77 13-item file (red until C01 dev)"; fi
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
  ok "t6[cf-124 C01 + C08 AC3/T2]: skill carries the checklist spec section, schema-2 capture, backup gate, human-executed import, v87 degrade, the v12.77 artifact pointer and the 19/13 generation counts — no stale 11-item/15-Services count or v12.65-dense CURRENT pointer — and never says the agent applies"
fi

# --- t7: the v2 artifact itself (C01 T3 / AC6; was C08 T3 / AC4) ------------------
# cf-124 re-cut: the artifact moves to this ticket's folder as the v12.77
# ENVELOPE {"rules": [one createCard rule]}; the Services anti-retyping law
# INVERTS from "== v1's 15" to "v1's 15 + the four fixed repo targets = 19" at
# equal strictness — a stale 15-item copy is now the DETECTED defect. The
# shipped invariants (exactly one checkItem, ONLY Model(s) arrives checked, the
# five-extras set, byte-equal Lifecycle/HITL, retired label absent) are kept.
if want t7; then
  [ -f "$ARTIFACT" ] \
    || fail "t7[cf-124 C01 AC6]: $ARTIFACT does not exist yet — C01 produces the v12.77 13-item rule-extra artifact for the new generation (modify-only, never applied by an agent; the owner imports it). Designed red until C01 dev writes it; the cf-106/cf-96 files stay as applied history."
  [ -f "$V1" ] || fail "harness: the v1 artifact $V1 is the Services/Type/Model(s) copy-source and must exist"
  cat >"$TMP/artifact_pins.py" <<'PY'
import json, re, sys

payload = json.load(open(sys.argv[1]))
assert isinstance(payload, dict) and isinstance(payload.get("rules"), list), \
    "artifact must be the {\"rules\": [...]} envelope (C01 T3 v12.77 shape), got " + type(payload).__name__
rules = payload["rules"]
assert len(rules) == 1, f"envelope must carry exactly one createCard rule, got {len(rules)}"
rule = rules[0]
assert rule["title"].startswith("Std checklists + defaults"), f"rule title drifted: {rule['title']}"
assert rule["trigger"]["activityType"] == "createCard", "trigger must stay the createCard activity (v1 shape)"

acts = [rule["action"]] + list(rule.get("extraActions") or [])
adds = {a["checklistName"]: a["checklistItems"].split(",") for a in acts if a.get("actionType") == "addChecklistWithItems"}
checks = [a for a in acts if a.get("actionType") == "checkItem"]
assert set(adds) == {"Services", "Type", "Model(s)", "Lifecycle", "Human in the Loop"}, f"five checklist extras expected, got {sorted(adds)}"

v1 = json.load(open(sys.argv[2]))
v1 = v1[0] if isinstance(v1, list) else v1["rules"][0]
v1acts = [v1["action"]] + list(v1.get("extraActions") or [])
v1adds = {a["checklistName"]: a["checklistItems"].split(",") for a in v1acts if a.get("actionType") == "addChecklistWithItems"}
# cf-124 D22 inverted Services law: v1's fifteen items, COPIED not retyped,
# PLUS the four fixed repo targets the owner added (both-lists ruling). The
# fifteen-item prefix equality keeps the anti-retyping control; the stale
# fifteen-only copy is the defect the suite now detects.
FIXED4 = ["HomeAssistant", "Home-Assistant-Label-based-Features",
          "brother-ptouch-automation", "CuratedForest.com"]
assert adds["Services"][:15] == v1adds["Services"], \
    f"the first 15 Services items must be COPIED from v1 (not retyped); got {adds['Services'][:15]}"
assert adds["Services"][15:] == FIXED4, \
    f"Services must extend v1's 15 with the four fixed repo targets in this order; got {adds['Services'][15:]}"
assert len(adds["Services"]) == 19, f"Services has {len(adds['Services'])} items, want 15 + 4 = 19"
assert set(adds["Type"]) == {"feat","bug","debug","dep","refactor","chore","docs"}, "Type drifted from the 7"
assert adds["Model(s)"] == ["Qwen Large", "Qwen Dense", "Qwen Flash", "Local (gpu-ai)"], (
    f"Model(s) extras must be the Dense generation's four labels in order; got {adds['Model(s)']} "
    f"(v1 carries {v1adds['Model(s)']} — copying it verbatim is the failure this leg exists for)")
assert "Qwen 27b" not in json.dumps(rule), "the current-generation artifact may not carry the retired label — it belongs to the applied history (v1/cf-96) and the boards alias sentence only"

text = open(sys.argv[3]).read()
m = re.search(r"(?ms)^\s*- \*\*Lifecycle\*\*(.*?)(?=^\s*- \*\*|^#|\Z)", text)
run = next((re.findall(r"`([^`]+)`", mm.group(0)) for mm in re.finditer(r"(?:`[^`]+`\s*\|?\s*){3,}", m.group(0))), None)
assert run and run[-1] == "Human in the Loop" and len(run) == 13, f"boards skill list unreadable or drifted (artifact equality is pinned against it): {run}"
assert adds["Lifecycle"] == run, f"artifact Lifecycle {adds['Lifecycle']} != the boards skill's landed 13-item text {run} (AC4: byte-equal or drift fails loudly)"
assert adds["Human in the Loop"] == run, f"artifact HITL {adds['Human in the Loop']} != the same 13 names (HITL mirrors Lifecycle exactly, ending Human in the Loop)"
assert run == ["Session Rename","Worktree Creation","Exploration","Agent Decides Research",
               "Planning","Test Writing","Chunk Development","Chunk Review","Final Review",
               "Deployment","Single Session","Follow-up cards created","Human in the Loop"], \
    f"boards landed list drifted from the cf-124 C01 plan order (Session Rename first, HITL last): {run}"

named = {c["checklistName"] for c in checks}
assert named == {"Model(s)"}, f"OQ13: ONLY Model(s) may arrive checked — checkItems found on {sorted(named)}"
assert all(c["checkItemName"] == "Qwen Dense" for c in checks), (
    f"the one checkItem must be Model(s) -> Qwen Dense (the Dense default-check this artifact exists for); "
    f"got {[c['checkItemName'] for c in checks]}")
assert len(checks) == 1, f"exactly one checkItem expected (Model(s) default only); got {len(checks)}"
assert not re.search(r"custom[-_ ]?[Ff]ield", json.dumps(rule)), \
    "D17/OQ4: the artifact carries NO custom-field action — WeKan rules never had one and a promised one is inert upstream"
print("ok")
PY
  if ! python3 "$TMP/artifact_pins.py" "$ARTIFACT" "$V1" "$SRC_BOARDS"; then
    fail "t7[cf-124 C01 AC6]: the artifact pins failed (reason above)"; fi
  # The copy-source must itself be the PRE-Dense generation: repointing V1 at a
  # Dense-era file would make the Model(s) anti-copy arm vacuous by construction.
  if ! python3 - "$V1" <<'PCOPY'
import json, sys
raw = json.load(open(sys.argv[1]))
v1 = raw[0] if isinstance(raw, list) else raw["rules"][0]
acts = [v1["action"]] + list(v1.get("extraActions") or [])
adds = {a["checklistName"]: a["checklistItems"].split(",") for a in acts if a.get("actionType") == "addChecklistWithItems"}
checks = [a for a in acts if a.get("actionType") == "checkItem"]
bad = []
if "Qwen 27b" not in adds.get("Model(s)", []):
    bad.append(f"the copy-source Model(s) extras {adds.get('Model(s)')} carry no retired label — it is not the pre-Dense generation")
if [c.get("checkItemName") for c in checks] != ["Qwen Flash"]:
    bad.append(f"the copy-source checkItems are {[c.get('checkItemName') for c in checks]}, want the applied generation's single Model(s) → Qwen Flash")
if len(adds.get("Services", [])) != 15:
    bad.append(f"the copy-source Services has {len(adds.get('Services'))} items, want the v1 15 (v12.64/v12.65 era)")
print("; ".join(bad)); sys.exit(1 if bad else 0)
PCOPY
  then fail "t7 control: the copy-source $V1 is not the pre-Dense generation — the anti-copy arm would be vacuous (re-point V1, never relax the leg)"; fi
  # Non-vacuity: defects fabricated into a COPY of the real artifact, one per arm
  # (wrong vocabulary, wrong copy, missing extra, wrong and duplicated checkItem,
  # Lifecycle drift, and the NEW cf-124 defects: the stale 15-item Services copy
  # and the missing CuratedForest.com). The suite's own checker decides; every
  # one must be rejected or the leg is inert.
  cat >"$TMP/mutate_art.py" <<'PART'
import json, sys
src, defect, v1path = json.load(open(sys.argv[1])), sys.argv[3], sys.argv[4]
rule = src["rules"][0]
acts = [rule["action"]] + list(rule.get("extraActions") or [])
def find(name, kind):
    return [a for a in acts if a.get("actionType") == kind and a.get("checklistName") == name]
if defect == "model_v1":          # Model(s) copied verbatim from the pre-Dense generation
    raw = json.load(open(v1path))
    v1 = raw[0] if isinstance(raw, list) else raw["rules"][0]
    v1acts = [v1["action"]] + list(v1.get("extraActions") or [])
    src_items = next(a["checklistItems"] for a in v1acts
                     if a.get("actionType") == "addChecklistWithItems" and a.get("checklistName") == "Model(s)")
    find("Model(s)", "addChecklistWithItems")[0]["checklistItems"] = src_items
elif defect == "sixth_label":     # a fifth option joins the vocabulary generation
    tgt = find("Model(s)", "addChecklistWithItems")[0]
    tgt["checklistItems"] = tgt["checklistItems"] + ",Qwen Mini"
elif defect == "services_typed":  # Services retyped here instead of copied from v1
    tgt = find("Services", "addChecklistWithItems")[0]
    items = tgt["checklistItems"].split(",")
    items[3] = "item-not-in-v1"
    tgt["checklistItems"] = ",".join(items)
elif defect == "services_stale15":  # cf-124: the pre-cutover 15-item Services copy — now the defect
    tgt = find("Services", "addChecklistWithItems")[0]
    tgt["checklistItems"] = ",".join(tgt["checklistItems"].split(",")[:15])
elif defect == "services_no_cf":    # cf-124: the four repo targets present but CuratedForest.com dropped
    tgt = find("Services", "addChecklistWithItems")[0]
    tgt["checklistItems"] = ",".join(i for i in tgt["checklistItems"].split(",") if i != "CuratedForest.com")
elif defect == "missing_extra":   # the HITL mirror extra is dropped
    rule["extraActions"] = [a for a in (rule.get("extraActions") or [])
                            if not (a.get("actionType") == "addChecklistWithItems" and a.get("checklistName") == "Human in the Loop")]
elif defect == "checkitem_flash": # the default-check target stays the retired generation's
    for c in find("Model(s)", "checkItem"):
        c["checkItemName"] = "Qwen Flash"
elif defect == "second_check":    # a second checklist pre-arrives checked (OQ13: Model(s) only)
    rule.setdefault("extraActions", []).append({"actionType": "checkItem", "checklistName": "Type", "checkItemName": "feat"})
elif defect == "custom_field":    # D17: a custom-field action the platform cannot execute
    rule.setdefault("extraActions", []).append({"actionType": "setCustomField", "customFieldName": "Priority", "value": "5"})
elif defect == "lifecycle_short": # Lifecycle drifts from the boards skill's 13 names
    tgt = find("Lifecycle", "addChecklistWithItems")[0]
    tgt["checklistItems"] = ",".join(tgt["checklistItems"].split(",")[:-1])
json.dump(src, open(sys.argv[2], "w"))
PART
  for defect in model_v1 sixth_label services_typed services_stale15 services_no_cf missing_extra checkitem_flash second_check custom_field lifecycle_short; do
    python3 "$TMP/mutate_art.py" "$ARTIFACT" "$TMP/art-$defect.json" "$defect" "$V1" \
      || fail "t7 control: could not fabricate the '$defect' defect from $ARTIFACT (harness fault)"
    python3 "$TMP/artifact_pins.py" "$TMP/art-$defect.json" "$V1" "$SRC_BOARDS" >/dev/null 2>&1 \
      && fail "t7 control: the fabricated '$defect' defect still PASSED the artifact pins — the leg is inert, fix the checker (not the artifact)"
  done
  # Envelope-shape control: the same checker must reject a bare-LIST artifact (the
  # pre-envelope generation) — proof the v12.77 envelope pin is live, not decorative.
  python3 - "$ARTIFACT" "$TMP/art-barelist.json" <<'PJ'
import json, sys
src = json.load(open(sys.argv[1]))
json.dump(src["rules"], open(sys.argv[2], "w"))
PJ
  python3 "$TMP/artifact_pins.py" "$TMP/art-barelist.json" "$V1" "$SRC_BOARDS" >/dev/null 2>&1 \
    && fail "t7 control: a bare-LIST artifact (no rules envelope) PASSED — the v12.77 envelope pin is inert (C01 T3 shape not enforced)"
  ok "t7[cf-124 C01 AC6]: artifact valid — one-rule rules envelope, five extras, Services = v1's 15 COPIED + the four fixed repo targets = 19 (a stale 15-copy or a missing CuratedForest.com is a detected defect), Type on the 7, Model(s) on the Dense four labels (v1 copy explicitly rejected), Lifecycle+HITL byte-equal to the boards skill's 13-item text (Session Rename first, Human in the Loop last), exactly one checkItem = Model(s) → Qwen Dense, NO custom-field action, retired label absent — control-proven: the copy-source is the pre-Dense generation and ten fabricated defects (v1-copied Model(s), fifth label, retyped Services, stale-15 Services, missing CuratedForest.com, missing HITL extra, Qwen Flash target, second checkItem, custom-field action, short Lifecycle) plus the bare-list shape are all rejected"
fi

# --- t8: engine↔artifact equality, one more angle (AC4 + cf-124 C01) ---------------
if want t8; then
  [ -f "$ARTIFACT" ] || fail "t8[C08 AC4]: no artifact yet to compare the engine against (same designed red as t7)"
  if ! python3 - "$ENGINE" "$ARTIFACT" <<'PY'
import ast, json, sys

tree = ast.parse(open(sys.argv[1]).read())
lists = []
for node in ast.walk(tree):
    if isinstance(node, ast.List):
        vals = [e.value for e in node.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        if len(vals) == 13:
            lists.append(vals)
if not lists:
    print("t8: the engine carries no 13-item spec constant — the equality pin needs the new-generation spec landed (cf-124 C01; designed red before C01 dev)"); sys.exit(1)

# The engine's inline Model(s) items/checked constants (LIFECYCLE_ITEMS rides a
# name, so only inline string lists are readable here — which is exactly the
# vocabulary generation this leg cares about).
spec_node = next((n for n in ast.walk(tree) if isinstance(n, ast.Assign)
                  and any(isinstance(t, ast.Name) and t.id == "CHECKLIST_SPEC" for t in n.targets)), None)
spec = {}
services_spec = None
if spec_node is not None:
    for d in ast.walk(spec_node.value):
        if not isinstance(d, ast.Dict):
            continue
        for k, v in zip(d.keys, d.values):
            if not (isinstance(k, ast.Constant) and isinstance(v, ast.Dict)):
                continue
            if k.value == "Model(s)":
                for k2, v2 in zip(v.keys, v.values):
                    if isinstance(k2, ast.Constant) and k2.value in ("items", "checked") and isinstance(v2, ast.List):
                        vals = [e.value for e in v2.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                        if len(vals) == len(v2.elts):
                            spec[k2.value] = vals
            if k.value == "Services":
                for k2, v2 in zip(v.keys, v.values):
                    if isinstance(k2, ast.Constant) and k2.value == "items" and isinstance(v2, ast.List):
                        vals = [e.value for e in v2.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                        if len(vals) == len(v2.elts):
                            services_spec = vals

payload = json.load(open(sys.argv[2]))
rule = payload["rules"][0]
acts = [rule["action"]] + list(rule.get("extraActions") or [])
adds = {a["checklistName"]: a["checklistItems"].split(",") for a in acts if a.get("actionType") == "addChecklistWithItems"}
for name in ("Lifecycle", "Human in the Loop"):
    if adds[name] not in lists:
        print(f"t8: the artifact's {name} list is not equal to ANY engine spec constant — engine and artifact drift (AC4 fails loudly by design)"); sys.exit(1)
if services_spec is None:
    print("t8: no inline Services items constant readable in the engine CHECKLIST_SPEC — the Services equality leg needs it inline"); sys.exit(1)
if services_spec != adds["Services"]:
    print(f"t8: engine Services spec ({len(services_spec)} items) != artifact Services extras ({len(adds['Services'])} items) — the engine, the artifact and the rule must carry ONE Services generation (cf-124 D22: folders ∪ fixed six on both sides; the drift action's own plan must not drift from the artifact it points at)"); sys.exit(1)
if not spec.get("items"):
    print("t8: no inline Model(s) items constant readable in the engine — the vocabulary equality leg needs the spec's items list inline (cf-106 C02 keeps it inline)"); sys.exit(1)
if spec["items"] != adds["Model(s)"]:
    print(f"t8: engine Model(s) spec {spec['items']} != artifact Model(s) extras {adds['Model(s)']} — the engine and the rule-extra artifact must carry the SAME vocabulary generation (cf-106 C02 AC5: the drift action's own plan must not drift from the artifact it points at)"); sys.exit(1)
targets = sorted(c["checkItemName"] for c in acts if c.get("actionType") == "checkItem")
want_checked = sorted(spec.get("checked", []))
if targets != want_checked:
    print(f"t8: the artifact checks {targets} but the engine spec declares checked {want_checked} — the default-check generation drifts between engine and artifact (cf-106 C02 flips both together)"); sys.exit(1)
print("ok")
PY
  then fail "t8[cf-124 C01/C02 AC5/C08 AC4]: engine↔artifact equality failed (reason above)"; fi
  ok "t8[cf-124 C01 + C02 AC5/C08 AC4]: engine spec equals the artifact on Lifecycle/HITL lists, the Services 19-item split, AND the Model(s) items/checked pair (one vocabulary generation on both sides)"
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

# --- t10: Model(s) vocabulary generation coherent across engine, fixtures and the
#     drift alarm (cf-106 C02 AC1/AC5) --------------------------------------------------
if want t10; then
  cat >"$TMP/vocab.py" <<'PY'
# Engine spec ↔ fixture vocabulary coherence, plus the claim that the RETIRED
# vocabulary is itself drift. One checker, run against the real surfaces (the
# dev-facing pins) and against fabricated copies (the controls), so a green run
# proves the checker can fail.
import ast, json, sys

engine, mode, path = sys.argv[1], sys.argv[2], sys.argv[3]
CANON = ["Qwen Large", "Qwen Dense", "Qwen Flash", "Local (gpu-ai)"]


def spec_model(src):
    tree = ast.parse(src)
    node = next((n for n in ast.walk(tree) if isinstance(n, ast.Assign)
                 and any(isinstance(t, ast.Name) and t.id == "CHECKLIST_SPEC" for t in n.targets)), None)
    out = {}
    if node is None:
        return out
    for d in ast.walk(node.value):
        if not isinstance(d, ast.Dict):
            continue
        for k, v in zip(d.keys, d.values):
            if not (isinstance(k, ast.Constant) and k.value == "Model(s)" and isinstance(v, ast.Dict)):
                continue
            for k2, v2 in zip(v.keys, v.values):
                if isinstance(k2, ast.Constant) and k2.value in ("items", "checked") and isinstance(v2, ast.List):
                    vals = [e.value for e in v2.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                    if len(vals) == len(v2.elts):
                        out[k2.value] = vals
    return out


if mode == "engine":
    s = spec_model(open(engine).read())
    if s.get("items") != CANON:
        print(f"engine Model(s) items {s.get('items')} != the Dense generation {CANON} — the "
              f"provisioning spec still carries the retired label (cf-106 C02 renames it; "
              f"the ids are untouched, only the label moves)"); sys.exit(1)
    if s.get("checked") != ["Qwen Dense"]:
        print(f"engine Model(s) checked {s.get('checked')} != ['Qwen Dense'] — the checklist "
              f"default flips with the vocabulary (OQ-7: BOTH defaults flip)"); sys.exit(1)
    sys.exit(0)
if mode == "fixture":
    got = (json.load(open(path)).get("checklist_extras") or {}).get("Model(s)", {})
    want = spec_model(open(engine).read())
    if got.get("items") != want.get("items") or sorted(got.get("checked", [])) != sorted(want.get("checked", [])):
        print(f"applied-state fixture Model(s) {got} disagrees with the engine spec {want} — one "
              f"side is still on the other vocabulary generation (AC5: the drift scan must report "
              f"zero actions on the applied state once both sides read Dense)"); sys.exit(1)
    sys.exit(0)
if mode == "drift":
    entries = [d for a in json.load(open(path)) if a.get("action") == "update_createcard_checklists"
               for d in (a.get("drift") or [])]
    if not any(e.startswith("Model(s)") for e in entries):
        print(f"the pre-cutover fixture (live board still reads the retired label) produced no "
              f"Model(s) drift entry — got {entries}. Retired vocabulary IS drift once the spec is "
              f"Dense (AC5); the transition alias governs card consumption, NOT the provisioning spec"); sys.exit(1)
    sys.exit(0)
print(f"harness: unknown vocab mode '{mode}'"); sys.exit(2)
PY
  # Controls FIRST: they must hold whatever dev does, and they prove the three
  # dev-facing pins below are not vacuous.
  python3 - "$ENGINE" "$TMP/engine-fabricated.py" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
i = text.index('"Model(s)"'); k = text.index("{", i)
depth, end = 0, k
for p in range(k, len(text)):
    if text[p] == "{": depth += 1
    elif text[p] == "}":
        depth -= 1
        if depth == 0:
            end = p; break
block = text[k:end + 1].replace('"Qwen 27b"', '"Qwen Dense"').replace('"checked": ["Qwen Flash"]', '"checked": ["Qwen Dense"]')
open(sys.argv[2], "w", encoding="utf-8").write(text[:k] + block + text[end + 1:])
PY
  python3 "$TMP/vocab.py" "$TMP/engine-fabricated.py" engine _ >/dev/null 2>&1 \
    || fail "t10 control: a fabricated Dense-generation engine spec FAILED the vocabulary pin — the pin is broken, not dev"
  python3 - "$FX_MATCH" "$TMP/fx-fifth-option.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["checklist_extras"]["Model(s)"]["items"] = d["checklist_extras"]["Model(s)"]["items"] + ["Qwen Flash Next"]
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"))
PY
  python3 "$TMP/vocab.py" "$TMP/engine-fabricated.py" fixture "$TMP/fx-fifth-option.json" >/dev/null 2>&1 \
    && fail "t10 control: a fixture carrying a FIFTH Model(s) option passed the coherence pin — the pin is vacuous (AC3's four-option closure must be enforced here)"
  ok "t10[C02 AC3 control]: the vocabulary checker fails a fabricated fifth option and accepts a fabricated Dense spec — the dev-facing pins below are non-vacuous"
  # (a) dev-facing: the engine spec must read the Dense generation.
  if ! python3 "$TMP/vocab.py" "$ENGINE" engine _ >/dev/null 2>&1; then
    python3 "$TMP/vocab.py" "$ENGINE" engine _ || fail "t10[C02 AC1/AC5]: the engine's Model(s) vocabulary/default pin failed (reason above; designed red until C02 flips the spec)"
  fi
  # (b) dev-facing: every applied-state fixture must agree with the engine spec.
  for fx in "$FX_MATCH" "$FX_CASE" "$FX_NOLABEL"; do
    if ! python3 "$TMP/vocab.py" "$ENGINE" fixture "$fx" >/dev/null 2>&1; then
      python3 "$TMP/vocab.py" "$ENGINE" fixture "$fx" || fail "t10[C02 AC5]: engine↔fixture Model(s) vocabulary coherence failed for $fx (reason above; designed red until C02 flips the spec — the fixtures are re-pinned to the Dense generation on purpose)"
    fi
  done
  # (c) dev-facing: the pre-cutover fixture must ALARM on the retired vocabulary.
  run_engine vocab-drift "$FX_DRIFT" || { cat "$TMP/vocab-drift.err" >&2; fail "t10[C02 AC5]: engine nonzero on the drifted schema-2 fixture (reason above)"; }
  if ! python3 "$TMP/vocab.py" _ drift "$TMP/vocab-drift.out" >/dev/null 2>&1; then
    python3 "$TMP/vocab.py" _ drift "$TMP/vocab-drift.out" || fail "t10[C02 AC5]: the drift alarm did not name Model(s) (reason above; designed red until the spec flips Dense — the retired label must be drift, not a tolerated state)"
  fi
  ok "t10[C02 AC1/AC3/AC5]: Model(s) vocabulary generation coherent across engine spec, applied-state fixtures and the drift alarm"
fi

printf 'PASS: cf-96 cutover artifact checks (%d ok)\n' "$checks"
