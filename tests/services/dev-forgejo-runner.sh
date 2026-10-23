#!/usr/bin/env bash
# Fused two-controller contract for charts/forgejo-runner (F01 + F02 of
# 2026-10-feat-forgejo-infra-and-runner, fusion 2026-10-23): exactly TWO
# StatefulSets (runner-dev, runner-infra), each with one privileged dind
# sidecar initContainer (docker:29.9.1-dind, restartPolicy Always, socket
# probes) + one hardened runner container (13.2.0 pin, dumb-init daemon,
# drop ALL, no register, no registration env), grace 300 + fsGroup 1000,
# per-controller headless services, two ExternalSecrets (bitwarden-login;
# uuid<-username, token<-password; per-item remoteRef keys), both
# config.yamls with the 5-label act set + timeout 30m + shutdown_timeout 5m
# + chart-default connection URLs, URL override probe, renovate built-in
# helm-values extraction, the two bitwardenIds sentinels, the doc ports
# (RESEARCH-dind-supplement.md + RESEARCH.md pointer), the F02 custom-values
# second slot + 2<->2 parity, the F02 dev-umbrella render (both URL pins +
# resolved UUIDs in the appset values blob), and the updated
# both-controllers trio-deviation comment.
#
# Contract sources: chunks/F01.md acceptance criteria 1-5 + its Tests list
# (t1-t6) and chunks/F02.md acceptance criteria 1-4 + its Tests list
# (t7-t10) — ONE script stays the runner contract for the whole ticket.
# F01's assertions (t1-t6) are green from F01 dev onward; F02's assertions
# (t7-t10) stay red (for the right reason: the service slice and the second
# custom-values slot do not exist yet) until F02 lands.
#
# The chart is rendered from a COPY under /tmp/opencode after
# `helm dependency update` there (repo convention: charts/**/charts is
# gitignored, Chart.lock is committed) — the worktree is never written.
#
# A helm binary is taken from HELM_BIN, the PATH, /home/coder/.local/bin,
# or /tmp/opencode; failing that, helm v3.21.4 is downloaded there (same
# provenance as tests/services/dev-git-auth.sh). If the registry is
# unreachable, t1-t3 are skipped (t4-t10 still run — t4 needs only
# node/npx, t9 needs only helm for the dependency-free dev umbrella).
#
# The renovate check (t4) uses the FRICTION-ported recipe: the bundled
# renovate 44.115.13 CLI from the npx cache, --platform=local (localDir =
# cwd) + --dry-run against a minimal /tmp git repo holding the chart + the
# repo renovate.json. Extraction comes from renovate's BUILT-IN helm-values
# manager (FRICTION mechanism erratum: per-line `# renovate:` comments are
# inert); the pinned 44.115.13 exits non-zero on modern node (unsupported
# node env warning) even on a fully successful scan, so the assertion gates
# on the extraction lines in the debug log, not on the exit code.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/dev-forgejo-runner.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RUNNER="charts/forgejo-runner"
DEVUMB="services/dev/prod"
DEV_VALUES="services/dev/prod/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
FEAT=".agents/plans/2026/2026-10-feat-forgejo-infra-and-runner"
SUPP="$FEAT/RESEARCH-dind-supplement.md"
RESEARCH="$FEAT/RESEARCH.md"
# Run 1's RESEARCH.md (the byte-identity source for the supplement). The
# worktree may be gone; the sha256 below is the fallback (fusion-plan
# recorded value).
RUN1_RESEARCH="/home/coder/.local/share/opencode/worktree/5e680f/feat-forgejo-infra-and-dev-runner-3/.agents/plans/2026/2026-10-feat-forgejo-infra-and-dev-runner/RESEARCH.md"
RUN1_SHA="917de3c1902099027acbba5fda379decdb81bf436f703d881d3cc459c16afeca"
# Pre-fusion RESEARCH.md minus its title line — the port inserts the pointer
# as line 2, so post-fusion `tail -n +3` must byte-match this baseline
# (the "nothing else in it changed" guard).
RESEARCH_REST_SHA="7d6b5d04276ada390a43d4338f6834aec2f9a133b4f1cc02047aba7afb3d3e52"
RESEARCH_TITLE="# RESEARCH — Forgejo Actions runner on the dev k3s cluster"
SUPP_HDR1="> Provenance: byte-identical copy of run 1's RESEARCH.md (ticket 2026/2026-10-feat-forgejo-infra-and-dev-runner, branch feat-forgejo-infra-and-dev-runner-3), ported by the 2026-10-23 fusion (port 4)."
SUPP_HDR2="> Path references inside are historical run-1-folder paths; this folder's RESEARCH.md remains the ticket's primary research."
SUPP_PTR="> DinD supplement (run 1, ported 2026-10-23): RESEARCH-dind-supplement.md — k3s MTU clone-failure warning (forgejo/runner#1779), ArgoCD-timeout rationale, reliability self-rating."

# Fusion Validation block's test UUIDs.
TEST_UUID_DEV="00000000-0000-0000-0000-000000000000"
TEST_UUID_INFRA="00000000-0000-0000-0000-000000000001"

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
  # Each branch prints exactly one path AND returns 0 — a missing return
  # falls through and concatenates a second path into $helm_bin (the on-PATH
  # branch did exactly that: false t1 red under the fusion Validation PATH,
  # F01 review finding 1).
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
  fail "t1: $RUNNER does not exist (the chart has not been created — nothing to dependency-update, lint, or render)"

