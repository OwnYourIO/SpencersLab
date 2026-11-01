#!/usr/bin/env bash
# C05 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline), re-pinned by
# C10 (owner delta 2026-11-01): the dev trio wiring — home-assistant +
# mosquitto `charts:` entries, the home-assistant top-level slice, and the
# HA ingress subdomain, rendered through the dev umbrella. C10 shape: the
# slice is EXACTLY `homeAssistant: {enabled: true}` (the postgres.enabled +
# persistence.enabled keys are DELETED — dev now renders the full CNPG +
# always-on-PVC stack), and the trio's SECRETS LEG ACTIVATES:
# custom-values/dev/prod-values.yaml gains the `home-assistant:
# bitwardenIds:` block, 1:1 with the chart's three sentinel keys, placeholder
# markers until the owner's dedicated dev item id lands (the one hand-off
# ask — C10 Tasks: grow ids are reference-only, never copied agent-side).
#
# Contract source: chunks/C05.md "## Tests" + chunks/C10.md test-delta
# bullets. AC trace: t1[C05 AC1] t2[C05 AC2] t3[C05 AC3 + C10 slice-comment
# posture] t4[C10 AC3-in-dev + C05 AC4 re-pinned] t5[C05 AC5] t6[C10 AC5
# sentinel 1:1 leg — placement call: dev-wiring owns custom-values/dev].
#
# Slice-extraction recipe (helm-chart-creation): appset-charts merges ONLY
# the top-level <appName>: key into each release, so t4 extracts
# `home-assistant:` from the dev values and feeds it via -f — the C03/C05
# wiring proof that never assumes which nesting C03 actually shipped (chunk
# Notes: "AC4 is the contract test for that").
#
# Slice-fed renders run on a /tmp copy after `helm dependency update`
# (gitignored charts/, committed Chart.lock). Registry-unreachable => the
# chart-render legs skip LOUD; all other legs are local. PATH export first —
# FRICTION.
#
# Pre-C10 reds (expected until dev lands the delta): t3 (slice comment still
# carries the superseded SQLite posture), t4 (slice not the final exact
# shape; CNPG/ES/PVC missing from the slice render), t6 (no dev assistant
# block yet). C05-era legs t1/t2/t5 stay green — regression pins.
#
# Usage:
#   bash tests/multi-repo/dev-wiring.sh           # t1..t6
#   bash tests/multi-repo/dev-wiring.sh t2 t3     # subset
# Env: HELM_BIN, DEV_UMBRELLA (default services/dev/prod),
#      DEV_VALUES (default services/dev/prod/values.yaml),
#      DEV_CV (default custom-values/dev/prod-values.yaml),
#      DEV_CV_ALLOW_GROW_ID=1 (owner-pasted grow-uuid escape, t6 only).
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
  for i in 1 2 3 4 5 6; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
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
# C10 posture flip: the slice's rewritten comment must name the CNPG render
# + the custom-values secrets consumption, and the superseded SQLite posture
# (owner: "not interested in supporting sqlite") may survive nowhere in the
# dev values file.
idx = [i for i, l in enumerate(lines) if re.match(r'^home-assistant:\s*$', l)]
if not idx:
    bad(f'{path} has no top-level home-assistant: slice (t4 extracts it)')
j = idx[0] - 1
win = []
while j >= 0 and (lines[j].strip().startswith('#') or not lines[j].strip()):
    win.insert(0, lines[j]); j -= 1
win = win + lines[idx[0]:idx[0] + 10]
wtxt = '\n'.join(win)
if 'sqlite' in wtxt.lower() or any('sqlite' in l.lower() and l.strip().startswith('#') for l in lines):
    bad('SQLite posture wording survives in the dev values comments — C10 deletes the SQLite stance (owner verbatim) and rewrites the slice block')
if not (re.search(r'CNPG|postgres', wtxt, re.I) and re.search(r'custom-values|bitwardenIds', wtxt, re.I)):
    bad('the home-assistant slice comment must carry the POST-C10 posture vocabulary: dev renders CNPG + ExternalSecrets consume the three bitwardenIds keys resolved from custom-values/dev (C10 Tasks comment rewrite)')
print('ok: t3 — trio greps: charts entries + HA slice + HA subdomain present, mosquitto proxy leg documented N/A (forgejo-runner-dev precedent), no mosquitto subdomain, and the C10 comment posture landed (C05 AC3 + C10)')
PY
  checks=$((checks + 1))
fi

