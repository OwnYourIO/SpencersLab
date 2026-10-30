#!/usr/bin/env bash
# agent-board + /wekan-board-context collector contract
# (2026/2026-10-cf-75-bug-wekan-mcp-skill, C03): the board-MCP worker agent
# (generated surface, deny-all baseline, dev-boards* as its ONLY MCP grant —
# hyphen spelling, no global-wekan fallback per OQ7; board-tick-cleanup C01's
# OQ9 ruling adds the one trailing `ls *` shell allow after the shell deny,
# gated in t1), the collector command
# (six-step resolution sequence, AI-Dev/In Process defaults, fenced output,
# pointer-not-copy of the C01 schema), the boards-skill consumer rule (additive
# — the rulesync-surface pinned section titles must survive), the agent-board
# permissions-matrix row (additive to the base matrix), and proof the hourly
# gate was NOT widened for agent-board (it is not a coordinator).
#
# Contract source: chunks/C03.md "## Tests". AC trace: t1[AC1] t2[AC2]
# t3[AC3] t4[AC4] t5[AC6-regen/commit-shape] t6[AC6-regression].
# Live smoke [AC5] is dev+review run, not asserted here — D8: no network in
# suites.
#
# Red before C03: every check fails on a missing file/row, naming the absent
# contract. The rulesync-surface c8 / agents-md c7 / gate t14 scope admits for
# this ticket landed at the test phase (agent-test's prerogative, cf-50
# precedent), so HOLD posture after C01/C02 land.
#
# Usage:
#   bash tests/wekan-mcp/board-context.sh            # t1..t6
#   bash tests/wekan-mcp/board-context.sh t1 t5      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

AGENT_SRC=".rulesync/subagents/agent-board.md"
AGENT_GEN=".opencode/agents/agent-board.md"
CMD_SRC=".rulesync/commands/wekan-board-context.md"
CMD_GEN=".opencode/commands/wekan-board-context.md"
BOARDS_SRC=".rulesync/skills/boards/SKILL.md"
BOARDS_GEN=".opencode/skills/boards/SKILL.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"
RULESYNC_SUITE="tests/agent-board-coord/rulesync-surface.sh"
GATE_SCRIPT="scripts/agent-board-coord-gate.sh"
HEADER='Board context (collected'
TB=$(git merge-base main HEAD 2>/dev/null || git rev-parse HEAD)

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/board-context-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-6])$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: generated agent-board — frontmatter + asserted permission sets (AC1) ----
if want t1; then
  [ -f "$AGENT_SRC" ] || fail "t1: $AGENT_SRC missing (source+output land together — AC1)"
  [ -f "$AGENT_GEN" ] || fail "t1: $AGENT_GEN missing (the generated surface is what the client loads)"
  python3 - "$AGENT_GEN" <<'PY' || fail "t1: agent-board frontmatter violates the permission contract (reason above)"
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "t1: no YAML frontmatter"
fm = yaml.safe_load(m.group(1))
errs = []
if fm.get("name") != "agent-board":
    errs.append(f"name is {fm.get('name')!r}, want agent-board")
if fm.get("mode") != "primary":
    errs.append(f"mode is {fm.get('mode')!r}, want primary")
perms = fm.get("permissions") or []
deny = {"action": "*", "resource": "*", "effect": "deny"}
if not perms or perms[0] != deny:
    errs.append("leading deny-all baseline row missing (deny-all first or the grants do not resolve under last-match-wins)")
