#!/usr/bin/env bash
# cf-6 C02 contract suite (2026/2026-11-cf-6-feat-forgejo-container-builds-3,
# chunks/C02.md "## Tests" + the ticket's test directive): the card-134
# pre-merge leg — the plain-image customManager's 3rd managerFilePatterns
# entry exposing the top-level services/<category>/<env>/values.yaml pin
# lines, so the one-time v84/v162 bump becomes a Renovate PR after the first
# post-merge forge build mints 26.11.1 (owner leg A) instead of a manual
# bump (owner leg B; plan "Card-134 post-merge sequence").
#
# Why the pins look picky, and must stay:
#  - v2 pins the two pre-existing patterns byte-identical: C02 is the single
#    pattern-string addition (chunk task); any other field change in the
#    plain-image manager (matchStrings/datasourceTemplate/description) would
#    change what Renovate extracts from the 16 lines the v5-v7 pins count.
#  - v3 pins the calendar packageRule (identified by its ghcr.io/ownyourio/*
#    scope, not by index — the .agents/** disable rule sits behind it)
#    byte-identical, and since run -4 also the alpine/helm hold rule: its
#    fields and its slot directly after the helm/helm hold whose law it
#    mirrors. The count literal moves only in the commit that lands a rule
#    — 10 arrived with cf-6 run -2's calendar rule, 11 arrives with this
#    run -4 hold (pair-whole law; forgejo-move-config pins the same count).
#  - v6/v7 pin the extracted line SETS (multisets: the dev and gpu
#    renovate-mcp:v84 pairs are identical (file, image) rows) — after owner
#    leg B moves the pins onto the calendar form, v6 reddens by design; the
#    fix is the ticketed re-pin, not a silent edit.
#  - The file-pattern match is the plan-verified probe shape (FRICTION
#    2026-11-16 plan-rework): the pattern's leading/trailing / delimiters are
#    stripped before re.search over the repo-relative path — passing the
#    delimited pattern raw makes the leading / demand a slash at string start
#    and fails spuriously.
#  - matchStrings and the calendar versioning carry the JS named-group
#    (?<name>) form; python re needs (?P<name> — converted at run time, never
#    duplicated here (FRICTION 2026-11-16 plan-rework, 10th-rule gotcha).
#
# AC trace: v1[AC1-json] v2[AC1-patterns] v3[AC1-rules + run-4 C01 AC6 hold]
# v4[AC2-files] v5[AC2-16-lines] v6[AC2-ownyourio-pins] v7[AC2-other-org]
# v8[AC3-behavior].
#
# Purely static — no network, no live registry. Usage (from anywhere in the
# worktree):
#   bash tests/renovate/services-values-pins.sh
#   RENOVATE_CONFIG=<abs path> bash tests/renovate/services-values-pins.sh
# RENOVATE_CONFIG defaults to the repo's renovate.json (the dockerfile-pins.sh
# override convention) and runs the contract against a simulated final config
# before dev edits the file.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RENOVATE="${RENOVATE_CONFIG:-renovate.json}"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- v1: existence + JSON validity --------------------------------------------
[ -f "$RENOVATE" ] || fail "v1: $RENOVATE does not exist"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$RENOVATE" \
  || fail "v1: $RENOVATE does not parse as JSON"
ok "v1: $RENOVATE exists and parses as JSON"

# --- v2 [AC1]: the plain-image manager — 3 patterns, nothing else moved -------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))
legs = cfg.get('customManagers') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: v2: {msg}', file=sys.stderr)
        sys.exit(1)


# The plain-image manager is identified by its description (chunk task 1);
# exactly one leg may claim it.
plain = [l for l in legs if isinstance(l, dict)
         and str(l.get('description', '')).startswith('Plain image: lines in chart/service templates')]
need(len(plain) == 1,
     f'expected exactly one plain-image customManager leg, found {len(plain)}')
plain = plain[0]

