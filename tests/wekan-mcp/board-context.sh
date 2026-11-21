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
# (cf-126 C02 / OQ6 / DECISIONS D24 extension: the dispatch matcher row is
# admissible and era-REQUIRED once the dispatcher source ships, and the four
# frozen coord-family rows may visibly carry the widened truth — the coord-pr
# settled-bytes precedent mirrored in the walk.)
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
# cf-126 C02 (OQ-N1 review rule unchanged): the agents-sync matrix must also
# be able to gain the agent-board-dispatch ROW (the C01 dispatcher's
# permission surface documented by the C02 dev's same-commit matrix duty —
# the coord-pr settled-bytes precedent is the model for how such a row then
# gets byte-pinned by a later test round). Admitted as a label variant set,
# never as a blanket skip: any OTHER gained matcher still reddens.
added = [x for x in nlabels if x not in blabels]
admitted = {"board", "agent-board", "dev-deploy", "dev-deploy-pr", "explore",
            "agent-board-dispatch", "board-dispatch"}
if added and not set(added) <= admitted:
    print(f"unexpected matcher rows added: {added}"); sys.exit(1)
if "agent-board" not in nlabels and "board" not in nlabels:
    print("no agent-board matcher row found"); sys.exit(1)
import os
if os.path.exists(".rulesync/subagents/agent-dev-deploy.md"):
    for dep in ("dev-deploy", "dev-deploy-pr"):
        if dep not in nlabels:
            print(f"cf-90 C06 era: the deploy pair shipped but the '{dep}' matcher row is absent — the matrix must carry the new roles"); sys.exit(1)
