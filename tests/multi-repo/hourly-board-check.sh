#!/usr/bin/env bash
# C02 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the hourly
# gate's BOARD CHECK counts only Executing cards THIS repo could pick up
# (C01's eligibility test), the session gate keeps deliberate cross-project
# counting with a documented posture note, and the gate SCRIPT stays
# logic-unchanged (comment-only diff). Command text + comments only.
#
# Contract source: chunks/C02.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC2] t3[AC3+AC4].
#
# Red before C02 lands: t1 (the pre-change BOARD CHECK block has no Repo:/
# filter/get_card-per-card procedure). Green-at-base by design: t3's manual-
# command negative (no BOARD CHECK block was ever on the manual path) and
# t2's --help legend — both are regression gates.
#
# The comment-only proof uses the branch fork point (git merge-base HEAD
# main) as base — dev commits land on the branch, so a plain `git diff HEAD`
# would show nothing. GATE_DIFF_BASE re-points it if main legitimately moved
# the script.
#
# Usage:
#   bash tests/multi-repo/hourly-board-check.sh          # t1..t3
#   bash tests/multi-repo/hourly-board-check.sh t2       # subset
# Env: GATE_DIFF_BASE, RUNSYNC_BIN.
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # FRICTION seed: rulesync/helm discovery

cd "$(git rev-parse --show-toplevel)"

HOURLY_GEN=.opencode/commands/pipeline-boards-hourly.md
HOURLY_SRC=.rulesync/commands/pipeline-boards-hourly.md
GATE_SCRIPT=scripts/agent-board-coord-gate.sh
MANUAL_GEN=.opencode/commands/pipeline-boards.md
MANUAL_PR_GEN=.opencode/commands/pipeline-boards-pr.md

DIFF_BASE="${GATE_DIFF_BASE:-$(git merge-base HEAD main)}"

