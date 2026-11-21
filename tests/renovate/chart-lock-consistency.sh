#!/usr/bin/env bash
# cf-135 C04 contract suite (2026/2026-11-cf-135-feat-renovate-forgejo,
# chunks/C04.md "## Tests"): the permanent Chart.yaml <-> Chart.lock
# consistency net. Renovate's helm artifact step failed through the Forgejo
# move ("No tool releases found.") and the rebuild-batch merges #19/#53/#63
# landed yaml-only, baking drift into main — only a real `helm dependency
# update` writes a valid lock, so drift must be REPAIRED by regeneration and
# never re-introduced by a yaml-only merge or a hand-edit (the U16 class).
# k2 reddens the next review touching such a tree.
#
# Hard scope rule: only charts/*/Chart.yaml and services/*/prod/Chart.yaml.
# .agents/** is deliberately OUT: the vendored helm-bjw-s-chart skill template
# carries dependencies with legitimately no lock (nothing is built from it and
# renovate.json's .agents/** rule suppresses PRs there), so pairing it would
# fail k1 forever; vendored trees under */charts/ sit below the two patterns'
# depth and stay out the same way.
#
# repository: strings are compared only trailing-slash-normalized and
# INFO-printed, never failed — helm's own emitted text is truth (RESEARCH
# §R3.0/3); the version pair is the invariant.
#
# AC trace: k1[AC1 inventory + both-way pairing invariant] k2[AC1 whole-tree
# version-pair scan] k3[AC2/AC3 the two repaired pairs pin equal].
#
# Red-first by design: k2/k3 FAIL on the drifted main state (3 rows across
# charts/base + services/home/prod) until C04's regeneration lands; green =
# zero mismatch rows.
#
# Purely static — no network, no helm binary: python3 parses the tree files
# per leg (house shape of the tests/renovate/ suites).
#
# Usage (from anywhere in the worktree):
#   bash tests/renovate/chart-lock-consistency.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- k1 [AC1]: inventory + lock<->deps pairing invariant ------------------------
if ! python3 - <<'PY'
import glob, os, sys, yaml

charts = sorted(glob.glob('charts/*/Chart.yaml') + glob.glob('services/*/prod/Chart.yaml'))


def need(cond, msg):
    if not cond:
        print(f'FAIL: k1: {msg}', file=sys.stderr)
        sys.exit(1)


deps, locks, nodeps = [], [], []
for y in charts:
    d = yaml.safe_load(open(y)) or {}
    (deps if d.get('dependencies') else nodeps).append(y)
    lk = os.path.join(os.path.dirname(y), 'Chart.lock')
    if os.path.exists(lk):
        locks.append(lk)

# The census is printed, never pinned: exact counts rot the way
# kubernetes-mcp-version-floor.sh k2 did — the invariant is the pairing.
print(f'census: {len(charts)} in-scope Chart.yaml ({len(deps)} with dependencies, '
      f'{len(nodeps)} dependency-less skipped), {len(locks)} Chart.lock')
need(charts, 'no Chart.yaml found in scope — the scan patterns no longer match the tree')
missing = [y for y in deps if not os.path.exists(os.path.join(os.path.dirname(y), 'Chart.lock'))]
need(not missing, f'dependency-bearing charts with no Chart.lock sibling: {missing}')
orphan = [lk for lk in locks
          if not (yaml.safe_load(open(os.path.join(os.path.dirname(lk), 'Chart.yaml'))) or {}).get('dependencies')]
need(not orphan, f'Chart.lock files whose Chart.yaml declares no dependencies: {orphan}')
PY
then
  fail "k1: see the k1 detail above"
fi
ok "k1: every deps chart has a lock sibling and every lock has a deps chart (census above)"

# --- k2 [AC1]: whole-tree dependency version-pair scan ---------------------------
if ! python3 - <<'PY'
import glob, os, sys, yaml

charts = sorted(glob.glob('charts/*/Chart.yaml') + glob.glob('services/*/prod/Chart.yaml'))
rows = []

