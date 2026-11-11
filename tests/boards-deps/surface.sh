#!/usr/bin/env bash
# boards skill — pickup dependency gate, preload consumer, grouped siblings,
# follow-up label/lineage updates (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C05).
#
# Pins cf-96 C05 + cf-124 C06/C08 "## Tests": windowed grep contracts over
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
# AC trace: t1[cf-124 C06 AC1-AC3 — gate shape INVERTED: related-to sole gating
# type, source-is-dependent direction, blocks/is-blocked-by/fixes/duplicates
# enumerated non-gating with a negative bar, satisfaction set/_id keying/reporting
# unchanged, pickup-only scope, mutual/cycle never-gates-and-reports; negatives:
# no hardcoded list ids, no blocks-gates sentence] t2[AC2 — consumer: claim-time
# call site named, NOT the hook; lean stamp keys; per-card get_card kept for the
# claimed card; degrade to today's reads + gate-skip] t3[cf-124 C06 AC4 — grouped
# flow: Executing-at-start / Review-at-end, coord-owned, ride-the-claim,
# plan-enumerated degrade; trigger = INBOUND related-to, outbound never a trigger,
# fixes + parent_id never grouping (negative), settled rule cites membership
# authority] t4[cf-124 C08 AC1/AC2 — follow-up lineage = parent_id AND a
# child→parent fixes edge, non-effects + UPSERT re-run, parentId-ONLY supersession
# bar; set_card_labels degrade] t5[source↔mirror — the regenerated mirror carries
# every pinned passage; rulesync output never hand-edited]
# t6[C11 OQ-P2 — degrade law gains the present-but-FAILED branch: a failed
#     call degrades exactly like absence, at most ONE retry (the read is
#     idempotent), never a stall. Needle groups tools/list|fails|retry|
#     idempotent, min-span 261 (plan-sim 238) of 2400, ORIG infeasible on
#     'fails'.]
# t7[C11 OQ-P3 — unresolvable edge end never gates: non-gating|REPORT|
#     deleted/moved away, min-span 117 (plan-sim 105) of 2600 — type-agnostic,
#     survives the C06 rewrite UNCHANGED (a red here means the rewrite leaked
#     into the unresolvable-endpoint rule).]
# t8[C11 OQ-P3 — title-map fallback: block|map|swimlane in one Card-pickup
#     window (the block's map carries only the named swimlane's lists),
#     min-span 38, ORIG infeasible on 'swimlane' in this section. Chosen
#     over the plan's literal 2-group shape because 'block'/'map' alone
#     read green at ORIG (24) — the red/green discipline of this suite
#     demands the swimlane-scope group.]
#
# Red posture (cf-124): t1/t3/t4 DESIGNED RED until C06 (wave 2) and C08 (wave 3)
# land their rewrites — t4 stays red through C06's window because the single
# test session (D21) lands the whole ticket's re-pins in one pass, superseding
# C06's note that t4 stays green "as shipped". t2/t5/t6/t7/t8 are UNCHANGED
# shipped law and stay green. The file-wide negatives (no hardcoded ids) are
# GREEN at base and HOLD.
#
# Usage:
#   bash tests/boards-deps/surface.sh            # t1..t8
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
  for i in 1 2 3 4 5 6 7 8 9; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t([1-9]|1[0-2])$ ]] || fail "unknown check id '$a' (expected t1..t12)"
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

