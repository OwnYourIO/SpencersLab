#!/usr/bin/env bash
# C01 + C02 acceptance checks (2026-11-cf-156 feat-actual-budget-mcp-server):
# the wuulf-budget third Actual Budget instance (C01 — the service-trio mirror
# of the live bri-budget precedent, plus the R2 criterion: wuulf comes up
# WITHOUT the broken 01-enable-openid initContainer that lives only in the
# umbrella's own actualbudget: block, while the chart's SSO envFrom wiring
# and both existing instances stay untouched) and the s-stefanov/actual-mcp
# ToolHive server on home (C02 — read-only tier BY THE ABSENCE of
# --enable-write, the SPLIT credential sentinels with 1:1 UUID mirrors, the
# wuulf in-cluster URL, the deliberate ACTUAL_BUDGET_SYNC_ID absence).
#
# Hermetic (C01/C02 Tests): greps + python3/PyYAML structure asserts only;
# no cluster access, no helm in this suite. The render checks (C01 AC1/AC5,
# C02 AC1/AC2 — the wuulf chart render, the hivetools render per the
# mcp-servers.md Validation recipe) are plan Commands run by dev/review and
# quoted in commands_run — the home-dead-image-refs.sh division of labor.
# There is no docker-build leg in this plan (upstream image), so no check
# references a build gate.
#
# Unpinned by design (the 0.4.2 stale-pin lesson, DECISIONS 2026-11-24):
# the s-stefanov image tag is asserted by FORMAT only (the exact image name
# + a non-empty, non-rolling tag — never a tag value, which is the dev-time
# live registry query); the Bitwarden UUIDs are asserted by FORM (8-4-4-4-4
# hex) and the count-based 1:1 sentinel<->custom-values pairing, never a
# specific UUID value.
#
# The proxy-local values define the YAML anchor `port` twice (qbittorrent 8080
# + the backup entry's 80): legal YAML, which PyYAML refuses; this suite
# tolerates redefinitions (last definition wins, as lenient parsers do).
#
# Each check prints one pass/fail line; any fail makes the script exit
# non-zero. Run from anywhere in the worktree:
#   bash tests/services/actual-budget-wuulf-mcp.sh

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

HOMEV="services/home/prod/values.yaml"
CV="custom-values/home/prod-values.yaml"
PL="services/proxy-local/prod/values.yaml"
PR="services/proxy-remote/prod/values.yaml"
CHART="charts/actualbudget/values.yaml"

for f in "$HOMEV" "$CV" "$PL" "$PR" "$CHART"; do
  [ -f "$f" ] || { echo "fail: precondition: $f is missing"; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "fail: precondition: python3 with PyYAML is unavailable"; exit 1; }

