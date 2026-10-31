#!/usr/bin/env bash
# C06 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the REFERENCE
# pipeline port into /home/coder/Home-Assistant-Label-based-Features — full
# rulesync machinery (sources, generated surfaces, templates, three plugins,
# five scripts, loop disabled), Repo identity line, LBF's pytest/ruff test
# law, the C01/C02 board texts — ALL landing UNCOMMITTED on the repo's main
# working tree (owner ruling, this card only).
#
# Contract source: chunks/C06.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC2] t3[AC3] t4[AC4] t5[AC5] t6[AC6].
#
# Safety posture (plan Verified facts + FRICTION): this suite READS the target
# repo and may only ever run rulesync generate inside it (working-tree writes
# are the landed port's own surface; nothing commits). The suite NEVER runs a
# git write verb in the target. HEAD pins below were re-verified by
# agent-test on 2026-10-31 (git rev-parse HEAD) and match the plan; review
# re-pins via env when the fork story legitimately changes.
#
# Red before C06 lands: ALL legs — the precondition `LBF/.rulesync/ exists`
# fails first with the port-not-landed message, so no leg ever mutates a
# pre-port repo (rulesync is only invoked AFTER that gate).
#
# Pins re-pinnable via env:
#   LBF_ROOT LBF_HEAD_PIN LBF_WORKTREES_MIN LBF_SKILLS_LOCK_SHA
#   LBF_SKILLS_TREE_SHA RUNSYNC_BIN
# The skills-lock + .agents/skills tree digests were captured pre-port
# 2026-10-31 (registry files are READ-ONLY to this run, chunk Files-in-scope).
#
# Usage:
#   bash tests/multi-repo/port-lbf.sh            # t1..t6
#   bash tests/multi-repo/port-lbf.sh t2 t4      # subset
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # FRICTION seed (rulesync discovery parity)

cd "$(git rev-parse --show-toplevel)"

LBF="${LBF_ROOT:-/home/coder/Home-Assistant-Label-based-Features}"
HEAD_PIN="${LBF_HEAD_PIN:-2ea63fdecf1b5cfe36f7ac2e1f56ce8d4bbd5e7e}"
WORKTREES_MIN="${LBF_WORKTREES_MIN:-25}"        # `git worktree list` rows, 2026-10-31 pre-port
SKILLS_LOCK_SHA="${LBF_SKILLS_LOCK_SHA:-1442a292996175e322925150718fec087e8abe36d5ffa6eec41f6a3c06efe2e0}"
SKILLS_TREE_SHA="${LBF_SKILLS_TREE_SHA:-e2eee38a2c6446031104b959693cd4df3e273ea1fe5607825da8b03c6386e8c0}"

# The plain set C06 must generate (chunk Sources bullet: coord x3, board-coord
# x3, board, plan, research, test, dev-local, dev-pr, review, fuser + the
# standalone ask/code/debug/planner/review/dev family). SDLC-stage agents are
# NOT part of the ported set.
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