allows = [p for p in perms if p.get("effect") == "allow"]
# The chunk asserts the allow set EXACTLY: read areas, skill, question,
# execute, and dev-boards* as the only MCP grant. Anything extra (a dev*,
# a readonly*, an edit) is a privilege deviation, not a draft. Shell's ONE
# exception is board-tick-cleanup C01 (OQ9 user ruling): a trailing `ls *`
# allow sitting AFTER the shell-'*' deny. ls_gate owns count, exact shape
# and position for EVERY shell allow — no other shell grant can slip past
# it — which is what lets the action-set arm below discount shell without
# widening the ban (mirror of the t4 sanctioned-moves treatment).
LS_ALLOW = {"action": "shell", "resource": "ls *", "effect": "allow"}
SHELL_DENY = {"action": "shell", "resource": "*", "effect": "deny"}
shell_allows = [p for p in perms if p.get("action") == "shell" and p.get("effect") == "allow"]
deny_at = next((i for i, p in enumerate(perms) if p == SHELL_DENY), None)
ls_gate_ok = (not shell_allows) or (
    len(shell_allows) == 1 and shell_allows[0] == LS_ALLOW
    and deny_at is not None and perms.index(LS_ALLOW) > deny_at)
if not ls_gate_ok:
    errs.append(f"shell allows {shell_allows}, want none or exactly the one 'ls *' allow AFTER the shell '*' deny (C01/OQ9 read-only exception — last-match-wins only grants ls reads)")
want_actions = sorted({"read", "skill", "question", "execute", "dev-boards*"})
got_actions = sorted({p.get("action") for p in allows if p.get("action") != "shell"})
if got_actions != want_actions:
    errs.append(f"allow actions {got_actions}, want exactly {want_actions}")
if not any(p.get("action") == "question" and p.get("resource") == "*" for p in allows):
    errs.append("explicit question '*' allow missing (repo hard rule)")
mcp_allows = [p for p in allows if p.get("action") == "dev-boards*"]
if len(mcp_allows) != 1 or mcp_allows[0].get("resource") != "*":
    errs.append(f"dev-boards* allow rows: {mcp_allows}, want exactly one with resource '*'")
for banned in ("dev*", "readonly*", "admin*", "global*", "global-wekan*"):
    if any(p.get("action") == banned and p.get("effect") == "allow" for p in perms):
        errs.append(f"broad/forbidden MCP allow {banned!r} present (OQ7: dev-boards* ONLY)")
for action in ("shell", "edit", "subagent"):
    # shell allows are adjudicated by ls_gate above (the era before C01 — no
    # shell allow at all — also passes); edit and subagent stay unconditional
    # family-spec bans. The '*' DENY row stays mandatory for all three: C01
    # appends a read grant, it never removes a denial.
    if action != "shell" and any(p.get("action") == action and p.get("effect") == "allow" for p in perms):
        errs.append(f"{action} allow present — the family spec denies it")
    if not any(p.get("action") == action and p.get("resource") == "*" and p.get("effect") == "deny" for p in perms):
        errs.append(f"{action} '*' deny row missing (explicit denial, not fallthrough)")
if "dev_boards" in text:
    errs.append("underscore respelling dev_boards appears — MCP tool ids keep the hyphen (lesson 9deea82db)")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
  ok "t1: generated agent-board — name/mode, deny-all baseline, allow set exactly read/skill/question/execute/dev-boards* with at most the one C01 trailing 'ls *' shell allow gated to sit after the shell-'*' deny, shell+edit+subagent '*' denies kept, no underscore or broad MCP grant (C03 AC1 + C01/OQ9 read-only exception)"
fi

# --- t2: collector command — sequence, defaults, pointer-not-copy (C03 AC2) -----
if want t2; then
  for f in "$CMD_SRC" "$CMD_GEN"; do
    [ -f "$f" ] || fail "t2: $f missing"
  done
  python3 - "$CMD_GEN" <<'PY' || fail "t2: generated command frontmatter does not bind agent-board"
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1))
if fm.get("agent") != "agent-board":
    print(f"agent is {fm.get('agent')!r}, want agent-board"); sys.exit(1)
PY
  for f in "$CMD_SRC" "$CMD_GEN"; do
    for tok in '$ARGUMENTS' list_boards get_board list_swimlanes list_lists list_custom_fields fenced 'AI-Dev' 'In Process'; do
      grep -qF "$tok" "$f" || fail "t2: $f never carries '$tok' (resolution sequence / defaults / fenced-output instruction)"
    done
    python3 - "$f" <<'PY' || fail "t2: $f does not run the five resolution calls in order"
