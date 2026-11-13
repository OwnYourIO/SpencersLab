#!/usr/bin/env bash
# cf-143 C07 — the naming-wave contract suite (chunks/C07.md Tests bullet 3,
# legs n1-n4 + the workflow deliverable the chunk's file scope names).
#
# The wave makes the R9700/APU claim deterministic BY NAME ON GPU-AI (owner
# Q9 ruling + B1 shield, DECISIONS D18/D19/D21): a vendored charts/amd-gpu
# (upstream 0.22.0 + the ~10-line args hook) runs the plugin at 1.31.0.12
# with -resource_naming_strategy=product; the gpu-ai-amd-gpu Application
# switches source repo->git-path with IDENTICAL object names; llama-swap's
# gpu-ai render claims amd.com/gpu-8060s VIA ITS SERVICE-OVERLAY ADD and the
# gpu cluster claims the bare amd.com/gpu VIA ITS OWN OVERLAY ADD — the CHART
# default ships NO GPU claim (C10/D26: a tree-global claim cannot be retired
# per cluster — overlay nulls die in the ApplicationSet->Application
# valuesObject chain, §D2 live pair; extended resources take positive
# integers only, so 0 is no escape either; positive per-cluster ADDs are the
# carrier that survives. D21's INTENT stands verbatim: gpu bare, gpu-ai the
# named APU, a tree-global flip would strand live gpu-llama-swap).
#
# Re-scopes: C07 landing round made n2 the per-cluster flip needle and n3 the
# AC4 placement sweep; C10/D26 moved the CARRIER (chart claim-less, both
# claims live as per-cluster overlay ADDs — the null-retirement mechanism and
# the tree-global bare default are DEAD LAW, the same false-prose honesty
# pass that cleared values.yaml); the env-gated guard now accepts WAVE-A/B
# (zero-diff check) and WAVE-C (transfer check: chart bare 1->0 AND services/
# gpu 0->+ in ONE commit). Comments/fixtures exempt by pattern; the
# off-parity fixture moved by EXACTLY the transferred 2 lines at C10's
# re-baseline (PROVENANCE era entry — the "zero lines" B1 claim is history).
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
AMD_GPU_VALUES="${AMD_GPU_VENDORED_VALUES:-charts/amd-gpu/values.yaml}"
VENDORED="$AMD_GPU_VALUES"   # legacy alias: the file's path is stable across the C08 rewrite
APPSET="${AMD_GPU_APPSET:-charts/base/templates/appset-charts.yaml}"
WORKFLOW=".github/workflows/amd-gpu-render-tests.yaml"

# ---------------------------------------------------------------------------
# GPU RESOURCE-NAME CONSTANTS — the C08 lane RULING LANDED mid-round (D24:
# table-mount rename; the string the owner first asked is unreachable by any
# mechanism — §R7-Q1's code-constant prefix/domain law — so the pool carries
# the sanitizer's closest output below). THE ONLY bash-side name needles
# ticket-wide: any future lane move edits HERE and the marked block in
# charts/amd-gpu/tests/amd_gpu_testlib.py (the python canonical home), never
# needle archaeology. Conversion legs (C08 n2) are name-agnostic.
BARE_CLAIM="amd.com/gpu"                       # gpu-cluster claim; C10: the CARRIER moved to
#                                                the gpu overlay (chart default is claim-less —
#                                                D26: nulls die in the appset→valuesObject
#                                                chain; positive per-cluster ADDs are the only
#                                                carrier). The NAME never renames.
GPU_VALS="services/gpu/prod/values.yaml"
APU_CLAIM="amd.com/gpu-8060s"                  # frozen by the D24 ruling scope
R9700_CLAIM="amd.com/gpu-r9700-1"              # D24: patched-table sanitizer output
# ---------------------------------------------------------------------------

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

