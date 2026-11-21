#!/usr/bin/env bash
# cf-126 C01 — the shared-session dispatcher doctrine pin suite.
#
# Pins the boards-skill Dispatcher contract lines: the chunk placed one arm
# per C01 contract line here (the admissible new home), the `delegated`
# token closure lives in tests/noop-marker/surface.sh N2/N7, the loop-file
# bytes in its N8. AC trace:
#   D1[AC6 walk-citation line]  D2[AC6 spawn-contract metadata shape]
#   D3[D18 variant rule + spawn fields]  D4[AC6 deploy-follow-up contract line]
#   D5[AC6 handed-off-intake note + D5 fallback law]  D6[AC6 release-wake
#   naming in Card lifecycle]  D7[AC6 Stage-map Deployment-row board-family
#   clause]  D8[AC6 Provider-filtering one-scheduled-walk rewording]
#   D9[C01 Tasks Dispatcher-reset citation (C03 owns the mechanics)]
#
# Red posture: designed-red until C01 dev edits the boards skill and
# regenerates the mirror — every red names the missing contract line (or,
# before dev, the missing `## Dispatcher` section). Each arm carries a
# fabricated-drift control: a copy with the line's anchor token stripped must
# fail the same window call (the suite convention — an uncaught mutant means
# the pin is vacuous).
#
# Offline-deterministic text pins over the trees; no server, no board call.
#
# Usage:
#   bash tests/dispatcher/surface.sh           # D1..D9
#   bash tests/dispatcher/surface.sh D2 D4     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BD_SRC=".rulesync/skills/boards/SKILL.md"
BD_GEN=".opencode/skills/boards/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/dispatcher-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8 9; do WANT["d$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^d[1-9]$ ]] || fail "unknown check id '$a' (expected D1..D9)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

cat >"$TMP/sectwin.py" <<'PY'
# Window scoped to one heading's section (the sibling suites' convention): the
# contract tokens must read as ITS passage — section-scoped to the next
# heading, so a token smuggled into later prose does not satisfy the pin.
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

cat >"$TMP/stripcopy.py" <<'PY'
# Fabricated-drift control fixture: a copy of the file with EVERY occurrence of
# one anchor token removed — the same window call must fail against it, proving
# the pin is keyed to the contract line and not satisfiable by file-wide scatter.
import sys
src, dst, token = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src, encoding="utf-8").read()
if token not in t:
    # The token is already absent: the strip cannot bite, so the mutant equals
    # the file whose arm the control is meant to prove non-vacuous against.
    print(f'control fault: anchor token "{token}" absent from {src} — the pin for it is vacuous'); sys.exit(3)
open(dst, "w", encoding="utf-8").write(t.replace(token, ""))
PY

SRC="$BD_SRC"
GEN="$BD_GEN"

# --- D1: the Dispatcher section cites the shared-authority walk (AC6) ----------
if want d1; then
  for f in "$SRC" "$GEN"; do
    [ -f "$f" ] || fail "D1: $f missing (harness fault)"
    python3 "$TMP/sectwin.py" --ci "$f" 2000 'Dispatcher' 'Card pickup' 'Repo identity' 'dependency gate' 'Provider filtering' \
      || fail "D1[C01 AC6]: $f has no Dispatcher section citing the walk's SHARED authorities (Card pickup + repo filter + dependency gate + Provider filtering) — the scheduled walk moved to the dispatcher; the coord keeps the fallback (D5) (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d1-off.md" 'dependency gate' \
    || fail "D1 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d1-off.md" 2000 'Dispatcher' 'Card pickup' 'Repo identity' 'dependency gate' 'Provider filtering' >/dev/null 2>&1; then
    fail "D1 control: the copy with the dependency-gate citation stripped still passed D1 — the pin does not key the walk-citation line"
  fi
  ok "D1[C01 AC6]: Dispatcher section cites the shared walk authorities in source AND mirror; the fabricated stripped-line copy reddens"
