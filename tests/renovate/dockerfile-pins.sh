#!/usr/bin/env bash
# C02 acceptance checks (2026-10-feat-coder-workspace-rebuild), criteria 2-3:
# renovate.json's custom managers must extract exactly the pinned Dockerfile
# artifacts and only them. The NEW manager (containers/*/Dockerfile) yields
# exactly 5 deps with a narrowed datasource capture; the EXISTING git-pin
# manager keeps exactly 3; the two result sets are disjoint; no sha256 is
# tracked.
#
# Extended by C01 (2026-11-cf-95-bug-fix-renovate), AC2: the git-refs ARG
# pins move out of the git-pin manager into two branch-split legs (DECISIONS
# D7) because git-refs runs `git ls-remote <packageName>` and a bare
# owner/repo resolves as a local path (card failure #4). The leg matrix, the
# branch=/branch-less mutual exclusion, the leg template fields and the
# A/B/gitPin result-set disjointness bind to the REAL renovate.json at run
# time; the branch= shape exists only in a tmpdir fixture Dockerfile (no
# tracked Dockerfile carries branch= today — AC2).
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

# The branch= pin shape AC2 requires for the branch-aware leg exists in no
# tracked Dockerfile today, and none may gain one (the gpt-researcher pins
# stay branch-less per user answer #5), so the fixture lives here only.
mkdir -p "$TMPDIR_PINS/branch-fixture"
cat > "$TMPDIR_PINS/branch-fixture/Dockerfile" <<'EOF'
# renovate: datasource=git-refs depName=acme/widget branch=develop
ARG WIDGET_SHA=0a1b2c3d4e5f60718293a4b5c6d7e8f901234567
EOF

# Every tracked containers Dockerfile feeds the leg matrix (the branch-aware
# leg must extract 0 from all of them; the default leg only from gpt files).
mapfile -t REAL_DOCKERFILES < <(git ls-files 'containers' | grep -E '(^|/)Dockerfile$')
[ "${#REAL_DOCKERFILES[@]}" -ge 2 ] || { echo "fail: precondition: fewer than 2 tracked Dockerfiles under containers/"; exit 1; }

# A missing manager, a regex error, or a tuple mismatch is a fail line, never
# a crash — the script must say WHY the contract is unmet, not die on it.
cat > "$TMPDIR_PINS/check.mjs" <<'EOF'
import { readFileSync } from 'node:fs';

const [cfgPath, fixturePath, ...realPaths] = process.argv.slice(2);
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
const read = (p) => readFileSync(p, 'utf8');

const CW = realPaths.find((p) => p.endsWith('containers/coder-workspace/Dockerfile'));
const GPT_BE = realPaths.find((p) => p.endsWith('containers/gpt-researcher/Dockerfile'));
const GPT_FE = realPaths.find((p) => p.endsWith('containers/gpt-researcher-frontend/Dockerfile'));

// C02 task 1 names the pattern verbatim; the new manager is identified by it,
// so a manager for the same file under a different pattern is still "missing".
const NEW_MGR_PATTERN = '/(^|/)containers/[^/]+/Dockerfile$/';
const NARROWED = 'node-version|golang-version|forgejo-releases|npm';
const FJ_SHA256 = '6803c12eed17bfadb40ba95da2a6ab58f9b4a7dc10eabfe3512fce7e2fe6216f';
const CODESERVER_SHA256 = '65bcd20b524d03eb1b5adb7f360244599ef0e5b74089a46a982d32c074b97a29';
const GPTR_DIGEST = '5cdad9cb434754188b78bd998df18dd8d502cf7e';

