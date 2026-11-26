#!/usr/bin/env bash
# Whole-state surface guard for the REBUILT cf-55 (chart-half move, reconciled
# to cf-6's conventions per DECISIONS D31/D32): the fence's OTHER side.
# forgejo-build-charts.sh proves the moved builder's internals from the .forgejo
# side; this suite pins the inventory from both sides and sweeps every live
# surface for stale claims the rebuild must have erased:
#   - .forgejo/workflows/ holds EXACTLY the six-workflow family (cf-6's
#     main-sync/renovate + the container builder (renamed build-containers
#     in round 5) + this ticket's chart builder + the AD-56 coder-template
#     publish workflow + the cf-6 builder-bootstrap dispatch recovery lane);
#   - .github/workflows/ keeps the seven gate workflows AND docker-build.yaml
#     — the workflow_dispatch-only manual-fallback builder cf-6 deliberately
#     kept — and NOT the deleted chart twin (the chart half moved, the container half
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
#     PUSH_TOKEN_GH pair — one credential name per registry side, so both
#     GitHub-side lanes share PUSH_TOKEN_GH (retired spellings ride t5's
#     ban lists) — and contains()-membership ROLE guards with the
#     narrow/widen polarity per file and the substring caveat.
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
# Round 4 (chunks/C11.md, D47.6): t8 joins — the stale-name sweep for the
# chart-builder workflow rename (its old bare name token is deliberately
# not written in this comment — this suite is a live surface of its own t8
# once the rename lands). It is CONDITIONAL BY DESIGN:
# while the builder still lives under its old name (this HEAD state) the
# sweep is vacuously green — nothing is stale yet; once the renamed file
# lands, every bare name/title token on a live surface must have been
# re-fenced in the same commit set, with the FROZEN/deferred files
# hard-listed (append-only records, the fire-coupled deferrals D47.8) and
# the sanctioned composed forms (os.path.join, path-qualified twin/history
# mentions) passing. That makes the half-renamed intermediate the leg's
# red state — its named purpose — and C11's merge its first full run.
#
# reading: the t-spec's teeth "drop one bare literal into a live file -> red"
# only have meaning once build-charts.yaml exists).
#
# Round 5 (C15 §D): t8 now carries TWO independent sweeps (release-era and
# containers-era), each vacuous until its own rename arms it; the
# containers-era one accepts the D50.3 dated-history exemption on top of
# the composed forms. t1's FJ_SET member, t5's token tuple and t6's
# WIDEN_OK name the builder under its FINAL file — red through the
# C13/C14 waves by design (pin 3: docs + suite move in ONE commit set at
# C15).
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
# cf-6 shipped main-sync (predates), renovate and the container builder;
# cf-55 contributes the chart half ONLY (its container twin was superseded);
# builder-bootstrap is cf-6's public-image dispatch recovery lane — the
# fence moved to five before the file landed (red-first doctrine), so a
# fourth-file-only tree is a designed RED here, not a stale pin. Round 5
# (C15 pin 3): the container builder is renamed — the member below names its
# FINAL file; red until the rename commit lands (pairing law: docs + suite
# move in the same commit). AD-56 adds the sixth member (coder-template-push.yaml,
# the coder-template publish workflow) in its own ticket; the fence moves
# five → six with it, in the same commit set as its re-fence (D50.3 pairing).
FJ_SET = {'main-sync.yaml', 'renovate.yaml', 'build-containers.yaml', 'build-charts.yaml',
          'builder-bootstrap.yaml', 'coder-template-push.yaml'}
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
    print(f'FAIL: t1: {FJ} holds {sorted(fj)}, expected exactly {sorted(FJ_SET)} (the six-workflow forge family — build-charts.yaml is cf-55\'s, coder-template-push.yaml is AD-56\'s, builder-bootstrap.yaml is the cf-6 recovery lane, nothing else may appear)', file=sys.stderr)
    sys.exit(1)
print('ok: t1: the Forgejo inventory is exactly the six-workflow family (cf-6 trio + the moved chart builder + the AD-56 coder-template workflow + the bootstrap recovery lane)')

