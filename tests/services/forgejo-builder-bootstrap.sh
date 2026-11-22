#!/usr/bin/env bash
# Offline contract suite for .forgejo/workflows/builder-bootstrap.yaml — the
# dispatch-only, public-image recovery lane that (re)mints any container's
# calendar tags on a prod-role instance to ghcr + the building instance's own
# registry (ticket 2026/2026-11-cf-6-feat-builder-bootstrap, C01 v2).
#
# AC trace (C01.md Acceptance criteria): b1[AC1] b2[AC2 — the PARADOX GUARD]
# b3[AC3] b4[AC1/AC3 flow shape] b5[AC4 calendar law] b6[AC4 P4' NO-PEER
# closed set] b7[AC5 detector reuse] b8[AC6 behavioral detect shapes] b9[AC8
# law pair + docs] b10[AC9 syntax] bt1..bt10[AC9 battery].
#
# Red posture (authored BEFORE the workflow exists): every b-leg plus every
# bt-probe is RED until DEV lands .forgejo/workflows/builder-bootstrap.yaml
# (b1..b8, b10, bt1..bt10: file existence; b9: the doc surfaces still carry
# the four-workflow enumeration). b9's peer-claim clauses and the x3 per-line
# clause inside it are prohibitions that already hold today and must keep
# holding; the enumeration clauses are the red-until-DEV ones. On the full
# green run the suite answers 20 ok.
#
# Subset discipline (41-suite idiom, groups as separate argv words):
#   bash tests/services/forgejo-builder-bootstrap.sh            # all 20
#   bash tests/services/forgejo-builder-bootstrap.sh b          # the legs
#   bash tests/services/forgejo-builder-bootstrap.sh bt         # the battery
#   bash tests/services/forgejo-builder-bootstrap.sh b2 bt1     # per-leg
#
# The battery mutates TMP COPIES of the workflow — the repo is never written.
# Probes anchor on the shipped-mirror bytes (the ghcr_/forge_ per-side tokens,
# the `for tag in $ghcr_tags` loop headers, `ghcr_manifest_code()`): C01 Tasks
# require those blocks to mirror containers-build.yaml, so a probe anchor that
# cannot be applied is itself a FAIL the dev surface must answer — a battery
# leg never passes vacuously. Probe redness is exact: the mutation must redden
# its named leg(s) and nothing else that was green (documented collateral for
# bt7's inline-filter twin and bt10's URL-bearing ref aside).
#
# Pins and their why:
#   - b2 is the lane's reason to exist: its jobs run on the PUBLIC act image
#     through the ubuntu-22.04 label, so the lane can mint the baked runner
#     image that every OTHER workflow needs. Any other runs-on (especially a
#     calendar/baked ref or a docker:// literal) re-arms the paradox — the
#     suite reddens it before CI can silently schedule nothing.
#   - b6 implements owner ruling P4' (2026-11-22, NO PEER) as an executable
#     closed set: every secrets.* reference is in {GHCR_PUSH_PAT,
#     FORGE_PUSH_TOKEN} and every vars.* reference in {ROLE}. A future
#     cross-host arm must redden this leg and force a fresh ruling, not sneak
#     in as a variable.
#   - the ROLE guard is NARROW here (calendar-minting lane = the fail-safe
#     class): b3 pins the ABSENCE of the null-widen clause that
#     containers-build deliberately carries, so the widen cannot drift in
#     through copy-paste. ci-surface t6 is the family-level twin of this pin;
#     b3 keeps the law inside the lane's own suite.
#   - b5 follows the 41-suite's proven methods: t11's per-side tolerance
#     branches, r2's all-reads-before-any-push ordering, r3's chain
#     attribution for the ghcr-then-own push order (an unattributable push
#     fails), t8's transitive chain walk (a tag no chain reaches is never
#     pushed). Re-stating them per-side is the mirror contract.
#   - b8 is behavioral because text pins cannot see a silently reverted
#     dispatch contract (the 41-suite's t14 lesson): the shipped detect run
#     body is extracted and EXECUTED against a copy of the SHIPPED detector
#     (byte-untouched — P6) in a scratch tree; five faithful input shapes
#     answer exact JSON arrays, and the empty dispatch stays the silent no-op
#     the family law pins.
#   - pyyaml resolves the bare `on:` key to boolean True (YAML 1.1): trigger
#     legs read doc.get(True) or doc.get('on') — the 41-suite/main-sync
#     idiom; asserting the string key alone would redden a correct file.
#   - x1 rigor here runs INVERTED: containers-build blesses commented-out
#     triggers as a re-enable affordance; this lane's AC1 forbids any
#     push/PR/schedule text (live or commented) inside on: — dispatch-only is
#     the ruling (P1), and a commented arm is the uncomment one bad review
#     away from re-arming the double-publish.
#
# Constraints: no network, no docker daemon (the lane's live proof is owner
# OL2; AC11-shape `docker build => no-daemon, CI-deferred` stands); needs
# python3+pyyaml and bash. Self-mutating legs use /tmp/opencode scratch only.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-builder-bootstrap.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BB=".forgejo/workflows/builder-bootstrap.yaml"
HELP="scripts/forgejo-container-detect.sh"
HELP_ABS="$PWD/$HELP"

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

