#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/main-sync.yaml: the static
# invariants that keep the main-sync design safe — the prod-stage guard on
# every job (the repo is hosted on two instances; only the prod one may fan
# main out, and the dev stage firing no job is what stops a push ping-pong),
# plain non-force pushes, destinations and credentials drawn from instance
# vars/secrets rather than file literals, fail-fast run semantics, lab runner
# labels, push-dev being a bare main push with no merge — and from cf-139
# reopen4 (C13, ruling R8) the `sync-fanout` job: the mirror workflow IS the
# webhook and speaks to the clusters DIRECTLY, FLEET-BLIND.
#
# Post-rebase (cf-55/cf-56 shapes on origin/main, D59 + D4 owner rulings):
# the file carries SEVEN jobs — push-gh, push-dev, the called builders
# build-containers + build-charts + push-coder-templates, the aggregate
# advance-marker, and sync-fanout. The fan-out's needs are
# [push-gh, build-containers, build-charts]: build-charts pushes a bump
# commit to Forgejo main, so a fan-out firing before the builders would
# push-gh-advance GitHub with the PRE-bump tree and sync the fleet to a
# stale SHA — the R1(c) race resolution now covers the builder group (D59).
# push-coder-templates is deliberately NOT in sync-fanout's needs (D4): a
# red coder leg blocks the marker aggregate but must not hold the fleet
# release, since the fleet does not depend on an external-service publish;
# the coder leg IS in advance-marker's needs (the marker only moves on a
# fully-green fan). The cf-56 fold also re-aims EVT_REF at the native
# `${{ forgejo.event.ref }}` context (GH_REF keeps github.ref for
# GitHub-compat, with a comment) — that pin is a designed-red carrier
# until the dev session lands the fold.
# A deploy incident added t14: act passes unresolved called-workflow
# outputs through as literal expression text, so the marker's
# `TARGET=${{ needs.build-charts.outputs.bump_sha }}` died 'bad
# substitution' on a no-bump fan. The advance-marker block must carry the
# consumer sanitizer (quoted RAW capture, empty-or-literal case fallback
# to $GITHUB_SHA, 40-hex win, loud exit on resolved garbage) — pinned
# statically AND proven by running the landed decision block under four
# stubbed inputs.
#
# The C10 22-row env enumeration DIES with R8: its premise (Forgejo cannot
# index secrets dynamically) was source-refuted (DECISIONS 2026-11-26, RESEARCH
# round 3 [43][44][46][49]). The job shape survives — diag → bare
# actions/checkout@v7 → NEW `resolve fan-out pairs` filter step → `fan out
# ArgoCD syncs` — and the enumeration pins are replaced by:
#   * the two blob expressions `${{ toJSON(secrets) }}` / `${{ toJSON(vars) }}`
#     exactly once each, ONLY in the filter step's env (plan "Fan-out INPUT
#     contract"); the naive shape (blob into the checkout-running fan-out
#     step's env) is banned — RESEARCH Agenda 4's 22-value env floor is the
#     invariant the filter step exists to keep;
#   * the filter contract itself: dumb serializer (DECISIONS (a)) — pair-regex
#     union select, $RUNNER_TEMP/pairs.json flat {NAME: value}, chmod 0600,
#     print of the count line ONLY;
#   * fleet-blind bans: zero ARGOCD_SYNC_<SEG>_(URL|TOKEN) name strings (a
#     resurrected row is structurally impossible), zero indexed refs
#     (secrets./vars. ARGOCD twins, secrets[, vars[), zero fleet counts.
# The script's C14 channel reads what the filter writes; until C14 lands the
# script env-scans and a CI run warn-greens inert — never wrong (C13 "Consumes").
# The file still carries zero secret VALUES; hosts live instance-side.
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

# Leg selector (behavior.sh convention): default is the full suite; named
# legs re-run in isolation (the C13 designed-red map and the mutation
# battery address legs one at a time).
declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 14); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[0-4])$ ]] || fail "unknown test id '$a' (expected t1..t14)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: shape --------------------------------------------------------------
if want t1; then
[ -f "$WF" ] || fail "t1: $WF does not exist"
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$WF" \
  || fail "t1: $WF does not parse as YAML"
ok "t1: $WF exists and parses as YAML"
fi

# --- t2: trigger -------------------------------------------------------------
if want t2; then
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
fi

# --- t3: jobs + prod-stage guards --------------------------------------------
if want t3; then
# The job SET is exactly {push-gh, push-dev, build-containers, build-charts,
# push-coder-templates, advance-marker, sync-fanout} (C06 rename + cf-55's
# called-builder fan + cf-56's coder-template member, D59/D4) — every one
# guarded on the byte-exact membership form; the fan-out or a builder
# firing on a dev instance would act for a push the mirror never made.
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
need(set(jobs) == {'push-gh', 'push-dev', 'build-containers', 'build-charts',
                   'push-coder-templates', 'advance-marker', 'sync-fanout'},
     f"jobs keys are {sorted(jobs)}, expected exactly the seven-job fan (push-gh + push-dev + the called builders + the cf-56 coder-template member + advance-marker + sync-fanout; the C06 relay replacement, the cf-55 D59 builder group and cf-56 D4 are the landed set)")
need('hook-relay' not in raw,
     'the retired hook-relay name survives in the file — the job is renamed to sync-fanout (C06), no relay-era identifier may linger')
for name in ('push-gh', 'push-dev', 'build-containers', 'build-charts',
             'push-coder-templates', 'advance-marker', 'sync-fanout'):
    need((jobs[name] or {}).get('if') == GUARD,
         f"{name}.if is {(jobs[name] or {}).get('if')!r}, expected {GUARD!r} (byte-exact membership on EVERY job of the fan; ${{ }}-wrapped or equality forms redden this leg)")
# The dev-stage server must fire no job; any dev guard defeats the breaker.
need("vars.ROLE == 'dev'" not in raw, 'a job guards on vars.ROLE == dev (the dev stage must fire nothing)')
# URL-based instance detection is retired.
need('forgejo.server_url' not in raw, 'forgejo.server_url is referenced (URL detection is retired)')
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: exactly seven jobs (push-gh, push-dev, build-containers, build-charts, push-coder-templates, advance-marker, sync-fanout), no hook-relay residue, every one guarded on the byte-exact contains(vars.ROLE, 'prod'); no dev guard, no server_url"
fi

