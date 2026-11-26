#!/usr/bin/env bash
# C02 behavioral contract, re-pinned to the C04 marker-arm ruling
# (2026/2026-11-cf-56-feat-forgejo-coder-template-pipeline) for
# scripts/coder-template-detect.sh — the changed-template detector the
# .forgejo/workflows/coder-template-push.yaml detect job runs (the
# scripts/forgejo-container-detect.sh house shape, adapted to
# charts/coder/coder-templates/). AC trace (chunks/C02.md AC2;
# chunks/C04.md):
# l1[a push range touching <x>/main.tf names exactly the changed gated
#    dirs; the stderr echo carries base=before (marker absent)]
# l2[an unrelated path change names [] — the script-owned empty-set
#    warning is RETIRED (OQ12: the step owns the law): no ::warning:: on
#    any channel, and the grep-bans for the exempt flag + the 'will push
#    nothing' warning text replace the old positive assert; base=before
#    on the echo]
# l3[a first push (all-zero before) narrows tip-only with the warning
#    line (the narrowing announce is RETAINED — only the empty-set
#    warning died) + base=tip-only on the echo]
# l4[an empty EVENT_BEFORE on a REAL push dies non-zero with the fatal
#    message (the die stayed scoped to real pushes — the marker arm
#    moved ahead of it, d20/d21); the no-`|| true`-on-git-diff ban;
#    the event vocabulary is exactly push|workflow_call|
#    workflow_dispatch — workflow_call present, pull_request banned
#    anywhere in the file]
# l5[a dispatch list names exactly the listed gated dirs]
# l6[an ungated name (no main.tf) is excluded, and so is a non-DNS-safe
#    name]
# l7[the no-op ref update (before == sha) and the empty dispatch list
#    stay silent; the script never warns on any channel (the step owns
#    the law, OQ12) — the two empties are correct semantics, not script
#    exemptions]
# d17[MARKER_SHA == SHA: the marker arm wins, answers [] with exit 0 and
#     stdout exactly one JSON line — the quiet re-run semantics, no
#     warning on any channel; the echo names base=marker]
# d18[empty MARKER_SHA: the push channels (the die / the all-zero
#     tip-only / before..sha non-empty + empty) + the named dispatch
#     channel reproduce the shipped C02 fallback byte-for-byte on every
#     channel (stdout, stderr, exit) — with the r5 base= token; the call
#     channel answers the announced tip-only bootstrap (the new arm — the
#     announce is the signal). DEVIATION: the all-ungated dispatch
#     channel is NOT byte-identical to C02 — the C02
#     all-ungated-dispatch warning is RETIRED by OQ12 (the dispatch
#     no-op is exempt wholesale at the step level), so a C02 dispatch
#     warning would be a red here; the silence is the pin]
# d19[an unreachable MARKER_SHA (an oid no commit resolves to) propagates
#     git 128 with NO JSON on stdout through the unmasked diff — the
#     workflow's resolver owns the reachability pre-check; the script
#     stays unmasked and fails loud (the echo names base=marker before
#     the die)]
# d20[workflow_call + MARKER_SHA set + empty before: the marker arm
#     PRECEDES the payload die — diffs marker..sha, base=marker, exit 0
#     (the C15 call-aware reorder: the marker check must precede the
#     empty-before die)]
# d21[workflow_call + no marker + empty before: the announced tip-only
#     HEAD^..HEAD bootstrap (base=tip-only), NEVER the push-payload die
#     (the C15 call arm — a called run carries no push payload, so an
#     empty before is expected there)]
# d22[a REAL push + empty before + no marker: STILL DIES (naming before)
#     — the die stayed scoped to real pushes, the marker arm moved ahead
#     of it]
#
# The legs run against a synthetic git tree with the standard layout this
# file builds (the cf-139 C07 "detect A/B on real history" shape):
#   c0: kubernetes + kubernetes-hardened templates (main.tf each), an
#       `ungated` dir (a README, no main.tf), charts/coder/Chart.yaml
#   c1: touches both templates + the ungated dir + Chart.yaml
#   c2: touches Chart.yaml only
# (l3/d18's tip tree: a base commit + one tip commit touching one
# template.)
#
# The marker d-legs run the SHIPPED script with MARKER_SHA wired in the
# env (the workflow's accessor, empty on the bootstrap state — d18 pins
# the empty-wired identity with the C02 fallback; the l-legs leave the
# accessor unset, the same fallback).
#
# Designed-RED through C04 on the re-pinned l-legs + the marker d-legs:
# on the pre-C04 tree the script has no workflow_call arm (the l4 vocab
# pin + the d20/d21 call legs red), no base= token (l1/l2/l3/d17 red),
# and still carries the retired exempt flag + the 'will push nothing'
# warning (l2 red); d18's push channels go red on the base= bytes alone
# (the C02 fallback is otherwise byte-frozen) while its call channel
# dies where the bootstrap arm should announce. d22 + l5/l6/l7 stay
# green (the die + the dispatch list behavior + the silent empties are
# C02-carried).
#
# Run from the repo root:
#   bash tests/coder/coder-template-detect.sh          # l1..l7 + d17..d22
#   bash tests/coder/coder-template-detect.sh d17     # subset
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
  for d in 17 18 19 20 21 22; do WANT["d$d"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^l[1-7]$|^d(1[7-9]|2[0-2])$ ]] ||
      fail "unknown leg id '$a' (expected l1..l7 or d17..d22)"
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

