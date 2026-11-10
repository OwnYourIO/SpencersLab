#!/usr/bin/env bash
# cf-135 C02 contract suite (2026/2026-11-cf-135-feat-renovate-forgejo,
# chunks/C02.md "## Tests"): the static shape of .forgejo/workflows/renovate.yaml,
# the Forgejo-hosted Renovate runner. Model: tests/services/forgejo-main-sync.sh.
#
# What the legs bind, with the ruling behind each:
#  - t2: schedule + workflow_dispatch only — schedules fire from the default
#    branch alone, so branch testing rides the dispatch; a push trigger would
#    run a full Renovate pass on every push (DECISIONS D6).
#  - t3: the dev-stage gate — exactly one job guarded vars.ROLE == 'dev';
#    an unset ROLE fires nothing (same fail-safe class as main-sync), and the
#    guard's textual reach is capped at the if: and the diag echo so instance
#    identity stays in prose-free shape (DECISIONS D1/Q1).
#  - t4/m6-pair: immutable full-patch image tag with NO "# renovate:"
#    annotation anywhere — the native github-actions manager extracts the
#    container image line (dist extract.js, probe of record 2026-11-10); an
#    annotation plus the broad YAML legs would double-match (DECISIONS D13).
#  - t5: credentials and instance identity come ONLY from contexts and secret
#    refs, so the file is identical-safe on both forges (cf-119 convention).
#  - t6/t7: zero uses: steps — the actions mirror's inventory beyond
#    actions/checkout is unproven and Renovate self-clones with its token
#    (DECISIONS D8); t7 doubles as the accepted-churn tripwire: merge a
#    stranded ubuntu-26.04 label bump anyway and this leg reddens for the next
#    agent touching the file (DECISIONS D12).
#  - t8: the ruling-consistency pair against renovate.json — exactly ONE
#    manager claims the workflow's pins (pairs with forgejo-move-config.sh).
#
# t9 is the only network leg and it is OFF by default: FORGEJO_RENOVATE_PROBE=1
# opts into a live --platform=local --dry-run=lookup run of the pinned CLI,
# grepping the DEBUG "packageFiles with updates" payload for the native
# extraction. Grep shapes per FRICTION 2026-11-10: there is NO "Extracted"
# INFO line, and the log must never be grepped for "duplicate" — renovate.json's
# own descriptions contain that literal text. Like dev-forgejo-runner.sh t4, the
# leg gates on log content, not exit code: the pinned CLI exits non-zero on an
# unsupported node even after a successful scan.
#
# pyyaml binds the trigger-leg shape: YAML 1.1 resolves the bare `on:` key to
# boolean True, so the trigger block is doc.get(True) or doc.get('on');
# asserting on the string key 'on' alone would redden a correct file.
#
# Run from anywhere in the worktree:
#   bash tests/services/forgejo-renovate.sh
#   FORGEJO_RENOVATE_PROBE=1 bash tests/services/forgejo-renovate.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF=".forgejo/workflows/renovate.yaml"
# The t8 consistency pair reads the repo config; the override convention of
# tests/renovate/* also lets the pair run against a simulated final config.
RENOVATE="${RENOVATE_CONFIG:-renovate.json}"
# The UA6 infra flip is exactly two edits: this constant and the workflow if:.
GUARD="vars.ROLE == 'dev'"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

# --- t1: existence + YAML parse ------------------------------------------------
[ -f "$WF" ] || fail "t1: $WF does not exist (C02 task 1: author the workflow)"
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$WF" \
  || fail "t1: $WF does not parse as YAML"
ok "t1: $WF exists and parses as YAML"

# --- t2 [AC1]: triggers exactly schedule + workflow_dispatch ---------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
trig = doc.get(True) or doc.get('on')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t2: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(trig, dict), 'no top-level on: mapping')
# The exact key set is also the ban on a push trigger (DECISIONS D6).
need(set(trig) == {'schedule', 'workflow_dispatch'},
     f'on: keys are {sorted(map(str, trig))}, expected exactly schedule + workflow_dispatch')
