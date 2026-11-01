#!/usr/bin/env bash
# charts/home-assistant contract — C03 as LANDED, re-pinned by C10 (owner
# delta 2026-11-01): the postgres.enabled guard (six templates + values key)
# and the homeAssistant.persistence.enabled gate (PVC template + keys) are
# DELETED — CNPG, the four ExternalSecrets and the /config PVC render
# unconditionally; the ONLY surviving gate is the HA container
# (homeAssistant.enabled, default false, + Chart.yaml condition). The two
# credential ExternalSecrets gain the forced-username target.template shape
# (usernames per C10's mapping table; only the password is read from the
# Bitwarden item). Grow stays container-free (its HA is EXTERNAL) but now
# renders the always-on PVC — the owner-accepted interpretation cost.
#
# Contract source: chunks/C10.md "Tests (test_session delta)" + Acceptance
# criteria, amending chunks/C03.md. AC trace: t1[C10 AC2] t2[C10 AC3]
# t3[C10 AC5 render half] t4[C10 AC1 + C03 AC4/AC5 still-live pins] t5[C10
# AC4 grow posture].
#
# GOLDEN BASELINE — C10 AC2 replaces C03's whole-file byte-identity with a
# re-baseline: the old golden lives on as snapshots/ha-chart-default-preC10.yaml
# (2 Clusters + 4 ExternalSecrets, captured 2026-10-31 @ branch 7e07a6273e,
# content sha256 c4c8c65ea4ace29ff1017ecb272e9735e5cc088ea6af543f3b2bef82d859f86f)
# and is the DIFF AUTHORITY, not the equality target:
#   - the two Cluster docs must stay byte-identical (AC2 "diff EMPTY"),
#   - each ExternalSecret may differ from its golden counterpart ONLY by the
#     forced-username/target.template shape (structural view comparison),
#   - one new PersistentVolumeClaim completes the set.
# AUTHORIZED RE-CAPTURE: once C10 lands, the new-baseline golden is recorded
# at snapshots/ha-chart-default.yaml via
#   HA_RECAPTURE=1 bash tests/multi-repo/ha-chart.sh t1
# which refuses to write anything unless every structural expectation below
# already passes (never green-by-construction against today's tree). t1
# additionally cmp's the render against that file when it exists.
#
# Rendering runs on a COPY under /tmp/opencode after `helm dependency update`
# (repo convention: charts/**/charts is gitignored, Chart.lock committed —
# dev-forgejo-runner.sh precedent). No-cluster/no-network: if the bjw-s
# registry is unreachable the helm legs skip LOUDLY (stderr skip lines) —
# never silent. FRICTION: PATH exports ~/.local/bin first or helm vanishes.
#
# Usage:
#   bash tests/multi-repo/ha-chart.sh            # t1..t5
#   bash tests/multi-repo/ha-chart.sh t1 t5      # subset
#   HA_RECAPTURE=1 bash tests/multi-repo/ha-chart.sh t1   # post-C10 authorized
#   re-baseline (writes snapshots/ha-chart-default.yaml)
# Env: HELM_BIN, HA_SNAPSHOT (re-point the pre-C10 authority file),
#      CHART (default charts/home-assistant).
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # helm lives here — FRICTION seed, never optional

cd "$(git rev-parse --show-toplevel)"

CHART="${CHART:-charts/home-assistant}"
PREC10="${HA_SNAPSHOT:-tests/multi-repo/snapshots/ha-chart-default-preC10.yaml}"
NEWGOLDEN=tests/multi-repo/snapshots/ha-chart-default.yaml
HA_IMAGE="ghcr.io/home-assistant/home-assistant"
HA_TAG="2026.10.4"
REL=ha-test
BW_PG=home-assistant-pg
BW_MCP1=mcp-pg-grow-assistant
BW_MCP2=mcp-pg-grow-assistant-sensors

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

