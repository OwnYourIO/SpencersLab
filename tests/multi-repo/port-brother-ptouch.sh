#!/usr/bin/env bash
# C08 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the C06
# reference port replicated into /home/coder/brother-ptouch-automation — the
# NON-HA Python service repo. Plain pipeline set only (no ha overlays), the
# real pytest/ruff test law, a code repo's Services set, and the
# absent-skill guard that proves the machinery is domain-agnostic: every
# skill pinned by a generated agent must exist in THIS repo's registry (7
# third-party skills — no agent-rules, no home-assistant-best-practices).
#
# Contract source: chunks/C08.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC1] t3[AC1] t4[AC2] t5[AC1 spot-checks] t6[AC1+AC3 absent-skill
# guard + no agent-ha-*] t7[AC2 registry pins + the 2 pre-existing dirty
# files].
#
# Pre-flight (agent-test, 2026-10-31, read-only): HEAD 381d72f75f7c169edb448dc3c04ea64743d6abf7
# (== plan Verified facts), main clean-tracking, 2 tracked-dirty files
# .agents/agents/code.md f07dac60… + .agents/agents/plan.md aaba9e48… — the
# C06 symlink swap may replace the containing dir, so each sha-pin applies
# ONLY while the file is still a regular file; once swapped the fold-into-
# sources leg takes over (the port must not LOSE their text; it must not
# revert the dirt either — no git write verb here ever).
#
# Red before C08 lands: ALL legs behind the .rulesync precondition gate.
# Env re-pins: PT_ROOT PT_HEAD_PIN PT_SKILLS_LOCK_SHA PT_SKILLS_TREE_SHA
# PT_CODE_SHA PT_PLAN_SHA PT_CODEMD_PLAN_SRC RUNSYNC_BIN.
#
# Usage:
#   bash tests/multi-repo/port-brother-ptouch.sh
#   bash tests/multi-repo/port-brother-ptouch.sh t6      # absent-skill guard
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH

cd "$(git rev-parse --show-toplevel)"

PT="${PT_ROOT:-/home/coder/brother-ptouch-automation}"
HEAD_PIN="${PT_HEAD_PIN:-381d72f75f7c169edb448dc3c04ea64743d6abf7}"
SKILLS_LOCK_SHA="${PT_SKILLS_LOCK_SHA:-7ee54c40449685bee6d988cb677d2b75b416f8d0dac2e62c0bf2933ae4db10a7}"
SKILLS_TREE_SHA="${PT_SKILLS_TREE_SHA:-91d2b43d6b6e7fb2312d89db8320a0e20bca77cee9a6a595794179a35c47ad68}"
CODE_SHA="${PT_CODE_SHA:-f07dac605d7f6b9e557a08b2b9ba7fa2d10e5b52d22752078e25a735679c80e2}"
PLAN_SHA="${PT_PLAN_SHA:-aaba9e48d6045355279ada312d5151af19b4a7887274447719eb2227729aa0cb}"

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
  for i in 1 2 3 4 5 6 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-7]$ ]] || fail "unknown test id '$a' (expected t1..t7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -d "$PT" ] || fail "port-brother-ptouch: target repo $PT does not exist"

require_port() {
  [ -d "$PT/.rulesync" ] || fail "${1:-t1}: $PT has no .rulesync/ — the C08 port has not landed; no machinery runs in a pre-port repo"
}

