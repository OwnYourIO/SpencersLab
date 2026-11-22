#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/builder-bootstrap.yaml — the
# SINGLE-PURPOSE recovery lane: on a prod-role instance a bare
# workflow_dispatch (no input at all) (re)mints THE lab build image,
# containers/forgejo-runner, to ghcr + the building instance's own registry
# under the surviving calendar law (ticket 2026/2026-11-cf-6-feat-builder-bootstrap-1, C01).
#
# AC trace (C01.md Acceptance criteria): b1[AC1 no-input trigger — THE
# ANTI-TRAP LEG] b2[AC2 paradox guard on the scheduling surface] b3[AC3
# bare-membership clause pin] b4[AC3/AC1 single-job flow] b5[AC5 calendar
# law + F1 push-unconditional] b6[AC6 closed credential surface] b7[AC7
# detector law, flipped halves] b8[AC4 fixed target] b9[AC9 docs law pair,
# single-purpose truth] b10[AC10 syntax] bt1..bt10[AC8 battery].
#
# Red posture (authored against the STILL-GENERAL shipped file): RED at
# b1 (inputs mapping + accessors live), b3 (publish carries the '!= []'
# skip clause the single job may not keep), b4 (detect job + matrix
# present), b7 (detect-mode call present), b8 (matrix-templated build
# context, no forgejo-runner refs, name carriers live), b9 (lane surfaces
# still say any-container service), bt7 (its anchor bytes — the fixed
# context — do not exist yet). GREEN at b2/b5/b6/b10 because the reduction
# preserves the scheduling surface, the calendar law, the closed credential
# surface and the run-block syntax — legs aimed at not-yet-shipped shapes
# are honest about which half of the contract already holds. All 20 ok
# after DEV lands the reduced lane.
#
# Subset discipline (41-suite idiom, groups as separate argv words):
#   bash tests/services/forgejo-builder-bootstrap.sh            # all 20
#   bash tests/services/forgejo-builder-bootstrap.sh b          # the legs
#   bash tests/services/forgejo-builder-bootstrap.sh bt         # the battery
#   bash tests/services/forgejo-builder-bootstrap.sh b2 bt1     # per-leg
#
# The battery mutates TMP COPIES of the workflow — the repo is never written.
# Probes anchor on the TARGET bytes (the fixed build context, the mirrored
# walk blocks, the `for tag in $ghcr_tags` chains): a probe whose anchor
# cannot bite the landed file is itself a FAIL the dev surface must answer —
# a battery leg never passes vacuously. Probe redness is exact: the mutation
# must redden its named leg(s) and nothing else that was green (documented
# collateral: bt7 tolerates b4 — the restored matrix context re-enters the
# matrix-flow ban; bt10 tolerates b3+b6 — the URL-bearing ref trips the
# host greps; bt4 is a compound probe whose two mutations BOTH land on b5).
#
# Pins and their why:
#   - b1 is THE ANTI-TRAP LEG (plan R1): the owner hit the blank-dispatch
#     silent-empty no-op on the general lane and ruled it away. The reduced
#     shape is pinned three ways — parsed on-keys exactly {workflow_dispatch},
#     a whole-document walk rejecting any `inputs` mapping ANYWHERE, and raw
#     accessor greps (forgejo.event.inputs / inputs. / MANUAL_CONTAINERS)
#     EMPTY. bt9 re-arms the trap (restores the input) and must redden b1 by
#     construction. A defaulted input was rejected in ruling: the trap's
#     door left ajar.
#   - b2 is the PARADOX GUARD, and R4 MOVED it to the scheduling surface:
#     the single-purpose file MUST name forgejo-runner as its payload (b8),
#     so the old raw ban on the image name lifted; what may never happen is
#     the lane SCHEDULING on its own output — every runs-on is the public
#     ubuntu-22.04 label, none carries forgejo-runner or a baked-family
#     label, and zero docker:// literals exist to pin an image.
#   - b3 pins the bare membership as the ONLY if-clause of the single job
#     and bans the '!= []' matrix-skip clause outright: with no matrix it
#     is a dangling reference (R2), and its return is the general lane.
#   - b4 pins the single job and the absence of every flow carrier (strategy/
#     matrix/needs/outputs keys, fromJSON, the matrix. accessor).
#   - b5 keeps the shipped calendar methods (t11 tolerance posture, r2
#     all-reads-before-any-push, r3 chain attribution, t8 transitive chain
#     walk) AND absorbs the base review's F1: every docker push sits
#     UNCONDITIONALLY in its attributed for-chain — a semantic
#     manifest-inspect skip written without the banned lexicon would pass
#     the old lexical ban but fails this structural one, and bt4's wrapper
#     mutation proves it.
#   - b6 is the P4' closed set, byte-stable through the reduction: secrets
#     exactly {GHCR_PUSH_PAT, FORGE_PUSH_TOKEN}, vars exactly {ROLE}, two
#     logins, two push sides, zero second-instance names.
#   - b7 flipped its halves per R3: next-n REQUIRED exactly twice (the
#     walks' month math rides the shared script — P6 reuse), the detect-mode
#     call FORBIDDEN (bt7 restores it to prove the return of the general
#     lane reddens here), no all-expansion, no sanitize/pr- shape, no
#     writes under scripts/.
#   - b8 is the FIXED TARGET (its behavioral detect-shape subject died with
#     the input): exactly one docker build, final context
#     containers/forgejo-runner, both registry refs naming forgejo-runner,
#     and ZERO name-carrier shapes (picked/MANUAL_CONTAINERS/matrix./
#     containers/* glob/container= variables) anywhere — a lane that could
#     name another container is not this lane.
#   - b9 rewrites the doc pins for the new truth: the five-workflow
#     enumeration + narrow-class law pair SURVIVES unchanged (ci-surface
#     t1's five-set is R8's byte-frozen neighbor), while the lane-wording
#     surfaces must say single-purpose. The residue ban is scoped to the
#     five live lane surfaces of the b9 RESIDUE tuple exactly — the
#     workflow file, .rulesync/rules, skills/container-creation,
#     AGENTS.md, containers/ — NOT repo-wide —
#     by the two grounded R9 exemptions: containers-build.yaml's own
#     dispatch description says what is true OF IT (that file is FORBIDDEN
#     anyway), and this suite carries the banned phrases inside b9's
#     prohibition tuples as teeth, not residue (tests/ is outside the
#     sweep paths by design).
#   - b10 floors at 2 extracted run blocks (unchanged) and PRINTS the
#     count: the reduced lane is 5 blocks (was 7); the count is a
#     bar-reading fact for review, not a hard pin, because step-splitting
#     (merging the ghcr login into diag) is DEV's honest latitude under
#     the chunk's b6-two-logins condition.
#   - pyyaml resolves the bare `on:` key to boolean True (YAML 1.1): the
#     trigger read takes doc.get(True) or doc.get('on'); a scalar
#     `on: workflow_dispatch` and a null-value mapping are the same legal
#     trigger surface, so both parse shapes are accepted.
#   - x1 rigor stays inverted: a commented push/PR/schedule arm is banned
#     inside on: — dispatch-only is the ruling (P1), and a commented arm is
#     the uncomment one bad review away from re-arming the double-publish.
#
# Constraints: no network, no docker daemon (the lane's live proof is owner
# OL2; `docker build => no-daemon, CI-deferred` is the designed passing
# line). Needs python3+pyyaml and bash. Battery and scratch legs use
# /tmp/opencode only; the repo is never mutated by a probe.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-builder-bootstrap.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BB=".forgejo/workflows/builder-bootstrap.yaml"

checks=0
FAILED=0