# --- helm discovery (dev-forgejo-runner.sh convention, loud on failure) ------
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
[ -n "$helm_bin" ] || fail "ha-chart: no helm binary (HELM_BIN/PATH/~/.local/bin//tmp/opencode) — the whole suite is helm-shaped, a silent pass here is the FRICTION hazard"

WORK=$(mktemp -d /tmp/opencode/ha-chart.XXXXXX)
NORMALIZER="$WORK/normalize.py"
cat > "$NORMALIZER" <<'PY'
# Keep only real resources (docs with apiVersion+kind), sort deterministically,
# re-emit as canonical YAML. See header: this is THE snapshot pipeline — capture
# and re-check must run the identical code.
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.stdin) if isinstance(d, dict) and d.get('kind')]
docs.sort(key=lambda d: (d.get('kind'), (d.get('metadata') or {}).get('name', ''), (d.get('metadata') or {}).get('namespace', '')))
out = []
for i, d in enumerate(docs):
    if i:
        out.append('---\n')
    out.append(yaml.safe_dump(d, sort_keys=False, default_flow_style=False, allow_unicode=True))
sys.stdout.write(''.join(out))
PY

[ -f "$PREC10" ] || fail "ha-chart: pre-C10 golden $PREC10 missing — it is C10 AC2's diff authority (the old golden at snapshots/ was renamed on 2026-11-01; never hand-edit it)"

