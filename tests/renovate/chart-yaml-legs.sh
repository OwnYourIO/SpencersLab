#!/usr/bin/env bash
# C01 acceptance checks (2026-11-cf-95-bug-fix-renovate), AC3: the contracts
# of the Chart.yaml-side custom manager (#9 "Override changelog/source URL")
# and of the renovate.json packageRules, plus the permanent dead-annotation
# enumeration gate over tracked Dockerfiles.
#
#  - #9 registryUrl capture (card failures #1/#2): the generic \S+ capture
#    grabbed mariadb-operator's `repository: oci://...` line and fed the OCI
#    URL to the helm datasource, which fetches <registryUrl>/index.yaml — the
#    card's `ERROR: cannot parse url`. The RE2-safe fix scopes the capture to
#    https?:// (DECISIONS D6): no lookahead the runner's RE2 would reject,
#    and an oci:// dependency block then produces NO match at all.
#  - the `.agents/**` packageRule (card failure #3): vendored hash-locked
#    skill content must never receive dependency PRs (DECISIONS D2); its
#    template placeholders are not published packages.
#  - the negative packageRule pin: the draft's grafana-16541 SILENCE rule was
#    superseded by user answer #3 (live-successor replacement in C02) — a
#    resurrected silence rule would hide that replacement.
#  - the containers/ datasource enumeration gate (DECISIONS D10): the dead
#    `datasource=docker depName=debian` annotation on the coder-workspace
#    FROM line is removed, and no future `# renovate:` datasource token that
#    no Dockerfile-facing leg can capture may return silently.
#
# The regexes under test are extracted from renovate.json at run time (never
# duplicated here) and executed over the real Chart.yaml / .agents files in
# node, so the checks bind to the config that dev actually writes, not to a
# copy of it. Mutation checks (k6) prove the exclusion assertions are live,
# per the RE2-safety convention in DECISIONS.md (the local repro had no RE2
# and fell back to RegExp — patterns are validated by Node RegExp emulation).
#
# This repo has no unit-test suite (AGENTS.md "Pipeline specifics"); each
# check prints one pass/fail line; any fail makes the script exit non-zero.
# Hermetic: no network — the mariadb/chrome/grafana liveness probes stay in
# plan Commands for dev/review.
#
# Usage: bash tests/renovate/chart-yaml-legs.sh
#   RENOVATE_CONFIG=<abs path> bash tests/renovate/chart-yaml-legs.sh
# RENOVATE_CONFIG defaults to the repo's renovate.json; the override exists to
# run the same contract against a simulated final config (same convention as
# dockerfile-pins.sh).

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

RENOVATE="${RENOVATE_CONFIG:-renovate.json}"
HOME_CHART="services/home/prod/Chart.yaml"

# node comes from nvm in this environment; a login shell may not have it.
if ! command -v node >/dev/null 2>&1; then
  export NVM_DIR=/home/coder/.nvm
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
fi

[ -f "$RENOVATE" ] || { echo "fail: precondition: $RENOVATE is missing"; exit 1; }
[ -f "$HOME_CHART" ] || { echo "fail: precondition: $HOME_CHART is missing"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "fail: node is not available (PATH and nvm)"; exit 1; }

mapfile -t OCI_CHARTS < <(git ls-files | grep -E '(^|/)Chart\.yaml$' | xargs grep -l 'repository: oci://' 2>/dev/null)
[ "${#OCI_CHARTS[@]}" -ge 1 ] || { echo "fail: precondition: no tracked Chart.yaml carries a repository: oci:// line"; exit 1; }
mapfile -t REAL_DOCKERFILES < <(git ls-files 'containers' | grep -E '(^|/)Dockerfile$')
[ "${#REAL_DOCKERFILES[@]}" -ge 1 ] || { echo "fail: precondition: no tracked Dockerfiles under containers/"; exit 1; }
mapfile -t AGENTS_FILES < <(git ls-files '.agents')
[ "${#AGENTS_FILES[@]}" -ge 1 ] || { echo "fail: precondition: nothing tracked under .agents/"; exit 1; }

TMPDIR_LEGS=$(mktemp -d /tmp/opencode/chart-yaml-legs.XXXXXX) || { echo "fail: mktemp failed"; exit 2; }
trap 'rm -rf "$TMPDIR_LEGS"' EXIT

