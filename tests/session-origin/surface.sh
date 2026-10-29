#!/usr/bin/env bash
# session-origin contract suite (2026/2026-10-bug-session-origin-no-line, C02).
#
# Pins the resolution-leg text, the claim-once record, the FOURTH scoped shell
# grant, the regenerated mirrors and the D17 envelope-recipe fix (DECISIONS
# D10-D17, chunk C02.md). Sibling suites keep their regression duty through
# this ticket exactly the way kickoff-mints widened the cf-52 ladder: the
# legacy shell-allow pins (i4, t17, c2, m4) are sanctioned-FORMS ladders that
# accept the landed three-allow state AND the post-C02 four-allow state (never
# a fifth row, never off-anchor). The ABSOLUTE "four scoped allows exist NOW"
# presence duty lives ONLY in s4 below — so this suite is the designed-red
# carrier and every legacy suite stays zero-red through C01.
#
# Geometry, per arm (s4; the m4/i4/t17/c2 ladders mirror it one rung wider):
#   arm A (delta pending)  — current == the $BASE perms normalized (sanctioned
#     rows stripped) with the SHELL4 block spliced after the `opencode '*'
#     allow`: today's three-allow base + this ticket's 3-line addition is the
#     C02-review geometry (line twin +3 on a 3-allow base).
#   arm B (delta committed) — current == base AND the base rebuilds under the
#     SHELL4 strip/re-insert; the empty diff switches the line twin to the
#     absolute pinned-position presence pin (atpos4, twelve literal lines).
#   Regression gate: a base already carrying the origin allow admits SHELL4
#   only (a post-C02 state never regresses to three); the three-allow posture
#   is rejected at the C02 arm — made explicit as control C2, deterministic
#   today, together with fabricated-fifth-row (C3) and off-anchor (C5) rejects.
#
# NQ1 (grant-glob shape): the resource literal is pinned as the NO-SPACE form
# `bash scripts/session-origin.sh*`. The sibling's `... .sh *` style fits its
# arg-taking script; C01's call is zero-arg, and a `* `-suffixed whole-string
# matcher requires the space that the zero-arg command line never carries.
# The spaced form is asserted ABSENT (the literal pin below); the live
# whole-string matcher confirmation is a Review manual control per plan NQ1.
#
# Fourth antecedent (D1/D10): a launch whose board command never expanded is
# the state the old definition left undefined — this suite pins the C02.md 2.1
# wording family (`no board command` leg-2 passage + `session resolver
# unavailable` terminal token), not the round-1 docs-only literal: D10 retired
# the "no-line ⇒ UNRESOLVED(no board-command expansion) ⇒ raw-id by rule"
# resolution when the user chose the script leg.
#
# D17 fold-in (s7): pipeline-kickoff's read-merge-write recipe must state the
# {"data": ...} response envelope explicitly — an unwrap omission let a
# top-level `.metadata` read silently return nothing, defeating the idempotent
# skip and wiping openchamber.kind on the PATCH-whole-replace. Placement
# constraint (measured 2026-10-26): the sentence rides bullet 35 BEFORE
# `metadata.openchamber.work` and stays under ~250 chars, or cf-52's i1
# windows (work-key 800 with min span 710; rmw-why 700 with min span 441)
# genuinely move — a re-pin decision, not a silent widening; the sim run
# proves the honest sentence fits unmodified.
#
# AC trace: s1[C02 AC1 both-legs + bans + reason token + curl-count]
# s2[AC2 claim-once + consumer-bullet byte-equality] s3[AC3 t19/c12/i3 carry
# inventory, natively re-pinned] s4[AC4 four-allow splice + fmshape + literal
# lines on all four coord files] s5[AC5/AC6 containment sentence +
# permissions.md cell] s6[AC7 pair-sync + commands freeze + five-surface
# parity ladder, both trees] s7[D17 envelope recipe + kickoff carries survive].
#
# Red posture (test phase, before C01+C02 dev): s1 reds first on the missing
# leg-2 passage, s2 on the absent session_origin record, s4 on the absent
# fourth grant, s5 on the unmoved containment/cell text, s6 on b6's absent
# script side, s7 on the missing envelope sentence — every red names its
# missing C02 (or C01 script) artifact. s3 + the byte-equality/freeze/regen
# components are HOLD guards: green now, red if C02 escapes scope.
#
# cf-58 merge re-pin (2026-10-27): the standalone-agent merge lands the
# sanctioned git block + the agent-dev → agent-dev-local roster rename on the
# coord family. s4's mechanism re-pins accordingly: the arm comparisons run
# on git-block-stripped core projections with a whole-block tail check
# (splice4), the line twin admits the fourteen-row git block as the only
# sanctioned continuation (atpos4), the shape check admits exactly that
# block as the only git surface and pins the alias's -local roster (shape4),
# and the soundness controls build their no-allow base from the live
# skeleton. s4(b)'s diff-shape arm CANNOT express a merge delta: it is
# designed-red in the merge window under BASE=pre-merge-HEAD and green again
# at the merge commit (empty diff → arm-B atpos posture), provable
# pre-commit via CHUNK_BASE=<merge snapshot>. s2's HEAD-relative byte pin
# greens again at the same commit for the same reason.
# The kickoff naming landing (2026-10-27, bug-coord-opencode-perms) inherits
# the same discipline: splice4 strips the execute/opencode_* naming rows from
# the core projections (whole-and-order tail check, the four-allow duty keeps
# its teeth), so the parsed arms go green in-window; s4(b) stays designed-red
# until the landing commit flips the files to the empty-diff arm-B posture.
# The absolute naming duty lives in tests/agent-perms/surface.sh A12.
#
# cf-85 RE-PIN (2026-10-29, cf-85-refactor-wekan-slug-session-link): the board
# write-back becomes ONE custom field — `slug` carrying the combined
# `[<slug>](<session link>)` link, raw session id in the link half when the
# origin says UNRESOLVED (DECISIONS D11) — so this suite's cf-85 legs are:
#   s3's new 'raw session id'+'link half' window — DESIGNED RED against the
#     pre-flip text (the slot list still names the retired session field),
#     green at the flip commit;
#   s2's b2 write-back byte-pin — the block cf-85 legitimately rewrites, so it
#     is byte-equal until the flip edits it, red ONLY for a CHUNK_BASE=<pre-
#     chunk> run inside the edit window, and green again at the flip commit
#     (same in-window red as s6's command freeze, which the flip's command
#     edits cause and which greens the same way);
#   s2's b1/b3 byte-pins and every s3 window/carry string — HOLD: the flip
#     must leave the claim-comment bullet, the research step-7 sentence, the
#     resolution-leg text and the `slug`/`session`/`custom field` substrings
#     intact, so a red there names an out-of-scope edit.
#
# Usage (harness convention from tests/coord-inwork/surface.sh):
#   bash tests/session-origin/surface.sh             # s1..s7
#   bash tests/session-origin/surface.sh s4          # subset (designed-red inventory runs per check)
#   CHUNK_BASE=<pre-chunk commit> bash tests/session-origin/surface.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

