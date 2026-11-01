#!/usr/bin/env bash
# cf-96 C10 — deploy-chain runbook pin suite (HOLD chunk, human-executed)
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C10).
#
# C10 has NO code surface: every execution step lands after the merge and
# belongs to the OWNER (cf-90 C07 precedent — the agent deliverable is the
# read-back runbook as a REVIEW CONTRACT plus this offline suite pinning
# that its required steps never drift away).
#
# Red posture: GREEN AT AUTHORING by design — the runbook is this change's
# own deliverable, so these are HOLD pins (drift of the runbook fails
# loudly) + documented production read-back legs (runbook steps 4/5/8 are
# executed in production against the live clusters/board, never here; the
# suite deliberately does not encode their expected VALUES, only that the
# runbook carries them). The designed-reds of this ticket live in the other
# nine chunk suites; C10 is the pin-the-plan arm.
#
# AC trace: t1[C10 AC1 — steps 1–9 present, in order, actor-named]
# t2[AC1/AC3 — bump scope: dev + gpu per OQ8, exact file paths + image:
# line shape + the stale-:v60 comment rewrite] t3[AC2 — probe pins: 38
# tools, the seven names, the readonly-tier shape, the ops recipe]
# t4[AC1 — L4 absorption line + owner-owned Inbox move-out] t5[AC2 —
# cutover apply legs: backup-before-import, artifact path, zero-action
# re-run, degrade-flip record] t6[AC1 negatives — nothing implies an
# agent-executed merge/pin/apply; no invented run number] t7[AC2 — the
# reporting contract: post-deploy legs as production read-backs].
#
# Usage:
#   bash tests/cf96-deploy/surface.sh            # t1..t7
#   bash tests/cf96-deploy/surface.sh t6         # just the negatives
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

RUNBOOK="tests/cf96-deploy/readback-runbook.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-7]$ ]] || fail "unknown check id '$a' (expected t1..t7)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$RUNBOOK" ] \
  || fail "t1[C10 T1]: $RUNBOOK missing — the read-back runbook is the C10 deliverable (agent-authored review contract, cf-90 C07 precedent; it lives in tests/ because chunk files are plan/coord-owned)"

# --- t1: all nine steps, in order, each naming its actor ------------------------------
if want t1; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
# numbered "N. **Actor" step lines, 1..9 in order
steps = re.findall(r"(?m)^(\d)\.\s+\*\*", t)
if steps != [str(n) for n in range(1, 10)]:
    print(f"t1: step numbering found {steps} — the runbook must present T1 steps 1-9 in order"); sys.exit(1)
sec = re.search(r"(?ms)^## Steps.*?(?=^## |\Z)", t).group(0)
actors = {}
for m in re.finditer(r"(?m)^(\d)\.\s+\*\*([^*]+)\*\*", sec):
    actors[m.group(1)] = m.group(2).strip()
for n, who in (("1", "Owner"), ("2", "CI"), ("3", "Owner"), ("7", "Owner")):
    if who not in actors.get(n, ""):
        print(f"t1[C10 AC1]: step {n} must name {who} as its actor (got {actors.get(n)!r}) — no step may imply an agent-executed merge/build/bump/apply"); sys.exit(1)
# every step labels an actor; step 4/5/6/8/9 per the chunk's actor split
if len(actors) != 9:
    print(f"t1: only {len(actors)} steps parsed"); sys.exit(1)
print("ok")
PY
  then fail "t1[C10 AC1]: the step/actor pins failed (reason above)"; fi
  ok "t1[C10 AC1]: runbook presents the nine ordered steps, each actor-named (Owner/CI/ArgoCD/coord/user-probe)"
fi