WORK=$(mktemp -d /tmp/opencode/actual-budget-wuulf-mcp.XXXXXX) || { echo "fail: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/lines.log"
: > "$LOG"

pass() { printf 'pass: %s\n' "$1" | tee -a "$LOG"; }
fail() { printf 'fail: %s\n' "$1" | tee -a "$LOG"; }

# want_count <needle> <file> <n> <label> — literal fixed-string count.
want_count() {
  local n
  n=$(grep -cF -- "$1" "$2" 2>/dev/null || true)
  if [ "${n:-0}" -eq "$3" ]; then
    pass "$4 (count $n == $3)"
  else
    fail "$4 (count ${n:-0}, want $3; needle: $1 in $2)"
  fi
}

# want_min <needle> <file> <n> <label> — literal fixed-string count >= n (the
# chunk's s4 SSO envFrom grep is ">= 1", so a second wiring may not fail it).
want_min() {
  local n
  n=$(grep -cF -- "$1" "$2" 2>/dev/null || true)
  if [ "${n:-0}" -ge "$3" ]; then
    pass "$4 (count $n >= $3)"
  else
    fail "$4 (count ${n:-0}, want >= $3; needle: $1 in $2)"
  fi
}

# --- s4 shell legs [C01 AC2/R2 — the plan Commands R2 validation line] -------
# The broken 01-enable-openid step must not migrate into the shared chart
# (a future chart change adding initContainers is the recorded R2 fallback);
# the SSO envFrom wiring the chart-field copy inherits must stay.
want_count 'enable-openid' "$CHART" 0 's4 [R2]: charts/actualbudget values carry no enable-openid reference (the broken step lives only in the umbrella block)'
want_min 'name: "actualbudget-sso-secret"' "$CHART" 1 's4 [R2]: the SSO envFrom wiring wuulf inherits (secretRef -> actualbudget-sso-secret) is present in the chart values'

# --- s1-s7: python structure asserts ------------------------------------------
python3 - "$HOMEV" "$CV" "$PL" "$PR" "$CHART" 2>>"$LOG" <<'PY' | tee -a "$LOG"
import os, re, sys, yaml
from yaml.events import AliasEvent, ScalarEvent, SequenceStartEvent, MappingStartEvent

homev, cvp, plp, prp, chartv = sys.argv[1:6]

def ok(msg):
    print(f'pass: {msg}')

def bad(msg):
    print(f'fail: {msg}')

SENTINEL = 'OVERRIDE_VIA_CUSTOM_VALUES'
UUID_RE = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')

# Tolerant of duplicate anchor definitions (see header). Everything else is
# the SafeLoader behaviour, so it is safe for all five files.
class TolerantLoader(yaml.SafeLoader):
    def compose_node(self, parent=None, index=None):
        if self.check_event(AliasEvent):
            event = self.get_event()
            anchor = event.anchor
            if anchor not in self.anchors:
                raise yaml.composer.ComposerError(None, None, "found undefined alias %r" % anchor, event.start_mark)
            return self.anchors[anchor]
        event = self.peek_event()
        anchor = event.anchor
        self.descend_resolver(parent, index)
        if self.check_event(ScalarEvent):
            node = self.compose_scalar_node(anchor)
        elif self.check_event(SequenceStartEvent):
            node = self.compose_sequence_node(anchor)
        elif self.check_event(MappingStartEvent):
            node = self.compose_mapping_node(anchor)
        self.ascend_resolver()
        return node

def load(path):
    try:
        d = yaml.load(open(path), Loader=TolerantLoader)
    except Exception as ex:
        bad(f'precondition: {path} does not parse ({ex}) — its checks are unassessable')
        return None
    if not isinstance(d, dict):
        bad(f'precondition: {path} did not parse to a mapping')
        return None
    return d

def find_keys(obj, key):
    out = []
    if isinstance(obj, dict):
        if key in obj:
            out.append(obj)
        for v in obj.values():
            out.extend(find_keys(v, key))
    elif isinstance(obj, list):
        for v in obj:
            out.extend(find_keys(v, key))
    return out

home = load(homev)
cv = load(cvp)
pl = load(plp)
pr = load(prp)
chart = load(chartv)

# --- s1 [C01 AC1/AC3]: the three home service values entries -----------------
if home is not None:
    w = (home.get('charts') or {}).get('wuulf-budget')
    if not isinstance(w, dict):
        bad('s1 [AC1/AC3]: charts.wuulf-budget entry missing from the home service values')
    else:
        diffs = [f'{k}: got {w.get(k)!r}, want {v!r}' for k, v in
                (('chart', 'actualbudget'), ('ServerSideApply', 'true'), ('namespace', 'default'))
                if w.get(k) != v]
        if diffs:
            bad('s1 [AC1/AC3]: charts.wuulf-budget entry shape wrong — ' + '; '.join(diffs))
        else:
            ok('s1 [AC1/AC3]: charts.wuulf-budget is the actualbudget chart: entry (namespace default, ServerSideApply "true")')

    s = ((home.get('ingress') or {}).get('subdomains') or {}).get('wuulf-budget')
    if not isinstance(s, dict):
        bad('s1 [AC3]: ingress.subdomains.wuulf-budget entry missing from the home service values')
    else:
        diffs = [f'{k}: got {s.get(k)!r}, want {v!r}' for k, v in
                (('service', 'home-wuulf-budget'), ('port', 5006)) if s.get(k) != v]
        if diffs:
            bad('s1 [AC3]: ingress.subdomains.wuulf-budget shape wrong — ' + '; '.join(diffs))
        else:
            ok('s1 [AC3]: ingress.subdomains.wuulf-budget points at service home-wuulf-budget port 5006')

    b = home.get('wuulf-budget')
    at = ((b or {}).get('app-template') or {}).get('global') or {} if isinstance(b, dict) else {}
    if at.get('nameOverride') == 'wuulf-budget':
        ok('s1 [AC1]: the top-level wuulf-budget app-template block sets global.nameOverride wuulf-budget')
    else:
        bad(f's1 [AC1]: top-level wuulf-budget app-template block missing or wrong (nameOverride got {at.get("nameOverride")!r}, want "wuulf-budget")')
else:
    bad('s1: unassessable — the home service values did not parse (see precondition fail above)')

# --- s2 [C01 AC3]: the proxy pair --------------------------------------------
if pl is not None:
    e = ((pl.get('proxy') or {}).get('subdomains') or {}).get('wuulf-budget')
    if not isinstance(e, dict):
        bad('s2 [AC3]: proxy-local proxy.subdomains.wuulf-budget entry missing')
    else:
        diffs = []
        if e.get('target') != 'wuulf-budget':
            diffs.append(f'target: got {e.get("target")!r}, want "wuulf-budget"')
        path_ = e.get('ssoRedirectPath') or ''
        if 'client_id=actualbudget' not in path_:
            diffs.append('ssoRedirectPath lacks client_id=actualbudget')
        if 'wuulf-budget' not in path_:
            diffs.append('ssoRedirectPath carries no wuulf-budget redirect URI')
        if e.get('loginSubDomain') != 'login':
            diffs.append(f'loginSubDomain: got {e.get("loginSubDomain")!r}, want "login"')
        if diffs:
            bad('s2 [AC3]: proxy-local wuulf-budget entry shape wrong — ' + '; '.join(diffs))
        else:
            ok('s2 [AC3]: proxy-local wuulf-budget carries the actualbudget SSO redirect (client_id=actualbudget, the wuulf redirect URI) with target + loginSubDomain login')

if pr is not None:
    e = ((pr.get('proxy') or {}).get('subdomains') or {}).get('wuulf-budget')
    if isinstance(e, dict) and e.get('enabled') is True:
        ok('s2 [AC3]: proxy-remote wuulf-budget is enabled: true')
    else:
        bad(f's2 [AC3]: proxy-remote wuulf-budget missing or not enabled: true (got {e!r})')

if pl is None:
    bad('s2: unassessable — the proxy-local values did not parse (see precondition fail above)')
if pr is None:
    bad('s2: unassessable — the proxy-remote values did not parse (see precondition fail above)')

# --- s3 [C01 AC4]: the 1:1 sentinel<->custom-values pairing for wuulf --------
if cv is not None and home is not None:
    v = ((cv.get('wuulf-budget') or {}).get('bitwardenIds') or {}).get('actualbudget-sso-secret')
    if isinstance(v, str) and UUID_RE.fullmatch(v) and v != SENTINEL:
        ok('s3 [AC4]: custom-values wuulf-budget.bitwardenIds.actualbudget-sso-secret is a UUID-form value (not a sentinel)')
    else:
        bad(f's3 [AC4]: custom-values wuulf-budget.bitwardenIds.actualbudget-sso-secret got {v!r}, want a UUID-form non-sentinel value')

    t = (home.get('bitwardenIds') or {}).get('actualbudget-sso-secret')
    if t == SENTINEL:
        ok('s3 [AC4]: the pre-existing top-level bitwardenIds.actualbudget-sso-secret sentinel exists in the home service values (the 1:1 counterpart)')
    else:
        bad(f's3 [AC4]: the top-level bitwardenIds.actualbudget-sso-secret sentinel is missing or not a sentinel (got {t!r})')
elif cv is None or home is None:
    bad('s3: unassessable — one of custom-values / the home service values did not parse (see precondition fail above)')

# --- s4 [C01 AC2/R2]: the initContainer criterion, per-instance by ----------
# construction: the shared chart clean, the wuulf blocks clean, the umbrella
# block's broken step still present (untouched), bri-budget untouched.
if chart is not None:
    n = len(find_keys(chart, 'initContainers'))
    if n == 0:
        ok('s4 [R2]: the charts/actualbudget value tree carries no initContainers key anywhere (the chart-field copy inherits none)')
    else:
        bad(f's4 [R2]: the charts/actualbudget value tree carries {n} initContainers key(s) — a future chart change must not add one to wuulf (the recorded R2 fallback fires)')
if home is not None:
    wch = (home.get('charts') or {}).get('wuulf-budget')
    if isinstance(wch, dict):
        n = len(find_keys(wch, 'initContainers'))
        if n == 0:
            ok('s4 [R2]: the charts.wuulf-budget entry carries no initContainers key')
        else:
            bad(f's4 [R2]: the charts.wuulf-budget entry carries {n} initContainers key(s)')
    else:
        bad('s4 [R2]: unassessable — charts.wuulf-budget entry missing (see s1)')

    wb = home.get('wuulf-budget')
    if isinstance(wb, dict):
        n = len(find_keys(wb, 'initContainers'))
        if n == 0:
            ok('s4 [R2]: the wuulf-budget app-template block carries no initContainers key (the broken 01-enable-openid step stays out of wuulf)')
        else:
            bad(f's4 [R2]: the wuulf-budget app-template block carries {n} initContainers key(s) — the R2 criterion fails')
    else:
        bad('s4 [R2]: unassessable — the wuulf-budget block is missing (see s1)')

    ic = (((home.get('actualbudget') or {}).get('controllers') or {}).get('actual') or {}).get('initContainers') or {}
    args = ic.get('01-enable-openid', {}).get('args') if isinstance(ic.get('01-enable-openid'), dict) else None
    if isinstance(args, list) and any('enable-openid' in a for a in args):
        ok('s4 [R2]: the umbrella actualbudget block STILL carries the 01-enable-openid initContainer (the per-instance fix must not have touched instance 1)')
    else:
        bad('s4 [R2]: the umbrella actualbudget block lost its 01-enable-openid initContainer — the fix must stay per-instance (instance 1 untouched)')

    bb = home.get('bri-budget')
    if isinstance(bb, dict):
        no_ic = len(find_keys(bb, 'initContainers')) == 0
        no_override = ((bb.get('app-template') or {}).get('global') or {}).get('nameOverride') == 'bri-budget'
        if no_ic and no_override:
            ok('s4 [R2]: the bri-budget block is untouched (nameOverride intact, no initContainers — instance 2 unchanged)')
        else:
            bad(f's4 [R2]: the bri-budget block drifted (no-initContainers {no_ic}, nameOverride intact {no_override})')
    else:
        bad('s4 [R2]: the bri-budget block is missing — regression')
if chart is None:
    bad('s4: unassessable — the chart values did not parse (see precondition fail above)')

# --- s5 [C02 AC1/AC4/AC5 + file presence]: the mcp.actual-budget entry ------
def file_check(path, label, needles):
    if not os.path.isfile(path):
        bad(f'{label}: {path} is missing')
        return
    text = open(path).read()
    missing = [n for n in needles if n not in text]
    if missing:
        bad(f'{label}: {path} lacks: {", ".join(missing)}')
    else:
        ok(f'{label}: {path} present with the {len(needles)} boilerplate markers (the bitwarden-login store ref + the conversion/decoding/metadataPolicy lines that keep ArgoCD quiet)')

if home is not None:
    e = ((home.get('hivetools') or {}).get('mcp') or {}).get('actual-budget')
    if not isinstance(e, dict):
        bad('s5 [AC1/AC4]: hivetools.mcp.actual-budget entry missing from the home service values')
    else:
        if e.get('enabled') is True:
            ok('s5 [AC1]: mcp.actual-budget is enabled: true')
        else:
            bad(f's5 [AC1]: mcp.actual-budget enabled got {e.get("enabled")!r}, want true')

        # FORMAT only — the tag VALUE is the dev-time live Docker Hub query
        # (the 0.4.2 lexicographic lesson); pinning a value here would
        # re-create the stale-pin bug.
        img = e.get('image')
        m = re.fullmatch(r'sstefanov/actual-mcp:([A-Za-z0-9][A-Za-z0-9._-]*)', img) if isinstance(img, str) else None
        if not m:
            bad(f's5 [AC4]: image got {img!r}, want sstefanov/actual-mcp:<pinned-tag>')
        elif m.group(1) in ('latest', 'main'):
            bad(f's5 [AC4]: image tag {m.group(1)!r} is a rolling alias — the pin must be a concrete version tag')
        else:
            ok(f's5 [AC4]: image is sstefanov/actual-mcp:{m.group(1)} — a pinned non-rolling tag (format asserted; the value is the live registry query)')

        if e.get('transport') == 'streamable-http':
            ok('s5 [AC1]: transport is streamable-http')
        else:
            bad(f's5 [AC1]: transport got {e.get("transport")!r}, want streamable-http')

        args = e.get('args') or []
        if not isinstance(args, list):
            args = [args]
        if '--sse' not in args:
            bad(f's5 [AC1]: args lack --sse (got {args})')
        else:
            ok('s5 [AC1]: args carry --sse')
        if '--enable-bearer' not in args:
            bad(f's5 [AC1]: args lack --enable-bearer (got {args})')
        else:
            ok('s5 [AC1]: args carry --enable-bearer')
        if '--enable-write' in args:
            bad('s5 [AC5]: args carry --enable-write — the first tier is read-only BY THE ABSENCE of this flag (the owner ruling); it must not be present')
        else:
            ok('s5 [AC5]: args lack --enable-write — the read-only tier boundary holds')

        env = e.get('env')
        envmap = {}
        if isinstance(env, list):
            for it in env:
                if isinstance(it, dict) and 'name' in it:
                    envmap[it['name']] = it.get('value')
        elif isinstance(env, dict):
            envmap = env

        su = envmap.get('ACTUAL_SERVER_URL')
        if isinstance(su, str) and 'home-wuulf-budget.default.svc:5006' in su:
            ok('s5 [AC4]: ACTUAL_SERVER_URL resolves to the C01 in-cluster service (home-wuulf-budget.default.svc:5006)')
        else:
            bad(f's5 [AC4]: ACTUAL_SERVER_URL got {su!r}, want a value resolving to home-wuulf-budget.default.svc:5006')

        dd = envmap.get('ACTUAL_DATA_DIR')
        pts = (e.get('podTemplateSpec') or {}).get('spec') or {}
        containers = [c for c in (pts.get('containers') or []) if isinstance(c, dict)]
        mcp_c = [c for c in containers if c.get('name') == 'mcp']
        if not mcp_c:
            bad('s5 [AC4]: no container named mcp in podTemplateSpec — the ToolHive contract names the override container mcp')
        elif isinstance(dd, str):
            mounts = [vm for c in mcp_c for vm in (c.get('volumeMounts') or []) if isinstance(vm, dict)]
            match = [vm for vm in mounts if vm.get('mountPath') == dd]
            vols = [v for v in (pts.get('volumes') or []) if isinstance(v, dict)]
            if not match:
                bad(f's5 [AC4]: ACTUAL_DATA_DIR {dd!r} matches no volumeMount mountPath (mounts: {[vm.get("mountPath") for vm in mounts]})')
            else:
                vn = match[0].get('name')
                is_pvc = any(v.get('name') == vn and isinstance(v.get('persistentVolumeClaim'), dict) for v in vols)
                if is_pvc:
                    ok(f's5 [AC4]: ACTUAL_DATA_DIR {dd!r} equals the data volume mount path, and that volume is a persistentVolumeClaim (the 5Gi cache PVC)')
                else:
                    bad(f's5 [AC4]: the volume {vn!r} mounted at {dd!r} is not a persistentVolumeClaim entry')
        else:
            bad(f's5 [AC4]: ACTUAL_DATA_DIR env missing or not a string (got {dd!r})')

        if mcp_c:
            sc = mcp_c[0].get('securityContext') or {}
            # The repo-standard security floor (helm-chart-creation: every
            # container drops ALL capabilities); the runAsUser derivation is a
            # dev-time image check (C02 Notes item 4), deliberately not pinned.
            caps = ((sc.get('capabilities') or {}).get('drop') or [])
            if sc.get('allowPrivilegeEscalation') is False and 'ALL' in caps:
                ok('s5 [repo-standard]: the mcp container carries the security floor (allowPrivilegeEscalation false, capabilities drop ALL)')
            else:
                bad(f's5 [repo-standard]: the mcp container securityContext lacks the floor (got {sc!r})')

        sec = e.get('secrets')
        if not isinstance(sec, list) or len(sec) != 2:
            bad(f's5 [AC3/AC4]: secrets must be exactly one entry per credential item (2); got {sec!r}')
        else:
            smap = {it.get('name'): it for it in sec if isinstance(it, dict)}
            want = {
                'actual-budget-mcp': ('BEARER_TOKEN', 'BEARER_TOKEN'),
                'actual-budget-mcp-key': ('ACTUAL_SESSION_TOKEN', 'ACTUAL_SESSION_TOKEN'),
            }
            diffs = []
            for name, (key, tenv) in want.items():
                it = smap.get(name)
                if not isinstance(it, dict):
                    diffs.append(f'{name} entry missing')
                elif it.get('key') != key:
                    diffs.append(f'{name}.key got {it.get("key")!r}, want {key!r}')
                elif it.get('targetEnvName') != tenv:
                    diffs.append(f'{name}.targetEnvName got {it.get("targetEnvName")!r}, want {tenv!r}')
            extra = sorted(set(smap) - set(want))
            if extra:
                diffs.append(f'unexpected extra secret entries: {extra}')
            if diffs:
                bad('s5 [AC3/AC4]: the secrets wiring is wrong — ' + '; '.join(diffs))
            else:
                ok('s5 [AC3/AC4]: secrets carry exactly one entry per item — actual-budget-mcp -> BEARER_TOKEN, actual-budget-mcp-key -> ACTUAL_SESSION_TOKEN (the SPLIT credential, the API-key slot for the 26.12+ key)')

    # File presence (the C02 new templates): ExternalSecret boilerplate per the
    # wekan-mcp shape; the PVC template by presence (its shape is the plan's
    # dev task, its name is the contract).
    if home is not None:
        file_check('services/home/prod/templates/secret-actual-budget-mcp.yaml', 's5 [AC3]',
                   ['name: bitwarden-login', 'conversionStrategy: Default', 'decodingStrategy: None', 'metadataPolicy: None'])
        file_check('services/home/prod/templates/secret-actual-budget-mcp-key.yaml', 's5 [AC3]',
                   ['name: bitwarden-login', 'conversionStrategy: Default', 'decodingStrategy: None', 'metadataPolicy: None'])
        if os.path.isfile('services/home/prod/templates/pvc-actual-budget-mcp-default.yaml'):
            ok('s5 [AC3]: the pvc-actual-budget-mcp-default.yaml template exists (the 5Gi data PVC)')
        else:
            bad('s5 [AC3]: services/home/prod/templates/pvc-actual-budget-mcp-default.yaml is missing')
else:
    bad('s5: unassessable — the home service values did not parse (see precondition fail above)')

# --- s6 [C02 AC3]: the 1:1 sentinel<->custom-values pairing, both items -----
if home is not None and cv is not None:
    tb = home.get('bitwardenIds') or {}
    sentinels = {k for k, v in tb.items() if v == SENTINEL}
    missing = [k for k in ('actual-budget-mcp', 'actual-budget-mcp-key') if k not in sentinels]
    if missing:
        bad(f's6 [AC3]: the top-level sentinels for {missing} are missing from the home service values bitwardenIds')
    else:
        ok('s6 [AC3]: both actual-budget-mcp and actual-budget-mcp-key top-level sentinels exist in the home service values')

    cvb = cv.get('bitwardenIds') or {}
    uuids = {k for k, v in cvb.items() if isinstance(v, str) and UUID_RE.fullmatch(v) and v != SENTINEL}
    unmirrored = sorted(sentinels - uuids)
    if unmirrored:
        bad(f's6 [AC3]: sentinels without a UUID-form custom-values mirror (count-based 1:1 broken — a third unmirrored sentinel fails here): {unmirrored}')
    else:
        ok(f's6 [AC3]: every one of the {len(sentinels)} home top-level sentinels has a UUID-form mirror in custom-values (count-based 1:1)')

    diffs = []
    for k in ('actual-budget-mcp', 'actual-budget-mcp-key'):
        v = cvb.get(k)
        if not (isinstance(v, str) and UUID_RE.fullmatch(v) and v != SENTINEL):
            diffs.append(f'custom-values bitwardenIds.{k} got {v!r}, want a UUID-form non-sentinel value')
    if diffs:
        bad('s6 [AC3]: ' + '; '.join(diffs))
    else:
        ok('s6 [AC3]: both credential UUIDs in custom-values are UUID-form, not sentinels (the 1:1 pair, both mirrored)')
elif home is None or cv is None:
    bad('s6: unassessable — one of the home service values / custom-values did not parse (see precondition fail above)')

# --- s7 [C02 Notes]: ACTUAL_BUDGET_SYNC_ID is deliberately absent -----------
if home is not None:
    e = ((home.get('hivetools') or {}).get('mcp') or {}).get('actual-budget')
    if not isinstance(e, dict):
        bad('s7: unassessable — hivetools.mcp.actual-budget entry missing (see s5)')
    else:
        env = e.get('env')
        names = []
        if isinstance(env, list):
            names = [it.get('name') for it in env if isinstance(it, dict)]
        elif isinstance(env, dict):
            names = list(env)
        if 'ACTUAL_BUDGET_SYNC_ID' in names:
            bad('s7 [Notes]: ACTUAL_BUDGET_SYNC_ID is set — it must be deliberately ABSENT (single-budget server; the key per-budget file grant selects wuulf)')
        else:
            ok('s7 [Notes]: ACTUAL_BUDGET_SYNC_ID is absent from the entry env (single-budget server; budget selection rides the key grant)')
else:
    bad('s7: unassessable — the home service values did not parse (see precondition fail above)')
PY
py_rc=${PIPESTATUS[0]}
if [ "$py_rc" -ne 0 ]; then
  fail "s1-s7: the python assert block exited $py_rc (see stderr above) — counted as a failure, not a skip"
fi

# --- final tally ------------------------------------------------------------
PASS=$(grep -c '^pass: ' "$LOG" || true)
FAIL=$(grep -c '^fail: ' "$LOG" || true)
printf '=== actual-budget-wuulf-mcp: %s passed, %s failed ===\n' "${PASS:-0}" "${FAIL:-0}"
[ "${FAIL:-1}" -eq 0 ] || exit 1
exit 0
