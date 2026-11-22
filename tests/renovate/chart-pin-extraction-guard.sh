#!/usr/bin/env bash
# cf-145 owner-followup permanent net: every ENABLED chart version pin under
# the charts: map of the top-level services values files must actually
# extract through renovate.json's "Update Charts - key as chart name"
# manager (or its "Update Charts - explicit chart field" twin for the
# chart:-field shape).
#
# Why the pins need a net:
#  - The inline `# renovate: datasource=helm registryUrl=` syntax is parsed
#    only by the baseChartVersion manager, which fileMatches appset.yaml and
#    needs the appName:/baseChartVersion: pair — a values.yaml annotation is
#    dead-on-arrival, and worse, a TRAILING comment after the version digits
#    breaks the [\d.]+-to-repository adjacency the key-as-chart-name manager
#    requires, so the pin silently stops being tracked. That orphan class
#    (6x external-secrets-bitwarden + grafana + exporter-mikrotik +
#    kube-prometheus-stack) is what this sweep removed and what g4 keeps out.
#  - The tracked shape is a bare `version: <digits>` line directly under the
#    entry key (or under a `chart:` field), with a bare `repository: <url>`
#    line below it — no trailing comment.
#  - The services values files do not parse with yaml.safe_load (shared YAML
#    anchors, e.g. dev/prod's `&port`), so pins are enumerated by a line
#    scan mirroring the adjacency the manager's own regex demands. The
#    regexes are read from renovate.json at run time, never duplicated here;
#    the JS named-group (?<name>) form is converted for python re at run
#    time, the same trick as services-values-pins.sh.
#  - Expected depName/currentValue/registryUrl triples are read from the
#    scanned lines, never pinned as literals: a Renovate bump PR edits the
#    pin in place and must keep this suite green (the pair law is the point,
#    as in chart-lock-consistency.sh k3).
#
# AC trace: g1[managers present and their file patterns cover the scanned
# files] g2[the owner's named grafana pin extracts] g3[full coverage: every
# scanned enabled version+repository trio extracts with the correct triple]
# g4[anti-pattern: no enabled version pin carries a trailing `# renovate:`
# comment].
#
# Purely static — no network, no live registry. Usage (from anywhere in the
# worktree):
#   bash tests/renovate/chart-pin-extraction-guard.sh
#   RENOVATE_CONFIG=<abs path> bash tests/renovate/chart-pin-extraction-guard.sh
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

# --- g1: both chart-pin managers exist and claim the scanned files ----------
if ! python3 - "$RENOVATE" <<'PY'
import glob, json, re, sys

cfg = json.load(open(sys.argv[1]))
legs = cfg.get('customManagers') or []


def need(cond, msg):
    if not cond:
        print(f'FAIL: g1: {msg}', file=sys.stderr)
        sys.exit(1)


for desc in ('Update Charts - key as chart name',
             'Update Charts - explicit chart field'):
    found = [l for l in legs if isinstance(l, dict) and l.get('description') == desc]
    need(len(found) == 1,
         f'expected exactly one customManager with description {desc!r}, found {len(found)} — '
         'the guard identifies its managers by description, not index')

files = sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml')))
need(files, 'no top-level services values files found — the scan glob no longer matches the tree')

# The pattern probe is the services-values-pins.sh v4 shape: strip the
# slash delimiters before re.search over the repo-relative path.
key = next(l for l in legs if l.get('description') == 'Update Charts - key as chart name')
uncovered = [f for f in files
             if not any(re.compile(p[1:-1]).search(f) for p in key.get('managerFilePatterns') or [])]
need(not uncovered,
     f'files {uncovered} are outside the key-as-chart-name managerFilePatterns — '
     'asserting extraction for them would prove nothing about what Renovate sees')
print(f'census: {len(files)} top-level services values files, all under the manager file patterns')
PY
then
  fail "g1: see the g1 detail above"
fi
ok "g1: both chart-pin managers exist, identified by description, and the key manager's file patterns cover all scanned values files"

# --- g2 [owner's named case]: the grafana pin extracts ----------------------
if ! python3 - "$RENOVATE" <<'PY'
import json, re, sys

cfg = json.load(open(sys.argv[1]))
key = next(l for l in cfg['customManagers'] if l.get('description') == 'Update Charts - key as chart name')
# JS named-group form converted for python re at run time (never duplicated).
extract = re.compile(re.sub(r'\(\?<(?=\w)', '(?P<', key['matchStrings'][0]))

f = 'services/monitoring/prod/values.yaml'
lines = open(f).read().split('\n')
hits = {(m.group('depName'), m.group('currentValue'), m.group('registryUrl'))
        for m in extract.finditer('\n'.join(lines))}

section = None
grafana = []
for i, ln in enumerate(lines):
    if re.match(r'^[a-zA-Z0-9_-]+:', ln):
        section = ln.split(':', 1)[0]
    if section != 'charts':
        continue
    mk = re.match(r'^[ \t]*grafana:[ \t]*$', ln)
    mv = re.match(r'^[ \t]*version:[ \t]*([\d.]+)[ \t]*$', lines[i + 1]) if i + 1 < len(lines) else None
    mr = re.match(r'^[ \t]*repository:[ \t]*(\S+)', lines[i + 2]) if i + 2 < len(lines) else None
    if mk and mv and mr:
        grafana.append(('grafana', mv.group(1), mr.group(1)))

