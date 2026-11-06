#!/usr/bin/env bash
# C07 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the C06
# reference port replicated into /home/coder/HomeAssistant (HA
# packages/automations/dashboards repo), with this repo's deltas: the
# hand-authored cost-title plugin + extensions/ stay BYTE-IDENTICAL owner
# files, the Services set + test law fit a YAML-config repo, and
# Repo identity: HomeAssistant. Uncommitted-dirty-main, THIS CARD ONLY.
#
# Contract source: chunks/C07.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC1] t3[AC1] t4[AC2] t5[AC1] t6[AC3+registry-unchanged].
# Mirror of tests/multi-repo/port-lbf.sh with HomeAssistant anchors (the
# chunk names it): idempotence/--check, AGENTS.md pins, C01/C02 text greps,
# HEAD + protected-file hashes (cmp vs pre-flight), generated-agent spot
# greps, registry-unchanged greps.
#
# Pre-flight protected-file pins captured by agent-test 2026-10-31 (sha256,
# read-only): cost-title.ts b83f1d63…, group-costs 9f194003…/6f6f03b5…/2db2d828…,
# Coder.code-workspace 3063b24a… (tracked-dirty at run start — never revert).
# HomeAssistant HEAD ddd20d587fc6a92186d0cbce6d0d50270d8f4950 verified equal
# to the plan's Verified-facts pin on the same date.
#
# Red before C07 lands: ALL legs behind the .rulesync precondition gate.
# Env re-pins: HA_ROOT HA_HEAD_PIN HA_COST_TITLE_SHA HA_GC_*_SHA
# HA_CODEWORKSPACE_SHA HA_SKILLS_LOCK_SHA HA_SKILLS_TREE_SHA RUNSYNC_BIN.
#
# Usage:
#   bash tests/multi-repo/port-homeassistant.sh
#   bash tests/multi-repo/port-homeassistant.sh t2    # subset
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH

cd "$(git rev-parse --show-toplevel)"

HA="${HA_ROOT:-/home/coder/HomeAssistant}"
HEAD_PIN="${HA_HEAD_PIN:-ddd20d587fc6a92186d0cbce6d0d50270d8f4950}"
COST_TITLE_SHA="${HA_COST_TITLE_SHA:-b83f1d63e401dc0d7b41d6438559b5e1d2df089040897b407709eea3a545c710}"
GC_PKG_SHA="${HA_GC_PKG_SHA:-9f194003b801d52081de8a9f62cd86c294d8b7898d05a1a82f893e8fb6e87c9f}"
GC_INDEX_SHA="${HA_GC_INDEX_SHA:-6f6f03b50e15ad84826133fd63959af73ad5d13789a99a80f84e84ec0d6e9072}"
GC_MAIN_SHA="${HA_GC_MAIN_SHA:-2db2d8285771789fa81c6690dfb3abf61c2073778038a88df906a5585ba5d1c5}"
CODEWS_SHA="${HA_CODEWORKSPACE_SHA:-3063b24a4ec1cb73bc50b3bc0aa750f903d79f80169c69879c22dfb09faaf88c}"
SKILLS_LOCK_SHA="${HA_SKILLS_LOCK_SHA:-ae0801939fbf0e710966c5d8a7fa9a07b1ea1011d995a8c65366eb6e0b136dd5}"
SKILLS_TREE_SHA="${HA_SKILLS_TREE_SHA:-bb16be1d43b0f12c354486c5f349081c7db1e0014e3f71e352f9be729f22654f}"

PLAIN_AGENTS=(agent-coord agent-coord-local agent-coord-pr
              agent-board-coord agent-board-coord-local agent-board-coord-pr
              agent-board agent-plan agent-research agent-test
              agent-dev-local agent-dev-pr agent-review agent-fuser
              ask code debug planner review dev dev-local dev-pr)

