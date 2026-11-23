# RESEARCH-r5 — Forgejo issues/PR access + the card-ID linkage

Round R5 of AD-140 (`cf-140-feat-agent-card-reconcile`) · 2026-11-23 · STORM-shaped, own
source numbering `[S#]` (independent of R1 and of `EXPLORE-*`). Sibling rounds stay
separate files per DECISIONS; nothing is merged into `RESEARCH.md` here.

Ask (card, verbatim intent): the agent should also have access to Forgejo issues and
pull requests; explore what the lab has, research best practice for organising that
access, and ideally tag/label the PR/issue with the card ID. R5 scopes it to what the
`card-runner` reconcile loop needs: consult the forge, stamp the card identity onto a
PR/issue, and later read it back to decide whether a card's objective is landed.

## Reliability notes (peer review, read first)

| Finding | Conf. | Why |
|---|---|---|
| Two Forgejos, prod canonical (`git.spencerslab.com`), dev (`git.scifi.farm`), both **15.0.10+gitea-1.22.0**, both serving this repo **publicly** | 9/10 | live `/api/v1/version` + `/repos/...` probes + per-instance custom-values |
| API surface for read/label/comment/poll at the deployed version (routes, guards, query params) | 9/10 | read from Forgejo source at tag `v15.0.10` **plus** live unauthenticated probes; guards verified in `routers/api/v1/api.go`, not from stale swagger (swagger is disabled on both instances) |
| Agent sessions today have **no** Forgejo credentials | 9/10 | live env probe of this workspace (`FORGEJO_*` absent) + `forgejo-token` ExternalSecret is rendered only by the dev umbrella |
| Non-admin token **can** label a PR; the lab has **never** actually landed a label via API | 7/10 | route/handler read at the pinned tag (confident) + zero-labels-on-both-instances evidence (strong signal, single-cause not proven) — needs a live-fire probe |
| Branch name is the right canonical join; per-card labels are the wrong shape | 8/10 | prior-art sources + pinned-source traps (silent label-drop, label-create needs repo-writer) |
| Drop webhooks (sibling ruling holds for Forgejo too) | 8/10 | outbound-only + `reqAdmin()` + `ALLOWED_HOST_LIST = external` default + no retry knobs in the pinned settings struct |

**Weakest claim:** the Renovate-label diagnosis (F4.6). It is a hypothesis about
`RENOVATE_TOKEN`'s scope, inferred from two observed facts (labels configured, zero
labels present); the run log is the arbiter and I could not read it unauthenticated.
**What would verify it:** one Renovate run log line (`Failed to add labels …`) or the
live-fire label probe in §Ranked recommendation step 1.
**Blind spot no perspective pressed:** the *dual-lane* reality — GitHub carries a live
`renovate[bot]` PR lane (927 PRs, merges landing) while the forge lane is new, so
"landed" is not testable from one place until the owner rules a canonical forge
(OQ-R5b/OQ-R5e). R5 recommends scoping card linkage to one forge rather than solving
that hazard.
**Perspectives used** (trail inline, no `storm-runs/` dir, same posture as R1): the
reconciler author (determinism, zero context burn), the forge operator/owner (token
minting, instance config, blast radius), the API lawyer (scopes and guards at the
pinned version), the traceability designer (what survives squash-merge and board moves),
and the integration buyer (do we adopt a published MCP server / CLI).

Evidence classes: **[live]** probed from this agent shell 2026-11-23 · **[src v15]**
Forgejo source read at tag `v15.0.10` (the deployed version) · **[repo]** this worktree ·
**[doc]** upstream/vendor documentation · **[inferred]** reasoning from the above, marked.

---

## TL;DR (≤5 lines)

1. **Two Forgejos, one repo, both public, both at 15.0.10.** Reads of issues/PRs/comments/labels/timeline need **no token at all** today; only writes do. `FORGEJO_*` never reaches agent workspaces (`forgejo-token` is dev-cluster-only), so any write path is owner-mint-first.
2. **The deployed API is built for polling, not for events**: `GET /repos/{o}/{r}/issues?state=all&type=pulls&since=<RFC3339>` returns issues *and* PRs updated since a stamp in one call; `/pulls` alone has no `since`. Webhooks are outbound-only, repo-admin-gated, and refuse in-cluster receivers by default → the sibling "drop webhooks" ruling holds.
3. **Labels from a non-admin token are permitted** (`POST /issues/{index}/labels` needs a token at Issue-category **write** level, no repo-writer check in the handler) — but the lab has never landed a label: `GET /labels` is `[]` on both instances despite `renovate.json` asking for `dependencies`. Per-card labels are the wrong shape anyway (label-create needs repo-writer; a `labels=` filter with a non-existent name silently matches **everything**).
4. **Canonical link = branch name**, read back with the zero-write `GET /pulls/{base}/{head}` (live-proven), reinforced by a `Card:` **commit trailer** (survives squash-merge, needs no API) and a PR-body footer token carrying the card `_id`. **No** per-card label, **no** new WeKan custom field.
5. **Storage**: forge facts live in the run registry / plan folder (plugin-owned, one read per card per tick, ≤N-line delta forwarded); the card gets a PR URL in its existing summary comment. A no-forge-credential state is a *recorded* answer, never a stall — and forge payloads must never enter coordinator context (that is symptom (a) reborn).

---

## F1 — What the lab has (in-repo inventory, with evidence paths)

### F1.1 Instances, origins, roles

| Instance | Origin | Role | Evidence |
|---|---|---|---|
| **prod / canonical** | `https://git.spencerslab.com` | infra cluster, `ROLE` lists `prod` (the only instance allowed to fan main out) | [repo] `custom-values/infra/prod-values.yaml:58-67` (`APP_NAME: "SpencersLab"`, `DOMAIN`/`ROOT_URL`), `custom-values/infra/prod-values.yaml:86-88` (package registries the dual-publish CI pushes to); [repo] `.forgejo/workflows/main-sync.yaml:1-10` header; [live] `GET /api/v1/version` → `15.0.10+gitea-1.22.0` |
| **dev** | `https://git.scifi.farm` (SSH `ssh://git@…:22222`) | dev cluster, `ROLE` lists `dev` (runs the daily Renovate pass) | [repo] `custom-values/dev/prod-values.yaml:72-90`; `services/dev/prod/values.yaml:20-25` (`gitSshPort: 22222`); [live] `GET /api/v1/version` → `15.0.10+gitea-1.22.0` |
| **GitHub twin** | `git@github.com:OwnYourIO/SpencersLab.git` | mirror of prod main (downstream), but see F1.5 — it carries a live PR lane | [repo] `git remote -v` (`upstream`); [repo] `.forgejo/workflows/main-sync.yaml:28-47`; [live] `GET /repos/OwnYourIO/SpencersLab` → public, `has_issues`/`has_pull_requests` true |

- The repo is one repository on both forges: prod `CuratedForest/SpencersLab` **id 3**, dev **id 1**; both `private: false`, `has_issues`/`has_pull_requests`/`has_actions` true, `external_tracker: null` [live].
- Chart: `charts/forgejo/Chart.yaml` — wrapper over `oci://code.forgejo.org/forgejo-helm` chart **17.3.1** (`Chart.lock` generated 2026-10-25), `appVersion: 15.0.9`; the OCI dependency is **not** Renovate-trackable (comment: bumps are manual). Deployed binary is `15.0.10+gitea-1.22.0` [live], i.e. R5's pinned source tag matches what answers the API.
- The gpu cluster (where this agent fleet runs) **runs no Forgejo**: `services/gpu/prod/values.yaml:115-122` + `:265-273` — `forgejo-runner-gpu` is a client that dials `https://git.spencerslab.com` over HTTPS.
- Ingress/SSH wiring, LFS, mailer, OIDC (lab Keycloak) are per-instance in `custom-values/**`; the chart's one static env surface is `forgejo.gitea.additionalConfigFromEnvs` (`charts/forgejo/values.yaml:123-187` — a slice that overrides it replaces the whole list).