fi

# --- D2: the spawn contract's metadata shape (AC6, D18/D4) ---------------------
if want d2; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 2400 'Dispatcher' 'cardNumber' 'slug' 'parent' 'variant' 'location' \
      || fail "D2[C01 AC6]: $f's spawn contract does not name the creation-metadata shape (card + cardNumber + slug + parent = the dispatcher session id + variant + location = the project root) — the coord's kickoff mints its own worktree per the checked Worktree Creation stage (D18) (red before C01 dev)"
    python3 "$TMP/sectwin.py" --ci "$f" 2400 'Dispatcher' 'pre-resolved' 'never re-ask' \
      || fail "D2[C01 AC6]: $f's launch brief does not state the pre-resolved checklist answers ride it and are never re-asked (the card-driven-kickoff law)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d2-off.md" 'cardNumber' \
    || fail "D2 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d2-off.md" 2400 'Dispatcher' 'cardNumber' >/dev/null 2>&1; then
    fail "D2 control: the copy with every cardNumber mention removed still passed — the metadata pin is vacuous"
  fi
  ok "D2[C01 AC6]: spawn contract pins the metadata shape + the never-re-asked intake in source AND mirror; stripped-cardNumber copy reddens"
fi

# --- D3: the variant rule (D18 — Deployment checked => -pr, default => -local) --
if want d3; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1800 'Dispatcher' 'agent-board-coord-pr' 'agent-board-coord-local' 'pipeline-models' \
      || fail "D3[C01 AC6/D18]: $f's spawn contract does not state the variant rule (checked Lifecycle Deployment bit selects agent-board-coord-pr, default selects -local) with the model tiers resolved through the pipeline-models citation (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d3-off.md" 'agent-board-coord-pr' \
    || fail "D3 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d3-off.md" 1800 'Dispatcher' 'agent-board-coord-pr' >/dev/null 2>&1; then
    fail "D3 control: the copy with every agent-board-coord-pr mention removed still passed — the variant pin is vacuous"
  fi
  ok "D3[C01 AC6/D18]: the variant rule + pipeline-models tier citation sit in the spawn contract (source + mirror); stripped copy reddens"
fi

# --- D4: the deploy follow-up contract line (D18) -------------------------------
if want d4; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1800 'Dispatcher' 'agent-dev-deploy-pr' 'top-level' 'out of context' 'card comment' \
      || fail "D4[C01 AC6/D18]: $f's deploy follow-up is missing its contract line — final review passed + Deployment checked => spawn the TOP-LEVEL agent-dev-deploy-pr with the card/plan-folder/worktree/branch brief and \"when done or out of context, notify the dispatcher (or let the user do it) and leave a card comment\" (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d4-off.md" 'out of context' \
    || fail "D4 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d4-off.md" 1800 'Dispatcher' 'out of context' >/dev/null 2>&1; then
    fail "D4 control: the copy stripped of the contract phrase still passed — the deploy follow-up pin is vacuous"
  fi
  ok "D4[C01 AC6/D18]: the dispatcher's top-level agent-dev-deploy-pr follow-up carries its contract line (source + mirror); stripped copy reddens"
fi

# --- D5: the handed-off-intake note + the fallback law (D5) ---------------------
if want d5; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1200 'Card pickup' 'handed-off' 'brief' \
      || fail "D5[C01 AC6]: $f's Card pickup section does not carry the handed-off-intake note (a coord launched with a named candidate plus the dispatcher's pre-resolved brief — the step-1 shape, the answers consumed without re-asking) (red before C01 dev)"
    python3 "$TMP/sectwin.py" --ci "$f" 1600 'Card pickup' 'fallback' 'pipeline-boards-hourly' 'manual' \
      || fail "D5[C01 AC6/D5]: $f's Card pickup section never states the FALLBACK law — the walk stays in the coord for /pipeline-boards, /pipeline-boards-hourly and a manual named-card launch (the evaluation answer: removal would break the documented fallback) (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d5-off.md" 'handed-off' \
    || fail "D5 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d5-off.md" 1200 'Card pickup' 'handed-off' >/dev/null 2>&1; then
    fail "D5 control: the copy stripped of the intake-note token still passed — the note pin is vacuous"
  fi
  ok "D5[C01 AC6/D5]: intake note + fallback law in Card pickup (source + mirror); stripped copy reddens"
