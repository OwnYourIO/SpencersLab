#!/usr/bin/env bash
# Kickoff-mints text & grant contract suite
# (2026/2026-10-bug-kickoff-mints-run-branch, C02).
#
# Pins the landing of "kickoff actually mints the run's branch":
#   m1  C01's behavior suite passes (plan Commands line 2; review runs one cmd)
#   m2  the grep-proof trio — 'kickoff-mint-branch' in all six kickoff/
#       role-coord/boards SKILL.md (source+generated), the exact resource
#       string 'bash scripts/kickoff-mint-branch.sh *' in all four coord files
#       (C02 AC4, plan Commands grep-proof)
#   m3  the contract text — honest worktree_create bullet + mint step + resume
#       clause (kickoff pair), step-0 mint + extended containment (role-coord
#       pair), citation-only boards line with no restated command (boards
#       pair, D12 posture), the three-allow matrix rows + drift entry
#       (permissions.md pair), and every cf-52 carry-set intact (in-work
#       contract strings, boards carry strings, withdrawn title strings absent
#       tree-wide)
#   m4  the frontmatter grant contract — the scoped shell allows
#       (arm-aware OR-form splice + literal-line twins, the atpos.py/splice.py
#       convention shipped in tests/coord-inwork/surface.sh and exercised by
#       tests/agent-perms/surface.sh A10; widened by
#       2026-10-bug-session-origin-no-line from SHELL3-only to the SHELL3|SHELL4
#       forms ladder — green at today's landed three-allow posture, admitting
#       the fourth session-origin grant the moment that C02 lands, while the
#       absolute four-allow presence duty lives in
#       tests/session-origin/surface.sh s4; negative controls prove the
#       mechanism rejects an unsanctioned row, a fabricated fifth row, and
#       off-anchor placement)
#   m5  the regeneration contract (generate --check + second-run no-op, the
#       PATH/npx skip-with-warning ladder — c7/t14/A6 precedent)
#   m6  the no-touch set — AGENTS.md, .rulesync/rules, both commands dirs,
#       the gate SCRIPT, pipeline-models/gates pairs byte-unchanged vs $BASE
#       (C02 AC6; the Q3/DECISIONS promise that AGENTS.md stays frozen)
#
# Red posture (post-landing, 2026-10-26/27): m1–m4 are GREEN — C01's script
# landed at 5a335aff2, C02's text + third grant landed at c6689202c, and m4
# now runs as the SHELL3|SHELL4 forms ladder widened by
# 2026-10-bug-session-origin-no-line (green at today's three-allow posture,
# accepting the fourth the moment that C02 lands; its designed-red carrier is
# tests/session-origin/surface.sh s4, not this file). m5 and m6 are HOLD
# guards: green at the test phase, and they turn red if any later chunk
# escapes scope or leaves a mirror stale. Both arms (BASE=HEAD and
# CHUNK_BASE=081b57889) keep passing until session-origin C02 lands, after
# which both arms (HEAD and the new landed posture) must go fully green again
# on one commit.
#
# Sibling posture: the legacy suites keep their regression duty through this
# ticket by widening to the sanctioned-FORMS ladder (two-allow cf-52 form OR
# three-allow kickoff-mints form, now three|four-allow after session-origin):
# tests/coord-inwork/surface.sh i4,
# tests/agent-board-coord/gate.sh t17, tests/agent-board-coord/
# rulesync-surface.sh c2. The absolute "four allows exist NOW" presence duty
# lives in tests/session-origin/surface.sh s4, so the session-origin C01-phase
# regressions stay green at both operational arms while that C02 contract is
# still designed-red.
#
# Offline-deterministic except m5's generator gate (skip-with-warning when
# rulesync is unresolvable) and m1's own scratch-repo fixtures.
#
# Usage (harness convention from tests/coord-inwork/surface.sh):
#   bash tests/kickoff-branch/surface.sh           # m1..m6
#   bash tests/kickoff-branch/surface.sh m3 m4     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

# Operational refs the m4 soundness controls use regardless of $BASE
# (tests/agent-perms/surface.sh A10 discipline): arm A = the landing parent of
# the cf-52 content (coord files carry NO shell allows), arm B = HEAD (the
# two-allow committed posture today; the three-allow committed posture after
# C02). 916044893/f11bfcb85-era bases are historical.
ARM_A=081b57889

