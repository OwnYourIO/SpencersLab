#!/usr/bin/env bash
# agent-test / agent-dev-pr / agent-dev-local top-level tests/** permission
# contract suite
# (2026/2026-10-bug-tests-edit-perms, C01; RE-PINNED by cf-58 for the dev-role
# split into agent-dev-pr/agent-dev-local (C02) and the coord-family variants
# + aliases (C03)).
#
# Pins the invariant this ticket creates: the agent-* permission blocks know
# top-level `tests/` exists — agent-test may write the repo-validation suites
# under it (last-match after its `edit * deny`), the dev variants may not
# (last-match after their `edit * allow`), the role-matrix/skill prose says
# so, and the regenerated mirrors are honest. Contract source: plan file
# Goal + chunks/C01.md AC1-AC9; DECISIONS D2-D5 (the blocks' blind spot) and
# D9-D12 (the post-landing base-posture fold-in) are binding. cf-58 re-pin
# source: chunks/C02.md + C03.md "## Tests" (DEV_* now the TWO variant pairs,
# coord path variables the SIX family files, new parsed checks A11-A13).
#
# AC trace: A1[AC1] A2[AC2] A3[AC3] A4[AC4] A5[AC5-pairs]
# A6[AC5-regen/AC6-hold] A7[AC6-AC7] A8[AC6-parse-safety] A9[AC9-admits]
# A10[AC9-or-form→cf-58 mechanism-integrity] A11[C02 git rows + push policy]
# A12[C03 six-family: alias parity, git block order, roster dev slot]
# A13[C02 AC5/C03 AC7 rename sweep + command→agent pairing].
#
# Red posture: A1-A4 — the permission rows and the text rows do not exist
# yet; every red line names the missing rule/row, never a harness fault.
# A5-A8 are HOLD posture (green now, must stay green). A9 pinned the TEST
# phase's own suite re-pins (folder admits), green from this file's landing
# and HOLD through dev. A10 is the cf-58 RE-PIN of the old mechanism test:
# the splice OR-form died with the C02/C03 splits (the sanctioned coord-side
# delta is no longer "+two shell rows" — it is the git block + roster +
# alias parity), so A10 now runs the parsed family checks the plan re-pins
# onto this suite: alias↔local equality (the drift guard), git-row order,
# push-policy last-match, roster dev slot, plus fabricated-row negative
# controls proving the guards never degenerate into "empty diff ⇒ pass".
# A10/A11/A12 are RED before C02/C03 (variant/alias files absent); A13's
# rename sweep is RED before C02 (bare pre-split references still live in
# AGENTS.md and the case-arm literals until the chunks land).
# After each chunk lands, `bash tests/agent-perms/surface.sh` must pass the
# subset its chunk owns; the full suite is green at the end of C03.
#
# Sweep-scope judgment (recorded for review): C02 AC5 ("no bare agent-dev
# in .rulesync/, .opencode/, AGENTS.md, tests/") is implemented on the
# BINDING surfaces — subagent/command sources and their generated mirrors —
# where a bare reference re-grants the retired single-agent wiring. Prose
# mirrors are pinned POSITIVELY instead: AGENTS.md must carry C02's new
# roster row (the variant set named), and the two retired paths must not
# exist as files. Why: the plan itself leaves prose bare mentions byte-
# stable (pipeline-role-dev's description; AGENTS.md "Pipeline specifics"
# lines until C03's overview surgery), so a literal prose sweep would pin
# the plan into a contradiction — the strongest deterministic assertion
# the acceptance criteria support is binding-surface absence + roster
# presence. C03's overview rewrite additionally clears AGENTS.md prose.
#
# Offline-deterministic: no server, no session, no live cluster — rules are
# parsed from the YAML frontmatter (dict comparison, not bytes: rulesync
# re-serializes the mirror, so the honest pair invariant is "same parsed rule
# list in the same order"; byte-equality is asserted only where rulesync
# copies verbatim, the two agents-sync references pairs, A5).
#
# Operational bases (D10/D11 fold-in): every run must pass at BOTH default
# BASE=HEAD (arm B — committed posture on the integrated line, main >=
# 124fc2ae8) AND CHUNK_BASE=081b57889 (arm A — the landing parent of the
# cf-52 content 20ed5dfaf). A7's sanctioned-delta walk uses $BASE; A10 runs
# its fixtures at the two literal operational refs regardless of $BASE.
# Pre-landing bases (f11bfcb85; 916044893 as a chunk base; the cf-52 branch
# refs b0c975bf6/1a6517c81) are historical and need not pass.
#
# Usage (harness convention from tests/coord-inwork/surface.sh):
#   bash tests/agent-perms/surface.sh            # A1..A13
#   bash tests/agent-perms/surface.sh A1 A4      # subset (ids case-insensitive)
# Chunk-owned subsets (red-between-chunks is by design per DECISIONS):
#   C02 review: A1..A11 + A13 (A10/A12 belong to C03)
#   C03 review: full suite
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${CHUNK_BASE:-HEAD}"
git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: CHUNK_BASE '$BASE' is not a commit in this repo" >&2; exit 2; }

# The two operational refs A10 pins against (D11: 081b57889 is the landing
# parent of the cf-52 content, NOT 916044893, whose child is the release-bot
# Chart.yaml commit the scope guards do not admit).
ARM_A=081b57889
ARM_B=HEAD
INTEGRATED=124fc2ae8

TEST_SRC=".rulesync/subagents/agent-test.md"
TEST_GEN=".opencode/agents/agent-test.md"
# cf-58 C02 re-pin: the single implementer pair is now the TWO variant pairs.
DEV_LOCAL_SRC=".rulesync/subagents/agent-dev-local.md"
DEV_LOCAL_GEN=".opencode/agents/agent-dev-local.md"
DEV_PR_SRC=".rulesync/subagents/agent-dev-pr.md"
DEV_PR_GEN=".opencode/agents/agent-dev-pr.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"
POV_SRC=".rulesync/skills/agents-sync/references/pipeline-overview.md"
POV_GEN=".opencode/skills/agents-sync/references/pipeline-overview.md"
RT_SRC=".rulesync/skills/pipeline-role-test/SKILL.md"
RT_GEN=".opencode/skills/pipeline-role-test/SKILL.md"
RULES_SRC=".rulesync/rules/overview.md"
# cf-58 C03 re-pin: the coord path variables name the SIX family files (alias
# + -local + -pr per coord), sources and generated mirrors.
CF_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
        .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
        .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
CF_GEN=(.opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md
        .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md
        .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md)
