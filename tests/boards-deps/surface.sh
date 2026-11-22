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
# t10[C01 bug-board-preload-lean-consumer AC1 — scoped claim-time default:
#     preload_board|swimlane_titles|"In Process" in one 1800 window. ABSENT
#     at base on the quoted literal — designed red until the amendment +
#     regen land.]
# t11[C01 AC4 — block-is-walk-map: cards:|walk|slug 1800 window, min span
#     495 at base (the shipped consumer bullet already satisfies it — GREEN
#     at hand-back with HOLD duty through the amendment); the '?'-optional
#     fourth group second whole-board|never a second is allowed, not
#     mandatory: skipped when absent, in-window when used.]
# t12[C01 AC3 — claimed-card-only consumption: get_card_details|checklists|
#     CANDIDATE 1800 window, min span 1915 at base; + the claim-anchored
#     file-wide negative on the retired candidate-reads-off-preload posture
#     — a sentence-wide exemption list hides the shipped violation behind
#     its own "no fan-out"/"not one of the current names" asides, so the
#     arm exempts only within ±260/120 of the claim — with fabricated
#     violating + compliant controls (teeth AND scope, t4's shape).]
# t13[C01 AC5 — far-end settle: far end|get_card|non-gating in one 2600
#     Card-pickup window, min span 3316 at base; + file-wide grep -qF
#     negative on the falsified 'carry no titles' clause (present at base).]
# t14[cf-123 R2 C03 AC1 — the probe-gated lean claim-time ask: (a)
#     with_checklists + swimlane_titles + tools/list co-located in one 1800
#     Board-context window (one scoped call, one probe gate — D16's shape:
#     advertised-arg ⇒ ask false, else today's ask); (b) never-empty pairing
#     — with_checklists windowed with 'never empt|not empti|omitted, not';
#     (c) claim-anchored negative (±200, t12's shape): EVERY with_checklists
#     mention sits inside a conditioning/fallback window — an unconditional-
#     lean teaching is the D14 hazard (the deployed :v162 answers the unknown
#     arg with a deterministic ToolError), so the arm is vacuous-until-landed
#     at base and its teeth live in the fabricated violating/compliant
#     controls; (d) file-wide positive on BOTH homes (source edited AND
#     regenerated mirror). DESIGNED RED at base: (a)/(b)/(d) name the absent
#     amendment; the wording is dev's, these needles are the contract.]
#
# Red posture (cf-124): t1/t3/t4 DESIGNED RED until C06 (wave 2) and C08 (wave 3)
# land their rewrites — t4 stays red through C06's window because the single
# test session (D21) lands the whole ticket's re-pins in one pass, superseding
# C06's note that t4 stays green "as shipped". t2/t5/t6/t7/t8 are UNCHANGED
# shipped law and stay green. The file-wide negatives (no hardcoded ids) are
# GREEN at base and HOLD.
#
# Red posture (2026-11-bug-board-preload-lean-consumer C01): t10/t12/t13
# DESIGNED RED until the lean-consumer prose + rulesync regen land; t11 is
# green at base and joins the HOLD set. t2/t6/t9 spans were re-measured at
# this test round on the shipped passage — minima 55/102/58/69/346/693/19
# (t2's seven check_pair arms in order), 261 (t6 — equals the C11 note),
# 26/0/19/163 (t9) — every pinned span clears them with >= 2.6x headroom,
# so no span value moves at this pass; a review-time red on t2/t6/t9 would
# mean the amendment scattered a group, and the prose bends, not the
# strictness (plan Risks).
#
# Red posture (cf-123 R2 C03 test wave, 2026-11-22): t14 DESIGNED RED at base
# — the with_checklists amendment has not landed in either home; t1..t13 are
# the C01-landed HOLD set and must stay green (dev re-measures t2/t6/t9/t10/
# t11/t12/t13 min-spans on the amended passage and records "(min span N)"
# notes; caps move only if headroom demands — C01's minima precedent).
#
# Usage:
#   bash tests/boards-deps/surface.sh            # t1..t14
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
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t([1-9]|1[0-4])$ ]] || fail "unknown check id '$a' (expected t1..t14)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/boards-deps-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# Section extractor + OR-group minimum-window checker (needle groups are
# alternation lists: the window must contain one match of EVERY group; a
# group whose first alternative starts '?' is OPTIONAL — it never fails the
# arm when the text does not use the phrase, and participates in the
# coverage when it does; only t11's never-a-second group rides this).
cat >"$TMP/sec.py" <<'PY'
import re, sys