BOARD_SRC=".rulesync/skills/boards/SKILL.md"
BOARD_GEN=".opencode/skills/boards/SKILL.md"
KICK_SRC=".rulesync/skills/pipeline-kickoff/SKILL.md"
KICK_GEN=".opencode/skills/pipeline-kickoff/SKILL.md"
RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
COORD_SRC=".rulesync/subagents/agent-coord.md"
COORD_GEN=".opencode/agents/agent-coord.md"
BCOORD_SRC=".rulesync/subagents/agent-board-coord.md"
BCOORD_GEN=".opencode/agents/agent-board-coord.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"
POV_SRC=".rulesync/skills/agents-sync/references/pipeline-overview.md"
POV_GEN=".opencode/skills/agents-sync/references/pipeline-overview.md"
SCRIPT="scripts/session-origin.sh"
CMD_FILES=(.rulesync/commands/pipeline-boards.md .opencode/commands/pipeline-boards.md
           .rulesync/commands/pipeline-boards-hourly.md .opencode/commands/pipeline-boards-hourly.md)

ORIGIN_RES='bash scripts/session-origin.sh*'
# Historical arm-A reference: the sibling's landed commit (the three-allow
# base this ticket's delta rode; the pre-landing refs are historical per the
# tests-edit-perms discipline, documented in STATE execution_notes). Since
# the cf-58 merge re-pin (2026-10-27) the s4 soundness controls derive their
# no-allow base from the live skeleton (synth strip-shell) instead, so ARM_A
# is kept for the record only.
ARM_A="c6689202c"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/session-origin-surface-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["s$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^s[1-7]$ ]] || fail "unknown check id '$a' (expected s1..s7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -------------------------------------------------------------
cat >"$TMP/win.py" <<'PY'
# Co-location window (win.py convention of the sibling suites): needles must
# read as ONE passage; --ci folds case for prose needles so the pins survive
# dev's register without pinning sentences.
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci: argv = argv[1:]
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
        if i < 0: break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'missing needle: {n}'); sys.exit(1)
pts.sort()
need = len(set(needles))
cnt, have, best, left = {}, 0, None, 0
for right, (p, n) in enumerate(pts):
    cnt[n] = cnt.get(n, 0) + 1
    if cnt[n] == 1: have += 1
    while have == need:
        s = p - pts[left][0]
        if best is None or s < best: best = s
        cnt[pts[left][1]] -= 1
        if cnt[pts[left][1]] == 0: have -= 1
        left += 1
if best is None or best > span:
    print(f'no window of {span} chars covers all needles (min span {best})'); sys.exit(1)
PY

cat >"$TMP/sectwin.py" <<'PY'
# Window scoped to one heading's section (coord-inwork sectwin.py convention).
import re, sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci: argv = argv[1:]
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
        if i < 0: break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'needle "{n}" not in section "{title}"'); sys.exit(1)
pts.sort()
need = len(set(needles))
cnt, have, best, left = {}, 0, None, 0
for right, (p, n) in enumerate(pts):
    cnt[n] = cnt.get(n, 0) + 1
    if cnt[n] == 1: have += 1
    while have == need:
        s = p - pts[right][0]
        if best is None or s < best: best = s
        cnt[pts[left][1]] -= 1
        if cnt[pts[left][1]] == 0: have -= 1
        left += 1
if best is None or best > span:
    print(f'no window of {span} chars covers all needles in section "{title}" (min span {best})'); sys.exit(1)
PY

cat >"$TMP/sectgrep.py" <<'PY'
# Row/section text pins (kickoff-branch sectgrep.py convention).
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

cat >"$TMP/neg12.py" <<'PY'
# D12 models/custom-field pairing must be negated (rulesync-surface.sh c12 copy).
import re, sys
pat = re.compile(r'models.*custom.?field', re.I)
neg = re.compile(r"\b(no|not|never|dropped|doesn'?t|does not|absent|omits?)\b", re.I)
bad = []
for i, line in enumerate(open(sys.argv[1]), 1):
    if pat.search(line) and not neg.search(line):
        bad.append(f"line {i}: {line.strip()}")
if bad:
    print(" | ".join(bad)); sys.exit(1)
PY