# --- t4: no force --------------------------------------------------------------
if want t4; then
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
fi

# --- t5: destinations, blobs, fleet-blindness, header (C13 AC2/AC3/AC4/AC7) -----
if want t5; then
# C13 re-pin (reopen4, R8): the 22-row pair matrix and its placement bans DIE
# with the enumeration. What replaces them: the PUSH_* legs survive unchanged
# (the mirror jobs are byte-untouched); the two toJSON blob expressions appear
# EXACTLY once each and only in the filter step's env; the pairs wiring
# (RUNNER_TEMP file → ARGOCD_PAIRS_FILE) is exact-once; the file is
# FLEET-BLIND (no pair-name strings, no indexed refs, no fleet counts); the
# header retires the enumeration claims and carries the source-corrected
# precedence sentence (vars: repo > org/user > global [45]; secrets:
# repo > owner [44]) — both moot under the no-repo-twin rule, and the header
# says so.
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

job = jobs.get('sync-fanout') or {}
steps = [s for s in (job.get('steps') or []) if isinstance(s, dict)]
filt = [s for s in steps if s.get('name') == 'resolve fan-out pairs']
fan = [s for s in steps if s.get('name') == 'fan out ArgoCD syncs']
need(len(filt) == 1, f'{len(filt)} steps named "resolve fan-out pairs" — the filter step is the blobs\' sole home (C13 AC3)')
need(len(fan) == 1, f'{len(fan)} steps named "fan out ArgoCD syncs" — the fan-out step must exist under its pinned name (C13 AC6)')


def env_of(step):
    return {k: str(v) for k, v in ((step.get('env') or {}) if isinstance(step.get('env'), dict) else {}).items()}


def norm(s):
    return re.sub(r'\s+', '', s)


# --- the R8 blob pair (plan "Fan-out INPUT contract") --------------------------
for token, env_name in (('toJSON(secrets)', 'SECRETS_JSON'), ('toJSON(vars)', 'VARS_JSON')):
    n = raw.count(token)
    need(n == 1, f'{token} appears {n} time(s), expected EXACTLY once (the second blob context reference is a second serialization surface)')
fe = env_of(filt[0])
need('SECRETS_JSON' in fe and norm(fe['SECRETS_JSON']) == '${{toJSON(secrets)}}',
     f'the filter step env must map SECRETS_JSON to ${{{{ toJSON(secrets) }}}} exactly, got {fe.get("SECRETS_JSON")!r} (C13 AC3)')
need('VARS_JSON' in fe and norm(fe['VARS_JSON']) == '${{toJSON(vars)}}',
     f'the filter step env must map VARS_JSON to ${{{{ toJSON(vars) }}}} exactly, got {fe.get("VARS_JSON")!r} (C13 AC3)')
ve = env_of(fan[0])
need(not ({'SECRETS_JSON', 'VARS_JSON'} & set(ve)),
     f'blob env names reach the fan-out step ({sorted(set(ve) & {"SECRETS_JSON", "VARS_JSON"})}) — the naive shape hands the checkout-running process the whole vault; the filter step is what keeps its env at the pair floor (RESEARCH Agenda 4)')
need(not ({'SECRETS_JSON', 'VARS_JSON'} & set(env_of(job) if isinstance(job.get('env'), dict) else {})),
     'blob env names sit at job level — step-scoped only, or every step inherits the blobs')

# --- pairs wiring (AC4) ---------------------------------------------------------
n = expr_count('runner.temp')
need(n == 1, f'runner.temp is wired {n} times, expected exactly once (the fan-out step env — C13 AC4)')
need('ARGOCD_PAIRS_FILE' in ve and norm(ve.get('ARGOCD_PAIRS_FILE', '')) == '${{runner.temp}}/pairs.json',
     f'the fan-out step env must map ARGOCD_PAIRS_FILE to ${{{{ runner.temp }}}}/pairs.json, got {ve.get("ARGOCD_PAIRS_FILE")!r} — same file the filter writes, via the context name (runner.temp ↔ RUNNER_TEMP [40][51])')
need(count('ARGOCD_PAIRS_FILE') == 1,
     f'ARGOCD_PAIRS_FILE occurs {count("ARGOCD_PAIRS_FILE")} times, expected exactly once (the fan-out step env)')
fbody = str(filt[0].get('run', ''))
need('RUNNER_TEMP' in fbody and 'pairs.json' in fbody,
     'the filter block does not write $RUNNER_TEMP/pairs.json — the fan-out env would point at a file nothing creates')

# --- FLEET-BLIND (AC2): the enumeration cannot resurrect ------------------------
revived = re.findall(r'ARGOCD_SYNC_[A-Z0-9_]+_(?:URL|TOKEN)(?![0-9A-Za-z_])', raw)
need(not revived,
     f'enumeration-era pair name(s) resurrected: {sorted(set(revived))} — the job must know ZERO fleet members (R8; the filter regex literal with ( ) is not a name)')
idx = re.findall(r'(?:secrets|vars)\.ARGOCD(?![0-9A-Za-z_])', raw)
need(not idx, f'indexed ARGOCD context reference(s) {sorted(set(idx))} — the design serializes the whole map instead (toJSON blobs); a pair reference would re-enumerate it')
brack = re.findall(r'\b(?:secrets|vars)\[', raw)
need(not brack, f'dynamic-index expression(s) {sorted(set(brack))} survive — retired premise [21][25] resurrection')
counts = re.findall(r'(?<![-0-9.])(?:11|22)(?![-0-9.])', raw)
need(not counts,
     f'fleet-count claim(s) {sorted(set(counts))} in the file — a fleet-blind job states no member counts (dates like 2026-11-23 are exempt)')

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

# Header-comment sentences (C13 AC7): fleet-blind + org placement + the
# source-corrected precedence claim; the enumeration-era claims retired.
header = []
for ln in raw.splitlines():
    if ln.strip().startswith('on:'):
        break
    if ln.lstrip().startswith('#'):
        header.append(ln)
