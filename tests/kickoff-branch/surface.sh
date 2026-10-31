#!/usr/bin/env bash
# Kickoff-mints text & grant contract suite
# (2026/2026-10-bug-kickoff-mints-run-branch, C02).
#
# Pins the landing of "kickoff actually mints the run's branch":
#   m1  C01's behavior suite passes (plan Commands line 2; review runs one cmd)
#   m2  the grep-proof trio — 'kickoff-mint-branch' in all six kickoff/
#       role-coord/boards SKILL.md (source+generated), the exact resource
#       string 'bash scripts/kickoff-mint-branch.sh *' in all four coord files
#       (C02 AC4, plan Commands grep-proof)
#   m3  the contract text — honest worktree_create bullet + mint step + resume
#       clause (kickoff pair), step-0 mint + extended containment (role-coord
#       pair), citation-only boards line with no restated command (boards
#       pair, D12 posture), the three-allow matrix rows + drift entry
#       (permissions.md pair), and every cf-52 carry-set intact (in-work
#       contract strings, boards carry strings, withdrawn title strings absent
#       tree-wide)
#   m4  the frontmatter grant contract — the scoped shell allows
#       (arm-aware OR-form splice + literal-line twins, the atpos.py/splice.py
#       convention shipped in tests/coord-inwork/surface.sh and exercised by
#       tests/agent-perms/surface.sh A10; widened by
#       2026-10-bug-session-origin-no-line from SHELL3-only to the SHELL3|SHELL4
#       forms ladder — green at today's landed three-allow posture, admitting
#       the fourth session-origin grant the moment that C02 lands, while the
#       absolute four-allow presence duty lives in
#       tests/session-origin/surface.sh s4; negative controls prove the
#       mechanism rejects an unsanctioned row, a fabricated fifth row, and
#       off-anchor placement)
#   m5  the regeneration contract (generate --check + second-run no-op, the
#       PATH/npx skip-with-warning ladder — c7/t14/A6 precedent)
#   m6  the no-touch set vs $BASE — commands dirs, the gate SCRIPT and the
#       pipeline-models/gates pairs byte-unchanged (C02 AC6, i5/c17
#       dependency). AGENTS.md + .rulesync/rules carry the cf-76 D7
#       REGENERATION-EQUIV CARVE (validation_at_fault re-pin, same class as
#       the accepted S3 delta-aware arm): the kickoff-era blanket freeze
#       ("Q3/DECISIONS promise that AGENTS.md stays frozen") was retired by
#       the approved plan — C02 AC5 MANDATES editing .rulesync/rules/overview.md
#       and regenerating AGENTS.md, and C06/C07 regenerate it again. The
#       delta is admitted ONLY as a rulesync regeneration of the .rulesync/
#       sources (generate --check; a hand-edit or unregenerated source still
#       fails this arm — no blind path whitelist), fail-closed when the
#       generator is unresolvable (the freeze it replaced was unconditional)
#
# Red posture (post-landing, 2026-10-26/27): m1–m4 are GREEN — C01's script
# landed at 5a335aff2, C02's text + third grant landed at c6689202c, and m4
# now runs as the SHELL3|SHELL4 forms ladder widened by
# 2026-10-bug-session-origin-no-line (green at today's three-allow posture,
# accepting the fourth the moment that C02 lands; its designed-red carrier is
# tests/session-origin/surface.sh s4, not this file). m5 and m6 are HOLD
# guards: green at the test phase; m6's frozen paths turn red if any later
# chunk escapes scope, and the carved AGENTS.md/.rulesync/rules surfaces turn
# red on a hand-edit or a stale mirror via the regeneration-equivalence check. Both arms (BASE=HEAD and
# CHUNK_BASE=081b57889) keep passing until session-origin C02 lands, after
# which both arms (HEAD and the new landed posture) must go fully green again
# on one commit.
#
# cf-58 merge re-pin (2026-10-27): the standalone-agent merge lands the
# sanctioned git block + the agent-dev → agent-dev-local roster rename on the
# coord family. m4's mechanism re-pins accordingly: the arm comparisons run
# on git-block-stripped core projections with a whole-block tail check
# (splice3), the line twin admits the cf-72 B block as the only sanctioned
# continuation (atpos3 — sixty-eight effect-aware shared rows + the two-/
# seven-row push tail), the soundness controls build their
# no-allow base from the live skeleton (git rows projected, not enumerated),
# and the shape check keeps its git -C
# ban untouched (m4-shape). m4(b)'s diff-shape arm CANNOT express a merge
# delta (the merge adds the git block + rewrites prose): it is designed-red
# in the merge window under BASE=pre-merge-HEAD and green again at the merge
# commit (empty diff → arm-B atpos posture), provable pre-commit via
# CHUNK_BASE=<merge snapshot>.
# cf-72 B-block re-pin (2026-10-29, card #72): the coord family's fourteen-row
# reads list is replaced by the broad-grant-plus-floor block; splice3's
# whole-block equality and atpos3's literal walk carry the 68+2/-row sequence
# for the alias/-local files this suite tests, and synth's skeleton projection
# keeps the fabricated-row controls alive through those whole-sequence checks.
# m4(b)'s diff-shape arm follows the same merge-window discipline as cf-58's:
# designed-red under BASE=HEAD while the landing is uncommitted, arm-B green
# at the landing commit (pre-commit proof: CHUNK_BASE=$(git stash create)).
# The kickoff naming landing (2026-10-27, bug-coord-opencode-perms) inherits
# the same discipline: its execute/opencode_* rows are stripped from the core
# projections and whole-checked tail-style (like the git block), so the parsed
# arms go green in-window; m4(b)'s classifier stays designed-red until the
# landing commit flips the files to the empty-diff arm-B posture. The absolute
# naming duty lives in tests/agent-perms/surface.sh A12 (family.py naming).
#
# Sibling posture: the legacy suites keep their regression duty through this
# ticket by widening to the sanctioned-FORMS ladder (two-allow cf-52 form OR
# three-allow kickoff-mints form, now three|four-allow after session-origin):
# tests/coord-inwork/surface.sh i4,
# tests/agent-board-coord/gate.sh t17, tests/agent-board-coord/
# rulesync-surface.sh c2. The absolute "four allows exist NOW" presence duty
# lives in tests/session-origin/surface.sh s4, so the session-origin C01-phase
# regressions stay green at both operational arms while that C02 contract is
# still designed-red.
#
# Offline-deterministic except m5's generator gate (skip-with-warning when
# rulesync is unresolvable) and m1's own scratch-repo fixtures.
#
# board-tick-cleanup RE-PIN (2026-10-chore-board-tick-cleanup, 2026-10-29):
# m4's geometry admits C01's `ls *` allow (re-seated in-family 2026-10-30) and C03's scoped preload-
# probe allow (both stripped from the splice core like the date row, admitted
# at most once whole; atpos3 grew the WANT6/WANT7 rungs (probe, then ls).
# This suite keeps the zero-red sibling posture — the absolute presences live
# in agent-perms A16 and tests/board-preload-probe/surface.sh, so committed
# postures stay green at default BASE=HEAD (the arm-B twin) through both
# waves; the m4(b) diff-shape arm keeps the date-wave precedent — it only
# expresses its own historical geometry, so a landing window is designed-red
# there and green again at the landing commit. The 2026-10-30 merge round
# added the MERGE_HEAD rung to that arm: while a main merge is in flight the
# worktree delta is the RESOLUTION (cf-72's restructure is not an additions-
# only grant delta, and git stash create refuses over conflict stages, so the
# snapshot proof cannot run) — the rung instead pre-validates the landing
# commit's arm-B posture on the live resolved file via atpos3.
#
# Usage (harness convention from tests/coord-inwork/surface.sh):
#   bash tests/kickoff-branch/surface.sh           # m1..m6
#   bash tests/kickoff-branch/surface.sh m3 m4     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