TMP=$(mktemp -d /tmp/opencode/forgejo-builder-bootstrap-test.XXXXXX) || { echo 'harness: mktemp failed' >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
group_b()  { for i in 1 2 3 4 5 6 7 8 9 10; do WANT["b$i"]=1; done; }
group_bt() { for i in 1 2 3 4 5 6 7 8 9 10; do WANT["bt$i"]=1; done; }
if [ "$#" -eq 0 ]; then
  group_b; group_bt
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    case "$lc" in
      b)        group_b ;;
      bt|battery) group_bt ;;
      bt10|bt[1-9]) WANT["$lc"]=1 ;;
      b10|b[1-9])   WANT["$lc"]=1 ;;
      *) printf 'FAIL: unknown check id %s (expected b1..b10, bt1..bt10, or groups b bt)\n' "$a" >&2; exit 2 ;;
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

# --- b1: THE ANTI-TRAP LEG — existence, parse, no-input trigger -------------
# Takes the workflow path as $1 so the battery can probe mutated copies.
leg_b1() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b1: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
try:
    doc = yaml.safe_load(raw)
except yaml.YAMLError as exc:
    print(f'FAIL: b1: {path} does not parse: {exc}', file=sys.stderr)
    sys.exit(1)

def need(cond, msg):
    if not cond:
        print(f'FAIL: b1: {msg}', file=sys.stderr)
        sys.exit(1)

trig = doc.get(True) or doc.get('on')
# The reduced trigger surface: workflow_dispatch and nothing else. Both the
# scalar (`on: workflow_dispatch`) and the mapping with a null/{}/value are
# the same legal shape — a scalar physically cannot carry inputs.
if isinstance(trig, dict):
    need(set(trig) == {'workflow_dispatch'},
         f'on: keys are {sorted(map(str, trig))}, expected exactly [workflow_dispatch] — a live push/PR/schedule arm double-publishes against containers-build (P1/AC1)')
else:
    need(trig == 'workflow_dispatch',
         f'trigger surface is {trig!r}, expected workflow_dispatch only (P1/AC1)')

# R1 walk: NO `inputs` mapping anywhere in the document. The owner's
# silent-empty trap was the INPUT, not the dispatch; pinning the keyset
# alone would let `workflow_dispatch: {inputs: {...}}` pass, so the whole
# tree is walked. A defaulted input was rejected by ruling — the trap's
# door left ajar.
def walk(node, where):
    if isinstance(node, dict):
        for k, v in node.items():
            need(str(k) != 'inputs',
                 f'an `inputs:` mapping exists at {where} — the reduced lane takes NO dispatch input (R1: a dispatch is the button, there is nothing to name)')
            walk(v, f'{where}.{k}')
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f'{where}[{i}]')
walk(doc, 'doc')

# x1 rigor, inverted: no commented-out trigger text in the on: block either
# — dispatch-only with no re-enable affordance (AC1).
in_on = False
region = []
for i, line in enumerate(raw.splitlines(), 1):
    if not in_on:
        if re.match(r'^(on|true|True|["\x27]on["\x27])\s*:', line, re.I):
            in_on = True
        continue
    if re.match(r'^[^#\s]', line):
        break
    region.append((i, line))
for i, line in region:
    m = re.match(r'^\s*#?\s*(push|pull_request|schedule|workflow_call|workflow_run|repository_dispatch|create|delete)\s*:', line)
    need(not m, f'on: block line {i} carries a {m.group(1) if m else "?"} arm'
                f'{" (commented)" if line.lstrip().startswith("#") else ""}: {line.strip()!r} — dispatch-only means no commented arm either (AC1/x1 rigor)')

# raw accessor greps (empty): the dispatch input's whole consumption chain.
for pat, why in ((r'forgejo\.event\.inputs', 'reads the dispatch event payload'),
                 (r'inputs\.', 'interpolates an inputs value'),
                 ('MANUAL_CONTAINERS', 'carries the old dispatch-list env var')):
    hits = re.findall(pat, raw) if pat != 'MANUAL_CONTAINERS' else raw.count(pat)
    n = len(hits) if isinstance(hits, list) else hits
    need(n == 0,
         f'{pat!r} occurs {n} time(s) in raw text — {why}; with no input there is nothing to read, and the token returning is the general lane re-entering (R1)')

# no all-expansion shape: the `all` keyword existed only for the input list.
need(re.search(r'["\x27]all["\x27]', raw) is None,
     'a quoted-all expansion shape appears — the all keyword died with the dispatch input (R1/R3); restoring it is the general lane')

conc = doc.get('concurrency')
need(isinstance(conc, dict) and conc.get('cancel-in-progress') is False,
     f'concurrency is {conc!r}, expected a mapping with cancel-in-progress: false (queue stays: capacity-1 serializes, P1 rationale)')
PY
  then
    return 1
  fi
  ok "b1: ANTI-TRAP — parses; on-keys exactly {workflow_dispatch} (scalar or null-mapping shape); NO inputs mapping anywhere in the document; no live/commented push/PR/schedule arm; accessor greps (forgejo.event.inputs / inputs. / MANUAL_CONTAINERS) and the quoted-all expansion EMPTY; concurrency queues (cancel-in-progress false) [C01 AC1, R1]"
}

# --- b2: the PARADOX GUARD, scheduling-surface form (R4) ---------------------
leg_b2() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b2: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import sys, yaml

path = sys.argv[1]
raw = open(path).read()
jobs = (yaml.safe_load(raw) or {}).get('jobs') or {}

def need(cond, msg):
    if not cond:
        print(f'FAIL: b2: {msg}', file=sys.stderr)
        sys.exit(1)

BAKED = {'ubuntu-latest', 'ubuntu-24.04', 'docker', 'node22'}
for name, job in jobs.items():
    label = (job or {}).get('runs-on')
    need(label == 'ubuntu-22.04',
         f'{name}.runs-on is {label!r}, expected the public ubuntu-22.04 label exactly — this lane exists to mint the image the baked labels point at; any other label can schedule onto the image that is not yet published (the paradox re-entry the suite is named for)')
    s = str(label)
    need('forgejo-runner' not in s,
         f'{name}.runs-on {label!r} schedules ON the image this lane produces — the payload naming is legitimate (b8 pins it), the SCHEDULER naming it is the paradox (R4: the ban moved to the scheduling surface)')
    need(s not in BAKED, f'{name}.runs-on {label!r} is a baked-family label (the paradox, stated for the red line)')
need(raw.count('docker://') == 0,
     f'docker:// occurs {raw.count("docker://")} time(s), expected zero — a docker:// literal pins an IMAGE for the scheduler, and this file may pin only the public LABEL (P8)')
PY
  then
    return 1
  fi
  ok "b2: PARADOX GUARD on the scheduling surface (R4) — every runs-on is the public ubuntu-22.04 label exactly; no runs-on names forgejo-runner or a baked-family label; zero docker:// literals. The lifted raw ban is b8's job: the image may be the PAYLOAD, never the scheduler (mutation-probed by bt1/bt10) [C01 AC2]"
}

# --- b3: the bare membership as the ONLY guard clause -------------------------
leg_b3() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b3: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
doc = yaml.safe_load(raw)
jobs = (doc or {}).get('jobs') or {}

def need(cond, msg):
    if not cond:
        print(f'FAIL: b3: {msg}', file=sys.stderr)
        sys.exit(1)

MEMBER = "contains(vars.ROLE, 'prod')"

def clauses(expr):
    return [c.strip() for c in str(expr).split('&&')]

# The clause-list pin (chunk b3): for EVERY job, the guard is exactly the
# bare membership — nothing before it (null-widen), nothing after it. A
# second job or a compound guard is the general lane's detect/publish pair.
for name, job in jobs.items():
    expr = (job or {}).get('if')
    need(expr is not None, f'{name} carries no if: guard — the narrow prod membership must decide the single job')
    need(clauses(expr) == [MEMBER],
         f'{name}.if is {expr!r}, expected exactly [{MEMBER!r}] — narrow on unset (P3 fail-safe class), and with one job there is no matrix and nothing to skip (R2)')

