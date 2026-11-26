#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/build-charts.yaml (cf-55 on the
# REBUILT branch — DECISIONS D31/D32 reconcile): the chart bump+publish
# pipeline running on Forgejo Actions with DUAL publish, reconciled to the
# cf-6 conventions that landed on main. The invariants pinned here are the
# ones that keep the design safe — the ROLE-MEMBERSHIP guard on every job
# (contains(vars.ROLE, 'prod'), the repo-wide shape of the AGENTS.md Forge
# Actions law: guards test membership, never equality, and never an instance
# URL; this workflow stays NARROW on unset — a bump/publish pipeline must
# not fire unconfigured, the opposite polarity of build-containers.yaml's
# deliberate widen), the bump leg being a single-writer idempotent
# fast-forward-only loop (concurrency is best-effort; the loop is the safety
# property), the per-direction credential topology (PUSH_TOKEN_GH serves the
# GitHub release leg only; the instance package push rides the shipped
# FORGE_PUSH_TOKEN human-PAT with the cosmetic "forge:" username and the
# literal lowercase curatedforest namespace — the Actions job token cannot
# write packages, and the retired PUSH_TOKEN_FJ/FJ_PACKAGE_USER pair must
# never re-enter as a binding), the output-write compat idiom
# (${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}, the same one build-containers.yaml
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
# Fix round (2026-11-21, chunks/C07.md; D41/D42/D43): 20 legs. t5 flipped to
# the checkout-only allow-list with azure/setup-helm on the file-wide bans;
# t19 re-turned from the runtime-cr contract to the BAKED-toolchain contract
# (absence-of-installs + presence-of-work, and per D43 deliberately NO
# presence-step legs — the vacated slots must stay empty); t20 newly pins
# the bump leg's --retry-hardened published-index fetch. Every other leg is
# byte-unchanged from the rebuild.
#
# Fix round 2 (2026-11-23, chunks/C08.md; D45): 21 legs. t21 added — the
# repo-add loop COMPLETENESS replay: each carrier, extracted per job, must
# emit EVERY URL-shaped dependency row through the shipped `tail +2 | head
# -n -1` arithmetic over live-measured fixture shapes, and the derived repo
# set must cover every http(s) Chart.lock URL of the four victim charts (the
# shipped program-`exit` registered only each chart's first row and the
# owner's release re-run died in cr package naming the unregistered repos).
# t6's comment is re-truthed to the per-row contract; t1-t20 are
# byte-unchanged.
#
# Round 4 (2026-11-25, chunks/C09.md + C10.md; D47/D49): 26 legs, written
# RED-FIRST against the pre-heal/pre-calendar workflow (the drift trio
# {base, traefik, traefik-zerotrust} is live at HEAD). C09: t22 pins the
# bump-job full-tree lock heal (glob loop placed after the main-tip reset
# and before the version derivation, locks staged beside the bumps, the
# commit guarded on staged content, the message naming the heal set); t23
# pins the test-build build->update flip and the file-wide code-line
# absence of the aborting verb; t24 is the hermetic full-tree
# lock-consistency projection (cf-135 dev-forgejo-runner t10's contract
# made offline — t10 STAYS as the live-helm witness, untouched). C10: t25
# pins the calendar bump — static (one unpadded `date -u +%Y.%-m` stamp
# per run, a stamp binding into python, the fail-loud tree-ahead arm,
# ver()/pairing-parser retention) plus the executed walk battery replayed
# against MUTANT fixtures with a stubbed stamp (the Masterminds
# leading-zero trap gets its own case); t26 pins the post-rewrite
# AGENTS.md + .rulesync law pair: calendar language, the unpadded-month
# statement, and the brand-new-chart seed as Y.M.1 per the D49 owner
# override. t15 is re-aimed in place (C10.md): the pairing behavior it
# replays is byte-preserved, its ROLE is re-truthed from derivation term
# to the skip-when-already-published collision guard.
#
# Round 5 (2026-11-26, chunks/C13.md + C14.md + C15.md; D52-D59): 34 legs,
# written RED-FIRST against the pre-fix workflow — the Nov-25 fire died on
# exactly the parse shape t27/t28 replay executed. C13: t27 batteries the
# test-build Patch-bump heredoc (clean line, tolerated comment surviving the
# rewrite, garbage refusing, the column-0 anchor keeping dependency pins
# out, `#nospace` still refusing); t28 extends the t25 CASES-walk machinery
# to the bump-derivation heredoc with the commenttolerant/garbagetail pair;
# t29 pins the class ban — no live charts/*/Chart.yaml version line carries
# a trailing comment. C14: t30/t31 execute the shared ci/last-built
# resolver and the marker..sha chain against scratch bare remotes (the
# silent empty-before fallback of the old t18 is RE-AIMED to the loud-die
# law, the marker==sha verified-empty info line replaces the anomaly
# warning), t32 pins the single advance WRITER as a two-state law (C14's
# interim build-charts job ↔ C15's main-sync aggregate — exactly one
# writer, D54) and t33 the bump_sha output plumbing. C15: t2 re-aims to
# the called-only trigger (push-era paths pins die with the push arm,
# D56) and t34 pins the on.workflow_call.outputs declaration. Re-aimed
# t2/t18 are red until their own chunk lands.
#
# Carried by C09's flip commit, NOT by this wave (chunk Files-in-scope):
# t19's test-build cmds list swaps 'helm dependency build' -> 'helm
# dependency update' exactly when the workflow flips (AC2's
# green-at-merge law); the guard-trio admit joins for the three healed
# Chart.lock paths join at the same commit. t1-t21 are otherwise
# byte-stable except this header, the t15 block, and that one future
# t19 line.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-build-charts.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF=".forgejo/workflows/build-charts.yaml"

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

# --- t2: trigger — called-only (C15 re-aim, D56) ---------------------------
# The push arm died with owner directive 4: main-sync's next run calls this
# workflow, and path filtering lives in the marker..sha detection instead
# (plan Round-5 landing §3). The push-era branches/paths pins are DELETED
# with the arm they pinned; no dispatch and no PR ever (t2's historic "no
# dispatch, no PR" clause re-aims to "call only"). Red until C15 lands:
# the shipped file is still push-triggered.
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
trig = doc.get(True) or doc.get('on')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t2: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(trig, dict), 'no top-level on: mapping')
need(set(trig) == {'workflow_call'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly workflow_call (C15/D56: build-charts ends called-only — a surviving push arm keeps the pre-call detection era alive, a dispatch/PR arm contradicts the "no dispatch, no PR" law)')
PY
then
  fail "t2: see the t2 detail above"
fi
ok "t2: on: is exactly {workflow_call} — push arm and paths filter retired with it, filtering rides the marker..sha detection (C15, D56)"

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
# The job inventory the chunk prescribes; a renamed or extra job reddens
# here. C14's INTERIM advance-marker job (deleted again by C15's aggregate)
# is the sanctioned sixth name for exactly one wave — the writer law lives
# in t32, not here; anything else extra or missing is a rogue surface.
INVENTORY = {'changes', 'test-build', 'bump', 'release', 'forgejo-publish'}
need(set(jobs) in (INVENTORY, INVENTORY | {'advance-marker'}),
     f'jobs keys are {sorted(jobs)}, expected the five-job inventory or the five plus C14\'s interim advance-marker (a sixth name beyond it, or a missing one, is an unpinned surface)')
for name, job in jobs.items():
    if_expr = str((job or {}).get('if') or '')
    if name == 'advance-marker':
        # C14's interim job: membership guard PLUS the has-changes term
        # (t32 pins the full shape); the bare-GUARD law below is for the
        # permanent jobs and does not apply to the carved-out sixth.
        need(if_expr.startswith(GUARD) and "has_changes == 'true'" in if_expr,
             f'advance-marker.if is {if_expr!r} — expected {GUARD!r} extended with the has-changes term (C14 task 5)')
        continue
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
        # unset; the `vars.ROLE == null` widen clause (build-containers's
        # deliberate opposite) has no place here.
        need('== null' not in expr and '!= null' not in expr,
             f'a live if carries an unset-widen clause ({expr!r}) — build-charts.yaml is narrow-on-unset by the bump-is-a-state-change reading (D31/D32)')
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
ok "t3: the five prescribed jobs (plus C14's carved-out interim advance-marker where present), every permanent job guarded on contains(vars.ROLE, 'prod') byte-exact, the advance job on guard+has-changes (equality/null-widen live guards absent); dev guard absent; substring caveat present"

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
ALLOWED = ('actions/checkout@',)


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
         f'{jn}: uses {u!r} — only the mirror-confirmed actions/checkout may be used; the baked job image (C05/C06) means no workflow step installs anything (D33)')
    need('github.com' not in u and 'http' not in u,
         f'{jn}: absolute-URL uses {u!r} (unproven runner egress for clones)')
# The four wrapper actions the move replaced inline stay retired, and the fix
# round joins them with azure/setup-helm: that action downloads helm from
# get.helm.sh INSIDE the job — the read ECONNRESET that killed the release
# pipeline's first fire — and the tool it installed is now baked into the
# image, so the name may not survive anywhere, uses, runs or comments.
for banned in ('dorny/paths-filter', 'EMAsphere', 'EndBug', 'chart-releaser-action', 'azure/setup-helm'):
    need(banned not in raw, f'{banned} appears in the file (retired-action / retired-installer law: the inline replacements and the baked toolchain are mandatory)')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: every uses is actions/checkout and nothing else; azure/setup-helm and the four retired actions appear nowhere in the file"

# --- t6: hardened repo-add loop in every dependency-resolving leg (AC5) --------
if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}

# Legs that run helm against chart dependencies. The hardened loop's contract
# is the first URL-shaped field OF EACH dependency row, every row emitting:
# a carrier that ends its print block with a program terminator registers
# only each chart's FIRST row and cr package's lock-driven Build dies on the
# rest (cf-77 r2's exit-vs-next defect, D45). This leg pins the loop's TOKENS
# per job; the all-rows completeness replay is t21. A leg that runs `helm
# dependency list` without the field guard re-breaks on any empty-REPOSITORY
# subchart row.
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
     'bump has a strategy: — the matrix bump was the known-broken shape (the pre-rename builder TODO); the fix is ONE job looping the changed charts (D4)')
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

# File-wide: never force, never merge, never rewrite. The merge ban carries
# the round-5 carve-out: `git merge-base --is-ancestor` is the marker
# tolerance's ancestry CLASSIFY (C14 task 2, D54) — a read, not a write —
# while `git merge` as a verb is what V-4's FF-only loop forbids.
for pat in ('--force', '+refs', 'git push -f'):
    n = raw.count(pat)
    need(n == 0, f'{pat!r} occurs {n} time(s) file-wide, expected zero (a refused non-FF re-loops; it never overwrites)')
n = len(re.findall(r'git\s+merge(?!-base)', raw))
need(n == 0, f'git merge (non-base) occurs {n} time(s) file-wide, expected zero (a refused non-FF re-loops; it never overwrites; merge-base --is-ancestor is the tolerated classify)')

