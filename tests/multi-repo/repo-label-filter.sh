#!/usr/bin/env bash
# C01 contract (2026/2026-10-cf-93-feat-multi-repo-pipeline): the boards skill
# carries the `Repo:` pickup filter (filter, NOT a lock), the repo-identity
# rule, and the four exact label spellings; AGENTS.md declares this repo's
# identity; the pipeline-locks plugin stays byte-unchanged and Pipeline:-only.
#
# Contract source: chunks/C01.md "## Tests" + Acceptance criteria. AC trace:
# t1[AC1] t2[AC1+regression] t3[AC3] t4[AC2] t5[AC4].
#
# Assertions run against the GENERATED twins (.opencode/skills/boards/SKILL.md,
# AGENTS.md) because AC1 pins them; rulesync owns those files, dev edits only
# the .rulesync sources. Phrase matching is anchor+window ("near"): a token
# table of regexes that must co-occur within N chars of an anchor — prose may
# re-wrap or split bullets, the semantics must not move. Token wording follows
# the chunk's own quoted phrasings (OQ-A1/A2/B2 answers are the confirmed
# design, so the literal anchors are the contract, not a convenience).
#
# The repo-mismatch leg of t3 is scope-conditional: C02 (wave 2) edits the
# command files ON PURPOSE, so once the hourly command carries `Repo:` text
# the command-untouched check is reported as scope-transferred (C02's own
# suite guards that surface from then on). Subagents stay pinned for the
# whole run — no chunk of this plan touches this repo's agent sources.
#
# Red before C01 lands: t1, t2(Repo: leg), t4 identity legs. Green-at-base
# regression gates by design: t2 Pipeline: wording, t3 plugin byte-pin, t5.
#
# Usage:
#   bash tests/multi-repo/repo-label-filter.sh          # t1..t5
#   bash tests/multi-repo/repo-label-filter.sh t3 t4    # subset
# Env: PLUGIN_DIFF_BASE (default: git merge-base HEAD main) re-points the
#    byte-pin when main legitimately moved the plugin.
#    RUNSYNC_BIN overrides the rulesync binary discovery.
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH   # helm/rulesync PATH recipe, FRICTION seed

cd "$(git rev-parse --show-toplevel)"

SKILL=.opencode/skills/boards/SKILL.md
SKILL_SRC=.rulesync/skills/boards/SKILL.md
AGENTS_MD=AGENTS.md
RULES_SRC=.rulesync/rules/overview.md
PLUGIN=.opencode/plugin/pipeline-locks/index.ts
HOURLY_GEN=.opencode/commands/pipeline-boards-hourly.md
GATE_SCRIPT=scripts/agent-board-coord-gate.sh

DIFF_BASE="${PLUGIN_DIFF_BASE:-$(git merge-base HEAD main)}"

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
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected t1..t5)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: generated boards skill carries the filter semantics (C01 AC1) -------
if want t1; then
  if python3 - "$SKILL" <<'PY'
import re, sys

path = sys.argv[1]
text = open(path).read()

def bad(msg):
    print(f'FAIL: t1 {msg}', file=sys.stderr)
    sys.exit(1)

def near(anchor, tokens, window=600):
    """True when some occurrence of `anchor` has every token within +/- window.

    Case-insensitive throughout: the chunk capitalises DEFAULT PICKER in prose
    and the contract is the semantic pairing, never the letter case. The exact
    label SPELLINGS are case-sensitive and checked separately, never here."""
    for m in re.finditer(anchor, text, re.I):
        lo, hi = max(0, m.start() - window), min(len(text), m.end() + window)
        seg = text[lo:hi]
        if all(re.search(t, seg, re.I) for t in tokens):
            return True
    return False

# 1) `Repo:` label posture mirrors the human-owned `Pipeline:` wording (OQ-A1).
if not near(r'Repo:', [r'human-created', r'never agent-created or agent-mutated'], 500):
    bad('missing the Repo: human-owned posture (human-created in the WeKan UI, never agent-created or agent-mutated)')
