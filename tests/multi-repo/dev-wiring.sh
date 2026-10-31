#!/usr/bin/env bash
# C05 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the dev trio
# wiring — home-assistant + mosquitto `charts:` entries, the home-assistant
# top-level slice (C03's flags flipped for the empty dev instance), the HA
# ingress subdomain, and mosquitto's documented proxy-leg N/A comment — all
# in services/dev/prod/values.yaml, rendered through the dev umbrella.
#
# Contract source: chunks/C05.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC2] t3[AC3] t4[AC4] t5[AC5].
#
# Slice-extraction recipe (helm-chart-creation): appset-charts merges ONLY
# the top-level <appName>: key into each release, so t4 extracts
# `home-assistant:` from the dev values and feeds it via -f — the C03/C05
# wiring proof that never assumes which nesting C03 actually shipped (chunk
# Notes: "AC4 is the contract test for that").
#
# The chart render (t4) runs on a /tmp copy after `helm dependency update`
# (gitignored charts/, committed Chart.lock). Registry-unreachable => t4
# skips LOUD; all other legs are local. PATH export first — FRICTION.
#
# Pre-C05 reds: every leg (entries absent). Pre-C03 red on t4 (slice keys
# unknown to the stub chart => no Deployment => fail), which is the correct
# dependency signal, waves 1 before 2.
#
# Usage:
#   bash tests/multi-repo/dev-wiring.sh           # t1..t5
#   bash tests/multi-repo/dev-wiring.sh t2 t3     # subset
# Env: HELM_BIN, DEV_UMBRELLA (default services/dev/prod),
#      DEV_VALUES (default services/dev/prod/values.yaml),
#      DEV_CV (default custom-values/dev/prod-values.yaml).
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # helm lives here — FRICTION seed

cd "$(git rev-parse --show-toplevel)"

UMBRELLA="${DEV_UMBRELLA:-services/dev/prod}"
DEV_VALUES="${DEV_VALUES:-services/dev/prod/values.yaml}"
DEV_CV="${DEV_CV:-custom-values/dev/prod-values.yaml}"
HA_CHART="${HA_CHART:-charts/home-assistant}"
DOMAIN=test.example.com

checks=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
skip() { printf 'skip: %s\n' "$1" >&2; }

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

find_helm() {
  local cand
  if [ -n "${HELM_BIN:-}" ] && [ -x "${HELM_BIN}" ]; then printf '%s' "$HELM_BIN"; return 0; fi
  if command -v helm >/dev/null 2>&1; then command -v helm; return 0; fi
  if [ -x "$HOME/.local/bin/helm" ]; then printf '%s' "$HOME/.local/bin/helm"; return 0; fi
  cand=$(find /tmp/opencode -maxdepth 4 -type f -name helm -perm -u+x 2>/dev/null | head -n 1 || true)
  [ -n "$cand" ] && { printf '%s' "$cand"; return 0; }
  return 1
}

helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || fail "dev-wiring: no helm binary — silent skip is the documented FRICTION hazard"

WORK=$(mktemp -d /tmp/opencode/dev-wiring.XXXXXX)
HA_SLICE="$WORK/ha-slice.yaml"

extract_ha_slice() { # writes $HA_SLICE; fails with the reason if absent (red for C05 not landed)
  python3 - "$DEV_VALUES" "$HA_SLICE" <<'PY'
import re, sys, yaml

path, out = sys.argv[1:3]
def bad(msg):
    print(f'FAIL: slice extraction {msg}', file=sys.stderr)
    sys.exit(1)

lines = []
for line in open(path):
    line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)   # anchor-lenient loader
    line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
    lines.append(line)
sv = yaml.safe_load(''.join(lines)) or {}
sl = sv.get('home-assistant')
if not isinstance(sl, dict):
    bad(f'{path} has no top-level home-assistant: slice — the C05 values slice is what proves the C03 wiring (AC4)')
yaml.safe_dump(sl, open(out, 'w'), sort_keys=False)
PY
}

# --- umbrella render: dev-forgejo-runner.sh t9 recipe --------------------------
UMB_RENDER="$WORK/umbrella.yaml"
if ! "$helm_bin" template dev "$UMBRELLA" -f "$DEV_CV" \
    --set "domain=$DOMAIN" --set clusterName=dev >"$UMB_RENDER" 2>"$WORK/umbrella.err"; then
  tail -n 30 "$WORK/umbrella.err" >&2
  fail "umbrella render of $UMBRELLA failed (stderr kept at $WORK/umbrella.err)"
