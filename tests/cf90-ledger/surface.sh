#!/usr/bin/env bash
# cf-90 C07 deferred-cards ledger — policy/text gate + read-back runbook check
# (2026/2026-10-cf-90-feat-board-coord-improvements, C07).
#
# C07 has NO code surface: the ledger cards are created on the live AI-Dev
# board by the COORDINATOR (board writes are the coord's surface), and the
# chunk's "tests" are a post-creation board read-back executed at review.
# The agent-test deliverable is therefore (a) the read-back runbook — a
# REVIEW CONTRACT, not code — and (b) this offline suite pinning the
# policy TEXT the coord-executed creation must obey plus the ledger's
# CONTENT AUTHORITY (the plan appendix) — everything deterministically
# checkable without touching the board. The runbook is a tests/ file because
# chunk files are plan/coord-owned; this suite pins that its required steps
# never drift away (t1), that the appendix keeps the 8-CREATE/4-CITE shape
# (t2, AC1/AC2 guards), that the C03 follow-up protocol the run executes
# under is present at execution time (t3 — pre-existing from C03's own c22
# pin, repeated here so C07's gate is self-contained: policy before use),
# and that the superseded destinations never sneak back (t4).
#
# Red posture: t1/t2/t4 are GREEN NOW (the runbook is this change's own
# deliverable; the appendix is approved plan content) and HOLD; t3 is
# DESIGNED RED until C03 lands (C07 executes in wave 2, after C03, so its
# gate sees t3 green — red for anyone running C07's gate early means the
# dependency order was violated).
#
# AC trace: t1[chunk Tests: the read-back checklist exists and covers AC1-AC5]
# t2[AC1/AC2 content guards — 12 entries, CREATE/CITE split, each CREATE
# names Services+Type, destination Inbox] t3[AC3 preconditions — landing in
# Inbox (Backlog), timing after post-research before the test session,
# parent labels EXCEPT Research, never add_checklist, default_checked-or-
# toggle degrade] t4[AC2 negatives — no Low-Priority/Review destination for
# ledger cards; Inbox is never CREATED by this chunk].
#
# Offline-deterministic: text pins over the repo tree only. No dev-boards
# call, no OpenChamber, no network — the live read-back legs run in
# production during the coord-executed C07 pass, per this runbook.
#
# Usage:
#   bash tests/cf90-ledger/surface.sh            # t1..t4
#   bash tests/cf90-ledger/surface.sh t3         # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

RUNBOOK="tests/cf90-ledger/readback-runbook.md"
PLAN=".agents/plans/2026/2026-10-cf-90-feat-board-coord-improvements/2026-10-31-feat-board-coord-improvements.md"
BOARDS_SRC=".rulesync/skills/boards/SKILL.md"
BOARDS_GEN=".opencode/skills/boards/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/cf90-ledger-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-4]$ ]] || fail "unknown check id '$a' (expected t1..t4)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: the read-back runbook carries every review leg -------------------------
if want t1; then
  [ -f "$RUNBOOK" ] \
    || fail "t1[C07 Tests]: $RUNBOOK missing — it is agent-test's deliverable for the coord-executed ledger chunk (the chunk file itself is plan/coord-owned, so the runbook lives in tests/)"
  # The read-back steps (chunk "## Tests" + ACs 1-5), pinned as co-located
  # review handles, not prose shape.
  grep -qF 'list_cards_in_list' "$RUNBOOK" \
    || fail "t1[C07 Tests]: runbook lost the Inbox list read-back (every expected title EXACTLY ONCE — AC1/AC2)"
  grep -qF 'get_card' "$RUNBOOK" \
    || fail "t1[C07 Tests]: runbook lost the first+last created-card body sample (the three required lines — AC3)"
  grep -qF 'get_checklist' "$RUNBOOK" \
    || fail "t1[C07 Tests]: runbook lost the five-checklists-with-right-items-checked sample (AC3)"
  grep -qF 'list_comments' "$RUNBOOK" \
    || fail "t1[C07 Tests]: runbook lost the card-#90 ledger-comment check (AC4)"
  grep -qiE 'no move, no edit' "$RUNBOOK" \
    || fail "t1[C07 AC2]: runbook lost the CITE-cards-untouched posture (cite-only: no move, no edit, no comment on existing cards)"
  grep -qiE 'EXACTLY ONCE|exactly once' "$RUNBOOK" \
    || fail "t1[C07 AC1]: runbook lost the once-and-only-once title duty"
  grep -qiE 'MINUS Research|minus Research' "$RUNBOOK" && grep -qiE 'Parent labels' "$RUNBOOK" \
    || fail "t1[C07 AC3]: runbook lost the parent-labels-line contract (all parent labels MINUS Research)"
  grep -qiE 'list_lists' "$RUNBOOK" && grep -qiE 'never.*creat|creation belongs' "$RUNBOOK" \
    || fail "t1[C07 Tasks]: runbook lost the Inbox re-resolve + never-create-it-here posture (provisioning owns list creation)"
  ok "t1[C07]: read-back runbook present with all AC1-AC5 legs + the destination re-resolve posture"