import sys
text = open(sys.argv[1]).read()
seq = ["list_boards", "get_board", "list_swimlanes", "list_lists", "list_custom_fields"]
pos = [text.find(s) for s in seq]
if any(p < 0 for p in pos):
    print(f"missing calls: {[s for s, p in zip(seq, pos) if p < 0]}"); sys.exit(1)
if pos != sorted(pos):
    print(f"order violated: {list(zip(seq, pos))}"); sys.exit(1)
PY
    grep -qF 'wekan-mcp' "$f" || fail "t2: $f never points at the C01 skill (the schema's single normative home)"
    if grep -qF "$HEADER" "$f"; then
      fail "t2: $f copies the canonical schema header — pointer to the skill only (one normative owner, DECISIONS 2026-10-27)"
    fi
  done
  ok "t2: command (source + generated) binds agent-board, carries the ordered six-step resolution sequence with AI-Dev/In Process defaults and the fenced-output note, and points at (never copies) the schema (C03 AC2)"
fi

# --- t3: boards skill consumer rule — additive over the pinned titles (C03 AC3) --
if want t3; then
  for f in "$BOARDS_SRC" "$BOARDS_GEN"; do
    [ -f "$f" ] || fail "t3: $f missing"
    grep -qE '^#{1,6}[[:space:]].*Board context block' "$f" \
      || fail "t3: $f has no 'Board context block' subsection heading (the consumer rule is missing)"
    python3 - "$f" <<'PY' || fail "t3: $f's consumer passage lacks a required clause"
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'(?ms)^#+[^\n]*Board context block[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print("consumer section body not found"); sys.exit(1)
body = m.group(1).lower()
errs = []
if "consumer" not in body and "consumer" not in m.group(0).lower():
    errs.append("no 'consumer' naming")
if not re.search(r"re.?resolve", body):
    errs.append("no on-id-error re-resolve clause (board structure drifts — the block is a starting context only)")
if "board_context" not in body:
    errs.append("no kickoff.board_context STATE.json naming")
if "wekan-board-context" not in body:
    errs.append("no pointer to the /wekan-board-context producer")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
    n=$(grep -oF 'board_context' "$f" | wc -l)
    [ "$n" -eq 1 ] || fail "t3: 'board_context' spelled $n times in $f, want exactly once (the STATE key has one canonical mention; AC3)"
  done
  # Re-pin posture: the pinned section titles are rulesync-surface c4's
  # fixture — extract them live from that suite instead of restating the
  # list, so the two guards can never drift apart.
  python3 - "$RULESYNC_SUITE" "$BOARDS_GEN" <<'PY' || fail "t3: pinned boards-skill titles violated (reason above)"
import re, sys
suite = open(sys.argv[1]).read()
m = re.search(r'^\s*for title in (.*?); do', suite, re.M)
assert m, "could not find the c4 title fixture in rulesync-surface.sh — the containment source moved, update this extractor deliberately"
titles = re.findall(r"'([^']+)'", m.group(1))
assert titles, "empty title fixture parse"
text = open(sys.argv[2]).read()
missing = [t for t in titles if not re.search(r"^#{1,6}[^\n]*" + re.escape(t), text, re.M | re.I)]
if missing:
    print(f"pinned section titles lost from the generated boards skill: {missing}"); sys.exit(1)
print(f"(c4 fixture: {len(titles)} titles contained)")
PY
  ok "t3: consumer rule present on source + mirror with re-resolve/board_context/producer-pointer clauses, key spelled once; c4 pinned titles survive (containment vs the live fixture)"
fi