cat >"$TMP/pairsync.py" <<'PY'
# Source/generated pair sync WITHOUT running the generator (coord-inwork
# i6 convention): bodies equal once frontmatter and blank space are stripped;
# meaningful frontmatter fields equal once parsed.
import re, sys, yaml
src, gen, kind = sys.argv[1], sys.argv[2], sys.argv[3]
def parts(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{path}: no parsable frontmatter"
    return yaml.safe_load(m.group(1)), m.group(2).strip("\n") + "\n"
f1, b1 = parts(src); f2, b2 = parts(gen)
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

# s4 mechanism: the SHELL4-ONLY OR-form (this suite owns the absolute presence
# duty; the ladders one rung down live in the sibling suites).
cat >"$TMP/splice4.py" <<'PY'
# Arm A — current == the $BASE perms normalized (SHELL4 rows stripped) with
# exactly the four scoped allows spliced after the `opencode '*' allow`.
# Arm B — current == base AND the base is idempotent under the SHELL4
# strip/re-insert. The landed three-allow posture FAILS both arms here —
# rejecting it at the C02 arm is this ticket's designed duty (control C2).
import re, sys, yaml
base_path, cur_path, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
SHELL4 = [
    {"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"},
    {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"},
    {"action": "shell", "resource": "bash scripts/kickoff-mint-branch.sh *", "effect": "allow"},
    {"action": "shell", "resource": "bash scripts/session-origin.sh*", "effect": "allow"},
]
# Date-grant RE-PIN (2026-10-27): the in-work mark embeds $(date +%s%3N) in
# the patch payload; the shell matcher checks the substitution's `date`
# subcommand against the agent's own list, so the family carries a `date *`
# allow. Same discipline as the git block and the naming rows: both arms
# strip it from the core projection (the four-allow duty keeps its teeth)
# and a separate check admits it at most once, whole.
DATE = {"action": "shell", "resource": "date *", "effect": "allow"}
# cf-58 MERGE RE-PIN (2026-10-27): the merged coord family additionally
# carries the sanctioned git block after the SHELL4 block (pinned absolutely
# across all twelve family files by the cfpins contract in
# tests/coord-inwork/surface.sh i4 and tests/agent-board-coord/gate.sh t17).
# Both arms compare core projections (git block stripped); a separate check
# admits the block only whole and in order. The four-allow duty keeps teeth.
GITBLOCK = [
    {"action": "shell", "resource": "git status *", "effect": "allow"},
    {"action": "shell", "resource": "git log *", "effect": "allow"},
    {"action": "shell", "resource": "git diff *", "effect": "allow"},
    {"action": "shell", "resource": "git show *", "effect": "allow"},
    {"action": "shell", "resource": "git branch *", "effect": "allow"},
    {"action": "shell", "resource": "git merge-base *", "effect": "allow"},
    {"action": "shell", "resource": "git rev-parse *", "effect": "allow"},
    {"action": "shell", "resource": "git ls-files *", "effect": "allow"},
    {"action": "shell", "resource": "git add *", "effect": "allow"},
    {"action": "shell", "resource": "git commit *", "effect": "allow"},
    {"action": "shell", "resource": "git checkout *", "effect": "allow"},
    {"action": "shell", "resource": "git switch *", "effect": "allow"},
    {"action": "shell", "resource": "git merge main*", "effect": "allow"},
    {"action": "shell", "resource": "git push*", "effect": "deny"},
]
# Naming RE-PIN (2026-10-27, bug-coord-opencode-perms): the coord family now
# additionally carries the kickoff naming surface — `execute` (the Code Mode
# transport for tools.opencode.*) + four opencode_* per-tool allows, MCP-style
# <server>_<tool>. Same discipline as the git block: both arms strip these rows
# from the core projection (the four-allow duty keeps its teeth) and a separate
# check admits the four per-tool rows only whole and in order. The absolute
# naming duty lives in tests/agent-perms/surface.sh A12, never here.
EXEC = {"action": "execute", "resource": "*", "effect": "allow"}
NAMING = [
    {"action": "opencode_worktree_create", "resource": "*", "effect": "allow"},
    {"action": "opencode_worktree_list", "resource": "*", "effect": "allow"},
    {"action": "opencode_session_move", "resource": "*", "effect": "allow"},
    {"action": "opencode_session_rename", "resource": "*", "effect": "allow"},
]
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
def splice(seq):
    anchor = [i for i, p in enumerate(seq)
              if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
    if len(anchor) != 1:
        return None, len(anchor)
    i = anchor[0]
    return seq[:i + 1] + SHELL4 + seq[i + 1:], i
b, c = perms(base_path), perms(cur_path)
if b[0] != {"action": "*", "resource": "*", "effect": "deny"}:
    print("deny-baseline first rule changed at base — the suite's premise broke"); sys.exit(1)
b_core = [p for p in b if p not in GITBLOCK and p not in NAMING and p != EXEC and p != DATE]
c_core = [p for p in c if p not in GITBLOCK and p not in NAMING and p != EXEC and p != DATE]
want, i = splice([p for p in b_core if p not in SHELL4])
if want is None:
    print(f"base must carry exactly one opencode '*' allow, found {i}"); sys.exit(1)
if c_core == want:
    pass  # arm A — the +3-on-a-three-allow-base geometry a C02 review run sees
else:
    if not any(p.get("resource") == SHELL4[3]["resource"] for p in c_core):
        print(f"the fourth scoped allow '{SHELL4[3]['resource']}' is MISSING (red before C02 dev phase — the session-origin resolver grant has not landed; the landed three-allow posture satisfies the re-pinned sibling ladders, not this contract)"); sys.exit(1)
    if c_core == b_core:  # arm B candidate — committed base
        stripped = list(b_core)
        for s in SHELL4:
            if s not in stripped:
                print("arm B: current == base but the four-allow delta is absent at base — the contract never landed (the three-allow state is rejected at the C02 arm)"); sys.exit(1)
            stripped.remove(s)
        again, _ = splice(stripped)
        if again is None or b_core != again:
            print("arm B: the committed base does not idempotently rebuild as the four scoped allows at the pinned splice position — unsanctioned drift"); sys.exit(1)
    else:
        extra = [p for p in c_core if p not in want]
        missing = [p for p in want if p not in c_core]
        print(f"frontmatter delta is not exactly the four scoped allows in either arm: extra={extra} missing={missing}"); sys.exit(1)
gb = [p for p in c if p in GITBLOCK]
if gb and gb != GITBLOCK:
    print("git-block rows are present but are not exactly the sanctioned fourteen rows in order — unsanctioned git surface"); sys.exit(1)
nb = [p for p in c if p in NAMING]
if nb and nb != NAMING:
    print("kickoff naming rows are present but are not exactly the sanctioned four in order — unsanctioned naming surface"); sys.exit(1)
dt = [p for p in c if p == DATE]
if dt and dt != [DATE]:
    print("the date allow is present more than once or with a different effect — unsanctioned date surface"); sys.exit(1)
shells = [p.get("resource") for p in c_core if p.get("action") == "shell"]
if shells != [s["resource"] for s in SHELL4]:
    print(f"shell resources are {shells}, want exactly the four scoped allows in order (the only other sanctioned shell surfaces are the cf-58 git block and the date allow, both checked whole above)"); sys.exit(1)
if c[0] != b[0]:
    print("deny-baseline line drifted"); sys.exit(1)
if need_dev_boards and not any(p.get("action") == "dev-boards*" and p.get("resource") == "*"
                               and p.get("effect") == "allow" for p in c):
    print("dev-boards* allow missing from a board-coord file"); sys.exit(1)
PY

cat >"$TMP/atpos4.py" <<'PY'
# Arm-B line twin: the FIFTEEN literal allow lines (two session triples, the
# mint triple, the session-origin triple, the date triple — 2026-10-27
# date-grant re-pin) directly after the opencode '*' allow anchor at the
# anchor's own indent; the only sanctioned continuation
# is the cf-58 git block (comment lines + the fourteen git rows, whole and
# in order) — any other shell row is an unsanctioned grant.
import re, sys
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
lines = [l.rstrip(" \t\r") for l in m.group(1).split("\n") if l.strip()]
ANCHOR = re.compile(r"^(\s*)- action: opencode$")
WANT = [('resource: opencode api get /api/session*', 'effect: allow'),
        ('resource: opencode api patch /api/session/*', 'effect: allow'),
        ('resource: bash scripts/kickoff-mint-branch.sh *', 'effect: allow'),
        ('resource: bash scripts/session-origin.sh*', 'effect: allow'),
        ('resource: date *', 'effect: allow')]
hits = []
for i, l in enumerate(lines):
    am = ANCHOR.match(l)
    if am and lines[i + 1:i + 3] == [f"{am.group(1)}  resource: '*'", f"{am.group(1)}  effect: allow"]:
        hits.append((i, am.group(1)))
if len(hits) != 1:
    print(f"want exactly one '- action: opencode' + resource '*' + effect allow rule, found {len(hits)}"); sys.exit(1)
ind = hits[0][1]
want_lines = [x for rule in WANT for x in
              (f"{ind}- action: shell", f"{ind}  {rule[0]}", f"{ind}  {rule[1]}")]
at = hits[0][0] + 3
if lines[at:at + 15] != want_lines:
    print("the fifteen literal shell allow lines (two session triples + mint triple + session-origin triple + date triple) do not follow the "
          f"opencode '*' allow at the pinned position (want under indent '{ind}', got {lines[at:at + 15]})"); sys.exit(1)
# cf-58 merge re-pin: after the sanctioned fifteen, the only permitted
# continuation is comment lines plus the sanctioned fourteen-row git block
# (whole, in order, ending the shell surface); any other shell row is an
# unsanctioned grant.
GB = [(f"{ind}- action: shell", f"{ind}  resource: {r}", f"{ind}  effect: {e}")
      for r, e in [("git status *", "allow"), ("git log *", "allow"), ("git diff *", "allow"),
                   ("git show *", "allow"), ("git branch *", "allow"), ("git merge-base *", "allow"),
                   ("git rev-parse *", "allow"), ("git ls-files *", "allow"), ("git add *", "allow"),
                   ("git commit *", "allow"), ("git checkout *", "allow"), ("git switch *", "allow"),
                   ("git merge main*", "allow"), ("git push*", "deny")]]
k = at + 15
gi = saw = 0
while k < len(lines):
    if lines[k].lstrip().startswith("#"):
        k += 1
        continue
    if lines[k].strip() == "- action: shell":
        saw = 1
        if gi >= len(GB) or lines[k:k + 3] != list(GB[gi]):
            print(f"a shell row continues the block after the sanctioned twelve and is not the next sanctioned git-block row (want {GB[gi] if gi < len(GB) else 'nothing'}, got {lines[k:k + 3]}) — unsanctioned shell grant"); sys.exit(1)
        gi += 1
        k += 3
        continue
    break
if saw and gi != len(GB):
    print(f"the git block continues the shell surface but is truncated or reordered (matched {gi} of {len(GB)} sanctioned rows)"); sys.exit(1)
PY

cat >"$TMP/synth.py" <<'PY'
# Clone a coord file with an origin-grant mutation for the s4 controls
# (kickoff-branch synth.py convention: literal-line triples, item indent from
# the resource line's indent, so both nesting shapes survive).
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
ORIGIN = "bash scripts/session-origin.sh*"
MINT = "bash scripts/kickoff-mint-branch.sh *"
BAD = "git -C * checkout -b *"
# cf-58 merge re-pin (2026-10-27): strip-shell removes every sanctioned
# shell triple (the SHELL4 allows + the fourteen-row git block) to build the
# no-allow skeleton the form4 control splices into; form4 splices the
# canonical four-allow form after the opencode '*' allow anchor on ANY base,
# so those modes must not require the cf-52 rows up front.
SANCTIONED = {"opencode api get /api/session*", "opencode api patch /api/session/*", MINT, ORIGIN, "date *",
              "git status *", "git log *", "git diff *", "git show *", "git branch *",
              "git merge-base *", "git rev-parse *", "git ls-files *", "git add *",
              "git commit *", "git checkout *", "git switch *", "git merge main*", "git push*"}
i_o = find(ORIGIN); i_m = find(MINT); i_p = find("opencode api patch /api/session/*")
if mode not in ("strip-shell", "form4"):
    assert i_p >= 0, "fixture source must carry the cf-52 two-allow posture"
item_ind = lines[i_p][: len(lines[i_p]) - len(lines[i_p].lstrip())][:-2] if i_p >= 0 else None
if mode == "add-origin":
    out = lines if i_o >= 0 else (lines[: i_m + 2] + block(item_ind, ORIGIN) + lines[i_m + 2:])
elif mode == "strip-origin":
    out = lines if i_o < 0 else lines[: i_o - 1] + lines[i_o + 2:]
elif mode == "off-anchor":
    if i_o >= 0:
        lines = lines[: i_o - 1] + lines[i_o + 2:]; i_m = find(MINT)
    j = next(k for k, l in enumerate(lines) if l.strip() == "- action: opencode")
    out = lines[:j] + block(item_ind, ORIGIN) + lines[j:]
elif mode == "fifth-row":
    assert i_o >= 0, "add a fifth row only to a four-allow fixture"
    out = lines[: i_o + 2] + block(item_ind, BAD) + lines[i_o + 2:]
elif mode == "strip-shell":
    out, k = [], 0
    while k < len(lines):
        if (lines[k].strip() == "- action: shell" and k + 2 < len(lines)
                and lines[k + 1].strip().startswith("resource: ")
                and lines[k + 1].strip()[len("resource: "):] in SANCTIONED
                and lines[k + 2].strip().startswith("effect: ")):
            k += 3
        else:
            out.append(lines[k]); k += 1
elif mode == "form4":
    j = next(k for k, l in enumerate(lines) if l.strip() == "- action: opencode")
    # items sit at the anchor's own indent (resource lines two deeper) — the
    # item_ind convention of the other modes above.
    ind = lines[j][: len(lines[j]) - len(lines[j].lstrip())]
    rows = ["opencode api get /api/session*", "opencode api patch /api/session/*", MINT, ORIGIN]
    out = lines[: j + 3] + [x for r in rows for x in block(ind, r)] + lines[j + 3:]
else:
    print(f"unknown synth mode {mode}"); sys.exit(2)
open(dst, "w").write("\n".join(out))
PY

cat >"$TMP/shape4.py" <<'PY'
# Parsed shape contract on both trees (m4-shape.py convention, widened to the
# two sanctioned bash grants): source == generated including order
# (last-match-wins makes order load-bearing), exactly the mint + origin pair
# as bash grants, the sanctioned cf-58 git block as the only git surface
# (raw git -C still rejected), question allow kept, and the variant's MCP
# posture.
import re, sys, yaml
src, gen, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
ORIGIN = "bash scripts/session-origin.sh*"
ps, pg = perms(src), perms(gen)
errs = []
if ps != pg:
    errs.append(f"parsed permission lists differ between {src} and {gen} (order included) — regenerate, never hand-edit the mirror")
# cf-58 merge re-pin: the blanket git ban yields to the sanctioned git
# block (fourteen rows, whole and in order — pinned absolutely across the
# family by cfpins i4/t17); the raw 'git -C' mechanism stays rejected.
GB = [("git status *", "allow"), ("git log *", "allow"), ("git diff *", "allow"),
      ("git show *", "allow"), ("git branch *", "allow"), ("git merge-base *", "allow"),
      ("git rev-parse *", "allow"), ("git ls-files *", "allow"), ("git add *", "allow"),
      ("git commit *", "allow"), ("git checkout *", "allow"), ("git switch *", "allow"),
      ("git merge main*", "allow"), ("git push*", "deny")]
gitrows = [(p.get("resource"), p.get("effect")) for p in ps
           if p.get("action") == "shell" and str(p.get("resource", "")).startswith("git ")]
if gitrows and gitrows != GB:
    errs.append(f"git shell grants are {gitrows}, want exactly the sanctioned cf-58 git block in order (or none)")
for p in ps:
    if p.get("action") == "shell" and "git -C" in str(p.get("resource", "")):
        errs.append("a raw git -C shell grant exists (scope escape — the plan's rejected mechanism)")
bashish = [p.get("resource") for p in ps if p.get("action") == "shell" and str(p.get("resource", "")).startswith("bash ")]
if bashish != ["bash scripts/kickoff-mint-branch.sh *", ORIGIN]:
    errs.append(f"bash shell grants are {bashish}, want exactly the mint + session-origin pair in splice order")
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in ps):
    errs.append("question allow lost (repo hard rule)")
subs = sorted(p.get("resource") for p in ps if p.get("action") == "subagent" and p.get("effect") == "allow")
# cf-58 merge re-pin: the tested files are the unsuffixed aliases, which are
# byte-identical -local twins by construction (cf-58 DECISIONS Q2/R2) — the
# dev slot is agent-dev-local; the variant rosters themselves are pinned by
# the cfpins family contract.
if subs != sorted(["agent-plan", "agent-test", "agent-dev-local", "agent-review", "agent-research"]):
    errs.append(f"subagent allows are {subs}")
edits = sorted(p.get("resource") for p in ps if p.get("action") == "edit")
if edits != sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"]):
    errs.append(f"edit allows are {edits}")
if need_dev_boards:
    db = [i for i, p in enumerate(ps) if p.get("action") == "dev-boards*"]
    deny_at = next((i for i, p in enumerate(ps) if p.get("action") == "*" and p.get("effect") == "deny"), None)
    if len(db) != 1 or not (deny_at is not None and db[0] > deny_at):
        errs.append("the single narrow dev-boards* allow after the deny-all is gone")
    if any(p.get("action") == "dev*" for p in ps):
        errs.append("broad dev* allow appeared (D21)")
else:
    if any(p.get("action") in ("dev*", "dev_boards*", "dev-boards*") for p in ps):
        errs.append("a board MCP allow appeared on the plain coord")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY

# --- s1: boards pair — two-leg resolution definition (C02 AC1) -------------------
if want s1; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "s1: $f missing (harness fault)"
    # leg 2 named verbatim in one passage (C02.md 2.1 wording duty; the exact
    # command string is what C01's script accepts):
    python3 "$TMP/win.py" --ci "$f" 700 'no board command' 'bash scripts/session-origin.sh' 'Session origin:' \
      || fail "s1: $f does not define the leg-2 antecedent (a launch with no board command expansion resolves via \`bash scripts/session-origin.sh\` as ONE passage — red before C02 dev phase; the round-1 'no-line ⇒ raw-id' literal was retired by D10's script leg)"
    # ban posture survives verbatim-or-faithful (2.1): the functional form is
    # the re-derivation ban AND the named script in one passage — keeping the
    # literal sentence while naming block-or-script as the only channels also
    # passes this window.
    grep -qF 'Never a remembered, guessed or historically-observed host' "$f" \
      || fail "s1: $f lost the host-ban sentence VERBATIM (2.1: pinned byte-exact)"
    python3 "$TMP/win.py" --ci "$f" 700 're-derived' 'session-origin.sh' \
      || fail "s1: $f does not scope the free-hand ban to block-or-script resolution (the derivation-ban passage must name the script leg — verbatim-kept or faithfully amended wording both pass; red before C02 dev phase)"
    grep -qF 'session resolver unavailable' "$f" \
      || fail "s1: $f lacks the terminal reason token 'session resolver unavailable' (2.1: the exact literal for a script channel that cannot run — red before C02 dev phase)"
    ncurl=$(grep -o 'curl' "$f" | wc -l)
    [ "$ncurl" -eq 1 ] || fail "s1: $f mentions curl $ncurl times — the boards skill must keep EXACTLY the pre-existing expansion mention (AC1: probing lives in the block and the script, never restated here)"
  done
  ok "s1: boards pair defines leg 2 with the exact command string, keeps both ban sentences, carries the resolver-unavailable token, single curl mention (C02 AC1)"
fi

# --- s2: claim-once record + minimal contact (C02 AC2) ---------------------------
extract_block() { # file start-regex end-regex outfile — sed-range on purpose: the
  # consumer bullets are the D23-r2 wording byte-frozen against the chunk base
  sed -n "/$2/,/$3/p" "$1" > "$4"
}
if want s2; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "s2: $f missing (harness fault)"
    python3 "$TMP/win.py" --ci "$f" 700 'session_origin' 'claim' 're-use' \
      || fail "s2: $f does not state the claim-once record (STATE.json kickoff.session_origin written at claim, re-used by every later leg — OQ2/D14; red before C02 dev phase)"
    python3 "$TMP/win.py" --ci "$f" 400 'session_origin' 'kickoff' 'card' 'slug' \
      || fail "s2: $f does not extend the kickoff-carries sentence with session_origin (2.3: card + slug + session_origin; red before C02 dev phase)"
  done
  # the three consumer bullets resolve THROUGH the amended definition and must
  # not be touched (AC2 byte-unchanged vs the chunk base):
  # cf-85 RE-PIN (2026-10-29): b1 (claim-comment bullet) and b3 (research
  # step-7 session link) stay byte-frozen for cf-85 too — they resolve through
  # the amended definition, they are not the definition. b2 (write-back step 2)
  # is the slot cf-85 legitimately rewrites, so that leg is designed-red only
  # inside the flip's edit window (CHUNK_BASE=<pre-chunk commit> with the
  # edited sources in the worktree) and green again at the flip commit, where
  # $BASE already carries the combined-value block — the cf-50 posture that
  # also reddens s6's command freeze in-window.
  # b1 is extracted as ONE bullet rather than a sed range: the bullet ends on
  # the same words the old end anchor looked for, and sed searches a range's
  # end pattern only in lines AFTER the start line, so the old range ran to the
  # next such line far below and byte-pinned the Post-plan write-back, the
  # batched-question sentence and the launch prompt as well — all three of
  # which cf-85 legitimately edits (surface map 1g/1h/1i). Same duty (the
  # claim comment stays byte-unchanged), no longer pinning the text below it.
  extract_bullet() { # file needle outfile — the bullet naming the needle plus
    # its continuation lines, stopping at the next bullet or heading
    awk -v n="$2" '
      !p && index($0, n) { p = 1; print; next }
      p && (/^- / || /^## /) { exit }
      p { print }' "$1" > "$3"
  }
  n=0
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    n=$((n + 1))
    git show "$BASE:$f" >"$TMP/s2-base-$n.md" 2>/dev/null || fail "s2: $f not readable at $BASE"
    extract_bullet "$TMP/s2-base-$n.md" 'claiming the card:' "$TMP/s2-b1"
    extract_bullet "$f"                   'claiming the card:' "$TMP/s2-c1"
    [ -s "$TMP/s2-b1" ] || fail "s2: the claim-comment bullet is not found at $BASE in $f (its wording moved — harness/base fault, report it)"
    cmp -s "$TMP/s2-b1" "$TMP/s2-c1" || fail "s2: $f Pickup consumer bullet (session line … plan folder path) moved vs $BASE — AC2 pins it byte-unchanged (minimal contact: it resolves through the amended definition)"
    extract_block "$TMP/s2-base-$n.md" '`set_card_custom_field` (upsert)' 'constants consistency check\.' "$TMP/s2-b2"
    extract_block "$f"            '`set_card_custom_field` (upsert)' 'constants consistency check\.' "$TMP/s2-c2"
    [ -s "$TMP/s2-b2" ] || fail "s2: write-back step 2 block not found at $BASE in $f (anchor moved — harness/base fault, report it)"
    [ -s "$TMP/s2-c2" ] || fail "s2: write-back step 2 block not found in $f — the '(upsert)' opener or the 'constants consistency check.' close moved (cf-85 AC2 keeps both: the single upsert still closes on the consistency check)"
    cmp -s "$TMP/s2-b2" "$TMP/s2-c2" || fail "s2: $f write-back step 2 (the slug field's combined-value slot) differs from $BASE — designed-red ONLY inside cf-85's edit window; at the flip commit the block matches $BASE again, and byte-unchanged anywhere else means the flip did not land"
    extract_block "$TMP/s2-base-$n.md" 'add_comment` on the card: the research session link' 'from RESEARCH.md' "$TMP/s2-b3"
    extract_block "$f"            'add_comment` on the card: the research session link' 'from RESEARCH.md' "$TMP/s2-c3"
    cmp -s "$TMP/s2-b3" "$TMP/s2-c3" || fail "s2: $f research-only step 7 session-link sentence moved vs $BASE — AC2 byte-pin"
  done
  ok "s2: claim-once record + kickoff extension present; the three consumer bullets byte-unchanged vs $BASE (C02 AC2)"
fi

# --- s3: carry inventory re-pinned natively (C02 AC3: t19/c12/i3) ------------------
if want s3; then
  for f in "$BOARD_SRC" "$BOARD_GEN"; do
    [ -f "$f" ] || fail "s3: $f missing (harness fault)"
    for s in 'SESSION_URL_BASE' 'Session origin:' 'VSCODE_PROXY_URI' 'UNRESOLVED' \
             '$(SESSION_URL_BASE)/?session=<sessionID>' 'Never a raw session id (D13)' \
             'slug' 'session' 'custom field' 'cf-<card' 'session_rename' '?session='; do
      grep -qF "$s" "$f" || fail "s3: $f lost carry string '$s' (t19/c12/i3 sets re-pinned natively — C02 wording must not drop a sibling needle)"
    done
    python3 "$TMP/win.py" --ci "$f" 900 'UNRESOLVED' 'absent' 'shape' 'answered' \
      || fail "s3: $f no longer defines UNRESOLVED via the three expansion-time branches in ONE passage (t19 window — the leg-2 text must leave this passage intact, C02 2.2)"
    python3 "$TMP/win.py" --ci "$f" 400 'raw session id' 'proceed' \
      || fail "s3: $f lost the D23-r2 fallback posture window (t19)"
    python3 "$TMP/win.py" --ci "$f" 600 'raw session id' 'RESULT' \
      || fail "s3: $f lost the fallback/RESULT binding window (t19)"
    # cf-85 AC5: the UNRESOLVED bullet's slot list re-points from the retired
    # `session` custom-field value to the `slug` field's LINK HALF. The raw-id
    # posture itself is untouched (the two windows above are its older legs
    # and stay green), so this pairing is the leg that reddens until the flip
    # lands — DECISIONS D11 keeps it the single shape, no bare-slug fork.
    python3 "$TMP/win.py" --ci "$f" 400 'raw session id' 'link half' \
      || fail "s3[cf-85 AC5]: $f's UNRESOLVED bullet does not name the slug field's link half among the raw-id slots (red before the flip — the slot list still points at the retired session field)"
    python3 "$TMP/win.py" --ci "$f" 200 'never' 're-guess' \
      || fail "s3: $f lost the never-silently-re-guess window (t19)"
    python3 "$TMP/win.py" --ci "$f" 400 'consistency' 'mismatch' \
      || fail "s3: $f lost the consistency-vs-mismatch window (t19; 2.3 extends this bullet, never scatters it)"
    grep -qiE 'no run tag|run tag[^.]{0,60}retir|retir[^.]{0,60}run tag|omits/nulls' "$f" \
      || fail "s3: $f lost the run-tag retirement phrase (c12 regex)"
    python3 "$TMP/neg12.py" "$f" || fail "s3: $f pairs 'models' with 'custom field' without negating it (c12 neg12)"
    if grep -qF 'openchamber--dev-thehackmeister-coder' "$f"; then
      fail "s3: $f re-introduces the proven-dead host literal (c12/t19/i3: absence is correctness)"
    fi
    if grep -qF 'SESSION_URL_BASE = https://' "$f"; then
      fail "s3: $f hard-codes SESSION_URL_BASE again (t19 negative)"
    fi
    # i3: boards stays citation-only on the work-state contract — key-path
    # negatives included, C02 must not leak pipeline-kickoff's paths here:
    for bad in 'metadata.openchamber' 'openchamber.work'; do
      if grep -qF "$bad" "$f"; then
        fail "s3: $f leaks the work-state key path '$bad' — single-sourced in pipeline-kickoff (i3 negative must stay green; D17's envelope sentence lives THERE, not here)"
      fi
    done
    python3 "$TMP/sectwin.py" --ci "$f" 500 'Card-driven kickoff' 'in-work' 'pipeline-kickoff' \
      || fail "s3: $f Card-driven kickoff lost its in-work citation passage (i3 section window)"
    rl_base=$(git show "$BASE:$f" | grep -F 'RESEARCH_LABEL = Research' || true)
    rl_cur=$(grep -F 'RESEARCH_LABEL = Research' "$f" || true)
    [ -n "$rl_cur" ] || fail "s3: $f lost the RESEARCH_LABEL line (t19)"
    [ "$rl_base" = "$rl_cur" ] || fail "s3: $f RESEARCH_LABEL line changed vs $BASE — every non-SESSION_URL_BASE constant stays copy-verbatim (t19)"
  done
  neg=$(grep -rn -e 'in-work:' -e 'done:' .rulesync/skills .opencode/skills 2>/dev/null || true)
  [ -z "$neg" ] || fail "s3: withdrawn title-convention strings under the skill trees (i1 negative, tree-wide): $neg"
  ok "s3: full t19/c12/i3 carry inventory holds in both boards trees (strings, windows, section window, key-path + dead-literal + title negatives, RESEARCH_LABEL byte) + the cf-85 AC5 link-half slot re-point"
fi

# --- s4: the FOURTH scoped allow — absolute presence duty (C02 AC4) ----------------
if want s4; then
  # cf-58 MERGE RE-PIN (2026-10-27): mirror of the kickoff-branch m4 re-pin —
  # the no-allow base is the live skeleton (synth strip-shell), the committed
  # posture is exercised as arm-B idempotence at the live file itself, and
  # splice4/atpos4 admit the sanctioned git block (core projection +
  # whole-block continuation). Teeth unchanged: the four-allow form must be
  # satisfiable; the three-allow state, a fifth row and off-anchor placement
  # must be refused.
  git show "$BASE:$COORD_SRC" >"$TMP/s4-base.md" 2>/dev/null || fail "s4: $COORD_SRC not readable at $BASE"
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/s4-skel.md" strip-shell
  python3 "$TMP/synth.py" "$TMP/s4-skel.md" "$TMP/s4-canon.md" form4
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/s4-four.md" add-origin
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/s4-three.md" strip-origin
  python3 "$TMP/synth.py" "$TMP/s4-four.md" "$TMP/s4-fifth.md" fifth-row
  python3 "$TMP/synth.py" "$COORD_SRC" "$TMP/s4-off.md" off-anchor
  # controls (deterministic today AND after C02 — the contract's soundness and
  # its refusals):
  python3 "$TMP/splice4.py" "$TMP/s4-skel.md" "$TMP/s4-canon.md" none >/dev/null \
    || fail "s4: CONTROL FAILED — splice4 rejects the canonical four-allow form at the no-allow skeleton base (the contract would be unsatisfiable for C02 dev)"
  python3 "$TMP/splice4.py" "$TMP/s4-four.md" "$TMP/s4-four.md" none >/dev/null \
    || fail "s4: CONTROL FAILED — splice4 rejects the committed posture at itself (arm-B idempotence: the landed SHELL4 + sanctioned git block must satisfy the mechanism)"
  python3 "$TMP/atpos4.py" "$TMP/s4-four.md" >/dev/null \
    || fail "s4: CONTROL FAILED — atpos4 rejects the committed posture's fifteen literal lines + sanctioned git-block continuation (line twin unsatisfiable)"
  if python3 "$TMP/splice4.py" "$TMP/s4-skel.md" "$TMP/s4-three.md" none >/dev/null 2>&1; then
    fail "s4: CONTROL FAILED — splice4 accepted the three-allow state at the C02 arm (this suite owns the designed-red: the fourth grant MUST be required)"
  fi
  if python3 "$TMP/splice4.py" "$TMP/s4-skel.md" "$TMP/s4-fifth.md" none >/dev/null 2>&1; then
    fail "s4: CONTROL FAILED — splice4 accepted a fabricated FIFTH shell row (git -C after the origin triple)"
  fi
  if python3 "$TMP/atpos4.py" "$TMP/s4-fifth.md" >/dev/null 2>&1; then
    fail "s4: CONTROL FAILED — atpos4 accepted the fabricated fifth row continuing the block"
  fi
  if python3 "$TMP/splice4.py" "$TMP/s4-skel.md" "$TMP/s4-off.md" none >/dev/null 2>&1; then
    fail "s4: CONTROL FAILED — splice4 accepted the origin allow placed off the anchor"
  fi
  # the real files: OR-form vs $BASE + arm-aware line twin (the sanctioned
  # review geometry is a 3-line addition on a 3-allow base: 3:3 — the four-
  # allow committed base satisfies the twin only through the empty-diff atpos).
  n=0
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    git show "$BASE:$f" >"$TMP/s4-base-$n.md" 2>/dev/null || fail "s4: $f not readable at $BASE"
    python3 "$TMP/splice4.py" "$TMP/s4-base-$n.md" "$f" "$adb" \
      || fail "s4: $f satisfies neither s4 arm (base: $BASE) — red before C02 dev phase"
    if git diff --quiet "$BASE" -- "$f"; then
      python3 "$TMP/atpos4.py" "$f" \
        || fail "s4: $f has an empty diff vs $BASE (arm B posture) but does not carry the twelve literal allow lines at the pinned position"
    else
      bc=$(git show "$BASE:$f" | grep -c '^[[:space:]]*- action: shell' || true)
      ns=$(git diff --numstat "$BASE" -- "$f" | head -n 1 || true)
      add=$(printf '%s' "${ns:-0	0}" | cut -f1)
      del=$(printf '%s' "${ns:-0	0}" | cut -f2)
      case "$bc:$add" in
        0:12) rng='1,12' ;;
        3:3) rng='10,12' ;;
        *) fail "s4: $f diff vs $BASE is +$add/-$del on a base carrying $bc shell allows — want +3 (the session-origin triple on the landed three-allow posture) or +12 (the full four-allow form on a no-allow base), additions only (base: $BASE)" ;;
      esac
      [ "$del" = "0" ] || fail "s4: $f diff vs $BASE removes $del lines — the sanctioned delta is additions-only"
      git diff -U0 "$BASE" -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' | sed 's/^[[:space:]]*//' \
        >"$TMP/s4-add-$n.txt"
      printf '%s\n' '- action: shell' 'resource: opencode api get /api/session*' 'effect: allow' \
                    '- action: shell' 'resource: opencode api patch /api/session/*' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/kickoff-mint-branch.sh *' 'effect: allow' \
                    '- action: shell' 'resource: bash scripts/session-origin.sh*' 'effect: allow' \
        | sed -n "${rng}p" >"$TMP/s4-want-$n.txt"
      cmp -s "$TMP/s4-add-$n.txt" "$TMP/s4-want-$n.txt" \
        || fail "s4: $f added lines are not the literal sanctioned allow rules (see $TMP/s4-add-$n.txt vs $TMP/s4-want-$n.txt)"
    fi
    # NQ1: no-space glob form (zero-arg matcher), the sibling spaced form pinned absent.
    grep -qF "resource: $ORIGIN_RES" "$f" \
      || fail "s4: $f lacks the exact resource literal 'resource: $ORIGIN_RES' (NQ1: NO-SPACE form — C01 calls zero-arg and a trailing-space glob would never match it)"
    if grep -qF 'resource: bash scripts/session-origin.sh *' "$f"; then
      fail "s4: $f carries the SPACED glob form — wrong for a zero-arg call (NQ1 adjudication pinned by plan/C02 2.5)"
    fi
  done
  for pair in "$COORD_SRC|$COORD_GEN|none" "$BCOORD_SRC|$BCOORD_GEN|dev-boards"; do
    IFS='|' read -r s g adb <<<"$pair"
    python3 "$TMP/shape4.py" "$s" "$g" "$adb" \
      || fail "s4: permission shape contract broken for the $s/$g pair"
  done
  ok "s4: fourth scoped allow 'bash scripts/session-origin.sh*' present in all four coord files at the pinned position (OR-form + line twins 3:3/0:12/atpos12; controls accept the sanctioned form and reject the three-allow state, a fabricated fifth row and off-anchor placement); fmshape, deny-baseline, dev-boards*/none posture and the NQ1 glob spelling hold"