# --- render-on-copy machinery: dependency update once, legs reuse -------------
skip_render=0
COPY="$WORK/home-assistant"
mkdir -p "$COPY"
cp -R "$CHART"/. "$COPY"/
dep_log="$WORK/dependency-update.log"
if ! (cd "$COPY" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
  if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|failed to download|failed to fetch|could not download' "$dep_log"; then
    skip_render=1
    skip "helm dependency update could not reach the registry (log $dep_log); t1-t3+t5 render legs skipped LOUD, t4 statics still run"
  else
    tail -n 30 "$dep_log" >&2
    fail "helm dependency update failed for $CHART — not a network skip (log $dep_log)"
  fi
fi

render_raw() { # render_raw <outfile> [--set ...] — raw helm output, failing loudly
  local out="$1"; shift
  if ! "$helm_bin" template "$REL" "$COPY" "$@" >"$out" 2>"$out.err"; then
    tail -n 30 "$out.err" >&2
    fail "helm template of $COPY ($*) failed (stderr kept at $out.err)"
  fi
}

# --- t1: new default baseline vs the C10 authority (C10 AC2) ------------------
if want t1; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t1: baseline diff not run (dependency registry unreachable)"
  else
    render_raw "$WORK/default.yaml"
    if python3 - "$WORK/default.yaml" "$PREC10" "$REL" <<'PY'
import re, sys, yaml

render_f, golden_f, rel = sys.argv[1:4]
def bad(msg):
    print(f'FAIL: t1 {msg}', file=sys.stderr)
    sys.exit(1)

docs = [d for d in yaml.safe_load_all(open(render_f)) if isinstance(d, dict)]
golden = [d for d in yaml.safe_load_all(open(golden_f)) if isinstance(d, dict)]

# 1) object set EXACTLY 2 Cluster + 4 ExternalSecret + 1 PVC (C10 AC2).
counts = {}
for d in docs:
    counts[d['kind']] = counts.get(d['kind'], 0) + 1
if counts != {'Cluster': 2, 'ExternalSecret': 4, 'PersistentVolumeClaim': 1}:
    bad(f'default render counts {counts} — expected exactly Cluster:2 + ExternalSecret:4 + PersistentVolumeClaim:1 (postgres + PVC unconditional, container gated off)')
def names(kind):
    return sorted(d['metadata']['name'] for d in docs if d['kind'] == kind)
want_cl = sorted([f'pg-{rel}', f'pg-{rel}-sensors'])
want_es = sorted([rel, f'pg-{rel}-secret', f'pg-{rel}-mcp-secret', f'pg-{rel}-sensors-mcp-secret'])
if names('Cluster') != want_cl:
    bad(f'CNPG Cluster names {names("Cluster")} != {want_cl}')
if names('ExternalSecret') != want_es:
    bad(f'ExternalSecret names {names("ExternalSecret")} != {want_es}')
if names('PersistentVolumeClaim') != [rel]:
    bad(f'PVC names {names("PersistentVolumeClaim")} != [{rel!r}] ({{{{ .Release.Name }}}} derived)')

# The credential ES named <rel> and the release-named PVC SHARE
# metadata.name by C10 design — a name-keyed dict last-wins collides
# them — so every doc lookup below is (kind, name)-scoped.
by_kn = {(d['kind'], d['metadata']['name']): d for d in docs}
gold_by_kn = {(d['kind'], d['metadata']['name']): d for d in golden}

# 2) Cluster docs byte-identical to the pre-C10 golden (AC2: the diff is EMPTY).
for n in want_cl:
    if ('Cluster', n) not in gold_by_kn:
        bad(f'golden has no Cluster {n} — pre-C10 authority malformed')
    a = yaml.safe_dump(gold_by_kn[('Cluster', n)], sort_keys=False, default_flow_style=False, allow_unicode=True)
    b = yaml.safe_dump(by_kn[('Cluster', n)], sort_keys=False, default_flow_style=False, allow_unicode=True)
    if a != b:
        bad(f'Cluster {n} is not byte-identical to the pre-C10 golden — guard removal may not touch the CNPG docs (AC2)')

# 3) ES docs differ from the golden counterpart ONLY by the forced-username/
#    target.template shape: a structural view (names, refresh interval, target
#    Secret, store refs, password refs with username-ish secretKeys stripped)
#    must be equal.
def es_view(d):
    spec = d.get('spec') or {}
    refs = set()
    for e in spec.get('data') or []:
        sk = e.get('secretKey') or ''
        rr = e.get('remoteRef') or {}
        if sk.endswith('username'):
            continue
        refs.add((sk, rr.get('key'), rr.get('property')))
    stores = set()
    ssr = spec.get('secretStoreRef')
    if ssr and ssr.get('name'):
        stores.add(ssr['name'])
    for e in spec.get('data') or []:
        n = (((e.get('sourceRef') or {}).get('storeRef') or {}).get('name'))
        if n:
            stores.add(n)
    tgt = spec.get('target') or {}
    return {'refs': sorted(refs), 'stores': sorted(stores),
            'target': tgt.get('name'), 'creationPolicy': tgt.get('creationPolicy'),
            'refresh': spec.get('refreshInterval')}

for n in want_es:
    if ('ExternalSecret', n) not in gold_by_kn:
        bad(f'rendered ES {n} has no pre-C10 golden counterpart — name drift, not the documented delta')
    if es_view(by_kn[('ExternalSecret', n)]) != es_view(gold_by_kn[('ExternalSecret', n)]):
        bad(f'ES {n} structural view differs from its golden counterpart beyond the forced-username shape: '
            f'render={es_view(by_kn[("ExternalSecret", n)])} golden={es_view(gold_by_kn[("ExternalSecret", n)])}')

# 4) the forcing itself, per C10's mapping table: username literal + password
#    passthrough in target.template (engineVersion v2); spec.data reads ONLY
#    password from the item; NO remoteRef may read a username property.
FORCED = {f'pg-{rel}-secret':        ('username',    'home-assistant', 'password'),
          rel:                        ('pg_username', 'home-assistant', 'pg_password'),
          f'pg-{rel}-mcp-secret':     ('username',    'readonly',       'password'),
          f'pg-{rel}-sensors-mcp-secret': ('username', 'readonly',       'password')}
for n, (ukey, uval, pkey) in FORCED.items():
    d = by_kn[('ExternalSecret', n)]
    tpl = (((d['spec'].get('target') or {}).get('template')) or {})
    if tpl.get('engineVersion') != 'v2':
        bad(f'ES {n} target.template.engineVersion is {tpl.get("engineVersion")!r}, expected v2 (the mcp-secrets pattern copied per C10 Tasks)')
    td = tpl.get('data') or {}
    if td.get(ukey) != uval:
        bad(f'ES {n} must force {ukey!r} = {uval!r}, template.data is {td}')
    pw = td.get(pkey) or ''
    if not re.fullmatch(r'\{\{ \.\w*password\w* \}\}', pw):
        bad(f'ES {n} {pkey} must be the password passthrough template (e.g. {{{{ .password }}}}), got {pw!r}')
    sks = sorted((e.get('secretKey') or '') for e in (d['spec'].get('data') or []))
    if sks != [pkey]:
        bad(f'ES {n} spec.data secretKeys are {sks}, expected exactly [{pkey!r}] — username is FORCED, never read from the item')
    for e in (d['spec'].get('data') or []):
        rr = e.get('remoteRef') or {}
        if rr.get('property') != 'password':
            bad(f'ES {n} reads remoteRef property {rr.get("property")!r} — ONLY the password may come from the Bitwarden item (owner ruling)')

# 5) the always-on PVC: 5Gi, local-path, RWO. Fetched BY KIND (the t2/t5
#    idiom) — its name collides with the credential ES above by design.
pvc = next(d for d in docs if d.get('kind') == 'PersistentVolumeClaim')
pspec = pvc.get('spec') or {}
if ((pspec.get('resources') or {}).get('requests', {}).get('storage')) != '5Gi':
    bad(f'PVC requests {((pspec.get("resources") or {}).get("requests") or {}).get("storage")!r}, expected 5Gi (dig-safe default)')
if pspec.get('storageClassName') != 'local-path':
    bad(f'PVC storageClassName is {pspec.get("storageClassName")!r}, expected local-path')
if pspec.get('accessModes') != ['ReadWriteOnce']:
    bad(f'PVC accessModes {pspec.get("accessModes")!r}, expected [ReadWriteOnce]')
print('ok: t1 — new default baseline: 2 Clusters byte-identical to the pre-C10 golden, 4 ES differing ONLY by the forced-username shape (table pinned), always-on PVC ha-test/5Gi/local-path (C10 AC2)')
PY
    then checks=$((checks + 1)); else fail 't1: the new default baseline is not satisfied (reason printed above)'; fi

    # Authorized re-baseline write (post-C10 only — the structural legs above
    # must be green first; a red tree fails the suite before any write).
    if [ "${HA_RECAPTURE:-0}" = 1 ]; then
      prev='(none)'; [ -f "$NEWGOLDEN" ] && prev=$(sha256sum "$NEWGOLDEN" | awk '{print $1}')
      { printf '# cf-93 C10-era golden (post-delta default render, release %s, normalized by the\n' "$REL"
        printf '# suite pipeline); captured via the AUTHORIZED re-capture flow — see the suite\n'
        printf '# header; the pre-C10 diff authority stays at ha-chart-default-preC10.yaml.\n'
        printf '# previous-file-sha: %s\n' "$prev"
        "$helm_bin" template "$REL" "$COPY" | python3 "$NORMALIZER"; } > "$NEWGOLDEN"
      ok "t1: RECAPTURE (authorized): wrote the new-baseline golden $NEWGOLDEN (previous sha $prev)"
    elif [ -f "$NEWGOLDEN" ]; then
      "$helm_bin" template "$REL" "$COPY" | python3 "$NORMALIZER" > "$WORK/default.norm.yaml"
      if cmp -s "$WORK/default.norm.yaml" <(grep -v '^#' "$NEWGOLDEN") ; then
        ok "t1: render matches the re-captured new-baseline golden $NEWGOLDEN (whole-set equality from C10 onward)"
      else
        diff -u <(grep -v '^#' "$NEWGOLDEN") "$WORK/default.norm.yaml" | head -n 40 >&2
        fail "t1: the default render drifted from the re-captured golden $NEWGOLDEN (structural legs pass; the whole-set cmp is the tighter C10-onward pin)"
      fi
    else
      ok "t1: new-baseline golden $NEWGOLDEN not yet captured — awaiting review's authorized one-shot (HA_RECAPTURE=1 bash tests/multi-repo/ha-chart.sh t1 post-C10); the AC2 diff authority is already green, so this is the designed pending-capture posture, not a gap"
    fi
  fi
fi

# --- t2: container-gate render (C10 AC3) --------------------------------------
if want t2; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t2: dev-mode render not run (dependency registry unreachable)"
  else
    render_raw "$WORK/enabled.yaml" --set homeAssistant.enabled=true
    if python3 - "$WORK/enabled.yaml" "$HA_IMAGE" "$HA_TAG" <<'PY'
import sys, yaml

f, image, tag = sys.argv[1:4]
def bad(msg):
    print(f'FAIL: t2 {msg}', file=sys.stderr)
    sys.exit(1)

docs = [d for d in yaml.safe_load_all(open(f)) if isinstance(d, dict)]
counts = {}
for d in docs:
    counts[d.get('kind')] = counts.get(d.get('kind'), 0) + 1
# The ONLY surviving gate adds EXACTLY Deployment+Service to the always-on
# default set (2 Clusters + 4 ES + 1 PVC — C10 AC3; flags postgres.enabled /
# homeAssistant.persistence.enabled are GONE keys).
want = {'Cluster': 2, 'ExternalSecret': 4, 'PersistentVolumeClaim': 1, 'Deployment': 1, 'Service': 1}
if counts != want:
    bad(f'homeAssistant.enabled=true rendered {counts}, expected exactly {want} (enable-delta = Deployment+Service over the unconditional set)')

dep = next(d for d in docs if d.get('kind') == 'Deployment')
pod = dep['spec']['template']['spec']
cons = pod.get('containers') or []
ha = next((c for c in cons if image in (c.get('image') or '')), None)
if ha is None or ha['image'] != f'{image}:{tag}':
    bad(f'HA container image is {ha and ha["image"]!r}, expected the pinned {image}:{tag} (container block byte-stable)')
envs = sorted((e.get('name') or '') for e in ha.get('env') or [])
if envs != ['TZ']:
    bad(f'container env names are {envs}, expected exactly [TZ] — NO db env (HA integration is owner-side, C10 AC3/ruling 4)')
ports = [p.get('containerPort') for p in ha.get('ports') or []]
if 8123 not in ports:
    bad(f'container ports {ports} lack 8123')
for probe in ('readinessProbe', 'livenessProbe', 'startupProbe'):
    if not ha.get(probe):
        bad(f'HA container lacks {probe}')
sc = ha.get('securityContext') or {}
if (sc.get('capabilities') or {}).get('drop') != ['ALL']:
    bad(f'securityContext.capabilities.drop is {(sc.get("capabilities") or {}).get("drop")!r}, expected [ALL]')
if sc.get('allowPrivilegeEscalation') is not False:
    bad('securityContext.allowPrivilegeEscalation is not false')
mounts = [m for m in ha.get('volumeMounts') or [] if m.get('mountPath') == '/config']
if len(mounts) != 1:
    bad(f'expected exactly one /config mount, got {ha.get("volumeMounts")}')
vol = next((v for v in pod.get('volumes') or [] if v.get('name') == mounts[0].get('name')), None)
claim = ((vol or {}).get('persistentVolumeClaim') or {}).get('claimName')
pvc = next(d for d in docs if d.get('kind') == 'PersistentVolumeClaim')
if claim != pvc['metadata']['name']:
    bad(f'/config volume claimName {claim!r} does not pair with the unconditional PVC {pvc["metadata"]["name"]!r} (existingClaim ↔ PVC law)')

svcs = [d for d in docs if d.get('kind') == 'Service']
if not any(p.get('port') == 8123 for s in svcs for p in (s.get('spec') or {}).get('ports') or []):
    bad('no Service exposes port 8123')
for s in svcs:
    if (s.get('spec') or {}).get('type') not in (None, 'ClusterIP'):
        bad(f'Service {s["metadata"]["name"]} type {s["spec"].get("type")!r} — ClusterIP expected')
kinds = {d.get('kind') for d in docs}
if 'ServiceAccount' in kinds:
    bad('a ServiceAccount rendered — createDefaultServiceAccount suppression must survive the de-gating (C10 AC3)')
print('ok: t2 — enabled render: exactly Deployment+Service beyond the unconditional set; pinned image, TZ-only env (no db wiring), probes, drop-ALL sc, /config↔PVC claim pairing, no ServiceAccount (C10 AC3)')
PY
    then checks=$((checks + 1)); else fail 't2: the container-gate render contract is not satisfied (reason printed above)'; fi
  fi
fi

# --- t3: sentinel-free full render (C10 AC5 render half) ----------------------
if want t3; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t3: full render not run (dependency registry unreachable)"
  else
    "$helm_bin" template "$REL" "$COPY" \
      --set homeAssistant.enabled=true \
      --set domain=test.example.com \
      --set "bitwardenIds.$BW_PG=test-uuid" \
      --set "bitwardenIds.$BW_MCP1=test-uuid" \
      --set "bitwardenIds.$BW_MCP2=test-uuid" \
      >"$WORK/full.yaml" 2>"$WORK/full.err" \
      || { tail -n 30 "$WORK/full.err" >&2; fail "t3: full render failed"; }
    # No postgres.enabled --set anymore — the key is deleted (C10); supplying
    # test values for the three bitwardenIds proves the sentinel-free render
    # (AC5's "proven by feeding test values").
    if grep -q 'OVERRIDE_' "$WORK/full.yaml"; then
      grep -n 'OVERRIDE_' "$WORK/full.yaml" | head >&2
      fail 't3: an OVERRIDE_* sentinel survived the full-feature render — the four ES password refs must consume the supplied bitwardenIds (C10 AC5)'
    fi
    for kind in Cluster ExternalSecret PersistentVolumeClaim Deployment; do
      grep -q "^kind: $kind$" "$WORK/full.yaml" || fail "t3: full render lost kind $kind (the unconditional DB set + always-on PVC + the gated container together form the dev shape)"
    done
    ok "t3: sentinel-free full render (3 test uuids + domain, no postgres/persistence flags) with Cluster+ExternalSecret+PVC+Deployment kinds present (C10 AC5)"
  fi
fi

# --- t4: guard-free static shape (C10 AC1) + version/pin law (C03 AC4/AC5) ----
if want t4; then
  grep -qE '^version: [0-9.]+$' "$CHART/Chart.yaml" || fail "t4: no parsable version line in $CHART/Chart.yaml"
  cur_v=$(grep -m1 -E '^version:' "$CHART/Chart.yaml" | tr -d '[:space:]')
  base_v=$(git show "$(git merge-base HEAD main):$CHART/Chart.yaml" | grep -m1 -E '^version:' | tr -d '[:space:]')
  [ "$cur_v" = "$base_v" ] || fail "t4: Chart.yaml version bumped ($base_v -> $cur_v) — release.yaml owns patch bumps, NEVER hand-bump (version law)"
  ok "t4: Chart.yaml $cur_v matches the fork-point value — no hand-bump (C03 AC4 pin, still live)"

  grep -q '5.0.1' "$CHART/Chart.yaml" || fail "t4: Chart.yaml lacks the app-template 5.0.1 dependency entry"
  grep -q 'bjw-s-labs.github.io/helm-charts' "$CHART/Chart.yaml" || fail "t4: Chart.yaml dependency repository is not the bjw-s-labs repo"
  grep -q 'condition: homeAssistant.enabled' "$CHART/Chart.yaml" \
    || fail "t4: Chart.yaml lost the condition: homeAssistant.enabled line — the container gate is the SURVIVING gate (C10 AC1 wording + Tasks bullet)"
  ok "t4: dependency 5.0.1 + the surviving container-gate condition pinned in Chart.yaml"

  [ -f "$CHART/Chart.lock" ] || fail "t4: $CHART/Chart.lock not committed"
  if grep -Eq '^\s*#\s*dependencies|#version: 4\.3\.0' "$CHART/Chart.yaml" 2>/dev/null && ! grep -qE '^dependencies:' "$CHART/Chart.yaml"; then
    fail "t4: the commented app-template 4.3.0 stub is back in Chart.yaml"
  fi
  ok "t4: Chart.lock committed, 4.3.0 stub absent"

  # AC1 machine shape: values carries NO postgres key and homeAssistant
  # parses to EXACTLY {enabled: false}.
  [ "$(grep -c postgres "$CHART/values.yaml")" = "0" ] \
    || { grep -n postgres "$CHART/values.yaml" >&2; fail "t4: values.yaml still mentions postgres — the postgres: key + comment block are DELETED by C10 (AC1b)"; }
  if python3 - "$CHART/values.yaml" "$CHART/templates" <<'PY'
import glob, os, re, sys, yaml

vals_f, tmpl_dir = sys.argv[1:3]
def bad(msg):
    print(f'FAIL: t4 {msg}', file=sys.stderr)
    sys.exit(1)

v = yaml.safe_load(open(vals_f).read()) or {}
if 'postgres' in v:
    bad('values.yaml still has a top-level postgres: key (AC1b: key deleted)')
ha = v.get('homeAssistant')
if ha != {'enabled': False}:
    bad(f'values homeAssistant block is {ha!r}, expected EXACTLY {{enabled: false}} (persistence subkeys deleted, C10 AC1b)')
# AC1a: no template carries an {{- if gate anymore (pre-state proof: exactly
# 7 gated templates; post-state: zero).
gated = []
for p in sorted(glob.glob(os.path.join(tmpl_dir, '*.yaml'))):
    src = open(p).read()
    if re.search(r'\{\{-?\s*if\b', src):
        gated.append(os.path.basename(p))
if gated:
    bad(f'templates still carrying {{- if }} gates: {gated} (AC1a: ALL zero after guard deletion)')
print('ok: t4-values: zero template gates, postgres key gone, homeAssistant == {enabled: false} (C10 AC1)')
PY
  then checks=$((checks + 1)); else fail "t4: the guard-free values/templates shape is not satisfied (reason printed above)"; fi

  grep -q "$HA_IMAGE" "$CHART/values.yaml" || fail "t4: values.yaml does not reference $HA_IMAGE"
  grep -q "$HA_TAG" "$CHART/values.yaml" || fail "t4: values.yaml does not pin tag $HA_TAG (C03 AC5 pin, still live — container block byte-stable)"
  ok "t4: values image literals kept ($HA_IMAGE : $HA_TAG)"

  if [ "$skip_render" -eq 1 ]; then
    skip "t4: lint/dependency-list legs not run (dependency registry unreachable)"
  else
    lint_log="$WORK/lint.log"
    (cd "$COPY" && "$helm_bin" lint .) >"$lint_log" 2>&1 || { tail -n 30 "$lint_log" >&2; fail "t4: helm lint failed for $CHART (log $lint_log)"; }
    ok "t4: helm lint passes ($("$helm_bin" version --short 2>/dev/null || echo helm))"
    deps="$WORK/dep-list.txt"
    "$helm_bin" dependency list "$COPY" >"$deps" 2>&1 || fail "t4: helm dependency list failed"
    # helm's status vocabulary is ok|missing|outdated (verified against helm
    # 3.16.4); the `ok` row is what AC4's "dependency list OK" means.
    grep -E '^app-template\s+5\.0\.1\s+https://bjw-s-labs\.github\.io/helm-charts/\s+ok\s*$' "$deps" >/dev/null \
      || { cat "$deps" >&2; fail "t4: helm dependency list lacks an app-template 5.0.1 row with status ok (missing/outdated/absent all fail — C10 AC6 keeps the dep intact)"; }
    ok "t4: helm dependency list shows app-template 5.0.1 ok (Chart.lock consistent)"
  fi
fi

# --- t5: grow-slice render — the live release shape (C10 AC4) -----------------
if want t5; then
  if [ "$skip_render" -eq 1 ]; then
    skip "t5: grow-slice render not run (dependency registry unreachable)"
  else
    python3 - <<'PY' || fail "t5: could not extract the grow assistant slice (schema drift in services/grow or custom-values/grow?)"
import re, sys, yaml

# Anchor-stripping loader (values files use YAML anchors; placeholder values
# are never asserted — dev-forgejo loader precedent).
def load(path):
    lines = []
    for line in open(path):
        line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
        line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
        lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

merged = {}
grow = load('services/grow/prod/values.yaml')
# The grow release's chart values flow from the top-level `assistant:` slice
# merged with custom-values/grow `assistant:` (the real bitwardenIds).
top = grow.get('assistant')
if isinstance(top, dict):
    merged.update(top)
cv = load('custom-values/grow/prod-values.yaml')
cv_a = cv.get('assistant')
if not isinstance(cv_a, dict):
    print('FAIL: t5 custom-values/grow/prod-values.yaml has no top-level assistant: block — grow would render no real bitwardenIds', file=sys.stderr)
    sys.exit(1)
merged = {**merged, **cv_a}
# C10 grow posture: the slice must NOT have grown any postgres/persistence
# keys either (grow files are byte-untouched by C10 — AC4).
yaml.safe_dump(merged, open('/tmp/opencode/ha-chart-grow-slice.yaml', 'w'), sort_keys=False)
PY
    if "$helm_bin" template assistant "$COPY" -f /tmp/opencode/ha-chart-grow-slice.yaml --set domain=test.example.com >"$WORK/grow.yaml" 2>"$WORK/grow.err"; then
      if python3 - "$WORK/grow.yaml" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if isinstance(d, dict)]
