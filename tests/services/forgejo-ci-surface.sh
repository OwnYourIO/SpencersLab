#!/usr/bin/env bash
# Whole-state surface guard for the REBUILT cf-55 (chart-half move, reconciled
# to cf-6's conventions per DECISIONS D31/D32): the fence's OTHER side.
# forgejo-release.sh proves the moved builder's internals from the .forgejo
# side; this suite pins the inventory from both sides and sweeps every live
# surface for stale claims the rebuild must have erased:
#   - .forgejo/workflows/ holds EXACTLY the five-workflow family (cf-6's
#     main-sync/renovate/containers-build + this ticket's release.yaml + the
#     cf-6 builder-bootstrap dispatch recovery lane);
#   - .github/workflows/ keeps the seven gate workflows AND docker-build.yaml
#     — the workflow_dispatch-only manual-fallback builder cf-6 deliberately
#     kept — and NOT release.yaml (the chart half moved, the container half
#     did not);
#   - no live surface cites the deleted GitHub release path;
#   - on the carriers the reconcile touched, every docker-build mention
#     co-names its manual-fallback status (cf-6's x3 legs own the same rule
#     for their files; this leg owns the sweep across the rest, and other
#     tickets' deferred survivors — charts/ values comments, the strata image
#     test, the cf-96 runbook, suites under tests/ — stay with the close-out
#     sweep card per D29's deferral, reported not pinned);
#   - the prose states the REBUILT laws: calendar yy.mm.N tags (the old
#     v-date scheme died with superseded C02), the FORGE_PUSH_TOKEN /
#     PUSH_TOKEN_GH per-direction pair (FJ_PACKAGE_USER/PUSH_TOKEN_FJ
#     retired), and contains()-membership ROLE guards with the narrow/widen
#     polarity per file and the substring caveat.
#
# The historical record under .agents/ (plans, notes) is deliberately NOT a
# live surface: append-only, it keeps citing pre-move paths honestly.
# Purely static — bash + git grep + python3 (pyyaml for the guards leg).
#
# Self-safety under my own sweep: the banned release path and the retired
# credential names are composed here so this file (a live surface under
# tests/) does not match its own patterns; cf-6's inventory lines naming
# docker-build are exempt because tests/ is outside this suite's claim
# routes, and the ci-surface ban list is exactly the DELETED twin path.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-ci-surface.sh
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

# --- t1 + t2: the workflow inventory, both sides -------------------------------
if ! python3 - <<'PY'
import os, sys

FJ = '.forgejo/workflows'
GH = '.github/workflows'
# cf-6 shipped main-sync (predates), renovate and containers-build; cf-55
# contributes the chart half ONLY (its container twin was superseded);
# builder-bootstrap is cf-6's public-image dispatch recovery lane — the
# fence moved to five before the file landed (red-first doctrine), so a
# fourth-file-only tree is a designed RED here, not a stale pin.
FJ_SET = {'main-sync.yaml', 'renovate.yaml', 'containers-build.yaml', 'release.yaml',
          'builder-bootstrap.yaml'}
# Ruling R1's five gates + the render-test growth (amd-gpu, radiance) that
# landed on main since, PLUS the docker-build manual fallback cf-6 kept.
GH_SET = {'aislop.yaml', 'rulesync.yaml', 'vllm-render-tests.yaml',
          'gpt-researcher-render-tests.yaml', 'llama-swap-tools-tests.yaml',
          'amd-gpu-render-tests.yaml', 'radiance-render-tests.yaml',
          'docker-build.yaml'}


def names(d):
    if not os.path.isdir(d):
        print(f'FAIL: {d} does not exist', file=sys.stderr)
        sys.exit(1)
    return {e for e in os.listdir(d) if os.path.isfile(os.path.join(d, e))}


fj = names(FJ)
if fj != FJ_SET:
    print(f'FAIL: t1: {FJ} holds {sorted(fj)}, expected exactly {sorted(FJ_SET)} (the five-workflow forge family — release.yaml is this ticket\'s, builder-bootstrap.yaml is the cf-6 recovery lane, nothing else may appear)', file=sys.stderr)
    sys.exit(1)
print('ok: t1: the Forgejo inventory is exactly the five-workflow family (cf-6 trio + the moved chart builder + the bootstrap recovery lane)')

gh = names(GH)
if gh != GH_SET:
    print(f'FAIL: t2: {GH} holds {sorted(gh)}, expected the seven gate workflows + docker-build.yaml (the manual-fallback builder cf-6 kept) and NOT release.yaml (the chart half moved) — a stray here means a gate was deleted or a cutover half-did', file=sys.stderr)
    sys.exit(1)
