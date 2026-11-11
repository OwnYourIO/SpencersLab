#!/usr/bin/env bash
# board-checklist-backfill engine contract (2026/2026-11-cf-124-feat-checklist-
# locks-dependency, C07): the offline, additive-only, dry-run-by-default backfill
# that moves the ~90 live cards onto the cf-124 generation. The ENGINE CONTRACT
# below is fixed here because the assertions are the interface (the sibling
# checklist-cutover.sh posture): dev implements TO this suite.
#
# ENGINE CONTRACT (scripts/board-checklist-backfill.py, stdlib-only):
#   --board <export.json>   input, the shape of fixtures/board-backfill-sample.json
#                           (schema wekan-board-export/1; cards carry inline
#                           checklists {title, items: [{title, isFinished, sort}]}
#                           and custom_fields [{name, value}])
#   --out <plan.json>       plan document (pure JSON array); stdout carries the
#                           same plan; the plan is sorted by (card num, checklist
#                           title, item order) so it is diffable
#   --report <path>         the REPORT text (anomalies, per-leg counts)
#   --apply                 requires BOTH --yes and --backup-confirmed <ref>;
#                           without either, exit non-zero, write nothing
#   --include-list/--exclude-list   scope overrides; defaults: In Process
#                           swimlane excluded, Cancelled excluded, archived excluded
#   --card <id>             repeatable narrow-target escape hatch
#   --create-missing-lifecycle      default OFF (missing-Lifecycle stays report-only)
#   --priority-default N    default OFF; numeric writes ONLY where the field is
#                           unset/null; never overwrites; the leg's header names
#                           the owner-run bulk vs the agent's own per-card stamp
#   Every insert action: {card, card_num, checklist (id, or null when the
#   checklist itself is being created), checklist_title, action: add_item,
#   title, sort (explicit, strictly negative), reason}; a missing checklist is
#   planned as {action: create_checklist, checklist: null, checklist_title,
#   sort, reason} followed by its add_item actions (checklist null, items in
#   spec order). No action ever carries isFinished/tick state.
#   Vocabulary is IMPORTED from scripts/provision-board.py's CHECKLIST_SPEC
#   (spec_from_file_location on the dashed sibling name, resolved relative to
#   THIS script's directory — the copied-not-retyped law, D9/C07 dev note), so a
#   scratch copy pair re-points the plan (b4 proves the coupling).
#   The module emits NO HTTP delete anywhere and offers no delete/replace/
#   rebuild flag (#6816 cascade law). Dry run performs ZERO network calls.
#
# Pins chunks/C07.md "## Tests" b1..b7 + the runbook/pointer leg (b8, AC6).
# Red posture: DESIGNED RED for the whole suite until C07 dev lands the script
# and runbook; the existence gate names that reason, never a harness fault.
#
# Usage:
#   bash tests/wekan-board-provision/backfill.sh            # b1..b8
#   bash tests/wekan-board-provision/backfill.sh b3         # subset
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # scratch copies import siblings — keep the tree clean
cd "$(git rev-parse --show-toplevel)"

SCRIPT="scripts/board-checklist-backfill.py"
PROVISION="scripts/provision-board.py"
FIXTURE="tests/wekan-board-provision/fixtures/board-backfill-sample.json"
RUNBOOK="skills/wekan-board-provision/references/checklist-backfill-runbook.md"
SKILL="skills/wekan-board-provision/SKILL.md"
BOARDS=".rulesync/skills/boards/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/cf124-backfill-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8; do WANT["b$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^b[1-8]$ ]] || fail "unknown check id '$a' (expected b1..b8)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Fixture self-validation before blaming dev (sibling-suite law).
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FIXTURE" \
  || fail "harness: $FIXTURE is not valid JSON — the test data itself is broken (report, do not blame dev)"

# Existence gate: every arm below drives the real module; until C07 dev lands
# it the honest red is THIS message, not a python traceback.
gate_script() {
  [ -f "$SCRIPT" ] || fail "${1:-b}: $SCRIPT does not exist yet — C07 writes it (offline engine, dry-run default, additive-only); designed red before C07 dev, not a harness fault"
  [ -f "$PROVISION" ] || fail "${1:-b}: $PROVISION missing (harness fault — the vocabulary source)"
}