need(header, 'no header comment block above on: — the placement doctrine has no other home (the file cannot prove scope)')
# Prose wraps across comment lines, so the claims are matched against the
# UNWRAPPED flow of the header block (join the # lines into one text).
hbflow = " ".join(ln.lstrip("#").strip() for ln in header)
need(re.search(r'ARGOCD_SYNC_<[A-Za-z]+>_(?:URL|TOKEN)', hbflow),
     'the header never names the ARGOCD_SYNC_<CATEGORY>_* key FAMILY (the <CAT> placeholder form; a real category name is banned by fleet-blindness) — the org placement sentence is its only home')
need(re.search(r"(?i)\borg\b", hbflow) and re.search(r"(?i)vars", hbflow) and re.search(r"(?i)secrets", hbflow),
     'the header does not name ORG placement for BOTH vars and secrets (repo twins of either kind win silently — single-instance hygiene is the whole placement story)')
need(re.search(r"(?i)fleet[- ]blind", hbflow),
     'the header lacks the fleet-blind sentence (C13 AC7: the values surface is the org key pairs, the job carries none — DECISIONS 2026-11-26 R8)')
need(re.search(r"(?i)vars\D{0,80}repo\s*>\s*org\s*/\s*user\s*>\s*global", hbflow),
     'the header lacks the source-corrected VARS precedence (repo > org/user > global [45]) — the GetVariablesOfRun fix queued from RESEARCH round 3 rides C13 (AC7)')
need(re.search(r"(?i)secrets\D{0,80}repo\s*>\s*owner", hbflow),
     'the header lacks the source-corrected SECRETS precedence (repo > owner [44]) (AC7)')
need(re.search(r"(?i)moot", hbflow),
     'the header does not say the precedence split is moot under the no-repo-twin rule (C13: say so — the ordering claim must not invite repo twins)')
need(re.search(r"(?i)values\s+never\s+reach[^.]{0,80}argv", hbflow) and re.search(r"(?i)run bod", hbflow),
     'the run-body/argv values doctrine is gone — it survives R8 and now covers the blob: the step-1 blob lives in its env, never in its body (C13 AC7)')
for claim, why in (
        (r'(?i)static\s+enumerat', 'the static-enumeration claim survives — R8 deletes it with the rows (the filter IS the discovery surface)'),
        (r'(?i)cannot\s+index', 'the refuted [21][25] indexing-premise claim survives — source-refuted [43][44][46][49], DECISIONS 2026-11-26'),
        (r'(?i)\blockstep\b', 'the decommission-lockstep claim survives — fleet ops are vault-only now (no rows to sync)'),
        (r'(?i)two\s+rows', 'the pair-of-rows edit cost is still claimed — a fleet change is org-key work, zero workflow edits'),
        (r'(?i)static\s+rows', 'static-rows wording survives (same reason as static enumeration)'),
        (r'(?i)endpoint\s+list', 'an endpoint-list claim survives (the R7 wording: the enumeration WAS the endpoint list; the file now lists none)'),
        (r'repo\s*(?:→|->)\s*org', 'the stale repo→org arrow-chain precedence claim survives — replace with the source-corrected > chain (vars [45], secrets [44])'),
):
    need(not re.search(claim, raw), f'the file carries a retired enumeration-era claim ({why})')
for claim in (r'(?i)repo[- /]?(level|scoped)[^.]{0,40}(actions )?(vars?|secrets?)',
              r'(?i)single[^.]{0,40}(secret|vault|credential)',
              r'(?i)newline|cat:token'):
    need(not re.search(claim, hbflow), f'the header carries a stale-placement or dead-grammar claim ({claim!r}) — per-cluster PAIRS, org placement, not one blob and not repo-side (R7 stands; R8 only changes delivery)')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: PUSH_* keys exactly once under their jobs; the two toJSON blobs once each and ONLY in the filter step env; pairs.json wiring (RUNNER_TEMP write + exact-once runner.temp→ARGOCD_PAIRS_FILE); fleet-blind sweeps (no pair names, no indexed refs, no fleet counts); header fleet-blind + corrected precedence (moot note) + values-never-reach doctrine, all enumeration-era claims retired (C13 AC2/AC3/AC4/AC7)"
fi

# --- t6: failure semantics (every run block in both jobs) -----------------------
if want t6; then
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
fi

# --- t7: runner labels ------------------------------------------------------------
if want t7; then
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
fi

# --- t8: push-dev hygiene -----------------------------------------------------------
if want t8; then
if ! python3 - "$WF" <<'PY'
import sys, yaml

raw = open(sys.argv[1]).read()
if 'backup-proxy' in raw:
    print('FAIL: t8: backup-proxy appears in the workflow (retired from the active design)', file=sys.stderr)
    sys.exit(1)
# 'git merge' (the command) stays banned file-wide; 'git merge-base' is the
# advance-marker's legitimate ancestry probe (C14 ancestor tolerance).
if 'git merge' in raw.replace('git merge-base', 'ANCESTRY-PROBE'):
    print('FAIL: t8: a git merge command appears in the workflow (push-dev must be a plain push; only merge-base ancestry probes are legitimate)', file=sys.stderr)
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
fi

# --- t9: sync-fanout job shape (C13 AC6; D59+D4 race resolution) --------------------
if want t9; then
# The four-step pinned sequence: diag → bare checkout → resolve fan-out pairs
# → fan out ArgoCD syncs. needs == [push-gh, build-containers, build-charts]
# EXACT (D59 owner ruling; cf-56's D4 keeps push-coder-templates OUT of the
# fan-out's needs BY OWNER DESIGN — the landed job comment says why: a red
# coder leg blocks the aggregate marker but must not hold the fleet release,
# because the fleet does not depend on an external-service publish; the
# bump-sha endpoint rule needs no coder commit — it mints none). The
# advance-marker needs the FULL builder trio: the marker moves only once
# every called leg of the fan published green (aggregate rule).
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
need(job.get('needs') == ['push-gh', 'build-containers', 'build-charts'],
     f'needs is {job.get("needs")!r}, expected exactly the list ["push-gh", "build-containers", "build-charts"] — D59: GitHub must carry the POST-bump tree before any cluster is dialed (apps track GitHub); D4: push-coder-templates stays OUT (the fleet does not hold over an external-service publish), and a shuffled list re-opens the pre-bump race')
