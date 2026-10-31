#!/usr/bin/env bash
# C03 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline):
# charts/home-assistant gains the app-template 5.0.1 HA container + gated
# /config PVC, and the existing CNPG/secret templates move behind
# postgres.enabled (default TRUE) — the LIVE grow release is the regression
# risk, so the golden snapshot below is the proof instrument.
#
# Contract source: chunks/C03.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC2] t3[AC3] t4[AC4+AC5] t5[AC1 grow-slice].
#
# GOLDEN SNAPSHOT — tests/multi-repo/snapshots/ha-chart-default.yaml,
# captured by agent-test on 2026-10-31 from branch cf-93-feat-multi-repo-
# pipeline @ 7e07a6273e (pre-C03 HEAD, charts/home-assistant clean), via
# `helm template ha-test charts/home-assistant` (helm v3.16.4) run through
# the normalizer below (the same code path reviews re-run). sha256 of the
# snapshot at capture: c4c8c65ea4ace29ff1017ecb272e9735e5cc088ea6af543f3b2bef82d859f86f
# Content: 2 CNPG Clusters + 4 ExternalSecrets — nothing else, no kind
# Deployment/PVC (container + persistence are the gated-off new resources).
#
# Why normalized, not raw bytes: the pre-change render contains the fully
# commented PVC stub AS a comment-only document (helm emits it as text), and
# C03 rewrites that file into a gated real template — that document
# legitimately disappears. The snapshot pipeline drops comment-only docs,
# parses each remaining resource through yaml, and sorts by (kind, name,
# namespace): byte-identity of every resource ArgoCD would apply, immune to
# comment placement and template-wrap whitespace. A changed value, label,
# added/removed resource, or reordering of content still breaks the cmp.
#
# Rendering runs on a COPY under /tmp/opencode after `helm dependency update`
# (repo convention: charts/**/charts is gitignored, Chart.lock committed —
# dev-forgejo-runner.sh precedent). No-cluster/no-network: if the bjw-s
# registry is unreachable the helm legs skip LOUDLY (stderr skip lines) —
# never silent. FRICTION: PATH exports ~/.local/bin first or helm vanishes.
#
# Usage:
#   bash tests/multi-repo/ha-chart.sh            # t1..t5
#   bash tests/multi-repo/ha-chart.sh t1 t5      # subset
# Env: HELM_BIN (binary override), HA_SNAPSHOT (re-point the golden file if
#   main legitimately re-based the chart), CHART (default
#   charts/home-assistant).
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # helm lives here — FRICTION seed, never optional

cd "$(git rev-parse --show-toplevel)"

CHART="${CHART:-charts/home-assistant}"
SNAP="${HA_SNAPSHOT:-tests/multi-repo/snapshots/ha-chart-default.yaml}"
DIFF_BASE="${HA_CHART_DIFF_BASE:-$(git merge-base HEAD main)}"
HA_IMAGE="ghcr.io/home-assistant/home-assistant"
HA_TAG="2026.10.4"

checks=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
skip() { printf 'skip: %s\n' "$1" >&2; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected t1..t5)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- helm discovery (dev-forgejo-runner.sh convention, loud on failure) ------
find_helm() {
  local cand
  if [ -n "${HELM_BIN:-}" ] && [ -x "${HELM_BIN}" ]; then printf '%s' "$HELM_BIN"; return 0; fi
  if command -v helm >/dev/null 2>&1; then command -v helm; return 0; fi
  if [ -x "$HOME/.local/bin/helm" ]; then printf '%s' "$HOME/.local/bin/helm"; return 0; fi
  cand=$(find /tmp/opencode -maxdepth 4 -type f -name helm -perm -u+x 2>/dev/null | head -n 1 || true)
  [ -n "$cand" ] && { printf '%s' "$cand"; return 0; }
  return 1
}

helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || fail "ha-chart: no helm binary (HELM_BIN/PATH/~/.local/bin//tmp/opencode) — the whole suite is helm-shaped, a silent pass here is the FRICTION hazard"