all_exprs = [str(j.get('if') or '') for j in jobs.values() if isinstance(j, dict)]
all_exprs += [str(s.get('if') or '') for j in jobs.values() if isinstance(j, dict)
              for s in (j.get('steps') or []) if isinstance(s, dict) and 'if' in s]
for e in all_exprs:
    need(not re.search(r'vars\.ROLE\s*[=!]=\s*null', e),
         f'a guard carries the null-widen clause ({e!r}) — widen-on-unset would let an unset-ROLE dev instance mint calendar tags (P3 rejected)')
    need(not re.search(r"vars\.ROLE\s*[=!]=\s*['\"]", e),
         f'a guard compares ROLE to a string ({e!r}) — equality polarity is retired (AGENTS hard rule)')
    need('forgejo.server_url' not in e, f'a guard reads forgejo.server_url ({e!r}) — instance decisions are ROLE-only (g1 law, re-pinned here)')
    need('fromjson' not in e.lower(), f'a guard uses fromJSON ({e!r}) — a guard error fails the job; nothing is parsed here anymore (R2)')
    need('startsWith' not in e, f'a guard uses startsWith ({e!r}) — the URL guard is retired repo-wide')

# The matrix-skip clause is BANNED outright (R2): a dangling needs/matrix
# reference with no matrix behind it.
need(re.search(r"!=\s*['\"]\[\]['\"]", raw) is None,
     "a '!= []' skip clause appears — it referenced the detect output; with no detect job and no matrix it is a dangling reference, and its return is the general lane (R2)")

for pat in ('git.spencerslab.com', 'git.scifi.farm', 'github.com/', '@github.com', 'startsWith(forgejo.server_url'):
    need(raw.count(pat) == 0, f'{pat!r} occurs {raw.count(pat)} time(s) in raw text (comments included), expected zero — g1\'s no-URL law re-pinned with this file\'s own suite, not by g1\'s grace alone')
PY
  then
    return 1
  fi
  ok "b3: guard law — every job's if is exactly the bare contains(vars.ROLE, 'prod') membership; no widen/equality/server_url/fromJSON/startsWith in any if; the '!= []' matrix-skip clause is banned (dangling with no matrix); g1's URL substrings absent from raw text [C01 AC3, P3, R2]"
}

# --- b4: the single job and the absence of every flow carrier ------------------
leg_b4() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b4: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
jobs = (doc or {}).get('jobs') or {}

def need(cond, msg):
    if not cond:
        print(f'FAIL: b4: {msg}', file=sys.stderr)
        sys.exit(1)

need(set(jobs) == {'publish'},
     f'jobs keys are {sorted(jobs)}, expected exactly [publish] — the detect job died with the dispatch input; ONE job remains (R2; the name stays because b5/b6/b10 anchor on it)')

BAN_KEYS = ('strategy', 'matrix', 'needs', 'outputs', 'timeout-minutes', 'container', 'services')
def sweep(node, where):
    if isinstance(node, dict):
        for k, v in node.items():
            need(str(k) not in BAN_KEYS,
                 f'{where} carries a {k}: key — no fan-out, no inter-job wiring, no outputs carrier, no job container/services, no per-file timeout in the single-purpose lane (R2, P8, fact 10)')
            sweep(v, f'{where}.{k}')
    elif isinstance(node, list):
        for i, v in enumerate(node):
            sweep(v, f'{where}[{i}]')
sweep(doc, 'doc')

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
need(not carriers,
     f'{len(carriers)} fromJSON carrier(s) {carriers[:2]!r} — nothing parses a runtime list here anymore (R2); the count is zero, not restricted')

raw = open(sys.argv[1]).read()
n = raw.count('matrix.')
need(n == 0,
     f'the matrix. accessor occurs {n} time(s), expected zero — a templated matrix value is the general lane re-entering (AC1 accessor law; bt7 trips here as documented collateral)')

uses = {s['uses'] for job in jobs.values() for s in (job or {}).get('steps', [])
        if isinstance(s, dict) and 'uses' in s}
need(uses == {'actions/checkout@v7'}, f'uses set is {sorted(uses)}, expected exactly actions/checkout@v7 (mirror-inventory law, D8)')
for job in jobs.values():
    for s in (job or {}).get('steps', []):
        if isinstance(s, dict) and 'uses' in s:
            w = s.get('with') or {}
            need('fetch-depth' not in w,
                 f'a checkout carries with: fetch-depth — no diff range exists here (dispatch names nothing), so the depth-0 cost containers-build pays must not be copied (C01 Tasks: shallow only)')
PY
  then
    return 1
  fi
  ok 'b4: single job `publish` — jobs exactly {publish}; zero strategy/matrix/needs/outputs/timeout-minutes/container:/services: keys anywhere; zero fromJSON carriers; the matrix. accessor absent; uses is checkout@v7 only and shallow [C01 AC1/AC3, R2]'
}

# --- b5: calendar law mirror + the F1 semantic push pin -------------------------
leg_b5() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b5: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, shlex, sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
jobs = (doc or {}).get('jobs') or {}
steps_txt = [str(s.get('run', '')) for s in ((jobs.get('publish') or {}).get('steps') or [])
             if isinstance(s, dict) and 'run' in s]
raw = open(sys.argv[1]).read()

def need(cond, msg):
    if not cond:
        print(f'FAIL: b5: {msg}', file=sys.stderr)
        sys.exit(1)

need(steps_txt, 'publish has no run steps — the calendar law is unpinnable (C01 Tasks name the pair of walks + the build/push step)')

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

def side(stmt):
    low = stmt.lower()
    if 'ghcr' in low:
        return 'ghcr'
    if 'forge' in low:
        return 'forge'
    return None

# t11 methodology: every registry read answers absence as an HTTP code, never
# a fail-flag; the walk lives inside its side's list-200 branch; ghcr keeps
# the pull-token nesting and the 200-without-token fatal guard.
reads = [s for s in statements if 'curl' in s and ('tags/list' in s or 'manifests/' in s or 'ghcr.io/token' in s)]
need(reads, 'no curl read of a registry endpoint in publish — N is registry-derived (P5)')
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
    need(fail_flag(c) is None, f'the registry read {c.strip()!r} carries a fail-flag — absence answers 403 (ghcr token) or 404 (forge), and a fail-flagged read dies before next-n (41-suite major-2 posture, mirrored)')
    need('%{http_code}' in c, f'the registry read {c.strip()!r} does not capture the HTTP code — mirrored tolerance posture')

joined = '\n'.join(steps_txt)
defaults = re.findall(r'(?m)^[ \t]*(n_ghcr|n_forge)=1[ \t]*(#.*)?$', joined)
need(len(defaults) >= 2, f'{len(defaults)} per-side n=1 default line(s), expected one per side (tolerated absence falls through to the month first release, RD8 mirrored)')
nncalls = [s for s in statements if 'next-n' in s]
need(len(nncalls) >= 2, f'{len(nncalls)} next-n call(s), expected two (the union max walks BOTH registries, fact 10; b7 pins the exact count)')
for c in nncalls:
    need('YYMM=' in c, f'next-n call {c.strip()!r} does not pass YYMM — the month arrives via env exactly as containers-build does')

lines = joined.splitlines()
def if_block(pred):
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
    need(blk, f'no {want}-side list-200 branch — the existence walk may run only where the tags/list read answered 200 (mirrored)')
    walk = '\n'.join(lines[blk[0] + 1:blk[1]])
    need(re.search(r'(?m)^[ \t]*while\b', walk) and 'manifests/' in walk,
         f'the {want} advance-walk (while + manifests) must sit inside its list-200 branch (mirrored: a side that answered 404 contributes no tags and gets no walk)')
    tol = [ln for ln in lines if want in ln.lower() and '_code' in ln and all(code in ln for code in ('401', '403', '404'))]
    need(tol, f'no {want}-side 401/403/404 tolerance branch — anything else than those codes stays fatal (mirrored posture)')
