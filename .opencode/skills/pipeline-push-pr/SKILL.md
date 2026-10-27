---
name: pipeline-push-pr
description: >-
  Single authority for pushing work to be built and tested remotely — which
  agents may push, the AGENTS.md hard rules a push obeys, what a push triggers
  in CI, PR creation and its fallback, verify-after-push, and the Deploy-stage
  hook. MUST-loaded by the `-pr` agent variants; never auto-selected.
metadata:
  opencode/autoinvoke: 'false'
disable-model-invocation: true
---
# Push work to be built and tested remotely

One authority for the push/PR operation. `-local` and plain agents never load this skill; agents that do load it follow it exactly.

## Applies to

Only the `-pr` variants: `agent-coord-pr`, `agent-board-coord-pr`, `agent-dev-pr`, and standalone `dev-pr`. A `-local` or plain-alias agent that finds this skill in its load list has drifted — it must stop and report instead of pushing.

## Push rules

Push only the run's feature/ticket branch, and only when the run's mandate is remote build/test — the `-pr` invocation is itself the standing user request for that branch push, nothing else authorizes it. Every push obeys the AGENTS.md Hard rules: never `main` and never a refspec that updates `main` (no `HEAD:main`, no fast-forward of the branch tip onto it), never force-push, never rewrite published history; never self-remediate an accidental push — stop and tell the user immediately, remediation is the user's decision. Landing via merge to `main` stays human-owned.

## What a push triggers here

A push is build+test, not deploy: `.github/workflows/aislop.yaml` runs `aislop ci --changes` on PRs (every touched file must clear the score floor with no error findings), and `docker-build.yaml` / `release.yaml` fire only on merge to main — ArgoCD syncs only after that user-owned merge.

## PR creation

Run `gh pr create` for the ticket branch when `gh` is authenticated; otherwise hand the user the compare URL (`https://github.com/ownyourio/SpencersLab/compare/main...<branch>`) and say no PR was opened. Never report or comment a PR that was not created.

## Verify after push

Confirm the push landed — `git ls-remote origin <branch>` must show the remote branch — then report the commit range and the CI expectation above in the RESULT handoff (or the board card comment). A failed push is reported, never retried with force: failure usually means the remote moved, and only the user decides the next move.

## Deploy stage hook

When a Lifecycle `Deploy` check drives the run, the push/PR of this skill is the Deploy action — the handoff still stops there. `-local` variants answer Deploy with "ready — commits local" and stop: they neither push nor claim deployment, because deploy arrives only after the user merges.
