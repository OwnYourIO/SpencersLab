#!/usr/bin/env bash
# agent-board-coord debounce-gate contract suite (2026/2026-10-cf-50-feat-
# prevent-multiple-agent-board-coords, C01 + C02, + C03 round-2 re-pins).
#
# Pins D17's three-state session-operand contract for
# scripts/agent-board-coord-gate.sh (t1..t10), the /pipeline-boards-hourly
# command surface plus the manual-path byte-freeze (t11..t17), and the
# round-2 Session-origin command/skill contract (t18/t19). Written before
# the implementation exists — red-before-green by design:
#   C01 not landed: t1 fails file-not-found; t2..t9 fail as invocation
#     errors (exit 127); t10 fails-or-skips.
# Current red posture (2026-10-27, cf-58 test phase + cf-52 merge): the
#   DESIGNED REDS of cf-58 in this file were t17 and t20 — both landed with
#   C03 (six-family files + widened liveness filter). t1..t16, t18, t19 are
#   HOLD: green now and green at the C03/C05/C06 landings (t14/t15/t16
#   re-pinned from byte-freeze arms to presence/allow-set guards, see the
#   cf-58 header note; the historical operational bases of the earlier
#   tickets — 081b57889, f11bfcb85, 916044893, 72500166a — stay documented
#   above and need not pass every check between chunks;
#   "red-between-chunks-by-design" per DECISIONS). MERGE NOTE: the cf-52
#   session-origin/kickoff-mints shell-allow ladder lives ON TOP of the cf-58
#   contract — t17's cfpins admits the two sanctioned script allows
#   (`bash scripts/kickoff-mint-branch.sh *`, `bash scripts/session-origin.sh*`)
#   between the API pair and the git block; the absolute presence duties live
#   in tests/kickoff-branch/surface.sh m4 and tests/session-origin/surface.sh
#   s4, and the atpos twin pins the twelve-line SHELL4 literal block.
#   C02 not landed: t11/t13/t15/t16 fail on missing strings/files;
#     t12/t14 are invariance guards — green at plan time and must HOLD.
#   C03 not landed (round-2 base 72500166a): t11 red on the STRENGTHENED
#     windows (LIVE allow-list lacks list_swimlanes/list_lists; the
#     --threshold 0 note lacks the host clarifier); t18 red (no Session
#     origin block anywhere); t19 red first on the dead host literal still
#     shipped by the boards skill; rulesync-surface.sh c12 red on its
#     absence pin. t12/t13/t14/t15/t16/t17 HOLD — green now, and t12/t15/
#     t17 turn red the moment C03 touches a frozen byte.
#
# AC trace: t1[C01 AC2+AC5] t2[AC1 a] t3[AC1 b] t4[AC1 c] t5[AC1 d]
# t6[AC1 e] t7[AC1 f] t8[AC1 g] t9[AC1 h+i] t10[C01 AC4] t11[C02 AC1 +
# C03 AC3 strengthened] t12[C02 AC2, C03 AC4 carve] t13[AC3] t14[AC4 +
# C03 AC5 scope; cf-52 widenings] t15[AC5 + C03 AC4 round-aware HOLD] t16[AC6]
# t17[AC2/D13; cf-52 RE-PIN = base + two scoped shell allows;
# kickoff-mints RE-PIN = sanctioned forms ladder SHELL2|SHELL3;
# session-origin C02 RE-PIN = SHELL2|SHELL3|SHELL4 (fourth scoped
# `bash scripts/session-origin.sh*` origin grant; absolute four-allow presence
# duty lives in tests/session-origin/surface.sh s4, never here)]
# t18[C03 AC1 origin block] t19[C03 AC2 skill dynamic contract].
#
# AC7 (regression) is not re-implemented here: run
# tests/agent-board-coord/rulesync-surface.sh and agents-md.sh; their scope
# allow-lists carry this ticket's in-surface paths, and agents-md.sh c8's
# AGENTS.md section allow-set includes "Where things live" — this ticket's
# scripts/ bullet lands there, so the regression holds at any CHUNK_BASE.
#
# cf-52 posture (this branch shares the suite): t17 was RE-PINNED from D13's
# byte-freeze to the coord pair's delta contract (the two scoped `opencode
# api` session allows, D10); t14's allow-set carried cf-52's in-scope paths.
# cf-58 RE-PIN (2026-10-cf-58-feat-standalone-agent-merge, C03): the coord
# family is SIX agents now (2 alias + 4 variants) and their sanctioned
# permission content grows the git block, so the exact-two-allow delta is
# retired — t17 re-pins to the ABSOLUTE family contract (API containment at
# the pinned position + git-only additional shell rows + variant rosters,
# cfpins.py, the coord-inwork i4 twin convention); the historical arm A /
# arm B refs (081b57889, f11bfcb85, 916044893) stay documented above. t14's
# allow-set admits the cf-58 surfaces (the whole subagent/command/skill tree
# is this ticket's workshop; infra dirs stay fenced). t15/t16 shed their
# byte-freeze arms because C03/C05 legitimately edit the agent bodies and
# the rules bullets — the surviving contract is the hourly-pointer presence
# and the scripts/gate facts. t20 (new) pins the widened liveness filter.
# t11/t12/t13/t18/t19 HOLD unchanged.
#
# tests-edit-perms posture (2026-10-26, D4/D9/D10/D11 fold-in) — the current
# discipline for this suite and its siblings:
#   - Operational bases: every run must pass at default BASE=HEAD (arm B — the
#     committed-delta posture on the integrated line, main >= 124fc2ae8) AND at
#     CHUNK_BASE=081b57889 (arm A — the landing parent of the cf-52 content
#     20ed5dfaf). Historical bases need not pass: f11bfcb85 (unrelated renovate
#     chore), 916044893 as a chunk base (its child 081b57889 is the release-bot
#     Chart.yaml commit the scope guards do not admit, D11), the cf-52 branch
#     bases (b0c975bf6-era) and the pre-landing round-2 base 72500166a.
#   - t17 accepts either arm via the c2 OR-form (splice-idempotence), its line
#     twins are arm-aware, and its shape blocks stay unconditional; the
#     kickoff-mints C02 re-pin widens the accepted delta to the SHELL2|SHELL3
#     forms ladder with base-gated admission (a base carrying the mint allow
#     admits only SHELL3) and keys the line twins to the base's allow count
#     (+6/+9 from a no-allow base, +3 mint triple from the two-allow base).
#   - t14 admits scripts/* so C01's scripts/kickoff-mint-branch.sh lands
#     in-scope; the gate script's own freeze lives in surface.sh i5.
#   - t12 carves exactly the four agents-sync references files
#     (permissions.md + pipeline-overview.md, source and generated) out of the
#     byte freeze and guards them source<->generated instead; the rest of the
#     freeze and the untracked guard stand.
#   - t14 admits this ticket's in-scope paths (agent-test/agent-dev pairs, the
#     carved references, the pipeline-role-test pair, tests/**) and the three
#     follow-up ticket folders 124fc2ae8 introduced.
#
# The suite is offline-deterministic: the agent-test session that wrote it
# made no dev-boards/MCP call, and no check except t10 touches a live server
# (t10 is skip-guarded, intake-ticket t14 precedent). Live positive controls
# belong to Review notes, never here.
#
# Fixture clock: NOW_MS is deliberately far in the past (2023-11-14). A script
# that ignores GATE_NOW_MS and uses the wall clock ages every fixture session
# by the full multi-year gap, so the LIVE rows go red for the right reason
# instead of passing by accident (fixture sessions are ~minutes apart).
#
# Fixture scoping for dev: every fixture session carries
# location.directory = this repo's toplevel and a constant projectID. A script
# that scopes by location.directory (the fuser convention, C01 "Notes for
# dev") is therefore a no-op on fixtures; one that scopes by a projectID it
# looked up live would break AC1(c)/(d)/(h) — the agent-name filter is the
# documented minimum, so fixture mode must not require live project facts.
#
# Usage (harness conventions from tests/agent-board-coord/rulesync-surface.sh):
#   bash tests/agent-board-coord/gate.sh                # t1..t20
#   bash tests/agent-board-coord/gate.sh t4 t9          # subset
#   CHUNK_BASE=<pre-chunk commit> bash tests/agent-board-coord/gate.sh  # for the BASE-relative guards
# Chunk bases: C02-era guards ran 0ed96ed99/a42dc2896/87617353a; round-2
# (C03) per-chunk base is 72500166a — t12/t15/t17 freeze against that base's
# shipped round-1 content, t14 scopes the C03 delta, t18/t19 + strengthened
# t11 go red until C03 lands. t15 auto-detects which round the base belongs
# to (pointer absent in base → the one-sentence append rule; pointer present
# → the byte-frozen HOLD) so every historical base stays meaningful.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

