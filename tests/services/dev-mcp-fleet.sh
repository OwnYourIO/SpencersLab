#!/usr/bin/env bash
# dev MCP fleet contract (2026/2026-10-feat-dev-mcp-fleet):
#   C01 t1-t5   searxng backend on dev (chart entry, custom-values slice, LAN ingress)
#   C03 t6-t11  dev hivetools mcp entries (playwright/renovate/searxng/boards),
#               umbrella github-mcp/wekan-mcp ExternalSecret templates, sentinel
#               parity, inherited kubernetes gates survive the mcp map merge
#   C04 t12-t14 client dev-* server entries, rulesync dev* allow rules,
#               regenerated AGENTS.md row + regenerated agent files
#
# Contract source: chunks/C01.md|C03.md|C04.md "## Tests". AC trace:
# t1[C01 AC3+AC5] t2[C01 AC1] t3[C01 AC2] t4[C01 AC4] t5[C01 AC5]
# t6[C03 AC1] t7[C03 AC2+AC5 — boards multi-key Secret consumption re-ruled
#   2026-10-25 to podTemplateSpec envFrom; spec.secrets is a CRD list-map
#   keyed by name and cannot repeat a Secret] t8[C03 AC2] t9[C03 AC3 —
#   github-mcp store re-ruled 2026-10-24 to bitwarden-login/password]
# t10[C03 AC4] t11[C03 AC5]
# t12[C04 AC1] t13[C04 AC2] t14[C04 AC3+AC4]
#
# One shared script for three chunks is the user-approved layout (chunk files).
# Amendment (ticket 2026-10-feat-board-coord-intake, D17/D24): t7's mcp-boards
# image equality accepts wekan-mcp:(main|v[0-9]+) so that ticket's M2 pin-bump
# lands without touching this file; every other fleet image stays strict.
# Each chunk's review can run the whole file or only its own ids:
#   bash tests/services/dev-mcp-fleet.sh              # t1..t14
#   bash tests/services/dev-mcp-fleet.sh t1 t2 t3 t4 t5
#
# Style provenance: tests/services/dev-forgejo-runner.sh — charts are rendered
# from a COPY under /tmp/opencode after `helm dependency update` (charts/**/
# charts is gitignored, Chart.lock committed; the worktree is never written),
# and helm is resolved HELM_BIN -> PATH -> /home/coder/.local/bin ->
# /tmp/opencode find -> download v3.21.4 (FRICTION 2026-10-24: helm is NOT on
# PATH in this environment). Registry-unreachable is skip-with-warning only
# where a vendored dep genuinely needs it (t2/t3 app-template repo, t6-t8/
# t11 OCI toolhive deps); everything else (t1, t4, t5, t9, t10, t12, t13)
# renders or parses offline. t14 uses `npx --no-install` so rulesync never
# reaches the network by this script's fault.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DEVUMB="services/dev/prod"
DEV_VALUES="services/dev/prod/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
SEARXNG_CHART="charts/searxng"
HIVETOOLS_CHART="charts/hivetools"
OC_CFG=".opencode/opencode.jsonc"
AGENT_SOURCES=(
  .rulesync/subagents/agent-plan.md
  .rulesync/subagents/agent-research.md
  .rulesync/subagents/agent-test.md
  .rulesync/subagents/agent-dev.md
  .rulesync/subagents/agent-review.md
  .rulesync/subagents/agent-fuser.md
)
# Surfaces rulesync owns (AGENTS.md Hard rule: never hand-edit). t14 proves
# the committed generated output equals fresh generator output by asserting a
# real `rulesync generate` leaves none of these dirty.
GENERATED_SURFACES=(AGENTS.md .opencode/agents .opencode/commands .opencode/skills)

# Distinguishable test UUIDs so t9 can tie each rendered remoteRef.key to the
# --set that resolved it (same rationale as dev-forgejo-runner's per-release
# UUIDs). Non-MCP sentinels take one shared value; nothing asserts on it —
# except forgejo-token-canonical (added 2026-10-25 for the
# 2026-10-feat-forgejo-auth-support C03 sentinel on this umbrella): t9 ties
# its remoteRef.key, so it gets its own value like the MCP pair.
TEST_UUID="test-uuid"
TEST_UUID_GITHUB="test-uuid-github-mcp"
TEST_UUID_WEKAN="test-uuid-wekan-mcp"
TEST_UUID_CANONICAL="test-uuid-forgejo-token-canonical"

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
# Default all; explicit ids let C01's review run t1-t5 without the not-yet-
# implemented C03/C04 contracts counting against it.
declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 14); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[0-4])$ ]] ||
      fail "unknown test id '$a' (expected t1..t14)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- helm discovery (dev-forgejo-runner.sh recipe) ----------------------------