WORK=$(mktemp -d /tmp/opencode/ha-chart.XXXXXX)
NORMALIZER="$WORK/normalize.py"
cat > "$NORMALIZER" <<'PY'
# Keep only real resources (docs with apiVersion+kind), sort deterministically,
# re-emit as canonical YAML. See header: this is THE snapshot pipeline — capture
# and re-check must run the identical code.
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.stdin) if isinstance(d, dict) and d.get('kind')]
docs.sort(key=lambda d: (d.get('kind'), (d.get('metadata') or {}).get('name', ''), (d.get('metadata') or {}).get('namespace', '')))
out = []
for i, d in enumerate(docs):
    if i:
        out.append('---\n')
    out.append(yaml.safe_dump(d, sort_keys=False, default_flow_style=False, allow_unicode=True))
sys.stdout.write(''.join(out))
PY

[ -f "$SNAP" ] || fail "ha-chart: golden snapshot $SNAP missing — agent-test captures it from the pre-C03 HEAD; without it AC1 has no baseline"

# --- render-on-copy machinery: dependency update once, legs reuse -------------
skip_render=0
COPY="$WORK/home-assistant"
mkdir -p "$COPY"
cp -R "$CHART"/. "$COPY"/
dep_log="$WORK/dependency-update.log"
if ! (cd "$COPY" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
  if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|failed to download|failed to fetch|could not download' "$dep_log"; then
    skip_render=1
    skip "helm dependency update could not reach the registry (log $dep_log); t1-t3+t5 render legs skipped LOUD, t4 statics still run"
  else
    tail -n 30 "$dep_log" >&2
    fail "helm dependency update failed for $CHART — not a network skip (log $dep_log)"
  fi
fi

render() { # render <outfile> [--set ...] — plain defaults when no args
  local out="$1"; shift
  if ! "$helm_bin" template ha-test "$COPY" "$@" >"$out" 2>"$out.err"; then
    tail -n 30 "$out.err" >&2
    fail "helm template of $COPY ($*) failed (stderr kept at $out.err)"
  fi
}

# --- t1: default render == golden snapshot (C03 AC1, grow regression proof) ---
if want t1; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t1: golden diff not run (dependency registry unreachable)"
  else
    "$helm_bin" template ha-test "$COPY" | python3 "$NORMALIZER" > "$WORK/default.norm.yaml"
    cmp -s "$WORK/default.norm.yaml" "$SNAP" \
      || { diff -u "$SNAP" "$WORK/default.norm.yaml" | head -n 60 >&2; fail "t1: the DEFAULT render no longer matches the pre-C03 golden snapshot — postgres.enabled defaults on, container+PVC default off, grow renders unchanged (AC1). Diff above."; }
    ok "t1: default render is resource-identical to the pre-change golden snapshot at $SNAP (postgres gated on, HA container + PVC gated off — grow regression proof)"
  fi
fi

# --- t2: dev-mode render (C03 AC2) --------------------------------------------
if want t2; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t2: dev-mode render not run (dependency registry unreachable)"
  else
    render "$WORK/dev.yaml" --set homeAssistant.enabled=true --set postgres.enabled=false
    render "$WORK/dev-pvc.yaml" --set homeAssistant.enabled=true --set postgres.enabled=false --set homeAssistant.persistence.enabled=true
    if python3 - "$WORK/dev.yaml" "$WORK/dev-pvc.yaml" "$HA_IMAGE" "$HA_TAG" <<'PY'
import re, sys, yaml

dev_f, pvc_f, image, tag = sys.argv[1:5]
def bad(msg):
    print(f'FAIL: t2 {msg}', file=sys.stderr)
    sys.exit(1)

docs = [d for d in yaml.safe_load_all(open(dev_f)) if isinstance(d, dict)]
kinds = sorted({d.get('kind') for d in docs})
if kinds != ['Deployment', 'Service']:
    bad(f'homeAssistant.enabled=true, postgres.enabled=false rendered kinds {kinds}, expected exactly [Deployment, Service] (AC2 renders EXACTLY the HA workload+service)')

dep = next(d for d in docs if d.get('kind') == 'Deployment')
pod = dep['spec']['template']['spec']
cons = pod.get('containers') or []
ha = next((c for c in cons if image in (c.get('image') or '')), None)
if ha is None:
    bad(f'no container image referencing {image} in the Deployment (images: {[c.get("image") for c in cons]})')
if ha['image'] != f'{image}:{tag}':
    bad(f'HA image is {ha["image"]!r}, expected the pinned {image}:{tag} (AC2 — no :latest, no unpinned)')
ports = [p.get('containerPort') for p in ha.get('ports') or []]
if 8123 not in ports:
    bad(f'container ports {ports} lack 8123')
for probe in ('readinessProbe', 'livenessProbe', 'startupProbe'):
    if not ha.get(probe):
        bad(f'HA container lacks {probe} (AC2: probes rendered; startup probe covers the HA cold start)')
sc = ha.get('securityContext') or {}
if (sc.get('capabilities') or {}).get('drop') != ['ALL']:
    bad(f'securityContext.capabilities.drop is {(sc.get("capabilities") or {}).get("drop")!r}, expected [ALL]')
if sc.get('allowPrivilegeEscalation') is not False:
    bad('securityContext.allowPrivilegeEscalation is not false')
if sc.get('readOnlyRootFilesystem') is True:
    bad('readOnlyRootFilesystem true — HA writes into its install tree (chunk: only when the app tolerates it)')
mounts = [m.get('mountPath') for m in ha.get('volumeMounts') or []]
if '/config' not in mounts:
    bad(f'no /config mount (volumeMounts: {mounts})')

svcs = [d for d in docs if d.get('kind') == 'Service']
if not svcs:
    bad('no Service rendered')
for s in svcs:
    if (s.get('spec') or {}).get('type') not in (None, 'ClusterIP'):
        bad(f'Service {s["metadata"]["name"]} type is {s["spec"]["type"]!r}, expected ClusterIP-only in dev')
if not any(p.get('port') == 8123 for s in svcs for p in (s.get('spec') or {}).get('ports') or []):
    bad('no Service exposes port 8123')

raw = open(dev_f).read()
if 'postgresql.cnpg.io' in raw:
    bad('CNPG apiGroup still appears with postgres.enabled=false')
off_kinds = {d.get('kind') for d in docs}
for forbidden in ('Cluster', 'ExternalSecret', 'Secret', 'PersistentVolumeClaim'):
    if forbidden in off_kinds:
        bad(f'{forbidden} rendered with postgres.enabled=false / persistence default-off — no CNPG cluster, no pg/app/mcp secret, no PVC (AC2)')

pvc_docs = [d for d in yaml.safe_load_all(open(pvc_f)) if isinstance(d, dict) and d.get('kind') == 'PersistentVolumeClaim']
if len(pvc_docs) != 1:
    bad(f'with homeAssistant.persistence.enabled=true the render has {len(pvc_docs)} PVCs, expected exactly 1 (AC2)')
pvc = pvc_docs[0]
if ((pvc.get('spec') or {}).get('resources') or {}).get('requests', {}).get('storage') != '5Gi':
    bad(f'PVC requests {(((pvc.get("spec") or {}).get("resources") or {}).get("requests") or {}).get("storage")!r}, expected 5Gi')
if re.search(r'ha-test', pvc['metadata']['name']) is None:
    bad(f'PVC name {pvc["metadata"]["name"]!r} is not release-derived ({{{{ .Release.Name }}}}-named, chunk Tasks)')
print('ok: t2 — dev-mode render: pinned image, 8123 port+service, probes, drop-ALL no-priv sc, /config mount, no CNPG/secret/PVC; PVC appears exactly (5Gi, release-named) when persistence is set true (C03 AC2)')
PY
    then checks=$((checks + 1)); else fail 't2: the dev-mode render contract is not satisfied (reason printed above)'; fi
  fi
fi

# --- t3: full-feature render leaks no OVERRIDE_ (C03 AC3) --------------------
if want t3; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t3: full-feature render not run (dependency registry unreachable)"
  else
    "$helm_bin" template ha-test "$COPY" \
      --set postgres.enabled=true --set homeAssistant.enabled=true \
      --set domain=test.example.com \
      --set bitwardenIds.home-assistant-pg=test-uuid \
      --set bitwardenIds.mcp-pg-grow-assistant=test-uuid \
      --set bitwardenIds.mcp-pg-grow-assistant-sensors=test-uuid \
      >"$WORK/full.yaml" 2>"$WORK/full.err" \
      || { tail -n 30 "$WORK/full.err" >&2; fail "t3: full-feature render failed"; }
    if grep -q 'OVERRIDE_' "$WORK/full.yaml"; then
      grep -n 'OVERRIDE_' "$WORK/full.yaml" | head >&2
      fail 't3: an OVERRIDE_* sentinel survived the full-feature render — every bitwardenIds/domain placeholder must be consumed when set (AC3)'
    fi
    for kind in Cluster ExternalSecret Deployment; do
      grep -q "^kind: $kind$" "$WORK/full.yaml" || fail "t3: full-feature render lost kind $kind (postgres ON + HA ON must render CNPG, secrets AND the workload)"
    done
    ok "t3: full-feature render carries no OVERRIDE_* string and keeps Cluster + ExternalSecret + Deployment kinds (C03 AC3)"
  fi
fi

# --- t4: lint, dependency list, version law, image literal (C03 AC4+AC5) -----
if want t4; then
  grep -qE '^version: [0-9.]+$' "$CHART/Chart.yaml" || fail "t4: no parsable version line in $CHART/Chart.yaml"
  cur_v=$(grep -m1 -E '^version:' "$CHART/Chart.yaml" | tr -d '[:space:]')
  base_v=$(git show "$DIFF_BASE:$CHART/Chart.yaml" | grep -m1 -E '^version:' | tr -d '[:space:]')
  [ "$cur_v" = "$base_v" ] || fail "t4: Chart.yaml version bumped ($base_v -> $cur_v) — release.yaml owns patch bumps, NEVER hand-bump (version law)"
  ok "t4: Chart.yaml $cur_v matches the fork-point value — no hand-bump (AC4)"

  if grep -q '4.3.0' "$CHART/Chart.yaml"; then
    fail "t4: the commented app-template 4.3.0 stub is still in Chart.yaml — C03 replaces it with the active 5.0.1 dependency"
  fi
  grep -q '5.0.1' "$CHART/Chart.yaml" || fail "t4: Chart.yaml lacks the app-template 5.0.1 dependency entry (the zigbee2mqtt-pinned version)"
  grep -q 'bjw-s-labs.github.io/helm-charts' "$CHART/Chart.yaml" || fail "t4: Chart.yaml dependency repository is not the bjw-s-labs repo"
  [ -f "$CHART/Chart.lock" ] || fail "t4: $CHART/Chart.lock not committed (helm dependency update output, AC4)"
  ok "t4: Chart.yaml declares app-template 5.0.1 @ bjw-s-labs, 4.3.0 stub gone, Chart.lock committed"

  grep -q "$HA_IMAGE" "$CHART/values.yaml" || fail "t4: values.yaml does not reference $HA_IMAGE"
  grep -q "$HA_TAG" "$CHART/values.yaml" || fail "t4: values.yaml does not pin tag $HA_TAG (AC5 — explicit pinned tag, no :latest)"
  ok "t4: values image literals present ($HA_IMAGE : $HA_TAG)"

  if [ "$skip_render" -eq 1 ]; then
    skip "t4: lint/dependency-list legs not run (dependency registry unreachable)"
  else
    lint_log="$WORK/lint.log"
    (cd "$COPY" && "$helm_bin" lint .) >"$lint_log" 2>&1 || { tail -n 30 "$lint_log" >&2; fail "t4: helm lint failed for $CHART (log $lint_log)"; }
    ok "t4: helm lint passes ($("$helm_bin" version --short 2>/dev/null || echo helm))"
    deps="$WORK/dep-list.txt"
    "$helm_bin" dependency list "$COPY" >"$deps" 2>&1 || fail "t4: helm dependency list failed"
    grep -E '^app-template\s+5\.0\.1\s+https://bjw-s-labs\.github\.io/helm-charts/\s+READY' "$deps" >/dev/null \
      || { cat "$deps" >&2; fail "t4: helm dependency list lacks an app-template 5.0.1 READY row (AC4)"; }
    ok "t4: helm dependency list shows app-template 5.0.1 READY (Chart.lock consistent)"
  fi
fi

# --- t5: grow-slice render — the live release shape (C03 AC1 corroboration) --
if want t5; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t5: grow-slice render not run (dependency registry unreachable)"
  else
    python3 - <<'PY' || fail "t5: could not extract the grow assistant slice (schema drift in services/grow or custom-values/grow?)"
import re, sys, yaml

# Anchor-stripping loader (values files use YAML anchors; placeholder values
# are never asserted — dev-forgejo loader precedent).
def load(path):
    lines = []
    for line in open(path):
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

merged = {}
grow = load('services/grow/prod/values.yaml')
# The grow release's chart values flow from the top-level `assistant:` slice
# (today none exists — the charts.assistant entry is the chart SELECTOR, not
# values) merged with custom-values/grow `assistant:` (the real bitwardenIds).
top = grow.get('assistant')
if isinstance(top, dict):
    merged.update(top)
cv = load('custom-values/grow/prod-values.yaml')
cv_a = cv.get('assistant')
if not isinstance(cv_a, dict):
    print('FAIL: t5 custom-values/grow/prod-values.yaml has no top-level assistant: block — grow would render no real bitwardenIds', file=sys.stderr)
    sys.exit(1)
merged = {**merged, **cv_a}
yaml.safe_dump(merged, open('/tmp/opencode/ha-chart-grow-slice.yaml', 'w'), sort_keys=False)
PY
    if "$helm_bin" template assistant "$COPY" -f /tmp/opencode/ha-chart-grow-slice.yaml --set domain=test.example.com >"$WORK/grow.yaml" 2>"$WORK/grow.err"; then
      if python3 - "$WORK/grow.yaml" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if isinstance(d, dict)]
