#!/usr/bin/env bash
# C02 behavioral contract (2026/2026-11-cf-56-feat-forgejo-coder-template-
# pipeline) for scripts/coder-template-detect.sh — the changed-template
# detector the .forgejo/workflows/coder-template-push.yaml detect job runs
# (the scripts/forgejo-container-detect.sh house shape, adapted to
# charts/coder/coder-templates/). AC trace (chunks/C02.md AC2):
# l1[a push range touching <x>/main.tf names exactly the changed gated dirs]
# l2[an unrelated path change names []] l3[a first push (all-zero before)
# narrows tip-only with the warning line] l4[an empty EVENT_BEFORE dies
# non-zero with the fatal message — plus the no-`|| true`-on-git-diff ban,
# the same red-detection-fails-loud contract] l5[a dispatch list names
# exactly the listed gated dirs] l6[an ungated name (no main.tf) is
# excluded, and so is a non-DNS-safe name] l7[the two exempted empties —
# a no-op ref update (before == sha) and an empty dispatch list — stay
# silent; every other empty set warns].
#
# The legs run against a synthetic git tree with the standard layout this
# file builds (the cf-139 C07 "detect A/B on real history" shape):
#   c0: kubernetes + kubernetes-hardened templates (main.tf each), an
#       `ungated` dir (a README, no main.tf), charts/coder/Chart.yaml
#   c1: touches both templates + the ungated dir + Chart.yaml
#   c2: touches Chart.yaml only
#
# Designed-RED until C02 lands the script: a missing script file is the
# not-yet-implemented state, not a skip.
#
# Run from the repo root:
#   bash tests/coder/coder-template-detect.sh       # l1..l7
#   bash tests/coder/coder-template-detect.sh l3    # subset
# Env: CODER_DETECT_ROOT (point at a pre-built synthetic tree with the
# standard layout above — the fanout-runbook FANOUT_ROOT green-shape
# convention; the default builds its own under /tmp/opencode).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/coder-template-detect.sh"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 7); do WANT["l$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^l[1-7]$ ]] || fail "unknown leg id '$a' (expected l1..l7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$SCRIPT" ] ||
  fail "$SCRIPT does not exist (designed-red: C02's detect script is not implemented)"

OWN_WORK=1
TIP=""
if [ -n "${CODER_DETECT_ROOT:-}" ]; then
  WORK="$CODER_DETECT_ROOT"
  OWN_WORK=0
else
  WORK="$(mktemp -d /tmp/opencode/coder-template-detect.XXXXXX)"
fi
cleanup() {
  if [ "$OWN_WORK" = 1 ]; then rm -rf "$WORK"; fi
  if [ -n "$TIP" ]; then rm -rf "$TIP"; fi
}
trap cleanup EXIT

commit() { # $1 repo, $2.. = message
  local repo="$1"
  shift
  git -C "$repo" -c user.name=t -c user.email=t@e.st commit -qm "$@"
}

build_tree() { # $1 repo — the standard layout (see the header)
  local repo="$1"
  git -C "$repo" init -q
  mkdir -p "$repo/charts/coder/coder-templates/kubernetes" \
           "$repo/charts/coder/coder-templates/kubernetes-hardened" \
           "$repo/charts/coder/coder-templates/ungated"
  echo 'terraform' > "$repo/charts/coder/coder-templates/kubernetes/main.tf"
  echo 'terraform' > "$repo/charts/coder/coder-templates/kubernetes-hardened/main.tf"
  echo 'not a template' > "$repo/charts/coder/coder-templates/ungated/README.md"
  echo 'chart' > "$repo/charts/coder/Chart.yaml"
  git -C "$repo" add -A
  commit "$repo" c0
  echo 'terraform c1' >> "$repo/charts/coder/coder-templates/kubernetes/main.tf"
  echo 'terraform c1' >> "$repo/charts/coder/coder-templates/kubernetes-hardened/main.tf"
  echo 'untouched' >> "$repo/charts/coder/coder-templates/ungated/README.md"
  echo 'chart c1' >> "$repo/charts/coder/Chart.yaml"
  git -C "$repo" add -A
  commit "$repo" c1
  echo 'chart c2' >> "$repo/charts/coder/Chart.yaml"
  git -C "$repo" add -A
  commit "$repo" c2
}

