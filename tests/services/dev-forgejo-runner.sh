#!/usr/bin/env bash
# C03 acceptance checks (2026-10-feat-forgejo-infra-and-runner): the new
# charts/forgejo-runner (app-template StatefulSet, 1 replica, dind sidecar
# initContainer, 2 VCTs, declarative-registration ExternalSecret, headless
# service, client-only — no ingress/LoadBalancer), the dev umbrella wiring,
# the sentinel sweep + trio greps, and the renovate comment placement.
# Criteria 1-6 of chunks/C03.md; RESEARCH.md is ground truth for the runner
# (declarative registration only — no register CLI, no env-var registration).
#
# The chart is rendered from a COPY under /tmp/opencode after
# `helm dependency update` there (repo convention: charts/**/charts is
# gitignored, Chart.lock is committed) — the worktree is never written.
#
# A helm binary is taken from HELM_BIN, the PATH, /home/coder/.local/bin,
# or /tmp/opencode; failing that, helm v3.21.4 is downloaded there (same
# provenance as tests/services/dev-git-auth.sh). If the registry is
# unreachable, t2 is skipped (t3's dev-umbrella and static checks still run).
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/dev-forgejo-runner.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RUNNER="charts/forgejo-runner"
DEVUMB="services/dev/prod"
DEV_VALUES="services/dev/prod/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
TEST_UUID="00000000-0000-0000-0000-000000000000"

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

# --- helm discovery (dev-git-auth.sh convention) --------------------------
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
  dir=/tmp/opencode/dev-forgejo-runner-helm-download
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

WORK=$(mktemp -d /tmp/opencode/dev-forgejo-runner.XXXXXX)

[ -d "$RUNNER" ] ||
  fail "t1: $RUNNER does not exist (C03 has not created the chart — nothing to dependency-update, lint, or render)"

# --- t1: dependency update (on a copy) + Chart.lock + lint ----------------
skip_helm=0
runner_copy=""
if [ -z "$helm_bin" ]; then
  skip "t1: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; t2 was not run"
  skip_helm=1