def bad(msg):
    print(f'FAIL: t5 {msg}', file=sys.stderr)
    sys.exit(1)

raw = open(sys.argv[1]).read()
kinds = {}
for d in docs:
    kinds[d.get('kind')] = kinds.get(d.get('kind'), 0) + 1
if kinds.get('Cluster', 0) != 2:
    bad(f'grow slice rendered {kinds.get("Cluster", 0)} CNPG Clusters, expected 2 (assistant + sensors) — postgres.enabled defaults TRUE so grow keeps its DBs')
if kinds.get('ExternalSecret', 0) < 4:
    bad(f'grow slice rendered {kinds.get("ExternalSecret")} ExternalSecrets, expected >=4 (pg secret + 2 mcp secrets + app creds)')
for forbidden in ('Deployment', 'PersistentVolumeClaim'):
    if forbidden in kinds:
        bad(f'grow slice rendered {forbidden} — the HA container + PVC stay gated off for grow (default OFF)')
if 'OVERRIDE_' in raw:
    bad('the grow-slice render carries an OVERRIDE_* sentinel — grow custom-values supply real UUIDs, nothing may leak')
print('ok: t5: grow slice renders pg (2 Clusters) + secrets, NO Deployment/PVC, no sentinels — the live grow release shape is preserved (C03 AC1)')
PY
      then checks=$((checks + 1)); else fail 't5: the grow-slice render contract is not satisfied (reason printed above)'; fi
    else
      tail -n 30 "$WORK/grow.err" >&2
      fail "t5: helm template of the grow slice failed (stderr $WORK/grow.err)"
    fi
  fi
fi

printf 'PASS: cf-93 C03 ha-chart contract (%d ok)\n' "$checks"