if [ "$OWN_WORK" = 1 ]; then
  build_tree "$WORK"
fi

RC=0
run_detect_in() { # $1 = the git root to run in, $2.. = env VAR=val pairs
  local dir="$1"
  shift
  if ( cd "$dir" && env "$@" bash "$SCRIPT" detect ) >"$dir/.out" 2>"$dir/.err"; then
    RC=0
  else
    RC=$?
  fi
  OUT="$(cat "$dir/.out")"
  ERR="$(cat "$dir/.err")"
}
run_detect() { run_detect_in "$WORK" "$@"; }

sha_of() { git -C "$WORK" rev-parse "$1"; }

# --- l1: a push range names exactly the changed gated dirs (AC2) -----------
if want l1; then
  a="$(sha_of HEAD~2)"
  b="$(sha_of HEAD~1)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$b"
  [ "$RC" -eq 0 ] ||
    fail "l1: the detector exited $RC on a template change — a red detection must fail the job loudly, never report 'nothing changed'"
  [ "$OUT" = '["kubernetes","kubernetes-hardened"]' ] ||
    fail "l1: the c0..c1 range printed '$OUT', expected the sorted JSON array of exactly the two changed gated dirs — the changed `ungated` dir must be gated out (no main.tf) and Chart.yaml sits outside charts/coder/coder-templates/"
  ok "l1: a push range touching <x>/main.tf names exactly the changed gated dirs (ungated gated out, out-of-tree paths ignored)"
fi

# --- l2: an unrelated path change names [] and warns (AC2) -----------------
if want l2; then
  a="$(sha_of HEAD~1)"
  b="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$b"
  [ "$RC" -eq 0 ] || fail "l2: the detector exited $RC on an empty change set"
  [ "$OUT" = '[]' ] ||
    fail "l2: an unrelated-path change printed '$OUT', expected [] — only template dirs under charts/coder/coder-templates/ may be named"
  printf '%s\n' "$ERR" | grep -q '::warning::' ||
    fail "l2: the non-exempted empty set went silent — an empty result that is NOT one of the two exempted no-ops must earn its ::warning:: line (a green run that pushed nothing must read differently from a range that resolved to nothing)"
  ok "l2: an unrelated path change names [] and the non-exempted empty set warns"
fi

# --- l3: a first push narrows tip-only and says so (AC2) ------------------
if want l3; then
  TIP="$(mktemp -d /tmp/opencode/coder-template-detect-tip.XXXXXX)"
  git -C "$TIP" init -q
  mkdir -p "$TIP/charts/coder/coder-templates/kubernetes" \
           "$TIP/charts/coder/coder-templates/kubernetes-hardened"
  echo 'terraform' > "$TIP/charts/coder/coder-templates/kubernetes/main.tf"
  echo 'terraform' > "$TIP/charts/coder/coder-templates/kubernetes-hardened/main.tf"
  git -C "$TIP" add -A
  commit "$TIP" base
  echo 'terraform tip' > "$TIP/charts/coder/coder-templates/kubernetes/main.tf"
  git -C "$TIP" add -A
  commit "$TIP" tip
  tip_head="$(git -C "$TIP" rev-parse HEAD)"
  run_detect_in "$TIP" EVENT_NAME=push EVENT_BEFORE=0000000000000000000000000000000000000000 SHA="$tip_head"
  [ "$RC" -eq 0 ] || fail "l3: the detector exited $RC on a first push (all-zero before)"
  [ "$OUT" = '["kubernetes"]' ] ||
    fail "l3: the first-push range printed '$OUT', expected [\"kubernetes\"] — the base commit's kubernetes-hardened addition is a PREVIOUS commit and must stay invisible under the tip-only HEAD^..HEAD narrowing"
  if ! printf '%s\n' "$ERR" | grep -q '::warning::' || ! printf '%s\n' "$ERR" | grep -qiE 'first push|tip.only'; then
    fail "l3: the first-push narrowing did not announce itself — the ::warning:: line is where the tip-only narrowing says it narrowed (a silent narrowing hides the commits it skipped)"
  fi
  ok "l3: a first push (all-zero before) narrows tip-only over HEAD^..HEAD and the warning line announces it"