fi

# --- s5: containment + permissions.md (C02 AC5/AC6) ---------------------------------
if want s5; then
  for f in "$RC_SRC" "$RC_GEN"; do
    [ -f "$f" ] || fail "s5: $f missing (harness fault)"
    python3 "$TMP/win.py" --ci "$f" 600 'session-origin.sh' 'origin' 'never' \
      || fail "s5: $f does not enumerate the script grants in the containment sentence (2.6: the session-origin grant exists ONLY for the origin slot, never anything else — red before C02 dev phase)"
    python3 "$TMP/win.py" --ci "$f" 500 'opencode api' 'shell' 'own' 'never' \
      || fail "s5: $f broke the cf-52 i2 containment window (must survive the wording move — 2.6)"
  done
  for f in "$PERM_SRC" "$PERM_GEN"; do
    [ -f "$f" ] || fail "s5: $f missing (harness fault)"
    python3 "$TMP/sectgrep.py" "$f" row coord 'session-origin.sh' 'kickoff-mint-branch.sh' 'opencode api get' 'opencode api patch' \
      || fail "s5: $f coord shell cell does not list all four scoped globs — red before C02 dev phase (2.7: the matrix must track the permission-block change, the sibling's coord-row correction precedent)"
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' 'session-origin' 'fifth' \
      || fail "s5: $f has no dated drift-incident entry for the fifth copy of the origin logic guarded by the parity ladder — red before C02 dev phase (2.7)"
  done
  ok "s5: role-coord pair enumerates the script grant (i2 window intact); permissions.md coord cell at four globs + drift entry (C02 AC5/AC6)"