# A missing manager, a regex error, or a tuple mismatch is a fail line, never
# a crash — the script must say WHY the contract is unmet, not die on it.
cat > "$TMPDIR_LEGS/check.mjs" <<'EOF'
import { readFileSync } from 'node:fs';

const argv = process.argv.slice(2);
const cfgPath = argv[0];
// Grouped positional args: --oci <files> --home <file> --dockerfiles <files> --agents <files>
function group(flag) {
  const out = [];
  const i = argv.indexOf(flag);
  if (i === -1) return out;
  for (let j = i + 1; j < argv.length && !argv[j].startsWith('--'); j++) out.push(argv[j]);
  return out;
}
const ociCharts = group('--oci');
const dockerfiles = group('--dockerfiles');
const agentsFiles = group('--agents');
const homeChart = argv[argv.indexOf('--home') + 1];

const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
const read = (p) => readFileSync(p, 'utf8');

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`pass: ${m}`); };
const bad = (m) => { fail++; console.log(`fail: ${m}`); };

const managers = Array.isArray(cfg.customManagers) ? cfg.customManagers : [];
const matchStringsOf = (m) =>
  (Array.isArray(m.matchStrings) ? m.matchStrings : []).map((s) => (typeof s === 'string' ? s : s.match));
const patternsOf = (m) => (Array.isArray(m.managerFilePatterns) ? m.managerFilePatterns : []);

// The "Override changelog/source URL" manager (#9) is identified by its
// capture contract — a helm-datasource regex manager whose matchString
// requires the changelog|sourceUrl comment line — which both the broken and
// the fixed config share, unlike the description text.
const mgr9 = managers.find(
  (m) => m.customType === 'regex' && m.datasourceTemplate === 'helm'
    && matchStringsOf(m).some((s) => s.includes('changelog|sourceUrl')),
);
const MARIADB = ociCharts.find((p) => p.endsWith('charts/mariadb-operator/Chart.yaml'));
const EXPECTED_WEKAN = { depName: 'wekan', registryUrl: 'https://wekan.github.io/charts/', currentValue: '12.65.0', sourceUrl: 'https://github.com/wekan/wekan' };
const key = (d) => `${d.depName || ''}|${d.registryUrl || ''}|${d.currentValue || ''}|${d.sourceUrl || ''}`;

function runPatterns(pats, text) {
  const deps = [];
  for (const pat of pats) {
    let re;
    try { re = new RegExp(pat, 'g'); }
    catch (e) { return { error: `regex ${JSON.stringify(pat)} is invalid: ${e.message}` }; }
    for (const m of text.matchAll(re)) {
      const g = m.groups || {};
      deps.push({ depName: g.depName || '', registryUrl: g.registryUrl || '', currentValue: g.currentValue || '', sourceUrl: g.sourceUrl || '' });
    }
  }
  return { deps };
}

