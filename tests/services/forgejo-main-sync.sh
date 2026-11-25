#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/main-sync.yaml: the static
# invariants that keep the main-sync design safe — the prod-stage guard on
# every job (the repo is hosted on two instances; only the prod one may fan
# main out, and the dev stage firing no job is what stops a push ping-pong),
# plain non-force pushes, destinations and credentials drawn from instance
# vars/secrets rather than file literals, fail-fast run semantics, lab runner
# labels, push-dev being a bare main push with no merge — and from cf-139
# reopen3 (C10, ruling R7) the `sync-fanout` job: the mirror workflow IS
# the webhook and speaks to the clusters DIRECTLY. t9..t13 pin its shape:
# needs [push-gh] (firing only after GitHub advanced is the race resolution,
# R1 option (c) — SURVIVES byte-true), a bare actions/checkout@v7 step (the
# fan-out logic home is scripts/argocd-fanout.py riding the checkout, no
# history needed), and the R7 INPUT flip: the single-blob
# secrets.ARGOCD_SYNC_TOKENS + the shell -z unset-guard DIE — the env block
# now enumerates 22 org key PAIRS (vars.ARGOCD_SYNC_<CAT>_URL +
# secrets.ARGOCD_SYNC_<CAT>_TOKEN, alphabetical by category, URL-then-TOKEN,
# EVT_REF/GH_REF last; static enumeration is the discovery surface because
# Forgejo cannot index secrets dynamically [21][25]), while the all-absent
# warn-green and pair-integrity RED lanes move INTO the script (C09). t5
# pins the pair matrix + placement bans (tokens are secrets, URLs are vars;
# repo twins would silently WIN); t10 bans the dead blob name and grammar
# file-wide; t12 bans the resurrected shell guard. The file still carries
# zero secret VALUES; hosts live instance-side, the script discovers its
# fleet from the env it is handed.
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
# C10 re-pin (reopen3, R7): the vault block flips from the single blob to the
# 22 enumerated org key PAIRS. Placement law: tokens are SECRETS, URLs are
# VARS (a swapped placement would mask a URL or leak wiring intent); the
# enumeration order is alphabetical by category, URL-then-TOKEN per pair,
# EVT_REF/GH_REF last (proxy-BACKUP sorts before proxy-LOCAL — a deliberate
# sort-order fact); the dead blob name appears NOWHERE. Org-scope ruling
# survives and now covers BOTH kinds; the reference form stays scope-blind
# (repo→org→user with repo winning [21][27]), so the header sentence is the
# only place the placement can live — and the repo-twin warning must name
# both kinds, because a repo key of either WINS silently.
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

# --- the R7 pair matrix (pinned order, DECISIONS micro-call g) ---------------
CATS = ['dev', 'gpu', 'gpu-ai', 'grow', 'home', 'infra', 'media',
         'monitoring', 'proxy-backup', 'proxy-local', 'proxy-remote']
job = jobs.get('sync-fanout') or {}
env_kv = {}
env_order = []
for src in [job.get('env') or {}] + [s.get('env') or {} for s in (job.get('steps') or [])
                                     if isinstance(s, dict)]:
    for k, v in src.items():
        if k not in env_kv:
            env_order.append(k)
        env_kv[k] = str(v)

for cat in CATS:
    u = cat.upper().replace('-', '_')
    vk, sk = 'ARGOCD_SYNC_%s_URL' % u, 'ARGOCD_SYNC_%s_TOKEN' % u
    n = expr_count('vars.' + vk)
    need(n == 1, f'vars.{vk} is wired (${{{{ ... }}}} line) {n} times, expected exactly once — the 22-row enumeration is the discovery surface (static, no matrix expressions [21][25])')
    need(vk in env_kv and 'vars.' + vk in env_kv[vk], f'env key {vk} does not map vars.{vk} — the env NAME the script discovers must equal the org key name')
    n = expr_count('secrets.' + sk)
    need(n == 1, f'secrets.{sk} is wired {n} times, expected exactly once')
    need(sk in env_kv and 'secrets.' + sk in env_kv[sk], f'env key {sk} does not map secrets.{sk}')
    dump = yaml.dump(job or {})
    need(vk in dump and sk in dump, f'{vk}/{sk} not under sync-fanout')

# Placement bans: a token wired as a var or a URL wired as a secret breaks
# the pair law (a vars.TOKEN row would surface the secret value as a
# plain-variable UI field).
swapped = re.findall(r'vars\.ARGOCD_SYNC_[A-Z0-9_]+_TOKEN(?![0-9A-Za-z_])', raw)
need(not swapped, f'token keys wired as VARS ({swapped}) — TOKENs are org SECRETS')
swapped = re.findall(r'secrets\.ARGOCD_SYNC_[A-Z0-9_]+_URL(?![0-9A-Za-z_])', raw)
need(not swapped, f'URL keys wired as SECRETS ({swapped}) — URLs are org VARS (route truth stays review-visible)')