fi

# --- s6: regeneration + commands freeze + five-surface parity (C02 AC7) -------------
if want s6; then
  for p in "$BOARD_SRC|$BOARD_GEN|skill" "$KICK_SRC|$KICK_GEN|skill" "$RC_SRC|$RC_GEN|skill" \
           "$COORD_SRC|$COORD_GEN|agent" "$BCOORD_SRC|$BCOORD_GEN|agent"; do
    IFS='|' read -r s g k <<<"$p"
    python3 "$TMP/pairsync.py" "$s" "$g" "$k" || fail "s6: source/generated pair out of sync for $s ($k) — regenerate, never hand-edit .opencode/"
  done
  for pair in "$PERM_SRC|$PERM_GEN" "$POV_SRC|$POV_GEN"; do
    IFS='|' read -r s g <<<"$pair"
    cmp -s "$s" "$g" || fail "s6: $s vs $g not byte-identical — rulesync copies these references verbatim (t12 carve posture)"
  done
  moved=$( { git diff --name-only "$BASE" -- .rulesync/commands .opencode/commands 2>/dev/null || true;
             git ls-files --others --exclude-standard -- .rulesync/commands .opencode/commands; } | sort -u || true )
  [ -z "$moved" ] || { printf '%s\n' "$moved" >&2; fail "s6: a command file moved vs $BASE — the commands stay byte-frozen to this ticket (t11/t13/t18 + plan Out of scope; the script is the 5th copy, never a 6th block edit)"; }
  # the five-surface fragment-parity ladder, both trees (belt to script.sh b6:
  # plan Commands names it HERE too — it guards C02 from touching commands or
  # the landed C01 script between the chunks):
  [ -f "$SCRIPT" ] || fail "s6: $SCRIPT absent — the parity ladder has no script side (red before C01 dev phase; plan Commands: surface.sh carries the five-surface ladder too)"
  for frag in "sed 's/{{port}}/openchamber/' | tr 'A-Z' 'a-z'" \
              "curl -s -o /dev/null -m 5 -w '%{http_code}'" \
              "200|301|302|303|401|403" \
              "no Coder app-origin env" "unexpected VSCODE_PROXY_URI shape" "derived host answered"; do
    for f in "$SCRIPT" "${CMD_FILES[@]}"; do
      grep -qF -- "$frag" "$f" || fail "s6: fragment '$frag' missing from $f — the five surfaces drift (D12 ladder; C02 must not touch commands or the script)"
    done
  done
  RS=""
  if command -v rulesync >/dev/null 2>&1; then RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then RS="npx --no-install rulesync"; fi
  if [ -z "$RS" ]; then
    skip "s6: rulesync not resolvable here — regen gate skipped with warning (c7/t14 precedent)"
    ok "s6: pair-sync + commands freeze + parity green offline; generator gate skipped with warning"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "s6: rulesync generate --check not clean — committed mirrors stale (C02 AC7)"; }
    timeout 180 $RS generate >/dev/null 2>&1 || fail "s6: first rulesync generate failed"
    before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "s6: second rulesync generate failed"
    after=$(git status --porcelain)
    [ "$before" = "$after" ] || fail "s6: second rulesync generate not a no-op (sources and mirrors drifted)"
    ok "s6: pair-sync + commands byte-freeze + five-surface parity + generate --check clean and no-op second run (C02 AC7)"
  fi