# --- t1: the pickup dependency gate — related-to sole type, source=dependent (C06) --
# cf-96 C05 shipped "blocking edge set is EXACTLY blocks/is-blocked-by". OQ12/
# OQ12b → D24 supersedes it: `related-to` is the ONLY gating type, the stored
# source is the dependent (`A →related-to→ B` ⇒ A waits for B), `blocks`/
# `is-blocked-by` become display-only, mutual/ambiguous pairs never gate and are
# reported, and the gate decides only whether a card may START (a run already
# holding its card reaches Review). Satisfaction set + skip/release/reporting
# + _id keying + no-hardcoded-ids negatives are UNCHANGED shipped law.
if want t1; then
  check_pair "t1[C06 AC1/AC2]" "Card pickup" 2600 \
    'dependen' 'related-to' 'waits for' \
    || fail "t1[C06 AC1]: the gate does not state the direction law (A →related-to→ B means the SOURCE A is the dependent and WAITS FOR B) in one passage (C06 rewrite; related-to sole type, source-is-dependent — designed red before C06 dev)"
  check_pair "t1[C06 AC2]" "Card pickup" 2600 \
    'Test' 'Finished' 'archived' 'skip' 'title' \
    || fail "t1[C06 AC2]: the satisfaction set changed — a prerequisite satisfies when archived OR in a list titled Test or Finished, resolved by TITLE at runtime (Review does NOT satisfy). This is unchanged shipped law; a red here means C06 moved it (it must not)"
  check_pair "t1[C06 AC2]" "Card pickup" 2600 \
    '_id' 'card_number|cardNumber' \
    || fail "t1[C06]: the gate must key on card _id and name card_number as display-only identity (unchanged — RESEARCH C2, numbers re-counter on cross-board moves)"
  check_pair "t1[C06]" "Card pickup" 2600 \
    'inverse|stored only|drawing card' 'archived' \
    || fail "t1[C06 AC1]: the gate does not state that only the DRAWING card stores the edge (no server-side inverse twin) and archived prerequisites are exempt — the both-directions consumer rule collapses to this single-type law (designed red before C06 dev)"
  check_pair "t1[C06 AC3]" "Card pickup" 2600 \
    'start' 'Review' 'already|complete|holding' \
    || fail "t1[C06 AC3]: the gate's SCOPE is missing — it decides only whether a card may START; a run already holding its card completes and hands it to Review, which stays the release point (OQ12b pickup-only; designed red before C06 dev)"
  check_pair "t1[C06 AC2]" "Card pickup" 2600 \
    'mutual|cycle' 'never gate|does not gate|neither gate' 'report' \
    || fail "t1[C06 AC2 mutual-pair]: mutual / cycle pairs must NEVER gate and be REPORTED (the #126↔#140 deadlock preventer — the law, not an edge case). Proven by a separate negative below. Designed red before C06 dev"
  check_pair "t1[C06]" "Card pickup" 2600 \
    'RESULT' 'skip|prerequisit|block' \
    || fail "t1[C06]: skipped candidates must still be REPORTED (candidate _id + far-end _id + its list) in the RESULT/claim comment so the walk is auditable (unchanged reporting duty)"
  # INVERTED sole-type enumeration (was: ONLY blocks/is-blocked-by gate): the
  # section must name related-to as the sole gating type AND enumerate
  # blocks/is-blocked-by as display-only AND fixes/duplicates as never gating.
  python3 - "$SRC" "$GEN" <<'PY' || fail "t1[C06 AC1]: the sole-gating-type + non-gating enumeration is not stated (reason above; designed red before C06 dev)"
import re, sys
for path in sys.argv[1:]:
    sec = re.search(r"(?ms)^#{2,4}[^\n]*Card pickup.*?(?=^#{1,2} |\Z)", open(path).read())
    if not sec:
        print(f"{path}: no Card pickup section"); sys.exit(1)
    s = sec.group(0)
    if not re.search(r"related-to[^.]{0,200}\b(only|sole)\b[^.]{0,60}gat", s, re.I):
        print(f"{path}: related-to is not stated as the ONLY/sole gating type (C06 AC1)"); sys.exit(1)
    for t, rx in (("blocks", r"\bblocks?\b[^.]{0,120}display[- ]only|display[- ]only[^.]{0,120}\bblocks?\b|\bblocks?\b[^.]{0,80}never gat"),
                  ("is-blocked-by", r"is-blocked-by[^.]{0,120}display[- ]only|display[- ]only[^.]{0,120}is-blocked-by|is-blocked-by[^.]{0,80}never gat"),
                  ("fixes", r"fixes[^.]{0,80}never gat|never gat[^.]{0,80}fixes"),
                  ("duplicates", r"duplicates[^.]{0,80}never gat|never gat[^.]{0,80}duplicates")):
        if not re.search(rx, s, re.I):
            print(f"{path}: {t} is not enumerated as non-gating/display-only (C06 AC1 — the plan requires the enumeration, not a 'contains related-to' relaxation)"); sys.exit(1)
