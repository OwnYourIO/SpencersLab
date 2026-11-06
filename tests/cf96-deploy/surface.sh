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
# line shape + the stale-:v60 comment rewrite] t3[AC2 — probe pins: the
# registry-derived surface counts, checked per claim line (cf-106 C07 N5:
# re-pinned to content AND scoped — a stale count elsewhere on the page can no
# longer satisfy the arm), the eight names, the readonly-tier shape, the ops
# recipe]
# t4[AC1 — L4 absorption line + owner-owned Inbox move-out] t5[AC2 —
# cutover apply legs: backup-before-import, artifact path, zero-action
# re-run, degrade-flip record] t6[AC1 negatives — nothing implies an
# agent-executed merge/pin/apply; no invented run number] t7[AC2 — the
# reporting contract: post-deploy legs as production read-backs]
# t8[C11 T5 — dead-sentence guard: the three deploy-recipe surfaces must
#     NOT carry the killed imagetools-as-tag-list claims (runbook: 'and its
#     tag list' co-located with imagetools inspect; container-creation: the
#     'Grab the run number from the workflow run or …' sentence), plus the
#     affirmative ops-reference half: the Deploy/verify loop carries
#     'tags/list'. GREEN ON ARRIVAL with the folded runbook; exact dead
#     sentences, no word-window games against corrected prose that
#     legitimately MENTIONS imagetools to warn about it.]
#
# Usage:
#   bash tests/cf96-deploy/surface.sh            # t1..t8
#   bash tests/cf96-deploy/surface.sh t6         # just the negatives
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

RUNBOOK="${CF96_RUNBOOK:-tests/cf96-deploy/readback-runbook.md}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-8]$ ]] || fail "unknown check id '$a' (expected t1..t8)"
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
  # N5 (cf-106 C07 round 2): the probe counts are registry-derived and the claim
  # must hold on the line that makes it — a grep-anywhere for '39' let a stale
  # '38 tools (17 reads + 21 writes)' sit on the probe line while a correct
  # '39-tool' line three lines away satisfied the arm. Scope: the lines that
  # state what the NEW build carries (the :v<run> bump narration and the
  # tools/list probe lines). The quoted narration of the build deployed TODAY
  # (":v60 = the 25-tool custom-field build") is history the runbook orders
  # rewritten, not a surface claim, so it stays out of scope.
  T3=$(mktemp -d /tmp/opencode/cf96-t3.XXXXXX) || fail "harness: mktemp failed"
  cat >"$T3/counts.py" <<'PY'
import re, subprocess, sys

runbook = sys.argv[1]
proc = subprocess.run([sys.executable, "tests/wekan-mcp/registry-parity.py", "counts",
                       "containers/wekan-mcp/wekan_mcp/server.py"],
                      capture_output=True, text=True)
if proc.returncode != 0:
    print(f"registry-parity counts failed ({proc.returncode}): {proc.stderr.strip()}")
    sys.exit(2)
reads, writes, total = (int(x) for x in proc.stdout.split()[:3])
WANT = {"tools": total, "reads": reads, "writes": writes}
CLAIM = re.compile(r"(?P<n>\d{1,3})(?P<k>[ -]tools?\b|-tool\b| reads\b| writes\b)")
BARE = re.compile(r":v<run>`?\s*=\s*(?P<n>\d{2,3})\b(?!\s*(?:tools?\b|reads\b|writes\b))")

bad, seen_tools, seen_reads = [], 0, 0
for no, line in enumerate(open(runbook).read().splitlines(), 1):
    if ":v<run>" not in line and "tools/list" not in line:
        continue
    for m in CLAIM.finditer(line):
        kind = "tools" if "tool" in m.group("k") else m.group("k").strip()
        got = int(m.group("n"))
        if got != WANT[kind]:
            bad.append(f"line {no} claims {got} {kind}; the registry says {WANT[kind]} ({reads} reads + {writes} writes = {total})")
        seen_tools += kind == "tools"
        seen_reads += kind == "reads"
    for m in BARE.finditer(line):
        if int(m.group("n")) != total:
            bad.append(f"line {no} claims the new build = {m.group('n')}; the registry says {total}")
        seen_tools += 1
if not seen_tools:
    bad.append("no scoped line states the new build's tool count — the probe count must be pinned, not left to the catalog alone")
if not seen_reads:
    bad.append("no scoped line states the read count — the readonly-tier probe (reads only, no new writes) is the _write_tool gating proof")
if bad:
    print("; ".join(bad))
    sys.exit(1)
