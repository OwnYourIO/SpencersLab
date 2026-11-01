#!/usr/bin/env bash
# C09 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the HA overlay
# agent family in the two HA TARGET repos (repo-owned per the DECISIONS
# placement ruling — nothing lands in this repo's sources): agent-ha-dev,
# agent-ha-code, agent-ha-debug, agent-ha-custom-component authored in each
# of LBF + HomeAssistant's .rulesync/subagents/, generated there, coord
# rosters extended with the two implementers ONLY, every skill pin resolving
# in that repo's own registry, permissions mirroring the base twins.
#
# Contract source: chunks/C09.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1+AC3] t2[AC4] t3[AC5] t4[AC2+AC6].
#
# Skill-pin table comes from DECISIONS (the binding log — the contract for
# which pins are REQUIRED; dev's C09 round cross-checked live that
# /executing-plans resolves post-port, so the Tasks bullet's extra pin is
# not asserted here and is not rejected either — the absent-skill leg below
# machine-checks that everything landed resolves in the repo's own
# registry). Per repo:
#   ha-dev / ha-custom-component -> ha-integration-dev + home-assistant-best-practices
#                                    (+ labeled-features in LBF ONLY)
#   ha-code                      -> home-assistant-best-practices + home-assistant-yaml
#   ha-debug                     -> home-assistant-best-practices
#
# Pin extraction idiom: a pin is a standalone `/<skill-name>` line inside the
# generated file's "## Skills" section (the rulesync agent-body shape).
# Permission mirroring is compared on the (action, resource, effect) tuple
# SET of the generated twins — "copied verbatim from their base twins" is the
# audit contract (agents-sync references/permissions.md).
#
# Red before C09 lands: file-existence legs; the --check legs skip until the
# overlay sources exist. Never mutates anything: rulesync generate is NOT run
# here (generate --check is read-only), so this suite is safe at any review
# point. HEAD pins re-verified by agent-test 2026-10-31.
#
# Env re-pins: LBF_ROOT LBF_HEAD_PIN HA_ROOT HA_HEAD_PIN PT_ROOT PT_HEAD_PIN
#   RUNSYNC_BIN
#
# Usage:
#   bash tests/multi-repo/ha-overlay-agents.sh
#   bash tests/multi-repo/ha-overlay-agents.sh t2
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH

cd "$(git rev-parse --show-toplevel)"

LBF="${LBF_ROOT:-/home/coder/Home-Assistant-Label-based-Features}"
LBF_HEAD="${LBF_HEAD_PIN:-2ea63fdecf1b5cfe36f7ac2e1f56ce8d4bbd5e7e}"
HA="${HA_ROOT:-/home/coder/HomeAssistant}"
HA_HEAD="${HA_HEAD_PIN:-ddd20d587fc6a92186d0cbce6d0d50270d8f4950}"
PT="${PT_ROOT:-/home/coder/brother-ptouch-automation}"
PT_HEAD="${PT_HEAD_PIN:-381d72f75f7c169edb448dc3c04ea64743d6abf7}"

HA_AGENTS=(agent-ha-dev agent-ha-code agent-ha-debug agent-ha-custom-component)

