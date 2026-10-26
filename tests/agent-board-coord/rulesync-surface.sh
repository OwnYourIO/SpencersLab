#!/usr/bin/env bash
# agent-board-coord surface contract (2026/2026-10-feat-board-coord-intake,
# C02 + C03, with c6 landing at C04): the boards skill as the redesigned
# card-driven intake contract, the agent-board-coord body + /pipeline-boards
# command reworded to it, and the permissions matrix row.
#
# RE-CREATED on the re-cut base as a SUPERSET of the deleted
# `git show 09696ae57:tests/agent-board-coord/rulesync-surface.sh` (D25): c1-c8
# keep the upstream ticket's pinned contracts (five section titles, the
# frontmatter shape, narrow dev_boards*, the launch-command target) so the
# new checks extend, never replace, them (D7). Deliberate adaptations to the
# new base: id selection so C02/C03 reviews can run before C04 lands the
# permissions row (the dev-mcp-fleet.sh convention), the rulesync npx ladder
# with skip-with-warning (the binary is ask-gated in subagent shells —
# FRICTION note, t14 precedent), and the c8 allow-set widened to the union of
# THIS ticket's four chunks (the old scope belonged to the old C05).
#
# Contract source: chunks/C02.md + chunks/C03.md "## Tests". AC trace:
# c1[AC-files] c2[C03 AC3 + D21; cf-52 RE-PIN: $PORT_REF frontmatter delta is
# the two scoped shell allows only] c3[C03 AC4] c4[C02 AC2] c5[C03 command]
# c6[C04 AC2 — green only once C04 lands] c7[C02 AC3] c8[C02 AC4 scope;
# cf-52 widenings] c9[C02 AC5 + C03 AC4] c10[C02 AC1 pickup order] c11[C02
# AC1 checklists + D9 drift detector] c12[C02 AC1 slug/session/cf- + cf-50 round-2 RE-PIN:
# dead-literal ABSENCE + dynamic Session-origin phrases + D12 negative]
# c13[C02 AC1 research-only + D15] c14[C02 AC1 D11 resume] c15[C02 AC1 C01
# tool names] c16[C03 AC1 body+command deltas] c17[C02 AC4 byte-unchanged;
# cf-52 RE-PIN drops kickoff/role-coord from the frozen set].
#
# Red before C02/C03 (the ported skill is still the old two-list pickup and
# live-question intake); c1-c5, c7, c9, c17 are already green and hold as
# regressions. cf-52 posture: this suite is a pure regression gate on the
# coord-inwork ticket — all of c1..c17 are green before C01 and must HOLD
# after it; the new contract is asserted by tests/coord-inwork/surface.sh.
#
# CHUNK_BASE=<ref> narrows the scope checks to "since that commit"; default
# HEAD = uncommitted working tree. PORT_REF=<ref> re-points the frontmatter
# byte-pin. Default 916044893 (main's tip when cf-52 landed): the pin must
# anchor on the tree the two-allow delta was applied TO, not the ticket's
# branch point — main moved the block independently (Code Mode execute
# allow), so a stale anchor reads sanctioned platform drift as a contract
# violation. The original anchor was bab7e7cc3 (the port commit).
#
# Usage:
#   bash tests/agent-board-coord/rulesync-surface.sh            # c1..c17
#   bash tests/agent-board-coord/rulesync-surface.sh c1 c4 c10 # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
PORT_REF="${PORT_REF:-916044893}"
FEATURE=".agents/plans/2026/2026-10-feat-board-coord-intake"
# This file is reused as a regression gate by the later cf-50 gate ticket,
# which shares the branch; its scope list must admit that ticket's plan
# folder and in-scope surface (the union-of-chunks convention above), or the
# cf-50 folder's mere existence reads as a scope violation. Content checks
# are untouched.
FEATURE2=".agents/plans/2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords"
# Same union convention: the WeKan v12.64 upgrade ticket ran on this branch
# (runbook + checked-in rule import JSON), so its folder is admitted too.
FEATURE3=".agents/plans/2026/2026-10-dep-wekan-v12-upgrade"
# Same union-of-tickets scope posture for cf-52, which shares the branch and
# legitimately re-opens the kickoff/role-coord pair plus the coord agents.
FEATURE4=".agents/plans/2026/2026-10-cf-52-feat-coord-session-inwork"
RULES_SRC=".rulesync/rules/overview.md"

