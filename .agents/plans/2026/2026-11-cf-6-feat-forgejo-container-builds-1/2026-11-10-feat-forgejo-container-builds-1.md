# PLAN: Build and deploy containers — run -1 rework (ROLE split, dual registry, commented fallback)
feature: 2026/2026-11-cf-6-feat-forgejo-container-builds-1

> **FINALIZED 2026-11-11** against the owner's batched-round answers (DECISIONS.md "owner batched-round answers"): OQ-3 dropped the probe (C01 retired), OQ-6 supersedes RD9 — the forge registry **mirrors the rolling tags**, OQ-1/OQ-7 confirmed with a binding sequencing rule (infra ROLE stays `prod` until C04 merges). All Open questions are ANSWERED; see that section.

## Goal

Rework the shipped cf-6 container pipeline to the owner's review ruling (card 6 comment `cNNkCZkBHHm2ESf87`): the Forgejo builder splits by **ROLE list membership, never by instance URL** — push-to-main/dispatch ∧ ROLE∋`prod` publishes `yy.mm.N` + `:latest` + `:main` to **ghcr AND the instance's own Forgejo registry** (OQ-6 mirror ruling), pull_request ∧ ROLE∋`dev` publishes `pr-<branch>-<sha>` to the **local registry only**, and an **unset ROLE defaults to `dev,prod`** (unset must widen, never disable). The same guard convention lands repo-wide over `.forgejo/workflows/*`, and `.github/workflows/docker-build.yaml` keeps its old `push:`/`pull_request:` trigger blocks **in the file, commented out**, so re-enabling is an uncomment, not a re-author.

Run 0's shipped pair (detector, contract suite at 23 legs — re-verified **23 ok post-merge at `9f53c2b73`**, Renovate calendar rule, workflow skeleton) is the base; this plan changes guards, triggers-to-roles, tag destinations, and their pins — not the detection or tag-derivation machinery (`detect`/`next-n`/`sanitize` carry over).

## Out of scope

