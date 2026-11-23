#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/main-sync.yaml: the static
# invariants that keep the main-sync design safe — the prod-stage guard on
# every job (the repo is hosted on two instances; only the prod one may fan
# main out, and the dev stage firing no job is what stops a push ping-pong),
# plain non-force pushes, destinations and credentials drawn from instance
# vars/secrets rather than file literals, fail-fast run semantics, lab runner
# labels, push-dev being a bare main push with no merge — and from cf-139
# reopen2 (C06, rulings R5/R6) the `sync-fanout` job: the mirror workflow IS
# the webhook and now speaks to the clusters DIRECTLY. t9..t13 pin its shape:
# needs [push-gh] (firing only after GitHub advanced is the race resolution,
# R1 option (c) — SURVIVES byte-true), a bare actions/checkout@v7 step (the
# fan-out logic home is scripts/argocd-fanout.py riding the checkout, no
# history needed), one ORG-level Actions secret `secrets.ARGOCD_SYNC_TOKENS`
# referenced exactly once through scope inheritance (the file cannot prove
# scope — the header sentence carries the org placement, the no-var-twin leg
# keeps the repo free of its own key), the unset-skip warn-and-exit-0
# posture, and the RULED exit refinement: config/setup errors go RED through
# the unguarded python call (no `|| true` swallow), runtime failures stay
# soft in the script's own contract. The reopen1 transport dies here: HMAC
# signing, the header family, curl, the payload builder — t10 bans them
# file-wide.
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
#      tests, or reviewing the file before it lands at its tracked path);
#      FANOUT_SCRIPT / FANOUT_ROSTER retarget t13's cross-artifact legs.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF="${MAIN_SYNC_WF:-.forgejo/workflows/main-sync.yaml}"
FANOUT="${FANOUT_SCRIPT:-scripts/argocd-fanout.py}"
ROSTER="${FANOUT_ROSTER:-scripts/argocd-fanout.json}"

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
# C06 re-pin (reopen2): the job SET is exactly {push-gh, push-dev,
# sync-fanout} — the relay trigger job becomes the direct fan-out job, so the
# retired NAME is banned file-wide too (a renamed-but-kept job would keep an
# unpinned fifth surface alive; the count stays three). The byte-exact
# membership guard must hold on all three — the fan-out firing on a dev
# instance would sync clusters for a push the mirror never made.
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
need(set(jobs) == {'push-gh', 'push-dev', 'sync-fanout'},
     f'jobs keys are {sorted(jobs)}, expected exactly push-gh + push-dev + sync-fanout (C06: the relay trigger job IS replaced by the fan-out job — a fourth job or a kept-alive hook job means an unpinned surface)')
need('hook-relay' not in raw,
     'the retired hook-relay name survives in the file — the job is renamed to sync-fanout (C06), no relay-era identifier may linger')
for name in ('push-gh', 'push-dev', 'sync-fanout'):
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
ok "t3: exactly three jobs (push-gh, push-dev, sync-fanout), no hook-relay residue, every one guarded on the byte-exact contains(vars.ROLE, 'prod'); no dev guard, no server_url"

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
# C06 re-pin: the vault-key matrix flips from the relay pair to the single
# tokens secret. Org-scope ruling (2026-11-23): the key is an ORG Actions
# secret inherited by the repo; ${{ secrets.* }} cannot tell the scopes apart,
# so the file-level pins are: exactly-once wiring under sync-fanout, NO
# repo-level twin (vars.ARGOCD_SYNC_TOKENS must stay at zero occurrences —
# the owner's org hygiene keeps the single instance and a repo key would
# silently shadow it), the retired ARGOCD_HOOK_* pair gone entirely, and a
# header sentence that declares the org placement while never claiming the
# repo carries the key.
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


def expr_count(key):
    return sum(ln.count(key) for ln in raw.splitlines() if '${{' in ln)


for key, job in (('vars.PUSH_URL_GH', 'push-gh'), ('secrets.PUSH_TOKEN_GH', 'push-gh'),
                 ('vars.PUSH_URL_DEV', 'push-dev'), ('secrets.PUSH_TOKEN_DEV', 'push-dev')):
    n = count(key)
    need(n == 1, f'{key} occurs {n} times file-wide, expected exactly once')
    need(key in yaml.dump(jobs.get(job) or {}), f'{key} is not referenced under {job}')
    for other, ojob in jobs.items():
        if other != job:
            need(key not in yaml.dump(ojob or {}), f'{key} is referenced under {other}')