SUITE_SURFACE="tests/coord-inwork/surface.sh"
SUITE_GATE="tests/agent-board-coord/gate.sh"
SUITE_RULESYNC="tests/agent-board-coord/rulesync-surface.sh"
SUITE_AGENTSMD="tests/agent-board-coord/agents-md.sh"
SUITE_PUSH="tests/pipeline-push-pr/surface.sh"
SUITE_STANDALONE="tests/standalone-agents/surface.sh"
SUITE_MODELS="tests/pipeline-models/surface.sh"

# The D4 carve set: exactly these four paths may move inside the agents-sync
# dirs; the exclusion regex is grepped inside both guarded suites (A7).
CARVE_RE='^(\.rulesync|\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview)\.md$'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/agent-perms-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 13); do WANT["a$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^a([1-9]|1[0-3])$ ]] || fail "unknown check id '$a' (expected A1..A13)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers ------------------------------------------------------------

cat >"$TMP/permdelta.py" <<'PY'
# One file's permission contract, both trees, one process:
#  - the parsed rule lists of source and generated mirror must be EQUAL and
#    in equal order (rulesync re-serializes bytes — dict/sequence equality is
#    the honest mirror invariant, and ordering is what last-match-wins makes
#    load-bearing, so it must be pinned);
#  - the pivot rule (deny for test, allow for dev) is the FIRST edit rule;
#  - the new rule (allow for test, deny for dev) exists with the exact shape
#    and sits AFTER the pivot — before it, the pivot silently wins.
# argv: role(test|dev) then the file pairs (source, generated).
import re, sys, yaml
role = sys.argv[1]
files = sys.argv[2:]
PIVOT = {"action": "edit", "resource": "*",
         "effect": "deny" if role == "test" else "allow"}
NEW = {"action": "edit", "resource": "tests/**",
       "effect": "allow" if role == "test" else "deny"}
SIBLINGS = ["charts/**/tests/**", "containers/**/tests/**"]
# The pre-existing chart/container test rules keep the OPPOSITE effect of the
# baseline (the deny-baseline test role grants them; the allow-baseline dev
# role revokes them) — pinning the wrong effect here would red on a healthy
# tree and bury the real missing-rule red underneath false findings.
SIBLING_EFFECT = "allow" if role == "test" else "deny"
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
errs = []
parsed = {}
for f in files:
    p = parsed[f] = perms(f)
    at = [i for i, r in enumerate(p) if r.get("action") == "edit"]
    if not at:
        errs.append(f"{f}: no edit rules at all")
        continue
    if p[at[0]] != PIVOT:
        errs.append(f"{f}: the first edit rule is {p[at[0]]}, want the {role} baseline {PIVOT}")
    piv = [i for i in at if p[i] == PIVOT]
    new = [i for i in at if p[i] == NEW]
    if not new:
        errs.append(f"{f}: the top-level tests/** '{NEW['effect']}' rule is MISSING "
                    f"(red before C01 dev phase — {role} block does not know top-level tests/ exists)")
    elif not piv or piv[0] > new[0]:
        errs.append(f"{f}: tests/** rule present but BEFORE its pivot — last match wins, the {role} baseline would silently override it")
    elif len(new) != 1:
        errs.append(f"{f}: tests/** rule appears {len(new)} times, want exactly one")
    for s in SIBLINGS:
        if not any(p[i] == {"action": "edit", "resource": s, "effect": SIBLING_EFFECT} for i in at):
            errs.append(f"{f}: the existing {s} '{SIBLING_EFFECT}' rule vanished")
# Pair equality runs as a separate finding, never an early exit: it buries the
# missing-rule red when a dev round edits the source before the mirror lands,
# and the reviewer must see BOTH reasons in one run.
src, gen = files
if parsed[src] != parsed[gen]:
    errs.append(f"source/generated permission lists differ for the {role} pair "
                f"(order or content drift between {src} and {gen} — regenerate, "
                f"never hand-edit the mirror)")
if errs:
    print("; ".join(errs))
    sys.exit(1)
PY

cat >"$TMP/sectgrep.py" <<'PY'
# Line/section-scoped text pins for the stale-surface sweep: role-matrix rows
# are pinned by their label cell, the drift incident by its section, the skill
# write-surface sentence by its lead-in. Row-level greps survive rewording
# elsewhere and fail exactly when the row has not moved.
# argv: file, mode, anchor..., needles...  (mode 'all' has no anchor)
#   row     — markdown table rows whose first cell equals the anchor
#   section — every line from the heading matching the anchor to EOF
#   line    — the lines that contain the anchor substring
#   all     — the whole file
import re, sys
path, mode = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
text = open(path).read()
if mode == "all":
    anchor, needles = None, rest
    hay = text
else:
    anchor, needles = rest[0], rest[1:]
    if mode == "row":
        # [ \t], NOT [[:space:]] — Python's re has no POSIX classes (on 3.14
        # the nested-set reading silently matches no space, killing row lookups).
        hay = "\n".join(l for l in text.splitlines()
                        if re.match(r"^\|[ \t]*" + re.escape(anchor) + r"[ \t]*\|", l))
    elif mode == "section":
        m = re.search(r"(?ms)^#+[^\n]*" + re.escape(anchor) + r"[^\n]*\n.*", text)
        hay = m.group(0) if m else ""
    elif mode == "line":
        hay = "\n".join(l for l in text.splitlines() if anchor in l)
    else:
        print(f"unknown sectgrep mode '{mode}'"); sys.exit(2)
if not hay:
    print(f"{path}: no {mode} '{anchor if anchor else ''}' content to search"); sys.exit(1)
for n in needles:
    if n not in hay:
        print(f"{path}: '{n}' missing from the {mode}"
              + (" (red before C01 dev phase — the text row has not moved)" if mode != "all" else ""))
        sys.exit(1)
PY

cat >"$TMP/blockwin.py" <<'PY'
# Windowed grep over a suite's `if want <id>; then ... fi` block: an admission
# or exclusion elsewhere in the file must not satisfy the pin (A9/A10/A7).
# argv: suite-file, check-id (t14|c8|c7|t12|i5|t17|i4|...), needle...
import sys
path, cid = sys.argv[1], sys.argv[2]
needles = sys.argv[3:]
lines = open(path).read().splitlines()
start = next((i for i, l in enumerate(lines) if l.startswith(f"if want {cid}; then")), None)
if start is None:
    print(f"{path}: block 'if want {cid}' not found"); sys.exit(1)
end = next((i for i in range(start + 1, len(lines)) if lines[i] == "fi"), None)
if end is None:
    print(f"{path}: no closing ^fi for block 'if want {cid}'"); sys.exit(1)
block = "\n".join(lines[start:end + 1])
for n in needles:
    if n not in block:
        print(f"{path}: '{n}' is not inside the if-want-{cid} block (windowed admission pin — "
              "a hit elsewhere in the file does not count)")
        sys.exit(1)
PY

cat >"$TMP/family.py" <<'PY'
# cf-58 C02/C03 guard set for the agent-dev variant pair and the six-agent
# coord family. One shipped implementation used by both the live checks
# (A11/A12) and the fabricated-row negative controls (A10) — the cf-52
# lesson kept: a guard must be provably NON-vacuous, so the same code the
# live run uses is what the controls exercise.
# Subcommands (all exit 1 with a reason on violation):
#   parity A B                 — parsed permission lists equal (dict+order)
#                                AND the body MUST-load lists (/skill lines)
#                                equal; the drift guard for alias<->-local.
#   gitrows FILE CLASS         — CLASS devlocal|devpr|local|pr: the git rows
#                                exactly as the plan declares, in order, and
#                                nothing else added beyond base+suffix.
#   policy FILE CMD            — prints the effective last-match verdict.
#   roster FILE SLOT           — subagent allows == the five roles with SLOT
#                                in the dev position, leading '*' deny first.
#   api FILE                   — exactly the two scoped opencode-api shell
#                                allows, in order, directly after the single
#                                opencode '*' allow rule.
#   board FILE                 — dev_boards* allow once, after the leading
#                                deny-all; execute allow present.
import re, sys, yaml

def fm(path):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    return (yaml.safe_load(m.group(1)) or {}, m.group(2))

def perms(path):
    f, _ = fm(path)
    return (f.get("opencode") or {}).get("permissions") or f.get("permissions") or []

def skillloads(path):
    _, body = fm(path)
    return [l.strip() for l in body.splitlines() if re.match(r"^\s*/[a-z0-9-]+\s*$", l)]

def sh(res, eff):
    return {"action": "shell", "resource": res, "effect": eff}

GIT_READS = ["git status *", "git log *", "git diff *", "git show *", "git branch *",
             "git merge-base *", "git rev-parse *", "git ls-files *"]
DEV_SUFFIX = {
    "devlocal": [sh("git add *", "allow"), sh("git commit *", "allow"), sh("git push*", "deny")],
    "devpr": [sh("git add *", "allow"), sh("git commit *", "allow"), sh("git push*", "allow"),
              sh("git push*main*", "deny"), sh("git push --force*", "deny"), sh("git push -f*", "deny"),
              sh("git push * --force*", "deny"), sh("git push * -f*", "deny")],
}
COORD_SUFFIX = {
    "local": [sh(r, "allow") for r in GIT_READS] +
             [sh("git add *", "allow"), sh("git commit *", "allow"),
              sh("git checkout *", "allow"), sh("git switch *", "allow"),
              sh("git merge main*", "allow"), sh("git push*", "deny")],
    "pr": [sh(r, "allow") for r in GIT_READS] +
          [sh("git add *", "allow"), sh("git commit *", "allow"),
           sh("git checkout *", "allow"), sh("git switch *", "allow"),
           sh("git merge main*", "allow"), sh("git push*", "allow"),
           sh("git push*main*", "deny"), sh("git push --force*", "deny"), sh("git push -f*", "deny"),
           sh("git push * --force*", "deny"), sh("git push * -f*", "deny")],
}

def fail(*msgs):
    print("; ".join(str(m) for m in msgs)); sys.exit(1)

def is_git(row):
    return row.get("action") == "shell" and str(row.get("resource", "")).startswith("git ")

def cmd():
    op = sys.argv[1]
    if op == "parity":
        a, b = sys.argv[2], sys.argv[3]
        pa, pb = perms(a), perms(b)
        if pa != pb:
            i = next((i for i, (x, y) in enumerate(zip(pa, pb)) if x != y), min(len(pa), len(pb)))
            fail(f"parity: {a} vs {b} permission lists differ at index {i} "
                 f"(a: {pa[i] if i < len(pa) else None} b: {pb[i] if i < len(pb) else None}; lengths {len(pa)}/{len(pb)})")
        sa, sb = skillloads(a), skillloads(b)
        if sa != sb:
            fail(f"parity: MUST-load lists differ: {a}={sa} {b}={sb}")
    elif op == "gitrows":
        path, cls = sys.argv[2], sys.argv[3]
        table = DEV_SUFFIX if cls.startswith("dev") else COORD_SUFFIX
        suffix = table[cls]
        p = perms(path)
        git = [r for r in p if is_git(r)]
        if cls.startswith("dev"):
            # the declared rows must appear in the declared relative order…
            seq = [r for r in git if any(r == s for s in suffix)]
            if seq != suffix:
                miss = [s for s in suffix if s not in git]
                dup = len(seq) != len(suffix)
                fail(f"gitrows({cls}): {path} declared git rows missing {miss}, duplicated {dup}, or out of order ({seq})")
            # …and no undeclared git row may ride along (the base block's own
            # status/diff/log reads are the only pre-existing git rows)
            base_reads = [sh("git status *", "allow"), sh("git diff *", "allow"), sh("git log *", "allow")]
            extras = [r for r in git if not any(r == s for s in suffix) and not any(r == s2 for s2 in base_reads)]
            if extras:
                fail(f"gitrows({cls}): {path} carries undeclared extra git rows: {extras}")
        else:
            # coord family: no pre-existing git rows — the whole git sequence
            # must equal the declared block, in order, exactly once
            if git != suffix:
                fail(f"gitrows({cls}): {path} git-row sequence is not the declared coord block in order "
                     f"({len(git)} rows seen, {len(suffix)} declared; diff at first mismatch)")
    elif op == "policy":
        import fnmatch as _fm
        path, command = sys.argv[2], sys.argv[3]
        verdict = None
        for r in perms(path):
            if not (r.get("action") == "shell" or _fm.fnmatch(str(r.get("action", "")), "*")):
                continue
            if _fm.fnmatch(command, str(r.get("resource", ""))):
                verdict = r.get("effect")
        print(verdict)
    elif op == "roster":
        path, slot = sys.argv[2], sys.argv[3]
        p = perms(path)
        if p[0] != {"action": "*", "resource": "*", "effect": "deny"}:
            fail(f"roster: {path} lost the leading deny-all baseline")
        allows = sorted(r.get("resource") for r in p if r.get("action") == "subagent" and r.get("effect") == "allow")
        want = sorted(["agent-plan", "agent-test", slot, "agent-review", "agent-research"])
        if allows != want:
            fail(f"roster: {path} subagent allows {allows}, want exactly {want} (deny-all + five-role roster, leading subagent '*' deny stays)")
        if not any(r.get("action") == "subagent" and r.get("resource") == "*" and r.get("effect") == "deny" for r in p):
            fail(f"roster: {path} lost the leading 'subagent * deny' row")
    elif op == "api":
        path = sys.argv[2]
        p = perms(path)
        want = [sh("opencode api get /api/session*", "allow"), sh("opencode api patch /api/session/*", "allow")]
        api = [r for r in p if r.get("action") == "shell" and str(r.get("resource", "")).startswith("opencode api")]
        if api != want:
            fail(f"api: {path} opencode-api shell rows are {api}, want exactly the two scoped session allows in order "
                 f"(the in-work-mark containment: no third API grant, no other effect)")
        anchors = [i for i, r in enumerate(p) if r == {"action": "opencode", "resource": "*", "effect": "allow"}]
        if len(anchors) != 1:
            fail(f"api: {path} must carry exactly one opencode '*' allow anchor, found {len(anchors)}")
        first = [i for i, r in enumerate(p) if r in want]
        if not first or p[anchors[0] + 1:anchors[0] + 3] != want:
            fail(f"api: {path} the two session allows must sit directly after the opencode '*' allow (the pinned splice position)")
    elif op == "board":
        path = sys.argv[2]
        p = perms(path)
        deny_at = next((i for i, r in enumerate(p) if r.get("action") == "*" and r.get("resource") == "*" and r.get("effect") == "deny"), None)
        db = [i for i, r in enumerate(p) if r.get("action") == "dev_boards*"]
        if deny_at is None or len(db) != 1 or db[0] < deny_at or p[db[0]].get("effect") != "allow":
            fail(f"board: {path} dev_boards* single allow-after-deny-all shape broken (found deny@{deny_at}, dev_boards@{db})")
        if not any(r.get("action") == "execute" and r.get("resource") == "*" and r.get("effect") == "allow" for r in p):
            fail(f"board: {path} lost the execute allow (Code Mode transport)")
        if any(r.get("action") == "dev*" for r in p):
            fail(f"board: {path} grew the broad dev* allow (D21: narrow dev_boards* only)")
    else:
        fail(f"family.py: unknown subcommand '{op}'"); sys.exit(2)

cmd()
PY

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): the description
# needle-pairs must read as one passage, not as scattered file-wide hits.
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