print("ok")
PY
  # NEGATIVE bar: reject any sentence that lets `blocks` GATE pickup (the
  # superseded cf-96 OQ2 law). blocks may appear only as display-only here.
  python3 - "$SRC" "$GEN" <<'PY' >/dev/null || fail "t1[C06 AC1 negative]: a sentence still lets \`blocks\`/\`is-blocked-by\` gate pickup — the display-only supersession is incomplete (the old EXACTLY-blocks law survives)"
import re, sys
for path in sys.argv[1:]:
    sec = re.search(r"(?ms)^#{2,4}[^\n]*Card pickup.*?(?=^#{1,2} |\Z)", open(path).read())
    if not sec:
        sys.exit(1)
    for sent in re.split(r"(?<=[.!?])\s+", sec.group(0)):
        if re.search(r"\b(blocks?|is-blocked-by)\b", sent, re.I) and re.search(r"\b(gate|gates|gating|skip|skips|skipped)\b", sent, re.I) \
           and not re.search(r"display[- ]only|never gat|not gat|non-gating|only.{0,40}related-to|sole|supersed|histor|retired|no longer|formerly|was the|old law", sent, re.I):
            sys.exit(1)
print("ok")
PY
  grep -qF 'jNYNdCPPkX8Bs95s4' "$SRC" && fail "t1[C05 AC1 negative]: the boards SOURCE hardcodes the live Test list id — ids resolve from the board-context block/preload map BY TITLE; plan-time ids ride STATE.json kickoff.board_context for traceability" || true
  grep -qF 'DHw56fMKy3qyfudz4' "$SRC" && fail "t1[C05 AC1 negative]: the boards SOURCE hardcodes the live Finished list id — same rule" || true
  ok "t1[C06 AC1-AC3]: gate inverted at equal strictness — related-to sole gating type (direction stated as a lab convention), blocks/is-blocked-by/fixes/duplicates enumerated non-gating with a negative bar against a blocks-gates sentence, satisfaction set + _id keying + reporting unchanged, pickup-only scope, and mutual/cycle pairs never-gate-and-report; no hardcoded ids file-wide"
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
  # cf-106 C06 AC5: the consumer text must name the new payload fields (the
  # checklist state + the swimlane/list titles) next to the tool they describe,
  # and keep the claimed-card get_card carve-out visible.
  check_pair "t2[cf-106 C06 AC5]" "Board context" 1800 \
    'preload_board' 'checklists' \
    || fail "t2[cf-106 C06 AC5]: the boards consumer passage never names the checklists state the enriched preload carries — the skill must teach what the run can stop re-reading (red before C06's skill edit)"
  check_pair "t2[cf-106 C06 AC5]" "Board context" 1800 \
    'preload_board' 'swimlane|title' \
    || fail "t2[cf-106 C06 AC5]: the consumer passage does not mention that swimlane/list TITLES ride the preload (the membership tests stop needing a separate list_lists round-trip)"
  check_pair "t2[cf-106 C06 AC5]" "Board context" 1400 \
    'get_card' 'claimed card' \
    || fail "t2[cf-106 C06 AC5]: the claimed-card get_card carve-out is not visible next to the preload text — the per-card read stays for the claimed card only, and the skill has to say so"
  ok "t2[C05 AC2 + cf-106 C06 AC5]: preload consumer pinned — claim-time call site, hook exclusion, lean stamp, degrade law, and the new-field + claimed-card carve-out wording"
fi