# --- t4: permissions matrix gains the agent-board row; base rows hold ----------
if want t4; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    grep -qE '^\|[[:space:]]*(agent-)?board[[:space:]]*\|' "$f" \
      || fail "t4: $f has no agent-board ('| board |' or '| agent-board |') row in the role matrix (C03 AC4)"
    grep -qF 'dev-boards' "$f" || fail "t4: $f does not document the dev-boards grant on the new row"
  done
  git show "$TB:$PERM_SRC" >"$TMP/perm-base.md" 2>/dev/null || fail "t4: cannot read the ticket-base permissions.md ($TB) — the matrix diff anchor"
  python3 - "$TMP/perm-base.md" "$PERM_SRC" <<'PY' || fail "t4: the base matrix rows did not survive additively (reason above)"
import sys
base = open(sys.argv[1]).read().splitlines()
new = open(sys.argv[2]).read().splitlines()
def rows(lines):
    out, started = [], False
    for l in lines:
        if l.startswith("| role |"):
            started = True
            continue
        if started:
            if not l.startswith("|"):
                break
            out.append(l)
    return out
b, n = rows(base), rows(new)
blabels = [r.split("|")[1].strip() for r in b]
nlabels = [r.split("|")[1].strip() for r in n]
# Base matchers must survive in order; the agent-board row's DELIVERY posture
# is era-gated (mechanical repair, board-tick-cleanup test wave): at cf-75's
# own base the row was the sanctioned single ADDITION; with cf-75 merged to
# main it rides every later TB, so presence — already grep-pinned — plus
# "no OTHER unexplained row appeared vs the base" is the permanent form.
missing = [x for x in blabels if nlabels.count(x) < 1]
if missing:
    print(f"base matchers lost: {missing}"); sys.exit(1)
added = [x for x in nlabels if x not in blabels]
if added and not (len(added) == 1 and added[0] in ("board", "agent-board")):
    print(f"unexpected matcher rows added: {added}"); sys.exit(1)
if "agent-board" not in nlabels and "board" not in nlabels:
    print("no agent-board matcher row found"); sys.exit(1)
# The coord-pr cell moved twice in the 2026-10-30 merge round — cf-72's main-
# side T-7 tail rewrite plus the scoped-read re-seat rider (in-family
# preload-probe + `ls *` rows), per the reconciliation entry at the bottom of
# .rulesync/skills/agents-sync/references/permissions.md. Admitted EXACTLY,
# never as a blanket skip: the TB form still rides (pre-merge trees, via the
# byte-equal walk below) and the pinned settled form rides; anything else — a
# dropped ls/probe grant, a reworded tail, any gained row — reddens.
COORD_PR_SETTLED = """| coord-pr | same as coord | plan/research/test/dev-pr/review | as coord-local — same scoped-read family (the probe and `ls *` rows ride it too) — but the T-7 push tail replaces T-2: feature push lives through the broad `git *` allow, denied back on the LAST rows for every main-token form (`git push*main*`, `git * push *main*` — covers `push :main`), the zero-arg `-C` footgun (`git * push`; bare `git push` in the own worktree stays ALLOWED per the owner's round-2 ruling) and all force spellings (`git push -f*`/`git push -P*` + their `git *` twins, over the floor-wide `--force`/`-f`/`-P` rows) — pushes the ticket branch for remote build/test under the `pipeline-push-pr` contract: never main, never force | as coord |"""
for r in b:
    label = r.split("|")[1].strip()
    # The review row's wording is C02's sanctioned contract move (validated by
    # tests/pipeline-gates/validation-fix.sh). The coord/board-coord/agent-
    # board/dev-local/dev-pr cells move per board-tick-cleanup C01 (same-
    # commit matrix duty, plan Grounded facts W3 — the cells list the `ls *`
    # row). The coord-local/board-coord-local/board-coord-pr reference-idiom
    # cells stay byte-stable (measured 2026-10-30: coord-pr is the ONLY other
    # mover — its cell is literal prose, admitted byte-exactly via
    # COORD_PR_SETTLED, not skipped). Every other base row must survive
    # byte-identical.
    if label in ("review", "coord", "board-coord", "agent-board", "dev-local", "dev-pr"):
        continue
    if r not in n:
        if label == "coord-pr":
            cur = [x for x in n if x.split("|")[1].strip() == "coord-pr"]
            if len(cur) == 1 and cur[0] == COORD_PR_SETTLED:
                continue
            print(f"coord-pr row is neither the TB form nor the pinned settled form (cf-72 T-7 tail + the in-family ls/preload-probe rider) — got {cur}; the admission is byte-exact: dropping a grant, rewording the tail or any other gain is unadmitted drift"); sys.exit(1)
        print(f"base row '{label}' changed byte-wise — the sanctioned matrix moves are the cf-75 agent-board insertion, the cf-76 review row, board-tick-cleanup C01's five shell-cell updates, and the byte-exact coord-pr settled admission; nothing else may drift"); sys.exit(1)
