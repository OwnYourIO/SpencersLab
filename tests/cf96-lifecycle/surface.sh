#!/usr/bin/env bash
# boards skill — Lifecycle vocabulary (cf-124 re-cut: 13 items, the nine-stage
# blank default), Stage map, blank defaults, HITL alignment, transitions,
# cutover (orig. 2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C07).
#
# Pins chunks/C01.md "## Tests" over .rulesync/skills/boards/
# SKILL.md (+ regenerated mirror). The 13 names in card order are cf-124 C01
# Task 1's literal list — the batched round is folded (OQ6 user verbatim), so
# this suite MAY pin the exact list; a checklist renders card order, ORDER
# MATTERS, and the engine/artifact copy from the skill's landed text (never
# retype from memory — the chunk's own note).
#
# CROSS-TREE AUDIT (C07 T7, run by agent-test 2026-11-01 over tests/ for
#  `Pre Research|Post Research|Single Session|Lifecycle` pins):
#   - tests/agent-board-coord/rulesync-surface.sh c11/c18 — re-pinned with
#     this suite in the cf-124 C01 wave (same generation on both surfaces).
#   - tests/agent-board-coord/agents-md.sh c9 — re-pinned to the 13-item
#     AGENTS.md paragraph in the same wave (cf-124 C01 T4 moves it).
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
# Red posture (cf-124): t1/t2/t3/t6 DESIGNED RED until C01 dev lands the
# 13-item generation (the current skill still carries the 11-item list and
# the seven-stage default; verified at the cutover re-pin). t4/t5/t7 stay
# green unchanged — their surfaces survive the vocabulary move.
#
# Usage:
#   bash tests/cf96-lifecycle/surface.sh            # t1..t7
#   bash tests/cf96-lifecycle/surface.sh t2 t3      # defaults + HITL pair
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC=".rulesync/skills/boards/SKILL.md"
GEN=".opencode/skills/boards/SKILL.md"
ROOT="$(pwd)"

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

# The 13 canonical names, card order (cf-124 C01 Task 1's landed list, verbatim:
# the two gated leading stages FIRST, `Single Session` still in the OPT-IN pair's
# place, `Human in the Loop` LAST). This ONE list is the suite's whole vocabulary
# pin: t1 (bullet + Stage map), t3 (HITL mirror) and t6's framing all read it, so
# a vocabulary ruling that moves a name is a one-line re-pin here, never a hunt.
cat >"$TMP/parse.py" <<'PY'
import re, sys

STAGES = ["Session Rename", "Worktree Creation", "Exploration", "Agent Decides Research",
          "Planning", "Test Writing", "Chunk Development", "Chunk Review", "Final Review",
          "Deployment", "Single Session", "Follow-up cards created", "Human in the Loop"]

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

# --- t1: the 13 items in card order, checklist + Stage map (C01 AC1) -----------------
if want t1; then
  python3 - "$TMP/parse.py" "$SRC" <<'PY' || fail "t1[cf-124 C01 AC1]: the 13-item order pins failed (reason above)"
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
text = open(sys.argv[2]).read()
b = ns["bullet"](text, "Lifecycle")
names = ns["checklist_names"](b)
if names is None:
    print("t1: the Lifecycle bullet carries no `a` | `b` | … item run — C01 Task 1's 13 named items must render as the checklist line (designed red before C01 dev)"); sys.exit(1)
if names != ns["STAGES"]:
    print(f"t1: Lifecycle items are {names}, want the 13 in card order {ns['STAGES']} — order matters (card order), `Session Rename` FIRST, `Worktree Creation` second (OQ1 genuine gates), `Human in the Loop` LAST (C01 AC1)"); sys.exit(1)
rows = ns["stage_rows"](text)
if rows is None:
    print("t1: no Stage map table found"); sys.exit(1)
got = [r[0] for r in rows]
if got != ns["STAGES"]:
    print(f"t1: Stage map rows are {got} — the map must have EXACTLY these 13 rows in this order (AC2: one row per stage, the two new stages at the TOP)"); sys.exit(1)
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
  ok "t1[cf-124 C01 AC1]: Lifecycle checklist + Stage map carry EXACTLY the 13 items in card order, Session Rename first, Human in the Loop last; old row names gone from the map"
