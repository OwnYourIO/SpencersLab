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
# tag + cf-85 AC8 combined slug value] c4[AC2 dev-<service> verbatim + no
# re-split] c5[AC2 permissions row, D21] c6[AC4 coord text unchanged]
# c7[AC3 scope; cf-50 + cf-52 + cf-85 widenings] c8[AC4 section preservation].
#
# Red before C04 (grep board-coord AGENTS.md: zero matches today); c1, c4,
# c6, c7, c8 are green at the base already and hold as regressions.
#
# cf-85 (2026-10-29, cf-85-refactor-wekan-slug-session-link): c3's combined-
# form pin is the DESIGNED RED — AGENTS.md and the rules source must name the
# single slug field WITH its `[<slug>](<session link>)` value, so the pin is
# red against the pre-flip text and green at the flip commit. c7 admits the
# cf-85 plan folder. c3's slug/session/custom-field substrings stay pinned on
# purpose: the retired field's name survives in the summary text, while the
# two-field wording is fenced by rulesync-surface.sh c19's tree-wide negatives.
#
# cf-58 RE-PIN (2026-10-cf-58-feat-standalone-agent-merge; C02/C03/C04/C05):
# c2's exact roster-set literal was the PRE-SPLIT row — re-pinned to the
# variant form C02's overview task pins verbatim, plus the pre-split row's
# absence and the new /pipeline-pr command name (C03). c6's 'Launch with
# the' literal relaxed to 'Launch with' — C03 legitimately rewrites the
# launch sentence (`/pipeline` = commit-only alias; `/pipeline-pr` =
# remote); the surviving contract is that launch guidance exists, not the
# article (judgment recorded here). c7 admits the cf-58 surfaces (directory
# wildcards for the agent-definition tree + opencode.jsonc + this ticket's
# plan folder; the retired pre-split dev-path literal leaves with the
# rename sweep — agent-perms A13). c9 (new): AGENTS.md + rules carry the
# Lifecycle wording (C05) and a standalone dev-family entry (C04).
#
# cf-90 RE-PIN (2026-10-31, agent-test; C02 naming round): c3's 'agent-coord
# keeps run tags' presence pin FLIPS to the global-retirement posture — the
# keeps-wording becomes the defect and the every-flavor window is DESIGNED
# RED until C02 lands the overview.md replacement sentence; c6's comment +
# verdict reword to the retirement-compatible framing its three arms always
# had (they grep surviving structure, never the run-tag sentence); c7 admits
# the cf-90 plan folder + skills/wekan-board-provision (C01).
# KNOWN REDS in sibling suites (gate t17, coord-inwork i4, session-origin s4,
# kickoff-branch m4, wekan-mcp create-list t2) are pre-existing
# permissions-matrix/base drift tracked OUTSIDE cf-90 — cf-90 chunk gates
# never run those ids (the selection notes live in gate.sh's cf-90 header).
#
# c1 runs rulesync generate twice via the PATH/npx ladder; the first run may
# materialize pending generation, so the gate is that the SECOND run changes
# nothing. rulesync is ask-gated in unattended subagent shells, so an
# unresolvable binary skips with a warning (t14 precedent).
#
# CHUNK_BASE=<ref> makes the scope and additive-only checks diff against that
# commit (review passes the pre-chunk commit); default HEAD.
#
# Usage: bash tests/agent-board-coord/agents-md.sh            # c1..c9
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
  for i in $(seq 1 14); do WANT["c$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^c(1[0-4]|[1-9])$ ]] || fail "unknown check id '$a' (expected c1..c14)"
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

cat >"$TMP/negwin.py" <<'PY'
# Co-location window (the sibling suites' win.py convention, same code):
# needles must read as one passage; --ci folds case for prose needles.
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path).read()
if ci:
    text = text.lower(); needles = [n.lower() for n in needles]
pts = []
for n in needles:
    start, found = 0, 0
    while True:
        i = text.find(n, start)
        if i < 0:
            break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'missing needle: {n}'); sys.exit(1)
pts.sort()
need = len(set(needles))
cnt, have, best, left = {}, 0, None, 0
for right, (p, n) in enumerate(pts):
    cnt[n] = cnt.get(n, 0) + 1
    if cnt[n] == 1:
        have += 1
    while have == need:
        s = p - pts[left][0]
        if best is None or s < best:
            best = s
        cnt[pts[left][1]] -= 1
        if cnt[pts[left][1]] == 0:
            have -= 1
        left += 1
