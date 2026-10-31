#!/usr/bin/env bash
# No-op marker cross-surface contract suite
# (2026/2026-10-chore-board-tick-cleanup, C02).
#
# Pins the marker contract's exactly-two homes and the docs-only truth task:
#   N1  reader side — question-notify carries the conjunction (marker key,
#       scheduled discriminator read, suppression audit line, exported seam)
#   N2  writer authority — the boards skill's "No-op marker" subsection with
#       the contract tokens, and BOTH no-op exits citing it (Card pickup step 4,
#       Parallel-pipeline-loops claim-cap stop)
#   N3  single-home grep counts — pipelineNoop exists in the skill pair + the
#       plugin only (no third normative copy, C02 AC4); the `"scheduled"` code
#       read is the plugin's alone (the skill cites, never re-derives); the
#       gate command stays marker-blind (OQ5: GATE SKIP/LIVE never mark)
#   N4  scheduler docs truth (AC6) — the loop file and AGENTS.md/rules stop
#       claiming "shipped disabled" as current fact; the live OpenChamber state
#       and the human-owned hygiene are named; the silence rule rides the
#       generated sentence. The frontmatter keeps exactly ONE enabled: row;
#       its value is settled `true` since main 080c9878a (the owner's own
#       toggle — OQ10 bounds who flips it, not what the bytes may pin).
#   N5  RESULT posture intact — the no-op ends still read NEEDS_INFO (C02:
#       "RESULT stays as today"); the suppression is an ALERT-scope change,
#       never a status change.
#
# Red posture: N1-N4 name not-yet-landed C02 text (plugin predicate, skill
# subsection, truth sentences) — red before dev, HOLD after. N5 is green now
# and must stay green (the chunk edits these very passages).
#
# Offline-deterministic text pins over the trees; no server, no session. The
# behavior matrix lives in tests/opencode/question-notify.test.ts T9/T10; the
# scheduled-side end-to-end leg is C03's LF6 runbook (unit arms are this
# chunk's proof surface per OQ-N2).
#
# Usage:
#   bash tests/noop-marker/surface.sh            # N1..N5
#   bash tests/noop-marker/surface.sh N2         # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

QN=".opencode/plugin/question-notify/index.ts"
BOARD_SRC=".rulesync/skills/boards/SKILL.md"
BOARD_GEN=".opencode/skills/boards/SKILL.md"
LOOP=".agents/loops/pipeline-worker.md"
RULES_SRC=".rulesync/rules/overview.md"
HOURLY=".rulesync/commands/pipeline-boards-hourly.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/noop-marker-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["n$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^n[1-5]$ ]] || fail "unknown check id '$a' (expected N1..N5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

cat >"$TMP/win.py" <<'PY'
# Co-location window (sibling-suite convention): needles must read as ONE
# passage; --ci folds case so prose pins survive dev's register without
# pinning sentences.
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