### F1.2 The GitHub↔Forgejo fan-out (how it actually works)

`.forgejo/workflows/main-sync.yaml` [repo]:

- Triggers: `push` to `main` + `workflow_dispatch`; both jobs guarded `if: contains(vars.ROLE, 'prod')` — so **only the prod instance fans out**, and an unset `ROLE` fires nothing (fail-safe, opposite polarity from `containers-build.yaml`).
- `push-gh`: `git push https://x-access-token:${PUSH_TOKEN_GH}@${PUSH_URL_GH#https://} HEAD:refs/heads/main`; `push-dev`: same shape to `PUSH_URL_DEV`/`PUSH_TOKEN_DEV`. Plain, non-force, `fetch-depth: 0` (a shallow clone cannot negotiate a non-force push); the instance's built-in push mirror is deliberately unused because it overwrites targets.
- Destinations and tokens are **instance-side** repo vars/secrets — the file carries no URL and no token, which is why it is safe to host on both instances.
- There is **no GitHub→Forgejo sync workflow** in `.github/workflows/` (only `aislop`, `rulesync`, `docker-build` (dispatch-only fallback), and render-test lanes) [repo]. GitHub is downstream for `main`.

### F1.3 Tokens and secrets that exist today (the minting precedent map)

Inventory of every `${{ secrets.* }}`/`${{ vars.* }}` referenced by `.forgejo/workflows/*` [repo, grep]:

| Name | Where used | What it is |
|---|---|---|
| `vars.ROLE` | all 5 workflows (23 refs) | repo-scoped comma list `{dev,prod}` — the job guard |
| `secrets.FORGE_PUSH_TOKEN` | `containers-build.yaml` (×4), `release.yaml` | **the precedent R5 should copy**: a per-instance, human-minted, **non-admin `write:package` PAT** for the forge's package registry (Actions job tokens cannot write packages). AGENTS.md: "per-instance human-minted non-admin scoped PAT (Actions secret `FORGE_PUSH_TOKEN`)" |
| `secrets.PUSH_TOKEN_GH` / `PUSH_TOKEN_DEV`, `vars.PUSH_URL_GH` / `PUSH_URL_DEV` | `main-sync.yaml` | git-push-only credentials, per destination |
| `secrets.RENOVATE_TOKEN` | `renovate.yaml:75` | the bot PAT that runs `RENOVATE_PLATFORM: forgejo` — **the lab's only existing API-writing forge token**, minted in the repo's Actions secrets, and (per PR authorship) it is the owner's own account `tms` [live] |
| `secrets.RENOVATE_GITHUB_COM_TOKEN`, `vars.RENOVATE_GIT_AUTHOR` | `renovate.yaml` | read-only donor token; commit-identity stamp |
| `runner-token` items | `custom-values/dev/prod-values.yaml:92-99`, `custom-values/gpu/prod-values.yaml:109-118` | Actions **runner** registration pairs (`uuid`+`token`); the dev file explicitly warns "NOT `forgejo-token` — that is the Coder workspace access token" |
| `forgejo`, `forgejo-admin`, `forgejo-pg`, `forgejo-sso`, `forgejo-s3` | `charts/forgejo/values.yaml:17-36` + `templates/secret-forgejo*.yaml` | `SECRET_KEY`, initial admin, CNPG creds, OIDC client, LFS S3 keys — all `OVERRIDE_VIA_CUSTOM_VALUES`, real UUIDs in `custom-values/{dev,infra}/prod-values.yaml` |
| **`forgejo-token`** (Bitwarden LOGIN) | `services/dev/prod/templates/secret-forgejo-token.yaml` | `FORGEJO_TOKEN` secret in namespace `default`, **dev umbrella only**, consumed by the Coder workspace template |

### F1.4 What an agent session actually has (live probe — this is the load-bearing fact)

- This workspace (`CODER_WORKSPACE_NAME=SpencersLab-Claud`, ns `default`) has **no `FORGEJO_*` environment at all** and none of `tea`, `gt`, `forgejo-cli`, `fj`, `gitea` on `PATH` [live]. `CODER_*` vars are plentiful, so this is not an env-visibility artefact.
- Why: `charts/coder/coder-templates/kubernetes-hardened/main.tf:454-490` injects `FORGEJO_TOKEN` (`secretKeyRef` on secret `forgejo-token`, **`optional = true`**), `FORGEJO_HOST = "git.scifi.farm"` (bare literal, **dev forge**) and `FORGEJO_OAUTH_ID = "forgejo"`. The secret exists only where `services/dev/prod/templates/secret-forgejo-token.yaml` renders it; an optional `secretKeyRef` to a missing secret yields **silently absent env** [repo → inferred, and consistent with the live probe].
- Per-user SSO alternative exists but is dev-side too: `services/gpu/prod/templates/secrets-coder.yaml:30-48` — coderd spends its single community-license external-auth slot on `git.spencerslab.com` (`CODER_EXTERNAL_AUTH_0_TYPE: gitea`, callback `https://coder.spencerslab.com/external-auth/forgejo/callback`), the item being `custom-values/gpu/prod-values.yaml:10-16`; the baked startup script layers the per-user token over the PAT helper once approved [repo, main.tf:478-490 comment].
- **Consequence:** reads work credential-free (public repo); writes require the owner to mint something and to choose how it is delivered (F5.2). Also: the reconcile plugin should *not* depend on workspace env for credentials — the plugin process, not the model, should hold the token.

### F1.5 Where issues/PRs actually live (dual lane — a scoping decision, not a detail)

- Forge prod: `x-total-count` 111 for `state=all` issues, **110 pulls, 1 pure issue** ("Dependency Dashboard") [live] → forge issues are effectively unused; PRs are the real object.
- Forge prod PRs #109-111 are `tms`-authored Renovate PRs (the forge lane, `.forgejo/workflows/renovate.yaml`, guard `contains(vars.ROLE,'dev')`) [live+repo].
- GitHub twin: `renovate[bot]` lane is **alive** — newest PR #927 created 2026-11-19, and 7 merged PRs since 2026-11-01 [live]. So dependency work currently lands on GitHub while the board/pipeline pushes branches to Forgejo.
- `.opencode/skills/pipeline-push-pr/SKILL.md:31` [repo]: the PR leg runs **`gh pr create`** (GitHub) with a GitHub compare-URL fallback, while "verify after push" checks `git ls-remote origin <branch>` and `origin` is Forgejo prod. As written, a `-pr` run pushes the ticket branch to the forge and then looks for a PR surface on the mirror, where that branch was never pushed → **the card-linked PR has no home until the owner rules one** (OQ-R5b).

### F1.6 MCP fleet: no Forgejo server (confirmed, as the brief predicted)