token_blk = if_block(lambda ln: 'token' in ln.lower() and '200' in ln and 'forge' not in ln.lower())
need(token_blk, 'no ghcr token-200 branch — the ghcr reads need the pull token (its manifest endpoint answers 401 anonymously)')
gl = if_block(lambda ln: 'ghcr' in ln.lower() and 'list' in ln and '200' in ln)
need(token_blk[0] < gl[0] and gl[1] <= token_blk[1], 'the ghcr tags/list branch is not nested inside the pull-token branch')
token_body = '\n'.join(lines[token_blk[0] + 1:token_blk[1]])
need(re.search(r'\[\s*-z\b', token_body) and 'exit 1' in token_body,
     'the ghcr token branch lost its 200-without-token fail-loud guard — an empty bearer would turn tags/list into the tolerated 401 and publish over a taken tag with no walk')

# r2 methodology: every walk finishes before the first push.
push_i = [i for i, s in enumerate(statements) if 'docker push' in s]
read_i = [i for i, s in enumerate(statements) if s in reads]
need(push_i, 'no docker push in publish — the lane must publish')
need(max(read_i) < min(push_i), 'a registry read or walk sits after the first docker push — the union max must complete before any publish (fact 10, mirrored)')

# union max + fixed month + three-tag trio per side + ghcr-then-own order
need(re.search(r'n=\$n_ghcr\b', joined), 'no n=$n_ghcr seed line — the calendar N is the union maximum of the two walked sides (fact 10)')
need(re.search(r'n_forge["\x27]?\s*-gt', joined), 'no -gt advance against n_forge — union max, not per-side N')
need(raw.count('date +%y.%m') == 1, f'date +%y.%m occurs {raw.count("date +%y.%m")} time(s), expected exactly 1 (the month is fixed once per job and shared via calendar.env, mirrored)')
need(re.search(r'echo "month=\$month" > calendar\.env', joined), 'the fixed month is never written to calendar.env (the family mechanism both walks and the build read)')

def has_cal(text):
    return '$month' in text or '%y.%m' in text

push_lines = {'ghcr': [], 'forge': []}
push_lists = {'ghcr': [], 'forge': []}
stack = []
for i, s in enumerate(statements):
    if s.startswith('#'):
        continue
    m = re.match(r'^for\b[^;]*\bin\b(.*)$', s)
    if m:
        stack.append(re.sub(r';\s*do\s*$', '', m.group(1)).strip())
    elif re.match(r'^done\b', s) and stack:
        stack.pop()
    if 'docker push' in s:
        a = side(s) or (side(stack[-1]) if stack else None)
        need(a is not None, f'unattributable docker push: {s!r} — every push must carry the ghcr/forge token in its line or its enclosing for: list (r3 method; the mirror ships exactly two attributed chains)')
        push_lines[a].append((i, s))
        if stack:
            push_lists[a].append(stack[-1])
need(push_lines['ghcr'] and push_lines['forge'], 'the push chains do not cover both registries (targets are ghcr + the building instance only, P4\x27)')
gi = [i for i, _ in push_lines['ghcr']]
fi_ = [i for i, _ in push_lines['forge']]
need(max(gi) < min(fi_), 'a forge push precedes a ghcr push — the mirrored order is ghcr first so a half-failed run gaps the side with no pinned consumers (fact 10)')

assignments = {}
for s in statements:
    if '=' in s and not s.startswith('#'):
        assignments.setdefault(s.split('=', 1)[0].strip(), s)
PREFIX = {'ghcr': 'ghcr.io/ownyourio/', 'forge': 'curatedforest'}
for token, lines_t in (('ghcr', push_lines['ghcr']), ('forge', push_lines['forge'])):
    chain = [s for _, s in lines_t] + push_lists[token]
    seen = set()
    for _ in range(3):
        names = {v for text in chain for v in re.findall(r'\{?(\w+)\}?', text)} - seen
        seen |= names
        chain += [assignments[v] for v in names if v in assignments]
    blob = '\n'.join(chain)
    need(PREFIX[token] in blob, f'the {token} push chain builds no image-qualified reference ({PREFIX[token]}<image>) (t8 chain discipline)')
    need('latest' in blob and re.search(r'\bmain\b', blob) and has_cal(blob),
         f'the {token} push chain does not reach all three tags (calendar + latest + main, the trio both targets carry, AC5)')

# no skip-if-exists logic in any runnable line (the lane's own comments may
# state the law by name — the ban reads code, not prose); the N+1 law travels
# with the file's own text.
code_only = '\n'.join(ln for ln in raw.splitlines() if not ln.strip().startswith('#'))
need(not re.search(r'(?i)skip[- _]?if[- _]?exists|already (pushed|published)|tag exists', code_only),
     'a skip-if-exists shape appears in code — every successful publish mints a fresh N; skipping would freeze the line (P5)')

# F1 (base review, closed HERE per R7): the LEXICAL ban above only sees the
# skip vocabulary. The semantic skip — an `if docker manifest inspect ...;
# then continue; fi` around a push — would pass the vocabulary check while
# freezing latest/main against the calendar law. Structural teeth: every
# docker push sits DIRECTLY in its attributed for-chain body, inside no
# if/while/case wrapper. bt4's wrapper mutation proves the leg bites.
for text in steps_txt:
    ctrl = []
    for ln in text.splitlines():
        st = ln.strip()
        if not st or st.startswith('#'):
            continue
        if re.match(r'^for\b', st):
            ctrl.append('for')
        elif re.match(r'^(while|until)\b', st):
            ctrl.append('loop')
        elif re.match(r'^(if|case)\b', st):
            ctrl.append('branch')
        elif re.match(r'^(done|fi|esac)\b', st):
            if ctrl:
                ctrl.pop()
        if 'docker push' in st:
            need(ctrl and ctrl[-1] == 'for',
                 f'docker push {st[:90]!r} is not directly inside a for-chain body (control stack {ctrl}) — every push must be UNCONDITIONAL; a conditional wrapper is a semantic skip-if-exists (F1/R7)')

need(re.search(r'(?i)(n\s*\+\s*1|advance until|gaps?[ ,;]?[^.\n]*never[^.\n]*clobber)', raw),
     'the file never states the registry-max-walk / gaps-never-clobbers law (launch pin: re-dispatch mints N+1 — the law text travels with the lane)')

# the forge-side API reads are TLS (the PAT must not ride http; r5 shape-4
# distilled to the hazard it guards): any curl whose statement literally
# builds a /v2/ URL on a forge-named variable must wear the scheme.
for s in statements:
    if 'curl' in s and '/v2/' in s and 'forge' in s.lower() and '$' in s:
        need('https://' in s, f'curl reads a forge /v2/ endpoint over a scheme-less URL ({s[:110]!r}) — curl defaults to http and would ship FORGE_PUSH_TOKEN in cleartext (fact 10 scheme law)')
PY
  then
    return 1
  fi
  ok "b5: calendar law mirrored + F1 closed — per-side ghcr_/forge_ walks with tolerance posture and the token-200/empty-token guards, all walks before the first push, union max + one fixed month + calendar.env, three-tag trio per side, ghcr-then-own chains, NO skip-if-exists lexically AND every docker push unconditionally in its for-chain, N+1 law text present [C01 AC5, P5, R7]"
}

# --- b6: the P4' NO-PEER closed set (byte-stable through the reduction) ---------
leg_b6() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b6: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
doc = yaml.safe_load(raw)
jobs = (doc or {}).get('jobs') or {}