# --- b1: existence, parse, trigger surface, input shape, concurrency ---------
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
except yaml.YAMLLError as exc:
    print(f'FAIL: b1: {path} does not parse: {exc}', file=sys.stderr)
    sys.exit(1)

def need(cond, msg):
    if not cond:
        print(f'FAIL: b1: {msg}', file=sys.stderr)
        sys.exit(1)

trig = doc.get(True) or doc.get('on')
need(isinstance(trig, dict), 'no top-level on: mapping')
# P1: dispatch-only. The parsed key-set is the authoritative inertness pin.
need(set(trig) == {'workflow_dispatch'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly [workflow_dispatch] — a live push/PR/schedule arm double-publishes against containers-build (P1)')

# x1 rigor, inverted per the header pin: no commented-out trigger text in the
# on: block either — this lane's ruling is dispatch-only with no re-enable
# affordance (AC1).
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

wd = trig['workflow_dispatch'] or {}
inp = (wd.get('inputs') or {}).get('containers')
need(isinstance(inp, dict), 'the containers dispatch input is missing — P2 names it')
need(inp.get('type') == 'string', f'input type is {inp.get("type")!r}, expected string (P2)')
need(inp.get('default') == '', f'input default is {inp.get("default")!r}, expected "" (P2 silent-empty)')
need(inp.get('required', False) is False, f'input required is {inp.get("required")!r}, expected false/absent')
desc = str(inp.get('description') or '')
need(re.search(r'(?i)comma', desc) and re.search(r'(?i)space', desc),
     f'input description {desc!r} does not name the comma/space list (C01 Tasks)')
need(re.search(r'(?i)(^|[^a-z])all([^a-z]|$)', desc),
     f'input description {desc!r} does not name the all keyword (P2)')
# P2's silent-empty law stated in the file's own wording: a lane whose empty
# list was fatal would answer differently than containers-build's dispatch.
need(re.search(r'(?i)empty[^\n]{0,60}(nothing|no-op|no op)', raw),
     'the file never states the empty-list-is-a-no-op law near "empty" — P2 mirrors the family silent-empty law and the wording must travel with the input')

conc = doc.get('concurrency')
need(isinstance(conc, dict) and conc.get('cancel-in-progress') is False,
     f'concurrency is {conc!r}, expected a mapping with cancel-in-progress: false (fact 10 family law)')
PY
  then
    return 1
  fi
  ok "b1: $BB exists, parses, triggers on workflow_dispatch ONLY (no live or commented push/PR/schedule arm), input containers is a string default '' naming the list/all/empty-no-op law, concurrency queues (cancel-in-progress false) [C01 AC1]"
}

# --- b2: the PARADOX GUARD -----------------------------------------------------
leg_b2() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b2: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

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
    need(label not in BAKED, f'{name}.runs-on {label!r} is a baked-family label (the paradox, stated twice for the red line)')
need(raw.count('docker://') == 0,
     f'docker:// occurs {raw.count("docker://")} time(s), expected zero — a docker:// runs-on literal pins an IMAGE, and this file may pin only the public LABEL (P8)')
for tok in ('ownyourio/forgejo-runner',):
    need(raw.count(tok) == 0, f'{tok!r} occurs {raw.count(tok)} time(s), expected zero (the lane may not name the image it mints as its own runner)')
need(re.search(r'forgejo-runner\s*:', raw) is None,
     'a forgejo-runner: label-mapping/image-tag shape appears — the lane runs on the public act image, never on its own output')
PY
  then
    return 1
  fi
  ok "b2: PARADOX GUARD — every runs-on is the public ubuntu-22.04 label only; zero docker://, zero baked-family label, zero forgejo-runner ref or mapping shapes (mutation-probed by bt1/bt10) [C01 AC2, P8]"
}

