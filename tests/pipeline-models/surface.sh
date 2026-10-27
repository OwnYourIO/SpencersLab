#!/usr/bin/env bash
# pipeline-models local-default routing + provider-catalog surface suite
# (2026/2026-10-cf-58-feat-standalone-agent-merge, C06).
#
# Pins chunks/C06.md: the local model re-cut (27b+Local → q4 unless another
# quant is requested; Flash+Local ⇒ Qwen Flash Next q3 as a COMBINATION rule —
# no fifth picker option; Local-only default → q4) across pipeline-models,
# pipeline-kickoff and the boards skill, plus the .opencode/opencode.jsonc
# gpu-ai catalog patch (tools on q4, two flash-next entries) and the
# serving-fact cross-check against the chart/gpu-ai values.
#
# AC trace: M1[AC1 pipeline-models] M2[AC2 kickoff] M3[AC3 catalog]
# M4[AC4 serving facts] M5[AC2 boards routing + Model(s) stability]
# M6[AC5 mirrors/regen].
#
# Red posture: M1, M2, M3, M5 are red before C06 — the combination rule, the
# q4/q3 routes and the catalog entries do not exist yet (every red names the
# missing route/entry, never a harness fault). M4 is a HOLD invariant pinned
# by the plan's verified serving facts (the ids route TO must appear in the
# serving authority; green today, red the day routing drifts to an unserved
# id). M6 is HOLD now (mirrors honest) and re-arms red between the C06 edit
# and its regenerate.
#
# Base discipline: the catalog-delta arm diffs against this ticket's own base
# TB=$(git merge-base main HEAD); the historical operational bases of the
# sibling suites (081b57889-era arms, f11bfcb85, 916044893) are documented
# there and are not re-pinned here.
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

TB="${CF58_BASE:-$(git merge-base main HEAD 2>/dev/null || git rev-parse HEAD)}"
git rev-parse --verify "${TB}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: ticket base '$TB' is not a commit in this repo" >&2; exit 2; }

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

# --- M1: pipeline-models local-mapping contracts (AC1) ---------------------------
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
    # Flash+Local combination rule, pinned verbatim
    grep -qF 'assume Qwen Flash Next' "$f" \
      || fail "M1[AC1]: $f lacks the combination rule's pinned phrasing 'assume Qwen Flash Next' (red before C06)"
    grep -qF 'gpu-ai/qwen3.8-flash-next-q3' "$f" \
      || fail "M1[AC1]: $f never routes Flash+Local to gpu-ai/qwen3.8-flash-next-q3 (red before C06)"
    grep -qF 'There is no plain-flash local route' "$f" \
      || fail "M1[AC1]: $f lacks the pinned 'There is no plain-flash local route.' clause (red before C06)"
    # Local-only default follows the 27b default (q6 → q4)
    python3 "$TMP/win.py" --ci "$f" 300 'no model' 'qwen3.8-27b-q4' \
      || fail "M1[AC1]: $f's Local-only default is not qwen3.8-27b-q4 (was q6; C06 re-cuts it)"
    # stale q6 mappings removed outright
    grep -qF 'qwen3.8-flash-q6' "$f" && fail "M1[AC1]: $f still references qwen3.8-flash-q6 — C06 drops it outright, not as a fallback"
    grep -qF '27b → `gpu-ai/qwen3.8-27b-q6`' "$f" && fail "M1[AC1]: $f still maps 27b to q6 as the default route"
    grep -qF 'basename + `-q6`' "$f" && fail "M1[AC1]: $f still states the basename + -q6 assumption rule (stale after the q4 re-cut)"
    # favorited-models table additions
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-flash-next-q3' 'solo' \
      || fail "M1[AC1]: $f's favorited table lacks the flash-next-q3 row with the SOLO-eviction clause (C06 Tasks)"
    python3 "$TMP/win.py" --ci "$f" 400 'qwen3.8-27b-q6' 'alternate' \
      || fail "M1[AC1]: $f's q6 row was not re-labelled the verified alternate (C06 Tasks)"
  done
  ok "M1[AC1]: pipeline-models carries the four-option picker (no fifth), q4 27b+Local route with the unless-escape, the pinned Flash+Local combination rule, Local-only q4, stale q6 routes gone, favorited table updated"
fi

# --- M2: pipeline-kickoff — four options, cites, updated derivation (AC2) --------
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
    grep -qF 'flash-next-q3' "$f" \
      || fail "M2[AC2]: $f's derivation lacks the Flash+Local → flash-next-q3 combination rule (red before C06)"
    grep -qF 'qwen3.8-27b-q6' "$f" && fail "M2[AC2]: $f still cites qwen3.8-27b-q6 as the Local default (stale after C06)"
    grep -qF 'qwen3.8-flash-q6' "$f" && fail "M2[AC2]: $f still cites the dropped flash-q6 mapping"
  done
  ok "M2[AC2]: kickoff keeps the four pinned options, cites pipeline-models, and its derivation carries the q4 default + flash-next-q3 combination rule with no stale q6 claims"