# C06's single vault reference: exactly one ${{ }} wiring, under sync-fanout
# only. The exactly-once count is of WIRING occurrences (lines carrying
# ${{ }}) — the pinned skip-warning TEXT also names the key per the chunk,
# and a second wiring anywhere is still caught.
n = expr_count('secrets.ARGOCD_SYNC_TOKENS')
need(n == 1, f'secrets.ARGOCD_SYNC_TOKENS is wired (${{{{ ... }}}} line) {n} times, expected exactly once — a second wiring means a duplicated or moved env reference')
need('secrets.ARGOCD_SYNC_TOKENS' in yaml.dump(jobs.get('sync-fanout') or {}), 'the tokens secret is not referenced under sync-fanout')
for other, ojob in jobs.items():
    if other != 'sync-fanout':
        need('secrets.ARGOCD_SYNC_TOKENS' not in yaml.dump(ojob or {}), f'the tokens secret is referenced under {other}')

# No var twin, no repo-scope shadow (ORG ruling: the repo must NOT define a
# key of this name; a vars row would also fake the secret's presence).
need(count('vars.ARGOCD_SYNC_TOKENS') == 0, 'vars.ARGOCD_SYNC_TOKENS appears — the tokens are a SECRET only, and the repo must carry no twin of the org-level key (single-instance discipline)')
for key in ('vars.ARGOCD_HOOK_URL', 'secrets.ARGOCD_HOOK_SECRET'):
    need(count(key) == 0, f'{key} still appears — the relay-era vault pair is disposed (C07 removes the keys instance-side; the file may not even mention them)')

# No repo destination URL literal; the bare https:// scheme is the only
# allowed fragment of a URL in the file. (The roster JSON deliberately lives
# OUTSIDE this sweep: its hosts are non-secret route truth, reviewed in PRs.)
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

# Header-comment scope sentence: the tokens secret is declared ORG-level
# (inherited), and no sentence may claim the repo carries it. The reference
# form is scope-blind, so this leg pins the DOC truth, not the resolution.
header = []
for ln in raw.splitlines():
    if ln.strip().startswith('on:'):
        break
    if ln.lstrip().startswith('#'):
        header.append(ln)
hb = "\n".join(header)
need('ARGOCD_SYNC_TOKENS' in hb, 'the header comment never names ARGOCD_SYNC_TOKENS — the instance-keys sentence must describe the single vault secret (C06 header task)')
need(re.search(r"(?i)\borg[- /]?(level|scoped)\b", hb) or re.search(r"(?i)\borg\b[^.\n]{0,60}secret", hb),
     'the header comment carries no org-scope wording for the tokens secret (owner ruling 2026-11-23: ORG-level Actions secret on the prod instance, inherited by the repo — the sentence is the only place the scope can live)')
for claim in (r'(?i)repo[- /]?(level|scoped)[^\n]{0,40}(actions )?secret',
              r'(?i)this repo[^.\n]{0,60}(defines|carries|holds)[^.\n]{0,30}ARGOCD_SYNC_TOKENS'):
    need(not re.search(claim, hb), f'the header comment makes a repo-scope claim about the tokens secret ({claim!r}) — the key lives at org scope; a repo key would shadow it')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: each PUSH_URL_*/PUSH_TOKEN_* key exactly once under its own job; secrets.ARGOCD_SYNC_TOKENS wired exactly once under sync-fanout only with no vars twin and no ARGOCD_HOOK_* residue; header declares the ORG-level scope without a repo claim; no URL literal, no reserved-prefix key, no automatic-token push"

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

# --- t9: sync-fanout job shape (C06 AC3) -------------------------------------------
# Designed-red until C06 lands: the job does not exist yet. The checkout leg
# FLIPS from the shipped t9 (the relay job had zero uses: steps): the fan-out
# runs repo-side scripts, so the job gains EXACTLY one bare actions/checkout@v7
# — bare because the fan-out needs no history (the push jobs' fetch-depth: 0
# exists for push negotiation only). needs [push-gh] keeps the race
# resolution byte-true (R1 option (c)).
if ! python3 - "$WF" <<'PY'
import sys, yaml