for y in charts:
    ydeps = (yaml.safe_load(open(y)) or {}).get('dependencies') or []
    if not ydeps:
        continue
    lpath = os.path.join(os.path.dirname(y), 'Chart.lock')
    lock_deps = (yaml.safe_load(open(lpath)) or {}).get('dependencies') or []
    # Pool by lock-entry name with ORDER-PRESERVING consumption: helm does not
    # write alias into Chart.lock, so same-named duplicates (home/prod's 7x
    # app-template, 2x wekan) pair positionally, not by a dict that would
    # collapse them.
    pool = {}
    for e in lock_deps:
        pool.setdefault(e.get('name'), []).append(e)
    for dep in ydeps:
        name = dep.get('name')
        alias = dep.get('alias')
        cand = pool.get(name) or (pool.get(alias) if alias else None)
        tag = f'{name}/{alias}' if alias and alias != name else name
        if not cand:
            rows.append(f'{y} | {tag} | yaml {dep.get("version")} vs lock (absent)')
            continue
        e = cand.pop(0)
        if e.get('version') != dep.get('version'):
            rows.append(f'{y} | {tag} | yaml {dep.get("version")} vs lock {e.get("version")}')
        ry = str(dep.get('repository') or '').rstrip('/')
        rl = str(e.get('repository') or '').rstrip('/')
        if ry != rl:
            print(f'info: {y} | {tag} | repository yaml {ry!r} vs lock {rl!r} (INFO: helm text is truth)')
    for leftover, es in pool.items():
        for e in es:
            rows.append(f'{y} | {leftover} | yaml (absent) vs lock {e.get("version")}')

if rows:
    for r in rows:
        print(f'FAIL: k2: drift row: {r}', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "k2: Chart.yaml/Chart.lock drift rows above — repair by helm regeneration, never by hand-editing either side"
fi
ok "k2: whole-tree scan — every yaml dependency version equals its paired lock entry (zero drift rows)"

# --- k3 [AC2/AC3]: this ticket's two repaired pairs pin equal --------------------
# Pair-equality, no version literals: at C04's landing the pairs read 10.18.2
# (argo-cd) and 12.99.0 x2 (wekan), but the LAW is yaml == lock — a future
# paired bump PR must stay green (C04: "the pair law is the point").
if ! python3 - <<'PY'
import sys, yaml


def need(cond, msg):
    if not cond:
        print(f'FAIL: k3: {msg}', file=sys.stderr)
        sys.exit(1)


def versions(chart, dep_name):
    ypath, lpath = f'{chart}/Chart.yaml', f'{chart}/Chart.lock'
    yv = [d.get('version') for d in (yaml.safe_load(open(ypath)) or {}).get('dependencies') or []
          if d.get('name') == dep_name]
    lv = [d.get('version') for d in (yaml.safe_load(open(lpath)) or {}).get('dependencies') or []
          if d.get('name') == dep_name or d.get('alias') == dep_name]
    return yv, lv


yv, lv = versions('charts/base', 'argo-cd')
need(len(yv) == 1 and len(lv) == 1,
     f'charts/base argo-cd: expected one yaml + one lock entry, got yaml {yv} lock {lv}')
need(yv == lv, f'charts/base argo-cd pair unequal: yaml {yv[0]} vs lock {lv[0]}')
yv, lv = versions('services/home/prod', 'wekan')
need(len(yv) == 2 and len(lv) == 2,
     f'services/home/prod wekan: expected the plain + alias boards pair on both sides, got yaml {yv} lock {lv}')
need(yv == lv, f'services/home/prod wekan pairs unequal: yaml {yv} vs lock {lv}')
PY
then
  fail "k3: see the k3 detail above"
fi
ok "k3: base/argo-cd and home/prod/wekan x2 pin yaml==lock (the two repaired pairs)"

printf 'PASS: chart-lock-consistency checks (%d ok)\n' "$checks"