if best is None or best > span:
    print(f'no window of {span} chars covers all needles (min span {best})'); sys.exit(1)
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
# Two-era pin (the suite's own re-pin convention — "the pins move where the
# contract moves"): C02's pinned roster literal is the contract until C03
# rewrites the bullet to name the coord variants; whichever era the tree is
# in, the pre-split row must be gone once the dev variants exist. The
# presence of agent-coord-local.md selects the C03-era arm.
if want c2; then
  for f in AGENTS.md "$RULES_SRC"; do
    grep -q 'board-coord' "$f" || fail "c2: $f never names board-coord (the roster entry is missing)"
    grep -qF 'agent-{coord,plan,research,test,dev,review,fuser,board-coord}' "$f" \
      && fail "c2[cf-58 C02]: $f still carries the pre-split roster row verbatim (red posture: fires today until C02 lands)"
    grep -qF 'dev-pr' "$f" && grep -qF 'dev-local' "$f" \
      || fail "c2[cf-58 C02]: $f never names the dev variants (red before C02 — the split is invisible in the roster)"
    if [ -f .rulesync/subagents/agent-coord-local.md ]; then
      for name in agent-coord-local agent-coord-pr agent-board-coord-local agent-board-coord-pr; do
        grep -qF "$name" "$f" || fail "c2[cf-58 C03]: $f never names $name (C03's rewritten Agents bullet must name the coord variants + aliases)"
      done
      grep -qF '/pipeline-pr' "$f" || fail "c2[cf-58 C03]: $f lacks the /pipeline-pr launch guidance (C03's launch-sentence rewrite)"
      grep -qF '/pipeline-boards-pr' "$f" || fail "c2[cf-58 C03]: $f lacks the /pipeline-boards-pr command name"
    else
      grep -qF 'agent-{coord,plan,research,test,dev-pr,dev-local,review,fuser,board-coord}' "$f" \
        || fail "c2[cf-58 C02]: $f does not carry C02's pinned roster set agent-{...,dev-pr,dev-local,...} (red before C02)"
    fi
    grep -qF '/pipeline-boards' "$f" || fail "c2: $f never mentions /pipeline-boards"
  done
  ok "c2: roster era-correct (C02 literal or C03 variant names), pre-split row retired, board-coord + /pipeline-boards (+ /pipeline-pr post-C03) in AGENTS.md and the rules source"
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
    # cf-85 AC8: the summary surfaces name ONE field, and name it with the
    # combined value the field carries. `session` stays present as the retired
    # field's name (the line above pins that); the pair-as-two-fields wording
    # is fenced by rulesync-surface.sh c19's tree-wide negatives.
    grep -qF '[<slug>](' "$f" \
      || fail "c3[cf-85 AC8]: $f never states the combined [<slug>](<session link>) value of the slug field (red before the cf-85 flip)"
    grep -qF 'Model(s) checklist' "$f" \
      || fail "c3: $f does not route models from the Model(s) checklist alone (D12)"
    grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag' "$f" \
      || fail "c3: $f never retires the run tag for card-driven runs"
    # cf-90 C02 FLIP (2026-10-31): GLOBAL retirement replaces the old
    # 'agent-coord keeps run tags' posture — the keeps-wording is now the
    # defect, and the summary surfaces must state both-family scope with the
    # slug naming all four surfaces. Designed red until C02 lands.
    if grep -qF 'keeps run tags' "$f"; then
      fail "c3[C02 AC4]: $f still says agent-coord KEEPS run tags — the retirement is global (cf-90 C02); flip the sentence in the rules source, never by hand-editing AGENTS.md"
    fi
    if python3 "$TMP/negwin.py" --ci "$f" 1200 'run tag' 'retir' 'worktree' 'branch'; then :;
    elif python3 "$TMP/negwin.py" --ci "$f" 1200 'run tag' 'retir' 'session'; then :;
    else fail "c3[C02 AC4]: $f lacks the global retirement passage (run tag + retired + slug names worktree/branch/session) (red before C02 dev)"; fi
  done
  awk '/^## Agents/{f=1; next} /^## /{if (f) exit} f' AGENTS.md >"$TMP/agents-section.md"
  awk '/^## Feature pipeline/{f=1; next} /^## /{if (f) exit} f' AGENTS.md >"$TMP/fp-section.md"
  cat "$TMP/agents-section.md" "$TMP/fp-section.md" >"$TMP/new-text.md"
  python3 "$TMP/neg12.py" "$TMP/new-text.md" \
    || fail "c3: the new AGENTS.md text pairs 'models' with 'custom field' without negating it (D12)"
  ok "c3: pickup order, research-only -> Review, slug/session cf intake, cf- slug, GLOBAL run-tag retirement (cf-90 C02 flip: keeps-run-tags rejected), cf-85 combined [<slug>](<session link>) value; D12 negative holds in the new sections"
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
    echo "$row" | grep -qF 'dev-boards' \
      || fail "c5: $f board-coord row does not carry the NARROW dev-boards* spelling (D21 — server-name spelling, re-pinned 2026-10-27 by 2026-10-bug-board-coord-dev-boards-allow)"
    # The row may mention broad `dev*` ONLY as the denial D21 records; an
    # un-negated `dev*` in the row would re-grant the fleet-wide surface.
    if echo "$row" | grep -qF '`dev*`' && ! echo "$row" | grep -qE 'not[^|]*`dev\*`'; then
      fail "c5: $f board-coord row grants/mentions \`dev*\` without negating it — D21: narrow dev-boards* only"
    fi
    grep -qE '^\|[[:space:]]*coord[[:space:]]*\|' "$f" \
      || fail "c5: $f lost the coord row (merge, do not replace)"
  done
  ok "c5: permissions.md (source + generated) carries the board-coord row with narrow dev-boards*, coord row intact"
fi

# --- c6: the agent-coord text C04 must leave alone (C04 AC4) -------------------
# The live kickoff QUESTIONS and the pipeline-kickoff/pipeline-gates
# references stay (cf-90 C02 retires only the run tag, not the question
# flow — Q1 slug suggestions remain for cardless runs). Post-C02 the
# ok-note reads retirement-compatible: these arms never pinned the run-tag
# sentence itself, only the surviving structure (see c3 for the flipped
# run-tag pins).
if want c6; then
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'pipeline-kickoff' "$f" \
      || fail "c6: $f lost the pipeline-kickoff mention — agent-coord's live kickoff questions stand"
    grep -qF 'pipeline-gates` for' "$f" \
      || fail "c6: $f reworded the pipeline-skills sentence (the coord-side kickoff/model-routing description is out of C04's scope)"
    grep -qF 'Launch with' "$f" || fail "c6[cf-58 relaxed]: $f lost the /pipeline launch sentence — C03 may reword it (alias/-pr pairing), but launch guidance must exist"
  done
  ok "c6: the agent-coord kickoff/gates/launch sentences still present in source + AGENTS.md (cf-90 C02: questions stand, only the run tag retired — c3 pins the new posture)"
fi

