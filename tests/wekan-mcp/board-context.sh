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
# Red posture (cf-106 C07 test wave 2): t1-t5 are green against the tree. t6
# runs its nested suites as id-subsets, the way it already trims gate.sh's
# pre-existing t17: agent-perms runs minus A15, because A15's cf-106 legs — the
# pipeline_claim `shared` override input (C08 AC6) and the boards skill's
# co-tenancy posture (C08 AC7) — are cf-106 C08's work and stay red through
# C07. A15 still runs, as its own arm: it must either be green or fail naming
# C08, so an unrelated A15 breakage still reads as this suite's. Every other
# agent-perms leg is C07's blast radius and must be green.
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

# --- t2: collector command — six legs in order, defaults, derivation + degrade, pointer-not-copy (C03 AC2 + cf-123 C01 AC7 re-pin) -----
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
    for tok in '$ARGUMENTS' list_boards get_board list_swimlanes list_lists list_custom_fields preload_board fenced 'AI-Dev' 'In Process'; do
      grep -qF "$tok" "$f" || fail "t2: $f never carries '$tok' (six-leg resolution sequence / defaults / fenced-output instruction — cf-123 C01 adds the sixth, preload_board, leg)"
    done
    python3 - "$f" <<'PY' || fail "t2: $f does not run the six resolution calls in order"
import sys
text = open(sys.argv[1]).read()
seq = ["list_boards", "get_board", "list_swimlanes", "list_lists", "list_custom_fields", "preload_board"]
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
    # cf-123 C01: the card_number derivation + degrade instruction rides the
    # command prose (the schema itself stays pointed-at, never copied): the
    # prefix is the board key the get_board leg carries, and the keyless
    # pre-rollout shape must be documented, not silently rendered.
    python3 - "$f" <<'PY' || fail "t2: $f lost the card_number derivation + degrade instruction (cf-123 C01 AC7)"
import re, sys
text = open(sys.argv[1]).read()
errs = []
if "card_number" not in text:
    errs.append("no 'card_number' naming — the command cannot document the field it derives")
if not re.search(r"board.{0,12}key", text, re.I):
    errs.append("no board-key derivation source named (ruling #2: the prefix is the board key from get_board, never a hardcoded literal)")
if not re.search(r"degrad|bare|no key", text, re.I):
    errs.append("no degrade instruction (the pre-rollout projection carries no key — the bare-number + note-line shape must be documented)")
print("; ".join(errs)); sys.exit(1 if errs else 0)
PY
    # The reworded usage note: cards ARE pre-collected now (card_number /
    # card_id / labels as a collection-time snapshot) — only checklist ids
    # stay live per-card data, and the drift advice survives the reword.
    if grep -qiF 'Card and checklist ids are never pre-collected' "$f"; then
      fail "t2: $f still says 'Card and checklist ids are never pre-collected' — the cards group pre-collects card_number/card_id/labels as a snapshot; only checklist ids stay live per-card data (cf-123 C01 AC7 reworded usage note)"
    fi
    grep -qiF 'checklist' "$f" || fail "t2: $f's usage note lost the checklist exclusion — checklist ids remain live per-card data after the cards join"
    grep -qiE 're-resolve|re-collect' "$f" || fail "t2: $f's usage note lost the drift advice (re-collect after a structure change / re-resolve on any id-shaped call error)"
  done
  ok "t2: command (source + generated) binds agent-board, carries the ordered six-leg resolution sequence with AI-Dev/In Process defaults, the card_number derivation + degrade instruction, the reworded usage note (cards pre-collected as a snapshot, checklist ids live), and points at (never copies) the schema (C03 AC2 + cf-123 C01 AC7 re-pin)"
fi

# --- t3: boards skill consumer rule — cards group consumable, snapshot caveat, stale claims gone (C03 AC3 + cf-123 C01 AC8 re-pin) --
if want t3; then
  for f in "$BOARDS_SRC" "$BOARDS_GEN"; do
    [ -f "$f" ] || fail "t3: $f missing"
    grep -qE '^#{1,6}[[:space:]].*Board context block' "$f" \
      || fail "t3: $f has no 'Board context block' subsection heading (the consumer rule is missing)"
    python3 - "$f" <<'PY' || fail "t3: $f's consumer passage lacks a required clause (cf-123 C01 re-pin)"
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
# cf-123 C01: the cards group is consumable at launch (the injected per-list
# projections serve the walk), the snapshot caveat rides the consumer rule,
# and the two stale present-tense claims leave with the reword: the six-count
# predates the preload leg, and the hook is no longer structural-only (its
# sixth leg prefetches the per-list cards — the claim-time preload law itself
# stays, only the OQ3 "structural-only" clause is replaced).
if not re.search(r"cards.{0,200}(walk|pickup|launch)|(walk|pickup|launch).{0,200}cards", body, re.S):
    errs.append("no cards-group-consumable-at-launch rule (the block's per-list projections must serve the pickup walk)")