# Historical arm-A reference (tests/agent-perms/surface.sh A10 discipline):
# the landing parent of the cf-52 content (coord files carry NO shell
# allows). Since the cf-58 merge re-pin (2026-10-27) the m4 soundness
# controls derive their no-allow base from the live skeleton (synth
# strip-shell) instead — cf-58's roster rename moved ARM_A off the live
# skeleton by one subagent line — so ARM_A is kept for the record only.
ARM_A=081b57889

SCRIPT_SUITE="tests/kickoff-branch/script.sh"
KICK_SRC=".rulesync/skills/pipeline-kickoff/SKILL.md"
KICK_GEN=".opencode/skills/pipeline-kickoff/SKILL.md"
RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
BOARD_SRC=".rulesync/skills/boards/SKILL.md"
BOARD_GEN=".opencode/skills/boards/SKILL.md"
COORD_SRC=".rulesync/subagents/agent-coord.md"
COORD_GEN=".opencode/agents/agent-coord.md"
BCOORD_SRC=".rulesync/subagents/agent-board-coord.md"
BCOORD_GEN=".opencode/agents/agent-board-coord.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"

MINT_RES='bash scripts/kickoff-mint-branch.sh *'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/kickoff-branch-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 6); do WANT["m$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^m[1-6]$ ]] || fail "unknown check id '$a' (expected m1..m6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -------------------------------------------------------------

cat >"$TMP/win.py" <<'PY'
# Co-location window (tests/coord-inwork/surface.sh win.py convention): the
# needles must read as one passage; --ci folds case for prose needles so the
# pins survive dev's register without pinning exact sentences.
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path).read()
if ci:
    text = text.lower()
    needles = [n.lower() for n in needles]
pts = []
for n in needles:
    start, found = 0, 0
    while True:
        i = text.find(n, start)
        if i < 0:
            break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'missing needle: {n}')
        sys.exit(1)
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
    print(f'no window of {span} chars covers all needles (min span {best})')
    sys.exit(1)
PY

cat >"$TMP/order1.py" <<'PY'
# First-occurrence order across the whole file (rulesync-surface.sh order.py
# convention without the section scoping): the mint step must sit in the
# worktree bullet, i.e. after worktree_create is introduced, not as a stray
# mention elsewhere in the skill.
import sys
path = sys.argv[1]
text = open(path).read().lower()
needles = sys.argv[2:]
pos = []
for n in needles:
    i = text.find(n.lower())
    if i < 0:
        print(f'needle "{n}" not in {path}'); sys.exit(1)
    pos.append(i)
if pos != sorted(pos):
    print(f'order violated: {list(zip(needles, pos))}'); sys.exit(1)
PY

cat >"$TMP/sectgrep.py" <<'PY'
# Row/section text pins (tests/agent-perms/surface.sh sectgrep.py convention):
# the permissions matrix rows are pinned by their label cell, the drift log by
# its section. Row regex uses [ \t] — Python re has no POSIX classes.
import re, sys
path, mode = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
text = open(path).read()
anchor, needles = rest[0], rest[1:]
if mode == "row":
    hay = "\n".join(l for l in text.splitlines()
                    if re.match(r"^\|[ \t]*" + re.escape(anchor) + r"[ \t]*\|", l))
elif mode == "section":
    m = re.search(r"(?ms)^#+[^\n]*" + re.escape(anchor) + r"[^\n]*\n.*", text)
    hay = m.group(0) if m else ""
else:
    print(f"unknown sectgrep mode '{mode}'"); sys.exit(2)
if not hay:
    print(f"{path}: no {mode} '{anchor}' content to search"); sys.exit(1)
for n in needles:
    if n not in hay:
        print(f"{path}: '{n}' missing from the {mode} '{anchor}' (red before C02 dev phase — the text row has not moved)")
        sys.exit(1)
PY

# m4 mechanism, SHELL3-only (no ladder — this suite owns the absolute presence
# duty; the legacy siblings own the forms ladder). Arm A normalizes the base
# first (strip any sanctioned rows, re-splice all three at the anchor) so a
# two-allow base + the +3 mint delta reads as the sanctioned posture — the
# C02-review geometry — while any fourth row still breaks equality in both
# arms.
cat >"$TMP/synth.py" <<'PY'
# Clone a coord file with a form mutation for the m4 controls. Rows are
# located by literal-line triples; the item indent is the resource line's
# indent minus the two-space key nesting, so both shapes (source nests under
# opencode:, generated at top level) survive. after-patch/after-origin are the
# modes that no-op when the appended allow is already present (the accept
# controls then use the real committed form); the negative-control modes
# append unconditionally so they stay meaningful after C02 lands.
import sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src).read().split("\n")
def find(resource):
    for i, l in enumerate(lines):
        if l.strip() == f"resource: {resource}":
            return i
    return -1
def block(item_ind, resource):
    return [f"{item_ind}- action: shell", f"{item_ind}  resource: {resource}", f"{item_ind}  effect: allow"]
MINT = "bash scripts/kickoff-mint-branch.sh *"
ORIGIN = "bash scripts/session-origin.sh*"
BAD = "git -C * checkout -b *"
# cf-72 re-pin (2026-10-29): the git block grew past any enumeration — the
# B block is sixty-eight shared rows + a two-/seven-row tail — so strip-shell
# projects on resource.startswith("git ") to build the no-allow skeleton the
# form3/form4 controls splice into. Pinning stays honest: the whole-sequence
# controls (splice3's projection equality, atpos3's literal walk) re-check
# every landed row against the declared block, so the skeleton only has to
# be git-free. form3/form4 splice the canonical forms after the opencode '*'
# allow anchor on ANY base, so those modes must not require the cf-52 rows
# up front. 2026-10-31 merge union: the scoped-read family is date, preload-
# probe, then the cf-88 diagnostic pairs (ls, ls *, pwd, pwd * — the ls row
# deduped, serving C01's grant duty AND the cf-88 pair) — every row joins the
# strip set so the skeleton stays truly no-allow in every era.
SHELL_ROWS = {"opencode api get /api/session*", "opencode api patch /api/session/*", MINT, ORIGIN, "date *",
              "bash scripts/board-preload-probe.sh *", "ls", "ls *", "pwd", "pwd *"}
def sanctioned(res):
    return res in SHELL_ROWS or res.startswith("git ")
i_p = find("opencode api patch /api/session/*")
if mode not in ("strip-shell", "form3", "form4"):
    assert i_p >= 0, "fixture source must carry the cf-52 two-allow posture"
item_ind = lines[i_p][: len(lines[i_p]) - len(lines[i_p].lstrip())][:-2] if i_p >= 0 else None
i_m = find(MINT)
i_o = find(ORIGIN)
if mode == "after-patch":
    out = lines if i_m >= 0 else (lines[: i_p + 2] + block(item_ind, MINT) + lines[i_p + 2:])
elif mode == "after-origin":
    assert i_m >= 0, "the origin allow rides after the landed mint allow"
    out = lines if i_o >= 0 else (lines[: i_m + 2] + block(item_ind, ORIGIN) + lines[i_m + 2:])
elif mode == "after-anchor":
    j = next(k for k, l in enumerate(lines) if l.strip() == "- action: opencode")
    out = lines[:j] + block(item_ind, MINT) + lines[j:]
elif mode == "bad-row":
    out = lines[: i_p + 2] + block(item_ind, BAD) + lines[i_p + 2:]
elif mode == "fifth-row":
    assert i_o >= 0, "fifth-row needs the origin allow present (run after-origin first)"
    out = lines[: i_o + 2] + block(item_ind, BAD) + lines[i_o + 2:]
elif mode == "strip-shell":
    out, k = [], 0
    while k < len(lines):
        if (lines[k].strip() == "- action: shell" and k + 2 < len(lines)
                and lines[k + 1].strip().startswith("resource: ")
                and sanctioned(lines[k + 1].strip()[len("resource: "):])
                and lines[k + 2].strip().startswith("effect: ")):
            k += 3
        else:
            out.append(lines[k]); k += 1
