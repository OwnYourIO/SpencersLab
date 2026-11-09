#!/usr/bin/env bash
# Git LFS contract (cf-122 feat-lfs-s3-optional, reworking the cf-104 master
# contract): the forgejo wrapper chart gates ALL S3-only LFS artifacts on the
# merged `gitea.config.lfs.STORAGE_TYPE == "minio"` declaration — default OFF
# (LFS stays on, objects land locally on the data volume) — dev takes the
# not-enabled stance, and infra's effective S3 config is byte-stable (plan A9:
# the whole-render delta is exactly the pinned four-item list).
#
# Leg -> acceptance-criteria map (plan Test contract, section A):
#   t1   harness: dependency builds on /tmp copies + A9 oracle chart        plan Commands
#   t2   default OFF: bare render carries zero S3 artifacts (A10 residual)  AC1 — red-first
#   t3   gate-open render: ESO object-identical + shape Secret + 3-key [lfs] AC2 — red-first
#   t4   env legs: 8 on init-app-ini, 6 gated optional, 2 core hard         AC1/AC2 — red-first
#   t5   dev effective = the local stance (no [lfs], [server] stable)       AC3/AC4 — red-first
#   t6   infra effective = 7 keys of record + A9 whole-render delta         AC3 — red-first
#   t7   shape constants single-sourced in the gated template               AC2 — red-first
#   t8   storage-aware UUID leg: infra keeps, dev drops the forgejo-s3 key  AC4 — dev half red-first
#   t9   sentinel sweeps at the pinned baselines + app-JSON sentinel-free   AC6 (green across)
#   t10  trio survives                                                      AC5 (green across)
#   t11  blast radius: shared gateway + runner + infra/gpu custom-values    AC5 (new clause red-first)
#   t12  C02 SSA posture: dev+infra charts.forgejo "true", runner boundary  cf-122 C02 AC1/AC5 (red-first)
#        "false" on dev forgejo-runner-dev + gpu forgejo-runner-gpu
#
# Red-first by design: the run STOPS at its first failing leg — on the
# pre-C01 tree that is t2 (the gate does not exist yet, so the bare render
# still carries the S3 artifacts); every later leg is red on that tree too,
# independently. A stopped run is the contract working, not a broken suite;
# the legs behind it re-run once C01 lands.
#
# The A9 oracle is rebuilt from git on every run: the pre-change chart is
# `git archive`d from the fork base into the /tmp workspace and rendered the
# same way as the working renders. No committed render artifact — the
# comparison holds on any checkout. "Byte-identical" means parsed-object
# equality (the C01 chunk updates the ESO header comment, and comments are
# not part of object identity); inline-config sections compare as exact
# strings (their stringData values are raw ini, no comments).
#
# The oracle is era-aware: the A9 four-item delta is only measurable
# against a fork base that predates C01 (the base chart renders the ESO
# ungated). Against a post-C01 base the base and working charts differ by
# nothing C02 may change, so t3 compares the gate-open ESO against the
# base's own gate-open capture and t6 asserts whole-render object
# invariance instead of the historical delta.
#
# Blast-radius and oracle legs diff against the FORK base (the point where
# this branch left main), not main itself: main has moved ahead of the fork
# and touches services/{dev,gpu} values, which a main base would count as
# this ticket's diff. LFS_DIFF_BASE re-points it if the fork base moves.
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
# static legs (t7, t8, t10, t11, t12) always run.
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
GPU_VALUES="services/gpu/prod/values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
INFRA_CV="custom-values/infra/prod-values.yaml"
SWD_VALUES="charts/seaweedfs/values.yaml"
SHAPE_TPL="$FJ_CHART/templates/secret-forgejo-lfs-shape.yaml"

DEV_SENT_BASELINE=1
INFRA_SENT_BASELINE=1

# Fork base, not raw main: main has moved ahead of the fork and touches
# services/{dev,gpu} values, which a main base would count as this ticket's
# diff. LFS_DIFF_BASE re-points it if the fork base legitimately moves.
DIFF_BASE="${LFS_DIFF_BASE:-$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || git rev-parse --verify main 2>/dev/null || git rev-parse --verify origin/main 2>/dev/null || true)}"

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
pre_ok=0   # 1 once the A9 oracle (pre-change chart + renders) is ready

# The gate-open values file: t3's working render and t1's pre-gate oracle
# capture share it, so the ESO invariance compares like-for-like (same
# activation keys, same u5 sentinel — an indexed --set is never used, it
# nulls list entries).
gate_vals="$WORK/gate-open-values.yaml"
cat >"$gate_vals" <<'VALS'
forgejo:
  gitea:
    config:
      lfs:
        STORAGE_TYPE: minio
        MINIO_ENDPOINT: s3.spencerslab.com
        MINIO_USE_SSL: true
VALS

# --- t1: harness (dependency builds on copies + A9 oracle) ------------------
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
    # A9 oracle: the pre-change chart at the fork base, rendered the same way
    # as the working renders below, so t3/t4/t5/t6 can prove their
    # byte-identity and delta claims against the actual fork-base state
    # (era-aware: pre-C01 bases carry the ungated ESO in the bare render,
    # post-C01 bases gate it closed — t3/t6 pick the matching comparison).
    if [ -n "$DIFF_BASE" ]; then
      mkdir -p "$WORK/pre-root"
      if git archive "$DIFF_BASE" "$FJ_CHART" 2>"$WORK/pre-archive.err" | tar -x -C "$WORK/pre-root"; then
        pre_log="$WORK/pre-root/$FJ_CHART/dependency-build.log"
        if (cd "$WORK/pre-root/$FJ_CHART" && "$helm_bin" dependency build .) >"$pre_log" 2>&1; then
          extract_slice "$DEV_CV" forgejo "$WORK/forgejo-dev-slice.yaml"
          extract_slice "$INFRA_CV" forgejo "$WORK/forgejo-infra-slice.yaml"
          pre_bare_err="$WORK/pre-bare.err"
          pre_dev_err="$WORK/pre-dev.err"
          pre_infra_err="$WORK/pre-infra.err"
          pre_gate_err="$WORK/pre-gate.err"
          if "$helm_bin" template dev "$WORK/pre-root/$FJ_CHART" \
              --set domain=scifi.farm --set clusterName=dev \
              --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
              --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
              --set bitwardenIds.forgejo-s3=u5 >"$WORK/pre-bare.yaml" 2>"$pre_bare_err" \
            && "$helm_bin" template dev "$WORK/pre-root/$FJ_CHART" \
              -f "$WORK/forgejo-dev-slice.yaml" \
              --set domain=scifi.farm --set clusterName=dev \
              >"$WORK/pre-dev.yaml" 2>"$pre_dev_err" \
            && "$helm_bin" template infra "$WORK/pre-root/$FJ_CHART" \
              -f "$WORK/forgejo-infra-slice.yaml" \
              --set domain=spencerslab.com --set clusterName=infra \
              >"$WORK/pre-infra.yaml" 2>"$pre_infra_err" \
            && "$helm_bin" template dev "$WORK/pre-root/$FJ_CHART" \
              -f "$gate_vals" \
              --set domain=scifi.farm --set clusterName=dev \
              --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
              --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
              --set bitwardenIds.forgejo-s3=u5 >"$WORK/pre-gate.yaml" 2>"$pre_gate_err"; then
            pre_ok=1
          else
            tail -n 30 "$pre_bare_err" "$pre_dev_err" "$pre_infra_err" "$pre_gate_err" 2>/dev/null >&2 || true
            fail "t1: a pre-change oracle render failed (logs kept at $WORK/pre-*.err)"
          fi
        else
          if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$pre_log"; then
            skip "t1: the A9 oracle chart could not reach the registry; the byte-identity sub-checks (t3/t4/t5/t6) were not run (log kept at $pre_log)"
          else
            tail -n 30 "$pre_log" >&2
            fail "t1: helm dependency build of the pre-change chart at $DIFF_BASE failed (log kept at $pre_log)"
          fi
        fi
      else
        tail -n 5 "$WORK/pre-archive.err" >&2
        fail "t1: git archive of $FJ_CHART at $DIFF_BASE failed (the A9 oracle cannot be rebuilt)"
      fi
    else
      skip "t1: no fork-base ref to rebuild the A9 oracle from; the byte-identity sub-checks (t3/t4/t5/t6) were not run (set LFS_DIFF_BASE)"
    fi

    if [ "$pre_ok" -eq 1 ]; then
      ok "t1: helm dependency build succeeds for $FJ_CHART, $DEVUMB and $INFRAUMB on copies, and the A9 oracle chart renders at fork base ${DIFF_BASE:0:12} ($("$helm_bin" version --short 2>/dev/null || echo helm))"
    else
      ok "t1: helm dependency build succeeds for $FJ_CHART, $DEVUMB and $INFRAUMB on copies ($("$helm_bin" version --short 2>/dev/null || echo helm))"
    fi

    # ---- t2: default OFF — bare render carries zero S3 artifacts (AC1) -----
    # The gate is closed without any [lfs] declaration, so nothing S3 may
    # render. The six env legs are the pinned structural residual (A10): the
    # env list is the subchart's only env surface and it is static, so the
    # names remain — but every referenced Secret is absent by design.
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
    # The sanctioned closed-gate proof (plan A13): a gated template renders
    # nothing, and --show-only answers "could not find template".
    so_out="$WORK/t2-showonly.out"
    so_err="$WORK/t2-showonly.err"
    if "$helm_bin" template dev "$fj_copy" --show-only templates/secret-forgejo-s3.yaml \
      --set domain=scifi.farm --set clusterName=dev \
      --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
      --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
      --set bitwardenIds.forgejo-s3=u5 >"$so_out" 2>"$so_err"; then
      fail "t2: --show-only rendered the forgejo-s3 ExternalSecret — without an [lfs] declaration the gate must be closed, so no S3 artifact may render (default OFF)"
    fi
    grep -q 'could not find template' "$so_err" ||
      fail "t2: the closed-gate proof is not the sanctioned 'could not find template' (got: $(head -n 1 "$so_err"))"
    ok "t2: closed-gate proof — --show-only of templates/secret-forgejo-s3.yaml answers 'could not find template' on the bare render"
    if python3 - "$chart_out" "$WORK/t2-count" <<'PY'