- **Dev-instance live validation is NOT promised.** The dev instance is healthy but has executed **zero workflow tasks ever** (EXPLORE §6); its runner-pickup triage stays owner-owned. This run *authors and offline-pins* the `ROLE∋dev` PR leg; whether it ever fires on the dev box is gated on the owner's triage + the hard H2 precondition (`ROLE=dev` before that runner picks up anything). Infra runs the PR leg live only after the **post-C04** `ROLE=dev,prod` flip (H1) — during this run infra stays `prod`.
- The wide docs-parity card stays deferred: `tests/pipeline-push-pr/surface.sh` P7 and `tests/wekan-mcp/tools.sh` t5 pin old GitHub-builder/`:v<run>` prose in files this run does not edit (run-0 DECISIONS); they stay green and drift together until that card.
- No Renovate widening to the forge registry, no chart pin changes, no cluster pull-secret work, no consumer migration to forge-registry images (AD-134 stays the pinned ghcr bump path). The docs may now *offer* the forge registry as a 1:1 pull source (OQ-6), but no pin or Renovate rule moves to it this run. Publishing remains the deploy (run-0 D6); no ArgoCD-side step.
- `:main` retirement, PR-tag GC *automation* (beyond the owner-UI Cleanup Rule leg H8), role words beyond the `{dev, prod}` vocabulary, instance-global Actions variables, and the run-0 `head_ref`/PAT-interpolation nits (accepted posture — do not churn).
- Landing on `main` (PR is user-owned); pushing this branch (commit-only run; pushes only on the owner's explicit word).

## Global constraints

- Guard engine facts (RESEARCH R1, source-proven on the deployed 15.0.10 + runner v13.2.0): job-`if:` is evaluated by the runner with the full expression engine; unset `vars.X` ⇒ null, `null == ''` true, `contains` case-insensitive substring that **never errors**; `fromJSON` **errors on unset/empty/non-JSON** and an expression **error fails the job** (a false guard only skips it); `on:` itself cannot be conditioned — the ROLE/event split lives only in job `if:`. Avoid `case()` (runner-only function, version-skew trap).
- **ROLE input contract (owner-confirmed, OQ-2):** a comma list without spaces — `dev,prod` — evaluated by substring `contains`. The guard is forever the cannot-error spelling `vars.ROLE == null || contains(vars.ROLE, '<role>')`; `fromJSON` never evaluates an instance-set value.
- Job-token/deploy-token registry pushes are source-closed (R2: `// TODO: ActionUser permission check`, zero deploy-token wiring) — the forge push rides a human-minted **non-admin `write:package` PAT** (`secrets.FORGE_PUSH_TOKEN` per instance, Bitwarden `forgejo-registry-token-{infra,dev}`, OQ-5/OQ-9).
- `concurrency.cancel-in-progress: false`, matrix `fail-fast: false`, `uses:` ⊆ `actions/checkout@v6`, plain `docker build`/`docker push`, `set -euo pipefail` everywhere — run-0 invariants stand.
- Repo git rules unchanged (branch commits only, never main, PR is user-owned). One claim, one card; co-tenancy with card 55 is sanctioned on `Pipeline: CICD`, landing order ruled (OQ-11): **cf-6 run -1 lands first, card 55 rebases onto it**.

## Commands

Offline validation doctrine (agent sessions; run from anywhere in the worktree):

- test (full): `bash tests/services/forgejo-containers-build.sh` — **23 legs at the post-merge baseline** (t1–t11, d1–d8, x1–x4; verified 23 ok at `9f53c2b73`); run -1 re-authors t3/t5/t7/t8/t9/t11/x1 and adds `r1–r5` + `g1` → **29** at full green. The leg-id parser gains the `r`/`g` groups and ids in the same commit that adds the legs.
- test (red posture + gating): once `agent-test` has written all chunks' legs red-first, expect t3/t5/t7/t8/t9/t11 + r1–r5 red until C02 lands and x1 red until C03 lands (run-0 precedent: the FULL suite is green only after the last chunk). Gate chunks on scoped subsets: C02 → `bash tests/services/forgejo-containers-build.sh t d r` (24 ok when C02 is done); C03 → `… x1`; C04/final → full (29 ok).
- test (subsets): groups `t` / `d` / `x` / `r` / `g` or per-leg, e.g. `bash tests/services/forgejo-containers-build.sh t3 r2 x1`.
- detector: `bash -n scripts/forgejo-container-detect.sh` (detector logic unchanged; comment reword only).
- YAML parse, every touched workflow: `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' <file>` (containers-build, docker-build, main-sync).
- embedded-run hygiene: `bash -n` sweep of every `run:` block extracted via pyyaml (run-0 doctrine; all blocks clean).
- neighbor regression: `bash tests/services/forgejo-main-sync.sh` (C04 moves its t3 byte — re-run mandatory), `bash tests/pipeline-push-pr/surface.sh`, `bash tests/wekan-mcp/tools.sh` (untouched, must stay green).
- docs (C04): `rulesync generate && rulesync generate --check` (NEVER `rulesync gitignore`); x3-shape greps — `containers-build` named in `skills/container-creation/SKILL.md`, `.rulesync/rules/overview.md`, regenerated `AGENTS.md`; every `docker-build.yaml` line co-names `workflow_dispatch`.
- Renovate (regression only; `renovate.json` unchanged): dev-renovate MCP `check_setup` + `validate_config` + `test_package_rules` ×3 via the **inline `configContent` route** (DECISIONS-pinned — the dev-cluster server has no worktree visibility; a pass there is a validator pass on the real text, not a path-resolution proof; report NOT-RUN rather than a pass for anything needing path resolution).
- quality gate: `npx aislop ci --changes` (AGENTS.md rule; expect 0 errors).
- `docker build => no-daemon, CI-deferred` — the passing AC shape (no daemon in agent sessions; the live Forgejo run is the authoritative build test).
- helm lint/template: N/A (no chart is touched).

Owner legs, never agent ACs: live smoke (H7), `kubectl exec` egress checks and the `app.ini` `[packages]/[quota]/[service]` read (H6), and all variable/PAT/Cleanup-Rule settings (H1–H3, H8). (H4/H5 retired — namespace decided, probe cancelled by ruling.)

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | ~~ROLE guard-semantics probe~~ **DROPPED by owner ruling (OQ-3: "No probe, implement", 2026-11-11)** — tombstone kept at `chunks/C01.md`; id retired, never re-used or re-numbered (trail cites it; coord removed the `STATE.json` entry) | — | — | — | — |
| C02 | containers-build ROLE split + dual-registry mirror (`yy.mm.N`/`:latest`/`:main` both registries; PR `pr-*` forge-only) + union-max derivation + suite re-author | L | 1 | [] | was [C01] — the probe is dropped, so the owner-confirmed cannot-error guard spelling lands directly; no verdict dependency |
| C03 | GitHub fallback: commented-out `push:`/`pull_request:` blocks + note-1 x1 re-author | S | 1 | [] | independent of C02 (different file, disjoint legs); wave 1, run in id order after C02 |
| C04 | Repo-wide ROLE-convention sweep (main-sync membership migration + g1 no-URL leg) + docs parity + rulesync regen | M | 2 | [C02, C03] | docs/g-legs describe the final byte-shape of both workflow files; g1 scans `.forgejo/workflows/*` as it stands after C02; x3 gates docs against C03's file state too |

Wave order:
1. **C02**, then **C03** (independent — C02 touches `.forgejo/` + t/r legs, C03 touches `.github/` + x1; id order).
2. **C04** (sweep + docs after the bytes are final). Owner legs H2/H3 ideally land before the first live run; **H1 (infra `dev,prod`) may NOT land until C04 has merged** (sequencing rule, OQ-1/OQ-7).

## Tests (suite at 23 legs → 29)

Re-authored, not added-to (RESEARCH R1 §5 / EXPLORE §7.1 — the guard/trigger change moves these): **t3** (URL guard ⇄ zero URL literals + ROLE membership posture), **t5** (single build job ⇄ detect + `build-release` + `build-pr`), **t7** (one PAT ⇄ two PATs, each exactly once under its own login step), **t8** (one `case`-split ⇄ per-job tag arms incl. PR-never-ghcr, both registries carrying the full three-tag release set), **t9** (diag `server_url` ⇄ diag `ROLE`), **t11** (ghcr-only reads ⇄ per-registry tolerance + walk-under-200 per side), **x1** (absence-of-triggers ⇄ positive assertion that the commented `push:`/`pull_request:` text is present *and* inert, still `on:`-scoped so the `push:` INPUT key at `docker-build.yaml:139` stays a blessed false positive — EXPLORE §7.2 replayed both shapes).
Unchanged: t1, t2 (`on:` events/paths don't change — `on:` can't be role-conditioned, R1 §4), t4, t6, t10, d1–d8, x2, x4; x3 logic unchanged (its content re-pins ride C04).
New legs: **r1** exact guard/event-gate bytes + job-id set (cannot-error spellings only); **r2** derivation reads both `tags/list` before any push + per-registry walk-before-push (R2 invariants 1–2); **r3** ghcr-arm-before-forge-arm + `|| true` banned on login/push/derivation lines (R2 invariants 3–4); **r4** PR-tag total length bound + lowercase forge path segment; **r5** `forgejo.server_url` blessed as derived host via `env:` only — count 0 inside any `if:` and 0 URL literals; **g1** repo-wide sweep: every `.forgejo/workflows/*.yaml` has 0 URL literals, 0 `startsWith(forgejo.server_url`, no `forgejo.server_url` inside any `if:`, every ROLE-referencing guard uses `vars.ROLE`, and the string-equality form `vars.ROLE == '` occurs nowhere (membership-only, post-migration).
R2's five test-pinnable invariants, re-checked against the OQ-6 rolling mirror: (1) both-lists-before-push → r2 — unchanged (rolling tags never gate on reads); (2) walk-before-push protects the **calendar line only** — `:latest`/`:main` are mutable-by-contract on both registries, no leg may demand a walk before a rolling push → r2/t11 scoped to `$month.$n`; (3) forge login with `FORGE_PUSH_TOKEN` exactly once per login job → t7; (4) no `|| true` swallowing on any push arm, including the second (forge) multi-tag loop → r3; (5) per-side tolerated absence codes (ghcr token 403 / forge 404 `NAME_UNKNOWN` ⇒ contribute nothing; walk only where that side's list answered 200; anything else fatal) → t11.

