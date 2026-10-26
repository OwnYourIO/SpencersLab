#!/usr/bin/env bash
# AGENTS.md surface contract (2026/2026-10-feat-board-coord-intake, C04): the
# board-coord roster line, the feature-pipeline board-variant bullet, the
# pipeline-specifics bullet and the permissions-matrix row MERGED into main's
# diverged rule surfaces — not a copy of the old branch's (D25): main already
# carries the combined `dev-<service>` MCP row (dev-mcp-fleet's C04), so this
# gate asserts the merge preserves it verbatim while re-adding what the re-cut
# dropped.
#
# RE-CREATED as a superset of `git show 09696ae57:tests/agent-board-coord/
# agents-md.sh` (that script's four separate dev-* table rows are obsolete on
# this base; the roster/permissions/regen-no-op/section-preservation contracts
# carry over and gain the redesigned intake facts).
#
# Contract source: chunks/C04.md "## Tests". AC trace:
# c1[AC3 regen] c2[AC2 roster] c3[AC1 new facts + D10/D11/D12/D17-era no-run-
# tag] c4[AC2 dev-<service> verbatim + no re-split] c5[AC2 permissions row,
# D21] c6[AC4 coord text unchanged] c7[AC3 scope; cf-50 + cf-52 widenings]
# c8[AC4 section preservation].
#
# Red before C04 (grep board-coord AGENTS.md: zero matches today); c1, c4,
# c6, c7, c8 are green at the base already and hold as regressions.
#
# c1 runs rulesync generate twice via the PATH/npx ladder; the first run may
# materialize pending generation, so the gate is that the SECOND run changes
# nothing. rulesync is ask-gated in unattended subagent shells, so an
# unresolvable binary skips with a warning (t14 precedent).
#
# CHUNK_BASE=<ref> makes the scope and additive-only checks diff against that
# commit (review passes the pre-chunk commit); default HEAD.
#
# Usage: bash tests/agent-board-coord/agents-md.sh            # c1..c8
#        bash tests/agent-board-coord/agents-md.sh c3 c5      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
FEATURE=".agents/plans/2026/2026-10-feat-board-coord-intake"
# Reused as a regression gate by the later cf-50 gate ticket sharing this
# branch: its plan folder and in-scope surface must pass c7, or the
# invariance checks here report a false scope violation. Content checks are
# untouched.
FEATURE2=".agents/plans/2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords"
# Same union convention: the WeKan v12.64 upgrade ticket ran on this branch,
# so its plan folder is admitted here as well.
FEATURE3=".agents/plans/2026/2026-10-dep-wekan-v12-upgrade"
# Same posture for cf-52, which re-opens the coord pair and the
# kickoff/role-coord contract pair (its AGENTS.md delta stays absent — the
# content pins c2-c6/c8 HOLD untouched; only the scope list widens).
FEATURE4=".agents/plans/2026/2026-10-cf-52-feat-coord-session-inwork"
RULES_SRC=".rulesync/rules/overview.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"

# The combined fleet row as main ships it — C04 keeps it VERBATIM (D25; the
# old branch re-split it into four rows, that world is gone). Byte-pinned so
# a "helpful" reword fails too: the row belongs to dev-mcp-fleet, not here.
DEV_ROW='| `dev-<service>` (playwright, renovate, searxng, boards) | Dev-cluster utility MCPs over the public ingress `mcp.dev.scifi.farm/<name>/mcp`; tier-less, allowed to pipeline agents via a `dev*` allow rule |'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/agents-md-test.XXXXXX) || { echo "fail: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 8); do WANT["c$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^c[1-8]$ ]] || fail "unknown check id '$a' (expected c1..c8)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

cat >"$TMP/neg12.py" <<'PY'
# D12 dropped the `models` custom field: new board text may only pair
# "models" with "custom field" inside an explicit negation (the plan's own
# wording "no `models` custom field exists" is such a denial; a bare
# announcement would fake a third field back into existence).
import re, sys
pat = re.compile(r'models.*custom.?field', re.I)
neg = re.compile(r"\b(no|not|never|dropped|doesn'?t|does not|absent|omits?)\b", re.I)
bad = []
for i, line in enumerate(open(sys.argv[1]), 1):
    if pat.search(line) and not neg.search(line):
        bad.append(f"line {i}: {line.strip()}")
if bad:
    print(" | ".join(bad))
    sys.exit(1)
PY

