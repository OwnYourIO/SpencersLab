#!/usr/bin/env bash
# agent-test / agent-dev-pr / agent-dev-local top-level tests/** permission
# contract suite
# (2026/2026-10-bug-tests-edit-perms, C01; RE-PINNED by cf-58 for the dev-role
# split into agent-dev-pr/agent-dev-local (C02) and the coord-family variants
# + aliases (C03)).
#
# Pins the invariant this ticket creates: the agent-* permission blocks know
# top-level `tests/` exists — agent-test may write the repo-validation suites
# under it (last-match after its `edit * deny`), the dev variants may not
# (last-match after their `edit * allow`), the role-matrix/skill prose says
# so, and the regenerated mirrors are honest. Contract source: plan file
# Goal + chunks/C01.md AC1-AC9; DECISIONS D2-D5 (the blocks' blind spot) and
# D9-D12 (the post-landing base-posture fold-in) are binding. cf-58 re-pin
# source: chunks/C02.md + C03.md "## Tests" (DEV_* now the TWO variant pairs,
# coord path variables the SIX family files, new parsed checks A11-A13).
#
# AC trace: A1[AC1] A2[AC2] A3[AC3] A4[AC4] A5[AC5-pairs]
# A6[AC5-regen/AC6-hold] A7[AC6-AC7] A8[AC6-parse-safety] A9[AC9-admits]
# A10[AC9-or-form→cf-58 mechanism-integrity] A11[C02 git rows + push policy]
# A12[C03 six-family: alias parity, git block order, roster dev slot]
# A12+cf-72[AC6: B-block rows 70/75 + the 90-command per-class verdict matrix
# through family.py policybatch over all six sources and six mirrors]
# A13[C02 AC5/C03 AC7 rename sweep + command→agent pairing]
# A14[bug-board-coord-dev-boards-allow AC6: MCP action-glob vs registered server-name spelling]
# A15[cf-76 C07: pipeline_* lock-tool rows on the board-coord trio + tool/label-constant
# parity across plugin ↔ permission rows ↔ boards skill];
# A16[board-tick-cleanup C01 AC1-AC4: the explicit `ls *` allow on every
# permission-bearing source and mirror, the effective 'ls -a' verdict, the
# fabricated-strip/duplicate negative controls, the 22/9 verified counts and
# the permissions.md matrix + drift move].
#
# cf-72 re-pin (2026-10-29, card #72, candidate B): the coord family's git
# surface is no longer a reads allow-list — A12's GIT_SHARED/TAIL_* block (and
# the sibling suites' atpos/splice pins) declare the B contract, and the AC6
# verdict matrix is evaluated THROUGH family.py's shipped last-match loop
# (policybatch), never a hand-rolled second semantics. RED before the B block
# lands, green at the landing commit; the matrix's tail cells (G3-G5) are
# what make a future row reorder fail as a VERDICT drift, not just a text diff.
#
# Red posture: A1-A4 — the permission rows and the text rows do not exist
# yet; every red line names the missing rule/row, never a harness fault.
# A16 (board-tick-cleanup C01) shipped with the C01 commit and HOLDs: it
# names any source/mirror that lost its `ls *` row. The 2026-10-30 merge
# re-seat moved the coord-family row INSIDE the scoped-read family (after the
# preload-probe row, before cf-72's absolute-last push tail); the
# dev/standalone/agent-board positions are unchanged. A16 pins COUNT and
# EFFECT, so the re-seat moves neither — only this note records it.
# A5-A8 are HOLD posture (green now, must stay green). A9 pinned the TEST
# phase's own suite re-pins (folder admits), green from this file's landing
# and HOLD through dev. A10 is the cf-58 RE-PIN of the old mechanism test:
# the splice OR-form died with the C02/C03 splits (the sanctioned coord-side
# delta is no longer "+two shell rows" — it is the git block + roster +
# alias parity), so A10 now runs the parsed family checks the plan re-pins
# onto this suite: alias↔local equality (the drift guard), git-row order,
# push-policy last-match, roster dev slot, plus fabricated-row negative
# controls proving the guards never degenerate into "empty diff ⇒ pass".
# A10/A11/A12 are RED before C02/C03 (variant/alias files absent — the red
# names the missing file/row); A13's rename sweep is RED before C02 (bare
# pre-split references still live in AGENTS.md and the case-arm literals
# until the chunks land); A13's -pr command pairing + pointer
# arms self-engage with pipeline-pr.md (era-gated like the AGENTS pins —
# C02's AC5 sweep coverage must not be held hostage by unlanded C03
# content). Validation-at-fault re-pins, user-approved: C04 round (P4 of
# the pipeline-push-pr suite) and C02 round (A11's policy filter is
# action-scoped — the first form's fnmatch(action,"*") was a tautology that
# let the block's trailing MCP-tier rows overwrite the git verdicts). A14 is
# the 2026-10-bug-board-coord-dev-boards-allow guard: RED against the
# pre-fix frontmatter (all three board-coord files carried the dead
# underscore glob), GREEN at this landing; its fabricated-dev_boards*
# negative control proves the guard non-vacuous offline. After each chunk
# lands, `bash tests/agent-perms/surface.sh` must pass the
# subset its chunk owns; the full suite is green at the end of C03.
#
# cf-85 RE-PIN (2026-10-29, 2026-10-cf-85-refactor-wekan-slug-session-link):
# the board write-back roster shrinks from two custom fields to one — `slug`
# carrying the combined `[<slug>](<session link>)` link — so A15's roster arm
# re-pins from the two-field form to the one-field form instead of being
# deleted: cf-76's duty (the roster count is pinned, no third field may sneak
# back as a wording artifact, `create_custom_field` stays absent, the
# fabricated-row control stays) survives the roster shrinking. A15's roster
# arm is this suite's only red leg until the flip commit lands; A9 grows the
# cf-85 plan-folder admit so the running ticket's own folder never reads as a
# scope violation in t14/c8/c7.
#
# Sweep-scope judgment (recorded for review): C02 AC5 ("no bare agent-dev
# in .rulesync/, .opencode/, AGENTS.md, tests/") is implemented on the
# BINDING surfaces — subagent/command sources and their generated mirrors —
# where a bare reference re-grants the retired single-agent wiring. Prose
# mirrors are pinned POSITIVELY instead: AGENTS.md must carry C02's new
# roster row (the variant set named), and the two retired paths must not
# exist as files. Why: the plan itself leaves prose bare mentions byte-
# stable (pipeline-role-dev's description; AGENTS.md "Pipeline specifics"
# lines until C03's overview surgery), so a literal prose sweep would pin
# the plan into a contradiction — the strongest deterministic assertion
# the acceptance criteria support is binding-surface absence + roster
# presence. C03's overview rewrite additionally clears AGENTS.md prose.
#
# Offline-deterministic: no server, no session, no live cluster — rules are
# parsed from the YAML frontmatter (dict comparison, not bytes: rulesync
# re-serializes the mirror, so the honest pair invariant is "same parsed rule
# list in the same order"; byte-equality is asserted only where rulesync
# copies verbatim, the two agents-sync references pairs, A5).
#
# Operational bases (D10/D11 fold-in): every run must pass at BOTH default
# BASE=HEAD (arm B — committed posture on the integrated line, main >=
# 124fc2ae8) AND CHUNK_BASE=081b57889 (arm A — the landing parent of the
# cf-52 content 20ed5dfaf). A7's sanctioned-delta walk uses $BASE; A10 runs
# its fixtures at the two literal operational refs regardless of $BASE.
# Pre-landing bases (f11bfcb85; 916044893 as a chunk base; the cf-52 branch
# refs b0c975bf6/1a6517c81) are historical and need not pass.
#
# Usage (harness convention from tests/coord-inwork/surface.sh):
#   bash tests/agent-perms/surface.sh            # A1..A15
#   bash tests/agent-perms/surface.sh A1 A4      # subset (ids case-insensitive)
# Chunk-owned subsets (red-between-chunks is by design per DECISIONS):
#   C02 review: A1..A11 + A13 (A10/A12 belong to C03; the devlocal/devpr
#     add/commit rows are DENY-pinned here — cf-76 C02 moved commit ownership
#     to the coord, so A11 is red until that flip lands)
#   C03 review: full suite minus A15
#   C07 review: full suite (A15 skips until the pipeline-locks plugin exists,
#     then engages red-before-C07-dev and pins the landed surface)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

# The two operational refs A10 pins against (D11: 081b57889 is the landing
# parent of the cf-52 content, NOT 916044893, whose child is the release-bot
# Chart.yaml commit the scope guards do not admit).
ARM_A=081b57889
ARM_B=HEAD
INTEGRATED=124fc2ae8

TEST_SRC=".rulesync/subagents/agent-test.md"
TEST_GEN=".opencode/agents/agent-test.md"
# cf-58 C02 re-pin: the single implementer pair is now the TWO variant pairs.
DEV_LOCAL_SRC=".rulesync/subagents/agent-dev-local.md"
DEV_LOCAL_GEN=".opencode/agents/agent-dev-local.md"
DEV_PR_SRC=".rulesync/subagents/agent-dev-pr.md"
DEV_PR_GEN=".opencode/agents/agent-dev-pr.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"
POV_SRC=".rulesync/skills/agents-sync/references/pipeline-overview.md"
POV_GEN=".opencode/skills/agents-sync/references/pipeline-overview.md"
PAR_SRC=".rulesync/skills/agents-sync/references/plan-and-result.md"
PAR_GEN=".opencode/skills/agents-sync/references/plan-and-result.md"
RT_SRC=".rulesync/skills/pipeline-role-test/SKILL.md"
RT_GEN=".opencode/skills/pipeline-role-test/SKILL.md"
RULES_SRC=".rulesync/rules/overview.md"
# cf-58 C03 re-pin: the coord path variables name the SIX family files (alias
# + -local + -pr per coord), sources and generated mirrors.
CF_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
        .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
        .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
CF_GEN=(.opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md
        .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md
        .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md)
SUITE_SURFACE="tests/coord-inwork/surface.sh"
SUITE_GATE="tests/agent-board-coord/gate.sh"
SUITE_RULESYNC="tests/agent-board-coord/rulesync-surface.sh"
SUITE_AGENTSMD="tests/agent-board-coord/agents-md.sh"
SUITE_PUSH="tests/pipeline-push-pr/surface.sh"
SUITE_STANDALONE="tests/standalone-agents/surface.sh"
SUITE_MODELS="tests/pipeline-models/surface.sh"

