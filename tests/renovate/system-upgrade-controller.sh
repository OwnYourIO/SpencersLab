#!/usr/bin/env bash
# renovate manages the k3s system-upgrade-controller (AD-66)
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C04).
#
# Pins chunks/C04.md "## Tests": the new regex custom manager in
# renovate.json's customManagers — depNameTemplate, git-tags datasource, the
# file pattern scoped to exactly the SUC manifest, the matchStrings capturing
# the CURRENT v0.14.2 pin (a manual drift of the pin without the config =
# loud), and the target file still carrying a plain `targetRevision:` line
# for the regex to bite.
#
# The manager's regexes are READ FROM renovate.json at run time and executed
# in node against the target file — the sibling dockerfile-pins.sh mechanism:
# the checks bind to the config dev actually writes, not to a copy of it, and
# node (not python) applies them so Renovate's exact JS-regex semantics are
# what's verified. The MCP offline trio (validate_config + lint_config +
# preview_custom_manager) is C04's other gate, run by dev/review in-session.
#
# AC trace: t1[C04 AC1-AC2 — manager shape pins + file-pattern scoping]
# t2[AC2 — exactly one extraction of rancher/system-upgrade-controller @
# v0.14.2] t3[AC4 — the manifest keeps the plain targetRevision line; the
# pin is not hand-moved in this ticket].
#
# Red posture: t1/t2 DESIGNED RED until C04 dev lands the manager (verified
# absent at authoring 2026-11-01 — no system-upgrade-controller depName in
# renovate.json; the reds name the missing manager, never a harness fault).
# t3 is GREEN at base and HOLD: it turns red the moment someone moves the
# pin by hand (the no-hand-bump rule) or comments the line so the regex
# stops matching.
#
# Usage:
#   bash tests/renovate/system-upgrade-controller.sh          # t1 t2 t3
#   bash tests/renovate/system-upgrade-controller.sh t3       # subset
set -u
cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root"; exit 2; }

RENOVATE="renovate.json"
SUC="charts/base/templates/k3s-system-upgrade-controller.yaml"
PIN="v0.14.2"
DEP="rancher/system-upgrade-controller"

# node comes from nvm in this environment; a login shell may not have it.
if ! command -v node >/dev/null 2>&1; then
  export NVM_DIR=/home/coder/.nvm
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
fi
command -v node >/dev/null 2>&1 || { echo "fail: node is not available (PATH and nvm)"; exit 1; }

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  WANT[t1]=1; WANT[t2]=1; WANT[t3]=1
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-3]$ ]] || fail "unknown check id '$a' (expected t1..t3)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$RENOVATE" ] || fail "harness: $RENOVATE missing"
[ -f "$SUC" ] || fail "harness: $SUC missing"

# --- t3: the manifest stays plain and un-moved (green now, HOLD) --------------------
if want t3; then
  grep -qE "^[[:space:]]*targetRevision:[[:space:]]*v0\.14\.2[[:space:]]*$" "$SUC" \
    || fail "t3[C04 AC4]: $SUC no longer carries a plain 'targetRevision: v0.14.2' line — either the pin moved by hand (forbidden — renovate PRs future bumps, the no-hand-bump rule) or the line was reshaped so the manager's regex can no longer bite; C04 keeps the manifest byte-quiet"
  ok "t3[C04 AC4]: the SUC manifest still carries the plain targetRevision: v0.14.2 line (no hand-bump, regex-bitable)"
fi

# --- t1: the manager block itself -----------------------------------------------------
if want t1; then
  if ! node - "$RENOVATE" "$SUC" "$DEP" <<'EOF'
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const [cfgPath, sucPath, DEP] = process.argv.slice(2);
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
let rc = 0;
const bad = (m) => { console.log(`FAIL-REASON: ${m}`); rc = 1; };

const managers = Array.isArray(cfg.customManagers) ? cfg.customManagers : [];
const mgr = managers.find((m) => m.customType === 'regex' && m.depNameTemplate === DEP);
if (!mgr) {
  bad(`t1[C04 T1]: renovate.json carries no regex customManager with depNameTemplate "${DEP}" — the AD-66 manager has not landed (designed red before C04 dev, not a harness fault)`);
  process.exit(1);
}
if (mgr.datasourceTemplate !== 'git-tags')
  bad(`t1[C04 AC1]: datasourceTemplate is ${JSON.stringify(mgr.datasourceTemplate)}, want "git-tags" — SUC releases are git tags (the k3s manager in this file is the precedent shape)`);