def section(path, heading_pat):
    text = open(path).read()
    m = re.search(rf"(?ims)^#{{2,4}}[^\n]*{heading_pat}[^\n]*\n(.*?)(?=^#{{1,4}} |\Z)", text)
    return m.group(0) if m else None

def window(hay, groups, span):
    pts = []
    need = 0
    for gi, alts in enumerate(groups):
        opt = bool(alts) and alts[0].startswith("?")
        if opt:
            alts = [alts[0][1:]] + alts[1:]
        found = False
        for alt in alts:
            for m in re.finditer(re.escape(alt), hay, re.I):
                pts.append((m.start(), gi)); found = True
        if not found:
            if opt:
                continue
            return None, [a for a in alts]
        need += 1
    pts.sort()
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

# --- t10: the scoped claim-time read (C01 AC1 — designed red before dev+regen) -----
# The lean-consumer default: the exactly-ONE claim-time preload_board passes
# swimlane_titles: ["In Process"] — the walk lists AND the gate's
# satisfaction lists all live in that swimlane, so the unfiltered whole-board
# read pays for ~200 cards' checklist trees the run cannot use (the ticket's
# FRICTION item). The quoted literal is the pin: prose that states a scope
# without the argument shape has not changed the call.
if want t10; then
  check_pair "t10[C01 AC1]" "Board context" 1800 \
    'preload_board' 'swimlane_titles' '"In Process"' \
    || fail "t10[C01 AC1]: the claim-time preload passage never passes the scoped default swimlane_titles: [\"In Process\"] in one passage — the consumer doctrine still defaults to the whole-board read (designed red until C01's prose + regen land)"
  ok "t10[C01 AC1]: scoped claim-time default pinned — preload_board + swimlane_titles + the \"In Process\" literal in one Board-context passage"
fi

# --- t11: the block's cards: group IS the walk map + slug-check source (C01 AC4) ----
# Green at base through the shipped consumer bullet (min span 495) — this
# arm holds that posture THROUGH the amendment, it is not new law. The
# '?'-optional fourth group is the never-a-second-snapshot idea: allowed,
# not mandatory (chunk Tests — prose without the phrase stays green; prose
# that uses it must keep it inside the same window, which is what the
# block-present bullet's parenthetical does).
if want t11; then
  check_pair "t11[C01 AC4]" "Board context" 1800 \
    'cards:' 'walk' 'slug' '?second whole-board|never a second' \
    || fail "t11[C01 AC4]: the per-list cards: group is no longer stated as the pickup walk's map / slug-check source in one passage (or the amendment scattered the never-a-second phrasing wide of it) — the launch block stays the walk's starting map, the claim-time read stays ONE scoped read"
  ok "t11[C01 AC4]: block-is-walk-map pinned — cards: + walk + slug in one window, never-a-second phrasing in-window when used"
fi

# --- t12: kickoff checklist consumption — claimed card only (C01 AC3) --------------
# Two legs. Window: the amended passage must co-locate get_card_details,
# the checklists payload and the CANDIDATE rule (min span 1915 at base —
# the card-details text still lives after the preload paragraph; red is
# designed). Negative: no sentence anywhere may still teach the retired
# posture — that a CANDIDATE's kickoff checklist consumption reads off the
# claim-time preload (the shipped cf-106 sentence fires at base — red is
# designed). The negative is claim-anchored, NOT sentence-anchored with
# t3's bare exemption list: the shipped violation sentence is 693 chars
# carrying an incidental "title is not one of the current names" several
# asides AFTER the claim, and a bare "no fan-out" beside it — a
# sentence-wide "not"/"no" exemption would hide the retired posture behind
# its own parentheses. So: the claim regex locates each
# read(s|ing)?-off/from-the-preload (or "preload reads") assertion; only
# the ±260/120 chars around it must be free of candidate+checklist
# pairing, or carry a real negation/supersession word (t3's idea plus the
# retirement vocabulary the amendment needs to cite what it drops).
# Fabricated violating + compliant copies prove teeth and scope (t4's
# control shape).
if want t12; then
  check_pair "t12[C01 AC3]" "Board context" 1800 \
    'get_card_details' 'checklists' 'CANDIDATE' \
    || fail "t12[C01 AC3]: the passage that moves kickoff checklist consumption to the claimed card's get_card_details block never co-locates it with the checklists payload and the candidate rule — consumption law must read as one passage (min span 1915 at base; designed red until C01)"
  cat >"$TMP/cand-preload.py" <<'PY'