# --- t1: dependency update (on a copy) + Chart.lock + lint (F01 c1) -------
skip_helm=0
runner_copy=""
if [ -z "$helm_bin" ]; then
  skip "t1: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; t1-t3 were not run"
  skip_helm=1
else
  runner_copy="$WORK/forgejo-runner-copy"
  cp -R "$RUNNER"/. "$runner_copy"/
  dep_log="$runner_copy/dependency-update.log"
  if ! (cd "$runner_copy" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "t1: helm dependency update could not reach the registry for $RUNNER here; t1-t3 were not run (log kept at $dep_log)"
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

# --- t2: two-controller render (F01 c2) -----------------------------------
runner_out=""
if [ "$skip_helm" -eq 1 ]; then
  skip "t2: render not run (dependency update unavailable)"
else
  runner_out="$WORK/runner-render.yaml"
  runner_err="$WORK/runner-render.err"
  if ! "$helm_bin" template "$runner_copy" \
      --set "bitwardenIds.forgejo-runner-token=$TEST_UUID_DEV" \
      --set "bitwardenIds.forgejo-runner-infra-token=$TEST_UUID_INFRA" \
    >"$runner_out" 2>"$runner_err"; then
    tail -n 30 "$runner_err" >&2
    fail "t2: helm template of $RUNNER failed (log kept at $runner_err)"
  fi
  [ -s "$runner_out" ] || fail "t2: helm template of $RUNNER rendered nothing"
  if python3 - "$runner_out" "$TEST_UUID_DEV" "$TEST_UUID_INFRA" "$WORK/runner-count" <<'PY'
import re, sys, yaml

render, uuid_dev, uuid_infra, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# Run 1's GitHub-parity act-image label set (conflict ruling 3) — the exact
# set both connections must advertise; the old node:lts/dev labels are gone.
ACT_LABELS = {
    'ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'ubuntu-24.04:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04',
    'docker:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'node22:docker://docker.io/library/node:22-bookworm',
}
# Chart defaults (F01 change 2) — the service slice overrides these at
# deploy time (F02), but the chart render must carry exactly these.
CHART_DEFAULT_URLS = {
    'runner-dev': 'http://dev-forgejo-http.default.svc:3000',
    'runner-infra': 'https://git.spencerslab.com',
}
TARGET_SECRETS = {'runner-dev': 'forgejo-runner-dev', 'runner-infra': 'forgejo-runner-infra'}
ITEM_UUIDS = {'runner-dev': uuid_dev, 'runner-infra': uuid_infra}
CONNECTION_NAMES = {'runner-dev': 'dev', 'runner-infra': 'infra'}
CONTROLLERS = ('runner-dev', 'runner-infra')

try:
    with open(render) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]

    sts = [d for d in docs if d.get('kind') == 'StatefulSet']
    deps = [d for d in docs if d.get('kind') == 'Deployment']
    if len(sts) != 2:
        bad(f't2: expected exactly two StatefulSets (runner-dev + runner-infra), found {len(sts)} — the fused chart reworks the single-controller C03 shape into two controllers')
    if deps:
        bad(f't2: the render also contains Deployment(s) {[(d.get("metadata") or {}).get("name") for d in deps]} — a Deployment is the rejected alternative')
    byctl = {}
    for s in sts:
        ctl = (((s.get('metadata') or {}).get('labels') or {}).get('app.kubernetes.io/controller'))
        byctl[ctl] = s
    if set(byctl) != set(CONTROLLERS):
        bad(f't2: the StatefulSet controller labels are {sorted(byctl)}, expected exactly [runner-dev, runner-infra]')
    ok('t2: exactly two StatefulSets — runner-dev + runner-infra, and no Deployment renders')

    for ctl in CONTROLLERS:
        s = byctl[ctl]
        spec = s.get('spec') or {}
        if spec.get('replicas') != 1:
            bad(f't2: {ctl} replicas is {spec.get("replicas")!r}, expected 1 (one (uuid, token) pair maps to exactly one pod; scaling means more runner records)')
        vcts = spec.get('volumeClaimTemplates') or []
        if len(vcts) != 2:
            bad(f't2: {ctl} has {len(vcts)} volumeClaimTemplates, expected exactly 2 (data + docker-data)')
        by = {(v.get('metadata') or {}).get('name'): (v.get('spec') or {}) for v in vcts}
        if set(by) != {'data', 'docker-data'}:
            bad(f't2: {ctl} volumeClaimTemplates are named {sorted(by)}, expected exactly [data, docker-data]')
        for name, size in (('data', '2Gi'), ('docker-data', '10Gi')):
            vspec = by[name]
            if (vspec.get('resources') or {}).get('requests', {}).get('storage') != size:
                bad(f't2: {ctl} VCT {name} requests {(vspec.get("resources") or {}).get("requests", {}).get("storage")!r}, expected {size}')
            if vspec.get('accessModes') != ['ReadWriteOnce']:
                bad(f't2: {ctl} VCT {name} accessModes are {vspec.get("accessModes")!r}, expected [ReadWriteOnce]')
            if vspec.get('storageClassName') != 'local-path':
                bad(f't2: {ctl} VCT {name} storageClassName is {vspec.get("storageClassName")!r}, expected local-path')
        ok(f't2: {ctl} — replicas 1, VCTs exactly data (2Gi) + docker-data (10Gi), both RWO local-path')

        pod = ((spec.get('template') or {}).get('spec')) or {}
        ics = pod.get('initContainers') or []
        dind = next((c for c in ics if (c or {}).get('name') == 'dind'), None)
        if dind is None:
            bad(f't2: {ctl} has no initContainer named dind (the DinD sidecar is missing)')
        if dind.get('image') != 'docker:29.9.1-dind':
            bad(f't2: {ctl} dind image is {dind.get("image")!r}, expected docker:29.9.1-dind')
        if dind.get('restartPolicy') != 'Always':
            bad(f't2: {ctl} dind restartPolicy is {dind.get("restartPolicy")!r}, expected Always (sidecar semantics — without it the pod dies when dockerd exits)')
        if ((dind.get('securityContext') or {}).get('privileged')) is not True:
            bad(f't2: {ctl} dind securityContext.privileged is not true (DinD requires it)')
        for probe in ('startupProbe', 'livenessProbe'):
            p = dind.get(probe)
            if not p:
                bad(f't2: {ctl} dind has no {probe} (the socket probe keeps the pod observable)')
            cmd = (p.get('exec') or {}).get('command')
            if cmd != ['test', '-S', '/var/run/docker.sock']:
                bad(f't2: {ctl} dind {probe} exec command is {cmd!r}, expected [test, -S, /var/run/docker.sock]')
        ok(f't2: {ctl} dind sidecar — docker:29.9.1-dind, restartPolicy Always, privileged, socket startup+liveness probes')

        cons = pod.get('containers') or []
        runner = next((c for c in cons if (c or {}).get('name') == 'runner'), None)
        if runner is None:
            bad(f't2: {ctl} has no container named runner')
        if runner.get('image') != 'data.forgejo.org/forgejo/runner:13.2.0':
            bad(f't2: {ctl} runner image is {runner.get("image")!r}, expected data.forgejo.org/forgejo/runner:13.2.0')
        rsc = runner.get('securityContext') or {}
        if (rsc.get('capabilities') or {}).get('drop') != ['ALL']:
            bad(f't2: {ctl} runner securityContext.capabilities.drop is {(rsc.get("capabilities") or {}).get("drop")!r}, expected [ALL] (only the dind sidecar is deliberately privileged)')
        if rsc.get('allowPrivilegeEscalation') is not False:
            bad(f't2: {ctl} runner securityContext.allowPrivilegeEscalation is not false')
        joined = ' '.join((runner.get('command') or []) + (runner.get('args') or []))
        if 'dumb-init' not in joined:
            bad(f't2: {ctl} command/args {joined!r} lack the explicit dumb-init (K8s `command` replaces the image entrypoint)')
        if 'daemon' not in joined:
            bad(f't2: {ctl} command/args {joined!r} do not run the daemon subcommand')
        if re.search(r'\bregister\b', joined):
            bad(f't2: {ctl} command/args {joined!r} contain a register subcommand (v13 registration is declarative-only — RESEARCH.md Q2)')
        env = {(e or {}).get('name'): e for e in runner.get('env') or []}
        cdir = (env.get('CREDENTIALS_DIRECTORY') or {}).get('value')
        if not cdir:
            bad(f't2: {ctl} runner has no CREDENTIALS_DIRECTORY env (config.yaml token_url references file:$CREDENTIALS_DIRECTORY/token)')
        if (env.get('DOCKER_HOST') or {}).get('value') != 'unix:///var/run/docker.sock':
            bad(f't2: {ctl} DOCKER_HOST is {(env.get("DOCKER_HOST") or {}).get("value")!r}, expected unix:///var/run/docker.sock (the in-pod socket)')
        # Env/mount consistency: the whole-secret mount lands where
        # CREDENTIALS_DIRECTORY says, and the config.yaml subPath lands where
        # the daemon's -c flag points. The creds volume is identified via the
        # subPath mount, so no path literal is assumed.
        toks = (runner.get('command') or []) + (runner.get('args') or [])
        cfg_path = None
        for i, t in enumerate(toks):
            if t in ('-c', '--config') and i + 1 < len(toks):
                cfg_path = toks[i + 1]
        if not cfg_path:
            bad(f't2: {ctl} command/args {joined!r} carry no -c/--config flag (the daemon must point at the rendered config.yaml)')
        mounts = runner.get('volumeMounts') or []
        subs = [m for m in mounts if (m or {}).get('subPath') == 'config.yaml']
        if len(subs) != 1:
            bad(f't2: {ctl} runner has {len(subs)} config.yaml subPath mount(s), expected exactly 1')
        creds_vol = subs[0].get('name')
        wholes = [m for m in mounts if (m or {}).get('name') == creds_vol and not (m or {}).get('subPath')]
        if len(wholes) != 1:
            bad(f't2: {ctl} runner has {len(wholes)} whole-volume mount(s) of the creds volume {creds_vol!r}, expected exactly 1 (the token file must land at CREDENTIALS_DIRECTORY)')
        if wholes[0].get('mountPath') != cdir:
            bad(f't2: {ctl} whole-secret mount is {wholes[0].get("mountPath")!r} but CREDENTIALS_DIRECTORY is {cdir!r}')
        if subs[0].get('mountPath') != cfg_path:
            bad(f't2: {ctl} config.yaml is mounted at {subs[0].get("mountPath")!r} but the daemon -c flag points at {cfg_path!r}')
        vols = {(v or {}).get('name'): v for v in pod.get('volumes') or []}
        sec_name = (((vols.get(creds_vol) or {}).get('secret') or {}).get('secretName'))
        if sec_name != TARGET_SECRETS[ctl]:
            bad(f't2: {ctl} creds volume {creds_vol!r} references Secret {sec_name!r}, expected {TARGET_SECRETS[ctl]!r} (each pod mounts its own target Secret)')
        ok(f't2: {ctl} runner — 13.2.0 pin, dumb-init daemon (no register), drop-ALL + no privilege escalation, CREDENTIALS_DIRECTORY/DOCKER_HOST and -c path consistent with the {TARGET_SECRETS[ctl]} mounts')

        bad_envs = []
        for c in ics + cons:
            for e in (c or {}).get('env') or []:
                n = (e or {}).get('name') or ''
                if n.startswith('GITEA_') or n in ('FORGEJO_RUNNER_REGISTRATION_TOKEN', 'FORGEJO_INSTANCE_URL'):
                    bad_envs.append(n)
        if bad_envs:
            bad(f't2: {ctl} pod carries registration-style env: {", ".join(sorted(set(bad_envs)))} (none of these work on runner v13 — RESEARCH.md Q2)')
        if pod.get('terminationGracePeriodSeconds') != 300:
            bad(f't2: {ctl} terminationGracePeriodSeconds is {pod.get("terminationGracePeriodSeconds")!r}, expected 300 (explicit short timeouts so ArgoCD syncs do not hang the pod — ruling 4)')
        psc = pod.get('securityContext') or {}
        if psc.get('fsGroup') != 1000:
            bad(f't2: {ctl} pod securityContext.fsGroup is {psc.get("fsGroup")!r}, expected 1000 (uid-1000 image vs node-owned fresh local-path VCT volumes)')
        if psc.get('fsGroupChangePolicy') != 'OnRootMismatch':
            bad(f't2: {ctl} pod securityContext.fsGroupChangePolicy is {psc.get("fsGroupChangePolicy")!r}, expected OnRootMismatch')
        ok(f't2: {ctl} pod — grace 300, fsGroup 1000 + OnRootMismatch, no registration env in any container')

    svcs = [d for d in docs if d.get('kind') == 'Service']
    for ctl in CONTROLLERS:
        hits = [d for d in svcs
                if ((d.get('spec') or {}).get('clusterIP') == 'None')
                and (((d.get('spec') or {}).get('selector') or {}).get('app.kubernetes.io/controller')) == ctl]
        if not hits:
            bad(f't2: no headless (clusterIP: None) service selects controller {ctl} — a StatefulSet requires one per controller')
    lb = [(d.get('metadata') or {}).get('name') for d in svcs if (d.get('spec') or {}).get('type') == 'LoadBalancer']
    if lb:
        bad(f't2: LoadBalancer Service(s) rendered: {lb} (the runners are client-only)')
    ings = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'Ingress']
    if ings:
        bad(f't2: Ingress(es) rendered: {ings} (the runners are client-only — no ingress by design)')
    cluster_roles = [((d.get('metadata') or {}).get('name'), d.get('kind'))
                     for d in docs if d.get('kind') in ('ClusterRole', 'ClusterRoleBinding')]
    if cluster_roles:
        bad(f't2: cluster-scoped RBAC rendered: {cluster_roles} (run 3\'s k8s-plugin surface was rejected — ruling 1)')
    ok('t2: headless service per controller; no Ingress, no LoadBalancer, no ClusterRole/ClusterRoleBinding')

    privileged = 0
    for s in sts:
        pod = (((s.get('spec') or {}).get('template') or {}).get('spec')) or {}
        for c in (pod.get('initContainers') or []) + (pod.get('containers') or []):
            if ((c or {}).get('securityContext') or {}).get('privileged') is True:
                privileged += 1
    if privileged != 2:
        bad(f't2: {privileged} privileged containers in the render, expected exactly 2 (one dind per pod — only deliberately privileged containers)')
    ok('t2: exactly 2 privileged containers (the two dind sidecars)')

    es_by = {}
    for d in docs:
        if d.get('kind') == 'ExternalSecret':
            es_by[((d.get('metadata') or {}).get('name'))] = d
    if set(es_by) != set(CONTROLLERS):
        bad(f't2: ExternalSecrets are {sorted(es_by)}, expected exactly [runner-dev, runner-infra] (secret-forgejo-runner.yaml splits into one per controller)')
    for ctl in CONTROLLERS:
        e = es_by[ctl]
        text = yaml.safe_dump(e)
        if 'bitwarden-login' not in text:
            bad(f't2: the {ctl} ExternalSecret does not use the bitwarden-login store')
        tname = (((e.get('spec') or {}).get('target') or {}).get('name'))
        if tname != TARGET_SECRETS[ctl]:
            bad(f't2: the {ctl} ExternalSecret target Secret is {tname!r}, expected {TARGET_SECRETS[ctl]!r}')
        pairs, keys = set(), set()
        def walk(node):
            if isinstance(node, dict):
                if 'remoteRef' in node and 'secretKey' in node:
                    rr = node.get('remoteRef') or {}
                    pairs.add((node['secretKey'], rr.get('property')))
                    keys.add(rr.get('key'))
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)
        walk(e)
        if ('uuid', 'username') not in pairs or ('token', 'password') not in pairs:
            bad(f't2: the {ctl} ExternalSecret remoteRefs are {sorted(pairs)}, expected uuid<-username and token<-password')
        if keys != {ITEM_UUIDS[ctl]}:
            bad(f't2: the {ctl} ExternalSecret remoteRef keys are {sorted(keys)}, expected exactly {ITEM_UUIDS[ctl]!r} (the {ctl} Bitwarden item UUID after --set)')
        data = (((e.get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
        if 'token' not in data:
            bad(f't2: the {ctl} ExternalSecret template data has no token key')
        elif data['token'] != '{{ .token }}':
            bad(f't2: the {ctl} ExternalSecret token template is {data["token"]!r}, expected {{{{ .token }}}}')
        if 'config.yaml' not in data:
            bad(f't2: the {ctl} ExternalSecret template data has no config.yaml key')
        else:
            try:
                cfg = yaml.safe_load(data['config.yaml'])
            except Exception as ex:
                bad(f't2: the {ctl} config.yaml template entry is not parseable YAML: {ex}')
            else:
                conns = (((cfg or {}).get('server') or {}).get('connections') or {})
                want = CONNECTION_NAMES[ctl]
                if set(conns) != {want}:
                    bad(f't2: the {ctl} config connections are {sorted(conns)}, expected exactly [{want}]')
                conn = conns[want]
                if conn.get('uuid') != '{{ .uuid }}':
                    bad(f't2: {want}.uuid is {conn.get("uuid")!r}, expected {{{{ .uuid }}}} (the only dynamic part)')
                if conn.get('url') != CHART_DEFAULT_URLS[ctl]:
                    bad(f't2: {want}.url is {conn.get("url")!r}, expected the chart default {CHART_DEFAULT_URLS[ctl]!r}')
                if conn.get('token_url') != 'file:$CREDENTIALS_DIRECTORY/token':
                    bad(f't2: {want}.token_url is {conn.get("token_url")!r}, expected file:$CREDENTIALS_DIRECTORY/token')
                if set(conn.get('labels') or []) != ACT_LABELS:
                    bad(f't2: {want}.labels are {conn.get("labels")!r}, expected the 5-label act set (ruling 3)')
                runner_cfg = (cfg or {}).get('runner') or {}
                if runner_cfg.get('timeout') != '30m':
                    bad(f't2: {ctl} config runner.timeout is {runner_cfg.get("timeout")!r}, expected 30m (ruling 4)')
                if runner_cfg.get('shutdown_timeout') != '5m':
                    bad(f't2: {ctl} config runner.shutdown_timeout is {runner_cfg.get("shutdown_timeout")!r}, expected 5m (ruling 4)')
        ok(f't2: ExternalSecret {ctl} — bitwarden-login, target {TARGET_SECRETS[ctl]}, uuid(username)+token(password) from the {ctl} item, token + config.yaml with the act label set, timeout 30m, shutdown_timeout 5m, chart-default url')

    raw = open(render).read()
    if 'OVERRIDE_' in raw:
        bad('t2: the rendered output still carries an OVERRIDE_* sentinel after --set of both bitwardenIds tokens')
    ok('t2: zero OVERRIDE_* in the rendered output after --set of both sentinel UUIDs')

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
fi

# --- t3: URL override probe (F01 c3) ---------------------------------------
if [ "$skip_helm" -eq 1 ]; then
  skip "t3: URL override probe not run (dependency update unavailable)"
else
  probe_out="$WORK/runner-probe.yaml"
  probe_err="$WORK/runner-probe.err"
  if ! "$helm_bin" template "$runner_copy" \
      --set "bitwardenIds.forgejo-runner-token=$TEST_UUID_DEV" \
      --set "bitwardenIds.forgejo-runner-infra-token=$TEST_UUID_INFRA" \
      --set "runners.infra.url=https://example.test" \
    >"$probe_out" 2>"$probe_err"; then
    tail -n 30 "$probe_err" >&2
    fail "t3: helm template of $RUNNER with the runners.infra.url override failed (log kept at $probe_err)"
  fi
  if python3 - "$probe_out" "$WORK/probe-count" <<'PY'
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

# Connection name per controller (F01: names stay dev / infra).
CONNECTIONS = {'runner-dev': 'dev', 'runner-infra': 'infra'}
# After the probe, infra must carry the probe value, dev must be untouched.
WANT = {'runner-dev': 'http://dev-forgejo-http.default.svc:3000',
        'runner-infra': 'https://example.test'}

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    for d in docs:
        if d.get('kind') != 'ExternalSecret':
            continue
        name = (d.get('metadata') or {}).get('name')
        if name not in CONNECTIONS:
            continue
        data = (((d.get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
        cfg = yaml.safe_load(data.get('config.yaml') or '')
        conn = (((cfg or {}).get('server') or {}).get('connections') or {}).get(CONNECTIONS[name])
        if not isinstance(conn, dict):
            bad(f't3: ExternalSecret {name} has no server.connections.{CONNECTIONS[name]}')
        if conn.get('url') != WANT[name]:
            bad(f't3: after --set runners.infra.url=https://example.test, {name} connection url is {conn.get("url")!r}, expected {WANT[name]!r} (values-driven URL templating)')
    ok('t3: --set runners.infra.url=https://example.test moves only the infra connection url; the dev url is unchanged (values-driven)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the probe render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/probe-count")))
  else
    exit 1
  fi
fi

# --- t4: renovate built-in helm-values extraction (F01 c4) -----------------
# FRICTION-ported recipe: bundled renovate 44.115.13 (npx cache), --platform=local
# (localDir = cwd), --dry-run, against a minimal /tmp git repo holding the
# chart + the repo renovate.json. The pinned CLI exits non-zero on modern
# node (unsupported-node warning) even on a successful scan, so the assertion
# gates on the extraction lines, not the exit code.
if ! command -v npx >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
  skip "t4: node/npx not available; the renovate dry-run was not run"
else
  t4_repo="$WORK/renovate-repo"
  mkdir -p "$t4_repo/charts"
  if ! git -C "$t4_repo" init -q -b main \
      && git -C "$t4_repo" config user.email renovate-test@example.com \
      && git -C "$t4_repo" config user.name renovate-test; then
    skip "t4: could not initialize the minimal /tmp git repo; the renovate dry-run was not run"
  else
    cp -R "$RUNNER"/. "$t4_repo/charts/forgejo-runner/"
    rm -rf "$t4_repo/charts/forgejo-runner/charts"  # vendored deps stay out of the scan
    cp renovate.json "$t4_repo/"
    git -C "$t4_repo" add -A
    git -C "$t4_repo" commit -qm extract-test
    ren_log="$t4_repo/renovate-dry-run.log"
    rc=0
    ( cd "$t4_repo" && LOG_LEVEL=debug timeout 300 \
        npx --yes renovate@44.115.13 --platform=local --dry-run=true \
        >"$ren_log" 2>&1 ) || rc=$?
    if [ "$rc" -eq 124 ]; then
      skip "t4: the renovate dry-run timed out at 300s (network conditions — log kept at $ren_log)"
    elif ! grep -q 'renovateVersion' "$ren_log"; then
      skip "t4: the bundled renovate CLI did not start (npx fetch failed? log kept at $ren_log)"
    else
      for needle in \
        'for manager helm-values' \
        '"depName": "data.forgejo.org/forgejo/runner"' \
        '"depName": "docker"' \
        '"packageFile": "charts/forgejo-runner/values.yaml"'; do
        grep -qF -- "$needle" "$ren_log" ||
          fail "t4: the renovate dry-run log (kept at $ren_log) shows no extraction of $needle by the built-in helm-values manager (both image pins must be tracked)"
      done
      ok "t4: renovate dry-run (bundled 44.115.13 CLI, minimal repo) extracts both image pins via the built-in helm-values manager"
    fi
  fi
fi

# --- t5: chart sentinels + dev trio (F01 t5) -------------------------------
if python3 - "$RUNNER/values.yaml" "$DEV_VALUES" "$WORK/t5-count" <<'PY'
import re, sys, yaml

chart_vals, dev_vals, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

SENTINEL = 'OVERRIDE_VIA_CUSTOM_VALUES'
WANT = {'forgejo-runner-token', 'forgejo-runner-infra-token'}

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
    bw = (load(chart_vals).get('bitwardenIds') or {})
    if set(bw) != WANT:
        bad(f't5: {chart_vals} bitwardenIds keys are {sorted(bw)}, expected exactly [forgejo-runner-token, forgejo-runner-infra-token] (one per controller; the 2<->2 custom-values parity is F02 t8)')
    for k in sorted(WANT):
        if bw[k] != SENTINEL:
            bad(f't5: {chart_vals} bitwardenIds.{k} is {bw[k]!r}, expected {SENTINEL} (the repo sentinel — the real UUIDs live only in custom-values/dev)')
    ok(f't5: {chart_vals} carries exactly the two bitwardenIds sentinels')

    sv = load(dev_vals)
    fr = (sv.get('charts') or {}).get('forgejo-runner')
    if not isinstance(fr, dict):
        bad(f't5: {dev_vals} has no charts.forgejo-runner entry (trio: chart leg missing)')
    if fr.get('namespace') != 'default' or str(fr.get('ServerSideApply')) != 'false':
        bad(f't5: charts.forgejo-runner entry is {fr!r}, expected namespace default + ServerSideApply "false"')
    ok(f't5: {dev_vals} carries charts.forgejo-runner (namespace default, ServerSideApply "false")')

    # The client-only rationale must be documented next to the entry, or the
    # next reader assumes the missing ingress leg is an oversight.
    with open(dev_vals) as f:
        lines = f.read().splitlines()
    idxs = [i for i, l in enumerate(lines) if re.match(r'^\s*forgejo-runner:\s*$', l)]
    if not idxs:
        bad(f't5: {dev_vals} has no forgejo-runner: line under charts:')
    else:
        idx = idxs[0]
        comments = []
        # The full contiguous comment block above the entry (a multi-line
        # rationale is the natural way to document this).
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
            bad(f't5: the charts.forgejo-runner entry has no comment explaining the deliberately missing ingress/proxy leg (client-only service)')
        ok(f't5: the charts.forgejo-runner entry carries the client-only comment (missing ingress/proxy leg)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't5: the static chart/dev checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t5-count")))
else
  exit 1
fi

# --- t6: doc ports (F01 t6) -------------------------------------------------
[ -f "$SUPP" ] ||
  fail "t6: $SUPP is missing (fusion port 4: run 1's RESEARCH.md was not ported as the byte-identical supplement)"
l1=$(sed -n '1p' "$SUPP")
l2=$(sed -n '2p' "$SUPP")
l3=$(sed -n '3p' "$SUPP")
[ "$l1" = "$SUPP_HDR1" ] ||
  fail "t6: $SUPP line 1 is '$l1' — expected the exact provenance header line 1"
[ "$l2" = "$SUPP_HDR2" ] ||
  fail "t6: $SUPP line 2 is '$l2' — expected the exact provenance header line 2"
[ -z "$l3" ] ||
  fail "t6: $SUPP line 3 is not blank (the header is 2 lines + exactly one blank line before the body)"
supp_sha=$(tail -n +4 "$SUPP" | sha256sum | awk '{print $1}')
[ "$supp_sha" = "$RUN1_SHA" ] ||
  fail "t6: $SUPP body (tail -n +4) sha256 is $supp_sha, expected $RUN1_SHA (run 1's RESEARCH.md, byte-identical)"
if [ -f "$RUN1_RESEARCH" ]; then
  cmp -s <(tail -n +4 "$SUPP") "$RUN1_RESEARCH" ||
    fail "t6: $SUPP body (tail -n +4) differs byte-for-byte from run 1's RESEARCH.md at $RUN1_RESEARCH"
fi
ok "t6: RESEARCH-dind-supplement.md — exact 2-line provenance header + byte-identical run-1 body (sha256 $RUN1_SHA)"

[ -f "$RESEARCH" ] || fail "t6: $RESEARCH is missing"
r1=$(sed -n '1p' "$RESEARCH")
r2=$(sed -n '2p' "$RESEARCH")
[ "$r1" = "$RESEARCH_TITLE" ] ||
  fail "t6: $RESEARCH line 1 is '$r1' — expected the title line (the pointer inserts as line 2, nothing before it)"
[ "$r2" = "$SUPP_PTR" ] ||
  fail "t6: $RESEARCH line 2 is '$r2' — expected the exact dinD-supplement pointer line immediately after the title"
rest_sha=$(tail -n +3 "$RESEARCH" | sha256sum | awk '{print $1}')
[ "$rest_sha" = "$RESEARCH_REST_SHA" ] ||
  fail "t6: $RESEARCH content below the pointer changed (sha256 $rest_sha, expected $RESEARCH_REST_SHA) — the doc port is a one-line pointer, nothing else"
ok "t6: $RESEARCH carries the pointer line immediately after the title and nothing else changed"

# --- t7: F02 second sentinel slot (F02 t1) ----------------------------------
if python3 - "$DEV_CV" "$WORK/t7-count" <<'PY'
import re, sys, yaml

dev_cv, count_file = sys.argv[1], sys.argv[2]
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
    # Same lenient anchor handling as the other loaders (see t5).
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    slot = ((load(dev_cv).get('forgejo-runner') or {}).get('bitwardenIds') or {}).get('forgejo-runner-infra-token')
    if slot is None:
        bad(f't7: {dev_cv} has no forgejo-runner.bitwardenIds.forgejo-runner-infra-token slot (the infra runner registration would have nowhere to put its UUID — plan User action 7)')
    elif slot == SENTINEL:
        bad(f't7: {dev_cv} forgejo-runner-infra-token is the service sentinel {SENTINEL} — a real UUID or the documented OVERRIDE_NEEDED placeholder, never the service sentinel')
    elif not (slot == 'OVERRIDE_NEEDED' or UUID_RE.match(str(slot))):
        bad(f't7: {dev_cv} forgejo-runner-infra-token is {slot!r} — not a UUID and not the documented OVERRIDE_NEEDED placeholder')
    else:
        ok(f't7: {dev_cv} carries the forgejo-runner-infra-token slot ({slot if slot == "OVERRIDE_NEEDED" else "a real UUID"})')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't7: the second-slot check could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t7-count")))
else
  exit 1
fi

# --- t8: sentinel parity 2<->2 (F02 t2) -------------------------------------
if python3 - "$RUNNER/values.yaml" "$DEV_CV" "$WORK/t8-count" <<'PY'
import re, sys, yaml

chart_vals, dev_cv, count_file = sys.argv[1:4]
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
WANT = {'forgejo-runner-token', 'forgejo-runner-infra-token'}

def load(path):
    # Same lenient anchor handling as the other loaders (see t5).
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    chart_bw = (load(chart_vals).get('bitwardenIds') or {})
    slots = ((load(dev_cv).get('forgejo-runner') or {}).get('bitwardenIds') or {})
    if set(chart_bw) != WANT:
        bad(f't8: {chart_vals} bitwardenIds keys are {sorted(chart_bw)}, expected exactly the two sentinels (2<->2 parity)')
    if set(slots) != WANT:
        bad(f't8: {dev_cv} forgejo-runner.bitwardenIds slots are {sorted(slots)}, expected exactly {sorted(WANT)} — one per chart sentinel')
    for k in sorted(WANT):
        v = slots[k]
        if v == SENTINEL:
            bad(f't8: {dev_cv} {k} still carries the service sentinel {SENTINEL} — parity requires a real UUID or OVERRIDE_NEEDED')
        elif not (v == 'OVERRIDE_NEEDED' or UUID_RE.match(str(v))):
            bad(f't8: {dev_cv} {k} is {v!r} — not a UUID and not the documented OVERRIDE_NEEDED placeholder')
    ok('t8: sentinel parity 2<->2 — both chart sentinels match custom-values/dev slots (UUID or OVERRIDE_NEEDED, never the service sentinel)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't8: the parity check could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t8-count")))
else
  exit 1
fi

# --- t9: F02 dev-umbrella render (F02 t3) -----------------------------------
if [ -z "$helm_bin" ]; then
  skip "t9: dev umbrella render not run (no helm binary)"
else
  dev_out="$WORK/dev-render.yaml"
  dev_err="$WORK/dev-render.err"
  # F02's exact acceptance command: the whole custom-values file is -f, and
  # the two runner-token slots are --set to the test UUIDs (they override the
  # -f file's OVERRIDE_NEEDED placeholder).
  if ! "$helm_bin" template dev "$DEVUMB" \
      -f "$DEV_CV" \
      --set domain=scifi.farm --set clusterName=dev \
      --set "forgejo-runner.bitwardenIds.forgejo-runner-token=$TEST_UUID_DEV" \
      --set "forgejo-runner.bitwardenIds.forgejo-runner-infra-token=$TEST_UUID_INFRA" \
    >"$dev_out" 2>"$dev_err"; then
    tail -n 30 "$dev_err" >&2
    fail "t9: helm template of $DEVUMB with -f custom-values failed (log kept at $dev_err)"
  fi
  [ -s "$dev_out" ] || fail "t9: helm template of $DEVUMB rendered nothing"
  if python3 - "$dev_out" "$TEST_UUID_DEV" "$TEST_UUID_INFRA" "$WORK/dev-count" <<'PY'
import sys, yaml

render, uuid_dev, uuid_infra, count_file = sys.argv[1:5]
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
        bad('t9: no ApplicationSet named dev-appset in the dev render')
    els = appsets[0]['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
    vals = (els[0] if els else {}).get('values')
    if not isinstance(vals, dict):
        bad('t9: the dev-appset generator element has no values blob')

    runners = ((vals.get('charts') or {}).get('forgejo-runner') or {}).get('runners') or {}
    dev_url = ((runners.get('dev') or {}).get('url'))
    infra_url = ((runners.get('infra') or {}).get('url'))
    if dev_url != 'http://dev-forgejo-http:3000':
        bad(f't9: the dev-appset values blob has charts.forgejo-runner.runners.dev.url {dev_url!r}, expected http://dev-forgejo-http:3000 (the live-verified in-cluster target — the F02 URL pin is missing or wrong)')
    if infra_url != 'https://git.spencerslab.com':
        bad(f't9: the dev-appset values blob has charts.forgejo-runner.runners.infra.url {infra_url!r}, expected https://git.spencerslab.com (the infra instance host)')
    ok('t9: dev-appset values blob pins both connection URLs (dev http://dev-forgejo-http:3000, infra https://git.spencerslab.com)')

    bw = ((vals.get('forgejo-runner') or {}).get('bitwardenIds') or {})
    if bw.get('forgejo-runner-token') != uuid_dev:
        bad(f't9: the dev-appset values blob has forgejo-runner.bitwardenIds.forgejo-runner-token {bw.get("forgejo-runner-token")!r}, expected the --set UUID {uuid_dev} (resolved, not a placeholder)')
    if bw.get('forgejo-runner-infra-token') != uuid_infra:
        bad(f't9: the dev-appset values blob has forgejo-runner.bitwardenIds.forgejo-runner-infra-token {bw.get("forgejo-runner-infra-token")!r}, expected the --set UUID {uuid_infra} (resolved, not a placeholder)')
    ok('t9: dev-appset values blob carries both resolved runner-token UUIDs')

    subs = (vals.get('ingress') or {}).get('subdomains') or {}
    if set(subs) != {'coder', 'git', 'research', 'cluster'}:
        bad(f't9: dev ingress.subdomains are {sorted(subs)}, expected exactly [coder, git, research, cluster] — the runners are client-only, so they get NO ingress entry')
    ok('t9: dev ingress.subdomains is unchanged (coder/git/research/cluster — no runner entry)')

    # Sentinels may remain only inside the appset-generator resource (the
    # values blob, where per-app placeholders ride to the base chart); the
    # service sentinel must not survive anywhere, and no other rendered
    # resource may carry any OVERRIDE_ string.
    raw = open(render).read()
    if 'OVERRIDE_VIA_CUSTOM_VALUES' in raw:
        bad('t9: the rendered dev umbrella still carries the OVERRIDE_VIA_CUSTOM_VALUES service sentinel (the -f/--set list did not resolve it)')
    for d in docs:
        if d.get('kind') == 'ApplicationSet':
            continue
        t = yaml.safe_dump(d)
        if 'OVERRIDE_' in t:
            bad(f"t9: non-appset document {((d.get('metadata') or {}).get('name'))!r} carries an OVERRIDE_* string — only the appset-generator resource may hold per-app placeholders")
    ok('t9: no OVERRIDE_ outside appset-generator resources; the service sentinel does not survive the render')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't9: the dev render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/dev-count")))
  else
    exit 1
  fi
fi

# --- t10: F02 updated trio-deviation comment (F02 t4) -----------------------
if python3 - "$DEV_VALUES" "$WORK/t10-count" <<'PY'
import re, sys

dev_vals, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    with open(dev_vals) as f:
        lines = f.read().splitlines()
    idxs = [i for i, l in enumerate(lines) if re.match(r'^\s*forgejo-runner:\s*$', l)]
    if not idxs:
        bad('t10: ' + dev_vals + ' has no forgejo-runner: line under charts:')
    else:
        idx = idxs[0]
        comments = []
        j = idx - 1
        while j >= 0 and lines[j].lstrip().startswith('#'):
            comments.append(lines[j])
            j -= 1
        for l in lines[idx + 1:]:
            s = l.strip()
            if s.startswith('#'):
                comments.append(s)
            elif s:
                break
        block = '\n'.join(comments)
        if not any(re.search(r'ingress|proxy', c, re.IGNORECASE) for c in comments):
            bad('t10: the charts.forgejo-runner entry has no comment explaining the deliberately missing ingress/proxy leg')
        # F02 updates the comment to cover BOTH controllers; the pre-F02
        # single-runner wording (mentions ingress/proxy but not both
        # controllers) must fail here.
        covers_both = (re.search(r'runner-dev', block) and re.search(r'runner-infra', block)) \
            or re.search(r'\bboth\b', block, re.IGNORECASE)
        if not covers_both:
            bad('t10: the trio-deviation comment does not cover BOTH controllers — name runner-dev + runner-infra, or state "both" (the F02 comment update is missing)')
        ok('t10: the charts.forgejo-runner trio-deviation comment covers both controllers (still no ingress entry)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't10: the comment check could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t10-count")))
else
  exit 1
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: dev-forgejo-runner checks (%d ok)\n' "$checks"