# --- l1: a push range names exactly the changed gated dirs (AC2 re-pin) ---
if want l1; then
  a="$(sha_of HEAD~2)"
  b="$(sha_of HEAD~1)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$b"
  [ "$RC" -eq 0 ] ||
    fail "l1: the detector exited $RC on a template change — a red detection must fail the job loudly, never report 'nothing changed'"
  [ "$OUT" = '["kubernetes","kubernetes-hardened"]' ] ||
    fail "l1: the c0..c1 range printed '$OUT', expected the sorted JSON array of exactly the two changed gated dirs — the changed `ungated` dir must be gated out (no main.tf) and Chart.yaml sits outside charts/coder/coder-templates/"
  if ! printf '%s\n' "$ERR" | grep -q 'base=before'; then
    fail "l1: the push-arm stderr echo carries no 'base=before' token — the r5 house echo names which base won (marker|tip-only|before), so a marker-fed run reads differently from a bootstrap one; the marker is absent here, so before must be the named base"
  fi
  ok "l1: a push range touching <x>/main.tf names exactly the changed gated dirs (ungated gated out, out-of-tree paths ignored); the stderr echo names base=before (marker absent)"
fi

# --- l2: an unrelated path change names [] and the script stays silent (AC2 re-pin) ---
if want l2; then
  a="$(sha_of HEAD~1)"
  b="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$b"
  [ "$RC" -eq 0 ] || fail "l2: the detector exited $RC on an empty change set"
  [ "$OUT" = '[]' ] ||
    fail "l2: an unrelated-path change printed '$OUT', expected [] — only template dirs under charts/coder/coder-templates/ may be named"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "l2: the script still warns on the empty set — the script-owned empty-set warning is RETIRED (OQ12: the step owns the warning law, one law governs); the script's stderr is the narrowing announces + the range/base echo only, and a green run that pushed nothing is read from the STEP's warning, not the script's"
  fi
  if grep -q 'exempt' "$SCRIPT"; then
    fail "l2: the 'exempt' flag survives in $SCRIPT — the script-owned exemption arithmetic is RETIRED with the warning (OQ12: a flag that classifies empties the step owns is a second law)"
  fi
  if grep -qF 'will push nothing' "$SCRIPT"; then
    fail "l2: the retired warning text 'will push nothing' survives in $SCRIPT — the script-owned empty-set warning print is RETIRED (OQ12; the step's warning is where a green run that pushed nothing is read)"
  fi
  if ! printf '%s\n' "$ERR" | grep -q 'base=before'; then
    fail "l2: the empty push-range stderr echo carries no 'base=before' token — the base token names which arm won even when the set resolves to nothing"
  fi
  ok "l2: an unrelated path change names [] and the script stays silent (the step owns the warning law, OQ12 — the exempt flag + the 'will push nothing' warning are grep-banned); the echo names base=before"
fi

# --- l3: a first push narrows tip-only and says so (AC2 re-pin) ----------
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
  if ! printf '%s\n' "$ERR" | grep -q 'base=tip-only'; then
    fail "l3: the first-push echo carries no 'base=tip-only' token — the base token names the arm that won; a bootstrap call run (d21) must read differently from a marker-fed one (d20)"
  fi
  ok "l3: a first push (all-zero before) narrows tip-only over HEAD^..HEAD and the warning line announces it; the echo names base=tip-only"
fi