# --- b3: narrow ROLE guards + the g1 law re-pinned for this file ---------------
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
SKIP = "needs.detect.outputs.containers != '[]'"

def clauses(expr):
    return [c.strip() for c in str(expr).split('&&')]

det = str((jobs.get('detect') or {}).get('if') or '')
pub = str((jobs.get('publish') or {}).get('if') or '')
need(clauses(det) == [MEMBER],
     f'detect.if is {det!r}, expected exactly the bare prod membership {MEMBER!r} — narrow on unset (P3: a calendar-minting lane belongs to the fail-safe class; the widen clause is containers-build\'s alone)')
need(clauses(pub) == [MEMBER, SKIP],
     f'publish.if is {pub!r}, expected exactly {MEMBER!r} && {SKIP!r} (bare membership + the matrix skip clause)')

all_exprs = [str(j.get('if') or '') for j in jobs.values() if isinstance(j, dict)]
all_exprs += [str(s.get('if') or '') for j in jobs.values() if isinstance(j, dict)
              for s in (j.get('steps') or []) if isinstance(s, dict) and 'if' in s]
for e in all_exprs:
    need(not re.search(r'vars\.ROLE\s*[=!]=\s*null', e),
         f'a guard carries the null-widen clause ({e!r}) — widen-on-unset would let an unset-ROLE dev instance mint calendar tags (P3 rejected)')
    need(not re.search(r"vars\.ROLE\s*[=!]=\s*['\"]", e),
         f'a guard compares ROLE to a string ({e!r}) — equality polarity is retired (AGENTS hard rule)')
    need('dev' not in e.replace(MEMBER, '').replace(SKIP, '').lower() or 'dev' in SKIP,
         f'a guard references the dev role ({e!r}) — this lane is prod-membership only (P3)')
    need('forgejo.server_url' not in e, f'a guard reads forgejo.server_url ({e!r}) — instance decisions are ROLE-only (g1 law, re-pinned here)')
    need('fromjson' not in e.lower(), f'a guard uses fromJSON ({e!r}) — a guard error fails the job; only the matrix may parse the detector output (OQ-2 law)')
    need('startsWith' not in e, f'a guard uses startsWith ({e!r}) — the URL guard is retired repo-wide')

for pat in ('git.spencerslab.com', 'git.scifi.farm', 'github.com/', '@github.com', 'startsWith(forgejo.server_url'):
    need(raw.count(pat) == 0, f'{pat!r} occurs {raw.count(pat)} time(s) in raw text (comments included), expected zero — g1\'s no-URL law re-pinned with this file\'s own suite, not by g1\'s grace alone')
PY
  then
    return 1
  fi
  ok "b3: both job guards are exactly the bare contains(vars.ROLE, 'prod') membership (+ publish's matrix skip clause); no widen/equality/server_url/fromJSON/startsWith in any if; g1's four URL substrings absent from raw text [C01 AC3, P3]"
}

# --- b4: job set, matrix flow, uses surface ------------------------------------
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

need(set(jobs) == {'detect', 'publish'},
     f'jobs keys are {sorted(jobs)}, expected exactly detect + publish (C01 Tasks job pair)')

det = jobs['detect'] or {}
pub = jobs['publish'] or {}
out = (det.get('outputs') or {}).get('containers')
need(isinstance(out, str) and re.search(r'steps\.[\w-]+\.outputs\.[\w-]+', out),
     f'detect.outputs.containers is {out!r}, expected a steps.<id>.outputs.<key> carrier (the detector emits via the step-output file)')
needs = pub.get('needs')
need(needs == 'detect' or (isinstance(needs, list) and needs == ['detect']),
     f'publish.needs is {needs!r}, expected detect')
strat = pub.get('strategy') or {}
mat = (strat.get('matrix') or {}).get('container')
need(mat == '${{ fromJSON(needs.detect.outputs.containers) }}',
     f'matrix.container is {mat!r}, expected the byte form from C01 Tasks (the only sanctioned fromJSON parses the detector\'s own output)')