# --- t2: the bump is EXACT and OQ8-scoped (three tiers, one commit) --------------------
if want t2; then
  grep -qF 'services/dev/prod/values.yaml' "$RUNBOOK" \
    || fail "t2[C10 AC3]: the runbook must name services/dev/prod/values.yaml for the boards bump"
  grep -qF 'services/gpu/prod/values.yaml' "$RUNBOOK" \
    || fail "t2[C10 AC3]: and services/gpu/prod/values.yaml for the gpu tiers (OQ8: all three tiers)"
  for who in boards wekan-admin wekan-readonly; do
    grep -qF "$who" "$RUNBOOK" || fail "t2[C10 AC3]: the '$who' entry is not named — bump scope line covers dev boards + gpu admin + gpu readonly"
  done
  grep -qF 'ghcr.io/ownyourio/wekan-mcp:v<run>' "$RUNBOOK" \
    || fail "t2[C10 AC3]: the image: line shape must be spelled verbatim with the v<run> PLACEHOLDER (the real number exists only post-merge/CI — T Notes: do not invent it)"
  grep -qF 'image: ghcr.io/ownyourio/wekan-mcp:v<run>' "$RUNBOOK" \
    || fail "t2[C10 AC3]: the bump instruction must give the exact line shape the owner can apply verbatim"
  grep -qE 'ONE commit|one owner commit|in ONE commit' "$RUNBOOK" \
    || fail "t2[C10 OQ8]: the one-owner-commit scope (all three tiers together) is not stated"
  grep -qF ':v60' "$RUNBOOK" \
    || fail "t2[C10 T3]: the stale ':v60 = the 25-tool build' comment narration rewrite must be spelled out (the values comment keeps telling the truth about the deployed surface)"
  ok "t2[C10 AC3]: bump scope + exact paths + v<run> placeholder + comment rewrite pinned"
fi

# --- t3: the probe arms ------------------------------------------------------------------
if want t3; then
  grep -qE '38 tools' "$RUNBOOK" || fail "t3[C10 T1-5]: the 38-tool probe count is not pinned in step 5"
  for n in list_board_dependencies list_card_dependencies add_card_dependency edit_card_dependency remove_card_dependency preload_board set_card_labels; do
    grep -qF "$n" "$RUNBOOK" || fail "t3[C10 T1-5]: the new-tool probe list is missing $n"
  done
  grep -qE '17 reads, NO new writes|no new writes' "$RUNBOOK" \
    || fail "t3[C10 T1-5]: the readonly-tier probe (17 reads, no new writes) is missing — _write_tool gating proof"
  grep -qF 'wekan-mcp-ops.md' "$RUNBOOK" \
    || fail "t3[C10 T1-5]: the probe recipe reference (skills/wekan-api/references/wekan-mcp-ops.md) is missing"
  grep -qF 'TNQJ2BrXenZovngTS' "$RUNBOOK" \
    || fail "t3[C10 T1-5]: the first-ever dependency round-trip probe must name the AI-Dev board id (the RESEARCH §1.5 no-agent-probe gap closes here)"
  ok "t3[C10 T1-5]: probe arms pinned — 38 tools, seven names, readonly shape, recipe, live round-trip"
fi

# --- t4: L4 absorption ----------------------------------------------------------------------
if want t4; then
  grep -qF 'r3ghE7qGj75HTnghH' "$RUNBOOK" \
    || fail "t4[C10 T1-3 / Run protocol]: ledger card L4's id is not named — the bump absorbs it and coord comments the absorption"
  grep -qiE 'absorb' "$RUNBOOK" \
    || fail "t4[C10]: the absorption wording is gone (L4 stays a live ask until this comment lands)"
  grep -qiE 'move-out stays owner-owned|owner-owned' "$RUNBOOK" \
    || fail "t4[C10 T1-3]: the plan's carve-out must survive: L4's Inbox MOVE-OUT stays owner-owned — the agent comments, nothing else"
  ok "t4[C10]: L4 absorb + coord-comments-only + owner-owned move-out pinned"
fi

# --- t5: cutover apply + verify + flip --------------------------------------------------------
if want t5; then
  grep -qiE 'backup' "$RUNBOOK" \
    || fail "t5[C10 T1-7]: the backup-before-import gate vanished — the card's explicit order (owner takes a board backup BEFORE the rules import)"
  python3 - "$RUNBOOK" <<'PY' || fail "t5[C10 T1-7]: the backup must be ordered BEFORE the import (reason above)"