fi

# --- D6: the release-wake naming in Card lifecycle (D6) -------------------------
if want d6; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1600 'Card lifecycle' 'release' 'wake' 'dispatcher' \
      || fail "D6[C01 AC6/D6]: $f's Card lifecycle section does not name the lock release waking the dispatcher — the coord-side \"trigger at lock clear\" is the same plugin mechanism plus this doctrine (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d6-off.md" 'wake' \
    || fail "D6 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d6-off.md" 1600 'Card lifecycle' 'wake' >/dev/null 2>&1; then
    fail "D6 control: the copy stripped of the wake wording still passed — the lifecycle naming pin is vacuous"
  fi
  ok "D6[C01 AC6/D6]: Card lifecycle names the release wake (source + mirror); stripped copy reddens"
fi

# --- D7: the Stage map's Deployment-row board-family clause (D18) ---------------
if want d7; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 2400 'Stage map' 'Deployment' 'dispatcher' 'board family' \
      || fail "D7[C01 AC6/D18]: $f's Stage map Deployment row does not carry the board-family clause — for board runs the deploy fixer is the dispatcher's TOP-LEVEL spawn (replacing the 8b subagent launch); the non-board coord family keeps its 8b subagent launch (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d7-off.md" 'board family' \
    || fail "D7 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d7-off.md" 2400 'Stage map' 'board family' >/dev/null 2>&1; then
    fail "D7 control: the copy stripped of the board-family wording still passed — the Deployment-row pin is vacuous"
  fi
  ok "D7[C01 AC6/D18]: the Stage map's Deployment row names the board-family dispatcher spawn (source + mirror); stripped copy reddens"
fi

# --- D8: the Provider-filtering one-scheduled-walk rewording --------------------
if want d8; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1600 'Provider filtering' 'dispatcher' 'scheduled' \
      || fail "D8[C01 AC6]: $f's Provider-filtering section does not read as ONE SCHEDULED WALK run by the dispatcher (the per-card Provider label still routes the model inside the run) — the pre-C01 phrasing taught the coord's hourly walk (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d8-off.md" 'dispatcher' \
    || fail "D8 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d8-off.md" 1600 'Provider filtering' 'dispatcher' >/dev/null 2>&1; then
    fail "D8 control: the copy stripped of every dispatcher mention still passed — the rewording pin is vacuous"
  fi
  ok "D8[C01 AC6]: Provider filtering reworded to the one scheduled dispatcher walk (source + mirror); stripped copy reddens"
fi

# --- D9: the Dispatcher section cites the compaction reset (C03 owns mechanics) --
if want d9; then
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 900 'Dispatcher' 'compaction' \
      || fail "D9[C01 Tasks]: $f's Dispatcher section does not name the contract that the compaction hook covers the dispatcher's own context reset — the section names it, C03 owns the mechanics (red before C01 dev)"
  done
  python3 "$TMP/stripcopy.py" "$SRC" "$TMP/d9-off.md" 'compaction' \
    || fail "D9 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/d9-off.md" 900 'Dispatcher' 'compaction' >/dev/null 2>&1; then
    fail "D9 control: the copy stripped of compaction wording still passed — the reset-citation pin is vacuous"
  fi
  ok "D9[C01 Tasks]: the Dispatcher section cites its own compaction reset (source + mirror); stripped copy reddens"
fi

printf 'PASS: dispatcher doctrine contract checks (%d ok)\n' "$checks"
