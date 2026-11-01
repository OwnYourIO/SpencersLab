#!/usr/bin/env bash
# C04 contract (ticket 2026-10-cf-11-feat-immich-hugo-pipeline) for
# charts/forgejo-secret-seed — the gpu-cluster Bitwarden -> Forgejo repo
# secret seeder: ONE mixed-store ExternalSecret (bitwarden-login +
# bitwarden-fields per the C04 table) and a daily idempotent CronJob that
# PUTs the five repo secrets with curl (no jq). GPU sentinel flavor:
# OVERRIDE_VIA_CLUSTER_ANNOTATION rides the ArgoCD cluster annotation
# (services.gpu.bitwardenIds) — a USER ACTION per key, NOT a custom-values
# file (DECISIONS R9; the gpu values header records the mechanism).
#
# AC trace (chunks/C04.md): t1[AC2 ExternalSecret table] t2[AC3 CronJob
# shape] t3[AC4 seed script] t4[AC5 gpu umbrella + sentinel sweep + user
# action docs] t5[AC2 mixed-store render proof].
#
# The chart is rendered from a /tmp copy after helm dependency build there
# (repo convention: charts/**/charts is gitignored, Chart.lock committed);
# the worktree is never written. Helm discovery + the v3.21.4 download
# fallback follow tests/services/dev-forgejo-runner.sh; registry-unreachable
# renders SKIP, static legs still run.
#
# Red-first: a missing charts/forgejo-secret-seed is a FAIL (the chunk is
# not implemented), never a skip.
#
# Run from the repo root:
#   bash tests/services/gpu-forgejo-secret-seed.sh
#   bash tests/services/gpu-forgejo-secret-seed.sh t3      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SEED="charts/forgejo-secret-seed"
GPU="services/gpu/prod"
GPU_VALUES="$GPU/values.yaml"

TEST_UUID_IMMICH="00000000-0000-0000-0000-0000000000a1"
TEST_UUID_NETLIFY="00000000-0000-0000-0000-0000000000a2"
TEST_UUID_PAT="00000000-0000-0000-0000-0000000000a3"

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
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected t1..t5)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -d "$SEED" ] ||
  fail "$SEED does not exist (the C04 chart has not been created — nothing to render or lint)"

