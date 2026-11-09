#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/main-sync.yaml: the static
# invariants that keep the main-sync design safe — the prod-stage guard on
# both jobs (the repo is hosted on two instances; only the prod one may fan
# main out, and the dev stage firing no job is what stops a push ping-pong),
# plain non-force pushes, destinations and credentials drawn from instance
# vars/secrets rather than file literals, fail-fast run semantics, lab runner
# labels, and push-dev being a bare main push with no merge.
#
# Purely static — no network, no runner: bash reads the file, python3 parses
# it per leg. Convention of tests/services/infra-forgejo.sh.
#
# pyyaml binds the trigger-leg shape: YAML 1.1 resolves the bare `on:` key to
# boolean True, so the trigger block is doc.get(True) or doc.get('on');
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

# --- t2: trigger -------------------------------------------------------------
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

# --- t3: jobs + prod-stage guards --------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

GUARD = "vars.ROLE == 'prod'"
raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t3: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(jobs, dict), 'no jobs: mapping')
need(set(jobs) == {'push-gh', 'push-dev'},
     f'jobs keys are {sorted(jobs)}, expected exactly push-gh + push-dev')
for name in ('push-gh', 'push-dev'):
    need((jobs[name] or {}).get('if') == GUARD,
         f"{name}.if is {(jobs[name] or {}).get('if')!r}, expected {GUARD!r}")
# The dev-stage server must fire no job; any dev guard defeats the breaker.
need("vars.ROLE == 'dev'" not in raw, 'a job guards on vars.ROLE == dev (the dev stage must fire nothing)')
# URL-based instance detection is retired.
need('forgejo.server_url' not in raw, 'forgejo.server_url is referenced (URL detection is retired)')
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: exactly two jobs, both guarded on vars.ROLE == 'prod'; no dev guard, no server_url"

# --- t4: no force --------------------------------------------------------------
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

# --- t5: destinations + credentials -------------------------------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


def count(key):
    # Boundary-anchored: a renamed key that merely extends the original
    # (PUSH_TOKEN_GH -> PUSH_TOKEN_GHX) must not count as an occurrence.
    return len(re.findall(re.escape(key) + r'(?![0-9A-Za-z_])', raw))


for key, job in (('vars.PUSH_URL_GH', 'push-gh'), ('secrets.PUSH_TOKEN_GH', 'push-gh'),
                 ('vars.PUSH_URL_DEV', 'push-dev'), ('secrets.PUSH_TOKEN_DEV', 'push-dev')):
    n = count(key)
    need(n == 1, f'{key} occurs {n} times file-wide, expected exactly once')
    need(key in yaml.dump(jobs.get(job) or {}), f'{key} is not referenced under {job}')
    other = 'push-dev' if job == 'push-gh' else 'push-gh'
    need(key not in yaml.dump(jobs.get(other) or {}), f'{key} is referenced under {other}')
# No repo destination URL literal; the bare https:// scheme is the only
# allowed fragment of a URL in the file.
for host in ('github.com/', 'git.scifi.farm/'):
    need(host not in raw, f'repo URL literal {host} is in the file (destinations are instance-side vars)')
need('forgejo.server_url' not in raw, 'forgejo.server_url is in the file')
# No reserved-prefix key: a secret or var starting with GITHUB_ / FORGEJO_.
reserved = re.findall(r'(?:secrets|vars)\.((?:GITHUB|FORGEJO)[A-Za-z0-9_]*)', raw)
need(not reserved, f'reserved-prefix key reference(s): {", ".join(reserved)}')
# The automatic per-run token is same-repo-only, so it can never credential
# one of these external pushes; checked file-wide so it cannot hide in a
# with: block or a comment.
for tok in ('FORGEJO_TOKEN', 'GITHUB_TOKEN'):
    need(tok not in raw, f'the automatic token {tok} is referenced in the file')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: each PUSH_URL_*/PUSH_TOKEN_* key exactly once under its own job; no URL literal, no reserved-prefix key, no automatic-token push"

# --- t6: failure semantics (every run block in both jobs) -----------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
runs = [(jn, s['run']) for jn, job in jobs.items()
        for s in (job or {}).get('steps', [])
        if isinstance(s, dict) and 'run' in s]

if not runs:
    print('FAIL: t6: no run: blocks found', file=sys.stderr)
    sys.exit(1)
for jn, r in runs:
    if not (isinstance(r, str) and r.lstrip().startswith('set -euo pipefail')):
        print(f'FAIL: t6: {jn} run block does not begin with set -euo pipefail', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t6: see the t6 detail above"
fi
ok "t6: every run block in both jobs begins with set -euo pipefail"

# --- t7: runner labels ------------------------------------------------------------
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

# --- t8: push-dev hygiene -----------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

raw = open(sys.argv[1]).read()
if 'backup-proxy' in raw:
    print('FAIL: t8: backup-proxy appears in the workflow (retired from the active design)', file=sys.stderr)
    sys.exit(1)
if 'git merge' in raw:
    print('FAIL: t8: git merge appears in the workflow (push-dev must be a plain push)', file=sys.stderr)
    sys.exit(1)
job = (yaml.safe_load(raw) or {}).get('jobs', {}).get('push-dev')
if not isinstance(job, dict):
    print('FAIL: t8: no push-dev job', file=sys.stderr)
    sys.exit(1)
steps = job.get('steps', [])
if not any(isinstance(s, dict) and str(s.get('uses', '')).startswith('actions/checkout@') for s in steps):
    print('FAIL: t8: push-dev has no actions/checkout step', file=sys.stderr)
    sys.exit(1)
runs = '\n'.join(str(s.get('run', '')) for s in steps if isinstance(s, dict) and 'run' in s)
if 'HEAD:refs/heads/main' not in runs:
    print('FAIL: t8: push-dev does not do a plain main push (HEAD:refs/heads/main)', file=sys.stderr)
    sys.exit(1)
for bad in ('git merge', 'git branch', 'checkout -B'):
    if bad in runs:
        print(f'FAIL: t8: push-dev run blocks carry branch/merge logic: {bad!r}', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t8: see the t8 detail above"
fi
ok "t8: push-dev is a bare main push — no merge, no backup-proxy, no branch creation"

printf 'PASS: forgejo-main-sync checks (%d ok)\n' "$checks"
