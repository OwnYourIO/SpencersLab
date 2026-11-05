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
# dependency order was violated). t5/t6/t7 were designed red until cf-106
# C05's skill edits landed (they are green in this tree); t8 is a HOLD pin
# that C05 must not move.
#
# AC trace: t1[chunk Tests: the read-back checklist exists and covers AC1-AC5]
# t2[AC1/AC2 content guards — 12 entries, CREATE/CITE split, each CREATE
# names Services+Type, destination Inbox] t3[AC3 preconditions — landing in
# Inbox (Backlog), timing after post-research before the test session,
# parent labels EXCEPT Research, never add_checklist, default_checked-or-
# toggle degrade] t4[AC2 negatives — no Low-Priority/Review destination for
# ledger cards; Inbox is never CREATED by this chunk].
# t5[cf-106 C05 AC1: the five follow-up modes (new session / current session /
#   plan only / Inbox card / none) with none-means-stop semantics, in the role
#   contract AND the boards override, sources + mirrors; fabricated sixth-mode
#   control] t6[C05 AC1 family preference — role contract recommends `new
#   session`, boards recommends `Inbox card`, never both] t7[C05 AC3 — the
#   current-session bound stated once in the role contract (never re-opens a done
#   chunk; new work = a recorded chunk in STATE.json + DECISIONS.md, or a
#   separate ticket) and CITED, not restated, by boards] t8[C05 AC4 HOLD — the
#   standing follow-up rules survive the C05 edit (Inbox in Backlog, list_lists
#   re-resolution, never add_checklist, not-a-run) with a destination-rewrite
#   control].
#
# cf-106 C05 harness repair (2026-11-04, agent-test; dev-proven read-only): t5's
# sixth-mode control ran a sed whose BRE group was never closed, so GNU sed died at
# parse time on any input and the whole suite exited 1 with no assertion having failed.
# The group is closed; no assertion, mode vocabulary, or HOLD leg changed. t8's rename
# fixture also stopped dumping the rewritten skill to stdout (it buried the report in
# ~400 lines of skill prose); it keeps its strip-target guard.
#
# Offline-deterministic: text pins over the repo tree only. No dev-boards
# call, no OpenChamber, no network — the live read-back legs run in
# production during the coord-executed C07 pass, per this runbook.
#
# Usage:
#   bash tests/cf90-ledger/surface.sh            # t1..t8
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
  for i in 1 2 3 4 5 6 7 8; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-8]$ ]] || fail "unknown check id '$a' (expected t1..t8)"
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

# --- t5-t8: cf-106 C05 — the five follow-up modes in both coordinator families --
# The plan's F1-F4 land as these ids (this suite numbers its legs t-n). One
# shipped checker, four modes, plus fabricated controls for the vocabulary and
# the recommendation arms.
cat >"$TMP/friction.py" <<'PYEOF'
import re, sys

_re = re
path, mode = sys.argv[1], sys.argv[2]
text = open(path).read()
FIVE = ["new session", "current session", "plan only", "Inbox card", "none"]
SIXTH = ["defer to owner", "do it here", "owner card", "later", "record only", "ticket only"]

def passage(t):
    # the friction-follow-up passage: role-coord's step 11, or the boards
    # override section, whichever exists — both are the contract surfaces.
    # Step 11 is the last numbered step, so the span is bounded at the next
    # `## ` heading: unbounded it ran line 35 -> EOF (12.3 KB, ~49% of the
    # contract) and the sixth-mode ban policed the Stage-gate/Research/Git
    # prose for ordinary words like `later` (C05 landmine, narrowed in
    # cf-106 wave 3).
    m = re.search(r"(?ms)^11\.[^\n]*Friction follow-up.*?(?=^\d+\.\s|^## |\Z)", t)
    if m:
        return m.group(0)
    m = re.search(r"(?ms)^#+[^\n]*Friction follow-up[^\n]*\n.*?(?=^#+ |\Z)", t)
    if m:
        return m.group(0)
    return ""

body = passage(text)
if not body:
    print(f"{path}: no friction-follow-up passage (step 11 or the boards override section) — nothing to check")
    sys.exit(1)

