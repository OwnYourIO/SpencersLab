#!/usr/bin/env bash
# C01 + C02 + C03 acceptance checks (2026-11-cf-156 feat-actual-budget-mcp-server):
# the wuulf-budget third Actual Budget instance (C01 — the service-trio mirror
# of the live bri-budget precedent, plus the R2 criterion: wuulf comes up
# WITHOUT the broken 01-enable-openid initContainer that lives only in the
# umbrella's own actualbudget: block, while the chart's SSO envFrom wiring
# and both existing instances stay untouched), the s-stefanov/actual-mcp
# ToolHive server on home (C02 — read-only tier BY THE ABSENCE of
# --enable-write, the SPLIT credential, the wuulf in-cluster URL, the
# deliberate ACTUAL_BUDGET_SYNC_ID absence), and the 2026-11-26 owner rework
# (C03 — wuulf NO LONGER on proxy-remote: s2 flipped to an absence assert;
# the two credential ExternalSecret templates + the data PVC MOVED into
# charts/actualbudget/templates/ behind the per-instance mcp.enabled gate
# (chart default false, true ONLY in the wuulf block) with release-prefixed
# {{ .Release.Name }}-mcp-* names + deletionPolicy Delete, the bitwardenIds
# sentinels MOVED into the chart and the real owner-minted UUIDs landed at
# the custom-values TOP level: s6 re-pinned to the chart sentinel source,
# both files 1:1 and GREEN). The designed 29/2 red shape is RETIRED by C03:
# this suite is expected to end 0 failures once C03 lands.
#
# Re-pinned 2026-11-26 by a FRESH Test Writing session (C03 round): s2/s5/s6
# re-pinned to the owner rework, s1/s3/s4/s7 preserved verbatim.
#
# Hermetic (C01/C02/C03 Tests): greps + python3/PyYAML structure asserts only;
# no cluster access, no helm in this suite. The render checks (C01 AC1/AC5,
# C02 AC1/AC2, the C03 three-way + collision-safety renders) are plan
# Commands run by dev/review and quoted in commands_run — the
# home-dead-image-refs.sh division of labor.
# There is no docker-build leg in this plan (upstream image), so no check
# references a build gate.
#
# Unpinned by design (the 0.4.2 stale-pin lesson, DECISIONS 2026-11-24):
# the s-stefanov image tag is asserted by FORMAT only (the exact image name
# + a non-empty, non-rolling tag — never a tag value, which is the dev-time
# live registry query); the Bitwarden UUIDs are asserted by FORM (8-4-4-4-4
# hex) and the count-based 1:1 sentinel<->custom-values pairing, never a
# specific UUID value — the owner-minted UUID values themselves are proven by
# the C03 plan-Commands render (the real UUID resolved through the
# custom-values injection path).
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

# want_dir_regex <regex> <dir> <n> <label> — extended-regex match-line count
# across a directory tree (the s6 stale-name sweep). A missing directory is
# a fail, not a silent 0 (the sweep must not pass on a tree that cannot be
# read). The regex matches the OLD item names at a non-dash boundary (so the
# C03-kept pod-local volume name actual-budget-mcp-data is not a false hit),
# the OLD key item name, and the OLD claimName reference (renamed by C03).
want_dir_regex() {
  [ -d "$2" ] || { fail "$4 (directory $2 is missing — the sweep is unassessable)"; return; }
  local n
  n=$(grep -rnE -- "$1" "$2" 2>/dev/null | wc -l)
  if [ "${n:-0}" -eq "$3" ]; then
    pass "$4 (count $n == $3)"
  else
    fail "$4 (count ${n:-0}, want $3; regex: $1 in $2)"
  fi
}

# --- s2 shell leg [C03 AC5 — the plan Commands changed leg] -----------------
# wuulf is no longer exposed on proxy-remote (the 2026-11-26 owner
# instruction): the string must be absent from the file at ANY position, so a
# re-added entry fails even outside proxy.subdomains. The unreadable-file
# guard is the s2 python leg below (a parse failure is a fail, not a pass).
want_count 'wuulf-budget' "$PR" 0 's2 [C03]: the string wuulf-budget is absent from the proxy-remote values file (a re-added entry fails)'

