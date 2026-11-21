#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/main-sync.yaml: the static
# invariants that keep the main-sync design safe — the prod-stage guard on
# every job (the repo is hosted on two instances; only the prod one may fan
# main out, and the dev stage firing no job is what stops a push ping-pong),
# plain non-force pushes, destinations and credentials drawn from instance
# vars/secrets rather than file literals, fail-fast run semantics, lab runner
# labels, push-dev being a bare main push with no merge — and from cf-139
# C04 (ruling R1 option (c)) the `hook-relay` job: the mirror workflow IS
# the webhook. t9..t13 pin its shape: needs [push-gh] (firing only after
# GitHub advanced is what resolves the race), the GitHub-shaped payload
# contract consumed by the argocd-hook relay, the plain-hex
# X-Forgejo-Signature dialect (R3: this caller must NOT speak the hub
# dialect — t10 bans both hub-dialect literals file-wide), the instance-side
# vars.ARGOCD_HOOK_URL / secrets.ARGOCD_HOOK_SECRET pair (joined to the
# exactly-once t5 matrix), the unset-skip / warn-and-continue fail-safe
# posture (a fan-out trigger failure lands that push as a no-op and never
# breaks the mirror — the R1 documented limitation), and `bash -n` over
# every extracted run block (t13 — this suite is the repo's only
# forge-workflow check; there is no actionlint precedent here).
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
# Env: MAIN_SYNC_WF=<path> points the suite at a workflow copy (mutation
#      tests, or reviewing the file before it lands at its tracked path).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF="${MAIN_SYNC_WF:-.forgejo/workflows/main-sync.yaml}"

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
# cf-139 C04 re-pin: the job SET grows to exactly {push-gh, push-dev,
# hook-relay} and the byte-exact membership guard must hold on all three —
# the hook job firing on a dev instance would POST a trigger for a push the
# mirror never made. Pre-C04 this leg is designed-red on the set equality.
if ! python3 - "$WF" <<'PY'
import sys, yaml

# Membership form (C04 migration, OQ-1/OQ-7 ruling): one guard shape
# repo-wide. Bare contains() keeps unset fail-safe NARROW here on purpose —
# the cf-119 dev-stage breaker survives — while list values like dev,prod
# start working; the exact bytes are pinned so either job regaining the
# equality form reddens this suite (and g1 in the containers suite).
GUARD = "contains(vars.ROLE, 'prod')"
raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t3: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(jobs, dict), 'no jobs: mapping')
need(set(jobs) == {'push-gh', 'push-dev', 'hook-relay'},
     f'jobs keys are {sorted(jobs)}, expected exactly push-gh + push-dev + hook-relay (C04: the relay trigger joins the set; a fourth job means an ad-hoc mirror not pinned by this suite)')
for name in ('push-gh', 'push-dev', 'hook-relay'):
    need((jobs[name] or {}).get('if') == GUARD,
         f"{name}.if is {(jobs[name] or {}).get('if')!r}, expected {GUARD!r} (byte-exact membership; ${{ }}-wrapped or equality forms redden this leg)")
# The dev-stage server must fire no job; any dev guard defeats the breaker.
need("vars.ROLE == 'dev'" not in raw, 'a job guards on vars.ROLE == dev (the dev stage must fire nothing)')
# URL-based instance detection is retired.
need('forgejo.server_url' not in raw, 'forgejo.server_url is referenced (URL detection is retired)')
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: exactly three jobs (push-gh, push-dev, hook-relay), every one guarded on the byte-exact contains(vars.ROLE, 'prod'); no dev guard, no server_url"

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
    for other, ojob in jobs.items():
        if other != job:
            need(key not in yaml.dump(ojob or {}), f'{key} is referenced under {other}')

# C04 joins the matrix: the hook job's destination and credential are
# instance-side too (the file still carries no URL and no token). The
# exactly-once count here is of WIRING occurrences (lines carrying ${{ }})
# — the pinned skip-warning TEXT also names both keys per the chunk, and a
# second ${{ }} mention anywhere (another job, a duplicated env) is still
# caught. Job-scoped absence stays absolute.
def expr_count(key):
    return sum(ln.count(key) for ln in raw.splitlines() if '${{' in ln)