# --- t3: the grouped-sibling flow section (C06 T2 / AC4; was C05 T3 / AC3) -------
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
    || fail "t3[C05 AC3]: the grouped flow must pin siblings-to-Executing-at-start / siblings-to-Review-at-end with one summary comment each (coord-owned moves) — unchanged"
  check_pair "t3[C05 AC3]" "sibling" 2400 \
    'claim' 'never' \
    || fail "t3[C05 AC3]: the ride-the-claim rule is missing — siblings run under the run's OWN claim, never claimed separately (one session, one card; the walk skips Executing so no double-pick) — unchanged"
  check_pair "t3[cf-124 C06 AC4]" "sibling" 2400 \
    'inbound' 'related-to' \
    || fail "t3[cf-124 C06 AC4]: the grouping trigger is not the claimed card's INBOUND related-to edges — D24: cards whose prerequisite is the card this run holds ride the claim; the shipped blocks/is-blocked-by trigger is superseded (designed red before C06 dev)"
  check_pair "t3[cf-124 C06 AC4]" "sibling" 2400 \
    'outbound' 'never' \
    || fail "t3[cf-124 C06 AC4]: the section does not say the OUTBOUND edges are prerequisites and NEVER a grouping trigger (reading the trigger from both ends would pull a card's own prerequisites into its run — the direction flipped with D24; designed red before C06 dev)"
  check_pair "t3[cf-124 C06 AC4]" "sibling" 2400 \
    'fixes' 'never' 'group|trigger' \
    || fail "t3[cf-124 C06 AC4]: fixes/is-fixed-by are not named as never-grouping here — C06 must write it so C08's follow-up edge cannot be read as a trigger (designed red before C06 dev)"
  check_pair "t3[cf-124 C06 AC4]" "sibling" 2400 \
    'settled' 'Test' 'Finished' 'Executing' \
    || fail "t3[cf-124 C06 AC4]: the 'never disturb the settled' rule lost its Test/Finished + Executing exclusions — they survive the rewrite, with the Executing leg citing the membership authority C02 landed instead of re-deriving a lock read"
  check_pair "t3[C05 AC3]" "sibling" 2400 \
    'plan-enumerated' 'degrade' \
    || fail "t3[C05 AC3]: the degrade path is missing — until edges exist, a run may operate from a plan-enumerated id list (this ticket's first instance does exactly that)"
  python3 - "$SRC" <<'PY' || fail "t3[cf-124 C06 AC4 negative]: the sibling section lets parent/fixes lineage read as a grouping trigger (neither ever groups — C06/C08)"
import re, sys
sec = re.search(r"(?ms)^#{2,3}[^\n]*sibling[^\n]*\n(.*?)(?=^#{1,4} |\Z)", open(sys.argv[1]).read(), re.I).group(0)
for line in sec.splitlines():
    if re.search(r"parent|fixes", line, re.I) and re.search(r"trigger|group", line, re.I) \
       and not re.search(r"never|not|no\b|exclude|only", line, re.I):
        print(f"affirmative parent/fixes-as-trigger line: {line.strip()[:100]}"); sys.exit(1)
print("ok")
PY
  ok "t3[cf-124 C06 AC4]: grouped-sibling flow pinned — moves, ride-the-claim, degrade path (all unchanged), INBOUND related-to trigger with outbound never a trigger, fixes + parent_id non-trigger (line negative extended), settled rule keeps Test/Finished + Executing exclusions"
fi