# --- s6 shell legs [C03 AC4/AC5 — the stale-name + no-sentinel sweep] ------
# The owner rename (actual-budget-mcp / actual-budget-mcp-key ->
# actualbudget-mcp-bearer / actualbudget-mcp-key): a stale reference must
# not survive anywhere in the tracked service / chart / custom-values
# surface — the C02 standing-constraint comment, the old top-level
# sentinels, the hivetools entry names, the old claimName, the old template
# files all carry the old names. The C03-kept pod-local volume name
# actual-budget-mcp-data is NOT a stale reference (the chunk: the pod-local
# volume name may stay as-is — it is not a cluster object), so the sweep
# matches the old item names at a non-dash boundary only.
STALE_RX='actual-budget-mcp([^a-z-]|$)|actual-budget-mcp-key|claimName:[[:space:]]*actual-budget-mcp-data'
want_dir_regex "$STALE_RX" services/ 0 's6 [AC5]: the old names (actual-budget-mcp / actual-budget-mcp-key / the old claimName reference) are absent from every services/ file (stale-reference sweep)'
want_dir_regex "$STALE_RX" charts/ 0 's6 [AC5]: the old names are absent from every charts/ file (stale-reference sweep)'
want_dir_regex "$STALE_RX" custom-values/ 0 's6 [AC5]: the old names are absent from every custom-values/ file (stale-reference sweep)'
want_count 'OVERRIDE_VIA_CUSTOM_VALUES' "$CV" 0 's6 [AC4]: the custom-values file carries no sentinel VALUES (every mirror is a real UUID)'

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

# [C03 — the 2026-11-26 owner instruction flips this leg to ABSENCE: "I
# don't want anything on proxy-remote yet". The assert must fail on a
# re-added entry at ANY position (the shell grep leg covers the raw file;
# the tree scan here covers non-proxy placement) and must NOT pass on an
# unreadable file (a parse failure below is a fail, not a pass).
if pr is not None:
    stray = find_keys(pr, 'wuulf-budget')
    if stray:
        e = ((pr.get('proxy') or {}).get('subdomains') or {}).get('wuulf-budget')
        bad(f's2 [C03]: wuulf-budget is PRESENT in the proxy-remote values ({len(stray)} tree occurrence(s); the proxy.subdomains entry: {e!r}) — C03 removes it; wuulf stays on proxy-local only')
    else:
        ok('s2 [C03]: the proxy-remote values carry NO wuulf-budget entry anywhere in the tree (the C01 enabled: true entry is removed; the proxy-local entry stands)')

if pl is None:
    bad('s2: unassessable — the proxy-local values did not parse (see precondition fail above)')
if pr is None:
    bad('s2 [C03]: unassessable — the proxy-remote values did not parse; an absence assert must not pass on an unreadable file')

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

# --- s5 [C02 AC1/AC4/AC5 + C03 re-pin]: the mcp.actual-budget entry --------
# The C02 entry invariants stand (enabled, image format, transport, args
# incl. the --enable-write absence, env, the mcp container, the security
# floor); C03 re-pins the secrets wiring + volume claimName to the
# release-prefixed names the moved chart templates render, and adds the
# gate keys (chart default false; true ONLY in the wuulf block) plus the
# moved-template shape (gate, release-prefixed names, owner-named remoteRef,
# deletionPolicy Delete).

if chart is not None:
    mg = chart.get('mcp')
    if isinstance(mg, dict) and mg.get('enabled') is False:
        ok('s5 [C03]: the chart default is mcp.enabled false (the per-instance opt-in gate, OFF by default — bri-budget and home-actualbudget render NONE of the MCP objects)')
    else:
        bad(f's5 [C03]: the chart default mcp.enabled got {mg.get("enabled") if isinstance(mg, dict) else "no mcp key"} — want false')