GATE="scripts/agent-board-coord-gate.sh"
NOW_MS=1700000000000
FXDIR="$(pwd)"

FEATURE=".agents/plans/2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords"
# cf-52 shares the branch and re-opens the coord-pair permission surface; its
# in-scope paths join the t14 allow-set (same union-of-tickets posture as
# rulesync-surface.sh c8) and t17 is re-pinned from D13's byte-freeze to its
# sanctioned delta — now the SHELL2|SHELL3 forms ladder (kickoff-mints C02).
# kickoff-mints also admits scripts/* (C01's scripts/kickoff-mint-branch.sh —
# the plan's collision map predated this suite's scope guard being live); the
# gate SCRIPT itself ($GATE) stays byte-frozen via surface.sh i5's freeze set,
# which lists it by exact path — the t14 widening is path-admission, not
# invariance.
FEATURE3=".agents/plans/2026/2026-10-cf-52-feat-coord-session-inwork"
# cf-58 joins the union-of-tickets scope posture (same convention as the two
# widenings above): its plan folder, the whole subagent/command/skill tree it
# rewrites, the generated mirrors, the gate script itself, and the hand-
# managed .opencode/opencode.jsonc catalog (C06). Infra dirs stay fenced.
FEATURE5=".agents/plans/2026/2026-10-cf-58-feat-standalone-agent-merge"
CF_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
        .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
        .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
CF_GEN=(.opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md
        .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md
        .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md)
RULES_SRC=".rulesync/rules/overview.md"
AGENT_SRC=".rulesync/subagents/agent-board-coord.md"
AGENT_GEN=".opencode/agents/agent-board-coord.md"
COORD_SRC=".rulesync/subagents/agent-coord.md"
COORD_GEN=".opencode/agents/agent-coord.md"
KICK_SRC_DIR=".rulesync/skills/pipeline-kickoff"
KICK_GEN_DIR=".opencode/skills/pipeline-kickoff"
RC_SRC_DIR=".rulesync/skills/pipeline-role-coord"
RC_GEN_DIR=".opencode/skills/pipeline-role-coord"
CMD_BASE_SRC=".rulesync/commands/pipeline-boards.md"
CMD_BASE_GEN=".opencode/commands/pipeline-boards.md"
CMD_SRC=".rulesync/commands/pipeline-boards-hourly.md"
CMD_GEN=".opencode/commands/pipeline-boards-hourly.md"
BOARDS_SRC=".rulesync/skills/boards"
BOARDS_GEN=".opencode/skills/boards"
AS_SRC=".rulesync/skills/agents-sync"
AS_GEN=".opencode/skills/agents-sync"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/gate-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 20); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[0-9]|20)$ ]] || fail "unknown check id '$a' (expected t1..t20)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -----------------------------------------------------------

# Fixture session builder: the field list the C01 probes pin (id, parentID,
# agent, title, time.created, time.updated, location.directory, projectID).
# Ages are seconds before NOW_MS; parentID is omitted for top-level sessions
# exactly as the live envelope omits it.
sess() { # id agent title created-ago-s updated-ago-s [parentID]
  local id="$1" agent="$2" title="$3" cago="$4" uago="$5" parent="${6:-}"
  local s="{\"id\":\"$id\",\"title\":\"$title\",\"agent\":\"$agent\""
  [ -z "$parent" ] || s="$s,\"parentID\":\"$parent\""
  s="$s,\"projectID\":\"proj_fixture\",\"location\":{\"directory\":\"$FXDIR\"}"
  s="$s,\"time\":{\"created\":$((NOW_MS - cago * 1000)),\"updated\":$((NOW_MS - uago * 1000))}}"
  printf '%s' "$s"
}

envelope() { # live envelope {"data":[...]} over pre-built sess() fragments
  local out='{"data":[' first=1 j
  for j in "$@"; do
    [ "$first" -eq 1 ] || out="$out,"
    out="$out$j"; first=0
  done
  printf '%s]}' "$out"
}

RC=0
run_gate() { # verdict-mode invocation; stdout -> $TMP/g.out, stderr -> $TMP/g.err
  RC=0
  GATE_NOW_MS="$NOW_MS" timeout 30 bash "$GATE" "$@" >"$TMP/g.out" 2>"$TMP/g.err" || RC=$?
}

fl() { head -n 1 "$TMP/g.out"; }

# Every AC1 row asserts BOTH the first-line marker and the exit code.
expect_verdict() { # desc want-rc first-line-extended-regex
  local desc="$1" want="$2" re="$3" line
  line=$(fl)
  if [ "$RC" -ne "$want" ]; then
    fail "$desc: exit $RC (want $want); first line: '$line'; stderr: $(head -c 160 "$TMP/g.err" | tr '\n' ' ')$([ -f "$GATE" ] || echo " | $GATE absent — expected red before C01")"
  fi
  [[ "$line" =~ $re ]] \
    || fail "$desc: first line '$line' does not match /$re/ (want exit $want)"
}

# The contract writes <age> in seconds; floor-vs-round of the ms math is not
# pinned, so ±1s proves the fixed-clock arithmetic without over-pinning.
expect_age() { # desc expected-seconds
  local desc="$1" want="$2" line a
  line=$(fl)
  a=$(printf '%s' "$line" | grep -oE '[0-9]+s' | head -n 1 || true)
  [ -n "$a" ] || fail "$desc: first line '$line' carries no <age>s value"
  a=${a%s}
  [ "$a" -ge $((want - 1)) ] && [ "$a" -le $((want + 1)) ] \
    || fail "$desc: age ${a}s not within 1s of the fixed-clock ${want}s"
}

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): needles must read as
# one passage, so a reworded decision rule still passes but a scattered or
# reordered one cannot. --ci folds case for prose needles; code identifiers
# and markers are matched case-exact by callers that omit it.
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

# t17's arm-B line twin (tests-edit-perms T10/D10). With an empty base diff the
# additions-based cmp of the old posture is vacuous-by-impossibility, so assert
# the positive instead: the six literal allow lines follow the `opencode '*'
# allow` rule byte-exactly, anchor-relative (the item line carries the anchor's
# own indent, the key lines one level deeper — the source nests the block under
# `opencode:`, the generated mirror does not, so absolute bytes cannot be
# shared between the two trees and indentation must not stay free to drift).
# The delta check still rejects any extra rule before or after the pinned six.
cat >"$TMP/atpos.py" <<'PY'
import re, sys
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
lines = [l.rstrip(" \t\r") for l in m.group(1).split("\n") if l.strip()]
ANCHOR = re.compile(r"^(\s*)- action: opencode$")
WANT2 = [('resource: opencode api get /api/session*', 'effect: allow'),
         ('resource: opencode api patch /api/session/*', 'effect: allow')]
WANT3 = WANT2 + [('resource: bash scripts/kickoff-mint-branch.sh *', 'effect: allow')]
WANT4 = WANT3 + [('resource: bash scripts/session-origin.sh*', 'effect: allow')]
# 2026-10-27 date-grant re-pin: SHELL5 = SHELL4 + the `date *` triple (the
# in-work mark's $(date +%s%3N) epoch subcommand grant).
WANT5 = WANT4 + [('resource: date *', 'effect: allow')]
hits = []
for i, l in enumerate(lines):
    am = ANCHOR.match(l)
    if am and lines[i + 1:i + 3] == [f"{am.group(1)}  resource: '*'", f"{am.group(1)}  effect: allow"]:
        hits.append((i, am.group(1)))
if len(hits) != 1:
    print(f"want exactly one '- action: opencode' + resource '*' + effect allow rule, found {len(hits)}"); sys.exit(1)
ind = hits[0][1]
at = hits[0][0] + 3
matched = 0
for want in (WANT5, WANT4, WANT3, WANT2):  # longest first: shorter blocks are prefixes
    want_lines = [x for rule in want for x in
                  (f"{ind}- action: shell", f"{ind}  {rule[0]}", f"{ind}  {rule[1]}")]
    if lines[at:at + 3 * len(want)] == want_lines:
        matched = 3 * len(want)
        break