PY
  counts_rc=0; counts_out=$(python3 "$T3/counts.py" "$RUNBOOK" 2>&1) || counts_rc=$?
  if [ "$counts_rc" -eq 2 ]; then
    printf '%s\n' "$counts_out" >&2
    fail "t3[harness]: the count checker could not run (registry-parity counts) — not a C07 red"
  elif [ "$counts_rc" -ne 0 ]; then
    printf '%s\n' "$counts_out" >&2
    fail "t3[C10 T1-5 + cf-106 C07 AC6]: the runbook's surface counts disagree with the tool registry (per-line, OQ-13: counts are content-pinned) — the probe count follows the registry, and the ledger must move with it"
  fi
  sed 's/\*\*39 tools\*\*/**38 tools**/' "$RUNBOOK" >"$T3/stale-total.md"
  cmp -s "$RUNBOOK" "$T3/stale-total.md" && fail "t3[cf-106 C07 N5]: harness — the stale-total control copy is identical to $RUNBOOK (the probe line lost its count claim)"
  python3 "$T3/counts.py" "$T3/stale-total.md" >/dev/null 2>&1 && fail "t3[cf-106 C07 N5]: NEGATIVE CONTROL FAILED — a runbook claiming 38 tools on the dev-boards probe line still passes: the per-line count arm is decoration"
  sed 's/(18 reads + 21 writes)/(17 reads + 21 writes)/' "$RUNBOOK" >"$T3/stale-reads.md"
  cmp -s "$RUNBOOK" "$T3/stale-reads.md" && fail "t3[cf-106 C07 N5]: harness — the stale-reads control copy is identical to $RUNBOOK (the read/write breakdown claim is gone)"
  python3 "$T3/counts.py" "$T3/stale-reads.md" >/dev/null 2>&1 && fail "t3[cf-106 C07 N5]: NEGATIVE CONTROL FAILED — a runbook claiming 17 reads still passes: the read-count half of the arm is decoration"
  for n in list_board_dependencies list_card_dependencies add_card_dependency edit_card_dependency remove_card_dependency preload_board set_card_labels get_card_details; do
    grep -qF "$n" "$RUNBOOK" || fail "t3[C10 T1-5 / cf-106 C07 AC6]: the new-tool probe list is missing $n"
  done
  grep -qE 'NO new writes|no new writes' "$RUNBOOK" \
    || fail "t3[C10 T1-5]: the readonly-tier probe (reads only, no new writes) is missing — _write_tool gating proof"
  grep -qF 'wekan-mcp-ops.md' "$RUNBOOK" \
    || fail "t3[C10 T1-5]: the probe recipe reference (skills/wekan-api/references/wekan-mcp-ops.md) is missing"
  grep -qF 'TNQJ2BrXenZovngTS' "$RUNBOOK" \
    || fail "t3[C10 T1-5]: the first-ever dependency round-trip probe must name the AI-Dev board id (the RESEARCH §1.5 no-agent-probe gap closes here)"
  grep -qE 'checklists' "$RUNBOOK" \
    || fail "t3[cf-106 C06 AC6]: the preload readback line never mentions the checklist state the enriched payload carries — the live check has to look for what C06 adds"
  grep -qE 'slug_stack' "$RUNBOOK" \
    || fail "t3[cf-106 C07 AC2]: the get_card_details readback line never names slug_stack/current_slug — the stack is the C01 contract the new tool carries"
  ok "t3[C10 T1-5 + cf-106 C06/C07]: probe arms pinned — 39 tools, eight names, readonly shape, the C06 preload field set and the C07 card-details stack, recipe, live round-trip"
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

# --- t8: dead-sentence guard on the three registry-recipe surfaces (C11 T5) ----------
if want t8; then
  OPS="skills/wekan-api/references/wekan-mcp-ops.md"
  CC="skills/container-creation/SKILL.md"
  [ -f "$OPS" ] || fail "harness: $OPS missing (C11 T5 host file)"
  [ -f "$CC" ] || fail "harness: $CC missing (C11 T5 host file)"
  python3 - "$RUNBOOK" "$OPS" "$CC" <<'PY' || fail "t8[C11 T5]: a killed recipe claim survived (reason above)"
import re, sys

def flat(path):
    return re.sub(r"\s+", " ", open(path).read())

run, ops, cc = flat(sys.argv[1]), flat(sys.argv[2]), flat(sys.argv[3])
for m in re.finditer(r"imagetools", run):
    w = run[max(0, m.start() - 200):m.end() + 200]
    if "and its tag list" in w:
        print(f"t8: the runbook still pairs `imagetools inspect` with a tag list: ...{w[:200]}..."); sys.exit(1)
if "Grab the run number from the workflow run or" in cc:
    print("t8: container-creation still carries the dead 'Grab the run number from the workflow run or' hint (the killed sentence)"); sys.exit(1)
if "tags/list" not in ops:
    print("t8: the ops Deploy/verify loop lost the anonymous tags/list enumeration half (C11 T5)"); sys.exit(1)
print("ok")
PY
  ok "t8[C11 T5]: imagetools-as-tag-list claims dead in runbook + container-creation; tags/list enumeration live in the ops reference"
fi

printf 'PASS: cf-96 deploy-runbook pin checks (%d ok)\n' "$checks"
