#!/usr/bin/env bash
# pipeline-models local-default routing + provider-catalog surface suite
# (2026/2026-10-cf-58-feat-standalone-agent-merge, C06; re-pinned by
# 2026/2026-10-cf-83-refactor-strata-flash, C01).
#
# Pins chunks/C01.md: the Flash+Local combination routes to
# gpu-ai/qwen3.8-flash-next-strata (Strata default) across pipeline-models,
# pipeline-kickoff and the boards skill; qwen3.8-flash-next-q3 survives ONLY
# as the documented explicit-request alternate in the pipeline-models
# combination bullet (Q1 — never a route form, never a table row; Q2 — the
# favorited table carries exactly one gpu-ai flash-next row, keyed strata,
# its operations clause stating the peers/arena serving truth and naming the
# -strix sibling inside that clause only, Q3; D4 — the clause drops the
# SOLO-eviction claim, which describes only the legacy q3/q4 rungs in the
# outer solo set); kickoff and boards carry the pure route-id swap with zero
# q3/strix text (single-authority convention). Kept from cf-58 C06: the
# 27b+Local → q4 unless-escape, the Local-only default → q4, the four-option
# picker with the Q6 no-fifth-option veto, stale q6 mappings gone, plus the
# gpu-ai catalog presence HOLD (D5 re-base; Q4 — this ticket edits no
# catalog) and the serving-fact cross-check against the chart/gpu-ai values.
#
# AC trace (cf-83 C01): M1[AC1–AC3 pipeline-models] M2[AC1–AC3 kickoff]
# M3[catalog HOLD — DECISIONS D5] M4[AC8 serving facts] M5[AC1–AC3 boards
# routing + Model(s) stability] M6[AC5 mirrors/regen].
# cf-105 (2026-11, Priority wiring): M3 re-pinned — the two gpu-ai vLLM class
# rows (C03, additive; the HOLD checks stay byte-green) plus the shadow-free
# bar for the peer wire name (R3 Q5.2). NEW M7[cf-105 C04]: the board
# Priority custom field as a kickoff answer — boards roster bullet + D12
# carve-out, the card-driven kickoff priority bullet + launch-prompt value,
# the board-scoped kickoff record slot (two-question list intact), and the
# single-authority class table in pipeline-models (the 4+/background leg text
# must not leak into boards/kickoff). M7 is designed-red before C04 and
# green after; C03 dev/review run the M1..M6 subset, C04 and the final
# review run the full set (cf-83 posture).
#
# AC trace (cf-106 C02 re-pin, OQ-6/OQ-7 rulings): M1 re-pins the label to
# `Qwen Dense` and forbids it in current-state prose, adds the local-first
# blank-Model(s) default (gpu-ai/qwen3.8-27b-q4, both tiers) and the
# local-first favorited-table order; M2 keeps the option ids byte-pinned with
# the label renamed and the retired label not an option; M5 re-pins the boards
# Model(s) line and requires the temporary alias sentence there (boards is the
# alias home — no board label changes, no new option); M7 sweeps the retired
# label out of every current-state surface (dated changelog rows and the single
# boards alias excepted); M8 closes the Model(s) vocabulary at exactly the
# canonical four. M7 and M8 are red until C02 lands the rename.
#
# Re-pin note (owner ruling 2026-11-09, flash-next Strata default → q4): the
# Flash+Local combination route moves `qwen3.8-flash-next-strata` (IQ3_S) ->
# `qwen3.8-flash-next-strata-q4` (UD-Q4_K_XL) across pipeline-models,
# pipeline-kickoff and boards; the favorited row re-keys to -strata-q4 with
# its quant clause reading UD-Q4_K_XL; the guards now reject any route form
# other than -q4 (the bare -strata route string is this ruling's stale form,
# the q3/q4 alternates are never route forms); q3 stays the documented
# explicit-request alternate; the M4 serving cross-check re-pins -strata-q4
# as the default. M3's provider-catalog HOLD and every other arm are
# untouched by the re-pin.
#
# cf-105-vllm-followup (2026-11-06, four-class priority amendment — supersedes
# cf-105 D6/HR2): M3 re-pinned by C01 — the vLLM class rows go 2 -> 3 (default
# row body.priority 10 -> 5; NEW qwen3.8-27b-vllm-low row 9; the shared wire
# modelID + 262144 pins carry). M7 re-pinned by C02 — the class table 3 -> 4
# rows (1-3/1, unset+4-7/5, 8-9/9, 10+/background), the favorited table gains
# the -low row, the floor prose 10 -> 5, and the single-authority absence
# guard's marker 4+ -> 10+. Red posture (cf-83): M3 red until C01's wire
# lands; M7 red until C02 — its cross-file legs are C01's (floor 5 + the three
# catalog rows) and turn green with the wire, its skills-text legs are C02's.
# M4's wire-id list is unchanged (the wire id is not new).
#
# AC trace (cf-131 C04 re-pin, rounds 1+2+3 — the 0.30 Radiance base move):
# M3 ONLY, additively — the three vLLM class rows gain the capabilities
# asserts (input [text, image] + output [text], the round-1 OQ9/R4 carry
# re-grounded on the 0.30 vision records; tools: true, the round-2 Q6
# override standing on the 0.30 stack's own 30/30 tool record — its
# TP2-only + mtp-29/30 caveats ride the runbook's on-target tool smoke, not
# this suite). The M3 vLLM-loop context assert STAYS 262144 byte-verbatim:
# the re-plan's 65536 re-pin is VOID (round-2 Q3 keep) and the round-3 Q11
# engine-cap ruling makes the axis TRUE on both sides (catalog 262144 ==
# engine --max-model-len 262144, D31). M1, M2, M4, M5, M6, M7: byte-untouched
# (the class table + floor needles + wire-id leg are the protected wiring —
# the re-scope and the base move change no class mapping). Red posture: M3 is
# red until C04's catalog edit lands (the capabilities key is absent on the
# rows until then); the other arms HOLD green across the window.
#
# cf-131 D38 amendment re-pin (2026-11-09, the vision-drop + f2 package on
# the R8/R8b ground — the owner's R8-Q1 "C — drop vision" + R8b-Q1 "C + f2",
# DECISIONS D38): M3's input deep-equal flips ['text','image'] -> ['text']
# on the three vLLM class rows — the shipped --language-model-only zeroes
# every modality and the engine refuses image inputs at validation, so the
# honest-grounding law that made the marker TRUE under vision-on forces it
# FALSE now (the marker reflects what the engine serves, never the reverse).
# Byte-stable under D38: the output leg ['text'], tools: true (tool
# parsing/serving is text-side — the round-2 Q6 override unchanged, the 3.7
# on-target smoke stays the marker's lease), the modelID/name/body.priority
# /262144 legs, every non-vLLM row, and every other arm. The 48 GB-RDNA3
# re-enable returns the "image" leg TOGETHER with the values serveArgs pair
# + the runbook marker rows (copy-back, R8b.4e).
#
# Red posture (cf-83): M1, M2 and M5 are red before the C01 dev edit — the
# sources still route Flash+Local to q3, so the strata route needles and the
# q3/strix absence guards name the missing re-route (never a harness fault).
# Inside them the q3+'explicit' alternate window and the picker/q4 pins
# HOLD across red→green. M3 is a presence HOLD: green already (cf-77 landed
# the entries) and green after — Q4 forbids catalog edits. M4 is a HOLD
# invariant pinned by the plan's verified serving facts (every id the
# contract names appears in a serving authority; green today, red the day
# routing drifts to an unserved id). M6 is HOLD now (mirrors honest) and
# re-arms red between the dev source edit and its regenerate.
# cf-105 handoff posture (2026-11-04): M3 red — the two vLLM class rows are
# absent until C03 (the q4/flash-next HOLD rows inside it stay green); M4
# red — qwen3.8-27b-vllm is not in a serving authority until C03's
# peers.vllm block lands in the gpu-ai values; M7 red — the C04 needles are
# absent until the C04 dev edit. C03 dev/review run M1..M6 (green once C03
# lands); C04 and the final review run M1..M7 (nothing designed-red after
# C04).
#
# Base discipline: no ticket-base diff remains in this suite since the cf-83
# re-pin — the cf-58 M3 delta arm and its TB/CF58_BASE read are retired
# (DECISIONS D5: self-contradictory on any post-cf-58 base, measured at
# eb8a963; the rejected alternative, a historical CF58_BASE default, would
# hide a stale ref that passes only when the env is set by accident).
#
# cf-143 C01 re-pin (2026-11-11, the vllm lane disabled commented-out — owner
# Q3): the vllm-side needles RETIRE and invert. M3: the three-qwen3.8-27b-
# vllm-row HOLD loop becomes an ABSENCE-NEB needle (no live vllm row key may
# parse out of the jsonc — the rows ride on as comments, one-edit-reversible;
# charts/vllm is the magiccodingman/vllm-radiance FORK lane, never the cf-143
# radiance engine — naming law). M4: the wire id leaves the serving-grep loop
# (grep would false-green on the comment text — the live-shape absence is
# pinned by charts/llama-swap/tests/test_vllm_disable_contract.py); M4 GAINS
# the retirement negative needle (tests/notes/vllm-runbook.sh absent while
# .agents/notes/vllm-on-target-acceptance.md lives with a cf-143 supersession
# header). M7: the peers.vllm floor leg, the vllm-catalog.js cross-file leg
# and the PM vllm class-table cells retire (C05 re-pins the class table for
# radiance in the NEW M8 arm — NOT here: M7 must be green at C01's review,
# C05 lands in wave 4). M1/M2/M5/M6: byte-untouched (nothing vllm-shaped;
# the strata/q4 route legs are Q5-proTECTED — strata lives).
# Red posture: M3's absence legs + M4's retirement needle are designed-RED
# naming C01 until the comment-out + runbook retirement land; M1, M2, M5,
# M6, M7 (minus the retired vllm legs) are HOLD-green and must stay green.
#
# Offline-deterministic: tree/parse checks only; JSONC is parsed with node
# evaluating the file as an object literal (the plan's "JSONC-tolerant"
# mandate — bare jq would choke on the comments).
#
# cf-143 C05 adds M8 (radiance catalog + class-table + priority-coherence
# legs, DECISIONS Q2/Q4/Q8 + D17/D18): designed-RED until C05 (wave 4). M8 is
# deliberately NOT in the default set — C01..C04 reviews run `bash
# tests/pipeline-models/surface.sh` bare and must PASS (chunks/C01.md AC6
# says so verbatim: "radiance legs don't exist yet — M-arm structure
# intact"); C05 and the final review run the full set explicitly:
# `bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M6 M7 M8`
# (cf-105's M7-before-C04 posture, re-expressed with M8 excluded from the
# default so the chunk-AC bare runs stay honest). M8's cross-file legs also
# wait on C04 (peers.radiance) and C02 (the chart scalars/polarity comment)
# — all predecessors of C05's wave, so C05's bar is a full green.
#
# 2026-11-feat-radiance-multi-instance (C02 routing move + C05 four-lane fleet).
# C02 re-pins M1/M2/M5 (both tiers and the blank/Local-only defaults move to
# gpu-ai/qwen3.8-flash-next-radiance; explicit Qwen Dense + Local moves to
# gpu-ai/qwen3.8-27b-radiance with its accepted 502 consequence, DECISIONS D20;
# the `10+`/background leg stays qwen3.8-27b-q4, which is why M7 is untouched),
# flips M8-F from "strata stays the DEFAULT route" to the demoted-Strata shape
# (PM alternate kept, kickoff/boards single-authority BAR, lane kept served),
# re-authors M8-H from an empty-diff touch-bar into the runner-literal PAIRING
# leg with planted-drift teeth, and replaces the retired ctx-equality needle with
# the two-figure ctx axis. M9 is C05's new arm: the four-trio radiance fleet, the
# per-lane floors, the re-frozen +6 delta and the two new peers/evidence units —
# designed-RED naming C05, NOT in the default set. Every decision, the priority
# ladder's arithmetic proof included, is in tests/pipeline-models/TEST_SPEC.md.
#
# Usage:
#   bash tests/pipeline-models/surface.sh            # M1..M7 (cf-143 default)
#   bash tests/pipeline-models/surface.sh M3 M4      # subset
#   bash tests/pipeline-models/surface.sh M8         # cf-143 radiance legs (C05+)
#   bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M7 M8 M9   # C05 bar
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PM_SRC=".rulesync/skills/pipeline-models/SKILL.md"
PM_GEN=".opencode/skills/pipeline-models/SKILL.md"
PK_SRC=".rulesync/skills/pipeline-kickoff/SKILL.md"
PK_GEN=".opencode/skills/pipeline-kickoff/SKILL.md"
BD_SRC=".rulesync/skills/boards/SKILL.md"
BD_GEN=".opencode/skills/boards/SKILL.md"
CAT=".opencode/opencode.jsonc"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/pipeline-models-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["m$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^m[1-9]$ ]] || fail "unknown check id '$a' (expected M1..M9)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Whitespace- and case-tolerant phrase bar (prose wraps mid-phrase; a
# line-bound grep false-reds on a rewrap of an otherwise intact semantic).
# Words are escaped individually and re-joined on \s+: re.escape of the
# whole needle first leaves a backslash before each space that the \s+
# join cannot clear.
phrased() {
  python3 -c '
import re, sys
needle, path = sys.argv[1], sys.argv[2]
rx = r"\s+".join(re.escape(t) for t in needle.lower().split())
text = re.sub(r"\s+", " ", open(path).read()).lower()
sys.exit(0 if re.search(rx, text) else 1)
' "$1" "$2"
}

# --- shared helpers -------------------------------------------------------------

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): the routing needles
# must read as one passage, not as scattered file-wide hits. Whitespace is
# collapsed first: prose wraps, and a needle must not fail on a line break
# mid-phrase (all current callers are single-line-safe, so this only ever
# ADDS matches — no existing check changes state).
import re, sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = re.sub(r"\s+", " ", open(path).read())
if ci:
    text = text.lower(); needles = [re.sub(r"\s+", " ", n).lower() for n in needles]
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

cat >"$TMP/pairsync.py" <<'PY'
# Source<->generated honesty for skill pairs (parsed frontmatter + verbatim
# body), the coord-inwork convention.
import re, sys, yaml
src, gen = sys.argv[1], sys.argv[2]

def parts(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{path}: no parsable frontmatter"
    return yaml.safe_load(m.group(1)), m.group(2).strip("\n") + "\n"

f1, b1 = parts(src); f2, b2 = parts(gen)
n = lambda f: {k: f.get(k) for k in ("name", "description", "metadata", "disable-model-invocation")}
if b1 != b2:
    print("body drift between source and generated mirror"); sys.exit(1)
if n(f1) != n(f2):
    print("frontmatter drift between source and generated mirror"); sys.exit(1)
PY

# --- M1: pipeline-models local-mapping contracts (AC1–AC3) -----------------------
if want m1; then
  for f in "$PM_SRC" "$PM_GEN"; do
    [ -f "$f" ] || fail "M1[AC1]: $f missing"
    # The picker option set stays FOUR (no fifth option) — cf-106 C02 renames
    # the middle label `Qwen 27b` -> `Qwen Dense` (a vocabulary change: no
    # model id carries "Dense"), so the needle moves with the label while the
    # veto and the id rows below HOLD.
    python3 "$TMP/win.py" "$f" 400 'Qwen Large' 'Qwen Dense' 'Qwen Flash' 'Local' \
      || fail "M1[AC1,AC3 cf-106 C02]: $f lost the four-option picker line (the option set stays Qwen Large / Qwen Dense / Qwen Flash / Local — no fifth option; Qwen Dense replaces Qwen 27b by the cf-106 OQ-6 ruling — red before C02 lands the rename)"
    if grep -nE 'Qwen Large.*Qwen (27b|Dense).*Qwen Flash.*Local' "$f" | grep -q 'Flash Next'; then
      fail "M1[AC1]: a picker option line gained 'Flash Next' — Q6 vetoed a fifth option; the combination of the two existing checks is the whole mechanism"
    fi
    grep -qE 'Qwen 27b' "$f" \
      && fail "M1[AC1 cf-106 C02]: $f still names the retired vocabulary label 'Qwen 27b' in current-state prose — C02 renames it to Qwen Dense (the transition ALIAS sentence is the only sanctioned survivor, and it lives in the boards skill, not here)"
    # 27b + Local → the q27 radiance lane (2026-11-feat-radiance-multi-instance
    # D20 supersedes the cf-83/cf-106 `gpu-ai/qwen3.8-27b-q4` route: the owner
    # chose "everything → radiance[-family]" over the 502-trap recommendation).
    # The unless-escape rides the new row.
    grep -qF 'gpu-ai/qwen3.8-27b-radiance' "$f" \
      || fail "M1[AC1 re-pinned cf-radiance C02/D20]: $f never routes Qwen Dense + Local to gpu-ai/qwen3.8-27b-radiance (owner ruling 2026-11-22 D20 — red until C02 lands the row move)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-27b-radiance' 'unless' \
      || fail "M1[AC1 re-pinned cf-radiance C02/D20]: $f's Dense+Local route lacks the 'unless another quant is requested' escape clause"
    # The accepted consequence must sit beside the route (chunk AC1 verbatim
    # requirement): the lane rests at replicas 0 and answers 502-loud until a
    # manual scale-up — accepted at ruling time, recorded so nobody refiles it.
    python3 "$TMP/win.py" --ci "$f" 700 'qwen3.8-27b-radiance' '502' \
      || fail "M1[AC1 re-pinned cf-radiance C02/D20]: $f routes Dense+Local to gpu-ai/qwen3.8-27b-radiance without the accepted-consequence sentence (the lane rests at replicas 0, so the route answers 502-loud until a manual scale-up — D20 records it as accepted, not a bug)"
    # Stale-route bar (word-boundary-safe by the trailing ' unless'): the
    # pre-D20 Dense+Local row must be gone from current-state prose.
    phrased 'gpu-ai/qwen3.8-27b-q4 unless' "$f" \
      && fail "M1[AC1 re-pinned cf-radiance C02/D20]: $f still routes Qwen Dense + Local to gpu-ai/qwen3.8-27b-q4 — D20 moved the explicit Dense+Local row to gpu-ai/qwen3.8-27b-radiance (the 27b-q4 id survives ONLY as the class table's 10+/background leg, which carries no 'unless' clause)"
    # Flash+Local combination rule, pinned verbatim (cf-83 re-pin: same
    # phrases, new route)
    grep -qF 'assume Qwen Flash Next' "$f" \
      || fail "M1[AC1]: $f lacks the combination rule's pinned phrasing 'assume Qwen Flash Next' (cf-83 keeps the phrase — red only if dev deleted it)"
    grep -qF 'gpu-ai/qwen3.8-flash-next-radiance' "$f" \
      || fail "M1[AC1 re-pinned cf-radiance C02]: $f never routes Flash+Local to gpu-ai/qwen3.8-flash-next-radiance (the Flash+Local default moves to the radiance lane — DECISIONS D4/D16)"
    grep -qF 'There is no plain-flash local route' "$f" \
      || fail "M1[AC1]: $f lacks the pinned 'There is no plain-flash local route.' clause (cf-83 keeps this phrase too)"
    # AC1 absence guard pins the ROUTE FORM, not the bare id: strata-q4 and q3
    # legitimately survive as documented alternates (the cf-radiance re-pin
    # keeps strata as ONE alternate sentence), so only a routed string is stale.
    grep -qF 'assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-strata`' "$f" \
      && fail "M1[AC1]: $f still carries the pre-ruling route string 'assume Qwen Flash Next: gpu-ai/qwen3.8-flash-next-strata' — the owner ruling 2026-11-09 re-keyed the default to -strata-q4, and 2026-11-22 (D4/D16) moved it again to -radiance"
    grep -qF 'assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-strata-q4`' "$f" \
      && fail "M1[AC1 re-pinned cf-radiance C02]: $f still ROUTES Flash+Local to gpu-ai/qwen3.8-flash-next-strata-q4 — the 2026-11-22 ruling moves the default to gpu-ai/qwen3.8-flash-next-radiance; strata-q4 survives as the documented ALTERNATE sentence, never as the route string"
    # AC2 documented-alternate (pipeline-models only, PM pair only): the
    # alternate sentence must co-locate q3 with its explicit-request escape —
    # windowed, not bare grep, so a stray mention elsewhere cannot satisfy it.
    python3 "$TMP/win.py" --ci "$f" 300 'qwen3.8-flash-next-q3' 'explicit' \
      || fail "M1[AC2]: $f no longer documents qwen3.8-flash-next-q3 as the explicit-request alternate in the combination bullet (cf-83 Q1)"
    # cf-radiance C02: strata-q4 keeps exactly one survivor slot here, in the
    # same documented-alternate shape (it leaves the DEFAULT tables everywhere
    # else — the M8-F flip pins that).
    python3 "$TMP/win.py" --ci "$f" 300 'qwen3.8-flash-next-strata-q4' 'alternate' \
      || fail "M1[AC1 re-pinned cf-radiance C02]: $f no longer documents qwen3.8-flash-next-strata-q4 as an alternate in the combination bullet (the 2026-11-22 move demotes the Strata default to ONE documented alternate — it does not delete it)"
    # Local-only default follows the tier default (27b-q4 → radiance)
    python3 "$TMP/win.py" --ci "$f" 300 'no model' 'qwen3.8-flash-next-radiance' \
      || fail "M1[AC1 re-pinned cf-radiance C02]: $f's Local-only/blank default is not gpu-ai/qwen3.8-flash-next-radiance (was qwen3.8-27b-q4; C02 re-cuts it per DECISIONS D4/D16)"
    # stale q6 mappings removed outright
    grep -qF 'qwen3.8-flash-q6' "$f" && fail "M1[AC1]: $f still references qwen3.8-flash-q6 — C06 drops it outright, not as a fallback"
    grep -qF '27b → `gpu-ai/qwen3.8-27b-q6`' "$f" && fail "M1[AC1]: $f still maps 27b to q6 as the default route"
    grep -qF 'basename + `-q6`' "$f" && fail "M1[AC1]: $f still states the basename + -q6 assumption rule (stale after the q4 re-cut)"
    # favorited-models table (cf-83 Q2: exactly one gpu-ai flash-next row,
    # keyed strata, replacing the q3 row)
    # Tier table (chunk AC1's first sentence, checked structurally): the two
    # DEFAULT-model rows — planning and code — must both carry the radiance
    # lane. The FINAL-review row names the run's planning-tier model, not a
    # literal, so it is excluded by construction.
    if ! python3 - "$f" <<'PY'
import re, sys
rows = [l for l in open(sys.argv[1]).read().splitlines() if l.lstrip().startswith('| `agent-')]
tiers = [l for l in rows if 'the run\u2019s planning-tier model' not in l
         and "planning-tier model" not in l]
if len(tiers) < 2:
    print(f"tier table has {len(tiers)} literal-default rows, want the planning + code pair"); sys.exit(1)
bad = [l for l in tiers if 'gpu-ai/qwen3.8-flash-next-radiance' not in l]
if bad:
    print("tier rows not on gpu-ai/qwen3.8-flash-next-radiance: " + " || ".join(bad)); sys.exit(1)
PY
    then fail "M1[AC1 cf-radiance C02]: $f's tier table does not put gpu-ai/qwen3.8-flash-next-radiance on BOTH default-model rows (the owner's 'for everything' ruling, DECISIONS D4/D16 — red until C02 lands it)"; fi
    # The provider-posture sentence still describing the default as the local
    # DENSE route is stale prose about the very row C02 moves.
    phrased 'the local dense route for both tiers' "$f" \
      && fail "M1[AC1 cf-radiance C02]: $f still calls the blank-Model(s) answer 'the local dense route for both tiers' — C02 re-words the posture sentence for the radiance MoE lane"
    grep -qF '| `gpu-ai` | `qwen3.8-flash-next-strata-q4` |' "$f" \
      || fail "M1[AC3]: $f's favorited table has no gpu-ai row keyed qwen3.8-flash-next-strata-q4 (owner ruling 2026-11-09 re-keys the row; a q3 or plain-strata row is stale)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-flash-next-strata' 'peers' 'arena' \
      || fail "M1[AC3]: $f's strata row lacks the peers/arena operations clause (dedicated Strata pod through the outer llama-swap peers seam; the IQ3_S arena pin makes cold start minutes-long — the serving truth D4 records)"
    # Inverted from the cf-58 q3+solo window: a peer-served model is invisible
    # to the outer matrix's SOLO-eviction semantics, so that claim may no
    # longer sit on the default route's row (D4 — it describes only the
    # legacy q3/q4 solo-set rungs).
    grep -F '| `gpu-ai` | `qwen3.8-flash-next-strata-q4` |' "$f" | grep -qiF 'solo' \
      && fail "M1[AC3]: $f's strata-q4 row still claims SOLO/matrix eviction — the clause must be the peers/arena one (cf-83 D4)"
    # cf-radiance C02: the inventory rows keep their ids but not the DEFAULT
    # claims. The Strata row loses "the Flash+Local default" prose; the radiance
    # row loses "opt-in for now" (it IS the default now, D16/D27).
    grep -F '| `gpu-ai` | `qwen3.8-flash-next-strata-q4` |' "$f" | grep -qiE 'flash\+local (default|combo)' \
      && fail "M1[AC1 cf-radiance C02]: $f's strata-q4 favorited row still calls it the Flash+Local default/combo route — 2026-11-22 moves that default to the radiance lane; the row keeps its serving prose, drops the default claim"
    grep -F '| `gpu-ai` | `qwen3.8-flash-next-radiance` |' "$f" | grep -qiF 'opt-in for now' \
      && fail "M1[AC1 cf-radiance C02]: $f's radiance favorited row still says 'opt-in for now' — the lane is the runner default since the 2026-11-22 ruling (D16)"
    # The q27 row keeps its NEVER-default + 502-idle law verbatim (chunk AC6) —
    # presence, not absence — and its runner-literal sentence must re-attribute
    # to radiance (it used to say the runner literal stays 27b-q4).
    python3 "$TMP/win.py" --ci "$f" 900 'qwen3.8-27b-radiance' 'never a default' \
      || fail "M1[AC6 cf-radiance C02]: $f's q27-radiance row lost its 'NEVER a default route' sentence (the parked-lane law survives the routing move intact)"
    phrased 'runner-model literal stay fn/27b-q4' "$f" \
      && fail "M1[AC6 cf-radiance C02]: $f still attributes the runner-model literal to fn/27b-q4 in the q27 row — the 2026-11-22 ruling moves the runner to gpu-ai/qwen3.8-flash-next-radiance (D16), so the sentence re-attributes"
    python3 "$TMP/win.py" --ci "$f" 900 'runner' 'qwen3.8-flash-next-radiance' \
      || fail "M1[AC6 cf-radiance C02]: $f never re-attributes the runner-model literal to gpu-ai/qwen3.8-flash-next-radiance (the D16 move must be stated in current-state prose, not just in the tier table)"
    grep -qF '| `qwen3.8-flash-next-q3`' "$f" \
      && fail "M1[AC2]: $f still carries a favorited row keyed qwen3.8-flash-next-q3 — q3's alternate status is rule text, never a table row (Q2; red before C01)"
    # Q3: the -strix sibling is named inside the strata row's operations
    # clause ONLY — never as a row, never in route syntax, never elsewhere.
    grep -qF 'gpu-ai/qwen3.8-flash-next-strata-strix' "$f" \
      && fail "M1[AC3]: $f gives -strix the gpu-ai/ route form — strix is never agent-routable (Q3/D7)"
    grep -F 'strix' "$f" | grep -vF '| `gpu-ai` | `qwen3.8-flash-next-strata-q4` |' | grep -q . \
      && fail "M1[AC3]: $f names strix outside the strata-q4 row's operations clause (Q3: that clause is strix's one location)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-27b-q6' 'alternate' \
      || fail "M1[AC1]: $f's q6 row was not re-labelled the verified alternate (C06 Tasks)"
    # cf-106 C02 (OQ-7 ruling, ask 10): the ROUTING default flips local-first —
    # a blank Model(s) resolves to the dense local route for BOTH tiers, and
    # openrouter becomes the documented explicit-choice/fallback provider.
    # cf-radiance C02 re-cuts the blank-Model(s) default: both tiers resolve to
    # the local radiance MoE lane (the D4/D16 "for everything" ruling).
    python3 "$TMP/win.py" --ci "$f" 700 'no model' 'both tiers' 'qwen3.8-flash-next-radiance' \
      || fail "M1[AC4 cf-radiance C02]: $f's BLANK Model(s) answer does not resolve to gpu-ai/qwen3.8-flash-next-radiance for BOTH tiers (red until C02 moves the default rows — D4/D16)"
    python3 "$TMP/win.py" --ci "$f" 700 'gpu-ai' 'default' 'openrouter' 'fallback' \
      || fail "M1[AC4 cf-106 C02]: $f never states the local-first provider posture (gpu-ai is the default, openrouter the documented explicit-choice/fallback) — unchanged by C04 (the lane moves, the posture stands)"
    # An explicit Qwen Dense check WITHOUT Local still routes openrouter — the
    # flip changes the default, not the label's own mapping (chunk AC4).
    python3 "$TMP/win.py" --ci "$f" 500 'dense' 'openrouter/qwen/qwen3.8-27b' \
      || fail "M1[AC4 cf-106 C02]: $f no longer maps an explicit Qwen Dense check (no Local) to openrouter/qwen/qwen3.8-27b — the rename keeps the id, only the label moves"
    # Favorited-models table order (cf-106 C02, OQ-7): local rows FIRST, ids and
    # verification notes unchanged — the re-order IS the posture, so it is
    # pinned structurally (first gpu-ai/gpu-moe row precedes the first
    # openrouter row) instead of by prose.
    if ! python3 - "$f" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
rows = [l for l in text.splitlines() if re.match(r"^\|\s*`(gpu-ai|gpu-moe|openrouter)`\s*\|", l)]
if not rows:
    print("no favorited-models table rows found"); sys.exit(1)
first_local = next((i for i, l in enumerate(rows) if "`gpu-ai`" in l or "`gpu-moe`" in l), None)
first_or = next((i for i, l in enumerate(rows) if "`openrouter`" in l), None)
if first_local is None or first_or is None:
    print("the favorited table lost one of the two providers"); sys.exit(1)
if first_local > first_or:
    print(f"first local row at {first_local}, first openrouter row at {first_or} — the local rows must come FIRST (OQ-7 local-first default)"); sys.exit(1)
PY
    then fail "M1[AC4 cf-106 C02]: $f's favorited-models table does not lead with the local rows (ids and verification notes unchanged — only the order moves)"; fi
  done
  ok "M1[AC1–AC4, re-pinned cf-radiance C02]: pipeline-models carries the four-option picker with Qwen Dense replacing Qwen 27b (no fifth option, no stale 27b label, stale q6 routes still gone), BOTH tier rows and the Local-only/blank defaults on gpu-ai/qwen3.8-flash-next-radiance, the D20 Dense+Local route to gpu-ai/qwen3.8-27b-radiance with its unless-escape and accepted-502 sentence, the pinned combination bullet routing Flash+Local to radiance with the strata-q4/q3 route strings gone and both ids documented as alternates, an explicit Dense check still mapping to openrouter, the favorited inventory without the stale default claims, and a favorited table that still leads with the local rows"
fi

# --- M2: pipeline-kickoff — four options, cites, strata derivation (AC1–AC3) -----
if want m2; then
  for f in "$PK_SRC" "$PK_GEN"; do
    [ -f "$f" ] || fail "M2[AC2]: $f missing"
    # the option list itself is unchanged — byte-pinned per C06 Tasks, with the
    # cf-106 C02 (OQ-6) rename of the middle label: ids byte-identical, only the
    # label moves
    for o in '`Qwen Large` — `openrouter/qwen/qwen3.8-2.4t-a95b`' \
             '`Qwen Dense` — `openrouter/qwen/qwen3.8-27b`' \
             '`Qwen Flash` — `openrouter/qwen/qwen3.8-flash`'; do
      grep -qF "$o" "$f" || fail "M2[AC2 cf-106 C02]: $f lost the pinned option '$o' (option set UNCHANGED apart from the Qwen Dense rename — red before C02 lands the label)"
    done
    grep -qF '`Local (gpu-ai)`' "$f" || fail "M2[AC2]: $f lost the Local option"
    grep -qF '`Qwen Flash Next`' "$f" && fail "M2[AC2]: $f gained a 'Qwen Flash Next' option — Q6 veto"
    grep -qF '`Qwen 27b`' "$f" && fail "M2[AC1,AC3 cf-106 C02]: $f still offers the retired 'Qwen 27b' label — the picker's only dense row must read Qwen Dense (OQ-6)"
    grep -qF 'pipeline-models' "$f" || fail "M2[AC2]: $f no longer cites pipeline-models as the mapping authority"
    # derivation updated: routes to the new ids (cf-radiance C02)
    grep -qF 'qwen3.8-flash-next-radiance' "$f" \
      || fail "M2[AC2 re-pinned cf-radiance C02]: $f's derivation never routes the Local/blank default to gpu-ai/qwen3.8-flash-next-radiance (the runner+default move of the 2026-11-22 owner ruling, D4/D16)"
    grep -qF 'qwen3.8-27b-radiance' "$f" \
      || fail "M2[AC1 re-pinned cf-radiance C02/D20]: $f's derivation lacks the explicit Dense+Local → gpu-ai/qwen3.8-27b-radiance route (owner ruling 2026-11-22 D20)"
    # Single-authority bars, radiance era: the alternates and the retired
    # default ids live in pipeline-models only. strata-q4 was the route until
    # 2026-11-22 and is now exactly one documented alternate sentence THERE;
    # qwen3.8-27b-q4 survives only as pipeline-models' 10+/background row.
    grep -qF 'qwen3.8-flash-next-strata-q4' "$f" \
      && fail "M2[AC1 re-pinned cf-radiance C02]: $f names gpu-ai/qwen3.8-flash-next-strata-q4 — the Strata lane is one documented alternate in the pipeline-models combination bullet (single-authority, same law as the q3 bar below)"
    grep -qF 'qwen3.8-27b-q4' "$f" \
      && fail "M2[AC1 re-pinned cf-radiance C02]: $f still defaults a Local/blank answer to gpu-ai/qwen3.8-27b-q4 — D20/D4 move every kickoff route into the radiance family; the 27b-q4 id stays ONLY in pipeline-models' 10+/background class row"
    phrased 'route both tiers to the local dense route' "$f" \
      && fail "M2[AC2 re-pinned cf-radiance C02]: $f's Local option still routes a no-model answer to 'the local dense route' — the blank default is the radiance MoE lane now"
    # Single-authority (Q1): kickoff cites pipeline-models for the quants and
    # "never restates its table" — the cf-83 change there is a pure route-id
    # swap, so zero q3 text (and zero strix text, Q3) may exist on this pair.
    grep -qF 'qwen3.8-flash-next-q3' "$f" \
      && fail "M2[AC2]: $f names qwen3.8-flash-next-q3 — the named alternate lives only in the pipeline-models bullet (red before C01)"
    grep -qF 'qwen3.8-flash-next-q4' "$f" \
      && fail "M2[AC2 owner ruling 2026-11-09]: $f names qwen3.8-flash-next-q4 as a route — the routed id is flash-next-strata-q4; named alternates live only in the pipeline-models bullet"
    grep -qF 'strix' "$f" \
      && fail "M2[AC3]: $f names strix — only the pipeline-models strata row clause may name it (Q3)"
    grep -qF 'qwen3.8-27b-q6' "$f" && fail "M2[AC2]: $f still cites qwen3.8-27b-q6 as the Local default (stale after C06)"
    grep -qF 'qwen3.8-flash-q6' "$f" && fail "M2[AC2]: $f still cites the dropped flash-q6 mapping"
  done
  ok "M2[AC1–AC3, re-pinned cf-radiance C02]: kickoff keeps the four pinned options, cites pipeline-models, and its derivation routes the Local/blank default to gpu-ai/qwen3.8-flash-next-radiance and explicit Dense+Local to gpu-ai/qwen3.8-27b-radiance, with no strata-q4/q3/q4/strix/27b-q4 restatement and no stale q6 claims"
fi

# --- M3: gpu-ai provider catalog — presence HOLD (DECISIONS D5 re-base) --------
# cf-83 C01 re-bases this arm: the cf-58 delta contract (exactly +2 added
# entries vs TB=$(git merge-base main HEAD) AND a tools-less q4 at that base)
# is self-contradictory once cf-58/cf-77 catalog state lives in the base
# itself — proven red-by-construction at eb8a963 ("added entries are []",
# "q4: fields other than capabilities changed"). Rejected alternative kept
# out by design: a historical CF58_BASE default — a hidden stale ref passing
# only when the env happens to be set. Under cf-83's Q4 this arm guards
# against the catalog losing or reshaping an entry a route needs: green
# before AND after the dev edit. cf-105 C03 re-pins it additively: the two
# gpu-ai vLLM class rows (D10 — same wire modelID, only body.priority
# differs) join the presence checks, and the peer wire name must stay
# shadow-free against the local llama-swap model ids (R3 Q5.2). cf-131 C04
# re-pins the vLLM loop additively: the capabilities marker (input/output —
# the round-1 OQ9/R4 carry; tools — the round-2 Q6 override) and the
# true-axis record below; cf-131 D38 re-pins the input leg to text-only
# (the owner's vision-drop ruling — see the suite header), the context
# assert itself stays byte-verbatim.
if want m3; then
  [ -f "$CAT" ] || fail "M3[HOLD]: $CAT missing"
  cat >"$TMP/catalog.js" <<'JS'
// JSONC-tolerant parse (the plan's mandate): evaluate the file as a JS object
// literal so line/block comments are legal — bare jq chokes. Presence shape
// for every id the contract routes to or documents: modelID equal to the key,
// tools capability (subagents are tool-capable by plan requirement), the
// 262144 context pin, a descriptive name.
const fs = require('fs');
function load(p) {
  const src = fs.readFileSync(p, 'utf8');
  return eval('(' + src + ')');
}
function gpuModels(o) {
  const provs = o.providerMetas || o.providers || null;
  if (!provs) throw new Error('no providers map found — re-pin the reader');
  const g = provs['gpu-ai'];
  if (!g) throw new Error('no gpu-ai provider found');
  return g.models || {};
}
const cur = gpuModels(load(process.argv[2]));
let errs = [];
const q4 = cur['qwen3.8-27b-q4'];
if (!q4 || !q4.capabilities || q4.capabilities.tools !== true)
  errs.push('qwen3.8-27b-q4 lacks capabilities.tools=true (agents cannot use the 27b+Local default)');
for (const k of ['qwen3.8-flash-next-q3', 'qwen3.8-flash-next-q4', 'qwen3.8-flash-next-strata']) {
  const e = cur[k];
  if (!e) { errs.push(`${k}: catalog entry missing`); continue; }
  if (e.modelID !== k) errs.push(`${k}: modelID is ${e.modelID}, want the key`);
  if (!e.capabilities || e.capabilities.tools !== true) errs.push(`${k}: capabilities.tools not true`);
  if (!e.limit || e.limit.context !== 262144) errs.push(`${k}: limit.context not 262144`);
  if (!e.name) errs.push(`${k}: no descriptive name`);
}
// cf-143 C01 (owner Q3 ruling, DECISIONS D6): the vllm lane is DISABLED
// commented-out — charts/vllm is the magiccodingman/vllm-radiance FORK
// engine (NOT the cf-143 radiance engine; naming law). The three-row HOLD
// loop (cf-105 C03 + cf-105-vllm-followup C01 + cf-131 C04/D38 re-pins)
// inverts to an ABSENCE needle: no live qwen3.8-27b-vllm* row key may parse
// out of the gpu-ai provider map. The rows survive as JSONC comments for the
// locate-and-uncomment re-enable (grep cf-143 finds each site — the marker
// legs live pytest-side in charts/llama-swap/tests/test_vllm_disable_
// contract.py, AC7); the loader parse itself is the same AC5 criterion.
for (const k of ['qwen3.8-27b-vllm', 'qwen3.8-27b-vllm-urgent', 'qwen3.8-27b-vllm-low']) {
  if (cur[k]) errs.push(`${k}: still a LIVE catalog row — cf-143 C01 comments the three vllm (vllm-radiance FORK) rows out (owner Q3: disable, keep one-edit-reversible)`);
}
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/catalog.js" "$CAT" \
    || fail "M3: gpu-ai catalog presence contract violated — the red names the missing/reshaped entry (HOLD rows never reshaped; the vllm rows are cf-143 C01's ABSENCE re-pin — a live row there is the disable not landed)"
  # The peer hop only works while the wire name is not also a local model id
  # (llama-swap precedence: local IDs beat unqualified peer IDs, R3 Q5.2).
  python3 - <<'PY' \
    || fail "M3: qwen3.8-27b-vllm is declared as a local llama-swap model id — it would shadow the unqualified vLLM peer (R3 Q5.2)"
import yaml

def model_ids(cfg):
    out = set((cfg or {}).get("models") or {})
    for fam, spec in ((cfg or {}).get("families") or {}).items():
        for quant, rung in ((spec or {}).get("quants") or {}).items():
            out.add((rung or {}).get("id") or f"{fam}-{quant}")
    return out

chart = yaml.safe_load(open("charts/llama-swap/values.yaml"))
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
ids = model_ids(chart.get("config") or {})
ids |= model_ids((svc.get("llama-swap") or {}).get("config") or {})
assert "qwen3.8-27b-vllm" not in ids, "qwen3.8-27b-vllm is a local model id in the chart or gpu-ai overlay config"
PY
  ok "M3: catalog parses; q4 declares tools; flash-next q3/q4/strata exist with modelID/name/tools/262144 (HOLD); NO live qwen3.8-27b-vllm* row key (cf-143 C01 absence re-pin — the fork-lane rows are commented-out, one-edit-reversible per owner Q3); the peer wire name is shadow-free (R3 Q5.2)"
fi

# --- M4: serving-fact cross-check (AC8) -------------------------------------------
if want m4; then
  # cf-83 list = the ids the contract TEXT names. Current shape (post
  # 2026-11-22 rulings): the radiance defaults, the strata-q4/q3 documented
  # alternates, and qwen3.8-27b-q4 as the class table's 10+/background rung —
  # every one of them must already be served somewhere.
  # cf-143 C01: the vllm wire id LEAVES this loop — grep -F would false-green
  # on the commented-out rows' text (the disable keeps the comments for the
  # one-edit re-enable); its live-shape absence is pinned by
  # charts/llama-swap/tests/test_vllm_disable_contract.py (parse-level),
  # never by a file-wide grep.
  # cf-radiance C02 (chunk Tests, the explicit no-op guard): the ids the
  # routing move routes TO must already be served, so the list gains the two
  # radiance wire ids — gpu-ai/qwen3.8-flash-next-radiance (both tiers' default
  # + the runner) and gpu-ai/qwen3.8-27b-radiance (the D20 explicit Dense+Local
  # route). Both already appear in a serving authority (peers.radiance /
  # peers.radiance-q27 in the gpu-ai values), which is the point of the guard:
  # the routing move invents no unserved id. The two NEW lane ids this ticket
  # adds (…-tp1 / …-tp2) are C05's and are pinned in M9, not here — M4 must be
  # green at C02's review.
  for id in qwen3.8-27b-q4 qwen3.8-flash-next-strata-q4 qwen3.8-flash-next-q3 \
            qwen3.8-flash-next-radiance qwen3.8-27b-radiance; do
    if grep -qF "$id" charts/llama-swap/values.yaml || grep -qF "$id" services/gpu-ai/prod/values.yaml; then
      :
    else
      fail "M4[AC8]: contract-named id '$id' is absent from both serving authorities (charts/llama-swap/values.yaml, services/gpu-ai/prod/values.yaml) — routing must never point at an unserved id"
    fi
  done
  # cf-143 C01 Tests bullet 4: the retirement negative needle — the vllm
  # runbook CONTRACT SUITE goes away with the lane while the runbook DOC
  # survives with a DORMANT supersession header (engine dormant, owner
  # circles back — header only, body untouched).
  if [ -e tests/notes/vllm-runbook.sh ]; then
    fail "M4[cf-143 C01]: tests/notes/vllm-runbook.sh still exists — the vllm (vllm-radiance fork lane) contract suite retires with its catalog rows (owner Q3/D6); git rm it and note the retirement in charts/llama-swap/tests/TEST_SPEC.md"
  fi
  if [ ! -f .agents/notes/vllm-on-target-acceptance.md ]; then
    fail "M4[cf-143 C01]: .agents/notes/vllm-on-target-acceptance.md must REMAIN (header-only supersession; the disable never deletes the runbook body — reversible-while-disabled)"
  fi
  head30=$(head -30 .agents/notes/vllm-on-target-acceptance.md)
  printf '%s' "$head30" | grep -q "cf-143" \
    || fail "M4[cf-143 C01]: the vllm runbook header carries no cf-143 supersession marker (engine dormant, owner circles back)"
  printf '%s' "$head30" | grep -qiE 'superseded' \
    || fail "M4[cf-143 C01]: the vllm runbook header lacks the word 'superseded' (the DORMANT framing of the fork lane)"
  ok "M4[AC8 + cf-143 C01, ids extended cf-radiance C02]: every contract-named id (the two radiance lanes C02 routes to, qwen3.8-27b-q4 as the background rung, strata-q4/q3 as documented alternates) appears in a serving authority; the vllm-runbook suite is retired while the runbook doc lives with its cf-143 superseded header (the wire id's live-shape absence is pinned by the pytest disable contract)"
fi

# --- M5: boards skill — Model(s) line re-pinned, routing clauses re-pinned (AC1, AC3) --
if want m5; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "M5[AC2]: $f missing"
    grep -qF '`Qwen Large` | `Qwen Dense` | `Qwen Flash` | `Local`' "$f" \
      || fail "M5[AC1,AC3 cf-106 C02]: $f's Model(s) checklist option line is not 'Qwen Large | Qwen Dense | Qwen Flash | Local' — the middle label renames per the cf-106 OQ-6 ruling (still exactly four options; red before C02 lands the rename)"
    grep -qF 'Default selection: `Qwen Dense`' "$f" \
      || fail "M5[AC2 cf-106 C02]: $f's Model(s) line does not state 'Default selection: Qwen Dense' — the checklist default flips with the vocabulary (OQ-7: BOTH defaults flip); red until C02 lands it"
    python3 - "$f" <<'PY' || fail "M5[AC2]: the Model(s) checklist line gained a 'Flash Next' item — the checklist gains NO option (Q6); the combination of the existing checks is the mechanism"
import sys
for l in open(sys.argv[1]):
    if 'Qwen Large' in l and 'Qwen Flash' in l and 'Next' in l:
        sys.exit(1)
PY
    # cf-106 C02 (OQ-6/OQ-12 ruling): boards is the ALIAS HOME — the current
    # board spec must say out loud that a card checked `Qwen 27b` is consumed as
    # `Qwen Dense`, mark the alias temporary, and name WHY (the planned
    # provider-catalog rename). The sentence is new, so this leg is red until
    # C02 writes it.
    if ! python3 "$TMP/win.py" --ci "$f" 700 'Qwen 27b' 'Qwen Dense' 'alias' \
      || ! python3 "$TMP/win.py" --ci "$f" 1100 'alias' 'temporar' 'rename' \
      || ! python3 "$TMP/win.py" --ci "$f" 1100 'alias' 'catalog' \
      || ! python3 "$TMP/win.py" --ci "$f" 1100 'alias' 'retire'; then
      fail "M5[AC3 cf-106 C02]: $f carries no current-state alias sentence binding board-spec `Qwen 27b` to `Qwen Dense` that is marked temporary and cites the planned provider-catalog rename it retires with (OQ-6 ruling: no board label is touched, no new option — the alias is written prose; red until C02 writes it)"
    fi
    # Exactly one retired-vocabulary mention stays on the pair: the alias itself.
    # Anything else is current-state prose C02 missed.
    n27="$(grep -c 'Qwen 27b' "$f")"
    if [ "$n27" -gt 1 ]; then
      fail "M5[AC1 cf-106 C02]: $f mentions 'Qwen 27b' $n27 times — only the alias sentence may carry the retired label, every other current-state use must read Qwen Dense"
    fi
    ok "M5[AC3 cf-106 C02]: $f's only 'Qwen 27b' mention is the alias (alias sentence present, temporary-cited, and the retired label appears nowhere else)"
    # routing paragraph combination clauses (cf-radiance C02 re-pin: the
    # Flash+Local route moves to the radiance lane)
    python3 "$TMP/win.py" --ci "$f" 600 'flash' 'local' 'flash-next-radiance' 'assume' \
      || fail "M5[AC1 re-pinned cf-radiance C02]: $f's routing paragraph lacks the Flash+Local → flash-next-radiance 'assume' clause (2026-11-22 owner ruling, D4/D16)"
    # Single-authority (Q1/Q3): boards "references it, never duplicates its
    # table" — the generic escape names no ids, so zero alternate-lane text
    # lives on this pair (strata-q4 joins the q3/strix bars now that the route
    # moved to radiance).
    grep -qF 'qwen3.8-flash-next-strata-q4' "$f" \
      && fail "M5[AC1 re-pinned cf-radiance C02]: $f names qwen3.8-flash-next-strata-q4 — the Strata alternate is documented in the pipeline-models combination bullet only (single-authority, same law as the q3 bar)"
    grep -qF 'qwen3.8-flash-next-q3' "$f" \
      && fail "M5[AC2]: $f names qwen3.8-flash-next-q3 — the named alternate lives only in the pipeline-models bullet (red before C01)"
    grep -qF 'strix' "$f" \
      && fail "M5[AC3]: $f names strix — only the pipeline-models strata row clause may name it (Q3)"
    python3 "$TMP/win.py" --ci "$f" 600 'dense' 'local' 'qwen3.8-27b-radiance' 'unless' \
      || fail "M5[AC2 re-pinned cf-radiance C02/D20]: $f's routing paragraph lacks the Qwen Dense + Local → qwen3.8-27b-radiance unless-another-quant clause (owner ruling 2026-11-22 D20 moves this row; the 10+/background leg is NOT it)"
    grep -qF 'qwen3.8-27b-q4' "$f" \
      && fail "M5[AC2 re-pinned cf-radiance C02]: $f still routes a Local answer to qwen3.8-27b-q4 — every boards route string moves into the radiance family (D4/D16/D20); the class table's background leg lives in pipeline-models alone"
    # The blank-Model(s) card default: either it names the radiance lane or it
    # cites pipeline-models for the default — both are legal readings of the
    # cite-don't-restate law, a stale 27b-q4/strata sentence is not (the plan
    # does not settle which of the two shapes boards takes: recorded as a test
    # deviation, TEST_SPEC §4, so the leg accepts either).
    if ! python3 - "$f" <<'PY'
import re, sys
text = re.sub(r"\s+", " ", open(sys.argv[1]).read()).lower()
m = re.search(r"no item is checked.{0,400}", text)
if not m:
    print("no 'if NO item is checked' default sentence in the models bullet"); sys.exit(1)
win = m.group(0)
if 'radiance' not in win and 'pipeline-models' not in win:
    print(f"blank-Model(s) default names neither a radiance lane nor the pipeline-models authority: {win[:200]!r}"); sys.exit(1)
PY
    then fail "M5[AC2 re-pinned cf-radiance C02]: $f's blank-Model(s) card default resolves to nothing current (red until C02: it must name a radiance lane or cite pipeline-models)"; fi
    grep -qF 'qwen3.8-27b-q6' "$f" && fail "M5[AC2]: $f still routes only-Local to qwen3.8-27b-q6 (stale default after C06)"
  done
  ok "M5[AC1–AC3, re-pinned cf-radiance C02]: boards Model(s) line names the canonical four with Qwen Dense as the default selection (no fifth); the temporary alias sentence binds a live Qwen 27b check and is the retired label's only survivor on the pair; the routing paragraph carries the radiance combination clause and the D20 Dense+Local unless-clause with no strata/q3/strix/27b-q4 restatement, and the blank-card default resolves through a radiance lane or the pipeline-models citation"
fi

# --- M6: mirror integrity + regeneration contract (AC5) ----------------------------
if want m6; then
  for p in "$PM_SRC|$PM_GEN" "$PK_SRC|$PK_GEN" "$BD_SRC|$BD_GEN"; do
    IFS='|' read -r s g <<<"$p"
    [ -f "$s" ] && [ -f "$g" ] || fail "M6[AC5]: pair incomplete ($s / $g)"
    python3 "$TMP/pairsync.py" "$s" "$g" skill \
      || fail "M6[AC5]: source/generated pair out of sync for $s — regenerate, never hand-edit .opencode/"
  done
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "M6: rulesync not resolvable — generate gate skipped with warning (c7/t14 precedent)"
    ok "M6[AC5]: three skill pairs honest; generator gate skipped with warning"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "M6[AC5]: rulesync generate --check is not clean — generated surfaces stale"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "M6[AC5]: rulesync generate failed"; }
    before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "M6[AC5]: second generate failed"
    after=$(git status --porcelain)
    [ "$before" = "$after" ] || fail "M6[AC5]: the second rulesync generate is not a no-op"
    ok "M6[AC5]: three skill pairs honest; generate --check clean; second generate a no-op (via $RS)"
  fi
fi

# --- M7: cf-105 Priority wiring (C04; designed-red before the dev edit) ------
# The board's Priority NUMBER custom field becomes a first-class kickoff
# answer (D11): the boards roster gains the second field + the D12 carve-out,
# the card-driven kickoff gains the priority bullet + the launch-prompt value,
# pipeline-kickoff gains the board-scoped record slot (the live Questions list
# keeps exactly its two questions), and pipeline-models publishes the
# single-authority class table. None of the needles exists yet, so M7 reds
# naming C04; C04 is the last chunk to touch these skills, so nothing is
# designed-red after it (cf-83 posture). Checked on source AND generated twin
# (a half-regenerate cannot pass).
# Re-pin note (cf-83 precedent): C04's edits are additive at every pinned
# location — M1's pipeline-models pins and M5's boards routing pins sit
# adjacent to the new text but no pinned phrase changes, so NO M1..M6 arm
# needed a C04 re-pin (they stay byte-untouched above); the only M1..M6
# re-pins in this suite are M3's two vLLM catalog rows + shadow-free bar and
# M4's vllm wire id, both C03's (suite header, cf-105 handoff posture).
# Re-pin note (cf-105-vllm-followup C02, 2026-11-06): the four-class
# amendment supersedes cf-105 D6/HR2 cell-for-cell — the default row's cell
# 10 -> 5, a low row (8-9 / 9) joins the table, the background marker 4+ ->
# 10+, the floor prose 10 -> 5, and the favorited table gains the -low row.
# The boards/kickoff halves' NEEDLES stay byte-untouched (D6: cite-only —
# only the absence guard's marker moves, 4+ -> 10+); M3's C01 catalog
# re-pin feeds the cross-file leg below.
# cf-124 C03 RE-PIN (OQ7 → D20): the "input-only / NEVER written back" bar is
# the ban's doctrine lock and the ban is REVOKED — the arm is re-cut, not
# deleted: same bullet, same strictness, now pinning the permission (MAY write
# — own claimed card + cards this run creates) and the boundary (bulk + every
# other card still need explicit owner direction; owner-run backfill), with
# the ban phrases as rejects. Every roster needle above stays unchanged; the
# three roster-family reds elsewhere stay red with verbatim messages.
if want m7; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "M7[AC3]: $f missing"
    # Roster: the Custom-fields bullet names BOTH board fields, resolved by name.
    python3 "$TMP/win.py" "$f" 500 'slug' 'Priority' 'list_custom_fields' \
      || fail "M7[AC3]: $f's Custom-fields bullet does not name both board fields (slug + Priority) with list_custom_fields name-resolution in one span (designed-red before C04)"
    # The D12 carve-out: Priority is a serving-class field; model choice still
    # rides the Model(s) checklist.
    python3 "$TMP/win.py" --ci "$f" 500 'serving-class' 'choice still rides the model(s) checklist' \
      || fail "M7[AC3]: $f lacks the D12 carve-out (Priority is a serving-class field consumed at kickoff; model choice still rides the Model(s) checklist)"
    # Retired-field roster semantics survive the re-pin.
    python3 "$TMP/win.py" --ci "$f" 400 'session' 'retired' \
      || fail "M7[AC3]: $f lost the 'legacy session field retired' roster semantic"
    # Whitespace-tolerant phrase bars (prose wraps mid-phrase; a line-bound
    # grep would false-red on a rewrap of an otherwise intact semantic).
    phrased 'no `models` custom field' "$f" \
      || fail "M7[AC3]: $f lost the 'no models custom field' roster semantic (D12)"
    # The real text reads "Nor a `pipeline` field" (D19) — the needle must be
    # a substring of that phrasing, not of the chunk's summary of it.
    phrased '`pipeline` field' "$f" \
      || fail "M7[AC3]: $f lost the 'no pipeline field' roster semantic (D19)"
    # The priority kickoff bullet, scoped to the Card-driven kickoff section.
    python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^## Card-driven kickoff[^\n]*\n.*?(?=^## |\Z)", text, re.S)
assert m, "no Card-driven kickoff section"
open(sys.argv[2], "w").write(m.group(0))
' "$f" "$TMP/kd.md" || fail "M7[AC3]: $f has no '## Card-driven kickoff' section"
    python3 "$TMP/win.py" "$TMP/kd.md" 400 'Priority' 'string→int' 'kickoff.priority' '{raw, class}' \
      || fail "M7[AC3]: $f's Card-driven kickoff section lacks the priority bullet (Priority + string→int + kickoff.priority + {raw, class} in one span)"
    # cf-124 C03 (OQ7 → D20): the input-only/never-written-back doctrine is
    # REVOKED. M7 was that ban's lock, not a wording pin — re-cut at equal
    # strictness rather than deleted: the bar now pins the NEW permission and
    # its two boundaries, and the withdrawn ban phrases become the defect.
    python3 "$TMP/win.py" --ci "$TMP/kd.md" 700 'priority' 'may' 'card this run claims' 'cards this run creates' \
      || fail "M7[cf-124 C03 AC1/AC2]: $f's priority bullet does not state the new permission in one span (Priority MAY be written — on the card this run claims and on cards this run creates) (designed red until C03 lands the ban-lift)"
    python3 "$TMP/win.py" --ci "$TMP/kd.md" 700 'bulk' 'explicit owner direction' \
      || fail "M7[cf-124 C03 AC2]: $f's priority bullet lacks the boundary — every other card and ALL bulk board-data mutation still need explicit owner direction (the lift is a permission, not a mandate and not a sweep authorization; the ~90-card leg stays the owner-run backfill)"
    phrased 'input-only' "$f" \
      && fail "M7[cf-124 C03 AC1]: $f still calls the Priority field 'input-only' — the owner revoked that doctrine (D20); the phrase is the defect now"
    phrased 'never written back' "$f" \
      && fail "M7[cf-124 C03 AC1]: $f still bars agent writes with 'NEVER written back' — the ban sentence must be replaced by the bounded permission, in the same bullet. The roster's retired-`session` 'never read, never written' clause is a different sentence and must survive (C03 AC5)"
    # The launch-prompt block names the Priority value alongside the slug value.
    python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^## Launch prompt to agent-plan[^\n]*\n.*?(?=^## |\Z)", text, re.S)
assert m, "no Launch prompt section"
open(sys.argv[2], "w").write(m.group(0))
' "$f" "$TMP/lp.md" || fail "M7[AC3]: $f has no '## Launch prompt to agent-plan' section"
    python3 "$TMP/win.py" --ci "$TMP/lp.md" 400 'slug' 'priority' 'cardnumber' \
      || fail "M7[AC3]: $f's launch-prompt block does not name the Priority value alongside the slug value and cardNumber"
    # Single-authority guard (cite-don't-restate): the background leg's
    # literal '10+' marker is pipeline-models' text alone — a bare absence
    # grep (the contract's "grep must be empty"), the same discipline as the
    # q3/strix bars. The word "background" itself is allowed: the D12
    # carve-out sentence names the background leg without the marker.
    grep -qF '10+' "$f" \
      && fail "M7[AC4]: $f carries the literal '10+' marker — the class table's background leg lives ONLY in pipeline-models"
  done
  for f in "$PK_SRC" "$PK_GEN"; do
    [ -f "$f" ] || fail "M7[AC3]: $f missing"
    # The record slot: priority {raw, class}, scoped to board runs.
    python3 "$TMP/win.py" --ci "$f" 400 'priority' '{raw, class}' 'board' \
      || fail "M7[AC3]: $f lacks the kickoff priority {raw, class} slot scoped to board runs"
    # The live Questions list keeps exactly its two questions (slug + models)
    # — the Priority field is board-intake-only, never a live question.
    python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^## Questions[^\n]*\n.*?(?=^## |\Z)", text, re.S)
assert m, "no Questions section"
nums = re.findall(r"(?m)^\s*\d+\.\s", m.group(0))
assert len(nums) == 2, f"the live Questions list must carry exactly two numbered questions, found {len(nums)}"
low = m.group(0).lower()
assert "slug" in low and "models" in low, "the two questions must be the slug and the models questions"
' "$f" || fail "M7[AC3]: $f's live Questions list no longer carries exactly its two questions (slug + models)"
    # Single-authority guard (kickoff half): the literal '10+' marker is
    # pipeline-models' text alone — same bare absence bar as the boards half.
    grep -qF '10+' "$f" \
      && fail "M7[AC4]: $f carries the literal '10+' marker — the class table's background leg lives ONLY in pipeline-models"
  done
  for f in "$PM_SRC" "$PM_GEN"; do
    [ -f "$f" ] || fail "M7[AC4]: $f missing"
    # The class table's BACKGROUND row is NOT vllm-shaped (it routes
    # gpu-ai/qwen3.8-27b-q4, llama.cpp — off any peer) and stands unchanged
    # across cf-143, so it stays the live M7 table leg (10+ marker included).
    # The urgent/default/low row cells, the polarity sentence and the three
    # favorited vLLM rows retired with cf-143 C01's vllm disable (suite
    # header); cf-143 C05 re-pins them for the radiance trio in M8 —
    # deliberately NOT in M7, so every review from C01 to C04 passes bare.
    python3 -c '
import re, sys
# Cells are conventionally backtick-wrapped (the plan table writes `1`-`3`);
# the contract is the cell TEXT, so match on backtick-stripped lines.
lines = [ln.replace("`", "").lower()
         for ln in open(sys.argv[1]).read().splitlines()
         if ln.lstrip().startswith("|")]
def find(cells, rx=None, must_not=()):
    for low in lines:
        if all(c.lower() in low for c in cells) and not any(b in low for b in must_not) \
           and (rx is None or re.search(rx, low)):
            return low
    return None
r3 = find(["background", "qwen3.8-27b-q4", "n/a"]) or find(["background", "qwen3.8-27b-q4", "n-a"])
assert r3, "class table: no background row (10+ / background / qwen3.8-27b-q4 / n-a)"
assert re.search(r"\b10\s*\+", r3), f"class table: background row lacks the 10+ card-Priority marker: {r3}"
' "$f" || fail "M7[AC4]: $f lacks the class table's background row leg (the cf-143-invariant row of the single-authority table)"
  done
  # Cross-file (cf-143 C01 re-pin of the cf-105 peers.vllm floor leg): the
  # vllm era is ABSENT at the live-parse level — peers.vllm gone and no live
  # charts.vllm entry (grep would false-green on the surviving comments; the
  # parsed shapes are the disable contract, chunks/C01.md AC1). The radiance
  # floor 5 takes the priority-wiring role in M8 (C04+C05 authority).
  python3 -c '
import sys, yaml
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
peer = ((svc.get("llama-swap") or {}).get("config") or {}).get("peers", {})
assert "vllm" not in peer, "cf-143 C01: llama-swap.config.peers.vllm is still a LIVE key — the vllm (vllm-radiance fork lane) peer must be commented out (Q3)"
assert "vllm" not in (svc.get("charts") or {}), "cf-143 C01: charts.vllm still live — the ApplicationSet entry must be commented out"
' || fail "M7[cf-143 C01]: the vllm disable is not live-parsed-absent in services/gpu-ai/prod/values.yaml (the floor-5 wiring role moves to peers.radiance in M8)"
  grep -qF 'qwen3.8-27b-q4' charts/llama-swap/values.yaml \
    || grep -qF 'qwen3.8-27b-q4' services/gpu-ai/prod/values.yaml \
    || fail "M7[AC5]: the background-leg rung qwen3.8-27b-q4 is absent from the serving authorities (chart catalog or gpu-ai overlay)"
  ok "M7[cf-105 C04, re-pinned cf-105-vllm-followup C02, retired the vllm cells at cf-143 C01]: boards roster names both fields + the D12 carve-out with the retired semantics intact, the priority kickoff bullet and launch-prompt value are present, the kickoff slot is board-scoped with the two-question list intact, the class table's background leg lives in pipeline-models alone, the vllm era is parse-absent in the gpu-ai values, the background rung serves, and no 10+/background leg text leaks into boards/kickoff"
fi

# --- M8: cf-143 radiance catalog + priority-coherence legs (C05; designed-red ---
# until C05 lands — wave 4. Run explicitly: `bash tests/pipeline-models/surface.sh
# M8` alongside the bare M1..M7 set at C05 review and the final review; NOT in
# the default set, so every earlier bare run stays honest (suite header, cf-143
# posture). Contract: chunks/C05.md "## Tests" — M-leg radiance re-pins (rows
# 9/5/1 higher-wins, ctx 200000 == the shipped maxModelLen — SUPERSEDED by the
# owner's 2026-11-22 catalog edit (M8-A/M8-B headers; TEST_SPEC §1) and made
# family-wide by D47, input [text,image]),
# the strata-KEEP needles (Q5 made executable), the negative peer-id bar, the
# four-surface priority coherence (catalog rows / peer floor 5 / class table +
# per-engine polarity / chart polarity comment — AC4's "one needle set... as a
# unit"), and the retirement-footnote shape of the vllm class rows in the
# favorited table ("live-inventory convention; test needle decides exact shape":
# vllm ids stay named in pipeline-models prose, never as live table rows).
# Cross-file legs additionally wait on C02 (chart scalars/polarity comment) and
# C04 (peers.radiance) — both predecessors of C05's wave, so C05's bar is full
# green. The table legs run against SOURCE AND generated mirror (M6's pairsync
# + generate --check is the mirror-integrity extension the chunk names: a
# half-regenerate cannot pass M8 + M6 together).
if want m8; then
  [ -f "$CAT" ] || fail "M8: $CAT missing"
  cat >"$TMP/rad-catalog.js" <<'JS'
// M8-A: the radiance trio HOLD (D7 honest ids, Q2 higher-wins 9/5/1, Q8
// [text,image]). Context law, re-pinned by 2026-11-feat-radiance-multi-instance
// (TEST_SPEC §1): the owner's catalog edit (b3d7fada8, 2026-11-22, protected by
// DECISIONS D27 — "never those six context values") puts limit.context 262144
// (the trained window OpenCode budgets against) on every radiance-family row,
// while the pod SERVES --max-model-len 200000 (the radiance roster block in
// services/gpu-ai/prod/values.yaml — C03 moved lane data out of the chart).
// The cf-143 equality needle (ctx == the shipped maxModelLen) is therefore
// RETIRED BY RULING, not dropped: M8-B below pins the served scalar and the
// documented divergence instead. The wire modelID is SHARED on all three rows
// (the vllm row pattern mirrored: only body.priority differs).
const fs = require('fs');
function load(p) { return eval('(' + fs.readFileSync(p, 'utf8') + ')'); }
const o = load(process.argv[2]);
const provs = o.providerMetas || o.providers || {};
const models = (provs['gpu-ai'] || {}).models || {};
const capEq = (a, b) => Array.isArray(a) && a.length === b.length && a.every((x, i) => x === b[i]);
const CTX_CATALOG = 262144;
const errs = [];
for (const [k, prio] of [['qwen3.8-flash-next-radiance', 5],
                         ['qwen3.8-flash-next-radiance-urgent', 9],
                         ['qwen3.8-flash-next-radiance-low', 1]]) {
  const e = models[k];
  if (!e) { errs.push(`${k}: catalog row missing — the fn trio is SHIPPED (cf-143 C05); its disappearance is a regression, not a pending chunk`); continue; }
  if (e.modelID !== 'qwen3.8-flash-next-radiance')
    errs.push(`${k}: modelID is ${e.modelID}, want the shared wire value qwen3.8-flash-next-radiance (D7)`);
  if (!e.limit || e.limit.context !== CTX_CATALOG)
    errs.push(`${k}: limit.context is ${JSON.stringify((e.limit || {}).context)}, want ${CTX_CATALOG} (the owner's radiance catalog figure — b3d7fada8, protected by D27; re-pinning it to the served 200000 is an owner act, not a ticket act)`);
  if (!e.body || e.body.priority !== prio)
    errs.push(`${k}: body.priority is ${JSON.stringify((e.body || {}).priority)}, want ${prio} (Q2 HIGHER-WINS: urgent 9 / default 5 / low 1 — a 1/5/9 port of the retired vLLM numbers is exactly the inversion bug RESEARCH RQ2 names)`);
  if (!e.name) errs.push(`${k}: no descriptive name`);
  const caps = e.capabilities || {};
  if (!capEq(caps.input, ['text', 'image']))
    errs.push(`${k}: capabilities.input is ${JSON.stringify(caps.input)}, want ["text","image"] (Q8 — vision tower verified in-pack RQ0; the runbook image-smoke leg retires the claim on failure)`);
  if (!capEq(caps.output, ['text']))
    errs.push(`${k}: capabilities.output is ${JSON.stringify(caps.output)}, want ["text"]`);
  if (caps.tools !== true)
    errs.push(`${k}: capabilities.tools is ${JSON.stringify(caps.tools)}, want true`);
}
// M8-A extended by cf-143 C15: TWO trios HOLD — fn's loop above stays
// byte-unchanged (its 9/5/1 are not stolen, not inverted, not re-pinned) and
// the q27 trio joins STRICTLY BELOW it at 8/4/0 (OQ-16 approved; higher-wins
// polarity preserved on both). priority-0 semantics are UNVERIFIED engine
// behaviour (no doc floor row; vLLM's priority=0=unset precedent does NOT
// transfer) — these arms pin the AUTHORED values, and C16's smoke read is
// the receipt that confirms them; a correction re-pins via prose fold, never
// a silent retarget (§R19-Q4/D56(5)).
for (const [k, prio] of [['qwen3.8-27b-radiance', 4],
                         ['qwen3.8-27b-radiance-urgent', 8],
                         ['qwen3.8-27b-radiance-low', 0]]) {
  const e = models[k];
  if (!e) { errs.push(`${k}: catalog row missing (C15 adds the q27 trio)`); continue; }
  if (e.modelID !== 'qwen3.8-27b-radiance')
    errs.push(`${k}: modelID is ${e.modelID}, want the shared q27 wire value qwen3.8-27b-radiance (honest-id law, the fn trio's D7 pattern cloned)`);
  if (!e.limit || e.limit.context !== CTX_CATALOG)
    errs.push(`${k}: limit.context is ${JSON.stringify((e.limit || {}).context)}, want ${CTX_CATALOG} (the owner's radiance-family catalog figure — b3d7fada8/D27; q27's PER-SESSION served ceiling stays the chart's --max-model-len 200000, and the ~335-409K aggregate is a CONCURRENCY caveat, not a context number — §R19-Q1)`);
  if (!e.body || e.body.priority !== prio)
    errs.push(`${k}: body.priority is ${JSON.stringify((e.body || {}).priority)}, want ${prio} (OQ-16: 8/4/0 sits strictly below fn's 9/5/1 without inverting higher-wins — the strict-less-than relation is this exact-pin arithmetic, fn's rows pinned above)`);
  if (!e.name) errs.push(`${k}: no descriptive name`);
  else if (!/radiance/i.test(e.name))
    errs.push(`${k}: name "${e.name}" does not carry the Radiance disambiguation (fn's trio shares the model family — the name must name the lane)`);
  const caps = e.capabilities || {};
  if (!capEq(caps.input, ['text', 'image']))
    errs.push(`${k}: capabilities.input is ${JSON.stringify(caps.input)}, want ["text","image"] (Q8 pattern — vision tower in-pack §R19-S1; the C16 smoke retires the claim on failure)`);
  if (!capEq(caps.output, ['text']))
    errs.push(`${k}: capabilities.output is ${JSON.stringify(caps.output)}, want ["text"]`);
  if (caps.tools !== true)
    errs.push(`${k}: capabilities.tools is ${JSON.stringify(caps.tools)}, want true`);
}
// M8-A2 (chunks/C05.md Tests, "Catalog-shape test — live-row set =="):
// the cf-143 DELTA contract against the test-wave frozen base (captured
// 2026-11-11 from the parsed catalog). Exactly -3 vllm rows, everything
// else byte-present ("strata five-ish as today" rides this same equality;
// M3's HOLD legs keep their shape).
// cf-143 C15 RE-FREEZE — test-lane choice RECORDED HERE (chunks/C15.md T5;
// TEST_SPEC §12.15): the base gains fn's landed radiance trio
// (CF143_C15_BASE_KEYS = the frozen 86 + trio), so the delta law keeps the
// original exact-equality shape. Alternative rejected then and still
// rejected: a per-wave multi-delta law (two deltas to reason about at once
// — drift-prone in exactly the ledger style this ticket keeps paying for).
// The 86-key snapshot stays as the historical base; later bases are derived
// from it, never re-captured from the live catalog (a live-capture base
// would freeze unrelated future growth).
// D19/C05 RE-FREEZE — 2026-11-22 (test landing round), same precedent, one
// step up: the C15 delta (the q27 trio) has become history, so the base
// gains the LANDED q27 trio too (D19_BASE_KEYS = C15 base + q27 trio) and
// the live delta is exactly D19's SIX new trio rows — flash-TP1's and
// 27b-TP2's trios — added, the vllm trio removed, nothing else. This is
// deliberately M9-B's law restated at M8's parse point, NOT a third
// formulation (M9-B derives the same base from CF143_BASE_KEYS + landed
// trios and wants the same six); the freeze keeps its teeth — the
// exact-equality shape means a SEVENTH row reddens the leg, which is what
// a frozen delta is for.
const CF143_BASE_KEYS = ["home-3b-v3","home-3b-v3-gpu","local/qwen3.8-27b","ornith-1.5-122b-q3","ornith-1.5-122b-q4","ornith-1.5-122b-q5","ornith-1.5-122b-q6","ornith-1.5-122b-strata-q4","qwen3-vl-2b-bf16","qwen3-vl-2b-bf16:caption","qwen3-vl-2b-bf16:tags","qwen3-vl-2b-q4","qwen3-vl-2b-q4:caption","qwen3-vl-2b-q4:tags","qwen3-vl-2b-q8","qwen3-vl-2b-q8:caption","qwen3-vl-2b-q8:tags","qwen3-vl-30b-a3b","qwen3-vl-30b-a3b-bf16","qwen3-vl-30b-a3b-bf16:caption","qwen3-vl-30b-a3b-bf16:tags","qwen3-vl-30b-a3b-q4","qwen3-vl-30b-a3b-q4:caption","qwen3-vl-30b-a3b-q4:tags","qwen3-vl-30b-a3b-q8","qwen3-vl-30b-a3b-q8:caption","qwen3-vl-30b-a3b-q8:tags","qwen3-vl-30b-a3b-thinking-bf16","qwen3-vl-30b-a3b-thinking-q4","qwen3-vl-30b-a3b-thinking-q8","qwen3-vl-4b","qwen3-vl-4b-bf16","qwen3-vl-4b-bf16:caption","qwen3-vl-4b-bf16:tags","qwen3-vl-4b-q4","qwen3-vl-4b-q4:caption","qwen3-vl-4b-q4:tags","qwen3-vl-4b-q8","qwen3-vl-4b-q8:caption","qwen3-vl-4b-q8:tags","qwen3-vl-4b-thinking-bf16","qwen3-vl-4b-thinking-q4","qwen3-vl-4b-thinking-q8","qwen3-vl-8b","qwen3-vl-8b-bf16","qwen3-vl-8b-bf16:caption","qwen3-vl-8b-bf16:tags","qwen3-vl-8b-q4","qwen3-vl-8b-q4:caption","qwen3-vl-8b-q4:tags","qwen3-vl-8b-q8","qwen3-vl-8b-q8:caption","qwen3-vl-8b-q8:tags","qwen3.6-27b-q6","qwen3.6-27b-q8","qwen3.6-35b-a3b-1m","qwen3.6-35b-a3b-bf16","qwen3.6-35b-a3b-q6","qwen3.6-35b-a3b-q8","qwen3.6-35b-a3b-q8-visual","qwen3.8","qwen3.8-27b-bf16","qwen3.8-27b-q4","qwen3.8-27b-q6","qwen3.8-27b-q8","qwen3.8-27b-q8-1m","qwen3.8-27b-q8-visual","qwen3.8-27b-vllm","qwen3.8-27b-vllm-low","qwen3.8-27b-vllm-urgent","qwen3.8-flash-next-heretic-q4","qwen3.8-flash-next-orca-q6","qwen3.8-flash-next-q3","qwen3.8-flash-next-q4","qwen3.8-flash-next-strata","qwen3.8-flash-next-strata-orca","qwen3.8-flash-next-strata-q4","qwen36-heretic","qwen36-huihui","qwen38-ara","qwen38-heretic","qwen38-humanlike","qwen38-orca","qwen38-orca-f16","qwen38-rana","whisper-large-v3"];
const CF143_C15_BASE_KEYS = CF143_BASE_KEYS.concat(["qwen3.8-flash-next-radiance",
    "qwen3.8-flash-next-radiance-urgent", "qwen3.8-flash-next-radiance-low"]);
const D19_BASE_KEYS = CF143_C15_BASE_KEYS.concat(["qwen3.8-27b-radiance",
    "qwen3.8-27b-radiance-urgent", "qwen3.8-27b-radiance-low"]);
const liveKeys = Object.keys(models).sort();
const added = liveKeys.filter(k => !D19_BASE_KEYS.includes(k));
const removed = D19_BASE_KEYS.filter(k => !liveKeys.includes(k));
const wantAdded = ['qwen3.8-flash-next-radiance-tp1', 'qwen3.8-flash-next-radiance-tp1-urgent',
                   'qwen3.8-flash-next-radiance-tp1-low',
                   'qwen3.8-27b-radiance-tp2', 'qwen3.8-27b-radiance-tp2-urgent',
                   'qwen3.8-27b-radiance-tp2-low'].sort();
const wantRemoved = ['qwen3.8-27b-vllm', 'qwen3.8-27b-vllm-urgent', 'qwen3.8-27b-vllm-low'].sort();
const deltaOk = (add, rem) =>
  JSON.stringify(add) === JSON.stringify(wantAdded) && JSON.stringify(rem) === JSON.stringify(wantRemoved);
if (!deltaOk(added, removed))
  errs.push(`live catalog rows added vs the D19 base are ${JSON.stringify(added)}, want exactly the six new trio rows (D19 full trios for the two resting lanes — the frozen delta bars a seventh row as firmly as it bars a missing one; fn's and q27's trios live inside the re-frozen base)`);
if (JSON.stringify(removed) !== JSON.stringify(wantRemoved))
  errs.push(`live catalog rows removed vs the D19 base are ${JSON.stringify(removed)}, want exactly the vllm trio (C01 disable — every other row stays live, strata AND the landed radiance trios included)`);
// Teeth (M9-A2's philosophy carried onto the freeze): the planted seventh row
// MUST fail the equality. If a future edit loosens the gate to a superset
// check, this arm reddens first — a delta that cannot refuse growth is a
// inventory print, not a freeze.
if (deltaOk(added.concat(['qwen3.8-planted-seventh']).sort(), removed))
  errs.push('M8-A2 is vacuous: a planted seventh row passed the frozen-delta equality');
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/rad-catalog.js" "$CAT" \
    || fail "M8: the radiance catalog contract is violated (FOUR trios under one ladder: fn 9/5/1 + q27 8/4/0 HOLD + D19's two resting-lane trios via M9 — shared modelIDs, higher-wins un-inverted, ctx 262144 the owner's trained figure with the served 200000 reconciled in prose, input [text,image], tools true; frozen delta vs the D19 base (added == the six new trio rows exactly, a seventh row refuses) — chunks/C05.md Tests + chunks/C15.md T5 + M8 header)"
  # M8-B: the ctx axis, both ends + the documented divergence. The cf-143 leg
  # asserted catalog ctx == the shipped maxModelLen; the owner's 2026-11-22
  # catalog edit (b3d7fada8, D27) makes the two figures deliberately different,
  # so the equality needle is retired BY RULING and replaced by three teeth:
  # the served scalar, the catalog figure, and the catalog comment that names
  # both figures where the rows sit (an unexplained gap between what the
  # client budgets and what the pod serves is the drift class this suite
  # catches — the numbers may differ, the prose may not go quiet).
  # [2026-11-23 bug-radiance-27b-context-window D4, re-pinned by ruling D9 —
  # the restated pairing law, annotated]: D47 restates as per-lane
  # `trained >= served` with EQUALITY LEGAL; post-C02 every radiance lane
  # serves 262144, so the fn pair COLLAPSES to equality (served == trained)
  # and the "catalog figure stays ABOVE the served" half retires with the
  # divergence. The three teeth, restated: (1) the served scalar is the
  # chart's 262144 (PROVISIONAL until C04; designed-red naming C02 while the
  # env stands at 200000); (2) the comment still names 200000 — post-move
  # that is the PRE-MOVE served figure, kept by the stale comment (the
  # restatement is the owner's C04 leg; if it drops 200000 from the prose,
  # this needle's re-pin is a recorded C04 follow-up, not pre-authored);
  # (3) the window carries 262144 (the row value + the comma-normalised
  # comment spelling "262,144") — green pre- and post-C02.
  python3 - <<'PY' || fail "M8: the radiance ctx axis drifted off its ruling (served scalar / catalog figure / the comment that reconciles them)"
import re, sys, yaml
try:
    svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
except FileNotFoundError:
    sys.exit("services/gpu-ai/prod/values.yaml missing — the ctx needle's carrier (the radiance roster block) cannot be read")
block = ((svc.get("radiance") or {}).get("app-template") or {})
# D43 (2026-11-22) re-anchor: the pod's served admission ceiling reaches the
# engine as the RADIANCE_MAX_MODEL_LEN env the compose wrapper feeds to
# --max-model-len; the era's block scalar + inline arg pair retired with the
# rendered argv (the composed-vector equality runs in the chart suite — this
# arm anchors the AUTHORING site). Designed-red naming dev round 3 while the
# lane env has not landed.
lanectr = (((block.get("controllers") or {}).get("radiance") or {}).get("containers") or {}).get("radiance") or {}
env = {e.get("name"): e.get("value") for e in lanectr.get("env") or []}
mm = env.get("RADIANCE_MAX_MODEL_LEN")
assert mm is not None and str(mm) == "262144", (
    f"the radiance block env RADIANCE_MAX_MODEL_LEN is {mm!r}, want 262144 — the pod's served "
    "admission ceiling (D9; PROVISIONAL until C04); designed-red naming C02 while the env "
    "stands at 200000; env is the lane's sizing channel since D43 and the chart suite pins "
    "the composed --max-model-len to it"
)
src = open(".opencode/opencode.jsonc").read()
low = src.lower()
gap = low.find("qwen3.8-flash-next-radiance")
assert gap >= 0, "no radiance row in the provider catalog"
block = src[max(0, gap - 3000):gap + 200]
flat = block.replace(",", "")
assert "200000" in flat, (
    "the radiance catalog commentary never names the pre-move served figure 200000 — post-C02 "
    "this is the historical figure the stale comment keeps until the owner's C04 restatement leg "
    "(the needle's re-pin is a recorded C04 follow-up if the restatement drops it)"
)
assert "262144" in flat, (
    "the radiance window never carries the trained/served figure 262144 — post-C02 trained == "
    "served == 262144 (the D4 collapsed pair); the row value and the comma-normalised comment "
    "spelling are both in-window, so this half is defense in depth on the value"
)
PY
  # M8-C: serving-fact cross-check (the cf-83 M4 role, radiance era): the wire
  # id is SERVED via peers.radiance (golden authority), and the strata ids
  # STILL appear in peers.strata.models (Q5 — the live default lane untouched).
  python3 - <<'PY' || fail "M8: the radiance wire id is not in peers.radiance.models, or a strata id vanished from peers.strata.models (serving-fact law + Q5 KEEP needle)"
import sys, yaml
ev = yaml.safe_load(open("charts/llama-swap/tests/evidence/radiance-peers-expected.yaml"))["radiance"]
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
peers = ((svc.get("llama-swap") or {}).get("config") or {}).get("peers") or {}
rad = peers.get("radiance")
assert rad is not None, "peers.radiance missing — C04 must land before C05's bar (wave 3 dep)"
assert rad.get("models") == ev["models_allowed"], f"peers.radiance.models {rad.get('models')!r} != the evidence-ruled id list"
floor = ((rad.get("filters") or {}).get("setParams") or {}).get("priority?")
assert floor == 5, f"peers.radiance priority? floor is {floor!r}, want 5 (Q2 default class under higher-wins — the M8 coherence unit: catalog 9/5/1 + floor 5 + PM table + chart comment)"
sev = yaml.safe_load(open("charts/llama-swap/tests/evidence/strata-peers-expected.yaml"))["strata"]
strata_models = (peers.get("strata") or {}).get("models") or []
assert strata_models in sev["models_states"], f"peers.strata.models {strata_models} left the sanctioned waves (Q5 violation)"
PY
  # M8-C15: the q27 clone of the serving-fact leg (designed-RED until dev D3
  # lands peers.radiance-q27): the q27 wire id is SERVED via its OWN peer at
  # ITS OWN evidence floor 4 — fn's block above is byte-verbatim, the floor
  # comparison is per-peer (a 5 on the q27 hop takes a rank D54 records as
  # NOT stolen, and a missing peer makes every q27 catalog row a phantom
  # route).
  python3 - <<'PY' || fail "M8: the q27 wire id is not served via peers.radiance-q27 at the evidence floor 4 (C15 serving-fact clone — designed-red naming C15-dev D3)"
import yaml
ev27 = yaml.safe_load(open("charts/llama-swap/tests/evidence/radiance-q27-peers-expected.yaml"))["radiance-q27"]
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
peers = ((svc.get("llama-swap") or {}).get("config") or {}).get("peers") or {}
q27 = peers.get("radiance-q27")
assert q27 is not None, "peers.radiance-q27 missing — C15 dev D3 has not landed (designed-red naming C15)"
assert q27.get("models") == ev27["models_allowed"], f"peers.radiance-q27.models {q27.get('models')!r} != the evidence-ruled q27 id list"
assert "/v1" not in (q27.get("proxy") or ""), "the q27 peer proxy carries a /v1 suffix — request paths append verbatim (every peer's law)"
floor = ((q27.get("filters") or {}).get("setParams") or {}).get("priority?")
assert floor == ev27["filters"]["setParams"]["priority?"], (
    f"peers.radiance-q27 priority? floor {floor!r} != the evidence floor (4 — q27's default class; "
    "fn's 5 is NOT reused — D54 records \"fn's ranks are NOT stolen\"; M8 coherence unit for the q27 lane: "
    "catalog 8/4/0 + floor 4)"
)
PY
  # M8-D: the negative needle (local-ids-shadow-peers law, R3 Q5.2 mirrored
  # from M3): the radiance wire id must NOT be a local llama-swap model id.
  # cf-143 C15: the needle CLONES per q27 wire id — the same shadow class
  # applies to gpu-ai-radiance-q27 (a local q27 id would out-rank the peer
  # and silently misroute the very lane the pod-swap exists to serve).
  python3 - <<'PY' || fail "M8: a radiance/q27 wire id is declared as a local llama-swap model id — it would shadow its own unqualified peer (the precedence bug that kept the vllm id out of the local map)"
import yaml
def model_ids(cfg):
    out = set((cfg or {}).get("models") or {})
    for fam, spec in ((cfg or {}).get("families") or {}).items():
        for quant, rung in ((spec or {}).get("quants") or {}).items():
            out.add((rung or {}).get("id") or f"{fam}-{quant}")
    return out
chart = yaml.safe_load(open("charts/llama-swap/values.yaml"))
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
ids = model_ids(chart.get("config") or {}) | model_ids((svc.get("llama-swap") or {}).get("config") or {})
for wire in ("qwen3.8-flash-next-radiance", "qwen3.8-27b-radiance"):
    assert wire not in ids, f"{wire} is a local model id in the chart or gpu-ai overlay config"
PY
  for f in "$PM_SRC" "$PM_GEN"; do
    [ -f "$f" ] || fail "M8[C05]: $f missing"
    # M8-E: the re-pinned class table (engine-scoped value column, radiance
    # cells, 9/5/1, intervals + the 10+ background leg unchanged), per-engine
    # polarity with the RETIRED-vLLM-lane guard sentence (the chunk's verbatim
    # marks), the re-pinned floor sentence, and the favorited table: radiance
    # row joins, strata-q4 row STAYS, vllm ids survive only OUTSIDE table
    # rows (retirement footnotes, live-inventory convention).
    python3 - "$f" <<'PY' || fail "M8[C05]: $f diverges from the re-pinned radiance tables/polarity (diagnostics above)"
import re, sys
path = sys.argv[1]
text = open(path).read()
lines = [ln.replace("`", "").lower() for ln in text.splitlines() if ln.lstrip().startswith("|")]
def find(cells, rx=None, must_not=()):
    for low in lines:
        if all(c.lower() in low for c in cells) and not any(b in low for b in must_not) \
           and (rx is None or re.search(rx, low)):
            return low
    return None
errs = []
header = [ln for ln in lines if "class" in ln or "priority" in ln]
if not any(("radiance" in ln and "body.priority" in ln) for ln in header):
    errs.append("the class table value column is not renamed engine-scoped (Radiance body.priority)")
# cf-126 C04 RE-PIN of the three class-table rows: the default/urgent/low
# routes move to the q27 trio (8/4/0); the background row and the polarity
# law stay; the floor citation follows the default class onto q27 (verify,
# never re-derive — M8-C15 already pins the serving-side floor 4). fn's
# catalog trio and favorited rows survive UNTOUCHED above (M8-A) — the table
# moved, the inventory did not. DESIGNED RED until C04's gate facts land.
r1 = find(["urgent", "qwen3.8-27b-radiance-urgent"], rx=r"1\s*[–\-—]\s*3")
if not r1 or not re.search(r"\|\s*8\s*\|", r1):
    errs.append("no urgent row (1-3 / urgent / qwen3.8-27b-radiance-urgent / 8) — the C04 class-row move (was fn-urgent/9)")
r2 = find(["default", "qwen3.8-27b-radiance", "unset"], must_not=["-urgent", "-low"])
if not r2 or not re.search(r"\|\s*4\s*\|", r2):
    errs.append("no default row (unset / default / qwen3.8-27b-radiance / 4) — the C04 default-class flip cites the q27 lane's own priority (was fn/5)")
rl = find(["low", "qwen3.8-27b-radiance-low"], rx=r"8\s*[–\-—]\s*9")
if not rl or not re.search(r"\|\s*0\s*\|", rl):
    errs.append("no low row (8-9 / low / qwen3.8-27b-radiance-low / 0) — the C04 move (was fn-low/1)")
# The stale pre-flip cells are the drift the two-tree sweep must not hide:
# a restored fn class row after the flip redds here (M8-A's catalog pins and
# the favorited fn rows are NOT this sentence — the table taught routes, the
# inventory teaches serving).
for stale in (["urgent", "qwen3.8-flash-next-radiance-urgent"], ["low", "qwen3.8-flash-next-radiance-low"]):
    if find(stale):
        errs.append(f"class table still carries the pre-C04 route cell {stale} — only the Model-row column moved, and it moved fully")
if find(["default", "qwen3.8-flash-next-radiance", "unset"], must_not=["-urgent", "-low"]):
    errs.append("class table default row still routes fn radiance — C04 moved the default class to the q27 lane")
r3 = find(["background", "qwen3.8-27b-q4"]) 
if not r3 or not re.search(r"\b10\s*\+", r3):
    errs.append("the background row (10+ / qwen3.8-27b-q4) changed — the chunk rules it UNCHANGED")
low_t = text.lower()
if not re.search(r"radiance[^\n]{0,200}higher[^\n]{0,40}wins|higher[^\n]{0,30}wins[^\n]{0,200}radiance", low_t):
    errs.append("no per-engine polarity: radiance higher-wins since cf-143 is not stated")
if not re.search(r"retired vllm lane[^\n]{0,120}lower-wins|lower-wins[^\n]{0,120}retired vllm lane", low_t):
    errs.append("the vLLM-history sentence lacks the RETIRED-lane (lower-wins) mark")
if "never port" not in low_t:
    errs.append("'never port those numbers to radiance' is missing (Q2 verbatim guard)")
if not re.search(r'peers\.radiance-q27[^\n]{0,80}priority\?[^\n]{0,30}= ?4|priority\?[^\n]{0,40}=? ?4[^\n]{0,120}peers\.radiance-q27', low_t):
    errs.append('the floor sentence is not re-pinned to peers.radiance-q27.filters.setParams "priority?" = 4 — the C04 default-class move carries the set-if-undefined floor citation onto the q27 lane (verify, never re-derive: the serving floor already stands at 4, M8-C15)')
def favrow(cell):
    for ln in lines:
        cells = [c.strip().strip("`").strip() for c in ln.strip().strip("|").split("|")]
        if cell in cells and "gpu-ai" in cells:
            return ln
    return None
if not favrow("qwen3.8-flash-next-radiance"):
    errs.append("favorited models: no gpu-ai row keyed qwen3.8-flash-next-radiance")
# cf-143 C15 (D6): the q27 lane joins the favorited table as a MEASURED
# OPT-IN candidate beside fn — designed-red until D6 lands the row + the
# generated twin. The class table keeps fn's routes UNTOUCHED (the fn trio
# rows above stay pinned byte-verbatim; q27 never becomes a default route
# and the runner-model literal does not move — D54(4)).
if not favrow("qwen3.8-27b-radiance"):
    errs.append("favorited models: no gpu-ai row keyed qwen3.8-27b-radiance (C15/D6 adds the q27 lane as a measured opt-in candidate)")
if not favrow("qwen3.8-flash-next-strata-q4"):
    errs.append("favorited models: the strata-q4 row vanished — Q5 says it STAYS (still the default)")
vllm_rows = [ln for ln in lines if "qwen3.8-27b-vllm" in ln]
if vllm_rows:
    errs.append(f"the vllm rows are still live TABLE rows in pipeline-models ({len(vllm_rows)} lines) — retirement footnotes must sit outside the tables")
if "qwen3.8-27b-vllm" not in low_t:
    errs.append("the vllm ids vanished from pipeline-models prose entirely — the retirement footnote is required (dormant-by-owner-ruling, not deleted, echoes Q3/D6)")
if errs:
    print("; ".join(errs), file=sys.stderr); sys.exit(1)
PY
    # M8-F (FLIPPED by 2026-11-feat-radiance-multi-instance C02): cf-143's leg
    # KEPT strata-q4 as the DEFAULT route on every surface. The 2026-11-22
    # rulings demote it, so the arm now pins the NEW shape:
    #   - pipeline-models: the id SURVIVES (documented alternate + inventory
    #     row) and the ROUTED form is the defect (M1 bars the routed string,
    #     M1 window-pins the alternate sentence — this leg re-pins both so the
    #     flip is visible inside the arm that used to demand the old KEEP);
    #   - pipeline-kickoff / boards: single-authority, so the id must be GONE
    #     (the same bar the q3 alternate has always had);
    #   - the catalog/serving side keeps the lane live and served via M3's HOLD
    #     rows and M4's serving-authority loop — demoted, never deleted.
    python3 - "$f" <<'PY' || fail "M8[cf-radiance C02]: $f diverges from the demoted-Strata shape (diagnostics above)"
import re, sys
path = sys.argv[1]
text = re.sub(r"\s+", " ", open(path).read())
if "gpu-ai/qwen3.8-flash-next-strata-q4" not in text:
    print("the strata-q4 id vanished from pipeline-models — the 2026-11-22 ruling DEMOTES the Strata default to one documented alternate; deleting the lane's inventory is not part of that ruling"); sys.exit(1)
if "assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-strata-q4`" in text:
    print("strata-q4 is still the ROUTED form — the combination rule must route gpu-ai/qwen3.8-flash-next-radiance (D4/D16)"); sys.exit(1)
PY
  done
  python3 -c '
import re, sys
for f in (".rulesync/skills/pipeline-kickoff/SKILL.md", ".rulesync/skills/boards/SKILL.md"):
    t = re.sub(r"\s+", " ", open(f).read())
    if "gpu-ai/qwen3.8-flash-next-strata-q4" in t:
        print(f"{f}: still routes Flash+Local to gpu-ai/qwen3.8-flash-next-strata-q4 — the 2026-11-22 ruling moves the route to the radiance lane and the Strata alternate lives ONLY in the pipeline-models combination bullet (single-authority, the same law as the q3 bar)"); sys.exit(1)
' || fail "M8[cf-radiance C02]: the strata route string survives in pipeline-kickoff/boards — M8-F's KEEP flipped to a single-authority BAR when D4/D16 moved the default to radiance"
  # M8-G: the chart polarity comment (AC4's fourth surface — one unit with the
  # catalog rows, the floor and the class table).
  python3 - <<'PY' || fail "M8[AC4]: the charts/radiance priority comment block does not complete the four-surface coherence unit"
import re, sys
try:
    text = open("charts/radiance/values.yaml").read()
except FileNotFoundError:
    sys.exit("charts/radiance/values.yaml missing — C02 not landed (the polarity-comment surface)")
low = text.lower()
if not re.search(r"higher[^\n]{0,60}wins", low):
    sys.exit("the chart priority block never states higher-wins (Q2)")
if "opposite" not in low or "vllm" not in low:
    sys.exit("the chart block never marks the OPPOSITE polarity of the retired vLLM table (Q2/C02 task)")
for tok in ("429", "5000", "peers.radiance"):
    if tok not in text:
        sys.exit(f"the chart priority block lacks {tok!r} (preempt-wait-ms default / 429+Retry-After / the pointer at the C04 floor)")
PY
  # M8-H (re-authored by 2026-11-feat-radiance-multi-instance C02 from cf-143's
  # empty-diff touch-bar): the RUNNER-LITERAL PAIRING leg. The old leg failed on
  # ANY touch of overview.md/pipeline-worker.md, which blocked exactly the edit
  # the 2026-11-22 ruling (D16) ordered; the new bar is PAIRING — the six
  # surfaces that carry the runner literal must carry the SAME byte, and moving
  # one without moving the others fails. The CF143_BASE_SHA git-diff idiom
  # survives as the second half (per-range pairing, review-time).
  python3 - <<'PY' || fail "M8[cf-radiance C02 AC4]: the runner-model literal is not paired across its six surfaces (single-authority law — one byte, six carriers)"
import re, sys

RUNNER = "gpu-ai/qwen3.8-flash-next-radiance"  # owner ruling 2026-11-22 (D16)
SOURCES = {
    ".agents/loops/pipeline-worker.md": r"^model:\s*(\S+)\s*$",
    ".rulesync/rules/overview.md": r"runner model `([^`]+)`",
    "AGENTS.md": r"runner model `([^`]+)`",
    "tests/opencode/pipeline-locks-tick.test.ts": r'fields\.model,\s*"([^"]+)"',
    "tests/provider-loops/surface.sh": r"model\s*[=:]\s*(gpu-ai/[A-Za-z0-9._/-]+)",
    "tests/agent-board-coord/agents-md.sh": r"'loop' (?:\|\|[^\n]*)?'(gpu-ai/[^']+)'",
}

def literals(texts):
    out = {}
    for path, rx in SOURCES.items():
        hits = re.findall(rx, texts[path].replace("\\.", "."), re.M)
        hits = sorted({h for h in hits if h.startswith("gpu-ai/")})
        out[path] = hits
    return out

texts = {p: open(p).read() for p in SOURCES}
lit = literals(texts)
missing = {p: h for p, h in lit.items() if not h}
assert not missing, f"no runner-model literal parsed out of {sorted(missing)} — the extractor is the thing that broke, fix the leg"
distinct = {h for hits in lit.values() for h in hits}
assert len(distinct) == 1, (
    "the six runner surfaces disagree: "
    + "; ".join(f"{p}={h}" for p, h in sorted(lit.items()) if len(h) != 1 or h[0] != next(iter(distinct)))
    + " — the pairing law is one byte across loops, rules, generated AGENTS.md and every byte-pin"
)
cur = next(iter(distinct))
assert cur == RUNNER, (
    f"the paired runner literal is {cur}, want {RUNNER} (owner ruling 2026-11-22; the chain cf-106 OQ-14 2026-11-03 -> 2026-11-09 strata-q4 -> 2026-11-22 radiance "
    "must be cited where the literal lives — a re-pin rewrites the byte everywhere at once, never one surface)"
)

# Teeth: an inventory that cannot fail is the vacuous-needle class FRICTION
# already recorded, so the comparison runs against a planted drift — mutate one
# surface and the leg must see exactly that surface as the odd one out.
drifted = dict(texts)
drifted[".agents/loops/pipeline-worker.md"] = drifted[".agents/loops/pipeline-worker.md"].replace(RUNNER, "gpu-ai/planted-drift-model", 1)
dlit = literals(drifted)
dvals = {h for hits in dlit.values() for h in hits}
assert len(dvals) == 2, "the pairing comparison cannot see a planted single-surface drift — the leg is vacuous"
odd = sorted(p for p, h in dlit.items() if h != [RUNNER])
assert odd == [".agents/loops/pipeline-worker.md"], f"planted drift reported the wrong surface(s): {odd}"
PY
  if [ -n "${CF143_BASE_SHA:-}" ]; then
    # Range half (the idiom this leg keeps): over a review range, the six
    # carriers move together or not at all.
    touched=$(git diff --name-only "$CF143_BASE_SHA"...HEAD -- .agents/loops/pipeline-worker.md .rulesync/rules/overview.md AGENTS.md tests/opencode/pipeline-locks-tick.test.ts tests/provider-loops/surface.sh tests/agent-board-coord/agents-md.sh)
    n=$(printf '%s\n' "$touched" | grep -c . || true)
    [ "$n" -eq 0 ] || [ "$n" -eq 6 ] \
      || fail "M8[cf-radiance C02 AC4]: the range vs $CF143_BASE_SHA moves $n of the 6 runner-literal carriers: $touched — the pairing law moves all six in one commit or none"
    ok "M8: radiance TWO-trio HOLD (fn 9/5/1 + q27 8/4/0 under un-inverted higher-wins, shared modelIDs, the owner's 262144 ctx figure with the served 200000 scalar reconciled in prose, [text,image] + tools) + serving cross-check (peers.radiance.models == evidence floor 5; peers.radiance-q27 == its evidence floor 4) + re-frozen delta + strata DEMOTION shape (PM alternate kept, kickoff/boards barred, lane kept served) + negative peer-id bars + re-pinned class/favorited tables on source AND mirror + chart polarity comment + the runner-literal pairing leg, range-pairing checked vs $CF143_BASE_SHA"
  else
    skip "M8: runner-literal range half not run — review sets CF143_BASE_SHA=<merge-base> and re-runs M8 (git diff check, chunks/C02.md Tests)"
    ok "M8: radiance TWO-trio HOLD (fn 9/5/1 + q27 8/4/0 under un-inverted higher-wins, shared modelIDs, the owner's 262144 ctx figure with the served 200000 scalar reconciled in prose, [text,image] + tools) + serving cross-check (peers.radiance.models == evidence floor 5; peers.radiance-q27 == its evidence floor 4) + re-frozen delta + strata DEMOTION shape (PM alternate kept, kickoff/boards barred, lane kept served) + negative peer-id bars + re-pinned class/favorited tables on source AND mirror + chart polarity comment + the runner-literal pairing leg with planted-drift teeth (range half skipped: CF143_BASE_SHA unset)"
  fi
fi

# --- M9: cf-radiance C05 four-lane roster legs (designed-red until C05) ----------
# The two NEW lanes' law-order trio: evidence YAML -> peers entry -> catalog
# row. Designed-RED naming C05 (the rows/peers/roster do not exist yet); NOT in
# the default set, so every earlier chunk's bare run stays honest, and C05's
# review runs it explicitly with M1..M8 (the cf-143 M8 posture, re-used).
#
# Priority numbers, RESOLVED BY THE COORDINATOR'S FOLLOW-UP RULING on the test
# author's D-3: the plan's starting shape stands — 7/3/2 + 6/2/1, floors each
# lane's OWN default row (3/2, the per-lane M8 coherence law). The earlier
# negative-rung resolution (-1/-2) is REJECTED on evidence: the catalog has only
# ever shipped non-negative body.priority (the six live rows, 0..9), and cf-143
# already records priority-0 semantics as UNVERIFIED with the CI smoke as the
# receipt — an authoring session does not extend an unverified behaviour class
# into untested negatives on its own authority (TEST_SPEC §3 carries the law).
# D19's shipped collision — 27b-tp2 low 1 duplicating fn low 1 — is an ACCEPTED
# CROSS-PEER TIE, not a collision: the four lanes are four separate engines with
# four separate queues, each peer's `priority?` floor is per lane, and no M8 law
# requires cross-peer uniqueness. What the suite still pins: full trios, urgent/
# def columns cross-lane unique and strictly below the live lanes, every trio
# strictly decreasing within its lane, and NO negative rung anywhere.
#
#   lane              urgent  default  low     peer floor (== its own default)
#   fn        (live)     9       5       1      5
#   q27       (live)     8       4       0      4
#   flash-tp1 (new)      7       3       2      3
#   q27-tp2   (new)      6       2       1      2
#
# The low rungs 2 and 1 sit inside the shipped, smoke-proven range (fn's low has
# served 1 since cf-143; the ladder keeps 0 for q27). The on-target smoke read
# stays the receipt for the values as shipped; a correction re-pins here through
# a DECISIONS line, never a silent retarget.
#
# The ctx half (owner ruling D47, 2026-11-23, added by the C05 landing round's
# follow-up): every radiance-family row carries limit.context 262144 — the
# trained window the CLIENT budgets against — and the commentary governing the
# six NEW rows must name BOTH figures (trained 262144 / served 200000), the same
# pairing law M8-B enforces at the fn rows. D47 flipped the six rows the C05 dev
# authored at 200000 to the family figure; the reviewer's dissent (200000 equals
# served admission, so no truncation class exists at 200000; the risk runs the
# other way — over-budgeted requests meet a loud server refusal) is recorded in
# FRICTION, not here. Before this leg NO leg read the new rows' ctx in either
# direction — D27's recurring lesson: an unpinned convention drifts.
if want m9; then
  [ -f "$CAT" ] || fail "M9: $CAT missing"
  cat >"$TMP/fleet.js" <<'JS'
const fs = require('fs');
function load(p) { return eval('(' + fs.readFileSync(p, 'utf8') + ')'); }
const o = load(process.argv[2]);
const models = (((o.providerMetas || o.providers || {})['gpu-ai'] || {}).models) || {};

// The four lanes of the radiance family, lane rank order (fn first).
const LANES = [
  { base: 'qwen3.8-flash-next-radiance',      urgent: 9, def: 5, low: 1, floor: 5 },
  { base: 'qwen3.8-27b-radiance',             urgent: 8, def: 4, low: 0, floor: 4 },
  { base: 'qwen3.8-flash-next-radiance-tp1',  urgent: 7, def: 3, low: 2, floor: 3 },
  { base: 'qwen3.8-27b-radiance-tp2',         urgent: 6, def: 2, low: 1, floor: 2 },
];
// D47 ctx law, value half: the trained-window figure every radiance row must
// carry. Stated for ALL four lanes (the family-wide law); the six NEW rows are
// the drift class D47 was asked about — fn/q27 duplication of M8-A's pin is
// deliberate defence in depth, one law two places, not a second formulation.
const CTX_FIGURE = 262144;
// [2026-11-23 bug-radiance-27b-context-window D4/D9 — dated per-lane
// annotation, value UNCHANGED]: pre-C02 the single served figure was 200000 on
// all four lanes; post-C02 EVERY radiance lane serves 262144 (served ==
// trained, the D47 pair collapsed to equality per lane — plan fact 13,
// verified against the jsonc row census). The constant stays 200000 on
// purpose: it is the PROSE half's needle (the stale commentary's pre-move
// figure, kept green until the owner's C04 restatement leg), not a claim
// about what any lane serves. The per-lane served column is TEST_SPEC §1's,
// not a leg constant.
const SERVED_FIGURE = 200000;
function ctxValueErr(key, e) {
  if (!e.limit || e.limit.context !== CTX_FIGURE)
    return `${key}: limit.context is ${JSON.stringify((e.limit || {}).context)}, want ${CTX_FIGURE} — the D47 family figure (the trained window the client budgets against); the served ${SERVED_FIGURE} belongs in the commentary, never in the row`;
  return null;
}
// D47 ctx law, prose half: the commentary GOVERNING the six new rows must name
// BOTH figures. Boundaries derive from the row keys' own file order (live-lane
// rows bound the slice backward, each new row forward) — no literal comment text
// is pinned, so a re-worded block stays green while it names both numbers; the
// comma spelling (262,144) is normalised. M8-B owns the fn/q27 commentary; this
// covers the new family only.
function ctxProseErrors(raw, modelsObj) {
  const bad = [];
  const occ = {};
  for (const k of Object.keys(modelsObj)) {
    const i = raw.indexOf(`"${k}": {`);
    if (i >= 0) occ[k] = i;
  }
  const isLive = (base) => base === 'qwen3.8-flash-next-radiance' || base === 'qwen3.8-27b-radiance';
  const laneKeys = (l) => [l.base, l.base + '-urgent', l.base + '-low'];
  const liveKeys = LANES.filter(l => isLive(l.base)).flatMap(laneKeys);
  const restKeys = LANES.filter(l => !isLive(l.base)).flatMap(laneKeys);
  const missing = restKeys.filter(k => occ[k] === undefined);
  if (missing.length)
    return [`ctx prose: new-family row key(s) ${missing.join(', ')} not found — the governing commentary cannot be located (the rows must exist for D47 to govern them)`];
  const firstNew = Math.min(...restKeys.map(k => occ[k]));
  const liveOccs = liveKeys.map(k => occ[k]).filter(i => i !== undefined && i < firstNew);
  const famStart = liveOccs.length ? Math.max(...liveOccs) : 0;
  for (const k of restKeys) {
    const slice = raw.slice(famStart, occ[k]);
    const prose = slice.split('\n').filter(l => /^\s*\/\//.test(l)).join(' ').replace(/,/g, '');
    if (!prose.includes(String(CTX_FIGURE)) || !prose.includes(String(SERVED_FIGURE)))
      bad.push(`${k}: the commentary governing this new-family row does not name BOTH figures (trained ${CTX_FIGURE} / served ${SERVED_FIGURE}) — D47 keeps the client/served pair stated wherever the rows sit (mirrors M8-B's fn-side pairing law; the numbers may differ, the prose may not go silent)`);
  }
  return bad;
}
const errs = [];
const rows = {};
for (const lane of LANES) {
  for (const [suffix, prio] of [['-urgent', lane.urgent], ['', lane.def], ['-low', lane.low]]) {
    const key = lane.base + suffix;
    const e = models[key];
    rows[key] = prio;
    if (!e) {
      // The two live lanes are shipped; the two new ones are C05's rows.
      const live = lane.base === 'qwen3.8-flash-next-radiance' || lane.base === 'qwen3.8-27b-radiance';
      errs.push(`${key}: catalog row ${live ? 'vanished (regression — the live lane is shipped)' : 'missing (C05 registers the full trio per D19)'}`);
      continue;
    }
    if (e.modelID !== lane.base)
      errs.push(`${key}: modelID is ${e.modelID}, want the lane's shared wire id ${lane.base} (honest-id law — the fn/q27 pattern, cloned)`);
    if (!e.body || e.body.priority !== prio)
      errs.push(`${key}: body.priority is ${JSON.stringify((e.body || {}).priority)}, want ${prio} (D19 lane ladder with the coordinator's follow-up ruling — TEST_SPEC §3 carries the law)`);
    if (!e.name) errs.push(`${key}: no descriptive name`);
    const caps = e.capabilities || {};
    if (!Array.isArray(caps.input) || !caps.input.includes('text'))
      errs.push(`${key}: capabilities.input ${JSON.stringify(caps.input)} does not serve text`);
    if (caps.tools !== true) errs.push(`${key}: capabilities.tools is ${JSON.stringify(caps.tools)}, want true`);
    const ctxErr = ctxValueErr(key, e);
    if (ctxErr) errs.push(ctxErr);
  }
}
// M9-A2: the class-column law, per the coordinator's follow-up ruling on D-3
// (TEST_SPEC §3), stated generally so any future lane reads the same law:
//  * urgent/def columns are CROSS-LANE law: pairwise unique, strictly decreasing
//    in lane rank (every new lane sits below both live lanes);
//  * the low column is PER-LANE law: the four lanes are four engines with four
//    queues, so low values may tie across lanes — the only sanctioned tie is the
//    D19 shipped one, fn low == 27b-tp2 low == 1, and a second unnamed tie is a
//    ruling away, not a slip;
//  * every trio is strictly decreasing within its own lane, and NO rung is
//    negative: the catalog has only ever shipped non-negative body.priority
//    (six live rows, 0..9) — negative rungs are out of the verified class.
const ACCEPTED_LOW_TIES = [['qwen3.8-flash-next-radiance', 'qwen3.8-27b-radiance-tp2']];
function lowTieErrors(lanes) {
  const bad = [];
  const seen = new Map();
  for (const lane of lanes) {
    const v = lane.low;
    if (seen.has(v)) {
      const a = seen.get(v), b = lane.base;
      const accepted = ACCEPTED_LOW_TIES.some(([x, y]) => (x === a && y === b) || (x === b && y === a));
      if (!accepted)
        bad.push(`low column: ${a} and ${b} both use ${v} — only the named fn/27b-tp2 tie is accepted (separate peers, separate queues; a second tie needs a ruling)`);
    } else seen.set(v, lane.base);
  }
  return bad;
}
for (const cls of ['urgent', 'def']) {
  const seen = new Map();
  for (const lane of LANES) {
    const v = lane[cls];
    if (seen.has(v)) errs.push(`class column ${cls}: ${seen.get(v)} and ${lane.base} both use priority ${v} — the ${cls} column is cross-lane unique`);
    else seen.set(v, lane.base);
  }
  const vals = LANES.map(l => l[cls]);
  for (let i = 1; i < vals.length; i++)
    if (!(vals[i] < vals[i - 1])) errs.push(`class column ${cls}: lane rank order not strictly decreasing (${vals.join(' > ')})`);
}
for (const lane of LANES) {
  if (!(lane.urgent > lane.def && lane.def > lane.low))
    errs.push(`${lane.base}: trio not strictly decreasing within the lane (${lane.urgent}/${lane.def}/${lane.low})`);
  if (lane.urgent < 0 || lane.def < 0 || lane.low < 0)
    errs.push(`${lane.base}: negative priority rung (${lane.urgent}/${lane.def}/${lane.low}) — the catalog ships only non-negative body.priority; negative rungs are UNVERIFIED behaviour and barred absent a fresh ruling (TEST_SPEC §3)`);
}
errs.push(...lowTieErrors(LANES));
// Teeth: the tie law must be able to fail, in BOTH directions. Half one: the
// shipped table itself carries the accepted fn/27b-tp2 low tie — if the policy
// over-rejected, the real run above would already have reddened. Half two: a
// SECOND, unnamed collision (flash-tp1 low := 0, clashing q27's shipped 0) must
// be reported.
{
  const planted = LANES.map(l => ({ ...l, low: l.base === 'qwen3.8-flash-next-radiance-tp1' ? 0 : l.low }));
  if (!lowTieErrors(planted).length) { console.log('M9-A2 is vacuous: the planted second low collision (flash-tp1 low 0 vs q27 low 0) went unreported'); process.exit(1); }
}
// The ctx law, live read + self-proving teeth (same philosophy as the tie
// teeth: a check that cannot fail cannot pass). Prose errors join the live
// verdict; the plants run in memory so the leg cannot rot into a rubber stamp.
{
  const rawSrc = fs.readFileSync(process.argv[2], 'utf8');
  errs.push(...ctxProseErrors(rawSrc, models));
  const victim = 'qwen3.8-flash-next-radiance-tp1';
  if (!models[victim]) {
    errs.push(`ctx teeth cannot run: ${victim} row is absent — the D47 ctx law is unexercised until the row lands`);
  } else if (!ctxValueErr(victim, { ...models[victim], limit: { ...models[victim].limit, context: 200000 } })) {
    console.log(`M9-A2 ctx teeth vacuous: a planted limit.context 200000 on ${victim} went unreported`);
    process.exit(1);
  }
  const stripped = rawSrc.split('\n').map(l => /^\s*\/\//.test(l) ? '' : l).join('\n');
  if (!ctxProseErrors(stripped, models).length) {
    console.log('M9-A2 ctx teeth vacuous: a catalog with every commentary line stripped went unreported (the JSON bodies still spell 262144 — only the prose carries the served figure)');
    process.exit(1);
  }
}
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/fleet.js" "$CAT" \
    || fail "M9[C05]: the four-lane radiance fleet contract is violated (four trios under one higher-wins ladder, TEST_SPEC §3; plus the D47 ctx law — every radiance row at limit.context 262144 and BOTH figures named in the new-family commentary) — designed-red naming C05 until D19's six rows land"
  # M9-B: the frozen-delta law, re-frozen at the pre-ticket catalog (the cf-143
  # C15 precedent): base := the C15 base + the q27 trio, so the delta is exactly
  # the SIX new trio rows and nothing else. A seventh row can only arrive as a
  # deliberate later wave.
  python3 - "$CAT" <<'PY' \
    || fail "M9[C05]: the live gpu-ai row set is not the frozen base plus exactly the six new trio rows (D19 delta contract)"
import re, subprocess, sys
# Parse the gpu-ai model keys with the same eval-as-object-literal trick the
# node legs use, but from python via node (single parser, no second dialect).
js = ("const fs=require('fs');const o=eval('('+fs.readFileSync(process.argv[1],'utf8')+')');"
      "console.log(Object.keys(((o.providerMetas||o.providers||{})['gpu-ai']||{}).models||{}).sort().join('\\n'))")
out = subprocess.run(["node", "-e", js, sys.argv[1]], capture_output=True, text=True)
assert out.returncode == 0, f"catalog parse failed: {out.stderr.strip()[:200]}"
live = out.stdout.split()
# Frozen base: the cf-143 C15 frozen 86 keys (read from this suite's own frozen
# constant — one source, no second snapshot to drift) plus the landed trios.
suite = open("tests/pipeline-models/surface.sh").read()
m = re.search(r"const CF143_BASE_KEYS = (\[[^\]]+\]);", suite)
assert m, "the frozen CF143_BASE_KEYS snapshot is gone from surface.sh — the delta law needs its base"
base = set(__import__("json").loads(m.group(1).replace("'", '"')))
base |= {"qwen3.8-flash-next-radiance", "qwen3.8-flash-next-radiance-urgent", "qwen3.8-flash-next-radiance-low",
         "qwen3.8-27b-radiance", "qwen3.8-27b-radiance-urgent", "qwen3.8-27b-radiance-low"}
want_added = {"qwen3.8-flash-next-radiance-tp1", "qwen3.8-flash-next-radiance-tp1-urgent",
              "qwen3.8-flash-next-radiance-tp1-low",
              "qwen3.8-27b-radiance-tp2", "qwen3.8-27b-radiance-tp2-urgent",
              "qwen3.8-27b-radiance-tp2-low"}
want_removed = {"qwen3.8-27b-vllm", "qwen3.8-27b-vllm-urgent", "qwen3.8-27b-vllm-low"}
added = set(live) - base
removed = base - set(live)
assert added == want_added, (f"rows added vs the frozen base: {sorted(added)} — want exactly the six new trio rows "
                             "(D19 registers full trios for the two new lanes, nothing else)")
assert removed == want_removed, f"rows removed vs the frozen base: {sorted(removed)} — want only the cf-143 vllm disable"
PY
  # M9-C: peers <-> evidence for the two new lanes, in law order, plus the KEEP
  # half (fn 5 / q27 4 floors and the strata lane unchanged — an additive wave
  # that moves an existing floor is the failure this leg exists to catch).
  python3 - <<'PY' || fail "M9[C05]: the new lanes' peers/evidence unit is not in place, or a live lane's floor moved (diagnostics above)"
import sys, yaml
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
peers = ((svc.get("llama-swap") or {}).get("config") or {}).get("peers") or {}
errs = []
for key, evfile, lane in (
        ("radiance", "radiance-peers-expected.yaml", "radiance"),
        ("radiance-q27", "radiance-q27-peers-expected.yaml", "radiance-q27"),
        ("radiance-flash-tp1", "radiance-flash-tp1-peers-expected.yaml", "radiance-flash-tp1"),
        ("radiance-q27-tp2", "radiance-q27-tp2-peers-expected.yaml", "radiance-q27-tp2")):
    try:
        ev = yaml.safe_load(open(f"charts/llama-swap/tests/evidence/{evfile}"))[lane]
    except FileNotFoundError:
        errs.append(f"{key}: evidence file charts/llama-swap/tests/evidence/{evfile} missing (law order — evidence FIRST)")
        continue
    p = peers.get(key)
    if p is None:
        errs.append(f"config.peers.{key} missing — C05 must join the lane through the peers seam")
        continue
    if p.get("models") != ev["models_allowed"]:
        errs.append(f"peers.{key}.models {p.get('models')!r} != the evidence id list {ev['models_allowed']!r}")
    floor = ((p.get("filters") or {}).get("setParams") or {}).get("priority?")
    want = ev["filters"]["setParams"]["priority?"]
    if floor != want:
        errs.append(f"peers.{key} priority? floor {floor!r} != the evidence floor {want!r} (the floor is the lane's OWN default-class row — the M8 coherence law, per lane)")
    if "/v1" in (p.get("proxy") or ""):
        errs.append(f"peers.{key}.proxy carries a /v1 suffix — request paths append verbatim")
    if p.get("apiKey"):
        errs.append(f"peers.{key} carries an apiKey — the lanes are keyless (cf-143 D8)")
    host = (p.get("proxy") or "").split("//")[-1].split(":")[0]
    if key != lane and False:
        pass
    want_host = "gpu-ai-" + key.replace("_", "-")
    if host.split(".")[0] != want_host:
        errs.append(f"peers.{key}.proxy host {host!r} does not derive from the roster key ({want_host}.default.svc…) — a drifting name silently breaks the route")
strata = (peers.get("strata") or {}).get("models") or []
sev = yaml.safe_load(open("charts/llama-swap/tests/evidence/strata-peers-expected.yaml"))["strata"]
if strata not in sev["models_states"]:
    errs.append(f"peers.strata.models {strata} left the sanctioned waves — an additive roster wave never moves the MoE lane")
if errs:
    print("; ".join(errs), file=sys.stderr); sys.exit(1)
PY
  # M9-D: the shadow bar and the solver-invisibility bar for both new wire ids.
  python3 - <<'PY' || fail "M9[C05]: a new radiance wire id shadows a local llama-swap model id, or sits in the outer models/matrix (peers are invisible to the solver — coexistence stays operator discipline)"
import yaml
def model_ids(cfg):
    out = set((cfg or {}).get("models") or {})
    for fam, spec in ((cfg or {}).get("families") or {}).items():
        for quant, rung in ((spec or {}).get("quants") or {}).items():
            out.add((rung or {}).get("id") or f"{fam}-{quant}")
    return out
chart = yaml.safe_load(open("charts/llama-swap/values.yaml"))
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
outer = (svc.get("llama-swap") or {}).get("config") or {}
ids = model_ids(chart.get("config") or {}) | model_ids(outer)
for wire in ("qwen3.8-flash-next-radiance-tp1", "qwen3.8-27b-radiance-tp2"):
    assert wire not in ids, f"{wire} is a LOCAL llama-swap model id — it would shadow its own unqualified peer"
    assert wire not in str(outer.get("matrix", "")), f"{wire} appears in the outer matrix — peers stay out of the arena"
PY
  # M9-E: the serving-fact guard extended to the new ids (the C05 half of the
  # M4 no-op guard — every id the tables name must be served somewhere).
  for id in qwen3.8-flash-next-radiance-tp1 qwen3.8-27b-radiance-tp2; do
    grep -qF "$id" services/gpu-ai/prod/values.yaml \
      || fail "M9[C05 AC2]: '$id' is absent from the gpu-ai serving authority (peers + lane block) — the tables must never name an unserved id"
  done
  # M9-F: the pipeline-models opt-in sentence on source AND generated twin.
  for f in "$PM_SRC" "$PM_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 900 'qwen3.8-flash-next-radiance-tp1' 'never a default' \
      || fail "M9[C05]: $f names the flash-TP1 lane without its never-a-default sentence (both new ids are opt-in resting lanes)"
    python3 "$TMP/win.py" --ci "$f" 900 'qwen3.8-27b-radiance-tp2' '502' \
      || fail "M9[C05]: $f names the 27b-TP2 lane without the 502-while-idle law (the resting lane refuses loudly — same sentence q27's row carries)"
  done
  ok "M9[C05]: four-trio radiance fleet (fn 9/5/1 · q27 8/4/0 · flash-tp1 7/3/2 · q27-tp2 6/2/1 — urgent/def cross-lane unique and strictly decreasing, trios strictly decreasing per lane, no negative rung, the fn/27b-tp2 low tie accepted per TEST_SPEC §3, floors 5/4/3/2 == each lane's own default row; D47 ctx: every row at limit.context 262144 with the served 200000 named in the governing commentary, both ctx teeth self-proven) + frozen delta == exactly the six new rows + evidence-first peers unit (no /v1, no apiKey, roster-derived hosts, strata wave kept) + shadow/matrix bars for the new wire ids + serving-authority guard + the PM opt-in/502-while-idle sentences on source and mirror — designed-red naming C05"
fi

printf 'PASS: pipeline-models contract checks (%d ok)\n' "$checks"
