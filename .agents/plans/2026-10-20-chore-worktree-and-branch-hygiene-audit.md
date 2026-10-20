# 2026-10-20 chore: worktree & branch hygiene audit (SpencersLab + opencode/openchamber)

Type: chore (read-only audit + two user-approved cleanups)

## Goal

Audit the repo for dangling worktrees, branches, and stale references in files
and opencode/openchamber state. Nothing removed without explicit user
confirmation.

## Context discovered during the audit

An integration sweep was actively running during the audit (another session):
cherry-picks of branch tips into `main`, rebases onto fresh `origin/main`,
pushes, and new commits between 01:37–01:50 UTC. `.git/index.lock` was present
at one point. Everything tied to that sweep (main checkout,
`can-you-load-…/fusion-mvcs8r5s`, g1–g4 coder-workspace worktrees) was
therefore classified as in-flight, not dangling.

## Findings

- 33 worktrees registered in git, all directories present; no prunable or
  orphan entries; no locked worktrees.
- opencode DB (`opencode.db` `worktree`/`session_v2`/`project_directory`):
  all 40 registered worktrees exist; 0 of 173 live sessions point at missing
  directories. OpenCode state is consistent.
- 6 opencode worktree registrations belong to other repos
  (`debug-new-buttons-*`, `fix-searxng-mcp-*`); directories exist, flagged to
  the user, out of scope.
- Anomaly: `/home/coder/.config/openchamber/tmp/oc-integrate-Oe23aX` was a
  second checkout of `main` left behind by openchamber's integrate flow
  (created 2026-10-18). Working tree == index == stale snapshot; 53 phantom
  staged changes vs current main; zero unique content.
- 24 branches fully merged into main (17 with worktrees, some carrying
  uncommitted residue: regenerated `.opencode/agents/*` plus hivetools/grow
  drafts). Live opencode sessions remain attached to several of those
  worktrees.
- Unmerged leftovers with real commits: `add-dev-server`,
  `add-mayan-edms-to-grow`, `add-pictaria-to-home-services`,
  `please-implement-…-keycl/…` (no worktree), `recovery`; plus
  effectively-integrated tips `feat/coder-workspace-debian-rebuild` and
  `we-need-…/fusion-mvekra9w`.
- 50 stale remote-tracking refs (upstream-deleted).

## Changes made (user-approved)

1. Removed the openchamber tmp worktree:
   `git worktree remove --force /home/coder/.config/openchamber/tmp/oc-integrate-Oe23aX`
   — verified gone from `git worktree list`, `.git/worktrees/` admin dir
   removed, tmp dir emptied; `main` now has exactly one checkout.
2. Pruned 50 stale remote-tracking refs: `git remote prune origin`
   (local-only) — follow-up dry-run reports 0 stale refs.

## Deferred by user decision

- All 24 merged branches + worktrees: kept (integration sweep still running;
  live sessions attached; dirty residue would need per-item review).
- All unmerged leftover branches: kept for now.

## Validation

- `git worktree list` / `git worktree list --porcelain`: no prunable/locked
  entries; single `main` checkout.
- `git remote prune origin --dry-run`: 0 stale refs remain.
- Existence + dirty-state sweep over all worktree directories before and
  after.
- No chart changes → helm lint/template not applicable. Nothing was pushed.