cat >"$TMP/pairsync.py" <<'PY'
# Source<->generated honesty (coord-inwork convention): bodies equal modulo
# frontmatter/blank space; meaningful frontmatter fields equal once parsed.
# permdelta already pins the parsed PERMISSION equality per pair; this adds
# body + mode/color/name honesty for the cf-58 variant and family pairs.
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

# --- A1: agent-test pair — tests/** allow after the edit-deny pivot (AC1) ------
if want a1; then
  python3 "$TMP/permdelta.py" test "$TEST_SRC" "$TEST_GEN" \
    || fail "A1[AC1]: agent-test tests/** allow contract not satisfied (grant absent — red before C01 dev phase)"
  ok "A1[AC1]: agent-test (source + mirror) carry the edit-deny baseline with the top-level tests/** allow after it; chart/container test allows intact; parsed rule lists identical across the pair"
fi

# --- A2: dev-variant pairs — tests/** deny after the edit-allow pivot (AC2) -----
# cf-58 C02 re-pin: the single pair became TWO variant pairs; the tests/**
# deny-after-pivot contract is asserted on both, and the retired pre-split
# pair is pinned GONE (its presence with a stale mirror is how role renames
# leave silent behavior behind).
if want a2; then
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    [ -f "$f" ] || fail "A2[AC2]: $f missing (red before C02 — the dev-role split has not landed)"
  done
  python3 "$TMP/permdelta.py" dev "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" \
    || fail "A2[AC2]: agent-dev-local tests/** deny contract not satisfied (deny absent — red before C02 dev phase)"
  python3 "$TMP/permdelta.py" dev "$DEV_PR_SRC" "$DEV_PR_GEN" \
    || fail "A2[AC2]: agent-dev-pr tests/** deny contract not satisfied (deny absent — red before C02 dev phase)"
  ok "A2[AC2]: agent-dev-local and agent-dev-pr (sources + mirrors) carry the edit-allow baseline with the top-level tests/** deny after it; chart/container test denies intact; parsed rule lists identical across each pair"