# --- t4: follow-up cards — lineage is the ruled PAIR (C08; was C05 T4 / AC4) -----
# Shipped arm (cf-96's OQ1 ruling): parent_id was the ONLY follow-up lineage
# representation. D25 (OQ13) supersedes it WHERE THE SENTENCE LIVES — the pair
# below is the new law, the ONLY-phrase becomes a reject, and the two
# non-effects (fixes never gates, never groups) plus the UPSERT re-run are
# pinned. The set_card_labels/tool-probe and labels-degrade legs are shipped
# law this chunk must not disturb.
if want t4; then
  check_pair "t4[C05 AC4]" "Follow-?up cards" 1500 \
    'set_card_labels' 'tools/list' \
    || fail "t4[C05 AC4]: the Follow-up cards section must use set_card_labels for parent-label inheritance, gated on the tools/list probe with the comment line as the until-deployed degrade (AD-74 retirement) — unchanged"
  check_pair "t4[cf-124 C08 AC1]" "Follow-?up cards" 1500 \
    'parent_id' 'create_card' 'add_card_dependency' 'fixes' 'child' \
    || fail "t4[cf-124 C08 AC1]: the follow-up Mechanics does not carry BOTH lineage representations in one span — parent_id on create_card AND a `fixes` edge drawn at creation via add_card_dependency called ON THE CHILD (the stored source is the follow-up card, D25/C06 direction; designed red before C08 dev)"
  check_pair "t4[cf-124 C08 AC2]" "Follow-?up cards" 1200 \
    'not|never' 'gating' 'grouping' \
    || fail "t4[cf-124 C08 AC2]: the non-effects are missing — fixes gates nothing (the gate reads related-to alone) and groups nothing, stated once in the bullet so nobody 'discovers' a new gate (designed red before C08 dev)"
  check_pair "t4[cf-124 C08 AC2]" "Follow-?up cards" 1200 \
    'upsert' 'refresh|re-run|duplicat' \
    || fail "t4[cf-124 C08 AC2]: the UPSERT/re-run sentence is missing — add_card_dependency updates the edge, so re-running the protocol refreshes instead of duplicating (designed red before C08 dev)"
  # Supersession bar: the plan's own needle — an ONLY-representation lineage
  # assertion is the withdrawn ruling; a compliant bullet may mention the
  # supersession without that phrase.
  cat >"$TMP/only-lineage.py" <<'PY'
import re, sys
sys.exit(1 if re.search(r"(only|sole)[^.\n]{0,40}follow[- ]up lineage|follow[- ]up lineage[^.\n]{0,40}(only|sole)",
                         open(sys.argv[1]).read(), re.I) else 0)
PY
  python3 - "$SRC" "$TMP/t4-single.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^#{2,3}[^\n]*Follow[- ]?up cards.*?(?=^#{1,2} |\Z)", text).group(0)
open(sys.argv[2], "w").write(sec + "\n`parent_id` is the ONLY follow-up lineage representation (the batched-round ruling — no dependency edge is drawn).\n")
PY
  python3 "$TMP/only-lineage.py" "$TMP/t4-single.md" >/dev/null 2>&1 \
    && fail "t4 control: the fabricated parentId-ONLY copy PASSED the supersession bar — the negative arm is inert"
  python3 - "$TMP/t4-pair.md" <<'PY'
import sys
open(sys.argv[1], "w").write("lineage is `parent_id` + a `fixes` edge from the child to the parent, drawn at creation — an explicit supersession of the batched-round single-representation ruling (owner OQ13, 2026-11-11)\n")
PY
  python3 "$TMP/only-lineage.py" "$TMP/t4-pair.md" >/dev/null 2>&1 \
    || fail "t4 control: the fabricated two-representation copy was rejected — the bar is overscoped (it names the ONLY-lineage assertion, not the word only)"
  for f in "$SRC" "$GEN"; do
    python3 "$TMP/only-lineage.py" "$f" \
      || fail "t4[cf-124 C08 AC1 negative]: $f still asserts parentId-only lineage (the superseded cf-96 OQ1 ruling) — D25 replaced it where the sentence lived (red until C08)"
  done
  check_pair "t4[C05 AC4]" "Follow-?up cards" 1500 \
    'labels to apply' \
    || fail "t4[C05 AC4]: the comment-line degrade must STAY documented (it is the pre-deploy path) — retiring the WORDING while set_card_labels is still undeployed would leave no degrade"
  ok "t4[cf-124 C08 AC1/AC2]: follow-up lineage pinned as the PAIR (parent_id + create_card AND add_card_dependency + fixes + child in one span), the fixes non-gating/non-grouping non-effects and the UPSERT re-run sentence, and the parentId-ONLY supersession bar — with a fabricated single-representation copy rejected and the ruled pair accepted; set_card_labels + labels-degrade legs unchanged"
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