need(strat.get('fail-fast') is False, f'strategy.fail-fast is {strat.get("fail-fast")!r}, expected boolean false (siblings keep publishing)')

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
    need('needs.detect.outputs' in s and 'vars.' not in s,
         f'fromJSON carrier {where} is {s!r} — fromJSON may only read the detect step output, never a vars.* value (OQ-2)')

for name, job in jobs.items():
    need('timeout-minutes' not in (job or {}), f'{name} restates timeout-minutes — the runner\'s 30m ceiling is the law, per-file restatement is not (fact 10)')
    need('container' not in (job or {}) and 'services' not in (job or {}),
         f'{name} carries container:/services: — the act image IS the environment; a job container changes the mount model for zero need (P8)')
    for s in (job or {}).get('steps', []):
        if isinstance(s, dict):
            need('services' not in s, f'{name} has a step with services:')

uses = {s['uses'] for job in jobs.values() for s in (job or {}).get('steps', [])
        if isinstance(s, dict) and 'uses' in s}
need(uses == {'actions/checkout@v7'}, f'uses set is {sorted(uses)}, expected exactly actions/checkout@v7 (mirror-inventory law, D8)')
for job in jobs.values():
    for s in (job or {}).get('steps', []):
        if isinstance(s, dict) and 'uses' in s:
            w = s.get('with') or {}
            need('fetch-depth' not in w,
                 f'a checkout carries with: fetch-depth — no diff range exists here (dispatch names its own set), so the depth-0 cost containers-build pays must not be copied (C01 Tasks: shallow)')
PY
  then
    return 1
  fi
  ok "b4: jobs are detect+publish; matrix is the byte-pinned fromJSON over the detect output with fail-fast false; no timeout-minutes, no container:/services:, uses is checkout@v7 only and shallow [C01 AC1/AC3 flow]"
}

# --- b5: calendar law mirror ----------------------------------------------------
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
need(len(nncalls) >= 2, f'{len(nncalls)} next-n call(s), expected two (the union max walks BOTH registries, fact 10)')
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
         f'the {token} push chain does not reach all three tags (calendar + latest + main, the trio both targets carry, AC4)')

# no skip-if-exists logic in any runnable line (the lane's own comments may
# state the law by name — the ban reads code, not prose); the N+1 law travels
# with the file's own text.
code_only = '\n'.join(ln for ln in raw.splitlines() if not ln.strip().startswith('#'))
need(not re.search(r'(?i)skip[- _]?if[- _]?exists|already (pushed|published)|tag exists', code_only),
     'a skip-if-exists shape appears in code — every successful publish mints a fresh N; skipping would freeze the line (P5)')
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
  ok "b5: calendar law mirrored — per-side ghcr_/forge_ walks with tolerance posture and the token-200/empty-token guards, all walks before the first push, union max + one fixed month + calendar.env, three-tag trio per side, ghcr-then-own chains, no skip-if-exists, N+1 law text present [C01 AC4, P5, fact 10]"
}

# --- b6: the P4' NO-PEER closed set ---------------------------------------------
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
need(len(logins) == 2, f'{len(logins)} docker login lines, expected exactly 2 (ghcr + the building instance — two targets, full stop, AC4)')
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
  ok "b6: NO-PEER pin — secrets.* is exactly {GHCR_PUSH_PAT, FORGE_PUSH_TOKEN}, vars.* exactly {ROLE}, zero second-instance names anywhere, exactly two logins (ghcr.io + the derived forge host) and two push chains (ghcr, forge) — a future cross-host arm reddens HERE (owner ruling 2026-11-22, P4')"
}

# --- b7: detector reuse, env contract, expansion order --------------------------
leg_b7() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b7: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  if ! python3 - "$f" <<'PY'
import re, sys, yaml

path = sys.argv[1]
raw = open(path).read()
doc = yaml.safe_load(raw)
jobs = (doc or {}).get('jobs') or {}
det_steps = (jobs.get('detect') or {}).get('steps') or []

def need(cond, msg):
    if not cond:
        print(f'FAIL: b7: {msg}', file=sys.stderr)
        sys.exit(1)

