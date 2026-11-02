#!/usr/bin/env bash
# cf-96 C03 sibling asks I — BOARD_COLORS stamp, FRICTION typo, verify pins
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C03).
#
# Pins chunks/C03.md "## Tests": t1 the v12.65 BOARD_COLORS section window in
# skills/wekan-api/references/rest-api-overview.md (AD-77b), t2 the
# .agents/plans/templates/FRICTION.md typo fix (AD-70b), t3 the -pr
# draft/ready two-tier contract across pipeline-push-pr + the four -pr agent
# sources (AD-81 verification — formalizes shipped cf-90 fact, GREEN at base),
# t4 the cf-75 silent-test-fix routing rule in pipeline-role-coord step 5d +
# its pipeline-gates citation (AD-78a verification — GREEN at base).
#
# The rest-overview-v102.sh re-pin (BOARD_COLORS joining its window pins)
# lands in C03's dev commit — same-commit doc-parity law; this file keeps
# the C03 gate self-contained and red-named.
#
# The exact color NAMES are deliberately not pinned here: T1 sources them
# from upstream wekan v12.65 config/const.js at implementation time ("NEVER
# from memory"), and review re-fetches to confirm — a hardcoded list in the
# suite would smuggle my own memory into the contract. What is pinned is the
# section window, the source stamp, and the retirement of the unsourced
# hedge that AD-77b exists because of.
#
# AC trace: t1[C03 AC1] t2[AC2] t3[AC3 — two-tier coverage verified across
# the -pr surfaces] t4[AC3 — silent-route coverage verified].
#
# Red posture: t1/t2 DESIGNED RED (verified absent at plan time and again at
# authoring 2026-11-01: no BOARD_COLORS token in the doc; "cord appends"
# still seeds templates/). t3/t4 GREEN at base — verification pins of
# shipped fact (cf-75, cf-90); they turn red only if a later edit drops the
# contract they confirm.
#
# Usage:
#   bash tests/cf96-siblings/surface.sh            # t1..t4
#   bash tests/cf96-siblings/surface.sh t3 t4      # the verification legs
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

OVERVIEW="skills/wekan-api/references/rest-api-overview.md"
TEMPLATE=".agents/plans/templates/FRICTION.md"
PUSHPR=".rulesync/skills/pipeline-push-pr/SKILL.md"
COORD=".rulesync/skills/pipeline-role-coord/SKILL.md"
GATES=".rulesync/skills/pipeline-gates/SKILL.md"

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

# --- t1: AD-77b — BOARD_COLORS at the POST /api/boards section ----------------------
if want t1; then
  [ -f "$OVERVIEW" ] || fail "harness: $OVERVIEW missing"
  if ! python3 - "$OVERVIEW" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?ms)^#{2,4}[^\n]*POST /api/boards[^\n]*\n(.*?)(?=^#{2,4} |\Z)", text)
if not m:
    print("t1: the POST /api/boards section cannot be located in rest-api-overview.md"); sys.exit(1)
sec = m.group(0) + m.group(1)
if "BOARD_COLORS" not in sec:
    print("t1: the POST /api/boards section still has no BOARD_COLORS list — AD-77b: stamp the v12.65 board-color set from upstream config/const.js (designed red before C03 dev; the label-colors cross-note at the labels section already promises this section exists)"); sys.exit(1)
if not re.search(r"v12\.65", sec):
    print("t1: the BOARD_COLORS window lacks the v12.65 version stamp (C03 AC1 — the rest-overview stamp style)"); sys.exit(1)
if not re.search(r"source-checked", sec):
    print("t1: the BOARD_COLORS window lacks the 'source-checked <date>' stamp — unsourced facts are exactly what this ticket's doc-refresh retired"); sys.exit(1)
if not re.search(r"config/const\.js", sec):
    print("t1: the list must name its upstream source (config/const.js) so review can re-fetch and confirm (C03 AC1)"); sys.exit(1)
if "Set has grown over time" in sec:
    print("t1: the unsourced '(Set has grown over time; verify against your version.)' hedge survives — the source-checked stamp replaces it; a hedged list is what AD-77b filed against"); sys.exit(1)
