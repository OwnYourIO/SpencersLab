#!/usr/bin/env bash
# C02 acceptance checks (2026-11-cf-95-bug-fix-renovate): the three
# dead-upstream replacements in the services values files — paperless tika →
# apache/tika (DECISIONS D4), karakeep chrome → zenika/alpine-chrome (D5),
# the deleted Grafana dashboard 16541 → live successor 13665 rev 4 (D3) —
# plus the regression pins around them.
#
# Hermetic (C02 Tests): greps, adjacency and YAML-structure asserts only.
# Digest VALUE correctness (AC3) and dashboard successor liveness (AC6) are
# network probes run by dev/review per plan Commands §4/§6 and quoted in
# commands_run — this suite pins the tag+digest FORMAT and the field shapes,
# never offline-assertable liveness.
#
# The byte-exact excerpts of the untouched neighbours (sibling 13665 entry,
# gotenberg block) are baseline literals taken from THIS tree — the same
# embedded-baseline convention as kubernetes-mcp-version-floor.sh: "no other
# block moved" is only provable against the recorded bytes, and if an
# unrelated main change drifts one, the red line names it for the
# coordinator rather than passing vacuously.
#
# Each check prints one pass/fail line; any fail makes the script exit
# non-zero. Run from anywhere in the worktree:
#   bash tests/services/home-dead-image-refs.sh

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

HOMEV="services/home/prod/values.yaml"
MONV="services/monitoring/prod/values.yaml"

for f in "$HOMEV" "$MONV"; do
  [ -f "$f" ] || { echo "fail: precondition: $f is missing"; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "fail: precondition: python3 with PyYAML is unavailable"; exit 1; }

