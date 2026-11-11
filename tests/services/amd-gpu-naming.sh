#!/usr/bin/env bash
# cf-143 C07 — the naming-wave contract suite (chunks/C07.md Tests bullet 3,
# legs n1-n4 + the workflow deliverable the chunk's file scope names).
#
# The wave makes the R9700/APU claim deterministic BY NAME (owner Q9 ruling,
# DECISIONS D18/D19): a vendored charts/amd-gpu (upstream 0.22.0 + the ~10-
# line args hook) runs the plugin at 1.31.0.12 with
# -resource_naming_strategy=product; the gpu-ai-amd-gpu Application switches
# source repo->git-path with IDENTICAL object names; llama-swap's claim flips
# to amd.com/gpu-8060s IN THE SAME COMMIT (same-wave law: after the strategy
# flip bare amd.com/gpu is GONE from the node — a rescheduled pre-flip pod or
# any stray bare claim goes Pending-forever, loud by design).
#
# Designed-RED at test-write: every leg names the missing artifact (entry,
# flip, vendored chart, ledger). The n2 same-wave COMMIT leg runs only when
# review passes AMD_GPU_FLIP_COMMIT=<sha> (a git-show check is review-time
# by the chunk's own wording); the needle legs run standalone.
#
# The radiance-side cross-check (the claimed name == the ledgered pool) is
# C02's suite (test_resource_name_identity.py) — the n4 leg here asserts the
# ledger the C02 needle reads, deferring the join, per the chunk.
#
# Run from the repo root:
#   bash tests/services/amd-gpu-naming.sh            # n1..n5
#   bash tests/services/amd-gpu-naming.sh n2 n3      # subset
#   AMD_GPU_FLIP_COMMIT=<sha> bash tests/services/amd-gpu-naming.sh n2   # with the same-wave guard
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

VALS="${AMD_GPU_VALS:-services/gpu-ai/prod/values.yaml}"
SWAP_VALUES="${AMD_GPU_SWAP_VALUES:-charts/llama-swap/values.yaml}"
VENDORED="${AMD_GPU_VENDORED_VALUES:-charts/amd-gpu/values.yaml}"
APPSET="${AMD_GPU_APPSET:-charts/base/templates/appset-charts.yaml}"
WORKFLOW=".github/workflows/amd-gpu-render-tests.yaml"

APU_CLAIM="amd.com/gpu-8060s"
R9700_CLAIM="amd.com/gpu-ai-pro-r9700"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for t in 1 2 3 4 5; do WANT["n$t"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^n[1-5]$ ]] || fail "unknown check id '$a' (expected N1..N5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- n1: the service entry is internal-shape, datasource moved, name kept -------
if want n1; then
  [ -f "$VALS" ] || fail "n1: $VALS missing"
  python3 - "$VALS" <<'PY' || fail "n1: charts.amd-gpu entry is not the vendored internal shape (see diagnostics)"
import re, sys, yaml
text = open(sys.argv[1]).read()
doc = yaml.safe_load(text)
entry = (doc.get("charts") or {}).get("amd-gpu")
errs = []
if entry is None:
    errs.append("charts.amd-gpu entry ABSENT (the flip wave replaces the external entry, it does not delete the app)")
else:
    if "version" in entry or "repository" in entry:
        errs.append(f"entry still carries external keys {sorted(entry)} — internal shape = namespace + ServerSideApply only")
    if entry.get("namespace") != "default" or entry.get("ServerSideApply") != "true":
        errs.append(f'entry is {entry}, want {{namespace: default, ServerSideApply: "true"}} (SSA "true" kept: it helps the args field-ownership watch-once)')
# The datasource=helm pin comment for amd-gpu must be GONE (it migrates to the
# vendored chart's docker pin), and the entry's region comment records the move.
m = re.search(r"(?ms)^  amd-gpu:\s*$.*?(?=^\S)", text)
region = m.group(0) if m else ""
if "datasource=helm" in region or "rocm.github.io/k8s-device-plugin" in region:
    errs.append("the datasource=helm pin / repository line survived inside the amd-gpu entry region")