print("ok")
PY
  then fail "t1[C03 AD-77b/AC1]: the BOARD_COLORS section pins failed (reason above)"; fi
  ok "t1[C03 AC1]: BOARD_COLORS present in the POST /api/boards window with v12.65 + source-checked + upstream-source attribution"
fi

# --- t2: AD-70b — the cord→coord typo that seeds every ticket folder ---------------
if want t2; then
  [ -f "$TEMPLATE" ] || fail "harness: $TEMPLATE missing"
  hits=$(grep -rn "cord appends" .agents/plans/templates/ || true)
  if [ -n "$hits" ]; then
    fail "t2[C03 AD-70b/AC2]: 'cord appends' still present — $hits — the FRICTION template's append-rule line must read 'coord appends' (designed red before C03 dev)"
  fi
  grep -qF "coord appends" "$TEMPLATE" \
    || fail "t2[C03 AC2]: $TEMPLATE lost the 'coord appends' line entirely — the fix is a correction, not a deletion"
  ok "t2[C03 AC2]: no 'cord appends' anywhere in templates/; 'coord appends' present in FRICTION.md"
fi

# --- t3: AD-81 — the -pr two-tier contract across every -pr surface (verification) --
if want t3; then
  [ -f "$PUSHPR" ] || fail "harness: $PUSHPR missing"
  grep -qF 'Draft PR — the unit tier' "$PUSHPR" \
    || fail "t3[C03 AD-81]: $PUSHPR lost the draft=unit tier arm — the cf-90 C05/C06 contract (GitHub runs pull_request workflows during draft; the unit tier rides plain on: pull_request)"
  grep -qF 'Ready PR — the integration tier' "$PUSHPR" \
    || fail "t3[C03 AD-81]: $PUSHPR lost the ready=integration tier arm"
  grep -qF 'ready_for_review' "$PUSHPR" \
    || fail "t3[C03 AD-81]: the integration tier must stay keyed on ready_for_review (+synchronize after ready)"
  grep -qF 'pull_request.draft == false' "$PUSHPR" \
    || fail "t3[C03 AD-81]: the draft guard (github.event.pull_request.draft == false) vanished — the two-tier contract needs it to keep the integration tier off draft"
  for f in agent-dev-pr agent-coord-pr agent-board-coord-pr agent-dev-deploy-pr; do
    grep -qF 'pipeline-push-pr' ".rulesync/subagents/$f.md" \
      || fail "t3[C03 AD-81]: .rulesync/subagents/$f.md no longer cites pipeline-push-pr — the two-tier contract must be loaded/cited on every -pr surface (T3 scope; a gap here is C03's patch-with-regenerate duty)"
  done
  ok "t3[C03 AD-81]: two-tier contract pinned on pipeline-push-pr + cited on all four -pr agent sources (verification of shipped fact)"
fi

# --- t4: AD-78a — silent test-fix routing rule (verification) -----------------------
if want t4; then
  grep -qF 'validation_at_fault' "$COORD" \
    || fail "t4[C03 AD-78a]: pipeline-role-coord step 5d lost the validation_at_fault trigger — cf-75's silent-route rule (a gap found here is C03's patch duty)"
  grep -qF 'test_session' "$COORD" \
    || fail "t4[C03 AD-78a]: step 5d no longer routes back to the authoring test session via test_session"
  grep -qiF 'silently' "$COORD" \
    || fail "t4[C03 AD-78a]: the silent routing word is gone from coord step 5 — the routing must stay no-question"
  grep -qF 'NEEDS_INFO' "$COORD" \
    || fail "t4[C03 AD-78a]: the functionality carve-out (test session returns NEEDS_INFO instead of writing) vanished from coord step 5"
  grep -qiF 'silently' "$GATES" && grep -qF 'test_session' "$GATES" && grep -qF 'NEEDS_INFO' "$GATES" \
    || fail "t4[C03 AD-78a]: the pipeline-gates rule that step 5d cites lost its silent-route / test_session / NEEDS_INFO trio — the two surfaces must agree"
  ok "t4[C03 AD-78a]: silent-route + functionality carve-out pinned across pipeline-role-coord and pipeline-gates (verification of shipped cf-75 fact)"
fi

printf 'PASS: cf-96 C03 sibling-asks checks (%d ok)\n' "$checks"
