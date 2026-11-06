#!/usr/bin/env bash
# Provider loop-tasks contract — the ONE scheduled runner (cf-90 C04 pair,
# collapsed to a single loop file by 2026/2026-11-cf-106-feat-coord-fixes C10).
#
# Pins chunks/C10.md "## Tests" + AC1-AC7 of that chunk: exactly one file under
# .agents/loops/, its frontmatter carrying only the keys OpenChamber recognizes
# with the owner-ruled model literal, and a body that (a) runs one Parallel
# pipeline loops iteration, (b) serves BOTH Provider flavors and routes from the
# card's Provider: label, (c) expects the structural board-context block plus the
# claimed card's details on the claim answer, and (d) cites the marked+archived
# no-work exit. Provider stops being a scheduler split and becomes per-card
# routing inside the run; the gate contract stays byte-unchanged under it.
# File edits only — OpenChamber approvals/toggles/fingerprint re-approvals are
# human hand-offs (USER-owned step 4), never operationed here.
#
# AC trace: t1[AC1 single file + frontmatter keys/values] t2[AC2 body: both
# flavors, ask-on-unlabeled, preload, no-work exit, no slash command] t3[AC6 the
# model pin re-pinned to the C10 literal, convention comment kept] t4[AC1 one
# task — the retired pair and its staggered schedule may not come back] t5[AC3
# boards-skill citation of the rewritten Provider filtering section] t6[AC5 gate
# script untouched + gate subset green] t7[AC3 negative posture — no
# current-state text still claims two tasks or an API-only scheduled walk] plus
# t8[AC4 single-file sweep: the deleted file's name lives only in records].
#
# Red posture: t1/t2/t3/t7/t8 are designed-red until C10 dev lands the single
# body, the model flip and the file deletion. t6 is the plan-time red that
# C01's scope admits clear; it stays green through C10 (the gate is untouched).
#
# Selection / known-baseline note (cf-90 FRICTION + DECISIONS): t6 runs
# tests/agent-board-coord/gate.sh as an ID SUBSET excluding t17 — t17 (like
# coord-inwork i4, session-origin s4, kickoff-branch m4, wekan-mcp
# create-list t2) is red at pristine main HEAD from the pre-existing
# warm-location permissions drift, tracked on its own Review card OUTSIDE
# this ticket. cf-90/cf-106 gates must never read that red as theirs, and no
# check here runs those suites whole.
#
# Offline-deterministic: text + frontmatter pins over the repo tree; the gate
# subset runs on mkfifo-style temp session fixtures inside gate.sh — no live
# board, no OpenChamber, no network.
#
# Usage:
#   bash tests/provider-loops/surface.sh            # t1..t8
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
  for i in 1 2 3 4 5 6 7 8; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-8]$ ]] || fail "unknown check id '$a' (expected t1..t8)"
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

cat >"$TMP/body.py" <<'PY'
# The body as OpenChamber would send it: frontmatter and HTML comment block out,
# lines joined — so a "no slash command" or "names both flavors" pin reads what
# the session actually receives, not the file's documentation.
import re, sys
text = open(sys.argv[1]).read()
body = re.split(r"^---\n.*?\n---\n", text, flags=re.S)[1] if text.startswith("---") else text
prose = re.sub(r"<!--[\s\S]*?-->", "", body)
print(" ".join(l.strip() for l in prose.splitlines() if l.strip()))
PY

fm_check() { # fm_check <file> <expect-kv-lines...> — frontmatter keys exactly
  # once each, drawn from the OpenChamber-recognized set (name/schedule/
  # enabled/model/agent, plus the optional timezone row; loops.js ignores
  # anything else, so a stray key is drift the file cannot show).
  local f="$1"; shift
  [ -f "$f" ] || return 97
  python3 - "$f" "$@" <<'PY'
import re, sys, yaml
path = sys.argv[1]; expect = sys.argv[2:]
text = open(path).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
recognized = ["name", "schedule", "enabled", "model", "agent", "timezone"]
stray = [k for k in fm if k not in recognized]
assert not stray, f"frontmatter keys {list(fm)} include {stray} — unrecognized keys are silently ignored by the syncer"
missing = [k for k in ("name", "schedule", "enabled", "model", "agent") if k not in fm]
assert not missing, f"frontmatter lost the decided fields {missing}"
for pair in expect:
    k, _, v = pair.partition("=")
    # str(...).lower(): yaml parses enabled: true as the BOOL, and a
    # byte-exact compare would false-redden the one bool-valued key.
    got = str(fm.get(k)).lower()
    assert got == v.lower(), f"{k}: {got!r} != pinned {v!r}"
# line-level single-occurrence duty: yaml would silently take the LAST
# duplicate, so count the raw rows too (the noop-marker N4 enabled:-row rule).
fmtext = text.split("---")[1]
for k in ("name", "schedule", "enabled", "model", "agent"):
    c = len(re.findall(rf"^{k}:", fmtext, re.M))
    assert c == 1, f"{k}: appears {c} times in the frontmatter, want exactly one row"
PY
}

