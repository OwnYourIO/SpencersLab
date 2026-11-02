#!/usr/bin/env bash
# boards skill — Lifecycle redesign: 11 items (10 stages + Single Session
# kept LAST), Stage map, blank defaults, HITL alignment, transitions, cutover
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C07).
#
# Pins chunks/C07.md "## Tests" + AC1-AC6 over .rulesync/skills/boards/
# SKILL.md (+ regenerated mirror). The 11 names in card order are the plan's
# T1 literal list — the batched round is folded (OQ6 user verbatim), so this
# suite MAY pin the exact list; a checklist renders card order, ORDER
# MATTERS, and C08's engine/artifact copy from C07's landed text (never
# retype from memory — the chunk's own note).
#
# CROSS-TREE AUDIT (C07 T7, run by agent-test 2026-11-01 over tests/ for
 # `Pre Research|Post Research|Single Session|Lifecycle` pins):
#   - tests/agent-board-coord/rulesync-surface.sh c11 — pins the OLD eight-
#     item Lifecycle window + the nothing-checked default + the old HITL
#     list + a stage_tokens dict keyed on the old row names, over the
#     GENERATED mirror → MUST re-pin in C07's commit (mirror of this design).
#   - tests/agent-board-coord/agents-md.sh c9 — pins the Lifecycle WORDING
#     (name + checked-stages-only), not the item list → stage-agnostic,
#     stays green.
#   - tests/agent-dev-deploy/surface.sh — cites `Deploy`/`Lifecycle`
#     wording; the rename to `Deployment` keeps every `Deploy` needle as a
#     substring → verify at C07 landing, no re-pin expected.
#   - tests/coord-inwork/ + tests/provider-loops/ — greps found NO old-
#     vocabulary pins (their known reds are the pre-existing warm-location
#     family: gate t17 / coord-inwork i4 / session-origin s4 / kickoff-
#     branch m4) → nothing to re-pin here.
#   - tests/opencode/question-notify.test.ts + permission-ask-notify.test.ts
#     — "lifecycle" = OpenCode session events, vocabulary false positive.
#   - tests/wekan-board-provision/fixtures/* + tests/cf90-ledger/readback-
#     runbook.md — name the CHECKLIST (word `Lifecycle`) only → survives.
#
# Red posture: DESIGNED RED until C07 dev lands (the current skill still
# carries the 8-item list + Plan-defaults; verified at authoring). The two
# negatives that are green today — no hardcoded list ids, mirror parity —
# HOLD.
#
# Usage:
#   bash tests/cf96-lifecycle/surface.sh            # t1..t7
#   bash tests/cf96-lifecycle/surface.sh t2 t3      # defaults + HITL pair
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC=".rulesync/skills/boards/SKILL.md"
GEN=".opencode/skills/boards/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-7]$ ]] || fail "unknown check id '$a' (expected t1..t7)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/cf96-lifecycle-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# The 11 canonical names, card order (C07 T1 verbatim; Single Session LAST).
cat >"$TMP/parse.py" <<'PY'
import re, sys

STAGES = ["Exploration", "Agent Decides Research", "Pre Research", "Planning",
          "Post Research", "Test Writing", "Chunk Development", "Chunk Review",
          "Final Review", "Deployment", "Single Session"]

def bullet(text, label):
    """The `**label**` bullet text, wrapped lines included, up to the next
    top-level bullet or heading."""
    m = re.search(rf"(?ms)^(\s*)- \*\*{re.escape(label)}\*\*(.*?)(?=^\s*-\s+\*\*|^#|\Z)", text)
    return m.group(0) if m else None

def checklist_names(b):
    """The pipe-separated backticked run is the item list; take the FIRST
    such run of >=3 names (the description prose follows)."""
    if not b:
        return None
    for m in re.finditer(r"(?:`([^`]+)`\s*\|?\s*){3,}", b):
        seg = m.group(0)
        names = re.findall(r"`([^`]+)`", seg)
        if names:
            return names
    return None

def stage_rows(text):
    m = re.search(r"(?ms)^## Stage map.*?(?=^#{1,2} |\Z)", text)
    if not m:
        return None
    rows = []
    for line in m.group(0).splitlines():
        r = re.match(r"^\|\s*`([^`]+)`\s*\|(.*)$", line)
        if r:
            rows.append((r.group(1), r.group(2)))
    return rows
