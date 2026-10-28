#!/usr/bin/env bash
# validation-fix routing contract (2026/2026-10-cf-75-bug-wekan-mcp-skill,
# C02): a validation_at_fault verdict no longer costs a user question.
# Mechanical repairs route SILENTLY back to the test_session that authored
# the validation; the TEST session returns NEEDS_INFO when a fix would modify
# functionality; only then does coord escalate — and a moved plan gets
# needs-replan. Pins the new wording on the .rulesync/skills SOURCES and their
# regenerated .opencode/skills MIRRORS alike, plus the agents-sync references
# and AGENTS.md, and proves source and generated surfaces never diverge
# (divergence = a hand-edited mirror or a skipped regenerate; both fail here).
#
# Contract source: chunks/C02.md "## Tests" + plan Goal/OQ6 + DECISIONS
# (adjudicator wording). AC trace: t1[AC1] t2[AC2] t3[AC3] t4[AC4] t5[AC5]
# t6[AC6] t7[AC7].
#
# Red before C02: t1-t5 fail on the old "Always ask the user — no exceptions"
# wording still living in the sources; t6/t7 are green at the base and HOLD
# (regression + commit-shape guards). t7's child suites carry their own
# red posture; this file only requires them to pass.
#
# Legit user questions the rewrite must NOT touch (t2/t4 pin them as
# regressions): the retry cap question, the BLOCKED/NEEDS_INFO generic ask,
# the deviation/replan ask, kickoff and friction-round questions, the
# frozen 2026-10-21 drift-history line.
#
# Usage:
#   bash tests/pipeline-gates/validation-fix.sh            # t1..t7
#   bash tests/pipeline-gates/validation-fix.sh t1 t4      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

COORD_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
COORD_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
GATES_SRC=".rulesync/skills/pipeline-gates/SKILL.md"
GATES_GEN=".opencode/skills/pipeline-gates/SKILL.md"
REVIEW_SRC=".rulesync/skills/pipeline-role-review/SKILL.md"
REVIEW_GEN=".opencode/skills/pipeline-role-review/SKILL.md"
AS_SRC=".rulesync/skills/agents-sync/references"
AS_GEN=".opencode/skills/agents-sync/references"
RULES_SRC=".rulesync/rules/overview.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/validation-fix-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-7])$ ]] || fail "unknown test id '$a' (expected t1..t7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Passage extractors are anchored on the structures C02 promises to KEEP
# (the "d." step letter, the "- `validation_at_fault`" bullet head) so the
# rewrite can move any wording inside them while the fences stay findable.
cat >"$TMP/step2d.py" <<'PY'
# Extract coord role-contract step 2.d: the d. line naming validation_at_fault
# through the next top-level numbered step.
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'(?ms)^[ \t]*d\.[^\n]*validation_at_fault[^\n]*\n(?:.*?\n)*?(?=^[ \t]*[0-9]+\. )', text)
if not m:
    m = re.search(r'(?ms)^[ \t]*d\.[^\n]*validation_at_fault[^\n]*\n.*', text)
if not m:
    print("no step 2.d (a d. line naming validation_at_fault) found"); sys.exit(2)
sys.stdout.write(m.group(0))
PY

cat >"$TMP/bullet.py" <<'PY'
# Extract the gates validation_at_fault bullet: its head line through the
# next "- " bullet or end of list.
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'(?ms)^- [^\n]*validation_at_fault[^\n]*(?:\n(?!- |#)[^\n]*)*', text)
if not m:
    print("no validation_at_fault bullet found"); sys.exit(2)
sys.stdout.write(m.group(0))
PY

# --- t1: coord step 2.d — silent route + test-session adjudication (C02 AC1) ----
if want t1; then
  for f in "$COORD_SRC" "$COORD_GEN"; do
    [ -f "$f" ] || fail "t1: $f missing"
    python3 "$TMP/step2d.py" "$f" >"$TMP/step2d.txt" || fail "t1: $f has no step 2.d naming validation_at_fault"
    python3 - "$f" "$TMP/step2d.txt" <<'PY' || fail "t1: step 2.d violates the routing contract (reason above)"
import re, sys
passage = open(sys.argv[2]).read()
errs = []
if not re.search(r"silent", passage, re.I):
    errs.append("no silent-route token (silently/SILENTLY) — mechanical fixes must route without a question")