if not matched:
    print("no sanctioned literal allow block (SHELL2 six lines, SHELL3 nine, SHELL4 twelve, SHELL5 fifteen) "
          f"follows the opencode '*' allow at the pinned position (want under indent '{ind}', got {lines[at:at + 15]})"); sys.exit(1)
# cf-58 merge re-pin: after the matched sanctioned block the only permitted
# continuation is comment lines (source tree only — the rulesync YAML
# round-trip strips them from the generated mirror) plus the sanctioned git
# block, whole and in order — the thirteen shared rows plus the variant
# tail: push-deny on -local/alias files, push-allow + push-main deny + the
# four force-flag denies on -pr files; any other shell row is unsanctioned.
COMMON = [(f"{ind}- action: shell", f"{ind}  resource: {r}", f"{ind}  effect: allow") for r in
          ("git status *", "git log *", "git diff *", "git show *", "git branch *",
           "git merge-base *", "git rev-parse *", "git ls-files *", "git add *",
           "git commit *", "git checkout *", "git switch *", "git merge main*")]
def T(r, e):
    return (f"{ind}- action: shell", f"{ind}  resource: {r}", f"{ind}  effect: {e}")
TAILS = [[T("git push*", "deny")],
         [T("git push*", "allow"), T("git push*main*", "deny"), T("git push --force*", "deny"),
          T("git push -f*", "deny"), T("git push * --force*", "deny"), T("git push * -f*", "deny")]]
k = at + matched
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
            print(f"the git block's tail is neither the -local push-deny row nor the -pr push sextet (got {lines[k:k + 18]}) — unsanctioned shell grant"); sys.exit(1)
        k += 3 * len(chosen)
        continue
    break
if saw and (gi != len(COMMON) or chosen is None):
    print(f"the git block continues the shell surface but is truncated or reordered (matched {gi} of {len(COMMON)} shared rows, tail {'found' if chosen else 'missing'})"); sys.exit(1)
PY

cat >"$TMP/argcheck.py" <<'PY'
# OpenCode expands $ARGUMENTS BEFORE shell blocks run (docs warning the C02
# task cites): a $ARGUMENTS occurrence inside a !`...` block would be
# substituted into a command line instead of reaching the agent as text.
import re, sys
text = open(sys.argv[1]).read()
spans = [(m.start(), m.end()) for m in re.finditer(r'!`[^`]*`', text)]
occ = [m.start() for m in re.finditer(r'\$ARGUMENTS', text)]
if not occ:
    print('no $ARGUMENTS occurrence'); sys.exit(1)
inside = [o for o in occ for s, e in spans if s <= o < e]
if inside:
    print(f'{len(inside)} $ARGUMENTS occurrence(s) inside a !` shell block'); sys.exit(1)
PY

# --- t1: gate script exists, is clean, --help carries the contract -----------
if want t1; then
  [ -f "$GATE" ] || fail "t1: $GATE does not exist (C01 AC2 target missing — red-before-C01 is expected here)"
  [ -x "$GATE" ] || fail "t1: $GATE is not executable (C01 task: 'bash + jq, executable')"
  bash -n "$GATE" || fail "t1: bash -n rejects $GATE (AC5)"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$GATE" >"$TMP/sc.log" 2>&1 || { sed -n 1,20p "$TMP/sc.log" >&2; fail "t1: shellcheck findings (AC5 skip-with-warning is only for its ABSENCE)"; }
    ok "t1: shellcheck clean (when present — AC5)"
  else
    skip "t1: shellcheck not installed here — skipped with warning (AC5 convention)"
  fi
  run_gate --help
  cat "$TMP/g.out" "$TMP/g.err" >"$TMP/help.txt"
  for flag in '--self' '--threshold' '--grace' '--json' '--help'; do
    grep -qF -- "$flag" "$TMP/help.txt" || fail "t1: --help does not document the '$flag' flag (AC2)"
  done
  for marker in 'GATE: RUN' 'GATE: LIVE' 'GATE: SKIP'; do
    grep -qF -- "$marker" "$TMP/help.txt" || fail "t1: --help does not document the '$marker' marker (AC2)"
  done
  # Each code must appear paired with its marker on some line: the command's
  # decision rule keys on markers, so help has to bind marker↔code explicitly.
  python3 - "$TMP/help.txt" <<'PY' || fail "t1: --help does not pair each marker with its exit code (AC2: 'the three exit codes')"
import sys
txt = open(sys.argv[1]).read().lower()
bad = [f"{m}/exit {c}" for m, c in (("gate: run", "0"), ("gate: live", "2"), ("gate: skip", "1"))
       if not any(m in l and c in l for l in txt.splitlines())]
if bad:
    print("unpaired: " + ", ".join(bad)); sys.exit(1)
PY
  grep -qiE 'fail.?closed' "$TMP/help.txt" || fail "t1: --help does not state the fail-closed policy (AC2/OQ2)"
  grep -qF 'GATE_NOW_MS' "$TMP/help.txt" || fail "t1: --help does not document GATE_NOW_MS (AC2)"
  python3 "$TMP/win.py" --ci "$TMP/help.txt" 300 'GATE_NOW_MS' 'fixture' \
    || fail "t1: --help does not bind GATE_NOW_MS to fixture mode (AC2: the fixture-only rule)"
  grep -qF '15' "$TMP/help.txt" || fail "t1: --help does not state the 15-minute threshold default (D9)"
  for banned in 'curl' 'wget' 'GATE_FORCE_BOARD_FAIL'; do
    ! grep -qF -- "$banned" "$GATE" || fail "t1: '$banned' appears in the script — the session operand is CLI-only and board-free (AC5, D16)"
  done
  for banned in '--exec-count' '--env' 'GATE_FORCE_BOARD_FAIL'; do
    ! grep -qF -- "$banned" "$TMP/help.txt" || fail "t1: --help advertises deleted surface '$banned' (AC2, D17 re-pin)"
  done
  ok "t1: gate script present, executable, syntax-clean; --help carries flags + three markers + marker-paired exit codes + fail-closed + GATE_NOW_MS-fixture binding; no curl/wget/deleted-surface"
fi

# --- t2..t8: AC1 fixture matrix rows (a)-(g), fixed GATE_NOW_MS clock --------
if want t2; then
  envelope "$(sess ses_dev agent-dev 'plain dev session' 600 60)" >"$TMP/fx_a.json"
  run_gate --json "$TMP/fx_a.json"
  expect_verdict "t2 row(a): no coord session at all" 0 '^GATE: RUN( |$)'
  run_gate --json - <"$TMP/fx_a.json"
  expect_verdict "t2 row(a): same fixture via --json -" 0 '^GATE: RUN( |$)'
  ok "t2: AC1(a) empty-coord fixture -> GATE: RUN / exit 0, from file and from stdin"
fi

if want t3; then
  # updated 20 min ago: stale under the 15-min default, so this row also
  # brackets the default threshold from above (paired with t4 from below).
  envelope "$(sess ses_old agent-board-coord 'stale coord b' 2400 1200)" \
           "$(sess ses_dev2 agent-dev 'fresh dev session' 600 60)" >"$TMP/fx_b.json"
  run_gate --json "$TMP/fx_b.json"
  expect_verdict "t3 row(b): stale coord + fresh non-coord" 0 '^GATE: RUN( |$)'
  ok "t3: AC1(b) stale coord session does not block; fresh other-agent sessions are filtered out"
fi

if want t4; then
  envelope "$(sess ses_c agent-board-coord 'coord-c-live' 2400 360)" >"$TMP/fx_c.json"
  run_gate --json "$TMP/fx_c.json"
  expect_verdict "t4 row(c): fresh coord" 2 '^GATE: LIVE ses_c( |$)'
  expect_age "t4 row(c): own-updated age" 360
  grep -qF 'coord-c-live' <(fl) || fail "t4: AC1(c) first line '$(fl)' does not name the session title"
  ok "t4: AC1(c) fresh coord -> GATE: LIVE ses_c / exit 2, naming id, age and title (default threshold brackets above 6min)"
fi