PY

# --- t1: the 11 items in card order, checklist + Stage map (C07 AC1) -----------------
if want t1; then
  python3 - "$TMP/parse.py" "$SRC" <<'PY' || fail "t1[C07 AC1]: the 11-item order pins failed (reason above)"
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
text = open(sys.argv[2]).read()
b = ns["bullet"](text, "Lifecycle")
names = ns["checklist_names"](b)
if names is None:
    print("t1: the Lifecycle bullet carries no `a` | `b` | … item run — C07 T1's 11 named items must render as the checklist line (designed red before C07 dev)"); sys.exit(1)
if names != ns["STAGES"]:
    print(f"t1: Lifecycle items are {names}, want the 11 in card order {ns['STAGES']} — order matters (card order), Single Session LAST (OQ6 user ruling)"); sys.exit(1)
rows = ns["stage_rows"](text)
if rows is None:
    print("t1: no Stage map table found"); sys.exit(1)
got = [r[0] for r in rows]
if got != ns["STAGES"]:
    print(f"t1: Stage map rows are {got} — the map must have EXACTLY these 11 rows in this order (AC1)"); sys.exit(1)
print("ok")
PY
  # old 8-item vocabulary survives ONLY inside the transition/cutover text:
  # no old row name as a Stage-map table row.
  python3 - "$SRC" <<'PY' || fail "t1[C07 AC1 negative]: the old 8-item vocabulary leaked outside the transition text (reason above)"
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?ms)^## Stage map.*?(?=^#{1,2} |\Z)", text)
if m:
    for badrow in ("Plan", "Test", "Code", "Review", "Deploy"):
        if re.search(rf"^\|\s*`{badrow}`\s*\|", m.group(0), re.M):
            print(f"stage map still carries a bare `{badrow}` row — the new map names are the rows; legacy names may live only in the transition/cutover prose"); sys.exit(1)
print("ok")
PY
  ok "t1[C07 AC1]: Lifecycle checklist + Stage map carry EXACTLY the 11 items in card order, Single Session last; old row names gone from the map"
fi

# --- t2: the blank defaults (C07 T3 / AC2) --------------------------------------------
if want t2; then
  python3 - "$SRC" <<'PY' || fail "t2[C07 AC2]: the blank-default pins failed (reason above)"
import re, sys
text = open(sys.argv[1]).read()
flat = re.sub(r"\s+", " ", text)
default = None
for m in re.finditer(r"Default when nothing is checked", flat):
    seg = flat[m.start():m.start() + 900]
    if "Exploration" in seg and "Final Review" in seg:
        default = seg
        break
if default is None:
    print("t2: no 'Default when nothing is checked' passage naming Exploration…Final Review — the blank-Lifecycle default must be the seven-stage list (C07 T3: Exploration, Agent Decides Research, Planning, Test Writing, Chunk Development, Chunk Review, Final Review; designed red before C07 dev)"); sys.exit(1)
order = ["Exploration", "Agent Decides Research", "Planning", "Test Writing", "Chunk Development", "Chunk Review", "Final Review"]
pos = [default.find(n) for n in order]
if -1 in pos or pos != sorted(pos):
    print(f"t2: the default list is missing members or out of order in: {default[:400]}"); sys.exit(1)
span = default[min(pos):default.rfind("Final Review") + len("Final Review")]
for banned in ("Pre Research", "Post Research", "Single Session", "Deployment"):
    if banned in span:
        print(f"t2: the default enumeration contains {banned!r} — the blank default EXCLUDES Deployment AND Single Session, and Agent Decides Research REPLACES Pre/Post (plan Tests negative pin)"); sys.exit(1)
if not re.search(r"Agent Decides Research.{0,120}(instead|rather than|replaces|not Pre|excluding Pre|— no Pre|without Pre|Pre Research)", default):
    print("t2: the default passage must state that Agent Decides Research stands in for Pre/Post Research (OQ14/blank-default wording)"); sys.exit(1)
if not re.search(r"opt-?in", flat, re.I):
    print("t2: Single Session must be documented as OPT-IN (never in the blank default)"); sys.exit(1)