run_ro() { # run_ro <out-name> <args...> — read-only run, stdout+exit captured
  local name="$1"; shift
  WEKAN_TOKEN="" WEKAN_URL="http://127.0.0.1:9/" NO_PROXY="" \
    python3 "$SCRIPT" "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"
}

# --- b1: dry-run default is zero-network; the apply gates refuse ----------
if want b1; then
  gate_script b1
  # Poisoned env (AC1): a bogus WEKAN_URL and empty token — a plan run must
  # still exit 0, which is only possible if it never opened a connection.
  if ! run_ro dry --board "$FIXTURE"; then
    cat "$TMP/dry.err" >&2
    fail "b1[C07 AC1]: dry-run default exited non-zero with a poisoned env — the plan path must perform ZERO network calls (a bogus WEKAN_URL must be invisible to it)"
  fi
  python3 - "$TMP/dry.out" <<'PY' || fail "b1[C07 AC1]: the dry run printed no parseable plan (reason above)"
import json, sys
raw = open(sys.argv[1]).read()
start = raw.index("[")
plan = json.loads(raw[start:raw.rindex("]") + 1])
assert isinstance(plan, list) and plan, "the plan must be a non-empty JSON array"
print("plan actions:", len(plan))
PY
  for combo in "--apply" "--apply --yes" "--apply --backup-confirmed ref"; do
    rm -f "$TMP/should-not-exist.json"
    if python3 "$SCRIPT" --board "$FIXTURE" --out "$TMP/should-not-exist.json" $combo >/dev/null 2>&1; then
      fail "b1[C07 AC1]: '$combo' exited 0 — writing requires --apply AND --yes AND --backup-confirmed (the engine's own guard); one of them missing must refuse"
    fi
    [ -e "$TMP/should-not-exist.json" ] \
      && fail "b1[C07 AC1]: '$combo' wrote an --out plan file despite refusing — a refused apply writes NOTHING"
  done
  ok "b1[C07 AC1]: dry-run default plans offline (poisoned env invisible, exit 0, JSON plan on stdout) and every incomplete apply combination exits non-zero writing nothing"
fi

# --- b2: insert shape — explicit sorts, imported vocabulary, dedupe, no ticks --
if want b2; then
  gate_script b2
  run_ro plan2 --board "$FIXTURE" || { cat "$TMP/plan2.err" >&2; fail "b2: engine nonzero on the sample export (reason above)"; }
  if ! python3 - "$TMP/plan2.out" "$PROVISION" "$FIXTURE" <<'PY'
import json, re, sys, ast

