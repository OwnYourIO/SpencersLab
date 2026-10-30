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
#   bash tests/pipeline-models/surface.sh            # M1..M6
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
  for i in 1 2 3 4 5 6; do WANT["m$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^m[1-6]$ ]] || fail "unknown check id '$a' (expected M1..M6)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -------------------------------------------------------------

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): the routing needles
# must read as one passage, not as scattered file-wide hits.
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
    # the picker option set is unchanged (no fifth option)
    python3 "$TMP/win.py" "$f" 400 'Qwen Large' 'Qwen 27b' 'Qwen Flash' 'Local' \
      || fail "M1[AC1]: $f lost the four-option picker line (Q6: the option set stays Qwen Large / Qwen 27b / Qwen Flash / Local — no fifth option)"
    if grep -nE 'Qwen Large.*Qwen 27b.*Qwen Flash.*Local' "$f" | grep -q 'Flash Next'; then
      fail "M1[AC1]: a picker option line gained 'Flash Next' — Q6 vetoed a fifth option; the combination of the two existing checks is the whole mechanism"
    fi
    # 27b + Local → q4 with the explicit escape
    grep -qF 'gpu-ai/qwen3.8-27b-q4' "$f" \
      || fail "M1[AC1]: $f never routes 27b+Local to gpu-ai/qwen3.8-27b-q4 (red before C06)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-27b-q4' 'unless' \
      || fail "M1[AC1]: $f's q4 route lacks the 'unless another quant is requested' escape clause"
    # Flash+Local combination rule, pinned verbatim (cf-83 re-pin: same
    # phrases, new route)
    grep -qF 'assume Qwen Flash Next' "$f" \
      || fail "M1[AC1]: $f lacks the combination rule's pinned phrasing 'assume Qwen Flash Next' (cf-83 keeps the phrase — red only if dev deleted it)"
    grep -qF 'gpu-ai/qwen3.8-flash-next-strata' "$f" \
      || fail "M1[AC1]: $f never routes Flash+Local to gpu-ai/qwen3.8-flash-next-strata (red before C01: the sources still route the combo to q3)"
    grep -qF 'There is no plain-flash local route' "$f" \
      || fail "M1[AC1]: $f lacks the pinned 'There is no plain-flash local route.' clause (cf-83 keeps this phrase too)"
    # AC1 absence guard pins the ROUTE FORM, not the bare id: q3 legitimately
    # survives as the alternate sentence (Q1), so only the old routed string
    # is stale.
    grep -qF 'assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-q3`' "$f" \
      && fail "M1[AC1]: $f still carries the old route string 'assume Qwen Flash Next: gpu-ai/qwen3.8-flash-next-q3' (red before C01)"
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
    grep -qF '| `gpu-ai` | `qwen3.8-flash-next-strata` |' "$f" \
      || fail "M1[AC3]: $f's favorited table has no gpu-ai row keyed qwen3.8-flash-next-strata (red before C01: the q3 row stands)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-flash-next-strata' 'peers' 'arena' \
      || fail "M1[AC3]: $f's strata row lacks the peers/arena operations clause (dedicated Strata pod through the outer llama-swap peers seam; the IQ3_S arena pin makes cold start minutes-long — the serving truth D4 records)"
    # Inverted from the cf-58 q3+solo window: a peer-served model is invisible
    # to the outer matrix's SOLO-eviction semantics, so that claim may no
    # longer sit on the default route's row (D4 — it describes only the
    # legacy q3/q4 solo-set rungs).
    grep -F '| `gpu-ai` | `qwen3.8-flash-next-strata` |' "$f" | grep -qiF 'solo' \
      && fail "M1[AC3]: $f's strata row still claims SOLO/matrix eviction — the clause must be the peers/arena one (cf-83 D4)"
    grep -qF '| `qwen3.8-flash-next-q3`' "$f" \
      && fail "M1[AC2]: $f still carries a favorited row keyed qwen3.8-flash-next-q3 — q3's alternate status is rule text, never a table row (Q2; red before C01)"
    # Q3: the -strix sibling is named inside the strata row's operations
    # clause ONLY — never as a row, never in route syntax, never elsewhere.
    grep -qF 'gpu-ai/qwen3.8-flash-next-strata-strix' "$f" \
      && fail "M1[AC3]: $f gives -strix the gpu-ai/ route form — strix is never agent-routable (Q3/D7)"
    grep -F 'strix' "$f" | grep -vF '| `gpu-ai` | `qwen3.8-flash-next-strata` |' | grep -q . \
      && fail "M1[AC3]: $f names strix outside the strata row's operations clause (Q3: that clause is strix's one location)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-27b-q6' 'alternate' \
      || fail "M1[AC1]: $f's q6 row was not re-labelled the verified alternate (C06 Tasks)"
  done
  ok "M1[AC1–AC3]: pipeline-models carries the four-option picker (no fifth), q4 27b+Local route with the unless-escape, the pinned combination bullet now routing Flash+Local to flash-next-strata with the old q3 route string gone and q3 documented as the explicit-request alternate, Local-only q4, stale q6 routes gone, and the single strata favorited row with the peers/arena clause (no solo claim; strix confined to that clause)"