# --- l4: an empty EVENT_BEFORE on a real push dies non-zero (AC2 re-pin) --
if want l4; then
  b="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE="" SHA="$b"
  [ "$RC" -ne 0 ] ||
    fail "l4: an empty EVENT_BEFORE on a real push exited 0 — no push payload sends an empty before, so reading it as a first push would silently narrow a multi-commit push to the tip commit; the die stays scoped to real pushes (the marker arm moved ahead of it — d20/d21 answer the call channel instead)"
  printf '%s\n' "$ERR" | grep -qiE 'before|empty' ||
    fail "l4: the fatal message names neither 'before' nor 'empty' — a red detection must be diagnosable from the job log alone"
  if grep -qE 'git diff.*\|\| *true' "$SCRIPT"; then
    fail "l4: a git diff call in $SCRIPT carries '|| true' — a range that fails to resolve must fail the job, not be reported as 'nothing changed'"
  fi
  if ! grep -q 'workflow_call' "$SCRIPT"; then
    fail "l4: the script's event vocabulary carries no 'workflow_call' — the C15 call arm is law (a called run carries no push payload; the tip-only bootstrap arm answers it, d21)"
  fi
  if grep -q 'pull_request' "$SCRIPT"; then
    fail "l4: 'pull_request' appears in $SCRIPT — the vocabulary is exactly push|workflow_call|workflow_dispatch (no PR arm, the OQ2 ruling: fork heads carry empty secrets and a PR would mint an active version)"
  fi
  ok "l4: an empty EVENT_BEFORE on a real push dies non-zero with the fatal message (the die scoped to real pushes); no '|| true' on the git diff call; the vocabulary is push|workflow_call|workflow_dispatch (workflow_call present, pull_request banned)"
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

# --- l7: the two no-op empties stay silent (AC2 re-pin) -------------------
# The script never warns on any channel (OQ12: the step owns the warning
# law — the script's stderr is the narrowing announces + the range/base
# echo only). These two empties are correct semantics — a no-op ref
# update, an empty dispatch list that names nothing (its own intent) —
# read as such by the step, not exempted by a script flag.
if want l7; then
  a="$(sha_of HEAD~1)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$a"
  [ "$RC" -eq 0 ] || fail "l7: the detector exited $RC on a no-op ref update (before == sha)"
  [ "$OUT" = '[]' ] || fail "l7: the no-op ref update printed '$OUT', expected []"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "l7: a no-op ref update (before == sha) warned — its empty range is correct semantics and stays silent (the step owns the law, OQ12: the script never warns)"
  fi
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES=''
  [ "$RC" -eq 0 ] || fail "l7: the detector exited $RC on an empty dispatch list"
  [ "$OUT" = '[]' ] || fail "l7: an empty dispatch list printed '$OUT', expected []"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "l7: an empty dispatch list warned — it is its own no-op intent (an empty list pushes nothing) and stays silent (the step owns the law, OQ12: the script never warns)"
  fi
  ok "l7: the no-op ref update (before == sha) and the empty dispatch list stay silent — the script never warns on any channel (the step owns the law, OQ12); the empties are correct semantics, not script exemptions"
fi

# --- d17: MARKER_SHA == SHA — the quiet re-run, the marker arm wins (C04)
if want d17; then
  b="$(sha_of HEAD~1)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$b" SHA="$b" MARKER_SHA="$b"
  [ "$RC" -eq 0 ] ||
    fail "d17: the detector exited $RC with MARKER_SHA == SHA — the marker arm must win and answer the quiet re-run (the marker..sha diff is empty), never die (the marker check precedes the payload die)"
  [ "$OUT" = '[]' ] ||
    fail "d17: the marker==sha range printed '$OUT', expected [] — marker..sha is an empty diff"
  [ "$(wc -l < "$WORK/.out")" -eq 1 ] ||
    fail "d17: stdout is not exactly one JSON line — the quiet re-run semantics keep stdout exactly the JSON array (the step captures it textually; an extra line re-breaks the parse contract)"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "d17: the marker==sha re-run warned — the quiet re-run carries no warning on any channel (the marker PROVES nothing was missed; the step's verified-empty info line is where a marker-fed empty reads)"
  fi
  if ! printf '%s\n' "$ERR" | grep -q 'base=marker'; then
    fail "d17: the echo names no 'base=marker' — the marker arm must win over the before==sha no-op (the marker check precedes it); a marker-fed run reads differently from a bootstrap one"
  fi
  ok "d17: MARKER_SHA == SHA answers [] with exit 0 and stdout exactly one JSON line — the quiet re-run semantics, no warning on any channel; the echo names base=marker (the marker arm won)"
