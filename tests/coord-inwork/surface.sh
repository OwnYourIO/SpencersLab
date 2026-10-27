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
# cf-58 RE-PIN (2026-10-cf-58-feat-standalone-agent-merge, C03; test session):
# the coord family becomes SIX agents (2 alias + 4 variants) whose sanctioned
# permission content is no longer "base + exactly two shell allows" — the
# aliases and variants also carry the git block. The splice OR-form (arm A /
# arm B exact-delta, historical at 081b57889 / f11bfcb85 / 916044893) is
# therefore retired as a delta mechanism; what it protected survives as
# ABSOLUTE presence pins over all twelve family files: the two scoped
# opencode-api session allows exactly (containment — no third API grant,
# which is what made the cf-52 delta meaningful), at their pinned position
# behind the opencode '*' allow (atpos.py, the former arm-B twin), every
# other shell row a git row (git-only-shell discipline), roster/dev-slot per
# variant, and the shapes fmshape pins. The arm-aware line twin stays at the
# empty-diff branch. i5's freeze set sheds the surfaces cf-58 legitimately
# re-opens (gate script, command dirs, AGENTS.md + rules, pipeline-models —
# each now guarded by its own cf-58 suite: gate.sh fixtures, rulesync-surface
# c18, agents-md.sh, tests/pipeline-models/surface.sh). i6 carries the
# six-family pairs. i7 pins the role-coord contract edits (C03 Git section +
# alias convention, C05 stage-gate citation, and the no-shell claim's
# removal). Red posture: i4/i6/i7 red before C03 (family files absent), i7
# partially red until C05 (stage-gate bullet) — between-chunks red is by
# design; i1/i2/i3/i5 stay green HOLD.
#
# Usage:
#   bash tests/coord-inwork/surface.sh           # i1..i7
#   bash tests/coord-inwork/surface.sh i4 i7     # subset
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
# cf-58 C03 re-pin: the six-agent coord family (alias + -local + -pr per
# coord), sources and generated mirrors — the citation set for i4/i6/i7.
CF_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
        .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
        .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
CF_GEN=(.opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md
        .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md
        .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md)