// --- k1: the manager exists ------------------------------------------------
if (!mgr9) {
  bad('k1: manager #9 not found (no regex custom manager with datasourceTemplate=helm and a changelog|sourceUrl matchString) — every #9 check below is unassessable');
} else {
  ok(`k1: manager #9 present (${JSON.stringify(matchStringsOf(mgr9).length)} matchString(s))`);

  const pats9 = matchStringsOf(mgr9);

  // --- k2 [AC3]: the registryUrl capture is https?://-scoped ----------------
  const SCOPED = '(?<registryUrl>https?://\\S+)';
  if (pats9.every((p) => p.includes(SCOPED))) {
    ok(`k2: every #9 matchString scopes the registryUrl capture to ${SCOPED} (RE2-safe OCI exclusion — D6)`);
  } else {
    bad(`k2: #9 registryUrl capture is not ${SCOPED}-scoped in: ${pats9.join(' | ')} — a generic \\S+ captures oci:// registryUrls and feeds them to the helm datasource (card ERROR "cannot parse url" on index.yaml)`);
  }

  // --- k3 [AC3]: the mariadb OCI block extracts NO dep ---------------------
  if (!MARIADB) {
    bad('k3: precondition — charts/mariadb-operator/Chart.yaml is not among the oci://-carrying Chart.yaml files detected');
  } else {
    const res = runPatterns(pats9, read(MARIADB));
    if (res.error) bad(`k3: ${res.error}`);
    else if (res.deps.length === 0) ok(`k3: #9 extracts 0 deps from ${MARIADB} (the oci:// repository block produces no match)`);
    else bad(`k3: #9 extracts ${res.deps.length} dep(s) from ${MARIADB} (${res.deps.map(key).join(' ; ')}) — the oci:// registryUrl would be fed to the helm datasource: the card's ERROR + mariadb-operator no-result`);
  }

  // --- k4 [AC3]: every other oci://-carrying Chart.yaml extracts 0 ---------
  for (const p of ociCharts.filter((x) => x !== MARIADB)) {
    const res = runPatterns(pats9, read(p));
    if (res.error) bad(`k4: ${p}: ${res.error}`);
    else if (res.deps.length === 0) ok(`k4: #9 extracts 0 deps from ${p}`);
    else bad(`k4: #9 extracts ${res.deps.length} dep(s) from ${p} (${res.deps.map(key).join(' ; ')}) — an OCI repository line must never reach the helm datasource`);
  }

  // --- k5 [AC3]: the healthy https legs are byte-unchanged ------------------
  {
    const res = runPatterns(pats9, read(homeChart));
    if (res.error) bad(`k5: ${homeChart}: ${res.error}`);
    else if (res.deps.length !== 2) bad(`k5: #9 extracts ${res.deps.length} deps from ${homeChart}, expected the 2 split wekan legs (${res.deps.map(key).join(' ; ') || '<none>'})`);
    else if (!res.deps.every((d) => key(d) === key(EXPECTED_WEKAN))) bad(`k5: #9 wekan tuples changed: ${res.deps.map(key).join(' ; ')} — expected 2x ${key(EXPECTED_WEKAN)} (C01 keeps every currently-healthy leg unchanged)`);
    else ok(`k5: #9 extracts exactly the 2 wekan deps from ${homeChart}, tuples unchanged`);
  }

  // --- k6 mutation [AC3]: swapping the capture back to \S+ re-yields the
  // mariadb oci:// dep — the exclusion in k3/k4 is live, not vacuous.
  {
    const mutated = pats9.map((p) => p.replace(SCOPED, '(?<registryUrl>\\S+)'));
    if (mutated.join('') === pats9.join('')) {
      bad(`k6: mutation not runnable — no ${SCOPED} capture present to widen (this line goes green only once k2's shape lands)`);
    } else if (!MARIADB) {
      bad('k6: mutation not runnable — mariadb Chart.yaml missing');
    } else {
      const res = runPatterns(mutated, read(MARIADB));
      const hit = !res.error && res.deps.find((d) => d.depName === 'mariadb-operator' && d.registryUrl.startsWith('oci://'));
      if (res.error) bad(`k6: mutation regex invalid: ${res.error}`);
      else if (hit) ok(`k6: mutation live — a generic \\S+ capture re-extracts ${key(hit)} with an oci:// registryUrl (k3 would fail)`);
      else bad('k6: mutation dead — widening the capture re-yields no mariadb oci:// dep (the exclusion has nothing to exclude; the test would pass vacuously)');
    }
  }
}

// --- k7 [AC3]: exactly one blanket .agents/** silence rule ------------------
{
  const rules = Array.isArray(cfg.packageRules) ? cfg.packageRules : [];
  const hits = rules.filter((r) => Array.isArray(r.matchFileNames) && r.matchFileNames.includes('.agents/**'));
  if (hits.length !== 1) {
    bad(`k7: ${hits.length} packageRules carry matchFileNames ".agents/**", expected exactly 1 — without it the built-in homeassistant-manager leg scans the vendored ha-integration-dev manifest templates (card failures pypi my-hub-api / my-service-api) and PRs against hash-locked skills-lock content (DECISIONS D2)`);
  } else {
    const r = hits[0];
    const keysOk = JSON.stringify(r.matchFileNames) === JSON.stringify(['.agents/**']);
    const enabledOk = r.enabled === false;
    const descOk = typeof r.description === 'string' && r.description.trim() !== '';
    if (keysOk && enabledOk && descOk) ok('k7: one blanket rule, matchFileNames exactly [".agents/**"], enabled === false (boolean), non-empty description (D2)');
    else bad(`k7: the .agents rule is malformed — matchFileNames ${JSON.stringify(r.matchFileNames)} (must be exactly [".agents/**"]), enabled ${JSON.stringify(r.enabled)} (must be boolean false — a string or {} value does not disable), description ${descOk ? 'ok' : 'missing'}`);
  }
}