if "test_session" not in passage:
    errs.append("no test_session reference — the fix routes back to the authoring session")
if re.search(r"always ask the user", passage, re.I):
    errs.append("step 2.d still carries 'always ask the user'")
if re.search(r"no exceptions", passage, re.I):
    errs.append("step 2.d still carries 'no exceptions'")
if "NEEDS_INFO" not in passage:
    errs.append("no NEEDS_INFO escalation from the TEST session")
if not re.search(r"functionality", passage, re.I):
    errs.append("no functionality-change adjudication wording")
if "needs-replan" not in passage:
    errs.append("no needs-replan mark for the moved-plan case")
if errs:
    print(f"{sys.argv[1]}: " + "; ".join(errs)); sys.exit(1)
PY
  done
  ok "t1: coord step 2.d (source + mirror) — silent route to test_session, NEEDS_INFO functionality escalation, needs-replan; no always-ask wording left"
fi

# --- t2: gates bullet — same semantics, legit questions untouched (C02 AC2) -----
if want t2; then
  for f in "$GATES_SRC" "$GATES_GEN"; do
    [ -f "$f" ] || fail "t2: $f missing"
    if grep -qi 'no exceptions' "$f"; then
      fail "t2: $f still carries 'no exceptions' (C02 AC2 retires it for validation_at_fault)"
    fi
    python3 "$TMP/bullet.py" "$f" >"$TMP/bullet.txt" || fail "t2: $f lost its validation_at_fault bullet entirely"
    python3 - "$f" "$TMP/bullet.txt" <<'PY' || fail "t2: the gates bullet violates the new rule wording (reason above)"
import re, sys
passage = open(sys.argv[2]).read()
errs = []
if "test_session" not in passage:
    errs.append("bullet lost the test_session routing target")
if not re.search(r"silent|automat|without a question", passage, re.I):
    errs.append("bullet carries no auto-route token (silently / automatically / without a question)")
if "NEEDS_INFO" not in passage:
    errs.append("bullet carries no NEEDS_INFO escalation from the test session")
if not re.search(r"functionality|changes? what the (plan|build)", passage, re.I):
    errs.append("bullet carries no functionality-escalation token")
if errs:
    print(f"{sys.argv[1]}: " + "; ".join(errs)); sys.exit(1)
PY
    grep -qi 'ask the user with options: more rounds' "$f" \
      || fail "t2: $f lost the retry-cap question (legit user question — must survive unchanged)"
    grep -qi 'ask the user if the question needs them' "$f" \
      || fail "t2: $f lost the BLOCKED-or-NEEDS_INFO generic ask (legit user question — must survive unchanged)"
  done
  ok "t2: gates bullet (source + mirror) routes silently with the functionality-escalation clause; retry-cap and generic BLOCKED/NEEDS_INFO asks intact"
fi

# --- t3: review posture — never edits, no user-confirmation clause (C02 AC3) ----
if want t3; then
  for f in "$REVIEW_SRC" "$REVIEW_GEN"; do
    [ -f "$f" ] || fail "t3: $f missing"
    grep -qF 'never edit' "$f" || fail "t3: $f lost the 'never edit' posture"
    grep -qF 'edit neither implementation code nor validation files' "$f" \
      || fail "t3: $f lost the hard-rule never-edit sentence (reviewer posture must be unchanged)"
    if grep -qF "with the user's confirmation" "$f"; then
      fail "t3: $f still requires the user's confirmation for routing a faulty validation (C02 AC3 drops it)"
    fi
  done
  ok "t3: review (source + mirror) keeps the never-edit posture and no longer conditions routing on user confirmation (C02 AC3)"
fi

