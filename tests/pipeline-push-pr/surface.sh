#!/usr/bin/env bash
# pipeline-push-pr hidden-contract-skill surface suite (2026/2026-10-cf-58-feat-
# standalone-agent-merge, C01).
#
# Pins chunks/C01.md: the single authority for "push work to be built and
# tested remotely" exists as a hidden contract skill (source + generated
# mirror), carries the five fixed contracts + the Deploy-stage hook, and is
# not yet referenced by any subagent (the wiring is C02/C03). Contract
# wording is dev's; the needle sets below are the contracts C01 pins.
#
# AC trace: P1[AC1-existence] P2[AC1-frontmatter] P3[AC3-contracts]
# P4[AC4-no-refs-yet / C02-flip] P5[AC2-mirror-integrity] P6[AC2-regen].
#
# Red posture (base: the cf-58 ticket base, arm-B discipline per the sibling
# suites — historical arm A=081b57889 / arm B refs stay documented there;
# this ticket's surfaces are all NEW, so every P check is a plain tree check):
# P1-P3,P5 red before C01 lands (skill files absent — the red names the
# missing file/contract, never a harness fault); P4 vacuous-green (absence
# proves it) and flips to the C02 wiring pin once agent-dev-pr.md exists;
# P6 HOLD posture (generator honesty of the committed tree).
#
# Offline-deterministic: no server, no session; the generator arm runs the
# rulesync PATH/npx ladder and skip-warns where unresolvable (c7/t14 precedent).
#
# Usage:
#   bash tests/pipeline-push-pr/surface.sh            # P1..P6
#   bash tests/pipeline-push-pr/surface.sh P1 P3      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC=".rulesync/skills/pipeline-push-pr/SKILL.md"
GEN=".opencode/skills/pipeline-push-pr/SKILL.md"
DEVPR=".rulesync/subagents/agent-dev-pr.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/push-pr-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["p$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^p[1-6]$ ]] || fail "unknown check id '$a' (expected P1..P6)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers ------------------------------------------------------------

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): the needles must read
# as one passage — a contract sentence — not as scattered file-wide hits.
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

cat >"$TMP/fm.py" <<'PY'
# AC1: the hidden-contract frontmatter shape, parsed (rulesync re-serializes
# bytes, so the mirror is checked parsed-equal, not byte-equal — same
# convention as tests/agent-perms/surface.sh A5's dict compare).
import re, sys, yaml
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
errs = []
if fm.get("name") != "pipeline-push-pr":
    errs.append(f"name is {fm.get('name')!r}")
d = str(fm.get("description") or "")
if not d.endswith("MUST-loaded by the `-pr` agent variants; never auto-selected."):
    errs.append("description does not end with the MUST-load/never-auto-select tail")
if fm.get("targets") != ["*"]:
    errs.append(f"targets is {fm.get('targets')!r}, want ['*']")
if fm.get("disable-model-invocation") is not True:
    errs.append("disable-model-invocation is not true")
if (fm.get("metadata") or {}).get("opencode/autoinvoke") != "false":
    errs.append("metadata opencode/autoinvoke is not the string false")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY

cat >"$TMP/pairsync.py" <<'PY'
# Source<->mirror honesty for a skill pair: bodies equal once frontmatter and
# surrounding blank space are stripped; the meaningful frontmatter fields
# equal once parsed (folded descriptions parse to the same string at any wrap
# width). A hand-edited mirror or an un-regenerated source lands here.
import re, sys, yaml
src, gen = sys.argv[1], sys.argv[2]