fi

# --- M2: pipeline-kickoff — four options, cites, strata derivation (AC1–AC3) -----
if want m2; then
  for f in "$PK_SRC" "$PK_GEN"; do
    [ -f "$f" ] || fail "M2[AC2]: $f missing"
    # the option list itself is unchanged — byte-pinned per C06 Tasks
    for o in '`Qwen Large` — `openrouter/qwen/qwen3.8-2.4t-a95b`' \
             '`Qwen 27b` — `openrouter/qwen/qwen3.8-27b`' \
             '`Qwen Flash` — `openrouter/qwen/qwen3.8-flash`'; do
      grep -qF "$o" "$f" || fail "M2[AC2]: $f lost the pinned option '$o' (option set UNCHANGED)"
    done
    grep -qF '`Local (gpu-ai)`' "$f" || fail "M2[AC2]: $f lost the Local option"
    grep -qF '`Qwen Flash Next`' "$f" && fail "M2[AC2]: $f gained a 'Qwen Flash Next' option — Q6 veto"
    grep -qF 'pipeline-models' "$f" || fail "M2[AC2]: $f no longer cites pipeline-models as the mapping authority"
    # derivation updated: routes to the new ids
    grep -qF 'qwen3.8-27b-q4' "$f" \
      || fail "M2[AC2]: $f's derivation still defaults Local to q6 (no q4 route yet — red before C06)"
    grep -qF 'flash-next-strata' "$f" \
      || fail "M2[AC1]: $f's derivation lacks the Flash+Local → flash-next-strata combination route (red before C01: kickoff still names q3)"
    # Single-authority (Q1): kickoff cites pipeline-models for the quants and
    # "never restates its table" — the cf-83 change there is a pure route-id
    # swap, so zero q3 text (and zero strix text, Q3) may exist on this pair.
    grep -qF 'qwen3.8-flash-next-q3' "$f" \
      && fail "M2[AC2]: $f names qwen3.8-flash-next-q3 — the named alternate lives only in the pipeline-models bullet (red before C01)"
    grep -qF 'strix' "$f" \
      && fail "M2[AC3]: $f names strix — only the pipeline-models strata row clause may name it (Q3)"
    grep -qF 'qwen3.8-27b-q6' "$f" && fail "M2[AC2]: $f still cites qwen3.8-27b-q6 as the Local default (stale after C06)"
    grep -qF 'qwen3.8-flash-q6' "$f" && fail "M2[AC2]: $f still cites the dropped flash-q6 mapping"
  done
  ok "M2[AC1–AC3]: kickoff keeps the four pinned options, cites pipeline-models, and its derivation carries the q4 default + flash-next-strata combination route with no q3/strix restatement and no stale q6 claims"
