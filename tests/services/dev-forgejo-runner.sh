#!/usr/bin/env bash
# C01 contract (2026-10-refactor-forgejo-runner-per-instance) for
# charts/forgejo-runner as the per-instance runner chart, re-aimed to the
# cf-55 ROUND-6 shape (D61/D62, owner ruling 2026-11-26): exactly one
# StatefulSet per release whose pods SELF-REGISTER (dind sidecar +
# register init container + podManagementPolicy Parallel), all resources named after the release
# name, one ExternalSecret per release (bitwarden-login; the item's
# password -> the SINGLE fetched registration-token key, no inline
# template — the C16 (uuid, token) record pair retires), one
# server.connections.default entry in the skeleton config.yaml
# (5-label act set — since the cf-55 fix round four of them ride the baked
# job image, timeout 30m, shutdown_timeout 5m) — the skeleton renders as
# a release-named ConfigMap and the register init container substitutes
# the minted uuid + writes the token onto the ordinal's /data PVC, hardened runner
# (13.2.0 pin, dumb-init daemon, drop ALL, no register subcommand, no
# daemon-side registration env), VCTs data 2Gi + docker-data 10Gi local-path, grace 300 + fsGroup
# 1000, no Ingress/LoadBalancer/cluster RBAC — deployed TWICE by the dev
# ApplicationSet via the chart: alias (charts.forgejo-runner-dev +
# charts.forgejo-runner-infra, both chart: forgejo-runner), per-app URLs in
# TOP-LEVEL slices (the only values the appset merge flows), and the single
# bitwardenIds.runner-token sentinel with 1<->2 custom-values parity. The
# base-chart ground-truth render proves the values flow.
# Supersession (2026-10-25 user decision, ticket 2026-10-feat-forgejo-auth-
# support): dev deploys forgejo-runner-dev ONLY — the forgejo-runner-infra
# alias, its top-level slice and its custom-values slot are un-wired from the
# deployed surface; the relocation that decision anticipated completed on
# 2026-11-05 (cf-104 e824542f8) as the gpu-cluster release
# forgejo-runner-gpu, dialing the infra instance over HTTPS. The chart keeps
# the multi-instance capability, so the chart-level legs (t1-t4, t5's chart-
# sentinel leg) are unchanged; the dev-deployed-slice legs (t5/t7-t10) assert
# the single aliased app.
#
# Contract source: chunks/C01.md Tests list (t1-t10) + cf-97 C02's wording
# leg (t11) + C04's mergePolicy leg (t12) + C05's socket-group leg (t13) +
# C06's identity pin (same leg, extended in place) + the labels-map
# capability record (t14; cf-104 C04, re-derived to the cf-55 fix-round
# baked-toolchain truth by D41; written BEFORE the pinned-red t5 because the harness
# stops at the first failing leg and an appended leg would never run) — ONE
# script stays the runner contract (predecessor ruling, DECISIONS.md).
#
# C01/C03 acceptance is cluster-only — no leg here can assert it (the vault
# and the live pod are out-of-repo, and list/event MCP shapes come back
# empty for agent sessions): the evidence shape is exact-name readonly-dev-
# kubernetes reads — resources_get StatefulSet + ExternalSecret
# dev-forgejo-runner-dev, pods_get + pods_log(container runner) pod
# dev-forgejo-runner-dev-0 — gated on the bounce-window oracle: pod startTime
# vs the reported C01 write time plus the 1h refreshInterval separates "not
# synced yet" from "will never sync".
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
# Round 5 (C16/D57): the DEPLOYED dev shape joins the pair — the chart plus
# the extracted top-level forgejo-runner-dev services slice (the only values
# the appset merges, so replicas: 10 rides there). The two standalone
# renders stay exactly the chart-default truth (the no-override case AC3
# fences); the slice render flips the deployed replicas expectation to 10.
if [ "$skip_helm" -eq 1 ]; then
  skip "t2: render not run (dependency update unavailable)"
else
  t2_slice="$WORK/t2-dev-slice.yaml"
  if ! python3 - "$DEV_VALUES" "$t2_slice" <<'PY'
import re, sys, yaml

src, out = sys.argv[1:3]
lines = []
with open(src) as f:
    for line in f:
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
d = yaml.safe_load(''.join(lines)) or {}
block = d.get('forgejo-runner-dev')
if not isinstance(block, dict):
    print(f'FAIL: t2: {src} has no top-level forgejo-runner-dev: slice to extract — the appset merges only this key (t17 loader discipline)', file=sys.stderr)
    sys.exit(1)
with open(out, 'w') as f:
    yaml.safe_dump(block, f)
PY
  then
    fail "t2: could not extract the dev services slice from $DEV_VALUES"
  fi
  runner_out_slice="$WORK/runner-render-dev-slice.yaml"
  if ! "$helm_bin" template "$RELEASE_DEV" "$runner_copy" \
      -f "$t2_slice" \
      --set "bitwardenIds.runner-token=$TEST_UUID_DEV" \
    >"$runner_out_slice" 2>"$WORK/runner-render-dev-slice.err"; then
    tail -n 30 "$WORK/runner-render-dev-slice.err" >&2
    fail "t2: helm template of $RUNNER (dev release WITH the services slice) failed (log kept at $WORK/runner-render-dev-slice.err)"
  fi
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
  if python3 - "$runner_out_dev" "$runner_out_infra" "$runner_out_slice" "$RELEASE_DEV" "$RELEASE_INFRA" "$TEST_UUID_DEV" "$TEST_UUID_INFRA" "$WORK/runner-count" <<'PY'
import re, sys, yaml

(render_dev, render_infra, render_slice, rel_dev, rel_infra,
 uuid_dev, uuid_infra, count_file) = sys.argv[1:9]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# The baked-runner label set — the CHART DEFAULT (cf-55 fix round, D39/D40;