for key, job in (('vars.ARGOCD_HOOK_URL', 'hook-relay'), ('secrets.ARGOCD_HOOK_SECRET', 'hook-relay')):
    n = expr_count(key)
    need(n == 1, f'{key} is WIRED (${{{{ ... }}}} line) {n} times, expected exactly once — a second wiring means a duplicated or moved env reference')
    need(key in yaml.dump(jobs.get(job) or {}), f'{key} is not referenced under {job}')
    for other, ojob in jobs.items():
        if other != job:
            need(key not in yaml.dump(ojob or {}), f'{key} is referenced under {other}')
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
ok "t5: each PUSH_URL_*/PUSH_TOKEN_* key exactly once under its own job, plus the hook job's ARGOCD_HOOK_URL/ARGOCD_HOOK_SECRET pair exactly once under hook-relay only; no URL literal, no reserved-prefix key, no automatic-token push"

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
ok "t6: every run block in every job begins with set -euo pipefail"

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

# --- t9: hook-relay job shape (C04 AC2) ------------------------------------------
# Designed-red until C04 lands: the job does not exist yet. Pin the race
# resolution itself — needs [push-gh] as a LIST (firing only on push-gh
# success is what makes the fan-out resolve the NEW revision, R1 option (c))
# — plus the file's own conventions for a new job: byte-exact prod guard,
# lab label, no checkout (the payload comes from the Actions context only),
# and the diag-step precedent.
if ! python3 - "$WF" <<'PY'
import sys, yaml

GUARD = "contains(vars.ROLE, 'prod')"
LABELS = {'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'docker', 'node22'}
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t9: {msg}', file=sys.stderr)
        sys.exit(1)


job = jobs.get('hook-relay')
need(isinstance(job, dict), 'no hook-relay job (C04: the main-sync job IS the webhook trigger)')
need(job.get('needs') == ['push-gh'],
     f'needs is {job.get("needs")!r}, expected exactly the list ["push-gh"] — after push-gh success is the race resolution, and needs on push-dev or a missing needs redden this leg')
need(job.get('if') == GUARD, f'if is {job.get("if")!r}, expected {GUARD!r} exact bytes')
need(job.get('runs-on') in LABELS, f'runs-on is {job.get("runs-on")!r}, not a lab label')
steps = job.get('steps') or []
need(steps, 'hook-relay has no steps')
need(not any(isinstance(s, dict) and 'uses' in s for s in steps),
     'a hook-relay step uses an action — no checkout here: the payload comes from the Actions context only (C04 job task)')
need(any(isinstance(s, dict) and s.get('name') == 'diag' for s in steps),
     'no diag step (neighbors carry one; it echoes ROLE for instance-side debugging)')
diag = next(s for s in steps if isinstance(s, dict) and s.get('name') == 'diag')
need('vars.ROLE' in str(diag.get('run', '')) and 'ROLE=' in str(diag.get('run', '')),
     f'diag step does not echo ROLE like its neighbors: {diag.get("run")!r:.120}')
runs = [s.get('run') for s in steps if isinstance(s, dict) and s.get('run')]
need(runs, 'hook-relay has no run block')
need(all(str(r).lstrip().startswith('set -euo pipefail') for r in runs),
     'a hook-relay run block does not start with set -euo pipefail (t6 shape, job-local)')
PY
then
  fail "t9: see the t9 detail above"
fi
ok "t9: hook-relay needs == [push-gh], exact prod guard, lab label, zero uses: steps, a ROLE-echoing diag step and set -euo pipefail run heads (C04 AC2)"

# --- t10: forbidden patterns, file-wide (C04 AC3) ---------------------------------
# The caller speaks the FORGE dialect only: the hub-dialect literals must not
# appear anywhere (a copy-pasted sha256= recipe would sign bytes the relay's
# first-present-header rule then rejects, or worse, claim GitHub provenance).
# t4's force sweep, t5's URL/token/reserved-prefix sweeps cover the rest.
if ! python3 - "$WF" <<'PY'
import sys

raw = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: t10: {msg}', file=sys.stderr)
        sys.exit(1)


for pat, why in (('sha256=', 'the sha256= prefix appears — this caller signs plain hex (R3; the hub dialect belongs to the R2 future-GitHub-webhook door, not to this file)'),
                 ('X-Hub-Signature-256', 'the hub header name appears — the job must send only X-Forgejo-Signature (R3)'),):
    n = raw.count(pat)
    need(n == 0, f'{pat!r} occurs {n} time(s) file-wide, expected zero ({why})')
PY
then
  fail "t10: see the t10 detail above"
fi
ok "t10: no sha256= and no X-Hub-Signature-256 literal anywhere — the job speaks the forge dialect exclusively (C04 AC3)"

# --- t11: contract tokens in the job (C04 AC4) -------------------------------------
# Payload key set + fallback defaults + signing + header family + curl knobs
# in the run block; context wiring in the env maps. These tokens ARE the
# offline contract between C04 and the re-pinned relay harness (its
# forge-delivery e2e leg signs and shapes the identical bytes).
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('hook-relay') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t11: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(job, dict) and job, 'no hook-relay job (t9 already reddened if C04 is missing; t11 needs it too)')
runs = [str(s.get('run')) for s in (job.get('steps') or []) if isinstance(s, dict) and s.get('run')]
blob = "\n".join(runs)

