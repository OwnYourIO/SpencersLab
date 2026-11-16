# EXPLORE — cf-6 run -1: ROLE-split container builds (card 6 rework)

Written by `agent-explore` 2026-11-10 (workspace clock), read-only scouting for the
run -1 planner. Predecessor: `…/2026-11-cf-6-feat-forgejo-container-builds/EXPLORE.md`
(run 0, §1–§11) — still accurate on GitHub-precedent mechanics (§1), `containers/`
inventory (§2), Actions syntax basics (§4), tag-scheme history (§6) and build
mechanics (§7); **its §3 topology is now STALE** (dev instance recovered) and its
§5 "no cluster registry exists" is **superseded by the owner's rework ask** (the
Forgejo package registry is live on both instances — §3 below).

Request under exploration = the owner's rework comment on card 6, `dev-boards` board
`TNQJ2BrXenZovngTS`, card `7dAgENe75dBt2FZY6`, comment `cNNkCZkBHHm2ESf87` (read live
2026-11-10). Verbatim key lines: NOTE 1 keep `.github/workflows/docker-build.yaml`'s
`on.push`/`on.pull_request` blocks **in the file, commented out**; NOTE 2 split
`.forgejo/workflows/containers-build.yaml` triggers **by ROLE, not instance URL** —
push-to-main ∧ ROLE∋prod → versioned push to **both** `ghcr.io/ownyourio` **and** the
local Forgejo registry; pull_request ∧ ROLE∋dev → **local Forgejo registry only**;
NOTE 3 job guards become ROLE-based, "NO direct URL references anywhere in the
workflows"; ROLE SEMANTICS: "ROLE is a list including dev and/or prod. If ROLE is
unset it DEFAULTS to dev,prod — the single-server case… an unset ROLE must produce the
widest behaviour rather than disabling the pipeline"; SCOPE RULING: the same ROLE
convention applies to the **existing** `.forgejo/workflows/*` **in this same run**.

## 0. Headlines the planner must not walk into (each proven below)

1. **The ROLE convention already exists and is already live in this repo** — `main`
   carries a ROLE-based `main-sync.yaml` whose **both** push jobs are guarded
   `if: vars.ROLE == 'prod'` (ROLE is an *instance selector*; the per-destination difference
   comes from instance-side `vars.PUSH_URL_{GH,DEV}` + `secrets.PUSH_TOKEN_{GH,DEV}`, and
   the file has zero URL literals). The infra instance has executed those guarded jobs in
   **15/15 runs** since the commit that introduced the guard, so `vars` resolves in job
   `if:` and `ROLE=prod` there is now observed, not assumed (§2). Two cautions that come
   with it: the false branch has **never been observed** on this instance, and the
   convention's live record is 6 green / 9 runs with a failing push job (§2). Its
   "unset = nothing fires (fail-safe)" header also **contradicts the owner's new
   "unset = widest"** ruling (§2.4, §Open questions 2).
2. **This branch is 9 ahead / 50 behind `main`**, and `main` already contains the
   sweep target: `.forgejo/workflows/main-sync.yaml` in its ROLE form. After the
   rebase, the only URL-guarded workflow left in the repo is cf-6's own
   `containers-build.yaml` (§1.3, §5-collisions).
3. **The local registry is enabled and reachable on both instances right now**
   (`/v2/` → 401 + `Docker-Distribution-Api-Version: registry/2.0`), and its
   absent-package status codes differ from GHCR's (§3, §4).
4. **The dev instance is healthy again** (server 1/1, runner 2/2, both ~30 h old) but
   **has executed zero workflow tasks ever** (§6) — so `ROLE∋dev` is testable in
   principle, untested in fact.
5. **No calendar tag exists yet on ghcr** (probed: no `26.11.*` on three images) — the
   run-0 pipeline has never fired, so run -1 changes an un-shipped scheme, not a
   live one (§4.5).

## 1. `.forgejo/workflows/*` inventory — the sweep surface

### 1.1 Files on this branch (the run -1 base)

`find .forgejo -type f` at HEAD `2f5d8efad` returns exactly two files (no other
workflow dir exists: `find -maxdepth 3 -name workflows` → `.forgejo/workflows`,
`.github/workflows`; no `.gitea/workflows`, nothing else under `.forgejo/`):

| File | Trigger block | Job guards (exact strings) | Hardcoded hosts |
|---|---|---|---|
| `.forgejo/workflows/containers-build.yaml` (210 L) | `on:` L28-44: `push.branches [main]` + `paths ['containers/**']` (L29-31), `pull_request` same (L32-34), `workflow_dispatch.inputs.containers` string default `''` (L38-44); top-level `concurrency.cancel-in-progress: false` L46-47 | L51 `startsWith(forgejo.server_url, 'https://git.spencerslab.com')` (`detect-changes`); L87 same string `&& needs.detect-changes.outputs.changed-containers != '[]'` (`build-and-push`) | the infra URL twice (L51, L87); diag steps echo `forgejo.server_url` L64, L102 |
| `.forgejo/workflows/main-sync.yaml` (80 L, **run-0-era v1**) | `on:` L24-27: `push.branches [main]`, `workflow_dispatch {}` | L31 `startsWith(forgejo.server_url, 'https://git.spencerslab.com')` (`push-main`); L53 `startsWith(forgejo.server_url, 'https://git.scifi.farm')` (`backup-proxy-merge`) | L31 + L53 guards **and** destination URL literals: L46 `…@github.com/OwnYourIO/SpencersLab.git`, L50 `…@git.scifi.farm/CuratedForest/SpencersLab.git`; diag echoes L41, L63 |

Repo-wide grep for `server_url|startsWith` outside plan/vendored dirs hits only those
four guard lines + the diag echoes + `tests/services/forgejo-containers-build.sh`
(guard const L174, counts L194-197); `charts/zigbee2mqtt` and `services/home` hits are
unrelated Jinja `server_url` names.

### 1.2 Files on `main` (what the sweep chunk is really sweeping after a rebase)

`git ls-tree -r --name-only main -- .forgejo` → **only `main-sync.yaml`**, and it is
already ROLE-shaped (`git show main:.forgejo/workflows/main-sync.yaml`, from commit
`b482935ed fix(cf-119): rework main-sync workflow and contract suite per approved
fixes`): header L1-16 states the ROLE rationale *and* "An unset ROLE renders empty and
fires nothing too (fail-safe)"; `on:` L18-21 (`push` main + `workflow_dispatch`);
jobs `push-gh` L24 and `push-dev` L45 both `if: vars.ROLE == 'prod'` (L25, L46); diag
`echo "ROLE=${{ vars.ROLE }}"` (L35, L56); destinations/credentials from instance-side
`vars.PUSH_URL_GH`/`vars.PUSH_URL_DEV` + `secrets.PUSH_TOKEN_GH`/`secrets.PUSH_TOKEN_DEV`
(L38-39, L59-60) with `rest="${PUSH_URL#https://}"` then a plain push (L42-43, L63-64).
**Zero URL literals in the file** — that is the shipped form of the owner's NOTE 3.

### 1.3 Consequences for the sweep chunk

- After rebasing run -1 onto `main`, the sweep's remaining URL-guard inventory is
  **one file**: `containers-build.yaml` L51/L87 (+ its diag echoes). `main-sync.yaml`
  arrives already converted; re-converting it is a no-op and the v1 text on this
  branch must not be re-applied over main's v2 (the merge is clean today:
  `git merge-tree --write-tree main HEAD` conflicts in exactly one path —
  `.agents/plans/2026/2026-11-cf-6-feat-forgejo-container-builds/DECISIONS.md`,
  add/add, because main carries a 49-line stale copy of run 0's DECISIONS while the
  branch carries the full 166-line one; `.rulesync/rules/overview.md`, `AGENTS.md` and
  `tests/pipeline-models/surface.sh` auto-merge).
- Owner's NOTE 3 "NO direct URL references anywhere in the workflows" is **already
  satisfied** by main's main-sync; `containers-build.yaml` still carries two
  (`forgejo.server_url`-derived, not destination URLs) plus `ghcr.io` literals
  (L119, L133, L145) — the planner must decide whether `ghcr.io`/the forge registry
  host count as "direct URL references" (main's precedent puts *destination* hosts in
  `vars.*`, and its t5 leg bans any `https://` repo-URL literal in the file:
  `git show main:tests/services/forgejo-main-sync.sh` L144-148).

## 2. Where a ROLE value can live, ranked by what THIS instance supports