# cf-126 era-gate (the same discipline as the deploy pair above): the
# dispatcher SOURCE shipped with C01; the matrix row is the C02 dev's
# same-commit duty (agents-sync drift law). Once the source ships, a matrix
# without any dispatch matcher row is unadmitted drift — this leg is the
# obligation the admission above opens.
if os.path.exists(".rulesync/subagents/agent-board-dispatch.md"):
    if not any("dispatch" in x.lower() for x in nlabels):
        print("cf-126 era: agent-board-dispatch shipped but the matrix carries no dispatch matcher row — the agents-sync law says a permission surface is only done when its matrix row moved (C02 dev's same-commit duty)"); sys.exit(1)
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
# seaweedfs-debug C07 (2026-11-11) re-pin: the dev-deploy EDIT cell moved a
# second time — the dev-family plans deny became the depth-2 `.agents/plans/*/*`
# and this row's wording moves with it in the same commit (the agents-sync law:
# a permission change is only done when its matrix rows moved). The byte below
# is that post-C07 row. Walking posture: pre-landing the still-unchanged TB
# row rides and t4 stays green; the settled admission engages the moment C07
# dev moves permissions.md, so a drifted row — not exactly these bytes —
# reddens. t7 in tests/seaweedfs-debug/surface.sh greps for this constant so
# the re-pin cannot be skipped.
DEV_DEPLOY_SETTLED = """| dev-deploy | everything EXCEPT the test paths (`charts/**/tests/**`, `containers/**/tests/**`, top-level `tests/**`) and everything below `.agents/plans/` root (depth-2 deny `.agents/plans/*/*` — plans-root dated deliverables stay dev-editable; ticket folders with STATE/chunks/FRICTION/DECISIONS/plan-of-record and `templates/` stay closed), plus the context-file rules below — the block mirrors `agent-dev-local` verbatim plus the cleanup grant (cf-90 C06) | none — and nothing launches them either yet: the pair ships DEFINITION ONLY (cf-90), the coord step-8b Deployment-stage hook under a checked Lifecycle `Deployment` is the only future launch surface (the boards Stage map governs) | as dev-local — git reads, `git add`/`git commit`/`git push` denied (the coordinator commits), trailing `ls *` allow, `helm lint/template` | as plan, plus the workspace-isolation trio (`opencode_worktree_create`/`opencode_worktree_list`/`opencode_session_move`) AND the cleanup row `opencode_worktree_remove` (the deploy fixer closes its OWN worktree at hand-back; branch stays coord-owned, landing-gated) — still NO `execute` row (no deny baseline: interactive runs approve Code Mode once, unattended pipeline runs stay blocked from minting coordinator-owned surfaces) |"""
for r in b:
    label = r.split("|")[1].strip()
    # cf-126 C02 widening admission (validation_at_fault via coord, DECISIONS
    # D24 route) for the FOUR frozen coord-family rows: the widened truth
    # (read * + env denies, the six global- fleet grants, the two session-
    # creation api post rows) must be able to ride these cells. The coord-pr
    # settled-bytes precedent is the model — a moved cell is admitted
    # EXACTLY by its pinned constant, or as visibly carrying the widening;
    # the pure reference rows carry it through the row they reference. An
    # unexplained rewrite — no pinned bytes, no widening markers, no
    # reference carry — still reddens, and an UNadmitted row drifting
    # reddens through the final message below. A later test round may
    # promote the widened bytes to settled constants; that is a re-pin,
    # never a silent skip.
    C02_WIDENED_MARKERS = ("global", "read *", "api post")
    C02_MOVERS = {"coord-local", "coord-pr", "board-coord-local", "board-coord-pr"}
    def cell_ok(ob, nb, mv_low):
        if ob == nb:
            return True
        low_nb = nb.lower()
        if ob in nb:
            return True  # the cell grew additively — the widened truth rides the old text
        if any(w in low_nb for w in C02_WIDENED_MARKERS):
            return True  # this very cell names the widening
        ref = ob.lower().startswith(("same as", "as coord", "as board-coord"))
        if ref and ("same as" in low_nb or "as coord" in low_nb or "as board-coord" in low_nb
                    or any(w in mv_low for w in C02_WIDENED_MARKERS)):
            return True  # a reference-idiom cell keeps riding its target row
        return False
    def widened_carry(mv, base_row):
        # Per-cell admission, not a row-wide escape hatch: an unexplained
        # PROSE SWAP (a reference cell replaced by text that neither keeps
        # the reference nor names the widening) reddens even when sibling
        # cells still read 'same as' — the cell-count equality plus the
        # per-cell bar is what keeps the coord-pr settled-bytes precedent
        # meaningful once the bytes move.
        bc = [c.strip() for c in mv.strip().strip("|").split("|")]
        oc = [c.strip() for c in base_row.strip().strip("|").split("|")]
        if len(bc) != len(oc) or bc[0] != oc[0]:
            return False
        mv_low = mv.lower()
        return all(cell_ok(a, b, mv_low) for a, b in zip(oc, bc))
    if label in ("review", "coord", "board-coord", "agent-board", "dev-local", "dev-pr"):
        continue
    if r not in n:
        if label == "coord-pr":
            cur = [x for x in n if x.split("|")[1].strip() == "coord-pr"]
            if len(cur) == 1 and cur[0] == COORD_PR_SETTLED:
                continue
            if len(cur) == 1 and widened_carry(cur[0], r):
                continue
            print(f"coord-pr row is neither the TB form, nor the pinned settled form (cf-72 T-7 tail + the cf-88 union rider + the cf-90 C06 launch-cell widen), nor a cf-126 C02 widened carry (global- fleet grants / read * / api post creation rows) — got {cur}; the admission is byte-exact or visibly widened: dropping a grant, rewording the tail or any other drift is unadmitted"); sys.exit(1)
        if label == "dev-deploy":
            cur = [x for x in n if x.split("|")[1].strip() == "dev-deploy"]
            if len(cur) == 1 and cur[0] == DEV_DEPLOY_SETTLED:
                continue
            print(f"dev-deploy row is neither the TB form nor the pinned settled form (cf-96 final-review Deploy->Deployment vocabulary sweep) — got {cur}; the admission is byte-exact"); sys.exit(1)
        if label in C02_MOVERS:
            cur = [x for x in n if x.split("|")[1].strip() == label]
            if len(cur) == 1 and widened_carry(cur[0], r):
                continue
            print(f"the {label} row changed byte-wise WITHOUT the sanctioned cf-126 C02 widening shape — neither the TB bytes, nor a moved cell that names the widened truth (global- fleet grants / read * / the api post creation rows) nor keeps a 'same as' reference idiom; a reshaped row (cell count moved) or an unexplained rewrite is unadmitted drift"); sys.exit(1)
        print(f"base row '{label}' changed byte-wise — the sanctioned matrix moves are the cf-75 agent-board insertion, the cf-76 review row, board-tick-cleanup C01's five shell-cell updates, cf-90 C06's deploy-pair rows + coord roster cell, the byte-exact coord-pr settled admission, seaweedfs-debug C07's dev-deploy edit-cell depth-2 move, and cf-126 C02's widened carries on the four coord-family mover rows plus the dispatch matcher addition; nothing else may drift"); sys.exit(1)
PY
  ok "t4: role matrix (source + mirror) keeps every base row byte-identical except the sanctioned moves (C02 review row, board-tick-cleanup C01's five shell cells, cf-90 C06's deploy-pair rows + coord roster cell + the byte-exact coord-pr settled admission, seaweedfs-debug C07's dev-deploy edit-cell depth-2 move, and cf-126 C02's visibly-widened carries on coord-local/coord-pr/board-coord-local/board-coord-pr), carries the agent-board row (era-gated presence — post-landing it rides the base too), the dispatch matcher once the dispatcher source ships (era-gated, C02 dev's same-commit matrix duty), and with the deploy pair shipped both dev-deploy matchers must be present"
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
  # The invariance premise, re-pinned at the cf-93 C10 rebase, then CONTENT-
  # re-pinned at cf-126 C01 AC3 (why: the card-mandated liveness QUADRUPLE
  # rewrites the map(select ...) filter line — the comment-only diff shape
  # this leg shipped is unsatisfiable by design). The stated law survives:
  # the hourly gate is NOT WIDENED beyond what the card commands — no
  # collector reference (leg above), no logic/verdict/flag move. So the
  # filter line is pinned to exactly the four scheduled-surface ids, the
  # three verdict emissions stay byte-exact, the marker-blind + board-blind
  # bans and the operand defaults hold, and the usage legend must name all
  # four ids. Controls strip semantic tokens, never bytes. The child-suite
  # runs below are unchanged.
  cat >"$TMP/gatecontent.py" <<'PY'