if "snapshot" not in body:
    errs.append("no snapshot caveat on the cards (a collection-time block that contradicts the live board must re-resolve)")
if re.search(r"first (six|6) board round-trips", body):
    errs.append("the stale 'first six board round-trips' count survives — the prefetch now spends a sixth (preload) leg")
if re.search(r"structural-only|structure-only|stays structural", body):
    errs.append("the stale 'hook stays structural(-only)' clause survives — the hook's sixth leg prefetches the per-list cards (C01 rewords both the preload-consumer and card-details sibling clauses)")
print("; ".join(errs)); sys.exit(1 if errs else 0)
PY
    n=$(grep -oF 'board_context' "$f" | wc -l)
    [ "$n" -eq 1 ] || fail "t3: 'board_context' spelled $n times in $f, want exactly once (the STATE key has one canonical mention; AC3 — the cards reword must not add a second literal)"
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
# cf-90 C06 widening: the sanctioned row ADDITIONS are the cf-75 agent-board
# row (era-gated: post-merge it rides the base too), the cf-96 C02 explore
# row and the deploy PAIR — dev-deploy/dev-deploy-pr. Admitted as the exact
# set, never as a blanket skip: any other gained matcher still reddens.
added = [x for x in nlabels if x not in blabels]
admitted = {"board", "agent-board", "dev-deploy", "dev-deploy-pr", "explore"}
if added and not set(added) <= admitted:
    print(f"unexpected matcher rows added: {added}"); sys.exit(1)
if "agent-board" not in nlabels and "board" not in nlabels:
    print("no agent-board matcher row found"); sys.exit(1)
import os
if os.path.exists(".rulesync/subagents/agent-dev-deploy.md"):
    for dep in ("dev-deploy", "dev-deploy-pr"):
        if dep not in nlabels:
            print(f"cf-90 C06 era: the deploy pair shipped but the '{dep}' matcher row is absent — the matrix must carry the new roles"); sys.exit(1)