# Task 1.6 list; also the i5 freeze set. The fuser pair is named explicitly
# because D8 keeps the fuser untouched (bare titles → exact title-match
# survives) — an accidental fuser edit would silently break fusion hand-back.
# cf-58 RE-PIN: the gate script, the command dirs, AGENTS.md + the rules
# source, and pipeline-models LEAVE the freeze — C02/C03/C05/C06 legitimately
# edit them, and each surface gained its own cf-58 contract check instead
# (gate.sh fixtures, rulesync-surface c18 pairings, agents-md.sh content
# pins, tests/pipeline-models/surface.sh). The D4 agents-sync carve line in
# the i5 block below stays byte-identical (pinned verbatim by agent-perms A7).
# cf-75 RE-PIN (2026-10-27): pipeline-gates LEAVES the freeze too — C02
# rewrites its validation_at_fault bullet (the silent-route contract), and
# its content is guarded by tests/pipeline-gates/validation-fix.sh, same
# posture as the cf-58 departures. The carve line grows to the three-file
# references trio with it (plan-and-result.md is C02's third rewrite site);
# the exclusion literal moves in lockstep with gate.sh t12 + agent-perms A7.
FREEZE_PATHS=(
  .rulesync/skills/pipeline-role-fuser .opencode/skills/pipeline-role-fuser
  .rulesync/skills/agents-sync .opencode/skills/agents-sync
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
  for i in 1 2 3 4 5 6 7; do WANT["i$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^i[1-7]$ ]] || fail "unknown check id '$a' (expected i1..i7)"
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

cat >"$TMP/cfpins.py" <<'PY'
# cf-58 C03 re-pin of i4/t17's frontmatter contract, replacing cf-52's
# splice OR-form: the sanctioned coord delta is no longer "base + two shell
# allows" (the family now also carries the git block), so the in-work-mark
# citation is pinned ABSOLUTELY per family file — which is stronger than the
# old delta pin:
#   - exactly the two scoped `opencode api` session allows, in get→patch
#     order, and NO other opencode-api shell row (the containment that made
#     the cf-52 delta meaningful — a third API grant is scope escape);
#   - the api pair sits directly after the single opencode '*' allow (the
#     pinned splice position — git rows follow behind, checked separately);
#   - deny-baseline first row intact, question allow intact;
#   - every shell row that is not the api pair is a `git ...` row or the
#     pre-cf-58 shell-'*'-ask baseline — no other tool surface (an agent
#     shell grant beyond git + own-session API is exactly what the plan
#     forbids);
#   - roster = five roles with the variant-correct dev slot (the -pr coords
#     launch the -pr dev, aliases/-local the -local dev);
#   - edit allows = the three plan-state files only.
# argv: file, class(local|pr), board(0|1)
import re, sys, yaml
path, cls, board = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
API = [{"action": "shell", "resource": "opencode api get /api/session*", "effect": "allow"},
       {"action": "shell", "resource": "opencode api patch /api/session/*", "effect": "allow"}]
errs = []
if perms and perms[0] != {"action": "*", "resource": "*", "effect": "deny"}:
    errs.append("deny-baseline first rule changed")
if not any(p.get("action") == "question" and p.get("effect") == "allow" for p in perms):
    errs.append("question allow lost (repo hard rule)")
api_rows = [p for p in perms if p.get("action") == "shell" and str(p.get("resource", "")).startswith("opencode api")]
if api_rows != API:
    errs.append(f"opencode-api shell rows are {api_rows}, want exactly the two scoped session allows in get/patch order (containment)")
anchors = [i for i, p in enumerate(perms) if p == {"action": "opencode", "resource": "*", "effect": "allow"}]
if len(anchors) != 1:
    errs.append(f"want exactly one opencode '*' allow anchor, found {len(anchors)}")
else:
    i = anchors[0]
    if perms[i + 1:i + 3] != API:
        errs.append("the api pair does not sit directly after the opencode '*' allow (pinned splice position)")
SANCTIONED_SCRIPTS = ("bash scripts/kickoff-mint-branch.sh *", "bash scripts/session-origin.sh*")
others = [p.get("resource") for p in perms if p.get("action") == "shell"
          and not str(p.get("resource", "")).startswith(("opencode api", "git "))
          and p.get("resource") != "*"
          and p.get("resource") not in SANCTIONED_SCRIPTS]
if others:
    errs.append(f"non-API non-git shell rows present: {others} (coord shell surface = the two API allows + the two cf-52 sanctioned script allows + the git block + the ask baseline, nothing more)")
slot = "agent-dev-pr" if cls == "pr" else "agent-dev-local"
subs = sorted(p.get("resource") for p in perms if p.get("action") == "subagent" and p.get("effect") == "allow")
want_subs = sorted(["agent-plan", "agent-test", slot, "agent-review", "agent-research"])
if subs != want_subs:
    errs.append(f"subagent allows {subs}, want the five roles with dev slot {slot}")
edits = sorted(p.get("resource") for p in perms if p.get("action") == "edit")
if edits != sorted([".agents/plans/**/STATE.json", ".agents/plans/**/DECISIONS.md", ".agents/plans/**/FRICTION.md"]):
    errs.append(f"edit allows are {edits}, want only the three plan-state files")
if board:
    db = [i for i, p in enumerate(perms) if p.get("action") == "dev-boards*"]
    if len(db) != 1 or db[0] < 1 or perms[db[0]].get("effect") != "allow":
        errs.append("the single narrow dev-boards* allow is gone (board variants keep it)")
    if not any(p.get("action") == "execute" and p.get("effect") == "allow" for p in perms):
        errs.append("execute allow lost from a board variant (Code Mode transport)")
    if any(p.get("action") == "dev*" for p in perms):
        errs.append("broad dev* allow appeared on a board variant (D21)")
if errs:
    print("; ".join(errs)); sys.exit(1)
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
# degree of freedom left to drift in; the only sanctioned continuation after
# the matched form is the cf-58 git block (comment lines in the source tree
# + the fourteen git rows, whole and in order) — any other shell row is
# unsanctioned.
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
# cf-58 merge re-pin: after the matched sanctioned block the only permitted
# continuation is comment lines (source tree only — the rulesync YAML
# round-trip strips them from the generated mirror) plus the sanctioned git
# block, whole and in order — the thirteen shared rows plus the variant
# tail: push-deny on -local/alias files, push-allow + push-main deny + the
# four force-flag denies on -pr files; any other shell row is unsanctioned.
COMMON = [(f"{ind}- action: shell", f"{ind}  resource: {r}", f"{ind}  effect: allow") for r in
          ("git status *", "git log *", "git diff *", "git show *", "git branch *",
           "git merge-base *", "git rev-parse *", "git ls-files *", "git add *",
           "git commit *", "git checkout *", "git switch *", "git merge main*")]
def T(r, e):
    return (f"{ind}- action: shell", f"{ind}  resource: {r}", f"{ind}  effect: {e}")
TAILS = [[T("git push*", "deny")],
         [T("git push*", "allow"), T("git push*main*", "deny"), T("git push --force*", "deny"),
          T("git push -f*", "deny"), T("git push * --force*", "deny"), T("git push * -f*", "deny")]]
k = at + matched
gi = saw = 0
chosen = None
while k < len(lines):
    if lines[k].lstrip().startswith("#"):
        k += 1
        continue
    if lines[k].strip() == "- action: shell":
        saw = 1
        if gi < len(COMMON):
            if lines[k:k + 3] != list(COMMON[gi]):
                print(f"a shell row continues the block after the sanctioned form and is not the next sanctioned git-block row (want {COMMON[gi]}, got {lines[k:k + 3]}) — unsanctioned shell grant"); sys.exit(1)
            gi += 1
            k += 3
            continue
        if chosen is not None:
            print("a shell row continues after the complete sanctioned git block — unsanctioned shell grant"); sys.exit(1)
        chosen = next((t for t in TAILS if lines[k:k + 3 * len(t)] == [ln for tr in t for ln in tr]), None)
        if chosen is None:
            print(f"the git block's tail is neither the -local push-deny row nor the -pr push sextet (got {lines[k:k + 18]}) — unsanctioned shell grant"); sys.exit(1)
        k += 3 * len(chosen)
        continue
    break
if saw and (gi != len(COMMON) or chosen is None):
    print(f"the git block continues the shell surface but is truncated or reordered (matched {gi} of {len(COMMON)} shared rows, tail {'found' if chosen else 'missing'})"); sys.exit(1)
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

# --- i4: in-work-mark citation across the SIX coord-family agents (AC1) --------
# cf-58 C03 re-pin (see the header): the delta mechanism retired; the two
# scoped opencode-api session allows + the shapes that must hold are now
# pinned absolutely on all twelve family files (6 sources + 6 mirrors).
# RED before C03 — the variant files do not exist yet; the red names them.
if want i4; then
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    [ -f "$f" ] || fail "i4[C03]: $f missing — the in-work-mark citation is asserted across ALL SIX coord-family agents (source + mirror), replacing the two-agent pins (red before C03)"
  done
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    # *-pr.md (with the extension) — a bare *-pr never matches the .md
    # filenames and would silently evaluate -pr files under -local
    # expectations (validation_at_fault round 3).
    case "$f" in
      *-pr.md) cls=pr ;; *) cls=local ;;
    esac
    case "$f" in *board-coord*) board=1 ;; *) board=0 ;; esac
    python3 "$TMP/cfpins.py" "$f" "$cls" "$board" \
      || fail "i4[C03]: $f violates the coord-family frontmatter contract (class $cls, board $board) — API containment / pinned position / roster slot / shapes (base semantics per cf-52 D10, pinned absolutely per cf-58 C03)"
    # Line-level twin, arm-aware (the cf-52 T10 discipline survives): once a
    # family file's cf-58 delta is committed (empty diff vs BASE) the pinned
    # literal shell lines must sit at the pinned position; while a file is
    # mid-flight the absolute cfpins presence pin above is the guard (the
    # old +6/-0 exact-delta twin died with the splice OR-form).
    if git diff --quiet "$BASE" -- "$f"; then
      python3 "$TMP/atpos.py" "$f" \
        || fail "i4[C03]: $f has an empty diff vs $BASE but does not carry the six literal shell allow lines directly after the opencode '*' allow"
    fi
  done
  ok "i4[C03]: all twelve coord-family files carry exactly the two scoped session API allows at the pinned position, git-only additional shell rows, variant-correct rosters, and the plan-state/question/deny-baseline shapes; committed files additionally line-twinned at pinned position"
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
  # cf-75 C02 re-pin (2026-10-27): plan-and-result.md joins the carve (the
  # trio literal moves in lockstep with t12/A7), and the pipeline-gates pair
  # left FREEZE_PATHS above — its silent-route rewrite is guarded by
  # tests/pipeline-gates/validation-fix.sh, not by invariance here.
  moved=$( { git diff --name-only "$BASE" -- "${FREEZE_PATHS[@]}" 2>/dev/null || true;
             git ls-files --others --exclude-standard -- "${FREEZE_PATHS[@]}"; } \
           | sort -u \
           | grep -v -x -E -e '(\.rulesync|\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview|plan-and-result)\.md' \
           || true )
  if [ -n "$moved" ]; then
    printf '%s\n' "$moved" >&2
    fail "i5: a byte-frozen surface (task 1.6 list, minus the cf-58 and cf-75 departures) changed vs $BASE outside the agents-sync references carve — fuser, the rest of agents-sync and templates stay untouched (D8/D12); the carved permissions.md/pipeline-overview.md/plan-and-result.md trio is guarded by t12/A5 pair-equality; gates moved to validation-fix.sh at cf-75 C02"
  fi
  ok "i5: freeze set byte-unchanged vs $BASE (worktree included) except the agents-sync references carve — fuser pairs, carve-excluded agents-sync internals, templates; gates/commands/AGENTS/rules/models left at the cf-58/cf-75 re-pins; carved trio guarded by t12 + agent-perms A5"
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
  for f in "${CF_GEN[@]}"; do
    grep -qF "$SHELL_GET" "$f" && grep -qF "$SHELL_PATCH" "$f" \
      || fail "i6[C03]: generated $f does not carry the two scoped shell grants (six-family pair-carry — red before C03)"
  done
  # (b) pair sync (offline): the mirrors equal their sources modulo rulesync's
  # deterministic re-serialization.
  for p in "$KICK_SRC|$KICK_GEN|skill" "$RC_SRC|$RC_GEN|skill" "$BOARD_SRC|$BOARD_GEN|skill" \
           "${CF_SRC[0]}|${CF_GEN[0]}|agent" "${CF_SRC[1]}|${CF_GEN[1]}|agent" "${CF_SRC[2]}|${CF_GEN[2]}|agent" \
           "${CF_SRC[3]}|${CF_GEN[3]}|agent" "${CF_SRC[4]}|${CF_GEN[4]}|agent" "${CF_SRC[5]}|${CF_GEN[5]}|agent"; do
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

