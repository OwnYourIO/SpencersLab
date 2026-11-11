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
# Usage:
#   bash tests/pipeline-models/surface.sh            # M1..M7 (cf-143 default)
#   bash tests/pipeline-models/surface.sh M3 M4      # subset
#   bash tests/pipeline-models/surface.sh M8         # cf-143 radiance legs (C05+)
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
    [[ "$lc" =~ ^m[1-8]$ ]] || fail "unknown check id '$a' (expected M1..M8)"
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
    # 27b + Local → q4 with the explicit escape
    grep -qF 'gpu-ai/qwen3.8-27b-q4' "$f" \
      || fail "M1[AC1]: $f never routes 27b+Local to gpu-ai/qwen3.8-27b-q4 (red before C06)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-27b-q4' 'unless' \
      || fail "M1[AC1]: $f's q4 route lacks the 'unless another quant is requested' escape clause"
    # Flash+Local combination rule, pinned verbatim (cf-83 re-pin: same
    # phrases, new route)
    grep -qF 'assume Qwen Flash Next' "$f" \
      || fail "M1[AC1]: $f lacks the combination rule's pinned phrasing 'assume Qwen Flash Next' (cf-83 keeps the phrase — red only if dev deleted it)"
    grep -qF 'gpu-ai/qwen3.8-flash-next-strata-q4' "$f" \
      || fail "M1[AC1]: $f never routes Flash+Local to gpu-ai/qwen3.8-flash-next-strata-q4 (owner ruling 2026-11-09: the q4 Strata quant is the default)"
    grep -qF 'There is no plain-flash local route' "$f" \
      || fail "M1[AC1]: $f lacks the pinned 'There is no plain-flash local route.' clause (cf-83 keeps this phrase too)"
    # AC1 absence guard pins the ROUTE FORM, not the bare id: q3 legitimately
    # survives as the alternate sentence (Q1), so only the old routed string
    # is stale.
    grep -qF 'assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-strata`' "$f" \
      && fail "M1[AC1]: $f still carries the pre-ruling route string 'assume Qwen Flash Next: gpu-ai/qwen3.8-flash-next-strata' — the owner ruling 2026-11-09 re-keyed the default to -strata-q4"
    # AC2 documented-alternate (pipeline-models only, PM pair only): the
    # alternate sentence must co-locate q3 with its explicit-request escape —
    # windowed, not bare grep, so a stray mention elsewhere cannot satisfy it.
    python3 "$TMP/win.py" --ci "$f" 300 'qwen3.8-flash-next-q3' 'explicit' \
      || fail "M1[AC2]: $f no longer documents qwen3.8-flash-next-q3 as the explicit-request alternate in the combination bullet (cf-83 Q1)"
    # Local-only default follows the 27b default (q6 → q4)
    python3 "$TMP/win.py" --ci "$f" 300 'no model' 'qwen3.8-27b-q4' \
      || fail "M1[AC1]: $f's Local-only default is not qwen3.8-27b-q4 (was q6; C06 re-cuts it)"
    # stale q6 mappings removed outright
    grep -qF 'qwen3.8-flash-q6' "$f" && fail "M1[AC1]: $f still references qwen3.8-flash-q6 — C06 drops it outright, not as a fallback"
    grep -qF '27b → `gpu-ai/qwen3.8-27b-q6`' "$f" && fail "M1[AC1]: $f still maps 27b to q6 as the default route"
    grep -qF 'basename + `-q6`' "$f" && fail "M1[AC1]: $f still states the basename + -q6 assumption rule (stale after the q4 re-cut)"
    # favorited-models table (cf-83 Q2: exactly one gpu-ai flash-next row,
    # keyed strata, replacing the q3 row)
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
    python3 "$TMP/win.py" --ci "$f" 700 'no model' 'both tiers' 'qwen3.8-27b-q4' \
      || fail "M1[AC4 cf-106 C02]: $f never resolves a BLANK Model(s) to gpu-ai/qwen3.8-27b-q4 for BOTH tiers — the default flip is C02's second half (red before C02: the table still defaults both tiers to openrouter)"
    python3 "$TMP/win.py" --ci "$f" 700 'gpu-ai' 'default' 'openrouter' 'fallback' \
      || fail "M1[AC4 cf-106 C02]: $f never states the local-first provider posture (gpu-ai is the default, openrouter the documented explicit-choice/fallback) — red before C02 lands it"
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
  ok "M1[AC1–AC4]: pipeline-models carries the four-option picker with Qwen Dense replacing Qwen 27b (no fifth option, no stale 27b label), the q4 27b+Local route with the unless-escape, the pinned combination bullet routing Flash+Local to flash-next-strata-q4 with the pre-ruling strata/q3 route strings gone and q3 documented as the explicit-request alternate, Local-only q4, stale q6 routes gone, the single strata-q4 favorited row with the peers/arena clause, the blank-Model(s) → gpu-ai/qwen3.8-27b-q4 both-tiers default with the local-first posture and an explicit Dense check still mapping to openrouter, and a favorited table that leads with the local rows"
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
    # derivation updated: routes to the new ids
    grep -qF 'qwen3.8-27b-q4' "$f" \
      || fail "M2[AC2]: $f's derivation still defaults Local to q6 (no q4 route yet — red before C06)"
    grep -qF 'flash-next-strata-q4' "$f" \
      || fail "M2[AC1]: $f's derivation lacks the Flash+Local → flash-next-strata-q4 combination route (owner ruling 2026-11-09)"
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
  ok "M2[AC1–AC3]: kickoff keeps the four pinned options, cites pipeline-models, and its derivation carries the q4 default + flash-next-strata-q4 combination route with no q3/q4/strix restatement and no stale q6 claims"
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
  # cf-83 list = the ids the contract TEXT names: the two default routes
  # (27b+Local → q4, Flash+Local → strata-q4 per the owner ruling
  # 2026-11-09) plus q3 as the documented explicit-request alternate.
  # flash-next-q4 joins because the contract now names it as the default.
  # cf-143 C01: the vllm wire id LEAVES this loop — grep -F would false-green
  # on the commented-out rows' text (the disable keeps the comments for the
  # one-edit re-enable); its live-shape absence is pinned by
  # charts/llama-swap/tests/test_vllm_disable_contract.py (parse-level),
  # never by a file-wide grep. C05 re-pins the serving cross-check with
  # peers.radiance in M8 (the radiance wire id + the golden authority).
  for id in qwen3.8-27b-q4 qwen3.8-flash-next-strata-q4 qwen3.8-flash-next-q3; do
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
  ok "M4[AC8 + cf-143 C01]: every contract-named id (27b-q4 + flash-next-strata-q4 defaults, flash-next-q3 documented alternate) appears in a serving authority; the vllm-runbook suite is retired while the runbook doc lives with its cf-143 superseded header (the wire id's live-shape absence is pinned by the pytest disable contract)"
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
    # routing paragraph combination clauses (cf-83 re-pin: strata route)
    python3 "$TMP/win.py" --ci "$f" 600 'flash' 'local' 'flash-next-strata-q4' 'assume' \
      || fail "M5[AC1]: $f's routing paragraph lacks the Flash+Local → flash-next-strata-q4 'assume' clause (owner ruling 2026-11-09)"
    # Single-authority (Q1/Q3): boards "references it, never duplicates its
    # table" — the generic escape names no ids, so zero q3/strix text lives
    # on this pair.
    grep -qF 'qwen3.8-flash-next-q3' "$f" \
      && fail "M5[AC2]: $f names qwen3.8-flash-next-q3 — the named alternate lives only in the pipeline-models bullet (red before C01)"
    grep -qF 'strix' "$f" \
      && fail "M5[AC3]: $f names strix — only the pipeline-models strata row clause may name it (Q3)"
    python3 "$TMP/win.py" --ci "$f" 600 '27b' 'local' 'qwen3.8-27b-q4' 'unless' \
      || fail "M5[AC2]: $f's routing paragraph lacks the 27b+Local → q4 unless-another-quant clause (red before C06)"
    grep -qF 'qwen3.8-27b-q6' "$f" && fail "M5[AC2]: $f still routes only-Local to qwen3.8-27b-q6 (stale default after C06)"
  done
  ok "M5[AC1–AC3]: boards Model(s) line names the canonical four with Qwen Dense as the default selection (no fifth); the temporary alias sentence binds a live Qwen 27b check and is the retired label's only survivor on the pair; the routing paragraph carries the strata-q4 combination clause and the 27b+Local q4 unless-clause with no q3/strix restatement"
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
    python3 -c '
