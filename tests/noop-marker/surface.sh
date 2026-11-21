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
# cf-126 RE-PIN (2026-11-19, agent-test; 2026-11-cf-126-feat-compaction-
# pipeline-sessions): the ruled marker vocabulary grows to SIX — the owner's
# OQ10 ruling adds the dispatcher's proxy exit `delegated` (D15). N2/N3/N7
# re-pin accordingly (designed red until C01 lands the skill text). N4's
# one-loop-file arm is superseded by Ruling OQ1: the ruled shape is TWO files
# — pipeline-worker.md byte-untouched PLUS the NEW pipeline-dispatch.md —
# until a future owner ruling git-rms the old file, which re-pins rather
# than deletes the arm (same settled-value law as the enabled row). N8 is
# new: the dispatcher loop file's shape, body contract and the old-file-
# untouched negative. DESIGNED REDS: N2/N3/N4/N7/N8 until C01, the N8 model
# leg until C04's gated flip; N1/N5/N6 stay HOLD green.
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
#   bash tests/noop-marker/surface.sh            # N1..N8
#   bash tests/noop-marker/surface.sh N2         # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

QN=".opencode/plugin/question-notify/index.ts"
BOARD_SRC=".rulesync/skills/boards/SKILL.md"
BOARD_GEN=".opencode/skills/boards/SKILL.md"
LOOP=".agents/loops/pipeline-worker.md"
LOOPD=".agents/loops/pipeline-dispatch.md"
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
  for i in 1 2 3 4 5 6 7 8; do WANT["n$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^n[1-8]$ ]] || fail "unknown check id '$a' (expected N1..N8)"
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
"""The boards 'No-op marker' subsection: exactly the SIX reason tokens (cf-106
C03b extends the writer predicate to the three tick stops; cf-126 OQ10's owner
ruling adds the dispatcher's proxy exit) and exactly ONE shared
archive recipe — the six exits cite the subsection, they never restate the recipe.
"""
import re, sys
SIX = {"no-cards", "no-claimable-cards", "gate-skip", "gate-live", "board-check-unavailable", "delegated"}
text = open(sys.argv[1]).read()
m = re.search(r"(?ms)^#{3,4}[^\n]*No-op marker[^\n]*\n(.*?)(?=^#{1,4}[^\n]*$|\Z)", text)
if not m:
    print("no 'No-op marker' subsection"); sys.exit(1)
s = m.group(1)
found = set(re.findall(r"[`\"]((?:no|gate|board-check)-[a-z][a-z-]*|delegated)[`\"]", s))
if not SIX <= found:
    print(f"the subsection is missing reason token(s) {sorted(SIX - found)} "
          f"(C03b adds gate-skip, gate-live, board-check-unavailable to the two existing stops; "
          f"cf-126 OQ10 adds delegated, the proxy-forward exit)")
    sys.exit(1)
if extra := found - SIX:
    print(f"the subsection invents reason token(s) {sorted(extra)} outside the ruled six — AC1 pins exactly "
          f"six marked exits; a seventh needs a DECISIONS ruling, not a skill edit")
    sys.exit(1)
if s.count('{"archived": true}') != 1:
    print('the subsection states the archive PATCH '
          f'{s.count(chr(123) + chr(34) + "archived" + chr(34) + ": true" + chr(125))} times — the recipe has '
          'ONE home and the six exits cite it')
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
    # cf-126 OQ10/D15: the sixth token — the dispatcher's proxy-forward exit
    # rides the SAME marked+archived recipe (the reader stays reason-agnostic,
    # so the subsection is the only writer-side home the token must appear in).
    python3 "$TMP/sectwin.py" --ci "$f" 1600 'No-op marker' 'delegated' 'exit' \
      || fail "N2[cf-126 C01 AC6/D15]: $f's No-op marker subsection does not name 'delegated' as a marked exit — the proxy-forward end (a live dispatcher existed, the tick delegated to it) is the sixth marked exit (red until C01 extends the predicate and regenerates)"
  done
  ok "N2[C02 AC3 + cf-106 C03b AC1/AC2 + cf-126 C01 AC6]: boards pair carries the marker subsection with its tokens; the two legacy exits cite it, the three tick stops and the delegated proxy exit are named as marked exits"
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
  # cf-126 C01 (OQ10 ruling): the vocabulary is six; `delegated` joins the scan.
  # The rules source joins the ALLOW set for it alone: overview.md's rewritten
  # "Pipeline worker iterations" section must NAME the exit to summarize it
  # (AC7); the generated AGENTS.md sits outside the scanned roots. Restating the
  # RECIPE there stays the defect the window pins are for.
  if ! out=$(python3 "$TMP/strays.py" --tokens gate-skip,gate-live,board-check-unavailable,no-claimable-cards,delegated \
        --allow "$BOARD_SRC,$BOARD_GEN,$QN,.rulesync/rules/overview.md,.rulesync/skills/agents-sync/references/permissions.md,.opencode/skills/agents-sync/references/permissions.md" \
        .rulesync .opencode skills 2>&1); then
    printf '%s\n' "$out" >&2
    fail "N3[cf-106 C03b AC1 + cf-126 C01]: a marker reason token found outside the boards pair + the plugin comment + the rules source (delegated only) — a third normative copy of the marker vocabulary (cite the subsection, never restate it)"
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
  # cf-106 C10 pinned ONE loop file; Ruling OQ1 (2026-11-17, cf-126) supersedes
  # the single-task shape for the cutover: TWO files — pipeline-worker.md stays
  # BYTE-UNTOUCHED (no fingerprint rotation, no re-approval), the NEW
  # pipeline-dispatch.md carries the dispatcher task. The old OpenChamber task's
  # deletion is the owner's hygiene step and deletes NO file; a future owner
  # git-rm would re-pin this count, never delete this arm (same settled-value
  # law as the enabled row above).
  n_loop=$(find .agents/loops -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
  [ "$n_loop" -eq 2 ] && [ -f "$LOOP" ] && [ -f "$LOOPD" ] \
    || fail "N4[cf-126 Ruling OQ1 re-pin of cf-106 C10]: .agents/loops/ holds $n_loop loop files — the ruled shape is exactly TWO (the byte-untouched pipeline-worker.md + the new pipeline-dispatch.md), red before C01 lands the second file and HOLD after"
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'pipeline-worker-local' "$f" \
      && fail "N4[cf-106 C10 AC4]: $f still names the retired pipeline-worker-local task as part of the live scheduler shape — the pair is superseded by the single runner"
  done
  # cf-106 C03b: the no-work exit is a marked AND archived exit — docs that say
  # "marked" while the archive half is unmentioned understate the silence path.
  for f in AGENTS.md "$RULES_SRC"; do
    python3 "$TMP/win.py" --ci "$f" 600 'no-work' 'archiv' \
      || fail "N4[cf-106 C03b AC6]: $f states the no-work silence without the archived-exit half (mark AND archive, per the boards skill's Exit step) — red until the C03b wording lands"
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
  # cf-106 C03b AC2: ONE shared recipe now serves the marked ends (five then,
  # six since cf-126 OQ10). The subsection must
  # keep the archive PATCH and the never-ask sentence together — if the shared
  # recipe loses the never-ask clause, all marked ends regain the ask at once.
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 900 'No-op marker' '{"archived": true}' 'never ask' \
      || fail "N6[cf-106 C03b AC2]: $f's shared marker recipe no longer carries the archive PATCH and the never-ask sentence in one passage — the marked exits (six since cf-126 OQ10) inherit whatever this passage says"
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
  # (2) dev-facing: the boards subsection names exactly the ruled six reason
  #     tokens, in source and mirror (AC1), and states the archive PATCH once as
  #     the shared recipe (the exits cite the subsection, they never restate it).
  # Controls first: a copy patched to the ruled six tokens must PASS the checker
  # (the pin can go green), and the same copy plus an invented seventh token must FAIL
  # it (the closure bites). Fabricating both sides is what makes the red above and the
  # green it turns into both meaningful.
  python3 - "$BOARD_SRC" "$TMP/boards-six.md" "$TMP/boards-seventh.md" <<'PYX'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"(?m)^#{3,4}[^\n]*No-op marker[^\n]*$", t)
six = ('\nMarked exits and their reason values: `no-cards`, `no-claimable-cards`, `gate-skip`, '
       '`gate-live`, `board-check-unavailable`, `delegated`.\n')
seventh = six + 'A stale-lock stop would write `gate-timeout`.\n'
open(sys.argv[2], "w", encoding="utf-8").write(t[:m.end()] + six + t[m.end():])
open(sys.argv[3], "w", encoding="utf-8").write(t[:m.end()] + seventh + t[m.end():])
PYX
  python3 "$TMP/subsec.py" "$TMP/boards-six.md" >/dev/null 2>&1 \
    || fail "N7 control: a subsection carrying exactly the ruled SIX tokens (OQ10 included) plus the shared recipe FAILED the closure pin — the pin cannot go green when C01 lands, so it is broken"
  python3 "$TMP/subsec.py" "$TMP/boards-seventh.md" >/dev/null 2>&1 \
    && fail "N7 control: a subsection inventing a seventh reason token (gate-timeout) passed the closure — the ruled-six exact count is not enforced"
  ok "N7[cf-106 C03b AC1 control + cf-126 OQ10 re-pin]: the six-token closure accepts a ruled-six copy and rejects an invented seventh token — the dev-facing pin is a genuine red/green pair"
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    python3 "$TMP/subsec.py" "$f" \
      || fail "N7[cf-106 C03b AC1/AC2 + cf-126 OQ10]: the boards marker subsection failed the six-token/one-recipe pin for $f (reason above; designed red until C03b's three stops and cf-126's delegated token land)"
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
  ok "N7[cf-106 C03b AC1/AC2/AC4/AC5 + cf-126 OQ10]: six-token marker subsection with one shared recipe, plugin comment parity (tokens + crash + reap-ungated), three hourly stop branches citing the marker+archive exit, and the mid-turn limit sentence"
fi

# --- N8: cf-126 C01/C04 — the dispatcher loop file + the old-file untouched ------
# The loop-file pin the chunk places "alongside the scheduler-docs-truth arms":
# the NEW pipeline-dispatch.md's frontmatter shape (the five OpenChamber-synced
# fields), its body contract lines (the live-dispatcher lookup, the proxy
# forward + `delegated` exit, the self-marker patch, the one-iteration wake),
# its comment block (the OQ1 ruling + the model-ruling note + C04 as the flip
# wave), and the NEGATIVE half: pipeline-worker.md stays byte-untouched on its
# own agent/model literals — a fabricated repurposing of the old file reddens.
# ONE model arm, ONE state (the chunk's C04 re-pin law): the expected literal
# is the gated radiance value — C01 ships flash-next-strata-q4 (D14), so THIS
# leg stays red through waves 1-3 and flips only when C04's gate facts land.
if want n8; then
  [ -f "$LOOPD" ] || fail "N8[C01 AC2]: $LOOPD missing — the OQ1 ruling names a SECOND, dedicated loop file while pipeline-worker.md stays byte-untouched beside it (designed red before C01 dev)"

  python3 - "$LOOPD" <<'PY' || fail "N8[C01 AC2]: the dispatcher loop file fails its frontmatter/body contract (reason above)"
import re, sys
text = open(sys.argv[1]).read()
# re.S is load-bearing: the YAML block is multi-line and `.` must cross
# newlines (the C01 test-repair round caught this regex never matching).
m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n?([\s\S]*)$", text, re.S)
assert m, "no YAML frontmatter block"
fields = {}
for line in m.group(1).splitlines():
    fm = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
    if fm:
        fields[fm.group(1)] = fm.group(2).strip().strip('"')
errs = []
recognized = {"agent", "enabled", "model", "name", "schedule", "timezone"}
unknown = sorted(set(fields) - recognized)
if unknown:
    errs.append(f"frontmatter carries keys OpenChamber ignores silently: {unknown}")
for k in ("agent", "enabled", "model", "name", "schedule"):
    if k not in fields:
        errs.append(f"missing the decided field {k}")
if fields.get("name") != "pipeline-dispatch":
    errs.append(f"name is {fields.get('name')!r}")
if fields.get("agent") != "agent-board-dispatch":
    errs.append(f"agent is {fields.get('agent')!r}, want agent-board-dispatch (the loop task runs the dispatcher)")
if fields.get("schedule") != "0 * * * *":
    errs.append(f"schedule is {fields.get('schedule')!r}, want the hourly 0 * * * * (mirrors the old task's cadence)")
if fields.get("enabled") != "true":
    errs.append(f"enabled is {fields.get('enabled')!r}, want true (ships ready; the owner creates the task as USER step 1)")
if len(re.findall(r"^model:", m.group(1), re.M)) != 1:
    errs.append("more than one model row — the YAML would silently take the last")
# The model VALUE is NOT checked here (the single C04-state leg runs after
# every content leg, last in N8 — the one-arm-one-state pin must not mask
# the shape/body legs it shares the file with).
if errs:
    print("; ".join(errs)); sys.exit(1)
body = m.group(2)
low = body.lower()
checks = [
    (("opencode api get /api/session",), "the live-dispatcher lookup leg (opencode api get /api/session + filter)"),
    (("pipelineDispatcher",), "the metadata.pipelineDispatcher marker leg"),
    (("api post", "prompt"), "the proxy forward: POST the same tick text to the live dispatcher session"),
    (("delegated",), "the no-op delegated marker + archived exit on the forward leg"),
    (("api patch",), "the self-marker leg: patch YOUR OWN record's metadata before loading the skill"),
    (("pipeline_status",), "the iteration starts first with pipeline_status"),
]
for needles, label in checks:
    if all(n in low or n in body for n in needles):
        continue
    print(f"body lacks {label}")
    sys.exit(1)
if "agent-board-dispatch" not in low:
    print("body never names the dispatcher agent (the filter leg)"); sys.exit(1)
if not re.search(r"exactly one parallel pipeline loops iteration|one parallel pipeline loops iteration", low):
    print("the body must load the boards skill and run exactly ONE Parallel pipeline loops iteration"); sys.exit(1)
print("ok")
PY

  # The comment block carries the ruling trail a future reader needs (the
  # vehicle choice, the byte-untouched law, and that the model row moves only
  # by a fresh owner ruling — C04 is named as the wave).
  python3 "$TMP/win.py" --ci "$LOOPD" 1800 'oq1' 'byte-untouched' 'pipeline-worker' \
    || fail "N8[C01 AC2]: $LOOPD's comment block does not name the OQ1 ruling and the byte-untouched law of the old loop — the two-file posture is a ruling, it must read as one (red before C01 dev)"
  python3 "$TMP/win.py" --ci "$LOOPD" 1800 'ruling' 'c04' \
    || fail "N8[C01 AC2/C04]: the comment block does not keep the model-ruling note AND name C04 as the model-flip wave"

  # The untouched negative on the OLD file: its own agent + the settled
  # 2026-11-09 runner literal stay exactly as committed (pipeline-locks-tick
  # T2 pins the same bytes from the node side; this leg is the loop-docs-home
  # half the chunk asked for, with the repurposing control below).
  grep -qE '^agent: agent-board-coord$' "$LOOP" \
    || fail "N8[C01 AC2 negative]: $LOOP's agent row moved — the OLD loop is byte-untouched by law (Ruling OQ1); repurposing it is the rejected shape"
  grep -qE '^model: gpu-ai/qwen3.8-flash-next-strata-q4$' "$LOOP" \
    || fail "N8[C01 AC2 negative]: $LOOP's settled 2026-11-09 model literal moved — the old file changes NEVER, its task's deletion is the owner's hygiene step"
  sed 's/^agent: agent-board-coord$/agent: agent-board-dispatch/' "$LOOP" >"$TMP/repurposed.md"
  if grep -qE '^agent: agent-board-coord$' "$TMP/repurposed.md"; then
    fail "N8 control: the fabricated repurposing copy still matched the untouched pin — the negative arm is vacuous"
  fi

  # ONE arm, ONE state — the model leg LAST so it never masks the content
  # legs above. The expected literal is the C04-extended state (the chunk's
  # re-pin law); C01 ships the runner literal gpu-ai/qwen3.8-flash-next-strata-q4
  # (D14 — the rotation stays body+agent in wave 1), so red here IS the single
  # designed red, named C04 and gated on the owner's merge/scale/receipt facts.
  if ! grep -qE '^model: gpu-ai/[^ ]+$' "$LOOPD"; then
    fail "N8[C04 AC5]: $LOOPD carries no single literal model row (the frontmatter leg counted the row; here the value read fails) — harness-shape fault"
  fi
  grep -qE '^model: gpu-ai/qwen3.8-27b-radiance$' "$LOOPD" \
    || fail "N8[C04 AC5, DESIGNED RED]: the dispatcher loop file's model row is not gpu-ai/qwen3.8-27b-radiance — the single C04-state pin (one arm, one state per chunks/C04.md Tests); C01 shipped the strata runner literal (D14) and it stays until C04's gate lands the owner ruling + fix-radiance-context merge + q27 scale-up + dated 8-session receipt, then this leg flips and no other N8 leg moves"
  ok "N8[C01 AC2 + C04 AC5]: dispatcher loop file exists with the five-field shape, the tick body (lookup, proxy forward with delegated, self-marker patch, one iteration), the ruling trail in its comment block; the old worker file reads byte-untouched and the repurposing mutant reddens; the model leg (the single C04-state pin) is evaluated last and reddens ALONE until the gate lands"
fi

printf 'PASS: no-op marker contract checks (%d ok)\n' "$checks"
