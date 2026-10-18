---
root: true
targets:
  - '*'
description: "Comment policy and AI-slop quality gate"
globs:
  - '**/*'
---

# Comments and code quality

- Comments explain **why** (constraints, invariants, trade-offs, links to issues). Never restate what the code does, narrate history ("now we…", "updated to…"), or describe planned work.
- When writing or editing comments/docstrings, or before handing back a change, apply the `comment-slop` skill (rulesync-managed, vendored from `dashed/claude-marketplace` — see `.rulesync/skills/comment-slop/VENDORED.md`). It auto-selects when comment work is in scope.
- Before declaring a task done, run the `aislop` skill (`$aislop`; manual-only by design — it is hidden from auto-selection). Resolve every error and every fixable warning, or explain why a finding is a false positive.
- The `aislop-gate` plugin (`.opencode/plugin/aislop-gate/index.ts`, hand-written — NOT rulesync-generated) may append "aislop findings" to edit/write tool results. Treat them as review comments on your own diff and fix them in the same turn.
- CI runs `aislop ci --changes` on PRs (`.github/workflows/aislop.yaml`, gate config in `.aislop/config.yml`): every file a PR touches must clear the score floor and have no error-severity findings. A change that fails it is not done.
- The vendored skills are pinned: to update one, re-fetch at a new SHA, re-apply the aislop frontmatter patch (see its `VENDORED.md` note), diff, and bump the recorded SHA. `.rulesync/skills/.curated/` (rulesync fetch cache) stays out of git.
