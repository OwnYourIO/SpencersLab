#!/usr/bin/env bash
# cf-135 C02 contract suite (2026/2026-11-cf-135-feat-renovate-forgejo,
# chunks/C02.md "## Tests"): the static shape of .forgejo/workflows/renovate.yaml,
# the Forgejo-hosted Renovate runner. Model: tests/services/forgejo-main-sync.sh.
#
# What the legs bind, with the ruling behind each:
#  - t2: schedule + workflow_dispatch only — schedules fire from the default
#    branch alone, so branch testing rides the dispatch; a push trigger would
#    run a full Renovate pass on every push (DECISIONS D6).
#  - t3: the dev-stage gate — exactly one job guarded by ROLE-list
#    membership (contains); an unset ROLE fires nothing (same fail-safe class
#    as main-sync), and the guard's textual reach is capped at the if: and the
#    diag echo so instance identity stays in prose-free shape (DECISIONS
#    D1/Q1; cf-6 run -2 migrated the shape, the reach cap did not move).
#  - t4/m6-pair: immutable full-patch image tag with NO "# renovate:"
#    annotation anywhere — the native github-actions manager extracts the
#    container image line (dist extract.js, probe of record 2026-11-10); an
#    annotation plus the broad YAML legs would double-match (DECISIONS D13).
#  - t5: credentials and instance identity come ONLY from contexts and secret
#    refs (cf-119 convention); the author stamp joins them as a
#    vars.RENOVATE_GIT_AUTHOR reference — D23: variable-not-secret (the
#    identity is public in every commit header), value minted instance-side.
#    An unset variable renders empty and degrades SILENTLY to platform /user
#    discovery, so the owner creates it before merge (UA12); the suites pin
#    the reference shape, never the value.
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
# C12 (cf-55 round 4, route F APPROVED by D49): the instance Renovate gains a
# runnable helm via the official `-full` image (helm pre-baked, global tool
# resolution — the slim tag's EACCES/ENOENT lock-regen failure is the chart
# drift's FIRST cause). Re-aims: t4's tag regex and t5's off_image line accept
# the `-full` variant; t5's EXPECTED env set grows seven keys -> eight with
# RENOVATE_BINARY_SOURCE=global (explicit, so a base-image default flip can
# never silently regress to install mode); t9's needle is UNCHANGED (the tag
# shares the depName). New t10 pins image-and-env as one PAIR — the
# install-mode regression fence. New t11 (C12 review r1 min-2) binds the
# image-line digest comment to the strict sha256:[0-9a-f]{64} shape — a
# 63-hex transcription rode through every prior leg because nothing read the
# comment. Gate posture: the one-time helm4-writes/
# helm3-builds digest cross-check is C12 DEV's pre-merge run (chunk AC1), not
# a suite leg.
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
# cf-6 run -2 (owner ruling OQ-j) migrates the guard to the repo membership
# convention; narrow-on-unset is the file's own polarity and stays — bare
# contains() on an unset var is false, so the fail-safe survives the shape.
GUARD="contains(vars.ROLE, 'dev')"

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
     and re.fullmatch(r'ghcr\.io/renovatebot/renovate:\d+\.\d+\.\d+(?:-full)?', image) is not None,
     f'container.image is {image!r}, expected ghcr.io/renovatebot/renovate:<x.y.z> (optionally the '
     '`-full` variant, C12 route F) — a full-patch immutable tag (floating tags stick at first-pull forever on the act runner)')
anns = [l for l in raw.splitlines() if re.search(r'#\s*renovate:', l)]
need(not anns,
     f'{len(anns)} "# renovate:" annotation line(s) file-wide — the native github-actions '
     'manager needs none and one would double-match the image line (DECISIONS D13)')
PY
then
  fail "t4: see the t4 detail above"
fi
ok "t4: container image is an immutable full-patch tag (slim or -full) and the file carries no renovate annotation"

# --- t5 [AC4 + C05 AC1/AC2]: env wiring exact, secret/vars refs once, no host literals -
if ! python3 - "$WF" <<'PY'
import re, sys, yaml

raw = open(sys.argv[1]).read()
doc = yaml.safe_load(raw)
job = (doc.get('jobs') or {}).get('renovate') or {}