if want t5; then
  # Own-updated 20 min ago (stale), child session updated 2 min ago: D2's
  # child rule must keep the coord LIVE, with the basis noted as child-fresh.
  envelope "$(sess ses_d agent-board-coord 'coord-d-child' 2400 1200)" \
           "$(sess ses_dc agent-dev 'child of d' 2400 120 ses_d)" >"$TMP/fx_d.json"
  run_gate --json "$TMP/fx_d.json"
  expect_verdict "t5 row(d): own-stale coord with fresh child" 2 '^GATE: LIVE ses_d( |$)'
  expect_age "t5 row(d): tree-newest age is the child's" 120
  grep -qiE 'child' "$TMP/g.out" || fail "t5: AC1(d) detail lines never mark the basis as child-fresh"
  ok "t5: AC1(d) child(parentID) freshness keeps the coord live; age = tree newest; child basis noted"
fi

if want t6; then
  # Updated 6 min ago is outside the 5-min grace, so only a genuine --self
  # id exclusion (not a recency accident) can turn this into RUN.
  envelope "$(sess ses_e agent-board-coord 'coord-e-self' 2400 360)" >"$TMP/fx_e.json"
  run_gate --json "$TMP/fx_e.json" --self ses_e
  expect_verdict "t6 row(e): fresh coord excluded via --self" 0 '^GATE: RUN( |$)'
  ok "t6: AC1(e) --self <id> excludes exactly that session"
fi

if want t7; then
  # Created 2 min ago (< default 5-min grace) and active: by D3 this is the
  # just-minted session of this very launch and must never count against it.
  envelope "$(sess ses_f agent-board-coord 'coord-f-young' 120 60)" >"$TMP/fx_f.json"
  run_gate --json "$TMP/fx_f.json"
  expect_verdict "t7 row(f): coord created inside --grace" 0 '^GATE: RUN( |$)'
  ok "t7: AC1(f) young-created self window excludes the freshly created coord session"
fi

if want t8; then
  # Same fixture three ways: 10 min of activity is live under the default and
  # under --threshold 15, stale under --threshold 5 — tunability proof, and
  # default≡15 bracketing from below.
  envelope "$(sess ses_g agent-board-coord 'coord-g-threshold' 2400 600)" >"$TMP/fx_g.json"
  run_gate --json "$TMP/fx_g.json"
  expect_verdict "t8 row(g): default threshold" 2 '^GATE: LIVE ses_g( |$)'
  run_gate --json "$TMP/fx_g.json" --threshold 15
  expect_verdict "t8 row(g): --threshold 15 above the 600s activity age" 2 '^GATE: LIVE ses_g( |$)'
  expect_age "t8 row(g): age" 600
  run_gate --json "$TMP/fx_g.json" --threshold 5
  expect_verdict "t8 row(g): --threshold 5 below the activity age" 0 '^GATE: RUN( |$)'
  ok "t8: AC1(g) --threshold above/below the activity age flips LIVE↔RUN on one fixture; default behaves as 15"
fi

# --- t9: rows (h) multi-live and (i) malformed inputs ------------------------
if want t9; then
  envelope "$(sess ses_h1 agent-board-coord 'coord-h-lowest' 2400 120)" \
           "$(sess ses_h2 agent-board-coord 'coord-h-higher' 2400 480)" >"$TMP/fx_h.json"
  run_gate --json "$TMP/fx_h.json"
  expect_verdict "t9 row(h): two live coords, first line = lowest age" 2 '^GATE: LIVE ses_h1( |$)'
  expect_age "t9 row(h): first-line age is the freshest coord's" 120
  grep -qF 'ses_h2' "$TMP/g.out" || fail "t9: AC1(h) detail output never lists the second live id ses_h2"
  grep -qF 'coord-h-higher' "$TMP/g.out" || fail "t9: AC1(h) detail output never names the second coord's title"
  ok "t9 row(h): multi-live — first line names the lowest-age coord, details list both ids/titles (AC1 h)"

  printf '{"data": [ {"id": "ses_m"' >"$TMP/fx_malformed.json"
  run_gate --json "$TMP/fx_malformed.json"
  expect_verdict "t9 row(i): truncated JSON" 1 '^GATE: SKIP [^[:space:]]'

  : >"$TMP/fx_empty.json"
  run_gate --json "$TMP/fx_empty.json"
  expect_verdict "t9 row(i): empty fixture file" 1 '^GATE: SKIP [^[:space:]]'

  envelope "$(sess ses_u agent-board-coord 'unreadable' 2400 360)" >"$TMP/fx_perm.json"
  chmod 000 "$TMP/fx_perm.json"
  bad="$TMP/fx_perm.json"
  # Running as root would silently read a 000 file; a nonexistent path fails
  # the same contract (fixture cannot be read) for any user.
  [ -r "$bad" ] && bad="$TMP/fx-does-not-exist.json"
  run_gate --json "$bad"
  expect_verdict "t9 row(i): unreadable fixture path" 1 '^GATE: SKIP [^[:space:]]'

  printf '{"nope":1}' >"$TMP/fx_nonenv.json"
  run_gate --json "$TMP/fx_nonenv.json"
  expect_verdict "t9 row(i): non-envelope object" 1 '^GATE: SKIP [^[:space:]]'

  printf '[%s]' "$(sess ses_arr agent-board-coord 'bare array coord' 2400 360)" >"$TMP/fx_array.json"
  run_gate --json "$TMP/fx_array.json"
  expect_verdict "t9 row(i): bare array (no data envelope)" 1 '^GATE: SKIP [^[:space:]]'
  ok "t9: AC1(i) malformed/empty/unreadable/non-envelope/bare-array fixtures each fail CLOSED -> GATE: SKIP / exit 1 with a reason"
fi

# --- t10: live smoke, skip-with-warning (first half of AC4) -------------------
# AC4's positive control (fresh coord tree ⇒ GATE: LIVE <coord-id>) is a
# manual Review step: asserting it here would pin volatile server state.
if want t10; then
  if ! command -v opencode >/dev/null 2>&1; then
    skip "t10: opencode CLI not present here — live smoke skipped with warning (AC4, intake-t14 precedent)"
  else
    RC=0
    timeout 60 bash "$GATE" >"$TMP/g.out" 2>"$TMP/g.err" || RC=$?
    if [ "$RC" -eq 124 ]; then
      skip "t10: live invocation timed out (server unreachable) — skipped with warning (AC4)"
    else
      line=$(fl)
      [[ "$RC" =~ ^[012]$ ]] \
        || fail "t10: live run exited $RC, want 0/1/2$([ -f "$GATE" ] || echo " — $GATE absent (red-before-C01)")"
      [[ "$line" =~ ^GATE:\ (RUN|LIVE|SKIP)(\ |$) ]] \
        || fail "t10: live first line '$line' is not one of the three markers (AC4)"
      ok "t10: live smoke exited $RC with a valid first-line marker (positive control stays a Review step)"
    fi
  fi
fi