cat >"$TMP/sectwin.py" <<'PY'
# Window scoped to one heading's section (coord-inwork convention): the marker
# subsection's contract tokens must read as ITS passage — section-scoped to the
# next heading, so a token smuggled into later prose does not satisfy the pin.
import re, sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span, title = argv[0], int(argv[1]), argv[2]
needles = [n.lower() for n in argv[3:]] if ci else argv[3:]
text = open(path).read()
m = re.search(r'(?ms)^#+[^\n]*' + re.escape(title) + r'[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print(f'section "{title}" not found'); sys.exit(1)
body = m.group(1).lower() if ci else m.group(1)
pts = []
for n in needles:
    i = body.find(n)
    if i < 0:
        print(f'needle "{n}" not in section "{title}"'); sys.exit(1)
    pts.append(i)
if max(pts) - min(pts) > span:
    print(f'section "{title}" needles span {max(pts) - min(pts)} > {span} — scattered'); sys.exit(1)
PY

# --- N1: reader side in the plugin (C02 Tasks, OQ2/OQ4) ------------------------
if want n1; then
  for needle in 'pipelineNoop' 'noWorkSuppressed' '== "scheduled"' 'suppressed no-work finished push' 'openchamber.kind'; do
    grep -qF -- "$needle" "$QN" \
      || fail "N1[C02 AC2]: $QN lacks '$needle' — the reader conjunction/audit surface has not landed (red before C02 dev)"
  done
  # The suppression line must carry the plugin's log prefix (LF6's PASS shape
  # greps for exactly this line in instance stderr).
  grep -qE '\[question-notify\] suppressed no-work finished push' "$QN" \
    || fail "N1[C02 AC2/LF6]: no stderr line in the shipped form '[question-notify] suppressed no-work finished push <sessionID>' — the live-fire leg's evidence handle"
  ok "N1[C02 AC2]: question-notify carries the seam name, the conjunction inputs, and the LF6-pinned audit line"
fi

# --- N2: writer authority — the boards-skill subsection + both exit cites -------
if want n2; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "N2: $f missing (harness fault)"
    grep -qE '^#{3,4}[[:space:]].*No-op marker' "$f" \
      || fail "N2[C02 AC3]: $f has no 'No-op marker' subsection heading (red before C02 dev — the writer authority does not exist yet)"
    # Contract tokens (C02.md Marker contract bullets): shape, both reasons,
    # rename-based self-id (OQ3), the pipeline-kickoff recipe citation, and
    # the one-sentence reader scope (OQ4). Span generous — the subsection IS
    # several sentences, but the tokens belong to it, nowhere in the file.
    python3 "$TMP/sectwin.py" --ci "$f" 1400 'No-op marker' \
      'pipelineNoop' 'no-cards' 'no-claimable-cards' 'session_rename' 'pipeline-kickoff' 'scheduled' \
      || fail "N2[C02 AC3]: $f's No-op marker subsection does not carry the contract tokens (marker key, both reason values, rename self-id, kickoff citation, scheduled-scope line) in its own passage"
    # Both no-op exits reference it (final step before the clean end).
    python3 "$TMP/win.py" --ci "$f" 900 'Nothing anywhere' 'no-op marker' \
      || fail "N2[C02 Tasks]: Card pickup step 4 ('Nothing anywhere') does not cite the No-op marker step (red before C02 dev)"
    python3 "$TMP/win.py" --ci "$f" 900 'no eligible work' 'no-op marker' \
      || fail "N2[C02 Tasks]: the Parallel-pipeline-loops claim-cap stop ('no eligible work') does not cite the No-op marker step (red before C02 dev)"
  done
  ok "N2[C02 AC3]: boards pair carries the marker subsection with its tokens; both no-op exits cite it"
fi

# --- N3: exactly-two homes, single reader, marker-blind gate (C02 AC4) ----------
if want n3; then
  [ "$(grep -c 'pipelineNoop' "$BOARD_SRC")" -eq 1 ] \
    || fail "N3[C02 AC4]: $BOARD_SRC mentions pipelineNoop $(grep -c 'pipelineNoop' "$BOARD_SRC") times, want exactly 1 (the key literal lives once: the shape line; the exits cite the subsection, not the key)"
  [ "$(grep -c 'pipelineNoop' "$BOARD_GEN")" -eq 1 ] \
    || fail "N3[C02 AC4]: the generated boards mirror must echo the key exactly once"
  [ "$(grep -c 'pipelineNoop' "$QN")" -ge 1 ] \
    || fail "N3[C02 AC4]: the reader predicate carries the pipelineNoop key (>=1)"
  strays=$(grep -rl 'pipelineNoop' .rulesync .opencode skills 2>/dev/null \
           | grep -v -x -e "$BOARD_SRC" -e "$BOARD_GEN" -e "$QN" || true)
  [ -z "$strays" ] || { printf '%s\n' "$strays" >&2; fail "N3[C02 AC4]: pipelineNoop found outside the two normative homes — a third copy of the marker contract (DECISIONS convention: anything else cites, never restates)"; }
  # The scheduled code-read belongs to the reader alone: a == "scheduled"
  # comparison outside the plugin would re-derive suppression authority.
  kind_reads=$(grep -rlF '== "scheduled"' .rulesync .opencode skills 2>/dev/null | grep -v -x "$QN" || true)
  [ -z "$kind_reads" ] || { printf '%s\n' "$kind_reads" >&2; fail "N3[C02 AC4]: the scheduled discriminator comparison exists outside the reader — the skill cites the discriminator, it never re-derives it"; }
  # OQ5: the gate command's SKIP/LIVE branches mark NOTHING (fail-closed
  # minimalism forbids the write there) — the command must stay marker-blind.
  grep -qF 'pipelineNoop' "$HOURLY" \
    && fail "N3[C02 OQ5]: $HOURLY restates the marker — the gate paths stay uncovered and the contract keeps its two homes"
  ok "N3[C02 AC4]: marker key pinned to skill(1)+mirror(1)+plugin; scheduled comparison plugin-only; hourly command stays marker-blind"
fi

# --- N4: scheduler docs truth (AC6, OQ10 docs-only ruling) ----------------------
if want n4; then
  # Negative arms first: the stale PRESENT-TENSE claims leave. The frontmatter
  # carries exactly one enabled: row, and its value is the settled one: main
  # 080c9878a recorded the human exercising the OQ10-owned toggle (false ->
  # true, 2026-10-30). The permanent duty is the single authoritative row —
  # a second row or a silent flip-back mid-file reddens here, while the value
  # itself tracks landed state and a future deliberate flip re-pins the
  # settled-value arm rather than deleting it.
  grep -qF 'Shipped DISABLED (D9/Q5)' "$LOOP" \
    && fail "N4[C02 AC6]: $LOOP still asserts 'Shipped DISABLED (D9/Q5)' as current fact — 2026-10-29 OpenChamber state contradicts it (RESEARCH W2 F5)"
  grep -qF 'shipped disabled until the cf-76 live smoke passes' "$RULES_SRC" \
    && fail "N4[C02 AC6]: $RULES_SRC still claims the loop ships disabled until the live smoke as current fact — reconcile to the 2026-10-29 state (AGENTS.md regenerates from it)"
  grep -qF 'shipped disabled until the cf-76 live smoke passes' AGENTS.md \
    && fail "N4[C02 AC6]: AGENTS.md still carries the stale fallback-entry sentence — regenerate from the rules source"
  [ "$(grep -cE '^enabled: (true|false)$' "$LOOP")" -eq 1 ] \
    || fail "N4[C02 OQ10]: $LOOP does not carry exactly one frontmatter enabled: row — the repo toggle must be a single authoritative line"
  grep -qE '^enabled: true$' "$LOOP" \
    || fail "N4[settled 080c9878a]: $LOOP frontmatter is not enabled: true — the human-owned flip landed on main; a future deliberate flip re-pins this arm to the new settled value, it is never deleted"
  # Positive arms: the verified live state is named, the hygiene is human-owned,
  # and the silence rule rides the generated sentence.
  python3 "$TMP/win.py" --ci "$LOOP" 900 'openchamber' 'enabled' '2026-10-29' \
    || fail "N4[C02 AC6]: $LOOP does not state the 2026-10-29 OpenChamber live state (scheduledTasks pipeline-worker enabled at cron 0 * * * *) in its comment block — red before C02 dev"
  python3 "$TMP/win.py" --ci "$LOOP" 500 'hourly pipeline call' 'human-owned' \
    || fail "N4[C02 AC6]: the legacy 'Hourly Pipeline call' daily task is not named as human-owned hygiene in $LOOP"
  for f in AGENTS.md "$RULES_SRC"; do
    python3 "$TMP/win.py" --ci "$f" 400 'scheduled' 'no-work' \
      || fail "N4[C02 Tasks]: $f lacks the silence-rule clause (a top-level scheduled-finished push happens unless the coord marked the session no-work) — red before C02 dev"
  done
  ok "N4[C02 AC6]: stale current-tense claims gone, one authoritative settled enabled: row, live state + human-owned hygiene + silence clause recorded"
fi

# --- N5: RESULT posture unchanged (C02: "RESULT stays as today") ----------------
if want n5; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 700 'nothing anywhere' 'needs_info' \
      || fail "N5[C02]: $f's empty-board exit no longer ends RESULT NEEDS_INFO — suppression changes WHO GETS PAGED, never the run's status"
    python3 "$TMP/win.py" --ci "$f" 900 'no eligible work' 'cleanly' \
      || fail "N5[C02]: $f's claim-cap stop lost its clean-end wording (HOLD — the marker rides BEFORE the end, it does not replace it)"
  done
  ok "N5[C02]: both no-op exits still end NEEDS_INFO + clean stops (alert-scope change only)"
fi

printf 'PASS: no-op marker contract checks (%d ok)\n' "$checks"