fi

# --- t2: the blank defaults (C01 T1 / AC3: the NINE-stage loop) ----------------------
# OQ3/D16: the two-member OPT-IN sentence (Deployment + Single Session) is the
# shipped law the owner kept — `Deployment` staying out of the default is
# pinned here as the banned member AND by t4's Deployment-row needle.
if want t2; then
  python3 - "$SRC" <<'PY' || fail "t2[cf-124 C01 AC3]: the blank-default pins failed (reason above)"
import re, sys
text = open(sys.argv[1]).read()
flat = re.sub(r"\s+", " ", text)
default = None
for m in re.finditer(r"Default when nothing is checked", flat):
    seg = flat[m.start():m.start() + 1200]
    if "Exploration" in seg and "Final Review" in seg:
        default = seg
        break
if default is None:
    print("t2: no 'Default when nothing is checked' passage naming Exploration…Final Review — the blank-Lifecycle default must be the NINE-stage list (D16/OQ2: Session Rename, Worktree Creation, Exploration, Agent Decides Research, Planning, Test Writing, Chunk Development, Chunk Review, Final Review; designed red before C01 dev)"); sys.exit(1)
order = ["Session Rename", "Worktree Creation", "Exploration", "Agent Decides Research",
         "Planning", "Test Writing", "Chunk Development", "Chunk Review", "Final Review"]
pos = [default.find(n) for n in order]
if -1 in pos or pos != sorted(pos):
    print(f"t2: the nine-stage default list is missing members or out of order in: {default[:400]}"); sys.exit(1)
# The enumeration span runs from the first default stage to the LAST default stage
# named after the eighth (never to a later 'Final Review' in the HITL sentence).
end = default.find("Final Review", pos[-1])
span = default[pos[0]:end + len("Final Review")]
for banned in ("Pre Research", "Post Research", "Single Session", "Deployment",
               "Follow-up cards created", "Human in the Loop"):
    if banned in span:
        print(f"t2: the default enumeration contains {banned!r} — the blank default is EXACTLY the nine: `Deployment` and `Single Session` stay OPT-IN (D16, the owner's own decline of card #124's ask) and the two trailing checklist names are stages, not defaults (plan Tests negative pin)"); sys.exit(1)
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
  ok "t2[cf-124 C01 AC3]: blank-Lifecycle = the NINE-stage default list (Session Rename + Worktree Creation in, Deployment/Single Session out, Agent Decides instead of Pre/Post); blank-HITL = Final Review; Single Session opt-in"
fi

# --- t3: HITL mirrors the same 13 names + the after-step stop (C01 AC1; was C07 T4 / AC3) --
if want t3; then
  python3 - "$SRC" "$TMP/parse.py" <<'PY' || fail "t3[cf-124 C01]: the HITL alignment pins failed (reason above)"
import re, sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[2]).read(), ns)
text = open(sys.argv[1]).read()
b = ns["bullet"](text, "Human in the Loop")
names = ns["checklist_names"](b)
if names != ns["STAGES"]:
    print(f"t3: HITL items are {names} — the batched round mirrors the SAME 13 Lifecycle names (cf-124 C01) (derived from the card's HITL-matches-Lifecycle + OQ6 keep-Single-Session; recorded in DECISIONS)"); sys.exit(1)
if not re.search(r"even if", b or "", re.I) or not re.search(r"AFTER", b or "", re.I):
    print("t3: the HITL bullet must keep the stop rule 'the checked item stops the run AFTER that step (even if a later stage is skipped)' — C07 T4"); sys.exit(1)
print("ok")
PY
  ok "t3[cf-124 C01]: HITL = the same 13 names in order + the AFTER-that-step-even-if-skipped stop rule"
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

