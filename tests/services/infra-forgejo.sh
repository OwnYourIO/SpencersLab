#!/usr/bin/env bash
# C02 acceptance checks (2026-10-feat-forgejo-infra-and-runner): the second
# Forgejo instance on infra (charts.forgejo wiring + two generic-ingress
# hosts), the proxy-local hub routing for git.spencerslab.com /
# forgejo.spencerslab.com (crowdsec-only, ExternalName to the infra apex),
# dev render parity after the chart's identity defaults were neutralized,
# the sentinel sweep, the service-trio greps, and the gitea-leftover
# deletions. Criteria 1-7 of chunks/C02.md.
#
# Vendored chart tarballs are not committed for these paths, so dependency
# builds + lint + renders run on COPIES under /tmp/opencode — the worktree
# is never written (repo convention: charts/**/charts is gitignored).
#
# A helm binary is taken from HELM_BIN, the PATH, /home/coder/.local/bin,
# or /tmp/opencode; failing that, helm v3.21.4 is downloaded there (same
# provenance as tests/services/dev-git-auth.sh). If the registry is
# unreachable, t2-t5 are skipped (not failed) and t6 still runs.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/infra-forgejo.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FORGEJO_CHART="charts/forgejo"
INFRA="services/infra/prod"
PROXY="services/proxy-local/prod"
DEVUMB="services/dev/prod"
INFRA_CV="custom-values/infra/prod-values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
PROXY_CV="custom-values/proxy-local/prod-values.yaml"

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
  dir=/tmp/opencode/infra-forgejo-helm-download
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

WORK=$(mktemp -d /tmp/opencode/infra-forgejo.XXXXXX)

# Copy a chart path into WORK and helm-dependency-build it there. Prints the
# copy path on success; on a registry-unreachable failure writes a flag file
# (a subshell cannot set the parent's skip variable) and prints a skip note,
# leaving stdout empty.
build_copy() {
  local chart="$1" flagfile="$2"
  local copy="$WORK/$(printf '%s' "$chart" | tr '/' '_')"
  cp -R "$chart"/. "$copy"/
  local log="$copy/dependency-build.log"
  if ! (cd "$copy" && "$helm_bin" dependency build .) >"$log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$log"; then
      : >"$flagfile"
      printf 'skip: t1: helm dependency build could not reach the registry for %s here; t2-t5 were not run (log kept at %s)\n' "$chart" "$log" >&2
      return 0
    fi
    tail -n 30 "$log" >&2
    printf 'FAIL: t1: helm dependency build failed for %s (log kept at %s)\n' "$chart" "$log" >&2
    exit 1
  fi
  printf '%s' "$copy"
}

skip_helm=0
fj_copy="" infra_copy="" proxy_copy=""

if [ -z "$helm_bin" ]; then
  skip "t1: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; t2-t5 were not run (run the plan's Commands manually)"
  skip_helm=1
