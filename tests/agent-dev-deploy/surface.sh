#!/usr/bin/env bash
# -deploy variant DEFINITION contract (2026/2026-10-cf-90-feat-board-coord-
# improvements, C06).
#
# Pins chunks/C06.md "## Tests" t1-t6 + AC1-AC5: the agent-dev-deploy /
# agent-dev-deploy-pr pair (permission blocks mirroring agent-dev-local /
# agent-dev-pr, plus the cleanup opencode rows and an EXPLICIT question allow —
# the user-cancel flow depends on it), the pipeline-role-deploy hidden
# contract skill (broken-initial-deployment expectation, couple-of-options,
# HITL-or-unmanned split, ~90%-context hand-back, re-review after
# reintegration, own-worktree close at hand-back), the coord post-final-
# review hook (Deploy-stage launch condition, widened roster, re-run final
# review, user-cancel -> ONE question), and the definition-only posture
# pinned everywhere so nothing in this ticket EXECUTES the stage.
#
# AC trace: t1[AC1 existence/parse/question+opencode rows/MUST-load]
# t2[AC1 permission-shape parity with the dev baselines — parsed diff
# restricted to the documented worktree_remove addition] t3[AC2 role-skill
# pins] t4[AC3 coord-hook pins] t5[AC4+AC5 definition-only named in the
# agents, overview.md AND AGENTS.md] t6[AC3 roster: both deploy names
# launchable by the coord family — sources AND generated mirrors].
#
# Red posture: everything is designed-red until C06 dev lands the wave-3
# chunk (files absent, hook text absent, roster rows absent); the HOLD arms
# (question-allow phrasing of the dev baselines, AGENTS.md section shape)
# keep the suite honest.
#
# Dev TODO carried here because the chunk scopes it (C06 "Files in scope"
# names tests/agent-perms/surface.sh): landing the pair takes agent-perms A16
# from its verified 22 permission-bearing sources to 24, widens the family
# roster forms there (A12's family.py `roster` 5-role set grows by the class
# launch — alias/local carry agent-dev-deploy, the -pr pair agent-dev-
# deploy-pr, matching this suite's t6), and re-pins any roster-shape arm in
# those files IN THE C06 COMMIT. Do NOT re-pin gate t17 / coord-inwork i4 /
# session-origin s4 / kickoff-branch m4 roster or ladder arms — those ids
# are already pre-existing-red (warm-location drift, see gate.sh's cf-90
# header note) and their drift Review card owns the whole re-pin; record the
# interaction in RESULT deviations instead. This suite deliberately leaves
# agent-perms untouched so A16/A12 stay green for the wave-1/wave-2 gates.
#
# Selection / known-baseline note: no check here invokes a suite carrying the
# pre-existing main-HEAD reds (agent-board-coord gate t17, coord-inwork i4,
# session-origin s4, kickoff-branch m4, wekan-mcp create-list t2 — the
# warm-location permissions drift + the merged cf-68 base, tracked outside
# cf-90). cf-90's C06 gate is: bash tests/agent-dev-deploy/surface.sh; the
# agent-board-coord trio minus t17; agent-perms; standalone-agents; and the
# deploy skill pair's rulesync generate --check (covered by i6-style ids).
#
# Offline-deterministic: frontmatter parse + text pins only — no session, no
# board, no OpenChamber, no deploy execution anywhere (definition-only means
# DEFINITION-only).
#
# Usage:
#   bash tests/agent-dev-deploy/surface.sh            # t1..t6
#   bash tests/agent-dev-deploy/surface.sh t3 t4      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DEP=".rulesync/subagents/agent-dev-deploy.md"
DEPPR=".rulesync/subagents/agent-dev-deploy-pr.md"
DEP_GEN=".opencode/agents/agent-dev-deploy.md"
DEPPR_GEN=".opencode/agents/agent-dev-deploy-pr.md"
BASE_LOCAL=".rulesync/subagents/agent-dev-local.md"
BASE_PR=".rulesync/subagents/agent-dev-pr.md"
ROLE_SRC=".rulesync/skills/pipeline-role-deploy/SKILL.md"
ROLE_GEN=".opencode/skills/pipeline-role-deploy/SKILL.md"
RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
RULES_SRC=".rulesync/rules/overview.md"
CF_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
        .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
        .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
CF_GEN=(.opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md
        .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md
        .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md)

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/agent-dev-deploy-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

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

cat >"$TMP/win.py" <<'PY'
# Co-location window (sibling-suite convention): the needles must read as ONE
# passage — a contract sentence — not as scattered file-wide hits.
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path).read()
if ci:
    text = text.lower(); needles = [n.lower() for n in needles]
