#!/usr/bin/env bash
# C04 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): brand-new
# charts/mosquitto — app-template 5.0.1 on the upstream eclipse-mosquitto
# image (the bitnami catalog is dead, RESEARCH C), in-cluster ClusterIP 1883
# only, ConfigMap-driven mosquitto.conf (allow_anonymous + listener are
# LOAD-BEARING: mosquitto 2.x refuses remote clients without them), emptyDir
# data/log, secret-free by construction.
#
# Contract source: chunks/C04.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC2+AC3+AC5] t3[AC4] t4[AC1].
#
# OVERRIDE_ exception pinned for t2 (per the chunk: "the documented domain
# exception, if any"): there is NONE — the `domain: OVERRIDE_VIA_APPSET`
# value must render UNUSED (nothing consumes it), so a plain render with zero
# --set must contain no OVERRIDE_ string at all. If a future dev wires domain
# into a template, AC2 demands the value be dropped from values.yaml instead.
#
# Renders run on a COPY under /tmp/opencode after `helm dependency update`
# (charts/**/charts is gitignored, Chart.lock committed). Registry-unreachable
# skips the render legs LOUD (skip lines on stderr); the static legs always
# run. PATH export first — FRICTION seed.
#
# Usage:
#   bash tests/multi-repo/mosquitto-chart.sh          # t1..t4
#   bash tests/multi-repo/mosquitto-chart.sh t2 t4    # subset
# Env: HELM_BIN, CHART (default charts/mosquitto), MOSQ_WORKDIR for logs.
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # helm lives here — FRICTION seed

cd "$(git rev-parse --show-toplevel)"

CHART="${CHART:-charts/mosquitto}"
IMAGE_REPO="docker.io/library/eclipse-mosquitto"
IMAGE_TAG="2.0.22"

checks=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
skip() { printf 'skip: %s\n' "$1" >&2; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-4]$ ]] || fail "unknown test id '$a' (expected t1..t4)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

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
[ -n "$helm_bin" ] || fail "mosquitto-chart: no helm binary — silent skip is the documented FRICTION hazard"

WORK=$(mktemp -d "${MOSQ_WORKDIR:-/tmp/opencode/mosquitto-chart}.XXXXXX")

# Red-before-C04 by design: a missing chart directory fails here with the
# reason, never a vacuous pass (dev-forgejo-runner.sh precedent).
[ -d "$CHART" ] || fail "t1: $CHART does not exist — the brand-new chart (Chart.yaml/values.yaml/templates/configmap) has not been created yet (C04 red at the base)"

