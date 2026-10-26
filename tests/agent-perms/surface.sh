#!/usr/bin/env bash
# agent-test / agent-dev top-level tests/** permission contract suite
# (2026/2026-10-bug-tests-edit-perms, C01).
#
# Pins the invariant this ticket creates: the agent-* permission blocks know
# top-level `tests/` exists — agent-test may write the repo-validation suites
# under it (last-match after its `edit * deny`), agent-dev may not (last-match
# after its `edit * allow`), the role-matrix/skill prose says so, and the
# regenerated mirrors are honest. Contract source: plan file Goal +
# chunks/C01.md AC1-AC9; DECISIONS D2-D5 (the blocks' blind spot) and D9-D12
# (the post-landing base-posture fold-in) are binding.
#
# AC trace: A1[AC1] A2[AC2] A3[AC3] A4[AC4] A5[AC5-pairs]
# A6[AC5-regen/AC6-hold] A7[AC6-AC7] A8[AC6-parse-safety] A9[AC9-admits]
# A10[AC9-or-form].
#
# Red before the dev phase (by design): A1-A4 — the permission rows and the
# text rows do not exist yet; every red line names the missing rule/row, never
# a harness fault. A5-A8 are HOLD posture (green now, must stay green). A9/A10
# pinned the TEST phase's own suite re-pins (folder admits + the i4/t17
# OR-form), so they are green from this file's landing and HOLD through dev.
# After dev lands (T5-T8), `bash tests/agent-perms/surface.sh` must pass fully.
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
#   bash tests/agent-perms/surface.sh            # A1..A10
#   bash tests/agent-perms/surface.sh A1 A4      # subset (ids case-insensitive)
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
DEV_SRC=".rulesync/subagents/agent-dev.md"
DEV_GEN=".opencode/agents/agent-dev.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"
POV_SRC=".rulesync/skills/agents-sync/references/pipeline-overview.md"
POV_GEN=".opencode/skills/agents-sync/references/pipeline-overview.md"
RT_SRC=".rulesync/skills/pipeline-role-test/SKILL.md"
RT_GEN=".opencode/skills/pipeline-role-test/SKILL.md"
COORD_SRC=".rulesync/subagents/agent-coord.md"
COORD_GEN=".opencode/agents/agent-coord.md"
BCOORD_SRC=".rulesync/subagents/agent-board-coord.md"
BCOORD_GEN=".opencode/agents/agent-board-coord.md"
SUITE_SURFACE="tests/coord-inwork/surface.sh"
SUITE_GATE="tests/agent-board-coord/gate.sh"
SUITE_RULESYNC="tests/agent-board-coord/rulesync-surface.sh"
SUITE_AGENTSMD="tests/agent-board-coord/agents-md.sh"

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
  for i in $(seq 1 10); do WANT["a$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^a([1-9]|10)$ ]] || fail "unknown check id '$a' (expected A1..A10)"
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

cat >"$TMP/fabricate.py" <<'PY'
# A10 negative control (AC9(iii)): copy a healthy coord file into a TMP edit
# and append one fabricated permission ROW to the parsed block (the row lives
# after the pinned delta, so the delta mechanism is the only component that
# can see it — which is exactly what the control proves: the redesigned
# checks must NOT degenerate into "empty diff => pass").
import re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
assert m, f"{src}: no frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
outer = fm.get("opencode")
key = "opencode" if isinstance(outer, dict) and "permissions" in outer else None
target = outer if key else fm
perms = target.get("permissions") or []
perms.append({"action": "question", "resource": "opencode api delete /api/session/*", "effect": "allow"})
target["permissions"] = perms
if key:
    fm["opencode"] = target
open(dst, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False, width=10**6) + "---\n" + m.group(2))
PY

# A10 runs the REDESIGNED mechanisms as shipped — extracted from the suites'
# own text (splice.py verbatim; t17's inline heredoc by line markers) so the
# proof is of the real artifact, not a copy that could drift.
extract_splice() {
  sed -n '/^cat >"\$TMP\/splice\.py" <<'"'"'PY'"'"'$/,/^PY$/p' "$SUITE_SURFACE" | sed '1d;$d' > "$1"
}
extract_t17() {
  # gate.sh keeps t17's delta python inline; surface.sh keeps the same
  # contract as splice.py. Extract gate.sh's copy by its heredoc markers.
  awk "/python3 - \\\"\\\$TMP\\/base-fm-\\\$n\\.md\\\"/{f=1;next} f && /^EOF\$/{exit} f" "$SUITE_GATE" > "$1"
}

