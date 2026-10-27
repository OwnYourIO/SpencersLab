#!/usr/bin/env bash
# Coordinator In-work/done contract suite (2026/2026-10-cf-52-feat-coord-session-inwork, C01).
#
# Pins the native OpenChamber work-state contract the coord pair must carry:
# read-merge-write of metadata.openchamber.work at kickoff in BOTH coordinator
# variants, done ONLY on an explicit in-session user indication, sibling
# metadata (openchamber.kind) always preserved, and nothing consuming the
# state. Contract source: plan file "The init/done contract" + "Mechanism —
# VERIFIED" + chunks/C01.md "## Tests"; DECISIONS.md D8–D13 are binding (the
# round-1 title convention is WITHDRAWN — i1's negative pin locks it out).
#
# AC trace: i1[C01 AC2 kickoff authority] i2[AC3 role-coord wiring]
# i3[AC4 boards citation + key-path non-leak] i4[AC1 scoped shell grants —
# forms ladder SHELL2|SHELL3 after kickoff-mints C02, widened to
# SHELL2|SHELL3|SHELL4 by session-origin C02] i5[AC5 freeze set]
# i6[AC6 regeneration contract].
#
# Red before C01: i1–i4 and i6 (its pair-carry component) — the contract text
# and the two shell allows are simply absent from both trees yet; every red
# line names the missing contract, never a harness fault. i5 is the freeze
# guard: green at plan time and must STAY green — it fails only if C01 touches
# a byte-frozen surface. i6's generate/--check component skip-with-warns where
# rulesync is unresolvable (c7/t14 precedent); its pair-carry + pair-sync
# components are offline-deterministic so i6 is red-before-C01 regardless.
#
# No check here reads a live session, the OpenChamber API, or any server: the
# work state is a runtime value this repo deliberately has zero consumers for
# (D12) — the suite pins TEXT and frontmatter shape only.
#
# Operational bases (2026-10-bug-tests-edit-perms D10/D11 fold-in; every run
# must pass at BOTH default BASE=HEAD (arm B — the committed-delta posture on
# the integrated line, main >= 124fc2ae8) AND CHUNK_BASE=081b57889 (arm A —
# the landing parent of the cf-52 content 20ed5dfaf). i4 accepts either arm
# over a sanctioned-FORMS ladder (widened by
# 2026-10-bug-kickoff-mints-run-branch C02, widened again by
# 2026-10-bug-session-origin-no-line C02):
# SHELL2 = cf-52's two scoped session allows, SHELL3 = SHELL2 plus the third
# scoped `bash scripts/kickoff-mint-branch.sh *` mint allow, SHELL4 = SHELL3
# plus the fourth scoped `bash scripts/session-origin.sh*` origin-resolver
# allow (NO-SPACE glob, NQ1 — the resolver call is zero-arg). arm A = current
# equals the base normalized to exactly one admitted form's allows spliced at
# the pinned position; arm B = current == base AND the base itself is
# idempotent under that form's strip/re-insert (splice-idempotence, the c2
# PORT_REF re-pin precedent 2f7bbb873). A base already carrying the origin
# allow admits SHELL4 only, and one carrying the mint allow never admits
# SHELL2 — the ladder never weakens a post-landing state.
# Pre-landing bases are historical and need not pass: f11bfcb85 (an unrelated
# renovate chore), 916044893 as a chunk base (its child 081b57889 is the
# release-bot Chart.yaml commit the scope guards do not admit, D11), and the
# cf-52 branch bases (b0c975bf6-era). CHUNK_BASE=<ref> otherwise narrows the
# diff/splice checks to "since that commit"; default HEAD (working tree vs
# committed base — same convention as the sibling suites in
# tests/agent-board-coord/).
#
# tests-edit-perms carve: this ticket re-pins the agents-sync references byte
# freeze (D4) — see the i5 block comment.
#
# tests-edit-perms fold-in (D9/D10): at HEAD of the integrated line the OLD
# i4 exact-delta form could never pass — self-reference, cf-52's delta is
# committed at the default base — so i4 gains the OR-form and its line twins
# become arm-aware (empty diff => absolute presence pin of the literal allow
# rows, replacing the mechanical trap of cmp-ing an empty additions file
# against the want file). i5 gains the D4 carve: the four
# agents-sync references files (permissions.md + pipeline-overview.md, source
# and generated) leave the byte freeze — this ticket's matrix/incident text
# edit re-opens them; their integrity moves to source<->generated
# byte-equality (gate.sh t12, tests/agent-perms/surface.sh A5).
#
# Usage:
#   bash tests/coord-inwork/surface.sh           # i1..i6
#   bash tests/coord-inwork/surface.sh i4 i5     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

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