pts = []
for n in needles:
    start, found = 0, 0
    while True:
        i = text.find(n, start)
        if i < 0:
            break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'missing needle: {n}'); sys.exit(1)
pts.sort()
need = len(set(needles))
cnt, have, best, left = {}, 0, None, 0
for right, (p, n) in enumerate(pts):
    cnt[n] = cnt.get(n, 0) + 1
    if cnt[n] == 1:
        have += 1
    while have == need:
        s = p - pts[left][0]
        if best is None or s < best:
            best = s
        cnt[pts[left][1]] -= 1
        if cnt[pts[left][1]] == 0:
            have -= 1
        left += 1
if best is None or best > span:
    print(f'no window of {span} chars covers all needles (min span {best})'); sys.exit(1)
PY

cat >"$TMP/deployfm.py" <<'PY'
# Shared parsed-frontmatter inspection: existence + parse + non-empty
# description + the explicit question allow + the three cleanup opencode rows
# + the /pipeline-role-deploy MUST-load line. Exit codes: 0 ok, 97 file
# missing (the CALLER renders the designed-red message naming C06 dev).
import re, sys, yaml
path = sys.argv[1]
try:
    text = open(path).read()
except FileNotFoundError:
    sys.exit(97)
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, f"{path}: no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
body = m.group(2)
assert (fm.get("description") or "").strip(), f"{path}: empty description"
perms = ((fm.get("opencode") or {}).get("permissions")) or fm.get("permissions") or []
def has(action, resource="*", effect="allow"):
    return any(p.get("action") == action and p.get("resource", "*") == resource
               and p.get("effect") == effect for p in perms)
assert has("question"), f"{path}: no explicit question allow — the user-cancel flow depends on it (repo hard rule)"
for tool in ("opencode_session_move", "opencode_worktree_list", "opencode_worktree_remove"):
    assert has(tool), f"{path}: missing the cleanup opencode row {tool} (C06 Tasks)"
assert re.search(r"^\s*/pipeline-role-deploy\s*$", body, re.M), \
    f"{path}: body does not MUST-load /pipeline-role-deploy"
print("fm-ok")
PY

# --- t1: the pair exists and carries the required grant shape (AC1) ------------
if want t1; then
  for f in "$DEP" "$DEPPR" "$DEP_GEN" "$DEPPR_GEN"; do
    if [ ! -f "$f" ]; then
      fail "t1[C06 AC1]: $f does not exist yet — the -deploy pair is C06's first task, sources AND generated mirrors land together (designed red before C06 dev)"
    fi
  done
  for f in "$DEP" "$DEPPR" "$DEP_GEN" "$DEPPR_GEN"; do
    python3 "$TMP/deployfm.py" "$f" \
      || fail "t1[C06 AC1]: $f violates the deploy-agent shape (parse / non-empty description / explicit question allow / session_move + worktree_list + worktree_remove / MUST-load /pipeline-role-deploy)"
  done
  ok "t1[C06 AC1]: both deploy agents exist as source+mirror pairs, parse, carry the explicit question allow, the three cleanup opencode rows, and MUST-load the role skill"
fi

# --- t2: permission-shape parity with the dev baselines (AC1) ------------------
if want t2; then
  for f in "$DEP" "$DEPPR" "$DEP_GEN" "$DEPPR_GEN" "$BASE_LOCAL" "$BASE_PR"; do
    [ -f "$f" ] || fail "t2[C06 AC1]: $f missing (designed red before C06 dev — same reason as t1)"
  done
  if ! python3 - "$DEP" "$BASE_LOCAL" "$DEPPR" "$BASE_PR" "$DEP_GEN" "$DEPPR_GEN" \
    ".opencode/agents/agent-dev-local.md" ".opencode/agents/agent-dev-pr.md" <<'PY'
import re, sys, yaml

def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return ((fm.get("opencode") or {}).get("permissions")) or fm.get("permissions") or []

REMOVE = {"action": "opencode_worktree_remove", "resource": "*", "effect": "allow"}

def parity(dep, base, label):
    a, b = perms(dep), perms(base)
    if REMOVE not in a:
        print(f"{label}: no opencode_worktree_remove allow row"); return 1
    # The documented addition is worktree_remove ONLY; strip every remove row
    # (count-checked) and the remainder must equal the baseline EXACTLY —
    # list equality keeps order, so a reordered row still reddens.
    a2 = [r for r in a if r != REMOVE]
    if len(a) - len(a2) != 1:
        print(f"{label}: {len(a) - len(a2)} worktree_remove rows, want exactly one"); return 1
    if a2 != b:
        diff_a = [r for r in a2 if r not in b]
        diff_b = [r for r in b if r not in a2]
        print(f"{label}: mirrored-permission delta beyond the documented addition — extra {diff_a} / missing {diff_b}")
        return 1
    return 0