import re, sys, yaml

render, count_file = sys.argv[1], sys.argv[2]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def docs_of(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]

# The six env legs that remain on a gate-closed render (A10 residual): the
# list is static values, so the names persist; the referenced Secrets do not.
LFS_LEGS = {
    'FORGEJO__LFS__MINIO_ACCESS_KEY_ID': ('forgejo-s3-secret', 'access_key_id'),
    'FORGEJO__LFS__MINIO_SECRET_ACCESS_KEY': ('forgejo-s3-secret', 'secret_access_key'),
    'FORGEJO__LFS__MINIO_BUCKET': ('forgejo-lfs-shape', 'MINIO_BUCKET'),
    'FORGEJO__LFS__MINIO_BUCKET_LOOKUP': ('forgejo-lfs-shape', 'MINIO_BUCKET_LOOKUP'),
    'FORGEJO__LFS__MINIO_CHECKSUM_ALGORITHM': ('forgejo-lfs-shape', 'MINIO_CHECKSUM_ALGORITHM'),
    'FORGEJO__LFS__SERVE_DIRECT': ('forgejo-lfs-shape', 'SERVE_DIRECT'),
}

try:
    docs = docs_of(render)
    raw = open(render).read()

    es = [d for d in docs if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if es:
        bad(f't2: the bare render still carries the forgejo-s3-secret ExternalSecret ({len(es)}x) — the gate must be closed without any [lfs] declaration')
    shape = [d for d in docs if d.get('kind') == 'Secret'
             and (d.get('metadata') or {}).get('name') == 'forgejo-lfs-shape']
    if shape:
        bad(f't2: the bare render still carries the forgejo-lfs-shape Secret ({len(shape)}x) — the gate must be closed without any [lfs] declaration')
    inlines = [d for d in docs if d.get('kind') == 'Secret'
               and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
    if len(inlines) != 1:
        bad(f't2: {len(inlines)} inline-config Secrets in the render, expected exactly one')
    secs = (inlines[0].get('stringData') or {})
    if 'lfs' in secs:
        bad(f't2: the bare render carries an [lfs] section ({secs["lfs"]!r}) — the chart ships NO [lfs] keys; the shape constants are template-injected (plan D2)')
    ok('t2: the bare render carries no forgejo-s3-secret ESO, no forgejo-lfs-shape Secret, no [lfs] section (default OFF)')

    if 'STORAGE_TYPE' in raw:
        bad('t2: STORAGE_TYPE appears in the bare render — the activation switch is an instance declaration only, and none is present here')
    ok('t2: zero STORAGE_TYPE hits anywhere in the bare render')

    leg_names = re.findall(r'^\s*- name: (FORGEJO__LFS__[A-Z_]+)\s*$', raw, re.M)
    if sorted(leg_names) != sorted(LFS_LEGS):
        missing = sorted(set(LFS_LEGS) - set(leg_names))
        extra = sorted(set(leg_names) - set(LFS_LEGS))
        bad(f't2: the bare render carries {sorted(leg_names)} FORGEJO__LFS__ legs (missing {missing}, unexpected {extra}) — expected exactly the six pinned residuals')
    def minio_residual(l):
        # name: lines are env-list items (carrying a "- " prefix); key: lines
        # are nested secretKeyRef fields (no prefix).
        return (re.match(r'\s*(?:- )?name: FORGEJO__LFS__MINIO_[A-Z_]+\s*$', l)
                or re.match(r'\s*key: MINIO_[A-Z_]+\s*$', l)) is not None
    minio_lines = [l for l in raw.splitlines() if 'MINIO' in l]
    if len(minio_lines) != 8 or not all(minio_residual(l) for l in minio_lines):
        bad(f't2: the bare render has {len(minio_lines)} MINIO lines, expected exactly 8 all on env-leg name:/key: lines (the A10 residual, nothing else): {minio_lines!r}')
    ok('t2: exactly six FORGEJO__LFS__* env entries and all 8 MINIO_* hits sit on their name:/key: lines (the pinned A10 residual, no more)')

    for banned in ('storage', 'attachment', 'picture'):
        if banned in secs:
            bad(f't2: the inline-config Secret renders a [{banned}] section — a [storage] section would move attachments/avatars/packages to S3 too; every LFS key lives in [lfs]')
    deps = [d for d in docs if d.get('kind') == 'Deployment']
    if len(deps) != 1:
        bad(f't2: {len(deps)} Deployments in the bare render, expected exactly one')
    pod = ((deps[0].get('spec') or {}).get('template') or {}).get('spec') or {}
    main = next((c for c in (pod.get('containers') or []) if (c or {}).get('name') == 'forgejo'), None)
    if main is None:
        bad('t2: no main forgejo container in the render')
    leaked = [e.get('name') for e in (main.get('env') or []) if (e or {}).get('name', '').startswith('FORGEJO__')]
    if leaked:
        bad(f't2: the main forgejo container carries FORGEJO__ env legs {leaked} — inline config is applied by init-app-ini only')
    override = sum(1 for l in raw.splitlines() if 'OVERRIDE_' in l)
    if override:
        bad(f't2: the bare render carries {override} OVERRIDE_* line(s) — the --set list resolves every chart sentinel, so none may survive (the unconsumed forgejo-s3 --set must stay harmless)')
    ok('t2: no storage/attachment/picture section, no FORGEJO__ legs on the main container, and 0 OVERRIDE_* lines in the bare render')

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

    # ---- t3: gate-open render (AC2) ----------------------------------------
    # The shared gate-open values file (never an indexed --set — it nulls
    # list entries) opts the render into S3 with exactly the three activation
    # keys. The ESO body must come out object-identical to the fork-base
    # gate-open capture (pre-C01 bases carry it ungated in every render,
    # post-C01 bases gate it — t1 captures it gate-open either way); the
    # shape Secret carries the four A14 constants.
    gate_out="$WORK/gate-render.yaml"
    gate_err="$WORK/gate-render.err"
    if ! "$helm_bin" template dev "$fj_copy" -f "$gate_vals" \
      --set domain=scifi.farm --set clusterName=dev \
      --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
      --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
      --set bitwardenIds.forgejo-s3=u5 \
      >"$gate_out" 2>"$gate_err"; then
      tail -n 30 "$gate_err" >&2
      fail "t3: helm template of $FJ_CHART with the gate-open values file failed (log kept at $gate_err)"
    fi
    [ -s "$gate_out" ] || fail "t3: the gate-open render produced nothing"
    if python3 - "$gate_out" "$WORK/pre-gate.yaml" "$WORK/t3-count" <<'PY'
import sys, yaml

render, pre_gate, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def docs_of(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]

# A14: the four shape constants of record. SERVE_DIRECT is the STRING
# 'false' (D7: env values are strings; the pre-change inline render also
# produced the literal false).
SHAPE = {
    'MINIO_BUCKET': 'git-lfs',
    'MINIO_BUCKET_LOOKUP': 'path',
    'MINIO_CHECKSUM_ALGORITHM': 'default',
    'SERVE_DIRECT': 'false',
}
# The three activation keys of the -f values file, rendered by printf %v.
ACTIVATION = {'STORAGE_TYPE': 'minio', 'MINIO_ENDPOINT': 's3.spencerslab.com', 'MINIO_USE_SSL': 'true'}

def diff_paths(a, b, path=''):
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            p = f'{path}.{k}' if path else str(k)
            if k not in a or k not in b:
                out.append(p)
            else:
                out.extend(diff_paths(a[k], b[k], p))
    elif a != b:
        out.append(path)
    return out

def ini(section):
    out = {}
    for line in (section or '').splitlines():
        if not line.strip():
            continue
        if '=' not in line:
            bad(f't3: the inline-config section has a non KEY=VALUE line {line!r}')
        k, v = line.split('=', 1)
        out[k] = v
    return out

try:
    docs = docs_of(render)
    es = [d for d in docs if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if len(es) != 1:
        bad(f't3: {len(es)} forgejo-s3-secret ExternalSecrets in the gate-open render, expected exactly one (the gate must be open on STORAGE_TYPE=minio)')
    es = es[0]
    spec = es.get('spec') or {}
    stores = []
    if spec.get('secretStoreRef'):
        stores.append(spec['secretStoreRef'])
    for e in (spec.get('data') or []):
        ref = ((e or {}).get('sourceRef') or {}).get('storeRef')
        if ref:
            stores.append(ref)
    if not stores or any(st.get('name') != 'bitwarden-login' or st.get('kind') != 'SecretStore' for st in stores):
        bad(f't3: the ExternalSecret stores are {stores!r}, expected the bitwarden-login SecretStore (the item is a LOGIN: username = access key id, password = secret access key)')
    target = spec.get('target') or {}
    if target.get('name') != 'forgejo-s3-secret' or target.get('creationPolicy') != 'Owner' or spec.get('refreshInterval') != '1h':
        bad(f't3: the ExternalSecret target/refresh is {target!r} / {spec.get("refreshInterval")!r}, expected name forgejo-s3-secret, creationPolicy Owner, refreshInterval 1h (the cf-104 shape, unchanged)')
    entries = spec.get('data') or []
    got = {}
    for e in entries:
        rr = (e or {}).get('remoteRef') or {}
        got[(e or {}).get('secretKey')] = (rr.get('key'), rr.get('property'),
                                           rr.get('conversionStrategy'),
                                           rr.get('decodingStrategy'),
                                           rr.get('metadataPolicy'))
    want = {'access_key_id': ('u5', 'username'), 'secret_access_key': ('u5', 'password')}
    if set(got) != set(want):
        bad(f't3: data secretKeys are {sorted(got)}, expected exactly access_key_id + secret_access_key')
    for key, (want_key, want_prop) in want.items():
        rkey, rprop, conv, dec, meta = got[key]
        if rkey != want_key:
            bad(f't3: {key} reads remoteRef key {rkey!r}, expected the bitwardenIds.forgejo-s3 value passed in ({want_key!r})')
        if rprop != want_prop:
            bad(f't3: {key} reads property {rprop!r}, expected {want_prop!r}')
        if (conv, dec, meta) != ('Default', 'None', 'None'):
            bad(f't3: {key} boilerplate is {(conv, dec, meta)!r}, expected (Default, None, None)')
    if pre_gate:
        pre_es = [d for d in docs_of(pre_gate) if d.get('kind') == 'ExternalSecret'
                  and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
        if len(pre_es) != 1:
            bad(f't3: the fork-base gate-open capture carries {len(pre_es)} forgejo-s3-secret ExternalSecrets, expected exactly one (the A9 oracle broke)')
        d = diff_paths(pre_es[0], es)
        if d:
            bad(f't3: the gate-open ESO differs from the fork-base gate-open capture at {d[:8]} — the ESO body must stay object-invariant against the fork base (plan A9)')
    ok('t3: the gate-open render carries the forgejo-s3-secret ESO, object-identical to the fork-base gate-open capture (remoteRef u5, LOGIN mapping, ESO boilerplate)' if pre_gate
       else 't3: the gate-open render carries the forgejo-s3-secret ESO with the pinned LOGIN mapping and ESO boilerplate')

    shape = [d for d in docs if d.get('kind') == 'Secret'
             and (d.get('metadata') or {}).get('name') == 'forgejo-lfs-shape']
    if len(shape) != 1:
        bad(f't3: {len(shape)} forgejo-lfs-shape Secrets in the gate-open render, expected exactly one (the template-injected single source for the shape constants)')
    shape = shape[0]
    if shape.get('type') != 'Opaque':
        bad(f't3: the shape Secret type is {shape.get("type")!r}, expected Opaque')
    sd = shape.get('stringData') or {}
    if sd != SHAPE:
        bad(f't3: the shape Secret stringData is {sd!r}, expected exactly {SHAPE!r} (A14 values; SERVE_DIRECT is the string form, D7 — an unquoted false would parse as a bool)')
    ok('t3: the forgejo-lfs-shape Secret renders with exactly the four A14 constants (SERVE_DIRECT the string false)')

    inlines = [d for d in docs if d.get('kind') == 'Secret'
               and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
    if len(inlines) != 1:
        bad(f't3: {len(inlines)} inline-config Secrets in the gate-open render, expected exactly one')
    secs = (inlines[0].get('stringData') or {})
    got_lfs = ini(secs.get('lfs', ''))
    if got_lfs != ACTIVATION:
        bad(f't3: the gate-open inline [lfs] is {got_lfs!r}, expected exactly the three activation keys {ACTIVATION!r} — the shape keys must no longer live in values (plan D2)')
    ok('t3: the gate-open inline [lfs] is exactly the three activation keys from the -f values file (no chart-shape keys)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't3: the gate-open render could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t3-count")))
    else
      exit 1
    fi

    # ---- t4: the eight config env legs (AC1/AC2) ---------------------------
    # Counted on FORGEJO__* names, not the whole env list: the subchart also
    # injects GITEA_* envs. Two core legs stay HARD (no optional — those
    # Secrets always exist, and softening them would mask a real
    # misconfiguration); the six gated legs are the only ones allowed
    # optional: true (A2 — the k8s-native soft dependency that keeps the
    # gate-closed pod bootable).
    if python3 - "$chart_out" "$WORK/pre-bare.yaml" "$WORK/t4-count" <<'PY'
import sys, yaml

render, pre_bare, count_file = sys.argv[1:4]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

CORE = {
    'FORGEJO__DATABASE__PASSWD': ('pg-forgejo-secret', 'password'),
    'FORGEJO__SECURITY__SECRET_KEY': ('forgejo-secret', 'SECRET_KEY'),
}
GATED = {
    'FORGEJO__LFS__MINIO_ACCESS_KEY_ID': ('forgejo-s3-secret', 'access_key_id'),
    'FORGEJO__LFS__MINIO_SECRET_ACCESS_KEY': ('forgejo-s3-secret', 'secret_access_key'),
    'FORGEJO__LFS__MINIO_BUCKET': ('forgejo-lfs-shape', 'MINIO_BUCKET'),
    'FORGEJO__LFS__MINIO_BUCKET_LOOKUP': ('forgejo-lfs-shape', 'MINIO_BUCKET_LOOKUP'),
    'FORGEJO__LFS__MINIO_CHECKSUM_ALGORITHM': ('forgejo-lfs-shape', 'MINIO_CHECKSUM_ALGORITHM'),
    'FORGEJO__LFS__SERVE_DIRECT': ('forgejo-lfs-shape', 'SERVE_DIRECT'),
}

def init_legs(path):
    for d in yaml.safe_load_all(open(path)):
        if not d or d.get('kind') != 'Deployment':
            continue
        pod = ((d.get('spec') or {}).get('template') or {}).get('spec') or {}
        init = next((c for c in (pod.get('initContainers') or [])
                     if (c or {}).get('name') == 'init-app-ini'), None)
        if init is None:
            bad(f't4: no init-app-ini container in {path} — the subchart writes app.ini in that init container, so the env legs have to sit there')
        out = {}
        for e in (init.get('env') or []):
            name = (e or {}).get('name') or ''
            if name.startswith('FORGEJO__'):
                out[name] = e
        return out
    bad(f't4: no Deployment in {path}')

try:
    got = init_legs(render)
    want = dict(CORE)
    want.update(GATED)
    if set(got) != set(want):
        missing = sorted(set(want) - set(got))
        extra = sorted(set(got) - set(want))
        bad(f't4: init-app-ini carries {len(got)} FORGEJO__ legs (missing {missing}, unexpected {extra}), expected exactly the eight {sorted(want)}')
    for name, (secret, key) in want.items():
        ref = (((got[name].get('valueFrom') or {}).get('secretKeyRef')) or {})
        if ref.get('name') != secret or ref.get('key') != key:
            bad(f't4: {name} reads {ref.get("name")}/{ref.get("key")!r}, expected {secret}/{key!r}')
    for name in GATED:
        ref = ((got[name].get('valueFrom') or {}).get('secretKeyRef')) or {}
        if ref.get('optional') is not True:
            bad(f't4: {name} carries optional={ref.get("optional")!r} — the six gated legs must be optional: true (A2: on a local instance the referenced Secrets do not exist, and a hard ref wedges init-app-ini in CreateContainerConfigError, the live dev incident)')
    ok('t4: init-app-ini carries exactly eight FORGEJO__ legs — 2 core + 6 gated, the gated refs pinned to forgejo-s3-secret / forgejo-lfs-shape, all six optional: true')

    for name, (secret, key) in CORE.items():
        ref = ((got[name].get('valueFrom') or {}).get('secretKeyRef')) or {}
        if set(ref) != {'name', 'key'}:
            bad(f't4: the core leg {name} carries the unexpected secretKeyRef fields {sorted(ref)} — the core legs stay byte-unchanged WITHOUT optional (still hard)')
        if ref.get('name') != secret or ref.get('key') != key:
            bad(f't4: the core leg {name} reads {ref.get("name")}/{ref.get("key")!r}, expected {secret}/{key!r}')
    if pre_bare:
        pre = init_legs(pre_bare)
        for name in CORE:
            if pre.get(name) != got[name]:
                bad(f't4: the core leg {name} changed vs the pristine capture: {pre.get(name)!r} -> {got[name]!r}')
    ok('t4: the two core legs (DB password, SECRET_KEY) are byte-unchanged vs the pristine capture and carry no optional (still hard)' if pre_bare
       else 't4: the two core legs (DB password, SECRET_KEY) keep their exact shape and carry no optional (still hard)')

    docs = [d for d in yaml.safe_load_all(open(render)) if d]
    dep = next(d for d in docs if d.get('kind') == 'Deployment')
    pod = ((dep.get('spec') or {}).get('template') or {}).get('spec') or {}
    main = next((c for c in (pod.get('containers') or []) if (c or {}).get('name') == 'forgejo'), None)
    if main is None:
        bad('t4: no forgejo container in the render')
    main_legs = [e.get('name') for e in (main.get('env') or []) if (e or {}).get('name', '').startswith('FORGEJO__')]
    if main_legs:
        bad(f't4: the main forgejo container carries FORGEJO__ env legs {main_legs} — inline config is applied by init-app-ini only; credentials on the app container would also re-expose them to the running process environment')
    ok('t4: the main forgejo container carries no FORGEJO__* env')

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

    # ---- t5: dev effective render = the local stance (AC3/AC4) -------------
    # Inverted from cf-104's S3 assertion: dev's slice declares no [lfs], so
    # the gate is closed and dev boots into local LFS storage on its data
    # volume (plan A5/A6/A7). The [server] section must come out
    # byte-identical to the pristine capture — LFS stays on, only the object
    # store moves.
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
    if python3 - "$dev_eff" "$WORK/pre-dev.yaml" "$DEV_CV" git.scifi.farm 'https://git.scifi.farm/' "$WORK/t5-count" <<'PY'
import re, sys, yaml

render, pre_dev, cv_file, domain, root_url, count_file = sys.argv[1:7]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def docs_of(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]

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
    docs = docs_of(render)
    raw = open(render).read()
    inlines = [d for d in docs if d.get('kind') == 'Secret'
               and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
    if len(inlines) != 1:
        bad(f't5: {len(inlines)} inline-config Secrets in the dev effective render, expected exactly one')
    secs = (inlines[0].get('stringData') or {})

    if 'lfs' in secs:
        bad(f't5: the dev effective render still carries an [lfs] section ({secs["lfs"]!r}) — dev takes the not-enabled stance: no [lfs] declaration, local storage (plan D6)')
    es = [d for d in docs if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if es:
        bad(f't5: the dev effective render still carries the forgejo-s3-secret ExternalSecret ({len(es)}x) — the gate must be closed for dev')
    shape = [d for d in docs if d.get('kind') == 'Secret'
             and (d.get('metadata') or {}).get('name') == 'forgejo-lfs-shape']
    if shape:
        bad(f't5: the dev effective render still carries the forgejo-lfs-shape Secret ({len(shape)}x) — the gate must be closed for dev')
    if 'STORAGE_TYPE' in raw:
        bad('t5: STORAGE_TYPE appears in the dev effective render — the not-enabled stance carries no activation switch')
    def minio_residual(l):
        # name: lines are env-list items (carrying a "- " prefix); key: lines
        # are nested secretKeyRef fields (no list dash).
        return (re.match(r'\s*(?:- )?name: FORGEJO__LFS__MINIO_[A-Z_]+\s*$', l)
                or re.match(r'\s*key: MINIO_[A-Z_]+\s*$', l)) is not None

    minio_lines = [l for l in raw.splitlines() if 'MINIO' in l]
    if len(minio_lines) != 8 or not all(minio_residual(l) for l in minio_lines):
        bad(f't5: the dev render has {len(minio_lines)} MINIO lines, expected exactly 8 all on the pinned env-leg name:/key: lines (A10 — the env list is static, the Secrets are absent): {minio_lines!r}')
    ok('t5: dev is the local stance — no [lfs], no forgejo-s3-secret, no forgejo-lfs-shape, zero STORAGE_TYPE, and the MINIO residual only on the eight env-leg lines (A10)')

    server_raw = secs.get('server') or ''
    server = ini(server_raw)
    if server.get('LFS_START_SERVER') != 'true':
        bad(f't5: [server] LFS_START_SERVER is {server.get("LFS_START_SERVER")!r}, expected true (dev keeps the LFS server ON; without it the batch endpoint stays 404 — plan D6)')
    for key, want in (('DOMAIN', domain), ('ROOT_URL', root_url), ('SSH_PORT', '22222')):
        if server.get(key) != want:
            bad(f't5: [server] {key} is {server.get(key)!r}, expected {want!r} (the identity block must stay intact; the flip touches only the object store)')
    if pre_dev:
        pre_secs = (next(d for d in docs_of(pre_dev) if d.get('kind') == 'Secret'
                         and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')).get('stringData') or {})
        if pre_secs.get('server') != server_raw:
            bad(f't5: dev [server] is not byte-identical to the pristine capture:\n  pre: {pre_secs.get("server")!r}\n  post: {server_raw!r}')
    ok('t5: dev [server] keeps LFS_START_SERVER=true + DOMAIN/ROOT_URL/SSH_PORT and is byte-identical to the pristine capture' if pre_dev
       else 't5: dev [server] keeps LFS_START_SERVER=true + DOMAIN/ROOT_URL/SSH_PORT=22222 (identity keys intact)')

    for banned in ('storage', 'attachment', 'picture'):
        if banned in secs:
            bad(f't5: the dev effective render introduces a [{banned}] section — attachments/avatars/packages stay on the PVC')
    ok('t5: no storage/attachment/picture section in the dev effective render')

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

    # ---- t6: infra effective render = zero regression (AC3, plan A9) -------
    # The effective [lfs] re-derives from the CURRENT infra slice (the three
    # activation keys) plus the four shape constants from the gated Secret —
    # so the leg holds on any checkout with no committed golden strings. The
    # pristine-capture comparisons pin the byte-stability: [server]/[mailer]
    # unchanged, ESO object-identical, and the whole-render delta is exactly
    # the A9 four-item list.
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
    if python3 - "$infra_eff" "$WORK/pre-infra.yaml" "$INFRA_CV" git.spencerslab.com 'https://git.spencerslab.com/' "$WORK/t6-count" <<'PY'
import sys, yaml

render, pre_infra, cv_file, domain, root_url, count_file = sys.argv[1:7]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def docs_of(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]

def inline_secs(path):
    for d in docs_of(path):
        if d.get('kind') == 'Secret' and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config'):
            return (d.get('stringData') or {})
    bad(f't6: no inline-config Secret in {path}')

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

def diff_paths(a, b, path=''):
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            p = f'{path}.{k}' if path else str(k)
            if k not in a or k not in b:
                out.append(p)
            else:
                out.extend(diff_paths(a[k], b[k], p))
    elif a != b:
        out.append(path)
    return out

# A14: the four shape constants of record (template-injected single source).
SHAPE = {
    'MINIO_BUCKET': 'git-lfs',
    'MINIO_BUCKET_LOOKUP': 'path',
    'MINIO_CHECKSUM_ALGORITHM': 'default',
    'SERVE_DIRECT': 'false',
}
# The two credential env legs (gate-open infra: both Secrets exist).
CRED = {
    'FORGEJO__LFS__MINIO_ACCESS_KEY_ID': ('forgejo-s3-secret', 'access_key_id'),
    'FORGEJO__LFS__MINIO_SECRET_ACCESS_KEY': ('forgejo-s3-secret', 'secret_access_key'),
}

try:
    docs = docs_of(render)
    raw = open(render).read()
    secs = inline_secs(render)

    with open(cv_file) as f:
        cv = yaml.safe_load(f) or {}
    # Self-derived expectation: the three activation keys of the CURRENT
    # infra slice (rendered by printf %v), plus the four A14 constants.
    slice_lfs = (((cv.get('forgejo') or {}).get('forgejo') or {}).get('gitea', {}).get('config', {}).get('lfs')) or {}
    activation = {k: (str(v).lower() if isinstance(v, bool) else str(v)) for k, v in slice_lfs.items()}
    if set(activation) != {'STORAGE_TYPE', 'MINIO_ENDPOINT', 'MINIO_USE_SSL'}:
        bad(f't6: the infra slice declares lfs keys {sorted(activation)}, expected exactly the three activation keys STORAGE_TYPE/MINIO_ENDPOINT/MINIO_USE_SSL')
    if activation.get('STORAGE_TYPE') != 'minio':
        bad(f't6: the infra slice declares STORAGE_TYPE={activation.get("STORAGE_TYPE")!r}, expected minio (infra keeps S3 — the zero-regression baseline)')
    record7 = dict(activation)
    record7.update(SHAPE)

    got_inline = ini(secs.get('lfs', ''))
    if got_inline != activation:
        bad(f't6: the infra inline [lfs] is {got_inline!r}, expected exactly the three slice activation keys {activation!r} (the shape keys must come from the gated Secret, not from inline values)')
    shape_docs = [d for d in docs if d.get('kind') == 'Secret'
                  and (d.get('metadata') or {}).get('name') == 'forgejo-lfs-shape']
    if len(shape_docs) != 1:
        bad(f't6: {len(shape_docs)} forgejo-lfs-shape Secrets in the infra effective render, expected exactly one (the gate must be open for infra)')
    if (shape_docs[0].get('stringData') or {}) != SHAPE:
        bad(f't6: the shape Secret stringData is {(shape_docs[0].get("stringData") or {})!r}, expected exactly {SHAPE!r} (A14)')
    effective7 = dict(got_inline)
    effective7.update({k: v for k, v in (shape_docs[0].get('stringData') or {}).items()})
    if effective7 != record7:
        bad(f't6: the effective [lfs] resolves to {effective7!r}, expected the 7 non-credential keys of record {record7!r} (3 inline ∪ 4 shape-env, disjoint unions — plan A9)')
    pod = next(d for d in docs if d.get('kind') == 'Deployment')
    p = ((pod.get('spec') or {}).get('template') or {}).get('spec') or {}
    init = next((c for c in (p.get('initContainers') or []) if (c or {}).get('name') == 'init-app-ini'), None)
    if init is None:
        bad('t6: no init-app-ini container in the infra render')
    legs = {e.get('name'): e for e in (init.get('env') or []) if (e or {}).get('name', '').startswith('FORGEJO__LFS__')}
    for name, (secret, key) in CRED.items():
        ref = (((legs.get(name) or {}).get('valueFrom') or {}).get('secretKeyRef')) or {}
        if ref.get('name') != secret or ref.get('key') != key:
            bad(f't6: the credential leg {name} reads {ref.get("name")}/{ref.get("key")!r}, expected {secret}/{key!r}')
        if ref.get('optional') is not True:
            bad(f't6: the credential leg {name} carries optional={ref.get("optional")!r}, expected true (the post-C01 shape)')
    ok(f't6: the effective [lfs] resolves the 7 non-credential keys of record — the 3 activation keys of the current infra slice ∪ the 4 A14 shape constants — with the two optional credential legs')

    uuid = ((cv.get('forgejo') or {}).get('bitwardenIds') or {}).get('forgejo-s3')
    es = [d for d in docs if d.get('kind') == 'ExternalSecret'
          and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
    if len(es) != 1:
        bad(f't6: {len(es)} forgejo-s3-secret ExternalSecrets in the infra effective render, expected exactly one')
    es = es[0]
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
    walk(es)
    if keys != {uuid}:
        bad(f't6: forgejo-s3-secret remoteRef keys are {sorted(str(k) for k in keys)}, expected the UUID from {cv_file} ({uuid!r})')
    if any('OVERRIDE_' in str(k) for k in keys):
        bad(f't6: an OVERRIDE_* sentinel reached the rendered remoteRef key ({sorted(str(k) for k in keys)}) — this slot may never carry a placeholder')
    if pre_infra:
        pre_es = [d for d in docs_of(pre_infra) if d.get('kind') == 'ExternalSecret'
                  and (d.get('metadata') or {}).get('name') == 'forgejo-s3-secret']
        if len(pre_es) != 1:
            bad(f't6: the pristine capture carries {len(pre_es)} forgejo-s3-secret ExternalSecrets, expected exactly one (the A9 oracle broke)')
        if diff_paths(pre_es[0], es):
            bad(f't6: the infra ESO differs from the pristine capture at {diff_paths(pre_es[0], es)[:8]} — the ESO body must stay byte-untouched (plan A9)')
    ok('t6: forgejo-s3-secret resolves the real UUID from the infra slice and is object-identical to the pristine capture' if pre_infra
       else 't6: forgejo-s3-secret resolves the real UUID from the infra slice (no sentinel, no placeholder)')

    server_raw = secs.get('server') or ''
    server = ini(server_raw)
    if server.get('LFS_START_SERVER') != 'true':
        bad(f't6: [server] LFS_START_SERVER is {server.get("LFS_START_SERVER")!r}, expected true')
    for key, want in (('DOMAIN', domain), ('ROOT_URL', root_url), ('SSH_PORT', '22222')):
        if server.get(key) != want:
            bad(f't6: [server] {key} is {server.get(key)!r}, expected {want!r} (infra is the canonical git host of the lab; the flip touches only the object store)')
    want_mailer = (((cv.get('forgejo') or {}).get('forgejo') or {}).get('gitea', {}).get('config', {}).get('mailer')) or {}
    got_mailer = ini(secs.get('mailer') or '')
    want_mailer_str = {k: str(v).lower() if isinstance(v, bool) else str(v) for k, v in want_mailer.items()}
    if got_mailer != want_mailer_str:
        bad(f't6: the [mailer] section is {got_mailer!r}, expected {want_mailer_str!r} (the infra-only extras stay alone)')
    if pre_infra:
        pre_secs = inline_secs(pre_infra)
        if pre_secs.get('server') != server_raw:
            bad(f't6: infra [server] is not byte-identical to the pristine capture:\n  pre: {pre_secs.get("server")!r}\n  post: {server_raw!r}')
        if pre_secs.get('mailer') != (secs.get('mailer') or ''):
            bad(f't6: infra [mailer] is not byte-identical to the pristine capture:\n  pre: {pre_secs.get("mailer")!r}\n  post: {secs.get("mailer")!r}')
    ok('t6: infra [server] (identity + LFS_START_SERVER) and [mailer] are byte-identical to the pristine capture' if pre_infra
       else 't6: infra [server] keeps LFS_START_SERVER=true + DOMAIN/ROOT_URL/SSH_PORT and [mailer] matches the slice')

    for banned in ('storage', 'attachment', 'picture'):
        if banned in secs:
            bad(f't6: the infra effective render introduces a [{banned}] section — plan D1 keeps attachments on the PVC')
    if 'https://s3.spencerslab.com' in raw:
        bad('t6: the public gateway host appears in the infra render — that is the hairpin through the local Traefik entry that the in-cluster endpoint exists to avoid (RESEARCH Q5)')
    ok('t6: no storage/attachment/picture section and no https://s3.spencerslab.com hairpin in the infra render')

    # A9: against a pre-C01 fork base the whole-render delta vs the pristine
    # capture is exactly the four-item list — (i) [lfs] loses the four shape
    # lines, (ii) the shape Secret is the only new object, (iii) the
    # Deployment env gains the four shape legs + optional on the two cred
    # legs, (iv) the checksum/config annotation changes. Anything else
    # moving is a regression. Against a post-C01 base the base chart already
    # carries the gate and C02 touches no chart code (the pg-forgejo header
    # comment changes no manifest object), so the delta is empty by law and
    # the whole render must be object-invariant instead.
    if pre_infra:
        pre_docs = docs_of(pre_infra)
        def index_docs(ds):
            return {((d.get('kind')), (d.get('metadata') or {}).get('name')): d for d in ds}
        pre_idx, post_idx = index_docs(pre_docs), index_docs(docs)
        added = set(post_idx) - set(pre_idx)
        removed = set(pre_idx) - set(post_idx)
        pre_sd, post_sd = inline_secs(pre_infra), secs
        if not any(k in ini(pre_sd.get('lfs', '')) for k in SHAPE):
            # Post-C01 fork base: the base [lfs] carries no shape lines, so
            # the historical four-item delta is not measurable here — the
            # invariance claim is the same teeth at this era.
            if removed:
                bad(f't6 A9: objects REMOVED from the infra render vs the fork-base render: {sorted(removed)} — C02 is services-only + comment-only chart, it does not prune infra')
            if added:
                bad(f't6 A9: objects ADDED to the infra render vs the fork-base render: {sorted(added)} — C02 touches no chart code, so no object may appear or vanish')
            for key, post_o in post_idx.items():
                if key not in pre_idx:
                    continue
                d = diff_paths(pre_idx[key], post_o)
                if d:
                    bad(f't6 A9: object {key} differs from the fork-base render at {d[:8]} — C02 touches only the pg-forgejo header comment, which changes no manifest object')
            ok('t6: the infra render is object-invariant against the fork-base render (post-C01 base; C02 is services-only + comment-only chart)')
        else:
            if removed:
                bad(f't6 A9: objects REMOVED from the infra render vs the pristine capture: {sorted(removed)} — C01 adds artifacts, it does not prune infra')
            if added != {('Secret', 'forgejo-lfs-shape')}:
                bad(f't6 A9: objects added are {sorted(added)}, expected exactly {("Secret", "forgejo-lfs-shape")} (A9 item ii)')
            inline_key = next(k for k in post_idx if k[0] == 'Secret' and str(k[1]).endswith('-forgejo-inline-config'))
            dep_key = next(k for k in post_idx if k[0] == 'Deployment')
            for key, post_o in post_idx.items():
                if key in (inline_key, dep_key) or key not in pre_idx:
                    continue
                d = diff_paths(pre_idx[key], post_o)
                if d:
                    bad(f't6 A9: object {key} differs from the pristine capture at {d[:8]} — the delta is pinned to the four-item list, nothing else may move')
            if set(pre_sd) != set(post_sd):
                bad(f't6 A9: the inline-config section set changed ({sorted(pre_sd)} -> {sorted(post_sd)}) — only the [lfs] CONTENT may change')
            for k in pre_sd:
                if k != 'lfs' and pre_sd[k] != post_sd[k]:
                    bad(f't6 A9: inline-config section [{k}] is not byte-identical to the pristine capture')
            pre_lfs_lines = [l for l in (pre_sd.get('lfs') or '').splitlines() if l.strip()]
            post_lfs_lines = [l for l in (post_sd.get('lfs') or '').splitlines() if l.strip()]
            shape_lines = sorted(f'{k}={v}' for k, v in SHAPE.items())
            lost = [l for l in pre_lfs_lines if l not in post_lfs_lines]
            gained = [l for l in post_lfs_lines if l not in pre_lfs_lines]
            if sorted(lost) != shape_lines:
                bad(f't6 A9: [lfs] lost {sorted(lost)}, expected exactly the four shape lines {shape_lines} (A9 item i)')
            if gained:
                bad(f't6 A9: [lfs] gained lines {gained} — the inline section may only SHRINK by the four shape lines')
            if post_lfs_lines != [l for l in pre_lfs_lines if l not in set(shape_lines)]:
                bad(f't6 A9: the remaining [lfs] lines {post_lfs_lines!r} are not the pristine lines minus the shape lines (order-preserving subset expected)')
            if ini(pre_sd.get('lfs', '')) != record7:
                bad(f't6 A9: the pristine capture [lfs] is {ini(pre_sd.get("lfs", ""))!r}, not the 7-key record {record7!r} — the fork base is wrong or the oracle broke')

            pre_dep = next(d for d in pre_docs if d.get('kind') == 'Deployment')
            post_dep = next(d for d in docs if d.get('kind') == 'Deployment')
            def pod_template(dep):
                return (dep.get('spec') or {}).get('template') or {}
            def norm_dep(dep):
                d = yaml.safe_load(yaml.safe_dump(dep))
                ann = (pod_template(d).get('metadata') or {}).get('annotations') or {}
                if 'checksum/config' in ann:
                    ann['checksum/config'] = '<checksum>'
                return d
            # The checksum/config annotation lives on the POD template metadata;
            # normalize it away, then the ONLY remaining difference may be the
            # initContainers list (diff_paths compares lists atomically).
            d = diff_paths(norm_dep(pre_dep), norm_dep(post_dep))
            allowed = {'spec.template.spec.initContainers'}
            if set(d) - allowed:
                bad(f't6 A9: the Deployment differs beyond the initContainers list at {sorted(set(d) - allowed)[:8]} (checksum normalized away)')
            if not (set(d) & allowed):
                bad('t6 A9: the Deployment initContainers did not change at all — the four shape legs + the two optional lines are missing (A9 item iii)')
            pre_inits = {c.get('name'): c for c in pod_template(pre_dep).get('spec', {}).get('initContainers', [])}
            post_inits = {c.get('name'): c for c in pod_template(post_dep).get('spec', {}).get('initContainers', [])}
            if set(pre_inits) != set(post_inits):
                bad(f't6 A9: init container sets differ: {sorted(set(pre_inits) ^ set(post_inits))}')
            for cname in sorted(set(pre_inits) & set(post_inits)):
                cd = diff_paths(pre_inits[cname], post_inits[cname])
                if cd and cname != 'init-app-ini':
                    bad(f't6 A9: init container {cname!r} differs at {cd[:6]} — only init-app-ini may change')
                if cd and cd != ['env']:
                    bad(f't6 A9: init-app-ini differs beyond its env list at {cd[:6]}')
            P = {e.get('name'): e for e in (pre_inits.get('init-app-ini') or {}).get('env') or []}
            Q = {e.get('name'): e for e in (post_inits.get('init-app-ini') or {}).get('env') or []}
            if set(P) - set(Q):
                bad(f't6 A9: env entries removed vs the pristine capture: {sorted(set(P) - set(Q))}')
            new = set(Q) - set(P)
            want_new = {'FORGEJO__LFS__MINIO_BUCKET', 'FORGEJO__LFS__MINIO_BUCKET_LOOKUP',
                        'FORGEJO__LFS__MINIO_CHECKSUM_ALGORITHM', 'FORGEJO__LFS__SERVE_DIRECT'}
            if new != want_new:
                bad(f't6 A9: env entries added are {sorted(new)}, expected exactly the four shape legs {sorted(want_new)} (A9 item iii)')
            for n in new:
                want = {'name': n, 'valueFrom': {'secretKeyRef': {'name': 'forgejo-lfs-shape', 'key': n.split('FORGEJO__LFS__')[1], 'optional': True}}}
                if Q[n] != want:
                    bad(f't6 A9: new leg {n} is {Q[n]!r}, expected {want!r}')
            changed = [n for n in set(P) & set(Q) if P[n] != Q[n]]
            if sorted(changed) != sorted(CRED):
                bad(f't6 A9: env entries changed are {sorted(changed)}, expected exactly the two cred legs {sorted(CRED)}')
            for n in changed:
                pk = dict(P[n]['valueFrom']['secretKeyRef'])
                qk = dict(Q[n]['valueFrom']['secretKeyRef'])
                gained = qk.get('optional')
                pk.pop('optional', None)
                qk.pop('optional', None)
                if pk != qk:
                    bad(f't6 A9: {n} changed more than the optional flag: {P[n]!r} -> {Q[n]!r}')
                if gained is not True:
                    bad(f't6 A9: {n} gained optional={gained!r}, expected true')
            if pod_template(pre_dep).get('spec', {}).get('containers') != pod_template(post_dep).get('spec', {}).get('containers'):
                bad('t6 A9: the main containers list changed vs the pristine capture')
            pre_ann = (pod_template(pre_dep).get('metadata') or {}).get('annotations', {}).get('checksum/config')
            post_ann = (pod_template(post_dep).get('metadata') or {}).get('annotations', {}).get('checksum/config')
            if pre_ann == post_ann:
                bad('t6 A9: the checksum/config annotation did not change (A9 item iv) — the inline-config change must roll a new checksum')
            ok('t6: the whole-render delta vs the pristine capture is exactly the A9 four-item list (shape Secret added; [lfs] loses the 4 shape lines; +4 env legs + 2 optional lines; checksum/config rolls)')

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

    # ---- t7: shape constants single-sourced (AC2) --------------------------
    # The four constants must live in values position in exactly ONE tracked
    # file — the gated template. A second copy (any custom-values, any
    # values.yaml) is a fork: the instances would drift silently.
    if python3 - "$SHAPE_TPL" "$infra_eff" "$dev_eff" "$WORK/t7-count" <<'PY'
import os, re, sys, yaml

shape_tpl, infra_render, dev_render, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def docs_of(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]

def inline_secs(path):
    for d in docs_of(path):
        if d.get('kind') == 'Secret' and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config'):
            return (d.get('stringData') or {})
    bad(f't7: no inline-config Secret in {path}')

def ini(section):
    return {kv.split('=', 1)[0]: kv.split('=', 1)[1]
            for kv in (section or '').splitlines() if kv.strip() and '=' in kv}

# A14 record (values as the subchart's printf %v emits them).
SHAPE = {
    'MINIO_BUCKET': 'git-lfs',
    'MINIO_BUCKET_LOOKUP': 'path',
    'MINIO_CHECKSUM_ALGORITHM': 'default',
    'SERVE_DIRECT': 'false',
}
# Scan the worktree (not git grep): the gated template is untracked until
# the coordinator commits it, and git grep would miss the very single source
# it is supposed to prove. Vendored subchart trees (charts/<name>/charts/,
# gitignored) are pruned so an in-place dependency build cannot add a second
# values land.
PY_RX = re.compile(r'^[ 	]*(MINIO_BUCKET|MINIO_BUCKET_LOOKUP|MINIO_CHECKSUM_ALGORITHM|SERVE_DIRECT)[ 	]*:')
try:
    hits = []
    for top in ('charts', 'services', 'custom-values'):
        for root, dirs, files in os.walk(top):
            # vendored subchart trees (charts/<name>/charts/, gitignored)
            # would be a second "values land" the single-source law does not
            # cover — skip them.
            dirs[:] = [d for d in dirs if not (d == 'charts' and root.count(os.sep) >= 1)]
            for name in files:
                if not name.endswith(('.yaml', '.yml', '.tpl')):
                    continue
                p = os.path.join(root, name)
                for i, line in enumerate(open(p, encoding='utf-8', errors='replace'), 1):
                    if PY_RX.match(line):
                        hits.append(f'{p}:{i}')
    files = {h.split(':', 1)[0] for h in hits}
    if len(hits) != 4 or files != {shape_tpl}:
        bad(f't7: the four shape constants appear in values position at {sorted(files)} ({len(hits)} lines) — expected exactly the four stringData lines of {shape_tpl} (the single source; any other occurrence is a per-instance fork)')
    ok(f't7: the four shape constants live in values position in exactly one shippable file - ' + chr(123) + 'shape_tpl' + chr(125) + ' (single source)')

    stray = []
    for root, _, names in os.walk('custom-values'):
        for n in names:
            if n.endswith(('.yaml', '.yml')):
                p = os.path.join(root, n)
                for i, line in enumerate(open(p), 1):
                    if re.search(r'MINIO_BUCKET|MINIO_BUCKET_LOOKUP|MINIO_CHECKSUM_ALGORITHM|SERVE_DIRECT', line):
                        stray.append(f'{p}:{i}')
    if stray:
        bad(f't7: custom-values/ carries shape-key literals: {stray} — the not-enabled stance and the activation slices may not repeat the constants (they would fork them)')
    ok('t7: custom-values/ carries zero shape-key literals (no per-instance fork)')

    infra_secs = inline_secs(infra_render)
    if 'lfs' not in infra_secs:
        bad('t7: the infra effective render has no [lfs] section (infra must keep S3)')
    infra_lfs = ini(infra_secs['lfs'])
    shape_docs = [d for d in docs_of(infra_render) if d.get('kind') == 'Secret'
                  and (d.get('metadata') or {}).get('name') == 'forgejo-lfs-shape']
    if len(shape_docs) != 1:
        bad(f't7: {len(shape_docs)} forgejo-lfs-shape Secrets in the infra render, expected exactly one')
    eff = dict(infra_lfs)
    eff.update((shape_docs[0].get('stringData') or {}))
    if set(eff) != {'STORAGE_TYPE', 'MINIO_ENDPOINT', 'MINIO_USE_SSL'} | set(SHAPE):
        bad(f't7: the infra effective [lfs] key set is {sorted(eff)}, expected the 7 keys of record (3 activation ∪ 4 shape)')
    for k, v in SHAPE.items():
        if eff.get(k) != v:
            bad(f't7: infra effective {k} resolves to {eff.get(k)!r}, expected the A14 constant {v!r}')
    dev_secs = inline_secs(dev_render)
    if 'lfs' in dev_secs:
        bad(f't7: the dev effective render carries an [lfs] section {dev_secs["lfs"]!r} — the not-enabled stance has no [lfs] at all')
    dev_shape = [d for d in docs_of(dev_render) if d.get('kind') == 'Secret'
                 and (d.get('metadata') or {}).get('name') == 'forgejo-lfs-shape']
    if dev_shape:
        bad(f't7: the dev effective render carries the forgejo-lfs-shape Secret ({len(dev_shape)}x) — the gate must be closed for dev')
    ok('t7: the infra effective 7-key set matches the constants of record, and the dev effective carries no [lfs] keys and no shape Secret')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't7: the single-source check could not be evaluated ({type(e).__name__}: {e})')
PY
    then
      checks=$((checks + $(cat "$WORK/t7-count")))
    else
      exit 1
    fi
  fi
fi

# --- t8: storage-aware UUID leg (AC4) --------------------------------------
# Static. The infra half is unchanged from cf-104: the credential leg is a
# secretKeyRef, so an unresolved id is a pod that cannot start. The dev half
# inverts with the gate: on the not-enabled stance the file keeps no forgejo-s3
# slot (the chart sentinel's only consumer is the gated ESO, which is closed
# for dev) and no S3 trace at all — a re-opt of dev into minio is a contract
# change and must rework this half in the same commit.
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

with open(infra_cv) as f:
    infra_raw = f.read()
infra = yaml.safe_load(infra_raw) or {}
ibw = ((infra.get('forgejo') or {}).get('bitwardenIds') or {})
if 'forgejo-s3' not in ibw:
    bad(f't8: {infra_cv} lost forgejo.bitwardenIds.forgejo-s3 — infra keeps S3, so the slot must stay')
val = ibw['forgejo-s3']
if not UUID_RE.match(str(val)):
    bad(f't8: {infra_cv} forgejo.bitwardenIds.forgejo-s3 is {val!r} — expected a real Bitwarden item UUID (OVERRIDE_NEEDED and any placeholder are banned for this slot)')
if 'OVERRIDE_' in json.dumps(infra.get('forgejo')):
    bad(f't8: an OVERRIDE_* sentinel survives in the forgejo: slice of {infra_cv} — the chart sentinel must be matched 1:1 by a real UUID here')
if 'OVERRIDE_NEEDED' in infra_raw:
    bad(f't8: {infra_cv} carries OVERRIDE_NEEDED at all — the forgejo slices may not use it, and nothing else in this file does')
ok(f't8: {infra_cv} carries a UUID-shaped forgejo.bitwardenIds.forgejo-s3 with no OVERRIDE_* in the forgejo slice')

with open(dev_cv) as f:
    dev_raw = f.read()
dev = yaml.safe_load(dev_raw) or {}
dbw = ((dev.get('forgejo') or {}).get('bitwardenIds') or {})
if 'forgejo-s3' in dbw:
    bad(f't8: {dev_cv} still carries forgejo.bitwardenIds.forgejo-s3 ({dbw["forgejo-s3"]!r}) — the not-enabled stance keeps no S3 slot; the chart sentinel is consumed only by the gated ESO, which is closed for dev (an orphaned UUID here would silently re-arm the gate on the next lfs declaration)')
for literal in ('forgejo-s3', 'MINIO', 'STORAGE_TYPE'):
    hits = [i + 1 for i, l in enumerate(dev_raw.splitlines()) if literal in l]
    if hits:
        bad(f't8: {dev_cv} carries the literal {literal!r} at line(s) {hits} — the not-enabled stance leaves no S3 trace in the file (the stance comment must avoid these words)')
if 'OVERRIDE_' in json.dumps(dev.get('forgejo')):
    bad(f't8: an OVERRIDE_* sentinel survives in the forgejo: slice of {dev_cv} — the remaining dev slots (forgejo/-admin/-pg/-sso) must keep real UUIDs')
ok(f't8: {dev_cv} carries no forgejo-s3 key and zero forgejo-s3/MINIO/STORAGE_TYPE literals (the not-enabled stance leaves no S3 trace)')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
then
  checks=$((checks + $(cat "$WORK/t8-count")))
else
  exit 1
fi

# --- t9: sentinel sweep at the pinned baselines (AC6) ----------------------
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

# --- t10: the service trio survives the LFS work (AC5) ---------------------
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

# --- t11: blast radius — the shared gateway and the untouched slices stay
# out (AC5) ------------------------------------------------------------------
# Enabling s3.enableAuth in charts/seaweedfs would auto-generate a fresh
# credential set and break every existing gateway consumer (Loki first), and
# a -s3.config flag is the same blast radius through the back door. Auth is
# already enforced by the filer-backed store, so this leg pins the file and
# forbids the back door. The new clause pins the rest of the blast radius:
# nothing under services/, charts/forgejo-runner/ or the infra/gpu
# custom-values may carry a single diff line against the fork base, except
# the two C02 flip files (services/{dev,infra}/prod/values.yaml) — the
# exclusion is path-based (git diff --name-only); their CONTENT is pinned by
# t12.
if [ -z "$DIFF_BASE" ]; then
  skip "t11: no fork-base ref to diff against; the blast-radius leg was not run (set LFS_DIFF_BASE)"
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

    # C02's in-scope set (the forgejo SSA flip, pinned by t12) legitimately
    # touches exactly the dev + infra service values; every other path in
    # this clause stays byte-pinned against the fork base.
    c02_in_scope = {'services/dev/prod/values.yaml', 'services/infra/prod/values.yaml'}
    moved = [m for m in git('diff', '--name-only', base, '--', 'services', 'charts/forgejo-runner', 'custom-values/infra', 'custom-values/gpu').split() if m not in c02_in_scope]
    if moved:
        bad(f't11: {moved} changed against the fork base {base} — out of scope for this ticket (C01: only the forgejo wrapper + the dev slice; C02: only the two forgejo values entries, pinned by t12)')
    ok('t11: services/ (minus the two C02 flip files), charts/forgejo-runner/ and custom-values/{infra,gpu}/ have zero diff lines against the fork base')

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

# --- t12: the C02 SSA posture — dev + infra forgejo apply server-side, the
# runner boundary stays client-side (cf-122 C02 AC1/AC5) --------------------
# Static: no helm. This suite is the LFS contract's home and t11's
# blast-radius leg is its sibling, so the SSA posture pins here. Mechanism,
# not incident narrative: on the first post-flip sync ArgoCD's CSA→SSA
# managedFields migration (the kubectl apply library under the explicit
# argocd-controller manager) unions the CSA-era Update entry — including the
# orphaned data.lfs key of the inline-config Secret — into the Apply entry,
# and the re-sent SSA patch prunes it; the client-side three-way apply that
# left the orphan can never remove it (k8s#99003, argo-cd#29109; cf-122
# RESEARCH incident section 2). The flip is a one-time orphan cleanup +
# future-prune-enablement for fields the app declares — NOT the durable
# class fix (upstream forgejo-helm data: rendering, STATE deferred).
# The runner entries deliberately stay client-side: a runner-app SSA flip
# would re-render the config surface that dev-forgejo-runner.sh t5's
# comment-window leg pins (the gpu values carry their own client-only
# exemption comment) — a separate ticket if ever wanted.
# The infra half complements infra-forgejo.sh t3, which pins the same flag
# in the rendered umbrella: static-vs-rendered together prove the flag
# reaches the generated Application through the umbrella.
if python3 - "$DEV_VALUES" "$INFRA_VALUES" "$GPU_VALUES" "$WORK/t12-count" <<'PY'
import re, sys, yaml

dev_values, infra_values, gpu_values, count_file = sys.argv[1:5]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load(path):
    # t10's anchor-rewrite convention: REDEFINED anchors are legal YAML
    # (helm/Go accept them; PyYAML raises ComposerError), so only the
    # value-position markers are rewritten; alias targets are never
    # asserted here, so the ANCHOR_REF placeholders are inert.
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}

def entry_of(path, key):
    entry = ((load(path).get('charts') or {}).get(key))
    if not isinstance(entry, dict):
        bad(f't12: {path} has no charts.{key} entry (the SSA posture pin needs the entry to exist)')
    return entry

try:
    got = entry_of(dev_values, 'forgejo').get('ServerSideApply')
    if got != 'true':
        bad(f't12: {dev_values} charts.forgejo.ServerSideApply is {got!r}, expected the quoted string "true" (cf-122 C02 flip: the app now applies server-side, so the first post-flip sync runs the CSA->SSA migration that prunes the orphaned data.lfs — k8s#99003, argo-cd#29109)')
    ok(f't12: {dev_values} charts.forgejo applies server-side (ServerSideApply "true" — cf-122 C02)')

    for path, key in ((dev_values, 'forgejo-runner-dev'), (gpu_values, 'forgejo-runner-gpu')):
        got = entry_of(path, key).get('ServerSideApply')
        if got != 'false':
            bad(f't12: {path} charts.{key}.ServerSideApply is {got!r}, expected "false" — the C02 boundary is forgejo only: a runner-app SSA flip would re-render the config surface that dev-forgejo-runner.sh t5 comment-window leg pins; a separate ticket if ever wanted')
    ok(f't12: the runner boundary stays client-side — {dev_values} charts.forgejo-runner-dev and {gpu_values} charts.forgejo-runner-gpu both carry ServerSideApply "false" (cf-122 C02 scope is forgejo only)')

    got = entry_of(infra_values, 'forgejo').get('ServerSideApply')
    if got != 'true':
        bad(f't12: {infra_values} charts.forgejo.ServerSideApply is {got!r}, expected the quoted string "true" (cf-122 C02 flip; infra rides the same CSA->SSA migration — complements infra-forgejo.sh t3, which pins the flag in the rendered umbrella)')
    ok(f't12: {infra_values} charts.forgejo applies server-side (ServerSideApply "true" — cf-122 C02, static half of the t3 static-vs-rendered pair)')

    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as e:
    bad(f't12: the SSA-posture check could not be evaluated ({type(e).__name__}: {e})')
PY
then
  checks=$((checks + $(cat "$WORK/t12-count")))
else
  exit 1
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so every "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: forgejo-lfs checks (%d ok)\n' "$checks"