- Project-local `.opencode/opencode.jsonc` `mcp.servers` = exactly six: `readonly-dev-kubernetes`, `admin-dev-kubernetes`, `dev-playwright`, `dev-renovate`, `dev-searxng`, `dev-boards` [repo].
- The AGENTS.md server table (global fleet) lists kubernetes/postgres/Grafana/HA/WeKan/searxng/playwright/renovate — **no forgejo row** [repo]. Machine-global `~/.config/opencode/opencode.json` was not re-enumerated (not needed: no forge server appears in any agent permission set or in the AGENTS.md table that documents it).
- Upstream landscape (F3.3): several exist, none mature/lab-shaped.

---

## F2 — Access options, with API shapes pinned to the deployed version

All route/guard facts below are read from Forgejo **tag `v15.0.10`** (`routers/api/v1/api.go`, `routers/api/v1/repo/{issue,pull,issue_label}.go`, `modules/structs/{issue,pull}.go`, `modules/setting/webhook.go`, `models/auth/access_token_scope.go`, `custom/conf/app.example.ini`) — the version both instances answer [live]. Swagger is disabled on both instances (`GET /api/v1/swagger.json` → 404 [live]), so the source *is* the spec here, matching the cf-11 round's finding [S23].

### F2.1 Auth model and scopes (the exact token vocabulary)

- Header form used in-repo and upstream: `Authorization: token <PAT>` ([repo] `containers/forgejo-host-runner/sync/forgejo_publish.py:80`; [doc] [S10]).
- Category gates: the whole `/repos/{owner}/{repo}` read block is wrapped in `tokenRequiresScopes(AccessTokenScopeCategoryRepository)` (`api.go:1076`); the issues/labels block in `…CategoryIssue` (`api.go:1199`) [src v15].
- **Level comes from the HTTP verb**: `requiredScopeLevel()` = `Read` for GET/HEAD, `Write` for POST/PUT/PATCH/DELETE (`api.go:253-260`) [src v15]. So one endpoint family needs `read:issue` or `write:issue` depending only on the method.
- Scope strings (`models/auth/access_token_scope.go`): `all`, `public-only`, `read|write:{activitypub,admin,misc,notification,organization,package,issue,repository,user}`; write implies read [src v15].
- **Trap (real, non-obvious):** the scope check applies *only when a token is presented* (`api.go:251-252` comment: "if a token is not being used, reqToken will enforce other sign in methods"). On a public repo an anonymous GET succeeds where a wrongly-scoped token GET is refused. A reconciler that attaches `read:issue` to a `/pulls` call would fail while curl-with-no-token works — a confusing production failure mode waiting to happen. Rule: attach a token only to calls whose category it satisfies, or attach `all`/category-matched tokens deliberately.

### F2.2 Read surface (what the reconcile loop needs)

| Need | Endpoint | Guard at v15 | Proven |
|---|---|---|---|
| incremental delta of **issues + PRs** | `GET /repos/{o}/{r}/issues?state=all&type=pulls&since=<RFC3339>` (`before`, `labels`, `q`, `milestones`, `assigned`, `created`, `mentioned`, `review_requested`, `reviewed` also exist) | token optional on public repo; Issue category | [live] `since=2026-11-20T00:00:00Z` → results; [src v15] `issue.go` swagger params |
| one object | `GET /issues/{index}` / `GET /pulls/{index}` | pulls: `reqRepoReader(unit.TypeCode)` + Repository category | [live] PR 111 → `state`, `merged`, `mergeable`, `labels[]`, `head.sha`, `user.login` |
| **PR by branch pair** | `GET /pulls/{base}/{head}` (`GetPullRequestByBaseHead`, `api.go:1006`), head slash raw or `%2F` | same | [live] `/pulls/main/renovate/kube-prometheus-stack-93.x` → PR 111 |
| PR detail | `/pulls/{index}/commits`, `/files`, `/reviews`, `GET /pulls/{index}/merge` | same | [live] `/merge` → 404 for an unmerged PR (treat 404 as "not merged"); **`/pulls/{index}/pull` does NOT exist at this version** — it 404s through the `/{base}/*` pattern with a JSON body, so it *looks* like a real miss |
| human trail | `GET /issues/{index}/comments`, `GET /issues/{index}/timeline` | token optional on public | [live] timeline items incl. `type: "pull_push"`, `pull_request_url` |
| CI verdict | `GET /commits/{ref}/status` (combined), `/commits/{ref}/statuses` | `reqRepoReader(unit.TypeCode)` | [src v15] `api.go:1012-1019` |
| commit → PR (reverse) | `GET /commits/{sha}/pull` | same | [live] 404 for an unmerged head → best-effort only |
| labels present in repo | `GET /repos/{o}/{r}/labels` | open | [live] **`[]` on both instances** |

Cost: one request per card per tick (`/issues?since=` for the whole repo delta, or one `/pulls/{base}/{head}` for a known branch). No pagination gymnastics for a 111-PR repo; `x-total-count` rides the response [live].

### F2.3 Write surface (labels, comments, PR creation)

| Write | Endpoint | Guard at v15 | Verdict |
|---|---|---|---|
| add/replace/clear labels on an **issue or PR** | `POST|PUT|DELETE /repos/{o}/{r}/issues/{index}/labels`, `DELETE …/labels/{identifier}` (`api.go:1129-1135`) | `reqToken()` + Issue category at **write** level. Handler `AddIssueLabels`/`prepareForReplaceOrAdd` (`issue_label.go:347+`) contains **no** repo-write permission check | **Non-admin token can do it** — the only requirement is `write:issue` scope on a token whose account can see the repo |
| **create** a label | `POST /repos/{o}/{r}/labels` (`api.go:1184-1186`) | `reqRepoWriter(unit.TypeIssues, unit.TypePullRequests)` | needs an account with write on the issues/PRs unit (owner/admin here) — a read-only-ish bot cannot bootstrap its own vocabulary |
| comment | `POST /repos/{o}/{r}/issues/{index}/comments` | `reqToken()` + Issue write | fine |
| create / edit a PR | `POST /pulls` (`Labels []int64` supported at creation), `PATCH /pulls/{index}` (`title`, `body`, `state`, `Labels []int64`) | `reqToken()` (+ Repository write for code-touching) | labels are **ID-only** here, and a PR can be labelled in the same call that creates it |
| commit status | `POST /statuses/{sha}` | `reqRepoWriter(unit.TypeCode)` | only if R5 ever wants to publish a check |
| hooks | `GET|POST /repos/{o}/{r}/hooks` | `reqToken(), reqAdmin(), reqWebhooksEnabled()` (`api.go:811-820`) | repo-admin rights → owner-only |
| workflow dispatch (inbound seam) | `POST /repos/{o}/{r}/actions/workflows/{file}/dispatches` body `{"ref": …}` | `write:repository` (no `actions` scope exists) | the sanctioned "poke it now" path (cf-11 RESEARCH §1.2) |

### F2.4 Posture: plugin vs MCP vs CLI