find_rulesync() {
  if [ -n "${RUNSYNC_BIN:-}" ] && [ -x "${RUNSYNC_BIN}" ]; then printf '%s' "$RUNSYNC_BIN"; return 0; fi
  if command -v rulesync >/dev/null 2>&1; then command -v rulesync; return 0; fi
  local cand
  cand=$(ls -1 "$HOME"/.nvm/versions/node/*/bin/rulesync 2>/dev/null | sort -V | tail -n 1 || true)
  [ -n "$cand" ] && { printf '%s' "$cand"; return 0; }
  return 1
}

surface_digest() {
  local repo="$1"
  ( cd "$repo" \
    && find -L .opencode/agents .opencode/commands .opencode/skills -type f 2>/dev/null | LC_ALL=C sort \
       | xargs -d '\n' sha256sum 2>/dev/null; \
     sha256sum AGENTS.md 2>/dev/null ) | sha256sum | awk '{print $1}'
}

checks=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -d "$HA" ] || fail "port-homeassistant: target repo $HA does not exist"

require_port() {
  [ -d "$HA/.rulesync" ] || fail "${1:-t1}: $HA has no .rulesync/ — the C07 port has not landed; no machinery runs in a pre-port repo"
}

# --- t1: generate idempotence + --check (C07 AC1, C06 AC1-equivalent) ---------
if want t1; then
  require_port t1
  rulesync_bin=$(find_rulesync) || fail "t1: rulesync not found (PATH / ~/.nvm / RUNSYNC_BIN)"
  d0=$(surface_digest "$HA")
  ( cd "$HA" && "$rulesync_bin" generate >/tmp/opencode/port-ha-generate1.log 2>&1 ) \
    || { tail -n 20 /tmp/opencode/port-ha-generate1.log >&2; fail 't1: rulesync generate failed inside HomeAssistant'; }
  d1=$(surface_digest "$HA")
  ( cd "$HA" && "$rulesync_bin" generate >/tmp/opencode/port-ha-generate2.log 2>&1 ) || fail 't1: second generate failed'
  d2=$(surface_digest "$HA")
  [ "$d1" = "$d2" ] || fail "t1: second generate not a no-op ($d1 -> $d2)"
  [ "$d0" = "$d1" ] || fail "t1: landed port stale — first generate changed the surface ($d0 -> $d1)"
  ( cd "$HA" && "$rulesync_bin" generate --check >/tmp/opencode/port-ha-check.log 2>&1 ) \
    || { tail -n 20 /tmp/opencode/port-ha-check.log >&2; fail 't1: rulesync generate --check red in HomeAssistant'; }
  ok "t1: HomeAssistant generate idempotent twice + --check green ($rulesync_bin)"

  [ -L "$HA/.agents/agents" ] || fail "t1: HomeAssistant .agents/agents not swapped to a symlink (C06 recipe verbatim)"
  [ -L "$HA/.agents/commands" ] || fail "t1: HomeAssistant .agents/commands not swapped to a symlink"
  missing=""
  for a in "${PLAIN_AGENTS[@]}"; do
    [ -f "$HA/.opencode/agents/$a.md" ] || missing="$missing $a"
  done
  [ -z "$missing" ] || fail "t1: generated agents missing:$missing"
  grep -q 'enabled: false' "$HA/.agents/loops/pipeline-worker.md" \
    || fail "t1: ported loop not enabled:false (human-owned scheduler, DECISIONS)"
  ok "t1: symlinks swapped, all ${#PLAIN_AGENTS[@]} plain agents present, loop ships disabled"
fi

# --- t2: AGENTS.md pins (C07 AC1, delta anchors) ------------------------------
if want t2; then
  A="$HA/AGENTS.md"
  [ -f "$A" ] || fail "t2: $A missing"
  grep -q 'Repo identity: HomeAssistant' "$A" \
    || fail "t2: AGENTS.md lacks 'Repo identity: HomeAssistant' (exact spelling, OQ-B2)"
  # "not the default picker" parenthetical is legal; only an UNqualified
  # claim is the bug (mirrors port-lbf.sh).
  grep 'Repo identity:' "$A" | grep -i 'default picker' | grep -qviE 'not[^a-z]*default picker' \
    && fail "t2: HomeAssistant must NOT claim the default picker (SpencersLab is the only one)"
  # YAML-config repo test law (C07 Tasks): machinery check + sanity greps.
  grep -q 'rulesync generate --check' "$A" \
    || fail "t2: the pipeline test law (rulesync generate --check for machinery chunks) did not land"
  if ! grep -q 'yamllint' "$A" && ! grep -qi 'grep' "$A"; then
    fail "t2: no YAML-sanity leg in the test law — yamllint-if-installed or pure greps (C07: probe once, record what the survey found)"
  fi
  grep -q '.agents/plans' "$A" || fail "t2: no plan-folder section"
  grep -q 'cf-93' "$A" || fail "t2: working-mode paragraph missing (cf-93 card-scoped uncommitted port)"
  if grep -q 'helm lint' "$A" || grep -qw helm "$A"; then
    fail "t2: helm/GitOps law text leaked into HomeAssistant AGENTS.md (C06 AC2 equivalence)"
  fi
  if grep -qi 'uv run pytest' "$A"; then
    fail "t2: LBF's pytest law leaked into HomeAssistant — this repo has NO pytest harness (C07 Tasks)"
  fi
  ok "t2: identity + YAML-repo test law + plan section + working-mode note landed; no helm/pytest leakage"
fi

# --- t3: C01/C02 board texts (C07 AC1) ------------------------------------------
if want t3; then
  require_port t3
  SK="$HA/.opencode/skills/boards/SKILL.md"
  [ -f "$SK" ] || fail "t3: ported boards skill missing"
  if python3 - "$SK" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)

def near(anchor, tokens, window=600):
    for m in re.finditer(anchor, text, re.I):
        seg = text[max(0, m.start() - window):m.end() + window]
        if all(re.search(t, seg, re.I) for t in tokens):
            return True
    return False

for anchor, tokens, window in [
    (r'Repo:', [r'human-created', r'never agent-created or agent-mutated'], 500),
    (r'default\s+picker', [r'Repo:', r'eligible|belongs'], 700),
    (r'Repo:', [r'never', r'claim'], 300),
    (r'Repo identity', [r'basename|canonical', r'NEEDS_INFO', r'never guess'], 1200),
]:
    if not near(anchor, tokens, window):
        bad(f'ported boards skill lost anchors: {anchor!r} + {tokens}')
for spelling in ('SpencersLab', 'HomeAssistant', 'Home-Assistant-Label-based-Features', 'brother-ptouch-automation'):
    if spelling not in text:
        bad(f'spelling {spelling!r} missing from the filter table')
# OQ-D1 HomeAssistant Services set.
if not near(r'Services', [r'dwains-dashboard'], 900):
    bad('HomeAssistant Services checklist missing its work targets (dwains-dashboard, blueprints, esphome, …)')
for tok in ('blueprints', 'esphome', 'packages'):
    if tok not in text:
        bad(f'Services target {tok!r} missing (C07 Tasks checklist)')
if 'custom_components' in text or 'hacs' in text:
    bad("LBF's Services set (custom_components/hacs) leaked into the HomeAssistant port")
print('ok: t3 — HomeAssistant boards skill: C01 filter + identity + spellings + this repo\'s Services set (C07 AC1)')
PY
  then checks=$((checks + 1)); else fail 't3: the boards contract is not satisfied (reason printed above)'; fi

  HR="$HA/.opencode/commands/pipeline-boards-hourly.md"
  [ -f "$HR" ] || fail "t3: ported hourly command missing"
  if python3 - "$HR" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)
m = re.search(r'BOARD CHECK.*?(?=^Notes:)', text, re.M | re.S)
if not m:
    bad('no BOARD CHECK block')
block = m.group(0)
for pat in (r'get_card', r'Repo:', r'filter', r'EMPTY|no filtered-in|zero filtered-in|empty', r'≥1', r'max 5', r'fail-closed'):
    if not re.search(pat, block):
        bad(f'ported BOARD CHECK lacks {pat!r} (post-C02 copy required)')
print('ok: t3: HomeAssistant hourly command carries the repo-filtered BOARD CHECK (C07 AC1)')
PY
  then checks=$((checks + 1)); else fail 't3: the hourly contract is not satisfied (reason printed above)'; fi
fi

# --- t4: HEAD + protected owner files (C07 AC2) ---------------------------------
if want t4; then
  cur=$(git -C "$HA" rev-parse HEAD) || fail "t4: could not read HEAD in $HA"
  [ "$cur" = "$HEAD_PIN" ] || fail "t4: HomeAssistant HEAD moved ($cur != $HEAD_PIN) — NOTHING committed in the target (plan Verified facts; env re-pin only for owner commits, which this card forbids)"
  ok "t4: HomeAssistant HEAD pin holds ($cur)"

  # Owner files: byte-identical to the pre-flight captures (cmp semantics via
  # sha; the port copies plugins IN without touching these).
  sha=$(sha256sum "$HA/.opencode/plugin/cost-title.ts" 2>/dev/null | awk '{print $1}')
  [ "$sha" = "$COST_TITLE_SHA" ] || fail "t4: cost-title.ts changed ($sha != pre-flight $COST_TITLE_SHA) — OWNER FILE read-only to this run (C07 pre-flight)"
  for pair in "panel/index.html:$GC_INDEX_SHA" "panel/main.js:$GC_MAIN_SHA" "package.json:$GC_PKG_SHA"; do
    rel="${pair%%:*}"; want_sha="${pair#*:}"
    s=$(sha256sum "$HA/.opencode/extensions/group-costs/$rel" 2>/dev/null | awk '{print $1}')
    [ "$s" = "$want_sha" ] || fail "t4: group-costs/$rel changed ($s != pre-flight $want_sha) — owner files untouched (AC2)"
  done
  s=$(sha256sum "$HA/Coder.code-workspace" 2>/dev/null | awk '{print $1}')
  [ "$s" = "$CODEWS_SHA" ] || fail "t4: Coder.code-workspace (tracked-dirty at run start) changed ($s != pre-flight $CODEWS_SHA) — never revert pre-existing dirt"
  ok "t4: cost-title.ts + extensions/group-costs + Coder.code-workspace byte-identical to pre-flight"

  # AC2: three pipeline plugins present ALONGSIDE the kept one; no aislop-gate.
  for p in pipeline-locks question-notify board-context; do
    [ -f "$HA/.opencode/plugin/$p/index.ts" ] || fail "t4: plugin $p missing — copy IN without touching cost-title.ts (C07 Tasks)"
  done
  [ -d "$HA/.opencode/plugin/aislop-gate" ] && fail 't4: aislop-gate was ported — excluded by DECISIONS' || true
  ok "t4: three pipeline plugins landed alongside cost-title.ts; aislop-gate correctly absent"
fi

# --- t5: generated-agent spot greps (C07 AC1) -----------------------------------
if want t5; then
  require_port t5
  if python3 - "$HA" <<'PY'
import glob, os, sys, yaml

repo = sys.argv[1]
def bad(msg):
    print(f'FAIL: t5 {msg}', file=sys.stderr)
    sys.exit(1)

def fm(path):
    lines = open(path).read().splitlines()
    if not lines or lines[0].strip() != '---':
        return None
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
    return yaml.safe_load('\n'.join(lines[1:end])) or {} if end else None

def perms(path):
    data = fm(path)
    if data is None:
        bad(f'{path}: no parsable frontmatter')
    return {(p.get('action'), p.get('resource'), p.get('effect')) for p in data.get('permissions') or []}

files = sorted(glob.glob(os.path.join(repo, '.opencode/agents/*.md')))
if not files:
    bad('no generated agents in HomeAssistant')
for f in files:
    if ('question', '*', 'allow') not in perms(f):
        bad(f'{f}: question allow row missing — hard rule on EVERY generated agent')
dvlp = perms(os.path.join(repo, '.opencode/agents/agent-dev-local.md'))
for row in (('edit', 'tests/**', 'deny'), ('edit', '.agents/plans/**', 'deny'), ('edit', '.rulesync/**', 'ask')):
    if row not in dvlp:
        bad(f'agent-dev-local lost {row}')
if any(r.startswith('helm ') for (a, r, e) in dvlp if a == 'shell' and e == 'allow'):
    bad('helm shell rows leaked into the HomeAssistant dev-local allow-list')
coord = perms(os.path.join(repo, '.opencode/agents/agent-coord-local.md'))
launchable = {r for (a, r, e) in coord if a == 'subagent' and e == 'allow'}
for need in ('agent-plan', 'agent-test', 'agent-dev-local', 'agent-review', 'agent-research'):
    if need not in launchable:
        bad(f'coord roster lost {need}')
print(f'ok: t5 — question allowed in all {len(files)} agents, dev denies + coord roster spot-greps green')
PY
  then checks=$((checks + 1)); else fail 't5: the generated-agent greps failed (reason above)'; fi

  for s in agent-board-coord-gate.sh kickoff-mint-branch.sh kickoff-warm-location.sh session-origin.sh board-preload-probe.sh; do
    [ -f "$HA/scripts/$s" ] || fail "t5: scripts/$s not copied into HomeAssistant"
  done
  [ -d "$HA/.agents/plans/templates" ] || fail "t5: plan templates missing in HomeAssistant"
  ( cd "$HA" && bash scripts/agent-board-coord-gate.sh --help >/dev/null 2>&1 ) \
    || fail "t5: gate script --help fails inside HomeAssistant"
  ok "t5: five scripts + templates + runnable gate landed in HomeAssistant"
fi

# --- t6: registry + overlay-absence (C07 AC1 AC3) --------------------------------
if want t6; then
  sha=$(sha256sum "$HA/skills-lock.json" | awk '{print $1}')
  [ "$sha" = "$SKILLS_LOCK_SHA" ] || fail "t6: HomeAssistant skills-lock.json changed ($sha != pre-port $SKILLS_LOCK_SHA)"
  tree=$( (cd "$HA" && find .agents/skills -type f | LC_ALL=C sort | xargs -d '\n' sha256sum 2>/dev/null) | sha256sum | awk '{print $1}')
  [ "$tree" = "$SKILLS_TREE_SHA" ] || fail "t6: .agents/skills tree changed ($tree != pre-port $SKILLS_TREE_SHA) — the aurora set is untouched (AC3)"
  if git -C "$HA" diff --name-only HEAD -- .agents/skills/ skills-lock.json | grep .; then
    fail "t6: git diff shows registry changes in HomeAssistant (AC1/AC3: byte-unchanged)"
  fi
  ok "t6: skills-lock.json + .agents/skills byte-unchanged vs pre-port pins (aurora set untouched)"

  # No overlay agents yet — C09's scope (AC3). Once C09 lands in wave 5 the
  # leg flips to "overlays present is expected"; the final whole-plan review
  # runs with C09 done, so the guard self-releases on overlay sources.
  if [ -f "$HA/.rulesync/subagents/agent-ha-dev.md" ]; then
    ok "t6: C09 overlays already landed (agent-ha-dev source exists) — the no-overlays-yet leg transfers to tests/multi-repo/ha-overlay-agents.sh"
  else
    if find "$HA/.opencode/agents" "$HA/.rulesync/subagents" -name 'agent-ha-*' 2>/dev/null | grep .; then
      fail "t6: agent-ha-* surfaced while no overlay sources exist — C07 ships the plain set ONLY (AC3, overlays are C09)"
    fi
    ok "t6: no overlay agents before C09 (plain set + folded standalones exactly)"
  fi
fi

printf 'PASS: cf-93 C07 port-homeassistant contract (%d ok)\n' "$checks"