SKILL_SRC=".rulesync/skills/boards/SKILL.md"
AGENT_SRC=".rulesync/subagents/agent-board-coord.md"
CMD_SRC=".rulesync/commands/pipeline-boards.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
SKILL_GEN=".opencode/skills/boards/SKILL.md"
AGENT_GEN=".opencode/agents/agent-board-coord.md"
CMD_GEN=".opencode/commands/pipeline-boards.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/rulesync-surface-test.XXXXXX) || { echo "fail: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 17); do WANT["c$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^c([1-9]|1[0-7])$ ]] || fail "unknown check id '$a' (expected c1..c17)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Shared assertion helpers for the content checks (each small, single-purpose).
cat >"$TMP/neg12.py" <<'PY'
# D12 pins the board surface to exactly two custom fields, so a surface must
# never present a `models` custom field as existing. A line pairing "models"
# with "custom field" fails — unless the same line negates it: "no `models`
# custom field exists" is D12's own clarification quoted verbatim in the
# plan's C03 task text, and forbidding it would punish dev for recording the
# decision. The negation word is the difference between denial and announcement.
import re, sys
pat = re.compile(r'models.*custom.?field', re.I)
neg = re.compile(r"\b(no|not|never|dropped|doesn'?t|does not|absent|omits?)\b", re.I)
bad = []
for i, line in enumerate(open(sys.argv[1]), 1):
    if pat.search(line) and not neg.search(line):
        bad.append(f"line {i}: {line.strip()}")
if bad:
    print(" | ".join(bad))
    sys.exit(1)
PY

cat >"$TMP/order.py" <<'PY'
# Pickup order is a business rule (Rework first, then Not Started, then the
# new Low Priority list), so first-occurrence offsets inside the named
# section are the check — a reworded passage still passes, a reordered one
# cannot.
import re, sys
path, title = sys.argv[1], sys.argv[2]
needles = sys.argv[3:]
text = open(path).read()
m = re.search(r'(?ms)^#+[^\n]*' + re.escape(title) + r'[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print(f'section "{title}" not found'); sys.exit(1)
body = m.group(1)
pos = []
for n in needles:
    i = body.find(n)
    if i < 0:
        print(f'needle "{n}" not in section "{title}"'); sys.exit(1)
    pos.append(i)
if pos != sorted(pos):
    print(f'order violated: {list(zip(needles, pos))}'); sys.exit(1)
PY

cat >"$TMP/window.py" <<'PY'
# Co-location within a bounded span: the needles must read as one passage
# (a checklist definition, a label rule), not as scattered file-wide hits.
import sys
path, span = sys.argv[1], int(sys.argv[2])
needles = sys.argv[3:]
text = open(path).read()
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

# --- c1: all eight source + generated files exist ----------------------------
if want c1; then
  for f in "$SKILL_SRC" "$AGENT_SRC" "$CMD_SRC" "$PERM_SRC" "$SKILL_GEN" "$AGENT_GEN" "$CMD_GEN" "$PERM_GEN"; do
    [ -f "$f" ] || fail "c1: $f is missing"
  done
  ok "c1: the four sources and four generated counterparts all exist (ported at $PORT_REF)"
fi

# --- c2: the generated agent — frontmatter contract (C03 AC3, D21) ------------
if want c2; then
  python3 - "$AGENT_GEN" <<'EOF' || fail "c2: generated agent-board-coord frontmatter violates the contract"
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1))
perms = fm.get("permissions") or []
errs = []
if fm.get("name") != "agent-board-coord":
    errs.append(f"name is {fm.get('name')!r}, want agent-board-coord")