fi
[ -s "$UMB_RENDER" ] || fail "umbrella render of $UMBRELLA produced nothing"

# --- t1: appset Applications cover both workloads (C05 AC1) -------------------
if want t1; then
  if python3 - "$UMB_RENDER" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if isinstance(d, dict)]
def bad(msg):
    print(f'FAIL: t1 {msg}', file=sys.stderr)
    sys.exit(1)

appsets = [d for d in docs if d.get('kind') == 'ApplicationSet'
           and (d.get('metadata') or {}).get('name') == 'dev-appset']
if not appsets:
    bad('no ApplicationSet named dev-appset in the umbrella render')

# Collect every charts dict from every list-generator elements blob — the
# walk survives matrix/generator nesting reshuffles (dev-forgejo proved the
# current shape is generators[0].matrix.generators[1].list.elements).
charts = {}
def walk(node):
    if isinstance(node, dict):
        if 'elements' in node and isinstance(node['elements'], list):
            for el in node['elements']:
                if isinstance(el, dict) and isinstance(el.get('values'), dict):
                    charts.update(el['values'].get('charts') or {})
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
walk(appsets[0])

for app in ('home-assistant', 'mosquitto'):
    e = charts.get(app)
    if not isinstance(e, dict):
        bad(f'the dev-appset values blob lacks charts.{app} — the charts: entry is what generates the Application (appName==chart name, service-name law)')
    if e.get('namespace') != 'default':
        bad(f'charts.{app}.namespace is {e.get("namespace")!r}, expected default (the dev cluster runs everything in default)')
print('ok: t1 — dev-appset covers charts.home-assistant and charts.mosquitto, both namespace default (C05 AC1)')
PY
  then checks=$((checks + 1)); else fail 't1: the appset Applications contract is not satisfied (reason printed above)'; fi
fi

# --- t2: ingress host asserts incl. mosquitto absence (C05 AC2) --------------
if want t2; then
  if python3 - "$UMB_RENDER" "$DOMAIN" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if isinstance(d, dict)]
domain = sys.argv[2]
def bad(msg):
    print(f'FAIL: t2 {msg}', file=sys.stderr)
    sys.exit(1)

ingresses = [d for d in docs if d.get('kind') == 'Ingress']
def hosts_and_backends(ing):
    out = []
    for rule in (ing.get('spec') or {}).get('rules') or []:
        host = rule.get('host') or ''
        for p in ((rule.get('http') or {}).get('paths') or []):
            svc = ((p.get('backend') or {}).get('service') or {})
            out.append((host, svc.get('name'), (svc.get('port') or {}).get('number')))
    return out

pairs = [h for ing in ingresses for h in hosts_and_backends(ing)]
ha = [p for p in pairs if p[0] == f'home-assistant.{domain}']
if not ha:
    bad(f'no Ingress host home-assistant.{domain} (hosts: {sorted({p[0] for p in pairs})}) — the generic ingress must carry the HA subdomain entry')
if not any(name == 'dev-home-assistant' and port == 8123 for _h, name, port in ha):
    bad(f'home-assistant.{domain} routes to {ha}, expected backend service dev-home-assistant port 8123 (the release-named Service — C05 pins the name, do not guess)')
for h, name, _p in pairs:
    if 'mosquitto' in h or 'mosquitto' in (name or ''):
        bad(f'a mosquitto ingress surfaced ({h} -> {name}) — the broker is ClusterIP-only in dev, NO ingress host (OQ-C2/AC2)')
print('ok: t2 — home-assistant.test.example.com -> dev-home-assistant:8123 rendered; zero mosquitto ingress hosts (C05 AC2)')
PY
  then checks=$((checks + 1)); else fail 't2: the ingress contract is not satisfied (reason printed above)'; fi
fi

# --- t3: trio greps on the values file (C05 AC3) ------------------------------
if want t3; then
  # Structure via the anchor-lenient loader (dev-forgejo precedent).
  python3 - "$DEV_VALUES" <<'PY' || fail 't3: the trio structure/greps are not satisfied (reason printed above)'