GUARD = "contains(vars.ROLE, 'prod')"
LABELS = {'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'docker', 'node22'}
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t9: {msg}', file=sys.stderr)
        sys.exit(1)


job = jobs.get('sync-fanout')
need(isinstance(job, dict), 'no sync-fanout job (C06: the fan-out job replaces the relay trigger)')
need(job.get('needs') == ['push-gh'],
     f'needs is {job.get("needs")!r}, expected exactly the list ["push-gh"] — after push-gh success is the race resolution (apps track GitHub), unchanged from C04')
need(job.get('if') == GUARD, f'if is {job.get("if")!r}, expected {GUARD!r} exact bytes')
need(job.get('runs-on') in LABELS, f'runs-on is {job.get("runs-on")!r}, not a lab label')
steps = job.get('steps') or []
need(steps, 'sync-fanout has no steps')
uses = [s for s in steps if isinstance(s, dict) and 'uses' in s]
need(len(uses) == 1, f'{len(uses)} uses: steps — the job carries EXACTLY one checkout (any second action, or none, deviates from the C06 job task)')
step = uses[0]
need(str(step.get('uses')) == 'actions/checkout@v7', f'the checkout is {step.get("uses")!r}, expected exactly actions/checkout@v7 (the file pins action majors like its neighbors)')
need(not step.get('with'), 'the checkout step carries a with: block — the fan-out needs no fetch-depth: 0 history; a shallow default clone is the pinned shape (push jobs need history, this one does not)')
need(any(isinstance(s, dict) and s.get('name') == 'diag' for s in steps),
     'no diag step (neighbors carry one; it echoes ROLE for instance-side debugging)')
diag = next(s for s in steps if isinstance(s, dict) and s.get('name') == 'diag')
need('vars.ROLE' in str(diag.get('run', '')) and 'ROLE=' in str(diag.get('run', '')),
     f'diag step does not echo ROLE like its neighbors: {diag.get("run")!r:.120}')
runs = [s.get('run') for s in steps if isinstance(s, dict) and s.get('run')]
need(runs, 'sync-fanout has no run block')
need(all(str(r).lstrip().startswith('set -euo pipefail') for r in runs),
     'a sync-fanout run block does not start with set -euo pipefail (t6 shape, job-local)')
PY
then
  fail "t9: see the t9 detail above"
fi
ok "t9: sync-fanout needs == [push-gh], exact prod guard, lab label, exactly one bare actions/checkout@v7 as its sole uses: step, a ROLE-echoing diag step and set -euo pipefail run heads (C06 AC3)"

# --- t10: forbidden patterns, file-wide (C06 AC2) ---------------------------------
# The reopen1 transport is dead weight in the reopen2 shape: with no inbound
# surface and no HTTP client step there is nothing to sign, no header family
# to send, no payload to build. The set widens per the plan: the shipped
# hub/forge dialect literals plus the entire relay-era tooling (openssl
# signing, curl, the payload builder) and the retired key/job names.
if ! python3 - "$WF" <<'PY'
import sys

raw = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: t10: {msg}', file=sys.stderr)
        sys.exit(1)


for pat, why in (
        ('sha256=', 'an HMAC recipe fragment survives — the fan-out authenticates with per-cluster bearer tokens, there is no signature anywhere (R5)'),
        ('X-Hub-Signature', 'the hub header family survives — headers die with the HTTP transport'),
        ('X-Forgejo-Signature', 'the forgejo header family survives — same'),
        ('X-Forgejo-Event', 'the event-header gate survives — the job knows its own ref, no gate header is needed'),
        ('X-GitHub-', 'a GitHub-shaped header survives — the dual-dialect delivery dies with the relay'),
        ('openssl dgst', 'an openssl signing line survives — the crypto layer is gone (plan: no HMAC, R5)'),
        ('curl', 'a curl invocation survives — the script is a stdlib urllib client; the job runs python3, not curl'),
        ('json.dumps', 'a payload builder survives — no webhook payload exists any more'),
        ('ARGOCD_HOOK', 'a relay-era vault key name survives — the pair is disposed (C07/C08 delete it instance-side)'),
        ('hook-relay', 'the retired job name survives anywhere in the file'),
        ('RELAY_', 'a relay-era env name survives (RELAY_URL/RELAY_SECRET were the trigger wiring)'),
):
    n = raw.count(pat)
    need(n == 0, f'{pat!r} occurs {n} time(s) file-wide, expected zero ({why})')
PY
then
  fail "t10: see the t10 detail above"
fi
ok "t10: zero HMAC/header/crypto/payload/curl/relay-key/hook-relay literals anywhere — the transport layer is fully gone from the file (C06 AC2)"

# --- t11: contract tokens in the job (C06 AC4/AC5) --------------------------------
# The pinned invocation IS the offline contract between C06 and C05's script
# (path, flags, env names). Tokens travel env-only: a --token flag or an
# interpolation of the secret into a run body would land the value in the
# step script file the runner writes ([27][29] doctrine) — t5 counts the one
# ${{ }} wiring; this leg bars the secret from the bodies and argv entirely.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('sync-fanout') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t11: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(job, dict) and job, 'no sync-fanout job (t9 already reddened if C06 is missing; t11 needs it too)')
runs = [str(s.get('run')) for s in (job.get('steps') or []) if isinstance(s, dict) and s.get('run')]
blob = "\n".join(runs)

env_kv = {}
for src in [job.get('env') or {}] + [s.get('env') or {} for s in (job.get('steps') or []) if isinstance(s, dict)]:
    for k, v in src.items():
        env_kv[k] = str(v)
# env map: the secret reaches the job ONLY as an env mapping (never a run
# interpolation), and the context refs are the pinned pair.
need('ARGOCD_SYNC_TOKENS' in env_kv, 'env key ARGOCD_SYNC_TOKENS is not set — the vault secret must arrive via an env: mapping (secrets interpolated into run bodies land in the step script file, [27][29])')
need('secrets.ARGOCD_SYNC_TOKENS' in env_kv.get('ARGOCD_SYNC_TOKENS', ''), f'env ARGOCD_SYNC_TOKENS is {env_kv.get("ARGOCD_SYNC_TOKENS")!r}, expected to reference secrets.ARGOCD_SYNC_TOKENS')
need('github.event.ref' in env_kv.get('EVT_REF', ''), 'EVT_REF is not wired to github.event.ref (push events carry the ref)')
need('github.ref' in env_kv.get('GH_REF', ''), 'GH_REF is not wired to github.ref (the dispatch/workflow fallback, release.yaml:54 precedent)')
# Secrets are env-only: an interpolated ${{ secrets.* }} inside a run body
# lands the literal value in the step script file the runner writes
# ([27][29] doctrine). vars.* interpolation stays legal (the diag neighbors
# echo ROLE that way).
for ln in blob.splitlines():
    if ln.lstrip().startswith('#'):
        continue
    need('${{ secrets' not in ln and 'secrets.' not in ln,
         f'run body line interpolates a secret expression: {ln.strip()[:100]!r} — the vault value comes in through env maps only')

# the invocation: script path + roster + ref flag, byte-pattern per the plan.
m = re.search(r'python3 scripts/argocd-fanout\.py --config scripts/argocd-fanout\.json --ref "\$REF"', blob)
need(bool(m), 'no invocation line matching the pinned contract: python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF" (the flags/path ARE the C05↔C06 interface)')
invocation_lines = [ln for ln in blob.splitlines() if 'argocd-fanout.py' in ln and not ln.strip().startswith('#')]
need(invocation_lines, 'no argocd-fanout.py invocation line found')
for ln in invocation_lines:
    need('ARGOCD_SYNC_TOKENS' not in ln, f'the invocation line references the vault key ({ln.strip()[:100]!r}) — tokens are env-mapped to the STEP, never passed per-call')
    need('--token' not in ln, f'the invocation passes a --token flag — banned by the CLI contract (plan: tokens ONLY from the environment)')

# REF fallback chain: dispatch pushes may carry no event ref (release.yaml:54
# context-quirk precedent) — the chain is pinned exactly.
need(re.search(r'REF="\$\{EVT_REF:-\$\{GH_REF:-refs/heads/main\}\}"', blob),
     'no REF="${EVT_REF:-${GH_REF:-refs/heads/main}}" fallback chain — dispatch/first-push runs must resolve main, not fan out on an empty ref')
PY
then
  fail "t11: see the t11 detail above"
fi
ok 't11: env mapping of the tokens secret + EVT_REF/GH_REF context wiring, no action-expression interpolation inside run bodies, the byte-pinned invocation (path/config/ref, no --token, no per-call key), and the exact REF fallback chain (C06 AC4/AC5)'

# --- t12: posture (C06 AC6, ruled exit refinement) ---------------------------------
# Unset vault => warn (with the org-worded line pinned byte-true so operators
# and the runbook grep it) and exit 0 — the not-yet-filled vault is a designed
# state. The shipped "no exit 1 anywhere" leg DIES with the reopen1 doctrine:
# setup errors are the ruled RED lane, so the guard must not swallow them —
# no written exit 1, no `|| true` / `|| echo` on the python call, and the call
# must not hide in a command substitution.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('sync-fanout') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t12: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(job, dict) and job, 'no sync-fanout job')
runs = [str(s.get('run')) for s in (job.get('steps') or []) if isinstance(s, dict) and s.get('run')]
blob = "\n".join(runs)

need(re.search(r'-z\s*"?\$\{?ARGOCD_SYNC_TOKENS', blob), 'no `-z $ARGOCD_SYNC_TOKENS` unset guard — an unfilled vault must warn and skip, never fail the mirror (R1 warn-not-break)')
WARN = ('::warning::sync-fanout not configured (org-level Actions secret '
        'ARGOCD_SYNC_TOKENS absent) — fan-out skipped, manual sync or the '
        'next push covers it')
need(WARN in blob, f'the unset-skip warning is not the pinned byte-true line (runbook §4/§7 and the operator grep depend on it):\nexpected: {WARN!r}')
need(re.search(r'exit 0\b', blob), 'no exit 0 on the skip path — unset must leave the job green')
need('exit 1' not in blob, 'a written exit 1 appears — the script owns the config-red exit code; the run body must not hand-write failures')
need('|| true' not in blob, 'a `|| true` swallow appears — it would push the ruled config-error class back into the silent lane (DECISIONS 2026-11-23 exit-posture refinement)')
for ln in blob.splitlines():
    if 'argocd-fanout.py' in ln and not ln.strip().startswith('#'):
        need('||' not in ln, f'the python call is guarded on this line ({ln.strip()[:100]!r}) — it must run UN-guarded under set -euo pipefail so config errors reach the job exit code')
        need(not re.search(r'=\$\(.*argocd-fanout\.py', ln), f'the python call sits in a command substitution ({ln.strip()[:100]!r}) — its exit code must reach the step, not be captured and dropped')
PY
then
  fail "t12: see the t12 detail above"
fi
ok "t12: unset-token guard warns with the exact org-worded line and exits 0; no exit 1, no || true, the python call is unguarded and not captured — config errors go red, unset stays green (C06 AC6, ruled posture)"

# --- t13: syntax + cross-artifact compile (C06 AC1) --------------------------------
# bash -n every extracted run block (the shipped leg, kept) plus the two
# artifacts the job calls: the fan-out script compiles and the roster parses.
# The py_compile/json legs are GREEN from C05 onward (they are the wave gate);
# a regression here means C06 wired a path that does not build.
if ! python3 - "$WF" "$FANOUT" "$ROSTER" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
import yaml

wf, fanout, roster = sys.argv[1:4]

jobs = (yaml.safe_load(open(wf)) or {}).get('jobs') or {}
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

if not os.path.isfile(fanout):
    print(f'FAIL: t13: {fanout} absent — the job invokes a script that does not exist (C05 must land first; this leg turns green at C05 and may not regress)', file=sys.stderr)
    sys.exit(1)
rc = subprocess.run([sys.executable, '-m', 'py_compile', fanout], capture_output=True, text=True)
if rc.returncode != 0:
    print(f'FAIL: t13: py_compile rejected {fanout}: {rc.stderr.strip()[:300]}', file=sys.stderr)
    sys.exit(1)
try:
    json.load(open(roster))
except Exception as e:
    print(f'FAIL: t13: the roster {roster} does not parse as JSON: {e}', file=sys.stderr)
    sys.exit(1)
print('ok: t13 — %d run blocks pass bash -n; the fan-out script compiles; the roster parses' % len(runs))
PY
then
  fail "t13: see the t13 detail above"
fi
ok "t13: all run blocks are syntactically valid bash, scripts/argocd-fanout.py py_compiles, and the roster JSON parses (C06 AC1 + cross-artifact gate)"

printf 'PASS: forgejo-main-sync checks (%d ok)\n' "$checks"
