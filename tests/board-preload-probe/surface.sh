#!/usr/bin/env bash
# board-preload-probe script + grant contract suite
# (2026/2026-10-chore-board-tick-cleanup, C03 T2 / OQ-N1, user-approved
# gate round 2026-10-29: scripts/board-preload-probe.sh behind ONE scoped
# bash allow on all six coord variants, same-commit matrix + suite re-pins).
#
# This is the designed-red carrier for the probe wave — the legacy SHELL
# suites (coord-inwork i4, gate t17, kickoff m4, session-origin s4) ADMIT the
# sixth sanctioned shell row so they stay green in every era; the absolute
# "the probe capability exists NOW, exactly and contained" duty lives here,
# the session-origin s4 posture one ticket later.
#
# AC trace: B1[C03 AC4 shape: script exists, machine-checkable PROBE lines,
#   legs + fail-loud] B2[OQ-N1 grant: one scoped row, six sources + six mirrors,
#   uniform position, no broader mint] B3[effective verdict: the granted call
#   evaluates allow on every coord file] B4[permissions.md moves with the
#   rows: coord/board-coord matrix cells + drift entry] B5[containment: the
#   grant names only the six coord files; no api-post or opencode-run widening].
#
# Red posture: every arm is red until C03 dev lands the script + rows
# (each red names the missing artifact). After T2 lands, HOLD forever.
#
# Offline-deterministic: parses the trees; the probe script is NEVER executed
# here — its legs mint live sessions (agent-owned runbook, plan Commands
# "Probe legs ... not CI-runnable"). Existence/shape/grant pins only.
#
# Usage:
#   bash tests/board-preload-probe/surface.sh          # B1..B5
#   bash tests/board-preload-probe/surface.sh B2       # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SCRIPT="scripts/board-preload-probe.sh"
PROBE_RES='bash scripts/board-preload-probe.sh *'
CF_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
        .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
        .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