gh = names(GH)
if gh != GH_SET:
    print(f'FAIL: t2: {GH} holds {sorted(gh)}, expected the seven gate workflows + docker-build.yaml (the manual-fallback builder cf-6 kept) and NOT the chart twin (the chart half moved) — a stray here means a gate was deleted or a cutover half-did', file=sys.stderr)
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
ok "t3: no tracked live-surface file cites the deleted GitHub twin's workflow path"

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
# lowercase namespace; the GitHub-side secret name is workflow law pinned
# per file — chart releases by forgejo-build-charts.sh t8, container pushes by
# cf-6's build-containers suite t7 — and ONE name serves both lanes since
# R-A (2026-11-22): PUSH_TOKEN_GH. The rules file deliberately stays at the
# shared identity + the job-token prohibition.
for tok in ('FORGE_PUSH_TOKEN', 'curatedforest'):
    need(tok in agents, f'AGENTS.md does not name {tok} — the instance credential and the lowercase namespace are hard-rule material post-reconcile')
# The ROLE-membership law + its two caveats.
for tok in ('contains(', 'Substring caveat', 'yy.mm.N'):
    need(tok in agents, f'AGENTS.md lost {tok!r} — membership guards / the substring caveat / the calendar tag are the landed laws')
# Dead worlds must not survive as law anywhere.
DEAD = ('PUSH_TOKEN_FJ', 'FJ_PACKAGE_USER', 'GHCR_PUSH_PAT', '10000', 'type=gha',
        'UTC-YYYYMMDD', 'HHMM-base10', 'v<run_number>` (immutable)')
for tok in DEAD:
    need(tok not in agents, f'AGENTS.md still carries {tok!r} — a retired scheme re-becomes law the moment it re-enters the rules file')
# The container skill (cf-6-rewritten): the live builder, the calendar tag,
# the forge PAT + the one GitHub-side PAT — and none of the retired
# spellings.
for tok in ('build-containers.yaml', 'yy.mm.N', 'FORGE_PUSH_TOKEN', 'PUSH_TOKEN_GH'):
    need(tok in skill, f'container-creation SKILL.md lost {tok!r} — it must describe the builder that actually runs')
for tok in ('10000', 'type=gha', '%Y%m%d', 'HHMM', 'PUSH_TOKEN_FJ', 'FJ_PACKAGE_USER', 'GHCR_PUSH_PAT', 'github.actor', 'secrets.GITHUB_TOKEN'):
    need(tok not in skill, f'container-creation SKILL.md carries {tok!r} — retired scheme/credential prose (the auto-token push and the v-date/offset schemes are dead; docs must not re-teach them)')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: AGENTS + container skill state the reconciled law (instance FORGE_PUSH_TOKEN + curatedforest + per-PAT registry pushes; one GitHub-side name — PUSH_TOKEN_GH — for both lanes, pinned per file by forgejo-build-charts.sh t8 and the containers-build suite) with every retired scheme absent"

# --- t6: ROLE guard membership is consistent across the .forgejo family ---------------
if ! python3 - <<'PY'
import glob, re, sys, yaml

WIDEN_OK = {'build-containers.yaml'}   # the one file whose unset polarity is deliberate

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
            bad.append(f'{name}: unset-widen clause in {e[:90]!r} — widen-on-unset is the container builder\'s alone; main-sync/renovate/chart builder stay narrow by the fail-safe reading')