# 2) trimmed-remainder naming rule (chunk Tasks, board-facts paragraph).
if not near(r'Repo:', [r'TRIMMED remainder', r'owning repo'], 400):
    bad('missing the rule that the TRIMMED remainder of a Repo: label names the owning repo')
# 3) at-most-one Repo: label per card (multi-label -> claimed by none, skipped).
if not near(r'Repo:', [r'at most one'], 300):
    bad('missing the at-most-one Repo: label rule')
# 4) eligibility = match OR (no Repo: label AND this repo is the default picker).
if not near(r'default\s+picker', [r'Repo:', r'eligible|belongs'], 700):
    bad('missing the eligibility rule (label match OR no-label + default picker)')
# 5) Repo: NEVER contributes to the claim set (coexistence, OQ-A1 COEXIST).
if not near(r'Repo:', [r'never', r'claim'], 300):
    bad('missing the sentence that Repo: never contributes to the claim set')
# 6) repo-mismatch skips ride the existing no-op reason token. A bare "repo"
# token would false-match "report" — name the mismatch forms explicitly.
if not near(r'no-claimable-cards', [r'Repo:|repo-mismatch|repo mismatch'], 400):
    bad('repo-mismatch skips must count toward the no-claimable-cards reason (no third token, DECISIONS)')
# 7) Repo identity rule: canonical-root basename cross-checked against the
#    AGENTS.md line; mismatch -> NEEDS_INFO, never guess.
if not near(r'Repo identity', [r'basename|canonical', r'NEEDS_INFO', r'never guess'], 1200):
    bad('missing the Repo identity subsection (basename + AGENTS.md cross-check, NEEDS_INFO on mismatch, never guess)')

# 8) the four exact label spellings (OQ-B2), case-sensitive; the card's
#    mis-cased historical spelling may only appear as a flagged note.
for spelling in ('SpencersLab', 'HomeAssistant',
                 'Home-Assistant-Label-based-Features', 'brother-ptouch-automation'):
    if spelling not in text:
        bad(f'label spelling {spelling!r} absent (spellings are exact dir names, case-sensitive, OQ-B2)')
for m in re.finditer(r'Home-Assistant-Label-Based', text):
    seg = text[max(0, m.start() - 300):m.end() + 300]
    if not re.search(r'mis-?cas|historical|renamed', seg, re.I):
        bad(f'capital-B "Label-Based" present without the mis-cased/historical flag at offset {m.start()}')

# 9) filter POSITION in the walk: after the step-3 get_card confirm (pickup
#    section) and before the lock-availability skip (Parallel section).
pickup = re.search(r'^## Card pickup$(.*?)^## ', text, re.M | re.S)
if not pickup:
    bad('no "## Card pickup" section to locate the filter step in')
psec = pickup.group(1)
if 'Repo:' not in psec:
    bad('the pickup walk carries no Repo: filter step')
if psec.find('get_card') > psec.find('Repo:'):
    bad('the Repo: filter must sit AFTER the step-3 get_card confirm in the walk')
par = re.search(r'^## Parallel pipeline loops$(.*?)^## ', text, re.M | re.S)
if par:
    qsec = par.group(1)
    if 'Repo:' in qsec and 'ENTIRE derived set' in qsec and qsec.find('Repo:') > qsec.find('ENTIRE derived set'):
        bad('the Repo: filter step must precede the lock-availability check')
print('ok: t1 — generated boards skill carries the Repo: posture, eligibility rule, never-in-claim-set sentence, no-op reason reuse, identity rule, exact spellings, and the filter sits between get_card-confirm and lock availability (C01 AC1)')
PY
  then checks=$((checks + 1)); else fail 't1: the filter-semantics contract is not satisfied (reason printed above)'; fi
fi

# --- t2: Pipeline: lock wording intact + Repo: excluded from claims (AC1) ----
if want t2; then
  if python3 - "$SKILL" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t2 {msg}', file=sys.stderr)
    sys.exit(1)