need(jobs.get('advance-marker', {}).get('needs') == ['build-containers', 'build-charts', 'push-coder-templates'],
     f"advance-marker needs is {jobs.get('advance-marker', {}).get('needs')!r}, expected [build-containers, build-charts, push-coder-templates] — the marker moves only once the WHOLE fan's called legs published green (the cf-56 D4 aggregate rule)")
for bname, target in (('build-containers', 'build-containers.yaml'),
                      ('build-charts', 'build-charts.yaml'),
                      ('push-coder-templates', 'coder-template-push.yaml')):
    bjob = jobs.get(bname) or {}
    use = str(bjob.get('uses', ''))
    need(use.startswith('./.forgejo/workflows/') and use.endswith(target),
         f'the {bname} job is not a called-workflow ref to ./.forgejo/workflows/{target} ({use!r}) — the fan CALLS the standalone builders (cf-55/cf-56), it must not inline their logic')
need(job.get('if') == GUARD, f'if is {job.get("if")!r}, expected {GUARD!r} exact bytes')
need(job.get('runs-on') in LABELS, f'runs-on is {job.get("runs-on")!r}, not a lab label')
need(not job.get('env'), 'the job carries a job-level env block — every blob and path is step-scoped (C13 placement: the fan-out step env is exactly the file + refs)')
steps = job.get('steps') or []
need(steps, 'sync-fanout has no steps')
names = [str(s.get('name')) if isinstance(s, dict) and s.get('name') else ('uses:' + str(s.get('uses'))) for s in steps]
want = ['diag', 'uses:actions/checkout@v7', 'resolve fan-out pairs', 'fan out ArgoCD syncs']
need(names == want,
     f'steps are {names}, expected exactly {want} (C13 AC6: diag → bare checkout → filter → fan-out; no renamed, extra, or reordered step)')
uses = [s for s in steps if isinstance(s, dict) and 'uses' in s]
need(len(uses) == 1, f'{len(uses)} uses: steps — the job carries EXACTLY one checkout (the filter and fan-out are run steps)')
step = uses[0]
need(str(step.get('uses')) == 'actions/checkout@v7', f'the checkout is {step.get("uses")!r}, expected exactly actions/checkout@v7 (the file pins action majors like its neighbors)')
need(not step.get('with'), 'the checkout step carries a with: block — the fan-out needs no fetch-depth: 0 history; a shallow default clone is the pinned shape (push jobs need history, this one does not)')
diag = next(s for s in steps if isinstance(s, dict) and s.get('name') == 'diag')
need('vars.ROLE' in str(diag.get('run', '')) and 'ROLE=' in str(diag.get('run', '')),
     f'diag step does not echo ROLE like its neighbors: {diag.get("run")!r:.120}')
runs = [s.get('run') for s in steps if isinstance(s, dict) and s.get('run')]
need(len(runs) == 3, f'{len(runs)} run steps, expected 3 (diag, filter, fan-out — C13 AC6)')
need(all(str(r).lstrip().startswith('set -euo pipefail') for r in runs),
     'a sync-fanout run block does not start with set -euo pipefail (t6 shape, job-local)')
PY
then
  fail "t9: see the t9 detail above"
fi
ok "t9: sync-fanout needs == [push-gh, build-containers, build-charts] EXACT (D59; coder EXCLUDED by D4 owner design), advance-marker gates on the full trio [build-containers, build-charts, push-coder-templates], all three called legs are ./.forgejo/workflows/ refs, exact prod guard, lab label, no job-level env, the four pinned steps in order (diag → bare checkout@v7 → resolve fan-out pairs → fan out ArgoCD syncs), three set -euo pipefail run heads (C13 AC6)"
fi

# --- t10: forbidden patterns, file-wide (C13 AC2 + C06/C10 survivors) ---------------
if want t10; then
# The reopen1 transport and the reopen2 blob grammar stay dead. The C13 delta:
# the pair-name regex joins the sweep (a resurrected static row fails here on
# top of t5 — defense in depth) and the naive blob placement is banned at the
# fan-out step. The json.dumps ban RETIRES with the enumeration: the C13 filter
# serializes pairs.json with json.dumps(sort_keys=True) BY CONTRACT (plan
# "Fan-out INPUT contract"); it is not a payload builder.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

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
        ('ARGOCD_HOOK', 'a relay-era vault key name survives — the pair is disposed (C07/C08 delete it instance-side)'),
        ('hook-relay', 'the retired job name survives anywhere in the file'),
        ('RELAY_', 'a relay-era env name survives (RELAY_URL/RELAY_SECRET were the trigger wiring)'),
        ('ARGOCD_SYNC_TOKENS', 'the reopen2 single-blob key name survives — the dead blob input must not resurrect in code, comments or guards (C10 AC2 stands through R8)'),
        ('cat:token', 'the dead newline blob grammar lingers in the comments — the record form died with the blob (DECISIONS 2026-11-25 consequence 4)'),
):
    n = raw.count(pat)
    need(n == 0, f'{pat!r} occurs {n} time(s) file-wide, expected zero ({why})')

pair_names = re.findall(r'ARGOCD_SYNC_[A-Z0-9_]+_(?:URL|TOKEN)(?![0-9A-Za-z_])', raw)
need(not pair_names, f'static pair name(s) {sorted(set(pair_names))} — the enumeration resurrection ban (C13 AC2; t5 runs the same sweep, this is the belt)')

jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}
job = jobs.get('sync-fanout') or {}
for s in (job.get('steps') or []):
    if isinstance(s, dict) and s.get('name') == 'fan out ArgoCD syncs':
        names = set((s.get('env') or {}) if isinstance(s.get('env'), dict) else {})
        need(names == {'ARGOCD_PAIRS_FILE', 'EVT_REF', 'GH_REF'},
             f'the fan-out step env is {sorted(names)}, expected exactly ARGOCD_PAIRS_FILE + EVT_REF + GH_REF (C13 AC3/AC4 — the naive shape ban: no blob env reaches the checkout-running step)')
PY
then
  fail "t10: see the t10 detail above"
