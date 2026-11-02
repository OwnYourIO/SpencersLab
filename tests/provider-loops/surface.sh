#!/usr/bin/env bash
# Provider loop-tasks contract — pipeline-worker (API) + pipeline-worker-local
# (2026/2026-10-cf-90-feat-board-coord-improvements, C04).
#
# Pins chunks/C04.md "## Tests" t1-t7 + AC1/AC2/AC4/AC5/AC6: the loop-file
# pair that implements the card's Provider: label pattern — the API task's
# scheduled walk takes ONLY explicit Provider: API cards (the final-approval
# ruling; unlabeled reaches it only via a user-initiated manual run), the
# Local task is the PLANNED steady-state taker of Provider: Local + unlabeled
# cards, and BOTH bodies carry the ask-before-routing + human-labeling
# instruction. File edits only — OpenChamber approvals/toggles are human
# hand-offs (DECISIONS.md), never operationed here. AC trace: t1[AC1+AC2
# frontmatter shapes] t2[AC1+AC2 provider/ask sentences both bodies] t3[AC2
# Local model pin, confirmed in the batched round] t4[DECISIONS staggered
# hourly schedules] t5[AC2 boards-skill citation — the single authority for
# the walk] t6[AC4 gate script untouched + gate contract passes] t7[AC1/AC2
# negative posture pins — the superseded "claimable by both"/"whichever
# claims first" wording may not survive].
#
# Red posture: t1/t2/t3/t4/t5/t7 are designed-red until C04 dev lands the two
# loop bodies (pipeline-worker-local.md absent entirely; the API body carries
# no provider sentence yet — its frontmatter arms go green on day one and
# HOLD). The HOLD arms are deliberate: the frontmatter of pipeline-worker.md
# is byte-stable through C04 (AC1).
#
# Selection / known-baseline note (cf-90 FRICTION + DECISIONS): t6 runs
# tests/agent-board-coord/gate.sh as an ID SUBSET excluding t17 — t17 (like
# coord-inwork i4, session-origin s4, kickoff-branch m4, wekan-mcp
# create-list t2) is red at pristine main HEAD from the pre-existing
# warm-location permissions drift, tracked on its own Review card OUTSIDE
# this ticket. cf-90 gates must never read that red as theirs, and no check
# here runs those suites whole.
#
# Offline-deterministic: text + frontmatter pins over the repo tree; the
# gate subset runs on mkfifo-style temp session fixtures inside gate.sh — no
# live board, no OpenChamber, no network.
#
# Usage:
#   bash tests/provider-loops/surface.sh            # t1..t7
#   bash tests/provider-loops/surface.sh t2 t7      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

API=".agents/loops/pipeline-worker.md"
LOCAL=".agents/loops/pipeline-worker-local.md"
GATE_SCRIPT="scripts/agent-board-coord-gate.sh"
GATE_SUITE="tests/agent-board-coord/gate.sh"
BASE="${CHUNK_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/provider-loops-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-7]$ ]] || fail "unknown check id '$a' (expected t1..t7)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

cat >"$TMP/win.py" <<'PY'
# Co-location window (sibling-suite convention): needles read as ONE passage
# of the loop body — the whole body becomes the OpenChamber prompt, so a
# scattered contract is a broken prompt. --ci folds case (prose register).
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

fm_check() { # fm_check <file> <expect-kv-lines...> — frontmatter keys exactly
  # once each + the five-OpenChamber-recognized-key set (name/schedule/
  # enabled/model/agent; loops.js ignores anything else, so the bodies stay
  # clean and the set stays closed).
  local f="$1"; shift
  [ -f "$f" ] || return 97
  python3 - "$f" "$@" <<'PY'
import re, sys, yaml
path = sys.argv[1]; expect = sys.argv[2:]
text = open(path).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
keys = list(fm.keys())
assert sorted(keys) == sorted(["name", "schedule", "enabled", "model", "agent"]), \
    f"frontmatter keys {keys} != the five OpenChamber loop keys (a stray key is silently ignored by the syncer — drift the file cannot show)"
for pair in expect:
    k, _, v = pair.partition("=")
    # str(...).lower(): yaml parses enabled: true as the BOOL, and a
    # byte-exact compare would false-redden the one bool-valued key.
    got = str(fm.get(k)).lower()
    assert got == v.lower(), f"{k}: {got!r} != pinned {v!r}"
# line-level single-occurrence duty: yaml would silently take the LAST
# duplicate, so count the raw rows too (the noop-marker N4 enabled:-row rule).
body = text.split("---")[1]
for k in ("name", "schedule", "enabled", "model", "agent"):
    c = len(re.findall(rf"^{k}:", body, re.M))
    assert c == 1, f"{k}: appears {c} times in the frontmatter, want exactly one row"
PY
}

