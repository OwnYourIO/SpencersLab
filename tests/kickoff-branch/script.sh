#!/usr/bin/env bash
# Branch-mint behavior suite for scripts/kickoff-mint-branch.sh
# (2026/2026-10-bug-kickoff-mints-run-branch, C01).
#
# Pins the verdict contract of chunks/C01.md: `MINTED|EXISTS|REJECT` on stdout,
# one line; `<verdict> <branch> <sha>` for the first two; exit 0 on MINTED and
# EXISTS, exit 1 with a REJECT line for every validation rejection (AC3);
# usage + exit 2 on wrong arity; the branch == worktree-basename invariant (Q2)
# enforced; never a mint target for the main checkout or any unregistered dir
# (the rule that makes the wildcard grant safe); args never eval'd; the scratch
# repo unharmed on rejects; the base commit preserved; the cf-52 recovery
# ordering (commit detached, then hand-`checkout -b`) made unnecessary.
# Contract source: plan file "Commands" + chunks/C01.md "## Tests" t1..t7.
# AC trace: t1[AC1+AC3-static] t2[AC2 t2 / AC3] t3[AC2 t3] t4[AC2 t4]
# t5[AC2 t5] t6[AC2 t6] t7[AC2 t7] t8[C01 task "on checkout failure print
# REJECT <reason> and exit 1" — the checkout-failure arm of the AC3 vocabulary].
#
# Red posture (test phase, by design): scripts/kickoff-mint-branch.sh does not
# exist until C01 dev lands it — t1 reds on the missing file and fail-fast
# stops the run there, naming the absent script (gate.sh t1 precedent). Every
# check is fully satisfiable by a script written to C01.md's task wording —
# nothing here pins an implementation choice (main-vs-linked detection,
# realpath handling, message prose) beyond the mandated verdict lines.
#
# Arm-independent: fixtures are throwaway repos under /tmp/opencode (C01 AC2
# "never against this repo's live worktrees"), so this suite passes identically
# at either operational base (081b57889 or HEAD) once the script lands —
# sibling-suite arm discipline (tests/agent-perms/surface.sh A10) lives in the
# text-pins of tests/kickoff-branch/surface.sh, not here.
#
# Determinism: GIT_CONFIG_GLOBAL/SYSTEM are pinned to /dev/null so host
# config (signing, aliases, defaultBranch) cannot perturb fixtures, and
# GIT_TERMINAL_PROMPT=0 makes any credential or network ask a hard failure —
# the no-network/no-credentials posture (C01 task) then breaks loudly instead
# of hanging.
#
# Usage (harness convention from tests/coord-inwork/surface.sh):
#   bash tests/kickoff-branch/script.sh          # t1..t8
#   bash tests/kickoff-branch/script.sh t2 t3    # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SCRIPT="scripts/kickoff-mint-branch.sh"
# behavior checks invoke the script from assorted cwds (the C01 "works from
# ANY cwd" posture), so the path used for execution is absolute; the relative
# name stays in messages so a red line reads as a repo path.
SCRIPT_ABS="$PWD/$SCRIPT"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/kickoff-script-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 8); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-8]$ ]] || fail "unknown check id '$a' (expected t1..t8)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@invalid

# require_script guards every behavior check: the red line must name the
# missing C01 artifact, never surface as an invocation error (127/ENOENT).
require_script() {
  [ -f "$SCRIPT" ] || fail "$1: $SCRIPT does not exist (C01 AC1 target missing — red before C01 dev phase; the contract is chunks/C01.md)"
}

