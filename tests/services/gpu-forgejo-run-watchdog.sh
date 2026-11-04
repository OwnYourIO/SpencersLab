#!/usr/bin/env bash
# C05 contract (ticket 2026-10-cf-11-feat-immich-hugo-pipeline) for
# charts/forgejo-run-watchdog — the schedule-failure watchdog owner answer 3
# made phase-1 mandatory: hourly CHECK CronJob, freshness via the Forgejo
# runs API with 48h (2x the DAILY cadence) threshold, Netlify-deploys
# fallback when the runs endpoint 404s, and a fully VALUE-driven notification
# POST (the channel is the owner's choice — HA lives in services/grow, so no
# in-cluster receiver may be assumed). GPU wiring reuses C04's Bitwarden
# items (forgejo-pat + netlify; NO new mandatory secrets) with the
# OVERRIDE_VIA_CLUSTER_ANNOTATION sentinel flavor.
#
# AC trace (chunks/C05.md): t1[AC1 CronJob shape] t2[AC2 runs-API
# construction + 48h math + dispatch construction + run-owned timestamp
# field (BLOCKER-1 pin)] t3[AC2 fallback construction] t4[AC3 value-driven
# notify] t5[AC4/AC5 gpu umbrella + C04 sentinel-key parity +
# custom-values app-block 1:1 + no OVERRIDE_* + no ingress]
# t6[sibling C04 contract stays green — wave-3 regression].
#
# Helm discovery + registry-skip + render-from-/tmp-copy conventions follow
# tests/services/gpu-forgejo-secret-seed.sh (kept duplicated so the suites
# stay independent). Red-first: the missing chart is a FAIL, not a skip.
#
# Run from the repo root:
#   bash tests/services/gpu-forgejo-run-watchdog.sh
#   bash tests/services/gpu-forgejo-run-watchdog.sh t2     # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WD="charts/forgejo-run-watchdog"
SEED="charts/forgejo-secret-seed"
GPU="services/gpu/prod"
GPU_VALUES="$GPU/values.yaml"
CV="custom-values/gpu/prod-values.yaml"

TEST_UUID_NETLIFY="00000000-0000-0000-0000-0000000000b2"
TEST_UUID_PAT="00000000-0000-0000-0000-0000000000b3"

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
  for i in 1 2 3 4 5 6; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -d "$WD" ] ||
  fail "$WD does not exist (the C05 chart has not been created — nothing to render or lint)"

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

WORK=$(mktemp -d /tmp/opencode/gpu-forgejo-run-watchdog.XXXXXX)
wd_copy="$WORK/forgejo-run-watchdog-copy"
cp -R "$WD"/. "$wd_copy"/

skip_helm=0
helm_bin=$(find_helm || true)
if [ -z "$helm_bin" ]; then
  skip "no helm binary; the render legs (t1-t4 render parts, t5 umbrella) were not run"
  skip_helm=1
