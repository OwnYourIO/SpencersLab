#!/usr/bin/env bash
# hivetools kubernetes-mcp-server TOML-config contract (2026/2026-10-bug-kubernetes-mcp-toml, C01):
#   t1..t7 pin the chart migration off the runtime-CLI surface that upstream
#   v0.0.68 (PR #1423) deleted — the dead `--port/--stateless/--read-only` args
#   crash-looped both kubernetes tiers on 10 clusters after the v0.0.69 bump
#   (SEV-HIGH, 2026-10-25). A contract that only checks "helm renders" would
#   have stayed green through that incident; these bind args, ConfigMap bytes,
#   the mount/arg cross-check, the image pin, render hygiene, and a repo-wide
#   sweep so the NEXT flag-based breakage is caught by test, not by outage.
#
# Contract source: chunks/C01.md "Interface contract" + "## Tests". AC trace:
# t1[AC1] t2[AC2] t3[AC3] t4[AC4] t5[AC5] t6[AC6] t7[AC7].
# Sibling-style model for t7's uniqueness/universality guard: dev-mcp-fleet.sh
# t7's spec.secrets list-map check — generic over every rendered entry.
#
# Usage (default all; unknown ids fail):
#   bash tests/services/hivetools-kubernetes-mcp-toml.sh
#   bash tests/services/hivetools-kubernetes-mcp-toml.sh t2 t3
# Cross-chunk regression, run SEQUENTIALLY after C01 lands (never in parallel:
# two suites execing the same scripts, and never edit dev-mcp-fleet.sh — it is
# the sibling ticket's immutable contract):
#   bash tests/services/dev-mcp-fleet.sh t6 t7 t8 t11
#
# Style provenance: tests/services/dev-mcp-fleet.sh — helm resolved
# HELM_BIN -> PATH -> ~/.local/bin -> /tmp/opencode find -> download v3.21.4
# (helm is NOT on PATH here; FRICTION 2026-10-24), renders from a /tmp/opencode
# COPY after `helm dependency update` (charts/**/charts is gitignored; the
# worktree is never written), registry-unreachable => skip-with-warning,
# everything else offline and deterministic. `--set` cannot carry values
# containing `/`, so the probe entry in t6 goes through a `-f` values file.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

HIVETOOLS_CHART="charts/hivetools"
TEST_UUID="test-uuid"

# Contract constants (chunks/C01.md interface table — tests bind to these, not
# to dev's wording). TOML bytes are contractual: `port` is a quoted STRING
# (v0.0.69 schema: string, default "", non-empty enables HTTP mode); unknown
# keys fail startup, so nothing beyond the per-tier lines may appear.
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

# --- test selection ----------------------------------------------------------
declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 7); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-7]$ ]] ||
      fail "unknown test id '$a' (expected t1..t7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- helm discovery (dev-mcp-fleet.sh recipe) --------------------------------
