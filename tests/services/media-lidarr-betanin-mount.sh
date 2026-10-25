#!/usr/bin/env bash
# C02 acceptance checks (2026-10-debug-lidarr-music-stack): the lidarr pod's
# deterministic StartError is fixed by GitOps content only — the betanin
# Secret is mounted into the lidarr container as a whole-directory volume at
# /betanin-secrets (no file subPath, which is what failed against the live
# /config PVC), the betanin.sh custom script reads the key at
# /betanin-secrets/BETANIN_API_KEY, and the umbrella chart still lints/renders
# clean with the pinned LSIO nightly image untouched.
#
# Legs map to the numbered acceptance criteria in chunks/C02.md:
#   c2s / c2r -> 1+2 (values shape static, rendered Deployment real)
#   c3s / c3r -> 3   (ConfigMap script path, source and render)
#   c1        -> 1   (helm lint exit 0)
#   c4        -> 2+4 (full render: no old path anywhere, no OVERRIDE_ leak)
#   c5        -> 5   (exactly one content commit ahead of main, two files)
#
# The render legs lint/template a fresh copy of services/media/prod in
# /tmp/opencode rather than the worktree path itself: building the umbrella's
# dependencies (Chart.lock present, charts/ tarballs gitignored and possibly
# absent) rewrites Chart.lock whenever resolution drifts, and a mutated
# tracked file would break C01's clean-index assertion and c5's commit-scope
# assertion mid-review. The copy is taken at run start, so every rendered byte
# comes from the worktree files under review (repo convention: the worktree
# is never written, same as gpu-coder-sso.sh / infra-forgejo.sh).
#
# Scope is PRE-MERGE only: post-merge cluster verification (argocd app media
# Healthy, pod 1/1) is the readonly-MCP + USER steps in the plan file, not
# part of this suite.
#
# A missing/unreachable helm degrades to skip for the render legs (the static
# c2s/c3s and git c5 legs still run and still gate), matching the
# registry-skip discipline of gpu-coder-sso.sh.
#
# Run from anywhere in the worktree:
#   bash tests/services/media-lidarr-betanin-mount.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

UMB_VALUES="services/media/prod/values.yaml"
UMB_SCRIPT_TEMPLATE="services/media/prod/templates/configmap-lidarr-betanin-script.yaml"
BETANIN_MOUNT="/betanin-secrets"
OLD_PATH="/config/secrets/betanin"
LIDARR_IMAGE="lscr.io/linuxserver/lidarr:nightly-version-3.1.6.5078"
RENDER_SETS=(--set domain=spencerslab.com --set clusterName=media --set bitwardenIds.argocd-mcp=test-uuid)

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