# Task 1.6 list; also the i5 freeze set. The fuser pair is named explicitly
# because D8 keeps the fuser untouched (bare titles → exact title-match
# survives) — an accidental fuser edit would silently break fusion hand-back.
FREEZE_PATHS=(
  scripts/agent-board-coord-gate.sh
  .rulesync/commands .opencode/commands
  .rulesync/skills/pipeline-role-fuser .opencode/skills/pipeline-role-fuser
  .rulesync/skills/agents-sync .opencode/skills/agents-sync
  .rulesync/skills/pipeline-models .opencode/skills/pipeline-models
  .rulesync/skills/pipeline-gates .opencode/skills/pipeline-gates
  AGENTS.md .rulesync/rules
  .agents/plans/templates
)

# The two scoped shell grants (task 1.1, agent-fuser precedent shape; D10).
SHELL_GET='opencode api get /api/session*'
SHELL_PATCH='opencode api patch /api/session/*'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/coord-inwork-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["i$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^i[1-6]$ ]] || fail "unknown check id '$a' (expected i1..i6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -----------------------------------------------------------

cat >"$TMP/win.py" <<'PY'
# Co-location window (tests/agent-board-coord/gate.sh win.py convention):
# needles must read as one passage; --ci folds case for prose needles so the
# pins survive dev's register (task "Notes for dev": match each file's voice),
# while a reordered or scattered contract still fails. Spans are sized to the
# passage the contract bullet actually occupies in C01 tasks 1.2/1.3, with
# slack for the HOW-to prose — generous enough not to over-pin wording,
# tight enough that file-wide scattering cannot satisfy them.
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

cat >"$TMP/sectwin.py" <<'PY'
# Window scoped to one heading's section (order.py section extraction from
# rulesync-surface.sh + the win.py sliding window): the boards in-work
# citation must read as part of Card-driven kickoff, not appear anywhere in
# the file — and the earlier passages of that section must not push the
# window closed, so this is a minimum-span search, not a first-occurrence gap.
import re, sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span, title = argv[0], int(argv[1]), argv[2]
needles = [n.lower() for n in argv[3:]] if ci else argv[3:]
text = open(path).read()
m = re.search(r'(?ms)^#+[^\n]*' + re.escape(title) + r'[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print(f'section "{title}" not found'); sys.exit(1)
body = m.group(1).lower() if ci else m.group(1)
pts = []
for n in needles:
    start, found = 0, 0
    while True:
        i = body.find(n, start)
        if i < 0:
            break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'needle "{n}" not in section "{title}"'); sys.exit(1)
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
    print(f'no window of {span} chars covers all needles in section "{title}" (min span {best})')
    sys.exit(1)
PY

cat >"$TMP/splice.py" <<'PY'
# i4/t17 frontmatter delta contract, OR-form over a sanctioned-FORMS ladder
# (2026-10-bug-tests-edit-perms D10; widened by
# 2026-10-bug-kickoff-mints-run-branch C02 to SHELL3; widened again by
# 2026-10-bug-session-origin-no-line C02 to SHELL4):
#   SHELL2 — cf-52's two scoped session-API allows;
#   SHELL3 — SHELL2 plus the third scoped mint allow (kickoff-mints, landed);
#   SHELL4 — SHELL3 plus the fourth scoped `bash scripts/session-origin.sh*`
#     origin-resolver allow (session-origin C02; NO-SPACE glob — NQ1).
# Either arm per admitted form:
#   arm A (delta pending) — current == the base normalized to exactly the
#     form's allows at the `opencode '*' allow` anchor: sanctioned rows are
#     stripped from the base first, so a no-allow base AND the three-allow
#     committed base both reach the same sanctioned posture (the +3-origin
#     geometry a session-origin C02 review run sees).
#   arm B (delta committed) — current == base AND base is idempotent under
#     that form's strip/re-insert — the c2 PORT_REF re-pin precedent
#     (2f7bbb873) expressed as a splice instead of a constant ref, which
#     keeps the suites' working-tree-vs-$BASE convention and its
#     red-then-green-in-run workflow.
# Ladder gating: a base already carrying the origin allow admits ONLY SHELL4
# (post-session-origin states never regress); a base carrying the mint allow
# admits SHELL4 or SHELL3 — green through this ticket's C01 and red-free at
# today's three-allow posture, while the absolute "four allows exist NOW"
# duty lives in tests/session-origin/surface.sh s4. The OR-form never
# degenerates into "empty diff => pass": every unsanctioned row survives
# normalization and breaks both arms' equalities, and the shell-set literal
# check rejects a fifth shell grant in every form. deny-baseline preservation
# and dev_boards* presence are enforced for BOTH arms below.
# Source files nest the block under opencode:, generated files at top level —
# read from whichever carries it.
import re, sys, yaml
base_path, cur_path, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
GET = {"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"}
PATCH = {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"}
MINT = {"action": "shell", "resource": "bash scripts/kickoff-mint-branch.sh *", "effect": "allow"}
ORIGIN = {"action": "shell", "resource": "bash scripts/session-origin.sh*", "effect": "allow"}
SHELL2 = [GET, PATCH]
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
elif MINT in b:
    forms = [SHELL4, SHELL3]
else:
    forms = [SHELL4, SHELL3, SHELL2]
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
    if not any(p.get("action") == "shell" for p in c):
        print("no sanctioned shell allow form is applied (red before C01 — cf-52's scoped session allows are absent)"); sys.exit(1)
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
            print("arm B: current == base but the base is not a sanctioned allow form (SHELL2, SHELL3 or SHELL4) at the pinned splice position — the contract never landed or drifted off-anchor"); sys.exit(1)
    else:
        want, _ = splice(norm, SHELL4)
        extra = [p for p in c if p not in want]
        missing = [p for p in want if p not in c]
        print(f"frontmatter delta is not a sanctioned shell-allow form in either arm: extra={extra} missing={missing}")
        sys.exit(1)
shells = [p.get("resource") for p in c if p.get("action") == "shell"]
if shells not in ([s["resource"] for s in SHELL2], [s["resource"] for s in SHELL3],
                  [s["resource"] for s in SHELL4]):
    print(f"shell resources are {shells}, want exactly the two-, three- or four-allow sanctioned form in order"); sys.exit(1)
if c[0] != b[0]:
    print("deny-baseline line drifted"); sys.exit(1)
if need_dev_boards and not any(p.get("action") == "dev_boards*" and p.get("resource") == "*"
                               and p.get("effect") == "allow" for p in c):
    print("dev_boards* allow missing from a board-coord file"); sys.exit(1)
PY

# Arm-B twin of the line-level delta check (T10). The +6/-0 numstat and
# literal-added-lines cmp are only meaningful while the delta is a working
# change; at a committed base the diff is empty, so cmp of an empty additions
# file against the 6-line want file is a mechanical trap that fails a healthy
# tree. On an empty diff this check asserts the positive instead: the six
# literal allow lines sit at the pinned position — directly after the three
# lines of the `opencode '*' allow` rule. Matching is anchor-relative and
# byte-exact, because the block's nesting shape differs between trees (the
# source nests it under `opencode:`, the generated mirror does not): the item
# dash must carry the anchor's own indent and the key lines one level deeper,
# while the key text and order are pinned literally. Indentation therefore has
# no degree of freedom left to drift in.
cat >"$TMP/atpos.py" <<'PY'
# Arm-B twin of the line-level delta check (T10), forms-aware (kickoff-mints):
# exactly one sanctioned literal block — the six-line SHELL2 block (cf-52) or
# the nine-line SHELL3 block (mint triple appended) — directly after the three
# lines of the `opencode '*' allow` rule. Matching is anchor-relative and
# byte-exact because the block's nesting shape differs between trees (source
# nests under `opencode:`, the generated mirror does not): the item dash
# carries the anchor's own indent, keys one level deeper. Indentation has no
# degree of freedom left to drift in, and a further `- action: shell` row
# continuing the block after a matched form is unsanctioned.
import re, sys
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
lines = [l.rstrip(" \t\r") for l in m.group(1).split("\n") if l.strip()]
ANCHOR = re.compile(r"^(\s*)- action: opencode$")
WANT2 = [('resource: opencode api get /api/session*', 'effect: allow'),
         ('resource: opencode api patch /api/session/*', 'effect: allow')]
WANT3 = WANT2 + [('resource: bash scripts/kickoff-mint-branch.sh *', 'effect: allow')]
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
for want in (WANT4, WANT3, WANT2):  # longest first: shorter blocks are its prefixes
    want_lines = [x for rule in want for x in
                  (f"{ind}- action: shell", f"{ind}  {rule[0]}", f"{ind}  {rule[1]}")]
    if lines[at:at + 3 * len(want)] == want_lines:
        matched = 3 * len(want)
        break
if not matched:
    print("none of the sanctioned literal blocks (SHELL2 six lines, SHELL3 nine, SHELL4 twelve) "
          f"follows the opencode '*' allow at the pinned position (want under indent '{ind}', got {lines[at:at + 12]})"); sys.exit(1)
nxt = lines[at + matched] if at + matched < len(lines) else ""
if nxt.strip() == "- action: shell":
    print("a further '- action: shell' row continues the block after the sanctioned form — unsanctioned fourth shell grant"); sys.exit(1)
PY

cat >"$TMP/fmshape.py" <<'PY'
# Shape assertions that must hold for BOTH coord variants after the delta
# (the t17 companion, re-pinned for cf-52): question allow, exactly five
# subagent allows, exactly the three plan-state edit allows, no broad dev*,
# and the shell set equals the two scoped session globs.
import re, sys, yaml
path, need_dev_boards = sys.argv[1], sys.argv[2] == 'dev-boards'
text = open(path).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
errs = []
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in perms):
    errs.append("question allow lost (repo hard rule)")
if any(p.get("action") == "dev*" for p in perms):
    errs.append("broad dev* allow appeared")
shells = [p.get("resource") for p in perms if p.get("action") == "shell"]
want2 = ["opencode api get /api/session*", "opencode api patch /api/session/*"]
if shells not in (want2, want2 + ["bash scripts/kickoff-mint-branch.sh *"],
                  want2 + ["bash scripts/kickoff-mint-branch.sh *", "bash scripts/session-origin.sh*"]):
    errs.append(f"shell resources {shells} != the two-, three- or four-allow sanctioned form in order")
subs = sorted(p.get("resource") for p in perms if p.get("action") == "subagent" and p.get("effect") == "allow")
if subs != sorted(["agent-plan", "agent-test", "agent-dev", "agent-review", "agent-research"]):
    errs.append(f"subagent allows are {subs}")
edits = sorted(p.get("resource") for p in perms if p.get("action") == "edit")
if edits != sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"]):
    errs.append(f"edit allows are {edits}")
if need_dev_boards:
    db = [i for i, p in enumerate(perms) if p.get("action") == "dev_boards*"]
    deny_at = next((i for i, p in enumerate(perms) if p.get("action") == "*" and p.get("effect") == "deny"), None)
    if len(db) != 1 or not (deny_at is not None and db[0] > deny_at):
        errs.append("the single narrow dev_boards* allow after the deny-all is gone")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY

cat >"$TMP/pairsync.py" <<'PY'
# i6(b): source/generated pair sync WITHOUT running the generator. rulesync
# re-serializes (key order, quote style, targets flattened away, leading blank
# line, trailing newline), so raw byte-equality would fail on every healthy
# pair. The real invariant: bodies equal once frontmatter and surrounding
# blank space are stripped, and the frontmatter's meaningful fields equal once
# parsed (folded descriptions parse to the same string at any wrap width).
# A hand-edited mirror or an un-regenerated source lands here — and only here
# — when the contract substrings happen to be present in both trees.
import re, sys, yaml
src, gen, kind = sys.argv[1], sys.argv[2], sys.argv[3]

def parts(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{path}: no parsable frontmatter"
    return yaml.safe_load(m.group(1)), m.group(2).strip("\n") + "\n"

f1, b1 = parts(src)
f2, b2 = parts(gen)
if kind == "skill":
    n = lambda f: {k: f.get(k) for k in ("name", "description", "metadata", "disable-model-invocation")}
else:
    def n(f):
        oc = f.get("opencode") or {}
        return {"name": f.get("name"), "description": f.get("description"),
                "mode": oc.get("mode", f.get("mode")), "color": oc.get("color", f.get("color")),
                "permissions": oc.get("permissions", f.get("permissions"))}
if b1 != b2:
    print("body drift between source and generated mirror"); sys.exit(1)
if n(f1) != n(f2):
    print("frontmatter drift between source and generated mirror"); sys.exit(1)
PY

# --- i1: pipeline-kickoff pair — the single-authority contract text (AC2) -----
if want i1; then
  for f in "$KICK_SRC" "$KICK_GEN"; do
    [ -f "$f" ] || fail "i1: $f missing"
    python3 "$TMP/win.py" "$f" 800 'metadata.openchamber.work' 'open' 'done' \
      || fail "i1: $f does not pin the work key path with both state values in one passage"
    python3 "$TMP/win.py" --ci "$f" 200 'openedBy' 'auto' \
      || fail "i1: $f does not fix openedBy to the enum value 'auto' in one passage"
    grep -qF 'doneAt' "$f" || fail "i1: $f never names doneAt (the done-write's timestamp field)"
    python3 "$TMP/win.py" "$f" 900 'opencode api get /api/session' 'opencode api patch /api/session' \
      || fail "i1: $f does not carry both opencode api get/patch session carriers in one passage"
    python3 "$TMP/win.py" --ci "$f" 700 'read-merge-write' 'replaces' 'whole' \
      || fail "i1: $f lacks the read-merge-write mandate WITH its WHY (PATCH replaces metadata whole — siblings die on partial writes)"
    python3 "$TMP/win.py" --ci "$f" 300 'skip' 'state' 'open' \
      || fail "i1: $f does not state the idempotent skip (already-open reads → no write)"
    python3 "$TMP/win.py" --ci "$f" 300 'suggestDoneAt' 'reviewOffer' 'never' \
      || fail "i1: $f does not forbid writing the Jev-owned suggestDoneAt/reviewOffer"
  done
  # D8 locks the withdrawn round-1 title convention out; a 'done:'/'in-work:'
  # title string surviving anywhere in either skill tree re-opens the dead
  # convention, so the negative spans every skill, not just the pair.
  neg=$(grep -rn -e 'in-work:' -e 'done:' .rulesync/skills .opencode/skills 2>/dev/null || true)
  [ -z "$neg" ] || fail "i1: withdrawn title-convention string(s) present under the skill trees: $neg"
  ok "i1: kickoff pair carries the authority contract (key path, states, openedBy auto, doneAt, carriers, read-merge-write WHY, idempotent skip, Jev-field ban); no withdrawn title strings in any skill"
fi

# --- i2: pipeline-role-coord pair — wiring at init + done-on-user-only (AC3) ---
if want i2; then
  for f in "$RC_SRC" "$RC_GEN"; do
    [ -f "$f" ] || fail "i2: $f missing"
    python3 "$TMP/win.py" --ci "$f" 1200 'session_rename' 'in-work' 'resume' \
      || fail "i2: $f step-0 passage does not pair the rename/sessionID capture with the in-work mark AND name resume re-capture"
    python3 "$TMP/win.py" --ci "$f" 1400 'user' 'complete' 'doneAt' \
      || fail "i2: $f does not state the done-write (doneAt) gated on the user indicating completion in one passage"
    python3 "$TMP/win.py" --ci "$f" 400 'never' 'done' \
      || fail "i2: $f lacks the never-automatic sentence around the done mark (no auto-mark at final review or step-9 report)"
    python3 "$TMP/win.py" --ci "$f" 500 'opencode api' 'shell' 'own' 'never' \
      || fail "i2: $f does not carry the grant-containment sentence (the two shell grants exist ONLY for the own-session work mark, never anything else)"
  done
  ok "i2: role-coord pair — mark at step 0 (new + resume), done only on user indication (never automatic), grants contained by text"
fi

# --- i3: boards pair — citation-only mirror, no key-path leak (AC4) ------------
if want i3; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "i3: $f missing"
    python3 "$TMP/sectwin.py" --ci "$f" 500 'Card-driven kickoff' 'in-work' 'pipeline-kickoff' \
      || fail "i3: $f Card-driven kickoff lacks the one-line in-work citation to the pipeline-kickoff authority"
    # D12: boards never states the key path — the single authority is kickoff.
    if grep -qF 'metadata.openchamber' "$f" || grep -qF 'openchamber.work' "$f"; then
      fail "i3: $f leaks the work-state key path (metadata.openchamber/openchamber.work) — the contract is single-sourced in pipeline-kickoff"
    fi
    for s in 'session_rename' 'cf-<card' 'Session origin:' 'VSCODE_PROXY_URI' '?session='; do
      grep -qF "$s" "$f" || fail "i3: $f lost the carry-set string '$s' (card-driven kickoff must survive the added line)"
    done
    if grep -qF 'openchamber--dev-thehackmeister-coder' "$f"; then
      fail "i3: $f re-introduces the proven-dead host literal (cf-50 D25 r2: absence is correctness)"
    fi
  done
  ok "i3: boards pair — citation-only in-work line in Card-driven kickoff, no key-path leak, carry-set intact, dead literal absent"
fi

# --- i4: frontmatter delta on the coord pair — sanctioned shell-allow forms ----
# (AC1; kickoff-mints C02 widened "exactly the two cf-52 allows" to the forms
# ladder SHELL2|SHELL3, and session-origin C02 widens it to SHELL2|SHELL3|SHELL4
# — green through this ticket's C01 at both operational arms, admits the fourth
# scoped origin-resolver allow the moment C02's delta appears, and still
# rejects any fifth row, off-anchor placement, or a regression against a base
# that already carries the higher rung. The absolute four-allow presence duty
# lives in tests/session-origin/surface.sh s4, never here.)
if want i4; then
  n=0
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    git show "$BASE:$f" >"$TMP/base-$n.md" 2>/dev/null || fail "i4: $f not readable at $BASE"
    python3 "$TMP/splice.py" "$TMP/base-$n.md" "$f" "$adb" \
      || fail "i4: $f frontmatter is not a sanctioned shell-allow form (SHELL2 cf-52 two-allow / SHELL3 kickoff-mints three-allow / SHELL4 session-origin four-allow, gated by what the base carries) in either arm — arm A: normalized-base splice at the opencode allow; arm B: committed-base idempotence at that position (base: $BASE)"
    # Line-level twin of the semantic splice, arm-aware (T10/D10), now keyed
    # to the ALLOW COUNT THE BASE CARRIES: a no-allow base pairs with the
    # cf-52 +6 delta, the full +9 SHELL3 delta or the full +12 SHELL4 delta;
    # a two-allow base pairs with exactly the +3 mint triple; a three-allow
    # base (session-origin's C02 review geometry) pairs with exactly the
    # +3 origin triple; a four-allow base can only satisfy the twin through
    # an empty diff.
    # Additions-only keeps a reworded deny-baseline from hiding inside a
    # rewrite. On an empty diff the twin switches to the absolute
    # presence pin atpos.py — never "empty diff implies pass".
    if git diff --quiet "$BASE" -- "$f"; then
      python3 "$TMP/atpos.py" "$f" \
        || fail "i4: $f has an empty diff vs $BASE (arm B posture) but does not carry a sanctioned literal allow block (six, nine or twelve lines) directly after the opencode '*' allow"
    else
      bc=$(git show "$BASE:$f" | grep -c '^[[:space:]]*- action: shell' || true)
      ns=$(git diff --numstat "$BASE" -- "$f" | head -n 1 || true)
      add=$(printf '%s' "${ns:-0	0}" | cut -f1)
      del=$(printf '%s' "${ns:-0	0}" | cut -f2)
      case "$bc:$add" in
        0:6) rng='1,6' ;;
        0:9) rng='1,9' ;;
        0:12) rng='1,12' ;;
        2:3) rng='7,9' ;;
        3:3) rng='10,12' ;;
        *) fail "i4: $f diff vs $BASE is +$add/-$del on a base carrying $bc shell allows — want +6 (SHELL2 on a no-allow base), +9 (SHELL3 on a no-allow base), +12 (SHELL4 on a no-allow base), +3 (the mint triple on the two-allow posture) or +3 (the origin triple on the three-allow posture) (base: $BASE)" ;;
      esac
      [ "$del" = "0" ] \
        || fail "i4: $f diff vs $BASE removes $del lines — the sanctioned delta is additions-only"
      git diff -U0 "$BASE" -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' | sed 's/^[[:space:]]*//' \
        >"$TMP/add-$n.txt"
      printf '%s\n' '- action: shell' 'resource: opencode api get /api/session*' 'effect: allow' \
                    '- action: shell' 'resource: opencode api patch /api/session/*' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/kickoff-mint-branch.sh *' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/session-origin.sh*' 'effect: allow' \
        | sed -n "${rng}p" >"$TMP/want-$n.txt"
      cmp -s "$TMP/add-$n.txt" "$TMP/want-$n.txt" \
        || fail "i4: $f added lines are not the literal sanctioned allow rules (see $TMP/add-$n.txt vs $TMP/want-$n.txt)"
    fi
  done
  for f in "$COORD_GEN" "$BCOORD_GEN"; do
    python3 "$TMP/fmshape.py" "$f" "$( [ "$f" = "$BCOORD_GEN" ] && echo dev-boards || echo none )" \
      || fail "i4: generated $f breaks the permission shape that must hold through the delta"
  done
  ok "i4: all four coord files carry a sanctioned shell-allow form (OR-form over the forms ladder SHELL2|SHELL3|SHELL4: normalized-splice arm A or committed-idempotence arm B; line twins arm-aware, keyed to the base's allow count — +6/+9/+12/+3-empty/atpos); shapes, dev_boards* and deny-baseline intact"