fi

# --- d18: empty MARKER_SHA — the C02 fallback byte-for-byte (C04) --------
# The workflow always wires the MARKER_SHA accessor; empty is the
# bootstrap state. d18 pins that the empty-wired state reproduces the
# shipped C02 fallback byte-for-byte on every channel (outcome identity:
# the exact stdout, the exact stderr lines, the exit code) — with the r5
# base= token on the push-era echoes. DEVIATION (recorded in the header):
# the all-ungated dispatch channel is NOT byte-identical to C02 — the C02
# all-ungated-dispatch warning is RETIRED by OQ12 (the dispatch no-op is
# exempt wholesale at the step level); the silence is the pin, a C02
# warning would be a red.
if want d18; then
  D18TIP="$(mktemp -d /tmp/opencode/coder-template-detect-d18tip.XXXXXX)"
  git -C "$D18TIP" init -q
  mkdir -p "$D18TIP/charts/coder/coder-templates/kubernetes" \
           "$D18TIP/charts/coder/coder-templates/kubernetes-hardened"
  echo 'terraform' > "$D18TIP/charts/coder/coder-templates/kubernetes/main.tf"
  echo 'terraform' > "$D18TIP/charts/coder/coder-templates/kubernetes-hardened/main.tf"
  git -C "$D18TIP" add -A
  commit "$D18TIP" base
  echo 'terraform tip' > "$D18TIP/charts/coder/coder-templates/kubernetes/main.tf"
  git -C "$D18TIP" add -A
  commit "$D18TIP" tip
  tip_head="$(git -C "$D18TIP" rev-parse HEAD)"

  # (a) the die on a real push (C02's die, scoped and carried)
  b="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE= SHA="$b" MARKER_SHA=
  [ "$RC" -ne 0 ] || fail "d18a: a real push with an empty before (marker empty) exited 0 — the C02 die is carried: no push payload sends an empty before"
  [ -z "$OUT" ] || fail "d18a: the die channel printed stdout '$OUT' — a die must print no JSON (the run is red, the verdict is the fatal message)"
  printf '%s\n' "$ERR" | grep -qF 'push arm: EVENT_BEFORE is empty, which no push payload sends' ||
    fail "d18a: the die message is not the C02 fatal (byte-frozen) — 'push arm: EVENT_BEFORE is empty, which no push payload sends'"

  # (b) the all-zero first push (tip tree): the announce + base=tip-only
  run_detect_in "$D18TIP" EVENT_NAME=push EVENT_BEFORE=0000000000000000000000000000000000000000 SHA="$tip_head" MARKER_SHA=
  [ "$RC" -eq 0 ] || fail "d18b: the all-zero first push (marker empty) exited $RC"
  [ "$OUT" = '["kubernetes"]' ] || fail "d18b: the all-zero tip-only range printed '$OUT', expected [\"kubernetes\"] (the C02 tip-only narrowing, byte-frozen)"
  [ "$ERR" = "$(printf '::warning::first push (all-zero before): tip-only detection over HEAD^..HEAD\ndetect: range HEAD^..HEAD (event push, base=tip-only)')" ] ||
    fail "d18b: the all-zero channel stderr is not byte-for-byte the C02 announce + the r5 echo with base=tip-only — got: $(printf '%s' "$ERR" | tr '\n' '|')"

  # (c) before..sha non-empty (c0..c1)
  a="$(sha_of HEAD~2)"
  c="$(sha_of HEAD~1)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$a" SHA="$c" MARKER_SHA=
  [ "$RC" -eq 0 ] || fail "d18c: the c0..c1 push range (marker empty) exited $RC"
  [ "$OUT" = '["kubernetes","kubernetes-hardened"]' ] || fail "d18c: the c0..c1 range printed '$OUT', expected the C02 byte-frozen sorted array"
  [ "$ERR" = "detect: range $a..$c (event push, base=before)" ] ||
    fail "d18c: the before..sha channel stderr is not byte-for-byte the r5 echo with base=before — got: $(printf '%s' "$ERR" | tr '\n' '|')"

  # (d) before..sha empty (c1..c2) — silent (the step owns the warning, OQ12)
  d="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE="$c" SHA="$d" MARKER_SHA=
  [ "$RC" -eq 0 ] || fail "d18d: the c1..c2 empty push range (marker empty) exited $RC"
  [ "$OUT" = '[]' ] || fail "d18d: the empty push range printed '$OUT', expected []"
  [ "$ERR" = "detect: range $c..$d (event push, base=before)" ] ||
    fail "d18d: the empty push-range stderr is not byte-for-byte the r5 echo with base=before (and silent — the script never warns, OQ12) — got: $(printf '%s' "$ERR" | tr '\n' '|')"

  # (e1) the named dispatch channel — byte-identical to C02 (a non-empty
  # result never warned in C02 either; the dispatch arm echoes nothing)
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES='kubernetes, kubernetes-hardened' MARKER_SHA=
  [ "$RC" -eq 0 ] || fail "d18e: the named dispatch list (marker empty) exited $RC"
  [ "$OUT" = '["kubernetes","kubernetes-hardened"]' ] || fail "d18e: the named dispatch list printed '$OUT', expected the C02 byte-frozen array"
  [ -z "$ERR" ] || fail "d18e: the named dispatch channel printed stderr '$(printf '%s' "$ERR" | tr '\n' '|')' — the dispatch arm echoes nothing on either side (a non-empty result never warned in C02 either)"

  # (e2) the all-ungated dispatch channel — the RETIRED C02 divergence:
  # C02 warned, C04 stays silent (OQ12: the step owns the law; the
  # dispatch no-op is exempt wholesale). Not byte-identical to C02 — the
  # recorded deviation; the silence is the pin.
  run_detect EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES='ungated' MARKER_SHA=
  [ "$RC" -eq 0 ] || fail "d18e2: the all-ungated dispatch list (marker empty) exited $RC"
  [ "$OUT" = '[]' ] || fail "d18e2: the all-ungated dispatch list printed '$OUT', expected [] (the named dir has no main.tf)"
  if printf '%s\n' "$ERR" | grep -q '::warning::'; then
    fail "d18e2: the all-ungated dispatch channel warned — the C02 all-ungated-dispatch warning is RETIRED (OQ12: the step owns the law; the dispatch no-op is exempt wholesale). This channel is the recorded deviation from C02 byte-identity: the silence is the pin"
  fi

  # (f) the call channel — the NEW arm: the announced tip-only bootstrap
  # (the announce is the signal; never the push-payload die)
  run_detect_in "$D18TIP" EVENT_NAME=workflow_call EVENT_BEFORE= SHA="$tip_head" MARKER_SHA=
  [ "$RC" -eq 0 ] || fail "d18f: the called bootstrap (marker empty) exited $RC — a called run carries no push payload, so the empty before is EXPECTED and the die must not fire (it is scoped to real pushes)"
  [ "$OUT" = '["kubernetes"]' ] || fail "d18f: the called tip-only bootstrap printed '$OUT', expected [\"kubernetes\"]"
  [ "$ERR" = "$(printf '::warning::first called run (workflow_call, no marker): tip-only detection over HEAD^..HEAD\ndetect: range HEAD^..HEAD (event workflow_call, base=tip-only)')" ] ||
    fail "d18f: the called bootstrap stderr is not byte-for-byte the announce + the r5 echo with base=tip-only — got: $(printf '%s' "$ERR" | tr '\n' '|')"
  rm -rf "$D18TIP"
  ok "d18: empty MARKER_SHA reproduces the C02 fallback byte-for-byte on every channel — the die (a), the all-zero tip-only (b), before..sha non-empty + empty (c/d), the named dispatch (e1) — with the r5 base= token; the all-ungated dispatch is the recorded deviation (the C02 warning RETIRED, OQ12 — the silence is the pin); the call channel answers the announced tip-only bootstrap (the new arm, the announce is the signal)"