P_CHARTS = '/(^|/)charts/[^/]+/templates/[^/]+\\.ya?ml$/'
P_SERVICES_TEMPLATES = '/(^|/)services/[^/]+/[^/]+/templates/[^/]+\\.ya?ml$/'
P_SERVICES_VALUES = '/(^|/)services/[^/]+/[^/]+/values\\.ya?ml$/'
# C02 appends the top-level values pattern as the 3rd entry; the first two
# stay byte-identical (chunk task 1), so the order is part of the pin.
need(plain.get('managerFilePatterns') == [P_CHARTS, P_SERVICES_TEMPLATES, P_SERVICES_VALUES],
     f'managerFilePatterns is {plain.get("managerFilePatterns")!r}, expected the two pre-existing '
     'patterns byte-identical plus the new 3rd entry '
     f'{P_SERVICES_VALUES!r} (the card-134 pre-merge leg)')
# The rest of the leg is C02's do-not-touch list (chunk task 1: NO other
# field in renovate.json changes).
need(plain.get('customType') == 'regex',
     f'customType is {plain.get("customType")!r}, expected "regex"')
need(plain.get('description') ==
     'Plain image: lines in chart/service templates (ToolHive MCPServer specs, raw Deployments). '
     'Helm-templated and commented lines don\'t match; untagged/latest images yield no updates.',
     f'description is {plain.get("description")!r} — the pre-C02 text must stay byte-identical')
need(plain.get('matchStrings') ==
     ['(^|\\n)[ \\t]*image:[ \\t]+(?<depName>[A-Za-z0-9._/-]+):(?<currentValue>[A-Za-z0-9._-]+)'],
     f'matchStrings is {plain.get("matchStrings")!r} — C02 touches no matchStrings (chunk do-not-touch)')
need(plain.get('datasourceTemplate') == 'docker',
     f'datasourceTemplate is {plain.get("datasourceTemplate")!r}, expected "docker"')
# The new pattern may live in exactly one managerFilePatterns list entry repo-wide.
all_patterns = [p for l in legs if isinstance(l, dict)
               for p in (l.get('managerFilePatterns') or [])]
need(all_patterns.count(P_SERVICES_VALUES) == 1,
     f'the new top-level values pattern occurs {all_patterns.count(P_SERVICES_VALUES)}x across all '
     'customManager legs, expected exactly 1 (one pattern string added, nothing else)')
PY
then
  fail "v2: see the v2 detail above"
fi
ok "v2: plain-image customManager has exactly 3 managerFilePatterns (two pre-existing byte-identical + the top-level values pattern) and no other field moved"

# --- v3 [AC1 + C01 AC6]: 11 packageRules, the hold at index 5 ---------------
if ! python3 - "$RENOVATE" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))
rules = cfg.get('packageRules') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: v3: {msg}', file=sys.stderr)
        sys.exit(1)


need(len(rules) == 11,
     f"packageRules has {len(rules)} entries, expected 11 (run -4's docker.io/alpine/helm v3 hold is the 11th, C01 AC6; this re-pin and the rule land in the same commit — pair-whole law)")
# C01 AC6 position + field pin: exactly one rule scopes the bake's helm
# stage image, sitting directly after the helm/helm hold whose law it
# mirrors so the two v3-line holds read as one decision. The description is
# free prose, but it must name the parent hold.
holds = [i for i, r in enumerate(rules) if r.get('matchPackageNames') == ['docker.io/alpine/helm']]
need(len(holds) == 1,
     f'slots {holds} scope docker.io/alpine/helm, expected exactly one (C01 AC6: one hold rule — the stage FROM line itself is tracked by the built-in dockerfile manager and carries no annotation)')
need(holds[0] == 5,
     f'the docker.io/alpine/helm hold sits at index {holds[0]}, expected 5 — directly after the helm/helm hold (C01 AC6 position law)')
hold = rules[5]
need(hold.get('matchDatasources') == ['docker'],
     f'index-5 hold matchDatasources is {hold.get("matchDatasources")!r}, expected ["docker"] — the docker datasource names the stage image where the github-releases hold above names the release line')
need(hold.get('allowedVersions') == '/^3\\./',
     f'index-5 hold allowedVersions is {hold.get("allowedVersions")!r}, expected the slash-wrapped /^3\\./ — docker tags carry no v prefix, and a bare ^3. is not a valid semver range (the lookup-error lesson the parent rule documents)')
need('helm/helm' in (hold.get('description') or ''),
     'the index-5 hold does not name the helm/helm hold as its parent law in its description (C01 AC6)')