# --- t1: exactly one loop file, frontmatter shape (AC1) ------------------------
if want t1; then
  [ -f "$API" ] || fail "t1[cf-106 C10]: $API missing (harness fault)"
  if [ -e "$LOCAL" ]; then
    fail "t1[cf-106 C10 AC1]: $LOCAL still exists — C10 collapses the hourly pair to ONE scheduled runner (git rm the file; the live OpenChamber task's retirement stays the owner's step)"
  fi
  # The model literal follows the loop-file bytes — the single authority
  # (OpenChamber syncs from the main checkout); owner ruling OQ-14 of this
  # ticket (2026-11-03) moved the runner to the Dense/local default,
  # superseding cf-86's 652ba904c flash-next-strata pin.
  fm_check "$API" \
    "name=pipeline-worker" "schedule=0 * * * *" "enabled=true" \
    "model=gpu-ai/qwen3.8-27b-q4" "agent=agent-board-coord" \
    || fail "t1[cf-106 C10 AC1]: $API frontmatter is not the single-runner shape — one schedule, enabled true, agent agent-board-coord, model gpu-ai/qwen3.8-27b-q4 (red until C10 flips the literal)"
  ok "t1[cf-106 C10 AC1]: one loop file, exactly the recognized keys once each, agent agent-board-coord, model gpu-ai/qwen3.8-27b-q4"
fi

# --- t2: the single body carries the C10 contract (AC2) ------------------------
if want t2; then
  [ -f "$API" ] || fail "t2[cf-106 C10]: $API missing (harness fault)"
  python3 "$TMP/body.py" "$API" >"$TMP/body.txt" || fail "t2: body extraction failed (harness fault)"
  # (a) one iteration — the worker sentence, unchanged in its core.
  python3 "$TMP/win.py" --ci "$TMP/body.txt" 400 'one parallel pipeline loops iteration' \
    || fail "t2[cf-106 C10 AC2]: the body no longer orders exactly ONE Parallel pipeline loops iteration (D30 posture)"
  # (b) one task, both Provider flavors, routing from the card's label.
  python3 "$TMP/win.py" --ci "$TMP/body.txt" 900 'provider: api' 'provider: local' \
    || fail "t2[cf-106 C10 AC2]: the body never names BOTH Provider flavors — this single task serves both and the run routes from the card's Provider: label (C10 task (b))"
  python3 "$TMP/win.py" --ci "$TMP/body.txt" 900 'label' 'rout' \
    || fail "t2[cf-106 C10 AC2]: the body does not say provider rides the card's label (per-card routing, not a scheduler split)"
  # the ask survives the collapse: unlabeled cards still trigger one kickoff ask
  python3 "$TMP/win.py" --ci "$TMP/body.txt" 900 'unlabeled' 'ask' \
    || fail "t2[cf-106 C10 AC2]: the body dropped the ask-on-unlabeled rule — that ask is the only place a human learns a card needs a Provider: label (C10 Notes)"
  # (c) preload expectation: the structural ids and the claimed card arrive early.
  python3 "$TMP/win.py" --ci "$TMP/body.txt" 900 'board-context' 'card' \
    || fail "t2[cf-106 C10 AC2]: the body never names the board-context block plus the claimed card's details — the whole point of the preload is that the first turn does not spend round-trips (C06/C07)"
  # (d) the no-work exit, cited not restated.
  python3 "$TMP/win.py" --ci "$TMP/body.txt" 500 'no-work' 'archiv' \
    || fail "t2[cf-106 C10 AC2]: the body omits the marked+archived no-work exit citation (C03b's contract — cite it, do not restate it)"
  if grep -qE '(^|[[:space:]])/pipeline-[a-z-]+' "$TMP/body.txt"; then
    fail "t2[cf-106 C10 AC2]: a slash command sits in the body text — dispatch from loop text is unproven on v2.1.4 (D30), the body stays plain text"
  fi
  ok "t2[cf-106 C10 AC2]: one body orders one iteration, names both Provider flavors + label routing + the unlabeled ask, expects the board-context/card preload, cites the marked+archived no-work exit, and stays slash-free"
fi