def need(cond, msg):
    if not cond:
        print(f'FAIL: b6: {msg}', file=sys.stderr)
        sys.exit(1)

# Boundary-anchored extraction (t7 discipline): PAT -> PATX is a DIFFERENT
# identifier, and FORGE_PUSH_TOKEN_DEV must not pass as FORGE_PUSH_TOKEN.
secrets = set(re.findall(r'\bsecrets\.([A-Za-z_][A-Za-z0-9_]*)', raw))
vars_ = set(re.findall(r'\bvars\.([A-Za-z_][A-Za-z0-9_]*)', raw))
need(secrets == {'GHCR_PUSH_PAT', 'FORGE_PUSH_TOKEN'},
     f'secrets.* set is {sorted(secrets)}, expected exactly GHCR_PUSH_PAT + FORGE_PUSH_TOKEN — the credential surface is CLOSED by the owner ruling 2026-11-22 (P4\x27); a new secret needs a new ruling, and it reddens here first')
need(vars_ == {'ROLE'},
     f'vars.* set is {sorted(vars_)}, expected exactly ROLE — no second-registry variable may ever enter this lane (P4\x27)')
for tok in ('FORGE_DEV_REGISTRY', 'FORGE_PUSH_TOKEN_DEV', 'PUSH_URL_DEV', 'PUSH_TOKEN_DEV',
            'scifi.farm', 'spencerslab'):
    need(raw.count(tok) == 0,
         f'{tok!r} occurs {raw.count(tok)} time(s), expected zero — any second-instance name, minted or literal, is the peer arm the ruling rejected (fact 13)')

logins = [ln.strip() for ln in raw.splitlines() if 'docker login' in ln and not ln.strip().startswith('#')]
need(len(logins) == 2, f'{len(logins)} docker login lines, expected exactly 2 (ghcr + the building instance — two targets, full stop, AC6)')
need(any('ghcr.io' in l for l in logins), 'no login reaches ghcr.io')
need(any(re.search(r'\$\{?forge_registry', l) for l in logins), 'no login reaches the derived $forge_registry host')

def side(stmt):
    low = stmt.lower()
    if 'ghcr' in low:
        return 'ghcr'
    if 'forge' in low:
        return 'forge'
    return None
statements = []
for text in (str(s.get('run', '')) for job in jobs.values() for s in (job or {}).get('steps', [])
             if isinstance(s, dict) and 'run' in s):
    buf = ''
    for ln in text.splitlines():
        st = ln.strip()
        if st.endswith('\\'):
            buf = (buf + ' ' + st[:-1].strip()).strip()
            continue
        if st or buf:
            statements.append((buf + ' ' + st).strip())
        buf = ''
sides = []
stack = []
for s in statements:
    if s.startswith('#'):
        continue
    m = re.match(r'^for\b[^;]*\bin\b(.*)$', s)
    if m:
        stack.append(re.sub(r';\s*do\s*$', '', m.group(1)).strip())
    elif re.match(r'^done\b', s) and stack:
        stack.pop()
    if 'docker push' in s:
        a = side(s) or (side(stack[-1]) if stack else None)
        need(a is not None, f'unattributable docker push: {s!r} — the two-chain pin needs every push side-named (b5 shares the method)')
        sides.append(a)
need(set(sides) == {'ghcr', 'forge'},
     f'push sides are {sorted(set(sides))}, expected exactly ghcr + forge — a third chain name is a third target (P4\x27); the arm ORDER is b5\'s law, not this leg\'s')
PY
  then
    return 1
  fi
  ok "b6: NO-PEER pin, byte-stable — secrets.* exactly {GHCR_PUSH_PAT, FORGE_PUSH_TOKEN}, vars.* exactly {ROLE}, zero second-instance names anywhere, exactly two logins (ghcr.io + the derived forge host) and two push chains (ghcr, forge) — a future cross-host arm reddens HERE (owner ruling 2026-11-22, P4'; R6) [C01 AC6]"
}

# --- b7: detector law, halves flipped per R3 -------------------------------------
leg_b7() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b7: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
doc = yaml.safe_load(raw)
jobs = (doc or {}).get('jobs') or {}

def need(cond, msg):
    if not cond:
        print(f'FAIL: b7: {msg}', file=sys.stderr)
        sys.exit(1)

code_all = []
for job in jobs.values():
    for s in (job or {}).get('steps', []):
        if isinstance(s, dict) and 'run' in s:
            for ln in str(s.get('run', '')).splitlines():
                st = ln.strip()
                if st and not st.startswith('#'):
                    code_all.append(st)
code_joined = '\n'.join(code_all)

# REQUIRED half: the two walks keep calling the shared script's month math
# (P6 reuse — re-inlining the arithmetic would fork it away from
# containers-build's proven single source; ruling OQ-1 best-guess).
nncalls = [s for s in code_all if 'next-n' in s]
need(len(nncalls) == 2,
     f'{len(nncalls)} next-n call(s), expected exactly 2 — the two registry walks ride the shared detector for the month math (R3: the surviving calendar-law mirror)')
for c in nncalls:
    need('YYMM=' in c, f'next-n call {c!r} does not pass YYMM — the month arrives via env exactly as containers-build does')

# FORBIDDEN half: the detect-mode call. It gated the dispatch list; with no
# input there is nothing to gate, and its return is the general-lane
# sneak-in (bt7-probed). Checked on code lines — comments may recount the
# lane's history.
need(re.search(r'forgejo-container-detect\.sh[ \t]+detect', code_joined) is None,
     'a detect-mode call appears — the detection step died with the dispatch input; a returned call means the general any-container lane is re-entering (R3)')
need('containers/*/' not in code_joined and not re.search(r'=\s*["\x27]all["\x27]', code_joined),
     "an all-expansion shape appears in code — the keyword expansion died with the input (R3)")

need(raw.count('sanitize') == 0, 'sanitize appears — this lane never mints PR tags (the PR arm is containers-build alone)')
need(re.search(r'(?<![A-Za-z0-9._-])pr-', raw) is None, 'a pr- tag shape appears — the bootstrap lane must never produce one (P4\x27 family posture)')

for text in (str(s.get('run', '')) for job in jobs.values() for s in (job or {}).get('steps', [])
             if isinstance(s, dict) and 'run' in s):
    for ln in text.splitlines():
        st = ln.strip()
        if not st or st.startswith('#') or 'scripts/forgejo-container-detect.sh' in st:
            continue
        need(not re.search(r'^\s*(sudo\s+)?(rm|cp|mv|tee|touch|chmod|chown|mkdir|rmdir|ln|dd|patch|install)\b[^\n]*\bscripts/', st)
             and not re.search(r'>{1,2}\s*["\x27]?[^\s"\x27]*scripts/', st)
             and not re.search(r'\bsed\b[^\n]*-i[^\n]*\bscripts/', st),
             f'a run body writes under scripts/: {st!r} — the shared detector is byte-untouched (P6); reuse, never reshape')
PY
  then
    return 1
  fi
  ok "b7: detector law, flipped halves — next-n REQUIRED exactly twice (YYMM env, the surviving calendar-law mirror), the detect-mode call and the all-expansion FORBIDDEN, no sanitize/pr- shape, no run body writes under scripts/ (bt7 restores the detect call and reddens this leg) [C01 AC7, R3]"
}

# --- b8: the fixed target (repurposed — no input to exercise behaviorally) --------
leg_b8() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b8: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, shlex, sys, yaml

path = sys.argv[1]
raw = open(path).read()
doc = yaml.safe_load(raw)
jobs = (doc or {}).get('jobs') or {}

def need(cond, msg):
    if not cond:
        print(f'FAIL: b8: {msg}', file=sys.stderr)
        sys.exit(1)