import re, sys
t = re.sub(r"\s+", " ", open(sys.argv[1]).read())
i, j = t.lower().find("backup"), t.find("board-rules-v12.65.json")
if j < 0:
    print("t5: the C08 artifact path is not named — step 7 imports it"); sys.exit(1)
if t[:i].lower().count("import json") >= 1 and i > j:
    # only a real drift if an Import-JSON mention precedes the backup AND the
    # backup line sits after the artifact reference with no earlier backup
    print("t5: the backup reference sits after the artifact import instruction"); sys.exit(1)
seg = t[j-2000:j+2000]
if "backup" not in seg.lower():
    print("t5: no backup gate co-located with the import step"); sys.exit(1)
print("ok")
PY
  grep -qiE 'Import JSON' "$RUNBOOK" \
    || fail "t5[C10 T1-7]: the WeKan UI → Rules → Import JSON path must be spelled out (checklist extras are UI/import-only — that is WHY this step is human-executed)"
  grep -qE 'ZERO actions' "$RUNBOOK" \
    || fail "t5[C10 T1-8]: the zero-action re-run verification (schema-2 snapshot → provision-board.py --dry-run → ZERO) is missing"
  grep -qE -- '--dry-run' "$RUNBOOK" || fail "t5[C10 T1-8]: the exact engine invocation shape is missing"
  grep -qiE 'flip' "$RUNBOOK" && grep -qiE 'summary comment' "$RUNBOOK" \
    || fail "t5[C10 T1-9]: the degrade-flip record (coord, card #96 summary comment) is missing"
  ok "t5[C10]: backup-gated import, UI-path rationale, zero-action re-run, degrade-flip record pinned"
fi

# --- t6: negatives — the human-execution firewall (C10 AC1) ----------------------------------
if want t6; then
  python3 - "$RUNBOOK" <<'PY' || fail "t6[C10 AC1 negative]: the runbook implies an agent-executed merge/bump/apply (reason above)"
import re, sys
t = re.sub(r"\s+", " ", open(sys.argv[1]).read())
FORBID = [
    r"\bagents? (will |can |should )?(merges?|bumps?|appl(y|ies)|push(es)? main)\b",
    r"coord (merges|bumps|applies|pushes)",
    r"dev (merges|bumps|applies)",
]
for pat in FORBID:
    m = re.search(pat, t, re.I)
    if m:
        print(f"t6: agent-execution-shaped phrase /{pat}/ present: …{t[max(0,m.start()-60):m.end()+60]}…"); sys.exit(1)
# no invented run numbers: concrete :vNN may appear ONLY for the CURRENT
# state (:v87) and the stale-comment narration (:v60) — the target is v<run>.
for m in re.finditer(r":v(\d+)", t):
    if m.group(1) not in ("87", "60"):
        print(f"t6: an invented concrete tag :v{m.group(1)} — the run number exists only post-CI; the runbook carries the placeholder"); sys.exit(1)
if "v<run>" not in t:
    print("t6: the v<run> placeholder itself is gone — T Notes forbid inventing the number"); sys.exit(1)
print("ok")
PY
  ok "t6[C10 AC1]: no agent-executed merge/bump/apply phrasing; the run number stays a placeholder"
fi

# --- t7: reporting posture (HOLD legs are production read-backs) -------------------------------
if want t7; then
  grep -qiE 'commands_run' "$RUNBOOK" \
    || fail "t7[C10 T2/AC2]: the reporting contract (RESULT commands_run per probe leg, cf-90 C07 posture) is missing"
  grep -qiE 'production read-back|read-back' "$RUNBOOK" \
    || fail "t7[C10 T2]: the runbook must state that the post-deploy legs are production read-backs, not suite tests"
  grep -qiE 'never re-apply blindly|stop' "$RUNBOOK" \
    || fail "t7[C10]: the fail-loud posture on a red probe (verify sync landed before assuming — GitOps law) is missing"
  ok "t7[C10 AC2]: reporting contract pinned — probes surface via RESULT, red probes stop the chain"
fi

printf 'PASS: cf-96 deploy-runbook pin checks (%d ok)\n' "$checks"
