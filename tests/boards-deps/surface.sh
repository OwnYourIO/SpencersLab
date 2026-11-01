#!/usr/bin/env bash
# boards skill — pickup dependency gate, preload consumer, grouped siblings,
# follow-up label/lineage updates (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C05).
#
# Pins chunks/C05.md "## Tests": windowed grep contracts over
# .rulesync/skills/boards/SKILL.md (SOURCE — the mirror must equal it after
# regeneration) for AC1-AC4: the dependency gate inside Card pickup, the
# claim-time preload consumer with its lean STATE.json stamp and degrade
# law, the new grouped-sibling section, and the Follow-up cards updates
# (set_card_labels-with-degrade + parent_id lineage, OQ1 parentId-only).
#
# Section anchors ARE the interface (same-commit rule): C05's edits land the
# gate as text inside `## Card pickup`, the consumer near the Board context
# block section, and a new section whose heading names siblings. A red says
# the landed text lacks a pinned fact, or dev wrote it somewhere else than
# the chunk says — the failure message names the expected home.
#
# The tool names pinned here must match C01's landed signatures exactly
# (preload_board, set_card_labels, parent_id, list ids of the dependency
# tools) — the wekan-mcp skill's failure-mode playbook's exact drift failure
# this chunk warns about.
#
# AC trace: t1[C05 AC1 — gate shape: blocking types, Test/Finished by TITLE
# at runtime, _id keying, both edge directions, archived exemption, audit
# reporting; negatives: no hardcoded list ids in the file, no card_number
# keying] t2[AC2 — consumer: claim-time call site named, NOT the hook; lean
# stamp keys; per-card get_card kept for the claimed card; degrade to
# today's reads + gate-skip] t3[AC3 — grouped flow: Executing-at-start /
# Review-at-end, coord-owned, ride-the-claim, plan-enumerated degrade;
# trigger names blocking edges ONLY (no parentId/kind-1, OQ1 negative)]
# t4[AC4 — Follow-up cards: set_card_labels with tools/list-gated degrade,
# parent_id passed on creation] t5[source↔mirror — the regenerated mirror
# carries every pinned passage; rulesync output never hand-edited].
#
# Red posture: DESIGNED RED until C05 dev lands (verified at authoring
# 2026-11-01: no dependency-gate / preload / grouped-sibling / set_card_labels
# text in the boards skill). The file-wide negatives (no hardcoded ids) are
# GREEN at base and HOLD. cf90-ledger's re-pin duty for the old follow-up
# wording belongs to C05's own commit.
#
# Usage:
#   bash tests/boards-deps/surface.sh            # t1..t5
#   bash tests/boards-deps/surface.sh t3         # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC=".rulesync/skills/boards/SKILL.md"
GEN=".opencode/skills/boards/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-5]$ ]] || fail "unknown check id '$a' (expected t1..t5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/boards-deps-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# Section extractor + OR-group minimum-window checker (needle groups are
# alternation lists: the window must contain one match of EVERY group).
cat >"$TMP/sec.py" <<'PY'
import re, sys

def section(path, heading_pat):
    text = open(path).read()
    m = re.search(rf"(?ims)^#{{2,4}}[^\n]*{heading_pat}[^\n]*\n(.*?)(?=^#{{1,4}} |\Z)", text)
    return m.group(0) if m else None

def window(hay, groups, span):
    pts = []
    for gi, alts in enumerate(groups):
        found = False
        for alt in alts:
            for m in re.finditer(re.escape(alt), hay, re.I):
                pts.append((m.start(), gi)); found = True
        if not found:
            return None, [a for a in alts]
    pts.sort()
    need = len(groups)
    cnt, have, best, left = {}, 0, None, 0
    for right, (pos, g) in enumerate(pts):
        if cnt.get(g, 0) == 0:
            have += 1
        cnt[g] = cnt.get(g, 0) + 1
        while have == need:
            s = pos - pts[left][0]
            if best is None or s < best:
                best = s
            lg = pts[left][1]
            cnt[lg] -= 1
            if cnt[lg] == 0:
                have -= 1
            left += 1
    if best is not None and best <= span:
        return best, None
    return best, "gap too wide"
PY

# Every leg runs over BOTH source and mirror; t5 is the strict equality pin.
check_pair() { # check_pair <tlabel> <heading-pat|FULL> <span> <group|~sep>...
  local label="$1" heading="$2" span="$3"; shift 3
  local file
  for file in "$SRC" "$GEN"; do
    [ -f "$file" ] || fail "harness: $file missing"
    python3 - "$TMP/sec.py" "$file" "$heading" "$span" "${@//§/|}" <<'PY' || fail "$label[$file]: text pin failed (reason above)"
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
path, heading, span = sys.argv[2], sys.argv[3], int(sys.argv[4])
groups = [[a for a in g.split("|") if a] for g in sys.argv[5:]]
if heading == "FULL":
    hay = open(path).read()
    missing_heading = None
else:
    hay = ns["section"](path, heading)
    if hay is None:
        print(f"no section heading matching {heading!r} — C05's text must live where the chunk says (designed red before C05 dev if new, or dev wrote it outside the named section)")
        sys.exit(1)
best, why = ns["window"](hay, groups, span)
if best is None:
    print(f"needle group {why!r} absent from the section — the pinned contract fact is not in the landed text")
    sys.exit(1)
if why:
    print(f"no single passage of {span} chars covers all needle groups (min span {best}) — the contract facts must read as one passage, not file-wide scatter")
    sys.exit(1)
print("ok")
PY
  done
}

# --- t1: the pickup dependency gate (C05 T1 / AC1) ----------------------------------
if want t1; then
  check_pair "t1[C05 AC1]" "Card pickup" 2600 \
    'dependen' 'is-blocked-by' 'blocks' \
    || fail "t1[C05 AC1]: the Card-pickup dependency gate does not name the blocking edge types"
  check_pair "t1[C05 AC1]" "Card pickup" 2600 \
    'Test' 'Finished' 'skip' 'title' \
    || fail "t1[C05 AC1]: the gate text lacks the target-list condition (a dependency satisfied = its card in Test OR Finished; list ids resolved by TITLE at runtime, never hardcoded)"
  check_pair "t1[C05 AC1]" "Card pickup" 2600 \
    '_id' 'card_number|cardNumber' \
    || fail "t1[C05 AC1]: the gate must key on card _id and name card_number as display-only identity (RESEARCH C2 — numbers re-counter on cross-board moves)"
  check_pair "t1[C05 AC1]" "Card pickup" 2600 \
    'inverse' 'archived' \
    || fail "t1[C05 AC1]: the gate text must honor BOTH edge directions (blocks stored on the dependency side via WeKan's inverse map) and exempt archived dependency targets"
  check_pair "t1[C05 AC1]" "Card pickup" 2600 \
    'RESULT' 'blocking' \
    || fail "t1[C05 AC1]: skipped candidates must be reported (card id + blocking card id + its list) in the RESULT/claim comment so the walk is auditable"
  python3 - "$SRC" <<'PY' || fail "t1[C05 AC1]: the gate does not pin that ONLY blocks/is-blocked-by edges gate pickup (related-to/fixes/duplicates never do — plan OQ2 ruling)"
import re, sys
sec = re.search(r"(?ms)^## Card pickup.*?(?=^## |\Z)", open(sys.argv[1]).read()).group(0)
if not re.search(r"related-to|fixes|duplicates", sec):
    sys.exit(1)
print("ok")
PY
  grep -qF 'jNYNdCPPkX8Bs95s4' "$SRC" && fail "t1[C05 AC1 negative]: the boards SOURCE hardcodes the live Test list id — ids resolve from the board-context block/preload map BY TITLE; plan-time ids ride STATE.json kickoff.board_context for traceability" || true
  grep -qF 'DHw56fMKy3qyfudz4' "$SRC" && fail "t1[C05 AC1 negative]: the boards SOURCE hardcodes the live Finished list id — same rule" || true
  ok "t1[C05 AC1]: dependency-gate contracts pinned in Card pickup (both files); no hardcoded ids file-wide"
fi

# --- t2: the preload consumer at claim (C05 T2 / AC2) --------------------------------
if want t2; then
  check_pair "t2[C05 AC2]" "Board context" 1800 \
    'preload_board' 'pipeline_claim' \
    || fail "t2[C05 AC2]: no preload consumer passage at the claim-time call site near the Board context block section (the coord calls preload_board ONCE after pipeline_claim — plan OQ3 ruling)"
  check_pair "t2[C05 AC2]" "Board context" 1800 \
    'preload_board' 'not the hook|never the hook' \
    || fail "t2[C05 AC2]: the consumer text must state the hook is NOT the call site (the 8 s board-context hook budget stays untouched — one of these phrasings, co-located with preload_board, is the pin)"
  python3 - "$SRC" "$GEN" <<'PY' || fail "t2[C05 AC2]: the preload/hook co-location pin failed (reason above)"
import re, sys
for path in sys.argv[1:]:
    t = open(path).read()
    m = re.search(r"(?ms)^## Board context.*?(?=^## |\Z)", t)
    if not m:
        print(f"{path}: no Board context section"); sys.exit(1)
    sec = m.group(0)
    for alt in ("not the hook", "never the hook"):
        i = sec.lower().find(alt)
        if i >= 0:
            break
    else:
        print(f"{path}: neither 'not the hook' nor 'never the hook' in the section"); sys.exit(1)
    if "preload_board" not in sec[max(0, i-900):i+900]:
        print(f"{path}: the hook-exclusion sentence is not co-located with preload_board"); sys.exit(1)
print("ok")
PY
  check_pair "t2[C05 AC2]" "Board context" 1800 \
    'preload' 'degraded' 'STATE.json' \
    || fail "t2[C05 AC2]: the lean preload stamp {preload: {at, tool, cards, degraded}} under STATE.json kickoff.board_context is not pinned — the full card map must NOT persist to STATE.json"
  check_pair "t2[C05 AC2]" "Board context" 2400 \
    'tools/list' 'absent' 'get_card' \
    || fail "t2[C05 AC2]: the degrade law is missing — probe tools/list first; preload_board absent ⇒ today's per-list reads unchanged + the gate skipped with a RESULT note, and the per-candidate get_card confirmation stays for the CLAIMED card only"
  ok "t2[C05 AC2]: preload consumer pinned — claim-time call site, hook exclusion, lean stamp, degrade law"
fi

# --- t3: the grouped-sibling flow section (C05 T3 / AC3) ------------------------------
if want t3; then
  [ -n "$(python3 - "$TMP/sec.py" "$SRC" "sibling" <<'PY'
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
print(ns["section"](sys.argv[2], sys.argv[3]) or "")
PY
  )" ] || fail "t3[C05 AC3]: $SRC has no grouped-sibling section (a heading naming 'sibling'/'siblings') — C05 T3 adds it as its own section so later tickets can cite it (designed red before C05 dev)"
  check_pair "t3[C05 AC3]" "sibling" 2400 \
    'Executing' 'Review' 'summary comment' \
    || fail "t3[C05 AC3]: the grouped flow must pin siblings-to-Executing-at-start / siblings-to-Review-at-end with one summary comment each (coord-owned moves)"
  check_pair "t3[C05 AC3]" "sibling" 2400 \
    'claim' 'never' \
    || fail "t3[C05 AC3]: the ride-the-claim rule is missing — siblings run under the run's OWN claim, never claimed separately (one session, one card; the walk skips Executing so no double-pick)"
  check_pair "t3[C05 AC3]" "sibling" 2400 \
    'is-blocked-by' 'blocks' \
    || fail "t3[C05 AC3]: the grouping trigger must name the blocking Red Strings edge types (kinds 2+3)"
  check_pair "t3[C05 AC3]" "sibling" 2400 \
    'plan-enumerated' 'degrade' \
    || fail "t3[C05 AC3]: the degrade path is missing — until edges exist, a run may operate from a plan-enumerated id list (this ticket's first instance does exactly that)"
  python3 - "$SRC" <<'PY' || fail "t3[C05 AC3/OQ1 negative]: the sibling section lets parentId/kind-1 lineage read as a grouping trigger (the batched ruling makes follow-up lineage parentId-ONLY — it never groups)"
import re, sys
sec = re.search(r"(?ms)^#{2,3}[^\n]*sibling[^\n]*\n(.*?)(?=^#{1,4} |\Z)", open(sys.argv[1]).read(), re.I).group(0)
for line in sec.splitlines():
    if re.search(r"parent", line, re.I) and re.search(r"trigger|group", line, re.I) \
       and not re.search(r"never|not|no\b|exclude|only", line, re.I):
        print(f"affirmative parent-as-trigger line: {line.strip()[:100]}"); sys.exit(1)
print("ok")
PY
  ok "t3[C05 AC3]: grouped-sibling flow pinned — moves, ride-the-claim, degrade path, blocking-edge-only trigger"
fi

# --- t4: follow-up cards — set_card_labels + parent_id (C05 T4 / AC4) -----------------
if want t4; then
  check_pair "t4[C05 AC4]" "Follow-?up cards" 1500 \
    'set_card_labels' 'tools/list' \
    || fail "t4[C05 AC4]: the Follow-up cards section must use set_card_labels for parent-label inheritance, gated on the tools/list probe with the comment line as the until-deployed degrade (AD-74 retirement)"
  check_pair "t4[C05 AC4]" "Follow-?up cards" 1500 \
    'parent_id' 'create_card' \
    || fail "t4[C05 AC4]: follow-up creation must pass parent_id to create_card — the OQ1 ruling: parentId is the ONLY follow-up representation (no dependency edge drawn, none expected back)"
  check_pair "t4[C05 AC4]" "Follow-?up cards" 1500 \
    'labels to apply' \
    || fail "t4[C05 AC4]: the comment-line degrade must STAY documented (it is the pre-deploy path) — retiring the WORDING while set_card_labels is still undeployed would leave no degrade"
  ok "t4[C05 AC4]: follow-up protocol carries set_card_labels-with-degrade + parent_id lineage (AD-74 cite intact)"
fi

# --- t5: source↔mirror regeneration parity (C05 AC5) ---------------------------------
if want t5; then
  python3 - "$SRC" "$GEN" <<'PY' || fail "t5[C05 AC5]: source↔mirror body equality failed (reason above)"
import re, sys
def body(path):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path).read(), re.S)
    assert m, f"{path}: no frontmatter"
    return re.sub(r"\s+", " ", m.group(2)).strip()
if body(sys.argv[1]) != body(sys.argv[2]):
    print("the generated .opencode/skills/boards mirror's BODY differs from the .rulesync source — run rulesync generate and commit the mirror with the source (never hand-edit)")
    sys.exit(1)
print("ok")
PY
  ok "t5[C05 AC5]: boards source and generated mirror carry the same body (whitespace-normalized)"
fi

printf 'PASS: boards dependency-gate/preload/sibling/follow-up checks (%d ok)\n' "$checks"