if home is not None:
    wb = home.get('wuulf-budget')
    wbm = (wb or {}).get('mcp') if isinstance(wb, dict) else None
    if isinstance(wbm, dict) and wbm.get('enabled') is True:
        ok('s5 [C03]: the wuulf-budget per-instance block sets mcp.enabled true (the ONLY instance that enables the gate)')
    else:
        bad(f's5 [C03]: the wuulf-budget block lacks mcp.enabled true (got {wbm.get("enabled") if isinstance(wbm, dict) else "no mcp key"})')
    for inst in ('bri-budget', 'actualbudget'):
        b = home.get(inst)
        bm = (b or {}).get('mcp') if isinstance(b, dict) else None
        if isinstance(bm, dict) and bm.get('enabled') is True:
            bad(f's5 [C03]: the {inst} block sets mcp.enabled true — the gate must be true ONLY in the wuulf block')
        else:
            ok(f's5 [C03]: the {inst} block does not enable the mcp gate (only wuulf does)')

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
                pv = [v for v in vols if v.get('name') == vn]
                pvc0 = pv[0].get('persistentVolumeClaim') if pv else None
                is_pvc = isinstance(pvc0, dict)
                cn = pvc0.get('claimName') if is_pvc else None
                if not is_pvc:
                    bad(f's5 [AC4]: the volume {vn!r} mounted at {dd!r} is not a persistentVolumeClaim entry')
                elif cn != 'home-wuulf-budget-mcp-data':
                    bad(f's5 [C03]: the data volume claimName got {cn!r}, want home-wuulf-budget-mcp-data (the release-prefixed name the moved PVC template renders)')
                else:
                    ok(f's5 [AC4/C03]: ACTUAL_DATA_DIR {dd!r} equals the data volume mount path, a persistentVolumeClaim with claimName home-wuulf-budget-mcp-data (the release-prefixed 5Gi cache PVC)')
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
                'home-wuulf-budget-mcp-bearer': ('BEARER_TOKEN', 'BEARER_TOKEN'),
                'home-wuulf-budget-mcp-key': ('ACTUAL_SESSION_TOKEN', 'ACTUAL_SESSION_TOKEN'),
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
                bad('s5 [C03/AC4]: the secrets wiring is wrong — ' + '; '.join(diffs))
            else:
                ok('s5 [C03/AC4]: secrets carry exactly one entry per credential — home-wuulf-budget-mcp-bearer -> BEARER_TOKEN, home-wuulf-budget-mcp-key -> ACTUAL_SESSION_TOKEN (the release-prefixed target Secrets the moved chart templates render; the owner-confirmed name->role mapping, OQ3)')

    # [C03]: the three C02 templates MOVED into the chart behind the
    # per-instance gate — release-prefixed object names, the owner-named
    # bitwardenIds remoteRef items, deletionPolicy Delete (the repo-wide
    # convention for MCP-credential ExternalSecrets), the verbatim wekan-mcp
    # boilerplate kept; the old umbrella files must be GONE (git mv, no
    # copy-and-leave-behind).
    def moved_shape(path, label, rx_name, min_name, item, extras):
        if not os.path.isfile(path):
            bad(f'{label}: {path} is missing (the C02 template must be MOVED here, behind the mcp.enabled gate)')
            return
        text = open(path).read()
        problems = []
        if not re.search(r'\{\{-?\s*if\s+index\s+\.Values\s+["\']mcp["\']\s+["\']enabled["\']\s*\}\}', text):
            problems.append('the mcp.enabled gate ({{- if index .Values "mcp" "enabled" }}) is missing')
        n = len(re.findall(rx_name, text))
        if n < min_name:
            problems.append(f'the release-prefixed name count is {n}, want >= {min_name} (metadata.name + target.name)')
        if item is not None and not re.search(r'index\s+\.Values\s+"bitwardenIds"\s+"%s"' % item, text):
            problems.append(f'the remoteRef bitwardenIds item {item} reference is missing')
        for needle in extras:
            if needle not in text:
                problems.append(f'lacks {needle}')
        if problems:
            bad(f'{label}: {path} shape wrong — ' + '; '.join(problems))
        else:
            what = f'the {item} remoteRef' if item else 'no remoteRef (a PVC)'
            ok(f'{label}: {path} carries the mcp.enabled gate, the release-prefixed name, {what} and the credential boilerplate (bitwarden-login store ref, the conversion/decoding/metadataPolicy lines that keep ArgoCD quiet, deletionPolicy Delete)')

    moved_shape('charts/actualbudget/templates/secret-actualbudget-mcp-key.yaml', 's5 [C03]',
               r'\{\{\s*\.Release\.Name\s*\}\}-mcp-key', 2, 'actualbudget-mcp-key',
               ['name: bitwarden-login', 'conversionStrategy: Default', 'decodingStrategy: None', 'metadataPolicy: None',
                'creationPolicy: Owner', 'refreshInterval: 1h', 'engineVersion: v2', 'property: password',
                'deletionPolicy: Delete',
                'Boiler plate needed for ArgoCD to not complain about a mismatch.',
                'ACTUAL_SESSION_TOKEN: "{{ `{{ .token }}` }}"'])
    moved_shape('charts/actualbudget/templates/secret-actualbudget-mcp-bearer.yaml', 's5 [C03]',
               r'\{\{\s*\.Release\.Name\s*\}\}-mcp-bearer', 2, 'actualbudget-mcp-bearer',
               ['name: bitwarden-login', 'conversionStrategy: Default', 'decodingStrategy: None', 'metadataPolicy: None',
                'creationPolicy: Owner', 'refreshInterval: 1h', 'engineVersion: v2', 'property: password',
                'deletionPolicy: Delete',
                'Boiler plate needed for ArgoCD to not complain about a mismatch.',
                'BEARER_TOKEN: "{{ `{{ .token }}` }}"'])
    moved_shape('charts/actualbudget/templates/pvc-actualbudget-mcp-data.yaml', 's5 [C03]',
               r'\{\{\s*\.Release\.Name\s*\}\}-mcp-data', 1, None,
               ['kind: PersistentVolumeClaim', 'namespace: default', 'ReadWriteOnce', '5Gi'])
    for old in ('services/home/prod/templates/secret-actual-budget-mcp.yaml',
               'services/home/prod/templates/secret-actual-budget-mcp-key.yaml',
               'services/home/prod/templates/pvc-actual-budget-mcp-default.yaml'):
        if os.path.isfile(old):
            bad(f's5 [C03]: {old} is still present in the home umbrella — the templates MOVED into charts/actualbudget/templates/ (a rename, not a copy-and-leave-behind)')
        else:
            ok(f's5 [C03]: {old} is gone from the home umbrella (the move left no old file behind)')