fi

# --- d19: an unreachable MARKER_SHA propagates git 128 (C04) -------------
if want d19; then
  m="$(printf 'f%.0s' {1..40})"
  b="$(sha_of HEAD)"
  run_detect EVENT_NAME=workflow_call EVENT_BEFORE= MARKER_SHA="$m" SHA="$b"
  [ "$RC" -eq 128 ] ||
    fail "d19: an unreachable MARKER_SHA ($m) exited $RC, expected git 128 — the diff is unmasked (no '|| true', no rescue): an endpoint git cannot resolve must fail the job loudly, not be reported as 'nothing changed'"
  [ -z "$OUT" ] ||
    fail "d19: the unreachable-marker channel printed stdout '$OUT' — a red detection must print NO JSON (a JSON verdict would tell the matrix to push a range that failed to resolve)"
  if ! printf '%s\n' "$ERR" | grep -q 'base=marker'; then
    fail "d19: the echo before the die names no 'base=marker' — the marker arm must win (and be named) before the unmasked diff dies"
  fi
  ok "d19: an unreachable MARKER_SHA (an oid no commit resolves to) propagates git 128 with NO JSON on stdout through the unmasked diff (the echo names base=marker before the die)"
fi

# --- d20: the marker arm precedes the payload die (C04) ------------------
if want d20; then
  a="$(sha_of HEAD~2)"
  d="$(sha_of HEAD)"
  run_detect EVENT_NAME=workflow_call EVENT_BEFORE= MARKER_SHA="$a" SHA="$d"
  [ "$RC" -eq 0 ] ||
    fail "d20: the called run with a marker + empty before exited $RC — the marker arm must PRECEDE the payload die (the C15 call-aware reorder): the empty before is expected on a call, and the marker..sha diff answers it"
  [ "$OUT" = '["kubernetes","kubernetes-hardened"]' ] ||
    fail "d20: the marker..sha range (c0..c2) printed '$OUT', expected the sorted array of the two template dirs touched between the marker and the sha (the chart + ungated touches are gated out)"
  if ! printf '%s\n' "$ERR" | grep -q 'base=marker'; then
    fail "d20: the echo names no 'base=marker' — the marker arm won, and a marker-fed call run must read differently from a bootstrap one"
  fi
  ok "d20: workflow_call + MARKER_SHA set + empty before diffs marker..sha (base=marker, exit 0) — the marker check precedes the empty-before die (the C15 call-aware reorder)"
