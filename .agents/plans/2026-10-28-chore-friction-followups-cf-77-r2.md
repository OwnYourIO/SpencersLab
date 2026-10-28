# 2026-10-28 chore: cf-77 run-2 friction follow-ups (owner-directed, in-session)

Owner instruction: address all open friction items from the cf-77 runs in this session
(the code-agent seat, after the run-2 merge to main), then link the board cards.
Board cards #64–67 on AI-Dev track the same items.

## Changes

1. **Dev-family edit-deny narrowed** (card #64; `.rulesync/subagents/{agent-dev-local,
   agent-dev-pr,dev,dev-local,dev-pr}.md` + regenerated `.opencode/agents/` mirrors):
   the blanket `edit .agents/** deny` (and `.kilo/**`) over-reached `.agents/notes/`,
   which is repo content per AGENTS.md — it forced shell-channel runbook writes in
   both cf-77 runs (FRICTION 2026-10-27/28). Now denies exactly the machinery
   subtrees (`plans|skills|agents|commands`, both `.agents/` and `.kilo/` spellings)
   and carries an explicit `allow` on `.agents/notes/**`.
2. **Friction-round routing fixed** (card #67; `.rulesync/skills/pipeline-role-coord/
   SKILL.md` + mirror): step 10 now creates one board intake card per checked item
   via `dev-boards` instead of launching in-session `agent-plan` tickets; the
   non-board `agent-coord` fallback keeps the standalone-ticket shape.
3. **No-daemon posture + agent-shell tooling documented as repo law** (card #66;
   `.rulesync/rules/overview.md` → AGENTS.md, `skills/container-creation/SKILL.md`):
   container-chunk `docker build` ACs are CI-primary (`docker-build.yaml` on push is
   authoritative; GHCR layer/digest captures are the local substitutes — a
   no-daemon line in `commands_run` is the designed passing shape, not a deviation);
   plus the `helm` PATH / `npx aislop` / per-directory pytest recipes.
4. **release.yaml hardened** (friction round item; both `Add repositories` steps):
   the awk now emits NAME + first URL-shaped field only, so a declared dependency
   with an empty `repository:` column can no longer shift `unpacked` into the
   `helm repo add` URL slot and break every future release job under `bash -e`
   (the cf-77 r2 subchart-hostility repro).
5. **Runbook test docstrings** (`charts/llama-swap/tests/test_strata_runbook.py`):
   the two line-scoped negation scanners now carry the author rule that prose
   hard-wrap must not separate a negation from its token (cf-77 r2 wrap-line false-
   fail; owner-directed in-session edit of a test-session-owned file).
6. **Stale test expectations re-pinned** (`tests/renovate/dockerfile-pins.sh`,
   `tests/coder-workspace/image-structure.sh`): uv `0.13.1→0.13.5`, node
   `v26.12.0→26.12.1`, golang `1.27.2→1.27.3`, base
   `debian:13-slim@sha256:a29215f6…→62bd423a…` — renovate had bumped the
   coder-workspace Dockerfile on main past its ticket-time literals; the suites
   now match the shipped image (this closes the red cf-77's test session had been
   forced to exclude from its gates).

## Commands (validation)

- `npx rulesync generate` → 7 surfaces written; `npx rulesync generate --check` → all up to date
- `bash tests/agent-perms/surface.sh` → PASS 14/14 (twin/alias parsed-equality holds over the narrowed denies)
- `bash tests/renovate/dockerfile-pins.sh` → 8 passed / 0 failed (was 6/2)
- `bash tests/coder-workspace/image-structure.sh` → 46 passed / 0 failed (was 43/3)
- `PATH=$HOME/.local/bin:$PATH python3 -m pytest charts/llama-swap/tests/ -q` → 264 passed / 2 skipped (unchanged)
- `python3 -c "import yaml; yaml.safe_load(...)"` on release.yaml → OK
- `npx aislop ci --changes` over each edit → 100/Healthy (ruff-format steps skipped — ruff not installed, pre-existing note in the tooling recipe)

Deferred by design: nothing new — carried items stay in the run-2 folder's
STATE.json `deferred` (split mode, renovate flavor-scoping rule, live bench).

## Owner fine-tunes (same-day review of this batch)

- **Routing placement reverted** (commit `c9c2b0299`): `pipeline-role-coord` step 10
  is back to its original standalone-ticket launch — correct for boardless
  `agent-coord` runs. The board-card intake override now lives in the `boards` skill
  as a new "Friction follow-up (board override)" section (card per checked item into
  Not Started via `create_card`; the rule creates the five checklists — never manual
  `add_checklist`, the #64–67 duplication lesson; dormant rule checks are toggled by
  hand; the closing session does not claim or move the new cards).
- **.kilo blanket deny restored** (commit `953bf2bf9`): `.kilo` symlinks into
  `.agents` and is slated for removal, so the five dev-family sources deny `.kilo/**`
  wholesale again — no subtree grading. Card #64's actual fix (`.agents/notes/**`
  made editable via the narrowed `.agents` subtree denies + explicit allow) stands.
- Re-validated: `rulesync generate` + `--check` clean · agent-perms 14/14 ·
  rulesync-surface 19/19.
- **Landing amended (owner, same day, commit `e6dcf7fe3`):** friction cards are created
  into **Review**, not Not Started — records awaiting the owner's call, outside the
  pickup walk, so they can never be auto-run into a duplicate of shipped work; the
  owner re-enters one to the pipeline via Rework. Cards #64–67 already sit in Review,
  consistent with the rule.