# The mode list: the maximal run of consecutive same-kind list items (all
# numbered or all bulleted) that leads with at least four of the five known
# mode names. A marker-kind switch (bullets -> numbered) starts a new list,
# so the question bullets above the mode list do not dilute the count.
NUM = re.compile(r"(?m)^\s*\d+[\.)]\s+")
BUL = re.compile(r"(?m)^\s*[-*]\s+")

def mode_run(b):
    lines = b.split("\n")
    kind = []
    for ln in lines:
        if NUM.match(ln):
            kind.append("n")
        elif BUL.match(ln):
            kind.append("b")
        else:
            kind.append(None)
    seqs = []
    for i, k in enumerate(kind):
        if k is None:
            continue
        if seqs and seqs[-1][1] == k and i == seqs[-1][0][-1] + 1:
            seqs[-1][0].append(i)
        else:
            seqs.append(([i], k))
    def lead(i):
        txt = (NUM if kind[i] == "n" else BUL).sub("", lines[i], count=1).lstrip("*").strip()
        return txt
    best = None
    for idxs, _k in seqs:
        known = sum(1 for i in idxs if any(lead(i).startswith(f) for f in FIVE))
        if known >= 4 and (best is None or known > best[1]):
            best = (idxs, known)
    if best is None:
        return None, "no mode-list run carries at least four of the five known mode names — the enumeration cannot be counted"
    return best[0], None

run, run_err = mode_run(body)

bad = []
if mode == "vocab":
    missing = [m for m in FIVE if m not in body]
    if missing:
        bad.append(f"modes absent: {missing}")
    if run_err:
        bad.append(run_err)
    elif len(run) != 5:
        bad.append(f"the mode enumeration carries {len(run)} items — the offer is EXACTLY five options; count the listed entries, not just the known names (C05 N3)")
    # Token belt, scoped to the mode run: a stray `later` in prose outside the
    # list is not a sixth mode, and `collateral`/`bilateral` must not trip the
    # ban (word-boundary match for `later`, C05 landmine).
    region_lines = body.split("\n")
    region = "\n".join(region_lines[run[0]:run[-1] + 1]) if run else body
    for s in SIXTH:
        hit = re.search(r"\blater\b", region, re.I) if s == "later" else re.search(_re.escape(s), region, re.I)
        if hit:
            bad.append(f"a sixth mode appears ({[s]}) — the offer carries EXACTLY five options")
    if not re.search(r"\bnone\b[^\n]{0,160}(stop|nothing)", body, re.I):
        bad.append("the `none` option's semantics (check nothing → stop) are not stated next to the option")
elif mode == "recommend":
    want = sys.argv[3]
    other = "Inbox card" if want == "new session" else "new session"
    # The recommendation is a property of a MODE ENTRY, not of the passage: the
    # entry that carries the word "recommend" must be the family's own mode, and
    # the other family's mode must not be the recommended one here.
    items = _re.split(r"(?m)^\s*(?:\d+[.)]|[-*])\s+", body)
    rec_items = [it for it in items if _re.search(r"recommend", it, _re.I)]
    if not rec_items:
        bad.append("the passage never says which mode is recommended")
    else:
        def lead(t):
            hits = [(t.find(f), f) for f in FIVE if f in t]
            return min(hits)[1] if hits else None
        leads = [lead(it) for it in rec_items]
        if want not in leads:
            bad.append(f"no recommended entry names {want!r} (recommended entries lead with {leads})")
        if any(l == other and want not in it for l, it in zip(leads, rec_items)):
            bad.append(f"the recommended entry is {other!r} — this family recommends {want!r}")
elif mode == "bound":
    if "current session" not in body:
        bad.append("the `current session` mode is not described")
    at = body.find("current session")
    window = body[at:at + 1400]
    if "done" not in window or not re.search(r"never[^\n]{0,120}(re-?open)", window, re.I):
        bad.append("the `current session` bound is missing: it must state it never re-opens a done chunk of the current plan")
    if not re.search(r"STATE\.json|DECISIONS\.md|separate ticket|new chunk", window):
        bad.append("the bound is incomplete: new work must be recorded as a new chunk in STATE.json (+ DECISIONS.md) or become a separate ticket")
