#!/usr/bin/env bash
# cf-135 C01 + C03 contract suite (2026/2026-11-cf-135-feat-renovate-forgejo,
# chunks/C01.md "## Tests" + rework-round-2 chunks/C03.md "## Tests"): pins
# the renovate.json side of the Renovate-to-Forgejo move — the card's
# limit-removal ask as two zeros, the owner's Q3 ruling that the config gains
# NO containment rule and NO self-update leg, and the delta round's EXACTLY
# two recovery keys with their value pins.
#
# Why the pins look picky, and must stay:
#  - m2 fails on key ABSENCE, not only a wrong value: deleting prHourlyLimit/
#    prConcurrentLimit silently restores the built-in 2/10 (DECISIONS D5), so
#    only present-and-0 is "no limit".
#  - m3/m4/m5 are the ruling itself (DECISIONS D12/D13/D14): the native
#    github-actions manager tracks C02's workflow image line, so any
#    containment packageRule or renovatebot customManager leg would
#    re-introduce what the owner rejected — a later round reddens here, and
#    the fix is the edit's absence, not the test.
#  - m5's keyset carries C03's two delta keys (constraints, gitIgnoredAuthors)
#    and nothing else: the recovery round's config surface is EXACTLY those
#    keys, so any other arrival or removal means a ruling was bypassed
#    through another door.
#  - m7/m8 are the delta's value pins (DECISIONS D17/D18, rework round 2):
#    gitIgnoredAuthors frees the edited-branch guard for the orphaned
#    pipeline-bot commits, and a SINGLE exact constraints.helm value is what
#    short-circuits the containerbase resolver before its api.github.com hop —
#    extra entries in either value change that behaviour, hence structural
#    equality, not membership. m8 binds the pin to the coder-workspace
#    HELM_VERSION ARG so a bump PR cannot silently stale one side (R3 §D.1).
#  - m6 skips while the workflow is absent so C01 and C02 stay chunk-order
#    independent; once the file exists the pin binds.
#
# AC trace: m1[precondition] m2[AC1] m3[AC2/D12] m4[AC2/D13] m5[AC2/D14]
# m6[C02 native-shape pin, D4 immutable tag] m7[C03 AC1/D17+D18 values]
# m8[C03 AC6/D18 ARG parity].
#
# Purely static — no network, no live forge; python3 parses the JSON per leg
# (house shape of kubernetes-mcp-version-floor.sh / forgejo-main-sync.sh).
#
# Usage (from anywhere in the worktree):
#   bash tests/renovate/forgejo-move-config.sh
#   RENOVATE_CONFIG=<abs path> bash tests/renovate/forgejo-move-config.sh
# RENOVATE_CONFIG defaults to the repo's renovate.json (the dockerfile-pins.sh
# override convention) and runs the contract against a simulated final config
# before dev edits the file.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RENOVATE="${RENOVATE_CONFIG:-renovate.json}"
WF=".forgejo/workflows/renovate.yaml"

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

# --- m1: existence + JSON validity --------------------------------------------
[ -f "$RENOVATE" ] || fail "m1: $RENOVATE does not exist"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$RENOVATE" \
  || fail "m1: $RENOVATE does not parse as JSON"
ok "m1: $RENOVATE exists and parses as JSON"

# --- m2 [AC1]: the two limit zeros ---------------------------------------------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))


def need(cond, msg):
    if not cond:
        print(f'FAIL: m2: {msg}', file=sys.stderr)
        sys.exit(1)


for key in ('prHourlyLimit', 'prConcurrentLimit'):
    need(key in cfg,
         f'{key} is absent — the built-in default ({2 if key == "prHourlyLimit" else 10}) '
         'keeps limiting PRs; the card ask is the explicit value 0')
    v = cfg[key]
    # bool is excluded because Python compares False == 0: a JSON false would
    # otherwise satisfy the limit check.
    need(isinstance(v, int) and not isinstance(v, bool) and v == 0,
         f'{key} is {v!r}, expected the integer 0')
PY
then
  fail "m2: see the m2 detail above"
fi
ok "m2: prHourlyLimit and prConcurrentLimit are present with the integer value 0"

# --- m3 [AC2/D12]: ruling pin — no github-actions containment ------------------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