fi
ok "t10: zero HMAC/header/crypto/curl/relay-key/hook-relay literals AND the dead ARGOCD_SYNC_TOKENS / cat:token shapes AND no resurrected pair names; the fan-out step env is exactly the pairs-file + refs (no blob env) — transport, superseded input grammar, AND the naive shape stay gone (C13 AC2/AC3)"
fi

# --- t11: the filter contract + invocation bytes (C13 AC4/AC5) ----------------------
if want t11; then
# The inline filter is the pinned enumeration: a DUMB serializer (DECISIONS
# (a)). Selection regex literal verbatim (it is the same law the script
# enforces); union keys; blobs read via os.environ names only (never
# $-interpolated); mkdir/chmod 0600/sort_keys tokens; the count-line print
# literal as the ONLY data printing; the pairs path under $RUNNER_TEMP. The
# invocation and REF chain stay at the C10 landed bytes. The env inventory
# across the job is exactly the five pinned names.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
job = jobs.get('sync-fanout') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t11: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(job, dict) and job, 'no sync-fanout job (t3/t9 already reddened if absent; t11 needs it too)')
steps = [s for s in (job.get('steps') or []) if isinstance(s, dict)]
filt = next((s for s in steps if s.get('name') == 'resolve fan-out pairs'), None)
need(filt is not None, 'no resolve fan-out pairs step (t9 reddens too; t11 needs it)')
fbody = str(filt.get('run', ''))
fcode = "\n".join(ln for ln in fbody.splitlines() if not ln.lstrip().startswith('#'))

env_kv = {}
for src in [job.get('env') or {}] + [s.get('env') or {} for s in steps]:
    for k, v in src.items():
        env_kv[k] = str(v)
need(set(env_kv) == {'SECRETS_JSON', 'VARS_JSON', 'ARGOCD_PAIRS_FILE', 'EVT_REF', 'GH_REF'},
     f'job+step env keys are {sorted(env_kv)}, expected EXACTLY SECRETS_JSON + VARS_JSON (filter step) + ARGOCD_PAIRS_FILE + EVT_REF + GH_REF (fan-out step) (C13 AC2/AC3)')

fan_env = {}
for s in steps:
    if s.get('name') == 'fan out ArgoCD syncs':
        fan_env = {k: str(v) for k, v in (s.get('env') or {}).items()}
# Context wiring, cf-56 D4 form: EVT_REF re-aims at the NATIVE
# forgejo.event.ref context (the event payload is Forgejo's own;
# github.event.ref was the GH-emulation alias); GH_REF keeps github.ref for
# the run-ref fallback, with the compat note the fold must carry. Until the
# dev session lands the fold, the EVT_REF leg is a DESIGNED-RED CARRIER —
# it flips green at the fold commit (the C13-carrier pattern); the pin must
# not be softened to accept the pre-fold form.
ev = fan_env.get('EVT_REF', '')
need('forgejo.event.ref' in ev,
     f'EVT_REF is wired to {ev!r}, expected ${{{{ forgejo.event.ref }}}} — DESIGNED-RED CARRIER until the cf-56 D4 fold lands (the dev session owns main-sync.yaml; the event ref is Forgejo-native, the github.event.ref alias retires with the fold)')
need('github.ref' in fan_env.get('GH_REF', ''),
     'GH_REF is not wired to github.ref (the run-ref fallback keeps the GitHub-compat context, cf-56 D4)')
need(bool(re.search(r"(?i)github[- /]compat|compat|D4", "\n".join(ln for ln in raw.splitlines() if re.search(r"github\.ref|GH_REF", ln) and ln.lstrip().startswith('#')))),
     'no comment line names the github.ref compatibility role (cf-56 pins a D4/compat note beside the surviving github.ref use — a reader must learn why one context stays while the event ref moved to forgejo.*)')

# Run-body interpolation ban: no secrets at all, no vars beyond the diag
# ROLE echo the job-shape leg pins.
blob = "\n".join(str(s.get('run')) for s in steps if s.get('run'))
for ln in blob.splitlines():
    if ln.lstrip().startswith('#'):
        continue
    if 'secrets.' in ln:
        need(False, f'run body line references a secret: {ln.strip()[:100]!r} — vault values come in through env maps only ([27][29])')
    badvar = re.search(r'vars\.(?!ROLE(?![0-9A-Za-z_]))([A-Za-z0-9_]+)', ln)
    if badvar:
        need(False, f'run body line interpolates vars.{badvar.group(1)}: {ln.strip()[:100]!r} — only the diag ROLE echo may read vars in-body')

# --- the filter block (C13 AC4/AC5) -------------------------------------------------
need(re.search(r'python3\s+-c', fbody), 'the filter step runs no inline python3 -c (a scripts/ helper would defeat the dumb-serializer ruling and the checkout-ordering)')
need('"^ARGOCD_SYNC_(.+)_(URL|TOKEN)$"' in fbody,
     'the selection regex literal is not the pinned pair shape (verbatim, double-quoted in python): ^ARGOCD_SYNC_(.+)_(URL|TOKEN)$ — a divergent regex forks the law the script\'s PAIR_KEY_RE enforces')
for tok, why in (('json.loads', 'blobs must be parsed with stdlib json'),
                 ('os.environ.get("VARS_JSON")', 'blob read via env NAME (VARS_JSON)'),
                 ('os.environ.get("SECRETS_JSON")', 'blob read via env NAME (SECRETS_JSON)'),
                 ('mkdir', 'RUNNER_TEMP must be mkdir-ed before the write (C13 pins mkdir -p "$RUNNER_TEMP")'),
                 ('chmod', 'the filter owns the 0600 mode (DECISIONS (f): the script never stats)'),
                 ('0o600', 'the pinned mode literal'),
                 ('sort_keys', 'pairs.json must serialize sorted (json.dumps sort_keys=True — the deterministic file)'),
                 ('RUNNER_TEMP', 'the file lands under $RUNNER_TEMP (per-job ephemeral [40][51])'),
                 ('pairs.json', 'the pinned file name the fan-out step env points at')):
    need(tok in fcode, f'filter block lacks the contract token {tok!r} ({why})')
need('json.loads(os.environ.get("VARS_JSON") or "{}")' in fcode
     and 'json.loads(os.environ.get("SECRETS_JSON") or "{}")' in fcode,
     'a blob side must load as `json.loads(os.environ.get("<NAME>") or "{}")` — missing/empty side is the designed all-absent state (a non-JSON blob must raise loud, never fall back)')