elif mode == "cite":
    # Entry-scoped, exactly as `recommend`: the citation is a property of the
    # `current session` mode ENTRY. Anchoring on the first mention (the mode
    # list in the intro) let an entry that restates the bound pass while the
    # intro kept citing (C05 N4).
    items = _re.split(r"(?m)^\s*(?:\d+[.)]|[-*])\s+", body)
    def lead(it):
        hits = [(it.find(f), f) for f in FIVE if f in it]
        return min(hits)[1] if hits else None
    entry = next((it for it in items if lead(it) == "current session"), None)
    if entry is None:
        bad.append("no mode entry for `current session` — the boards override must name every mode it asks about")
    else:
        if not _re.search(r"pipeline-role-coord|role contract|step 11|cite", entry, re.I):
            bad.append(f"the `current session` entry never cites the role contract's bound ({entry.strip()[:100]!r}) — cite, do not drop the pointer")
        if _re.search(r"never[^\n]{0,120}(re-?open)|STATE\.json|DECISIONS\.md line|separate ticket", entry, re.I):
            bad.append("the `current session` entry restates the bound's content — the boards override cites, it does not restate (AC3)")
elif mode == "hold":
    if "Inbox" not in body:
        bad.append("the Inbox destination is gone")
    if "list_lists" not in text:
        bad.append("the Inbox id re-resolution via list_lists is gone")
    if not re.search(r"(never|do NOT|don't)[^\n]{0,40}`?add_checklist", body, re.I):
        bad.append("the never-add_checklist prohibition is gone")
    if not re.search(r"not a run", body, re.I):
        bad.append("the 'this is not a run' posture is gone")
else:
    print(f"unknown mode {mode}"); sys.exit(2)

if bad:
    print("; ".join(bad)); sys.exit(1)
PYEOF

RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"