# The dead blob is gone file-wide (count catches every form, expressions and
# comments alike).
need(count('ARGOCD_SYNC_TOKENS') == 0, 'ARGOCD_SYNC_TOKENS still appears — the reopen2 single-blob secret is dead input (R7); zero occurrences file-wide')
for key in ('vars.ARGOCD_HOOK_URL', 'secrets.ARGOCD_HOOK_SECRET'):
    need(count(key) == 0, f'{key} still appears — the relay-era vault pair stays disposed')

# Exact env inventory + pinned ORDER (pair interleave, EVT/GH last).
want_order = []
for cat in CATS:
    u = cat.upper().replace('-', '_')
    want_order += ['ARGOCD_SYNC_%s_URL' % u, 'ARGOCD_SYNC_%s_TOKEN' % u]
want_order += ['EVT_REF', 'GH_REF']
need(env_order == want_order,
     f'env keys are {env_order}, expected the 22 pair rows alphabetical by category (proxy-backup before proxy-local), URL then TOKEN per pair, EVT_REF/GH_REF last (C10 pinned order; a shuffled block fails the eye-tick review)')

# No repo destination URL literal; the bare https:// scheme is the only
# allowed fragment of a URL in the file. (The org-side host VALUES are
# instance data; the roster JSON is outside this sweep's file.)
for host in ('github.com/', 'git.scifi.farm/'):
    need(host not in raw, f'repo URL literal {host} is in the file (destinations are instance-side vars)')
need('forgejo.server_url' not in raw, 'forgejo.server_url is in the file')
reserved = re.findall(r'(?:secrets|vars)\.((?:GITHUB|FORGEJO)[A-Za-z0-9_]*)', raw)
need(not reserved, f'reserved-prefix key reference(s): {", ".join(reserved)}')
for tok in ('FORGEJO_TOKEN', 'GITHUB_TOKEN'):
    need(tok not in raw, f'the automatic token {tok} is referenced in the file')

# Header-comment placement sentences (R7 shape): org scope for BOTH kinds,
# the static-enumeration cost sentence, and NO leftover claim of a single
# secret or the dead newline grammar.
header = []
for ln in raw.splitlines():
    if ln.strip().startswith('on:'):
        break
    if ln.lstrip().startswith('#'):
        header.append(ln)
hb = "\n".join(header)
need('ARGOCD_SYNC' in hb, 'the header comment never names the ARGOCD_SYNC_* key family — the placement sentence is its only home (the file cannot prove scope)')
# Prose wraps across comment lines, so the claims are matched against the
# UNWRAPPED flow of the header block (join the # lines into one text).
hbflow = " ".join(ln.lstrip("#").strip() for ln in header)
need(re.search(r"(?i)\borg\b", hbflow) and re.search(r"(?i)vars", hbflow) and re.search(r"(?i)secrets", hbflow),
     'the header does not name ORG placement for BOTH vars and secrets (repo twins of either kind win silently — single-instance hygiene is the whole placement story)')
need(re.search(r"(?i)static", hbflow), 'the header lacks the static-enumeration cost sentence (fleet add/remove = org keys + these rows, same release — the R7 named cost)')
for claim in (r'(?i)repo[- /]?(level|scoped)[^.]{0,40}(actions )?(vars?|secrets?)',
              r'(?i)single[^.]{0,40}(secret|vault|credential)',
              r'(?i)newline|cat:token'):
    need(not re.search(claim, hbflow), f'the header carries a stale-placement or dead-grammar claim ({claim!r}) — R7: per-cluster PAIRS, org placement, not one blob and not repo-side')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: PUSH_* keys exactly once under their jobs; the 22-row ARGOCD_SYNC pair matrix wired once each under sync-fanout in the pinned order (URL-then-TOKEN alphabetical, EVT_REF/GH_REF last); tokens-are-secrets/URLs-are-vars placement; zero ARGOCD_SYNC_TOKENS/ARGOCD_HOOK_* occurrences; header names ORG placement for both kinds + static enumeration cost, no single-secret or newline claim"

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
        ('ARGOCD_SYNC_TOKENS', 'the reopen2 single-blob key name survives — R7 replaces it with the 22 enumerated PAIRS; the dead name must not resurrect in code, comments or guards (C10 AC2)'),
        ('cat:token', 'the dead newline blob grammar lingers in the comments — the record form died with the blob (DECISIONS 2026-11-25 consequence 4)'),
):
    n = raw.count(pat)
    need(n == 0, f'{pat!r} occurs {n} time(s) file-wide, expected zero ({why})')
PY
then
  fail "t10: see the t10 detail above"