# --- n2: the per-cluster carrier needles (ADDs; no nulls) + same-wave guard -----
# C10/D26 law: the gpu-ai overlay ADDS amd.com/gpu-8060s (requests mirror
# included), the gpu overlay ADDS the bare amd.com/gpu, the chart ships NO
# GPU claim; the old overlay-null retirement is DEAD (nulls are dropped by
# the ApplicationSet->valuesObject chain before helm sees them — §D2 live
# pair — and positive integers only, so the ADD is the carrier). The
# same-wave lockstep law is closed by construction (entry swap + flip share
# this file; the chart conversion rides its commit); the env-gated git-show
# guard re-pins each landing wave's file set + claim-line/transfer checks.
if want n2; then
  [ -f "$SWAP_VALUES" ] || fail "n2: $SWAP_VALUES missing"
  [ -f "$VALS" ] || fail "n2: $VALS missing"
  # (a) the gpu-ai overlay ADD: APU limits pair + the explicit requests
  #     mirror (positive per-cluster ADDs only, D26 shape)
  grep -qE "^[[:space:]]*${APU_CLAIM}: 1" "$VALS" \
    || fail "n2: $VALS carries no live '${APU_CLAIM}: 1' overlay line — the per-cluster flip did not land (llama-swap keeps the APU BY NAME on gpu-ai, owner Q9/B1)"
  # C10/D26 flip: the null retirement is INERT through the appset→valuesObject
  # chain (live pair §D2) — it must be GONE (chart claim-less makes it moot)
  # and the gpu cluster's claim must exist as a positive ADD in services/gpu.
  if grep -qE "^[[:space:]]*amd\.com/gpu:[[:space:]]*null[[:space:]]*$" "$VALS"; then
    fail "n2 (C10): the inert 'amd.com/gpu: null' retirement line is still in the gpu-ai overlay — nulls never reach helm through the chain (§D2/D26); the carrier is the per-cluster ADD, delete the null"
  fi
  grep -qE "^[[:space:]]*amd\.com/gpu:[[:space:]]*1[[:space:]]*$" "$GPU_VALS" \
    || fail "n2 (C10): services/gpu/prod/values.yaml carries no bare 'amd.com/gpu: 1' ADD — the gpu cluster would get a GPU-LESS llama-swap pod once the chart default goes claim-less (the carrier moved, not the posture, D21 intent)"
  # (b) C10: the chart default is CLAIM-LESS (both pools named only per-cluster);
  # no claim of ANY name lives in the chart anymore.
  if grep -E "^[[:space:]]*amd\.com/gpu(-[a-z0-9-]+)?:[[:space:]]*[0-9]+[[:space:]]*$" "$SWAP_VALUES" | grep -vqE '^[[:space:]]*#'; then
    fail "n2 (C10): a LIVE GPU-claim line remains in charts/llama-swap/values.yaml — the carrier moved per-cluster (D26); a tree-global claim is exactly what cannot be retired through the chain"
  fi
  # the fallback comment retired as realized prose (needle mirror of the pytest leg)
  if grep -qi "fallback once a naming-capable plugin exists" "$SWAP_VALUES"; then
    fail "n2: the 'fallback once a naming-capable plugin exists' comment survived — it rewrites to per-cluster REALIZED prose (C07 task, D21 wording)"
  fi
  if [ -n "${AMD_GPU_FLIP_COMMIT:-}" ]; then
    # Same-wave guard (review-time), TWO accepted wave shapes (C09 extension
    # of the C08 file-set):
    #   WAVE-A (C07/C08 landings): the chart conversion + the radiance values
    #     legs + the gpu-ai service file — one commit, window closed by
    #     construction (R6-Q4-2);
    #   WAVE-B (C09 live-defect fix): the values key + the runbook doc — the
    #     receipt/consequence lines RIDE the fix (a stale runbook next to a
    #     crashloop fix is its own defect class).
    # The chart claim-line zero-diff sub-check runs only when the commit
    # touches charts/llama-swap/values.yaml (WAVE-A territory; B1 shield).
    stat=$(git show --stat --format= "$AMD_GPU_FLIP_COMMIT" 2>/dev/null || true)
    [ -n "$stat" ] || fail "n2: AMD_GPU_FLIP_COMMIT=$AMD_GPU_FLIP_COMMIT is not a commit"
    wave_a() {
      for path in charts/amd-gpu/ charts/radiance/ "$VALS"; do
        printf '%s\n' "$stat" | grep -q "$path" || return 1
      done
    }
    wave_b() {
      for path in charts/amd-gpu/ .agents/notes/radiance-on-target-acceptance.md; do
        printf '%s\n' "$stat" | grep -q "$path" || return 1
      done
    }
    wave_c() {
      for path in charts/llama-swap/values.yaml "$GPU_VALS" "$VALS" .agents/notes/radiance-on-target-acceptance.md; do
        printf '%s\n' "$stat" | grep -q "$path" || return 1
      done
    }
    if wave_c; then
      shape="WAVE-C (C10 carrier wave: chart + BOTH overlays + runbook in ONE commit)"
    elif wave_a; then
      shape="WAVE-A (conversion wave)"
    elif wave_b; then
      shape="WAVE-B (C09 defect-fix wave: values + runbook)"
    else
      fail "n2: same-wave violation — commit $AMD_GPU_FLIP_COMMIT matches NO accepted shape (WAVE-C: charts/llama-swap + services/gpu + services/gpu-ai + the runbook as one commit; WAVE-A: charts/amd-gpu + charts/radiance + $VALS; WAVE-B: charts/amd-gpu + runbook) — a SPLIT carrier leaves a cluster with zero schedulable claims between syncs"
    fi
    claim_note=" (llama-swap chart untouched by this commit)"
    if printf '%s\n' "$stat" | grep -q "charts/llama-swap/values.yaml"; then
      bare_now=$(git show "$AMD_GPU_FLIP_COMMIT:charts/llama-swap/values.yaml" 2>/dev/null | grep -cE '^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$' || true)
      bare_before=$(git show "$AMD_GPU_FLIP_COMMIT^:charts/llama-swap/values.yaml" 2>/dev/null | grep -cE '^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$' || true)
      gpu_now=$(git show "$AMD_GPU_FLIP_COMMIT:$GPU_VALS" 2>/dev/null | grep -cE '^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$' || true)
      gpu_before=$(git show "$AMD_GPU_FLIP_COMMIT^:$GPU_VALS" 2>/dev/null | grep -cE '^[[:space:]]*amd\.com/gpu: 1[[:space:]]*$' || true)
      if [ "$shape" != "${shape#WAVE-C}" ]; then
        # TRANSFER check: the bare claim MOVED chart→gpu-overlay in THIS commit —
        # exactly one live site before (the chart), exactly one after (services/gpu).
        [ "$bare_before" -ge 1 ] || fail "n2 transfer check: WAVE-C parent had no chart bare claim to transfer"
        [ "$bare_now" = "0" ] || fail "n2 transfer check (C10): the WAVE-C commit left $bare_now chart default bare claim(s) — the carrier move must zero it"
        [ "$gpu_now" -gt "$gpu_before" ] || fail "n2 transfer check (C10): services/gpu bare ADD did not grow (gpu_before=$gpu_before gpu_now=$gpu_now) — the claim must be ADDED there in the SAME commit (split = one cluster unschedulable between syncs)"
        claim_note=" + carrier transfer verified (chart bare $bare_before->0, gpu overlay +$((gpu_now-gpu_before)))"
      else
        [ "$bare_now" = "$bare_before" ] \
          || fail "n2: the $shape commit MOVED the chart's bare claim line ($bare_before -> $bare_now) — only WAVE-C may do that (carrier move)"
        [ "$gpu_now" = "$gpu_before" ] \
          || fail "n2: the $shape commit moved the gpu-overlay bare claims ($gpu_before -> $gpu_now) — only WAVE-C may do that"
        claim_note=" + chart/gpu claim-line zero-diff"
      fi
    fi
    ok "n2: per-cluster flip needles green AND the $shape same-wave guard verified$claim_note against $AMD_GPU_FLIP_COMMIT"
  else
    skip "n2: same-wave COMMIT guard not run — review sets AMD_GPU_FLIP_COMMIT=<sha> and re-runs n2 (git-show check incl. the claim-line zero-diff leg, C07 Tests bullet 3)"
    ok "n2: carrier law holds — gpu-ai overlay ADDs gpu-8060s with NO inert null line, services/gpu ADDs the bare claim, the chart ships NO GPU claim at all (claim-less default, D26), fallback comment retired (same-wave commit guard deferred to review)"
  fi
