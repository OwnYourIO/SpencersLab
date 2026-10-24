#!/usr/bin/env bash
# C02 acceptance checks (2026-10-feat-coder-workspace-rebuild), criteria 2-3:
# renovate.json's custom managers must extract exactly the pinned Dockerfile
# artifacts and only them. The NEW manager (containers/*/Dockerfile) yields
# exactly 5 deps with a narrowed datasource capture; the EXISTING git-pin
# manager keeps exactly 3; the two result sets are disjoint; no sha256 is
# tracked.
#
# The regexes under test are extracted from renovate.json at run time (never
# duplicated here) and executed over the Dockerfile text in node, so the
# checks bind to the config that dev actually writes, not to a copy of it.
#
# This repo has no unit-test suite (AGENTS.md "Pipeline specifics"); these
# are the local gate for C02. Each check prints one pass/fail line; any fail
# makes the script exit non-zero.
#
# Usage: bash tests/renovate/dockerfile-pins.sh
#   RENOVATE_CONFIG=<abs path> bash tests/renovate/dockerfile-pins.sh
# RENOVATE_CONFIG defaults to the repo's renovate.json; the override exists to
# run the same contract against a simulated final config.

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

DOCKERFILE="containers/coder-workspace/Dockerfile"
RENOVATE="${RENOVATE_CONFIG:-renovate.json}"

# node comes from nvm in this environment; a login shell may not have it.
if ! command -v node >/dev/null 2>&1; then
  export NVM_DIR=/home/coder/.nvm
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
fi

[ -f "$DOCKERFILE" ] || { echo "fail: precondition: $DOCKERFILE is missing"; exit 1; }
[ -f "$RENOVATE" ] || { echo "fail: precondition: $RENOVATE is missing"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "fail: node is not available (PATH and nvm)"; exit 1; }

TMPDIR_PINS=$(mktemp -d /tmp/opencode/dockerfile-pins.XXXXXX) || { echo "fail: mktemp failed"; exit 2; }
trap 'rm -rf "$TMPDIR_PINS"' EXIT

# A missing manager, a regex error, or a tuple mismatch is a fail line, never
# a crash — the script must say WHY the contract is unmet, not die on it.
cat > "$TMPDIR_PINS/check.mjs" <<'EOF'
import { readFileSync } from 'node:fs';

const [cfgPath, dfPath] = process.argv.slice(2);
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
const text = readFileSync(dfPath, 'utf8');

// C02 task 1 names the pattern verbatim; the new manager is identified by it,
// so a manager for the same file under a different pattern is still "missing".
const NEW_MGR_PATTERN = '/(^|/)containers/[^/]+/Dockerfile$/';
const NARROWED = 'node-version|golang-version|forgejo-releases|npm';
const FJ_SHA256 = '6803c12eed17bfadb40ba95da2a6ab58f9b4a7dc10eabfe3512fce7e2fe6216f';
const CODESERVER_SHA256 = '65bcd20b524d03eb1b5adb7f360244599ef0e5b74089a46a982d32c074b97a29';

// Criterion 2, verbatim. registryUrl '' means the comment has no
// registryUrl attribute (only the forgejo-cli line does).
const EXPECTED_NEW = [
  { datasource: 'node-version', depName: 'node', registryUrl: '', currentValue: 'v26.12.0' },
  { datasource: 'golang-version', depName: 'golang', registryUrl: '', currentValue: '1.27.2' },
  { datasource: 'forgejo-releases', depName: 'forgejo-contrib/forgejo-cli', registryUrl: 'https://codeberg.org', currentValue: 'v0.7.0' },
  { datasource: 'npm', depName: '@opencode/cli', registryUrl: '', currentValue: '2.1.4' },
  { datasource: 'npm', depName: '@openchamber/web', registryUrl: '', currentValue: '2.5.1' },
];
const EXPECTED_GITPIN = [
  { datasource: 'github-releases', depName: 'helm/helm', registryUrl: '', currentValue: 'v3.22.1' },
  { datasource: 'github-releases', depName: 'kubernetes/kubernetes', registryUrl: '', currentValue: 'v1.36.5' },
  { datasource: 'github-releases', depName: 'astral-sh/uv', registryUrl: '', currentValue: '0.13.1' },
];

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`pass: ${m}`); };
const bad = (m) => { fail++; console.log(`fail: ${m}`); };