# --- t11: /pipeline-boards-hourly command contract (source + generated) -------
t11_contract() { # one file, the whole AC1 string set
  local f="$1"
  [ -f "$f" ] || fail "t11: $f is missing (C02 AC1 — red-before-C02 is expected here)"
  grep -qF 'bash scripts/agent-board-coord-gate.sh' "$f" \
    || fail "t11: $f does not carry the exact gate line 'bash scripts/agent-board-coord-gate.sh' (AC1)"
  python3 "$TMP/win.py" --ci "$f" 120 'bash scripts/agent-board-coord-gate.sh' '|| true' \
    || fail "t11: $f gate line is not paired with '|| true' — a non-zero verdict exit would blank the inserted output (D17)"
  for marker in 'GATE: RUN' 'GATE: LIVE' 'GATE: SKIP'; do
    grep -qF -- "$marker" "$f" || fail "t11: $f never names the '$marker' marker (AC1 decision rule)"
  done
  python3 "$TMP/win.py" --ci "$f" 600 'GATE: LIVE' 'BOARD CHECK' \
    || fail "t11: $f does not tie the GATE: LIVE verdict to a BOARD CHECK section (AC1)"
  python3 "$TMP/win.py" --ci "$f" 900 'ai-dev' 'in process' 'executing' \
    || fail "t11: $f does not name board AI-Dev / swimlane In Process / list Executing as one passage (AC1)"
  # C03 AC3 (folded minor-1, D24 r2): the LIVE-branch resolution chain's own
  # steps (list_swimlanes/list_lists) join the read allow-list — eight read
  # operations pinned in one passage.
  python3 "$TMP/win.py" "$f" 1500 'list_boards' 'get_board' 'list_cards_in_list' 'get_card' 'list_comments' 'list_swimlanes' 'list_lists' \
    || fail "t11: $f read-only allow list is incomplete (C02 AC1 five tools + C03 AC3 folded minor-1: list_swimlanes, list_lists)"
  python3 "$TMP/win.py" "$f" 1500 'move_card' 'add_comment' 'set_card_custom_field' 'delete_checklist_item' 'toggle_checklist_item' \
    || fail "t11: $f write-deny list is incomplete (AC1 names all five banned operations)"
  python3 "$TMP/win.py" --ci "$f" 400 'unavailable' 'fail-closed' \
    || fail "t11: $f does not state the board-check-unavailable => skip fail-closed rule (AC1, row 4)"
  python3 "$TMP/win.py" --ci "$f" 300 'continue exactly as' '/pipeline-boards' \
    || fail "t11: $f lacks the 'continue exactly as /pipeline-boards' clause — the boards skill must stay the flow authority (AC1)"
  python3 "$TMP/win.py" --ci "$f" 300 'manual' 'ungated' \
    || fail "t11: $f never notes that manual one-off launches are ungated by design (AC1, D11)"
  grep -qF -- '--threshold 0' "$f" || fail "t11: $f does not carry the --threshold 0 forced-through escape note (AC1)"
  # C03 AC3 (nit-1 folded): the escape is a HOST-shell action — agent-board-coord
  # has no shell (t17), so the note must say whose shell; window pairs the
  # substring with the host clarifier instead of trusting either alone.
  python3 "$TMP/win.py" --ci "$f" 200 '--threshold 0' 'host' \
    || fail "t11: $f pairs --threshold 0 with no on-the-host clarifier (C03 AC3 folded nit-1)"
  grep -qE '^[[:space:]]*agent:[[:space:]]+agent-board-coord$' "$f" \
    || fail "t11: $f frontmatter does not target agent agent-board-coord (AC1)"
  python3 "$TMP/argcheck.py" "$f" \
    || fail "t11: $f puts \$ARGUMENTS inside a !\` shell block or omits it (AC1 — OpenCode expands args BEFORE shell blocks)"
}
if want t11; then
  t11_contract "$CMD_SRC"
  t11_contract "$CMD_GEN"
  ok "t11: C02 AC1 contract strings + C03 AC3 strengthened windows in the hourly command source AND generated copy"
fi

# --- t12: byte-freeze of the surfaces still frozen (C02 AC2 → C03 AC4 carve) --
# Round-2 re-pin (D21 r2): the user's OQ-R1 answer re-opens the boards skill
# and the /pipeline-boards command pair — C03 deliberately edits them, so
# they leave the freeze set; everything else C02 froze stays frozen, and
# t18/t19/t13 now guard the re-opened pair for WHAT it may contain.
# tests-edit-perms D4 carve (second re-pin): the agents-sync references pair
# permissions.md + pipeline-overview.md (source and generated) leave the byte
# freeze too — this ticket edits that matrix/incident prose, and a prose
# delta-pin across future tickets is a treadmill. The carve covers EXACTLY
# those four paths (the exclusion line is pinned by agent-perms A7); the pair
# moves to source<->generated byte-equality here (rulesync copies them
# verbatim — a hand-edited mirror or an un-regenerated source fails), their
# content is row-anchored by rulesync-surface c6 / agents-md c5, and the
# NEW invariant itself by agent-perms A1-A4. The exclusion literal below is
# shared verbatim with coord-inwork i5 (the A7 pin greps both).
# cf-75 C02 re-pin (2026-10-27): plan-and-result.md joins the carve (source +
# generated) — C02 rewrites its validation_at_fault routing sentence (the
# retry-cap/deviation wording is untouched), guarded by the same pair-
# equality loop below, agent-perms A5 + validation-fix t6; the exclusion
# literal moves in lockstep in t12, i5 and A7's needles (three-way pin —
# editing one without the others fails A7).
if want t12; then
  moved=$( { git diff --name-only "$BASE" -- "$AS_SRC" "$AS_GEN" 2>/dev/null || true;
             git ls-files --others --exclude-standard -- "$AS_SRC" "$AS_GEN"; } \
           | sort -u \
           | grep -v -x -E -e '(\.rulesync|\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview|plan-and-result)\.md' \
           || true )
  if [ -n "$moved" ]; then
    printf '%s\n' "$moved" >&2
    fail "t12: an agents-sync file changed vs $BASE outside the carve — only references/permissions.md + pipeline-overview.md + plan-and-result.md (source and generated) may move; the rest stays byte-frozen (tests-edit-perms D4; cf-75 C02 grew the trio; C03 AC4 zero-edits elsewhere)"
  fi
  for pair in "$AS_SRC/references/permissions.md|$AS_GEN/references/permissions.md" \
              "$AS_SRC/references/pipeline-overview.md|$AS_GEN/references/pipeline-overview.md" \
              "$AS_SRC/references/plan-and-result.md|$AS_GEN/references/plan-and-result.md"; do
    IFS='|' read -r psrc pgen <<<"$pair"
    [ -f "$psrc" ] && [ -f "$pgen" ] || fail "t12: carved pair file missing ($psrc / $pgen)"
    cmp -s "$psrc" "$pgen" \
      || fail "t12: carved pair drifted source<->generated: $psrc vs $pgen are not byte-identical — rulesync copies these verbatim, so the text edit must land in the source and regenerate, never in the mirror"
  done
  ok "t12: agents-sync byte-unchanged vs $BASE except the carved references trio (permissions.md + pipeline-overview.md + plan-and-result.md pairs, guarded byte-equal source<->generated); boards/manual-command pair re-opened by the C03 carve"
fi

# --- t13: shared "Current state:" block byte-equality (AC3) -------------------
state_block() {
  awk '/^Current state:$/{p=1} p{print} p&&/^!`/{exit}' "$1"
}
if want t13; then
  b1=$(state_block "$CMD_BASE_SRC")
  [ -n "$b1" ] || fail "t13: could not extract the 'Current state:' block from $CMD_BASE_SRC (frozen manual surface changed shape?)"
  [ -f "$CMD_SRC" ] || fail "t13: $CMD_SRC missing — nothing to compare the shared block against (red-before-C02)"
  b2=$(state_block "$CMD_SRC")
  [ "$b1" = "$b2" ] \
    || { printf '=== pipeline-boards\n%s\n=== hourly\n%s\n' "$b1" "$b2" >"$TMP/block.diff"; fail "t13: 'Current state:' block drifted between the two command sources (AC3 drift detector; see $TMP/block.diff)"; }
  ok "t13: the 'Current state:' !-block is byte-identical in both command sources (AC3)"
fi