surface_digest() { # one-line digest of the generated surfaces + AGENTS.md
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

[ -d "$LBF" ] || fail "port-lbf: target repo $LBF does not exist (lowercase-b spelling is the real dir name — RESEARCH B note 11)"

require_port() { # red-gate before ANY rulesync invocation in the target
  [ -d "$LBF/.rulesync" ] || fail "${1:-t1}: $LBF has no .rulesync/ — the C06 port has not landed; refusing to run machinery in a pre-port repo"
}

# --- t1: generate idempotence + --check green in LBF (C06 AC1) ----------------
if want t1; then
  require_port t1
  rulesync_bin=$(find_rulesync) || fail "t1: rulesync not found (PATH / ~/.nvm/versions/node/*/bin / RUNSYNC_BIN)"
  d0=$(surface_digest "$LBF")
  ( cd "$LBF" && "$rulesync_bin" generate >/tmp/opencode/port-lbf-generate1.log 2>&1 ) \
    || { tail -n 20 /tmp/opencode/port-lbf-generate1.log >&2; fail 't1: rulesync generate failed inside LBF'; }
  d1=$(surface_digest "$LBF")
  ( cd "$LBF" && "$rulesync_bin" generate >/tmp/opencode/port-lbf-generate2.log 2>&1 ) \
    || fail 't1: second rulesync generate failed inside LBF'
  d2=$(surface_digest "$LBF")
  [ "$d1" = "$d2" ] || fail "t1: second generate is not a no-op (digest $d1 -> $d2) — sources and generated surfaces must be deterministic (AC1)"
  [ "$d0" = "$d1" ] || fail "t1: the LANDED port was stale — first generate changed the surface ($d0 -> $d1); C06 must leave it freshly generated (AC1)"
  ( cd "$LBF" && "$rulesync_bin" generate --check >/tmp/opencode/port-lbf-check.log 2>&1 ) \
    || { tail -n 20 /tmp/opencode/port-lbf-check.log >&2; fail 't1: rulesync generate --check is red in LBF (AC1)'; }
  ok "t1: LBF generate is idempotent (twice, no-op) and --check exits 0 ($rulesync_bin)"

  # symlink swap + sources carry the plain set (same AC1 leg)
  [ -L "$LBF/.agents/agents" ] || fail "t1: LBF .agents/agents is not a symlink into .opencode/ (the swap, AC1)"
  [ -L "$LBF/.agents/commands" ] || fail "t1: LBF .agents/commands is not a symlink into .opencode/ (the swap, AC1)"
  missing=""
  for a in "${PLAIN_AGENTS[@]}"; do
    [ -f "$LBF/.opencode/agents/$a.md" ] || missing="$missing $a"
  done
  [ -z "$missing" ] || fail "t1: generated agents missing in LBF:$missing"
  ok "t1: .agents/{agents,commands} are symlinks and all ${#PLAIN_AGENTS[@]} plain-set agents generated in LBF (.opencode/agents/)"
fi

# --- t2: LBF AGENTS.md pins (C06 AC2) -------------------------------------------
if want t2; then
  A="$LBF/AGENTS.md"
  [ -f "$A" ] || fail "t2: $A missing"
  grep -q 'Repo identity: Home-Assistant-Label-based-Features' "$A" \
    || fail "t2: AGENTS.md lacks 'Repo identity: Home-Assistant-Label-based-Features' (exact spelling incl. lowercase-b, OQ-B2)"
  # A parenthetical "not the default picker" is legal; an UNqualified claim
  # is the bug: count picker-claims only when no negation precedes them.
  grep 'Repo identity:' "$A" | grep -i 'default picker' | grep -qviE 'not[^a-z]*default picker' \
    && fail "t2: the LBF identity line claims the default picker — only SpencersLab is the default picker (C01)"
  grep -q 'uv run pytest' "$A" || fail "t2: LBF test law not landed: no 'uv run pytest' text (OQ-D1 per-repo harness)"
  grep -q 'ruff' "$A" || fail "t2: LBF test law not landed: no ruff text"
  grep -q '.agents/plans' "$A" || fail "t2: no per-ticket plan-folder section in LBF AGENTS.md"
  grep -q 'STATE.json' "$A" || fail "t2: the pipeline section must name the plan-folder machinery (STATE.json)"
  # Working-mode paragraph: THIS card's uncommitted port, nothing else exempt
  # (OQ-B1 ANSWERED WITH AN ADDITION — C06 HARD RULES bullet).
  grep -q 'cf-93' "$A" || fail "t2: the cf-93 working-mode paragraph is absent (the port landing uncommitted is card-scoped)"
  grep -qi 'uncommitted' "$A" || fail "t2: no 'uncommitted' wording — the ported rules text must state the this-card-only dirty-main posture"
  # GitOps-law leak guard (AC2: spot-grep helm lint absent).
  if grep -q 'helm lint' "$A"; then
    fail "t2: 'helm lint' leaked into LBF AGENTS.md — SpencersLab's chart law must not ride the port (AC2)"
  fi
  if grep -qw helm "$A"; then
    fail "t2: a bare 'helm' mention in LBF AGENTS.md — review must justify any such carry-over (AC2 no-chart-law-leak)"
  fi
  ok "t2: LBF AGENTS.md carries identity/pytest-law/plan-folder/working-mode pins and zero GitOps-law leakage (C06 AC2)"
fi

# --- t3: ported board texts (C06 AC3) -------------------------------------------
if want t3; then
  require_port t3
  SK="$LBF/.opencode/skills/boards/SKILL.md"
  [ -f "$SK" ] || fail "t3: ported boards skill $SK missing"
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

# C01's filter semantics must ride the PORTED copy (the chunk pins reuse of
# the same anchor list as tests/multi-repo/repo-label-filter.sh t1).
checks = [
    (r'Repo:', [r'human-created', r'never agent-created or agent-mutated'], 500),
    (r'Repo:', [r'TRIMMED remainder', r'owning repo'], 400),
    (r'default\s+picker', [r'Repo:', r'eligible|belongs'], 700),
    (r'Repo:', [r'never', r'claim'], 300),
    (r'Repo identity', [r'basename|canonical', r'NEEDS_INFO', r'never guess'], 1200),
]
for anchor, tokens, window in checks:
    if not near(anchor, tokens, window):
        bad(f'ported boards skill lost an anchor set: {anchor!r} + {tokens} within {window} chars')
for spelling in ('SpencersLab', 'HomeAssistant', 'Home-Assistant-Label-based-Features', 'brother-ptouch-automation'):
    if spelling not in text:
        bad(f'spelling {spelling!r} absent from the ported filter table')
# OQ-D1: the Services checklist is LBF's work-target set, not SpencersLab's
# 13-folder list.
if not near(r'Services', [r'custom_components'], 700):
    bad('the ported Services checklist lacks LBF work targets (custom_components, hacs, …) — the 13-folder SpencersLab set must be re-targeted')
if 'hacs' not in text:
    bad('ported Services checklist lacks the hacs target (C06 Tasks, OQ-D1)')
if 'proxy-backup' in text or 'proxy-remote' in text:
    bad("SpencersLab's folder-service targets leaked into the LBF boards skill")
print('ok: t3 — LBF boards skill carries the C01 filter + identity + spellings + the LBF Services set (C06 AC3)')
PY
  then checks=$((checks + 1)); else fail 't3: the ported boards contract is not satisfied (reason printed above)'; fi

  HR="$LBF/.opencode/commands/pipeline-boards-hourly.md"
  [ -f "$HR" ] || fail "t3: ported hourly command $HR missing"
  if python3 - "$HR" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)