const managers = Array.isArray(cfg.customManagers) ? cfg.customManagers : [];
const patternsOf = (m) => (Array.isArray(m.managerFilePatterns) ? m.managerFilePatterns : []);
const matchStringsOf = (m) =>
  (Array.isArray(m.matchStrings) ? m.matchStrings : []).map((s) => (typeof s === 'string' ? s : s.match));

// The pre-existing manager is recognised by its github-source alternation;
// C02 forbids touching it, so the signature is stable.
const gitPin = managers.find(
  (m) => m.customType === 'regex' && matchStringsOf(m).some((s) => s.includes('github-tags|github-releases|git-refs')),
);
const newMgr = managers.find((m) => m.customType === 'regex' && patternsOf(m).includes(NEW_MGR_PATTERN));

// runManager mirrors renovate's regex-manager semantics: every matchString is
// applied to the whole file text and ALL its matches are kept (that is how
// one pattern yields several deps). The datasource is the named group —
// with no datasourceTemplate a per-match datasource can only come from it.
function runManager(mgr) {
  const deps = [];
  for (const pat of matchStringsOf(mgr)) {
    let re;
    try { re = new RegExp(pat, 'g'); }
    catch (e) { return { error: `regex ${JSON.stringify(pat)} is invalid: ${e.message}` }; }
    for (const m of text.matchAll(re)) {
      const g = m.groups || {};
      deps.push({
        datasource: g.datasource || '',
        depName: g.depName || '',
        registryUrl: g.registryUrl || '',
        currentValue: g.currentValue || '',
      });
    }
  }
  return { deps };
}

const key = (d) => `${d.datasource}|${d.depName}|${d.registryUrl}|${d.currentValue}`;

function compareSet(label, got, want) {
  const wantSet = new Map(want.map((d) => [key(d), d]));
  const gotKeys = new Set(got.map(key));
  const missing = [...wantSet.values()].filter((d) => !gotKeys.has(key(d))).map(key);
  const extra = got.filter((d) => !wantSet.has(key(d))).map(key);
  if (missing.length === 0 && extra.length === 0) {
    ok(`${label}: extracts exactly the ${want.length} expected deps`);
  } else {
    bad(`${label}: expected ${want.length} deps, extracted ${got.length}`
      + (missing.length ? `; missing: ${missing.join(' ; ')}` : '')
      + (extra.length ? `; unexpected: ${extra.join(' ; ')}` : ''));
  }
}

// --- criterion 2: the two managers, the two exact tuples, disjoint --------
if (!gitPin) {
  bad('c2: existing git-pin manager not found (no regex custom manager capturing github-tags|github-releases|git-refs)');
} else {
  ok('c2: existing git-pin manager present');
}

let newDeps = [], gitpinDeps = [];
if (!newMgr) {
  bad(`c2: NEW custom manager not found (no regex custom manager with managerFilePatterns ${JSON.stringify(NEW_MGR_PATTERN)}); `
    + `managerFilePatterns present: ${managers.map((m) => patternsOf(m).join(', ')).join(' | ') || '<none>'}`);
  bad('c2: new manager extracts 0 of the 5 expected deps (manager missing)');
} else {
  ok(`c2: NEW custom manager present (${JSON.stringify(patternsOf(newMgr))})`);
  const res = runManager(newMgr);
  if (res.error) bad(`c2: new manager: ${res.error}`);
  else {
    newDeps = res.deps;
    compareSet('c2: new manager', newDeps, EXPECTED_NEW);
  }
}

if (gitPin) {
  const res = runManager(gitPin);
  if (res.error) bad(`c2: git-pin manager: ${res.error}`);
  else {
    gitpinDeps = res.deps;
    compareSet('c2: git-pin manager', gitpinDeps, EXPECTED_GITPIN);
  }
}

