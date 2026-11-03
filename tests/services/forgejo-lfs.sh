#!/usr/bin/env bash
# Git LFS contract (cf-104 feat-forgejo-lfs): the forgejo wrapper chart's inert
# `[lfs]` plumbing (C01), the per-instance activation in custom-values/dev
# (C02) and custom-values/infra (C03), and the blast-radius pins that keep the
# shared SeaweedFS gateway and the service trio untouched.
#
# Leg -> acceptance-criteria map (plan test contract, section A):
#   t1  harness: dependency builds on /tmp copies             plan Commands
#   t2  inert [lfs] shape, no STORAGE_TYPE, no [storage]      C01 AC2, AC3
#   t3  ExternalSecret forgejo-s3-secret mapping              C01 AC5
#   t4  exactly four FORGEJO__* legs on init-app-ini          C01 AC4
#   t5  dev effective [lfs] + LFS_START_SERVER                C02 AC1-3
#   t6  infra effective [lfs] over the in-cluster endpoint    C03 AC1-3
#   t7  cross-instance bucket + path-style parity             C03 Notes drift guard
#   t8  UUID-shaped bitwardenIds.forgejo-s3 in both files     C02 AC4, C03 AC4
#   t9  sentinel sweep at the pinned baselines                C02 AC5, C03 AC4
#   t10 trio survives (charts.forgejo, git routes, dev s3 = 0) C02 AC6, C03 AC7
#   t11 charts/seaweedfs + infra templates untouched          C03 AC7 (plan D4)
#
# Red-first by design: the run STOPS at its first failing leg — t2/t3/t4 until
# C01 lands, t5 until C02, t6 until C03. A stopped run is the contract working,
# not a broken suite; the legs behind it re-run once the blocker lands.
#
# Sentinel baselines are measured, not assumed zero (FRICTION 2026-11-03):
# each umbrella writes its whole values blob as ONE JSON line, so grep -c
# counts one line per app that carries sentinels.
#   dev   1  home-assistant.bitwardenIds (cf-93 wart)
#   infra 1  samba.bitwardenIds — the plan's Commands say 0, but that line
#            renders services/infra/prod IN PLACE, where helm aborts before
#            writing anything (cloudnative-pg + samba are not vendored), so
#            its grep only saw an empty stream. Under this repo's copy +
#            dependency-build harness the pre-existing count is 1. The leg
#            pins "unchanged", which is the criterion; a legitimate baseline
#            move must update the constant in the same change, with the reason.
#
# Harness per tests/services/infra-forgejo.sh:1-30: helm from HELM_BIN, PATH,
# ~/.local/bin or /tmp/opencode (else v3.21.4 downloaded there); charts and
# umbrella services are copied to /tmp/opencode and dependency-built there —
# the worktree is never written (charts/**/charts is gitignored). An
# unreachable registry SKIPS the render legs instead of failing them; the
# static legs (t8, t10, t11) always run.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/forgejo-lfs.sh
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # FRICTION seed: helm lives at ~/.local/bin

cd "$(git rev-parse --show-toplevel)"

FJ_CHART="charts/forgejo"
DEVUMB="services/dev/prod"
INFRAUMB="services/infra/prod"
DEV_VALUES="$DEVUMB/values.yaml"
INFRA_VALUES="$INFRAUMB/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
INFRA_CV="custom-values/infra/prod-values.yaml"
SWD_VALUES="charts/seaweedfs/values.yaml"

DEV_SENT_BASELINE=1
INFRA_SENT_BASELINE=1

# Blast-radius legs diff against the fork point's main. LFS_DIFF_BASE re-points
# it if main legitimately moved a pinned path.
DIFF_BASE="${LFS_DIFF_BASE:-$(git rev-parse --verify main 2>/dev/null || git rev-parse --verify origin/main 2>/dev/null || true)}"

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

# --- helm discovery (infra-forgejo.sh convention) --------------------------
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
  dir=/tmp/opencode/forgejo-lfs-helm-download
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

WORK=$(mktemp -d /tmp/opencode/forgejo-lfs.XXXXXX)

# Copy a chart/service path into WORK and dependency-build it there. Prints
# the copy path on success; on a registry-unreachable failure writes a flag
# file (a subshell cannot set the parent's skip variable) and prints a skip
# note, leaving stdout empty.
build_copy() {
  local chart="$1" flagfile="$2"
  local copy="$WORK/$(printf '%s' "$chart" | tr '/' '_')"
  cp -R "$chart"/. "$copy"/
  local log="$copy/dependency-build.log"
  if ! (cd "$copy" && "$helm_bin" dependency build .) >"$log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$log"; then
      : >"$flagfile"
      printf 'skip: t1: helm dependency build could not reach the registry for %s here; the render legs were not run (log kept at %s)\n' "$chart" "$log" >&2
      return 0
    fi
    tail -n 30 "$log" >&2
    printf 'FAIL: t1: helm dependency build failed for %s (log kept at %s)\n' "$chart" "$log" >&2
    exit 1
  fi
  printf '%s' "$copy"
}