# --- t3: the model line, pinned exactly, convention comment intact (AC6) -------
# The catalog churns, so this pin moves ONLY by a fresh user ruling; that
# convention comment is part of the contract — C10's re-pin cites the cf-106
# OQ-14 ruling as its authority, so a silent literal change reddens here.
if want t3; then
  grep -qE '^model: gpu-ai/qwen3\.8-27b-q4$' "$API" \
    || fail "t3[cf-106 C10 AC6]: the runner's model line is not exactly gpu-ai/qwen3.8-27b-q4 — owner ruling OQ-14 (2026-11-03) sets the Dense/local default for the scheduled runner; the catalog churns, so the pin moves only by a fresh user ruling"
  grep -E '^[[:space:]]*#' "$0" | grep -qiE 'catalog churns, so (this|the) pin moves only by a fresh user ruling' \
    || fail "t3[cf-106 C10 AC6]: this suite's convention comment is gone — the re-pin must carry the authority for the literal it pins (owner ruling + no silent flips)"
  grep -qiE 'OQ-14|cf-106' "$API" \
    || fail "t3[cf-106 C10 AC6]: the loop file's comment block does not cite the ruling behind its model literal (C10 task: the comment block carries the live facts, not the history)"
  ok "t3[cf-106 C10 AC6]: model line pinned to gpu-ai/qwen3.8-27b-q4 with the fresh-ruling convention comment on both sides"
fi

# --- t4: one task — the retired pair and its stagger may not come back (AC1) ---
# C10 retires the cf-90 staggered-schedule arm: with ONE task there is nothing
# to stagger, and a second schedule row would stack two claims per tick.
if want t4; then
  [ -f "$API" ] || fail "t4[cf-106 C10]: $API missing (harness fault)"
  grep -qE '^schedule: 0 \* \* \* \*$' "$API" \
    || fail "t4[cf-106 C10 AC1]: the runner's hourly :00 schedule moved — the gate + stale-clock math (2 h window) assume hourly"
  n_sched=$(grep -cE '^schedule:' "$API" || true)
  [ "$n_sched" -eq 1 ] || fail "t4[cf-106 C10 AC1]: $n_sched schedule rows in the loop file — one task, one cadence"
  if [ -e "$LOCAL" ]; then
    fail "t4[cf-106 C10 AC1]: the retired 30 * * * * twin is back on disk — the staggered pair is superseded by the single runner (OQ-14/C10)"
  fi
  ok "t4[cf-106 C10 AC1]: single hourly schedule; the staggered-pair shape is gone (retired arm, replaced by the one-cadence pin)"
fi

# --- t5: the body cites the boards skill's Provider filtering (single home) ----
if want t5; then
  [ -f "$API" ] || fail "t5[cf-106 C10]: $API missing (harness fault)"
  python3 "$TMP/win.py" --ci "$API" 600 'provider filtering' 'boards' \
    || fail "t5[cf-106 C10 AC3]: $API never cites the boards skill's Provider filtering as the authority — the pickup-filter semantics live in ONE place (C10 rewrites that section); the loop body names, never restates"
  # the section it cites must itself read as per-card routing (AC3), so the
  # citation is not pointing at retired text.
  if ! python3 - .rulesync/skills/boards/SKILL.md <<'PY'
import re, sys
text = open(sys.argv[1]).read()
at = text.find("Provider filtering")
assert at >= 0, "the boards skill lost its Provider filtering section — the citation anchor moved"
end = text.find("\n## ", at + 1)
sec = text[at:end if end > 0 else len(text)]
low = sec.lower()
bad = []
if not re.search(r"routes[^.\n]{0,60}(models?|not pickups)|routing[^.\n]{0,60}models?", low):
    bad.append("the section never says the Provider label ROUTES models rather than filtering pickups (C10 task: provider stops being a scheduler split)")
if not re.search(r"unlabeled[^.]{0,200}(ask|kickoff)|(ask|kickoff)[^.]{0,200}unlabeled", low):
    bad.append("the section lost the ask-on-unlabeled rule (the one kickoff ask, Local recommended first per C02)")
print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
  then
    fail "t5[cf-106 C10 AC3]: the boards Provider filtering section is not yet the per-card-routing contract the single runner cites (red until C10 rewrites it)"
  fi
  ok "t5[cf-106 C10 AC3]: the loop body cites the boards Provider filtering section, and that section reads as per-card routing with the unlabeled ask"
fi