m = re.search(r'BOARD CHECK.*?(?=^Notes:)', text, re.M | re.S)
if not m:
    bad('no BOARD CHECK block in the ported hourly command')
block = m.group(0)
for pat in (r'get_card', r'Repo:', r'filter', r'EMPTY|no filtered-in|zero filtered-in|empty', r'≥1', r'max 5', r'fail-closed'):
    if not re.search(pat, block):
        bad(f'ported BOARD CHECK lacks {pat!r} — the C02 repo-filtered count must ride the port (post-C01/C02 copy)')
print('ok: t3: ported hourly command carries the C02 filtered-count BOARD CHECK (C06 AC3)')
PY
  then checks=$((checks + 1)); else fail 't3: the ported hourly contract is not satisfied (reason printed above)'; fi
fi

# --- t4: no-commit safety + worktrees survive (C06 AC4) ------------------------
if want t4; then
  cur=$(git -C "$LBF" rev-parse HEAD) || fail "t4: could not read HEAD in $LBF"
  [ "$cur" = "$HEAD_PIN" ] || fail "t4: LBF HEAD moved ($cur != pinned $HEAD_PIN) — NOTHING may be committed in the target repos (plan Verified facts; re-pin via LBF_HEAD_PIN only if the owner committed, which this card forbids)"
  oneline=$(git -C "$LBF" log --oneline -1)
  case "$oneline" in
    2ea63fd*) ;;
    *) fail "t4: LBF log --oneline -1 changed: '$oneline' (pinned story 2ea63fd…, AC4 no-commits)" ;;
  esac
  wt_rows=$(git -C "$LBF" worktree list | wc -l)
  [ "$wt_rows" -ge "$WORKTREES_MIN" ] || fail "t4: LBF worktree rows $wt_rows < pre-port $WORKTREES_MIN — the port must leave existing worktrees alone (no prune, no removal; RESEARCH B)"
  [ -d "$LBF/.agents/worktrees" ] || fail "t4: LBF .agents/worktrees/ vanished — pre-existing worktree dir must stay (RESEARCH B working-state note)"
  ok "t4: LBF HEAD pin holds ($cur), top commit unchanged, worktrees intact ($wt_rows rows >= $WORKTREES_MIN)"
fi

# --- t5: generated-agent spot checks (C06 AC5) ---------------------------------
if want t5; then
  require_port t5
  if python3 - "$LBF" "${PLAIN_AGENTS[@]}" <<'PY'
import glob, os, sys, yaml

repo = sys.argv[1]
plain = sys.argv[2:]
def bad(msg):
    print(f'FAIL: t5 {msg}', file=sys.stderr)
    sys.exit(1)

def fm(path):
    # rulesync emits `---`-delimited YAML frontmatter; parse the block only.
    lines = open(path).read().splitlines()
    if not lines or lines[0].strip() != '---':
        return None
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
    if end is None:
        return None
    return yaml.safe_load('\n'.join(lines[1:end])) or {}

def perms(path):
    data = fm(path)
    if data is None:
        bad(f'{path}: no parsable frontmatter')
    return {(p.get('action'), p.get('resource'), p.get('effect')) for p in data.get('permissions') or []}

# The repo hard rule: question stays allowed in EVERY agent, incl. the
# board-coord family — silent permission drift is the agents-sync lesson.
agent_files = sorted(glob.glob(os.path.join(repo, '.opencode/agents/*.md')))
if len(agent_files) < len(plain):
    bad(f'only {len(agent_files)} generated agents in LBF (plain set is {len(plain)})')
for f in agent_files:
    if ('question', '*', 'allow') not in perms(f):
        bad(f'{f}: the question allow row is gone — hard rule (every agent must keep `question` allowed)')
