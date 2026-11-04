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
#   N6  archive-on-no-cards exit (cf-90 C03) — BOTH no-op ends PATCH the
#       session `{"archived": true}` after the marker write and NEVER ask
#       about closing out; the marker recipe (rename → get → merge → patch
#       whole-metadata) stays intact around the new step; PATCH failure
#       still ends cleanly.
#
# Red posture: N1-N4 name not-yet-landed C02 text (plugin predicate, skill
# subsection, truth sentences) — red before dev, HOLD after. N5 is green now
# and must stay green (the chunk edits these very passages). N6 (cf-90 C03)
# is red until the archive-on-no-cards exit text lands; its two HOLD arms —
# marker-recipe order and the whole-metadata read-merge-write mandate — are
# green now and must stay green through the C03 edit.
#
# AC trace (cf-106 C03b re-pin, ask 8 + the OQ5 reconciliation): N2 also names the
# three tick stops as marked exits in the subsection; N3 scans the five-token
# reason vocabulary for a third normative home (agents-sync dated changelog rows
# excepted) and machine-checks the gate SCRIPT stays marker-blind; N6's arms ride
# the ONE shared recipe that now serves five ends; N7 pins the five-token closure
# (fabricated sixth-token control), the plugin comment parity (tokens, crash-never-
# suppressed, reap alert ungated), the hourly command's three stop branches citing
# the marker+archive exit, and the skill's mid-turn-limit sentence — with a
# fabricated-third-home control for the stray scanner. N7 and N2's tick-stop arms
# are red until C03b lands; N3's script-blind and N6's shared-recipe arms are HOLD.
#
# Offline-deterministic text pins over the trees; no server, no session. The
# behavior matrix lives in tests/opencode/question-notify.test.ts T9/T10; the
# scheduled-side end-to-end leg is C03's LF6 runbook (unit arms are this
# chunk's proof surface per OQ-N2).
#
# Usage:
#   bash tests/noop-marker/surface.sh            # N1..N7
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
  for i in 1 2 3 4 5 6 7; do WANT["n$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^n[1-7]$ ]] || fail "unknown check id '$a' (expected N1..N7)"
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

cat >"$TMP/strays.py" <<'PY'
"""Third-home scanner (C02 AC4 single-home law, cf-106 C03b token closure).

usage: strays.py --tokens a,b,c --allow file,file <root>...
Prints every file under the roots (outside --allow) carrying any token, and exits
1 when there is at least one — a token contract gains a normative copy.
"""
import os, sys
argv = sys.argv[1:]
tokens, allow, roots = [], set(), []
i = 0
while i < len(argv):
    if argv[i] == "--tokens":
        tokens = [t for t in argv[i + 1].split(",") if t]; i += 2
    elif argv[i] == "--allow":
        allow = {os.path.normpath(a) for a in argv[i + 1].split(",") if a}; i += 2
    else:
        roots.append(argv[i]); i += 1
hits = []
for root in roots:
    if os.path.isfile(root):
        files = [root]
    else:
        files = [os.path.join(b, f) for b, _d, fs in os.walk(root) for f in fs]
    for p in files:
        if os.path.normpath(p) in allow:
            continue
        try:
            text = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        found = [t for t in tokens if t in text]
        if found:
            hits.append(f"{os.path.normpath(p)}: {','.join(found)}")
for h in hits:
    print(h)
sys.exit(1 if hits else 0)
PY

cat >"$TMP/subsec.py" <<'PY'
"""The boards 'No-op marker' subsection: exactly the five reason tokens (cf-106
C03b extends the writer predicate to the three tick stops) and exactly ONE shared
archive recipe — the five exits cite the subsection, they never restate the recipe.
"""
import re, sys
FIVE = {"no-cards", "no-claimable-cards", "gate-skip", "gate-live", "board-check-unavailable"}
text = open(sys.argv[1]).read()
m = re.search(r"(?ms)^#{3,4}[^\n]*No-op marker[^\n]*\n(.*?)(?=^#{1,4}[^\n]*$|\Z)", text)
if not m:
    print("no 'No-op marker' subsection"); sys.exit(1)
s = m.group(1)
found = set(re.findall(r"[`\"]((?:no|gate|board-check)-[a-z][a-z-]*)[`\"]", s))
if not FIVE <= found:
    print(f"the subsection is missing reason token(s) {sorted(FIVE - found)} "
          f"(C03b adds gate-skip, gate-live, board-check-unavailable to the two existing stops)")
    sys.exit(1)
if extra := found - FIVE:
    print(f"the subsection invents reason token(s) {sorted(extra)} outside the ruled five — AC1 pins exactly "
          f"five marked exits; a sixth needs a DECISIONS ruling, not a skill edit")
    sys.exit(1)
if s.count('{"archived": true}') != 1:
    print('the subsection states the archive PATCH '
          f'{s.count(chr(123) + chr(34) + "archived" + chr(34) + ": true" + chr(125))} times — the recipe has '
          'ONE home and the five exits cite it')
    sys.exit(1)
print("ok")
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
    # cf-106 C03b AC1/AC2: the writer predicate extends to the three tick stops —
    # each must be named as a marked exit inside the subsection (the exits elsewhere
    # stay cite-only, so the subsection is where the five-end coverage is pinned).
    for stop in 'gate-skip' 'gate-live' 'board-check-unavailable'; do
      python3 "$TMP/sectwin.py" --ci "$f" 1400 'No-op marker' "$stop" 'exit' \
        || fail "N2[cf-106 C03b AC1/AC2]: $f's No-op marker subsection does not name '$stop' as a marked exit — the three tick stops must run the same recipe (red until C03b extends the predicate)"
    done
  done
  ok "N2[C02 AC3 + cf-106 C03b AC1/AC2]: boards pair carries the marker subsection with its tokens; the two legacy exits cite it and the three tick stops are named as marked exits"
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
  # cf-106 C03b: the REASON vocabulary keeps the same single-home law — the boards
  # pair (writer authority) plus the plugin comment (reader parity). The agents-sync
  # permissions reference is excepted: its mentions sit inside dated changelog rows
  # recording past tickets (append-only history, same law as the cf-106 C02 sweep).
  if ! out=$(python3 "$TMP/strays.py" --tokens gate-skip,gate-live,board-check-unavailable,no-claimable-cards \
        --allow "$BOARD_SRC,$BOARD_GEN,$QN,.rulesync/skills/agents-sync/references/permissions.md,.opencode/skills/agents-sync/references/permissions.md" \
        .rulesync .opencode skills 2>&1); then
    printf '%s\n' "$out" >&2
    fail "N3[cf-106 C03b AC1]: a marker reason token found outside the boards pair + the plugin comment — a third normative copy of the marker vocabulary (cite the subsection, never restate it)"
  fi
  # cf-106 C03b AC3: the gate SCRIPT stays marker-blind — it prints a verdict and
  # touches no session; the RUN that reads the verdict marks and archives.
  if hits=$(grep -nE 'pipelineNoop|archiv' scripts/agent-board-coord-gate.sh); then
    printf '%s\n' "$hits" >&2
    fail "N3[cf-106 C03b AC3]: scripts/agent-board-coord-gate.sh carries marker/archive text — the script must stay marker-blind (the run marks, the script never does)"
  fi
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
  # cf-106 C10: the scheduler docs describe ONE loop file — a docs surface that
  # still enumerates the retired pair teaches a task that no longer exists.
  n_loop=$(find .agents/loops -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
  [ "$n_loop" -eq 1 ] \
    || fail "N4[cf-106 C10 AC1]: .agents/loops/ holds $n_loop loop files while the scheduler docs describe the runner — one scheduled task is the contract (red until C10's git rm lands)"
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'pipeline-worker-local' "$f" \
      && fail "N4[cf-106 C10 AC4]: $f still names the retired pipeline-worker-local task as part of the live scheduler shape — the pair is superseded by the single runner"
  done
  # cf-106 C03b: the no-work exit is a marked AND archived exit — docs that say
  # "marked" while the archive half is unmentioned understate the silence path.
  for f in AGENTS.md "$RULES_SRC"; do
    python3 "$TMP/win.py" --ci "$f" 600 'no-work' 'archiv' \
      || fail "N4[cf-106 C03b AC3]: $f states the no-work silence without the archived-exit half (mark AND archive, per the boards skill's Exit step) — red until the C03b wording lands"
  done
  ok "N4[C02 AC6 + cf-106 C03b/C10]: stale current-tense claims gone, one authoritative settled enabled: row, live state + human-owned hygiene + silence clause recorded, ONE loop file named by the scheduler docs, and the no-work silence stated as the marked+archived exit"
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

# --- N6: archive-on-no-cards exit (cf-90 C03 AC1 — red before C03 dev) ----------
# The no-cards end ARCHIVES its own session, never asks. Pins: the literal
# archive body in BOTH exits, the never-ask sentence naming the "should I
# close out?" question, the failure-still-clean posture, and the two HOLD
# arms proving the marker recipe (write it FIRST, whole-metadata
# read-merge-write) survives around the new step. C03 chunk Notes-for-dev:
# the PATCH is a NEW step after the recipe, never a rewrite of it.
if want n6; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "N6: $f missing (harness fault)"
    grep -qF '{"archived": true}' "$f" \
      || fail "N6[C03 AC1]: $f lacks the native OpenCode archive body {\"archived\": true} — the no-cards exit archives its own session (RESEARCH F4; red before C03 dev)"
    grep -qF 'close out' "$f" \
      || fail "N6[C03 AC1]: $f has no never-ask sentence — a no-cards end must be stated NEVER to ask \"should I close out?\" (the posture that replaces it: archive and stop)"
    python3 "$TMP/win.py" --ci "$f" 1200 'Nothing anywhere' 'archiv' \
      || fail "N6[C03 AC1]: Card pickup step 4 (the no-cards end) does not carry the archive step near its exit line (red before C03 dev)"
    python3 "$TMP/win.py" --ci "$f" 1200 'no eligible work' 'archiv' \
      || fail "N6[C03 AC1]: the claim-cap stop does not carry the archive step near its exit line (red before C03 dev)"
    python3 "$TMP/win.py" --ci "$f" 700 'archiv' 'never' \
      || fail "N6[C03 AC1]: the archive step is not bound to its never-ask sentence in ONE passage"
    python3 "$TMP/win.py" --ci "$f" 700 'archiv' 'failure' \
      || fail "N6[C03 Tasks]: $f does not state the PATCH-failure posture (any PATCH failure → end cleanly anyway, recorded in commands_run — the marker-failure posture, never a retry loop)"
    python3 "$TMP/win.py" --ci "$f" 900 'PATCH replaces' 'read-merge-write' \
      || fail "N6[C03 Notes-for-dev]: the whole-metadata read-merge-write mandate was reordered or reworded away — the archive PATCH rides AFTER the recipe; the recipe itself stays byte-true"
    if ! python3 - "$f" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'(?ms)^#+[^\n]*No-op marker[^\n]*\n(.*?)(?=^#{1,4}[^\n]*$|\Z)', text)
if not m:
    print("No-op marker subsection lost"); sys.exit(1)
s = m.group(1)
meta = s.find('\'{"metadata":')
arch = s.find('{"archived": true}')
if arch >= 0 and meta >= 0 and arch < meta:
    print("archive PATCH placed BEFORE the marker write — posture: marker first, then archive, then stop"); sys.exit(1)
sys.exit(0)
PY
    then fail "N6[C03]: marker-recipe-before-archive order broken in $f (reason above)"; fi
  done
  # cf-106 C03b AC2: ONE shared recipe now serves five ends. The subsection must
  # keep the archive PATCH and the never-ask sentence together — if the shared
  # recipe loses the never-ask clause, all five ends regain the ask at once.
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 900 'No-op marker' '{"archived": true}' 'never ask' \
      || fail "N6[cf-106 C03b AC2]: $f's shared marker recipe no longer carries the archive PATCH and the never-ask sentence in one passage — the five marked exits inherit whatever this passage says"
  done
  ok "N6[C03 AC1 + cf-106 C03b AC2]: the no-op ends archive {\"archived\": true} after the marker write with the never-ask + failure-still-clean posture, on one shared recipe; marker recipe order and the whole-metadata mandate intact"
fi

# --- N7: cf-106 C03b — the three tick-stop exits, the plugin comment parity, and
#     the mid-turn limit sentence ---------------------------------------------------
if want n7; then
  # (1) Control FIRST: the token-stray scanner must FIND a fabricated third home,
  #     or N3's single-home green proves nothing.
  mkdir -p "$TMP/ghost"
  printf '%s\n' 'The reason vocabulary is `no-claimable-cards`, `gate-skip` and `board-check-unavailable`.' >"$TMP/ghost/third-home.md"
  if python3 "$TMP/strays.py" --tokens gate-skip,board-check-unavailable --allow "$TMP/ghost/allowed.md" "$TMP/ghost" >"$TMP/ghost.out" 2>&1; then
    fail "N7 control: the fabricated third home (ghost/third-home.md) passed the single-home scan — the scanner is vacuous, fix it before trusting N3"
  fi
  grep -q 'third-home.md' "$TMP/ghost.out" \
    || fail "N7 control: the stray scanner fired but did not name the fabricated home — its reporting is broken (output: $(head -2 "$TMP/ghost.out" | tr '\n' ' '))"
  ok "N7[cf-106 C03b AC1 control]: the stray scanner catches a fabricated third marker home — N3's single-home arm bites"
  # (2) dev-facing: the boards subsection names exactly the five reason tokens, in
  #     source and mirror (AC1), and states the archive PATCH once as the shared
  #     recipe (the exits cite the subsection, they never restate the recipe).
  # Controls first: a copy patched to the ruled five tokens must PASS the checker
  # (the pin can go green), and the same copy plus an invented sixth token must FAIL
  # it (the closure bites). Fabricating both sides is what makes the red above and the
  # green it turns into both meaningful.
  python3 - "$BOARD_SRC" "$TMP/boards-five.md" "$TMP/boards-sixth.md" <<'PYX'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"(?m)^#{3,4}[^\n]*No-op marker[^\n]*$", t)