need('print("filter: %d keys selected" % len(pairs))' in fcode,
     'the pinned count line is not byte-exact: print("filter: %d keys selected" % len(pairs)) (plan INPUT contract — the runbook greps it)')
printers = [ln.strip() for ln in fcode.splitlines() if 'print(' in ln]
need(printers and all('filter: %d keys selected' in ln for ln in printers),
     f'the filter block prints something beyond the count line: {[p[:80] for p in printers]} — the print law: NO values, names-with-values, or blobs ever leave the step (C13 AC5)')
need('echo' not in fcode or not re.search(r'echo[^\n]*(SECRETS_JSON|VARS_JSON|pairs)', fcode),
     'the filter echoes a blob or pair content — count only (C13 AC5)')
for ref in ('"$SECRETS_JSON"', '"$VARS_JSON"', '$SECRETS_JSON', '$VARS_JSON'):
    need(ref not in fcode, f'the filter body $-interpolates {ref} — env names are read via os.environ inside python, never shell-expanded into the source (C13 quoting rule)')
need('.unlink' not in fcode and 'remove(' not in fcode,
     'the filter deletes the pairs file — RUNNER_TEMP is per-job ephemeral by ruling (DECISIONS (f)); cleanup is the runner\'s')

# The invocation: script path + roster + ref flag, byte-pattern per the plan
# (UNCHANGED by R8 — C13 AC4 "the invocation line bytes").
m = re.search(r'python3 scripts/argocd-fanout\.py --config scripts/argocd-fanout\.json --ref "\$REF"', blob)
need(bool(m), 'no invocation line matching the pinned contract: python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF" (the flags/path ARE the C13↔C14 interface)')
invocation_lines = [ln for ln in blob.splitlines() if 'argocd-fanout.py' in ln and not ln.strip().startswith('#')]
need(invocation_lines, 'no argocd-fanout.py invocation line found')
for ln in invocation_lines:
    need('ARGOCD_SYNC' not in ln, f'the invocation line references a vault key ({ln.strip()[:100]!r}) — pairs travel via the file, never per-call')
    need('--token' not in ln, f'the invocation passes a --token flag — banned by the CLI contract (tokens ONLY through the pairs file)')

# REF fallback chain: dispatch pushes may carry no event ref (build-charts.yaml:96
# context-quirk precedent) — the chain is pinned exactly (survives byte-true).
need(re.search(r'REF="\$\{EVT_REF:-\$\{GH_REF:-refs/heads/main\}\}"', blob),
     'no REF="${EVT_REF:-${GH_REF:-refs/heads/main}}" fallback chain — dispatch/first-push runs must resolve main, not fan out on an empty ref')
PY
then
  fail "t11: see the t11 detail above"
fi
ok 't11: env inventory is EXACTLY the five pinned names; refs wired per cf-56 D4 (EVT_REF → forgejo.event.ref — designed-red carrier until the fold; GH_REF keeps github.ref with a compat note pin); no body interpolation; the filter contract holds (python3 -c, verbatim pair regex, env-name blob reads with {}-fallback, mkdir/chmod 0o600/sort_keys, byte-exact count line as sole print, no $-interpolation, no self-cleanup); the byte-pinned invocation and the exact REF fallback chain survive (C13 AC4/AC5)'
fi

# --- t12: posture (C13 AC5/AC6, posture lives in the script) -------------------------
if want t12; then
# The all-absent warn-green lane and the pair-integrity RED lane live in the
# script (unchanged by R8); the job only propagates. C13 adds: the blobs are
# never echoed anywhere, and the filter's nonzero exits come ONLY from python
# exceptions (v13 fail-loud doctrine [53]) — no written exit code in its
# block; the fan-out call stays unguarded.
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
steps = [s for s in (job.get('steps') or []) if isinstance(s, dict)]
runs = [str(s.get('run')) for s in steps if s.get('run')]
blob = "\n".join(runs)

# The guard is DEAD: no -z/-n test on any ARGOCD_SYNC name anywhere in the
# file, and no resurrection of the skip-warning wording (that string now
# lives ONLY in the script, pinned by behavior.sh t5).
need(not re.search(r'-[zn]\s+"?\$\{?ARGOCD_SYNC', raw),
     'a shell emptiness test on an ARGOCD_SYNC_* name survives — the script owns both lanes (a YAML guard would diverge from the token-side predicate)')
need('sync-fanout not configured' not in raw,
     'the skip-warning string still lives in the workflow — the warning must come from the script\'s stdout (behavior.sh pins its exact bytes), not from a shell echo that cannot see the fleet')

# Blob echo ban, file-wide: the serialized maps stay inside step-1's process
# and its env line; no body may echo or print them (interpolation-into-
# command lines would land raw values in the step script file [27][29]).
for pat in (r'echo[^\n]*\$?\{?(SECRETS_JSON|VARS_JSON)', r'printf[^\n]*\$?\{?(SECRETS_JSON|VARS_JSON)'):
    hits = [ln.strip()[:100] for ln in blob.splitlines() if re.search(pat, ln) and not ln.lstrip().startswith('#')]
    need(not hits, f'a run body echoes/prints a blob env: {hits} — print law (C13 AC5): the count line is the only data output')

# Written exits die with the enumeration's inertness defense (C10 deleted the
# guard; C13's filter fails loud through python exceptions ONLY): no exit
# statement in any sync-fanout run block, and no written exit 1 anywhere.
need('exit 1' not in blob, 'a written exit 1 appears — the script owns the config-red exit code; the run body must not hand-write failures')
for s in steps:
    if isinstance(s, dict) and s.get('name') in ('resolve fan-out pairs', 'fan out ArgoCD syncs'):
        body = "\n".join(ln for ln in str(s.get('run', '')).splitlines() if not ln.lstrip().startswith('#'))
        need(not re.search(r'\bexit\b', body),
             f'the {s.get("name")!r} block hand-writes an exit — the filter exits nonzero ONLY via python exceptions (fail-loud [53]); the fan-out propagates the script\'s own code (C13 AC5/AC6)')