# scratch <id> — a throwaway repo at $TMP/<id>/repo with one commit on branch
# main; echoes "<repo> <head-sha>". Worktrees are registered per check with
# `add_wt <repo> <wdir>` (detached HEAD at the seed commit, the posture
# worktree_create delivers — the plan's whole premise). Paths never contain
# spaces, so the "repo sha" pair is splittable on the single space.
scratch() {
  local r="$TMP/$1/repo"
  mkdir -p "$TMP/$1"
  git init -q -b main "$r"
  git -C "$r" commit -q --allow-empty -m seed
  printf '%s %s\n' "$r" "$(git -C "$r" rev-parse HEAD)"
}
scratch_repo() { printf '%s\n' "${1%% *}"; }
scratch_sha() { printf '%s\n' "${1##* }"; }
add_wt() { # add_wt <repo> <wdir>
  git -c advice.detachedHead=false -C "$1" worktree add -q --detach "$2" HEAD
}

# mint <dir> <branch> — invokes the script with stdout captured to MINT_OUT,
# stderr to MINT_ERR, exit code to MINT_RC; an arity-0..3 escape hatch: mint
# forwards all args verbatim.
MINT_RC=0 MINT_OUT='' MINT_ERR=''
mint() {
  local rc=0 out
  out=$(bash "$SCRIPT_ABS" "$@" 2>"$TMP/last.err") || rc=$?
  MINT_RC=$rc; MINT_OUT=$out; MINT_ERR=$(cat "$TMP/last.err")
}

# Verdict-shape asserts (AC3: exactly the vocabulary, one stdout line).
expect_one_line() { # <id> <verdict-prefix>
  [[ "$MINT_OUT" == *$'\n'* ]] && fail "$1: stdout is not one line: [$MINT_OUT]"
  [[ "$MINT_OUT" == "$2"* ]] || fail "$1: verdict line is [$MINT_OUT], want the '$2' verdict (AC3 vocabulary)"
}
expect_verdict_sha() { # <id> <verdict> <branch> — full-line match incl. 40-hex sha
  # the pattern goes through a variable: an inline =~ regex cannot carry
  # spaces between its quoted segments
  local re="^$2 $3 [0-9a-f]{40}$"
  [[ "$MINT_OUT" =~ $re ]] \
    || fail "$1: verdict line is [$MINT_OUT], want '$2 $3 <40-hex sha>' on one line (AC3)"
}

# main-untouched guard: the parent repo's main checkout is the scheduled runs'
# working tree — no mint call may move it (plan Q1's owner-problem).
main_state() { # <repo> — "<head-sha>|<branch>"
  printf '%s|%s\n' "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" branch --show-current)"
}

# --- t1: static gate (AC1; shellcheck skip-with-warning, t1 convention cf-50) --
if want t1; then
  require_script t1
  bash -n "$SCRIPT" || fail "t1: bash -n rejects $SCRIPT (AC1)"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$SCRIPT" >"$TMP/sc.log" 2>&1 || { sed -n 1,20p "$TMP/sc.log" >&2; fail "t1: shellcheck findings on $SCRIPT"; }
    ok "t1: bash -n clean; shellcheck clean (when present)"
  else
    skip "t1: shellcheck not installed here — skipped with warning (t1 convention, cf-50)"
    ok "t1: bash -n clean; shellcheck skipped with warning (absent)"
  fi
fi

# --- t2: happy path — MINTED on a detached registered worktree (AC2 t2) --------
if want t2; then
  require_script t2
  pair=$(scratch t2); repo=$(scratch_repo "$pair"); seed=$(scratch_sha "$pair")
  wdir="$TMP/t2/wt/wt-alpha"
  add_wt "$repo" "$wdir"
  main_before=$(main_state "$repo")
  mint "$wdir" wt-alpha
  [ "$MINT_RC" -eq 0 ] || fail "t2: exit $MINT_RC (want 0), stderr: $MINT_ERR"
  expect_one_line t2 MINTED
  expect_verdict_sha t2 MINTED wt-alpha
  [ "$MINT_OUT" = "MINTED wt-alpha $seed" ] || fail "t2: sha is not the worktree's HEAD ($seed): [$MINT_OUT] — the base commit must be preserved (cf-50/cf-52 invariant)"
  [ "$(git -C "$wdir" branch --show-current)" = "wt-alpha" ] || fail "t2: after MINTED the worktree is not on branch wt-alpha"
  [ "$(git -C "$wdir" rev-parse HEAD)" = "$seed" ] || fail "t2: HEAD moved — checkout -b must mint at the current detached HEAD"
  [ "$(git -C "$repo" rev-parse refs/heads/wt-alpha)" = "$seed" ] || fail "t2: refs/heads/wt-alpha not at the minted sha"
  [ "$main_before" = "$(main_state "$repo")" ] || fail "t2: the main checkout moved (was [$main_before]) — a mint never touches it"
  ok "t2: MINTED <name> <sha> on one line, exit 0; branch == basename, created at the preserved detached HEAD; main checkout untouched"
