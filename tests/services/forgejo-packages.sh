#!/usr/bin/env bash
# Offline contract suite for the repo-side enablement of the prod instance's
# package registries (cf-55 C04, rebuilt): the `[packages]` declaration in
# custom-values/infra/prod-values.yaml is what serves BOTH registries the CI
# pushes to — the Helm registry (build-charts.yaml's forgejo-publish leg) and the
# OCI registry (cf-6's containers-build.yaml instance push) — the single
# section gating both. Invariants pinned here — the declaration rides the
# INFRA slice only (dev stays un-enabled, D20; its registries would silently
# share the prod publish targets), the value is the STRING "true" in the
# neighboring typed style, the key set is EXACTLY {ENABLED} (D24: v15.0 has
# no generic LIMIT_SIZE — declaring one renders into app.ini and the binary
# silently ignores it — and the per-type caps deliberately stay at their
# unlimited defaults), the wrapper chart stays un-edited (the gate is
# per-instance and the static additionalConfigFromEnvs list must never be
# forked by a slice, chart law), a render proof that the declaration actually
# reaches the inline-config Secret the instance consumes, and the reconciled
# why-comment carrying the provenance (cf-6 proved the registry live;
# [storage] stays deliberately unconfigured). ENABLED already defaults true
# upstream — the declaration is the deliberate explicit-on pin, and this suite
# is what keeps it pinned (V-3 [16]/[47]).
#
# t1-t5 are purely static (bash reads files, python3 parses). t6 renders the
# chart on a /tmp/opencode copy; the harness and its registry-unreachable=>SKIP
# rule follow tests/services/gpu-forgejo-runner.sh:84-149 — instance state is
# not workspace-verifiable and a merge-blocked network must SKIP, not FAIL.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-packages.sh
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # FRICTION seed: helm lives at ~/.local/bin

cd "$(git rev-parse --show-toplevel)"

INFRA_CV="custom-values/infra/prod-values.yaml"
DEV_CV="custom-values/dev/prod-values.yaml"
CHART="charts/forgejo"

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

# --- t1: file shape — the packages path is a mapping (AC1) --------------------
[ -f "$INFRA_CV" ] || fail "t1: $INFRA_CV does not exist"
if ! python3 - "$INFRA_CV" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}
path = ['forgejo', 'forgejo', 'gitea', 'config', 'packages']
node = doc
walked = []
for k in path:
    walked.append(k)
    if not isinstance(node, dict) or k not in node:
        print(f'FAIL: t1: {".".join(walked)} is missing — C04 adds the packages block under forgejo.forgejo.gitea.config (the LFS declaration-is-the-gate pattern)', file=sys.stderr)
        sys.exit(1)
    node = node[k]
if not isinstance(node, dict):
    print(f'FAIL: t1: forgejo.forgejo.gitea.config.packages is {node!r}, expected a mapping', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t1: see the t1 detail above"
fi
ok "t1: $INFRA_CV parses and forgejo.forgejo.gitea.config.packages is a mapping"

# --- t2: ENABLED is the string "true" (AC1) -------------------------------------
if ! python3 - "$INFRA_CV" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}
pkg = ((doc.get('forgejo') or {}).get('forgejo') or {}).get('gitea', {}).get('config', {}).get('packages') or {}
val = pkg.get('ENABLED')
if not (isinstance(val, str) and val == 'true'):
    print(f'FAIL: t2: packages.ENABLED is {val!r} (type {type(val).__name__}), expected the STRING "true" — bare-bool true is drift from the typed style of the neighboring server/lfs/mailer blocks', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t2: see the t2 detail above"
fi
ok "t2: packages.ENABLED is exactly the string \"true\" (typed-style parity with the sibling config blocks)"

# --- t3: the key set is EXACTLY {ENABLED} (AC1, D24) ------------------------------
if ! python3 - "$INFRA_CV" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}
pkg = ((doc.get('forgejo') or {}).get('forgejo') or {}).get('gitea', {}).get('config', {}).get('packages') or {}
keys = set(pkg)
if keys != {'ENABLED'}:
    print(f'FAIL: t3: the packages map keys are {sorted(keys)}, expected EXACTLY [ENABLED] — D24: no size caps declared (per-type LIMIT_SIZE_HELM/LIMIT_SIZE_CONTAINER default to unlimited; declaring caps is scope creep) and a generic LIMIT_SIZE is not a v15.0 key at all (it would render and be silently ignored)', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: the packages map key set is exactly {ENABLED} — no LIMIT_SIZE, no invented keys (D24)"

# --- t4: prod-only — the dev slice carries no packages key (AC2, D20) ---------------
if ! python3 - "$DEV_CV" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}