need('|| true' not in blob, 'a `|| true` swallow appears — it would push the pair-integrity RED class back into the silent lane (DECISIONS exit-posture refinement, unchanged by R8)')
for ln in blob.splitlines():
    if 'argocd-fanout.py' in ln and not ln.strip().startswith('#'):
        need('||' not in ln, f'the python call is guarded on this line ({ln.strip()[:100]!r}) — it must run UN-guarded under set -euo pipefail so the script-owned RED lanes reach the job exit code')
        need(not re.search(r'=\$\(.*argocd-fanout\.py', ln), f'the python call sits in a command substitution ({ln.strip()[:100]!r}) — its exit code must reach the step, not be captured and dropped')
PY
then
  fail "t12: see the t12 detail above"
fi
ok "t12: no -z guard / no skip-warning echo on ARGOCD_SYNC names anywhere, no blob echo (print law), no written exit in filter or fan-out blocks (the filter fails loud via python exceptions only), no || true, the python call unguarded and uncaptured — config RED propagates, warn-green comes from the script's stdout (C13 AC5/AC6)"
fi

# --- t13: syntax + cross-artifact compile (C13 AC1) --------------------------------
if want t13; then
# bash -n every extracted run block INCLUDING the new filter block (the
# designed-red shape leg: today there is no fourth step), the fan-out script
# compiles, and the roster PARSES. The roster schema assert is PERMANENTLY
# parse-only here (DECISIONS 2026-11-26: OQ-A answered pure discovery, zero
# schema churn — the five-globals pin lives in behavior.sh t2; a workflow
# suite must not fork a second home for it).
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
fan_runs = {name for jn, name, r in runs if jn == 'sync-fanout'}
if not {'diag', 'resolve fan-out pairs', 'fan out ArgoCD syncs'} <= fan_runs:
    print(f'FAIL: t13: sync-fanout run blocks are {sorted(fan_runs)}, expected diag + resolve fan-out pairs + fan out ArgoCD syncs — the filter block must exist AND lint (C13 AC1/AC6; the shape leg is designed-red until the fleet-blind job lands)', file=sys.stderr)
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

# The filter's inline python must COMPILE too — the single-quoted body lives
# at the shell indent inside a YAML block scalar, and a one-space drift is a
# silent IndentationError at dispatch (bash -n cannot see it).
import re as _re
filter_blocks = [r for jn, name, r in runs if name == 'resolve fan-out pairs']
if filter_blocks:
    m = _re.search(r"python3 -c '(?P<code>.*)'\s*$", filter_blocks[0], _re.DOTALL)
    if not m:
        print('FAIL: t13: the filter run block has no single-quoted python3 -c body (C13 quoting rule)', file=sys.stderr)
        sys.exit(1)
    try:
        compile(m.group('code'), '<filter>', 'exec')
    except SyntaxError as e:
        print(f'FAIL: t13: the filter inline python does not compile: {e}', file=sys.stderr)
        sys.exit(1)

if not os.path.isfile(fanout):
    print(f'FAIL: t13: {fanout} absent — the job invokes a script that does not exist (C05 must land first; this leg turns green at C05 and may not regress)', file=sys.stderr)
    sys.exit(1)
rc = subprocess.run([sys.executable, '-m', 'py_compile', fanout], capture_output=True, text=True)
if rc.returncode != 0:
    print(f'FAIL: t13: py_compile rejected {fanout}: {rc.stderr.strip()[:300]}', file=sys.stderr)
    sys.exit(1)
# PARSE-ONLY (the permanent split, DECISIONS 2026-11-26): a roster that does
# not parse breaks the invocation; its KEY SET is behavior.sh t2's schema pin
# — no six-vs-five question lives here any more (the OQ-A oracle died).
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
ok "t13: every sync-fanout run block exists (diag/filter/fan-out) and passes bash -n, scripts/argocd-fanout.py py_compiles, and the roster parses — schema pin lives permanently in behavior.sh t2 (C13 AC1, parse-only split)"
fi

# --- t14: advance-marker output sanitizer — deploy-incident carrier ------------------
# act hands an UNRESOLVED called-workflow output through to bash as literal
# expression text: on a no-bump fan `needs.build-charts.outputs.bump_sha`
# arrived unset, the old direct `TARGET=${{ ... }}` line died 'bad
# substitution', and the `:-` default trick cannot help because the RAW
# assignment is what explodes (owner deploy incident). The consumer
# sanitizer (the dev session lands the fold): single-quoted RAW capture,
# a case guard mapping empty-or-literal to the $GITHUB_SHA fallback,
# resolved 40-hex winning, resolved-malformed exiting 1 LOUD naming
# bump_sha. DESIGNED-RED CARRIER until the fold lands — the fail text
# names it; the sim harness then runs the LANDED block itself (bash-stub
# scratch, no net, no real marker — t13's run-block extraction pattern).
if want t14; then
if ! python3 - "$WF" <<'PY'
import os, re, subprocess, sys, tempfile, yaml

wf = sys.argv[1]
jobs = (yaml.safe_load(open(wf)) or {}).get('jobs') or {}
raw_text = open(wf).read()


def bad(msg):
    print('FAIL: t14: %s\nFAIL: t14: see the t14 detail above' % msg, file=sys.stderr)
    sys.exit(1)


CARRIER = "DESIGNED-RED CARRIER until the deploy-incident sanitizer fold lands (the parallel dev session owns .forgejo/workflows/main-sync.yaml; pre-fold the marker block still holds the bare TARGET=${{ ... }} form the owner's deploy died on)"

job = jobs.get('advance-marker') or {}
steps = [s for s in (job.get('steps') or []) if isinstance(s, dict)]
runs = [str(s.get('run')) for s in steps if s.get('run')]
block_all = "\n".join(runs)
if not block_all:
    bad("advance-marker has no run block — " + CARRIER)

# --- static contract pins -----------------------------------------------------------
m = re.search(r"""(?m)^([ \t]*)RAW='\$\{\{\s*needs\.build-charts\.outputs\.bump_sha\s*\}\}'[ \t]*$""", block_all)
if not m:
    bad("(a) no single-quoted RAW capture of the needs expression (expected exactly RAW='${{ needs.build-charts.outputs.bump_sha }}' on its own line — the quoting is the whole fix: the literal arrives as text instead of exploding as a parameter expansion) — " + CARRIER)