if not re.search(r"[Dd]efault[^\n]{0,160}Final Review|Final Review[^\n]{0,160}default", text):
    print("t2: the blank-HITL default must be Final Review (replacing today's Plan default — C07 T3; designed red before C07 dev)"); sys.exit(1)
if re.search(r"Default: `Plan`", text):
    print("t2: the old HITL default sentence 'Default: `Plan`' survives — the rewrite replaces it with Final Review"); sys.exit(1)
print("ok")
PY
  ok "t2[C07 AC2]: blank-Lifecycle = the 7-stage default list (Exploration in, Deployment/Single Session out, Agent Decides instead of Pre/Post); blank-HITL = Final Review; Single Session opt-in"
fi

# --- t3: HITL mirrors the same 11 names + the after-step stop (C07 T4 / AC3) ----------
if want t3; then
  python3 - "$SRC" "$TMP/parse.py" <<'PY' || fail "t3[C07 AC3]: the HITL alignment pins failed (reason above)"
import re, sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[2]).read(), ns)
text = open(sys.argv[1]).read()
b = ns["bullet"](text, "Human in the Loop")
names = ns["checklist_names"](b)
if names != ns["STAGES"]:
    print(f"t3: HITL items are {names} — the batched round mirrors the SAME 11 Lifecycle names (derived from the card's HITL-matches-Lifecycle + OQ6 keep-Single-Session; recorded in DECISIONS)"); sys.exit(1)
if not re.search(r"even if", b or "", re.I) or not re.search(r"AFTER", b or "", re.I):
    print("t3: the HITL bullet must keep the stop rule 'the checked item stops the run AFTER that step (even if a later stage is skipped)' — C07 T4"); sys.exit(1)
print("ok")
PY
  ok "t3[C07 AC3]: HITL = the same 11 names in order + the AFTER-that-step-even-if-skipped stop rule"
fi

# --- t4: row semantics — Single Session, Chunk Review, Chunk Development (C07 T2 / AC4) --
if want t4; then
  python3 - "$SRC" "$TMP/parse.py" <<'PY' || fail "t4[C07 AC4]: the Stage-map row semantics pins failed (reason above)"
import re, sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[2]).read(), ns)
rows = dict(ns["stage_rows"](open(sys.argv[1]).read()) or [])
def need(stage, *alts):
    body = rows.get(stage, "")
    for a in alts:
        if not re.search(a, body, re.I):
            print(f"t4: the `{stage}` row lacks /{a}/ (C07 T2 semantics — designed red before C07 dev)"); sys.exit(1)
need("Single Session", "Test Writing", "Chunk Development", "Chunk Review", "ONE session", "final", "other checked stages|checked stages still")
need("Chunk Review", "skipped", "unchecked|not checked|never silently absorbed")
need("Chunk Development", "Chunk Review", "dev-only|no review", "commands_run|command evidence|validations-green|validations green")
need("Exploration", "agent-explore", "EXPLORE.md")
need("Agent Decides Research", "coord|pipeline-role-coord", "Research: Parallel|per-ask|per ask|serial")
need("Deployment", "push|pipeline-push-pr")
print("ok")
PY
  grep -qE '`Final Review`.*planning-tier|planning-tier.*Final Review|Final Review[^\n]*planning tier' "$SRC" \
    || fail "t4[C07 T2]: the Final Review row must keep the planning-tier model note (today's `Review` row semantics carry over)"
  ok "t4[C07 AC4]: Single Session preserved-semantics row, OQ15 checked-stages-only on the two chunk rows, Exploration/ADR/Deployment rows pinned"
fi

# --- t5: the legacy-Research transition + legacy HITL mapping (C07 T5) -----------------
if want t5; then
  python3 - "$SRC" <<'PY' || fail "t5[C07 AC4]: the transition-rule pins failed (reason above)"
import re, sys
text = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^#{2,3}[^\n]*[Tt]ransition[^\n]*\n(.*?)(?=^#{1,4} |\Z)", text)
if not sec:
    print("t5: no Transition section (C07 T5 rewrites the existing one — designed red before C07 dev)"); sys.exit(1)
