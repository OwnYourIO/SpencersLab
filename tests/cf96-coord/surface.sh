#!/usr/bin/env bash
# coord+plan contract deltas — per-ask research, agent-explore launchable,
# AD-71 chunk guidance, OQ15 Chunk-Review-skipped done-gate carve-out
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C06).
#
# Pins chunks/C06.md "## Tests": windowed pins over
# .rulesync/skills/pipeline-role-coord/SKILL.md (T1, T2, T3b, T5) and
# .rulesync/skills/pipeline-role-plan/SKILL.md (T3a), plus the generated
# mirror bodies, and the negative pins the chunk demands: no unconditional
# parallel-research wording, and no done-gate text that drops the
# command-evidence requirement in the review-skipped shape.
#
# Single-authority rule (C06 Notes for dev): the coord skill must only CITE
# the boards Stage map for the Exploration row — t2 pins the citation verb,
# never a restatement; the stage-row text itself lands in C07's file.
#
# AC trace: t1[C06 AC1 — per-ask sessions, shared RESEARCH.md, serial
# default, Research: Parallel case-insensitive label exception, label
# human-owned; boards research-only loop untouched] t2[AC2 — "may only
# launch" names agent-explore; stage-gate paragraph cites the Exploration
# row] t3[AC3 — plan skill fewer-cohesive-chunks guidance; coord one-at-a-
# time-explicit line; wave-parallel DEV DEFERRED entry in DECISIONS] t4[AC4 —
# step 5b + step 7 OQ15 carve-out: skip when unchecked, done = dev DONE +
# commands_run evidence; checked shape unchanged] t5[AC4 negatives — no
# unconditional parallel-launch wording; no wording waiving validations in
# the review-skipped shape] t6[AC5 — mirrors regenerated: body equality].
#
# Red posture: t1–t4 DESIGNED RED at authoring 2026-11-01 — verified: the
# Research section is singular today ("launch agent-research with the
# scope"), the may-only-launch list has no agent-explore, plan's grouping
# rule still ends at the "up to 5 S tasks" line, steps 5b/7 know nothing of
# a skipped review. t3's DEFERRED arm is GREEN now (DECISIONS.md already
# carries the wave-parallel deferral — the plan folded it) and HOLD. t5
# negatives are GREEN now, HOLD. t6 mirror parity GREEN now, HOLD.
#
# Usage:
#   bash tests/cf96-coord/surface.sh            # t1..t6
#   bash tests/cf96-coord/surface.sh t4 t5      # the OQ15 pair
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

COORD_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
COORD_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
PLAN_SRC=".rulesync/skills/pipeline-role-plan/SKILL.md"
PLAN_GEN=".opencode/skills/pipeline-role-plan/SKILL.md"
BOARDS_SRC=".rulesync/skills/boards/SKILL.md"
DECISIONS=".agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/DECISIONS.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-6]$ ]] || fail "unknown check id '$a' (expected t1..t6)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/cf96-coord-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# Section + OR-group window helpers (same engine as tests/boards-deps).
cat >"$TMP/sec.py" <<'PY'
import re, sys

def section(path, heading_pat):
    text = open(path).read()
    m = re.search(rf"(?ims)^#{{1,4}}[^\n]*{heading_pat}[^\n]*\n(.*?)(?=^#{1,4} |\Z)", text)
    return m.group(0) if m else None

def window(hay, groups, span):
    pts = []
    for gi, alts in enumerate(groups):
        found = False
        for alt in alts:
            for m in re.finditer(re.escape(alt), hay, re.I):
                pts.append((m.start(), gi)); found = True
        if not found:
            return None, [a for a in alts]
    pts.sort()
    need = len(groups)
    cnt, have, best, left = {}, 0, None, 0
    for right, (pos, g) in enumerate(pts):
        if cnt.get(g, 0) == 0:
            have += 1
        cnt[g] = cnt.get(g, 0) + 1
        while have == need:
            s = pos - pts[left][0]
            if best is None or s < best:
                best = s
            lg = pts[left][1]
            cnt[lg] -= 1
            if cnt[lg] == 0:
                have -= 1
            left += 1
    if best is not None and best <= span:
        return best, None
    return best, "gap too wide"
PY