Docs basis (v15.0 line = the deployed `15.0.10+gitea-1.22.0`, §8.4): Forgejo's own
`docs/user/actions/basic-concepts.md` and `docs/user/actions/reference.md`, fetched raw
from `codeberg.org/forgejo/docs` branch `v15.0` (saved at `/tmp/opencode/`), plus
Forgejo's upstream conformance workflow `code.forgejo.org/forgejo/end-to-end/raw/branch/main/actions/example-expression/.forgejo/workflows/test.yml`.

**Rank 1 — repository variable `vars.ROLE` (live-proven in this lab).**
- Referencing: `${{ vars.ROLE }}` for text; **`vars` is a documented accessible context
  for `jobs.<job-id>.if`** (reference.md Availability table L1205:
  `env, forgejo, inputs, needs, secrets, vars`) and for `steps[*].if` (L1221), step/run
  `env` (L1220), workflow `env` (L1192), `concurrency` (L1191), `jobs.<id>.name`
  (L1206). Contexts table: `vars | variables available in the repository` (L1173).
- Scopes: `/org/{org}/settings/actions/variables`, `/user/settings/actions/variables`,
  `/{owner}/{repo}/settings/actions/variables` (basic-concepts L131-133). **No
  instance-global variable scope is documented for v15.0.** Precedence: an
  owner(org/user)-level variable **beats** the repo-level one (L155) — so an org-level
  `ROLE` on `CuratedForest` silently outranks a repo-level one.
- Name rules (L146-152): `[A-Za-z0-9_]` only, **must not start with `FORGEJO_`,
  `GITHUB_` or `GITEA_`**, must not start with a digit, **case-insensitive names**,
  must not be `CI`. `ROLE` legal; `GHCR_PUSH_PAT` legal (cf-119's rework applied the
  same rule to secret names: DECISIONS 2026-11-09 fix 3).
- In a `run:` step: pass it through `env:` (`env: ROLE: ${{ vars.ROLE }}`, allowed by
  L1192/L1202) and read `$ROLE`, or interpolate directly (the file's existing pattern,
  e.g. `containers-build.yaml:64`). `env:ROLE: ${{ vars.ROLE }}` with the variable
  unset yields an **empty** `$ROLE` → shell-side default expansion
  (`ROLE=${ROLE:-dev,prod}`) is the one widening mechanism whose semantics are
  pure-bash, no expression engine involved.
- **Live proof in this lab (recounted from the full task history, not one run).** `GET
  https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/actions/tasks`
  (anonymous 200, 66 tasks) contains **15 runs of the ROLE-era file — run numbers 18-32**
  (10 `event: push` + 5 `workflow_dispatch`), from `b482935ed` at 2026-11-09T15:51:22Z (23 s
  after that commit's 15:50:59Z author date; it is the commit that introduced `vars.ROLE`:
  `git log --format='%h %ad %s' main -- .forgejo/workflows/main-sync.yaml`) through
  `a6e493b78` at 2026-11-10T20:34:32Z — and in **15/15 both** guarded jobs (`push-gh`,
  `push-dev`) *executed*: neither ever came back `skipped`. So `vars.ROLE == 'prod'`
  evaluated **true** on the infra instance every time ⇒ **`vars.ROLE` really is `prod`
  there** (cf-119 UA3's claim, now observed, not assumed) and **`vars` resolves inside a
  job-level `if:`** on 15.0.10.
- **What has *not* been observed here: a `vars` guard actually blocking.** There is no
  negative case on this instance (infra's ROLE is `prod`, so both guards are always true;
  the dev instance has never executed anything — §6). The only job-level `if:` skips in the
  whole history are **18 × `backup-proxy-merge`**, and those come from the *pre-ROLE* file's
  `startsWith(forgejo.server_url, …)` guards (`git show ea9e97f64:.forgejo/workflows/main-sync.yaml`
  L31/L53 — the job is gone from main's v2, which is why ROLE-era runs list only the two
  push jobs). Conclusion for the plan: the false-guard → `skipped` reporting path works, and
  `vars` guards demonstrably *pass*; a demonstrably *blocking* `vars` guard is still an
  open item (§Open questions 1, "Sharpener").
- **Track record of the shipped convention (fact, not interpretation).** Those 15 ROLE-era
  runs: 6 fully green; `push-gh` failed in 7, `push-dev` in 5 (the three runs at
  15:51/15:53/15:54 failed both jobs; 11-10 15:28/15:37/15:38 each failed `push-gh` while
  `push-dev` succeeded; the newest run, 20:34, is `push-gh` success + `push-dev` failure).
  This is git-push fan-in, not container pushing — but it is the live instability on record
  for the ROLE convention the owner is asking to extend.
- Owner-side state to confirm-or-set: infra repo per cf-119 UA3 already lists
  `ROLE=prod` + `PUSH_URL_GH` + `PUSH_URL_DEV` + the two `PUSH_TOKEN_*`
  (`main:.agents/plans/2026/2026-11-cf-119-feat-forgejo-push-main/2026-11-06-cf-119-feat-forgejo-push-main.md:285-294`);
  **the dev repo's `ROLE=dev` value is UNVERIFIED** (nothing has ever run there to
  reveal it — §6; unset and `dev` are indistinguishable from outside).

**Rank 2 — secrets (`secrets.ROLE`).** Available in `jobs.<id>.if` too (reference.md
L1205), same scopes as variables. Costs: masked-in-logs semantics make a mis-set role
invisible in a diag echo (cf. the ROLE diag step main-sync L35/L56, which is exactly
how cf-119 made the value readable), and a secret is the wrong store for a routing
fact. cf-119 fix 3 rules apply to key names.