def parts(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{path}: no parsable frontmatter"
    return yaml.safe_load(m.group(1)), m.group(2).strip("\n") + "\n"

f1, b1 = parts(src)
f2, b2 = parts(gen)
n = lambda f: {k: f.get(k) for k in ("name", "description", "metadata", "disable-model-invocation")}
if b1 != b2:
    print("body drift between source and generated mirror"); sys.exit(1)
if n(f1) != n(f2):
    print("frontmatter drift between source and generated mirror"); sys.exit(1)
PY

# --- P1: skill source + generated mirror exist ---------------------------------
if want p1; then
  [ -f "$SRC" ] || fail "P1[AC1]: $SRC does not exist (red before C01 — the skill is the C02/C03 name to reference)"
  [ -f "$GEN" ] || fail "P1[AC1]: generated mirror $GEN does not exist (red before C01 — sources + generated land together)"
  ok "P1[AC1]: source and generated mirror of pipeline-push-pr exist"
fi

# --- P2: hidden-skill frontmatter shape (AC1) ----------------------------------
if want p2; then
  [ -f "$SRC" ] || fail "P2[AC1]: $SRC missing — frontmatter cannot be checked (red before C01)"
  python3 "$TMP/fm.py" "$SRC" \
    || fail "P2[AC1]: $SRC frontmatter is not the hidden-contract shape (name / MUST-load description tail / targets ['*'] / disable-model-invocation true / opencode/autoinvoke 'false' — the pipeline-gates + pipeline-kickoff contract)"
  ok "P2[AC1]: source frontmatter parses as the hidden contract-skill shape"
fi

# --- P3: the five contracts + Deploy hook, source AND mirror (AC3) -------------
# The five fixed contracts + the Deploy-stage hook, as co-location windows run
# identically against source and mirror (AC3). Wording is dev's; the needles
# are the contracts C01's Tasks pin.
contract() { # label, ci(1|0), span, file, needles...
  local label="$1" ci="$2" span="$3" f="$4"; shift 4
  if [ "$ci" = "1" ]; then
    python3 "$TMP/win.py" --ci "$f" "$span" "$@" \
      || fail "P3[AC3]: $f does not carry the '$label' contract as one passage (red before C01 — the contracts are fixed, the wording is dev's)"
  else
    python3 "$TMP/win.py" "$f" "$span" "$@" \
      || fail "P3[AC3]: $f does not carry the '$label' contract as one passage (red before C01 — the contracts are fixed, the wording is dev's)"
  fi
}
if want p3; then
  for f in "$SRC" "$GEN"; do
    [ -f "$f" ] || fail "P3[AC3]: $f missing (red before C01)"
    # 1. Applies-to — the four -pr consumers named; a -local/plain loader is drift.
    contract applies-to 0 400 "$f" 'agent-coord-pr' 'agent-board-coord-pr' 'agent-dev-pr' 'dev-pr'
    contract drift-stop 1 300 "$f" 'drift' 'stop'
    # 2. Push rules — the AGENTS.md hard-rule citations + the standing-request basis.
    contract push-rules 1 900 "$f" 'AGENTS.md' 'main' 'force-push' 'self-remediat' 'human-owned'
    contract standing-request 1 400 "$f" 'user request' 'branch'
    grep -qF 'never a refspec' "$f" || grep -qF 'HEAD:main' "$f" \
      || fail "P3[AC3]: $f never cites the refspec-updating-main hard rule ('never a refspec that updates main' / the HEAD:main form) — one of the pinned AGENTS.md citations (red before C01)"
    # 3. What a push triggers — CI facts, and push is build+test, not deploy.
    contract ci-on-push 1 600 "$f" 'aislop ci --changes' 'docker-build' 'release.yaml'
    contract build-not-deploy 1 300 "$f" 'build' 'deploy'
    contract argocd-after-merge 1 300 "$f" 'ArgoCD' 'merge'
    # 4. PR creation — gh when authenticated, else the compare URL, never a claim of a PR that was not created.
    contract pr-create 1 400 "$f" 'gh pr create' 'compare/main'
    contract pr-honesty 1 300 "$f" 'not created'
    # 5. Verify after push — ls-remote + RESULT reporting; a failed push is reported, never force-retried.
    contract verify-push 1 400 "$f" 'git ls-remote' 'RESULT'
    contract no-force-retry 1 300 "$f" 'force' 'retr'
    # 6. Deploy stage hook (C05 pairing) — push/PR is the Deploy action; -local answers "ready — commits local".
    contract deploy-hook 1 400 "$f" 'Deploy' 'ready — commits local'
    contract deploy-local-stop 1 300 "$f" 'local' 'stop'
  done
  ok "P3[AC3]: all five contracts + the Deploy hook read as passages in source AND mirror (applies-to, push rules with the AGENTS.md citations, CI-on-push facts, PR-creation fallback, verify-after-push, Deploy stage hook)"
fi

# --- P4: AC4 no-agent-references-yet, flipping to the C02 wiring pin -----------
if want p4; then
  if [ ! -f "$DEVPR" ]; then
    refs=$(grep -rln 'pipeline-push-pr' .rulesync/subagents 2>/dev/null || true)
    [ -z "$refs" ] || fail "P4[AC4]: subagents reference the skill before C02/C03 ($refs) — C01 ends with the grep empty (dangling reference)"
    ok "P4[AC4]: no subagent references pipeline-push-pr yet (C01 posture)"
  else
    grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$DEVPR" \
      || fail "P4[C02-flip]: $DEVPR exists but does not MUST-load /pipeline-push-pr (C02 AC4)"
    ok "P4[C02-flip]: post-C02 — agent-dev-pr carries the /pipeline-push-pr MUST-load"
  fi
fi

# --- P5: mirror integrity — parsed, not bytes (AC2) ----------------------------
if want p5; then
  [ -f "$SRC" ] && [ -f "$GEN" ] || fail "P5[AC2]: pair incomplete (red before C01)"
  python3 "$TMP/pairsync.py" "$SRC" "$GEN" \
    || fail "P5[AC2]: $SRC and $GEN are not honest source/mirror copies (red before C01; after, a drifted mirror means a hand-edit or a missing regenerate)"
  ok "P5[AC2]: source and generated mirror agree (body equal, meaningful frontmatter fields parsed-equal)"
fi

# --- P6: regeneration contract (AC2) --------------------------------------------
if want p6; then
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "P6: rulesync not resolvable here (PATH or npx cache) — generate --check + no-op gate skipped with warning (c7/t14 precedent)"
    ok "P6[AC2-regen]: generator gate skipped with warning"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "P6[AC2]: rulesync generate --check is not clean — committed generated surfaces are stale against the sources"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "P6[AC2]: rulesync generate failed"; }
    snap_before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "P6[AC2]: second rulesync generate failed"
    snap_after=$(git status --porcelain)
    [ "$snap_before" = "$snap_after" ] || fail "P6[AC2]: the second rulesync generate is not a no-op (sources and generated have drifted)"
    ok "P6[AC2]: generate --check clean and the second generate is a no-op (via $RS)"
  fi
fi

printf 'PASS: pipeline-push-pr surface checks (%d ok)\n' "$checks"