fi

# --- n3: per-cluster claim sweep (AC4 re-scoped) --------------------------------
if want n3; then
  # Live requests/limits claim lines across charts/ services/, comments and
  # test fixtures excluded (the fixtures are RENDERS guarded by the
  # off-parity byte cadence — re-baselined at C10 by exactly the transferred
  # 2 lines, PROVENANCE era entry). Per-cluster law (C10/D26 carrier):
  #   bare amd.com/gpu     -> ONLY services/gpu/prod/values.yaml (the gpu
  #                           cluster's overlay ADD — its plugin is the
  #                           external single-naming 1.31.0.9; the CHART
  #                           default is now claim-less and must carry ZERO
  #                           live claim lines of any name);
  #   amd.com/gpu-8060s    -> ONLY services/gpu-ai/prod/values.yaml (overlay
  #                           flip) — ledger/name mentions are comments,
  #                           exempt by pattern;
  #   renamed pool ($R9700_CLAIM) -> ONLY charts/radiance live claims (D24 sweep);
  #                           no other file carries it claim-shaped; comment/
  #                           ledger/doc placement is AC4's python-leg scope.
  claim_grep() {  # $1=resource name -> "file:line: text" hits, non-comment, yaml-ish
    grep -rn --include='*.yaml' --include='*.yml' --include='*.tpl' \
      -E "^[[:space:]]*$(printf '%s' "$1" | sed 's/\./\\./g'):[[:space:]]*[0-9]+[[:space:]]*$" \
      charts/ services/ 2>/dev/null \
      | grep -vE ':[0-9]+:[[:space:]]*#' \
      | grep -vE '^charts/[^/]+/tests/|^services/[^/]+/tests/' || true
  }
  # C10/D26: the bare CLAIM now lives ONLY in the gpu overlay (the chart default
  # is claim-less; gpu-ai's node has the name at capacity 0 — a stray there is
  # the live Pending-forever defect).
  bad=$(claim_grep "$BARE_CLAIM" | grep -vE "^$GPU_VALS:" || true)
  if [ -n "$bad" ]; then
    fail "n3 (C10 AC4 per-cluster): bare amd.com/gpu live claims OUTSIDE services/gpu/prod/values.yaml (the gpu cluster's ADD carrier) —