def near(anchor, tokens, window=600):
    for m in re.finditer(anchor, text, re.I):
        seg = text[max(0, m.start() - window):m.end() + window]
        if all(re.search(t, seg, re.I) for t in tokens):
            return True
    return False

# Regression: the D17 derivation bullet must survive C01 untouched for Pipeline:.
if not near(r'starts with `Pipeline:`', [r'contributes', r'TRIMMED remainder', r'lock name'], 350):
    bad('the Pipeline: derivation bullet (case-sensitive prefix -> TRIMMED remainder -> lock name) changed — C01 keeps Pipeline: semantics byte-faithful')
if not near(r'NO matching label', [r'single `default` pipeline'], 300):
    bad('the no-Pipeline:-label -> default pipeline rule vanished')
# C01's added sentence: the derivation bullet itself must state Repo: never
# contributes (the chunk names this exact placement).
if not near(r'derive the pipeline set', [r'Repo:', r'never|does not'], 900):
    bad('the Parallel pipeline loops derivation bullet must also state that Repo: never joins the claim set')
print('ok: t2 — Pipeline: lock semantics intact and the derivation bullet states Repo: never contributes to the claim set (C01 AC1)')
PY
  then checks=$((checks + 1)); else fail 't2: the coexistence contract is not satisfied (reason printed above)'; fi
fi

# --- t3: lock surface untouched (C01 AC3) -------------------------------------
if want t3; then
  changed=$(git diff --name-only "$DIFF_BASE" -- "$PLUGIN" | wc -l)
  [ "$changed" -eq 0 ] || fail "t3: $PLUGIN differs from $DIFF_BASE — C01 forbids any plugin change (plan Out-of-scope, RESEARCH A2)"
  disk_sha=$(sha256sum "$PLUGIN" | awk '{print $1}')
  base_sha=$(git show "$DIFF_BASE:$PLUGIN" | sha256sum | awk '{print $1}')
  [ "$disk_sha" = "$base_sha" ] || fail "t3: $PLUGIN working copy ($disk_sha) is not byte-identical to $DIFF_BASE ($base_sha)"
  ok "t3: $PLUGIN byte-unchanged vs $DIFF_BASE (AC3: no lock-surface change anywhere)"

  # derivePipelineSet keeps matching ONLY the exact Pipeline: prefix; a Repo:
  # string anywhere in the plugin would mean a dev invented a second lock path.
  if python3 - "$PLUGIN" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t3 {msg}', file=sys.stderr)
    sys.exit(1)
if 'export const LABEL_PREFIX = "Pipeline:";' not in src:
    bad('LABEL_PREFIX no longer the exact Pipeline: literal')
if 'derivePipelineSet' not in src or '.startsWith(LABEL_PREFIX)' not in src:
    bad('derivePipelineSet lost its Pipeline:-prefix filter')
if re.search(r'Repo:', src):
    bad('the plugin mentions Repo: at all — Repo: is invisible to the lock surface by construction (RESEARCH A2)')
print('ok: t3 — derivePipelineSet still filters on the exact Pipeline: prefix only, zero Repo: awareness in the plugin (C01 AC3)')
PY
  then checks=$((checks + 1)); else fail 't3: the plugin-source contract is not satisfied (reason printed above)'; fi

  # No subagent surface changes in this repo for the whole plan (C09 authors
  # overlays in the TARGET repos only — DECISIONS placement ruling).
  if git diff --name-only "$DIFF_BASE" -- .rulesync/subagents .opencode/agents | grep -q .; then
    fail "t3: agent sources/generated agents changed under $DIFF_BASE — no chunk of this plan edits this repo's subagents"
  fi
  ok "t3: no .rulesync/subagents or .opencode/agents change vs $DIFF_BASE (AC3 no-subagent leg)"

  # Command files belong to C01 until C02 lands (C01 Tasks: "do NOT touch any
  # command file"); once the hourly command carries Repo: text, C02 owns it.
  if grep -q 'Repo:' "$HOURLY_GEN" 2>/dev/null; then
    ok "t3: hourly command already carries Repo: text — C02 landed, its untouched-for-C01 leg transfers to tests/multi-repo/hourly-board-check.sh"
  else
    if git diff --name-only "$DIFF_BASE" -- .rulesync/commands .opencode/commands "$GATE_SCRIPT" | grep -q .; then
      fail "t3: command files or the gate script changed while the hourly command still lacks the C02 Repo: text — C01 must not touch them (C02 scope)"
    fi
    ok "t3: no command/gate-script change vs $DIFF_BASE (C01 commands-untouched leg)"
  fi