# --- t4: slice shape + slice-fed render (C10 re-pin of C05 AC4) ---------------
if want t4; then
  extract_ha_slice || fail 't4: slice extraction failed (reason above)'

  # C10: the slice is EXACTLY {homeAssistant: {enabled: true}} — the dropped
  # postgres/persistence keys must be gone (they read as live flags today;
  # the deleted chart keys make stale slice keys dead values, so the slice
  # itself is pinned, not just rendered).
  if python3 - "$HA_SLICE" <<'PY'
import sys, yaml

sl = yaml.safe_load(open(sys.argv[1]))
def bad(msg):
    print(f'FAIL: t4 {msg}', file=sys.stderr)
    sys.exit(1)
if sl != {'homeAssistant': {'enabled': True}}:
    bad(f'the dev home-assistant slice is {sl!r}, expected EXACTLY {{homeAssistant: {{enabled: true}}}} — postgres.enabled + homeAssistant.persistence.enabled are DELETED keys (C10)')
print('ok: t4: dev slice parses to exactly {homeAssistant: {enabled: true}} (dropped keys absent, C10)')
PY
  then checks=$((checks + 1)); else fail 't4: the slice-shape contract is not satisfied (reason above)'; fi

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
    # Test uuids stand for the awaited owner hand-off (t6 tracks the real
    # state): AC5's "sentinel-free render proven by feeding test values".
    slice_out="$WORK/ha-slice.render.yaml"
    if ! "$helm_bin" template dev-home-assistant "$HACOPY" -f "$HA_SLICE" \
        --set "domain=$DOMAIN" \
        --set 'bitwardenIds.home-assistant-pg=test-uuid' \
        --set 'bitwardenIds.mcp-pg-grow-assistant=test-uuid' \
        --set 'bitwardenIds.mcp-pg-grow-assistant-sensors=test-uuid' \
        >"$slice_out" 2>"$WORK/ha-slice.err"; then
      tail -n 30 "$WORK/ha-slice.err" >&2
      fail "t4: rendering $HA_CHART with the extracted dev slice failed (stderr $WORK/ha-slice.err)"
    fi
    if python3 - "$slice_out" <<'PY'
import sys, yaml

f = sys.argv[1]
docs = [d for d in yaml.safe_load_all(open(f)) if isinstance(d, dict)]
def bad(msg):
    print(f'FAIL: t4 {msg}', file=sys.stderr)
    sys.exit(1)

raw = open(f).read()
counts = {}
for d in docs:
    counts[d.get('kind')] = counts.get(d.get('kind'), 0) + 1
# C10 inverts the C05 dev render: CNPG + ExternalSecrets now RENDER for dev
# (the trio's secrets leg is active), the PVC is unconditional, and the
# container arrives via the slice. Full dev stack, exact multiset.
want = {'Cluster': 2, 'ExternalSecret': 4, 'PersistentVolumeClaim': 1, 'Deployment': 1, 'Service': 1}
if counts != want:
    bad(f'slice render kinds {counts}, expected exactly {want} — dev renders CNPG + PVC + container (C10)')
dep = next(d for d in docs if d.get('kind') == 'Deployment')
imgs = [c.get('image') or '' for c in dep['spec']['template']['spec'].get('containers') or []]
if not any('home-assistant:2026.10.4' in i for i in imgs):
    bad(f'slice render images {imgs} lack the pinned home-assistant:2026.10.4')
pod = dep['spec']['template']['spec']
if not [m for m in (pod.get('containers') or [{}])[0].get('volumeMounts') or [] if m.get('mountPath') == '/config']:
    bad('no /config mount in the dev Deployment')
pvc = next(d for d in docs if d.get('kind') == 'PersistentVolumeClaim')
vol = next((v for v in pod.get('volumes') or [] if (v.get('persistentVolumeClaim') or {}).get('claimName')), None)
if not vol or (vol.get('persistentVolumeClaim') or {}).get('claimName') != pvc['metadata']['name']:
    bad(f'/config existingClaim does not pair with the unconditional PVC {pvc["metadata"]["name"]!r}')
if 'ServiceAccount' in {d.get('kind') for d in docs}:
    bad('ServiceAccount rendered for dev — createDefaultServiceAccount suppression must survive C10')
if 'OVERRIDE_' in raw:
    bad('OVERRIDE_* sentinel survived the slice render with test uuids supplied (C10 AC5 proof shape)')
print('ok: t4 — slice-fed render: full dev stack (2 CNPG Clusters + 4 ExternalSecrets + PVC + Deployment + Service), pinned image, /config↔claim pairing, sentinel-free with supplied test uuids (C10 re-pin of C05 AC4)')
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

