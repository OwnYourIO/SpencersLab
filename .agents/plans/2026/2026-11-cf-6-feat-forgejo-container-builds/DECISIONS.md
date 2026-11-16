# DECISIONS — cf-6 feat forgejo-container-builds

Append-only log of decisions, rejected alternatives, conventions. Coord writes.

## 2026-11-09 — Flash+Local routes to the q4 Strata quant (owner ruling, detour)

- Ruling (in-session, 2026-11-09): subagents resolved from `Qwen Flash` +
  `Local` must run `gpu-ai/qwen3.8-flash-next-strata-q4` (UD-Q4_K_XL), not
  the IQ3_S `gpu-ai/qwen3.8-flash-next-strata`.
- Lands as: re-route of the three rule sources (`pipeline-models` combo
  bullet + favorited row, `pipeline-kickoff` derivation, `boards` kickoff
  combo clause), `rulesync generate`, AND the same-commit re-pin of
  `tests/pipeline-models/surface.sh` the `test_c05_default_route_flip...`
  guard demands. `qwen3.8-flash-next-q3` stays the documented explicit-request
  alternate; `-strata` (IQ3_S) is demoted to non-route (never agent-routable
  prose on the kickoff/boards pairs); `-strix` posture unchanged.
- The commit rode THIS ticket branch (the owner directed the detour mid-run);
  kept as its own single-purpose commit, not mixed with cf-6 chunks.
- Pre-existing reds on the base commit, NOT touched (owner eyes, separate
  work): `test_c05_hygiene_ids_registered`,
  `test_c05_no_phantom_catalog_entries`,
  `test_c05_ornith_strata_id_present_only_where_it_should_be`, and
  `pipeline-locks-tick.test.ts`'s loop-file model byte —
  `.agents/loops/pipeline-worker.md` ships
  `model: gpu-ai/qwen3.8-flash-next-strata-q4` while the test pins the
  cf-106 OQ-14 literal `gpu-ai/qwen3.8-27b-q4` (test comment: the literal
  moves only by a fresh owner ruling — loop-file-vs-test needs the owner's
  call, loop-file sync is OpenChamber-owned).
- Rejected alternative: widening the flip to the loop-file/runner literal —
  out of scope of the ruling (subagent routing only), and scheduler/model
  literals move only by an explicit owner ruling.

## 2026-11-09 — runner literal re-pinned to the Strata q4 route (owner ruling)

- The owner confirmed b438e1684 (`model: gpu-ai/qwen3.8-flash-next-strata-q4`
  in `.agents/loops/pipeline-worker.md`) AS the fresh ruling the
  `pipeline-locks-tick` test demands, so the re-pin side landed: the test's
  model byte + provenance comment, `.rulesync/rules/overview.md` (regenerated
  AGENTS.md), and the loop file's stale header comment now read
  `gpu-ai/qwen3.8-flash-next-strata-q4`. Supersedes cf-106 OQ-14
  (2026-11-03). Tick suite 15/15 green. This entry supersedes the previous
  entry's "widening" rejection — the owner ruled that widening explicitly.
- Owner-side follow-up: the loop-file body edit rotates OpenChamber's
  loopApprovals fingerprint — if the scheduled task shows
  `loopApproval: outdated`, re-approve it once (the frontmatter model byte
  itself was already landed by b438e1684).
- Still untouched (pre-existing reds on main, separate owner eyes):
  `test_c05_hygiene_ids_registered`, `test_c05_no_phantom_catalog_entries`,
  `test_c05_ornith_strata_id_present_only_where_it_should_be`.

## 2026-11-09 — planning rulings for the cf-6 request (agent-plan; EXPLORE §10 OQs decided-with-evidence)

Evidence keys: EX = EXPLORE.md §n, RS = RESEARCH.md §letter/TLDR. Card rulings
carry a best guess into the plan's Open questions for the one batched round
(no-questions rule).

- **D1 (OQ-1) Atomic replace, delete the GitHub builder.** `.github/
  workflows/docker-build.yaml` is deleted in C02, same change that activates
  the forge builder + Renovate rule. While it lives it keeps minting
  `v<ghRun>` + `:main`, and Renovate's tag-union + ordering keeps every pin
  on the GitHub line — coexistence is a correctness failure, not double
  minutes (RS-B). Rejected: narrow to `workflow_dispatch`-only (leaves a
  second builder to rot and a stale doc surface); rejected: coexist (RS-A/B
  measured ordering hazard). Alternative noted for the human round: two-PR
  staged landing (plan OQ-5).
- **D2 (OQ-2) Infra-instance guard, dev excluded.** Every job
  `startsWith(forgejo.server_url, 'https://git.spencerslab.com')` (main-sync
  house shape, EX §2/§3): dev instance is CrashLoopBackOff AND would fire on
  an unset Actions secret; forge-side PRs get the `pull_request` trigger
  regardless of today's GitHub-PR-only landing flow.