find_rulesync() {
  if [ -n "${RUNSYNC_BIN:-}" ] && [ -x "${RUNSYNC_BIN}" ]; then printf '%s' "$RUNSYNC_BIN"; return 0; fi
  if command -v rulesync >/dev/null 2>&1; then command -v rulesync; return 0; fi
  local cand
  cand=$(ls -1 "$HOME"/.nvm/versions/node/*/bin/rulesync 2>/dev/null | sort -V | tail -n 1 || true)
  [ -n "$cand" ] && { printf '%s' "$cand"; return 0; }
  return 1
}

checks=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-3]$ ]] || fail "unknown test id '$a' (expected t1..t3)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: filtered-count procedure in the generated command (AC1) --------------
if want t1; then
  [ -f "$HOURLY_GEN" ] || fail "t1: $HOURLY_GEN missing"
  if python3 - "$HOURLY_GEN" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t1 {msg}', file=sys.stderr)
    sys.exit(1)

m = re.search(r'BOARD CHECK.*?(?=^Notes:)', text, re.M | re.S)
if not m:
    bad('no BOARD CHECK block found in the hourly command')
block = m.group(0)

required = [
    (r'get_card', 'the filtered count needs the single-card read per Executing candidate (by-list projection strips labels — boards skill rule)'),
    (r'Repo:', 'the block must apply C01\'s Repo: eligibility test (cite the boards skill as the single authority, not a restated table)'),
    (r'boards skill|eligib', 'the block must reference the boards-skill eligibility rule rather than duplicate it (cite-the-single-authority posture)'),
    (r'filter', 'the raw card count must be replaced by a repo-filtered count'),
    (r'EMPTY|no filtered-in|zero filtered-in|empty', 'the EMPTY verdict (no card passes the filter) must be stated'),
    (r'≥1', 'the >=1 filtered-in card -> stop branch must remain'),
    (r'max 5', 'the card-titles max-5 truncation must remain'),
    (r'fail-closed', 'the fail-closed branch (any call failure -> skip) must remain'),
]
for pat, why in required:
    if not re.search(pat, block):
        bad(f'BOARD CHECK block lacks {pat!r} — {why}')
print('ok: t1 — BOARD CHECK block: per-candidate get_card + Repo: eligibility (cited, not restated), EMPTY iff zero filtered-in, >=1-stop, max-5 titles, fail-closed kept (C02 AC1)')
PY
  then checks=$((checks + 1)); else fail 't1: the filtered-count contract is not satisfied (reason printed above)'; fi
fi

# --- t2: gate script is comment-only-changed; --help legend intact (AC2) ------
if want t2; then
  diff_out=$(git diff "$DIFF_BASE" -- "$GATE_SCRIPT" || true)
  if [ -n "$diff_out" ]; then
    # Anything starting with '-' other than the diff header is a deletion or
    # a rewritten line — the D11 history is append-only per the chunk Notes.
    if printf '%s\n' "$diff_out" | grep -E '^-' | grep -vE '^--- ' | grep -q .; then
      fail "t2: the gate diff vs $DIFF_BASE deletes/rewrites lines — only comment APPENDS are allowed (D11 block is load-bearing history)"
    fi
    if printf '%s\n' "$diff_out" | grep -E '^\+[^+]' | grep -vE '^\+\s*(#|$)' | grep .; then
      fail "t2: the gate diff adds a non-comment line — the script's executable logic must not change (AC2)"
    fi
    ok "t2: gate-script diff vs $DIFF_BASE touches comment lines only (no logic, no verdict, no flag changes)"
  else
    ok "t2: gate script unchanged vs $DIFF_BASE (comment-only diff, vacuously green)"
  fi

  help_out=$(bash "$GATE_SCRIPT" --help 2>&1) || fail "t2: bash $GATE_SCRIPT --help exited non-zero"
  for marker in 'GATE: RUN' 'GATE: LIVE' 'GATE: SKIP'; do
    printf '%s\n' "$help_out" | grep -qF "$marker" || fail "t2: --help lost the '$marker' verdict legend"
  done
  ok "t2: --help exits 0 printing the GATE: RUN / GATE: LIVE / GATE: SKIP legend"

  python3 - "$GATE_SCRIPT" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t2 {msg}', file=sys.stderr)
    sys.exit(1)

# D11 sentences the note must APPEND to, never rewrite (chunk Notes).
for anchor in ('must stay visible', 'No directory or project'):
    if anchor not in text:
        bad(f'the pre-existing D11 rationale sentence around {anchor!r} was rewritten — append, never rewrite')

def near(anchor, tokens, window=900):
    for m in re.finditer(anchor, text, re.I):
        seg = text[max(0, m.start() - window):m.end() + window]
        if all(re.search(t, seg, re.I) for t in tokens):
            return True
    return False

if not near(r'single-writer|conservative', [r'serializ', r'project'], 1200):
    bad('the multi-repo posture sentence is missing: LIVE across projects is the conservative single-writer answer (why the gate counts all projects)')
print('ok: t2 — D11 rationale intact and the multi-repo single-writer posture note landed in the header comment (C02 AC2)')
PY
  checks=$((checks + 1))
fi

# --- t3: generate --check, Notes posture bullet, manual path untouched -------
if want t3; then
  rulesync_bin=$(find_rulesync) || fail "t3: rulesync not found (PATH / ~/.nvm / RUNSYNC_BIN) — FRICTION: no silent skips"
  "$rulesync_bin" generate --check >/tmp/opencode/cf93-hourly-board-check.check.log 2>&1 \
    || { tail -n 20 /tmp/opencode/cf93-hourly-board-check.check.log >&2; fail "t3: rulesync generate --check is red — the generated hourly command is out of sync with $HOURLY_SRC (AC3; the second-generate no-op is dev's own check per plan Commands)"; }
  ok "t3: rulesync generate --check exits 0 in this repo ($rulesync_bin)"

  if python3 - "$HOURLY_GEN" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)

m = re.search(r'^Notes:.*', text, re.M | re.S)
if not m:
    bad('no Notes section in the generated command')
notes = m.group(0)

def near(anchor, tokens, window=700):
    for mm in re.finditer(anchor, notes, re.I):
        seg = notes[max(0, mm.start() - window):mm.end() + window]
        if all(re.search(t, seg, re.I) for t in tokens):
            return True
    return False

if not near(r'serializ', [r'all projects|ALL projects|projects', r'D11|OQ-A3|human decision|not a silent fix'], 900):
    bad('the Notes section lacks the OQ-A3 posture bullet: cross-project counting serializes hourly launches across repos by design; per-repo gate scoping is a human decision')
print('ok: t3 — Notes carry the deliberate cross-project-counting posture bullet (C02 AC4)')
PY
  then checks=$((checks + 1)); else fail 't3: the Notes posture leg is not satisfied (reason printed above)'; fi

  # Regression: the manual path never had a gate and must not gain the block
  # (C02 Tasks: "the manual /pipeline-boards command needs NO edit").
  for f in "$MANUAL_GEN" "$MANUAL_PR_GEN"; do
    [ -f "$f" ] || fail "t3: $f missing — the manual launch surface"
    if grep -q 'BOARD CHECK' "$f"; then
      fail "t3: $f grew a BOARD CHECK block — the guard lives only on the scheduled path (AC3 no-other-surface)"
    fi
  done
  ok "t3: neither manual /pipeline-boards command carries a BOARD CHECK block (manual path stays ungated by design)"
fi

printf 'PASS: cf-93 C02 hourly-board-check contract (%d ok)\n' "$checks"