if not re.search(r"(?i)docker", region):
    errs.append("the entry comment does not record the datasource MOVE to the chart's docker pin (C07 task)")
if errs:
    print("; ".join(errs), file=sys.stderr); sys.exit(1)
PY
  # The base appset template is the name-derivation evidence (identical
  # Application name gpu-ai-amd-gpu after the source flip):
  grep -q 'name: "{{ `{{ .serviceName }}` }}-{{ `{{ .appName }}` }}"' "$APPSET" \
    || fail "n1: $APPSET no longer derives Application names as serviceName-appName — the gpu-ai-amd-gpu identity has no template evidence"
  grep -q 'hasKey . "version"' "$APPSET" \
    || fail "n1: $APPSET lost the internal-vs-external (version-key) source branch — git-path rendering for versionless entries is the flip's mechanism"
  ok "n1: charts.amd-gpu renders internal (no version/repository, SSA \"true\", namespace default), the helm-pin comment left services/ with the datasource-move recorded, and the base-appset name/path derivation is intact (C07 AC1/AC2)"
fi

# --- n2: the llama-swap flip needle (+ same-wave commit guard, review-time) ------
if want n2; then
  [ -f "$SWAP_VALUES" ] || fail "n2: $SWAP_VALUES missing"
  grep -qE "^[[:space:]]*${APU_CLAIM}: 1" "$SWAP_VALUES" \
    || fail "n2: $SWAP_VALUES carries no live '${APU_CLAIM}: 1' limit line — the same-wave flip did not land (llama-swap keeps the APU BY NAME, owner Q9)"
  # bare `amd.com/gpu:` only in comments — a live requests/limits occurrence is the drift class
  if grep -nE "^[[:space:]]*amd\.com/gpu:" "$SWAP_VALUES" | grep -q .; then
    fail "n2: a live bare 'amd.com/gpu:' claim line survives in $SWAP_VALUES — post-flip that name does not exist on the node: Pending-forever"
  fi
  # the fallback comment retired as realized prose (needle mirror of the pytest leg)
  if grep -qi "fallback once a naming-capable plugin exists" "$SWAP_VALUES"; then
    fail "n2: the 'fallback once a naming-capable plugin exists' comment survived — it rewrites to REALIZED prose (C07 task)"
  fi
  if [ -n "${AMD_GPU_FLIP_COMMIT:-}" ]; then
    # Same-wave guard (review-time): the vendored chart + the entry swap + the
    # flip ride ONE commit; a split lands a window where llama-swap is
    # unschedulable on its next restart (R6-Q4-2).
    stat=$(git show --stat --format= "$AMD_GPU_FLIP_COMMIT" 2>/dev/null || true)
    [ -n "$stat" ] || fail "n2: AMD_GPU_FLIP_COMMIT=$AMD_GPU_FLIP_COMMIT is not a commit"
    for path in charts/amd-gpu/ "$SWAP_VALUES" "$VALS"; do
      printf '%s\n' "$stat" | grep -q "$path" \
        || fail "n2: same-wave violation — commit $AMD_GPU_FLIP_COMMIT does not touch $path (vendored chart, service entry swap and the llama-swap flip land in ONE commit; git show --stat is the evidence)"
    done
    ok "n2: flip needle green AND the same-wave commit guard verified against $AMD_GPU_FLIP_COMMIT"
  else
    skip "n2: same-wave COMMIT guard not run — review sets AMD_GPU_FLIP_COMMIT=<sha> and re-runs n2 (git-show check, C07 Tests bullet 3)"
    ok "n2: llama-swap claims ${APU_CLAIM} live, no bare amd.com/gpu live claim, fallback comment retired (same-wave commit guard deferred to review)"
  fi
fi

