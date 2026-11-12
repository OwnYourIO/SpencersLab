#!/usr/bin/env bash
# cf-143 C07 — the naming-wave contract suite (chunks/C07.md Tests bullet 3,
# legs n1-n4 + the workflow deliverable the chunk's file scope names).
#
# The wave makes the R9700/APU claim deterministic BY NAME ON GPU-AI (owner
# Q9 ruling + B1 shield, DECISIONS D18/D19/D21): a vendored charts/amd-gpu
# (upstream 0.22.0 + the ~10-line args hook) runs the plugin at 1.31.0.12
# with -resource_naming_strategy=product; the gpu-ai-amd-gpu Application
# switches source repo->git-path with IDENTICAL object names; llama-swap's
# gpu-ai render flips to amd.com/gpu-8060s VIA THE SERVICE OVERLAY (null
# retire of the inherited bare key) in the same commit, while the chart's
# tree-global claim stays bare amd.com/gpu: 1 for the gpu cluster's single-
# naming plugin (D21: a tree-global flip would strand live gpu-llama-swap).
#
# Landing-round re-scope (this file's C07 test round): n2 pins the per-cluster
# flip (overlay APU pair + null + chart claim-line untouched) and the env-
# gated same-wave guard now also PROVES the claim-line zero-diff via
# git show before/after; n3 became the AC4 per-cluster sweep (bare claims
# ONLY the chart default, APU name ONLY the gpu-ai overlay, R9700 nowhere
# until C02 — then charts/radiance only; comments/fixtures exempt, the
# off-parity fixture moved ZERO lines under B1, TEST_SPEC §12.2).
#
# Designed-RED at test-write: every leg names the missing artifact (entry,
# flip, vendored chart, ledger). The n2 same-wave COMMIT leg runs only when
# review passes AMD_GPU_FLIP_COMMIT=<sha> (a git-show check is review-time
# by the chunk's own wording); the needle legs run standalone.
# State now (C07 landing test round): n1/n3/n4/n5 green on the landing tree;
# n2's needle legs green, the commit guard awaits the landing sha at review.
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

# --- n2: the per-cluster flip needle (overlay null) + same-wave guard -----------
# C07 landing-round re-scope (owner B1 / DECISIONS D21): the APU flip lives
# in the gpu-ai SERVICE OVERLAY (null-retire of the inherited bare key), the
# chart's tree-global claim line STAYS bare amd.com/gpu: 1 by design (gpu-
# cluster shield). The same-wave lockstep law is closed by construction (the
# entry swap and the flip share this one file; the vendored chart joins the
# same commit), and the review-time git-show guard re-pins it.
if want n2; then
  [ -f "$SWAP_VALUES" ] || fail "n2: $SWAP_VALUES missing"
  [ -f "$VALS" ] || fail "n2: $VALS missing"
  # (a) the overlay flip: APU limits pair + the load-bearing null on the
  #     inherited bare key + the explicit requests mirror (D21 shape)
  grep -qE "^[[:space:]]*${APU_CLAIM}: 1" "$VALS" \
    || fail "n2: $VALS carries no live '${APU_CLAIM}: 1' overlay line — the per-cluster flip did not land (llama-swap keeps the APU BY NAME on gpu-ai, owner Q9/B1)"
  grep -qE "^[[:space:]]*amd\.com/gpu:[[:space:]]*null[[:space:]]*$" "$VALS" \
    || fail "n2: no 'amd.com/gpu: null' retirement line in the overlay — maps deep-merge ADD-only; without the null the gpu-ai render keeps the bare claim beside the APU name (double slot)"
  # (b) the chart's claim line UNTOUCHED: bare lives, APU name absent live
  grep -qE "^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$" "$SWAP_VALUES" \
    || fail "n2: charts/llama-swap/values.yaml lost the tree-global bare amd.com/gpu: 1 claim — the gpu cluster's single-naming plugin can advertise NOTHING ELSE (B1 shield; a flip here strands live gpu-llama-swap)"
  if grep -E "^[[:space:]]*${APU_CLAIM}:" "$SWAP_VALUES" | grep -vqE '^[[:space:]]*#'; then
    fail "n2: a LIVE ${APU_CLAIM} claim line in the CHART values — the flip is overlay-only (the tree-global shape is the B1 leak this shield retires)"
  fi
  # the fallback comment retired as realized prose (needle mirror of the pytest leg)
  if grep -qi "fallback once a naming-capable plugin exists" "$SWAP_VALUES"; then
    fail "n2: the 'fallback once a naming-capable plugin exists' comment survived — it rewrites to per-cluster REALIZED prose (C07 task, D21 wording)"
  fi
  if [ -n "${AMD_GPU_FLIP_COMMIT:-}" ]; then
    # Same-wave guard (review-time): the vendored chart + the entry swap +
    # the overlay flip ride ONE commit (R6-Q4-2 window-closed-by-
    # construction); the chart's claim line must be provably UNMOVED in that
    # commit (comment-only diff, AC3).
    stat=$(git show --stat --format= "$AMD_GPU_FLIP_COMMIT" 2>/dev/null || true)
    [ -n "$stat" ] || fail "n2: AMD_GPU_FLIP_COMMIT=$AMD_GPU_FLIP_COMMIT is not a commit"
    for path in charts/amd-gpu/ "$VALS"; do
      printf '%s\n' "$stat" | grep -q "$path" \
        || fail "n2: same-wave violation — commit $AMD_GPU_FLIP_COMMIT does not touch $path (vendored chart, entry swap and the overlay flip — one commit; git show --stat is the evidence)"
    done
    bare_now=$(git show "$AMD_GPU_FLIP_COMMIT:charts/llama-swap/values.yaml" 2>/dev/null | grep -cE '^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$' || true)
    bare_before=$(git show "$AMD_GPU_FLIP_COMMIT^:charts/llama-swap/values.yaml" 2>/dev/null | grep -cE '^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$' || true)
    [ "$bare_now" = "$bare_before" ] \
      || fail "n2: the flip commit MOVED the chart's tree-global bare claim line ($bare_before -> $bare_now) — B1: claim-line diff must be zero, comments only"
    ok "n2: per-cluster flip needles green AND the same-wave commit guard + chart claim-line-zero-diff verified against $AMD_GPU_FLIP_COMMIT"
  else
    skip "n2: same-wave COMMIT guard not run — review sets AMD_GPU_FLIP_COMMIT=<sha> and re-runs n2 (git-show check incl. the claim-line zero-diff leg, C07 Tests bullet 3)"
    ok "n2: per-cluster truth holds — gpu-ai overlay carries the APU flip with the bare-null retire, the chart keeps its tree-global bare claim untouched (APU-name-free), fallback comment retired (same-wave commit guard deferred to review)"
  fi