# --- A1: agent-test pair — tests/** allow after the edit-deny pivot (AC1) ------
if want a1; then
  python3 "$TMP/permdelta.py" test "$TEST_SRC" "$TEST_GEN" \
    || fail "A1[AC1]: agent-test tests/** allow contract not satisfied (grant absent — red before C01 dev phase)"
  ok "A1[AC1]: agent-test (source + mirror) carry the edit-deny baseline with the top-level tests/** allow after it; chart/container test allows intact; parsed rule lists identical across the pair"
fi

# --- A2: agent-dev pair — tests/** deny after the edit-allow pivot (AC2) ------
if want a2; then
  python3 "$TMP/permdelta.py" dev "$DEV_SRC" "$DEV_GEN" \
    || fail "A2[AC2]: agent-dev tests/** deny contract not satisfied (deny absent — red before C01 dev phase)"
  ok "A2[AC2]: agent-dev (source + mirror) carry the edit-allow baseline with the top-level tests/** deny after it; chart/container test denies intact; parsed rule lists identical across the pair"
fi

# --- A3: stale-text sweep — matrix rows + drift incident (AC3) -----------------
if want a3; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row test '`tests/**`' \
      || fail "A3[AC3]: $f test row does not name top-level \`tests/**\` (text row unmoved — red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" row dev '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f dev row does not list all three test denies incl. top-level \`tests/**\` (red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" section 'Drift incidents' '2026-10-26' 'top-level `tests/`' \
      || fail "A3[AC3]: $f has no 2026-10-26 drift-incident entry naming the top-level \`tests/\` blind spot (red before C01 dev phase)"
  done
  for f in "$POV_SRC" "$POV_GEN"; do
    python3 "$TMP/sectgrep.py" "$f" row test '`tests/**`' \
      || fail "A3[AC3]: $f test row lacks top-level \`tests/**\` (red before C01 dev phase)"
    python3 "$TMP/sectgrep.py" "$f" row dev '`charts/**/tests/**`' '`containers/**/tests/**`' '`tests/**`' \
      || fail "A3[AC3]: $f dev row lacks the three test paths (red before C01 dev phase)"
  done
  ok "A3[AC3]: permissions.md + pipeline-overview.md (source + mirrors) describe top-level tests/** in the test/dev rows; the 2026-10-26 drift incident is recorded"
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
  for f in "$0" "$SUITE_SURFACE" "$SUITE_GATE" "$SUITE_RULESYNC" "$SUITE_AGENTSMD"; do
    bash -n "$f" || fail "A8[AC6-parse-safety]: bash -n failed on $f"
  done
  ok "A8[AC6-parse-safety]: all five touched/created suite files parse (bash -n)"
fi

# --- A9: follow-up-folder admits inside the three scope blocks (AC9-admits) ----
if want a9; then
  for slug in 2026-10-bug-kickoff-mints-run-branch 2026-10-bug-session-origin-no-line 2026-10-bug-tests-edit-perms; do
    python3 "$TMP/blockwin.py" "$SUITE_GATE" t14 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: gate.sh t14 does not admit $slug inside its if-want block (the D9 widening did not land)"
    python3 "$TMP/blockwin.py" "$SUITE_RULESYNC" c8 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: rulesync-surface.sh c8 does not admit $slug inside its if-want block"
    python3 "$TMP/blockwin.py" "$SUITE_AGENTSMD" c7 ".agents/plans/2026/$slug/*" \
      || fail "A9[AC9-admits]: agents-md.sh c7 does not admit $slug inside its if-want block"
  done
  ok "A9[AC9-admits]: all three 2026-10-bug-* follow-up folders are admitted inside the t14, c8 and c7 blocks (windowed, not file-global)"
fi

