#!/usr/bin/env bash
# Gateway API surface for git-SSH: ONE runner contract for chunks C02, C03
# and C04 of 2026-10-feat-forgejo-ssh.
#
# C02 slice (t1, t3a): the base chart's dormant gitSshPort-gated gitssh
# blocks in the k3s traefik HelmChartConfig (kubernetesGateway provider +
# experimentalChannel, ports.gitssh, gateway: listeners with the chart-
# default web listener nulled). Gate closed by default: the base chart is
# cluster-wide, so nothing gateway-related may render on any cluster until
# gitSshPort is set.
#
# C03 slice (t5, t6, t7, t8): the activation — gitSshPort: 22222 in exactly
# the dev + infra umbrella values, charts/forgejo advertising SSH_PORT
# 22222 in the inline-config Secret (subchart hardcodes 22; its auto-follow
# is dead code) while the ssh Service stays ClusterIP :22 and the subchart's
# tcpRoute attaches <fullname>-ssh to the traefik-gateway (kube-system,
# sectionName gitssh), the open-gate base renders with the REAL service
# values files, the umbrella appset values blobs carry the wiring, and the
# operator/client-migration notes land in .agents/notes/.
#
# C04 slice (t2, t3b, t4, t5b, the check_crd half of t7): the CRD carrier
# swap (user-directed follow-up, 2026-10-24) — the C02-era vendored
# tcproutes CRD template (history: charts/base/templates/gateway-tcproute-
# crd.yaml) is deleted and replaced by a PINNED chart dependency:
# gateway-api-crds 1.2.5 from https://charts.christianhuth.de (Chart.yaml +
# committed Chart.lock), base default-OFF via the condition key (GOTCHA:
# helm loads a conditioned subchart when the condition path is ABSENT — the
# default-OFF keys must exist in base values), dev/infra re-enable exactly
# the experimental tcproutes CRD (+ resource-policy keep) as static
# companion wiring next to gitSshPort. A chart dependency renders from
# STATIC values, so the gitSshPort template gate stays the single SEMANTIC
# gate for the HelmChartConfig surface only; t4 pins the separation
# (--set gitSshPort alone renders the surface but NO CRD). The rendered CRD
# must be the v1.6.3 experimental spec — pinned by sha256 (SPEC_PIN), proven
# equal from both the dependency render and the former vendored template
# render during C04 planning (2026-10-24); a renovate bump that changes the
# spec must fail t7.
#
# Contract sources: chunks/C02.md criteria 1-6 + Tests, chunks/C03.md
# criteria 1-7 + Tests, chunks/C04.md criteria 1-12 + its Tests rewrite spec
# (t2, t3b, t4, t5, t7, t8 rewritten/extended; t1, t3a, the t5 gitSshPort
# assertions, t6, t9, t10, t11 unchanged). DECISIONS.md: the port literal
# 22222 appears in value-land in exactly the two sanctioned places.
#
# LIFECYCLE (fused single-script pattern, cf. dev-forgejo-runner.sh): the
# C02/C03-era assertions are green from C02/C03 onward; the C04-era
# assertions (t2, t3b, t4, t5b, and check_crd inside t7) stay red (for the
# right reason: the vendored template still exists and the dependency is
# not pinned) until C04 lands. t11 (predecessor regressions) must be green
# whenever this script runs — C01's trail move is what keeps
# tests/services/audit-trail.sh green while the root storm-runs/ of THIS
# ticket still exists.
#
# Sentinel scoping note: the t7 dev open render passes no sentinel --sets
# (the plan's exact command), so base's ExternalSecret documents and the
# appset values blob legitimately carry OVERRIDE_VIA_CUSTOM_VALUES there
# (they resolve at deploy via customValuesUrls; t8's --set renders sweep
# them). The "no OVERRIDE_VIA_*" assertions are therefore scoped to the
# HelmChartConfig document (check_hcc) and the CRD document (check_crd) —
# the union of which is exactly what the C02/C03-era --show-only renders
# contained.
#
# The t2b renovate-annotation guard matches the repo's override-regex form
# (renovate.json): a comment line whose FIRST token is `changelog:` or
# `sourceUrl:`. An explanatory comment mentioning those words mid-sentence
# (the interface WHY-comment says "no # sourceUrl: annotation") does not
# match and is allowed.
#
# Helm discovery follows the dev-git-auth.sh convention: HELM_BIN, the
# PATH, /home/coder/.local/bin, /tmp/opencode; failing that, helm v3.21.4 is
# downloaded there. Vendored chart tarballs are not committed, so
# `helm dependency build` runs on COPIES under /tmp/opencode — the
# worktree is never written. Post-C04 the base copy's build also pulls
# gateway-api-crds per the committed Chart.lock (charts.christianhuth.de) —
# the registry-unreachable skip handling covers it. If a registry is
# unreachable, that chart's renders are skipped (not failed); the static
# checks (t1, t2, t5, t5b, t9, t10, t11) and the dev-umbrella render (no
# vendored deps) still run.
#
# The plan's umbrella Commands use --debug (manifests to stderr); this
# script captures stdout — the rendered manifests are identical.
#
# The infra umbrella render carries one OVERRIDE_NEEDED string from the
# vendored samba SUBCHART's own default values (bitwardenIds.samba-users)
# — a pre-existing third-party default, not a deploy-time sentinel of this
# ticket, so the render sweep targets OVERRIDE_VIA_* only.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/forgejo-ssh-gateway.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE="charts/base"
FORGEJO="charts/forgejo"
DEVUMB="services/dev/prod"
INFRAUMB="services/infra/prod"
DEV_VALUES="$DEVUMB/values.yaml"
INFRA_VALUES="$INFRAUMB/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
INFRA_CV="custom-values/infra/prod-values.yaml"
TCFG="$BASE/templates/traefik-config.yaml"
CRD_TPL="$BASE/templates/gateway-tcproute-crd.yaml"
NOTES=".agents/notes/2026-10-23-forgejo-git-ssh.md"
# The C04 CRD identity pin: sha256 of the canonicalized (json.dumps
# sort_keys) spec of the rendered tcproutes CRD. Proven equal during C04
# planning (2026-10-24) from BOTH the gateway-api-crds dependency render
# and the former vendored template render — i.e. the v1.6.3 experimental
# spec. A renovate bump of the dependency that changes the CRD spec must
# fail check_crd.
CRD_NAME="tcproutes.gateway.networking.k8s.io"
SPEC_PIN="c29ee86ea554c32b83ca8ab6b07651a99e8d72345088f6b4f829b44ad700947e"

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
  # falls through and concatenates a second path into $helm_bin (FRICTION
  # from the predecessor ticket's find_helm bug).
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
  dir=/tmp/opencode/forgejo-ssh-gateway-helm-download
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

WORK=$(mktemp -d /tmp/opencode/forgejo-ssh-gateway.XXXXXX)

# Copy a chart path into WORK and helm-dependency-build it there. Prints the
# copy path on success. On a registry-unreachable failure writes
# $WORK/<id>-skip and prints a skip note (those renders are skipped, not
# failed — an environment problem). On any other build failure writes
# $WORK/<id>-fail; the caller fails the run (a broken dependency build is a
# real defect, not an environment problem). The flag files stand in for
# variables: $(...) runs in a subshell, so an exit inside it would not
# propagate to the parent.
build_copy() {
  local chart="$1" id="$2"
  local copy="$WORK/$(printf '%s' "$chart" | tr '/' '_')"
  cp -R "$chart"/. "$copy"/
  local log="$copy/dependency-build.log"
  if ! (cd "$copy" && "$helm_bin" dependency build .) >"$log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$log"; then
      : >"$WORK/$id-skip"
      printf 'skip: setup: helm dependency build could not reach the registry for %s here; its renders were not run (log kept at %s)\n' "$chart" "$log" >&2
      return 0
    fi
    : >"$WORK/$id-fail"
    return 1
  fi
  printf '%s' "$copy"
}

base_copy="" fj_copy="" infra_copy=""

if [ -z "$helm_bin" ]; then
  skip "setup: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; the helm-dependent renders below were not run (the static checks still run)"