# --- t1: generate idempotence + --check (C08 AC1) ------------------------------
if want t1; then
  require_port t1
  rulesync_bin=$(find_rulesync) || fail "t1: rulesync not found (PATH / ~/.nvm / RUNSYNC_BIN)"
  d0=$(surface_digest "$PT")
  ( cd "$PT" && "$rulesync_bin" generate >/tmp/opencode/port-pt-generate1.log 2>&1 ) \
    || { tail -n 20 /tmp/opencode/port-pt-generate1.log >&2; fail 't1: rulesync generate failed inside brother-ptouch-automation'; }
  d1=$(surface_digest "$PT")
  ( cd "$PT" && "$rulesync_bin" generate >/tmp/opencode/port-pt-generate2.log 2>&1 ) || fail 't1: second generate failed'
  d2=$(surface_digest "$PT")
  [ "$d1" = "$d2" ] || fail "t1: second generate not a no-op ($d1 -> $d2)"
  [ "$d0" = "$d1" ] || fail "t1: landed port stale — first generate changed the surface ($d0 -> $d1)"
  ( cd "$PT" && "$rulesync_bin" generate --check >/tmp/opencode/port-pt-check.log 2>&1 ) \
    || { tail -n 20 /tmp/opencode/port-pt-check.log >&2; fail 't1: rulesync generate --check red in brother-ptouch-automation'; }
  [ -L "$PT/.agents/agents" ] || fail "t1: .agents/agents not swapped to a symlink (C06 recipe verbatim)"
  [ -L "$PT/.agents/commands" ] || fail "t1: .agents/commands not swapped to a symlink"
  missing=""
  for a in "${PLAIN_AGENTS[@]}"; do
    [ -f "$PT/.opencode/agents/$a.md" ] || missing="$missing $a"
  done
  [ -z "$missing" ] || fail "t1: generated agents missing:$missing"
  grep -q 'enabled: false' "$PT/.agents/loops/pipeline-worker.md" \
    || fail "t1: ported loop not enabled:false (human-owned scheduler)"
  ok "t1: brother-ptouch generate twice idempotent + --check green, symlinks swapped, plain set + disabled loop ($rulesync_bin)"
fi

# --- t2: AGENTS.md pins — python-service law (C08 AC1) -------------------------
if want t2; then
  A="$PT/AGENTS.md"
  [ -f "$A" ] || fail "t2: $A missing"
  grep -q 'Repo identity: brother-ptouch-automation' "$A" \
    || fail "t2: AGENTS.md lacks 'Repo identity: brother-ptouch-automation' (OQ-B2 exact dir-name spelling)"
  # "not the default picker" parenthetical is legal; only an UNqualified
  # claim is the bug (mirrors port-lbf.sh).
  grep 'Repo identity:' "$A" | grep -i 'default picker' | grep -qviE 'not[^a-z]*default picker' \
    && fail "t2: brother-ptouch must NOT claim the default picker"
  grep -q 'uv run pytest' "$A" || fail "t2: the real pytest law did not land ('uv run pytest')"
  grep -q 'ruff' "$A" || fail "t2: ruff missing from the test law"
  grep -q '.agents/plans' "$A" || fail "t2: no plan-folder section"
  grep -q 'cf-93' "$A" || fail "t2: working-mode paragraph missing (this-card-only uncommitted port)"
  if grep -qw helm "$A" || grep -qi 'home-assistant' "$A"; then
    fail "t2: helm/HA text leaked into a non-HA python repo (AC1: NO helm/HA text leaked)"
  fi
  ok "t2: identity + pytest/ruff law + plan section landed; no helm/HA leakage"
fi

# --- t3: C01/C02 board texts + code-repo Services (C08 AC1) --------------------
if want t3; then
  require_port t3
  SK="$PT/.opencode/skills/boards/SKILL.md"
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
        bad(f'spelling {spelling!r} missing (the label table rides every port)')
# OQ-D1 code-repo Services set.
if not near(r'Services', [r'printer-hardware'], 900):
    bad('the Services checklist lacks the python-service work targets (printer-hardware, src, …)')
for tok in ('src', 'research'):
    if not re.search(rf'`{tok}`', text):
        bad(f'Services target {tok!r} missing (C08 Tasks checklist)')
if 'dwains-dashboard' in text or 'custom_components' in text or 'hacs' in text:
    bad('an HA-repo Services set leaked into the brother-ptouch port (sets are per-repo)')
print('ok: t3 — brother-ptouch boards skill: C01 filter + identity + spellings + its own Services set (C08 AC1)')
PY
  then checks=$((checks + 1)); else fail 't3: the boards contract is not satisfied (reason printed above)'; fi

  HR="$PT/.opencode/commands/pipeline-boards-hourly.md"
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
        bad(f'ported BOARD CHECK lacks {pat!r}')