raw = open(sys.argv[1]).read()
plan = json.loads(raw[raw.index("["):raw.rindex("]") + 1])
src = open(sys.argv[2]).read()
tree = ast.parse(src)
named = {}
for node in ast.walk(tree):
    if isinstance(node, ast.Assign):
        for t in node.targets:
            if isinstance(t, ast.Name) and isinstance(node.value, ast.List):
                vals = [e.value for e in node.value.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                if len(vals) == len(node.value.elts):
                    named[t.id] = vals
spec = {}
for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "CHECKLIST_SPEC" for t in node.targets):
        for d in ast.walk(node.value):
            if not isinstance(d, ast.Dict):
                continue
            for k, v in zip(d.keys, d.values):
                if not (isinstance(k, ast.Constant) and isinstance(v, ast.Dict)):
                    continue
                items = None
                for k2, v2 in zip(v.keys, v.values):
                    if not (isinstance(k2, ast.Constant) and k2.value == "items"):
                        continue
                    if isinstance(v2, ast.List):
                        vals = [e.value for e in v2.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                        if len(vals) == len(v2.elts):
                            items = vals
                    elif isinstance(v2, ast.Name):
                        items = named.get(v2.id)  # LIFECYCLE_ITEMS rides a name, not a literal
                if items is not None:
                    spec[k.value] = items
if "Lifecycle" not in spec or len(spec["Lifecycle"]) != 13:
    print("harness: CHECKLIST_SPEC not readable or not the 13-item generation — re-run after C01 lands")
    sys.exit(1)
fixture = json.load(open(sys.argv[3]))

def norm(t):
    return re.sub(r"\s+", " ", t).strip().lower()

# (a) every insert carries an explicit integer sort and a title from the spec;
# (b) no action anywhere carries tick state;
# (c) the C-variant card's case/whitespace-variant items yield NO action.
for a in plan:
    act = a.get("action", "")
    if act in ("add_item", "create_checklist"):
        s = a.get("sort")
        if not isinstance(s, int):
            print(f"action {a} lacks an explicit integer sort — new items land strictly negative so they append after the existing set without renumbering (dev note)"); sys.exit(1)
        if s >= 0:
            print(f"action {a} carries a non-negative sort — new inserts must be strictly negative (C07 Tasks 3a/AC2)"); sys.exit(1)
    if act == "add_item" and a.get("checklist_title") in spec:
        if norm(a.get("title", "")) not in {norm(t) for t in spec[a["checklist_title"]]}:
            print(f"action {a} targets a title outside the imported CHECKLIST_SPEC — the plan's target list must come from provision-board.py, byte-equal (AC3)"); sys.exit(1)
    if act == "create_checklist" and a.get("checklist_title") not in spec:
        print(f"create action for a checklist outside the spec: {a}"); sys.exit(1)
if any(("isFinished" in json.dumps(a)) or ('"finished"' in json.dumps(a)) for a in plan):
    print("a planned action carries isFinished/finished — the engine never touches tick state (C07 dev note: ticks are the human record)"); sys.exit(1)
variant_titles = {"session rename", "worktree creation"}
for a in plan:
    if a.get("card") == "C-variant" and a.get("checklist_title") == "Lifecycle" \
       and norm(a.get("title", "")) in variant_titles:
        print(f"C-variant already carries '{a['title']}' (case/whitespace variant) yet an insert was planned — same-title normalized match must be a no-op (AC2)"); sys.exit(1)
lc = [a for a in plan if a.get("card") == "C-legacy" and a.get("checklist_title") == "Lifecycle"]
if {norm(a.get("title", "")) for a in lc} != {norm(t) for t in spec["Lifecycle"]} - {"exploration", "agent decides research", "planning", "test writing", "chunk development", "chunk review", "final review", "deployment", "single session"}:
    print(f"C-legacy Lifecycle inserts are {[a.get('title') for a in lc]} — want exactly the spec names the legacy 11-item list lacks (the four cf-124 additions; the legacy Pre/Post Research items stay, never deleted)"); sys.exit(1)
print("ok")
PY
  then fail "b2[C07 AC2]: the insert-shape pin failed (reason above)"; fi
  ok "b2[C07 AC2]: every insert carries an explicit strictly-negative sort and an imported-spec title, case/whitespace variants dedupe to no-op, no action carries tick state, and the legacy card inserts exactly the four cf-124 additions"
fi

# --- b3: the never-delete law — source scan + help scan, control-proven --------
if want b3; then
  gate_script b3
  cat >"$TMP/nodelete.py" <<'PY'
# HTTP-delete sites + delete/replace/rebuild flags are the defect this engine
# may never carry (the #6816 cascade would destroy every tick on ~76 cards).
import re, sys
mode = sys.argv[2]
text = open(sys.argv[1]).read()
if mode == "source":
    hits = re.findall(r'"DELETE"|\'DELETE\'|\.delete\(|method\s*=\s*"DELETE"', text)
    if hits:
        print(f"HTTP delete sites in the module: {hits[:3]}"); sys.exit(1)
else:  # help
    if re.search(r"--[a-z-]*(delete|replace|rebuild)[a-z-]*", text, re.I):
        print(f"delete/replace/rebuild flag in --help: {re.findall(r'--[a-z-]*(?:delete|replace|rebuild)[a-z-]*', text, re.I)[:3]}"); sys.exit(1)
sys.exit(0)
PY
  python3 "$TMP/nodelete.py" "$SCRIPT" source \
    || fail "b3[C07 AC2]: the emitted script contains an HTTP delete call — C07's hard guarantee is add-only (a fabricated DELETE copy reddens this arm via the control below)"
  python3 "$SCRIPT" --help >"$TMP/help.out" 2>&1 \
    || fail "b3: --help exited non-zero (harness fault if this fires alone)"
  python3 "$TMP/nodelete.py" "$TMP/help.out" help \
    || fail "b3[C07 AC2]: --help lists a delete/replace/rebuild flag — the flag that enables the cascade must not EXIST"
  # Controls (the house negative-proof): a fabricated copy carrying a DELETE
  # request, and a fabricated copy whose help lists --force-replace, must both
  # redden their arms — proof the scans bite rather than vacuously pass.
  python3 - "$SCRIPT" "$TMP/b3-del.md" "$TMP/b3-help.md" <<'PY'
import sys
src = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(src + '\n_PROBE = lambda url: __import__("urllib.request", fromlist=["x"]).Request(url, method="DELETE")\n')
open(sys.argv[3], "w").write(src + "\nusage: board-checklist-backfill.py [--force-replace] ...\n")
PY
  python3 "$TMP/nodelete.py" "$TMP/b3-del.md" source >/dev/null 2>&1 \
    && fail "b3 control: a fabricated HTTP-delete copy PASSED the source scan — the never-delete arm is inert"
  python3 "$TMP/nodelete.py" "$TMP/b3-help.md" help >/dev/null 2>&1 \
    && fail "b3 control: a fabricated --force-replace help listing PASSED the flag scan — the flag guard is inert"
  ok "b3[C07 AC2]: the module contains no HTTP delete and --help offers no delete/replace/rebuild flag — control-proven: fabricated copies of both defects redden their scans"
fi

# --- b4: vocabulary coupling — the plan tracks an EDITED provision spec -------
if want b4; then
  gate_script b4
  S="$TMP/scratch"
  if mkdir -p "$S" && cp "$PROVISION" "$S/provision-board.py" && cp "$SCRIPT" "$S/board-checklist-backfill.py" 2>/dev/null \
     && python3 - "$S/provision-board.py" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
assert '"agent context",' in t, "fixture: Services literal moved"
open(p, "w").write(t.replace('"agent context",', '"agent context",\n            "scratch-extra-service",', 1))
PY
  then :
  else
    skip "b4: could not build the scratch script pair — documented SKIP, never a silent pass (report it)"
    b4_ran=0
  fi
  if [ "${b4_ran:-1}" = "1" ]; then
    WEKAN_TOKEN="" WEKAN_URL="http://127.0.0.1:9/" python3 "$S/board-checklist-backfill.py" --board "$FIXTURE" >"$TMP/b4.out" 2>"$TMP/b4.err" \
      || { cat "$TMP/b4.err" >&2; fail "b4[C07 AC3]: the scratch backfill run failed (reason above)"; }
    run_ro b4-real --board "$FIXTURE" || fail "b4: the real backfill run failed (reason above)"
    grep -q "scratch-extra-service" "$TMP/b4.out" \
      || fail "b4[C07 AC3]: a scratch CHECKLIST_SPEC with an extra Services item did NOT change the plan's target list — the vocabulary is not imported from provision-board.py resolved against THIS script's directory (C07 dev note: import, never paste)"
    grep -q "scratch-extra-service" "$TMP/b4-real.out" \
      && fail "b4 control inverted: the REAL spec already carries scratch-extra-service — the mutation leaked (harness fault)"
    ok "b4[C07 AC3]: editing CHECKLIST_SPEC in a scratch copy changes the plan (vocabulary imported from provision-board.py, not restated); the real generation is untouched by the probe"
  fi
fi

# --- b5: anomalies report, never repair; the create leg is default-off ---------
if want b5; then
  gate_script b5
  run_ro b5 --board "$FIXTURE" --report "$TMP/b5-report.txt" \
    || { cat "$TMP/b5.err" >&2; fail "b5: engine nonzero on the sample export (reason above)"; }
  [ -s "$TMP/b5-report.txt" ] || fail "b5[C07 AC4]: --report wrote nothing — anomalies (duplicated sets, missing Lifecycle) must be REPORTED, not repaired (C07 Tasks 3d/3e)"
  grep -q "C-dup" "$TMP/b5-report.txt" || fail "b5[C07 AC4]: the duplicated-set card C-dup (#65/#66 class) is not in the report with its id"
  grep -q "C-nolifecycle" "$TMP/b5-report.txt" || fail "b5[C07 AC4]: the missing-Lifecycle card C-nolifecycle (#57/#71 class) is not in the report with its id"
  if ! python3 - "$TMP/b5.out" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
plan = json.loads(raw[raw.index("["):raw.rindex("]") + 1])
bad = [a for a in plan if a.get("card") in ("C-dup", "C-nolifecycle")]
print(f"anomalous write actions: {bad}" if bad else "ok")
sys.exit(1 if bad else 0)
PY
  then fail "b5[C07 AC4]: an anomaly card received a write action despite --create-missing-lifecycle being OFF — report-only is the default (the anomaly call stays human)"; fi
  run_ro b5-flag --board "$FIXTURE" --create-missing-lifecycle --report "$TMP/b5b-report.txt" \
    || { cat "$TMP/b5-flag.err" >&2; fail "b5: engine nonzero with --create-missing-lifecycle (reason above)"; }
  python3 - "$TMP/b5-flag.out" <<'PY' || fail "b5[C07 AC4]: --create-missing-lifecycle produced no create action for C-nolifecycle — the default-off is assumed, not proved (reason above)"
import json, sys
raw = open(sys.argv[1]).read()
plan = json.loads(raw[raw.index("["):raw.rindex("]") + 1])
creates = [a for a in plan if a.get("card") == "C-nolifecycle" and a.get("action") == "create_checklist" and a.get("checklist_title") == "Lifecycle"]
sys.exit(0 if creates else 1)
PY
  if ! python3 - "$TMP/b5-flag.out" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
plan = json.loads(raw[raw.index("["):raw.rindex("]") + 1])
sys.exit(0 if not [a for a in plan if a.get("card") == "C-dup"] else 1)
PY
  then fail "b5[C07 AC4]: with the flag ON, the DUPLICATED-set card also received writes — the flag covers the missing-Lifecycle leg only; duplicates stay report-only"; fi
  ok "b5[C07 AC4]: duplicated-set and missing-Lifecycle cards are reported with ids and receive zero writes by default; the opt-in flag turns the missing-Lifecycle card into a create action (and only that card)"
fi

# --- b6: the Priority leg — default-off, unset-only, numeric, boundary header --
if want b6; then
  gate_script b6
  run_ro b6-off --board "$FIXTURE" || fail "b6: engine nonzero (reason above)"
  python3 - "$TMP/b6-off.out" <<'PY' || fail "b6[C07 AC5]: Priority actions appear with the leg default-OFF — the flag is opt-in (bulk mutation is owner-run by OQ6; red posture below)"
import json, sys
raw = open(sys.argv[1]).read()
plan = json.loads(raw[raw.index("["):raw.rindex("]") + 1])
sys.exit(1 if [a for a in plan if "priority" in json.dumps(a).lower() and a.get("action") != "report"] else 0)
PY
  WEKAN_TOKEN="" WEKAN_URL="http://127.0.0.1:9/" python3 "$SCRIPT" --board "$FIXTURE" --priority-default 5 \
    --out "$TMP/b6-plan.json" >"$TMP/b6-on.out" 2>"$TMP/b6-on.err" \
    || { cat "$TMP/b6-on.err" >&2; fail "b6[C07 AC5]: the --priority-default run exited non-zero (reason above)"; }
  python3 - "$TMP/b6-plan.json" "$TMP/b6-on.out" "$TMP/b6-on.err" <<'PY' || fail "b6[C07 AC5]: the Priority leg failed its pins (reason above)"
import json, sys
plan = json.loads(open(sys.argv[1]).read())
prio = [a for a in plan if "priority" in json.dumps(a).lower() and a.get("action") != "report"]
assert prio, "with --priority-default 5 not one Priority action was planned"
vals = [a.get("value") for a in prio]
assert all(isinstance(v, int) and v == 5 for v in vals), f"Priority writes must be the NUMBER 5 (never \"5\"): {vals}"
assert not any(a.get("card") == "C-prio-set" for a in prio), "C-prio-set carries an explicit Priority \"9\" — the leg must skip any card with a value, never overwrite (D20/OQ7 idempotence)"
assert any(a.get("card") == "C-legacy" for a in prio), "the unset-Priority in-scope card got no action"
head = (open(sys.argv[2]).read() + open(sys.argv[3]).read()).lower()
for needle in ("owner", "bulk", "own", "stamp"):
    if needle not in head:
        print(f"the leg's emitted header lacks {needle!r} — it must restate that this is the OWNER-run BULK path while an agent's OWN per-card stamp is a separate permission (OQ6/OQ7, D19/D20)")
        raise SystemExit(1)
print("ok")
PY
  ok "b6[C07 AC5]: the Priority leg is default-off; when enabled it plans numeric-5 writes for UNSET in-scope cards only, skips the card with an explicit value, and its emitted header names both permission boundaries (owner-run bulk vs the agent's own stamp)"
fi

# --- b7: determinism — same export, byte-identical plans -----------------------
if want b7; then
  gate_script b7
  run_ro b7a --board "$FIXTURE" || fail "b7: run 1 failed"
  run_ro b7b --board "$FIXTURE" || fail "b7: run 2 failed"
  cmp "$TMP/b7a.out" "$TMP/b7b.out" \
    || fail "b7[C07 Tasks 1]: two runs on one export differ — the plan is sorted by card number with stable ordering (diffable by contract); see the diff above"
  ok "b7[C07 Tasks 1]: two dry runs on the same export produce byte-identical plans (sorted, stable, diffable)"
fi

# --- b8: the runbook + the two pointer sentences (AC6) -------------------------
if want b8; then
  [ -f "$RUNBOOK" ] \
    || fail "b8[C07 AC6]: $RUNBOOK does not exist yet — C07 ships the owner-facing runbook (pre-flight, dry-run, read-back, anomaly triage, the Priority boundary, the no-upstream-action line); designed red before C07 dev"
  python3 - "$RUNBOOK" <<'PY' || fail "b8[C07 AC6]: the runbook token set is incomplete (reason above)"
import re, sys
t = open(sys.argv[1]).read()
flat = re.sub(r"\s+", " ", t).lower()
need = {
    "WITH_API pre-flight": "with_api",
    "token env name (never a value)": "wekan_token",
    "board backup step": "backup",
    "dry-run command": "--dry-run|--board",
    "rule drift is expected pre-import": "drift",
    "the apply command (all three flags)": "--yes",
    "--backup-confirmed guard": "--backup-confirmed",
    "read-back spot check": "read.back|read back",
    "anomaly triage cards": "#57|#71|#65|#66",
    "Priority section: bulk = owner-run": "bulk",
    "Priority section: the agent's own stamp": "stamp",
}
missing = []
for why, rx in need.items():
    if not re.search(rx, flat):
        missing.append(why)
if re.search(r"file an issue|open an issue|draft an? upstream|upstream (issue|pr)", flat):
    missing.append("an upstream-filing ask survives — D18 closed it as a deliberate non-action")
if missing:
    print("runbook lacks: " + "; ".join(missing)); sys.exit(1)
print("ok")
PY
  # The two one-sentence pointers C07 adds (Tasks 3, 4) — the skill's and the
  # boards cutover's. Both are surfaces other arms read, so they are pinned
  # narrowly here rather than by touching those suites.
  grep -qiE 'backfill' "$SKILL" \
    || fail "b8[C07 Tasks 3]: the provision skill carries no pointer bullet to the backfill engine + runbook (the apply leg is human-run, the engine dry-run-default and additive)"
  python3 - "$SKILL" <<'PY' || fail "b8[C07 Tasks 3]: the provision-skill pointer does not state the human-run/owner-run apply leg (reason above)"
import re, sys
t = re.sub(r"\s+", " ", open(sys.argv[1]).read())
# A ±300 window around any 'backfill' mention (filenames carry dots, so no
# sentence-boundary regex can be trusted here — the co-location is the claim).
hit = False
for m in re.finditer(r"backfill", t, re.I):
    seg = t[max(0, m.start() - 300):m.end() + 300]
    if re.search(r"human-run|owner-run|owner runs|human runs|owner-executed", seg, re.I):
        hit = True
        break
sys.exit(0 if hit else 1)
PY
  python3 - "$BOARDS" <<'PY' || fail "b8[C07 Tasks 4]: the boards human-owned cutover section does not yet name the owner-run, dry-run-default, additive backfill (red until C07's one sentence lands)"
import re, sys
t = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^#{2,3}[^\n]*cutover[^\n]*\n(.*?)(?=^#{1,4} |\Z)", t)
if not sec:
    print("no Board-side cutover section"); sys.exit(1)
s = re.sub(r"\s+", " ", sec.group(0))
sys.exit(0 if re.search(r"(?i)backfill", s) and re.search(r"(?i)owner", s) and re.search(r"(?i)dry.?run", s) else 1)
PY
  ok "b8[C07 AC6 + Tasks 3/4]: the runbook exists with the full token set (WITH_API, WEKAN_TOKEN env, backup, dry-run, expected rule drift, the three-flag apply, read-back, the anomaly cards, the two-permission Priority boundary, and no upstream-filing ask per D18), the provision skill carries its human-run pointer bullet, and the boards cutover section names the owner-run additive backfill"
fi

printf 'PASS: board-checklist-backfill engine checks (%d ok)\n' "$checks"