import re, sys, yaml

path = sys.argv[1]
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)

def load(path):
    lines = []
    for line in open(path):
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

sv = load(path)
charts = sv.get('charts') or {}
for app in ('home-assistant', 'mosquitto'):
    if app not in charts:
        bad(f'{path} has no charts.{app} entry (trio leg 1)')
if not isinstance(sv.get('home-assistant'), dict):
    bad(f'{path} has no TOP-LEVEL home-assistant: slice — appset-charts merges only that key into the release (trio leg: the values slice)')
sub = ((sv.get('ingress') or {}).get('subdomains') or {})
hsub = sub.get('home-assistant')
if not isinstance(hsub, dict):
    bad('no ingress.subdomains.home-assistant entry (trio leg 2 for HA)')
if hsub.get('service') != 'dev-home-assistant' or hsub.get('port') != 8123:
    bad(f'ingress.subdomains.home-assistant is {hsub!r}, expected service dev-home-assistant port 8123')
if 'mosquitto' in sub:
    bad('ingress.subdomains grew a mosquitto entry — the dev proxy leg is N/A by design (OQ-C2)')

# AC3's mosquitto leg is a grep-shaped COMMENT: the trio-exemption rationale
# must sit adjacent to the charts.mosquitto entry where grep readers land,
# and cite the forgejo-runner precedent so the missing leg never reads as an
# oversight (repo trio law + chunk Tasks).
lines = open(path).read().splitlines()
idx = [i for i, l in enumerate(lines) if re.match(r'^[ \t]+mosquitto:\s*$', l)]
if not idx:
    bad('no mosquitto: line found in the values file')
window = []
anchor = idx[0]
lo = anchor - 12
while lo < anchor:
    window.append(lines[lo]); lo += 1
window = window + lines[anchor:anchor + 8]
comments = [l.strip() for l in window if l.strip().startswith('#')]
blob = ' '.join(comments)
if not re.search(r'N/A|not an oversight|in-cluster|client', blob, re.I):
    bad('the charts.mosquitto entry carries no N/A-in-cluster comment (the trio-grep readers must see why there is no proxy leg)')
if not re.search(r'forgejo-runner', blob):
    bad('the mosquitto N/A comment must cite the forgejo-runner-dev precedent (documented posture, not invented)')
print('ok: t3 — trio greps: charts entries + HA slice + HA subdomain present, mosquitto proxy leg documented N/A (forgejo-runner-dev precedent), no mosquitto subdomain (C05 AC3)')
PY
  checks=$((checks + 1))
fi

# --- t4: slice-fed chart render (C05 AC4) -------------------------------------
if want t4; then
  extract_ha_slice || fail 't4: slice extraction failed (reason above)'

  if [ ! -d "$HA_CHART" ]; then
    fail "t4: $HA_CHART missing — nothing to render the slice against"
  fi
  HACOPY="$WORK/home-assistant"
  mkdir -p "$HACOPY"
  cp -R "$HA_CHART"/. "$HACOPY"/
  dep_log="$WORK/ha-dependency-update.log"
  if ! (cd "$HACOPY" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "t4: chart-slice render not run — helm registry unreachable (log $dep_log)"
    else
      tail -n 30 "$dep_log" >&2
      fail "t4: helm dependency update failed for $HA_CHART (log $dep_log)"
    fi
  else
    slice_out="$WORK/ha-slice.render.yaml"
    if ! "$helm_bin" template dev-home-assistant "$HACOPY" -f "$HA_SLICE" \
        --set "domain=$DOMAIN" >"$slice_out" 2>"$WORK/ha-slice.err"; then
      tail -n 30 "$WORK/ha-slice.err" >&2
      fail "t4: rendering $HA_CHART with the extracted dev slice failed (stderr $WORK/ha-slice.err)"
    fi
    if python3 - "$slice_out" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if isinstance(d, dict)]
def bad(msg):
    print(f'FAIL: t4 {msg}', file=sys.stderr)
    sys.exit(1)

raw = open(sys.argv[1]).read()
kinds = {d.get('kind') for d in docs}
if 'Deployment' not in kinds:
    bad('the dev slice did NOT enable the HA container — no Deployment (the slice must carry the exact enable mechanism C03 shipped; AC4)')