# --- t4: old phrasing dead, remaining asks on the enumerated allow-list (AC4) ----
if want t4; then
  UNION=(AGENTS.md "$RULES_SRC" "$COORD_SRC" "$COORD_GEN" "$GATES_SRC" "$GATES_GEN" \
         "$REVIEW_SRC" "$REVIEW_GEN")
  for d in "$AS_SRC" "$AS_GEN"; do
    for f in "$d"/*.md; do UNION+=("$f"); done
  done
  printf '%s\n' "${UNION[@]}" >"$TMP/union.txt"
  python3 - "$TMP/union.txt" <<'PY' || fail "t4: the old contract wording or an unenumerated ask survives (reason above)"
import re, sys
files = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
# Whitespace is collapsed before matching: AGENTS.md wraps sentences, and a
# line-boundary-blind grep would let "coord asks the user and\nroutes" live on
# as two innocent-looking lines.
OLD = [r"coord asks the user \(always", r"asks the user and\s+routes"]
ALLOW = [
    r"can ask the user questions",        # role capability, agents-sync overview
    r"targeted questions",               # intake kickoff (coord step 1)
    r"which one",                        # feature-folder picker (coord step 2)
    r"multi-select",                     # friction follow-up round
    r"more rounds",                      # retry cap (gates / plan-and-result)
    r"if the question needs them",       # generic BLOCKED/NEEDS_INFO (gates)
    r"needs-replan",                     # deviation-to-replan ask (gates)
    r"NEEDS_INFO",                       # new-contract escalation sentence
    r"functionality",                    # new-contract adjudication sentence
    r"2026-10-21",                       # permissions.md frozen drift-history
    r"kickoff", r"friction", r"escalat",  # context words for the legit asks
]
errs = []
for path in files:
    text = open(path).read()
    flat = re.sub(r"\s+", " ", text)
    for pat in OLD:
        if re.search(pat, flat, re.I):
            errs.append(f"{path}: old-contract phrasing /{pat}/ still present")
    for i, line in enumerate(text.splitlines(), 1):
        if not re.search(r"asks? the user", line, re.I):
            continue
        if any(re.search(a, line, re.I) for a in ALLOW):
            continue
        errs.append(f"{path}:{i}: unenumerated 'ask the user' hit: {line.strip()[:90]}")
if errs:
    print("\n".join(errs)); sys.exit(1)
PY
  ok "t4: zero old-phrasing hits across the union; every surviving 'ask the user' line matches the enumerated allow-list (C02 AC4)"
fi

# --- t5: permissions.md drift history frozen + CORRECTED annotation (C02 AC5) ---
if want t5; then
  for f in "$AS_SRC/permissions.md" "$AS_GEN/permissions.md"; do
    [ -f "$f" ] || fail "t5: $f missing"
    grep -qF '2026-10-21 (same day, user corrections)' "$f" \
      || fail "t5: $f lost the 2026-10-21 drift-history bullet (frozen history — C02 AC5)"
    grep -qF 'coord asks the user, the fix routes to the authoring session' "$f" \
      || fail "t5: the 2026-10-21 history bullet was REWRITTEN — history is kept verbatim; only a dated CORRECTED annotation may follow it"
    python3 - "$f" <<'PY' || fail "t5: no dated CORRECTED annotation after the history bullet (reason above)"
import re, sys
lines = open(sys.argv[1]).read().splitlines()
hist = [i for i, l in enumerate(lines) if "2026-10-21 (same day, user corrections)" in l]
if not hist:
    print("history bullet not found"); sys.exit(1)
corr = [i for i, l in enumerate(lines) if "CORRECTED" in l]
if not corr or max(corr) < min(hist):
    print(f"no CORRECTED annotation at-or-after the history bullet (hist {hist}, corrected {corr})"); sys.exit(1)
if not any(re.search(r"2026-\d\d-\d\d", lines[i]) for i in corr if i >= min(hist)):
    print("the CORRECTED annotation is not dated yyyy-mm-dd"); sys.exit(1)
PY
  done
  ok "t5: permissions.md (source + mirror) keeps the frozen 2026-10-21 bullet verbatim with a dated CORRECTED annotation after it (C02 AC5)"
fi

# --- t6: source/generated parity + regen + same-commit discipline (C02 AC6) -----
if want t6; then
  # rulesync copies references/*.md verbatim but rewrites SKILL.md frontmatter
  # (folds description, reorders keys) and re-serializes the body's edge
  # whitespace (the mirror drops the source's blank line after the closing
  # ---). Parity is therefore the stripped BODY: text after the frontmatter
  # block, edge whitespace normalized. A content delta with no regenerated
  # mirror is a hand-edited surface or a skipped regenerate — both fail here.
  for pair in "$COORD_SRC|$COORD_GEN" "$GATES_SRC|$GATES_GEN" "$REVIEW_SRC|$REVIEW_GEN"; do
    IFS='|' read -r s g <<<"$pair"
    [ -f "$s" ] && [ -f "$g" ] || fail "t6: pair file missing ($s / $g)"
    python3 - "$s" "$g" <<'PY' || fail "t6: source and generated mirror diverged ($s vs $g)"
import re, sys
def body(p):
    text = open(p).read()
    m = re.match(r"^---\n.*?\n---\n", text, re.S)
    return (text[m.end():] if m else text).strip() + "\n"
a, b = body(sys.argv[1]), body(sys.argv[2])
if a != b:
    import difflib
    d = list(difflib.unified_diff(a.splitlines(True), b.splitlines(True), sys.argv[1], sys.argv[2], lineterm=""))
    print("\n".join(d[:15])); sys.exit(1)
PY
  done
  for pair in "$AS_SRC/permissions.md|$AS_GEN/permissions.md" \
              "$AS_SRC/pipeline-overview.md|$AS_GEN/pipeline-overview.md" \
              "$AS_SRC/plan-and-result.md|$AS_GEN/plan-and-result.md"; do
    IFS='|' read -r s g <<<"$pair"
    cmp -s "$s" "$g" || fail "t6: $s and its generated mirror $g differ byte-for-byte (rulesync copies these verbatim — regenerate, never hand-edit)"
  done
  RS=""
  if command -v rulesync >/dev/null 2>&1; then RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "t6: rulesync not resolvable here — generate --check skipped with warning (c7/t14 ladder precedent)"
    ok "t6: mirror parity holds (regen gate skipped with warning)"
  else
    timeout 180 $RS generate --check >"$TMP/rscheck.log" 2>&1 \
      || { tail -n 15 "$TMP/rscheck.log" >&2; fail "t6: rulesync generate --check not clean — committed generated surfaces are stale"; }
    ok "t6: mirror parity + rulesync generate --check clean via $RS (C02 AC6)"
  fi
  # Same-commit discipline: any commit moving a C02 source must move its
  # generated surface in the same commit. Vacuously green pre-landing (the
  # range holds only plan commits); review re-runs it after dev commits.
  TB=$(git merge-base main HEAD 2>/dev/null || git rev-parse HEAD)
  checked=0
  while read -r sha; do
    [ -n "$sha" ] || continue
    touched=$(git show --name-only --format= "$sha")
    src_hits=$(printf '%s\n' "$touched" | grep -E '^(\.rulesync/skills/(pipeline-role-coord|pipeline-gates|pipeline-role-review)/|\.rulesync/skills/agents-sync/|\.rulesync/rules/)' || true)
    [ -n "$src_hits" ] || continue
    gen_hits=$(printf '%s\n' "$touched" | grep -E '^(\.opencode/skills/|AGENTS\.md)' || true)
    [ -n "$gen_hits" ] || { echo "$sha moves C02 sources ($src_hits) but no generated surface" >&2; fail "t6: source/generated split across commits — commit them together"; }
    checked=$((checked + 1))
  done < <(git log --format=%H "$TB..HEAD" 2>/dev/null || true)
  ok "t6: commit-shape guard holds ($checked source commits in $TB..HEAD each carry their generated surfaces; pre-landing this is vacuously green)"
fi

# --- t7: existing suites stay green (C02 AC7) -----------------------------------
if want t7; then
  # env -u CHUNK_BASE pins the chain to each child suite's documented default
  # shape: this suite never reads CHUNK_BASE itself, so an ambient base from
  # the caller's shell re-based the children's scope guards by accident (cf-75
  # final-review: that leak made t7 read as an independent failure of suites
  # that were green). Base-shape probes belong in direct suite invocations.
  for s in tests/agent-perms/surface.sh tests/standalone-agents/surface.sh \
           tests/agent-board-coord/rulesync-surface.sh tests/agent-board-coord/agents-md.sh \
           tests/agent-board-coord/gate.sh; do
    log="$TMP/$(basename "$s").log"
    if env -u CHUNK_BASE timeout 600 bash "$s" >"$log" 2>&1; then
      :
    else
      tail -n 20 "$log" >&2
      fail "t7: bash $s failed (log: $log) — C02 must keep every listed suite green"
    fi
  done
  ok "t7: agent-perms, standalone-agents, rulesync-surface, agents-md and gate suites all pass (C02 AC7)"
fi

printf 'PASS: pipeline-gates validation-fix checks (%d ok)\n' "$checks"
