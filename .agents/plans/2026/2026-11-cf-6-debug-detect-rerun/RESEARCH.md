# RESEARCH — cf-6-debug-detect-rerun (agent-research, 2026-11-25)

Topic: keeping monorepo container-build change-detection CORRECT under
re-integration (rebase/replay/force-push + push-to-main) workflows —
STORM round on the owner's ask: *"something that supports my current
workflow of re-integrating commits onto main and then pushing."*

## Reliability notes (storm self-review)

- Failure-mode catalog (R1): **9/10** — primary payload docs + the two most
  used changed-files tools' docs/issue threads describing exactly these
  shapes; corroborated by this ticket's own live forensics.
- "Delivery loss is the real AD-133 mechanism" : **9/10** — the
  nx-set-shas README problem statement [7] and #314's detailed thread
  answer [3] state it verbatim; ticket reproductions prove the shipped
  detector's arithmetic is NOT the culprit.
- Reconciliation loop correctness (tree-hash label → registry probe):
  **8/10** — every primitive is source-proven ([9][10][11][13] + the repo's
  own vllm-radiance config-blob-label read and the shipped registry-HTTP
  walks); the *assembly* as a public, documented recipe is **not** found —
  this exact loop in bash-on-Forgejo is synthesis, stated honestly.
- Marker-pointer option (O2) : **7/10** — pattern is battle-proven at
  GitHub scale [7], but its per-container granularity trap and the CI git-
  write requirement are reasoned, not observed, in this stack.
- Weakest claim: "GHCR public reads are effectively un-rate-limited at this
  scale" — based on documented anonymous-access semantics [16] and an
  unresolved community thread [18], not a published quota. Would verify by
  running the pilot loop (it *is* the verification).
