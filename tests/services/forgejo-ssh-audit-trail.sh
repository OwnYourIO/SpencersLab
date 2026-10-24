#!/usr/bin/env bash
# C01 acceptance checks (2026-10-feat-forgejo-ssh): the untracked STORM
# research audit trail moved from the repo root into this ticket's feature
# folder and that move committed on its own as the feature's first dev
# commit (which also bootstraps branch feat-forgejo-ssh-ssh from the
# detached-HEAD worktree).
#
# Contract sources: chunks/C01.md acceptance criteria 1-5 + its Tests list
# (t1-t5). t6 below covers criterion 4 (no stray untracked trail files)
# directly via git status.
#
# The trail at move time holds exactly ONE file (perspectives.md) plus an
# empty raw/ directory. Git does not track empty directories, so the
# contract counts FILES, not dirs — a dev-added .gitkeep would fail t2.
# Unlike the predecessor ticket, this ticket's RESEARCH.md carries no
# storm-runs pointer line (C01 Notes default), so there is no pointer check:
# the move commit may carry nothing but the destination files.
#
# Red today for the right reason: t1 fails while the trail still sits
# untracked at the repo root (the move has not happened).
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/forgejo-ssh-audit-trail.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FEAT=".agents/plans/2026/2026-10-feat-forgejo-ssh"
DEST="$FEAT/storm-runs/forgejo-ssh-exposure-k3s-traefik"
TRAIL_FILE="$DEST/perspectives.md"
BRANCH="feat-forgejo-ssh-ssh"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- t1: root storm-runs/ is gone -----------------------------------------
[ ! -e storm-runs ] ||
  fail "t1: storm-runs/ still exists at the repo root (the move into $FEAT has not happened)"
ok "t1: no storm-runs/ at the repo root"

# --- t2: whole directory moved, nothing left behind or added --------------
[ -f "$TRAIL_FILE" ] ||
  fail "t2: $TRAIL_FILE is missing (the audit trail was not moved into the feature folder)"
count=$(find "$DEST" -type f 2>/dev/null | wc -l)
[ "$count" -eq 1 ] ||
  fail "t2: $DEST holds $count files, expected exactly 1 — the trail is perspectives.md plus an empty raw/ dir (count files, not dirs; nothing left behind or added)"
ok "t2: $TRAIL_FILE exists and nothing else is under $DEST (whole-directory move)"

# --- t3: content integrity vs the committed file --------------------------
# The move commit is the one that ADDED the file at its destination
# (--diff-filter=A), so a later commit touching the trail cannot displace it.
commit=$(git log --format=%H -n 1 --diff-filter=A -- "$TRAIL_FILE" || true)
[ -n "$commit" ] ||
  fail "t3: no commit added $TRAIL_FILE (the move is not committed)"
git show "$commit:$TRAIL_FILE" 2>/dev/null | cmp -s - "$TRAIL_FILE" ||
  fail "t3: $TRAIL_FILE differs from its content in commit $(git log --format=%h -1 "$commit") (the trail was edited during the move)"
ok "t3: $TRAIL_FILE is byte-identical to its content in move commit $(git log --format=%h -1 "$commit")"

# --- t4: the move commit carries only destination files, on the branch ----
changed=$(git show --name-only --format= "$commit")
[ -n "$changed" ] || fail "t4: commit $commit touches $DEST but changed no files"
while IFS= read -r f; do
  case "$f" in
    "$DEST"/*) ;;
    *) fail "t4: move commit $(git log --format=%h -1 "$commit") contains an unrelated file: $f (the first dev commit must carry only the moved audit trail — pipeline artifacts stay with coord)" ;;
  esac
done <<< "$changed"
git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null ||
  fail "t4: branch $BRANCH does not exist (C01 must create and attach it before committing)"
git merge-base --is-ancestor "$commit" "refs/heads/$BRANCH" ||
  fail "t4: move commit $(git log --format=%h -1 "$commit") is not an ancestor of $BRANCH (the move was committed on the wrong branch)"
ok "t4: move commit $(git log --format=%h -1 "$commit") carries only files under $DEST and is on $BRANCH"

# --- t5: predecessor regression stays green --------------------------------
# The predecessor script targets the OLD ticket's trail. It is red only while
# THIS ticket's untracked root storm-runs/ still exists; t1's move restores it.
if bash tests/services/audit-trail.sh >/dev/null 2>&1; then
  ok "t5: tests/services/audit-trail.sh exits 0 (predecessor regression green)"
else
  fail "t5: tests/services/audit-trail.sh exited non-zero (predecessor audit-trail contract broken — the root storm-runs/ must be gone for its t1)"
fi

# --- t6: no stray untracked trail files (criterion 4) ----------------------
stray=$(git status --porcelain | grep -E '^\?\?.*storm-runs' || true)
[ -z "$stray" ] ||
  fail "t6: git status shows untracked trail file(s) after the move:
$stray"
ok "t6: git status shows no stray untracked storm-runs entries"

printf 'PASS: forgejo-ssh-audit-trail checks (%d ok)\n' "$checks"
