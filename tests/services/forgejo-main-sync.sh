#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/main-sync.yaml: the static
# invariants that keep the main-sync design safe — the two instance guards
# (both Forgejo instances serve the same repository path, so an unguarded
# job ping-pongs pushes between them), non-force pushes, push targets and
# secret keys confined to push-main, fail-fast run semantics, lab runner
# labels, and backup-proxy-merge's zero-secret posture (its push target is
# the repository it runs in, which the automatic same-run token already
# writes).
#
# Purely static — no network, no runner: bash reads the file, python3
# parses it per leg. Convention of tests/services/infra-forgejo.sh.
#
# pyyaml binds the trigger-leg shape: YAML 1.1 resolves the bare `on:` key
# to boolean True, so the trigger block is doc.get(True) or doc.get('on');
# asserting on the string key 'on' alone would redden a correct file.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-main-sync.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF=".forgejo/workflows/main-sync.yaml"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- t1: shape --------------------------------------------------------------
[ -f "$WF" ] || fail "t1: $WF does not exist"
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$WF" \
  || fail "t1: $WF does not parse as YAML"
ok "t1: $WF exists and parses as YAML"

# --- t2: triggers -------------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
trig = doc.get(True) or doc.get('on')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t2: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(trig, dict), 'no top-level on: mapping')
need(set(trig) == {'push', 'workflow_dispatch'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly push + workflow_dispatch')
push = trig['push']
need(isinstance(push, dict), 'push: is not a mapping')
need(push.get('branches') == ['main'],
     f'push.branches is {push.get("branches")!r}, expected exactly [main]')
PY
then
  fail "t2: see the t2 detail above"
fi
ok "t2: on: carries exactly push.branches == [main] plus workflow_dispatch"

# --- t3: jobs + instance guards -------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

GUARD_INFRA = "startsWith(forgejo.server_url, 'https://git.spencerslab.com')"
GUARD_DEV = "startsWith(forgejo.server_url, 'https://git.scifi.farm')"

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t3: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(jobs, dict), 'no jobs: mapping')
need(set(jobs) == {'push-main', 'backup-proxy-merge'},
     f'jobs keys are {sorted(jobs)}, expected exactly push-main + backup-proxy-merge')
need(jobs['push-main'].get('if') == GUARD_INFRA,
     f"push-main.if is {jobs['push-main'].get('if')!r}, expected {GUARD_INFRA!r}")
need(jobs['backup-proxy-merge'].get('if') == GUARD_DEV,
     f"backup-proxy-merge.if is {jobs['backup-proxy-merge'].get('if')!r}, expected {GUARD_DEV!r}")
need(GUARD_INFRA != GUARD_DEV, 'the two guard expressions are not distinct')
# Counted over the raw file, not per job, so a duplicate instance URL pasted
# into a comment or the other job's push URL reddens the leg; the if:
# equality above already pins which job owns each guard.
for lit in ('https://git.spencerslab.com', 'https://git.scifi.farm'):
    n = raw.count(lit)
    need(n == 1, f'{lit} occurs {n} times in the file, expected exactly once')
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: exactly two jobs, each with its one-of, distinct, file-wide server_url guard"

# --- t4: no force ---------------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys

raw = open(sys.argv[1]).read()
for pat in ('--force', '+refs', 'git push -f'):
    n = raw.count(pat)
    if n:
        print(f'FAIL: t4: {pat!r} occurs {n} time(s), expected zero', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t4: see the t4 detail above"
fi
ok "t4: no force-push spelling (--force, +refs, push -f) anywhere in $WF"

# --- t5: targets + secrets --------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
raw = open(sys.argv[1]).read()
jobs = doc.get('jobs') or {}
pm_runs = '\n'.join(str(s.get('run', '')) for s in (jobs.get('push-main') or {}).get('steps', [])
                    if isinstance(s, dict) and 'run' in s)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


for key in ('secrets.GITHUB_PUSH_TOKEN', 'secrets.FORGEJO_DEV_PUSH_TOKEN'):
    # Boundary-anchored: a renamed key that merely extends the original
    # (TOKEN -> TOKENX) must not be counted as an occurrence of it.
    find = re.compile(re.escape(key) + r'(?![0-9A-Za-z_])')
    need(len(find.findall(raw)) == 1, f'{key} occurs {len(find.findall(raw))} times file-wide, expected exactly once')
    need(len(find.findall(pm_runs)) == 1, f'{key} is not used in a push-main run step')
for dst in ('github.com/OwnYourIO/SpencersLab', 'git.scifi.farm/CuratedForest/SpencersLab'):
    need(dst in pm_runs, f'{dst} is not a push destination in push-main')
# The automatic per-run token is scoped to its own repository, so it can
# never credential one of these external pushes; checked file-wide so the
# reference cannot hide in a with: block or a comment.
for tok in ('GITHUB_TOKEN', 'FORGEJO_TOKEN'):
    need(tok not in raw, f'the automatic token {tok} is referenced in the file')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: both external targets and each push credential exactly once, confined to push-main; no automatic-token pushes"

# --- t6: failure semantics (push-main) ----------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

steps = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs', {}).get('push-main', {}).get('steps', [])
runs = [s['run'] for s in steps if isinstance(s, dict) and 'run' in s]

if not runs:
    print('FAIL: t6: push-main has no run: steps', file=sys.stderr)
    sys.exit(1)
for i, r in enumerate(runs):
    if not r.lstrip().startswith('set -euo pipefail'):
        print(f'FAIL: t6: run step {i + 1} does not begin with set -euo pipefail', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t6: see the t6 detail above"
fi
ok "t6: every push-main run: block begins with set -euo pipefail"

# --- t7: runner labels ---------------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

LABELS = {'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'docker', 'node22'}
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}

for name, job in jobs.items():
    label = (job or {}).get('runs-on')
    if label not in LABELS:
        print(f'FAIL: t7: {name}.runs-on is {label!r}, not one of {sorted(LABELS)}', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t7: see the t7 detail above"
fi
ok "t7: every job runs on an advertised lab runner label"

# --- t8: backup-proxy-merge hygiene ------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

job = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs', {}).get('backup-proxy-merge')

if not isinstance(job, dict):
    print('FAIL: t8: no backup-proxy-merge job', file=sys.stderr)
    sys.exit(1)
dumped = yaml.dump(job)
if 'secrets.' in dumped:
    print('FAIL: t8: backup-proxy-merge references a secret key', file=sys.stderr)
    sys.exit(1)
if 'github.com/' in dumped:
    print('FAIL: t8: backup-proxy-merge contains a github.com URL', file=sys.stderr)
    sys.exit(1)
runs = '\n'.join(str(s.get('run', '')) for s in job.get('steps', []) if isinstance(s, dict) and 'run' in s)
if 'backup-proxy' not in runs:
    print('FAIL: t8: no run step names the backup-proxy branch', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t8: see the t8 detail above"
fi
ok "t8: backup-proxy-merge is secret-free and github-free, and its steps name backup-proxy"

printf 'PASS: forgejo-main-sync checks (%d ok)\n' "$checks"