if want t5; then
  for f in "$RC_SRC" "$RC_GEN" "$BOARDS_SRC" "$BOARDS_GEN"; do
    python3 "$TMP/friction.py" "$f" vocab \
      || fail "t5[cf-106 C05 AC1]: $f does not carry the five-mode vocabulary with the none-means-stop semantics (red before C05's skill edit; source and mirror must move together)"
  done
  # Control: a fabricated sixth option reddens the same checker. The BRE group must
  # close — an unterminated `\(…` kills sed at parse time on ANY input, which read as
  # a suite failure rather than as a broken fixture (cf-106 C05 dev round). The
  # mutant is planted IN the mode list (after the `none` entry): the count arm sees
  # a sixth item, the scoped token belt sees its name.
  sed 's/^\([[:space:]]*5\.[[:space:]]\*\*none\*\*.*\)$/\1\n      6. **defer to owner** — hand the item to the owner./' "$RC_SRC" >"$TMP/sixth.md" \
    || fail "t5[cf-106 C05]: the sixth-mode fabricator itself failed (fixture fault — a broken sed/awk expression reads as a suite failure, not as a broken control)"
  grep -q 'hand the item to the owner' "$TMP/sixth.md" \
    || fail "t5[cf-106 C05]: NEGATIVE CONTROL FAILED — could not fabricate a sixth mode in the copy (the control proves nothing)"
  python3 "$TMP/friction.py" "$TMP/sixth.md" vocab >"$TMP/sixth.out" 2>&1 \
    && fail "t5[cf-106 C05]: NEGATIVE CONTROL FAILED — a passage with a sixth mode still passes the exactly-five arm"
  grep -qE "carries 6 items|a sixth mode appears" "$TMP/sixth.out" \
    || fail "t5[cf-106 C05]: control 'sixth' was caught by the wrong arm: $(head -1 "$TMP/sixth.out")"
  # C05 N3: a sixth mode with an UNCATALOGUED name passes the token belt by
  # construction — only the structural count catches it, and the count must be
  # the arm that bites.
  sed 's/^\([[:space:]]*5\.[[:space:]]\*\*none\*\*.*\)$/\1\n      6. **escalate to the steering group** — hand the item up the chain./' "$RC_SRC" >"$TMP/sixth-uncat.md" \
    || fail "t5[cf-106 C05 N3]: the uncatalogued sixth-mode fabricator itself failed (fixture fault)"
  grep -q 'hand the item up the chain' "$TMP/sixth-uncat.md" \
    || fail "t5[cf-106 C05 N3]: NEGATIVE CONTROL FAILED — could not fabricate the uncatalogued sixth mode (the control proves nothing)"
  python3 "$TMP/friction.py" "$TMP/sixth-uncat.md" vocab >"$TMP/sixth-uncat.out" 2>&1 \
    && fail "t5[cf-106 C05 N3]: NEGATIVE CONTROL FAILED — a sixth mode with an uncatalogued name still passes: 'exactly five' is present-plus-token-blacklist, not a count"
  grep -qF "carries 6 items" "$TMP/sixth-uncat.out" \
    || fail "t5[cf-106 C05 N3]: control 'sixth-uncat' was caught by the wrong arm: $(head -1 "$TMP/sixth-uncat.out")"
  # C05 landmine (narrowed, cf-106 wave 3): legitimate prose OUTSIDE the mode
  # run must not redden the ban — a `later` in the Stage-gate paragraph, and
  # `collateral` (an embedded, non-word `later`) inside a mode entry, both pass
  # the vocab arm.
  sed '/^\*\*Stage gate /s/$/ The later chunks may extend this gate./' "$RC_SRC" >"$TMP/later-outside.md" \
    || fail "t5[cf-106 C05]: the outside-span fabricator itself failed (fixture fault)"
  grep -q 'The later chunks' "$TMP/later-outside.md" \
    || fail "t5[cf-106 C05]: NEGATIVE CONTROL FAILED — could not fabricate the outside-span `later` (the control proves nothing)"
  python3 "$TMP/friction.py" "$TMP/later-outside.md" vocab >/dev/null 2>&1 \
    || fail "t5[cf-106 C05]: a legitimate `later` in the Stage-gate paragraph (outside the mode run) reddens the sixth-mode ban — the span is still not narrowed"
  sed 's/^\([[:space:]]*1\.[[:space:]]\*\*new session\*\*.*\)$/\1 A collateral mode never exists./' "$RC_SRC" >"$TMP/collateral-in.md" \
    || fail "t5[cf-106 C05]: the collateral fabricator itself failed (fixture fault)"
  grep -q 'A collateral mode' "$TMP/collateral-in.md" \
    || fail "t5[cf-106 C05]: NEGATIVE CONTROL FAILED — could not fabricate the embedded `later` (the control proves nothing)"
  python3 "$TMP/friction.py" "$TMP/collateral-in.md" vocab >/dev/null 2>&1 \
    || fail 't5[cf-106 C05]: `collateral` (an embedded, non-word `later`) inside a mode entry reddens the ban — the ban must match the word, not the substring'
  ok "t5[cf-106 C05 AC1]: the five modes (new session / current session / plan only / Inbox card / none) with the none-means-stop semantics are stated in the role contract and the boards override, sources and mirrors alike — the mode list is COUNTED (a sixth entry under any name reddens), the token belt is scoped to that run, and \`later\`/\`collateral\` outside and inside it pass"
fi

