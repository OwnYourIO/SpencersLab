#!/usr/bin/env bash
# Renovate config-surface floor contract for kubernetes-mcp-server
# (2026/2026-10-bug-kubernetes-mcp-toml, C02):
#   Renovate's v0.0.65→v0.0.69 bump (PR #704) crossed the upstream v0.0.68
#   flag→TOML boundary and crash-looped the fleet. The durable fix is a
#   packageRule flooring that package at the TOML side; this script pins the
#   rule's EXISTENCE, SHAPE, and — critically — its MATCHING EXCLUSIVITY: a
#   floor that leaked onto sibling ghcr images would silently freeze unrelated
#   updates, and a floor written as a regex or wildcard would stop binding
#   future tags.
#
# Contract source: chunks/C02.md "Interface contract" + "## Tests". AC trace:
# k1[AC1] k2[AC2] k3[AC3] k4[AC4-typo-guard].
#
# AC4's real schema validation is the agent-run dev-renovate MCP step —
# validate_config (strict) + lint_config + test_package_rules (target,
# `ghcr.io/ownyourio/wekan-mcp`, and the `-old` prefix variant) recorded in
# chunks/C02.md "Review step 2" and pre-proven in DECISIONS D3. The bash
# script cannot substitute for it; k4 is the deterministic offline guard
# against typos dev could introduce, per the chunk.
#
# Usage (default all; unknown ids fail):
#   bash tests/renovate/kubernetes-mcp-version-floor.sh
#   bash tests/renovate/kubernetes-mcp-version-floor.sh k1 k3
#   RENOVATE_CONFIG=<abs path> bash tests/renovate/kubernetes-mcp-version-floor.sh
# RENOVATE_CONFIG defaults to the repo's renovate.json; the override (same
# convention as dockerfile-pins.sh) lets the contract run against a simulated
# final config before dev edits the file. dockerfile-pins.sh's node-from-nvm
# fallback is deliberately not reproduced: this script parses JSON with
# python3 (the chunk's mechanism) and needs no regex-manager execution, so
# node would be an unused dependency.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RENOVATE="${RENOVATE_CONFIG:-renovate.json}"
[ -f "$RENOVATE" ] || { printf 'FAIL: precondition: %s is missing\n' "$RENOVATE" >&2; exit 1; }

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

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4; do WANT["k$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^k[1-4]$ ]] ||
      fail "unknown test id '$a' (expected k1..k4)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

WORK=$(mktemp -d /tmp/opencode/kubernetes-mcp-version-floor.XXXXXX)

# k1 [AC1] — rule present, exact contract fields, sanctioned position + keyset
if want k1; then
  if python3 - "$RENOVATE" "$WORK/k1-count" <<'PY'
import json, re, sys

cfg_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load_cfg(path):
    # AC1: "parses as JSON5/JSON". The repo's comment style is whole-line //;
    # strip those, then strict json.loads (a trailing inline comment is a
    # style break and must fail here, not be tolerated).
    raw = open(path).read()
    stripped = '\n'.join(l for l in raw.splitlines() if not re.match(r'^\s*//', l))
    return json.loads(stripped)

TARGET = 'ghcr.io/containers/kubernetes-mcp-server'
EXPECT_NAMES = [TARGET]
EXPECT_ALLOWED = '>= v0.0.68'   # byte equality — D3: semver comparator, not a regex

try:
    cfg = load_cfg(cfg_path)
    rules = cfg.get('packageRules')
    if not isinstance(rules, list):
        bad(f'k1: {cfg_path} has no packageRules list (JSON5/JSON parse succeeded; the envelope is missing)')
    hits = [(i, r) for i, r in enumerate(rules)
            if isinstance(r.get('matchPackageNames'), list) and r['matchPackageNames'] == EXPECT_NAMES]
    if len(hits) != 1:
        bad(f'k1: {len(hits)} packageRules carry matchPackageNames == {EXPECT_NAMES!r}, expected exactly 1 — AC1 uniqueness, and today the floor rule does not exist at all (the missing-fix state this test is red for)')
    i, rule = hits[0]
    if i != len(rules) - 1:
        bad(f'k1: the floor rule is at index {i}, expected the LAST entry of packageRules (interface contract: appended after the kubectl-hold rule)')
    if set(rule) != {'description', 'matchPackageNames', 'allowedVersions'}:
        bad(f'k1: the floor rule keys are {sorted(rule)}, expected exactly [allowedVersions, description, matchPackageNames] — an extra matcher (e.g. matchUpdateTypes) would narrow the floor past the patch-type bumps that actually carried this incident')
    if rule.get('allowedVersions') != EXPECT_ALLOWED:
        bad(f'k1: allowedVersions is {rule.get("allowedVersions")!r}, expected exactly {EXPECT_ALLOWED!r}')
    desc = rule.get('description')
    if not (isinstance(desc, str) and desc.strip() and 'v0.0.68' in desc):
        bad(f'k1: description must be non-empty and mention v0.0.68 (the boundary the floor encodes), got {desc!r}')
    ok('k1: exactly one floor rule, last entry, exact keyset, byte-exact matchPackageNames + allowedVersions, v0.0.68 in description (C02 AC1)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f'k1: the renovate config could not be parsed/evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/k1-count")))
  else
    exit 1
  fi
fi

# k2 [AC2] — rule count == 7 and the six originals byte-intact.
# The six rule bodies are embedded as literals: today's renovate.json IS the
# baseline, and "no other rule lost or changed" is provable only against it
# (same convention as dev-mcp-fleet.sh's pinned literals; if an unrelated
# renovate.json change lands via main first, the red line names the drifted
# rule so the coordinator routes the literal update — the test is immutable
# to dev).
if want k2; then
  if python3 - "$RENOVATE" "$WORK/k2-count" <<'PY'
import json, re, sys

cfg_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load_cfg(path):
    raw = open(path).read()
    stripped = '\n'.join(l for l in raw.splitlines() if not re.match(r'^\s*//', l))
    return json.loads(stripped)

ORIG_RULES = [
    {
        "description": "Update base Chart nightly",
        "matchFileNames": ["chart/base"],
        "matchUpdateTypes": ["minor", "patch"],
        "automerge": True,
        "automergeSchedule": ["* 1-6 * * *"]
    },
    {
        "description": "Auto Update Proxies",
        "matchFileNames": ["service/proxy"],
        "matchPackageNames": ["base", "monitoring-agent", "external-secrets-bitwarden"],
        "matchUpdateTypes": ["minor", "patch"],
        "automerge": True,
        "automergeSchedule": ["* 1-6 * * *"]
    },
    {
        "description": "Internet facing services.",
        "matchUpdateTypes": ["minor", "patch"],
        "automergeSchedule": ["* 1-6 * * *"],
        "matchPackageNames": [
            "traefik", "keycloakopenid", "keycloakx",
            "ghcr.io/linuxserver/openssh-server", "crowdsec"
        ],
        "lockFileMaintenance": {"enabled": True},
        "automerge": True
    },
    {
        "description": "Non-critical services",
        "matchUpdateTypes": ["minor", "patch"],
        "automergeSchedule": ["* 1-6 * * 2"],
        "matchPackageNames": [
            "argo-cd", "org.keycloak:keycloak-parent", "wekan", "jellyseerr",
            "lidarr", "radarr", "readarr", "sonarr",
            "ghcr.io/home-operations/prowlarr", "ghcr.io/advplyr/audiobookshelf",
            "ghcr.io/kieraneglin/pinchflat", "ghcr.io/onedr0p/qbittorrent",
            "ghcr.io/music-assistant/server", "toertel/logitech-media-server", "alpine"
        ],
        "lockFileMaintenance": {"enabled": True},
        "automerge": True
    },
    {
        "description": "Hold the helm v3 line: ArgoCD renders this repo's charts with helm v3, so v4 updates are held back until that changes. The pattern is slash-wrapped: a bare ^v3. is not a valid semver range, so renovate would error this dep at lookup with no updates.",
        "matchPackageNames": ["helm/helm"],
        "allowedVersions": "/^v3\\./"
    },
    {
        "description": "Hold kubectl to the lab cluster minor (k3s v1.36.x per charts/base/templates/k3s-version.yaml); a cluster minor upgrade must bump this pattern together with the Dockerfile pin. The pattern is slash-wrapped: a bare ^v1.36. is not a valid semver range, so renovate would error this dep at lookup with no updates.",
        "matchPackageNames": ["kubernetes/kubernetes"],
        "allowedVersions": "/^v1\\.36\\./"
    },
]

try:
    rules = load_cfg(cfg_path).get('packageRules') or []
    if len(rules) != 7:
        bad(f'k2: packageRules count is {len(rules)}, expected 7 (the six originals + exactly the new floor rule) — today it is {len(rules)} because the floor is missing (the missing-fix state)')
    for i, want_rule in enumerate(ORIG_RULES):
        if rules[i] != want_rule:
            bad(f'k2: packageRules[{i}] drifted from the baseline body (description {want_rule["description"][:40]!r}...): C02 forbids touching any other rule — got {rules[i]!r}')
    ok('k2: exactly 7 packageRules; the six original rule bodies are byte-intact at their positions (C02 AC2)')

    descs = [r.get('description') for r in rules]
    for want_rule in ORIG_RULES:
        n = descs.count(want_rule['description'])
        if n != 1:
            bad(f'k2: original description {want_rule["description"][:60]!r}... occurs {n} times, expected exactly once')
    ok('k2: each of the six original descriptions is present exactly once (C02 AC2)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f'k2: the renovate config could not be parsed/evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/k2-count")))
  else
    exit 1
  fi
fi

# k3 [AC3] — matching exclusivity: the floor binds ONE package and nothing
# else claims it. Static exact-name semantics here; the live proof is the
# MCP test_package_rules triple (header). The prefix variant and other ghcr
# images must NOT match — matchPackageNames is exact-membership, so a
# wildcard or slash-wrapped (regex-flavored) entry would silently widen the
# hold to every kubernetes-mcp-server-anything tag.
if want k3; then
  if python3 - "$RENOVATE" "$WORK/k3-count" <<'PY'
import json, re, sys

cfg_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load_cfg(path):
    raw = open(path).read()
    stripped = '\n'.join(l for l in raw.splitlines() if not re.match(r'^\s*//', l))
    return json.loads(stripped)

TARGET = 'ghcr.io/containers/kubernetes-mcp-server'
NEGATIVES = [TARGET + '-old', 'ghcr.io/ownyourio/wekan-mcp']

def pattern_matches(p, dep):
    # Renovate matchPackagePatterns are JS regexes, optionally /.../ wrapped.
    m = re.match(r'^/(.+)/([a-z]*)$', p)
    src, flags = (m.group(1), m.group(2)) if m else (p, '')
    try:
        return re.search(src, dep) is not None
    except re.error:
        return p == dep

try:
    rules = load_cfg(cfg_path).get('packageRules') or []
    floor_idx = [i for i, r in enumerate(rules)
                 if isinstance(r.get('matchPackageNames'), list) and TARGET in r['matchPackageNames']]
    if len(floor_idx) != 1:
        bad(f'k3: expected exactly one rule naming {TARGET} in matchPackageNames, found indices {floor_idx} (the floor rule is absent — nothing claims the package)')
    fi = floor_idx[0]

    names = rules[fi]['matchPackageNames']
    if len(names) != 1 or names[0] != TARGET:
        bad(f'k3: floor rule matchPackageNames is {names!r}, expected exactly [{TARGET!r}] — a single exact entry')
    if '*' in names[0] or names[0].startswith('/'):
        bad(f'k3: floor matchPackageNames entry {names[0]!r} looks wildcarded or slash-wrapped (pattern semantics) — matchPackageNames is exact membership; a pattern there would hold sibling images (e.g. the -old prefix)')
    for neg in NEGATIVES:
        if neg in names:
            bad(f'k3: floor rule also names {neg!r} — must match ONLY {TARGET!r}')
    ok(f'k3: floor rule is a single exact-name entry; the -old prefix variant and wekan-mcp are outside it (C02 AC3)')

    others = [r for i, r in enumerate(rules) if i != fi]
    for r in others:
        mpn = r.get('matchPackageNames') or []
        mpp = r.get('matchPackagePatterns') or []
        if TARGET in mpn:
            bad(f'k3: a SECOND rule names {TARGET} in matchPackageNames ({r.get("description", "<no description>")[:60]!r}...) — only the floor may claim it')
        for p in mpp:
            if pattern_matches(p, TARGET):
                bad(f'k3: non-floor rule ({r.get("description", "<no description>")[:60]!r}...) has matchPackagePatterns entry {p!r} that also matches {TARGET!r} — an unaccounted second matcher could override or intersect the floor (k3 proves exclusivity statically; MCP test_package_rules is the live triple)')
    ok(f'k3: no other rule matches {TARGET} via literal names or patterns ({len(others)} other rules checked) (C02 AC3)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f'k3: the renovate config could not be parsed/evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/k3-count")))
  else
    exit 1
  fi
fi

# k4 [AC4] — structural sanity only (typo guard). Real Renovate-schema
# validation is the agent-run MCP step named in the header; a bash script
# cannot load Renovate's own schema offline.
if want k4; then
  if python3 - "$RENOVATE" "$WORK/k4-count" <<'PY'
import json, re, sys

cfg_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def load_cfg(path):
    raw = open(path).read()
    stripped = '\n'.join(l for l in raw.splitlines() if not re.match(r'^\s*//', l))
    return json.loads(stripped)

TARGET = 'ghcr.io/containers/kubernetes-mcp-server'

try:
    rules = load_cfg(cfg_path).get('packageRules') or []
    hits = [r for r in rules
            if isinstance(r.get('matchPackageNames'), list) and TARGET in r['matchPackageNames']]
    if len(hits) != 1:
        bad(f'k4: floor rule not uniquely present (found {len(hits)}) — structural sanity is unassessable (missing-fix state)')
    rule = hits[0]
    av = rule.get('allowedVersions')
    if not isinstance(av, str):
        bad(f'k4: allowedVersions is {av!r}, expected a string')
    if not av.startswith('>='):
        bad(f'k4: allowedVersions {av!r} does not start with ">=" — a floor, not an exclusion list or regex (D3 rejected the regex floor as fragile across future tag formats)')
    if 'v0.0.68' not in av:
        bad(f'k4: allowedVersions {av!r} does not carry the floor tag v0.0.68 (the flag→TOML boundary)')
    desc = rule.get('description')
    if not (isinstance(desc, str) and desc.strip()):
        bad(f'k4: description is empty — the rationale for the hold is the only place a future reader learns WHY the floor exists')
    ok('k4: allowedVersions is a ">= v0.0.68" semver floor with a non-empty rationale (C02 AC4 structural guard; MCP validate_config is the real schema gate)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f'k4: the renovate config could not be parsed/evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/k4-count")))
  else
    exit 1
  fi
fi

rm -rf "$WORK"

printf 'PASS: kubernetes-mcp-version-floor checks (%d ok)\n' "$checks"