skip_render=0
COPY="$WORK/mosquitto"
mkdir -p "$COPY"
cp -R "$CHART"/. "$COPY"/
dep_log="$WORK/dependency-update.log"
if ! (cd "$COPY" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
  if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|failed to download|failed to fetch|could not download' "$dep_log"; then
    skip_render=1
    skip "helm dependency update could not reach the registry (log $dep_log): t1/t3 + t4's lint leg skip LOUD; t2 statics still run"
  else
    tail -n 30 "$dep_log" >&2
    fail "helm dependency update failed for $CHART — not a network skip (log $dep_log)"
  fi
fi

RENDER="$WORK/render.yaml"
if [ "$skip_render" -eq 0 ]; then
  if ! "$helm_bin" template mosquitto "$COPY" >"$RENDER" 2>"$RENDER.err"; then
    tail -n 30 "$RENDER.err" >&2
    fail "helm template mosquitto $COPY failed (stderr kept at $RENDER.err)"
  fi
  [ -s "$RENDER" ] || fail "helm template of $CHART rendered nothing"
fi

# --- t1: render shape (C04 AC1) ------------------------------------------------
if want t1; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t1: render assertions not run (dependency registry unreachable)"
  else
    if python3 - "$RENDER" "$IMAGE_REPO" "$IMAGE_TAG" <<'PY'
import sys, yaml

render_f, repo, tag = sys.argv[1:4]
def bad(msg):
    print(f'FAIL: t1 {msg}', file=sys.stderr)
    sys.exit(1)

docs = [d for d in yaml.safe_load_all(open(render_f)) if isinstance(d, dict)]
kinds = {}
for d in docs:
    kinds[d.get('kind')] = kinds.get(d.get('kind'), 0) + 1
for need in ('ConfigMap', 'Service'):
    if kinds.get(need) != 1:
        bad(f'expected exactly one {need}, render has {kinds.get(need)} (kinds: {sorted(kinds)})')
workloads = kinds.get('Deployment', 0) + kinds.get('StatefulSet', 0)
if workloads != 1:
    bad(f'expected exactly one Deployment/StatefulSet (app-template default is Deployment), got {sorted(kinds)}')
if kinds.get('Ingress'):
    bad('an Ingress rendered — the dev broker is ClusterIP-only, no ingress in the chart (chunk Tasks, OQ-C2)')

wl = next(d for d in docs if d.get('kind') in ('Deployment', 'StatefulSet'))
pod = wl['spec']['template']['spec']
cons = pod.get('containers') or []
c = next((x for x in cons if repo in (x.get('image') or '')), None)
if c is None or c['image'] != f'{repo}:{tag}':
    bad(f'container image is {c and c["image"]!r}, expected exactly {repo}:{tag}')

svc = next(d for d in docs if d.get('kind') == 'Service')
if (svc.get('spec') or {}).get('type') != 'ClusterIP':
    bad(f'Service type is {svc["spec"].get("type")!r}, expected ClusterIP')
ports = (svc.get('spec') or {}).get('ports') or []
mqtt = [p for p in ports if p.get('port') == 1883]
if not mqtt:
    bad(f'Service ports {ports} lack 1883')
if mqtt[0].get('name') != 'mqtt':
    bad(f'1883 port is named {mqtt[0].get("name")!r}, expected mqtt (the named-port contract)')
if any(p.get('port') == 9001 for p in ports):
    bad('websockets 9001 is ENABLED — the chunk pins it as a comment placeholder only')

mounts = {(m.get('mountPath'), m.get('subPath')) for m in c.get('volumeMounts') or []}
if ('/mosquitto/config/mosquitto.conf', 'mosquitto.conf') not in mounts and not any(mp == '/mosquitto/config/mosquitto.conf' for mp, _ in mounts):
    bad(f'the config is not mounted at /mosquitto/config/mosquitto.conf via subPath (mounts: {sorted(mounts)}) — mosquitto 2.x refuses remote connections without the ConfigMap listener; the mount is load-bearing, not decoration')
vols = {v.get('name'): v for v in pod.get('volumes') or []}
for path in ('/mosquitto/data', '/mosquitto/log'):
    hit = [m for m in c.get('volumeMounts') or [] if m.get('mountPath') == path]
    if not hit:
        bad(f'no mount at {path} (emptyDir data/log volumes, chunk Tasks)')
    v = vols.get(hit[0].get('name')) or {}
    if 'emptyDir' not in v:
        bad(f'volume {hit[0].get("name")} for {path} is not an emptyDir ({sorted(v)}) — dev-only broker, no persistence (DECISIONS OQ-C2)')
cfg_vol = [v for v in vols.values() if 'configMap' in v]
if not cfg_vol:
    bad('no configMap-backed volume — mosquitto.conf must ride the ConfigMap (t1 mount leg proves consumption)')

cm = next(d for d in docs if d.get('kind') == 'ConfigMap')
conf = None
for k, v in (cm.get('data') or {}).items():
    if 'mosquitto' in k:
        conf = v
if conf is None:
    bad(f'ConfigMap {cm["metadata"]["name"]} data has no mosquitto.conf key (keys: {sorted((cm.get("data") or {}))})')
for needle in ('listener 1883', 'allow_anonymous true', 'persistence false'):
    if needle not in conf:
        bad(f'mosquitto.conf lacks {needle!r} — the dev envelope is anonymous+unexposed WITH the listener line that makes 2.x bind at all')
print('ok: t1 — kinds/ports/emptyDir/subPath-ConfigMap-mount/render: one ConfigMap + ClusterIP mqtt:1883 + one Deployment + data/log emptyDirs + listener/allow_anonymous/persistence-false conf (C04 AC1)')
PY
    then checks=$((checks + 1)); else fail 't1: the render-shape contract is not satisfied (reason printed above)'; fi
  fi
fi

# --- t2: version law, pin literals, secret-free (C04 AC2+AC3+AC5) ------------
if want t2; then
  grep -qE '^version: 1\.0\.0$' "$CHART/Chart.yaml" \
    || fail "t2: $CHART/Chart.yaml version is not exactly 1.0.0 — the brand-new-chart exception of the version law (release.yaml bumps later, AC2)"
  grep -q 'app-template' "$CHART/Chart.yaml" && grep -q '5.0.1' "$CHART/Chart.yaml" \
    || fail 't2: Chart.yaml lacks the app-template 5.0.1 dependency'
  ok "t2: Chart.yaml — version 1.0.0 + app-template 5.0.1 (new-chart law)"

  grep -q 'eclipse-mosquitto' "$CHART/values.yaml" || fail "t2: values.yaml lacks the eclipse-mosquitto image"
  grep -q "$IMAGE_TAG" "$CHART/values.yaml" || fail "t2: values.yaml lacks the pinned $IMAGE_TAG tag (live Docker Hub probe 2026-10-31; AC3)"
  grep -qiE ':\s*latest|tag:\s*stable' "$CHART/values.yaml" && fail 't2: values.yaml carries an unpinned latest/stable tag' || true
  ok "t2: image literals — eclipse-mosquitto:$IMAGE_TAG pinned (C04 AC3)"

  if grep -Ril 'externalsecret' "$CHART" | grep .; then
    fail "t2: ExternalSecret artifacts inside $CHART — the broker is secret-free, no ExternalSecret template (AC5)"
  fi
  if grep -Ri 'bitwarden' "$CHART" | grep .; then
    fail "t2: bitwardenIds references inside $CHART — no secrets, therefore no bitwardenIds (OQ-C2/AC5)"
  fi
  if grep -rn 'mosquitto' custom-values/ 2>/dev/null | grep .; then
    fail "t2: a custom-values entry for mosquitto exists — services without secrets get NO custom-values entry (helm-chart-creation law, AC5)"
  fi
  ok "t2: zero secret/ExternalSecret/custom-values artifacts (C04 AC5)"

  if [ "$skip_render" -eq 1 ]; then
    skip "t2: plain-render OVERRIDE_ leg not run (registry unreachable)"
  else
    # No documented exception: domain must render UNUSED (header pins this).
    if grep -q 'OVERRIDE_' "$RENDER"; then
      grep -n 'OVERRIDE_' "$RENDER" | head >&2
      fail 't2: OVERRIDE_* string survived the plain render — the domain passthrough must stay unconsumed or be dropped (AC2)'
    fi
    ok "t2: plain render contains no OVERRIDE_ string (zero documented exceptions — pinned in the suite header)"
  fi
fi

# --- t3: container securityContext (C04 AC4) ----------------------------------
if want t3; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t3: rendered sc asserts not run (registry unreachable)"
  else
    if python3 - "$RENDER" "$IMAGE_REPO" <<'PY'
import sys, yaml

render_f, repo = sys.argv[1:3]
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)