rc = 0
for dep, base, label in (
    (sys.argv[1], sys.argv[2], "agent-dev-deploy vs agent-dev-local (source)"),
    (sys.argv[3], sys.argv[4], "agent-dev-deploy-pr vs agent-dev-pr (source)"),
    (sys.argv[5], sys.argv[7], "agent-dev-deploy vs agent-dev-local (generated mirror)"),
    (sys.argv[6], sys.argv[8], "agent-dev-deploy-pr vs agent-dev-pr (generated mirror)"),
):
    rc |= parity(dep, base, label)
sys.exit(rc)
PY
  then fail "t2[C06 AC1]: the -deploy pair mirrors agent-dev-local/agent-dev-pr permission shape OUTSIDE the single documented addition (opencode_worktree_remove) — plain twin stays push-free, -pr twin keeps the push allow with the main/force deny tail (reason above)"; fi
  ok "t2[C06 AC1]: permission parity — each deploy twin equals its dev baseline plus exactly the worktree_remove addition, order kept, sources AND mirrors"
fi

# --- t3: pipeline-role-deploy skill pins (AC2) ---------------------------------
if want t3; then
  for f in "$ROLE_SRC" "$ROLE_GEN"; do
    [ -f "$f" ] || fail "t3[C06 AC2]: $f missing — the hidden role skill is C06's second task (designed red before C06 dev)"
  done
  if ! python3 - "$ROLE_SRC" <<'PY'
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
assert m, "no frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
assert fm.get("disable-model-invocation") is True, "the hidden contract skill must set disable-model-invocation: true (the pipeline-role-* convention)"
d = (fm.get("description") or "")
assert re.search(r"(?i)MUST-loaded by .*deploy", d), "the description does not declare it is MUST-loaded by the deploy agents"
PY
  then fail "t3[C06 AC2]: the role skill frontmatter breaks the hidden-contract shape (reason above)"; fi
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 900 'broken' 'deploy' \
    || fail "t3[C06 AC2]: the skill never states the expectation that the INITIAL DEPLOYMENT IS BROKEN in one or more ways (the card's framing of the role)"
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 600 'couple' 'option' \
    || fail "t3[C06 AC2]: the couple-of-options rule is missing — per issue, produce A COUPLE of solution options"
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 1200 'human in the loop' 'question' \
    || fail "t3[C06 AC2]: the HITL decision split is not stated — interactive run OR Deployment checked under Human in the Loop -> question the user to pick"
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 1200 'recommendation' 'implement' \
    || fail "t3[C06 AC2]: the unmanned branch is missing — take its own recommendation, implement, deploy, examine the result"
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 900 '90%' 'hand' \
    || fail "t3[C06 AC2]: the ~90%-context-or-satisfied hand-back to the coord is not pinned"
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 1200 're-review' 'coord' \
    || fail "t3[C06 AC2]: the reintegration contract is missing — RESULT to the coord, fold into plan/tests, everything re-reviewed"
  python3 "$TMP/win.py" --ci "$ROLE_SRC" 900 'worktree' 'hand-back' \
    || fail "t3[C06 AC2]: the own-worktree-close-at-hand-back sentence is missing (branch stays coord-owned, landing-gated per C03)"
  python3 "$TMP/win.py" --ci "$ROLE_GEN" 900 '90%' 'hand' \
    || fail "t3[C06 AC2]: the generated mirror does not carry the role contract (sources + generated land together)"
  ok "t3[C06 AC2]: pipeline-role-deploy pins the broken-initial expectation, couple-of-options, HITL-vs-unmanned split, 90%-hand-back, re-review, own-worktree close — source + mirror"
fi