fi

# --- t2: the plan appendix keeps the reconciled ledger shape --------------------
# The appendix is the content authority the coord copies; this arm guards its
# structure (a drifted appendix silently changes what gets created).
if want t2; then
  [ -f "$PLAN" ] || fail "t2[harness]: $PLAN not found"
  # mawk-safe: section walk with ASCII-only patterns (the heading's em-dash
  # never enters the regex).
  awk '/^## Appendix/{f=1; next} f && /^## /{exit} f' "$PLAN" | grep -oE '\*\*L[0-9]+ \((CREATE|CITE)\)' \
    >"$TMP/entries" || true
  python3 - "$TMP/entries" <<'PY' || fail "t2[C07 AC1/AC2]: the plan appendix ledger shape drifted (detail above)"
import re, sys
rows = [re.search(r'L(\d+) \((CREATE|CITE)\)', l) for l in open(sys.argv[1]) if l.strip()]
rows = [(int(m.group(1)), m.group(2)) for m in (r for r in rows if r)]
got = dict(rows)
assert sorted(got) == list(range(1, 13)), f"expected L1..L12 exactly, got {sorted(got)}"
create = {k for k, v in got.items() if v == "CREATE"}
cite = {k for k, v in got.items() if v == "CITE"}
assert create == {1, 2, 3, 4, 7, 10, 11, 12}, f"CREATE set drifted: {sorted(create)} (8 creates is the reconciled shape)"
assert cite == {5, 6, 8, 9}, f"CITE set drifted: {sorted(cite)} (existing cards are cited, never duplicated)"
PY
  # Per-entry Services/Type facts — appendix lines WRAP, so evaluate whole
  # entry blocks (split on the leading `**L<n>` bullets), not single lines.
  awk '/^## Appendix/{f=1; next} f && /^## /{exit} f' "$PLAN" >"$TMP/appendix.txt"
  cat >"$TMP/appendix.py" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
blocks = re.split(r'(?m)^- (?=\*\*L\d)', text)
facts = {}
for b in blocks:
    m = re.match(r'\*\*L(\d+)', b)
    if m:
        # appendix lines wrap mid-token ('agent\ncontext'), so match on
        # whitespace-flattened blocks
        facts[int(m.group(1))] = re.sub(r'\s+', ' ', b)
want = {1: ('agent context', 'chore'), 2: ('agent context', 'chore'),
        3: ('agent context', 'chore'), 4: ('dev', 'dep'),
        7: ('dev', 'feat'), 10: ('dev', 'feat'), 11: ('dev', 'feat'), 12: ('dev', 'feat')}