- **D3 (OQ-3) CalVer `yy.mm.N`, registry-derived + existence-advance.**
  `N = max(yy.mm.* in ghcr tags/list)+1` (card-literal density, on-spec
  CalVer YY.MM.MICRO), then advance while the manifest HEAD exists — GHCR has
  no tag immutability, re-push silently overwrites (RS-D); re-run semantics
  documented in the workflow comment. Rejected: `yy.mm.<forgejo.run_number>`
  (repo-wide counter, not "N of month" — EX §6 option 1); rejected:
  `git rev-list` monthly count (a commit index, not a per-image release
  index); rejected: timestamp fallback (off-spec, RS-D). Renovate migration:
  one packageRule, `matchDatasources: ["docker"]`,
  `versioning: regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$` scoped to
  `ghcr.io/ownyourio/*`, landing before-or-with any pin bump — on a `v162`
  pin it is a clean silent skip, never a downgrade PR (RS-A EMPIRICAL);
  in-repo precedent: the llama-swap regex-versioning rule.
- **D4 (OQ-4) push `:main` AND `:latest` on main builds.** `:main`+Always is
  a live consumer contract (coder-workspace main.tf, strata, vllm-rocm pin
  it); rolling tags never compete as Renovate pins (RS-A), so running both
  costs nothing. Rejected for now: retire `:main` — consumer migration is its
  own change (follow-up candidate).
- **D5 (OQ-5) PR builds push, `pr-<branch>-<sha>` only.** Card-literal
  ("tag with the branch name, and additionally have a build hash"); the
  `pr-` prefix + lowercase/`/`→`-`/charclass/≤128 sanitizer makes shadowing a
  rolling or calendar tag impossible. GHCR has no retention → stance: PR tags
  are disposable, API-prune is a follow-up card. Deviates from the GitHub
  precedent's PR-never-push rule deliberately (its clobber rationale is
  neutralized by the naming).
- **D6 (OQ-6) Publish IS the deploy.** Merge→forge build→ghcr→Renovate
  pin-bump→ArgoCD sync is the existing consume loop; no ArgoCD-side step is
  added (EX §8).
- **D7 (OQ-7) `workflow_dispatch` kept (free-text `containers` input); `dev`
  leg dropped.** No `dev` branch exists on any remote (EX §1).