// --- k8 [AC3 negative pin]: no rule for the superseded grafana-16541 silence
{
  const rules = Array.isArray(cfg.packageRules) ? cfg.packageRules : [];
  const blob = JSON.stringify(rules);
  if (blob.includes('Speedtest Exporter') || blob.includes('16541')) {
    bad(`k8: a packageRule mentions "Speedtest Exporter" or 16541 — the draft's SILENCE choice was superseded by user answer #3 (live-successor replacement in C02); a silence rule here would bury the dead pin instead of fixing it`);
  } else {
    ok('k8: no packageRule references the superseded grafana-16541 silence (C02 replaces the pin at its site instead)');
  }
}

// --- k9 [.agents control]: no custom regex manager extracts deps from .agents
// (the blanket k7 rule is what silences the BUILT-IN homeassistant-manifest
// leg over the same tree — that leg is not executable offline; its coverage
// is pinned by the C01 AC5 dry-run, which must show 0 lookup attempts for
// files under .agents/).
{
  const toRe = (p) => new RegExp(p.slice(1, p.lastIndexOf('/')));
  let targeted = 0, extracted = 0;
  const offenders = [];
  for (const f of agentsFiles) {
    const applying = managers.filter((m) => m.customType === 'regex' && patternsOf(m).some((p) => { try { return toRe(p).test(f); } catch { return false; } }));
    if (!applying.length) continue;
    targeted++;
    const text = read(f);
    for (const m of applying) {
      const res = runPatterns(matchStringsOf(m), text);
      if (res.error) { offenders.push(`${f}: ${res.error}`); continue; }
      extracted += res.deps.length;
      for (const d of res.deps) offenders.push(`${f} -> ${key(d)}`);
    }
  }
  if (offenders.length) bad(`k9: ${offenders.slice(0, 3).join(' ; ')}${offenders.length > 3 ? ` (+${offenders.length - 3} more)` : ''} — a custom regex manager extracts deps from .agents content; the k7 blanket rule must stay, and dev must not add a manager leg that PRs against synced content`);
  else ok(`k9: the ${targeted} tracked .agents files matched by custom-manager filePatterns produce 0 extracted deps (built-in leg silence: k7 rule + AC5 dry-run)`);
}

// --- k10 [AC3 / D10]: permanent dead-annotation enumeration gate -----------
// Supported datasource tokens = what the Dockerfile-facing legs can capture:
// the git-pin group, the containers/*/Dockerfile manager's group, and the
// two git-refs legs' datasourceTemplate. Hardcoded per chunk AC3's verbatim
// set — derivation from the config would admit manager #1's
// datasourceTemplate=docker, which belongs to chart/service templates and
// must stay OUT of this gate (that is exactly how the coder-workspace
// `datasource=docker` FROM annotation died silently: a token no
// Dockerfile-facing leg can ever match).
const SUPPORTED = ['github-tags', 'github-releases', 'git-refs', 'node-version', 'golang-version', 'forgejo-releases', 'npm'];
{
  const dead = [];
  let counted = 0;
  for (const f of dockerfiles) {
    read(f).split('\n').forEach((line, i) => {
      if (!/#\s*renovate:/.test(line)) return;
      counted++;
      const m = /#\s*renovate:\s*datasource=(\S+)(?:\s+registryUrl=\S+)?\s+depName=(\S+)/.exec(line);
      if (!m) { dead.push(`${f}:${i + 1} — "# renovate:" line no manager can parse: ${line.trim()}`); return; }
      if (!SUPPORTED.includes(m[1])) dead.push(`${f}:${i + 1} — dead annotation datasource=${m[1]} depName=${m[2]} (no Dockerfile-facing leg captures it; supported: ${SUPPORTED.join('|')})`);
    });
  }
  if (dead.length) for (const d of dead) bad(`k10: ${d}`);
  else ok(`k10: all ${counted} "# renovate:" annotations across ${dockerfiles.length} tracked Dockerfiles carry a datasource the legs capture (D10 gate)`);
}

console.log(`=== chart-yaml-legs: ${pass} passed, ${fail} failed ===`);
process.exit(fail === 0 ? 0 : 1);
EOF

node "$TMPDIR_LEGS/check.mjs" "$RENOVATE" \
  --oci "${OCI_CHARTS[@]}" \
  --home "$HOME_CHART" \
  --dockerfiles "${REAL_DOCKERFILES[@]}" \
  --agents "${AGENTS_FILES[@]}"