else
  dep_log="$WORK/dependency-build.log"
  if ! (cd "$wd_copy" && "$helm_bin" dependency build .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "helm dependency build could not reach the registry (render legs not run; log kept at $dep_log)"
      skip_helm=1
    else
      tail -n 30 "$dep_log" >&2
      fail "helm dependency build failed for $WD (log kept at $dep_log)"
    fi
  fi
fi

if [ "$skip_helm" -eq 0 ]; then
  [ "$(grep -m1 -E '^version:' "$WD/Chart.yaml" | sed -E 's/^version:[[:space:]]*//')" = "1.0.0" ] ||
    fail "t1: $WD/Chart.yaml version must be 1.0.0 (new-chart rule)"
  lint_log="$WORK/lint.log"
  if ! (cd "$wd_copy" && "$helm_bin" lint .) >"$lint_log" 2>&1; then
    tail -n 30 "$lint_log" >&2
    fail "t1: helm lint failed for $WD (log kept at $lint_log)"
  fi
fi

render="$WORK/wd-render.yaml"
if [ "$skip_helm" -eq 0 ]; then
  if ! "$helm_bin" template forgejo-run-watchdog "$wd_copy" \
      --set "bitwardenIds.netlify=$TEST_UUID_NETLIFY" \
      --set "bitwardenIds.forgejo-pat=$TEST_UUID_PAT" \
      --debug \
    >"$render" 2>"$WORK/render.err"; then
    tail -n 30 "$WORK/render.err" >&2
    fail "chart template of $WD with the reused-item --sets failed (log kept at $WORK/render.err)"
  fi
  [ -s "$render" ] || fail "the watchdog chart rendered nothing"
fi

# --- t1: chart + CronJob shape -------------------------------------------------
if want t1 && [ "$skip_helm" -eq 0 ]; then
  if python3 - "$render" "$WORK/t1-count" <<'PY'
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
        bad(f't1: {len(cjs)} CronJobs rendered, expected exactly 1')
    spec = (cjs[0].get('spec') or {})
    sched = str(spec.get('schedule') or '')
    # HOURLY check, daily sync cadence: hour field wildcard, minute fixed.
    if not re.fullmatch(r'\d+ \* \* \* \*', sched):
        bad(f't1: schedule {sched!r} is not an hourly check (expected "M * * * *") — the watchdog CHECK stays hourly even though the sync is daily')
    if spec.get('concurrencyPolicy') != 'Forbid':
        bad(f't1: concurrencyPolicy {spec.get("concurrencyPolicy")!r}, expected Forbid')
    jt = ((spec.get('jobTemplate') or {}).get('spec') or {})
    if jt.get('ttlSecondsAfterFinished') is None and spec.get('ttlSecondsAfterFinished') is None:
        bad('t1: ttlSecondsAfterFinished missing (sibling convention of C04)')
    pod = ((jt.get('template') or {}).get('spec') or {})
    containers = (pod.get('containers') or [])
    wdc = next((c for c in containers if 'curl' in str(c.get('image'))), None)
    if wdc is None:
        bad('t1: no curl-image container (sibling convention: pinned docker.io/curlimages/curl)')
    img = str(wdc.get('image'))
    if img.endswith(':latest') or not re.search(r'curlimages/curl:[v0-9][0-9a-zA-Z._-]*$', img):
        bad(f't1: curl image {img!r} is not a pinned concrete tag (C05 §shape: renovate)')
    if pod.get('restartPolicy') != 'OnFailure':
        bad(f't1: restartPolicy {pod.get("restartPolicy")!r}, expected OnFailure (sibling shape)')
    drops = []
    for c in [wdc] + (pod.get('initContainers') or []):
        drops.append(str(((c.get('securityContext') or {}).get('capabilities') or {}).get('drop')))
    sc = str((pod.get('securityContext') or {}).get('capabilities') or {})
    if not any('ALL' in d for d in drops) and 'ALL' not in sc:
        bad('t1: drop-ALL security context missing (same chart conventions as C04)')
    if not (wdc.get('command') or wdc.get('args')):
        bad('t1: the watchdog container carries no command — the ConfigMap script must run')
    if not re.search(r'reloader.stakater.com', open(render).read()):
        bad('t1: no reloader.stakater.com annotation (C05 §shape: same chart conventions as C04)')
    ok(f't1: hourly CronJob {sched!r}, Forbid, ttl set, OnFailure, pinned {img}, drop-ALL, reloader present')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't1: the watchdog render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t1-count")))
  else
    exit 1
  fi
fi

# --- t2 + t3 + t4: script construction legs ------------------------------------
# All three read the rendered ConfigMap script — construction tests only until
# a live repo with runs exists (C05 §Notes for dev).
if { want t2 || want t3 || want t4; } && [ "$skip_helm" -eq 0 ]; then
  if python3 - "$render" "$WD/values.yaml" "$WORK/t234-count" <<'PY'
import re, sys, yaml

render, wd_values, count_file = sys.argv[1:4]
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

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    script_text = ''
    for cm in (d for d in docs if d.get('kind') == 'ConfigMap'):
        for v in (cm.get('data') or {}).values():
            if isinstance(v, str) and 'curl' in v:
                script_text += v
    if not script_text:
        bad('t2: no ConfigMap carries the check script')

    wv = load(wd_values)
    wd = wv.get('watchdog') or {}
    # --- t2: runs-API leg + 48h default
    if not re.search(r"/api/v1/repos/[^\" ]*/actions/runs|actions/runs", script_text):
        bad(f't2: the script never calls the Forgejo runs API (GET {{"{forgejoUrl}"}}/api/v1/repos/{owner}/{repo}/actions/runs per the contract)')
    if wd.get('maxAgeHours') != 48:
        bad(f't2: watchdog.maxAgeHours default is {wd.get("maxAgeHours")!r}, expected 48 (2x the daily cadence — answer 7 mitigation math)')
    if not re.search(r'(?i)max_?age|agen?ow|agehours', script_text):
        bad('t2: the script shows no age-threshold handling at all')
    if not re.search(r'3600|172800|86400|\bepoch\b|date -d|date \+|TZ=UTC', script_text):
        bad('t2: no time arithmetic (epoch / hour- or day-seconds conversion) for the threshold comparison')
    auth = re.search(r'Authorization:\s*token', script_text)
    if not auth:
        bad('t2: the runs call carries no "Authorization: token" header (the reused forgejo-pat)')
    if '/secrets/forgejo_pat' not in script_text and 'forgejo_pat' not in script_text:
        bad('t2: the PAT is not read from the mounted secret material')
    envs = []
    for d in docs:
        if d.get('kind') != 'CronJob':
            continue
        pod = ((((d.get('spec') or {}).get('jobTemplate') or {}).get('spec') or {}).get('template') or {}).get('spec') or {}
        for c in pod.get('containers') or []:
            envs += [e for e in (c.get('env') or []) if isinstance(e, dict)]
    if not any(re.search(r'max.?age', str(e.get('name')), re.IGNORECASE) or str(e.get('value')) == '48' for e in envs):
        bad(f't2: the 48h threshold never reaches the container env ({[e.get("name") for e in envs]}) — the values knob would be inert')

    # Stale-recovery dispatch construction (runs leg), live-swagger verified:
    # POST /repos/{owner}/{repo}/actions/workflows/{workflowfilename}/
    # dispatches with a required "ref" body.
    if not re.search(r'/actions/workflows/[^/\s]+/dispatches', script_text):
        bad('t2: no construction of the Actions dispatch endpoint (POST …/actions/workflows/{workflowfilename}/dispatches, live-swagger verified) — the stale-recovery re-dispatch is the runs leg\'s action')
    if not re.search(r'"ref"\s*:', script_text):
        bad('t2: the dispatch body carries no "ref" — the endpoint requires it (live-swagger verified)')

    # BLOCKER-1 regression pin (review r1, field names verified live at
    # git.spencerslab.com /swagger.v1.json): the pinned Gitea-1.22 ActionRun
    # serializes its own timestamps as "created"/"started"/"stopped" — there
    # is NO "created_at" key on the run record, but the nested repository
    # object HAS one. A created_at grep in the runs leg therefore measures
    # the repo\'s birth date (steady state = hourly false re-dispatch, the
    # watchdog inverted). The ban is scoped to the function that extracts
    # the run\'s own field — the Netlify fallback leg legitimately reads
    # created_at/published_at on deploy records.
    def _fn_bodies(text):
        defs = list(re.finditer(r'^[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(\)[ \t]*\{', text, re.M))
        for i, m in enumerate(defs):
            end = defs[i + 1].start() if i + 1 < len(defs) else len(text)
            yield m.group(1), text[m.start():end]

    run_legs = [
        (name, body)
        for name, body in _fn_bodies(script_text)
        if re.search(r'grep -o[^\n]*"(created|started|stopped)":"', body)
    ]
    if not run_legs:
        bad('t2: no shell function extracts the run\'s own timestamp field — the runs leg must grep one of "created"/"started"/"stopped" (Gitea-1.22 ActionRun shape, live-swagger verified); a "created_at" extraction is the BLOCKER-1 regression this pin kills')
    for name, body in run_legs:
        if 'created_at' in re.sub(r'#.*', '', body):
            bad(f't2: the runs-leg function {name!r} still reads "created_at" — that key belongs to the nested repository object (repo age), not the ActionRun record (BLOCKER-1)')
    ok('t2: runs-API GET with token auth from the mounted PAT + maxAgeHours 48 flowing into the container env + dispatch construction + run-owned timestamp field pinned (BLOCKER-1)')

    # --- t3: Netlify fallback leg
    if 'api.netlify.com/api/v1/sites' not in script_text or '/deploys' not in script_text:
        bad('t3: the script constructs no Netlify deploys call (fallback leg: GET https://api.netlify.com/api/v1/sites/{siteId}/deploys)')
    if wd.get('maxAgeDays') != 3:
        bad(f't3: watchdog.maxAgeDays default is {wd.get("maxAgeDays")!r}, expected 3 (liveness floor, contract §1b)')
    if not re.search(r'(?i)"?ready"?', script_text):
        bad('t3: the fallback never checks the ready state of deploys (contract §1b: newest READY deploy)')
    ok('t3: fallback leg builds the Netlify deploys call, checks ready, maxAgeDays 3')

    # --- t4: value-driven notify
    notify = (wd.get('notify') or {})
    if 'url' not in notify:
        bad('t4: watchdog.notify.url missing from values — the channel must be a VALUE (contract §2)')
    if not re.search(r'-X +POST|\bPOST\b', script_text):
        bad('t4: the script has no POST construction for the notification')
    if not re.search(r'(?i)notify', script_text):
        bad('t4: the script never names the notify target — the URL would be hardcoded')
    url_val = str(notify.get('url') or '')
    for banned in ('ntfy.sh', 'hooks.slack', 'discord.com', 'gotify'):
        if banned in url_val.lower() or re.search(r'https://[a-z0-9.-]*' + banned, script_text, re.IGNORECASE):
            bad(f't4: a concrete receiver ({banned}) is baked into values/script — the channel is the owner\'s value, not the chart\'s')
    if not any(re.search(r'(?i)notify', str(e.get('name'))) for e in envs):
        bad(f't4: the notify URL does not flow as container env ({[e.get("name") for e in envs]})')
    ok('t4: notify POST is fully value-driven (watchdog.notify.url -> env -> POST; zero hardcoded receivers)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't2/t3/t4: the check script could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t234-count")))
  else
    exit 1
  fi
fi

# --- t5: gpu umbrella wiring + C04 sentinel-key parity --------------------------
if want t5; then
  [ -d "$SEED" ] ||
    fail "t5: $SEED does not exist — the parity of the two gpu sentinel key sets cannot be proven without the sibling chart (C05 depends_on C04)"
  if python3 - "$WD/values.yaml" "$SEED/values.yaml" "$GPU_VALUES" "$WORK/t5-count" <<'PY'
import re, sys, yaml

wd_vals, seed_vals, gpu_values, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

SENTINEL = 'OVERRIDE_VIA_CLUSTER_ANNOTATION'

def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    wdb = (load(wd_vals).get('bitwardenIds') or {})
    seb = (load(seed_vals).get('bitwardenIds') or {})
    if not {'forgejo-pat', 'netlify'} <= set(wdb):
        bad(f't5: watchdog bitwardenIds is {sorted(wdb)} — it must reuse C04\'s forgejo-pat + netlify items (AC4)')
    extra = set(wdb) - set(seb)
    with open(wd_vals) as f:
        wtxt = f.read()
    for key in sorted(extra):
        m = re.search(r'^[ \t]*' + re.escape(key) + r':', wtxt, re.M)
        ctx = wtxt[max(0, m.start() - 300):m.start()] if m else ''
        if not re.search(r'(?i)optional', ctx):
            bad(f't5: watchdog key {key!r} is not in C04\'s item set and is not comment-marked optional — AC4 forbids NEW mandatory Bitwarden items')
    for key in wdb:
        if wdb[key] != SENTINEL:
            bad(f't5: {wd_vals} bitwardenIds.{key} is {wdb[key]!r}, expected the gpu flavor {SENTINEL}')
    ok(f't5: watchdog sentinel keys {sorted(wdb)} reuse C04\'s items (grep-diff parity; extras must be documented optional)')

    sv = load(gpu_values)
    charts = sv.get('charts') or {}
    if 'forgejo-run-watchdog' not in charts:
        bad(f't5: {gpu_values} has no charts.forgejo-run-watchdog entry')
    e = charts['forgejo-run-watchdog']
    if e.get('namespace') != 'default' or str(e.get('ServerSideApply')) != 'false':
        bad(f't5: charts.forgejo-run-watchdog entry shape is {e!r}, expected namespace default + ServerSideApply "false"')
    gpu_bw = sv.get('bitwardenIds') or {}
    for key in wdb:
        if gpu_bw.get(key) != SENTINEL:
            bad(f't5: {gpu_values} global bitwardenIds.{key} is {gpu_bw.get(key)!r}, expected {SENTINEL} (the uuid entries ride C04\'s user-action annotation list — same keys, no new mandatory items)')
    ok('t5: gpu umbrella wires both the charts entry and the shared sentinel keys (C05 rides C04\'s annotation user action)')

    subs = ((sv.get('ingress') or {}).get('subdomains') or {})
    if 'forgejo-run-watchdog' in subs:
        bad('t5: ingress.subdomains has a forgejo-run-watchdog entry — the watchdog is client-only (AC5)')
    ok('t5: no ingress entry for the watchdog (client-only asserted)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't5: the gpu wiring checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t5-count")))
  else
    exit 1
  fi

  # MAJOR-2 leg (review r1): the custom-values/gpu app block that actually
  # delivers the uuids (valuesObject projection) was never read by this
  # suite — AC4's app-block 1:1 was enforced by reviewer grep only.
  [ -f "$CV" ] ||
    fail "t5: $CV does not exist — the valuesObject delivery path for the real uuids cannot be checked"
  if python3 - "$WD/values.yaml" "$CV" "$WORK/t5cv-count" <<'PY'
import re, sys, yaml

wd_vals, cv_path, count_file = sys.argv[1:4]
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

try:
    chart_bw = (load(wd_vals).get('bitwardenIds') or {})
    cv = load(cv_path)
    wd_app = (cv.get('forgejo-run-watchdog') or {}).get('bitwardenIds')
    if not isinstance(wd_app, dict) or not wd_app:
        bad(f't5: {cv_path} has no forgejo-run-watchdog bitwardenIds app block — the valuesObject delivery path for the real uuids does not exist (AC4)')
    if set(wd_app) != set(chart_bw):
        bad(f't5: the app-block keys {sorted(wd_app)} are not 1:1 with the chart sentinel keys {sorted(chart_bw)} (AC4)')
    seed_app = (cv.get('forgejo-secret-seed') or {}).get('bitwardenIds') or {}
    if not seed_app:
        bad(f't5: {cv_path} has no forgejo-secret-seed app block — the C04 slot-parity baseline is missing')
    new_items = set(wd_app) - set(seed_app)
    if new_items:
        bad(f't5: the app block carries keys {sorted(new_items)} absent from C04\'s block — slot parity forbids new Bitwarden items (AC4)')
    uuid_re = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
    for key in sorted(set(wd_app) & set(seed_app)):
        wv, sv = str(wd_app[key]), str(seed_app[key])
        # An unfilled OVERRIDE_NEEDED is the contract shape at landing (the
        # owner fill is user action 5; the unfilled slot fails the hourly
        # fetch loudly by design) — only a filled mismatch is a fault.
        if uuid_re.match(wv) and uuid_re.match(sv) and wv != sv:
            bad(f't5: app-block {key} is filled with {wv} but C04\'s block carries {sv} — the watchdog must reuse the same item (AC4: no new items)')
    ok(f"t5: custom-values/gpu app block 1:1 with the chart sentinels {sorted(chart_bw)} and slot-parity with C04's block (no new items)")
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't5: the custom-values app-block check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t5cv-count")))
  else
    exit 1
  fi

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
      fail "t5: helm template of $GPU with the full bitwardenIds --set list failed"
    fi
    if grep -q 'OVERRIDE_' "$gpu_out"; then
      grep -n 'OVERRIDE_' "$gpu_out" | head -5 >&2
      fail "t5: the fully --set-resolved gpu umbrella render still carries an OVERRIDE_* sentinel (AC5)"
    fi
    if ! grep -q 'forgejo-run-watchdog' "$gpu_out"; then
      fail "t5: the gpu render never mentions forgejo-run-watchdog (the charts entry did not reach the appset generator)"
    fi
    ok "t5: gpu umbrella renders with zero OVERRIDE_* strings and the forgejo-run-watchdog app visible in the generator"
  else
    skip "t5 umbrella render leg not run (helm unavailable)"
  fi
fi

# --- t6: regression — the C04 sibling contract stays green ---------------------
if want t6; then
  if bash tests/services/gpu-forgejo-secret-seed.sh >/tmp/opencode/gpu-forgejo-secret-seed-regression.log 2>&1; then
    ok "t6: tests/services/gpu-forgejo-secret-seed.sh green (C05 changed nothing the sibling contract asserts)"
  else
    tail -n 30 /tmp/opencode/gpu-forgejo-secret-seed-regression.log >&2
    fail "t6: the C04 sibling script is no longer green (log kept at /tmp/opencode/gpu-forgejo-secret-seed-regression.log)"
  fi
fi

rm -rf "$WORK"

printf 'PASS: gpu-forgejo-run-watchdog checks (%d ok)\n' "$checks"