# The Application receives the CONTENTS of the top-level <appName>: key
# (charts/base/templates/appset-charts.yaml), so a per-instance render must
# dump that key at the TOP level — re-wrapping it renders nothing (FRICTION
# 2026-11-03).
extract_slice() {
  local src="$1" key="$2" out="$3"
  if ! python3 - "$src" "$key" "$out" <<'PY'
import sys, yaml

src, key, out = sys.argv[1:4]
with open(src) as f:
    d = yaml.safe_load(f) or {}
block = d.get(key)
if not isinstance(block, dict):
    print(f'FAIL: {src} has no top-level {key}: block to extract', file=sys.stderr)
    sys.exit(1)
with open(out, 'w') as f:
    yaml.safe_dump(block, f)
PY
  then
    exit 1
  fi
}

skip_helm=0
fj_copy="" devumb_copy="" infraumb_copy=""

# --- t1: harness (dependency builds on copies) -----------------------------
if [ -z "$helm_bin" ]; then
  skip "t1: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; the render legs (t2-t7, t9) were not run"
  skip_helm=1
else
  [ -d "$FJ_CHART" ] || fail "t1: $FJ_CHART does not exist — nothing to dependency-build"
  fj_copy=$(build_copy "$FJ_CHART" "$WORK/fj-skip")
  if [ -f "$WORK/fj-skip" ]; then skip_helm=1; fi
  devumb_copy=$(build_copy "$DEVUMB" "$WORK/dev-skip")
  if [ -f "$WORK/dev-skip" ]; then skip_helm=1; fi
  infraumb_copy=$(build_copy "$INFRAUMB" "$WORK/infra-skip")
  if [ -f "$WORK/infra-skip" ]; then skip_helm=1; fi

  if [ "$skip_helm" -eq 1 ]; then
    skip "t2-t7, t9: not run (dependency builds not reachable from here)"
  else
    ok "t1: helm dependency build succeeds for $FJ_CHART, $DEVUMB and $INFRAUMB on copies ($("$helm_bin" version --short 2>/dev/null || echo helm))"

    # ---- t2: chart-level inert [lfs] shape (C01 AC2, AC3) ------------------
    # The four shape keys must exist WITHOUT the activation switch, so the
    # chart can deploy to a cluster that has no bucket and no credentials.
    chart_out="$WORK/chart-render.yaml"
    chart_err="$WORK/chart-render.err"
    if ! "$helm_bin" template dev "$fj_copy" \
      --set domain=scifi.farm --set clusterName=dev \
      --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
      --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
      --set bitwardenIds.forgejo-s3=u5 \
      >"$chart_out" 2>"$chart_err"; then
      tail -n 30 "$chart_err" >&2
      fail "t2: helm template of $FJ_CHART failed (log kept at $chart_err)"
    fi
    [ -s "$chart_out" ] || fail "t2: helm template of $FJ_CHART rendered nothing"
    if python3 - "$chart_out" "$WORK/t2-count" <<'PY'
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

# The inert shape C01 ships for BOTH instances. `default` is the Q6 answer:
# a valid literal at v15.0.10 identical to unset (only `md5` sets
# SendContentMd5), made explicit rather than left to the code default.
CHART_LFS = {
    'MINIO_BUCKET': 'git-lfs',
    'MINIO_BUCKET_LOOKUP': 'path',
    'MINIO_CHECKSUM_ALGORITHM': 'default',
    'SERVE_DIRECT': 'false',
}

