# DECISIONS — cf-6 run -1 feat forgejo-container-builds-1 (rework)

Append-only log of decisions, rejected alternatives, conventions. Coord/plan write.
Predecessor: `…/2026-11-cf-6-feat-forgejo-container-builds/DECISIONS.md` (run 0 D1–D8,
owner round, coord rulings, Deferred list) — read it; nothing here re-decides it except
where the owner's rework comment `cNNkCZkBHHm2ESf87` overrules it.

## 2026-11-11 — surface deviation: run -1 reuses run 0's worktree AND branch

- Ruled by the coordinator's launch (recorded here per the launch's explicit ask): run
  -1 runs in worktree/branch `cf-6-feat-forgejo-container-builds` (run 0's surfaces),
  not a fresh `…-1` branch, because run 0's C01/C02 exist only as 9 local commits on
  that branch (never pushed) and the rework edits *that* code. The branch carries
  `main` merged at `7bb44ae5f` (post-merge ground: `main-sync.yaml` v2 ROLE-era, the
  50 upstream commits, `containers/vllm-rocm` deleted, `containers/vllm-radiance-mxfp4`
  added). Only the plan folder and slug carry the `-1` suffix.
- The plan of record keeps the coordinator-named file `2026-11-10-feat-forgejo-container-builds-1.md`
  (run launched on the 2026-11-10 workspace clock; the naming follows one-plan-per-work).

## 2026-11-11 — run -1 planning rulings (agent-plan; no-questions rule — every guess is also an Open question in the plan file)

Evidence keys: X = run -1 EXPLORE.md, R1/R2 = run -1 RESEARCH.md, D* = run 0 DECISIONS.

- **RD1 (NOTE 1) GitHub fallback: comment, don't delete.** `.github/workflows/docker-build.yaml`
  regains its original `on.push:`/`on.pull_request:` blocks **inside `on:`, fully
  commented** (parent AND children — a commented parent with live children breaks
  `yaml.safe_load`, X fact 8), annotated "re-enabling races the calendar line" (X OQ-7
  guess: a re-enabled GitHub builder mints `v<run>` + `<branch>` and re-opens run 0's
  Renovate-ordering hazard D1). x1 re-authors to assert the commented text is present
  **and** inert, keeping its `on:`-scoped grep so the `push:` INPUT key at L139 stays
  the blessed false positive (coord ruling 2026-11-10 + X §7.2). Rejected: keep the
  current deletion-only state (fails NOTE 1's uncomment affordance).
- **RD2 (NOTE 2/3) Guard convention: ROLE list membership in job `if:`, zero URL literals.**
  Guard bytes = R1 §1 rank-1, the only spelling that is unset-widest AND cannot error:
  `vars.ROLE == null || contains(vars.ROLE, '<role>')` (`== null` also covers set-but-empty;
  `contains` never errors; `fromJSON` **errors** ⇒ job red ⇒ rejected for a hand-typed
  value; gate-job form kept as the documented fallback if the probe surprises). Event
  split lives in the same `if:` (`forgejo.event_name` — `on:` itself cannot be
  conditioned, R1 §4). Jobs: `detect-changes` (either-role guard: unset ⇒ true, `dev` or
  `prod` ⇒ true, foreign role ⇒ false ⇒ whole run skips), `build-release`
  (`event_name != 'pull_request' && (…contains 'prod') && needs… != '[]'` — dispatch
  keeps sharing the release arm, run-0 escape-hatch posture), `build-pr`
  (`event_name == 'pull_request' && (…contains 'dev') && needs… != '[]'`). Rejected:
  keep `vars.ROLE == 'prod'` equality in containers (fails the owner's list + unset-widest
  ruling, R1 §5); step-level gates only (job shows green-but-empty instead of a gray
  skipped, and hides the false branch the probe needs to observe).
- **RD3 (NOTE 4) Polarity: one shape, per-file unset-default.** containers guards widen
  on unset (owner ruling); `main-sync` stays narrow-on-unset — as bare
  `contains(vars.ROLE, 'prod')` (unset ⇒ null ⇒ `''` ⇒ contains false ⇒ skipped: cf-119's
  fail-safe and dev-stage breaker **survive unchanged** while the file joins the
  membership shape and starts accepting list values). This makes the sweep a real
  migration (2 job-if bytes + its suite's t3 byte + header gloss), not a verify-noop —
  without it, infra's single `ROLE` cannot serve both files (a `dev,prod` value silently
  stops main-sync's exact `== 'prod'` fan-out). Owner confirms as one ruling with the
  infra ROLE value (plan OQ-1 + OQ-7). Rejected: unify *semantics* (widening main-sync
  would make an unconfigured instance push main out — cf-119's deliberate fail-safe);
  leaving main-sync on `== 'prod'` while containers use membership (two conventions —
  exactly what NOTE 5 forbids at merge time).
- **RD4 (NOTE 5) Sweep scope verified, not assumed:** post-merge the only URL-guarded
  forge workflow left is `containers-build.yaml` itself (C02 converts it);
  `main-sync.yaml` arrived already ROLE-shaped from `main` (`b482935ed`). C04's sweep =
  the RD3 migration + the repo-wide `g1` leg (0 URL literals, 0 `startsWith(forgejo.server_url`,
  no `forgejo.server_url` inside any `if:`, every guard a `vars.ROLE` reference) + the
  docs that state the convention.
- **RD5 (NOTE 2, "local registry") Reading A:** local = the executing instance's own
  registry, host derived from `forgejo.server_url` (source-proven = AppURL, R2) inside
  steps via `env:`, `rest`-style scheme strip mirroring main-sync's `PUSH_URL` shape;
  `forgejo.server_url` is thereby blessed as a *derivation input*, banned as a guard
  predicate, and no URL literal appears anywhere (r5 pins all three). Rejected: Reading
  B cross-instance fan-out (dev PAT custody on prod + a second calendar writer, R2 §5);
  `vars.REGISTRY_HOST` (one more per-instance variable that fails red on unset, against
  the owner's unset-just-works single-server mental model) — carried as OQ-8 since it
  sidesteps the "URL detection retired" prose argument.
- **RD6 Namespace: `curatedforest/<image>`** (lowercase path segment — OCI repository
  names are lowercase-only; owner lookup is case-insensitive). `ownyourio` exists on
  neither lab instance (R2 probed); minting it on both is the parity alternative (OQ-4).
  Push auto-creates the package; visibility inherits the org's (public ⇒ anonymous pull,
  R2 measured) — read anyway with the push PAT so a visibility flip cannot degrade
  derivation to "404 ⇒ N=1 with no walk" (OQ-10).
- **RD7 Push identity: per-instance `secrets.FORGE_PUSH_TOKEN`, human-minted non-admin
  PAT** (org write on the namespace; username in `docker login -u` is cosmetic — Forgejo
  authenticates the token in the password field, R2). Job-token and deploy-token routes
  are source-closed (`// TODO: ActionUser permission check`, no deploy-token wiring) —
  not re-litigated. Non-admin on purpose: site-admin PATs bypass the package access-mode
  check.
- **RD8 Dual-registry N: P3 union-max + per-registry existence walk before any push;
  arms ghcr-then-forge.** `next-n` is registry-agnostic already (detector unchanged);
  the union max + walks live in the workflow shell. Tolerance per side (ghcr token-403 /
  forge 404 `NAME_UNKNOWN` ⇒ contributes nothing; walk only where that side's list
  answered 200; everything else fatal). Failure semantics pinned: half-success leaves a
  *gap*, never a clobber; arm order puts the gap on the registry with no pinned
  consumers. Docs say "every successful build published the same N everywhere it pushed",
  never "the tag sets are equal". Rejected: P1/P2 single-source (cross-registry silent
  overwrite), P4 per-registry N (Renovate and the forge UI disagree).
- **RD9 Tag sets: ghcr = `yy.mm.N` + `latest` + `main` (unchanged D4); forge = versioned
  `yy.mm.N` only; PR = `pr-<sanitized>-<sha>` to the forge registry ONLY.** D5's PR tag
  moves off ghcr per NOTE 2 ("pull_request → local registry only"); `:latest`/`:main`
  stay the documented ghcr cluster contract (OQ-6 guess). PR tag total length must fit
  the tag grammar (≤128): bound the sanitized branch component to leave room for the
  `pr-` prefix + `-<short-sha>` (r4 leg). Renovate rule scope stays ghcr-only (x2
  untouched) — forge images are not pin targets this run.
- **RD10 Probe first (C01):** four dispatch-only probe jobs — rank-1-true, sentinel-false
  (expect the instance's **first-ever observed skipped `vars` guard**), literal-JSON
  `fromJSON` (proves parses at job level), bare-`contains` narrow (the main-sync
  migration shape) — run on infra (dispatch proven there), verdicts recorded in this
  file before C02 review closes (H5). C02 does not hard-block on it (its bytes are the
  cannot-error spelling), but a surprise verdict switches C02/C04 to the gate-job
  fallback and rewrites the r1 bytes; C02 deletes the probe file. Rejected: ship guards
  with no probe (the false branch has never been observed on this instance, X §2
  sharpener; probe cost is one dispatch).
- **RD11 Infra ROLE value `dev,prod` + dev ROLE `dev` (H1/H2, owner-gated):** PR builds
  run on infra (the only instance with a proven executing runner); dev's runner is
  healthy but has **zero tasks ever** and MUST get an explicit `ROLE=dev` before it
  picks anything up (unset ⇒ widest ⇒ dev would publish as a second writer). Dev-role
  live validation on dev hardware stays owner-gated on the runner triage; this run
  promises author + offline pins, plus live PR validation on infra if the owner sets H1.
- **RD12 Retention: forge-side owner-UI Cleanup Rule (`pr-.*`, ~14 d) per instance
  (H8); GHCR `pr-*` stays unpruned** (no platform feature; R2). The nightly
  `cleanup_packages` cron reaps only unreferenced data — the rule is the only forge-side
  reaper; `latest` is code-protected from rules, calendar tags are rule-deletable, so
  the rule pattern must stay narrow (doc line).
- **RD13 Suite economics:** re-author (not append) t3/t5/t7/t8/t9/t11/x1; keep t1/t2/t4/t6/t10/d1–d8/x2/x4
  byte-stable so regressions stay legible; add p1, r1–r5, g1; extend the leg-id parser
  in the same commit. x3's *logic* is unchanged — its content re-pins ride C04.

## 2026-11-11 — owner batched-round answers (ONE round, 8 merged questions; supersedes the matching RD guesses)

- **OQ-1 + OQ-7 CONFIRMED as one ruling — one guard SHAPE, per-file polarity; infra ROLE stays `prod` for now.** containers widens on unset; `main-sync` migrates to bare `contains(vars.ROLE,'prod')` so unset stays cf-119's fail-safe narrow. RD3 stands. **Sequencing rule now binding:** infra's `ROLE` is NOT switched to `dev,prod` until C04 has merged — flipping it earlier silently stops main-sync's `== 'prod'` fan-out. RD11's "dev,prod" becomes a post-C04 owner leg, not a precondition of this run; `ROLE=dev` on the dev instance stays a hard precondition before that runner ever picks work up.
- **OQ-2 CONFIRMED — `dev,prod` (comma, no spaces) + substring `contains`.** RD2's rank-1 guard bytes stand; `fromJSON` is rejected for a hand-typed value (it errors on unset/empty and an expression error FAILS jobs while a false guard only skips). The documented input contract is a comma list with no spaces.
- **OQ-3 OWNER CHOSE: NO probe — RD10 SUPERSEDED, chunk C01 dropped.** The run implements the guards directly with the cannot-error spelling. Consequences the plan must carry: the first-ever false-branch `skipped` of a `vars` guard on this instance stays **unobserved**, the gate-job fallback stays an unexercised documented alternative, and the plan's `depends_on` for C02 loses C01. H5 (the owner's one dispatch) is retired as a precondition; a real PR or the pre-merge smoke becomes the first live observation instead.
- **OQ-4 + OQ-10 CONFIRMED — `curatedforest/<image>`, org stays public.** RD6 stands; reads use the push PAT regardless so a visibility flip cannot degrade tag derivation.
- **OQ-6 OWNER CHOSE: MIRROR THE ROLLING TAGS — RD9 SUPERSEDED on the forge side.** The local Forgejo registry carries `yy.mm.N` **plus** `:latest` **plus** `:main` on main builds, and `pr-<branch>-<sha>` on PRs; ghcr keeps the same set. Impact to re-plan: both registries get the rolling repoint (the pre-merge smoke caveat now names two registries), the owner-UI Cleanup Rule keep-patterns must protect `latest`/`main` and the calendar line while pruning `pr-.*` (RD12 tightened), and the docs may now offer forge as a 1:1 consumer source.
- **OQ-5 + OQ-9 CONFIRMED — Reading A + two human-minted non-admin PATs.** Each server pushes to its OWN registry plus ghcr; the owner mints `write:package` PATs from a non-admin account per instance, stored as Bitwarden items `forgejo-registry-token-{infra,dev}` and entered as repo secret `FORGE_PUSH_TOKEN`. RD5/RD7 stand; RD8's ghcr-then-forge arm order and union-max N are unaffected.
- **OQ-8 CONFIRMED — derive the registry host from `forgejo.server_url` inside steps** via `env:` (no literal anywhere; derivation blessed, guard use banned, `g1`/`r5` pin all three). RD5 stands; `vars.REGISTRY_HOST` rejected.
- **OQ-11 RULED — cf-6 run -1 lands first; card 55 rebases onto it.** This run owns `docker-build.yaml`'s trigger text (C03) and the repo-wide guard convention; the shared-`CICD` co-tenancy overlap is resolved at merge time in this order.



## 2026-11-11 — coord rulings on the Test Writing hand-off (binding on C02/C04 dev and on review)

The test session (`ses_e345dbe39ffepXgOWSSNOIGwc8`) surfaced four judgement calls. The coordinator's edit grant covers `STATE.json`/`DECISIONS.md`/`FRICTION.md` only, so the chunk files keep their original wording and THIS section is the authority where they conflict (run-0 precedent: the C02 folded-in-guard ruling).

- **r1's `fromJSON` ban is scoped, not file-wide.** `chunks/C02.md` AC2 / Tests T-r1 say "`fromJSON` absent file-wide", which contradicts that same chunk's Tasks ("matrix `fromJSON` + `fail-fast: false` + per-cell `name:` … byte-stable") and its T-t5 leg. The plan's Global Constraints and the owner's OQ-2 ruling place the ban on **hand-typed / instance-set values**, and the reason is the failure mode: `fromJSON` *errors* on unset/empty, so it must never evaluate `vars.*`. Pinned scope: **no `fromJSON` in any `if:`, and never over a `vars.*` value**; the `fromJSON(needs.detect-changes.outputs.changed-containers)` matrix carrier stays, byte-stable, and `t5` pins it. Review must not re-litigate the matrix.
- **t8 is strengthened to a per-side push chain** (beyond C02 AC5's per-step token co-presence): each side's push statements, their enclosing `for:` lists, and the transitively reachable assignments must carry that registry's image prefix **and** calendar **and** `:latest` **and** `:main`. That is what makes OQ-6's mirror real rather than assembled-and-never-pushed; mutation-proven red on a forge-calendar-only arm. Accepted as-is.
- **The suite's static per-side naming contract is now law for C02's dev** (documented in the suite header, each FAIL line names the requirement): per-side variables `ghcr_*` / `forge_*`, `${VAR#https://}` scheme-strip for the derived host, per-side tag (or tag-list) variables iterated by *that side's* push loop, and a pre-push `pr-` tag length bound. This is the price of offline determinism — it is not a dev invention to be reworked, and it is what lets `t8`/`t11`/`r2`/`r3`/`r5` be meaningful without a live run.
- **Selector group `c01` renamed `c02`** (`t d r`) because the probe chunk was dropped by the owner's OQ-3 ruling. `t d r` is the C02 gate; `x1` is C03's; the full 29 is C04's and the final review's.
- **Process lesson adopted:** the test session's own `t8` edit left a used-but-undefined name that only a *green-fixture* replay could catch, so the `/tmp/opencode/cf6-fixture*` scratch tree is a mandatory re-run for dev and review on this run.



## 2026-11-11 — coord rulings on the C02 rounds (binding on C03/C04 and on the final review)

- **Both round-1 blockers accepted as real, not reviewer over-reach.** `forgejo.server_url` is `setting.AppURL` verbatim and AppURL is code-guaranteed to carry a trailing `/`, so an untrimmed strip yields `host//owner/img` = invalid reference and **every** run dies at `docker build` before any push (both registries, because one build takes both tag sets); and a scheme-less `/v2/` read makes curl default to **http**, which was demonstrated live against this ingress — a `write:package` PAT in a Basic header over cleartext :80 that *works*, so it fails silently. Both were invisible to a static suite and knowable offline from source: the lesson is that a derived-host refactor in this repo must be checked against the registry grammar and the transport default, not only against the legs.
- **Boundary now pinned in the suite header, not just in chat**: a scheme is required on the registry **API read** and forbidden on `docker login` (takes a hostname) and on the image **ref** (takes a repository path) — a scheme in either is itself an invalid reference. Anyone "fixing" one side of that later breaks the other; `r5` enforces both directions.
- **Tolerance widening (`401/403/404 → contributes nothing`, per side) ACCEPTED as not-a-deviation**: C02's own Tasks and RESEARCH R2 O4 both prescribe the per-side table and `t11` requires the branch. Residual hazard is a ghcr-side 401/403 on a *pushed* image (anomalous: ghcr reads are anonymous, absence answers 403, real outages are fatal 5xx); mitigated by the reviewer's ask, now implemented — both arms **log** their tolerated codes, so a degraded side is visible at H7 instead of silently retargeting N.
- **Optional month-once item taken by the dev and approved**: `date +%y.%m` runs once per release cell and is carried through `calendar.env`, so a run straddling a month boundary cannot mint `newmonth.N` from an old-month walk (gap-vs-clobber asymmetry: a gap is inside the plan's accepted failure semantics, but it was cheap to remove). Reviewer verified the mechanism fails loudly if the file is missing and has no cross-cell carry path.
- **Deferred, deliberately: no static tooth for the trailing-slash class.** The reviewer offered one (reddening a future refactor that drops `${forge_registry%/}`); declined — a missing trim makes **every** run red, i.e. self-announcing at H7, whereas the cleartext class fails silently and *that* one got a pin. Revisit only if a run ever ships trimmed-host code past review.
- **Process**: the `validation_at_fault` route ran as designed and silently — the reviewer never touched the leg, the leg's author amended it, and the amendment was re-verified by the reviewer before the dev was relaunched. Ordering mattered: amending `r5` **before** the dev fix kept the gate honest (23 ok / 1 red pinpointed the unfixed file), and the author's GREEN-first teeth harness is what proved the leg could bless a working file at all.

## 2026-11-12 — run -1 complete: what is NOT carded, and why

- The final review recommended two follow-up cards — (a) **pipeline-locks**: heartbeat must survive a human stop point (the idle-reap-at-human-round bit this card twice, run 0 and run -1) and the `PIPELINE LOCK LOST` notice must key on the live claim's setId so a re-emit is distinguishable from a fresh reap; (b) **permission config**: anchor the `git * push*` deny to the verb position, since it currently matches the word "push" inside a commit-message string and silently blocks the coordinator from writing that word in a message. **Neither was created**: the owner deleted the "Create follow-up cards" HITL item at run 0's write-back, so card creation on this board is owner-owned. Recorded here and in the card's Review comment instead.
- Also left un-carded, deliberately: the stale `~L139` prose in `tests/services/forgejo-containers-build.sh` (the leg is line-number-independent, so it is cosmetic; any edit belongs to the test session, not to a fresh card) and the run-0 docs-parity card already inherited in the Deferred list above.
- Run -1 ends at **Final Review** per the card's surviving HITL item: commit-only class, branch local, no push, no merge. PR creation and merge are the owner's; landing order is cf-6 first, card 55 rebases (OQ-11).

## Deferred (inherited / still open through run -1)

- Run 0's docs-parity card (its test teeth: `tests/pipeline-push-pr/surface.sh` P7,
  `tests/wekan-mcp/tools.sh` t5 + READMEs + runbook + `forgejo-host-runner.sh:235` +
  `wekan-mcp-login.sh` prose). Those suites are green today and none of run -1's file
  lists touch their pinned sources; run -1's doc re-pins must keep x3/P7/tools.sh green
  as they stand.
- AD-134 (one-time pin bump) unchanged; the `services/{dev,gpu}/prod/values.yaml`
  manager-extraction gap unchanged; `:main` retirement unchanged; dev-instance runner
  zero-task triage remains owner-owned (and is now load-bearing via RD11).
- run-0 nits carried, do-not-churn: `head_ref`/PAT interpolation into single-quoted
  shell (same-repo-PR posture), dispatch-from-branch shares the release arm (now with a
  second publish target — restate in the workflow header).

## 2026-11-11 — plan finalized against the owner batched round (agent-plan finalize pass)

The plan of record and all four chunk files now carry the rulings above (agents work
from those files, not from the RD history). Fold deltas, for the trail:

- C01 **DROPPED** (OQ-3): `chunks/C01.md` is a tombstone; the `p1` leg dies with it —
  RD13's "add p1, r1–r5, g1" reads as "add r1–r5, g1" from here. Suite arithmetic:
  **23** (post-merge baseline, 23 ok re-verified at `9f53c2b73`; main-sync neighbor 8 ok)
  → 24 (t/d/r groups) after C02 → **29** full after C04. C02 `depends_on: []`; waves
  renumbered C02+C03 = 1, C04 = 2 (chunk ids never re-used). No H5, no verdict clause,
  no probe-deletion task, no gate-job branch anywhere in the plan text; the unobserved
  false-branch risk stands plainly in the plan's Risks.
- RD9 superseded (OQ-6 mirror): forge carries `yy.mm.N` + `:latest` + `:main` (release)
  and `pr-*` (PR); the calendar walk still gates only `yy.mm.N` — the rolling tags are
  mutable-by-contract and no leg may demand a walk before them (R2 invariant 2
  re-scoped); H7 now repoints rolling tags on **two** registries and mints the first
  calendar tag in both; H8's Cleanup Rule pattern must stay strictly `pr-.*` because
  only `latest` is code-protected (`:main` + calendar survive on pattern narrowness).
- RD11 rewritten (OQ-1/OQ-7): infra `ROLE` stays `prod` through the run — `dev,prod` is
  a **post-C04-merge** owner leg (H1); `ROLE=dev` on dev stays a hard precondition (H2).
  C04's AC7 pins the merge-before-flip clause into the docs text.
- OQ-2/4/5/8/9/10/11 confirmed → plan "Open questions" is now an ALL-ANSWERED section;
  no new question was opened. Verified post-merge ground: 13 container dirs
  (`vllm-radiance-mxfp4` in, `vllm-rocm` gone), main-sync guards still the exact
  `vars.ROLE == 'prod'` bytes C04 migrates (its suite pins them at its L74).