# Shipped checker, live AND mutants (the controls exercise the same code).
import sys
text = open(sys.argv[1]).read()
errs = []
QUAD = ('| map(select(.agent == "agent-board-coord" or .agent == "agent-board-coord-local"'
        ' or .agent == "agent-board-coord-pr" or .agent == "agent-board-dispatch"))')
if QUAD not in text:
    errs.append("the liveness disjunction is not the exact quadruple filter line — the only widening cf-126 C01 AC3 sanctions; a fifth name or the retired triple is drift (AC6)")
if text.count('.agent == ') != 4:
    errs.append(f"{text.count('.agent == ')} name conjuncts, want exactly the four on the single filter line")
for em in ("say_run() { printf 'GATE: RUN %s\\n' \"$1\"; exit 0; }",
           "say_skip() { printf 'GATE: SKIP %s\\n' \"$1\"; exit 1; }",
           "printf 'GATE: LIVE %s (%ss) %s\\n' \"$id\" \"$age\" \"$title\""):
    if em not in text:
        errs.append(f"verdict emission moved: {em!r} — gate logic, verdicts and flags stay untouched (AC6)")
for banned in ('pipelineNoop', 'archiv', 'opencode api patch', 'opencode api post',
               'list_swimlanes', 'get_board', 'list_cards', 'move_card', 'add_comment'):
    if banned in text:
        errs.append(f"the gate grew {banned!r} — marker writes, session writes and board calls never cross into the script (AC6)")
for op in ("THRESHOLD_MIN_DEFAULT=15", "GRACE_MIN_DEFAULT=5", "map(select(.id != $self))",
           'now="$(date +%s%3N)"'):
    if op not in text:
        errs.append(f"operand logic moved: {op!r}")
print("; ".join(errs))
sys.exit(1 if errs else 0)
PY
  python3 "$TMP/gatecontent.py" "$GATE_SCRIPT" \
    || fail "t6[cf-126 re-pin of C03 AC6]: $GATE_SCRIPT violates the not-widened gate CONTENT law (reason above)"
  sed 's/ or .agent == "agent-board-dispatch"//' "$GATE_SCRIPT" >"$TMP/t6-mquad.sh"
  if python3 "$TMP/gatecontent.py" "$TMP/t6-mquad.sh" >/dev/null 2>&1; then
    fail "t6 control: the dispatcher-leg-stripped mutant passed — the quadruple confinement pin is vacuous"
  fi
  cp "$GATE_SCRIPT" "$TMP/t6-mmarker.sh"; printf '%s\n' '# pipelineNoop marker would land here' >>"$TMP/t6-mmarker.sh"
  if python3 "$TMP/gatecontent.py" "$TMP/t6-mmarker.sh" >/dev/null 2>&1; then
    fail "t6 control: a mutant carrying the marker vocabulary passed the marker-blind ban"
  fi
  for n in agent-board-coord agent-board-coord-local agent-board-coord-pr agent-board-dispatch; do
    grep -qF "\"$n\"" "$GATE_SCRIPT" \
      || fail "t6[cf-126 C01]: the gate never names \"$n\" — the explicit enumeration (legend and filter alike) is the not-widened proof"
  done
  ok "t6[cf-126 re-pin]: $GATE_SCRIPT holds the not-widened gate law as CONTENT (exact quadruple filter, byte-exact verdicts, marker/board bans, operand defaults, four names in the legend), and both semantic mutants redden"
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
        ok "t6: agent-perms A15 reads green — the roster-fence legs have landed, fold A15 back into the subset run above"
      elif grep -qE 'C08|cf-106 C01' "$a15log"; then
        # Admitted names, never a blanket skip: C08 = the original designed
        # red (pipeline_claim `shared` input + co-tenancy posture); cf-106 C01
        # = the roster-fence leg that has been red on main since the C05-C07
        # window (verified byte-identical in a detached worktree at the cf-126
        # test wave — pre-existing drift tracked OUTSIDE cf-126, the same
        # posture as gate t17's selection note). An A15 failure naming NEITHER
        # contract leg is a new failure mode and still reddens this arm.
        ok "t6: agent-perms A15 red, and red on an admitted contract leg (C08's co-tenancy surface or the cf-106 C01 roster fence — the latter pre-existing at main HEAD, tracked outside cf-126) — recorded as designed red, not a C07 regression (log: $a15log)"
      else
        tail -n 20 "$a15log" >&2
        fail "t6: agent-perms A15 failed for a reason other than the two admitted contract legs (log: $a15log)"
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
  ok "t6[cf-126 re-pin]: gate script holds the not-widened CONTENT law vs the shipped script and is free of agent-board references; gate contract (ids minus the known-red t17), agent-perms (ids minus A15 = C08's leg, which is admitted by name) and standalone-agents suites pass (C03 AC6 regression)"
fi

printf 'PASS: wekan-mcp board-context checks (%d ok)\n' "$checks"