# --- t6: the call-failure degrade branch (C11 OQ-P2) --------------------------------
if want t6; then
  check_pair "t6[C11 OQ-P2]" "Board context" 2400 \
    'tools/list' 'fails' 'retry' 'idempotent' \
    || fail "t6[C11 OQ-P2]: the degrade law lacks the present-but-FAILED branch — a failed preload_board call (export disabled, admin-fields 403, outage, truncated stream) must degrade EXACTLY like absence: per-list reads, gate skipped, RESULT note, at most ONE retry (the read is idempotent), never a hard failure, never a stall"
  ok "t6[C11 OQ-P2]: call-failure degrade pinned — tools/list PRESENCE is not call-successfulness, one retry max"
fi

# --- t7: the unresolvable edge end never gates (C11 OQ-P3) ---------------------------
if want t7; then
  check_pair "t7[C11 OQ-P3]" "Card pickup" 2600 \
    'non-gating' 'REPORT' 'deleted/moved away' \
    || fail "t7[C11 OQ-P3]: the gate lacks the unresolvable-edge-end clause — an edge whose far end resolves to no card must be NON-GATING, skip-safe, and its endpoints REPORTED; the relation is never assumed either way"
  ok "t7[C11 OQ-P3]: unresolvable-edge-end clause pinned (skip-safe and reported)"
fi

# --- t8: the title-map fallback covers swimlane-scoped blocks (C11 OQ-P3) ------------
if want t8; then
  check_pair "t8[C11 OQ-P3]" "Card pickup" 2600 \
    'block' 'map' 'swimlane' \
    || fail "t8[C11 OQ-P3]: the TITLE fallback lacks the block-map branch — `list_lists` is due when no block rode the launch OR the blocker's list id is not in the block's map (the block carries only the named swimlane's lists; titles repeat across swimlanes)"
  ok "t8[C11 OQ-P3]: title-map fallback pinned (block's map / named-swimlane scope)"
fi

# --- t9: cf-106 C07 — the claim-time card block in the boards skill -----------
# The skill is the contract the coordinator reads, so the arrival of the
# single-card preload on the claim answer has to be stated there — with the
# degrade law and, critically, the clause that keeps the two hooks distinct:
# the PROMPT hook stays structural (cf-96 OQ3), this is a TOOL hook with its
# own budget. Red before C07's skill edit; a HOLD posture pin afterwards.
if want t9; then
  check_pair "t9[cf-106 C07 AC4]" "Board context" 1800 \
    'get_card_details' 'claim' \
    || fail "t9[cf-106 C07 AC4]: the boards skill never says a card-details block arrives on the claim answer (red before C07's skill edit — the skill is where the coordinator learns it does not have to fan out)"
  check_pair "t9[cf-106 C07 AC4]" "Board context" 1800 \
    'get_card_details' 'get_card' \
    || fail "t9[cf-106 C07 AC4]: the skill does not state the degrade family for the new tool — absent tool / failed call / no block ⇒ the coordinator does its own get_card plus the checklist fan-out and notes it in RESULT"
  check_pair "t9[cf-106 C07 AC4]" "Board context" 900 \
    'tool hook|tool-call hook' 'prompt' \
    || fail "t9[cf-106 C07 AC4]: the clause separating the claim-time TOOL hook from the PROMPT prefetch is missing — without it the pinned 'never the hook' sentence and the new leg read as a contradiction (and the 8 s budget ruling reads as broken)"
  check_pair "t9[cf-106 C07 AC4]" "Board context" 1800 \
    'get_card_details' 'checklist' \
    || fail "t9[cf-106 C07 AC4]: the skill never names what the block replaces for THIS card (the kickoff checklist consumption and the dependency reads)"
  ok "t9[cf-106 C07 AC4]: the boards skill states the claim-time card block, what it replaces, its degrade family, and the tool-hook-not-prompt-prefetch clause"
fi

printf 'PASS: boards dependency-gate/preload/sibling/follow-up checks (%d ok)\n' "$checks"