import re, sys
CLAIM = re.compile(r"reads?\s+(?:off|from)\s+the\s+preload|reading\s+(?:off|from)\s+the\s+preload|preload\s+reads?\b", re.I)
EXEMPT = re.compile(r"never|\bnot\b|no longer|irrelevant|retir|supersed|drop|withdraw|obsolete|exclude|\bonly\b|instead", re.I)
def scan(path):
    text = open(path).read()
    for m in CLAIM.finditer(text):
        w = text[max(0, m.start() - 260): m.end() + 120]
        if re.search(r"candidat", w, re.I) and re.search(r"checklist", w, re.I) and not EXEMPT.search(w):
            print(f"{path}: affirmative candidate-checklists-off-preload claim {m.group(0)!r} still taught")
            return True
    return False
sys.exit(1 if any(scan(p) for p in sys.argv[1:]) else 0)
PY
  python3 "$TMP/cand-preload.py" "$SRC" "$GEN" \
    || fail "t12[C01 AC3 negative]: a sentence still teaches that a candidate's kickoff checklist consumption reads off the preload — the retired cf-106 posture survives (fires on the shipped sentence at base; designed red until C01)"
  cat >"$TMP/t12-violating.md" <<'MD'
the kickoff checklist consumption and the legacy-vs-Lifecycle checklist detection read off the preload for a CANDIDATE - with no list_checklists fan-out
MD
  cat >"$TMP/t12-compliant.md" <<'MD'
the preload reads no longer teach candidate checklist consumption: kickoff consumption moved to the claimed card's card-details block
MD
  python3 "$TMP/cand-preload.py" "$TMP/t12-violating.md" >/dev/null 2>&1 \
    && fail "t12 control: the fabricated affirmative candidate-preload copy PASSED the negative — the arm is inert"
  python3 "$TMP/cand-preload.py" "$TMP/t12-compliant.md" >/dev/null 2>&1 \
    || fail "t12 control: the fabricated supersession copy was REJECTED — the negative is overscoped (the amendment could not say what it retired)"
  ok "t12[C01 AC3]: claimed-card-only consumption pinned — window co-location + the claim-anchored retired-posture negative, teeth and scope both controlled"
fi

# --- t13: the gate's far-end settle + titles truth (C01 AC5 — designed red) --------
# Two legs. Window: the Card-pickup gate must state the far-end settle rule
# as one passage — a prerequisite card outside the scoped read gets ONE
# targeted get_card (list membership + archived flag) BEFORE the
# deleted/moved-away NON-GATING branch may fire (DECISIONS D3; min span
# 3316 at base because the settle sentence does not exist yet). Negative:
# the falsified clause "carry no titles" must be gone from both files — the
# preload's swimlane/list entries DO carry titles beside ids (cf-106 C06
# shipped it; plan fact 1/D7), and the shipped gate paragraph still says
# otherwise — that clause is the base red.
if want t13; then
  check_pair "t13[C01 AC5]" "Card pickup" 2600 \
    'far end' 'get_card' 'non-gating' \
    || fail "t13[C01 AC5]: the gate never states the far-end settle rule in one passage — one targeted get_card resolves a prerequisite outside the scoped swimlanes before the non-gating deleted/moved-away branch may fire (designed red until C01's prose + regen land)"
  for f in "$SRC" "$GEN"; do
    grep -qF 'carry no titles' "$f" && fail "t13[C01 AC5 negative]: $f still says the preload's list entries carry no titles — falsified by cf-106 C06 (server.py emits swimlane/list titles; the membership tests read the scoped payload), and the scoped-read doctrine depends on that truth (designed red at base)" || true
  done
  ok "t13[C01 AC5]: far-end settle rule + titles-truth negative pinned"
fi