# re-pointed to the infra instance registry by cf-6-debug-forge-runner-docker-1
# on 2026-11-22, family B per-release ruling): the four act-24.04-family
# labels resolve to the repo-built derivative of the digest-pinned act-24.04
# base with helm and cr baked in (containers/forgejo-runner), published as
# git.spencerslab.com/curatedforest/forgejo-runner — the ref the gpu release
# rides; the dev release overrides the labels in its own services slice
# (t17), because each runner pulls from its OWN instance registry. The
# ghcr.io/ownyourio pin this leg carried since the cf-55 fix round named a
# calendar tag that was walk-predicted and never minted (EXPLORE §2/§3).
# The pin is an immutable calendar tag because these runners never re-pull a
# tag they have cached: a rolling ref would freeze silently at first-pull
# content. Bumps are manual + red-first here — no renovate manager reads the
# label lines. ubuntu-22.04 stays the plain act tag (D40: no job uses it, and
# a 24.04-content image behind a 22.04 label would lie about its OS). t2
# renders the chart standalone, so this is the chart-default truth, never a
# services slice. DESIGNED RED until the run-1 DEV move lands
# charts/forgejo-runner/values.yaml (the t2 stop).
ACT_LABELS = {
    'ubuntu-latest:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1',
    'ubuntu-24.04:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1',
    'ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04',
    'docker:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1',
    'node22:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1',
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
            bad(f't2: {release} — replicas is {spec.get("replicas")!r}, expected 1: this is the NO-OVERRIDE chart-default render (the D57 default-single stands under D61 — a new release is one pod until a slice rules otherwise; a default flip is a ruling, not a drift)')
        if spec.get('podManagementPolicy') != 'Parallel':
            bad(f't2: {release} — podManagementPolicy is {spec.get("podManagementPolicy")!r}, expected Parallel (D62 belt: one pending ordinal must not freeze the ones behind it — the exact StatefulSet sequencing class that held gpu at 3/10, EXPLORE Round-6 A1; OrderedReady is the default this round replaces)')
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
        ok(f't2: {release} — replicas 1 with no slice override (chart default stays single per D57-as-superseded-by-D61), VCTs exactly data (2Gi) + docker-data (10Gi), both RWO local-path')

        pod = ((spec.get('template') or {}).get('spec')) or {}
        ics = pod.get('initContainers') or []
        dind = next((c for c in ics if (c or {}).get('name') == 'dind'), None)
        if dind is None:
            bad(f't2: {release} — no initContainer named dind (the DinD sidecar is missing)')
        # values.yaml's renovate-tracked tag is the authority (RESEARCH
        # contradiction 5) — a values-only bump must resurface here as
        # contract drift, not ride silently past the suite.
        if dind.get('image') != 'docker:29.9.2-dind':
            bad(f't2: {release} — dind image is {dind.get("image")!r}, expected docker:29.9.2-dind')
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
        # Run-3 family (c) render proof (owner ruling 2026-11-23): the D33
        # TLS-35 egress class recurring at lane dispatch #215 makes the
        # documented --mtu=1450 cap live on the dind daemon of BOTH
        # runner releases — and only on dind: the same pair on the runner
        # container would render validly yet cap nothing. Placement is what
        # this pin holds; the pair itself is g7's diff fence.
        if dind.get('args') != ['--mtu=1450']:
            bad(f't2: {release} — dind args is {dind.get("args")!r}, expected exactly ["--mtu=1450"] — the run -3 egress ruling lands the documented MTU mitigation on every dind daemon; args are dockerd-prefixed by the image entrypoint (verified: docker:29.9.2-dind declares no Cmd)')
        ok(f't2: {release} — dind sidecar — docker:29.9.2-dind, restartPolicy Always, privileged, socket startup+liveness probes, args [--mtu=1450]')
        reg = next((c for c in ics if (c or {}).get('name') == 'register'), None)
        if reg is None:
            bad(f't2: {release} — no initContainer named register (C17/D62: each ordinal mints its OWN runner record on first boot off the one reusable registration token; the script-shape teeth live in t21 — its absence here is the C16 shared-record pair coming back)')
        ok(f't2: {release} — initContainers carry dind AND the register init (ten rows, one token — D61)')

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
        if 'CREDENTIALS_DIRECTORY' in env:
            bad(f't2: {release} — runner still carries CREDENTIALS_DIRECTORY {env["CREDENTIALS_DIRECTORY"]!r} — C17 retires the env/Secret pair: the config and token arrive on the ordinal /data PVC from the register init, and the skeleton token_url is absolute (D62)')
        if (env.get('DOCKER_HOST') or {}).get('value') != 'unix:///var/run/docker.sock':
            bad(f't2: {release} — DOCKER_HOST is {(env.get("DOCKER_HOST") or {}).get("value")!r}, expected unix:///var/run/docker.sock (the in-pod socket)')
        # Command/persistence consistency (C17 re-aim): the -c path is the
        # PVC-rendered config home, reached by the /data mount — never by a
        # Secret mount. subPath is the shadow class; any Secret volume in the
        # daemon container is the cold-boot-credential-in-steady-state class.
        toks = (runner.get('command') or []) + (runner.get('args') or [])
        cfg_path = None
        for i, t in enumerate(toks):
            if t in ('-c', '--config') and i + 1 < len(toks):
                cfg_path = toks[i + 1]
        if cfg_path != '/data/config/config.yaml':
            bad(f't2: {release} — the daemon -c flag points at {cfg_path!r}, expected /data/config/config.yaml (AC3: the command is unchanged by C17 — what changed is that the file is PRODUCED there by the register init instead of mounted from the Secret)')
        mounts = runner.get('volumeMounts') or []
        if [m for m in mounts if (m or {}).get('subPath') == 'config.yaml']:
            bad(f't2: {release} — the runner container keeps a config.yaml subPath mount — a subPath Secret mount would SHADOW the /data/config/config.yaml the register init renders onto the PVC (C17/D62: the mount retires precisely because the file is now produced, not mounted)')
        vols = {(v or {}).get('name'): v for v in pod.get('volumes') or []}
        secret_vols = {n for n, v in vols.items() if (v or {}).get('secret')}
        mounted_secrets = [m for m in mounts if (m or {}).get('name') in secret_vols]
        if mounted_secrets:
            bad(f't2: {release} — the runner container mounts Secret volume(s) {sorted(m["name"] for m in mounted_secrets)} — the release Secret holds only the registration token now; it belongs to the init container (env or init-only mount), never the daemon (AC3 — the shadow-mount + steady-state-credential class C17 closes)')
        if not [m for m in mounts if (m or {}).get('mountPath') == '/data']:
            bad(f't2: {release} — the runner container has no /data mount — the config/token now live on the data PVC, so the daemon must read what the register init wrote there')
        ok(f't2: {release} — runner — 13.2.0 pin, dumb-init daemon (no register subcommand), drop-ALL + no privilege escalation, DOCKER_HOST on the in-pod socket, -c /data/config/config.yaml on the data PVC, NO CREDENTIALS_DIRECTORY and NO Secret mount (re-attach-from-PVC shape, D62)')

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
        if pairs != {('registration-token', 'password')}:
            bad(f't2: {release} — the ExternalSecret remoteRefs are {sorted(pairs)}, expected exactly [registration-token, password] — D61/D62: the item carries ONE reusable instance-scope registration token in its password field; a second fetched key (the uuid record pair) is the C16 shape returning, and one (uuid, token) can never show more than one row because ActionRunner.UUID is UNIQUE (RESEARCH TL;DR 1 [S2])')
        if keys != {uuid}:
            bad(f't2: {release} — the ExternalSecret remoteRef keys are {sorted(keys)}, expected exactly {uuid!r} (the bitwardenIds.runner-token item after --set — the KEY name survives C17 per D63 blast-radius discipline; only its CONTENT meaning changes to the registration token)')
        if (((es.get('spec') or {}).get('target') or {}).get('template')) is not None:
            bad(f't2: {release} — spec.target.template still renders — C17 deletes the inline template entirely (the config skeleton moved to the release ConfigMap, D62); with no template the v2-CRD mergePolicy Replace trap of card #97 is moot by construction')
        ok(f't2: {release} — ExternalSecret — bitwarden-login, target {release!r}, ONE fetched key registration-token from the item password, no target.template')

        # Config skeleton (C17/D62): the static half of config.yaml renders as
        # a release-named ConfigMap (app-template configMaps); the register
        # init substitutes the minted uuid for the placeholder and writes the
        # token file onto the /data PVC. Readers moved off the retired ESO
        # template.data (C17 TEST FOLD: the kind switches, the rulings ride).
        cms = by_kind(docs, 'ConfigMap')
        if len(cms) != 1:
            bad(f't2: {release} — {len(cms)} ConfigMaps rendered, expected exactly 1 (the config-skeleton home since C17 — one app-template configMaps entry per release)')
        cm = cms[0]
        cmname = (cm.get('metadata') or {}).get('name') or ''
        if cmname != release and not cmname.startswith(f'{release}-'):
            bad(f't2: {release} — the skeleton ConfigMap is named {cmname!r}, expected the release-derived app-template name')
        cmdata = cm.get('data') or {}
        if set(cmdata) != {'config.yaml'}:
            bad(f't2: {release} — the skeleton ConfigMap data keys are {sorted(cmdata)}, expected exactly [config.yaml] (the register init renders this file to /data/config/config.yaml)')
        body = cmdata.get('config.yaml') or ''
        if '{{' in body or '{%' in body:
            bad(f't2: {release} — the rendered skeleton carries unresolved template braces — the ESO-era dot-uuid/dot-token substitution pair retires with the template; the placeholder must be a plain string the init script substitutes')
        cfg = yaml.safe_load(body)
        conns = (((cfg or {}).get('server') or {}).get('connections') or {})
        if set(conns) != {'default'}:
            bad(f't2: {release} — the skeleton connections are {sorted(conns)}, expected exactly [default] (one release owns its whole config)')
        conn = conns.get('default') or {}
        ph = conn.get('uuid')
        if not isinstance(ph, str) or not ph.strip():
            bad(f't2: {release} — skeleton default.uuid is {ph!r}, expected a non-empty PLACEHOLDER string the register script substitutes (C17 Tasks — an empty uuid would reproduce the daemon fail-fast crash-loop the old B1 note carried)')
        if re.fullmatch(r'[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', ph):
            bad(f't2: {release} — skeleton default.uuid is a literal UUID ({ph!r}) — the shared skeleton must carry a placeholder; one baked uuid in the ConfigMap is the C16 one-row shape back (D61: ten records named after the pods)')
        if conn.get('url') != CHART_DEFAULT_URL:
            bad(f't2: {release} — default.url is {conn.get("url")!r}, expected the chart default {CHART_DEFAULT_URL!r}')
        if conn.get('token_url') != 'file:/data/config/token':
            bad(f't2: {release} — default.token_url is {conn.get("token_url")!r}, expected the absolute PVC path file:/data/config/token (D62/G3 — the file:dollar-CREDENTIALS token pair retires with the Secret mount)')
        if set(conn.get('labels') or []) != ACT_LABELS:
            bad(f't2: {release} — skeleton default.labels are {conn.get("labels")!r}, expected the baked 5-label chart default: four act-24.04-family labels on git.spencerslab.com/curatedforest/forgejo-runner plus plain act-22.04 (cf-55 D39/D40; the byte-identity law moves from the ESO render to the ConfigMap render — D62 keeps EVERY row advertising the identical set so jobs route uniformly)')
        runner_cfg = (cfg or {}).get('runner') or {}
        if runner_cfg.get('capacity') != 1:
            bad(f't2: {release} — skeleton runner.capacity is {runner_cfg.get("capacity")!r}, expected 1 (D57 arithmetic survives D61 and is now honest per row: one ordinal = one record = one slot)')
        if runner_cfg.get('timeout') != '30m':
            bad(f't2: {release} — config runner.timeout is {runner_cfg.get("timeout")!r}, expected 30m (ruling 4)')
        if runner_cfg.get('shutdown_timeout') != '5m':
            bad(f't2: {release} — config runner.shutdown_timeout is {runner_cfg.get("shutdown_timeout")!r}, expected 5m (ruling 4)')
        ok(f't2: {release} — ConfigMap skeleton — connections [default] with the uuid placeholder, absolute file:/data/config/token, the baked 5-label set, capacity 1, timeout 30m, shutdown_timeout 5m, chart-default url')

        if 'OVERRIDE_' in raw:
            bad(f't2: {release} — the rendered output still carries an OVERRIDE_* sentinel after --set bitwardenIds.runner-token')
        ok(f't2: {release} — zero OVERRIDE_* in the rendered output after --set of the sentinel UUID')

    check_release(render_dev, rel_dev, uuid_dev)
    check_release(render_infra, rel_infra, uuid_infra)

    # Deployed dev shape (C16/D57): the appset merges ONLY the top-level
    # services slice, so the release this cluster actually runs carries
    # replicas 10 — ten poller pods on ONE registration, one job per pod.
    sdocs = [d for d in yaml.safe_load_all(open(render_slice)) if d]
    ssts = by_kind(sdocs, 'StatefulSet')
    if len(ssts) != 1:
        bad(f't2: the slice-overlay render carries {len(ssts)} StatefulSets, expected exactly 1')
    sspec = (ssts[0].get('spec')) or {}
    if sspec.get('replicas') != 10:
        bad(f't2: {rel_dev} DEPLOYED render — replicas is {sspec.get("replicas")!r}, expected 10 (owner ruling 2026-11-26: ten pods, both instances — the D57 count and capacity-1 arithmetic STAND under D61, but the identity law changed: ten pods now hold TEN self-minted records behind ONE reusable registration token, not one shared (uuid, token) pair)')
    if sspec.get('podManagementPolicy') != 'Parallel':
        bad(f't2: {rel_dev} DEPLOYED render — podManagementPolicy is {sspec.get("podManagementPolicy")!r}, expected Parallel (D62 belt — the exact freeze class from EXPLORE Round-6 A1: one pending ordinal must never block registration of the ordinals behind it)')
    spod = ((ssts[0].get('spec') or {}).get('template') or {}).get('spec') or {}
    snames = {(c or {}).get('name') for c in (spod.get('initContainers') or [])}
    if 'register' not in snames:
        bad(f't2: {rel_dev} DEPLOYED render — initContainers are {sorted(snames)}, expected the register init next to dind (C17: the deployed shape exists for the per-ordinal self-registration)')
    srunner = next((c for c in (spod.get('containers') or []) if (c or {}).get('name') == 'runner'), {})
    if any((e or {}).get('name') == 'CREDENTIALS_DIRECTORY' for e in ((srunner or {}).get('env') or [])):
        bad(f't2: {rel_dev} DEPLOYED render — the daemon container still carries CREDENTIALS_DIRECTORY (C17 retires the env/Secret pair on the PVC-arrived config; the standalone renders pin the shape, this is the deployed witness)')
    svcts = {(v.get('metadata') or {}).get('name'): (v.get('spec') or {}) for v in (sspec.get('volumeClaimTemplates') or [])}
    if set(svcts) != {'data', 'docker-data'}:
        bad(f't2: {rel_dev} slice render — volumeClaimTemplates named {sorted(svcts)}, expected [data, docker-data] (the per-pod shape is not what scaled)')
    ok(f't2: {rel_dev} with the services slice — replicas 10 + podManagementPolicy Parallel + register init + no CREDENTIALS_DIRECTORY (one token, ten records — D61), VCTs unchanged data + docker-data')

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
        # C17 reader move: the config skeleton renders from the release
        # ConfigMap; the ESO-template limb only keeps this URL-flow ruling
        # green against the pre-C17 tree (t2/t12/t21 pin the new shape).
        cms = [d for d in docs if d.get('kind') == 'ConfigMap']
        if cms:
            cfg = yaml.safe_load(((cms[0].get('data') or {}).get('config.yaml') or ''))
        else:
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
# --- t14: baked-toolchain capability record beside the labels map (red-first) -
# The cf-55 fix round re-derives cf-104's LFS record to the baked truth
# (D41/C06): the record must name the image the four 24.04-family labels
# resolve to, helm+cr as IN-image facts, the manual calendar-pin bump, and —
# only on the act-22.04 limb — the installer-pin caveat; the no-digest rule
# and the git-lfs↔labels binding survive. The labels map itself stays t2's
# (ACT_LABELS), and the dev trio-exemption comment window stays t5's (since
# the cf-6 OQ-A narrowing the capture ends before the next entry's leading
# comment — the false-positive class this suite carried), so neither is
# re-checked here.
if python3 - "$RUNNER/templates/secret-runner.yaml" "$RUNNER/values.yaml" "$WORK/t14-count" <<'PY'
import re, sys

tpl_old, tpl_new, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# The shipped caveat wraps across comment lines, so every pattern runs on the
# whitespace-collapsed record, never on raw lines (t11's precedent).
def collapse(parts):
    return ' '.join(' '.join(parts).split())

def strip_marker(line):
    return re.sub(r'^\s*#\s?', '', line)

def near(text, a, b, window=200):
    # True if some match of `a` has a match of `b` within `window` chars.
    ar, br = re.compile(a, re.I), re.compile(b, re.I)
    for m in ar.finditer(text):
        lo = max(0, m.start() - window)
        if br.search(text[lo:m.end() + window]):
            return True
    return False

try:
    # C17 home first: the config body (with its labels-map record) moves
    # from the retired ESO template into the values.yaml ConfigMap skeleton,
    # rendered via `.Values.runner.labels | toYaml`. The template limb only
    # keeps the pre-C17 tree readable — t2/t12 pin the new shape outright.
    lines = labels_idx = tpl = None
    for cand in (tpl_new, tpl_old):
        ls = open(cand).read().splitlines()
        ix = next((i for i, l in enumerate(ls)
                   if re.match(r'^\s*labels:\s*$', l)
                   and i + 1 < len(ls) and 'runner.labels | toYaml' in ls[i + 1]), None)
        if ix is None and cand == tpl_old:
            ix = next((i for i, l in enumerate(ls) if re.match(r'^\s*labels:\s*$', l)), None)
        if ix is not None:
            lines, labels_idx, tpl = ls, ix, cand
            break
    if lines is None:
        bad(f't14: no labels-map anchor — {tpl_new} has no `labels:` key rendered via the runner.labels toYaml line (the C17 home beside the skeleton), and {tpl_old} carries no legacy map either; re-derive the leg if the record moved again')

    block = []
    i = labels_idx - 1
    while i >= 0:
        s = lines[i].strip()
        if s.startswith('#'):
            block.insert(0, strip_marker(lines[i]))
        elif s:
            break
        i -= 1
    j = labels_idx + 1
    while j < len(lines):
        s = lines[j].strip()
        if s.startswith('#'):
            block.append(strip_marker(lines[j]))
        elif s.startswith('-') and 'docker://' in s:
            pass
        elif not s:
            pass
        else:
            break
        j += 1
    if not block:
        bad(f't14: {tpl} has no comment beside the labels map — the labels only provably carry their toolchain if the map documents what its images ship (cf-104 C04 + cf-55 fix round)')
    record = collapse(block)

    if 'sha256:' in record:
        bad(f't14: the record embeds an image digest ({record[record.index("sha256:"):][:40]}…) — digests here go stale silently and no renovate manager reads these lines; the verified base digest lives in the ticket EXPLORE note, not in the chart')
    ok('t14: a comment block sits beside the labels map and carries no pinned digest')

    if 'curatedforest/forgejo-runner' not in record:
        bad('t14: the record does not name curatedforest/forgejo-runner — since the cf-6 run-1 re-point (2026-11-22, family B per-release) the act-24.04-family labels resolve to the repo-built baked job image on the instance registries (chart default git.spencerslab.com, dev slice git.scifi.farm — the bare org/name substring covers both hosts), and the block beside the map is where that fact is recorded (cf-55 D39 lineage)')
    ok('t14: the record names the baked image the 24.04-family labels resolve to')

    if not re.search(r'git[\s-]*lfs', record, re.I):
        bad('t14: the record never names git-lfs — jobs must see that the label set maps to LFS-capable images (EXPLORE R2b)')
    if not near(record, r'label', r'git[\s-]*lfs'):
        bad('t14: git-lfs is not tied to the label set — the record has to say the advertised labels map to images carrying git-lfs, not that LFS exists somewhere')
    ok('t14: the record states that the label set maps to git-lfs-bearing images')

    if not (near(record, r'\bhelm\b', r'\bcr\b')
            and near(record, r'\b(?:helm|cr)\b', r'baked|in the image|image ships|inside the image')):
        bad('t14: the record does not name helm and cr as baked into the job image — C07 retires every runtime install only while the map says the toolchain is IN (D33/D37); jobs must verify helm version / cr --version in-job')
    ok('t14: the record states helm and cr are baked into the image (verify in-job)')

    # The installer-pin caveat now belongs to the act-22.04 limb alone: the
    # baked labels inherit git-lfs from their digest-pinned act base, while
    # plain act-22.04 still gets it from the upstream act.sh installer, so
    # its tag alone proves nothing (cf-104 V6 + cf-55 D40).
    if not (near(record, r'22\.04', r'installer|act\.sh', 160)
            and re.search(r'\bpin|not (?:the|from) the tag|never the tag', record, re.I)):
        bad('t14: the act-22.04 limb lost the installer-pin caveat — plain act-22.04 gets git-lfs from the upstream installer (act.sh), NOT from the tagged build, so the tag alone does not prove the binary there; the baked labels inherit from their pinned base instead')
    ok('t14: the act-22.04 limb records git-lfs as installer-pinned (act.sh), not implied by the tag')

    if not ('calendar' in record.lower() and near(record, r'bump|pin', r'manual', 160)):
        bad('t14: the record omits the manual calendar-tag bump law — label pins are immutable calendar tags bumped by hand and re-checked here first; no renovate manager reads these lines, and a rolling ref would freeze at first-pull content (D39)')
    ok('t14: the record states the calendar label pins bump manually')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't14: the wording checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t14-count")))
else
  exit 1
fi
# --- t15: docker-backend config.container is the complete socket contract (red-first) -
# Runner v13.2.0 defaults container.docker_host to "-" — do NOT share the
# daemon socket with job containers — so the chart's docker branch must opt
# in explicitly: without the key the job container has no
# /var/run/docker.sock and docker build dies in the dial (the failed forge
# container-build runs, EXPLORE §2/§4). Exact key-set equality: an added or
# replaced key silently changes what jobs can reach. DESIGNED RED until the
# line lands in templates/secret-runner.yaml's docker branch; without a pin
# here a future revert rides green.
if [ "$skip_helm" -eq 1 ]; then
  skip "t15: docker-backend container pin not run (dependency update unavailable)"
else
  if python3 - "$runner_out_dev" "$runner_out_infra" "$RELEASE_DEV" "$RELEASE_INFRA" "$WORK/container-count" <<'PY'
import sys, yaml

(render_dev, render_infra, rel_dev, rel_infra, count_file) = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

EXPECTED = {'privileged': False, 'docker_host': 'unix:///var/run/docker.sock'}

try:
    for render_file, release in ((render_dev, rel_dev), (render_infra, rel_infra)):
        docs = [d for d in yaml.safe_load_all(open(render_file)) if d]
        es = [d for d in docs if d.get('kind') == 'ExternalSecret']
        if len(es) != 1:
            bad(f't15: {release} — the render has {len(es)} ExternalSecret(s), expected exactly one')
        # C17 reader move (same discipline as t3): the container block rides
        # the ConfigMap skeleton now; the ESO-template limb only keeps the
        # pre-C17 tree readable.
        cms = [d for d in docs if d.get('kind') == 'ConfigMap']
        if cms:
            cfg = yaml.safe_load(((cms[0].get('data') or {}).get('config.yaml') or ''))
        else:
            data = (((es[0].get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
            cfg = yaml.safe_load(data.get('config.yaml') or '')
        container = (cfg or {}).get('container')
        if container != EXPECTED:
            bad(f't15: {release} — the docker-backend config.container is {container!r}, expected exactly {EXPECTED!r} — jobs must reach the in-pod dind socket at /var/run/docker.sock (the runner default "-" shares nothing; cf-6)')
    ok(f't15: both docker-backend releases render config.container exactly as privileged false + docker_host unix:///var/run/docker.sock (complete job→dind socket contract, cf-6)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't15: the container-block checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/container-count")))
  else
    exit 1
  fi
fi

# --- t16: host-backend config keeps the container block OFF (green-first) --
# The cf-6 fix belongs to the docker branch of the template gate ONLY; host
# releases execute jobs in the runner container itself, where a container:
# block is docker-mode syntax (card #88 shape, EXPLORE §7). Green before and
# after the fix — its job is to turn a future wrong-branch fix red. The
# null-outs mirror the release-slice contract; the template's C03 gate
# refuses to render host mode while docker-only structures survive, so a
# surviving dind/DOCKER_HOST/socket fails this leg loudly at render time.
if [ "$skip_helm" -eq 1 ]; then
  skip "t16: host-backend companion not run (dependency update unavailable)"
else
  host_out="$WORK/runner-render-host.yaml"
  if ! "$helm_bin" template host-probe "$runner_copy" \
      --set "bitwardenIds.runner-token=$TEST_UUID_DEV" \
      --set runner.backend=host \
      --set 'app-template.controllers.runner.initContainers.dind=null' \
      --set 'app-template.controllers.runner.containers.runner.env.DOCKER_HOST=null' \
      --set 'app-template.persistence.socket=null' \
    >"$host_out" 2>"$WORK/runner-render-host.err"; then
    tail -n 30 "$WORK/runner-render-host.err" >&2
    fail "t16: helm template of $RUNNER (runner.backend=host with the three slice null-outs) failed (log kept at $WORK/runner-render-host.err)"
  fi
  if python3 - "$host_out" "$WORK/host-count" <<'PY'
import sys, yaml

host_out, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    docs = [d for d in yaml.safe_load_all(open(host_out)) if d]
    es = [d for d in docs if d.get('kind') == 'ExternalSecret']
    if len(es) != 1:
        bad(f't16: the host render has {len(es)} ExternalSecret(s), expected exactly one')
    # C17 reader move (as t3/t15); host mode also keeps the register init —
    # the per-ordinal self-registration is backend-AGNOSTIC by D63(3): host
    # releases inherit the mechanism, they just null the dind sidecar.
    cms = [d for d in docs if d.get('kind') == 'ConfigMap']
    if cms:
        cfg = yaml.safe_load(((cms[0].get('data') or {}).get('config.yaml') or ''))
    else:
        data = (((es[0].get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
        cfg = yaml.safe_load(data.get('config.yaml') or '')
    if set(cfg) != {'cache', 'host', 'runner', 'server'}:
        bad(f't16: the host-backend config keys are {sorted(cfg)}, expected exactly [cache, host, runner, server]')
    if 'container' in (cfg or {}):
        bad(f't16: the host-backend config gained a container block ({cfg["container"]!r}) — the socket-share fix is docker-branch-only; host mode executes jobs in the runner container')
    if ((cfg or {}).get('cache') or {}).get('dir') != '/data/cache':
        bad(f't16: the host skeleton cache.dir is {((cfg or {}).get("cache") or {}).get("dir")!r}, expected /data/cache (AC4 backend branch: the host cache rides the release data PVC so a re-attach wakes warm)')
    if ((cfg or {}).get('host') or {}).get('workdir_parent') != '/data/workdir':
        bad(f't16: the host skeleton host.workdir_parent is {((cfg or {}).get("host") or {}).get("workdir_parent")!r}, expected /data/workdir (AC4 backend branch)')
    hspec = ((next((d for d in docs if d.get('kind') == 'StatefulSet'), {}).get('spec')) or {})
    hics = (((hspec.get('template') or {}).get('spec') or {}).get('initContainers') or [])
    if not any((c or {}).get('name') == 'register' for c in hics):
        bad(f't16: the host render lost the register init — per-ordinal self-registration is backend-agnostic (D63(3): host releases inherit the mechanism; the null-outs target dind/DOCKER_HOST/socket only)')
    ok('t16: the host-backend render keeps config keys exactly [cache, host, runner, server] (cache.dir + workdir_parent on the data PVC, no container block) and retains the register init — branch separation and the backend-agnostic registration both intact')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't16: the host-render checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/host-count")))
  else
    exit 1
  fi
fi
# --- t17: dev release's own-registry labels override via the slice (red-first) -
# The appset merges ONLY the top-level forgejo-runner-dev: slice into the dev
# release, so from cf-6-debug-forge-runner-docker-1 (2026-11-22, family B
# per-release ruling) the dev job-image labels come from that slice: the dev
# runner pulls its OWN instance registry (git.scifi.farm/curatedforest/
# forgejo-runner), not the infra-registry chart default. Helm REPLACES lists
# wholesale — planning proved a four-entry overlay silently DROPPED
# ubuntu-22.04 — so this leg pins the EXACT five-set, the act-22.04 entry
# byte-identical to the chart default's, the slice url, and run-0's
# container block surviving the overlay (a partial or mistyped override must
# die here, loudly, never as a silently label-less runner). DESIGNED RED from
# authoring until the DEV slice hunk lands: today the slice carries only
# runner.url, so the overlay render shows the chart default, not the dev set.
if [ "$skip_helm" -eq 1 ]; then
  skip "t17: dev-slice overlay render not run (dependency update unavailable)"
else
  t17_slice="$WORK/t17-dev-slice.yaml"
  if ! python3 - "$DEV_VALUES" "$t17_slice" <<'PY'
import re, sys, yaml

src, out = sys.argv[1:3]
# Same lenient anchor handling as t5's loader (REDEFINED anchors are legal
# YAML that PyYAML refuses to compose).
lines = []
with open(src) as f:
    for line in f:
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
d = yaml.safe_load(''.join(lines)) or {}
block = d.get('forgejo-runner-dev')
if not isinstance(block, dict):
    print(f'FAIL: t17: {src} has no top-level forgejo-runner-dev: slice to extract — the appset merges only this key into the dev release', file=sys.stderr)
    sys.exit(1)
with open(out, 'w') as f:
    yaml.safe_dump(block, f)
PY
  then
    exit 1
  fi
  t17_out="$WORK/t17-render.yaml"
  if ! "$helm_bin" template "$RELEASE_DEV" "$runner_copy" \
      -f "$t17_slice" \
      --set "bitwardenIds.runner-token=$TEST_UUID_DEV" \
    >"$t17_out" 2>"$WORK/t17-render.err"; then
    tail -n 30 "$WORK/t17-render.err" >&2
    fail "t17: helm template of $RUNNER (release $RELEASE_DEV, -f the extracted forgejo-runner-dev slice) failed (log kept at $WORK/t17-render.err)"
  fi
  if python3 - "$t17_out" "$runner_out_dev" "$WORK/t17-count" <<'PY'
import sys, yaml

t17_render, default_render, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# The dev five-set (AC2): four git.scifi.farm calendar refs + the plain
# act-22.04 entry the override must re-declare (Helm replaces lists — the
# act-22.04 line carries no forgejo-runner ref, so it disappears from a
# partial override).
DEV_LABELS = {
    'ubuntu-latest:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1',
    'ubuntu-24.04:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1',
    'ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04',
    'docker:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1',
    'node22:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1',
}
# The slice's own values, restated here so a slice hunk that fixes labels
# but moves the url or breaks the container merge dies naming t17.
SLICE_URL = 'http://dev-forgejo-http:3000'
CONTAINER = {'privileged': False, 'docker_host': 'unix:///var/run/docker.sock'}

def labels_and_conn(render_file):
    docs = [d for d in yaml.safe_load_all(open(render_file)) if d]
    es = [d for d in docs if d.get('kind') == 'ExternalSecret']
    if len(es) != 1:
        bad(f't17: the render has {len(es)} ExternalSecret(s), expected exactly one')
    # C17 reader move: the five-set pin rides the ConfigMap skeleton (the
    # byte-identity law moved with the config, D62); the template limb only
    # keeps the pre-C17 tree readable.
    cms = [d for d in docs if d.get('kind') == 'ConfigMap']
    if cms:
        cfg = yaml.safe_load(((cms[0].get('data') or {}).get('config.yaml') or ''))
    else:
        data = (((es[0].get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
        cfg = yaml.safe_load(data.get('config.yaml') or '')
    conns = (((cfg or {}).get('server') or {}).get('connections') or {})
    if set(conns) != {'default'}:
        bad(f't17: config connections are {sorted(conns)}, expected exactly [default]')
    return cfg, conns['default']

try:
    raw = open(t17_render).read()
    cfg, conn = labels_and_conn(t17_render)
    labels = conn.get('labels') or []
    if len(labels) != 5:
        bad(f't17: the slice overlay rendered {len(labels)} labels {sorted(labels)}, expected exactly 5 — Helm REPLACES lists wholesale, so every entry the dev release must advertise has to be re-declared in the slice; a dropped entry is invisible to the runner until a job requests it and dies unscheduled (cf-6 run-1 planning trap)')
    if set(labels) != DEV_LABELS:
        bad(f't17: the dev release labels are {sorted(labels)}, expected the dev five-set {sorted(DEV_LABELS)} — four git.scifi.farm/curatedforest/forgejo-runner calendar refs (own-registry pull, owner ruling 2026-11-22) plus the plain act-22.04 entry')
    _, default_conn = labels_and_conn(default_render)
    default22 = [l for l in (default_conn.get('labels') or []) if l.startswith('ubuntu-22.04:')]
    got22 = [l for l in labels if l.startswith('ubuntu-22.04:')]
    if got22 != default22:
        bad(f't17: the re-declared ubuntu-22.04 entry is {got22!r} but the chart default renders {default22!r} — the override must copy the act-22.04 line byte-identical, or the two releases advertise the same label with different backends')
    if conn.get('url') != SLICE_URL:
        bad(f't17: the overlay render has default.url {conn.get("url")!r}, expected the slice url {SLICE_URL!r} — the labels override must not disturb the per-app URL flow (t5/t9/t10 pin it elsewhere)')
    if (cfg or {}).get('container') != CONTAINER:
        bad(f't17: the overlay render config.container is {(cfg or {}).get("container")!r}, expected exactly {CONTAINER!r} — run-0 pinned this block so jobs reach the in-pod dind socket; the slice overlay must not disturb it')
    if 'OVERRIDE_' in raw:
        bad('t17: the overlay render carries an OVERRIDE_* sentinel after --set of the sentinel UUID')
    # C17: the same five-set must reach the registration PAYLOAD from a
    # single chart source (D62 uniform-routing law) — either the register
    # init carries the label strings itself, or it mounts the skeleton
    # ConfigMap they now live in. A divergent second baked copy is the
    # Declare-thrash class the round corrected out of the record.
    t17_docs = [d for d in yaml.safe_load_all(open(t17_render)) if d]
    t17_sts = next((d for d in t17_docs if d.get('kind') == 'StatefulSet'), None)
    t17_pod = ((((t17_sts or {}).get('spec') or {}).get('template') or {}).get('spec') or {})
    t17_reg = next((c for c in (t17_pod.get('initContainers') or []) if (c or {}).get('name') == 'register'), None)
    if t17_reg is None:
        bad('t17: the dev-slice overlay render has no register init — the payload-labels law needs its carrier (t2 pins presence; this leg owns the payload shape)')
    rj = ' '.join((t17_reg.get('command') or []) + (t17_reg.get('args') or []))
    if 'docker://' in rj:
        missing = [l for l in labels if l not in rj]
        if missing:
            bad(f't17: the register init inlines labels that DIVERGE from the skeleton five-set: {missing[:3]} — the POST payload must advertise EXACTLY the chart set (D62: every row carries the identical set so jobs route uniformly)')
    else:
        cm_vols = {(v or {}).get('name') for v in (t17_pod.get('volumes') or []) if (v or {}).get('configMap')}
        if not any((m or {}).get('name') in cm_vols for m in (t17_reg.get('volumeMounts') or [])):
            bad('t17: the register init takes the labels neither inline nor via the skeleton ConfigMap mount — the five-set would reach the payload from an unrendered source (fork class); mount the ConfigMap or render the set from the chart values')
    ok('t17: the extracted forgejo-runner-dev slice renders the dev five-set on git.scifi.farm + byte-identical act-22.04, exactly 5 labels, the slice url, run-0 container block, zero sentinels, and the register init takes the same set from the single chart source (list-replacement + uniform-payload traps pinned)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't17: the dev-slice overlay render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t17-count")))
  else
    exit 1
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
        bad(f't5: {dev_vals} has charts.{UNWIRED_KEY} again — dev deploys the dev runner only (user decision 2026-10-25; the infra dial-out rides the gpu-cluster release since cf-104 e824542f8)')
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
    at_sibling = False
    while i < len(lines):
        l = lines[i]
        s = l.strip()
        if s and not s.startswith('#'):
            if (len(l) - len(l.lstrip())) <= hi_indent:
                at_sibling = True
                break
        i += 1
    if at_sibling:
        # cf-6 OQ-A: the contiguous comment run immediately above the next
        # sibling key documents THAT entry, not this one — reading it into
        # this block is how cf-93's "appName == chart name for both" pair
        # comment turned into this leg's false positive. Step back over it.
        k = i - 1
        while k > hi and lines[k].lstrip().startswith('#'):
            k -= 1
        i = k + 1
    region = lines[j + 1:i]
    comments = [l for l in region if l.strip().startswith('#')]
    block_text = '\n'.join(comments)
    # The rationale wraps across comment lines, so the phrase checks run on
    # the whitespace-collapsed text (t14's precedent), never on raw lines.
    flat = ' '.join(block_text.split())
    if not any(re.search(r'ingress|proxy', c, re.IGNORECASE) for c in comments):
        bad(f't5: the aliased charts entry has no comment explaining the deliberately missing ingress/proxy leg (client-only service)')
    # Single client-only runner since 2026-10-25 (user decision); the infra
    # instance's registration relocation COMPLETED 2026-11-05 (cf-104
    # e824542f8) as the gpu-cluster release. Pins: the corrected comment
    # names the deployed runner, keeps the infra + relocat* vocabulary, and
    # drops the BOTH claim (dead since 2026-10-25); the relocation-pending
    # claim is dead since cf-104 and must not return.
    if re.search(r'\bboth\b', flat, re.IGNORECASE):
        bad('t5: the trio-exemption comment claims BOTH runners dial out — dev deploys forgejo-runner-dev only since 2026-10-25')
    if not re.search(r'forgejo-runner-dev', flat):
        bad('t5: the trio-exemption comment does not name the single deployed runner (forgejo-runner-dev)')
    if not (re.search(r'infra', flat, re.IGNORECASE) and re.search(r'relocat\w*', flat, re.IGNORECASE)):
        bad('t5: the trio-exemption comment no longer records the infra-instance relocation vocabulary (infra + relocat*)')
    if re.search(r'relocat\w*\b.{0,60}\bpending\b|pending\b.{0,60}relocat', flat, re.IGNORECASE):
        bad('t5: the trio-exemption comment claims the infra relocation is still pending — cf-104 (e824542f8, 2026-11-05) completed it')
    ok('t5: the aliased entry carries the client-only comment for the single runner (infra relocation recorded as done; no BOTH/pending claims; still no ingress entry)')

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
        bad(f't7: {dev_cv} still wires {UNWIRED_KEY} ({(cv[UNWIRED_KEY] or {}).get("bitwardenIds")}) — dev no longer deploys the infra runner (user decision 2026-10-25; the relocated infra dial-out rides the gpu-cluster release since cf-104 e824542f8); the vault item stays, the dev slot must not')
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
    ok('t8: sentinel parity 1<->1 — the single chart sentinel matches exactly the one deployed custom-values slot (UUID or OVERRIDE_NEEDED, never the service sentinel); the infra app stays un-wired (its runner rode cf-104\'s 2026-11-05 relocation to the gpu cluster)')
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
    # The addition list moved 2026-11-21 (cf-6-debug-forge-runner-docker,
    # coord OQ-E ruling): cf-93/C10 (2026-11-01) landed the dev HA sandbox,
    # and this pin never re-pinned for it — the leg has been red ever since,
    # masked behind t5's fail-stop. The rule itself is unchanged: anything
    # beyond the sanctioned hosts is still unapproved.
    base4 = {'coder', 'git', 'research', 'cluster'}
    if not base4 <= set(subs):
        bad(f't9: dev ingress.subdomains lost {sorted(base4 - set(subs))} — expected at least coder/git/research/cluster')
    runners = sorted(set(subs) & {'forgejo-runner-dev', 'forgejo-runner-infra'})
    if runners:
        bad(f't9: dev ingress.subdomains carries runner entries {runners} — the runners are client-only, so they get NO ingress entry')
    unapproved = sorted(set(subs) - (base4 | {'searxng', 'home-assistant'}))
    if unapproved:
        bad(f't9: dev ingress.subdomains carries unapproved entries {unapproved} — only coder/git/research/cluster plus the dev-mcp-fleet C01 searxng host and the cf-93/C10 home-assistant host are sanctioned')
    ok('t9: dev ingress.subdomains within the approved set (original four + searxng + cf-93 home-assistant; no runner entry, no unapproved addition)')

    # Sentinels may remain only inside the appset-generator resource (the
    # values blob, where per-app placeholders ride to the base chart). The
    # pinned OVERRIDE_NEEDED tolerance for forgejo-token-canonical was
    # retired together with that wiring (removed unused 2026-10-26), so NO
    # non-appset document may carry any OVERRIDE_ string. A future must-fill
    # slot needs its own contract amendment, not a widened allow — the
    # github-mcp allowance was retired the same way by the DECISIONS
    # 2026-10-24 post-approval ruling (the real items exist — dev-github
    # LOGIN 522b1cc4 reused for github-mcp, searxng LOGIN f90806ff).
    # This leg's own amendment is the 2026-11-21 cf-6-debug-forge-runner-docker
    # coord OQ-E ruling below: ONE dated, permissive-anchored exemption for
    # the three home-assistant bitwardenIds placeholders the OWNER's C10
    # delta comment in custom-values/dev/prod-values.yaml (2026-11-01)
    # sanctions verbatim — "Until the owner pastes the id, dev's
    # home-assistant ExternalSecrets fail to resolve (NotReady — visibly
    # broken by design; one id fills all three)". The exemption is a
    # tolerance, never a demand: once the ids are pasted these paths stop
    # holding the sentinel, it matches nothing, and the leg stays green —
    # no edit owed here; the block then retires with the close-out-sweep
    # card. Any OTHER occurrence — a fourth home-assistant key, another
    # slice, another app, another custom-values file's sentinel — reddens
    # here, on the render side (A) and at the source (B).
    raw = open(render).read()
    SENT = 'OVERRIDE_VIA_CUSTOM_VALUES'
    HA_INTERIM_IDS = {'home-assistant-pg', 'mcp-pg-grow-assistant',
                      'mcp-pg-grow-assistant-sensors'}
    ha_bw = ((vals.get('home-assistant') or {}).get('bitwardenIds') or {})
    tolerated = {k for k, v in ha_bw.items() if v == SENT}
    if not tolerated <= HA_INTERIM_IDS:
        bad(f't9: the home-assistant slice carries {SENT} on {sorted(tolerated - HA_INTERIM_IDS)} beyond the C10 interim trio — the exemption covers exactly the three ids the owner comment sanctions (cf-6 OQ-E)')
    if raw.count(SENT) > len(tolerated):
        bad(f't9: {raw.count(SENT) - len(tolerated)} {SENT} occurrence(s) beyond the C10 home-assistant interim trio — the -f file must resolve every other sentinel it flows (cf-6 OQ-E)')
    # (B) Source side: the exemption is anchored to one FILE and three
    # KEYS — walk the PARSED values of every custom-values file (a
    # sentinel named in owner prose is a comment, not a placeholder). No
    # file outside dev's may carry it; dev's may carry it only on the trio
    # paths. A sentinel elsewhere is unresolved drift regardless of what
    # the dev render happens to show.
    ALLOWED_SRC = {'home-assistant.bitwardenIds.' + k for k in HA_INTERIM_IDS}
    def sent_paths(node, path, acc):
        if isinstance(node, dict):
            for k, v in node.items():
                sent_paths(v, path + [str(k)], acc)
        elif isinstance(node, list):
            for i, v in enumerate(node):
                sent_paths(v, path + [str(i)], acc)
        elif node == SENT:
            acc.append('.'.join(path))
    import glob as _glob
    offenders = []
    for cf in sorted(_glob.glob('custom-values/*/prod-values.yaml')):
        acc = []
        try:
            data = cv if cf == dev_cv else load(cf)
        except Exception as ex:
            offenders.append(f'{cf} unparsable ({type(ex).__name__})')
            continue
        sent_paths(data, [], acc)
        if cf == dev_cv:
            offenders += [f'{cf}:{p}' for p in acc if p not in ALLOWED_SRC]
        else:
            offenders += [f'{cf}:{p}' for p in acc]
    if offenders:
        bad(f't9: service sentinel outside the C10 home-assistant interim trio at its source: {offenders[:4]} — the exemption is permissive-anchored to custom-values/dev + those three keys; anything else must carry a resolved id, never the placeholder (cf-6 OQ-E)')
    for d in docs:
        if d.get('kind') == 'ApplicationSet':
            continue
        t = yaml.safe_dump(d)
        if 'OVERRIDE_' in t:
            bad(f"t9: non-appset document {((d.get('metadata') or {}).get('name'))!r} carries an OVERRIDE_* string — deploy-time sentinels may ride only in the appset-generator values blob, and the canonical must-fill slot was retired with its wiring")
    ok('t9: OVERRIDE_* strings stay confined to the appset values blob, and the service sentinel rides only the C10 home-assistant interim trio — render side and custom-values source side both anchored (canonical slot retired 2026-10-26; cf-6 OQ-E exemption)')

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

# --- t11: wording truthfulness at the cf-97 sites (re-aimed for C17/D61(3)) --
# The same four sites (values.yaml bitwardenIds block, secret-runner.yaml
# header, custom-values dev item comment, NOTES.txt one-time-action block)
# carry the ROUND-6 truth at the first three: the item's password IS the
# instance-scope registration token (owner-minted at Admin -> Actions ->
# Runners, UA-R6-3, D64 repurpose-existing-items). The cf-97-era claim — a
# (uuid, token) record pair shown once at record creation, "NOT the
# deprecated registration-token exchange" — is the retired truth and may
# only survive negated or historical. Instance-admin scope stays a
# presence-only claim (B3 reaffirmed). NOTES.txt is OUT of C17's
# Files-in-scope: its legs keep the old text byte-pinned and the
# stray-positive guard doubles as the scope guard (its staleness vs the new
# shape is a coord-flagged open question, not a silent re-aim). What must
# NOT change is pinned by the render legs above (t2/t3/t12 — the re-aimed
# ESO-contract legs, t5/t7-t10 trio/slice legs) — C17 lands comments only
# here, so raw byte equality is deliberately not asserted (template
# comments ride the helm output).
if python3 - "$RUNNER/values.yaml" "$RUNNER/templates/secret-runner.yaml" \
    "$RUNNER/templates/NOTES.txt" "$DEV_CV" "$WORK/t11-count" <<'PY'
import re, sys

chart_vals, secret_tpl, notes_txt, dev_cv, count_file = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# The shipped misnomer wraps across comment lines (custom-values splits
# "registration"/"token" at 84/85), so every pattern below runs on the
# whitespace-collapsed site block, never on raw lines.
def collapse(parts):
    return ' '.join(' '.join(parts).split())

TOKEN_RE = re.compile(r'registration[\s-]+token', re.I)
NEG_RE = re.compile(r'\b(?:not|never|deprecated|no longer)\b', re.I)
# C17/D61(3) inverts the cf-97 mapping law: the vault password IS the
# registration token now, so the OLD mapping claim (password = the runner
# record token) becomes the misnomer this leg bans at re-aimed sites.
MAPPING_BAD_RE = re.compile(r'password\s*=\s*(?:the\s+)?(?:runner|long-lived)[\s-]+token', re.I)
RECORD_RE = re.compile(r'\(\s*uuid\s*,\s*token\s*\)|runner record|record creation|shown once at record|uuid\s*=\s*(?:the\s+)?runner\s+uuid', re.I)
NEG_WINDOW = 100

def excerpt(text, m):
    return '…' + text[max(0, m.start() - 40):m.end() + 40] + '…'

def stray_positive(text, label):
    # Kept for the NOTES.txt site (out of C17 scope): a positive
    # "registration token" mention there means the file was touched — the
    # scope guard. Re-aimed sites get the opposite rule below.
    for m in TOKEN_RE.finditer(text):
        if not NEG_RE.search(text[max(0, m.start() - NEG_WINDOW):m.start()]):
            bad(f't11: {label} — positive "registration token" mention: {excerpt(text, m)} '
                '(NOTES.txt is out of C17 Files-in-scope; folding it in is a coord ruling, not a dev edit)')

def stray_record(text, label):
    # Retired record-pair claims may only survive behind a negation or a
    # historical marker — an un-negated one tells the owner to mint a
    # runner record, the exact shape D61 replaces.
    HIST_RE = re.compile(r'\b(?:not|never|no longer|deprecated|retired|superseded|historical|historically|used to|formerly|was|C16|C0[1-6]|round[- ][45])\b', re.I)
    for m in RECORD_RE.finditer(text):
        if not HIST_RE.search(text[max(0, m.start() - NEG_WINDOW):m.start()]):
            bad(f't11: {label} — un-negated record-pair claim: {excerpt(text, m)} '
                '(the (uuid, token) item content is retired; C17 header re-truths may keep it historical at most)')

def strip_marker(line):
    return re.sub(r'^\s*#\s?', '', line)

def comment_block(path, block_re, label):
    """Comment lines sitting directly above the runner-token key the block documents."""
    with open(path) as f:
        lines = f.read().splitlines()
    start = next((i for i, l in enumerate(lines) if re.match(block_re, l)), None)
    if start is None:
        bad(f't11: {label} — no {block_re!r} block in {path} (the site moved; re-derive the leg)')
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].strip() and not lines[i].lstrip().startswith('#') and lines[i][0] not in (' ', '\t'):
            end = i
            break
    key = next((i for i in range(start + 1, end) if re.match(r'^[ \t]+runner-token:', lines[i])), None)
    if key is None:
        bad(f't11: {label} — no runner-token key inside the block in {path} '
            '(the key is contract-pinned by t5/t7/t8 — it must not move or rename)')
    block, i = [], key - 1
    while i > start:
        s = lines[i].strip()
        if s.startswith('#'):
            block.insert(0, strip_marker(lines[i]))
        elif s:
            break
        i -= 1
    if not block:
        bad(f't11: {label} — no comment block directly above the runner-token key in {path}')
    return collapse(block)

def header_block(path, label):
    """Leading template-file comments, up to the first non-comment line."""
    block = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if s.startswith('#'):
                block.append(strip_marker(line))
            elif s:
                break
    if not block:
        bad(f't11: {label} — {path} has no leading comment header')
    return collapse(block)

def check_comment_site(label, text):
    m = MAPPING_BAD_RE.search(text)
    if m:
        bad(f't11: {label} — mapping comment still reads {excerpt(text, m)} (D61(3)/C17 Tasks: the vault password IS the instance-scope registration token, owner-minted — re-truth this site)')
    stray_record(text, label)
    if not TOKEN_RE.search(text):
        bad(f't11: {label} — no registration-token wording at all (the C17 header re-truth has not landed at this site)')
    if all(NEG_RE.search(text[max(0, m.start() - NEG_WINDOW):m.start()]) for m in TOKEN_RE.finditer(text)):
        bad(f't11: {label} — every registration-token mention is negated (the old C02 polarity survives; C17 makes the token the POSITIVE item content)')
    if 'forgejo-token' not in text:
        bad(f't11: {label} — the standing NEVER-the-forgejo-token guard is gone (C17 Tasks keep it: that item is the Coder workspace access token, never a runner credential source)')
    ok(f't11: {label} — registration token as the positive item content, record-pair claims retired or historical, forgejo-token guard standing')

try:
    check_comment_site('values.yaml bitwardenIds block',
                       comment_block(chart_vals, r'^bitwardenIds:', 'values.yaml bitwardenIds block'))
    check_comment_site('secret-runner.yaml header', header_block(secret_tpl, 'secret-runner.yaml header'))
    check_comment_site('custom-values dev item comment',
                       comment_block(dev_cv, r'^forgejo-runner-dev:', 'custom-values dev item comment'))

    notes = collapse(open(notes_txt).read().splitlines())
    # (?<![\w.-]) keeps the key reference `.bitwardenIds.runner-token` from
    # standing in for the copy-step's prose "runner token".
    if not re.search(r'(?<![\w.-])runner[\s-]+token\b', notes, re.I):
        bad('t11: NOTES.txt — the copy step does not name the runner token (C02 wording not landed)')
    stray_positive(notes, 'NOTES.txt')
    if not re.search(r'(?i)\b(?:not|never|no longer)\b[^.;]{0,40}ephemeral|ephemeral[^.;]{0,60}\b(?:refus\w*|reject\w*|disallow\w*|unsupport\w*)', notes):
        bad('t11: NOTES.txt — no ephemeral-refusal warning (the daemon refuses ephemeral records — RESEARCH F2)')
    if not re.search(r'(?i)(?:shown|displayed)[\s-]*(?:only[\s-]*)?once', notes):
        bad('t11: NOTES.txt — the shown-once fact is missing (the record token is displayed once at creation)')
    if not re.search(r'(?i)\blogin\b[^.;]{0,40}\busername\b|\busername\b[^.;]{0,40}\blogin\b', notes):
        bad('t11: NOTES.txt — the login username/password field mapping is not stated '
            '(custom fields, notes and the URI are invisible to property: username|password)')
    if not re.search(r'(?i)\badmin\b[^.;]{0,40}\bactions\b[^.;]{0,40}\brunners\b', notes):
        bad('t11: NOTES.txt — the Admin -> Actions -> Runners instance path is gone '
            '(instance-admin is the only path per the user ruling reaffirming B3)')
    ok('t11: NOTES.txt — runner-token copy step, ephemeral refusal, shown-once, login-field mapping, '
       'no positive registration-token mention, instance-admin path present')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't11: the wording checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
then
  checks=$((checks + $(cat "$WORK/t11-count")))
else
  exit 1
fi

# --- t12: ESO shape — single fetched key, NO target.template (re-aimed C17) ---
# The cf-97 C04 leg pinned `mergePolicy: Merge` because the v2 CRD defaults
# it to REPLACE at admission (invisible to repo renders) and Replace drops
# every fetched key the template does not re-emit — the card-#97 lesson: the
# live Secret carried only {config.yaml, token}, the fetched uuid key stayed
# invisible, and a day of diagnosis was lost (DECISIONS 2026-11-02). C17/D62
# deletes the whole target.template block, so the trap becomes MOOT BY
# CONSTRUCTION and this leg pins the replacement shape: exactly ONE fetched
# data entry (registration-token from the item's password field). The lesson
# message keeps its home here rather than in a dead mergePolicy pin. No leg
# reads live state — cluster proof stays owner-side.
if [ "$skip_helm" -eq 1 ]; then
  skip "t12: ESO-shape leg not run (no chart render — dependency update unavailable)"
else
  if python3 - "$runner_out_dev" "$RELEASE_DEV" "$TEST_UUID_DEV" "$WORK/t12-count" <<'PY'
import sys, yaml

render, release, uuid, count_file = sys.argv[1:5]
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
    es = [d for d in docs if d.get('kind') == 'ExternalSecret']
    if len(es) != 1:
        bad(f't12: {release} — the render has {len(es)} ExternalSecret(s), expected exactly one')
    spec = es[0].get('spec') or {}
    target = spec.get('target') or {}
    if target.get('template') is not None:
        bad(f't12: {release} — spec.target.template is still rendered (keys: {sorted(((target.get("template") or {}).get("data") or {}))}) — C17/D62 DELETES the block: the config skeleton moved to the release ConfigMap, and with no template the v2-CRD mergePolicy Replace trap that hid the uuid key of card #97 (fetched keys the template does not re-emit are silently dropped; DECISIONS 2026-11-02) is moot by construction. The engineVersion/mergePolicy pins retire with the block — their lesson lives in this message')
    entries = spec.get('data') or []
    if len(entries) != 1:
        bad(f't12: {release} — spec.data carries {len(entries)} fetched entries ({sorted(((e or {}).get("secretKey")) for e in entries)}), expected exactly 1 — ONE reusable registration token per release (D61); a second key re-opens the (uuid, token) record-pair shape the round retires')
    e0 = entries[0] or {}
    rr = e0.get('remoteRef') or {}
    if (e0.get('secretKey'), rr.get('property')) != ('registration-token', 'password'):
        bad(f't12: {release} — the fetched entry is secretKey {e0.get("secretKey")!r} property {rr.get("property")!r}, expected registration-token from the item password field (the token lives where the old record token lived; D64 repurpose-existing-items)')
    if rr.get('key') != uuid:
        bad(f't12: {release} — remoteRef.key is {rr.get("key")!r}, expected the bitwardenIds.runner-token UUID {uuid!r} — and never a literal like the forgejo-token item (that one is the Coder workspace token: the standing guard, C17 Tasks)')
    ok(f't12: {release} — ESO shape: no target.template (card-#97 trap moot by construction), exactly one fetched key registration-token<-password from {uuid!r}')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't12: the ESO-shape check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t12-count")))
  else
    exit 1
  fi
fi

# --- t13: cf-97 C05 dind-socket group grant + C06 identity pin (red-first) ---
# The daemon passes uuid/token validation and dies at configCheck: ping to
# unix:///var/run/docker.sock returns EACCES. Cause is pinned-image
# arithmetic: docker:29.9.2-dind's base pre-adds group docker at a FIXED gid
# (upstream 29/cli/Dockerfile addgroup) and dockerd serves the socket
# root:docker 0660, so the uid-1000 runner needs group membership (DECISIONS
# 2026-11-02, user ruling shape (a)). supplementalGroups exists only at the
# pod level (container SC has no such field) — the exact chained reads below
# are the placement enforcement, per the C04 t12 lesson. Live socket mode is
# NOT asserted: no pod-exec surface; C03's post-merge re-run is the
# mechanism proof. The posture guards are the reason (a) beat the TCP shapes
# — a mid-review shape switch must flip them and die here.
#
# C06 (user ruling "Add runAsGroup: 1000 before the PR") adds the
# primary-group assertion: the pinned image config declares User: 1000:1000
# but ships no /etc/passwd entry for uid 1000, so containerd's bare-runAsUser
# fallback resolves the primary group as 0 — runAsGroup: 1000 restores the
# image intent. Identity must also stay container-local: pod-level identity
# applies to every container, so kubelet's FsUserFrom (which bails to nil
# while dind carries no uid pin) would resolve a real fs user and recursively
# re-chown the 12 GiB of VCT volumes at apply.
if [ "$skip_helm" -eq 1 ]; then
  skip "t13: socket-group leg not run (no chart render — dependency update unavailable)"
else
  if python3 - "$runner_out_dev" "$RELEASE_DEV" "$WORK/t13-count" <<'PY'
import sys, yaml

render, release, count_file = sys.argv[1:4]
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
    sts = [d for d in docs if d.get('kind') == 'StatefulSet']
    if len(sts) != 1:
        bad(f't13: {release} — the render has {len(sts)} StatefulSet(s), expected exactly one')
    pod = ((sts[0].get('spec') or {}).get('template') or {}).get('spec') or {}
    ics = pod.get('initContainers') or []
    cons = pod.get('containers') or []
    dind = next((c for c in ics if (c or {}).get('name') == 'dind'), None)
    runner = next((c for c in cons if (c or {}).get('name') == 'runner'), None)
    if dind is None or runner is None:
        bad(f't13: {release} — rendered pod lacks the dind or runner container (t2 also pins them)')

    psc = pod.get('securityContext') or {}
    sgs = psc.get('supplementalGroups')
    if not (isinstance(sgs, list) and 2375 in sgs):
        bad(f't13: {release} — pod spec.securityContext.supplementalGroups is {sgs!r}, expected to '
            'contain 2375 — the pinned docker:29.9.2-dind pre-adds group docker at that fixed gid '
            'and serves the socket root:docker 0660 (upstream 29/cli addgroup line); without the '
            'membership the uid-1000 runner gets EACCES on ping — C05 adds the key')
    rsc = runner.get('securityContext') or {}
    if rsc.get('runAsUser') != 1000:
        bad(f't13: {release} — runner securityContext.runAsUser is {rsc.get("runAsUser")!r}, '
            'expected 1000 — the pinned image config declares User: 1000:1000, but the image '
            'ships no /etc/passwd entry for uid 1000, so containerd resolves a bare uid with '
            'primary group 0; identity is only fully specified with runAsGroup: 1000 beside it, '
            'at CONTAINER level — a pod-level pin would let FsUserFrom resolve an fs user and '
            'recursively re-chown the VCTs (C06)')
    ok(f't13: {release} — socket grant in place: pod supplementalGroups carries 2375 '
       '(pod-level only path) + runner runAsUser 1000 explicit')

    # C06 identity block — placement guards first (so a pod-level pin fails
    # with the re-chown explanation), then the presence check (today's
    # designed-red: the runner has no runAsGroup yet).
    for k in ('runAsUser', 'runAsGroup'):
        if k in psc:
            bad(f't13: {release} — the POD securityContext carries {k!r}: pod-level identity '
                'applies to every container including dind, so FsUserFrom resolves an fs user '
                'and kubelet recursively re-chowns both VCTs (2Gi+10Gi, incl /var/lib/docker) '
                'at apply — the identity pins belong on the runner container alone (C06)')
    dsc = dind.get('securityContext') or {}
    for k in ('runAsUser', 'runAsGroup'):
        if k in dsc:
            bad(f't13: {release} — the dind container carries {k!r}: dind must stay without uid '
                'pins so FsUserFrom keeps bailing to nil (ownership stays root:fsGroup, '
                'OnRootMismatch intact); volume re-chown is exactly what C06 keeps closed')
    if rsc.get('runAsGroup') != 1000:
        bad(f't13: {release} — runner securityContext.runAsGroup is {rsc.get("runAsGroup")!r}, '
            'expected 1000 — the pinned image has no /etc/passwd entry for uid 1000, so '
            'containerd resolves a bare runAsUser with primary group 0 (image config declares '
            'User: 1000:1000); the key restores the image intent (user ruling 2026-11-02, C06)')
    ok(f't13: {release} — identity fully specified and container-local: runAsGroup 1000 beside '
       'runAsUser on the runner only; pod SC and dind carry no uid pins, so FsUserFrom bails '
       'to nil and the 12 GiB VCTs keep their root:1000 expectation')

    if (rsc.get('capabilities') or {}).get('drop') != ['ALL']:
        bad(f't13: {release} — runner capabilities.drop is '
            f'{(rsc.get("capabilities") or {}).get("drop")!r}, expected [ALL] — C05 grants the '
            'socket group WITHOUT dropping hardening (shape (a), not a widening)')
    if rsc.get('allowPrivilegeEscalation') is not False:
        bad(f't13: {release} — runner allowPrivilegeEscalation is not false (C05 must keep it)')
    if dind.get('image') != 'docker:29.9.2-dind':
        bad(f't13: {release} — dind image is {dind.get("image")!r}, expected docker:29.9.2-dind — '
            'the 2375 grant is coupled to THIS pin\'s pre-added group; a pin bump must re-check '
            'upstream before either side changes')
    if ((dind.get('securityContext') or {}).get('privileged')) is not True:
        bad(f't13: {release} — dind is no longer privileged (the sidecar pair shape stands; C05 is SC keys only)')
    renv = {(e or {}).get('name'): (e or {}).get('value') for e in runner.get('env') or []}
    if renv.get('DOCKER_HOST') != 'unix:///var/run/docker.sock':
        bad(f't13: {release} — runner DOCKER_HOST is {renv.get("DOCKER_HOST")!r}, expected the in-pod '
            'unix socket — a TCP transport here is the rejected shape (b), not C05')
    denames = {(e or {}).get('name') for e in dind.get('env') or []}
    if 'DOCKER_TLS_CERTDIR' in denames:
        bad(f't13: {release} — dind now carries a DOCKER_TLS_CERTDIR env — the TLS TCP shape (b2) '
            'sneaking in behind the unix socket (C05 Notes: dind container untouched)')
    ok(f't13: {release} — posture intact: drop-ALL, no privilege escalation, privileged dind at the '
       '29.9.2 pin, DOCKER_HOST on the unix socket, no TLS-certdir env (still shape (a))')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't13: the socket-group checks could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t13-count")))
  else
    exit 1
  fi
fi

# --- t18: the deployed services slice carries replicas 10 (C16 leg (a), D57) ----
# The ruling rides the SLICE, never the chart: the appset merges only this
# top-level block, so this static pin is the durable record of where the 10
# lives (t2's overlay render proves it survives the merge).
if ! python3 - "$DEV_VALUES" <<'PY'
import re, sys, yaml

src = sys.argv[1]
lines = []
for line in open(src):
    line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
    line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
    lines.append(line)
d = yaml.safe_load(''.join(lines)) or {}
block = d.get('forgejo-runner-dev')
if not isinstance(block, dict):
    print(f'FAIL: t18: {src} has no top-level forgejo-runner-dev: slice', file=sys.stderr)
    sys.exit(1)
rep = (((block.get('app-template') or {}).get('controllers') or {}).get('runner') or {}).get('replicas')
if rep != 10:
    print(f'FAIL: t18: the dev slice carries app-template.controllers.runner.replicas {rep!r}, expected 10 — owner ruling 2026-11-26 (cf-55 round-5 directive 5, D57 as superseded by D61 for identity): ten poller pods behind ONE reusable registration token, each minting its own runner record; the count and the capacity stay 1, only the identity law changed', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t18: see the t18 detail above"
fi
ok "t18: services/dev/prod/values.yaml forgejo-runner-dev block pins app-template.controllers.runner.replicas: 10 (owner ruling 2026-11-26, D57 count standing under D61 — slice, not chart)"

# --- t19: capacity STAYS 1 in the deployed render (C16 leg (b), D57) ------------
# The owner asked for 10 RUNNERS, not an in-pod queue: 10 pods x capacity 1
# = 10 concurrent jobs, each pod inside its honest dind envelope. The
# stay-1 decision is un-pinned today (scout §D) — this leg fences it, so a
# future capacity bump is a ruling, not drift.
if [ "$skip_helm" -eq 1 ]; then
  skip "t19: not run (dependency update unavailable)"
else
  if ! python3 - "$runner_out_slice" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
# C17 reader move: capacity 1 now rides the ConfigMap skeleton; the ESO-
# template limb only keeps the pre-C17 tree readable (t2/t12 pin the home).
cfg = None
for d in docs:
    if d.get('kind') == 'ConfigMap' and ((d.get('data') or {}).get('config.yaml')):
        cfg = yaml.safe_load(d['data']['config.yaml'])
        break
if cfg is None:
    es = [d for d in docs if d.get('kind') == 'ExternalSecret']
    if not es:
        print('FAIL: t19: the deployed render carries neither the ConfigMap skeleton (C17 home) nor an ExternalSecret template (pre-C17 home) — the config.yaml home moved again and this leg was not re-aimed', file=sys.stderr)
        sys.exit(1)
    data = (((es[0].get('spec') or {}).get('target') or {}).get('template') or {}).get('data') or {}
    cfg = yaml.safe_load(data.get('config.yaml') or '')
cap = ((cfg or {}).get('runner') or {}).get('capacity')
if cap != 1:
    print(f'FAIL: t19: the deployed render carries runner.capacity {cap!r}, expected 1 — the stay-1 is a DECISION and D61 makes it honest per row: ten pods x ten records x capacity 1 = ten concurrent jobs, each inside its own 2cpu/4Gi dind envelope (D57 arithmetic survives verbatim; EXPLORE Round-6 B: the only cap is the client-side per-process budget)', file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "t19: see the t19 detail above"
  fi
  ok "t19: the deployed (slice-overlay) render still carries runner capacity 1 in the ConfigMap skeleton — stay-1 fenced (D57 arithmetic standing under D61: ten rows x one job, not a queue)"
fi

# --- t20: the chart default stays 1 without any override (C16 leg (c), D57) -----
# The amended law keeps the single-pod DEFAULT so a future release cannot
# silently inherit 10: with no slice merged, the STS renders replicas 1.
# (t2's no-override renders are the same witness for the two tested
# releases; this leg names the MUTANT explicitly: chart-default changes
# redden here and in t2's no-override case, per C16 AC3.)
if [ "$skip_helm" -eq 1 ]; then
  skip "t20: not run (dependency update unavailable)"
else
  if ! python3 - "$runner_out_dev" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
sts = [d for d in docs if d.get('kind') == 'StatefulSet']
if len(sts) != 1:
    print(f'FAIL: t20: {len(sts)} StatefulSets in the no-override render, expected exactly 1', file=sys.stderr)
    sys.exit(1)
rep = (sts[0].get('spec') or {}).get('replicas')
if rep != 1:
    print(f'FAIL: t20: the NO-OVERRIDE render is replicas {rep!r}, expected the chart default 1 — D61 keeps the default single (scaling rides per-slice overrides only; a chart flip to 10 would silently multiply EVERY future runner release into ten self-registrations)', file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "t20: see the t20 detail above"
  fi
  ok "t20: chart default renders replicas 1 with no slice — D57's default-single stands under D61: a new release is one pod until a slice rules otherwise"
fi

# --- t21: register init container — behavior pins (C17 red-first) -----------
# D62 A-prime, the load-bearing half: first boot POSTs the registration and
# renders the skeleton onto the ordinal's data PVC; every later boot finds
# the file and re-attaches without a POST. Pinned in BEHAVIOR form (plan
# ruling 4 / AC5) so a registration-client swap (G2) survives the suite:
# names and env keys per C17 Tasks, but the teeth are the semantics —
# guard-first, downward-API name source, release-Secret token plumbing,
# ephemeral false-class, response-to-files write paths, loud failure exit,
# and NO deregistration call anywhere (v13 has no client-side one,
# RESEARCH Q4 [S9 grep] — a DELETE branch would be invented lifecycle).
if [ "$skip_helm" -eq 1 ]; then
  skip "t21: not run (dependency update unavailable)"
else
  if ! python3 - "$runner_out_dev" "$runner_out_slice" "$RELEASE_DEV" <<'PY'
import re, sys, yaml

default_render, slice_render, release = sys.argv[1:4]

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def legs(render_file, tag):
    docs = [d for d in yaml.safe_load_all(open(render_file)) if d]
    sts = next((d for d in docs if d.get('kind') == 'StatefulSet'), None)
    if sts is None:
        bad(f't21: {tag} — no StatefulSet (t2 owns this; naming own dependency)')
    pod = ((((sts.get('spec') or {}).get('template') or {}).get('spec')) or {})
    reg = next((c for c in (pod.get('initContainers') or []) if (c or {}).get('name') == 'register'), None)
    if reg is None:
        bad(f't21: {tag} — no register init container (t2 also pins presence; the script legs need its carrier)')
    script = '\n'.join((reg.get('command') or []) + (reg.get('args') or []))
    if not script.strip():
        bad(f't21: {tag} — the register container carries no command/args — the guard/POST/render sequence must live in the pod, not an unpinnable image default')
    guard = re.search(r'\[\s*-f\s+/data/config/config\.yaml\s*\]', script)
    if not guard:
        bad(f't21: {tag} — script lacks the `[ -f /data/config/config.yaml ]` guard — without it EVERY container restart (reloader Secret-change included) re-POSTs and churns a new uuid per boot, piling stale rows (D62 restart discipline, tooth (c))')
    post = script.find('actions/runners')
    if post < 0:
        bad(f't21: {tag} — no admin-scope registration endpoint in the script — the POST to the runners admin route is the minting path (RESEARCH Q2(b) [S14]); a client that hides the endpoint entirely defeats the behavior pin')
    if guard and guard.start() > post:
        bad(f't21: {tag} — the config guard sits AFTER the registration call — a restart would re-register before ever checking the PVC (guard-FIRST is the re-attach law, D62)')
    envs = {(e or {}).get('name'): e for e in (reg.get('env') or [])}
    pod_name = envs.get('POD_NAME') or {}
    if ((pod_name.get('valueFrom') or {}).get('fieldRef') or {}).get('fieldPath') != 'metadata.name':
        bad(f't21: {tag} — POD_NAME env is {pod_name!r}, expected a downward-API fieldRef metadata.name — the record name IS the pod name (official k8s example shape, RESEARCH [S11]); hostname or ordinal math is the off-by-one class this avoids')
    if not re.search(r'\$\{?POD_NAME\}?', script):
        bad(f't21: {tag} — the script never references POD_NAME — the registration body must carry the pod-derived name (AC5)')
    tok = next(((n, e) for n, e in envs.items() if ((e or {}).get('valueFrom') or {}).get('secretKeyRef')), None)
    if tok is None:
        bad(f't21: {tag} — no env with valueFrom.secretKeyRef — the registration token must arrive from the release Secret (never a literal in values, never the forgejo-token item)')
    skr = (tok[1].get('valueFrom') or {}).get('secretKeyRef') or {}
    if skr.get('key') != 'registration-token' or skr.get('name') != release:
        bad(f't21: {tag} — token env {tok[0]!r} points at secretKeyRef {skr!r}, expected the release Secret {release!r} key registration-token')
    if not re.search(r'\$\{?' + re.escape(tok[0]) + r'\}?', script):
        bad(f't21: {tag} — the fetched token env {tok[0]!r} is never used by the script (dead plumbing is broken plumbing)')
    cm = next((d for d in docs if d.get('kind') == 'ConfigMap'), None)
    cfg = yaml.safe_load((((cm or {}).get('data') or {}).get('config.yaml') or '') or '') or {}
    conn = (((cfg.get('server') or {}).get('connections') or {}).get('default') or {})
    url = conn.get('url')
    if not url:
        bad(f't21: {tag} — skeleton carries no connection url to cross-check the registration target (t2 pins it; this leg names its own dependency)')
    url_env = next((e for e in envs.values() if (e or {}).get('value') == url), None)
    if url_env is None and url not in script:
        bad(f't21: {tag} — the registration target never flows: no env carries the skeleton url {url!r} and the script never names it — one runner.url must feed both the config and the POST (RUNNER_URL per C17 Tasks)')
    if re.search(r'ephemeral[^A-Za-z]{0,8}\btrue\b', script, re.I):
        bad(f't21: {tag} — payload carries ephemeral TRUE — the v13 daemon refuses ephemeral records (exits "not supported in daemon-mode", [S9 daemon.go]) and the server deletes the row after one job: the crash-loop class, tooth (d)')
    if not re.search(r'ephemeral[^A-Za-z]{0,12}\bfalse\b', script, re.I):
        bad(f't21: {tag} — no ephemeral false-class token in the registration payload (REQUIRED, C17 Tasks — the record must persist)')
    for p in ('/data/config/config.yaml', '/data/config/token'):
        if p not in script:
            bad(f't21: {tag} — script never writes {p} — the minted identity must land on the ordinal data PVC (the skeleton render target and the absolute token_url file, D62)')
    ph = conn.get('uuid')
    cm_vols = {(v or {}).get('name') for v in (pod.get('volumes') or []) if (v or {}).get('configMap')}
    mounts_cm = any((m or {}).get('name') in cm_vols for m in (reg.get('volumeMounts') or []))
    if isinstance(ph, str) and ph and ph not in script and not mounts_cm:
        bad(f't21: {tag} — the skeleton uuid placeholder is neither named by the script nor reachable via a mounted skeleton ConfigMap — nothing would substitute it: the daemon would crash on a literal placeholder (fail-fast class)')
    if not any((m or {}).get('mountPath') == '/data' for m in (reg.get('volumeMounts') or [])):
        bad(f't21: {tag} — the register init has no /data mount — it writes onto the data PVC, nowhere else')
    if not re.search(r'set -e|exit 1|\|\|\s*exit|\|\|\s*\{', script):
        bad(f't21: {tag} — no loud failure limb — a swallowed cold-boot error leaves the daemon crash-looping on the unsubstituted placeholder (the empty-uuid fail-fast class the chart header already documents)')
    if re.search(r'deregist|-X\s*DELETE|DELETE\s|deleteRunner', script, re.I):
        bad(f't21: {tag} — the register script carries a deregistration/DELETE limb — v13 has NO client-side deregistration (RESEARCH Q4 [S9 grep]) and D63 rules stale rows OUT of scope (cleanup cron stays OFF; scale-down rows are owner-side)')
    raw = open(render_file).read()
    noc = '\n'.join(l for l in raw.splitlines() if not l.strip().startswith('#'))
    if re.search(r'deregist|-X\s*DELETE', noc, re.I):
        bad(f't21: {tag} — a deregistration call hides somewhere in the render (AC5: none anywhere — no client-side path exists in v13)')

legs(default_render, 'default render')
legs(slice_render, 'DEPLOYED slice render')
PY
  then
    fail "t21: see the t21 detail above"
  fi
  ok "t21: register init pins on both renders — guard-first, downward-API POD_NAME payload, release-Secret registration-token env, skeleton-url cross-check, ephemeral false, PVC write paths, placeholder reachability, loud failure exit, zero deregistration (behavior-form, client-swap survivable — D62/AC5)"
fi

# --- t22: chart-text re-truths + retired-shape statics (C17 red-first) ------
# The headers and shipped comments are operator-facing code: the D61 law,
# the :67-68 "do not work" softening (RESEARCH Contradictions verdict:
# deprecated, not broken — D63(3) folds the reword here at next touch), the
# D63 stale-row runbook, the CREDENTIALS_DIRECTORY pair retiring, and the
# host-mode null-out gate byte-untouched (AC6 — pinned by hash, the same
# byte-identity law class as C03's template comment rule). Chart.yaml's
# false description ("one 1-replica StatefulSet ... declarative
# registration") is retired WITHOUT a version edit (CI law: the fan bumps
# 2026.11.1 -> 2026.11.2 after merge, never this suite).
if ! python3 - "$RUNNER/values.yaml" "$RUNNER/templates/secret-runner.yaml" \
    "$RUNNER/Chart.yaml" <<'PY'
import hashlib, re, sys

chart_vals, secret_tpl, chart_yaml = sys.argv[1:4]

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def collapse(parts):
    return ' '.join(' '.join(parts).split())

def strip_marker(line):
    return re.sub(r'^\s*#\s?', '', line)

def near(text, a, b, window=200):
    ar, br = re.compile(a, re.I), re.compile(b, re.I)
    for m in ar.finditer(text):
        lo = max(0, m.start() - window)
        if br.search(text[lo:m.end() + window]):
            return True
    return False

vtext = open(chart_vals).read()
vlines = vtext.splitlines()
header = []
for line in vlines:
    s = line.strip()
    if s.startswith('#'):
        header.append(strip_marker(line))
    elif s:
        break
h = collapse(header)
if not h:
    bad('t22: values.yaml has no leading comment header — the law text is operator-facing')
if re.search(r'one registration per release', h, re.I):
    bad('t22: the values header still claims one registration PER RELEASE — D61: one registration TOKEN, N records (N pods, N admin rows named after the pods); the title line is the first thing a reader anchors on')
if re.search(r'release runs exactly one\s+pod', h, re.I):
    bad('t22: the values header still claims each release runs EXACTLY ONE POD — dead since D57 and doubly false post-C17')
if not (re.search(r'registration[\s-]+token', h, re.I) and re.search(r'self[- ]register|per[- ]pod|records', h, re.I)):
    bad('t22: the re-aimed law text is missing — the header must positively carry the one-token / per-pod-record mechanism (D61/D62)')
if not re.search(r're-?attach', h, re.I):
    bad('t22: no re-attach wording — the PVC-persisted identity (restart never re-registers, D62) is the design\'s load-bearing half and belongs in the header')
if near(h, r'register CLI', r'do(?:es)? not work'):
    bad('t22: the values header still says the register CLI DOES NOT WORK — RESEARCH Contradictions ruled it deprecated, not broken (D63(3) folds the reword into C17 as the next-touch law)')
if not near(h, r'register CLI', r'deprecated'):
    bad('t22: no deprecated wording beside the register CLI claim — the softened truth (works, discouraged; [S9 register.go]) must land here, not silently disappear')
if not (re.search(r'cleanup_offline_runners', h) and near(h, r'cleanup_offline_runners', r'\boff\b|false|stay')):
    bad('t22: the stale-row runbook is missing the cleanup-cron posture — D63: cron.cleanup_offline_runners STAYS OFF (enabling it can delete rows under live PVCs -> crash-loop until the ordinal config is cleared)')
if not near(h, r'/data/config/config\.yaml', r'delet|remov|clear|rm\b'):
    bad('t22: the runbook limb is missing — row-loss recovery = delete /data/config/config.yaml on that ordinal so the next boot re-registers (D63)')
if not near(h, r'scale-?down', r'offline|stale|row'):
    bad('t22: no scale-down leaves-offline-rows statement (D63 stale-row law — owner-side cleanup, never a client deregister)')
if 'D61' not in vtext:
    bad('t22: nothing in values.yaml cites D61 — the B1-as-amended note retires to superseded-law text naming the ruling that replaced it (C17 Tasks :158-167)')
if re.search(r'CREDENTIALS_DIRECTORY', vtext):
    bad('t22: CREDENTIALS_DIRECTORY survives in values.yaml — the env/token_url pair retires with the Secret mount (D62/G3)')
if re.search(r'file:\$CREDENTIALS', vtext):
    bad('t22: the relative Secret-mount token_url survives in values.yaml — expected the absolute file:/data/config/token')
if 'token_url: file:/data/config/token' not in vtext:
    bad('t22: no absolute token_url wiring in values.yaml — the skeleton must point the daemon at the PVC-written token (AC4)')

stext = open(secret_tpl).read()
snoncomment = '\n'.join(l for l in stext.splitlines() if not l.strip().startswith('#'))
for needle, why in (
    ('template:', 'the ESO inline template retires entirely (D62) — with no template the card-#97 mergePolicy class cannot recur'),
    ('mergePolicy', 'the policy pin rode the retired template block (its lesson lives in the t12 message now)'),
    ('config.yaml', 'the config body belongs to the ConfigMap skeleton, not the ESO'),
    ('uuid', 'no uuid key may survive in the ESO — the fetched record pair is the C16 shape'),
):
    if needle in snoncomment:
        bad(f't22: secret-runner.yaml still carries {needle!r} outside comments — {why}')
if 'secretKey: registration-token' not in snoncomment:
    bad('t22: secret-runner.yaml does not fetch a registration-token key — the single-key ESO rewrite (D62) is C17\'s whole Secret story')
if 'property: username' in snoncomment:
    bad('t22: the username-property fetch survives — the stale uuid field is IGNORED by the new shape (D64), not fetched')
region = None
slines = open(secret_tpl, errors='replace').read().splitlines(keepends=True)
i0 = next((i for i, l in enumerate(slines) if l.startswith('{{- if eq .Values.runner.backend "host" }}')), None)
ia = next((i for i, l in enumerate(slines) if l.startswith('apiVersion:')), None)
if i0 is None or ia is None or ia <= i0:
    bad('t22: the host-mode null-out gate cannot be located in secret-runner.yaml — the gate block ({{- if eq .Values.runner.backend "host" }} ... up to apiVersion:) must SURVIVE the ESO rewrite (AC6: byte-untouched)')
region = ''.join(slines[i0:ia])
GATE_SHA = 'b8425f3c03a04cfcc30cf18fa464c7ef30e09c12e3604db48ce4049f362ba06a'
if hashlib.sha256(region.encode()).hexdigest() != GATE_SHA:
    bad('t22: the host-mode null-out gate region is NOT byte-identical to the C16-era hash (secret-runner.yaml lines 18-52 at 4dfe9a02e) — C17 Tasks KEEP it byte-untouched; the argo-cd#16312 silent-resurrection defense must not be re-flowed by the rewrite')
for m in re.finditer(r'forgejo-token', stext):
    line = stext[max(0, m.start() - 120):m.start()].rsplit('\n', 1)[0]
    # guard sentence only: every mention sits in a comment line (render-side
    # value absence is pinned by the remoteRef legs)
    if not line.lstrip().startswith('#'):
        bad(f't22: a forgejo-token reference rides a live line in secret-runner.yaml: {line.strip()!r} — the standing guard keeps it comment-only and negative')

ctext = open(chart_yaml).read()
if re.search(r'1-replica|one 1-replica', ctext, re.I):
    bad('t22: Chart.yaml still describes ONE 1-replica StatefulSet per release — false since D57 and doubly since D61 (ten self-registering pods); the description re-truth is in C17 Tasks')
if re.search(r'declarative registration', ctext, re.I):
    bad('t22: Chart.yaml still claims declarative registration — C17 moves identity minting to the register-on-boot init (the record is POSTed, not declared)')
if not re.search(r'^version: 20\d\d\.\d{1,2}\.\d{1,2}$', ctext, re.M):
    bad('t22: Chart.yaml version is not a calendar stamp — CI owns bumps (build-charts fan); a hand-edit here is the forbidden class and a rewrite must not smuggle one in')
ok('t22: values header law re-truthed (D61 token/records + re-attach + deprecated + runbook + D61 citation), CREDENTIALS pair gone, absolute token_url wired, ESO static shape single-key and template-free, host gate byte-stable, Chart.yaml lies retired, version untouched')
PY
then
  fail "t22: see the t22 detail above"
fi
ok "t22: chart-text re-truths + single-key ESO statics + gate-hash pin landed (C17 ACs 2/6/7 render-side witnesses)"

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: dev-forgejo-runner checks (%d ok)\n' "$checks"
