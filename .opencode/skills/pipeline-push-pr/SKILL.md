---
name: pipeline-push-pr
description: >-
  Single authority for pushing work to be built and tested remotely — which
  agents may push, the AGENTS.md hard rules a push obeys, what a push triggers
  in CI, PR creation and its fallback, the assumed draft/ready PR testing tiers,
  verify-after-push, and the Deployment-stage hook. MUST-loaded by the `-pr`
  agent variants; never auto-selected.
metadata:
  opencode/autoinvoke: 'false'
disable-model-invocation: true
---
# Push work to be built and tested remotely

One authority for the push/PR operation. `-local` and plain agents never load this skill; agents that do load it follow it exactly.

## Applies to

Only the `-pr` variants: `agent-coord-pr`, `agent-board-coord-pr`, `agent-dev-pr`, standalone `dev-pr`, and standalone `code-pr` — the `code` family's push twin, governed here because it is the only standalone agent allowed to push (cf-106 OQ-10). A `-local` or plain-alias agent that finds this skill in its load list has drifted — it must stop and report instead of pushing.

## Push rules

Push only the run's feature/ticket branch, and only when the run's mandate is remote build/test — the `-pr` invocation is itself the standing user request for that branch push, nothing else authorizes it. Every push obeys the AGENTS.md Hard rules: never `main` and never a refspec that updates `main` (no `HEAD:main`, no fast-forward of the branch tip onto it), never force-push, never rewrite published history; never self-remediate an accidental push — stop and tell the user immediately, remediation is the user's decision. Landing via merge to `main` stays human-owned.

## What a push triggers here

A push is build+test, not deploy: `.github/workflows/aislop.yaml` runs `aislop ci --changes` on PRs (every touched file must clear the score floor with no error findings), and `docker-build.yaml` / `release.yaml` fire only on merge to main — ArgoCD syncs only after that user-owned merge.

## PR creation

Run `gh pr create` for the ticket branch when `gh` is authenticated; otherwise hand the user the compare URL (`https://github.com/ownyourio/SpencersLab/compare/main...<branch>`) and say no PR was opened. Never report or comment a PR that was not created.

## -pr testing flow (assumed)

What the `-pr` family may count on once it pushes a ticket branch: linting runs automatically (a future plugin runs it for the `-pr` family — ledger card L3), CI performs the builds and the tests, and the PR's lifecycle state selects the tier.

- **Draft PR — the unit tier.** GitHub runs `pull_request`-triggered workflows while a PR is draft — the ready tier's `draft == false` guard below exists precisely because they do — so the unit tier rides plain `on: pull_request`: its default types (opened, synchronize, reopened) fire during the draft.
- **Ready PR — the integration tier.** A second workflow keyed `on: pull_request: types: [ready_for_review, synchronize]` with the draft guard `if: github.event.pull_request.draft == false` — `synchronize` keeps it re-running on new commits after the PR leaves draft. Skipped checks can report a stale pass on a draft-to-ready transition, so the required-check list stays aligned with the ready-stage workflow (guidance for the CI cards, not for an agent run).

Coverage shapes per surface:

- **k8s charts — unit:** load the impacted chart(s) into the test environment, then a playwright login/verify/logout walk over every accessible ingress or gateway object lacking the `skip-testing` annotation (settable in Chart.yaml). **Integration:** the same walk plus a restore of the most recent production kopia backup into the test environment, with data presence confirmed after login. Ledger cards: L7 (test-environment loading and the exact skip-testing key), L8 (the playwright mechanics), L9 (the kopia mechanics), L10 (the charts PR flow).
- **services:** the same tier flow performed at the `services/` location — ledger card L11.
- **containers:** builds ride the existing `docker-build.yaml` PR validation — merge = publish stays the split; each container's `testing/` folder ships a values.yaml carrying an app-template that defines how to run the container, and the tests execute against it — ledger card L12.
- **Test credentials:** one shared dev/test username and password arrive as agent env vars (`$LAB_TEST_USER` / `$LAB_TEST_PASSWORD`), consumed by the agent and the tests alike; how they reach the agent env (k8s Secret plus `coder_env` in the Coder template) is part of L10.
- **When tests do not exist yet:** prefer live playwright-MCP actions if the app is reachable; otherwise write the tests from prior research and update them once the app runs.

Mechanics ship under those follow-up ledger cards (L7-L12); this section is the contract with them assumed in place — no agent run implements, probes, or re-derives any of it.

## Verify after push

Confirm the push landed — `git ls-remote origin <branch>` must show the remote branch — then report the commit range and the CI expectation above in the RESULT handoff (or the board card comment). A failed push is reported, never retried with force: failure usually means the remote moved, and only the user decides the next move.

## Deployment stage hook

When a Lifecycle `Deployment` check drives the run, the push/PR of this skill is the Deployment action — the handoff still stops there. `-local` variants answer Deployment with "ready — commits local" and stop: they neither push nor claim deployment, because deploy arrives only after the user merges.