CF_GEN=(.opencode/agents/agent-coord.md .opencode/agents/agent-coord-local.md
        .opencode/agents/agent-coord-pr.md .opencode/agents/agent-board-coord.md
        .opencode/agents/agent-board-coord-local.md .opencode/agents/agent-board-coord-pr.md)
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/board-preload-probe-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["b$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^b[1-5]$ ]] || fail "unknown check id '$a' (expected B1..B5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- B1: the script itself (C03 T2: deterministic pass/fail lines, fail-loud) ---
if want b1; then
  [ -f "$SCRIPT" ] || fail "B1[C03 T2]: $SCRIPT missing — the agent-owned live-fire has no capability (red before C03 dev; OQ-N1 grant lands script + row together)"
  [ -x "$SCRIPT" ] || fail "B1[C03 T2]: $SCRIPT is not executable (the gate-script convention: bash + executable)"
  bash -n "$SCRIPT" || fail "B1[C03 T2]: bash -n rejects $SCRIPT"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$SCRIPT" >"$TMP/sc.log" 2>&1 || { sed -n 1,20p "$TMP/sc.log" >&2; fail "B1[C03 T2]: shellcheck findings on $SCRIPT"; }
  else
    skip "B1: shellcheck not installed here — skipped with warning (t1 convention)"
  fi
  # Machine-checkable evidence lines: `PROBE: <leg> pass|fail` is what the
  # coord runbook greps (and what the LF6-degraded decision reads).
  grep -qE 'PROBE: ' "$SCRIPT" \
    || fail "B1[C03 T2]: $SCRIPT emits no 'PROBE: ' marker — the runbook's evidence lines are the output contract"
  grep -qw pass "$SCRIPT" && grep -qw fail "$SCRIPT" \
    || fail "B1[C03 T2]: $SCRIPT lacks both pass and fail verdict words — each leg must answer one of exactly two verdict tokens (deterministic pass/fail lines, per C03 T2)"
  for leg in LF1 LF2 LF4 LF5 LF7; do
    grep -q "$leg" "$SCRIPT" || fail "B1[C03 runbook]: $SCRIPT never names $leg — the live-fire legs must be addressable individually (LF3 stays offline-primary, LF6 its own ladder)"
  done
  # Fail-loud on any unknown shape (C03 T2 wording): a leg that cannot decide
  # must report fail, never pass silently.
  grep -qE 'exit [0-9]' "$SCRIPT" \
    || fail "B1[C03 T2]: $SCRIPT carries no explicit exit status — fail-loud needs non-zero on any unknown shape"
  ok "B1[C03 T2]: script exists, parses, is shellcheck-clean where available, names its legs and the PROBE: verdict shape"
fi

# --- B2: the one scoped grant — six sources + six mirrors, uniform position ----
if want b2; then
  for f in "${CF_SRC[@]}" "${CF_GEN[@]}"; do
    [ -f "$f" ] || fail "B2: $f missing (harness fault)"
    c=$(grep -cF "resource: $PROBE_RES" "$f")
    [ "$c" -eq 1 ] \
      || fail "B2[OQ-N1]: $f carries $c rows of 'resource: $PROBE_RES', want exactly one (the approved spaced-plan literal, counted as a fixed string — an unspaced minting fails the position python below, not this count)"
  done
  # Uniform position (the mint/session-origin/date grant precedent): the row
  # lands after `date *`, before the git block — parsed order, all twelve
  # files; a per-variant drift would read as a non-uniform block.
  if ! python3 - "${CF_SRC[@]}" "${CF_GEN[@]}" <<'PY'
import re, sys, yaml
PROBE = "bash scripts/board-preload-probe.sh *"
bad = []
for path in sys.argv[1:]:
    m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
    at = lambda pred: next((i for i, r in enumerate(perms) if pred(r)), None)
    p = at(lambda r: r.get("action") == "shell" and r.get("resource") == PROBE)
    d = at(lambda r: r.get("action") == "shell" and r.get("resource") == "date *")
    g = at(lambda r: r.get("action") == "shell" and str(r.get("resource", "")).startswith("git "))
    if p is None:
        bad.append(f"{path}: probe row absent (live grep arm names it first — cannot happen)")
    elif d is None or g is None or not (d < p < g):
        bad.append(f"{path}: probe row at {p} is not between the date allow ({d}) and the git block ({g}) — the uniform block shape broke")
    else:
        nxt = perms[p + 1]
        if not (nxt.get("action") == "shell" and nxt.get("resource") == "ls *" and nxt.get("effect") == "allow"):
            bad.append(f"{path}: the row after the probe allow is not the in-family `ls *` allow ({nxt}) — the 2026-10-30 re-seat order is …date, probe, ls directly before the git block")
if bad:
    print("; ".join(bad)); sys.exit(1)
PY
  then
    fail "B2[OQ-N1]: probe row position not uniform across the six coord variants + mirrors"
  fi
  ok "B2[OQ-N1]: one spaced scoped allow per coord file (12/12), uniformly placed after date * and before the git block"
fi

# --- B3: effective verdict — the granted call evaluates allow, family-wide -----
if want b3; then
  for f in "${CF_SRC[@]}"; do
    v=$(python3 - "$f" "$PROBE_RES lf1" <<'PY' 2>/dev/null || true
import fnmatch, re, sys, yaml
path, command = sys.argv[1], sys.argv[2]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
fm = yaml.safe_load(m.group(1)) or {}
perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
verdict = None
for r in perms:
    a = str(r.get("action", ""))
    if not (a == "shell" or fnmatch.fnmatch("shell", a)):
        continue
    if fnmatch.fnmatch(command, str(r.get("resource", ""))):
        verdict = r.get("effect")
print(verdict)
PY
)
    [ "$v" = "allow" ] || fail "B3[OQ-N1]: $f effective verdict for '$PROBE_RES lf1' is '$v', want allow (a deny-baseline family that forgets the row reads the probe as ungranted)"
  done
  ok "B3[OQ-N1]: every coord variant effectively allows the spaced probe call (last-match-wins verdict, not row presence alone)"
fi

# --- B4: the matrix moves with the rows (permissions.md drift lesson) -----------
if want b4; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    [ -f "$f" ] || fail "B4: $f missing"
    for row in coord board-coord; do
      python3 - "$f" "$row" <<'PY' || fail "B4[OQ-N1 matrix]: $f '$row' row does not name the probe grant — a permission-block change is only done when its matrix row moved too"
import re, sys
path, anchor = sys.argv[1], sys.argv[2]
hay = "\n".join(l for l in open(path).read().splitlines()
                if re.match(r"^\|[ \t]*" + re.escape(anchor) + r"[ \t]*\|", l))
sys.exit(0 if hay and "board-preload-probe" in hay else 1)
PY
    done
    grep -q 'board-preload-probe' "$f" \
      || fail "B4[OQ-N1 matrix]: $f never names board-preload-probe (drift incidents entry)"
  done
  ok "B4[OQ-N1]: permissions.md coord + board-coord rows and the drift log carry the scoped probe grant (source + mirror)"
fi

# --- B5: containment — exactly the six coord files, no broader mint (review rule)
if want b5; then
  holders=$(grep -l 'board-preload-probe' .rulesync/subagents/*.md || true)
  want_h="$(printf '%s\n' "${CF_SRC[@]}" | sort)"
  got_h="$(printf '%s\n' $holders | sort)"
  [ "$got_h" = "$want_h" ] \
    || fail "B5[OQ-N1]: the probe grant appears outside the six coord variants (got: $got_h) — review treats any broader mint as a deviation"
  for f in "${CF_SRC[@]}"; do
    grep -qE 'resource: opencode api post' "$f" \
      && fail "B5[OQ-N1]: $f grew 'opencode api post' — the rejected widening shape (A12's api containment breaks; the script is the grant)"
    grep -qE 'resource: opencode run' "$f" \
      && fail "B5[OQ-N1]: $f grew raw 'opencode run' — purpose-bound script only"
  done
  ok "B5[OQ-N1]: grant scoped to the six coord variants; no api-post or opencode-run shape anywhere in the family"
fi

printf 'PASS: board-preload-probe contract checks (%d ok)\n' "$checks"