# --- t6: the board-side cutover section + the cf-124 artifact (C01 T1/T3; was C07 T6 / AC5) ----
# The rules-import artifact is a RULES envelope — {"rules": [ one createCard
# rule ]} whose extraActions carry the checklist adds and the single
# `checkItem` ACTION (Model(s) -> Qwen Dense, D17: the artifact stays
# vocabulary + one check). It is NOT a wekan-board-snapshot: a `schema` key
# here would belong to a fixture, never to an import file. The cutover
# section cites the artifact by path; this leg follows the citation and
# checks the file itself at the strictness the cutover posture always had.
if want t6; then
  cat >"$TMP/t6_check.py" <<'PY'
# Cutover-section + artifact checker: argv = <boards-file> <root> [artifact
# override]. The same code runs against the real tree (dev-facing pin) and
# against the fabricated controls below (satisfiability + non-vacuity), so a
# green control proves the dev-facing pin can be satisfied by real work.
import json, os, re, sys

text = open(sys.argv[1]).read()
root = sys.argv[2]
override = sys.argv[3] if len(sys.argv) > 3 else None
sec = re.search(r"(?ms)^#{2,3}[^\n]*cutover[^\n]*\n(.*?)(?=^#{1,4} |\Z)", text)
if not sec:
    print("t6: no Board-side cutover section"); sys.exit(1)
s = re.sub(r"\s+", " ", sec.group(0))
for tok in ("13", "Lifecycle", "Human in the Loop", "board-rules-v12.77", "backup", "createCard"):
    if tok not in s:
        print(f"t6: the cutover section does not name {tok!r} — C01 T1: the section names the 13-item Lifecycle "
              f"+ matching 13-item HITL + the v12.77 rules-import artifact (C01 T3 produces it) + backup-first, "
              f"human-only apply (designed red before C01 dev)"); sys.exit(1)
m = re.search(r"([.\w/-]*board-rules-v12\.77[\w.-]*\.json)", s)
if not m:
    print("t6: no board-rules-v12.77 artifact path in the cutover section — the pointer must move off the "
          "v12.65-dense citation onto the 13-item generation (designed red before C01 dev)"); sys.exit(1)
if "/2026-11-cf-124-feat-checklist-locks-dependency/" not in m.group(1):
    print(f"t6: the cutover section cites {m.group(1)!r} — the current-generation artifact lives in the cf-124 "
          "plan folder; older citations stay as applied history (designed red before C01 dev)"); sys.exit(1)
if not re.search(r"never agent|human-only|human owned|human-owned", s, re.I):
    print("t6: the never-agent-executed posture must survive the update"); sys.exit(1)


def check_artifact(path):
    if not os.path.exists(path):
        return False, "the cited artifact does not exist on disk"
    art = json.load(open(path))
    if not (isinstance(art, dict) and isinstance(art.get("rules"), list)):
        return False, (f"the artifact is {type(art).__name__}, want the rules envelope with a `rules` list "
                       "(C01 T3: the v12.77 envelope {\"rules\": [one createCard rule]})")
    rules = art["rules"]
    if len(rules) != 1:
        return False, f"the envelope carries {len(rules)} rules, want exactly one createCard rule"
    rule = rules[0]
    if (rule.get("trigger") or {}).get("activityType") != "createCard":
        return False, "the one rule is not triggered on createCard (the artifact IS the standard-checklist rule)"
    if "schema" in art:
        return False, "the artifact carries a `schema` key — that is the SNAPSHOT shape; a rules-import file " \
                      "is the {rules: [...]} envelope, and an agent feeding a snapshot to Rules -> Import JSON fails"
    acts = [rule.get("action") or {}] + list(rule.get("extraActions") or [])
    checks = [a for a in acts if a.get("actionType") == "checkItem"]
    if len(checks) != 1:
        return False, (f"the rule carries {len(checks)} checkItem actions, want exactly one "
                       "(D17: the artifact is vocabulary + the single Model(s) -> Qwen Dense check; a second "
                       "would promise a pre-check the inert upstream verb could never deliver)")
    if not (checks[0].get("checklistName") == "Model(s)" and checks[0].get("checkItemName") == "Qwen Dense"):
        return False, f"the one checkItem is {checks[0]}, want Model(s) -> Qwen Dense (the shipped default check)"
    return True, ""


