#!/usr/bin/env bash
# C01 contract (2026-10-refactor-forgejo-runner-per-instance) for
# charts/forgejo-runner as a SINGLE-runner chart: exactly one StatefulSet
# + one dind sidecar per release, all resources named after the release
# name, one ExternalSecret per release (bitwarden-login; uuid<-username,
# token<-password), one server.connections.default entry in config.yaml
# (5-label act set, timeout 30m, shutdown_timeout 5m), hardened runner
# (13.2.0 pin, dumb-init daemon, drop ALL, no register, no registration
# env), VCTs data 2Gi + docker-data 10Gi local-path, grace 300 + fsGroup
# 1000, no Ingress/LoadBalancer/cluster RBAC — deployed TWICE by the dev
# ApplicationSet via the chart: alias (charts.forgejo-runner-dev +
# charts.forgejo-runner-infra, both chart: forgejo-runner), per-app URLs in
# TOP-LEVEL slices (the only values the appset merge flows), and the single
# bitwardenIds.runner-token sentinel with 1<->2 custom-values parity. The
# base-chart ground-truth render proves the values flow.
# Supersession (2026-10-25 user decision, ticket 2026-10-feat-forgejo-auth-
# support): dev deploys forgejo-runner-dev ONLY — the forgejo-runner-infra
# alias, its top-level slice and its custom-values slot are un-wired from the
# deployed surface (infra runner relocation pending). The chart keeps the
# multi-instance capability, so the chart-level legs (t1-t4, t5's chart-
# sentinel leg) are unchanged; the dev-deployed-slice legs (t5/t7-t10) assert
# the single aliased app.
#
# Contract source: chunks/C01.md Tests list (t1-t10) — ONE script stays the
# runner contract (predecessor ruling, DECISIONS.md).
#
# The chart is rendered from a COPY under /tmp/opencode after
# `helm dependency update` there (repo convention: charts/**/charts is
# gitignored, Chart.lock is committed) — the worktree is never written.
#
# A helm binary is taken from HELM_BIN, the PATH, /home/coder/.local/bin,
# or /tmp/opencode; failing that, helm v3.21.4 is downloaded there (same
# provenance as tests/services/dev-git-auth.sh). If the registry is
# unreachable, t1-t3 and t10 are skipped (t4-t9 still run — t4 needs only
# node/npx, t5-t9 need no registry).
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
# t9/t10 read the expected runner-token UUIDs from custom-values/dev at run
# time: the test asserts slot existence + flow, never the UUID values.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/dev-forgejo-runner.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RUNNER="charts/forgejo-runner"
DEVUMB="services/dev/prod"
DEV_VALUES="services/dev/prod/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
BASE="charts/base"
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

# One test UUID per release, so the remoteRef key assertions can tie each
# rendered ExternalSecret to that release's --set item.
TEST_UUID_DEV="00000000-0000-0000-0000-000000000000"
TEST_UUID_INFRA="00000000-0000-0000-0000-000000000001"
RELEASE_DEV="dev-forgejo-runner-dev"
RELEASE_INFRA="dev-forgejo-runner-infra"

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

# --- t1: dependency update (on a copy) + Chart.lock + lint (C01 c1) -------
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

# --- t2: single-instance render per release (C01 c2) ----------------------
if [ "$skip_helm" -eq 1 ]; then
  skip "t2: render not run (dependency update unavailable)"
else
  runner_out_dev="$WORK/runner-render-dev.yaml"
  runner_out_infra="$WORK/runner-render-infra.yaml"
  if ! "$helm_bin" template "$RELEASE_DEV" "$runner_copy" \
      --set "bitwardenIds.runner-token=$TEST_UUID_DEV" \
    >"$runner_out_dev" 2>"$WORK/runner-render-dev.err"; then
    tail -n 30 "$WORK/runner-render-dev.err" >&2
    fail "t2: helm template of $RUNNER (release $RELEASE_DEV) failed (log kept at $WORK/runner-render-dev.err)"
  fi
  if ! "$helm_bin" template "$RELEASE_INFRA" "$runner_copy" \
      --set "bitwardenIds.runner-token=$TEST_UUID_INFRA" \
    >"$runner_out_infra" 2>"$WORK/runner-render-infra.err"; then
    tail -n 30 "$WORK/runner-render-infra.err" >&2
    fail "t2: helm template of $RUNNER (release $RELEASE_INFRA) failed (log kept at $WORK/runner-render-infra.err)"
  fi
  [ -s "$runner_out_dev" ] || fail "t2: helm template (release $RELEASE_DEV) rendered nothing"
  [ -s "$runner_out_infra" ] || fail "t2: helm template (release $RELEASE_INFRA) rendered nothing"
  if python3 - "$runner_out_dev" "$runner_out_infra" "$RELEASE_DEV" "$RELEASE_INFRA" "$TEST_UUID_DEV" "$TEST_UUID_INFRA" "$WORK/runner-count" <<'PY'
import re, sys, yaml

(render_dev, render_infra, rel_dev, rel_infra,
 uuid_dev, uuid_infra, count_file) = sys.argv[1:8]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# GitHub-parity act-image label set (conflict ruling 3) — the exact set the
# single connection must advertise.
ACT_LABELS = {
    'ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'ubuntu-24.04:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04',
    'docker:docker://ghcr.io/catthehacker/ubuntu:act-24.04',
    'node22:docker://docker.io/library/node:22-bookworm',
}
# Chart default runner.url — the standalone-render stand-in; the per-app
# top-level slices override it at deploy time.
CHART_DEFAULT_URL = 'http://dev-forgejo-http.default.svc:3000'