# --- c7: scope — only C04's files changed (C04 AC3) -----------------------------
# tests-edit-perms D4/D9 widening: that ticket's agent-test/agent-dev pairs,
# the pipeline-overview pair (permissions.md is PERM_SRC/PERM_GEN, already
# admitted), the pipeline-role-test pair and the three follow-up ticket
# folders the cf-52 landing 124fc2ae8 introduced (folder patterns are inline
# literals so agent-perms A9 window-greps them inside this block).
# cf-75 widening (agent-test, same union-of-tickets convention): the new
# skills/wekan-mcp skill + the wekan-api pointer edit + the hand-managed
# .opencode/plugin/board-context plugin dir + this ticket's own plan folder
# (a scope guard that reds on the mere existence of the running ticket's
# folder buries every later check — cf-58's A9 note).
# cf-75 final-review widening: the OQ2-approved draft retirement is a coord
# bookkeeping write into the superseded sibling folder
# 2026-10-docs-wekan-mcp-arg-ergonomics (STATE.json, dca8a25d2) — same
# sanctioned-plan-folder class as c8's enumerations, admitted whole.
# cf-85 (2026-10-29): the running ticket's own plan folder joins the admit;
# its content edits ride the boards-skill, subagent, command, rules, AGENTS.md
# and tests/* admits already in this set.
# board-tick-cleanup widening (2026-10-29, agent-test): the hand-managed
# question-notify reader + the loop-file truth edit + this ticket's own plan
# folder (the agent-perms A9 window pin; a guard red on the running ticket's
# folder buries every later check).
# merge round (2026-10-30): cf-68 + cf-83 plan folders join the admit — `git merge
# main` moves the changed-paths walk across ticket-base boundaries, and a guard red
# on another ticket's already-landed folder buries every later check (same class as
# the own-folder admits above). containers/wekan-mcp/* joins per the c8 union —
# cf-68's create_list landed the container surface on this branch.
# cf-86 widening (C06 test round, 2026-10-30): cf-86's plan folder plus the
# exact serving files its chunks declare (chart values, the strata profile
# ConfigMap template, the gpu-ai overlay, the two docs pinned by
# test_strata_runbook.py (the runbook note and the parent
# README — added by the docs round) and that chart's tests
# tree — no
# directory admits, and no other chart or service. Why not manifest-driven:
# the c8 block of tests/agent-board-coord/rulesync-surface.sh.
# cf-86 C07 round (2026-10-31, owner U9.4): chunks/C07.md declares the strata
# image surfaces (Dockerfile, README, the three files/ entries, its test file) —
# admitted one path at a time, same reasoning as the chart trio above.
# cf-86 C09 round (2026-10-31, owner U11): + one exact path — the vendored
# carry/ornith-q36.patch chunks/C09.md declares (same one-path-at-a-time rule;
# rulesync-surface c8's probe loop keeps carry/ itself out).
# cf-90 widening (2026-10-31, agent-test): the running ticket's plan folder +
# the hand-written skills/wekan-board-provision dir (C01); its skill/command/
# agent/AGENTS/tests/loops/scripts edits ride the wildcards already in this set.
# cf-106 widening (2026-11-03, agent-test; chunks/C01.md "Scope admits"): the
# running ticket's own plan folder, admitted ONCE for the whole ticket (plan
# DECISIONS 2026-11-03) — its content surfaces already ride this set's
# .rulesync/*, .opencode/{agents,commands,skills}/*, AGENTS.md, tests/*,
# scripts/*, containers/wekan-mcp/*, skills/*, .opencode/plugin/* and
# .agents/loops/* admits. A replan-added file joins THIS line.
# cf-143 widening (2026-11-12, agent-test round, chunks/C01..C07): the
# radiance serving ticket — own plan folder (D9 rule) + its declared serving
# surfaces exact-style (cf-86 precedent): charts/radiance/* and
# charts/amd-gpu/* (the two new chart trees), charts/vllm/tests/* (the C01
# era re-pins ONLY — charts/vllm/** itself stays out, byte-untouched-
# disabled), the three render-test workflow files and the three notes docs.
# Its skills/catalog/llama-swap/gpu-ai/tests edits ride the
# .rulesync/skills/*, .opencode/skills/*, .opencode/opencode.jsonc,
# charts/llama-swap/{values.yaml,tests/*}, services/gpu-ai/prod/values.yaml
# and tests/* admits already in this set. A replan-added file joins THIS line.
# cf-55 widening (2026-11-16, agent-test re-anchor round; DECISIONS D31/D32):
# the plan folder joins ONCE for the rebuilt ticket (D9 rule, cf-106/cf-123
# precedent) plus the exact CHART-HALF surfaces its chunks declare:
# .forgejo/workflows/build-charts.yaml and its DELETED GitHub twin (the twin path
# is admitted in the composed ".github/"-quote form because this branch's
# tests/services/forgejo-ci-surface.sh sweeps live surfaces for the plain
# deleted path — the same convention the cf-55 suites follow), the C04
# enablement file custom-values/infra/prod-values.yaml (the first enumerated
# serving-custom-values exception in this arm), and the prose-truth files
# skills/helm-chart-creation/* + containers/renovate-mcp/Dockerfile (the
# comment-truth edits the dev round landed; the wekan-mcp pyproject comment
# rides the existing containers/wekan-mcp/* wildcard). The container half is
# cf-6's — NO docker-build or vllm-radiance
# admits, this branch touches neither. The strata guard re-point rides
# charts/llama-swap/tests/*; the cf-55 contract suites ride tests/*; the
# rules/skill sources + mirrors + AGENTS.md ride existing lines. A
# replan-added file joins THIS line, not a new arm.
# cf-126 C06 round-3 (D37 route b′): the committed .openchamber/project.json
# artifact + its canonical fixture join the admit union — the fixture rides
# tests/* already but is listed explicitly as the ruling's artifact pair (the
# void-whole-map invariant makes the trail worth two lines; same admit class
# as every per-ticket entry above).
# cf-55 FIX ROUND (2026-11-21 fix-wave test round; DECISIONS D41/D42,
# chunks/C05-C07): the fix round lands its own trees — the baked act job
# image containers/forgejo-runner/* (C05) and the runner chart the label
# re-point edits, charts/forgejo-runner/* (C06) — as directory admits per
# the cf-143 new-chart-trees precedent; the build-charts.yaml install retirement
# (C07) rides the arm above, the fix-round suites tests/*, the prose law
# the rules/mirrors/AGENTS.md lines.
# cf-55 ROUND 4 / C09 (2026-11-25 fix-wave successor round; DECISIONS
# D50.4/D51-Q3, chunks/C09.md): the bump-job lock self-heal commits the three
# REGENERATED drift-trio locks (charts/base/Chart.lock,
# charts/traefik/Chart.lock, charts/traefik-zerotrust/Chart.lock) and the
# D51-Q1 fold lands the traefik >=42.4 additionalProperties:false schema
# migration (service.type under spec:) in the two traefik charts' values
# files (charts/traefik/values.yaml, charts/traefik-zerotrust/values.yaml) —
# five explicit per-file joins, deliberately NOT a charts/* wildcard (a
# catch-all would outlive the ticket and admit every future chart surface);
# build-charts.yaml and the suites ride the cf-55 arms above per the fix-round
# paragraph. A replan-added file joins THIS line.
# cf-55 ROUND 4 / C12 (2026-11-25, route F approved by D49; chunks/C12.md):
# .forgejo/workflows/renovate.yaml joins as an EXACT path — the first
# cf-55-round edit of that file (dev commit 93cb79107: the -full image swap
# behind the helm4-writes/helm3-builds digest cross-check gate plus the
# declared RENOVATE_BINARY_SOURCE pair, r2 APPROVED). The fix rounds admitted
# the builder path only and the C09 join above covered the locks + values, so
# the branch delta tripped this arm until the carryover fold — exact path,
# no .forgejo/workflows/* wildcard (main-sync/containers-build stay outside;
# C11's rename will flip the release line, not add a sibling — since
# superseded 2026-11-25: the C11 fold in this region joins main-sync
# explicitly, containers-build still stays outside).
# cf-55 ROUND 4 / C11 (2026-11-25, owner Q3 "rename, LANDS LAST";
# chunks/C11.md): the git mv renames the admitted builder path — the old
# .forgejo/workflows/release.yaml became build-charts.yaml (since renamed;
# the composed ".github/" twin entry stays forever, the deleted GitHub twin
# keeps its historical name). Two new per-file joins for the rename's own
# edits, neither wildcard-covered: .forgejo/workflows/main-sync.yaml (the
# anchor cite re-pin — the C09 header edit shifted the detect-step env block
# off :54, cites moved to the verified true number :57) and
# charts/prowlarr/Chart.yaml (its shipped comment re-truth; touching
# charts/** makes the rename merge the designed first fire under heal +
# calendar, plan Round-4 landing #4). The renamed suite, surface.sh and the
# strata pins ride the existing tests/* and charts/llama-swap/tests/*
# wildcards. A replan-added file joins THIS line.
# bug-board-preload-lean-consumer (2026-11-21, agent-test, C01 Tests): this ticket's own plan folder
# joins on the once-per-ticket rule (cf-106 precedent row) — its six in-scope
# files already ride tests/*, .rulesync/skills/* and .opencode/skills/*; the
# amendment is skill-side only (plan D8), so nothing else joins.
# cf-55 ROUND 5 (2026-11-26, chunks/C14-C16.md; D52-D59): the shared-marker
# adaptation edits the PRE-RENAME container-builder workflow (C14 ref rename
# + ancestor tolerance) and C15's git mv lands it as build-containers.yaml —
# both paths join (the mv surfaces the deleted pre-rename path as one side
# of the delta; the bare literal is quote-composed below so the ci-surface
# t8 containers-era sweep never reads this arm as a live claim).
# renovate.json joins for the pin-7 description re-pin, and the two services
# values files for the C16 per-slice replicas (D57 owner ruling). The
# renamed suite rides tests/*, the detect script scripts/*,
# charts/forgejo-runner/values.yaml the existing charts/forgejo-runner/*
# wildcard (C16 asked to verify — covered), and the prowlarr admit already
# stands from the C11 round (C13's fold is a no-op there). A replan-added
# file joins THIS line.
# cf-55 ROUND 5 / C15 (2026-11-26, D56; chunks/C15.md): the rename's
# collateral comment re-truths are forced on live surfaces by ci-surface
# t8's armed containers sweep — join lines extended with
# .github/workflows/docker-build.yaml:5 (the GitHub twin citing the forge
# builder) and containers/vllm-radiance-mxfp4/{Dockerfile,README.md}
# (first-build calendar-tag cites). Exact per-file joins, no wildcards;
# the rebuild round's "NO docker-build or vllm-radiance admits" premise
# assumed the branch touches neither — C15's fence says otherwise.
# cf-55 ROUND 6 / C17 (2026-11-26, owner ruling D64; chunks/C17.md): the two
# runner custom-values files join as EXACT per-file admits (comment-only
# registration-token re-truths; the KEY names and UUIDs stay). Chart moves
# are already covered by charts/forgejo-runner/* — bash case globs span
# '/', so an admitted path needs no new join regardless of diff status.
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
      .rulesync/skills/boards/*|.opencode/skills/boards/*|\
      .rulesync/subagents/agent-test.md|.opencode/agents/agent-test.md|\
      .rulesync/skills/agents-sync/references/pipeline-overview.md|.opencode/skills/agents-sync/references/pipeline-overview.md|\
      .rulesync/skills/pipeline-role-test/*|.opencode/skills/pipeline-role-test/*|\
      .agents/plans/2026/2026-10-bug-kickoff-mints-run-branch/*|\
      .agents/plans/2026/2026-10-bug-session-origin-no-line/*|\
      .agents/plans/2026/2026-10-bug-tests-edit-perms/*|\
      .rulesync/subagents/*|.opencode/agents/*|.rulesync/commands/*|.opencode/commands/*|\
      .rulesync/skills/*|.opencode/skills/*|.opencode/opencode.jsonc|\
      .agents/plans/2026/2026-10-cf-58-feat-standalone-agent-merge/*|\
      .agents/plans/2026/2026-10-bug-board-coord-dev-boards-allow/*|\
      skills/wekan-mcp/*|skills/wekan-api/*|containers/wekan-mcp/*|skills/container-creation/*|.opencode/plugin/board-context/*|\
      .opencode/plugin/pipeline-locks/*|\
      .opencode/plugin/question-notify/*|.agents/loops/*|\
      .agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/*|\
      .agents/plans/2026/2026-10-docs-wekan-mcp-arg-ergonomics/*|\
      .agents/plans/2026/2026-10-chore-board-tick-cleanup/*|\
      .agents/plans/2026/2026-10-cf-68-feat-wekan-mcp-create-list/*|\
      .agents/plans/2026/2026-10-cf-83-refactor-strata-flash/*|\
      .agents/plans/2026/2026-10-cf-85-refactor-wekan-slug-session-link/*|\
      .agents/plans/2026/2026-10-cf-72-chore-coord-git-read-globs/*|\
      .agents/plans/2026-10-30-chore-coord-surface-grants.md|\
      .agents/plans/2026/2026-10-cf-86-feat-more-strata-models/*|\
      charts/llama-swap/values.yaml|charts/llama-swap/templates/configmap-strata-profile.yaml|\
      services/gpu-ai/prod/values.yaml|charts/llama-swap/tests/*|\
      .agents/notes/strata-host-prep-gpu-ai.md|charts/llama-swap/README.md|\
      containers/strata/Dockerfile|containers/strata/README.md|\
      containers/strata/files/fetch_models.sh|containers/strata/files/hf_fetch.py|\
      containers/strata/files/byte_pins.env|containers/strata/tests/test_dockerfile.py|\
      containers/strata/carry/ornith-q36.patch|\
      .agents/plans/2026/2026-10-cf-90-feat-board-coord-improvements/*|\
      .agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/*|\
      charts/coder/coder-templates/kubernetes/main.tf|charts/coder/coder-templates/kubernetes-hardened/main.tf|\
      skills/wekan-board-provision/*|\
      .agents/plans/2026/2026-11-cf-106-feat-coord-fixes/*|\
      .agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/*|\
      .agents/plans/2026/2026-11-cf-126-feat-compaction-pipeline-sessions/*|\
      .openchamber/project.json|\
      tests/openchamber-project/default-summary-instructions.txt|\
      .agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/*|\
      charts/radiance/*|charts/amd-gpu/*|charts/vllm/tests/*|\
      .github/workflows/vllm-render-tests.yaml|.github/workflows/radiance-render-tests.yaml|\
      .github/workflows/amd-gpu-render-tests.yaml|\
      .agents/notes/vllm-on-target-acceptance.md|.agents/notes/radiance-on-target-acceptance.md|\
      .agents/notes/radiance-second-gpu-tp2.md|\
      .agents/plans/2026/2026-11-cf-55-feat-helm-builds-to-forgejo/*|\
      .forgejo/workflows/build-charts.yaml|".github/"workflows/release.yaml|\
      custom-values/infra/prod-values.yaml|skills/helm-chart-creation/*|\
      containers/renovate-mcp/Dockerfile|\
      charts/forgejo-runner/*|containers/forgejo-runner/*|\
      charts/base/Chart.lock|charts/traefik/Chart.lock|charts/traefik-zerotrust/Chart.lock|\
      charts/traefik/values.yaml|charts/traefik-zerotrust/values.yaml|\
      .forgejo/workflows/renovate.yaml|\
      .forgejo/workflows/main-sync.yaml|charts/prowlarr/Chart.yaml|\
      .forgejo/workflows/"containers-build".yaml|.forgejo/workflows/build-containers.yaml|renovate.json|\
      .github/workflows/docker-build.yaml|containers/vllm-radiance-mxfp4/Dockerfile|containers/vllm-radiance-mxfp4/README.md|\
      services/dev/prod/values.yaml|services/gpu/prod/values.yaml|\
      custom-values/dev/prod-values.yaml|custom-values/gpu/prod-values.yaml|\
      .agents/plans/2026/2026-11-bug-board-preload-lean-consumer/*|\
      .agents/plans/2026-11-07-bug-question-notify-instance-fanout.md) : ;;
      *) fail "c7: path outside C04's in-scope set: $p (base: $BASE; cf-124 plan-folder + cf-143 radiance + cf-55 chart-half admits in the union)" ;;
    esac
  done <"$TMP/changed.txt"
  ok "c7: changed paths limited to the in-scope files (C04 set + cf-50/cf-52 + tests-edit-perms D4/D9 + cf-58 agent-surface + cf-75 wekan-mcp/board-context/plan-folder + cf-85/cf-72/board-tick-cleanup plan-folder widenings + cf-88 surface-grants root plan doc + cf-86 plan-folder/serving-files/docs/image-build-surface widenings + cf-96 plan-folder and C09 coder-template admits + cf-106 own-folder admit + cf-124 plan-folder admit + cf-126 own-folder + D37 artifact admits (.openchamber/project.json + canonical fixture) + cf-143 plan-folder/new-chart-trees/vllm-tests-era/workflows/docs admits + cf-55 own-folder + chart-half surface admits (Forgejo release builder, deleted GitHub twin, C04 infra values, helm-chart-creation skill, renovate-mcp comment truth) + cf-55 fix-round directory admits (charts/forgejo-runner, containers/forgejo-runner) + cf-123 own-folder admit (bug-board-preload-lean-consumer) + 2026-11-07 fan-out-dedup standalone root plan doc + cf-55 round-4/C09 per-file admits (the three regenerated drift-trio Chart.locks + the two traefik values files, D51-Q1/Q3) + cf-55 round-4/C12 admit (the renovate workflow's -full image+env pair behind the digest gate, D49, dev 93cb79107); base: $BASE)"
fi

# --- c8: no other AGENTS.md section changed (C04 AC4) ---------------------------
# Section-level comparison, not line-level: an in-line extension reads as
# deletion+addition and would hide a cross-section edit in a line diff.
# board-tick-cleanup C02 widens the allowed set with "Pipeline worker
# iterations" — the OQ10 docs-only truth task + silence rule edit exactly that
# section's worker sentence (chunks/C02.md Tasks; AGENTS.md regenerates from
# the sanctioned .rulesync/rules/overview.md delta). cf-124 C05 (AC7, D28)
# widens it further with "Hard rules" — the gated-mint clause is an approved
# amendment to the feature-branch hard rule, mandated in overview.md and
# regenerated into AGENTS.md by exactly that section (its content is pinned by
# c12, the same division of duty as every other widened section).
# cf-6 (merged on main) and the cf-55 re-anchor round (2026-11-16, DECISIONS
# D31/D32) both rewrite "Hard rules" — the calendar-tag/forge-builder
# sentence and the chart release clause + instance credential law. The
# merged cf-6 wave landed its section edit without widening this arm (its
# chunk gates saw AGENTS.md committed); at cf-55's final review the section
# differs from the base for real, so the set names it now.
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
allowed = {"Where things live", "MCP servers", "Agents", "Feature pipeline (agent-*)", "Pipeline specifics in this repo",
           "Pipeline worker iterations", "Hard rules"}
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

# --- c9: cf-58 AGENTS.md + rules content — Lifecycle wording + dev family --------
# C05: the board-coord specifics bullet re-names the checklist (Lifecycle,
# eight stages, checked-stages-only) and the old slash-enumeration naming
# Research-as-checklist is gone. C04: a STANDALONE dev-family entry (the
# line naming dev-local/dev-pr WITHOUT the agent- prefix — the pipeline
# family cannot satisfy it). Red before C04/C05 — the new wording is absent
# and the retired enumeration still present.
if want c9; then
  for f in AGENTS.md "$RULES_SRC"; do
    python3 "$TMP/negwin.py" --ci "$f" 400 'lifecycle' 'checked' \
      || fail "c9[cf-58 C05]: $f lacks the Lifecycle wording (checked-stages-only — the board-coord bullet rewrite; red before C05)"
    # cf-124 C01 re-pin: the paragraph now names the 13-item generation — the
    # count, the nine-stage default, and the two gated leading stages. These
    # move the pins where the contract moved; the old counts become rejects.
    python3 "$TMP/negwin.py" --ci "$f" 700 'lifecycle' '13-item' \
      || fail "c9[cf-124 C01]: $f's board-coord paragraph does not name the 13-item checklist (the cf-124 vocabulary generation; red until C01 moves overview.md and regenerates)"
    python3 "$TMP/negwin.py" --ci "$f" 700 'default' 'nine stages' \
      || fail "c9[cf-124 C01]: $f never pairs the default loop with the nine stages the Blank defaults section names (D16; red until C01 dev)"
    python3 "$TMP/negwin.py" --ci "$f" 1200 'lifecycle' 'session rename' 'worktree creation' \
      || fail "c9[cf-124 C01]: $f's stage sentence never names the two gated leading stages (Session Rename + Worktree Creation, D15) — the paragraph must show what the checklist now starts with (red until C01 dev)"
    if grep -qE 'the 11-item checklist|seven stages' "$f"; then
      fail "c9[cf-124 C01 negative]: $f still carries the pre-cf-124 counts (11-item checklist / seven stages) — this is a current-state summary surface; the generation move must rewrite it in the same commit"
    fi
    if grep -qE 'Model\(s\)[[:space:]]*/[[:space:]]*Research([[:space:]]*/[[:space:]]*Human| checklists)' "$f"; then
      fail "c9[cf-58 C05]: $f still enumerates the retired Research CHECKLIST (Model(s)/Research/... or 'Research checklists') — the LABEL wording may stay, the checklist enumeration must become Lifecycle"
    fi
    python3 - "$f" <<'PY' || fail "c9[cf-58 C04]: $f has no standalone dev-family line (a line naming dev-local AND dev-pr without the agent- prefix — red before C04)"