else
  base_copy=$(build_copy "$BASE" base || true)
  fj_copy=$(build_copy "$FORGEJO" fj || true)
  infra_copy=$(build_copy "$INFRAUMB" infra || true)
  if [ -f "$WORK/base-fail" ]; then
    tail -n 30 "$WORK/charts_base/dependency-build.log" >&2
    fail "setup: helm dependency build failed for $BASE (log kept at $WORK/charts_base/dependency-build.log)"
  fi
  if [ -f "$WORK/fj-fail" ]; then
    tail -n 30 "$WORK/charts_forgejo/dependency-build.log" >&2
    fail "setup: helm dependency build failed for $FORGEJO (log kept at $WORK/charts_forgejo/dependency-build.log)"
  fi
  if [ -f "$WORK/infra-fail" ]; then
    tail -n 30 "$WORK/services_infra_prod/dependency-build.log" >&2
    fail "setup: helm dependency build failed for $INFRAUMB (log kept at $WORK/services_infra_prod/dependency-build.log)"
  fi
  if [ -f "$WORK/base-skip" ] || [ -f "$WORK/fj-skip" ] || [ -f "$WORK/infra-skip" ]; then
    skip "setup: dependency builds only partially reachable (base: ${base_copy:+yes}, forgejo: ${fj_copy:+yes}, infra umbrella: ${infra_copy:+yes}); the dependent renders below are skipped individually"
  else
    ok "setup: helm dependency build succeeds for $BASE, $FORGEJO and $INFRAUMB on copies ($("$helm_bin" version --short 2>/dev/null || echo helm))"
  fi
fi

# --- t1: the gitSshPort-gated interface blocks in traefik-config.yaml ------
# (C02 t1 — structural: every interface element must sit INSIDE a
# gitSshPort conditional, not merely exist as a string.)
# The gate conditional C02 must add, in either accepted spelling (the
# interface shows the index form, matching the seaweedVolumePort precedent;
# the dot form is semantically identical for this integer value).
#
# t1 uses two rules, because some target lines are shared with pre-existing
# blocks: `protocol: TCP` at 8 spaces also belongs to the seaweedvolume
# block (a different gate). Elements that NAME the new surface (gitssh,
# kubernetesGateway, gateway, the gitSshPort port expressions) must appear
# EXCLUSIVELY inside a gitSshPort conditional; shared-value lines (protocol:
# TCP, enabled: true) only need one occurrence inside one.

if [ ! -f "$TCFG" ]; then
  fail "t1: $TCFG is missing (C02 has not added the gitssh surface — nothing to gate)"
fi
if python3 - "$TCFG" "$WORK/t1-count" <<'PY'
import re, sys

path, count_file = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

IF_RE = re.compile(r'\{\{-?\s*if\s+(.+?)\s*-?\}\}')
RANGE_RE = re.compile(r'\{\{-?\s*range\b')
END_RE = re.compile(r'\{\{-?\s*end\s*-?\}\}')
GATE_RE = re.compile(r'(?:index\s+\.Values\s+"gitSshPort"|\.Values\.gitSshPort)')
PORT_EXPR = r'\{\{-?\s*(?:index \.Values "gitSshPort"|\.Values\.gitSshPort)\s*-?\}\}'

# Indents are the valuesContent block-scalar layout of this file: 4 spaces
# for top-level keys (ports:, providers:, entryPoints:), +2 per level below.
# (label, regex, exclusive) — exclusive elements must not appear at all
# outside the gate; present elements only need one in-gate occurrence.
targets = [
    ('providers.kubernetesGateway block', re.compile(r'^ {6}kubernetesGateway:\s*$'), True),
    ('kubernetesGateway.enabled: true', re.compile(r'^ {8}enabled:\s*true\s*$'), False),
    ('kubernetesGateway.experimentalChannel: true', re.compile(r'^ {8}experimentalChannel:\s*true\s*$'), True),
    ('ports.gitssh block', re.compile(r'^ {6}gitssh:\s*$'), True),
    ('ports.gitssh port (gitSshPort expr)', re.compile(rf'^ {{8}}port:\s*{PORT_EXPR}\s*$'), True),
    ('ports.gitssh exposedPort (gitSshPort expr)', re.compile(rf'^ {{8}}exposedPort:\s*{PORT_EXPR}\s*$'), True),
    ('ports.gitssh protocol: TCP', re.compile(r'^ {8}protocol:\s*TCP\s*$'), False),
    ('gateway: top-level key', re.compile(r'^ {4}gateway:\s*$'), True),
    ('gateway.listeners.web nulled', re.compile(r'^ {8}web:\s*(?:null|~)\s*$'), True),
    ('gateway.listeners.gitssh block', re.compile(r'^ {8}gitssh:\s*$'), True),
    ('listener gitssh port (gitSshPort expr)', re.compile(rf'^ {{10}}port:\s*{PORT_EXPR}\s*$'), True),
    ('listener gitssh protocol: TCP', re.compile(r'^ {10}protocol:\s*TCP\s*$'), False),
    ('listener namespacePolicy', re.compile(r'^ {10}namespacePolicy:\s*$'), True),
    ('listener namespacePolicy from: All', re.compile(r'^ {12}from:\s*All\s*$'), True),
]

# Walk the template with an if/range stack so each line knows whether it
# sits inside a gitSshPort conditional.
frames = []          # active directive conditions; None marks a range frame
gate_directives = 0
in_gate_count = {label: 0 for label, _, _ in targets}
total_count = {label: 0 for label, _, _ in targets}
bad_lines = {label: [] for label, _, _ in targets}
for lineno, line in enumerate(lines, 1):
    in_gate = any(cond is not None and GATE_RE.search(cond) for cond in frames)
    m = IF_RE.search(line)
    is_range = bool(RANGE_RE.search(line)) and not m
    for label, rx, _ in targets:
        if rx.match(line):
            total_count[label] += 1
            if in_gate:
                in_gate_count[label] += 1
            else:
                bad_lines[label].append(lineno)
    if m or is_range:
        frames.append(m.group(1) if m else None)
        if m and GATE_RE.search(m.group(1)):
            gate_directives += 1
    if END_RE.search(line):
        if frames:
            frames.pop()

if gate_directives == 0:
    bad(f't1: no Go-template conditional on gitSshPort found in {path} (C02 has not added the gate — the gitssh surface is not dormant-by-default)')

for label, rx, exclusive in targets:
    if in_gate_count[label] == 0:
        bad(f't1: {label} not found inside any gitSshPort conditional in {path} (the element of the C02 interface is missing or ungated)')
    if exclusive and bad_lines[label]:
        bad(f't1: {label} also occurs OUTSIDE the gitSshPort conditional (lines {bad_lines[label]}) — it would render on every base-managed cluster; the gate must enclose every occurrence')
ok(f't1: all three gitSshPort interface blocks (kubernetesGateway provider, ports.gitssh, gateway.listeners) exist inside the gitSshPort conditional in {path}')

# The gitssh entrypoint is chart-derived from ports.*; the pre-existing
# (chart-ignored) entryPoints: block must NOT gain a gitssh key.
in_entry = False
for lineno, line in enumerate(lines, 1):
    if re.match(r'^ {4}entryPoints:\s*$', line):
        in_entry = True
        continue
    if in_entry:
        if re.match(r'^ {4}\S', line):
            in_entry = False
        elif 'gitssh' in line:
            bad(f't1: entryPoints: block (line {lineno}) gained a gitssh entry — the chart derives the entrypoint from ports.*; the entryPoints block is chart-ignored dead weight (C02 interface)')
ok('t1: the entryPoints: block was left alone (no gitssh key added)')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t1-count")))
else
  exit 1
fi

# --- t2: the pinned gateway-api-crds dependency (C04 criteria 1-4) ---------
# (supersedes the C02 vendored-template structure check; t7/check_crd
# re-proves the CRD on the rendered document.)
# t2a: the vendored template is deleted, and the filename is referenced
# nowhere outside this ticket's plan artifacts + this script's history.
if [ -e "$CRD_TPL" ]; then
  fail "t2: $CRD_TPL still exists (C04 deletes the vendored CRD template — the CRD is now a pinned chart dependency)"
fi
ok "t2: the vendored CRD template is deleted"
if python3 - "$WORK/t2-count" <<'PY'
import subprocess, sys

count_file = sys.argv[1]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

r = subprocess.run(['git', 'grep', '-n', 'gateway-tcproute-crd'], capture_output=True, text=True)
stray = []
for line in r.stdout.splitlines():
    p = line.split(':', 1)[0]
    # this ticket's plan artifacts + this script's history comment are the
    # sanctioned remaining references (C04 criterion 2)
    if p.startswith('.agents/plans/2026/2026-10-feat-forgejo-ssh/') or p == 'tests/services/forgejo-ssh-gateway.sh':
        continue
    stray.append(line)
if stray:
    bad('t2: the deleted template name is still referenced outside the plan artifacts + this test\'s history (C04 criterion 2):\n' + '\n'.join(stray))
ok('t2: no remaining reference to the vendored template filename (except plan artifacts + this script\'s history)')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t2-count")))
else
  exit 1