# --- t14: the probe-gated lean claim-time ask (cf-123 R2 C03 — designed red) ------
# D16's shape at the doctrine home: the ONE scoped claim-time read also drops
# the checklist trees IFF the claim-time `tools/list` probe the degrade law
# ALREADY runs shows the deployed tool advertising `with_checklists` — never
# an unconditional ask (D14 measured the pre-bump rejection: every claim would
# burn its one retry into the present-but-failed branch = per-list reads plus
# the SKIPPED dependency gate). The wording is dev's; these needles are the
# contract. At base the token is absent from both homes: (a)/(b)/(d) are the
# designed reds; (c) is vacuous-until-landed and carries its teeth in the
# fabricated controls (t12's claim-anchored shape, ±200 like the chunk pins).
if want t14; then
  # Generator-first (the t2 wave rule): the negative checker and the two
  # fabricated controls exist on disk BEFORE the live legs, so the teeth are
  # re-derivable by a direct call even while the legs are designed-red.
  cat >"$TMP/lean-cond.py" <<'PY'
import re, sys
COND = re.compile(r"tools/list|advertis|predates|fallback|when|build", re.I)
bad = False
for path in sys.argv[1:]:
    text = open(path).read()
    for m in re.finditer(r"with_checklists", text, re.I):
        w = text[max(0, m.start() - 200): m.end() + 200]
        if not COND.search(w):
            print(f"{path}: unconditioned with_checklists teaching at offset {m.start()} ("
                  f"{text[max(0, m.start() - 40):m.end() + 40].replace(chr(10), ' ')!r}) — every lean ask "
                  "must sit beside its probe-gate/fallback wording (D16: on a build predating the arg the "
                  "ask stays exactly today's)")
            bad = True
sys.exit(1 if bad else 0)
PY
  cat >"$TMP/t14-violating.md" <<'MD'
the claim-time preload always passes with_checklists: false and the payload never carries checklist trees anywhere — unconditional lean is the posture now.
MD
  cat >"$TMP/t14-compliant.md" <<'MD'
it calls preload_board exactly ONCE with swimlane_titles: ["In Process"] and — when the claim-time tools/list probe the degrade law already requires shows the deployed tool advertising with_checklists — also passes with_checklists: false; on a build predating the arg the ask stays exactly today's.
MD
  check_pair "t14[cf-123 R2 C03 AC1]" "Board context" 1800 \
    'with_checklists' 'swimlane_titles' 'tools/list' \
    || fail "t14[cf-123 R2 C03]: the passage teaching the scoped claim-time default never co-locates the lean ask with the scope and its tools/list probe gate — D16 (advertised-arg ⇒ with_checklists: false, else today's ask; one scoped call, zero extra round-trips) has not landed as doctrine (designed red until C03 prose + regen)"
  check_pair "t14[cf-123 R2 C03 never-empty]" "Board context" 1800 \
    'with_checklists' 'never empt|not empti|omitted, not' \
    || fail "t14[cf-123 R2 C03]: the lean-answer law lacks its never-empty pairing beside the arg name — a lean answer DROPS the key (an absent key is not a negative answer about checklist state, D11) (designed red until C03)"
  python3 "$TMP/lean-cond.py" "$SRC" "$GEN" \
    || fail "t14[cf-123 R2 C03 negative]: the doctrine teaches an UNCONDITIONAL lean ask — the deployed build answers the unknown argument with a deterministic ToolError (D14, measured), so each claim would fire the present-but-failed degrade branch instead of the read. The ask is probe-gated, never blanket"
  # Teeth AND scope, in the suite's fabricated-copy shape: the unconditional
  # teaching must redden (c); the probe-gated phrasing must pass it — the
  # amendment's own voice stays writable.
  python3 "$TMP/lean-cond.py" "$TMP/t14-violating.md" >/dev/null 2>&1 \
    && fail "t14 control: the fabricated unconditional-lean copy PASSED the conditioning negative — the arm is inert"
  python3 "$TMP/lean-cond.py" "$TMP/t14-compliant.md" >/dev/null 2>&1 \
    || fail "t14 control: the fabricated probe-gated copy was REJECTED — the negative is overscoped (dev could not write the ruled sentence)"
  for f in "$SRC" "$GEN"; do
    grep -q 'with_checklists' "$f" \
      || fail "t14[cf-123 R2 C03]: $f never names with_checklists — the amendment has not landed in this home (source edited AND mirror regenerated in the same wave; designed red until C03)"
  done
  ok "t14[cf-123 R2 C03 AC1]: the probe-gated lean claim-time ask pinned — arg + scope + tools/list gate in one passage, never-empty pairing, every lean mention conditioned (unconditional-lean control rejected, probe-gated control accepted), token present in both homes"
fi

printf 'PASS: boards dependency-gate/preload/sibling/follow-up checks (%d ok)\n' "$checks"