statements = []
for job in jobs.values():
    for s in (job or {}).get('steps', []):
        if isinstance(s, dict) and 'run' in s:
            buf = ''
            for ln in str(s.get('run', '')).splitlines():
                st = ln.strip()
                if st.endswith('\\'):
                    buf = (buf + ' ' + st[:-1].strip()).strip()
                    continue
                if st or buf:
                    statements.append((buf + ' ' + st).strip())
                buf = ''

builds = [s for s in statements if re.match(r'^docker build ', s)]
need(len(builds) == 1,
     f'{len(builds)} docker build command lines, expected exactly 1 — the single-purpose lane mints ONE image (R4; buildx lines are excluded by the command anchor)')
if builds:
    try:
        toks = shlex.split(builds[0])
    except ValueError:
        toks = builds[0].split()
    need(toks[-1] == 'containers/forgejo-runner',
         f'the build context is {toks[-1]!r}, expected exactly containers/forgejo-runner — the fixed target IS the ruling (a templated or variable context is the general lane)')

n_ghcr = raw.count('ownyourio/forgejo-runner')
n_own = raw.count('curatedforest/forgejo-runner')
need(n_ghcr >= 1 and n_own >= 1,
     f'image refs: ownyourio/forgejo-runner x{n_ghcr}, curatedforest/forgejo-runner x{n_own}, expected at least one each — both push targets must name the build image (the R4 payload naming b2 released)')

for tok in ('picked', 'MANUAL_CONTAINERS', 'matrix.', 'containers/*'):
    need(raw.count(tok) == 0,
         f'{tok!r} occurs {raw.count(tok)} time(s), expected zero — every name-carrier shape (variable, matrix, glob loop) died with the input; any of them returning means a lane that could name ANOTHER container (R4)')
code_lines = [ln for ln in raw.splitlines() if ln.strip() and not ln.strip().startswith('#')]
carrier = [ln.strip() for ln in code_lines if re.search(r'(?i)[a-z0-9_]*container[a-z0-9_]*\s*=\s*["\x27$]', ln)]
need(not carrier,
     f'a container-name variable assignment appears in code: {carrier[:2]!r} — the target is fixed by the ruling, not carried by a variable')
PY
  then
    return 1
  fi
  ok "b8: FIXED TARGET — exactly one docker build with final context containers/forgejo-runner; both registry refs (ghcr ownyourio + curatedforest) name forgejo-runner; zero name-carrier shapes (picked/MANUAL_CONTAINERS/matrix./containers-glob/container= variable) anywhere [C01 AC4, R4]"
}

# --- b9: the doc law pair, rewritten to the single-purpose truth -----------------
leg_b9() {
  if ! python3 - <<'PY'
import os, re, sys

BB = '.forgejo/workflows/builder-bootstrap.yaml'
DOCS = ('AGENTS.md', '.rulesync/rules/overview.md',
        'skills/container-creation/SKILL.md', 'containers/forgejo-runner/README.md')
PAIR = ('AGENTS.md', '.rulesync/rules/overview.md')
LANE = 'skills/container-creation/SKILL.md'
README = 'containers/forgejo-runner/README.md'
# The five live lane-wording surfaces (plan fact 6 / R9): the residue pin
# greps EXACTLY these — containers-build.yaml's own dispatch description is
# exempt (true about itself, file FORBIDDEN) and tests/ is exempt (this
# suite carries the phrases inside b9's prohibition tuples: teeth, not
# residue). History folders are dated record, not lies.
RESIDUE = (BB, '.rulesync/rules', 'skills/container-creation', 'AGENTS.md', 'containers')
BANNED = ('any named container', "any container's", 'name the containers')
EMPTY_LIST = re.compile(r'(?i)\bempty list\b')
NOINPUT = re.compile(r'(?i)(no input|takes nothing|without any input|inputless|no dispatch input)')

def blocks(text):
    return [' '.join(b.lower().split()) for b in re.split(r'\n\s*\n', text)]

errs = []
texts = {}
for f in DOCS + (BB,):
    try:
        texts[f] = open(f).read()
    except OSError as exc:
        errs.append(f'cannot read {f}: {exc}')

# 1. The residue sweep (the Commands-bar grep, encoded): the three
#    general-lane phrases and the empty-list clause are gone from EVERY
#    live lane surface.
if not errs:
    for path in RESIDUE:
        files = []
        if os.path.isfile(path):
            files.append(path)
        else:
            for dirpath, _dn, filenames in os.walk(path):
                for name in filenames:
                    files.append(os.path.join(dirpath, name))
        for fp in sorted(files):
            try:
                body = open(fp).read()
            except (UnicodeDecodeError, OSError):
                continue  # binary or unreadable: not prose, cannot lie
            for phrase in BANNED:
                if phrase in body:
                    errs.append(f'{fp}: still claims the general lane ({phrase!r}) — no live surface may describe any-container service after the reduction (fact 6)')
            if EMPTY_LIST.search(body):
                errs.append(f'{fp}: still carries an empty-list law clause — the empty-list law died with the dispatch input (R9)')

if not errs:
    # 2. The five-workflow law pair: source + generated twin carry it
    #    together (rulesync discipline), each naming builder-bootstrap in
    #    the narrow class. R8: the enumeration is UNCHANGED — the file
    #    persists, the family stays five.
    for f in PAIR:
        if not any(('five' in b and '.forgejo' in b and 'builder-bootstrap' in b and 'narrow' in b)
                   for b in blocks(texts[f])):
            errs.append(f'{f}: no single block states the FIVE-workflow enumeration with builder-bootstrap in the narrow class (P7′ — unchanged by the reduction; ci-surface t1 is the byte-frozen five-set neighbor)')
    # 3. The PAIR lane block must name the build image (single purpose):
    #    the block carrying the lane with its recovery/dispatch wording
    #    pairs it with forgejo-runner.
    for f in PAIR:
        lane_blocks = [b for b in blocks(texts[f])
                       if 'builder-bootstrap' in b and ('recovery lane' in b or 'dispatch-driven' in b or '(re)mints' in b)]
        if not lane_blocks:
            errs.append(f'{f}: no lane block identifies builder-bootstrap as the recovery lane — the law sentence moved somewhere the pair pin cannot read')
        for b in lane_blocks:
            if 'forgejo-runner' not in b and 'build image' not in b:
                errs.append(f'{f}: the builder-bootstrap lane block does not name the build image (containers/forgejo-runner) it (re)mints — single purpose is the ruling (R9)')
    # 4. SKILL names the lane with its REAL surface: no-input dispatch,
    #    ghcr + the building instance, the build image (fact 7g discipline:
    #    the doc moves must not drift the target list).
    skill_lane = [b for b in blocks(texts[LANE]) if 'builder-bootstrap' in b]
    if not skill_lane:
        errs.append(f'{LANE}: no block names the builder-bootstrap lane anymore')
    for b in skill_lane:
        ok_pos = ('dispatch' in b and 'ghcr' in b
                  and ('own registry' in b or 'building instance' in b)
                  and NOINPUT.search(b) and ('forgejo-runner' in b or 'build image' in b))
        if not ok_pos:
            errs.append(f'{LANE}: the lane block does not pair builder-bootstrap with the no-input dispatch, ghcr + the building instance, and the build image it mints (R9: single-purpose truth)')
    # 5. README byte-kept: the base deviation-2 fix ALREADY wrote it
    #    single-purpose-true, so its claims pin here while the file stays
    #    untouched (the bar's git-diff proof is the byte half).
    for f in DOCS:
        m = re.search(r'(?i)\bfour\b[^.\n]{0,60}`?\.forgejo', texts[f])
        if m:
            errs.append(f'{f}: still claims a four-workflow .forgejo family ({m.group(0)!r}) — the sentence goes false the moment the lane file exists (fact 8)')
    if not any('builder-bootstrap' in b and '22.04' in b for b in blocks(texts[README])):
        errs.append(f'{README}: the correction does not pair the builder-bootstrap lane with the public act-22.04 image it rides (C01 Tasks: the dated pointer)')
    if not any('builder-bootstrap' in b and 'mints this image' in b for b in blocks(texts[README])):
        errs.append(f'{README}: the single-purpose truth (the lane is what mints THIS image when the baked reference is missing) moved — the byte-keep proof means this claim stays exactly as the base run landed it')
    # 6. x3 per-line rule, local mirror on the three gated prose carriers.
    for f in PAIR + (LANE,):
        for i, ln in enumerate(texts[f].splitlines(), 1):
            if 'docker-build.yaml' in ln and 'workflow_dispatch' not in ln:
                errs.append(f'{f}:{i} names docker-build.yaml without workflow_dispatch — x3 line rule re-asserted here')
    # 7. The NO-PEER ruling travels with the docs (survives unchanged): the
    #    coined peer names never enter any doc surface, and no block
    #    naming the lane may claim a second-instance target.
    for f in DOCS:
        for tok in ('FORGE_DEV_REGISTRY', 'FORGE_PUSH_TOKEN_DEV', 'PUSH_URL_DEV', 'PUSH_TOKEN_DEV'):
            if tok in texts[f]:
                errs.append(f'{f}: carries {tok} — a peer-arm identifier has no home in any doc surface (P4\x27)')
        for b in blocks(texts[f]):
            if 'builder-bootstrap' in b and re.search(r'(?i)scifi\.farm|spencerslab|(dev|peer|second|cross)[ -]registry', b):
                errs.append(f'{f}: a builder-bootstrap block claims a peer/dev/second-registry target — the lane publishes ghcr + the building instance ONLY (owner ruling 2026-11-22)')

if errs:
    for e in errs:
        print(f'FAIL: b9: {e}', file=sys.stderr)
    sys.exit(1)
PY
  then
    return 1
  fi
  ok "b9: doc law pair at the SINGLE-PURPOSE truth — residue grep (any named container / any container's / name the containers / empty-list clause) EMPTY over exactly the five live lane surfaces (R9's two grounded exemptions encoded by the scoped path list); overview+AGENTS keep the five-workflow narrow-class enumeration AND name the build image in the lane block; SKILL pairs the lane with the no-input dispatch + ghcr + own; README byte-keeps its single-purpose claims; four-workflow ban, x3 rule and peer-claim bans unchanged [C01 AC9, R8/R9]"
}