step = next((s for s in det_steps if isinstance(s, dict) and 'bash scripts/forgejo-container-detect.sh detect' in str(s.get('run', ''))), None)
need(step, 'the detect job never calls the SHIPPED detector\'s detect mode — P6 reuses it unchanged, it is not re-implemented')
body = str(step.get('run', ''))
env = step.get('env')
need(isinstance(env, dict) and set(env) == {'EVENT_NAME', 'MANUAL_CONTAINERS'},
     f'detect step env keys are {sorted(env) if isinstance(env, dict) else env!r}, expected exactly EVENT_NAME + MANUAL_CONTAINERS (the dispatch path reads only these; extra accessors invite a routed event into a lane that has none)')
need(env.get('EVENT_NAME') == 'workflow_dispatch',
     f'EVENT_NAME is {env.get("EVENT_NAME")!r}, expected the static workflow_dispatch literal — the lane IS dispatch-only; a live accessor would route a foreign event into the dispatch arm')
need(env.get('MANUAL_CONTAINERS') == '${{ forgejo.event.inputs.containers }}',
     f'MANUAL_CONTAINERS is {env.get("MANUAL_CONTAINERS")!r}, expected the byte accessor (t13 discipline: the accessor string is the contract)')

call_i = next(i for i, ln in enumerate(body.splitlines()) if 'forgejo-container-detect.sh detect' in ln)
pre = '\n'.join(body.splitlines()[:call_i])
need(re.search(r'(?i)\ball\b', pre), 'the all-keyword expansion is not BEFORE the detector call (P2: the expansion lives in the step, the gate stays in the shipped script)')
need('Dockerfile' in pre, 'the all-expansion does not enumerate Dockerfile-bearing dirs (P2 scope of "all")')

m = re.search(r'(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)=[ \t]*\$\(bash scripts/forgejo-container-detect\.sh[ \t]+detect[^\n]*\)[ \t]*$', body)
need(m, 'the detector output is not a standalone assignment (pattern var=$(bash ... detect)) — assign before emitting or a failed detect writes an empty matrix (t10 major-1 law, mirrored)')
var = m.group(1)
emits = [ln for ln in body.splitlines() if re.search(r'>> "\$\{GITHUB_OUTPUT:-\$FORGEJO_OUTPUT\}"', ln)]
need(emits, 'no emit appends via "${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}" (the family output-file contract)')
for ln in emits:
    need('$(' not in ln and re.search(r'\$\{?' + re.escape(var) + r'\b', ln),
         f'the emit line {ln.strip()!r} must interpolate the assigned {var}, never re-inline the substitution (t10)')
need(body.count('$(bash scripts/forgejo-container-detect.sh') == 1,
     'a second detect command substitution appeared — exactly the assignment may invoke it')

pub_runs = '\n'.join(str(s.get('run', '')) for s in ((jobs.get('publish') or {}).get('steps') or [])
                     if isinstance(s, dict) and 'run' in s)
need('next-n' in pub_runs, 'publish never calls next-n — the walks are the shared script\'s month math, not restated arithmetic (P6)')
need(raw.count('sanitize') == 0, 'sanitize appears — this lane never mints PR tags (b7: the PR arm is containers-build alone)')
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
  ok "b7: detector REUSE, zero edits — the detect step calls the shipped script with the exact two-key env contract, all-expansion precedes the call, assign-then-emit honors the output-file law, next-n drives the walks, no sanitize/pr- anywhere, no run body writes under scripts/ [C01 AC5, P6]"
}

# --- b8: behavioral detect shapes (t14 pattern) ----------------------------------
leg_b8() {
  local f="${1:-$BB}"
  [ -f "$f" ] || { printf 'FAIL: b8: %s does not exist (C01 lands it)\n' "$f" >&2; return 1; }
  local sdir="$TMP/b8-${RANDOM}"
  mkdir -p "$sdir/fix/containers/alpha" "$sdir/fix/containers/beta" \
           "$sdir/fix/containers/Not_a_Name" "$sdir/fix/containers/no-dockerfile" "$sdir/fix/scripts" || { printf 'FAIL: b8: harness could not build the scratch tree\n' >&2; return 1; }
  printf 'FROM scratch\n' | tee "$sdir/fix/containers/alpha/Dockerfile" "$sdir/fix/containers/beta/Dockerfile" "$sdir/fix/containers/Not_a_Name/Dockerfile" >/dev/null
  echo readme > "$sdir/fix/containers/no-dockerfile/README.md"
  cp "$HELP_ABS" "$sdir/fix/scripts/forgejo-container-detect.sh" || { printf 'FAIL: b8: harness could not copy the shipped detector\n' >&2; return 1; }
  if ! python3 - "$f" "$sdir" <<'PY'
import os, re, shlex, sys, yaml

path, sdir = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(path))
jobs = (doc or {}).get('jobs') or {}