fi
ok "t10: zero HMAC/header/crypto/payload/curl/relay-key/hook-relay literals AND the dead ARGOCD_SYNC_TOKENS / cat:token blob shapes anywhere — transport AND superseded input grammar stay gone (C10 AC2)"

# --- t11: contract tokens in the job (C10 AC4) ------------------------------------
# The pinned invocation IS the offline contract between C10 and C09's script
# (path, flags, roster). The env block's INVENTORY (set equality against the
# 22 pair names + EVT_REF/GH_REF) lands here; t5 pins the per-key wiring and
# order. Values travel env-only: a run-body interpolation would land them in
# the step script file the runner writes ([27][29] doctrine). vars.ROLE in
# the diag body is the one surviving interpolation (the pinned t9 job shape
# carries it); every other vars.*/any secrets. inside a body reddens.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('sync-fanout') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t11: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(job, dict) and job, 'no sync-fanout job (t3/t9 already reddened if absent; t11 needs it too)')
runs = [str(s.get('run')) for s in (job.get('steps') or []) if isinstance(s, dict) and s.get('run')]
blob = "\n".join(runs)

env_kv = {}
for src in [job.get('env') or {}] + [s.get('env') or {} for s in (job.get('steps') or []) if isinstance(s, dict)]:
    for k, v in src.items():
        env_kv[k] = str(v)

# Env inventory: EXACTLY the 22 pair names + EVT_REF + GH_REF — a stale
# blob row, a hand-added thirteenth category or a dropped pair all redden.
CATS = ['dev', 'gpu', 'gpu-ai', 'grow', 'home', 'infra', 'media',
         'monitoring', 'proxy-backup', 'proxy-local', 'proxy-remote']
want = set()
for cat in CATS:
    u = cat.upper().replace('-', '_')
    want |= {'ARGOCD_SYNC_%s_URL' % u, 'ARGOCD_SYNC_%s_TOKEN' % u}
want |= {'EVT_REF', 'GH_REF'}
need(set(env_kv) == want,
     f'env keys are {sorted(env_kv)}, expected EXACTLY the 22 canonical pair names + EVT_REF/GH_REF (C10 AC2: no other ARGOCD_SYNC_* reference, no stragglers)')

# Context wiring (the pair rows' wiring is t5's; the ref fields survive here).
need('github.event.ref' in env_kv.get('EVT_REF', ''), 'EVT_REF is not wired to github.event.ref (push events carry the ref)')
need('github.ref' in env_kv.get('GH_REF', ''), 'GH_REF is not wired to github.ref (the dispatch/workflow fallback, release.yaml:54 precedent)')

# Run-body interpolation ban: no secrets at all, no vars beyond the diag
# ROLE echo the job-shape leg pins.
for ln in blob.splitlines():
    if ln.lstrip().startswith('#'):
        continue
    if 'secrets.' in ln:
        need(False, f'run body line references a secret: {ln.strip()[:100]!r} — vault values come in through env maps only ([27][29])')
    badvar = re.search(r'vars\.(?!ROLE(?![0-9A-Za-z_]))([A-Za-z0-9_]+)', ln)
    if badvar:
        need(False, f'run body line interpolates vars.{badvar.group(1)}: {ln.strip()[:100]!r} — only the diag ROLE echo may read vars in-body; pair keys are env-mapped')

# The invocation: script path + roster + ref flag, byte-pattern per the plan
# (UNCHANGED by R7 — C10 AC4 "run block unchanged otherwise").
m = re.search(r'python3 scripts/argocd-fanout\.py --config scripts/argocd-fanout\.json --ref "\$REF"', blob)
need(bool(m), 'no invocation line matching the pinned contract: python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF" (the flags/path ARE the C09↔C10 interface)')
invocation_lines = [ln for ln in blob.splitlines() if 'argocd-fanout.py' in ln and not ln.strip().startswith('#')]
need(invocation_lines, 'no argocd-fanout.py invocation line found')
for ln in invocation_lines:
    need('ARGOCD_SYNC' not in ln, f'the invocation line references a vault key ({ln.strip()[:100]!r}) — pairs are env-mapped to the STEP, never passed per-call')
    need('--token' not in ln, f'the invocation passes a --token flag — banned by the CLI contract (tokens ONLY from the environment)')

# REF fallback chain: dispatch pushes may carry no event ref (release.yaml:54
# context-quirk precedent) — the chain is pinned exactly.
need(re.search(r'REF="\$\{EVT_REF:-\$\{GH_REF:-refs/heads/main\}\}"', blob),
     'no REF="${EVT_REF:-${GH_REF:-refs/heads/main}}" fallback chain — dispatch/first-push runs must resolve main, not fan out on an empty ref')
PY
then
  fail "t11: see the t11 detail above"
