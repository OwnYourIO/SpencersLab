#!/usr/bin/env bash
# C01 acceptance checks (2026-10-feat-forgejo-infra-and-runner): the untracked
# STORM research audit trail moved from the repo root into the feature folder,
# RESEARCH.md's pointer updated to the new location, and the move committed on
# its own (the feature's first dev commit carries nothing else).
#
# The plan/chunk text says "11 files"; the audit trail actually holds 13
# (3 top-level + 5 perspectives x 2 raw files), so this test lists all 13 —
# the contract is "the whole directory moved", which the explicit list plus
# the exact-file-count check enforces.
#
# The pointer check is a RESOLUTION check, not a string diff: after the move
# RESEARCH.md sits next to the trail, so the relative path it names is the
# same string as the old repo-root-relative one. What distinguishes old from
# new is (a) the path exists when read from the feature folder and (b) the
# root-level storm-runs/ is gone, so the pointer can no longer be read as a
# repo-root claim.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/audit-trail.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FEAT=".agents/plans/2026/2026-10-feat-forgejo-infra-and-runner"
DEST="$FEAT/storm-runs/forgejo-act-runner-on-kubernetes-for-spencerslab-dev-cluster"
RESEARCH="$FEAT/RESEARCH.md"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# --- t1: root storm-runs/ is gone ----------------------------------------
[ ! -e storm-runs ] ||
  fail "t1: storm-runs/ still exists at the repo root (the move into the feature folder has not happened)"
ok "t1: no storm-runs/ at the repo root"

# --- t2: every audit-trail file exists under the feature folder ----------
files=(
  "perspectives.md"
  "sources.md"
  "contradictions.md"
  "raw/act-runner-project.notes.md"
  "raw/act-runner-project.sources.tsv"
  "raw/helm-chart-ecosystem.notes.md"
  "raw/helm-chart-ecosystem.sources.tsv"
  "raw/k8s-homelab-practitioner.notes.md"
  "raw/k8s-homelab-practitioner.sources.tsv"
  "raw/ops-security-reviewer.notes.md"
  "raw/ops-security-reviewer.sources.tsv"
  "raw/upstream-forgejo-docs.notes.md"
  "raw/upstream-forgejo-docs.sources.tsv"
)
for f in "${files[@]}"; do
  [ -f "$DEST/$f" ] ||
    fail "t2: $DEST/$f is missing (the audit trail was not moved into the feature folder)"
done
count=$(find "$DEST" -type f | wc -l)
[ "$count" -eq "${#files[@]}" ] ||
  fail "t2: $DEST holds $count files, expected exactly ${#files[@]} (whole-directory move, nothing left behind or added)"
ok "t2: all ${#files[@]} audit-trail files exist under $DEST (nothing else)"

# --- t3: RESEARCH.md's pointer resolves from the feature folder ----------
[ -f "$RESEARCH" ] || fail "t3: $RESEARCH is missing"
ptr=$(grep -oE '`storm-runs/[^`]+`' "$RESEARCH" | head -n 1 | tr -d '`' || true)
[ -n "$ptr" ] ||
  fail "t3: $RESEARCH names no backticked storm-runs/ audit-trail path (the pointer line is missing or reworded beyond recognition)"
[ -d "$FEAT/$ptr" ] ||
  fail "t3: the audit-trail path $RESEARCH names ('$ptr') does not exist relative to the feature folder — the pointer still implies the old repo-root location"
ok "t3: $RESEARCH points at $ptr, which resolves from the feature folder"

# --- t4: the move is committed, and that commit carries nothing else ------
commit=$(git log --format=%H -n 1 -- "$DEST" || true)
[ -n "$commit" ] ||
  fail "t4: no commit touches $DEST (the move is not committed)"
changed=$(git show --name-only --format= "$commit")
[ -n "$changed" ] || fail "t4: commit $commit touches $DEST but changed no files"
while IFS= read -r f; do
  case "$f" in
    "$DEST"/* | "$RESEARCH") ;;
    *) fail "t4: move commit $(git log --format=%h -1 "$commit") contains an unrelated file: $f (the first dev commit must carry only the moved audit trail + the RESEARCH.md pointer)" ;;
  esac
done <<< "$changed"
ok "t4: move commit $(git log --format=%h -1 "$commit") carries only the moved files + $RESEARCH"

printf 'PASS: audit-trail checks (%d ok)\n' "$checks"
