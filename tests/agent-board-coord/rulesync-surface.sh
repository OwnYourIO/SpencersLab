#!/usr/bin/env bash
# agent-board-coord surface contract (2026/2026-10-feat-board-coord-intake,
# C02 + C03, with c6 landing at C04): the boards skill as the redesigned
# card-driven intake contract, the agent-board-coord body + /pipeline-boards
# command reworded to it, and the permissions matrix row.
#
# RE-CREATED on the re-cut base as a SUPERSET of the deleted
# `git show 09696ae57:tests/agent-board-coord/rulesync-surface.sh` (D25): c1-c8
# keep the upstream ticket's pinned contracts (five section titles, the
# frontmatter shape, narrow dev-boards*, the launch-command target) so the
# new checks extend, never replace, them (D7). Deliberate adaptations to the
# new base: id selection so C02/C03 reviews can run before C04 lands the
# permissions row (the dev-mcp-fleet.sh convention), the rulesync npx ladder
# with skip-with-warning (the binary is ask-gated in subagent shells —
# FRICTION note, t14 precedent), and the c8 allow-set widened to the union of
# THIS ticket's four chunks (the old scope belonged to the old C05).
#
# Contract source: chunks/C02.md + chunks/C03.md "## Tests". AC trace:
# c1[AC-files] c2[C03 AC3 + D21; cf-52 RE-PIN: $PORT_REF frontmatter delta is
# a sanctioned shell-allow form (the two scoped session allows; kickoff-mints
# C02 extends the sanctioned forms to the three-allow SHELL3; session-origin
# C02 extends them to the four-allow SHELL4)] c3[C03 AC4] c4[C02 AC2] c5[C03 command]
# c6[C04 AC2 — green only once C04 lands] c7[C02 AC3] c8[C02 AC4 scope;
# cf-52 widenings] c9[C02 AC5 + C03 AC4] c10[C02 AC1 pickup order] c11[C02
# AC1 checklists + D9 drift detector] c12[C02 AC1 slug/session/cf- + cf-50 round-2 RE-PIN:
# dead-literal ABSENCE + dynamic Session-origin phrases + D12 negative]
# c13[C02 AC1 research-only + D15] c14[C02 AC1 D11 resume] c15[C02 AC1 C01
# tool names] c16[C03 AC1 body+command deltas] c17[C02 AC4 byte-unchanged;
# cf-52 RE-PIN drops kickoff/role-coord from the frozen set; cf-75 C02 RE-PIN
# drops gates — content now guarded by tests/pipeline-gates/validation-fix.sh]
# c19[cf-85 AC2/AC3/AC4/AC6/AC7/AC10 — the single `slug` field carrying
# `[<slug>](<session link>)`]; cf-90 joins as c20[C02 naming round: global
# run-tag retirement + mint-shape negatives + slug auto-accept] c21[C03
# Provider filtering — final-approval pickup split + ask-on-every-flavor]
# c22[C03 follow-up-card protocol + friction destination flipped to Inbox].
#
# cf-90 posture (2026-10-31): c20-c22 are DESIGNED RED until their chunks
# land — C02 owns c20's wording flips (its Tests list names THIS suite's
# c12/c16), C03 owns c21/c22. c12/c16 gained the flipped arms + HOLD
# negatives with them; everything else is a HOLD regression as before.
# The pre-existing reds of sibling suites (gate t17 etc.) are listed in
# gate.sh's header — nothing here invokes those suites.
#
# Red before C02/C03 (the ported skill is still the old two-list pickup and
# live-question intake); c1-c5, c7, c9, c17 are already green and hold as
# regressions. cf-52 posture: this suite is a pure regression gate on the
# coord-inwork ticket — all of c1..c17 are green before C01 and must HOLD
# after it; the new contract is asserted by tests/coord-inwork/surface.sh.
# cf-83 posture: C01 re-pins two needles of this gate — c11's Flash+Local
# routing-clause window, and c8 admits this ticket's plan folder (D6
# landing-widening). The routing needles rode the model of their era and are
# re-pinned again by 2026-11-feat-radiance-multi-instance: c11's windows now
# demand the radiance family (owner rulings 2026-11-22 D16/D20 — the cf-83
# strata route is retired doctrine, single-authoritied in
# tests/pipeline-models/surface.sh; the new contract's full text lives there).
# Every other arm stays green and holds.
# cf-85 posture (2026-10-29): c19 is the DESIGNED RED — it pins the one-field
# write-back the flip introduces, so it is red against the pre-flip sources
# and green at the flip commit (tests + sources + mirrors in one commit,
# DECISIONS D5). c8 admits the cf-85 plan folder; every other arm is a HOLD —
# c12's presence set, c14's resume rule, c15's tool names and c16's
# body/command deltas all stay satisfiable under the new wording (slug,
# session and custom field all still occur; the reworded command sentence
# still names both substrings).
# cf-86 posture: c8-only widenings. This round-1 posture line (C05 era) admitted
# the ticket's plan folder only; the C06 test round added the rest of its
# declared surface — the serving trio (chart values, strata profile ConfigMap
# template, gpu-ai overlay) plus charts/llama-swap/tests/**, none of which the
# contract-built admit list covered, so c8 reddened on any dirty serving tree
# mid-chunk and over the whole-ticket range (CHUNK_BASE=merge-base). The docs
# round added the runbook note and the parent README as exact files (both docs'
# doctrine is pinned by test_strata_runbook.py). See the c8 block for why the
# admits stayed literal rather than manifest-driven.
#
# CHUNK_BASE=<ref> narrows the scope checks to "since that commit"; default
# HEAD = uncommitted working tree. PORT_REF is retained only for c1's
# provenance comment — cf-58 retired c2's port byte-walk (the sanctioned
# delta grew; the absolute coord-family guards in agent-perms A12 +
# coord-inwork i4 + gate t17 are the frontmatter contract now).
#
# Usage:
#   bash tests/agent-board-coord/rulesync-surface.sh            # c1..c25
#   bash tests/agent-board-coord/rulesync-surface.sh c1 c4 c10 # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
PORT_REF="${PORT_REF:-916044893}"
FEATURE=".agents/plans/2026/2026-10-feat-board-coord-intake"
# This file is reused as a regression gate by the later cf-50 gate ticket,
# which shares the branch; its scope list must admit that ticket's plan
# folder and in-scope surface (the union-of-chunks convention above), or the
# cf-50 folder's mere existence reads as a scope violation. Content checks
# are untouched.
FEATURE2=".agents/plans/2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords"
# Same union convention: the WeKan v12.64 upgrade ticket ran on this branch
# (runbook + checked-in rule import JSON), so its folder is admitted too.
FEATURE3=".agents/plans/2026/2026-10-dep-wekan-v12-upgrade"
# Same union-of-tickets scope posture for cf-52, which shares the branch and
# legitimately re-opens the kickoff/role-coord pair plus the coord agents.
FEATURE4=".agents/plans/2026/2026-10-cf-52-feat-coord-session-inwork"
# cf-58 joins the union-of-tickets scope posture (its agent-surface widening
# is documented at the c8 case list).
FEATURE5=".agents/plans/2026/2026-10-cf-58-feat-standalone-agent-merge"
# cf-75 (2026-10-cf-75-bug-wekan-mcp-skill) joins the same posture: its plan
# folder plus the surfaces its chunks declare (the new skills/wekan-mcp skill,
# the wekan-api pointer edit, and the hand-managed board-context plugin dir)
# are admitted at c8 — agent-test's prerogative per the plan's scope caveat,
# never dev's.
RULES_SRC=".rulesync/rules/overview.md"

SKILL_SRC=".rulesync/skills/boards/SKILL.md"
AGENT_SRC=".rulesync/subagents/agent-board-coord.md"
CMD_SRC=".rulesync/commands/pipeline-boards.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
SKILL_GEN=".opencode/skills/boards/SKILL.md"
AGENT_GEN=".opencode/agents/agent-board-coord.md"
CMD_GEN=".opencode/commands/pipeline-boards.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/rulesync-surface-test.XXXXXX) || { echo "fail: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 26); do WANT["c$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^c([1-9]|1[0-9]|2[0-6])$ ]] || fail "unknown check id '$a' (expected c1..c26)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Shared assertion helpers for the content checks (each small, single-purpose).
cat >"$TMP/neg12.py" <<'PY'
# D12 dropped the `models` custom field, so a surface must never present a
# `models` custom field as existing. A line pairing "models" with "custom
# field" fails — unless the same line negates it: "no `models` custom field
# exists" is D12's own clarification quoted verbatim in the plan's C03 task
# text, and forbidding it would punish dev for recording the decision. The
# negation word is the difference between denial and announcement. (Roster
# count is not this guard's business: cf-85 shrank the roster to one field,
# the models negation survives either way.)
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

cat >"$TMP/order.py" <<'PY'
# Pickup order is a business rule (Rework first, then Not Started, then the
# new Low Priority list), so first-occurrence offsets inside the named
# section are the check — a reworded passage still passes, a reordered one
# cannot.
import re, sys
path, title = sys.argv[1], sys.argv[2]
needles = sys.argv[3:]
text = open(path).read()
m = re.search(r'(?ms)^#+[^\n]*' + re.escape(title) + r'[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print(f'section "{title}" not found'); sys.exit(1)
body = m.group(1)
pos = []
for n in needles:
    i = body.find(n)
    if i < 0:
        print(f'needle "{n}" not in section "{title}"'); sys.exit(1)
    pos.append(i)
if pos != sorted(pos):
    print(f'order violated: {list(zip(needles, pos))}'); sys.exit(1)
PY

cat >"$TMP/window.py" <<'PY'
# Co-location within a bounded span: the needles must read as one passage
# (a checklist definition, a label rule), not as scattered file-wide hits.
# --ci (case-folded prose needles, the gate.sh/coord-inwork win.py convention
# this suite's helpers already follow) was accepted at call sites but not
# parsed here — the first-arg int() crashed the arm before the needle check,
# so every --ci window was unsatisfiable regardless of content
# (validation_at_fault round 4). Non---ci callers keep byte-exact semantics.
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path).read()
if ci:
    text = text.lower()
    needles = [n.lower() for n in needles]
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

cat >"$TMP/desc.py" <<'PY'
# Frontmatter description value, not the file bytes: rulesync re-serializes a
# changed description as a folded block scalar, so a byte grep of a description
# phrase depends on where the 80-column wrap lands and breaks whenever the
# description changes length (cf-85 surface map 1a edits it). Exit 0 = needle
# present in the parsed value.
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    print("no parsable frontmatter"); sys.exit(2)
desc = " ".join(((yaml.safe_load(m.group(1)) or {}).get("description") or "").split())
needle = " ".join(sys.argv[2].split())
if needle not in desc:
    print(f"'{needle}' not in the description value"); sys.exit(1)
PY

# --- c1: all eight source + generated files exist ----------------------------
if want c1; then
  for f in "$SKILL_SRC" "$AGENT_SRC" "$CMD_SRC" "$PERM_SRC" "$SKILL_GEN" "$AGENT_GEN" "$CMD_GEN" "$PERM_GEN"; do
    [ -f "$f" ] || fail "c1: $f is missing"
  done
  ok "c1: the four sources and four generated counterparts all exist (ported at $PORT_REF)"
fi

# --- c2: the generated agent — frontmatter contract (C03 AC3, D21) ------------
if want c2; then
  python3 - "$AGENT_GEN" <<'EOF' || fail "c2: generated agent-board-coord frontmatter violates the contract"
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1))
perms = fm.get("permissions") or []
errs = []
if fm.get("name") != "agent-board-coord":
    errs.append(f"name is {fm.get('name')!r}, want agent-board-coord")
if fm.get("mode") != "primary":
    errs.append(f"mode is {fm.get('mode')!r}, want primary")
color = fm.get("color")
if not color:
    errs.append("no color set")
elif color == "#06b6d4":
    errs.append("color is agent-coord's #06b6d4 — the variant needs a distinct color")
desc = str(fm.get("description") or "")
if "STATE.json, DECISIONS.md and FRICTION.md" not in desc:
    errs.append("description lost the 'writes only STATE.json, DECISIONS.md and FRICTION.md' clause")
if "board" not in desc.lower():
    errs.append("description is not reworded for the board-driven variant")
def has(a, r, e):
    return any(p.get("action") == a and p.get("resource") == r and p.get("effect") == e for p in perms)
if not has("question", "*", "allow"):
    errs.append("explicit question allow missing (repo hard rule)")
if not has("dev-boards*", "*", "allow"):
    errs.append("dev-boards* allow missing (the variant's single MCP permission — server-name spelling: MCP tool ids keep the hyphen, re-pinned 2026-10-27 by 2026-10-bug-board-coord-dev-boards-allow)")
# cf-76 C07 era-gate: the four pipeline_* allow rows engage on the generated
# mirror as soon as the boards skill teaches the call surface (the skill
# text lands with the same chunk; before it the grant is unshipped and this
# check must not hold earlier chunks' runs hostage — the A13/-pr pattern).
try:
    skill_text = open(".rulesync/skills/boards/SKILL.md").read()
except OSError:
    skill_text = ""
if "pipeline_claim" in skill_text:
    for tool in ("pipeline_claim", "pipeline_release", "pipeline_heartbeat", "pipeline_status"):
        if not has(tool, "*", "allow"):
            errs.append(f"{tool} allow missing (cf-76 C07: the boards skill already names the lock surface — the grant must follow)")
# D21 adjudication: the re-cut onto main brought a fleet-wide `dev*`
# convention, but board-coord consumes card intake/exit only — least privilege
# survives, so the broad action must stay ABSENT, not merely be accompanied.
if any(p.get("action") == "dev*" for p in perms):
    errs.append("broad dev* allow present — D21 rules board-coord keeps ONLY narrow dev-boards*")
subs = sorted(p.get("resource") for p in perms if p.get("action") == "subagent" and p.get("effect") == "allow")
# cf-58 C03 re-pin: the roster names the VARIANT dev slot — the alias
# board-coord is -local semantics, so its dev slot is agent-dev-local, and
# the set is asserted EXACT (a retired bare slot would re-launch the
# pre-split agent).
# cf-90 C06 era-gate (agent-test): once the pipeline-role-deploy skill pair
# exists, the coord family's roster has widened with its class's launch
# (the alias carries plain agent-dev-deploy; tests/agent-dev-deploy t6
# enforces the per-class rule across all twelve family files). Before C06
# lands, the skill is absent and the 5-role set stays the contract — the
# same era-gating discipline as the pipeline_* arms above, so waves 1-2
# keep a green HOLD and a C06 that ships the hook WITHOUT the roster reddens here.
import os
want_subs = ["agent-plan", "agent-test", "agent-dev-local", "agent-review", "agent-research"]
if os.path.exists(".rulesync/skills/pipeline-role-deploy/SKILL.md"):
    want_subs = sorted(want_subs + ["agent-dev-deploy"])
else:
    want_subs = sorted(want_subs)
if os.path.exists(".rulesync/subagents/agent-explore.md"):
    want_subs = sorted(want_subs + ["agent-explore"])
# cf-106 C04 era-gate: the code-family second implementer. The alias carries
# -local semantics, so its slot is the commit-only `code` (the -pr twin is
# code-pr, pinned on that family by tests/agent-perms A12). Era-gated on the
# SOURCE row so the mirror arm reddens exactly when a landing forgets to
# regenerate — before C04 the wave stays green.
src_txt = ""
try:
    src_txt = open(".rulesync/subagents/agent-board-coord.md").read()
except OSError:
    pass
if re.search(r"resource: code\b", src_txt) or os.path.exists(".rulesync/subagents/code-pr.md"):
    want_subs = sorted(want_subs + ["code"])