if fm.get("mode") != "primary":
    errs.append(f"mode is {fm.get('mode')!r}, want primary")
color = fm.get("color")
if not color:
    errs.append("no color set")
elif color == "#06b6d4":
    errs.append("color is agent-coord's #06b6d4 — the variant needs a distinct color")
desc = str(fm.get("description") or "")
if "STATE.json, DECISIONS.md and FRICTION.md" not in desc:
    errs.append("description lost the 'writes only STATE.json, DECISIONS.md and FRICTION.md' clause")
if "board" not in desc.lower():
    errs.append("description is not reworded for the board-driven variant")
def has(a, r, e):
    return any(p.get("action") == a and p.get("resource") == r and p.get("effect") == e for p in perms)
if not has("question", "*", "allow"):
    errs.append("explicit question allow missing (repo hard rule)")
if not has("dev_boards*", "*", "allow"):
    errs.append("dev_boards* allow missing (the variant's single MCP permission)")
# D21 adjudication: the re-cut onto main brought a fleet-wide `dev*`
# convention, but board-coord consumes card intake/exit only — least privilege
# survives, so the broad action must stay ABSENT, not merely be accompanied.
if any(p.get("action") == "dev*" for p in perms):
    errs.append("broad dev* allow present — D21 rules board-coord keeps ONLY narrow dev_boards*")
for a in ["agent-plan", "agent-test", "agent-dev", "agent-review", "agent-research"]:
    if not has("subagent", a, "allow"):
        errs.append(f"subagent allow missing for {a}")
edits = [p.get("resource") for p in perms if p.get("action") == "edit"]
want_edits = sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"])
if sorted(edits) != want_edits:
    errs.append(f"edit allows are {edits}, want ONLY the three plan-state files")
if errs:
    print("; ".join(errs))
    sys.exit(1)
# last-match-wins: the allow must sit after the leading deny-all
idx = {i: p for i, p in enumerate(perms)}
deny_all = [i for i, p in idx.items() if p.get("action") == "*" and p.get("resource") == "*" and p.get("effect") == "deny"]
dev_boards = [i for i, p in idx.items() if p.get("action") == "dev_boards*"]
if not deny_all or not dev_boards or dev_boards[0] < deny_all[0]:
    print("the dev_boards allow does not follow the leading deny-all (last-match-wins would deny it)")
    sys.exit(1)
EOF
  ok "c2: generated agent frontmatter (name, distinct color, question + dev_boards* allows, NO broad dev* (D21), five subagent allows, three edit allows only)"

  # C03 pinned this frontmatter byte-identical to the port commit. cf-52 D10
  # re-pins: the block is now "identical to the port, or the port plus exactly
  # the two scoped opencode-api shell allows" — every other permission drift
  # still fails here, and tests/coord-inwork/surface.sh i4 pins the delta's
  # existence, placement and literals, so this guard only loosens along the
  # one user-approved axis (cf-50 D21 posture: a pin moves where the contract
  # moves).
  git show "$PORT_REF:$AGENT_GEN" >"$TMP/c2-port-fm.md" 2>/dev/null \
    || fail "c2: $AGENT_GEN not readable at $PORT_REF"
  python3 - "$TMP/c2-port-fm.md" "$AGENT_GEN" <<'EOF' || fail "c2: agent-board-coord generated frontmatter drifted from $PORT_REF beyond the two cf-52 scoped shell allows (C03 AC3; cf-52 D10 re-pin)"
import re, sys, yaml