print(f'ok: t5: question allowed in all {len(agent_files)} generated LBF agents')

dvlp = perms(os.path.join(repo, '.opencode/agents/agent-dev-local.md'))
for row in (('edit', 'tests/**', 'deny'), ('edit', '.agents/plans/**', 'deny'),
            ('edit', '.rulesync/**', 'ask')):
    if row not in dvlp:
        bad(f'agent-dev-local lost {row} (dev-shaped permissions, C06 AC5 spot-check)')

coord = perms(os.path.join(repo, '.opencode/agents/agent-coord-local.md'))
launchable = {r for (a, r, e) in coord if a == 'subagent' and e == 'allow'}
for need in ('agent-plan', 'agent-test', 'agent-dev-local', 'agent-review', 'agent-research'):
    if need not in launchable:
        bad(f'agent-coord roster lost {need} (C06 AC5 spot-check)')

# shell allow-list = LBF commands, NOT SpencersLab's helm rows.
shell_allows = [r for (a, r, e) in dvlp if a == 'shell' and e == 'allow']
if any(r.startswith('helm ') for r in shell_allows):
    bad(f'agent-dev-local shell allow-list still carries helm rows ({shell_allows}) — the port must re-target the allow-list to LBF commands')

# a /pipeline command body resolving LBF's plans layout (AC5 spot-check)
cmd = open(os.path.join(repo, '.opencode/commands/pipeline.md')).read()
if '.agents/plans' not in cmd:
    bad('ported /pipeline command does not resolve the LBF plans layout (.agents/plans paths)')
print('ok: t5 — spot-checks green: dev denies + ask row intact, coord roster full, helm-free shell list, /pipeline names the LBF layout (C06 AC5)')
PY
  then checks=$((checks + 1)); else fail 't5: the generated-agent spot contract is not satisfied (reason printed above)'; fi

  # loop file ships disabled + the three plugins + five scripts + templates
  grep -q 'enabled: false' "$LBF/.agents/loops/pipeline-worker.md" \
    || fail "t5: ported loop is not enabled:false — scheduler enablement is human-owned (cf-76 ruling, DECISIONS)"
  for p in pipeline-locks question-notify board-context; do
    [ -f "$LBF/.opencode/plugin/$p/index.ts" ] || fail "t5: plugin $p not ported to LBF (board runs need all three — DECISIONS: aislop-gate excepted)"
  done
  [ -d "$LBF/.opencode/plugin/aislop-gate" ] && fail 't5: aislop-gate WAS ported — DECISIONS rule it out (their CI does not run aislop ci)' || true
  for s in agent-board-coord-gate.sh kickoff-mint-branch.sh kickoff-warm-location.sh session-origin.sh board-preload-probe.sh; do
    [ -f "$LBF/scripts/$s" ] || fail "t5: scripts/$s not copied into LBF"
  done
  [ -d "$LBF/.agents/plans/templates" ] || fail "t5: .agents/plans/templates/ not copied into LBF"
  ok "t5: loop disabled, three plugins (no aislop-gate), five scripts, plan templates all landed in LBF"

  # the gate script must actually run from the target
  ( cd "$LBF" && bash scripts/agent-board-coord-gate.sh --help >/dev/null 2>&1 ) \
    || fail "t5: bash scripts/agent-board-coord-gate.sh --help fails inside LBF (AC5 spot-check)"
  ok "t5: gate script runs (exit 0 --help) from LBF"
fi

# --- t6: registry files byte-unchanged (C06 AC6) --------------------------------
if want t6; then
  disk_lock=$(sha256sum "$LBF/skills-lock.json" | awk '{print $1}')
  [ "$disk_lock" = "$SKILLS_LOCK_SHA" ] || fail "t6: LBF skills-lock.json changed ($disk_lock != pre-port $SKILLS_LOCK_SHA) — the registry is READ-ONLY to this run (Files-in-scope)"
  tree=$( (cd "$LBF" && find .agents/skills -type f | LC_ALL=C sort | xargs -d '\n' sha256sum 2>/dev/null) | sha256sum | awk '{print $1}')
  [ "$tree" = "$SKILLS_TREE_SHA" ] || fail "t6: the .agents/skills third-party tree changed ($tree != pre-port $SKILLS_TREE_SHA) — no re-sync, no re-hash (AC6)"
  if git -C "$LBF" diff --name-only HEAD -- .agents/skills/ skills-lock.json | grep .; then
    fail "t6: git diff in LBF shows changes under .agents/skills/ or to skills-lock.json (AC6: zero)"
  fi
  ok "t6: LBF skills-lock.json + .agents/skills byte-identical to the pre-port pins; git diff clean under both (C06 AC6)"
fi

printf 'PASS: cf-93 C06 port-lbf contract (%d ok)\n' "$checks"