# --- b10: embedded run syntax ----------------------------------------------------
leg_b10() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b10: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  local dir="$TMP/b10"
  rm -rf "$dir"; mkdir -p "$dir"
  local n
  n=$(python3 - "$f" "$dir" <<'PY' || echo 0
import os, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
n = 0
for jname, job in ((doc or {}).get('jobs') or {}).items():
    for i, s in enumerate((job or {}).get('steps', [])):
        if isinstance(s, dict) and 'run' in s:
            n += 1
            with open(os.path.join(sys.argv[2], f'{jname}-{i}.sh'), 'w') as fh:
                fh.write(str(s['run']))
print(n)
PY
)
  [ "$n" -ge 2 ] || { printf 'FAIL: b10: extracted %s run block(s), expected at least the walk+push pair (floor unchanged; the reduced lane reads 5, was 7 — the count below is the bar fact)\n' "$n" >&2; return 1; }
  local b
  for b in "$dir"/*.sh; do
    bash -n "$b" || { printf 'FAIL: b10: the embedded run block %s is not bash -n clean\n' "$(basename "$b")" >&2; return 1; }
  done
  ok "b10: all $n embedded run blocks parse under bash -n (every run step is plain shell, the family steps law; reduced-lane expectation is 5, floor is >= 2)"
}

# --- battery: mutation probes on TMP copies (the repo is never written) ----------
PROBE_LEGS="b1 b2 b3 b4 b5 b6 b7 b8 b10"
_bat_base=""
battery_baseline() {
  [ -n "$_bat_base" ] && return 0
  _bat_base='clean'
  local l
  for l in $PROBE_LEGS; do
    if ! ( "leg_$l" "$BB" >/dev/null 2>&1 ); then
      _bat_base="$_bat_base $l"
    fi
  done
}
in_list() { local needle="$1"; shift; local x; for x in "$@"; do [ "$x" = "$needle" ] && return 0; done; return 1; }

probe() { # id  mutation-fn  named-legs  allowed-collateral  description
  local id="$1" mut="$2" named="$3" allow="$4" desc="$5"
  want "$id" || return 0
  [ -f "$BB" ] || { printf 'FAIL: %s: cannot probe — %s does not exist yet (the battery certifies the landed file)\n' "$id" "$BB" >&2; return 1; }
  battery_baseline
  local copy="$TMP/$id.yaml"
  cp "$BB" "$copy"
  if ! "$mut" "$copy"; then
    printf 'FAIL: %s: the mutation anchor did not match the landed file (%s) — a probe that cannot bite proves nothing; the target bytes the battery anchors on are C01 Tasks contract\n' "$id" "$desc" >&2
    return 1
  fi
  local reds="" l
  for l in $PROBE_LEGS; do
    if ! ( "leg_$l" "$copy" >/dev/null 2>&1 ); then reds="$reds $l"; fi
  done
  local n
  for n in $named; do
    in_list "$n" $reds || { printf 'FAIL: %s: mutation (%s) did NOT redden %s — a vacuous pin: the ruling it guards would merge unenforced\n' "$id" "$desc" "$n" >&2; return 1; }
  done
  local r
  for r in $reds; do
    in_list "$r" $named $allow $_bat_base || { printf 'FAIL: %s: mutation (%s) also reddened %s outside the named/allowed/baseline set — the probe is not surgical\n' "$id" "$desc" "$r" >&2; return 1; }
  done
  ok "$id: mutation '$desc' reddens exactly [$named] on the TMP copy (repo untouched)"
}

mut_bt1() { python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
n = t.count('runs-on: ubuntu-22.04')
assert n >= 1, 'no public-label line to flip'
open(p, 'w').write(t.replace('runs-on: ubuntu-22.04', 'runs-on: ubuntu-24.04'))
PY
}
mut_bt2() { python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
s = "if: contains(vars.ROLE, 'prod')"
assert s in t, 'no bare membership guard to widen'
open(p, 'w').write(t.replace(s, "if: vars.ROLE == null || " + s[len('if: '):]))
PY
}
mut_bt3() { python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
m = re.search(r'(?m)([ \t]+)for tag in \$ghcr_tags; do\n(?:.*\n)*?\1done\n', t)
assert m, 'no ghcr push loop of the mirrored shape'
m2 = re.search(r'(?m)([ \t]+)for tag in \$forge_tags; do\n(?:.*\n)*?\1done\n', t)
assert m2 and m2.start() >= m.end(), 'no forge push loop after the ghcr one'
own, ghcr = m2.group(0), m.group(0)
new = t[:m.start()] + own + t[m.end():m2.start()] + ghcr + t[m2.end():]
open(p, 'w').write(new)
PY
}
mut_bt4() { # compound: (1) delete the ghcr existence-walk block; (2) wrap the
# ghcr push chain in a condition — both mutations must land ONLY on b5
# (the walk guard and the F1 semantic push pin, same named leg).
python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)
idx = next((i for i, l in enumerate(lines) if 'ghcr_code=$(ghcr_manifest_code' in l and 'while' not in l), None)
assert idx is not None, 'no ghcr existence-walk start to delete'
ind = lines[idx][:len(lines[idx]) - len(lines[idx].lstrip())]
end = idx
while not (lines[end].rstrip() == ind + 'done'):
    end += 1
    assert end < len(lines) + 100, 'unbalanced walk block'
lines = lines[:idx] + lines[end + 1:]
t = ''.join(lines)
import re
m = re.search(r'(?m)^([ \t]*)for tag in \$ghcr_tags; do\n([ \t]*)docker push "\$tag"\n\1done\n', t)
assert m, 'no unconditional ghcr push loop to wrap'
g1, g2 = m.group(1), m.group(2)
wrapped = (g1 + 'for tag in $ghcr_tags; do\n' + g2 + 'if true; then\n' + g2 + '  docker push "$tag"\n'
           + g2 + 'fi\n' + g1 + 'done\n')
open(p, 'w').write(t[:m.start()] + wrapped + t[m.end():])
PY
}
mut_bt5() { python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)
lines.insert(1, '# peer copies would ride git.scifi.farm/curatedforest\n')
open(p, 'w').write(''.join(lines))
PY
}
mut_bt6() { python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
anchor = '      - name: build and push'
assert anchor in t, 'no build-and-push step to precede the peer block with'
peer = """      - name: log in to the peer registry
        env:
          FORGE_DEV_HOST: ${{ vars.FORGE_DEV_REGISTRY }}
        run: |
          set -euo pipefail
          printf '%s' '${{ secrets.FORGE_PUSH_TOKEN_DEV }}' | docker login "$FORGE_DEV_HOST" -u forge-push --password-stdin
"""
push = """          for tag in $forge_dev_tags; do
            docker push "$tag"
          done
"""
t = t.replace(anchor, peer + anchor, 1)
mark = 'for tag in $forge_tags; do'
assert mark in t, 'no forge push chain to append the peer chain to'
end = t.index('done', t.index(mark)) + len('done\n')
t = t[:end] + push + t[end:]
open(p, 'w').write(t)
PY
}
mut_bt7() { # the general-lane sneak-in: restore the detect call and the
# matrix-templated build context ⇒ b7 (detect mode) + b8 (fixed target);
# b4 tolerated (the matrix. accessor re-enters through the same string).
python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
assert '"containers/forgejo-runner"' in t, 'no fixed build context to loosen (the general lane is already loose — probe targets the reduced file)'
t = t.replace('"containers/forgejo-runner"', '"containers/${{ matrix.container }}"', 1)
m = re.search(r'(- name: build and push\n(?:.*\n)*?[ \t]*)set -euo pipefail\n', t)
assert m, 'no build-and-push step body to restore the detect call into'
t = t[:m.end()] + '          picked=$(bash scripts/forgejo-container-detect.sh detect)\n' + t[m.end():]
open(p, 'w').write(t)
PY
}
mut_bt8() { python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
m = re.search(r'(?m)^on:\s*$', t) or re.search(r'(?m)^true:\s*$', t)
if m:
    ins = m.end() + 1
    open(p, 'w').write(t[:ins] + '  push:\n    branches: [main]\n' + t[ins:])
else:
    m2 = re.search(r'(?m)^on:[ \t]+workflow_dispatch[ \t]*$', t)
    assert m2, 'no on: surface (mapping or scalar) to arm a live push trigger on'
    open(p, 'w').write(t[:m2.start()] + 'on:\n  push:\n    branches: [main]\n  workflow_dispatch:\n' + t[m2.end():])
PY
}
mut_bt9() { # THE TRAP PROBE: restore the dispatch input the owner ruled
# away ⇒ b1 red by construction — the silent-empty failure mode re-armed.
python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
m = re.search(r'(?m)^([ \t]*)workflow_dispatch\s*:?\s*(\{[ \t]*\})?\s*$', t)
if m:
    ind = m.group(1)
    block = (ind + 'workflow_dispatch:\n'
             + ind + '  inputs:\n'
             + ind + '    containers:\n'
             + ind + "      description: 'names to mint'\n"
             + ind + '      required: false\n'
             + ind + "      default: ''\n"
             + ind + '      type: string\n')
    t = t[:m.start()] + block + t[m.end():]
else:
    m2 = re.search(r'(?m)^on:[ \t]+workflow_dispatch[ \t]*$', t)
    assert m2, 'no workflow_dispatch surface (mapping or scalar) to restore the input on'
    block = ('on:\n  workflow_dispatch:\n    inputs:\n      containers:\n'
             "        description: 'names to mint'\n        required: false\n        default: ''\n        type: string\n")
    t = t[:m2.start()] + block + t[m2.end():]
open(p, 'w').write(t)
PY
}
mut_bt10() { python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
assert 'runs-on: ubuntu-22.04' in t, 'no public-label line to re-point'
open(p, 'w').write(t.replace('runs-on: ubuntu-22.04',
                             'runs-on: docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1', 1))
PY
}

leg_bt1()  { probe bt1  mut_bt1  b2   ''        'runs-on flipped to the baked ubuntu-24.04 (the paradox via a schedulable-but-unpublished label; g1 also reddens in the real tree — cross-suite tooth)'; }
leg_bt2()  { probe bt2  mut_bt2  b3   ''        'the null-widen clause added to the guard (the dev-mints-calendar hazard P3 rejected)'; }
leg_bt3()  { probe bt3  mut_bt3  b5   ''        'the ghcr/own push chains swapped (the gap would land on the pinned side)'; }
leg_bt4()  { probe bt4  mut_bt4  b5   ''        'the ghcr existence-walk deleted AND the ghcr push wrapped in a condition (walk gone; the F1 semantic skip-if-exists the lexical ban could not see)'; }
leg_bt5()  { probe bt5  mut_bt5  'b3 b6' ''     'the instance host literal inserted in a comment (g1 counts comments; the b3/b6 re-pin must too)'; }
leg_bt6()  { probe bt6  mut_bt6  b6   ''        'a peer push arm with vars.FORGE_DEV_REGISTRY + secrets.FORGE_PUSH_TOKEN_DEV added (the NO-PEER ruling own teeth)'; }
leg_bt7()  { probe bt7  mut_bt7  'b7 b8' 'b4'   'the general lane sneak-in: detect call restored + the fixed build context loosened to the matrix (b4 tolerated — the matrix. accessor re-enters through the same string)'; }
leg_bt8()  { probe bt8  mut_bt8  b1   ''        'a live push: trigger armed inside on: (the double-publish P1 rejected)'; }
leg_bt9()  { probe bt9  mut_bt9  b1   ''        'THE TRAP PROBE — the dispatch input re-armed (the owner-hit silent-empty shape returns; b1 reddens by construction, R1)'; }
leg_bt10() { probe bt10 mut_bt10 b2   'b3 b6'   'runs-on pointed at the instance calendar ref (the exact paradox re-entry: an image this lane has not yet minted; the URL-bearing ref trips b3+b6 as documented collateral)'; }

run_leg b1  leg_b1
run_leg b2  leg_b2
run_leg b3  leg_b3
run_leg b4  leg_b4
run_leg b5  leg_b5
run_leg b6  leg_b6
run_leg b7  leg_b7
run_leg b8  leg_b8
run_leg b9  leg_b9
run_leg b10 leg_b10
run_leg bt1  leg_bt1
run_leg bt2  leg_bt2
run_leg bt3  leg_bt3
run_leg bt4  leg_bt4
run_leg bt5  leg_bt5
run_leg bt6  leg_bt6
run_leg bt7  leg_bt7
run_leg bt8  leg_bt8
run_leg bt9  leg_bt9
run_leg bt10 leg_bt10

if [ "$FAILED" -eq 0 ]; then
  printf 'PASS: forgejo-builder-bootstrap checks (%d ok)\n' "$checks"
else
  printf 'FAIL: forgejo-builder-bootstrap checks (%d ok, %d failed)\n' "$checks" "$FAILED"
  exit 1
fi