# The bump rides the checkout's default same-repo credentials — the automatic
# automatic-token carve-out is the loop-guard history (R3/D5 — C15 moved
# the guard to marker idempotence) — so no secret may be named in it.
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
# version is 1.0.103). C10 (D47.4) demotes the index from a derivation term
# to the skip-when-already-published COLLISION GUARD of the calendar walk:
# the guard reads exactly this map, so a pin-contaminated entry would either
# re-mint a published version or skip a bump that must happen — the phantom
# class is unchanged, its consumer is. t25 pins the walk arithmetic; nothing
# but this leg pins the VALUE the guard is fed. It runs the extracted carriers
# offline against fixtures mirroring the live index shape — no network, no
# live fetch.
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
    # C10 re-aim: once the carrier binds a clock stamp (argv/env), the
    # exec-wrapper must feed it a stub too — under the pre-C10 parser both
    # stubs are inert.
    stamp_names = sorted(set(re.findall(
        r'''environ(?:\.get)?[\(\[]\s*["']([A-Za-z_][A-Za-z0-9_]*)["']''', python_src))) if 'environ' in python_src else []
    stamp_env = {n: ('2026' if n.endswith('_Y') else '11' if n.endswith('_M') else '2026.11')
                 for n in stamp_names}
    for g in ('CALVER_STAMP', 'CALVER_Y', 'CALVER_M', 'CAL_STAMP', 'CAL_Y', 'CAL_M'):
        stamp_env[g] = '2026' if g.endswith('_Y') else '11' if g.endswith('_M') else '2026.11'
    parser_path = os.path.join(work, 'parser.py')
    with open(parser_path, 'w') as f:
        f.write(python_src)
    runner_path = os.path.join(work, 'runner.py')
    with open(runner_path, 'w') as f:
        f.write('import json, os, sys\n'
                'def _enc(v):\n'
                '    return ".".join(str(x) for x in v) if isinstance(v, (tuple, list)) else str(v)\n'
                'for _k, _v in ' + repr(stamp_env) + '.items():\n'
                '    os.environ.setdefault(_k, _v)\n'
                'src_path, charts_json, index_path = sys.argv[1:4]\n'
                '_s = open(src_path).read()\n'
                'sys.argv = [src_path, charts_json, index_path] + (["2026", "11"] if "sys.argv[4]" in _s else ["2026.11", "2026", "11"] if "sys.argv[3]" in _s else [])\n'
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
         f"bump parser: traefik resolved to {got.get('traefik')!r}, expected the ENTRY version (1,0,103) — 42.1.3 is the upstream dependency pin inside the same entry's dependencies: block (measured on the live index); the calendar walk's collision guard (C10) reads this map, and a dep-pin entry here walks N past versions that were never published")
    need(got.get('alpha') == (1, 0, 2),
         f"bump parser: alpha resolved to {got.get('alpha')!r}, expected the entry version (1,0,2) — the app-template dep pin 9.9.9 must not leak either way")
    need(got.get('forgejo') == (1, 0, 7),
         f"bump parser: forgejo resolved to {got.get('forgejo')!r}, expected (1,0,7) — its Chart.yaml is exactly this repo's real shape (dependency forgejo 17.3.1, chart 1.0.7, oci:// repository with dots in the URL); a dep-pin read as published would have the collision guard skip bumps that never happened")
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
# the FORGEJO_* fallback (the same idiom build-containers.yaml writes its
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
ok "t16: every output write uses \${GITHUB_OUTPUT:-\$FORGEJO_OUTPUT} (the cf-6 build-containers idiom); none relies on the bare GITHUB_* export"

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

# --- t18: the marker..sha chain arms (C14 re-aim of the empty-before era) ----
# The shipped silent HEAD^-fallback on an empty EVENT_BEFORE is DEAD law
# (D53: no real push payload sends one; the containers law the chunk mirrors):
# the chain must route MARKER set → marker..sha, all-zero before (marker-side
# only) → tip-only + ::warning:: announce, empty before → LOUD die, else
# before..sha (bootstrap-era). Red until C14 lands the resolver + chain;
# after C15 the same arms stand with the marker as the only push-side base
# (a called run carries no event.before), so this leg spans both eras.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
det = '\n'.join(str(s.get('run', '')) for s in (jobs.get('changes') or {}).get('steps', [])
                if isinstance(s, dict) and 'run' in s)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t18: {msg}', file=sys.stderr)
        sys.exit(1)


need(re.search(r'MARKER', det),
     'the changes-job chain never reads a marker value — the marker..sha detection this chunk adopts is the whole delivery-loss heal (C14 task 2), a chain still anchored on the payload alone re-dies like the Nov-25 fire')
# Arm ORDER is the law: marker first, then the all-zero tip-only announce,
# then the empty-before die, then the before-chain fallback.
i_marker = det.find('MARKER')
i_zero = det.find('0000000000000000000000000000000000000000')
i_die = re.search(r'\b(die|exit 1)\b', det[i_zero:] if i_zero >= 0 else '')
need(i_marker >= 0 and i_zero > i_marker,
     'the all-zero branch does not follow the marker read — marker must win over every payload fallback (C14: MARKER set → diff marker..sha first)')
need(i_zero >= 0 and '::warning::' in det[i_zero:i_zero + 600],
     'the all-zero first-push route carries no ::warning:: tip-only announce — the narrowing must name itself in the log (containers :199-204 semantics)')
need(re.search(r'-z\s+"?\$\{?EVENT_BEFORE', det) and i_die is not None,
     'an empty EVENT_BEFORE is not a LOUD die — the silent HEAD^-fallback the shipped guard hides is exactly the wrong-accessor mask the containers law buried ("no push payload sends one")')
need(re.search(r'git\s+diff\s+--name-only[^\n]*HEAD\^', det),
     'no HEAD^ range diff on the tip-only route — the first-push fallback stays HEAD^..HEAD scoped to charts/')
need('"${EVENT_BEFORE}"' in det or '${EVENT_BEFORE}' in det,
     'the before-fallback arm never uses the payload bound — with a marker absent but a real before, before..sha must still resolve (bootstrap-era)')
need('-- charts/' in det and "cut -d'/' -f2" in det,
     'the CHARTS filter moved — cut -d/ -f2 + DNS-safe + Chart.yaml gate stay EXACTLY (the coder-templates collapse is card #56\'s filter decision, not this chunk\'s)')
PY
then
  fail "t18: see the t18 detail above"
fi
ok "t18: chain arms route marker→tip-only(announce)→loud-die-on-empty→before..sha, in order, with the charts/ filter and DNS-safe/Chart.yaml gates byte-stable (C14 re-aim; t31/t30 replay it executed)"

# --- t19: the toolchain rides the baked job image — nothing installs, and the vacated slots stay empty ---
# Fix-round flip of the runtime-cr contract (C07, D37/D38/D43): the pin pair
# migrated to the C05 Dockerfile ARGs and the workflow env block died with it.
# D43 retired the replacement presence-check steps too, so what is pinned
# here is absence-of-installs plus presence-of-WORK: the real cr/helm
# invocations ARE the toolchain check (a mis-baked image dies on them with
# command-not-found — loud, early), and the literal bans are what keep a
# download from creeping back into any lane.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
doc = yaml.safe_load(raw) or {}
jobs = doc.get('jobs') or {}
env = doc.get('env') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t19: {msg}', file=sys.stderr)
        sys.exit(1)


for key in ('CR_VERSION', 'CR_SHA256', 'RELEASES_HOST'):
    need(key not in env,
         f'the top-level env still carries {key} — the cr pin pair lives in the containers/forgejo-runner Dockerfile ARGs now (D37/D38)')
# File-wide, comments included: every literal that described a run-time
# download. chart-releaser_ is the underscore asset-naming form precisely so
# prose may still name the helm/chart-releaser depName.
for lit in ('CR_VERSION', 'CR_SHA256', 'RELEASES_HOST', '1.10.1',
            'ce46baf9975d10193b7070b2b7406750c3f664181e36df3f3bbb4a00be40dc1b',
            'get.helm.sh', 'chart-releaser_', 'cr.tar.gz', '.cr-bin'):
    need(lit not in raw,
         f'{lit!r} appears in the file — the bake retired every run-time install fact; a survivor re-arms the egress class that killed the first fire (D33)')
for jn, job in jobs.items():
    steps = [s for s in ((job or {}).get('steps') or []) if isinstance(s, dict)]
    for s in steps:
        name = str(s.get('name', ''))
        need(not re.search(r'set up helm|install cr|verify toolchain|toolchain (check|presence)', name, re.I),
             f'{jn}: step {name!r} is an installer or presence-check step — D43 rules the vacated slots EMPTY')
    blob = '\n'.join(str(s.get('run', '')) for s in steps)
    need('helm version' not in blob and 'cr --version' not in blob,
         f'{jn}: a run block gates on helm version / cr --version — presence assertions retired with the Verify steps (D43)')


def runs(jn):
    return '\n'.join(str(s.get('run', '')) for s in ((jobs.get(jn) or {}).get('steps') or [])
                     if isinstance(s, dict))


tb, rel, fj = runs('test-build'), runs('release'), runs('forgejo-publish')
for cmd in ('helm dependency list', 'helm repo add', 'helm dependency update',
            'helm lint', 'helm package'):
    need(cmd in tb,
         f'test-build no longer runs {cmd!r} — the flip cannot be satisfied by deleting the work the baked helm serves')
for cmd in ('helm dependency list', 'helm repo add', 'cr package', 'cr upload', 'cr index'):
    need(cmd in rel, f'release no longer runs {cmd!r} — the invocation sites are the de-facto toolchain check (D43)')
for cmd in ('helm dependency list', 'cr package'):
    need(cmd in fj, f'forgejo-publish no longer runs {cmd!r} — same law on the instance leg')
PY
then
  fail "t19: see the t19 detail above"
fi
ok "t19: no cr env pair, no install/pin literals, no installer or presence-check steps anywhere; every baked helm/cr invocation site of the shipped contract still runs"

# --- t20: the bump leg's published-index fetch is retry-hardened (D37) -------
# The one egress the bake cannot retire: the bump loop reads the PUBLISHED
# INDEX — data, not a tool — so it rides bounded hardening instead of the
# bare fetch that would let a transient Pages failure empty the bump.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}
jobs = doc.get('jobs') or {}
blob = '\n'.join(str(s.get('run', '')) for s in ((jobs.get('bump') or {}).get('steps') or [])
                 if isinstance(s, dict))


def need(cond, msg):
    if not cond:
        print(f'FAIL: t20: {msg}', file=sys.stderr)
        sys.exit(1)


flat = re.sub(r'\\\n[ \t]*', ' ', blob)
fetch = [l for l in flat.splitlines() if 'curl' in l and 'PUBLISHED_INDEX' in l]
need(fetch,
     'the bump leg no longer curls $PUBLISHED_INDEX — the published-index data read is part of the shipped bump contract (the t7 loop and the t15 parser depend on it)')