elif mode in ("form3", "form4"):
    j = next(k for k, l in enumerate(lines) if l.strip() == "- action: opencode")
    # items sit at the anchor's own indent (resource lines two deeper) — the
    # item_ind convention of the after-* modes above.
    ind = lines[j][: len(lines[j]) - len(lines[j].lstrip())]
    rows = ["opencode api get /api/session*", "opencode api patch /api/session/*", MINT]
    if mode == "form4":
        rows.append(ORIGIN)
    out = lines[: j + 3] + [x for r in rows for x in block(ind, r)] + lines[j + 3:]
else:
    print(f"unknown synth mode {mode}"); sys.exit(2)
open(dst, "w").write("\n".join(out))
PY

cat >"$TMP/splice3.py" <<'PY'
# The m4 OR-form over the sanctioned-FORMS ladder (splice.py convention from
# tests/coord-inwork/surface.sh, incl. the arm A / arm B vocabulary that
# tests/agent-perms/surface.sh A10 greps from the shipped siblings):
#   SHELL3 — the three scoped allows this suite minted as its absolute duty
#     (cf-52 GET/PATCH + the mint triple), landed;
#   SHELL4 — SHELL3 plus the fourth scoped session-origin resolver allow
#     (`bash scripts/session-origin.sh*`, no-space glob — NQ1), admitted the
#     moment 2026-10-bug-session-origin-no-line C02's delta appears. The
#     absolute FOUR-allow presence duty lives in
#     tests/session-origin/surface.sh s4, never here — m4 stays green through
#     that ticket's C01 at today's three-allow posture.
#   arm A — current == the base normalized to exactly the form's allows after
#     the `opencode '*' allow` rule: sanctioned rows are stripped from the
#     base first, so a no-allow base, the cf-52 two-allow base and the
#     landed three-allow base all reach the same sanctioned posture — the +3
#     origin-triple geometry of a session-origin C02 review run is arm A; any
#     unsanctioned row survives normalization and breaks the equality.
#   arm B (committed base) — current == base AND base is idempotent under the
#     form's strip/re-insert at the anchor.
# A base already carrying the origin allow admits SHELL4 only (a landed
# four-allow state never regresses to three); every other base admits SHELL3
# or SHELL4 but never SHELL2 — the ladder never weakens.
import re, sys, yaml
base_path, cur_path, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
GET = {"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"}
PATCH = {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"}
MINT = {"action": "shell", "resource": "bash scripts/kickoff-mint-branch.sh *", "effect": "allow"}
ORIGIN = {"action": "shell", "resource": "bash scripts/session-origin.sh*", "effect": "allow"}
# Date-grant RE-PIN (2026-10-27): the in-work mark embeds $(date +%s%3N) in
# the patch payload; the shell matcher checks the substitution's `date`
# subcommand against the agent's own list, so the family carries a `date *`
# allow. Same discipline as the git block and the naming rows: both arms
# strip it from the core projection (the shell-allow ladder geometry is
# unchanged) and a separate check admits it at most once, whole.
DATE = {"action": "shell", "resource": "date *", "effect": "allow"}
# cf-88 re-pin (2026-10-30) + 2026-10-31 merge union: the surface-check pairs
# (ls/pwd bare + spaced, `ls *` deduped across the waves) ride the block after
# the preload-probe row; stripped from the core projection like DATE so the
# SHELL4 splice geometry keeps its teeth, admitted at most once, whole, in
# order. The pairs also grew the READ surface (loop file + agent definitions,
# for diagnosing the same kickoff surfaces) — same strip/whole-admit
# discipline. Absolute presence duties: ls -> agent-perms A16, probe ->
# tests/board-preload-probe/surface.sh B2. A deny or duplicated copy of any
# of them still breaks both arms.
PROBE = {"action": "shell", "resource": "bash scripts/board-preload-probe.sh *", "effect": "allow"}
DIAG = [{"action": "shell", "resource": "ls", "effect": "allow"},
        {"action": "shell", "resource": "ls *", "effect": "allow"},
        {"action": "shell", "resource": "pwd", "effect": "allow"},
        {"action": "shell", "resource": "pwd *", "effect": "allow"}]
READDIAG = [{"action": "read", "resource": ".agents/loops/**", "effect": "allow"},
            {"action": "read", "resource": ".opencode/agents/**", "effect": "allow"}]
SHELL3 = [GET, PATCH, MINT]
SHELL4 = [GET, PATCH, MINT, ORIGIN]
# cf-58 MERGE RE-PIN (2026-10-27): the merged coord family additionally
# carries the sanctioned git block after the SHELL4 block (pinned absolutely
# across all twelve family files by the cfpins contract in
# tests/coord-inwork/surface.sh i4 and tests/agent-board-coord/gate.sh t17).
# Both arms compare core projections (git block stripped); a separate check
# admits the block only whole and in order. The ladder itself is unchanged.
# cf-72 B block (this suite's splice runs on the ALIAS/-local files only:
# sixty-eight shared rows + the two-row push tail; the -pr tail's 75-row
# sequence is pinned absolutely by coord-inwork i4, gate t17 and A12).
def is_git(p):
    return p.get("action") == "shell" and str(p.get("resource", "")).startswith("git ")
GITBLOCK = [
    {"action": "shell", "resource": "git *", "effect": "allow"},
    {"action": "shell", "resource": "git checkout main*", "effect": "deny"},
    {"action": "shell", "resource": "git * checkout main*", "effect": "deny"},
    {"action": "shell", "resource": "git checkout * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * checkout * main*", "effect": "deny"},
    {"action": "shell", "resource": "git switch main*", "effect": "deny"},
    {"action": "shell", "resource": "git * switch main*", "effect": "deny"},
    {"action": "shell", "resource": "git switch * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * switch * main*", "effect": "deny"},
    {"action": "shell", "resource": "git update-ref*", "effect": "deny"},
    {"action": "shell", "resource": "git * update-ref*", "effect": "deny"},
    {"action": "shell", "resource": "git symbolic-ref*", "effect": "deny"},
    {"action": "shell", "resource": "git * symbolic-ref*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -f main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -f main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch --force main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch --force main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -d main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -d * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -d main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -d * main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -D main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -D * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -D main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -D * main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -m main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -m * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -m main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -m * main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -M main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -M * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -M main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -M * main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -c main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -c main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -c * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -c * main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -C main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -C main*", "effect": "deny"},
    {"action": "shell", "resource": "git branch -C * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * branch -C * main*", "effect": "deny"},
    {"action": "shell", "resource": "git worktree add * main*", "effect": "deny"},
    {"action": "shell", "resource": "git * worktree add * main*", "effect": "deny"},
    {"action": "shell", "resource": "git pull*", "effect": "deny"},
    {"action": "shell", "resource": "git * pull*", "effect": "deny"},
    {"action": "shell", "resource": "git merge *", "effect": "deny"},
    {"action": "shell", "resource": "git * merge *", "effect": "deny"},
    {"action": "shell", "resource": "git config alias*", "effect": "deny"},
    {"action": "shell", "resource": "git * config alias*", "effect": "deny"},
    {"action": "shell", "resource": "git * --force*", "effect": "deny"},
    {"action": "shell", "resource": "git * -f *", "effect": "deny"},
    {"action": "shell", "resource": "git * -P *", "effect": "deny"},
    {"action": "shell", "resource": "git merge main*", "effect": "allow"},
    {"action": "shell", "resource": "git * merge main*", "effect": "allow"},
    {"action": "shell", "resource": "git merge --abort", "effect": "allow"},
    {"action": "shell", "resource": "git * merge --abort", "effect": "allow"},
    {"action": "shell", "resource": "git merge --continue", "effect": "allow"},
    {"action": "shell", "resource": "git * merge --continue", "effect": "allow"},
    {"action": "shell", "resource": "git checkout -b * main*", "effect": "allow"},
    {"action": "shell", "resource": "git * checkout -b * main*", "effect": "allow"},
    {"action": "shell", "resource": "git checkout -B * main*", "effect": "allow"},
    {"action": "shell", "resource": "git * checkout -B * main*", "effect": "allow"},
    {"action": "shell", "resource": "git switch -c * main*", "effect": "allow"},
    {"action": "shell", "resource": "git * switch -c * main*", "effect": "allow"},
    {"action": "shell", "resource": "git switch -C * main*", "effect": "allow"},
    {"action": "shell", "resource": "git * switch -C * main*", "effect": "allow"},
    {"action": "shell", "resource": "git worktree add -b * main*", "effect": "allow"},
    {"action": "shell", "resource": "git * worktree add -b * main*", "effect": "allow"},
    {"action": "shell", "resource": "git push*", "effect": "deny"},
    {"action": "shell", "resource": "git *push*", "effect": "deny"},
]
# Naming RE-PIN (2026-10-27, bug-coord-opencode-perms): the coord family now
# additionally carries the kickoff naming surface — `execute` (the Code Mode
# transport for tools.opencode.*) + four opencode_* per-tool allows, MCP-style
# <server>_<tool>. Same discipline as the git block directly above: both arms
# strip these rows from the core projection (the shell-allow ladder geometry
# is unchanged) and a separate check admits the four per-tool rows only whole
# and in order. The absolute naming duty lives in
# tests/agent-perms/surface.sh A12, never here.
EXEC = {"action": "execute", "resource": "*", "effect": "allow"}
NAMING = [
    {"action": "opencode_worktree_create", "resource": "*", "effect": "allow"},
    {"action": "opencode_worktree_list", "resource": "*", "effect": "allow"},
    {"action": "opencode_session_move", "resource": "*", "effect": "allow"},
    {"action": "opencode_session_rename", "resource": "*", "effect": "allow"},
]

def perms(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []

def splice(seq, form):
    anchor = [i for i, p in enumerate(seq)
              if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
    if len(anchor) != 1:
        return None, len(anchor)
    i = anchor[0]
    return seq[:i + 1] + form + seq[i + 1:], i

b, c = perms(base_path), perms(cur_path)
if b[0] != {"action": "*", "resource": "*", "effect": "deny"}:
    print("deny-baseline first rule changed at base — the suite's premise broke"); sys.exit(1)
b_core = [p for p in b if not is_git(p) and p not in NAMING and p != EXEC and p != DATE and p != PROBE and p not in DIAG and p not in READDIAG]
c_core = [p for p in c if not is_git(p) and p not in NAMING and p != EXEC and p != DATE and p != PROBE and p not in DIAG and p not in READDIAG]
if ORIGIN in b:
    forms = [SHELL4]
else:
    # m4's floor is the landed three-allow posture — SHELL2 never admitted.
    forms = [SHELL4, SHELL3]
norm = [p for p in b_core if p not in SHELL4]
hit = None
for form in forms:
    want, i = splice(norm, form)
    if want is None:
        print(f"base must carry exactly one opencode '*' allow, found {i}"); sys.exit(1)
    if c_core == want:
        hit = "arm A"
        break
if hit is None:
    if not any(p.get("resource") == MINT["resource"] for p in c_core):
        print("the third scoped mint allow is MISSING (the landed three-allow posture is this suite's floor — a tree below it broke some sibling's contract)"); sys.exit(1)
    if c_core == b_core:  # arm B candidate — committed base
        rebuilt = False
        for form in forms:
            stripped = list(b_core)
            if not all(s in stripped for s in form):
                continue
            for s in form:
                stripped.remove(s)
            again, _ = splice(stripped, form)
            if again is not None and b_core == again:
                rebuilt = True
                break
        if not rebuilt:
            print("arm B: current == base but the base is not a sanctioned allow form (SHELL3 or SHELL4) at the pinned splice position — the contract never landed or drifted off-anchor"); sys.exit(1)
    else:
        want, _ = splice(norm, SHELL4)
        extra = [p for p in c_core if p not in want]
        missing = [p for p in want if p not in c_core]
        print(f"frontmatter delta is not a sanctioned shell-allow form (three- or four-allow) in either arm: extra={extra} missing={missing}")
        sys.exit(1)
gb = [p for p in c if is_git(p)]
if gb and gb != GITBLOCK:
    print("git-block rows are present but are not exactly the cf-72 B block for an alias/-local file — sixty-eight shared rows + the two-row push tail — in order — unsanctioned git surface"); sys.exit(1)
nb = [p for p in c if p in NAMING]
if nb and nb != NAMING:
    print("kickoff naming rows are present but are not exactly the sanctioned four in order — unsanctioned naming surface"); sys.exit(1)
dt = [p for p in c if p == DATE]
if dt and dt != [DATE]:
    print("the date allow is present more than once or with a different effect — unsanctioned date surface"); sys.exit(1)
dg = [p for p in c if p in DIAG]
if dg and dg != DIAG:
    print("the diagnostic rows are present but not exactly the sanctioned ls/pwd pairs (ls * deduped) in order — unsanctioned diagnostic surface"); sys.exit(1)
rd = [p for p in c if p in READDIAG]
if rd and rd != READDIAG:
    print("the cf-88 read allows are present but not exactly the sanctioned pair in order — unsanctioned read surface"); sys.exit(1)
prt = [p for p in c if p.get("action") == "shell" and str(p.get("resource", "")).startswith("bash scripts/board-preload-probe.sh")]
if prt and prt != [PROBE]:
    print("the preload-probe allow is present more than once, off-spelling, or with a non-allow effect — unsanctioned probe surface (the OQ-N1 grant is exactly one scoped row)"); sys.exit(1)
shells = [p.get("resource") for p in c_core if p.get("action") == "shell"]
if shells not in ([s["resource"] for s in SHELL3], [s["resource"] for s in SHELL4]):
    print(f"shell resources are {shells}, want exactly the three or four scoped allows in order (the other sanctioned shell surfaces are the cf-72 git block, the date allow, the in-family preload-probe row and the cf-88 diagnostic pair — each checked whole above; presences in agent-perms A16 / tests/board-preload-probe/surface.sh)"); sys.exit(1)
if c[0] != b[0]:
    print("deny-baseline line drifted"); sys.exit(1)
if need_dev_boards and not any(p.get("action") == "dev-boards*" and p.get("resource") == "*"
                               and p.get("effect") == "allow" for p in c):
    print("dev-boards* allow missing from a board-coord file"); sys.exit(1)
PY

cat >"$TMP/atpos3.py" <<'PY'
# Arm-B line twin (atpos.py convention, forms-aware). The sanctioned literal
# family is seven rows ending ls * (2026-10-30 merge re-seat: ls joined the
# scoped-read family after the preload-probe row; the trailing-ls rung after
# the git block is OBSOLETE — cf-72 made the push tail the absolute-last
# shell rows). Rungs stay OPTIONAL longest-first — the absolute presence
# duties are tests/session-origin/surface.sh s4 (four-allow), agent-perms
# A16 (ls) and tests/board-preload-probe/surface.sh B2 (probe); the m4(b)
# classifier geometries name the +3 deltas. Block matching skips source-tree
# comment lines; row bytes, count and order stay pinned like the
# continuation walk. The only sanctioned continuation is the cf-72 B block;
# any other shell row is unsanctioned.
import re, sys
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
lines = [l.rstrip(" \t\r") for l in m.group(1).split("\n") if l.strip()]
ANCHOR = re.compile(r"^(\s*)- action: opencode$")
WANT3 = [('resource: opencode api get /api/session*', 'effect: allow'),
         ('resource: opencode api patch /api/session/*', 'effect: allow'),
         ('resource: bash scripts/kickoff-mint-branch.sh *', 'effect: allow')]
WANT4 = WANT3 + [('resource: bash scripts/session-origin.sh*', 'effect: allow')]
WANT5 = WANT4 + [('resource: date *', 'effect: allow')]
# 2026-10-31 merge union: the canonical literal is WANT10 = SHELL5 +
# [preload-probe, ls, ls *, pwd, pwd *] (ten rows / thirty lines); the
# merge-1 WANT6/WANT7 and cf-88's WANT9 are broken prefixes of the union and
# are dropped — only the pre-wave SHELL3..5 rungs survive beside WANT10.
WANT10 = WANT5 + [('resource: bash scripts/board-preload-probe.sh *', 'effect: allow'),
                  ('resource: ls', 'effect: allow'), ('resource: ls *', 'effect: allow'),
                  ('resource: pwd', 'effect: allow'), ('resource: pwd *', 'effect: allow')]
hits = []
for i, l in enumerate(lines):
    am = ANCHOR.match(l)
    if am and lines[i + 1:i + 3] == [f"{am.group(1)}  resource: '*'", f"{am.group(1)}  effect: allow"]:
        hits.append((i, am.group(1)))
if len(hits) != 1:
    print(f"want exactly one '- action: opencode' + resource '*' + effect allow rule, found {len(hits)}"); sys.exit(1)
ind = hits[0][1]
at = hits[0][0] + 3
def noncomment(pos):
    while pos < len(lines) and lines[pos].lstrip().startswith("#"):
        pos += 1
    return pos
matched_end = 0
for want in (WANT10, WANT5, WANT4, WANT3):  # longest first: shorter blocks are prefixes
    pos = at
    ok = True
    for rule in want:
        pos = noncomment(pos)
        if lines[pos:pos + 3] != [f"{ind}- action: shell", f"{ind}  {rule[0]}", f"{ind}  {rule[1]}"]:
            ok = False
            break
        pos += 3
    if ok:
        matched_end = pos
        break
if not matched_end:
    print("none of the sanctioned literal family blocks (SHELL3 nine lines, SHELL4 twelve, SHELL5 fifteen, "
          "SHELL10 thirty — comments skipped, the union family's broken intermediate rungs never match) "
          f"follows the opencode '*' allow at the pinned position (want under indent '{ind}', got {lines[at:at + 30]})"); sys.exit(1)
# cf-72 B-block re-pin: after the sanctioned family the only permitted
# continuation is comment lines plus the sanctioned git block — sixty-eight
# effect-aware shared rows, then the variant push tail (two rows on
# alias/-local files, seven on -pr files) ending the shell surface; any other
# shell row is an unsanctioned grant.
def T(r, e):
    return (f"{ind}- action: shell", f"{ind}  resource: {r}", f"{ind}  effect: {e}")
COMMON = [T(r, e) for r, e in (
    ("git *", "allow"),
    ("git checkout main*", "deny"),
    ("git * checkout main*", "deny"),
    ("git checkout * main*", "deny"),
    ("git * checkout * main*", "deny"),
    ("git switch main*", "deny"),
    ("git * switch main*", "deny"),
    ("git switch * main*", "deny"),
    ("git * switch * main*", "deny"),
    ("git update-ref*", "deny"),
    ("git * update-ref*", "deny"),
    ("git symbolic-ref*", "deny"),
    ("git * symbolic-ref*", "deny"),
    ("git branch -f main*", "deny"),
    ("git * branch -f main*", "deny"),
    ("git branch --force main*", "deny"),
    ("git * branch --force main*", "deny"),
    ("git branch -d main*", "deny"),
    ("git branch -d * main*", "deny"),
    ("git * branch -d main*", "deny"),
    ("git * branch -d * main*", "deny"),
    ("git branch -D main*", "deny"),
    ("git branch -D * main*", "deny"),
    ("git * branch -D main*", "deny"),
    ("git * branch -D * main*", "deny"),
    ("git branch -m main*", "deny"),
    ("git branch -m * main*", "deny"),
    ("git * branch -m main*", "deny"),
    ("git * branch -m * main*", "deny"),
    ("git branch -M main*", "deny"),
    ("git branch -M * main*", "deny"),
    ("git * branch -M main*", "deny"),
    ("git * branch -M * main*", "deny"),
    ("git branch -c main*", "deny"),
    ("git * branch -c main*", "deny"),
    ("git branch -c * main*", "deny"),
    ("git * branch -c * main*", "deny"),
    ("git branch -C main*", "deny"),
    ("git * branch -C main*", "deny"),
    ("git branch -C * main*", "deny"),
    ("git * branch -C * main*", "deny"),
    ("git worktree add * main*", "deny"),
    ("git * worktree add * main*", "deny"),
    ("git pull*", "deny"),
    ("git * pull*", "deny"),
    ("git merge *", "deny"),
    ("git * merge *", "deny"),
    ("git config alias*", "deny"),
    ("git * config alias*", "deny"),
    ("git * --force*", "deny"),
    ("git * -f *", "deny"),
    ("git * -P *", "deny"),
    ("git merge main*", "allow"),
    ("git * merge main*", "allow"),
    ("git merge --abort", "allow"),
    ("git * merge --abort", "allow"),
    ("git merge --continue", "allow"),
    ("git * merge --continue", "allow"),
    ("git checkout -b * main*", "allow"),
    ("git * checkout -b * main*", "allow"),
    ("git checkout -B * main*", "allow"),
    ("git * checkout -B * main*", "allow"),
    ("git switch -c * main*", "allow"),
    ("git * switch -c * main*", "allow"),
    ("git switch -C * main*", "allow"),
    ("git * switch -C * main*", "allow"),
    ("git worktree add -b * main*", "allow"),
    ("git * worktree add -b * main*", "allow"),
)]
TAILS = [[T("git push*", "deny"), T("git *push*", "deny")],
         [T("git push*main*", "deny"), T("git * push *main*", "deny"), T("git * push", "deny"),
          T("git push -f*", "deny"), T("git push -P*", "deny"), T("git * push -f*", "deny"),
          T("git * push -P*", "deny")]]
k = matched_end
gi = saw = 0
chosen = None
while k < len(lines):
    if lines[k].lstrip().startswith("#"):
        k += 1
        continue
    if lines[k].strip() == "- action: shell":
        saw = 1
        if gi < len(COMMON):
            if lines[k:k + 3] != list(COMMON[gi]):
                print(f"a shell row continues the block after the sanctioned form and is not the next sanctioned git-block row (want {COMMON[gi]}, got {lines[k:k + 3]}) — unsanctioned shell grant"); sys.exit(1)
            gi += 1
            k += 3
            continue
        if chosen is not None:
            print("a shell row continues after the complete sanctioned git block — unsanctioned shell grant"); sys.exit(1)
        chosen = next((t for t in TAILS if lines[k:k + 3 * len(t)] == [ln for tr in t for ln in tr]), None)
        if chosen is None:
            print(f"the git block's tail is neither the two-row alias/-local push tail nor the seven-row -pr push tail (got {lines[k:k + 21]}) — unsanctioned shell grant"); sys.exit(1)
        k += 3 * len(chosen)
        continue
    break
if saw and (gi != len(COMMON) or chosen is None):
    print(f"the git block continues the shell surface but is truncated or reordered (matched {gi} of {len(COMMON)} shared rows, tail {'found' if chosen else 'missing'})"); sys.exit(1)
PY

cat >"$TMP/m4-shape.py" <<'PY'
# Pair component of m4(c): parsed perms of source == generated (order too —
# last-match-wins makes order load-bearing), no shell grant touches git, the
# bash grants are exactly the landed mint pair or the landed mint + landed
# session-origin pair (no third bash grant), question allow kept, and the
# variant's MCP posture (none on plain coord, single dev-boards* after deny on
# board-coord).
import re, sys, yaml
src, gen, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
ps, pg = perms(src), perms(gen)
errs = []
if ps != pg:
    errs.append(f"parsed permission lists differ between {src} and {gen} (order included) — regenerate, never hand-edit the mirror")
for p in ps:
    if p.get("action") == "shell" and "git -C" in str(p.get("resource", "")):
        errs.append("a raw git -C shell grant exists — the plan's rejected mechanism (main-checkout flip hazard)")
bashish = [p for p in ps if p.get("action") == "shell" and str(p.get("resource", "")).startswith("bash ")]
if [p.get("resource") for p in bashish] not in (["bash scripts/kickoff-mint-branch.sh *"],
                                                 ["bash scripts/kickoff-mint-branch.sh *", "bash scripts/session-origin.sh*"],
                                                 ["bash scripts/kickoff-mint-branch.sh *", "bash scripts/session-origin.sh*",
                                                  "bash scripts/board-preload-probe.sh *"]):
    errs.append(f"bash shell grants are {[p.get('resource') for p in bashish]}, want the landed mint pair, the landed mint + session-origin pair, or those plus the OQ-N1 preload-probe row (the m4-paired alias files — the absolute probe duty is tests/board-preload-probe/surface.sh)")
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in ps):
    errs.append("question allow lost (repo hard rule)")
if need_dev_boards:
    db = [i for i, p in enumerate(ps) if p.get("action") == "dev-boards*"]
    deny_at = next((i for i, p in enumerate(ps) if p.get("action") == "*" and p.get("effect") == "deny"), None)
    if len(db) != 1 or not (deny_at is not None and db[0] > deny_at):
        errs.append("the single narrow dev-boards* allow after the deny-all is gone")
    if any(p.get("action") == "dev*" for p in ps):
        errs.append("broad dev* allow appeared (D21)")
else:
    if any(p.get("action") in ("dev*", "dev_boards*", "dev-boards*") for p in ps):
        errs.append("a board MCP allow appeared on the plain coord")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY

# --- m1: the C01 behavior suite passes (plan Commands; review runs one cmd) ----
if want m1; then
  [ -f "$SCRIPT_SUITE" ] || fail "m1: $SCRIPT_SUITE is missing (the test-phase artifact itself — harness fault, not C01's)"
  if timeout 600 bash "$SCRIPT_SUITE" >"$TMP/m1.log" 2>&1; then
    ok "m1: tests/kickoff-branch/script.sh passes (C01 behavior contract green)"
  else
    tail -n 3 "$TMP/m1.log" >&2
    fail "m1: tests/kickoff-branch/script.sh does not pass (red before C01 dev phase — see the first red line above; it names the missing script)"
  fi
fi

# --- m2: the grep-proof trio across both trees (C02 AC4) ------------------------
if want m2; then
  miss_text=(); miss_res=()
  for f in "$KICK_SRC" "$KICK_GEN" "$RC_SRC" "$RC_GEN" "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "m2: $f is missing (harness fault)"
    grep -qF 'kickoff-mint-branch' "$f" || miss_text+=("$f")
  done
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    [ -f "$f" ] || fail "m2: $f is missing (harness fault)"
    grep -qF "$MINT_RES" "$f" || miss_res+=("$f")
  done
  [ ${#miss_text[@]} -eq 0 ] || fail "m2: 'kickoff-mint-branch' absent from: ${miss_text[*]} (red before C02 dev phase — the contract text has not landed in source or mirror)"
  [ ${#miss_res[@]} -eq 0 ] || fail "m2: '$MINT_RES' absent from: ${miss_res[*]} (red before C02 dev phase — the scoped grant has not landed in a coord file or its mirror)"
  ok "m2: mint string in all six skill files, resource string in all four coord files (source + generated)"
fi

# --- m3: contract text + citation posture + carry-sets (C02 tasks 1-3, 5) ------
if want m3; then
  for f in "$KICK_SRC" "$KICK_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 900 'worktree_create' 'detached' 'scripts/kickoff-mint-branch.sh' \
      || fail "m3: $f does not make the worktree bullet honest (worktree_create + detached + the mint command in one passage — red before C02 dev phase)"
    python3 "$TMP/order1.py" "$f" 'worktree_create' 'scripts/kickoff-mint-branch.sh' \
      || fail "m3: $f mentions the mint before worktree_create is introduced — the mint step must live in the worktree bullet"
    python3 "$TMP/win.py" --ci "$f" 700 'resume' 'idempoten' \
      || fail "m3: $f lacks the Q6 resume clause (on resume, the same idempotent mint) in one passage — red before C02 dev phase"
    for s in 'metadata.openchamber.work' 'openedBy' 'doneAt' 'suggestDoneAt' 'done' 'skip'; do
      grep -qF "$s" "$f" || fail "m3: $f lost the cf-52 in-work carry string '$s' (i1 windows must hold through the C02 edit)"
    done
    # i1's read-merge-write needle is matched case-insensitively (the bullet
    # opens with capital R); mirror that, not a stricter grep.
    grep -qiF 'read-merge-write' "$f" \
      || fail "m3: $f lost the cf-52 read-merge-write mandate (i1 window needle)"
  done
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 1500 'mint' 'worktree' 'resume' \
      || fail "m3: $f step 0 does not name the mint alongside the worktree naming and the resume case — red before C02 dev phase"
    grep -qF 'scripts/kickoff-mint-branch.sh' "$f" \
      || fail "m3: $f never names the scoped mint command string — red before C02 dev phase"
    python3 "$TMP/win.py" --ci "$f" 700 'kickoff-mint-branch.sh' 'never' 'own' \
      || fail "m3: $f does not extend the containment sentence to the mint grant (own branch, own worktree, never anything else) — red before C02 dev phase"
    python3 "$TMP/win.py" --ci "$f" 1200 'session_rename' 'in-work' 'resume' \
      || fail "m3: $f broke the i2 step-0 window (rename + in-work + resume must still read as one passage)"
  done
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    grep -qF 'kickoff-mint-branch.sh' "$f" \
      || fail "m3: $f never cites the mint step in the slug surface list — red before C02 dev phase"
    python3 "$TMP/win.py" --ci "$f" 500 'kickoff-mint-branch.sh' 'pipeline-kickoff' \
      || fail "m3: $f does not pair the mint citation with pipeline-kickoff as the mechanism holder in one passage — red before C02 dev phase"
    if grep -qF 'bash scripts/kickoff-mint-branch.sh' "$f"; then
      fail "m3: $f restates the mint COMMAND — boards cites, never restates mechanics (C02 task: D12 posture)"
    fi
    for s in 'session_rename' 'cf-<card' 'Session origin:' 'VSCODE_PROXY_URI' '?session='; do
      grep -qF "$s" "$f" || fail "m3: $f lost the boards carry-set string '$s' (c12/i3 must hold through the added line)"
    done
    if grep -qE 'metadata\.openchamber|openchamber\.work' "$f"; then
      fail "m3: $f leaks the work-state key path (i3 single-source rule must survive C02)"
    fi
    if grep -qF 'openchamber--dev-thehackmeister-coder' "$f"; then
      fail "m3: $f re-introduces the proven-dead host literal"
    fi
  done
  for f in "$PERM_SRC" "$PERM_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row coord 'kickoff-mint-branch.sh' 'opencode api patch' \
      || fail "m3: $f coord shell cell does not list the three scoped allows — red before C02 dev phase (Q4: the matrix must track the permission-block change)"
    # The board-coord row may either name the mint grant or use the matrix's
    # established "same as coord" reference idiom (its edit/subagent cells
    # already do) — but the reference must state the CURRENT allow count: the
    # pre-C02 row says "none" there, so a reference form is accepted;
    # session-origin C02 legitimately moves the count three→four, so both
    # reference counts are admitted (naming the mint grant remains accepted).
    row=$(grep -E '^\|[[:space:]]*board-coord[[:space:]]*\|' "$f" || true)
    [ -n "$row" ] || fail "m3: $f has no board-coord row (c5/c6 duty broken by the matrix edit)"
    case "$row" in
      *'kickoff-mint-branch.sh'*|*'same three scoped shell allows'*|*'same four scoped shell allows'*|*'same scoped-read family as coord'*) : ;;
      *) fail "m3: $f board-coord shell cell lists neither the mint grant nor a current-count scoped-allows/family reference to the coord cell (the settled 2026-10-30 form names the family idiom) — red before C02 dev phase" ;;
    esac
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' 'kickoff-mint-branch' \
      || fail "m3: $f has no drift-log entry for the mint grant — red before C02 dev phase"
  done
  neg=$(grep -rn -e 'in-work:' -e 'done:' .rulesync/skills .opencode/skills 2>/dev/null || true)
  [ -z "$neg" ] || fail "m3: withdrawn title-convention string(s) under the skill trees: $neg"
  ok "m3: honest kickoff bullet + Q6 resume clause, role-coord step-0 mint + containment, boards citation-only, permissions rows + drift entry, every carry-set intact, no withdrawn title strings"
fi

# --- m4: the coord-pair scoped shell allows (C02 task 4) ---------------------
if want m4; then
  # (a) mechanism soundness — cf-58 MERGE RE-PIN (2026-10-27): the fixtures
  # stay live-file based, but the no-allow base is now the live SKELETON
  # (synth strip-shell: the SHELL4 allows + the sanctioned git block removed)
  # instead of the historical ARM_A commit — cf-58's roster rename (agent-dev
  # → agent-dev-local, its DECISIONS Q2) moved ARM_A's skeleton off the live
  # skeleton by exactly one subagent line, and its git block added a second
  # sanctioned shell surface the ladder never knew. The committed posture is
  # exercised as arm-B idempotence at the live file itself. Teeth unchanged:
  # the accept controls prove the SHELL3 and SHELL4 forms satisfy the
  # mechanism, and the reject controls still refuse a fabricated row, a fifth
  # row, and off-anchor placement.
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-skel.md" strip-shell
  python3 "$TMP/synth.py" "$TMP/a-skel.md" "$TMP/a-f3.md" form3
  python3 "$TMP/synth.py" "$TMP/a-skel.md" "$TMP/a-f4.md" form4
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-t4.md" after-origin
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-bad.md" bad-row
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-off.md" after-anchor
  python3 "$TMP/synth.py" "$TMP/a-t4.md" "$TMP/a-fifth.md" fifth-row
  python3 "$TMP/splice3.py" "$TMP/a-skel.md" "$TMP/a-f3.md" none >/dev/null \
    || fail "m4: CONTROL FAILED — splice3 rejects the canonical three-allow form at the no-allow skeleton base (the landed posture would read as drift)"
  python3 "$TMP/splice3.py" "$TMP/a-skel.md" "$TMP/a-f4.md" none >/dev/null \
    || fail "m4: CONTROL FAILED — splice3 rejects the canonical four-allow form at the no-allow skeleton base (session-origin C02's grant would be unsatisfiable)"
  python3 "$TMP/splice3.py" "$TMP/a-t4.md" "$TMP/a-t4.md" none >/dev/null \
    || fail "m4: CONTROL FAILED — splice3 rejects the committed posture at itself (arm-B idempotence: the landed SHELL4 + sanctioned git block must satisfy the mechanism)"
  python3 "$TMP/atpos3.py" "$TMP/a-t4.md" >/dev/null \
    || fail "m4: CONTROL FAILED — atpos3 rejects the committed posture's twenty-seven-line SHELL9 block + sanctioned git-block continuation (the landed-line arm-B posture)"
  if python3 "$TMP/atpos3.py" "$TMP/a-fifth.md" >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — atpos3 accepted a fabricated FIFTH row continuing the block (the sanctioned literal geometry: SHELL block + cf-72 B block only)"
  fi
  if python3 "$TMP/splice3.py" "$TMP/a-skel.md" "$TMP/a-fifth.md" none >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — splice3 accepted a fifth shell row (any non-sanctioned row must break both arms)"
  fi
  if python3 "$TMP/splice3.py" "$TMP/a-skel.md" "$TMP/a-bad.md" none >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — splice3 accepted a fabricated (raw git -C) shell row (any non-sanctioned row must break both arms)"
  fi
  if python3 "$TMP/splice3.py" "$TMP/a-skel.md" "$TMP/a-off.md" none >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — splice3 accepted the mint allow placed off the anchor"
  fi
  if python3 "$TMP/atpos3.py" "$TMP/a-bad.md" >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — atpos3 accepted the fabricated bad row"
  fi
  # the current two-allow posture rejected at the C02 arm (the designed-red
  # made explicit as a control, independent of the real-file outcome):
  git show "$BASE:$COORD_SRC" >"$TMP/a-cur-committed.md" 2>/dev/null
  if ! grep -qF "$MINT_RES" "$TMP/a-cur-committed.md"; then
    if python3 "$TMP/splice3.py" "$TMP/a-skel.md" "$TMP/a-cur-committed.md" none >/dev/null 2>&1; then
      fail "m4: CONTROL FAILED — splice3 accepted the two-allow committed state at arm A (this suite must reject it: it is the C02 contract)"
    fi
  fi
  # (b) the real files: OR-form splice vs $BASE + arm-aware line twin.
  n=0
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    git show "$BASE:$f" >"$TMP/m4-base-$n.md" 2>/dev/null || fail "m4: $f not readable at $BASE"
    python3 "$TMP/splice3.py" "$TMP/m4-base-$n.md" "$f" "$adb" \
      || fail "m4: $f satisfies neither arm A ($BASE perms + a sanctioned three- or four-allow form spliced after the opencode allow) nor arm B (committed base already carrying a sanctioned form at that position) (base: $BASE)"
    if git diff --quiet "$BASE" -- "$f"; then
      python3 "$TMP/atpos3.py" "$f" \
        || fail "m4: $f has an empty diff vs $BASE (arm B posture) but does not carry a sanctioned literal family block (SHELL3..SHELL5 historical or SHELL10 union) at the pinned position"
    elif git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      # 2026-10-30 MERGE-WINDOW RUNG: the worktree delta vs $BASE is the merge
      # RESOLUTION — cf-72's block restructure (+194/-18-class) is not an
      # additions-only grant delta and no historical geometry expresses it; the
      # documented snapshot proof (CHUNK_BASE=$(git stash create)) is refused
      # while conflict stages sit in the index and this round may not git add.
      # The rung proves the stronger thing directly: the live file must carry
      # the exact posture the merge commit will run through arm B — the
      # literal SHELL family block at the pinned position and the whole cf-72
      # continuation with the push tail absolute-last. A mis-resolved file
      # (old 13-row list, trailing-ls after the tail, reordered floor) reddens
      # here; non-merge windows stay on the geometry ladder.
      python3 "$TMP/atpos3.py" "$f" \
        || fail "m4: $f is mid-merge (MERGE_HEAD present) and the resolution does not pre-validate the landing commit's arm-B posture — want the literal sanctioned family block + whole cf-72 continuation at the pinned position before the merge commit"
    else
      bc=$(git show "$BASE:$f" | grep -c '^[[:space:]]*- action: shell' || true)
      ns=$(git diff --numstat "$BASE" -- "$f" | head -n 1 || true)
      add=$(printf '%s' "${ns:-0	0}" | cut -f1)
      del=$(printf '%s' "${ns:-0	0}" | cut -f2)
      case "$bc-$add" in
        0-9) sed_start=1; sed_end=9 ;;
        0-12) sed_start=1; sed_end=12 ;;
        2-3) sed_start=7; sed_end=9 ;;
        3-3) sed_start=10; sed_end=12 ;;
        # board-tick-cleanup geometries (merge-1 eras): +3 ls triple onto the
        # 19-row posture, +3 preload-probe triple onto the 20-row posture.
        # cf-88 geometries (their base: five-allow family, no probe row):
        # +23/+18 surface-check delta. Historical entries stay listed for
        # rebase-window runs; they cannot collide. Comment-bearing deltas
        # beyond a listed case keep the date-wave posture — the MERGE_HEAD
        # rung above pre-validates this merge's resolution directly.
        19-3) sed_start=13; sed_end=15 ;;
        20-3) sed_start=16; sed_end=18 ;;
        75-23) cf88=full ;;
        75-18) cf88=nocomment ;;
        *) fail "m4: $f diff vs a $bc-allow base is +$add/-$del, want +3 (the mint/session-origin/ls/probe triples on the named historical postures), +9 or +12 (full three-/four-allow form on a no-allow base), +23/+18 (the cf-88 surface-check delta on the landed five-allow posture — 18 grant rows, sources additionally carry the 5-line why-comment), additions only, or a pre-validated arm-B posture under MERGE_HEAD (the merge-window rung above) (base: $BASE)" ;;
      esac
      [ "$del" = "0" ] || fail "m4: $f diff removes lines (-$del) — the delta must be additions only"
      git diff -U0 "$BASE" -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' | sed 's/^[[:space:]]*//' \
        >"$TMP/m4-add-$n.txt"
      if [ "${cf88:-}" = "full" ] || [ "${cf88:-}" = "nocomment" ]; then
        printf '%s\n' '- action: read' 'resource: .agents/loops/**' 'effect: allow' \
                      '- action: read' 'resource: .opencode/agents/**' 'effect: allow' \
                      '- action: shell' 'resource: ls' 'effect: allow' \
                      '- action: shell' 'resource: ls *' 'effect: allow' \
                      '- action: shell' 'resource: pwd' 'effect: allow' \
                      '- action: shell' 'resource: pwd *' 'effect: allow' >"$TMP/m4-want-$n.txt"
        if [ "${cf88:-}" = "full" ]; then
          printf '%s\n' '# Surface checks (cf-88 postmortem 2026-10-30): verifying its own kickoff' \
                        '# surfaces (worktree/branch present, session location) is coordination, not' \
                        '# investigation — denied ls/pwd probes once masqueraded as a broken env and' \
                        '# a healthy run was abandoned. Command pairs: `ls *`/`pwd *` miss the bare' \
                        '# forms; `ls*`/`pwd*` would shadow lsof/pwdx-style tools.' >>"$TMP/m4-want-$n.txt"
        fi
      else
      printf '%s\n' '- action: shell' 'resource: opencode api get /api/session*' 'effect: allow' \
                    '- action: shell' 'resource: opencode api patch /api/session/*' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/kickoff-mint-branch.sh *' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/session-origin.sh*' 'effect: allow' \
                    '- action: shell' 'resource: ls *' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/board-preload-probe.sh *' 'effect: allow' \
        | sed -n "${sed_start},${sed_end}p" >"$TMP/m4-want-$n.txt"
      fi
      cmp -s "$TMP/m4-add-$n.txt" "$TMP/m4-want-$n.txt" \
        || fail "m4: $f added lines are not the sanctioned literals (see $TMP/m4-add-$n.txt vs $TMP/m4-want-$n.txt)"
    fi
  done
  # (c) shapes + negatives, parsed, both trees, per pair.
  for pair in "$COORD_SRC|$COORD_GEN|none" "$BCOORD_SRC|$BCOORD_GEN|dev-boards"; do
    IFS='|' read -r s g adb <<<"$pair"
    python3 "$TMP/m4-shape.py" "$s" "$g" "$adb" \
      || fail "m4: permission shape contract broken for the $s/$g pair"
  done
  ok "m4: coord files carry a sanctioned shell-allow form (three-allow landed posture or the four-allow form the moment session-origin C02's delta appears — the absolute four-allow duty lives in tests/session-origin/surface.sh s4); OR-form + arm-aware line twins, controls reject a fabricated row, a fifth row and off-anchor placement; deny-baseline, question, subagent/edit allows and the dev*/git-grant negatives hold in both trees; the naming landing keeps this geometry (parsed arms green in-window via the core-strip, m4(b) designed-red until the landing commit — or pre-validated through the MERGE_HEAD rung mid-merge; the absolute naming duty is A12 in tests/agent-perms/surface.sh)"