fi

# --- i5: freeze set — byte-unchanged vs the ticket base (AC5) ------------------
if want i5; then
  # D4 carve (2026-10-bug-tests-edit-perms): the agents-sync references pair
  # re-opened by this ticket's matrix/incident text leaves the byte freeze —
  # a matrix row is prose, and delta-pinning prose across every future ticket
  # is a treadmill; the row anchors that matter stay grepped by c5/c6 and the
  # carve's integrity moves to source<->generated byte-equality (gate.sh t12,
  # agent-perms A5). Everything else under the freeze set — including
  # agents-sync's SKILL.md and its other references — stays byte-frozen.
  # The exclusion literal below is shared verbatim with gate.sh t12 and is
  # pinned by agent-perms A7(i) in both suites.
  moved=$( { git diff --name-only "$BASE" -- "${FREEZE_PATHS[@]}" 2>/dev/null || true;
             git ls-files --others --exclude-standard -- "${FREEZE_PATHS[@]}"; } \
           | sort -u \
           | grep -v -x -E -e '(\.rulesync|\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview)\.md' \
           || true )
  if [ -n "$moved" ]; then
    printf '%s\n' "$moved" >&2
    fail "i5: a byte-frozen surface (task 1.6 list) changed vs $BASE outside the tests-edit-perms D4 carve — gate, commands, fuser, the rest of agents-sync, models/gates, AGENTS.md and templates stay untouched (D8/D12); the carved permissions.md/pipeline-overview.md pair is guarded by t12/A5 pair-equality"
  fi
  ok "i5: freeze set byte-unchanged vs $BASE (worktree included) except the D4 agents-sync references carve — gate script, commands, fuser/models/gates pairs, AGENTS.md, rules, templates; carved pair guarded by t12 + agent-perms A5"