sched = trig['schedule']
need(isinstance(sched, list) and len(sched) == 1,
     f'schedule is {sched!r}, expected a list of exactly one entry')
entry = sched[0]
need(isinstance(entry, dict) and set(entry) == {'cron'},
     f'schedule entry is {entry!r}, expected a mapping whose only key is cron')
need(isinstance(entry['cron'], str) and entry['cron'] == '17 6 * * *',
     f"cron is {entry['cron']!r}, expected the quoted 5-field string '17 6 * * *'")
PY
then
  fail "t2: see the t2 detail above"
fi
ok "t2: on: is exactly one cron-quoted UTC schedule plus workflow_dispatch, no push"

# --- t3 [AC2]: one dev-gated job, instance identity stays in contexts ------------
if ! python3 - "$WF" "$GUARD" <<'PY'
import sys, yaml

raw = open(sys.argv[1]).read()
GUARD = sys.argv[2]
jobs = (yaml.safe_load(raw) or {}).get('jobs')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t3: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(jobs, dict), 'no jobs: mapping')
need(set(jobs) == {'renovate'}, f'jobs keys are {sorted(jobs)}, expected exactly renovate')
job = jobs['renovate'] or {}
need(job.get('if') == GUARD,
     f"jobs.renovate.if is {job.get('if')!r}, expected exactly {GUARD!r}")
# The runner's configured ceiling (charts/forgejo-runner timeout: 30m) bounds
# the job; a workflow-side timeout-minutes would restate it (C02 task).
need('timeout-minutes' not in job,
     'jobs.renovate carries timeout-minutes — the lab runner already caps jobs at 30m')
need('forgejo.server_url' not in raw,
     'forgejo.server_url appears — instance detection is retired in favour of the ROLE gate')
# AC2 caps the guard's textual reach: a comment or second job could read like
# a gate the parsed doc does not carry.
for line in raw.splitlines():
    if 'vars.ROLE' in line:
        s = line.strip()
        need((s.startswith('if:') and GUARD in s) or '${{ vars.ROLE }}' in s,
             f'vars.ROLE appears outside the job if: guard and the diag echo: {s!r}')
PY
then
  fail "t3: see the t3 detail above"
fi
ok "t3: exactly one job renovate guarded on $GUARD; no timeout-minutes, no server_url, guard text scoped to if:+echo"

# --- t4 [AC3]: immutable tag, zero renovate annotations --------------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
doc = yaml.safe_load(raw)
job = (doc.get('jobs') or {}).get('renovate') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t4: {msg}', file=sys.stderr)
        sys.exit(1)


image = (job.get('container') or {}).get('image')
need(isinstance(image, str)
     and re.fullmatch(r'ghcr\.io/renovatebot/renovate:\d+\.\d+\.\d+', image) is not None,
     f'container.image is {image!r}, expected ghcr.io/renovatebot/renovate:<x.y.z> — '
     'a full-patch immutable tag (floating tags stick at first-pull forever on the act runner)')
anns = [l for l in raw.splitlines() if re.search(r'#\s*renovate:', l)]
need(not anns,
     f'{len(anns)} "# renovate:" annotation line(s) file-wide — the native github-actions '
     'manager needs none and one would double-match the image line (DECISIONS D13)')
PY
then
  fail "t4: see the t4 detail above"
fi
ok "t4: container image is an immutable full-patch tag and the file carries no renovate annotation"

# --- t5 [AC4]: env wiring exact, secrets once, no host literals -------------------
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
doc = yaml.safe_load(raw)
job = (doc.get('jobs') or {}).get('renovate') or {}

EXPECTED = {
    'LOG_LEVEL': 'info',
    'RENOVATE_PLATFORM': 'forgejo',
    'RENOVATE_ENDPOINT': '${{ github.server_url }}',
    'RENOVATE_REPOSITORIES': '${{ github.repository }}',
    'RENOVATE_TOKEN': '${{ secrets.RENOVATE_TOKEN }}',
    'RENOVATE_GITHUB_COM_TOKEN': '${{ secrets.RENOVATE_GITHUB_COM_TOKEN }}',
}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