find_helm() {
  # Each branch prints exactly one path AND returns 0 — never concatenate
  # two candidates (dev-forgejo-runner.sh F01 review finding 1).
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
  dir=/tmp/opencode/gpu-forgejo-secret-seed-helm-download
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

WORK=$(mktemp -d /tmp/opencode/gpu-forgejo-secret-seed.XXXXXX)
seed_copy="$WORK/forgejo-secret-seed-copy"
cp -R "$SEED"/. "$seed_copy"/

skip_helm=0
helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || helm_bin=$(download_helm || true)
if [ -z "$helm_bin" ]; then
  skip "no helm binary found or downloadable; the render legs (t1/t2/t5, t4 umbrella) were not run"
  skip_helm=1
else
  dep_log="$WORK/dependency-build.log"
  if ! (cd "$seed_copy" && "$helm_bin" dependency build .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "helm dependency build could not reach the registry (t1/t2/t5, t4 umbrella not run; log kept at $dep_log)"
      skip_helm=1
    else
      tail -n 30 "$dep_log" >&2
      fail "helm dependency build failed for $SEED (log kept at $dep_log)"
    fi
  fi
fi

if [ "$skip_helm" -eq 0 ]; then
  [ -f "$SEED/Chart.lock" ] ||
    fail "t1: $SEED/Chart.lock is not committed (new-chart rule: dependency built and locked — C04 chart shape)"
  [ "$(grep -m1 -E '^version:' "$SEED/Chart.yaml" | sed -E 's/^version:[[:space:]]*//')" = "1.0.0" ] ||
    fail "t1: $SEED/Chart.yaml version must be 1.0.0 (brand-new-chart rule — release.yaml bumps patch on merge, never by hand)"
  lint_log="$WORK/lint.log"
  if ! (cd "$seed_copy" && "$helm_bin" lint .) >"$lint_log" 2>&1; then
    tail -n 30 "$lint_log" >&2
    fail "t1: helm lint failed for $SEED (log kept at $lint_log)"
  fi
  ok "t1: Chart.lock committed, Chart.yaml version 1.0.0, helm lint green"
fi

render="$WORK/seed-render.yaml"
if [ "$skip_helm" -eq 0 ]; then
  if ! "$helm_bin" template forgejo-secret-seed "$seed_copy" \
      --set "bitwardenIds.immich-api-key=$TEST_UUID_IMMICH" \
      --set "bitwardenIds.netlify=$TEST_UUID_NETLIFY" \
      --set "bitwardenIds.forgejo-pat=$TEST_UUID_PAT" \
      --debug \
    >"$render" 2>"$WORK/render.err"; then
    tail -n 30 "$WORK/render.err" >&2
    fail "chart template of $SEED with the three sentinel --sets failed (log kept at $WORK/render.err)"
  fi
  [ -s "$render" ] || fail "the seed chart rendered nothing"
fi

# --- t1: rendered ExternalSecret matches the C04 secrets table ---------------
if want t1 && [ "$skip_helm" -eq 0 ]; then
  if python3 - "$render" "$TEST_UUID_IMMICH" "$TEST_UUID_NETLIFY" "$TEST_UUID_PAT" "$WORK/t1-count" <<'PY'
import sys, yaml

render, u_imm, u_net, u_pat, count_file = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# C04 "Secrets seeded" table: secretKey -> (store, property, bitwardenIds key).
TABLE = {
    'immich_api_key': ('bitwarden-login', 'password', u_imm),
    'netlify_auth_token': ('bitwarden-login', 'password', u_net),
    'netlify_site_id': ('bitwarden-fields', 'site_id_com', u_net),
    'netlify_site_id_farm': ('bitwarden-fields', 'site_id_farm', u_net),
    'forgejo_pat': ('bitwarden-login', 'password', u_pat),
}

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    es = [d for d in docs if d.get('kind') == 'ExternalSecret']
    if len(es) != 1:
        bad(f't1: {len(es)} ExternalSecrets rendered, expected exactly ONE (chart shape: a single mixed-store seeder object)')
    es = es[0]
    top_store = ((es.get('spec') or {}).get('secretStoreRef') or {}).get('name')
    got = {}
    for entry in (es.get('spec') or {}).get('data') or []:
        key = entry.get('secretKey')
        rr = entry.get('remoteRef') or {}
        store = ((entry.get('sourceRef') or {}).get('storeRef') or {}).get('name') or top_store
        got[key] = (store, rr.get('property'), rr.get('key'))
    if set(got) != set(TABLE):
        bad(f't1: secretKeys are {sorted(got)}, expected exactly {sorted(TABLE)}')
    for key, (want_store, want_prop, want_uuid) in TABLE.items():
        store, prop, uuid = got[key]
        if store != want_store:
            bad(f't1: {key}: store is {store!r}, expected {want_store!r} (C04 table row)')
        if prop != want_prop:
            bad(f't1: {key}: property is {prop!r}, expected {want_prop!r} (C04 table row)')
        if uuid != want_uuid:
            bad(f't1: {key}: remoteRef key is {uuid!r}, expected the resolved bitwardenIds uuid {want_uuid!r} (the sentinel must flow through --set/annotation, never a hardcoded id)')
    ok('t1: all five mappings match the C04 table name-for-name, store-for-store, property-for-property')

    tmpl = (((es.get('spec') or {}).get('target') or {}).get('template') or {})
    if tmpl.get('engineVersion') != 'v2':
        bad(f't1: ExternalSecret target template engineVersion is {tmpl.get("engineVersion")!r}, expected v2 (chart shape)')
    tname = ((es.get('spec') or {}).get('target') or {}).get('name')
    if not tname:
        bad('t1: the ExternalSecret has no target Secret name')
    for secret_name, key in (('IMMICH_API_KEY', 'immich_api_key'), ('NETLIFY_AUTH_TOKEN', 'netlify_auth_token'),
                             ('NETLIFY_SITE_ID', 'netlify_site_id'), ('NETLIFY_SITE_ID_FARM', 'netlify_site_id_farm'),
                             ('FORGEJO_SYNC_PAT', 'forgejo_pat')):
        if key not in (tmpl.get('data') or {}):
            bad(f't1: the target template has no {key} key for the {secret_name} repo secret (script expectations, AC2)')
    ok('t1: engineVersion v2 + the five target keys the seed script mounts')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't1: the seed render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t1-count")))
  else
    exit 1
  fi
fi

# --- t2: CronJob shape --------------------------------------------------------
if want t2 && [ "$skip_helm" -eq 0 ]; then
  if python3 - "$render" "$WORK/t2-count" <<'PY'
import re, sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    cjs = [d for d in docs if d.get('kind') == 'CronJob']
    if len(cjs) != 1:
        bad(f't2: {len(cjs)} CronJobs rendered, expected exactly 1')
    cj = cjs[0]
    spec = cj.get('spec') or {}
    sched = str(spec.get('schedule') or '')
    # Daily = fixed minute+hour with wildcard dom/month/dow (or @daily); the
    # exact time is dev's choice, the DAILY cadence is the contract (§
    # controller: daily schedule).
    if sched != '@daily' and not re.fullmatch(r'\d+ \d+ \* \* \*', sched):
        bad(f't2: schedule {sched!r} is not a daily cron (expected ' + "'M H * * *'" + ' or @daily)')
    if spec.get('concurrencyPolicy') != 'Forbid':
        bad(f't2: concurrencyPolicy is {spec.get("concurrencyPolicy")!r}, expected Forbid (overlapping PUTs of the same secrets are pure churn)')
    jt = spec.get('jobTemplate') or {}
    jt_spec = (jt.get('spec') or {})
    # ttlSecondsAfterFinished is a JOB-level field (k8s API), so it lives
    # under jobTemplate.spec when set through app-template's cronjob block.
    if jt_spec.get('ttlSecondsAfterFinished') is None and spec.get('ttlSecondsAfterFinished') is None:
        bad('t2: ttlSecondsAfterFinished missing (chart shape: finished jobs are collected)')
    pod = ((((jt.get('spec') or {}).get('template') or {}).get('spec')) or {})
    if pod.get('restartPolicy') != 'OnFailure':
        bad(f't2: pod restartPolicy is {pod.get("restartPolicy")!r}, expected OnFailure (a failed seed must be visible in job status)')
    containers = (pod.get('containers') or []) + (pod.get('initContainers') or [])
    seed_c = next((c for c in containers if 'curl' in str(c.get('image'))), None)
    if seed_c is None:
        bad('t2: no curl-image container found')
    img = str(seed_c.get('image'))
    if img == 'docker.io/curlimages/curl:latest' or not re.search(r'curlimages/curl:[v0-9][0-9a-zA-Z._-]*$', img):
        bad(f't2: curl image {img!r} is not a pinned concrete tag (renovate docker datasource contract)')
    podsc = pod.get('securityContext') or {}
    drops = ((podsc.get('capabilities') or {}).get('drop') or [])
    if not any(str(d).upper() == 'ALL' for d in drops):
        for c in containers:
            if not any(str(d).upper() == 'ALL' for d in ((c.get('securityContext') or {}).get('capabilities') or {}).get('drop', [])):
                bad('t2: drop-ALL security context missing (chart convention, C04 §shape)')
                break
    mounts = seed_c.get('volumeMounts') or []
    if not any((m or {}).get('mountPath', '').startswith('/secrets') for m in mounts):
        bad(f't2: the seed container mounts no volume at /secrets — secrets must arrive as files, never inline values')
    if not (seed_c.get('command') or seed_c.get('args')):
        bad('t2: the seed container carries no command — the ConfigMap script must be executed')
    ok(f't2: CronJob {sched} daily, Forbid, ttl set, OnFailure, pinned {img}, /secrets mounted, drop-ALL')
    inline = re.findall(r'(?i)Bearer [A-Za-z0-9+/=_-]{12,}|token [A-Za-z0-9+/=_-]{12,}', open(render).read())
    if inline:
        bad(f't2: an inline credential-shaped literal appears in the render: {inline[:2]} (AC3: no secret values inline anywhere)')
    ok('t2: no inline secret values in the render')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't2: the CronJob could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t2-count")))
  else
    exit 1
  fi
  grep -q 'reloader.stakater.com' "$render" ||
    fail "t2: no reloader.stakater.com annotation in the render (C04 §chart shape: 'Also reloader annotation')"
  ok "t2: reloader annotation present"
fi

# --- t3: the seed script itself ----------------------------------------------
if want t3 && [ "$skip_helm" -eq 0 ]; then
  if python3 - "$render" "$WORK/t3-count" <<'PY'
import re, sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    cms = [d for d in docs if d.get('kind') == 'ConfigMap']
    script_text = ''
    for cm in cms:
        for k, v in (cm.get('data') or {}).items():
            if isinstance(v, str) and 'curl' in v and 'secrets' in v:
                script_text = v
    if not script_text:
        bad(f't3: no ConfigMap carries the seed script (looked in {[(cm.get("metadata") or {}).get("name") for cm in cms]})')

    names = ['IMMICH_API_KEY', 'NETLIFY_AUTH_TOKEN', 'NETLIFY_SITE_ID', 'NETLIFY_SITE_ID_FARM', 'FORGEJO_SYNC_PAT']
    # "5 PUTs" read semantically: scripts legitimately loop a put() helper
    # over the names, so the pinned shape is: every name present, the
    # actions/secrets endpoint path present, and PUT construction present.
    if '/actions/secrets' not in script_text:
        bad('t3: no /actions/secrets endpoint path in the script (AC4 endpoint pattern)')
    for name in names:
        if not re.search(name + r'\b', script_text):
            bad(f't3: the script never references the {name} repo secret (AC4: all 5 names)')
    if not re.search(r'-X +PUT|curl[^#\n]*\bput\b', script_text):
        bad('t3: no PUT construction found (-X PUT / curl + put helper)')
    if not re.search(r"/api/v1/repos/", script_text):
        bad('t3: the PUT URLs do not use the /api/v1/repos/{owner}/{repo}/ path (AC4 endpoint pattern)')
    if 'token $(cat /secrets/forgejo_pat)' not in script_text.replace('`', '$') and '/secrets/forgejo_pat' not in script_text:
        bad('t3: Authorization is not built from the mounted /secrets/forgejo_pat file')
    if not re.search(r"Authorization:\s+token", script_text):
        bad('t3: no "Authorization: token" header construction')
    if not re.search(r'\{"data"', script_text):
        bad('t3: bodies are not static {"data":...} JSON (Forgejo secret PUT shape, AC4)')
    if re.search(r'\bjq\b', script_text):
        bad('t3: the script shells out to jq — the chart pins a jq-free printf construction')
    if not (re.search(r'set -e', script_text) or re.search(r'curl[^|;&]*\s-f', script_text)):
        bad('t3: no fail-loud discipline (set -e or curl -f): a failed PUT must exit non-zero (AC3/§controller)')
    ok('t3: five PUTs to the pinned endpoint path, PAT from the mounted file, jq-free {"data":...} bodies, fail-loud')

    # owner/repo must flow from seed.* VALUES, not be baked literals in the
    # script body — the chart renders the ConfigMap from values, so the
    # rendered script shows the BG pair; assert the pair appears AND the
    # script itself builds URLs from a variable/prefix (one edit point).
    if 'CuratedForest' not in script_text:
        bad('t3: the rendered script lost the seed.repoOwner/repoName pair (the values, not sentinels — C04 §chart shape)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the seed script could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t3-count")))
  else
    exit 1
  fi
fi

# --- t4: gpu umbrella wiring + sentinel bookkeeping ---------------------------
if want t4; then
  if python3 - "$GPU_VALUES" "$SEED/values.yaml" "$WORK/t4-count" <<'PY'
import re, sys, yaml

gpu_values, seed_vals, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

SENTINEL = 'OVERRIDE_VIA_CLUSTER_ANNOTATION'
KEYS = ('immich-api-key', 'netlify', 'forgejo-pat')

def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    cv = load(seed_vals)
    bw = cv.get('bitwardenIds') or {}
    for key in KEYS:
        if bw.get(key) != SENTINEL:
            bad(f't4: {seed_vals} bitwardenIds.{key} is {bw.get(key)!r}, expected {SENTINEL} (the gpu sentinel flavor — uuids resolve from the ArgoCD cluster annotation, not custom-values files)')
    ok(f't4: the chart declares exactly the {SENTINEL} flavor for {list(KEYS)}')

    sv = load(gpu_values)
    charts = sv.get('charts') or {}
    if 'forgejo-secret-seed' not in charts:
        bad(f't4: {gpu_values} has no charts.forgejo-secret-seed entry — the app would never be created')
    e = charts['forgejo-secret-seed']
    if e.get('namespace') != 'default':
        bad(f't4: charts.forgejo-secret-seed.namespace is {e.get("namespace")!r}, expected default')
    if str(e.get('ServerSideApply')) != 'false':
        bad(f't4: charts.forgejo-secret-seed.ServerSideApply is {e.get("ServerSideApply")!r}, expected "false"')
    gpu_bw = sv.get('bitwardenIds') or {}
    for key in KEYS:
        if gpu_bw.get(key) != SENTINEL:
            bad(f't4: {gpu_values} global bitwardenIds.{key} is {gpu_bw.get(key)!r}, expected {SENTINEL} — the cluster-annotation mechanism resolves exactly these keys')
    ok('t4: gpu service values carry the charts entry + the three cluster-annotation sentinel keys')

    # 1:1 user-action documentation (AC5/plan user-action 5): every sentinel
    # key must be documented against the services.gpu.bitwardenIds
    # annotation, or the must-fill silently strands a broken seeder.
    with open(gpu_values) as f:
        gtxt = f.read()
    if 'services.gpu.bitwardenIds' not in gtxt:
        bad('t4: the gpu values never name the services.gpu.bitwardenIds cluster annotation the sentinels resolve from — the per-key user action is undocumented')
    for key in KEYS:
        m = re.search(r'^[ \t]*' + re.escape(key) + r':.*$', gtxt, re.M)
        if not m:
            bad(f't4: {gpu_values}: sentinel line for {key} not found')
        start = gtxt.rfind('\n', 0, max(0, m.start() - 300))
        ctx = gtxt[start:m.start()]
        if not re.search(r'annotation|cluster|bitwarden', ctx, re.IGNORECASE):
            bad(f't4: {key}: no comment documenting the gpu cluster-annotation entry (user action) within the surrounding block')
    ok('t4: each sentinel key is comment-documented against the gpu cluster annotation (user-action 5)')

    subs = ((sv.get('ingress') or {}).get('subdomains') or {})
    if 'forgejo-secret-seed' in subs:
        bad('t4: ingress.subdomains carries a forgejo-secret-seed entry — the seeder is internal/client-only (AC5)')
    ok('t4: no ingress entry for the seeder (client-only asserted)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't4: the gpu wiring checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t4-count")))
  else
    exit 1
  fi

  # The umbrella render leg (same --set ladder discipline as
  # gpu-coder-sso.sh g-sso-3): every sentinel in the service values must be
  # --set-resolved, or the sweep would flag LEGACY sentinels this ticket
  # does not own. Keys are read from the file so the ladder cannot drift.
  if [ "$skip_helm" -eq 0 ]; then
    sets=()
    while IFS= read -r key; do
      sets+=("--set" "bitwardenIds.$key=00000000-0000-0000-0000-00000000feed")
    done < <(python3 -c "
import re, sys, yaml
lines = []
for line in open('services/gpu/prod/values.yaml'):
    line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
    line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
    lines.append(line)
v = yaml.safe_load(''.join(lines)) or {}
for k in (v.get('bitwardenIds') or {}):
    print(k)
")
    gpu_out="$WORK/gpu-render.yaml"
    if ! "$helm_bin" template gpu "$GPU" \
        --set domain=test.example.com --set clusterName=gpu "${sets[@]}" \
      >"$gpu_out" 2>"$WORK/gpu-render.err"; then
      tail -n 30 "$WORK/gpu-render.err" >&2
      fail "t4: helm template of $GPU with the full bitwardenIds --set list failed"
    fi
    if grep -q 'OVERRIDE_' "$gpu_out"; then
      grep -n 'OVERRIDE_' "$gpu_out" | head -5 >&2
      fail "t4: the fully --set-resolved gpu umbrella render still carries an OVERRIDE_* sentinel (AC5: none may remain in rendered output)"
    fi
    if ! grep -q 'forgejo-secret-seed' "$gpu_out"; then
      fail "t4: the gpu render never mentions forgejo-secret-seed (the charts entry did not reach the appset generator)"
    fi
    ok "t4: gpu umbrella renders with zero OVERRIDE_* strings and the forgejo-secret-seed app visible in the generator"
  else
    skip "t4 umbrella render leg not run (helm unavailable)"
  fi
fi

# --- t5: mixed-store ExternalSecret render proof ------------------------------
if want t5 && [ "$skip_helm" -eq 0 ]; then
  if grep -q 'bitwarden-login' "$render" && grep -q 'bitwarden-fields' "$render"; then
    ok "t5: ONE ExternalSecret object references both bitwarden-login and bitwarden-fields stores (the mixed-store shape precedents charts/immich-analyze + charts/archon prove renderable)"
  else
    fail "t5: the render lacks one of the two stores — the C04 table needs login(password) AND fields(site_id_*) mappings in a single object"
  fi
fi

rm -rf "$WORK"

printf 'PASS: gpu-forgejo-secret-seed checks (%d ok)\n' "$checks"