find_helm() {
  # Each branch prints exactly one path AND returns 0 — a missing return
  # concatenates a second path into the result (dev-forgejo-runner F01).
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
  dir=/tmp/opencode/hivetools-kubernetes-mcp-toml-helm-download
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

WORK=$(mktemp -d /tmp/opencode/hivetools-kubernetes-mcp-toml.XXXXXX)

# --- shared /tmp chart copy + dependency update (t1..t6) ----------------------
# Same gate shape as dev-mcp-fleet.sh: missing helm or an unreachable OCI
# registry for the vendored toolhive deps skips the render-based ids; any
# other dependency-update failure is a hard fail (a broken chart is not a
# network condition).
hive_copy=""
skip_hive=0
if want t1 || want t2 || want t3 || want t4 || want t5 || want t6; then
  [ -d "$HIVETOOLS_CHART" ] ||
    fail "t1: $HIVETOOLS_CHART does not exist (nothing to dependency-update, lint, or render)"
  if [ -z "$helm_bin" ]; then
    skip "t1: no helm binary on PATH, in ~/.local/bin, or downloadable; t1-t6 were not run"
    skip_hive=1
  else
    hive_copy="$WORK/hivetools-copy"
    cp -R "$HIVETOOLS_CHART"/. "$hive_copy"/
    hive_dep_log="$hive_copy/dependency-update.log"
    if ! (cd "$hive_copy" && "$helm_bin" dependency update .) >"$hive_dep_log" 2>&1; then
      if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$hive_dep_log"; then
        skip "t1: helm dependency update could not reach the OCI registry for $HIVETOOLS_CHART here; t1-t6 were not run (log kept at $hive_dep_log)"
        skip_hive=1
        hive_copy=""
      else
        tail -n 30 "$hive_dep_log" >&2
        fail "t1: helm dependency update failed for $HIVETOOLS_CHART (log kept at $hive_dep_log)"
      fi
    fi
  fi
fi

# --- shared chart-default render (t2..t6) --------------------------------------
# The plan Commands' five --sets; standalone chart defaults, no service slice —
# AC2..AC6 are stated on the chart as every cluster's appset layer deep-merges
# over it (renders identically on every cluster, plan constraint 4).
hive_render=""
if { want t2 || want t3 || want t4 || want t5 || want t6; } && [ "$skip_hive" -eq 0 ]; then
  hive_render="$WORK/hivetools-render.yaml"
  hive_err="$WORK/hivetools-render.err"
  if ! "$helm_bin" template hivetools "$hive_copy" \
      --set "domain=test.example.com" --set "clusterName=dev" --set "subDomain=dev" \
      --set "bitwardenIds.mcp-sso=$TEST_UUID" --set "keycloak.realm=test" \
      >"$hive_render" 2>"$hive_err"; then
    tail -n 30 "$hive_err" >&2
    fail "t2: helm template of the $HIVETOOLS_CHART copy failed (log kept at $hive_err)"
  fi
  [ -s "$hive_render" ] || fail "t2: the chart-default render produced no output"
fi

# =========================================================================
# t1 [AC1] — helm lint on the /tmp copy
# =========================================================================
if want t1 && [ "$skip_hive" -eq 0 ]; then
  hive_lint_log="$WORK/lint-hivetools.log"
  if (cd "$hive_copy" && "$helm_bin" lint .) >"$hive_lint_log" 2>&1; then
    ok "t1: helm lint passes for $HIVETOOLS_CHART (C01 AC1)"
  else
    tail -n 30 "$hive_lint_log" >&2
    fail "t1: helm lint failed for $HIVETOOLS_CHART (log kept at $hive_lint_log)"
  fi
fi

# =========================================================================
# t2 [AC2] — both MCPServers carry exactly the --config pair, no deleted flag
# =========================================================================
if want t2 && [ -n "$hive_render" ]; then
  if python3 - "$hive_render" "$WORK/t2-count" <<'PY'
import sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# Flag names upstream v0.0.68 deleted (PR #1423); substring containment also
# catches the `--flag=value` spelling. This is exactly what crash-looped the
# fleet — the baseline render must fail here.
DEAD_FLAGS = ('--port', '--stateless', '--read-only')
WANT_ARGS = ['--config', '/etc/kubernetes-mcp-server/config.toml']

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    servers = {(d.get('metadata') or {}).get('name'): (d.get('spec') or {})
               for d in docs if d.get('kind') == 'MCPServer'}

    for tier in ('kubernetes-readonly', 'kubernetes-admin'):
        name = f'mcp-{tier}'
        if name not in servers:
            bad(f't2: no MCPServer {name} in the chart-default render (present: {sorted(servers)})')
        args = servers[name].get('args') or []
        hits = [a for a in args if isinstance(a, str) and any(f in a for f in DEAD_FLAGS)]
        if hits:
            bad(f't2: {name} still passes flags the pinned v0.0.69 binary does not understand: {hits} (full args {args!r}) — the 2026-10-25 crashloop, exactly; runtime settings belong in the mounted config.toml')
        if args != WANT_ARGS:
            bad(f't2: {name} spec.args is {args!r}, expected exactly {WANT_ARGS!r}')
        ok(f't2: MCPServer {name} args are exactly the --config pair, no deleted flag (C01 AC2)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't2: the chart-default render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t2-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# t3 [AC3] — the two ConfigMaps exist with the EXACT per-tier TOML bytes
# =========================================================================
if want t3 && [ -n "$hive_render" ]; then
  if python3 - "$hive_render" "$WORK/t3-count" <<'PY'
import sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# Byte-exact per the chunks/C01.md contract table. Comparing the YAML-parsed
# value pins the bytes while staying robust to the template's nindent: a block
# scalar's indentation is stripped at parse time, so only the content itself
# can differ. The readonly tier MUST carry read_only (the v0.0.69 image-baked
# default boots stateful with write tools visible — a zero-explicit-config
# readonly tier is the tier split silently dissolving); the admin MUST NOT.
EXPECT = {
    'mcp-kubernetes-readonly-config':
        'port = "8080"\nstateless = true\nread_only = true\n',
    'mcp-kubernetes-admin-config':
        'port = "8080"\nstateless = true\n',
}

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    cms = {(d.get('metadata') or {}).get('name'): d
           for d in docs if d.get('kind') == 'ConfigMap'}

    for name, toml in EXPECT.items():
        cm = cms.get(name)
        if cm is None:
            bad(f't3: no ConfigMap {name} rendered (ConfigMaps present: {sorted(cms)}) — the tiers are configured through the mounted config.toml only')
        if ((cm.get('metadata') or {}).get('namespace')) != 'default':
            bad(f't3: {name} namespace is {((cm.get("metadata") or {}).get("namespace"))!r}, expected default (.Values.namespace | default "default")')
        data = cm.get('data') or {}
        if set(data) != {'config.toml'}:
            bad(f't3: {name} data keys are {sorted(data)}, expected exactly [config.toml]')
        got = data['config.toml']
        if got != toml:
            bad(f't3: {name} config.toml is {got!r}, expected exactly {toml!r} — port must be the quoted STRING "8080" (v0.0.69 schema; the int form is wrong) and no unknown key may appear (unknown keys fail startup hard)')
        ok(f't3: ConfigMap {name} data["config.toml"] byte-exact, single key, namespace default (C01 AC3)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the chart-default render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t3-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# t4 [AC4] — mount/arg cross-check: the arg path resolves through the mount
# =========================================================================
# The slow-motion reproduction of this incident is a contract drift where the
# arg names one path and the volume projects another: the pod boots, reads the
# image-baked default (or nothing), and every tier guarantee evaporates with
# no CrashLoopBackOff to notice. t4 therefore derives everything from args[1]
# instead of repeating literals: mountPath must equal dirname(args[1]), the CM
# key must equal basename(args[1]), and the CM the volume names must be the
# rendered tier ConfigMap.
if want t4 && [ -n "$hive_render" ]; then
  if python3 - "$hive_render" "$WORK/t4-count" <<'PY'
import os, sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

TIERS = {
    'kubernetes-readonly': 'mcp-kubernetes-readonly-config',
    'kubernetes-admin': 'mcp-kubernetes-admin-config',
}

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    servers = {(d.get('metadata') or {}).get('name'): (d.get('spec') or {})
               for d in docs if d.get('kind') == 'MCPServer'}
    cms = {(d.get('metadata') or {}).get('name'): d
           for d in docs if d.get('kind') == 'ConfigMap'}

    for tier, cm_name in TIERS.items():
        spec = servers.get(f'mcp-{tier}')
        if spec is None:
            bad(f't4: no MCPServer mcp-{tier} in the render (present: {sorted(servers)})')
        args = spec.get('args') or []
        if len(args) != 2 or args[0] != '--config':
            bad(f't4: mcp-{tier} args are {args!r}, not the [--config, <path>] pair — the mount/arg cross-check is meaningless against the dead-flag form (t2 pins it; this fails for the same incident)')
        cfg_path = args[1]
        cfg_dir, cfg_key = os.path.dirname(cfg_path), os.path.basename(cfg_path)

        if cm_name not in cms:
            bad(f't4: volume target ConfigMap {cm_name} did not render (ConfigMaps present: {sorted(cms)})')
        if cfg_key not in ((cms[cm_name].get('data') or {})):
            bad(f't4: {cm_name} has no key {cfg_key!r} — the key is projected at <mountPath>/<key>, so the arg would point at a missing file')

        # MCPServer CRD spec.volumes is HostPath-only (toolhive v0.56
        # mcpserver_types.go) — a configMap volume placed there is rejected by
        # the API and the server never comes up at all.
        for v in spec.get('volumes') or []:
            if (v or {}).get('configMap'):
                bad(f't4: mcp-{tier} spec.volumes contains a configMap volume {v!r} — CRD spec.volumes is hostPath-only; config volumes must live inside podTemplateSpec.spec.volumes')

        pts = (spec.get('podTemplateSpec') or {}).get('spec') or {}
        volumes = {(v or {}).get('name'): v for v in pts.get('volumes') or []}
        containers = pts.get('containers') or []
        mcp_c = next((c for c in containers if (c or {}).get('name') == 'mcp'), None)
        if mcp_c is None:
            bad(f't4: mcp-{tier} podTemplateSpec has no container named mcp (containers: {[(c or {}).get("name") for c in containers]})')
        mounts = mcp_c.get('volumeMounts') or []
        cm_mounts = [m for m in mounts
                     if ((volumes.get((m or {}).get('name')) or {}).get('configMap') or {}).get('name') == cm_name]
        if not cm_mounts:
            bad(f't4: no volumeMount on container mcp projects {cm_name}: mounts={mounts!r} volumes={sorted(volumes)} — the --config path would resolve to the image-baked default, not the chart-owned config')
        m = cm_mounts[0]
        if m.get('mountPath') != cfg_dir:
            bad(f't4: {cm_name} is mounted at {m.get("mountPath")!r}, expected the dirname of the --config arg ({cfg_dir!r})')
        # Directory mount, not subPath: a subPath projection is materialized at
        # container start and never refreshes on ConfigMap edits.
        if m.get('subPath'):
            bad(f't4: the config volumeMount uses subPath={m.get("subPath")!r} — subPath projections never refresh on CM edits; the contract is a directory mount of the projected volume')
        ok(f't4: mcp-{tier}: {cfg_path} resolves via a subPath-less directory mount of {cm_name} (key {cfg_key}) (C01 AC4)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't4: the chart-default render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t4-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# t5 [AC5] — image pin equality (the fix must not touch tags)
# =========================================================================
if want t5 && [ -n "$hive_render" ]; then
  if python3 - "$hive_render" "$WORK/t5-count" <<'PY'
import sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# Binding user decision D2: fix forward on v0.0.69, no rollback, no tag change
# anywhere. Green at baseline BY DESIGN — it is a non-regression guard: the
# migration must earn its keep without moving the pin.
PIN = 'ghcr.io/containers/kubernetes-mcp-server:v0.0.69'

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    servers = {(d.get('metadata') or {}).get('name'): (d.get('spec') or {})
               for d in docs if d.get('kind') == 'MCPServer'}
    for tier in ('kubernetes-readonly', 'kubernetes-admin'):
        spec = servers.get(f'mcp-{tier}')
        if spec is None:
            bad(f't5: no MCPServer mcp-{tier} in the render')
        if spec.get('image') != PIN:
            bad(f't5: mcp-{tier} image is {spec.get("image")!r}, expected exactly {PIN!r} (D2: tags are off-limits in this ticket; release automation owns bumps)')
        ok(f't5: mcp-{tier} image pin unchanged ({PIN}) (C01 AC5)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't5: the chart-default render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t5-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# t6 [AC6] — render hygiene: exactly the two new ConfigMaps, nothing else;
#            a configFile-less mcp entry renders no ConfigMap
# =========================================================================
# The second clause is proven by injecting a synthetic entry WITHOUT
# configFile (probe, via -f values file — --set cannot carry a slash-containing
# image value) and asserting the probe gains an MCPServer but no ConfigMap:
# the gate shape copied from generic-mcpserver.yaml must not fire for entries
# the old way. The MCPServer-presence assertion keeps the probe from passing
# vacuously if the injected entry never rendered at all.
if want t6 && [ -n "$hive_render" ]; then
  probe_values="$WORK/probe-noconfig-values.yaml"
  cat > "$probe_values" <<'YAML'
mcp:
  toml-gate-probe:
    enabled: true
    image: ghcr.io/stacklok/probe-sidecar:1
    transport: stdio
YAML
  probe_render="$WORK/hivetools-probe-render.yaml"
  probe_err="$WORK/hivetools-probe-render.err"
  if ! "$helm_bin" template hivetools "$hive_copy" \
      -f "$probe_values" \
      --set "domain=test.example.com" --set "clusterName=dev" --set "subDomain=dev" \
      --set "bitwardenIds.mcp-sso=$TEST_UUID" --set "keycloak.realm=test" \
      >"$probe_render" 2>"$probe_err"; then
    tail -n 30 "$probe_err" >&2
    fail "t6: helm template with the configFile-less probe entry failed (log kept at $probe_err)"
  fi
  if python3 - "$hive_render" "$probe_render" "$WORK/t6-count" <<'PY'
import sys, yaml

render, probe, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

WANT_CMS = {'mcp-kubernetes-readonly-config', 'mcp-kubernetes-admin-config'}
WANT_SERVERS = {'mcp-kubernetes-readonly', 'mcp-kubernetes-admin'}

def kinds(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]

try:
    docs = kinds(render)
    got_cms = {(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'ConfigMap'}
    if got_cms != WANT_CMS:
        bad(f't6: chart-default render ConfigMap set is {sorted(got_cms)}, expected exactly {sorted(WANT_CMS)} — the two tier configs and nothing else (baseline renders zero, which is the missing-fix state)')
    ok('t6: chart-default render contains exactly the two tier ConfigMaps (C01 AC6)')

    got_servers = {(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'MCPServer'}
    if got_servers != WANT_SERVERS:
        bad(f't6: chart-default render MCPServer set is {sorted(got_servers)}, expected exactly {sorted(WANT_SERVERS)}')
    ok('t6: chart-default render contains exactly the two kubernetes MCPServers (C01 AC6)')

    postgres = [n for n in got_servers if n.startswith('mcp-postgres-')]
    if postgres:
        bad(f't6: postgresMcp servers appeared in a chart-default render with databases []: {postgres} — other default docs must be untouched')
    ingresses = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'Ingress']
    if ingresses != ['mcp-multi-server-ingress']:
        bad(f't6: Ingress set is {ingresses}, expected exactly [mcp-multi-server-ingress] — the migration touches no ingress/proxy shape')
    ok('t6: postgresMcp default (empty) and the ingress doc are undisturbed by the new template (C01 AC6)')

    # Probe render: the gate — entries without configFile gain no ConfigMap.
    pdocs = kinds(probe)
    pservers = {(d.get('metadata') or {}).get('name') for d in pdocs if d.get('kind') == 'MCPServer'}
    if 'mcp-toml-gate-probe' not in pservers:
        bad(f't6: probe MCPServer mcp-toml-gate-probe did not render (present: {sorted(pservers)}) — the gate was never exercised')
    pcms = {(d.get('metadata') or {}).get('name') for d in pdocs if d.get('kind') == 'ConfigMap'}
    if pcms != WANT_CMS:
        bad(f't6: with the configFile-less probe entry the ConfigMap set is {sorted(pcms)}, expected exactly {sorted(WANT_CMS)} — generic-mcpconfigmap.yaml must render NOTHING for entries without configFile')
    ok('t6: a configFile-less mcp entry renders its MCPServer but no ConfigMap (gate shape, C01 AC6)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't6: the chart-default/probe renders could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t6-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# t7 [AC7] — repo-wide sweep: no mcp entry anywhere passes flags the pinned
#            binary rejects (static; no helm, no network)
# =========================================================================
# The standing hazard (DECISIONS D8): internal charts ship from main with no
# version pin, so an image bump re-renders EVERY cluster on merge — and any
# future mcp: entry (chart default, service slice, or custom-values) that
# reuses the dead flag shape reopens the incident cluster-wide. Modeled on
# dev-mcp-fleet.sh t7's secrets-name guard: one generic contract over all
# entries, not one assertion per today-known server.
if want t7; then
  sweep_files=(charts/hivetools/values.yaml)
  for f in services/*/prod/values.yaml; do
    [ -f "$f" ] && sweep_files+=("$f")
  done
  while IFS= read -r f; do
    sweep_files+=("$f")
  done < <(find custom-values -type f -name '*.yaml' | sort)

  if python3 - "$WORK/t7-count" "${sweep_files[@]}" <<'PY'
import re, sys, yaml

count_file, *paths = sys.argv[1:]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load(path):
    # REDEFINED anchors are legal YAML (helm/Go accept them; PyYAML raises).
    # Same lenient rewrite as dev-mcp-fleet.sh's loaders.
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

IMG = 'ghcr.io/containers/kubernetes-mcp-server'
EXPECT_ARGS = ['--config', '/etc/kubernetes-mcp-server/config.toml']
EXPECT_IMAGE = IMG + ':v0.0.69'
DEAD_RE = re.compile(r'--(?:port|stateless|read-only)\b')

try:
    entries = []

    def walk(node, path, fname):
        if isinstance(node, dict):
            mcp = node.get('mcp')
            if isinstance(mcp, dict):
                for name, entry in mcp.items():
                    if isinstance(entry, dict) and isinstance(entry.get('image'), str) \
                            and entry['image'].startswith(IMG + ':'):
                        entries.append((fname, path + f'/mcp.{name}', entry))
            for k, v in node.items():
                walk(v, path + '/' + str(k), fname)
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f'{path}[{i}]', fname)

    for p in paths:
        try:
            walk(load(p), '', p)
        except Exception as ex:
            bad(f't7: {p} could not be parsed even with the lenient loader — the sweep would be vacuous, which is exactly how a flag-based breakage hides ({type(ex).__name__}: {ex})')

    where = {(p, w) for (p, w, _) in entries}
    for tier in ('kubernetes-readonly', 'kubernetes-admin'):
        if ('charts/hivetools/values.yaml', f'/mcp.{tier}') not in where:
            bad(f't7: the chart default mcp.{tier} entry is no longer findable as a kubernetes-mcp-server image entry — the sweep guard would go silently vacuous (C01 must keep both entries under mcp:)')
    ok(f't7: sweep is non-vacuous — both chart-default tier entries found ({len(entries)} kubernetes-mcp-server mcp entries repo-wide)')

    for p, w, e in entries:
        if e.get('image') != EXPECT_IMAGE:
            bad(f't7: {p} {w} image is {e.get("image")!r}, expected exactly {EXPECT_IMAGE!r} (no tag drift; the sweep entry point)')
        if e.get('args') != EXPECT_ARGS:
            bad(f't7: {p} {w} args are {e.get("args")!r}, expected exactly {EXPECT_ARGS!r} — every entry on this image must use the --config pair; the deleted flags crash-loop the pod (2026-10-25, PR #704)')
    ok(f't7: all {len(entries)} swept kubernetes-mcp-server mcp entries carry the --config pair at the pinned tag (C01 AC7)')

    # Belt for shapes the loader above cannot see (templated strings, future
    # file layouts): the dead flag strings may not co-occur with this image
    # within 20 lines in any swept file.
    for p in paths:
        lines = open(p, errors='replace').read().splitlines()
        for i, line in enumerate(lines):
            if IMG not in line:
                continue
            lo, hi = max(0, i - 20), min(len(lines), i + 21)
            for j in range(lo, hi):
                m = DEAD_RE.search(lines[j])
                if m:
                    bad(f't7: {p}:{j + 1} mentions {m.group(0)} within 20 lines of the {IMG} name — a dead flag in the same block as this image is the incident shape; comments must not describe removed flags as live either')
    ok('t7: no --port/--stateless/--read-only string co-occurs with the kubernetes-mcp-server image in any swept file (C01 AC7)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't7: the repo-wide sweep could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t7-count")))
  else
    exit 1
  fi
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: hivetools-kubernetes-mcp-toml checks (%d ok)\n' "$checks"