def fm(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    return yaml.safe_load(m.group(1)) or {}

a, b = fm(sys.argv[1]), fm(sys.argv[2])
SHELL = [{"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"},
         {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"}]
pa, pb = a.get("permissions") or [], b.get("permissions") or []
rest = lambda d: {k: v for k, v in d.items() if k != "permissions"}
if rest(a) != rest(b):
    print("a non-permissions frontmatter key changed"); sys.exit(1)
if pa == pb:
    sys.exit(0)
kept = [p for p in pb if p not in SHELL]
if kept == pa and [p for p in pb if p in SHELL] == SHELL:
    sys.exit(0)
print(f"{len(pb) - len(pa)} permission row(s) differ — only the two scoped shell allows are sanctioned")
sys.exit(1)
EOF
  ok "c2: generated agent frontmatter frozen at $PORT_REF except the sanctioned cf-52 two-allow delta"
fi

# --- c3: the generated agent — body keeps the skeleton ------------------------
if want c3; then
  grep -qE '^[[:space:]]*/pipeline-conventions[[:space:]]*$' "$AGENT_GEN" \
    || fail "c3: the agent body lost its pipeline-conventions MUST-load entry (skeleton not kept)"
  grep -qE '^[[:space:]]*/boards[[:space:]]*$' "$AGENT_GEN" \
    || fail "c3: the agent body MUST-load list does not include /boards"
  grep -q '^## Boards' "$AGENT_GEN" \
    || fail "c3: the agent body has no '## Boards' section (board-driven intake + protocol)"
  ok "c3: agent body keeps the skeleton and adds /boards + the Boards section"
fi

# --- c4: the generated skill — five sections + the board facts (C02 AC2) ------
if want c4; then
  for title in 'Board facts' 'Card pickup' 'Card lifecycle' 'Batched question protocol' 'Launch prompt to agent-plan'; do
    grep -qiE "^#{1,6}[[:space:]].*${title}" "$SKILL_GEN" \
      || fail "c4: the boards skill is missing its '${title}' section"
  done
  for fact in 'wekan.spencerslab.com' 'AI-Dev' 'In Process' 'Not Started' 'Executing' '**Review**' 'Rework' 'Finished' 'dev-boards' 'wekan-api'; do
    grep -qF "$fact" "$SKILL_GEN" || fail "c4: the boards skill never names '$fact' (the board facts are incomplete)"
  done
  grep -qi 'human' "$SKILL_GEN" || fail "c4: the boards skill never assigns Finished to a human (the agent must never self-move to Finished)"
  grep -qF 'open_questions' "$SKILL_GEN" \
    || fail "c4: the boards skill does not name the RESULT open_questions channel for the batched round"
  ok "c4: generated skill has all five sections, the board facts, and the launch-prompt contract"
fi

# --- c5: the generated command -------------------------------------------------
if want c5; then
  grep -q '^agent: agent-board-coord$' "$CMD_GEN" \
    || fail "c5: the /pipeline-boards command does not target agent-board-coord"
  grep -q 'ARGUMENTS' "$CMD_GEN" || fail "c5: the /pipeline-boards command does not read \$ARGUMENTS (card id)"
  grep -qi 'AI-Dev board card' "$CMD_GEN" || fail "c5: the command description does not say it runs a WeKan AI-Dev board card"
  # C03 rewords the intake sentence but must keep the resume machinery.
  grep -q 'STATE.json' "$CMD_GEN" || fail "c5: the command lost its STATE snapshot line"
  grep -q 'approved' "$CMD_GEN" || fail "c5: the command lost the approved-plan resume logic"
  ok "c5: /pipeline-boards targets agent-board-coord, takes an optional card id, keeps the STATE snapshot + resume logic"
fi

# --- c6: permissions matrix — board-coord row (lands with C04) -----------------
if want c6; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    grep -qE '^\|[[:space:]]*board-coord[[:space:]]*\|' "$f" \
      || fail "c6: $f has no board-coord row in the role matrix (C04 restores it — excluded from C02/C03 review runs)"
    grep -q 'dev_boards' "$f" || fail "c6: $f does not explain the dev_boards allow"
    grep -qE '^\|[[:space:]]*coord[[:space:]]*\|' "$f" \
      || fail "c6: $f lost the coord row (the matrix must stay, not be replaced)"
  done
  ok "c6: permissions matrix carries the board-coord row (source + generated) and keeps the coord row"
fi

# --- c7: rulesync generate twice — the second run is a no-op (C02 AC3) --------
# rulesync runs ask-gated in unattended subagent shells (its own edit surface
# is machinery), so an unresolvable binary skips with a warning like t14 of
# tests/services/dev-mcp-fleet.sh; the first run may materialize pending
# generation, so the gate is that the SECOND run changes nothing.
if want c7; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "c7: rulesync is not resolvable here (PATH or npx cache); the regeneration gate was not run — re-run where it is available"
  else
    $RS generate >"$TMP/rs1.log" 2>&1 || { tail -n 20 "$TMP/rs1.log" >&2; fail "c7: first rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    $RS generate >"$TMP/rs2.log" 2>&1 || { tail -n 20 "$TMP/rs2.log" >&2; fail "c7: second rulesync generate failed"; }
    snap_after=$(git status --porcelain)
    if [ "$snap_before" != "$snap_after" ]; then
      printf '%s\n' "--- after first run
$snap_before
--- after second run
$snap_after" >"$TMP/noop.diff"
      fail "c7: the second rulesync generate is not a no-op (sources and generated surfaces have drifted; see $TMP/noop.diff)"
    fi
    ok "c7: the second rulesync generate is a no-op (sources + generated in sync, via $RS)"
  fi
fi

# --- c8: scope — changed paths limited to this ticket's in-scope files ---------
# The union of C01-C04's file lists (the old ticket's eight-file scope cannot
# hold when four chunks share this branch); anything outside it — notably the
# pipeline-models/pipeline-gates sources — is a contract violation (C02 AC4,
# D1). cf-52 widens the set: its coord-pair grants, the kickoff/role-coord
# contract pair, tests/coord-inwork/* (tests/* already admits them) and its
# plan folder (D10 — the pins move with the contract, not against it).
if want c8; then
  { git diff --name-only "$BASE" || true; git ls-files --others --exclude-standard; } | sort -u >"$TMP/changed.txt"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "$SKILL_SRC"|"$AGENT_SRC"|"$CMD_SRC"|"$PERM_SRC"|"$RULES_SRC"|\
      "$SKILL_GEN"|"$AGENT_GEN"|"$CMD_GEN"|"$PERM_GEN"|AGENTS.md|\
      containers/wekan-mcp/*|skills/wekan-api/*|tests/*|"$FEATURE"/*|\
      "$FEATURE2"/*|"$FEATURE3"/*|"$FEATURE4"/*|scripts/*|.rulesync/commands/pipeline-boards-hourly.md|\
      .opencode/commands/pipeline-boards-hourly.md|\
      .rulesync/subagents/agent-coord.md|.opencode/agents/agent-coord.md|\
      .rulesync/skills/pipeline-kickoff/SKILL.md|.opencode/skills/pipeline-kickoff/SKILL.md|\
      .rulesync/skills/pipeline-role-coord/SKILL.md|.opencode/skills/pipeline-role-coord/SKILL.md) : ;;
      *) fail "c8: path outside the ticket's in-scope files: $p (base: $BASE)" ;;
    esac
  done <"$TMP/changed.txt"
  ok "c8: changed paths limited to the ticket's in-scope files (base: $BASE)"
fi

# --- c9: skill self-declaration + agent skeleton loads (C02 AC5, C03 AC4) -----
if want c9; then
  grep -qF 'MUST-loaded by agent-board-coord' "$SKILL_GEN" \
    || fail "c9: the boards skill no longer declares itself MUST-loaded by agent-board-coord"
  grep -qiE 'on demand[^.]*run start|never at run start' "$SKILL_GEN" \
    || fail "c9: the boards skill lost the 'wekan-api on demand, never at run start' note"
  grep -qE '^[[:space:]]*/pipeline-kickoff[[:space:]]*$' "$AGENT_GEN" \
    || fail "c9: the agent lost its /pipeline-kickoff MUST-load — the skill's override text retires the QUESTIONS for board runs, not the load list"
  grep -qE '^[[:space:]]*/pipeline-models[[:space:]]*$' "$AGENT_GEN" \
    || fail "c9: the agent lost its /pipeline-models MUST-load (the size mapping stays authoritative there)"
  ok "c9: skill declares its consumer + the on-demand note; agent still MUST-loads /pipeline-kickoff and /pipeline-models"
fi

# --- c10: pickup order gains Low Priority (C02 AC1) ----------------------------
if want c10; then
  grep -qF 'Low Priority' "$SKILL_GEN" \
    || fail "c10: the boards skill never mentions the new Low Priority list"
  python3 "$TMP/order.py" "$SKILL_GEN" 'Card pickup' 'Rework' 'Not Started' 'Low Priority' \
    || fail "c10: the Card pickup passage does not order pickup Rework -> Not Started -> Low Priority"
  ok "c10: pickup walks Rework -> Not Started -> Low Priority inside the Card pickup passage"
fi

# --- c11: the five standard checklists (C02 AC1, D9 drift detector) ------------
# The Services item set regenerates from `ls services/` at run time (D9): the
# day a folder is added and the skill goes stale, this check fails loudly
# instead of a doc drifting silently.
if want c11; then
  python3 "$TMP/window.py" "$SKILL_GEN" 2500 'Services' 'Type' 'Model(s)' 'Research' 'Human in the Loop' \
    || fail "c11: Services/Type/Model(s)/Research/Human in the Loop do not read as one checklist-definition passage"
  for d in $(ls services/); do
    grep -qF "\`$d\`" "$SKILL_GEN" \
      || fail "c11: the Services checklist does not name the services/$d folder as a code span — drift detector (D9) failed"
  done
  for extra in 'home-assistant' 'agent context'; do
    grep -qF "\`$extra\`" "$SKILL_GEN" \
      || fail "c11: the Services checklist does not name the non-folder work target '$extra' as a code span"
  done
  grep -qE 'feat.*bug.*debug.*dep.*refactor.*chore.*docs' "$SKILL_GEN" \
    || fail "c11: the Type checklist does not list feat|bug|debug|dep|refactor|chore|docs in one passage"
  grep -qE 'Qwen Large.*Qwen 27b.*Qwen Flash.*Local' "$SKILL_GEN" \
    || fail "c11: the Model(s) checklist does not list Qwen Large | Qwen 27b | Qwen Flash | Local"
  python3 "$TMP/window.py" "$SKILL_GEN" 500 'None' 'Before Planning' 'After Planning' 'Agent Decides' \
    || fail "c11: the Research checklist does not carry its four options (None / Before Planning / After Planning / Agent Decides)"
  grep -qE 'Human in the Loop.*`Research` \| `Plan` \| `PR` \| `Deployment`' "$SKILL_GEN" \
    || fail "c11: the Human in the Loop checklist does not list Research | Plan | PR | Deployment in one passage"
  grep -qF 'Default selection: `Qwen Flash`' "$SKILL_GEN" \
    || fail "c11: the Model(s) checklist does not state its default selection (Qwen Flash alone)"
  grep -qF 'Default: `Agent Decides`' "$SKILL_GEN" \
    || fail "c11: the Research checklist does not state its default item (Agent Decides)"
  grep -qF 'Default: `Plan`' "$SKILL_GEN" \
    || fail "c11: the Human in the Loop checklist does not state its default item (Plan)"
  ok "c11: five checklist titles with full item sets — Services regenerated from ls services/ (13 folders) + home-assistant/agent context; Research options + default; HITL items + default; Model(s) default stated"
fi

# --- c12: slug/session custom fields, cf- slugs, session-origin URL, no run tag (C02 AC1, cf-50 r2 re-pin) --
if want c12; then
  for s in 'slug' 'session' 'custom field' 'cf-<card' 'session_rename'; do
    grep -qF "$s" "$SKILL_GEN" || fail "c12: the boards skill never states the intake fact '$s'"
  done
  grep -qF 'SESSION_URL_BASE' "$SKILL_GEN" \
    || fail "c12: the boards skill lost the config constant name"
  # cf-50 round 2 (D18/D25-r2): the intake-D20 literal is a proven dead host
  # (coderd answers it 400 — malformed app-host grammar), so PRESENCE is now
  # the defect: the old VERBATIM sub-pin flips to absence pins plus the
  # dynamic-resolution phrases the origin block ships.
  if grep -qF 'openchamber--dev-thehackmeister-coder' "$SKILL_GEN"; then
    fail "c12: the dead intake-D20 host literal is present in the boards skill — cf-50 D25 r2: absence is correctness, not drift"
  fi
  if grep -qF 'SESSION_URL_BASE = https://' "$SKILL_GEN"; then
    fail "c12: SESSION_URL_BASE is hard-coded again — the value must be THIS run's Session origin: line (cf-50 D18 r2)"
  fi
  grep -qF 'Session origin:' "$SKILL_GEN" \
    || fail "c12: the skill lost the dynamic SESSION_URL_BASE resolution source (the run's Session origin: line)"
  grep -qF 'VSCODE_PROXY_URI' "$SKILL_GEN" \
    || fail "c12: the skill lost the Coder app-origin env the command blocks derive from (cf-50 D19 r2)"
  grep -qF '?session=' "$SKILL_GEN" \
    || fail "c12: the session-link path format (OpenChamber router, research §10) is missing"
  grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag|omits/nulls' "$SKILL_GEN" \
    || fail "c12: the skill never retires the run tag for card-driven runs (D10/retirement rule)"
  python3 "$TMP/neg12.py" "$SKILL_GEN" \
    || fail "c12: a line pairs 'models' with 'custom field' without negating it — D12 dropped the models field (phrase the negation explicitly, e.g. 'no third field; routing rides the Model(s) checklist')"
  ok "c12: slug/session custom fields + cf- slug rule + dead-literal ABSENCE + dynamic Session-origin phrases + run-tag retirement; no models/custom-field pairing"
fi

# --- c13: research-only iterative loop (C02 AC1, D14/D15/D19) ------------------
if want c13; then
  python3 "$TMP/window.py" "$SKILL_GEN" 600 'Research' 'label' 'case-insensitiv' \
    || fail "c13: the Research-LABEL trigger is not stated as the (only, case-insensitive — D14/D18) detector"
  grep -qF 'agent-research' "$SKILL_GEN" || fail "c13: the research-only loop never names agent-research"
  grep -qiE '(never|not)[^.]{0,80}(planner|agent-plan)' "$SKILL_GEN" \
    || fail "c13: the skill must state research-only cards do not reach the planner/plan-test-dev-review chain"
  grep -qE 'follow-up' "$SKILL_GEN" || fail "c13: the ONE batched follow-up question round (D15 step 3) is missing"
  grep -qiE 'at most one[^.]*follow-up|one follow-up round' "$SKILL_GEN" \
    || fail "c13: the default termination (at most one follow-up round, then wrap) is missing"
  grep -qF 'sessionID' "$SKILL_GEN" \
    || fail "c13: further research must continue the SAME agent-research session via its sessionID (D15 step 4)"
  ok "c13: research-only chain greppable — label trigger, agent-research, one follow-up round, same-session continuation, never to the planner"
fi

# --- c14: D11 resume-vs-sequential-new-run (C02 AC1) ---------------------------
if want c14; then
  grep -qF 'plan_status' "$SKILL_GEN" \
    || fail "c14: the resume rule must key on the existing folder's plan_status (D11)"
  grep -qiE 'resume' "$SKILL_GEN" || fail "c14: no resume phrasing for unfinished runs"
  grep -qF '<slug>-1' "$SKILL_GEN" && grep -qF '<slug>-2' "$SKILL_GEN" \
    || fail "c14: re-picking a COMPLETED run must mint the sequential <slug>-1, <slug>-2, … (D11)"
  ok "c14: D11 resume rule present (plan_status-not-complete resumes; completed runs continue as <slug>-N)"
fi

# --- c15: C01's pinned tool names in the write-back steps (C02 AC1) ------------
if want c15; then
  for t in 'list_custom_fields' 'set_card_custom_field' 'delete_checklist_item'; do
    grep -qF "$t" "$SKILL_GEN" \
      || fail "c15: the skill does not name $t — C01 pinned these names as the C02/C03 contract (D2)"
  done
  ok "c15: the write tools (list_custom_fields / set_card_custom_field / delete_checklist_item) are named in the skill"
fi

# --- c16: agent body + command carry the redesigned intake (C03 AC1) -----------
if want c16; then
  awk 'c>=2{print} /^---$/{c++}' "$AGENT_GEN" >"$TMP/agent-body.md"
  for f in "$TMP/agent-body.md" "$CMD_GEN"; do
    grep -qF 'Rework → Not Started → Low Priority' "$f" \
      || fail "c16: $f lacks the pinned pickup sequence 'Rework → Not Started → Low Priority'"
    grep -qF 'research-only' "$f" || fail "c16: $f never mentions the research-only branch"
    grep -qF 'Review.' "$f" || fail "c16: $f never states the Review-list exit (the board's list is named Review)"
    grep -qF 'Research' "$f" || fail "c16: $f never names the Research label"
  done
  grep -qF 'cf-<card' "$TMP/agent-body.md" \
    || fail "c16: the agent body does not carry the cf-<card-… slug rule (D10)"
  grep -qE 'worktree' "$TMP/agent-body.md" && grep -qE 'branch' "$TMP/agent-body.md" \
    || fail "c16: the agent body must state the slug names folder/worktree/branch (D10)"
  grep -qF 'Model(s) checklist' "$TMP/agent-body.md" \
    || fail "c16: the agent body does not route models from the Model(s) checklist (D12 — the sole routing input)"
  grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag' "$TMP/agent-body.md" \
    || fail "c16: the agent body never retires the run tag for card-driven runs"
  python3 "$TMP/neg12.py" "$TMP/agent-body.md" \
    || fail "c16: agent body pairs 'models' with 'custom field' without negating it (D12)"
  grep -qE 'slug' "$CMD_GEN" && grep -qE 'session' "$CMD_GEN" \
    || fail "c16: the command never mentions the slug/session custom-field intake"
  ok "c16: agent body + command mirror the skill's pinned strings (pickup order, research-only exit, cf-slug/no-run-tag, checklist intake)"
fi

# --- c17: pipeline-models / pipeline-gates byte-unchanged ----------------------
# D1 + C02 AC4: the board flow overrides the kickoff QUESTIONS from the skill
# text; the models/gates sources stay untouched through this whole ticket, so
# any diff on them is scope escape. cf-52 RE-PIN: pipeline-kickoff and
# pipeline-role-coord LEAVE the byte set — cf-52 legitimately re-opens them
# with the in-work/done authority (D6/D10, cf-50 D21 posture); their content
# is guarded by tests/coord-inwork/surface.sh i1/i2, not by invariance here.
if want c17; then
  if ! git diff --quiet "$BASE" -- \
      .rulesync/skills/pipeline-models .rulesync/skills/pipeline-gates \
      .opencode/skills/pipeline-models .opencode/skills/pipeline-gates 2>/dev/null; then
    git diff --name-only "$BASE" -- .rulesync/skills/pipeline-models .rulesync/skills/pipeline-gates \
      .opencode/skills/pipeline-models .opencode/skills/pipeline-gates >&2
    fail "c17: a pipeline-models/pipeline-gates file changed vs $BASE (they stay byte-pinned; only kickoff/role-coord were re-opened by cf-52 D10)"
  fi
  ok "c17: pipeline-models and pipeline-gates (source + generated) are byte-unchanged vs $BASE (kickoff/role-coord re-opened by cf-52, i1/i2-guarded)"
fi

printf 'PASS: agent-board-coord rulesync-surface checks (%d ok)\n' "$checks"