five = ('\nMarked exits and their reason values: `no-cards`, `no-claimable-cards`, `gate-skip`, '
        '`gate-live`, `board-check-unavailable`.\n')
six = five + 'A stale-lock stop would write `gate-timeout`.\n'
open(sys.argv[2], "w", encoding="utf-8").write(t[:m.end()] + five + t[m.end():])
open(sys.argv[3], "w", encoding="utf-8").write(t[:m.end()] + six + t[m.end():])
PYX
  python3 "$TMP/subsec.py" "$TMP/boards-five.md" >/dev/null 2>&1 \
    || fail "N7 control: a subsection carrying exactly the ruled five tokens plus the shared recipe FAILED the closure pin — the pin cannot go green when C03b lands, so it is broken"
  python3 "$TMP/subsec.py" "$TMP/boards-sixth.md" >/dev/null 2>&1 \
    && fail "N7 control: a subsection inventing a sixth reason token (gate-timeout) passed the closure — AC1's five-exact count is not enforced"
  ok "N7[cf-106 C03b AC1 control]: the five-token closure accepts a ruled-five copy and rejects an invented sixth token — the dev-facing pin is a genuine red/green pair"
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    python3 "$TMP/subsec.py" "$f" \
      || fail "N7[cf-106 C03b AC1/AC2]: the boards marker subsection failed the five-token/one-recipe pin for $f (reason above; designed red until C03b extends the writer predicate to the three tick stops)"
  done
  # (3) dev-facing: the plugin comment names the writer's five tokens and the two
  #     never-mute rules (crash push, reap alert), comment-only parity (AC4).
  for tok in 'gate-skip' 'gate-live' 'board-check-unavailable'; do
    grep -qF -- "$tok" "$QN" \
      || fail "N7[cf-106 C03b AC4]: $QN's header comment does not name '$tok' — the reader is token-agnostic, so the comment must name the writer's full vocabulary or the next reader change will re-derive a narrower one (red until C03b's comment parity)"
  done
  python3 "$TMP/win.py" --ci "$QN" 900 'crash' 'never' 'suppress' \
    || fail "N7[cf-106 C03b AC4]: $QN does not state the crash-push-never-suppressed rule in one passage (handleLifecycle consults the predicate on FINISHED only — the comment must carry that boundary)"
  python3 "$TMP/win.py" --ci "$QN" 700 'reap' 'haNotify' \
    || fail "N7[cf-106 C03b AC4]: $QN does not state that the reap alert stays gated only by haNotify (owner's answer 13: the marker never reaches sendHaReapAlert)"
  if python3 "$TMP/win.py" --ci "$QN" 400 'sendHaReapAlert' 'noWorkSuppressed'; then
    fail "N7[cf-106 C03b AC4]: sendHaReapAlert and noWorkSuppressed co-occur in $QN — the reap alert must stay OUTSIDE the no-work suppression (owner's answer 13)"
  fi
  # (4) dev-facing: the hourly command's three stop branches each name the
  #     marker+archive exit (citing the subsection, never restating the key).
  for branch in 'GATE: SKIP' 'filtered-in card' 'board-check unavailable'; do
    python3 "$TMP/win.py" --ci "$HOURLY" 900 "$branch" 'marker' 'archiv' \
      || fail "N7[cf-106 C03b AC2]: the hourly command's '$branch' stop does not name the marker+archive exit in one passage — C03b makes every tick-stop a marked, archived end (the coverage gap C03a measured)"
  done
  grep -qF 'pipelineNoop' "$HOURLY" \
    && fail "N7[cf-106 C03b AC1]: the hourly command restates the pipelineNoop key — the branches cite the boards subsection; the key keeps its single home"
  # (5) dev-facing: the honest limit stated once in the skill (AC5).
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 900 'cannot mark itself' 'dies' \
      || fail "N7[cf-106 C03b AC5]: $f does not state the mid-turn limit (a run that dies before reaching an exit cannot mark itself) — the plan requires it written once, honestly, instead of a guessed engine-side fix"
  done
  ok "N7[cf-106 C03b AC1/AC2/AC4/AC5]: five-token marker subsection with one shared recipe, plugin comment parity (tokens + crash + reap-ungated), three hourly stop branches citing the marker+archive exit, and the mid-turn limit sentence"
fi

printf 'PASS: no-op marker contract checks (%d ok)\n' "$checks"