PY
  ok "t4: role matrix (source + mirror) keeps every base row byte-identical except the sanctioned moves (C02 review row, board-tick-cleanup C01's five shell cells, the byte-exact coord-pr settled admission) and carries the agent-board row (era-gated presence — post-landing it rides the base too)"
fi

# --- t5: regen no-op + --check, and same-commit source/generated shape (AC6) ----
if want t5; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "t5: rulesync not resolvable here — regen gate skipped with warning (c7/t14 ladder precedent)"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "t5: rulesync generate --check not clean — generated surfaces stale"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || fail "t5: rulesync generate failed"
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "t5: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "t5: second rulesync generate is not a no-op (sources and generated drifted)"
  fi
  checked=0
  while read -r sha; do
    [ -n "$sha" ] || continue
    touched=$(git show --name-only --format= "$sha")
    src_hits=$(printf '%s\n' "$touched" | grep -E '^\.rulesync/(subagents/agent-board\.md|commands/wekan-board-context\.md|skills/boards/|skills/agents-sync/|rules/)' || true)
    [ -n "$src_hits" ] || continue
    gen_hits=$(printf '%s\n' "$touched" | grep -E '^\.opencode/(agents/|commands/|skills/)|^AGENTS\.md' || true)
    [ -n "$gen_hits" ] || { echo "$sha moves C03 sources ($src_hits) but no generated surface" >&2; fail "t5: source/generated split across commits — commit them together"; }
    checked=$((checked + 1))
  done < <(git log --format=%H "$TB..HEAD" 2>/dev/null || true)
  ok "t5: regen no-op + --check clean (via ${RS:-skipped}); commit-shape guard holds ($checked source commits in $TB..HEAD each carry their generated surfaces; vacuously green pre-landing)"
fi

# --- t6: hourly gate not widened; sibling suites green (C03 AC6 regression) -----
if want t6; then
  [ -f "$GATE_SCRIPT" ] || fail "t6: $GATE_SCRIPT missing"
  if grep -nE 'agent-board([^-]|$)' "$GATE_SCRIPT" >"$TMP/gatehits.txt"; then
    cat "$TMP/gatehits.txt" >&2
    fail "t6: agent-board-coord-gate.sh references agent-board — the hourly gate counts the three board-coord names ONLY (agent-board is not a coordinator; C03 AC6)"
  fi
  git diff --quiet "$TB" -- "$GATE_SCRIPT" || fail "t6: $GATE_SCRIPT changed since $TB — this ticket touches nothing in it (prove-by-diff, AC6)"
  # env -u CHUNK_BASE: same default-shape containment as validation-fix.sh t7 —
  # an ambient base must not silently re-base these regression children.
  for s in tests/agent-board-coord/gate.sh tests/agent-perms/surface.sh tests/standalone-agents/surface.sh; do
    log="$TMP/$(basename "$s").log"
    if env -u CHUNK_BASE timeout 600 bash "$s" >"$log" 2>&1; then
      :
    else
      tail -n 20 "$log" >&2
      fail "t6: bash $s failed (log: $log)"
    fi
  done
  ok "t6: gate script byte-untouched and free of agent-board references; gate/agent-perms/standalone-agents suites pass (C03 AC6 regression)"
fi

printf 'PASS: wekan-mcp board-context checks (%d ok)\n' "$checks"