if subs != want_subs:
    errs.append(f"subagent allows {subs}, want exactly {want_subs}")
edits = [p.get("resource") for p in perms if p.get("action") == "edit"]
want_edits = sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"])
if sorted(edits) != want_edits:
    errs.append(f"edit allows are {edits}, want ONLY the three plan-state files")
if errs:
    print("; ".join(errs))
    sys.exit(1)
# last-match-wins: the allow must sit after the leading deny-all
idx = {i: p for i, p in enumerate(perms)}
deny_all = [i for i, p in idx.items() if p.get("action") == "*" and p.get("resource") == "*" and p.get("effect") == "deny"]
boards_allow = [i for i, p in idx.items() if p.get("action") == "dev-boards*"]
if not deny_all or not boards_allow or boards_allow[0] < deny_all[0]:
    print("the dev-boards allow does not follow the leading deny-all (last-match-wins would deny it)")
    sys.exit(1)
EOF
  ok "c2: generated agent frontmatter (name, distinct color, question + dev-boards* allows, NO broad dev* (D21), the era-gated subagent roster — eight with cf-106 C04's code slot, three edit allows only)"

  # cf-58 C02/C03 re-pin: the PORT_REF frozen-permission-walk (the second
  # arm of this check) is RETIRED — the sanctioned delta grew from "the two
  # scoped shell allows" to the full cf-58 git block, and the absolute
  # family contract (API containment, git-only rows, variant rosters,
  # shapes) now guards this surface strictly in agent-perms A12 +
  # coord-inwork i4 + gate t17, which are stronger than "port + two shell
  # allows". What stays is the position pin — cf-126 C02 / Ruling OQ6
  # (validation_at_fault via coord, DECISIONS D24 route) grew the scoped
  # session-API family to FOUR rows: get→patch→post→post, the two creation
  # rows landing beside get/patch as the sanctioned C03 handoff transport.
  # The pin is the same law — only these session allows, in order, directly
  # after the single opencode '*' anchor — applied to the grown family; the
  # shipped checker also runs against the fabricated mutants (a dropped
  # creation post row, a reordered pair) so the equality is proven non-
  # vacuous, mirroring agent-perms family.py's re-pinned api mode.
  cat >"$TMP/c2api.py" <<'PY'
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode") if isinstance(fm.get("opencode"), dict) else {}
perms = outer.get("permissions") or fm.get("permissions") or []
API = [{"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"},
       {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"},
       {"action": "shell", "resource": "opencode api post /api/session*", "effect": "allow"},
       {"action": "shell", "resource": "opencode api post /api/session/*", "effect": "allow"}]
api_rows = [p for p in perms if p.get("action") == "shell" and str(p.get("resource", "")).startswith("opencode api")]
if api_rows != API:
    print(f"opencode-api rows {api_rows}, want exactly the four-row scoped session family get->patch->post->post in order (containment: the OQ6 lift sanctions the /api/session CREATION rows, nothing beyond the family)")
    sys.exit(1)
anchors = [i for i, p in enumerate(perms) if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
if len(anchors) != 1:
    print(f"want exactly one opencode '*' allow anchor, found {len(anchors)}")
    sys.exit(1)
if perms[anchors[0] + 1:anchors[0] + 5] != API:
    print("the four-row api family does not sit directly after the opencode '*' allow (the pinned splice position — the in-work-mark machinery keeps its anchor whatever the block grows around it)")
    sys.exit(1)
print("ok")
PY
  python3 "$TMP/c2api.py" "$AGENT_GEN" \
    || fail "c2: generated agent-board-coord mirror violates the four-row session-API family at the pinned position (the cf-126 C02 shape; reason above)"
  # Fabricated-drift controls: dropping a creation post row and reordering
  # the head of the family must each redden the SAME shipped checker.
  python3 - "$AGENT_GEN" "$TMP/c2-drop.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(src).read(), re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode") if isinstance(fm.get("opencode"), dict) else {}
target = outer if outer.get("permissions") else fm
rows = list(target.get("permissions") or [])
k = next(i for i, r in enumerate(rows) if r.get("resource") == "opencode api post /api/session*")
del rows[k]
target["permissions"] = rows
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  if python3 "$TMP/c2api.py" "$TMP/c2-drop.md" >/dev/null 2>&1; then
    fail "c2 control: dropping one creation-post row passed the family pin — the four-row containment is vacuous"
  fi
  python3 - "$AGENT_GEN" "$TMP/c2-order.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(src).read(), re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode") if isinstance(fm.get("opencode"), dict) else {}
target = outer if outer.get("permissions") else fm
rows = list(target.get("permissions") or [])
ig = next(i for i, r in enumerate(rows) if r.get("resource") == "opencode api get /api/session*")
ip = next(i for i, r in enumerate(rows) if r.get("resource") == "opencode api patch /api/session/*")
rows[ig], rows[ip] = rows[ip], rows[ig]
target["permissions"] = rows
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  if python3 "$TMP/c2api.py" "$TMP/c2-order.md" >/dev/null 2>&1; then
    fail "c2 control: the reordered get/patch mutant passed — the family ORDER (last-match-wins splice) is not enforced"
  fi
  ok "c2: generated agent frontmatter — shape/name/color/desc/dev-boards/roster-slot pins plus the four-row session-API family (get→patch→post→post) at the pinned splice position (cf-126 C02/OQ6 re-pin; drop and reorder mutants redden; the port byte-walk stays retired to the absolute family guards)"
fi

# --- c3: the generated agent — body keeps the skeleton ------------------------
if want c3; then
  grep -qE '^[[:space:]]*/pipeline-conventions[[:space:]]*$' "$AGENT_GEN" \
    || fail "c3: the agent body lost its pipeline-conventions MUST-load entry (skeleton not kept)"
  grep -qE '^[[:space:]]*/boards[[:space:]]*$' "$AGENT_GEN" \
    || fail "c3: the agent body MUST-load list does not include /boards"
  grep -q '^## Boards' "$AGENT_GEN" \
    || fail "c3: the agent body has no '## Boards' section (board-driven intake + protocol)"
  ok "c3: agent body keeps the skeleton and adds /boards + the Boards section"
fi

# --- c4: the generated skill — five sections + the board facts (C02 AC2) ------
if want c4; then
  for title in 'Board facts' 'Card pickup' 'Card lifecycle' 'Batched question protocol' 'Launch prompt to agent-plan'; do
    grep -qiE "^#{1,6}[[:space:]].*${title}" "$SKILL_GEN" \
      || fail "c4: the boards skill is missing its '${title}' section"
  done
  for fact in 'wekan.spencerslab.com' 'AI-Dev' 'In Process' 'Not Started' 'Executing' '**Review**' 'Rework' 'Finished' 'dev-boards' 'wekan-api'; do
    grep -qF "$fact" "$SKILL_GEN" || fail "c4: the boards skill never names '$fact' (the board facts are incomplete)"
  done
  grep -qi 'human' "$SKILL_GEN" || fail "c4: the boards skill never assigns Finished to a human (the agent must never self-move to Finished)"
  grep -qF 'open_questions' "$SKILL_GEN" \
    || fail "c4: the boards skill does not name the RESULT open_questions channel for the batched round"
  ok "c4: generated skill has all five sections, the board facts, and the launch-prompt contract"
fi

# --- c5: the generated command -------------------------------------------------
if want c5; then
  grep -q '^agent: agent-board-coord$' "$CMD_GEN" \
    || fail "c5: the /pipeline-boards command does not target agent-board-coord"
  grep -q 'ARGUMENTS' "$CMD_GEN" || fail "c5: the /pipeline-boards command does not read \$ARGUMENTS (card id)"
  grep -qi 'AI-Dev board card' "$CMD_GEN" || fail "c5: the command description does not say it runs a WeKan AI-Dev board card"
  # C03 rewords the intake sentence but must keep the resume machinery.
  grep -q 'STATE.json' "$CMD_GEN" || fail "c5: the command lost its STATE snapshot line"
  grep -q 'approved' "$CMD_GEN" || fail "c5: the command lost the approved-plan resume logic"
  ok "c5: /pipeline-boards targets agent-board-coord, takes an optional card id, keeps the STATE snapshot + resume logic"
fi

# --- c6: permissions matrix — board-coord row (lands with C04) -----------------
if want c6; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    grep -qE '^\|[[:space:]]*board-coord[[:space:]]*\|' "$f" \
      || fail "c6: $f has no board-coord row in the role matrix (C04 restores it — excluded from C02/C03 review runs)"
    grep -q 'dev-boards' "$f" || fail "c6: $f does not explain the dev-boards allow"
    grep -qE '^\|[[:space:]]*coord[[:space:]]*\|' "$f" \
      || fail "c6: $f lost the coord row (the matrix must stay, not be replaced)"
  done
  ok "c6: permissions matrix carries the board-coord row (source + generated) and keeps the coord row"
fi