def ini(section):
    out = {}
    for line in (section or '').splitlines():
        if not line.strip():
            continue
        if '=' not in line:
            bad(f't2: the inline-config section has a non KEY=VALUE line {line!r}')
        k, v = line.split('=', 1)
        out[k] = v
    return out

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    raw = open(render).read()

    inlines = [d for d in docs
               if d.get('kind') == 'Secret'
               and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
    if len(inlines) != 1:
        bad(f't2: {len(inlines)} inline-config Secrets in the render, expected exactly one')
    secs = (inlines[0].get('stringData') or {})

    if 'lfs' not in secs:
        bad(f't2: the inline-config Secret has no [lfs] section (sections: {sorted(secs)}) — C01 must ship the inert shape keys in charts/forgejo/values.yaml under forgejo.gitea.config.lfs')
    got = ini(secs['lfs'])
    if got != CHART_LFS:
        bad(f't2: the [lfs] section is {got!r}, expected exactly {CHART_LFS!r}')
    ok('t2: the chart renders [lfs] as exactly MINIO_BUCKET=git-lfs, MINIO_BUCKET_LOOKUP=path, MINIO_CHECKSUM_ALGORITHM=default, SERVE_DIRECT=false')

    if 'STORAGE_TYPE' in secs['lfs']:
        bad('t2: the chart-level [lfs] section carries STORAGE_TYPE — the activation switch is per-instance (custom-values), and a chart-level switch turns LFS on for every cluster deploying this chart')
    if 'STORAGE_TYPE' in raw:
        bad('t2: STORAGE_TYPE appears anywhere in the chart-only render — same reason: C01 must stay inert')
    ok('t2: no STORAGE_TYPE anywhere in the chart-only render (C01 is inert; activation stays per-instance)')

    for banned in ('storage', 'attachment', 'picture'):
        if banned in secs:
            bad(f't2: the inline-config Secret renders a [{banned}] section — a [storage] section would also move attachments/avatars/packages to S3 (plan D1); every LFS key must live in [lfs]')
    env_names = set()
    for d in docs:
        pod = (((d.get('spec') or {}).get('template') or {}).get('spec')) or {}
        for c in (pod.get('initContainers') or []) + (pod.get('containers') or []):
            for e in (c or {}).get('env') or []:
                env_names.add((e or {}).get('name') or '')
    leaked = sorted(n for n in env_names
                    if n.startswith(('FORGEJO__STORAGE__', 'FORGEJO__ATTACHMENT__', 'FORGEJO__PICTURE__')))
    if leaked:
        bad(f't2: env legs introduce other storage sections: {leaked} (same D1 blast radius as a [storage] section)')
    ok('t2: no storage/attachment/picture section in the inline-config Secret or in any env leg')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't2: the chart render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t2-count")))
    else
      exit 1
    fi

    # ---- t3: ExternalSecret forgejo-s3-secret (C01 AC5) ---------------------
    if python3 - "$chart_out" "$WORK/t3-count" <<'PY'
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
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    es = [d for d in docs
          if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if len(es) != 1:
        bad(f't3: {len(es)} ExternalSecrets named forgejo-s3-secret in the render, expected exactly one (C01 adds templates/secret-forgejo-s3.yaml, ungated and fixed-name like secret-forgejo.yaml)')
    es = es[0]
    spec = es.get('spec') or {}

    # The store may be declared once at spec level (charts/forgejo-runner) or
    # per entry via sourceRef.storeRef (charts/forgejo's own style, which C01
    # is told to follow) — either is fine, the LOGIN store is what matters.
    stores = []
    if spec.get('secretStoreRef'):
        stores.append(spec['secretStoreRef'])
    for e in (spec.get('data') or []):
        ref = ((e or {}).get('sourceRef') or {}).get('storeRef')
        if ref:
            stores.append(ref)
    if not stores:
        bad('t3: forgejo-s3-secret declares no SecretStore at all')
    for st in stores:
        if st.get('name') != 'bitwarden-login' or st.get('kind') != 'SecretStore':
            bad(f't3: the ExternalSecret declares store {st!r}, expected the bitwarden-login SecretStore (the item is a LOGIN: username = access key id, password = secret access key)')
    ok('t3: forgejo-s3-secret reads the bitwarden-login store')

    target = spec.get('target') or {}
    if target.get('name') != 'forgejo-s3-secret':
        bad(f't3: target Secret name is {target.get("name")!r}, expected forgejo-s3-secret (the fixed name the two env legs reference)')
    if target.get('creationPolicy') != 'Owner':
        bad(f't3: target.creationPolicy is {target.get("creationPolicy")!r}, expected Owner')
    if spec.get('refreshInterval') != '1h':
        bad(f't3: refreshInterval is {spec.get("refreshInterval")!r}, expected 1h (the cadence every sibling forgejo ExternalSecret uses)')
    ok('t3: target Secret forgejo-s3-secret, creationPolicy Owner, refreshInterval 1h')

    entries = spec.get('data') or []
    got = {}
    for e in entries:
        rr = (e or {}).get('remoteRef') or {}
        got[(e or {}).get('secretKey')] = (rr.get('key'), rr.get('property'),
                                           rr.get('conversionStrategy'),
                                           rr.get('decodingStrategy'),
                                           rr.get('metadataPolicy'))
    if set(got) != {'access_key_id', 'secret_access_key'}:
        bad(f't3: data secretKeys are {sorted(got)}, expected exactly access_key_id + secret_access_key')
    want = {'access_key_id': ('u5', 'username'), 'secret_access_key': ('u5', 'password')}
    for key, (want_key, want_prop) in want.items():
        rkey, rprop, conv, dec, meta = got[key]
        if rkey != want_key:
            bad(f't3: {key} reads remoteRef key {rkey!r}, expected the bitwardenIds.forgejo-s3 value passed in ({want_key!r})')
        if rprop != want_prop:
            bad(f't3: {key} reads property {rprop!r}, expected {want_prop!r} (the LOGIN field the credential lives in)')
        for field, want_field in (('conversionStrategy', 'Default'), ('decodingStrategy', 'None'), ('metadataPolicy', 'None')):
            actual = {'conversionStrategy': conv, 'decodingStrategy': dec, 'metadataPolicy': meta}[field]
            if actual != want_field:
                bad(f't3: {key}.{field} is {actual!r}, expected {want_field!r} (ESO admission boilerplate this repo requires on every remoteRef)')
    ok('t3: access_key_id <- username and secret_access_key <- password from the forgejo-s3 item, with the three ESO boilerplate fields')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't3: the ExternalSecret check could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t3-count")))
    else
      exit 1
    fi

    # ---- t4: exactly four config env legs (C01 AC4) ------------------------
    # Counted on FORGEJO__* names, not the whole env list: the subchart also
    # injects GITEA_* envs. The four must be the two pre-existing ones plus
    # the two LFS ones — a fifth leg means config is being smuggled in, and a
    # lost leg means the DB password silently disappeared (the indexed --set
    # trap, FRICTION 2026-11-03).
    if python3 - "$chart_out" "$WORK/t4-count" <<'PY'
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

LFS_LEGS = {
    'FORGEJO__LFS__MINIO_ACCESS_KEY_ID': ('forgejo-s3-secret', 'access_key_id'),
    'FORGEJO__LFS__MINIO_SECRET_ACCESS_KEY': ('forgejo-s3-secret', 'secret_access_key'),
}
OLD_LEGS = {
    'FORGEJO__DATABASE__PASSWD': ('pg-forgejo-secret', 'password'),
    'FORGEJO__SECURITY__SECRET_KEY': ('forgejo-secret', 'SECRET_KEY'),
}

def legs(container):
    out = {}
    for e in (container or {}).get('env') or []:
        name = (e or {}).get('name') or ''
        if not name.startswith('FORGEJO__'):
            continue
        ref = ((e.get('valueFrom') or {}).get('secretKeyRef') or {})
        out[name] = (ref.get('name'), ref.get('key'))
    return out

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    deps = [d for d in docs if d.get('kind') == 'Deployment']
    if len(deps) != 1:
        bad(f't4: {len(deps)} Deployments in the render, expected exactly one')
    pod = ((deps[0].get('spec') or {}).get('template') or {}).get('spec') or {}
    init = next((c for c in (pod.get('initContainers') or [])
                 if (c or {}).get('name') == 'init-app-ini'), None)
    if init is None:
        bad('t4: no init-app-ini container — the subchart writes app.ini in that init container, so the LFS credential legs have to sit there')

    got = legs(init)
    want = dict(OLD_LEGS)
    want.update(LFS_LEGS)
    if set(got) != set(want):
        missing = sorted(set(want) - set(got))
        extra = sorted(set(got) - set(want))
        bad(f't4: init-app-ini carries {len(got)} FORGEJO__ legs (missing {missing}, unexpected {extra}), expected exactly {sorted(want)}')
    for name, pair in want.items():
        if got[name] != pair:
            bad(f't4: {name} reads secret {got[name]!r}, expected {pair!r}')
    ok('t4: init-app-ini carries exactly four FORGEJO__ legs — the pre-existing DB password + SECRET_KEY, plus the two LFS legs on forgejo-s3-secret/access_key_id and /secret_access_key')

    main = next((c for c in (pod.get('containers') or []) if (c or {}).get('name') == 'forgejo'), None)
    if main is None:
        bad('t4: no forgejo container in the render')
    if legs(main):
        bad(f't4: the main forgejo container carries FORGEJO__ env legs {sorted(legs(main))} — inline config is applied by init-app-ini only; credentials on the app container would also re-expose them to the running process environment')
    ok('t4: the main forgejo container still carries no FORGEJO__* env')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't4: the env-leg check could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t4-count")))
    else
      exit 1
    fi

    # ---- t5: dev effective render (C02 AC1-3) ------------------------------
    extract_slice "$DEV_CV" forgejo "$WORK/forgejo-dev-slice.yaml"
    dev_eff="$WORK/dev-effective.yaml"
    dev_eff_err="$WORK/dev-effective.err"
    if ! "$helm_bin" template dev "$fj_copy" -f "$WORK/forgejo-dev-slice.yaml" \
      --set domain=scifi.farm --set clusterName=dev \
      >"$dev_eff" 2>"$dev_eff_err"; then
      tail -n 30 "$dev_eff_err" >&2
      fail "t5: helm template of $FJ_CHART with dev's extracted forgejo: slice failed (log kept at $dev_eff_err)"
    fi
    [ -s "$dev_eff" ] || fail "t5: the dev effective render produced nothing"
    if python3 - "$dev_eff" "$DEV_CV" dev git.scifi.farm 'https://git.scifi.farm/' "$WORK/t5-count" <<'PY'
import sys, yaml

render, cv_file, release, domain, root_url, count_file = sys.argv[1:7]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# dev reaches the gateway over its PUBLIC route (dev has no local gateway,
# EXPLORE 3.1): bare host + TLS, minio-go builds https://<host> and Go
# defaults to 443 (v7.0.99 utils.go:109-128).
DEV_LFS = {
    'MINIO_BUCKET': 'git-lfs',
    'MINIO_BUCKET_LOOKUP': 'path',
    'MINIO_CHECKSUM_ALGORITHM': 'default',
    'MINIO_ENDPOINT': 's3.spencerslab.com',
    'MINIO_USE_SSL': 'true',
    'SERVE_DIRECT': 'false',
    'STORAGE_TYPE': 'minio',
}

def ini(section):
    out = {}
    for line in (section or '').splitlines():
        if not line.strip():
            continue
        if '=' not in line:
            bad(f't5: the inline-config section has a non KEY=VALUE line {line!r}')
        k, v = line.split('=', 1)
        out[k] = v
    return out

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    inlines = [d for d in docs
               if d.get('kind') == 'Secret'
               and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
    if len(inlines) != 1:
        bad(f't5: {len(inlines)} inline-config Secrets in the dev effective render, expected exactly one')
    secs = (inlines[0].get('stringData') or {})

    if 'lfs' not in secs:
        bad(f't5: the dev effective render has no [lfs] section (sections: {sorted(secs)}) — C02 adds the three per-instance keys under forgejo.forgejo.gitea.config.lfs in {cv_file}')
    got = ini(secs['lfs'])
    if got != DEV_LFS:
        bad(f't5: the dev [lfs] section is {got!r}, expected exactly {DEV_LFS!r} (the four shape keys from the chart merged with the three activation keys C02 adds)')
    ok('t5: dev resolves the full 7-key [lfs] section with endpoint s3.spencerslab.com and MINIO_USE_SSL=true')

    server = ini(secs.get('server') or '')
    if server.get('LFS_START_SERVER') != 'true':
        bad(f't5: [server] LFS_START_SERVER is {server.get("LFS_START_SERVER")!r}, expected true (Forgejo 15 defaults it to false — without it the batch endpoint stays 404)')
    for key, want in (('DOMAIN', domain), ('ROOT_URL', root_url), ('SSH_PORT', '22222')):
        if server.get(key) != want:
            bad(f't5: [server] {key} is {server.get(key)!r}, expected {want!r} (the identity block must stay byte-identical; C02 touches only the LFS keys)')
    ok('t5: dev [server] gains LFS_START_SERVER=true beside the unchanged DOMAIN/ROOT_URL/SSH_PORT=22222')

    for banned in ('storage', 'attachment', 'picture'):
        if banned in secs:
            bad(f't5: the dev effective render introduces a [{banned}] section — attachments/avatars/packages stay on the PVC (plan D1)')
    ok('t5: no storage/attachment/picture section in the dev effective render')

    with open(cv_file) as f:
        cv = yaml.safe_load(f) or {}
    uuid = ((cv.get('forgejo') or {}).get('bitwardenIds') or {}).get('forgejo-s3')
    es = [d for d in docs
          if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if len(es) != 1:
        bad('t5: the dev effective render has no forgejo-s3-secret ExternalSecret (the chart template plus the resolved UUID must both be present)')
    keys = set()
    def walk(node):
        if isinstance(node, dict):
            if 'remoteRef' in node:
                keys.add((node['remoteRef'] or {}).get('key'))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(es[0])
    if keys != {uuid}:
        bad(f't5: forgejo-s3-secret remoteRef keys are {sorted(str(k) for k in keys)}, expected the UUID from {cv_file} ({uuid!r}) — no sentinel or placeholder may survive here (plan D11: the credential secretKeyRef sits on the init container, so an unresolved ExternalSecret stops the pod)')
    if any('OVERRIDE_' in str(k) for k in keys):
        bad(f't5: an OVERRIDE_* sentinel reached the rendered remoteRef key ({sorted(str(k) for k in keys)}) — the LFS credential slot must carry a real UUID from the first commit')
    ok(f't5: forgejo-s3-secret resolves the real UUID from {cv_file} (no sentinel, no placeholder)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't5: the dev effective render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t5-count")))
    else
      exit 1
    fi

    # ---- t6: infra effective render (C03 AC1-3) ----------------------------
    extract_slice "$INFRA_CV" forgejo "$WORK/forgejo-infra-slice.yaml"
    infra_eff="$WORK/infra-effective.yaml"
    infra_eff_err="$WORK/infra-effective.err"
    if ! "$helm_bin" template infra "$fj_copy" -f "$WORK/forgejo-infra-slice.yaml" \
      --set domain=spencerslab.com --set clusterName=infra \
      >"$infra_eff" 2>"$infra_eff_err"; then
      tail -n 30 "$infra_eff_err" >&2
      fail "t6: helm template of $FJ_CHART with infra's extracted forgejo: slice failed (log kept at $infra_eff_err)"
    fi
    [ -s "$infra_eff" ] || fail "t6: the infra effective render produced nothing"
    if python3 - "$infra_eff" "$INFRA_CV" git.spencerslab.com 'https://git.spencerslab.com/' "$WORK/t6-count" <<'PY'
import sys, yaml

render, cv_file, domain, root_url, count_file = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# infra's gateway lives on infra, so the endpoint is the ClusterIP service —
# routing it through its own public Traefik entry would be a hairpin
# (RESEARCH Q5). Same bucket, same path-style lookup, TLS off in-cluster.
INFRA_LFS = {
    'MINIO_BUCKET': 'git-lfs',
    'MINIO_BUCKET_LOOKUP': 'path',
    'MINIO_CHECKSUM_ALGORITHM': 'default',
    'MINIO_ENDPOINT': 'seaweedfs-s3.default.svc.cluster.local:8333',
    'MINIO_USE_SSL': 'false',
    'SERVE_DIRECT': 'false',
    'STORAGE_TYPE': 'minio',
}

def ini(section):
    out = {}
    for line in (section or '').splitlines():
        if not line.strip():
            continue
        if '=' not in line:
            bad(f't6: the inline-config section has a non KEY=VALUE line {line!r}')
        k, v = line.split('=', 1)
        out[k] = v
    return out

try:
    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    raw = open(render).read()
    inlines = [d for d in docs
               if d.get('kind') == 'Secret'
               and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
    if len(inlines) != 1:
        bad(f't6: {len(inlines)} inline-config Secrets in the infra effective render, expected exactly one')
    secs = (inlines[0].get('stringData') or {})

    if 'lfs' not in secs:
        bad(f't6: the infra effective render has no [lfs] section (sections: {sorted(secs)}) — C03 adds the three activation keys under forgejo.forgejo.gitea.config.lfs in {cv_file}')
    got = ini(secs['lfs'])
    if got != INFRA_LFS:
        bad(f't6: the infra [lfs] section is {got!r}, expected exactly {INFRA_LFS!r} (only the endpoint and the TLS flag differ from dev)')
    ok('t6: infra resolves the full 7-key [lfs] section with endpoint seaweedfs-s3.default.svc.cluster.local:8333 and MINIO_USE_SSL=false')

    server = ini(secs.get('server') or '')
    if server.get('LFS_START_SERVER') != 'true':
        bad(f't6: [server] LFS_START_SERVER is {server.get("LFS_START_SERVER")!r}, expected true')
    for key, want in (('DOMAIN', domain), ('ROOT_URL', root_url), ('SSH_PORT', '22222')):
        if server.get(key) != want:
            bad(f't6: [server] {key} is {server.get(key)!r}, expected {want!r} (infra is the canonical git host of the lab; C03 touches only the LFS keys)')
    ok('t6: infra [server] gains LFS_START_SERVER=true and keeps DOMAIN git.spencerslab.com / ROOT_URL / SSH_PORT=22222')

    with open(cv_file) as f:
        cv = yaml.safe_load(f) or {}
    want_mailer = ((cv.get('forgejo') or {}).get('forgejo') or {}).get('gitea', {}).get('config', {}).get('mailer') or {}
    got_mailer = ini(secs.get('mailer') or '')
    want_mailer_str = {k: str(v).lower() if isinstance(v, bool) else str(v) for k, v in want_mailer.items()}
    if got_mailer != want_mailer_str:
        bad(f't6: the [mailer] section is {got_mailer!r}, expected {want_mailer_str!r} — the infra-only extras stay alone (C03 Files-in-scope)')
    ok('t6: the infra [mailer] block is unchanged')

    for banned in ('storage', 'attachment', 'picture'):
        if banned in secs:
            bad(f't6: the infra effective render introduces a [{banned}] section — plan D1 keeps attachments on the PVC')
    if 'https://s3.spencerslab.com' in raw:
        bad('t6: the public gateway host appears in the infra render — that is the hairpin through the local Traefik entry that the in-cluster endpoint exists to avoid (RESEARCH Q5)')
    ok('t6: no storage/attachment/picture section and no https://s3.spencerslab.com hairpin in the infra render')

    uuid = ((cv.get('forgejo') or {}).get('bitwardenIds') or {}).get('forgejo-s3')
    es = [d for d in docs
          if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if len(es) != 1:
        bad('t6: the infra effective render has no forgejo-s3-secret ExternalSecret')
    keys = set()
    def walk(node):
        if isinstance(node, dict):
            if 'remoteRef' in node:
                keys.add((node['remoteRef'] or {}).get('key'))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(es[0])
    if keys != {uuid}:
        bad(f't6: forgejo-s3-secret remoteRef keys are {sorted(str(k) for k in keys)}, expected the UUID from {cv_file} ({uuid!r})')
    if any('OVERRIDE_' in str(k) for k in keys):
        bad(f't6: an OVERRIDE_* sentinel reached the rendered remoteRef key ({sorted(str(k) for k in keys)}) — plan D11 bans a placeholder for this slot')
    ok(f't6: forgejo-s3-secret resolves the real UUID from {cv_file} (no sentinel, no placeholder)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't6: the infra effective render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t6-count")))
    else
      exit 1
    fi

    # ---- t7: cross-instance bucket + path-style parity ---------------------
    if python3 - "$dev_eff" "$infra_eff" "$WORK/t7-count" <<'PY'
import sys, yaml

dev_render, infra_render, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def lfs_of(render):
    for d in yaml.safe_load_all(open(render)):
        if not d or d.get('kind') != 'Secret':
            continue
        if not ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config'):
            continue
        body = (d.get('stringData') or {}).get('lfs')
        if body is None:
            bad(f't7: {render} renders no [lfs] section')
        return {kv.split('=', 1)[0]: kv.split('=', 1)[1]
                for kv in body.splitlines() if '=' in kv}
    bad(f't7: {render} has no inline-config Secret')

try:
    dev, infra = lfs_of(dev_render), lfs_of(infra_render)
    # Both instances must land on the same bucket with a path-style lookup:
    # the virtual-host form would ask for git-lfs.s3.spencerslab.com, which no
    # wildcard cert covers (plan D5/D8; C03 Notes: t5/t6 are the drift guards,
    # this leg is the parity guard between them).
    for key, want in (('MINIO_BUCKET', 'git-lfs'), ('MINIO_BUCKET_LOOKUP', 'path')):
        if dev.get(key) != want or infra.get(key) != want:
            bad(f't7: {key} resolves to dev={dev.get(key)!r} infra={infra.get(key)!r}, expected {want!r} on both')
    ok('t7: dev and infra both resolve MINIO_BUCKET=git-lfs with MINIO_BUCKET_LOOKUP=path (path-style — the virtual-host form would break TLS on git-lfs.s3.…)')

    shared = {k: v for k, v in dev.items()
              if k in ('MINIO_BUCKET', 'MINIO_BUCKET_LOOKUP', 'MINIO_CHECKSUM_ALGORITHM', 'SERVE_DIRECT')}
    infra_shared = {k: infra.get(k) for k in shared}
    if shared != infra_shared:
        bad(f't7: the shape keys drift apart — dev={shared!r} vs infra={infra_shared!r}. They ship once in the chart; repeating them in one custom-values file forks the instances silently (C02 Tasks).')
    ok('t7: the four chart-shape keys are identical across instances (no per-instance fork of shared keys)')

    if dev.get('MINIO_ENDPOINT') == infra.get('MINIO_ENDPOINT'):
        bad('t7: both instances use the same MINIO_ENDPOINT — dev has no local gateway and infra must not hairpin its own; the split is the design (plan D3)')
    ok('t7: the endpoints stay deliberately different per instance (dev public route, infra in-cluster)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't7: the parity check could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t7-count")))
    else
      exit 1
    fi
  fi
fi

# --- t8: UUID-shaped bitwardenIds.forgejo-s3 (C02 AC4, C03 AC4) ------------
# Static: the credential leg is a secretKeyRef on the init container, so an
# unresolved or placeholder id is a pod that cannot start, not a cosmetic wart
# (plan D11) — the deliberate exception to the repo's interim-placeholder
# precedent. Checked per file so the dev half goes green with C02 and the
# infra half only with C03.
if python3 - "$DEV_CV" "$INFRA_CV" "$WORK/t8-count" <<'PY'
import json, re, sys, yaml

dev_cv, infra_cv, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')

for path in (dev_cv, infra_cv):
    with open(path) as f:
        raw = f.read()
    d = yaml.safe_load(raw) or {}
    bw = ((d.get('forgejo') or {}).get('bitwardenIds') or {})
    if 'forgejo-s3' not in bw:
        bad(f't8: {path} has no forgejo.bitwardenIds.forgejo-s3 slot — the chart ships the sentinel, so a missing slot means the ExternalSecret remoteRef renders empty')
    val = bw['forgejo-s3']
    if not UUID_RE.match(str(val)):
        bad(f't8: {path} forgejo.bitwardenIds.forgejo-s3 is {val!r} — expected a real Bitwarden item UUID (OVERRIDE_NEEDED and any placeholder are banned for this slot: plan D11)')
    if 'OVERRIDE_' in json.dumps(d.get('forgejo')):
        bad(f't8: an OVERRIDE_* sentinel survives in the forgejo: slice of {path} — the chart sentinel must be matched 1:1 by a real UUID here')
    if 'OVERRIDE_NEEDED' in raw:
        bad(f't8: {path} carries OVERRIDE_NEEDED at all — the forgejo slices may not use it (plan D11) and nothing else in these files does today')
    ok(f't8: {path} carries a UUID-shaped forgejo.bitwardenIds.forgejo-s3 with no OVERRIDE_* in the forgejo slice')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t8-count")))
else
  exit 1
fi

# --- t9: sentinel sweep at the pinned baselines (C02 AC5, C03 AC4) ---------
# Whole-render count is pinned at the measured pre-ticket baseline; the real
# criterion is that the ticket adds nothing, so the per-application values JSON
# is also checked on its own (FRICTION 2026-11-03: a "want 0" leg would fail
# on an unrelated wart).
if [ "$skip_helm" -eq 1 ]; then
  skip "t9: sentinel sweep not run (dependency builds unavailable)"
else
  dev_umb="$WORK/dev-umbrella.yaml"
  dev_umb_err="$WORK/dev-umbrella.err"
  if ! "$helm_bin" template dev "$devumb_copy" -f "$DEV_CV" \
    --set domain=scifi.farm --set clusterName=dev >"$dev_umb" 2>"$dev_umb_err"; then
    tail -n 30 "$dev_umb_err" >&2
    fail "t9: helm template of $DEVUMB failed (log kept at $dev_umb_err)"
  fi
  infra_umb="$WORK/infra-umbrella.yaml"
  infra_umb_err="$WORK/infra-umbrella.err"
  if ! "$helm_bin" template infra "$infraumb_copy" -f "$INFRA_CV" \
    --set domain=spencerslab.com --set clusterName=infra >"$infra_umb" 2>"$infra_umb_err"; then
    tail -n 30 "$infra_umb_err" >&2
    fail "t9: helm template of $INFRAUMB failed (log kept at $infra_umb_err)"
  fi
  if python3 - "$dev_umb" "$infra_umb" "$DEV_SENT_BASELINE" "$INFRA_SENT_BASELINE" "$WORK/t9-count" <<'PY'
import json, sys, yaml

dev_render, infra_render, dev_base, infra_base, count_file = sys.argv[1:6]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def sentinels(render):
    # grep -c semantics: LINES containing OVERRIDE_ (each umbrella writes its
    # whole values blob on one line).
    return sum(1 for line in open(render) if 'OVERRIDE_' in line)

def app_json(render, app):
    for d in yaml.safe_load_all(open(render)):
        if not d or d.get('kind') != 'ApplicationSet':
            continue
        els = d['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']
        for el in els:
            vals = el.get('values')
            if isinstance(vals, dict) and app in vals:
                return json.dumps(vals[app])
    bad(f't9: no {app} key in the ApplicationSet values blob of {render} (the per-application values the release actually receives)')

try:
    for render, base, label in ((dev_render, int(dev_base), 'dev'),
                                (infra_render, int(infra_base), 'infra')):
        got = sentinels(render)
        if got != base:
            bad(f't9: {label} umbrella render has {got} OVERRIDE_ lines, expected the pinned baseline {base}. If a pre-existing sentinel legitimately moved, update the constant in the same change and say why in the commit message; this ticket must not change it.')
        ok(f't9: {label} umbrella sentinel sweep unchanged at the pinned baseline ({got} line)')

    for render, label in ((dev_render, 'dev'), (infra_render, 'infra')):
        blob = app_json(render, 'forgejo')
        if 'OVERRIDE_' in blob:
            bad(f't9: the {label} forgejo Application values JSON carries an OVERRIDE_* sentinel: {blob[:300]}')
        ok(f't9: the {label} forgejo Application values JSON is sentinel-free')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't9: the sentinel sweep could not be evaluated ({type(e).__name__}: {e})')
PY
  then
    checks=$((checks + $(cat "$WORK/t9-count")))
  else
    exit 1
  fi
fi

# --- t10: the service trio survives the LFS work (C02 AC6, C03 AC7) --------
# Static: no helm needed. LFS changes config, not routing — with
# SERVE_DIRECT=false no git client ever contacts the storage host, so the
# trio's proxy leg is legitimately untouched and the existing legs must
# simply still be there.
if python3 - "$DEV_VALUES" "$INFRA_VALUES" "$WORK/t10-count" <<'PY'
import re, sys, yaml

dev_values, infra_values, count_file = sys.argv[1:4]
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
    # ComposerError) — services values files use them, so only the value-
    # position markers are rewritten. Alias targets are never asserted here,
    # so the ANCHOR_REF placeholders are inert.
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

try:
    for path, cluster in ((dev_values, 'dev'), (infra_values, 'infra')):
        sv = load(path)
        cf = (sv.get('charts') or {}).get('forgejo')
        if not isinstance(cf, dict):
            bad(f't10: {path} lost its charts.forgejo entry — LFS must not move or rename the app')
        if cf.get('namespace') != 'default':
            bad(f't10: {path} charts.forgejo.namespace is {cf.get("namespace")!r}, expected default')
        subs = (sv.get('ingress') or {}).get('subdomains') or {}
        hosts = ['git'] + (['forgejo'] if cluster == 'infra' else [])
        for host in hosts:
            e = subs.get(host)
            if not isinstance(e, dict):
                bad(f't10: {path} lost its ingress.subdomains.{host} entry')
            if e.get('service') != f'{cluster}-forgejo-http':
                bad(f't10: {path} ingress.subdomains.{host}.service is {e.get("service")!r}, expected {cluster}-forgejo-http')
            if e.get('port') != 3000:
                bad(f't10: {path} ingress.subdomains.{host}.port is {e.get("port")!r}, expected 3000')
        ok(f't10: {path} keeps charts.forgejo plus the {"git + forgejo" if cluster == "infra" else "git"} proxy leg to {cluster}-forgejo-http:3000')

    with open(dev_values) as f:
        dev_raw = f.read()
    s3_hits = [i + 1 for i, l in enumerate(dev_raw.splitlines()) if 's3' in l]
    if s3_hits:
        bad(f't10: services/dev gained s3 mentions at line(s) {s3_hits} (baseline 0) — SERVE_DIRECT=false means no client ever contacts the storage host, so dev gains no storage route (C02 AC6)')
    ok('t10: services/dev/prod/values.yaml still has zero s3 mentions (no new storage route)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't10: the trio checks could not be evaluated ({type(e).__name__}: {e})')
PY
then
  checks=$((checks + $(cat "$WORK/t10-count")))
else
  exit 1
fi

# --- t11: blast radius — the shared gateway stays untouched (plan D4) ------
# Enabling s3.enableAuth in charts/seaweedfs would auto-generate a fresh
# credential set and break every existing gateway consumer (Loki first), and a
# -s3.config flag is the same blast radius through the back door. Auth is
# already enforced by the filer-backed store, so this leg pins the file and
# forbids the back door.
if [ -z "$DIFF_BASE" ]; then
  skip "t11: no main/origin/main ref to diff against; the blast-radius leg was not run (set LFS_DIFF_BASE)"
else
  if python3 - "$DIFF_BASE" "$SWD_VALUES" "$WORK/t11-count" <<'PY'
import re, subprocess, sys

base, swd_values, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def git(*args):
    return subprocess.run(('git',) + args, capture_output=True, text=True).stdout

try:
    moved = git('diff', '--name-only', base, '--', 'charts/seaweedfs', 'services/infra/prod/templates').split()
    if moved:
        bad(f't11: {moved} changed against {base} — the shared SeaweedFS chart and the infra gateway/PVC templates are out of scope for this ticket (plan D4, C03 Files-in-scope)')
    ok('t11: charts/seaweedfs and services/infra/prod/templates are byte-untouched against the fork base')

    text = open(swd_values).read()
    if re.search(r'(?m)^\s*enableAuth\s*:\s*true', text):
        bad(f't11: {swd_values} enabled s3.enableAuth — the flag auto-generates a new credential set and breaks every existing gateway consumer (Loki first); the plan bans it (D4)')
    if not re.search(r'(?m)^\s*#enableAuth:\s*true\s*$', text):
        bad(f't11: the commented `#enableAuth: true` line in {swd_values} is gone or reworded — the next reader must still find that the flag exists and is deliberately off')
    ok(f't11: {swd_values} still ships s3.enableAuth commented out')

    grep = git('grep', '-n', '--', '-e', '-s3.config', '--', 'charts/seaweedfs', 'services', 'custom-values')
    if grep.strip():
        bad(f't11: a -s3.config flag appeared: {grep.strip()[:300]} (same blast radius as enabling auth — plan D4)')
    ok('t11: no -s3.config flag anywhere in charts/seaweedfs, services or custom-values')

    jobs = git('grep', '-ln', 'kind: Job', '--', 'services')
    bucket_cmds = git('grep', '-n', '-e', 's3.bucket', '-e', 'weed shell', '--', 'services', 'charts/seaweedfs')
    if jobs.strip() or bucket_cmds.strip():
        bad(f't11: bucket-provisioning machinery appeared in the deployed surface (jobs: {jobs.strip()[:200]!r}, cmds: {bucket_cmds.strip()[:200]!r}) — identity and bucket creation are User actions UA1-UA3 against the gateway shell, never a repo Job')
    ok('t11: no weed/bucket Job or shell command introduced in services or charts/seaweedfs')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't11: the blast-radius checks could not be evaluated ({type(e).__name__}: {e})')
PY
  then
    checks=$((checks + $(cat "$WORK/t11-count")))
  else
    exit 1
  fi
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: forgejo-lfs checks (%d ok)\n' "$checks"
