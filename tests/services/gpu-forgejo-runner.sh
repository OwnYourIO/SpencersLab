#!/usr/bin/env bash
# gpu Forgejo runner instance contract (cf-104 C05): a SECOND runner release,
# on the gpu cluster, dialing out over HTTPS to the INFRA Forgejo
# (https://git.spencerslab.com — plan Q13 answer; gpu has no Forgejo of its
# own). Named after the gpu-coder-sso.sh precedent: one suite per gpu service
# surface.
#
# Leg -> acceptance-criteria map (plan test contract, section C):
#   g1  harness: dependency build of a charts/forgejo-runner copy  plan Commands
#   g2  standalone render of the gpu release (names, replicas, VCTs,
#       labels map == the post-C04 act set)                       C05 AC1
#   g3  the SERVICES file carries the top-level slice with the exact
#       infra URL, and no in-cluster/dead host anywhere            C05 AC2
#   g4  charts: alias entry + trio-exemption comment + no new
#       ingress.subdomains entry                                   C05 AC3
#   g5  custom-values UUID for the runner token, naming the new
#       gpu-forgejo-runner item; the reserved dev item never here   C05 AC4
#   g6  gpu umbrella sentinel sweep at the pinned baseline 1 and a
#       sentinel-free forgejo-runner-gpu values JSON                C05 AC5
#   g7  blast radius: dev runner trio untouched, no gpu Forgejo or
#       SeaweedFS, runner chart untouched beyond C04's swap         C05 AC6
#
# Why the URL is pinned instead of derived: `git.spencerslab.com` is the infra
# instance's canonical DOMAIN/ROOT_URL host and split DNS carries it to the
# lab-side hub; the `forgejo.spencerslab.com` alias exists repo-side but from
# gpu resolves to the public edge, where TLS fails a certificate name
# mismatch (EXPLORE R3) — so the alias is banned, not merely disfavoured. An
# in-cluster URL is dead on gpu: no forgejo service exists there.
#
# Red-first by design: g2-g6 stop the run until C05 lands (g2 also waits on
# C04, since the labels map must be the LFS-capable act set). g7 is a
# green-at-base regression gate.
#
# Harness per tests/services/infra-forgejo.sh:1-30 (helm from HELM_BIN/PATH/
# ~/.local/bin//tmp/opencode, else v3.21.4 downloaded there; renders on
# /tmp/opencode copies, never in the worktree; registry-unreachable renders
# SKIP instead of failing).
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/gpu-forgejo-runner.sh
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # FRICTION seed: helm lives at ~/.local/bin

cd "$(git rev-parse --show-toplevel)"

RUNNER="charts/forgejo-runner"
GPU="services/gpu/prod"
GPU_VALUES="$GPU/values.yaml"
GPU_CV="custom-values/gpu/prod-values.yaml"
APP="forgejo-runner-gpu"

# Q13 answer: the runner serves the infra instance; canonical host, no
# trailing slash.
GPU_URL='https://git.spencerslab.com'
# Dead or wrong targets for a gpu pod (EXPLORE R3, R5): the in-cluster URLs of
# the dev and infra clusters, and the alias whose public path fails TLS.
BANNED='http://dev-forgejo-http http://infra-forgejo-http forgejo.spencerslab.com'

# Measured pre-ticket baseline of `grep -c OVERRIDE_` on the gpu umbrella
# render: the legacy OVERRIDE_VIA_CLUSTER_ANNOTATION trio on one values-JSON
# line. Not zero, and this ticket must not change it (FRICTION 2026-11-03).
GPU_SENT_BASELINE=1

DIFF_BASE="${GPU_RUNNER_DIFF_BASE:-$(git rev-parse --verify main 2>/dev/null || git rev-parse --verify origin/main 2>/dev/null || true)}"

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