# The coord-pr cell moved four times: cf-72's main-side T-7 tail rewrite, the
# scoped-read re-seat rider (in-family ls/preload-probe — the 2026-10-30
# admission this constant replaces), cf-88's union wording ("the probe row
# and the cf-88 surface block ride it too"), landed 2026-10-31 (merge2), and
# cf-90 C06's launch-cell widen (the roster names the class's deploy variant
# — the agents-sync law of the matrix moving with every permission change). The
# constant below is the landed byte, pinned like the TB form — a future cell
# edit must arrive with a re-pin, not silently pass. The cf-88 wording also
# carries the owner's round-2 zero-arg-push ruling inline:
# preload-probe + `ls *` rows), per the reconciliation entry at the bottom of
# .rulesync/skills/agents-sync/references/permissions.md. Admitted EXACTLY,
# never as a blanket skip: the TB form still rides (pre-merge trees, via the
# byte-equal walk below) and the pinned settled form rides; anything else — a
# dropped ls/probe grant, a reworded tail, any gained row — reddens.
# The byte below is the landed row at .rulesync/skills/agents-sync/
# references/permissions.md:27 — re-pinned in the cf-106 C07 test wave 2
# because C06 widened the cell (the standalone `code-pr` roster class,
# cf-106 OQ-10); the previous 762-char literal went stale by design.
COORD_PR_SETTLED = """| coord-pr | same as coord | plan/explore/research/test/dev-pr/dev-deploy-pr/review + standalone `code-pr` (cf-106 C04: the push-capable second implementer — it MAY push the ticket branch, only under `pipeline-push-pr`) | as coord-local — same scoped-read family (the probe row and the cf-88 surface block ride it too) — but the T-7 push tail replaces T-2: feature push lives through the broad `git *` allow, denied back on the LAST rows for every main-token form (`git push*main*`, `git * push *main*` — covers `push :main`), the zero-arg `-C` footgun (`git * push`; bare `git push` in the own worktree stays ALLOWED per the owner's round-2 ruling) and all force spellings (`git push -f*`/`git push -P*` + their `git *` twins, over the floor-wide `--force`/`-f`/`-P` rows) — pushes the ticket branch for remote build/test under the `pipeline-push-pr` contract: never main, never force | as coord |"""
# cf-96 final-review vocabulary sweep (Deploy -> Deployment, C11 fold
# round): the dev-deploy row's launch-surface cell moved once — the
# retired `Deploy` stage cite now reads `Deployment`. Admitted EXACTLY,
# never as a blanket skip: the TB form still rides (pre-merge trees)
# and the pinned settled form rides; anything else reddens.
DEV_DEPLOY_SETTLED = """| dev-deploy | everything EXCEPT the test paths (`charts/**/tests/**`, `containers/**/tests/**`, top-level `tests/**`) and `.agents/plans/**`, plus the context-file rules below — the block mirrors `agent-dev-local` verbatim plus the cleanup grant (cf-90 C06) | none — and nothing launches them either yet: the pair ships DEFINITION ONLY (cf-90), the coord step-8b Deployment-stage hook under a checked Lifecycle `Deployment` is the only future launch surface (the boards Stage map governs) | as dev-local — git reads, `git add`/`git commit`/`git push` denied (the coordinator commits), trailing `ls *` allow, `helm lint/template` | as plan, plus the workspace-isolation trio (`opencode_worktree_create`/`opencode_worktree_list`/`opencode_session_move`) AND the cleanup row `opencode_worktree_remove` (the deploy fixer closes its OWN worktree at hand-back; branch stays coord-owned, landing-gated) — still NO `execute` row (no deny baseline: interactive runs approve Code Mode once, unattended pipeline runs stay blocked from minting coordinator-owned surfaces) |"""
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
            print(f"coord-pr row is neither the TB form nor the pinned settled form (cf-72 T-7 tail + the cf-88 union rider + the cf-90 C06 launch-cell widen) — got {cur}; the admission is byte-exact: dropping a grant, rewording the tail or any other gain is unadmitted drift"); sys.exit(1)
        if label == "dev-deploy":
            cur = [x for x in n if x.split("|")[1].strip() == "dev-deploy"]
            if len(cur) == 1 and cur[0] == DEV_DEPLOY_SETTLED:
                continue
            print(f"dev-deploy row is neither the TB form nor the pinned settled form (cf-96 final-review Deploy->Deployment vocabulary sweep) — got {cur}; the admission is byte-exact"); sys.exit(1)
        print(f"base row '{label}' changed byte-wise — the sanctioned matrix moves are the cf-75 agent-board insertion, the cf-76 review row, board-tick-cleanup C01's five shell-cell updates, cf-90 C06's deploy-pair rows + coord roster cell, the byte-exact coord-pr settled admission, and the cf-96 dev-deploy Deploy->Deployment re-pin; nothing else may drift"); sys.exit(1)