find_helm() {
  # Each branch prints exactly one path AND returns 0 — a missing return
  # concatenates a second path into the result (the trap documented in that
  # script's header, F01 review finding).
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
  dir=/tmp/opencode/dev-mcp-fleet-helm-download
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

WORK=$(mktemp -d /tmp/opencode/dev-mcp-fleet.XXXXXX)

# =========================================================================
# C01 — searxng backend on dev
# =========================================================================

# --- t1: static dev values (C01 AC3 + AC5) -----------------------------------
if want t1; then
  if python3 - "$DEV_VALUES" "$WORK/t1-count" <<'PY'
import re, sys, yaml

dev_vals, count_file = sys.argv[1:3]
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
    # ComposerError). Same lenient rewrite as dev-forgejo-runner.sh's loaders.
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    sv = load(dev_vals)
    entry = (sv.get('charts') or {}).get('searxng')
    if not isinstance(entry, dict):
        bad(f't1: {dev_vals} has no charts.searxng entry (C01 AC3: the internal-chart entry appset-charts.yaml turns into the dev-searxng Application)')
    if entry.get('namespace') != 'default':
        bad(f't1: charts.searxng.namespace is {entry.get("namespace")!r}, expected default')
    if str(entry.get('ServerSideApply')) != 'false':
        bad(f't1: charts.searxng.ServerSideApply is {entry.get("ServerSideApply")!r}, expected "false" (string, per the gpu internal-chart pattern services/gpu/prod/values.yaml:50-52)')
    ok('t1: charts.searxng {namespace: default, ServerSideApply: "false"} present (C01 AC3)')

    sub = ((sv.get('ingress') or {}).get('subdomains') or {}).get('searxng')
    if not isinstance(sub, dict):
        bad(f't1: {dev_vals} has no ingress.subdomains.searxng entry (C01 AC5: the LAN host searxng.scifi.farm, user decision 2026-10-24)')
    if set(sub) != {'service', 'port'}:
        bad(f't1: ingress.subdomains.searxng is {sub!r}; expected exactly keys service+port — clusterBase would move the host under dev.<domain>, serviceName would render a second ingress (gpu sets it; the dev key-derived host already equals searxng.<domain>, C01 AC5)')
    if sub.get('service') != 'dev-searxng' or sub.get('port') != 8080:
        bad(f't1: ingress.subdomains.searxng is {sub!r}, expected service dev-searxng / port 8080 (dev-searxng is the release <serviceName>-<appName> service name, DECISIONS.md)')
    ok('t1: ingress.subdomains.searxng == {service: dev-searxng, port: 8080}, no clusterBase/serviceName (C01 AC5)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't1: the static dev-values check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t1-count")))
  else
    exit 1
  fi
fi

# --- t2+t3: searxng chart lint + standalone render (C01 AC1, AC2) -------------
# Both need the vendored app-template dep: lint/render run from the /tmp copy
# after `helm dependency update`. Registry-unreachable => skip-with-warning.
searxng_copy=""
skip_searxng=0
if want t2 || want t3; then
  [ -d "$SEARXNG_CHART" ] ||
    fail "t2: $SEARXNG_CHART does not exist (nothing to dependency-update, lint, or render)"
  if [ -z "$helm_bin" ]; then
    skip "t2: no helm binary on PATH, in ~/.local/bin, or downloadable; t2-t3 were not run"
    skip_searxng=1
  else
    searxng_copy="$WORK/searxng-copy"
    cp -R "$SEARXNG_CHART"/. "$searxng_copy"/
    sx_dep_log="$searxng_copy/dependency-update.log"
    if ! (cd "$searxng_copy" && "$helm_bin" dependency update .) >"$sx_dep_log" 2>&1; then
      if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$sx_dep_log"; then
        skip "t2: helm dependency update could not reach the registry for $SEARXNG_CHART here; t2-t3 were not run (log kept at $sx_dep_log)"
        skip_searxng=1
        searxng_copy=""
      else
        tail -n 30 "$sx_dep_log" >&2
        fail "t2: helm dependency update failed for $SEARXNG_CHART (log kept at $sx_dep_log)"
      fi
    fi
  fi
fi

if want t2 && [ "$skip_searxng" -eq 0 ]; then
  sx_lint_log="$WORK/lint-searxng.log"
  if (cd "$searxng_copy" && "$helm_bin" lint .) >"$sx_lint_log" 2>&1; then
    ok "t2: helm lint passes for $SEARXNG_CHART (C01 AC1)"
  else
    tail -n 30 "$sx_lint_log" >&2
    fail "t2: helm lint failed for $SEARXNG_CHART (log kept at $sx_lint_log)"
  fi
fi

if want t3 && [ "$skip_searxng" -eq 0 ]; then
  sx_out="$WORK/searxng-render.yaml"
  sx_err="$WORK/searxng-render.err"
  if ! "$helm_bin" template searxng "$searxng_copy" \
      --set "domain=test.example.com" \
      --set "bitwardenIds.searxng=$TEST_UUID" \
      >"$sx_out" 2>"$sx_err"; then
    tail -n 30 "$sx_err" >&2
    fail "t3: helm template of the $SEARXNG_CHART copy failed (log kept at $sx_err)"
  fi
  [ -s "$sx_out" ] || fail "t3: the searxng render produced no output"
  if python3 - "$sx_out" "$TEST_UUID" "$WORK/t3-count" <<'PY'
import sys, yaml

render, test_uuid, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    raw = open(render).read()
    docs = [d for d in yaml.safe_load_all(raw) if d]

    es = [d for d in docs if d.get('kind') == 'ExternalSecret']
    if len(es) != 1 or (es[0].get('metadata') or {}).get('name') != 'searxng':
        bad(f't3: expected exactly one ExternalSecret named searxng, got {[(d.get("metadata") or {}).get("name") for d in es]}')
    spec = es[0].get('spec') or {}
    data = spec.get('data') or []
    if len(data) != 1:
        bad(f't3: the ExternalSecret has {len(data)} data entries, expected exactly 1 (secret_key)')
    d0 = data[0]
    if d0.get('secretKey') != 'secret_key':
        bad(f't3: secretKey is {d0.get("secretKey")!r}, expected secret_key')
    store = ((d0.get('sourceRef') or {}).get('storeRef') or {}).get('name')
    if store != 'bitwarden-login':
        bad(f't3: storeRef.name is {store!r}, expected bitwarden-login (the LOGIN item\'s password field carries the secret_key)')
    rr = d0.get('remoteRef') or {}
    if rr.get('key') != test_uuid:
        bad(f't3: remoteRef.key is {rr.get("key")!r}, expected the --set test-uuid {test_uuid!r} — the item id must flow from values, never be hardcoded')
    if rr.get('property') != 'password':
        bad(f't3: remoteRef.property is {rr.get("property")!r}, expected password')
    ok('t3: ExternalSecret searxng — secret_key <- bitwarden-login/password, remoteRef key from --set (C01 AC2)')

    tmpl = ((spec.get('target') or {}).get('template') or {}).get('data') or {}
    if 'SEARXNG_SECRET_KEY' not in tmpl:
        bad(f't3: the target Secret template has no SEARXNG_SECRET_KEY key (keys: {sorted(tmpl)})')
    settings = tmpl.get('settings.yml')
    if settings is None:
        bad(f't3: the target Secret template has no settings.yml key (keys: {sorted(tmpl)})')
    try:
        s = yaml.safe_load(settings)
    except Exception as ex:
        bad(f't3: the rendered settings.yml template entry is not parseable YAML: {ex}')
    formats = ((s.get('search') or {}).get('formats'))
    if formats != ['html', 'json']:
        bad(f't3: settings search.formats is {formats!r}, expected [html, json] — the JSON API is what mcp-searxng consumes; without json, /search?format=json is a 403')
    ok('t3: target Secret data carries SEARXNG_SECRET_KEY + settings.yml with formats [html, json] (C01 AC2)')

    services = [d for d in docs if d.get('kind') == 'Service']
    hit8080 = any(8080 in [(p or {}).get('port') for p in (svc.get('spec') or {}).get('ports') or []]
                  for svc in services)
    if not hit8080:
        bad(f't3: no Service exposes port 8080 (services: {[(svc.get("metadata") or {}).get("name") for svc in services]}) — the MCP server reaches it at http://dev-searxng.default.svc.cluster.local:8080')
    ok('t3: a Service exposes port 8080 (C01 AC2)')

    pvcs = [(d.get('metadata') or {}).get('name') for d in docs if d.get('kind') == 'PersistentVolumeClaim']
    if 'searxng' not in pvcs:
        bad(f't3: no PersistentVolumeClaim named searxng (claims: {pvcs}) — the config persistence existingClaim must survive')
    claims = set()
    for d in docs:
        pod = (((d.get('spec') or {}).get('template') or {}).get('spec')) or {}
        for v in pod.get('volumes') or []:
            claim = ((v or {}).get('persistentVolumeClaim') or {}).get('claimName')
            if claim:
                claims.add(claim)
    if 'searxng' not in claims:
        bad(f't3: no workload mounts claim searxng (claims mounted: {sorted(claims)})')
    ok('t3: PVC claim searxng exists and is mounted by the workload (C01 AC2)')

    if 'OVERRIDE_' in raw:
        bad('t3: the rendered searxng output still carries an OVERRIDE_* sentinel after --set bitwardenIds.searxng')
    ok('t3: zero OVERRIDE_* in the rendered searxng output (C01 AC2)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't3: the searxng render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t3-count")))
  else
    exit 1
  fi
fi

# --- t4: custom-values searxng slice (C01 AC4) --------------------------------
if want t4; then
  if python3 - "$DEV_CV" "$WORK/t4-count" <<'PY'
import re, sys, yaml

dev_cv, count_file = sys.argv[1:3]
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

UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')

try:
    cv = load(dev_cv)
    slot = (((cv.get('searxng') or {}).get('bitwardenIds') or {}).get('searxng'))
    if slot is None:
        bad(f't4: {dev_cv} has no top-level searxng.bitwardenIds.searxng slot — appset-charts.yaml extracts only (index .Values $appName) into the dev-searxng release, so the chart sentinel would stay unresolved (C01 AC4)')
    if not (isinstance(slot, str) and slot.strip()):
        bad(f't4: searxng.bitwardenIds.searxng is {slot!r}, expected a non-empty string')
    if slot != 'OVERRIDE_NEEDED' and not UUID_RE.match(slot):
        bad(f't4: searxng.bitwardenIds.searxng is {slot!r}; expected a real UUID (the dev-searxng LOGIN item exists: f90806ff-8ee5-435d-b2e2-b4ed0176d701 per DECISIONS 2026-10-24 ruling) or the OVERRIDE_NEEDED interim until that paste lands')
    ok(f't4: custom-values searxng.bitwardenIds.searxng slot present ({slot}) (C01 AC4)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't4: the custom-values check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t4-count")))
  else
    exit 1
  fi
fi

# --- t5+t9: dev umbrella render (C01 AC5, C03 AC3) ----------------------------
# One render feeds both: the umbrella has no chart dependencies, so it renders
# offline; only helm itself is needed. The --set bitwardenIds are the plan's
# six Commands entries (C01 t5 says "the six test bitwardenIds from plan
# Commands") plus bitwardenIds.forgejo-token-canonical — the seventh, added
# 2026-10-25 when 2026-10-feat-forgejo-auth-support C03 landed its sentinel on
# this umbrella: the t9 sweep resolves EVERY top-level sentinel, exactly what
# the deploy-time custom-values layer does. --set-ingesting github-mcp/
# wekan-mcp before C03 exists is inert and keeps the command identical across
# chunks.
umb_out=""
if want t5 || want t9; then
  if [ -z "$helm_bin" ]; then
    skip "t5: no helm binary; the umbrella render (t5, t9) was not run"
  else
    umb_out="$WORK/dev-umbrella-render.yaml"
    umb_err="$WORK/dev-umbrella-render.err"
    if ! "$helm_bin" template dev "$DEVUMB" \
        --set "domain=test.example.com" --set "clusterName=dev" \
        --set "bitwardenIds.github-mcp=$TEST_UUID_GITHUB" \
        --set "bitwardenIds.wekan-mcp=$TEST_UUID_WEKAN" \
        --set "bitwardenIds.cert-manager-solver-token=$TEST_UUID" \
        --set "bitwardenIds.argocd-sso-secret=$TEST_UUID" \
        --set "bitwardenIds.github-pat=$TEST_UUID" \
        --set "bitwardenIds.forgejo-token=$TEST_UUID" \
        --set "bitwardenIds.forgejo-token-canonical=$TEST_UUID_CANONICAL" \
        >"$umb_out" 2>"$umb_err"; then
      tail -n 30 "$umb_err" >&2
      fail "t5: helm template of $DEVUMB failed (log kept at $umb_err)"
    fi
    [ -s "$umb_out" ] || fail "t5: the dev umbrella render produced no output"
  fi
fi

# --- t5: searxng LAN ingress (C01 AC5) ----------------------------------------
if want t5 && [ -n "$umb_out" ]; then
  if python3 - "$umb_out" "$WORK/t5-count" <<'PY'
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

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    ingresses = [d for d in docs if d.get('kind') == 'Ingress']

    named = [(d.get('metadata') or {}).get('name') for d in ingresses]
    if 'searxng-ingress' not in named:
        bad(f't5: no Ingress named searxng-ingress (ingresses: {named}) — the key-derived generic-ingress form must render the LAN host (C01 AC5)')
    ing = next(d for d in ingresses if (d.get('metadata') or {}).get('name') == 'searxng-ingress')

    hosts = [((r or {}).get('host')) for r in ((ing.get('spec') or {}).get('rules') or [])]
    if hosts != ['searxng.test.example.com']:
        bad(f't5: searxng-ingress rule hosts are {hosts!r}, expected exactly [searxng.test.example.com] (top-level LAN host, NOT searxng.dev.test.example.com — clusterBase must stay absent)')

    paths = (((ing.get('spec') or {}).get('rules') or [{}])[0].get('http') or {}).get('paths') or []
    if len(paths) != 1:
        bad(f't5: searxng-ingress has {len(paths)} paths, expected exactly 1')
    backend = ((paths[0].get('backend') or {}).get('service') or {})
    if backend.get('name') != 'dev-searxng' or ((backend.get('port') or {}).get('number')) != 8080:
        bad(f't5: searxng-ingress backend is {backend.get("name")!r}:{((backend.get("port") or {}).get("number"))}, expected dev-searxng:8080')

    tls = ((ing.get('spec') or {}).get('tls') or [])
    if len(tls) != 1 or ((tls[0] or {}).get('secretName')) != 'wildcard-cert':
        bad(f't5: searxng-ingress tls is {tls!r}, expected one entry with secretName wildcard-cert (top-level cert, not cluster-wildcard-cert)')
    tls_hosts = (tls[0] or {}).get('hosts') or []
    if 'searxng.test.example.com' not in tls_hosts:
        bad(f't5: searxng-ingress tls hosts are {tls_hosts!r}, expected them to include the rule host')
    ok('t5: Ingress searxng-ingress — host searxng.test.example.com, dev-searxng:8080, TLS wildcard-cert (C01 AC5)')

    # The proxy-remote external-dns target is commented out in the template;
    # parse-based absence is the real contract (raw grep would match the
    # comment line itself). Any *uncommented* proxy-remote target by any other
    # name would still route the host off-cluster — user decision says no.
    ann = ((ing.get('metadata') or {}).get('annotations') or {})
    edns = [k for k in ann if 'external-dns' in k]
    if edns:
        bad(f't5: searxng-ingress carries external-dns annotation(s) {edns} — the LAN host must NOT get a proxy-remote target (C01 AC5, user decision 2026-10-24)')
    # Guard against a copied-with-serviceName implementation: that renders a
    # second, dev-searxng-backed ingress beside the key-derived one.
    routed = [n for (d, n) in zip(ingresses, named)
              for r in ((d.get('spec') or {}).get('rules') or [])
              for p in (((r or {}).get('http') or {}).get('paths') or [])
              if (((p.get('backend') or {}).get('service') or {}).get('name')) == 'dev-searxng']
    if len(routed) != 1:
        bad(f't5: {len(routed)} ingresses route to dev-searxng ({routed}), expected exactly 1 — a serviceName key would render a duplicate second ingress beside the key-derived one (gpu sets serviceName; dev must not)')
    ok('t5: no external-dns annotation on searxng-ingress and exactly one ingress routes dev-searxng (C01 AC5)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't5: the dev umbrella render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t5-count")))
  else
    exit 1
  fi
fi

# --- t9: umbrella ExternalSecret templates (C03 AC3) --------------------------
# github-mcp: bitwarden-login/password <- --set UUID (DECISIONS 2026-10-24 user
# ruling: reuses the existing dev-github LOGIN item, password = PAT; the
# internal secretKey name stays 'token'), GITHUB_PERSONAL_ACCESS_TOKEN target.
# wekan-mcp: THREE entries from the same LOGIN item — username+password
# via bitwarden-login, base URL via bitwarden-uri (the OQ1 resolution: no
# hardcoded host). forgejo-token-canonical (added 2026-10-25): the documented
# must-fill slot on this umbrella (custom-values/dev holds OVERRIDE_NEEDED per
# the infra-forgejo t6 precedent + dev-git-auth c-canonical-2) — its rendered
# ExternalSecret is pinned and tied to its --set UUID. Sentinel sweep follows
# the dev-forgejo-runner convention, narrowed the same day to the
# OVERRIDE_VIA_* deploy-time class: those may ride ONLY inside the appset-
# generator values blob (a real deploy resolves them from custom-values via
# the cluster annotation); no service/cluster sentinel may leak elsewhere.
if want t9 && [ -n "$umb_out" ]; then
  if python3 - "$umb_out" "$TEST_UUID_GITHUB" "$TEST_UUID_WEKAN" "$TEST_UUID_CANONICAL" "$WORK/t9-count" <<'PY'
import sys, yaml

render, uuid_github, uuid_wekan, uuid_canonical, count_file = sys.argv[1:6]
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
    by_name = {}
    for d in docs:
        if d.get('kind') == 'ExternalSecret':
            by_name[(d.get('metadata') or {}).get('name')] = d

    es = by_name.get('github-mcp')
    if es is None:
        bad(f't9: no ExternalSecret named github-mcp in the umbrella render ({sorted(by_name)}) — services/dev/prod/templates/secret-github-mcp.yaml is missing')
    spec = es.get('spec') or {}
    if (((spec.get('target') or {}).get('name'))) != 'github-mcp':
        bad(f't9: github-mcp ExternalSecret target Secret name is {((spec.get("target") or {}).get("name"))!r}, expected github-mcp (the renovate initContainer secretKeyRef hardcodes it)')
    data = spec.get('data') or []
    if len(data) != 1:
        bad(f't9: github-mcp has {len(data)} data entries, expected exactly 1')
    d0 = data[0]
    rr = d0.get('remoteRef') or {}
    if d0.get('secretKey') != 'token':
        bad(f't9: github-mcp secretKey is {d0.get("secretKey")!r}, expected token (the internal name — the ruling changed the source field, not this key)')
    if ((d0.get('sourceRef') or {}).get('storeRef') or {}).get('name') != 'bitwarden-login':
        bad(f't9: github-mcp store is {((d0.get("sourceRef") or {}).get("storeRef") or {}).get("name")!r}, expected bitwarden-login — DECISIONS 2026-10-24 user ruling: the dev GitHub token reuses the EXISTING dev-github LOGIN item (522b1cc4-…, password = the PAT), not a new FIELDS item')
    if rr.get('property') != 'password':
        bad(f't9: github-mcp remoteRef.property is {rr.get("property")!r}, expected password (the LOGIN item\'s password field carries the PAT per the 2026-10-24 ruling)')
    if rr.get('key') != uuid_github:
        bad(f't9: github-mcp remoteRef.key is {rr.get("key")!r}, expected the --set test-uuid {uuid_github!r} (read from top-level .Values.bitwardenIds)')
    for k in ('conversionStrategy', 'decodingStrategy', 'metadataPolicy'):
        if k not in rr:
            bad(f't9: github-mcp remoteRef lacks the ArgoCD boilerplate {k} (gpu templates carry it verbatim)')
    tmpl = ((spec.get('target') or {}).get('template') or {}).get('data') or {}
    if tmpl.get('GITHUB_PERSONAL_ACCESS_TOKEN') != '{{ .token }}':
        bad(f't9: github-mcp template GITHUB_PERSONAL_ACCESS_TOKEN is {tmpl.get("GITHUB_PERSONAL_ACCESS_TOKEN")!r}, expected {{{{ .token }}}}')
    ok('t9: ExternalSecret github-mcp — bitwarden-login/password from the --set UUID, GITHUB_PERSONAL_ACCESS_TOKEN <- {{ .token }} (C03 AC3 as re-ruled 2026-10-24)')

    es = by_name.get('wekan-mcp')
    if es is None:
        bad(f't9: no ExternalSecret named wekan-mcp in the umbrella render ({sorted(by_name)}) — services/dev/prod/templates/secret-wekan-mcp.yaml is missing')
    spec = es.get('spec') or {}
    if (((spec.get('target') or {}).get('name'))) != 'wekan-mcp':
        bad(f't9: wekan-mcp ExternalSecret target Secret name is {((spec.get("target") or {}).get("name"))!r}, expected wekan-mcp')
    entries = {(d or {}).get('secretKey'): d for d in (spec.get('data') or [])}
    if set(entries) != {'username', 'password', 'url'}:
        bad(f't9: wekan-mcp secretKeys are {sorted(entries)}, expected exactly [username, password, url] (three values from the ONE item d8e2b2ca, per the secret-homeassistant-mcp multi-store pattern)')
    expect = {
        'username': ('bitwarden-login', 'username'),
        'password': ('bitwarden-login', 'password'),
        'url': ('bitwarden-uri', None),
    }
    for key, (store, prop) in expect.items():
        d = entries[key]
        got_store = ((d.get('sourceRef') or {}).get('storeRef') or {}).get('name')
        if got_store != store:
            bad(f't9: wekan-mcp {key}: store is {got_store!r}, expected {store!r}')
        rr = d.get('remoteRef') or {}
        if rr.get('property') != prop:
            bad(f't9: wekan-mcp {key}: remoteRef.property is {rr.get("property")!r}, expected {prop!r}')
        if rr.get('key') != uuid_wekan:
            bad(f't9: wekan-mcp {key}: remoteRef.key is {rr.get("key")!r}, expected the --set test-uuid {uuid_wekan!r} (all three entries read the SAME LOGIN item)')
    tmpl = ((spec.get('target') or {}).get('template') or {}).get('data') or {}
    want_keys = {
        'WEKAN_USERNAME': '{{ .username }}',
        'WEKAN_PASSWORD': '{{ .password }}',
        'WEKAN_BASE_URL': '{{ .url }}',
    }
    for k, v in want_keys.items():
        if tmpl.get(k) != v:
            bad(f't9: wekan-mcp template {k} is {tmpl.get(k)!r}, expected {v!r} (backtick-escaped Go template reaching the C02 login flow)')
    if 'WEKAN_TOKEN' in tmpl:
        bad('t9: wekan-mcp template carries WEKAN_TOKEN — dev mints it in-pod from username+password (C02), the gpu token-only pattern must not be copied')
    ok('t9: ExternalSecret wekan-mcp — username/password <- bitwarden-login, url <- bitwarden-uri, three templated WEKAN_* env keys, no WEKAN_TOKEN (C03 AC3)')

    # The sanctioned must-fill slot: pinned here so the narrowed sweep
    # below can never hide an unresolved sentinel of the same class — the
    # ladder's --set leg must actually reach this document.
    canon = [d for d in docs if d.get('kind') == 'ExternalSecret'
             and (d.get('metadata') or {}).get('name') == 'forgejo-token-canonical']
    if len(canon) != 1:
        bad(f't9: expected exactly one ExternalSecret named forgejo-token-canonical in the umbrella render ({len(canon)} found) — services/dev/prod/templates/secret-forgejo-token-canonical.yaml is missing or duplicated')
    cdata = ((canon[0].get('spec') or {}).get('data')) or []
    if len(cdata) != 1:
        bad(f't9: forgejo-token-canonical has {len(cdata)} data entries, expected exactly 1 (one password read)')
    crr = ((cdata[0] or {}).get('remoteRef') or {})
    if crr.get('key') != uuid_canonical:
        bad(f't9: forgejo-token-canonical remoteRef.key is {crr.get("key")!r}, expected the --set UUID {uuid_canonical!r} — the documented must-fill slot must resolve through the same ladder the deploy uses (its custom-values value is the OVERRIDE_NEEDED placeholder until the Bitwarden item exists)')
    ok('t9: ExternalSecret forgejo-token-canonical — the documented must-fill slot renders with its remoteRef tied to the --set UUID (amended 2026-10-25)')

    for d in docs:
        if d.get('kind') == 'ApplicationSet':
            continue
        t = yaml.safe_dump(d)
        if 'OVERRIDE_VIA_' in t:
            bad(f't9: non-appset document {((d.get("metadata") or {}).get("name"))!r} ({d.get("kind")}) carries an OVERRIDE_VIA_* deploy-time sentinel — only the appset-generator values blob may hold unresolved placeholders')
    ok('t9: zero OVERRIDE_VIA_* outside the ApplicationSet documents of the dev umbrella render (C03 AC3, narrowed 2026-10-25 with the must-fill pin above)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't9: the dev umbrella render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t9-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# C03 — hivetools slice (t6, t7, t8, t11) + umbrella sentinels (t10)
# =========================================================================

# --- t6: lints (C03 AC1) ------------------------------------------------------
# The umbrella lint runs in place (dependency-free chart, lint writes nothing).
# The hivetools lint + slice render (t6/t7/t8/t11) need the OCI toolhive deps:
# copy + dependency update, skip-with-warning when ghcr is unreachable.
if want t6; then
  if [ -z "$helm_bin" ]; then
    skip "t6: no helm binary; helm lints were not run"
  else
    umb_lint_log="$WORK/lint-umbrella.log"
    if "$helm_bin" lint "$DEVUMB" >"$umb_lint_log" 2>&1; then
      ok "t6: helm lint passes for $DEVUMB (C03 AC1)"
    else
      tail -n 30 "$umb_lint_log" >&2
      fail "t6: helm lint failed for $DEVUMB (log kept at $umb_lint_log)"
    fi
  fi
fi

hive_copy=""
skip_hive=0
if want t6 || want t7 || want t8 || want t11; then
  [ -d "$HIVETOOLS_CHART" ] ||
    fail "t6: $HIVETOOLS_CHART does not exist (nothing to dependency-update, lint, or render)"
  if [ -z "$helm_bin" ]; then
    skip "t6: no helm binary; the $HIVETOOLS_CHART lint and the slice render (t7, t8, t11) were not run"
    skip_hive=1
  else
    hive_copy="$WORK/hivetools-copy"
    cp -R "$HIVETOOLS_CHART"/. "$hive_copy"/
    hive_dep_log="$hive_copy/dependency-update.log"
    if ! (cd "$hive_copy" && "$helm_bin" dependency update .) >"$hive_dep_log" 2>&1; then
      if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$hive_dep_log"; then
        skip "t6: helm dependency update could not reach the OCI registry for $HIVETOOLS_CHART here; the hivetools lint and slice render (t7, t8, t11) were not run (log kept at $hive_dep_log)"
        skip_hive=1
        hive_copy=""
      else
        tail -n 30 "$hive_dep_log" >&2
        fail "t6: helm dependency update failed for $HIVETOOLS_CHART (log kept at $hive_dep_log)"
      fi
    fi
  fi
fi

if want t6 && [ "$skip_hive" -eq 0 ]; then
  hive_lint_log="$WORK/lint-hivetools.log"
  if (cd "$hive_copy" && "$helm_bin" lint .) >"$hive_lint_log" 2>&1; then
    ok "t6: helm lint passes for $HIVETOOLS_CHART (C03 AC1)"
  else
    tail -n 30 "$hive_lint_log" >&2
    fail "t6: helm lint failed for $HIVETOOLS_CHART (log kept at $hive_lint_log)"
  fi
fi

# --- shared slice render for t7/t8/t11 ----------------------------------------
# mcp-servers.md Validation recipe: extract dev's hivetools: block to a temp
# values file, render the standalone chart with the test domain/cluster/sso/
# realm --sets (a slice before C03 simply lacks the mcp: map — t7/t11 then
# fail for exactly the right reason).
hive_render=""
if { want t7 || want t8 || want t11; } && [ "$skip_hive" -eq 0 ]; then
  slice="$WORK/hivetools-slice.yaml"
  if ! python3 - "$DEV_VALUES" "$slice" <<'PY'
import re, sys, yaml

dev_vals, out = sys.argv[1:3]

def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

sv = load(dev_vals)
h = sv.get('hivetools') or {}
with open(out, 'w') as f:
    yaml.safe_dump(h, f)
PY
  then
    fail "t7: could not extract the hivetools: block from $DEV_VALUES"
  fi
  hive_render="$WORK/hivetools-render.yaml"
  hive_err="$WORK/hivetools-render.err"
  if ! "$helm_bin" template hivetools "$hive_copy" \
      -f "$slice" \
      --set "domain=test.example.com" --set "clusterName=dev" --set "subDomain=dev" \
      --set "bitwardenIds.mcp-sso=$TEST_UUID" --set "keycloak.realm=test" \
      >"$hive_render" 2>"$hive_err"; then
    tail -n 30 "$hive_err" >&2
    fail "t7: helm template of the $HIVETOOLS_CHART copy with the dev slice failed (log kept at $hive_err)"
  fi
  [ -s "$hive_render" ] || fail "t7: the hivetools slice render produced no output"
fi

# --- t7: four MCPServers + ingress paths (C03 AC2 + AC5) -----------------------
if want t7 && [ -n "$hive_render" ]; then
  if python3 - "$hive_render" "$WORK/t7-count" <<'PY'
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

def by_kind(docs, kind):
    return [d for d in docs if d.get('kind') == kind]

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    servers = {}
    for d in by_kind(docs, 'MCPServer'):
        servers[(d.get('metadata') or {}).get('name')] = d.get('spec') or {}

    for name in ('mcp-playwright', 'mcp-renovate', 'mcp-searxng', 'mcp-boards'):
        if name not in servers:
            bad(f't7: no MCPServer {name} in the slice render (present: {sorted(servers)}) — the dev hivetools.mcp entry is missing or disabled')

    # MCPServer CRD declares spec.secrets x-kubernetes-list-type: map keyed by
    # name — one Secret name may appear at most ONCE per server (live proof
    # 2026-10-25: ArgoCD rejected mcp-boards "duplicate entries for key
    # [name=wekan-mcp]", so it was never admitted — no pod, dead /boards
    # backend). Multi-key Secrets go through podTemplateSpec envFrom instead
    # (gpu homeassistant precedent; user ruling 2026-10-25). Enforced across
    # every rendered MCPServer, not just boards, so no future entry repeats it.
    for srv_name in sorted(servers):
        sec_names = [(s or {}).get('name') for s in (servers[srv_name].get('secrets') or [])]
        dupes = sorted({n for n in sec_names if sec_names.count(n) > 1})
        if dupes:
            bad(f't7: {srv_name} repeats Secret name(s) {dupes} in spec.secrets ({sec_names}) — the CRD list-map keyed by name rejects duplicates and the object is never admitted; use podTemplateSpec envFrom for a multi-key Secret (2026-10-25 ruling)')
    ok(f't7: spec.secrets name-uniqueness holds across all {len(servers)} rendered MCPServers (CRD list-map keyed by name, 2026-10-25 ruling)')

    pw = servers['mcp-playwright']
    if pw.get('image') != 'mcr.microsoft.com/playwright/mcp:v0.0.78':
        bad(f't7: mcp-playwright image is {pw.get("image")!r}, expected mcr.microsoft.com/playwright/mcp:v0.0.78 (gpu:428-487 verbatim)')
    if pw.get('transport') != 'streamable-http' or pw.get('mcpPort') != 8931 or pw.get('proxyPort') != 8080:
        bad(f't7: mcp-playwright transport/mcpPort/proxyPort is {pw.get("transport")!r}/{pw.get("mcpPort")!r}/{pw.get("proxyPort")!r}, expected streamable-http/8931/8080')
    ok('t7: MCPServer mcp-playwright — image, streamable-http, mcpPort 8931, proxyPort 8080 (C03 AC2)')

    rn = servers['mcp-renovate']
    if rn.get('image') != 'ghcr.io/ownyourio/renovate-mcp:v31':
        bad(f't7: mcp-renovate image is {rn.get("image")!r}, expected ghcr.io/ownyourio/renovate-mcp:v31 (gpu:772-885 verbatim; no hand-bumped tag per Hard rule)')
    if rn.get('transport') != 'streamable-http' or rn.get('mcpPort') != 8080:
        bad(f't7: mcp-renovate transport/mcpPort is {rn.get("transport")!r}/{rn.get("mcpPort")!r}, expected streamable-http/8080')
    initcs = ((rn.get('podTemplateSpec') or {}).get('spec') or {}).get('initContainers') or []
    clone = next((c for c in initcs if (c or {}).get('name') == 'clone'), None)
    if clone is None:
        bad(f't7: mcp-renovate has no initContainer named clone (initContainers: {[(c or {}).get("name") for c in initcs]}) — the workspace clone leg is missing')
    cenv = {(e or {}).get('name'): e for e in clone.get('env') or []}
    skr = ((((cenv.get('GITHUB_PERSONAL_ACCESS_TOKEN') or {}).get('valueFrom') or {}).get('secretKeyRef') or {}))
    if skr.get('name') != 'github-mcp' or skr.get('key') != 'GITHUB_PERSONAL_ACCESS_TOKEN':
        bad(f't7: clone GITHUB_PERSONAL_ACCESS_TOKEN secretKeyRef is {skr.get("name")!r}/{skr.get("key")!r}, expected github-mcp/GITHUB_PERSONAL_ACCESS_TOKEN (the t9 ExternalSecret target)')
    args_joined = ' '.join((clone.get('command') or []) + [str(a) for a in (clone.get('args') or [])])
    if 'rm -rf /workspace/SpencersLab' not in args_joined:
        bad(f't7: clone args lack the idempotent rm -rf (/workspace emptyDir survives restarts; git clone refuses a non-empty target -> CrashLoopBackOff): {args_joined!r}')
    if 'github.com/OwnYourIO/SpencersLab.git' not in args_joined:
        bad(f't7: clone args do not target github.com/OwnYourIO/SpencersLab.git (the forgejo remotes are mirrors — DECISIONS.md): {args_joined!r}')
    ok('t7: MCPServer mcp-renovate — v31 image, clone initContainer with github-mcp secretKeyRef + idempotent rm -rf of the origin clone (C03 AC2+AC5)')

    sx = servers['mcp-searxng']
    if sx.get('image') != 'isokoliuk/mcp-searxng:1.13.0':
        bad(f't7: mcp-searxng image is {sx.get("image")!r}, expected isokoliuk/mcp-searxng:1.13.0 (gpu:554-588 verbatim except SEARXNG_URL)')
    if sx.get('transport') != 'streamable-http' or sx.get('mcpPort') != 8080:
        bad(f't7: mcp-searxng transport/mcpPort is {sx.get("transport")!r}/{sx.get("mcpPort")!r}, expected streamable-http/8080')
    sxenv = {(e or {}).get('name'): (e or {}).get('value') for e in sx.get('env') or []}
    if sxenv.get('SEARXNG_URL') != 'http://dev-searxng.default.svc.cluster.local:8080':
        bad(f't7: mcp-searxng SEARXNG_URL is {sxenv.get("SEARXNG_URL")!r}, expected http://dev-searxng.default.svc.cluster.local:8080 (C01\'s dev-local backend; the gpu URL pointing at gpu-searxng means the entry was copied unedited)')
    if sxenv.get('MCP_HTTP_PORT') != '8080' or sxenv.get('MCP_HTTP_HOST') != '0.0.0.0':
        bad(f't7: mcp-searxng native-HTTP env is MCP_HTTP_PORT={sxenv.get("MCP_HTTP_PORT")!r} MCP_HTTP_HOST={sxenv.get("MCP_HTTP_HOST")!r}, expected "8080"/"0.0.0.0" (without them mcp-searxng stays stdio and the streamable-http transport is a lie)')
    ok('t7: MCPServer mcp-searxng — dev-local SEARXNG_URL + native HTTP env (C03 AC5)')

    bd = servers['mcp-boards']
    # D17/D24 (this ticket's M2 step): the wekan-mcp ref moves from :main to
    # the immutable :v<run_number> of the C01 build once C01 merges, so the
    # boards equality is generalized NOW to (main|v<digits>) — the pin-bump
    # commit must not need a test edit. This is the deliberate exception: the
    # other three fleet images stay strictly pinned above.
    bd_image = str(bd.get('image') or '')
    if not re.fullmatch(r'ghcr\.io/ownyourio/wekan-mcp:(main|v[0-9]+)', bd_image):
        bad(f't7: mcp-boards image is {bd.get("image")!r}, expected ghcr.io/ownyourio/wekan-mcp:main or :v<run> (:main until M1 publishes the tag; :v<digits> after the M2 pin per D17/D24)')
    if bd.get('transport') != 'streamable-http' or bd.get('mcpPort') != 8080:
        bad(f't7: mcp-boards transport/mcpPort is {bd.get("transport")!r}/{bd.get("mcpPort")!r}, expected streamable-http/8080')
    bdenv = {(e or {}).get('name') for e in bd.get('env') or []}
    if 'WEKAN_BASE_URL' in bdenv:
        bad('t7: mcp-boards carries a top-level env WEKAN_BASE_URL — the base URL must arrive via the wekan-mcp Secret (data-driven from the Bitwarden item URI, OQ1 resolution), not a values-pinned host')
    bd_dump = yaml.safe_dump(bd)
    if 'WEKAN_MCP_READ_ONLY' in bd_dump:
        bad('t7: mcp-boards carries WEKAN_MCP_READ_ONLY anywhere — dev-boards is the admin-tier use case; server-side read-only is deliberately NOT enforced (intake decision 2026-10-24)')
    pt_containers = ((bd.get('podTemplateSpec') or {}).get('spec') or {}).get('containers') or []
    mcp_c = next((c for c in pt_containers if (c or {}).get('name') == 'mcp'), None)
    got_pull = (mcp_c or {}).get('imagePullPolicy') if mcp_c is not None else None
    if got_pull != 'Always':
        bad(f't7: mcp-boards podTemplateSpec container mcp imagePullPolicy is {got_pull!r}, expected Always (:main is a mutable tag)')
    envfrom = (mcp_c or {}).get('envFrom') or []
    if not any(((e or {}).get('secretRef') or {}).get('name') == 'wekan-mcp' for e in envfrom):
        bad(f't7: boards mcp container envFrom is {envfrom!r}, expected a secretRef to wekan-mcp — the three runtime values (WEKAN_BASE_URL/USERNAME/PASSWORD, emitted by the t9 ES template) land via envFrom (gpu homeassistant precedent); repeated spec.secrets names are rejected by the CRD list-map keyed by name (2026-10-25 user ruling)')
    ok('t7: MCPServer mcp-boards — image :main|:v<run> + Always pull, wekan-mcp consumed via podTemplateSpec envFrom, no hardcoded BASE_URL, no READ_ONLY (C03 AC2+AC5 as re-ruled 2026-10-25; this ticket\'s D17/D24 pin window)')

    ings = [d for d in by_kind(docs, 'Ingress')
            if (d.get('metadata') or {}).get('name') == 'mcp-multi-server-ingress']
    if len(ings) != 1:
        bad(f't7: expected exactly one Ingress mcp-multi-server-ingress, got {len(ings)}')
    ing_spec = ings[0].get('spec') or {}
    rules = ing_spec.get('rules') or []
    if [((r or {}).get('host')) for r in rules] != ['mcp.dev.test.example.com']:
        bad(f't7: mcp ingress hosts are {[((r or {}).get("host")) for r in rules]!r}, expected exactly [mcp.dev.test.example.com] (subDomain=dev rides the cluster-scoped host form)')
    paths = {}
    for r in rules:
        for p in ((r or {}).get('http') or {}).get('paths') or []:
            paths[(p or {}).get('path')] = ((p.get('backend') or {}).get('service') or {})
    for name in ('playwright', 'renovate', 'searxng', 'boards'):
        svc = paths.get(f'/{name}')
        if svc is None:
            bad(f't7: no ingress path /{name} on mcp.dev.test.example.com (paths: {sorted(paths)}) — boards ships enabled:true (OQ1 resolution), the other three are the fleet itself')
        if svc.get('name') != f'mcp-mcp-{name}-proxy':
            bad(f't7: path /{name} backend is {svc.get("name")!r}, expected mcp-mcp-{name}-proxy (ToolHive proxy service naming)')
        if ((svc.get('port') or {}).get('number')) != 8080:
            bad(f't7: path /{name} backend port is {((svc.get("port") or {}).get("number"))!r}, expected 8080 (the proxy always exposes proxyPort, not mcpPort)')
    ok(f't7: ingress mcp.dev.test.example.com routes /playwright /renovate /searxng /boards -> mcp-mcp-<name>-proxy:8080 (C03 AC2)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't7: the hivetools slice render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t7-count")))
  else
    exit 1
  fi
fi

# --- t8: slice render sentinel-clean (C03 AC2) --------------------------------
if want t8 && [ -n "$hive_render" ]; then
  if grep -q 'OVERRIDE_' "$hive_render"; then
    grep -n 'OVERRIDE_' "$hive_render" | head >&2
    fail "t8: the hivetools slice render carries an OVERRIDE_* substring (log above) — with mcp-sso/realm/domain --set, no chart sentinel may survive the slice render (C03 AC2)"
  fi
  ok 't8: zero OVERRIDE_* in the hivetools slice render (C03 AC2)'
fi

# --- t11: inherited kubernetes gates survive the merge (C03 AC5) --------------
if want t11 && [ -n "$hive_render" ]; then
  if python3 - "$hive_render" "$WORK/t11-count" <<'PY'
import sys, yaml

render, count_file = sys.argv[1:3]

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    names = sorted((d.get('metadata') or {}).get('name')
                   for d in docs if d.get('kind') == 'MCPServer')
    want = sorted(['mcp-kubernetes-readonly', 'mcp-kubernetes-admin',
                   'mcp-playwright', 'mcp-renovate', 'mcp-searxng', 'mcp-boards'])
    # Exact set, not just presence of the two defaults: a whole-map `mcp:`
    # replace (instead of the Helm deep-merge) would drop the gates, and an
    # accidental extra key would mean the dev block escaped its intended size.
    if names != want:
        bad(f't11: MCPServer set is {names}, expected exactly {want} — the chart-default kubernetes-readonly/admin entries must survive the dev hivetools.mcp merge (C03 AC5)')
    print('ok: t11: mcp-kubernetes-readonly + mcp-kubernetes-admin render alongside the four new servers (exact 6-server set, C03 AC5)')
    with open(count_file, 'w') as f:
        f.write('1')
except SystemExit:
    raise
except Exception as ex:
    bad(f't11: the slice render could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t11-count")))
  else
    exit 1
  fi
fi

# --- t10: sentinel 1:1 parity (C03 AC4) ----------------------------------------
# Repo Hard rule (scripted here, per chunk t10 "set comparison, not eyeball"):
# every OVERRIDE_VIA_CUSTOM_VALUES key in the umbrella values has exactly one
# pair in custom-values/dev's top-level bitwardenIds, holding a real UUID or
# the documented OVERRIDE_NEEDED placeholder (never the sentinel itself).
if want t10; then
  if python3 - "$DEV_VALUES" "$DEV_CV" "$WORK/t10-count" <<'PY'
import re, sys, yaml

dev_vals, dev_cv, count_file = sys.argv[1:4]
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

SENTINEL = 'OVERRIDE_VIA_CUSTOM_VALUES'
UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')

try:
    v_bw = (load(dev_vals).get('bitwardenIds') or {})
    c_bw = (load(dev_cv).get('bitwardenIds') or {})
    sentinel_keys = {k for k, v in v_bw.items() if v == SENTINEL}
    non_sentinel = {k: v for k, v in v_bw.items() if v != SENTINEL}
    if non_sentinel:
        bad(f't10: {dev_vals} top-level bitwardenIds carries non-sentinel values {non_sentinel} — real UUIDs live ONLY in custom-values (Hard rule: no secrets/UUIDs in service values)')
    missing = sorted(sentinel_keys - set(c_bw))
    extra = sorted(set(c_bw) - set(v_bw))
    if missing:
        bad(f't10: umbrella sentinel(s) {missing} have no key in {dev_cv} top-level bitwardenIds — they would deploy unresolved')
    if extra:
        bad(f't10: custom-values key(s) {extra} have no sentinel in {dev_vals} — an orphaned UUID that no template reads')
    for k in sorted(sentinel_keys):
        v = c_bw[k]
        if not (isinstance(v, str) and (v == 'OVERRIDE_NEEDED' or UUID_RE.match(v))):
            bad(f't10: {dev_cv} bitwardenIds.{k} is {v!r} — expected a real UUID or the documented OVERRIDE_NEEDED placeholder (never the sentinel, never empty)')
    ok(f't10: umbrella<->custom-values sentinel parity 1:1 over all {len(sentinel_keys)} top-level bitwardenIds keys (C03 AC4)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't10: the parity check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t10-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# C04 — client config + rulesync
# =========================================================================

# --- t12: opencode.jsonc dev-* server entries (C04 AC1) -----------------------
if want t12; then
  if python3 - "$OC_CFG" "$WORK/t12-count" <<'PY'
import json, re, sys

cfg_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def strip_jsonc(text):
    """Remove // and /* */ comments, then trailing commas before } or ]."""
    out, i, n = [], 0, len(text)
    instr, esc = False, False
    while i < n:
        c = text[i]
        if instr:
            out.append(c)
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                instr = False
            i += 1
            continue
        if c == '"':
            instr = True
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    s = ''.join(out)
    return re.sub(r',(\s*[}\]])', r'\1', s)

WANT_SERVERS = {
    'dev-playwright': 'https://mcp.dev.scifi.farm/playwright/mcp',
    'dev-renovate': 'https://mcp.dev.scifi.farm/renovate/mcp',
    'dev-searxng': 'https://mcp.dev.scifi.farm/searxng/mcp',
    'dev-boards': 'https://mcp.dev.scifi.farm/boards/mcp',
}

try:
    cfg = json.loads(strip_jsonc(open(cfg_path).read()))
    ok(f't12: {cfg_path} parses as JSONC (comment-stripped json.loads, C04 AC1)')

    servers = ((cfg.get('mcp') or {}).get('servers') or {})
    if not servers:
        bad(f't12: {cfg_path} has no mcp.servers envelope (the V2 shape the whole fleet relies on)')
    for name, url in WANT_SERVERS.items():
        e = servers.get(name)
        if not isinstance(e, dict):
            bad(f't12: mcp.servers has no {name} entry')
        if e.get('type') != 'remote':
            bad(f't12: {name}.type is {e.get("type")!r}, expected remote')
        if e.get('url') != url:
            bad(f't12: {name}.url is {e.get("url")!r}, expected {url!r} (public ingress form like the dev-kubernetes entries — NOT the in-cluster -headless form; path fixed by C03)')
        if e.get('disabled') is not False:
            bad(f't12: {name}.disabled is {e.get("disabled")!r}, expected false (all four ship enabled; boards per the OQ1 resolution)')
        if e.get('timeout') != {'catalog': 60000, 'execution': 60000}:
            bad(f't12: {name}.timeout is {e.get("timeout")!r}, expected {{catalog: 60000, execution: 60000}} (fleet convention)')
    ok(f't12: all four dev-* entries — remote, public /<name>/mcp URLs, enabled, 60s catalog/execution timeouts (C04 AC1)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't12: the client-config check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t12-count")))
  else
    exit 1
  fi
fi

# --- t13: dev* allow rules in the six rulesync sources (C04 AC2) ---------------
# The triplet must exist per file AND the admin* deny must still precede it:
# the dev* allow is what unblocks tier-less dev-* servers in unattended runs,
# but an admin* allow sneaking ahead would silently widen the admin deny
# scope. The six files are exactly those carrying the readonly*/global*
# triplet (agent-coord.md and the numbered pipeline agents have a different
# permission shape — out of scope per C04).
if want t13; then
  if python3 - "$WORK/t13-count" "${AGENT_SOURCES[@]}" <<'PY'
import re, sys

count_file, sources = sys.argv[1], sys.argv[2:]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def find_action(lines, pattern):
    return [i for i, l in enumerate(lines)
            if re.match(r'^\s*-\s*action:\s*' + pattern + r'\s*$', l)]

def effect_of(lines, idx):
    for j in range(idx + 1, min(idx + 4, len(lines))):
        m = re.match(r'^\s*effect:\s*(\S+)', lines[j])
        if m:
            return m.group(1)
    return None

try:
    for src in sources:
        with open(src) as f:
            lines = f.read().splitlines()
        dev_idx = find_action(lines, r'dev\*')
        if not dev_idx:
            bad(f't13: {src} has no `action: dev*` rule (C04 AC2 — without it the tier-less dev-* servers fall through to ask = blocked in unattended pipeline runs)')
        if len(dev_idx) != 1:
            bad(f't13: {src} has {len(dev_idx)} `action: dev*` rules, expected exactly 1')
        i = dev_idx[0]
        if not re.match(r"^\s*resource:\s*'\*'\s*$", lines[i + 1] if i + 1 < len(lines) else ''):
            bad(f't13: {src} line after `action: dev*` is not `resource: '*'` — the C04 triplet is action/resource/effect, verbatim')
        if effect_of(lines, i) != 'allow':
            bad(f't13: {src} dev* rule effect is not `allow`')
        admin_idx = [k for k in find_action(lines, r'admin\*') if effect_of(lines, k) == 'deny']
        if not admin_idx:
            bad(f't13: {src} lost its `action: admin*` deny rule — dev-* must be granted ONLY by the dev* allow, never by reopening admin')
        if admin_idx[0] > i:
            bad(f't13: {src} places the dev* allow before the admin* deny — first-match semantics would leave the deny unreachable (ordering guard, C04 AC2)')
        ok(f't13: {src} — dev* allow triplet present, admin* deny first (C04 AC2)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f't13: the rulesync source permission check could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/t13-count")))
  else
    exit 1
  fi
fi

# --- t14: rulesync regeneration lands (C04 AC3 + AC4) --------------------------
# generate (not --check) first, then --check exits 0, then the generated
# surfaces must show the ticket's fingerprints AND still match the working
# tree — dirty generated files after generate mean dev edited a generated
# surface by hand or committed sources without the regen (AGENTS.md Hard
# rule). --no-install keeps the whole section offline: rulesync must already
# be resolvable from the npx cache, and its absence is a skip-with-warning
# (this machine has v37 cached; C04's note: generate fetches nothing).
if want t14; then
  if ! command -v npx >/dev/null 2>&1 || ! npx --no-install rulesync --version >"$WORK/rulesync-probe.log" 2>&1; then
    skip "t14: rulesync is not resolvable via npx --no-install here (see $WORK/rulesync-probe.log before this line was skipped); the regeneration check was not run"
  else
    rs_version=$(cat "$WORK/rulesync-probe.log")
    gen_log="$WORK/rulesync-generate.log"
    if ! npx --no-install rulesync generate >"$gen_log" 2>&1; then
      tail -n 30 "$gen_log" >&2
      fail "t14: npx rulesync generate failed (log kept at $gen_log)"
    fi
    check_log="$WORK/rulesync-check.log"
    if ! npx --no-install rulesync generate --check >"$check_log" 2>&1; then
      tail -n 30 "$check_log" >&2
      fail "t14: npx rulesync generate --check still reports drift (log kept at $check_log) — sources and generated output are not committed together (C04 AC3)"
    fi
    ok "t14: rulesync generate + generate --check both clean ($rs_version, offline via npx cache, C04 AC3)"

    if ! grep -qF 'dev-<service>' AGENTS.md; then
      fail "t14: the regenerated AGENTS.md has no \`dev-<service>\` MCP table row — the .rulesync/rules/overview.md row did not reach the generated surface (C04 AC4, 'keep these lists current' Hard rule)"
    fi
    ok 't14: generated AGENTS.md carries the dev-<service> fleet row (C04 AC4)'

    for src in "${AGENT_SOURCES[@]}"; do
      gen=".opencode/agents/$(basename "$src")"
      [ -f "$gen" ] || fail "t14: $gen is missing after rulesync generate"
      grep -q 'action: dev\*' "$gen" ||
        fail "t14: regenerated $gen carries no dev* allow — the regen did not land (C04 AC4 proves regen, not just the source edit)"
    done
    ok 't14: all six regenerated .opencode/agents/agent-*.md carry the dev* allow (C04 AC4)'

    dirty=$(git status --porcelain -- "${GENERATED_SURFACES[@]}")
    if [ -n "$dirty" ]; then
      printf '%s\n' "$dirty" >&2
      fail "t14: rulesync generate left generated surfaces dirty (list above) — committed output is not fresh-from-sources: dev must commit .rulesync sources AND the regenerated files together, never hand-edit the generated ones (C04 AC3)"
    fi
    ok 't14: generate left AGENTS.md + .opencode/{agents,commands,skills} byte-identical to the committed state (C04 AC3)'
  fi
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: dev-mcp-fleet checks (%d ok)\n' "$checks"