# --- t4: coord hook pins (AC3) --------------------------------------------------
if want t4; then
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 1200 'deploy' 'final review' \
      || fail "t4[C06 AC3]: $f lacks the post-final-review deploy hook — launched when the final review returns APPROVED AND the run has a Deploy stage (checked Lifecycle Deploy; the boards Stage map stays the launch-surface authority, cited not restated)"
  done
  grep -qiE 'lifecycle[^.]{0,80}deploy|deploy[^.]{0,80}checked' "$RC_SRC" \
    || fail "t4[C06 AC3]: the RC hook does not gate the launch on the checked Lifecycle Deploy stage (cite the boards stage map, never duplicate it)"
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 1200 're-run' 'review' \
      || fail "t4[C06 AC3]: $f omits the re-run-the-final-review step after the deploy RESULT is folded back"
    python3 "$TMP/win.py" --ci "$f" 900 'cancel' 'one' \
      || fail "t4[C06 AC3]: $f omits the user-cancel path — ONE question whose answer hands control back to the coord, never a silent relaunch"
    grep -qiE 'never[^.]{0,60}relaunch|no silent relaunch' "$f" \
      || fail "t4[C06 AC3]: $f does not forbid silently relaunching a user-cancelled deploy session"
  done
  ok "t4[C06 AC3]: RC pair carries the launch condition, the re-run-final-review, and the user-cancel ONE-question path"
fi

# --- t5: definition-only posture named everywhere (AC4 + AC5) ------------------
if want t5; then
  for f in "$DEP" "$DEPPR"; do
    if ! python3 - "$f" <<'PY'
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
fm = yaml.safe_load(m.group(1)) or {}
d = " ".join(str(fm.get("description") or "").split())
assert re.search(r"(?i)definition[ -]only", d), "the frontmatter description must state the definition-only status (C06 Tasks)"
print("ok")
PY
    then fail "t5[C06 AC4]: $f's description omits the definition-only status"; fi
  done
  grep -qiE 'definition[ -]only' "$RULES_SRC" \
    || fail "t5[C06 AC4]: $RULES_SRC names the deploy pair without the definition-only status — AGENTS.md regenerates from here"
  grep -qiE 'definition[ -]only' AGENTS.md \
    || fail "t5[C06 AC5]: AGENTS.md lost the definition-only wording — regenerate from the rules source"
  grep -qE 'agent-dev-deploy' "$RULES_SRC" && grep -qE 'agent-dev-deploy-pr' "$RULES_SRC" \
    || fail "t5[C06 AC4]: the rules Agents section does not name BOTH deploy variant names"
  # DEFINITION-ONLY, operational half: nothing in this ticket WIRES an
  # execution entry point. The stage fires only through the coord hook under
  # a checked Lifecycle Deploy (boards Stage map, cited) — commands and loop
  # files must stay deploy-free.
  leaks=$(grep -rln 'agent-dev-deploy' .rulesync/commands .opencode/commands .agents/loops 2>/dev/null || true)
  [ -z "$leaks" ] || { printf '%s\n' "$leaks" >&2; fail "t5[C06 AC5]: a command or loop file already references the deploy agent — this ticket ships the DEFINITION only; the launch surface is the coord hook + checked Lifecycle Deploy, never an entry point"; }
  ok "t5[C06 AC4+AC5]: the definition-only status is pinned in both agent descriptions, the rules source and AGENTS.md, the pair is named, and no command/loop wires a deploy execution path"
fi

# --- t6: the widened launch roster (AC3) ----------------------------------------
if want t6; then
  for f in "$RC_SRC" "$RC_GEN"; do
    grep -qE 'agent-dev-deploy`' "$f" \
      || fail "t6[C06 AC3]: $f's widened roster line never names plain agent-dev-deploy (the -local-class launch)"
    grep -qE 'agent-dev-deploy-pr`' "$f" \
      || fail "t6[C06 AC3]: $f's widened roster line never names agent-dev-deploy-pr (the -pr-class launch)"
  done
  if ! python3 - "${CF_SRC[@]}" "${CF_GEN[@]}" <<'PY'
import re, sys, yaml

def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    fm = yaml.safe_load(m.group(1)) or {}
    return ((fm.get("opencode") or {}).get("permissions")) or fm.get("permissions") or []

rc = 0
for path in sys.argv[1:]:
    want = "agent-dev-deploy-pr" if path.endswith("-pr.md") else "agent-dev-deploy"
    subs = [p.get("resource") for p in perms(path) if p.get("action") == "subagent" and p.get("effect") == "allow"]
    if want not in subs:
        print(f"{path}: subagent allows {subs} lack {want} — the coord family must launch its class's deploy variant")
        rc = 1
sys.exit(rc)
PY
  then fail "t6[C06 AC3]: not every coord-family file (sources AND mirrors) carries the launch allow for its class's deploy variant (reasons above; agent-perms A12/gate roster forms move with the same commit — see the dev TODO in this header)"; fi
  ok "t6[C06 AC3]: roster widened — RC names both deploy variants and all twelve coord-family files launch their class's variant"
fi

printf 'PASS: -deploy definition contract checks (%d ok)\n' "$checks"