## Human legs (owner, enumerated — not implemented by any chunk)

- **H1 — infra ROLE `dev,prod`: POST-C04 OWNER LEG, NOT a precondition (OQ-1/OQ-7 sequencing rule).** Infra's repo variable stays `prod` for the whole run; flipping it to `dev,prod` **before C04 has merged** silently stops main-sync's `== 'prod'` fan-out (the exact-matching guard rejects a list). After C04 merges (membership guard live on `main`), the owner flips it; only then does the PR arm run live on infra.
- **H2 — dev ROLE (HARD PRECONDITION):** set `ROLE=dev` explicitly on the dev repo **before its runner ever picks up a task** — with unset=`dev,prod` an unset ROLE on dev makes it a second calendar writer for both registries. (Today's zero-task state is the only thing masking this.)
- **H3 — PATs (confirmed shape, OQ-5/OQ-9):** mint a non-admin `write:package` PAT per instance from an account with write on the `CuratedForest` org, Bitwarden items `forgejo-registry-token-{infra,dev}`, entered as repo Actions secret `FORGE_PUSH_TOKEN` on each instance. The run-0 `GHCR_PUSH_PAT` leg is unchanged and still outstanding — both push arms need it.
- **H4 — namespace: RETIRED as a leg (decided, OQ-4/OQ-10)** — `curatedforest/<image>` on the existing, publicly visible org; no new account. The org stays public (anonymous pull); the workflow reads with the PAT regardless. The org-write-membership requirement lives inside H3.
- **H5 — RETIRED (OQ-3 "No probe, implement"):** the probe workflow and its one-dispatch run are cancelled; a real PR or the pre-merge smoke is the guard engine's first live observation.
- **H6 — reads:** optional `kubectl exec` egress probes (R2 §5 commands) and one `app.ini` `[packages]/[quota]/[service]` read (readonly tiers can't see secrets).
- **H7 — live smoke (post-H3) — two-registry caveat:** one infra `workflow_dispatch` with `containers=<one>` shares the release arm, so it **repoints live `:latest`/`:main` on BOTH registries (ghcr and the infra forge) and mints the first real `yy.mm.N` calendar tag in both**; then one internal PR ⇒ `pr-*` appears in the infra registry only (and, after H1, PR builds publish there). First pushes settle the hairpin-ingress/MTU unknowns.
- **H8 — retention (tightened by the OQ-6 mirror):** forge-side owner-UI Cleanup Rule per instance with **RemovePattern strictly `pr-.*`** (+ RemoveDays ≈14). `latest` is code-protected from rules, but **`:main` and the calendar line are NOT** — they survive only because the pattern stays narrow; never widen it to `.*`-like forms. GHCR `pr-*` stays unpruned (no platform feature).

## Open questions — ALL ANSWERED by the owner batched round (2026-11-11)

Authoritative record: DECISIONS.md "2026-11-11 — owner batched-round answers". No open question remains; the residuals are owner legs (H1–H3/H6–H8, sequencing), not uncertainty. **No new question was opened by any answer** — the one genuinely new decision the mirror raised (cleanup keep-patterns for `:main`/calendar) was answered inside the OQ-6 ruling itself and landed in H8/RD12-tightened; nothing else needs the owner before launch.

1. **OQ-1 Guard polarity — ANSWERED:** one guard *shape* (membership), per-file unset-default (containers widen; main-sync migrates to bare `contains(vars.ROLE, 'prod')` and stays fail-safe). Impact: C04 carries the real main-sync byte migration + its suite re-pin; cf-119's fail-safe survives.
2. **OQ-2 List syntax — ANSWERED:** `dev,prod` (comma, no spaces) + substring `contains`; documented input contract. Impact: C02 guard bytes stand; `fromJSON` banned for hand-typed values.
3. **OQ-3 Probe — ANSWERED (owner chose NO):** C01 dropped; guards implemented directly in the cannot-error spelling. Impact: waves renumbered, C02 deps cleared, false-branch `skipped` stays unobserved until the first live run (see Risks).
4. **OQ-4 Namespace — ANSWERED:** `curatedforest/<image>`, org exists + public. Impact: refs pinned lowercase; H4 retired.
5. **OQ-5 Reading A vs B — ANSWERED (A):** each instance pushes its own registry + ghcr. Impact: per-instance `FORGE_PUSH_TOKEN`, single-writer-per-registry derivation stands.
6. **OQ-6 Forge tag set — ANSWERED (owner chose MIRROR, supersedes RD9):** both registries carry `yy.mm.N` + `:latest` + `:main`; PRs push `pr-*` to the forge only. Impact: C02 publish arms/legs, H7 two-registry caveat, H8 keep-patterns, docs offer forge as a 1:1 pull source.
7. **OQ-7 infra ROLE value — ANSWERED with a sequencing rule:** stays `prod` now; `dev,prod` only after C04 merges (H1 rewritten). Impact: no live PR arm on infra inside this run; the flip is post-merge and safe only post-C04.
8. **OQ-8 Registry host carrier — ANSWERED:** derive from `forgejo.server_url` inside steps via `env:`; blessed as derivation, banned as guard predicate; `vars.REGISTRY_HOST` rejected. Impact: `r5`/`g1` pin the posture; zero new per-instance variables.
9. **OQ-9 PAT ownership — ANSWERED:** two human-minted non-admin `write:package` PATs, Bitwarden `forgejo-registry-token-{infra,dev}` → repo secret `FORGE_PUSH_TOKEN`. Impact: H3 finalized; site-admin bypass stays out of the grant path.
10. **OQ-10 Org visibility — ANSWERED:** `CuratedForest` stays public; workflow reads use the PAT regardless. Impact: a visibility flip cannot degrade derivation; pull secrets stay out of scope.
11. **OQ-11 Landing order — RULED:** cf-6 run -1 lands first; card 55 rebases onto it. Impact: C03 owns `docker-build.yaml` trigger text; the guard convention lands on this branch first.

## Risks / assumptions

- **Co-tenant collision (card 55, same `CICD` pipeline, sanctioned shared claim):** concurrent `.forgejo/workflows/*` + `overview.md`/`AGENTS.md` edits on different branches; C03/C04 own overlapping prose with cf-55's GitHub-builder move. **Ruled (OQ-11): this run lands first and card 55 rebases onto it.** Mitigation: one change per commit, never merge/push main ourselves.
- **Guard engine unexercised on this instance (no probe, OQ-3):** the false-branch `skipped` of a `vars`-based job guard remains **unobserved here**, and `contains`/`fromJSON` at job level are source- and docs-backed but **never executed** on either lab instance. The first live observation is a real PR or the owner's pre-merge smoke (H7). Therefore: the guard stays the cannot-error spelling (`== null || contains`, never `fromJSON` on `vars.*`, no `case()`) **forever in this run**; an expression *error* fails jobs while a false guard only skips; the gate-job form stays a documented, unexercised alternative — do not implement it.
- **ROLE value sequencing (OQ-1/OQ-7, binding):** infra `ROLE` stays `prod` until C04 has merged — an early flip to `dev,prod` silently stops main-sync's `== 'prod'` fan-out (main stops reaching GitHub/dev). H1 is a post-merge owner leg; the final-review handoff must carry the warning (C04 ACs pin the clause).
- **Unset=widest on dev is a hazard, not a convenience:** H2 is a precondition, not a nicety.
- **First forge pushes are unverified end-to-end:** hairpin through the Traefik ingress, k3s MTU on big layers, `tags/list` body byte-compat with `next-n` — all settle only at H7; fallbacks (in-cluster service needs `insecure-registries` config that doesn't exist; `network: host`) are owner-side.
- **Substring semantics are vocabulary-bound:** `{dev, prod}` has no substring collisions (`prod`⊄`dev`); a future role word like `production` would silently widen `prod` guards — pinned in docs + legs. A whitespace-only ROLE value is neither unset nor empty to the engine (documented edge; keep UI values tidy).
- **Two-registry N is union-max with per-side walk (P3):** failures leave *gaps* (one side lags), never clobbers. Both registries now carry the rolling tags, so the ghcr-then-forge arm order leaves a half-failed lag on the forge side — the newer line the fleet's pins have not adopted (ghcr stays authoritative for Renovate until any later migration). The guarantee is "every successful build published the same N everywhere it pushed" — say exactly that in docs.
- **Dispatch from a non-main branch shares the release arm** (run-0 carried caveat): the pre-merge smoke (H7) and any future dispatch republish real tags — now `:latest`/`:main` repointed and a calendar tag minted on **two** registries.
- **Post-merge inventory moved:** `containers/vllm-rocm` deleted upstream, `containers/vllm-radiance-mxfp4` added (13 dirs now — re-verified on this branch). Run-0 docs/risk text naming vllm-rocm are stale; C04 text must speak the current inventory and not resurrect the old one.
- **ROLE-era fan-out is young and flaky:** main-sync's ROLE-era record is 6 green / 9 runs with a failing push job — context for any "prod fan-out just works" assumption; containers pushes are docker push, a different path, equally first-time here.
- Fork PRs get empty secrets ⇒ a PR job there fails red rather than skips (lab flow is internal PRs only; documented).

## Chunk index

- `chunks/C01.md` — **[DROPPED]** tombstone (owner OQ-3: no probe; id retired)
- `chunks/C02.md` — the ROLE split + dual-registry mirror (calendar+latest+main on both; PR forge-only) + union-max derivation + t/r-leg re-author
- `chunks/C03.md` — GitHub fallback commented triggers + x1 re-author
- `chunks/C04.md` — repo-wide sweep (main-sync membership migration + g1) + docs parity + rulesync regen (carries the merge-before-flip clause)