path = override if override else os.path.join(root, m.group(1))
good, why = check_artifact(path)
if not good:
    print(f"t6: {why}"); sys.exit(1)
print("ok")
PY
  # Controls FIRST (they hold whatever dev lands, and they prove the dev-facing
  # pin below is satisfiable and non-vacuous): a fabricated compliant
  # envelope+section must PASS the checker; the same fabricate with a SECOND
  # checkItem must be REJECTED (the plan's negative arm).
  python3 - "$SRC" "$TMP/t6-boards-compliant.md" "$TMP/t6-art-compliant.json" "$TMP/t6-art-two-check.json" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^#{2,3}[^\n]*cutover[^\n]*\n(.*?)(?=^#{1,4} |\Z)", text).group(0)
compliant = (
    "### Board-side cutover — human-owned, documented, never agent-executed\n\n"
    "Aligning the live AI-Dev board with the 13-item design is runbook work: replace the Lifecycle items with "
    "the 13 names, and the Human in the Loop items with the same 13 names, via the rules-import artifact "
    "`.agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/board-rules-v12.77-13item.json` — the "
    "createCard rule, vocabulary only, backup first, human-only apply; agents never mutate board checklists or "
    "rule extras.\n")
open(sys.argv[2], "w").write(text.replace(sec, compliant) if sec in text else text + "\n" + compliant)
rule = {"title": "Std checklists + defaults (v12.77 · 13 items)",
        "trigger": {"activityType": "createCard"},
        "action": {"actionType": "addChecklistWithItems", "checklistName": "Model(s)",
                   "checklistItems": "Qwen Large,Qwen Dense,Qwen Flash,Local (gpu-ai)"},
        "extraActions": [
            {"actionType": "checkItem", "checklistName": "Model(s)", "checkItemName": "Qwen Dense"},
            {"actionType": "addChecklistWithItems", "checklistName": "Services", "checklistItems": "x"},
            {"actionType": "addChecklistWithItems", "checklistName": "Type", "checklistItems": "feat"},
            {"actionType": "addChecklistWithItems", "checklistName": "Lifecycle", "checklistItems": "Session Rename"},
            {"actionType": "addChecklistWithItems", "checklistName": "Human in the Loop",
             "checklistItems": "Session Rename"}]}
json.dump({"rules": [rule]}, open(sys.argv[3], "w"))
two = json.loads(json.dumps(rule))
two["extraActions"].append({"actionType": "checkItem", "checklistName": "Type", "checkItemName": "feat"})
json.dump({"rules": [two]}, open(sys.argv[4], "w"))
PY
  python3 "$TMP/t6_check.py" "$TMP/t6-boards-compliant.md" /unused "$TMP/t6-art-compliant.json" >/dev/null 2>&1 \
    || { python3 "$TMP/t6_check.py" "$TMP/t6-boards-compliant.md" /unused "$TMP/t6-art-compliant.json"; fail "t6 control: a fabricated COMPLIANT cutover + v12.77 envelope failed its own pins — the dev-facing arm below is unsatisfiable (harness fault, report it)"; }
  if python3 "$TMP/t6_check.py" "$TMP/t6-boards-compliant.md" /unused "$TMP/t6-art-two-check.json" >/dev/null 2>&1; then
    fail "t6 control: an artifact with a SECOND checkItem PASSED — the single-check arm is inert (the plan's negative arm does not bite)"
  fi
  python3 "$TMP/t6_check.py" "$SRC" "$ROOT" \
    || fail "t6[cf-124 C01]: the cutover-section / artifact pins failed (reason above; designed red until C01 lands the 13-item cutover text and the cf-124 envelope)"
  ok "t6[cf-124 C01 T1/T3]: cutover names the 13-item generation and cites the v12.77 artifact inside the cf-124 folder — which exists as the one-createCard rules envelope with exactly one checkItem (Model(s) -> Qwen Dense), backup gate and human-only apply intact; controls: a compliant fabrication passes and a second checkItem is rejected"
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