# --- helm discovery (infra-forgejo.sh convention) --------------------------
find_helm() {
  local cand
  if [ -n "${HELM_BIN:-}" ] && [ -x "${HELM_BIN}" ]; then
    printf '%s' "$HELM_BIN"
    return 0
  fi
  if command -v helm >/dev/null 2>&1; then
    command -v helm
    return 0
  fi
  if [ -x /home/coder/.local/bin/helm ]; then
    printf '%s' "/home/coder/.local/bin/helm"
    return 0
  fi
  cand=$(find /tmp/opencode -maxdepth 4 -type f -name helm -perm -u+x 2>/dev/null | head -n 1 || true)
  if [ -n "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  return 1
}

download_helm() {
  local version=3.21.4 arch dir tar expected
  command -v curl >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  dir=/tmp/opencode/gpu-forgejo-runner-helm-download
  mkdir -p "$dir"
  tar="$dir/helm-v${version}-linux-${arch}.tar.gz"
  curl -fsSL --max-time 120 -o "$tar" \
    "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz" >/dev/null 2>&1 || return 1
  curl -fsSL --max-time 30 -o "${tar}.sha256sum" "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz.sha256sum" >/dev/null 2>&1 || return 1
  (cd "$dir" && sha256sum -c "$(basename "$tar").sha256sum" >/dev/null 2>&1) || return 1
  tar -xzf "$tar" -C "$dir" || return 1
  expected=$(find "$dir" -type f -name helm -perm -u+x | head -n 1 || true)
  [ -n "$expected" ] || return 1
  printf '%s' "$expected"
}

helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || helm_bin=$(download_helm || true)

WORK=$(mktemp -d /tmp/opencode/gpu-forgejo-runner.XXXXXX)

build_copy() {
  local chart="$1" flagfile="$2"
  local copy="$WORK/$(printf '%s' "$chart" | tr '/' '_')"
  cp -R "$chart"/. "$copy"/
  local log="$copy/dependency-build.log"
  if ! (cd "$copy" && "$helm_bin" dependency build .) >"$log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$log"; then
      : >"$flagfile"
      printf 'skip: g1: helm dependency build could not reach the registry for %s here; the render legs were not run (log kept at %s)\n' "$chart" "$log" >&2
      return 0
    fi
    tail -n 30 "$log" >&2
    printf 'FAIL: g1: helm dependency build failed for %s (log kept at %s)\n' "$chart" "$log" >&2
    exit 1
  fi
  printf '%s' "$copy"
}

# The Application receives the CONTENTS of the top-level <appName>: key, so
# the slice is dumped at the top level (charts/base/templates/appset-charts.yaml).
extract_slice() {
  local src="$1" key="$2" out="$3" leg="$4"
  if ! python3 - "$src" "$key" "$out" "$leg" <<'PY'
import sys, yaml

src, key, out, leg = sys.argv[1:5]
with open(src) as f:
    d = yaml.safe_load(f) or {}
block = d.get(key)
if not isinstance(block, dict):
    print(f'FAIL: {leg}: {src} has no top-level {key}: block to extract — C05 adds it (the appset merges only this key into the release)', file=sys.stderr)
    sys.exit(1)
with open(out, 'w') as f:
    yaml.safe_dump(block, f)
PY
  then
    exit 1
  fi
}

skip_helm=0
runner_copy="" gpuumb_copy="" gpu_render=""

# --- g1: harness ------------------------------------------------------------
if [ -z "$helm_bin" ]; then
  skip "g1: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; the render legs (g2, g6) were not run"
  skip_helm=1
else
  [ -d "$RUNNER" ] || fail "g1: $RUNNER does not exist — nothing to dependency-build"
  runner_copy=$(build_copy "$RUNNER" "$WORK/runner-skip")
  if [ -f "$WORK/runner-skip" ]; then skip_helm=1; fi
  gpuumb_copy=$(build_copy "$GPU" "$WORK/gpu-skip")
  if [ -f "$WORK/gpu-skip" ]; then skip_helm=1; fi

  if [ "$skip_helm" -eq 1 ]; then
    skip "g2, g6: not run (dependency builds not reachable from here)"
  else
    ok "g1: helm dependency build succeeds for $RUNNER and $GPU on copies ($("$helm_bin" version --short 2>/dev/null || echo helm))"

    # --- g2: standalone render of the gpu release (C05 AC1) ------------------
    extract_slice "$GPU_CV" "$APP" "$WORK/runner-gpu-slice.yaml" g2
    gpu_render="$WORK/gpu-render.yaml"
    gpu_err="$WORK/gpu-render.err"
    if ! "$helm_bin" template "$APP" "$runner_copy" \
      -f "$WORK/runner-gpu-slice.yaml" \
      --set "runner.url=$GPU_URL" \
      >"$gpu_render" 2>"$gpu_err"; then
      tail -n 30 "$gpu_err" >&2
      fail "g2: helm template of $RUNNER as release $APP failed (log kept at $gpu_err)"
    fi
    [ -s "$gpu_render" ] || fail "g2: the gpu runner render produced nothing"
    if python3 - "$gpu_render" "$GPU_CV" "$APP" "$WORK/g2-count" <<'PY'
import re, sys, yaml

render, cv_file, release, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# GitHub-parity act set as of C04: node22 moved to the act family, which is
# the only set whose images carry git-lfs (EXPLORE R2b). Asserted here as well
# as in dev-forgejo-runner.sh t2 so a gpu release can never ride an
# LFS-incapable label map.
ACT_LABELS = {
    'ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'ubuntu-24.04:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04',
    'docker:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'node22:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
}

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]

    deps = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'Deployment']
    if deps:
        bad(f'g2: the render contains Deployment(s) {deps} — the runner is a StatefulSet (one pod per registration)')
    for kind in ('ServiceAccount', 'StatefulSet', 'Service', 'ExternalSecret'):
        got = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == kind]
        if len(got) != 1 or got[0] != release:
            bad(f'g2: {kind} names are {got}, expected exactly one named {release!r} (app-template 5.0.1 names single-resource kinds after the release)')
    ok(f'g2: exactly one SA/STS/Service/ExternalSecret, all named {release!r}; no Deployment')

    sts = next(d for d in docs if d.get('kind') == 'StatefulSet')
    spec = sts.get('spec') or {}
    if spec.get('replicas') != 1:
        bad(f'g2: replicas is {spec.get("replicas")!r}, expected 1 (one uuid/token pair maps to one pod)')
    vcts = {(v.get('metadata') or {}).get('name'): (v.get('spec') or {}) for v in (spec.get('volumeClaimTemplates') or [])}
    if set(vcts) != {'data', 'docker-data'}:
        bad(f'g2: volumeClaimTemplates named {sorted(vcts)}, expected exactly [data, docker-data]')
    for name, size in (('data', '2Gi'), ('docker-data', '10Gi')):
        vspec = vcts[name]
        if (vspec.get('resources') or {}).get('requests', {}).get('storage') != size:
            bad(f'g2: VCT {name} requests {(vspec.get("resources") or {}).get("requests", {}).get("storage")!r}, expected {size}')
        if vspec.get('accessModes') != ['ReadWriteOnce']:
            bad(f'g2: VCT {name} accessModes are {vspec.get("accessModes")!r}, expected [ReadWriteOnce]')
        # gpu's default StorageClass is local-path (EXPLORE R1), so the chart
        # default needs no per-cluster override.
        if vspec.get('storageClassName') != 'local-path':
            bad(f'g2: VCT {name} storageClassName is {vspec.get("storageClassName")!r}, expected local-path')
    ok('g2: replicas 1, VCTs data 2Gi + docker-data 10Gi, both RWO local-path (gpu default StorageClass)')

    es = next(d for d in docs if d.get('kind') == 'ExternalSecret')
    data = (((es.get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
    cfg = yaml.safe_load(data.get('config.yaml') or '')
    conns = (((cfg or {}).get('server') or {}).get('connections') or {})
    if set(conns) != {'default'}:
        bad(f'g2: config connections are {sorted(conns)}, expected exactly [default]')
    conn = conns['default']
    if set(conn.get('labels') or []) != ACT_LABELS:
        bad(f'g2: default.labels are {sorted(conn.get("labels") or [])}, expected the post-C04 5-label act set {sorted(ACT_LABELS)} (a gpu release must not register with an LFS-incapable node22)')
    ok('g2: config.yaml labels map equals the post-C04 act set (every label LFS-capable)')

    with open(cv_file) as f:
        cv = yaml.safe_load(f) or {}
    uuid = ((cv.get(release) or {}).get('bitwardenIds') or {}).get('runner-token')
    keys = set()
    def walk(node):
        if isinstance(node, dict):
            if 'remoteRef' in node:
                keys.add((node['remoteRef'] or {}).get('key'))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(es)
    if keys != {uuid}:
        bad(f'g2: ExternalSecret remoteRef keys are {sorted(str(k) for k in keys)}, expected the UUID from {cv_file} ({uuid!r})')
    if not uuid or 'OVERRIDE_' in str(uuid):
        bad(f'g2: {cv_file} {release}.bitwardenIds.runner-token is {uuid!r} — an empty or sentinel id crashloops the daemon ("uuid is empty"), so C05 needs the real UA6 UUID (plan D11 class)')
    ok(f'g2: the ExternalSecret resolves the real runner-token UUID from {cv_file}')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f'g2: the gpu runner render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/g2-count")))
    else
      exit 1
    fi
  fi
fi

# --- g3: the SERVICES file carries the URL slice (C05 AC2) ------------------
# The URL flows ONLY through the top-level slice (appset-charts.yaml merges
# (index .Values $appName)), so a URL buried in the charts: entry, or the chart
# default left standing, is a runner that registers nowhere.
if python3 - "$GPU_VALUES" "${gpu_render:-/dev/null}" $GPU_URL "$BANNED" "$WORK/g3-count" <<'PY'
import re, sys, yaml

gpu_values, render_file, url, banned, count_file = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load(path):
    # REDEFINED anchors are legal YAML (helm/Go accept them; PyYAML raises
    # ComposerError) — services values files use them, so only the value-
    # position markers are rewritten.
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

banned = banned.split()

try:
    sv = load(gpu_values)
    slice_ = sv.get('forgejo-runner-gpu')
    if not isinstance(slice_, dict):
        bad(f'g3: {gpu_values} has no top-level forgejo-runner-gpu: slice — the appset merges only this key into the release, so the runner URL has to sit here (dev precedent: services/dev/prod/values.yaml)')
    got = ((slice_.get('runner') or {}).get('url'))
    if got != url:
        bad(f'g3: the top-level forgejo-runner-gpu slice has runner.url {got!r}, expected exactly {url!r} (Q13 answer: the INFRA instance, canonical host, no trailing slash)')
    ok(f'g3: {gpu_values} carries the top-level slice with runner.url exactly {url}')

    texts = {'gpu services slice': yaml.safe_dump(slice_)}
    raw = open(gpu_values).read()
    entry = [l for l in raw.splitlines() if 'forgejo-runner' in l]
    texts['gpu services file (runner lines)'] = '\n'.join(entry)
    try:
        texts['gpu runner render'] = open(render_file).read()
    except OSError:
        pass
    for label, text in texts.items():
        hits = [b for b in banned if b in text]
        if hits:
            bad(f'g3: {hits} appears in {label} — on gpu an in-cluster URL is dead (no forgejo service there) and the forgejo.spencerslab.com alias resolves to the public edge, where TLS fails a certificate name mismatch (EXPLORE R3)')
    ok('g3: no in-cluster URL and no banned forgejo.spencerslab.com alias in the gpu slice, the runner lines, or the render')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f'g3: the URL checks could not be evaluated ({type(e).__name__}: {e})')
PY
then
  checks=$((checks + $(cat "$WORK/g3-count")))
else
  exit 1
fi

# --- g4: charts: alias entry + trio-exemption comment (C05 AC3) -------------
if python3 - "$GPU_VALUES" "$WORK/g4-count" <<'PY'
import re, sys, yaml

gpu_values, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

KEY = 'forgejo-runner-gpu'

try:
    sv = load(gpu_values)
    entry = (sv.get('charts') or {}).get(KEY)
    if not isinstance(entry, dict):
        bad(f'g4: {gpu_values} has no charts.{KEY} entry — the appset renders one Application per charts: entry, so without it nothing deploys')
    if entry.get('chart') != 'forgejo-runner':
        bad(f'g4: charts.{KEY}.chart is {entry.get("chart")!r}, expected forgejo-runner (aliased entry: one chart, one release per instance)')
    if entry.get('namespace') != 'default':
        bad(f'g4: charts.{KEY}.namespace is {entry.get("namespace")!r}, expected default')
    if str(entry.get('ServerSideApply')) != 'false':
        bad(f'g4: charts.{KEY}.ServerSideApply is {entry.get("ServerSideApply")!r}, expected "false"')
    ok(f'g4: charts.{KEY} exists (chart: forgejo-runner, namespace default, ServerSideApply "false")')

    # The trio is chart entry + ApplicationSet values entry + proxy entry. A
    # runner has no proxy leg, so the reason has to sit next to the entry or
    # the next reader files the missing ingress as an oversight (the same
    # documented posture dev carries for forgejo-runner-dev).
    with open(gpu_values) as f:
        lines = f.read().splitlines()
    charts_idx = next((i for i, l in enumerate(lines) if re.match(r'^charts:\s*$', l)), None)
    if charts_idx is None:
        bad(f'g4: {gpu_values} has no charts: block')
    block_end = len(lines)
    for i in range(charts_idx + 1, len(lines)):
        l = lines[i]
        if l.strip() and not l.lstrip().startswith('#') and not l.startswith((' ', '\t')):
            block_end = i
            break
    m = [i for i in range(charts_idx + 1, block_end)
         if re.match(r'^[ \t]+%s:\s*$' % re.escape(KEY), lines[i])]
    if not m:
        bad(f'g4: {gpu_values} has no {KEY}: entry inside the charts: block')
    lo = m[0]
    j = lo - 1
    while j > charts_idx and (lines[j].lstrip().startswith('#') or not lines[j].strip()):
        j -= 1
    hi_indent = len(lines[lo]) - len(lines[lo].lstrip())
    i = lo + 1
    while i < len(lines):
        l = lines[i]
        if l.strip() and not l.lstrip().startswith('#') and (len(l) - len(l.lstrip())) <= hi_indent:
            break
        i += 1
    comments = [l for l in lines[j + 1:i] if l.strip().startswith('#')]
    blob = ' '.join(c.strip().lstrip('#').strip() for c in comments)
    if not comments:
        bad(f'g4: the charts.{KEY} entry has no comment at all — the deliberately missing proxy leg has to be explained where the entry sits')
    if not re.search(r'ingress|proxy', blob, re.IGNORECASE):
        bad('g4: the charts.forgejo-runner-gpu comment does not mention the ingress/proxy leg it omits')
    if not re.search(r'by design|not an oversight|N/A', blob, re.IGNORECASE):
        bad('g4: the comment does not state the missing proxy leg is N/A by design, not an oversight (the trio-grep readers look for the reason, not the leg)')
    if not re.search(r'client[- ]only|dial(?:s|ing)?[- ]out|outbound', blob, re.IGNORECASE):
        bad('g4: the comment does not give the reason — the runner is a client-only/dial-out service, nothing client-facing points at it')
    if 'forgejo-runner' not in blob:
        bad('g4: the comment does not name the runner app it documents')
    ok('g4: the entry carries the trio-exemption comment (client-only/dial-out, N/A proxy leg by design)')

    subs = (sv.get('ingress') or {}).get('subdomains') or {}
    runner_subs = [k for k in subs
                   if 'runner' in k or 'runner' in str((subs[k] or {}).get('service') or '')]
    if runner_subs:
        bad(f'g4: gpu ingress.subdomains gained runner entry/entries {runner_subs} — a runner takes no ingress; the exemption comment is the documented posture (C05 Tasks)')
    ok('g4: gpu ingress.subdomains carries no runner entry')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f'g4: the trio checks could not be evaluated ({type(e).__name__}: {e})')
PY
then
  checks=$((checks + $(cat "$WORK/g4-count")))
else
  exit 1
fi

# --- g5: the vault slot names the NEW item (C05 AC4) ------------------------
# Q15 answer: gpu gets its own Bitwarden item `gpu-forgejo-runner`; the
# reserved `dev-forgejo-prod-runner` item stays free for the pending infra
# runner relocation, so it must not be pasted onto gpu.
if python3 - "$GPU_CV" "$WORK/g5-count" <<'PY'
import json, re, sys, yaml

gpu_cv, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
KEY = 'forgejo-runner-gpu'

try:
    with open(gpu_cv) as f:
        raw = f.read()
    d = yaml.safe_load(raw) or {}
    slice_ = d.get(KEY)
    if not isinstance(slice_, dict):
        bad(f'g5: {gpu_cv} has no top-level {KEY}: slice — the runner token UUID is only consumed through it')
    bw = slice_.get('bitwardenIds') or {}
    if 'runner-token' not in bw:
        bad(f'g5: {gpu_cv} {KEY}.bitwardenIds has no runner-token slot (the chart ships the sentinel; an unmatched slot renders an empty remoteRef)')
    val = bw['runner-token']
    if not UUID_RE.match(str(val)):
        bad(f'g5: {gpu_cv} {KEY}.bitwardenIds.runner-token is {val!r} — expected the real UA6 UUID. An empty or placeholder id crashloops the daemon ("connection default is invalid: uuid is empty"), so no placeholder is allowed here (plan D11 class)')
    if 'OVERRIDE_' in json.dumps(slice_):
        bad(f'g5: an OVERRIDE_* sentinel survives in the {KEY} slice of {gpu_cv}')
    ok(f'g5: {gpu_cv} {KEY}.bitwardenIds.runner-token is UUID-shaped with no sentinel in the slice')

    lines = raw.splitlines()
    # Scoped to this app's slice: other apps may carry their own runner-token
    # key, and the item name must be documented at THIS slot.
    slice_idx = next((i for i, l in enumerate(lines)
                      if re.match(r'^%s:\s*$' % re.escape(KEY), l)), None)
    if slice_idx is None:
        bad(f'g5: no top-level {KEY}: block found in {gpu_cv}')
    slice_end = next((i for i in range(slice_idx + 1, len(lines))
                      if re.match(r'^[^ \t]', lines[i]) and not lines[i].startswith('#')), len(lines))
    key_idx = next((i for i in range(slice_idx + 1, slice_end)
                    if re.match(r'^[ \t]+runner-token:', lines[i])), None)
    if key_idx is None:
        bad(f'g5: no runner-token key inside the {KEY} block of {gpu_cv} (the slot is contract-pinned by g2/g5 — it must not move or rename)')
    block = []
    i = key_idx - 1
    while i >= slice_idx:
        s = lines[i].strip()
        if s.startswith('#'):
            block.insert(0, s.lstrip('#').strip())
        elif s:
            break
        i -= 1
    blob = ' '.join(block)
    if 'gpu-forgejo-runner' not in blob:
        bad(f'g5: the comment above {gpu_cv} runner-token does not name the Bitwarden item gpu-forgejo-runner (Q15 answer: a dedicated gpu item, one item per concern — the dev precedent documents the item name at the slot)')
    ok('g5: the slot comment names the gpu-forgejo-runner item')

    reserved = raw.count('dev-forgejo-prod-runner')
    if reserved:
        bad(f'g5: the reserved dev-forgejo-prod-runner item appears {reserved}x in {gpu_cv} — it stays free for the infra runner relocation (DECISIONS 2026-10-25, Q15 answer)')
    ok('g5: the reserved dev-forgejo-prod-runner item appears nowhere under custom-values/gpu')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f'g5: the custom-values checks could not be evaluated ({type(e).__name__}: {e})')