- **D8 (OQ-3 cache leg/OQ-8) Plain `docker build` + `docker push`; cache =
  the persistent 10 Gi dind docker-data VCT; no buildx cache backend.**
  `type=gha` fails the lab dind shape (classic store, env/scope gates, RS-C)
  and the VCT layer store is already a cross-job cache; workflows must pass
  cold anyway (practitioner principle, RS-C). No `docker/*` actions
  (data.forgejo.org mirror inventory unproven — RS-C policy "no dependency
  on the mirror"); only `actions/checkout@v6` (live-proven, EX §3). Auth =
  Actions secret `GHCR_PUSH_PAT` (human-minted PAT, Bitwarden-backed item,
  entered on the infra instance; the ExternalSecret hard rule binds K8s
  objects, not instance-DB secrets, EX §5). `concurrency:
  {cancel-in-progress: false}` mandatory (RS TL;DR-2); matrix `fail-fast:
  false` + unique per-cell job name; capacity-1 serialization documented.
## 2026-11-09 — owner batched-round answers (SUPERSEDES D1; glosses D5; D2/D3/D4/D6/D7/D8 stand)

- **OQ-1 → D1 SUPERSEDED: narrow, do not delete.**
  `.github/workflows/docker-build.yaml` is kept but reduced to
  `workflow_dispatch`-only — its `push` and `pull_request` triggers are
  stripped in C02, leaving it as the GitHub-side manual rebuild escape
  hatch. The Renovate-hazard answer shifts accordingly: the GitHub builder
  can no longer mint tags automatically, so the calendar line is
  authoritative from activation (D1's delete was one way to the same
  convergence; the owner chose the one that keeps a manual fallback
  builder). The docs re-pin MUST state the fallback's manual-only status.
- **OQ-3 CONFIRMED** — registry-derived `max(yy.mm.*)+1` + existence-
  advance; **D3 stands unchanged** (packageRule, rule-before-bump).
- **OQ-4 CONFIRMED** — main builds push `:main` AND `:latest`; **D4
  stands** unchanged.
- **OQ-5 CONFIRMED with owner gloss; D5 stands.** PR builds run on the
  FORGE — PRs live on the forge, not GitHub — so the GitHub PR trigger's
  departure (OQ-1 narrowing) is by design, and `pr-<branch>-<sha>` tags
  push to ghcr exactly as D5 spells.
- **OQ-7 RESOLVED (same gloss):** the forge is the PR venue — the
  `pull_request` leg on the forge workflow is real, not ceremonial.
- **Landing cadence CONFIRMED:** one atomic change on this branch (C01 +
  C02), with the owner running the pre-merge `workflow_dispatch` smoke on
  the pushed branch before merge.
- **Follow-up cards:** ONLY (a) — the one-time pin-bump PR (v84/v162 →
  first calendar tag after the first forge build) — is created as an
  Inbox card by the coordinator. (b) PR-tag GC, (c) runner records /
  timeout raise, (d) dev-instance inclusion, (e) `:main` retirement stay
  deferred WITHOUT cards.
- Folder mechanics: plan of record `2026-11-09-feat-forgejo-container-builds.md`;
  two chunks (C01 workflow subsystem M w1; C02 atomic cutover S w2 ← C01);
  validation doctrine = offline contract suite + detector unit tests +
  dev-renovate MCP checks, `docker build => no-daemon, CI-deferred` as the
  passing CI-deferred line (cf-77), actionlint/hadolint NOT installed never
  pinned. Deferred to follow-up-card candidates (RESULT open_questions, no
  cards created by this run): one-time pin bump, PR-tag GC, runner
  records/timeout raise, dev-instance inclusion, `:main` retirement.

## 2026-11-10 — C02 launch rulings by coord (scope, and what the reviewer must judge)

- **Folded-in C01 hardening is authorized inside C02.** `chunks/C02.md` says "Do not touch: `.forgejo/workflows/*` (C01)", and the C01 round-2 review recorded one accepted non-blocking minor — "token-200-but-empty extraction → folded into C02 round". Those two lines collide, so the coordinator ruled before the launch: the ONLY permitted edit in `.forgejo/workflows/containers-build.yaml` is the fail-loud guard on a 200-with-empty-body registry token; `curl -f` stays out (t11's shapes are the regression teeth for exactly that), and every C01 leg must remain green. Everything else in that file is still off-limits to this chunk. Review should judge the edit against that ruling, not as a silent scope violation.
- **Renovate MCP route is inline, not path-aware** (FRICTION 2026-11-10): `validate_config`/`test_package_rules` ran against the whole `renovate.json` passed as `configContent` because the dev-cluster server cannot see the worktree. A pass from that route is a real validator/matcher pass on the real config text — it is not a path-resolution proof. Report NOT-RUN rather than a pass if a later leg needs path resolution.
- **x1 is `on:`-scoped by design** (plan Commands, coord-fixed per test-session OQ-2): the `docker/build-push-action` `push:` INPUT key stays in the file; any review suggestion to rename or remove it is out of scope, and a raw `^push:` grep result is a false positive, not a failure.

## Deferred (out-of-scope findings, not forwarded to dev)

- 2026-11-10 · dev(C02) open_questions · surfaces outside C02's file list still naming `.github/workflows/docker-build.yaml` as (near-)live: `.rulesync/skills/pipeline-push-pr/SKILL.md` (~L24, ~L41), `.rulesync/skills/role-planner/SKILL.md` and `.rulesync/skills/role-code/SKILL.md`, `containers/{wekan-mcp,vllm-rocm,strata}/README.md`, `tests/cf96-deploy/readback-runbook.md`, `skills/helm-chart-creation/references/mcp-servers.md:401`. None is x3-gated and every one is outside the chunk's Modify list, so they were deliberately left; a docs-parity sweep (rulesync sources + regenerate, container READMEs, runbook) is the right shape for its own card.

## 2026-11-10 — final whole-plan review APPROVED; owner handoff record

- **Verdict**: `APPROVED`, fresh session `ses_e39bbfbc7ffenRO63brkI8DXlk` on the planning tier, every validation re-run (FULL suite 23/23, x1, `rulesync generate --check`, the dev-renovate trio, aislop 0 findings, all 5 embedded run blocks `bash -n`), nothing NOT-RUN. Recorded in `STATE.json` `final_review`. `plan_status` is now `complete`.
- **Owner handoff — pre-merge smoke side effect (the reviewer's minor 1, landed here because the coord's edit grant does not include the plan file)**: the pre-merge `workflow_dispatch` smoke **shares the main push arm**, so it repoints live `:latest`/`:main` on `ghcr.io/ownyourio/<image>` and mints a real `yy.mm.1` calendar tag. Harmless by construction (the branch's `containers/**` is byte-identical to main at smoke time) and that first tag is exactly the precondition Inbox card AD-134 waits on. `GHCR_PUSH_PAT` must already be entered on the infra instance before the smoke and before the merge — both the PR and push legs need it.
- **Deferred additions from the final review** (beyond the docs-parity list above, which gains test teeth): the sweep must move docs **and** their pins in one change — `tests/pipeline-push-pr/surface.sh` P7 and `tests/wekan-mcp/tools.sh` t5 currently pin the GitHub-builder / `:v<run>`+`:branch` prose; and the `v84`/`v162` `image:` lines sit in `services/{dev,gpu}/prod/values.yaml`, which no current `renovate.json` manager extracts (the plain-image regex manager covers `*/templates/` only), so card 134 needs a `managerFilePatterns` extension or a repeated manual bump.
- **Not taken**: `.forgejo/workflows/containers-build.yaml:128` keeps interpolating `forgejo.head_ref` into a single-quoted shell literal (reviewer minor 2) — contained by the file's same-repo-PR-only posture, and churning it would collide with the t8 pin; `env:`-passing stays the noted one-line alternative for a future card.