# --- c1: rulesync generate twice — the second run is a no-op (C04 AC3) --------
if want c1; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "c1: rulesync is not resolvable here (PATH or npx cache); the regeneration gate was not run — re-run where it is available"
  else
    $RS generate >"$TMP/rs1.log" 2>&1 || { tail -n 20 "$TMP/rs1.log" >&2; fail "c1: first rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    $RS generate >"$TMP/rs2.log" 2>&1 || { tail -n 20 "$TMP/rs2.log" >&2; fail "c1: second rulesync generate failed"; }
    snap_after=$(git status --porcelain)
    if [ "$snap_before" != "$snap_after" ]; then
      printf '%s\n' "--- after first run
$snap_before
--- after second run
$snap_after" >"$TMP/noop.diff"
      fail "c1: the second rulesync generate is not a no-op (rules source and AGENTS.md have drifted; see $TMP/noop.diff)"
    fi
    ok "c1: the second rulesync generate is a no-op (via $RS)"
  fi
fi

# --- c2: the roster re-gains board-coord in source AND generated (C04 AC2) ----
if want c2; then
  for f in AGENTS.md "$RULES_SRC"; do
    grep -q 'board-coord' "$f" || fail "c2: $f never names board-coord (the roster entry is missing)"
    grep -qF 'agent-{coord,plan,research,test,dev,review,fuser,board-coord}' "$f" \
      || fail "c2: $f does not carry the exact roster set agent-{...,fuser,board-coord}"
    grep -qF '/pipeline-boards' "$f" || fail "c2: $f never mentions /pipeline-boards"
  done
  ok "c2: board-coord roster entry + /pipeline-boards in AGENTS.md and the rules source"
fi

# --- c3: the redesigned intake facts in the new board-coord text (C04 AC1) -----
# AGENTS.md is a summary surface, so these are presence checks over the whole
# file (and its source); the boards skill remains the contract.
if want c3; then
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'Rework → Not Started → Low Priority' "$f" \
      || fail "c3: $f lacks the new pickup sequence 'Rework → Not Started → Low Priority'"
    grep -qF 'research-only' "$f" || fail "c3: $f never mentions the research-only loop"
    grep -qF 'Review — see the `boards` skill' "$f" || fail "c3: $f never states the Review-list research exit (the board's list is named Review)"
    grep -qF 'cf-<card' "$f" || fail "c3: $f lacks the cf-<card-…> slug rule (D10)"
    grep -qF 'slug' "$f" && grep -qF 'session' "$f" && grep -qF 'custom field' "$f" \
      || fail "c3: $f does not name the slug/session custom-field intake"
    grep -qF 'Model(s) checklist' "$f" \
      || fail "c3: $f does not route models from the Model(s) checklist alone (D12)"
    grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag' "$f" \
      || fail "c3: $f never retires the run tag for card-driven runs"
    grep -qF 'keeps run tags' "$f" \
      || fail "c3: $f must state agent-coord KEEPS run tags — AGENTS.md does not globally retire them"
  done
  awk '/^## Agents/{f=1; next} /^## /{if (f) exit} f' AGENTS.md >"$TMP/agents-section.md"
  awk '/^## Feature pipeline/{f=1; next} /^## /{if (f) exit} f' AGENTS.md >"$TMP/fp-section.md"
  cat "$TMP/agents-section.md" "$TMP/fp-section.md" >"$TMP/new-text.md"
  python3 "$TMP/neg12.py" "$TMP/new-text.md" \
    || fail "c3: the new AGENTS.md text pairs 'models' with 'custom field' without negating it (D12)"
  ok "c3: pickup order, research-only -> Review, slug/session cf intake, cf- slug, no-run-tag-for-card-runs + agent-coord keeps them; D12 negative holds in the new sections"
fi

# --- c4: main's combined dev-<service> row preserved verbatim (C04 AC2) --------
if want c4; then
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF "$DEV_ROW" "$f" \
      || fail "c4: $f does not carry main's combined dev-<service> MCP-table row VERBATIM — do not re-split or reword it (it belongs to dev-mcp-fleet)"
    if grep -qE '^\|[[:space:]]*`dev-(boards|searxng|playwright|renovate)`[[:space:]]*\|' "$f"; then
      fail "c4: $f re-split the fleet into separate dev-boards/dev-searxng/dev-playwright/dev-renovate rows — the combined row is the settled surface"
    fi
  done
  ok "c4: the combined dev-<service> row is kept verbatim in source + AGENTS.md; no re-split rows"
fi

# --- c5: permissions matrix board-coord row (C04 AC2, D21) ---------------------
if want c5; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    row=$(grep -E '^\|[[:space:]]*board-coord[[:space:]]*\|' "$f" || true)
    [ -n "$row" ] || fail "c5: $f has no board-coord row in the role matrix"
    echo "$row" | grep -qF 'dev_boards' \
      || fail "c5: $f board-coord row does not carry the NARROW dev_boards* spelling (D21)"
    # The row may mention broad `dev*` ONLY as the denial D21 records; an
    # un-negated `dev*` in the row would re-grant the fleet-wide surface.
    if echo "$row" | grep -qF '`dev*`' && ! echo "$row" | grep -qE 'not[^|]*`dev\*`'; then
      fail "c5: $f board-coord row grants/mentions \`dev*\` without negating it — D21: narrow dev_boards* only"
    fi
    grep -qE '^\|[[:space:]]*coord[[:space:]]*\|' "$f" \
      || fail "c5: $f lost the coord row (merge, do not replace)"
  done
  ok "c5: permissions.md (source + generated) carries the board-coord row with narrow dev_boards*, coord row intact"
fi

# --- c6: the agent-coord (non-board) text C04 must leave alone (C04 AC4) -------
# Run tags and the live kickoff questions stay for the plain flow; these are
# main's own sentences, pinned as byte-presence so a global rewrite fails.
if want c6; then
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'pipeline-kickoff' "$f" \
      || fail "c6: $f lost the pipeline-kickoff mention — agent-coord's live kickoff questions stand"
    grep -qF 'pipeline-gates` for' "$f" \
      || fail "c6: $f reworded the pipeline-skills sentence (the coord-side kickoff/model-routing description is out of C04's scope)"
    grep -qF 'Launch with the' "$f" || fail "c6: $f lost the /pipeline launch sentence"
  done
  ok "c6: the agent-coord kickoff/gates/launch sentences still present in source + AGENTS.md (no global run-tag retirement)"
fi

# --- c7: scope — only C04's files changed (C04 AC3) -----------------------------
if want c7; then
  { git diff --name-only "$BASE" || true; git ls-files --others --exclude-standard; } | sort -u >"$TMP/changed.txt"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "AGENTS.md"|"$RULES_SRC"|"$PERM_SRC"|"$PERM_GEN"|tests/*|"$FEATURE"/*|\
      "$FEATURE2"/*|"$FEATURE3"/*|"$FEATURE4"/*|scripts/*|.rulesync/commands/pipeline-boards-hourly.md|\
      .opencode/commands/pipeline-boards-hourly.md|\
      .rulesync/subagents/agent-board-coord.md|.opencode/agents/agent-board-coord.md|\
      .rulesync/subagents/agent-coord.md|.opencode/agents/agent-coord.md|\
      .rulesync/skills/pipeline-kickoff/SKILL.md|.opencode/skills/pipeline-kickoff/SKILL.md|\
      .rulesync/skills/pipeline-role-coord/SKILL.md|.opencode/skills/pipeline-role-coord/SKILL.md|\
      .rulesync/commands/pipeline-boards.md|.opencode/commands/pipeline-boards.md|\
      .rulesync/skills/boards/*|.opencode/skills/boards/*) : ;;
      *) fail "c7: path outside C04's in-scope set: $p (base: $BASE)" ;;
    esac
  done <"$TMP/changed.txt"
  ok "c7: changed paths limited to the in-scope files (C04 set + cf-50/cf-52 widenings; base: $BASE)"
fi

# --- c8: no other AGENTS.md section changed (C04 AC4) ---------------------------
# Section-level comparison, not line-level: an in-line extension reads as
# deletion+addition and would hide a cross-section edit in a line diff.
if want c8; then
  if git diff --quiet "$BASE" -- AGENTS.md 2>/dev/null; then
    ok "c8: AGENTS.md shows no delta vs $BASE (committed) — content checks c2-c6 carry the gate"
  else
    git show "$BASE:AGENTS.md" >"$TMP/old-agents.md" 2>/dev/null || fail "c8: cannot read AGENTS.md at $BASE"
    python3 - "$TMP/old-agents.md" AGENTS.md <<'EOF'
import re, sys
def sections(path):
    out, name, buf = {}, "PREAMBLE", []
    for line in open(path).read().splitlines(keepends=True):
        m = re.match(r"^## +(.+?)\s*$", line)
        if m:
            out[name] = "".join(buf); name, buf = m.group(1), []
        else:
            buf.append(line)
    out[name] = "".join(buf)
    return out
old, new = sections(sys.argv[1]), sections(sys.argv[2])
allowed = {"Where things live", "MCP servers", "Agents", "Feature pipeline (agent-*)", "Pipeline specifics in this repo"}
changed = [n for n in old if old.get(n) != new.get(n)]
extra = [n for n in new if n not in old]
if extra:
    changed += [f"(new section: {n})" for n in extra]
if not changed:
    print("no sections changed"); sys.exit(0)
print("changed sections: " + ", ".join(sorted(changed)))
bad = [n for n in changed if n.split(": ", 1)[-1] not in allowed]
if bad:
    print("VIOLATION: " + ", ".join(bad) + f" — allowed: {sorted(allowed)}")
    sys.exit(1)
EOF
    ok "c8: only allowed AGENTS.md sections changed vs $BASE"
  fi
fi

printf 'PASS: agent-board-coord agents-md checks (%d ok)\n' "$checks"