EXPECTED = {
    # C02 (e) re-aim: LOG_LEVEL leaves the exact-value pin — it becomes the
    # vars.DEBUG-gated shape (default info per OQ7, verbose debug); the value
    # of the variable is never pinned (the suite's own law), its shape is.
    'RENOVATE_PLATFORM': 'forgejo',
    'RENOVATE_ENDPOINT': '${{ github.server_url }}',
    'RENOVATE_REPOSITORIES': '${{ github.repository }}',
    'RENOVATE_TOKEN': '${{ secrets.RENOVATE_TOKEN }}',
    'RENOVATE_GITHUB_COM_TOKEN': '${{ secrets.RENOVATE_GITHUB_COM_TOKEN }}',
    # D23: the stamp arrives as a repo-scoped Actions VARIABLE reference, never
    # a repo literal (public commit-header identity; ROLE/PUSH_URL_* lineage)
    # and never a secret. The instance-side value of record stays D21's
    # pairing-law address — Renovate <tms@spencerslab.com>, the running PAT
    # account's commit email; stamping bot-and-reviewed@ instead would DEMOTE
    # tms@ from the guard's accepted set and leave the stuck ranges locked
    # (census arithmetic, DECISIONS D21).
    'RENOVATE_GIT_AUTHOR': '${{ vars.RENOVATE_GIT_AUTHOR }}',
    # C12 route F (D49): the -full image ships its tools globally; declaring
    # the mode explicitly is the fence against a base-image default flip back
    # to install mode — the class that starved Chart.lock regeneration
    # (EACCES /opt/containerbase/data, PR #112; spawn helm ENOENT, PR #113).
    'RENOVATE_BINARY_SOURCE': 'global',
}


def need(cond, msg):
    if not cond:
        print(f'FAIL: t5: {msg}', file=sys.stderr)
        sys.exit(1)


env = job.get('env')
need(isinstance(env, dict), 'jobs.renovate has no env: mapping')
need(set(env) == set(EXPECTED) | {'LOG_LEVEL'},
     f'env keys are {sorted(env)}, expected exactly {sorted(set(EXPECTED) | {"LOG_LEVEL"})} (the eight-key law, C02 task e: no new key)')
for key, value in EXPECTED.items():
    need(env.get(key) == value, f'env.{key} is {env.get(key)!r}, expected {value!r}')
ll = str(env.get('LOG_LEVEL', ''))
need('vars.DEBUG' in ll, f'LOG_LEVEL is {ll!r} — it must reference vars.DEBUG (C02 task e: the single verbose switch; the scout\'s warn recommendation is overruled, OQ7)')
need('info' in ll, f'LOG_LEVEL is {ll!r} — the info DEFAULT literal is missing (OQ7: the default stays info)')
need('debug' in ll, f'LOG_LEVEL is {ll!r} — the debug VERBOSE literal is missing (DEBUG=true raises it)')
n = len(re.findall(r'vars\.DEBUG(?![0-9A-Za-z_])', raw))
need(n == 1, f'vars.DEBUG occurs {n} time(s) file-wide, expected exactly once (the single binding site; the variable\'s value is never pinned — the suite\'s own law, C02 task e)')
for key in ('secrets.RENOVATE_TOKEN', 'secrets.RENOVATE_GITHUB_COM_TOKEN',
            'vars.RENOVATE_GIT_AUTHOR'):
    # Boundary-anchored like forgejo-main-sync.sh t5: an extended key name
    # (…TOKENX) must not count as an occurrence of the original. D23 extends
    # the same once-file-wide law to the stamp's vars ref: the shape appears
    # at exactly one binding site.
    n = len(re.findall(re.escape(key) + r'(?![0-9A-Za-z_])', raw))
    need(n == 1, f'{key} occurs {n} times file-wide, expected exactly once')
reserved = re.findall(r'(?:secrets|vars)\.((?:GITHUB|FORGEJO)[A-Za-z0-9_]*)', raw)
need(not reserved, f'reserved-prefix secret/var reference(s): {", ".join(reserved)}')
for host in ('git.scifi.farm', 'git.spencerslab.com', 'github.com/'):
    need(host not in raw,
         f'host literal {host!r} in the file — the workflow stays instance-neutral (contexts + secrets only)')
off_image = [l for l in raw.splitlines()
             if 'ghcr.io' in l
             and not re.match(r'^\s+image: ghcr\.io/renovatebot/renovate:\d+\.\d+\.\d+(?:-full)?$', l)]
need(not off_image,
     f'ghcr.io appears outside the container image line: {off_image}')
PY
then
  fail "t5: see the t5 detail above"
fi
ok "t5: eight env keys (the other seven exact, LOG_LEVEL in the vars.DEBUG-gated info/debug shape, value never pinned), each secret/vars ref once, no reserved-prefix refs, no host literals, ghcr.io only as the image (C05 AC1/AC2; C02 task e re-aim)"

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
# 9 was the cf-135 count; cf-6's calendar packageRule (landed on this
# branch by run -0) is the 10th — re-pinned by cf-6 run -2's C02 ruling —
# and run -4's alpine/helm v3 hold (C01 AC6) is the 11th: the count
# re-pin lands in the same commit as the rule (pair-whole law).
need(len(rules) == 11, f'packageRules has {len(rules)} entries, expected 11 (9 since cf-135, the calendar rule cf-6 carries on this branch, and the run -4 alpine/helm hold)')
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