find_helm() {
  local cand
  if [ -n "${HELM_BIN:-}" ] && [ -x "$HELM_BIN" ]; then
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

# Pinned + sha256-checked per the repo's container-pinning rule; keep the
# version aligned with the other suites' helm pin.
download_helm() {
  local version=3.21.4 arch dir tar
  command -v curl >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  dir=/tmp/opencode/media-lidarr-betanin-mount-helm-download
  mkdir -p "$dir"
  tar="$dir/helm-v${version}-linux-${arch}.tar.gz"
  curl -fsSL --max-time 120 -o "$tar" \
    "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz" >/dev/null 2>&1 || return 1
  curl -fsSL --max-time 30 -o "${tar}.sha256sum" \
    "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz.sha256sum" >/dev/null 2>&1 || return 1
  (cd "$dir" && sha256sum -c "$(basename "$tar").sha256sum" >/dev/null 2>&1) || return 1
  tar -xzf "$tar" -C "$dir" || return 1
  find "$dir" -type f -name helm -perm -u+x | head -n 1
}

# --- c2s: the committed values shape (runs without helm) -------------------
# The StartError contract lives in the values file, so it is asserted twice:
# statically here (always runs) and against the real render below (c2r).
if ! python3 - "$UMB_VALUES" "$BETANIN_MOUNT" "$OLD_PATH" <<'PY'
import sys, yaml

path, mount, old = sys.argv[1:4]
lidarr = yaml.safe_load(open(path))['lidarr']
mounts = lidarr['volumeMounts']
vols = lidarr['volumes']

secret = [m for m in mounts if m.get('name') == 'betanin-secret']
if len(secret) != 1:
    print(f'FAIL: c2s: expected exactly one betanin-secret volumeMount, found {len(secret)}', file=sys.stderr)
    sys.exit(1)
m = secret[0]
if m.get('mountPath') != mount:
    print(f"FAIL: c2s: betanin-secret mounts at {m.get('mountPath')!r}, expected {mount!r} — the file subPath into /config is the StartError mechanism the fix removes", file=sys.stderr)
    sys.exit(1)
if 'subPath' in m or 'subPathExpr' in m:
    print(f'FAIL: c2s: betanin-secret mount still carries a subPath ({m}) — a whole-directory mount must not name a key', file=sys.stderr)
    sys.exit(1)
if any(str(x.get('mountPath', '')).startswith(old) for x in mounts):
    print(f'FAIL: c2s: a lidarr volumeMount still targets {old}...', file=sys.stderr)
    sys.exit(1)

svol = [v for v in vols if v.get('name') == 'betanin-secret']
if len(svol) != 1:
    print(f'FAIL: c2s: expected exactly one betanin-secret volume, found {len(svol)}', file=sys.stderr)
    sys.exit(1)
sec = svol[0].get('secret') or {}
if sec.get('secretName') != 'betanin' or sec.get('optional') is not True:
    print(f'FAIL: c2s: the betanin-secret volume changed shape ({sec}) — the fix keeps secretName betanin + optional: true, only the mount mechanism moves', file=sys.stderr)
    sys.exit(1)

script = [x for x in mounts if x.get('name') == 'betanin-script']
if len(script) != 1 or script[0].get('mountPath') != '/config/scripts/betanin.sh' or script[0].get('subPath') != 'betanin.sh':
    print(f'FAIL: c2s: the betanin-script configMap mount is not the unchanged /config/scripts/betanin.sh subPath entry ({script})', file=sys.stderr)
    sys.exit(1)
cfg = [v for v in vols if v.get('name') == 'betanin-script']
if len(cfg) != 1 or (cfg[0].get('configMap') or {}).get('name') != 'lidarr-betanin-script':
    print(f'FAIL: c2s: the betanin-script volume no longer references configMap lidarr-betanin-script ({cfg})', file=sys.stderr)
    sys.exit(1)
PY
then
  exit 1
fi
ok "c2s: values.yaml mounts betanin-secret as a directory at $BETANIN_MOUNT without subPath; volume keeps secretName betanin + optional: true; script mount untouched (criteria 2)"

# --- c3s: the script template reads the key by Secret key name ---------------
[ -f "$UMB_SCRIPT_TEMPLATE" ] || fail "c3s: $UMB_SCRIPT_TEMPLATE is missing (the betanin custom script ConfigMap is part of the fix scope)"
grep -qF "API_KEY=\"\$(cat ${BETANIN_MOUNT}/BETANIN_API_KEY)\"" "$UMB_SCRIPT_TEMPLATE" ||
  fail "c3s: the script no longer reads API_KEY via cat $BETANIN_MOUNT/BETANIN_API_KEY — the directory mount exposes the key under its Secret key name (criterion 3)"
if grep -qF "$OLD_PATH" "$UMB_SCRIPT_TEMPLATE"; then
  fail "c3s: $UMB_SCRIPT_TEMPLATE still references $OLD_PATH (the header comment's path reference is part of the prescribed edit — a stale path here would send readers back to the broken mount)"
fi
ok "c3s: script template reads $BETANIN_MOUNT/BETANIN_API_KEY and names no old path (criterion 3)"

# --- render legs (helm required) --------------------------------------------
helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || helm_bin=$(download_helm || true)

if [ -z "$helm_bin" ]; then
  skip "c1/c2r/c3r/c4: no helm binary found and none could be downloaded — run the plan's lint/template commands manually before the chunk verdict"
else
  WORK=$(mktemp -d /tmp/opencode/media-lidarr-betanin-mount.XXXXXX)
  trap 'rm -rf "$WORK"' EXIT
  UMB="$WORK/prod"
  cp -r services/media/prod "$UMB"

  dep_err="$WORK/dep.err"
  if ! "$helm_bin" dependency update "$UMB" >"$dep_err" 2>&1; then
    # The bjw-s + bubylou repos must be reachable for any render; house
    # skip-discipline: a network failure here skips (not fails) the render legs.
    skip "c1/c2r/c3r/c4: helm dependency update of the umbrella copy failed (subchart repos unreachable?) — log kept at $dep_err, render legs not run"
  else
    # --- c1: lint ------------------------------------------------------------
    if ! "$helm_bin" lint "$UMB" >"$WORK/lint.out" 2>&1; then
      tail -n 30 "$WORK/lint.out" >&2
      fail "c1: helm lint of $UMB_VALUES's chart failed (criterion 1)"
    fi
    ok "c1: helm lint services/media/prod passes (criterion 1)"

    # --- c2r: the rendered lidarr Deployment ---------------------------------
    "$helm_bin" template media "$UMB" -f "$UMB/values.yaml" "${RENDER_SETS[@]}" \
      --show-only charts/lidarr/templates/deployment.yaml >"$WORK/deployment.yaml" 2>"$WORK/deployment.err" || {
      tail -n 30 "$WORK/deployment.err" >&2
      fail "c2r: rendering the lidarr subchart deployment failed (plan command from the plan file's Commands section)"
    }
    if grep -qF "$OLD_PATH" "$WORK/deployment.yaml"; then
      fail "c2r: the rendered lidarr Deployment still contains $OLD_PATH — the StartError mount mechanism survived the fix (criterion 2)"
    fi
    if python3 - "$WORK/deployment.yaml" "$BETANIN_MOUNT" "$LIDARR_IMAGE" <<'PY'
import sys, yaml

path, mount, image = sys.argv[1:4]
docs = [d for d in yaml.safe_load_all(open(path)) if d]
deps = [d for d in docs if d.get('kind') == 'Deployment' and d['metadata']['name'] == 'media-lidarr']
if not deps:
    print('FAIL: c2r: the render has no Deployment named media-lidarr', file=sys.stderr)
    sys.exit(1)
pod = deps[0]['spec']['template']['spec']

containers = pod['containers']
target = [c for c in containers if any(m.get('name') == 'betanin-secret' for m in c.get('volumeMounts', []))]
if len(target) != 1:
    print(f'FAIL: c2r: expected exactly one container with a betanin-secret volumeMount, found {len(target)}', file=sys.stderr)
    sys.exit(1)
c = target[0]
vm = [m for m in c['volumeMounts'] if m.get('name') == 'betanin-secret'][0]
if vm.get('mountPath') != mount or 'subPath' in vm or 'subPathExpr' in vm:
    print(f'FAIL: c2r: the rendered betanin-secret volumeMount is {vm}, expected mountPath {mount} with no subPath (criterion 2)', file=sys.stderr)
    sys.exit(1)
vol = [v for v in pod['volumes'] if v.get('name') == 'betanin-secret']
if len(vol) != 1 or (vol[0].get('secret') or {}).get('secretName') != 'betanin' or (vol[0].get('secret') or {}).get('optional') is not True:
    print(f'FAIL: c2r: the rendered betanin-secret volume pair changed (secretName betanin + optional true required): {vol}', file=sys.stderr)
    sys.exit(1)
if c['image'] != image:
    print(f"FAIL: c2r: container image is {c['image']!r}, expected the untouched pin {image!r} (chart edits must not move image tags — CI/Renovate own them)", file=sys.stderr)
    sys.exit(1)
script_vm = [m for m in c['volumeMounts'] if m.get('name') == 'betanin-script']
if len(script_vm) != 1 or script_vm[0].get('mountPath') != '/config/scripts/betanin.sh' or script_vm[0].get('subPath') != 'betanin.sh':
    print(f'FAIL: c2r: the /config/scripts/betanin.sh configMap mount is not unchanged: {script_vm}', file=sys.stderr)
    sys.exit(1)
config_vm = [m for m in c['volumeMounts'] if m.get('name') == 'lidarr-config']
if len(config_vm) != 1 or config_vm[0].get('mountPath') != '/config':
    print(f'FAIL: c2r: the lidarr-config /config mount is not untouched: {config_vm}', file=sys.stderr)
    sys.exit(1)
PY
    then
      ok "c2r: rendered lidarr Deployment: betanin-secret directory-mounts at $BETANIN_MOUNT with no subPath, volume pair intact, script + /config mounts and nightly image unchanged (criterion 2)"
    else
      exit 1
    fi

    # --- c3r: the rendered ConfigMap ------------------------------------------
    "$helm_bin" template media "$UMB" -f "$UMB/values.yaml" "${RENDER_SETS[@]}" \
      --show-only templates/configmap-lidarr-betanin-script.yaml >"$WORK/configmap.yaml" 2>"$WORK/configmap.err" || {
      tail -n 30 "$WORK/configmap.err" >&2
      fail "c3r: rendering the lidarr-betanin-script ConfigMap failed (plan command from the plan file's Commands section)"
    }
    grep -qF "${BETANIN_MOUNT}/BETANIN_API_KEY" "$WORK/configmap.yaml" ||
      fail "c3r: the rendered ConfigMap script does not read ${BETANIN_MOUNT}/BETANIN_API_KEY (criterion 3)"
    ok "c3r: rendered ConfigMap lidarr-betanin-script reads $BETANIN_MOUNT/BETANIN_API_KEY (criterion 3)"

    # --- c4: full render sentinel + old-path sweep ------------------------------
    "$helm_bin" template media "$UMB" -f "$UMB/values.yaml" "${RENDER_SETS[@]}" \
      >"$WORK/full.yaml" 2>"$WORK/full.err" || {
      tail -n 30 "$WORK/full.err" >&2
      fail "c4: the full umbrella render failed (plan command from the plan file's Commands section)"
    }
    sentinels=$(grep -c 'OVERRIDE_' "$WORK/full.yaml" || true)
    [ "$sentinels" -eq 0 ] ||
      fail "c4: the full render leaks $sentinels OVERRIDE_ hit(s) — a bitwardenIds sentinel reaching the cluster means the deploy path lost its custom-values override (criterion 4)"
    old_hits=$(grep -cF "$OLD_PATH" "$WORK/full.yaml" || true)
    [ "$old_hits" -eq 0 ] ||
      fail "c4: $OLD_PATH still appears $old_hits time(s) in the full render — criterion 2's 'nowhere' spans every document, Deployment and ConfigMap alike"
    ok "c4: full render contains no OVERRIDE_ sentinel and no $OLD_PATH string (criteria 2+4)"
  fi
fi

# --- c5: commit scope --------------------------------------------------------
# The branch had already fallen behind main (366fddd60) when C02 starts, so
# "one commit ahead of main" only lands after dev merges main in per AGENTS.md;
# the merge is plumbing, hence --no-merges on the count.
ahead=$(git rev-list --count --no-merges main..HEAD)
[ "$ahead" -eq 1 ] ||
  fail "c5: $ahead non-merge commit(s) ahead of main — the chunk prescribes exactly one fix commit, and the branch must first merge main to be ahead of it at all (criterion 5)"
changed=$(git diff --name-only main..HEAD | sort | paste -sd' ' -)
expected=$(printf '%s\n' "$UMB_VALUES" "$UMB_SCRIPT_TEMPLATE" | sort | paste -sd' ' -)
[ "$changed" = "$expected" ] ||
  fail "c5: main..HEAD diff touches [$changed], expected exactly [$expected] — no version bumps, no Chart.lock churn, no other chart in this commit (criterion 5)"
ok "c5: exactly one content commit ahead of main, touching only the two in-scope files (criterion 5)"

printf 'PASS: media-lidarr-betanin-mount checks (%d ok)\n' "$checks"