rc = 0
for n, toks in want.items():
    b = facts.get(n, '')
    for t in toks + ('Services:', 'Type:'):
        if t not in b:
            print(f"L{n}: entry block lacks {t!r} — checklist answers derive from the appendix tokens")
            rc = 1
sys.exit(rc)
PY
  if ! python3 "$TMP/appendix.py" "$TMP/appendix.txt"; then
    fail "t2[C07 AC3]: an appendix CREATE entry lost its Services/Type tokens (reason above)"; fi
  # Destination sentence — appendix lines wrap mid-sentence, match the
  # flattened text.
  if ! python3 - "$TMP/appendix.txt" <<'PY'
import re, sys
flat = re.sub(r'\s+', ' ', open(sys.argv[1]).read())
assert 'Destination for every CREATE: the **Inbox** list in the Backlog swimlane' in flat, 'destination sentence drifted'
assert re.search(r'never the prefetched block', flat), 're-resolve posture drifted'
PY
  then fail "t2[C07]: the appendix destination sentence moved — ledger cards land in Inbox (Backlog swimlane), id re-resolved at use time, never the prefetched block"; fi
  ok "t2[C07 AC1/AC2]: appendix keeps 12 entries — 8 CREATE (L1-L4,7,10-12) / 4 CITE (L5,6,8,9), per-entry Services+Type facts, Inbox destination"
fi

# --- t3: the follow-up protocol the coord executes under (C03-owned text) --------
if want t3; then
  for f in "$BOARDS_SRC" "$BOARDS_GEN"; do
    [ -f "$f" ] || fail "t3: $f missing (harness fault)"
    grep -qE '^#{2,4}[[:space:]].*Follow-?up cards' "$f" \
      || fail "t3[C07 preconditions]: $f has no Follow-up cards section yet — C07 must run under C03's landed protocol (policy before use; designed red before C03, and a red HERE in wave 2 means the dependency order was violated)"
    if ! python3 - "$f" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'(?ms)^#+[^\n]*Follow-?up cards[^\n]*\n(.*?)(?=^#{1,4}[^\n]*$|\Z)', text)
if not m:
    sys.exit(1)
t = m.group(1).lower()
for needle in ('post-research', 'test', 'inbox', 'backlog', 'list_lists', 'except'):
    if needle not in t:
        print(f"follow-up protocol lacks {needle!r}"); sys.exit(1)
PY
    then fail "t3[C07 AC3]: $f's follow-up protocol is incomplete for C07 execution (timing before the test session, Inbox-in-Backlog destination + list_lists re-resolve, parent labels except Research — reason above)"; fi
  done
  ok "t3[C07]: boards follow-up protocol landed (C03) — C07's coord execution has its policy home"
fi

# --- t4: superseded destinations must not leak into the C07 surfaces -------------
if want t4; then
  grep -qiE 'low priority' "$RUNBOOK" \
    && fail "t4[C07]: the runbook sends ledger cards to Low Priority — the batched-round ruling repointed ALL follow-up/ledger cards to Inbox (Backlog swimlane)"
  python3 - "$RUNBOOK" <<'PY' || fail "t4[C07 AC2]: a Review-destination leak or a missing never-mutate posture in the runbook (reason above)"
import re, sys
t = open(sys.argv[1]).read().lower()
# 'Review' legitimately appears as a re-listed cite-target and a
# friction-history contrast; a DESTINATION is 'lands/moves/creates into
# Review' — assert no destination-shaped Review phrase.
if re.search(r'(lands?|creat\w+|mov\w+)\s+\w*\s*\**review\**', t):
    print("destination-shaped Review phrase in the runbook"); sys.exit(1)
if 'cite-only' not in t and 'never' not in t:
    print("the never-mutate-existing-cards posture vanished"); sys.exit(1)
PY
  ok "t4[C07 AC2]: no superseded destination leaks into the ledger runbook; cite-only posture present"
fi

printf 'PASS: cf-90 C07 ledger policy/runbook checks (%d ok)\n' "$checks"