fi

# --- M3: gpu-ai provider catalog — presence HOLD (DECISIONS D5 re-base) --------
# cf-83 C01 re-bases this arm: the cf-58 delta contract (exactly +2 added
# entries vs TB=$(git merge-base main HEAD) AND a tools-less q4 at that base)
# is self-contradictory once cf-58/cf-77 catalog state lives in the base
# itself — proven red-by-construction at eb8a963 ("added entries are []",
# "q4: fields other than capabilities changed"). Rejected alternative kept
# out by design: a historical CF58_BASE default — a hidden stale ref passing
# only when the env happens to be set. Q4 rules no catalog edits on this
# ticket, so this arm is the guard against the catalog losing or reshaping
# an entry a route needs: green before AND after the dev edit.
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
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/catalog.js" "$CAT" \
    || fail "M3[HOLD]: gpu-ai catalog presence contract violated — the red names the missing/reshaped entry (HOLD across C01: Q4 forbids catalog edits, cf-77 landed these)"
  ok "M3[HOLD]: catalog parses; q4 declares tools; flash-next q3/q4/strata exist with modelID/name/tools/262144 (presence HOLD, cf-83 D5 re-base)"
fi

# --- M4: serving-fact cross-check (AC8) -------------------------------------------
if want m4; then
  # cf-83 list = the ids the contract TEXT names: the two default routes
  # (27b+Local → q4, Flash+Local → strata) plus q3 as the documented
  # explicit-request alternate. flash-next-q4 stays OUT — the generic escape
  # names no ids; it joins if contract text ever names one.
  for id in qwen3.8-27b-q4 qwen3.8-flash-next-strata qwen3.8-flash-next-q3; do
    if grep -qF "$id" charts/llama-swap/values.yaml || grep -qF "$id" services/gpu-ai/prod/values.yaml; then
      :
    else
      fail "M4[AC8]: contract-named id '$id' is absent from both serving authorities (charts/llama-swap/values.yaml, services/gpu-ai/prod/values.yaml) — routing must never point at an unserved id"
    fi
  done
  ok "M4[AC8]: every id the contract names (27b-q4 + flash-next-strata defaults, flash-next-q3 documented alternate) appears in the serving authority (HOLD invariant)"
fi

# --- M5: boards skill — Model(s) line stable, routing clauses re-pinned (AC1) -----
if want m5; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "M5[AC2]: $f missing"
    grep -qF '`Qwen Large` | `Qwen 27b` | `Qwen Flash` | `Local`' "$f" \
      || fail "M5[AC2]: $f's Model(s) checklist option line changed — it stays byte-stable (four options)"
    grep -qF 'Default selection: `Qwen Flash`' "$f" \
      || fail "M5[AC2]: $f lost the Model(s) default selection (Qwen Flash stays)"
    python3 - "$f" <<'PY' || fail "M5[AC2]: the Model(s) checklist line gained a 'Flash Next' item — the checklist gains NO option (Q6); the combination of the existing checks is the mechanism"
import sys
for l in open(sys.argv[1]):
    if 'Qwen Large' in l and 'Qwen Flash' in l and 'Next' in l:
        sys.exit(1)
PY
    # routing paragraph combination clauses (cf-83 re-pin: strata route)
    python3 "$TMP/win.py" --ci "$f" 600 'flash' 'local' 'flash-next-strata' 'assume' \
      || fail "M5[AC1]: $f's routing paragraph lacks the Flash+Local → flash-next-strata 'assume' clause (red before C01: boards still names q3)"
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
  ok "M5[AC1–AC3]: boards Model(s) line byte-stable (four options, Qwen Flash default, no fifth); routing paragraph carries the strata combination clause and the 27b+Local q4 unless-clause with no q3/strix restatement"
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

printf 'PASS: pipeline-models contract checks (%d ok)\n' "$checks"