fi

# --- A3: stale-text sweep — matrix rows + drift incident (AC3) -----------------
# cf-58 C02 re-pin: in permissions.md the single dev row becomes the
# dev-local/dev-pr pair of rows and the Drift-incidents section grows the
# split entry. pipeline-overview.md (POV) is NOT edited by any cf-58 chunk
# (its role prose stays), so its row pins hold unchanged.
if want a3; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row test '`tests/**`' \
      || fail "A3[AC3]: $f test row does not name top-level \`tests/**\` (text row unmoved — red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" row dev-local '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f has no dev-local row listing all three test denies (red before C02 — the split matrix rows have not landed)"
    python3 "$TMP/sectgrep.py" "$f" row dev-pr '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f has no dev-pr row listing all three test denies (red before C02 — the split matrix rows have not landed)"
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' '2026-10-26' 'top-level `tests/`' \
      || fail "A3[AC3]: $f no longer records the 2026-10-26 top-level \`tests/\` drift incident (HOLD — the entry must survive the re-pin)"
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' 'agent-dev-pr' 'agent-dev-local' \
      || fail "A3[AC3]: $f drift-history section lacks the C02 split entry naming agent-dev-pr/agent-dev-local (red before C02 dev phase)"
  done
  for f in "$POV_SRC" "$POV_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row test '`tests/**`' \
      || fail "A3[AC3]: $f test row lacks top-level \`tests/**\` (red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" row dev '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f dev row lacks the three test paths (red before C01 dev phase)"
  done
  ok "A3[AC3]: permissions.md (source + mirrors) carries the dev-local/dev-pr split rows and the C02 drift entry; pipeline-overview rows intact; the 2026-10-26 drift incident survives"
fi

# --- A4: pipeline-role-test skill — false claim gone, surface widened (AC4) ----
if want a4; then
  for f in "$RT_SRC" "$RT_GEN"; do
    if grep -qF 'there is no global' "$f"; then
      fail "A4[AC4]: $f still carries the '(there is no global tests/)' claim — it is false (top-level tests/ ships suites) and this ticket deletes it (red before C01 dev phase)"
    fi
    python3 "$TMP/sectgrep.py" "$f" line 'write only test files' 'top-level `tests/`' \
      || fail "A4[AC4]: $f write-surface line does not include top-level \`tests/\` (red before C01 dev phase)"
  done
  ok "A4[AC4]: pipeline-role-test SKILL.md (source + mirror) — false 'no global tests/' claim gone, write-surface line states top-level \`tests/\`"
fi

# --- A5: agents-sync references pairs byte-identical source<->mirror (AC5) -----
if want a5; then
  for pair in "$PERM_SRC|$PERM_GEN" "$POV_SRC|$POV_GEN"; do
    IFS='|' read -r s g <<<"$pair"
    cmp -s "$s" "$g" \
      || fail "A5[AC5]: $s and its generated mirror $g are not byte-identical — rulesync copies these verbatim, so a text edit must land in the source and regenerate"
  done
  ok "A5[AC5]: the two agents-sync references pairs are byte-identical source<->generated (HOLD before and after dev — rulesync copies verbatim)"
fi

# --- A6: regeneration contract (AC5 regen / AC6 hold) --------------------------
if want a6; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "A6: rulesync not resolvable here (PATH or npx cache) — generate --check + no-op gate skipped with warning (c7/t14/i6 precedent)"
    ok "A6[AC5-regen/AC6-hold]: generator gate skipped with warning (ladder found no rulesync)"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "A6[AC5]: rulesync generate --check is not clean — committed generated surfaces are stale against the sources"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "A6[AC5]: rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "A6[AC5]: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "A6[AC5]: the second rulesync generate is not a no-op (sources and generated have drifted)"
    ok "A6[AC5-regen/AC6-hold]: generate --check clean and the second generate is a no-op (via $RS)"
  fi
fi

# --- A7: re-pin HOLD posture — carve present, sanctioned agents-sync delta -----
if want a7; then
  python3 "$TMP/blockwin.py" "$SUITE_GATE" t12 \
    "grep -v -x -E -e '(\\.rulesync|\\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview)\\.md'" \
    || fail "A7[AC6-AC7]: gate.sh t12 lacks the D4 carve exclusion line — the re-pin did not land"
  python3 "$TMP/blockwin.py" "$SUITE_SURFACE" i5 \
    "grep -v -x -E -e '(\\.rulesync|\\.opencode)/skills/agents-sync/references/(permissions|pipeline-overview)\\.md'" \
    || fail "A7[AC6-AC7]: surface.sh i5 lacks the D4 carve exclusion line — the re-pin did not land"
  others=$( { git diff --name-only "$BASE" -- .rulesync/skills/agents-sync .opencode/skills/agents-sync 2>/dev/null || true;
              git ls-files --others --exclude-standard -- .rulesync/skills/agents-sync .opencode/skills/agents-sync; } \
            | grep -Ev "$CARVE_RE" || true )
  [ -z "$others" ] || { printf '%s\n' "$others" >&2; fail "A7[AC6-AC7]: agents-sync paths changed vs $BASE beyond the four carved references files (base: $BASE) — the byte-freeze carve is EXACTLY permissions.md + pipeline-overview.md (source and generated), no other frozen-dir edit is sanctioned"; }
  ok "A7[AC6-AC7]: t12/i5 carve lines present; no agents-sync delta vs $BASE outside the carved four (worktree included)"
fi

# --- A8: parse-safety of every touched suite (AC6-parse-safety) ----------------
if want a8; then
  for f in "$0" "$SUITE_SURFACE" "$SUITE_GATE" "$SUITE_RULESYNC" "$SUITE_AGENTSMD" \
           "$SUITE_PUSH" "$SUITE_STANDALONE" "$SUITE_MODELS"; do
    bash -n "$f" || fail "A8[AC6-parse-safety]: bash -n failed on $f"
  done
  ok "A8[AC6-parse-safety]: all five touched/created suite files + the three cf-58-new suites parse (bash -n)"
fi

# --- A9: follow-up-folder admits inside the three scope blocks (AC9-admits) ----
# cf-58 re-pin: the loop grows a fourth slug — this ticket's own folder must
# be admitted by the same blocks (a scope guard that reds on the mere
# existence of the running ticket's plan folder buries every later check).
if want a9; then
  for slug in 2026-10-bug-kickoff-mints-run-branch 2026-10-bug-session-origin-no-line 2026-10-bug-tests-edit-perms 2026-10-cf-58-feat-standalone-agent-merge; do
    python3 "$TMP/blockwin.py" "$SUITE_GATE" t14 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: gate.sh t14 does not admit $slug inside its if-want block (the D9 widening did not land)"
    python3 "$TMP/blockwin.py" "$SUITE_RULESYNC" c8 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: rulesync-surface.sh c8 does not admit $slug inside its if-want block"
    python3 "$TMP/blockwin.py" "$SUITE_AGENTSMD" c7 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: agents-md.sh c7 does not admit $slug inside its if-want block"
  done
  ok "A9[AC9-admits]: all three 2026-10-bug-* follow-up folders and the cf-58 ticket folder are admitted inside the t14, c8 and c7 blocks (windowed, not file-global)"
fi

# --- A10: cf-58 family-mechanism integrity + negative controls (C03-owned) -----
# Re-PIN history: the old A10 exercised cf-52's splice OR-form (coord files
# = base + exactly two shell allows). C02/C03 supersede that sanctioned delta
# (the git block + roster + alias parity are now part of the coord contract),
# so the OR-form arms are retired; the discipline they encoded — the guard
# must be provably NON-vacuous (fabricated-row controls, never "empty diff
# ⇒ pass") — carries over onto the shipped guards in $TMP/family.py:
#   (a) the repo-history anchors still resolve (the cf-52-era operational
#       bases, now historical facts, and the integrated-line ancestor);
#   (b) parity control: a fabricated extra permission row appended to a copy
#       of an alias twin must make the drift guard REJECT the pair;
#   (c) policy controls: the real -pr file must effectively deny
#       `git push origin main`; stripping the trailing denies from a TMP copy
#       must flip that verdict to allow — proving the deny rows are load-
#       bearing in the shipped matcher, not decorative;
#   (d) documentation discipline: the re-pinned coord-inwork i4 / gate t17
#       blocks keep the arm-aware line twin (atpos + empty-diff branch) and
#       their headers keep naming the historical bases + this ticket.
# RED before C03 (family files absent — the red names them), green after.
if want a10; then
  git rev-parse --verify "${ARM_A}^{commit}" >/dev/null 2>&1 \
    || fail "A10[family-integrity]: historical base $ARM_A not resolvable in this repo"
  git merge-base --is-ancestor "$INTEGRATED" HEAD 2>/dev/null \
    || fail "A10[family-integrity]: HEAD does not include the integrated-line landing $INTEGRATED (historical anchor for the dual-base discipline)"
  [ -f "${CF_SRC[1]}" ] || fail "A10[family-integrity]: ${CF_SRC[1]} missing — the coord-family guards cannot run before C03 (red-before-C03 by design)"
  # (b) parity negative control — one fabricated row must break the drift guard
  python3 - "${CF_SRC[0]}" "${CF_SRC[1]}" "$TMP/fab-alias.md" <<'PY'
import re, sys, yaml
src, twin, dst = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(twin).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, f"{twin}: no frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
perms = list(target.get("permissions") or [])
perms.append({"action": "question", "resource": "opencode api delete /api/session/*", "effect": "allow"})
target["permissions"] = perms
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  if python3 "$TMP/family.py" parity "${CF_SRC[0]}" "$TMP/fab-alias.md" >/dev/null 2>&1; then
    fail "A10[family-integrity]: NEGATIVE CONTROL FAILED — the parity guard accepted a fabricated permission row (it degenerated; alias drift would pass silently)"
  fi
  # (c) push-policy controls on the -pr variant (real file denies main; stripping denies flips it)
  v=$(python3 "$TMP/family.py" policy "${CF_SRC[2]}" 'git push origin main' 2>/dev/null || true)
  [ "$v" = "deny" ] || fail "A10[family-integrity]: effective verdict for 'git push origin main' on agent-coord-pr is '$v', want deny (trailing main deny load-bearing; red-before-C03 when the file is absent)"
  v=$(python3 "$TMP/family.py" policy "${CF_SRC[2]}" 'git push origin feature-x' 2>/dev/null || true)
  [ "$v" = "allow" ] || fail "A10[family-integrity]: effective verdict for 'git push origin feature-x' on agent-coord-pr is '$v', want allow"
  python3 - "${CF_SRC[2]}" "$TMP/pr-stripped.md" <<'PY'
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
perms = [p for p in (target.get("permissions") or [])
         if not (p.get("action") == "shell" and str(p.get("resource", "")).startswith("git push") and p.get("effect") == "deny")]
target["permissions"] = perms
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY
  v=$(python3 "$TMP/family.py" policy "$TMP/pr-stripped.md" 'git push origin main' 2>/dev/null || true)
  [ "$v" = "allow" ] || fail "A10[family-integrity]: NEGATIVE CONTROL FAILED — stripping the trailing deny rows did not flip 'git push origin main' to allow on the TMP copy (matcher is inert; the real guard would pass on drift)"
  # (d) the re-pinned sibling blocks keep their shipped line twins + header discipline
  for f in "$SUITE_SURFACE" "$SUITE_GATE"; do
    python3 "$TMP/blockwin.py" "$f" "$( [ "$f" = "$SUITE_SURFACE" ] && echo i4 || echo t17 )" \
      'git diff --quiet "$BASE"' 'atpos.py' \
      || fail "A10[family-integrity]: $f's re-pinned block lacks the arm-aware line twin (empty-diff branch or atpos call) — the cf-58 re-pin did not land"
  done
  python3 "$TMP/sectgrep.py" "$SUITE_SURFACE" all \
    '081b57889' 'f11bfcb85' '916044893' 'historical' 'arm A' 'arm B' 'cf-58' \
    || fail "A10[family-integrity]: $SUITE_SURFACE header lost the cf-52-era base documentation (arm A/arm B refs, historical markers) or the cf-58 re-pin note"
  python3 "$TMP/sectgrep.py" "$SUITE_GATE" all \
    '081b57889' 'f11bfcb85' '916044893' 'historical' 'arm A' 'arm B' 'cf-58' \
    || fail "A10[family-integrity]: $SUITE_GATE header lost the cf-52-era base documentation (arm A/arm B refs, historical markers) or the cf-58 re-pin note"
  ok "A10[family-integrity]: parity/policy guards reject fabricated drift and flip on stripped denies (negative controls pass), the history anchors resolve, and the re-pinned sibling blocks keep their shipped twins"
fi

# --- A11: agent-dev variant pair — git rows + push policy + wiring (C02) --------
# C02 AC2/AC3: the git block exactly per the Tasks list (reads → add → commit
# → push policy, last-match-wins order), the pr MUST-load of
# /pipeline-push-pr, the local silence about it, the descriptions naming the
# one difference, source<->mirror honesty, and the retired pre-split files
# gone from source AND generated.
if want a11; then
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN" "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    [ -f "$f" ] || fail "A11[C02]: $f missing (red before C02 — the dev-role split has not landed)"
    case "$f" in
      *local*) python3 "$TMP/family.py" gitrows "$f" devlocal || fail "A11[C02]: $f violates the declared devlocal git rows";;
      *pr*)    python3 "$TMP/family.py" gitrows "$f" devpr    || fail "A11[C02]: $f violates the declared devpr git rows";;
    esac
  done
  retired_src=".rulesync/subagents/agent-de""v.md"   # path assembled — A13's own sweep would flag the literal
  retired_gen=".opencode/agents/agent-de""v.md"
  [ ! -f "$retired_src" ] || fail "A11[C02]: $retired_src still present — C02 retires the pre-split source (red before C02)"
  [ ! -f "$retired_gen" ] || fail "A11[C02]: $retired_gen still present — rulesync generate (delete: true) must sweep it (red before C02)"
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN"; do
    v=$(python3 "$TMP/family.py" policy "$f" 'git push origin feature-x' 2>/dev/null || true)
    [ "$v" = "deny" ] || fail "A11[C02]: $f effective push verdict '$v', want deny (the explicit deny is the loud-failure guard)"
  done
  for f in "$DEV_PR_SRC" "$DEV_PR_GEN"; do
    for cmd in 'git push origin main' 'git push HEAD:main' 'git push feature:main' \
               'git push --force origin feature-x' 'git push -f origin feature-x' 'git push origin feature-x --force'; do
      v=$(python3 "$TMP/family.py" policy "$f" "$cmd" 2>/dev/null || true)
      [ "$v" = "deny" ] || fail "A11[C02]: $f '$cmd' verdict '$v', want deny (trailing main/force denies)"
    done
    grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$f" \
      || fail "A11[C02]: $f does not MUST-load /pipeline-push-pr (pr list gains it after /pipeline-role-dev)"
    grep -qF 'pipeline-role-dev' "$f" || fail "A11[C02]: $f lost the /pipeline-role-dev MUST-load (implementer contract unchanged)"
  done
  for f in "$DEV_LOCAL_SRC" "$DEV_LOCAL_GEN"; do
    grep -qF 'pipeline-push-pr' "$f" && fail "A11[C02]: $f references pipeline-push-pr — the local variant must never see the push skill (C02: local's list is unchanged)"
  done
  python3 "$TMP/win.py" "$DEV_LOCAL_SRC" 600 'commits' 'never pushes' \
    || fail "A11[C02]: the local description does not name its difference ('commits only, never pushes' — C02 Tasks)"
  python3 "$TMP/win.py" "$DEV_PR_SRC" 600 'pushes' 'remote build/test' \
    || fail "A11[C02]: the pr description does not name its difference ('pushes the ticket branch for remote build/test' — C02 Tasks)"
  ok "A11[C02]: dev-variant pair carries the declared git rows in order, effective push policy per variant, the pr-only push-skill wiring, naming descriptions; pre-split files retired"
fi

# --- A12: coord family — six files, alias parity, block order, rosters (C03) ----
# C03 AC1-AC3. The alias↔local parity is the drift guard the plan calls the
# ticket's new silent-failure mode; it runs on BOTH the sources (where drift
# is written) and the generated mirrors (where a half-regenerated pair hides).
if want a12; then
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    [ -f "$f" ] || fail "A12[C03]: $f missing (red before C03 — six coord-family agents + mirrors are the C03 shape)"
  done
  python3 "$TMP/family.py" parity "${CF_SRC[0]}" "${CF_SRC[1]}" \
    || fail "A12[C03]: agent-coord alias and agent-coord-local drifted apart (sources) — the same-commit parity rule"
  python3 "$TMP/family.py" parity "${CF_SRC[3]}" "${CF_SRC[4]}" \
    || fail "A12[C03]: agent-board-coord alias and agent-board-coord-local drifted apart (sources)"
  python3 "$TMP/family.py" parity "${CF_GEN[0]}" "${CF_GEN[1]}" \
    || fail "A12[C03]: coord alias/mirror-pair drift on the generated surfaces"
  python3 "$TMP/family.py" parity "${CF_GEN[3]}" "${CF_GEN[4]}" \
    || fail "A12[C03]: board-coord alias/mirror-pair drift on the generated surfaces"
  for i in 0 1 2 3 4 5; do
    f="${CF_SRC[$i]}"; g="${CF_GEN[$i]}"
    python3 "$TMP/family.py" api "$f" || fail "A12[C03]: $f in-work-mark API containment broken"
    python3 "$TMP/family.py" api "$g" || fail "A12[C03]: $g in-work-mark API containment broken"
    case "$f" in
      *-pr) slot=agent-dev-pr; cls=pr;;
      *)    slot=agent-dev-local; cls=local;;
    esac
    python3 "$TMP/family.py" roster "$f" "$slot" || fail "A12[C03]: $f roster dev slot wrong (want $slot)"
    python3 "$TMP/family.py" gitrows "$f" "$cls"  || fail "A12[C03]: $f git block wrong for class $cls"
    case "$f" in
      *board-coord*) python3 "$TMP/family.py" board "$f" || fail "A12[C03]: $f board extras (dev_boards*/execute) broken";;
    esac
    python3 "$TMP/pairsync.py" "$f" "$g" agent \
      || fail "A12[C03]: $f and $g out of sync — regenerate, never hand-edit .opencode/"
  done
  # MUST-load wiring: /pipeline-push-pr ONLY on the -pr pair (sources + mirrors)
  for f in "${CF_SRC[2]}" "${CF_GEN[2]}" "${CF_SRC[5]}" "${CF_GEN[5]}"; do
    grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$f" \
      || fail "A12[C03]: -pr family file $f does not MUST-load /pipeline-push-pr"
  done
  for i in 0 1 3 4; do
    for f in "${CF_SRC[$i]}" "${CF_GEN[$i]}"; do
      grep -qF 'pipeline-push-pr' "$f" && fail "A12[C03]: $f (non-pr) references the push skill — aliases never carry -pr behavior"
    done
  done
  # alias description tags (C03 pins them)
  grep -qF 'commit-only alias of agent-coord-local' "${CF_SRC[0]}" \
    || fail "A12[C03]: the agent-coord alias lacks its '(commit-only alias of agent-coord-local...)' description tag"
  grep -qF 'commit-only alias of agent-board-coord-local' "${CF_SRC[3]}" \
    || fail "A12[C03]: the agent-board-coord alias lacks its '(commit-only alias of agent-board-coord-local...)' description tag"
  ok "A12[C03]: six coord-family agents (+mirrors) exist and sync; alias↔local parity holds; API containment, git-block order, roster dev slots, board extras, and the -pr-only push wiring all carry the C03 shape"
fi

# --- A13: rename sweep + command→agent pairing (C02 AC5 + C03 AC4/AC7) ----------
# Binding surfaces (agent/command sources + generated mirrors) must carry NO
# bare pre-split dev-role reference — a bare name there would re-grant or
# re-launch the retired single agent. Prose mirrors are pinned positively
# instead (roster-row presence + retired-path absence + clean named
# sections); judgment recorded in this file's header. Command pairing is the
# C03 AC4 table, checked in source AND generated frontmatter.
if want a13; then
  hits=$(python3 - <<'PY'
import re, sys, glob
# Build the retired-role pattern without embedding the literal token, so the
# sweep file itself stays clean under its own rule (the token is
# reconstructed from its two halves at runtime).
tok = "agent-de" + "v"
pat = re.compile(tok + r"(?![-]pr|[-]local)")
bad = []
for root in (".rulesync/subagents", ".rulesync/commands", ".opencode/agents", ".opencode/commands"):
    for p in glob.glob(root + "/*.md") + glob.glob(root + "/**/*.md"):
        for i, line in enumerate(open(p), 1):
            if pat.search(line):
                bad.append(f"{p}:{i}: {line.strip()}")
print("\n".join(bad))
PY
)
  # Era split: hits in the dev-role's OWN surfaces must clear with C02;
  # hits inside the coord-family files are C03's roster-rewrite territory
  # (C02's diff is surgical per its chunk), so they only fail once the
  # family exists and still carries the retired reference.
  hits_c02=$(printf '%s\n' "$hits" | grep -v 'agent-coord\|agent-board-coord' || true)
  hits_c03=$(printf '%s\n' "$hits" | grep 'agent-coord\|agent-board-coord' || true)
  [ -z "$hits_c02" ] || { printf '%s\n' "$hits_c02" >&2; fail "A13[C02 AC5]: bare pre-split dev-role reference in a binding surface (wiring that launches/grants the retired agent) — red before C02"; }
  if [ -f .rulesync/subagents/agent-coord-local.md ] && [ -n "$hits_c03" ]; then
    printf '%s\n' "$hits_c03" >&2
    fail "A13[C03 AC7]: the coord-family files exist but still reference the retired dev-role name — the roster rewrite did not land everywhere"
  fi
  tests_hits=$(python3 - <<'PY'
import re, sys, glob
# The suite-side form: a QUOTED roster name (the token inside "..." or '...')
# pins the retired agent inside another suite's roster assertion, and a bare
# case-arm PATH literal re-admits the retired file into a scope allow-set.
# The pinned-copy arm of the standalone suite LEGITIMATELY reads the retired
# agent's block from the ticket base (C04 Tasks), so lines running git show /
# git cat-file against that path are history loads, not wiring — allowed.
tok = "agent-de" + "v"
quoted = re.compile(r"[\"']" + tok + r"[\"']")
casepath = re.compile(r"(\.rulesync/subagents/|\.opencode/agents/)" + tok + r"\.md")
history = re.compile(r"git (show|cat-file)\b")
# Scope: the cf-58 suite files only — every other suite's pins belong to
# other tickets' bases and legitimately name historical paths; requiring
# this ticket to edit them would break one-branch-one-concern.
suites = ["tests/agent-perms/surface.sh", "tests/coord-inwork/surface.sh",
          "tests/agent-board-coord/gate.sh", "tests/agent-board-coord/rulesync-surface.sh",
          "tests/agent-board-coord/agents-md.sh", "tests/pipeline-push-pr/surface.sh",
          "tests/standalone-agents/surface.sh", "tests/pipeline-models/surface.sh"]
bad = []
for p in suites:
    for i, line in enumerate(open(p), 1):
        if quoted.search(line) or (casepath.search(line) and not history.search(line)):
            bad.append(f"{p}:{i}: {line.strip()}")
print("\n".join(bad))
PY
)
  [ -z "$tests_hits" ] || { printf '%s\n' "$tests_hits" >&2; fail "A13[C02 AC5]: a suite still names the retired agent in a roster list or case path — re-pin did not land (red before C02)"; }
  # Two-era prose pin (the pins move where the contract moves): C02's exact
  # roster literal is the wording until C03 rewrites the Agents bullet to
  # name the coord variants; the dev-variant names + pre-split-row absence
  # hold in BOTH eras.
  for f in AGENTS.md "$RULES_SRC"; do
    grep -qF 'dev-pr' "$f" && grep -qF 'dev-local' "$f" \
      || fail "A13[C02 AC5]: $f never names the dev variants (red before C02)"
    grep -qF 'agent-{coord,plan,research,test,dev,review,fuser,board-coord}' "$f" \
      && fail "A13[C02 AC5]: $f still carries the pre-split roster row verbatim (red before C02)"
    if [ -f .rulesync/subagents/agent-coord-local.md ]; then
      for name in agent-coord-local agent-coord-pr agent-board-coord-local agent-board-coord-pr; do
        grep -qF "$name" "$f" || fail "A13[C03 AC7]: $f never names $name — C03's rewritten Agents bullet must carry the coord variants"
      done
      grep -qF '/pipeline-pr' "$f" || fail "A13[C03 AC4]: $f never names the /pipeline-pr command (launch-sentence rewrite)"
    else
      grep -qF 'agent-{coord,plan,research,test,dev-pr,dev-local,review,fuser,board-coord}' "$f" \
        || fail "A13[C02 AC5]: $f lacks C02's pinned post-split roster row — red before C02"
    fi
    if [ -f .rulesync/subagents/agent-coord-local.md ]; then
      # C03-era: the Agents/Feature-pipeline prose has been rewritten, so no
      # bare pre-split dev-role mention may survive there. Pre-C03 the prose
      # lines belong to C03's overview task (C02's diff is surgical per its
      # chunk), so the scan is era-gated like the roster pins above.
      python3 - "$f" <<'PY' || fail "A13[C03 AC7]: $f Agents / Feature-pipeline sections still carry a bare pre-split dev-role reference after the coord rewrite"
import re, sys
tok = "agent-de" + "v"
pat = re.compile(tok + r"(?![-]pr|[-]local)")
section = None
bad = []
for i, line in enumerate(open(sys.argv[1]), 1):
    m = re.match(r"^## +(.+?)\s*$", line)
    if m:
        section = m.group(1)
    if section in ("Agents", "Feature pipeline (agent-*)") and pat.search(line):
        bad.append(f"line {i} in section '{section}'")
print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
    fi
  done
  # C03 AC4 command→agent pairing — source AND generated frontmatter target.
  pair() { # cmd-name  want-agent
    local c="$1" a="$2"
    for d in ".rulesync/commands" ".opencode/commands"; do
      local f="$d/$c.md"
      [ -f "$f" ] || fail "A13[C03 AC4]: $f missing (red before C03 — the -pr commands ship with the family)"
      grep -qE "^([[:space:]]*)?agent:[[:space:]]+$a\$" "$f" \
        || { grep -n 'agent:' "$f" >&2 || true; fail "A13[C03 AC4]: $f does not target agent $a"; }
    done
  }
  pair pipeline agent-coord
  pair pipeline-resume agent-coord
  pair pipeline-boards agent-board-coord
  pair pipeline-boards-hourly agent-board-coord
  pair pipeline-pr agent-coord-pr
  pair pipeline-resume-pr agent-coord-pr
  pair pipeline-boards-pr agent-board-coord-pr
  # the hourly command never points at a -pr variant (an unattended run never pushes)
  ! grep -qE 'agent:[[:space:]]+.*-pr' .rulesync/commands/pipeline-boards-hourly.md .opencode/commands/pipeline-boards-hourly.md \
    || fail "A13[C03 AC4]: pipeline-boards-hourly targets a -pr agent — scheduled runs stay -local semantics (R2)"
  # pointer lines on the four plain commands (C03 Tasks)
  grep -qF '/pipeline-pr' .rulesync/commands/pipeline.md \
    || fail "A13[C03 AC4]: pipeline.md lacks the '/pipeline-pr' pointer line (red before C03)"
  grep -qF '/pipeline-pr' .rulesync/commands/pipeline-resume.md \
    || fail "A13[C03 AC4]: pipeline-resume.md lacks the '/pipeline-pr' pointer line (red before C03)"
  grep -qF '/pipeline-boards-pr' .rulesync/commands/pipeline-boards.md \
    || fail "A13[C03 AC4]: pipeline-boards.md lacks the '/pipeline-boards-pr' pointer line (red before C03)"
  grep -qF '/pipeline-boards-pr' .rulesync/commands/pipeline-boards-hourly.md \
    || fail "A13[C03 AC4]: hourly command lacks the '/pipeline-boards-pr' pointer line (red before C03)"
  ok "A13[C02 AC5 + C03 AC4/AC7]: binding surfaces and suites free of the retired dev-role wiring; AGENTS.md/rules roster row present; seven commands pair to the right agents (plain→aliases, -pr→variants, hourly never -pr); pointer lines landed"
fi

printf 'PASS: agent-perms contract checks (%d ok)\n' "$checks"