fi

# --- s7: D17 — the {"data": ...} envelope recipe (kickoff pair) ----------------------
if want s7; then
  for f in "$KICK_SRC" "$KICK_GEN"; do
    [ -f "$f" ] || fail "s7: $f missing (harness fault)"
    # Two honest wording families for the same mandate (D17 execution note:
    # unwrap before reading metadata; a top-level read silently returns nothing).
    # Pass either; fail red naming the missing envelope sentence.
    if python3 "$TMP/win.py" --ci "$f" 400 '{"data"' 'unwrap' 'top-level' '.metadata' 2>/dev/null; then
      :
    elif python3 "$TMP/win.py" --ci "$f" 400 '.data' 'unwrap' 'silently' 2>/dev/null; then
      :
    else
      fail "s7: $f does not state the response-envelope unwrap recipe in the read-merge-write mandate (D17 fold-in: opencode api get wraps the record in {\"data\": ...}; a top-level .metadata read silently returns nothing, defeating the idempotent skip and wiping openchamber.kind on the whole-replace — red before C02 dev phase)"
    fi
    # cf-52's i1 windows must ALL hold with the sentence added (placement
    # constraint documented in the header — a genuine move is a re-pin decision,
    # and the sim run proves the honest sentence fits unmodified):
    python3 "$TMP/win.py" "$f" 800 'metadata.openchamber.work' 'open' 'done' \
      || fail "s7: $f broke cf-52's i1 work-key window (metadata.openchamber.work + open + done within 800) — envelope sentence placement moved it; that is the documented re-pin decision, escalate, never silently widen"
    python3 "$TMP/win.py" --ci "$f" 200 'openedBy' 'auto' || fail "s7: $f broke the openedBy/auto window"
    python3 "$TMP/win.py" "$f" 900 'opencode api get /api/session' 'opencode api patch /api/session' \
      || fail "s7: $f broke the carriers window"
    python3 "$TMP/win.py" --ci "$f" 700 'read-merge-write' 'replaces' 'whole' \
      || fail "s7: $f broke the read-merge-write/replaces/whole window (259 chars of slack: keep the sentence under it and before metadata.openchamber.work — see header)"
    python3 "$TMP/win.py" --ci "$f" 300 'skip' 'state' 'open' || fail "s7: $f broke the idempotent-skip window"
    python3 "$TMP/win.py" --ci "$f" 300 'suggestDoneAt' 'reviewOffer' 'never' || fail "s7: $f broke the Jev-field ban window"
  done
  ok "s7: kickoff pair states the {\"data\":...} envelope unwrap; every cf-52 i1 window survives the added sentence (D17 fold-in, re-pin-free)"
fi

printf 'PASS: session-origin contract checks (%d ok)\n' "$checks"
