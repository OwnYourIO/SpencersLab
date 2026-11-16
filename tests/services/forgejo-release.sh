#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/release.yaml (cf-55 on the
# REBUILT branch — DECISIONS D31/D32 reconcile): the chart bump+publish
# pipeline running on Forgejo Actions with DUAL publish, reconciled to the
# cf-6 conventions that landed on main. The invariants pinned here are the
# ones that keep the design safe — the ROLE-MEMBERSHIP guard on every job
# (contains(vars.ROLE, 'prod'), the repo-wide shape of the AGENTS.md Forge
# Actions law: guards test membership, never equality, and never an instance
# URL; this workflow stays NARROW on unset — a bump/publish pipeline must
# not fire unconfigured, the opposite polarity of containers-build.yaml's
# deliberate widen), the bump leg being a single-writer idempotent
# fast-forward-only loop (concurrency is best-effort; the loop is the safety
# property), the per-direction credential topology (PUSH_TOKEN_GH serves the
# GitHub release leg only; the instance package push rides the shipped
# FORGE_PUSH_TOKEN human-PAT with the cosmetic "forge:" username and the
# literal lowercase curatedforest namespace — the Actions job token cannot
# write packages, and the retired PUSH_TOKEN_FJ/FJ_PACKAGE_USER pair must
# never re-enter as a binding), the output-write compat idiom
# (${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}, the same one containers-build.yaml
# ships), the release/forgejo-publish independence, the retired wrapper
# actions really retired, and the full-depth checkouts the inline git-diff
# and cr replacements live on (a shallow clone silently empties the detect
# range and collapses cr's latest-tag lookup).
#
# Purely static — no network, no runner: bash reads the file, python3 parses
# it per leg. Convention of tests/services/forgejo-main-sync.sh (the GitHub
# twin's ABSENCE is checked through a COMPOSED path so this file never carries
# the old full path as literal text — tests/services/forgejo-ci-surface.sh
# sweeps live surfaces for exactly that).
#
# pyyaml binds the trigger-leg shape: YAML 1.1 resolves the bare `on:` key to
# boolean True, so the trigger block is doc.get(True) or doc.get('on');
# asserting on the string key 'on' alone would redden a correct file.
#
# Historic legs kept from the old-branch rounds (t13 outputs-wiring and
# t14 POST-vs-GET upload method came from the fix rounds and survive the
# rebuild unchanged, as do the index VALUE-semantics carrier legs t15).
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-release.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF=".forgejo/workflows/release.yaml"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- t1: shape — twin moved, GitHub original gone (AC1) ----------------------
[ -f "$WF" ] || fail "t1: $WF does not exist (the chart builder must be written on the rebuilt branch)"
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$WF" \
  || fail "t1: $WF does not parse as YAML"
if ! python3 - <<'PY'
import os, sys