# --- t10 [C12 AC2]: -full image and global tool mode travel as ONE pair -----------
# The install-mode regression fence: the drift's first cause was a Renovate
# that CANNOT run helm — either the image lacks the tools at runtime (the
# slim tag's binarySource=install class, EACCES/ENOENT smoking guns) or the
# mode is undeclared and a future base-image default flips it back. Either
# half alone is that bug re-arming, so the leg asserts the PAIR, not two
# independent keys.
if ! python3 - "$WF" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
job = (doc.get('jobs') or {}).get('renovate') or {}
image = str((job.get('container') or {}).get('image') or '')
bs = (job.get('env') or {}).get('RENOVATE_BINARY_SOURCE')

if not image.endswith('-full'):
    print(f'FAIL: t10: container.image {image!r} does not end "-full" — the slim tag cannot execute helm in the sandbox (EACCES /opt/containerbase-data, spawn helm ENOENT: the Chart.lock drift sources, PRs #112/#113), so lock regeneration keeps failing inside the PR', file=sys.stderr)
    sys.exit(1)
if bs != 'global':
    print(f'FAIL: t10: env.RENOVATE_BINARY_SOURCE is {bs!r}, expected "global" — the -full image must DECLARE its tool mode: implicit defaults are exactly how install-mode crept in the first time (C12 route F)', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t10: see the t10 detail above"
fi
ok "t10: image is the -full variant AND RENOVATE_BINARY_SOURCE=global is declared — the pair, or neither (install-mode regression fence)"

# --- t11 [C12 review r1 min-2]: the image-line digest comment is strict-shape ------
# The 63-hex transcription slip rode through every shipped leg because nothing
# bound the comment's shape: a stale or mangled digest silently falsifies the
# chunk's implementation-time evidence (C12.md task 2 requires the comment to
# CARRY the -full tag's index digest; the review posture is "verify the digest
# comment is the -full index digest, not the slim's"). SHAPE only — no leg
# here reaches the registry (offline-suite law); verifying the token lives in
# the dev RESULT's gate transcript, not in CI.
# Posture pinned: for a -full image an accompanying digest comment is
# REQUIRED (absent => red) — C12.md AC2 ships the pair "with a fresh digest
# comment" (the slim era had the comment; the chunk REPLACES it, never drops
# it, and the review posture reads it). For any image, every sha256 token
# beside the image line must be exactly 64 lowercase hex on ONE line —
# 63/65/uppercase/wrapped forms are the transcription class this leg exists
# to catch.
if ! python3 - "$WF" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
img_i = [i for i, l in enumerate(lines) if re.match(r'^\s+image:\s*ghcr\.io/renovatebot/renovate:', l)]
if len(img_i) != 1:
    print(f'FAIL: t11: {len(img_i)} image lines found, expected exactly one (the t4/m6 anchor) — no single digest companion to bind', file=sys.stderr)
    sys.exit(1)
i = img_i[0]
image = lines[i].split(':', 1)[1].strip()

# The digest comment rides the image line: comment lines directly after it
# (the block up to the next executable key), plus the one line before.
block = [l for l in ([lines[i - 1]] if i and lines[i - 1].lstrip().startswith('#') else [])]
for l in lines[i + 1:]:
    if l.lstrip().startswith('#'):
        block.append(l)
    else:
        break

TOKEN = re.compile(r'sha256:[0-9A-Za-z]+')
BAD = re.compile(r'^sha256:[0-9a-f]{64}$')

tokens = [m.group(0) for l in block for m in TOKEN.finditer(l)]
bad = [t for t in tokens if not BAD.match(t)]
if bad:
    why = []
    for t in bad:
        h = t[len('sha256:'):]
        why.append(f'{t[:24]}... length {len(h)}' + ('' if h.islower() else ' (uppercase hex)'))
    print(f'FAIL: t11: digest comment beside the image line violates the sha256:[0-9a-f]{{64}} shape: {why} — a 63/65-hex, uppercase, or line-wrapped transcription is exactly the slip C12 review r1 caught (the 63-hex comment passed every prior leg)', file=sys.stderr)
    sys.exit(1)
if image.endswith('-full') and not tokens:
    print('FAIL: t11: the -full image carries no sha256 digest comment beside its line — C12.md AC2 ships the image+env pair WITH a fresh digest comment (the -full tag\'s manifest digest read at implementation time, replacing the stale slim-era one); without it that evidence is unverifiable', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "t11: see the t11 detail above"
fi
ok "t11: the image-line digest comment is a complete lowercase sha256:[0-9a-f]{64} on one line, present for the -full tag (shape-only — registry truth is the dev transcript's, per the offline-suite law)"

printf 'PASS: forgejo-renovate checks (%d ok)\n' "$checks"