// Criterion 2, verbatim. registryUrl '' means the comment has no
// registryUrl attribute (only the forgejo-cli line does).
const EXPECTED_NEW = [
  { datasource: 'node-version', depName: 'node', registryUrl: '', currentValue: '26.12.1' },
  { datasource: 'golang-version', depName: 'golang', registryUrl: '', currentValue: '1.27.3' },
  { datasource: 'forgejo-releases', depName: 'forgejo-contrib/forgejo-cli', registryUrl: 'https://codeberg.org', currentValue: 'v0.7.0' },
  { datasource: 'npm', depName: '@opencode/cli', registryUrl: '', currentValue: '2.1.4' },
  { datasource: 'npm', depName: '@openchamber/web', registryUrl: '', currentValue: '2.5.1' },
];
const EXPECTED_GITPIN = [
  { datasource: 'github-releases', depName: 'helm/helm', registryUrl: '', currentValue: 'v3.22.1' },
  { datasource: 'github-releases', depName: 'kubernetes/kubernetes', registryUrl: '', currentValue: 'v1.36.5' },
  { datasource: 'github-releases', depName: 'astral-sh/uv', registryUrl: '', currentValue: '0.13.5' },
];
// AC2: the two git-refs legs capture the pinned commit as a DIGEST, never as
// a version — the version field carries the branch (A) or 'main' (B) via
// manager-level templates.
const EXPECTED_B_GPTR = [{ depName: 'assafelovic/gpt-researcher', currentDigest: GPTR_DIGEST }];
const EXPECTED_A_FIXTURE = [{ depName: 'acme/widget', branch: 'develop', currentDigest: '0a1b2c3d4e5f60718293a4b5c6d7e8f901234567' }];

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`pass: ${m}`); };
const bad = (m) => { fail++; console.log(`fail: ${m}`); };

if (!CW || !GPT_BE || !GPT_FE) {
  bad(`precondition: expected coder-workspace + both gpt-researcher Dockerfiles among ${realPaths.join(', ')}`);
  console.log(`=== dockerfile-pins: ${pass} passed, ${fail} failed ===`);
  process.exit(1);
}
const textCw = read(CW);
const textGptBe = read(GPT_BE);
const textGptFe = read(GPT_FE);
const textFixture = read(fixturePath);

const managers = Array.isArray(cfg.customManagers) ? cfg.customManagers : [];
const patternsOf = (m) => (Array.isArray(m.managerFilePatterns) ? m.managerFilePatterns : []);
const matchStringsOf = (m) =>
  (Array.isArray(m.matchStrings) ? m.matchStrings : []).map((s) => (typeof s === 'string' ? s : s.match));

// Re-signed for C01: the narrowed alternation is `github-tags|github-releases`
// (git-refs moved to its own legs), so the signature is the still-supported
// prefix — stable across the fix. The old signature
// `github-tags|github-releases|git-refs` would vanish with the fix.
const gitPin = managers.find(
  (m) => m.customType === 'regex' && matchStringsOf(m).some((s) => s.includes('github-tags|github-releases')),
);
const newMgr = managers.find((m) => m.customType === 'regex' && patternsOf(m).includes(NEW_MGR_PATTERN));

// The two git-refs legs are identified by datasourceTemplate + pattern shape
// (AC2/C01 Tests): the branch-aware leg A carries a (?<branch>) group, the
// default leg B does not. Exactly two such managers, one per shape.
const gitRefsMgrs = managers.filter((m) => m.customType === 'regex' && m.datasourceTemplate === 'git-refs');
const mgrA = gitRefsMgrs.find((m) => matchStringsOf(m).some((s) => s.includes('(?<branch>')));
const mgrB = gitRefsMgrs.find((m) => m !== mgrA && !matchStringsOf(m).some((s) => s.includes('(?<branch>')));

// runManager mirrors renovate's regex-manager semantics: every matchString is
// applied to the whole file text and ALL its matches are kept (that is how
// one pattern yields several deps). The datasource is the named group —
// with no datasourceTemplate a per-match datasource can only come from it.
function runManager(mgr, text) {
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
        currentDigest: g.currentDigest || '',
        branch: g.branch || '',
      });
    }
  }
  return { deps };
}

const key = (d) =>
  [d.datasource || '', d.depName || '', d.registryUrl || '', d.currentValue || '', d.currentDigest || '', d.branch || ''].join('|');

// Renovate's duplicate-dependency warning keys on package identity, not on
// which capture group name held the version — the effective key folds the
// datasourceTemplate in and currentValue/currentDigest into one slot.
const effKey = (mgr, d) =>
  `${d.datasource || mgr.datasourceTemplate || ''}|${d.depName}|${d.currentValue || d.currentDigest || ''}`;

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
  bad('c2: existing git-pin manager not found (no regex custom manager capturing github-tags|github-releases)');
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
  const res = runManager(newMgr, textCw);
  if (res.error) bad(`c2: new manager: ${res.error}`);
  else {
    newDeps = res.deps;
    compareSet('c2: new manager', newDeps, EXPECTED_NEW);
  }
}