# --- t6: sentinel↔custom-values 1:1 — the trio's secrets leg (C10 AC5) --------
# Repo validation idiom (AGENTS.md): every OVERRIDE_VIA_CUSTOM_VALUES
# placeholder matched 1:1 by a custom-values/ entry. C10 activates the dev
# secrets leg: custom-values/dev/prod-values.yaml gains a home-assistant
# bitwardenIds block with the chart's three keys. Values are placeholder
# markers (OVERRIDE_*-style, the documented interim state until the owner's
# dedicated dev-item id lands — ONE id is expected to serve all three keys,
# grow's shape as reference only) or real UUIDs post hand-off. The
# placeholder-vs-filled distinction rides the ok message so review can see
# the hand-off state; a grow UUID pasted in agent-side is the C10 violation
# this leg also refuses (owner-paste escape: DEV_CV_ALLOW_GROW_ID=1).
if want t6; then
  if python3 - "$HA_CHART/values.yaml" "$DEV_CV" <<'PY'
import os, re, sys, yaml

chart_vals_f, dev_cv_f = sys.argv[1:3]
def bad(msg):
    print(f'FAIL: t6 {msg}', file=sys.stderr)
    sys.exit(1)

def load(path):
    lines = []
    for line in open(path):
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
GROW_ITEM = 'f59add53-a8fb-42cd-b784-b3c8011081df'   # custom-values/grow's single item — reference only
EXPECT = {'home-assistant-pg', 'mcp-pg-grow-assistant', 'mcp-pg-grow-assistant-sensors'}

bw = (load(chart_vals_f).get('bitwardenIds') or {})
if set(bw) != EXPECT:
    bad(f'chart bitwardenIds keys are {sorted(bw)}, expected exactly {sorted(EXPECT)} (the three keys C10 wires)')
for k, v in bw.items():
    if not str(v).startswith('OVERRIDE_'):
        bad(f'chart sentinel {k} is {v!r} — chart values must keep the OVERRIDE_* placeholder shape (real ids live only in custom-values)')

cv = load(dev_cv_f)
blk = cv.get('home-assistant')
if not isinstance(blk, dict):
    bad(f'{dev_cv_f} has no top-level home-assistant: block — the C10 secrets leg of the trio has not landed')
slot = blk.get('bitwardenIds')
if not isinstance(slot, dict):
    bad(f'{dev_cv_f} home-assistant block has no bitwardenIds: sub-block')
if set(slot) != EXPECT:
    bad(f'dev custom-values bitwardenIds keys are {sorted(slot)}, expected the 1:1 set {sorted(EXPECT)}')

filled = marked = 0
allow_grow = os.environ.get('DEV_CV_ALLOW_GROW_ID', '') == '1'
for k, v in sorted(slot.items()):
    v = str(v)
    if UUID_RE.match(v):
        filled += 1
        if v == GROW_ITEM and not allow_grow:
            bad(f'{k} carries GROW\'s item id — C10: grow ids are reference-only, never copied agent-side without the owner word (owner-paste escape: DEV_CV_ALLOW_GROW_ID=1)')
    elif v.startswith('OVERRIDE_'):
        marked += 1
    else:
        bad(f'{k} value {v!r} is neither an OVERRIDE_* placeholder marker nor a UUID — not a recognized state')

# The dated why-comment (C10 Tasks: placeholder + dated why-comment): a
# comment line near the block must carry the ruling date and hand-off
# context, so the unfilled state reads as intentional, not forgotten.
lines = open(dev_cv_f).read().splitlines()
idx = [i for i, l in enumerate(lines) if re.match(r'^home-assistant:\s*$', l)]
win = []
if idx:
    j = idx[0] - 1
    while j >= 0 and (lines[j].strip().startswith('#') or not lines[j].strip()):
        win.insert(0, lines[j]); j -= 1
    win += [l for l in lines[idx[0]:idx[0] + 12] if l.strip().startswith('#')]
blob = ' '.join(win)
if not (re.search(r'2026-11', blob) and re.search(r'owner|hand-?off|placeholder|id lands', blob, re.I)):
    bad('the dev home-assistant block lacks a dated (2026-11) why-comment naming the owner hand-off — the placeholder interim must be documented in-file (C10 Tasks)')

state = f'{filled} filled / {marked} placeholder'
if marked and filled:
    bad(f'mixed block state ({state}) — the hand-off fills all three keys at once (one id serves them; grow-shape reference)')
print(f'ok: t6 — sentinel 1:1: chart {sorted(EXPECT)} ↔ custom-values/dev home-assistant block ({state}); {"awaiting the owner dev-item id hand-off" if marked else "ids filled — deploy-time sentinel consumption can complete"} (C10 AC5)')
PY
  then checks=$((checks + 1)); else fail 't6: the sentinel↔custom-values contract is not satisfied (reason printed above)'; fi
fi

printf 'PASS: cf-93 C05/C10 dev-wiring contract (%d ok)\n' "$checks"