if os.path.join(GH, 'release.yaml') in [os.path.join(GH, n) for n in gh]:
    print('FAIL: t2: the GitHub release twin survived the cutover', file=sys.stderr)
    sys.exit(1)
print('ok: t2: the GitHub inventory is the gates + the manual-fallback docker-build, with the release twin deleted')
PY
then
  fail "t1/t2: see the detail above"
fi
checks=$((checks + 2))

# --- t3: deleted-path sweep — no live surface cites the GitHub release twin ----
# Tracked files only (git grep), the infra-forgejo.sh precedent: vendored
# dependency trees under charts/ are not a live surface, and .agents/ is
# excluded by the explicit root list (append-only history). The pattern is
# composed so this suite never matches itself.
STALE_PAT='\.github/workflows/'release'\.yaml'
if stale=$(git grep -IlE "$STALE_PAT" -- skills tests containers .rulesync .opencode charts services custom-values); then
  printf 'FAIL: t3: live surfaces still citing the deleted GitHub release path:\n%s\n' "$stale" >&2
  exit 1
fi
ok "t3: no tracked live-surface file cites the deleted GitHub release.yaml path"

# --- t4: builder-claim sweep on the reconciled carriers -------------------------
# docker-build.yaml still EXISTS (cf-6 kept it as the workflow_dispatch-only
# manual fallback), so a path citation is not stale — a CLAIM that it is the
# live builder is. Rule: every line naming docker-build on a carrier this
# reconcile owns must co-name the manual/workflow_dispatch/fallback status
# within its sentence (±1 line, prose wraps). charts/ values comments, the
# strata image test, the cf-96 runbook and other tickets' suites carry
# deferred survivors (D29 follow-up sweep card) and are OUT of these routes
# by ruling, not by oversight.
if ! python3 - <<'PY'
import os, subprocess, sys

ROUTES = ['AGENTS.md', 'skills', '.rulesync', '.opencode',
          'custom-values', 'services',
          os.path.join('containers', 'wekan-mcp'),
          os.path.join('containers', 'renovate-mcp')]
OK_WORDS = ('workflow_dispatch', 'manual', 'fallback', 'Manual', 'Fallback')

hits = subprocess.run(['git', 'grep', '-c', 'docker-build', '--'] + ROUTES,
                      capture_output=True, text=True).stdout
bad = []
for line in hits.splitlines():
    f = line.split(':', 1)[0]
    lines = open(f).read().splitlines()
    for i, l in enumerate(lines):
        if 'docker-build' not in l:
            continue
        window = ' '.join(lines[max(0, i - 1):i + 2])
        if not any(w in window for w in OK_WORDS):
            bad.append(f'{f}:{i + 1}: {l.strip()[:110]}')
if bad:
    print('FAIL: t4: docker-build mentions WITHOUT their manual-fallback status on reconciled carriers:\n  ' + '\n  '.join(bad), file=sys.stderr)
    sys.exit(1)
print('  (mentions all co-named; deferred survivors live outside these routes by ruling)')
PY
then
  fail "t4: see the t4 detail above"
fi
ok "t4: on every carrier the reconcile owns, naming docker-build means manual-fallback (a live-builder claim would mis-describe the forge containers-build split)"

# --- t5: credential law + calendar tags, dead schemes banned (D31/D32 prose) ------
if ! python3 - <<'PY'
import sys

agents = open('AGENTS.md').read()
skill = open('skills/container-creation/SKILL.md').read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


# The credential law as LANDED: AGENTS names the shared instance PAT + the
# lowercase namespace; the per-pipeline GitHub-side secret names (chart
# releases: PUSH_TOKEN_GH; container pushes: GHCR_PUSH_PAT) are workflow
# law pinned by forgejo-release.sh t8 and cf-6's containers-build suite —
# the rules file deliberately stays at the shared identity + the job-token
# prohibition.
for tok in ('FORGE_PUSH_TOKEN', 'curatedforest'):
    need(tok in agents, f'AGENTS.md does not name {tok} — the instance credential and the lowercase namespace are hard-rule material post-reconcile')
# The ROLE-membership law + its two caveats.
for tok in ('contains(', 'Substring caveat', 'yy.mm.N'):
    need(tok in agents, f'AGENTS.md lost {tok!r} — membership guards / the substring caveat / the calendar tag are the landed laws')