fi
ok 't11: env keys are EXACTLY the 22 pair names + EVT_REF/GH_REF, context wiring pinned, no secret/vars interpolation in run bodies (diag ROLE excepted by the t9 shape), the byte-pinned invocation, and the exact REF fallback chain (C10 AC4)'

# --- t12: posture (C10 AC3, posture moved into the script) -------------------------
# R7 kills the shell-side unset guard: the all-absent warn-green lane and the
# pair-integrity RED lane both live in C09's script (the 22-way emptiness
# test in YAML was the rejected shape). This leg bans the resurrected guard
# file-wide and keeps the propagation pins: the python call runs UN-guarded
# so the script-owned lanes actually reach the job exit code. The warn-green
# behavior itself is pinned cross-suite by behavior.sh t5's kill-lane arms
# (offline suites stay file-local — this is the cross-reference note).
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('sync-fanout') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t12: {msg}', file=sys.stderr)
        sys.exit(1)


raw = open(sys.argv[1]).read()
need(isinstance(job, dict) and job, 'no sync-fanout job')
runs = [str(s.get('run')) for s in (job.get('steps') or []) if isinstance(s, dict) and s.get('run')]
blob = "\n".join(runs)

# The guard is DEAD: no -z/-n test on any ARGOCD_SYNC name anywhere in the
# file, and no resurrection of the skip-warning wording (that string now
# lives ONLY in the script, pinned by behavior.sh t5).
need(not re.search(r'-[zn]\s+"?\$\{?ARGOCD_SYNC', raw),
     'a shell emptiness test on an ARGOCD_SYNC_* name survives — R7 moved the unset lane into the script (the column-0 warning is C09\'s; a YAML guard would diverge from the token-side predicate)')
need('sync-fanout not configured' not in raw,
     'the skip-warning string still lives in the workflow — the warning must come from the script\'s stdout (behavior.sh pins its exact bytes), not from a shell echo that cannot see 22 keys')

# Propagation pins (survive byte-true): the call is un-guarded, uncaptured,
# and nothing hand-writes failure or swallow paths in the job bodies.
need('exit 1' not in blob, 'a written exit 1 appears — the script owns the config-red exit code; the run body must not hand-write failures')
need('|| true' not in blob, 'a `|| true` swallow appears — it would push the pair-integrity RED class back into the silent lane (DECISIONS exit-posture refinement, unchanged by R7)')
for ln in blob.splitlines():
    if 'argocd-fanout.py' in ln and not ln.strip().startswith('#'):
        need('||' not in ln, f'the python call is guarded on this line ({ln.strip()[:100]!r}) — it must run UN-guarded under set -euo pipefail so the script-owned RED lanes reach the job exit code')
        need(not re.search(r'=\$\(.*argocd-fanout\.py', ln), f'the python call sits in a command substitution ({ln.strip()[:100]!r}) — its exit code must reach the step, not be captured and dropped')
PY
then
  fail "t12: see the t12 detail above"
fi
ok "t12: no -z guard / no skip-warning echo on ARGOCD_SYNC names anywhere (the script owns both lanes), no exit 1, no || true, the python call unguarded and uncaptured — config RED propagates, warn-green comes from C09 stdout (C10 AC3)"

# --- t13: syntax + cross-artifact compile (C10 AC1) --------------------------------
# bash -n every extracted run block (the shipped leg, kept) plus the two
# artifacts the job calls: the fan-out script compiles and the roster parses
# to the FIVE globals. The py_compile leg rides green from C05 onward; the
# schema leg is designed-red until C09 lands (the shipped roster still
# carries targets[]); a regression here means C10 wired a path that breaks.
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
    roster_doc = json.load(open(roster))
except Exception as e:
    print(f'FAIL: t13: the roster {roster} does not parse as JSON: {e}', file=sys.stderr)
    sys.exit(1)
# C10 upgrade: the ROSTER SHAPE is part of the job's contract — the script
# demands EXACTLY the five globals (targets[] died with R7; a roster still
# carrying it is RED at runtime, so the compile leg must not green-light it).
if set(roster_doc) != {"allowed_refs", "tracked_repo", "settle_seconds",
                       "target_timeout_seconds", "parallel_workers"}:
    print(f'FAIL: t13: roster keys are {sorted(roster_doc)}, expected exactly the five R7 globals (targets[] must be deleted — C09)', file=sys.stderr)
    sys.exit(1)
print('ok: t13 — %d run blocks pass bash -n; the fan-out script compiles; the roster is the five-globals JSON' % len(runs))
PY
then
  fail "t13: see the t13 detail above"
fi
ok "t13: all run blocks pass bash -n, scripts/argocd-fanout.py py_compiles, and the roster parses to exactly the five R7 globals (C10 AC1 + cross-artifact gate)"

printf 'PASS: forgejo-main-sync checks (%d ok)\n' "$checks"