if (gitPin) {
  const res = runManager(gitPin, textCw);
  if (res.error) bad(`c2: git-pin manager: ${res.error}`);
  else {
    gitpinDeps = res.deps;
    compareSet('c2: git-pin manager', gitpinDeps, EXPECTED_GITPIN);
  }

  // AC2 / D7: the git-refs alternation must leave #8 — a bare owner/repo is
  // not a valid git-refs packageName, so the leg that fed it produced the
  // card's gpt-researcher no-result failures.
  if (matchStringsOf(gitPin).some((s) => s.includes('git-refs'))) {
    bad('g1: git-pin manager matchStrings still name git-refs — the datasource group must narrow to '
      + 'github-tags|github-releases (git-refs moves to its own legs, DECISIONS D7)');
  } else {
    ok('g1: git-pin manager matchStrings no longer name git-refs (narrowed per D7)');
  }
}

// AC2: the git-pin manager must yield 0 deps on both gpt-researcher files —
// their branch-less git-refs ARG pins belong to the default leg now.
if (gitPin) {
  for (const [name, text] of [['gpt-researcher', textGptBe], ['gpt-researcher-frontend', textGptFe]]) {
    const res = runManager(gitPin, text);
    if (res.error) bad(`g2: git-pin on ${name}: ${res.error}`);
    else if (res.deps.length === 0) ok(`g2: git-pin manager extracts 0 deps from containers/${name}/Dockerfile`);
    else bad(`g2: git-pin manager extracts ${res.deps.length} dep(s) from containers/${name}/Dockerfile `
      + `(${res.deps.map(key).join(' ; ')}) — the bare owner/repo git-refs leg is the card's failure #4 and must be gone`);
  }
}

// --- AC2: the two git-refs legs exist, one per comment shape --------------
if (gitRefsMgrs.length !== 2 || !mgrA || !mgrB) {
  bad(`g3: expected exactly 2 git-refs custom managers (datasourceTemplate=git-refs; branch-aware A + default B), found ${gitRefsMgrs.length}`
    + ` (A=${mgrA ? 'yes' : 'no'}, B=${mgrB ? 'yes' : 'no'}) — the branch= grammar split of DECISIONS D7 is not in the config`);
} else {
  ok('g3: both git-refs legs present — exactly 2 managers with datasourceTemplate=git-refs, one with a (?<branch>) capture, one without');

  const FP = 'https://github.com/{{depName}}';
  const tmplChecks = [
    ['A.currentValueTemplate == "{{branch}}"', mgrA.currentValueTemplate, '{{branch}}'],
    ['B.currentValueTemplate == "main"', mgrB.currentValueTemplate, 'main'],
    [`A.packageNameTemplate == "${FP}"`, mgrA.packageNameTemplate, FP],
    [`B.packageNameTemplate == "${FP}"`, mgrB.packageNameTemplate, FP],
  ];
  for (const [label, actual, want] of tmplChecks) {
    if (actual === want) ok(`g4: ${label} (the git-refs datasource resolves a bare owner/repo as a local path; the FQDN template and the branch-as-version are what make the leg live)`);
    else bad(`g4: ${label} violated — got ${JSON.stringify(actual)}`);
  }

  const resAFixture = runManager(mgrA, textFixture);
  const resBFixture = runManager(mgrB, textFixture);
  const resAGptBe = runManager(mgrA, textGptBe);
  const resBGptBe = runManager(mgrB, textGptBe);
  const resAGptFe = runManager(mgrA, textGptFe);
  const resBGptFe = runManager(mgrB, textGptFe);
  const resBCw = runManager(mgrB, textCw);
  for (const [name, res] of Object.entries({ 'A on fixture': resAFixture, 'B on fixture': resBFixture, 'A on gpt': resAGptBe, 'B on gpt': resBGptBe, 'A on gpt-fe': resAGptFe, 'B on gpt-fe': resBGptFe, 'B on coder-workspace': resBCw })) {
    if (res.error) bad(`g5/g6: ${name}: ${res.error}`);
  }

  // A: exactly the fixture tuple; 0 on every tracked Dockerfile (none carries
  // branch= — user answer #5 keeps the gpt pins branch-less).
  if (!resAFixture.error) compareSet('g5: branch-aware leg A', resAFixture.deps, EXPECTED_A_FIXTURE);
  let aRealTotal = 0, aRealErr = null;
  for (const p of realPaths) {
    const res = runManager(mgrA, read(p));
    if (res.error) { aRealErr = `${p}: ${res.error}`; break; }
    aRealTotal += res.deps.length;
  }
  if (aRealErr) bad(`g5: branch-aware leg A: ${aRealErr}`);
  else if (aRealTotal === 0) ok(`g5: branch-aware leg A extracts 0 deps from all ${realPaths.length} tracked Dockerfiles`);
  else bad(`g5: branch-aware leg A extracted ${aRealTotal} dep(s) from tracked Dockerfiles — no tracked Dockerfile carries branch=, so the leg must be empty there`);

  // B: exactly the gpt digest tuple in both files; 0 everywhere else — the
  // mutual exclusion means B must not match the branch= fixture either.
  if (!resBGptBe.error) compareSet('g6: default leg B on gpt-researcher', resBGptBe.deps, EXPECTED_B_GPTR);
  if (!resBGptFe.error) compareSet('g6: default leg B on gpt-researcher-frontend', resBGptFe.deps, EXPECTED_B_GPTR);
  if (!resBCw.error) compareSet('g6: default leg B on coder-workspace (empty)', resBCw.deps, []);
  if (!resBFixture.error) compareSet('g6: default leg B on branch= fixture (empty — mutual exclusion)', resBFixture.deps, []);
  for (const p of realPaths) {
    if (p === GPT_BE || p === GPT_FE) continue;
    const res = runManager(mgrB, read(p));
    if (res.error) { bad(`g6: default leg B on ${p}: ${res.error}`); continue; }
    if (res.deps.length === 0) ok(`g6: default leg B extracts 0 deps from ${p}`);
    else bad(`g6: default leg B extracted ${res.deps.length} dep(s) from ${p} (${res.deps.map(key).join(' ; ')}) — expected 0 outside the gpt-researcher pins`);
  }
}