def found(node, key):
    if isinstance(node, dict):
        return key in node or any(found(v, key) for v in node.values())
    if isinstance(node, list):
        return any(found(v, key) for v in node)
    return False


block = doc.get('forgejo')
if isinstance(block, dict) and found(block, 'packages'):
    print('FAIL: t4: the dev custom-values forgejo block carries a packages key — enablement is prod-only (D20); a dev registry would double-publish from the synced repo', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t4: see the t4 detail above"
fi
ok "t4: custom-values/dev has no packages key under its forgejo block (prod-only)"

# --- t5: chart untouched — the gate rides the slice only (AC2) -------------------------
if ! python3 - "$CHART" <<'PY'
import sys, yaml


def found(node, key):
    if isinstance(node, dict):
        return key in node or any(found(v, key) for v in node.values())
    if isinstance(node, list):
        return any(found(v, key) for v in node)
    return False


values = yaml.safe_load(open(f'{sys.argv[1]}/values.yaml')) or {}
if found(values, 'packages'):
    print('FAIL: t5: charts/forgejo/values.yaml carries a packages key — the per-instance gate rides the custom-values slice; a chart-wide default would enable dev too (D19/D20)', file=sys.stderr)
    sys.exit(1)
raw = open(f'{sys.argv[1]}/values.yaml').read()
if 'FORGEJO__PACKAGES__' in raw:
    print('FAIL: t5: a FORGEJO__PACKAGES__ env leg was added to the static additionalConfigFromEnvs list — chart law forbids slices overriding that list, and the gate belongs in gitea.config (D19)', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: charts/forgejo/values.yaml gained neither a packages key nor a FORGEJO__PACKAGES__ env leg"

# --- helm discovery (gpu-forgejo-runner.sh convention) -------------------------
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

# --- t6: render proof — the declaration reaches the inline-config Secret (AC3) ----
# A synthesized values file carrying the SAME gitea.config.packages block is
# rendered against the real chart; the ini spelling is asserted against how
# sibling sections render in this same harness (the forgejo-lfs.sh inline
# comparison), not against invented syntax.
helm_bin=$(find_helm || true)
if [ -z "$helm_bin" ]; then
  skip "t6: no helm binary on PATH or in /tmp/opencode; the render proof was not run"
else
  WORK=$(mktemp -d /tmp/opencode/forgejo-packages.XXXXXX)
  copy="$WORK/forgejo"
  cp -R "$CHART"/. "$copy"/
  build_log="$copy/dependency-build.log"
  if ! (cd "$copy" && "$helm_bin" dependency build .) >"$build_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$build_log"; then
      skip "t6: helm dependency build could not reach the OCI registry for $CHART here; the render proof was not run (the [packages] -> inline-config path itself was verified upstream by RESEARCH V-3 [47]; log kept at $build_log)"
    else
      tail -n 30 "$build_log" >&2
      fail "t6: helm dependency build failed for $CHART (log kept at $build_log)"
    fi
  else
    # The slice structure C04 writes, in the standalone-chart values shape
    # (the umbrella feeds the app block's contents as release values).
    cat >"$WORK/packages-values.yaml" <<'YAML'
forgejo:
  gitea:
    config:
      packages:
        ENABLED: "true"
YAML
    render="$WORK/render.yaml"
    render_err="$WORK/render.err"
    if ! "$helm_bin" template infra "$copy" -f "$WORK/packages-values.yaml" \
      --set domain=scifi.farm --set clusterName=infra \
      --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
      --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
      --set bitwardenIds.forgejo-s3=u5 \
      >"$render" 2>"$render_err"; then
      tail -n 30 "$render_err" >&2
      fail "t6: helm template of $CHART with the packages values failed (log kept at $render_err)"
    fi
    if python3 - "$render" "$WORK/t6-count" <<'PY'
import sys, yaml

render, count_file = sys.argv[1:3]
ok_n = 0


def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')


def bad(msg):
    print(f'FAIL: t6: {msg}', file=sys.stderr)
    sys.exit(1)


def ini(section):
    # Same KEY=VALUE tolerance the sibling inline assertions use (forgejo-lfs
    # t3): the subchart emits ini body lines; the spacing is the subchart's,
    # not an invented spelling.
    out = {}
    for line in (section or '').splitlines():
        if not line.strip():
            continue
        if '=' not in line:
            bad(f'the inline-config section has a non KEY=VALUE line {line!r}')
        k, v = line.split('=', 1)
        out[k.strip()] = v.strip()
    return out


docs = [d for d in yaml.safe_load_all(open(render)) if d]
inlines = [d for d in docs if d.get('kind') == 'Secret'
           and ((d.get('metadata') or {}).get('name') or '').endswith('-forgejo-inline-config')]
if len(inlines) != 1:
    bad(f'{len(inlines)} inline-config Secrets in the render, expected exactly one')
secs = inlines[0].get('stringData') or {}
if 'server' not in secs:
    bad('the render has no [server] section to compare the inline spelling against — the harness is not reading the config Secret the instance consumes')
if 'packages' not in secs:
    bad(f'the inline-config Secret has no [packages] section (sections present: {sorted(secs)}) — the gitea.config.packages declaration does not reach app.ini')
pkg = ini(secs['packages'])
if pkg.get('ENABLED') != 'true':
    bad(f'the rendered [packages] ENABLED is {pkg.get("ENABLED")!r}, expected true (the string "true" renders as the ini scalar)')
ok('t6: the [packages] section lands in the inline-config Secret with ENABLED = true (same harness, same spelling as the sibling sections)')
caps = [k for k in pkg if 'LIMIT_SIZE' in k or k == 'SIZE']
if caps:
    bad(f'the rendered [packages] carries size caps {caps} — D24 keeps them at the unlimited defaults; only ENABLED may be declared')
ok('t6: the rendered [packages] section carries ENABLED and no size-cap lines')

with open(count_file, 'w') as f:
    f.write(str(ok_n))
PY
    then
      checks=$((checks + $(cat "$WORK/t6-count")))
      rm -rf "$WORK"
    else
      exit 1
    fi
  fi
fi

# --- t7: the reconciled why-comment carries the provenance (C04 comment law) -----
# The C04 task demanded a comment naming the dual-registry target and the
# deliberate non-touches. Post-reconcile it also carries the cf-6 facts — the
# sibling OCI consumer and the proven-live flag — and THOSE are what a
# future editor could silently drop while the YAML itself stays green.
if ! python3 - "$INFRA_CV" <<'PY'
import sys

raw = open(sys.argv[1]).read()
i = raw.find('        packages:')
if i < 0:
    print('FAIL: t7: no packages: block to anchor the comment on (t1 owns that red; this leg presumes it landed)', file=sys.stderr)
    sys.exit(1)
comment = raw[max(0, i - 1600):i]
for tok, why in (
        ('build-containers.yaml', 'the OCI sibling consumer — the section gates BOTH registries (C15 pin 6: the tuple and the comment above packages: flip together)'),
        ('cf-6', 'the provenance that the registry is already exercised live (the declaration is an explicit-on pin, not a flip)'),
        ('[storage] stays deliberately unconfigured', 'the chart-law non-touch that keeps attachments/avatars off the S3 drag'),
        ('D24', 'the key-set law: {ENABLED} only, per-type caps unlimited by default'),
        ('D20', 'the prod-only ruling this comment documents for the dev-slice absence')):
    if tok not in comment:
        print(f'FAIL: t7: the comment above packages: lost {tok!r} — {why}', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t7: see the t7 detail above"
fi
ok "t7: the packages: comment carries the reconciled provenance (containers-build.yaml sibling, cf-6 proven-live, [storage] non-touch, D24/D20 laws)"

printf 'PASS: forgejo-packages checks (%d ok)\n' "$checks"