WORK=$(mktemp -d /tmp/opencode/home-dead-image-refs.XXXXXX) || { echo "fail: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/lines.log"
: > "$LOG"

pass() { printf 'pass: %s\n' "$1" | tee -a "$LOG"; }
fail() { printf 'fail: %s\n' "$1" | tee -a "$LOG"; }

# want_count <needle> <file> <n> <label> — literal fixed-string count.
want_count() {
  local n
  n=$(grep -cF -- "$1" "$2" 2>/dev/null || true)
  if [ "${n:-0}" -eq "$3" ]; then
    pass "$4 (count $n == $3)"
  else
    fail "$4 (count ${n:-0}, want $3; needle: $1 in $2)"
  fi
}

# --- s1 [C02 AC1]: the dead references and exact old strings are gone -------
want_count 'ghcr.io/paperless-ngx/tika' "$HOMEV" 0 's1 [AC1]: paperless-ngx tika fork ref absent'
want_count 'gcr.io/zenika-hub' "$HOMEV" 0 's1 [AC1]: zenika-hub GCR project ref absent'
want_count '2.9.1-minimal@sha256:20db' "$HOMEV" 0 's1 [AC1]: old tika 2.9.1-minimal@sha256:20db tag string absent'
want_count '16541' "$MONV" 0 's1 [AC1]: deleted dashboard id 16541 absent'
want_count 'depName="Speedtest Exporter"' "$MONV" 0 's1 [AC1]: old hub-entry depName "Speedtest Exporter" absent'

# --- s2 [C02 AC1 "assert not resurrected elsewhere"]: the OTHER dashboard
# entries legitimately keep `name: datasource` mappings (baseline 5:
# Troubleshooting x2 + hub x1 + Unbound x2; the fix converts exactly the hub
# one, so 4 must remain). The count is the deterministic offline proof that
# the hub entry's deleted-dashboard variable name was neither left in place
# nor copied into a sibling.
want_count 'name: datasource' "$MONV" 4 's2 [AC1]: name: datasource count drops to the 4 untouched entries'

# --- s3 [C02 AC2]: the new refs and tag strings occur exactly once ----------
want_count 'repository: apache/tika' "$HOMEV" 1 's3 [AC2]: exactly one apache/tika repository line'
want_count 'repository: zenika/alpine-chrome' "$HOMEV" 1 's3 [AC2]: exactly one zenika/alpine-chrome repository line'
want_count '2.9.2.1-full@sha256:' "$HOMEV" 1 's3 [AC2]: exactly one tika 2.9.2.1-full@sha256: tag string'

# --- s4..s9: adjacency, digest FORMAT, dashboard legs, YAML parse, pins -----
python3 - "$HOMEV" "$MONV" 2>>"$LOG" <<'PY' | tee -a "$LOG"
import re, sys, yaml

homev, monv = sys.argv[1:3]
home_text = open(homev).read()
mon_text = open(monv).read()
home = home_text.split('\n')

def ok(msg):
    print(f'pass: {msg}')

def bad(msg):
    print(f'fail: {msg}')

def find_parents(obj, key, out):
    if isinstance(obj, dict):
        if key in obj:
            out.append(obj)
        for v in obj.values():
            find_parents(v, key, out)
    elif isinstance(obj, list):
        for v in obj:
            find_parents(v, key, out)

# s4 [AC2/AC3-format]: the apache/tika line is followed by exactly
# `tag: 2.9.2.1-full@sha256:<64hex>`. FORMAT only — the digest VALUE must
# equal the live docker-content-digest of the tag's multi-arch index
# manifest, which is dev/review's plan Commands §4 probe (AC3/AC6), never
# assertable offline.
tika_idx = [i for i, l in enumerate(home) if l == '            repository: apache/tika']
if len(tika_idx) != 1:
    bad(f's4 [AC2]: expected exactly one "repository: apache/tika" line at its baseline indentation, found {len(tika_idx)} — adjacency unassessable')
else:
    nxt = home[tika_idx[0] + 1] if tika_idx[0] + 1 < len(home) else ''
    if re.fullmatch(r'            tag: 2\.9\.2\.1-full@sha256:[0-9a-f]{64}', nxt):
        ok('s4 [AC2/AC3]: tika tag line is 2.9.2.1-full@sha256:<64hex> — D4 newest-2.9.x tag plus the file-standard digest-pin style (value = the AC3 live probe)')
    else:
        bad(f's4 [AC2/AC3]: tika tag line is {nxt!r}, want "            tag: 2.9.2.1-full@sha256:<64hex>"')

# s5 [AC2/D5]: zenika/alpine-chrome keeps the FLOATING `tag: 124` — this
# block never carried a digest pin (user answer #7), so requiring one here
# would invent a style the plan explicitly rejected.
chr_idx = [i for i, l in enumerate(home) if l == '            repository: zenika/alpine-chrome']
if len(chr_idx) != 1:
    bad(f's5 [AC2]: expected exactly one "repository: zenika/alpine-chrome" line at its baseline indentation, found {len(chr_idx)} — adjacency unassessable')
else:
    nxt = home[chr_idx[0] + 1] if chr_idx[0] + 1 < len(home) else ''
    if nxt == '            tag: 124':
        ok('s5 [AC2/D5]: chrome tag line is the floating tag: 124, no digest pin added')
    else:
        bad(f's5 [AC2/D5]: chrome tag line is {nxt!r}, want "            tag: 124"')

# s6 [AC4/D3]: the hub dashboard entry, its four fields asserted together —
# depName comment line (raw adjacency, comments are invisible to YAML),
# gnetId, revision and the datasource mapping (parsed, so either flow or
# block list style binds). The (hub) disambiguator is REQUIRED: the sibling
# already pins 13665 under depName "Speedtest-Exporter Dashboard", and two
# same-file deps with identical depName+packageName dedupe to one,
# half-bumping this file silently.
hub_key_n = len(re.findall(r'^      speedtest-exporter-hub:$', mon_text, re.M))
hub_adj_ok = False
if hub_key_n != 1:
    bad(f's6 [AC4]: speedtest-exporter-hub key occurs {hub_key_n} times, want exactly 1 — entry unassessable')
else:
    hub_adj_ok = bool(re.search(
        r'^      speedtest-exporter-hub:\n'
        r'        # renovate: depName="Speedtest-Exporter Dashboard \(hub\)"$',
        mon_text, re.M))
    if not hub_adj_ok:
        bad('s6 [AC4]: speedtest-exporter-hub: is not followed by the (hub)-disambiguated depName comment')

mon = None
try:
    mon = yaml.safe_load(mon_text)
except Exception as ex:
    bad(f's6 [AC4]/s8 [AC5]: {monv} does not parse ({ex}); structural fields unassessable')
if mon is not None:
    parents = []
    find_parents(mon, 'speedtest-exporter-hub', parents)
    if len(parents) != 1:
        bad(f's6 [AC4]: {len(parents)} parsed entries named speedtest-exporter-hub, want exactly 1')
    else:
        hub = parents[0]['speedtest-exporter-hub']
        want = {'gnetId': 13665, 'revision': 4, 'datasource': [{'name': 'DS_PROMETHEUS', 'value': 'Prometheus'}]}
        diffs = [f'{k}: got {hub.get(k)!r}, want {v!r}' for k, v in want.items() if hub.get(k) != v]
        if hub_adj_ok and not diffs:
            ok('s6 [AC4]: hub entry carries all four fields together — (hub) depName comment, gnetId 13665, revision 4, DS_PROMETHEUS mapping (D3, sibling-proven shape)')
        else:
            reason = '; '.join(diffs) if diffs else 'depName comment wrong (asserted above)'
            bad(f's6 [AC4]: hub entry four-field check failed — {reason}')

# s7 [AC4]: the sibling speedtest-exporter entry is byte-stable — its
# comment+gnetId+revision excerpt occurs exactly once, so the hub rewrite
# cannot have touched it, and the two legs stay distinct deps.
SIBLING = ('        # renovate: depName="Speedtest-Exporter Dashboard"\n'
           '        gnetId: 13665\n'
           '        revision: 4\n')
sib_n = mon_text.count(SIBLING)
if sib_n == 1:
    ok('s7 [AC4]: sibling excerpt byte-unchanged and unique (the hub rewrite kept the two 13665 legs distinct)')
else:
    bad(f's7 [AC4]: sibling excerpt occurs {sib_n} times, want exactly 1')
if mon is not None:
    parents = []
    find_parents(mon, 'speedtest-exporter', parents)
    if len(parents) != 1:
        bad(f's7 [AC4]: {len(parents)} parsed entries named speedtest-exporter, want exactly 1')
    else:
        sib = parents[0]['speedtest-exporter']
        want = {'gnetId': 13665, 'revision': 4, 'datasource': [{'name': 'DS_PROMETHEUS', 'value': 'Prometheus'}]}
        diffs = [f'{k}: got {sib.get(k)!r}, want {v!r}' for k, v in want.items() if sib.get(k) != v]
        if diffs:
            bad('s7 [AC4]: sibling fields drifted — ' + '; '.join(diffs))
        else:
            ok('s7 [AC4]: sibling entry parses to gnetId 13665 / revision 4 / DS_PROMETHEUS mapping (already live, untouched)')

# s8 [AC5]: both values files parse as YAML (the monitoring file's parse is
# also asserted here standalone — s6 only covers it incidentally).
for path in (homev, monv):
    try:
        yaml.safe_load(open(path))
        ok(f's8 [AC5]: {path} parses as YAML')
    except Exception as ex:
        bad(f's8 [AC5]: {path} does not parse: {ex}')

# s9 [regression pins]: the environment and command blocks C02 must leave
# byte-unchanged around the swapped images — the sidecars' own proven
# neighbours, so a careless whole-block rewrite shows up here.
GOTENBERG = ('            repository: gotenberg/gotenberg\n'
             '            tag: 8.38.1@sha256:aa552cc115db488e0f0bcb07446aac13071ad51505b642c84bb894500907b42b\n')
got_n = home_text.count(GOTENBERG)
if got_n == 1:
    ok('s9 [regression]: gotenberg/gotenberg block byte-unchanged (the sidecar whose tag@digest style D4 copies)')
else:
    bad(f's9 [regression]: gotenberg excerpt occurs {got_n} times, want exactly 1')

if home_text.count('PAPERLESS_TIKA_ENDPOINT: http://localhost:9998') == 1:
    ok('s9 [regression]: PAPERLESS_TIKA_ENDPOINT http://localhost:9998 still present (apache/tika serves 9998 by default — no endpoint change needed)')
else:
    bad(f's9 [regression]: PAPERLESS_TIKA_ENDPOINT: http://localhost:9998 occurs {home_text.count("PAPERLESS_TIKA_ENDPOINT: http://localhost:9998")} times, want exactly 1')

if home_text.count('- chromium-browser') == 1 and home_text.count('--remote-debugging-port=9222') == 1:
    ok('s9 [regression]: chromium-browser command + --remote-debugging-port=9222 arg byte-present (the alpine-chrome CDP entrypoint carries over unchanged)')
else:
    bad(f's9 [regression]: chromium-browser x{home_text.count("- chromium-browser")}, '
        f'--remote-debugging-port=9222 x{home_text.count("--remote-debugging-port=9222")} — want 1 and 1')
PY
py_rc=${PIPESTATUS[0]}
if [ "$py_rc" -ne 0 ]; then
  fail "s4-s9: the python assert block exited $py_rc (see stderr above) — counted as a failure, not a skip"
fi

# --- final tally ------------------------------------------------------------
PASS=$(grep -c '^pass: ' "$LOG" || true)
FAIL=$(grep -c '^fail: ' "$LOG" || true)
printf '=== home-dead-image-refs: %s passed, %s failed ===\n' "${PASS:-0}" "${FAIL:-0}"
[ "${FAIL:-1}" -eq 0 ] || exit 1
exit 0