for l in fetch:
    need('--retry' in l,
         f'the published-index fetch lacks --retry: {l.strip()[:120]!r}')
PY
then
  fail "t20: see the t20 detail above"
fi
ok "t20: the bump leg's published-index curl carries --retry (the un-bakeable data egress gets bounded hardening, D37)"

# --- t21: repo-add loop COMPLETENESS — every URL-shaped row registers (fix round 2, D45) ---
# The owner's release re-run proved t6's token pins are not completeness: the
# Add-repositories step ran green while registering only the FIRST URL-shaped
# dependency row of each chart — cf-77 r2's awk ends its print block with
# program-`exit`, which terminates the whole program where `next` would move
# to the next record — and cr package died with `no repository definition for
# https://charts.jetstack.io, https://charts.christianhuth.de` (scout TEST D
# reproduced the owner's error verbatim from the shipped loop's state; TEST F
# proved the exit->next shape end-to-end). This leg extracts each of the
# three carriers and replays it OFFLINE through the shipped `tail +2 | head
# -n -1` arithmetic over dependency-list-shaped fixtures, then over the four
# victim charts' real Chart.lock rows — the lockfiles are the fixture source,
# so a future multi-row chart is covered by derivation, not enumeration.
if ! python3 - "$WF" <<'PY'
import re, subprocess, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
JOBS = ('test-build', 'release', 'forgejo-publish')
VICTIMS = ('base', 'k8s-monitoring', 'postiz', 'traefik')
HDR = 'NAME\tVERSION\tREPOSITORY\tSTATUS'

# Fixtures: live-measured `helm dependency list` column shapes (workspace helm
# 3.16.4, 2026-11-23). Display padding is stripped — awk splits on every run
# of tabs/spaces, so the fields the carrier scans are the real output's; scout
# TEST B' verified helm 3.22.1 (the baked runner version) keeps the rows +
# trailing blank that the `tail +2 | head -n -1` arithmetic eats. The zero-dep
# fixture is the one shape without a header: helm puts the WARNING line on
# STDOUT (the step's `2> /dev/null` does not silence it) and `tail +2` drops
# that single line — which is exactly what makes the step a no-op there.
def fixture(rows):
    return HDR + '\n' + ''.join(r + '\n' for r in rows) + '\n'

# charts/base — the owner-fire chart: rows 2 and 3 are the exact URLs the
# dead fire named. An exit-shaped carrier emits 1 of these 3 pairs.
BASE = fixture(['argo-cd\t10.18.2\thttps://argoproj.github.io/argo-helm\tmissing',
                'cert-manager\tv1.21.3\thttps://charts.jetstack.io\tmissing',
                'gateway-api-crds\t1.2.5\thttps://charts.christianhuth.de\tmissing'])
BASE_PAIRS = [('argo-cd', 'https://argoproj.github.io/argo-helm'),
              ('cert-manager', 'https://charts.jetstack.io'),
              ('gateway-api-crds', 'https://charts.christianhuth.de')]
# The six charts that packaged on the dead fire (loki/seaweedfs shape): the
# completeness fix must not regress them — exactly one pair.
SINGLE = fixture(['loki\t7.5.0\thttps://grafana.github.io/helm-charts\tmissing'])
SINGLE_PAIRS = [('loki', 'https://grafana.github.io/helm-charts')]
# cf-77 r2's class: an empty REPOSITORY column shifts the STATUS word into
# $3, so the per-row field guard must skip the row instead of emitting a
# name + status pair that `helm repo add` swallows and bash -e kills the
# step over. Orthogonal to completeness: the exit-shape carrier PASSES this
# fixture; it is the twin-era print-$1-$3 mutant that reddens here.
EMPTY_REPO = fixture(['bjw-common\t9.9.9\thttps://bjw-s-labs.github.io/helm-charts/\tmissing',
                      'local-sub\t1.0.0\t\tmissing'])
EMPTY_REPO_PAIRS = [('bjw-common', 'https://bjw-s-labs.github.io/helm-charts/')]
# hivetools: both rows oci://. The awk emission duty covers them too;
# keeping them out of helm repo add is the step's ^oci:// skip (t6's token).
OCI_BOTH = fixture(['toolhive-operator-crds\t0.56.0\toci://ghcr.io/stacklok/toolhive\tmissing',
                    'toolhive-operator\t0.56.0\toci://ghcr.io/stacklok/toolhive\tmissing'])
OCI_BOTH_PAIRS = [('toolhive-operator-crds', 'oci://ghcr.io/stacklok/toolhive'),
                  ('toolhive-operator', 'oci://ghcr.io/stacklok/toolhive')]
ZERO_DEP = 'WARNING: no dependencies at charts/zerochart/charts\n'


def carrier(jn):
    # t6's blob idiom per job; the repo-add program is the single-quoted awk
    # body riding the helm dependency list line. None = no scan carrier left.
    blob = '\n'.join(str(s.get('run', '')) for s in (jobs.get(jn) or {}).get('steps', [])
                     if isinstance(s, dict) and 'run' in s)
    for line in blob.splitlines():
        if 'helm dependency list' in line and 'awk' in line:
            m = re.search(r"awk '([^']*)'", line)
            if m:
                return m.group(1)
    return None


def replay(prog, text):
    # The shipped pipeline arithmetic verbatim, then the landed carrier as-is.
    t = subprocess.run(['tail', '+2'], input=text, capture_output=True, text=True)
    h = subprocess.run(['head', '-n', '-1'], input=t.stdout, capture_output=True, text=True)
    a = subprocess.run(['awk', prog], input=h.stdout, capture_output=True, text=True)
    if a.returncode != 0:
        return None, a.stderr.strip()
    return [tuple(l.split(' ', 1)) for l in a.stdout.splitlines() if l.strip()], ''


def fmt(pairs):
    return ', '.join(' '.join(p) for p in pairs) or 'nothing'


problems = []


def check(jn, what, pairs, expected):
    missing = [p for p in expected if p not in pairs]
    extra = [p for p in pairs if p not in expected]
    if missing or extra:
        problems.append(f'{jn}: {what} emitted [{fmt(pairs)}]'
                        + (f' — MISSING [{fmt(missing)}]' if missing else '')
                        + (f' — unexpected [{fmt(extra)}]' if extra else ''))


for jn in JOBS:
    prog = carrier(jn)
    if prog is None:
        problems.append(f'{jn}: no repo-add awk carrier on the helm dependency list line')
        continue
    pairs, err = replay(prog, BASE)
    if pairs is None:
        problems.append(f"{jn}: carrier replay errored ({err!r}) — the awk program does not run")
        continue
    check(jn, 'base-shape 3-URL-row fixture', pairs, BASE_PAIRS)
    check(jn, 'single-URL-row fixture', replay(prog, SINGLE)[0], SINGLE_PAIRS)
    check(jn, 'empty-REPOSITORY fixture', replay(prog, EMPTY_REPO)[0], EMPTY_REPO_PAIRS)
    check(jn, 'oci-both fixture', replay(prog, OCI_BOTH)[0], OCI_BOTH_PAIRS)
    check(jn, 'zero-dependency fixture', replay(prog, ZERO_DEP)[0], [])
    # AC2 derivation: the repo set the loop derives must cover every http(s)
    # URL of the chart's Chart.lock — cr's lock-driven Build resolves each
    # one against the repositories file (D45; victim set per scout §A2).
    for chart in VICTIMS:
        deps = yaml.safe_load(open('charts/' + chart + '/Chart.lock'))['dependencies']
        rows = [d['name'] + '\t' + str(d['version']) + '\t' + d['repository'] + '\tmissing'
                for d in deps]
        emitted = {u for _, u in replay(prog, fixture(rows))[0]}
        lock_http = {d['repository'] for d in deps
                     if d['repository'].startswith(('http://', 'https://'))}
        gap = sorted(lock_http - emitted)
        if gap:
            problems.append(f'{jn}: {chart} Chart.lock URLs never registered: '
                            + ', '.join(gap))

if problems:
    print('FAIL: t21: the repo-add loop is INCOMPLETE — a carrier that ends its print '
          'block with a program terminator (cf-77 r2 wrote exit where the all-rows loop '
          'needs next) registers only each chart\'s FIRST URL-shaped dependency row, so '
          'cr package dies on the unregistered repos (no repository definition for ..., '
          'the owner release fire). Offenders:', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t21: see the t21 detail above"
fi
ok "t21: all three repo-add carriers emit every URL-shaped dependency row (base 3-of-3, loki-shape 1, oci-both 2, empty-REPOSITORY row silent, zero-dep silent) and the derived repo set covers every http(s) Chart.lock URL of the four victim charts"

# --- t22: the bump job's lock self-heal pin (C09, D47.1) -------------------------
# One drifted Chart.lock poisons EVERY fire: cr package Build()s every chart
# every run, so the heal must be full-tree, must run on the REMOTE tip (after
# the reset — heal decisions may never ride the event checkout's stale tree),
# must precede the version derivation, and must land the locks in the SAME
# bump commit (the top-level version: is outside helm's digest inputs, so
# bump+heal in one commit is digest-safe by construction). Static carrier pin
# (t21/t15 idiom); red at HEAD: the loop does not exist yet.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
bodies = [str(s.get('run', '')) for s in (jobs.get('bump') or {}).get('steps', [])
          if isinstance(s, dict) and 'run' in s]
body = next((b for b in bodies if 'refs/remotes/origin/main' in b and 'python3' in b), None)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t22: {msg}', file=sys.stderr)
        sys.exit(1)


need(body is not None, 'the bump job has no run block combining the main-tip reset with the python derivation — nothing to pin the heal into')
code = [(i, l) for i, l in enumerate(body.splitlines()) if not l.lstrip().startswith('#')]

reset_i = next((i for i, l in code if 'git reset --hard refs/remotes/origin/main' in l), None)
py_i = next((i for i, l in code if 'python3' in l), None)
need(reset_i is not None and py_i is not None, 'reset/python3 anchors missing from the bump step')

# (a) full-tree regen: a charts/*/Chart.lock-glob loop running the regen verb
loop_i = next((i for i, l in code if re.search(r'\bfor\s+[A-Za-z_]\w*\s+in\s+charts/\*/Chart\.lock\b', l)), None)
need(loop_i is not None, 'no `for <v> in charts/*/Chart.lock` heal loop in the bump step — the full-tree self-heal (D47.1) is not in place; glob-gated by design (charts without a lock are skipped, zero-dep charts no-op)')
end = next((i for i, l in code if i > loop_i and re.search(r'\bdone\b', l)), code[-1][0])
window = '\n'.join(l for i, l in code if loop_i <= i <= end)
need('helm dependency update' in window, 'the Chart.lock glob loop does not invoke `helm dependency update` — that is the only regen verb (no --force-update exists on the dep subcommands)')

# (b) placement: on the remote tip, before the version rewrite
need(loop_i > reset_i, f'the heal loop sits at line {loop_i}, reset at {reset_i} — healing BEFORE the main-tip reset lets a stale event checkout decide what is drifted')
need(loop_i < py_i, f'the heal loop sits at line {loop_i}, python3 derivation at {py_i} — locks must be healed before versions are derived from the tree')

# (c) locks staged next to the bumped Chart.yamls
need(any('git add' in l and 'Chart.lock' in l for _, l in code),
     'no git add line covers Chart.lock — a healed lock that is never staged cannot ride the bump commit')

# (d) commit guarded on staged content (a fresh-tree fire must not mint an
# empty commit under set -euo pipefail; helm itself skips byte-equal writes)
commit_i = next((i for i, l in code if 'git commit' in l), None)
need(commit_i is not None, 'no git commit in the bump step')
cl = next(l for i, l in code if i == commit_i)
guard_inline = re.search(r'git\s+diff\s+--cached\s+--quiet\s*\|\|\s*git commit', cl)
prev = [l for i, l in code if commit_i - 3 <= i < commit_i]
guard_block = any(re.search(r'if\s+!?\s*git\s+diff\s+--cached\s+--quiet', p) for p in prev)
need(guard_inline or guard_block,
     f'the bump commit is unguarded ({cl.strip()[:80]!r}) — `git diff --cached --quiet || git commit` (or the if-block twin) is required so a no-op heal stages nothing and fires nothing')

# (e) message names BOTH sets when the heal set is non-empty
need(any('chore(release): bump' in l for _, l in code),
     'the commit message no longer heads with `chore(release): bump <bumped>` (D17-era head, kept per C09.md)')
need(any('+ heal' in l for _, l in code),
     'the message construction never appends ` + heal <healed-locks>` — the heal set must be named when non-empty (the message shape is pinned from C09 onward)')
need(any(re.search(r'\[\s*-n\s+[^\]]*heal', l, re.I) for _, l in code),
     'the heal-set append is unconditional or unguarded — the + heal segment must ride a non-empty test of the heal set')
PY
then
  fail "t22: see the t22 detail above"
fi
ok "t22: bump heals full-tree after the main-tip reset and before the derivation, stages the locks in the guarded single bump commit, and names the heal set in the message"

# --- t23: the test-build build->update flip (C09, D47.2) ------------------------
# Job order is test-build -> bump: a smoke that ABORTS on drift (dependency
# build digest-checks before any download) makes the self-heal unreachable on
# exactly the drift-carrying push. The smoke flips to the ephemeral heal; the
# repo-side drift signal moves to t24, which runs pre-merge. Red at HEAD.
if ! python3 - "$WF" <<'PY'
import sys, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}
step = next((s for s in (jobs.get('test-build') or {}).get('steps', [])
             if isinstance(s, dict) and 'helm lint' in str(s.get('run', ''))), None)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t23: {msg}', file=sys.stderr)
        sys.exit(1)