def bad(msg):
    print(f'FAIL: t5 {msg}', file=sys.stderr)
    sys.exit(1)

raw = open(sys.argv[1]).read()
counts = {}
for d in docs:
    counts[d.get('kind')] = counts.get(d.get('kind'), 0) + 1
# C10 AC4: grow keeps rendering the FULL always-on DB set (now unconditional)
# plus the new PVC — and still NO Deployment (the surviving container gate,
# grow's HA being EXTERNAL).
if counts.get('Cluster', 0) != 2:
    bad(f'grow slice rendered {counts.get("Cluster", 0)} CNPG Clusters, expected 2 (assistant + sensors) — unconditional post-C10')
if counts.get('ExternalSecret', 0) != 4:
    bad(f'grow slice rendered {counts.get("ExternalSecret")} ExternalSecrets, expected exactly 4')
if counts.get('PersistentVolumeClaim', 0) != 1:
    bad(f'grow slice rendered {counts.get("PersistentVolumeClaim")} PVCs, expected exactly 1 (the always-on /config claim — the owner-accepted grow consequence)')
if counts.get('Deployment'):
    bad('grow slice rendered a Deployment — the homeAssistant.enabled container gate must still keep the HA container OFF for grow (C10 interpretation statement; AC4)')
pvc = next(d for d in docs if d.get('kind') == 'PersistentVolumeClaim')
if pvc['metadata']['name'] != 'assistant':
    bad(f'grow PVC named {pvc["metadata"]["name"]!r}, expected the release name assistant')
if 'OVERRIDE_' in raw:
    bad('the grow-slice render carries an OVERRIDE_* sentinel — grow custom-values supply real UUIDs, nothing may leak')
print('ok: t5 — grow shape: 2 Clusters + 4 ExternalSecrets + the new always-on PVC, NO Deployment, no sentinels (C10 AC4)')
PY
      then checks=$((checks + 1)); else fail 't5: the grow-shape contract is not satisfied (reason printed above)'; fi
    else
      tail -n 30 "$WORK/grow.err" >&2
      fail "t5: helm template of the grow slice failed (stderr $WORK/grow.err)"
    fi
  fi
fi

printf 'PASS: cf-93 ha-chart contract at the C10 baseline (%d ok)\n' "$checks"