import sys
lines = open(sys.argv[1]).read().splitlines()
hits = [l for l in lines if "dev-local" in l and "dev-pr" in l]
standalone = [l for l in hits if "agent-" not in l]
sys.exit(0 if standalone else 1)
PY
  done
  ok "c9: AGENTS.md + rules carry the cf-124 Lifecycle wording (13-item checklist, nine-stage default, the two gated leading stages named, old counts rejected), the retired Research-checklist enumeration is gone, and the standalone dev family has its own entry"
fi

# --- c10: the worker alert sentence covers every stop path (cf-106 C03b AC6/AC7) -------
if want c10; then
  # The alert sentence is the one place AGENTS.md states when a scheduled tick
  # stays quiet. C03b extends it from "the coord marked it no-work" to "EVERY stop
  # path marks and archives, including the gate/tick stops" — the generated file
  # and the rules source must both carry it (rulesync parity is c1's job; here the
  # claim itself is pinned on both surfaces so neither drifts alone).
  for f in "$RULES_SRC" AGENTS.md; do
    [ -f "$f" ] || fail "c10[cf-106 C03b AC6]: $f missing (harness fault)"
    python3 "$TMP/negwin.py" --ci "$f" 400 'scheduled' 'no-work' \
      || fail "c10[cf-106 C03b AC6]: $f lost the silence-rule clause (the scheduled finished push happens unless the coord marked the session no-work) — HOLD arm, it must survive C03b's edit"
    python3 "$TMP/negwin.py" --ci "$f" 400 'no-op marker' 'stop' 'mark' \
      || fail "c10[cf-106 C03b AC6]: $f's alert sentence never pairs the no-op marker with the STOP paths in one passage — C03b's point is that a tick ending on a gate SKIP / LIVE-with-cards / board-check stop marks and archives too, and the generated rule must say so or AGENTS.md contradicts the boards skill (red until C03b edits the rules source and regenerates)"
  done
  # Negative control: the pin must not be satisfied by today's marker sentence —
  # the coverage words must actually be next to it. A copy with the stop-path
  # wording moved 1200 chars away must fail.
  python3 - "$RULES_SRC" "$TMP/rules-moved.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.find("no-op marker")