if (!newMgr || !gitPin) {
  bad('c2: cannot check disjointness — one of the two managers is missing');
} else {
  const shared = newDeps.filter((d) => gitpinDeps.some((e) => key(e) === key(d)));
  if (shared.length === 0) ok('c2: new and git-pin result sets are disjoint (0 deps matched by both)');
  else bad(`c2: ${shared.length} dep(s) matched by BOTH managers: ${shared.map(key).join(' ; ')}`);
}

// AC2, last clause: every manager's result set must be pairwise disjoint per
// file — renovate dedupes by depName+datasource+version, so two legs hitting
// the same pin is a duplicate-dependency warning no matter which group name
// holds the version (the git-refs split must not re-collide with #8).
{
  const texts = [['coder-workspace', textCw], ['gpt-be', textGptBe], ['gpt-fe', textGptFe], ['fixture', textFixture]];
  const active = managers.filter((m) => m.customType === 'regex');
  let collisions = 0;
  for (const [fname, text] of texts) {
    const perMgr = [];
    for (const m of active) {
      const res = runManager(m, text);
      if (res.error) { bad(`g7: ${fname}: ${m.description || '<manager>'}: ${res.error}`); continue; }
      if (res.deps.length) perMgr.push([m, new Set(res.deps.map((d) => effKey(m, d)))]);
    }
    for (let i = 0; i < perMgr.length; i++) {
      for (let j = i + 1; j < perMgr.length; j++) {
        const dup = [...perMgr[i][1]].filter((k) => perMgr[j][1].has(k));
        if (dup.length) {
          collisions++;
          bad(`g7: ${fname}: managers "${(perMgr[i][0].description || '').slice(0, 40)}" and "${(perMgr[j][0].description || '').slice(0, 40)}" both extract ${dup.join(' ; ')} (duplicate-dependency surface)`);
        }
      }
    }
  }
  if (collisions === 0) ok(`g7: per-file manager result sets are pairwise disjoint across all ${active.length} regex managers`);
}