fi

# --- l4: an empty EVENT_BEFORE dies non-zero (AC2) -------------------------
if want l4; then
  b="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE="" SHA="$b"
  [ "$RC" -ne 0 ] ||
    fail "l4: an empty EVENT_BEFORE exited 0 — no push payload sends an empty before, so reading it as a first push would silently narrow a multi-commit push to the tip commit; the detector must die (the model's die, exit 2)"
  printf '%s\n' "$ERR" | grep -qiE 'before|empty' ||
    fail "l4: the fatal message names neither 'before' nor 'empty' — a red detection must be diagnosable from the job log alone"
  if grep -qE 'git diff.*\|\| *true' "$SCRIPT"; then
    fail "l4: a git diff call in $SCRIPT carries '|| true' — a range that fails to resolve must fail the job, not be reported as 'nothing changed'"
  fi
  ok "l4: an empty EVENT_BEFORE dies non-zero with the fatal message; no '|| true' on the git diff call"
fi

# --- l5: a dispatch list names exactly the listed gated dirs (AC2) ---------
if want l5; then
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES='kubernetes, kubernetes-hardened'
  [ "$RC" -eq 0 ] || fail "l5: the detector exited $RC on a named dispatch list"
  [ "$OUT" = '["kubernetes","kubernetes-hardened"]' ] ||
    fail "l5: the dispatch list printed '$OUT', expected the sorted array of exactly the two named gated dirs"
  ok "l5: a dispatch list names exactly the listed gated dirs"
fi

# --- l6: ungated + non-DNS-safe names are excluded (AC2) -------------------
if want l6; then
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES='kubernetes,ungated'
  [ "$RC" -eq 0 ] || fail "l6: the detector exited $RC on a dispatch list with an ungated name"
  [ "$OUT" = '["kubernetes"]' ] ||
    fail "l6: a named dir without a main.tf printed '$OUT', expected [\"kubernetes\"] — a name in a free-text input is not a promise that a pushable template exists"
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES='kubernetes,Bad_Name'
  [ "$RC" -eq 0 ] || fail "l6: the detector exited $RC on a dispatch list with a non-DNS-safe name"
  [ "$OUT" = '["kubernetes"]' ] ||
    fail "l6: a non-DNS-safe name printed '$OUT', expected [\"kubernetes\"] — the DNS-safe gate applies to dispatch lists too (a bad name would be a bad --directory target)"
  ok "l6: ungated (no main.tf) and non-DNS-safe names are excluded from dispatch lists"
fi

# --- l7: the two exempted empties stay silent (AC2) ------------------------
if want l7; then
  a="$(sha_of HEAD~1)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$a"
  [ "$RC" -eq 0 ] || fail "l7: the detector exited $RC on a no-op ref update (before == sha)"
  [ "$OUT" = '[]' ] || fail "l7: the no-op ref update printed '$OUT', expected []"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "l7: a no-op ref update (before == sha) warned — its empty range is correct semantics and stays silent"
  fi
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES=''
  [ "$RC" -eq 0 ] || fail "l7: the detector exited $RC on an empty dispatch list"
  [ "$OUT" = '[]' ] || fail "l7: an empty dispatch list printed '$OUT', expected []"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "l7: an empty dispatch list warned — it is its own no-op intent (an empty list pushes nothing) and stays silent"
  fi
  ok "l7: the two exempted empties (no-op ref update, empty dispatch list) stay silent; every other empty set warns (l2)"
fi

printf 'PASS: coder template detect checks (%d ok)\n' "$checks"