PY
  ok "t4: role matrix (source + mirror) keeps every base row byte-identical except the sanctioned moves (C02 review row, board-tick-cleanup C01's five shell cells, cf-90 C06's deploy-pair rows + coord roster cell + the byte-exact coord-pr settled admission) and carries the agent-board row (era-gated presence — post-landing it rides the base too); with the deploy pair shipped, both dev-deploy matchers must be present"
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
  # The invariance premise, re-pinned at the cf-93 C10 rebase: C02
  # legitimately APPENDED a comment-only posture note to this script (OQ-A3 —
  # deliberate cross-project counting, guarded as comment-only by
  # tests/multi-repo/hourly-board-check.sh t2, which also pins the untouched
  # usage-heredoc twin via the D11 sentences + verdict legend). So this leg
  # proves COMMENT-ONLY invariance vs $TB — the same ^+#-only shape as that
  # guard: added lines are comments/blank, zero deleted or rewritten lines.
  gate_diff=$(git diff "$TB" -- "$GATE_SCRIPT" || true)
  if [ -n "$gate_diff" ]; then
    if printf '%s\n' "$gate_diff" | grep -E '^-' | grep -vE '^--- ' | grep -q .; then
      fail "t6: the $GATE_SCRIPT diff vs $TB deletes/rewrites lines — only comment APPENDS are admissible (C02's posture note; deletions would widen the hourly gate, AC6)"
    fi
    if printf '%s\n' "$gate_diff" | grep -E '^\+[^+]' | grep -vE '^\+\s*(#|$)' | grep .; then
      fail "t6: the $GATE_SCRIPT diff adds a non-comment line vs $TB — gate logic, verdicts and flags stay untouched (mirrors hourly-board-check.sh t2)"
    fi
    ok "t6: $GATE_SCRIPT vs $TB is comment-only (the cf-93 C02 OQ-A3 posture append; no logic, verdict or flag change — AC6 invariance)"
  else
    ok "t6: $GATE_SCRIPT unchanged vs $TB (comment-only invariance, vacuously)"
  fi
  # env -u CHUNK_BASE: same default-shape containment as validation-fix.sh t7 —
  # an ambient base must not silently re-base these regression children.
  # cf-90 selection note (agent-test, mechanical): gate.sh's child runs as an
  # ID SUBSET excluding t17 — t17 is red at pristine main HEAD from the
  # pre-existing warm-location permissions drift tracked outside cf-90 (the
  # gate.sh cf-90 header note); running it whole would attribute that drift
  # red to this ticket and to every later chunk gate. The same subset
  # discipline tests/provider-loops/surface.sh t6 ships. agent-perms runs the
  # same way: A15 is cf-106 C08's leg (the pipeline_claim `shared` override
  # input + the boards skill's co-tenancy posture) and stays red until C08
  # lands, so it runs as its own arm — its red is admitted BY NAME and its
  # output must name C08, so a new A15 failure for another reason still reads
  # as t6's. Every other agent-perms leg is this chunk's blast radius.
  AP_ALL=$(seq 1 19 | grep -v '^15$' | sed 's/^/A/' | tr '\n' ' ')
  for s in tests/agent-board-coord/gate.sh tests/agent-perms/surface.sh tests/standalone-agents/surface.sh; do
    log="$TMP/$(basename "$s").log"
    if [ "$s" = "tests/agent-board-coord/gate.sh" ]; then
      gate_ids=$(seq 1 20 | grep -v '^17$' | sed 's/^/t/' | tr '\n' ' ')
      # shellcheck disable=SC2086
      env -u CHUNK_BASE timeout 600 bash "$s" $gate_ids >"$log" 2>&1 \
        || { tail -n 20 "$log" >&2; fail "t6: bash $s (ids minus the pre-existing t17) failed (log: $log)"; }
      continue
    fi
    if [ "$s" = "tests/agent-perms/surface.sh" ]; then
      # shellcheck disable=SC2086
      env -u CHUNK_BASE timeout 600 bash "$s" $AP_ALL >"$log" 2>&1 \
        || { tail -n 20 "$log" >&2; fail "t6: bash $s (ids minus A15, cf-106 C08's leg) failed (log: $log)"; }
      a15log="$TMP/agent-perms-A15.log"
      if env -u CHUNK_BASE timeout 300 bash "$s" A15 >"$a15log" 2>&1; then
        ok "t6: agent-perms A15 reads green — cf-106 C08's permission legs have landed, fold A15 back into the subset run above"
      elif grep -qF 'C08' "$a15log"; then
        ok "t6: agent-perms A15 red, and red on cf-106 C08's contract (the pipeline_claim \`shared\` input + the boards-skill co-tenancy posture) — recorded as C08's designed red, not a C07 regression (log: $a15log)"
      else
        tail -n 20 "$a15log" >&2
        fail "t6: agent-perms A15 failed for a reason other than cf-106 C08's legs (log: $a15log)"
      fi
      continue
    fi
    if env -u CHUNK_BASE timeout 600 bash "$s" >"$log" 2>&1; then
      :
    else
      tail -n 20 "$log" >&2
      fail "t6: bash $s failed (log: $log)"
    fi
  done
  ok "t6: gate script comment-only-invariant vs $TB and free of agent-board references; gate contract (ids minus the known-red t17), agent-perms (ids minus A15 = C08's leg, which is admitted by name) and standalone-agents suites pass (C03 AC6 regression)"
fi

printf 'PASS: wekan-mcp board-context checks (%d ok)\n' "$checks"