try:
    def by_kind(docs, kind):
        return [d for d in docs if d.get('kind') == kind]

    def check_release(render_file, release, uuid):
        raw = open(render_file).read()
        docs = [d for d in yaml.safe_load_all(raw) if d]

        deps = by_kind(docs, 'Deployment')
        if deps:
            bad(f't2: {release} — the render contains Deployment(s) {[(d.get("metadata") or {}).get("name") for d in deps]} (a Deployment is the rejected alternative)')
        for kind in ('ServiceAccount', 'StatefulSet', 'Service', 'ExternalSecret'):
            got = [(d.get('metadata') or {}).get('name') for d in by_kind(docs, kind)]
            if len(got) != 1 or got[0] != release:
                bad(f't2: {release} — {kind} names are {got}, expected exactly one named {release!r} (one runner per release; app-template 5.0.1 names single-resource kinds exactly after the release)')
        ok(f't2: {release} — exactly one SA/STS/Service/ExternalSecret, all named {release!r}; no Deployment')

        spec = (by_kind(docs, 'StatefulSet')[0].get('spec')) or {}
        if spec.get('replicas') != 1:
            bad(f't2: {release} — replicas is {spec.get("replicas")!r}, expected 1 (one (uuid, token) pair maps to exactly one pod; scaling means more runner records)')
        vcts = spec.get('volumeClaimTemplates') or []
        if len(vcts) != 2:
            bad(f't2: {release} — {len(vcts)} volumeClaimTemplates, expected exactly 2 (data + docker-data)')
        vby = {(v.get('metadata') or {}).get('name'): (v.get('spec') or {}) for v in vcts}
        if set(vby) != {'data', 'docker-data'}:
            bad(f't2: {release} — volumeClaimTemplates named {sorted(vby)}, expected exactly [data, docker-data]')
        for name, size in (('data', '2Gi'), ('docker-data', '10Gi')):
            vspec = vby[name]
            if (vspec.get('resources') or {}).get('requests', {}).get('storage') != size:
                bad(f't2: {release} — VCT {name} requests {(vspec.get("resources") or {}).get("requests", {}).get("storage")!r}, expected {size}')
            if vspec.get('accessModes') != ['ReadWriteOnce']:
                bad(f't2: {release} — VCT {name} accessModes are {vspec.get("accessModes")!r}, expected [ReadWriteOnce]')
            if vspec.get('storageClassName') != 'local-path':
                bad(f't2: {release} — VCT {name} storageClassName is {vspec.get("storageClassName")!r}, expected local-path')
        ok(f't2: {release} — replicas 1, VCTs exactly data (2Gi) + docker-data (10Gi), both RWO local-path')

        pod = ((spec.get('template') or {}).get('spec')) or {}
        ics = pod.get('initContainers') or []
        dind = next((c for c in ics if (c or {}).get('name') == 'dind'), None)
        if dind is None:
            bad(f't2: {release} — no initContainer named dind (the DinD sidecar is missing)')
        if dind.get('image') != 'docker:29.9.1-dind':
            bad(f't2: {release} — dind image is {dind.get("image")!r}, expected docker:29.9.1-dind')
        if dind.get('restartPolicy') != 'Always':
            bad(f't2: {release} — dind restartPolicy is {dind.get("restartPolicy")!r}, expected Always (sidecar semantics — without it the pod dies when dockerd exits)')
        if ((dind.get('securityContext') or {}).get('privileged')) is not True:
            bad(f't2: {release} — dind securityContext.privileged is not true (DinD requires it)')
        for probe in ('startupProbe', 'livenessProbe'):
            p = dind.get(probe)
            if not p:
                bad(f't2: {release} — dind has no {probe} (the socket probe keeps the pod observable)')
            if (p.get('exec') or {}).get('command') != ['test', '-S', '/var/run/docker.sock']:
                bad(f't2: {release} — dind {probe} exec command is {(p.get("exec") or {}).get("command")!r}, expected [test, -S, /var/run/docker.sock]')
        ok(f't2: {release} — dind sidecar — docker:29.9.1-dind, restartPolicy Always, privileged, socket startup+liveness probes')

        cons = pod.get('containers') or []
        runner = next((c for c in cons if (c or {}).get('name') == 'runner'), None)
        if runner is None:
            bad(f't2: {release} — no container named runner')
        if runner.get('image') != 'data.forgejo.org/forgejo/runner:13.2.0':
            bad(f't2: {release} — runner image is {runner.get("image")!r}, expected data.forgejo.org/forgejo/runner:13.2.0')
        rsc = runner.get('securityContext') or {}
        if (rsc.get('capabilities') or {}).get('drop') != ['ALL']:
            bad(f't2: {release} — runner securityContext.capabilities.drop is {(rsc.get("capabilities") or {}).get("drop")!r}, expected [ALL] (only the dind sidecar is deliberately privileged)')
        if rsc.get('allowPrivilegeEscalation') is not False:
            bad(f't2: {release} — runner securityContext.allowPrivilegeEscalation is not false')
        joined = ' '.join((runner.get('command') or []) + (runner.get('args') or []))
        if 'dumb-init' not in joined:
            bad(f't2: {release} — command/args {joined!r} lack the explicit dumb-init (K8s `command` replaces the image entrypoint)')
        if 'daemon' not in joined:
            bad(f't2: {release} — command/args {joined!r} do not run the daemon subcommand')
        if re.search(r'\bregister\b', joined):
            bad(f't2: {release} — command/args {joined!r} contain a register subcommand (v13 registration is declarative-only — RESEARCH.md Q2)')
        env = {(e or {}).get('name'): e for e in runner.get('env') or []}
        cdir = (env.get('CREDENTIALS_DIRECTORY') or {}).get('value')
        if not cdir:
            bad(f't2: {release} — runner has no CREDENTIALS_DIRECTORY env (config.yaml token_url references file:$CREDENTIALS_DIRECTORY/token)')
        if (env.get('DOCKER_HOST') or {}).get('value') != 'unix:///var/run/docker.sock':
            bad(f't2: {release} — DOCKER_HOST is {(env.get("DOCKER_HOST") or {}).get("value")!r}, expected unix:///var/run/docker.sock (the in-pod socket)')
        # Env/mount consistency: the whole-secret mount lands where
        # CREDENTIALS_DIRECTORY says, and the config.yaml subPath lands where
        # the daemon's -c flag points. The creds volume is identified via
        # the subPath mount, so no path literal is assumed.
        toks = (runner.get('command') or []) + (runner.get('args') or [])
        cfg_path = None
        for i, t in enumerate(toks):
            if t in ('-c', '--config') and i + 1 < len(toks):
                cfg_path = toks[i + 1]
        if not cfg_path:
            bad(f't2: {release} — command/args {joined!r} carry no -c/--config flag (the daemon must point at the rendered config.yaml)')
        mounts = runner.get('volumeMounts') or []
        subs = [m for m in mounts if (m or {}).get('subPath') == 'config.yaml']
        if len(subs) != 1:
            bad(f't2: {release} — runner has {len(subs)} config.yaml subPath mount(s), expected exactly 1')
        creds_vol = subs[0].get('name')
        wholes = [m for m in mounts if (m or {}).get('name') == creds_vol and not (m or {}).get('subPath')]
        if len(wholes) != 1:
            bad(f't2: {release} — runner has {len(wholes)} whole-volume mount(s) of the creds volume {creds_vol!r}, expected exactly 1 (the token file must land at CREDENTIALS_DIRECTORY)')
        if wholes[0].get('mountPath') != cdir:
            bad(f't2: {release} — whole-secret mount is {wholes[0].get("mountPath")!r} but CREDENTIALS_DIRECTORY is {cdir!r}')
        if subs[0].get('mountPath') != cfg_path:
            bad(f't2: {release} — config.yaml is mounted at {subs[0].get("mountPath")!r} but the daemon -c flag points at {cfg_path!r}')
        vols = {(v or {}).get('name'): v for v in pod.get('volumes') or []}
        sec_name = (((vols.get(creds_vol) or {}).get('secret') or {}).get('secretName'))
        if sec_name != release:
            bad(f't2: {release} — creds volume {creds_vol!r} references Secret {sec_name!r}, expected {release!r} (each release mounts its own release-named target Secret)')
        ok(f't2: {release} — runner — 13.2.0 pin, dumb-init daemon (no register), drop-ALL + no privilege escalation, CREDENTIALS_DIRECTORY/DOCKER_HOST and -c path consistent with the {release} mounts')

        bad_envs = []
        for c in ics + cons:
            for e in (c or {}).get('env') or []:
                n = (e or {}).get('name') or ''
                if n.startswith('GITEA_') or n in ('FORGEJO_RUNNER_REGISTRATION_TOKEN', 'FORGEJO_INSTANCE_URL'):
                    bad_envs.append(n)
        if bad_envs:
            bad(f't2: {release} — pod carries registration-style env: {", ".join(sorted(set(bad_envs)))} (none of these work on runner v13 — RESEARCH.md Q2)')
        if pod.get('terminationGracePeriodSeconds') != 300:
            bad(f't2: {release} — terminationGracePeriodSeconds is {pod.get("terminationGracePeriodSeconds")!r}, expected 300 (explicit short timeouts so ArgoCD syncs do not hang the pod — ruling 4)')
        psc = pod.get('securityContext') or {}
        if psc.get('fsGroup') != 1000:
            bad(f't2: {release} — pod securityContext.fsGroup is {psc.get("fsGroup")!r}, expected 1000 (uid-1000 image vs node-owned fresh local-path VCT volumes)')
        if psc.get('fsGroupChangePolicy') != 'OnRootMismatch':
            bad(f't2: {release} — pod securityContext.fsGroupChangePolicy is {psc.get("fsGroupChangePolicy")!r}, expected OnRootMismatch')
        ok(f't2: {release} — pod — grace 300, fsGroup 1000 + OnRootMismatch, no registration env in any container')

        svcs = by_kind(docs, 'Service')
        if (svcs[0].get('spec') or {}).get('clusterIP') != 'None':
            bad(f't2: {release} — the Service is not headless (clusterIP is {(svcs[0].get("spec") or {}).get("clusterIP")!r}, expected None — a StatefulSet requires one)')
        lb = [(d.get('metadata') or {}).get('name') for d in svcs if (d.get('spec') or {}).get('type') == 'LoadBalancer']
        if lb:
            bad(f't2: {release} — LoadBalancer Service(s) rendered: {lb} (the runners are client-only)')
        ings = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'Ingress']
        if ings:
            bad(f't2: {release} — Ingress(es) rendered: {ings} (the runners are client-only — no ingress by design)')
        cluster_roles = [((d.get('metadata') or {}).get('name'), d.get('kind'))
                         for d in docs if d.get('kind') in ('ClusterRole', 'ClusterRoleBinding')]
        if cluster_roles:
            bad(f't2: {release} — cluster-scoped RBAC rendered: {cluster_roles} (run 3\'s k8s-plugin surface was rejected — ruling 1)')
        ok(f't2: {release} — headless Service; no Ingress, no LoadBalancer, no ClusterRole/ClusterRoleBinding')

        privileged = 0
        for c in ics + cons:
            if ((c or {}).get('securityContext') or {}).get('privileged') is True:
                privileged += 1
        if privileged != 1:
            bad(f't2: {release} — {privileged} privileged containers in the render, expected exactly 1 (only the dind sidecar is deliberately privileged)')
        ok(f't2: {release} — exactly one privileged container (the dind sidecar)')

        es = by_kind(docs, 'ExternalSecret')[0]
        text = yaml.safe_dump(es)
        if 'bitwarden-login' not in text:
            bad(f't2: {release} — the ExternalSecret does not use the bitwarden-login store')
        tname = (((es.get('spec') or {}).get('target') or {}).get('name'))
        if tname != release:
            bad(f't2: {release} — the ExternalSecret target Secret is {tname!r}, expected {release!r} (release-derived, so two releases coexist in namespace default without collisions)')
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
        walk(es)
        if ('uuid', 'username') not in pairs or ('token', 'password') not in pairs:
            bad(f't2: {release} — the ExternalSecret remoteRefs are {sorted(pairs)}, expected uuid<-username and token<-password')
        if keys != {uuid}:
            bad(f't2: {release} — the ExternalSecret remoteRef keys are {sorted(keys)}, expected exactly {uuid!r} (this release\'s bitwardenIds.runner-token after --set)')
        data = (((es.get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
        if 'token' not in data:
            bad(f't2: {release} — the ExternalSecret template data has no token key')
        elif data['token'] != '{{ .token }}':
            bad(f't2: {release} — the ExternalSecret token template is {data["token"]!r}, expected {{{{ .token }}}}')
        if 'config.yaml' not in data:
            bad(f't2: {release} — the ExternalSecret template data has no config.yaml key')
        else:
            try:
                cfg = yaml.safe_load(data['config.yaml'])
            except Exception as ex:
                bad(f't2: {release} — the config.yaml template entry is not parseable YAML: {ex}')
            else:
                conns = (((cfg or {}).get('server') or {}).get('connections') or {})
                if set(conns) != {'default'}:
                    bad(f't2: {release} — the config connections are {sorted(conns)}, expected exactly [default] (one release owns its whole config — the per-instance dev/infra keys are gone)')
                conn = conns.get('default') or {}
                if conn.get('uuid') != '{{ .uuid }}':
                    bad(f't2: {release} — default.uuid is {conn.get("uuid")!r}, expected {{{{ .uuid }}}} (quoted — must stay a string before substitution)')
                if conn.get('url') != CHART_DEFAULT_URL:
                    bad(f't2: {release} — default.url is {conn.get("url")!r}, expected the chart default {CHART_DEFAULT_URL!r}')
                if conn.get('token_url') != 'file:$CREDENTIALS_DIRECTORY/token':
                    bad(f't2: {release} — default.token_url is {conn.get("token_url")!r}, expected file:$CREDENTIALS_DIRECTORY/token')
                if set(conn.get('labels') or []) != ACT_LABELS:
                    bad(f't2: {release} — default.labels are {conn.get("labels")!r}, expected the 5-label act set (ruling 3)')
                runner_cfg = (cfg or {}).get('runner') or {}
                if runner_cfg.get('timeout') != '30m':
                    bad(f't2: {release} — config runner.timeout is {runner_cfg.get("timeout")!r}, expected 30m (ruling 4)')
                if runner_cfg.get('shutdown_timeout') != '5m':
                    bad(f't2: {release} — config runner.shutdown_timeout is {runner_cfg.get("shutdown_timeout")!r}, expected 5m (ruling 4)')
        ok(f't2: {release} — ExternalSecret — bitwarden-login, target {release!r}, uuid(username)+token(password) from this release\'s item, token + config.yaml with the act label set, timeout 30m, shutdown_timeout 5m, chart-default url')

        if 'OVERRIDE_' in raw:
            bad(f't2: {release} — the rendered output still carries an OVERRIDE_* sentinel after --set bitwardenIds.runner-token')
        ok(f't2: {release} — zero OVERRIDE_* in the rendered output after --set of the sentinel UUID')

    check_release(render_dev, rel_dev, uuid_dev)
    check_release(render_infra, rel_infra, uuid_infra)

    seen, dupes = set(), set()
    for render_file in (render_dev, render_infra):
        for d in (x for x in yaml.safe_load_all(open(render_file)) if x):
            p = (d.get('kind'), ((d.get('metadata') or {}).get('name')))
            if p in seen:
                dupes.add(p)
            seen.add(p)
    if dupes:
        bad(f't2: cross-render name collision — (kind, name) pairs {sorted(dupes)} appear in more than one release (the two releases must be name-disjoint in namespace default)')
    ok('t2: cross-render collision check — the (kind,name) union of both releases is disjoint')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't2: the renders could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/runner-count")))
  else
    exit 1
  fi
fi
# --- t3: URL override probe (C01 c3) ----------------------------------------
if [ "$skip_helm" -eq 1 ]; then
  skip "t3: URL override probe not run (dependency update unavailable)"
else
  probe_out_dev="$WORK/runner-probe-dev.yaml"
  probe_out_infra="$WORK/runner-probe-infra.yaml"
  if ! "$helm_bin" template "$RELEASE_DEV" "$runner_copy" \
      --set "bitwardenIds.runner-token=$TEST_UUID_DEV" \
      --set "runner.url=https://example.test" \
    >"$probe_out_dev" 2>"$WORK/runner-probe-dev.err"; then
    tail -n 30 "$WORK/runner-probe-dev.err" >&2
    fail "t3: helm template of $RUNNER (release $RELEASE_DEV, --set runner.url) failed (log kept at $WORK/runner-probe-dev.err)"
  fi
  if ! "$helm_bin" template "$RELEASE_INFRA" "$runner_copy" \
      --set "bitwardenIds.runner-token=$TEST_UUID_INFRA" \
      --set "runner.url=https://example.test" \
    >"$probe_out_infra" 2>"$WORK/runner-probe-infra.err"; then
    tail -n 30 "$WORK/runner-probe-infra.err" >&2
    fail "t3: helm template of $RUNNER (release $RELEASE_INFRA, --set runner.url) failed (log kept at $WORK/runner-probe-infra.err)"
  fi
  if python3 - "$probe_out_dev" "$probe_out_infra" "$RELEASE_DEV" "$RELEASE_INFRA" "$WORK/probe-count" <<'PY'
import sys, yaml

render_dev, render_infra, rel_dev, rel_infra, count_file = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    for render_file, release in ((render_dev, rel_dev), (render_infra, rel_infra)):
        docs = [d for d in yaml.safe_load_all(open(render_file)) if d]
        es = [d for d in docs if d.get('kind') == 'ExternalSecret']
        if len(es) != 1:
            bad(f't3: {release} — the probe render has {len(es)} ExternalSecret(s), expected exactly one')
        name = (es[0].get('metadata') or {}).get('name')
        if name != release:
            bad(f't3: {release} — the probe ExternalSecret is named {name!r}, expected {release!r}')
        data = (((es[0].get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
        cfg = yaml.safe_load(data.get('config.yaml') or '')
        conns = (((cfg or {}).get('server') or {}).get('connections') or {})
        if set(conns) != {'default'}:
            bad(f't3: {release} — the probe config connections are {sorted(conns)}, expected exactly [default]')
        if (conns.get('default') or {}).get('url') != 'https://example.test':
            bad(f't3: {release} — after --set runner.url=https://example.test, the default connection url is {(conns.get("default") or {}).get("url")!r}, expected https://example.test (values-driven URL templating)')
    ok('t3: --set runner.url=https://example.test moves the default connection url on both releases (values-driven)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the probe renders could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/probe-count")))
  else
    exit 1
  fi
fi

# --- t4: renovate built-in helm-values extraction (C01 c4) -----------------
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
# --- t5: chart sentinel + aliased charts entries + top-level slices --------
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
# Deployed slice (amended 2026-10-25, user decision): dev aliases the chart
# once. UNWIRED_KEY must be absent from services/dev — its standalone render
# (t2/t3) is chart-capability proof, not a deployed state.
APP_KEYS = ('forgejo-runner-dev',)
UNWIRED_KEY = 'forgejo-runner-infra'
URLS = {'forgejo-runner-dev': 'http://dev-forgejo-http:3000'}

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
    bw = load(chart_vals).get('bitwardenIds') or {}
    if set(bw) != {'runner-token'}:
        bad(f't5: {chart_vals} bitwardenIds keys are {sorted(bw)}, expected exactly [runner-token] (one sentinel per chart install — one runner per release)')
    if bw['runner-token'] != SENTINEL:
        bad(f't5: {chart_vals} bitwardenIds.runner-token is {bw["runner-token"]!r}, expected {SENTINEL} (the repo sentinel — the real UUIDs live only in custom-values/dev)')
    ok(f't5: {chart_vals} carries exactly one bitwardenIds sentinel (runner-token)')

    sv = load(dev_vals)
    charts = sv.get('charts') or {}
    if 'forgejo-runner' in charts:
        bad(f't5: {dev_vals} still has a charts.forgejo-runner entry (the aliased entry replaces it — the old app would not be pruned)')
    if UNWIRED_KEY in charts:
        bad(f't5: {dev_vals} has charts.{UNWIRED_KEY} again — dev deploys the dev runner only (user decision 2026-10-25; infra relocation pending)')
    for key in APP_KEYS:
        e = charts.get(key)
        if not isinstance(e, dict):
            bad(f't5: {dev_vals} has no charts.{key} entry (one aliased entry per deployed Forgejo instance)')
        if e.get('chart') != 'forgejo-runner':
            bad(f't5: {dev_vals} charts.{key}.chart is {e.get("chart")!r}, expected forgejo-runner (the alias mechanism — the app deploys the shared chart)')
        if e.get('namespace') != 'default':
            bad(f't5: {dev_vals} charts.{key}.namespace is {e.get("namespace")!r}, expected default')
        if str(e.get('ServerSideApply')) != 'false':
            bad(f't5: {dev_vals} charts.{key}.ServerSideApply is {e.get("ServerSideApply")!r}, expected "false"')
    ok('t5: dev values carry charts.forgejo-runner-dev (chart: forgejo-runner, namespace default, ServerSideApply "false") and no charts.forgejo-runner or charts.forgejo-runner-infra')

    for key in APP_KEYS:
        sl = sv.get(key)
        if not isinstance(sl, dict):
            bad(f't5: {dev_vals} has no TOP-LEVEL {key}: slice — appset-charts.yaml merges only (index $.Values $appName) into each release, so per-app content in the charts: entry never reaches the release')
        url = ((sl.get('runner') or {}).get('url'))
        if url != URLS[key]:
            bad(f't5: the top-level {key} slice has runner.url {url!r}, expected {URLS[key]!r} (load-bearing: the only place the per-app URL flows)')
    if UNWIRED_KEY in sv:
        bad(f't5: {dev_vals} still has the top-level {UNWIRED_KEY}: slice — with no charts.{UNWIRED_KEY} entry it would ride the merged values to no Application (un-wired 2026-10-25)')
    ok('t5: the top-level slice carries the dev in-cluster URL http://dev-forgejo-http:3000 and no infra slice remains')

    # The client-only rationale must be documented adjacent to the aliased
    # entry, or the next reader assumes the missing ingress leg is an
    # oversight. The comment region spans from the block above the entry to
    # the end of its block.
    with open(dev_vals) as f:
        lines = f.read().splitlines()
    charts_idx = next((i for i, l in enumerate(lines) if re.match(r'^charts:\s*$', l)), None)
    if charts_idx is None:
        bad(f't5: {dev_vals} has no charts: block')
    block_end = len(lines)
    for i in range(charts_idx + 1, len(lines)):
        l = lines[i]
        if l.strip() and not l.lstrip().startswith('#') and not l.startswith((' ', '\t')):
            block_end = i
            break
    entry_idx = {}
    for key in APP_KEYS:
        m = [i for i in range(charts_idx + 1, block_end)
             if re.match(r'^[ \t]+%s:\s*$' % re.escape(key), lines[i])]
        if not m:
            bad(f't5: {dev_vals} has no {key}: entry inside the charts: block')
        entry_idx[key] = m[0]
    lo = min(entry_idx.values())
    j = lo - 1
    while j > charts_idx and lines[j].lstrip().startswith('#'):
        j -= 1
    hi = max(entry_idx.values())
    hi_indent = len(lines[hi]) - len(lines[hi].lstrip())
    i = hi + 1
    while i < len(lines):
        l = lines[i]
        s = l.strip()
        if s and not s.startswith('#'):
            if (len(l) - len(l.lstrip())) <= hi_indent:
                break
        i += 1
    region = lines[j + 1:i]
    comments = [l for l in region if l.strip().startswith('#')]
    block_text = '\n'.join(comments)
    if not any(re.search(r'ingress|proxy', c, re.IGNORECASE) for c in comments):
        bad(f't5: the aliased charts entry has no comment explaining the deliberately missing ingress/proxy leg (client-only service)')
    # Single client-only runner since 2026-10-25 (user decision): the old
    # wording claiming BOTH dial out must fail, the deployed one must be
    # named, and the un-wired infra instance must read as relocation-pending
    # so its absence is never re-filed as an oversight.
    if re.search(r'\bboth\b', block_text, re.IGNORECASE):
        bad('t5: the trio-exemption comment still claims BOTH runners dial out — dev deploys forgejo-runner-dev only since 2026-10-25')
    if not re.search(r'forgejo-runner-dev', block_text):
        bad('t5: the trio-exemption comment does not name the single deployed runner (forgejo-runner-dev)')
    if not (re.search(r'infra', block_text, re.IGNORECASE) and re.search(r'relocat|pending', block_text, re.IGNORECASE)):
        bad('t5: the trio-exemption comment does not record the infra runner as un-wired with relocation pending (user decision 2026-10-25)')
    ok('t5: the aliased entry carries the client-only comment for the single runner (infra relocation pending noted; still no ingress entry)')

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

# --- t6: doc ports (UNCHANGED from the predecessor contract) ---------------
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
# --- t7: custom-values per-app UUID slots (C01 c6) --------------------------
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
APP_KEYS = ('forgejo-runner-dev',)
UNWIRED_KEY = 'forgejo-runner-infra'

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
    cv = load(dev_cv)
    for key in APP_KEYS:
        slot = (((cv.get(key) or {}).get('bitwardenIds') or {}).get('runner-token'))
        if slot is None:
            bad(f't7: {dev_cv} has no {key}.bitwardenIds.runner-token slot (the {key} release would have no Bitwarden item to sync)')
        elif slot == SENTINEL:
            bad(f't7: {dev_cv} {key}.bitwardenIds.runner-token is the service sentinel {SENTINEL} — a real UUID or the documented OVERRIDE_NEEDED placeholder, never the service sentinel')
        elif not (slot == 'OVERRIDE_NEEDED' or (isinstance(slot, str) and UUID_RE.match(slot))):
            bad(f't7: {dev_cv} {key}.bitwardenIds.runner-token is {slot!r} — not a UUID and not the documented OVERRIDE_NEEDED placeholder')
        else:
            ok(f't7: {dev_cv} carries the {key}.bitwardenIds.runner-token slot')
    if UNWIRED_KEY in cv:
        bad(f't7: {dev_cv} still wires {UNWIRED_KEY} ({(cv[UNWIRED_KEY] or {}).get("bitwardenIds")}) — dev no longer deploys the infra runner (user decision 2026-10-25: relocation pending); the vault item stays, the dev slot must not')
    if 'forgejo-runner' in cv:
        bad(f't7: {dev_cv} still has the old top-level forgejo-runner: block (the per-app blocks replace it — it would keep riding the values of the app the appset prunes)')
    ok(f't7: {dev_cv} no longer carries the old top-level forgejo-runner: block or the un-wired {UNWIRED_KEY}: block')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't7: the custom-values slot check could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t7-count")))
else
  exit 1
fi

# --- t8: sentinel parity 1<->1 (deployed slice, amended 2026-10-25) ---------
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
APP_KEYS = ('forgejo-runner-dev',)
UNWIRED_KEY = 'forgejo-runner-infra'

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
    chart_bw = load(chart_vals).get('bitwardenIds') or {}
    if set(chart_bw) != {'runner-token'}:
        bad(f't8: {chart_vals} bitwardenIds keys are {sorted(chart_bw)}, expected exactly [runner-token] (one sentinel per chart install — the 1<->1 parity of the deployed slice)')
    if chart_bw['runner-token'] != SENTINEL:
        bad(f't8: {chart_vals} bitwardenIds.runner-token is {chart_bw["runner-token"]!r}, expected {SENTINEL}')
    cv = load(dev_cv)
    if UNWIRED_KEY in cv:
        bad(f't8: {dev_cv} still has a top-level {UNWIRED_KEY}: block — dev deploys the dev runner only (user decision 2026-10-25); parity is 1<->1')
    for key in APP_KEYS:
        bw = (cv.get(key) or {}).get('bitwardenIds') or {}
        if set(bw) != {'runner-token'}:
            bad(f't8: {dev_cv} {key}.bitwardenIds slots are {sorted(bw)}, expected exactly [runner-token] — one slot for the deployed app, matching the single chart sentinel')
        v = bw['runner-token']
        if v == SENTINEL:
            bad(f't8: {dev_cv} {key}.runner-token still carries the service sentinel {SENTINEL} — parity requires a real UUID or OVERRIDE_NEEDED')
        elif not (v == 'OVERRIDE_NEEDED' or (isinstance(v, str) and UUID_RE.match(v))):
            bad(f't8: {dev_cv} {key}.runner-token is {v!r} — not a UUID and not the documented OVERRIDE_NEEDED placeholder')
    ok('t8: sentinel parity 1<->1 — the single chart sentinel matches exactly the one deployed custom-values slot (UUID or OVERRIDE_NEEDED, never the service sentinel); the infra app stays un-wired pending relocation')
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
# --- t9: dev-umbrella render (C01 c7) ---------------------------------------
if [ -z "$helm_bin" ]; then
  skip "t9: dev umbrella render not run (no helm binary)"
else
  dev_out="$WORK/dev-render.yaml"
  dev_err="$WORK/dev-render.err"
  # C01 acceptance 7's exact command: the whole custom-values file is the -f,
  # with NO --set for the runner tokens — they are real UUIDs in the file
  # now, not placeholders to override.
  if ! "$helm_bin" template dev "$DEVUMB" \
      -f "$DEV_CV" \
      --set domain=scifi.farm --set clusterName=dev \
    >"$dev_out" 2>"$dev_err"; then
    tail -n 30 "$dev_err" >&2
    fail "t9: helm template of $DEVUMB with -f custom-values failed (log kept at $dev_err)"
  fi
  [ -s "$dev_out" ] || fail "t9: helm template of $DEVUMB rendered nothing"
  if python3 - "$dev_out" "$DEV_CV" "$WORK/dev-count" <<'PY'
import re, sys, yaml

render, dev_cv, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
APP_KEYS = ('forgejo-runner-dev',)
UNWIRED_KEY = 'forgejo-runner-infra'
URLS = {'forgejo-runner-dev': 'http://dev-forgejo-http:3000'}

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
    cv = load(dev_cv)
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

    charts = vals.get('charts') or {}
    for key in APP_KEYS:
        e = charts.get(key)
        if not isinstance(e, dict):
            bad(f't9: the dev-appset values blob has no charts.{key} entry (the aliased entry is missing — the app would never be created)')
        if e.get('chart') != 'forgejo-runner':
            bad(f't9: the dev-appset values blob has charts.{key}.chart {e.get("chart")!r}, expected forgejo-runner (the alias mechanism)')
    if 'forgejo-runner' in charts:
        bad('t9: the dev-appset values blob still has a charts.forgejo-runner entry (it must be replaced by the aliased entry — the old app would not be pruned)')
    if UNWIRED_KEY in charts:
        bad(f't9: the dev-appset values blob still has charts.{UNWIRED_KEY} — ArgoCD would deploy a second runner against the un-wired slot (user decision 2026-10-25: dev deploys runner-dev only)')
    ok('t9: dev-appset values blob carries charts.forgejo-runner-dev (chart: forgejo-runner) and no charts.forgejo-runner or charts.forgejo-runner-infra')

    for key in APP_KEYS:
        got = ((vals.get(key) or {}).get('runner') or {}).get('url')
        if got != URLS[key]:
            bad(f't9: the dev-appset values blob has no top-level {key} slice with runner.url {URLS[key]!r} (got {got!r} — the per-app URL slice is missing or wrong)')
    if UNWIRED_KEY in vals:
        bad(f't9: the dev-appset values blob still has a top-level {UNWIRED_KEY} slice (un-wired 2026-10-25)')
    ok('t9: dev-appset values blob carries the top-level forgejo-runner-dev slice with the dev in-cluster URL, no infra slice')

    # "Resolved" = equal to what custom-values/dev carries for that app key —
    # the test asserts the flow, never the UUID value itself.
    for key in APP_KEYS:
        want = (((cv.get(key) or {}).get('bitwardenIds') or {}).get('runner-token'))
        got = ((vals.get(key) or {}).get('bitwardenIds') or {}).get('runner-token')
        if got != want:
            bad(f't9: the dev-appset values blob has {key}.bitwardenIds.runner-token {got!r}, expected the custom-values value {want!r}')
        if got != 'OVERRIDE_NEEDED' and not (isinstance(got, str) and UUID_RE.match(got)):
            bad(f't9: the dev-appset values blob {key}.bitwardenIds.runner-token {got!r} is not a resolved UUID (and not the documented OVERRIDE_NEEDED placeholder)')
    ok('t9: dev-appset values blob carries the resolved dev runner-token UUID under its app key')

    subs = (vals.get('ingress') or {}).get('subdomains') or {}
    # Re-ruled by 2026/2026-10-feat-dev-mcp-fleet C01 AC5 (user ruling
    # 2026-10-24): the exact set froze the forgejo-runner-era dev surface; the
    # approved plan adds the searxng LAN host. The load-bearing claims remain:
    # the original four hosts stay, the runners stay client-only (NO ingress
    # entry), and nothing beyond the approved additions appears.
    base4 = {'coder', 'git', 'research', 'cluster'}
    if not base4 <= set(subs):
        bad(f't9: dev ingress.subdomains lost {sorted(base4 - set(subs))} — expected at least coder/git/research/cluster')
    runners = sorted(set(subs) & {'forgejo-runner-dev', 'forgejo-runner-infra'})
    if runners:
        bad(f't9: dev ingress.subdomains carries runner entries {runners} — the runners are client-only, so they get NO ingress entry')
    unapproved = sorted(set(subs) - (base4 | {'searxng'}))
    if unapproved:
        bad(f't9: dev ingress.subdomains carries unapproved entries {unapproved} — only coder/git/research/cluster plus the dev-mcp-fleet C01 searxng host are sanctioned')
    ok('t9: dev ingress.subdomains within the approved set (original four + searxng; no runner entry, no unapproved addition)')

    # Sentinels may remain only inside the appset-generator resource (the
    # values blob, where per-app placeholders ride to the base chart). The
    # pinned OVERRIDE_NEEDED tolerance for forgejo-token-canonical was
    # retired together with that wiring (removed unused 2026-10-26), so NO
    # non-appset document may carry any OVERRIDE_ string. A future must-fill
    # slot needs its own contract amendment, not a widened allow — the
    # github-mcp allowance was retired the same way by the DECISIONS
    # 2026-10-24 post-approval ruling (the real items exist — dev-github
    # LOGIN 522b1cc4 reused for github-mcp, searxng LOGIN f90806ff).
    raw = open(render).read()
    if 'OVERRIDE_VIA_CUSTOM_VALUES' in raw:
        bad('t9: the rendered dev umbrella still carries the OVERRIDE_VIA_CUSTOM_VALUES service sentinel (the -f file did not resolve it)')
    for d in docs:
        if d.get('kind') == 'ApplicationSet':
            continue
        t = yaml.safe_dump(d)
        if 'OVERRIDE_' in t:
            bad(f"t9: non-appset document {((d.get('metadata') or {}).get('name'))!r} carries an OVERRIDE_* string — deploy-time sentinels may ride only in the appset-generator values blob, and the canonical must-fill slot was retired with its wiring")
    ok('t9: no OVERRIDE_* strings outside the appset-generator resource (canonical slot retired 2026-10-26)')

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

# --- t10: base-chart ground-truth render (C01 c7) ---------------------------
# appset-charts.yaml builds each element's values blob ONLY from
# `merge $extraValues (index $.Values $appName)` — this render proves the
# top-level slices + custom-values keys actually flow to the per-app values
# (the predecessor's charts.forgejo-runner.runners pins were inert here).
if [ "$skip_helm" -eq 1 ]; then
  skip "t10: base-chart render not run (no helm binary / registry unreachable)"
elif [ ! -d "$BASE" ]; then
  fail "t10: $BASE does not exist (the ground-truth render needs the base chart)"
else
  base_copy="$WORK/base-copy"
  cp -R "$BASE"/. "$base_copy"/
  if [ -z "$(ls -A "$base_copy/charts" 2>/dev/null)" ]; then
    dep_log="$base_copy/dependency-build.log"
    if ! (cd "$base_copy" && "$helm_bin" dependency build .) >"$dep_log" 2>&1; then
      if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
        skip "t10: helm dependency build could not reach the registry for $BASE here; t10 was not run (log kept at $dep_log)"
      else
        tail -n 30 "$dep_log" >&2
        fail "t10: helm dependency build failed for $BASE (log kept at $dep_log)"
      fi
    fi
  fi
  base_out="$WORK/base-render.yaml"
  base_err="$WORK/base-render.err"
  if ! "$helm_bin" template dev "$base_copy" \
      -f "$DEV_VALUES" -f "$DEV_CV" \
      --set domain=scifi.farm --set clusterName=dev --set serviceName=dev \
      --show-only templates/appset-charts.yaml \
    >"$base_out" 2>"$base_err"; then
    tail -n 30 "$base_err" >&2
    fail "t10: helm template of $BASE (--show-only templates/appset-charts.yaml) failed (log kept at $base_err)"
  fi
  [ -s "$base_out" ] || fail "t10: the base render produced no appset-charts.yaml output"
  if python3 - "$base_out" "$DEV_CV" "$WORK/base-count" <<'PY'
import re, sys, yaml

render, dev_cv, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
APP_KEYS = ('forgejo-runner-dev',)
UNWIRED_KEY = 'forgejo-runner-infra'
URLS = {'forgejo-runner-dev': 'http://dev-forgejo-http:3000'}

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
    cv = load(dev_cv)
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    appsets = [d for d in docs
               if d.get('kind') == 'ApplicationSet'
               and (d.get('metadata') or {}).get('name') == 'dev-charts-appset']
    if not appsets:
        bad('t10: no ApplicationSet named dev-charts-appset in the base render')
    els = appsets[0]['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
    by_app = {(e or {}).get('appName'): e for e in els if isinstance(e, dict)}
    for key in APP_KEYS:
        if key not in by_app:
            bad(f't10: the generator has no appName {key} element (the charts.{key} entry is missing from the base values)')
        if by_app[key].get('chart') != 'forgejo-runner':
            bad(f't10: element {key} has chart {by_app[key].get("chart")!r}, expected forgejo-runner (the alias mechanism — the app deploys the shared chart)')
    if 'forgejo-runner' in by_app:
        bad('t10: the generator still has an appName forgejo-runner element (the aliased entry replaces it — the old app would not be pruned)')
    if UNWIRED_KEY in by_app:
        bad(f't10: the generator still has an appName {UNWIRED_KEY} element (charts.{UNWIRED_KEY} was un-wired from services/dev — user decision 2026-10-25)')
    ok('t10: generator elements include forgejo-runner-dev (chart: forgejo-runner) and no plain forgejo-runner or forgejo-runner-infra element')
    for key in APP_KEYS:
        blob = by_app[key].get('values')
        if not isinstance(blob, dict):
            bad(f't10: element {key} has no values blob')
        got_url = ((blob.get('runner') or {}).get('url'))
        if got_url != URLS[key]:
            bad(f't10: element {key} values blob runner.url is {got_url!r}, expected {URLS[key]!r} — per-app values flow ONLY from the top-level {key}: slice (the appset merge), never from the charts: entry')
        want = (((cv.get(key) or {}).get('bitwardenIds') or {}).get('runner-token'))
        got = ((blob.get('bitwardenIds') or {}).get('runner-token'))
        if got != want:
            bad(f't10: element {key} values blob bitwardenIds.runner-token is {got!r}, expected the custom-values value {want!r} (the UUID rides the same top-level slice merge)')
        if got != 'OVERRIDE_NEEDED' and not (isinstance(got, str) and UUID_RE.match(got)):
            bad(f't10: element {key} values blob bitwardenIds.runner-token {got!r} is not a resolved UUID (and not the documented OVERRIDE_NEEDED placeholder)')
    ok('t10: each element values blob carries ITS top-level-slice url + ITS resolved runner-token UUID (the values flow is real — the inert-pins landmine is guarded)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't10: the base render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/base-count")))
  else
    exit 1
  fi
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: dev-forgejo-runner checks (%d ok)\n' "$checks"