# Identified by scope, not index: the .agents/** disable rule sits behind the
# calendar rule in the file, so the last-by-count slot is not the calendar rule.
cal = [r for r in rules if r.get('matchPackageNames') == ['ghcr.io/ownyourio/*']]
need(len(cal) == 1,
     f'expected exactly one packageRule scoping ghcr.io/ownyourio/*, found {len(cal)}')
# Byte-identical pin of the calendar rule (JSON-space equality): C02 must not
# touch it, and leg B's bump PR must not need to either.
EXPECTED = {
    'description': 'Calendar line owns ghcr.io/ownyourio images: .forgejo/workflows/build-containers.yaml '
    'publishes them as yy.mm.N, and the docker datasource\'s default versioning ranks the legacy '
    'v<run_number> tags above every 26.x calendar tag (v162 > 26.11.1), so pins would never cross '
    'onto the calendar line. This regex versioning compares calendar tags numerically; a legacy '
    'v-pin fails the regex and the dep is a clean silent skip (invalid-version) until the one-time '
    'bump PR moves the pin onto the first calendar tag — never a downgrade PR.',
    'matchPackageNames': ['ghcr.io/ownyourio/*'],
    'matchDatasources': ['docker'],
    'versioning': 'regex:^(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)$',
}
need(cal[0] == EXPECTED,
     f'the calendar packageRule is {json.dumps(cal[0])}, expected the pre-C02 rule byte-identical: '
     f'{json.dumps(EXPECTED)}')
PY
then
  fail "v3: see the v3 detail above"
fi
ok "v3: 11 packageRules — the docker.io/alpine/helm hold exact at index 5 — and the ghcr.io/ownyourio/* calendar rule byte-identical"

# --- v4 [AC2]: the 13 top-level values files, matched by the new pattern only -
if ! python3 - "$RENOVATE" <<'PY'
import glob, json, os, re, sys

cfg = json.load(open(sys.argv[1]))
legs = cfg.get('customManagers') or []
plain = next(l for l in legs if isinstance(l, dict)
             and str(l.get('description', '')).startswith('Plain image: lines in chart/service templates'))
patterns = plain.get('managerFilePatterns') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: v4: {msg}', file=sys.stderr)
        sys.exit(1)


need(len(patterns) == 3,
     f'the plain-image manager has {len(patterns)} managerFilePatterns, expected 3 (the C02 extension not landed yet?)')
# Plan-verified probe shape (FRICTION plan-rework): strip the / delimiters
# before matching repo-relative paths.
compiled = []
for p in patterns:
    need(isinstance(p, str) and len(p) > 1 and p.startswith('/') and p.endswith('/'),
         f'file pattern {p!r} is not slash-delimited — the probe shape cannot strip it')
    compiled.append(re.compile(p[1:-1]))
new_re, old_res = compiled[2], compiled[:2]

files = sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml')))
need(len(files) == 13,
     f'found {len(files)} top-level services values files, expected 13: {files}')
unmatched = [f for f in files if not new_re.search(f)]
need(not unmatched,
     f'the new top-level values pattern does not match {unmatched}')
# Zero overlap, direction 1: no top-level file matches the templates/ patterns.
old_hits = [f for f in files if any(p.search(f) for p in old_res)]
need(not old_hits,
     f'the pre-existing templates/ patterns match top-level files {old_hits} — expected zero overlap')
# Zero overlap, direction 2: across every ya?ml file under services/ and
# charts/, nothing matches the new pattern and a templates/ pattern alike, and
# the new pattern matches no file outside the 13.
both, extra = [], []
for root in ('services', 'charts'):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ('.git', 'charts')]
        for name in filenames:
            if not name.endswith(('.yaml', '.yml')):
                continue
            path = os.path.join(dirpath, name)
            if new_re.search(path) and any(p.search(path) for p in old_res):
                both.append(path)
            if new_re.search(path) and path not in files:
                extra.append(path)
need(not both, f'the new pattern co-matches templates/ files {both} — expected disjoint scope')
need(not extra, f'the new pattern matches files outside the 13: {extra}')
PY
then
  fail "v4: see the v4 detail above"
fi
ok "v4: exactly 13 top-level values files, all matched by the 3rd pattern with zero overlap against the two pre-existing templates/ patterns (both directions)"

