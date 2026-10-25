#!/usr/bin/env bash
# agent-board-coord debounce-gate contract suite (2026/2026-10-cf-50-feat-
# prevent-multiple-agent-board-coords, C01 + C02).
#
# Pins D17's three-state session-operand contract for
# scripts/agent-board-coord-gate.sh (t1..t10) and the /pipeline-boards-hourly
# command surface plus the manual-path byte-freeze (t11..t17). Written before
# the implementation exists — red-before-green by design:
#   C01 not landed: t1 fails file-not-found; t2..t9 fail as invocation
#     errors (exit 127); t10 fails-or-skips.
#   C02 not landed: t11/t13/t15/t16 fail on missing strings/files;
#     t12/t14/t17 are invariance guards — green at plan time and must HOLD.
#
# AC trace: t1[C01 AC2+AC5] t2[AC1 a] t3[AC1 b] t4[AC1 c] t5[AC1 d]
# t6[AC1 e] t7[AC1 f] t8[AC1 g] t9[AC1 h+i] t10[C01 AC4] t11[C02 AC1]
# t12[AC2] t13[AC3] t14[AC4] t15[AC5] t16[AC6] t17[AC2/D13].
#
# AC7 (regression) is not re-implemented here: run
# tests/agent-board-coord/rulesync-surface.sh and agents-md.sh; their scope
# allow-lists already carry this ticket's in-surface paths. agents-md.sh c8
# checks AGENTS.md section-level deltas only when an explicit CHUNK_BASE
# points at a pre-C02 commit — C02's legitimate `scripts/` bullet then trips
# its allow-set: that is the plan's documented validation_at_fault hand-back,
# not a C02 defect.
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
#   bash tests/agent-board-coord/gate.sh                # t1..t17
#   bash tests/agent-board-coord/gate.sh t4 t9          # subset
#   CHUNK_BASE=<pre-C01 commit> bash tests/agent-board-coord/gate.sh  # for t12/t14/t15/t16/t17
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

GATE="scripts/agent-board-coord-gate.sh"
NOW_MS=1700000000000
FXDIR="$(pwd)"

FEATURE=".agents/plans/2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords"
RULES_SRC=".rulesync/rules/overview.md"
AGENT_SRC=".rulesync/subagents/agent-board-coord.md"
AGENT_GEN=".opencode/agents/agent-board-coord.md"
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
  for i in $(seq 1 17); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[0-7])$ ]] || fail "unknown check id '$a' (expected t1..t17)"
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
  python3 "$TMP/win.py" "$f" 1500 'list_boards' 'get_board' 'list_cards_in_list' 'get_card' 'list_comments' \
    || fail "t11: $f read-only allow list is incomplete (AC1: list_boards, get_board, list_cards_in_list, get_card, list_comments)"
  python3 "$TMP/win.py" "$f" 1500 'move_card' 'add_comment' 'set_card_custom_field' 'delete_checklist_item' 'toggle_checklist_item' \
    || fail "t11: $f write-deny list is incomplete (AC1 names all five banned operations)"
  python3 "$TMP/win.py" --ci "$f" 400 'unavailable' 'fail-closed' \
    || fail "t11: $f does not state the board-check-unavailable => skip fail-closed rule (AC1, row 4)"
  python3 "$TMP/win.py" --ci "$f" 300 'continue exactly as' '/pipeline-boards' \
    || fail "t11: $f lacks the 'continue exactly as /pipeline-boards' clause — the boards skill must stay the flow authority (AC1)"
  python3 "$TMP/win.py" --ci "$f" 300 'manual' 'ungated' \
    || fail "t11: $f never notes that manual one-off launches are ungated by design (AC1, D11)"
  grep -qF -- '--threshold 0' "$f" || fail "t11: $f does not carry the --threshold 0 forced-through escape note (AC1)"
  grep -qE '^[[:space:]]*agent:[[:space:]]+agent-board-coord$' "$f" \
    || fail "t11: $f frontmatter does not target agent agent-board-coord (AC1)"
  python3 "$TMP/argcheck.py" "$f" \
    || fail "t11: $f puts \$ARGUMENTS inside a !\` shell block or omits it (AC1 — OpenCode expands args BEFORE shell blocks)"
}
if want t11; then
  t11_contract "$CMD_SRC"
  t11_contract "$CMD_GEN"
  ok "t11: C02 AC1 contract strings present in the hourly command source AND generated copy"
fi