# Dead worlds must not survive as law anywhere.
DEAD = ('PUSH_TOKEN_FJ', 'FJ_PACKAGE_USER', '10000', 'type=gha',
        'UTC-YYYYMMDD', 'HHMM-base10', 'v<run_number>` (immutable)')
for tok in DEAD:
    need(tok not in agents, f'AGENTS.md still carries {tok!r} — a retired scheme re-becomes law the moment it re-enters the rules file')
# The container skill (cf-6-rewritten): the live builder, the calendar tag,
# the forge PAT — and none of the retired spellings.
for tok in ('containers-build.yaml', 'yy.mm.N', 'FORGE_PUSH_TOKEN', 'GHCR_PUSH_PAT'):
    need(tok in skill, f'container-creation SKILL.md lost {tok!r} — it must describe the builder that actually runs')
for tok in ('10000', 'type=gha', '%Y%m%d', 'HHMM', 'PUSH_TOKEN_FJ', 'FJ_PACKAGE_USER', 'github.actor', 'secrets.GITHUB_TOKEN'):
    need(tok not in skill, f'container-creation SKILL.md carries {tok!r} — retired scheme/credential prose (the auto-token push and the v-date/offset schemes are dead; docs must not re-teach them)')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: AGENTS + container skill state the reconciled law (instance FORGE_PUSH_TOKEN + curatedforest + per-PAT registry pushes; GitHub-side secret names ride the workflow suites) with every retired scheme absent"

# --- t6: ROLE guard membership is consistent across the .forgejo family ---------------
if ! python3 - <<'PY'
import glob, re, sys, yaml

WIDEN_OK = {'containers-build.yaml'}   # the one file whose unset polarity is deliberate

bad = []
for path in sorted(glob.glob('.forgejo/workflows/*.yaml')):
    name = path.rsplit('/', 1)[-1]
    doc = yaml.safe_load(open(path)) or {}
    jobs = doc.get('jobs') or {}
    exprs = [str((job or {}).get('if', '')) for job in jobs.values()]
    exprs += [str(s.get('if', '')) for job in jobs.values()
              for s in (job or {}).get('steps', []) if isinstance(s, dict) and 'if' in s]
    for e in exprs:
        if 'vars.ROLE' not in e:
            continue
        if 'contains(vars.ROLE' not in e:
            bad.append(f'{name}: ROLE guard {e[:90]!r} is not a contains() membership test')
        if re.search(r'vars\.ROLE\s*[=!]=\s*["\x27]', e):
            bad.append(f'{name}: ROLE guard compares ROLE to a STRING value ({e[:90]!r}) — equality polarity is retired (AGENTS Hard rule)')
        if re.search(r'vars\.ROLE\s*[=!]=\s*null', e) and name not in WIDEN_OK:
            bad.append(f'{name}: unset-widen clause in {e[:90]!r} — widen-on-unset is containers-build\'s alone; main-sync/renovate/release stay narrow by the fail-safe reading')
if bad:
    print('FAIL: t6:\n  ' + '\n  '.join(bad), file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t6: see the t6 detail above"
fi
ok "t6: every ROLE guard in every .forgejo workflow is a contains() membership test; the unset-widen clause stays exclusive to containers-build.yaml"

# --- t7: the chart clause in the chart skill names the forge builder -------------------
if ! python3 - <<'PY'
import sys

ref = open('skills/helm-chart-creation/references/chart-templates.md').read()
agents = open('AGENTS.md').read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: t7: {msg}', file=sys.stderr)
        sys.exit(1)


# The chart-creation reference teaches where bumps/publish run; a reader
# following it must land on the Forgejo reality, not the deleted GitHub one.
need('release.yaml' in ref and 'Forgejo' in ref,
     'chart-templates.md does not situate release.yaml on prod Forgejo — the two release.yaml sentences must describe where CI actually runs')
for tok in ('publishes DUAL', 'gh-pages', 'Helm package registry'):
    need(tok in agents, f'AGENTS.md lost the chart clause token {tok!r} — the DUAL publish (GitHub Releases + Pages AND the instance Helm registry) is the landed law')
PY
then
  fail "t7: see the t7 detail above"
fi
ok "t7: the chart-creation reference + AGENTS carry the chart clause (prod-Forgejo release.yaml, DUAL publish to GitHub Releases/gh-pages and the instance Helm registry)"

printf 'PASS: forgejo-ci-surface checks (%d ok)\n' "$checks"