pad = " ".join(f"filler {k}" for k in range(240))
open(sys.argv[2], "w", encoding="utf-8").write(t[:i] + "no-op marker " + pad + "marks every stop path" + t[i + len("no-op marker"):])
PY
  if python3 "$TMP/negwin.py" --ci "$TMP/rules-moved.md" 400 'no-op marker' 'stop' 'mark' >/dev/null 2>&1; then
    fail "c10 control: the coverage wording separated from the marker sentence by 1200 chars of filler still passed — the window pin does not require the coverage to ride the alert sentence"
  fi
  ok "c10[cf-106 C03b AC6/AC7]: the silence clause survives and the alert sentence gains the stop-path coverage on rules source and generated AGENTS.md alike"
fi

# --- c11: the worker paragraph — one loop file, the ruled model, per-card Provider (cf-106 C10 AC4) ---
if want c11; then
  # C10's rules edit lands here: the pipeline-worker paragraph names ONE loop
  # file, the owner-ruled runner model, and Provider routing per card. Both
  # surfaces are pinned (rulesync regenerates AGENTS.md from the source; the
  # claim must be present on each so a one-sided edit reddens).
  for f in "$RULES_SRC" AGENTS.md; do
    [ -f "$f" ] || fail "c11[cf-106 C10 AC4]: $f missing (harness fault)"
    python3 "$TMP/negwin.py" --ci "$f" 900 'loop' 'gpu-ai/qwen3.8-flash-next-radiance' \
      || fail "c11[cf-106 C10 AC4, re-pinned 2026-11-22]: $f does not pair the loop/worker paragraph with the owner-ruled runner model gpu-ai/qwen3.8-flash-next-radiance — the runner literal moved cf-106 OQ-14 2026-11-03 (27b-q4) -> owner ruling 2026-11-09 (strata-q4) -> owner ruling 2026-11-22 (radiance, 2026-11-feat-radiance-multi-instance D16); red until C02 edits the rules source and regenerates"
    # The paragraph must cite the chain, not just the newest date: the
    # supersession is by citation, never by deletion (D23).
    python3 "$TMP/negwin.py" --ci "$f" 1200 'gpu-ai/qwen3.8-flash-next-radiance' '2026-11-22' \
      || fail "c11[cf-106 C10 AC4, re-pinned 2026-11-22]: $f names the radiance runner literal without the dated ruling behind it (2026-11-22) in the same paragraph"
    python3 "$TMP/negwin.py" --ci "$f" 1200 'runner model' 'cf-106 OQ-14' \
      || fail "c11[cf-106 C10 AC4, re-pinned 2026-11-22]: $f's runner-model sentence lost the chain origin (cf-106 OQ-14) — the 2026-11-22 ruling supersedes 2026-11-09, which superseded OQ-14; the paragraph keeps the chain"
    python3 "$TMP/negwin.py" --ci "$f" 900 'loop' 'one' 'pipeline-worker.md' \
      || fail "c11[cf-106 C10 AC4]: $f still describes the loop surface as a pair — the paragraph must name the single pipeline-worker.md runner"
    # Shell-level alternation: negwin.py's needles are literal (str.find),
    # so a grep-E-style 'per-card|per card|rout' string was satisfiable only
    # by the pipe string itself — one honest spelling per window call.
    if ! { python3 "$TMP/negwin.py" --ci "$f" 900 'provider' 'per-card' \
        || python3 "$TMP/negwin.py" --ci "$f" 900 'provider' 'per card' \
        || python3 "$TMP/negwin.py" --ci "$f" 900 'provider' 'rout'; } \
        >"$TMP/c11-route.out" 2>&1; then
      cat "$TMP/c11-route.out" >&2
      fail "c11[cf-106 C10 AC4]: $f never says Provider is per-card routing inside the run (no per-card / per card / rout spelling within 900 chars of provider) — the scheduler split is retired"
    fi
    strays=$(grep -inE 'pipeline-worker-local|two loop (files|tasks)|both loop tasks' "$f" || true)
    [ -z "$strays" ] || { printf '%s\n' "$strays" >&2; fail "c11[cf-106 C10 AC4]: $f still names the retired second loop task in current-state prose"; }
    # The gate/LIVE/Timeout sentences stay accurate through the rewrite (C10 task).
    for tok in 'LIVE' 'Timeout'; do
      grep -qF "$tok" "$f" || fail "c11[cf-106 C10 AC4]: $f lost the '$tok' sentence — the gate/Timeout wording stays accurate, C10 does not rewrite it"
    done
  done
  # Fabricated-drift control: restoring the pair sentence must redden the sweep.
  python3 - "$RULES_SRC" "$TMP/rules-pair.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(
    t + "\nThe two loop tasks, pipeline-worker.md and pipeline-worker-local.md, split the hourly ticks.\n")