rules = json.load(open(sys.argv[1])).get('packageRules') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: m3: {msg}', file=sys.stderr)
        sys.exit(1)


hits = [i for i, r in enumerate(rules)
        if isinstance(r, dict) and 'github-actions' in (r.get('matchManagers') or [])]
need(not hits,
     f'packageRules {hits} scope the github-actions manager — the owner ruled NO '
     '.forgejo/** containment (DECISIONS D12); the accepted label/uses churn is '
     'guarded by the contract suites (t7 legs), not by config')
PY
then
  fail "m3: see the m3 detail above"
fi
ok "m3: no packageRule disables or scopes the github-actions manager (the Q3 override holds)"

# --- m4 [AC2/D13]: ruling pin — no renovatebot self-update leg -----------------
# Scopes the renovatebot grep to matchStrings/depNameTemplate only: the broad
# Grafana /\.ya?ml$/ leg merely annotation-matches YAML files and is not a
# claimant on the workflow image line.
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

legs = json.load(open(sys.argv[1])).get('customManagers') or []


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
        print(f'FAIL: m4: {msg}', file=sys.stderr)
        sys.exit(1)


hits = [i for i, leg in enumerate(legs)
        if isinstance(leg, dict) and any('renovatebot' in t for t in leg_texts(leg))]
need(not hits,
     f'customManagers legs {hits} carry "renovatebot" in matchStrings/depNameTemplate — '
     'the native github-actions manager owns the workflow image line alone; a regex leg '
     'on it double-matches (DECISIONS D13)')
PY
then
  fail "m4: see the m4 detail above"
fi
ok "m4: no customManager leg claims the workflow's renovate image line (no double-match claimant)"

# --- m5 [AC2/D14]: counts + immutables containment ------------------------------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))

# Config keyset: main's 11 at the rework-round-2 base plus C03's two delta
# keys (D17 gitIgnoredAuthors, D18 constraints). The ticket-pair's whole
# config surface is these plus the m2 values, so any other key appearing or
# vanishing means a ruling was bypassed through another door.
KEYS = {
    '$schema', 'extends', 'timezone', 'ignoreTests', 'labels',
    'prHourlyLimit', 'prConcurrentLimit', 'semanticCommits',
    'customManagers', 'customDatasources', 'packageRules',
    'constraints', 'gitIgnoredAuthors',
}
rules = cfg.get('packageRules') or []
legs = cfg.get('customManagers') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: m5: {msg}', file=sys.stderr)
        sys.exit(1)


need(set(cfg) == KEYS,
     f'top-level keys are {sorted(map(str, cfg))}, expected exactly {sorted(KEYS)}')
# cf-135's D14 "no rule lands" holds at its own 9; cf-6's calendar
# packageRule (landed on this branch by run -0) is the 10th, re-pinned by
# cf-6 run -2's C02 ruling, and run -4's alpine/helm v3 hold (C01 AC6) is
# the 11th — the count re-pin lands in the same commit as the rule
# (pair-whole law).
need(len(rules) == 11, f'packageRules has {len(rules)} entries, expected 11 (cf-135 D14 stays true at 9 — cf-6\'s calendar rule on this branch is the 10th and the run -4 alpine/helm hold is the 11th)')
need(len(legs) == 13, f'customManagers has {len(legs)} legs, expected 13 (D14: no leg lands)')
need(cfg.get('$schema') == 'https://docs.renovatebot.com/renovate-schema.json',
     f'$schema is {cfg.get("$schema")!r}')
need(cfg.get('extends') == ['config:recommended'],
     f'extends is {cfg.get("extends")!r}, expected ["config:recommended"]')
need(cfg.get('timezone') == 'America/Denver', f'timezone is {cfg.get("timezone")!r}')
need(cfg.get('ignoreTests') is True,
     f'ignoreTests is {cfg.get("ignoreTests")!r} — it stays load-bearing for the four '
     'automerge schedules while Forgejo PRs run no CI (DECISIONS D7)')
need(cfg.get('labels') == ['dependencies'], f'labels is {cfg.get("labels")!r}')
need(cfg.get('semanticCommits') == 'disabled', f'semanticCommits is {cfg.get("semanticCommits")!r}')
PY
then
  fail "m5: see the m5 detail above"