find_rulesync() {
  if [ -n "${RUNSYNC_BIN:-}" ] && [ -x "${RUNSYNC_BIN}" ]; then printf '%s' "$RUNSYNC_BIN"; return 0; fi
  if command -v rulesync >/dev/null 2>&1; then command -v rulesync; return 0; fi
  local cand
  cand=$(ls -1 "$HOME"/.nvm/versions/node/*/bin/rulesync 2>/dev/null | sort -V | tail -n 1 || true)
  [ -n "$cand" ] && { printf '%s' "$cand"; return 0; }
  return 1
}

checks=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-4]$ ]] || fail "unknown test id '$a' (expected t1..t4)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

for repo in "$LBF" "$HA"; do
  [ -d "$repo" ] || fail "ha-overlay-agents: target repo $repo missing"
done

# --- t1: 4 sources + 4 twins per repo, --check green, pin-vs-registry --------
if want t1; then
  for pair in "LBF:$LBF:lbf" "HomeAssistant:$HA:ha"; do
    label="${pair%%:*}"; rest="${pair#*:}"; repo="${rest%%:*}"; tag="${rest##*:}"
    [ -d "$repo/.rulesync" ] || fail "t1: $label has no .rulesync/ — C06/C07 must land before C09 (waves 1→4)"
    missing=""
    for a in "${HA_AGENTS[@]}"; do
      [ -f "$repo/.rulesync/subagents/$a.md" ] || missing="$missing source:$a"
      [ -f "$repo/.opencode/agents/$a.md" ] || missing="$missing twin:$a"
    done
    [ -z "$missing" ] || fail "t1: $label missing overlay files:$missing (8 sources + 8 twins total, AC1; whole-value names per the overlay-name law)"
    ok "t1: $label — 4 sources + 4 generated twins exist"

    rulesync_bin=$(find_rulesync) || fail "t1: rulesync not found"
    ( cd "$repo" && "$rulesync_bin" generate --check >/tmp/opencode/overlay-$tag-check.log 2>&1 ) \
      || { tail -n 20 "/tmp/opencode/overlay-$tag-check.log" >&2; fail "t1: generate --check red in $label after the overlay landed (AC1)"; }
    ok "t1: $label — rulesync generate --check exits 0 with the overlays in the set"
  done

  # Pin-vs-registry table (AC3): every DECISIONS pin resolves in THAT repo,
  # appears as a standalone pin line in the twin, and labeled-features is
  # LBF-only.
  if python3 - "$LBF" "$HA" <<'PY'
import os, re, sys

lbf, ha = sys.argv[1], sys.argv[2]

TABLE = {
    'agent-ha-dev': ['ha-integration-dev', 'home-assistant-best-practices'],
    'agent-ha-custom-component': ['ha-integration-dev', 'home-assistant-best-practices'],
    'agent-ha-code': ['home-assistant-best-practices', 'home-assistant-yaml'],
    'agent-ha-debug': ['home-assistant-best-practices'],
}
EXTRA_LBF = {'agent-ha-dev': ['labeled-features'],
             'agent-ha-custom-component': ['labeled-features']}

def registry_names(repo):
    out = set()
    for d in ('.opencode/skills', '.agents/skills', 'skills'):
        p = os.path.join(repo, d)
        if os.path.isdir(p):
            out |= {n for n in os.listdir(p) if os.path.isdir(os.path.join(p, n))}
    return out

def skills_section(path):
    text = open(path).read()
    m = re.search(r'^## Skills\s*$(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not m:
        return None
    return m.group(1)

def pins(section):
    return set(re.findall(r'^/([a-z0-9][a-z0-9-]*)$', section, re.M))

def bad(msg):
    print(f'FAIL: t1 {msg}', file=sys.stderr)
    sys.exit(1)

for repo, name in ((lbf, 'LBF'), (ha, 'HomeAssistant')):
    reg = registry_names(repo)
    for agent, want_pins in TABLE.items():
        twin = os.path.join(repo, '.opencode/agents', agent + '.md')
        sec = skills_section(twin)
        if sec is None:
            bad(f'{name} {agent} twin has no "## Skills" section to pin in')
        got = pins(sec)
        for p in want_pins:
            if p not in reg:
                bad(f'{name}: DECISIONS pin {p!r} is not in this repo\'s registry — the table must be corrected or the skill vendored (pins must resolve locally)')
            if p not in got:
                bad(f'{name} {agent} does not pin /{p} (DECISIONS pin table)')
        for p in EXTRA_LBF.get(agent, []):
            if name == 'LBF':
                if p not in reg or p not in got:
                    bad(f'LBF {agent} must pin the self-written /{p} (parity law; registry has it)')
            else:
                if p in got:
                    bad(f'HomeAssistant {agent} pins /{p} — labeled-features is LBF-only (AC3); it is not in the HomeAssistant registry')
        # Every pin the twin carries must resolve in this repo's registries —
        # the absent-skill machine-check. The DECISIONS table above pins the
        # REQUIRED set; anything extra (e.g. /executing-plans, which resolves
        # post-port in both targets — dev's live C09 cross-check) passes so
        # long as it exists in the repo, fails if it does not.
        real_missing = sorted(x for x in got if x not in reg)
        if real_missing:
            bad(f'{name} {agent} pins skills absent from every registry: {real_missing}')
print('ok: t1 — per-agent skill-pin-vs-registry table green in both repos; labeled-features LBF-only (C09 AC3)')
PY
  then checks=$((checks + 1)); else fail 't1: the pin-vs-registry table is not satisfied (reason above)'; fi
fi

# --- t2: permission audit vs base twins (C09 AC4) ------------------------------
if want t2; then
  PAIRS=(agent-ha-dev:agent-dev-local agent-ha-custom-component:agent-dev-local agent-ha-code:code agent-ha-debug:debug)
  for repo in "$LBF" "$HA"; do
    label=HA; [ "$repo" = "$LBF" ] && label=LBF
    if python3 - "$repo" "${PAIRS[@]}" <<'PY'
import os, sys, yaml

repo = sys.argv[1]
pairs = [p.split(':') for p in sys.argv[2:]]
def bad(msg):
    print(f'FAIL: t2 {msg}', file=sys.stderr)
    sys.exit(1)

def perms(path):
    lines = open(path).read().splitlines()
    if not lines or lines[0].strip() != '---':
        bad(f'{path}: no frontmatter')
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
    if end is None:
        bad(f'{path}: unterminated frontmatter')
    data = yaml.safe_load('\n'.join(lines[1:end])) or {}
    return data, {(p.get('action'), p.get('resource'), p.get('effect')) for p in data.get('permissions') or []}

for ha_agent, base in pairs:
    hp = os.path.join(repo, '.opencode/agents', ha_agent + '.md')
    bp = os.path.join(repo, '.opencode/agents', base + '.md')
    if not os.path.isfile(bp):
        bad(f'base twin {bp} missing — cannot audit {ha_agent} (C06/C07 must have landed the plain set)')
    (h_data, h_set) = perms(hp)
    (_b_data, b_set) = perms(bp)

    # Repo hard rule, universal over all four twins: question stays allowed.
    if ('question', '*', 'allow') not in h_set:
        bad(f'{ha_agent} lacks the question allow row — repo hard rule on EVERY agent')
    # AC4 rows scope by shape: the three dev-shaped denies/ask are required
    # on the dev-shaped overlays (ha-dev + ha-custom-component, base
    # agent-dev-local). ha-code/ha-debug mirror the STANDALONE code.md /
    # debug.md twins, whose grant shapes legitimately differ (code.md allows
    # tests/** by design); demanding the dev rows there would make the
    # verbatim-equality leg below unsatisfiable without moving base-twin
    # scope — which C09 forbids (permission blocks copied verbatim from the
    # approved C06/C07 twins).
    DEV_SHAPED = ('agent-ha-dev', 'agent-ha-custom-component')
    if ha_agent in DEV_SHAPED:
        for row in (('edit', 'tests/**', 'deny'), ('edit', '.agents/plans/**', 'deny'),
                    ('edit', '.rulesync/**', 'ask')):
            if row not in h_set:
                bad(f'{ha_agent} lacks the dev-shaped row {row} (agent-dev-local mirror contract, C09 AC4)')
    # "copied verbatim from their base twins" — universal, the (action,resource,effect)
    # set must equal the base twin's exactly (color/name/description may
    # differ; grants may not).
    if h_set != b_set:
        extra = sorted(h_set - b_set)
        lost = sorted(b_set - h_set)
        bad(f'{ha_agent} permissions drift from base {base}: extra={extra} lost={lost} (verbatim copy is the audit contract)')
print(f'ok: t2 — universal question-allow + verbatim-mirror audit green for all {len(pairs)} ha/base pairs; dev-shaped rows asserted on the dev-shaped overlays (C09 AC4)')
PY
    then checks=$((checks + 1)); else fail "t2: the permission audit failed for $label (reason above)"; fi
  done
fi

# --- t3: coord rosters extended, standalones not launchable (C09 AC5) ----------
if want t3; then
  for repo in "$LBF" "$HA"; do
    label=LBF; [ "$repo" = "$HA" ] && label=HomeAssistant
    if python3 - "$repo" <<'PY'
import glob, os, sys, yaml

repo = sys.argv[1]
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)

def allow_resources(path):
    lines = open(path).read().splitlines()
    end = next((i for i in range(1, len(lines)) if i > 0 and lines[i].strip() == '---'), None)
    data = yaml.safe_load('\n'.join(lines[1:end])) or {}
    return data, {(p.get('action'), p.get('resource'), p.get('effect')) for p in data.get('permissions') or []}

coords = ['agent-coord', 'agent-coord-local', 'agent-coord-pr',
          'agent-board-coord', 'agent-board-coord-local', 'agent-board-coord-pr']
seen = 0
for c in coords:
    p = os.path.join(repo, '.opencode/agents', c + '.md')
    if not os.path.isfile(p):
        bad(f'coord twin {c}.md missing in the target')
    _d, perms = allow_resources(p)
    launch = {r for (a, r, e) in perms if a == 'subagent' and e == 'allow'}
    for need in ('agent-ha-dev', 'agent-ha-custom-component'):
        if need not in launch:
            bad(f'{c} roster does not allow {need} (C09 extends implementer roles only, AC5)')
    for must_not in ('agent-ha-code', 'agent-ha-debug'):
        if must_not in launch:
            bad(f'{c} may launch {must_not} — those are standalone overlays, coord-launchable set stays plain+2 (AC5)')
    # nothing else widened: the deny-all row must still lead the roster
    if ('subagent', '*', 'deny') not in perms:
        bad(f'{c} lost the subagent deny-all default — the roster is an allow-list on top of it (hard rule: universal default first)')
    seen += 1
print(f'ok: t3 — all {seen} coord twins gained the two ha implementers, no standalone leaked into the roster, deny-all default intact')
PY
    then checks=$((checks + 1)); else fail "t3: the coord roster audit failed in $label (reason above)"; fi
  done
fi

# --- t4: naming law + HEAD pins + brother untouched (C09 AC2+AC6) -------------
if want t4; then
  for pair in "LBF:$LBF" "HomeAssistant:$HA"; do
    label="${pair%%:*}"; repo="${pair#*:}"
    if python3 - "$repo" "$label" <<'PY'
import glob, os, sys, yaml

repo, label = sys.argv[1:3]
def bad(msg):
    print(f'FAIL: t4 {msg}', file=sys.stderr)
    sys.exit(1)

names = sorted(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(repo, '.opencode/agents/*.md')))
expected = ('agent-ha-dev', 'agent-ha-code', 'agent-ha-debug', 'agent-ha-custom-component')
for e in expected:
    if e not in names:
        bad(f'{label}: {e} is not a whole-value generated agent name (overlay-name law: names lead with the ha marker and match exactly)')

# prefix-collision law: no launchable allow-resource may be a strict prefix of
# another agent name (exact-match permission semantics).
def allow_resources(path):
    lines = open(path).read().splitlines()
    end = next((i for i in range(1, len(lines)) if i > 0 and lines[i].strip() == '---'), None)
    data = yaml.safe_load('\n'.join(lines[1:end])) or {}
    return {(p.get('action'), p.get('resource'), p.get('effect')) for p in data.get('permissions') or []}

collisions = []
for c in ('agent-coord', 'agent-coord-local', 'agent-coord-pr',
          'agent-board-coord', 'agent-board-coord-local', 'agent-board-coord-pr'):
    p = os.path.join(repo, '.opencode/agents', c + '.md')
    if not os.path.isfile(p):
        continue
    for (a, r, e) in allow_resources(p):
        if a != 'subagent' or e != 'allow' or r == '*':
            continue
        for n in names:
            if n != r and n.startswith(r):
                collisions.append((c, r, n))
if collisions:
    bad(f'{label}: launchable prefix collisions {collisions} — exact-match permission check violated (AC2)')
print(f'ok: t4: {label} naming law holds — whole-value names, zero prefix collisions')
PY
    then checks=$((checks + 1)); else fail "t4: the naming audit failed (reason above)"; fi

    cur=$(git -C "$repo" rev-parse HEAD) || fail "t4: cannot read HEAD in $repo"
    pin=$LBF_HEAD; [ "$repo" = "$HA" ] && pin=$HA_HEAD
    [ "$cur" = "$pin" ] || fail "t4: $label HEAD moved ($cur != $pin) — no commits in the targets, C09 included (plan Verified facts)"
  done
  ok "t4: both overlay-bearing repos still sit on their pinned HEADs (no commits)"

  if [ -d "$PT" ]; then
    if find "$PT" -name 'agent-ha-*' 2>/dev/null | grep .; then
      fail "t4: agent-ha-* found under brother-ptouch-automation — C09 touches only LBF + HomeAssistant (AC6)"
    fi
    cur=$(git -C "$PT" rev-parse HEAD) || fail "t4: cannot read HEAD in $PT"
    [ "$cur" = "$PT_HEAD" ] || fail "t4: brother-ptouch HEAD moved ($cur != $PT_HEAD) — nothing changed in it since C08 (AC6)"
    ok "t4: brother-ptouch-automation carries no ha artifacts and holds its HEAD pin (AC6)"
  fi
fi

printf 'PASS: cf-93 C09 ha-overlay-agents contract (%d ok)\n' "$checks"