import re, sys
text = re.sub(r"\s+", " ", open(sys.argv[1]).read()).lower()
sys.exit(0 if "never written back" in text else 1)
' "$f" \
      || fail "M7[AC3]: $f's priority bullet lacks the 'NEVER written back' phrasing (the board field is input-only; post-plan write-back stays slug-only)"
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
# 9/5/1 higher-wins, ctx 200000 == the shipped maxModelLen, input [text,image]),
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
// [text,image], D17/Q10 ctx 200000 served truth — the 262,144-trained figure
// stays OUT of the row, D38 honesty pattern). The wire modelID is SHARED on
// all three rows (the vllm row pattern mirrored: only body.priority differs).
const fs = require('fs');
function load(p) { return eval('(' + fs.readFileSync(p, 'utf8') + ')'); }
const o = load(process.argv[2]);
const provs = o.providerMetas || o.providers || {};
const models = (provs['gpu-ai'] || {}).models || {};
const capEq = (a, b) => Array.isArray(a) && a.length === b.length && a.every((x, i) => x === b[i]);
const errs = [];
for (const [k, prio] of [['qwen3.8-flash-next-radiance', 5],
                         ['qwen3.8-flash-next-radiance-urgent', 9],
                         ['qwen3.8-flash-next-radiance-low', 1]]) {
  const e = models[k];
  if (!e) { errs.push(`${k}: catalog row missing (C05 adds the trio)`); continue; }
  if (e.modelID !== 'qwen3.8-flash-next-radiance')
    errs.push(`${k}: modelID is ${e.modelID}, want the shared wire value qwen3.8-flash-next-radiance (D7)`);
  if (!e.limit || e.limit.context !== 200000)
    errs.push(`${k}: limit.context is ${JSON.stringify((e.limit || {}).context)}, want 200000 (Q10 FULL profile served truth)`);
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
// M8-A2 (chunks/C05.md Tests, "Catalog-shape test — live-row set =="):
// the cf-143 DELTA contract against the test-wave frozen base (captured
// 2026-11-11 from the parsed catalog). Exactly +3 radiance rows, exactly
// -3 vllm rows, everything else byte-present ("strata rows five-ish as
// today" rides this same equality; M3's HOLD legs keep their shape).
const CF143_BASE_KEYS = ["home-3b-v3","home-3b-v3-gpu","local/qwen3.8-27b","ornith-1.5-122b-q3","ornith-1.5-122b-q4","ornith-1.5-122b-q5","ornith-1.5-122b-q6","ornith-1.5-122b-strata-q4","qwen3-vl-2b-bf16","qwen3-vl-2b-bf16:caption","qwen3-vl-2b-bf16:tags","qwen3-vl-2b-q4","qwen3-vl-2b-q4:caption","qwen3-vl-2b-q4:tags","qwen3-vl-2b-q8","qwen3-vl-2b-q8:caption","qwen3-vl-2b-q8:tags","qwen3-vl-30b-a3b","qwen3-vl-30b-a3b-bf16","qwen3-vl-30b-a3b-bf16:caption","qwen3-vl-30b-a3b-bf16:tags","qwen3-vl-30b-a3b-q4","qwen3-vl-30b-a3b-q4:caption","qwen3-vl-30b-a3b-q4:tags","qwen3-vl-30b-a3b-q8","qwen3-vl-30b-a3b-q8:caption","qwen3-vl-30b-a3b-q8:tags","qwen3-vl-30b-a3b-thinking-bf16","qwen3-vl-30b-a3b-thinking-q4","qwen3-vl-30b-a3b-thinking-q8","qwen3-vl-4b","qwen3-vl-4b-bf16","qwen3-vl-4b-bf16:caption","qwen3-vl-4b-bf16:tags","qwen3-vl-4b-q4","qwen3-vl-4b-q4:caption","qwen3-vl-4b-q4:tags","qwen3-vl-4b-q8","qwen3-vl-4b-q8:caption","qwen3-vl-4b-q8:tags","qwen3-vl-4b-thinking-bf16","qwen3-vl-4b-thinking-q4","qwen3-vl-4b-thinking-q8","qwen3-vl-8b","qwen3-vl-8b-bf16","qwen3-vl-8b-bf16:caption","qwen3-vl-8b-bf16:tags","qwen3-vl-8b-q4","qwen3-vl-8b-q4:caption","qwen3-vl-8b-q4:tags","qwen3-vl-8b-q8","qwen3-vl-8b-q8:caption","qwen3-vl-8b-q8:tags","qwen3.6-27b-q6","qwen3.6-27b-q8","qwen3.6-35b-a3b-1m","qwen3.6-35b-a3b-bf16","qwen3.6-35b-a3b-q6","qwen3.6-35b-a3b-q8","qwen3.6-35b-a3b-q8-visual","qwen3.8","qwen3.8-27b-bf16","qwen3.8-27b-q4","qwen3.8-27b-q6","qwen3.8-27b-q8","qwen3.8-27b-q8-1m","qwen3.8-27b-q8-visual","qwen3.8-27b-vllm","qwen3.8-27b-vllm-low","qwen3.8-27b-vllm-urgent","qwen3.8-flash-next-heretic-q4","qwen3.8-flash-next-orca-q6","qwen3.8-flash-next-q3","qwen3.8-flash-next-q4","qwen3.8-flash-next-strata","qwen3.8-flash-next-strata-orca","qwen3.8-flash-next-strata-q4","qwen36-heretic","qwen36-huihui","qwen38-ara","qwen38-heretic","qwen38-humanlike","qwen38-orca","qwen38-orca-f16","qwen38-rana","whisper-large-v3"];
const liveKeys = Object.keys(models).sort();
const added = liveKeys.filter(k => !CF143_BASE_KEYS.includes(k));
const removed = CF143_BASE_KEYS.filter(k => !liveKeys.includes(k));
const wantAdded = ['qwen3.8-flash-next-radiance', 'qwen3.8-flash-next-radiance-urgent', 'qwen3.8-flash-next-radiance-low'].sort();
const wantRemoved = ['qwen3.8-27b-vllm', 'qwen3.8-27b-vllm-urgent', 'qwen3.8-27b-vllm-low'].sort();
if (JSON.stringify(added) !== JSON.stringify(wantAdded))
  errs.push(`live catalog rows added vs the cf-143 base are ${JSON.stringify(added)}, want exactly the radiance trio (C05 delta contract)`);
if (JSON.stringify(removed) !== JSON.stringify(wantRemoved))
  errs.push(`live catalog rows removed vs the cf-143 base are ${JSON.stringify(removed)}, want exactly the vllm trio (C01 disable + C05 delta — every other row stays live, strata included)`);
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/rad-catalog.js" "$CAT" \
    || fail "M8: the radiance catalog contract is violated (trio HOLD: shared modelID, body.priority 9/5/1 higher-wins, ctx 200000, input [text,image], tools true; delta equality vs the frozen cf-143 base — chunks/C05.md Tests + M8 header)"
  # M8-B: cross-chart context needle — the catalog's 200000 == the SHIPPED
  # maxModelLen scalar (single-sources honesty law; reads charts/radiance/
  # values.yaml, so it names C02 until the chart lands).
  python3 - <<'PY' || fail "M8: the catalog context pin does not equal the shipped chart scalar (cross-chart honesty needle)"
import re, sys, yaml
try:
    vals = yaml.safe_load(open("charts/radiance/values.yaml"))
except FileNotFoundError:
    sys.exit("charts/radiance/values.yaml missing — C02 not landed; the cross-chart ctx needle waits on it")
mm = (vals.get("app-template") or {}).get("maxModelLen")
assert mm == 200000, f"charts/radiance maxModelLen is {mm!r}, want 200000 (D17 FULL profile — the catalog rows must mirror the served truth)"
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
  # M8-D: the negative needle (local-ids-shadow-peers law, R3 Q5.2 mirrored
  # from M3): the radiance wire id must NOT be a local llama-swap model id.
  python3 - <<'PY' || fail "M8: qwen3.8-flash-next-radiance is declared as a local llama-swap model id — it would shadow the unqualified radiance peer (the very precedence bug that kept the vllm id out of the local map)"
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
assert "qwen3.8-flash-next-radiance" not in ids, "the radiance wire id is a local model id in the chart or gpu-ai overlay config"
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
r1 = find(["urgent", "qwen3.8-flash-next-radiance-urgent"], rx=r"1\s*[–\-—]\s*3")
if not r1 or not re.search(r"\|\s*9\s*\|", r1):
    errs.append("no urgent row (1-3 / urgent / qwen3.8-flash-next-radiance-urgent / 9)")
r2 = find(["default", "qwen3.8-flash-next-radiance", "5", "unset"], must_not=["-urgent", "-low"])
if not r2 or not re.search(r"\|\s*5\s*\|", r2):
    errs.append("no default row (unset / default / qwen3.8-flash-next-radiance / 5)")
rl = find(["low", "qwen3.8-flash-next-radiance-low"], rx=r"8\s*[–\-—]\s*9")
if not rl or not re.search(r"\|\s*1\s*\|", rl):
    errs.append("no low row (8-9 / low / qwen3.8-flash-next-radiance-low / 1)")
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
if not re.search(r'peers\.radiance[^\n]{0,80}priority\?[^\n]{0,30}= ?5|priority\?[^\n]{0,40}=? ?5[^\n]{0,120}peers\.radiance', low_t):
    errs.append('the floor sentence is not re-pinned to peers.radiance.filters.setParams "priority?" = 5')
def favrow(cell):
    for ln in lines:
        cells = [c.strip().strip("`").strip() for c in ln.strip().strip("|").split("|")]
        if cell in cells and "gpu-ai" in cells:
            return ln
    return None
if not favrow("qwen3.8-flash-next-radiance"):
    errs.append("favorited models: no gpu-ai row keyed qwen3.8-flash-next-radiance")
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
    # M8-F: the strata-KEEP route strings (C05 AC3): the default route SURVIVES
    # everywhere C05 must not touch it — pipeline-models combination rule, the
    # kickoff derivation, the boards routing paragraph, catalog side via M3
    # HOLD. (A disappearance here IS the Q5 violation.)
    python3 -c '
import re, sys
text = re.sub(r"\s+", " ", open(sys.argv[1]).read())
assert "gpu-ai/qwen3.8-flash-next-strata-q4" in text, f"strata route string absent from {sys.argv[1]}"
' "$f" || fail "M8[Q5]: $f lost the strata-q4 route string — the routing DEFAULT does not move this run (C05 notes-for-dev; reviewer rejects otherwise)"
  done
  python3 -c '
import re
for f in (".rulesync/skills/pipeline-kickoff/SKILL.md", ".rulesync/skills/boards/SKILL.md"):
    t = re.sub(r"\s+", " ", open(f).read())
    assert "gpu-ai/qwen3.8-flash-next-strata-q4" in t, f"strata-q4 default route vanished from {f}"
' || fail "M8[Q5]: the strata default route moved in pipeline-kickoff/boards — C05 edits ONLY pipeline-models (+ catalog + this suite)"
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
  # M8-H (review-time, env-gated like cf-143's other git legs): the Q5
  # untouched-file diff inventory — the runner-literal surfaces were never in
  # the edit set (C05 AC3: "asserted by diff, not by grep").
  if [ -n "${CF143_BASE_SHA:-}" ]; then
    touched=$(git diff --name-only "$CF143_BASE_SHA"...HEAD -- .rulesync/rules/overview.md .agents/loops/pipeline-worker.md)
    [ -z "$touched" ] || fail "M8[Q5]: the deferred surfaces were touched: $touched — loops/AGENTS runner literals ride the cutover ruling, NOT this run (DECISIONS Deferred)"
    ok "M8: radiance trio HOLD (9/5/1 higher-wins, shared modelID, ctx 200000 == shipped maxModelLen, [text,image] + tools) + serving cross-check (peers.radiance.models == evidence, floor 5) + strata KEEP needles + negative peer-id bar + re-pinned class/favorited tables on source AND mirror + chart polarity comment + the loops/overview diff inventory vs $CF143_BASE_SHA"
  else
    skip "M8: Q5 diff-inventory leg not run — review sets CF143_BASE_SHA=<merge-base> and re-runs M8 (git diff check, chunks/C05.md AC3)"
    ok "M8: radiance trio HOLD (9/5/1 higher-wins, shared modelID, ctx 200000 == shipped maxModelLen, [text,image] + tools) + serving cross-check (peers.radiance.models == evidence, floor 5) + strata KEEP needles + negative peer-id bar + re-pinned class/favorited tables on source AND mirror + chart polarity comment"
  fi
fi

printf 'PASS: pipeline-models contract checks (%d ok)\n' "$checks"