// --- criterion 3: no sha256 is renovate-tracked ---------------------------
// "Tracked" = extracted as a currentValue from any regex custom manager over
// this Dockerfile. The sha check runs over every manager, not just the two:
// criterion 3 is about the file, not the two managers.
const allDeps = [];
for (const m of managers) {
  if (m.customType !== 'regex') continue;
  const res = runManager(m, textCw);
  if (!res.error) allDeps.push(...res.deps);
}
const shaDeps = allDeps.filter((d) => d.currentValue === FJ_SHA256 || d.currentValue === CODESERVER_SHA256);
if (shaDeps.length === 0) ok('c3: FJ_SHA256 and code-server sha256 are not tracked as a version');
else bad(`c3: sha256 value(s) are tracked: ${shaDeps.map(key).join(' ; ')}`);

const hexDeps = allDeps.filter((d) => /^[0-9a-f]{64}$/.test(d.currentValue));
if (hexDeps.length === 0) ok('c3: no extracted currentValue is a 64-hex sha256');
else bad(`c3: 64-hex currentValue(s) extracted: ${hexDeps.map(key).join(' ; ')}`);

// The gpt pins' 40-hex is the currentDigest of the git-refs legs, never a
// currentValue (AC2/AC3: the digest-vs-version field split).
{
  const gptHexAsValue = [];
  for (const m of managers) {
    if (m.customType !== 'regex') continue;
    for (const [fname, text] of [['gpt-be', textGptBe], ['gpt-fe', textGptFe]]) {
      const res = runManager(m, text);
      if (!res.error) gptHexAsValue.push(...res.deps.filter((d) => /^[0-9a-f]{7,40}$/.test(d.currentValue)).map((d) => `${fname}:${key(d)}`));
    }
  }
  if (gptHexAsValue.length === 0) ok('g8: no regex manager extracts the gpt-researcher 40-hex commit as a currentValue (it is a currentDigest)');
  else bad(`g8: 40-hex extracted as currentValue on gpt files: ${gptHexAsValue.join(' ; ')} — the commit belongs in currentDigest (git-refs digest recipe)`);
}

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
        for (const m of textCw.matchAll(new RegExp(pat, 'g'))) {
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

// --- AC2 mutation check: re-adding git-refs to #8 must re-create the
// collision on the gpt files — proving the g2 zero-extraction and the
// disjointness assertions bind to the alternation content, not vacuously.
if (!gitPin || !mgrB) {
  bad('g9: collision mutation not runnable — git-pin manager or default leg B missing');
} else {
  const gpats = matchStringsOf(gitPin);
  const reWidened = gpats.map((p) => p.replace(
    'datasource=(?<datasource>github-tags|github-releases)',
    'datasource=(?<datasource>github-tags|github-releases|git-refs)',
  ));
  if (reWidened.join('') === gpats.join('')) {
    bad('g9: collision mutation not runnable — git-pin capture is not the narrowed github-tags|github-releases alternation (git-refs still in the group?)');
  } else {
    const widenedDeps = [];
    let err = null;
    for (const pat of reWidened) {
      try {
        for (const m of textGptBe.matchAll(new RegExp(pat, 'g'))) {
          const g = m.groups || {};
          widenedDeps.push({
            datasource: g.datasource || '',
            depName: g.depName || '',
            registryUrl: '',
            currentValue: g.currentValue || '',
            currentDigest: g.currentDigest || '',
            branch: g.branch || '',
          });
        }
      } catch (e) { err = e.message; }
    }
    const bKeys = new Set(runManager(mgrB, textGptBe).deps.map((d) => effKey(mgrB, d)));
    const hits = widenedDeps.filter((d) => bKeys.has(effKey({ datasourceTemplate: 'git-refs' }, d)));
    if (err) bad(`g9: collision mutation broken — re-widened git-pin regex is invalid: ${err}`);
    else if (hits.length > 0) ok(`g9: mutation live — git-refs back in the git-pin group re-extracts assafelovic/gpt-researcher and collides with the default leg (g2/g7 would fail)`);
    else bad('g9: mutation dead — re-adding git-refs to the git-pin group produced no extraction on the gpt-researcher file (the group shape the split depends on is unenforced)');
  }
}

console.log(`=== dockerfile-pins: ${pass} passed, ${fail} failed ===`);
process.exit(fail === 0 ? 0 : 1);
EOF

node "$TMPDIR_PINS/check.mjs" "$RENOVATE" "$TMPDIR_PINS/branch-fixture/Dockerfile" "${REAL_DOCKERFILES[@]}"