PY
  if ! grep -qiE 'pipeline-worker-local|two loop (files|tasks)' "$TMP/rules-pair.md"; then
    fail "c11 control: the fabricated pair sentence was not caught by the sweep (the guard is inert)"
  fi
  # Negative control for the routing arm: with the routing sentence deleted
  # the disjunction must fail, and its failure must name one of the three
  # alternatives — a control that only asserts "fails" cannot see a dead
  # branch of the alternation.
  if ! python3 - "$RULES_SRC" "$TMP/rules-noroute.md" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"The\s+Provider label is per-card routing.*?unlabeled-card ask\)\.\s", t, re.S)
if not m:
    sys.exit("c11 control: the routing sentence is not in the expected shape in " + sys.argv[1])
open(sys.argv[2], "w", encoding="utf-8").write(t[:m.start()] + t[m.end():])
PY
  then
    fail "c11 control: the routing-deleted copy could not be fabricated (fixture fault)"
  fi
  if { python3 "$TMP/negwin.py" --ci "$TMP/rules-noroute.md" 900 'provider' 'per-card' \
      || python3 "$TMP/negwin.py" --ci "$TMP/rules-noroute.md" 900 'provider' 'per card' \
      || python3 "$TMP/negwin.py" --ci "$TMP/rules-noroute.md" 900 'provider' 'rout'; } >"$TMP/noroute.out" 2>&1; then
    fail "c11 control: the routing-passage-deleted copy still satisfies the per-card routing arm — the alternation is inert"
  fi
  if ! grep -qE 'missing needle: (per-card|per card|rout)' "$TMP/noroute.out"; then
    cat "$TMP/noroute.out" >&2
    fail "c11 control: the deleted copy failed the arm without a missing-needle naming one of the three alternatives — the failure is not the arm's"
  fi
  ok "c11[cf-106 C10 AC4, re-pinned 2026-11-22]: the worker paragraph names one loop file, the ruled gpu-ai/qwen3.8-flash-next-radiance model with its dated ruling chain, and per-card Provider routing on rules source and generated AGENTS.md, keeps the gate/Timeout sentences, a fabricated pair sentence is rejected, and deleting the routing sentence reddens the routing arm"