fi
ok "m5: 11 packageRules / 13 customManager legs and the pinned 13-key top-level keyset with every immutable value intact"

# --- m6: workflow image line native shape (order-tolerant) ----------------------
if [ ! -f "$WF" ]; then
  skip "m6: $WF not present yet — the leg binds as soon as C02 lands the file (C01 may land first)"
elif ! python3 - "$WF" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()


def need(cond, msg):
    if not cond:
        print(f'FAIL: m6: {msg}', file=sys.stderr)
        sys.exit(1)


img = [(i, l) for i, l in enumerate(lines) if re.match(r'^\s+image:', l)]
need(len(img) == 1, f'expected exactly one image: line in {sys.argv[1]}, found {len(img)}')
i, line = img[0]
# The end-of-line anchor is deliberate: only a tag-terminated line is a
# docker-datasource bump target, so the digest comment must sit on its own
# line rather than trailing the tag (C02 task).
need(re.match(r'^\s+image: ghcr\.io/renovatebot/renovate:\d+\.\d+\.\d+$', line),
     f'image line is {line!r}, expected "image: ghcr.io/renovatebot/renovate:<x.y.z>" '
     'ending the line — full-patch immutable tag, no latest, no trailing comment')
if i > 0:
    need(not re.match(r'^\s*#\s*renovate:', lines[i - 1]),
         f'the line above image: is a "# renovate:" annotation ({lines[i - 1]!r}) — the '
         'native github-actions manager extracts this line without one (DECISIONS D13)')
PY
then
  fail "m6: see the m6 detail above"
else
  ok "m6: workflow image line is the unannotated immutable full-patch tag the native manager bumps"
fi

# --- m7 [C03 AC1/D17/D18]: the delta keys' exact values --------------------------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))


def need(cond, msg):
    if not cond:
        print(f'FAIL: m7: {msg}', file=sys.stderr)
        sys.exit(1)


# Exact dict/list equality, not membership: a second constraint tool or a
# second ignored author changes what the resolver short-circuits (D18) and what
# the edited-branch guard accepts (D17 pairing law: accepted set =
# {stamp email} + this list, nothing more).
need(cfg.get('constraints') == {'helm': '3.22.1'},
     f'constraints is {cfg.get("constraints")!r}, expected exactly {{"helm": "3.22.1"}}')
need(cfg.get('gitIgnoredAuthors') == ['bot-and-reviewed@spencerslab.com'],
     f'gitIgnoredAuthors is {cfg.get("gitIgnoredAuthors")!r}, expected exactly '
     '["bot-and-reviewed@spencerslab.com"]')
PY
then
  fail "m7: see the m7 detail above"
fi
ok "m7: constraints.helm and gitIgnoredAuthors carry the D17/D18 values byte-exact"

# --- m8 [C03 AC6/D18]: constraints.helm <-> coder-workspace HELM_VERSION parity --
# Parity is read live from both surfaces: the pin follows the ARG (a bump of
# one without the other is the R3 §D.1 drift knob this leg exists to redden).
if ! python3 - "$RENOVATE" containers/coder-workspace/Dockerfile <<'PY'
import json, re, sys

cfg = json.load(open(sys.argv[1]))
dockerfile = sys.argv[2]


def need(cond, msg):
    if not cond:
        print(f'FAIL: m8: {msg}', file=sys.stderr)
        sys.exit(1)


m = re.search(r'(?m)^ARG\s+HELM_VERSION=(\S+)\s*$', open(dockerfile).read())
need(m, f'{dockerfile} carries no "ARG HELM_VERSION=<value>" line — the pair law lost its partner')
arg = m.group(1)
want = arg[1:] if arg.startswith('v') else arg
helm = (cfg.get('constraints') or {}).get('helm')
need(helm is not None,
     f'constraints is {cfg.get("constraints")!r} — no helm entry to compare with HELM_VERSION={arg!r}')
need(helm == want,
     f'constraints.helm {helm!r} != HELM_VERSION {arg!r} minus its v — move both in one change')
PY
then
  fail "m8: see the m8 detail above"
fi
ok "m8: constraints.helm equals the coder-workspace HELM_VERSION ARG (v stripped) — one helm v3 line on both surfaces"

printf 'PASS: forgejo-move-config checks (%d ok)\n' "$checks"