need(step is not None, 'test-build has no smoke step running helm lint — the step the flip re-truths is gone')
run = str(step.get('run', ''))
need('helm dependency update "charts/${{ matrix.chart }}"' in run,
     'the Lint-and-package-smoke does not run `helm dependency update "charts/${{ matrix.chart }}"` — the flip (D47.2) heals ephemerally on the matrix copy instead of aborting on drift')
need('helm lint' in run and 'helm package' in run,
     'the flip may not delete the work: lint + package stay in the smoke')
for l in raw.splitlines():
    if l.lstrip().startswith('#'):
        continue
    need('helm dependency build' not in l,
         f'a code line still invokes the aborting verb ({l.strip()[:90]!r}) — dependency build must end up absent from every code line file-wide (the aborting leg is the self-heal-unreachable defect)')
PY
then
  fail "t23: see the t23 detail above"
fi
ok "t23: test-build re-negotiates (dependency update) with lint+package intact; the aborting verb appears on zero code lines file-wide"

# --- t24: hermetic full-tree lock consistency (C09 AC1/D47.3) -------------------
# cf-135's dev-forgejo-runner t10 contract (the lock must resolve to the
# Chart.yaml) made OFFLINE and FULL-TREE: no helm, no network — pure
# committed-state projection. Red at HEAD naming exactly {charts/base,
# charts/traefik, charts/traefik-zerotrust} (the drift trio RESEARCH item 83
# measured); green once C09's regeneration merges; t10 stays the live-helm
# witness untouched (one branch one concern).
if ! python3 - <<'PY'
import glob, os, re, sys, yaml

EXACT = re.compile(r'^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')


def project(entry, keys):
    # Go omitempty mirror: absent/empty-string/empty-list drop out, an
    # explicit false stays — a value is a value.
    return {k: entry[k] for k in keys if entry.get(k) is not None and entry.get(k) != '' and entry.get(k) != []}


offenders = []
for cy in sorted(glob.glob('charts/*/Chart.yaml')):
    d = os.path.dirname(cy)
    deps = (yaml.safe_load(open(cy)) or {}).get('dependencies') or []
    if not deps:
        continue
    lock_p = os.path.join(d, 'Chart.lock')
    if not os.path.exists(lock_p):
        offenders.append(f'{d}: Chart.yaml declares dependencies but carries no Chart.lock (build would silently mirror update)')
        continue
    lock = yaml.safe_load(open(lock_p)) or {}
    entries = lock.get('dependencies') or []
    if not str(lock.get('digest', '')).startswith('sha256:'):
        offenders.append(f'{d}: Chart.lock carries no sha256 digest: field (not a helm-written lock)')
    # Helm v3 serializes name/repository/version into lock entries; the other
    # chart.Dependency fields (alias/tags/condition/enabled/import-values)
    # enter the digest from the Chart.yaml side only. Project both sides onto
    # the union the lock actually carries so the check stays true against
    # today's format and self-adapts if helm ever serializes more.
    keys = sorted({'name', 'version', 'repository'} | {k for e in entries for k in e if project(e, [k])})
    want = [project(e, keys) for e in deps]
    got = [project(e, keys) for e in entries]
    for e in deps:
        v = str(e.get('version', ''))
        if not EXACT.match(v):
            offenders.append(f'{d}: dependency {e.get("name")} pins {v!r} — not an exact resolved version; a range pin makes resolved-lock != constraint by design and must be RE-DESIGNED, not silently drifted (RESEARCH 1207-1211)')
    if got != want:
        offenders.append(f'{d}: Chart.lock projects to {got}, Chart.yaml to {want} — helm hashes exactly this serialized-field pair, so dependency build would abort on this delta')

if offenders:
    print('FAIL: t24: committed Chart.lock files disagree with their Chart.yaml '
          'dependency declarations (position, name, version, repository field-wise; '
          'the trio heals in C09, every future drift-source is caught pre-merge):', file=sys.stderr)
    for o in offenders:
        print('  ' + o, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t24: see the t24 detail above"
fi
ok "t24: every Chart.yaml dependency declaration projects field-wise onto its committed Chart.lock, full-tree, hermetic (digest+generated headers present, all pins exact)"

# --- t25: the calendar walk — static pins + executed battery (C10, D47.4/D49) ----
# The owner's scheme: `2026.11.1++` with N derived LOCALLY from the tree + one
# clock stamp per run; the published index demotes to a collision guard. The
# Masterminds trap is the load-bearing part: NewVersion rejects leading zeros,
# so `2026.07.1` is INVALID semver and dies at helm package (the D15 lesson
# reborn, RESEARCH 1178-1184 [88]) — `date -u +%Y.%-m` plus a numeric
# round-trip must make the padded form unproducible. Red at HEAD: no stamp,
# no walk arms, the derivation is still max(tree, published)+1.
if ! python3 - "$WF" <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile, yaml

raw = open(sys.argv[1]).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}
bodies = [str(s.get('run', '')) for s in (jobs.get('bump') or {}).get('steps', [])
          if isinstance(s, dict) and 'run' in s]
body = next((b for b in bodies if 'refs/remotes/origin/main' in b and 'python3' in b), None)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t25: {msg}', file=sys.stderr)
        sys.exit(1)


need(body is not None, 'no bump derivation step to calendarize')
code = '\n'.join(l for l in body.splitlines() if not l.lstrip().startswith('#'))

# --- static calendar pins (C10.md t25) ---
stamps = [l for l in code.splitlines() if 'date' in l and re.search(r'\+?%Y', l)]
need(len(stamps) == 1 and '+%Y.%-m' in stamps[0],
     f'the bump step carries {len(stamps)} clock-stamp line(s), expected exactly one `date -u +%Y.%-m` (one stamp per run like build-containers\'s month= law; UNPADDED month is the Masterminds law, D47.4)')
for bad in ('+%Y.%m', '02d', '%.2d', 'strftime'):
    need(bad not in code,
         f'a zero-pad spelling ({bad!r}) survives on code lines — a padded stamp renders invalid semver (2026.07.1) and dies at helm package; the trap must be unproducible')

heredoc = re.search(r"<<'PY'[ ]*\n(.*?)\nPY[ ]*(?=\n|\Z)", body, re.S)
need(heredoc is not None, 'the bump step no longer embeds its derivation heredoc')
src = heredoc.group(1)
need(('sys.argv[3]' in src) or ('environ' in src),
     'the python block reads no stamp binding (sys.argv[3] or os.environ) — the one-shot stamp must be PASSED to the derivation, never recomputed inside it')
need(re.search(r'\(\s*Y\s*,\s*M\s*,\s*0\s*\)', src) and re.search(r'(?:raise|SystemExit)[^\n]*ahead', src, re.S),
     'no fail-loud arm for tree > (Y, M, 0) — the walk must REFUSE to walk backwards (never re-mint below the clock), not clamp')
need('def ver(' in src and 'len(parts) == 3' in src and 'isdigit' in src,
     'ver() is no longer the 3-part tuple parser — 4-digit calendar majors ride the same comparison (RESEARCH 1192-1194)')
need('name, name_indent = m.group(1), indent' in src and 'indent == name_indent' in src,
     'the same-indent pairing parser block moved — t15 pins its VALUE semantics and C10 keeps it verbatim as the collision-guard feed')

# --- executed walk battery (C10.md t26 cases (i)-(viii)) ---
mode = 'argv' if 'sys.argv[3]' in src else 'env'
env_names = sorted(set(re.findall(r'''environ(?:\.get)?[\(\[]\s*["']([A-Za-z_][A-Za-z0-9_]*)["']''', src))) if mode == 'env' else []
if mode == 'env':
    need(bool(env_names), 'environ is mentioned but no os.environ[...] variable name is discoverable — the leg cannot stub the stamp')