fi

# --- c12: cf-124 C05 — the feature-branch hard rule gains the gated-mint clause --
# C05 appends to the hard rule (overview.md:418 → AGENTS.md) that a board run
# whose checked set omits `Worktree Creation` works UNCOMMITTED, IN PLACE, in
# whatever checkout it lands in (main included) and its coordinator makes NO
# COMMITS, so never-advance-`main` is honoured by the absence of commits.
# Needles only (the law is the semantic pairing, never a prose copy); designed
# red before C05 dev. The shipped feature-branch law must survive intact.
if want c12; then
  # Window-bite proof (self-contained, holds today and after C05): the SAME
  # needles must read clean when co-located and must fail when the commit-rule
  # spelling is moved >1200 chars away — proof c12 demands co-location, not
  # file-wide scatter (the c10/c11 control discipline).
  python3 - "$TMP/c12-co.md" "$TMP/c12-moved.md" <<'PY'
import sys
clause = "A board run whose checked set omits `Worktree Creation` works uncommitted, in place, in whatever branch it landed in, main included, and its coordinator makes no commits at all."
pad = " ".join(f"filler {k}" for k in range(400))
open(sys.argv[1], "w").write(clause + "\n")
head, _, tailc = clause.partition("no commits")
open(sys.argv[2], "w").write(head + pad + "no commits" + tailc + "\n")
PY
  python3 "$TMP/negwin.py" --ci "$TMP/c12-co.md" 900 'worktree creation' 'uncommitted' >/dev/null 2>&1 \
    || fail "c12 control: the fabricated co-located clause failed its own window — the pin is unsatisfiable by the planned C05 sentence (harness fault)"
  python3 "$TMP/negwin.py" --ci "$TMP/c12-co.md" 900 'uncommitted' 'no commits' >/dev/null 2>&1 \
    || fail "c12 control: the compliant copy lost the zero-commit pairing — fabricate fault (harness)"
  if python3 "$TMP/negwin.py" --ci "$TMP/c12-moved.md" 900 'worktree creation' 'no commits' >/dev/null 2>&1; then
    fail "c12 control: the moved copy satisfied the 900-char window across 1200+ chars of filler — the co-location pin is inert"
  fi
  for f in "$RULES_SRC" AGENTS.md; do
    [ -f "$f" ] || fail "c12[cf-124 C05]: $f missing (harness fault)"
    python3 "$TMP/negwin.py" --ci "$f" 900 'worktree creation' 'uncommitted' \
      || fail "c12[cf-124 C05 AC1/AC2]: $f's feature-branch rule does not pair the unchecked Worktree Creation with the uncommitted-in-place posture (D28; red until C05 edits the rules source and regenerates)"
    # Zero-commit rule, one honest spelling per window call (negwin needles are
    # literal — the c11 routing-alternation discipline).
    if ! { python3 "$TMP/negwin.py" --ci "$f" 900 'uncommitted' 'no commits' \
        || python3 "$TMP/negwin.py" --ci "$f" 900 'uncommitted' 'never commit' \
        || python3 "$TMP/negwin.py" --ci "$f" 900 'uncommitted' 'commits nothing' \
        || python3 "$TMP/negwin.py" --ci "$f" 900 'uncommitted' 'makes no commit'; } \
        >"$TMP/c12-nocommit.out" 2>&1; then
      cat "$TMP/c12-nocommit.out" >&2
      fail "c12[cf-124 C05 AC1/AC2]: $f never pairs the uncommitted posture with the zero-commit rule (no commits / never commit / commits nothing / makes no commit) in one passage — D28's safety property is the ABSENCE of commits"
    fi
    python3 "$TMP/negwin.py" --ci "$f" 1200 'uncommitted' 'main' \
      || fail "c12[cf-124 C05 AC2]: $f states the uncommitted posture without naming main in the same passage — the clause must make clear working on main is permitted while committing there is not"
    grep -qF 'feature/fix branch' "$f" \
      || fail "c12[cf-124 C05 negative]: $f lost the feature/fix-branch hard rule the D28 clause extends — the amendment rides beside the law, never replaces it"
  done
  ok "c12[cf-124 C05 AC1/AC2]: the feature-branch hard rule carries the gated-mint clause — unchecked Worktree Creation pairs with uncommitted-in-place work, a zero-commit spelling, and main named in the same breath, while the feature/fix-branch law survives (rules source + generated AGENTS.md; red until C05 edits and regenerates); the window control proves co-location is required"