if (!mgr.description)
  bad("t1[C04 T1]: the manager lacks the description field every sibling customManager carries (the file's own convention)");

const pats = Array.isArray(mgr.managerFilePatterns) ? mgr.managerFilePatterns : [];
if (!pats.length) bad('t1[C04 T1]: managerFilePatterns is empty — the manager would match nothing');
// Renovate's "/pattern/flags" strings -> live RegExp objects.
const asRegex = (p) => {
  const m = /^\/(.*)\/([a-z]*)$/.exec(p);
  return new RegExp(m ? m[1] : p, m ? m[2] : '');
};
if (!pats.some((p) => asRegex(p).test(sucPath)))
  bad(`t1[C04 AC2]: none of managerFilePatterns ${JSON.stringify(pats)} matches ${sucPath} — the manager would never read the SUC manifest`);
// repo-wide accidental-match audit (AC2 "zero unintended new matches"): the
// pattern set must hit EXACTLY the SUC file among all tracked YAMLs.
const yamls = execSync('git ls-files "*.yaml" "*.yml"', { encoding: 'utf8' }).split('\n').filter(Boolean);
const hits = yamls.filter((f) => pats.some((p) => { try { return asRegex(p).test(f); } catch { return false; } }));
if (hits.length !== 1 || hits[0] !== sucPath)
  bad(`t1[C04 AC2]: the file pattern set matches ${JSON.stringify(hits)} — expected EXACTLY ${sucPath}; a broader pattern silently changes what OTHER files renovate extracts (the dev-run preview_custom_manager whole-repo leg must agree)`);
if (!rc) console.log('ok: t1 — manager shape pinned: depName template, git-tags datasource, description convention, SUC-scoped file pattern (exact single hit repo-wide)');
process.exit(rc);
EOF
  then fail "t1[C04 AC1/AC2]: the SUC manager shape pins failed (reason above)"; fi
  ok "t1[C04 AC1]: renovate.json's SUC customManager matches the pinned shape"
fi

# --- t2: the extraction, through the config's own regexes -----------------------------
if want t2; then
  if ! node - "$RENOVATE" "$SUC" "$DEP" "$PIN" <<'EOF'
import { readFileSync } from 'node:fs';

const [cfgPath, sucPath, DEP, PIN] = process.argv.slice(2);
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
const text = readFileSync(sucPath, 'utf8');
let rc = 0;
const bad = (m) => { console.log(`FAIL-REASON: ${m}`); rc = 1; };

const managers = Array.isArray(cfg.customManagers) ? cfg.customManagers : [];
const mgr = managers.find((m) => m.customType === 'regex' && m.depNameTemplate === DEP);
if (!mgr) {
  bad('t2[C04 T2]: no regex customManager with depNameTemplate "' + DEP + '" in renovate.json — the extraction cannot be verified before the manager lands (designed red before C04 dev)');
  process.exit(1);
}
const strs = (Array.isArray(mgr.matchStrings) ? mgr.matchStrings : []).map((s) => (typeof s === 'string' ? s : s.match));
if (!strs.length) bad('t2[C04 T2]: matchStrings empty — nothing to extract');
let extracted = [];
for (const pat of strs) {
  let re;
  try { re = new RegExp(pat, 'g'); }
  catch (e) { bad(`t2[C04 AC1]: matchString ${JSON.stringify(pat)} is not a valid regex: ${e.message}`); continue; }
  for (const m of text.matchAll(re)) extracted.push(m.groups?.currentValue);
}
if (extracted.length !== 1)
  bad(`t2[C04 AC2]: the manager extracts ${JSON.stringify(extracted)} from the SUC manifest — want EXACTLY one dep at the current pin (a doubled capture means the pattern over-matches the file)`);
else if (extracted[0] !== PIN)
  bad(`t2[C04 AC2]: extracted currentValue ${JSON.stringify(extracted[0])} != the manifest's ${PIN} — the matchStrings drifted from the pin; the capture must track the CURRENT pin so a hand-move stays loud (the no-hand-bump rule)`);
if (!rc) console.log('ok: t2 — matchStrings extract exactly one rancher/system-upgrade-controller @ v0.14.2 from the target file');
process.exit(rc);
EOF
  then fail "t2[C04 AC2]: the extraction contract failed (reason above)"; fi
  ok "t2[C04 AC2]: the manager extracts rancher/system-upgrade-controller at the pinned v0.14.2"
fi

printf 'PASS: renovate system-upgrade-controller management checks (%d ok)\n' "$checks"