env = job.get('env')
need(isinstance(env, dict), 'jobs.renovate has no env: mapping')
need(set(env) == set(EXPECTED),
     f'env keys are {sorted(env)}, expected exactly {sorted(EXPECTED)}')
for key, value in EXPECTED.items():
    need(env.get(key) == value, f'env.{key} is {env.get(key)!r}, expected {value!r}')
for key in ('secrets.RENOVATE_TOKEN', 'secrets.RENOVATE_GITHUB_COM_TOKEN'):
    # Boundary-anchored like forgejo-main-sync.sh t5: an extended key name
    # (…TOKENX) must not count as an occurrence of the original.
    n = len(re.findall(re.escape(key) + r'(?![0-9A-Za-z_])', raw))
    need(n == 1, f'{key} occurs {n} times file-wide, expected exactly once')
reserved = re.findall(r'(?:secrets|vars)\.((?:GITHUB|FORGEJO)[A-Za-z0-9_]*)', raw)
need(not reserved, f'reserved-prefix secret/var reference(s): {", ".join(reserved)}')
for host in ('git.scifi.farm', 'git.spencerslab.com', 'github.com/'):
    need(host not in raw,
         f'host literal {host!r} in the file — the workflow stays instance-neutral (contexts + secrets only)')
off_image = [l for l in raw.splitlines()
             if 'ghcr.io' in l
             and not re.match(r'^\s+image: ghcr\.io/renovatebot/renovate:\d+\.\d+\.\d+$', l)]
need(not off_image,
     f'ghcr.io appears outside the container image line: {off_image}')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: six exact env keys, each secret ref once, no reserved-prefix refs, no host literals, ghcr.io only as the image"

# --- t6 [AC5]: two run-only steps, fail-fast, PATH proof -------------------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
job = (doc.get('jobs') or {}).get('renovate') or {}
steps = job.get('steps')


def need(cond, msg):
    if not cond:
        print(f'FAIL: t6: {msg}', file=sys.stderr)
        sys.exit(1)


need(isinstance(steps, list) and len(steps) == 2,
     f'steps are {steps!r}, expected exactly two (diag + renovate)')
for s in steps:
    need(isinstance(s, dict), f'step {s!r} is not a mapping')
    # Zero uses: is runner-safe by design: the actions mirror carries no
    # proven inventory beyond actions/checkout and Renovate clones/pushes with
    # its own token (DECISIONS D8).
    need('uses' not in s, f'step {s.get("name")!r} has a uses: key (mirror inventory beyond actions/checkout is unproven)')
    run = s.get('run')
    need(isinstance(run, str) and run.lstrip().startswith('set -euo pipefail'),
         f'step {s.get("name")!r} run block does not begin with set -euo pipefail')
need('renovate --version' in steps[0]['run'],
     'the first (diag) step does not run renovate --version — the cheap PATH proof (U4)')
need(any(l.strip() == 'renovate' for l in steps[1]['run'].splitlines()),
     'the second step does not invoke renovate as a bare command line')
PY
then
  fail "t6: see the t6 detail above"
fi
ok "t6: two run-only steps (no uses:), both fail-fast, diag proves renovate --version"

# --- t7 [AC5/D12]: lab-runner label whitelist — the churn tripwire ----------------
if ! python3 - "$WF" <<'PY'
import sys, yaml