fi
# t2b: the Chart.yaml dependency is exactly the interface triple + condition,
# https repo (renovate-trackable, not oci://), no renovate override annotation.
if python3 - "$BASE/Chart.yaml" "$WORK/t2b-count" <<'PY'
import re, sys, yaml

path, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t2: {path} could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

raw = open(path).read()
chart = yaml.safe_load(raw)
deps = [d for d in (chart.get('dependencies') or []) if isinstance(d, dict)]
by_name = {d.get('name'): d for d in deps}
for keep in ('argo-cd', 'cert-manager'):
    if keep not in by_name:
        bad(f't2: Chart.yaml no longer lists the {keep!r} dependency (C04 adds gateway-api-crds alongside the existing dependencies)')
entry = by_name.get('gateway-api-crds')
if entry is None:
    bad('t2: Chart.yaml has no gateway-api-crds dependency (C04 must pin the experimental-channel tcproutes CRD as a chart dependency)')
expected = {'name': 'gateway-api-crds', 'version': '1.2.5', 'repository': 'https://charts.christianhuth.de', 'condition': 'gateway-api-crds.enabled'}
if entry != expected:
    bad(f't2: the gateway-api-crds dependency entry is {entry!r}, expected exactly {expected!r} (the pinned triple + the condition key that keeps the subchart off by default)')
ok('t2: Chart.yaml pins gateway-api-crds 1.2.5 from https://charts.christianhuth.de with condition gateway-api-crds.enabled (exactly the interface entry)')

# renovate.json's override regex extracts an annotation only when a comment
# line's FIRST token is `changelog:` or `sourceUrl:` (the built-in helmv3
# manager already tracks HTTP-repo Chart.yaml deps — an annotation would
# double-extract the dependency). An explanatory comment mentioning those
# words mid-sentence does not match.
lines = raw.splitlines()
idx = None
for i, l in enumerate(lines):
    if re.match(r'^- name: gateway-api-crds\s*$', l):
        idx = i
        break
if idx is None:
    bad('t2: the - name: gateway-api-crds line was not found in the raw Chart.yaml (the entry layout differs from the interface block)')
start = idx
while start > 0 and lines[start - 1].lstrip().startswith('#'):
    start -= 1
end = start
while end + 1 < len(lines) and lines[end + 1][:1] in (' ', '\t', '#'):
    end += 1
ann = [l.strip() for l in lines[start:end + 1] if re.match(r'^\s*#\s*(?:changelog|sourceUrl):', l)]
if ann:
    bad(f't2: the gateway-api-crds entry carries a renovate annotation-form comment {ann!r} (renovate.json\'s override regex would double-extract the dependency)')
ok('t2: no # sourceUrl: / # changelog: annotation attached to the gateway-api-crds entry')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t2b-count")))
else
  exit 1
fi
# t2c: the lock is committed, carries the entry, and a sha256 digest.
# (Lock/Chart.yaml sync itself is proven by the setup dependency build — a
# stale lock fails it.)
if python3 - "$BASE/Chart.lock" "$WORK/t2c-count" <<'PY'
import re, subprocess, sys, yaml

path, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t2: {path} could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

r = subprocess.run(['git', 'ls-files', '--error-unmatch', path], capture_output=True, text=True)
if r.returncode != 0:
    bad(f't2: {path} is not tracked in git (the regenerated Chart.lock must be committed together with Chart.yaml)')
ok('t2: Chart.lock is committed')

lock = yaml.safe_load(open(path).read())
deps = {d.get('name'): d for d in (lock.get('dependencies') or []) if isinstance(d, dict)}
e = deps.get('gateway-api-crds')
if e is None:
    bad('t2: Chart.lock has no gateway-api-crds entry (the lock was not regenerated after the Chart.yaml change)')
if e.get('version') != '1.2.5' or e.get('repository') != 'https://charts.christianhuth.de':
    bad(f't2: the Chart.lock gateway-api-crds entry is {e!r}, expected version 1.2.5 + repository https://charts.christianhuth.de')
ok('t2: Chart.lock carries the gateway-api-crds entry (1.2.5, https://charts.christianhuth.de)')