else
  runner_copy="$WORK/forgejo-runner-copy"
  cp -R "$RUNNER"/. "$runner_copy"/
  dep_log="$runner_copy/dependency-update.log"
  if ! (cd "$runner_copy" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "t1: helm dependency update could not reach the registry for $RUNNER here; t2 was not run (log kept at $dep_log)"
      skip_helm=1
      runner_copy=""
    else
      tail -n 30 "$dep_log" >&2
      fail "t1: helm dependency update failed for $RUNNER (log kept at $dep_log)"
    fi
  fi
fi

if [ "$skip_helm" -eq 0 ]; then
  ok "t1: helm dependency update succeeds for $RUNNER on a copy ($("$helm_bin" version --short 2>/dev/null || echo helm))"

  # The committed Chart.lock must resolve to the same dependency digest that
  # a fresh update computes — a stale or hand-edited lock fails here.
  [ -f "$RUNNER/Chart.lock" ] ||
    fail "t1: $RUNNER/Chart.lock is not committed (helm dependency update must commit it)"
  committed_digest=$(grep -m1 -E '^digest:[[:space:]]*' "$RUNNER/Chart.lock" | sed -E 's/^digest:[[:space:]]*//')
  fresh_digest=$(grep -m1 -E '^digest:[[:space:]]*' "$runner_copy/Chart.lock" | sed -E 's/^digest:[[:space:]]*//')
  [ -n "$committed_digest" ] && [ "$committed_digest" = "$fresh_digest" ] ||
    fail "t1: $RUNNER/Chart.lock digest ($committed_digest) does not match a fresh dependency update ($fresh_digest)"
  grep -q 'app-template' "$RUNNER/Chart.lock" ||
    fail "t1: $RUNNER/Chart.lock does not record an app-template dependency"
  ok "t1: Chart.lock is committed and its digest matches a fresh update (app-template present)"

  log="$WORK/lint-runner.log"
  if (cd "$runner_copy" && "$helm_bin" lint .) >"$log" 2>&1; then
    ok "t1: helm lint passes for $RUNNER"
  else
    tail -n 30 "$log" >&2
    fail "t1: helm lint failed for $RUNNER (log kept at $log)"
  fi
fi

# --- t2: render + pod/secret structure (criteria 2, 3) --------------------
runner_out=""
if [ "$skip_helm" -eq 1 ]; then
  skip "t2: render not run (dependency update unavailable)"
else
  runner_out="$WORK/runner-render.yaml"
  runner_err="$WORK/runner-render.err"
  if ! "$helm_bin" template "$runner_copy" --set "bitwardenIds.forgejo-runner-token=$TEST_UUID" \
    >"$runner_out" 2>"$runner_err"; then
    tail -n 30 "$runner_err" >&2
    fail "t2: helm template of $RUNNER failed (log kept at $runner_err)"
  fi
  [ -s "$runner_out" ] || fail "t2: helm template of $RUNNER rendered nothing"
  if python3 - "$runner_out" "$WORK/runner-count" <<'PY'
import re, sys, yaml

render, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    with open(render) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]

    sts = [d for d in docs if d.get('kind') == 'StatefulSet']
    deps = [d for d in docs if d.get('kind') == 'Deployment']
    if len(sts) != 1:
        bad(f't2: expected exactly one StatefulSet in the render, found {len(sts)} (the runner workload must be a StatefulSet)')
    if deps:
        bad(f't2: the render also contains Deployment(s) {[ (d.get("metadata") or {}).get("name") for d in deps ]} — a Deployment is the rejected alternative')
    ok('t2: the workload is a StatefulSet, and no Deployment renders')

    s = sts[0]
    if (s.get('spec') or {}).get('replicas') != 1:
        bad(f't2: StatefulSet replicas is {(s.get("spec") or {}).get("replicas")!r}, expected 1 (scaling = more runner records, never more replicas of one identity)')
    ok('t2: StatefulSet replicas: 1')

    vcts = (s.get('spec') or {}).get('volumeClaimTemplates') or []
    if len(vcts) != 2:
        bad(f't2: StatefulSet has {len(vcts)} volumeClaimTemplates, expected exactly 2 (data + docker-data)')
    by = {(v.get('metadata') or {}).get('name'): (v.get('spec') or {}) for v in vcts}
    if set(by) != {'data', 'docker-data'}:
        bad(f't2: volumeClaimTemplates are named {sorted(by)}, expected exactly [data, docker-data]')
    for name, size in (('data', '2Gi'), ('docker-data', '10Gi')):
        spec = by[name]
        if (spec.get('resources') or {}).get('requests', {}).get('storage') != size:
            bad(f't2: volumeClaimTemplate {name} requests {(spec.get("resources") or {}).get("requests", {}).get("storage")!r}, expected {size}')
        if spec.get('accessModes') != ['ReadWriteOnce']:
            bad(f't2: volumeClaimTemplate {name} accessModes are {spec.get("accessModes")!r}, expected [ReadWriteOnce]')
        if spec.get('storageClassName') != 'local-path':
            bad(f't2: volumeClaimTemplate {name} storageClassName is {spec.get("storageClassName")!r}, expected local-path')
    ok('t2: volumeClaimTemplates are exactly data (2Gi) + docker-data (10Gi), both RWO local-path')

    pod = ((s.get('spec') or {}).get('template') or {}).get('spec') or {}
    ics = pod.get('initContainers') or []
    dind = next((c for c in ics if (c or {}).get('name') == 'dind'), None)
    if dind is None:
        bad('t2: no initContainer named dind (the DinD sidecar is missing)')
    if dind.get('image') != 'docker:29.9.1-dind':
        bad(f't2: dind image is {dind.get("image")!r}, expected docker:29.9.1-dind')
    if dind.get('restartPolicy') != 'Always':
        bad(f't2: dind restartPolicy is {dind.get("restartPolicy")!r}, expected Always (sidecar semantics — without it the pod dies when dockerd exits)')
    if ((dind.get('securityContext') or {}).get('privileged')) is not True:
        bad('t2: dind securityContext.privileged is not true (DinD requires it)')
    for probe in ('startupProbe', 'livenessProbe'):
        p = dind.get(probe)
        if not p:
            bad(f't2: dind has no {probe} (the socket probe keeps the pod observable)')
        cmd = (p.get('exec') or {}).get('command')
        if cmd != ['test', '-S', '/var/run/docker.sock']:
            bad(f't2: dind {probe} exec command is {cmd!r}, expected [test, -S, /var/run/docker.sock]')
    ok('t2: dind sidecar — docker:29.9.1-dind, restartPolicy Always, privileged, socket startup+liveness probes')

    cons = pod.get('containers') or []
    runner = next((c for c in cons if (c or {}).get('name') == 'runner'), None)
    if runner is None:
        bad('t2: no container named runner')
    if runner.get('image') != 'data.forgejo.org/forgejo/runner:13.2.0':
        bad(f't2: runner image is {runner.get("image")!r}, expected data.forgejo.org/forgejo/runner:13.2.0')
    env = {(e or {}).get('name'): e for e in runner.get('env') or []}
    if (env.get('CREDENTIALS_DIRECTORY') or {}).get('value') != '/run/secrets/forgejo-runner':
        bad(f't2: CREDENTIALS_DIRECTORY is {(env.get("CREDENTIALS_DIRECTORY") or {}).get("value")!r}, expected /run/secrets/forgejo-runner')
    if (env.get('DOCKER_HOST') or {}).get('value') != 'unix:///var/run/docker.sock':
        bad(f't2: DOCKER_HOST is {(env.get("DOCKER_HOST") or {}).get("value")!r}, expected unix:///var/run/docker.sock')
    rsc = runner.get('securityContext') or {}
    if (rsc.get('capabilities') or {}).get('drop') != ['ALL']:
        bad(f't2: runner securityContext.capabilities.drop is {(rsc.get("capabilities") or {}).get("drop")!r}, expected [ALL] (the standard context — only dind is deliberately privileged)')
    if rsc.get('allowPrivilegeEscalation') is not False:
        bad('t2: runner securityContext.allowPrivilegeEscalation is not false')
    joined = ' '.join((runner.get('command') or []) + (runner.get('args') or []))
    if 'daemon' not in joined:
        bad(f't2: the runner command/args {joined!r} do not run the daemon subcommand')
    if re.search(r'\bregister\b', joined):
        bad(f't2: the runner command/args {joined!r} contain a register subcommand (v13 registration is declarative-only — RESEARCH.md Q2)')
    ok('t2: runner container — pinned image, CREDENTIALS_DIRECTORY + DOCKER_HOST, drop-ALL security context, daemon command without register')

    bad_envs = []
    for c in ics + cons:
        for e in (c or {}).get('env') or []:
            n = (e or {}).get('name') or ''
            if n.startswith('GITEA_') or n in ('FORGEJO_RUNNER_REGISTRATION_TOKEN', 'FORGEJO_INSTANCE_URL'):
                bad_envs.append(n)
    if bad_envs:
        bad('t2: registration-style env present in the pod: ' + ', '.join(sorted(set(bad_envs))) + ' (none of these work on runner v13 — RESEARCH.md Q2)')
    ok('t2: no GITEA_*/FORGEJO_RUNNER_REGISTRATION_TOKEN/FORGEJO_INSTANCE_URL env anywhere in the pod')

    if pod.get('terminationGracePeriodSeconds') != 10800:
        bad(f't2: pod terminationGracePeriodSeconds is {pod.get("terminationGracePeriodSeconds")!r}, expected 10800 (>= the runner shutdown_timeout 3h, so in-flight jobs finish)')
    ok('t2: pod terminationGracePeriodSeconds: 10800')

    svcs = [d for d in docs if d.get('kind') == 'Service']
    if not any(((d.get('spec') or {}).get('clusterIP')) == 'None' for d in svcs):
        bad('t2: no headless (clusterIP: None) Service renders — a StatefulSet requires one')
    lb = [(d.get('metadata') or {}).get('name') for d in svcs if (d.get('spec') or {}).get('type') == 'LoadBalancer']
    if lb:
        bad(f't2: LoadBalancer Service(s) rendered: {lb} (the runner is client-only)')
    ings = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'Ingress']
    if ings:
        bad(f't2: Ingress(es) rendered: {ings} (the runner is client-only — no ingress by design)')
    ok('t2: headless Service present; no Ingress, no LoadBalancer')

    es = [d for d in docs
          if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-runner']
    if not es:
        bad('t2: no ExternalSecret named forgejo-runner renders')
    e = es[0]
    text = yaml.safe_dump(e)
    if 'bitwarden-login' not in text:
        bad('t2: the forgejo-runner ExternalSecret does not use the bitwarden-login store')
    pairs = set()
    def walk(node):
        if isinstance(node, dict):
            if 'remoteRef' in node and 'secretKey' in node:
                pairs.add((node['secretKey'], (node.get('remoteRef') or {}).get('property')))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(e)
    if ('uuid', 'username') not in pairs:
        bad(f't2: the ExternalSecret has no data entry reading the item username as uuid (remoteRef pairs found: {sorted(pairs)})')
    if ('token', 'password') not in pairs:
        bad(f't2: the ExternalSecret has no data entry reading the item password as token (remoteRef pairs found: {sorted(pairs)})')
    data = (((e.get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
    if 'token' not in data:
        bad('t2: the ExternalSecret template data has no token key')
    elif data['token'] != '{{ .token }}':
        bad(f't2: the ExternalSecret token template is {data["token"]!r}, expected {{{{ .token }}}}')
    if 'config.yaml' not in data:
        bad('t2: the ExternalSecret template data has no config.yaml key')
    else:
        try:
            cfg = yaml.safe_load(data['config.yaml'])
        except Exception as ex:
            bad(f't2: the config.yaml template entry is not parseable YAML: {ex}')
        else:
            conn = (((cfg or {}).get('server') or {}).get('connections') or {}).get('dev')
            if not isinstance(conn, dict):
                bad('t2: config.yaml has no server.connections.dev connection (declarative registration)')
            else:
                if conn.get('uuid') != '{{ .uuid }}':
                    bad(f't2: server.connections.dev.uuid is {conn.get("uuid")!r}, expected {{{{ .uuid }}}} (the only dynamic part)')
                if conn.get('url') != 'http://dev-forgejo-http.default.svc:3000':
                    bad(f't2: server.connections.dev.url is {conn.get("url")!r}, expected http://dev-forgejo-http.default.svc:3000 (in-cluster — the runner is a client)')
                if conn.get('token_url') != 'file:$CREDENTIALS_DIRECTORY/token':
                    bad(f't2: server.connections.dev.token_url is {conn.get("token_url")!r}, expected file:$CREDENTIALS_DIRECTORY/token')
                if conn.get('labels') != ['docker:docker://data.forgejo.org/oci/node:lts', 'dev']:
                    bad(f't2: server.connections.dev.labels are {conn.get("labels")!r}, expected [docker:docker://data.forgejo.org/oci/node:lts, dev]')
            if ((cfg or {}).get('runner') or {}).get('capacity') != 1:
                bad(f't2: runner.capacity is {((cfg or {}).get("runner") or {}).get("capacity")!r}, expected 1')
            if ((cfg or {}).get('container') or {}).get('privileged') is not False:
                bad('t2: container.privileged in config.yaml is not false (jobs stay sandboxed)')
            if ((cfg or {}).get('cache') or {}).get('enabled') is not True:
                bad('t2: cache.enabled in config.yaml is not true')
    ok('t2: ExternalSecret forgejo-runner — bitwarden-login store, uuid(username)+token(password) remoteRefs, token + config.yaml template data with declarative server.connections.dev')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't2: the runner render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/runner-count")))
  else
    exit 1
  fi

  # Criterion 3: the sentinels are gone after the --set.
  if grep -n 'OVERRIDE_' "$runner_out" >/dev/null 2>&1; then
    grep -n 'OVERRIDE_' "$runner_out" >&2
    fail "t3: the rendered runner manifests still carry an OVERRIDE_* sentinel after --set bitwardenIds.forgejo-runner-token"
  fi
  ok "t3: no OVERRIDE_* in the rendered output after --set"
fi

# --- t3: dev umbrella + sweep + trio + renovate (criteria 4-6) ------------
# (b) Dev umbrella: the appset values blob gains charts.forgejo-runner and
# ingress.subdomains keeps exactly the pre-existing dev hosts.
dev_out="$WORK/dev-render.yaml"
dev_err="$WORK/dev-render.err"
if ! "$helm_bin" template "$DEVUMB" \
  --set domain=scifi.farm --set subDomain=dev --set clusterName=dev \
  --set bitwardenIds.cert-manager-solver-token=u --set bitwardenIds.argocd-sso-secret=u \
  --set bitwardenIds.github-pat=u --set bitwardenIds.forgejo-token=u \
  --set hivetools.bitwardenIds.mcp-sso=u \
  >"$dev_out" 2>"$dev_err"; then
  tail -n 30 "$dev_err" >&2
  fail "t3: helm template of $DEVUMB failed (log kept at $dev_err)"
fi
[ -s "$dev_out" ] || fail "t3: helm template of $DEVUMB rendered nothing"
if python3 - "$dev_out" "$WORK/dev-count" <<'PY'
import sys, yaml

render, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    with open(render) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]

    appsets = [d for d in docs
               if d.get('kind') == 'ApplicationSet'
               and (d.get('metadata') or {}).get('name') == 'dev-appset']
    if not appsets:
        bad('t3: no ApplicationSet named dev-appset in the dev render')
    els = appsets[0]['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
    vals = (els[0] if els else {}).get('values')
    if not isinstance(vals, dict):
        bad('t3: the dev-appset generator element has no values blob')

    fr = (vals.get('charts') or {}).get('forgejo-runner')
    if not isinstance(fr, dict):
        bad('t3: the dev-appset values blob has no charts.forgejo-runner entry (the runner app is not wired into the dev umbrella)')
    if fr.get('namespace') != 'default':
        bad(f't3: charts.forgejo-runner.namespace is {fr.get("namespace")!r}, expected "default"')
    if str(fr.get('ServerSideApply')) != 'false':
        bad(f't3: charts.forgejo-runner.ServerSideApply is {fr.get("ServerSideApply")!r}, expected "false"')
    ok('t3: dev-appset values blob has charts.forgejo-runner (namespace default, ServerSideApply "false")')

    subs = (vals.get('ingress') or {}).get('subdomains') or {}
    if set(subs) != {'coder', 'git', 'research', 'cluster'}:
        bad(f't3: dev ingress.subdomains are {sorted(subs)}, expected exactly [coder, git, research, cluster] — the runner is client-only, so it gets NO ingress entry')
    ok('t3: dev ingress.subdomains is unchanged (coder/git/research/cluster — no runner entry)')

    raw = open(render).read()
    if 'OVERRIDE_VIA_CUSTOM_VALUES' in raw or 'OVERRIDE_VIA_APPSET' in raw:
        bad('t3: the rendered dev umbrella still carries an OVERRIDE_VIA_* sentinel (the plan --set list did not resolve it)')
    ok('t3: no OVERRIDE_VIA_* sentinel survives in the rendered dev umbrella')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the dev render could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/dev-count")))
else
  exit 1
fi

# (c) Sentinel sweep + trio greps (criterion 5). The chart's sentinel must
# match custom-values/dev 1:1; the service entry must exist WITH a comment
# explaining the deliberately missing proxy/ingress leg.
if python3 - "$RUNNER/values.yaml" "$DEV_VALUES" "$DEV_CV" "$WORK/sweep-count" <<'PY'
import re, sys, yaml

chart_vals, dev_vals, dev_cv, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

SENTINEL = 'OVERRIDE_VIA_CUSTOM_VALUES'
UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')

def load(path):
    # REDEFINED anchors are legal YAML (helm/Go accept them; PyYAML raises
    # ComposerError). Only markers in `key: &anchor` / `key: *alias` value
    # position are rewritten; & inside quoted strings and in comments is
    # untouched. Alias targets are values this test never asserts, so the
    # ANCHOR_REF placeholders are inert.
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    cv = load(chart_vals)
    bw = (cv.get('bitwardenIds') or {}).get('forgejo-runner-token')
    if bw != SENTINEL:
        bad(f't3: {chart_vals} bitwardenIds.forgejo-runner-token is {bw!r}, expected {SENTINEL} (the repo sentinel — the real UUID lives only in custom-values/dev)')
    ok(f't3: {chart_vals} carries the forgejo-runner-token sentinel')

    dv = load(dev_cv)
    entry = ((dv.get('forgejo-runner') or {}).get('bitwardenIds') or {}).get('forgejo-runner-token')
    if entry is None:
        bad(f't3: {dev_cv} has no forgejo-runner.bitwardenIds.forgejo-runner-token entry (the sentinel would survive to the cluster)')
    elif entry == SENTINEL or not (entry == 'OVERRIDE_NEEDED' or UUID_RE.match(str(entry))):
        bad(f't3: {dev_cv} forgejo-runner.bitwardenIds.forgejo-runner-token is {entry!r} — must be a real UUID or the documented OVERRIDE_NEEDED placeholder, never the service sentinel')
    else:
        ok(f't3: {dev_cv} carries the forgejo-runner-token value ({entry if entry == "OVERRIDE_NEEDED" else "a real UUID"})')

    sv = load(dev_vals)
    fr = (sv.get('charts') or {}).get('forgejo-runner')
    if not isinstance(fr, dict):
        bad('t3: ' + dev_vals + ' has no charts.forgejo-runner entry (trio: chart leg missing)')
    if fr.get('namespace') != 'default' or str(fr.get('ServerSideApply')) != 'false':
        bad(f't3: charts.forgejo-runner entry is {fr!r}, expected namespace default + ServerSideApply "false"')
    ok('t3: ' + dev_vals + ' carries charts.forgejo-runner (namespace default, ServerSideApply "false")')

    # The client-only rationale must be documented next to the entry, or the
    # next reader assumes the missing ingress leg is an oversight.
    with open(dev_vals) as f:
        lines = f.read().splitlines()
    idxs = [i for i, l in enumerate(lines) if re.match(r'^\s*forgejo-runner:\s*$', l)]
    if not idxs:
        bad('t3: ' + dev_vals + ' has no forgejo-runner: line under charts:')
    else:
        idx = idxs[0]
        comments = []
        # The full contiguous comment block above the entry (a multi-line
        # rationale is the natural way to document this), then any comments
        # inside the entry block before the first real line.
        j = idx - 1
        while j >= 0 and lines[j].lstrip().startswith('#'):
            comments.append(lines[j])
            j -= 1
        for l in lines[idx + 1:]:
            s = l.strip()
            if s.startswith('#'):
                comments.append(s)
            elif s:
                break  # end of the (possibly comment-free) entry block
        if not any(re.search(r'ingress|proxy', c, re.IGNORECASE) for c in comments):
            bad('t3: the charts.forgejo-runner entry has no comment explaining the deliberately missing ingress/proxy leg (client-only service)')
        ok('t3: the charts.forgejo-runner entry carries a comment explaining the missing proxy/ingress leg')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the sweep could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/sweep-count")))
else
  exit 1
fi

# (d) Renovate comment (criterion 6): directly above the runner image tag,
# datasource=docker, depName == the image repository. The repository is read
# from the rendered pod when available, else declared in the chart values.
repo_arg=""
if [ -n "$runner_out" ] && [ -s "$runner_out" ]; then
  repo_arg=$(python3 - "$runner_out" <<'PY'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if not d or d.get('kind') != 'StatefulSet':
        continue
    for c in (((d.get('spec') or {}).get('template') or {}).get('spec') or {}).get('containers') or []:
        if (c or {}).get('name') == 'runner':
            img = c.get('image') or ''
            print(img.rsplit(':', 1)[0])
            sys.exit(0)
sys.exit(1)
PY
  ) || repo_arg=""
fi
if python3 - "$RUNNER/values.yaml" "${repo_arg:-}" "$WORK/renovate-count" <<'PY'
import re, sys

vals_path, rendered_repo, count_file = sys.argv[1], sys.argv[2], sys.argv[3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    lines = open(vals_path).read().splitlines()
    tag_re = re.compile(r'^\s*tag:\s*13\.2\.0\b')
    inline_re = re.compile(r'^\s*image:\s*data\.forgejo\.org/forgejo/runner:13\.2\.0\b')
    tag_idx = [i for i, l in enumerate(lines) if tag_re.match(l) or inline_re.match(l)]
    if not tag_idx:
        bad(f't3: no runner image tag line (tag: 13.2.0 / inline image) found in {vals_path}')
    # Declared repo: the repository: line of the runner container block, or
    # the inline image. The rendered image is the ground truth when present.
    declared = None
    for i, l in enumerate(lines):
        m = re.match(r'^\s*image:\s*(\S+):13\.2\.0\s*$', l)
        if m:
            declared = m.group(1)
            break
    if declared is None:
        for i, l in enumerate(lines):
            m = re.match(r'^\s*repository:\s*(\S+)\s*$', l)
            if m and 'forgejo/runner' in m.group(1):
                declared = m.group(1)
                break
    repo = rendered_repo or declared
    if not repo:
        bad(f't3: the runner image repository could not be determined (no rendered image, no repository:/image: line in {vals_path})')
    renovate_re = re.compile(r'^\s*#\s*renovate:.*\bdatasource=docker\b.*\bdepName=' + re.escape(repo) + r'(\b|$)')
    for i in tag_idx:
        if i == 0 or not renovate_re.match(lines[i - 1]):
            bad(f't3: the runner image tag line {i + 1} ({lines[i].strip()!r}) has no renovate comment directly above it — expected: # renovate: datasource=docker depName={repo} versioning=semver')
    ok(f't3: renovate comment sits directly above the runner image tag with depName={repo}')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the renovate placement could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/renovate-count")))
else
  exit 1
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: dev-forgejo-runner checks (%d ok)\n' "$checks"