**Plugin-direct REST (recommended).** Deterministic, zero extra surfaces, and the plugin process is already the thing that must own the cross-process run registry (`REVIEW-existing-plugins.md` §1 item 8, M1). In-repo precedents: `forgejo_publish.py` (`GET`/`POST`/`PATCH /api/v1/repos/{repo}/pulls` with `Authorization: token`, config from `FORGEJO_URL`/`FORGEJO_REPO`/`FORGEJO_PAT`) [repo], and the `board-context` plugin's raw JSON-RPC-over-HTTP leg [repo EXPLORE-agents §6]. A `fetch`-only leg adds no npm dependency, which keeps R1's zero-dep posture intact, and it is trivially unit-testable offline (the `tests/opencode/*.test.ts` family's law).

**MCP server (defer; optional and only for *conversational* reads).** None in the lab (F1.6). Upstream landscape, metadata pulled live 2026-11-23:

| Project | Lang | License | ★ | Last push | Notes |
|---|---|---|---|---|---|
| `Sqcows/forgejo-mcp` (twin `ric_harvey/forgejo-mcp` on Codeberg) | TypeScript | MIT | 19 | 2026-11-22 (active) | 103 tools across repos/issues/PRs/orgs/users/admin; created 2026-02 — very young [live API] |
| `goern/forgejo-mcp` | Go | GPL-3.0 | 159 | 2026-11-23 | self-described **"MIRROR ONLY"**, built around Codeberg's API semantics; a contributor report of a **context-window overflow** from an unbounded `list_repo_pull_requests` payload is filed against it [live API + S14] |
| `raohwork/forgejo-mcp` (docker `ronmi/forgejo-mcp`) | Go | MPL-2.0 | 70 | 2025-10-28 (**stale >1 y**) | HTTP/SSE mode; PR *viewing* only per its own feature list [live API + doc] |
| `minhcuongvu/forgejo-mcp` | Go | none declared | 0 | 2026-05 | unlicensed → unusable under this repo's posture [live API] |

Two structural arguments against MCP *for the loop*, independent of maturity: (1) MCP tool results land in model context, which is exactly the failure symptom (a) is being retired to fix (`REVIEW-existing-plugins.md` §2(a): 15/17 long-lived board-coord sessions re-injected, worst 12 of 34 prompts); (2) standing one up the lab way (container in `containers/`, ToolHive `MCPServer`, Bitwarden item, values pin bump, deploy verify) is its own ticket by the wekan-mcp precedent [repo EXPLORE-wekan-mcp §1.3,§2]. If the owner later wants agents to *browse* the forge interactively, a read-only tier server is the safe shape, mirroring `wekan-readonly`.

**CLI (no, for the loop; `gt` is worth knowing for humans/probes).** `tea` is **archived**, replaced by the official Gitea CLI **`gt`** (`gitea.com/gitea/cli`, v2.0.0, MIT, active 2026-11-18; every list/view command supports `--json`, `--jq` works without jq, `gt help exit-codes` documents stable exit codes, `gt commit pr`, `gt label list --search`; the repo even ships an agent skill for it) [doc S15/S16]. Forgejo's bundled `forgejo forgejo-cli` covers only `actions` and `f3` — **no issues/PRs** [doc S17]; community `Cyborus/forgejo-cli` is not official (upstream discussion #400 notes tea stayed Forgejo-compatible) [doc S18]. A CLI must exist in the workspace image (no docker daemon to build one) — a worse fit than `fetch` for a plugin, but a fine human/probe tool and a good documented validation command.

---

## F3 — The card-ID linkage: prior art, then the recommendation

### F3.1 What systems that already do this actually do

| System | Link mechanism | Readable back? | Source |
|---|---|---|---|
| **Linear** | issue ID in the **branch name** *or* the **PR title**, or a magic keyword (`Fixes ENG-123`) in the PR body; "Copy git branch name" emits the configured `<id>-<desc>` format | yes — server-side parsing of branch/title; status automations follow PR state | [S1] linear.app/integrations/github, [S2] linear.app/enablement/guide/diffs |
| **Jira** | **issue key in the commit message** (`git commit -m "JRA-123 <summary>"`) feeds the Development panel; Smart Commits `<ISSUE_KEY> … #<command> <params>` mutate the ticket | yes — commit-message parse, survives rebases/squash as long as the message survives | [S3] Atlassian "Reference work items", [S4] "Process work items with smart commits" |
| **GitHub** | **closing keywords** in the PR body (`close|closes|closed|fix|fixes|fixed` + `#N`) create a *linked PR* record; **only when the PR targets the default branch**; keywords in a **commit message** close on merge into default but create *no* linked-PR record; auto-close-on-merge is now a repo setting | yes — `repository.issue.closedByPullRequestsReferences` / the "Development" field | [S5] docs.github.com linking-a-pull-request-to-an-issue, [S6] managing-auto-closing-issues |
| **GitLab** | first-class **cross-link API**: `GET /projects/:id/issues/:iid/related_merge_requests`, `…/issues/:iid/closed_by`, `GET /merge_requests/:iid/closes_issues`, `…/merge_requests/:iid/related_issues`; plus crosslinking by referencing the issue **URL** in a commit message | yes — queryable from either end | [S7] docs.gitlab.com/api/issues, [S8] /api/merge_requests, [S9] crosslinking_issues |
| **WeKan** | **nothing native.** Only open feature requests: GitLab sync rules (#2698), card-to-card links (#3257), and #4758 asking that a card link survive a **board move** because traceability breaks today | — | [S11] wekan/wekan#2698, [S12] #3257, [S13] #4758 |

Reading across the table: nobody makes the *card number* the durable join. Every mature system joins on either (a) a **stable identifier embedded in the branch/commit** (Linear, Jira), or (b) a **relationship record the platform itself stores** (GitHub linked PRs, GitLab `closes_issues`). WeKan offers neither, so the lab must pick one and read it back itself.

### F3.2 The lab's own identity constraints (why the obvious answer is wrong)

- `card_number` is **display-only and re-counters on cross-board moves**; the board flow's join key is the card `_id` (`boards` skill, Dependency gate: "Every reference keys on the card `_id`; `card_number` is display-only identity, never a join key (it re-counters on cross-board moves)"), and upstream WeKan knows card links break across boards [S13]. AD-140's own `_id` is `zKf2GkiwPgeDmfpu2` with `card_number: 140` and board key `AD` (`STATE.json.kickoff`).
- The **slug `cf-<cardNumber>-<type>-<desc>`** already names every surface of a run: feature folder, worktree, branch, session (`boards` Card-driven kickoff, D10). Re-picks after a completed run append `-1`, `-2` to the slug.
- So the slug embeds the number (mutable) but **the branch is the number's only authoritative live carrier**: the run that owns the card creates the branch, and the run's `STATE.json` records both `_id` and slug in one place.

### F3.3 Recommendation: one canonical spelling, layered — **branch name is the join**

**Layer 1 — canonical, machine-read (zero new state, zero writes): the branch name.**
`<branch> == <slug> == cf-<cardNumber>-<type>-<desc>` (re-picks `-N`). Read back with the
live-proven zero-write lookup `GET /repos/{o}/{r}/pulls/{base}/{head}` → exact PR object
(`state`, `merged`, `mergeable`, `head.sha`, `labels[]`) — no token needed on a public
repo. Fallback for multi-PR or unknown-branch cases: one
`GET /issues?state=all&type=pulls&since=<stamp>` and match `head.ref` against the slug
prefix `cf-<cardNumber>-`. This is exactly Linear's mechanism [S1][S2], it survives card
re-numbering (the slug is what the card itself carries in its `slug` stack), and it
cannot drift, because the branch is minted from the slug by `kickoff-mint-branch.sh`.

**Layer 2 — durable traceability (git-only, no API, no credentials): a commit trailer.**
`Card: AD-140 cf-140-feat-agent-card-reconcile` on every chunk commit, written with
`git interpret-trailer` (so `git log --grep '^Card: AD-140'` and `--trailers` parse it).
This is the Jira commit-key pattern [S3] adapted to a trailer instead of a message prefix
— a trailer does not collide with the repo's commit-message style and is machine-extractable.
Its unique value: a **squash-merged** commit on `main` keeps the trailer forever, so
"did card AD-140 land?" is answerable from `git log` on the forge (or locally) without
any API at all. The coordinator is the sole chunk committer (AGENTS.md / `agents-sync`),
so exactly one writer needs to obey it.

**Layer 3 — human-facing + reverse lookup: one PR-body footer line.**
`wekan-card: AD-140 · <slug> · card=<card _id> · <board card url>` appended by the
`-pr`/dev leg at PR creation (the repo has **no** PR template — verified `.github/` holds
only `workflows/` — so the token belongs in the PR-creation step, or in a new
`.forgejo/pull_request_template.md` the owner approves). Regex-able, click-through for
humans, and it carries the `_id` so it stays correct even if the card moves boards and
re-counters. The reconciler treats it as an **accelerator, never the join** — humans open
PRs too and will not type it.

**Explicitly rejected: a label per card (the card's literal "tag the PR with the card ID"
ask).** Three grounded reasons, all specific to this deployment:

1. Label *creation* is repo-writer-gated (`reqRepoWriter(unit.TypeIssues, unit.TypePullRequests)`, `api.go:1186`), so a bot token cannot bootstrap a growing vocabulary; and one label per card means label sprawl (~90 cards and counting) in a repo where `GET /labels` is currently `[]`.
2. **The filter silently lies**: `labels=` is documented "Non existent labels are discarded" [src v15], and my live probe with `labels=dependencies` (a label that does not exist) returned **unfiltered** results — an "is there a PR labelled with this card?" query would read as "everything matches" or "nothing matches" with no error. This is the same silent-drift class the `boards` skill calls out for `Repo:` label spelling.
3. The lab's only existing API label-writer has never landed a label (F4.6) — so the very capability the design would depend on is currently unproven here.

If the owner wants a visible forge-side badge, use **one static label** (e.g.
`agent-run`, owner pre-created, ≤ a handful of labels total) to mark agent-authored PRs,
and keep the card identity in the branch/trailer/body. That keeps labels human-owned
(the standing `boards` doctrine) and keeps the join out of a mutable, sparse vocabulary.

**Also rejected: WeKan-side fields as the forge-link store** (see F4.2).

---

## F4 — Organization: what to store where, and how not to re-inject context

### F4.1 Where each fact belongs

| Fact | Home | Why there |
|---|---|---|
| Card ↔ slug ↔ session ↔ claim | unchanged: card `slug` custom-field stack + `STATE.json.kickoff` | already the canonical stack, append-only, parsed by the resume rule (`boards`) |
| **Card → PR/issue state** (the reconcile answer) | **run registry / plan folder**: one bounded record per run, e.g. STATE.json `forge: {forge, repo, pr_number, pr_url, head_sha, state, merged_sha, checked_at}` (or the pivot's registry row — the plan chooses the file, not this round) | "files are the bus"; the plugin reads it without a model in the loop; survives compaction |
| Human-readable PR pointer | the card's **existing** final-review / chunk **summary comment** (one added line: `PR: <url> (<state>)`) | `add_comment` is already the card's audit surface and the claim comment already carries a session link; **no new field** |
| PR/issue *content* (bodies, timelines, comments, diffs) | **nowhere persistent by default**; if a dev/review session genuinely needs it, it fetches it itself in its own session and writes a summary into its chunk file | this is the whole point of the pivot — the coordinator must not pay for it |

**No new WeKan custom field.** The board carries exactly two fields (`slug`, `Priority`),
resolved **by name**; adding a third would move the roster in the provision engine
(`scripts/provision-board.py` `CHECKLIST_SPEC`/constants), the snapshot fixtures
(`tests/wekan-board-provision/fixtures/`), `boards` SKILL.md's roster law, and the
name→id maps in `scripts/board-checklist-backfill.py` — board structure is human-owned and
"DRIFTS; this enumeration is context, never a freeze" (`boards` Board facts; [repo]
EXPLORE-agents §4). That is a board-provision ticket, not a reconcile feature, and the
`slug` stack already carries the card's identity.

### F4.2 The staleness / one-shot rule (symptom (a) is the design constraint)

DECISIONS (this ticket): symptom (a) is "a capability flap, not a tunable bug: the process
serving follow-ups had no `ctx.storage` binding, so `writeOnce` never advanced the
once-mark", with live evidence 15/17 long-lived board-coord sessions re-injected (worst 12
of 34 prompts), and the replacement "must move the once-mark off `ctx.storage` onto a
provably cross-process surface" [repo]. DECISIONS Deferred also warns: "Change-forwarding
risks becoming the new context injector — the pivot's own symptom (a) reintroduced; the
plan needs a bound." Forge reads are the biggest new payload in the design, so the bound
is written here for the plan to adopt:

1. **One read per card per tick.** Per card, the plugin spends at most one forge request (`/pulls/{base}/{head}` for the known branch; the repo-wide `since=` delta at most once per tick, shared by all cards).
2. **Cross-process once-mark.** `forge_checked_at` + a small last-seen digest (`{pr_number, state, head_sha}`) live on the same provably cross-process surface the pivot already mandates for once-marks (shared session record or a canonical-root file — **never `ctx.storage`**), so a second process cannot re-read and re-forward.
3. **Forward a delta, never a payload.** The coord receives ≤N lines (recommend N=3: `landed | pending | none | unknown` + PR URL + state/sha). Bodies, timelines, comments, file lists and logs are **never** pasted into a prompt or into STATE.json.
4. **Staleness = TTL, not a re-read on every prompt.** Trust the record while `now - forge_checked_at < tick cadence`; refresh only on a tick, or on the state transitions that actually matter (card hand to Review, final-review pass, `Deployment` checked).
5. **Failures are recorded, not retried inline.** An unreachable forge or a missing token writes `{state: "unknown", reason: …}` and moves on — the same degrade law the family already uses for board reads ("never a hard failure, never a stall"), and it is what makes "no credentials" a visible answer instead of a silent loop.
6. **Never write forge state onto the board as a mirror.** The card gets one human line at the summary; the machine truth stays on disk, so a stale board comment can never be read as truth.

---

## F5 — Reality check

### F5.1 Do labels on PRs work from a non-admin token on the deployed instance?

**Permitted by the deployed code: yes.** `POST /repos/{o}/{r}/issues/{index}/labels`
requires a token at Issue-category **write** level (`write:issue` or `all`) and carries no
repo-writer check in its handler at v15.0.10 [src v15]. PRs share the issue label routes
(the PR is an issue: `html_url` of issue 111 resolves to `/pulls/111` [live]), so there is
no separate PR-label surface to worry about.

**Proven in this lab: no.** `GET /labels` returns `[]` on both instances [live], every
open PR carries `labels: []` [live], and `renovate.json:8` asks for
`"labels": ["dependencies"]` [repo]. So the one label-writing automation the lab already
runs has never produced a label. **Most likely cause (hypothesis, one log line from
proof):** the Forgejo platform module's own documentation requires the PAT to carry
`issue: Read and Write` [S19], and a token minted before that requirement — or minted
"repo only" — makes Renovate's label step a logged warning, not a failure. Verification
is owner-side: read one Renovate run log for `Failed to add labels`, or run the probe
below. Either way, R5's stance: **do not build the card link on labels** (F3.3), and if
any label write *is* built, its first chunk must be a live-fire probe:
create → add → `GET` back → remove, against a throwaway PR.

### F5.2 Credentials: what has to be minted (owner-owned)

Nothing agent-reachable exists today (F1.4). Three shapes, in the order R5 recommends:

1. **Dedicated bot account + scoped PAT** — mirrors `FORGE_PUSH_TOKEN`: per-instance, non-admin, least scope, stored as a Bitwarden LOGIN item (the `forgejo-token` item pattern), surfaced as an ExternalSecret'd env to *the plugin's* location. Minimum scope for the recommended design: `read:repository` (+ `read:issue`) for reads; add `write:issue` only if label/comment writes are adopted; `write:repository` only if the plugin ever creates PRs. The instance can mint it without the UI: `forgejo admin user create … --access-token --access-token-scopes "read:repository,write:issue,read:user"` [doc S17].
2. **Coder external-auth per-user tokens** (`FORGEJO_OAUTH_ID=forgejo`, `coder external-auth access-token forgejo`) — honest human attribution, already wired for dev's coder; but per-user coupling, approval state outside the repo, and the token belongs to the human whose workspace happens to serve the loop.
3. **Reuse `forgejo-token`** — the Coder workspace PAT; it is the owner's own identity and is pointed at the **dev** forge (`FORGEJO_HOST = "git.scifi.farm"`). Acceptable for probes, wrong for a standing reconcile writer.

Also note: reads today need **no** credential because the repo is public — a legitimate
option (`public-only` scope exists for exactly this), but it couples the design to repo
visibility, and the "wrong token is worse than no token" trap (F2.1) applies.

### F5.3 Is there a webhook path at all — and does the sibling's "drop webhooks" hold?

**Yes there is a webhook path, and no it does not change the ruling.** Forgejo webhooks
are outbound-only (repo/org/user hooks POST events; there is no inbound generic webhook
trigger and no `repository_dispatch` equivalent — cf-11 RESEARCH §1.3 [S23][S20]), and at
v15.0.10 the repo-hook routes are `reqToken(), reqAdmin(), reqWebhooksEnabled()`
[repo `api.go:811-820`] → creating one is a repo-admin act, so it is owner-owned before
it is anything else. Concretely against the deployed config:

- `[api].DISABLE_WEBHOOKS = false` and no `[webhook]` block in the lab's chart → webhooks are enabled but fully defaulted [src v15 app.example.ini:498-499, repo `charts/forgejo/values.yaml`].
- **`ALLOWED_HOST_LIST = external` is the shipped default** ("Built-in: loopback, private, external, *; since 1.15.7") → an in-cluster receiver (`http://…svc.cluster.local`) is **refused** until the instance config allow-lists the internal host/CIDR — a chart-values change plus a redeploy, i.e. genuinely new infra, the same cost class the sibling round rejected for WeKan.
- `DELIVER_TIMEOUT = 5` s and `QUEUE_LENGTH = 1000`; the `[webhook]` settings struct at this tag has **no retry knobs at all** (`modules/setting/webhook.go` fields: QueueLength, DeliverTimeout, AllowedHostList, …) → queue-delivered, single attempt, with per-webhook `hook_task` delivery history retained under `[cron.update_hook_task_table]` [src v15]. Delivery is therefore *observably best-effort*, not at-least-once.
- Decisive point: **the reconcile loop's question is a state question, not an event question.** "Is this card's objective landed?" is answered by PR `state`/`merged`/`mergeable`/head-sha, which the polling surface exposes in one cheap call (`/pulls/{base}/{head}`, or one `since=` delta covering issues *and* PRs). `/pulls` itself has no `since` [src v15 `modules/structs/pull.go:74-77`], so a naive `/pulls`-based design would re-fetch everything every tick — worth writing into the plan so nobody builds that.

So: **drop webhooks for Forgejo in this ticket too**, for the same reason the sibling
dropped them for WeKan plus the allow-list/token cost. If low-latency wake ever becomes a
real requirement, the sanctioned inbound seam is
`POST /repos/{o}/{r}/actions/workflows/<file>/dispatches` with `{"ref": …}`
(`write:repository`, no new listener, no new host) [S23][S10] — not a webhook.

### F5.4 The scoping trap R5 discovered (must be ruled, not assumed)

`pipeline-push-pr` pushes the ticket branch to `origin` = **Forgejo prod** but opens PRs
with **`gh pr create`** on **GitHub**, where that branch was never pushed
[repo `.opencode/skills/pipeline-push-pr/SKILL.md:31,52` + `git remote -v`]. Meanwhile
GitHub carries a live `renovate[bot]` lane (927 PRs; 7 merged since 2026-11-01) while the
forge lane is new [live]. A reconcile loop that guesses a forge will therefore answer
"nothing landed" for PRs that exist on the other side. Recommendation: **Forgejo prod is
the card-link canonical surface** (that is where branches land, where Actions build, where
Renovate PRs now open, and where `origin` points), GitHub stays a mirror for main, and the
reconciler reads exactly one forge. The GitHub-side main divergence hazard (merges on the
mirror vs the prod→GitHub non-force fan-out) is pre-existing and out of scope, but it is
why "landed" should be judged by the forge's own PR state and not by a mirror diff.

---

## Ranked recommendation

**Access mechanism (ranked)**

1. **`card-runner` plugin, direct Forgejo REST via `fetch`, zero dependencies.** Read path: `GET /pulls/{base}/{head}` per card per tick (public repo → no token), repo-wide `GET /issues?state=all&type=pulls&since=` once per tick when multiple cards are in flight. Write path (only if adopted): `POST /issues/{index}/labels` / `/comments` with `Authorization: token <scoped PAT>` from an ExternalSecret'd env held by the plugin process. Offline-testable, matches the repo's plugin precedents, and never spends coordinator context.
2. **Human/probe CLI** — `gt` (`--json`, stable exit codes) as a documented validation command where a binary exists. Not a loop dependency.
3. **Read-only MCP tier server later, only if agents need conversational forge browsing** — after the lab builds or adopts one; do not gate this ticket on it.
4. **Webhooks** — not in this ticket (F5.3).

**Canonical card-ID link (adopt in this order; 1+2 are the pair R5 recommends)**

1. Branch name `cf-<cardNumber>-<type>-<desc>` (== slug) as the join, read back via `GET /pulls/{base}/{head}`, fallback `GET /issues?…&since=` + `head.ref` prefix match.
2. Commit trailer `Card: AD-<n> <slug>` (git-only, survives squash-merge, answers "landed?" with `git log --grep`).
3. PR-body footer line `wekan-card: AD-<n> · <slug> · card=<_id> · <url>` (human + reverse lookup; accelerator only).
4. **Not** a per-card label; if a badge is wanted, one static owner-created label (e.g. `agent-run`).

**Storage**

- Machine truth → plan folder / run registry (`STATE.json.forge` or the registry row): `{forge, repo, pr_number, pr_url, head_sha, state, merged_sha, checked_at}`, plugin-read only.
- Human truth → one line in the card's existing summary comment. `slug` stack stays the card identity; **no new custom field, no new board list, no new board label from an agent**.
- Context budget → the F4.2 six-point bound (one read/card/tick, cross-process once-mark, ≤3-line delta, TTL staleness, record-not-stall on failure, no board mirroring).

**Plan-shaping consequence:** the plan should carry a *precondition* chunk — "owner mints
the token and rules the canonical forge; live-fire forge probes (public read, label
create/add/read/remove, `/pulls/{base}/{head}` lookup) run against prod and are recorded"
— before any writer code is trusted. Reads-only can ship immediately with no credential at
all.

## Contradictions and how to weigh them

- **"Label it" (the card's literal ask) vs "branch+trailer is the join" (prior art + this deployment's traps).** Weighed toward the latter: the label path is permitted but unproven here, its filter fails silently, and its vocabulary is repo-writer-gated. The user's *intent* (find the PR from the card, and see the card on the PR) is fully met by layers 1-3.
- **"No token needed" (public repo) vs "least privilege" (mint a scoped read token).** Both true; recommend recording the visibility assumption as a risk and preferring a `read:repository`/`public-only` token once the owner mints one — a wrong-scope token is *worse* than none (F2.1), so the token decision must name the endpoint families it is attached to.
- **"Events are better for PR/issue activity" vs "polling is what the deployed API is built for".** Events win on latency, cost infra + admin token + instance config, and deliver best-effort with no retry at this version; polling answers the actual question (state, not event). Poll.
- **MCP reuse (103 tools, one MIT, active) vs plugin-direct.** Reuse looks cheap until the payload lands in model context; the loop is specifically the component that must not do that.
- **GitHub as PR home (where `gh pr create` points, and where dependency PRs already land) vs Forgejo prod (where branches are pushed and CI runs).** Weighed hard toward Forgejo for card linkage; the GitHub lane stays as-is and out of scope (OQ-R5b/e).

## Adjacent (found, not core)

- `.opencode/skills/pipeline-push-pr/SKILL.md:31` is stale relative to this repo's remotes (see F5.4) — a doc fix worth folding into whatever chunk touches the PR leg.
- The dev cluster's coder template hard-codes `FORGEJO_HOST = "git.scifi.farm"`, so any future `FORGEJO_*` trio for agents should be parameterised per cluster rather than copied [repo main.tf:474-477].
- Swagger is disabled on both instances, so every future forge-API claim in this repo should cite the pinned tag (as this file does), not a swagger URL [live, S23].

## Open questions (owner / coord)

1. **OQ-R5a (owner):** mint the bot PAT? Scope for the recommended design is `read:repository` (+`read:issue`); `write:issue` only if label/comment writes are adopted. Which Bitwarden item name, and which umbrella renders the ExternalSecret (prod forge is on infra; agent workspaces are on gpu — so the delivery target is the plugin's location, not the workspace)? Related: the gpu coder template carries no `FORGEJO_*` trio at all today.
2. **OQ-R5b (owner):** rule the canonical PR home = Forgejo prod? If yes, `pipeline-push-pr`'s PR leg changes from `gh pr create` to a forge PR (API `POST /pulls`, or the compare URL `https://git.spencerslab.com/CuratedForest/SpencersLab/compare/main...<branch>`) — the second half needs its own ruling because it changes a MUST-load contract.
3. **OQ-R5c (owner):** labels yes/no; if yes, who pre-creates the (small, fixed) label set — creation is repo-writer-gated and labels are human-owned doctrine.
4. **OQ-R5d (plan):** does the loop judge "landed" from PR state alone? The forge carries exactly 1 issue today [live]; if issues stay unused, the read surface halves to pulls/branch lookups and the `type=issues` branch can be dropped from the design.
5. **OQ-R5e (owner, pre-existing, out of scope):** the dual-lane main situation (merges on the GitHub mirror vs prod-forge→GitHub non-force fan-out). It does not block R5, but it eventually decides whether "landed" can be tested by `git log --grep '^Card: …'` on main alone.
6. **OQ-R5f (plan):** where exactly the forge record lives — `STATE.json.forge` vs the pivot's run-registry row. R5 recommends one record, plugin-owned, whichever file the pivot standardises on; two copies would recreate drift.

## Sources

- [S1] Linear — GitHub integration (link PRs/commits by putting the issue ID in the branch name or PR title; status automations) — https://linear.app/integrations/github
- [S2] Linear — Enablement guide, Reviews (identifier in branch name **or** PR title, linking keyword in PR body; "Copy git branch name") — https://linear.app/enablement/guide/diffs
- [S3] Atlassian — Reference work items in your development spaces (`git commit -m "JRA-123 <summary>"` → development panel) — https://support.atlassian.com/jira-software-cloud/docs/reference-issues-in-your-development-work/
- [S4] Atlassian — Process work items with smart commits (`<ISSUE_KEY> … #<command> <params>`) — https://support.atlassian.com/jira-software-cloud/docs/process-issues-with-smart-commits/
- [S5] GitHub Docs — Linking a pull request to an issue (keyword list; keywords work only when the PR targets the default branch; commit-message keywords close on merge but create no linked PR) — https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
- [S6] GitHub Docs — Managing the automatic closing of issues (repo setting, added after the 2025-04-23 changelog) — https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/managing-auto-closing-issues
- [S7] GitLab Docs — Issues API (`…/issues/:iid/related_merge_requests`, `…/issues/:iid/closed_by`) — https://docs.gitlab.com/api/issues/
- [S8] GitLab Docs — Merge requests API (`…/merge_requests/:iid/closes_issues`, `…/related_issues`) — https://docs.gitlab.com/api/merge_requests/
- [S9] GitLab Docs — Crosslinking issues (from commit messages / MRs) — https://docs.gitlab.com/user/project/issues/crosslinking_issues/
- [S10] Forgejo prior research in this repo — `.agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/RESEARCH-forgejo-runner.md` (dispatch API + `write:repository`; "webhooks are outbound only, no inbound generic trigger"; `Authorization: token <PAT>`; automatic `FORGEJO_TOKEN` anti-recursion rule)
- [S11] wekan/wekan#2698 — GitLab integration via WeKan rules (open feature request; no native forge sync) — https://github.com/wekan/wekan/issues/2698
- [S12] wekan/wekan#3257 — card-to-card attachments/links (open) — https://github.com/wekan/wekan/issues/3257
- [S13] wekan/wekan#4758 — "Link to a card should still work when the card was moved to another board" (traceability breaks today) — https://github.com/wekan/wekan/issues/4758
- [S14] `goern/forgejo-mcp` listing (Codeberg-focused, "MIRROR ONLY"; contributor report #593/#596 on unbounded `list_repo_pull_requests` payloads overflowing a context window) — https://mcpservers.org/servers/goern/forgejo-mcp
- [S15] Gitea `tea` — ARCHIVED, "replaced by gt (gitea.com/gitea/cli)" — https://gitea.com/gitea/tea
- [S16] Official Gitea CLI `gt` (v2.0.0, MIT, active; `--json`, `--jq`, `gt help exit-codes`, agent skill) — https://gitea.com/gitea/cli
- [S17] Forgejo v15 admin command-line (bundled `forgejo-cli` covers `actions` + `f3` only; `forgejo admin user create --access-token --access-token-scopes "all"|"read:issue,…"`) — https://forgejo.org/docs/v15.0/admin/command-line/
- [S18] Forgejo discussion #400 — "Moving Cyborus/forgejo-cli towards being official?" (notes tea stays Forgejo-compatible) — https://codeberg.org/forgejo/discussions/issues/400
- [S19] Renovate — Forgejo platform module (PAT table: `repo` RW, `user` R, **`issue` RW**, `organization` R; `platform=forgejo`) — https://docs.renovatebot.com/modules/platform/forgejo/ (Gitea twin: https://docs.renovatebot.com/modules/platform/gitea/)
- [S20] Renovate — Configuration Options `labels` ("By default, Renovate will not add any labels to PRs") — https://docs.renovatebot.com/configuration-options/#labels
- [S21] MCP-server metadata, live API pulls 2026-11-23: `api.github.com/repos/{Sqcows,goern,minhcuongvu,ronmi→raohwork}/forgejo-mcp`, `codeberg.org/api/v1/repos/ric_harvey/forgejo-mcp`
- [S22] Forgejo source at the deployed tag `v15.0.10` (raw, code.forgejo.org): `routers/api/v1/api.go` (scope categories `:1076`, `:1199`; verb→level `:253-260`; issue label routes `:1129-1135`; repo labels `:1184-1190`; pulls group `:965-1007`; commits/status `:1008-1019`; repo hooks `:811-820`), `routers/api/v1/repo/issue_label.go` (`AddIssueLabels`, `prepareForReplaceOrAdd`), `routers/api/v1/repo/issue.go` (list params incl. `since`, `type`, `labels`), `modules/structs/pull.go` (`ListPullRequestsOptions` = page+state; `Create/EditPullRequestOption.Labels []int64`), `models/auth/access_token_scope.go` (scope categories, Read/Write levels, the `read:issue`/`write:issue`/`public-only` string vocabulary), `modules/setting/webhook.go` (QueueLength/DeliverTimeout/AllowedHostList, no retry fields), `custom/conf/app.example.ini` (`:498-499` DISABLE_WEBHOOKS, `:1679-1700` `[webhook]` incl. `ALLOWED_HOST_LIST = external`, `DELIVER_TIMEOUT = 5`, `QUEUE_LENGTH = 1000`; `:2207-2211` hook_task retention)
- [S23] Live probes, 2026-11-23, agent shell (read-only GETs only; **no writes were made to either forge**): `/api/v1/version` on both instances → `15.0.10+gitea-1.22.0`; `/api/v1/swagger.json` → 404; `/api/v1/labels` → 404 (not a route); `GET /repos/CuratedForest/SpencersLab` → public, flags as in F1.1; `GET …/labels` → `[]` on prod **and** dev; `…/issues`, `…/pulls`, `…/issues/111`, `…/issues/111/timeline`, `…/pulls/111/pull` (404), `…/pulls/111/merge` (404), `…/commits/<head-sha>/pull` (404), `…/pulls/main/<head>` (200, raw and `%2F`), `…/issues?state=all&type=pulls&labels=dependencies` (unfiltered ⇒ silent label-drop), `…/issues?since=…` (200), `…/hooks` → 401 `token is required`; `x-total-count` 111 / 110 / 1; GitHub twin `api.github.com/repos/OwnYourIO/SpencersLab` + newest PRs (`renovate[bot]` #927 @ 2026-11-19; 7 merged since 2026-11-01); Actions-runs list readable unauthenticated; env/CLI inventory probe (no `FORGEJO_*`, no `tea`/`gt`/`forgejo-cli`); `git remote -v`
- In-repo evidence (no URL): `.forgejo/workflows/{main-sync,renovate,containers-build,release,builder-bootstrap}.yaml`; `charts/forgejo/{Chart.yaml,Chart.lock,values.yaml}`; `charts/forgejo/templates/secret-forgejo{,-admin,-db,-lfs-shape,-s3}.yaml`; `charts/forgejo-runner/values.yaml`; `services/dev/prod/templates/secret-forgejo-token.yaml`; `services/{dev,infra,gpu,proxy-local}/prod/values.yaml` (forgejo rows); `custom-values/{dev,infra,gpu}/prod-values.yaml`; `services/gpu/prod/templates/secrets-coder.yaml`; `charts/coder/coder-templates/kubernetes-hardened/main.tf:445-490`; `charts/coder/values.yaml`; `containers/forgejo-host-runner/sync/forgejo_publish.py`; `renovate.json`; `.opencode/opencode.jsonc` (`mcp.servers`, `plugins`); `.opencode/skills/pipeline-push-pr/SKILL.md`; `AGENTS.md` (MCP table, Forge role convention, `FORGE_PUSH_TOKEN`); this folder's `EXPLORE-agents.md`, `EXPLORE-wekan-mcp.md`, `REVIEW-existing-plugins.md`, `DECISIONS.md`, `STATE.json`; `git remote -v` + this workspace's env

---

RESULT
status: DONE
chunk: R5
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/RESEARCH-r5-forgejo-linkage.md]
commands_run: [read ticket folder (STATE.json, DECISIONS.md, EXPLORE-agents.md, EXPLORE-wekan-mcp.md, REVIEW-existing-plugins.md §grep) => pass, repo inventory (charts/forgejo*, services/**, custom-values/**, .forgejo/workflows/*, containers/forgejo-host-runner/sync, coder template, opencode.jsonc mcp block, renovate.json) => pass, live read-only probes of git.spencerslab.com + git.scifi.farm + api.github.com (version, repo flags, labels, issues/pulls/timeline/merge/commits-pull, /pulls/{base}/{head}, x-total-count, hooks 401) => pass, Forgejo v15.0.10 source fetch+grep {api.go, issue.go, pull.go, label.go, issue_label.go, structs/{issue,pull}.go, access_token_scope.go, setting/webhook.go, app.example.ini} => pass, env/CLI inventory probe => pass (result: no FORGEJO_*, no forge CLI), MCP-candidate metadata via api.github.com + codeberg API (Promise.allSettled) => pass, web survey (Linear, Jira, GitHub, GitLab, WeKan issues, tea/gt, forgejo-cli, Renovate forgejo/gitea modules) => pass]
deviations: no RESEARCH.md written per launch instruction — own sibling file RESEARCH-r5-forgejo-linkage.md; STORM trail embedded in-file (reliability notes + perspectives + sources) instead of a storm-runs/ dir, matching R1's posture; **no writes of any kind to either Forgejo** (research session is read-only; the label probe is handed to the plan as a live-fire chunk)
friction: agent sessions carry no Forgejo credential and `FORGEJO_HOST` points at the dev forge — resolved by grounding the credential gap as a finding and probing reads unauthenticated (public repo); swagger is disabled on both instances, so API claims were pinned to the v15.0.10 tag instead of a spec URL; `webfetch` for one doc returned a proxy-cached body (re-fetched by the vendor URL + Renovate docs markdown directly); Renovate run logs are not readable unauthenticated, so the zero-label cause is stated as a hypothesis with the exact verification step
open_questions: OQ-R5a owner PAT minting (scope set + Bitwarden item + which location gets it; gpu coder template has no FORGEJO_* trio); OQ-R5b rule Forgejo prod as canonical PR home and change pipeline-push-pr's `gh pr create` leg accordingly; OQ-R5c labels adopted or dropped (creation is repo-writer-gated; labels are human-owned); OQ-R5d is forge-issue state in scope at all (1 issue live); OQ-R5e GitHub-mirror main divergence (pre-existing, out of scope); OQ-R5f which file owns the per-run forge record (STATE.json.forge vs run registry)
next_suggested: plan should adopt branch-name + `Card:` trailer as the link (no labels, no new board field), gate any forge writer behind an owner token + a live-fire probe chunk (public read, /pulls/{base}/{head} lookup, label create/add/read/remove on a throwaway PR), and write the F4.2 six-point context bound into the card-runner contract; R4's card-change-detection round should cross-check the `since=` poll shape (it is the same incremental-read pattern, one call covering issues and PRs)