fi

# --- d21: the called tip-only bootstrap arm (C04) ------------------------
if want d21; then
  d="$(sha_of HEAD)"
  run_detect EVENT_NAME=workflow_call EVENT_BEFORE= MARKER_SHA= SHA="$d"
  [ "$RC" -eq 0 ] ||
    fail "d21: the called bootstrap (no marker, empty before) exited $RC — it must answer the tip-only HEAD^..HEAD bootstrap, NEVER the push-payload die (the die is scoped to real pushes; a called run carries no push payload, so an empty before is expected)"
  [ "$OUT" = '[]' ] ||
    fail "d21: the tip-only bootstrap (c1..c2: chart only) printed '$OUT', expected [] — the template touches are in c1, PREVIOUS to the tip"
  if ! printf '%s\n' "$ERR" | grep -qF '::warning::first called run (workflow_call, no marker): tip-only detection over HEAD^..HEAD'; then
    fail "d21: the bootstrap did not announce itself — the ::warning:: line is where the called tip-only narrowing says it narrowed (a silent narrowing hides the commits it skipped)"
  fi
  if ! printf '%s\n' "$ERR" | grep -q 'base=tip-only'; then
    fail "d21: the bootstrap echo names no 'base=tip-only' — the base token must name the arm that won"
  fi
  ok "d21: workflow_call + no marker + empty before answers the announced tip-only HEAD^..HEAD bootstrap (base=tip-only, exit 0) — NEVER the push-payload die (the C15 call arm)"
fi

# --- d22: the die stayed scoped to real pushes (C04) ---------------------
if want d22; then
  d="$(sha_of HEAD)"
  run_detect EVENT_NAME=push EVENT_BEFORE= MARKER_SHA= SHA="$d"
  [ "$RC" -ne 0 ] ||
    fail "d22: a REAL push with an empty before (marker empty) exited 0 — the die stays scoped to real pushes: no push payload sends an empty before, and reading it as a first push would silently narrow a multi-commit push to the tip commit"
  [ -z "$OUT" ] || fail "d22: the die channel printed stdout '$OUT' — a die must print no JSON"
  printf '%s\n' "$ERR" | grep -qF 'push arm: EVENT_BEFORE is empty, which no push payload sends' ||
    fail "d22: the die message is not the scoped C02 fatal — 'push arm: EVENT_BEFORE is empty, which no push payload sends'"
  ok "d22: a real push + empty before + no marker STILL DIES (naming before) — the die stayed scoped to real pushes, the marker arm moved ahead of it (d20/d21 answer the call channel instead)"
fi

printf 'PASS: coder template detect checks (%d ok)\n' "$checks"
