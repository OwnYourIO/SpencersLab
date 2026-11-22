#!/usr/bin/env bash
# Offline contract suite for the cf-6 Forgejo container-build pipeline, run -2
# hardening (2026/2026-11-cf-6-feat-forgejo-container-builds-2): the static
# invariants of .forgejo/workflows/containers-build.yaml +
# scripts/forgejo-container-detect.sh, the GitHub fallback
# .github/workflows/docker-build.yaml, the repo-wide guard sweep over
# .forgejo/workflows/, and the detection-contract doc pins. Shape follows
# tests/services/forgejo-main-sync.sh; the per-leg selection follows
# tests/pipeline-models/surface.sh.
#
# AC trace — run 0 base (superseded where run -1 re-authored): t1[AC1] t2[AC2]
# t4[AC3] t6[AC8] t10/t11[review r1 majors 1-2; run -1 generalizes t11 per
# registry side] d1-d8[AC6]; x2[AC2 offline half] x3[AC3] x4[AC1 scope fence].
# Run -1: t3/t5/t7/t8/t9 + r1-r5 [C02 AC2-AC5 — ROLE membership guards, the
# dual-registry mirror, union-max N]; x1 [C03 AC1-AC4 — commented-out trigger
# restore]; g1 [C04 — repo-wide no-URL/membership sweep].
# Run -2: t12-t15 + d9-d15 [C01 — pinned checkout depth, payload-accessor bytes,
# the loud empty/fallback postures, the wide-range and merge-base fixtures, the
# echo that makes a nothing-built run legible]; x5 [C03 — the detection contract
# pinned in the gated docs]. AC11 (`docker build
# => no-daemon, CI-deferred`, cf-77) is a RESULT-line contract, never a build
# test: this workspace has no docker daemon and the live Forgejo run on infra
# is the authoritative build test — no leg here fakes one.
#
# Subset discipline (plan Commands):
#   - Run -2 gates: C01 `t d` — 30 ok; C02 `g1` (paired with cf-135's suites,
#     which live in other files); C03 `x` — 5 ok; final: the full set — 41 ok.
#     Group selectors are SEPARATE argv words (`... t d`); a quoted `'t d'`
#     dies as one unknown id — the parser takes argv per id. The legacy `c02`
#     alias is run -1's `t d r` subset and is not a run -2 gate.
#   - t/d legs read only containers-build.yaml + the detector (scratch git
#     fixtures under /tmp/opencode for d-legs, and for t14's behavioral half,
#     which EXECUTES the shipped detect-step run body against the shipped
#     detector); r legs read only
#     containers-build.yaml; x legs read only docker-build.yaml, renovate.json
#     and the gated docs; g1 sweeps .forgejo/workflows/. No leg reads a file
#     outside its chunk's set.
#
# Red posture (red-first as authored for run -2 against the post-merge base —
# the implementation does not exist yet): t14 (no echo today), d11 (no fallback
# annotation), d12 (an empty before falls through green), d14/d15 (the shipped
# PR arm is two-dot; the owner ruling is merge-base) are red until C01 lands,
# x5 until C03 and g1 until C02 — `t d` hands off 25 ok / 5 red, the full suite
# 34 ok / 7 red. t12/t13/t15/d9/d10/d13 are green-at-authoring regression pins
# of a contract that exists but was unpinned — the plan's mutation column is
# their teeth proof; a pin no mutation reddens is a vacuous leg: report it, do
# not ship it. Run -1's posture stands: t1/t2/t4/t6/t10, d1-d8, x2-x4 are
# byte-stable green across the run, and the FULL suite is green only after the
# last chunk. A FAIL line that names no artifact is a harness fault: report it,
# do not work around it.
#
# Pins and their why:
#   - t14 has a behavioral half because a text pin cannot see a silently
#     reverted exemption: C01 round 1 shipped the empty-set warning WITHOUT
#     the owner's before == sha exemption and every static clause stayed
#     green (review caught it by running the step). The leg now runs the
#     shipped run body under five faithful env shapes and asserts which arms
#     warn — scope pinned, spelling free (the compound line may read any
#     way bash allows; run -1's r5 over-fitting lesson).
#   - run -2's d11/d12/d13/d15 read stdout AND stderr AND the exit code (the
#     detect_capture helper): the fallback annotation, the A5 die, the 128
#     propagation and RP19's endpoint-line-before-merge-base all live on
#     channels detect_in cannot see. stdout must stay exactly the one JSON
#     line (the channel law, RP5) — that is why these legs byte-check stdout
#     separately instead of only its content.
#   - d14/d15 pin the OWNER-RULED B5 shape (merge-base, hand-rolled — the
#     `git diff --merge-base` flag would need git >= 2.43 and the runner
#     image's git is unverified, OQ-b/OQ-g), measured on fix4: BASE=M HEAD=H
#     => ["beta"], not the two-dot ["alpha","beta"]; an unrelated base/head
#     pair exits non-zero (measured 1, git merge-base writing nothing) where
#     two-dot quietly answered a set. Red-by-design, not a regression claim
#     against run 0's shipped arm.
#   - d12 pins non-zero, not a number: the A5 exit code is dev's choice (OQ-m
#     answered that way deliberately); the prototype's die-2 is not a pin.
#   - x5 keys on stable markers, never line numbers (x3's discipline): the
#     CONTRACT vocabulary (before..sha range / merge base / first push /
#     tip-only / announced / fetch-depth: 0) is agreed with C03 in the chunk
#     file, and the negative clause exists because on v15.0.10 + runner
#     v13.2.0 the new lines are job-log text — no gated doc may promise an
#     annotation render (RESEARCH §7.2/§7.3).
#   - pyyaml: YAML 1.1 resolves the bare `on:` key to boolean True, so trigger
#     legs read doc.get(True) or doc.get('on'); asserting the string key alone
#     would redden a correct file (main-sync precedent).
#   - x1's raw trigger grep is scoped to the `on:` block: the plan-Commands
#     verbatim `^[[:space:]]*(push|pull_request):` false-reds on the
#     docker/build-push-action `push:` INPUT key deep in the (kept) job body
#     (~L139) — that line is not a trigger, and it stays the blessed false
#     positive. The parsed `on:` key-set is the authoritative inertness
#     assertion; the commented-text checks pin a WHOLE block (parent plus
#     commented branches/paths children) so a matching phrase in an unrelated
#     comment cannot satisfy them; and the parse is what reddens the
#     half-commented shape — a commented parent with live children raises
#     ParserError (EXPLORE §7.2 replayed both shapes).
#   - r1 pins the fromJSON ban where the OQ-2 owner ruling puts it: fromJSON
#     may not guard (no fromJSON in any if:) and never evaluates a vars.*
#     value. The matrix keeps its fromJSON over the DETECTOR output (C02 Tasks
#     carry it over byte-stable): it parses a JSON array the workflow itself
#     emits, so it cannot error the way an instance-set ROLE value would.
#   - r3 attributes every docker push to a registry arm by the ghcr/forge
#     token in the push line or its enclosing for: list — the only static
#     shape that pins RD8's arm order; unattributable pushes fail the leg.
#   - Reads, walks and push chains carry the same ghcr/forge naming token
#     (t11's per-side tolerance branches, r2's both-lists-before-push, r3's
#     push attribution, r5's scheme-strip derivation): the per-side variables
#     are named ghcr_*/forge_* so the static legs tell the two registry arms
#     apart without a live run — the vars.PUSH_URL_{GH,DEV} naming precedent
#     from main-sync. t8 follows each side's PUSH CHAIN (its docker push
#     statements, their enclosing for: lists, and the variables those reach):
#     naming forge_latest is not proof forge pushes :latest — only a chain
#     that reaches the image prefix and all three tags is (a per-step
#     co-presence check let a calendar-only forge arm through).
#   - r5 blesses a scheme'd URL in exactly three places: inside a
#     `${VAR#https://}` strip fragment, on the public ghcr.io endpoint, and
#     directly in front of the per-side forge_* host variable
#     (`https://$forge_registry/v2/...`). The middle ground the first version
#     banned is the only correct one: the strip alone yields `host/` because
#     setting.AppURL is code-guaranteed to end in `/`, while a scheme-less
#     `"$host/v2/..."` makes curl default to http — shipping the write:package
#     PAT in cleartext on every release run. A hard-coded instance host (with
#     or without a scheme), any `https://` in an `if:`, a strip fragment used
#     as a guard predicate, and a scheme-less `<forge host var>/v2/...` read
#     stay red. Only the API path is scheme-pinned: docker logins and image
#     refs take a bare hostname/repository, so a scheme there would be an
#     invalid reference the leg must not force.
#   - x2 is the pure parse/regex half of the Renovate contract. The behavioral
#     half — dev-renovate validate_config + test_package_rules on renovate.json
#     (rule decides on ghcr.io/ownyourio/wekan-mcp, not on llama-swap) — stays
#     an MCP duty of the dev/review sessions per the plan's Commands section;
#     this suite never needs the network or the renovate binary.
#   - d8's expectations follow the D5/C01 sanitizer spec (lowercase, `/`->`-`,
#     remaining chars outside [a-z0-9._-] ->`-`, collapse repeated dashes,
#     cap <=128), so `My_Branch` keeps its underscore: `_` IS in the class.
#   - t8 reads the tag arms per JOB (build-release / build-pr): run -1's
#     event split makes the arms disjoint by construction (C02 AC5), so no
#     bash case/if archaeology is left to interpret. Runtime tag behavior is
#     live-fire (infra, post-merge H7), per the chunk.
#   - t10/t11 pin composition facts, not live behavior: echo $(...) discarding
#     an exit status is a bash reporting rule, and a registry answering 403
#     (ghcr) or 404 NAME_UNKNOWN (forge) for a never-pushed image is registry
#     behavior — no live probe belongs to them and the no-network rule bars
#     probing registries anyway.
#
# Constraints: no network; no actionlint/hadolint/yamllint (not installed —
# never invoked here); no pytest and no helm (no chart test rides this ticket);
# needs python3+pyyaml and git on PATH.
#
# Run from anywhere in the worktree (groups as separate argv words, never
# quoted together):
#   bash tests/services/forgejo-containers-build.sh              # full set — 41 ok at run end
#   bash tests/services/forgejo-containers-build.sh t d          # C01 gate — 30 ok
#   bash tests/services/forgejo-containers-build.sh g1           # C02 gate leg (cf-135 suites are separate files)
#   bash tests/services/forgejo-containers-build.sh x            # C03 gate — 5 ok
#   bash tests/services/forgejo-containers-build.sh c02          # run -1's t d r alias, not a run -2 gate
#   bash tests/services/forgejo-containers-build.sh t12 d9       # per-leg
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF=".forgejo/workflows/containers-build.yaml"
HELP="scripts/forgejo-container-detect.sh"
GHB=".github/workflows/docker-build.yaml"
HELP_ABS="$PWD/$HELP"

checks=0
FAILED=0

TMP=$(mktemp -d /tmp/opencode/forgejo-containers-build-test.XXXXXX) || { echo 'harness: mktemp failed' >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
group_t() { for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do WANT["t$i"]=1; done; }
group_d() { for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do WANT["d$i"]=1; done; }
group_x() { for i in 1 2 3 4 5; do WANT["x$i"]=1; done; }
group_r() { for i in 1 2 3 4 5; do WANT["r$i"]=1; done; }
group_g() { WANT[g1]=1; }
if [ "$#" -eq 0 ]; then
  group_t; group_d; group_x; group_r; group_g
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    case "$lc" in
      t)   group_t ;;
      d)   group_d ;;
      x)   group_x ;;
      r)   group_r ;;
      g)   group_g ;;
      c02) group_t; group_d; group_r ;;
      t1[0-5]|t[1-9]|d1[0-5]|d[1-9]|x[1-5]|r[1-5]|g1) WANT["$lc"]=1 ;;
      *) printf 'FAIL: unknown check id %s (expected t1..t15, d1..d15, x1..x5, r1..r5, g1, or groups t d x r g c02)\n' "$a" >&2; exit 2 ;;
    esac
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
run_leg() {
  local id="$1" fn="$2"
  want "$id" || return 0
  if ! "$fn"; then FAILED=$((FAILED + 1)); fi
}

# --- C01 workflow legs (t1-t15): .forgejo/workflows/containers-build.yaml ----

leg_t1() {
  [ -f "$WF" ] || { printf 'FAIL: t1: %s does not exist (C01 creates it)\n' "$WF" >&2; return 1; }
  python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$WF" \
    || { printf 'FAIL: t1: %s does not parse as YAML\n' "$WF" >&2; return 1; }
  [ -f "$HELP" ] || { printf 'FAIL: t1: %s does not exist (C01 creates it)\n' "$HELP" >&2; return 1; }
  bash -n "$HELP" || { printf 'FAIL: t1: bash -n %s is not clean\n' "$HELP" >&2; return 1; }
  ok "t1: $WF exists and parses; $HELP exists and is bash -n clean [C01 AC1]"
}