def bail(msg):
    print(f'FAIL: b8: {msg}', file=sys.stderr)
    sys.exit(1)

pub = jobs.get('publish') or {}
mat = str(((pub.get('strategy') or {}).get('matrix') or {}).get('container') or '')
m = re.search(r'fromJSON\(needs\.([\w-]+)\.outputs\.([\w-]+)\)', mat)
if not m:
    bail('the matrix reference does not name needs.<job>.outputs.<key> — the output chain is unpinnable')
dj, okey = m.groups()
outref = str(((jobs.get(dj) or {}).get('outputs') or {}).get(okey) or '')
m2 = re.search(r'steps\.([\w-]+)\.outputs\.([\w-]+)', outref)
if not m2:
    bail(f'{dj}.outputs.{okey} does not resolve to a steps.<id>.outputs.<key> carrier ({outref!r})')
sid, skey = m2.groups()
step = next((s for s in ((jobs.get(dj) or {}).get('steps') or []) if isinstance(s, dict) and s.get('id') == sid), None)
if not step or 'run' not in step:
    bail(f'no step with id {sid!r} and a run body under the {dj} job')
open(os.path.join(sdir, 'body.sh'), 'w').write(str(step['run']))
env = step.get('env') or {}
with open(os.path.join(sdir, 'env.inc'), 'w') as fh:
    for k, v in env.items():
        if k == 'MANUAL_CONTAINERS':
            continue
        fh.write(f'export {k}={shlex.quote(str(v))}\n')
open(os.path.join(sdir, 'chain_key'), 'w').write(skey + '\n')
PY
  then
    return 1
  fi
  local KEY
  KEY=$(cat "$sdir/chain_key")

  b8_shape() { # label manual_containers expected_json expect_silent(yes|no|skip-silence-check)
    local label="$1" input="$2" expect="$3" silent="$4"
    local of="$sdir/out" bodyout errf="$sdir/err" rc
    rm -f "$of"; : > "$of"
    if bodyout=$( cd "$sdir/fix" && . "$sdir/env.inc" && MANUAL_CONTAINERS="$input" GITHUB_OUTPUT="$of" bash "$sdir/body.sh" 2>"$errf" ); then
      rc=0
    else
      rc=$?
    fi
    [ "$rc" -eq 0 ] || { printf 'FAIL: b8: the %s shape exited %d — the dispatch run body must stay offline-executable (the shipped detector answers, never dies, on these inputs)\n' "$label" "$rc" >&2; return 1; }
    local got
    got=$(grep -m1 "^${KEY}=" "$of" 2>/dev/null | sed "s/^${KEY}=//" || true)
    got="${got//[[:space:]]/}"
    [ "$got" = "$expect" ] || { printf 'FAIL: b8: the %s shape answered %s, expected %s (container-dir + name gates and dedup/sort are the shipped detector contract; %s)\n' "$label" "${got:-<empty>}" "$expect" "$input" >&2; return 1; }
    if [ "$silent" = yes ]; then
      case "$bodyout$(cat "$errf")" in
        *'::warning::'*) printf 'FAIL: b8: the empty dispatch list warned — a dispatch names its own build set and the empty one is the documented no-op intent (family silent-empty law)\n' >&2; return 1 ;;
      esac
    fi
    return 0
  }
  if ! b8_shape 'empty list'          ''                    '[]'                      yes \
    || ! b8_shape 'all expansion'     'all'                 '["alpha","beta"]'        skip \
    || ! b8_shape 'bogus + ghost'     'alpha ghost'         '["alpha"]'               skip \
    || ! b8_shape 'dupe + unordered'  'beta,alpha alpha'    '["alpha","beta"]'        skip \
    || ! b8_shape 'no-Dockerfile dir' 'no-dockerfile'       '[]'                      skip ; then
    return 1
  fi
  ok "b8: executing the shipped detect run body against the shipped detector answers the five dispatch shapes exactly — empty=[] silent (the family no-op), all=every Dockerfile dir (Not_a_Name and no-dockerfile excluded), bogus/unbuilt names filtered, dupes collapsed and sorted [C01 AC6]"
}