# Composed, never written as one literal: the ci-surface sweep bans the old
# full path on live surfaces, and this suite is a live surface. Unlike the
# container half (cf-6 keeps the GitHub builder as the manual fallback),
# the release twin is DELETED.
twin = os.path.join(".github", "workflows", "release.yaml")
if os.path.exists(twin):
    print(f'FAIL: t1: {twin} still exists — the cutover deletes the GitHub release twin in the same commit as the Forgejo twin', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t1: see the t1 detail above"
fi
ok "t1: $WF exists and parses; the GitHub release twin is deleted (cutover in one commit)"

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
# Faithful to the twin this ticket replaces: push-only, no workflow_dispatch,
# no pull_request (the first fire rides a real merge; PR legs stay on GitHub).
need(set(trig) == {'push'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly push')
push = trig['push']
need(isinstance(push, dict), 'push: is not a mapping')
need(push.get('branches') == ['main'],
     f'push.branches is {push.get("branches")!r}, expected exactly [main]')
paths = push.get('paths')
need(isinstance(paths, list) and 'charts/**' in paths,
     f'push.paths is {paths!r}, expected to contain charts/**')
PY
then
  fail "t2: see the t2 detail above"
fi
ok "t2: on: is exactly push.branches [main] with paths covering charts/** (no dispatch, no PR)"

# --- t3: jobs + ROLE-membership guards (D31 reconcile) -------------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

GUARD = "contains(vars.ROLE, 'prod')"
raw = open(sys.argv[1]).read()
doc = yaml.safe_load(raw) or {}
jobs = doc.get('jobs')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t3: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(jobs, dict), 'no jobs: mapping')
# The job inventory the chunk prescribes; a renamed or extra job reddens here.
need(set(jobs) == {'changes', 'test-build', 'bump', 'release', 'forgejo-publish'},
     f'jobs keys are {sorted(jobs)}, expected exactly changes/test-build/bump/release/forgejo-publish')
for name, job in jobs.items():
    need((job or {}).get('if') == GUARD,
         f"{name}.if is {(job or {}).get('if')!r}, expected {GUARD!r} — every job carries exactly the membership guard (AGENTS Forge Actions law: contains(), never equality; has-changes gating belongs to step-level ifs)")
# Equality-as-live-guard is banned (D31): scan every live if, job and step.
# Not a raw-text ban — comments may discuss the retired equality polarity (the
# AGENTS sequencing note does), only executable positions must not use it.
live_ifs = [str((job or {}).get('if', '')) for job in jobs.values()]
live_ifs += [str(s.get('if', '')) for job in jobs.values() for s in (job or {}).get('steps', [])
             if isinstance(s, dict) and 'if' in s]
for expr in live_ifs:
    if 'vars.ROLE' in expr:
        need('contains(vars.ROLE' in expr,
             f'a live if tests vars.ROLE without contains() membership ({expr!r}) — equality guards retired repo-wide (D31)')
        # Narrow-on-unset polarity: this pipeline must never fire with ROLE
        # unset; the `vars.ROLE == null` widen clause (containers-build's
        # deliberate opposite) has no place here.
        need('== null' not in expr and '!= null' not in expr,
             f'a live if carries an unset-widen clause ({expr!r}) — release.yaml is narrow-on-unset by the bump-is-a-state-change reading (D31/D32)')
# The dev instance receives the synced copy and must fire no job here.
need("vars.ROLE == 'dev'" not in raw, 'a job guards on vars.ROLE == dev (the dev stage must fire nothing)')
# The header must carry the substring caveat: contains() is a substring test,
# so a future role word CONTAINING prod would silently widen these guards —
# the caveat is the AGENTS law this file is held to.
need('Substring caveat' in raw and 'as a substring' in raw,
     'the ROLE substring caveat comment is missing — contains() is a substring test and the caveat is what stops a future "production" role word from silently widening these guards')
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: exactly the five prescribed jobs, every one guarded on contains(vars.ROLE, 'prod') (equality/null-widen live guards absent); dev guard absent; substring caveat present"

# --- t4: runner labels ---------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

LABELS = {'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'docker', 'node22'}
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}

for name, job in jobs.items():
    label = (job or {}).get('runs-on')
    if label not in LABELS:
        print(f'FAIL: t4: {name}.runs-on is {label!r}, not one of the advertised act labels {sorted(LABELS)} (ubuntu-26.04 routes nowhere on lab runners)', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t4: see the t4 detail above"
fi
ok "t4: every job runs on an advertised lab runner label"

# --- t5: action allow-list ------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}
ALLOWED = ('actions/checkout@', 'azure/setup-helm@')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


steps = [(jn, s) for jn, job in jobs.items() for s in (job or {}).get('steps', [])
         if isinstance(s, dict)]
for jn, s in steps:
    u = str(s.get('uses', ''))
    if not u:
        continue
    need(u.startswith(ALLOWED),
         f'{jn}: uses {u!r} — only mirror-confirmed actions/checkout and azure/setup-helm may be used (D3)')
    need('github.com' not in u and 'http' not in u,
         f'{jn}: absolute-URL uses {u!r} (unproven runner egress for clones)')
    if 'azure/setup-helm' in u:
        ver = (s.get('with') or {}).get('version')
        need(bool(ver), f'{jn}: azure/setup-helm step carries no pinned version: input (AC4)')
# The four wrapper actions the move replaces inline — retired names may not
# re-enter the file anywhere, runs, comments or uses included.
for banned in ('dorny/paths-filter', 'EMAsphere', 'EndBug', 'chart-releaser-action'):
    need(banned not in raw, f'{banned} appears in the file (the inline replacements are mandatory: git-diff detect, stdlib patch bump, raw git, cr CLI)')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: every uses is actions/checkout or version-pinned azure/setup-helm; the four retired actions appear nowhere"

# --- t6: hardened repo-add loop in every dependency-resolving leg (AC5) --------
if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}

# Legs that run helm against chart dependencies. The cf-77-hardened awk scan
# (first URL-shaped field) plus the oci:// skip are copied VERBATIM from the
# proven loop; a leg that runs `helm dependency list` without it re-breaks on
# any empty-REPOSITORY subchart row.
for jn in ('test-build', 'release', 'forgejo-publish'):
    blob = '\n'.join(str(s.get('run', '')) for s in (jobs.get(jn) or {}).get('steps', [])
                     if isinstance(s, dict) and 'run' in s)
    for tok, why in (('helm dependency list', 'the loop iterates this output'),
                     ('^(https?|oci|file)', 'the awk URL-shaped-field scan (the awk source escapes the trailing slashes; the token up to the field list is the invariant)'),
                     ('^oci://', 'the oci:// skip that keeps registry deps out of helm repo add')):
        if tok not in blob:
            print(f'FAIL: t6: {jn} run blocks lack {tok!r} — {why}', file=sys.stderr)
            sys.exit(1)
PY
then
  fail "t6: see the t6 detail above"
fi
ok "t6: the hardened Add-repositories loop (URL-shaped scan + oci:// skip) is in test-build, release and forgejo-publish"

# --- t7: bump single-writer + idempotent FF-only loop (AC6) ---------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}
job = jobs.get('bump') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t7: {msg}', file=sys.stderr)
        sys.exit(1)


need('strategy' not in job,
     'bump has a strategy: — the matrix bump was the known-broken shape (the old release.yaml TODO); the fix is ONE job looping the changed charts (D4)')
runs = [str(s.get('run', '')) for s in job.get('steps', []) if isinstance(s, dict) and 'run' in s]
blob = '\n'.join(runs)

# V-6-3: the checkout is a detached HEAD — a bare `git pull` cannot be the
# remote-tip re-read; the explicit fetch refspec is. Comments may discuss the
# wrong shape (the why-note is load-bearing documentation), so the ban reads
# executable lines only; the refspec fetch pin above carries the positive duty.
need('refs/remotes/origin/main' in blob,
     'bump never fetches the remote main tip (refs/remotes/origin/main) — a bare git pull is wrong on the detached-HEAD checkout')
code = '\n'.join(l for l in blob.splitlines() if not l.lstrip().startswith('#'))
need(not re.search(r'\bgit\s+pull\b', code),
     'bump run blocks invoke bare git pull — wrong on the detached-HEAD checkout (V-6-3); fetch the refspec and reset onto it')

# The re-read must happen INSIDE the retry loop, not once outside it: a fetch
# line following a for/while/until header in the same run block is the static
# shape of "re-pull every attempt".
inside = False
for r in runs:
    lines = r.splitlines()
    loop_at = next((i for i, l in enumerate(lines) if re.match(r'\s*(for|while|until)\b', l)), None)
    fetch_at = next((i for i, l in enumerate(lines) if 'refs/remotes/origin/main' in l), None)
    if loop_at is not None and fetch_at is not None and fetch_at > loop_at:
        inside = True
need(inside, 'the remote-tip fetch does not occur inside a retry loop (each attempt must re-fetch, re-check, then push)')

# Bounded retry: a numeric cap on the loop (seq N, {1..N}, or -lt/-ge N).
need(re.search(r'seq\s+\d+|\{\s*\d+\s*\.\.\s*\d+\}|-(?:lt|le|gt|ge)\s+\d+', blob),
     'no numeric retry cap in the bump loop — an unbounded loop spins forever on a refused push')

# V-6-4: on detached HEAD the only correct push spelling is the explicit
# refspec (main-sync's proven form). FF-only is implicit: a plain push
# refuses non-FF; force spellings die in the ban below.
need('HEAD:refs/heads/main' in blob,
     'bump does not push HEAD:refs/heads/main (the detached-HEAD refspec shape)')

# File-wide: never force, never merge, never rewrite.
for pat in ('--force', '+refs', 'git push -f', 'git merge'):
    n = raw.count(pat)
    need(n == 0, f'{pat!r} occurs {n} time(s) file-wide, expected zero (a refused non-FF re-loops; it never overwrites)')

# The bump rides the checkout's default same-repo credentials — the automatic
# token's non-re-trigger is the loop guard — so no secret may be named in it.
# (This is the ONE carved-out automatic-token use in the repo's CI law: a
# same-repo git push, never a package write.)
need('secrets.' not in yaml.dump(job),
     'the bump job references a named secret — it must push with the automatic same-repo credential only (ruling R3; the credential law carves exactly this git push out)')
PY
then
  fail "t7: see the t7 detail above"
fi
ok "t7: bump is one matrix-less job: in-loop remote-tip fetch + reset shape, bounded retry cap, HEAD:refs/heads/main push, zero secrets, no force/merge file-wide"

# --- t8: credential topology (the D31 reconciled shape) -----------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}
rel = yaml.dump(jobs.get('release') or {})
fp = yaml.dump(jobs.get('forgejo-publish') or {})


def need(cond, msg):
    if not cond:
        print(f'FAIL: t8: {msg}', file=sys.stderr)
        sys.exit(1)


def count(key):
    # Boundary-anchored: a renamed key that merely extends the original
    # (PUSH_TOKEN_GH -> PUSH_TOKEN_GHX) must not count as an occurrence.
    return len(re.findall(re.escape(key) + r'(?![0-9A-Za-z_])', raw))


# One credential per direction, each bound once. The bump and instance legs
# reference PUSH_TOKEN_GH nowhere; cross-forge identities must never mix.
# The instance half is the SHIPPED cf-6 secret FORGE_PUSH_TOKEN (D31:
# PUSH_TOKEN_FJ/FJ_PACKAGE_USER retired — cf-6 already ships the PAT).
for key, own, other in (('secrets.PUSH_TOKEN_GH', rel, fp),
                        ('secrets.FORGE_PUSH_TOKEN', fp, rel),
                        ('vars.PUSH_URL_GH', rel, fp)):
    n = count(key)
    need(n == 1, f'{key} occurs {n} times file-wide, expected exactly once (single env binding in its own leg — main-sync t5 style)')
    need(key in own, f'{key} is not referenced under its own job')
    need(key not in other, f'{key} leaks into the other leg (identities must not cross)')

# Retired bindings may not re-enter: a comment MAY name them to explain the
# retirement, but no secrets./vars. reference to the dead pair is allowed.
for dead in (r'(?:secrets|vars)\.PUSH_TOKEN_FJ\b', r'(?:secrets|vars)\.FJ_PACKAGE_USER\b'):
    need(not re.search(dead, raw),
         f'a binding matching {dead} exists — the FJ_PACKAGE_USER/PUSH_TOKEN_FJ pair was retired by the cf-6 reconcile (D31): FORGE_PUSH_TOKEN is THE instance package credential, shipped and proven by the container pushes')

# The instance curl auth pairs the COSMETIC username literal with the bound
# token (identity comes from the password half — the same fact cf-6's docker
# login states; the username carries no secret). Both the index read and the
# upload must use the one form; a bare-token or context-identity user fails.
fp_runs = '\n'.join(str(s.get('run', '')) for s in (jobs.get('forgejo-publish') or {}).get('steps', [])
                    if isinstance(s, dict) and 'run' in s)
users = re.findall(r'--user\s+"([^"]*)"', fp_runs)
need(users, 'forgejo-publish curls carry no --user basic-auth pair — the push needs FORGE_PUSH_TOKEN bound as "forge:$TOKEN"')
for u in users:
    need(u == 'forge:${FORGE_PKG_TOKEN}',
         f'forgejo-publish --user value {u!r}, expected the literal cosmetic "forge:" paired with the bound FORGE_PKG_TOKEN step env (D31 carrier)')
# The automatic job token stays OFF the package legs: its permission check is
# an unimplemented upstream TODO, so a package push with it 401s (V-2).
for tok in ('github.actor', 'github.token', 'GITHUB_ACTOR', 'GITHUB_TOKEN'):
    need(tok not in fp_runs,
         f'forgejo-publish reads {tok} — the automatic workflow token is the REFUTED package credential (V-2; AGENTS credential law); FORGE_PUSH_TOKEN is load-bearing, never "fix" it back')

# Reserved-prefix keys and the automatic-token secrets may not appear anywhere
# (main-sync t5 law); nor may any forge URL literal (portability law — hosts
# ride runner-injected env / the server_url context inside steps).
# NOTE: FORGE_PUSH_TOKEN does not match the FORGEJO_ prefix pattern — it is a
# plain user-minted PAT name, not the reserved automatic-token name.
need(not re.findall(r'(?:secrets|vars)\.(?:GITHUB|FORGEJO)[A-Za-z0-9_]*', raw),
     'a reserved-prefix secret/var key reference exists (GITHUB_/FORGEJO_ prefixes are reserved)')
for lit in ('https://github.com', 'git.spencerslab.com', 'git.scifi.farm'):
    need(lit not in raw, f'URL literal {lit} in the file (no forge URL may be baked into the synced workflow)')
PY
then
  fail "t8: see the t8 detail above"
fi
ok "t8: each credential bound exactly once in its own leg (PUSH_TOKEN_GH | FORGE_PUSH_TOKEN); --user pairs forge: with the bound token; retired FJ bindings banned; no auto-token on the package legs; no reserved-prefix key, no URL literal"

# --- t9: needs-graph independence + explicit GitHub identity (AC8/AC9) -----------
if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
rel = jobs.get('release') or {}
fp = jobs.get('forgejo-publish') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t9: {msg}', file=sys.stderr)
        sys.exit(1)


def needs_of(job):
    n = job.get('needs')
    if n is None:
        return []
    return [n] if isinstance(n, str) else list(n)


rn, fn = needs_of(rel), needs_of(fp)
# D13: two independent parallel legs. A registry outage reddens ONLY
# forgejo-publish; the GitHub publish never waits on it and vice versa.
need('forgejo-publish' not in rn and 'release' not in fn,
     f'release needs {rn} / forgejo-publish needs {fn} — the two publish legs must not need each other (independent failure domains)')
# Both ride the bump output; publishing an un-bumped tree is the other broken shape.
need('bump' in rn and 'bump' in fn,
     f'a publish leg runs without needing bump (release {rn}, forgejo-publish {fn})')

rel_dump = yaml.dump(rel)
# The GITHUB_REPOSITORY owner trap: on the prod instance the forge context is
# CuratedForest/... — cr must be pointed at the explicit GitHub literals.
need('github.repository_owner' not in rel_dump and 'github.repository' not in rel_dump,
     'the release leg reads forge-context repository identity — owner/repo must be the explicit OwnYourIO/SpencersLab literals')
need('OwnYourIO' in rel_dump and 'SpencersLab' in rel_dump,
     'the release leg lacks the explicit OwnYourIO/SpencersLab literals')
rel_runs = '\n'.join(str(s.get('run', '')) for s in rel.get('steps', []) if isinstance(s, dict) and 'run' in s)
# The gh-pages push goes to the credential-slot GitHub remote (main-sync's
# proven shape), never to the Forgejo checkout's origin.
need('x-access-token:' in rel_runs,
     'the release leg has no x-access-token: credential-slot push (the gh-pages remote must ride PUSH_URL_GH + PUSH_TOKEN, not origin)')
PY
then
  fail "t9: see the t9 detail above"
fi
ok "t9: release and forgejo-publish are independent (both need bump); release names the GitHub literals and pushes Pages through the credential slot"

# --- t10: instance push target — derived host, LITERAL curatedforest (D31) ----
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
fp = jobs.get('forgejo-publish') or {}
fp_runs = '\n'.join(str(s.get('run', '')) for s in fp.get('steps', [])
                    if isinstance(s, dict) and 'run' in s)
fp_dump = yaml.dump(fp)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t10: {msg}', file=sys.stderr)
        sys.exit(1)


# Host is runtime-derived (GITHUB_SERVER_URL compat env or the forgejo
# server_url context inside a step — both sanctioned, both never an URL
# literal); the NAMESPACE is the literal lowercase curatedforest: repository
# names are lowercase-only (cf-6's container pushes carry this same literal),
# and the capitalized repository-context owner is not a valid package
# namespace, so no derivation may be attempted here (D31).
need(re.search(r'\$\{?GITHUB_SERVER_URL\b', fp_runs) or 'FORGE_SERVER_URL' in fp_dump or 'forgejo.server_url' in fp_dump,
     'forgejo-publish derives the endpoint host from neither $GITHUB_SERVER_URL nor the server_url step env — the location must be runtime-derived, never literal')
need('/api/packages/curatedforest/helm/api/charts' in fp_runs,
     'the instance upload URL is not the packages API charts route under the literal lowercase curatedforest namespace (D31: registry names are lowercase-only — cf-6 law, same literal)')
need('/api/packages/curatedforest/helm/index.yaml' in fp_runs,
     'the instance index read is not the /api/packages/curatedforest/helm/index.yaml route')
for derived in (r'\$\{?GITHUB_REPOSITORY\b', 'forgejo.repository', 'github.repository'):
    need(not re.search(derived, fp_dump),
         f'forgejo-publish reads repository context for the owner segment ({derived}) — the namespace is the curatedforest LITERAL; derivation would produce the capitalized CuratedForest form, which is not a valid package name (D31)')
PY
then
  fail "t10: see the t10 detail above"
fi
ok "t10: instance push URL = runtime-derived host + literal lowercase curatedforest on the helm api/index routes; no owner derivation attempted"

# --- t11: failure semantics ---------------------------------------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
runs = [(jn, s['run']) for jn, job in jobs.items()
        for s in (job or {}).get('steps', [])
        if isinstance(s, dict) and 'run' in s]


def need(cond, msg):
    if not cond:
        print(f'FAIL: t11: {msg}', file=sys.stderr)
        sys.exit(1)


need(runs, 'no run: blocks found')
for jn, r in runs:
    need(isinstance(r, str) and r.lstrip().startswith('set -euo pipefail'),
         f'{jn} has a run block not starting with set -euo pipefail (every inline replacement fails loudly)')
# Forgejo ignores job permissions: — a block that looks like authorization is
# dead config that a later reader will trust.
for jn, job in jobs.items():
    need('permissions' not in (job or {}), f'{jn} carries a permissions: block (dead config on Forgejo — drop it)')
PY
then
  fail "t11: see the t11 detail above"
fi
ok "t11: every run block starts set -euo pipefail; no job-level permissions: blocks"

# --- t12: shallow-clone guards (V-6) --------------------------------------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t12: {msg}', file=sys.stderr)
        sys.exit(1)


# The inline replacements fail LOUDEST on a shallow checkout: the detect range
# comes back empty, cr's lookup_latest_tag collapses to the root commit, and
# the bump loop cannot negotiate the push. main-sync.yaml is the same lesson
# already paid — every leg of this workflow needs full depth.
for jn in ('changes', 'test-build', 'bump', 'release', 'forgejo-publish'):
    steps = [s for s in (jobs.get(jn) or {}).get('steps', []) if isinstance(s, dict)]
    checkouts = [s for s in steps if str(s.get('uses', '')).startswith('actions/checkout@')]
    need(checkouts, f'{jn} has no checkout step')
    for s in checkouts:
        fd = (s.get('with') or {}).get('fetch-depth')
        need(fd in (0, '0'), f'{jn} checkout pins fetch-depth {fd!r}, expected 0')

# cr resolves "latest released" from TAGS: without them it re-publishes old
# versions or fails. Either the checkout fetches tags, or a run step fetches
# them before cr is invoked.
for jn, cr_pat in (('release', r'\bcr\s+(upload|index)'), ('forgejo-publish', r'\bcr\s+package')):
    steps = [s for s in (jobs.get(jn) or {}).get('steps', []) if isinstance(s, dict)]
    fetch_tags = any(str(s.get('uses', '')).startswith('actions/checkout@')
                     and (s.get('with') or {}).get('fetch-tags') in (True, 'true')
                     for s in steps)
    cr_at = next((i for i, s in enumerate(steps)
                  if 'run' in s and re.search(cr_pat, str(s.get('run', '')))), None)
    need(cr_at is not None, f'{jn} never invokes cr ({cr_pat}) — the leg cannot be ordered against the tag fetch')
    if fetch_tags:
        continue
    tag_fetch_at = next((i for i, s in enumerate(steps)
                         if 'run' in s and 'git fetch' in str(s.get('run', '')) and '--tags' in str(s.get('run', ''))), None)
    need(tag_fetch_at is not None and tag_fetch_at < cr_at,
         f'{jn}: no tag fetch precedes the cr invocation (checkout fetch-tags: true, or git fetch --tags before cr runs)')
PY
then
  fail "t12: see the t12 detail above"
fi
ok "t12: every consuming leg checks out at fetch-depth 0; the cr legs fetch tags before invoking cr"

# --- t13: outputs wiring — every steps.<id> has its id: in the same job ----------
# (fix-round BLOCKER: outputs referencing steps.detect with no `id: detect`
# step resolve empty, silently starving the matrix and every needs-consumer.)
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t13: {msg}', file=sys.stderr)
        sys.exit(1)


for jn, job in jobs.items():
    outs = (job or {}).get('outputs')
    if not outs:
        continue
    need(isinstance(outs, dict), f'{jn}.outputs is not a mapping')
    declared = {str(s['id']) for s in (job or {}).get('steps', [])
                if isinstance(s, dict) and s.get('id')}
    referenced = set()
    for expr in outs.values():
        referenced.update(re.findall(r'steps\.([A-Za-z0-9_-]+)\.outputs\.', str(expr)))
    missing = sorted(referenced - declared)
    need(not missing,
         f'{jn}.outputs references step id(s) {missing} that NO step in {jn} declares (declared ids: {sorted(declared) or "none"}) — the reference resolves empty')
PY
then
  fail "t13: see the t13 detail above"
fi
ok "t13: every steps.<id>.outputs.* cited by a job-level outputs: names an id: declared by a step in the same job"

# --- t14: instance upload POST-only, index read stays GET (fix-round, B2) ---------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
runs = '\n'.join(str(s.get('run', '')) for s in (jobs.get('forgejo-publish') or {}).get('steps', [])
                 if isinstance(s, dict) and 'run' in s)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t14: {msg}', file=sys.stderr)
        sys.exit(1)


# Rejoin backslash-continued curl commands, then split the curls by ROUTE:
# the charts route (directly, via a resolved shell variable, or by carrying
# a --upload-file payload) is the publish push; the index route is the
# read-before-upload churn guard.
cmds, pending = [], ''
for line in runs.splitlines():
    if line.rstrip().endswith('\\'):
        pending += line.rstrip()[:-1] + ' '
        continue
    cmds.append(pending + line)
    pending = ''
curls = [c for c in cmds if re.search(r'(?<![\w-])curl\b', c)]

upload_vars = [m.group(1) for m in re.finditer(r'^\s*([A-Za-z_]\w*)="[^"]*?/helm/api/charts[^"]*"\s*$', runs, re.M)]
read_vars = [m.group(1) for m in re.finditer(r'^\s*([A-Za-z_]\w*)="[^"]*?/helm/index\.yaml[^"]*"\s*$', runs, re.M)]


def refs(cmd, names):
    return any(re.search(r'\$\{?' + re.escape(n) + r'\b', cmd) for n in names)


uploads = [c for c in curls if '--upload-file' in c or '/helm/api/charts' in c or refs(c, upload_vars)]
reads = [c for c in curls if '/helm/index.yaml' in c or refs(c, read_vars)]

POST = r'(?:-X\s+POST|--request\s+POST)'
# Both sides of the method split are pinned: dropping either half of the
# reviewed shape reddens here.
need(uploads, 'no curl pushes to the instance charts route at all — the publish leg is gone')
for c in uploads:
    need(re.search(POST, c),
         f'charts-route upload is not -X POST ({c.strip()[:100]!r}) — Forgejo v15.0 serves /helm/api/charts POST-only (RESEARCH B2); --upload-file alone PUTs and fails')
need(reads,
     'the authenticated index read (GET on the /helm/index.yaml route) is gone — it is the reviewed retry-churn guard; both sides of the POST/GET split stay pinned')
for c in reads:
    need(not re.search(POST, c) and '--upload-file' not in c,
         f'the index read is no longer a plain GET ({c.strip()[:100]!r}) — a POST/payload turns the duplicate-check read into a write')
PY
then
  fail "t14: see the t14 detail above"
fi
ok "t14: charts-route uploads carry -X POST (v15 route is POST-only); the instance index read remains a plain GET"

# --- t15: index-parser VALUE semantics — dependency pins must not win -------------
# Both published-index readers are pure functions of index text, and both were
# proven WRONG on that text in review (old-branch BLOCKER 3: a naive line scan
# returns traefik's upstream dependency pin 42.1.3 for a real entry whose own
# version is 1.0.103, so the bump mints jump releases that every later bump
# chains from — public and unreclaimable). t7 pins the bump loop's control
# flow; nothing but this leg pins the VALUE either lookup feeds to
# `base = max(tree, published)`. It runs the extracted carriers offline against
# fixtures mirroring the live index shape — no network, no live fetch.
if ! python3 - "$WF" <<'PY'
import os, re, shutil, subprocess, sys, tempfile, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t15: {msg}', file=sys.stderr)
        sys.exit(1)


def run_blocks(job_name):
    return [str(s.get('run', '')) for s in (jobs.get(job_name) or {}).get('steps', [])
            if isinstance(s, dict) and 'run' in s]


def ver(s):
    parts = str(s).split('.')
    if len(parts) == 3 and all(p.isdigit() for p in parts):
        return tuple(int(p) for p in parts)
    return None


def heredoc(body, tag):
    """Pull one embedded <<'TAG' ... TAG heredoc out of a run block, dedented.
    The closing TAG sits at column 0 of the parsed run text (the YAML block
    scalar's base indent is stripped with everything else)."""
    m = re.search("<<'" + tag + r"'[ ]*\n(.*?)\n" + tag + r"[ ]*(?=\n|\Z)", body, re.S)
    if not m:
        return None
    lines = m.group(1).split('\n')
    indents = [len(l) - len(l.lstrip(' ')) for l in lines if l.strip()]
    base = min(indents) if indents else 0
    return '\n'.join(l[base:] if len(l) >= base and l[base:].strip() else l
                     for l in lines)


# Fixture built from the LIVE consumer-contract index (measured
# ownyourio.github.io/SpencersLab/index.yaml, fetched 2026-11-11 for shape
# only — the suite itself never goes online). cr sorts entry keys and keeps
# dependency keys alphabetically, so `version:` lands AFTER the dependencies
# block: the parser must not let the dep pin 42.1.3 beat the entry's own
# 1.0.103 no matter which line it meets first. The `alpha` twin proves
# entry-scoping, and the `forgejo` entry is this repo's real shape
# (dependency `forgejo` 17.3.1, chart version 1.0.7, dots inside the oci://
# repository URL): a published `forgejo` chart must never resolve to the
# dependency pin the index merely mentions.
FIXTURE = """apiVersion: v1
entries:
  traefik:
  - apiVersion: v2
    appVersion: 2.11.10
    created: "2026-10-25T22:43:39.18923588Z"
    dependencies:
    - name: traefik
      repository: https://traefik.github.io/charts
      version: 42.1.3
    - name: crowdsec
      repository: https://crowdsecurity.github.io/helm-charts
      version: 0.24.2
    digest: 5cfda61b2d72dd3a0a005debedb863b1827a0c0bce8db9886dabb0f46e908f46
    name: traefik
    urls:
    - https://github.com/OwnYourIO/SpencersLab/releases/download/traefik-1.0.103/traefik-1.0.103.tgz
    version: 1.0.103
  alpha:
  - apiVersion: v2
    appVersion: 1.0.0
    created: "2026-10-25T22:43:39.18923588Z"
    dependencies:
    - name: app-template
      repository: https://bjw-s-labs.github.io/helm-charts/
      version: 9.9.9
    digest: 0000000000000000000000000000000000000000000000000000000000000000
    name: alpha
    urls:
    - https://github.com/OwnYourIO/SpencersLab/releases/download/alpha-1.0.2/alpha-1.0.2.tgz
    version: 1.0.2
  forgejo:
  - apiVersion: v2
    appVersion: "15.0.9"
    created: "2026-10-25T22:43:39.18923588Z"
    dependencies:
    - name: forgejo
      repository: oci://code.forgejo.org/forgejo-helm/forgejo
      version: 17.3.1
    digest: 0000000000000000000000000000000000000000000000000000000000000000
    name: forgejo
    urls:
    - https://github.com/OwnYourIO/SpencersLab/releases/download/forgejo-1.0.7/forgejo-1.0.7.tgz
    version: 1.0.7
"""
# The same three entries with every entry-level `version:` line removed: only
# dependency pins are left. A carrier that keys off the dep name (cr writes
# the dependency's own name inside the dep block) would report published
# versions that were never published at all.
DEP_ONLY = re.sub(r'(?m)^    version: \S+\n', '', FIXTURE)

work = tempfile.mkdtemp(prefix='forgejo-release-t15.')
try:
    fx = {}
    for tag, text in (('fixture', FIXTURE), ('dep_only', DEP_ONLY)):
        path = os.path.join(work, tag + '.yaml')
        with open(path, 'w') as f:
            f.write(text)
        fx[tag] = path

    # --- carrier A: the bump leg's stdlib-python published-index parser ---
    python_src = None
    for body in run_blocks('bump'):
        if 'python3 - ' not in body:
            continue
        src = heredoc(body, 'PY')
        if src and re.search(r'^\s*published\s*=\s*\{', src, re.M):
            python_src = src
            break
    need(python_src is not None,
         'the bump leg embeds no published-index parser (a `published = {}` scan inside a <<PY heredoc) — this leg exists to pin its VALUE semantics')

    # Read the map back through an exec-wrapper: the parser source runs
    # byte-identical (full code path, side effects included), and the probe
    # lives in the wrapper's own file — not concatenated onto the parser's
    # final statement, which would inherit its indent. The wrapper reads
    # `published` out of the executed namespace; if a future parser renames
    # the map, this leg's message says so explicitly rather than silently
    # resolving None.
    parser_path = os.path.join(work, 'parser.py')
    with open(parser_path, 'w') as f:
        f.write(python_src)
    runner_path = os.path.join(work, 'runner.py')
    with open(runner_path, 'w') as f:
        f.write('import json, sys\n'
                'def _enc(v):\n'
                '    return ".".join(str(x) for x in v) if isinstance(v, (tuple, list)) else str(v)\n'
                'src_path, charts_json, index_path = sys.argv[1:4]\n'
                'sys.argv = [src_path, charts_json, index_path]\n'
                'ns = {"__name__": "__main__"}\n'
                'exec(compile(open(src_path).read(), src_path, "exec"), ns)\n'
                'assert "published" in ns, "no top-level published map in the parser namespace"\n'
                'sys.stderr.write("@@T15@@" + json.dumps({k: _enc(v) for k, v in ns["published"].items()}) + "\\n")\n')

    def run_python(index_file):
        r = subprocess.run([sys.executable, runner_path, parser_path, '[]', index_file],
                           capture_output=True, text=True)
        need(r.returncode == 0,
             f'bump parser could not run against {os.path.basename(index_file)} ({r.stderr.strip()[-300:]!r}) — the leg runs the landed carrier as-is; fix the carrier or route the change, do not bypass it')
        m = re.search(r'@@T15@@(\{.*\})', r.stderr)
        need(m is not None,
             f'bump parser exposed no published map (@@T15@@ probe missing — parser namespace lacks the top-level `published` assignment the bump decision reads)')
        try:
            out = __import__('json').loads(m.group(1))
        except Exception:
            need(False, f'bump parser probe emitted unparsable JSON ({m.group(1)[:200]!r})')
        return {k: ver(v) for k, v in out.items()}

    got = run_python(fx['fixture'])
    need(got.get('traefik') == (1, 0, 103),
         f"bump parser: traefik resolved to {got.get('traefik')!r}, expected the ENTRY version (1,0,103) — 42.1.3 is the upstream dependency pin inside the same entry's dependencies: block (measured on the live index); winning this lookup mints traefik-42.1.4 jump releases that every later bump chains from")
    need(got.get('alpha') == (1, 0, 2),
         f"bump parser: alpha resolved to {got.get('alpha')!r}, expected the entry version (1,0,2) — the app-template dep pin 9.9.9 must not leak either way")
    need(got.get('forgejo') == (1, 0, 7),
         f"bump parser: forgejo resolved to {got.get('forgejo')!r}, expected (1,0,7) — its Chart.yaml is exactly this repo's real shape (dependency forgejo 17.3.1, chart 1.0.7, oci:// repository with dots in the URL); base=max(tree,published) would jump 17.3.2 on first fire")
    got_dep = run_python(fx['dep_only'])
    phantoms = {k: v for k, v in got_dep.items() if k in ('traefik', 'alpha', 'forgejo')}
    need(not phantoms,
         f'bump parser resolved entry names from the deps-only index ({phantoms}) — versions that were NEVER published read as published; only entry-level name+version pairs may key the lookup')

    # --- carrier B: the forgejo-publish index pre-check's awk program ---
    Q = chr(39)  # the workflow wraps the awk program in single quotes
    awk_src = None
    for body in run_blocks('forgejo-publish'):
        for m in re.finditer('awk -v c="\\$chart" -v v="\\$version" ' + Q + '(.*?)' + Q, body, re.S):
            prog = m.group(1)
            if 'name:' in prog and 'version:' in prog and ('nind' in prog or 'RLENGTH' in prog):
                awk_src = prog
    need(awk_src is not None,
         'the forgejo-publish upload step embeds no awk index pre-check pairing entry name/version by indentation (RLENGTH/nind) — the overwrite-on-repush anti-churn guard (RESEARCH B4 confirmed: Forgejo CreatePackageOrAddFileToExisting sets OverwriteExisting=true) lives or dies on this lookup')

    def awk_hit(chart, version, index_file):
        # exit 0 == the pair IS present in the index (that is how the upload
        # step reads it: already-published, so skip the re-push).
        r = subprocess.run(['awk', '-v', f'c={chart}', '-v', f'v={version}', awk_src, index_file],
                           capture_output=True, text=True)
        return r.returncode == 0, r

    for name, v in (('traefik', '1.0.103'), ('alpha', '1.0.2'), ('forgejo', '1.0.7')):
        hit, r = awk_hit(name, v, fx['fixture'])
        need(hit, f'awk pre-check does not find the real entry {name} {v} (exit {r.returncode}) — a retry would re-push and OVERWRITE the published package')
    for name, v in (('traefik', '42.1.3'), ('forgejo', '17.3.1'), ('app-template', '9.9.9'),
                    ('traefik', '9.9.9')):
        hit, _ = awk_hit(name, v, fx['fixture'])
        need(not hit,
             f'awk pre-check pairs {name} with {v} on the live-shaped fixture — that is a dependency pin (or a stale entry match bleeding across entries), not a published {name}; the guard would skip pushes that must happen and the class is exactly the bump parser contamination')
    for name, v in (('traefik', '42.1.3'), ('alpha', '9.9.9'), ('forgejo', '17.3.1')):
        hit, _ = awk_hit(name, v, fx['dep_only'])
        need(not hit,
             f'awk pre-check finds {name} {v} in the deps-only index — the lookup keys off lines that carry no entry version')
finally:
    shutil.rmtree(work, ignore_errors=True)
PY
then
  fail "t15: see the t15 detail above"
fi
ok "t15: both index carriers resolve ENTRY versions on dep-block fixtures (python bump parser + awk pre-check), never dependency pins"

# --- t16: output writes carry the GITHUB_OUTPUT/FORGEJO_OUTPUT compat idiom -----
# Forgejo exports the GITHUB_* compatibility family but the reference names
# the FORGEJO_* fallback (the same idiom containers-build.yaml writes its
# outputs with); a bare "$GITHUB_OUTPUT" write dies on any engine build that
# drops the compat export, and the detect output is exactly what must not
# vanish silently.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
IDIOM = '${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}'

writes, bare = 0, []
for jn, job in jobs.items():
    for s in (job or {}).get('steps', []):
        if not isinstance(s, dict) or 'run' not in s:
            continue
        for line in str(s['run']).splitlines():
            if '>>' not in line or ('GITHUB_OUTPUT' not in line and 'FORGEJO_OUTPUT' not in line):
                continue
            writes += 1
            if IDIOM not in line:
                bare.append(f'{jn}: {line.strip()[:90]!r}')

if writes == 0:
    print('FAIL: t16: no $GITHUB_OUTPUT write found anywhere — the detect leg must publish CHARTS/HAS_CHANGES through the output file', file=sys.stderr)
    sys.exit(1)
if bare:
    print(f'FAIL: t16: output write(s) missing the "${{GITHUB_OUTPUT:-$FORGEJO_OUTPUT}}" compat idiom: {bare} — a bare $GITHUB_OUTPUT is the engine-compat bet the cf-6 workflows already refused to make', file=sys.stderr)
    sys.exit(1)
print(f'  ({writes} output write(s), all compat-guarded)')
PY
then
  fail "t16: see the t16 detail above"
fi
ok "t16: every output write uses \${GITHUB_OUTPUT:-\$FORGEJO_OUTPUT} (the cf-6 containers-build idiom); none relies on the bare GITHUB_* export"

# --- t17: the gh-pages publish rides the fetched tracking ref --------------------
# cr's pages worktree reads the LOCAL remote-tracking ref and never fetches,
# so the runtime-added publish remote must be fetched (explicit refspec)
# BEFORE cr index — and cr index must be told which remote. Without the
# fetch, cr index --push writes the index onto the FORGEJO checkout (the
# silent-wrong-publish trap the wrapper also had); pinning the ORDER keeps a
# later reorder from reintroducing it.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
rel_runs = '\n'.join(str(s.get('run', '')) for s in (jobs.get('release') or {}).get('steps', [])
                     if isinstance(s, dict) and 'run' in s)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t17: {msg}', file=sys.stderr)
        sys.exit(1)


# Command-line anchored (continuation-joining): the why-comments also NAME
# these commands, and a substring search would order against the prose.
lines = [l.strip() for l in rel_runs.splitlines()]


def cmd_line(prefix, must_contain=None):
    i = next((k for k, l in enumerate(lines) if l.startswith(prefix)
              and (must_contain is None or must_contain in l)), None)
    if i is None:
        return None
    return i


i_remote = cmd_line('git remote add publish')
i_fetch = cmd_line('git fetch publish', 'refs/heads/gh-pages:refs/remotes/publish/gh-pages')
i_index = cmd_line('cr index')
need(i_remote is not None, 'no git remote add publish — the Pages push must ride the credential-slot remote, not origin')
need(i_fetch is not None,
     'no explicit tracking-ref fetch of gh-pages through the publish remote (git fetch publish refs/heads/gh-pages:refs/remotes/publish/gh-pages) — cr builds its pages worktree from the LOCAL remote-tracking ref and never fetches it, so without this line cr index pushes to the wrong forge')
need(i_index is not None, 'no cr index invocation in the release leg')
need(i_remote < i_fetch < i_index,
     f'publish-remote fetch mis-ordered (remote add line {i_remote}, fetch line {i_fetch}, cr index line {i_index}) — the fetch must sit between adding the remote and invoking cr index')
cmd = lines[i_index]
k = i_index
while cmd.endswith('\\'):
    k += 1
    cmd += ' ' + lines[k]
need('--remote publish' in cmd,
     f'cr index does not name --remote publish ({cmd[:120]!r}) — its default remote is origin, the Forgejo checkout (the same default-origin trap the wrapper action carried)')
PY
then
  fail "t17: see the t17 detail above"
fi
ok "t17: gh-pages publishes through the credential-slot remote with its tracking ref fetched before cr index, which names --remote publish"

# --- t18: detect survives the empty/all-zero before (Forgejo payload caveat) -------
# Forgejo push payloads can OMIT event.before or send the all-zero first-push
# form (RESEARCH A3); either way the range diff must fall back to HEAD^ rather
# than diff against an unusable bound — the same lesson containers-build.yaml
# ships. An unresolvable bound that silently resolves to nothing would make
# every merge look like "no chart changed".
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
det = '\n'.join(str(s.get('run', '')) for s in (jobs.get('changes') or {}).get('steps', [])
                if isinstance(s, dict) and 'run' in s)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t18: {msg}', file=sys.stderr)
        sys.exit(1)


need(re.search(r'-z\s+"?\$\{?EVENT_BEFORE', det),
     'the detect loop does not test an EMPTY event.before — Forgejo payloads may omit the key entirely (A3), and an unset bound would empty the range diff into a silently-green no-changes run')
need('0000000000000000000000000000000000000000' in det and 'HEAD^' in det,
     'the all-zero first-push before does not fall back to HEAD^ — the same guard containers-build.yaml ships')
need(re.search(r'git\s+diff\s+--name-only\s+[^\n]*HEAD\^', det),
     'no HEAD^ range diff on the fallback path')
need('"${EVENT_BEFORE}"' in det or '${EVENT_BEFORE}' in det,
     'the normal range never uses the payload bounds')
PY
then
  fail "t18: see the t18 detail above"
fi
ok "t18: empty-before AND all-zero-before both route to the HEAD^ fallback; a real range still diffs EVENT_BEFORE..EVENT_SHA"

# --- t19: cr is one pinned, checksum-verified install shared by both cr legs -------
# The wrapper action's mirror absence forced the direct CLI (D3); the pin +
# sha256 pair is what the review verified against the upstream checksums.txt,
# and the download URL composes its host from RELEASES_HOST so the
# no-URL-literal law (t8) holds. A leg installing an unpinned or unhashed cr
# reopens the supply-chain question the pin closed.
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
jobs = doc.get('jobs') or {}
env = doc.get('env') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t19: {msg}', file=sys.stderr)
        sys.exit(1)


need(str(env.get('CR_VERSION')) == '1.10.1',
     f'workflow env CR_VERSION is {env.get("CR_VERSION")!r}, expected the review-verified 1.10.1 pin')
need(str(env.get('CR_SHA256')) == 'ce46baf9975d10193b7070b2b7406750c3f664181e36df3f3bbb4a00be40dc1b',
     'workflow env CR_SHA256 does not match the linux_amd64 checksum the review verified against the release checksums.txt')
need(str(env.get('RELEASES_HOST')) == 'github.com',
     'RELEASES_HOST missing/wrong — the asset host rides the composed variable precisely so no scheme-qualified URL literal enters the file (t8 law)')
for jn in ('release', 'forgejo-publish'):
    blob = '\n'.join(str(s.get('run', '')) for s in (jobs.get(jn) or {}).get('steps', [])
                     if isinstance(s, dict) and 'run' in s)
    need('${RELEASES_HOST}' in blob and 'helm/chart-releaser' in blob,
         f'{jn}: no cr install via the composed ${ "{RELEASES_HOST}" } asset URL')
    need('sha256sum -c' in blob and '${CR_SHA256}' in blob,
         f'{jn}: the cr archive is not sha256-verified against the pinned ${ "{CR_SHA256}" }')
    need('${CR_VERSION}' in blob, f'{jn}: the cr download does not ride the single shared CR_VERSION pin')
PY
then
  fail "t19: see the t19 detail above"
fi
ok "t19: cr v1.10.1 + its verified sha256 ride one shared workflow env pair; both cr legs install through the composed host and verify the hash"

printf 'PASS: forgejo-release checks (%d ok)\n' "$checks"