leg_t2() {
  [ -f "$WF" ] || { printf 'FAIL: t2: %s does not exist (C01 creates it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

path = sys.argv[1]
doc = yaml.safe_load(open(path))
trig = doc.get(True) or doc.get('on')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t2: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(trig, dict), 'no top-level on: mapping')
need(set(trig) == {'push', 'pull_request', 'workflow_dispatch'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly push + pull_request + workflow_dispatch (D7: no dev leg)')
for name in ('push', 'pull_request'):
    blk = trig[name] if isinstance(trig[name], dict) else {}
    need(bool(blk), f'{name}: trigger is not a mapping')
    need(blk.get('branches') == ['main'],
         f'{name}.branches is {blk.get("branches")!r}, expected exactly [main]')
    need('containers/**' in (blk.get('paths') or []),
         f'{name}.paths is {blk.get("paths")!r}, expected to contain containers/**')
inp = (trig['workflow_dispatch'] or {}).get('inputs', {}).get('containers')
need(isinstance(inp, dict) and inp.get('type') == 'string' and inp.get('default') == '',
     f'workflow_dispatch input containers is {inp!r}, expected a string input with default ""')
for i, line in enumerate(open(path).read().splitlines(), 1):
    if 'branches' in line and re.search(r'\bdev\b', line):
        need(False, f'line {i} carries a branches trigger naming dev: {line.strip()!r} (D7 drops the dev leg)')
PY
  then
    return 1
  fi
  ok "t2: on: is exactly push/PR on main with containers/** paths + string dispatch input, no dev leg [C01 AC2]"
}

leg_t3() {
  [ -f "$WF" ] || { printf 'FAIL: t3: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

path = sys.argv[1]
raw = open(path).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t3: {msg}', file=sys.stderr)
        sys.exit(1)


# NOTE 3 (owner ruling): instance selection is by ROLE membership, never by
# URL — the file carries zero instance/repo hosts and derives no decision from
# forgejo.server_url. Counted file-wide so a stray host paste anywhere,
# including a comment, reddens this leg (main-sync t3 mutation teeth).
for host in ('git.spencerslab.com', 'git.scifi.farm'):
    need(raw.count(host) == 0,
         f'the instance host {host!r} occurs {raw.count(host)} time(s), expected zero (NOTE 3: NO direct URL references anywhere in the workflows)')
need(raw.count('github.com/') == 0,
     f'github.com/ occurs {raw.count("github.com/")} time(s), expected zero (no repo-host literal either)')
need(raw.count('startsWith(forgejo.server_url') == 0,
     f'startsWith(forgejo.server_url occurs {raw.count("startsWith(forgejo.server_url")} time(s), expected zero (the URL guard is retired — C02 replaces it with the vars.ROLE membership guard)')
ifs = [str(j.get('if')) for j in jobs.values() if isinstance(j, dict) and j.get('if') is not None]
ifs += [str(s.get('if')) for j in jobs.values() if isinstance(j, dict)
        for s in (j.get('steps') or []) if isinstance(s, dict) and s.get('if') is not None]
need(all('forgejo.server_url' not in v for v in ifs),
     f'a job/step if: still guards on forgejo.server_url: {[v for v in ifs if "forgejo.server_url" in v]!r}')
PY
  then
    return 1
  fi
  ok "t3: zero instance/repo host literals; zero startsWith(forgejo.server_url); no server_url inside any if: [C02 AC3, NOTE 3]"
}

leg_t4() {
  [ -f "$WF" ] || { printf 'FAIL: t4: %s does not exist (C01 creates it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
conc = doc.get('concurrency')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t4: {msg}', file=sys.stderr)
        sys.exit(1)


# RESEARCH TL;DR-2: Forgejo's default silently cancels in-flight runs of the
# same workflow, killing matrix builds mid-publish.
need(isinstance(conc, dict), 'no top-level concurrency: mapping (cancel-in-progress:false is mandatory, RESEARCH TL;DR-2)')
need(conc.get('cancel-in-progress') is False,
     f'concurrency.cancel-in-progress is {conc.get("cancel-in-progress")!r}, expected boolean false')
PY
  then
    return 1
  fi
  ok "t4: top-level concurrency.cancel-in-progress is boolean false [C01 AC3]"
}

leg_t5() {
  [ -f "$WF" ] || { printf 'FAIL: t5: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
detect = jobs.get('detect-changes') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


# NOTE 2: the PR/release split moves from a case inside one build job to two
# jobs gated by event AND role; the job-id set is the contract.
need(set(jobs) == {'detect-changes', 'build-release', 'build-pr'},
     f'jobs keys are {sorted(jobs)}, expected exactly detect-changes + build-release + build-pr (C02 renames build-and-push to build-release and adds build-pr)')
out = (detect.get('outputs') or {}).get('changed-containers')
need(isinstance(out, str) and 'steps.' in out,
     f'detect-changes.outputs.changed-containers is {out!r}, expected a steps.<id> reference (the detector emits it via GITHUB_OUTPUT)')
for name in ('build-release', 'build-pr'):
    build = jobs[name] or {}
    needs = build.get('needs')
    need(needs == 'detect-changes' or (isinstance(needs, list) and 'detect-changes' in needs),
         f'{name}.needs is {needs!r}, expected detect-changes')
    strat = build.get('strategy') or {}
    mat = (strat.get('matrix') or {}).get('container')
    need(isinstance(mat, str) and re.search(r'fromjson\s*\(', mat, re.I) and 'needs.detect-changes.outputs.changed-containers' in mat,
         f'{name}.matrix.container is {mat!r}, expected ${{{{ fromJSON(needs.detect-changes.outputs.changed-containers) }}}}')
    need(strat.get('fail-fast') is False,
         f'{name}.strategy.fail-fast is {strat.get("fail-fast")!r}, expected boolean false (one container failing must not cancel siblings)')
    jname = build.get('name')
    need(isinstance(jname, str) and 'matrix.container' in jname,
         f'{name}.name is {jname!r}, expected to interpolate matrix.container (per-cell unique job name, RESEARCH C matrix caveat)')
    if_expr = build.get('if') or ''
    need("!= '[]'" in if_expr,
         f"{name}.if is {if_expr!r}, expected to short-circuit on '[]' (no containers changed => no build matrix)")
PY
  then
    return 1
  fi
  ok "t5: job set is detect-changes + build-release + build-pr; both build jobs need the detect, matrix fromJSON with fail-fast false and a per-cell name, and short-circuit on '[]' [C02 AC2]"
}

leg_t6() {
  [ -f "$WF" ] || { printf 'FAIL: t6: %s does not exist (C01 creates it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

path = sys.argv[1]
raw = open(path).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t6: {msg}', file=sys.stderr)
        sys.exit(1)


uses = {s['uses'] for job in jobs.values() for s in (job or {}).get('steps', [])
        if isinstance(s, dict) and 'uses' in s}
# Mirror-independence (D8/RESEARCH C): data.forgejo.org's action set beyond
# checkout is unproven, so checkout@v7 is the only action this workflow may
# ask the mirror to resolve.
need(uses == {'actions/checkout@v7'}, f'uses set is {sorted(uses)}, expected exactly actions/checkout@v7')
for s in ('type=gha', 'build-push-action', 'setup-buildx-action', 'metadata-action', 'login-action'):
    need(raw.count(s) == 0, f'{s!r} occurs {raw.count(s)} time(s), expected zero (plain docker build/push only, D8)')
runs = '\n'.join(str(st.get('run', '')) for job in jobs.values()
                 for st in (job or {}).get('steps', []) if isinstance(st, dict) and 'run' in st)
need('docker build' in runs, 'no plain `docker build` in any run step')
need('docker push' in runs, 'no plain `docker push` in any run step')
PY
  then
    return 1
  fi
  ok "t6: uses is checkout@v7 only; no docker/* actions or gha-cache strings; plain docker build+push present [C01 AC8]"
}

leg_t7() {
  [ -f "$WF" ] || { printf 'FAIL: t7: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t7: {msg}', file=sys.stderr)
        sys.exit(1)


# Boundary-anchored (main-sync t5 pattern): a key that merely extends the
# original (PAT -> PATX) must not count as an occurrence of it.
def hits(text, key):
    return len(re.findall(re.escape('secrets.' + key) + r'(?![0-9A-Za-z_])', text))


def runs_of(job):
    return '\n'.join(str(s.get('run', '')) for s in ((jobs.get(job) or {}).get('steps') or [])
                     if isinstance(s, dict) and 'run' in s)


ghcr, forge = hits(raw, 'GHCR_PUSH_PAT'), hits(raw, 'FORGE_PUSH_TOKEN')
need(ghcr == 1,
     f'secrets.GHCR_PUSH_PAT occurs {ghcr} times file-wide, expected exactly once (AC4: the release job alone logs in to ghcr)')
need(forge == 2,
     f'secrets.FORGE_PUSH_TOKEN occurs {forge} times file-wide, expected twice — exactly one login per login-bearing job (build-release, build-pr), the dual-registry push credential (AC4)')
rel_text, pr_text = runs_of('build-release'), runs_of('build-pr')
need(hits(rel_text, 'GHCR_PUSH_PAT') == 1,
     'the single GHCR_PUSH_PAT reference is not inside build-release run steps')
need(hits(rel_text, 'FORGE_PUSH_TOKEN') == 1,
     f'build-release carries {hits(rel_text, "FORGE_PUSH_TOKEN")} forge-PAT references, expected exactly one login')
need(hits(pr_text, 'FORGE_PUSH_TOKEN') == 1,
     f'build-pr carries {hits(pr_text, "FORGE_PUSH_TOKEN")} forge-PAT references, expected exactly one login')
outside = sum(hits(runs_of(j), 'FORGE_PUSH_TOKEN') for j in jobs if j not in ('build-release', 'build-pr'))
need(outside == 0, f'{outside} FORGE_PUSH_TOKEN reference(s) under jobs other than build-release/build-pr')
# Each PAT sits in a docker login statement; YAML block scalars keep run lines
# verbatim, so a line-level scan of the raw file is exact here.
for key in ('GHCR_PUSH_PAT', 'FORGE_PUSH_TOKEN'):
    for m in re.finditer(re.escape('secrets.' + key) + r'(?![0-9A-Za-z_])', raw):
        line_end = raw.find('\n', m.start())
        stmt = raw[raw.rfind('\n', 0, m.start()) + 1:len(raw) if line_end == -1 else line_end]
        need('docker login' in stmt,
             f'a push-PAT reference ({key}) sits outside a docker login statement: {stmt.strip()!r} (PATs are referenced in login steps only)')
for tok in ('GITHUB_TOKEN', 'FORGEJO_TOKEN'):
    need(tok not in raw,
         f'the automatic per-run token {tok} is referenced; registry pushes are source-closed for it (the job-token permission check is a TODO upstream) — the human-minted FORGE_PUSH_TOKEN is the only forge credential')
PY
  then
    return 1
  fi
  ok "t7: GHCR_PUSH_PAT once in the build-release login; FORGE_PUSH_TOKEN once per login job and only in docker login steps; automatic tokens absent [C02 AC4]"
}

leg_t8() {
  [ -f "$WF" ] || { printf 'FAIL: t8: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t8: {msg}', file=sys.stderr)
        sys.exit(1)


def runs_of(job):
    return '\n'.join(str(s.get('run', '')) for s in ((jobs.get(job) or {}).get('steps') or [])
                     if isinstance(s, dict) and 'run' in s)


# C02 AC5: the tag arms are STATIC SHAPE per job — build-release owns the
# three-tag mirror on BOTH registries (OQ-6), build-pr owns the disposable
# pr- tag on the forge registry only. The job split IS the disjointness.
rel = runs_of('build-release')
need(rel, 'no build-release job with run steps — the release tag arms are unpinnable (C02 splits build-and-push into build-release + build-pr)')
need('latest' in rel, 'build-release never tags latest (D4: main builds repoint :latest on both registries)')
need(re.search(r'\bmain\b', rel), 'build-release never tags main (D4/OQ-6: :main mirrors to the forge registry too)')
need('%y.%m' in rel, 'build-release carries no `date +%y.%m` calendar month computation (D3)')
need('next-n' in rel, 'build-release never runs `next-n` (D3 registry-derived calendar N)')
need('ghcr.io/ownyourio/' in rel, 'build-release assembles no ghcr.io/ownyourio/ image reference')
need('curatedforest' in rel,
     'build-release assembles no curatedforest/<image> forge reference (OQ-6 mirror: the same three tags land on the instance registry, lowercase owner segment per RD6)')
# C02 AC5 / OQ-6 mirror, static form, per registry SIDE: (a) each side's own
# statements must name its calendar/latest/main tag variables, and (b) the
# PUSH CHAIN of each side — the `docker push` statements attributed to it,
# their enclosing for: lists, and the variables those reach transitively —
# must carry the registry's image prefix AND all three tags. Attribution
# follows r3's rule (registry token in the push line or its enclosing for:
# list). Assembled-but-never-pushed tags and tag strings never qualified with
# an image reference are the two shapes that silently lose a mirror arm (the
# superseded RD9 forge arm pushed a subset; a per-step co-presence check let
# it through), and neither is visible without following the chain to the push
# (header pin: per-side naming plus push-chain iteration).
steps_rel = [str(s.get('run', '')) for s in ((jobs.get('build-release') or {}).get('steps') or [])
             if isinstance(s, dict) and 'run' in s]
rel_statements = []
for r in steps_rel:
    buf = ''
    for ln in r.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            rel_statements.append((buf + ' ' + st).strip())
        buf = ''


def has_cal(text, token):
    return ('%y.%m' in text or '$month' in text
            or bool(re.search(token + r'\w*(cal|calendar|release|ver)', text, re.IGNORECASE)))


PREFIX = {'ghcr': 'ghcr.io/ownyourio/', 'forge': 'curatedforest'}
push_lines = {'ghcr': [], 'forge': []}
push_lists = {'ghcr': [], 'forge': []}
stack = []
for s in rel_statements:
    if s.startswith('#'):
        continue
    m = re.match(r'^for\b.*\bin\b(.*)$', s)
    if m:
        stack.append(re.sub(r';\s*do\s*$', '', m.group(1)).strip())
    elif re.match(r'^done\b', s) and stack:
        stack.pop()
    if 'docker push' in s:
        low = (s + ' ' + (stack[-1] if stack else '')).lower()
        for tok in ('ghcr', 'forge'):
            if tok in low:
                push_lines[tok].append(s)
                if stack:
                    push_lists[tok].append(stack[-1])

assignments = {}
for s in rel_statements:
    if '=' in s and not s.startswith('#'):
        assignments.setdefault(s.split('=', 1)[0].strip(), s)

for token in ('ghcr', 'forge'):
    stmts = [s for s in rel_statements if token in s.lower() and not s.startswith('#')]
    need(stmts, f'no {token}-named statement in build-release — per-side variables carry the registry token (header pin)')
    need(any('latest' in s for s in stmts),
         f'no {token}-side statement tags latest — the three-tag trio must be assembled for EACH registry (OQ-6 mirror, AC5)')
    need(any(re.search(r'\bmain\b', s) for s in stmts),
         f'no {token}-side statement tags main — the three-tag trio must be assembled for EACH registry (OQ-6 mirror, AC5)')
    need(any(has_cal(s, token) for s in stmts),
         f'no {token}-side statement carries the calendar tag — the three-tag trio must be assembled for EACH registry (OQ-6 mirror, AC5)')
    need(push_lines[token],
         f'no {token}-attributed docker push in build-release — the release must publish the trio to {token}; name the registry token in the push line or its enclosing for: list (header pin, r3)')
    chain = push_lines[token] + push_lists[token]
    seen = set()
    for _ in range(3):
        names = {v for text in chain for v in re.findall(r'\{?(\w+)\}?', text)} - seen
        seen |= names
        chain += [assignments[v] for v in names if v in assignments]
    blob = '\n'.join(chain)
    need(PREFIX[token] in blob,
         f'the {token} push chain builds no image-qualified reference ({PREFIX[token]}<image>:<tag>) — a bare tag string is not a push target (OQ-6, RD6: the forge owner segment is lowercase curatedforest)')
    need('latest' in blob,
         f'the {token} push chain never reaches a latest tag — iterate the per-side tag variables on the for: line (or a {token} tag-list variable assembled with all three); a tag no push chain reaches is never pushed (OQ-6, AC5)')
    need(re.search(r'\bmain\b', blob),
         f'the {token} push chain never reaches the main tag — iterate the per-side tag variables on the for: line (or a {token} tag-list variable assembled with all three); a tag no push chain reaches is never pushed (OQ-6, AC5)')
    need(has_cal(blob, token),
         f'the {token} push chain never reaches the calendar tag — the registry-derived N is one of the three tags (D3/OQ-6); a tag no push chain reaches is never pushed')
pr = runs_of('build-pr')
need(pr, 'no build-pr job with run steps — the PR tag arm is unpinnable (NOTE 2: pull_request publishes pr-<branch>-<sha> to the local registry only)')
need('pr-' in pr, 'the build-pr job assembles no pr- prefixed tag (D5)')
need(not re.search(r'\blatest\b', pr),
     'build-pr names a latest token — a PR must never touch a rolling or calendar tag (D5/OQ-6: PRs are forge-pr-only)')
need(not re.search(r'\bmain\b', pr),
     'build-pr names a main token — a PR must never touch a rolling or calendar tag (D5/OQ-6)')
need('ghcr.io' not in pr,
     'build-pr references ghcr.io — the PR job is forge-registry-only and must work with zero ghcr secret (NOTE 2)')
need('curatedforest' in pr, 'build-pr assembles no curatedforest/<image> forge reference (the PR tag lands in the instance registry only)')
need('sanitize' in pr, 'build-pr never invokes `sanitize` (D5 tag component)')
need('rev-parse --short' in pr, 'build-pr never runs `git rev-parse --short` (D5 build-hash component)')
PY
  then
    return 1
  fi
  ok "t8: build-release mirrors calendar+latest+main on ghcr AND the forge ref; build-pr is a forge-only pr- tag with sanitize+short-sha and no ghcr/rolling token [C02 AC5]"
}

leg_t9() {
  [ -f "$WF" ] || { printf 'FAIL: t9: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

LABELS = {'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'docker', 'node22'}
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t9: {msg}', file=sys.stderr)
        sys.exit(1)


for name, job in jobs.items():
    label = (job or {}).get('runs-on')
    need(label in LABELS, f'{name}.runs-on is {label!r}, not one of the advertised lab runner labels {sorted(LABELS)} (EXPLORE §3)')
    runs = [s['run'] for s in (job or {}).get('steps', []) if isinstance(s, dict) and 'run' in s]
    need(runs, f'{name} has no run: steps')
    for i, r in enumerate(runs):
        need(r.lstrip().startswith('set -euo pipefail'),
             f'{name} run step {i + 1} does not begin with set -euo pipefail (house style, AC10)')
# The ROLE-era house diag echoes the raw ROLE (main-sync precedent) instead of
# the retired server_url, and still records docker reachability first-fire.
diag = [r for job in jobs.values() for r in
        (str(s.get('run', '')) for s in (job or {}).get('steps', []) if isinstance(s, dict) and 'run' in s)
        if 'ROLE' in r and 'docker' in r]
need(diag, 'no diag step names both ROLE and docker (the ROLE-era house shape per main-sync; the server_url echo retires with C02)')
PY
  then
    return 1
  fi
  ok "t9: every run block opens set -euo pipefail; runs-on advertised; diag step names ROLE + docker [C02 AC6]"
}

leg_t10() {
  [ -f "$WF" ] || { printf 'FAIL: t10: %s does not exist (C01 creates it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps = (jobs.get('detect-changes') or {}).get('steps') or []
emit = [str(s.get('run', '')) for s in steps
        if isinstance(s, dict) and 'run' in s and 'changed-containers=' in str(s.get('run', ''))]


def need(cond, msg):
    if not cond:
        print(f'FAIL: t10: {msg}', file=sys.stderr)
        sys.exit(1)


# Review round 1 major-1: `echo "k=$(cmd)"` reports echo's exit code, so under
# set -euo pipefail a detector that fails loudly on an unresolvable range is
# swallowed at the emit site — the detect job goes green and emits an empty
# value, and the build matrix receives fromJSON(''). A standalone assignment
# propagates the exit instead; the emit then only interpolates the variable.
need(len(emit) == 1, f'{len(emit)} detect-changes run steps mention changed-containers=, expected exactly the one emit step')
text = emit[0]
m = re.search(r'(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)=[ \t]*\$\(bash scripts/forgejo-container-detect\.sh[ \t]+detect[^\n]*\)[ \t]*$', text)
need(m, 'no standalone assignment of the detector output (pattern: var=$(bash scripts/forgejo-container-detect.sh detect)) — assign first, emit after (major-1)')
var = m.group(1)
emits = [ln for ln in text.splitlines() if 'changed-containers=' in ln]
need(emits, 'changed-containers= is never emitted')
for ln in emits:
    need(re.match(r'^\s*(echo|printf)\b', ln), f'the changed-containers= statement {ln.strip()!r} is not an echo/printf emit statement')
    need(re.search(r'\$\{?' + re.escape(var) + r'\b', ln), f'the changed-containers= statement {ln.strip()!r} does not interpolate the assigned ${var}')
    need('$(' not in ln, f'the changed-containers= statement {ln.strip()!r} re-inlines a command substitution — echo $(...) discards the detector exit (major-1)')
    need(re.search(r'GITHUB_OUTPUT|FORGEJO_OUTPUT', ln), f'the emit statement {ln.strip()!r} does not append to the step-output file (GITHUB_OUTPUT/FORGEJO_OUTPUT)')
PY
  then
    return 1
  fi
  ok "t10: detect-emit assigns the detector output before emitting changed-containers=\$var — echo \$(...) at the emit site would mask a failed detector [C01 review r1 major-1]"
}

leg_t11() {
  [ -f "$WF" ] || { printf 'FAIL: t11: %s does not exist (C01 creates it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, shlex, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps_txt = [str(s.get('run', '')) for s in ((jobs.get('build-release') or {}).get('steps') or [])
             if isinstance(s, dict) and 'run' in s]


def need(cond, msg):
    if not cond:
        print(f'FAIL: t11: {msg}', file=sys.stderr)
        sys.exit(1)


# Run -1 generalizes the review-round-1 major-2 to per-registry side: GHCR
# answers 403 DENIED (never-pushed token endpoint) and the forge registry 404
# NAME_UNKNOWN (no such package), so EVERY read on either side must answer
# absence as an HTTP code (no fail-flag), 401/403/404 fall through to that
# side's n=1 default, and each side's calendar walk runs only inside that
# side's list-200 branch — the manifest endpoint answers 401 unauthenticated,
# so the walk's 200/404 semantics need the authenticated read. The walk gates
# ONLY the calendar tag: :latest/:main are mutable-by-contract and carry no
# walk precondition, so nothing here demands one before a rolling push.
# Statements are side-attributed by their ghcr/forge naming token (header pin).
need(steps_txt,
     'no build-release job with run steps — t11 pins its per-side registry reads (C02 renames build-and-push to build-release and generalizes the derivation to both registries)')

statements = []
for text in steps_txt:
    buf = ''
    for ln in text.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            statements.append((buf + ' ' + st).strip())
        buf = ''

reads = [s for s in statements
         if 'curl' in s and ('tags/list' in s or 'manifests/' in s or 'ghcr.io/token' in s)]
need(reads, 'no curl read of a registry endpoint (token / tags/list / manifests) in build-release run steps')


def fail_flag(call):
    try:
        toks = shlex.split(call)
    except ValueError:
        toks = call.split()
    for t in toks:
        if t in ('--fail', '--fail-with-body'):
            return t
        if t.startswith('-') and not t.startswith('--') and 'f' in t[1:]:
            return t
    return None


for c in reads:
    bad = fail_flag(c)
    need(bad is None, f'the registry read {c.strip()!r} carries {bad} — a fail-flagged call aborts on the 403/404 a never-pushed image answers, before next-n runs (major-2, both sides)')
    need('%{http_code}' in c, f'the registry read {c.strip()!r} does not capture the HTTP code — absence must arrive as a status, not a transport failure (major-2)')


def side(stmt):
    low = stmt.lower()
    if 'ghcr' in low:
        return 'ghcr'
    if 'forge' in low:
        return 'forge'
    return None


need(any('ghcr.io/token' in s for s in reads),
     'the ghcr pull-token fetch is gone — C02 carries the ghcr-side token/walk shape over byte-stable (t11 generalization keeps it)')
tags_lists = [s for s in reads if 'tags/list' in s]
need(any(side(s) == 'ghcr' for s in tags_lists),
     'no ghcr-side tags/list read — name the side\'s variables ghcr_*/forge_* so the static legs can tell the two registry arms apart (header pin)')
need(any(side(s) == 'forge' for s in tags_lists),
     'no forge-side tags/list read — union-max N reads BOTH registries before any push (RD8/P3)')

joined = '\n'.join(steps_txt)
defaults = re.findall(r'(?m)^[ \t]*[A-Za-z_][A-Za-z0-9_]*=1[ \t]*(#.*)?$', joined)
need(len(defaults) >= 2,
     f'{len(defaults)} unconditional =1 default line(s), expected one per side — a tolerated-absent read must fall through to that side\'s first release of the month (RD8: n = max of the two next-n outputs, each side defaulting to 1)')
nncalls = [s for s in statements if 'next-n' in s]
need(len(nncalls) >= 2, f'{len(nncalls)} next-n call(s), expected two (n = max of the two next-n outputs, RD8)')

lines = joined.splitlines()


def if_block(pred):
    """(start, end) line indices of the first if-block whose header matches pred,
    end excluded; end is the elif/else/fi line closing the block at header indent."""
    for i, ln in enumerate(lines):
        if re.match(r'^[ \t]*if\b', ln) and pred(ln):
            ind = len(ln) - len(ln.lstrip())
            j = i + 1
            while j < len(lines):
                s = lines[j]
                if len(s) - len(s.lstrip()) <= ind and s.strip().startswith(('elif', 'else', 'fi')):
                    break
                j += 1
            return i, j
    return None


for want in ('ghcr', 'forge'):
    blk = if_block(lambda ln, w=want: w in ln.lower() and 'list' in ln and '200' in ln)
    need(blk, f'no `{want}`-side `if [ "$<want>_list_code" = 200 ]` branch — next-n may parse the body only on that side\'s 200 tags/list answer')
    walk = '\n'.join(lines[blk[0] + 1:blk[1]])
    need(re.search(r'(?m)^[ \t]*while\b', walk) and 'manifests/' in walk,
         f"the {want} existence-advance walk (while + manifests check) must stay inside that side's list-200 branch: a registry whose list answered 404 contributes no tags and gets no walk (R2 invariant 2, per side)")

token_blk = if_block(lambda ln: 'token' in ln.lower() and '200' in ln and 'forge' not in ln.lower())
need(token_blk, 'no ghcr `if [ "$token_code" = 200 ]` branch — the ghcr reads and walk must run only under a pull token')
gl = if_block(lambda ln: 'ghcr' in ln.lower() and 'list' in ln and '200' in ln)
need(token_blk[0] < gl[0] and gl[1] <= token_blk[1],
     'the ghcr tags/list branch is not inside the pull-token branch')
token_body = '\n'.join(lines[token_blk[0] + 1:token_blk[1]])
need(re.search(r'\[\s*-z\b', token_body) and 'exit 1' in token_body,
     'the ghcr pull-token branch lost its empty-token fail-loud guard — a 200 with no token would make tags/list answer 401, the tolerated no-tags code, publishing N=1 over a taken tag with no walk to stop it (run-0 shape, generalization keeps it)')

for want in ('ghcr', 'forge'):
    tol = [ln for ln in lines
           if want in ln.lower() and '_code' in ln and all(code in ln for code in ('401', '403', '404'))]
    need(tol, f"no {want}-side tolerance branch names the 401/403/404 no-readable-tags answer — those must fall through to that side's n=1 while any other code stays fatal (major-2 per side, R2 invariant 5)")
PY
  then
    return 1
  fi
  ok "t11: per-side reads carry no -f/--fail and capture the HTTP code; each side's 401/403/404 tolerance falls through to its own n=1; each side's calendar walk stays inside its list-200 branch; ghcr keeps the pull-token nesting and empty-token guard [C02 AC5, review r1 major-2 per side]"
}

# --- Run -2 C01 pins (t12-t15): depth, accessors, echo, loud-failure ---------

leg_t12() {
  [ -f "$WF" ] || { printf 'FAIL: t12: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t12: {msg}', file=sys.stderr)
        sys.exit(1)


def checkouts(job):
    return [s for s in ((jobs.get(job) or {}).get('steps') or [])
            if isinstance(s, dict) and s.get('uses') == 'actions/checkout@v7']


# t6 pins uses: but never reads with:, and deleting the depth block survived
# 29/29 (EXPLORE R2 section 6): this is the leg the owner's review comment
# asked for. Full history is what makes the pushed range resolve locally — at
# the depth-1 default the endpoints are absent and detection dies 'bad object'
# exit 128 — so the input is load-bearing, not decorative, and the two build
# jobs (which never diff a range) paying the cost again would be a regression.
det = checkouts('detect-changes')
need(len(det) == 1, f'{len(det)} checkout steps in detect-changes, expected exactly one')
w = det[0].get('with')
need(isinstance(w, dict) and 'fetch-depth' in w,
     "the detect-changes checkout has no with: fetch-depth — deleting the block puts "
     'checkout at its depth-1 default, where the before..sha endpoints do not exist; the '
     'owner fear shape must not be survivable (mutation column: deleting L85-88 reddens here)')
depth = w.get('fetch-depth')
# bool is a subclass of int in python: fetch-depth: false must not pass as 0.
need(type(depth) is int and depth == 0,
     f'fetch-depth is {depth!r}, expected the integer 0 exactly (1, "2", "0" and false all '
     'red — any non-zero depth re-creates the blind checkout)')
for name in ('build-release', 'build-pr'):
    for s in checkouts(name):
        need(s.get('with') is None,
             f"{name}'s checkout gained with: {s.get('with')!r} — the depth-0 cost is paid "
             'exactly once, in detect-changes')
PY
  then
    return 1
  fi
  ok "t12: detect-changes checks out with the integer fetch-depth 0 (the only shape where a non-tip commit of a push stays visible) and the two build jobs stay bare [run -2 C01, invariant 1]"
}

leg_t13() {
  [ -f "$WF" ] || { printf 'FAIL: t13: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps = (jobs.get('detect-changes') or {}).get('steps') or []
detect_steps = [s for s in steps if isinstance(s, dict)
                and 'changed-containers=' in str(s.get('run', ''))]


def need(cond, msg):
    if not cond:
        print(f'FAIL: t13: {msg}', file=sys.stderr)
        sys.exit(1)


need(len(detect_steps) == 1,
     f'{len(detect_steps)} steps carry changed-containers=, expected the one detect step')
# The detector consumes exactly these six variables (EXPLORE section 2: no
# head_ref, no commits[]), so this mapping IS the payload-to-shell contract.
# A typo'd accessor resolves empty at runtime; pre-A5 that fell into the
# tip-only fallback as a green run — the textual pin is the only offline
# tooth. It cannot prove the payload carries the field: RESEARCH R1 section 1
# (the v15.0.10 producer sweep) does that, and the optional H-P1 dispatch
# probe would observe it live (RP8).
EXPECTED = {
    'EVENT_NAME': '${{ forgejo.event_name }}',
    'EVENT_BEFORE': '${{ forgejo.event.before }}',
    'SHA': '${{ forgejo.sha }}',
    'BASE_SHA': '${{ forgejo.event.pull_request.base.sha }}',
    'HEAD_SHA': '${{ forgejo.event.pull_request.head.sha }}',
    'MANUAL_CONTAINERS': '${{ forgejo.event.inputs.containers }}',
}
env = detect_steps[0].get('env')
need(isinstance(env, dict), 'the detect step has no env: mapping')
need(set(env) == set(EXPECTED),
     f'env keys are {sorted(env)}, expected exactly {sorted(EXPECTED)}')
for key, value in EXPECTED.items():
    need(env.get(key) == value,
         f'env.{key} is {env.get(key)!r}, expected exactly {value!r} (r1 byte-constant '
         'discipline: the accessor string, not just the variable name, is the contract)')
PY
  then
    return 1
  fi
  ok "t13: the six detect-step env: accessors are byte-exact — textual pin only; proving the payload carries the field is R1's source chain and the optional H-P1 probe, never this leg [run -2 C01, invariant 7]"
}

# t14_step_warn <sdir> <label> <expect yes|no> <VAR=val>... — executes the
# SHIPPED detect-step run body (staged as <sdir>/step.sh) against the shipped
# detector copied into a scratch git repo, with faithful per-event env, and
# asserts whether the step's stdout carried the ::warning:: verdict. This is
# the shape-level pin: compound guard lines cannot be grammar-checked
# statically without over-fitting one spelling (run -1's r5 lesson), while
# the warning's SCOPE is a runnable fact.
t14_step_warn() {
  local sdir="$1" label="$2" expect="$3"
  shift 3
  local out rc
  if out=$( cd "$sdir" && env GITHUB_OUTPUT="$sdir/output" EVENT_NAME= EVENT_BEFORE= SHA= \
      BASE_SHA= HEAD_SHA= MANUAL_CONTAINERS= "$@" bash step.sh 2>/dev/null ); then
    rc=0
  else
    rc=$?
  fi
  [ "$rc" -eq 0 ] || { printf 'FAIL: t14: the detect step exited %d when executed for the %s scenario — the run body must stay offline-executable for its warning scope to be pinnable\n' "$rc" "$label" >&2; return 1; }
  case "$out" in
    *'changed containers:'*) ;;
    *) printf 'FAIL: t14: the step run for the %s scenario printed no "changed containers:" verdict line\n' "$label" >&2; return 1 ;;
  esac
  local warned=no
  case "$out" in *'::warning::'*) warned=yes ;; esac
  if [ "$expect" = yes ] && [ "$warned" = no ]; then
    printf 'FAIL: t14: the %s scenario resolved an empty set with NO ::warning:: — the empty-push/PR warning was silenced for an arm that must warn (only dispatch and before==sha are exempt)\n' "$label" >&2
    return 1
  fi
  if [ "$expect" = no ] && [ "$warned" = yes ]; then
    printf 'FAIL: t14: the %s scenario WARNED although it is one of the two exempt shapes — a silently dropped exemption (the before==sha no-op and the dispatch empty list are correct semantics, not anomalies)\n' "$label" >&2
    return 1
  fi
  return 0
}

leg_t14() {
  [ -f "$WF" ] || { printf 'FAIL: t14: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps = (jobs.get('detect-changes') or {}).get('steps') or []
text = next((str(s.get('run', '')) for s in steps
             if isinstance(s, dict) and 'changed-containers=' in str(s.get('run', ''))), '')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t14: {msg}', file=sys.stderr)
        sys.exit(1)


need(text, 'no detect step found')
m = re.search(r'(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)=[ \t]*\$\(bash scripts/forgejo-container-detect\.sh[ \t]+detect[^\n]*\)[ \t]*$', text)
need(m, 'no standalone assignment of the detector output — the echo must read the assigned variable (t10 shape)')
var = m.group(1)
marker = [ln for ln in text.splitlines() if 'changed containers:' in ln]
# Predecessor parity: main's .github/workflows/docker-build.yaml echoes
# "Changed containers: $RESULT"; the forge port silently dropped it (EXPLORE
# section 5), leaving a green run that built nothing indistinguishable from
# one that found nothing. This leg exists so the echo cannot be dropped a
# second time. Claims stay log-line-only: v15.0.10 renders no annotation and
# runner v13.2.0 does not interpret ::notice:: (RESEARCH section 7).
need(marker, 'the detect step never echoes the marker "changed containers:" — the nothing-built verdict is silent again (a port already dropped this line once)')
joined = '\n'.join(marker)
need(re.search(r'\$\{?' + re.escape(var) + r'\b', joined),
     f'the "changed containers:" echo never interpolates the assigned var {var}')
for ln in marker:
    need('$(' not in ln, f'the echo line {ln.strip()!r} re-inlines a command substitution (t10 discipline)')
for tok in ('EVENT_NAME', 'EVENT_BEFORE', 'SHA', 'BASE_SHA', 'HEAD_SHA'):
    need(re.search(r'\b' + tok + r'\b', joined),
         f'the echo never names {tok} — legibility is set + event + both endpoint values the step holds (OQ-e/OQ-k ruling)')
need(text.count('$(bash scripts/forgejo-container-detect.sh') == 1,
     'a second detect command substitution appeared — exactly the assignment may invoke the detector')
need(sum(1 for ln in text.splitlines() if 'changed-containers=' in ln) == 1,
     'more than one line writes changed-containers= — the emit line stays the sole output carrier')
warn = [ln for ln in text.splitlines() if '::warning::' in ln]
need(warn, 'no ::warning:: for an empty push/PR set — the empty outcome must be loud in the job log (a marked log line, nothing more on this build)')
need(any(re.search(r'\$\{?' + re.escape(var), ln) and '[]' in ln for ln in text.splitlines()),
     "nothing compares the assigned set against the empty array '[]' — the warning must fire on the empty resolution")
need('workflow_dispatch' in text,
     'the step never names workflow_dispatch — dispatch-empty is correct semantics and stays '
     'un-annotated (OQ-e exemption), so the warning branch must carry the event it skips')
PY
  then
    return 1
  fi
  # The behavioral half of t14: the before == sha exemption shipped MISSING in
  # C01 round 1 and survived every static clause of this leg — a text pin of a
  # compound guard line is the wrong tool, the exemption SCOPE is a fact of
  # execution. Five faithful payload scenarios, executed against the shipped
  # run body + shipped detector in a scratch git repo: only the dispatch
  # no-op, the before==sha no-op and a non-empty set stay silent; a real
  # empty push range and a real empty PR merge-base range both warn. The
  # all-zero first-push shape is deliberately not pinned here (the detector
  # owns that announcement, d11; the step warning there is the shipped
  # behavior, and neither posture may be demanded by this leg).
  local sdir="$TMP/t14-step"
  rm -rf "$sdir"; mkdir -p "$sdir/containers/alpha" "$sdir/scripts" \
    || { printf 'FAIL: t14: harness could not stage the step-run scratch dir\n' >&2; return 1; }
  cp "$HELP" "$sdir/scripts/forgejo-container-detect.sh" \
    || { printf 'FAIL: t14: harness could not copy the shipped detector into the scratch repo\n' >&2; return 1; }
  printf 'FROM scratch\n' > "$sdir/containers/alpha/Dockerfile"
  echo readme > "$sdir/README.md"
  git -C "$sdir" init -q . && git -C "$sdir" config user.email test@example.invalid && git -C "$sdir" config user.name test \
    && git -C "$sdir" add -A && git -C "$sdir" commit -qm a \
    || { printf 'FAIL: t14: harness could not init the scratch git repo (scratch trees must be their own repo)\n' >&2; return 1; }
  local S_A S_B S_C
  S_A=$(git -C "$sdir" rev-parse HEAD) || return 1
  echo readme2 > "$sdir/README.md"
  git -C "$sdir" add -A && git -C "$sdir" commit -qm b || return 1
  S_B=$(git -C "$sdir" rev-parse HEAD) || return 1
  echo change > "$sdir/containers/alpha/Dockerfile"
  git -C "$sdir" add -A && git -C "$sdir" commit -qm c || return 1
  S_C=$(git -C "$sdir" rev-parse HEAD) || return 1
  if ! python3 - "$WF" "$sdir/step.sh" <<'PY'
import sys, yaml
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps = (jobs.get('detect-changes') or {}).get('steps') or []
texts = [str(s.get('run', '')) for s in steps
         if isinstance(s, dict) and 'run' in s and 'changed-containers=' in str(s.get('run', ''))]
if len(texts) != 1:
    print(f'FAIL: t14: {len(texts)} run bodies carry changed-containers=, expected the one emit step (body not staged for execution)', file=sys.stderr)
    sys.exit(1)
open(sys.argv[2], 'w').write(texts[0])
PY
  then
    return 1
  fi
  # A real dispatch/PR payload still carries forgejo.sha (the dispatch
  # ref's commit; the PR head), and EVENT_BEFORE resolves empty — the
  # scenarios pass those faithful shapes so no mutation can hide a dropped
  # dispatch exemption behind the empty==empty before==sha exemption.
  t14_step_warn "$sdir" 'empty dispatch list'        no  EVENT_NAME=workflow_dispatch MANUAL_CONTAINERS= "SHA=$S_C" || return 1
  t14_step_warn "$sdir" 'before-equals-sha push'     no  EVENT_NAME=push "EVENT_BEFORE=$S_B" "SHA=$S_B" || return 1
  t14_step_warn "$sdir" 'real empty push range'      yes EVENT_NAME=push "EVENT_BEFORE=$S_A" "SHA=$S_B" || return 1
  t14_step_warn "$sdir" 'real empty PR range'        yes EVENT_NAME=pull_request "BASE_SHA=$S_A" "HEAD_SHA=$S_B" "SHA=$S_B" || return 1
  t14_step_warn "$sdir" 'non-empty push set'         no  EVENT_NAME=push "EVENT_BEFORE=$S_A" "SHA=$S_C" || return 1
  ok "t14: the detect step echoes changed containers: with the event and endpoint values from the assigned variable, and the ::warning:: scope executes right — empty push/PR ranges warn, the dispatch no-op, the before==sha no-op and a non-empty set stay silent (executed, not just texted; job-log legibility only, no UI-chip claim) [run -2 C01, invariant 6]"
}

leg_t15() {
  if ! python3 - <<'PY'
import re, sys

path = 'scripts/forgejo-container-detect.sh'
lines = open(path).read().splitlines()


def need(cond, msg):
    if not cond:
        print(f'FAIL: t15: {msg}', file=sys.stderr)
        sys.exit(1)


# r3's || true ban stops at the workflow file; the detector's own loud-failure
# posture (its no-masking comment) had zero teeth — re-adding a silencer
# survived 29/29 (EXPLORE section 6). The channel law pairs with it: stdout is
# the JSON carrier, so errexit is what propagates a bad range to the step.
first_set = next((ln for ln in lines if re.match(r'^set\b', ln)), None)
need(first_set is not None and first_set.strip() == 'set -eu',
     f'the first top-level set command is {first_set!r}, expected exactly "set -eu" — without '
     'errexit, the 128 propagation d13 pins is a lie')
need(not any(re.match(r'^set \+e', ln) for ln in lines), 'set +e appears — errexit is re-disabled somewhere')

try:
    start = next(i for i, ln in enumerate(lines) if re.match(r'^detect\(\)', ln))
except StopIteration:
    need(False, 'no detect() function to scope the scan to (harness fault, not a code red)')
end = next((i for i in range(start + 1, len(lines)) if lines[i] == '}'), None)
need(end is not None, 'detect() body does not close at column 0 (harness fault, not a code red)')

for ln in lines[start + 1:end]:
    st = ln.strip()
    if not st or st.startswith('#') or not re.search(r'\bgit\b', st):
        continue
    need('|| true' not in st and '|| :' not in st and '2>/dev/null' not in st
         and '>/dev/null' not in st and '&>' not in st and not st.startswith('if git'),
         f'a git call in detect() gained a silencer: {st!r} — a range that cannot resolve must '
         "fail the job, never report 'nothing changed'; the sanctioned tolerator is next-n's "
         'grep absence filter, named by the scan below')

for ln in lines:
    st = ln.strip()
    if st and not st.startswith('#') and '|| true' in st:
        need('grep' in st,
             f'an unexpected "|| true" silencer at {st!r} — the one tolerated occurrence is '
             "next-n's grep -E month filter (absence-tolerance by design: a month with no "
             'calendar tags answers nothing, which is data, not a malfunction); anywhere else '
             'it turns a real failure green')
PY
  then
    return 1
  fi
  ok "t15: set -eu stands and no git call in detect() carries || true, 2>/dev/null, a masking redirect or an if-git soft-pedal; next-n's tolerated grep || true is the named exemption [run -2 C01, invariant 5]"
}

# --- C02 run -1 ROLE/dual-registry legs (r1-r5): containers-build.yaml --------

# r1-r5 pin the run -1 contract on .forgejo/workflows/containers-build.yaml
# alone (no-mixing: they read no other file). The guard bytes are the
# owner-confirmed cannot-error spellings — an expression ERROR fails a job on
# the deployed runner while a false guard merely skips it, and no live probe
# will have exercised this engine before the first real run (OQ-3 ruling), so
# the pin is byte-exact.

leg_r1() {
  [ -f "$WF" ] || { printf 'FAIL: r1: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

path = sys.argv[1]
doc = yaml.safe_load(open(path))
jobs = (doc or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: r1: {msg}', file=sys.stderr)
        sys.exit(1)


# C02 AC2 pinned bytes. Unset ROLE widens (== null also covers set-but-empty),
# contains is case-insensitive substring and never errors; swapping contains
# for == or dropping the null clause reddens the byte comparison (mutation
# teeth). fromJSON stays banned exactly where the OQ-2 ruling puts it: it may
# not guard and never evaluates an instance-set value, because a hand-typed
# ROLE that is unset/empty/non-JSON ERRORS and fails the job.
DETECT_IF = "vars.ROLE == null || contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')"
RELEASE_IF = "forgejo.event_name != 'pull_request' && (vars.ROLE == null || contains(vars.ROLE, 'prod')) && needs.detect-changes.outputs.changed-containers != '[]'"
PR_IF = "forgejo.event_name == 'pull_request' && (vars.ROLE == null || contains(vars.ROLE, 'dev')) && needs.detect-changes.outputs.changed-containers != '[]'"

need(set(jobs) == {'detect-changes', 'build-release', 'build-pr'},
     f'jobs keys are {sorted(jobs)}, expected exactly detect-changes + build-release + build-pr (C02 job split)')
for name, want in (('detect-changes', DETECT_IF), ('build-release', RELEASE_IF), ('build-pr', PR_IF)):
    got = (jobs.get(name) or {}).get('if')
    need(got == want,
         f'{name}.if is {got!r}, expected exactly {want!r} (the owner-confirmed cannot-error guard bytes, C02 AC2)')

ifs = [str(j.get('if') or '') for j in jobs.values() if isinstance(j, dict)]
ifs += [str(s.get('if') or '') for j in jobs.values() if isinstance(j, dict)
        for s in (j.get('steps') or []) if isinstance(s, dict)]
bad_ifs = [v for v in ifs if 'fromjson' in v.lower()]
need(not bad_ifs,
     f'fromJSON sits in a job/step if: ({bad_ifs!r}) — a guard may not use a function that errors on unset or malformed input (OQ-2: an error fails the job; a false guard only skips)')

carriers = []


def collect(node, where):
    if isinstance(node, str):
        if 'fromjson' in node.lower():
            carriers.append((where, node))
    elif isinstance(node, dict):
        for k, v in node.items():
            collect(v, f'{where}.{k}')
    elif isinstance(node, list):
        for i, v in enumerate(node):
            collect(v, f'{where}[{i}]')


collect(doc, 'doc')
for where, s in carriers:
    need('needs.detect-changes.outputs.changed-containers' in s and 'vars.' not in s,
         f'fromJSON outside the sanctioned matrix carrier: {where} is {s!r} — the only sanctioned fromJSON parses the DETECTOR\'s own JSON output (C02 Tasks carry it over; t5 pins it); it never evaluates a vars.* instance-set value (OQ-2)')
PY
  then
    return 1
  fi
  ok "r1: the three pinned if: byte-strings are exact over the {detect-changes, build-release, build-pr} set; fromJSON guards nothing and never evaluates a vars.* value (matrix-over-detector-output is the one carrier) [C02 AC2]"
}

leg_r2() {
  [ -f "$WF" ] || { printf 'FAIL: r2: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps_txt = [str(s.get('run', '')) for s in ((jobs.get('build-release') or {}).get('steps') or [])
             if isinstance(s, dict) and 'run' in s]


def need(cond, msg):
    if not cond:
        print(f'FAIL: r2: {msg}', file=sys.stderr)
        sys.exit(1)


# RD8/P3 with R2 invariants 1-2: one calendar N for both registries demands
# BOTH tags/list reads and BOTH calendar walks to complete before the first
# docker push — a shape that reads/walks one registry and then pushes the
# other at the same un-walked N silently overwrites the leading side (both
# registries are fully mutable). Statements carry their ghcr/forge token so
# the two sides are distinguishable statically (header pin).
need(steps_txt, 'no build-release job with run steps (C02 renames build-and-push and adds the derivation for both registries)')

statements = []
for text in steps_txt:
    buf = ''
    for ln in text.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            statements.append((buf + ' ' + st).strip())
        buf = ''

push_i = [i for i, s in enumerate(statements) if 'docker push' in s]
read_i = [i for i, s in enumerate(statements)
          if 'curl' in s and ('tags/list' in s or 'manifests/' in s or 'ghcr.io/token' in s)]
need(push_i, 'no docker push in build-release — the release arms must publish the three-tag mirror')
need(read_i, 'no registry derivation reads (tags/list / manifests / token) in build-release run steps')
need(max(read_i) < min(push_i),
     'a registry read or calendar walk sits after the first docker push — union-max N with the per-registry walk must COMPLETE before any push, so no arm can publish at an N the other side has not been walked at (R2 invariants 1-2)')


def side(stmt):
    low = stmt.lower()
    if 'ghcr' in low:
        return 'ghcr'
    if 'forge' in low:
        return 'forge'
    return None


tags_lists = [s for s in statements if 'tags/list' in s]
need(any(side(s) == 'ghcr' for s in tags_lists) and any(side(s) == 'forge' for s in tags_lists),
     'the tags/list reads do not cover BOTH registries (ghcr- and forge-named) — N is the union max of the two lists (RD8)')
PY
  then
    return 1
  fi
  ok "r2: both registries' tags/list reads and every calendar walk precede the first docker push in build-release; no push can run at an N the other side has not walked [C02 AC5, RD8, R2 invariants 1-2]"
}

leg_r3() {
  [ -f "$WF" ] || { printf 'FAIL: r3: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: r3: {msg}', file=sys.stderr)
        sys.exit(1)


def statements_of(job):
    text = '\n'.join(str(s.get('run', '')) for s in ((jobs.get(job) or {}).get('steps') or [])
                     if isinstance(s, dict) and 'run' in s)
    out, buf = [], ''
    for ln in text.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            out.append((buf + ' ' + st).strip())
        buf = ''
    return out


def side(stmt):
    low = stmt.lower()
    if 'ghcr' in low:
        return 'ghcr'
    if 'forge' in low:
        return 'forge'
    return None


# RD8 arm order: ghcr pushes strictly before forge pushes, so any half-failed
# run leaves the GAP on the forge side — the newer line the fleet's pins have
# not adopted (ghcr stays authoritative for Renovate). Attribution rides the
# registry token in the push line or its enclosing for: list (header pin);
# an unattributable push cannot be ordered and fails the leg.
steps_rel = statements_of('build-release')
need(steps_rel, 'no build-release job with run steps (C02 owns the dual-arm release job)')

arms = []
unattributed = []
stack = []
for i, s in enumerate(steps_rel):
    if s.startswith('#'):
        continue
    m = re.match(r'^for\b[^;]*\bin\b(.*)$', s)
    if m:
        stack.append(re.sub(r';\s*do\s*$', '', m.group(1)).strip())
    elif re.match(r'^done\b', s):
        if stack:
            stack.pop()
    if 'docker push' in s:
        a = side(s) if side(s) else (side(stack[-1]) if stack else None)
        if a is None:
            unattributed.append(s)
        else:
            arms.append((i, a))

if unattributed:
    need(False,
         f'{len(unattributed)} unattributable docker push statement(s) (e.g. {unattributed[0]!r}) — name the registry token (ghcr/forge) in the push line or its enclosing for: list so the arm order is pinnable')
ghcr_i = [i for i, a in arms if a == 'ghcr']
forge_i = [i for i, a in arms if a == 'forge']
need(ghcr_i, 'no ghcr-attributed push in build-release — the release pushes the three-tag mirror to ghcr')
need(forge_i, 'no forge-attributed push in build-release — the release mirrors the same three tags to the instance registry (OQ-6)')
need(max(ghcr_i) < min(forge_i),
     'a forge push precedes a ghcr push — RD8 orders the arms ghcr-then-forge so a half-failed run gaps the registry with no pinned consumers, never ghcr')

# R2 invariant 4: a registry-arm failure must arrive loud — || true on a
# login/push/derivation line would turn a rejected push into a green lie.
# Diag-only || true holds (env | grep ACTIONS_, docker buildx version) stay
# accepted; they are not login/push/derivation lines.
loud = re.compile(r'docker login|docker push|\bcurl\b|next-n')
for jname, job in jobs.items():
    for s in statements_of(jname):
        if not s.startswith('#') and loud.search(s) and '|| true' in s:
            need(False, f'{jname}: a login/push/derivation line swallows its failure with || true: {s!r} (R2 invariant 4 — a rejected push must fail the step)')
PY
  then
    return 1
  fi
  ok "r3: every ghcr push precedes every forge push in build-release; no || true on any login/push/derivation line file-wide [C02 AC5, RD8, R2 invariant 4]"
}

leg_r4() {
  [ -f "$WF" ] || { printf 'FAIL: r4: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}
steps_txt = [str(s.get('run', '')) for s in ((jobs.get('build-pr') or {}).get('steps') or [])
             if isinstance(s, dict) and 'run' in s]


def need(cond, msg):
    if not cond:
        print(f'FAIL: r4: {msg}', file=sys.stderr)
        sys.exit(1)


# D5/RD9: the PR tag is pr-<sanitized-branch>-<short-sha> on the forge
# registry, whose grammar accepts [A-Za-z0-9_][A-Za-z0-9._-]{0,127} — 128
# chars total. The sanitized component must therefore carry a length bound
# that leaves room for the pr- prefix and the -<sha>; the bound is applied
# BEFORE the push, so an over-long branch cannot push a rejected or truncated
# surprise. Static pin: a length/slice mechanism with an integer budget
# <=128 in a run statement preceding the first docker push (the budget value
# is the implementor's; the bound's existence and position are the contract).
need(steps_txt, 'no build-pr job with run steps (C02 adds build-pr for the forge-only pr- tag, NOTE 2)')
joined = '\n'.join(steps_txt)
need('pr-' in joined, 'build-pr assembles no pr- prefixed tag (D5)')
need('curatedforest' in joined, 'build-pr assembles no curatedforest/<image> forge ref (the PR tag lands in the instance registry only)')
for m in re.finditer(r'(?i)curatedforest', joined):
    need(m.group(0) == 'curatedforest',
         f'forge owner segment {m.group(0)!r} is not lowercase — OCI repository names are lowercase-only (RD6: curatedforest/<image>)')

statements = []
for text in steps_txt:
    buf = ''
    for ln in text.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            statements.append((buf + ' ' + st).strip())
        buf = ''

push_i = [i for i, s in enumerate(statements) if 'docker push' in s]
need(push_i, 'no docker push in build-pr')
bound = None
for i, s in enumerate(statements):
    if i >= min(push_i) or s.startswith('#'):
        continue
    if re.search(r'\$\{#|:0:|\bhead -c\b|\bcut\b[^\n]*-c\b', s) and any(1 <= int(v) <= 128 for v in re.findall(r'\b(\d{1,3})\b', s)):
        bound = s
        break
need(bound,
     'no length bound guards the assembled pr- tag before the first push (forge tag grammar caps tags at 128 chars; C02 Tasks: total tag length <=127 via a bounded sanitized component — a ${#var}/slice/head -c check against a <=128 budget before docker push)')
PY
  then
    return 1
  fi
  ok "r4: build-pr's pr- tag carries a lowercase curatedforest owner segment and a length bound (<=128-shaped) applied before the first push [C02 AC5, RD9]"
}

leg_r5() {
  [ -f "$WF" ] || { printf 'FAIL: r5: %s does not exist (run 0 shipped it)\n' "$WF" >&2; return 1; }
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
doc = yaml.safe_load(raw)


def need(cond, msg):
    if not cond:
        print(f'FAIL: r5: {msg}', file=sys.stderr)
        sys.exit(1)


# OQ-8 ruling: the registry host is blessed as a DERIVATION INPUT handed to
# steps via env:, banned as a guard predicate and banned as a literal URL.
# The parsed walk makes the posture structural: every forgejo.server_url
# string in the document must sit under an env: mapping — never an if: (that
# would decide by URL again) and never interpolated into a run: body (C02
# derives it once into FORGE_SERVER_URL and the shell works off the variable).
offenders = []


def walk(node, in_env, where):
    if isinstance(node, str):
        if 'forgejo.server_url' in node and not in_env:
            offenders.append(where)
    elif isinstance(node, dict):
        for k, v in node.items():
            walk(v, in_env or str(k) == 'env', f'{where}.{k}')
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, in_env, f'{where}[{i}]')


walk(doc, False, 'doc')
need(not offenders,
     f'forgejo.server_url sits outside an env: mapping at {offenders} — the derived host enters the file ONLY as an env: value (OQ-8); never a guard predicate, never run:/if: interpolation (C02 Tasks: FORGE_SERVER_URL via step env:)')

# The derivation itself: the forge host is the scheme-stripped server_url,
# mirroring main-sync's rest="${PUSH_URL#https://}" (RD5). A scheme'd URL is
# then legal in exactly three places (header pin): inside such a strip
# fragment, on ghcr's public API endpoint, or directly in front of the derived
# per-side host variable (`https://$forge_registry/v2/...`, the name the
# per-side naming contract gives it). Both alternatives the first version
# forced are broken in practice: the strip alone yields `host/` because
# setting.AppURL is code-guaranteed to end in '/', which makes
# `"$host//curatedforest/img"` an invalid reference, and a scheme-less
# `"$host/v2/..."` makes curl default to http — a cleartext write:package PAT
# on every release run. The instance's own URL still never appears as a
# literal, with or without a scheme (NOTE 3).
frags = [m.span() for m in re.finditer(r'\$\{[A-Za-z_][A-Za-z0-9_]*#[^}]*\}', raw)]
need(frags,
     'no scheme-strip derivation (${VAR#https://}) — the forge registry host is derived from FORGE_SERVER_URL by stripping the scheme, mirroring main-sync\'s rest="${PUSH_URL#https://}" (RD5)')

preds = []


def collect(node, key, where):
    if isinstance(node, str):
        if key in ('if', 'run'):
            preds.append((where, key, node))
    elif isinstance(node, dict):
        for k, v in node.items():
            collect(v, str(k), f'{where}.{k}')
    elif isinstance(node, list):
        for i, v in enumerate(node):
            collect(v, key, f'{where}[{i}]')


collect(doc, '', 'doc')

# Shape 2: no URL decides anything, so a scheme'd URL may not sit in an if:.
bad_if = [w for w, k, v in preds if k == 'if' and 'https://' in v]
need(not bad_if,
     f'an https:// inside an if: predicate at {bad_if} — instance detection by URL is retired; guards read vars.ROLE and the event only (OQ-8, NOTE 3)')


def is_guard(ln):
    return bool(re.match(r'\s*(if|elif|while|case)\b', ln)) or '[[' in ln or bool(re.search(r'\[\s+\S', ln))


# Shape 3: branching on the strip fragment re-opens decide-by-host through the
# shell (`if [ -z "${FORGE_SERVER_URL#https://}" ]`), which the if: ban exists
# to prevent.
bad_strip = []
for w, k, v in preds:
    if '#https://' not in v:
        continue
    if k == 'if':
        bad_strip.append((w, v.strip()))
        continue
    bad_strip += [(w, ln.strip()) for ln in v.splitlines() if '#https://' in ln and is_guard(ln)]
need(not bad_strip,
     f'a scheme-strip fragment is used as a guard predicate: {bad_strip[:2]} — the derived host feeds the registry reads only; branching on it is URL-based instance detection by another route (OQ-8, NOTE 3)')

# Shape 1: hard-coded hosts. g1 sweeps the same literals repo-wide; r5 names
# them here because this leg is the one a C02 author runs first.
hard = [h for h in ('git.spencerslab.com', 'git.scifi.farm', 'github.com') if h in raw]
need(not hard,
     f'a hard-coded instance/repo host {hard} — the forge host is derived from env FORGE_SERVER_URL and never written out, with or without a scheme (NOTE 3)')

derived = re.compile(r'https://\$\{?[A-Za-z0-9_]*forge[A-Za-z0-9_]*', re.IGNORECASE)


def merge(text):
    out, buf = [], ''
    for ln in text.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            out.append((buf + ' ' + st).strip())
        buf = ''
    return out


# Shape 4: a registry-API URL built on the derived host without a scheme is
# fetched over http (curl's default), and these reads carry the push token —
# so `<forge host var>/v2/...` must be scheme'd wherever a curl/wget reads it.
# Docker's own uses of the same bare host stay scheme-less on purpose (a login
# takes a registry HOSTNAME and an image ref takes a repository path; a scheme
# in either is an invalid reference), which is why only the `/v2/` API path is
# pinned here.
apire = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)((?:%[/A-Za-z])?)\}?/v2/')
cleartext = []
for w, k, v in preds:
    if k != 'run' or not re.search(r'\b(curl|wget)\b', v):
        continue
    for st in merge(v):
        for hm in apire.finditer(st):
            if 'forge' not in hm.group(1).lower():
                continue
            if st[:hm.start()].rstrip().lower().endswith('https://'):
                continue
            cleartext.append((w, st[:110]))
need(not cleartext,
     f'a scheme-less forge registry-API URL {cleartext[:2]} — curl defaults to http, so these reads ship FORGE_PUSH_TOKEN in cleartext; write https://$forge_registry/v2/... (host trailing-slash trimmed). Only the API URL is pinned: docker login "$forge_registry" and the image ref "$forge_registry/curatedforest/<img>" must stay scheme-less (a scheme there is an invalid reference)')

for m in re.finditer(r'https://', raw):
    if any(a <= m.start() < b for a, b in frags):
        continue
    if raw[m.end():m.end() + 7] == 'ghcr.io' or derived.match(raw, m.start()):
        continue
    need(False,
         f'an https:// URL literal ({raw[max(0, m.start() - 40):m.end() + 40]!r}...) — legal schemes are the strip fragment, the public ghcr.io endpoint, and https://$forge_registry (the derived host, trailing slash trimmed, read over TLS); a scheme-less "$host/v2/..." is not the answer: curl defaults to http (NOTE 3: NO direct URL references anywhere)')
PY
  then
    return 1
  fi
  ok "r5: forgejo.server_url only ever in an env: mapping; no if: scheme, no strip-as-guard, no instance host literal (scheme'd or bare); the derived host is slash-trimmed and its /v2/ reads are scheme'd (docker login and image refs stay bare) [C02 AC3, OQ-8, RD5]"
}


# --- C01 detector unit legs (d1-d15) on scratch git fixtures -----------------

helper_ready() {
  [ -f "$HELP" ] || { printf 'FAIL: %s: %s does not exist (C01 creates it)\n' "$1" "$HELP" >&2; return 1; }
}

# Fixture repo 1: commit A creates three container dirs + README, commit B
# changes README only (the d4 negative range A..B), commit C changes two
# container dirs and is the fixture tip — so the all-zero-before fallback
# (HEAD^..HEAD on the checked-out history, the pushed SHA being HEAD) sees
# exactly the d1 range B..C.
build_fix1() {
  [ -n "${FIX1:-}" ] && return 0
  FIX1="$TMP/fix1"
  local c="$FIX1/containers"
  mkdir -p "$c/alpha" "$c/beta" "$c/traefik-mqtt-allowlist" || return 1
  printf 'FROM scratch\n' | tee "$c/alpha/Dockerfile" "$c/beta/Dockerfile" "$c/traefik-mqtt-allowlist/Dockerfile" >/dev/null || return 1
  echo readme > "$FIX1/README.md"
  git -C "$FIX1" init -q . && git -C "$FIX1" config user.email test@example.invalid && git -C "$FIX1" config user.name test || return 1
  git -C "$FIX1" add -A && git -C "$FIX1" commit -qm a || return 1
  SHA_A=$(git -C "$FIX1" rev-parse HEAD)
  echo more >> "$FIX1/README.md" || return 1
  git -C "$FIX1" add -A && git -C "$FIX1" commit -qm b || return 1
  SHA_B=$(git -C "$FIX1" rev-parse HEAD)
  echo change > "$c/alpha/Dockerfile" && echo change > "$c/traefik-mqtt-allowlist/Dockerfile" || return 1
  git -C "$FIX1" add -A && git -C "$FIX1" commit -qm c || return 1
  SHA_C=$(git -C "$FIX1" rev-parse HEAD)
}

# Fixture repo 2 (d5): one DNS-unsafe name, one safe name without a
# Dockerfile, and one hyphen-compound valid dir — all three changed at
# commit B. Flipping either gate (or dropping the Dockerfile check) lets a
# rejected name into the output and reddens this leg.
build_fix2() {
  [ -n "${FIX2:-}" ] && return 0
  FIX2="$TMP/fix2"
  local c="$FIX2/containers"
  mkdir -p "$c/Not_a_Name" "$c/no-dockerfile" "$c/traefik-mqtt-allowlist" || return 1
  printf 'FROM scratch\n' | tee "$c/Not_a_Name/Dockerfile" "$c/traefik-mqtt-allowlist/Dockerfile" >/dev/null || return 1
  echo readme > "$c/no-dockerfile/README.md"
  git -C "$FIX2" init -q . && git -C "$FIX2" config user.email test@example.invalid && git -C "$FIX2" config user.name test || return 1
  git -C "$FIX2" add -A && git -C "$FIX2" commit -qm a || return 1
  SHA2_A=$(git -C "$FIX2" rev-parse HEAD)
  echo change > "$c/Not_a_Name/Dockerfile" && echo change > "$c/no-dockerfile/README.md" && echo change > "$c/traefik-mqtt-allowlist/Dockerfile" || return 1
  git -C "$FIX2" add -A && git -C "$FIX2" commit -qm b || return 1
  SHA2_B=$(git -C "$FIX2" rev-parse HEAD)
}

# detect_in <dir> <expect-json> <VAR=val...> — runs `detect` at the fixture
# root (the C01 contract: cwd is the checked-out repo) and byte-compares the
# whitespace-stripped JSON array, so sortedness and quoting are pinned while
# cosmetic spacing is not.
detect_in() {
  local dir="$1" expect="$2"
  shift 2
  local out
  if ! out=$( cd "$dir" && env "$@" bash "$HELP_ABS" detect ); then
    printf 'FAIL: detector `detect` exited non-zero in %s for env: %s\n' "$dir" "$*" >&2
    return 1
  fi
  out="${out//[[:space:]]/}"
  [ "$out" = "$expect" ] || { printf 'FAIL: detector emitted %s, expected %s (env: %s)\n' "$out" "$expect" "$*" >&2; return 1; }
}

leg_d1() {
  helper_ready d1 || return 1
  build_fix1 || { printf 'FAIL: d1: harness could not build the fixture repo\n' >&2; return 1; }
  detect_in "$FIX1" '["alpha","traefik-mqtt-allowlist"]' \
    EVENT_NAME=push "EVENT_BEFORE=$SHA_B" "SHA=$SHA_C" || return 1
  ok "d1: push range EVENT_BEFORE..SHA detects exactly the changed container dirs [C01 AC6]"
}

leg_d2() {
  helper_ready d2 || return 1
  build_fix1 || { printf 'FAIL: d2: harness could not build the fixture repo\n' >&2; return 1; }
  # First push to a branch carries an all-zero `before`; the fallback is HEAD^..HEAD
  # and the fixture tip is the pushed commit (SHA_C), mirroring a real checkout.
  detect_in "$FIX1" '["alpha","traefik-mqtt-allowlist"]' \
    EVENT_NAME=push "EVENT_BEFORE=$(printf '0%.0s' {1..40})" "SHA=$SHA_C" || return 1
  ok "d2: all-zero EVENT_BEFORE falls back to HEAD^..HEAD [C01 AC6]"
}

leg_d3() {
  helper_ready d3 || return 1
  build_fix1 || { printf 'FAIL: d3: harness could not build the fixture repo\n' >&2; return 1; }
  detect_in "$FIX1" '["alpha","traefik-mqtt-allowlist"]' \
    EVENT_NAME=pull_request "BASE_SHA=$SHA_B" "HEAD_SHA=$SHA_C" || return 1
  ok "d3: pull_request detects over BASE_SHA..HEAD_SHA [C01 AC6]"
}

leg_d4() {
  helper_ready d4 || return 1
  build_fix1 || { printf 'FAIL: d4: harness could not build the fixture repo\n' >&2; return 1; }
  detect_in "$FIX1" '[]' \
    EVENT_NAME=push "EVENT_BEFORE=$SHA_A" "SHA=$SHA_B" || return 1
  ok "d4: a changed non-container path yields [] [C01 AC6]"
}

leg_d5() {
  helper_ready d5 || return 1
  build_fix2 || { printf 'FAIL: d5: harness could not build the gate fixture repo\n' >&2; return 1; }
  detect_in "$FIX2" '["traefik-mqtt-allowlist"]' \
    EVENT_NAME=push "EVENT_BEFORE=$SHA2_A" "SHA=$SHA2_B" || return 1
  ok "d5: DNS-safe-name and Dockerfile gates exclude Not_a_Name/ and no-dockerfile/; hyphen-compound accepted [C01 AC6]"
}

leg_d6() {
  helper_ready d6 || return 1
  build_fix1 || { printf 'FAIL: d6: harness could not build the fixture repo\n' >&2; return 1; }
  detect_in "$FIX1" '["alpha","beta","traefik-mqtt-allowlist"]' \
    EVENT_NAME=workflow_dispatch 'MANUAL_CONTAINERS=beta, alpha  traefik-mqtt-allowlist' || return 1
  detect_in "$FIX1" '["alpha"]' \
    EVENT_NAME=workflow_dispatch 'MANUAL_CONTAINERS=alpha ghost' || return 1
  detect_in "$FIX1" '[]' \
    EVENT_NAME=workflow_dispatch 'MANUAL_CONTAINERS=' || return 1
  ok "d6: manual list normalizes+sorts, the Dockerfile gate still applies, empty input => [] [C01 AC6]"
}

leg_d7() {
  helper_ready d7 || return 1
  local got
  # Numeric compare: 26.11.10 is the month max (not 26.11.9); v162/latest/
  # foreign-month lines are ignored; next N is max+1.
  if ! got=$( printf '%s' '{"name":"ownyourio/wekan-mcp","tags":["26.11.2","26.11.9","26.11.10","v162","latest","25.12.7"]}' \
    | env YYMM=26.11 bash "$HELP_ABS" next-n ); then
    printf 'FAIL: d7: `next-n` exited non-zero on a month-populated tags/list fixture\n' >&2
    return 1
  fi
  got="${got//[[:space:]]/}"
  [ "$got" = '11' ] || { printf 'FAIL: d7: next-n emitted %s, expected 11 (max 26.11.10 + 1)\n' "$got" >&2; return 1; }
  if ! got=$( printf '%s' '{"name":"ownyourio/strata","tags":["v84","latest","main"]}' \
    | env YYMM=26.11 bash "$HELP_ABS" next-n ); then
    printf 'FAIL: d7: `next-n` exited non-zero on a no-calendar-tag fixture\n' >&2
    return 1
  fi
  got="${got//[[:space:]]/}"
  [ "$got" = '1' ] || { printf 'FAIL: d7: next-n emitted %s on v/rolling-only tags, expected 1 (first release of the month)\n' "$got" >&2; return 1; }
  ok "d7: next-n = max(yy.mm.*)+1 with numeric compare; v/rolling/foreign months ignored; 1 when none [C01 AC6]"
}

leg_d8() {
  helper_ready d8 || return 1
  local out
  san() { bash "$HELP_ABS" sanitize "$1"; }
  # `_` is inside the D5 charclass [a-z0-9._-], so it survives sanitizing.
  out=$(san 'CF-6/My_Branch') || { printf 'FAIL: d8: sanitize exited non-zero\n' >&2; return 1; }
  [ "$out" = 'cf-6-my_branch' ] || { printf 'FAIL: d8: sanitize(CF-6/My_Branch) = %s, expected cf-6-my_branch\n' "$out" >&2; return 1; }
  out=$(san 'feature/two//slashes') || { printf 'FAIL: d8: sanitize exited non-zero\n' >&2; return 1; }
  [ "$out" = 'feature-two-slashes' ] || { printf 'FAIL: d8: sanitize(feature/two//slashes) = %s, expected feature-two-slashes (slash->dash then collapse repeats)\n' "$out" >&2; return 1; }
  out=$(san 'bad!char@here') || { printf 'FAIL: d8: sanitize exited non-zero\n' >&2; return 1; }
  [ "$out" = 'bad-char-here' ] || { printf 'FAIL: d8: sanitize(bad!char@here) = %s, expected bad-char-here\n' "$out" >&2; return 1; }
  local long
  long="feature/$(printf 'x%.0s' {1..200})"
  out=$(san "$long") || { printf 'FAIL: d8: sanitize exited non-zero\n' >&2; return 1; }
  [ "${#out}" -le 128 ] && [ -n "$out" ] \
    || { printf 'FAIL: d8: sanitize of a 200-char branch returned %d chars, expected non-empty and <=128\n' "${#out}" >&2; return 1; }
  ok "d8: sanitize lowercases, /->dash, class-strip, dash-collapse, <=128 cap [C01 AC6]"
}

# Fixture 3 (d9-d13): the range-WIDTH fixture run -1's suite lacked — every
# older d-leg fixture is one commit wide, so narrowing the push range to the
# tip survived the whole suite (EXPLORE section 6, mutation column). Three
# commits: A creates alpha+beta, B changes beta (the MIDDLE commit), C changes
# alpha (the tip). A tip-narrowed range answers ["alpha"] where the event
# range answers ["alpha","beta"] — the owner's fear shape, red offline.
build_fix3() {
  [ -n "${FIX3:-}" ] && return 0
  FIX3="$TMP/fix3"
  local c="$FIX3/containers"
  mkdir -p "$c/alpha" "$c/beta" || return 1
  printf 'FROM scratch\n' | tee "$c/alpha/Dockerfile" "$c/beta/Dockerfile" >/dev/null || return 1
  echo readme > "$FIX3/README.md"
  git -C "$FIX3" init -q . && git -C "$FIX3" config user.email test@example.invalid && git -C "$FIX3" config user.name test || return 1
  git -C "$FIX3" add -A && git -C "$FIX3" commit -qm a || return 1
  SHA3_A=$(git -C "$FIX3" rev-parse HEAD) || return 1
  echo change > "$c/beta/Dockerfile" || return 1
  git -C "$FIX3" add -A && git -C "$FIX3" commit -qm b || return 1
  SHA3_B=$(git -C "$FIX3" rev-parse HEAD) || return 1
  echo change2 > "$c/alpha/Dockerfile" || return 1
  git -C "$FIX3" add -A && git -C "$FIX3" commit -qm c || return 1
  SHA3_C=$(git -C "$FIX3" rev-parse HEAD) || return 1
}

# d10's racing push: fix3 copied (identical object hashes) and a README-only
# commit E appended, so the checkout's HEAD has moved past the event SHA —
# the diff must still ride the event's endpoints, never the worktree's.
build_fix3e() {
  build_fix3 || return 1
  [ -n "${FIX3E:-}" ] && return 0
  FIX3E="$TMP/fix3e"
  cp -a "$FIX3" "$FIX3E" || return 1
  echo tip > "$FIX3E/README.md" || return 1
  git -C "$FIX3E" add -A && git -C "$FIX3E" commit -qm e || return 1
  SHA3E_E=$(git -C "$FIX3E" rev-parse HEAD) || return 1
}

# Fixture 4 (d14/d15): the PR shape. A creates alpha+beta; head H branches at
# A and modifies beta; the base then MOVES — M modifies alpha on the original
# branch. The worktree ends detached at H: a PR checkout lands on the head,
# and the Dockerfile gate reads the worktree, so both dirs stay buildable at
# head (a container existing only on base would be dropped by that gate and
# could never appear in any output — such an expectation pins nothing). O is
# an unrelated root commit for the rewritten-history shape.
build_fix4() {
  [ -n "${FIX4:-}" ] && return 0
  FIX4="$TMP/fix4"
  local c="$FIX4/containers" bb
  mkdir -p "$c/alpha" "$c/beta" || return 1
  printf 'FROM scratch\n' | tee "$c/alpha/Dockerfile" "$c/beta/Dockerfile" >/dev/null || return 1
  echo readme > "$FIX4/README.md"
  git -C "$FIX4" init -q . && git -C "$FIX4" config user.email test@example.invalid && git -C "$FIX4" config user.name test || return 1
  git -C "$FIX4" add -A && git -C "$FIX4" commit -qm a || return 1
  SHA4_A=$(git -C "$FIX4" rev-parse HEAD) || return 1
  bb=$(git -C "$FIX4" symbolic-ref --short HEAD) || return 1
  git -C "$FIX4" switch -qc head "$SHA4_A" || return 1
  echo head-change > "$c/beta/Dockerfile" || return 1
  git -C "$FIX4" add -A && git -C "$FIX4" commit -qm h || return 1
  SHA4_H=$(git -C "$FIX4" rev-parse HEAD) || return 1
  git -C "$FIX4" switch -q "$bb" || return 1
  echo base-move > "$c/alpha/Dockerfile" || return 1
  git -C "$FIX4" add -A && git -C "$FIX4" commit -qm m || return 1
  SHA4_M=$(git -C "$FIX4" rev-parse HEAD) || return 1
  git -C "$FIX4" checkout -q --orphan unrelated || return 1
  echo unrelated > "$FIX4/UNRELATED.md" || return 1
  git -C "$FIX4" add -A && git -C "$FIX4" commit -qm o || return 1
  SHA4_O=$(git -C "$FIX4" rev-parse HEAD) || return 1
  git -C "$FIX4" switch -q --detach "$SHA4_H" || return 1
}

# detect_capture <dir> <VAR=val...> — runs `detect` like detect_in but keeps
# stdout, stderr AND the exit code, because the loud postures (fallback
# annotation, A5 die, 128 propagation, RP19 endpoint-before-call) all live on
# channels stdout-only legs cannot see. Never fails the caller: the leg
# reads CAP_RC and friends and states its own FAIL.
detect_capture() {
  local dir="$1"
  shift
  if CAP_OUT=$( cd "$dir" && env "$@" bash "$HELP_ABS" detect 2>"$TMP/cap.err" ); then
    CAP_RC=0
  else
    CAP_RC=$?
  fi
  CAP_ERR=$(cat "$TMP/cap.err")
}

leg_d9() {
  helper_ready d9 || return 1
  build_fix3 || { printf 'FAIL: d9: harness could not build the wide-range fixture\n' >&2; return 1; }
  detect_in "$FIX3" '["alpha","beta"]' \
    EVENT_NAME=push "EVENT_BEFORE=$SHA3_A" "SHA=$SHA3_C" || return 1
  ok "d9: a three-commit push detects the container changed in the MIDDLE commit, not only the tip one [run -2 C01, invariant 2 — the owner's fear shape]"
}

leg_d10() {
  helper_ready d10 || return 1
  build_fix3e || { printf 'FAIL: d10: harness could not build the racing-push fixture\n' >&2; return 1; }
  # HEAD is commit E (README-only) while the event SHA is C: the range is the
  # event's endpoints. A worktree-anchored narrowing answers [] here.
  detect_in "$FIX3E" '["alpha","beta"]' \
    EVENT_NAME=push "EVENT_BEFORE=$SHA3_A" "SHA=$SHA3_C" || return 1
  ok "d10: with the checkout past the event SHA, detection still answers before..sha — endpoint identity, never worktree anchoring [run -2 C01, invariant 3]"
}

leg_d11() {
  helper_ready d11 || return 1
  build_fix3 || { printf 'FAIL: d11: harness could not build the wide-range fixture\n' >&2; return 1; }
  detect_capture "$FIX3" EVENT_NAME=push "EVENT_BEFORE=$(printf '0%.0s' {1..40})" "SHA=$SHA3_C"
  [ "$CAP_RC" -eq 0 ] || { printf 'FAIL: d11: the first-push fallback exited %d, expected 0 (the all-zero before is the designed fallback, not a failure)\n' "$CAP_RC" >&2; return 1; }
  local stripped; stripped="${CAP_OUT//[[:space:]]/}"
  [ "$stripped" = '["alpha"]' ] \
    || { printf 'FAIL: d11: all-zero before answered %s, expected the tip-only posture ["alpha"] (HEAD^..HEAD on the fixture) — A1 posture byte-exact, any silent shape change is a re-pin away\n' "$stripped" >&2; return 1; }
  local nlines; nlines=$(printf '%s\n' "$CAP_OUT" | grep -c . || true)
  [ "$nlines" -eq 1 ] \
    || { printf 'FAIL: d11: stdout carried %d non-empty line(s), expected exactly the one JSON array — stdout is the captured carrier (channel law)\n' "$nlines" >&2; return 1; }
  case "$CAP_ERR" in
    *'::warning::'*) ;;
    *) printf 'FAIL: d11: stderr carries no ::warning:: annotation — the fallback must announce itself, never narrow silently (A4)\n' >&2; return 1 ;;
  esac
  case "$CAP_ERR" in
    *'tip-only'*) ;;
    *) printf 'FAIL: d11: the fallback annotation does not name the narrowing with the stable marker "tip-only" (A4)\n' >&2; return 1 ;;
  esac
  ok "d11: all-zero before keeps the tip-only fallback, announces the narrowing on stderr, and leaves stdout exactly one JSON line [run -2 C01, invariants 4+6]"
}

leg_d12() {
  helper_ready d12 || return 1
  build_fix3 || { printf 'FAIL: d12: harness could not build the wide-range fixture\n' >&2; return 1; }
  detect_capture "$FIX3" EVENT_NAME=push "EVENT_BEFORE=" "SHA=$SHA3_C"
  [ "$CAP_RC" -ne 0 ] \
    || { printf 'FAIL: d12: an EMPTY before fell through to the tip-only fallback (exit 0, stdout %s) — empty is not first-push: at v15.0.10 no git-push or mirror producer sends one, so its arrival means a wrong accessor or an unexpected event and must exit non-zero (A5; the exact code is dev choice, OQ-m)\n' "${CAP_OUT//[[:space:]]/}" >&2; return 1; }
  local stripped; stripped="${CAP_OUT//[[:space:]]/}"
  [ -z "$stripped" ] \
    || { printf 'FAIL: d12: the empty-before red path emitted %s on stdout — a dead detection must produce no set\n' "$stripped" >&2; return 1; }
  printf '%s' "$CAP_ERR" | grep -qi 'before' \
    || { printf 'FAIL: d12: the empty-before failure names nothing — the message must name "before" so the anomaly is self-describing\n' >&2; return 1; }
  ok "d12: an empty before exits non-zero with a message naming it and no JSON on stdout — the masking fallthrough is structurally red now [run -2 C01, invariant 4 (A5)]"
}

leg_d13() {
  helper_ready d13 || return 1
  build_fix3 || { printf 'FAIL: d13: harness could not build the wide-range fixture\n' >&2; return 1; }
  local garbage; garbage=$(printf 'f%.0s' {1..40})
  detect_capture "$FIX3" EVENT_NAME=push "EVENT_BEFORE=$garbage" "SHA=$SHA3_C"
  [ "$CAP_RC" -eq 128 ] \
    || { printf 'FAIL: d13: an unreachable before exited %d, expected git 128 to propagate — a soft-pedal here (exit 0 with an empty set, or any masking wrapper) is the silent green the owner fears\n' "$CAP_RC" >&2; return 1; }
  local stripped; stripped="${CAP_OUT//[[:space:]]/}"
  [ -z "$stripped" ] \
    || { printf 'FAIL: d13: an unreachable before emitted %s — a failed range must emit nothing, not a set\n' "$stripped" >&2; return 1; }
  ok "d13: an unreachable/garbage before propagates git's exit 128 with no JSON on stdout — the loud range failure stays loud [run -2 C01, invariant 5]"
}

leg_d14() {
  helper_ready d14 || return 1
  build_fix4 || { printf 'FAIL: d14: harness could not build the PR fixture\n' >&2; return 1; }
  # B5 by ruling (OQ-b): the left endpoint is the MERGE BASE, not the raw
  # base tip — a base that moved after the head branched must not answer its
  # own alpha change. Adjacency parity: a base that IS an ancestor resolves
  # to itself, so the d3-style adjacent cases do not move.
  detect_in "$FIX4" '["beta"]' \
    EVENT_NAME=pull_request "BASE_SHA=$SHA4_M" "HEAD_SHA=$SHA4_H" || return 1
  detect_in "$FIX4" '["beta"]' \
    EVENT_NAME=pull_request "BASE_SHA=$SHA4_A" "HEAD_SHA=$SHA4_H" || return 1
  ok "d14: the PR arm diffs merge-base..head — a moved base contributes no base-side changes, an adjacent base keeps the two-dot answer [run -2 C01, invariant 8 (B5)]"
}

leg_d15() {
  helper_ready d15 || return 1
  build_fix4 || { printf 'FAIL: d15: harness could not build the PR fixture\n' >&2; return 1; }
  detect_capture "$FIX4" EVENT_NAME=pull_request "BASE_SHA=" "HEAD_SHA=$SHA4_H"
  [ "$CAP_RC" -eq 128 ] \
    || { printf 'FAIL: d15: an empty BASE_SHA exited %d, expected 128 — the PR arm has no silent fallback (EXPLORE section 3)\n' "$CAP_RC" >&2; return 1; }
  [ -z "${CAP_OUT//[[:space:]]/}" ] || { printf 'FAIL: d15: the empty-BASE_SHA red path emitted JSON\n' >&2; return 1; }
  detect_capture "$FIX4" EVENT_NAME=pull_request "BASE_SHA=$SHA4_M" "HEAD_SHA="
  [ "$CAP_RC" -eq 128 ] \
    || { printf 'FAIL: d15: an empty HEAD_SHA exited %d, expected 128\n' "$CAP_RC" >&2; return 1; }
  [ -z "${CAP_OUT//[[:space:]]/}" ] || { printf 'FAIL: d15: the empty-HEAD_SHA red path emitted JSON\n' >&2; return 1; }
  detect_capture "$FIX4" EVENT_NAME=pull_request "BASE_SHA=$SHA4_O" "HEAD_SHA=$SHA4_H"
  [ "$CAP_RC" -ne 0 ] \
    || { printf 'FAIL: d15: an unrelated base/head pair answered %s with exit 0 — the two-dot quietude is exactly what the merge-base ruling replaced: git merge-base answers 1 (RP19; red-by-design against the shipped arm)\n' "${CAP_OUT//[[:space:]]/}" >&2; return 1; }
  [ -z "${CAP_OUT//[[:space:]]/}" ] \
    || { printf 'FAIL: d15: the unrelated pair emitted %s despite the failed merge-base — no JSON on a red arm\n' "${CAP_OUT//[[:space:]]/}" >&2; return 1; }
  # RP19: git merge-base exits 1 writing NOTHING to stderr, so the endpoint
  # line must precede the call — otherwise the red run names nothing and is
  # undiagnosable without a payload dump.
  printf '%s' "$CAP_ERR" | grep -qF -- "$SHA4_O" \
    || { printf 'FAIL: d15: the unrelated-history red run does not name the base endpoint (%s) on stderr before failing — the endpoint line must precede the merge-base call\n' "$SHA4_O" >&2; return 1; }
  printf '%s' "$CAP_ERR" | grep -qF -- "$SHA4_H" \
    || { printf 'FAIL: d15: the unrelated-history red run does not name the head endpoint (%s) on stderr (RP19)\n' "$SHA4_H" >&2; return 1; }
  ok "d15: PR degenerate shapes fail loud — empty endpoints exit 128 with no JSON, an unrelated pair exits non-zero (measured 1) with stderr naming both endpoints before the call [run -2 C01, invariant 8, RP19]"
}

# --- C02 cutover legs (x1-x5) --------------------------------------------------

leg_x1() {
  [ -f "$GHB" ] || { printf 'FAIL: x1: %s does not exist — C02 must KEEP it, narrowed to workflow_dispatch-only (owner round supersedes the D1 delete)\n' "$GHB" >&2; return 1; }
  if ! python3 - "$GHB" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: x1: {msg}', file=sys.stderr)
        sys.exit(1)


# (a) The parse itself is a mutation check: the half-commented restore —
# a commented parent with LIVE children — raises ParserError (EXPLORE §7.2
# replayed both shapes), so pinning the parse pins the fully-commented shape.
try:
    doc = yaml.safe_load(raw)
except yaml.YAMLError as exc:
    need(False,
         f'{path} does not parse: {exc} — the half-commented trigger block is exactly this break: comment EVERY line of the restored block, parent and children')
trig = doc.get(True) or doc.get('on')
need(isinstance(trig, dict), 'no top-level on: mapping')

# (b) The parsed key-set is the authoritative inertness assertion: NOTE 1 (C03)
# restores the original push:/pull_request: blocks INSIDE on: as comments —
# present for the re-enable-by-uncomment, absent for the engine. A live
# trigger would race the forge calendar line (RESEARCH A hazard).
need(set(trig) == {'workflow_dispatch'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly [workflow_dispatch] — a live (uncommented) push/pull_request trigger mints tags automatically and outranks the calendar line (C02 posture + NOTE 1 keeps them commented)')

# (c) HOLD across the run: the manual rebuild escape hatch stays exactly.
wd = trig.get('workflow_dispatch')
need(isinstance(wd, dict) and 'containers' in ((wd or {}).get('inputs') or {}),
     'the containers dispatch input is gone — C02 preserves the manual rebuild escape hatch exactly')

in_on = False
region = []
for i, line in enumerate(raw.splitlines(), 1):
    if not in_on:
        if re.match(r'^(on|True|["\x27]on["\x27])\s*:', line):
            in_on = True
        continue
    if re.match(r'^[^#\s]', line):
        break
    region.append((i, line))

# (d) No live trigger key inside the on: region. Scoped to the region so the
# docker/build-push-action push: INPUT key deep in the job body stays the
# blessed false positive (header pin).
for i, line in region:
    m = re.match(r'^\s*(push|pull_request)\s*:', line)
    if m:
        need(False,
             f'line {i} keeps a live {m.group(1)}: key inside the on: block (mutation teeth: re-adding a trigger reddens here and in the parsed check; scoped so the build-push-action push: input key in the job body does not false-red)')


def commented_block(key):
    """Commented child lines under the first commented `<key>:` parent in the
    on: region, up to the next (commented or live) sibling key; None when no
    such parent exists. Pins the WHOLE block, parent plus commented
    branches:/paths: children — a `# push:` phrase in an unrelated comment
    cannot satisfy it, and neither can a lone commented parent (the
    half-commented shape breaks the parse in (a))."""
    for idx, (_i, ln) in enumerate(region):
        if re.match(r'^[ \t]*#[ \t]*' + key + r'[ \t]*:', ln):
            kids = []
            for _j, kid in region[idx + 1:]:
                if re.match(r'^[ \t]*#[ \t]*(push|pull_request|workflow_dispatch)[ \t]*:', kid):
                    break
                if re.match(r'^[ \t]*[^# \t]', kid):
                    break
                kids.append(kid)
            return kids
    return None


# (e) NOTE 1's re-enable affordance, positively pinned.
for key in ('push', 'pull_request'):
    kids = commented_block(key)
    need(kids is not None,
         f'no commented-out `{key}:` parent inside the on: block — NOTE 1 keeps the original triggers in the file, commented, so re-enabling is an uncomment and not a re-author (C03 restores them verbatim from main)')
    need(any(re.match(r'^[ \t]*#[ \t]*branches[ \t]*:', k) for k in kids)
         and any(re.match(r'^[ \t]*#[ \t]*paths[ \t]*:', k) for k in kids),
         f'the commented `{key}:` block carries no commented branches:/paths: children beneath the parent — the restore must comment every line of the original block (a commented parent with live children also breaks the parse in (a))')

# (f) RD1 annotation: uncommenting is an explicit owner decision, and the
# comment must say why (v<run> + <branch> tags would race the calendar line).
need(any(re.search(r'\bcalendar\b', ln, re.I) for _i, ln in region if ln.lstrip().startswith('#')),
     'no annotation comment naming the calendar race above the commented triggers (RD1: re-enabling makes GitHub mint v<run> + <branch> tags again, outranking the calendar line and the Renovate pins — the annotation must name it)')
PY
  then
    return 1
  fi
  ok "x1: on: parses to workflow_dispatch-only (inert) with the containers input preserved, and the on: block carries commented-out push:/pull_request: blocks WITH commented children plus the calendar-race annotation — L139 stays a blessed false positive [C03 AC1-AC4, NOTE 1]"
}

leg_x2() {
  python3 - <<'PY' || return 1
import json, sys
from fnmatch import fnmatchcase

try:
    cfg = json.load(open('renovate.json'))
except json.JSONDecodeError as exc:
    print(f'FAIL: x2: renovate.json does not parse as JSON: {exc}', file=sys.stderr)
    sys.exit(1)

rules = cfg.get('packageRules') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: x2: {msg}', file=sys.stderr)
        sys.exit(1)


def owns_ownyourio(pattern):
    # fnmatchcase(name, pattern): the rule entry is the glob, the image is the name.
    return (fnmatchcase('ghcr.io/ownyourio/wekan-mcp', pattern)
            and not fnmatchcase('ghcr.io/mostlygeek/llama-swap', pattern))


# Exactly one calendar rule (RESEARCH A: rule lands before-or-with any pin
# bump or the pin loop stalls / offers downgrades). The llama-swap
# regex-versioning precedent stays unique to its own image.
cands = [r for r in rules
         if isinstance(r.get('versioning'), str) and r['versioning'].startswith('regex:')
         and any(owns_ownyourio(str(p)) for p in (r.get('matchPackageNames') or []))]
need(len(cands) == 1,
     f'{len(cands)} packageRules carry a regex: versioning with a matchPackageNames glob covering ghcr.io/ownyourio/* — expected exactly 1; C02 adds it (DECISIONS D3)')
rule = cands[0]
need(rule.get('matchDatasources') == ['docker'],
     f'the calendar rule matchDatasources is {rule.get("matchDatasources")!r}, expected ["docker"]')
# D3 verbatim; mutation teeth: \d -> \w reddens here.
need(rule['versioning'] == 'regex:^(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)$',
     f"the calendar rule versioning is {rule['versioning']!r}, expected the D3 form verbatim")
pats = [str(p) for p in rule['matchPackageNames']]
need(any(fnmatchcase('ghcr.io/ownyourio/wekan-mcp', p) for p in pats),
     'the calendar rule glob does not match ghcr.io/ownyourio/wekan-mcp')
need(not any(fnmatchcase('ghcr.io/mostlygeek/llama-swap', p) for p in pats),
     'the calendar rule glob also matches ghcr.io/mostlygeek/llama-swap — foreign images stay on their existing rules')
need(not any(fnmatchcase('ghcr.io/containers/kubernetes-mcp-server', p) for p in pats),
     'the calendar rule glob also matches ghcr.io/containers/kubernetes-mcp-server — foreign images stay on their existing rules')
# Shape-only leg: the behavioral pair (dev-renovate validate_config +
# test_package_rules, which names the deciding matcher for * vs **) is the
# dev/review MCP duty pinned in the plan Commands, not this offline suite.
PY
  ok "x2: exactly one ownyourio calendar rule, docker datasource, D3 versioning verbatim, globs foreign-image-clean [C02 AC2]"
}

leg_x3() {
  python3 - <<'PY' || return 1
import sys

files = ('skills/container-creation/SKILL.md', '.rulesync/rules/overview.md', 'AGENTS.md')
errs = []
for f in files:
    try:
        lines = open(f).read().splitlines()
    except OSError as exc:
        errs.append(f'cannot read {f}: {exc}')
        continue
    if not any('containers-build' in ln for ln in lines):
        errs.append(f'{f} names containers-build nowhere — C02 re-pins the container-CI docs to the forge workflow')
    for i, ln in enumerate(lines, 1):
        if 'docker-build.yaml' in ln and 'workflow_dispatch' not in ln:
            errs.append(f'{f}:{i} names docker-build.yaml without workflow_dispatch — the only allowed co-mention is the workflow_dispatch-only manual fallback (C02 x3 gate)')
if errs:
    for e in errs:
        print(f'FAIL: x3: {e}', file=sys.stderr)
    sys.exit(1)
PY
  ok "x3: SKILL.md, overview.md and regenerated AGENTS.md name containers-build; every docker-build.yaml line co-names workflow_dispatch [C02 AC3]"
}

leg_x4() {
  # release.yaml left this fence on 2026-11-21 (cf-6 absorption of cf-55's
  # 1ada03a50, which deleted the GitHub release twin when the chart
  # releases moved to .forgejo/workflows/release.yaml). The fence guards the
  # .github sibling fleet at cutover, not release continuity across fleets —
  # the moved file and its deleted twin are pinned by forgejo-ci-surface.sh
  # t1/t2 and the agent-board-coord twin-path bans.
  local missing=() f
  for f in aislop.yaml gpt-researcher-render-tests.yaml llama-swap-tools-tests.yaml rulesync.yaml vllm-render-tests.yaml; do
    [ -f ".github/workflows/$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'FAIL: x4: .github/workflows/%s is gone — C02 narrows docker-build.yaml only; every other cutover sibling stays (C02 AC1 scope fence)\n' "${missing[0]}" >&2
    return 1
  fi
  ok "x4: the five cutover sibling .github/workflows files are untouched (scope fence) [C02 AC1]"
}

leg_x5() {
  if ! python3 - <<'PY'
import re, sys

# x5 pins the detection contract in the gated docs so the prose cannot drift
# the way the echo did. Markers are the vocabulary agreed with C03 (chunk
# file), keyed and line-number-free (x3 discipline). AGENTS.md is checked
# because it is the regenerated carrier of overview.md — C03 lands source and
# generated surface together, so a marker present only in one of them means
# the pair drifted apart.
DOCS = ('skills/container-creation/SKILL.md', '.rulesync/rules/overview.md', 'AGENTS.md')
MARKERS = (
    ('pushed-range', ('before..sha', 'whole pushed range')),
    ('PR merge base', ('merge-base', 'merge base')),
    ('tip-only fallback', ('tip-only',)),
    ('announced empty set', ('announce',)),
    ('fetch-depth reason', ('fetch-depth: 0',)),
)
# On v15.0.10 + runner v13.2.0 the new lines are job-log text: no gated-doc
# sentence may promise an annotation render (RESEARCH 7.2/7.3). The phrase
# list, not the bare word: "renovate annotations" (the pin-keeping rule) and
# C03's sanctioned "announced/annotated first push" wording stay legal.
BANNED = ('ui chip', 'ui annotation', 'run page', 'run-page', 'step summary',
          'step-summary', 'annotation store', 'annotation rendering',
          'renders as an annotation', 'rendered as an annotation')

errs = []
texts = {}
for f in DOCS:
    try:
        text = open(f).read()
    except OSError as exc:
        errs.append(f'cannot read {f}: {exc}')
        continue
    texts[f] = text
    low = text.lower()
    for label, alts in MARKERS:
        if not any(a in low for a in alts):
            errs.append(f'{f}: no {label} marker (any of {alts}) — the detection-contract '
                        'prose drifted out; C03 owns re-landing it')
    # The first-push sentence must PAIR the event with its narrowing inside
    # one paragraph: SKILL.md's tag-walk prose already says "before the first
    # push" about an unrelated fact, so a bare substring check would pass
    # vacuously.
    blocks = [b.lower() for b in re.split(r'\n\s*\n', text)]
    if not any(('first push' in b or 'first-push' in b) and 'tip-only' in b
               for b in blocks):
        errs.append(f'{f}: no sentence block pairs the first push with the '
                    'tip-only narrowing — the fallback must be documented AS a '
                    'narrowing, not merely mentioned (C03)')
    for i, ln in enumerate(text.splitlines(), 1):
        l = ln.lower()
        for b in BANNED:
            if b in l:
                errs.append(f'{f}:{i} claims {b!r} — the changed-set lines are job-log text on '
                            'this build (v15.0.10 has no annotation store); docs may not '
                            'promise a UI render')
        if 'docker-build.yaml' in ln and 'workflow_dispatch' not in ln:
            errs.append(f'{f}:{i} names docker-build.yaml without workflow_dispatch — x3\'s '
                        'per-line rule re-asserted over the regenerated text')
if errs:
    for e in errs:
        print(f'FAIL: x5: {e}', file=sys.stderr)
    sys.exit(1)
PY
  then
    return 1
  fi
  ok "x5: SKILL.md, overview.md and regenerated AGENTS.md carry the detection contract by marker (before..sha range / merge base / first push / tip-only / announced / fetch-depth: 0), no line over-claims an annotation render, and every docker-build.yaml line co-names workflow_dispatch [run -2 C03 AC3-AC4]"
}

# --- C04 repo-wide sweep (g1): every .forgejo/workflows/*.yaml ----------------

leg_g1() {
  if ! python3 - <<'PY'
import os, re, sys, yaml

# NOTE 5 (owner ruling): ONE guard convention repo-wide at merge time — every
# ROLE-referencing job guard is vars.ROLE membership (contains), never exact
# equality (which silently rejects the dev,prod list the owner will set), and
# no .forgejo workflow decides anything by URL. Files are DISCOVERED by the
# directory walk, never hardcoded, so a workflow added later cannot dodge the
# sweep. Per-file FAIL lines name the file and the offending pattern.
ROOT = '.forgejo/workflows'
files = []
for dirpath, _dirnames, filenames in os.walk(ROOT):
    for name in filenames:
        if name.endswith(('.yaml', '.yml')):
            files.append(os.path.join(dirpath, name))
files.sort()

errs = []
if not files:
    errs.append(f'no workflow files discovered under {ROOT} — a directory that lost every workflow is a harness fault or a clobbered tree, never a pass')

for path in files:
    raw = open(path).read()
    for pat in ('git.spencerslab.com', 'git.scifi.farm', 'github.com/', '@github.com'):
        n = raw.count(pat)
        if n:
            errs.append(f'{path}: instance/repo host literal {pat!r} occurs {n} time(s) — NOTE 3: NO direct URL references anywhere in the workflows')
    n = raw.count('startsWith(forgejo.server_url')
    if n:
        errs.append(f'{path}: startsWith(forgejo.server_url occurs {n} time(s) — the URL guard is retired repo-wide (C02/C04)')
    try:
        doc = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        errs.append(f'{path}: does not parse as YAML ({exc})')
        continue
    jobs = (doc or {}).get('jobs') or {}
    ifs = [str(j.get('if')) for j in jobs.values() if isinstance(j, dict) and j.get('if') is not None]
    ifs += [str(s.get('if')) for j in jobs.values() if isinstance(j, dict)
            for s in (j.get('steps') or []) if isinstance(s, dict) and s.get('if') is not None]
    bad = [v for v in ifs if 'forgejo.server_url' in v]
    if bad:
        errs.append(f'{path}: forgejo.server_url inside a job/step if: {bad!r} — host derivation is never a guard predicate (OQ-8)')
    for jname, job in jobs.items():
        guard = str((job or {}).get('if') or '')
        if 'ROLE' in guard and 'ROLE' in guard.replace('vars.ROLE', ''):
            errs.append(f'{path}: {jname}.if references ROLE without the vars carrier ({guard!r}) — every ROLE guard reads the instance variable (no secrets.ROLE, no env-role shadow)')
    m = re.search(r'vars\.ROLE\s*==\s*[\'"]', raw)
    if m:
        errs.append(f"{path}: string-equality ROLE guard {raw[m.start():m.start() + 24]!r} — the repo convention is membership (contains); equality rejects list values and re-breaks on the post-C04 dev,prod flip; the null-comparison vars.ROLE == null stays allowed (byte-boundary: quote after ==)")

if errs:
    for e in errs:
        print(f'FAIL: g1: {e}', file=sys.stderr)
    sys.exit(1)
PY
  then
    return 1
  fi
  ok "g1: every discovered .forgejo/workflows/*.yaml is URL-literal-free, URL-guard-free, server_url-guard-free, guards ROLE only via vars.ROLE membership (no equality form, no shadow carrier) [C04, NOTE 3+5]"
}

run_leg t1 leg_t1
run_leg t2 leg_t2
run_leg t3 leg_t3
run_leg t4 leg_t4
run_leg t5 leg_t5
run_leg t6 leg_t6
run_leg t7 leg_t7
run_leg t8 leg_t8
run_leg t9 leg_t9
run_leg t10 leg_t10
run_leg t11 leg_t11
run_leg t12 leg_t12
run_leg t13 leg_t13
run_leg t14 leg_t14
run_leg t15 leg_t15
run_leg r1 leg_r1
run_leg r2 leg_r2
run_leg r3 leg_r3
run_leg r4 leg_r4
run_leg r5 leg_r5
run_leg d1 leg_d1
run_leg d2 leg_d2
run_leg d3 leg_d3
run_leg d4 leg_d4
run_leg d5 leg_d5
run_leg d6 leg_d6
run_leg d7 leg_d7
run_leg d8 leg_d8
run_leg d9 leg_d9
run_leg d10 leg_d10
run_leg d11 leg_d11
run_leg d12 leg_d12
run_leg d13 leg_d13
run_leg d14 leg_d14
run_leg d15 leg_d15
run_leg x1 leg_x1
run_leg x2 leg_x2
run_leg x3 leg_x3
run_leg x4 leg_x4
run_leg x5 leg_x5
run_leg g1 leg_g1

if [ "$FAILED" -eq 0 ]; then
  printf 'PASS: forgejo-containers-build checks (%d ok)\n' "$checks"
else
  printf 'FAIL: forgejo-containers-build checks (%d ok, %d failed)\n' "$checks" "$FAILED"
  exit 1
fi