# The D4 carve set, grown to the cf-75 C02 trio (2026-10-27): exactly these
# six paths may move inside the agents-sync dirs; the exclusion regex is
# grepped inside both guarded suites (A7) and its literal moves in lockstep
# across gate.sh t12, coord-inwork i5 and A7's needles.
CARVE_RE='^(\.rulesync|\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview|plan-and-result)\.md$'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/agent-perms-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 16); do WANT["a$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^a([1-9]|1[0-6])$ ]] || fail "unknown check id '$a' (expected A1..A16)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers ------------------------------------------------------------

cat >"$TMP/permdelta.py" <<'PY'
# One file's permission contract, both trees, one process:
#  - the parsed rule lists of source and generated mirror must be EQUAL and
#    in equal order (rulesync re-serializes bytes — dict/sequence equality is
#    the honest mirror invariant, and ordering is what last-match-wins makes
#    load-bearing, so it must be pinned);
#  - the pivot rule (deny for test, allow for dev) is the FIRST edit rule;
#  - the new rule (allow for test, deny for dev) exists with the exact shape
#    and sits AFTER the pivot — before it, the pivot silently wins.
# argv: role(test|dev) then the file pairs (source, generated).
import re, sys, yaml
role = sys.argv[1]
files = sys.argv[2:]
PIVOT = {"action": "edit", "resource": "*",
         "effect": "deny" if role == "test" else "allow"}
NEW = {"action": "edit", "resource": "tests/**",
       "effect": "allow" if role == "test" else "deny"}
SIBLINGS = ["charts/**/tests/**", "containers/**/tests/**"]
# The pre-existing chart/container test rules keep the OPPOSITE effect of the
# baseline (the deny-baseline test role grants them; the allow-baseline dev
# role revokes them) — pinning the wrong effect here would red on a healthy
# tree and bury the real missing-rule red underneath false findings.
SIBLING_EFFECT = "allow" if role == "test" else "deny"
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
errs = []
parsed = {}
for f in files:
    p = parsed[f] = perms(f)
    at = [i for i, r in enumerate(p) if r.get("action") == "edit"]
    if not at:
        errs.append(f"{f}: no edit rules at all")
        continue
    if p[at[0]] != PIVOT:
        errs.append(f"{f}: the first edit rule is {p[at[0]]}, want the {role} baseline {PIVOT}")
    piv = [i for i in at if p[i] == PIVOT]
    new = [i for i in at if p[i] == NEW]
    if not new:
        errs.append(f"{f}: the top-level tests/** '{NEW['effect']}' rule is MISSING "
                    f"(red before C01 dev phase — {role} block does not know top-level tests/ exists)")
    elif not piv or piv[0] > new[0]:
        errs.append(f"{f}: tests/** rule present but BEFORE its pivot — last match wins, the {role} baseline would silently override it")
    elif len(new) != 1:
        errs.append(f"{f}: tests/** rule appears {len(new)} times, want exactly one")
    for s in SIBLINGS:
        if not any(p[i] == {"action": "edit", "resource": s, "effect": SIBLING_EFFECT} for i in at):
            errs.append(f"{f}: the existing {s} '{SIBLING_EFFECT}' rule vanished")
# Pair equality runs as a separate finding, never an early exit: it buries the
# missing-rule red when a dev round edits the source before the mirror lands,
# and the reviewer must see BOTH reasons in one run.
src, gen = files
if parsed[src] != parsed[gen]:
    errs.append(f"source/generated permission lists differ for the {role} pair "
                f"(order or content drift between {src} and {gen} — regenerate, "
                f"never hand-edit the mirror)")
if errs:
    print("; ".join(errs))
    sys.exit(1)
PY

cat >"$TMP/sectgrep.py" <<'PY'
# Line/section-scoped text pins for the stale-surface sweep: role-matrix rows
# are pinned by their label cell, the drift incident by its section, the skill
# write-surface sentence by its lead-in. Row-level greps survive rewording
# elsewhere and fail exactly when the row has not moved.
# argv: file, mode, anchor..., needles...  (mode 'all' has no anchor)
#   row     — markdown table rows whose first cell equals the anchor
#   section — every line from the heading matching the anchor to EOF
#   line    — the lines that contain the anchor substring
#   all     — the whole file
import re, sys
path, mode = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
text = open(path).read()
if mode == "all":
    anchor, needles = None, rest
    hay = text
else:
    anchor, needles = rest[0], rest[1:]
    if mode == "row":
        # [ \t], NOT [[:space:]] — Python's re has no POSIX classes (on 3.14
        # the nested-set reading silently matches no space, killing row lookups).
        hay = "\n".join(l for l in text.splitlines()
                        if re.match(r"^\|[ \t]*" + re.escape(anchor) + r"[ \t]*\|", l))
    elif mode == "section":
        m = re.search(r"(?ms)^#+[^\n]*" + re.escape(anchor) + r"[^\n]*\n.*", text)
        hay = m.group(0) if m else ""
    elif mode == "line":
        hay = "\n".join(l for l in text.splitlines() if anchor in l)
    else:
        print(f"unknown sectgrep mode '{mode}'"); sys.exit(2)
if not hay:
    print(f"{path}: no {mode} '{anchor if anchor else ''}' content to search"); sys.exit(1)
for n in needles:
    if n not in hay:
        print(f"{path}: '{n}' missing from the {mode}"
              + (" (red before C01 dev phase — the text row has not moved)" if mode != "all" else ""))
        sys.exit(1)
PY

cat >"$TMP/blockwin.py" <<'PY'
# Windowed grep over a suite's `if want <id>; then ... fi` block: an admission
# or exclusion elsewhere in the file must not satisfy the pin (A9/A10/A7).
# argv: suite-file, check-id (t14|c8|c7|t12|i5|t17|i4|...), needle...
import sys
path, cid = sys.argv[1], sys.argv[2]
needles = sys.argv[3:]
lines = open(path).read().splitlines()
start = next((i for i, l in enumerate(lines) if l.startswith(f"if want {cid}; then")), None)
if start is None:
    print(f"{path}: block 'if want {cid}' not found"); sys.exit(1)
end = next((i for i in range(start + 1, len(lines)) if lines[i] == "fi"), None)
if end is None:
    print(f"{path}: no closing ^fi for block 'if want {cid}'"); sys.exit(1)
block = "\n".join(lines[start:end + 1])
for n in needles:
    if n not in block:
        print(f"{path}: '{n}' is not inside the if-want-{cid} block (windowed admission pin — "
              "a hit elsewhere in the file does not count)")
        sys.exit(1)
PY

cat >"$TMP/family.py" <<'PY'
# cf-58 C02/C03 guard set for the agent-dev variant pair and the six-agent
# coord family. One shipped implementation used by both the live checks
# (A11/A12) and the fabricated-row negative controls (A10) — the cf-52
# lesson kept: a guard must be provably NON-vacuous, so the same code the
# live run uses is what the controls exercise.
# Subcommands (all exit 1 with a reason on violation):
#   parity A B                 — parsed permission lists equal (dict+order)
#                                AND the body MUST-load lists (/skill lines)
#                                equal; the drift guard for alias<->-local.
#   gitrows FILE CLASS         — CLASS devlocal|devpr|local|pr: the git rows
#                                exactly as the plan declares, in order, and
#                                nothing else added beyond base+suffix.
#   lsrow FILE                 — exactly one {shell, "ls *", allow} row (board-
#                                tick-cleanup C01 AC1: the explicit ls allow on
#                                every permission-bearing source and mirror).
#   policy FILE CMD            — prints the effective last-match verdict.
#   policybatch FILE CLASS     — re-verdicts the cf-72 AC6 matrix (stdin TSV
#                                class<TAB>want<TAB>command, '#' lines skipped)
#                                through the SAME last-match loop as policy —
#                                the matrix is lifted through the shipped
#                                projection, never a hand-rolled second one.
#   roster FILE SLOT           — subagent allows == the five roles with SLOT
#                                in the dev position, leading '*' deny first.
#   api FILE                   — exactly the two scoped opencode-api shell
#                                allows, in order, directly after the single
#                                opencode '*' allow rule.
#   board FILE                 — dev-boards* allow once, after the leading
#                                deny-all; execute allow present.
#   naming FILE                — the execute transport allow plus exactly the
#                                four kickoff opencode_* per-tool allows in
#                                order (worktree create/list, session
#                                move/rename); no other opencode_* row.
import re, sys, yaml

def fm(path):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    return (yaml.safe_load(m.group(1)) or {}, m.group(2))

def perms(path):
    f, _ = fm(path)
    return (f.get("opencode") or {}).get("permissions") or f.get("permissions") or []

def skillloads(path):
    _, body = fm(path)
    return [l.strip() for l in body.splitlines() if re.match(r"^\s*/[a-z0-9-]+\s*$", l)]

def sh(res, eff):
    return {"action": "shell", "resource": res, "effect": eff}

# The kickoff naming surface (2026-10-27): MCP actions are permissioned as
# <server>_<tool>, so these rows — not the inert `opencode` anchor — are the
# grant, and `execute` is the transport that exposes the namespace at all.
NAMING = [{"action": "opencode_worktree_create", "resource": "*", "effect": "allow"},
          {"action": "opencode_worktree_list",   "resource": "*", "effect": "allow"},
          {"action": "opencode_session_move",    "resource": "*", "effect": "allow"},
          {"action": "opencode_session_rename",  "resource": "*", "effect": "allow"}]

# cf-72 (card #72, owner ruling 2026-10-29, candidate B): the coord family's
# reads allow-list is GONE. The B block (chunks/C01.md "The block") is one
# `git *` broad-write allow closed by a pinned deny floor — rows 1-68 shared
# by all six sources, effect-aware ORDER being the contract: the floor only
# guards the allow because it follows it, and the 16 exception re-allows only
# ride over the floor because they follow IT. gitrows compares the WHOLE
# sequence, so any reorder, insertion, drop or effect flip fails at its index.
GIT_SHARED = [
    sh("git *", "allow"),
    sh("git checkout main*", "deny"),
    sh("git * checkout main*", "deny"),
    sh("git checkout * main*", "deny"),
    sh("git * checkout * main*", "deny"),
    sh("git switch main*", "deny"),
    sh("git * switch main*", "deny"),
    sh("git switch * main*", "deny"),
    sh("git * switch * main*", "deny"),
    sh("git update-ref*", "deny"),
    sh("git * update-ref*", "deny"),
    sh("git symbolic-ref*", "deny"),
    sh("git * symbolic-ref*", "deny"),
    sh("git branch -f main*", "deny"),
    sh("git * branch -f main*", "deny"),
    sh("git branch --force main*", "deny"),
    sh("git * branch --force main*", "deny"),
    sh("git branch -d main*", "deny"),
    sh("git branch -d * main*", "deny"),
    sh("git * branch -d main*", "deny"),
    sh("git * branch -d * main*", "deny"),
    sh("git branch -D main*", "deny"),
    sh("git branch -D * main*", "deny"),
    sh("git * branch -D main*", "deny"),
    sh("git * branch -D * main*", "deny"),
    sh("git branch -m main*", "deny"),
    sh("git branch -m * main*", "deny"),
    sh("git * branch -m main*", "deny"),
    sh("git * branch -m * main*", "deny"),
    sh("git branch -M main*", "deny"),
    sh("git branch -M * main*", "deny"),
    sh("git * branch -M main*", "deny"),
    sh("git * branch -M * main*", "deny"),
    sh("git branch -c main*", "deny"),
    sh("git * branch -c main*", "deny"),
    sh("git branch -c * main*", "deny"),
    sh("git * branch -c * main*", "deny"),
    sh("git branch -C main*", "deny"),
    sh("git * branch -C main*", "deny"),
    sh("git branch -C * main*", "deny"),
    sh("git * branch -C * main*", "deny"),
    sh("git worktree add * main*", "deny"),
    sh("git * worktree add * main*", "deny"),
    sh("git pull*", "deny"),
    sh("git * pull*", "deny"),
    sh("git merge *", "deny"),
    sh("git * merge *", "deny"),
    sh("git config alias*", "deny"),
    sh("git * config alias*", "deny"),
    sh("git * --force*", "deny"),
    sh("git * -f *", "deny"),
    sh("git * -P *", "deny"),
    sh("git merge main*", "allow"),
    sh("git * merge main*", "allow"),
    sh("git merge --abort", "allow"),
    sh("git * merge --abort", "allow"),
    sh("git merge --continue", "allow"),
    sh("git * merge --continue", "allow"),
    sh("git checkout -b * main*", "allow"),
    sh("git * checkout -b * main*", "allow"),
    sh("git checkout -B * main*", "allow"),
    sh("git * checkout -B * main*", "allow"),
    sh("git switch -c * main*", "allow"),
    sh("git * switch -c * main*", "allow"),
    sh("git switch -C * main*", "allow"),
    sh("git * switch -C * main*", "allow"),
    sh("git worktree add -b * main*", "allow"),
    sh("git * worktree add -b * main*", "allow"),
]
# The push tails are the load-bearing LAST rows (T-2 on alias/-local, T-7 on
# -pr, DECISIONS D15): the -local substring row `git *push*` exists because
# the spaced `git * push*` leaks quoted args (`git commit -am 'push
# posture'` slipped in simulation — probe finding F1).
TAIL_LOCAL = [sh("git push*", "deny"), sh("git *push*", "deny")]
TAIL_PR = [sh("git push*main*", "deny"), sh("git * push *main*", "deny"),
           sh("git * push", "deny"), sh("git push -f*", "deny"), sh("git push -P*", "deny"),
           sh("git * push -f*", "deny"), sh("git * push -P*", "deny")]
# cf-76 C02 (D7): the pipeline implementers no longer stage or commit — the
# coordinator is the sole committer (one commit per chunk: code + tests +
# state). The rows stay as explicit DENIES (fail-loud parity with the push
# deny), placed where the allows were. The standalone dev trio keeps its
# allows; tests/standalone-agents/surface.sh S3 pins the deliberate delta.
DEV_SUFFIX = {
    "devlocal": [sh("git add *", "deny"), sh("git commit *", "deny"), sh("git push*", "deny")],
    "devpr": [sh("git add *", "deny"), sh("git commit *", "deny"), sh("git push*", "allow"),
              sh("git push*main*", "deny"), sh("git push --force*", "deny"), sh("git push -f*", "deny"),
              sh("git push * --force*", "deny"), sh("git push * -f*", "deny")],
}
# cf-72 B block totals: 70 rows alias/-local, 75 rows -pr — tails absolute
# last, variant flip changes ONLY the tail (A12 gitrows pins whole+order per
# class; the AC6 verdict matrix below pins what the sequence EVALUATES to).
COORD_SUFFIX = {"local": GIT_SHARED + TAIL_LOCAL, "pr": GIT_SHARED + TAIL_PR}

def fail(*msgs):
    print("; ".join(str(m) for m in msgs)); sys.exit(1)

def is_git(row):
    return row.get("action") == "shell" and str(row.get("resource", "")).startswith("git ")

def verdict(path, command):
    # The single shipped last-match-wins projection (cf-72: lifted out of the
    # policy branch so policy and policybatch share ONE matcher — matrix
    # verdicts proven through any other semantics would prove nothing).
    import fnmatch as _fm
    out = None
    for r in perms(path):
        # Action-scoped (validation_at_fault fix, C02 review 2026-10-27):
        # the rule's action must BE shell or glob-match it — the old
        # fnmatch(action,"*") test was a tautology that counted the block's
        # trailing MCP-tier rows (readonly*/global*/dev* with resource '*')
        # as shell candidates, silently overwriting the git verdicts. The '*'
        # deny-baseline stays in play (its action glob-matches shell), so
        # A10's stripped-deny control semantics are unchanged.
        if not (r.get("action") == "shell" or _fm.fnmatch("shell", str(r.get("action", "")))):
            continue
        if _fm.fnmatch(command, str(r.get("resource", ""))):
            out = r.get("effect")
    return out

def cmd():
    op = sys.argv[1]
    if op == "parity":
        a, b = sys.argv[2], sys.argv[3]
        pa, pb = perms(a), perms(b)
        if pa != pb:
            i = next((i for i, (x, y) in enumerate(zip(pa, pb)) if x != y), min(len(pa), len(pb)))
            fail(f"parity: {a} vs {b} permission lists differ at index {i} "
                 f"(a: {pa[i] if i < len(pa) else None} b: {pb[i] if i < len(pb) else None}; lengths {len(pa)}/{len(pb)})")
        sa, sb = skillloads(a), skillloads(b)
        if sa != sb:
            fail(f"parity: MUST-load lists differ: {a}={sa} {b}={sb}")
    elif op == "gitrows":
        path, cls = sys.argv[2], sys.argv[3]
        table = DEV_SUFFIX if cls.startswith("dev") else COORD_SUFFIX
        suffix = table[cls]
        p = perms(path)
        git = [r for r in p if is_git(r)]
        if cls.startswith("dev"):
            # the declared rows must appear in the declared relative order…
            seq = [r for r in git if any(r == s for s in suffix)]
            if seq != suffix:
                miss = [s for s in suffix if s not in git]
                dup = len(seq) != len(suffix)
                fail(f"gitrows({cls}): {path} declared git rows missing {miss}, duplicated {dup}, or out of order ({seq})")
            # …and no undeclared git row may ride along (the base block's own
            # status/diff/log reads are the only pre-existing git rows)
            base_reads = [sh("git status *", "allow"), sh("git diff *", "allow"), sh("git log *", "allow")]
            extras = [r for r in git if not any(r == s for s in suffix) and not any(r == s2 for s2 in base_reads)]
            if extras:
                fail(f"gitrows({cls}): {path} carries undeclared extra git rows: {extras}")
        else:
            # coord family: no pre-existing git rows — the whole git sequence
            # must equal the declared block, in order, exactly once
            if git != suffix:
                fail(f"gitrows({cls}): {path} git-row sequence is not the declared coord block in order "
                     f"({len(git)} rows seen, {len(suffix)} declared; diff at first mismatch)")
    elif op == "lsrow":
        # board-tick-cleanup C01: one explicit `ls *` allow per permission-
        # bearing file. Count, not position: placement correctness is the
        # EFFECT duty — policy FILE 'ls -a' below must answer allow, which is
        # only true if the row sits after every catch-all deny that would
        # shadow it (agent-board's `shell *` deny, the family baselines).
        path = sys.argv[2]
        want = sh("ls *", "allow")
        n = sum(1 for r in perms(path) if r == want)
        if n != 1:
            fail(f"lsrow: {path} carries {n} exact {{shell, 'ls *', allow}} rows, want exactly one")
        wrong = [r for r in perms(path) if r.get("action") == "shell" and r.get("resource") == "ls *" and r != want]
        if wrong:
            fail(f"lsrow: {path} grew a malformed ls row: {wrong}")
    elif op == "policy":
        print(verdict(sys.argv[2], sys.argv[3]))
    elif op == "policybatch":
        # cf-72 AC6: the verdict matrix through the shipped matcher. argv:
        # file, class; stdin TSV lines class<TAB>want<TAB>command ('#'-lines
        # skipped). Any cell whose effective verdict differs from the chunk's
        # declared one exits 1 naming command + want + got.
        path, cls = sys.argv[2], sys.argv[3]
        bad, n = [], 0
        for line in sys.stdin:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            c, want, command = line.split("\t")
            if c != cls:
                continue
            n += 1
            got = verdict(path, command)
            if got != want:
                bad.append(f"'{command}': want {want} got {got}")
        if bad:
            print(f"policybatch({cls}): {path} verdict drift — " + "; ".join(bad)); sys.exit(1)
        print(f"policybatch({cls}): {path} all {n} matrix cells green")
    elif op == "roster":
        path, slot = sys.argv[2], sys.argv[3]
        p = perms(path)
        if p[0] != {"action": "*", "resource": "*", "effect": "deny"}:
            fail(f"roster: {path} lost the leading deny-all baseline")
        allows = sorted(r.get("resource") for r in p if r.get("action") == "subagent" and r.get("effect") == "allow")
        want = sorted(["agent-plan", "agent-test", slot, "agent-review", "agent-research"])
        if allows != want:
            fail(f"roster: {path} subagent allows {allows}, want exactly {want} (deny-all + five-role roster, leading subagent '*' deny stays)")
        if not any(r.get("action") == "subagent" and r.get("resource") == "*" and r.get("effect") == "deny" for r in p):
            fail(f"roster: {path} lost the leading 'subagent * deny' row")
    elif op == "api":
        path = sys.argv[2]
        p = perms(path)
        want = [sh("opencode api get /api/session*", "allow"), sh("opencode api patch /api/session/*", "allow")]
        api = [r for r in p if r.get("action") == "shell" and str(r.get("resource", "")).startswith("opencode api")]
        if api != want:
            fail(f"api: {path} opencode-api shell rows are {api}, want exactly the two scoped session allows in order "
                 f"(the in-work-mark containment: no third API grant, no other effect)")
        anchors = [i for i, r in enumerate(p) if r == {"action": "opencode", "resource": "*", "effect": "allow"}]
        if len(anchors) != 1:
            fail(f"api: {path} must carry exactly one opencode '*' allow anchor, found {len(anchors)}")
        first = [i for i, r in enumerate(p) if r in want]
        if not first or p[anchors[0] + 1:anchors[0] + 3] != want:
            fail(f"api: {path} the two session allows must sit directly after the opencode '*' allow (the pinned splice position)")
    elif op == "board":
        path = sys.argv[2]
        p = perms(path)
        deny_at = next((i for i, r in enumerate(p) if r.get("action") == "*" and r.get("resource") == "*" and r.get("effect") == "deny"), None)
        db = [i for i, r in enumerate(p) if r.get("action") == "dev-boards*"]
        if deny_at is None or len(db) != 1 or db[0] < deny_at or p[db[0]].get("effect") != "allow":
            fail(f"board: {path} dev-boards* single allow-after-deny-all shape broken (found deny@{deny_at}, dev-boards@{db})")
        if not any(r.get("action") == "execute" and r.get("resource") == "*" and r.get("effect") == "allow" for r in p):
            fail(f"board: {path} lost the execute allow (Code Mode transport)")
        if any(r.get("action") == "dev*" for r in p):
            fail(f"board: {path} grew the broad dev* allow (D21: narrow dev-boards* only)")
    elif op == "naming":
        path = sys.argv[2]
        p = perms(path)
        if not any(r.get("action") == "execute" and r.get("resource") == "*" and r.get("effect") == "allow" for r in p):
            fail(f"naming: {path} lacks the execute allow — Code Mode is the only transport for tools.opencode.*, without it the naming surface is invisible")
        seq = [r for r in p if r in NAMING]
        if seq != NAMING:
            fail(f"naming: {path} kickoff naming rows are {seq}, want exactly the four per-tool allows (worktree create/list, session move/rename) in order")
        extra = [r for r in p if str(r.get("action", "")).startswith("opencode_") and r not in NAMING]
        if extra:
            fail(f"naming: {path} grew unsanctioned opencode_* rows: {extra} — the role contract grants the naming surface only")
    elif op == "locktools":
        # cf-76 C07: the board-coord trio owns the lease-lock tool surface.
        # Exactly the four pipeline_* allow rows (resource '*'), in the
        # declared order, sitting after the dev-boards* MCP row — the claim
        # must precede moves, so the grant block follows its board anchor —
        # and nothing else in the pipeline_ namespace (no globs, no denies
        # riding along that a later edit could silently invert).
        path = sys.argv[2]
        p = perms(path)
        LOCK = [{"action": a, "resource": "*", "effect": "allow"} for a in
                ("pipeline_claim", "pipeline_release", "pipeline_heartbeat", "pipeline_status")]
        for w in LOCK:
            n = sum(1 for r in p if r == w)
            if n != 1:
                fail(f"locktools: {path} row {w['action']} appears {n} times, want exactly the one allow")
        seq = [r for r in p if r in LOCK]
        if seq != LOCK:
            fail(f"locktools: {path} pipeline_* rows out of the declared order: {[r['action'] for r in seq]}")
        extra = [r for r in p if str(r.get("action", "")).startswith("pipeline_") and r not in LOCK]
        if extra:
            fail(f"locktools: {path} grew unsanctioned pipeline_* rows: {extra}")
        db = [i for i, r in enumerate(p) if r.get("action") == "dev-boards*"]
        first = [i for i, r in enumerate(p) if r == LOCK[0]]
        if db and first and first[0] < db[0]:
            fail(f"locktools: {path} the pipeline_* block precedes the dev-boards* row — C07 adds it AFTER")
        if not db:
            fail(f"locktools: {path} lost its dev-boards* anchor (the board-coord block shape)")
    elif op == "action":
        # Last-match verdict for a TOOL action name (MCP/tool rows are
        # permissioned as <action> '<server>_<tool>' style, cf A14's
        # spelling finding) — used to prove the lock surface stays closed
        # for the non-board families (deny-all baseline -> 'deny').
        import fnmatch as _fm
        path, action = sys.argv[2], sys.argv[3]
        out = None
        for r in perms(path):
            a = str(r.get("action", ""))
            if action == a or _fm.fnmatch(action, a):
                out = r.get("effect")
        print(out)
    else:
        fail(f"family.py: unknown subcommand '{op}'"); sys.exit(2)

cmd()
PY

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): the description
# needle-pairs must read as one passage, not as scattered file-wide hits.
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