# --- c7: rulesync generate twice — the second run is a no-op (C02 AC3) --------
# rulesync runs ask-gated in unattended subagent shells (its own edit surface
# is machinery), so an unresolvable binary skips with a warning like t14 of
# tests/services/dev-mcp-fleet.sh; the first run may materialize pending
# generation, so the gate is that the SECOND run changes nothing.
if want c7; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "c7: rulesync is not resolvable here (PATH or npx cache); the regeneration gate was not run — re-run where it is available"
  else
    $RS generate >"$TMP/rs1.log" 2>&1 || { tail -n 20 "$TMP/rs1.log" >&2; fail "c7: first rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    $RS generate >"$TMP/rs2.log" 2>&1 || { tail -n 20 "$TMP/rs2.log" >&2; fail "c7: second rulesync generate failed"; }
    snap_after=$(git status --porcelain)
    if [ "$snap_before" != "$snap_after" ]; then
      printf '%s\n' "--- after first run
$snap_before
--- after second run
$snap_after" >"$TMP/noop.diff"
      fail "c7: the second rulesync generate is not a no-op (sources and generated surfaces have drifted; see $TMP/noop.diff)"
    fi
    ok "c7: the second rulesync generate is a no-op (sources + generated in sync, via $RS)"
  fi
fi

# --- c8: scope — changed paths limited to this ticket's in-scope files ---------
# The union of C01-C04's file lists (the old ticket's eight-file scope cannot
# hold when four chunks share this branch); anything outside it — notably the
# pipeline-models/pipeline-gates sources — is a contract violation (C02 AC4,
# D1). cf-52 widens the set: its coord-pair grants, the kickoff/role-coord
# contract pair, tests/coord-inwork/* (tests/* already admits them) and its
# plan folder (D10 — the pins move with the contract, not against it).
# tests-edit-perms D4/D9 widening: that ticket's agent-test/agent-dev pairs,
# the pipeline-overview pair (its permissions.md pair is PERM_SRC/PERM_GEN,
# already admitted), the pipeline-role-test pair, its tests/agent-perms/*
# suite (tests/* admits it) and the three follow-up ticket folders that the
# cf-52 landing 124fc2ae8 introduced — a landing that adds plan folders must
# not read as a scope violation here at any later base. The three folder
# patterns are inline literals so agent-perms A9 window-greps them here.
# cf-75 final-review widening: the OQ2-approved draft retirement is a coord
# bookkeeping write into the SUPERSEDED sibling folder
# 2026-10-docs-wekan-mcp-arg-ergonomics (STATE.json, commit dca8a25d2) — the
# same sanctioned-plan-folder class as the enumerations above, admitted whole
# so no further retirement note reddens the full-range scope shape.
# cf-83 C01 widening (D6, same landing-widening precedent): the strata
# re-route ticket's plan folder must read as admitted before its bookkeeping
# commits, else the full board-coord suite treats the mere untracked folder
# as scope escape. Its skill-source/mirror and tests edits are already
# admitted by the .rulesync/skills/*, .opencode/skills/* and tests/* lines;
# the folder pattern is an inline literal so scope-block window greps (the
# A9 convention) still match this admission here.
# cf-85 (2026-10-29): same own-folder admit; its surface edits ride the
# .rulesync/skills/*, .rulesync/subagents/*, .opencode/agents/*,
# .rulesync/commands/*, .opencode/commands/*, .rulesync/rules, tests/* and
# AGENTS.md admits already in this set.
# board-tick-cleanup widening (2026-10-29): the hand-managed question-notify
# reader edit + the loop-file truth fix + this ticket's own plan folder
# (agent-perms A9 window-pin), all in-scope per its chunks/C02.md.
# merge round (2026-10-30): cf-68 joins the admit beside cf-83 — merged ticket
# folders ride the changed-paths walk; guards red on landed folders bury later checks.
# merge2 round (2026-10-31): cf-88 lands a ROOT plan doc, not a folder — admitted
# whole like the folders; question-notify stays admitted for CHUNK_BASE runs.
# cf-86 widening (2026-10-30, same D6 precedent): the more-strata-models
# ticket's plan folder joins the admit list — its bookkeeping commits (STATE
# handoffs, approved chunk files) land on this branch like every ticket since
# cf-58, and any untracked/dirty plan-folder state reddened c8 before then.
# Inline literal per the A9 window-grep convention (agent-perms A9's pinned
# slug loop does NOT demand this slug: cf-86 lands no t14/c7 block admits).
# cf-86 serving-surface widening (2026-10-30 C06 test round, same prerogative
# as every widening above): the admit list was assembled from CONTRACT tickets,
# so it carried no serving surface at all — a model ticket's own chart/services
# edits reddened c8 on any dirty tree mid-chunk, and its chart test tree
# reddened over a range base (CHUNK_BASE=merge-base). Admits are the exact
# files cf-86's chunks declare (chart values, the strata profile ConfigMap
# template, the gpu-ai overlay) plus that chart's tests tree — deliberately NOT
# charts/** or services/**, so a stray serving edit still goes red, and the
# probe loop below keeps that true without a human remembering to check.
# Manifest-driven admits (reading each chunk's "Files in scope") were rejected:
# the plan folder is itself admitted and rewritten mid-run, so dev would grow
# its own allow-list — a scope guard that trusts the scoped party is not a
# guard — and agent-perms A9 window-greps literal admits inside the if-want
# block, which a parsed loop cannot satisfy (it would need re-pinning too).
# cf-90 widening (2026-10-31, agent-test): the running ticket's plan folder +
# the hand-written skills/wekan-board-provision dir (C01; skills/* stays
# enumerated per contract, exactly as wekan-mcp was admitted). Loop and test
# edits ride the .agents/loops/*, tests/*, .rulesync/skills/*, .opencode/* and
# AGENTS.md admits already in this set.
# cf-106 widening (2026-11-03, agent-test; chunks/C01.md "Scope admits"): the
# running ticket's own plan folder, admitted ONCE for all eleven chunks (plan
# DECISIONS 2026-11-03, the cf-96 "admits cost a line in FOUR arms" friction
# paid once). Its declared surfaces already ride this set: .rulesync/* +
# .opencode/{agents,commands,skills}/* + AGENTS.md (skills/subagents/commands/
# rules), scripts/* (C03a's session-noop-audit.sh), tests/* (tests/cf106-noop/**
# and every re-pin), containers/wekan-mcp/*, skills/{wekan-mcp,wekan-board-
# provision}/*, .opencode/plugin/*, .opencode/opencode.jsonc and .agents/loops/*.
# Any file a replan adds joins THIS line — same rule as the cf-86 exact-file
# precedent, and the probe loop below keeps the widening from becoming a
# catch-all.
# cf-123 (2026-11-07, agent-test): this ticket's own plan folder joins on the
# same once-per-ticket rule (cf-106 precedent row) — its declared surfaces
# already ride this set: tests/*, .opencode/plugin/board-context/*,
# containers/wekan-mcp/*, skills/wekan-mcp/*, .agents/loops/* and .rulesync/*
# + .opencode/{commands,skills}/*. Harness state, not repo drift (plan
# DECISIONS baseline note).
# cf-143 (2026-11-12, agent-test round, chunks/C01..C07 files-in-scope): the
# radiance serving ticket — own plan folder on the D9 rule plus its declared
# serving surfaces, exact style per the cf-86 precedent: the two new chart
# trees (charts/radiance/*, charts/amd-gpu/*), the vllm ERAS TEST TREE only
# (charts/vllm/tests/* — C01's era re-pins; charts/vllm/** stays out, the
# byte-untouched-disabled guarantee keeps teeth), the three render-test
# workflow files, the three exact notes docs. The rest rides existing admits
# (.rulesync/skills/* covers pipeline-models, .opencode/opencode.jsonc, the
# llama-swap values/tests pair, the gpu-ai overlay, tests/*). Same-line
# widening on replan (cf-106 rule).
# cf-55 widening (2026-11-16, agent-test re-anchor round; DECISIONS
# D31/D32): the rebuilt ticket's own plan folder joins on the same
# once-per-ticket rule, plus the CHART-HALF surfaces its chunks declare that
# no wildcard here covers — .forgejo/workflows/build-charts.yaml and its DELETED
# GitHub twin (cutover; admitted in the composed ".github/"-quote form
# because this branch's forgejo-ci-surface.sh sweeps live surfaces for the
# plain deleted path), custom-values/infra/prod-values.yaml (C04's
# [packages] enablement — the first enumerated serving-custom-values
# exception in this arm; the gate keeps the CLASS outside the allow-set and
# a chunk declaration is the sanctioned exception), and the prose/comment
# truth files skills/helm-chart-creation/* and containers/renovate-mcp/Dockerfile
# (the wekan-mcp pyproject comment rides the existing containers/wekan-mcp/*
# wildcard). Sibling files of those dirs stay
# OUT (probe below). The container-build half is cf-6's — no docker-build or
# vllm-radiance admits, this branch touches neither. The strata re-point
# rides charts/llama-swap/tests/*, cf-55 suites ride tests/*, sources +
# mirrors + AGENTS.md ride existing lines. A replan-added file joins THIS
# line, not a new arm.
# cf-126 C06 round-3 (D37 route b′): .openchamber/project.json + its canonical
# fixture join the admit union — the same per-ruling artifact trail as the
# cf-124/cf-55/cf-126 folder admits above (fixture rides tests/* but is listed
# explicitly; both admits are exact paths, so ANY other file under .openchamber/
# or a sibling in tests/openchamber-project/ stays refused by *) return 1).
# cf-55 FIX ROUND (2026-11-21 fix-wave test round; DECISIONS D41/D42,
# chunks/C05-C07): charts/forgejo-runner/* (the C06 label re-point) and
# containers/forgejo-runner/* (the C05 baked act job image) join as
# directory admits — the cf-143 new-chart-trees precedent. The admits stay
# tree-exact: the act-base sibling image and the Forgejo-instance chart
# beside them join the probe list below.
# cf-55 ROUND 4 / C09 (2026-11-25, D50.4/D51-Q3 fold; chunks/C09.md): the
# three regenerated drift-trio Chart.locks (base, traefik, traefik-zerotrust)
# and the two traefik values files of the D51-Q1 additionalProperties fold
# join as EXACT per-file admits — no charts/* or charts/*/Chart.lock
# wildcard: sibling charts (charts/loki/Chart.lock, charts/vllm/values.yaml)
# and the unconverted charts' values files stay outside the arm and join the
# probe discipline below.
# cf-55 ROUND 4 / C11 (2026-11-25, owner Q3 "rename, LANDS LAST";
# chunks/C11.md): the git mv renames the admitted builder path — the old
# .forgejo/workflows/release.yaml became build-charts.yaml (since renamed;
# the composed ".github/" twin entry stays forever, the deleted GitHub twin
# keeps its historical name). Two new per-file joins for the rename's own
# edits joining per-file: charts/prowlarr/Chart.yaml (its shipped comment
# re-truth; touching charts/** makes the rename merge the designed first
# fire under heal + calendar, plan Round-4 landing #4). The anchor cite
# re-pin of .forgejo/workflows/main-sync.yaml (:54 -> the verified :57 after
# C09's header shift) rides the agents-md/gate arms; the test-wave fold (same
# commit set) has moved the c8 probe entry into the admit list, so this arm
# admits main-sync.yaml too. The
# renamed suite, surface.sh and the strata pins ride the existing tests/*
# and charts/llama-swap/tests/* wildcards.
# A replan-added file joins THIS line.
# cf-55 ROUND 4 / C12 (2026-11-25, route F approved by D49; chunks/C12.md):
# .forgejo/workflows/renovate.yaml joins as an EXACT path — dev 93cb79107
# (r2 APPROVED) is the first cf-55-round edit of that file: the -full image
# behind the helm4-writes/helm3-builds digest cross-check gate plus the
# declared RENOVATE_BINARY_SOURCE pair. Exact-only: the cf-6 workflows
# beside it stay outside the arm (main-sync — since joined by the C11 fold
# above, 2026-11-25; containers-build and builder-bootstrap stay outside).
# bug-board-preload-lean-consumer (2026-11-21, agent-test, C01 Tests): this ticket's own plan folder
# joins on the once-per-ticket rule (cf-106 precedent row) — its six in-scope
# files already ride tests/*, .rulesync/skills/* and .opencode/skills/* here;
# the amendment is skill-side only (plan D8: no tool, plugin, collector or
# rules surface), so nothing else joins.
if want c8; then
# (round-5 entries ride the cf-55 lines inside c8_admits; provenance)
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
  c8_admits() {
    case "$1" in
      "$SKILL_SRC"|"$AGENT_SRC"|"$CMD_SRC"|"$PERM_SRC"|"$RULES_SRC"|\
      "$SKILL_GEN"|"$AGENT_GEN"|"$CMD_GEN"|"$PERM_GEN"|AGENTS.md|\
      containers/wekan-mcp/*|skills/wekan-api/*|tests/*|"$FEATURE"/*|\
      "$FEATURE2"/*|"$FEATURE3"/*|"$FEATURE4"/*|scripts/*|.rulesync/commands/pipeline-boards-hourly.md|\
      .opencode/commands/pipeline-boards-hourly.md|\
      .rulesync/subagents/agent-coord.md|.opencode/agents/agent-coord.md|\
      .rulesync/skills/pipeline-kickoff/SKILL.md|.opencode/skills/pipeline-kickoff/SKILL.md|\
      .rulesync/skills/pipeline-role-coord/SKILL.md|.opencode/skills/pipeline-role-coord/SKILL.md|\
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
      skills/wekan-mcp/*|skills/container-creation/*|.opencode/plugin/board-context/*|\
      .agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/*|\
      .agents/plans/2026/2026-10-docs-wekan-mcp-arg-ergonomics/*|\
      .agents/plans/2026/2026-10-cf-76-feat-parallel-pipeline-loops/*|\
      .agents/plans/2026/2026-10-cf-83-refactor-strata-flash/*|\
      .agents/plans/2026/2026-10-cf-86-feat-more-strata-models/*|\
      .agents/plans/2026/2026-10-cf-68-feat-wekan-mcp-create-list/*|\
      .agents/plans/2026/2026-10-cf-85-refactor-wekan-slug-session-link/*|\
      .agents/plans/2026/2026-10-cf-72-chore-coord-git-read-globs/*|\
      .agents/plans/2026/2026-10-chore-board-tick-cleanup/*|\
      .agents/plans/2026-10-30-chore-coord-surface-grants.md|\
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
      .opencode/plugin/pipeline-locks/*|.opencode/plugin/question-notify/*|.agents/loops/*|.gitignore|\
      .agents/plans/2026/2026-11-cf-106-feat-coord-fixes/*|\
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
      charts/prowlarr/Chart.yaml|\
      .forgejo/workflows/main-sync.yaml|\
      .forgejo/workflows/"containers-build".yaml|.forgejo/workflows/build-containers.yaml|renovate.json|\
      services/dev/prod/values.yaml|services/gpu/prod/values.yaml|\
      .agents/plans/2026-11-cf-123-bug-tweak-init/*|\
      .agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/*|\
      .agents/plans/2026/2026-11-cf-126-feat-compaction-pipeline-sessions/*|\
      .agents/plans/2026/2026-11-bug-board-preload-lean-consumer/*|\
      .openchamber/project.json|\
      tests/openchamber-project/default-summary-instructions.txt) return 0 ;;
      *) return 1 ;;
    esac
  }
  { git diff --name-only "$BASE" || true; git ls-files --others --exclude-standard; } | sort -u >"$TMP/changed.txt"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    c8_admits "$p" || fail "c8: path outside the ticket's in-scope files: $p (base: $BASE)"
  done <"$TMP/changed.txt"
  # Widening, not a catch-all: paths no ticket on this branch has ever declared
  # must stay outside the admit list. A probe path need not exist on disk — the
  # check is on the pattern set.
  # cf-86 docs round (2026-10-30): the runbook NOTE and the parent README join
  # the admits as exact files — test_strata_runbook.py pins both docs'
  # doctrine, so a docs round that moves the doctrine must move them.
  # cf-86 C07 round (2026-10-31, owner U9.4): the image lift makes the strata
  # image a cf-86 serving surface after all — the admits are the four paths
  # chunks/C07.md declares (Dockerfile, README, files/, its test file), still
  # never containers/** or containers/strata/* as a whole; the earlier probe
  # entry (containers/strata/Dockerfile, "cf-86 builds no image") is retired
  # with that premise, and its teeth move to the sibling-image probes below.
  # cf-86 C09 round (2026-10-31, owner U11): one more exact build-context
  # file joins the admits — the vendored carry patch chunks/C09.md declares.
  # The carry/ DIRECTORY and any second patch file stay OUT (probe below):
  # a third hunk would mean re-research, not a new file, and the scope guard
  # keeps that expensive.
  # .agents/notes/* and charts/llama-swap/* as wholes are NOT admitted
  # (next loop proves the neighbours stay out).
  # cf-55 fix round (2026-11-21): the two new directory admits stay
  # tree-exact — the act-base sibling container and the Forgejo-instance
  # chart beside the runner chart join the probes below.
  # cf-55 ROUND 5 (2026-11-26, chunks/C16.md; D57): services/gpu/prod/
  # values.yaml RETIRES from this probe list — the owner's runner-scale
  # ruling makes it an admitted per-file surface (the replicas slice), the
  # same way services/dev/prod/values.yaml never carried a probe here.
  for p in containers/strata/.dockerignore containers/music-assistant/Dockerfile \
           containers/strata/carry/ornith-strata-fixups.patch containers/gemma/serve.Dockerfile \
           charts/llama-swap/templates/deployment.yaml \
           charts/home-assistant/values.yaml services/home/agents/prod/values.yaml \
           .github/workflows/ci.yaml .agents/notes/strata-remediation-plan.md \
           charts/vllm/values.yaml \
           charts/loki/Chart.lock \
           custom-values/gpu/prod-values.yaml \
           containers/renovate-mcp/README.md \
           containers/forgejo-host-runner/Dockerfile charts/forgejo/values.yaml; do
    if c8_admits "$p"; then
      fail "c8: the admit list admits $p — a serving widening grew into a catch-all (scope teeth lost)"
    fi
  done
  ok "c8: changed paths limited to the ticket's in-scope files incl. the tests-edit-perms D4/D9, cf-75 (skills/wekan-mcp, board-context plugin, own plan folder), cf-83 D6 (plan folder), cf-85 (own plan folder), cf-72 (own plan folder), the merge-round own-folder admits (cf-68, board-tick-cleanup, cf-88 surface-grants doc), cf-86 (plan folder + declared serving trio + its chart tests tree + its two pinned docs + its C07 image-build surfaces), cf-90 (plan folder + skills/wekan-board-provision admits), cf-96 (plan folder + C09 coder-template pair), the cf-106/cf-123 own-folder admits, the cf-143 radiance admits (plan folder, the two new chart trees, the vllm TEST tree only, three render workflows, three notes docs) and the cf-55 chart-half admits (own folder, Forgejo release builder + composed deleted GitHub twin, C04 infra values file, helm-chart-creation skill, renovate-mcp Dockerfile) + the cf-55 fix-round directory admits (charts/forgejo-runner, containers/forgejo-runner) + the cf-123 own-folder admit (bug-board-preload-lean-consumer) + the cf-55 round-4/C09 per-file admits (the three regenerated drift-trio Chart.locks + the two traefik values files, D51-Q1/Q3) + the cf-55 round-4/C12 admit (the renovate workflow's -full image+env pair behind the digest gate, D49, dev 93cb79107) — charts/vllm/values.yaml, the loki sibling lock, services/gpu, sibling custom-values, the act-base sibling container and the Forgejo-instance chart, and unadmitted container files stay probed OUT; undeclared serving paths still rejected (base: $BASE)"
fi

# --- c9: skill self-declaration + agent skeleton loads (C02 AC5, C03 AC4) -----
if want c9; then
  python3 "$TMP/desc.py" "$SKILL_GEN" 'MUST-loaded by agent-board-coord' \
    || fail "c9: the boards skill's frontmatter description no longer declares itself MUST-loaded by agent-board-coord (the value, not the bytes — a changed description re-wraps the mirror's folded scalar)"
  python3 "$TMP/desc.py" "$SKILL_SRC" 'MUST-loaded by agent-board-coord' \
    || fail "c9: the boards skill SOURCE lost its MUST-loaded declaration — the mirror regenerates from it, never the reverse"
  grep -qiE 'on demand[^.]*run start|never at run start' "$SKILL_GEN" \
    || fail "c9: the boards skill lost the 'wekan-api on demand, never at run start' note"
  grep -qE '^[[:space:]]*/pipeline-kickoff[[:space:]]*$' "$AGENT_GEN" \
    || fail "c9: the agent lost its /pipeline-kickoff MUST-load — the skill's override text retires the QUESTIONS for board runs, not the load list"
  grep -qE '^[[:space:]]*/pipeline-models[[:space:]]*$' "$AGENT_GEN" \
    || fail "c9: the agent lost its /pipeline-models MUST-load (the size mapping stays authoritative there)"
  ok "c9: skill declares its consumer + the on-demand note; agent still MUST-loads /pipeline-kickoff and /pipeline-models"
fi

# --- c10: pickup order gains Low Priority (C02 AC1) ----------------------------
if want c10; then
  grep -qF 'Low Priority' "$SKILL_GEN" \
    || fail "c10: the boards skill never mentions the new Low Priority list"
  python3 "$TMP/order.py" "$SKILL_GEN" 'Card pickup' 'Rework' 'Not Started' 'Low Priority' \
    || fail "c10: the Card pickup passage does not order pickup Rework -> Not Started -> Low Priority"
  ok "c10: pickup walks Rework -> Not Started -> Low Priority inside the Card pickup passage"
fi

# --- c11: the five standard checklists (C02 AC1, D9 drift detector; cf-58
#       C05 Lifecycle re-pin + C06 routing clauses) ---------------------------
# The Services item set regenerates from `ls services/` at run time (D9).
# cf-58 C05: the third checklist is LIFECYCLE (checked-stages-only,
# nothing-checked = the standard loop). cf-96 C07 RE-PIN: the intake eight-
# stage set became ELEVEN items — the ten stages in card order plus Single
# Session LAST (OQ6 ruling). cf-124 C01 RE-PIN: the generation is now THIRTEEN
# — `Session Rename` + `Worktree Creation` FIRST (genuine gates, D15) and
# `Follow-up cards created` + `Human in the Loop` last — with a NINE-stage
# nothing-checked default (Session Rename first, Final Review last, D16/OQ2;
# Deployment + Single Session stay the two-member OPT-IN sentence), and
# Services = derived folders ∪ a FIXED six (D22) with an exactness negative.
# C06: the Model(s) four-option line stays UNCHANGED while the routing
# paragraph carries the two combination clauses. The Model(s)/HITL pins hold
# exactly as before. Re-pin history: cf-83 moved Flash+Local q3 -> strata;
# 2026-11-feat-radiance-multi-instance (owner rulings 2026-11-22 D16/D20)
# moved both clauses to the radiance family — the routes move, the option
# set and Q6 veto guards stay byte-identical.
if want c11; then
  python3 "$TMP/window.py" "$SKILL_GEN" 2500 'Services' 'Type' 'Model(s)' 'Lifecycle' 'Human in the Loop' \
    || fail "c11[C05]: Services/Type/Model(s)/Lifecycle/Human in the Loop do not read as one checklist-definition passage (red before C05 — the Research checklist has not been replaced by Lifecycle)"
  for d in $(ls services/); do
    grep -qF "\`$d\`" "$SKILL_GEN" \
      || fail "c11: the Services checklist does not name the services/$d folder as a code span — drift detector (D9) failed"
  done
  for extra in 'home-assistant' 'agent context' 'HomeAssistant' 'Home-Assistant-Label-based-Features' \
               'brother-ptouch-automation' 'CuratedForest.com'; do
    grep -qF "\`$extra\`" "$SKILL_GEN" \
      || fail "c11[cf-124 C01]: the Services checklist does not name the fixed non-folder work target '$extra' as a code span — the extra set is the fixed six, folders ∪ six (red before C01 dev)"
  done
  # cf-124 C01: exactness, not "contains something" — every target-shaped code
  # span in the Services bullet must be a live folder or one of the fixed six,
  # and a fabricated seventh target must be rejected by the same check.
  python3 - "$SKILL_GEN" <<'PY' || fail "c11[cf-124 C01]: the Services bullet is not the exact folders ∪ fixed-six set (reason above)"
import os
import re
import sys
text = open(sys.argv[1]).read()
m = re.search(r"(?ms)^\s*-\s+\*\*Services\*\*(.*?)(?=^\s*-\s+\*\*Type\*\*)", text)
if not m:
    print("no Services bullet between the Services and Type checklist titles"); sys.exit(1)
bullet = m.group(1)
folders = sorted(os.listdir("services"))
allowed = set(folders) | {"home-assistant", "agent context", "HomeAssistant",
                          "Home-Assistant-Label-based-Features", "brother-ptouch-automation",
                          "CuratedForest.com"}
spans = re.findall(r"`([^`\n]+)`", bullet)


def unlisted(spans):
    # target-shaped = one bare path component (a folder or repo name);
    # descriptive spans (`services/`, `ls services/`, `Repo:`, `agent context`)
    # carry slashes, spaces or colons and are never work targets.
    return [s for s in spans
            if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", s) and s not in allowed]


def folders_listed(spans):
    # count distinct bare names matching the folder set — proof a fabricated
    # unlisted folder (which joins `allowed` live) would be caught by the
    # fabricated control below, not waved through.
    return sum(1 for s in spans
               if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", s) and s in folders)


bad = unlisted(spans)
if bad:
    print(f"unlisted target-shaped tokens in the Services bullet: {bad!r} — the set is exactly "
          f"the services/ folders ∪ the fixed six, nothing else (red before C01 dev)"); sys.exit(1)
# Exactness of the DERIVED half: the bullet must enumerate every live folder,
# not merely mention some. The folder loop above checks each against a live
# `ls services/`, so this leg proves a fabricated unlisted folder is caught.
listed = folders_listed(spans)
if listed < len(folders):
    print(f"the Services bullet enumerates {listed} of {len(folders)} live folders — the exactness "
          f"arm must bite on a non-enumerating bullet, or the fabricated-folder control is vacuous"); sys.exit(1)
# Defect control: a fabricated unlisted target must be rejected by this check.
if not unlisted(spans + ["totally-made-up-target"]):
    print("the fabricated unlisted target PASSED the exactness check — the negative is inert"); sys.exit(1)
print("ok")
PY
  grep -qE 'feat.*bug.*debug.*dep.*refactor.*chore.*docs' "$SKILL_GEN" \
    || fail "c11: the Type checklist does not list feat|bug|debug|dep|refactor|chore|docs in one passage"
  grep -qE 'Qwen Large.*Qwen Dense.*Qwen Flash.*Local' "$SKILL_GEN" \
    || fail "c11[cf-106 C02]: the Model(s) checklist does not list Qwen Large | Qwen Dense | Qwen Flash | Local — the four-option line keeps its shape with the renamed middle label (red until C02 renames and regenerates)"
n27="$(grep -c 'Qwen 27b' "$SKILL_GEN")"
if [ "$n27" -gt 1 ]; then
    fail "c11[cf-106 C02]: the generated boards mirror mentions 'Qwen 27b' $n27 times — only the alias sentence may carry the retired label (regenerate the mirror, never hand-edit it)"
fi
   # source↔mirror parity for the same claim (c11's posture: mirror work, but a
   # source that disagrees with its mirror is a rulesync lie)
   grep -qE 'Qwen Large.*Qwen Dense.*Qwen Flash.*Local' "$SKILL_SRC" \
     || fail "c11[cf-106 C02 AC1]: the boards SOURCE Model(s) line is not the four-label Dense set — the source and its generated mirror must carry the same vocabulary"
  grep -qE 'Qwen Large.*Flash Next' "$SKILL_GEN" && fail "c11[C06]: a single passage pairing 'Qwen Large' with 'Flash Next' — the Model(s) checklist gained a fifth option; Q6 vetoed it (combination of existing checks is the mechanism)"
  python3 "$TMP/window.py" "$SKILL_GEN" 1150 'Session Rename' 'Worktree Creation' 'Exploration' 'Agent Decides Research' 'Planning' 'Test Writing' 'Chunk Development' 'Chunk Review' 'Final Review' 'Deployment' 'Single Session' 'Follow-up cards created' 'Human in the Loop' \
    || fail "c11[cf-124 C01]: the Lifecycle checklist does not carry its thirteen items in one passage (cf-124 C01 list, card order, Session Rename FIRST, Human in the Loop LAST; red before C01's text + this re-pin)"
  python3 "$TMP/window.py" --ci "$SKILL_GEN" 900 'default' 'nothing is checked' 'session rename' 'worktree creation' 'exploration' 'agent decides research' 'final review' \
    || fail "c11[cf-124 C01]: no nothing-checked default passage naming the nine-stage blank default (Session Rename first, Final Review last — the cf-124 D16 default loop; red before C01's text + this re-pin)"
  python3 "$TMP/window.py" --ci "$SKILL_GEN" 400 'opt-in' 'Deployment' 'Single Session' \
    || fail "c11[cf-124 C01]: the two-member OPT-IN sentence (Deployment + Single Session, outside the default set) is missing or was rewritten"
  grep -qE 'Human in the Loop.*`Session Rename` \| `Worktree Creation` \| `Exploration` \| `Agent Decides Research` \| `Planning` \| `Test Writing` \| `Chunk Development` \| `Chunk Review` \| `Final Review` \| `Deployment` \| `Single Session` \| `Follow-up cards created` \| `Human in the Loop`' "$SKILL_GEN" \
    || fail "c11[cf-124 C01]: the Human in the Loop checklist does not mirror the thirteen Lifecycle names in one passage (the cf-124 13-name mirror, Session Rename first; red before C01 dev)"
  # cf-106 C02 AC2: the default selection is pinned on SOURCE and MIRROR alike —
  # the flip must be identical on both (a hand-edited or stale mirror fails here).
  for f in "$SKILL_SRC" "$SKILL_GEN"; do
    grep -qF 'Default selection: `Qwen Dense`' "$f" \
      || fail "c11[cf-106 C02 AC2]: $f does not state the Model(s) default selection as Qwen Dense — the checklist default flips with the vocabulary (OQ-7: BOTH defaults flip) and source+mirror must agree; red until C02 + regenerate"
  done
  grep -qF 'Default: `Final Review`' "$SKILL_GEN" \
    || fail "c11[C07]: the Human in the Loop checklist does not state its default item (Final Review - the C07 blank-HITL default)"
  # C06: the routing paragraph's two combination clauses (source of truth is
  # the boards skill; tests/pipeline-models runs the same pins on SOURCE).
  # 2026-11-feat-radiance-multi-instance re-pin (ruling chain cf-106 OQ-14
  # 2026-11-03 -> owner ruling 2026-11-09 strata-q4 -> owner ruling 2026-11-22
  # radiance D16/D20): the Strata era is documented in pipeline-models ONLY
  # (the single-authority law — tests/pipeline-models/surface.sh M5 bars any
  # strata token in the boards pair, so the pre-C02 'flash-next-strata' needle
  # here contradicted the suite it rode beside and could only be satisfied by
  # needle-hacking). C02 landed the move (dcf9526ea); both windows now pin the
  # shipped radiance routes.
  python3 "$TMP/window.py" --ci "$SKILL_GEN" 600 'flash' 'local' 'qwen3.8-flash-next-radiance' 'assume' \
    || fail "c11[C06, re-pinned 2026-11-22 radiance ruling]: the routing paragraph lacks the Flash+Local → qwen3.8-flash-next-radiance assume clause (the runner-literal chain cf-106 OQ-14 2026-11-03 -> 2026-11-09 strata-q4 -> 2026-11-22 radiance moved this needle; D16)"
  python3 "$TMP/window.py" --ci "$SKILL_GEN" 600 'local' 'qwen3.8-27b-radiance' 'unless' \
    || fail "c11[C06, re-pinned 2026-11-22]: the routing paragraph lacks the Qwen Dense+Local → qwen3.8-27b-radiance unless-another-quant clause — owner ruling D20 (2026-11-22) moved this row out of qwen3.8-27b-q4; the 10+/background leg lives in pipeline-models alone and must NOT leak into this window (the M7 law)"
  ok "c11: five checklist titles with full item sets — Services = regenerated ls services/ folders ∪ the fixed six exactly (unlisted tokens rejected); Lifecycle's thirteen items (cf-124 C01) + nine-stage nothing-checked default + the untouched two-member OPT-IN sentence; Model(s) four options with Qwen Dense as the default selection, source and mirror agreeing and the retired label surviving only as the alias; HITL items mirror the thirteen + Final Review default; combination clauses present on the 2026-11-22 radiance routes (D16/D20 re-pin)"
fi

# --- c12: slug/session custom fields, cf- slugs, session-origin URL, no run tag (C02 AC1, cf-50 r2 re-pin) --
# cf-85 keeps this arm a HOLD: it pins SUBSTRINGS, not the pair wording —
# after the flip `slug` names the one field and `session` the retired one, and
# c19 owns the combined-form and the retired-wording negatives.
if want c12; then
  for s in 'slug' 'session' 'custom field' 'cf-<card' 'session_rename'; do
    grep -qF "$s" "$SKILL_GEN" || fail "c12: the boards skill never states the intake fact '$s'"
  done
  grep -qF 'SESSION_URL_BASE' "$SKILL_GEN" \
    || fail "c12: the boards skill lost the config constant name"
  # cf-50 round 2 (D18/D25-r2): the intake-D20 literal is a proven dead host
  # (coderd answers it 400 — malformed app-host grammar), so PRESENCE is now
  # the defect: the old VERBATIM sub-pin flips to absence pins plus the
  # dynamic-resolution phrases the origin block ships.
  if grep -qF 'openchamber--dev-thehackmeister-coder' "$SKILL_GEN"; then
    fail "c12: the dead intake-D20 host literal is present in the boards skill — cf-50 D25 r2: absence is correctness, not drift"
  fi
  if grep -qF 'SESSION_URL_BASE = https://' "$SKILL_GEN"; then
    fail "c12: SESSION_URL_BASE is hard-coded again — the value must be THIS run's Session origin: line (cf-50 D18 r2)"
  fi
  grep -qF 'Session origin:' "$SKILL_GEN" \
    || fail "c12: the skill lost the dynamic SESSION_URL_BASE resolution source (the run's Session origin: line)"
  grep -qF 'VSCODE_PROXY_URI' "$SKILL_GEN" \
    || fail "c12: the skill lost the Coder app-origin env the command blocks derive from (cf-50 D19 r2)"
  grep -qF '?session=' "$SKILL_GEN" \
    || fail "c12: the session-link path format (OpenChamber router, research §10) is missing"
  grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag|omits/nulls' "$SKILL_GEN" \
    || fail "c12: the skill never retires the run tag for card-driven runs (D10/retirement rule)"
  # cf-90 C02 FLIP (2026-10-31): the card-driven-only posture is retired
  # globally — the boards retirement bullet now states BOTH-family scope and
  # cites pipeline-kickoff for the mechanics. Designed red before C02 dev;
  # the or-form accepts either global wording ('every flavor' or
  # 'both families' — the plan's two phrasings across the chunk table).
  if grep -qF 'keeps run tag' "$SKILL_GEN"; then
    fail "c12[C02 AC4]: the boards skill still says agent-coord KEEPS run tags — the retirement is global now (cf-90 C02), supersede this wording"
  fi
  if python3 "$TMP/window.py" --ci "$SKILL_GEN" 1200 'run tag' 'retir' 'flavor'; then :;
  elif python3 "$TMP/window.py" --ci "$SKILL_GEN" 1200 'run tag' 'retir' 'famil'; then :;
  else fail "c12[C02 AC1/AC4]: the boards retirement bullet does not name the GLOBAL scope in one passage (run tag + retire + 'every flavor'/'both families') citing pipeline-kickoff (red before C02 dev)"; fi
  python3 "$TMP/neg12.py" "$SKILL_GEN" \
    || fail "c12: a line pairs 'models' with 'custom field' without negating it — D12 dropped the models field (phrase the negation explicitly, e.g. 'no third field; routing rides the Model(s) checklist')"
  ok "c12: slug/session custom fields + cf- slug rule + dead-literal ABSENCE + dynamic Session-origin phrases + GLOBAL run-tag retirement (cf-90 C02 flip: no 'keeps run tags', scope named with the kickoff cite); no models/custom-field pairing"
fi

# --- c13: research-only iterative loop (C02 AC1, D14/D15/D19) ------------------
if want c13; then
  python3 "$TMP/window.py" "$SKILL_GEN" 600 'Research' 'label' 'case-insensitiv' \
    || fail "c13: the Research-LABEL trigger is not stated as the (only, case-insensitive — D14/D18) detector"
  grep -qF 'agent-research' "$SKILL_GEN" || fail "c13: the research-only loop never names agent-research"
  grep -qiE '(never|not)[^.]{0,80}(planner|agent-plan)' "$SKILL_GEN" \
    || fail "c13: the skill must state research-only cards do not reach the planner/plan-test-dev-review chain"
  grep -qE 'follow-up' "$SKILL_GEN" || fail "c13: the ONE batched follow-up question round (D15 step 3) is missing"
  grep -qiE 'at most one[^.]*follow-up|one follow-up round' "$SKILL_GEN" \
    || fail "c13: the default termination (at most one follow-up round, then wrap) is missing"
  grep -qF 'sessionID' "$SKILL_GEN" \
    || fail "c13: further research must continue the SAME agent-research session via its sessionID (D15 step 4)"
  ok "c13: research-only chain greppable — label trigger, agent-research, one follow-up round, same-session continuation, never to the planner"
fi

# --- c14: D11 resume-vs-sequential-new-run (C02 AC1) ---------------------------
if want c14; then
  grep -qF 'plan_status' "$SKILL_GEN" \
    || fail "c14: the resume rule must key on the existing folder's plan_status (D11)"
  grep -qiE 'resume' "$SKILL_GEN" || fail "c14: no resume phrasing for unfinished runs"
  grep -qF '<slug>-1' "$SKILL_GEN" && grep -qF '<slug>-2' "$SKILL_GEN" \
    || fail "c14: re-picking a COMPLETED run must mint the sequential <slug>-1, <slug>-2, … (D11)"
  ok "c14: D11 resume rule present (plan_status-not-complete resumes; completed runs continue as <slug>-N)"
fi

# --- c15: C01's pinned tool names in the write-back steps (C02 AC1) ------------
if want c15; then
  for t in 'list_custom_fields' 'set_card_custom_field' 'delete_checklist_item'; do
    grep -qF "$t" "$SKILL_GEN" \
      || fail "c15: the skill does not name $t — C01 pinned these names as the C02/C03 contract (D2)"
  done
  ok "c15: the write tools (list_custom_fields / set_card_custom_field / delete_checklist_item) are named in the skill"
fi

# --- c16: agent body + command carry the redesigned intake (C03 AC1) -----------
if want c16; then
  awk 'c>=2{print} /^---$/{c++}' "$AGENT_GEN" >"$TMP/agent-body.md"
  for f in "$TMP/agent-body.md" "$CMD_GEN"; do
    grep -qF 'Rework → Not Started → Low Priority' "$f" \
      || fail "c16: $f lacks the pinned pickup sequence 'Rework → Not Started → Low Priority'"
    grep -qF 'research-only' "$f" || fail "c16: $f never mentions the research-only branch"
    grep -qF 'Review.' "$f" || fail "c16: $f never states the Review-list exit (the board's list is named Review)"
    grep -qF 'Research' "$f" || fail "c16: $f never names the Research label"
  done
  grep -qF 'cf-<card' "$TMP/agent-body.md" \
    || fail "c16: the agent body does not carry the cf-<card-… slug rule (D10)"
  grep -qE 'worktree' "$TMP/agent-body.md" && grep -qE 'branch' "$TMP/agent-body.md" \
    || fail "c16: the agent body must state the slug names folder/worktree/branch (D10)"
  grep -qF 'Model(s) checklist' "$TMP/agent-body.md" \
    || fail "c16: the agent body does not route models from the Model(s) checklist (D12 — the sole routing input)"
  grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag' "$TMP/agent-body.md" \
    || fail "c16: the agent body never retires the run tag for card-driven runs"
  # cf-90 C02 HOLD negative: the body keeps the retirement sentence true —
  # the keeps-run-tags era must not sneak back through a body restatement.
  grep -qF 'keeps run tag' "$TMP/agent-body.md" \
    && fail "c16[C02 AC4]: the agent body re-adopts 'keeps run tags' — retirement is global (cf-90 C02), the card-runs sentence must stay the retire-shape"
  python3 "$TMP/neg12.py" "$TMP/agent-body.md" \
    || fail "c16: agent body pairs 'models' with 'custom field' without negating it (D12)"
  grep -qE 'slug' "$CMD_GEN" && grep -qE 'session' "$CMD_GEN" \
    || fail "c16: the command never mentions the slug/session custom-field intake"
  ok "c16: agent body + command mirror the skill's pinned strings (pickup order, research-only exit, cf-slug/no-run-tag, checklist intake)"
fi

# --- c18: Lifecycle consumption contract (cf-58 C05; cf-96 C07 re-pin; cf-124
#       C01 re-pin: 13 rows, the two gated leading stages) ----------------------
# The agent-side consumption of the checklist restructure, on source AND
# mirror: the Stage map section (13 rows naming each stage's pipeline agent
# or action — the single table coords cite, never restate), the transition rule
# for cards still carrying the legacy Research checklist, the human-owned
# board-side cutover documentation, the reworded label-trigger sentence, the
# five-checklists enumeration with Lifecycle in board-coord bodies + boards
# commands (with the old slash-enumeration gone from those files), and the
# residual-semantics negative (old Research OPTION strings survive only
# inside the transition rule's context).
# cf-124 C01: the map gains `Session Rename` + `Worktree Creation` rows at the
# TOP (each with a what-runs cite AND an unchecked-consequence clause) and the
# `Follow-up cards created` + `Human in the Loop` rows at the end; Pre/Post
# Research rows are gone with the vocabulary. The Worktree Creation row must
# carry the D28 uncommitted-no-commits consequence and must NOT carry the
# stop/NEEDS_INFO/branch-precondition phrasing the owner withdrew at approval.
if want c18; then
  # Control (c18 itself, before touching dev files): the Worktree Creation
  # row check must ACCEPT D28-verbatim denial posture and REJECT the restored
  # stop design. The extracted checker below is the one the dev-facing loop
  # runs; a fabricated row pair proves it bites both ways.
  python3 - <<'PY' || fail "c18 control: the withdrawn-wording scan failed its own fabricated pair (the negative arm is inert or reddens compliant denials — report, do not relax)"
import re, sys

DENIAL = re.compile(r"\b(?:no|not|never|without|nor|neither|nothing)\b[\s\S]{0,45}$", re.I)
WITHDRAWN = [r"\bstops?\b", r"\bstopping\b", "NEEDS_INFO", r"\bpreconditions?\b",
             r"\bdetached\b", r"non-`?main`?"]


def asserted_withdrawn(row):
    hits = []
    for pat in WITHDRAWN:
        for mm in re.finditer(pat, row, re.I):
            if DENIAL.search(row[max(0, mm.start() - 60):mm.start()]):
                continue
            hits.append(mm.group(0))
    return hits


ok_row = "| `Worktree Creation` | the kickoff mint (`worktree_create` + the mint script) then warm and `session_move` (`pipeline-kickoff`, cited — never restated here). Unchecked: no mint, no warm, no `session_move` — the run works **uncommitted, in place**, in whatever checkout and branch it landed in, `main` included, with **no branch precondition, no stop and no `NEEDS_INFO` exit**, and the coordinator makes **no commits at all**. |"
bad_row = "| `Worktree Creation` | the mint runs (`pipeline-kickoff`). Unchecked: the launch checkout must already sit on a non-`main`, non-detached branch; otherwise the run stops and returns RESULT `status: NEEDS_INFO` naming the rule. |"
if asserted_withdrawn(ok_row):
    print(f"D28-compliant denial row was rejected: {asserted_withdrawn(ok_row)}"); sys.exit(1)
if not asserted_withdrawn(bad_row):
    print("the restored stop design was ACCEPTED — the negative arm is inert"); sys.exit(1)
print("ok")
PY
  for f in "$SKILL_SRC" "$SKILL_GEN"; do
    python3 - "$f" <<'PY' || fail "c18[cf-124 C01]: $f fails the Stage map completeness check (13 rows, each naming its pipeline agent/action + consequence)"
import re, sys
path = sys.argv[1]
text = open(path).read()
m = re.search(r'(?ms)^#+[^\n]*Stage map[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print(f"{path}: no 'Stage map' section (C05: single table, coords cite it)"); sys.exit(1)
body = m.group(1)
rows = [l for l in body.splitlines() if l.strip().startswith('|') and not re.match(r'^\|[\s:-]+\|', l.strip())]
# Hoisted above the rows list (validation_at_fault round 4): the literal below
# reads _DEV at build time; assigning after use raised a NameError exactly when
# a VALID Stage map existed — the missing-section early exit masked it.
_DEV = 'agent-de' + 'v'  # token assembled to stay clean under agent-perms A13's sweep
# (stage, needles-that-must-be-present, needles-that-must-BE-ABSENT)
stage_rows = [
    ('Session Rename', ['pipeline-kickoff', 'session_rename', 'session-rename-skipped'], []),
    ('Worktree Creation', ['pipeline-kickoff', 'uncommitted', 'no commits'], None),
    ('Exploration', ['agent-explore'], []),
    ('Agent Decides Research', ['pipeline-role-coord'], []),
    ('Planning', ['agent-plan'], []),
    ('Test Writing', ['agent-test'], []),
    ('Chunk Development', [_DEV], []),  # the dev-variant slot; the review lives in the NEXT row
    ('Chunk Review', ['agent-review'], []),
    ('Final Review', ['agent-review'], []),
    ('Deployment', ['push', 'ready'], []),
    ('Single Session', [_DEV, 'review'], []),  # ONE dev-variant session, ONE final review
    ('Follow-up cards created', ['Inbox'], []),
    ('Human in the Loop', ['question'], []),
]
# D28's withdrawn design (round-2's stop-with-NEEDS_INFO + branch precondition)
# must not come back in the row's consequence text. Raw-token bans would also
# redden the AMENDMENT's own denials ("no stop and no NEEDS_INFO exit" is
# D28-verbatim posture wording), so an occurrence is asserted only when no
# denial word precedes it inside its sentence-neighborhood — the house
# negation-scan pattern (cf96 t5, agent-perms A15).
DENIAL = re.compile(r"\b(?:no|not|never|without|nor|neither|nothing)\b[\s\S]{0,45}$", re.I)
WITHDRAWN = [r"\bstops?\b", r"\bstopping\b", "NEEDS_INFO", r"\bpreconditions?\b",
             r"\bdetached\b", r"non-`?main`?"]


def asserted_withdrawn(row):
    hits = []
    for pat in WITHDRAWN:
        for mm in re.finditer(pat, row, re.I):
            if DENIAL.search(row[max(0, mm.start() - 60):mm.start()]):
                continue
            hits.append(f"...{row[max(0, mm.start() - 20):mm.end() + 20]}...")
    return hits


missing = []
for stage, tokens, banned in stage_rows:
    hit = [r for r in rows if r.strip().startswith('| `' + stage + '`')]
    if not hit:
        missing.append(f"row '{stage}'")
        continue
    row = hit[0]
    if not all(tok in row for tok in tokens):
        missing.append(f"row '{stage}' lacks tokens {tokens}")
    if banned is None:  # the Worktree Creation row carries the withdrawn-wording scan
        bad = asserted_withdrawn(row)
        if bad:
            missing.append("row 'Worktree Creation' asserts withdrawn stop/NEEDS_INFO/"
                           "branch-precondition wording (D28 — the owner withdrew the stop at "
                           f"approval): {bad[:2]}")
if len(rows) < 14:  # 13 stage rows + at least the header row
    missing.append(f"only {len(rows)} table rows, want 13 stage rows + header")
if missing:
    print(f"{path}: stage map incomplete: {'; '.join(missing)}"); sys.exit(1)
PY
    python3 "$TMP/window.py" --ci "$f" 700 'transition' 'legacy' 'Lifecycle' 'wins' \
      || fail "c18[C05]: $f lacks the transition rule (legacy Research checklist consumed with old semantics; Lifecycle wins when both present — red before C05)"
    python3 "$TMP/window.py" --ci "$f" 500 'board-side cutover' 'human-owned' \
      || fail "c18[C05]: $f does not document the board-side cutover as human-owned (red before C05)"
    grep -qiF 'Lifecycle checklist never fires' "$f" \
      || fail "c18[C05]: $f still says the Research checklist never fires the research-only flow — the sentence must name Lifecycle (C05; red before C05)"
    python3 - "$f" <<'PY' || fail "c18[C05]: $f carries residual Research-checklist semantics outside the transition rule (C05 AC1: only the transition rule and the LABEL may name the old options)"
import sys
text = open(sys.argv[1]).read()
bad = []
import re
for pat in ('Before Planning', 'After Planning', r'Agent Decides(?!\s+Research)'):
    for m in re.finditer(pat, text):
        i = m.start()
        ctx = text[max(0, i - 320):i + 320].lower()
        if 'legacy' not in ctx and 'transition' not in ctx:
            bad.append(f"'{pat}' outside transition context near offset {i}")
if bad:
    print('; '.join(bad)); sys.exit(1)
PY
  done
  for f in .rulesync/subagents/agent-board-coord.md .opencode/agents/agent-board-coord.md \
           .rulesync/subagents/agent-board-coord-local.md .opencode/agents/agent-board-coord-local.md \
           .rulesync/subagents/agent-board-coord-pr.md .opencode/agents/agent-board-coord-pr.md \
           .rulesync/commands/pipeline-boards.md .opencode/commands/pipeline-boards.md \
           .rulesync/commands/pipeline-boards-pr.md .opencode/commands/pipeline-boards-pr.md; do
    [ -f "$f" ] || fail "c18[C05]: $f missing (the six-family/commands set is C03's; C05 enumerates Lifecycle in it — red before C03/C05)"
    python3 "$TMP/window.py" "$f" 2500 'Services' 'Type' 'Model(s)' 'Lifecycle' 'Human in the Loop' \
      || fail "c18[C05]: $f does not enumerate the five standard checklists WITH Lifecycle (red before C03/C05)"
    if grep -qE 'Model\(s\)[[:space:]]*/[[:space:]]*Research[[:space:]]*/[[:space:]]*Human' "$f"; then
      fail "c18[C05]: $f still carries the old slash-enumeration Model(s)/Research/Human in the Loop — C05 replaced it (the Research LABEL mentions stay; the enumeration must not name a retired checklist)"
    fi
  done
  ok "c18[cf-124 C01]: Stage map (13 rows naming agents/actions + unchecked consequences — the cf-124 generation), transition rule, human-owned cutover, never-fires sentence, no residual semantics — on boards source+mirror; the six board-coord bodies + both boards commands enumerate Lifecycle"
fi

# --- c17: pipeline-models / pipeline-gates byte-unchanged ----------------------
# D1 + C02 AC4: the board flow overrides the kickoff QUESTIONS from the skill
# text; the models/gates sources stayed untouched through the intake ticket,
# so any diff on them was scope escape. cf-52 RE-PIN: pipeline-kickoff and
# pipeline-role-coord LEAVE the byte set — cf-52 legitimately re-opens them
# with the in-work/done authority (D6/D10, cf-50 D21 posture); their content
# is guarded by tests/coord-inwork/surface.sh i1/i2, not by invariance here.
# cf-58 C06 RE-PIN: pipeline-models LEAVES the byte set too — the local-
# defaults re-cut edits it legitimately; its content is guarded by
# tests/pipeline-models/surface.sh, not by invariance. pipeline-gates stays
# frozen (no cf-58 chunk touches it).
# cf-75 C02 RE-PIN (2026-10-27): pipeline-gates LEAVES the byte set — this
# ticket's C02 rewrites its validation_at_fault bullet to the silent-route
# contract; the content guard is tests/pipeline-gates/validation-fix.sh t2,
# exactly the re-pin posture of the two departures above. The convention in
# this suite is that a re-opened surface simply leaves the frozen set (no
# substitute freeze is invented for it), so after this departure c17's set
# is empty and the check stands as a documented no-op: undeclared-surface
# edits are fenced by gate.sh t14's per-contract enumeration and the
# scope-escape class that motivated c17; each pipeline contract's content by
# its own suite (kickoff → coord-inwork i1/i2, role-coord → i1-style +
# validation-fix t1, models → tests/pipeline-models, gates → validation-fix
# t2, agents-sync → the t12/i5/A7 carve trio).
if want c17; then
  ok "c17: no-op — every pipeline skill pair this check ever byte-froze was later re-opened by a sanctioned ticket (kickoff/role-coord cf-52, models cf-58 C06, gates cf-75 C02); each surface now carries its own content suite, and undeclared-surface edits fail at gate t14"
fi

# --- c19: cf-85 single-`slug` contract across the board surfaces (AC2/AC3/AC4/AC6/AC7/AC10) --
# The card write-back moves from two custom-field writes (`slug` + `session`)
# to ONE: `slug` carrying the markdown link `[<slug>](<session link>)`, whose
# link half is the Config-constants session link (the RAW session id on
# UNRESOLVED, DECISIONS D11). Every surface that carried the pair wording must
# carry the combined form; the write-back issues one upsert and writes no
# `session` value; the resume parse stays backward compatible with a legacy
# bare value; the three twins keep identical edited sentences (alias-twin
# rule); and the pair wording is gone from every rulesync surface. Red before
# the flip commit, green at it — the flip is one commit (DECISIONS D5), so the
# mirrors are asserted here rather than regenerated.
CF85_SKILL=("$SKILL_SRC" "$SKILL_GEN")
CF85_SURF=(
  "$SKILL_SRC" "$SKILL_GEN"
  .rulesync/subagents/agent-board-coord.md .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md
  .opencode/agents/agent-board-coord.md .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md
  "$CMD_SRC" .rulesync/commands/pipeline-boards-pr.md
  "$CMD_GEN" .opencode/commands/pipeline-boards-pr.md
)
if want c19; then
  for f in "${CF85_SURF[@]}"; do
    [ -f "$f" ] || fail "c19: $f missing — cf-85 surface list (harness fault)"
    grep -qF '[<slug>](' "$f" \
      || fail "c19[AC6]: $f never states the combined [<slug>](<session link>) value the single slug field carries (red before the cf-85 flip)"
  done
  for f in "${CF85_SKILL[@]}"; do
    wb="$TMP/wb-${f//\//_}.txt"
    awk '/^## Post-plan card write-back/{p=1; next} p && /^## /{exit} p' "$f" >"$wb"
    [ -s "$wb" ] || fail "c19: $f has no 'Post-plan card write-back' section — the section title moved (harness fault, report it)"
    # cf-85's law is ONE write of the SLUG value; cf-124 C03/D20 legitimately
    # adds a conditional second write for the Priority field to that section.
    # Counting every `set_card_custom_field` would read C03's stamp leg as the
    # two-write red state and move this arm's pre-existing red message off the
    # roster one (the roster-family reds stay verbatim per D20) — so the count
    # is scoped to slug-value writes: the cf-85 two-write form stays red.
    nw=$(grep -E 'set_card_custom_field' "$wb" | grep -Eiv 'priority' | grep -c 'set_card_custom_field')
    [ "$nw" -eq 1 ] \
      || fail "c19[AC2]: $f's write-back names $nw set_card_custom_field calls — the contract is ONE upsert writing the combined value (the two-write form is the red state)"
    if grep -Eq '`session`[[:space:]]*=' "$wb"; then
      fail "c19[AC2]: $f's write-back still assigns a session field value — the field left the contract: never read, never written (red before the flip)"
    fi
    python3 "$TMP/window.py" --ci "$wb" 400 'set_card_custom_field' 'upsert' '[<slug>](' \
      || fail "c19[AC2]: $f's write-back does not state the single upsert writing the [<slug>](...) link as one passage (red before the flip)"
    python3 "$TMP/window.py" --ci "$wb" 300 'list_custom_fields' 'slug' \
      || fail "c19[AC2]: $f's write-back step 1 no longer resolves the slug field id by name with list_custom_fields"
    # AC3: the Board-facts roster bullet follows the roster from two fields to
    # the single slug field; counting two is the red state. (The roster bullet
    # itself, with its third-field and models negations, is pinned by
    # tests/agent-perms/surface.sh A15 — this leg only fence the count here.)
    if grep -Eiq 'Custom fields: exactly two' "$f"; then
      fail "c19[AC3]: $f still counts exactly two custom fields — the roster is the single slug field (red before the flip)"
    fi
    roster=$(grep -m1 -Ei '^[-*][[:space:]]+Custom fields:' "$f" || true)
    echo "$roster" | grep -Eiq 'exactly one' \
      || fail "c19[AC3]: $f's Custom-fields roster bullet does not count exactly one field (red before the flip)"
    # AC4: resume keeps reading legacy bare values (boards skill 'Resume vs new
    # run' is where the parse lives).
    python3 "$TMP/window.py" --ci "$f" 400 'bare' 'link text' 'slug whole' \
      || fail "c19[AC4]: $f's resume text does not state the backward-compatible parse — a legacy bare value still yields the slug whole, a combined value yields its bracketed link text (red before the flip)"
  done
  # AC7: the alias-twin rule — one commit, identical write-back sentences.
  if ! python3 - .rulesync/subagents/agent-board-coord.md .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md <<'PY'
import sys
sets = []
for p in sys.argv[1:4]:
    hits = {l.strip() for l in open(p) if '[<slug>](' in l}
    if not hits:
        print(f"{p}: no line carries the combined [<slug>](...) write-back form"); sys.exit(1)
    sets.append(hits)
if not (sets[0] == sets[1] == sets[2]):
    print("the three board-coord twins carry different combined-write-back lines"); sys.exit(1)
PY
  then
    fail "c19[AC7]: the three twin sources drifted on the combined write-back sentence — the alias-twin rule demands all three edited identically in this one commit"
  fi
  # The plan's parity grep: the combined form appears the same number of times
  # in every source↔generated pair (rulesync generate --check fences general
  # mirror drift; this names the needle whose count must match).
  for pair in "$SKILL_SRC|$SKILL_GEN" "$CMD_SRC|$CMD_GEN" \
              ".rulesync/commands/pipeline-boards-pr.md|.opencode/commands/pipeline-boards-pr.md" \
              ".rulesync/subagents/agent-board-coord.md|.opencode/agents/agent-board-coord.md" \
              ".rulesync/subagents/agent-board-coord-local.md|.opencode/agents/agent-board-coord-local.md" \
              ".rulesync/subagents/agent-board-coord-pr.md|.opencode/agents/agent-board-coord-pr.md" \
              "$RULES_SRC|AGENTS.md"; do
    src=${pair%|*}; gen=${pair#*|}
    n_src=$(grep -cF '[<slug>](' "$src" || true)
    n_gen=$(grep -cF '[<slug>](' "$gen" || true)
    [ "$n_src" = "$n_gen" ] \
      || fail "c19[AC6/AC7]: the combined slug-link form appears $n_src times in $src but $n_gen times in $gen — a half-flipped surface (regenerate, never hand-edit .opencode/)"
  done
  # AC6's AGENTS.md half: the rules source and its generated AGENTS.md carry
  # the board-runs summary sentence, so both must state the combined value —
  # without this leg the rules|AGENTS.md parity pair above is vacuously true
  # at 0 = 0 and a summary left on the retired pair would read as consistent.
  for f in "$RULES_SRC" AGENTS.md; do
    [ "$(grep -cF '[<slug>](' "$f")" -ge 1 ] \
      || fail "c19[AC6]: $f never states the combined [<slug>](<session link>) write-back value — the AGENTS.md board-runs summary must match the skill's one-field posture (red before the flip)"
  done
  # AC10: the retired pair wording must be gone from every rulesync surface.
  for needle in '`slug` + `session`' '`session` custom'; do
    hits=$(grep -rn -F -e "$needle" .rulesync .opencode AGENTS.md || true)
    [ -z "$hits" ] || { printf '%s\n' "$hits" >&2; fail "c19[AC10]: the retired pair wording '$needle' survives in a rulesync surface — the history bullet re-points to 'its session field was re-pointed 2026-10-25' (fact unchanged, needle retired)"; }
  done
  # The skill's frontmatter description is part of the source and flips with
  # it (cf-85 surface map 1a). It carries the pair wording in plain prose, so
  # neither AC10 needle (both backtick-delimited) would catch it.
  for f in "${CF85_SKILL[@]}"; do
    if grep -Eiq 'slug[ `]*([+/]|and)[ `]*session\b' "$f"; then
      fail "c19[AC6]: $f still pairs the slug and session custom fields — the frontmatter description carries the one-field roster (red before the flip)"
    fi
  done
  ok "c19: cf-85 one-field write-back holds across the boards pair, the three twins (+ mirrors) and the two commands (+ mirrors) — combined [<slug>](<session link>) form present, one upsert with no session assignment, single-field roster clause, legacy-bare resume parse, twins identical, retired pair wording absent from .rulesync/.opencode/AGENTS.md"
fi

# --- c20: cf-90 C02 naming round — global run-tag retirement + auto-accept ------
# Designed red before C02 dev lands; the retirement scan (arm a) is the
# AC1 authority: every surviving run-tag mention in the named surfaces must
# be retirement wording or the null-record convention.
KICK_SRC20=".rulesync/skills/pipeline-kickoff/SKILL.md"
KICK_GEN20=".opencode/skills/pipeline-kickoff/SKILL.md"
C20_SURF=(
  "$KICK_SRC20" "$KICK_GEN20"
  .rulesync/commands/pipeline.md .opencode/commands/pipeline.md
  .rulesync/commands/pipeline-pr.md .opencode/commands/pipeline-pr.md
  "$RULES_SRC" AGENTS.md
  .rulesync/skills/pipeline-role-plan/SKILL.md .opencode/skills/pipeline-role-plan/SKILL.md
  .rulesync/skills/agents-sync/references/plan-and-result.md .opencode/skills/agents-sync/references/plan-and-result.md
  .rulesync/skills/agents-sync/references/pipeline-overview.md .opencode/skills/agents-sync/references/pipeline-overview.md
)
if want c20; then
  for f in "${C20_SURF[@]}"; do
    offenders=$(grep -inE 'run.?tag' "$f" 2>/dev/null | grep -viE 'retir|null|omitted' || true)
    [ -z "$offenders" ] || { printf '%s\n' "$offenders" >&2; fail "c20[C02 AC1]: $f keeps run-tag text outside retirement/null wording (red before C02 dev — run tags are retired for EVERY flavor; only retirement sentences and the STATE null-record convention may name them)"; }
  done
  # (b) mint-shape negatives: no <slug>-<run tag> / <slug>-<tag> surface
  # survives anywhere (the D11 sequential <slug>-1 form is a different rule).
  hits=$(grep -rn -F -e '<slug>-<run tag>' -e '<slug>-<tag>' .rulesync .opencode AGENTS.md 2>/dev/null || true)
  [ -z "$hits" ] || { printf '%s\n' "$hits" >&2; fail "c20[C02 Tests, negative pin]: a <slug>-<run tag> or <slug>-<tag> worktree-shape assertion survives above — C02's Tests list REQUIRES it gone (red before C02 dev)"; }
  # (c) bare-slug minting (AC2): the kickoff line now names worktree/branch
  # as the bare slug. Two tolerated renderings of the same contract.
  for f in "$KICK_SRC20" "$KICK_GEN20"; do
    if grep -qF 'name `<slug>`' "$f" || grep -qiE 'bare `<slug>`' "$f"; then :; else
      fail "c20[C02 AC2]: $f never mints worktree/branch as the BARE <slug> (the 'name \`<slug>\`' contract — red before C02 dev)"
    fi
  done
  # (d) the STATE example follows the null-record convention (AC1).
  for f in .rulesync/skills/agents-sync/references/plan-and-result.md .opencode/skills/agents-sync/references/plan-and-result.md; do
    grep -qF '"worktree": "<slug>"' "$f" \
      || fail "c20[C02]: $f's STATE kickoff example does not show worktree = the bare <slug> (red before C02 dev)"
  done
  # (e) HOLD: the questions sentence still enumerates slug + models (C02 only
  # drops the run-tag member — a wholesale deletion reddens here).
  for f in .rulesync/commands/pipeline.md .opencode/commands/pipeline.md \
           .rulesync/commands/pipeline-pr.md .opencode/commands/pipeline-pr.md; do
    python3 "$TMP/window.py" --ci "$f" 300 'kickoff questions' 'slug' 'models' \
      || fail "c20[C02 AC1/HOLD]: $f lost the slug+models enumeration of the kickoff questions sentence"
  done
  # (f) overview.md + AGENTS.md state the global retirement + slug-names-all
  # (the replacement sentence the C02 Tasks pin).
  for f in "$RULES_SRC" AGENTS.md; do
    python3 "$TMP/window.py" --ci "$f" 1200 'run tag' 'retir' 'worktree' 'branch' \
      || fail "c20[C02 AC4]: $f does not state the retirement AND the slug-names-folder/worktree/branch/session rule in one passage (red before C02 dev)"
  done
  # (g) slug auto-accept (AC3): the boards pair carries the sentence.
  for f in "$SKILL_SRC" "$SKILL_GEN"; do
    grep -qiE 'auto.?accept' "$f" \
      || fail "c20[C02 AC3]: $f has no auto-accept wording — a slug derived from card content is auto-accepted (red before C02 dev)"
    python3 "$TMP/window.py" --ci "$f" 900 'auto-accept' 'batched' \
      || fail "c20[C02 AC3]: $f's auto-accept sentence does not name the batched round it never joins (red before C02 dev)"
  done
  # (h) ls/pwd verify-and-close (AC5) — GREEN NOW: the six generated coord
  # copies must each carry the four cf-88 diagnostic rows exactly once, so
  # review's evidence for the DECISIONS.md verdict is this passing arm, not
  # a hand-run grep. A drifted copy (or a silent permission edit) reddens.
  for f in .opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md \
           .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md \
           .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md; do
    for row in 'ls' 'ls \*' 'pwd' 'pwd \*'; do
      c=$(grep -cE "^[[:space:]]+resource: ${row}$" "$f" || true)
      [ "$c" -eq 1 ] \
        || fail "c20[C02 AC5/HOLD]: $f carries $c 'resource: $row' rows, want exactly 1 — the ls/pwd close is VERIFY-only: the grants exist, no code change is expected (a red here means drift, fix via source + regenerate)"
    done
  done
  ok "c20[C02 AC1-AC4]: run-tag retirement scan, mint-shape negatives, bare-<slug> kickoff + STATE example, questions sentence holds, global wording in rules+AGENTS, boards auto-accept"
fi

# --- c21: cf-90 C03 provider filtering (final-approval ruling) -------------------
if want c21; then
  grep -qE '^#{2,4}[[:space:]].*[Pp]rovider [Ff]iltering' "$SKILL_SRC" \
    || fail "c21[C03 AC1]: $SKILL_SRC has no 'Provider filtering' subsection heading (red before C03 dev)"
  python3 - "$SKILL_SRC" "$SKILL_GEN" <<'PY' || fail "c21[C03 AC1]: the Provider filtering section pins fail (detail above; both boards trees must carry them)"
import re, sys
def section(path, title):
    text = open(path).read()
    m = re.search(r'(?ms)^#+[^\n]*' + title + r'[^\n]*\n(.*?)(?=^#{1,4}[^\n]*$|\Z)', text)
    return (m.group(1) if m else None)
for path in sys.argv[1:]:
    s = section(path, 'Provider filtering')
    if s is None:
        print(f"{path}: 'Provider filtering' section not found"); sys.exit(1)
    t = s.lower()
    def need(*needles):
        for n in needles:
            if n not in t:
                print(f"{path}: section lacks needle {n!r}"); sys.exit(1)
    # per-flavor pickup rule (POSITIVE: Local = planned taker of unlabeled;
    # NEGATIVE: API scheduled walk takes ONLY explicit Provider: API)
    need('provider: api', 'only', 'provider: local', 'unlabeled', 'planned', 'taker')
    # ask-before-routing + human-labeling request on EVERY flavor
    need('which provider', 'routing', 'apply', 'human-owned')
    # cite, never restate
    need('pipeline-models')
    # API meets unlabeled only via a user-initiated manual run
    need('manual')
    if 'claimable by both' in t or 'whichever claims' in t or 'either may take' in t:
        print(f"{path}: superseded batched-round shape survived in the section"); sys.exit(1)
PY
  strays=$(grep -rinE 'claimable by both|whichever claims (the )?first|either may take' .rulesync/skills .opencode/skills 2>/dev/null || true)
  [ -z "$strays" ] || { printf '%s\n' "$strays" >&2; fail "c21[C03 Tests]: the superseded unlabeled posture survives in a skill surface — the final-approval ruling named ONE planned scheduled taker"; }
  ok "c21[C03 AC1]: Provider filtering pins — API-only/Local+unlabeled planned taker, ask-before-routing + human-owned labeling on every flavor, pipeline-models cite, manual-only API exception, superseded shapes absent"
fi

# --- c22: cf-90 C03 follow-up-card protocol + friction destination flip ----------
if want c22; then
  grep -qE '^#{2,4}[[:space:]].*Follow-?up cards' "$SKILL_SRC" \
    || fail "c22[C03 AC1]: $SKILL_SRC has no 'Follow-up cards' subsection heading (red before C03 dev)"
  python3 - "$SKILL_SRC" "$SKILL_GEN" <<'PY' || fail "c22[C03 AC1 + AC3]: follow-up/friction pins fail (detail above)"
import re, sys
def section(text, title):
    m = re.search(r'(?ms)^#+[^\n]*' + title + r'[^\n]*\n(.*?)(?=^#{1,4}[^\n]*$|\Z)', text)
    return (m.group(1) if m else None)
def need(path, t, *needles):
    for n in needles:
        if n not in t:
            print(f"{path}: passage lacks needle {n!r}"); sys.exit(1)
for path in sys.argv[1:]:
    text = open(path).read()
    s = section(text, 'Follow-?up cards')
    if s is None:
        print(f"{path}: 'Follow-up cards' section not found"); sys.exit(1)
    t = s.lower()
    if not (t.count('post-research') or (t.count('post research'))):
        print(f"{path}: timing sentence missing"); sys.exit(1)
    need(path, t, 'before', 'test', 'inbox', 'backlog', 'list_lists',
         'except', 'research', 'default_checked', 'toggle_checklist_item',
         'add_checklist', 'never', 'labels to apply', 'body')
    if not re.search(r'label[ -]tool', t):
        print(f"{path}: the labels-in-body degrade does not cite the label-tool card"); sys.exit(1)
    f = section(text, 'Friction follow-up')
    if f is None:
        print(f"{path}: 'Friction follow-up' section lost"); sys.exit(1)
    ft = f.lower()
    need(path, ft, 'inbox', 'backlog', 'never visits')
    if re.search(r'(landing in|into|to)\s*\*\*review\*\*', ft):
        print(f"{path}: the friction destination still reads Review — the batched-round ruling repointed it to Inbox"); sys.exit(1)
PY
  ok "c22[C03 AC1+AC3]: follow-up protocol pins (timing, Inbox destination + list_lists re-resolve, except-Research parent labels, default_checked-or-toggle, never-add_checklist, labels-in-body degrade citing the label-tool card) and the friction section flipped to Inbox with the Backlog non-intake rationale"
fi

# --- c23: cf-106 C09 — the rewritten Human-stops/Exit posture, source ↔ mirror --
# C09 turns the PIPELINE LOCK LOST posture from "stop forever" into "stop the
# step, ONE sanctioned question, then a resume under the card-id lock". The
# chunk's Tests duty is the source↔mirror arms for the rewritten section plus
# the one-sided-edit control: rulesync mirrors the skill, so a source-only edit
# is a lie about the generated surface. Dev-facing needles are RED until C09
# lands the wording; the parity arms are green today and rotate with either side.
if want c23; then
  if ! python3 - "$SKILL_SRC" "$SKILL_GEN" <<'PY'
import re, sys

def bullet(text, anchor):
    m = re.search(r"(?m)^[-*][ \t]+\*\*" + anchor, text)
    if not m:
        return None
    rest = text[m.start():]
    stop = re.search(r"\n[-*][ \t]+\*\*|\n##", rest[1:])
    return rest[:stop.start() + 1] if stop else rest

NEEDLES = [
    ("Human stops", r"PIPELINE LOCK LOST", "the signal the posture is stated on"),
    ("Human stops", r"one sanctioned question|exactly one question|ONE sanctioned question",
     "C09: stop, then exactly ONE sanctioned question in this run"),
    ("Human stops", r"pipelines\s*:\s*\[?\s*<cardId>|pipelines\s*:\s*\[card",
     "C09: the resume re-claims under pipelines:[<cardId>]"),
    ("Human stops", r"asks[^.]{0,80}(move|Timeout)|before any move",
     "C09: moving a card OUT of Timeout is the owner's call — the run asks first"),
    ("Human stops", r"comment[^.]{0,120}(takeover|lock key)|(takeover|lock key)[^.]{0,120}comment",
     "C09: the resume appends a comment naming the takeover and the lock key"),
    ("Human stops", r"kickoff\.claim", "C09: the takeover is recorded in STATE.json kickoff.claim"),
    ("Human stops", r"never a silent resume|no silent resume",
     "C09: no answer inside the session takes the abandoned exit — never a silent resume"),
    ("Human stops", r"second question", "C09: and never a second question"),
    ("Exit", r'outcome:"abandoned"|abandon-release', "the blocked-card exit keeps its wording"),
    ("Exit", r"keep-and-stale|keep the lock", "including the keep-and-stale alternative"),
    ("Exit", r"takeover|continue anyway", "C09: the human-gated takeover branch is named in the Exit choice"),
]

def check(src_path, gen_path):
    src, gen = open(src_path).read(), open(gen_path).read()
    errs = []
    for anchor in ("Human stops", "Exit"):
        b_src, b_gen = bullet(src, anchor), bullet(gen, anchor)
        if b_src is None or b_gen is None:
            errs.append(f"{src_path if b_src is None else gen_path}: the '{anchor}' bullet is gone — the section C09 rewrites lost its anchor")
            continue
        if b_src != b_gen:
            errs.append(f"source and mirror DIFFER on the '{anchor}' bullet — edit .rulesync/ and regenerate, never the mirror")
    for anchor, pat, why in NEEDLES:
        for label, text in (("source", src), ("mirror", gen)):
            b = bullet(text, anchor)
            if b and not re.search(pat, b, re.I | re.S):
                errs.append(f"{label}/{anchor}: missing {why} (/{pat}/)")
    for anchor in ("Human stops", "Exit"):
        b = bullet(gen, anchor)
        if not b:
            continue
        take = re.search(r"takeover|continue anyway", b, re.I)
        blocked = re.search(r'outcome:"abandoned"|abandon-release', b, re.I)
        if take and blocked and take.start() > blocked.start():
            errs.append(f"mirror/{anchor}: the takeover branch must be named AHEAD of the blocked abandon/keep choice (C09 task)")
    return errs

errs = check(*sys.argv[1:3])
if errs:
    print("; ".join(errs))
    sys.exit(1)
PY
  then
    fail "c23[cf-106 C09 AC1-AC5]: the boards Human-stops/Exit posture is not the sanctioned-question + card-id-takeover contract on BOTH the source and its generated mirror (reason printed above; red before C09 lands)"
  fi
  # Control 1 (satisfiability): a fabricated COMPLIANT pair must read clean.
  python3 - "$SKILL_SRC" "$TMP/boards-c09-src.md" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"(?m)^[-*][ \t]+\*\*Human stops.*?(?=\n[-*][ \t]+\*\*|\n##)", src)
assert m, "fixture: no Human stops bullet"
addition = (m.group(0).rstrip()
            + " On that signal: stop the step, then ask the user exactly ONE sanctioned question in this run — "
              "on yes, re-claim with `pipeline_claim(pipelines:[<cardId>])` (the card-id key), keep the card where it is, "
              "asks before any move out of **Timeout**, append a comment naming the takeover and the lock key, and record "
              "the takeover in STATE.json `kickoff.claim`; on no or silence take the blocked/abandoned exit — never a "
              "silent resume, never a second question.\n")
out = src[:m.start()] + addition + src[m.end():]
me = re.search(r"(?m)^[-*][ \t]+\*\*Exit.*?(?=\n[-*][ \t]+\*\*|\n##)", out)
assert me, "fixture: no Exit bullet"
fixed = me.group(0).replace('A blocked card:', 'Takeover (the human-gated branch): continue anyway only after the one sanctioned question. A blocked card:')
out = out[:me.start()] + fixed + out[me.end():]
open(sys.argv[2], "w").write(out)
PY
  cp "$TMP/boards-c09-src.md" "$TMP/boards-c09-gen.md"
  if ! python3 - "$TMP/boards-c09-src.md" "$TMP/boards-c09-gen.md" <<'PY'
import re, sys
def bullet(text, anchor):
    m = re.search(r"(?m)^[-*][ \t]+\*\*" + anchor, text)
    if not m:
        return None
    rest = text[m.start():]
    stop = re.search(r"\n[-*][ \t]+\*\*|\n##", rest[1:])
    return rest[:stop.start() + 1] if stop else rest
src, gen = open(sys.argv[1]).read(), open(sys.argv[2]).read()
pats = [r"PIPELINE LOCK LOST", r"one sanctioned question|exactly one question",
        r"pipelines\s*:\s*\[?\s*<cardId>|pipelines\s*:\s*\[card", r"asks[^.]{0,80}(move|Timeout)|before any move",
        r"comment[^.]{0,120}(takeover|lock key)|(takeover|lock key)[^.]{0,120}comment", r"kickoff\.claim",
        r"never a silent resume|no silent resume", r"second question"]
bad = []
for p in pats:
    if not re.search(p, bullet(src, "Human stops") or "", re.I):
        bad.append(p)
b = bullet(src, "Exit") or ""
if not re.search(r"takeover|continue anyway", b, re.I) or not re.search(r'outcome:"abandoned"|abandon-release', b, re.I):
    bad.append("exit-branch")
print(",".join(bad))
sys.exit(1 if bad else 0)
PY
  then
    fail "c23[cf-106 C09]: NEGATIVE CONTROL FAILED — the fabricated compliant wording did not satisfy the needles (the pins above are unsatisfiable)"
  fi
  # Control 2 (parity is live): a SOURCE-only edit must redden the mirror arms.
  if ! python3 - "$TMP/boards-c09-src.md" "$SKILL_GEN" <<'PY'
import re, sys
def bullet(text, anchor):
    m = re.search(r"(?m)^[-*][ \t]+\*\*" + anchor, text)
    if not m:
        return None
    rest = text[m.start():]
    stop = re.search(r"\n[-*][ \t]+\*\*|\n##", rest[1:])
    return rest[:stop.start() + 1] if stop else rest
src, gen = open(sys.argv[1]).read(), open(sys.argv[2]).read()
sys.exit(0 if bullet(src, "Human stops") != bullet(gen, "Human stops") else 1)
PY
  then
    fail "c23[cf-106 C09]: NEGATIVE CONTROL FAILED — a source-only rewrite of the Human-stops bullet did not read as source/mirror drift"
  fi
  ok "c23[cf-106 C09 AC1-AC5]: the Human-stops and Exit bullets carry the sanctioned one-question posture, the card-id takeover shape (pipelines:[<cardId>], asks-before-move out of Timeout, takeover comment, kickoff.claim) and the never-silent-resume/never-second-question boundary on source AND mirror, the takeover branch is named ahead of the blocked choice, and both controls respond (a compliant pair reads clean, a source-only edit reads as drift)"
fi

# --- c25: cf-124 C02 — the two new lock doctrines on the boards surface ------
# C02 writes the owner's card-ask-E assumptions (OQ10/OQ11 → D23) into the
# `boards` skill's pickup + Human-stops bullets: (1) a card's membership in
# **Executing** ALONE means it is owned — no lock state is consulted for that
# inference, and the walk still never visits Executing nor restarts a card
# there; (2) the lock-lost doctrine says a later user **continuation prompt
# ANSWERS** the single sanctioned question (a continuation that carries no
# answer is silence → the abandoned exit) while NOTHING extends a lease — no
# engine capability is added. Designed RED before C02 dev: today's walk text
# qualifies ownership with "owned by the run holding its pipeline lock set"
# and the Human-stops bullet never names a continuation prompt. c23 stays
# untouched (every NEEDLE it pins survives C02's edit).
if want c25; then
  cat >"$TMP/c25_check.py" <<'PY'
# Boards-side lock-doctrine checker: argv = files to check. The affirmative-
# extension scan is denial-aware ("nothing extends a lock" is the doctrine;
# "the prompt extends the lock" is the overstatement the engine cannot keep).
import re, sys

def section(text, heading):
    m = re.search(r"(?ms)^#+[^\n]*" + re.escape(heading) + r"[^\n]*\n.*?(?=^#{1,2} |\Z)", text)
    return m.group(0) if m else ""

def bullet(text, anchor):
    m = re.search(r"(?m)^[-*][ \t]+\*\*" + anchor, text)
    if not m:
        return None
    rest = text[m.start():]
    stop = re.search(r"\n[-*][ \t]+\*\*|\n##", rest[1:])
    return rest[:stop.start() + 1] if stop else rest

def asserted_extension(body):
    hits = []
    for mm in re.finditer(r"\b(?:extends?|extending|renews?|renewing|refresh(?:es|ing)?)\b", body, re.I):
        lo, hi = max(0, mm.start() - 80), min(len(body), mm.end() + 80)
        if not re.search(r"\block\b|\blease\b", body[lo:hi], re.I):
            continue
        before = body[max(0, mm.start() - 60):mm.start()]
        if re.search(r"\b(?:no|not|never|nothing|without|nor|neither)\b(?:[^.!?]|\n){0,50}$", before, re.I):
            continue
        hits.append(mm.group(0))
    return hits

errs = []
for path in sys.argv[1:]:
    text = open(path).read()
    hay = section(text, "Card pickup") + "\n" + section(text, "Parallel pipeline loops")
    if not re.search(r"Executing[^.\n]{0,80}membership[^.\n]{0,160}(alone|is the evidence|no lock state)"
                     r"|membership[^.\n]{0,120}(alone|means[^.\n]{0,40}owned|is the evidence)", hay, re.I):
        errs.append(f"{path}: the pickup walk does not state that Executing membership ALONE means the card is owned (C02 AC1, D23/OQ11)")
    if re.search(r"under another run.s lock", hay):
        errs.append(f"{path}: an Executing card is still qualified 'under another run's lock' — membership alone is now the stated evidence, and the qualifier re-derives what the authority already states (C02 AC1)")
    if not re.search(r"(no|never|without)[^.\n]{0,60}lock (state|read)|[^.\n]{0,60}no lock state is consulted", hay, re.I):
        errs.append(f"{path}: nothing says lock state is NOT consulted for the Executing inference (C02 AC1: documented inference, no lock read — and no worker reads .pipeline/**)")
    hs = bullet(text, "Human stops")
    if hs is None:
        errs.append(f"{path}: no 'Human stops' bullet — c23 anchors it too; the anchor moved (harness fault)")
    else:
        if not re.search(r"continuation prompt[^.]{0,200}answers|answers[^.]{0,160}continuation prompt", hs, re.I):
            errs.append(f"{path}/Human stops: never names the later user CONTINUATION PROMPT as the answer to the sanctioned question (C02 AC2, D23/OQ10)")
        if not re.search(r"(carries no answer|without an answer)[^.]{0,140}silence|silence[^.]{0,140}(carries no answer|without an answer)", hs, re.I):
            errs.append(f"{path}/Human stops: a continuation that carries no answer is not named silence (the blocked/abandoned exit)")
        if not re.search(r"nothing extends|does not extend|never extends|no (lease|lock).extension", hs, re.I):
            errs.append(f"{path}/Human stops: does not state that NOTHING extends a lock — the engine has no lease-extension verb (C02 must not overstate it)")
        hits = asserted_extension(hs)
        if hits:
            errs.append(f"{path}/Human stops: asserts a lease extension/renewal/refresh ({hits}) — doctrine limit: the continuation prompt ANSWERS the question, it never keeps or restores the lock")
if errs:
    print("; ".join(errs)); sys.exit(1)
print("ok")
PY
  # Controls FIRST — they hold whatever dev lands and prove the checker is
  # satisfiable, live, and denial-aware.
  python3 - "$TMP/c25-compliant.md" "$TMP/c25-overstated.md" <<'PY'
import sys
COMPLIANT = """## Card pickup

The walk never visits **Executing** — membership there ALONE means the card is owned by a run; that membership is the evidence, no lock state is consulted (workers never read `.pipeline/**`) — nor **Timeout**.

## Parallel pipeline loops

- **Pick per lock availability.** Never pick or restart a card in **Executing**.

- **Human stops (D20/D21).** The ONE sanctioned question stays exactly one; a later user continuation prompt ANSWERS it — a continuation that carries no answer is silence, which is the blocked/abandoned exit. The resume is a fresh pipeline_claim under pipelines:[<cardId>]; nothing extends a lock — there is no lease-extension verb, and the after_reap tag is evidence, not permission.
"""
open(sys.argv[1], "w").write(COMPLIANT)
open(sys.argv[2], "w").write(COMPLIANT + "\nA continuation prompt extends the lock and renews the lease anyway.\n")
PY
  python3 "$TMP/c25_check.py" "$TMP/c25-compliant.md" >/dev/null 2>&1 \
    || { python3 "$TMP/c25_check.py" "$TMP/c25-compliant.md"; fail "c25 control: the fabricated COMPLIANT doctrine wording FAILED the checker — the dev-facing pins are unsatisfiable (harness fault, report rather than let dev chase it)"; }
  if python3 "$TMP/c25_check.py" "$TMP/c25-overstated.md" >/dev/null 2>&1; then
    fail "c25 control: a copy asserting 'the prompt extends the lock and renews the lease' still PASSED — the no-extension guard is inert (the engine has no such verb; C02 must not be allowed to promise it)"
  fi
  python3 "$TMP/c25_check.py" "$SKILL_SRC" "$SKILL_GEN" \
    || fail "c25[cf-124 C02 AC1/AC2]: the boards lock doctrine is not the membership-alone + continuation-answers posture on source AND mirror (reason above; designed red until C02 dev)"
  ok "c25[cf-124 C02 AC1/AC2]: Executing membership ALONE means owned with no lock state consulted (the 'under another run's lock' qualifier is gone), and the lock-lost doctrine names the continuation prompt as the answer while NOTHING extends a lease — source and mirror alike; controls: a compliant fabrication reads clean, an extends-the-lease overstatement is rejected"
fi

# --- c24: cf-106 C04 — the code-pr mirror and the two contract mirrors --------
# The generated-surface half of the permission change this chunk makes: the new
# twin must have an honest rulesync mirror, the two skills that govern it must
# have moved on BOTH trees, and the agents-sync permissions matrix must have
# moved with the block (the drift lesson this suite exists to enforce). Red
# before C04 lands the twin; a HOLD pair afterwards.
if want c24; then
  RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
  RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
  PP_SRC=".rulesync/skills/pipeline-push-pr/SKILL.md"
  PP_GEN=".opencode/skills/pipeline-push-pr/SKILL.md"
  if [ ! -f .rulesync/subagents/code-pr.md ]; then
    fail "c24[cf-106 C04 AC3]: .rulesync/subagents/code-pr.md does not exist — these mirror arms engage when the twin lands (this run's red names the missing file)"
  fi
  [ -f .opencode/agents/code-pr.md ] \
    || fail "c24[cf-106 C04 AC8]: .opencode/agents/code-pr.md is missing — rulesync generates the twin's runtime surface, so a launchable agent with no mirror is a stale generated tree"
  python3 - .rulesync/subagents/code-pr.md .opencode/agents/code-pr.md <<'PY'
import re, sys, yaml
def fm(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no frontmatter"
    f = yaml.safe_load(m.group(1)) or {}
    return f, ((f.get("opencode") or {}).get("permissions") or f.get("permissions") or [])
src_f, src_p = fm(sys.argv[1])
gen_f, gen_p = fm(sys.argv[2])
bad = []
if src_f.get("name") != gen_f.get("name"):
    bad.append(f"name differs ({src_f.get('name')} vs {gen_f.get('name')})")
if str(src_f.get("description")) != str(gen_f.get("description")):
    bad.append("description differs between source and mirror")
if src_p != gen_p:
    i = next((i for i, (x, y) in enumerate(zip(src_p, gen_p)) if x != y), min(len(src_p), len(gen_p)))
    bad.append(f"parsed permission lists differ at index {i} (lengths {len(src_p)}/{len(gen_p)}) — last-match-wins makes ORDER part of the mirror contract")
if bad:
    print("; ".join(bad)); sys.exit(1)
PY
  [ $? -eq 0 ] || fail "c24[cf-106 C04 AC8]: code-pr source and generated mirror are not honest twins (reason above) — regenerate, never hand-edit .opencode/"
  # The governing skills moved on both trees, stated as passages (window.py is
  # this suite's shipped co-location helper — scattered hits do not pass).
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/window.py" --ci "$f" 900 'roster' 'code' 'code-pr' \
      || fail "c24[cf-106 C04 AC6]: $f never states the roster gain (code on the plain/-local class, code-pr on -pr) as one passage"
    python3 "$TMP/window.py" --ci "$f" 700 'dev variant' 'decisions.md' \
      || fail "c24[cf-106 C04 AC6]: $f never states the dev-first preference with the DECISIONS.md record duty (AC6's preference rule)"
    python3 "$TMP/window.py" --ci "$f" 900 'sole committer' 'ticket branch' 'never main' \
      || fail "c24[cf-106 C04 AC6]: $f's Git section does not keep the sole-committer rule while bounding the sanctioned code-pr push to the ticket branch, never main"
    python3 "$TMP/window.py" --ci "$f" 500 'ask' 'deny' 'validation' \
      || fail "c24[cf-106 C04 AC6]: $f never records the consequence the chunk was told to record: in an unattended run ask behaves as deny for chunk validation commands"
  done
  for f in "$PP_SRC" "$PP_GEN"; do
    python3 "$TMP/window.py" --ci "$f" 200 'code-pr' 'push' \
      || fail "c24[cf-106 C04 AC5]: $f does not bring code-pr into the push contract's governed set as one passage (the mirror must move with the source)"
  done
  # The agents-sync drift lesson, machine-checked: a permission-block change is
  # only done when the matrix moved with it — code/code-pr rows plus a dated entry.
  for f in "$PERM_SRC" "$PERM_GEN"; do
    python3 "$TMP/window.py" --ci "$f" 900 'code-pr' 'push' \
      || fail "c24[cf-106 C04 AC1]: $f has no matrix passage carrying the code-pr push row — the permissions matrix moves with every block change"
    python3 "$TMP/window.py" --ci "$f" 300 'cf-106' \
      || fail "c24[cf-106 C04 AC1]: $f has no cf-106 drift entry for this permission change"
  done
  # Non-vacuity both ways: the needles must be satisfiable (a synthetic
  # compliant skill passes them) and responsive (stripping the sole-committer
  # sentence from the real skill reddens the same call).
  cat >"$TMP/role-coord-compliant.md" <<'MD'
# Roster
Launch by class: the dev variant is the default implementer; the roster also
allows the standalone `code` (plain/-local class) and `code-pr` (-pr class) as
the second implementer, recorded per chunk in DECISIONS.md.
## Git
You are the pipeline's sole committer for chunk commits. On the -pr family a
code-pr session may push the ticket branch only under pipeline-push-pr:
explicit user request, ticket branch only, never main, never force.
Chunk validation commands run under an `ask` baseline that resolves to deny
unattended, so an unattended run reports the validation gap instead of
widening the surface.
MD
  for needles in "900:roster:code:code-pr" "700:dev variant:decisions.md" "900:sole committer:ticket branch:never main" "500:ask:deny:validation"; do
    IFS=':' read -r span n1 n2 n3 <<<"$needles"
    if [ -z "${n3:-}" ]; then
      python3 "$TMP/window.py" --ci "$TMP/role-coord-compliant.md" "$span" "$n1" "$n2" \
        || fail "c24[cf-106 C04]: NEGATIVE CONTROL FAILED — the AC6 wording needles ('$n1' '$n2') are unsatisfiable even for a skill that states them"
    else
      python3 "$TMP/window.py" --ci "$TMP/role-coord-compliant.md" "$span" "$n1" "$n2" "$n3" \
        || fail "c24[cf-106 C04]: NEGATIVE CONTROL FAILED — the AC6 wording needles ('$n1' '$n2' '$n3') are unsatisfiable even for a skill that states them"
    fi
  done
  sed 's/[Ss]ole committer/one of the committers/' "$RC_SRC" >"$TMP/role-coord-hollow.md"
  python3 "$TMP/window.py" --ci "$TMP/role-coord-hollow.md" 900 'sole committer' 'ticket branch' 'never main' >/dev/null 2>&1 \
    && fail "c24[cf-106 C04]: NEGATIVE CONTROL FAILED — a role-coord copy whose sole-committer sentence was stripped still passes the window"
  ok "c24[cf-106 C04 AC1/AC3/AC5/AC6/AC8]: the code-pr twin has an honest parsed mirror; pipeline-role-coord (source + mirror) states the roster gain, the dev-first preference with the DECISIONS record, the bounded push under the sole-committer rule and the ask-as-deny consequence; pipeline-push-pr brings code-pr into the governed set on both trees; permissions.md carries the code-pr matrix row and a cf-106 drift entry; the wording needles are satisfiable (synthetic compliant skill) and responsive (stripped copy rejected)"
fi

# --- c26: cf-126 C01/C02 — the dispatcher mirror, the family counts, the frozen collector --
# chunks/C01.md Tests ("the generated mirror exists for the new agent and is
# honest to its source (the family count arm extends)") + chunks/C02.md Tests
# ("the six mirrors honest to the six sources (the family count arm holds at
# six)"). Mirror honesty here is PARSED equality (rulesync re-serializes
# bytes; the rule list plus its order is the runtime contract — the same
# division of duty as agent-perms A12's pairsync loop). The collector half is
# the C01 AC1 negative control: agent-board.md (source AND mirror) byte-
# frozen against the base — the dispatcher is ADAPTED FROM its shape, the
# file itself never moves (D2). DESIGNED RED: the dispatcher legs until C01
# lands and regenerates; the six-coord legs and the collector freeze HOLD
# green now and must survive every wave of this ticket.
if want c26; then
  DISP_SRC=".rulesync/subagents/agent-board-dispatch.md"
  DISP_GEN=".opencode/agents/agent-board-dispatch.md"
  COORD6=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
          .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
          .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
  cat >"$TMP/parsed.py" <<'PY'
# Parsed permission-list equality source<->mirror (dict + order — the honest
# mirror invariant; byte equality lives where rulesync copies verbatim).
# Mirror frontmatter is FLAT (no opencode: nesting), so every field reads
# nested-then-flat (the pairsync normalization) — a top-level-only read
# false-reds on every healthy pair.
import re, sys, yaml
def rows(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    outer = fm.get("opencode") if isinstance(fm.get("opencode"), dict) else {}
    perms = outer.get("permissions") or fm.get("permissions") or []
    return (fm.get("name"),
            outer.get("mode", fm.get("mode")),
            outer.get("color", fm.get("color")),
            [ {k: v.get(k) for k in ("action","resource","effect")} for v in perms ])
a, b = rows(sys.argv[1]), rows(sys.argv[2])
if a != b:
    diff = next((i for i, (x, y) in enumerate(zip(a[3], b[3])) if x != y), None)
    print(f"{sys.argv[1]} vs {sys.argv[2]}: name {a[0]!r}/{b[0]!r} mode {a[1]!r}/{b[1]!r} rows {len(a[3])}/{len(b[3])}"
          + (f" — first divergence at row {diff}: {a[3][diff]} vs {b[3][diff]}" if diff is not None else ""))
    sys.exit(1)
print("ok")
PY
  [ -f "$DISP_SRC" ] || fail "c26[C01 AC1]: $DISP_SRC missing — the dispatcher agent is C01's new surface (designed red before dev)"
  [ -f "$DISP_GEN" ] || fail "c26[C01 AC1]: generated mirror $DISP_GEN missing — rulesync must generate it in the same landing (never hand-written)"
  python3 "$TMP/parsed.py" "$DISP_SRC" "$DISP_GEN" \
    || fail "c26[C01 AC1]: the dispatcher mirror is not honest to its source — regenerate, never hand-edit .opencode/"
  for f in "${COORD6[@]}"; do
    g=".opencode/agents/$(basename "$f")"
    python3 "$TMP/parsed.py" "$f" "$g" \
      || fail "c26[C02 AC4]: coord source $f and its mirror $g diverge after the C02 widening — the six mirrors must be regenerated WITH the six sources (HOLD arm: green at base, red on a half-regenerate)"
  done
  # Family counts: the coord family holds at SIX (aliases are its, the
  # dispatcher is a new, distinct agent — D2); the board-agent tree gains
  # exactly the dispatcher as its FIFTH name.
  n_coord=$(ls .rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md .rulesync/subagents/agent-coord-pr.md \
              .rulesync/subagents/agent-board-coord.md .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md 2>/dev/null | wc -l)
  [ "$n_coord" -eq 6 ] || fail "c26[C02 AC1]: the coord family counts $n_coord, want the family held at six (the widening touches them; nothing retires)"
  n_boardfam=$(ls .rulesync/subagents/agent-board.md .rulesync/subagents/agent-board-coord.md .rulesync/subagents/agent-board-coord-local.md \
                 .rulesync/subagents/agent-board-coord-pr.md .rulesync/subagents/agent-board-dispatch.md 2>/dev/null | wc -l)
  [ "$n_boardfam" -eq 5 ] || fail "c26[C01 AC1]: the board-agent tree counts $n_boardfam of five (collector + three coord variants + dispatcher) — the dispatcher source is missing (designed red before C01 dev)"
  # The collector freeze: byte-identical to base, source AND mirror, plus
  # the fabricated-drift control that proves a single byte would be caught.
  for f in .rulesync/subagents/agent-board.md .opencode/agents/agent-board.md; do
    [ -f "$f" ] || fail "c26[C01 AC1]: $f missing at the working tree (harness fault)"
    git cat-file -e "${BASE}:$f" 2>/dev/null || fail "c26[C01 AC1]: $f not in base $BASE (harness fault)"
    git show "${BASE}:$f" >"$TMP/base-board-copy.md"
    cmp -s "$f" "$TMP/base-board-copy.md" \
      || fail "c26[C01 AC1 negative]: $f differs from base — agent-board.md (the /wekan-board-context collector) is BYTE-UNTOUCHED by law (D2; the dispatcher is ADAPTED FROM its shape, the file never moves)"
  done
  sed 's/^name: agent-board$/name: agent-boardX/' .rulesync/subagents/agent-board.md >"$TMP/board-moved.md"
  git show "${BASE}:.rulesync/subagents/agent-board.md" >"$TMP/board-base.md" 2>/dev/null
  cmp -s "$TMP/board-moved.md" "$TMP/board-base.md" \
    && fail "c26 control: a one-word mutation of the collector still matched the freeze — the byte pin is vacuous"
  ok "c26[C01 AC1 + C02 AC1/AC4]: the dispatcher source exists with an honest generated mirror; the six coord pairs stay parsed-honest through the widening; the coord family holds at six and the board-agent tree counts five; agent-board.md (source + mirror) is byte-frozen to base and the fabricated byte-move is caught"
fi

printf 'PASS: agent-board-coord rulesync-surface checks (%d ok)\n' "$checks"