fi

# --- c13: cf-126 C01 AC7 — the worker paragraph states the dispatcher model ----
# The "Pipeline worker iterations" rewrite + the Agents-section roster mention
# are one generated pair: overview.md is the source, AGENTS.md regenerates, so
# both surfaces must carry the doctrine or the mirror and the law disagree.
# Needles only (the semantic pairing, never a prose copy): loop vehicle = the
# NEW pipeline-dispatch.md, the dispatcher agent name, the release wake, the
# delegated exit, the fallback path; plus the agent-* paragraph naming
# agent-board-dispatch beside the family. DESIGNED RED until C01 edits
# overview.md and regenerates. c8's section-allow set already admits "Pipeline
# worker iterations" and "Agents" — no widening owed here.
if want c13; then
  for f in "$RULES_SRC" AGENTS.md; do
    [ -f "$f" ] || fail "c13[C01 AC7]: $f missing (harness fault)"
    python3 "$TMP/negwin.py" --ci "$f" 2400 'pipeline-dispatch' 'agent-board-dispatch' \
      || fail "c13[C01 AC7]: $f's worker section does not pair the NEW loop file pipeline-dispatch.md with the agent-board-dispatch runner — the OQ1 second-file ruling must read in the doctrine (red before C01 dev)"
    python3 "$TMP/negwin.py" --ci "$f" 2400 'release' 'wake' 'delegated' \
      || fail "c13[C01 AC7/D6/D15]: $f never pairs the lock-release wake with the delegated no-op exit — both are the dispatcher model's visible surface in the worker paragraph (red before C01 dev)"
    python3 "$TMP/negwin.py" --ci "$f" 2400 'fallback' 'walk' \
      || fail "c13[C01 AC7/D5]: $f lost the fallback law (the walk stays in the coord for /pipeline-boards, /pipeline-boards-hourly and a manual named-card launch — the evaluation answer) — must stay stated (red before C01 dev)"
    # The gate now counts the dispatcher name (OQ2): the worker paragraph must
    # pair the gate with the dispatcher for the cutover to read truthfully.
    python3 "$TMP/negwin.py" --ci "$f" 900 'gate' 'dispatcher' \
      || fail "c13[C01 AC7/OQ2]: $f's worker paragraph never pairs the gate with the dispatcher — the widened liveness count is part of the shape it must teach (red before C01 dev)"
    # The Agents-section roster mention (AC7 tail).
    python3 "$TMP/negwin.py" --ci "$f" 1600 'agent-board-coord-pr' 'agent-board-dispatch' \
      || fail "c13[C01 AC7]: $f's agent-family paragraph does not name agent-board-dispatch beside the board-coord variants (red before C01 dev)"
  done
  # Fabricated-drift control: a copy with the loop-file name moved out of
  # every window must redden the pairing arms (c10/c11 control discipline).
  python3 - "$RULES_SRC" "$TMP/c13-off.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read().replace("pipeline-dispatch", "pipeline-XXXXX")
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY
  if python3 "$TMP/negwin.py" --ci "$TMP/c13-off.md" 2400 'pipeline-dispatch' 'agent-board-dispatch' >/dev/null 2>&1; then
    fail "c13 control: the renamed-loop-file copy still passed the pairing arm — the pin is vacuous"
  fi
  ok "c13[C01 AC7]: worker paragraph states the dispatcher model (loop vehicle, runner, release wake, delegated, fallback, gate count) and the family paragraph names agent-board-dispatch, on rules source AND generated AGENTS.md; the fabricated rename control reddens"
fi

# --- c14: cf-126 C02 AC5 — the privilege paragraph gains the global-MCP line ----
# The MCP section's "Agent privilege rules" paragraph gains one line (the
# C02 task): the coord family + agent-board-dispatch carry the tier-less
# global-* and readonly-global-* grants, the admin-* tier stays
# user-confirmation-gated as for the code agent. The per-server TABLE is
# byte-unchanged (c4 pins its dev row; a table edit reddens there and in
# c8's section diff) — this arm pins the paragraph line alone. DESIGNED RED
# until C02 lands.
if want c14; then
  for f in "$RULES_SRC" AGENTS.md; do
    python3 "$TMP/negwin.py" --ci "$f" 700 'coord family' 'global-' \
      || fail "c14[C02 AC5]: $f's privilege rules never pair the coord family with the global- grants (read-only tiers only; red before C02 dev)"
    python3 "$TMP/negwin.py" --ci "$f" 900 'admin' 'confirmation' \
      || fail "c14[C02 AC5]: $f lost the admin-tier confirmation caveat in the privilege rules (it must ride beside the new grant line, not vanish with the rewrite; red before C02 dev)"
  done
  # Fabricated drift: the admitted line removed from a copy must redden the
  # first window (the plan names this exact probe).
  python3 - "$RULES_SRC" "$TMP/c14-off.md" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"[^\n]*coord family[^\n]*global-[^\n]*\n", t, re.I)
if not m:
    sys.exit(0)  # the live arms are already red pre-C02; nothing to strip
open(sys.argv[2], "w", encoding="utf-8").write(t[:m.start()] + t[m.end():])
PY
  if [ -s "$TMP/c14-off.md" ]; then
    python3 "$TMP/negwin.py" --ci "$TMP/c14-off.md" 700 'coord family' 'global-' >/dev/null 2>&1 \
      && fail "c14 control: deleting the privilege line did not redden the pairing — the pin rides scattered text, not the line"
  fi
  ok "c14[C02 AC5]: the privilege paragraph pairs the coord family with the global- grants and keeps the admin-confirmation caveat on both surfaces; the line-deleted control reddens"
fi

printf 'PASS: agent-board-coord agents-md checks (%d ok)\n' "$checks"