# --- t6: the gate script is UNTOUCHED, and its contract still passes (AC5) -----
if want t6; then
  git rev-parse --verify "$BASE" >/dev/null 2>&1 \
    || fail "harness: base ref '$BASE' does not resolve (CHUNK_BASE=<ref>)"
  git diff --quiet "$BASE" -- "$GATE_SCRIPT" \
    || fail "t6[cf-106 C10 AC5]: $GATE_SCRIPT changed since $BASE — the runner rides the gate, it does not replace it (verdict vocabulary + LIVE-branch read-only ban list byte-unchanged)"
  # gate ids t1..t21 MINUS t17: t17 is the known pre-existing red at main HEAD
  # (warm-location permissions drift — a Review card outside this ticket),
  # excluded from these gates per the header note; everything else must pass.
  gate_ids=""
  for i in $(seq 1 21); do
    [ "$i" -eq 17 ] && continue
    gate_ids="$gate_ids t$i"
  done
  bash "$GATE_SUITE" $gate_ids >"$TMP/gate.log" 2>&1 \
    || { tail -n 12 "$TMP/gate.log" >&2; fail "t6[cf-106 C10 AC5]: the gate suite (ids excluding the known-red t17) is not green — log above"; }
  ok "t6[cf-106 C10 AC5]: gate script byte-unchanged vs $BASE and the gate contract passes (t1..t21 minus the pre-existing t17)"
fi

# --- t7: NEGATIVE pins — the two-task posture may not survive (AC3) ------------
if want t7; then
  strays=$(grep -rinE 'claimable by both|whichever claims (the )?first|either may take' .agents/loops/ 2>/dev/null || true)
  [ -z "$strays" ] || { printf '%s\n' "$strays" >&2; fail "t7[cf-90 C04]: the loop files carry the batched-round 'either may take / whichever claims first' shape — superseded by the final-approval ruling and again by the single runner"; }
  # C10 AC3: no CURRENT-STATE surface may still teach the two-task split (an
  # API-only scheduled walk, the Local task as the unlabeled pool's taker, or a
  # per-flavor scheduled task). Dated records — changelog rows, plan folders,
  # this ticket's artifacts — are history and stay out of the sweep by scope.
  cur_state=".agents/loops/pipeline-worker.md .rulesync/skills/boards/SKILL.md .opencode/skills/boards/SKILL.md .rulesync/rules/overview.md AGENTS.md"
  RETIRED='walk takes only|planned (steady[- ]state )?taker|scheduled `?Provider: (API|Local)`? task|the (API|Local) task (is|takes)|both loop (files|tasks)|pipeline-worker-local'
  for f in $cur_state; do
    [ -f "$f" ] || fail "t7[cf-106 C10 AC3]: $f is missing from the sweep (harness fault)"
  done
  hits=$(grep -inE "$RETIRED" $cur_state 2>/dev/null || true)
  [ -z "$hits" ] || { printf '%s\n' "$hits" >&2; fail "t7[cf-106 C10 AC3]: a current-state surface still teaches the two-task / API-only-walk posture above — one scheduled runner, Provider routing per card (red until C10 rewrites these surfaces)"; }
  # Fabricated-stray control: the sweep must reject a reintroduced split sentence.
  printf '%s\n' 'The Scheduled `Provider: API` task walk takes only Provider: API cards; the Local task is the planned steady-state taker.' > "$TMP/two-task.md"
  fabricated=$(grep -inE "$RETIRED" "$TMP/two-task.md" 2>/dev/null || true)
  [ -n "$fabricated" ] || fail "t7[cf-106 C10]: NEGATIVE CONTROL FAILED — the fabricated two-task sentence did not match the sweep (the guard is inert)"
  ok "t7[cf-106 C10 AC3]: negatives hold — no 'both may claim' wording, no current-state surface teaching an API-only walk, the Local planned taker, or a second scheduled task, and the fabricated split is caught"
fi

# --- t8: single-file sweep — the retired name lives only in records (AC4) ------
if want t8; then
  [ -d .agents/loops ] || fail "t8[cf-106 C10 AC4]: .agents/loops/ is gone (harness fault)"
  n_files=$(find .agents/loops -maxdepth 1 -name '*.md' | wc -l)
  [ "$n_files" -eq 1 ] || fail "t8[cf-106 C10 AC4]: .agents/loops/ holds $n_files loop files, want exactly one — AC1's single runner is a file-level fact, not just a frontmatter one"
  # The retired file name may survive ONLY in this ticket's records and the
  # retirement runbook (dated history is history); never in a live surface.
  strays=$(grep -rln 'pipeline-worker-local' .agents/loops .rulesync .opencode scripts AGENTS.md 2>/dev/null || true)
  [ -z "$strays" ] || { printf '%s\n' "$strays" >&2; fail "t8[cf-106 C10 AC4]: the retired loop file's name still lives in a live surface above — the deletion is a repo-side fact (the live task's retirement is the owner's)"; }
  ok "t8[cf-106 C10 AC4]: exactly one loop file; the retired name appears in no live surface (records and the runbook only)"
fi

printf 'PASS: provider loop-tasks contract checks (%d ok)\n' "$checks"