fi

# --- t3: idempotence — second invocation EXISTS, no checkout (AC2 t3) ----------
if want t3; then
  require_script t3
  pair=$(scratch t3); repo=$(scratch_repo "$pair")
  wdir="$TMP/t3/wt/wt-idem"
  add_wt "$repo" "$wdir"
  mint "$wdir" wt-idem
  [ "$MINT_RC" -eq 0 ] || fail "t3: setup mint exit $MINT_RC, want 0: [$MINT_OUT]"
  [[ "$MINT_OUT" =~ ^MINTED\ wt-idem\ [0-9a-f]{40}$ ]] || fail "t3: setup mint did not report MINTED: [$MINT_OUT]"
  first_sha="${MINT_OUT##* }"
  # Move the worktree off the branch on purpose — a resume run may find it
  # detached; EXISTS must still report the branch tip and check nothing out.
  git -C "$wdir" switch -q --detach HEAD
  mint_from=$(cd "$TMP" && bash "$SCRIPT_ABS" "$wdir" wt-idem 2>/dev/null) \
    || fail "t3: second invocation exited nonzero (want exit 0, idempotent no-op)"
  [[ "$mint_from" == *$'\n'* ]] && fail "t3: second verdict is not one line: [$mint_from]"
  [[ "$mint_from" =~ ^EXISTS\ wt-idem\ [0-9a-f]{40}$ ]] \
    || fail "t3: second verdict is [$mint_from], want 'EXISTS wt-idem <sha>' (idempotence contract)"
  [ "${mint_from##* }" = "$(git -C "$repo" rev-parse refs/heads/wt-idem)" ] \
    || fail "t3: EXISTS sha is not the branch tip sha"
  [ -z "$(git -C "$wdir" branch --show-current)" ] || fail "t3: EXISTS checked something out — resume runs are no-ops"
  [ "$(git -C "$wdir" rev-parse HEAD)" = "$first_sha" ] || fail "t3: EXISTS moved the worktree HEAD"
  ok "t3: second run prints EXISTS <branch> <tip-sha>, exit 0, from any cwd, and checks nothing out"
fi

# --- t4: branch != basename → REJECT, repo unharmed (AC2 t4) -------------------
if want t4; then
  require_script t4
  pair=$(scratch t4); repo=$(scratch_repo "$pair")
  wdir="$TMP/t4/wt/wt-mis"
  add_wt "$repo" "$wdir"
  head_sha=$(git -C "$wdir" rev-parse HEAD); main_before=$(main_state "$repo")
  mint "$wdir" some-other-name
  [ "$MINT_RC" -eq 1 ] || fail "t4: exit $MINT_RC, want 1"
  expect_one_line t4 REJECT
  [ "$MINT_OUT" != "REJECT" ] || fail "t4: REJECT must carry a reason (AC3: 'REJECT <reason>')"
  git -C "$repo" rev-parse --verify -q refs/heads/some-other-name 2>/dev/null \
    && fail "t4: REJECT still created refs/heads/some-other-name"
  git -C "$repo" rev-parse --verify -q refs/heads/wt-mis 2>/dev/null \
    && fail "t4: the Q2 invariant violation still minted the basename branch"
  [ -z "$(git -C "$wdir" branch --show-current)" ] || fail "t4: rejected run switched the worktree onto a branch"
  [ "$(git -C "$wdir" rev-parse HEAD)" = "$head_sha" ] || fail "t4: rejected run moved the worktree HEAD"
  [ "$main_before" = "$(main_state "$repo")" ] || fail "t4: rejected run touched the main checkout"
  ok "t4: branch != basename → single-line REJECT with a reason, exit 1, scratch repo and main checkout unharmed"