if (!newMgr || !gitPin) {
  bad('c2: cannot check disjointness — one of the two managers is missing');
} else {
  const shared = newDeps.filter((d) => gitpinDeps.some((e) => key(e) === key(d)));
  if (shared.length === 0) ok('c2: new and git-pin result sets are disjoint (0 deps matched by both)');
  else bad(`c2: ${shared.length} dep(s) matched by BOTH managers: ${shared.map(key).join(' ; ')}`);
}

// --- criterion 3: no sha256 is renovate-tracked ---------------------------
// "Tracked" = extracted as a currentValue from any regex custom manager over
// this Dockerfile. The sha check runs over every manager, not just the two:
// criterion 3 is about the file, not the two managers.
const allDeps = [];
for (const m of managers) {
  if (m.customType !== 'regex') continue;
  const res = runManager(m);
  if (!res.error) allDeps.push(...res.deps);
}
const shaDeps = allDeps.filter((d) => d.currentValue === FJ_SHA256 || d.currentValue === CODESERVER_SHA256);
if (shaDeps.length === 0) ok('c3: FJ_SHA256 and code-server sha256 are not tracked as a version');
else bad(`c3: sha256 value(s) are tracked: ${shaDeps.map(key).join(' ; ')}`);

const hexDeps = allDeps.filter((d) => /^[0-9a-f]{64}$/.test(d.currentValue));
if (hexDeps.length === 0) ok('c3: no extracted currentValue is a 64-hex sha256');
else bad(`c3: 64-hex currentValue(s) extracted: ${hexDeps.map(key).join(' ; ')}`);

// --- mutation check: the disjointness check must be live ------------------
// Widening the narrowed datasource capture back to the probe's generic
// [a-z-]+ re-matches the three github-releases ARG lines, so the disjointness
// check above must then find duplicates. If it did not, the check would pass
// vacuously and the narrowing (DECISIONS #15) would be unenforced.
if (!newMgr) {
  bad('c2: mutation check not runnable — new manager missing');
} else {
  const pats = matchStringsOf(newMgr);
  const widened = pats.map((p) => {
    const groupRe = /datasource=\(\?<datasource>([^)]+)\)/;
    if (groupRe.test(p)) return p.replace(groupRe, 'datasource=(?<datasource>[a-z-]+)');
    if (p.includes(NARROWED)) return p.replace(NARROWED, '[a-z-]+');
    return p;
  });
  if (widened.every((p, i) => p === pats[i])) {
    bad('c2: mutation check not runnable — no narrowed datasource capture found to widen (patterns: ' + pats.join(' | ') + ')');
  } else {
    let mutated = [];
    let widenedErr = null;
    for (const pat of widened) {
      try {
        for (const m of text.matchAll(new RegExp(pat, 'g'))) {
          const g = m.groups || {};
          mutated.push({
            datasource: g.datasource || '',
            depName: g.depName || '',
            registryUrl: g.registryUrl || '',
            currentValue: g.currentValue || '',
          });
        }
      } catch (e) { widenedErr = e.message; }
    }
    if (widenedErr) {
      bad(`c2: mutation check not runnable — widened pattern is invalid: ${widenedErr}`);
    } else {
      const shared = mutated.filter((d) => gitpinDeps.some((e) => key(e) === key(d)));
      const dupNames = shared.map((d) => d.depName);
      const wantDups = ['helm/helm', 'kubernetes/kubernetes', 'astral-sh/uv'];
      const missingDups = wantDups.filter((n) => !dupNames.includes(n));
      if (shared.length > 0 && missingDups.length === 0) {
        ok(`c2: mutation check live — generic [a-z-]+ capture duplicates ${dupNames.join(', ')} (disjointness would fail)`);
      } else {
        bad(`c2: mutation check dead — generic [a-z-]+ capture produced no expected duplicates (shared: ${shared.map(key).join(' ; ') || '<none>'})`);
      }
    }
  }
}

console.log(`=== dockerfile-pins: ${pass} passed, ${fail} failed ===`);
process.exit(fail === 0 ? 0 : 1);
EOF

node "$TMPDIR_PINS/check.mjs" "$RENOVATE" "$DOCKERFILE"