PY
then
  checks=$((checks + $(cat "$WORK/g5-count")))
else
  exit 1
fi

# --- g6: gpu umbrella sentinel sweep (C05 AC5) ------------------------------
if [ "$skip_helm" -eq 1 ]; then
  skip "g6: sentinel sweep not run (dependency builds unavailable)"
else
  gpu_umb="$WORK/gpu-umbrella.yaml"
  gpu_umb_err="$WORK/gpu-umbrella.err"
  if ! "$helm_bin" template gpu "$gpuumb_copy" -f "$GPU_CV" \
    --set domain=spencerslab.com --set clusterName=gpu >"$gpu_umb" 2>"$gpu_umb_err"; then
    tail -n 30 "$gpu_umb_err" >&2
    fail "g6: helm template of $GPU failed (log kept at $gpu_umb_err)"
  fi
  if python3 - "$gpu_umb" "$GPU_SENT_BASELINE" "$APP" "$WORK/g6-count" <<'PY'
import json, sys, yaml

render, baseline, app, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    got = sum(1 for line in open(render) if 'OVERRIDE_' in line)
    if got != int(baseline):
        bad(f'g6: the gpu umbrella render has {got} OVERRIDE_ lines, expected the pinned baseline {baseline} (the legacy OVERRIDE_VIA_CLUSTER_ANNOTATION trio on one values-JSON line). The runner follows the current custom-values standard, so this ticket must not move the count; a legitimate baseline move updates the constant in the same change.')
    ok(f'g6: gpu umbrella sentinel sweep unchanged at the pinned baseline ({got} line)')

    found = False
    for d in yaml.safe_load_all(open(render)):
        if not d or d.get('kind') != 'ApplicationSet':
            continue
        for el in d['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']:
            vals = el.get('values')
            if isinstance(vals, dict) and app in vals:
                found = True
                blob = json.dumps(vals[app])
                if 'OVERRIDE_' in blob:
                    bad(f'g6: the {app} Application values JSON carries an OVERRIDE_* sentinel: {blob[:300]} (the chart sentinel must be matched 1:1 by the real UUID in custom-values/gpu)')
    if not found:
        bad(f'g6: no {app} key in the ApplicationSet values blob — the release would render with only the chart defaults')
    ok(f'g6: the {app} Application values JSON is sentinel-free')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f'g6: the sentinel sweep could not be evaluated ({type(e).__name__}: {e})')