# This repo's lock format pins the dependency set with a top-level
# `digest: sha256:...` (see the pre-change argo-cd/cert-manager entries);
# accept a per-entry sha256 too in case a helm version writes one.
sha = e.get('sha256') or lock.get('digest')
if not (isinstance(sha, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', sha)):
    bad(f't2: Chart.lock carries no sha256 digest (entry sha256={e.get("sha256")!r}, lock digest={lock.get("digest")!r})')
ok('t2: Chart.lock carries a sha256 digest pinning the dependency set')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t2c-count")))
else
  exit 1
fi
# t2d: base default values carry the default-OFF condition keys (the
# condition-key gotcha — an ABSENT path makes helm load the subchart).
if python3 - "$BASE/values.yaml" "$WORK/t2d-count" <<'PY'
import re, sys, yaml

path, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t2: {path} could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

def load(p):
    # REDEFINED anchors are legal YAML (helm/Go accept them; PyYAML raises
    # ComposerError) — only markers in value position are rewritten.
    lines = []
    with open(p) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

g = load(path).get('gateway-api-crds')
if not isinstance(g, dict):
    bad('t2: base values have no gateway-api-crds: block — the condition-key gotcha: helm loads a conditioned subchart when the condition path is ABSENT, so the default-OFF keys must exist here or every base-managed cluster gets the chart\'s default CRD bundle')
if g.get('enabled') is not False:
    bad(f't2: base values gateway-api-crds.enabled is {g.get("enabled")!r}, expected false (default OFF on every cluster)')
if (g.get('standard') or {}).get('enabled') is not False:
    bad(f't2: base values gateway-api-crds.standard.enabled is {(g.get("standard") or {}).get("enabled")!r}, expected false')
if (g.get('experimental') or {}).get('enabled') is not False:
    bad(f't2: base values gateway-api-crds.experimental.enabled is {(g.get("experimental") or {}).get("enabled")!r}, expected false (the dev/infra service values re-enable exactly the tcproutes CRD)')
ok('t2: base default values carry the default-OFF gateway-api-crds block (enabled / standard.enabled / experimental.enabled all false)')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t2d-count")))
else
  exit 1
fi

# --- t3: gate CLOSED — the dormant default (C02 c2, C04 c5) ---------------
# (a) the closed-gate valuesContent carries none of the gitssh surface AND
#     is BYTE-IDENTICAL to the pre-change render, anchored to main's
#     template (the pre-change tree at this ticket's start; after merge the
#     anchor equals the new template and the diff is trivially empty). The
#     C04 comment fix inside the gate cannot change the closed render.
# (b) the FULL closed-gate render carries zero gateway.networking.k8s.io
#     CRDs (replaces the C02 --show-only check — the vendored template is
#     deleted in C04; the default-OFF condition keys are load-bearing).
if [ -z "$helm_bin" ] || [ -z "$base_copy" ]; then
  skip "t3: closed-gate render not run (no helm or base dependency build)"
else
  closed_out="$WORK/closed-render.yaml"
  if ! "$helm_bin" template base "$base_copy" --set serviceName=dev \
      --show-only templates/traefik-config.yaml >"$closed_out" 2>"$WORK/closed-render.err"; then
    tail -n 30 "$WORK/closed-render.err" >&2
    fail "t3: helm template of $BASE (gate closed) failed (log kept at $WORK/closed-render.err)"
  fi
  if python3 - "$closed_out" <<'PY'
import sys, yaml

text = open(sys.argv[1]).read()

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t3: the closed-gate render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

docs = [d for d in yaml.safe_load_all(text) if d]
hcc = [d for d in docs if d.get('kind') == 'HelmChartConfig' and (d.get('metadata') or {}).get('name') == 'traefik']
if not hcc:
    print('FAIL: t3: no HelmChartConfig named traefik in the closed-gate render', file=sys.stderr)
    sys.exit(1)
vc_raw = (hcc[0].get('spec') or {}).get('valuesContent') or ''
for needle, why in (
    ('kubernetesGateway', 'the Gateway provider would come up on a cluster without gitSshPort'),
    ('gitssh', 'the gitssh port/listener surface would render on a cluster without gitSshPort'),
):
    if needle in vc_raw:
        print(f'FAIL: t3: the closed-gate valuesContent still contains {needle!r} ({why})', file=sys.stderr)
        sys.exit(1)
vc = yaml.safe_load(vc_raw)
if not isinstance(vc, dict):
    print('FAIL: t3: the closed-gate valuesContent does not parse as a YAML mapping (the C02 edit broke the block scalar)', file=sys.stderr)
    sys.exit(1)
if 'gateway' in vc:
    print('FAIL: t3: the closed-gate valuesContent has a gateway: key (the lab Gateway must not render on clusters without gitSshPort)', file=sys.stderr)
    sys.exit(1)
print('ok: t3: closed-gate valuesContent carries no kubernetesGateway/gitssh/gateway surface and still parses')
PY
  then
    checks=$((checks + 1))
  else
    exit 1
  fi

  main_tcfg="$WORK/main-traefik-config.yaml"
  if ! git show main:"$TCFG" >"$main_tcfg" 2>"$WORK/main-show.err"; then
    fail "t3: cannot read the pre-change template via git show main:$TCFG (the byte-identity anchor is missing — $(head -n 1 "$WORK/main-show.err" 2>/dev/null))"
  fi
  main_copy="$WORK/base-main-copy"
  cp -R "$base_copy/." "$main_copy/"
  cp "$main_tcfg" "$main_copy/templates/traefik-config.yaml"
  rm -f "$main_copy/templates/gateway-tcproute-crd.yaml"
  main_out="$WORK/closed-render-main.yaml"
  if ! "$helm_bin" template base "$main_copy" --set serviceName=dev \
      --show-only templates/traefik-config.yaml >"$main_out" 2>"$WORK/closed-render-main.err"; then
    tail -n 30 "$WORK/closed-render-main.err" >&2
    fail "t3: render of the pre-change (main) template failed (log kept at $WORK/closed-render-main.err)"
  fi
  if ! diff -u "$main_out" "$closed_out" >"$WORK/closed-diff.txt"; then
    head -n 40 "$WORK/closed-diff.txt" >&2
    fail "t3: the closed-gate render is NOT byte-identical to the pre-change (main) render — the gitSshPort gate leaked output into the default (C02 criterion 2)"
  fi
  ok "t3: closed-gate HelmChartConfig render is byte-identical to the pre-change (main) render"

  full_out="$WORK/closed-full-render.yaml"
  if ! "$helm_bin" template base "$base_copy" --set serviceName=dev \
      >"$full_out" 2>"$WORK/closed-full.err"; then
    tail -n 30 "$WORK/closed-full.err" >&2
    fail "t3: full closed-gate render of $BASE failed (log kept at $WORK/closed-full.err)"
  fi
  if python3 - "$full_out" <<'PY'
import sys, yaml

render = sys.argv[1]
docs = [d for d in yaml.safe_load_all(open(render)) if d]
gw = [d for d in docs if d.get('kind') == 'CustomResourceDefinition'
      and str((d.get('metadata') or {}).get('name', '')).endswith('.gateway.networking.k8s.io')]
if gw:
    print(f"FAIL: t3: the closed-gate render carries {len(gw)} gateway.networking.k8s.io CRD(s) {[ (d.get('metadata') or {}).get('name') for d in gw ]} — the default-OFF condition keys are load-bearing: without them helm installs the chart's default CRD bundle on every base-managed cluster", file=sys.stderr)
    sys.exit(1)
print('ok: t3: the closed-gate full render carries zero gateway.networking.k8s.io CRDs (the condition default-off skips the dependency everywhere)')
PY
  then
    checks=$((checks + 1))
  else
    exit 1
  fi
fi

# check_hcc — the gitssh HelmChartConfig surface of an open-gate base
# render. $1 = render file, $2 = tag. (All valuesContent assertions are
# unchanged from the C02/C03 era; the OVERRIDE_VIA_* scan is scoped to the
# HelmChartConfig document — see the header's sentinel-scoping note.)
check_hcc() {
  local out="$1" tag="$2"
  python3 - "$out" "$tag" "$WORK/$tag-hcc-count" <<'PY'
import sys, yaml

render, tag, count_file = sys.argv[1:4]
text = open(render).read()
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: {tag}: the open-gate render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

docs = [d for d in yaml.safe_load_all(text) if d]
hcc = [d for d in docs if d.get('kind') == 'HelmChartConfig' and (d.get('metadata') or {}).get('name') == 'traefik']
if not hcc:
    bad(f'{tag}: no HelmChartConfig named traefik in the render')

try:
    vc = yaml.safe_load((hcc[0].get('spec') or {}).get('valuesContent') or '')
except yaml.YAMLError as e:
    bad(f'{tag}: the open-gate valuesContent does not parse as YAML ({e})')
if not isinstance(vc, dict):
    bad(f'{tag}: the open-gate valuesContent is not a mapping')

kg = (vc.get('providers') or {}).get('kubernetesGateway')
if not isinstance(kg, dict) or kg.get('enabled') is not True or kg.get('experimentalChannel') is not True:
    bad(f'{tag}: providers.kubernetesGateway is {kg!r}, expected enabled: true + experimentalChannel: true (traefik 3.7 gates TCPRoute behind experimentalChannel)')
ok(f'{tag}: providers.kubernetesGateway {{"enabled": true, "experimentalChannel": true}}')

pg = (vc.get('ports') or {}).get('gitssh')
if not isinstance(pg, dict):
    bad(f'{tag}: ports.gitssh missing from the open-gate valuesContent')
if pg.get('port') != 22222:
    bad(f"{tag}: ports.gitssh.port is {pg.get('port')!r}, expected 22222")
if pg.get('exposedPort') != 22222:
    bad(f"{tag}: ports.gitssh.exposedPort is {pg.get('exposedPort')!r}, expected 22222")
if pg.get('protocol') != 'TCP':
    bad(f"{tag}: ports.gitssh.protocol is {pg.get('protocol')!r}, expected TCP")
if (pg.get('expose') or {}).get('default') is not True:
    bad(f"{tag}: ports.gitssh.expose.default is {(pg.get('expose') or {}).get('default')!r}, expected true (the chart exposes it as a ServiceLB hostPort)")
ok(f'{tag}: ports.gitssh exposes 22222 TCP (port + exposedPort)')

gw = vc.get('gateway')
if not isinstance(gw, dict):
    bad(f'{tag}: no gateway: key in the open-gate valuesContent (the k3s chart would not render the lab Gateway)')
ls = (gw.get('listeners') or {})
if ls.get('web') is not None:
    bad(f"{tag}: gateway.listeners.web is {ls.get('web')!r}, expected null (the chart-default web listener must be removed so the lab Gateway carries ONLY the git-SSH listener)")
lg = ls.get('gitssh')
if not isinstance(lg, dict) or lg.get('port') != 22222 or lg.get('protocol') != 'TCP':
    bad(f'{tag}: gateway.listeners.gitssh is {lg!r}, expected port 22222 + protocol TCP')
if ((lg.get('namespacePolicy') or {}).get('from')) != 'All':
    bad(f"{tag}: gateway.listeners.gitssh.namespacePolicy.from is {((lg.get('namespacePolicy') or {}).get('from'))!r}, expected All (the TCPRoutes live in default next to the forgejo Services while the Gateway lands in kube-system)")
ok(f'{tag}: gateway.listeners — web nulled, gitssh 22222/TCP with namespacePolicy.from All')

hcc_text = yaml.safe_dump(hcc[0])
if 'OVERRIDE_VIA_' in hcc_text:
    bad(f'{tag}: the HelmChartConfig document still carries an OVERRIDE_VIA_* sentinel')
ok(f'{tag}: no OVERRIDE_VIA_* sentinel in the HelmChartConfig document')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
}

# check_crd — the rendered CRD of an open-gate base render (C04): exactly
# ONE tcproutes CRD from the gateway-api-crds dependency (and no other
# gateway.networking.k8s.io CRDs — the tcproutes-only scoping), channel
# experimental, bundle v1.6.3, v1 (served+storage) + v1alpha2 (served,
# deprecated), the resource-policy keep annotation, and the spec identity
# pin (SPEC_PIN). $1 = render file, $2 = tag.
check_crd() {
  local out="$1" tag="$2"
  python3 - "$out" "$tag" "$SPEC_PIN" "$WORK/$tag-crd-count" <<'PY'
import hashlib, json, sys, yaml

render, tag, spec_pin, count_file = sys.argv[1:5]
crd_name = 'tcproutes.gateway.networking.k8s.io'
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: {tag}: the open-gate render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

docs = [d for d in yaml.safe_load_all(open(render)) if d]
crds = [d for d in docs if d.get('kind') == 'CustomResourceDefinition']
tc = [d for d in crds if (d.get('metadata') or {}).get('name') == crd_name]
other_gw = [d for d in crds if (d.get('metadata') or {}).get('name') != crd_name
            and str((d.get('metadata') or {}).get('name', '')).endswith('.gateway.networking.k8s.io')]
if other_gw:
    bad(f'{tag}: the render carries extra gateway.networking.k8s.io CRDs {[ (d.get("metadata") or {}).get("name") for d in other_gw ]} — the dependency must stay scoped to tcproutes only (the ownership overlap with k3s traefik-crd stays at exactly 1 CRD)')
if len(tc) != 1:
    bad(f'{tag}: expected exactly one {crd_name} CRD, found {len(tc)} (the static enable values must render it via the gateway-api-crds dependency)')
crd = tc[0]
md = crd.get('metadata') or {}
ann = md.get('annotations') or {}
if ann.get('gateway.networking.k8s.io/channel') != 'experimental':
    bad(f"{tag}: CRD channel annotation is {ann.get('gateway.networking.k8s.io/channel')!r}, expected experimental (the standard channel does not serve v1alpha2 — the plan's RESEARCH correction)")
if ann.get('gateway.networking.k8s.io/bundle-version') != 'v1.6.3':
    bad(f"{tag}: CRD bundle-version annotation is {ann.get('gateway.networking.k8s.io/bundle-version')!r}, expected v1.6.3")
ok(f'{tag}: CRD channel experimental + bundle-version v1.6.3')

vers = {v.get('name'): v for v in (crd.get('spec') or {}).get('versions', [])}
if not (vers.get('v1', {}).get('served') is True and vers.get('v1', {}).get('storage') is True):
    bad(f"{tag}: CRD v1 version must be served+storage, got {vers.get('v1')!r}")
v2 = vers.get('v1alpha2', {})
if v2.get('served') is not True:
    bad(f"{tag}: CRD v1alpha2 version must be served (traefik 3.7's TCPRoute client is pinned to v1alpha2), got {v2!r}")
if v2.get('deprecated') is not True:
    bad(f"{tag}: CRD v1alpha2 version must be deprecated (C04 criterion 7), got {v2!r}")
ok(f'{tag}: CRD v1 (served+storage) + v1alpha2 (served, deprecated)')

if ann.get('helm.sh/resource-policy') != 'keep':
    bad(f'{tag}: the CRD lacks helm.sh/resource-policy: keep (a base-release uninstall must not cascade-delete a CRD k3s also owns — C04 criterion 7)')
ok(f'{tag}: CRD carries helm.sh/resource-policy: keep')

doc_text = yaml.safe_dump(crd)
if 'OVERRIDE_VIA_' in doc_text:
    bad(f'{tag}: the CRD document carries an OVERRIDE_VIA_* sentinel')
ok(f'{tag}: no OVERRIDE_VIA_* sentinel in the CRD document')

# SPEC_PIN provenance: the v1.6.3 experimental spec, verified during C04
# planning (2026-10-24) to hash equally from BOTH the dependency render and
# the former vendored template render.
pin = hashlib.sha256(json.dumps(crd.get('spec') or {}, sort_keys=True).encode()).hexdigest()
if pin != spec_pin:
    bad(f'{tag}: the rendered CRD spec sha256 is {pin}, expected the v1.6.3 experimental pin {spec_pin} (the CRD spec changed — a dependency bump must not silently change what the lab applies)')
ok(f'{tag}: the rendered CRD spec matches the v1.6.3 experimental identity pin')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
}

# --- t4: gate separation — gitSshPort opens the surface, never the CRD ---
# (C04 c6: the CRD is driven by the STATIC gateway-api-crds enable values,
# never by the template gate. This render — gate via --set only, default
# values, no service values file — pins the separation against re-coupling:
# check_hcc must pass AND zero gateway.networking.k8s.io CRDs.)
if [ -z "$helm_bin" ] || [ -z "$base_copy" ]; then
  skip "t4: gate-separation render not run (no helm or base dependency build)"
else
  t4_out="$WORK/gate-only-render.yaml"
  if ! "$helm_bin" template base "$base_copy" --set serviceName=dev --set gitSshPort=22222 \
      >"$t4_out" 2>"$WORK/gate-only.err"; then
    tail -n 30 "$WORK/gate-only.err" >&2
    fail "t4: gate-only render of $BASE failed (log kept at $WORK/gate-only.err)"
  fi
  if check_hcc "$t4_out" t4; then
    checks=$((checks + $(cat "$WORK/t4-hcc-count")))
  else
    exit 1
  fi
  if python3 - "$t4_out" t4 <<'PY'
import sys, yaml

render, tag = sys.argv[1], sys.argv[2]
docs = [d for d in yaml.safe_load_all(open(render)) if d]
gw = [d for d in docs if d.get('kind') == 'CustomResourceDefinition'
      and str((d.get('metadata') or {}).get('name', '')).endswith('.gateway.networking.k8s.io')]
if gw:
    print(f"FAIL: {tag}: --set gitSshPort alone rendered {len(gw)} gateway CRD(s) {[ (d.get('metadata') or {}).get('name') for d in gw ]} — the CRD must be driven by the static gateway-api-crds enable values, never by the template gate (the design got re-coupled)", file=sys.stderr)
    sys.exit(1)
print(f'ok: {tag}: gate separation — gitSshPort opens the HelmChartConfig surface but renders zero gateway CRDs')
PY
  then
    checks=$((checks + 1))
  else
    exit 1
  fi
fi

# --- t5: gitSshPort: 22222 in exactly the two umbrella values (C03 c1) ----
if python3 - "$DEV_VALUES" "$INFRA_VALUES" "$WORK/t5-count" <<'PY'
import re, subprocess, sys

dev_vals, infra_vals, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

for path in (dev_vals, infra_vals):
    text = open(path).read()
    hits = [l for l in text.splitlines() if re.match(r'\s*gitSshPort:', l)]
    if len(hits) != 1:
        bad(f't5: {path} has {len(hits)} gitSshPort lines, expected exactly one (the gate key must be set exactly once)')
    if not re.match(r'\s*gitSshPort:\s*22222\s*(#.*)?$', hits[0]):
        bad(f't5: {path} gitSshPort line is {hits[0]!r}, expected `gitSshPort: 22222` (DECISIONS: the two port literals must stay equal)')
    ok(f't5: {path} carries gitSshPort: 22222 exactly once')

r = subprocess.run(['git', 'grep', '-n', 'gitSshPort', '--', 'services', 'custom-values'],
                   capture_output=True, text=True)
allowed = {dev_vals, infra_vals}
for line in r.stdout.splitlines():
    path = line.split(':', 1)[0]
    if path not in allowed:
        bad(f't5: gitSshPort appears outside the dev/infra umbrella values: {line} (other clusters must stay untouched — only these two umbrellas may carry the gate)')
ok('t5: no other service values or custom-values file carries gitSshPort (repo-wide)')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t5-count")))
else
  exit 1
fi

# --- t5b: the static gateway-api-crds companion wiring (C04 criterion 7, 9)
# (a) the enable blocks parse to the interface shape, (b) no other
# service/custom-values file mentions gateway-api-crds, (c) the block sits
# directly after gitSshPort with a comment naming it (the pair moves together).
if python3 - "$DEV_VALUES" "$INFRA_VALUES" "$WORK/t5b-count" <<'PY'
import re, subprocess, sys, yaml

dev_vals, infra_vals, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t5: the companion-wiring checks could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

def load(p):
    # REDEFINED anchors are legal YAML (helm/Go accept them; PyYAML raises
    # ComposerError) — only markers in value position are rewritten.
    lines = []
    with open(p) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

# The 13 experimental.crds.* toggles the Interface lists off (tcproutes is
# the 14th — it stays at the chart default true).
CRD_TOGGLES = ('backendtlspolicies', 'gatewayclasses', 'gateways', 'grpcroutes',
               'httproutes', 'listenersets', 'referencegrants', 'tlsroutes',
               'udproutes', 'xbackends', 'xbackendtrafficpolicies',
               'xlistenersets', 'xmeshes')

def check_enable(label, values):
    g = values.get('gateway-api-crds')
    if not isinstance(g, dict):
        bad(f't5: {label} has no gateway-api-crds: block (the C04 companion wiring for gitSshPort is missing)')
    if g.get('enabled') is not True:
        bad(f"t5: {label} gateway-api-crds.enabled is {g.get('enabled')!r}, expected true")
    if (g.get('standard') or {}).get('enabled') is not False:
        bad(f"t5: {label} gateway-api-crds.standard.enabled is {(g.get('standard') or {}).get('enabled')!r}, expected false (only the experimental channel serves v1alpha2)")
    exp = g.get('experimental') or {}
    if exp.get('enabled') is not True:
        bad(f"t5: {label} gateway-api-crds.experimental.enabled is {exp.get('enabled')!r}, expected true")
    crds = exp.get('crds') or {}
    for name in CRD_TOGGLES:
        if crds.get(name) is not False:
            bad(f"t5: {label} gateway-api-crds.experimental.crds.{name} is {crds.get(name)!r}, expected false (tcproutes-only scoping keeps the k3s ownership overlap at exactly 1 CRD)")
    if 'tcproutes' in crds and crds['tcproutes'] is not True:
        bad(f"t5: {label} gateway-api-crds.experimental.crds.tcproutes is {crds['tcproutes']!r}, expected true (or absent — the chart default)")
    if (((g.get('global') or {}).get('resourcePolicy') or {}).get('keep')) is not True:
        bad(f"t5: {label} gateway-api-crds.global.resourcePolicy.keep is not true (a base-release uninstall must not cascade-delete a CRD k3s also owns)")
    ok(f't5: {label} enable block — experimental tcproutes only (13 other toggles off), standard off, resource-policy keep')

def check_adjacency(label, text):
    lines = text.splitlines()
    gi = None
    for i, l in enumerate(lines):
        if re.match(r'^gitSshPort:', l):
            gi = i
            break
    if gi is None:
        bad(f't5: {label} has no top-level gitSshPort: line (the t5 gitSshPort assertions above cover this — reaching here means a layout the walker cannot see)')
        return
    # next top-level key after gitSshPort (skipping blanks + comments)
    ai = None
    for j in range(gi + 1, len(lines)):
        l = lines[j]
        if not l.strip() or l.lstrip().startswith('#'):
            continue
        ai = j
        break
    if ai is None or not re.match(r'^gateway-api-crds:', lines[ai]):
        next_key = repr(lines[ai]) if ai is not None else 'EOF'
        bad(f't5: {label}: the next top-level key after gitSshPort: is {next_key}, expected gateway-api-crds: directly after (no other top-level key may sit between the pair)')
    # the comment block directly above gateway-api-crds: must name gitSshPort
    block = []
    k = ai - 1
    while k >= 0 and (not lines[k].strip() or lines[k].lstrip().startswith('#')):
        block.append(lines[k])
        k -= 1
    if 'gitSshPort' not in '\n'.join(block):
        bad(f't5: {label}: the comment above gateway-api-crds: does not name gitSshPort (the pair must be documented as moving together)')
    ok(f't5: {label} gateway-api-crds: sits directly after gitSshPort with a comment naming it')

for path, label in ((dev_vals, 'services/dev/prod/values.yaml'),
                    (infra_vals, 'services/infra/prod/values.yaml')):
    check_enable(label, load(path))
    check_adjacency(label, open(path).read())

r = subprocess.run(['git', 'grep', '-n', 'gateway-api-crds', '--', 'services', 'custom-values'],
                   capture_output=True, text=True)
allowed = {dev_vals, infra_vals}
if not r.stdout.strip():
    bad('t5: git grep found no gateway-api-crds in services/ or custom-values/ (the enable blocks are missing)')
for line in r.stdout.splitlines():
    p = line.split(':', 1)[0]
    if p not in allowed:
        bad(f't5: gateway-api-crds appears outside the dev/infra umbrella values: {line} (the CRD enable wiring is scoped to exactly the two git-SSH clusters)')
ok('t5: no other service values or custom-values file carries gateway-api-crds (repo-wide)')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t5b-count")))
else
  exit 1
fi

# --- t6: charts/forgejo — SSH_PORT 22222 + tcpRoute, Service unchanged ----
# (C03 c2: lint + plan --set list render with release `forgejo` so
# <fullname>-ssh is exactly forgejo-ssh; c3: deep merge with dev's
# custom-values forgejo: block, release dev-forgejo.)
if [ -z "$helm_bin" ] || [ -z "$fj_copy" ]; then
  skip "t6: forgejo chart checks not run (no helm or forgejo dependency build)"
else
  lint_log="$WORK/lint-forgejo.log"
  if (cd "$fj_copy" && "$helm_bin" lint .) >"$lint_log" 2>&1; then
    ok "t6: helm lint passes for $FORGEJO"
  else
    tail -n 30 "$lint_log" >&2
    fail "t6: helm lint failed for $FORGEJO (log kept at $lint_log)"
  fi

  r1="$WORK/fj-render.yaml"
  if ! "$helm_bin" template forgejo "$fj_copy" \
      --set domain=test.example.com \
      --set bitwardenIds.forgejo=u --set bitwardenIds.forgejo-admin=u \
      --set bitwardenIds.forgejo-pg=u --set bitwardenIds.forgejo-sso=u \
      >"$r1" 2>"$WORK/fj-render.err"; then
    tail -n 30 "$WORK/fj-render.err" >&2
    fail "t6: helm template of $FORGEJO failed (log kept at $WORK/fj-render.err)"
  fi
  if python3 - "$r1" "$WORK/t6-count" <<'PY'
import re, sys, yaml

render, count_file = sys.argv[1], sys.argv[2]
text = open(render).read()
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t6: the forgejo render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

# Line-anchored so a comment, a longer key, or an env-name line cannot
# satisfy the inline-config check.
for rx, label in (
    (r'(?m)^\s*SSH_PORT=22222\s*$', 'SSH_PORT=22222 in the inline-config Secret (the subchart hardcodes 22 and its auto-follow is dead code once the key is set — the explicit override is the point)'),
    (r'(?m)^\s*SSH_LISTEN_PORT=2222\s*$', 'SSH_LISTEN_PORT=2222 unchanged (the container listens on 2222; coincidentally similar digits to 22222, different layers)'),
    (r'(?m)^\s*START_SSH_SERVER=true\s*$', 'START_SSH_SERVER=true'),
):
    if not re.search(rx, text):
        bad(f't6: the rendered inline config lacks {label}')
ok('t6: inline config — SSH_PORT=22222, SSH_LISTEN_PORT=2222, START_SSH_SERVER=true')

docs = [d for d in yaml.safe_load_all(text) if d]

svcs = [d for d in docs if d.get('kind') == 'Service' and (d.get('metadata') or {}).get('name') == 'forgejo-ssh']
if not svcs:
    bad('t6: no Service named forgejo-ssh rendered (the release-name/namespace assumption broke)')
spec = svcs[0].get('spec') or {}
if spec.get('type') != 'ClusterIP':
    bad(f't6: the forgejo-ssh Service type is {spec.get("type")!r}, expected ClusterIP (the TCPRoute backend stays ClusterIP :22 — the LB is traefik\'s, DECISIONS)')
ports = spec.get('ports') or []
ssh_port = next((p for p in ports if p.get('name') == 'ssh'), None)
if ssh_port is None or ssh_port.get('port') != 22 or ssh_port.get('targetPort') != 'ssh':
    bad(f't6: the forgejo-ssh Service ssh port is {ssh_port!r}, expected port 22 -> named targetPort ssh (unchanged)')
ok('t6: forgejo-ssh Service stays ClusterIP :22 -> targetPort ssh')

tr = [d for d in docs if d.get('kind') == 'TCPRoute' and (d.get('metadata') or {}).get('name') == 'forgejo-ssh']
if not tr:
    bad('t6: no TCPRoute named forgejo-ssh rendered (the subchart tcpRoute block is not enabled in charts/forgejo/values.yaml)')
if tr[0].get('apiVersion') != 'gateway.networking.k8s.io/v1alpha2':
    bad(f"t6: TCPRoute apiVersion is {tr[0].get('apiVersion')!r}, expected gateway.networking.k8s.io/v1alpha2 (traefik 3.7's TCPRoute client is pinned to v1alpha2)")
tsp = tr[0].get('spec') or {}
if tsp.get('parentRefs') != [{'name': 'traefik-gateway', 'namespace': 'kube-system', 'sectionName': 'gitssh'}]:
    bad(f"t6: TCPRoute parentRefs are {tsp.get('parentRefs')!r}, expected exactly [{{name: traefik-gateway, namespace: kube-system, sectionName: gitssh}}] (the Gateway C02 renders, in kube-system next to traefik)")
rules = tsp.get('rules')
if rules != [{'backendRefs': [{'kind': 'Service', 'name': 'forgejo-ssh', 'port': 22}]}]:
    bad(f't6: TCPRoute rules are {rules!r}, expected exactly one rule with one backendRef to Service forgejo-ssh:22 (raw TCP — no TLS, no hostname)')
ok('t6: TCPRoute forgejo-ssh — v1alpha2, parentRef traefik-gateway/kube-system/sectionName gitssh, backendRef Service forgejo-ssh:22')

if 'OVERRIDE_' in text:
    bad('t6: the forgejo render still carries an OVERRIDE_* sentinel (the plan --set list did not resolve it)')
ok('t6: no OVERRIDE_* sentinel in the forgejo render')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
  then
    checks=$((checks + $(cat "$WORK/t6-count")))
  else
    exit 1
  fi

  # c3: the same chart rendered with dev's custom-values forgejo: block —
  # SSH_PORT must survive the deep merge alongside the per-instance identity.
  dev_block="$WORK/dev-fj-block.yaml"
  if ! python3 - "$DEV_CV" "$dev_block" <<'PY'
import sys, yaml

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    d = yaml.safe_load(f)
block = (d or {}).get('forgejo')
if not isinstance(block, dict):
    print(f'FAIL: t6: {src} has no top-level forgejo: block to extract', file=sys.stderr)
    sys.exit(1)
with open(dst, 'w') as f:
    yaml.safe_dump(block, f)
PY
  then
    exit 1
  fi
  r2="$WORK/fj-dev-render.yaml"
  if ! "$helm_bin" template dev-forgejo "$fj_copy" -f "$dev_block" \
      --set bitwardenIds.forgejo=u --set bitwardenIds.forgejo-admin=u \
      --set bitwardenIds.forgejo-pg=u --set bitwardenIds.forgejo-sso=u \
      --set domain=scifi.farm \
      >"$r2" 2>"$WORK/fj-dev-render.err"; then
    tail -n 30 "$WORK/fj-dev-render.err" >&2
    fail "t6: helm template of $FORGEJO with dev's custom-values forgejo: block failed (log kept at $WORK/fj-dev-render.err)"
  fi
  if python3 - "$r2" "$WORK/t6b-count" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
count_file = sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t6: the dev custom-values render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

want = (
    (r'(?m)^\s*SSH_PORT=22222\s*$', 'SSH_PORT=22222 (must survive the deep merge with the per-instance values)'),
    (r'(?m)^\s*SSH_LISTEN_PORT=2222\s*$', 'SSH_LISTEN_PORT=2222 (untouched by the merge)'),
    (r'(?m)^\s*DOMAIN=git\.scifi\.farm\s*$', 'DOMAIN=git.scifi.farm (per-instance identity intact)'),
    (r'(?m)^\s*ROOT_URL=https://git\.scifi\.farm/\s*$', 'ROOT_URL=https://git.scifi.farm/ (per-instance identity intact)'),
    (r'(?m)^\s*SSH_DOMAIN=git\.scifi\.farm\s*$', 'SSH_DOMAIN=git.scifi.farm (SSH_DOMAIN follows DOMAIN)'),
)
for rx, label in want:
    if not re.search(rx, text):
        bad(f't6: the dev custom-values deep-merge render lost {label}')
ok('t6: dev custom-values deep merge — SSH_PORT stays 22222 alongside server.{DOMAIN,ROOT_URL} (git.scifi.farm) and SSH_DOMAIN follows DOMAIN')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
  then
    checks=$((checks + $(cat "$WORK/t6b-count")))
  else
    exit 1
  fi
fi

# --- t7: gate OPEN via the REAL service values — full renders (C04 c7) ----
# (C03 c5 intent, C04 carrier: drop both --show-only flags — the CRD now
# comes from the gateway-api-crds dependency, so the assertions parse the
# FULL render: the HCC surface (check_hcc) plus exactly one scoped CRD
# with the spec identity pin (check_crd). The dev render passes no
# sentinel --sets (the plan's exact command) — see the header's sentinel-
# scoping note.)
if [ -z "$helm_bin" ] || [ -z "$base_copy" ]; then
  skip "t7: open-gate renders with the real service values not run (no helm or base dependency build)"
else
  t7a="$WORK/base-dev-open.yaml"
  if ! "$helm_bin" template base "$base_copy" -f "$DEV_VALUES" \
      --set domain=scifi.farm --set clusterName=dev --set serviceName=dev \
      >"$t7a" 2>"$WORK/base-dev-open.err"; then
    tail -n 30 "$WORK/base-dev-open.err" >&2
    fail "t7: full open-gate base render with -f $DEV_VALUES failed (log kept at $WORK/base-dev-open.err) — the dev values must carry gitSshPort (no --set)"
  fi
  if check_hcc "$t7a" t7a; then
    checks=$((checks + $(cat "$WORK/t7a-hcc-count")))
  else
    exit 1
  fi
  if check_crd "$t7a" t7a; then
    checks=$((checks + $(cat "$WORK/t7a-crd-count")))
  else
    exit 1
  fi

  t7b="$WORK/base-infra-open.yaml"
  if ! "$helm_bin" template base "$base_copy" -f "$INFRA_VALUES" \
      --set domain=spencerslab.com --set clusterName=infra --set serviceName=infra \
      --set bitwardenIds.keycloak=u --set bitwardenIds.keycloak-pg=u \
      --set bitwardenIds.smtp=u --set hivetools.bitwardenIds.mcp-pg-keycloak=u \
      --set forgejo.bitwardenIds.forgejo=u --set forgejo.bitwardenIds.forgejo-admin=u \
      --set forgejo.bitwardenIds.forgejo-pg=u --set forgejo.bitwardenIds.forgejo-sso=u \
      >"$t7b" 2>"$WORK/base-infra-open.err"; then
    tail -n 30 "$WORK/base-infra-open.err" >&2
    fail "t7: full open-gate base render with -f $INFRA_VALUES failed (log kept at $WORK/base-infra-open.err) — the infra values must carry gitSshPort (no --set)"
  fi
  if check_hcc "$t7b" t7b; then
    checks=$((checks + $(cat "$WORK/t7b-hcc-count")))
  else
    exit 1
  fi
  if check_crd "$t7b" t7b; then
    checks=$((checks + $(cat "$WORK/t7b-crd-count")))
  else
    exit 1
  fi
fi

# --- t8: umbrella renders + appset values blobs + 1:1 sentinel sweep ------
# (C03 c4 — both umbrellas render with the plan --set lists, 0 OVERRIDE_VIA_
# sentinels, and the rendered appset element's values blob carries gitSshPort
# for both services; plus the plan's static sentinel sweep.)
dev_out="" infra_out=""
if [ -z "$helm_bin" ]; then
  skip "t8: umbrella renders not run (no helm binary)"
else
  dev_out="$WORK/dev-umbrella-render.yaml"
  if ! "$helm_bin" template "$DEVUMB" \
      --set domain=scifi.farm --set subDomain=dev --set clusterName=dev \
      --set bitwardenIds.cert-manager-solver-token=u \
      --set bitwardenIds.argocd-sso-secret=u \
      --set bitwardenIds.github-pat=u --set bitwardenIds.forgejo-token=u \
      --set hivetools.bitwardenIds.mcp-sso=u \
      >"$dev_out" 2>"$WORK/dev-umb.err"; then
    tail -n 30 "$WORK/dev-umb.err" >&2
    fail "t8: helm template of $DEVUMB failed (log kept at $WORK/dev-umb.err)"
  fi
  [ -s "$dev_out" ] || fail "t8: helm template of $DEVUMB rendered nothing"

  if [ -n "$infra_copy" ]; then
    infra_out="$WORK/infra-umbrella-render.yaml"
    if ! "$helm_bin" template "$infra_copy" \
        --set domain=spencerslab.com --set clusterName=infra \
        --set bitwardenIds.keycloak=u --set bitwardenIds.keycloak-pg=u \
        --set bitwardenIds.smtp=u \
        --set hivetools.bitwardenIds.mcp-pg-keycloak=u \
        --set forgejo.bitwardenIds.forgejo=u --set forgejo.bitwardenIds.forgejo-admin=u \
        --set forgejo.bitwardenIds.forgejo-pg=u --set forgejo.bitwardenIds.forgejo-sso=u \
        >"$infra_out" 2>"$WORK/infra-umb.err"; then
      tail -n 30 "$WORK/infra-umb.err" >&2
      fail "t8: helm template of $INFRAUMB failed (log kept at $WORK/infra-umb.err)"
    fi
    [ -s "$infra_out" ] || fail "t8: helm template of $INFRAUMB rendered nothing"
  else
    skip "t8: infra umbrella render not run (dependency build unavailable)"
  fi
fi

if [ -n "$dev_out" ]; then
  if python3 - "$dev_out" dev "$WORK/t8-count" <<'PY'
import sys, yaml

render, which, count_file = sys.argv[1:4]
appset = f'{which}-appset'
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t8: the {which} umbrella render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

docs = [d for d in yaml.safe_load_all(open(render)) if d]
sets = [d for d in docs
        if d.get('kind') == 'ApplicationSet' and (d.get('metadata') or {}).get('name') == appset]
if not sets:
    bad(f't8: no ApplicationSet named {appset} in the {which} umbrella render')
els = sets[0]['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
vals = (els[0] if els else {}).get('values')
if not isinstance(vals, dict):
    bad(f't8: the {appset} generator element has no values blob')
if vals.get('gitSshPort') != 22222:
    bad(f"t8: the {appset} values blob has gitSshPort {vals.get('gitSshPort')!r}, expected 22222 (the base Application for this cluster must carry the gate — C03 criterion 4)")
if ((vals.get('gateway-api-crds') or {}).get('enabled')) is not True:
    bad(f"t8: the {appset} values blob has gateway-api-crds.enabled {((vals.get('gateway-api-crds') or {}).get('enabled'))!r}, expected true (the CRD enable wiring must ride to base with the umbrella values — C04 criterion 9)")
ok(f't8: {appset} values blob carries gitSshPort: 22222 + gateway-api-crds.enabled: true')

raw = open(render).read()
for s in ('OVERRIDE_VIA_CUSTOM_VALUES', 'OVERRIDE_VIA_APPSET'):
    if s in raw:
        bad(f't8: the rendered {which} umbrella still carries the {s} sentinel (the plan --set list did not resolve it)')
ok(f't8: no OVERRIDE_VIA_* sentinel survives in the rendered {which} umbrella')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
  then
    checks=$((checks + $(cat "$WORK/t8-count")))
  else
    exit 1
  fi
fi

if [ -n "$infra_out" ]; then
  if python3 - "$infra_out" infra "$WORK/t8b-count" <<'PY'
import sys, yaml

render, which, count_file = sys.argv[1:4]
appset = f'{which}-appset'
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def _uncaught(exc_type, exc_value, exc_tb):
    print(f'FAIL: t8: the {which} umbrella render could not be evaluated ({exc_type.__name__}: {exc_value})', file=sys.stderr)
    sys.exit(1)
sys.excepthook = _uncaught

docs = [d for d in yaml.safe_load_all(open(render)) if d]
sets = [d for d in docs
        if d.get('kind') == 'ApplicationSet' and (d.get('metadata') or {}).get('name') == appset]
if not sets:
    bad(f't8: no ApplicationSet named {appset} in the {which} umbrella render')
els = sets[0]['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
vals = (els[0] if els else {}).get('values')
if not isinstance(vals, dict):
    bad(f't8: the {appset} generator element has no values blob')
if vals.get('gitSshPort') != 22222:
    bad(f"t8: the {appset} values blob has gitSshPort {vals.get('gitSshPort')!r}, expected 22222 (the base Application for this cluster must carry the gate — C03 criterion 4)")
if ((vals.get('gateway-api-crds') or {}).get('enabled')) is not True:
    bad(f"t8: the {appset} values blob has gateway-api-crds.enabled {((vals.get('gateway-api-crds') or {}).get('enabled'))!r}, expected true (the CRD enable wiring must ride to base with the umbrella values — C04 criterion 9)")
ok(f't8: {appset} values blob carries gitSshPort: 22222 + gateway-api-crds.enabled: true')

raw = open(render).read()
for s in ('OVERRIDE_VIA_CUSTOM_VALUES', 'OVERRIDE_VIA_APPSET'):
    if s in raw:
        bad(f't8: the rendered {which} umbrella still carries the {s} sentinel (the plan --set list did not resolve it)')
ok(f't8: no OVERRIDE_VIA_* sentinel survives in the rendered {which} umbrella')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
  then
    checks=$((checks + $(cat "$WORK/t8b-count")))
  else
    exit 1
  fi
fi

# t8 static: every OVERRIDE_VIA_CUSTOM_VALUES in the three touched values
# files is matched 1:1 by its category's custom-values (real UUID, not
# another sentinel). charts/forgejo is consumed by BOTH dev and infra, so
# its sentinels must match in both custom-values files.
if python3 - "$FORGEJO/values.yaml" "$DEV_VALUES" "$INFRA_VALUES" "$DEV_CV" "$INFRA_CV" "$WORK/t8c-count" <<'PY'
import subprocess, sys, yaml

chart_vals, dev_vals, infra_vals, dev_cv, infra_cv, count_file = sys.argv[1:7]
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
    # ComposerError) — the service values files are the ones that use them.
    # Only markers in `key: &anchor` / `key: *alias` value position are
    # rewritten; & inside quoted URLs and in comments is untouched.
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
        bad(f't8: {label}: ' + '; '.join(missing + still_sentinel))
    else:
        n = sum(1 for _, v in sentinel_paths(values) if v == SENTINEL)
        ok(f't8: {label}: all {n} OVERRIDE_VIA_CUSTOM_VALUES sentinels have a matching key in {custom_path}')

chart = load(chart_vals)
check_sentinels('charts/forgejo/values.yaml (consumed by dev)', chart, load(dev_cv), dev_cv, prefix='forgejo.')
check_sentinels('charts/forgejo/values.yaml (consumed by infra)', chart, load(infra_cv), infra_cv, prefix='forgejo.')
check_sentinels('services/dev/prod/values.yaml', load(dev_vals), load(dev_cv), dev_cv)
check_sentinels('services/infra/prod/values.yaml', load(infra_vals), load(infra_cv), infra_cv)

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t8c-count")))
else
  exit 1
fi

# --- t9: no tcpRoute/SSH_PORT references outside charts/forgejo (C03 c6) --
# git grep only, so untracked vendored tarballs (charts/**/charts) cannot
# false-positive; the positive side (charts/forgejo values DO carry them)
# pins C03 against an accidental full removal too.
if python3 - "$WORK/t9-count" <<'PY'
import subprocess, sys

count_file = sys.argv[1]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

r = subprocess.run(['git', 'grep', '-nE', 'tcpRoute|SSH_PORT', '--',
                    'charts', 'services', 'custom-values'],
                   capture_output=True, text=True)
hits = r.stdout.splitlines()
stray = [l for l in hits if not l.split(':', 1)[0].startswith('charts/forgejo/')]
if stray:
    bad('t9: tcpRoute/SSH_PORT appears outside charts/forgejo (no accidental duplicates — C03 criterion 6):\n' + '\n'.join(stray))
if not any(l.split(':', 1)[0] == 'charts/forgejo/values.yaml' for l in hits):
    bad('t9: charts/forgejo/values.yaml carries no tcpRoute/SSH_PORT (the shared forgejo chart config is missing)')
ok('t9: only charts/forgejo references tcpRoute/SSH_PORT across charts/, services/ and custom-values/')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t9-count")))
else
  exit 1
fi

# --- t10: operator/client-migration notes (C03 c7) ------------------------
if python3 - "$NOTES" "$WORK/t10-count" <<'PY'
import os, re, sys

path, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

if not os.path.isfile(path):
    bad(f't10: {path} is missing (C03 must add the operator/client-migration notes)')
text = open(path).read()
lines = text.splitlines()

for host in ('git.scifi.farm', 'git.spencerslab.com'):
    if host not in text:
        bad(f't10: the notes do not name host {host}')
    if not re.search(r'ssh://git@' + re.escape(host) + r':22222/', text):
        bad(f't10: the notes show no ssh://git@{host}:22222/ URL (the new per-host ssh:// URL shape with port 22222)')
ok('t10: notes name both git hosts with the ssh://git@host:22222/ URL shape')

if '22222' not in text:
    bad('t10: the notes never mention port 22222')
if '~/.ssh/config' not in text:
    bad('t10: the notes do not document the ~/.ssh/config trick (the way scp-style URLs keep working)')
if not re.search(r'(?m)^\s*Port\s+22222\b', text):
    bad('t10: the ~/.ssh/config block has no `Port 22222` line')
ok('t10: notes document port 22222 and the ~/.ssh/config Host/Port trick')

if not any(re.search(r'sshd', l, re.IGNORECASE) and re.search(r'(?<!\d)22(?!\d)', l) for l in lines):
    bad('t10: no line warns that port 22 on the git hosts is still the node sshd (clients would git-clone on :22 and hit the wrong daemon)')
ok('t10: notes warn that port 22 on the git hosts remains the node sshd')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t10-count")))
else
  exit 1
fi

# --- t11: predecessor regressions stay untouched and green ----------------
for s in audit-trail.sh infra-forgejo.sh dev-forgejo-runner.sh dev-git-auth.sh; do
  reg_out="$WORK/reg-$s.out"
  if bash "tests/services/$s" >"$reg_out" 2>&1; then
    ok "t11: tests/services/$s exits 0 (predecessor regression green)"
  else
    tail -n 20 "$reg_out" >&2
    fail "t11: tests/services/$s exited non-zero (predecessor contract broken by this ticket)"
  fi
done

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: forgejo-ssh-gateway checks (%d ok)\n' "$checks"