else:
    bad('s5: unassessable — the home service values did not parse (see precondition fail above)')

# --- s6 [C03 AC4 + grep legs]: the 1:1 sentinel<->custom-values, both files -
# The sentinels MOVED into the chart's bitwardenIds map (the lowest merge
# tier); the real owner-minted UUIDs land at the custom-values TOP level
# (the appset merge overrides the chart tier — the same injection that
# resolves actualbudget-sso-secret; per-app blocks do NOT feed the chart
# map, so no per-app UUID blocks are added). The 2026-11-24 ruling's
# deliberate red state ENDS with C03: both files 1:1 and GREEN.
if chart is not None and home is not None and cv is not None:
    cb = chart.get('bitwardenIds')
    if not isinstance(cb, dict) or not cb:
        bad('s6 [AC4]: the chart bitwardenIds map is missing or empty — the two MCP sentinels must live in the chart (the lowest merge tier)')
    else:
        leaked = sorted(k for k, v in cb.items() if not (isinstance(v, str) and v == SENTINEL))
        want_keys = {'actualbudget-mcp-key', 'actualbudget-mcp-bearer'}
        if set(cb) != want_keys or leaked:
            bad(f's6 [AC4]: the chart bitwardenIds map is wrong (keys {sorted(cb)}, want exactly {sorted(want_keys)}; real UUIDs leaked into the tracked chart file: {leaked})')
        else:
            ok('s6 [AC4]: the chart carries exactly the two new sentinels (actualbudget-mcp-key / actualbudget-mcp-bearer), every value OVERRIDE_VIA_CUSTOM_VALUES (no real UUID leaked into the tracked chart file)')

        cvb = cv.get('bitwardenIds') or {}
        unmirrored = [k for k in cb if not (isinstance(cvb.get(k), str) and UUID_RE.fullmatch(cvb.get(k)) and cvb.get(k) != SENTINEL)]
        if unmirrored:
            bad(f's6 [AC4]: chart sentinels without a UUID-form top-level custom-values mirror (count-based 1:1 broken — a third unmirrored sentinel fails here): {unmirrored}')
        else:
            ok(f's6 [AC4]: every one of the {len(cb)} chart sentinels has a UUID-form top-level custom-values mirror (count-based 1:1 — the owner mint landed)')

    tb = home.get('bitwardenIds') or {}
    stale = [k for k in ('actual-budget-mcp', 'actual-budget-mcp-key') if k in tb]
    if stale:
        bad(f's6 [AC4]: the OLD sentinel names {stale} are still present in the home service values — they moved into the chart with the owner rename; a stale reference must not survive')
    else:
        ok('s6 [AC4]: the old sentinel names (actual-budget-mcp, actual-budget-mcp-key) are ABSENT from the home service values (the rename is complete)')

    non_sent = sorted(k for k, v in tb.items() if not (isinstance(v, str) and v == SENTINEL))
    if non_sent:
        bad(f's6 [AC4]: non-sentinel values in the home top-level bitwardenIds (a real UUID leaked into the service values): {non_sent}')
    else:
        ok(f's6 [AC4]: every one of the {len(tb)} home top-level bitwardenIds values is the OVERRIDE_VIA_CUSTOM_VALUES sentinel (no UUID leaked into the service values)')

    cvb = cv.get('bitwardenIds') or {}
    unmirrored = [k for k, v in tb.items() if v == SENTINEL and not (isinstance(cvb.get(k), str) and UUID_RE.fullmatch(cvb.get(k)))]
    if unmirrored:
        bad(f's6 [AC4]: home top-level sentinels without a UUID-form custom-values mirror (count-based 1:1 broken — every pre-existing sentinel must stay mirrored): {unmirrored}')
    else:
        ok(f's6 [AC4]: every one of the {len(tb)} home top-level sentinels has a UUID-form custom-values mirror (count-based 1:1, both files 1:1)')

    existing8 = ['admin-account', 'wekan-sso-secret', 'paperless-sso-secret', 'paperless-samba-secret',
                'karakeep-secret', 'karakeep-sso', 'actualbudget-sso-secret', 'mcp-pg-paperless']
    missing8 = [k for k in existing8 if k not in tb]
    if missing8:
        bad(f's6 [AC4]: pre-existing home top-level sentinels missing (regression — C03 removes exactly the two old MCP names, nothing else): {missing8}')
    else:
        ok('s6 [AC4]: all 8 pre-existing home top-level sentinels are present (regression pin — the C02 pair is out, the 8 stand)')

    diffs = []
    for k in ('actualbudget-mcp-key', 'actualbudget-mcp-bearer'):
        v = cvb.get(k)
        if not (isinstance(v, str) and UUID_RE.fullmatch(v) and v != SENTINEL):
            diffs.append(f'custom-values bitwardenIds.{k} got {v!r}, want a UUID-form (real, not a sentinel) value')
    if diffs:
        bad('s6 [AC4]: ' + '; '.join(diffs))
    else:
        ok('s6 [AC4]: both owner-minted credential UUIDs (actualbudget-mcp-key / actualbudget-mcp-bearer) are UUID-form, not sentinels — the 2026-11-24 ruling red state ends with C03 (the exact values are proven by the C03 plan-Commands render)')

    bad_sent = sorted(k for k, v in cvb.items() if v == SENTINEL)
    if bad_sent:
        bad(f's6 [AC4]: sentinel VALUES in the custom-values top-level bitwardenIds (a mirror must be a real UUID, not the sentinel string): {bad_sent}')
    else:
        ok('s6 [AC4]: the custom-values top-level bitwardenIds carries no sentinel VALUES (every mirror is a real UUID)')
elif chart is None or home is None or cv is None:
    bad('s6: unassessable — one of the chart / home service values / custom-values did not parse (see precondition fail above)')

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
