# Friction — cf-6 run -2 (forgejo-container-builds-2)

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; **coord appends (its own items included)** — this file ships as folder boilerplate only, and the planner's discoveries went to `DECISIONS.md` (post-merge ground) and to RESULT `friction:` instead of here.

## Inherited live (do not rediscover — full ledgers: run 0
`…/2026-11-cf-6-feat-forgejo-container-builds/FRICTION.md`, run -1
`…/2026-11-cf-6-feat-forgejo-container-builds-1/FRICTION.md`)

- **dev-renovate MCP has no worktree visibility** — pass the `renovate.json` text inline as
  `configContent`; report NOT-RUN for anything needing path resolution (never a fake pass).
- **Suite selectors take groups as separate argv words** — `'t d r'` (one argv) dies with
  `unknown check id`; per-leg ids work; re-verified this session on the merged tree (`rc=2`).
- **`-strata-q4` cold-arena `connection refused` / `cancelled` on a subagent's first fire** — one
  sanctioned retry per the cf-106 precedent; this run's second repeat is what the owner's
  OpenRouter-flash word covers (DECISIONS: rule-conformant fallback, not a new ruling).
- **Scratch trees must be `git init`ed** (the suites resolve the repo root with
  `git rev-parse --show-toplevel`) and edit/write tools are denied outside the repo — build harnesses
  under `/tmp/opencode` by shell heredoc. **`git init` alone is NOT isolation: build scratch with
  `tar --exclude=.git` or `git archive`, never `cp -a`.** A C03 review copied a *worktree* with `cp -a`,
  and a worktree's `.git` is a pointer *file* — so the pointer came along, the later `git init` was a
  no-op, and the scratch's mutation commits plus two `user.*` config keys landed on the real branch.
  Disclosed, remediated (`git reset --mixed`, keys unset, tree destroyed, gates re-run) and verified
  independently by coord (`git log --format=%h%x09%an` showed only the intended commits). · open
- **`npx aislop ci --changes` scores the whole branch range**, not the chunk's files — read it as a
  range gate (post-merge it reports 0/0 over 106 files).
- **Agent-surface scope fences (`agents-md.sh c7`, `rulesync-surface.sh c8`, `gate.sh t14`) read an
  *uncommitted* plan folder as an out-of-scope path change** — they redden while planning work is
  untracked and clear the moment the coordinator commits it (proven by a scratch-repo replay with a
  commit). Resolution: do not edit another ticket's rule source to silence them; report it, commit,
  re-run.
- **A human question round keeps the 2 h stale-lock clock running** (twice on this card) — verify
  `pipeline_status` before acting on a `PIPELINE LOCK LOST` notice, then the one sanctioned
  continue-anyway question; commit planning records early so a reap never strands an untracked folder.