# env maps: job-level or step-level, flattened to name -> value text
env_kv = {}
for src in [job.get('env') or {}] + [s.get('env') or {} for s in (job.get('steps') or []) if isinstance(s, dict)]:
    for k, v in src.items():
        env_kv[k] = str(v)
for key, want_frag in (
        ('RELAY_URL', 'vars.ARGOCD_HOOK_URL'),
        ('RELAY_SECRET', 'secrets.ARGOCD_HOOK_SECRET'),
        ('EVT_REF', 'github.event.ref'),
        ('EVT_BEFORE', 'github.event.before'),
        ('EVT_AFTER', 'github.event.after'),
        ('EVT_FULL_NAME', 'github.event.repository.full_name'),
        ('GH_SHA', 'github.sha'),
        ('GH_REPO', 'github.repository'),
        ('GH_REF', 'github.ref'),
        ('RUN_TAG', 'github.run_id')):
    need(key in env_kv, f'env key {key} is not set in the job (instance keys and context fields stay env-side, C04 job task)')
    need(want_frag in env_kv[key], f'env {key} is {env_kv[key]!r}, expected to reference {want_frag!r}')
need('github.run_attempt' in env_kv.get('RUN_TAG', ''), 'RUN_TAG does not use github.run_attempt (retries must form a distinct delivery id)')

# the payload builder: json.dumps fed from the env, keys exactly the contract set
dumps_blocks = [r for r in runs if 'json.dumps' in r]
need(dumps_blocks, 'no run block uses json.dumps — the payload must be built by python3 from env, not shell-quoted (C04 payload task)')
db = "\n".join(dumps_blocks)
for tok in ('"ref"', '"before"', '"after"', '"full_name"'):
    need(tok in db, f'payload key {tok} missing from the json.dumps block — the pinned key set is ref/before/after/repository.full_name')
for tok, why in (('refs/heads/main', 'ref fallback default'),
                 ('$GH_SHA', 'after fallback default'),
                 ('$GH_REPO', 'full_name fallback default')):
    need(tok in db, f'{why} {tok!r} missing — dispatch/first-push payloads must fall back exactly as pinned (release.yaml:54 context-quirk precedent)')

# signing: openssl plain hex, NO prefix (prefix ban is t10's file-wide sweep)
need('openssl dgst -sha256 -hmac' in blob, 'no `openssl dgst -sha256 -hmac` signing line (R3 plain-hex HMAC of the raw body)')
need("awk '{print $NF}'" in blob, "no awk '{print $NF}' field extraction — the digest line must reduce to bare hex")

# header family, all on curl lines
curl_lines = [ln for ln in blob.splitlines() if 'curl' in ln or re.search(r'-H\s', ln) or 'X-' in ln]
cb = "\n".join(curl_lines)
for tok in ('Content-Type', 'X-Forgejo-Event', 'X-GitHub-Event', 'X-Forgejo-Signature',
            'X-Forgejo-Delivery', 'X-GitHub-Delivery'):
    need(tok in cb, f'header {tok} missing from the curl invocation — the full delivery-identity family is the real-Forgejo shape the relay expects (C04 POST task)')
need('X-GitHub-Event: push' in cb, 'X-GitHub-Event is not pinned to push — that header IS the relay event gate, unchanged')

# curl knobs: bounded, quiet-but-erroneous, code-capturing, body-verbatim
for tok, why in (('-sS', 'curl -sS'), ('-o /dev/null', 'curl output redirect'),
                 ("%{http_code}", 'curl -w code capture'), ('--max-time 15', 'per-attempt timeout'),
                 ('--retry 3', 'bounded retries'), ('--retry-delay 5', 'retry delay'),
                 ('--retry-all-errors', 'retry-all-errors (5xx/connection must retry, not just some codes)'),
                 ('--data', 'body passed verbatim')):
    need(tok in blob, f'{why} token {tok!r} missing from the curl call (C04 POST task)')