# --- i7: role-coord contract edits — C03 Git section + C05 stage gate -----------
# Pins the chunk-owned SKILL.md passages (source + mirror): the Git section
# (coord commits per chunk, may merge main INTO the work branch, -pr pushes
# only per pipeline-push-pr, -local/alias never push), the alias-convention
# line, the removal of the stale "coord has no shell" claim, and the C05
# Stage-gate bullet that CITES the boards stage map instead of restating it
# (the D1 single-authority pattern). Red before C03/C05 — the passages do
# not exist yet; every red names the missing passage.
if want i7; then
  for f in "$RC_SRC" "$RC_GEN"; do
    [ -f "$f" ] || fail "i7: $f missing"
    grep -qiE '^#{1,6}[[:space:]].*Git' "$f" \
      || fail "i7[C03]: $f has no Git section — coord commits the subagents' work per chunk (red before C03)"
    python3 "$TMP/win.py" --ci "$f" 700 'git' 'commit' 'merge' 'main' 'push' \
      || fail "i7[C03]: $f's Git passage does not carry the full C03 shape (commit per chunk; may merge main INTO the work branch; -pr pushes only per pipeline-push-pr; -local/alias never push)"
    python3 "$TMP/win.py" --ci "$f" 300 'pipeline-push-pr' 'push' \
      || fail "i7[C03]: $f does not route -pr pushes through the pipeline-push-pr authority"
    python3 "$TMP/win.py" --ci "$f" 500 'alias' 'local' \
      || fail "i7[C03]: $f lacks the alias-convention line (plain coord names are aliases of their -local variants; a variant change lands on the alias in the same commit)"
    if grep -qiE 'coord (is|has) (shell-less|no shell)|no shell (access|grants?) (for|on) coord' "$f"; then
      fail "i7[C03]: $f still claims coord is shell-less — the hard-rule wording is stale (C03 fixes it: git-only shell; the never-plan/investigate/implement rules stand)"
    fi
    python3 "$TMP/win.py" --ci "$f" 500 'stage gate' 'lifecycle' 'boards' \
      || fail "i7[C05]: $f lacks the Stage-gate (board runs) bullet citing the boards stage map (red before C05)"
    if python3 "$TMP/win.py" --ci "$f" 900 'stage gate' 'pre research' 'post research' 'single session' 'deploy'; then
      fail "i7[C05]: $f RESTATES the stage map — the boards skill is the single authority; the coord bullet cites it, one paragraph, never duplicates the table (the D1 pattern)"
    fi
  done
  ok "i7: role-coord carries the Git section, the alias convention, the corrected shell posture, and a citation-only Stage-gate bullet (source + mirror)"
fi

printf 'PASS: coord-inwork surface checks (%d ok)\n' "$checks"