docs = [d for d in yaml.safe_load_all(open(render_f)) if isinstance(d, dict)]
wl = next(d for d in docs if d.get('kind') in ('Deployment', 'StatefulSet'))
c = next(x for x in (wl['spec']['template']['spec'].get('containers') or []) if repo in (x.get('image') or ''))
sc = c.get('securityContext') or {}
if (sc.get('capabilities') or {}).get('drop') != ['ALL']:
    bad(f'container capabilities.drop is {(sc.get("capabilities") or {}).get("drop")!r}, expected [ALL] (AC4)')
if sc.get('allowPrivilegeEscalation') is not False:
    bad('container allowPrivilegeEscalation is not false (AC4)')
print('ok: t3 — rendered container: drop-ALL capabilities + allowPrivilegeEscalation false (C04 AC4)')
PY
    then checks=$((checks + 1)); else fail 't3: the securityContext contract is not satisfied (reason printed above)'; fi
  fi
fi

# --- t4: lint + dependency list (C04 AC1) --------------------------------------
if want t4; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t4: lint/dependency-list legs not run (registry unreachable)"
  else
    lint_log="$WORK/lint.log"
    (cd "$COPY" && "$helm_bin" lint .) >"$lint_log" 2>&1 || { tail -n 30 "$lint_log" >&2; fail "t4: helm lint failed for $CHART (log $lint_log)"; }
    ok "t4: helm lint passes ($("$helm_bin" version --short 2>/dev/null || echo helm))"
    deps="$WORK/dep-list.txt"
    "$helm_bin" dependency list "$COPY" >"$deps" 2>&1 || fail 't4: helm dependency list failed'
    grep -E '^app-template\s+5\.0\.1\s+https://bjw-s-labs\.github\.io/helm-charts/\s+READY' "$deps" >/dev/null \
      || { cat "$deps" >&2; fail 't4: app-template 5.0.1 row not READY (Chart.lock missing/stale)'; }
    ok "t4: helm dependency list — app-template 5.0.1 READY"
  fi
  [ -f "$CHART/Chart.lock" ] || fail "t4: $CHART/Chart.lock not committed (dependency-update output lands in git, AC1 hygiene)"
  ok "t4: Chart.lock committed"
fi

printf 'PASS: cf-93 C04 mosquitto-chart contract (%d ok)\n' "$checks"