# --- t12: manual-path byte-freeze (AC2) ---------------------------------------
if want t12; then
  if ! git diff --quiet "$BASE" -- \
      "$CMD_BASE_SRC" "$CMD_BASE_GEN" "$BOARDS_SRC" "$BOARDS_GEN" "$AS_SRC" "$AS_GEN" 2>/dev/null; then
    git diff --name-only "$BASE" -- "$CMD_BASE_SRC" "$CMD_BASE_GEN" "$BOARDS_SRC" "$BOARDS_GEN" "$AS_SRC" "$AS_GEN" >&2
    fail "t12: a manual-path surface changed vs $BASE — /pipeline-boards, the boards skill and agents-sync references are byte-frozen (C02 AC2, D13)"
  fi
  others=$(git ls-files --others --exclude-standard -- "$BOARDS_SRC" "$BOARDS_GEN" "$AS_SRC" "$AS_GEN" || true)
  [ -z "$others" ] || fail "t12: new untracked file(s) under the byte-frozen manual-path dirs: $others"
  ok "t12: /pipeline-boards, boards skill and agents-sync references byte-unchanged vs $BASE (worktree included)"
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
if want t14; then
  { git diff --name-only "$BASE" || true; git ls-files --others --exclude-standard; } | sort -u >"$TMP/changed.txt"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "$GATE"|tests/*|AGENTS.md|"$RULES_SRC"|"$AGENT_SRC"|"$AGENT_GEN"|\
      "$CMD_SRC"|"$CMD_GEN"|"$FEATURE"/*) : ;;
      *) fail "t14: path outside the ticket's Files in scope: $p (base: $BASE, C02 AC4)" ;;
    esac
  done <"$TMP/changed.txt"
  ok "t14: changed paths limited to the ticket's Files in scope (base: $BASE)"

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

# --- t15: agent body gains exactly one pointer sentence (AC5) -----------------
body_of() { awk 'c>=2{print} /^---$/{c++}' "$1"; }   # skeleton convention from rulesync-surface c16
if want t15; then
  n=0
  for f in "$AGENT_SRC" "$AGENT_GEN"; do
    n=$((n + 1))
    git show "$BASE:$f" >"$TMP/base-$n.md" 2>/dev/null || fail "t15: $f not readable at $BASE"
    body_of "$TMP/base-$n.md" >"$TMP/base-body-$n"
    body_of "$f" >"$TMP/cur-body-$n"
    if diff -q "$TMP/base-body-$n" "$TMP/cur-body-$n" >/dev/null; then
      fail "t15: $f body identical to $BASE — the one-line hourly pointer is missing (C02 AC5 — red-before-C02)"
    fi
    # diff exits 1 on any difference; capture it once instead of re-running
    # it per grep (every `diff | grep` pipeline would otherwise trip pipefail
    # even when grep matches).
    diff "$TMP/base-body-$n" "$TMP/cur-body-$n" >"$TMP/d-$n" || true
    grep '^> ' "$TMP/d-$n" >"$TMP/add-$n" || true
    grep '^< ' "$TMP/d-$n" >"$TMP/rem-$n" || true
    add_n=$(sed 's/^> //' "$TMP/add-$n" | grep -cv '^[[:space:]]*$' || true)
    rem_n=$(sed 's/^< //' "$TMP/rem-$n" | grep -cv '^[[:space:]]*$' || true)
    [ "$add_n" -eq 1 ] \
      || fail "t15: $f body has $add_n non-blank added line(s) — AC5 pins exactly ONE new pointer sentence"
    [ "$rem_n" -le 1 ] \
      || fail "t15: $f body rewrites $rem_n existing line(s) — only a one-sentence append to a single line is allowed"
    if [ "$rem_n" -eq 1 ]; then
      python3 - "$TMP/rem-$n" "$TMP/add-$n" <<'PY' || fail "t15: $f rewrote (not merely extended) a body line — the pointer must be additive so an old sentence cannot vanish"
import sys
r = [ln[2:] for ln in open(sys.argv[1]).read().splitlines() if ln[2:].strip()]
a = [ln[2:] for ln in open(sys.argv[2]).read().splitlines() if ln[2:].strip()]
sys.exit(0 if len(r) == 1 and len(a) == 1 and r[0] in a[0] else 1)
PY
    fi
    grep -qF 'pipeline-boards-hourly' "$TMP/add-$n" \
      || fail "t15: $f pointer sentence does not name pipeline-boards-hourly (the sentence's whole purpose)"
    grep -qiE 'manual' "$TMP/add-$n" \
      || fail "t15: $f pointer sentence never mentions the ungated manual path (C02 task: one sentence covering both)"
    for mech in 'GATE:' '--threshold' 'BOARD CHECK'; do
      ! grep -qF -- "$mech" "$TMP/cur-body-$n" || fail "t15: $f body carries gate mechanics '$mech' — mechanics live in the script/command only (AC5)"
    done
  done
  ok "t15: exactly one additive pointer sentence in both agent body surfaces; no gate mechanics leaked into the body"
fi

# --- t16: rules surface additive (AC6) -----------------------------------------
if want t16; then
  for f in "$RULES_SRC" AGENTS.md; do
    grep -qE '^[[:space:]]*[-*][[:space:]].*`scripts/`' "$f" \
      || fail "t16: $f has no scripts/ bullet — the rules entry is missing (C02 AC6 — red-before-C02)"
    grep -qF 'pipeline-boards-hourly' "$f" \
      || fail "t16: $f never names pipeline-boards-hourly (AC6: agents-section extension)"
  done
  for f in "$RULES_SRC" AGENTS.md; do
    git diff "$BASE" -- "$f" | grep '^-' | grep -v '^---' | grep -v 'agent-board-coord' >"$TMP/rem-lines.txt" || true
    if [ -s "$TMP/rem-lines.txt" ]; then
      cat "$TMP/rem-lines.txt" >&2
      fail "t16: $f deletes a line unrelated to the agent-board-coord sentence — the rules surface is additive-only (AC6)"
    fi
  done
  ok "t16: scripts/ bullet + hourly-variant line in rules source AND AGENTS.md; nothing removed beyond the allowed sentence extension"
fi

# --- t17: D13 permission byte-pin — agent frontmatter unchanged, dev_boards* ---
if want t17; then
  n=0
  for f in "$AGENT_SRC" "$AGENT_GEN"; do
    n=$((n + 1))
    git show "$BASE:$f" >"$TMP/base-fm-$n.md" 2>/dev/null || fail "t17: $f not readable at $BASE"
    sed -n '1,/^---$/p' "$TMP/base-fm-$n.md" | tail -n +2 >"$TMP/fm-base-$n"
    sed -n '1,/^---$/p' "$f" | tail -n +2 >"$TMP/fm-cur-$n"
    cmp -s "$TMP/fm-base-$n" "$TMP/fm-cur-$n" \
      || fail "t17: frontmatter of $f drifted from $BASE — D13 pins ZERO permission changes; the gate rides the !-block, not permissions"
  done
  python3 - "$AGENT_GEN" <<'PY' || fail "t17: generated agent permission block violates the D13 byte-pin shape"
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no YAML frontmatter"
perms = (yaml.safe_load(m.group(1)) or {}).get("permissions") or []
errs = []
db = [p for p in perms if p.get("action") == "dev_boards*"]
if len(db) != 1 or db[0].get("effect") != "allow" or db[0].get("resource") != "*":
    errs.append("dev_boards* must appear EXACTLY once as allow '*' — the pre-existing single allow is the whole board surface (D13)")
if any(p.get("action") == "dev*" for p in perms):
    errs.append("broad dev* allow appeared — C02 adds no permission surface at all (D13)")
if any(p.get("action") == "shell" for p in perms):
    errs.append("a shell permission row appeared — the scoped shell allow was CANCELLED by D13 (the !-block runs outside tool permissions)")
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in perms):
    errs.append("question allow lost (repo hard rule)")
deny_at = next((i for i, p in enumerate(perms) if p.get("action") == "*" and p.get("resource") == "*" and p.get("effect") == "deny"), None)
db_at = perms.index(db[0]) if db else None
if deny_at is None or db_at is None or db_at < deny_at:
    errs.append("the dev_boards allow no longer follows the leading deny-all (last-match-wins would deny it)")
subs = sorted(p.get("resource") for p in perms if p.get("action") == "subagent" and p.get("effect") == "allow")
want_subs = sorted(["agent-plan", "agent-test", "agent-dev", "agent-review", "agent-research"])
if subs != want_subs:
    errs.append(f"subagent allows are {subs}, want exactly {want_subs}")
edits = sorted(p.get("resource") for p in perms if p.get("action") == "edit")
want_edits = sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"])
if edits != want_edits:
    errs.append(f"edit allows are {edits}, want ONLY the three plan-state files")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
  ok "t17: agent-board-coord frontmatter byte-identical to $BASE (source + generated) and the single narrow dev_boards* allow shape intact (D13)"
fi

printf 'PASS: agent-board-coord gate contract checks (%d ok)\n' "$checks"