if bad:
    print('FAIL: t6:\n  ' + '\n  '.join(bad), file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t6: see the t6 detail above"
fi
ok "t6: every ROLE guard in every .forgejo workflow is a contains() membership test; the unset-widen clause stays exclusive to build-containers.yaml"

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
need('build-charts.yaml' in ref and 'Forgejo' in ref,
     'chart-templates.md does not situate build-charts.yaml on prod Forgejo — the two build-charts.yaml sentences must describe where CI actually runs')
for tok in ('publishes DUAL', 'gh-pages', 'Helm package registry'):
    need(tok in agents, f'AGENTS.md lost the chart clause token {tok!r} — the DUAL publish (GitHub Releases + Pages AND the instance Helm registry) is the landed law')
PY
then
  fail "t7: see the t7 detail above"
fi
ok "t7: the chart-creation reference + AGENTS carry the chart clause (prod-Forgejo build-charts.yaml, DUAL publish to GitHub Releases/gh-pages and the instance Helm registry)"

# --- t8: stale-name sweeps, armed by each rename (C11 AC2/D47.6; C15 widen) ----
# EXPLORE's rename law: after a git mv, NO live surface may carry the old
# workflow's bare name or display-title token — every legitimate survivor is
# either a composed twin mention (os.path.join, the path-qualified `".github/"`
# alternation the coord allow-cases use, the dated containers-build history
# line) or a hard-listed append-only record. Pre-rename the sweep is
# vacuously green by design: the name is live truth, nothing lies; the leg's
# red state is the half-renamed intermediate (C11.md's posture — report
# reading: the t-spec's teeth "drop one bare literal into a live file -> red"
# only have meaning once build-charts.yaml exists). Round 5 WIDENS the leg
# (C15 §D): a second sweep, armed by the containers-build ->
# build-containers.yaml rename, bans the bare old file token on live
# surfaces; composed forms + FROZEN records + self-identifying dated
# history exempt (D50.3).
if ! python3 - <<'PY'
import os, re, subprocess, sys

# Needles composed at runtime (t3's STALE_PAT discipline): this live file
# must never carry the plain tokens it bans.
OLD = 'release' + '.' + 'yaml'
old_re = re.compile('release' + r'[.]' + 'yaml')
title_re = re.compile('Release' + r'[ ]Charts')
OLD2 = 'containers-build' + '.' + 'yaml'
old2_re = re.compile('containers-build' + r'[.]' + 'yaml')

# Hard-listed exemptions (C11.md FROZEN + LEAVE-AS-RECORD + D47.8 fire-
# coupled deferrals — every entry names why it may carry the historical
# token; the follow-up-card sweep removes them file by file).
EXEMPT = {
    os.path.join('charts', 'llama-swap', 'tests', 'evidence', 'c05_expected_evidence.yaml'),  # historical evidence artifact
    os.path.join('tests', 'cf96-deploy', 'readback-runbook.md'),                               # dated runbook, append-only law
    os.path.join('charts', 'amd-gpu', 'tests', 'test_provenance.py'),                          # fire-coupled FAIL prose (charts/** edit mints a release)
    os.path.join('charts', 'radiance', 'tests', 'test_contract.py'),                           #   ...same deferral
    os.path.join('tests', 'multi-repo', 'ha-chart.sh'),                                        #   ...same deferral
    os.path.join('tests', 'multi-repo', 'mosquitto-chart.sh'),                                 #   ...same deferral
}

files = subprocess.run(['git', 'ls-files', '-z'], capture_output=True, text=True).stdout.split('\0')
offenders = []

def sweep(re_path, token_re, extra_res, armed_label, history_free):
    """One rename sweep over every tracked live surface. Returns offenders.
    history_free=1 adds the D50.3 dated-history exemption (second rename
    only — the release-era sweep keeps its original, stricter teeth)."""
    hits = []
    for f in files:
        if not f or f.startswith('.agents' + os.sep):
            continue
        if f in EXEMPT:
            continue
        if os.path.exists(os.path.join('.forgejo', 'workflows', re_path)):
            continue  # the old file is still LIVE truth — vacuous (armed later)
        try:
            text = open(f, encoding='utf-8', errors='replace').read()
        except (IsADirectoryError, OSError):
            continue
        for i, l in enumerate(text.splitlines(), 1):
            for rx in extra_res:
                if rx.search(l):
                    hits.append(f'{f}:{i}: [{armed_label} title token] {l.strip()[:100]}')
                    break
            else:
                for m in token_re.finditer(l):
                    # Composed forms pass (EXPLORE H.1 / C11 AC2): an
                    # os.path.join carrier, or a line that names the GitHub
                    # twin or brackets itself as history ("since renamed",
                    # "moved to"). A bare name claim — stale allow-case
                    # member, forgotten prose cite — matches neither.
                    if 'os.path.join' in l:
                        continue
                    before = l[:m.start()]
                    if before.endswith('/') and re.search(r'(?i)github|renamed|moved to', l):
                        continue
                    if history_free and re.search(r'(?i)since renamed|moved to|\bdated\b|histor|pre-rename|\bera\b', l):
                        continue
                    hits.append(f'{f}:{i}: [{armed_label} bare name token] {l.strip()[:100]}')
    return hits

if os.path.exists(os.path.join('.forgejo', 'workflows', 'build-charts.yaml')):
    offenders += sweep(OLD, old_re, [title_re], 'release-rename', 0)
if os.path.exists(os.path.join('.forgejo', 'workflows', 'build-containers.yaml')):
    offenders += sweep(OLD2, old2_re, [], 'containers-rename', 1)

if offenders:
    print('FAIL: t8: live surfaces still carry an old builder name/title after a rename — the git mv and the re-fence ride ONE commit set (C11 AC2; C15 widen):', file=sys.stderr)
    for o in offenders:
        print('  ' + o, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t8: see the t8 detail above"
fi
ok "t8: with each rename landed, zero bare old-name/old-title tokens survive on live surfaces (composed twin forms and the hard-listed records pass; each sweep vacuous-green until its own rename arms it — the containers-era sweep joins the release-era one)"

printf 'PASS: forgejo-ci-surface checks (%d ok)\n' "$checks"