def write_case(root, name, tree, published):
    os.makedirs(os.path.join(root, 'charts', name), exist_ok=True)
    with open(os.path.join(root, 'charts', name, 'Chart.yaml'), 'w') as f:
        f.write(f'apiVersion: v2\nname: {name}\nversion: {tree}\n')
    idx = os.path.join(root, 'published-index.yaml')
    lines = ['apiVersion: v1', 'entries:']
    for k, v in published.items():
        lines += [f'  {k}:', '  - apiVersion: v2', f'    name: {k}', f'    version: {v}']
    with open(idx, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    return idx


parser = os.path.join(tempfile.gettempdir(), 'r4t25-carrier.py')
work = []
problems = []
CASES = [
    # name,            tree,        published,           stamp,  expect
    ('samemonth',      '2026.11.3', {},                  ('2026', '11'), '2026.11.4'),   # (i)
    ('rollover',       '2026.10.5', {},                  ('2026', '11'), '2026.11.1'),   # (ii)
    ('legacyjump',     '1.0.203',   {},                  ('2026', '11'), '2026.11.1'),   # (iii)
    ('aheadtree',      '2027.1.2',  {},                  ('2026', '11'), None),          # (iv) FAIL LOUD
    ('collision',      '2026.11.1', {'collision': '2026.11.3'}, ('2026', '11'), '2026.11.4'),   # (v)
    ('indexnotderiv',  '1.0.203',   {'indexnotderiv': '2026.10.9'}, ('2026', '11'), '2026.11.1'),  # (vi)
    ('padtrap',        '1.0.5',     {},                  ('2026', '07'), '2026.7.1'),    # (vii)
    ('yearroll',       '2026.12.4', {},                  ('2027', '1'), '2027.1.1'),     # (viii)
]
try:
    with open(parser, 'w') as f:
        f.write(src)
    for name, tree, published, (ys, ms), expect in CASES:
        root = tempfile.mkdtemp(prefix='forgejo-release-t25.')
        work.append(root)
        idx = write_case(root, name, tree, published)
        cmd = [sys.executable, parser, json.dumps([name]), idx]
        if mode == 'argv':
            # C10.md prices "argv or env"; argv shapes may be one stamp string
            # (argv[3]="Y.M") or split vars (argv[3]=Y, argv[4]=M) — the form
            # is read off the carrier itself so both legal dev shapes run.
            if re.search(r'sys\.argv\[4\]', src):
                cmd += [ys, ms]
            else:
                cmd += [f'{ys}.{ms}', ys, ms]
        env = os.environ.copy()
        for var in list(env_names) + ['CALVER_STAMP', 'CALVER_Y', 'CALVER_M', 'CAL_STAMP', 'CAL_Y', 'CAL_M']:
            if var.endswith('_Y'):
                env[var] = ys
            elif var.endswith('_M'):
                env[var] = ms
            else:
                env[var] = f'{ys}.{ms}'
        r = subprocess.run(cmd, cwd=root, capture_output=True, text=True, env=env)
        if expect is None:
            # (iv): must die LOUD, naming the chart — a silent skip would let
            # a clock-skew push walk released versions backwards.
            if r.returncode == 0:
                cur = re.search(r'(?m)^version: (\S+)$', open(os.path.join(root, 'charts', name, 'Chart.yaml')).read())
                problems.append(f'{name} (tree-ahead): exit 0 with version {cur.group(1) if cur else "?"!r} — the walk refused to fail loud on tree > clock stamp')
            elif name not in (r.stderr + r.stdout):
                problems.append(f'{name} (tree-ahead): nonzero exit but never names the chart ({(r.stderr.strip()[-160:] or r.stdout.strip()[-160:])!r})')
            continue
        if r.returncode != 0:
            problems.append(f"{name} ({tree} @ {ys}.{ms}): exit {r.returncode} ({(r.stderr.strip()[-160:] or r.stdout.strip()[-160:])!r}), expected {expect}")
            continue
        cur = re.search(r'(?m)^version: (\S+)$', open(os.path.join(root, 'charts', name, 'Chart.yaml')).read())
        got = cur.group(1) if cur else '<none>'
        if got != expect:
            problems.append(f'{name} ({tree} @ {ys}.{ms}, published={published or "-"}): wrote {got!r}, expected {expect!r} — strict string equality is the padding defense too (2026.07.1 != 2026.7.1 is the Masterminds trap)')
finally:
    for root in work:
        shutil.rmtree(root, ignore_errors=True)
    if os.path.exists(parser):
        os.unlink(parser)

if problems:
    print('FAIL: t25: the bump derivation does not implement the calendar walk (D47.4 '
          'local-N rule: same-month N+1, tree<(Y,M,0) -> N=1, tree-ahead fails loud, '
          'the published index only guards collisions, stamps round-trip numerically):', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t25: see the t25 detail above"
fi
ok "t25: one unpadded clock stamp per run is passed to the derivation (argv/env), ver()/pairing-parser survive, and the executed walk battery passes all eight calendar cases incl. the padded-stamp round-trip and the tree-ahead loud refusal"

# --- t26: the AGENTS + rulesync law pair, calendar form (C10, D49) ---------------
# The hard-rule bullet is the law every session loads; the D49 owner override
# picks the Y.M.1 seed for brand-new charts, so BOTH the generated AGENTS.md
# and its .rulesync source must carry the calendar wording after C10's pair
# commit — red at HEAD on the old patch language by design (rulesync generate
# keeps the pair in step; C10 owns the rewrite, never hand-edit AGENTS.md).
if ! python3 - <<'PY'
import sys


def norm(p):
    return ' '.join(open(p).read().split())


pairs = [('AGENTS.md', norm('AGENTS.md')),
         ('.rulesync/rules/overview.md', norm('.rulesync/rules/overview.md'))]

problems = []
for path, text in pairs:
    for tok in ('calendar release', 'Y.M.N', 'unpadded month', 'same-month N+1', 'new-month N=1'):
        if tok not in text:
            problems.append(f'{path}: missing the calendar-law token {tok!r} (D47.4/R-Q1 rewrite: bumps `version` to the calendar release `Y.M.N` (unpadded month) — same-month N+1, new-month N=1)')
    i = text.find('brand-new chart')
    if i < 0 or 'Y.M.1' not in text[max(0, i - 320):i + 40]:
        problems.append(f'{path}: the brand-new-chart clause does not carry the D49 seed form (set version <current Y.M.1> only on a brand-new chart)')
    for dead in ('bumps `Chart.yaml` `version` (patch)', 'Set `version: 1.0.0` only on a brand-new chart'):
        if dead in text:
            problems.append(f'{path}: still states the retired patch-scheme clause {dead!r}')

if problems:
    print('FAIL: t26: the version-law PAIR (source + generated mirror) is not in its '
          'post-C10 calendar form:', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t26: see the t26 detail above"
fi
ok "t26: AGENTS.md and overview.md pair-states the calendar law (Y.M.N, unpadded month, same-month N+1, new-month N=1) with the D49 Y.M.1 seed clause and no patch-scheme residue"

# --- t27: executed Patch-bump battery — comment tolerance at :111-class (C13) ----
# The Nov-25 fire died HERE: a trailing `#` comment on the version line made
# the `$`-anchored regex refuse and the test-build matrix leg raised. These
# cases run the SHIPPED heredoc (extracted like t25 does the bump heredoc)
# against fixture Chart.yamls, so the fix shape is executed, not texted —
# and the garbage-refuses law is replayed in the same breath (a tolerance
# that swallows ` junk` or `#nospace` is a new bug class, not a fix).
if ! python3 - "$WF" <<'PY'
import os, re, shutil, subprocess, sys, tempfile, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
tb = (jobs.get('test-build') or {}).get('steps') or []
body = next((str(s.get('run', '')) for s in tb
             if isinstance(s, dict) and 'MAJOR.MINOR.PATCH' in str(s.get('run', ''))), None)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t27: {msg}', file=sys.stderr)
        sys.exit(1)


need(body is not None, 'the test-build job carries no Patch-bump version step — the smoke bump died (t1/t5 shape law: this leg reads the shipped heredoc, it does not substitute its own)')
heredoc = re.search(r"<<'PY'[ ]*\n(.*?)\nPY[ ]*(?=\n|\Z)", body, re.S)
need(heredoc is not None, 'the Patch-bump step no longer embeds its heredoc — t27 executes it verbatim')
src = heredoc.group(1)
need('(?m)^version:' in src,
     'the column-0 anchor is gone from the parse — dependency pins (indented version: lines) would start winning, the traefik 42.x collision law (C13 keeps (?m)^)')
need('m.start(1)' in src and 'm.end(3)' in src,
     'the group-1..3 rewrite slices moved — a tolerated comment survives the bump precisely because it sits after m.end(3) (C13 task 1)')

parser = os.path.join(tempfile.gettempdir(), 'r5t27-patchbump.py')
work = []
problems = []
CASES = [
    # name,      version-line,              expect_exit, expect_line_or_None, msg_needle_or_None
    ('clean',    'version: 1.0.40',          0, r'^version: 1\.0\.41$', None),
    ('comment',  'version: 1.0.1  # note',   0, r'^version: 1\.0\.2[ \t]+# note$', None),
    ('junk',     'version: 1.0.1 junk',      1, None, 'is not MAJOR.MINOR.PATCH'),
    ('indented', '  version: 5.0.1',         1, None, None),
    ('nospace',  'version: 1.0.1#nospace',   1, None, None),
]
try:
    with open(parser, 'w') as f:
        f.write(src)
    for name, line, want_rc, want_line, needle in CASES:
        root = tempfile.mkdtemp(prefix='forgejo-t27.')
        work.append(root)
        cdir = os.path.join(root, 'charts', name)
        os.makedirs(cdir)
        text = f'apiVersion: v2\nname: {name}\n{line}\nappVersion: "9.9.9"\n'
        with open(os.path.join(cdir, 'Chart.yaml'), 'w') as f:
            f.write(text)
        r = subprocess.run([sys.executable, parser, f'charts/{name}/Chart.yaml'],
                           cwd=root, capture_output=True, text=True)
        after = open(os.path.join(cdir, 'Chart.yaml')).read()
        if want_rc == 0:
            if r.returncode != 0:
                problems.append(f"{name}: exit {r.returncode} ({(r.stderr.strip() or r.stdout.strip())[-140:]!r}), expected the bump to succeed")
                continue
            if not re.search(want_line, after, re.M):
                got = [l for l in after.splitlines() if 'version:' in l]
                problems.append(f'{name}: after the bump the file carries {got!r}, expected a line matching {want_line!r}'
                                + (' — the seed-era comment must SURVIVE the rewrite (C13: slices end at group 3)' if name == 'comment' else ''))
        else:
            if r.returncode == 0:
                problems.append(f'{name}: exit 0 — {line!r} must REFUSE (garbage-refuses law; the fix tolerates only a #-prefixed tail)')
            if needle and needle not in (r.stderr + r.stdout):
                problems.append(f"{name}: refused but the message does not name {needle!r} ({(r.stderr.strip() or r.stdout.strip())[-140:]!r})")
            if after != text:
                problems.append(f'{name}: a refusing case still rewrote the file — the die must precede any write')
finally:
    for root in work:
        shutil.rmtree(root, ignore_errors=True)
    if os.path.exists(parser):
        os.unlink(parser)

if problems:
    print('FAIL: t27: the Patch-bump heredoc does not implement the C13 comment-tolerant shape:', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t27: see the t27 detail above"
fi
ok "t27: executed on the shipped test-build heredoc — clean bump regression, comment-tolerant bump with the comment surviving the rewrite, junk/indented/#nospace all refusing loudly (the :111-class battery, C13 t27)"

# --- t28: executed derivation battery — :258-class comment tolerance (C13) -------
# The sibling parse (the bump derivation's `^version: (\S+)$`) carries the
# same terminal-anchor bug with the OTHER refuse message. Two cases extend
# the t25 CASES-walk machinery (stamp stubbing, argv-or-env modes): the
# comment-tolerant derivation must rewrite the token and keep the comment
# in the written file; a junk tail must still refuse loud (the :260 die).
if ! python3 - "$WF" <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
bodies = [str(s.get('run', '')) for s in (jobs.get('bump') or {}).get('steps', [])
          if isinstance(s, dict) and 'run' in s]
body = next((b for b in bodies if 'refs/remotes/origin/main' in b and 'python3' in b), None)


def need(cond, msg):
    if not cond:
        print(f'FAIL: t28: {msg}', file=sys.stderr)
        sys.exit(1)


need(body is not None, 'no bump derivation step (t25 already reddens on the same absence; t28 cannot stage without it)')
heredoc = re.search(r"<<'PY'[ ]*\n(.*?)\nPY[ ]*(?=\n|\Z)", body, re.S)
need(heredoc is not None, 'the bump step no longer embeds its derivation heredoc')
src = heredoc.group(1)
need('(?m)^version: (\\S+)' in src,
     'the :258-class parse is not the (\\S+) shape t28 replays (a total rewrite of the parse belongs to a fresh t-spec, not to C13)')
need('m.start(1)' in src and 'm.end(1)' in src,
     'the rewrite slices at group 1 moved — text[m.end(1):] is what keeps a tolerated tail byte-identical (C13 task 2)')

mode = 'argv' if 'sys.argv[3]' in src else 'env'
env_names = sorted(set(re.findall(r'''environ(?:\.get)?[\(\[]\s*["']([A-Za-z_][A-Za-z0-9_]*)["']''', src))) if mode == 'env' else []
if mode == 'env':
    need(bool(env_names), 'environ is mentioned but no stub-able variable name is discoverable — the leg cannot inject the stamp')

CASES2 = [
    # name, tree, published, stamp, expect (None = must refuse)
    ('commenttolerant', '2026.11.3  # seed-era note', {}, ('2026', '11'), '2026.11.4'),
    ('garbagetail',     '2026.11.3 junk',             {}, ('2026', '11'), None),
]

parser = os.path.join(tempfile.gettempdir(), 'r5t28-derive.py')
work = []
problems = []
try:
    with open(parser, 'w') as f:
        f.write(src)
    for name, tree, published, (ys, ms), expect in CASES2:
        root = tempfile.mkdtemp(prefix='forgejo-t28.')
        work.append(root)
        cdir = os.path.join(root, 'charts', name)
        os.makedirs(cdir)
        with open(os.path.join(cdir, 'Chart.yaml'), 'w') as f:
            f.write(f'apiVersion: v2\nname: {name}\nversion: {tree}\n')
        idx = os.path.join(root, 'published-index.yaml')
        lines = ['apiVersion: v1', 'entries:']
        for k, v in published.items():
            lines += [f'  {k}:', '  - apiVersion: v2', f'    name: {k}', f'    version: {v}']
        with open(idx, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        cmd = [sys.executable, parser, json.dumps([name]), idx]
        if mode == 'argv':
            if re.search(r'sys\.argv\[4\]', src):
                cmd += [ys, ms]
            else:
                cmd += [f'{ys}.{ms}', ys, ms]
        env = os.environ.copy()
        for var in list(env_names) + ['CALVER_STAMP', 'CALVER_Y', 'CALVER_M', 'CAL_STAMP', 'CAL_Y', 'CAL_M']:
            if var.endswith('_Y'):
                env[var] = ys
            elif var.endswith('_M'):
                env[var] = ms
            else:
                env[var] = f'{ys}.{ms}'
        r = subprocess.run(cmd, cwd=root, capture_output=True, text=True, env=env)
        after = open(os.path.join(cdir, 'Chart.yaml')).read()
        if expect is None:
            if r.returncode == 0:
                problems.append(f'{name} (junk tail): exit 0 with {after.splitlines()[2]!r} — `2026.11.3 junk` has no #, the anchored tail cannot match it, the run must REFUSE (C13: garbage-refuses law preserved)')
            continue
        if r.returncode != 0:
            problems.append(f"{name}: exit {r.returncode} ({(r.stderr.strip()[-140:] or r.stdout.strip()[-140:])!r}), expected the derivation to bump {tree!r} to {expect!r} — the :258 parse still refuses a #-comment tail (the Nov-25 'no top-level version: line' class)")
            continue
        m2 = re.search(r'(?m)^version: (\S+)(?:[ \t]+#[^\n]*)?[ \t]*$', after)
        got = m2.group(1) if m2 else '<none>'
        if got != expect:
            problems.append(f"{name}: derivation wrote {got!r}, expected {expect!r}")
        if '# seed-era note' not in after:
            problems.append(f'{name}: the tolerated comment did NOT survive the rewrite — the rewrite is group-1-scoped precisely so the tail rides untouched')
finally:
    for root in work:
        shutil.rmtree(root, ignore_errors=True)
    if os.path.exists(parser):
        os.unlink(parser)

if problems:
    print('FAIL: t28: the bump derivation heredoc does not implement the C13 :258-class comment tolerance:', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t28: see the t28 detail above"
fi
ok "t28: executed on the shipped derivation heredoc — commenttolerant rewrites the token with the comment surviving the written file, garbagetail still refuses loud (the :258-class battery, C13 t28)"

# --- t29: class ban — no live chart carries the bug shape (C13) ------------------
# The prowlarr line MOVE is what makes the fire survivable TODAY; this leg
# keeps the CLASS from regrowing (the seed-law prose belongs ABOVE the line —
# charts/*/Chart.yaml top-level version lines stay comment-free, verified
# 2026-11-26 only prowlarr carries the shape).
if ! python3 - <<'PY'
import glob, sys

viol = []
for p in sorted(glob.glob('charts/*/Chart.yaml')):
    for i, ln in enumerate(open(p).read().splitlines(), 1):
        if ln.startswith('version:') and '#' in ln:
            viol.append(f'{p}:{i}: {ln.strip()[:90]}')
if viol:
    print('FAIL: t29: live charts carry a trailing comment ON the top-level version: line (the C13 fire class; move the comment to its own line above):', file=sys.stderr)
    for v in viol:
        print('  ' + v, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t29: see the t29 detail above"
fi
ok "t29: every live charts/*/Chart.yaml top-level version: line is comment-free (class ban; the prowlarr move is what turns this green)"

# --- t30: executed shared-marker resolver (C14) ----------------------------------
# The resolver step mirrors the containers shipped shape (ls-remote read,
# absent -> empty output bootstrap, non-40-hex LOUD, present-unreachable LOUD
# with reset/delete owner verbs) on the shared ci/last-built ref. Events
# outside the marker-side set must emit an empty sha= WITHOUT touching the
# network (dead-origin witness, the containers c5 idiom). Staged and executed
# against a scratch bare remote; the battery runs the marker-side event as
# workflow_call so it reads identically in the C14 (push+call) and C15
# (call-only) gate states.
if ! python3 - "$WF" <<'PY'
import os, re, shutil, subprocess, sys, tempfile, yaml

wf = sys.argv[1]
jobs = (yaml.safe_load(open(wf)) or {}).get('jobs') or {}
steps = (jobs.get('changes') or {}).get('steps') or []

RES = 'refs/heads/ci/last-built'
rs = [i for i, s in enumerate(steps)
      if isinstance(s, dict) and 'ls-remote' in str(s.get('run', '')) and RES in str(s.get('run', ''))]
ds = [i for i, s in enumerate(steps) if isinstance(s, dict) and 'CHARTS=' in str(s.get('run', ''))]
if not rs:
    print(f'FAIL: t30: the changes job carries no resolve step reading {RES} (the resolver is C14 task 1; absent means the marker never feeds detection)', file=sys.stderr)
    sys.exit(1)
if not ds:
    print('FAIL: t30: no detect step to position the resolver against (harness fault — t1 owns that red)', file=sys.stderr)
    sys.exit(1)
if rs[0] >= ds[0]:
    print(f'FAIL: t30: the resolver step sits at {rs[0]}, not BEFORE the detect step ({ds[0]}) — C14: resolve last-built marker goes before detection', file=sys.stderr)
    sys.exit(1)
rtext = str(steps[rs[0]].get('run', ''))
rtext = re.sub(r'\$\{\{[^}]*event_name[^}]*\}\}', '"$EVENT_NAME"', rtext)

git = shutil.which('git')
root = tempfile.mkdtemp(prefix='forgejo-t30.')
problems = []


def run(script, cwd, env_extra, out):
    e = os.environ.copy()
    e['GITHUB_OUTPUT'] = out
    e.update(env_extra)
    return subprocess.run(['bash', script], cwd=cwd, capture_output=True, text=True, env=e)


def answer(out):
    txt = open(out).read() if os.path.exists(out) else ''
    lines = [l for l in txt.splitlines() if l.startswith('sha=')]
    return lines[-1][4:] if lines else None


try:
    remote = os.path.join(root, 'remote.git')
    subprocess.run([git, 'init', '-q', '--bare', remote], check=True)
    work = os.path.join(root, 'work')
    subprocess.run([git, 'clone', '-q', remote, work], check=True, capture_output=True)
    subprocess.run([git, '-C', work, 'config', 'user.email', 'test@example.invalid'], check=True)
    subprocess.run([git, '-C', work, 'config', 'user.name', 'test'], check=True)
    open(os.path.join(work, 'seed.txt'), 'w').write('seed\n')
    subprocess.run([git, '-C', work, 'add', '-A'], check=True)
    subprocess.run([git, '-C', work, 'commit', '-qm', 'a'], check=True)
    subprocess.run([git, '-C', work, 'push', '-q', 'origin', 'HEAD:refs/heads/main'], check=True)
    head1 = subprocess.run([git, '-C', work, 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()

    script = os.path.join(root, 'resolver.sh')
    open(script, 'w').write(rtext + '\n')

    # r1: marker ABSENT -> exit 0 with an EMPTY sha= (bootstrap)
    out = os.path.join(root, 'out1')
    r = run(script, work, {'EVENT_NAME': 'workflow_call', 'MARKER_SHA': ''}, out)
    if r.returncode != 0:
        problems.append(f'r1 absent-marker: exit {r.returncode} ({(r.stderr.strip() or r.stdout.strip())[-140:]!r}), expected 0 — no marker yet is the bootstrap shape (emit sha= empty)')
    elif not os.path.exists(out) or answer(out) != '':
        problems.append(f'r1 absent-marker: output is {answer(out)!r}, expected an empty sha= emission (the detect env must never go missing)')

    # r2: marker present and reachable -> emits the marker sha
    subprocess.run([git, '-C', work, 'push', '-q', 'origin', f'{head1}:{RES}'], check=True)
    out = os.path.join(root, 'out2')
    r = run(script, work, {'EVENT_NAME': 'workflow_call', 'MARKER_SHA': ''}, out)
    got = answer(out) if os.path.exists(out) else None
    if r.returncode != 0 or got != head1:
        problems.append(f'r2 present+reachable: exit {r.returncode} sha={got!r}, expected 0/sha={head1} — the resolver must hand detect the marker')

    # r3: marker present but UNREACHABLE (advanced from a sibling clone the
    # checkout has never fetched) -> LOUD die naming the value + owner verbs
    work2 = os.path.join(root, 'work2')
    shutil.copytree(work, work2)  # same objects: the marker pre-move FFs and stays unreachable from `work`
    open(os.path.join(work2, 'ahead.txt'), 'w').write('ahead\n')
    subprocess.run([git, '-C', work2, 'add', '-A'], check=True)
    subprocess.run([git, '-C', work2, 'commit', '-qm', 'ahead'], check=True)
    subprocess.run([git, '-C', work2, 'push', '-q', 'origin', f'HEAD:{RES}'], check=True)
    head2 = subprocess.run([git, '-C', work2, 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
    out = os.path.join(root, 'out3')
    r = run(script, work, {'EVENT_NAME': 'workflow_call', 'MARKER_SHA': ''}, out)
    if r.returncode == 0:
        problems.append(f'r3 orphaned-marker: exit 0 (sha={answer(out)!r}) — a marker unreachable from the checkout must fail LOUD, never downgrade this run to the payload fallback in silence (C14 mirrors the containers shipped shape)')
    else:
        log = r.stderr + r.stdout
        if head2 not in log:
            problems.append('r3 orphaned-marker: the die does not name the marker sha — undiagnosable from the job log')
        if not re.search(r'reset|delete', log, re.I):
            problems.append('r3 orphaned-marker: the die carries no owner verbs (reset the marker to a reachable commit or delete it)')

    # r4: non-40-hex garbage from ls-remote (PATH shim) -> LOUD, naming it
    shim = os.path.join(root, 'shim')
    os.makedirs(shim)
    garbage = 'z' * 40
    stub = os.path.join(shim, 'git')
    with open(stub, 'w') as f:
        f.write(f'#!/bin/sh\nif [ "$1" = ls-remote ]; then printf "%s\\t{RES}\\n" "{garbage}"; exit 0; fi\nexec {git} "$@"\n')
    os.chmod(stub, 0o755)
    out = os.path.join(root, 'out4')
    r = run(script, work, {'EVENT_NAME': 'workflow_call', 'MARKER_SHA': '', 'PATH': shim + os.pathsep + os.environ['PATH']}, out)
    if r.returncode == 0:
        problems.append('r4 garbage-marker: exit 0 — a non-sha value is fatal, not a bootstrap reinterpretation')
    elif garbage not in (r.stderr + r.stdout):
        problems.append('r4 garbage-marker: the die does not name the garbage value')

    # r5: event OUTSIDE the marker-side set -> empty sha= with NO network
    # (dead origin: any ls-remote attempt would die loudly instead)
    dead = os.path.join(root, 'dead')
    os.makedirs(dead)
    subprocess.run([git, '-C', dead, 'init', '-q', '.'], check=True)
    subprocess.run([git, '-C', dead, 'remote', 'add', 'origin', os.path.join(root, 'no-such-remote.git')], check=True)
    out = os.path.join(root, 'out5')
    r = run(script, dead, {'EVENT_NAME': 'pull_request', 'MARKER_SHA': ''}, out)
    if r.returncode != 0:
        problems.append(f'r5 non-marker-side event: exit {r.returncode} against a DEAD origin — outside the marker-side set the resolver must emit sha= empty and touch no network (the shipped PR/dispatch law)')
    elif answer(out) != '':
        problems.append(f'r5 non-marker-side event: sha={answer(out)!r}, expected the empty emission')
finally:
    shutil.rmtree(root, ignore_errors=True)

if problems:
    print('FAIL: t30: the ci/last-built resolver does not implement the shipped-shape law (C14 task 1):', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t30: see the t30 detail above"
fi
ok "t30: executed against scratch bare remotes — absent→empty, present+reachable→sha, orphaned→loud naming value+owner verbs, non-hex→loud, non-marker-side events answer empty network-free (C14 resolver)"

# --- t31: executed marker..sha chain + idempotence + re-cover (C14) --------------
# The detect chain of the changes job, staged and run against a scratch repo
# carrying charts/{alpha,beta,gamma}: marker..sha happy path; marker==sha ->
# the verified-empty INFO line, empty CHARTS, NO ::warning:: anomaly (AC5);
# all-zero before -> tip-only + ::warning::; empty before with no marker ->
# LOUD die (the replaced silent-fallback shape, t18 static); and the dead-run
# recovery proof (AC4): a red fire leaves the marker put, the next fire's
# range still contains the lost chart change.
if ! python3 - "$WF" <<'PY'
import os, re, shutil, subprocess, sys, tempfile, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps = (jobs.get('changes') or {}).get('steps') or []
di = [i for i, s in enumerate(steps) if isinstance(s, dict) and 'CHARTS=' in str(s.get('run', ''))]
if not di:
    print('FAIL: t31: no detect step (the CHARTS= writer) in the changes job — nothing to stage (authored-red until C14 lands the chain)', file=sys.stderr)
    sys.exit(1)
dtext = str(steps[di[0]].get('run', ''))
env_map = steps[di[0]].get('env') or {}
ROLE_OF = (('outputs.sha', 'marker'), ('event.before', 'before'), ('event_name', 'event'), ('.sha', 'sha'))
key_role = {}
raw_expr = {}
for k, v in env_map.items():
    v = str(v)
    for frag, role in ROLE_OF:
        if frag in v:
            key_role[k] = role
            raw_expr[k] = v
            break
# Inline interpolations in the body bind to the canonical names; env-mapped
# keys bind to THEIR names (both paths covered — the step contract is the
# wiring, not one spelling).
dtext = re.sub(r'\$\{\{[^}]*event_name[^}]*\}\}', '"$R5_EVENT"', dtext)
dtext = re.sub(r'\$\{\{[^}]*event\.before[^}]*\}\}', '"$R5_BEFORE"', dtext)
dtext = re.sub(r'\$\{\{[^}]*(?:forgejo|github)\.sha[^}]*\}\}', '"$R5_SHA"', dtext)
dtext = re.sub(r'\$\{\{[^}]*outputs\.sha[^}]*\}\}', '"$R5_MARKER"', dtext)
if '${{' in dtext:
    print(f'FAIL: t31: the staged detect body still carries an unnormalized interpolation: {[l.strip()[:90] for l in dtext.splitlines() if "${{" in l]}', file=sys.stderr)
    sys.exit(1)

git = shutil.which('git')
root = tempfile.mkdtemp(prefix='forgejo-t31.')
problems = []


def chart(repo, name):
    d = os.path.join(repo, 'charts', name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'Chart.yaml'), 'w') as f:
        f.write(f'apiVersion: v2\nname: {name}\nversion: 1.0.0\n')


def commit(repo, msg):
    subprocess.run([git, '-C', repo, 'add', '-A'], check=True)
    subprocess.run([git, '-C', repo, 'commit', '-qm', msg], check=True)
    return subprocess.run([git, '-C', repo, 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()


def run_case(label, marker, before, sha, want_rc, want_charts=None,
             want_info=None, want_warn=None):
    out = os.path.join(root, f'out-{label}')
    script = os.path.join(root, f'chain-{label}.sh')
    open(script, 'w').write(dtext + '\n')
    e = os.environ.copy()
    e.update({'GITHUB_OUTPUT': out, 'EVENT_NAME': 'push',
              'MARKER_SHA': marker, 'EVENT_BEFORE': before, 'EVENT_SHA': sha, 'SHA': sha,
              'R5_EVENT': 'push', 'R5_BEFORE': before, 'R5_SHA': sha, 'R5_MARKER': marker})
    for k, role in key_role.items():
        e[k] = {'marker': marker, 'before': before, 'sha': sha, 'event': 'push'}[role]
    r = subprocess.run(['bash', script], cwd=repo, capture_output=True, text=True, env=e)
    log = r.stdout + r.stderr
    if want_rc == 0:
        if r.returncode != 0:
            problems.append(f'{label}: exit {r.returncode} ({(r.stderr.strip() or r.stdout.strip())[-140:]!r}), expected 0')
            return
        charts = re.findall(r'(?m)^CHARTS=(.*)$', open(out).read()) if os.path.exists(out) else []
        got = re.sub(r'\s', '', charts[-1]) if charts else '<none>'
        if want_charts is not None and got != want_charts:
            problems.append(f'{label}: CHARTS emitted {got!r}, expected {want_charts!r}')
        if want_info and want_info not in log:
            problems.append(f'{label}: the log carries no {want_info!r} — the designed calm line is how a verified-empty run reads differently from an anomaly')
        if want_warn is True and '::warning::' not in log:
            problems.append(f'{label}: expected a ::warning:: announcement on stderr/stdout and found none')
        if want_warn is False and '::warning::' in log:
            problems.append(f'{label}: the run wears a ::warning:: where the shipped law says calm — the marker==sha empty set is data, not an anomaly (C14 idempotence line)')
    else:
        if r.returncode == 0:
            problems.append(f'{label}: exit 0 — expected the LOUD die (the silent HEAD^-fallback mask is exactly what C14 buried)')


try:
    repo = os.path.join(root, 'work')
    os.makedirs(repo)
    subprocess.run([git, '-C', repo, 'init', '-q', '.'], check=True)
    subprocess.run([git, '-C', repo, 'config', 'user.email', 'test@example.invalid'], check=True)
    subprocess.run([git, '-C', repo, 'config', 'user.name', 'test'], check=True)
    open(os.path.join(repo, 'README.md'), 'w').write('a\n')
    sha_a = commit(repo, 'a')
    chart(repo, 'alpha')
    sha_b = commit(repo, 'b-alpha')
    chart(repo, 'beta')
    sha_c = commit(repo, 'c-beta')
    chart(repo, 'gamma')
    sha_d = commit(repo, 'd-gamma')

    # c1: happy marker..sha (marker=B, sha=C) — the beta change rides.
    run_case('happy', sha_b, sha_a, sha_c, 0, want_charts='["beta"]')
    # c2: marker==sha — verified-empty INFO line, no ::warning::, CHARTS=[] (AC5).
    run_case('idem', sha_c, sha_b, sha_c, 0, want_charts='[]',
             want_info='changed set verified empty', want_warn=False)
    # c3: all-zero before with no marker — tip-only fallback, announced.
    run_case('tiponly', '', '0' * 40, sha_d, 0, want_charts='["gamma"]', want_warn=True)
    # c4: EMPTY before with no marker — LOUD die (the replaced silent shape).
    run_case('die', '', '', sha_d, 1)
    # c5: dead-run recovery (AC4): the fire at C died before advancing the
    # marker; the next fire (tip D, marker still B) must SEE beta+gamma.
    run_case('recover', sha_b, sha_c, sha_d, 0, want_charts='["beta","gamma"]')
finally:
    shutil.rmtree(root, ignore_errors=True)

if problems:
    print('FAIL: t31: the marker..sha chain of the changes job does not implement the C14 law (happy / idempotence-info / tip-only-announce / empty-before-die / dead-run re-cover):', file=sys.stderr)
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t31: see the t31 detail above"
fi
ok "t31: executed on a scratch repo — marker..sha detection, marker==sha verified-empty info with no anomaly annotation, all-zero tip-only announce, empty-before loud die, and the dead-run re-cover (marker put ⇒ the next fire's range contains the lost chart) (C14 tasks 2-3, AC4/AC5)"

# --- t32: ONE advance writer — interim job here OR main-sync aggregate (C14/C15) --
# Two-state pin by ruling (F4/D59: C14+C15 land in the same merge session,
# but the waves gate independently): after C14 the marker moves ONLY through
# this file's interim job (needs triple = the green-fire gate, ROLE guard AND
# has_changes true, plain push of the BUMP COMMIT sha — never the event sha,
# the D53 eternal-tail law — with the ancestor tolerance and no force form
# anywhere); after C15 this file carries ZERO marker-push statements and the
# writer lives in main-sync.yaml (pinned by that suite). Red at HEAD: neither
# writer exists yet.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

REF = 'refs/heads/ci/last-built'
GUARD = "contains(vars.ROLE, 'prod')"
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
adv = jobs.get('advance-marker')

if adv is None:
    # C15 state: the builders carry no advance job; the writer must live in
    # main-sync (that suite's t15 owns its shape — this leg owns the fence
    # that NO marker push hides here).
    raw = open(sys.argv[1]).read()
    pushes = [ln.strip() for ln in raw.splitlines()
              if re.search(r'git\s+push', ln) and REF in ln and not ln.strip().startswith('#')]
    if pushes:
        print(f'FAIL: t32: no advance-marker job, yet the file carries marker pushes in other steps: {pushes!r} — a hidden writer dodges the aggregate single-writer law (D54)', file=sys.stderr)
        sys.exit(1)
    ms = yaml.safe_load(open('.forgejo/workflows/main-sync.yaml')) or {}
    if 'advance-marker' not in ((ms.get('jobs')) or {}):
        print('FAIL: t32: no advance writer exists at all — the marker can never move, so every fire re-diffs its payload and the delivery-loss class stays open (C14 lands the interim job HERE; C15 moves it to main-sync)', file=sys.stderr)
        sys.exit(1)
    sys.exit(0)

needs = adv.get('needs')
needs = [needs] if isinstance(needs, str) else (needs or [])
if set(needs) != {'bump', 'release', 'forgejo-publish'}:
    print(f'FAIL: t32: advance-marker.needs is {needs!r}, expected exactly [bump, release, forgejo-publish] — the all-green-fire gate (a skipped bump skips the advance, the matrix-green-law analogue, C14 task 5)', file=sys.stderr)
    sys.exit(1)
if_expr = str(adv.get('if') or '')
if GUARD not in if_expr or "needs.changes.outputs.has_changes == 'true'" not in if_expr:
    print(f"FAIL: t32: advance-marker.if is {if_expr!r}, expected the ROLE byte-guard AND the has_changes == 'true' term — an empty CHARTS fire must not move the marker (C14 task 5)", file=sys.stderr)
    sys.exit(1)
checkouts = [s for s in adv.get('steps') or [] if isinstance(s, dict) and str(s.get('uses', '')).startswith('actions/checkout@')]
if not checkouts:
    print('FAIL: t32: advance-marker has no checkout step (t5 owns the action allow-list; the push needs the repository)', file=sys.stderr)
    sys.exit(1)
w = (checkouts[0].get('with') or {})
if not (type(w.get('fetch-depth')) is int and w.get('fetch-depth') == 0):
    print(f'FAIL: t32: advance-marker checkout fetch-depth is {w.get("fetch-depth")!r}, expected the integer 0 — push negotiation needs the history', file=sys.stderr)
    sys.exit(1)
body = '\n'.join(str(s.get('run', '')) for s in adv.get('steps') or [] if isinstance(s, dict) and 'run' in s)
pushes = [ln.split('#', 1)[0].strip() for ln in body.splitlines()
          if re.search(r'git\s+push', ln) and REF in ln]
if not pushes:
    print(f'FAIL: t32: the advance body never pushes to {REF} (C14 task 5: push the BUMP_SHA endpoint)', file=sys.stderr)
    sys.exit(1)
for stmt in pushes:
    if re.search(r'--force|-f(\s|$)|force-with-lease|\+', stmt):
        print(f'FAIL: t32: the advance push statement {stmt!r} wears a force form — plain push stays the first verb, tolerance classifies refusals, never forces past them (AC6)', file=sys.stderr)
        sys.exit(1)
    if 'refs/heads/main' in stmt:
        print(f'FAIL: t32: the marker push rides a main refspec ({stmt!r}) — only the bump-commit endpoint (or the C15 target chain) advances ci/last-built (D53: an event-sha endpoint re-feeds B1 and mints an eternal one-release-per-fire tail)', file=sys.stderr)
        sys.exit(1)
if 'merge-base --is-ancestor' not in body:
    print('FAIL: t32: the advance body carries no merge-base --is-ancestor classification — on refusal the body must fetch the marker and distinguish already-advanced (skip-green) from divergence (loud), the shared-branch tolerance of C14 task 2', file=sys.stderr)
    sys.exit(1)
if not re.search(r'git\s+fetch', body):
    print('FAIL: t32: no fetch of the marker for the tolerance classification — merge-base needs FETCH_HEAD to reason about (C14 task 2)', file=sys.stderr)
    sys.exit(1)
if 'already advanced' not in body:
    print("FAIL: t32: the skip-green info line ('marker already advanced past this run's endpoint — consistent') is missing — the descendant case must read as calm, not as a forced-through red (C14 task 2)", file=sys.stderr)
    sys.exit(1)
blob = yaml.dump(adv)
for tok in ('vars.ROLE ==', 'secrets.'):
    if tok in blob:
        print(f'FAIL: t32: the advance job references {tok!r} — the marker push rides the checkout same-repo credential, no PAT, no equality guard (the containers t16 laws travel with the job)', file=sys.stderr)
        sys.exit(1)
PY
then
  fail "t32: see the t32 detail above"
fi
ok "t32: exactly one marker writer, in either era — interim job shape (needs triple, ROLE-guard+has_changes, plain push of the bump-commit endpoint, fetch/merge-base tolerance, no force, no secrets) or the deleted-job fence with the main-sync aggregate present (C14 task 5 / C15 §A, D53/D54)"

# --- t33: bump_sha output plumbing (C14 task 4) ----------------------------------
# The advance pushes the OUTPUT sha (the bump commit B1 or the re-looped
# landed commit), never the event sha — an event-sha endpoint would re-enter
# B1's own charts/** edits into the next detection and mint an eternal
# one-release-per-fire tail (D53). This leg pins the step-id + job-output
# chain t13 validates generically.
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
bump = jobs.get('bump') or {}
outs = bump.get('outputs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t33: {msg}', file=sys.stderr)
        sys.exit(1)


need('bump_sha' in outs, f'bump.outputs is {outs!r} — no bump_sha key (C14 task 4: the job-level output the advance rides)')
m = re.search(r'steps\.([A-Za-z0-9_-]+)\.outputs\.sha\b', str(outs.get('bump_sha')))
need(m, f'bump.outputs.bump_sha maps {outs.get("bump_sha")!r}, expected the steps.<id>.outputs.sha idiom')
sid = m.group(1)
step = next((s for s in (bump.get('steps') or []) if isinstance(s, dict) and s.get('id') == sid), None)
need(step is not None, f'no step declares id: {sid} in the bump job — t13 would redden on the dangling reference too (the output resolves empty)')
body = str(step.get('run', ''))
need('rev-parse HEAD' in body, f'step {sid} never rev-parse-es its own HEAD — the emitted sha is the bump commit (or the re-looped landed commit), read AFTER the successful push (C14 task 4)')
need(re.search(r'sha=\$\(git rev-parse HEAD\)', body), f'step {sid} carries no sha= output emission')
need('refs/heads/main' in body, f'step {sid} writes no main push — the emission belongs to the push-SUCCESS branch, before exit 0 (the bump job has exactly this one main push site)')
PY
then
  fail "t33: see the t33 detail above"
fi
ok "t33: bump.outputs.bump_sha maps a declared step id whose body emits sha=$(git rev-parse HEAD) on the push-success path (C14 task 4; t13 covers the id-integrity generically)"

# --- t34: on.workflow_call.outputs declaration (C15 §A) --------------------------
# main-sync's advance consumes this file's bump output — declared in the
# trigger block, mapping jobs.bump.outputs.bump_sha (the C14 JOB output key;
# distinct from the steps-level `sha` — B1 review-fold: the conflation made
# the called output resolve empty, dropping the aggregate advance to the
# event sha and re-arming the D53 bump-commit tail this pin exists to fence).
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}
trig = doc.get(True) or doc.get('on') or {}
wc = (trig or {}).get('workflow_call')
if not isinstance(wc, dict):
    print(f'FAIL: t34: on.workflow_call is {wc!r} — no mapping to declare outputs on (t2 owns the trigger set; C15 §A task 3)', file=sys.stderr)
    sys.exit(1)
outs = (wc.get('outputs') or {})
if 'bump_sha' not in outs:
    print(f'FAIL: t34: on.workflow_call.outputs is {outs!r} — bump_sha is not exported (main-sync consumes needs.build-charts.outputs.bump_sha)', file=sys.stderr)
    sys.exit(1)
val = outs['bump_sha'].get('value') if isinstance(outs['bump_sha'], dict) else outs['bump_sha']
if str(val) != '${{ jobs.bump.outputs.bump_sha }}':
    print(f"FAIL: t34: on.workflow_call.outputs.bump_sha is {outs['bump_sha']!r}, expected the value jobs.bump.outputs.bump_sha interpolation (the JOB key — steps-level `sha` resolves empty cross-job, B1)", file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t34: see the t34 detail above"
fi
ok "t34: on.workflow_call.outputs declares bump_sha = jobs.bump.outputs.bump_sha (job key, B1) — the called-run output the main-sync aggregate advance rides (C15 §A task 3)"

printf 'PASS: forgejo-build-charts checks (%d ok)\n' "$checks"