print('ok: t3: brother-ptouch hourly command carries the filtered BOARD CHECK (C08 AC1)')
PY
  then checks=$((checks + 1)); else fail 't3: the hourly contract is not satisfied (reason printed above)'; fi
fi

# --- t4: HEAD pin + the 2 pre-existing dirty files (C08 AC2) --------------------
if want t4; then
  cur=$(git -C "$PT" rev-parse HEAD) || fail "t4: could not read HEAD"
  [ "$cur" = "$HEAD_PIN" ] || fail "t4: HEAD moved ($cur != $HEAD_PIN) — NOTHING committed in the target (plan Verified facts; env re-pin only for owner commits, which this card forbids)"
  ok "t4: HEAD pin holds ($cur)"

  # The C06 recipe swaps .agents/agents to a symlink — the two dirty files
  # live inside it. Regular-file today => byte-pin. Symlink at review time =>
  # their text must have been FOLDED into sources (their twins exist) and the
  # swap must be the ONLY reason they left (never a checkout/stash/revert).
  code_md="$PT/.agents/agents/code.md"
  plan_md="$PT/.agents/agents/plan.md"
  for f in "$code_md" "$plan_md"; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      case "$f" in
        *code.md) want=$CODE_SHA ;;
        *) want=$PLAN_SHA ;;
      esac
      s=$(sha256sum "$f" | awk '{print $1}')
      [ "$s" = "$want" ] || fail "t4: $f changed ($s != pre-flight $want) — the 2 dirty files must stay untouched (AC2)"
    elif [ ! -e "$f" ]; then
      src=.rulesync/subagents/$(basename "$f")
      [ -f "$PT/$src" ] || fail "t4: $f is gone without $src — the symlink swap must be preceded by folding the dirty content into sources (C06 recipe), never a revert"
    fi
  done
  ok "t4: dirty-file posture holds (byte-pinned in place, or folded into .rulesync sources via the swap)"

  # AC3: no HA overlay anywhere in this repo — it is NOT an HA target.
  if find "$PT/.opencode/agents" "$PT/.opencode/commands" "$PT/.rulesync" -name 'agent-ha-*' 2>/dev/null | grep .; then
    fail "t4: agent-ha-* artifacts found in brother-ptouch — not an HA target, plain pipeline set only (DECISIONS, AC3)"
  fi
  ok "t4: zero agent-ha-* in brother-ptouch (C08 AC3)"
fi

# --- t5: generated-agent spot checks (C08 AC1, C06 AC5-equivalent) -------------
if want t5; then
  require_port t5
  if python3 - "$PT" <<'PY'
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
    bad('no generated agents')
for f in files:
    if ('question', '*', 'allow') not in perms(f):
        bad(f'{f}: question allow row missing — hard rule on EVERY agent')
dvlp = perms(os.path.join(repo, '.opencode/agents/agent-dev-local.md'))
for row in (('edit', 'tests/**', 'deny'), ('edit', '.agents/plans/**', 'deny'), ('edit', '.rulesync/**', 'ask')):
    if row not in dvlp:
        bad(f'agent-dev-local lost {row}')
if any(r.startswith('helm ') for (a, r, e) in dvlp if a == 'shell' and e == 'allow'):
    bad('helm shell rows leaked — the python port re-targets the shell allow-list')
coord = perms(os.path.join(repo, '.opencode/agents/agent-coord-local.md'))
launchable = {r for (a, r, e) in coord if a == 'subagent' and e == 'allow'}
for need in ('agent-plan', 'agent-test', 'agent-dev-local', 'agent-review', 'agent-research'):
    if need not in launchable:
        bad(f'coord roster lost {need}')