if not grafana:
    keyline = any(re.match(r'^[ \t]*grafana:[ \t]*$', ln) for ln in lines)
    detail = ('charts.grafana entry exists but its version/repository lines are not the '
              'tracked bare trio shape (a trailing comment is the known killer)'
              if keyline else
              f'no charts.grafana entry at all in {f} — the named case no longer exists to guard')
    print(f'FAIL: g2: {detail}', file=sys.stderr)
    sys.exit(1)
missing = [t for t in grafana if t not in hits]
if missing:
    print(f'FAIL: g2: grafana pins not extracted by the key manager: {missing}', file=sys.stderr)
    sys.exit(1)
print(f'grafana pins extracted: {sorted(set(grafana))}')
PY
then
  fail "g2: see the g2 detail above"
fi
ok "g2: the charts.grafana pin (triple read from the file) extracts through the key-as-chart-name manager"

# --- g3 [full coverage]: every enabled charts trio extracts -----------------
if ! python3 - "$RENOVATE" <<'PY'
import glob, json, re, sys

cfg = json.load(open(sys.argv[1]))
key = next(l for l in cfg['customManagers'] if l.get('description') == 'Update Charts - key as chart name')
chart = next(l for l in cfg['customManagers'] if l.get('description') == 'Update Charts - explicit chart field')
KEY = re.compile(re.sub(r'\(\?<(?=\w)', '(?P<', key['matchStrings'][0]))
CHART = re.compile(re.sub(r'\(\?<(?=\w)', '(?P<', chart['matchStrings'][0]))

TOPKEY = re.compile(r'^[a-zA-Z0-9_-]+:')
KEYLINE = re.compile(r'^[ \t]*([a-zA-Z0-9_-]+):[ \t]*$')
CHARTLINE = re.compile(r'^[ \t]*chart:[ \t]*(\S+)[ \t]*$')
VERLINE = re.compile(r'^[ \t]*version:[ \t]*([\d.]+)(.*)$')
REPOLINE = re.compile(r'^[ \t]*repository:[ \t]*(\S+)')

files = sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml')))
trios = 0
for f in files:
    text = open(f).read()
    lines = text.split('\n')
    key_hits = {(m.group('depName'), m.group('currentValue'), m.group('registryUrl'))
                for m in KEY.finditer(text)}
    chart_hits = {(m.group('depName'), m.group('currentValue'), m.group('registryUrl'))
                  for m in CHART.finditer(text)}
    section = None
    for i, ln in enumerate(lines):
        if TOPKEY.match(ln):
            section = ln.split(':', 1)[0]
        if section != 'charts':
            continue
        mv = VERLINE.match(ln)
        if not mv:
            continue
        mr = REPOLINE.match(lines[i + 1]) if i + 1 < len(lines) else None
        if not mr:
            continue
        prev = lines[i - 1] if i else ''
        ver, url = mv.group(1), mr.group(1)
        mk, mc = KEYLINE.match(prev), CHARTLINE.match(prev)
        if mk:
            trio, pool, mgr = (mk.group(1), ver, url), key_hits, 'key-as-chart-name'
        elif mc:
            trio, pool, mgr = (mc.group(1), ver, url), chart_hits, 'explicit-chart-field'
        else:
            print(f'FAIL: g3: {f}:{i + 1}: version/repository pair whose line above is neither a '
                  'bare entry key nor a chart: field — a shape no chart-pin manager consumes',
                  file=sys.stderr)
            sys.exit(1)
        if trio not in pool:
            print(f'FAIL: g3: {f}:{i + 1}: enabled pin {trio} does not extract via the '
                  f'{mgr} manager (a trailing comment on the version line breaks the adjacency)',
                  file=sys.stderr)
            sys.exit(1)
        trios += 1
print(f'census: {len(files)} files, {trios} enabled charts pins extracted with correct triples')
if trios == 0:
    print('FAIL: g3: zero enabled version+repository pins scanned — the line patterns drifted '
          'from the tree and this leg would pass vacuously', file=sys.stderr)
    sys.exit(1)
PY
then
  fail "g3: see the g3 detail above"
fi
ok "g3: every enabled charts version+repository pin in the services values files extracts via its manager, correct depName/currentValue/registryUrl (census above)"

# --- g4 [anti-pattern]: no trailing `# renovate:` on enabled pins -----------
if ! python3 - <<'PY'
import glob, re, sys

TOPKEY = re.compile(r'^[a-zA-Z0-9_-]+:')
VERLINE = re.compile(r'^[ \t]*version:[ \t]*([\d.]+)(.*)$')
ANNOT = re.compile(r'#\s*renovate', re.IGNORECASE)

bad = []
for f in sorted(set(glob.glob('services/*/*/values.yaml') + glob.glob('services/*/*/values.yml'))):
    lines = open(f).read().split('\n')
    section = None
    for i, ln in enumerate(lines):
        if TOPKEY.match(ln):
            section = ln.split(':', 1)[0]
        if section != 'charts':
            continue
        mv = VERLINE.match(ln)
        if mv and ANNOT.search(mv.group(2)):
            bad.append(f'{f}:{i + 1}: {ln.strip()}')
if bad:
    for b in bad:
        print(f'FAIL: g4: enabled version pin carries a trailing `# renovate:` comment '
              f'(inert annotation that kills the helm-pin extraction): {b}', file=sys.stderr)
    sys.exit(1)
print('census: no enabled version line under any charts: map carries a trailing renovate comment')
PY
then
  fail "g4: see the g4 detail above"
fi
ok 'g4: no enabled charts version pin carries a trailing # renovate: comment'

printf 'PASS: chart-pin-extraction-guard checks (%d ok)\n' "$checks"