$bad"
  fi
  claim_grep "$BARE_CLAIM" | grep -q "^$GPU_VALS:" \
    || fail "n3 (C10): the gpu overlay carries no bare claim line — after the chart went claim-less, gpu-llama-swap would lose its scheduling claim (posture unchanged, carrier moved, D21 intent)"
  bad=$(claim_grep "amd.com/gpu-8060s" | grep -vE '^services/gpu-ai/prod/values\.yaml:' || true)
  if [ -n "$bad" ]; then
    fail "n3 (AC4 stray-guard): live APU-name claims outside the gpu-ai overlay — the gpu cluster's 1.31.0.9 plugin cannot advertise it (B1):
$bad"
  fi
  bad=$(claim_grep "$R9700_CLAIM" | grep -vE '^charts/radiance/' || true)
  if [ -n "$bad" ]; then
    fail "n3 (AC4): live claims of the renamed pool outside charts/radiance (the D24 claim site) —
$bad"
  fi
  extra_gpu=$(claim_grep "$BARE_CLAIM" | grep -c "^$GPU_VALS:" || true)
  [ "$extra_gpu" = "1" ] || [ "$extra_gpu" = "0" ] \
    || fail "n3 (C10): services/gpu carries $extra_gpu bare-claim lines — exactly one is the carrier (double claims would demand capacity 2 the node lacks)"
  if claim_grep "$APU_CLAIM" | grep -q "^$GPU_VALS:"; then
    fail "n3: the gpu overlay claims ${APU_CLAIM} — that name exists only on the gpu-ai node (single-naming 1.31.0.9 plugin, D21 intent)"
  fi
  ok "n3: carrier-law sweep clean — bare claims ONLY in services/gpu/prod/values.yaml (the gpu overlay ADD — the chart default is claim-less since C10/D26), the APU name ONLY in the gpu-ai overlay, the renamed R9700 pool ONLY in charts/radiance (D24 sweep), the chart claim-free — exactly one live site per claim name (comments/fixtures exempt per the pattern)"
fi

# --- n4: the vendored chart's expected-names ledger (the C02 authority) ---------
if want n4; then
  [ -f "$VENDORED" ] || fail "n4: $VENDORED missing — the amd-gpu chart (first-party since C08/D23) is the producer of the pool names; the ledger comment lives here"
  grep -qF "$R9700_CLAIM" "$VENDORED" || fail "n4: $VENDORED never names ${R9700_CLAIM} (the 7551/C0 pool the D24 patched table derives; C02 claims it)"
  grep -qF "$APU_CLAIM" "$VENDORED" || fail "n4: $VENDORED never names ${APU_CLAIM} (the 1586 product pool llama-swap flips to)"
  grep -E "^[[:space:]]*#" "$VENDORED" | grep "7551" | grep -qF "${R9700_CLAIM#amd.com/}" \
    || fail "n4: no ledger COMMENT row mapping 7551 (R9700) to ${R9700_CLAIM#amd.com/} — the patched-table name (D24) must sit where the test reads it (same-line row form)"
  grep -E "^[[:space:]]*#" "$VENDORED" | grep "1586" | grep -q "gpu-8060s" \
    || fail "n4: no ledger COMMENT row mapping 1586 (APU) to gpu-8060s"
  # The fallback trap named (its decision tree stays in the runbook, C06):
  grep -qi "fallback" "$VENDORED" \
    || fail "n4: the unknown-(device,revision) -> bare amd.com/gpu fallback trap is not named beside the ledger"
  ok "n4: the chart's values ledger records 7551/C0->${R9700_CLAIM#amd.com/} (patched table), 1586->${APU_CLAIM#amd.com/} (carried rows) and the fallback trap + WATCH (cross-chart join: charts/radiance/tests/test_resource_name_identity.py)"
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