# --- b9: the law pair + the doc surfaces (red until the DEV doc moves) ----------
leg_b9() {
  if ! python3 - <<'PY'
import re, sys

DOCS = ('AGENTS.md', '.rulesync/rules/overview.md',
        'skills/container-creation/SKILL.md', 'containers/forgejo-runner/README.md')
PAIR = ('AGENTS.md', '.rulesync/rules/overview.md')
LANE = 'skills/container-creation/SKILL.md'
README = 'containers/forgejo-runner/README.md'

def blocks(text):
    return [b.lower() for b in re.split(r'\n\s*\n', text)]

errs = []
texts = {}
for f in DOCS:
    try:
        texts[f] = open(f).read()
    except OSError as exc:
        errs.append(f'cannot read {f}: {exc}')

if not errs:
    # The five-workflow law pair: source + generated twin carry it together
    # (rulesync discipline), each naming builder-bootstrap in the narrow class.
    for f in PAIR:
        if not any(('five' in b and '.forgejo' in b and 'builder-bootstrap' in b and 'narrow' in b)
                   for b in blocks(texts[f])):
            errs.append(f'{f}: no single block states the FIVE-workflow enumeration with builder-bootstrap in the narrow class (P7\x27 — the ROLE-law paragraph must name the lane where the class is decided)')
    # SKILL.md names the lane and its real surface: dispatch, ghcr, own
    # registry (fact 7g: the doc moves must not drift the target list).
    if not any('builder-bootstrap' in b and 'dispatch' in b and 'ghcr' in b
               and ('own registry' in b or 'building instance' in b)
               for b in blocks(texts[LANE])):
        errs.append(f'{LANE}: no block names the builder-bootstrap lane with its dispatch trigger and ghcr + own-registry targets')
    # README: the four-workflow assumption corrected with the dated public-image
    # pointer. The ban pattern is 'four' within a line-span of the workflow
    # directory — 'four of the five' phrasings are deliberately covered too:
    # the only true claims left are five-count ones.
    for f in DOCS:
        m = re.search(r'(?i)\bfour\b[^.\n]{0,60}`?\.forgejo', texts[f])
        if m:
            errs.append(f'{f}: still claims a four-workflow .forgejo family ({m.group(0)!r}) — the sentence goes false the moment the lane file exists (fact 8)')
    if not any('builder-bootstrap' in b and '22.04' in b for b in blocks(texts[README])):
        errs.append(f'{README}: the correction does not pair the builder-bootstrap lane with the public act-22.04 image it rides (C01 Tasks: the dated pointer)')
    # x3 per-line rule, local mirror on the three gated prose carriers.
    for f in PAIR + (LANE,):
        for i, ln in enumerate(texts[f].splitlines(), 1):
            if 'docker-build.yaml' in ln and 'workflow_dispatch' not in ln:
                errs.append(f'{f}:{i} names docker-build.yaml without workflow_dispatch — x3 line rule re-asserted here')
    # The NO-PEER ruling travels with the docs: the coined peer names never
    # enter any doc surface, and no block naming the lane may claim a
    # second-instance target (today vacuously green — the ruling was never
    # doc-true and must not become doc-false).
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
  ok "b9: law pair green — overview.md + AGENTS.md state the five-workflow enumeration with builder-bootstrap narrow-on-unset, SKILL.md names the lane (ghcr+own), README carries the dated act-22.04 correction, no stale four-claim, x3 per-line rule holds, and no doc surface ever claims a peer target [C01 AC8, P7']"
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
  [ "$n" -ge 2 ] || { printf 'FAIL: b10: extracted %s run block(s), expected at least the detect + publish pair\n' "$n" >&2; return 1; }
  local b
  for b in "$dir"/*.sh; do
    bash -n "$b" || { printf 'FAIL: b10: the embedded run block %s is not bash -n clean\n' "$(basename "$b")" >&2; return 1; }
  done
  ok "b10: all $n embedded run blocks parse under bash -n (every run step is plain shell, the family steps law)"
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
    printf 'FAIL: %s: the mutation anchor did not match the landed file (%s) — a probe that cannot bite proves nothing; the shipped-mirror bytes the battery anchors on are C01 Tasks contract\n' "$id" "$desc" >&2
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
mut_bt4() { python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)
idx = next((i for i, l in enumerate(lines) if 'ghcr_manifest_code()' in l), None)
assert idx is not None, 'no ghcr existence-walk step to delete'
start = idx
while not re.match(r'^\s*- ', lines[start]):
    start -= 1
end = idx + 1
while end < len(lines) and not re.match(r'^\s*- ', lines[end]):
    end += 1
open(p, 'w').write(''.join(lines[:start] + lines[end:]))
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
mut_bt7() { python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
mark = '$(bash scripts/forgejo-container-detect.sh detect)'
assert mark in t, 'no detector call to replace'
inline = ('$(printf \'%s\\n\' $MANUAL_CONTAINERS | tr \', \' \'\\n\\n\' '
          '| { grep -E \'^[a-z0-9]+(-[a-z0-9]+)*$\' || true; } '
          '| while IFS= read -r n; do { [ -f "containers/$n/Dockerfile" ] && printf \'%s\\n\' "$n"; } || true; done '
          '| sort -u | awk \'BEGIN{printf "["} NR>1{printf ","} {printf "\\"%s\\"", $0} END{printf "]\\n"}\')')
open(p, 'w').write(t.replace(mark, inline, 1))
PY
}
mut_bt8() { python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
m = re.search(r'(?m)^on:\s*$', t) or re.search(r'(?m)^true:\s*$', t)
assert m, 'no on: mapping line to arm'
ins = m.end() + 1
open(p, 'w').write(t[:ins] + '  push:\n    branches: [main]\n' + t[ins:])
PY
}
mut_bt9() { python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
guard = """          if [ -z "${MANUAL_CONTAINERS//[[:space:]]/}" ]; then
            echo 'empty dispatch list is rejected' >&2
            exit 1
          fi
"""
m = re.search(r'(?m)^([ \t]*)[A-Za-z_][A-Za-z0-9_]*=\$\(bash scripts/forgejo-container-detect\.sh detect\)\s*$', t)
assert m, 'no standalone detect assignment to guard'
t = t[:m.start()] + guard + t[m.start():]
t2, n = re.subn(r'(?i)(empty[^\n]{0,60}?)(nothing|no-op|no op)', r'\1rejected', t)
assert n >= 1, 'no empty-no-op law wording to flip'
open(p, 'w').write(t2)
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

leg_bt1()  { probe bt1  mut_bt1  b2   ''        'runs-on flipped to the baked ubuntu-24.04 (the paradox via a schedulable-but-unpublished label)'; }
leg_bt2()  { probe bt2  mut_bt2  b3   ''        'the null-widen clause added to every job guard (the dev-mints-calendar hazard P3 rejected)'; }
leg_bt3()  { probe bt3  mut_bt3  b5   ''        'the ghcr/own push chains swapped (the gap would land on the pinned side)'; }
leg_bt4()  { probe bt4  mut_bt4  b5   ''        'the ghcr-side walk block deleted (N published over a taken ghcr tag)'; }
leg_bt5()  { probe bt5  mut_bt5  'b3 b6' ''     'the instance host literal inserted in a comment (g1 counts comments; the b3/b6 re-pin must too)'; }
leg_bt6()  { probe bt6  mut_bt6  b6   ''        'a peer push arm with vars.FORGE_PUSH_TOKEN_DEV-era credentials added (the NO-PEER ruling own teeth)'; }
leg_bt7()  { probe bt7  mut_bt7  b7   b8        'the shipped detector call replaced by an inline name filter (P6 reuse broken; b8 tolerated as the behavior twin)'; }
leg_bt8()  { probe bt8  mut_bt8  b1   ''        'a live push: trigger armed inside on: (the double-publish P1 rejected)'; }
leg_bt9()  { probe bt9  mut_bt9  'b1 b8' ''     'the empty dispatch list made fatal and the law wording flipped (b8 shape + b1 wording pin, per C01)'; }
leg_bt10() { probe bt10 mut_bt10 b2   'b3 b6'   'runs-on pointed at the instance calendar ref (the exact paradox re-entry: an image this lane has not yet minted)'; }

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