fi

# --- n3: per-cluster claim sweep (AC4 re-scoped) --------------------------------
if want n3; then
  # Live requests/limits claim lines across charts/ services/, comments and
  # test fixtures excluded (the fixtures are RENDERS guarded by the
  # off-parity byte cadence — under B1 the default fixture moved ZERO lines,
  # TEST_SPEC §12.2). Per-cluster law:
  #   bare amd.com/gpu     -> ONLY charts/llama-swap/values.yaml (tree-global
  #                           default; the gpu cluster renders it against the
  #                           external single-naming plugin — services/gpu's
  #                           own values carry no claim line at all);
  #   amd.com/gpu-8060s    -> ONLY services/gpu-ai/prod/values.yaml (overlay
  #                           flip) — ledger/name mentions are comments,
  #                           exempt by pattern;
  #   amd.com/gpu-ai-pro-r9700 -> nowhere until C02, then charts/radiance
  #                           only (allow-list prefix pre-declared so the
  #                           guard stays honest when the chart lands).
  claim_grep() {  # $1=resource name -> "file:line: text" hits, non-comment, yaml-ish
    grep -rn --include='*.yaml' --include='*.yml' --include='*.tpl' \
      -E "^[[:space:]]*$(printf '%s' "$1" | sed 's/\./\\./g'):[[:space:]]*[0-9]+[[:space:]]*$" \
      charts/ services/ 2>/dev/null \
      | grep -vE ':[0-9]+:[[:space:]]*#' \
      | grep -vE '^charts/[^/]+/tests/|^services/[^/]+/tests/' || true
  }
  bad=$(claim_grep "amd.com/gpu" | grep -vE '^charts/llama-swap/values\.yaml:' || true)
  if [ -n "$bad" ]; then
    fail "n3 (AC4 per-cluster): bare amd.com/gpu claims OUTSIDE the charts/llama-swap tree-global default — every other renderer has no such pool post-gpu-ai-flip (stray claims are Pending-forever, R6-Q4-3):
$bad"
  fi
  bad=$(claim_grep "amd.com/gpu-8060s" | grep -vE '^services/gpu-ai/prod/values\.yaml:' || true)
  if [ -n "$bad" ]; then
    fail "n3 (AC4 stray-guard): live APU-name claims outside the gpu-ai overlay — the gpu cluster's 1.31.0.9 plugin cannot advertise it (B1):
$bad"
  fi
  bad=$(claim_grep "amd.com/gpu-ai-pro-r9700" | grep -vE '^charts/radiance/' || true)
  if [ -n "$bad" ]; then
    fail "n3 (AC4): live R9700-pool claims outside charts/radiance (where C02 will claim it) and the amd-gpu ledger comments:
$bad"
  fi
  if grep -E "^[[:space:]]*amd\.com/gpu(-[a-z0-9-]+)?:[[:space:]]*[0-9]+" services/gpu/prod/values.yaml \
     | grep -vE '^[[:space:]]*#' | grep -q .; then
    fail "n3: services/gpu/prod/values.yaml carries a GPU claim line — the gpu cluster is shielded, its overlay stays claim-free (D21 untouched witness)"
  fi
  ok "n3: per-cluster sweep clean — bare claims ONLY the llama-swap tree-global default, the APU name ONLY in the gpu-ai overlay, the R9700 name nowhere yet (charts/radiance pre-allowed for C02), services/gpu claim-free (comments/fixtures exempt per the pattern)"
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