fi

# --- t5: main checkout + unregistered dirs → REJECT (AC2 t5) -------------------
if want t5; then
  require_script t5
  pair=$(scratch t5); repo=$(scratch_repo "$pair")   # basename 'repo'
  mkdir -p "$TMP/t5/loose" "$repo/sub"
  main_before=$(main_state "$repo")
  mint "$repo" repo
  [ "$MINT_RC" -eq 1 ] || fail "t5: main checkout exit $MINT_RC, want 1"
  expect_one_line t5 REJECT
  mint "$TMP/t5/loose" loose
  [ "$MINT_RC" -eq 1 ] || fail "t5: unregistered non-repo dir exit $MINT_RC, want 1"
  expect_one_line t5 REJECT
  mint "$repo/sub" sub
  [ "$MINT_RC" -eq 1 ] || fail "t5: in-repo unregistered subdir exit $MINT_RC, want 1"
  expect_one_line t5 REJECT
  mint "$TMP/t5/does-not-exist" does-not-exist
  [ "$MINT_RC" -eq 1 ] || fail "t5: nonexistent dir exit $MINT_RC, want 1"
  expect_one_line t5 REJECT
  for b in repo loose sub does-not-exist; do
    git -C "$repo" rev-parse --verify -q "refs/heads/$b" 2>/dev/null \
      && fail "t5: rejected call still created refs/heads/$b"
  done
  [ "$main_before" = "$(main_state "$repo")" ] || fail "t5: a rejected call moved the main checkout — the wildcard grant's safety rule is broken"
  ok "t5: main checkout, unregistered dir, in-repo subdir and nonexistent dir all REJECT exit 1; main checkout never moves"
fi

# --- t6: arity + bad-name negatives + no-eval of args (AC2 t6) -----------------
if want t6; then
  require_script t6
  pair=$(scratch t6); repo=$(scratch_repo "$pair")
  wdir="$TMP/t6/wt/wt-six"
  add_wt "$repo" "$wdir"
  for argv in "" "$wdir" "$wdir wt-six extra"; do
    # shellcheck disable=SC2086  # deliberate: forwarding the empty/extra-arg cases verbatim
    mint $argv
    [ "$MINT_RC" -eq 2 ] || fail "t6: arity case [$argv] exit $MINT_RC, want 2"
    cat_out="$MINT_OUT$MINT_ERR"
    printf '%s' "$cat_out" | grep -qiE 'usage' || fail "t6: arity case [$argv] printed no usage line (out=[$MINT_OUT] err=[$MINT_ERR])"
  done
  for bad in '-lead' 'bad;name' 'bad name' 'bad~name' 'bad*name' 'bad!name'; do
    mint "$wdir" "$bad"
    [ "$MINT_RC" -eq 1 ] || fail "t6: bad name [$bad] exit $MINT_RC, want 1"
    expect_one_line t6 REJECT
  done
  # name-validity must bite even when branch == basename: a worktree dir whose
  # own name violates the refname grammar is rejected on the name rule.
  for bad in '-dash' 'pwn;dir'; do
    add_wt "$repo" "$TMP/t6/neg/$bad"
    mint "$TMP/t6/neg/$bad" "$bad"
    [ "$MINT_RC" -eq 1 ] || fail "t6: basename-equal invalid name [$bad] exit $MINT_RC, want 1 (leading - is never an option string; the regex rejects ;)"
    expect_one_line t6 REJECT
  done
  # no-eval proof: a payload ';' + space in the branch arg must neither execute
  # nor create the marker.
  mint "$wdir" 'wt-alpha; touch '"$TMP/PWNED"
  [ "$MINT_RC" -eq 1 ] || fail "t6: injection arg exit $MINT_RC, want 1"
  expect_one_line t6 REJECT
  mint "$TMP/t6/neg/pwn;dir" 'pwn;dir; touch '"$TMP/PWNED2"
  [ "$MINT_RC" -eq 1 ] || fail "t6: second injection exit $MINT_RC, want 1"
  [ ! -e "$TMP/PWNED" ] && [ ! -e "$TMP/PWNED2" ] || fail "t6: the script EVALUATED its arguments — markers $TMP/PWNED* exist"
  git -C "$repo" rev-parse --verify -q refs/heads/wt-six 2>/dev/null \
    && fail "t6: a rejected/usage call minted refs/heads/wt-six anyway"
  ok "t6: 0/1/3 args → usage + exit 2 with no side effect; six bad names + two basename-equal invalid names → REJECT exit 1; no arg was ever eval'd"
