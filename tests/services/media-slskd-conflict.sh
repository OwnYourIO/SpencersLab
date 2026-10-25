#!/usr/bin/env bash
# C01 acceptance checks (2026-10-debug-lidarr-music-stack): the stash-apply
# conflict in charts/slskd/values.yaml is resolved to the committed content —
# both slskd image refs carry the Renovate-bumped tag "0.26.2" (a60d11a0a) and
# the index is committable again, which is the precondition C02 needs to land
# the lidarr fix on this worktree.
#
# Legs map to the numbered acceptance criteria in chunks/C01.md:
#   t1 -> 1 (conflict markers gone)
#   t2 -> 2 (file byte-equals HEAD; initContainer + main container 0.26.2)
#   t3 -> 3 (no unmerged paths, no dirty tracked entries, both stashes kept)
#   t4 -> 4 (slskd service trio still referenced)
#
# t2 compares against HEAD rather than pinning the literal blob 8e2bf0ca4 the
# plan quotes: dev merges main into this branch to pick up newer commits
# (AGENTS.md flow) before C02's fix commit, and the criterion's "committed
# version" is then whatever HEAD carries for this file — a frozen hash would
# assert a stale tree.
#
# t3 asserts both stash entries still exist because the chunk forbids dev to
# drop them; the plan's USER step 1 drops stash@{0} only after this suite
# passes, so re-running it after that human step fails t3 by design.
#
# Read-only suite: it touches no file and runs no git mutation, so it may be
# executed at any point of the pipeline.
#
# Run from anywhere in the worktree:
#   bash tests/services/media-slskd-conflict.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SLSKD_VALUES="charts/slskd/values.yaml"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- t1: no conflict markers remain ---------------------------------------
[ -f "$SLSKD_VALUES" ] || fail "t1: $SLSKD_VALUES is missing"
markers=$(grep -cE '^(<<<<<<<|=======|>>>>>>>)' "$SLSKD_VALUES" || true)
[ "$markers" -eq 0 ] ||
  fail "t1: $SLSKD_VALUES still holds $markers conflict-marker line(s) — the stash-apply conflict is unresolved (criterion 1)"
ok "t1: no '<<<<<<< / ======= / >>>>>>>' lines in $SLSKD_VALUES (criterion 1)"

# --- t2: file == HEAD, and both image refs are the bumped 0.26.2 -----------
file_hash=$(git hash-object "$SLSKD_VALUES")
head_hash=$(git rev-parse "HEAD:$SLSKD_VALUES")
[ "$file_hash" = "$head_hash" ] ||
  fail "t2: $SLSKD_VALUES (blob $file_hash) differs from HEAD (blob $head_hash) — the resolution must restore the committed version, not hand-edit the conflict region (criterion 2)"
ok "t2: $SLSKD_VALUES is byte-identical to HEAD (criterion 2)"

# Exactly the two slskd image refs (initContainer + main container) exist and
# both are 0.26.2. A comment mentioning 0.26.0 ships with HEAD ("Plain 0.26.0
# tag verified..." above the main-container tag) and the t2 hash check pins it
# in place, so the version scan stays on tag: lines only.
tag_count=$(grep -cE '^[[:space:]]*tag:' "$SLSKD_VALUES" || true)
tag_262=$(grep -cE '^[[:space:]]*tag:[[:space:]]*"0\.26\.2"' "$SLSKD_VALUES" || true)
[ "$tag_count" -eq 2 ] && [ "$tag_262" -eq 2 ] ||
  fail "t2: expected both image refs to read tag: \"0.26.2\", found $tag_262 of $tag_count tag: line(s) — taking the stashed side would revert the Renovate bump a60d11a0a and desynchronise initContainer from the main container (criterion 2)"
ok "t2: initContainer AND main container both pin tag \"0.26.2\" (criterion 2)"

# --- t3: worktree committable, stashes untouched ----------------------------
unmerged=$(git ls-files -u)
[ -z "$unmerged" ] ||
  fail "t3: the index still holds unmerged entries — git refuses any commit until 'git add' clears them (criterion 3): $unmerged"
ok "t3: git ls-files -u is empty, no unmerged paths (criterion 3)"

dirty=$(git status --porcelain -uno)
[ -z "$dirty" ] ||
  fail "t3: tracked files differ from HEAD — the other six stash-touched files must sit at HEAD content, and any leftover edit would ride into C02's commit (criterion 3): $dirty"
ok "t3: git status --porcelain -uno is empty (criterion 3)"

stash_list=$(git stash list)
printf '%s\n' "$stash_list" | grep -q 'On add-music-to-media' ||
  fail "t3: the 'On add-music-to-media' stash disappeared — dropping stash@{0} is the plan's USER step 1, executed only after this suite passed (criterion 3)"
printf '%s\n' "$stash_list" | grep -q 'On main' ||
  fail "t3: the 'On main' stash (stash@{1}) disappeared — it is explicitly out of scope (criterion 3)"
ok "t3: both stash entries still listed (criterion 3)"

# --- t4: regression trio ----------------------------------------------------
for f in services/media/prod/values.yaml services/proxy-local/prod/values.yaml custom-values/media/prod-values.yaml; do
  [ -f "$f" ] || fail "t4: $f is missing — the slskd service trio must survive conflict resolution (criterion 4)"
  hits=$(grep -c 'slskd' "$f" || true)
  [ "$hits" -ge 1 ] ||
    fail "t4: $f no longer mentions slskd — every service needs chart entry + ApplicationSet values entry + proxy values entry (AGENTS.md), and criterion 4 guards them against the stash work (hits=$hits)"
done
ok "t4: slskd referenced in the ApplicationSet values, proxy values and custom-values files (criterion 4)"

printf 'PASS: media-slskd-conflict checks (%d ok)\n' "$checks"