# --- n3: whole-repo bare-claim sweep (AC4) ---------------------------------------
if want n3; then
  # Live requests/limits claims of bare amd.com/gpu across charts/ and
  # services/. Exemptions, each deliberate:
  #  - comment lines (history/prose may name the retired resource);
  #  - charts/*/tests/** and services/*/tests/** (captured fixtures are
  #    RENDERS, not claims — the off-parity evidence re-baseline cadence
  #    (TEST_SPEC §9.8, cf-143 §12 note) guards those, not this sweep);
  #  - the named pools themselves (gpu-ai-pro-r9700 / gpu-8060s — the pattern
  #    is the exact colon after "gpu", they cannot match).
  hits=$(grep -rn --include='*.yaml' --include='*.yml' --include='*.tpl' \
        -E '^[[:space:]]*amd\.com/gpu:' charts/ services/ 2>/dev/null \
      | grep -vE ':[0-9]+:[[:space:]]*#' \
      | grep -vE '^charts/[^/]+/tests/|^services/[^/]+/tests/' || true)
  if [ -n "$hits" ]; then
    fail "n3: live bare amd.com/gpu claims remain — post-flip they become Pending-forever (loud by design, R6-Q4-3):
$hits"
  fi
  ok "n3: whole-repo sweep finds ZERO live bare amd.com/gpu claims in charts/ services/ (comments and test fixtures exempt per the pattern above — the stray-claim-Pending precondition holds)"
fi

# --- n4: the vendored chart's expected-names ledger (the C02 authority) ---------
if want n4; then
  [ -f "$VENDORED" ] || fail "n4: $VENDORED missing — the vendored chart (C07) is the producer of the pool names; the ledger comment lives here"
  grep -qF "$R9700_CLAIM" "$VENDORED" || fail "n4: $VENDORED never names ${R9700_CLAIM} (the 7551/C0 product pool C02 claims)"
  grep -qF "$APU_CLAIM" "$VENDORED" || fail "n4: $VENDORED never names ${APU_CLAIM} (the 1586 product pool llama-swap flips to)"
  grep -E "^[[:space:]]*#" "$VENDORED" | grep "7551" | grep -q "gpu-ai-pro-r9700" \
    || fail "n4: no ledger COMMENT row mapping 7551 (R9700) to gpu-ai-pro-r9700 — §R6-Q1's computed names must sit where the test reads them (same-line row form)"
  grep -E "^[[:space:]]*#" "$VENDORED" | grep "1586" | grep -q "gpu-8060s" \
    || fail "n4: no ledger COMMENT row mapping 1586 (APU) to gpu-8060s"
  # The fallback trap named (its decision tree stays in the runbook, C06):
  grep -qi "fallback" "$VENDORED" \
    || fail "n4: the unknown-(device,revision) -> bare amd.com/gpu fallback trap is not named beside the ledger"
  ok "n4: the vendored chart's values ledger records 7551/C0->gpu-ai-pro-r9700, 1586->gpu-8060s and the fallback trap (the cross-chart name-identity join lives in charts/radiance/tests/test_resource_name_identity.py, deferred per the chunk)"
fi

# --- n5: the render-CI deliverable (file scope: .github/workflows/...) -----------
if want n5; then
  [ -f "$WORKFLOW" ] || fail "n5: $WORKFLOW missing — the clone-of-idiom render CI is a C07 deliverable"
  python3 - "$WORKFLOW" <<'PY' || fail "n5: the amd-gpu workflow diverges from the clone idiom (triggers/ladder)"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get("on") or wf.get(True) or {}
want = {"charts/amd-gpu/**", "services/gpu-ai/prod/values.yaml", ".github/workflows/amd-gpu-render-tests.yaml"}
for kind in ("push", "pull_request"):
    paths = set((on.get(kind) or {}).get("paths") or [])
    assert paths == want, f"{kind} trigger paths {sorted(paths)} != {sorted(want)}"
runs = []
def walk(n):
    if isinstance(n, dict):
        if isinstance(n.get("run"), str):
            runs.append(n["run"])
        for v in n.values():
            walk(v)
    elif isinstance(n, list):
        for v in n:
            walk(v)
walk(wf)
joined = "\n".join(runs)
for step in ("helm lint charts/amd-gpu", "helm template", "charts/amd-gpu/tests"):
    assert step in joined, f"ladder missing {step!r}"
PY
  ok "n5: amd-gpu-render-tests.yaml triggers the flip-wave paths and runs lint + template + pytest charts/amd-gpu/tests (plan Commands CI-shape)"
fi

printf 'PASS: amd-gpu naming-wave contract checks (%d ok)\n' "$checks"
