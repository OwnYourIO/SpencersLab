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
# Offline-deterministic: tree/parse checks only; JSONC is parsed with node
# evaluating the file as an object literal (the plan's "JSONC-tolerant"
# mandate — bare jq would choke on the comments).
#
# Usage:
#   bash tests/pipeline-models/surface.sh            # M1..M7
#   bash tests/pipeline-models/surface.sh M3 M4      # subset
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
    [[ "$lc" =~ ^m[1-7]$ ]] || fail "unknown check id '$a' (expected M1..M7)"
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
# true-axis record below; the context assert itself stays byte-verbatim.
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
// cf-105 C03 + cf-105-vllm-followup C01: the three vLLM class rows — D10
// keeps the wire modelID (qwen3.8-27b-vllm) identical on all rows; only
// body.priority differs (5 default / 1 urgent / 9 low). cf-131 C04: the
// 262144 context pin below is the owner-ruled TRUE AXIS — catalog 262144
// == engine --max-model-len 262144 (round-2 Q3 keep + round-3 Q11
// engine-cap ruling, D31) — the assert stays byte-verbatim; the same loop
// gains the capabilities marker (round-1 OQ9/R4 input/output + round-2 Q6
// tools: true, the 0.30 stack's own 30/30 tool record with its TP2-only
// and mtp-29/30 caveats — the runbook's on-target tool smoke closes it).
const capEq = (a, b) => Array.isArray(a) && a.length === b.length && a.every((x, i) => x === b[i]);
for (const [k, prio] of [['qwen3.8-27b-vllm', 5], ['qwen3.8-27b-vllm-urgent', 1], ['qwen3.8-27b-vllm-low', 9]]) {
  const e = cur[k];
  if (!e) { errs.push(`${k}: catalog row missing (cf-105 C03 adds the default/urgent pair, cf-105-vllm-followup C01 adds the low row)`); continue; }
  if (e.modelID !== 'qwen3.8-27b-vllm') errs.push(`${k}: modelID is ${e.modelID}, want the shared wire value qwen3.8-27b-vllm`);
  if (!e.limit || e.limit.context !== 262144) errs.push(`${k}: limit.context is ${JSON.stringify((e.limit || {}).context)}, want 262144 (HR3)`);
  if (!e.body || e.body.priority !== prio) errs.push(`${k}: body.priority is ${JSON.stringify((e.body || {}).priority)}, want ${prio}`);
  if (!e.name) errs.push(`${k}: no descriptive name`);
  const caps = e.capabilities || {};
  if (!capEq(caps.input, ['text', 'image'])) errs.push(`${k}: capabilities.input is ${JSON.stringify(caps.input)}, want ["text","image"] (cf-131 C04 — the 0.30 stack serves vision: records [109] + [91])`);
  if (!capEq(caps.output, ['text'])) errs.push(`${k}: capabilities.output is ${JSON.stringify(caps.output)}, want ["text"] (cf-131 C04)`);
  if (caps.tools !== true) errs.push(`${k}: capabilities.tools is ${JSON.stringify(caps.tools)}, want true (cf-131 round-2 Q6 override — the tools marker on the shipped dflash lane)`);
}
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/catalog.js" "$CAT" \
    || fail "M3: gpu-ai catalog presence contract violated — the red names the missing/reshaped entry (HOLD rows never reshaped; the vllm class rows are cf-105 C03 / cf-105-vllm-followup C01's additive re-pin)"
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
  ok "M3: catalog parses; q4 declares tools; flash-next q3/q4/strata exist with modelID/name/tools/262144 (HOLD); the three vLLM class rows exist with the shared wire modelID, body.priority 5/1/9, the 262144 context on the TRUE axis (catalog == engine cap, cf-131 round-2 Q3 + round-3 Q11) and the capabilities marker (input [text, image], output [text], tools true — cf-131 C04 re-pin); the peer wire name is shadow-free (R3 Q5.2)"
fi

# --- M4: serving-fact cross-check (AC8) -------------------------------------------
if want m4; then
  # cf-83 list = the ids the contract TEXT names: the two default routes
  # (27b+Local → q4, Flash+Local → strata-q4 per the owner ruling
  # 2026-11-09) plus q3 as the documented explicit-request alternate.
  # flash-next-q4 joins because the contract now names it as the default.
  # cf-105 C04
  # re-pins additively: the class table's wire id qwen3.8-27b-vllm joins —
  # it is served from C03's peers.vllm.models list in the gpu-ai values, so
  # this arm is designed-red until C03 lands (C03 review runs M1..M6 with
  # C03 already landed → green).
  for id in qwen3.8-27b-q4 qwen3.8-flash-next-strata-q4 qwen3.8-flash-next-q3 qwen3.8-27b-vllm; do
    if grep -qF "$id" charts/llama-swap/values.yaml || grep -qF "$id" services/gpu-ai/prod/values.yaml; then
      :
    else
      fail "M4[AC8]: contract-named id '$id' is absent from both serving authorities (charts/llama-swap/values.yaml, services/gpu-ai/prod/values.yaml) — routing must never point at an unserved id"
    fi
  done
  ok "M4[AC8]: every id the contract names (27b-q4 + flash-next-strata-q4 defaults, flash-next-q3 documented alternate, cf-105 vllm wire id — red until C03's peers.vllm block lands) appears in the serving authority"
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
    # The class table rows, verbatim cells (markdown table lines only).
    python3 -c '
import re, sys
# Cells are conventionally backtick-wrapped (the plan table writes `1`–`3`);
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
# The 1-3 range is part of the row MATCHER, not a post-hoc assert: the
# favorited -urgent row carries every other cell as a substring ("urgent"
# and "3" both inside qwen3.8-27b-vllm-urgent) and would otherwise shadow
# the table row when the favorited table precedes it in the file.
r1 = find(["urgent", "qwen3.8-27b-vllm-urgent"], rx=r"1\s*[–\-—]\s*3")
assert r1, "class table: no urgent row (1-3 / urgent / qwen3.8-27b-vllm-urgent / 1)"
assert re.search(r"\|\s*1\s*\|", r1), f"class table: urgent row lacks the vLLM priority cell 1: {r1}"
r2 = find(["default", "qwen3.8-27b-vllm", "5", "unset"], must_not=["-urgent"])
assert r2, "class table: no default row (unset / default / qwen3.8-27b-vllm / 5)"
assert re.search(r"\|\s*5\s*\|", r2), f"class table: default row lacks the vLLM priority cell 5: {r2}"
r_low = find(["low", "qwen3.8-27b-vllm-low"], rx=r"8\s*[–\-—]\s*9")
assert r_low, "class table: no low row (8-9 / low / qwen3.8-27b-vllm-low / 9)"
assert re.search(r"\|\s*9\s*\|", r_low), f"class table: low row lacks the vLLM priority cell 9: {r_low}"
r3 = find(["background", "qwen3.8-27b-q4", "n/a"]) or find(["background", "qwen3.8-27b-q4", "n-a"])
assert r3, "class table: no background row (10+ / background / qwen3.8-27b-q4 / n-a)"
assert re.search(r"\b10\s*\+", r3), f"class table: background row lacks the 10+ card-Priority marker: {r3}"
# Polarity + snap-interval sentence: lower = more urgent (vLLM convention);
# the discrete values ride the resolved body.priority 1:1.
text = open(sys.argv[1]).read().lower()
i = text.find("more urgent")
assert i >= 0, "no polarity sentence (lower = more urgent)"
window = text[max(0, i - 300):i + 300]
assert "lower" in window and "1:1" in window, "the polarity sentence must state 1:1 passthrough with lower = more urgent"
# The two favorited rows: exact model cells (the class table routes
# gpu-ai/<id>, so exact-cell matching keeps the two apart).
def favrow(cell):
    for ln in lines:
        cells = [c.strip().strip("`").strip() for c in ln.strip().strip("|").split("|")]
        if cell in cells and "gpu-ai" in cells:
            return ln
    return None
assert favrow("qwen3.8-27b-vllm"), "favorited models: no gpu-ai row keyed qwen3.8-27b-vllm"
assert favrow("qwen3.8-27b-vllm-urgent"), "favorited models: no gpu-ai row keyed qwen3.8-27b-vllm-urgent"
assert favrow("qwen3.8-27b-vllm-low"), "favorited models: no gpu-ai row keyed qwen3.8-27b-vllm-low"
' "$f" || fail "M7[AC4/AC5]: $f lacks the single-authority four-class table (rows + polarity + the three favorited vLLM rows)"
  done
  # Cross-file (M4 style): the class table's row IDs appear in a serving
  # authority, and the floor 5 equals the peer filter value.
  python3 -c '
import sys, yaml
svc = yaml.safe_load(open("services/gpu-ai/prod/values.yaml"))
peer = ((svc.get("llama-swap") or {}).get("config") or {}).get("peers", {}).get("vllm")
assert peer is not None, "services/gpu-ai: no llama-swap.config.peers.vllm block (C03)"
assert peer.get("models") == ["qwen3.8-27b-vllm"], f"peers.vllm.models must be exactly [qwen3.8-27b-vllm], got {peer.get('models')!r}"
floor = ((peer.get("filters") or {}).get("setParams") or {}).get("priority?")
assert floor == 5, f"the peer priority? floor must be 5 (the floor follows the default class — cf-105-vllm-followup D2), got {floor!r}"
' || fail "M7[AC5]: the peers.vllm serving authority (models list + priority? floor 5) is absent or wrong in services/gpu-ai/prod/values.yaml"
  cat >"$TMP/vllm-catalog.js" <<'JS'
// cf-105 C04 cross-file leg (re-pinned cf-105-vllm-followup C02): the class
// table's row IDs exist in the gpu-ai provider catalog with the shared wire
// modelID, the HR3 context pin and the class body.priority values
// (1 urgent / 5 default / 9 low).
const fs = require('fs');
function load(p) { return eval('(' + fs.readFileSync(p, 'utf8') + ')'); }
const o = load(process.argv[2]);
const provs = o.providerMetas || o.providers || {};
const models = (provs['gpu-ai'] || {}).models || {};
const errs = [];
for (const [k, prio] of [['qwen3.8-27b-vllm', 5], ['qwen3.8-27b-vllm-urgent', 1], ['qwen3.8-27b-vllm-low', 9]]) {
  const e = models[k];
  if (!e) { errs.push(`${k}: row missing`); continue; }
  if (e.modelID !== 'qwen3.8-27b-vllm') errs.push(`${k}: modelID ${e.modelID}, want the wire value qwen3.8-27b-vllm`);
  if (!e.limit || e.limit.context !== 262144) errs.push(`${k}: limit.context ${JSON.stringify((e.limit || {}).context)}, want 262144 (HR3)`);
  if ((e.body || {}).priority !== prio) errs.push(`${k}: body.priority ${JSON.stringify((e.body || {}).priority)}, want ${prio}`);
}
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/vllm-catalog.js" "$CAT" \
    || fail "M7[AC5]: the gpu-ai provider catalog rows do not match the class table (shared wire modelID, 262144 context, body.priority 5/1/9)"
  grep -qF 'qwen3.8-27b-q4' charts/llama-swap/values.yaml \
    || grep -qF 'qwen3.8-27b-q4' services/gpu-ai/prod/values.yaml \
    || fail "M7[AC5]: the background-leg rung qwen3.8-27b-q4 is absent from the serving authorities (chart catalog or gpu-ai overlay)"
  ok "M7[cf-105 C04, re-pinned cf-105-vllm-followup C02]: boards roster names both fields + the D12 carve-out with the retired semantics intact, the priority kickoff bullet and launch-prompt value are present, the kickoff slot is board-scoped with the two-question list intact, the four-class table + polarity + the three favorited vLLM rows live in pipeline-models alone, the serving authorities agree (floor 5, wire model, catalog body.priority 1/5/9, background rung), and no 10+/background leg text leaks into boards/kickoff"
fi

printf 'PASS: pipeline-models contract checks (%d ok)\n' "$checks"