- Over-weighted lens: GitOps-controller designer (the brief expected
  reconciliation to front-run; sources genuinely rank it there, and the
  homelab-realist counter-argument about trigger-gated WAKE-ups [G] was the
  correction that shaped the final #1 recommendation).
- Sixth angle that would sharpen conclusions: supply-chain/hermeticity —
  a tree-hash says *sources* unchanged, not *outputs* unchanged (base-image
  drift under an unchanged tree); flagged in Adjacent, would change the
  stamping contract (record resolved base digests too).

## TL;DR

1. The shipped detector is already rebase-safe *as arithmetic*: it diffs
   endpoint TREES, so replayed commits cannot fool it. The failure is not
   the diff — it is the **assumption that one successful event delivered
   every state change** [1][3][28].
2. The owner's class ("re-integration landed, nothing detected to build")
   is the ecosystem's *named* permanent-under-build hole: failed/dead runs
   leave content on main that no future event-delta ever covers; the
   recommended fix class (named in [3], implemented by [7]) is "diff
   against the last successfully-built state" [3][7][8].
3. Two implementations survive scrutiny: a **moved marker** (state ref, O2)
   and a **registry-state reconciliation sweep** (tree-hash stamped in the
   published image, compared every wake, O1). O1 is structurally
   self-healing; O2 self-heals lazily and keeps the current laws more
   literally.
4. Critical stack-specific catch: on Forgejo the *wake* itself is event-
   filtered (`on.push.paths: containers/**`), so O1 must pair with a
   scheduled sweep (or widened trigger) — that pairing (event fast-path +
   cron resync) is the ranked #1 recommendation.
5. Switching to PR-merge/squash does **not** fix this failure class — the
   completeness assumption breaks identically under any integration style.
   The PR trigger over-fire (finding A) is a separate upstream bug, already
   fixed in Gitea (#36045, merged 2025-11-28) [34].

---

## 1. Findings by theme (R1–R5)

### A. Payload semantics under history rewriting (R1)

- GitHub push payload: `before` = "SHA of the most recent commit on ref
  before the push", `after` = "...after the push" — no force-push special
  case; after a rewrite, `before` simply denotes an orphaned tip [1]
  (PROVEN-docs). Actions runs the workflow with `GITHUB_SHA` = tip pushed to
  the ref; a multi-commit push is ONE event covering the whole batch
  (events-not-created only above 5,000 branches / 3 tags) [2] (PROVEN-docs)
  ⇒ multi-push batches are SAFE for range diffing.
- Gitea/Forgejo push payload carries the same `before/after` plus
  `commits`/`total_commits`/`head_commit` [4] (PROVEN-docs); this repo's
  family law that Actions push payloads leave `total_commits` at 0 is why
  the shipped detector reads only endpoints (AGENTS.md; ticket-consistent).
  All-zero `before` = branch creation sentinel, in both families
  (GitHub webhook docs [1]; GitLab documents the identical shape for
  `CI_COMMIT_BEFORE_SHA` — "always 0000… for the first commit in pipelines
  for branches or tags") [29] (PROVEN-docs).
- **Re-runs**: GitHub re-runs execute "the same `GITHUB_SHA` and
  `GITHUB_REF` of the original event" [6] (PROVEN-docs); Forgejo exposes
  `FORGEJO_EVENT_PATH` (full stored webhook payload on the runner) and
  `run_attempt` incrementing on re-run [5] (PROVEN-docs). The ticket proved
  *live* that v15.0.10 reuses the stored payload verbatim across attempts
  (runs 240, 104–184, 244–246) — PROVEN(ticket) EXPLORE §2/§5. Consequence:
  a payload-anchored detector answers the *same* question forever, which is
  both the family's idempotency law and its static-truth trap.

### B. The permanent under-build — delivery loss, not bad math (R1/R5)

- dorny/paths-filter #314 (detailed thread answer): **"Failed/skipped/cancelled runs:
  `event.before` only covers _this_ push. If a run fails or gets cancelled,
  those changes are never examined again... the next push only diffs from
  its own `before`. So if this is driving deployments, services can get
  missed permanently. The more robust pattern there is to diff against the
  last _successfully deployed_ commit (a tag you move on success, or a
  lookup of the last successful workflow run, e.g. how `nx-set-shas` does
  it)."** [3] (PROVEN-quote)
- nx-set-shas states the same law from the deploy side: "If a few
  deployments fail one after another, that means that we're accumulating a
  list of affected projects that are not getting deployed... we want to
  include **every commit since the last time we deployed successfully**.
  That way we ensure we don't accidentally skip deploying a project that
  has changed" [7] (PROVEN-quote). v1 implemented the pointer as **git
  tags**; v2 switched to a **CI-API lookup** of the last successful run [7]
  (PROVEN-docs).
- Map to the owner's AD-133 event: the re-integration push's container
  content was ALREADY on main (dead-at-0s runner-down era, ticket case B —
  both registries never received those images). Event-diff vs the previous
  main tip sees zero container delta ⇒ empty set — and on the push side the
  platform's `paths: containers/**` filter may not even start the workflow
  (§G). Correct event-diff; wrong world-model. PROVEN(ticket) EXPLORE §2/§5
  + INFERRED mapping (the exact AD-133 payloads were not re-examined here).
- Over-fire mirror (same thread): "Rebase + force push: the diff
  between old and new tip includes _every upstream change pulled in by the
  rebase_... filters for unrelated services will fire. That's inherent to
  comparing snapshots before/after a rebase" [3] (PROVEN-quote). Note what
  this is NOT: it does not UNDER-build; a spurious extra calendar tag is the
  price of snapshot diffing — which is precisely why over-fire becomes a
  feature for state-based detectors (§H, teeth analysis).
- Tree-to-tree immunity: `git diff --name-only A B -- path` compares
  endpoints' content, not commit identity; the fast-forward-ness idiom
  `git merge-base --is-ancestor A B` [28] documents the algebra. Re-playing
  a commit whose result was already there ⇒ no spurious *content* delta;
  replaying NEW container content ⇒ delta regardless of commit shas.
  (PROVEN-docs syntax + PROVEN(ticket) 9-shape reproductions with the
  shipped script.)

### C. Trigger over-fire (finding A) has an upstream fix already (R4)

- Gitea issue #34710 "Gitea Actions `paths` filters incorrectly trigger
  during rebase operations" — filed as type/bug, reproduces this ticket's
  finding A mechanism-by-shape (monorepo, rebased branch, paths filter
  fires on files not changed in the PR's final diff) [33] (PROVEN-issue).
  The linked fix, PR **#36045 "Fix Actions `pull_request.paths` being
  triggered incorrectly by rebase", merged 2025-11-28** [34] (PROVEN-merged).
- A commenter reports the `push.paths` sibling still over-fires on GitHub
  too — i.e. the push-side filter semantics ("submitted commits changed")
  are inherent, matching [3] (PROVEN-comment, INFERRED generality).
- Forgejo's own track: #12739 fixed a DIFFERENT server-side changed-files
  defect (PR paths filter not running when merged — post-merge base..head
  evaluation) [32] (PROVEN-issue). The instance here is
  15.0.10+gitea-1.22.0 (ticket API probe) — predates #36045's lineage; the
  over-fire stays until Forgejo lands an equivalent (PROVEN version
  + INFERRED backport status). ⇒ **The C2 "needs upstream verification"
  item is materially answered**: the bug, its mechanism, and a merged fix
  all exist publicly; an owner-filed Forgejo issue can cite #34710/#36045
  verbatim.
- Design law extracted: trigger noise (a wake that shouldn't have happened)
  is a platform-layer property you cannot fully fix client-side; the
  detector's robustness is measured by its INDIFFERENCE to why it woke.

### D. State reconciliation: primitives and prior art (R2)

- **Tree hash = content identity.** `gitrev:<path>` names "the blob or tree
  at the given path" [10] (PROVEN-docs); a directory's tree oid is
  invariant to commit shas/branches/rebases. `want(c) = git rev-parse
  HEAD:containers/<c>` is a two-call primitive, runner-cheap.
- **The stamp.** OCI annotations spec: `org.opencontainers.image.revision`
  = "Source control revision identifier for the packaged software"; custom
  keys are legal under reverse-domain namespacing; `org.opencontainers`
  prefix reserved [9] (PROVEN-spec). `docker build --label` (classic
  builder — this fleet's exact builder) writes image **config labels**
  [13] (PROVEN-docs); a registry then serves the config blob at
  `GET /v2/<name>/blobs/<digest>` after `GET /v2/<name>/manifests/<ref>`
  [11] (PROVEN-spec). The repo has already performed exactly this read
  against a live registry (vllm-radiance ledger: revision label read from
  a config blob over the tags API) — PROVEN(ticket/repo).
  Provenance attestations are the modern alternative but are NOT available
  here: "Attestations attach to an image index. The classic image store
  doesn't support image indices" [14] (PROVEN-docs), and the fleet builds
  on the classic store (no buildx cache flags; plain `docker build` — repo
  YAML comment).
  Stamping nuance: stamp `revision=<commit sha>` for human provenance but
  compare a **custom tree key** (e.g. `io.ownyour.container.tree=<oid>`) —
  a commit-sha revision after a re-integration differs while content
  matches, causing rebuilds that the design exists to prevent (§B immunity
  would be thrown away). INFERRED design point, grounded on [3].
- **The loop family in the wild** (consumer-side, same physics): Argo CD
  Image Updater's strategies make the REGISTRY the truth — `newest-build`
  ("most recently built image found in a registry"), `digest` for mutable
  tags ("all update strategies except digest assume tags to be immutable")
  — directly applicable since this fleet's `:main`/`:latest` are mutable
  [12] (PROVEN-docs); Watchtower's whole product is a digest-compare
  reconcile loop [23]; Renovate homelab practice files digest-drift PRs
  under a fixed tag [25]; "a digest is an immutable content hash, unlike a
  mutable tag... pair digest pinning with scheduled rebuilds" [26].
  Controller theory: level-triggered reconciliation "survives missed
  events and crashes... a dropped notification only delays convergence,
  never breaks it" [17][27] (PROVEN-secondary).
- **The minimal correct bash loop** for this stack (synthesis — component
  citations above; the assembly itself: no public prior art found, said
  plainly):
  for each `containers/<c>`: `want = git rev-parse HEAD:containers/<c>`;
  `got = manifest(:main) → config blob → tree-label` (absent tag / absent
  label ⇒ `got=""`); emit `c` iff `want ≠ got`. Reads ride the ALREADY
  shipped auth surfaces: anonymous pull-token exchange on ghcr,
  `FORGE_PUSH_TOKEN` basic auth on the instance registry, with the same
  "absence-as-status, anything-else-fatal" tolerance posture (repo YAML;
  ticket §2). Parsing stays sed/text (runner image ships no jq/python —
  repo script header) following the proven `next-n` stdin-parser shape.

### E. Event-diff hardening patterns (R3)

- Merge-base fallbacks when `before` is orphaned: plain
  `git merge-base A B` yields the common ancestor (content diff of the
  divergence — over-fire-safe); `--fork-point` is the tool for rewound
  bases but **depends on the reflog**, fails when gc expired entries, and
  needs the right fork-tip history [28] (PROVEN-docs) — CI checkouts have
  no meaningful reflog, so fork-point is a workstation tool, not a runner
  tool (INFERRED from documented mechanism).
- "Last built sha" homes without new infra: (i) **a tag/ref the success leg
  moves** — dorny prescription [3], nx v1 implementation [7], and this
  repo's own precedent of CI-time token writes (release.yaml bump/publish
  under `FORGE_PUSH_TOKEN`; AGENTS.md) — cheap (`git ls-remote`/one ref
  read), one pointer per container or one global with the matrix-granularity
  trap (§H); (ii) **CI-API lookup** of last successful run [7] — but
  "run success" conflates chart-only runs that detected `[]` (they are
  green!) with runs that actually built the container: a global pointer
  advanced by a green empty run would skip past unpublished content — the
  runs API cannot ask "last run that built X" (INFERRED from workflow job
  shapes + [32]; flagged as the reason (ii) ranks below (i)/(iii));
  (iii) **the registry itself as state** (option D) — per-container truth by
  construction.
- tj-actions #2935 documents the push-range's other edge: a push whose
  history contains an INTERIOR merge makes `before..after` "reach back past
  the merge and sweep in the default branch" — measured 477,742 files vs
  156 real: "a wrong range is not only slow, it is wrong" [8] (PROVEN-issue).
  For container builds that shape is over-fire (extra rebuilds), and the
  shipped tree-diff makes it content-correct anyway — but it shows the
  event-delta concept drifting from "what changed to main" under mergey
  histories; the state-sweep has no such concept.
- dorny long-lived-branch mode anchors on "the most recent commit on the
  same branch before the push" [30] — i.e. every hardened tool in this
  space still anchors the DEFAULT path on the same `event.before` physics
  (PROVEN-docs); hardening means choosing a better BASE, which lands
  exactly on (i)–(iii).

### F. Workflow-change options evaluated honestly (R4)

- **PR-merge (merge-commit)**: platform adds a merge commit; the main push
  event's `before..after` covers base-advance + PR commits; correct and
  sound — but the dead/failed post-merge run creates the SAME permanent
  gap [3][7]. The owner's local re-integration + FF-push already produces
  event-sound ranges (§B immunity): their workflow is NOT broken; the
  detector's world-model is.
- **Squash-merge / rebase-merge**: the resulting main commit contains all
  PR content (event-diff sees it) [35];
  ticket §4 fact: heads land as ancestors only under merge-style — but for
  ENDPOINT tree diffs style is irrelevant anyway. Same delivery-loss hole.
- **Rebase-and-merge via UI**: linear replays on main in one push — event
  ranges stay sound (FF); no payload pathology difference from the owner's
  local re-integrate (INFERRED from [1][28]: same FF-before..after shape).
- **Branch/tag-per-container ("release declaration")**: Mixinet runs this
  exact stack shape — Forgejo Actions runner publishing OCI images, with
  multi-semantic-release creating per-Dockerfile-folder git tags and a
  `build-image-from-tag` workflow building from the TAG, not a push range
  [19][20] (PROVEN-blog+repo-API). Structurally this removes the detection
  question (a tag names its own build, like dispatch); it costs a release
  tool, new tag semantics, and collides with the yy.mm.N calendar contract
  (a second versioning story). Also retains delivery loss on the tag event
  (a dead tag-run needs a re-fire) but any later tag re-push rediscovers it
  (INFERRED).
- Verdict: no workflow change removes the completeness assumption; only
  base-reselection (O2) or state-vs-state comparison (O1) does.

### G. The wake-up blind spot — THIS stack's twist (R5, decisive)

- `.forgejo/workflows/containers-build.yaml` `on:` = `push: branches[main]
  paths['containers/**']` + `pull_request: ... paths['containers/**']` +
  dispatch escape hatch (repo, PROVEN-code). Forgejo evaluates the paths
  filter server-side from the event's changed files [31] (PROVEN-docs).
- Consequence: the AD-133 push (container delta EMPTY vs previous main tip
  because the content was already on main) **does not trigger the workflow
  at all** — the reconciliation answer never gets asked. A pure push-arm
  redesign of `detect()` would still self-heal nothing. (This also refines
  ticket finding A's twin: PR-side over-fire = filter false-positive;
  push-side under-wake = filter false-NEGATIVE — same platform mechanism,
  opposite symptom.)
- The controller fix: pair the event wake with a **scheduled resync** —
  Forgejo documents schedule events present in the default branch
  [5][31] (PROVEN-docs) — `on: schedule: cron` firing the detect job (and
  only-drift builds) hourly/daily. That is the textbook level-triggered
  shape: event = latency optimization, resync = correctness guarantee
  [17][27]. Alternatively widen push to every main push and let the sweep
  decide (noisier run list, same effect); or a hybrid (event-gated sweep on
  pushes + cron full sweep) — owner knob.
- The dispatch escape hatch already documents this failure model in
  comments: "name the containers to (re)build when their sources did not
  change but a publish is due (a failed or cancelled earlier run)" (repo
  YAML) — the owner's current manual patch; the scheduled sweep automates
  exactly that sentence (strong internal-consistency signal).

### H. Fit into this stack (R5 synthesis)

- **Costs/rate-limit exposure**: O1 sweep ≈ per container: 1 ghcr token +
  1 manifest GET + 1 blob GET (+ same trio on forge, auth'd) ⇒ ~14×(2–4)
  reads ≈ 30–60 GETs per wake — one order below what the calendar-N walks
  already issue per BUILD (repo YAML), sub-minute wall time, seconds of
  detect-job when it all matches. Public GHCR image access is documented
  as anonymous [16]; no published hard quota for registry reads, community
  thread unresolved [18]; forge reads are on-instance (INFERRED: negligible
  at homelab scale; pilot below MEASURES it). O2: one ref read + one
  tag-push per success. No new secrets in either (both ride
  `PUSH_TOKEN_GH`/`FORGE_PUSH_TOKEN`, already-scoped).
- **Re-run idempotency law**: O1 changes the guarantee's *letter* — a
  re-run of a successful build now answers `[]` (world converged), not
  attempt-1's set; the *intent* ("no under-report from refs moving") is
  preserved and strengthened. O2 keeps the letter: marker==sha ⇒ the same
  silent no-op exemption shape the before==sha rule already has (repo YAML
  guard). Both need the law restated in DECISIONS; O1 more deeply.
- **No-vacuity/warn laws**: today `[]` on push/PR = `::warning::changed
  set resolved empty`. Under O1, push-arm `[]` means VERIFIED published==
  main (good news, silence or info line); the NEW anomaly class to warn on
  is drift the sweep refused to build (gate skipped a differing container).
  PR arm keeps its semantics (PRs stay event-diffed — there is nothing to
  reconcile against `:main` for an unmerged head). Under O2 the laws
  survive nearly verbatim.
- **Which registry is the truth operand?** No public art (blind spot).
  Proposal: differing on EITHER side ⇒ build (the publish legs already
  advance both sides jointly with union-N; ghcr-first ordering means a
  half-publish gaps the forge side — checking both makes the gap
  self-heal, matching the workflow's own stated intent).
- **Teeth re-pin surface (41-leg suite, per EXPLORE §7)**:
  - O1: t13 re-pin (env contract grows: registry host(s)/token plumbing or
    stdin blobs); t14 rewritten for the new push-arm posture (new shapes +
    new warning law); d1–d11 push-arm family re-worded (range→sweep,
    all-zero→first-publish); d14/d15 untouched (PR arm); ONE new d/x fixture
    class with RECORDED registry JSON (keeps the script pure: network lives
    in the YAML, parsing in the script — the `next-n` stdin precedent);
    x5 doc-trio vocabulary; b-suite (non-use pins) untouched. Largest
    surface.
  - O2: t13 extended (marker accessor); t14 extended (marker==sha
    exemption); new d-leg(s) for marker resolution on detached CI clones;
    d14/d15 untouched; x5 modest; build leg gains a `git push` of the
    marker under FORGE_PUSH_TOKEN (new job permission — check the
    "non-advancing-main" law holds: the marker ref is NOT main; one
    deliberate new ref-verb).
  - O3 (C1 legibility, independent of the above): t14 + x5 only.
  - O4 (workflow change): no teeth, no code — and no fix.
- **Over-fire (finding A) per option**: O1/O2 make the DETECTOR immune
  (waking for no reason re-verifies and no-ops) — the over-fire becomes a
  FEATURE; the platform's spurious PR runs and their warnings remain a
  legibility issue (C1) plus an upstream nudge now backed by primary
  sources [33][34]. O3 leaves everything still needing the upstream issue.
- **What same-shape homelabs do (honest reading)**: the exact public
  intersection (Forgejo+act+dind+dual-OCI+bash-detector) is essentially
  unfindable. Adjacent public practice: Mixinet's tag-driven builds
  [19][20]; skopeo-for-dind publishing [21]; consumer-side reconcile loops
  everywhere (Watchtower/Argo/Renovate) [12][23][25]. No public bash
  tree-hash reconcile found ⇒ O1 is synthesis from proven components; the
  ticket's own N-walk + label-read receipts make it a short, low-risk
  assembly. State plainly rather than pad.
- Security footnote: CVE-2026-27771 (Gitea/Forgejo-family registry authz
  flaw — unauthenticated pulls of PRIVATE manifests) [22]: keep the sweep
  reads on authenticated paths; do not "optimize" the forge side to
  anonymous reads.

---

## 2. Expert lenses (grounded takes)

**CI-plumbing engineer**: "The payload is the only frozen truth; the
detector reads it correctly and re-runs faithfully — I proved that here
already. But 'faithful to a stale question' is a feature only while the
event inventory is complete, and the #314 thread just wrote our
post-mortem: a dead run's changes are never examined again. If we keep
event-diffing, diff from the last BUILT state, not the last PUSHED state —
a moved tag, or better, don't track it in git at all when the artifact
itself can carry the truth." [1][3][6][7]

**GitOps-controller designer**: "You built an edge-trigger that must be
level-triggered. Desired state = `containers/<c>` tree oid; observed state
= the oid stamped in the published config blob; build iff differ. Every
component is already in your runner's muscle memory (token exchange,
manifest walks, sed JSON parsing). One caveat your YAML teaches: WAKE is
also event-gated — a controller that only runs on change-notifications is
not reconciling, it's hoping. Add the resync period." [9][10][11][13][17][27]

**Monorepo-CI tooling engineer**: "The community answer to force-push
detection is boringly consistent: fetch-depth 0, snapshot diffing is
inherently over-firing, and the only cure for under-firing is a better
base. nx-set-shas spent two major versions converging on 'last successful'
resolution — v1 moved git tags, v2 queries the CI API. Your matrix makes
the API flavor subtly wrong (green-empty runs poison a global pointer), so
if you stay in event-land, use per-container markers; if you're adding a
pointer per container anyway, put it where it's per-container BY
CONSTRUCTION: the image." [3][7][8][30]

**Homelab realist**: "Translation of the owner's week: runner died,
Renovate rebased everything, registry quietly fell behind, and event-diff
says 'nothing to do' forever until someone dispatches by hand — which your
own dispatch-hatch comment already admits is the failure mode. Hourly
sweep + drift-only build is boring, costs ~40 GETs, needs zero new
services, and the pilot is ten lines of curl. Also: your `:main` tag is NOT
an identity — Argo's docs scream it at mutable-tag trackers — so compare
the CONFIG behind the tag, not the tag." [3][12][16][19][21]

## 3. Conflict map

| Axis | Event-diff hardened (O2/O3) | State reconcile (O1) |
|---|---|---|
| Truth base | last pushed / last built sha | published artifact's recorded content id |
| Rebase/force-push | correct via tree-diff; over-fires (inherent) | indifferent (why it woke doesn't matter) |
| Delivery loss (dead runs) | permanent gap until next container-touching wake (LAZY heal) | healed within one wake period (GUARANTEED heal) |
| Re-run semantics | reproduces original verdict; marker==sha silent | verdict = truth NOW (post-success re-run = `[]`) |
| New infra | a ref/tag + push leg, or none | registry reads + one `--label` stamp (+ a cron) |
| Wake gating (Forgejo) | still blind (trigger filter false-negatives) | needs cron/widened trigger to actually fire |
| Teeth churn | t13/t14 add, d14/d15 untouched | push-arm family re-pin + 1 new fixture class |

Where they clash: payload-fidelity maximalists (O2's law preservation) vs
convergence thinkers (O1) — resolved by noting the family law protects
against MUTABLE-REF drift, which O1 satisfies (its ref inputs stay frozen;
only its WORLD-VIEW live-ness changes) while restating the law. Agreement
across all lenses: shipped arithmetic is fine; the completeness assumption
is the bug; upstream trigger noise is separate and now-citable [33][34].
Blind spot (all): dual-registry truth-side, bootstrap policy, base-image
drift under unchanged trees (Adjacent).

## 4. Ranked options

Criteria: **W** = supports re-integrate+push (their ask) · **F** =
correctness under force-push/rewrite · **I** = re-run idempotency · **N** =
minimal new infra · **E** = effort (✓✓ = least) · **R** = rate-limit
exposure (✓ = least).

| # | Option | W | F | I | N | E | R | Net |
|---|---|---|---|---|---|---|---|---|
| 1 | **O1 — Reconcile sweep**: push-arm decision = `tree-oid HEAD:containers/<c>` vs stamped label on the published :main config blob (both registries); event-diff kept as PR-arm logic; **cron resync** as the wake-guarantee; `--label` stamping in the publish leg | ✓✓ structural | ✓✓ immune | ✓ law restated (re-run = re-verify) | ✓ reads only; no new services; one cron | ✗ biggest teeth surface | ✓ ~30–60 GETs/wake | **front-runner; fixes the class, makes over-fire harmless, automates the dispatch-hatch's own stated intent** |
| 2 | **O2 — Marker-shifted event-diff**: base = last-fully-built main sha (per-container tag `built/<c>` moved by the success leg, or global marker with over-fire-on-partial-failure); rerun-after-success answers `[]` silently via the marker==sha exemption | ✓✓ | ✓ (content-correct, can over-fire) | ✓✓ law verbatim | ✓ one ref + git-write permission | ✓ medium | ✓✓ one ref read | strong fallback if the owner wants the laws untouched; lazy-heal only, still wake-blind without a cron anyway |
| 3 | **O3 — Legibility polish (C1) + owner re-run discipline** (current ticket candidates) | ✓ (status quo) | ✓ | ✓✓ | ✓✓ none | ✓✓ t14/x5 only | ✓✓ none | ships regardless of #1/#2 — the warning wall deserves re-scope and the dead-at-0s PRs deserve their re-run leg |
| 4 | **O4 — Workflow change (PR-merge / rebase-and-merge / squash)** | ✗ the ask was "keep my workflow" | ✗ same hole (delivery loss is style-independent) | ✓ | ✓✓ none | ✓✓ none | ✓✓ none | **myth for this failure class** — evaluate as personal-preference only |
| 5 | **O5 — Release-declaration builds** (Mixinet-style per-folder git tags, or extend the calendar contract into a tag event) | ✓ | ✓✓ event-naming (tags carry their own set) | ✓ re-fire a tag | ✓✗ one release tool OR a bespoke tag-mover (then it's O2 wearing tag clothes) | ✗ re-contracts the calendar law | ✓ | parked: real precedent [19][20] but collides with yy.mm.N; revisit if O1 lands and the owner wants explicit publishes |

Mandatory companion, any ranking: **file the Forgejo upstream issue** for
the PR paths-filter over-fire with the ticket's evidence package +
Gitea #34710/#36045 pointers (C2's "needs research" is now answered).

## 5. Top-3 deltas (concrete, teeth-aware)

**O1** — `forgejo-container-detect.sh`: new `sweep` verb (stdin:
recorded registry probe lines `<name> <want-tree> <got-label>`, pure
differ+gates — keeps the no-network-script purity via the `next-n`
stdin pattern); YAML detect job: push arm curls the probes (token flow +
GET manifest + GET blob + sed-extract the tree label; tolerance posture =
existing codes-family), feeds the script, emits the drift set; PR arm
byte-untouched; build leg adds
`--label org.opencontainers.image.revision="$sha"` +
`--label io.ownyour.container.tree="$tree"`. New `on.schedule` job-guard
(cron wake skips PR/dispatch arms; empty sweep = silent verified no-op).
Teeth: t13 grows env list (re-pin bytes), t14 re-scope (push-empty
semantics flip to info; new warn class = gate-skipped drift), d1–d11
push-posture re-word, d14/d15 green untouched, new d-probe fixture class,
x5 trio vocabulary ("push sweeps state; PRs diff merge-base..head"),
b-suite untouched. Bootstrap decision: first sweep finds all ~14 unlabeled
⇒ either one-time full publish (simplest, honest) or "absent-label =
match" until adoption (keeps one manual dispatch clean-up; weaker
guarantee) — owner ruling.
**O2** — marker resolution `a=$(git ls-remote ... refs/tags/built/<c>)`
per container (or global ref), fallback `before` on first-ever run;
success leg pushes marker(s) with FORGE_PUSH_TOKEN (NOT main-advancing:
a refs/tags move; the never-advance-main law holds because tags aren't
main-advancing refspecs for a protected-branch main — plan must re-verify
the repo's ref-permission surface); detect arms re-pin at t13/t14 + new
d-legs; PR arm untouched; wake-blindness fix (cron) is an OPTIONAL add-on
that re-asks the marker question, making O2 converge to O1-lite with a
git-side pointer instead of an OCI-side one.
**O3** — C1 exactly as EXPLORE §6 sketches (warning re-scope for
legitimate-empty PR results; keep push no-vacuity) + the owner UI legs
(re-run dead-at-0s PRs, heads proven fetchable). No correctness change —
and therefore the next AD-133 still lands; its job is honesty of optics.

## 6. The <30-minute decisive pilot (owner-side, read-only + one local build)

Part 1 — the probe half (pure reads, no build; proves plumbing AND shows
today's drift — expect every container to answer `got=none` because the
era's images carry no tree label; that IS the pre-adoption state O1
handles by design):

```bash
cd <SpencersLab checkout, main tip>
for c in $(ls containers/); do
  [ -f "containers/$c/Dockerfile" ] || continue
  want=$(git rev-parse "HEAD:containers/$c")
  tok=$(curl -sf "https://ghcr.io/token?scope=repository:ownyourio/$c:pull" \
        | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  # one label per line; skip the index indirection for single-arch builds by
  # taking the manifest's own config digest (multi-arch = one extra hop)
  man=$(curl -sf -H "Authorization: Bearer $tok" \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
        "https://ghcr.io/v2/ownyourio/$c/manifests/main")
  cdig=$(printf '%s' "$man" | sed -n 's/.*"config":{"digest":"\(sha256:[0-9a-f]*\)".*/\1/p')
  got=$(curl -sf -H "Authorization: Bearer $tok" \
        "https://ghcr.io/v2/ownyourio/$c/blobs/$cdig" \
        | sed -n 's/.*"io.ownyour.container.tree":"\([^"]*\)".*/\1/p')
  printf '%-28s want=%s got=%s %s\n' "$c" "${want:0:12}" "${got:0:12}" \
    "$([ "$got" = "$want" ] && echo MATCH || echo BUILD)"
done
```

Part 2 — the stamp+round-trip half (one small container, e.g.
`renovate-mcp`; proves the write side end-to-end and flips that row to
MATCH):

```bash
c=renovate-mcp
tree=$(git rev-parse "HEAD:containers/$c")
docker build --label "io.ownyour.container.tree=$tree" \
  -t "$FORGE_HOST/curatedforest/$c:treepilot" "containers/$c"   # or run it
  docker push "$FORGE_HOST/curatedforest/$c:treepilot"          # inside a runner
# then probe back (curl, PAT-authed as in the YAML legs):
curl -sf -u "forge:$FORGE_PUSH_TOKEN" \
  "https://$FORGE_HOST/v2/curatedforest/$c/manifests/treepilot" | sed -n 's/.*"digest":"\(sha256:[0-9a-f]*\)".*/\1/p'
curl -sf -u "forge:$FORGE_PUSH_TOKEN" \
  "https://$FORGE_HOST/v2/curatedforest/$c/blobs/<that-digest>" | grep -o "io.ownyour.container.tree[^\"]*\"[^\"]*\""
```

What it decides: if Part 1's per-container loop runs in seconds (it will —
it's the N-walk subset) and Part 2 round-trips the label through both
registries' distribution APIs with stock tools, the whole O1 physics is
verified against the owner's real registries, and the ranked decision is
between restating-the-laws-now (O1) vs paying the lazy-heal gap (O2).
(No docker daemon exists in agent sessions — this is deliberately an
owner leg; a same-shape CI trial could run it inside a runner pod.)

## 7. Contradictions and how to weigh them

- Brief expected O1 front-runner; sources agree [3][7][12][16][17][19] —
  but ONLY with the wake-guarantee pairing [repo YAML `on.push.paths`],
  otherwise O1 is theater for the exact AD-133 class. Weigh: the pairing
  converts a good idea into a correct design; keep it non-negotiable.
- Re-runs-reproduce-the-set vs re-runs-reverify-the-world: genuinely
  irreducible; the ticket's law exists to block mutable-REF surprises, and
  O1 preserves that while changing verdict-freshness. Weigh: restate in
  DECISIONS (one paragraph, owner-confirmed) rather than pretend both
  properties coexist.
- [8]'s "wrong range is wrong" alarm vs this repo's immunity: the range
  IS tree-diffed here (endpoints, not commits), so the tj pathology is
  over-fire-only for us. Weigh: it warns against any future switch to
  commit-list semantics (rev-list), and against anchoring anything on the
  stale `merge_base` field (ticket C4 re-confirmed by [33]).
- [18] ghcr-limits-unresolved vs "unlimited" marketing guides: treat
  exposure as LOW-but-undocumented; the pilot measures it directly;
  worst-case mitigation = sweep only the event-delta set on pushes and the
  full set on cron (hybrid), halving read volume at negligible cost.

## 8. Implications for the plan (what the planner should decide differently)

1. Stop treating this as a detector-arithmetic bug: EXPLORE killed the
   hypothesis; the sources rename the real defect to **delivery loss +
   wake gating**. The plan's goal statement should be the owner's ask —
   "re-integration-safe detection" — not "fix empty diffs".
2. Scope decision for the owner (one ruling): O1(+cron) vs O2(+cron-lite)
   vs O3-now/O1-later. The teeth map says O1 ≈ push-arm-family re-pin +
   1 new fixture class; O2 ≈ additive legs; O3 = t14/x5 only. C1 legibility
   ships under all three.
3. If O1: rule the stamp key pair (`revision=commit` informational,
   `io.ownyour.container.tree=oid` compared), truth-side(s) (both
   registries recommended), bootstrap policy, and the restated re-run +
   warn laws BEFORE any leg re-pin (x5 doc-trio law: same change).
4. The upstream route (C2) no longer needs a research pass: cite [33][34]
   + the ticket's measured `merge_base` staleness; the ask = Forgejo
   backport status for the Gitea fix.
5. Tests: keep the script pure — registry I/O lives in the YAML, probes
   arrive on stdin (the `next-n` pattern); the new d-fixture class is
   recorded JSON, not a live-registry dependency.
6. Keep PR arm, dispatch hatch, calendar law, ROLE guards, b-suite and
   t12 byte-untouched under every option; "total_commits" stays unread.
7. Owner legs unchanged from EXPLORE §8 (dead-at-0s re-runs; build-failure
   logs) — the pilot is a new, cheap owner leg on top.

## 9. Open questions

1. Owner ruling O1-vs-O2-vs-O3-now (the ranking table is the brief).
2. Bootstrap: one-time unlabeled full publish vs adopt-on-next-change?
3. Is `[]` after a verified sweep silent (info) or still warned? (warn-law
   restatement, t14 scope)
4. Dual-registry truth side: accept the build's proposal (both, union)?
5. Does the owner want the cron resync, or widened push trigger, or both —
   run-list noise vs guarantee cadence.
6. Forgejo-backport check for the Gitea paths fix (one API probe + issue
   text — ready to draft).

## 10. Adjacent (short, out of core scope)

- **Base drift under unchanged trees**: the sweep compares SOURCE content,
  so a re-tagged upstream base image (same tree, different base digest)
  stays unpublished-until-renovate-touches. The fleet closes this BY
  CONVENTION, not by the loop: Dockerfile pins are digests/sha-ARGs
  (vllm-radiance's tag+digest law; forgejo-runner's `*_SHA256` ARGs), and
  a Renovate re-pin edits the Dockerfile — which changes the tree, so the
  sweep fires. Consider recording the resolved base digest in the stamp
  set only if the owner ever relaxes pinning [26].
- The Nov-24 build-stage failures (ticket class C) are delivery-loss
  generators in slow motion — any option that makes detection self-heal
  ALSO silently papers them (drift re-builds every wake until the daemon
  bug is fixed). Keep them their own ticket; the sweep's first full run
  will flood a fragile dind fleet if the build-leg bug is live — sequence
  the daemon fix BEFORE switching detection.
- Forgejo may eventually gain first-class changed-file outputs per job
  (the docs describe server-side filters [31]); if so, O2/O1 both shrink —
  watch, don't wait.

## 11. Sources (numbered; storm trail in `storm-runs/…` on the session host)

[1] docs.github.com/en/webhooks/webhook-events-and-payloads — push `before`/`after`. PROVEN
[2] docs.github.com/en/actions/using-workflows/events-that-trigger-workflows — push→tip GITHUB_SHA; batch limits. PROVEN
[3] github.com/dorny/paths-filter/issues/314 — #314 failure-mode answer + "last successfully deployed" prescription (community commenter, not the author). PROVEN (quote, attribution noted)
[4] docs.gitea.com/usage/repository/webhooks/ — push payload fields. PROVEN
[5] forgejo.org/docs/latest/user/actions/reference/ — FORGEJO_EVENT_PATH; run_attempt; schedule events. PROVEN
[6] docs.github.com/…/re-run-workflows-and-jobs — same GITHUB_SHA/REF on re-run. PROVEN
[7] raw.githubusercontent.com/nrwl/nx-set-shas/main/README.md — Problem statement; v1 tags / v2 CI-API. PROVEN
[8] github.com/tj-actions/changed-files/issues/2935 — interior-merge push range; 477,742 vs 156. PROVEN
[9] github.com/opencontainers/image-spec/…/annotations.md — revision key; reserved/custom namespaces. PROVEN
[10] git-scm.com/docs/gitrevisions — `<rev>:<path>` names the tree. PROVEN
[11] distribution.github.io/distribution/spec/api/ — tags/list; manifests; blobs. PROVEN
[12] argocd-image-updater.readthedocs.io/…/update-strategies/ — registry-truth strategies; mutable-tag caveat. PROVEN
[13] docs.docker.com/reference/cli/docker/image/build/ — `--label`. PROVEN
[14] docs.docker.com/build/metadata/attestations/ — index-only; classic-store exclusion. PROVEN
[15] docs.docker.com/build/metadata/attestations/slsa-provenance/ — version-control metadata in provenance. CONTEXT
[16] docs.github.com/…/working-with-the-container-registry — public images anonymous. PROVEN
[17] medium.com/hackernoon/level-triggering-and-reconciliation-in-kubernetes — level vs edge canon. PROVEN-secondary
[18] github.com/orgs/community/discussions/49671 — ghcr pull limits, unresolved. CONTEXT
[19] blogops.mixinet.net/posts/forgejo/configuring_forgejo_actions/ — tag-driven per-folder builds on Forgejo Actions. PROVEN
[20] forgejo.mixinet.net/api/v1/repos/oci/images — the repo behind it. PROVEN
[21] nexveridian.com/blog/forgejo-pushing-container-images — dind push caveats, skopeo. CONTEXT
[22] corgea.com/research/gitea-forgejo-private-container-registry-bypass — CVE-2026-27771. CONTEXT (security footnote)
[23] containrrr.dev/watchtower/ — digest-compare reconcile loop. PROVEN
[24] forgejo.org/docs/latest/user/packages/container/ — registry auth surface. PROVEN
[25] blog.gntech.me/posts/2026-06-01-renovate-bot-automated-docker-updates-homelab/ — Renovate digest-drift practice. CONTEXT
[26] containers.codeguides.io/…/base-image-pinning-by-digest/ — digest=content identity; scheduled rebuilds. CONTEXT
[27] containers.codeguides.io/kubernetes-internals/the-reconciliation-loop-explained — missed events delay, never break. PROVEN-secondary
[28] git-scm.com/docs/git-merge-base — is-ancestor idiom; fork-point reflog caveat + gc expiry. PROVEN
[29] docs.gitlab.com/ci/variables/predefined_variables/ — CI_COMMIT_BEFORE_SHA sentinel shapes. PROVEN
[30] raw.githubusercontent.com/dorny/paths-filter/master/README.md — push mode anchors on pre-push tip. PROVEN
[31] forgejo.org/docs/latest/user/actions/ — paths filter semantics (server-side). PROVEN
[32] codeberg.org/forgejo/forgejo/issues/12739 — server-side PR changed-files at merge. PROVEN
[33] github.com/go-gitea/gitea/issues/34710 — paths filters incorrectly trigger during rebase (type/bug). PROVEN
[34] github.com/go-gitea/gitea/pull/36045 — merged fix 2025-11-28 for pull_request.paths rebase over-trigger. PROVEN
[35] docs.github.com/…/about-pull-request-merges — merge/squash/rebase-merge history shapes. PROVEN
(Ticket-local primary evidence, cited in-text: EXPLORE.md §2–§5 (live payloads/reproductions), `.forgejo/workflows/containers-build.yaml` + `scripts/forgejo-container-detect.sh` at main tip, AGENTS.md calendar/payload laws, containers/vllm-radiance-mxfp4 README (config-blob label read precedent).)