# audit echo on success
need('relay accepted' in blob and 'code=' in blob, 'no `ok: relay accepted code=...` audit echo (C04 audit-echo task; the smoke greps it)')
PY
then
  fail "t11: see the t11 detail above"
fi
ok "t11: env wiring (RELAY_*/EVT_*/GH_*/RUN_TAG to their context fields), the json.dumps key set with the pinned fallback defaults, openssl plain-hex + awk NF, the full header family, the bounded curl knobs and the audit echo (C04 AC4)"

# --- t12: fail-safe posture (C04 AC4/AC1 limitation) -------------------------------
# Unset keys must skip with a warning and exit 0, and no curl path may abort
# the mirror: under set -euo pipefail a bare curl is a hard fail, so every
# curl line must be a command-substitution capture (CODE=$(curl ...)), and
# the job must end in an exit 0 guard, never exit 1.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('hook-relay') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t12: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(job, dict) and job, 'no hook-relay job')
runs = [str(s.get('run')) for s in (job.get('steps') or []) if isinstance(s, dict) and s.get('run')]
blob = "\n".join(runs)

need(re.search(r'-z\s*"?\$\{?RELAY_URL', blob), 'no `-z $RELAY_URL` skip test — unset vars.ARGOCD_HOOK_URL must warn and skip, never fail the mirror (C04 skip guard)')
need(re.search(r'-z\s*"?\$\{?RELAY_SECRET', blob), 'no `-z $RELAY_SECRET` skip test (same unset-skip posture for the secret)')
need('::warning::' in blob, 'no ::warning:: annotation on the skip/failure paths — the posture is visible-when-skipped, silent never')
need('hook-relay not configured' in blob, 'the skip warning must name the condition: `hook-relay not configured` (the runbook §4 kill-switch leg quotes it)')
need('exit 0' in blob, 'no exit 0 — unset-skip and post-failure both leave the job green (fail-safe, unset-ROLE posture philosophy)')
need('401' in blob and 'disagrees' in blob, 'no 401 branch with the "relay secret disagrees" wording (C04 failure-warn: a vault/Bitwarden disagreement must say so in the job log)')
need('exit 1' not in blob, 'exit 1 appears — no path in this job may fail the run; the fan-out trigger is best-effort by ruling (R1 limitation)')

bad_curl = [ln.strip()[:100] for ln in blob.splitlines()
            if re.search(r'(?<![\w/-])curl\b', ln) and '$(curl' not in ln and not ln.strip().startswith('#')]
need(not bad_curl, f'bare (non-captured) curl line(s) under set -euo pipefail — every curl must run inside a $( ... ) capture so its failure is classified, not fatal: {bad_curl}')
PY
then
  fail "t12: see the t12 detail above"
fi
ok 't12: unset-skip warns (hook-relay not configured) and exits 0, the 401-disagrees branch exists, no exit 1 anywhere, and every curl is a captured command substitution — the trigger can never abort the mirror (C04 fail-safe posture)'

# --- t13: bash -n over every run block (C04 AC1) -------------------------------------
# The runners only see the extracted scripts; a shell-syntax error in any
# job's run block is a CI-only failure, so the static suite must catch it
# first. Regression pin: green before C04 too (the two existing blocks are
# valid), red for any malformed new block.
if ! python3 - "$WF" <<'PY'
import os, subprocess, sys, tempfile, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
runs = [(jn, s.get('name') or i, str(s['run']))
        for jn, job in jobs.items()
        for i, s in enumerate((job or {}).get('steps') or [])
        if isinstance(s, dict) and s.get('run')]

if not runs:
    print('FAIL: t13: no run blocks found', file=sys.stderr)
    sys.exit(1)
for jn, name, r in runs:
    fd, path = tempfile.mkstemp(prefix='mainsync-', suffix='.sh',
                                dir=os.environ.get('TMPDIR', '/tmp/opencode'))
    with os.fdopen(fd, 'w') as f:
        f.write(r)
    rc = subprocess.run(['bash', '-n', path], capture_output=True, text=True)
    os.unlink(path)
    if rc.returncode != 0:
        print(f'FAIL: t13: bash -n rejected the {jn}/{name} run block: {rc.stderr.strip()[:200]}', file=sys.stderr)
        sys.exit(1)
print('ok: t13 — every extracted run block (%d) passes bash -n' % len(runs))
PY
then
  fail "t13: see the t13 detail above"
fi
ok "t13: all run blocks across all three jobs are syntactically valid bash"

printf 'PASS: forgejo-main-sync checks (%d ok)\n' "$checks"