else
  fj_copy=$(build_copy "$FORGEJO_CHART" "$WORK/fj-skip")
  [ -f "$WORK/fj-skip" ] && skip_helm=1
  infra_copy=$(build_copy "$INFRA" "$WORK/infra-skip")
  [ -f "$WORK/infra-skip" ] && skip_helm=1
  proxy_copy=$(build_copy "$PROXY" "$WORK/proxy-skip")
  [ -f "$WORK/proxy-skip" ] && skip_helm=1

  if [ "$skip_helm" -eq 1 ]; then
    if [ -n "$fj_copy" ] || [ -n "$infra_copy" ] || [ -n "$proxy_copy" ]; then
      skip "t1: dependency builds only partially reachable (forgejo: ${fj_copy:+yes}${fj_copy:+ }, infra: ${infra_copy:+yes}${infra_copy:+ }, proxy-local: ${proxy_copy:+yes}${proxy_copy:+ }); t2-t5 were not run"
    else
      skip "t1: no dependency build could reach its registry; t2-t5 were not run"
    fi
    skip "t2: helm lint not run (dependency builds unavailable)"
    skip "t3: infra render not run (dependency builds unavailable)"
    skip "t4: proxy-local render not run (dependency builds unavailable)"
    skip "t5: dev parity not run (dependency builds unavailable)"
  else
    ok "t1: helm dependency build succeeds for $FORGEJO_CHART, $INFRA and $PROXY (copies, $("$helm_bin" version --short 2>/dev/null || echo helm))"

    # --- t2: lint (criteria 1) -------------------------------------------
    for entry in "$FORGEJO_CHART|$fj_copy" "$INFRA|$infra_copy" "$PROXY|$proxy_copy"; do
      src=${entry%%|*}; cpy=${entry#*|}
      log="$WORK/lint-$(printf '%s' "$src" | tr '/' '_').log"
      if (cd "$cpy" && "$helm_bin" lint .) >"$log" 2>&1; then
        ok "t2: helm lint passes for $src"
      else
        tail -n 30 "$log" >&2
        fail "t2: helm lint failed for $src (log kept at $log)"
      fi
    done
    log="$WORK/lint-dev.log"
    if "$helm_bin" lint "$DEVUMB" >"$log" 2>&1; then
      ok "t2: helm lint passes for $DEVUMB (no vendored deps — linted in place)"
    else
      tail -n 30 "$log" >&2
      fail "t2: helm lint failed for $DEVUMB (log kept at $log)"
    fi

    # --- t3: infra umbrella render (criteria 2, 5) ------------------------
    # Sentinel --set list straight from the plan's Commands; the rendered
    # ApplicationSet's generator values blob (appset.yaml line 23) is a YAML
    # flow mapping, so python3 yaml reads it directly.
    infra_out="$WORK/infra-render.yaml"
    infra_err="$WORK/infra-render.err"
    if ! "$helm_bin" template "$infra_copy" \
      --set domain=spencerslab.com --set clusterName=infra \
      --set bitwardenIds.keycloak=u --set bitwardenIds.keycloak-pg=u \
      --set bitwardenIds.smtp=u \
      --set hivetools.bitwardenIds.mcp-pg-keycloak=u \
      --set forgejo.bitwardenIds.forgejo=u --set forgejo.bitwardenIds.forgejo-admin=u \
      --set forgejo.bitwardenIds.forgejo-pg=u --set forgejo.bitwardenIds.forgejo-sso=u \
      >"$infra_out" 2>"$infra_err"; then
      tail -n 30 "$infra_err" >&2
      fail "t3: helm template of $INFRA failed (log kept at $infra_err)"
    fi
    [ -s "$infra_out" ] || fail "t3: helm template of $INFRA rendered nothing"
    if python3 - "$infra_out" "$WORK/infra-count" <<'PY'
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
               and (d.get('metadata') or {}).get('name') == 'infra-appset']
    if not appsets:
        bad('t3: no ApplicationSet named infra-appset in the infra render (the umbrella did not render)')
    els = appsets[0]['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
    if len(els) != 1:
        bad(f't3: infra-appset generator list has {len(els)} elements, expected exactly 1')
    vals = els[0].get('values')
    if not isinstance(vals, dict):
        bad('t3: the infra-appset generator element has no values blob (appset.yaml renders the whole service values as JSON)')
    ok('t3: infra-appset generator element carries the values blob')

    cf = (vals.get('charts') or {}).get('forgejo')
    if not isinstance(cf, dict):
        bad('t3: the values blob has no charts.forgejo entry (the infra Forgejo app is not wired into the umbrella)')
    if cf.get('namespace') != 'default':
        bad(f't3: charts.forgejo.namespace is {cf.get("namespace")!r}, expected "default"')
    if str(cf.get('ServerSideApply')) != 'false':
        bad(f't3: charts.forgejo.ServerSideApply is {cf.get("ServerSideApply")!r}, expected "false"')
    ok('t3: values blob has charts.forgejo (namespace default, ServerSideApply "false")')

    subs = (vals.get('ingress') or {}).get('subdomains') or {}
    for host in ('git', 'forgejo'):
        e = subs.get(host)
        if not isinstance(e, dict):
            bad(f't3: the values blob has no ingress.subdomains.{host} entry')
        if e.get('service') != 'infra-forgejo-http':
            bad(f't3: ingress.subdomains.{host}.service is {e.get("service")!r}, expected infra-forgejo-http')
        if e.get('port') != 3000:
            bad(f't3: ingress.subdomains.{host}.port is {e.get("port")!r}, expected 3000')
    ok('t3: values blob routes ingress.subdomains.git and .forgejo to infra-forgejo-http:3000')

    def ingress_for(host):
        for d in docs:
            if d.get('kind') != 'Ingress':
                continue
            for r in (d.get('spec') or {}).get('rules', []):
                if r.get('host') == host:
                    return d
        return None

    for host in ('git.spencerslab.com', 'forgejo.spencerslab.com'):
        ing = ingress_for(host)
        if ing is None:
            bad(f't3: no Ingress renders for host {host} (generic-ingress did not produce the infra Forgejo route)')
        spec = ing.get('spec') or {}
        tls = (spec.get('tls') or [{}])[0]
        if tls.get('secretName') != 'wildcard-cert':
            bad(f't3: the Ingress for {host} uses tls secret {tls.get("secretName")!r}, expected wildcard-cert')
        if host not in (tls.get('hosts') or []):
            bad(f't3: the Ingress tls hosts for {host} are {tls.get("hosts")!r}')
        paths = (spec.get('rules') or [{}])[0].get('http', {}).get('paths', [{}])
        if len(paths) != 1:
            bad(f't3: the Ingress for {host} has {len(paths)} paths, expected 1')
        svc = (paths[0].get('backend') or {}).get('service') or {}
        if svc.get('name') != 'infra-forgejo-http' or svc.get('port', {}).get('number') != 3000:
            bad(f't3: the Ingress for {host} backs to {svc.get("name")}:{(svc.get("port") or {}).get("number")}, expected infra-forgejo-http:3000')
        ok(f't3: Ingress for {host} renders with wildcard-cert, backend infra-forgejo-http:3000')

    raw = open(render).read()
    hits = [l.strip() for l in raw.lower().splitlines() if 'gitea' in l][:3]
    if hits:
        bad('t3: the rendered infra manifests still contain the string "gitea" (dormant leftovers): ' + ' | '.join(hits))
    ok('t3: no "gitea" string anywhere in the rendered infra manifests')
    # The dormant block's LDAP host is the 389ds leftover to catch; a bare
    # "389ds" grep would false-positive on the legitimate charts.389ds chart
    # entry in the values blob.
    for leftover in ('redis-cluster', 'bindDn', 'infra-389ds.default'):
        if leftover in raw:
            bad(f't3: the rendered infra manifests still contain the dormant-forgejo leftover {leftover!r}')
    ok('t3: no redis-cluster/bindDn/infra-389ds.default leftovers in the render')
    if 'OVERRIDE_VIA_CUSTOM_VALUES' in raw or 'OVERRIDE_VIA_APPSET' in raw:
        bad('t3: the rendered infra manifests still carry an OVERRIDE_VIA_* sentinel (the plan --set list did not resolve it)')
    ok('t3: no OVERRIDE_VIA_* sentinel survives in the rendered infra manifests')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't3: the infra render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/infra-count")))
    else
      exit 1
    fi

    # --- t4: proxy-local render (criteria 3, 5) ---------------------------
    proxy_out="$WORK/proxy-render.yaml"
    proxy_err="$WORK/proxy-render.err"
    if ! "$helm_bin" template "$proxy_copy" \
      --set domain=spencerslab.com --set clusterName=proxy-local \
      --set bitwardenIds.argocd-sso-secret=u --set bitwardenIds.autossh-secret=u \
      --set bitwardenIds.traefik-mqtt=u --set authRealm=SpencersLab \
      >"$proxy_out" 2>"$proxy_err"; then
      tail -n 30 "$proxy_err" >&2
      fail "t4: helm template of $PROXY failed (log kept at $proxy_err)"
    fi
    [ -s "$proxy_out" ] || fail "t4: helm template of $PROXY rendered nothing"
    if python3 - "$proxy_out" "$WORK/proxy-count" <<'PY'
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

    def doc_by(kind, name):
        for d in docs:
            if d.get('kind') == kind and (d.get('metadata') or {}).get('name') == name:
                return d
        return None

    CROWDSEC = 'kube-system-crowdsec@kubernetescrd'
    # Crowdsec-only is EXACT equality: the default chain (crowdsec + userAuth)
    # or any redirect middleware fails the check — that is the point of A5.
    for name, host, svc in (('git-ingress', 'git.spencerslab.com', 'git-service'),
                            ('forgejo-ingress', 'forgejo.spencerslab.com', 'forgejo-service')):
        d = doc_by('Ingress', name)
        if d is None:
            bad(f't4: no Ingress named {name} in the proxy-local render')
        ann = (d.get('metadata') or {}).get('annotations') or {}
        mw = ann.get('traefik.ingress.kubernetes.io/router.middlewares')
        if mw != CROWDSEC:
            bad(f't4: Ingress {name} router.middlewares is {mw!r}, expected exactly {CROWDSEC!r} (crowdsec-only, no userAuth)')
        if ann.get('external-dns.alpha.kubernetes.io/target') != 'proxy-remote.spencerslab.com':
            bad(f't4: Ingress {name} external-dns target is {ann.get("external-dns.alpha.kubernetes.io/target")!r}, expected proxy-remote.spencerslab.com')
        labels = (d.get('metadata') or {}).get('labels') or {}
        if labels.get('external-dns') != 'enabled':
            bad(f't4: Ingress {name} lacks the external-dns: "enabled" label (the public record would not be published)')
        spec = d.get('spec') or {}
        tls = (spec.get('tls') or [{}])[0]
        if tls.get('secretName') != 'wildcard-cert':
            bad(f't4: Ingress {name} tls secret is {tls.get("secretName")!r}, expected wildcard-cert')
        rule = (spec.get('rules') or [{}])[0]
        if rule.get('host') != host:
            bad(f't4: Ingress {name} host is {rule.get("host")!r}, expected {host}')
        svcn = ((rule.get('http') or {}).get('paths') or [{}])[0].get('backend', {}).get('service') or {}
        if svcn.get('name') != svc or (svcn.get('port') or {}).get('number') != 443:
            bad(f't4: Ingress {name} backs to {svcn.get("name")}:{(svcn.get("port") or {}).get("number")}, expected {svc}:443')
        ok(f't4: Ingress {name}: crowdsec-only middleware, {svc}:443, external-dns -> proxy-remote.spencerslab.com')

    for name, host, svc in (('git-local-ingress', 'git.spencerslab.com', 'git-service'),
                            ('forgejo-local-ingress', 'forgejo.spencerslab.com', 'forgejo-service')):
        d = doc_by('IngressRoute', name)
        if d is None:
            bad(f't4: no IngressRoute named {name} in the proxy-local render')
        r = ((d.get('spec') or {}).get('routes') or [{}])[0]
        mw = r.get('middlewares')
        if mw != [{'name': CROWDSEC}]:
            bad(f't4: IngressRoute {name} middlewares are {mw!r}, expected exactly one: {CROWDSEC} (crowdsec-only, no userAuth)')
        if r.get('priority') != 100:
            bad(f't4: IngressRoute {name} priority is {r.get("priority")!r}, expected 100 (must beat the Ingress routers)')
        services = r.get('services') or [{}]
        if services[0].get('name') != svc or services[0].get('port') != 443:
            bad(f't4: IngressRoute {name} service is {services[0].get("name")}:{services[0].get("port")}, expected {svc}:443')
        ok(f't4: IngressRoute {name}: crowdsec-only, priority 100, {svc}:443')

    for name in ('git-service', 'forgejo-service'):
        d = doc_by('Service', name)
        if d is None:
            bad(f't4: no Service named {name} in the proxy-local render')
        spec = d.get('spec') or {}
        if spec.get('type') != 'ExternalName':
            bad(f't4: Service {name} type is {spec.get("type")!r}, expected ExternalName')
        if spec.get('externalName') != 'infra.spencerslab.com':
            bad(f't4: Service {name} externalName is {spec.get("externalName")!r}, expected infra.spencerslab.com (the infra cluster apex, mesh DNS)')
        ok(f't4: Service {name} is an ExternalName to infra.spencerslab.com')

    raw = open(render).read()
    if 'OVERRIDE_VIA_CUSTOM_VALUES' in raw or 'OVERRIDE_VIA_APPSET' in raw:
        bad('t4: the rendered proxy-local manifests still carry an OVERRIDE_VIA_* sentinel')
    ok('t4: no OVERRIDE_VIA_* sentinel survives in the rendered proxy-local manifests')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't4: the proxy-local render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/proxy-count")))
    else
      exit 1
    fi

    # --- t5: dev parity after the chart defaults went neutral (criterion 4)
    # The forgejo: block of custom-values/dev mirrors the wrapper chart's
    # values shape (bitwardenIds + forgejo.*), so its CONTENTS are the -f
    # file; --set overrides the real UUIDs so none land in the render. This
    # check passes pre-implementation too: it guards the A8 MIGRATION (chart
    # literals -> custom-values), not an addition.
    dev_block="$WORK/dev-forgejo-block.yaml"
    if ! python3 - "$DEV_CV" "$dev_block" <<'PY'
import sys, yaml

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    d = yaml.safe_load(f)
block = (d or {}).get('forgejo')
if not isinstance(block, dict):
    print(f'FAIL: t5: {src} has no top-level forgejo: block to extract', file=sys.stderr)
    sys.exit(1)
with open(dst, 'w') as f:
    yaml.safe_dump(block, f)
PY
    then
      exit 1
    fi
    parity_out="$WORK/parity-render.yaml"
    parity_err="$WORK/parity-render.err"
    if ! "$helm_bin" template "$fj_copy" -f "$dev_block" \
      --set bitwardenIds.forgejo=u --set bitwardenIds.forgejo-admin=u \
      --set bitwardenIds.forgejo-pg=u --set bitwardenIds.forgejo-sso=u \
      --set domain=scifi.farm \
      >"$parity_out" 2>"$parity_err"; then
      tail -n 30 "$parity_err" >&2
      fail "t5: helm template of $FORGEJO_CHART with dev's custom-values forgejo: block failed (log kept at $parity_err)"
    fi
    [ -s "$parity_out" ] || fail "t5: the dev-parity render produced nothing"
    # Line-anchored so SSH_DOMAIN=git.scifi.farm cannot satisfy the DOMAIN
    # check and a comment cannot satisfy APP_NAME.
    if ! python3 - "$parity_out" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
want = (
    (r'(?m)^\s*APP_NAME=SpencersLab Dev\s*$', 'APP_NAME: SpencersLab Dev'),
    (r'(?m)^\s*DOMAIN=git\.scifi\.farm\s*$', 'DOMAIN: git.scifi.farm'),
    (r'(?m)^\s*ROOT_URL=https://git\.scifi\.farm/\s*$', 'ROOT_URL: https://git.scifi.farm/'),
    (r'forgejo@scifi\.farm', 'admin email: forgejo@scifi.farm'),
)
for rx, label in want:
    if not re.search(rx, text):
        print(f'FAIL: t5: the dev-parity render lost the identity key {label} (the neutralized chart default was not migrated into custom-values/dev)', file=sys.stderr)
        sys.exit(1)
PY
    then
      exit 1
    fi
    ok "t5: dev parity — the chart rendered with dev's custom-values forgejo: block still yields APP_NAME SpencersLab Dev, admin email forgejo@scifi.farm, DOMAIN git.scifi.farm, ROOT_URL https://git.scifi.farm/"
  fi
fi

# --- t6: sentinel sweep, trio greps, deletions (criteria 5-7) -------------
# Static: no helm needed. Every OVERRIDE_VIA_CUSTOM_VALUES in the three
# touched values files must be matched 1:1 by the category's custom-values
# (real UUID or the documented OVERRIDE_NEEDED placeholder). charts/forgejo
# is consumed by BOTH dev and infra, so its sentinels must match in both.
if python3 - "$FORGEJO_CHART/values.yaml" "$INFRA/values.yaml" "$PROXY/values.yaml" \
    "$INFRA_CV" "$DEV_CV" "$PROXY_CV" "$WORK/t6-count" <<'PY'
import os, subprocess, sys, yaml

chart_vals, infra_vals, proxy_vals, infra_cv, dev_cv, proxy_cv = sys.argv[1:7]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

SENTINEL = 'OVERRIDE_VIA_CUSTOM_VALUES'

def load(path):
    # REDEFINED anchors are legal YAML (helm/Go accept them; PyYAML raises
    # ComposerError) — services/proxy-local/prod redefines &port for its
    # three apps. Only markers in `key: &anchor` / `key: *alias` value
    # position are rewritten; & inside quoted URLs and in comments is
    # untouched. Alias targets are values this test never asserts, so the
    # ANCHOR_REF placeholders are inert.
    import re as _re
    lines = []
    with open(path) as f:
        for line in f:
            line = _re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = _re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

def sentinel_paths(values):
    """Every (dotpath, value) under any bitwardenIds mapping, plus top-level
    scalars that are themselves the sentinel (e.g. authRealm)."""
    out = []
    def walk(node, path):
        if not isinstance(node, dict):
            return
        for k, v in node.items():
            p = f'{path}.{k}' if path else str(k)
            if k == 'bitwardenIds' and isinstance(v, dict):
                for kk, vv in v.items():
                    out.append((f'{p}.{kk}', vv))
            elif path == '' and v == SENTINEL:
                out.append((str(k), v))
            walk(v, p)
    walk(values, '')
    return out

def bw_key_occurrences(node, key, path=''):
    """(dotted path, value) of every occurrence of `key` under a bitwardenIds
    mapping anywhere in the tree. custom-values files nest per-app
    (traefik.bitwardenIds.traefik-mqtt), so the match is by KEY, not by the
    service values' exact path."""
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            p = f'{path}.{k}' if path else str(k)
            if k == 'bitwardenIds' and isinstance(v, dict) and key in v:
                out.append((f'{p}.{key}', v[key]))
            out.extend(bw_key_occurrences(v, key, p))
    return out

def check_sentinels(label, values, custom, custom_path, prefix=''):
    missing, still_sentinel = [], []
    for p, v in sentinel_paths(values):
        if v != SENTINEL:
            continue
        leaf = p.split('.')[-1]
        if '.' not in p and not prefix:
            # top-level scalar sentinel (authRealm): matched at custom top level
            occ = [('<top-level>', custom.get(leaf))] if leaf in custom else []
        else:
            occ = bw_key_occurrences(custom, leaf)
        good = [o for o in occ if o[1] != SENTINEL]
        if not good:
            if occ:
                still_sentinel.append(f'{prefix}{p} (key {leaf} exists at {occ[0][0]} but is still a sentinel)')
            else:
                missing.append(f'{prefix}{p} (no {leaf} key under any bitwardenIds in {custom_path})')
    if missing or still_sentinel:
        bad(f't6: {label}: ' + '; '.join(missing + still_sentinel))
    else:
        n = sum(1 for _, v in sentinel_paths(values) if v == SENTINEL)
        ok(f't6: {label}: all {n} OVERRIDE_VIA_CUSTOM_VALUES sentinels have a matching key in {custom_path}')

chart = load(chart_vals)
check_sentinels('charts/forgejo/values.yaml (consumed by dev)', chart, load(dev_cv), dev_cv, prefix='forgejo.')
check_sentinels('charts/forgejo/values.yaml (consumed by infra)', chart, load(infra_cv), infra_cv, prefix='forgejo.')
check_sentinels('services/infra/prod/values.yaml', load(infra_vals), load(infra_cv), infra_cv)
check_sentinels('services/proxy-local/prod/values.yaml', load(proxy_vals), load(proxy_cv), proxy_cv)

# --- trio (criterion 6) ----------------------------------------------------
iv = load(infra_vals)
if not isinstance((iv.get('charts') or {}).get('forgejo'), dict):
    bad('t6: services/infra/prod/values.yaml has no charts.forgejo entry (trio: chart leg missing)')
subs = (iv.get('ingress') or {}).get('subdomains') or {}
for host in ('git', 'forgejo'):
    if not isinstance(subs.get(host), dict):
        bad(f't6: services/infra/prod/values.yaml has no ingress.subdomains.{host} entry (trio: ingress leg missing)')
ok('t6: infra trio — charts.forgejo + ingress.subdomains.git + .forgejo present')

pv = load(proxy_vals)
psubs = (pv.get('proxy') or {}).get('subdomains') or {}
for host in ('git', 'forgejo'):
    e = psubs.get(host)
    if not isinstance(e, dict):
        bad(f't6: services/proxy-local/prod/values.yaml has no proxy.subdomains.{host} entry (trio: proxy leg missing)')
    if e.get('target') != 'infra':
        bad(f't6: proxy.subdomains.{host}.target is {e.get("target")!r}, expected infra')
ok('t6: proxy-local trio — proxy.subdomains.git + .forgejo both target infra')

icv = load(infra_cv)
fbw = (icv.get('forgejo') or {}).get('bitwardenIds')
if not isinstance(fbw, dict):
    bad('t6: custom-values/infra/prod-values.yaml has no forgejo.bitwardenIds block')
else:
    want = {'forgejo', 'forgejo-admin', 'forgejo-pg', 'forgejo-sso'}
    if set(fbw) != want:
        bad(f't6: custom-values/infra forgejo.bitwardenIds keys are {sorted(fbw)}, expected exactly {sorted(want)}')
    for k, v in fbw.items():
        if v == SENTINEL:
            bad(f't6: custom-values/infra forgejo.bitwardenIds.{k} is still the service sentinel {SENTINEL} (must be a real UUID or the OVERRIDE_NEEDED placeholder)')
    ok('t6: custom-values/infra forgejo.bitwardenIds has exactly the 4 expected keys')

# --- deletions (criterion 7) -----------------------------------------------
# The leftovers are the bitwardenIds.gitea/-admin KEYS, the two
# secret-gitea* templates, and gitea-secret/-admin-secret references. The
# string "gitea" is NOT banned in custom-values/infra: the chart's values
# structure is forgejo.forgejo.gitea.config.*, so the infra identity block
# legitimately carries a gitea: subkey there (criterion 3 separately bans the
# string in the RENDERED infra manifests, where it must not survive).
# git grep only, so untracked vendored tarballs (charts/**/charts) and this
# test file itself cannot false-positive; the backups service's gitea CHART
# dependency is a separate, untouched concern (criterion 7).
def bw_has(node, key, path=''):
    found = []
    if isinstance(node, dict):
        for k, v in node.items():
            p = f'{path}.{k}' if path else str(k)
            if k == 'bitwardenIds' and isinstance(v, dict) and key in v:
                found.append(f'{p}.{key}')
            found.extend(bw_has(v, key, p))
    return found
for label, doc in (('services/infra/prod/values.yaml', load(infra_vals)),
                   ('custom-values/infra/prod-values.yaml', load(infra_cv))):
    for key in ('gitea', 'gitea-admin'):
        hits = bw_has(doc, key)
        if hits:
            bad(f't6: {label} still has bitwardenIds key(s) {", ".join(hits)} (decision A7 deletes them)')
ok('t6: no bitwardenIds.gitea / bitwardenIds.gitea-admin in the infra values or custom-values')
r = subprocess.run(['git', 'grep', '-ni', '--', 'gitea', 'services/infra/prod'],
                   capture_output=True, text=True)
if r.stdout.strip():
    bad('t6: "gitea" still appears in services/infra/prod/ (leftovers not deleted):\n' + r.stdout.strip())
ok('t6: no gitea string anywhere in services/infra/prod/')
for gone in ('services/infra/prod/templates/secret-gitea.yaml',
             'services/infra/prod/templates/secret-gitea-admin.yaml'):
    if os.path.exists(gone):
        bad(f't6: {gone} still exists (decision A7 deletes it)')
ok('t6: secret-gitea.yaml and secret-gitea-admin.yaml are deleted')
r = subprocess.run(['git', 'grep', '-n', '--', 'gitea-admin',
                    'services/infra/prod', 'custom-values/infra'],
                   capture_output=True, text=True)
if r.stdout.strip():
    bad('t6: "gitea-admin" still appears in services/infra/prod/ or custom-values/infra/ (leftover, not the forgejo-admin rename):\n' + r.stdout.strip())
ok('t6: no gitea-admin string in services/infra/prod/ or custom-values/infra/')
r = subprocess.run(['git', 'grep', '-nE', '--', 'gitea-secret|gitea-admin-secret',
                    'services', 'charts', 'custom-values'],
                   capture_output=True, text=True)
if r.stdout.strip():
    bad('t6: gitea-secret/gitea-admin-secret is still referenced:\n' + r.stdout.strip())
ok('t6: nothing in services/ charts/ custom-values/ references gitea-secret or gitea-admin-secret')

with open(sys.argv[7], 'w') as f:
    f.write(str(ok_n))
sys.exit(0)
PY
then
  checks=$((checks + $(cat "$WORK/t6-count")))
else
  exit 1
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: infra-forgejo checks (%d ok)\n' "$checks"