if want t6; then
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/friction.py" "$f" recommend "new session" \
      || fail "t6[cf-106 C05 AC1]: $f does not recommend \`new session\` for the plain agent-coord family (red before C05's skill edit)"
  done
  for f in "$BOARDS_SRC" "$BOARDS_GEN"; do
    python3 "$TMP/friction.py" "$f" recommend "Inbox card" \
      || fail "t6[cf-106 C05 AC1]: $f does not recommend \`Inbox card\` on board-family runs (red before C05's skill edit)"
  done
  python3 "$TMP/friction.py" "$BOARDS_SRC" recommend "new session" >/dev/null 2>&1 \
    && python3 "$TMP/friction.py" "$BOARDS_SRC" recommend "Inbox card" >/dev/null 2>&1 \
    && fail "t6[cf-106 C05]: NEGATIVE CONTROL FAILED — the boards override recommends BOTH families' defaults, so the family-preference arm cannot fail"
  ok "t6[cf-106 C05 AC1]: the recommendation is family-differentiated — new session leads in the role contract, Inbox card leads in the boards override"
fi

if want t7; then
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/friction.py" "$f" bound \
      || fail "t7[cf-106 C05 AC3]: $f does not bound the \`current session\` mode (never re-opens a done chunk; new work is a recorded chunk in STATE.json plus a DECISIONS.md line, or a separate ticket) — red before C05's skill edit"
  done
  for f in "$BOARDS_SRC" "$BOARDS_GEN"; do
    python3 "$TMP/friction.py" "$f" cite \
      || fail "t7[cf-106 C05 AC3]: $f never cites the role contract's bound for \`current session\` (the boards override cites, it does not restate)"
  done
  # C05 N4 control: an entry that restates the bound (while the intro keeps
  # citing) must redden the entry-scoped cite arm — the old first-mention
  # window anchored on the mode list and let exactly this shape pass.
  sed 's/states for that mode (cite; this section does not restate it)\./states for that mode (cite; this section does not restate it). The bound: it never re-opens a done chunk of the current plan, and new work lands as a recorded chunk in STATE.json plus a DECISIONS.md line, or a separate ticket./' "$BOARDS_SRC" >"$TMP/cite-restate.md" \
    || fail "t7[cf-106 C05 N4]: the restate-cite fabricator itself failed (fixture fault)"
  grep -q 'never re-opens a done chunk' "$TMP/cite-restate.md" \
    || fail "t7[cf-106 C05 N4]: NEGATIVE CONTROL FAILED — could not fabricate the restating entry (the control proves nothing)"
  python3 "$TMP/friction.py" "$TMP/cite-restate.md" cite >"$TMP/cite-restate.out" 2>&1 \
    && fail "t7[cf-106 C05 N4]: NEGATIVE CONTROL FAILED — a boards copy restating the bound in the entry still passes: the cite arm anchors on the list, not the entry"
  grep -qF "restates the bound's content" "$TMP/cite-restate.out" \
    || fail "t7[cf-106 C05 N4]: control 'cite-restate' was caught by the wrong arm: $(head -1 "$TMP/cite-restate.out")"
  ok "t7[cf-106 C05 AC3]: the current-session bound is stated once in the role contract and cited by the boards override — entry-scoped, with a restating-entry mutant reddening the arm"
fi

if want t8; then
  for f in "$BOARDS_SRC" "$BOARDS_GEN"; do
    python3 "$TMP/friction.py" "$f" hold \
      || fail "t8[cf-106 C05 AC4]: $f lost one of the standing follow-up rules (Inbox destination, the list_lists re-resolution, the never-add_checklist prohibition, or the not-a-run posture) — C05 changes the question and the mode branches only"
  done
  python3 - "$BOARDS_SRC" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
# Guard only: the rename control below needs a destination token to rewrite. Writing
# the renamed copy to stdout would bury the suite's own report in skill prose.
out, n = re.subn(r"Inbox", "Review", text, count=1)
if n == 0:
    print("fixture: no Inbox mention to strip in the real skill (the live arm reddens first)"); sys.exit(1)
PY
  python3 - "$BOARDS_SRC" "$TMP/boards-no-inbox.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
out, n = re.subn(r"Inbox", "Low Priority", text)
assert n, "fixture: no Inbox mention to strip"
open(sys.argv[2], "w").write(out)
PY
  python3 "$TMP/friction.py" "$TMP/boards-no-inbox.md" hold >/dev/null 2>&1 \
    && fail "t8[cf-106 C05]: NEGATIVE CONTROL FAILED — a boards override with every Inbox destination renamed still passes the HOLD arm"
  ok "t8[cf-106 C05 AC4]: the standing follow-up rules survive in both boards trees (Inbox in Backlog, list_lists re-resolution, never add_checklist, not a run), and a destination rewrite is caught"
fi

printf 'PASS: cf-90 C07 ledger policy/runbook checks (%d ok)\n' "$checks"