if not re.search(r'(?m)^[ \t]*case[ \t]+"\$RAW"[ \t]+in[ \t]*$', block_all):
    bad("(b) no `case \"$RAW\" in` dispatch on the captured value — " + CARRIER)
if not re.search(r'''""\s*\|\s*\*\s*'\{\{'\*''', block_all):
    bad("(b) the case guard lacks the empty-or-literal pattern (\"\"|*'{{'*) — the unresolved-act pass-through class is unmatched — " + CARRIER)
if not re.search(r'\[0-9a-f\]\\?\{40\\?\}', block_all) and not re.search(r'\[0-9a-f\]\{40\}', block_all):
    bad("(c) no 40-hex acceptance arm (^[0-9a-f]{40}$ grep) — a resolved-but-truncated value would silently drive the marker — " + CARRIER)
loud = [ln for ln in block_all.splitlines() if re.search(r'(?i)(echo|printf)', ln) and 'bump_sha' in ln]
if not loud:
    bad("(d) no loud branch names bump_sha (the resolved-malformed class must announce WHICH output misbehaved) — " + CARRIER)
if 'exit 1' not in block_all:
    bad("(d) the malformed class has no exit 1 — resolved garbage must go RED, never fall back quietly — " + CARRIER)
revived = [ln.strip()[:90] for ln in raw_text.splitlines() if re.match(r'^[ \t]*TARGET=.*\$\{\{', ln)]
if revived:
    bad("(e) the bare TARGET=${{ ... }} assignment (direct or quoted — both explode on the unresolved literal) is back: %r — this exact line caused the owner's deploy 'bad substitution'" % revived)
trick = [ln.strip()[:90] for ln in raw_text.splitlines() if re.match(r'^[ \t]*TARGET=.*:-', ln)]
if trick:
    bad("(e) the `${TARGET:-...}` default trick is back: %r — the trick is dead because the RAW assignment explodes BEFORE any default on TARGET could apply; the case-guard fallback is the shape" % trick)

# --- functional proof: run the LANDED decision block under four inputs ---------------
lines = block_all.splitlines()
start = next(i for i, ln in enumerate(lines) if re.search(r"""RAW='\$\{\{""", ln))
end = next(i for i in range(start, len(lines)) if lines[i].strip() == 'esac')
block = "\n".join(lines[start:end + 1])

GH = "0f1e2d3c4b5a69788796a5b4c3d2e1f001234567"     # stub event sha (fallback owner)
HEX = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"     # stub resolved bump sha


def run_variant(raw_replacement=None):
    script = block if raw_replacement is None else re.sub(r"RAW='[^']*'", "RAW='%s'" % raw_replacement, block, count=1)
    # strip the embedded needs expression from the variant lines? NO — RAW='...'
    # single-quoted content is literal text to bash; keep it byte-true.
    full = "set -euo pipefail\n" + script + "\nprintf 'TARGET=%s\\n' \"$TARGET\"\n"
    fd, path = tempfile.mkstemp(prefix='marker-sim-', suffix='.sh',
                                dir=os.environ.get('TMPDIR', '/tmp/opencode'))
    with os.fdopen(fd, 'w') as f:
        f.write(full)
    env = dict(os.environ)
    env['GITHUB_SHA'] = GH
    r = subprocess.run(['bash', path], capture_output=True, text=True, env=env, timeout=20)
    os.unlink(path)
    return r


# (1) LITERAL PASS-THROUGH — the incident itself, exactly as act delivers it:
r = run_variant(None)
out = r.stdout + r.stderr
if r.returncode != 0:
    bad("sim/literal: the decision block EXITED %d on the unresolved-pass-through literal instead of falling back (%s) — the 'bad substitution' class is still alive in the landed shape" % (r.returncode, out[:200]))
if 'TARGET=%s' % GH not in r.stdout:
    bad("sim/literal: TARGET did not fall back to $GITHUB_SHA (%r, stdout %r) — the case guard misses the literal class" % (GH, r.stdout[:120]))
if '{{' in r.stdout or 'bump_sha' in r.stdout:
    bad("sim/literal: the expression literal LEAKED into TARGET (%r) — a marker ref must never be expression text" % r.stdout[:160])

# (2) EMPTY — the plain unset case:
r = run_variant('')
if r.returncode != 0 or 'TARGET=%s' % GH not in r.stdout:
    bad("sim/empty: rc %d stdout %r — an unset output must fall back to $GITHUB_SHA green" % (r.returncode, r.stdout[:120]))

# (3) VALID HEX — the resolved bump wins over the event sha:
r = run_variant(HEX)
if r.returncode != 0 or 'TARGET=%s' % HEX not in r.stdout:
    bad("sim/hex: rc %d stdout %r — a resolved 40-hex bump_sha must DRIVE the marker (D53 endpoint rule), not be discarded" % (r.returncode, r.stdout[:120]))

# (4) GARBAGE — resolved-but-malformed stays LOUD:
r = run_variant('oops-not-a-commit')
out = r.stdout + r.stderr
if r.returncode == 0:
    bad("sim/garbage: rc 0 — resolved garbage fell through instead of exiting 1 (the marker would move to a non-commit; the loud class exists to stop exactly that)")
if 'bump_sha' not in out:
    bad("sim/garbage: the red path did not name bump_sha (%r) — operators cannot trace which output misbehaved" % out[:200])
print('ok: t14 — sanitizer contract (quoted RAW, case guard, 40-hex arm, loud malformed branch, no bare TARGET/:- revival) and the decision block passes all four simulations')
PY
then
  fail "t14: see the t14 detail above"
fi
ok "t14: advance-marker output sanitizer — RAW single-quoted capture of the needs expression, case guard on the empty-or-literal class (''|*'{{'*'), 40-hex win arm, loud exit-1 branch naming bump_sha, the bare TARGET=\${{ }} and :- -default revivals banned; FUNCTIONAL: the landed decision block runs under literal/empty/valid-hex/garbage inputs against a stub GITHUB_SHA and answers fallback/fallback/win/RED with no expression leak (deploy-incident carrier)"
fi

printf 'PASS: forgejo-main-sync checks (%d ok)\n' "$checks"