win() { # win <tlabel> <file> <heading> <span> <group>...
  local label="$1" file="$2" heading="$3" span="$4"; shift 4
  python3 - "$TMP/sec.py" "$file" "$heading" "$span" "$@" <<'PY' || fail "$label: text pin failed (reason above)"
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
path, heading, span = sys.argv[2], sys.argv[3], int(sys.argv[4])
groups = [g.split("|") for g in sys.argv[5:] if g != "§"]
hay = path and open(path).read()
if heading != "FULL":
    hay = ns["section"](path, heading)
    if hay is None:
        print(f"no section heading matching {heading!r} in {path}")
        sys.exit(1)
best, why = ns["window"](hay, groups, span)
if best is None:
    print(f"needle group {why!r} absent — the landed text lacks this pinned fact (designed red before C06 dev)")
    sys.exit(1)
if why:
    print(f"no single passage of {span} chars covers all needle groups (min span {best})")
    sys.exit(1)
print("ok")
PY
}

# --- t1: research becomes one session per ask (C06 T1 / AC1) -------------------------
if want t1; then
  win "t1[C06 AC1]" "$COORD_SRC" "Research" 1600 'per distinct research ask|one `agent-research` session per|per ask' § 'SAME `RESEARCH.md`|same RESEARCH.md|append' \
    || fail "t1[C06 AC1]: the Research section must pin one agent-research session PER ask, all sessions writing into the SAME RESEARCH.md (sections appended/merged per ask)"
  win "t1[C06 AC1]" "$COORD_SRC" "Research" 1600 'serial' § 'Research: Parallel' § 'case-insensitiv' § 'human-owned|never agent-created|human-created' \
    || fail "t1[C06 AC1]: the section must pin the serial default + the human-created `Research: Parallel` board-label exception (matched case-insensitively like the existing Research label; the label is human-owned, never agent-created)"
  python3 - "$BOARDS_SRC" <<'PY' || fail "t1[C06 AC1 negative]: the boards research-only loop text changed shape — C06 T1 leaves that flow UNTOUCHED"
import re, sys
t = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^## Research-only cards.*?(?=^## |\Z)", t)
if not sec:
    print("the Research-only cards section disappeared from the boards skill"); sys.exit(1)
if "Research: Parallel" in sec.group(0):
    print("the research-only loop gained the Parallel-label exception — C06 pins it into the COORD Research section only; the boards loop keeps its own flow"); sys.exit(1)
print("ok")
PY
  ok "t1[C06 AC1]: per-ask research sessions, shared RESEARCH.md, serial-with-label-exception, boards loop untouched"
fi

# --- t2: agent-explore joins the launchable list + cited stage row (C06 T2 / AC2) -----
if want t2; then
  grep -qE 'You may only launch .*agent-explore' "$COORD_SRC" \
    || fail "t2[C06 AC2]: the coord hard-rule 'You may only launch …' list does not name agent-explore (the six twins share this skill file — one source edit lands it on all; designed red before C06 dev)"
  python3 - "$COORD_SRC" <<'PY' || fail "t2[C06 AC2]: the Exploration citation pin failed (reason above)"
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"(?ms)^\*\*Stage gate.*?(?=\n\n|\n## )", t)
if not m:
    print("the Stage gate paragraph vanished from the coord skill"); sys.exit(1)
para = m.group(0)
if "Exploration" not in para:
    print("the Stage-gate paragraph does not note the boards Stage map's Exploration row as the agent-explore launch surface (C06 T2)"); sys.exit(1)
if re.search(r"runs?\s+agent-explore\s+(with|by|passing)", para, re.I):
    print("the coord skill RESTATES the Exploration stage's launch mechanics — cite the boards Stage map, never restate (repo single-authority rule)"); sys.exit(1)
print("ok")
PY
  ok "t2[C06 AC2]: launchable list names agent-explore; the stage-gate paragraph cites (never restates) the Exploration row"
fi

# --- t3: AD-71 guidance + one-at-a-time explicit + DEFERRED wave-parallel (C06 T3) ----
if want t3; then
  win "t3[C06 AC3-plan]" "$PLAN_SRC" "FULL" 1400 'fewer' § 'subsystem' § 'reviewab' \
    || fail "t3[C06 AC3]: the plan skill's grouping rule still lacks the fewer-cohesive-chunks strengthening (one subsystem = one chunk even across code+docs; split on reviewability, not file count; never mint a chunk a single S task could join)"
  grep -qF 'never mint a chunk' "$PLAN_SRC" \
    || fail "t3[C06 AC3]: the 'never mint a chunk a single S task could join' clause is absent from pipeline-role-plan"
  win "t3[C06 AC3-coord]" "$COORD_SRC" "FULL" 700 'waves group independent chunks for ORDER|wave' § 'one at a time' \
    || fail "t3[C06 AC3]: the coord chunk-loop step does not make today's posture explicit — waves ORDER independent chunks; execution stays one at a time (C06 T3b)"
  grep -qiE 'wave-parallel' "$DECISIONS" && grep -qiE 'deferred' "$DECISIONS" \
    || fail "t3[C06 AC3]: DECISIONS.md no longer carries the wave-parallel-dev DEFERRED entry (sole-committer collision rationale) — verification pin of the plan's own record"
  ok "t3[C06 AC3]: plan guidance + explicit one-at-a-time + DEFERRED wave-parallel record pinned"
