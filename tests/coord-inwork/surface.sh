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
# i3[AC4 boards citation + key-path non-leak] i4[AC1 two scoped shell grants]
# i5[AC5 freeze set] i6[AC6 regeneration contract].
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
# CHUNK_BASE=<ref> narrows the diff/splice checks to "since that commit";
# default HEAD (working tree vs committed base — same convention as the
# sibling suites in tests/agent-board-coord/).
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
# i4/t17-style frontmatter delta contract: current permissions must equal the
# base permissions with EXACTLY the two scoped shell allows spliced after the
# `opencode '*' allow` rule — count, literals, order and position pinned at
# once; any other change anywhere in the block fails (deny-baseline byte-
# unchanged and "no other shell row" are enforced by the same equality).
# Source files nest the block under opencode:, generated files at top level —
# read from whichever carries it.
import re, sys, yaml
base_path, cur_path, need_dev_boards = sys.argv[1], sys.argv[2], sys.argv[3] == 'dev-boards'
SHELL = [
    {"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"},
    {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"},
]

def perms(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []

b, c = perms(base_path), perms(cur_path)
if b[0] != {"action": "*", "resource": "*", "effect": "deny"}:
    print("deny-baseline first rule changed at base — the suite's premise broke"); sys.exit(1)
anchor = [i for i, p in enumerate(b) if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
if len(anchor) != 1:
    print(f"base must carry exactly one opencode '*' allow, found {len(anchor)}"); sys.exit(1)
i = anchor[0]
want = b[:i + 1] + SHELL + b[i + 1:]
if c == want:
    pass
else:
    if len(c) == len(b) and not any(p.get("action") == "shell" for p in c):
        print("the two scoped shell allows are not applied (expected red before C01)"); sys.exit(1)
    extra = [p for p in c if p not in want]
    missing = [p for p in want if p not in c]
    print(f"frontmatter delta is not exactly the two shell allows: extra={extra} missing={missing}")
    sys.exit(1)
shells = [p.get("resource") for p in c if p.get("action") == "shell"]
if shells != [s["resource"] for s in SHELL]:
    print(f"shell resources are {shells}, want exactly the two scoped session globs in order"); sys.exit(1)
if c[0] != b[0]:
    print("deny-baseline line drifted"); sys.exit(1)
if need_dev_boards and not any(p.get("action") == "dev_boards*" and p.get("resource") == "*"
                               and p.get("effect") == "allow" for p in c):
    print("dev_boards* allow missing from a board-coord file"); sys.exit(1)
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
want = ["opencode api get /api/session*", "opencode api patch /api/session/*"]
if shells != want:
    errs.append(f"shell resources {shells} != exactly the two scoped session globs")
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

# --- i4: frontmatter delta on the coord pair — exactly two shell allows (AC1) --
if want i4; then
  n=0
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    git show "$BASE:$f" >"$TMP/base-$n.md" 2>/dev/null || fail "i4: $f not readable at $BASE"
    python3 "$TMP/splice.py" "$TMP/base-$n.md" "$f" "$adb" \
      || fail "i4: $f frontmatter is not the base perms + exactly the two scoped shell allows after the opencode allow (base: $BASE)"
    # Line-level twin of the semantic splice: the plan pins "exactly the two
    # added allow-line pairs (count + literal match)"; additions-only keeps a
    # reworded deny-baseline from hiding inside a rewrite.
    ns=$(git diff --numstat "$BASE" -- "$f" | head -n 1 || true)
    add=$(printf '%s' "${ns:-0	0}" | cut -f1)
    del=$(printf '%s' "${ns:-0	0}" | cut -f2)
    [ "$add" = "6" ] && [ "$del" = "0" ] \
      || fail "i4: $f diff vs $BASE is +$add/-$del lines, want exactly +6/-0 (two 3-line allow rules, nothing else)"
    git diff -U0 "$BASE" -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' | sed 's/^[[:space:]]*//' \
      >"$TMP/add-$n.txt"
    printf '%s\n' '- action: shell' 'resource: opencode api get /api/session*' 'effect: allow' \
                  '- action: shell' 'resource: opencode api patch /api/session/*' 'effect: allow' \
      >"$TMP/want-$n.txt"
    cmp -s "$TMP/add-$n.txt" "$TMP/want-$n.txt" \
      || fail "i4: $f added lines are not the literal two allow rules (see $TMP/add-$n.txt vs $TMP/want-$n.txt)"
  done
  for f in "$COORD_GEN" "$BCOORD_GEN"; do
    python3 "$TMP/fmshape.py" "$f" "$( [ "$f" = "$BCOORD_GEN" ] && echo dev-boards || echo none )" \
      || fail "i4: generated $f breaks the permission shape that must hold through the delta"
  done
  ok "i4: all four coord files carry exactly the two shell allows (splice + +6/-0 + literal lines); shapes, dev_boards* and deny-baseline intact"
fi

# --- i5: freeze set — byte-unchanged vs the ticket base (AC5) ------------------
if want i5; then
  if ! git diff --quiet "$BASE" -- "${FREEZE_PATHS[@]}" 2>/dev/null; then
    git diff --name-only "$BASE" -- "${FREEZE_PATHS[@]}" >&2
    fail "i5: a byte-frozen surface (task 1.6 list) changed vs $BASE — the marker is purely UI: gate, commands, fuser, agents-sync, models/gates, AGENTS.md and templates stay untouched (D8/D12)"
  fi
  untracked=$(git ls-files --others --exclude-standard -- "${FREEZE_PATHS[@]}" || true)
  [ -z "$untracked" ] || fail "i5: new untracked file(s) inside frozen dirs: $untracked"
  ok "i5: freeze set byte-unchanged vs $BASE (worktree included) — gate script, commands, fuser/agents-sync/models/gates pairs, AGENTS.md, rules, templates"
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