# --- v5 [AC2]: extraction via the manager's own matchStrings — 16 lines -------
if ! python3 - "$RENOVATE" <<'PY'
import glob, json, re, sys

cfg = json.load(open(sys.argv[1]))
legs = cfg.get('customManagers') or []
plain = next(l for l in legs if isinstance(l, dict)
             and str(l.get('description', '')).startswith('Plain image: lines in chart/service templates'))


def need(cond, msg):
    if not cond:
        print(f'FAIL: v5: {msg}', file=sys.stderr)
        sys.exit(1)


need(len(plain.get('managerFilePatterns') or []) == 3,
     'the 3rd managerFilePatterns entry is absent — the extraction contract binds once C02 lands it')
# The manager's own matchStrings (extracted at run time, JS named-group form
# converted for python re — never duplicated here).
ms = re.sub(r'\(\?<(?=\w)', '(?P<', plain['matchStrings'][0])
extract = re.compile(ms)

files = sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml')))
lines = []
for f in files:
    for m in extract.finditer(open(f).read()):
        lines.append((f, m.group('depName'), m.group('currentValue')))
need(len(lines) == 16,
     f'the extraction yields {len(lines)} image lines across the 13 files, expected exactly 16 '
     f'(7 ownyourio pins + 9 other-org): {sorted((f, d) for f, d, _ in lines)}')
PY
then
  fail "v5: see the v5 detail above"
fi
ok "v5: the manager's own matchStrings extracts exactly 16 image lines from the 13 top-level values files"

# --- v6 [AC2]: the 7 ownyourio pins — the exact EXPLORE.md §2 line set -------
if ! python3 - "$RENOVATE" <<'PY'
import glob, json, re, sys

cfg = json.load(open(sys.argv[1]))
legs = cfg.get('customManagers') or []
plain = next(l for l in legs if isinstance(l, dict)
             and str(l.get('description', '')).startswith('Plain image: lines in chart/service templates'))


def need(cond, msg):
    if not cond:
        print(f'FAIL: v6: {msg}', file=sys.stderr)
        sys.exit(1)


ms = re.sub(r'\(\?<(?=\w)', '(?P<', plain['matchStrings'][0])
extract = re.compile(ms)
files = sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml')))
own = []
for f in files:
    for m in extract.finditer(open(f).read()):
        if m.group('depName').startswith('ghcr.io/ownyourio/'):
            own.append((f, f'{m.group("depName")}:{m.group("currentValue")}'))
# Multiset pin (duplicates significant: two identical (file, image) rows per
# side for renovate-mcp:v84). The 7 lines are EXPLORE.md §2 verbatim:
# services/dev/prod L298/L332/L454, services/gpu/prod L732/L769/L912/L946.
EXPECTED = sorted([
    ('services/dev/prod/values.yaml', 'ghcr.io/ownyourio/renovate-mcp:v84'),
    ('services/dev/prod/values.yaml', 'ghcr.io/ownyourio/renovate-mcp:v84'),
    ('services/dev/prod/values.yaml', 'ghcr.io/ownyourio/wekan-mcp:v162'),
    ('services/gpu/prod/values.yaml', 'ghcr.io/ownyourio/renovate-mcp:v84'),
    ('services/gpu/prod/values.yaml', 'ghcr.io/ownyourio/renovate-mcp:v84'),
    ('services/gpu/prod/values.yaml', 'ghcr.io/ownyourio/wekan-mcp:v162'),
    ('services/gpu/prod/values.yaml', 'ghcr.io/ownyourio/wekan-mcp:v162'),
])
need(sorted(own) == EXPECTED,
     f'the ownyourio pin lines are {sorted(own)}, expected the 7 legacy pins of EXPLORE.md §2 '
     '(renovate-mcp:v84 x4 + wekan-mcp:v162 x3) — after owner leg B moves them onto the calendar '
     'form this leg reddens by design; the fix is the ticketed re-pin')
PY
then
  fail "v6: see the v6 detail above"
fi
ok "v6: the 7 ownyourio pins extract as the exact EXPLORE.md §2 lines (v84 x4 + v162 x3)"

# --- v7 [AC2]: the 9 other-org lines — exact set, none ownyourio -------------
if ! python3 - "$RENOVATE" <<'PY'
import glob, json, re, sys