fi

# --- t4: the OQ15 done-gate carve-out (C06 T5 / AC4) ----------------------------------
if want t4; then
  win "t4[C06 AC4-5b]" "$COORD_SRC" "FULL" 2200 'Chunk Review' § 'skip' \
    || fail "t4[C06 AC4]: step 5b's fresh-review launch is not conditioned on `Chunk Review` being in the checked stage list (unchecked ⇒ skipped, never silently absorbed — the OQ15 ruling)"
  win "t4[C06 AC4-step7]" "$COORD_SRC" "FULL" 2200 'commands_run' § 'evidence' § 'never on the' \
    || fail "t4[C06 AC4]: step 7 must judge the review-skipped done-gate from the dev's RESULT commands_run evidence — plan Commands + chunk tests ALL passing, judged exactly as review verdicts are judged today (never on the subagent's word)"
  win "t4[C06 AC4]" "$COORD_SRC" "FULL" 3000 'Chunk Review' § 'fresh' § 'unchanged' \
    || fail "t4[C06 AC4]: the checked-Chunk-Review shape (fresh-session agent-review unchanged) must stay pinned alongside the carve-out"
  win "t4[C06 AC4-determinism]" "$COORD_SRC" "FULL" 2200 'dev runs every command|determin' § 'validations-green|validations green|all passing' \
    || fail "t4[C06 AC4]: validation-green determinism must stay mandatory in BOTH shapes (the dev runs every command even when review is skipped)"
  ok "t4[C06 AC4]: step 5b + step 7 carry the checked-stages-only carve-out with the evidence doctrine intact"
fi

# --- t5: negatives — no unconditional parallelism, no waived validations (C06 AC4) ----
if want t5; then
  python3 - "$COORD_SRC" <<'PY' || fail "t5[C06 AC1/AC4 negatives]: a forbidden wording survived (reason above)"
import re, sys
t = open(sys.argv[1]).read()
flat = re.sub(r"\s+", " ", t)
# (1) unconditional parallel-research encouragement: 'parallel' near 'research'
#     must have the label condition adjacent (within the sentence pair).
for m in re.finditer(r"parallel", flat, re.I):
    around = flat[max(0, m.start()-160):m.start()+160]
    if re.search(r"research", around, re.I) and not re.search(r"Research: Parallel|label", around, re.I):
        print(f"'parallel' beside research without the label condition: …{around.strip()[:200]}…"); sys.exit(1)
# (2) done-gate waivers in the review-skipped shape.
for pat in (r"skip.{0,40}(commands|validations)", r"without.{0,40}running.{0,40}(commands|validations)", r"no.{0,30}command.{0,30}(needed|required)"):
    if re.search(pat, flat, re.I) and not re.search(r"skip.{0,40}(review|the review|agent-review)", flat, re.I):
        print(f"waiver-shaped wording /{pat}/ present"); sys.exit(1)
    elif re.search(pat, flat, re.I):
        hit = re.search(pat, flat, re.I).group(0)
        if not re.search(r"review", hit, re.I):
            print(f"waiver-shaped wording /{pat}/ present: {hit}"); sys.exit(1)
print("ok")
PY
  ok "t5[C06 negatives]: parallel-research wording is label-conditioned; nothing waives the validations-green requirement"
fi

# --- t6: mirrors regenerated (C06 AC5) -------------------------------------------------
if want t6; then
  python3 - "$COORD_SRC" "$COORD_GEN" "$PLAN_SRC" "$PLAN_GEN" <<'PY' || fail "t6[C06 AC5]: source↔mirror body equality failed (reason above)"
import re, sys
def body(path):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path).read(), re.S)
    assert m, f"{path}: no frontmatter"
    return re.sub(r"\s+", " ", m.group(2)).strip()
for s, g in ((sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])):
    if body(s) != body(g):
        print(f"{g}'s body differs from its source — run rulesync generate and commit the mirror with the source (never hand-edit)")
        sys.exit(1)
print("ok")
PY
  ok "t6[C06 AC5]: coord + plan skill mirrors equal their sources (whitespace-normalized bodies)"
fi

printf 'PASS: cf-96 coord/plan contract checks (%d ok)\n' "$checks"