fi

# --- i6: regeneration contract (AC6) --------------------------------------------
if want i6; then
  # (c) pair-carry first: this is the component red before C01 — the ticket's
  # delta must be present in the generated mirrors, not just the sources
  # ("sources + generated committed together" pins the whole pair, and
  # hand-edited generated copies are caught below by the sync check).
  grep -qF 'metadata.openchamber.work' "$KICK_GEN" \
    || fail "i6: the generated kickoff mirror does not yet carry the authority contract (red before C01 — sources+generated must land together)"
  grep -qF 'doneAt' "$RC_GEN" || fail "i6: generated role-coord lacks the done-write contract"
  grep -qiF 'in-work' "$RC_GEN" || fail "i6: generated role-coord lacks the in-work mark wiring"
  grep -qiF 'in-work' "$BOARD_GEN" || fail "i6: the generated boards mirror lacks the citation line"
  for f in "$COORD_GEN" "$BCOORD_GEN"; do
    grep -qF "$SHELL_GET" "$f" && grep -qF "$SHELL_PATCH" "$f" \
      || fail "i6: generated $f does not carry the two scoped shell grants"
  done
  # (b) pair sync (offline): the mirrors equal their sources modulo rulesync's
  # deterministic re-serialization.
  for p in "$KICK_SRC|$KICK_GEN|skill" "$RC_SRC|$RC_GEN|skill" "$BOARD_SRC|$BOARD_GEN|skill" \
           "$COORD_SRC|$COORD_GEN|agent" "$BCOORD_SRC|$BCOORD_GEN|agent"; do
    IFS='|' read -r s g k <<<"$p"
    python3 "$TMP/pairsync.py" "$s" "$g" "$k" || fail "i6: source/generated pair out of sync for $s ($k) — regenerate, never hand-edit .opencode/"
  done
  # (a) the live generator gate, skip-with-warning where unresolvable.
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "i6: rulesync not resolvable here (PATH or npx cache) — generate-idempotence + --check skipped with warning (c7/t14 precedent)"
    ok "i6: pair-carry + pair-sync green offline; generator gate skipped with warning (via the ladder finding no rulesync)"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "i6: rulesync generate --check is not clean — committed generated surfaces are stale against the sources"; }
    timeout 180 $RS generate >/dev/null 2>&1 || fail "i6: first rulesync generate failed"
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "i6: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "i6: the second rulesync generate is not a no-op (sources and generated have drifted)"
    ok "i6: pair-carry + pair-sync + generate --check clean and the second generate is a no-op (via $RS)"
  fi
fi

printf 'PASS: coord-inwork surface checks (%d ok)\n' "$checks"