print(f'ok: t5 — question allowed in all {len(files)} agents; dev denies/ask rows + coord roster green; shell list helm-free')
PY
  then checks=$((checks + 1)); else fail 't5: generated-agent spot checks failed (reason above)'; fi

  for s in agent-board-coord-gate.sh kickoff-mint-branch.sh kickoff-warm-location.sh session-origin.sh board-preload-probe.sh; do
    [ -f "$PT/scripts/$s" ] || fail "t5: scripts/$s not copied"
  done
  [ -d "$PT/.agents/plans/templates" ] || fail "t5: plan templates missing"
  [ -d "$PT/.opencode/plugin/aislop-gate" ] && fail 't5: aislop-gate ported — DECISIONS exclude it here too' || true
  for p in pipeline-locks question-notify board-context; do
    [ -f "$PT/.opencode/plugin/$p/index.ts" ] || fail "t5: plugin $p missing"
  done
  ok "t5: scripts, templates and the three (not four) plugins landed"
fi

# --- t6: ABSENT-SKILL GUARD — machine-checked (C08 AC1 + syncing-table rule) ----
# Every skill an agent pins (standalone `/<name>` line inside its Skills
# section) must exist in THIS repo's registries: .opencode/skills (rulesync-
# generated machinery), .agents/skills (hash-locked third party, 7 here — NO
# agent-rules, NO home-assistant-best-practices), or skills/ (self-written).
# The ported agents of a python repo naming an HA skill would silently fail
# at load time — permission drift is silent (agents-sync lesson), so pin
# validity is checked mechanically, not by eye.
if want t6; then
  require_port t6
  if python3 - "$PT" <<'PY'
import glob, os, re, sys

repo = sys.argv[1]
def bad(msg):
    print(f'FAIL: t6 {msg}', file=sys.stderr)
    sys.exit(1)

registries = [os.path.join(repo, d) for d in ('.opencode/skills', '.agents/skills', 'skills')]
def available(name):
    return any(os.path.isdir(os.path.join(r, name)) for r in registries)

bad_pins = []
scanned = 0
for path in sorted(glob.glob(os.path.join(repo, '.opencode/agents/*.md'))):
    text = open(path).read()
    m = re.search(r'^## Skills\s*$(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not m:
        continue
    scanned += 1
    for tok in re.findall(r'^/([a-z0-9][a-z0-9-]*)$', m.group(1), re.M):
        if tok == 'skill-name':  # the template placeholder line, never a pin
            continue
        if not available(tok):
            bad_pins.append((os.path.basename(path), tok))
if scanned == 0:
    bad('no generated agent carries a "## Skills" section — the guard would be vacuous')
if bad_pins:
    bad(f'pins name skills absent from the brother-ptouch registry: {bad_pins} — every pin must resolve locally (syncing-table rule)')
print(f'ok: t6 — absent-skill guard: every pin in the Skills sections of {scanned} generated agents resolves under this repo\'s registries')
PY
  then checks=$((checks + 1)); else fail 't6: the absent-skill guard failed (reason above)'; fi
fi

# --- t7: registry byte-unchanged (C08 AC1) --------------------------------------
if want t7; then
  sha=$(sha256sum "$PT/skills-lock.json" | awk '{print $1}')
  [ "$sha" = "$SKILLS_LOCK_SHA" ] || fail "t7: skills-lock.json changed ($sha != pre-port $SKILLS_LOCK_SHA)"
  tree=$( (cd "$PT" && find .agents/skills -type f | LC_ALL=C sort | xargs -d '\n' sha256sum 2>/dev/null) | sha256sum | awk '{print $1}')
  [ "$tree" = "$SKILLS_TREE_SHA" ] || fail "t7: .agents/skills tree changed ($tree != pre-port $SKILLS_TREE_SHA)"
  if git -C "$PT" diff --name-only HEAD -- .agents/skills/ skills-lock.json | grep .; then
    fail "t7: git diff shows registry changes in brother-ptouch (AC1: byte-unchanged)"
  fi
  ok "t7: skills-lock.json + .agents/skills byte-unchanged vs pre-port pins"
fi

printf 'PASS: cf-93 C08 port-brother-ptouch contract (%d ok)\n' "$checks"