SCRIPT_SUITE="tests/kickoff-branch/script.sh"
KICK_SRC=".rulesync/skills/pipeline-kickoff/SKILL.md"
KICK_GEN=".opencode/skills/pipeline-kickoff/SKILL.md"
RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
BOARD_SRC=".rulesync/skills/boards/SKILL.md"
BOARD_GEN=".opencode/skills/boards/SKILL.md"
COORD_SRC=".rulesync/subagents/agent-coord.md"
COORD_GEN=".opencode/agents/agent-coord.md"
BCOORD_SRC=".rulesync/subagents/agent-board-coord.md"
BCOORD_GEN=".opencode/agents/agent-board-coord.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"

MINT_RES='bash scripts/kickoff-mint-branch.sh *'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/kickoff-branch-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 6); do WANT["m$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^m[1-6]$ ]] || fail "unknown check id '$a' (expected m1..m6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -------------------------------------------------------------

cat >"$TMP/win.py" <<'PY'
# Co-location window (tests/coord-inwork/surface.sh win.py convention): the
# needles must read as one passage; --ci folds case for prose needles so the
# pins survive dev's register without pinning exact sentences.
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
        print(f'missing needle: {n}')
        sys.exit(1)
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
    print(f'no window of {span} chars covers all needles (min span {best})')
    sys.exit(1)
PY

cat >"$TMP/order1.py" <<'PY'
# First-occurrence order across the whole file (rulesync-surface.sh order.py
# convention without the section scoping): the mint step must sit in the
# worktree bullet, i.e. after worktree_create is introduced, not as a stray
# mention elsewhere in the skill.
import sys
path = sys.argv[1]
text = open(path).read().lower()
needles = sys.argv[2:]
pos = []
for n in needles:
    i = text.find(n.lower())
    if i < 0:
        print(f'needle "{n}" not in {path}'); sys.exit(1)
    pos.append(i)
if pos != sorted(pos):
    print(f'order violated: {list(zip(needles, pos))}'); sys.exit(1)
PY

cat >"$TMP/sectgrep.py" <<'PY'
# Row/section text pins (tests/agent-perms/surface.sh sectgrep.py convention):
# the permissions matrix rows are pinned by their label cell, the drift log by
# its section. Row regex uses [ \t] — Python re has no POSIX classes.
import re, sys
path, mode = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
text = open(path).read()
anchor, needles = rest[0], rest[1:]
if mode == "row":
    hay = "\n".join(l for l in text.splitlines()
                    if re.match(r"^\|[ \t]*" + re.escape(anchor) + r"[ \t]*\|", l))
elif mode == "section":
    m = re.search(r"(?ms)^#+[^\n]*" + re.escape(anchor) + r"[^\n]*\n.*", text)
    hay = m.group(0) if m else ""
else:
    print(f"unknown sectgrep mode '{mode}'"); sys.exit(2)
if not hay:
    print(f"{path}: no {mode} '{anchor}' content to search"); sys.exit(1)
for n in needles:
    if n not in hay:
        print(f"{path}: '{n}' missing from the {mode} '{anchor}' (red before C02 dev phase — the text row has not moved)")
        sys.exit(1)
PY

# m4 mechanism, SHELL3-only (no ladder — this suite owns the absolute presence
# duty; the legacy siblings own the forms ladder). Arm A normalizes the base
# first (strip any sanctioned rows, re-splice all three at the anchor) so a
# two-allow base + the +3 mint delta reads as the sanctioned posture — the
# C02-review geometry — while any fourth row still breaks equality in both
# arms.
cat >"$TMP/synth.py" <<'PY'
# Clone a coord file with a form mutation for the m4 controls. Rows are
# located by literal-line triples; the item indent is the resource line's
# indent minus the two-space key nesting, so both shapes (source nests under
# opencode:, generated at top level) survive. after-patch/after-origin are the
# modes that no-op when the appended allow is already present (the accept
# controls then use the real committed form); the negative-control modes
# append unconditionally so they stay meaningful after C02 lands.
import sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src).read().split("\n")
def find(resource):
    for i, l in enumerate(lines):
        if l.strip() == f"resource: {resource}":
            return i
    return -1
def block(item_ind, resource):
    return [f"{item_ind}- action: shell", f"{item_ind}  resource: {resource}", f"{item_ind}  effect: allow"]
MINT = "bash scripts/kickoff-mint-branch.sh *"
ORIGIN = "bash scripts/session-origin.sh*"
BAD = "git -C * checkout -b *"
i_p = find("opencode api patch /api/session/*")
assert i_p >= 0, "fixture source must carry the cf-52 two-allow posture"
item_ind = lines[i_p][: len(lines[i_p]) - len(lines[i_p].lstrip())][:-2]
i_m = find(MINT)
i_o = find(ORIGIN)
if mode == "after-patch":
    out = lines if i_m >= 0 else (lines[: i_p + 2] + block(item_ind, MINT) + lines[i_p + 2:])
elif mode == "after-origin":
    assert i_m >= 0, "the origin allow rides after the landed mint allow"
    out = lines if i_o >= 0 else (lines[: i_m + 2] + block(item_ind, ORIGIN) + lines[i_m + 2:])
elif mode == "after-anchor":
    j = next(k for k, l in enumerate(lines) if l.strip() == "- action: opencode")
    out = lines[:j] + block(item_ind, MINT) + lines[j:]
elif mode == "bad-row":
    out = lines[: i_p + 2] + block(item_ind, BAD) + lines[i_p + 2:]
elif mode == "fifth-row":
    assert i_o >= 0, "fifth-row needs the origin allow present (run after-origin first)"
    out = lines[: i_o + 2] + block(item_ind, BAD) + lines[i_o + 2:]
else:
    print(f"unknown synth mode {mode}"); sys.exit(2)
open(dst, "w").write("\n".join(out))
PY

cat >"$TMP/splice3.py" <<'PY'
# The m4 OR-form over the sanctioned-FORMS ladder (splice.py convention from
# tests/coord-inwork/surface.sh, incl. the arm A / arm B vocabulary that
# tests/agent-perms/surface.sh A10 greps from the shipped siblings):
#   SHELL3 — the three scoped allows this suite minted as its absolute duty
#     (cf-52 GET/PATCH + the mint triple), landed;
#   SHELL4 — SHELL3 plus the fourth scoped session-origin resolver allow
#     (`bash scripts/session-origin.sh*`, no-space glob — NQ1), admitted the
#     moment 2026-10-bug-session-origin-no-line C02's delta appears. The
#     absolute FOUR-allow presence duty lives in
#     tests/session-origin/surface.sh s4, never here — m4 stays green through
#     that ticket's C01 at today's three-allow posture.
#   arm A — current == the base normalized to exactly the form's allows after
#     the `opencode '*' allow` rule: sanctioned rows are stripped from the
#     base first, so a no-allow base, the cf-52 two-allow base and the
#     landed three-allow base all reach the same sanctioned posture — the +3
#     origin-triple geometry of a session-origin C02 review run is arm A; any
#     unsanctioned row survives normalization and breaks the equality.
#   arm B (committed base) — current == base AND base is idempotent under the
#     form's strip/re-insert at the anchor.
# A base already carrying the origin allow admits SHELL4 only (a landed
# four-allow state never regresses to three); every other base admits SHELL3
# or SHELL4 but never SHELL2 — the ladder never weakens.
import re, sys, yaml
base_path, cur_path, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
GET = {"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"}
PATCH = {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"}
MINT = {"action": "shell", "resource": "bash scripts/kickoff-mint-branch.sh *", "effect": "allow"}
ORIGIN = {"action": "shell", "resource": "bash scripts/session-origin.sh*", "effect": "allow"}
SHELL3 = [GET, PATCH, MINT]
SHELL4 = [GET, PATCH, MINT, ORIGIN]

def perms(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []

def splice(seq, form):
    anchor = [i for i, p in enumerate(seq)
              if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
    if len(anchor) != 1:
        return None, len(anchor)
    i = anchor[0]
    return seq[:i + 1] + form + seq[i + 1:], i

b, c = perms(base_path), perms(cur_path)
if b[0] != {"action": "*", "resource": "*", "effect": "deny"}:
    print("deny-baseline first rule changed at base — the suite's premise broke"); sys.exit(1)
if ORIGIN in b:
    forms = [SHELL4]
else:
    # m4's floor is the landed three-allow posture — SHELL2 never admitted.
    forms = [SHELL4, SHELL3]
norm = [p for p in b if p not in SHELL4]
hit = None
for form in forms:
    want, i = splice(norm, form)
    if want is None:
        print(f"base must carry exactly one opencode '*' allow, found {i}"); sys.exit(1)
    if c == want:
        hit = "arm A"
        break
if hit is None:
    if not any(p.get("resource") == MINT["resource"] for p in c):
        print("the third scoped mint allow is MISSING (the landed three-allow posture is this suite's floor — a tree below it broke some sibling's contract)"); sys.exit(1)
    if c == b:  # arm B candidate — committed base
        rebuilt = False
        for form in forms:
            stripped = list(b)
            if not all(s in stripped for s in form):
                continue
            for s in form:
                stripped.remove(s)
            again, _ = splice(stripped, form)
            if again is not None and b == again:
                rebuilt = True
                break
        if not rebuilt:
            print("arm B: current == base but the base is not a sanctioned allow form (SHELL3 or SHELL4) at the pinned splice position — the contract never landed or drifted off-anchor"); sys.exit(1)
    else:
        want, _ = splice(norm, SHELL4)
        extra = [p for p in c if p not in want]
        missing = [p for p in want if p not in c]
        print(f"frontmatter delta is not a sanctioned shell-allow form (three- or four-allow) in either arm: extra={extra} missing={missing}")
        sys.exit(1)
shells = [p.get("resource") for p in c if p.get("action") == "shell"]
if shells not in ([s["resource"] for s in SHELL3], [s["resource"] for s in SHELL4]):
    print(f"shell resources are {shells}, want exactly the three or four scoped allows in order (any fifth shell grant is unsanctioned)"); sys.exit(1)
if c[0] != b[0]:
    print("deny-baseline line drifted"); sys.exit(1)
if need_dev_boards and not any(p.get("action") == "dev_boards*" and p.get("resource") == "*"
                               and p.get("effect") == "allow" for p in c):
    print("dev_boards* allow missing from a board-coord file"); sys.exit(1)
PY

cat >"$TMP/atpos3.py" <<'PY'
# Arm-B line twin (atpos.py convention, forms-aware since session-origin): the
# sanctioned literal block — the nine allow lines (two session triples + the
# mint triple) or the twelve (plus the session-origin triple) — directly after
# the opencode '*' allow anchor, at the anchor's own indent; nothing else may
# continue the shell block.
import re, sys
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
lines = [l.rstrip(" \t\r") for l in m.group(1).split("\n") if l.strip()]
ANCHOR = re.compile(r"^(\s*)- action: opencode$")
WANT3 = [('resource: opencode api get /api/session*', 'effect: allow'),
         ('resource: opencode api patch /api/session/*', 'effect: allow'),
         ('resource: bash scripts/kickoff-mint-branch.sh *', 'effect: allow')]
WANT4 = WANT3 + [('resource: bash scripts/session-origin.sh*', 'effect: allow')]
hits = []
for i, l in enumerate(lines):
    am = ANCHOR.match(l)
    if am and lines[i + 1:i + 3] == [f"{am.group(1)}  resource: '*'", f"{am.group(1)}  effect: allow"]:
        hits.append((i, am.group(1)))
if len(hits) != 1:
    print(f"want exactly one '- action: opencode' + resource '*' + effect allow rule, found {len(hits)}"); sys.exit(1)
ind = hits[0][1]
at = hits[0][0] + 3
matched = 0
for want in (WANT4, WANT3):  # longest first: WANT3 is WANT4's prefix
    want_lines = [x for rule in want for x in
                  (f"{ind}- action: shell", f"{ind}  {rule[0]}", f"{ind}  {rule[1]}")]
    if lines[at:at + 3 * len(want)] == want_lines:
        matched = 3 * len(want)
        break
if not matched:
    print("neither the nine-line SHELL3 block nor the twelve-line SHELL4 block of literal shell allow lines "
          f"follows the opencode '*' allow at the pinned position (want under indent '{ind}', got {lines[at:at + 12]})"); sys.exit(1)
nxt = lines[at + matched] if at + matched < len(lines) else ""
if nxt.strip() == "- action: shell":
    print("a further '- action: shell' row continues the block after the sanctioned form — unsanctioned shell grant"); sys.exit(1)
PY

cat >"$TMP/m4-shape.py" <<'PY'
# Pair component of m4(c): parsed perms of source == generated (order too —
# last-match-wins makes order load-bearing), no shell grant touches git, the
# bash grants are exactly the landed mint pair or the landed mint + landed
# session-origin pair (no third bash grant), question allow kept, and the
# variant's MCP posture (none on plain coord, single dev_boards* after deny on
# board-coord).
import re, sys, yaml
src, gen, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
ps, pg = perms(src), perms(gen)
errs = []
if ps != pg:
    errs.append(f"parsed permission lists differ between {src} and {gen} (order included) — regenerate, never hand-edit the mirror")
for p in ps:
    if p.get("action") == "shell" and "git -C" in str(p.get("resource", "")):
        errs.append("a raw git -C shell grant exists — the plan's rejected mechanism (main-checkout flip hazard)")
bashish = [p for p in ps if p.get("action") == "shell" and str(p.get("resource", "")).startswith("bash ")]
if [p.get("resource") for p in bashish] not in (["bash scripts/kickoff-mint-branch.sh *"],
                                                 ["bash scripts/kickoff-mint-branch.sh *", "bash scripts/session-origin.sh*"]):
    errs.append(f"bash shell grants are {[p.get('resource') for p in bashish]}, want the landed mint grant alone or the landed mint + session-origin pair")
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in ps):
    errs.append("question allow lost (repo hard rule)")
if need_dev_boards:
    db = [i for i, p in enumerate(ps) if p.get("action") == "dev_boards*"]
    deny_at = next((i for i, p in enumerate(ps) if p.get("action") == "*" and p.get("effect") == "deny"), None)
    if len(db) != 1 or not (deny_at is not None and db[0] > deny_at):
        errs.append("the single narrow dev_boards* allow after the deny-all is gone")
    if any(p.get("action") == "dev*" for p in ps):
        errs.append("broad dev* allow appeared (D21)")
else:
    if any(p.get("action") in ("dev*", "dev_boards*") for p in ps):
        errs.append("a board MCP allow appeared on the plain coord")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY

# --- m1: the C01 behavior suite passes (plan Commands; review runs one cmd) ----
if want m1; then
  [ -f "$SCRIPT_SUITE" ] || fail "m1: $SCRIPT_SUITE is missing (the test-phase artifact itself — harness fault, not C01's)"
  if timeout 600 bash "$SCRIPT_SUITE" >"$TMP/m1.log" 2>&1; then
    ok "m1: tests/kickoff-branch/script.sh passes (C01 behavior contract green)"
  else
    tail -n 3 "$TMP/m1.log" >&2
    fail "m1: tests/kickoff-branch/script.sh does not pass (red before C01 dev phase — see the first red line above; it names the missing script)"
  fi
fi

# --- m2: the grep-proof trio across both trees (C02 AC4) ------------------------
if want m2; then
  miss_text=(); miss_res=()
  for f in "$KICK_SRC" "$KICK_GEN" "$RC_SRC" "$RC_GEN" "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "m2: $f is missing (harness fault)"
    grep -qF 'kickoff-mint-branch' "$f" || miss_text+=("$f")
  done
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    [ -f "$f" ] || fail "m2: $f is missing (harness fault)"
    grep -qF "$MINT_RES" "$f" || miss_res+=("$f")
  done
  [ ${#miss_text[@]} -eq 0 ] || fail "m2: 'kickoff-mint-branch' absent from: ${miss_text[*]} (red before C02 dev phase — the contract text has not landed in source or mirror)"
  [ ${#miss_res[@]} -eq 0 ] || fail "m2: '$MINT_RES' absent from: ${miss_res[*]} (red before C02 dev phase — the scoped grant has not landed in a coord file or its mirror)"
  ok "m2: mint string in all six skill files, resource string in all four coord files (source + generated)"
fi

# --- m3: contract text + citation posture + carry-sets (C02 tasks 1-3, 5) ------
if want m3; then
  for f in "$KICK_SRC" "$KICK_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 900 'worktree_create' 'detached' 'scripts/kickoff-mint-branch.sh' \
      || fail "m3: $f does not make the worktree bullet honest (worktree_create + detached + the mint command in one passage — red before C02 dev phase)"
    python3 "$TMP/order1.py" "$f" 'worktree_create' 'scripts/kickoff-mint-branch.sh' \
      || fail "m3: $f mentions the mint before worktree_create is introduced — the mint step must live in the worktree bullet"
    python3 "$TMP/win.py" --ci "$f" 700 'resume' 'idempoten' \
      || fail "m3: $f lacks the Q6 resume clause (on resume, the same idempotent mint) in one passage — red before C02 dev phase"
    for s in 'metadata.openchamber.work' 'openedBy' 'doneAt' 'suggestDoneAt' 'done' 'skip'; do
      grep -qF "$s" "$f" || fail "m3: $f lost the cf-52 in-work carry string '$s' (i1 windows must hold through the C02 edit)"
    done
    # i1's read-merge-write needle is matched case-insensitively (the bullet
    # opens with capital R); mirror that, not a stricter grep.
    grep -qiF 'read-merge-write' "$f" \
      || fail "m3: $f lost the cf-52 read-merge-write mandate (i1 window needle)"
  done
  for f in "$RC_SRC" "$RC_GEN"; do
    python3 "$TMP/win.py" --ci "$f" 1500 'mint' 'worktree' 'resume' \
      || fail "m3: $f step 0 does not name the mint alongside the worktree naming and the resume case — red before C02 dev phase"
    grep -qF 'scripts/kickoff-mint-branch.sh' "$f" \
      || fail "m3: $f never names the scoped mint command string — red before C02 dev phase"
    python3 "$TMP/win.py" --ci "$f" 700 'kickoff-mint-branch.sh' 'never' 'own' \
      || fail "m3: $f does not extend the containment sentence to the mint grant (own branch, own worktree, never anything else) — red before C02 dev phase"
    python3 "$TMP/win.py" --ci "$f" 1200 'session_rename' 'in-work' 'resume' \
      || fail "m3: $f broke the i2 step-0 window (rename + in-work + resume must still read as one passage)"
  done
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    grep -qF 'kickoff-mint-branch.sh' "$f" \
      || fail "m3: $f never cites the mint step in the slug surface list — red before C02 dev phase"
    python3 "$TMP/win.py" --ci "$f" 500 'kickoff-mint-branch.sh' 'pipeline-kickoff' \
      || fail "m3: $f does not pair the mint citation with pipeline-kickoff as the mechanism holder in one passage — red before C02 dev phase"
    if grep -qF 'bash scripts/kickoff-mint-branch.sh' "$f"; then
      fail "m3: $f restates the mint COMMAND — boards cites, never restates mechanics (C02 task: D12 posture)"
    fi
    for s in 'session_rename' 'cf-<card' 'Session origin:' 'VSCODE_PROXY_URI' '?session='; do
      grep -qF "$s" "$f" || fail "m3: $f lost the boards carry-set string '$s' (c12/i3 must hold through the added line)"
    done
    if grep -qE 'metadata\.openchamber|openchamber\.work' "$f"; then
      fail "m3: $f leaks the work-state key path (i3 single-source rule must survive C02)"
    fi
    if grep -qF 'openchamber--dev-thehackmeister-coder' "$f"; then
      fail "m3: $f re-introduces the proven-dead host literal"
    fi
  done
  for f in "$PERM_SRC" "$PERM_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row coord 'kickoff-mint-branch.sh' 'opencode api patch' \
      || fail "m3: $f coord shell cell does not list the three scoped allows — red before C02 dev phase (Q4: the matrix must track the permission-block change)"
    # The board-coord row may either name the mint grant or use the matrix's
    # established "same as coord" reference idiom (its edit/subagent cells
    # already do) — but the reference must state the CURRENT allow count: the
    # pre-C02 row says "none" there, so a reference form is accepted;
    # session-origin C02 legitimately moves the count three→four, so both
    # reference counts are admitted (naming the mint grant remains accepted).
    row=$(grep -E '^\|[[:space:]]*board-coord[[:space:]]*\|' "$f" || true)
    [ -n "$row" ] || fail "m3: $f has no board-coord row (c5/c6 duty broken by the matrix edit)"
    case "$row" in
      *'kickoff-mint-branch.sh'*|*'same three scoped shell allows'*|*'same four scoped shell allows'*) : ;;
      *) fail "m3: $f board-coord shell cell lists neither the mint grant nor a current-count 'same three/four scoped shell allows as coord' reference — red before C02 dev phase" ;;
    esac
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' 'kickoff-mint-branch' \
      || fail "m3: $f has no drift-log entry for the mint grant — red before C02 dev phase"
  done
  neg=$(grep -rn -e 'in-work:' -e 'done:' .rulesync/skills .opencode/skills 2>/dev/null || true)
  [ -z "$neg" ] || fail "m3: withdrawn title-convention string(s) under the skill trees: $neg"
  ok "m3: honest kickoff bullet + Q6 resume clause, role-coord step-0 mint + containment, boards citation-only, permissions rows + drift entry, every carry-set intact, no withdrawn title strings"
fi

# --- m4: the coord-pair scoped shell allows (C02 task 4) ---------------------
if want m4; then
  # (a) mechanism soundness — deterministic today (fail-fast still puts the
  # real-file red at the first unsatisfied duty afterwards): fixtures built
  # from the live files + arm A's committed posture prove the SHELL3 and
  # SHELL4 forms are accepted at both bases, and the controls reject a
  # fabricated row, a fifth row, and off-anchor placement.
  git show "$ARM_A:$COORD_SRC" >"$TMP/a-base.md" 2>/dev/null || fail "m4: $COORD_SRC not readable at $ARM_A"
  git show "$BASE:$COORD_SRC" >"$TMP/a-baseB.md" 2>/dev/null || fail "m4: $COORD_SRC not readable at $BASE"
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-t3.md" after-patch
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-t4.md" after-origin
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-bad.md" bad-row
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/a-off.md" after-anchor
  python3 "$TMP/synth.py" "$TMP/a-t4.md" "$TMP/a-fifth.md" fifth-row
  for b in a-base a-baseB; do
    python3 "$TMP/splice3.py" "$TMP/$b.md" "$TMP/a-t3.md" none >/dev/null \
      || fail "m4: CONTROL FAILED — splice3 rejects the sanctioned three-allow form at base $b (the landed posture would read as drift)"
    python3 "$TMP/splice3.py" "$TMP/$b.md" "$TMP/a-t4.md" none >/dev/null \
      || fail "m4: CONTROL FAILED — splice3 rejects the sanctioned four-allow form at base $b (session-origin C02's grant would be unsatisfiable)"
  done
  python3 "$TMP/atpos3.py" "$TMP/a-t4.md" >/dev/null \
    || fail "m4: CONTROL FAILED — atpos3 rejects the sanctioned twelve-line SHELL4 block (the landed-line arm-B posture)"
  if python3 "$TMP/atpos3.py" "$TMP/a-fifth.md" >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — atpos3 accepted a fabricated FIFTH row continuing the block (the sanctioned twelve)"
  fi
  if python3 "$TMP/splice3.py" "$TMP/a-base.md" "$TMP/a-fifth.md" none >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — splice3 accepted a fifth shell row (any non-sanctioned row must break both arms)"
  fi
  if python3 "$TMP/splice3.py" "$TMP/a-base.md" "$TMP/a-bad.md" none >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — splice3 accepted a fabricated (raw git -C) shell row (any non-sanctioned row must break both arms)"
  fi
  if python3 "$TMP/splice3.py" "$TMP/a-base.md" "$TMP/a-off.md" none >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — splice3 accepted the mint allow placed off the anchor"
  fi
  if python3 "$TMP/atpos3.py" "$TMP/a-bad.md" >/dev/null 2>&1; then
    fail "m4: CONTROL FAILED — atpos3 accepted the fabricated bad row"
  fi
  # the current two-allow posture rejected at the C02 arm (the designed-red
  # made explicit as a control, independent of the real-file outcome):
  git show "$BASE:$COORD_SRC" >"$TMP/a-cur-committed.md" 2>/dev/null
  if ! grep -qF "$MINT_RES" "$TMP/a-cur-committed.md"; then
    if python3 "$TMP/splice3.py" "$TMP/a-base.md" "$TMP/a-cur-committed.md" none >/dev/null 2>&1; then
      fail "m4: CONTROL FAILED — splice3 accepted the two-allow committed state at arm A (this suite must reject it: it is the C02 contract)"
    fi
  fi
  # (b) the real files: OR-form splice vs $BASE + arm-aware line twin.
  n=0
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    git show "$BASE:$f" >"$TMP/m4-base-$n.md" 2>/dev/null || fail "m4: $f not readable at $BASE"
    python3 "$TMP/splice3.py" "$TMP/m4-base-$n.md" "$f" "$adb" \
      || fail "m4: $f satisfies neither arm A ($BASE perms + a sanctioned three- or four-allow form spliced after the opencode allow) nor arm B (committed base already carrying a sanctioned form at that position) (base: $BASE)"
    if git diff --quiet "$BASE" -- "$f"; then
      python3 "$TMP/atpos3.py" "$f" \
        || fail "m4: $f has an empty diff vs $BASE (arm B posture) but does not carry a sanctioned literal allow block (nine or twelve lines) at the pinned position"
    else
      bc=$(git show "$BASE:$f" | grep -c '^[[:space:]]*- action: shell' || true)
      ns=$(git diff --numstat "$BASE" -- "$f" | head -n 1 || true)
      add=$(printf '%s' "${ns:-0	0}" | cut -f1)
      del=$(printf '%s' "${ns:-0	0}" | cut -f2)
      case "$bc-$add" in
        0-9) sed_start=1; sed_end=9 ;;
        0-12) sed_start=1; sed_end=12 ;;
        2-3) sed_start=7; sed_end=9 ;;
        3-3) sed_start=10; sed_end=12 ;;
        *) fail "m4: $f diff vs a $bc-allow base is +$add/-$del, want +3 (the mint triple on the two-allow posture, or the session-origin triple on the three-allow posture), +9 (full three-allow form on a no-allow base) or +12 (full four-allow form on a no-allow base), additions only (base: $BASE)" ;;
      esac
      [ "$del" = "0" ] || fail "m4: $f diff removes lines (-$del) — the delta must be additions only"
      git diff -U0 "$BASE" -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' | sed 's/^[[:space:]]*//' \
        >"$TMP/m4-add-$n.txt"
      printf '%s\n' '- action: shell' 'resource: opencode api get /api/session*' 'effect: allow' \
                    '- action: shell' 'resource: opencode api patch /api/session/*' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/kickoff-mint-branch.sh *' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/session-origin.sh*' 'effect: allow' \
        | sed -n "${sed_start},${sed_end}p" >"$TMP/m4-want-$n.txt"
      cmp -s "$TMP/m4-add-$n.txt" "$TMP/m4-want-$n.txt" \
        || fail "m4: $f added lines are not the sanctioned literals (see $TMP/m4-add-$n.txt vs $TMP/m4-want-$n.txt)"
    fi
  done
  # (c) shapes + negatives, parsed, both trees, per pair.
  for pair in "$COORD_SRC|$COORD_GEN|none" "$BCOORD_SRC|$BCOORD_GEN|dev-boards"; do
    IFS='|' read -r s g adb <<<"$pair"
    python3 "$TMP/m4-shape.py" "$s" "$g" "$adb" \
      || fail "m4: permission shape contract broken for the $s/$g pair"
  done
  ok "m4: coord files carry a sanctioned shell-allow form (three-allow landed posture or the four-allow form the moment session-origin C02's delta appears — the absolute four-allow duty lives in tests/session-origin/surface.sh s4); OR-form + arm-aware line twins, controls reject a fabricated row, a fifth row and off-anchor placement; deny-baseline, question, subagent/edit allows and the dev*/git-grant negatives hold in both trees"