s = sec.group(0)
flat = re.sub(r"\s+", " ", s)
for pair in (("Before Planning", "Pre Research"), ("After Planning", "Post Research"),
             ("Agent Decides", "Agent Decides Research")):
    if pair[0] not in flat or pair[1] not in flat:
        print(f"t5: the transition maps {pair[0]} → {pair[1]} in the NEW names — pair not co-located"); sys.exit(1)
if not re.search(r"time[sd]? (the )?research|only time|never gate", flat, re.I):
    print("t5: the timing-only law (checked items time research, never gate stages) must survive the rewrite"); sys.exit(1)
if not re.search(r"stage list.{0,80}(default|standard)|default.{0,80}(new names|standard)", flat, re.I):
    print("t5: such a card's stage list = the standard default loop IN THE NEW NAMES (C07 T5)"); sys.exit(1)
for pair in (("Plan", "Planning"), ("PR", "Deployment"), ("Research", "Pre Research")):
    if not re.search(re.escape(pair[0]) + r"\s*(→|->|maps? to\b|becomes\b|rides\b)[^\n]{0,40}" + re.escape(pair[1]), s):
        print(f"t5: the legacy-HITL mapping {pair[0]}→{pair[1]} is missing (best-guess mapping stands per DECISIONS)"); sys.exit(1)
# NO Single-Session transition rule (OQ6 keeps the item; nothing migrates)
for line in s.splitlines():
    if "Single Session" in line and re.search(r"transition", line, re.I) \
       and not re.search(r"no |not |never|needed|kept|stays|removed rule", line, re.I):
        print(f"t5: an affirmative Single-Session transition rule appeared — the ruling says none is needed: {line.strip()[:100]}"); sys.exit(1)
if not re.search(r"[Nn]o Single-[Ss]ession transition|never needed|not needed", flat):
    print("t5: the section should state positively that NO Single-Session transition rule is needed (v1 8-item cutover never landed; cards carry the legacy Research checklist)"); sys.exit(1)
print("ok")
PY
  ok "t5[C07]: transition rule rewritten in the new names (timing-only), legacy HITL mapping pinned, no Single-Session transition rule"
fi

# --- t6: the board-side cutover section names the 11+11+v2 artifact (C07 T6 / AC5) -----
if want t6; then
  python3 - "$SRC" <<'PY' || fail "t6[C07 AC5]: the cutover-section pins failed (reason above)"
import re, sys
text = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^#{2,3}[^\n]*cutover[^\n]*\n(.*?)(?=^#{1,4} |\Z)", text)
if not sec:
    print("t6: no Board-side cutover section"); sys.exit(1)
s = re.sub(r"\s+", " ", sec.group(0))
for tok in ("11", "Lifecycle", "Human in the Loop", "board-rules-v12.65.json", "backup", "createCard"):
    if tok not in s:
        print(f"t6: the cutover section does not name {tok!r} — T6: 11-item Lifecycle + matching 11-item HITL + the v2 rules-import artifact (C08 produces it) + backup-first, human-only apply (designed red before C07 dev)"); sys.exit(1)
if not re.search(r"never agent|human-only|human owned|human-owned", s, re.I):
    print("t6: the never-agent-executed posture must survive the update"); sys.exit(1)
print("ok")
PY
  ok "t6[C07 AC5]: cutover names the 11+11 checklists, the v2 artifact path, the backup gate, human-only apply"
fi

# --- t7: mirror regenerated (C07 AC6) ---------------------------------------------------
if want t7; then
  python3 - "$SRC" "$GEN" <<'PY' || fail "t7[C07 AC6]: source↔mirror body equality failed (reason above)"
import re, sys
def body(path):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path).read(), re.S)
    assert m, f"{path}: no frontmatter"
    return re.sub(r"\s+", " ", m.group(2)).strip()
if body(sys.argv[1]) != body(sys.argv[2]):
    print("the generated .opencode/skills/boards mirror's body differs from the source — rulesync generate output commits WITH the source (never hand-edit)")
    sys.exit(1)
print("ok")
PY
  ok "t7[C07 AC6]: boards mirror equals the rewritten source (whitespace-normalized)"
fi

printf 'PASS: cf-96 Lifecycle-redesign checks (%d ok)\n' "$checks"