PY
  then
    checks=$((checks + $(cat "$WORK/g6-count")))
  else
    exit 1
  fi
fi

# --- g7: blast radius (C05 AC6) --------------------------------------------
# The gpu instance must not disturb the dev runner trio (dev-wiring.sh cites
# its exemption comment), must not stand up a Forgejo or a SeaweedFS on gpu,
# and must not fork the shared runner chart — C04 owns that chart and its only
# edit is the one labels line, which shows as exactly two docker:// lines.
if [ -z "$DIFF_BASE" ]; then
  skip "g7: no main/origin/main ref to diff against; the blast-radius leg was not run (set GPU_RUNNER_DIFF_BASE)"
else
  if python3 - "$DIFF_BASE" "$GPU_VALUES" "$WORK/g7-count" <<'PY'
import re, subprocess, sys

base, gpu_values, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def git(*args):
    return subprocess.run(('git',) + args, capture_output=True, text=True).stdout

try:
    touched = re.findall(r'^[+-].*forgejo-runner', git('diff', base, '--', 'services/dev', 'custom-values/dev'), re.M)
    if touched:
        bad(f'g7: the dev runner surface changed: {touched[:4]} — dev keeps its own runner and its trio-exemption comment (dev-wiring.sh cites it); C05 is gpu-only')
    ok('g7: services/dev and custom-values/dev gained no forgejo-runner line (dev trio + comments byte-untouched)')

    moved = git('diff', '--name-only', base, '--', 'charts/forgejo-runner/values.yaml').split()
    if moved:
        bad(f'g7: {moved} changed — the runner chart values are renovate-tracked pins and stay untouched')
    imgs = re.findall(r'^[+-].*docker://', git('diff', base, '--', 'charts/forgejo-runner'), re.M)
    if len(imgs) > 2:
        bad(f'g7: {len(imgs)} docker:// lines changed under charts/forgejo-runner ({imgs[:6]}) — C04 owns that chart and its change is one labels line in and one out; a gpu-specific fork of the shared chart is the rejected shape')
    ok(f'g7: charts/forgejo-runner diff carries {len(imgs)} docker:// lines at most 2 (only C04 labels swap), and no values.yaml change')

    import yaml as _yaml
    lines = []
    with open(gpu_values) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    sv = _yaml.safe_load(''.join(lines)) or {}
    charts = sv.get('charts') or {}
    for forbidden in ('forgejo', 'seaweedfs'):
        if forbidden in charts:
            bad(f'g7: gpu charts gained a {forbidden} entry — gpu gets a runner, not a Forgejo or a gateway (C05 Files-in-scope)')
    ok('g7: gpu still has no forgejo and no seaweedfs chart entry')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f'g7: the blast-radius checks could not be evaluated ({type(e).__name__}: {e})')
PY
  then
    checks=$((checks + $(cat "$WORK/g7-count")))
  else
    exit 1
  fi
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: gpu-forgejo-runner checks (%d ok)\n' "$checks"