fi

# --- M3: gpu-ai provider catalog (AC3) -------------------------------------------
if want m3; then
  [ -f "$CAT" ] || fail "M3[AC3]: $CAT missing"
  git show "$TB:$CAT" >"$TMP/catalog-base.jsonc" 2>/dev/null || fail "M3[AC3]: $CAT not readable at ticket base $TB"
  cat >"$TMP/catalog.js" <<'JS'
// JSONC-tolerant parse (the plan's mandate): evaluate the file as a JS object
// literal so line/block comments are legal — bare jq chokes. Deep-compare
// against the ticket-base copy: exactly two added entries, q4 gains the tools
// capability, everything else byte-identical in parsed form.
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
const base = gpuModels(load(process.argv[2])), cur = gpuModels(load(process.argv[3]));
let errs = [];
const bkeys = Object.keys(base), ckeys = Object.keys(cur);
const added = ckeys.filter(k => !bkeys.includes(k));
const removed = bkeys.filter(k => !ckeys.includes(k));
if (removed.length) errs.push(`entries removed: ${removed}`);
const wantAdded = ['qwen3.8-flash-next-q3', 'qwen3.8-flash-next-q4'];
if (added.length !== 2 || !wantAdded.every(k => added.includes(k)))
  errs.push(`added entries are ${added}, want exactly the two flash-next rungs (entry-count delta exactly +2)`);
const q4 = cur['qwen3.8-27b-q4'];
if (!q4 || !q4.capabilities || q4.capabilities.tools !== true)
  errs.push('qwen3.8-27b-q4 lacks capabilities.tools=true (agents cannot use the new default)');
for (const k of wantAdded) {
  const e = cur[k];
  if (!e) continue;
  if (e.modelID !== k) errs.push(`${k}: modelID is ${e.modelID}, want the key`);
  if (!e.capabilities || e.capabilities.tools !== true) errs.push(`${k}: capabilities.tools not true`);
  if (!e.limit || e.limit.context !== 262144) errs.push(`${k}: limit.context not 262144`);
  if (!e.name) errs.push(`${k}: no descriptive name`);
}
const stripTools = e => { const c = JSON.parse(JSON.stringify(e)); delete c.capabilities; return c; };
for (const k of bkeys) {
  if (!ckeys.includes(k)) continue;
  if (k === 'qwen3.8-27b-q4') {
    if (JSON.stringify(stripTools(cur[k])) !== JSON.stringify(base[k]))
      errs.push(`${k}: fields other than capabilities changed (only the tools capability is sanctioned)`);
  } else if (JSON.stringify(cur[k]) !== JSON.stringify(base[k])) {
    errs.push(`${k}: changed but the diff contract allows only the three pinned entries`);
  }
}
if (errs.length) { console.log(errs.join('; ')); process.exit(1); }
JS
  node "$TMP/catalog.js" "$TMP/catalog-base.jsonc" "$CAT" \
    || fail "M3[AC3]: catalog contract violated (red before C06: the tools capability and the two flash-next entries are absent — the red names the missing piece)"
  ok "M3[AC3]: catalog parses; q4 declares tools; flash-next-q3/q4 exist with modelID/name/tools/262144; entry delta exactly +2; no other entry changed"
fi

# --- M4: serving-fact cross-check (AC4) -------------------------------------------
if want m4; then
  for id in qwen3.8-27b-q4 qwen3.8-flash-next-q3 qwen3.8-flash-next-q4; do
    if grep -qF "$id" charts/llama-swap/values.yaml || grep -qF "$id" services/gpu-ai/prod/values.yaml; then
      :
    else
      fail "M4[AC4]: routed id '$id' is absent from both serving authorities (charts/llama-swap/values.yaml, services/gpu-ai/prod/values.yaml) — routing must never point at an unserved id"
    fi
  done
  ok "M4[AC4]: every id this chunk routes to (q4, flash-next q3/q4) appears in the serving authority (HOLD invariant)"
fi

# --- M5: boards skill — Model(s) line stable, routing gains both clauses (AC2) -----
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
    # routing paragraph combination clauses
    python3 "$TMP/win.py" --ci "$f" 600 'flash' 'local' 'flash-next-q3' 'assume' \
      || fail "M5[AC2]: $f's routing paragraph lacks the Flash+Local → flash-next-q3 'assume Qwen Flash Next' clause (red before C06)"
    python3 "$TMP/win.py" --ci "$f" 600 '27b' 'local' 'qwen3.8-27b-q4' 'unless' \
      || fail "M5[AC2]: $f's routing paragraph lacks the 27b+Local → q4 unless-another-quant clause (red before C06)"
    grep -qF 'qwen3.8-27b-q6' "$f" && fail "M5[AC2]: $f still routes only-Local to qwen3.8-27b-q6 (stale default after C06)"
  done
  ok "M5[AC2]: boards Model(s) line byte-stable (four options, Qwen Flash default, no fifth) with both combination clauses in the routing paragraph"
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