**Rank 3 — workflow-level `env:` block.** `env` accepts `vars` and is readable as
`env.KEY` in job `if:` (reference.md L1192 + L1205; upstream conformance file proves
`if: env.KEY1 == 'value1'` works). But an `env:` value lives **in the file**, so both
instances render the identical value: cf-119 rejected it for precisely this reason
(DECISIONS 2026-11-09, "a file literal — identical on both instances, so it cannot
differ per server"). It can serve as a *default* layer, never as the discriminator.

**Rank 4 — a committed file (e.g. `.forgejo/ROLE`).** Same objection, plus it is not
readable in `if:` at all without an extra job+output hop. Both instances serve the same
repo content, so it cannot distinguish them.

**List-membership in `if:` — what the engine supports.**
- Functions documented as usable "in expressions" (basic-concepts L90-101):
  `contains(search, item)` — array membership *and* substring, **case-insensitive**,
  casts to string (L94); `startsWith`/`endsWith` (L95-96); `format(str, …)` (L97);
  `join` (L98); `toJSON`/`fromJSON` (L99-100); `hashFiles` (L101, runner/Node only).
  Operators (L59-74): `( ) ! < <= > >= == != && ||`; **"String comparisons are case
  insensitive"** (NOTE ~L76). Casting table: `null` → `''` (L107).
- Upstream conformance proof (the end-to-end `example-expression` workflow, run in
  Forgejo's own CI): `contains('zeroonetwo','one')` → true,
  **`contains(fromJSON('["one","two"]'), 'one')` → true**, `contains(…, 'notfound')` →
  false, `fromJSON('[…]')[0]` indexing, `format('{0} and {1}',…)`, `join`, case-insensitive
  `'something' == 'SOMETHING'` → true, and `env.NULL == null` → true.
- **UNVERIFIED on 15.0.10 in this lab**: that `contains()`/`fromJSON()` evaluate inside a
  **job-level** `if:` (the conformance file exercises them in step `if:`/`${{ }}`
  interpolation; job-`if:` is evaluated by the *server*, not the runner). The
  Availability table (reference.md L1205) lists accessible **contexts** for `jobs.<id>.if`
  and enumerates `always`/`cancelled`/`failure`/`success` as its accessible-functions
  column; it does not say `contains`/`fromJSON` are excluded, and it does not say they
  are included. Nothing in this repo has ever used a function in a job `if:` on this
  instance. The two halves of the problem have each been observed **separately**, never
  together: `startsWith(forgejo.server_url, …)` is the only guard ever seen to **block** a
  job here (the 18 `backup-proxy-merge` skips, pre-ROLE file), and `vars.ROLE == …` is the
  only `vars` guard ever run — which only ever **passed** (15/15 runs, above). No live
  evidence exists on this instance for a `vars`-based guard taking its false branch, let
  alone one using `contains`/`fromJSON`.
- **`on:` cannot be role-split.** reference.md's Availability table has **no row for
  `on.push.*`/`on.pull_request.*`** — the only `on.` rows are
  `on.workflow_call.inputs.<id>.default` and `on.workflow_call.outputs.<id>.value`
  (~L1233-1234); the `### on` section (L47-66) documents no expression evaluation. So
  NOTE 2's "split the triggers by ROLE" can only be realized as **event triggers that
  stay as-is + ROLE-membership `if:` on the jobs/steps** (or a job-level `if:` on the
  event name too), never as `on.push.if:`-style filtering. Corollary the planner
  should note: `concurrency` **can** reference `vars` (L1191), so role-scoped
  concurrency groups are on the table.

### 2.4 The unset case, per mechanism (the owner's hard requirement)

| Mechanism | What unset evaluates to | Widest-on-unset? |
|---|---|---|
| `if: vars.ROLE == 'prod'` (shipped main-sync shape) | guard false → job status **`skipped`** (proved live: v1 `backup-proxy-merge`); cf-119 documents it as fail-safe: main-sync header L5-6, plan L152, DECISIONS "unset `STAGE` → `''` → no fire" | **No — narrowest.** Directly opposite the owner's NOTE for ROLE. |
| `if: contains(vars.ROLE, 'prod')` (substring on the raw list) | `contains('', 'prod')` → false | **No**, unless the file pre-defaults ROLE (impossible in `if:` without a null/empty test). |
| `if: vars.ROLE == null \|\| contains(fromJSON(vars.ROLE_JSON), 'prod')` (or `vars.ROLE == ''`) | Docs are **silent** on unset `vars` (no "unset"/"not set" statement anywhere in reference.md/basic-concepts.md); cast table says `null` → `''` (L107) and the conformance file proves a **missing context key compares equal to `null`** (`env.NULL == null` → true). Whether `vars.ROLE == ''` and whether `||` short-circuits on an empty string in the **server-side job-`if:`** evaluator: **UNVERIFIED** | Depends on unverified evaluation; **function support in job `if:` also unverified** |
| `env: ROLE: ${{ vars.ROLE }}` + shell `ROLE=${ROLE:-dev,prod}` + a `case ",$ROLE," in *,prod,*)` gate inside the step | unset → empty string → shell default → `dev,prod`; membership is bash string logic (fully deterministic) | **Yes, without any expression-engine dependency** — but the job still has to *start*, so it only widens *what the job does*, not *whether it runs* |
| instance/org-level `vars.ROLE` | same as repo var, and org scope silently wins (L155) | same polarity as whatever the file tests |

Best available facts for the planner: the only *proven* job-`if:` constructs on this
instance are `==`/`startsWith` on `forgejo.*`/`vars.*`; everything list-shaped
(`contains`, `fromJSON`, `||`-with-null) is docs-supported but instance-unverified, and
a one-line `workflow_dispatch` probe workflow is the cheap way to settle it (the infra
instance has run 14 dispatch jobs already — dispatch works).

## 3. The local Forgejo container registry — live state

- **Enabled on both instances, today.** `GET https://git.spencerslab.com/v2/` →
  `401` + `docker-distribution-api-version: registry/2.0` +
  `www-authenticate: Bearer realm="https://git.spencerslab.com/v2/token",service="container_registry"`;
  identical shape on `https://git.scifi.farm/v2/` (probed 2026-11-10). Config default
  matches: `[packages] ENABLED: **true**` (v15.0 config-cheat-sheet §Packages L1291-1296)
  and `repo.packages` is in `DEFAULT_REPO_UNITS` with empty `DISABLED_REPO_UNITS`
  (same doc L94-95). **No package has ever been published to either instance**
  (infra org packages page `200` with no rows; dev has run nothing) — so every
  push-path claim below is spec-level, not observed.
- **Real endpoint/hostname.** Registry host = the instance web host (docs
  `user/packages/container.md`: naming `{registry}/{owner}/{image}`, "your registry is
  the domain of your forgejo instance"). Infra: `git.spencerslab.com` (Ingress
  `git-ingress`, class `traefik`, TLS, `/` Prefix → Service `infra-forgejo-http:3000`;
  the alias host `forgejo.spencerslab.com` routes to the same service via
  `forgejo-ingress` and is banned for machine use per cf-104 R3). Dev:
  `git.scifi.farm` (Ingress `git-ingress` → Service `dev-forgejo-http:3000`). In-cluster
  alternates (`infra-forgejo-http:3000`, `dev-forgejo-http:3000`, both ClusterIP port
  3000) are **plain HTTP**, so a docker/dind push through them needs an
  `insecure-registries` daemon setting — **no `insecure`/daemon-args config exists in
  `charts/forgejo-runner`** (grep: only the `docker:29.9.2-dind` sidecar + socket/gid
  contract, values.yaml L13-25, L158-217, L263-269). The HTTPS host is the viable push
  target from jobs.
- **Name/namespace form**: `git.spencerslab.com/<owner>/<image>:<tag>` where `<owner>`
  is a **user or org, never a repository** (`user/packages/index.md` "A package always
  belongs to an owner (a user or organisation), not a repository"); write access = "owner
  only" / "org members with admin or write access to the org" (same doc, Access
  Restrictions table). So a runner pushing `…/CuratedForest/<img>` acts as an identity
  with write into that org namespace; nesting (`/<owner>/<repo>/<img>`) and
  `LABEL org.opencontainers.image.source=` auto-linking are documented
  (`container.md` "Linking an image to a repository").
- **Auth from Actions — UNVERIFIED which credential works.** Options, with what the
  sources actually say:
  1. `secrets.FORGEJO_TOKEN` / `forgejo.token` (the automatic per-run token): docs say
     it can "read the repositories associated with the workflow", "has write permission
     to the repository and can be used to push commits or use API endpoints", is
     **repository-scoped** ("only … interactions with the repository of the project, any
     attempt to use it on other repositories … returns 404"), and **never re-triggers
     workflows** (basic-concepts L157-176). Nothing documents package/registry push, and
     packages are owner-scoped, not repo-scoped — so "works for package push" is a
     reasonable hope, **not a documented capability**. Owner-leg test (run on a job or
     from a workstation with a throwaway package):
     `docker login git.spencerslab.com -u <actor> --password-stdin <<< "$FORGEJO_TOKEN"`
     then `docker push git.spencerslab.com/<owner>/probe:0`.
  2. A **user PAT as an Actions secret** — the documented path (`container.md`: "If you
     are using 2FA or OAuth use a personal access token instead of the password");
     matches the shipped cf-119 shape (`PUSH_TOKEN_*` secrets in the infra repo) and the
     existing vault item `forgejo-token` (cf-119 DECISIONS 2026-11-09 OQ-5). Note the
     dev-side and infra-side PATs are different instances → different credentials.
- **Anonymous pull**: no instance-wide anonymous-package switch exists in v15.0
  (`grep -i anonymous docs/admin/config-cheat-sheet.md` → only `server.SSH_EXPOSE_ANONYMOUS`);
  read access is "public if the owning org/user is public, otherwise members/owner",
  and `service.REQUIRE_SIGNIN_VIEW` can gate everything (`user/packages/index.md`
  Access Restrictions; `REQUIRE_SIGNIN_VIEW` is set nowhere in this repo's chart/values
  — only `DISABLE_REGISTRATION: false` at `charts/forgejo/values.yaml:104`).
  Measurements: the token endpoint mints an **anonymous, zero-scope token** (`GET
  /v2/token?scope=repository:CuratedForest/<x>:pull` → 200, JWT payload `{"UserID":-1,"Scope":""}`),
  an unauthenticated `GET /v2/<name>/tags/list` → **401**, and `https://git.spencerslab.com/orgs/CuratedForest`
  → **404** (org page not publicly listed) → whether anonymous pull works for a
  `CuratedForest/…` image is **UNVERIFIED** and decides whether the cluster needs
  pull secrets if consumers ever move onto the forge registry.
- **No catalog enumeration on either instance** (measured): `GET /v2/_catalog` returns
  `UNAUTHORIZED` with the challenge carrying `scope="*"` on both hosts. Consequence the
  planner should keep: the detector cannot discover forge-side images by listing the
  registry — like the shipped ghcr logic, it has to ask per image name
  (`tags/list` / `HEAD manifest`), §4.
- **Storage / quota facts that touch the `pr-*` and `:latest` plan.** Defaults are
  unlimited: `LIMIT_TOTAL_OWNER_COUNT: -1`, `LIMIT_TOTAL_OWNER_SIZE: -1`,
  `LIMIT_SIZE_CONTAINER: -1` (cheat-sheet L1293-1300) — *unless the lab sets them in
  app.ini*, which is not readable from a readonly session (Secrets are forbidden to the
  readonly SA; UNVERIFIED). Owner-leg read of the rendered config:
  `kubectl -n default get secret -l app.kubernetes.io/instance=infra-forgejo` then
  `kubectl -n default get secret <that-name> -o jsonpath='{.data.app\.ini}' | base64 -d | sed -n '/\[packages\]/,/^\[/p'`.
  Package storage location: `[packages]` "Additional settings … where the data is
  stored" (cheat-sheet L1320) → **default = the instance's `APP_DATA_PATH` PVC**, not
  S3: this repo deliberately keeps LFS-only S3 and warns that a `[storage]` section
  "would … move attachments, avatars and **packages** to S3"
  (`charts/forgejo/values.yaml:90-100`); no `[storage]`/`[packages]` storage keys are
  set in `services/{infra,dev}/prod/values.yaml` (grep). So every pushed layer lands on
  the forge PVC.
  Retention: `cron.cleanup_packages` (ENABLED **true**, `@midnight`, `OLDER_THAN: 24h`)
  deletes **unreferenced** package data only (cheat-sheet L984-989) — it is not a
  tag-deletion policy, and there is no `[packages]` retention/cleanup-rule key in v15.0
  (grep: none). Version deletion is a human UI action, whole-package, "permanently
  delete" (`user/packages/index.md` "Delete a package"); the same doc says "You cannot
  edit a package after you have published it" — GHCR-style silent tag *overwrite*
  behaviour on Forgejo is **UNVERIFIED** (run 0 RESEARCH D established overwrite for
  GHCR only). Traefik adds no body-size limit on that path: `git-ingress` carries only
  the `argocd.argoproj.io/tracking-id` annotation, and no
  `MaxRequestBodySize`/`Buffering` middleware exists anywhere in `charts/`/`services/`
  (grep) — the k3s MTU caveat of run 0 §7 still applies to big layer pushes.

## 4. Can `yy.mm.N` still be registry-derived once two registries exist? (facts)

1. **Today N is derived from ghcr only.** `containers-build.yaml:133`
   `api="https://ghcr.io/v2/ownyourio/<container>"`; L145 token
   `https://ghcr.io/token?scope=repository:ownyourio/<container>:pull`; L158
   `GET $api/tags/list` under that token; L161 pipes the body to
   `scripts/forgejo-container-detect.sh next-n`; L162-187 HEADs
   `$api/manifests/<tag>` under the same token and advances while not 404 (fatal on any
   other code, capped at 50). The forge registry is never consulted.
2. **`next-n` is registry-agnostic text math**: stdin a `tags/list` JSON body, env
   `YYMM`; keeps only `^<yy\.mm>\.[0-9]+$` entries and returns max+1, `1` when none
   (`scripts/forgejo-container-detect.sh:68-91`). `pr-*`, `latest`, `main`, `v162` and
   foreign months are ignored, so **`pr-*` tags cannot corrupt N** regardless of which
   registry is read. Whether Forgejo's `tags/list` body is byte-compatible with the sed
   extraction (`{"name":…,"tags":[…]}`, one compact line) is **UNVERIFIED** — no
   package exists to read (measured `404 NAME_UNKNOWN`), though both are OCI
   implementations.
3. **Status-code shapes differ between the two registries** (measured 2026-11-10):
   GHCR → token endpoint **403 DENIED** for a never-pushed image, anonymous manifest
   HEAD **401**, walk only meaningful under a pull token (run 0 C01 review round-2).
   Forgejo → token endpoint **200 with a zero-scope token**, `tags/list` for an absent
   repo **404 `NAME_UNKNOWN`**, manifest HEAD **404**. Load-bearing detail: the shipped
   step *tolerates* 401/403/404 on `tags/list` (L188-191) and **only walks inside the
   `list_code = 200` branch** (L160-187, pinned by leg t11 at
   `tests/services/forgejo-containers-build.sh:611-619`) — so a per-registry read of a
   registry that answers 404 for "no such package" computes `n=1` and **never runs the
   existence walk** (correct for a true first publish; it also means a forge-side read
   gives no advance protection in the same edge cases where the ghcr read would).
4. **What "the two registries disagree" means concretely.** A single build produces one
   N today; if N is derived from registry A and both registries are pushed, then
   whenever B already holds that tag (B kept a tag A never got — e.g. a partial push
   after a mid-step failure, a dev-role run that only wrote B, a B-side manual delete,
   or a re-run where only one side advanced) the push to B overwrites whatever B's tag
   named, exactly the hazard D3's existence-advance exists to avoid — and conversely
   deriving from B can overwrite on A. Both registries are assumed fully mutable
   (GHCR proven, run 0 RESEARCH D; forge UNVERIFIED, §3), and neither exposes tag
   immutability. The walk is per-registry by construction, so the design space the
   planner has to choose in is: derive once and walk **both** before pushing either /
   derive per-registry (accepting divergent numbers for the same build) / derive from
   one and treat the other as a cache. Facts, no recommendation.
5. **Ordering context (unchanged but re-measured)**: no `26.11.*` tag exists on any of
   `ownyourio/traefik-mqtt-allowlist`, `wekan-mcp`, `strata` (anonymous tokened
   `tags/list`, 2026-11-10) → the run-0 pipeline has never minted a calendar release.
   Those images' real tag sets are `["0.0.1"…"0.0.12","latest","main","v87"]`,
   `["0.0.*","v24…v177","latest","main"]`, `["v93…v196","main"]`. The `0.0.N` line is
   **historical, not live**: image-config `created` timestamps are `2026-01-29`/`2026-01-30`
   for `0.0.1`/`0.0.12` vs `2026-10-25` for `v87`/`main` (last GitHub build). Note for
   the Renovate rule under the D3 `versioning: regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$`:
   `0.0.12` **is** rule-parseable (0.0.12 < 26.11.N so the calendar line still
   outranks), i.e. a legacy `0.0.x` pin would be a legal rule-matched pin — check
   whether any chart pins one before assuming "pins are only `v<run>`".

## 5. Pushing to ghcr from the forge runner (credential + reachability)

- Credential: the **Actions secret `GHCR_PUSH_PAT`** (owner's run-0 human legs #1-2,
  referenced once, in the login step, `containers-build.yaml:113-119`
  `printf '%s' '${{ secrets.GHCR_PUSH_PAT }}' | docker login ghcr.io -u OwnYourIO --password-stdin`),
  GitHub PAT `write:packages` on the `ownyourio` namespace, Bitwarden-backed, entered by
  the human on the **infra** instance. Nothing in the run -1 notes removes that leg,
  and NOTE 2 *adds* a second destination, so the push step becomes two logins + two
  pushes (or one build + two push loops). The forge-side push needs **its own**
  credential (§3) — there is currently no `FORGEJO_*`/registry secret in the repo's
  action surface (infra repo has `PUSH_TOKEN_GH`/`PUSH_TOKEN_DEV` per cf-119 UA3;
  `GHCR_PUSH_PAT` is still awaiting the owner).
- **Runner identity**: infra-instance jobs execute on the **gpu-cluster** runner —
  `gpu-forgejo-runner-gpu-0` log (2026-11-10T20:34:24Z): `task 65 repo is
  CuratedForest/SpencersLab https://data.forgejo.org https://git.spencerslab.com`,
  then `Cleaning up network for job push-gh` / `push-dev` (readonly-gpu-kubernetes
  `pods_log`). So the control-plane dial is `https://git.spencerslab.com` (public
  ingress) and every job egress goes through the gpu cluster's networking.
- **Egress facts measured/observed, job-level:**
  - `github.com` — **proven**: `push-gh` succeeded on runs 22, 24-28, 32 (tasks API),
    and `upstream/main` == `a6e493b78` == infra main (live `git ls-remote`).
  - `git.scifi.farm` over HTTPS — **proven**: `push-dev` succeeded on runs 24-28, 31
    and `dev` remote's `refs/heads/main` == `a6e493b78`. (Run 32's `push-dev`
    **failed in 5 s** — the most recent attempt; runs 29-31 had `push-gh` fail instead.
    Cause not readable: job logs are login-gated, §8.5.) This alternating
    failure pattern is current-state fact for any "prod fan-out works" assumption.
  - `ghcr.io` — proven **for pulls** (every job's own container image is a ghcr pull:
    the advertised labels map to `ghcr.io/catthehacker/ubuntu:act-24.04`/`act-22.04`,
    `charts/forgejo-runner/values.yaml:107-112`). **ghcr push has never been exercised
    from a forge runner** (no calendar tag exists, §4.5) → outbound 443 to ghcr.io
    *push* is UNVERIFIED.
  - `git.spencerslab.com` **from inside a job** (the new registry-push path) — the
    runner reaches the host for its own registration; a job's push to
    `git.spencerslab.com/v2/…` hairpins out through the Traefik ingress and back.
    No ingress middleware limits body size (§3). **UNVERIFIED until first push**; if
    it fails, the fallback candidates are the in-cluster service (needs
    insecure-registries, §3) or `network: host` per job (run 0 §7 k3s note).
- No pod exec was used or needed. If someone wants in-daemon facts later, the sanctioned
  shape is for the human to run it, e.g.
  `kubectl --context gpu -n default exec -it gpu-forgejo-runner-gpu-0 -c dind -- sh -c 'docker info -f "{{.RegistryConfig.Mirrors}} {{.HttpProxy}}"'`
  and, for the instance config, `kubectl --context infra -n default exec -it deploy/infra-forgejo -- sh -c 'cat /data/gitea/conf/app.ini'`
  (path per the forgejo chart's rootless layout — verify before running).

## 6. Runner capability for the dev role (is `ROLE∋dev` testable today?)

- **Run 0's §3 CrashLoopBackOff entries are stale.** Live pods list (readonly-dev-kubernetes,
  ns `default`, 2026-11-10): `dev-forgejo-c4ccf6fcb-2dbbk` **Running 1/1, Age 30 h,
  Restarts 0** (Forgejo `15.0.10`, chart `forgejo-17.3.1`) and
  `dev-forgejo-runner-dev-0` **Running 2/2, Age 30 h, Restarts 0**. Infra:
  `infra-forgejo-6b95547f88-psps8` Running 1/1, Age 30 h, 1 restart 8 h ago.
  `git ls-remote dev` (SSH `git.scifi.farm:22222`) also answers, corroborating a live
  server.
- **The dev runner is registered**: `dev-forgejo-runner-dev-0` container `runner` log:
  `runner: Dev Runner, with version: v13.2.0, with labels: [ubuntu-latest
  ubuntu-24.04 ubuntu-22.04 docker node22], ephemeral: false, declared successfully`
  (2026-11-09T15:16:10Z) + `[poller] launched`, then a single
  `failed to fetch task: deadline exceeded; increase fetch_timeout if this error is
  persistent` (15:44:16Z) and nothing since.
- **But nothing has ever executed there**: `GET
  https://git.scifi.farm/api/v1/repos/CuratedForest/SpencersLab/actions/tasks` →
  `{"workflow_runs":[]}` (anonymous 200), while the same call on
  `git.spencerslab.com` returns 66 tasks. Dev `main` == infra `main` == `a6e493b78`,
  i.e. the ROLE-guarded workflow file **is** on the dev instance, and pushes reached it
  after the runner came up — yet zero tasks. So: dev *server* + *runner pod* are healthy
  and the runner declared itself; **whether a `ROLE`-dev job would be picked up today is
  UNVERIFIED** (candidates: registration lost on the rebuild, the dev repo's Actions
  setting, the runner's `fetch_timeout` errors, or the fan-in push being authored in a
  way that doesn't fire workflows). Owner-leg checks: infra/dev UI
  `/{owner}/{repo}/settings/actions/runners`, and the dev repo's Actions settings.
- Consequence for the plan: `ROLE∋dev` behavior can be *authored* and offline-pinned,
  but a dev-role **live** validation depends on that unresolved pickup question; the
  only instance with a proven, executing runner today is **infra** (via the gpu
  runner), where the dev-role PR leg would also run if ROLE there includes `dev`.

## 7. Test + docs surfaces the rework must move

### 7.1 `tests/services/forgejo-containers-build.sh` (953 L, HEAD 2f5d8efad = **23 ok, exit 0** — re-run this session)

Legs that pin the **URL guard / trigger shape** and therefore change outright:
- **t2 triggers** (L130-167): parsed `on:` keys exactly
  `{push, pull_request, workflow_dispatch}`; `push.branches == ['main']`; both carry
  `containers/**` in `paths`; dispatch input `containers` string default `''`; no
  `branches` line naming `dev` (word-boundary scan L159-161).
- **t3 guard** (L169-203): `GUARD = "startsWith(forgejo.server_url, 'https://git.spencerslab.com')"`
  (L174) must appear in **both** jobs' `if` (L188-191), must occur exactly twice
  file-wide (L195), `git.scifi.farm` count == 0 (L194), and
  `https://git.spencerslab.com` count == exactly 2 (L196-197). Under NOTE 3 every one
  of these four assertions inverts (the URL must go, the guard must become a ROLE
  membership test) — the precedent to copy is main's `forgejo-main-sync.sh` t3 (L74
  `GUARD = "vars.ROLE == 'prod'"`, L86-88 exact `==`, L92 no `== 'dev'` job, L94 no
  `forgejo.server_url`) + t5 (L137-148: each `vars.PUSH_URL_*`/`secrets.PUSH_TOKEN_*`
  exactly once under its own job, no URL literal, no reserved-prefix key).
- **t8 tag arms** (L341-449): finds the PR/push arms via step `if:` on `pull_request`,
  a bash `if/elif` test, **or a `case` label** (L361-412), then asserts the PR arm has
  `pr-` and no `latest`/`main` token, the push arm has `latest` + `main` + `%y.%m`, and
  that `sanitize`/`next-n`/`rev-parse --short` are invoked. A ROLE split that moves the
  registry set per role makes this leg's "push arm ⇒ ghcr rolling+calendar" claim
  partial at best.
- **t9 hygiene** (L451-483): `runs-on` ∈ the five advertised labels, every `run:`
  starts `set -euo pipefail`, and a **diag step naming both `server_url` and `docker`**
  (L474-477) — the `server_url` half collides with NOTE 3 (main's diag echoes `ROLE`
  instead, `main:main-sync.yaml:35,56`).
- **t6/t7/t10/t11** (L272-339, L485-625) pin `uses ⊆ {actions/checkout@v6}`,
  `GHCR_PUSH_PAT` exactly once inside a login step + `GITHUB_TOKEN`/`FORGEJO_TOKEN`
  absent, the assign-then-emit detect shape, and the ghcr token/walk nesting; a
  second-registry login step hits t7's "exactly once" (its boundary-anchored regex,
  L327) and the registry-name assertions, so those need re-authoring, not tuning.
- **x2/x4** (L833-885, L912-922) pin the Renovate calendar rule
  (`matchDatasources == ['docker']`, versioning byte-verbatim, glob matches
  `ghcr.io/ownyourio/wekan-mcp`, rejects llama-swap/kubernetes-mcp-server) and the six
  sibling `.github/workflows` files; unaffected by ROLE per se, but x2's scope stays
  ghcr-only — a plan that also lets consumers pin the forge registry has to decide
  whether the rule widens.

### 7.2 The x1 `on:`-scoping subtlety vs NOTE 1's commented-out triggers

`x1` (L788-831) asserts the **parsed** `on:` key-set equals `{workflow_dispatch}` and
then greps **only inside the `on:` block** (`in_on` starts at the `on:` line, breaks on
the first zero-indent non-comment line L814-821) for a live `push:`/`pull_request:`
key. The scoping exists because `docker/build-push-action`'s **`push:` INPUT key** at
`.github/workflows/docker-build.yaml:139`
(`push: ${{ github.event_name != 'pull_request' }}`) is a permanent false-positive for
the plan-Commands verbatim `^[[:space:]]*(push|pull_request):` — I measured it: that raw
grep hits **line 139 today**.

I replayed x1's exact logic against two spliced copies of the real file (scratch
files, repo untouched):
- Fully commented block inside `on:` (`  # push:` + commented children):
  YAML parses, parsed `on:` == `{workflow_dispatch}`, scoped grep clean →
  **x1 stays GREEN**. So x1 as written **cannot tell "removed" from "commented out"** —
  if the owner wants NOTE 1's re-enable-by-uncomment affordance *pinned*, a new leg
  must positively assert the commented `push:`/`pull_request:` text is present **and**
  inert (e.g. a comment-aware regex on the `on:` block region), and it must keep
  ignoring L139.
- Commented parent with **live children** (`  # push:` then `    branches: [main]`):
  `yaml.safe_load` raises `ParserError: while parsing a block mapping` → t1/x1 go red on
  parse. That partial-comment shape is the real hazard, and it is caught by the parse
  legs, not by the grep.
Note also main's GitHub file (unaffected by cf-6 until merge) still has PR-path
remnants the sweep may want to comment consistently: `BASE_SHA`/`HEAD_SHA` envs L39-40,
PR diff arm L51-52, `if: github.event_name != 'pull_request'` L98, PR branch in the tag
step L116, and the `push:` input L139 (run 0's C02 review explicitly fenced L139).

### 7.3 Docs lines that re-pin under ROLE semantics

On this branch (the C02 re-pin, which the sweep re-does):
`.rulesync/rules/overview.md:21` (containers ⇒ "Forgejo CI in `.forgejo/workflows/`"),
`:223-226` (CI-primary line: forge workflow on the pushed branch; GitHub file is
`workflow_dispatch`-only), `:427-431` (hard rule: `.forgejo/workflows/containers-build.yaml`
pushes `yy.mm.N` + `:latest` + `:main`; PRs `pr-<branch>-<sha>`);
`skills/container-creation/SKILL.md:3` (description "publishing to ghcr.io/ownyourio …"),
`:42` ("builds and pushes containers" — one-registry claim), `:55` (calendar tag
"highest `yy.mm.*` tag **in the registry**"), `:62` (manual fallback), `:204`, `:216`,
`:229`, `:243-244`, `:263` (CI-authoritative line). `AGENTS.md` mirrors overview.md
(`x3` gates all three, L891-903), and `rulesync generate --check` must stay clean.
On `main` the same lines still name the GitHub builder (`git show main:` →
`overview.md:223` "`docker-build.yaml`", `:425` "pushes `:v<run_number>`";
`SKILL.md:3, 42, 54, 212, 235-236, 254`) — so the branch's docs hunks must be
re-applied after the rebase (merge-tree says they auto-merge).

Deferred-with-test-teeth (run 0's final review; the sweep must move docs **and** legs
together): `tests/pipeline-push-pr/surface.sh:313-314` — P7 demands the containers
section route builds to "**docker-build.yaml** PR validation" (plus `:215`
`contract ci-on-push … 'docker-build'`); `tests/wekan-mcp/tools.sh:351-358` — t5 pins
`containers/wekan-mcp/README.md` to `:v<run_number>` + `:<branch>` **and bans the string
`:latest`**, which is now a real tag this pipeline pushes. Further near-live prose (all
non-gated today): `containers/wekan-mcp/README.md:60`, `containers/strata/README.md:162`,
`containers/vllm-rocm/README.md:10`, `tests/cf96-deploy/readback-runbook.md:30,39`,
`tests/containers/forgejo-host-runner.sh:235`, `tests/containers/wekan-mcp-login.sh:497,510`.

### 7.4 Card 55 / concurrent-work collision surface (live)

- `git worktree list` → `…/e32e19/cf-55-feat-helm-builds-to-forgejo` at **`a6e493b78` =
  `main` tip**; inside it `git log --oneline -5` shows only main's commits (**no
  cf-55 commit yet**) and `git status --short` shows exactly one untracked path:
  `.agents/plans/2026/2026-11-cf-55-feat-helm-builds-to-forgejo/` (`EXPLORE.md`,
  `RESEARCH.md`, mtime 2026-11-10 21:40). Its `.forgejo/workflows/` contains **only
  `main-sync.yaml`** (it is based on main, so it has no cf-6 files).
- Card 6's run -1 claim comment (board, comment `2cvwFFunwTDHvDAzT`) records the
  sanctioned **shared** `Pipeline: CICD` claim with card 55 ("co-tenant is card 55 …
  setId 62e9d100 … **the expected overlap is `.forgejo/workflows/*` and AGENTS.md,
  resolved at merge time on separate branches**").
- cf-55's own EXPLORE (read from that worktree) declares its move surface = the seven
  `.github/workflows/*` files → new `.forgejo/workflows/*`, and it independently
  re-derives the ROLE facts (its §0/L107-115: both jobs guard `vars.ROLE == 'prod'`,
  `ROLE=prod` infra / `ROLE=dev` dev).
- Concrete collision set: (a) new files under `.forgejo/workflows/` (helm builds vs the
  container builder — different filenames, same directory and same guard convention);
  (b) `.rulesync/rules/overview.md` + regenerated `AGENTS.md` (both re-pin CI prose);
  (c) `tests/services/*` new suites (different files); (d) `skills/container-creation`
  vs cf-55's docs are disjoint. cf-55 additionally plans to move the GitHub-side
  builders, i.e. it may touch `.github/workflows/docker-build.yaml` prose — cf-6's x1
  owns that file's triggers. Landing order (who rebases on whom) is a coordinator/owner
  decision, not an explore call.

## 8. MCP / cluster ids resolved live (so planner + dev don't re-resolve)

1. **Kubernetes MCP servers used** (readonly only; no `admin-*`, no exec):
   `readonly-infra-kubernetes`, `readonly-gpu-kubernetes`, `readonly-dev-kubernetes`
   (Code Mode: `tools["readonly-<cluster>-kubernetes"].pods_list_in_namespace /
   pods_get / pods_log / resources_get / resources_list`). **Everything relevant lives
   in namespace `default`** on all three clusters. Secrets are **forbidden** to the
   readonly service account (`system:serviceaccount:default:kubernetes-mcp-readonly` →
   `forbidden` on `secrets get`), so `app.ini` is unreachable from here.
2. **infra cluster** (canonical `git.spencerslab.com`): Argo CD Application
   **`infra-forgejo`** (12 Applications in `default`); Pod
   `infra-forgejo-6b95547f88-psps8`; image
   `code.forgejo.org/forgejo/runner`… no: `code.forgejo.org/forgejo/forgejo:15.0.10-rootless`;
   Service **`infra-forgejo-http`** (ClusterIP, port 3000 → target `http`); Ingresses
   **`git-ingress`** (host `git.spencerslab.com`, class traefik, TLS, `/` → 3000) and
   **`forgejo-ingress`** (`forgejo.spencerslab.com` → same service); DB
   `pg-forgejo-1`; env `SSH_PORT=22222` / `SSH_LISTEN_PORT=2222` (pod env). No runner
   lives on the infra cluster.
3. **gpu cluster**: Application **`gpu-forgejo-runner-gpu`**; StatefulSet pod
   **`gpu-forgejo-runner-gpu-0`** (2/2 = dind + runner; containers `dind` + `runner`),
   dials `https://git.spencerslab.com`; 20 Applications in `default`.
4. **dev cluster**: Applications **`dev-forgejo`** and **`dev-forgejo-runner-dev`**;
   Pods `dev-forgejo-c4ccf6fcb-2dbbk` (1/1) and `dev-forgejo-runner-dev-0` (2/2);
   Service **`dev-forgejo-http`** (ClusterIP 3000); Ingress `git-ingress` →
   `git.scifi.farm`; DB `pg-forgejo-1`.
5. **Registry service name = the instance's web service** (`infra-forgejo-http:3000` /
   `dev-forgejo-http:3000`) — there is **no separate registry service/deployment**; the
   OCI endpoints are paths on the forge web host (`/v2/`, token realm `/v2/token`).
6. **Forgejo versions/APIs** (anonymous, live): `GET /api/v1/version` →
   `{"version":"15.0.10+gitea-1.22.0"}` on **both** instances; **public Actions
   history** `GET /api/v1/repos/CuratedForest/SpencersLab/actions/tasks` (infra: 66
   tasks, run_number max **32**; dev: empty) — the fastest way to see job names/statuses
   without auth. Job **logs are login-gated**: the job page's only log link is a
   `/user/login?redirect_to=…` and `GET /api/v1/repos/…/actions/jobs/66/logs` → 404
   anonymous. Owner-leg to read the failing job (run 32 `push-dev`, job id 66):
   UI `https://git.spencerslab.com/CuratedForest/SpencersLab/actions/runs/32/jobs/1/attempt/1`
   or `curl -H "Authorization: token $TOKEN"
   https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/actions/jobs/66/logs`.
7. **Docs sources read this session** (pinned upstream):
   `https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/reference.md`,
   `…/docs/user/actions/basic-concepts.md`,
   `…/docs/user/packages/{container.md,index.md}`,
   `…/docs/admin/config-cheat-sheet.md` (note: `docs/admin/…`, **not**
   `docs/administration/…` — the latter 404s), and
   `https://code.forgejo.org/forgejo/end-to-end/raw/branch/main/actions/example-expression/.forgejo/workflows/test.yml`.
8. **Git remotes reachable from this worktree today** (`git ls-remote`, all exit 0):
   `origin` = `https://git.spencerslab.com/CuratedForest/SpencersLab.git` (heads:
   `main`, `fix-strata-q4-oom-envelope` — **`cf-6-feat-forgejo-container-builds` is not
   pushed**), `dev` = `ssh://git@git.scifi.farm:22222/…` (heads `main`, `stash`),
   `upstream` = `git@github.com:OwnYourIO/SpencersLab.git`. This **corrects run 0 §3's
   "both forge remotes unreachable"**; the rework can push/inspect for real if the class
   allows it (this run is commit-only, so nothing was pushed).

## §Open questions for planning

1. **Does the ROLE guard live in `if:` as an expression, or in a step as shell?**
   Best guess: a job-level `if:` that stays inside the *proven* subset (`vars.*` with
   `==`/`!=`/`&&`/`||`), computing membership over a comma list, plus a diag step that
   echoes the raw value — and push the *list* semantics into the step (`ROLE=${ROLE:-dev,prod}`
   + `case ",$ROLE,"`) wherever the unset→widest default must hold. Why: `contains`/
   `fromJSON` are documented and upstream-conformance-proven but only ever at step level
   (§2), and a wrong guess here silently disables the pipeline — the opposite of the
   owner's requirement.
   **Sharpener (new, §2):** nothing on this instance has ever *shown* a `vars`-based job
   guard taking its **false** branch — infra's `ROLE` is `prod`, so main's two guards have
   only ever evaluated true (15/15 runs), and the only observed job-level skip is the
   pre-ROLE `forgejo.server_url` guard. So the plan needs a guard whose false branch is
   *observable in the first live run* (a diag step that prints the raw value and the
   computed verdict is the cheap way), and **needs research: yes** — whether
   `contains(fromJSON(vars.ROLE), …)` evaluates in a job-level `if:` on 15.0.10 (and whether
   a false one yields `skipped` rather than an executed job) is not documented and not yet
   observed here.
2. **How does "unset = widest" coexist with cf-119's shipped "unset = nothing fires"?**
   Best guess: keep both, scoped by file — `containers-build.yaml` guards default to
   widest, `main-sync.yaml`'s prod guard stays fail-safe, and the difference is stated
   in each header + pinned by separate legs. Why: widening `main-sync` would make an
   unconfigured instance start pushing `main` to GitHub and dev, which cf-119 rejected
   on purpose (main-sync header L1-6, plan L152, L375).
3. **Which identity pushes to the forge registry?** Best guess: a human-minted PAT
   secret (per-instance name following the `PUSH_TOKEN_*`/`GHCR_PUSH_PAT` convention),
   not `forgejo.token`. Why: `forgejo.token` is documented as *repository*-scoped while
   packages are *owner*-scoped (§3), and the PAT route is the documented one and the
   repo's established pattern; the token route is worth one cheap dispatch probe before
   being dismissed.
4. **Registry naming/namespace for the forge side** — `git.spencerslab.com/CuratedForest/<name>`
   (org) vs a user namespace. Best guess: the org `CuratedForest`, mirroring the repo
   owner, with the image name = the container dir (so `…/CuratedForest/wekan-mcp`),
   because auto-linking then matches the repo name automatically
   (`container.md` "naming the image after the repository"). Needs the owner to confirm
   the org exists and the pushing identity can write to it.
5. **Single N across two registries** (§4.4). Best guess: derive N **once** per build,
   then HEAD-walk **both** registries before pushing either, tolerating a registry that
   answers 404/`NAME_UNKNOWN` as "no tags here" — so the same calendar number lands in
   both and neither is silently overwritten. Why: two different Ns for one build would
   make Renovate (ghcr-pinned consumers) and the forge UI disagree, and the walk is the
   only overwrite protection either registry has.
6. **Does `:latest`/`:main` (and `pr-*`) go to the forge registry too?** The notes say
   push-role → "**VERSIONED** containers to BOTH", and PR-role → forge only. Best guess:
   "versioned" = the calendar `yy.mm.N` only on the forge side, keeping `:latest`/`:main`
   ghcr-only as the documented cluster contract, and `pr-*` forge-only as spelled; the
   PR-tag retention question (which registry accumulates the junk) follows from that.
7. **Does the GitHub `docker-build.yaml` fallback keep pushing ghcr rolling tags when
   re-enabled?** If NOTE 1's commented block is ever uncommented, the GitHub builder
   mints `v<run>` + `<branch>` and re-opens run 0's Renovate-ordering hazard
   (DECISIONS D1/owner round). Best guess: keep the block commented *and* annotate the
   comment with "re-enabling races the calendar line", and pin that annotation in the
   suite.
8. **Where does the dev role get exercised at all?** Best guess: author + offline-pin the
   dev leg now, and treat live dev-role validation as an owner leg gated on §6's
   zero-tasks finding (or run the dev leg on infra by including `dev` in infra's ROLE,
   which is exactly the single-server default the owner described).

## §Verified facts (each with its evidence)

1. Two files under `.forgejo/workflows/` on this branch: `containers-build.yaml`,
   `main-sync.yaml`; nothing else in `.forgejo/` — `find .forgejo -type f`, HEAD
   `2f5d8efad`.
2. URL guards live there: `containers-build.yaml:51,87` and
   `main-sync.yaml:31,53` (`startsWith(forgejo.server_url, …)`), plus destination URL
   literals `main-sync.yaml:46,50` — read from the files.
3. `main`'s `.forgejo/workflows/main-sync.yaml` is ROLE-shaped: `if: vars.ROLE ==
   'prod'` at L25/L46, `vars.PUSH_URL_GH/DEV` + `secrets.PUSH_TOKEN_GH/DEV` at
   L38-39/L59-60, no URL literal, header L5-6 "An unset ROLE renders empty and fires
   nothing too (fail-safe)" — `git show main:.forgejo/workflows/main-sync.yaml`
   (commit `b482935ed`).
4. This branch: 9 commits over / 50 behind `main`
   (`git rev-list --count main..HEAD` = 9, `HEAD..main` = 50, merge-base
   `b438e1684`); main carries only a stale 49-line copy of run 0's `DECISIONS.md` and
   **no** `containers-build.yaml`/detector/tests
   (`git ls-tree -r --name-only main -- .forgejo .agents/plans/2026/2026-11-cf-6-…`).
5. Rebase collision set = one add/add conflict
   (`.agents/plans/2026/2026-11-cf-6-feat-forgejo-container-builds/DECISIONS.md`);
   `overview.md`, `AGENTS.md`, `tests/pipeline-models/surface.sh` auto-merge —
   `git merge-tree --write-tree --name-only main HEAD`.
6. Owner rework text (NOTE 1-3, ROLE semantics, SCOPE RULING, facts (a)-(e)) —
   `dev-boards` `list_comments(board TNQJ2BrXenZovngTS, card 7dAgENe75dBt2FZY6)`,
   comment id `cNNkCZkBHHm2ESf87`; run -1's claim record (slug
   `cf-6-feat-forgejo-container-builds-1`, shared CICD claim with card 55, surface
   deviation keeping run 0's branch/worktree) — comment `2cvwFFunwTDHvDAzT`.
7. Posture to beat confirmed live: `bash tests/services/forgejo-containers-build.sh`
   → `PASS: forgejo-containers-build checks (23 ok)`, exit 0, at `2f5d8efad`.
8. Commented-out `push:`/`pull_request:` inside `on:` keeps x1 green (parsed
   `on:` == `{workflow_dispatch}`, scoped grep clean); commented parent with live
   children breaks `yaml.safe_load`; the plan-Commands verbatim raw grep already hits
   the `push:` INPUT key at `docker-build.yaml:139` — replayed x1's logic on spliced
   scratch copies in `/tmp/opencode/` (repo untouched).
9. `vars` is an accessible context for `jobs.<id>.if`, `steps[*].if`, step/workflow
   `env`, `concurrency`, `jobs.<id>.name`; the Availability table has **no** `on.push`/
   `on.pull_request` rows (only the two `on.workflow_call.*` rows) —
   `docs/user/actions/reference.md` L1173, L1190-1225 (v15.0 raw).
10. Expression functions/operators: `contains` (array membership + substring,
    case-insensitive) L94, `startsWith`/`endsWith` L95-96, `format` L97, `join` L98,
    `toJSON`/`fromJSON` L99-100, cast `null` → `''` L107; operators incl. `&&`, `||`,
    `==`, `!=`; "String comparisons are case insensitive" —
    `docs/user/actions/basic-concepts.md` (v15.0 raw). Upstream conformance file proves
    `contains(fromJSON('[…]'), 'one')`, `format`, `join`, `env.NULL == null`,
    case-insensitive `==`.
11. Variable scopes/paths (`/org/{org}`, `/user`, `/{owner}/{repo}`
    `/settings/actions/variables`), name constraints (no `FORGEJO_`/`GITHUB_`/`GITEA_`
    prefix, not `CI`, `[A-Za-z0-9_]`, case-insensitive), owner-level precedence, and the
    automatic token's repository-only scope + no-retrigger rule —
    `basic-concepts.md` L127-133, L146-152, L155, L157-176.
12. `vars.ROLE` resolves true on the infra instance **today**: infra
    `…/actions/tasks` shows run 32 (`push a6e493b78`, 2026-11-10T20:34:24Z) → `push-gh`
    `success`, `push-dev` `failure`; runs 22/24 `workflow_dispatch` → both `success`;
    false guards appear as `skipped` in this API — but the only
     observed skips in all 66 tasks are 18 × `backup-proxy-merge`, a job that exists only in
     the pre-ROLE file (`git show ea9e97f64:…` L31/L53 URL guards) and is gone from main's
     v2; runs 18-32 (10 `push`, 5 `workflow_dispatch`, `b482935ed` 15:51:22Z → `a6e493b78`
     2026-11-10T20:34:32Z) each executed **both** guarded jobs — 6 fully green, `push-gh`
     failed in 7 (18-21, 23, 29-31), `push-dev` in 5 (18-21, 32), **zero skipped**, so the
     guard's false branch has never been observed here. Infra `main`
    == `dev` main == `upstream` main == `a6e493b78` (`git ls-remote` ×3).
13. Container registry live on both instances: `GET /v2/` → 401 +
    `Docker-Distribution-Api-Version: registry/2.0` + `www-authenticate … realm=
    "https://<host>/v2/token",service="container_registry"` on
    `git.spencerslab.com` and `git.scifi.farm`; `GET /api/v1/version` → `15.0.10+gitea-1.22.0`
    on both.
14. Forgejo registry absent-package codes (measured, with the anonymous scoped pull
    token): `tags/list` → 404 `NAME_UNKNOWN`; `HEAD manifests/26.11.1` → 404.
    Anonymous un-tokened `tags/list` → 401; anonymous token → 200 with
    `{"UserID":-1,"Scope":""}`. `GET /v2/_catalog` on both instances: `UNAUTHORIZED`,
    challenge `scope="*"` (no anonymous catalog listing).
15. ghcr today: `ownyourio/traefik-mqtt-allowlist` tags
    `0.0.1-0.0.12, latest, main, v87`; `wekan-mcp` `0.0.*, v24…v177, latest, main`;
    `strata` `v93…v196, main`; **no `26.11.*` anywhere**; `0.0.1`/`0.0.12` image-config
    `created` = 2026-01-29/2026-01-30 vs `v87`/`main` = 2026-10-25 (tokened
    manifest+blob reads).
16. Package-registry config defaults: `[packages] ENABLED true`,
    `LIMIT_TOTAL_OWNER_COUNT/SIZE -1`, `LIMIT_SIZE_CONTAINER -1`;
    `cron.cleanup_packages ENABLED true @midnight OLDER_THAN 24h` (unreferenced data);
    `[actions] ENABLED true`, `DEFAULT_ACTIONS_URL https://data.forgejo.org`,
    `ARTIFACT_RETENTION_DAYS 90`, `LIMIT_DISPATCH_INPUTS 10`,
    `ABANDONED_JOB_TIMEOUT 24h`, `ENDLESS_TASK_TIMEOUT 3h` —
    `docs/admin/config-cheat-sheet.md` L94-95, L984-989, L1291-1300, L1400-1428.
17. Package ownership/visibility rules (org-owned package readable publicly only if the
    org is public; write = owner / org write-members; `service.REQUIRE_SIGNIN_VIEW` can
    restrict; per-package delete is permanent) — `docs/user/packages/index.md`
    (Repository-Packages, Access Restrictions, Delete a package).
18. Image naming `{registry}/{owner}/{image}` with registry = the instance domain, plus
    the `LABEL org.opencontainers.image.source=` / name-matches-repo auto-linking —
    `docs/user/packages/container.md`.
19. Live pod/app/service/ingress facts: infra `infra-forgejo-6b95547f88-psps8`
    (image `code.forgejo.org/forgejo/forgejo:15.0.10-rootless`), Application
    `infra-forgejo`, Service `infra-forgejo-http:3000`, Ingresses `git-ingress`
    (`git.spencerslab.com`) + `forgejo-ingress` (`forgejo.spencerslab.com`) with no
    middleware annotations; gpu Application `gpu-forgejo-runner-gpu` / pod
    `gpu-forgejo-runner-gpu-0` 2/2; dev Applications `dev-forgejo`,
    `dev-forgejo-runner-dev`, Service `dev-forgejo-http:3000`, Ingress `git-ingress`
    (`git.scifi.farm`) — readonly k8s MCP `pods_get`/`resources_get`/`resources_list`,
    ns `default`.
20. Dev recovery + dev-runner state: `dev-forgejo-c4ccf6fcb-2dbbk` Running 1/1 30 h
    0 restarts; `dev-forgejo-runner-dev-0` Running 2/2 30 h 0 restarts; runner log
    "Dev Runner … declared successfully" 2026-11-09T15:16:10Z + one
    "failed to fetch task: deadline exceeded"; dev instance Actions history is empty
    (`workflow_runs: []`) — readonly-dev-kubernetes +
    `https://git.scifi.farm/api/v1/repos/CuratedForest/SpencersLab/actions/tasks`.
21. Infra jobs run on the gpu-cluster runner and the server URL they carry: runner log
    `task 65 repo is CuratedForest/SpencersLab https://data.forgejo.org
    https://git.spencerslab.com` (2026-11-10T20:34:24Z) — readonly-gpu-kubernetes
    `pods_log(gpu-forgejo-runner-gpu-0, runner)`.
22. Runner labels/job images (ghcr-pulled, so ghcr *pull* egress is proven):
    `charts/forgejo-runner/values.yaml:107-112` maps
    `ubuntu-latest|ubuntu-24.04|ubuntu-22.04|docker|node22` →
    `ghcr.io/catthehacker/ubuntu:act-24.04`/`act-22.04`; the dev runner advertises the
    same five labels (its declare log).
23. No insecure-registry or registry-related daemon config exists in the runner chart,
    and no Traefik body-size/buffering middleware exists in the repo — grep over
    `charts/forgejo-runner` and `charts|services|custom-values` for
    `insecure|maxrequestbodybytes|buffering` (only unrelated
    `serversTransport.insecureSkipVerify` hits).
24. LFS-only S3 posture (packages therefore live on the instance PVC) —
    `charts/forgejo/values.yaml:90-100`; no `[packages]`/`[storage]` keys in
    `services/{infra,dev}/prod/values.yaml` (grep).
25. Test-leg line references as tabulated in §7.1/§7.2 —
    `tests/services/forgejo-containers-build.sh` L130-167, L169-203, L272-339, L341-449,
    L451-483, L485-625, L788-831, L833-885, L887-910, L912-922; precedent legs
    `git show main:tests/services/forgejo-main-sync.sh` L74-99, L133-161.
26. Docs pins as tabulated in §7.3 — branch `overview.md` L21, 223-226, 427-431 and
    `SKILL.md` L3, 42, 55, 62, 204, 216, 229, 243-244, 263; main's equivalents
    `overview.md` L223, 425 / `SKILL.md` L3, 42, 54, 212, 235-236, 254; teeth
    `tests/pipeline-push-pr/surface.sh:215,313-314`, `tests/wekan-mcp/tools.sh:351-358`.
27. Card 55's run is live but has written no code: its worktree sits at `main`
    (`a6e493b78`) with only its untracked plan folder
    (`2026-11-cf-55-feat-helm-builds-to-forgejo/{EXPLORE,RESEARCH}.md`) —
    `git worktree list`, `git -C <cf-55 wt> log/status`, file listing; and card 6's own
    claim comment names the shared `Pipeline: CICD` co-tenancy and the expected
    overlap.
28. Run 0 rulings this rework touches (read, not re-decided): D2 infra-URL guard,
    D3 registry-derived `yy.mm.N` + existence-advance + the calendar Renovate rule,
    D4 `:main` + `:latest`, D5 `pr-<branch>-<sha>`, D8 plain docker build/push with
    `GHCR_PUSH_PAT`; owner round = narrow-not-delete —
    run 0 `DECISIONS.md` L51-149, `chunks/C01.md` L14-22/L47-60, `chunks/C02.md` L10-36.
29. Deferred run-0 items that stay open through run -1: the GHCR PAT→Bitwarden leg,
    entering `GHCR_PUSH_PAT` on the infra instance, the pre-merge `workflow_dispatch`
    smoke (shares the push arm: repoints `:latest`/`:main` + mints the first
    `yy.mm.1`), PR+merge owner-only, Inbox card AD-134 for the one-time pin bump, and
    the fact that `services/{dev,gpu}/prod/values.yaml` `image:` pins are extracted by
    no current Renovate manager — run 0 `DECISIONS.md` L161-166, `chunks/C02.md`
    L90-128, card comment `4ZvzHhQf25qdc5bb7`.