# The five labels both lab runners advertise (charts/forgejo-runner
# values.yaml). The native github-actions manager PRs ubuntu-24.04 bumps to
# labels no runner carries (ubuntu-26.04, DECISIONS D12/F11); if one is ever
# merged, this leg reddens before the next agent touches the file.
LABELS = {'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'docker', 'node22'}
jobs = (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or {}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t7: {msg}', file=sys.stderr)
        sys.exit(1)


for name, job in jobs.items():
    label = (job or {}).get('runs-on')
    need(label in LABELS, f'{name}.runs-on is {label!r}, not one of {sorted(LABELS)}')
PY
then
  fail "t7: see the t7 detail above"
fi
ok "t7: every job runs on an advertised lab runner label (accepted-churn tripwire)"

# --- t8 [AC6]: ruling consistency against renovate.json --------------------------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))
rules = cfg.get('packageRules') or []
legs = cfg.get('customManagers') or []


def leg_texts(leg):
    out = []
    for field in ('matchStrings', 'depNameTemplate'):
        v = leg.get(field)
        if isinstance(v, str):
            out.append(v)
        elif isinstance(v, list):
            out.extend(x for x in v if isinstance(x, str))
    return out


def need(cond, msg):
    if not cond:
        print(f'FAIL: t8: {msg}', file=sys.stderr)
        sys.exit(1)


hits = [i for i, r in enumerate(rules)
        if isinstance(r, dict) and 'github-actions' in (r.get('matchManagers') or [])]
need(not hits, f'packageRules {hits} scope github-actions — with the workflow live that would '
     'suppress its own self-update or contain the accepted churn (DECISIONS D12)')
bot_hits = [i for i, leg in enumerate(legs)
            if isinstance(leg, dict) and any('renovatebot' in t for t in leg_texts(leg))]
need(not bot_hits,
     f'customManagers legs {bot_hits} mention renovatebot — two managers claiming the image '
     'line is the double-match the owner ruling rejected (DECISIONS D13)')
need(len(rules) == 9, f'packageRules has {len(rules)} entries, expected 9 (no-net-additions invariant)')
need(len(legs) == 13, f'customManagers has {len(legs)} legs, expected 13 (no-net-additions invariant)')
PY
then
  fail "t8: see the t8 detail above"
fi
ok "t8: renovate.json pairs with the workflow — exactly one manager (native github-actions) claims its pins"

# --- t9 [opt-in]: live native-extraction probe, default OFF ------------------------
if [ "${FORGEJO_RENOVATE_PROBE:-0}" != "1" ]; then
  skip "t9: LIVE PROBE SKIPPED — default-OFF network leg; opt in with FORGEJO_RENOVATE_PROBE=1 (proves the native github-actions manager extracts the image pin)"
elif ! command -v npx >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
  skip "t9: node/npx not available; the live extraction probe was not run"
else
  probe_dir="$(mktemp -d /tmp/opencode/forgejo-renovate-probe.XXXXXX)"
  probe_log="$probe_dir/dry-run.log"
  rc=0
  ( LOG_LEVEL=debug timeout 300 npx -y renovate@44.181.5 \
      --platform=local --dry-run=lookup >"$probe_log" 2>&1 ) || rc=$?
  if [ "$rc" -eq 124 ]; then
    skip "t9: the live probe timed out at 300s (network conditions — log kept at $probe_log)"
  elif ! grep -q 'renovateVersion' "$probe_log"; then
    skip "t9: the bundled renovate CLI did not start (npx fetch failed? log kept at $probe_log)"
  else
    # Needles follow the real DEBUG payload shape (probe of record
    # /tmp/opencode/cf135-q3-probe): the github-actions grouping key, the
    # packageFile line, and the extracted dep — no "Extracted" INFO line
    # exists to grep for.
    for needle in \
      '"github-actions": [' \
      '"packageFile": ".forgejo/workflows/renovate.yaml"' \
      '"depName": "ghcr.io/renovatebot/renovate"' \
      '"depType": "container"'; do
      grep -qF -- "$needle" "$probe_log" ||
        fail "t9: the probe log (kept at $probe_log) shows no $needle — the native github-actions manager did not claim the workflow image pin (grep shapes: FRICTION 2026-11-10)"
    done
    ok "t9: live probe — github-actions extracted ghcr.io/renovatebot/renovate (depType container) from $WF"
  fi
fi

printf 'PASS: forgejo-renovate checks (%d ok)\n' "$checks"