dep = next(d for d in docs if d.get('kind') == 'Deployment')
imgs = [c.get('image') or '' for c in dep['spec']['template']['spec'].get('containers') or []]
if not any('home-assistant:2026.10.4' in i for i in imgs):
    bad(f'slice render images {imgs} lack the pinned home-assistant:2026.10.4')
if 'PersistentVolumeClaim' not in kinds:
    bad('the dev slice did not bring up the /config PVC (homeAssistant.persistence enabled for the dev instance, chunk Tasks)')
if 'Cluster' in kinds or 'postgresql.cnpg.io' in raw:
    bad('CNPG Cluster renders with the dev slice — postgres.enabled=false must be wired (SQLite-in-/config is the dev shape)')
if 'ExternalSecret' in kinds:
    bad('ExternalSecret renders with the dev slice — with postgres off NO secret template may emit (the bitwardenIds sentinels are consumed by no template in this mode)')
print('ok: t4 — slice-fed render: Deployment + pinned image + PVC, no CNPG, no ExternalSecret (C03 flags wired right, C05 AC4)')
PY
    then checks=$((checks + 1)); else fail 't4: the slice-render contract is not satisfied (reason printed above)'; fi
  fi
fi

# --- t5: lints + additive diff (C05 AC5) --------------------------------------
if want t5; then
  lint_log="$WORK/lint-umbrella.log"
  "$helm_bin" lint "$UMBRELLA" >"$lint_log" 2>&1 \
    || { tail -n 30 "$lint_log" >&2; fail "t5: helm lint $UMBRELLA failed (log $lint_log)"; }
  ok "t5: helm lint passes for $UMBRELLA"

  # The chart-with-slice lint needs the same slice as t4; if C05 has not
  # landed the extraction fails and this leg reports it — honest red, the
  # slice lint is part of AC5.
  extract_ha_slice || fail "t5: chart-slice lint needs the home-assistant slice (see extraction reason above)"
  HACOPY2="$WORK/ha-lint"
  mkdir -p "$HACOPY2"
  cp -R "$HA_CHART"/. "$HACOPY2"/
  if (cd "$HACOPY2" && "$helm_bin" dependency update .) >/dev/null 2>&1; then
    lint2="$WORK/lint-ha-chart.log"
    if (cd "$HACOPY2" && "$helm_bin" lint . -f "$HA_SLICE") >"$lint2" 2>&1; then
      ok "t5: helm lint passes for $HA_CHART with the dev slice"
    else
      tail -n 30 "$lint2" >&2
      fail "t5: helm lint of $HA_CHART with the dev slice failed (log $lint2)"
    fi
  else
    skip "t5: chart-slice lint not run (registry unreachable)"
  fi

  # Additive-only proof: every fork-point key still exists; nothing unrelated
  # churned (AC5 "diff is additive").
  base_ref=$(git merge-base HEAD main)
  git show "$base_ref:$DEV_VALUES" > "$WORK/values.base.yaml" || fail "t5: could not read $DEV_VALUES at $base_ref"
  if python3 - "$WORK/values.base.yaml" "$DEV_VALUES" <<'PY'
import re, sys, yaml

def load(path):
    lines = []
    for line in open(path):
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

base = load(sys.argv[1])
cur = load(sys.argv[2])
def bad(msg):
    print(f'FAIL: t5 {msg}', file=sys.stderr)
    sys.exit(1)

lost = [k for k in base if k not in cur]
if lost:
    bad(f'top-level keys removed vs fork point: {lost} — the C05 diff must be additive')
lost_charts = [k for k in (base.get('charts') or {}) if k not in (cur.get('charts') or {})]
if lost_charts:
    bad(f'charts: entries removed: {lost_charts}')
lost_sub = [k for k in ((base.get('ingress') or {}).get('subdomains') or {})
            if k not in ((cur.get('ingress') or {}).get('subdomains') or {})]
if lost_sub:
    bad(f'ingress.subdomains entries removed: {lost_sub}')
print('ok: t5 — the values diff is additive: no top-level key, charts entry or subdomain removed vs the fork point (C05 AC5)')
PY
  then checks=$((checks + 1)); else fail 't5: the additive-diff contract is not satisfied (reason printed above)'; fi
fi

printf 'PASS: cf-93 C05 dev-wiring contract (%d ok)\n' "$checks"