cfg = json.load(open(sys.argv[1]))
legs = cfg.get('customManagers') or []
plain = next(l for l in legs if isinstance(l, dict)
             and str(l.get('description', '')).startswith('Plain image: lines in chart/service templates'))


def need(cond, msg):
    if not cond:
        print(f'FAIL: v7: {msg}', file=sys.stderr)
        sys.exit(1)


ms = re.sub(r'\(\?<(?=\w)', '(?P<', plain['matchStrings'][0])
extract = re.compile(ms)
files = sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml')))
other = []
for f in files:
    for m in extract.finditer(open(f).read()):
        dn = m.group('depName')
        if not dn.startswith('ghcr.io/ownyourio/'):
            other.append((f, f'{dn}:{m.group("currentValue")}'))
EXPECTED = sorted([
    ('services/dev/prod/values.yaml', 'isokoliuk/mcp-searxng:2.8.1'),
    ('services/dev/prod/values.yaml', 'mcr.microsoft.com/playwright/mcp:v0.0.83'),
    ('services/gpu/prod/values.yaml', 'grafana/mcp-grafana:2.1.1'),
    ('services/gpu/prod/values.yaml', 'grafana/mcp-grafana:2.1.1'),
    ('services/gpu/prod/values.yaml', 'isokoliuk/mcp-searxng:2.8.1'),
    ('services/gpu/prod/values.yaml', 'mcr.microsoft.com/playwright/mcp:v0.0.83'),
    ('services/gpu/prod/values.yaml', 'zorak1103/ha-mcp:2026.10.2'),
    ('services/gpu/prod/values.yaml', 'zorak1103/ha-mcp:2026.10.2'),
    ('services/media/prod/values.yaml', 'ghcr.io/matthisholleville/argocd-mcp:1.8.0'),
])
need(len(other) == 9, f'the extraction yields {len(other)} other-org lines, expected exactly 9')
need(sorted(other) == EXPECTED,
     f'the other-org lines are {sorted(other)}, expected the 9 pre-C02 lines (they ride '
     'Renovate\'s default docker rules — the designed trade of exposing the files, plan Risks)')
PY
then
  fail "v7: see the v7 detail above"
fi
ok "v7: exactly 9 other-org image lines extract, the exact pre-C02 set (none ownyourio)"

# --- v8 [AC3]: the 10th-rule behavior table — skip rows + the bump row -------
if ! python3 - "$RENOVATE" <<'PY'
import json, re, sys

cfg = json.load(open(sys.argv[1]))
rules = cfg.get('packageRules') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: v8: {msg}', file=sys.stderr)
        sys.exit(1)


cal = [r for r in rules if r.get('matchPackageNames') == ['ghcr.io/ownyourio/*']]
need(len(cal) == 1, f'expected exactly one ghcr.io/ownyourio/* packageRule, found {len(cal)}')
versioning = cal[0].get('versioning') or ''
need(versioning.startswith('regex:'),
     f'calendar rule versioning is {versioning!r}, expected the "regex:" form')
# The JS named-group form is not python re syntax (FRICTION plan-rework);
# convert, never duplicate.
rx = re.compile(re.sub(r'\(\?<(?=\w)', '(?P<', versioning[len('regex:'):]))
# Skip rows: the legacy v-pins and the rolling refs fail the calendar regex ->
# clean silent skip (invalid-version), never a downgrade PR.
for tag in ('v84', 'v162', 'v177', 'main', 'latest'):
    need(rx.fullmatch(tag) is None,
         f'tag {tag} matches the calendar versioning regex — the rule must fail it (clean silent '
         'skip, no downgrade PR)')
# Bump row: the calendar form is comparable -> the card-134 bump PR.
for tag in ('26.11.1', '26.11.2'):
    need(rx.fullmatch(tag) is not None,
         f'tag {tag} does not match the calendar versioning regex — the calendar form must be '
         'comparable so leg B is a Renovate bump PR')
PY
then
  fail "v8: see the v8 detail above"
fi
ok "v8: the calendar rule's behavior table holds — v84/v162/v177/main/latest fail (silent skip), 26.11.1/26.11.2 match (the bump PR)"

printf 'PASS: services-values-pins checks (%d ok)\n' "$checks"