# --- A10: the OR-form semantics, offline-deterministic (AC9-or-form) -----------
# Runs the redesigned delta mechanism as shipped (extracted from surface.sh's
# splice.py and gate.sh's t17 heredoc) on TMP fixtures: (a) arm A passes at
# the landing parent, (b) arm B passes at the committed base — today's
# exact-delta form could not (the fold-in's designed RED), (c) a fabricated
# extra row fails BOTH arms (AC9(iii)), (d) the headers document the
# both-operational-bases discipline and both mechanisms carry the arm logic.
if want a10; then
  git rev-parse --verify "${ARM_A}^{commit}" >/dev/null 2>&1 \
    || fail "A10[AC9-or-form]: operational base $ARM_A not resolvable in this repo"
  git merge-base --is-ancestor "$INTEGRATED" HEAD 2>/dev/null \
    || fail "A10[AC9-or-form]: HEAD does not include the integrated-line landing $INTEGRATED — the both-bases discipline is defined for main >= $INTEGRATED"
  extract_splice "$TMP/splice-shipped.py"
  extract_t17 "$TMP/t17-shipped.py"
  [ -s "$TMP/splice-shipped.py" ] || fail "A10[AC9-or-form]: could not extract splice.py from $SUITE_SURFACE (heredoc markers moved — re-pin the extractor)"
  [ -s "$TMP/t17-shipped.py" ] || fail "A10[AC9-or-form]: could not extract t17's delta heredoc from $SUITE_GATE (markers moved — re-pin the extractor)"
  for mech in "$TMP/splice-shipped.py" "$TMP/t17-shipped.py"; do
    grep -qF 'arm B' "$mech" || fail "A10[AC9-or-form]: $(basename "$mech") has no arm-B component — the OR-form redesign did not land (empty-diff posture would fail)"
  done
  n=0
  for f in "$COORD_SRC" "$COORD_GEN" "$BCOORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    git show "$ARM_A:$f" >"$TMP/a10-baseA-$n.md" 2>/dev/null || fail "A10: $f not readable at $ARM_A"
    git show "$ARM_B:$f" >"$TMP/a10-baseB-$n.md" 2>/dev/null || fail "A10: $f not readable at $ARM_B"
    for base in A B; do
      python3 "$TMP/splice-shipped.py" "$TMP/a10-base$base-$n.md" "$f" "$adb" \
        || fail "A10[AC9-or-form]: shipped splice.py rejects $f at operational base $base (arm A=delta-present, arm B=committed-idempotence — one of them must pass)"
      python3 "$TMP/t17-shipped.py" "$TMP/a10-base$base-$n.md" "$f" "$adb" \
        || fail "A10[AC9-or-form]: shipped t17 heredoc rejects $f at operational base $base"
    done
  done
  # (c) negative control: one fabricated extra permission row, both arms fail.
  n=0
  for f in "$COORD_SRC" "$BCOORD_GEN"; do
    n=$((n + 1))
    case "$f" in *agent-board-coord*) adb=dev-boards ;; *) adb=none ;; esac
    python3 "$TMP/fabricate.py" "$f" "$TMP/a10-fab-$n.md"
    for base in A B; do
      if python3 "$TMP/splice-shipped.py" "$TMP/a10-base$base-$n.md" "$TMP/a10-fab-$n.md" "$adb" >/dev/null 2>&1; then
        fail "A10[AC9-or-form]: NEGATIVE CONTROL FAILED — splice.py accepted a fabricated extra permission row at base $base (the OR-form degenerated; empty-diff must not imply pass)"
      fi
      if python3 "$TMP/t17-shipped.py" "$TMP/a10-base$base-$n.md" "$TMP/a10-fab-$n.md" "$adb" >/dev/null 2>&1; then
        fail "A10[AC9-or-form]: NEGATIVE CONTROL FAILED — t17 accepted the fabricated row at base $base"
      fi
    done
  done
  # (d) documentation discipline: both headers name the operational bases and
  # mark the pre-landing refs historical; the re-pinned blocks carry the twin.
  for f in "$SUITE_SURFACE" "$SUITE_GATE"; do
    python3 "$TMP/blockwin.py" "$f" "$( [ "$f" = "$SUITE_SURFACE" ] && echo i4 || echo t17 )" \
      'git diff --quiet "$BASE"' 'atpos.py' \
      || fail "A10[AC9-or-form]: $f's re-pinned block lacks the arm-aware line twin (empty-diff branch or atpos call)"
  done
  python3 "$TMP/sectgrep.py" "$SUITE_SURFACE" all \
    '081b57889' 'f11bfcb85' '916044893' 'historical' 'arm A' 'arm B' \
    || fail "A10[AC9-or-form]: $SUITE_SURFACE header does not name both operational bases and the historical pre-landing refs"
  python3 "$TMP/sectgrep.py" "$SUITE_GATE" all \
    '081b57889' 'f11bfcb85' '916044893' 'historical' 'arm A' 'arm B' \
    || fail "A10[AC9-or-form]: $SUITE_GATE header does not name both operational bases and the historical pre-landing refs"
  ok "A10[AC9-or-form]: both shipped mechanisms pass arm A at $ARM_A and arm B at $ARM_B on all four coord files, reject a fabricated row at both arms, and the headers document the both-operational-bases discipline"
fi

printf 'PASS: agent-perms contract checks (%d ok)\n' "$checks"