# --- t1: both loop files exist; frontmatter shapes (AC1, AC2) -------------------
if want t1; then
  [ -f "$API" ] || fail "t1[C04]: $API missing (harness fault)"
  [ -f "$LOCAL" ] \
    || fail "t1[C04 AC2]: $LOCAL does not exist yet — the duplicated Provider: Local loop file is C04's second task (designed red before C04 dev; file edits ONLY, the task itself is approved by the human in OpenChamber)"
  fm_check "$API" \
    "name=pipeline-worker" "schedule=0 * * * *" "enabled=true" \
    "model=openrouter/qwen/qwen3.8-flash" "agent=agent-board-coord" \
    || fail "t1[C04 AC1]: $API frontmatter drifted — byte-stable except comments is the contract (model openrouter/qwen/qwen3.8-flash, hourly :00, enabled true, agent agent-board-coord)"
  fm_check "$LOCAL" \
    "name=pipeline-worker-local" "schedule=30 * * * *" "enabled=true" \
    "model=gpu-ai/qwen3.8-flash-next-strata" "agent=agent-board-coord" \
    || fail "t1[C04 AC2]: $LOCAL frontmatter violates the DECISIONS-pinned shape (name pipeline-worker-local, hourly :30, enabled true — the shipped posture, never 'false to be safe' — model gpu-ai/qwen3.8-flash-next-strata, agent agent-board-coord)"
  ok "t1[C04 AC1+AC2]: both loop files parse with exactly the five loop keys once each; API frontmatter byte-stable, Local per the confirmed pinned shape"
fi

# --- t2: provider sentences + the ask instruction in BOTH bodies (AC1, AC2) -----
if want t2; then
  [ -f "$LOCAL" ] || fail "t2[C04 AC2]: $LOCAL missing (red before C04 dev — same reason as t1)"
  # API body: the scheduled walk takes ONLY explicit Provider: API cards…
  python3 "$TMP/win.py" --ci "$API" 700 'provider: api' 'only' \
    || fail "t2[C04 AC1]: $API body never states the scheduled walk takes ONLY Provider: API-labeled cards (final-approval ruling — the API task is not the unlabeled taker)"
  # …and never takes unlabeled ones…
  python3 "$TMP/win.py" --ci "$API" 900 'unlabeled' 'never' \
    || fail "t2[C04 AC1]: $API body lacks the unlabeled-never-taken clause for its scheduled walk"
  # …while carrying the ask instruction for manual runs pointed at unlabeled.
  python3 "$TMP/win.py" --ci "$API" 900 'ask' 'routing' \
    || fail "t2[C04 AC1]: $API body does not carry the ask-before-routing instruction for a MANUAL run on an unlabeled card"
  python3 "$TMP/win.py" --ci "$API" 1200 'ask' 'label' \
    || fail "t2[C04 AC1]: the API ask sentence omits the human-labeling request (labels stay human-owned — the ask ends with the human applying the Provider: label)"
  # Local body: planned taker of Provider: Local + unlabeled, with the ask.
  python3 "$TMP/win.py" --ci "$LOCAL" 900 'provider: local' 'unlabeled' \
    || fail "t2[C04 AC2]: $LOCAL body never names the Provider: Local + unlabeled pickup pool"
  python3 "$TMP/win.py" --ci "$LOCAL" 700 'planned' 'taker' \
    || fail "t2[C04 AC2]: $LOCAL body omits the PLANNED steady-state taker wording — the unlabeled pool has an owner by intent, not by lock race"
  python3 "$TMP/win.py" --ci "$LOCAL" 900 'ask' 'which provider' \
    || fail "t2[C04 AC2]: $LOCAL body omits the ask-before-routing sentence (which provider applies BEFORE Model(s)/provider routing is consumed)"
  python3 "$TMP/win.py" --ci "$LOCAL" 1200 'apply' 'label' \
    || fail "t2[C04 AC2]: $LOCAL body omits the human-labeling request"
  ok "t2[C04 AC1+AC2]: API walk = Provider: API only + unlabeled-never + manual-run ask; Local = Provider: Local AND unlabeled planned taker + ask-before-routing + human-labeling request"
fi

# --- t3: the Local model line, pinned exactly (AC2, batched-round CONFIRMED) ----
if want t3; then
  [ -f "$LOCAL" ] || fail "t3[C04 AC2]: $LOCAL missing (red before C04 dev)"
  grep -qE '^model: gpu-ai/qwen3\.8-flash-next-strata$' "$LOCAL" \
    || fail "t3[C04 AC2]: the Local model line is not exactly gpu-ai/qwen3.8-flash-next-strata — confirmed in the batched round 2026-10-31 (OQ3); the catalog churns, so the pin moves only by a fresh user ruling"
  ok "t3[C04 AC2]: Local initial model pinned to gpu-ai/qwen3.8-flash-next-strata"