fi

# --- m5: the regeneration contract (C02 AC5; ladder skip-with-warning) ---------
if want m5; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "m5: rulesync not resolvable here (PATH or npx cache) — generate --check + no-op gate skipped with warning (c7/t14/A6 precedent)"
    ok "m5[regen-hold]: generator gate skipped with warning (ladder found no rulesync)"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "m5: rulesync generate --check is not clean — committed generated surfaces are stale against the sources (HOLD guard: red if C02 edits sources without mirrors)"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "m5: rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "m5: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "m5: the second rulesync generate is not a no-op (sources and generated have drifted)"
    ok "m5[regen-hold]: generate --check clean and the second generate is a no-op (via $RS)"
  fi
fi

# --- m6: no-touch set vs $BASE + the cf-76 D7 regeneration carve ----------------
# Frozen members keep the original diff-vs-$BASE walk; AGENTS.md and
# .rulesync/rules moved to regeneration-equivalence (the blanket freeze
# contradicted the approved plan's MANDATED overview.md edit + AGENTS.md
# regeneration — C02 AC5; C06/C07 regenerate again, all covered by the same
# carve). The equivalence is the m5/c7/A6 ladder's own `generate --check`:
# a hand-edited AGENTS.md no longer matches the generator output, and an
# unregenerated rules edit fails the same way — so an UNMATCHED delta still
# goes red here while a genuine regeneration stays green. Fail-closed when
# rulesync cannot be resolved: a carve that silently degrades to
# anything-goes would be weaker than the freeze it replaces.
if want m6; then
  NOTOUCH=(.rulesync/commands .opencode/commands
           scripts/agent-board-coord-gate.sh
           .rulesync/skills/pipeline-models .opencode/skills/pipeline-models
           .rulesync/skills/pipeline-gates .opencode/skills/pipeline-gates)
  # 2026-10-30 merge-window rung (same discipline as session-origin s6): while
  # a main merge is in flight, cf-85's commands and cf-83's pipeline-models
  # legitimately move these paths vs $BASE (branch HEAD) — the freeze duty is
  # that THIS TICKET never touches them, so the in-window reference is
  # MERGE_HEAD (measured clean: every no-touch path equals main; a ticket-side
  # drift or a resolution away from main reddens here). At the merge commit
  # the original $BASE reference governs again.
  notb="$BASE"
  if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then notb=$(git rev-parse MERGE_HEAD); fi
  moved=$( { git diff --name-only "$notb" -- "${NOTOUCH[@]}" 2>/dev/null || true;
             git ls-files --others --exclude-standard -- "${NOTOUCH[@]}"; } | sort -u || true )
  [ -z "$moved" ] || { printf '%s\n' "$moved" >&2; fail "m6: a no-touch path moved vs $notb — commands dirs/the gate script/pipeline-models/pipeline-gates stay untouched (C02 AC6, i5/c17 dependency)"; }
  RS6=""
  if command -v rulesync >/dev/null 2>&1; then
    RS6="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS6="npx --no-install rulesync"
  fi
  [ -n "$RS6" ] \
    || fail "m6: AGENTS.md/.rulesync/rules may only change as a rulesync regeneration, but rulesync is not resolvable here (PATH or npx cache) — the carve cannot be verified, and the arm stays fail-closed (unlike m5's warning-skip, which guards a different duty)"
  timeout 180 $RS6 generate --check >"$TMP/m6-check.log" 2>&1 \
    || { tail -n 15 "$TMP/m6-check.log" >&2; fail "m6: the AGENTS.md/.rulesync/rules delta is NOT regeneration-explained — generate --check is not clean (hand-edit of a generated surface, or a rules edit with no mirror — cf-76 D7 carve)"; }
  ok "m6[hold]: commands dirs, the gate script and the pipeline-models/gates pairs byte-unchanged vs $notb (merge-window reference when MERGE_HEAD is live); AGENTS.md + .rulesync/rules carry the cf-76 regeneration carve and generate --check proves every delta is the current sources' output (via $RS6)"
fi

printf 'PASS: kickoff-mints contract checks (%d ok)\n' "$checks"