fi

# --- t7: mint at detached commits carries the work (AC2 t7) --------------------
if want t7; then
  require_script t7
  pair=$(scratch t7); repo=$(scratch_repo "$pair"); seed=$(scratch_sha "$pair")
  wdir="$TMP/t7/wt/wt-seven"
  add_wt "$repo" "$wdir"
  git -C "$wdir" commit -q --allow-empty -m work-on-detached
  work=$(git -C "$wdir" rev-parse HEAD)
  [ "$work" != "$seed" ] || fail "t7: fixture failed — detached commit did not advance HEAD"
  mint "$wdir" wt-seven
  [ "$MINT_RC" -eq 0 ] || fail "t7: exit $MINT_RC (want 0), stderr: $MINT_ERR"
  expect_verdict_sha t7 MINTED wt-seven
  [ "$MINT_OUT" = "MINTED wt-seven $work" ] \
    || fail "t7: MINTED sha is not the detached HEAD the work sits on (want $work): [$MINT_OUT]"
  git -C "$repo" merge-base --is-ancestor "$work" refs/heads/wt-seven \
    || fail "t7: the minted branch does not include the detached commit — the cf-52 recovery ordering was still required"
  [ "$(git -C "$repo" rev-parse refs/heads/main)" = "$seed" ] || fail "t7: main moved"
  ok "t7: committing on detached HEAD then minting lands the branch AT the work commit — no recovery ordering needed (cf-52 friction closed)"
fi

# --- t8: checkout-failure arm → REJECT <reason> exit 1 (C01 task) --------------
# 'dot.' passes C01's name regex (leading letter, inner dot) and equals the
# worktree basename, but git's check-ref-format rejects a trailing dot — the
# only reachable path through the "on checkout failure print REJECT <reason>
# and exit 1" clause. The script must speak the verdict, not leak git's exit.
if want t8; then
  require_script t8
  pair=$(scratch t8); repo=$(scratch_repo "$pair")
  wdir="$TMP/t8/wt/dot."
  add_wt "$repo" "$wdir"
  main_before=$(main_state "$repo")
  mint "$wdir" 'dot.'
  [ "$MINT_RC" -eq 1 ] || fail "t8: exit $MINT_RC, want 1"
  expect_one_line t8 REJECT
  [ "$MINT_OUT" != "REJECT" ] || fail "t8: REJECT must carry the checkout-failure reason"
  git -C "$repo" rev-parse --verify -q 'refs/heads/dot.' 2>/dev/null \
    && fail "t8: branch refs/heads/dot. exists despite the REJECT verdict"
  [ -z "$(git -C "$wdir" branch --show-current)" ] || fail "t8: the failed mint left the worktree on a branch"
  [ "$main_before" = "$(main_state "$repo")" ] || fail "t8: the failed mint touched the main checkout"
  ok "t8: git refusing checkout -b (invalid refname past the script's regex) surfaces as REJECT <reason>, exit 1, with the worktree left detached"
fi

printf 'PASS: kickoff-mint-branch behavior checks (%d ok)\n' "$checks"