fi

# --- t4: schedules — both hourly, staggered :00 / :30 (DECISIONS) --------------
if want t4; then
  [ -f "$LOCAL" ] || fail "t4[C04]: $LOCAL missing (red before C04 dev)"
  grep -qE '^schedule: 0 \* \* \* \*$' "$API" \
    || fail "t4[C04 AC1]: the API task's hourly :00 schedule moved — the gate + stale-clock math (2 h window) assume hourly"
  grep -qE '^schedule: 30 \* \* \* \*$' "$LOCAL" \
    || fail "t4[C04 DECISIONS]: the Local task is not staggered to :30 — same cron as the API task would stack two claims per tick"
  ok "t4[C04]: schedules staggered hourly — API 0 * * * *, Local 30 * * * *"
fi

# --- t5: both bodies CITE the boards skill's Provider filtering (single home) --
if want t5; then
  for f in "$API" "$LOCAL"; do
    [ -f "$f" ] || fail "t5[C04]: $f missing (red before C04 dev)"
    python3 "$TMP/win.py" --ci "$f" 600 'provider filtering' 'boards' \
      || fail "t5[C04 AC2]: $f never cites the boards skill's Provider filtering as the authority — the pickup-filter semantics live in ONE place (C03 owns them); the loop bodies name, never restate"
  done
  ok "t5[C04 AC2]: both loop bodies cite the boards skill Provider filtering section"
fi

# --- t6: the gate script is UNTOUCHED, and its contract still passes (AC4) -----
if want t6; then
  git rev-parse --verify "$BASE" >/dev/null 2>&1 \
    || fail "harness: base ref '$BASE' does not resolve (CHUNK_BASE=<ref>)"
  git diff --quiet "$BASE" -- "$GATE_SCRIPT" \
    || fail "t6[C04 AC4]: $GATE_SCRIPT changed since $BASE — both tasks run agent-board-coord and the gate counts the three board-coord names regardless of provider, so there is NOTHING to change (verified at planning; DECISIONS records the rationale)"
  # gate ids t1..t20 MINUS t17: t17 is the known pre-existing red at main HEAD
  # (warm-location permissions drift — a Review card outside cf-90), excluded
  # from this ticket's gates per the header note; everything else must pass.
  gate_ids=""
  for i in $(seq 1 20); do
    [ "$i" -eq 17 ] && continue
    gate_ids="$gate_ids t$i"
  done
  bash "$GATE_SUITE" $gate_ids >"$TMP/gate.log" 2>&1 \
    || { tail -n 12 "$TMP/gate.log" >&2; fail "t6[C04 AC4]: the gate suite (ids excluding the known-red t17) is not green — log above"; }
  ok "t6[C04 AC4]: gate script byte-unchanged vs $BASE and the gate contract passes (t1..t20 minus the pre-existing t17)"
fi

# --- t7: NEGATIVE pins — the superseded unlabeled posture may not survive -------
if want t7; then
  strays=$(grep -rinE 'claimable by both|whichever claims (the )?first|either may take' .agents/loops/ 2>/dev/null || true)
  [ -z "$strays" ] || { printf '%s\n' "$strays" >&2; fail "t7[C04 AC1]: the loop files carry the batched-round 'either may take / whichever claims first' shape — SUPERSEDED by the final-approval ruling (only Local plans on unlabeled pickup)"; }
  [ -f "$API" ] || fail "t7: $API missing (harness fault)"
  if ! python3 - "$API" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
body = re.split(r'^---\n.*?\n---\n', text, flags=re.S)[1] if text.startswith("---") else text
bad = []
for line in body.splitlines():
    if "unlabeled" in line.lower() and not re.search(r"(?i)never|not |no |only|manual|ask|except", line):
        bad.append(line.strip())
if bad:
    print("API-body lines that take unlabeled cards WITHOUT a never/manual/ask qualifier:")
    print("\n".join(bad))
    sys.exit(1)
print("clean")
PY
  then fail "t7[C04 AC1]: an affirmative API-walk-takes-unlabeled sentence survives above — the scheduled API walk NEVER takes them (manual runs only, with the ask)"; fi
  ok "t7[C04]: negatives hold — no 'both may claim' wording anywhere in the loop pair, no affirmative API-takes-unlabeled sentence"
fi

printf 'PASS: provider loop-tasks contract checks (%d ok)\n' "$checks"