fi

# --- t4: identity declaration + rulesync integrity (C01 AC2) ------------------
if want t4; then
  grep -q '^.*Repo identity: SpencersLab' "$AGENTS_MD" \
    || fail "t4: $AGENTS_MD carries no 'Repo identity: SpencersLab' line (generated — rulesync owns it)"
  grep -q 'Repo identity: SpencersLab' "$RULES_SRC" \
    || fail "t4: $RULES_SRC lacks the identity line — AGENTS.md must be generated from it, not hand-edited"
  grep -q 'default picker' "$RULES_SRC" \
    || fail "t4: the overview.md identity line must name SpencersLab as the default picker"

  rulesync_bin=$(find_rulesync) || fail "t4: rulesync not found (PATH, ~/.nvm/versions/node/*/bin or RUNSYNC_BIN) — FRICTION: never let a discovery miss pass silently"
  "$rulesync_bin" generate --check >/tmp/opencode/cf93-repo-label-filter.check.log 2>&1 \
    || { tail -n 20 /tmp/opencode/cf93-repo-label-filter.check.log >&2; fail "t4: rulesync generate --check is red — the generated surfaces (boards twin, AGENTS.md) are out of sync with sources (AC2; the double-generate no-op is dev's own check per plan Commands)"; }
  ok "t4: AGENTS.md + rules source carry the identity line; rulesync generate --check exits 0 ($rulesync_bin)"

  # Case-sensitive spelling set, lowercase-b form included (OQ-B2). The skill
  # twin is checked in t1; here the identity source must not spread the
  # mis-cased card spelling into the rules.
  if grep -q 'Home-Assistant-Label-Based' "$RULES_SRC"; then
    fail "t4: $RULES_SRC uses the mis-cased Label-Based form — the dir name is lowercase-b (RESEARCH B note 11)"
  fi
  ok "t4: rules source spellings are the exact dir-name forms (lowercase-b Label-based, OQ-B2)"
fi

# --- t5: pickup-walk regression (C01 AC4) --------------------------------------
if want t5; then
  python3 - "$SKILL" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: t5 {msg}', file=sys.stderr)
    sys.exit(1)

def near(anchor, tokens, window=600):
    for m in re.finditer(anchor, text, re.I):
        seg = text[max(0, m.start() - window):m.end() + window]
        if all(re.search(t, seg, re.I) for t in tokens):
            return True
    return False

if not near(r'never visits', [r'\*\*Executing\*\*']):
    bad('the "walk never visits Executing" sentence is gone — the Repo: filter must not re-open Executing pickups (AC4)')
if not near(r'never pick', [r'Timeout']):
    bad('the "never pick from Timeout" rule is gone (AC4)')
if 'at most 3 claim attempts' not in text:
    bad('the at-most-3-claim-attempts cap drifted — the filter consumes attempts the same way contended locks do (AC4)')
print('ok: t5 — walk still never visits Executing/Timeout and the 3-attempt cap holds (C01 AC4 regression)')
PY
  checks=$((checks + 1))
fi

# The source twin must exist for C02+ to keep editing (generated-only greps
# above would pass on a stale .rulesync too — rulesync --check in t4 proves
# freshness, this proves the file itself is there).
if want t1; then
  [ -f "$SKILL_SRC" ] || fail "t1: $SKILL_SRC missing — the ported copies (C06) grep-copy THIS source"
  ok "t1: $SKILL_SRC present as the single flow authority for the ports"
fi

printf 'PASS: cf-93 C01 repo-label-filter contract (%d ok)\n' "$checks"