fi

# --- m5: the regeneration contract (C02 AC5; ladder skip-with-warning) ---------
if want m5; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "m5: rulesync not resolvable here (PATH or npx cache) — generate --check + no-op gate skipped with warning (c7/t14/A6 precedent)"
    ok "m5[regen-hold]: generator gate skipped with warning (ladder found no rulesync)"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "m5: rulesync generate --check is not clean — committed generated surfaces are stale against the sources (HOLD guard: red if C02 edits sources without mirrors)"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "m5: rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "m5: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "m5: the second rulesync generate is not a no-op (sources and generated have drifted)"
    ok "m5[regen-hold]: generate --check clean and the second generate is a no-op (via $RS)"
  fi
fi

# --- m6: no-touch set vs $BASE (C02 AC6; Q3/DECISIONS AGENTS.md freeze) --------
if want m6; then
  NOTOUCH=(AGENTS.md .rulesync/rules .rulesync/commands .opencode/commands
           scripts/agent-board-coord-gate.sh
           .rulesync/skills/pipeline-models .opencode/skills/pipeline-models
           .rulesync/skills/pipeline-gates .opencode/skills/pipeline-gates)
  moved=$( { git diff --name-only "$BASE" -- "${NOTOUCH[@]}" 2>/dev/null || true;
             git ls-files --others --exclude-standard -- "${NOTOUCH[@]}"; } | sort -u || true )
  [ -z "$moved" ] || { printf '%s\n' "$moved" >&2; fail "m6: a no-touch path moved vs $BASE — AGENTS.md/.rulesync/rules/commands dirs/the gate script/pipeline-models/pipeline-gates stay untouched (C02 AC6, i5/c17 dependency)"; }
  ok "m6[hold]: AGENTS.md, rules, both commands dirs, the gate script, pipeline-models/gates pairs byte-unchanged vs $BASE (worktree included)"
fi

printf 'PASS: kickoff-mints contract checks (%d ok)\n' "$checks"