cat >"$TMP/pairsync.py" <<'PY'
# Source<->generated honesty (coord-inwork convention): bodies equal modulo
# frontmatter/blank space; meaningful frontmatter fields equal once parsed.
# permdelta already pins the parsed PERMISSION equality per pair; this adds
# body + mode/color/name honesty for the cf-58 variant and family pairs.
import re, sys, yaml
src, gen, kind = sys.argv[1], sys.argv[2], sys.argv[3]

def parts(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{path}: no parsable frontmatter"
    return yaml.safe_load(m.group(1)), m.group(2).strip("\n") + "\n"

f1, b1 = parts(src); f2, b2 = parts(gen)
if kind == "skill":
    n = lambda f: {k: f.get(k) for k in ("name", "description", "metadata", "disable-model-invocation")}
else:
    def n(f):
        oc = f.get("opencode") or {}
        return {"name": f.get("name"), "description": f.get("description"),
                "mode": oc.get("mode", f.get("mode")), "color": oc.get("color", f.get("color")),
                "permissions": oc.get("permissions", f.get("permissions"))}
if b1 != b2:
    print("body drift between source and generated mirror"); sys.exit(1)
if n(f1) != n(f2):
    print("frontmatter drift between source and generated mirror"); sys.exit(1)
PY

# --- A1: agent-test pair — tests/** allow after the edit-deny pivot (AC1) ------
if want a1; then
  python3 "$TMP/permdelta.py" test "$TEST_SRC" "$TEST_GEN" \
    || fail "A1[AC1]: agent-test tests/** allow contract not satisfied (grant absent — red before C01 dev phase)"
  ok "A1[AC1]: agent-test (source + mirror) carry the edit-deny baseline with the top-level tests/** allow after it; chart/container test allows intact; parsed rule lists identical across the pair"
fi

# --- A2: dev-variant pairs — tests/** deny after the edit-allow pivot (AC2) -----
# cf-58 C02 re-pin: the single pair became TWO variant pairs; the tests/**
# deny-after-pivot contract is asserted on both, and the retired pre-split
# pair is pinned GONE (its presence with a stale mirror is how role renames
# leave silent behavior behind).
if want a2; then
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    [ -f "$f" ] || fail "A2[AC2]: $f missing (red before C02 — the dev-role split has not landed)"
  done
  python3 "$TMP/permdelta.py" dev "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" \
    || fail "A2[AC2]: agent-dev-local tests/** deny contract not satisfied (deny absent — red before C02 dev phase)"
  python3 "$TMP/permdelta.py" dev "$DEV_PR_SRC" "$DEV_PR_GEN" \
    || fail "A2[AC2]: agent-dev-pr tests/** deny contract not satisfied (deny absent — red before C02 dev phase)"
  ok "A2[AC2]: agent-dev-local and agent-dev-pr (sources + mirrors) carry the edit-allow baseline with the top-level tests/** deny after it; chart/container test denies intact; parsed rule lists identical across each pair"
fi

# --- A3: stale-text sweep — matrix rows + drift incident (AC3) -----------------
# cf-58 C02 re-pin: in permissions.md the single dev row becomes the
# dev-local/dev-pr pair of rows and the Drift-incidents section grows the
# split entry. pipeline-overview.md (POV) is NOT edited by any cf-58 chunk
# (its role prose stays), so its row pins hold unchanged.
if want a3; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row test '`tests/**`' \
      || fail "A3[AC3]: $f test row does not name top-level \`tests/**\` (text row unmoved — red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" row dev-local '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f has no dev-local row listing all three test denies (red before C02 — the split matrix rows have not landed)"
    python3 "$TMP/sectgrep.py" "$f" row dev-pr '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f has no dev-pr row listing all three test denies (red before C02 — the split matrix rows have not landed)"
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' '2026-10-26' 'top-level `tests/`' \
      || fail "A3[AC3]: $f no longer records the 2026-10-26 top-level \`tests/\` drift incident (HOLD — the entry must survive the re-pin)"
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' 'agent-dev-pr' 'agent-dev-local' \
      || fail "A3[AC3]: $f drift-history section lacks the C02 split entry naming agent-dev-pr/agent-dev-local (red before C02 dev phase)"
  done
  for f in "$POV_SRC" "$POV_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row test '`tests/**`' \
      || fail "A3[AC3]: $f test row lacks top-level \`tests/**\` (red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" row dev '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f dev row lacks the three test paths (red before C01 dev phase)"
  done
  ok "A3[AC3]: permissions.md (source + mirrors) carries the dev-local/dev-pr split rows and the C02 drift entry; pipeline-overview rows intact; the 2026-10-26 drift incident survives"
fi

# --- A4: pipeline-role-test skill — false claim gone, surface widened (AC4) ----
if want a4; then
  for f in "$RT_SRC" "$RT_GEN"; do
    if grep -qF 'there is no global' "$f"; then
      fail "A4[AC4]: $f still carries the '(there is no global tests/)' claim — it is false (top-level tests/ ships suites) and this ticket deletes it (red before C01 dev phase)"
    fi
    python3 "$TMP/sectgrep.py" "$f" line 'write only test files' 'top-level `tests/`' \
      || fail "A4[AC4]: $f write-surface line does not include top-level \`tests/\` (red before C01 dev phase)"
  done
  ok "A4[AC4]: pipeline-role-test SKILL.md (source + mirror) — false 'no global tests/' claim gone, write-surface line states top-level \`tests/\`"
fi

# --- A5: agents-sync references pairs byte-identical source<->mirror (AC5) -----
if want a5; then
  # cf-75 C02 re-pin: plan-and-result.md joins the carved pair-equality loop
  # (it leaves the gate t12 / coord-inwork i5 byte-freeze with the widened
  # carve, so this is the pin that keeps its mirror regenerated).
  for pair in "$PERM_SRC|$PERM_GEN" "$POV_SRC|$POV_GEN" "$PAR_SRC|$PAR_GEN"; do
    IFS='|' read -r s g <<<"$pair"
    cmp -s "$s" "$g" \
      || fail "A5[AC5]: $s and its generated mirror $g are not byte-identical — rulesync copies these verbatim, so a text edit must land in the source and regenerate"
  done
  ok "A5[AC5]: the three agents-sync references pairs are byte-identical source<->generated (HOLD before and after dev — rulesync copies verbatim)"
fi

# --- A6: regeneration contract (AC5 regen / AC6 hold) --------------------------
if want a6; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "A6: rulesync not resolvable here (PATH or npx cache) — generate --check + no-op gate skipped with warning (c7/t14/i6 precedent)"
    ok "A6[AC5-regen/AC6-hold]: generator gate skipped with warning (ladder found no rulesync)"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "A6[AC5]: rulesync generate --check is not clean — committed generated surfaces are stale against the sources"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "A6[AC5]: rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "A6[AC5]: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "A6[AC5]: the second rulesync generate is not a no-op (sources and generated have drifted)"
    ok "A6[AC5-regen/AC6-hold]: generate --check clean and the second generate is a no-op (via $RS)"
  fi
fi

# --- A7: re-pin HOLD posture — carve present, sanctioned agents-sync delta -----
# cf-75 C02 re-pin (2026-10-27): the carve trio grew with plan-and-result.md;
# the needles below must match the exclusion lines in gate.sh t12 and
# coord-inwork i5 byte-for-byte, and those two lines must match each other —
# all four sites move together or A7 goes red (the three-way lockstep is the
# point: a carve widened in one suite only must leak the freeze elsewhere).
if want a7; then
  python3 "$TMP/blockwin.py" "$SUITE_GATE" t12 \
    "grep -v -x -E -e '(\\.rulesync|\\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview|plan-and-result)\\.md'" \
    || fail "A7[AC6-AC7]: gate.sh t12 lacks the D4 carve exclusion line — the re-pin did not land"
  python3 "$TMP/blockwin.py" "$SUITE_SURFACE" i5 \
    "grep -v -x -E -e '(\\.rulesync|\\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview|plan-and-result)\\.md'" \
    || fail "A7[AC6-AC7]: surface.sh i5 lacks the D4 carve exclusion line — the re-pin did not land"
  others=$( { git diff --name-only "$BASE" -- .rulesync/skills/agents-sync .opencode/skills/agents-sync 2>/dev/null || true;
              git ls-files --others --exclude-standard -- .rulesync/skills/agents-sync .opencode/skills/agents-sync; } \
            | grep -Ev "$CARVE_RE" || true )
  [ -z "$others" ] || { printf '%s\n' "$others" >&2; fail "A7[AC6-AC7]: agents-sync paths changed vs $BASE beyond the six carved references files (base: $BASE) — the byte-freeze carve is EXACTLY permissions.md + pipeline-overview.md + plan-and-result.md (source and generated), no other frozen-dir edit is sanctioned"; }
  ok "A7[AC6-AC7]: t12/i5 carve lines present; no agents-sync delta vs $BASE outside the carved six (worktree included)"
fi

# --- A8: parse-safety of every touched suite (AC6-parse-safety) ----------------
if want a8; then
  for f in "$0" "$SUITE_SURFACE" "$SUITE_GATE" "$SUITE_RULESYNC" "$SUITE_AGENTSMD" \
           "$SUITE_PUSH" "$SUITE_STANDALONE" "$SUITE_MODELS" \
           tests/noop-marker/surface.sh tests/board-preload-probe/surface.sh; do
    bash -n "$f" || fail "A8[AC6-parse-safety]: bash -n failed on $f"
  done
  ok "A8[AC6-parse-safety]: all five touched/created suite files + the three cf-58-new suites parse (bash -n)"
fi

# --- A9: follow-up-folder admits inside the three scope blocks (AC9-admits) ----
# cf-58 re-pin: the loop grows a fourth slug — this ticket's own folder must
# be admitted by the same blocks (a scope guard that reds on the mere
# existence of the running ticket's plan folder buries every later check).
# cf-75 re-pin (2026-10-27): the same rule adds 2026-10-cf-75-bug-wekan-mcp-
# skill — its plan folder's STATE.json/handoff commits land on this branch
# like cf-58's did, and every t14/c8/c7 run against a pre-chunk base would
# otherwise read them as scope violations.
# cf-85 (2026-10-29) joins the same admit for the running ticket's folder.
# cf-72 re-pin (2026-10-29): 2026-10-cf-72-chore-coord-git-read-globs joins
# the window loop — the three scope guards must admit this ticket's own plan
# folder or the very run landing the B block reddens on its own bookkeeping
# (D9, same precedent chain).
if want a9; then
  for slug in 2026-10-bug-kickoff-mints-run-branch 2026-10-bug-session-origin-no-line 2026-10-bug-tests-edit-perms 2026-10-cf-58-feat-standalone-agent-merge 2026-10-cf-75-bug-wekan-mcp-skill 2026-10-cf-85-refactor-wekan-slug-session-link 2026-10-cf-72-chore-coord-git-read-globs 2026-10-chore-board-tick-cleanup 2026-10-cf-68-feat-wekan-mcp-create-list 2026-10-cf-83-refactor-strata-flash; do
    python3 "$TMP/blockwin.py" "$SUITE_GATE" t14 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: gate.sh t14 does not admit $slug inside its if-want block (the D9 widening did not land)"
    python3 "$TMP/blockwin.py" "$SUITE_RULESYNC" c8 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: rulesync-surface.sh c8 does not admit $slug inside its if-want block"
    python3 "$TMP/blockwin.py" "$SUITE_AGENTSMD" c7 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: agents-md.sh c7 does not admit $slug inside its if-want block"
  done
  ok "A9[AC9-admits]: the three 2026-10-bug-* follow-up folders, the cf-58, cf-75, cf-85 and cf-72 ticket folders are admitted inside the t14, c8 and c7 blocks (windowed, not file-global)"
fi

# --- A10: cf-58 family-mechanism integrity + negative controls (C03-owned) -----
# Re-PIN history: the old A10 exercised cf-52's splice OR-form (coord files
# = base + exactly two shell allows). C02/C03 supersede that sanctioned delta
# (the git block + roster + alias parity are now part of the coord contract),
# so the OR-form arms are retired; the discipline they encoded — the guard
# must be provably NON-vacuous (fabricated-row controls, never "empty diff
# ⇒ pass") — carries over onto the shipped guards in $TMP/family.py:
#   (a) the repo-history anchors still resolve (the cf-52-era operational
#       bases, now historical facts, and the integrated-line ancestor);
#   (b) parity control: a fabricated extra permission row appended to a copy
#       of an alias twin must make the drift guard REJECT the pair;
#   (c) policy controls: the real -pr file must effectively deny
#       `git push origin main`; stripping the trailing denies from a TMP copy
#       must flip that verdict to allow — proving the deny rows are load-
#       bearing in the shipped matcher, not decorative;
#   (c2) cf-72 adds the twin flip on the alias/-local side: stripping the
#       declared T-2 tail from a TMP copy of a -local file must flip
#       `git push origin main` to allow — the B block's broad `git *` allow
#       is real, so the tail alone stands between it and a published main;
#   (d) documentation discipline: the re-pinned coord-inwork i4 / gate t17
#       blocks keep the arm-aware line twin (atpos + empty-diff branch) and
#       their headers keep naming the historical bases + this ticket.
# RED before C03 (family files absent — the red names them), green after.
if want a10; then
  git rev-parse --verify "${ARM_A}^{commit}" >/dev/null 2>&1 \
    || fail "A10[family-integrity]: historical base $ARM_A not resolvable in this repo"
  git merge-base --is-ancestor "$INTEGRATED" HEAD 2>/dev/null \
    || fail "A10[family-integrity]: HEAD does not include the integrated-line landing $INTEGRATED (historical anchor for the dual-base discipline)"
  [ -f "${CF_SRC[1]}" ] || fail "A10[family-integrity]: ${CF_SRC[1]} missing — the coord-family guards cannot run before C03 (red-before-C03 by design)"
  # (b) parity negative control — one fabricated row must break the drift guard
  python3 - "${CF_SRC[0]}" "${CF_SRC[1]}" "$TMP/fab-alias.md" <<'PY'
import re, sys, yaml
src, twin, dst = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(twin).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, f"{twin}: no frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
perms = list(target.get("permissions") or [])
perms.append({"action": "question", "resource": "opencode api delete /api/session/*", "effect": "allow"})
target["permissions"] = perms
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  if python3 "$TMP/family.py" parity "${CF_SRC[0]}" "$TMP/fab-alias.md" >/dev/null 2>&1; then
    fail "A10[family-integrity]: NEGATIVE CONTROL FAILED — the parity guard accepted a fabricated permission row (it degenerated; alias drift would pass silently)"
  fi
  # (b2) naming negative control — dropping a kickoff naming row must red the
  # guard (the same shipped code the A12 live loop runs)
  python3 - "${CF_SRC[1]}" "$TMP/fab-naming.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, f"{src}: no frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
target["permissions"] = [p for p in (target.get("permissions") or [])
                         if p.get("action") != "opencode_session_move"]
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  if python3 "$TMP/family.py" naming "$TMP/fab-naming.md" >/dev/null 2>&1; then
    fail "A10[family-integrity]: NEGATIVE CONTROL FAILED — the naming guard accepted a file missing the session_move allow"
  fi
  # (c) push-policy controls on the -pr variant (real file denies main; stripping denies flips it)
  v=$(python3 "$TMP/family.py" policy "${CF_SRC[2]}" 'git push origin main' 2>/dev/null || true)
  [ "$v" = "deny" ] || fail "A10[family-integrity]: effective verdict for 'git push origin main' on agent-coord-pr is '$v', want deny (trailing main deny load-bearing; red-before-C03 when the file is absent)"
  v=$(python3 "$TMP/family.py" policy "${CF_SRC[2]}" 'git push origin feature-x' 2>/dev/null || true)
  [ "$v" = "allow" ] || fail "A10[family-integrity]: effective verdict for 'git push origin feature-x' on agent-coord-pr is '$v', want allow"
  python3 - "${CF_SRC[2]}" "$TMP/pr-stripped.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
perms = [p for p in (target.get("permissions") or [])
         if not (p.get("action") == "shell" and str(p.get("resource", "")).startswith("git push") and p.get("effect") == "deny")]
target["permissions"] = perms
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  v=$(python3 "$TMP/family.py" policy "$TMP/pr-stripped.md" 'git push origin main' 2>/dev/null || true)
  [ "$v" = "allow" ] || fail "A10[family-integrity]: NEGATIVE CONTROL FAILED — stripping the trailing deny rows did not flip 'git push origin main' to allow on the TMP copy (matcher is inert; the real guard would pass on drift)"
  # (c2) cf-72 tail-strip control on a -local file: removing the declared T-2
  # push rows from a TMP copy of agent-coord-local must flip
  # 'git push origin main' to allow — the broad `git *` allow is real, so
  # only the tail stands between it and a published main (non-vacuity of the
  # substring floor, the same discipline (c) proves for -pr's T-7).
  python3 - "${CF_SRC[1]}" "$TMP/local-stripped.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
rows = target.get("permissions") or []
kept = [p for p in rows if not (p.get("action") == "shell" and p.get("effect") == "deny"
                                 and p.get("resource") in ("git push*", "git *push*"))]
assert len(rows) - len(kept) == 2, f"fixture: T-2 must be exactly the two declared deny rows, found {len(rows) - len(kept)}"
target["permissions"] = kept
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  v=$(python3 "$TMP/family.py" policy "$TMP/local-stripped.md" 'git push origin main' 2>/dev/null || true)
  [ "$v" = "allow" ] || fail "A10[family-integrity]: NEGATIVE CONTROL FAILED — stripping the T-2 push tail did not flip 'git push origin main' to allow on the -local TMP copy (verdict '$v') — the tail-strip non-vacuity control is inert"
  # (d) the re-pinned sibling blocks keep their shipped line twins + header discipline
  for f in "$SUITE_SURFACE" "$SUITE_GATE"; do
    python3 "$TMP/blockwin.py" "$f" "$( [ "$f" = "$SUITE_SURFACE" ] && echo i4 || echo t17 )" \
      'git diff --quiet "$BASE"' 'atpos.py' \
      || fail "A10[family-integrity]: $f's re-pinned block lacks the arm-aware line twin (empty-diff branch or atpos call) — the cf-58 re-pin did not land"
  done
  python3 "$TMP/sectgrep.py" "$SUITE_SURFACE" all \
    '081b57889' 'f11bfcb85' '916044893' 'historical' 'arm A' 'arm B' 'cf-58' \
    || fail "A10[family-integrity]: $SUITE_SURFACE header lost the cf-52-era base documentation (arm A/arm B refs, historical markers) or the cf-58 re-pin note"
  python3 "$TMP/sectgrep.py" "$SUITE_GATE" all \
    '081b57889' 'f11bfcb85' '916044893' 'historical' 'arm A' 'arm B' 'cf-58' \
    || fail "A10[family-integrity]: $SUITE_GATE header lost the cf-52-era base documentation (arm A/arm B refs, historical markers) or the cf-58 re-pin note"
  ok "A10[family-integrity]: parity/policy/naming guards reject fabricated drift and flip on stripped push tails on BOTH classes (negative controls pass), the history anchors resolve, and the re-pinned sibling blocks keep their shipped twins"
fi

# --- A11: agent-dev variant pair — git rows + push policy + wiring (C02) --------
# C02 AC2/AC3: the git block exactly per the Tasks list (reads → add → commit
# → push policy, last-match-wins order), the pr MUST-load of
# /pipeline-push-pr, the local silence about it, the descriptions naming the
# one difference, source<->mirror honesty, and the retired pre-split files
# gone from source AND generated.
if want a11; then
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    [ -f "$f" ] || fail "A11[C02]: $f missing (red before C02 — the dev-role split has not landed)"
    case "$f" in
      *local*) python3 "$TMP/family.py" gitrows "$f" devlocal || fail "A11[C02]: $f violates the declared devlocal git rows";;
      *pr*)    python3 "$TMP/family.py" gitrows "$f" devpr    || fail "A11[C02]: $f violates the declared devpr git rows";;
    esac
  done
  retired_src=".rulesync/subagents/agent-de""v.md"   # path assembled — A13's own sweep would flag the literal
  retired_gen=".opencode/agents/agent-de""v.md"
  [ ! -f "$retired_src" ] || fail "A11[C02]: $retired_src still present — C02 retires the pre-split source (red before C02)"
  [ ! -f "$retired_gen" ] || fail "A11[C02]: $retired_gen still present — rulesync generate (delete: true) must sweep it (red before C02)"
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN"; do
    v=$(python3 "$TMP/family.py" policy "$f" 'git push origin feature-x' 2>/dev/null || true)
    [ "$v" = "deny" ] || fail "A11[C02]: $f effective push verdict '$v', want deny (the explicit deny is the loud-failure guard)"
  done
  for f in "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    for cmd in 'git push origin main' 'git push HEAD:main' 'git push feature:main' \
               'git push --force origin feature-x' 'git push -f origin feature-x' 'git push origin feature-x --force'; do
      v=$(python3 "$TMP/family.py" policy "$f" "$cmd" 2>/dev/null || true)
      [ "$v" = "deny" ] || fail "A11[C02]: $f '$cmd' verdict '$v', want deny (trailing main/force denies)"
    done
    grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$f" \
      || fail "A11[C02]: $f does not MUST-load /pipeline-push-pr (pr list gains it after /pipeline-role-dev)"
    grep -qF 'pipeline-role-dev' "$f" || fail "A11[C02]: $f lost the /pipeline-role-dev MUST-load (implementer contract unchanged)"
  done
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN"; do
    grep -qF 'pipeline-push-pr' "$f" && fail "A11[C02]: $f references pipeline-push-pr — the local variant must never see the push skill (C02: local's list is unchanged)"
  done
  python3 "$TMP/win.py" "$DEV_LOCAL_SRC" 600 'commits' 'never pushes' \
    || fail "A11[C02]: the local description does not name its difference ('commits only, never pushes' — C02 Tasks)"
  python3 "$TMP/win.py" "$DEV_PR_SRC" 600 'pushes' 'remote build/test' \
    || fail "A11[C02]: the pr description does not name its difference ('pushes the ticket branch for remote build/test' — C02 Tasks)"
  # cf-76 C02 (D7) — the commit-ownership contract in suite form: pipeline
  # implementers evaluate to DENY for add/commit (work stays in the tree for
  # the coordinator), the coord family evaluates to ALLOW (coord is the sole
  # committer, one commit per chunk). Mirrors how the standalone-agents suite
  # pins its no-git-write roster — verdicts, not row presence alone.
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    v=$(python3 "$TMP/family.py" policy "$f" 'git commit -m x' 2>/dev/null || true)
    [ "$v" = "deny" ] || fail "A11[C02]: $f 'git commit -m x' verdict '$v', want deny (implementers never commit — D7)"
    v=$(python3 "$TMP/family.py" policy "$f" 'git add -A' 2>/dev/null || true)
    [ "$v" = "deny" ] || fail "A11[C02]: $f 'git add -A' verdict '$v', want deny (the coordinator stages the chunk)"
  done
  for f in "${CF_SRC[1]}" "${CF_SRC[4]}"; do
    v=$(python3 "$TMP/family.py" policy "$f" 'git commit -m x' 2>/dev/null || true)
    [ "$v" = "allow" ] || fail "A11[C02]: $f 'git commit -m x' verdict '$v', want allow (the sole-committer half of the contract — agent-coord-local / agent-board-coord-local)"
  done
  # Negative control (cf-52 non-vacuity rule): the matcher must be
  # effect-sensitive — flip the dev-local commit deny onto allow in a TMP
  # copy and require the verdict to move. A control that cannot move means
  # the real guard would pass on drifted rows forever.
  python3 - "$DEV_LOCAL_SRC" "$TMP/flip-control.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, "no frontmatter"
data = yaml.safe_load(m.group(1))
rows = ((data.get("opencode") or {}).get("permissions")) or data.get("permissions") or []
flipped = False
for r in rows:
    if r.get("action") == "shell" and r.get("resource") == "git commit *" and r.get("effect") == "deny":
        r["effect"] = "allow"
        flipped = True
assert flipped, "control fixture: no 'git commit * deny' row found to flip"
open(dst, "w").write("---\n" + yaml.safe_dump(data) + "---\n" + m.group(2))
PY
  v=$(python3 "$TMP/family.py" policy "$TMP/flip-control.md" 'git commit -m x' 2>/dev/null || true)
  [ "$v" = "allow" ] || fail "A11[C02]: NEGATIVE CONTROL FAILED — flipping the deny row did not move the verdict ('$v'), the matcher is inert"
  ok "A11[C02]: dev-variant pair carries the declared git rows in order (cf-76: add/commit DENY), effective push AND commit policy per family, the commit-ownership control proves the matcher; the pr-only push-skill wiring + naming descriptions; pre-split files retired"
fi

# --- A12: coord family — six files, alias parity, block order, rosters (C03) ----
# C03 AC1-AC3. The alias↔local parity is the drift guard the plan calls the
# ticket's new silent-failure mode; it runs on BOTH the sources (where drift
# is written) and the generated mirrors (where a half-regenerated pair hides).
if want a12; then
  # AC6 verdict matrix (cf-72): chunks/C01.md "Tests" — every declared cell,
  # class<TAB>want<TAB>command. G1/G2 apply to both classes; G3/G4/G5 carry
  # the per-class expectations the chunk's groups state (T-2 owns alias/
  # -local's blanket push denial, T-7 owns -pr's main/force/zero-arg shapes;
  # the "only" labels name the governing tail, not a cross-class allow — a
  # -pr main-leg deny also lands on -local, via the broader T-2 blanket).
  # policybatch re-evaluates each command through family.py's shipped
  # last-match loop — the suite's own projection, never a second matcher.
  cat >"$TMP/ac6.matrix" <<'AC6'
# G1 — ALLOW on ALL SIX files (chunks/C01.md first matrix paragraph; the
# chunk's shorthand cells are lifted concretely: "git -C <any> show" with the
# same repo path the adjacent cell uses, "lock/unlock" as two cells).
local	allow	git status
pr	allow	git status
local	allow	git status --porcelain
pr	allow	git status --porcelain
local	allow	git -C /home/coder/SpencersLab log --oneline main..HEAD
pr	allow	git -C /home/coder/SpencersLab log --oneline main..HEAD
local	allow	git -C /home/coder/SpencersLab show HEAD:AGENTS.md
pr	allow	git -C /home/coder/SpencersLab show HEAD:AGENTS.md
local	allow	git worktree list
pr	allow	git worktree list
local	allow	git worktree add /tmp/x feat-1
pr	allow	git worktree add /tmp/x feat-1
local	allow	git worktree remove /tmp/x
pr	allow	git worktree remove /tmp/x
local	allow	git worktree prune
pr	allow	git worktree prune
local	allow	git worktree lock /tmp/x feat-1
pr	allow	git worktree lock /tmp/x feat-1
local	allow	git worktree unlock /tmp/x feat-1
pr	allow	git worktree unlock /tmp/x feat-1
local	allow	git -C /tmp/x checkout other-branch
pr	allow	git -C /tmp/x checkout other-branch
local	allow	git add -A
pr	allow	git add -A
local	allow	git commit -m x
pr	allow	git commit -m x
local	allow	git commit --amend
pr	allow	git commit --amend
local	allow	git -C /tmp/x commit --amend
pr	allow	git -C /tmp/x commit --amend
local	allow	git reset --hard HEAD~1
pr	allow	git reset --hard HEAD~1
local	allow	git clean -fdx
pr	allow	git clean -fdx
local	allow	git rebase main
pr	allow	git rebase main
local	allow	git rebase -i main
pr	allow	git rebase -i main
local	allow	git cherry-pick abc
pr	allow	git cherry-pick abc
local	allow	git revert abc
pr	allow	git revert abc
local	allow	git fetch
pr	allow	git fetch
local	allow	git fetch origin main
pr	allow	git fetch origin main
local	allow	git checkout -b cf-99-x main
pr	allow	git checkout -b cf-99-x main
local	allow	git checkout -B cf-99-x main
pr	allow	git checkout -B cf-99-x main
local	allow	git -C /tmp/wk checkout -b cf-99-x main
pr	allow	git -C /tmp/wk checkout -b cf-99-x main
local	allow	git switch -c cf-99-x main
pr	allow	git switch -c cf-99-x main
local	allow	git worktree add -b feat2 /tmp/y main
pr	allow	git worktree add -b feat2 /tmp/y main
local	allow	git merge main
pr	allow	git merge main
local	allow	git -C /tmp/wk merge main
pr	allow	git -C /tmp/wk merge main
local	allow	git merge --abort
pr	allow	git merge --abort
local	allow	git -C /tmp/wk merge --abort
pr	allow	git -C /tmp/wk merge --abort
local	allow	git branch -d old-branch
pr	allow	git branch -d old-branch
local	allow	git branch -M feat3 feat2
pr	allow	git branch -M feat3 feat2
local	allow	git ls-remote
pr	allow	git ls-remote
# G2 — DENY on ALL SIX files: the make-main-HEAD legs (incl. every -C twin),
# plumbing, main-targeted branch verbs, pull, merge-INTO-non-main, the alias
# cap and the force family. `git log --grep push` denies class-wide: via the
# T-2 substring row on alias/-local, via T-7's `git * push` zero-arg row on
# -pr (the chunk's "(substring, -local class)" note names the -local leg).
local	deny	git checkout main
pr	deny	git checkout main
local	deny	git checkout main-2
pr	deny	git checkout main-2
local	deny	git -C /home/coder/SpencersLab checkout main
pr	deny	git -C /home/coder/SpencersLab checkout main
local	deny	git checkout -B main feature
pr	deny	git checkout -B main feature
local	deny	git -C x checkout -B main feature
pr	deny	git -C x checkout -B main feature
local	deny	git switch main
pr	deny	git switch main
local	deny	git -C x switch main
pr	deny	git -C x switch main
local	deny	git update-ref refs/heads/main abc
pr	deny	git update-ref refs/heads/main abc
local	deny	git -C x update-ref refs/heads/main abc
pr	deny	git -C x update-ref refs/heads/main abc
local	deny	git symbolic-ref HEAD refs/heads/main
pr	deny	git symbolic-ref HEAD refs/heads/main
local	deny	git branch -f main feature
pr	deny	git branch -f main feature
local	deny	git -C x branch -f main feature
pr	deny	git -C x branch -f main feature
local	deny	git branch --force main feature
pr	deny	git branch --force main feature
local	deny	git branch -d main
pr	deny	git branch -d main
local	deny	git branch -D main
pr	deny	git branch -D main
local	deny	git branch -m feat main
pr	deny	git branch -m feat main
local	deny	git -C x branch -m feat main
pr	deny	git -C x branch -m feat main
local	deny	git branch -M feat main
pr	deny	git branch -M feat main
local	deny	git branch -c feat main
pr	deny	git branch -c feat main
local	deny	git branch -C feat main
pr	deny	git branch -C feat main
local	deny	git worktree add /tmp/w main
pr	deny	git worktree add /tmp/w main
local	deny	git -C x worktree add /tmp/w main
pr	deny	git -C x worktree add /tmp/w main
local	deny	git pull
pr	deny	git pull
local	deny	git -C x pull --rebase
pr	deny	git -C x pull --rebase
local	deny	git merge feature-x
pr	deny	git merge feature-x
local	deny	git -C /home/coder/SpencersLab merge feature-x
pr	deny	git -C /home/coder/SpencersLab merge feature-x
local	deny	git config alias.p push
pr	deny	git config alias.p push
local	deny	git -C x config alias.p 'push --force'
pr	deny	git -C x config alias.p 'push --force'
local	deny	git checkout -f feat
pr	deny	git checkout -f feat
local	deny	git clean -f -d
pr	deny	git clean -f -d
local	deny	git worktree remove --force /tmp/x
pr	deny	git worktree remove --force /tmp/x
local	deny	git fetch --force origin feat
pr	deny	git fetch --force origin feat
local	deny	git rebase -f upstream
pr	deny	git rebase -f upstream
local	deny	git log --grep push
pr	deny	git log --grep push
# G3 — DENY on alias/-local (T-2). The pr-side want follows chain (4): plain
# and quoted-arg push live on -pr (D15's substring row is absent BY DESIGN
# there); the -C zero-arg, main-refspec and force shapes stay denied.
local	deny	git push
pr	allow	git push
local	deny	git push origin feature
pr	allow	git push origin feature
local	deny	git -C /tmp/x push
pr	deny	git -C /tmp/x push
local	deny	git -C /home/coder/SpencersLab push origin main
pr	deny	git -C /home/coder/SpencersLab push origin main
local	deny	git -C /home/coder/SpencersLab push --force origin feature-x
pr	deny	git -C /home/coder/SpencersLab push --force origin feature-x
local	deny	git commit -am 'push posture'
pr	allow	git commit -am 'push posture'
# G4 — ALLOW only on -pr (feature push lives; the blanket T-2 denies each on
# alias/-local).
local	deny	git push origin feature-x
pr	allow	git push origin feature-x
local	deny	git push -u origin feature-x
pr	allow	git push -u origin feature-x
local	deny	git -C /tmp/wk push origin feature-x
pr	allow	git -C /tmp/wk push origin feature-x
# G5 — DENY on -pr (T-7): main-leg refspecs, the zero-arg -C footgun and
# every force spelling incl. --force-with-lease (D14 never-force ruling).
# Alias/-local denies the same shapes via its blanket tail, so want is deny
# on both classes — the group names the TAIL that carries them where push
# otherwise lives. (`git push` and `git push origin feature` ride G3/G4
# rows: the same command+want pair would duplicate cells, not coverage.)
local	deny	git push origin main
pr	deny	git push origin main
local	deny	git push HEAD:main
pr	deny	git push HEAD:main
local	deny	git push origin feature-x:main
pr	deny	git push origin feature-x:main
local	deny	git -C x push origin main
pr	deny	git -C x push origin main
local	deny	git -C x push :main
pr	deny	git -C x push :main
local	deny	git -C /home/coder/SpencersLab push
pr	deny	git -C /home/coder/SpencersLab push
local	deny	git push --force origin feature
pr	deny	git push --force origin feature
local	deny	git push -f origin feature
pr	deny	git push -f origin feature
local	deny	git -C x push -f
pr	deny	git -C x push -f
local	deny	git push -P origin feature
pr	deny	git push -P origin feature
local	deny	git push --force-with-lease origin feat
pr	deny	git push --force-with-lease origin feat
local	deny	git -C /tmp/wk push --force-with-lease HEAD:feature-x
pr	deny	git -C /tmp/wk push --force-with-lease HEAD:feature-x
AC6
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    [ -f "$f" ] || fail "A12[C03]: $f missing (red before C03 — six coord-family agents + mirrors are the C03 shape)"
  done
  python3 "$TMP/family.py" parity "${CF_SRC[0]}" "${CF_SRC[1]}" \
    || fail "A12[C03]: agent-coord alias and agent-coord-local drifted apart (sources) — the same-commit parity rule"
  python3 "$TMP/family.py" parity "${CF_SRC[3]}" "${CF_SRC[4]}" \
    || fail "A12[C03]: agent-board-coord alias and agent-board-coord-local drifted apart (sources)"
  python3 "$TMP/family.py" parity "${CF_GEN[0]}" "${CF_GEN[1]}" \
    || fail "A12[C03]: coord alias/mirror-pair drift on the generated surfaces"
  python3 "$TMP/family.py" parity "${CF_GEN[3]}" "${CF_GEN[4]}" \
    || fail "A12[C03]: board-coord alias/mirror-pair drift on the generated surfaces"
  for i in 0 1 2 3 4 5; do
    f="${CF_SRC[$i]}"; g="${CF_GEN[$i]}"
    python3 "$TMP/family.py" api "$f" || fail "A12[C03]: $f in-work-mark API containment broken"
    python3 "$TMP/family.py" api "$g" || fail "A12[C03]: $g in-work-mark API containment broken"
    # *-pr.md, not *-pr: the files end in .md, so a bare *-pr would never
    # match and every -pr file would fall through to the -local arms —
    # unsatisfiable for correct content AND blind to a stale -pr roster
    # (validation_at_fault round 3).
    case "$f" in
      *-pr.md) slot=agent-dev-pr; cls=pr;;
      *)       slot=agent-dev-local; cls=local;;
    esac
    python3 "$TMP/family.py" roster "$f" "$slot" || fail "A12[C03]: $f roster dev slot wrong (want $slot)"
    python3 "$TMP/family.py" gitrows "$f" "$cls"  || fail "A12[C03]: $f git block wrong for class $cls"
    python3 "$TMP/family.py" policybatch "$f" "$cls" <"$TMP/ac6.matrix" >/dev/null \
      || fail "A12[AC6-matrix]: $f (class $cls) verdicts a cf-72 matrix cell differently than declared — the broad allow, the floor's ORDER, the re-allows or the push tail drifted from the chunk contract (failing cells named above; table = $TMP/ac6.matrix)"
    python3 "$TMP/family.py" policybatch "$g" "$cls" <"$TMP/ac6.matrix" >/dev/null \
      || fail "A12[AC6-matrix]: generated mirror $g (class $cls) verdicts a cf-72 matrix cell wrong — the mirror is the runtime surface; a regen that parses to different verdicts is a defect, not noise"
    python3 "$TMP/family.py" naming "$f" || fail "A12[C03]: $f kickoff naming surface broken (want the execute allow + the four opencode_* allows in order)"
    python3 "$TMP/family.py" naming "$g" || fail "A12[C03]: $g kickoff naming surface broken on the generated mirror"
    case "$f" in
      *board-coord*) python3 "$TMP/family.py" board "$f" || fail "A12[C03]: $f board extras (dev-boards*/execute) broken";;
    esac
    python3 "$TMP/pairsync.py" "$f" "$g" agent \
      || fail "A12[C03]: $f and $g out of sync — regenerate, never hand-edit .opencode/"
  done
  # MUST-load wiring: /pipeline-push-pr ONLY on the -pr pair (sources + mirrors)
  for f in "${CF_SRC[2]}" "${CF_GEN[2]}" "${CF_SRC[5]}" "${CF_GEN[5]}"; do
    grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$f" \
      || fail "A12[C03]: -pr family file $f does not MUST-load /pipeline-push-pr"
  done
  for i in 0 1 3 4; do
    for f in "${CF_SRC[$i]}" "${CF_GEN[$i]}"; do
      grep -qF 'pipeline-push-pr' "$f" && fail "A12[C03]: $f (non-pr) references the push skill — aliases never carry -pr behavior"
    done
  done
  # alias description tags (C03 pins them)
  grep -qF 'commit-only alias of agent-coord-local' "${CF_SRC[0]}" \
    || fail "A12[C03]: the agent-coord alias lacks its '(commit-only alias of agent-coord-local...)' description tag"
  grep -qF 'commit-only alias of agent-board-coord-local' "${CF_SRC[3]}" \
    || fail "A12[C03]: the agent-board-coord alias lacks its '(commit-only alias of agent-board-coord-local...)' description tag"
  ok "A12[C03 + cf-72 AC6]: six coord-family agents (+mirrors) exist and sync; alias↔local parity holds; API containment, git-block order (B block 70/75), roster dev slots, board extras, and the -pr-only push wiring all carry the C03 shape; every AC6 matrix cell evaluates as declared through family.py on sources AND mirrors"
fi

# --- A13: rename sweep + command→agent pairing (C02 AC5 + C03 AC4/AC7) ----------
# Binding surfaces (agent/command sources + generated mirrors) must carry NO
# bare pre-split dev-role reference — a bare name there would re-grant or
# re-launch the retired single agent. Prose mirrors are pinned positively
# instead (roster-row presence + retired-path absence + clean named
# sections); judgment recorded in this file's header. Command pairing is the
# C03 AC4 table, checked in source AND generated frontmatter.
if want a13; then
  hits=$(python3 - <<'PY'
import re, sys, glob
# Build the retired-role pattern without embedding the literal token, so the
# sweep file itself stays clean under its own rule (the token is
# reconstructed from its two halves at runtime).
tok = "agent-de" + "v"
pat = re.compile(tok + r"(?![-]pr|[-]local)")
bad = []
for root in (".rulesync/subagents", ".rulesync/commands", ".opencode/agents", ".opencode/commands"):
    for p in glob.glob(root + "/*.md") + glob.glob(root + "/**/*.md"):
        for i, line in enumerate(open(p), 1):
            if pat.search(line):
                bad.append(f"{p}:{i}: {line.strip()}")
print("\n".join(bad))
PY
)
  # Era split: hits in the dev-role's OWN surfaces must clear with C02;
  # hits inside the coord-family files are C03's roster-rewrite territory
  # (C02's diff is surgical per its chunk), so they only fail once the
  # family exists and still carries the retired reference.
  hits_c02=$(printf '%s\n' "$hits" | grep -v 'agent-coord\|agent-board-coord' || true)
  hits_c03=$(printf '%s\n' "$hits" | grep 'agent-coord\|agent-board-coord' || true)
  [ -z "$hits_c02" ] || { printf '%s\n' "$hits_c02" >&2; fail "A13[C02 AC5]: bare pre-split dev-role reference in a binding surface (wiring that launches/grants the retired agent) — red before C02"; }
  if [ -f .rulesync/subagents/agent-coord-local.md ] && [ -n "$hits_c03" ]; then
    printf '%s\n' "$hits_c03" >&2
    fail "A13[C03 AC7]: the coord-family files exist but still reference the retired dev-role name — the roster rewrite did not land everywhere"
  fi
  tests_hits=$(python3 - <<'PY'
import re, sys, glob
# The suite-side form: a QUOTED roster name (the token inside "..." or '...')
# pins the retired agent inside another suite's roster assertion, and a bare
# case-arm PATH literal re-admits the retired file into a scope allow-set.
# The pinned-copy arm of the standalone suite LEGITIMATELY reads the retired
# agent's block from the ticket base (C04 Tasks), so lines running git show /
# git cat-file against that path are history loads, not wiring — allowed.
tok = "agent-de" + "v"
quoted = re.compile(r"[\"']" + tok + r"[\"']")
casepath = re.compile(r"(\.rulesync/subagents/|\.opencode/agents/)" + tok + r"\.md")
history = re.compile(r"git (show|cat-file)\b")
# Scope: the cf-58 suite files only — every other suite's pins belong to
# other tickets' bases and legitimately name historical paths; requiring
# this ticket to edit them would break one-branch-one-concern.
suites = ["tests/agent-perms/surface.sh", "tests/coord-inwork/surface.sh",
          "tests/agent-board-coord/gate.sh", "tests/agent-board-coord/rulesync-surface.sh",
          "tests/agent-board-coord/agents-md.sh", "tests/pipeline-push-pr/surface.sh",
          "tests/standalone-agents/surface.sh", "tests/pipeline-models/surface.sh"]
bad = []
for p in suites:
    for i, line in enumerate(open(p), 1):
        if quoted.search(line) or (casepath.search(line) and not history.search(line)):
            bad.append(f"{p}:{i}: {line.strip()}")
print("\n".join(bad))
PY
)
  [ -z "$tests_hits" ] || { printf '%s\n' "$tests_hits" >&2; fail "A13[C02 AC5]: a suite still names the retired agent in a roster list or case path — re-pin did not land (red before C02)"; }
  # Two-era prose pin (the pins move where the contract moves): C02's exact
  # roster literal is the wording until C03 rewrites the Agents bullet to
  # name the coord variants; the dev-variant names + pre-split-row absence
  # hold in BOTH eras.
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'dev-pr' "$f" && grep -qF 'dev-local' "$f" \
      || fail "A13[C02 AC5]: $f never names the dev variants (red before C02)"
    grep -qF 'agent-{coord,plan,research,test,dev,review,fuser,board-coord}' "$f" \
      && fail "A13[C02 AC5]: $f still carries the pre-split roster row verbatim (red before C02)"
    if [ -f .rulesync/subagents/agent-coord-local.md ]; then
      for name in agent-coord-local agent-coord-pr agent-board-coord-local agent-board-coord-pr; do
        grep -qF "$name" "$f" || fail "A13[C03 AC7]: $f never names $name — C03's rewritten Agents bullet must carry the coord variants"
      done
      grep -qF '/pipeline-pr' "$f" || fail "A13[C03 AC4]: $f never names the /pipeline-pr command (launch-sentence rewrite)"
    else
      grep -qF 'agent-{coord,plan,research,test,dev-pr,dev-local,review,fuser,board-coord}' "$f" \
        || fail "A13[C02 AC5]: $f lacks C02's pinned post-split roster row — red before C02"
    fi
    if [ -f .rulesync/subagents/agent-coord-local.md ]; then
      # C03-era: the Agents/Feature-pipeline prose has been rewritten, so no
      # bare pre-split dev-role mention may survive there. Pre-C03 the prose
      # lines belong to C03's overview task (C02's diff is surgical per its
      # chunk), so the scan is era-gated like the roster pins above.
      python3 - "$f" <<'PY' || fail "A13[C03 AC7]: $f Agents / Feature-pipeline sections still carry a bare pre-split dev-role reference after the coord rewrite"
import re, sys
tok = "agent-de" + "v"
pat = re.compile(tok + r"(?![-]pr|[-]local)")
section = None
bad = []
for i, line in enumerate(open(sys.argv[1]), 1):
    m = re.match(r"^## +(.+?)\s*$", line)
    if m:
        section = m.group(1)
    if section in ("Agents", "Feature pipeline (agent-*)") and pat.search(line):
        bad.append(f"line {i} in section '{section}'")
print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
    fi
  done
  # C03 AC4 command→agent pairing — source AND generated frontmatter target.
  # The four PRE-EXISTING pairings + the hourly-never-pr rule hold in BOTH
  # eras (plain targets are C03-unchanged); the three -pr commands and the
  # pointer lines ship WITH pipeline-pr.md itself, so their arms self-engage
  # on its existence — same era-gating pattern as the AGENTS/RULES pins
  # above. Without the gate A13's C02-era sweep coverage (the rename sweep
  # is C02's own AC5) would be held hostage by unlanded C03 content.
  pair() { # cmd-name  want-agent
    local c="$1" a="$2"
    for d in ".rulesync/commands" ".opencode/commands"; do
      local f="$d/$c.md"
      [ -f "$f" ] || fail "A13[C03 AC4]: $f missing (red before C03 — the -pr commands ship with the family)"
      grep -qE "^([[:space:]]*)?agent:[[:space:]]+$a\$" "$f" \
        || { grep -n 'agent:' "$f" >&2 || true; fail "A13[C03 AC4]: $f does not target agent $a"; }
    done
  }
  pair pipeline agent-coord
  pair pipeline-resume agent-coord
  pair pipeline-boards agent-board-coord
  pair pipeline-boards-hourly agent-board-coord
  # the hourly command never points at a -pr variant (an unattended run never pushes)
  ! grep -qE 'agent:[[:space:]]+.*-pr' .rulesync/commands/pipeline-boards-hourly.md .opencode/commands/pipeline-boards-hourly.md \
    || fail "A13[C03 AC4]: pipeline-boards-hourly targets a -pr agent — scheduled runs stay -local semantics (R2)"
  if [ -f .rulesync/commands/pipeline-pr.md ]; then
    pair pipeline-pr agent-coord-pr
    pair pipeline-resume-pr agent-coord-pr
    pair pipeline-boards-pr agent-board-coord-pr
    # pointer lines on the four plain commands (C03 Tasks)
    grep -qF '/pipeline-pr' .rulesync/commands/pipeline.md \
      || fail "A13[C03 AC4]: pipeline.md lacks the '/pipeline-pr' pointer line (red before C03)"
    grep -qF '/pipeline-pr' .rulesync/commands/pipeline-resume.md \
      || fail "A13[C03 AC4]: pipeline-resume.md lacks the '/pipeline-pr' pointer line (red before C03)"
    grep -qF '/pipeline-boards-pr' .rulesync/commands/pipeline-boards.md \
      || fail "A13[C03 AC4]: pipeline-boards.md lacks the '/pipeline-boards-pr' pointer line (red before C03)"
    grep -qF '/pipeline-boards-pr' .rulesync/commands/pipeline-boards-hourly.md \
      || fail "A13[C03 AC4]: hourly command lacks the '/pipeline-boards-pr' pointer line (red before C03)"
    a13_pair_note="seven commands paired (plain→aliases, -pr→variants), pointer lines landed"
  else
    a13_pair_note="-pr command trio absent yet — its pairing + pointer arms engage with pipeline-pr.md (red-before-C03 by era, not a C02 failure)"
  fi
  ok "A13[C02 AC5 + C03 AC4/AC7]: binding surfaces and suites free of the retired dev-role wiring; AGENTS.md/rules roster row era-correct; four plain commands pair unchanged, hourly never -pr; $a13_pair_note"
fi

# --- A14: MCP action-glob spelling vs the project's registered server names ---
# 2026-10-bug-board-coord-dev-boards-allow AC6. OpenCode registers each MCP
# tool as `<config server name>_<tool>` with hyphens kept (opencode.ai docs
# "Glob patterns": my-mcp* matches my-mcp_search), so an action glob that
# re-spells a server name with underscores matches NOTHING and dies silently
# behind the family's leading deny-all — the dev_boards* failure that cost
# board runs their native board surface. Offline by construction: parses the
# subagent sources plus .opencode/opencode.jsonc, no OpenCode runtime. Scope:
# project-registered servers only — machine-global fleet names are not repo-
# resolvable, and separator-free family-wide globs (dev*, readonly*, admin*,
# global*) stay exempt because they match by leading segment under any reading.
# Red posture: against the pre-fix frontmatter this check REDS on all three
# board-coord files — verified 2026-10-27 against git base 4813c13d3 before
# the source re-spell landed. The live matcher proof (AC7) rides on the next
# agent-board-coord launch, not on this suite.
if want a14; then
  cat >"$TMP/mcpshape.py" <<'PY'
import json, re, sys, glob, yaml

def strip_jsonc(s):
    out, i, n, instr, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
            i += 1
            continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c); i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))

SERVERS = set(json.loads(strip_jsonc(open(".opencode/opencode.jsonc").read()))
              .get("mcp", {}).get("servers", {}))
FAMILY = ("dev", "admin", "readonly", "global")

def offenders(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    if not m:
        return []
    fm = yaml.safe_load(m.group(1)) or {}
    perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
    bad = []
    for p in perms:
        a = str(p.get("action", ""))
        if not a.endswith("*"):
            continue
        stem = a[:-1].split("*")[0]
        if stem in FAMILY:
            continue
        if stem.startswith(FAMILY) and stem not in SERVERS:
            bad.append(a)
    return bad

if len(sys.argv) == 3 and sys.argv[1] == "control":
    sys.exit(0 if offenders(sys.argv[2]) else 1)

hits = []
for path in sorted(glob.glob(".rulesync/subagents/agent-*.md")):
    hits += [f"{path}: {a}" for a in offenders(path)]
if hits:
    print("; ".join(hits))
    sys.exit(1)
PY
  python3 "$TMP/mcpshape.py" \
    || fail "A14[AC6]: a server-name-shaped MCP action glob diverges from the registered server name by separator substitution — the dead-literal class (2026-10-bug-board-coord-dev-boards-allow)"
  sed 's/dev-boards\*/dev_boards*/' .rulesync/subagents/agent-board-coord.md >"$TMP/fake-divergent.md"
  python3 "$TMP/mcpshape.py" control "$TMP/fake-divergent.md" \
    || fail "A14[AC6]: NEGATIVE CONTROL FAILED — the guard accepted a fabricated dev_boards* (it degenerated; real spelling drift would pass silently)"
  ok "A14[AC6]: every per-server MCP action glob in .rulesync/subagents/ equals a name registered in .opencode/opencode.jsonc mcp.servers verbatim (hyphen included); separator-substituted fabrication rejected; family-wide globs exempt"
fi

# --- A15: cf-76 C07 — pipeline_* lock surface on the board-coord trio ----------
# Red posture: engages once .opencode/plugin/pipeline-locks/index.ts exists
# (C03+), and stays RED until C07's permission rows + boards-skill text land
# — chunk subsets before C07 skip this check. Pins (C07 AC 1-4): the four
# allow rows on all three board-coord sources AND their generated mirrors;
# no OTHER subagent granted them (the lock surface belongs to the board
# family — agent-coord-local / agent-plan / agent-dev-local must evaluate
# non-allow); and the three-way single-source parity: the plugin's TOOL_NAMES
# constants == the permission-row actions == the call strings in the boards
# skill, plus the `Pipeline:` prefix and `default` pipeline constants
# mirrored in the skill text (the grep-parity discipline the rulesync
# suites run on the board-context block).
if want a15; then
  if [ ! -f .opencode/plugin/pipeline-locks/index.ts ]; then
    skip "a15: pipeline-locks plugin absent — the cf-76 lock surface has not landed (checks engage from C03 onward)"
  else
    for i in 3 4 5; do
      python3 "$TMP/family.py" locktools "${CF_SRC[$i]}" \
        || fail "A15[C07]: ${CF_SRC[$i]} lacks the four pipeline_* allow rows after dev-boards* (red before C07 dev)"
      python3 "$TMP/family.py" locktools "${CF_GEN[$i]}" \
        || fail "A15[C07]: generated mirror ${CF_GEN[$i]} lacks the rows — regenerate, never hand-edit .opencode/"
    done
    # The three sources must carry the SAME lock block (alias/pr parity is a
    # one-commit duty, C07 Tasks) — A12's parsed-equality covers alias↔local
    # wholesale; this pins the -pr twin on the new rows specifically.
    if ! python3 - "${CF_SRC[3]}" "${CF_SRC[4]}" "${CF_SRC[5]}" <<'PY'
import re, sys, yaml
def perms(p):
    m = re.match(r"^---\n(.*?)\n---\n", open(p).read(), re.S)
    assert m, f"{p}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
lock = lambda p: [r for r in perms(p) if str(r.get("action", "")).startswith("pipeline_")]
blocks = [lock(p) for p in sys.argv[1:4]]
if not (blocks[0] == blocks[1] == blocks[2]):
    print(f"pipeline_* blocks differ across the trio: {blocks}"); sys.exit(1)
PY
    then
      fail "A15[C07]: the three board-coord sources drifted on the pipeline_* block"
    fi
    # No other agent may hold the lock surface (C07 AC3).
    for f in .rulesync/subagents/agent-*.md; do
      case "$f" in
        *agent-board-coord*) continue ;;
      esac
      grep -qE 'action:[[:space:]]+pipeline_' "$f" \
        && fail "A15[C07]: $f grew a pipeline_* row — the board-coord family owns the lock surface (C07 AC3)"
    done
    for f in .rulesync/subagents/agent-coord-local.md .rulesync/subagents/agent-plan.md .rulesync/subagents/agent-dev-local.md; do
      v=$(python3 "$TMP/family.py" action "$f" 'pipeline_claim' 2>/dev/null || true)
      [ "$v" != "allow" ] || fail "A15[C07]: pipeline_claim evaluates to '$v' on $f — the lock surface must stay closed outside the board family (negative assert)"
    done
    # D19 retired the custom-field creation step (r1 D4 superseded): NO
    # surface this ticket touches may reference the dev-boards custom-field
    # create tool — pipeline identity is LABELS. Needle assembled from two
    # halves so this very suite cannot self-match the grep.
    CFN='create_custom_'"field"
    for f in .rulesync/skills/boards/SKILL.md .opencode/skills/boards/SKILL.md \
             "${CF_SRC[3]}" "${CF_SRC[4]}" "${CF_SRC[5]}" \
             "${CF_GEN[3]}" "${CF_GEN[4]}" "${CF_GEN[5]}" \
             .opencode/plugin/pipeline-locks/index.ts; do
      grep -q "$CFN" "$f" \
        && fail "A15[C07]: $f references $CFN — the custom-field route was retired with D19; the worker only READS Pipeline: labels"
    done
    # cf-85 RE-PIN of cf-76's roster fence (AC1/AC3): the flow's roster is now
    # exactly ONE board-level text field — `slug`, carrying the combined
    # `[<slug>](<session link>)` link — with the legacy `session` field named
    # only as retired and never read or written. cf-76's intent is unchanged:
    # the count is pinned, the sentence must keep naming the field the fence
    # protects, and neither the `models` route nor a third field may sneak
    # back in through a wording rewrite. Red until the flip commit lands.
    roster=$(grep -m1 -Ei '^[-*][[:space:]]+Custom fields:' .rulesync/skills/boards/SKILL.md || true)
    [ -n "$roster" ] \
      || fail "A15[cf-85 AC3]: the boards skill has no 'Custom fields:' roster bullet — the fence's anchor moved (harness fault, report it)"
    if echo "$roster" | grep -Eiq 'exactly (two|three)'; then
      fail "A15[cf-85 AC3]: the roster still counts the retired session field — the flow's roster is the single slug field (red until the flip lands)"
    fi
    echo "$roster" | grep -Eiq 'exactly one' \
      || fail "A15[cf-85 AC3]: the boards skill lost its 'Custom fields: exactly one' roster pin"
    echo "$roster" | grep -qF '`slug`' \
      || fail "A15[cf-85 AC3]: the roster sentence does not name the slug field"
    echo "$roster" | grep -Eq '\[<slug>\]\(' \
      || fail "A15[cf-85 AC3]: the roster does not state the combined [<slug>](<session link>) value the one field carries"
    echo "$roster" | grep -qF '`session`' \
      || fail "A15[cf-85 AC3]: the roster does not name the retired session field — the retirement belongs where the roster is stated"
    echo "$roster" | grep -Eiq 'retired|never (read|written|reads|writes)' \
      || fail "A15[cf-85 AC3]: the roster does not mark the session field retired / never read or written"
    echo "$roster" | grep -qF 'third field' \
      || fail "A15[C07 AC2]: the roster lost the third-field negation — the fence this guard exists for"
    echo "$roster" | grep -qF 'models' \
      || fail "A15[C07 AC2]: the roster lost the D12 no-models-field negation"
    # Fabricated-row control (A10/A14 discipline): drop one row from a TMP
    # copy and require the locktools guard to reject the crippled file.
    python3 - "${CF_SRC[3]}" "$TMP/lock-dropped.md" <<'PY'
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
data = yaml.safe_load(m.group(1))
rows = (data.get("opencode") or {}).get("permissions") or data["permissions"]
before = len(rows)
rows[:] = [r for r in rows if r.get("action") != "pipeline_heartbeat"]
assert len(rows) == before - 1, "fixture: pipeline_heartbeat row not found"
open(sys.argv[2], "w").write("---\n" + yaml.safe_dump(data) + "---\n" + m.group(2))
PY
    python3 "$TMP/family.py" locktools "$TMP/lock-dropped.md" >/dev/null 2>&1 \
      && fail "A15[C07]: NEGATIVE CONTROL FAILED — locktools accepted a file with the heartbeat row stripped (guard is inert)"
    # Three-way parity: plugin constants == row actions == boards-skill call
    # strings; label prefix + default pipeline mirrored into the skill text.
    if ! python3 - .opencode/plugin/pipeline-locks/index.ts "${CF_SRC[4]}" .rulesync/skills/boards/SKILL.md <<'PY'
import re, sys, yaml
src_path, agent_path, skill_path = sys.argv[1:4]
src = open(src_path).read()
def const_list(name):
    m = re.search(r"const\s+" + name + r"[^=\n]*=\s*\[([^\]]*)\]", src)
    assert m, f"plugin module no longer defines {name} as a single array literal (AC10 single source)"
    return re.findall(r'"([^"]+)"', m.group(1))
def const_str(name):
    m = re.search(r"const\s+" + name + r"[^=\n]*=\s*\"([^\"]*)\"", src)
    assert m, f"plugin module no longer defines {name} as a single string constant"
    return m.group(1)
tools = const_list("TOOL_NAMES")
assert len(tools) == 4 and all(t.startswith("pipeline_") for t in tools), f"TOOL_NAMES must be the four pipeline_* tools, saw {tools}"
m = re.match(r"^---\n(.*?)\n---\n", open(agent_path).read(), re.S)
fm = yaml.safe_load(m.group(1)) or {}
rows = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
row_actions = sorted(r.get("action") for r in rows if str(r.get("action", "")).startswith("pipeline_"))
if row_actions != sorted(tools):
    print(f"permission rows {row_actions} != plugin TOOL_NAMES {sorted(tools)}"); sys.exit(1)
skill = open(skill_path).read()
missing = [t for t in tools if t not in skill]
if missing:
    print(f"boards skill never names {missing} — the Parallel pipeline loops section and the plugin disagree on the tool surface (AC1 parity)"); sys.exit(1)
if const_str("LABEL_PREFIX") not in skill:
    print("the plugin's label prefix is not the string the boards skill teaches — single-source drift (D17)"); sys.exit(1)
if "`default`" not in skill:
    print("the boards skill lost the `default` pipeline fallback wording (D17)"); sys.exit(1)
PY
    then
      fail "A15[C07]: plugin/permission/skill three-way parity broken — one of the single sources drifted"
    fi
    ok "A15[C07]: the four pipeline_* allow rows carry across the board-coord trio (sources + mirrors, same block), no other agent granted, the negative verdicts hold, a fabricated row-drop is rejected, the plugin constants match the permission rows and the boards-skill call strings, and the roster fence holds the cf-85 one-field slug roster"
  fi
fi

# --- A16: board-tick-cleanup C01 — the explicit `ls *` allow everywhere --------
# User ruling 2026-10-29 ("Honestly, it should go on all agents"), interpreted
# by the plan as: every source carrying a permissions: block gains exactly one
# {shell, "ls *", allow} row. Pinned as three duties: row COUNT (AC1), EFFECTIVE
# verdict for 'ls -a' == allow on sources AND generated mirrors (AC4 — the
# verdict is the position test: agent-board's row must sit after its shell-'*'
# deny, else last-match-wins shadows it), and the MATRIX move (permissions.md
# rows + drift entry — the drift lesson a permission-block change is only done
# when its matrix row moved too). The nine stage agents verified permission-
# less (count fact, add nothing — plan Grounded facts W3).
# Red before C01 dev: the 12 lacking sources name their missing row; the
# matrix rows name their unmoved text. HOLD after landing.
if want a16; then
  mapfile -t permed < <(grep -l 'permissions:' .rulesync/subagents/*.md)
  [ "${#permed[@]}" -eq 22 ] \
    || fail "A16[C01 AC1]: ${#permed[@]} sources carry a permissions: block, want the plan's verified 22"
  no_perm_landing=$(grep -L 'permissions:' .rulesync/subagents/*.md | grep -v '/[0-9]' || true)
  [ -z "$no_perm_landing" ] \
    || fail "A16[C01 fact]: a NON-stage agent lost its permission block: $no_perm_landing (the nine stage agents are the permissionless set — W3 verified)"
  misses=$(grep -L 'resource: ls \*' "${permed[@]}" || true)
  [ -z "$misses" ] || { printf '%s\n' "$misses" >&2; fail "A16[C01 AC1]: the plan's grep -L over the permission-bearing sources is not empty — files missing the 'resource: ls *' row (HOLD since the C01 landing: a row drifted away)"; }
  for f in "${permed[@]}"; do
    c=$(grep -c 'resource: ls \*' "$f")
    [ "$c" -eq 1 ] || fail "A16[C01 AC1]: $f carries $c 'resource: ls *' rows, want exactly one"
    g=".opencode/agents/$(basename "$f")"
    [ -f "$g" ] || fail "A16[C01 AC5]: generated mirror $g missing"
    gm=$(grep -c 'resource: ls \*' "$g")
    [ "$gm" -eq 1 ] || fail "A16[C01 AC1/AC5]: mirror $g carries $gm ls rows, want exactly one (sources + generated land together)"
    python3 "$TMP/family.py" lsrow "$f" || fail "A16[C01 AC1]: $f parsed ls duty broken"
    python3 "$TMP/family.py" lsrow "$g" || fail "A16[C01 AC1]: $g parsed ls duty broken on the generated mirror"
    v=$(python3 "$TMP/family.py" policy "$f" 'ls -a' 2>/dev/null || true)
    [ "$v" = "allow" ] || fail "A16[C01 AC4]: $f effective verdict for 'ls -a' is '$v', want allow"
    v=$(python3 "$TMP/family.py" policy "$g" 'ls -a' 2>/dev/null || true)
    [ "$v" = "allow" ] || fail "A16[C01 AC4]: mirror $g verdict '$v', want allow"
  done
  # Negative controls (cf-52/cf-58 non-vacuity rule — the shipped guards must
  # reject drift): a stripped copy flips the verdict, a duplicated copy and an
  # effect-minted copy red the count guard, and a PRE-deny placement on an
  # agent-board-shaped block evaluates to not-allow (that file's shadowing
  # catch-all is exactly what AC4 calls out).
  python3 - "${permed[0]}" "$TMP/ls-stripped.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, "no frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
target = outer if isinstance(outer, dict) and "permissions" in outer else fm
rows = target.get("permissions") or []
before = len(rows)
rows[:] = [r for r in rows if not (r.get("action") == "shell" and r.get("resource") == "ls *")]
assert len(rows) == before - 1, "fixture: no 'ls *' allow row found to strip (the live loop reddens first — the row is mandatory since C01)"
target["permissions"] = rows
if outer is not target:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  v=$(python3 "$TMP/family.py" policy "$TMP/ls-stripped.md" 'ls -a' 2>/dev/null || true)
  [ "$v" != "allow" ] || fail "A16[C01]: NEGATIVE CONTROL FAILED — 'ls -a' still evaluates allow with the row stripped (matcher inert; the real guard would pass on drift)"
  python3 "$TMP/family.py" lsrow "$TMP/ls-stripped.md" >/dev/null 2>&1 \
    && fail "A16[C01]: NEGATIVE CONTROL FAILED — lsrow accepted the stripped fixture"
  python3 - "${permed[0]}" "$TMP/ls-dup.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
target = outer if isinstance(outer, dict) and "permissions" in outer else fm
rows = target.get("permissions") or []
ls = [r for r in rows if r.get("action") == "shell" and r.get("resource") == "ls *" and r.get("effect") == "allow"]
assert len(ls) == 1, "fixture: duplicate only a landed single ls row"
rows.append(dict(ls[0]))
target["permissions"] = rows
if outer is not target:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  python3 "$TMP/family.py" lsrow "$TMP/ls-dup.md" >/dev/null 2>&1 \
    && fail "A16[C01]: NEGATIVE CONTROL FAILED — lsrow accepted a duplicated ls row"
  python3 - .rulesync/subagents/agent-board.md "$TMP/ls-misplaced.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
target = outer if isinstance(outer, dict) and "permissions" in outer else fm
rows = target.get("permissions") or []
rows[:] = [r for r in rows if not (r.get("action") == "shell" and r.get("resource") == "ls *")]
deny_at = next(i for i, r in enumerate(rows)
               if r.get("action") == "shell" and r.get("resource") == "*" and r.get("effect") == "deny")
rows.insert(deny_at, {"action": "shell", "resource": "ls *", "effect": "allow"})
target["permissions"] = rows
if outer is not target:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  v=$(python3 "$TMP/family.py" policy "$TMP/ls-misplaced.md" 'ls -a' 2>/dev/null || true)
  [ "$v" != "allow" ] || fail "A16[C01]: NEGATIVE CONTROL FAILED — an ls allow placed BEFORE agent-board's shell-'*' deny still evaluates allow (the AC4 position test is decoration)"
  for f in "$PERM_SRC" "$PERM_GEN"; do
    for row in coord board-coord dev-local dev-pr agent-board; do
      python3 "$TMP/sectgrep.py" "$f" row "$row" 'ls *' \
        || fail "A16[C01 matrix]: $f '$row' row does not carry the ls * token — a permission-block change is only done when its matrix row moved too (permissions.md drift lesson)"
    done
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' 'ls *' \
      || fail "A16[C01 matrix]: $f Drift-incidents section has no ls-* entry for the 2026-10-29 ruling (12 sources, re-pinned suites)"
  done
  ok "A16[C01 AC1-AC5]: 22 permission-bearing sources + mirrors each carry exactly one shell 'ls *' allow, every one evaluates 'ls -a' => allow (agent-board placement proven by the misplaced-row control), strip/duplicate controls reject, the nine stage agents verified permissionless, permissions.md rows + drift entry moved"
fi

printf 'PASS: agent-perms contract checks (%d ok)\n' "$checks"