# --- t14: AC4 — changed paths == Files in scope, then rulesync no-op ----------
# tests-edit-perms D4/D9 widening (kept verbatim): that ticket's in-scope
# paths join the union-of-tickets allow-set — the agent-test/agent-dev-perm
# pairs era paths, the four carved agents-sync references files, the
# pipeline-role-test pair and tests/** — PLUS the three follow-up ticket
# folders that 124fc2ae8 introduced: a landing that adds plan folders must
# not read as a scope violation for every later guard. The folder patterns
# are written inline as literals (not variables) so the agent-perms A9 pin
# can window-grep them inside this block.
# cf-58 widening (C03/C04/C06): this ticket rewrites the whole agent-
# definition surface — subagent/command sources, their generated mirrors,
# the new skill dirs and the hand-managed .opencode/opencode.jsonc — so
# those join as directory wildcards (the retired pre-split dev-path literal
# is gone with the rename sweep, agent-perms A13). Skill dirs are widened
# one per edited contract, NOT a blanket skills/* — pipeline-role-dev joins
# with the C03 description fold-in (validation_at_fault round 3: C03's
# user-pinned edit tripped the enumeration gap); an unsanctioned skill edit
# still fails here. Granularity trades to the
# positive guards: t12 still fences agents-sync outside the carve,
# rulesync-surface c17 still fences pipeline-gates, and every cf-58 surface
# has its own content suite. Infra dirs (charts/containers/services/
# custom-values) stay OUTSIDE the allow-set.
# cf-75 widening (agent-test, 2026-10-27; same per-contract enumeration):
# C02 re-opens the pipeline-gates pair (its content suite is
# tests/pipeline-gates/validation-fix.sh; rulesync-surface c17's gates
# byte-freeze left with that RE-PIN — the sentence above holds only up to
# cf-75) and the pipeline-role-review pair (content: validation-fix t3), and
# adds plan-and-result.md to the carved agents-sync references trio (pair
# equality: validation-fix t6 + agent-perms A5/A7). C01 adds the new
# skills/wekan-mcp dir and the wekan-api pointer edit; C04 adds the
# hand-managed .opencode/plugin/board-context dir (rulesync never touches
# .opencode/plugin/ — AGENTS.md); plus this ticket's own plan folder (inline
# literal for the agent-perms A9 window-pin).
if want t14; then
  { git diff --name-only "$BASE" || true; git ls-files --others --exclude-standard; } | sort -u >"$TMP/changed.txt"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "$GATE"|scripts/*|tests/*|AGENTS.md|"$RULES_SRC"|"$AGENT_SRC"|"$AGENT_GEN"|"$COORD_SRC"|"$COORD_GEN"|\
      "$CMD_SRC"|"$CMD_GEN"|"$CMD_BASE_SRC"|"$CMD_BASE_GEN"|\
      "$BOARDS_SRC"/*|"$BOARDS_GEN"/*|"$FEATURE"/*|\
      "$FEATURE3"/*|.rulesync/subagents/*|.opencode/agents/*|\
      .rulesync/commands/*|.opencode/commands/*|\
      .rulesync/skills/pipeline-gates/*|.opencode/skills/pipeline-gates/*|\
      .rulesync/skills/pipeline-role-review/*|.opencode/skills/pipeline-role-review/*|\
      "$KICK_SRC_DIR"/*|"$KICK_GEN_DIR"/*|"$RC_SRC_DIR"/*|"$RC_GEN_DIR"/*|\
      .rulesync/skills/pipeline-push-pr/*|.opencode/skills/pipeline-push-pr/*|\
      .rulesync/skills/pipeline-models/*|.opencode/skills/pipeline-models/*|\
      .rulesync/skills/role-dev/*|.opencode/skills/role-dev/*|\
      .rulesync/skills/pipeline-role-dev/*|.opencode/skills/pipeline-role-dev/*|\
      .rulesync/skills/role-planner/*|.opencode/skills/role-planner/*|\
      .rulesync/skills/role-code/*|.opencode/skills/role-code/*|\
      .rulesync/skills/role-debug/*|.opencode/skills/role-debug/*|\
      .opencode/opencode.jsonc|.opencode/plugin/board-context/*|\
      skills/wekan-mcp/*|skills/wekan-api/*|\
      "$AS_SRC"/references/permissions.md|"$AS_GEN"/references/permissions.md|\
      "$AS_SRC"/references/pipeline-overview.md|"$AS_GEN"/references/pipeline-overview.md|\
      "$AS_SRC"/references/plan-and-result.md|"$AS_GEN"/references/plan-and-result.md|\
      .rulesync/skills/pipeline-role-test/*|.opencode/skills/pipeline-role-test/*|\
      .agents/plans/2026/2026-10-cf-58-feat-standalone-agent-merge/*|\
      .agents/plans/2026/2026-10-bug-kickoff-mints-run-branch/*|\
      .agents/plans/2026/2026-10-bug-session-origin-no-line/*|\
      .agents/plans/2026/2026-10-bug-tests-edit-perms/*|\
      .agents/plans/2026/2026-10-bug-board-coord-dev-boards-allow/*|\
      .agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/*|\
      .agents/plans/2026/2026-10-docs-wekan-mcp-arg-ergonomics/*) : ;;
      *) fail "t14: path outside the ticket's Files in scope: $p (base: $BASE, C02 AC4 + C03 AC5 scope + cf-52 + tests-edit-perms D4/D9 + cf-58 + cf-75 widenings)" ;;
    esac
  done <"$TMP/changed.txt"
  ok "t14: changed paths limited to the ticket's Files in scope, round-2 surfaces, the cf-52 coord-pair widening, the tests-edit-perms D4/D9 widening (three 2026-10-bug-* folders), the kickoff-mints scripts/* admit, the cf-58 agent-surface widening and the cf-75 skill/plugin/gates/review/plan-and-result/own-folder admits (base: $BASE)"

  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "t14: rulesync not resolvable here (PATH or npx cache) — regenerate gate skipped with warning (intake-t14 precedent)"
  else
    $RS generate >"$TMP/rs1.log" 2>&1 || { tail -n 20 "$TMP/rs1.log" >&2; fail "t14: first rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    $RS generate >"$TMP/rs2.log" 2>&1 || { tail -n 20 "$TMP/rs2.log" >&2; fail "t14: second rulesync generate failed"; }
    snap_after=$(git status --porcelain)
    if [ "$snap_before" != "$snap_after" ]; then
      printf '%s\n' "--- after first run
$snap_before
--- after second run
$snap_after" >"$TMP/noop.diff"
      fail "t14: the second rulesync generate is not a no-op (sources and generated surfaces drifted; see $TMP/noop.diff)"
    fi
    ok "t14: rulesync generate idempotent on the second run (via $RS) — sources + generated committed together (AC4)"
  fi
fi

# --- t15: hourly pointer — presence HOLD (cf-58 RE-PIN) ------------------------
# Original C02 AC5 pinned the pointer as exactly ONE appended sentence and
# C03 AC4 froze the agent body byte-identical from a base shipping the
# pointer. cf-58 C03/C05 legitimately EDIT the board-coord bodies (variant
# files copy the paragraph, C05 rewrites its checklist enumeration), so the
# frozen-body arm is retired; what survives — the actual contract — is that
# the hourly pointer sentence stays present in both trees and no gate
# mechanics ever leak into the agent body. Red posture: HOLD green now, red
# only if a chunk drops the pointer or leaks mechanics.
body_of() { awk 'c>=2{print} /^---$/{c++}' "$1"; }   # skeleton convention from rulesync-surface c16
if want t15; then
  n=0
  for f in "$AGENT_SRC" "$AGENT_GEN"; do
    n=$((n + 1))
    body_of "$f" >"$TMP/t15-body-$n"
    grep -qF 'pipeline-boards-hourly' "$TMP/t15-body-$n" \
      || fail "t15: $f body lost the hourly pointer sentence (C02 AC5 presence — the pointer survives every cf-58 body edit)"
    for mech in 'GATE:' '--threshold' 'BOARD CHECK'; do
      ! grep -qF -- "$mech" "$TMP/t15-body-$n" || fail "t15: $f body carries gate mechanics '$mech' — mechanics live in the script/command only (AC5)"
    done
  done
  ok "t15: hourly pointer sentence present in source and mirror; no gate mechanics in the agent bodies (cf-58 presence re-pin of the frozen-body arms)"
fi

# --- t16: rules surface — cf-58 RE-PIN of the additive-only arm ----------------
# The scripts/ bullet + the hourly-command name are presence pins; the
# deletion guard survives but narrows to the facts cf-58 may NOT remove:
# the scripts/ entry and the gate-script reference (cf-50 AC6's merged
# surface). cf-58 rewrites the AGENT bullets in the rules source (C02/C03/
# C04/C05 overview tasks), so the old "no deleted line except the
# agent-board-coord sentence" freeze contradicts the plan; deleted lines
# mentioning the scripts/gate facts are the violation that matters.
if want t16; then
  for f in "$RULES_SRC" AGENTS.md; do
    grep -qE '^[[:space:]]*[-*][[:space:]].*`scripts/`' "$f" \
      || fail "t16: $f has no scripts/ bullet — the rules entry is missing (C02 AC6)"
    grep -qF 'pipeline-boards-hourly' "$f" \
      || fail "t16: $f never names pipeline-boards-hourly (AC6: agents-section extension)"
    git diff "$BASE" -- "$f" | grep '^-' | grep -v '^---' | grep -E 'scripts/|agent-board-coord-gate\.sh' >"$TMP/rem-lines.txt" || true
    if [ -s "$TMP/rem-lines.txt" ]; then
      cat "$TMP/rem-lines.txt" >&2
      fail "t16: $f deletes a line carrying the scripts/ or gate-script fact — cf-58 may rewrite AGENT bullets, but the cf-50 scripts/ surface stays (agent-perms A7 sibling discipline)"
    fi
  done
  ok "t16: scripts/ bullet + hourly-variant name present in rules source AND AGENTS.md; no scripts/gate fact deleted (cf-58 re-pin of the additive-only arm)"
fi

# --- t17: coord-family frontmatter — cf-58 RE-PIN (absolute family contract) ---
# History: D13 froze the board-coord frontmatter bytes; cf-52 re-pinned to
# "base + exactly the two scoped opencode-api session allows" (arm A/arm B
# splice OR-form, historical refs 081b57889 / f11bfcb85 / 916044893 stay
# documented in the header); tests-edit-perms D10 made the arms OR-form.
# cf-58 C03 supersedes the delta form: the sanctioned content is now the API
# pair PLUS the git block on all SIX family agents, so t17 pins the
# absolute family contract on every one of the twelve files — API
# containment (the two session allows exactly, no third API grant — the
# cf-52 axis that made the delta meaningful), pinned position (atpos line
# twin at the committed/posture), git-only additional shell rows, variant
# dev-slot rosters, plan-state edit allows, board extras, deny-baseline and
# question allow. The arm-aware empty-diff twin keeps the cf-52 T10
# discipline: never "empty diff implies pass".
# argv: file, class(local|pr), board(0|1) — same guard as coord-inwork i4
# (each suite carries its own copy by the suites' self-contained convention).
cat >"$TMP/cfpins.py" <<'PY'
# (identical contract to tests/coord-inwork/surface.sh cfpins.py — keep in
# step when either moves; agent-perms A10 proves the pattern non-vacuous.)
import re, sys, yaml
path, cls, board = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
API = [{"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"},
       {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"}]
errs = []
if perms and perms[0] != {"action": "*", "resource": "*", "effect": "deny"}:
    errs.append("deny-baseline first rule changed")
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in perms):
    errs.append("question allow lost (repo hard rule)")
api_rows = [p for p in perms if p.get("action") == "shell" and str(p.get("resource", "")).startswith("opencode api")]
if api_rows != API:
    errs.append(f"opencode-api shell rows are {api_rows}, want exactly the two scoped session allows in get/patch order")
anchors = [i for i, p in enumerate(perms) if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
if len(anchors) != 1:
    errs.append(f"want exactly one opencode '*' allow anchor, found {len(anchors)}")
else:
    i = anchors[0]
    if perms[i + 1:i + 3] != API:
        errs.append("the api pair does not sit directly after the opencode '*' allow (pinned splice position)")
SANCTIONED_SCRIPTS = ("bash scripts/kickoff-mint-branch.sh *", "bash scripts/session-origin.sh*")
others = [p.get("resource") for p in perms if p.get("action") == "shell"
          and not str(p.get("resource", "")).startswith(("opencode api", "git "))
          and p.get("resource") != "*"
          and p.get("resource") not in SANCTIONED_SCRIPTS
          and p.get("resource") != "date *"]
if others:
    errs.append(f"non-API non-git shell rows present: {others} (coord shell surface = API pair + the two cf-52 sanctioned script allows + the date allow + git block + ask baseline)")
# 2026-10-27 date-grant re-pin: the kickoff in-work mark embeds
# $(date +%s%3N) in the patch payload; the shell matcher extracts command
# substitutions and checks the date subcommand against this agent's own
# list, so the allow is a presence duty, not merely an admitted row.
if not any(p.get("action") == "shell" and p.get("resource") == "date *" and p.get("effect") == "allow" for p in perms):
    errs.append("the `date *` allow is gone (the in-work mark's epoch subcommand would fall back to the deny baseline — the global date allow never reaches it)")
slot = "agent-dev-pr" if cls == "pr" else "agent-dev-local"
subs = sorted(p.get("resource") for p in perms if p.get("action") == "subagent" and p.get("effect") == "allow")
want_subs = sorted(["agent-plan", "agent-test", slot, "agent-review", "agent-research"])
if subs != want_subs:
    errs.append(f"subagent allows {subs}, want the five roles with dev slot {slot}")
edits = sorted(p.get("resource") for p in perms if p.get("action") == "edit")
if edits != sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"]):
    errs.append(f"edit allows are {edits}, want only the three plan-state files")
if board:
    db = [i for i, p in enumerate(perms) if p.get("action") == "dev-boards*"]
    if len(db) != 1 or db[0] < 1 or perms[db[0]].get("effect") != "allow":
        errs.append("the single narrow dev-boards* allow is gone (board variants keep it)")
    if not any(p.get("action") == "execute" and p.get("effect") == "allow" for p in perms):
        errs.append("execute allow lost from a board variant (Code Mode transport)")
    if any(p.get("action") == "dev*" for p in perms):
        errs.append("broad dev* allow appeared on a board variant (D21)")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
if want t17; then
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    [ -f "$f" ] || fail "t17[C03]: $f missing — the six-agent coord family is the re-pinned contract set (red before C03)"
  done
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    # *-pr.md not *-pr — the bare pattern never matches .md names and falls
    # through to the -local arms (validation_at_fault round 3).
    case "$f" in *-pr.md) cls=pr ;; *) cls=local ;; esac
    case "$f" in *board-coord*) board=1 ;; *) board=0 ;; esac
    python3 "$TMP/cfpins.py" "$f" "$cls" "$board" \
      || fail "t17[C03]: $f violates the absolute coord-family contract (class $cls, board $board) — cf-58 C03 API containment + git-only shells + roster slot + shapes (base: $BASE)"
    if git diff --quiet "$BASE" -- "$f"; then
      python3 "$TMP/atpos.py" "$f" \
        || fail "t17[C03]: $f has an empty diff vs $BASE (committed posture) but does not carry the six literal API allow lines directly after the opencode '*' allow"
    fi
  done
  ok "t17[C03]: all twelve coord-family files carry the absolute family contract (two scoped API allows at the pinned position, git-only additional shell rows, variant rosters, plan-state edits, board extras, deny-baseline + question allow); committed files line-twinned at pinned position"
fi

# --- t20: liveness filter counts ALL THREE board-coord names (cf-58 C03) --------
# The plan names the gate's single-literal filter a double-launch risk if it
# misses a name: scheduled launches create the ALIAS (agent-board-coord),
# manual -local/-pr runs create the variants, and a stale gate lets two
# board-coord runs collide. Pins: (a) the three exact names appear as quoted
# literals in the script, (b) no startswith-style prefix matching (the
# agents-sync exact-names lesson), (c) the old single-equality filter line
# is gone, (d) --help/usage text names all three, (e) fixture behavior: one
# fresh session of EACH name -> LIVE; only stale ones of the three -> RUN;
# a fresh FOREIGN agent -> RUN.
if want t20; then
  grep -qF '"agent-board-coord"' "$GATE" \
    || fail "t20[C03]: $GATE lacks the exact quoted alias name (red before C03)"
  grep -qF '"agent-board-coord-local"' "$GATE" \
    || fail "t20[C03]: $GATE lacks the exact quoted -local name (red before C03)"
  grep -qF '"agent-board-coord-pr"' "$GATE" \
    || fail "t20[C03]: $GATE lacks the exact quoted -pr name (red before C03)"
  ! grep -qE 'startswith|StartsWith|\| startswith' "$GATE" \
    || fail "t20[C03]: $GATE matches agent names by prefix — C03 pins explicit enumeration (agents-sync lesson: exact names only)"
  ! grep -qF 'map(select(.agent == "agent-board-coord"))' "$GATE" \
    || fail "t20[C03]: the old single-literal filter is still the liveness expression — C03 replaced it (red before C03)"
  run_gate --help
  cat "$TMP/g.out" "$TMP/g.err" >"$TMP/t20-help.txt"
  for n in agent-board-coord agent-board-coord-local agent-board-coord-pr; do
    grep -qF "$n" "$TMP/t20-help.txt" \
      || fail "t20[C03]: --help/usage text never names $n — the header/usage update is part of the filter widening"
  done
  for n in agent-board-coord agent-board-coord-local agent-board-coord-pr; do
    envelope "$(sess "ses_$n" "$n" "fresh $n run" 2400 360)" >"$TMP/t20-$n.json"
    run_gate --json "$TMP/t20-$n.json"
    expect_verdict "t20 fixture: one fresh $n session counts as live" 2 "^GATE: LIVE ses_$n( |$)"
  done
  envelope "$(sess ses_a1 agent-board-coord 'stale alias' 2400 1200)" \
           "$(sess ses_a2 agent-board-coord-local 'stale local' 2400 1200)" \
           "$(sess ses_a3 agent-board-coord-pr 'stale pr' 2400 1200)" >"$TMP/t20_stale.json"
  run_gate --json "$TMP/t20_stale.json"
  expect_verdict "t20 fixture: only stale board-coord sessions -> RUN" 0 '^GATE: RUN( |$)'
  envelope "$(sess ses_x agent-coord-pr 'fresh foreign coord' 2400 120)" >"$TMP/t20_foreign.json"
  run_gate --json "$TMP/t20_foreign.json"
  expect_verdict "t20 fixture: a fresh NON-board-coord session stays RUN" 0 '^GATE: RUN( |$)'
  ok "t20[C03]: liveness set = the three explicit board-coord names (alias + -local + -pr) in code AND usage text, no prefix matching, old single-literal filter gone; fixtures prove LIVE each / RUN stale-only / RUN foreign"
fi

# --- t18: Session origin block contract across all four command files (C03) ---
# No concrete host is pinned anywhere in t18/t19: pinning one is exactly the
# round-1 defect class (RESEARCH Contradiction 1 — the shipped intake-D20
# literal answers 400, coderd rejects it as a malformed app host).
origin_block() { awk '/^!`/ && /VSCODE_PROXY_URI/ {print; exit}' "$1"; }
origin_lead() { grep -m1 '^Session origin rule:' "$1" || true; }
if want t18; then
  n=0
  for f in "$CMD_BASE_SRC" "$CMD_BASE_GEN" "$CMD_SRC" "$CMD_GEN"; do
    n=$((n + 1))
    [ -f "$f" ] || fail "t18: $f is missing"
    origin_block "$f" >"$TMP/blk-$n"
    [ -s "$TMP/blk-$n" ] || fail "t18: $f carries no Session origin !-block (C03 AC1 — red-before-C03: the block is absent everywhere)"
    origin_lead "$f" >"$TMP/lead-$n"
    [ -s "$TMP/lead-$n" ] || fail "t18: $f lacks the 'Session origin rule:' lead-in line (C03 AC1: one identical line before each block)"
    cmp -s "$TMP/blk-$n" "$TMP/blk-1" || fail "t18: the origin block differs between $CMD_BASE_SRC and $f — sources AND generated copies must carry the identical block (C03 AC1)"
    cmp -s "$TMP/lead-$n" "$TMP/lead-1" || fail "t18: the lead-in differs between $CMD_BASE_SRC and $f (C03 AC1)"
    for s in 'VSCODE_PROXY_URI' 's/{{port}}/openchamber/' '{{port}}' 'Session origin:' 'UNRESOLVED' 'RAW session id' 'RESULT' '-m 5' 'curl'; do
      grep -qF -- "$s" "$f" || fail "t18: $f does not carry '$s' (C03 AC1 substring set: derivation, shape guard, emitted line, raw-id+RESULT fallback, probe)"
    done
    python3 "$TMP/win.py" "$f" 120 '200' '301' '302' '303' '401' '403' \
      || fail "t18: $f lacks the self-probe recognition set {200,301,302,303,401,403} in one passage (D22 r2)"
    if grep -qF 'openchamber--' "$f"; then fail "t18: $f contains a concrete OpenChamber host literal — the origin is emitted by the block, never stored (RESEARCH Implications.3)"; fi
  done
  # Hourly placement: the block sits after the GATE: SKIP stop rule (the
  # SKIP one-line posture stays unaffected inert text) and before Notes:.
  python3 - "$CMD_SRC" "$TMP/blk-3" <<'PY' || fail "t18: hourly placement broken — expected GATE: SKIP rule < origin block < Notes: heading (C03 Tasks)"
import sys
blk = open(sys.argv[2]).read().strip()
txt = open(sys.argv[1]).read()
a, b, c = txt.find('GATE: SKIP'), txt.find(blk), txt.find('\nNotes:')
if not (-1 < a < b < c):
    print(f'got GATE: SKIP at {a}, block at {b}, Notes: at {c}'); sys.exit(1)
PY
  # Manual command: the block follows the shared Current state: block.
  python3 - "$CMD_BASE_SRC" "$TMP/blk-1" <<'PY' || fail "t18: manual-command placement wrong — the origin block must follow the Current state: block (C03 Tasks)"
import sys
blk = open(sys.argv[2]).read().strip()
txt = open(sys.argv[1]).read()
a, b = txt.find('state=$(find .agents/plans'), txt.find(blk)
if not (-1 < a < b):
    print(f'got Current state: block at {a}, origin block at {b}'); sys.exit(1)
PY
  ok "t18: identical Session origin lead-in + block in both sources and both generated copies, D22 probe strings + recognition set present, no host literal, placement per Tasks (C03 AC1)"
fi

# --- t19: boards-skill dynamic-origin contract (C03 AC2) -----------------------
if want t19; then
  for f in "$BOARDS_SRC/SKILL.md" "$BOARDS_GEN/SKILL.md"; do
    [ -f "$f" ] || fail "t19: $f is missing"
    # Negatives first: until C03 lands, the skill still ships the dead host —
    # the red reason must name that, not a missing dynamic phrase.
    if grep -qF 'openchamber--dev-thehackmeister-coder' "$f"; then
      fail "t19: $f still ships the dead intake-D20 host literal (D25 r2: coderd answers it 400 — absence is correctness, not drift)"
    fi
    if grep -qF 'SESSION_URL_BASE = https://' "$f"; then
      fail "t19: $f hard-codes SESSION_URL_BASE again (C03 AC2: the value is THIS run's Session origin line)"
    fi
    for s in 'SESSION_URL_BASE' 'Session origin:' 'VSCODE_PROXY_URI' 'UNRESOLVED'; do
      grep -qF -- "$s" "$f" || fail "t19: $f lost '$s' (C03 AC2 dynamic contract)"
    done
    grep -qF '$(SESSION_URL_BASE)/?session=<sessionID>' "$f" \
      || fail "t19: $f lost the byte-preserved link shape (C03 AC2: only the provenance moved, not the format)"
    grep -qF 'Never a raw session id (D13)' "$f" \
      || fail "t19: $f dropped D13's resolved-branch rule (C03 AC2: retained with its scope annotated)"
    # UNRESOLVED is DEFINED precisely (D22 r2): the three block branches read
    # as one passage, not scattered file-wide hits.
    python3 "$TMP/win.py" --ci "$f" 900 'UNRESOLVED' 'absent' 'shape' 'answered' \
      || fail "t19: $f does not define UNRESOLVED via all three branches (env absent / template shape / answered code) in one passage (C03 AC2)"
    python3 "$TMP/win.py" --ci "$f" 400 'raw session id' 'proceed' \
      || fail "t19: $f lacks the D23-r2 fallback posture (UNRESOLVED proceeds and writes the RAW session id)"
    python3 "$TMP/win.py" --ci "$f" 600 'raw session id' 'RESULT' \
      || fail "t19: $f does not bind the fallback to the RESULT record channel (C03 AC2)"
    python3 "$TMP/win.py" --ci "$f" 200 'never' 're-guess' \
      || fail "t19: $f lost the never-silently-re-guess ban (C03 AC2)"
    python3 "$TMP/win.py" --ci "$f" 400 'consistency' 'mismatch' \
      || fail "t19: $f does not carry the run-scoped consistency-vs-block check (C03 AC2: the drift check reworded)"
    # Every other D20 constant keeps copy-verbatim byte-exact (D18 r2):
    # RESEARCH_LABEL is the surviving exemplar of that set.
    git show "$BASE:$f" >"$TMP/rl-src" 2>/dev/null || fail "t19: $f not readable at $BASE"
    grep -F 'RESEARCH_LABEL = Research' "$TMP/rl-src" >"$TMP/rl-base" || fail "t19: RESEARCH_LABEL line absent at $BASE in $f"
    grep -F 'RESEARCH_LABEL = Research' "$f" >"$TMP/rl-cur" || fail "t19: $f lost the RESEARCH_LABEL line entirely (D18 r2)"
    cmp -s "$TMP/rl-base" "$TMP/rl-cur" \
      || fail "t19: $f RESEARCH_LABEL line changed vs $BASE — only SESSION_URL_BASE's provenance moves (D18 r2)"
  done
  ok "t19: boards skill (src + gen) free of host literals, dynamic Session-origin definition with all three UNRESOLVED branches, raw-id+RESULT fallback, never-re-guess, consistency check, preserved link shape and verbatim RESEARCH_LABEL (C03 AC2)"
fi

printf 'PASS: agent-board-coord gate contract checks (%d ok)\n' "$checks"
