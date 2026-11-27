# EXPLORE — AD-56 Forgejo pipeline for Coder templates

Grounded 2026-11-25 by `agent-explore` (read-only). Every fact cites its source.
Run context from `DECISIONS.md`: tp2-27b lane, AD-135 dependency-gate override,
shared CICD claim, no session rename.

## Q1 — Where the Coder templates live

**One directory: `charts/coder/coder-templates/`** — a subfolder of the Coder
wrapper chart, one folder per template, folder name = server-side template name
(the established layout from `2026-10-feat-coder-workspace-rebuild`):

```
charts/coder/coder-templates/
├── kubernetes/
│   ├── main.tf            (17.4 KB)
│   └── terraform.tfvars   (708 B)
└── kubernetes-hardened/
    └── main.tf            (18.7 KB)
```

- Layout law: `.agents/plans/2026/2026-10-feat-coder-workspace-rebuild/chunks/C03.md:5` —
  "the folder name under `coder-templates/` is what `coder templates push --path`
  targets; nothing in the chart or ArgoCD references the folder."
- **Trigger paths**: `charts/coder/coder-templates/**` (both subfolders). No
  `.tftpl` / `.coder.hcl` / `README.md` files exist — each template is a single
  pure-Terraform `main.tf` using the `coder/coder` provider (`required_providers`
  at `kubernetes/main.tf:2-12`, `kubernetes-hardened/main.tf:64-72`).
- **No `.terraform.lock.hcl` in either folder** (`ls -la` verified 2026-11-25).
  `coder templates push` has an `--ignore-lockfile` flag for exactly this
  (Coder docs, v2.39 — see Q5); the pipeline must pass it or accept the warning.
- `terraform.tfvars` (kubernetes only) header comment
  (`charts/coder/coder-templates/kubernetes/terraform.tfvars:1-13`): "The coder
  CLI auto-loads terraform.tfvars on `coder templates push`, so this file is
  the GitOps single source of truth for those values." It pins
  `opencode_version = "2.0.22"`, `openchamber_version = "2.1.0"`,
  `kilo_cli_version = "7.7.7"` (lines 11-13).
- **Terraform variables per template** (the surface `--var` can supply):
  - `kubernetes`: `use_kubeconfig` (default `false`, main.tf:18), `namespace`
    (**required, no default**, main.tf:32), `shared_pvc_name` (default
    `dev-shared`, main.tf:37), `opencode_version` (default `2.0.22`, main.tf:43),
    `openchamber_version` (default `2.1.0`, main.tf:49), `kilo_cli_version`
    (default `7.7.7`, main.tf:55).
  - `kubernetes-hardened`: `use_kubeconfig` (default `false`, main.tf:69),
    `namespace` (**required, no default**, main.tf:83). Everything else is
    `data "coder_parameter"` (runtime workspace inputs: `cpu`/`memory`/
    `home_disk_size`/`repos`) — not Terraform variables, so not `--var`-able.
- Template-to-cluster affinity (from in-file comments, not a hard binding):
  - `kubernetes` references the `dev-shared` SeaweedFS PVC, which "exists only
    on the gpu cluster" (`kubernetes-hardened/main.tf:20-22` calls this out),
    and `2026-10-04-dep-update-opencode-openchamber.md:23` says "The template
    source lives server-side (coder.spencerslab.com)" → legacy template is
    managed against the **gpu** Coder.
  - `kubernetes-hardened`'s header (main.tf:44-63) says `namespace` "must name
    the namespace that holds the git-auth secrets (github-pat, forgejo-token —
    rendered by `services/dev/prod`)" and "verified on dev 2026-10-20" → the
    hardened template is managed against the **dev** Coder.
  - Whether both templates are pushed to both servers is not documented anywhere
    in the repo (see Open questions).
- Historical push was **user-owned, manual**:
  `2026-10-feat-coder-workspace-rebuild/PLAN.md:8` ("Pushing templates to the
  Coder server (`coder templates push`) … user-owned"), and the exact recorded
  command in `2026-10-19-feat-coder-workspace-fusion.md:109`:
  `coder templates push <name> --directory charts/coder/coder-templates/kubernetes-hardened`
  (followed by `coder templates edit <name> --default-ttl 168h`). Note the
  modern CLI flag is `--directory` (older docs/prose say `--path`; the repo
  uses the `--directory` spelling in its 2026-10-19 plan).
- Chart side: `charts/coder/Chart.yaml` — wrapper v1.0.9, appVersion 2.35.2,
  dependency on official `coder` chart **2.38.2** from `https://helm.coder.com/v2`.
  `coder-templates/` is deliberately excluded from the packaged tgz
  (`2026-10-feat-coder-workspace-rebuild/PLAN.md` "chart packaging guard"
  command, expected count `0`).

## Q2 — Coder deployment in this repo (the push targets)

**Two live Coder instances**, both in namespace `default`:

| | dev cluster | gpu cluster |
|---|---|---|
| Access URL | `https://coder.dev.scifi.farm` | `https://coder.spencerslab.com` |
| URL source | `charts/coder/templates/secret-coder.yaml:14` renders `CODER_ACCESS_URL: "https://coder.{{ $.Values.subDomain }}.{{ $.Values.domain }}"` with `subDomain: dev` (`services/dev/prod/values.yaml:18`) | same template line; gpu `subDomain` empty → plain `coder.spencerslab.com` |
| Wildcard (workspace apps) | `*.dev.scifi.farm` (`services/dev/prod/values.yaml:230-234`, cluster-wildcard-cert) | `*.spencerslab.com` (`custom-values/gpu/prod-values.yaml:44-46`) |
| Chart wiring | internal chart `charts/coder` wrapper — appset entry `services/dev/prod/values.yaml:100-102` (`coder: namespace: default`); wrapper slice `services/dev/prod/values.yaml:215-235` | external chart `coder` **2.38.2** from helm.coder.com — `services/gpu/prod/values.yaml:140-143`; ingress `services/gpu/prod/values.yaml:187-196` (`serviceName: code`) |
| Ingress entry | `services/dev/prod/values.yaml:144-147` (`clusterBase: true`) | `services/gpu/prod/values.yaml:187-196` |
| Bitwarden ids | `custom-values/dev/prod-values.yaml:42-60` (`coder-sso-secret d07b1bec…`, `coder-pg 47d1d689…`, `coder-external-auth e04af1ad…`, `coder-token-encryption 4a7b0218…`) | `custom-values/gpu/prod-values.yaml:5-22` (`coder-sso-secret 6052ca6f…`, `coder-pg e197f717…`, `coder-external-auth 487e0cbc…`, `coder-token-encryption a59487dd…`) |
| Cluster API host | `https://cluster.dev.scifi.farm` (`scripts/argocd-fanout.json`) | `https://cluster.gpu.spencerslab.com` (same file) |
| Workspace git-auth secrets | `services/dev/prod/templates/secret-forgejo-token.yaml` (ExternalSecret `forgejo-token`, namespace `default`, consumed by kubernetes-hardened — its own header comment), plus `secret-github.yaml`, `secret-github-mcp.yaml` | — (legacy template needs none) |
| Secrets into coderd | `charts/coder/templates/secret-coder.yaml` (ExternalSecret `coder-secrets`: PG DSN, `CODER_ACCESS_URL`, OIDC, external-auth, `CODER_NO_FEATURE_WARNING=true`) + `secret-coder-db.yaml` + `pg-coder.yaml` (CNPG) | same chart templates |

- **infra cluster: no Coder** — `grep -ri coder services/infra/` returns nothing.
  The card's Services checklist (dev/gpu/infra) thus relates to Coder on **dev
  and gpu only**.
- `coderd` runs with the coder CLI inside its container (both
  `services/*/prod/values.yaml` coder blocks comment: "The coderd container also
  ships the coder CLI"), which is the precedent for the *server-side* version,
  not for the CI leg.

## Q3 — `.forgejo/workflows/` conventions (five shipped files)

`.forgejo/workflows/`: `builder-bootstrap.yaml`, `containers-build.yaml`,
`main-sync.yaml`, `release.yaml`, `renovate.yaml`.

**ROLE guard law** (AGENTS.md Hard rules + per-file headers):
- `ROLE` is a repo-scoped variable, comma list without spaces over
  `{dev, prod}`; guards test membership with `contains(vars.ROLE, '<role>')`
  (case-insensitive substring; a hand-typed value that errors would fail the
  job, so the shape is chosen to never error).
- **Per-file unset polarity, two deliberate classes**:
  - *widens on unset* (builder class): `containers-build.yaml:95,152,359` —
    `vars.ROLE == null || contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')`.
  - *narrow on unset* (fail-safe; everything that publishes/mints/commits):
    `main-sync.yaml:49,70,102`, `renovate.yaml` (job `if: contains(vars.ROLE, 'dev')`),
    `release.yaml` (every job `contains(vars.ROLE, 'prod')`),
    `builder-bootstrap.yaml` (`contains(vars.ROLE, 'prod')`).
- Substring caveat (containers-build.yaml:10-11): no future role word may
  contain `dev`/`prod` as substring.
- A new "publish to external service" workflow belongs to the **narrow-on-unset**
  class (same posture as release/renovate/builder-bootstrap).

**Triggers & path filters (as shipped):**
- `containers-build.yaml:72-88`: push main + `paths: ['containers/**']`, PR main
  + same paths, `workflow_dispatch` with a `containers` input (comma list, empty
  = no-op). Change detection is a **job** (detect-changes, `fetch-depth: 0`
  checkout, `scripts/forgejo-container-detect.sh` diffing `before..sha` trees)
  feeding a matrix — the house pattern for "only run when X changed".
- `main-sync.yaml:42-45`: push main (no path filter), `workflow_dispatch`.
- `release.yaml:28-32`: push main + `paths: [charts/**]`, detection job with
  first-push (`before` empty/all-zero) fallback to `HEAD^..HEAD`.
- `renovate.yaml:42-45`: `schedule: cron '17 6 * * *'` + `workflow_dispatch`;
  runs in a `container: image: ghcr.io/renovatebot/renovate:44.181.5` job
  (immutable full-patch pin, digest recorded in comment).
- `builder-bootstrap.yaml`: `workflow_dispatch` only, no inputs.
- `concurrency: cancel-in-progress: false` on containers-build (queue, never
  cancel mid-matrix); release's bump job uses a best-effort concurrency group.

**Secrets/vars consumption pattern:**
- Endpoints as **repo vars**, credentials as **repo/org secrets**, mapped into
  job/step `env:` only — never interpolated into `argv` (main-sync.yaml:62-63,
  83-84, 112; `scripts/argocd-fanout.py` docstring: "Tokens arrive ONLY as the
  ARGOCD_SYNC_TOKENS environment variable — never argv, never files").
- `FORGE_PUSH_TOKEN` (human-minted non-admin `write:package` PAT) for registry
  pushes (containers-build.yaml:199; release.yaml forgejo-publish job);
  `PUSH_TOKEN_GH`/`PUSH_TOKEN_DEV` + `PUSH_URL_GH`/`PUSH_URL_DEV` (main-sync);
  `PUSH_TOKEN_GH` also serves the GitHub release leg (release.yaml);
  org-level `ARGOCD_SYNC_TOKENS` (owner ruling 2026-11-23 — org-scoped key
  hygiene; a repo key of the same name must never exist).
- Instance hosts are **derived at runtime** from `forgejo.server_url` /
  `GITHUB_SERVER_URL` env, never literals (containers-build.yaml:187-199;
  release.yaml: "no instance URL literal enters the synced file (D14)").
- `forgejo.event_name` / `github.event.*` context (Forgejo exports the
  GITHUB_* compatibility family; containers-build.yaml:136-138).
- Fork-head PRs get empty secrets + read-only token → PR legs work for
  same-repository PRs only (containers-build.yaml:69-70).

**Runner labels / job images:**
- Jobs schedule `runs-on: ubuntu-24.04` (builder-bootstrap: `ubuntu-22.04` —
  the paradox-breaking public label). The labels map to the
  **`containers/forgejo-runner`** baked image (four act-24.04-family labels +
  bootstrap label; `charts/forgejo-runner/values.yaml:115-131`).
- Lab runner: capacity 1, 30-minute job ceiling (containers-build.yaml:60-62).
- No action steps beyond `actions/checkout@v7` — "the instance's mirror
  inventory beyond actions/checkout is unproven" (containers-build.yaml:67-70);
  steps are plain shell with `set -euo pipefail`.

## Q4 — Runner image facts (`containers/forgejo-runner`)

`containers/forgejo-runner/Dockerfile`:
- Base: `ghcr.io/catthehacker/ubuntu:act-24.04@sha256:7bf3…d721` (digest-pinned,
  line 52) with inherited git/git-lfs, jq, python3, node 20+24, yq,
  docker CLI + buildx + compose, apt (header lines 8-13).
- Baked at image build time: **helm 3.22.1** (digest-pinned tool stage,
  lines 49-59) and **chart-releaser 1.10.1** (lines 50-65), with
  binary sha256 anchors verified in a RUN (lines 98-101).
- **The coder CLI is NOT present.** No coder binary, no coder stage, no
  `coder` reference anywhere in the Dockerfile. A workflow step must either
  fetch it at run time or a bake must be added to this image (see Gotchas).
- Egress caution baked into history (Dockerfile:25-33, release.yaml D33 note):
  the runner's egress lane has a **targeted upstream filter that killed
  `get.helm.sh` downloads at run time** (three identical TLS exit-35 failures),
  which is why tools are baked. A run-time `curl https://coder.com/install.sh`
  is the same flaky-egress class and should be treated as a risk, not a
  default.

## Q5 — `coder templates push` mechanics (Coder docs, v2.39 mainline)

Sources: `https://coder.com/docs/reference/cli/templates/push`,
`https://coder.com/docs/admin/templates/managing-templates/change-management`,
`https://coder.com/docs/reference/cli/templates/versions` (fetched 2026-11-25).
The docs are v2.39 mainline; this repo runs coderd 2.35.2 / chart 2.38.2 —
flag the small version gap to the planner.

- **Invocation**: `coder templates push [flags] [template]` — positional
  template name is optional when `--name` is given.
- **Auth env**: the docs CI/CD section exports **`CODER_URL`** and
  **`CODER_SESSION_TOKEN`** (change-management page, "Coder CLI" section). The
  traditional env name `CODER_TOKEN` is what older Coder versions/`coder login`
  use; verify the accepted name against the pinned CLI version before relying
  on one (Open question).
- **Directory**: `-d, --directory` (default `.`; `--path` is the legacy
  spelling the repo's 2026-10-19 plan already migrated off).
- **Variable supply** — the card's parameterization mechanism:
  - `--variable` / `--var` (string-array): "Specify a set of values for
    Terraform-managed variables" → `--var namespace=default --var
    use_kubeconfig=false …`.
  - `--variables-file`: explicit tfvars file; the `terraform.tfvars` in the
    template dir is auto-loaded (repo precedent, Q1).
  - Resolved values **persist server-side** and override `default` on later
    versions (repo comment, `terraform.tfvars:3-7`, citing
    coder.com/docs/admin/templates/extending-templates/variables) — so a
    `--var` set in one push sticks for future versions of that template.
- **What "deploy" means**: push **creates a new template version and marks it
  active by default** (`--activate`, bool, **default `true`**, push reference).
  There is no separate CLI publish step in the current command set;
  `coder templates versions {list,archive,unarchive,promote}` is for version
  management afterwards. `-y/--yes` bypasses prompts; `--always-prompt` forces
  them; `--name` sets the version name (docs CI example uses
  `git rev-parse --short HEAD`); `--message` (-m) sets the version message;
  `--ignore-lockfile` suppresses the missing `.terraform.lock.hcl` warning
  (relevant: neither template dir ships one).
- **CLI acquisition** (change-management page): `curl -fsSL
  https://coder.com/install.sh | sh` with optional `--version=X` pin; official
  downloads at coder.com/downloads with SHA-256 checksums. Token creation is
  `coder tokens create` — **default token lifetime 30 days** (docs note),
  cap via server `--max-token-lifetime`; a CI token needs a longer/no
  lifetime or it will silently 401 after a month.
- **Alternative surface** (not the card's ask, but the documented other CI
  path): the `coderd` Terraform provider (`coder/coderd`) with
  `coderd_template` + `tf_vars` + remote state backend (same page).

## Q6 — Which Forgejo instance runs Actions (topology)

`git remote -v` (read 2026-11-25):
- `dev` — `ssh://git@git.scifi.farm:22222/CuratedForest/SpencersLab.git`
  (the **dev Forgejo**, git.scifi.farm; also `spencerslab-dev` →
  `https://git.scifi.farm/CuratedForest/SpencersLab-Dev.git` twin repo).
- `origin` — `https://git.spencerslab.com/CuratedForest/SpencersLab.git`
  (the **infra/prod-stage Forgejo**, git.spencerslab.com — main-sync.yaml:1-6:
  "only the prod-stage one may fan main out to GitHub and to the dev
  instance").
- `upstream` — `git@github.com:OwnYourIO/SpencersLab.git` (GitHub **mirror**,
  fed by main-sync `push-gh`).

So the workflow file is hosted on **both Forgejo instances** (each receives the
synced copy — release.yaml: "Both instances receive the synced copy") and on
GitHub, but:
- **GitHub does not run it**: `.github/workflows/docker-build.yaml` is
  `workflow_dispatch`-only with auto triggers deliberately commented
  (lines 5-21) — the repo's automatic pipelines are Forgejo-owned.
- The **ROLE guard decides which instance actually executes** (Q3 law). The
  dev instance's Actions runner is `forgejo-runner-dev` in-cluster on the dev
  cluster; the infra instance's runner was relocated to a **gpu-cluster**
  release `forgejo-runner-gpu` dialing the infra instance over HTTPS
  (`services/dev/prod/values.yaml:115-125` comment block). Both runners can
  reach the public coder hosts (`coder.dev.scifi.farm`, `coder.spencerslab.com`).
- Runner identity/labels are instance-scoped per release
  (`charts/forgejo-runner/values.yaml:55-56`).

## Q7 — Precedent: CI deploying to external APIs

- **`main-sync.yaml` sync-fanout + `scripts/argocd-fanout.py`/`.json`** — the
  closest precedent: a Forgejo Actions job driving **every cluster's ArgoCD
  sync API** with per-cluster bearer tokens from a single org-level secret
  (`ARGOCD_SYNC_TOKENS`), endpoints (11 cluster URLs) in a JSON file, token
  env-only, JWT shape validation at parse time, unset-vault = warn-and-skip
  green vs setup-error = red (main-sync.yaml:28-40, 104-124;
  argocd-fanout.py docstring).
- `renovate.yaml` — token secrets + identity var pattern (Q3).
- `FORGE_PUSH_TOKEN` / `PUSH_TOKEN_*` / `ARGOCD_SYNC_TOKENS` — the
  repo→org→user secret-resolution rule is documented in main-sync.yaml:23-26.
- In-cluster analogue (for contrast, not the CI path): Bitwarden item →
  ExternalSecret → k8s Secret (`services/dev/prod/templates/secret-*.yaml`,
  `charts/coder/templates/secret-coder.yaml`). The card's ask (Forgejo vault)
  is the CI-side twin of this pattern.

## Gotchas

1. **No coder CLI in the runner image** (Q4) → fetch at run time (egress-risk,
   D33 class) or bake into `containers/forgejo-runner` (keeps the "jobs
   install nothing at run time" law; image calendar tag is hand-bumped per
   AGENTS.md). Design choice for the planner.
2. **`namespace` is required with no default** in both templates and has no
   tfvars entry — today it is resolved at workspace-creation time. If the
   pipeline is to supply it via `--var`, the value must come from a Forgejo
   var/secret per cluster; omitting it changes the template's parameter
   behavior.
3. **`--activate` defaults to true**: every content-change push becomes the new
   active version — the desired "deploy on change" semantics, but note the
   `kubernetes-hardened` header's user-owned `--default-ttl 168h` edit is a
   separate `coder templates edit` action (2026-10-19 plan line 109) that a
   push does not re-apply and would need re-assertion if it can drift.
4. **Missing lockfile warning** (Q1) — pass `--ignore-lockfile` or the warning
   lands in every run log.
5. **Token lifetime**: default 30 days (Q5); the CI token must outlive that or
   the pipeline 401s monthly.
6. **PR trigger caveat**: fork PRs carry empty secrets (Q3); a PR push leg is
   same-repo PRs only. Whether a PR should push template versions at all (vs
   main-push-only + dispatch escape hatch, the containers-build shape) is a
   plan decision.
7. **Unchanged content**: whether the CLI no-ops when the pushed content is
   byte-identical to the active version is not verified from docs — treat
   "every push mints a version" as the safe assumption.

## Open questions (for the planner — not resolved here)

1. **Push target**: one Coder endpoint (which — dev `coder.dev.scifi.farm` or
   gpu `coder.spencerslab.com`?) or both, and does each template go to its
   "home" instance only (Q1 affinity evidence) or both instances? The card's
   "coder endpoint … from a variable" reads singular, but the repo has two
   live Coder instances and two templates.
2. **Trigger scope**: main-push-only (with `workflow_dispatch` escape hatch,
   the house shape) vs also PRs — and which ROLE class executes the publish
   (dev vs prod instance; the narrow-on-unset class is the fit).
3. **CLI acquisition**: fetch at run time from coder.com/install.sh vs bake
   into `containers/forgejo-runner` (Gotcha 1); if baked, the image calendar
   tag is hand-bumped per repo law.
4. **Env name**: `CODER_SESSION_TOKEN` (docs CI snippet) vs `CODER_TOKEN`
   (legacy) — pin to the CLI version chosen.
5. **Var/secret naming in the Forgejo vault**: which vars supply
   `namespace`/`use_kubeconfig`/the version pins per target, and which secret
   holds the token (per-instance vs one shared token with two URLs)?

## Round 2 (2026-11-26) — upstream marker law + build-charts rename

Grounded 2026-11-26 by `agent-explore` (read-only), on the catch-up merge
`00cedcd1e` (main tip `52d3b5c45`, cf-55 r4). Scope: the UPDATED
`containers-build` marker machinery, the cf-6 ruling that produced it, the
`release.yaml` -> `build-charts.yaml` rename surface, and what an adaptation
of the AD-56 pipeline concretely needs. Round 1's `Q3` file inventory is
corrected below where the merge moved it.

### R2-Q1 — `.forgejo/workflows/containers-build.yaml` at current branch: the marker machinery end to end

**What the marker IS.** A branch ref on the executing repository,
`refs/heads/ci/containers-built` (a head, not a tag — a moved tag would need
a force-push, violating the every-push-plain law and losing git's
fast-forward monotonicity; cf-6 plan `2026-11-25-feat-containers-built-marker.md:32-39`). Header law
`containers-build.yaml:20-23`: "The last-built marker belongs to no registry:
it is a commit ref on this repository, advanced by the workflow itself after
a fully-green push build, and it gates nothing — it only says where the
already-published history ends." It is read via `git ls-remote origin` and
written via `git push origin` — i.e. always against the **executing
instance's own repo** (see R2-Q5 for the multi-executor consequence).

**How it is READ (resolver step, `containers-build.yaml:133-165`).** A
dedicated step `id: marker` inside `detect-changes`, before the detect step:
- non-push events: emit empty `sha=` and exit 0 (`:139-146`) — the marker is
  push-side only; a missing output key would reach `detect()` *unset* rather
  than empty, and empty `MARKER_SHA` is exactly the payload-arm fallback
  state.
- `marker=$(git ls-remote origin refs/heads/ci/containers-built | cut -f1)`
  (`:147`); empty (ref absent) → emit empty `sha=` and exit 0 — the
  bootstrap fallback to `before..sha` (`:148-153`).
- value must match `^[0-9a-f]{40}$` or the step fails naming the value
  (`:154-157`).
- reachability: `git cat-file -e "$marker^{commit}"` against the
  `fetch-depth: 0` checkout; unreachable (orphaned by a history rewrite) →
  `exit 1` with the owner verbs: "reset the marker ref to a reachable commit
  or delete it to fall back" (`:158-164`) — a silent downgrade to
  `before..sha` is refused because it would re-open the hole the marker
  exists to close.

**What ADVANCES it and exactly WHEN (`advance-marker` job, `:464-483`).**
- Guard `:465`: `forgejo.event_name == 'push' && needs.build-release.result ==
  'success'` — push events only (PR excluded by the event test; dispatch
  excluded the same way), and only when the whole `build-release` matrix
  published green (with `fail-fast: false`, `result == 'success'` means every
  cell green; a skipped matrix — the empty-changed-set case — is
  `'skipped'`, not `'success'`, so **empty-set runs do NOT advance**; cf-6
  plan design 4, `2026-11-25-feat-containers-built-marker.md:80-82`: "provably
  harmless: tree(marker)==tree(sha) over containers/ makes the next run's
  range content-equivalent").
- `needs: [detect-changes, build-release]` (`:466`); checkout
  `fetch-depth: 0` with the push-negotiation comment ("A one-commit shallow
  clone cannot negotiate a non-force push (the main-sync and release
  precedent)", `:470-473`).
- The advance is one plain push, `:474-483`:
  `git push origin HEAD:refs/heads/ci/containers-built` — no force flag
  anywhere; `:476-482` comment: "git's own non-fast-forward refusal is the
  monotonicity law, so a queued or rewound run that lands behind the marker
  fails this job loudly instead of moving it backwards. The non-FF shape is
  the advance contract, not a retry case."
- **Auth (header `:44-48`)**: "The marker ref is the one write here that wears
  no PAT: it is a branch of this repository, so the checkout's own same-repo
  credential pushes it (the release.yaml idiom), and it stays Forgejo-local —
  main-sync mirrors refs/heads/main alone, so GitHub never receives the
  marker and the registry PATs are never marker credentials." No secret
  reference anywhere in the job (cf-6 DECISIONS 2026-11-25: "no new secret",
  L23). Note the in-file comment still names the *pre-rename* idiom file
  ("the release.yaml idiom", `:46`) — a frozen historical reference, textually
  pinned by the upstream suite (`tests/services/forgejo-containers-build.sh:1285`
  pins that exact string) — not a live pointer.

**The fallback ladder (header `:50-71` + detect step `:166-205` + script
`scripts/forgejo-container-detect.sh:51-80`).** In priority order, push arm:
1. empty `before` → `die` first and unconditional (A5 payload sanity, script
   `:52-58`) — "no real push payload sends one";
2. `MARKER_SHA` non-empty → base = marker (`a="$MARKER_SHA"`, `:63-66`):
   "the payload before can name a range a dead or cancelled run already lost,
   and re-diffing it is the heal this base exists for";
3. all-zero `before` (first push to a branch) → tip-only `HEAD^..HEAD` with a
   `::warning::` line naming the narrowing (script `:67-75`; header
   `:60-62`);
4. otherwise → `before..sha` (script `:76-79`).
An orphaned marker that survives to the script dies 128 through the unmasked
`git diff` (script `:90-94` carries no `|| true` / no masking redirect; cf-6
plan design 2, t15/d19 posture). PR arm: `git merge-base BASE_SHA HEAD_SHA`
(`:38-49`) — the marker never feeds a PR build.

**Empty-set / warning semantics per case (detect step `:190-205`).** The
decision lives in the **workflow step**, not the script (a round-2-relevant
shape change — see R2-Q2):
- empty push set **with a present marker** → one plain info line: "changed set
  verified empty: marker..sha (marker=… sha=…) — nothing was missed between
  the marker and this run" — no `::warning::` (the marker *proves* nothing
  was missed; cf-6 plan design 3, `…-containers-built-marker.md:61-67`);
- empty push set with `before != sha`, or any empty PR set →
  `::warning::changed set resolved empty … both build arms will skip`;
- no-op ref update (`before == sha`) → silent (the `:202` exemption);
- dispatch → always silent (it names its own build set; an empty list is its
  documented no-op intent, `:190-196`);
- header `:69-71`: nothing reads `event.commits`/`total_commits` — the Actions
  push payload leaves `total_commits` at 0.
Also: "a green run that built nothing must read differently from one whose
range silently resolved to nothing" (`:183-185`); the verdict echo names
event, endpoints and `marker=` (`:186`). No `::notice::` is emitted (runner
v13.2.0 does not interpret it — cf-6 plan OQ-3).

**Events the marker does NOT advance on:** pull_request (event test),
workflow_dispatch (event test), empty-set push runs (skipped matrix ⇒ skipped
dependent), any run whose matrix is not fully green. The dispatch escape
hatch "names its own set and NEVER advances the marker" (cf-6 plan out-of-
scope, `…-containers-built-marker.md:18`).

### R2-Q2 — `scripts/forgejo-container-detect.sh` current form, and the delta vs `scripts/coder-template-detect.sh`

**Inputs (env/argv, doc header `:2-20`):** `detect` reads
`EVENT_NAME` (push|pull_request|workflow_dispatch), `EVENT_BEFORE`, `SHA`,
`MARKER_SHA` (read-only here — "The container-build workflow resolves and
validates MARKER_SHA; this script only reads it, and an empty value is the
bootstrap fallback to before..sha", `:13-17`), `BASE_SHA`/`HEAD_SHA`,
`MANUAL_CONTAINERS`; `next-n` reads `YYMM` + stdin tags JSON; `sanitize`
takes argv. `die()` exits 2 (`:24-27`).

**Push-arm decision tree (`:51-80`)** — empty-before `die` first and
unconditional; then **marker wins if non-empty** (`base_src='marker'`,
`:63-66`); then all-zero `before` → tip-only `HEAD^..HEAD` + `::warning::`
(`:67-75`); else `before..sha` (`base_src='before'`, `:76-79`). The range
echo goes to stderr *before* the git call and now carries the stable
`base=marker|before|tip-only` token (`:82-89`). Output: stdout exactly one
JSON array; the `containers/` dirs must pass the DNS-safe-name + `Dockerfile`
gate (`:98-107`).

**Delta vs our `scripts/coder-template-detect.sh` (decision tree, line-precise):**

| | upstream `forgejo-container-detect.sh` | our `coder-template-detect.sh` |
|---|---|---|
| events | push, pull_request, workflow_dispatch (`:32-49`) | push, workflow_dispatch only — no PR arm by OQ2 ruling (header `:10-13`) |
| inputs | 7 env keys incl. `MARKER_SHA` (header `:13-17`) | 4 env keys: `EVENT_NAME`, `EVENT_BEFORE`, `SHA`, `MANUAL_TEMPLATES` — **no `MARKER_SHA`** |
| push base selection | empty-before die → **marker** → tip-only → before (`:51-80`) | empty-before die → tip-only → before (`:37-58`) — **no marker arm** |
| base-source echo | `detect: range %s..%s (event %s, base=%s)` token (`:88-89`) | `detect: range %s..%s (event %s)` — no base token (`:63`) |
| empty-set warning | **workflow-step-owned** (YAML `:190-205`), marker-aware exemption | **script-owned** via the `exempt` flag (`:29-35`, `:58`, `:86-92`) — the C03-documented inversion (our `STATE.json` L126 handoff: "detector owns the empty-set warning (inverted vs containers-build), documented in the step comment") |
| dispatch empty-set | always silent (names its own set) | silent only when the list is empty (`:35`); a list whose names all fail the gate **warns** (`:87-88`) — a divergence the upstream shape does not have |
| before==sha no-op | silent (`:202`) | silent (`:58`) — same |
| marker-empty (verified) | plain info line, no annotation (YAML `:200-201`) | **no such case exists** |
| path gate | `containers/` + `Dockerfile`, `cut -d/ -f2` (`:94-95`, `:101-105`) | `charts/coder/coder-templates/` + `main.tf`, `cut -d/ -f4` (`:68-69`, `:76-83`) |
| subcommands | `detect` \| `next-n` \| `sanitize` (`:153-161`) | `detect` only (`:105-108`) |
| die contract | exit 2, stderr-prefixed (`:24-27`) | exit 2, stderr-prefixed (`:15-20`) — identical shape |

### R2-Q3 — `.agents/plans/2026/2026-11-cf-6-debug-detect-rerun/`: the ruling that produced the marker law

**The failure story being fixed** (DECISIONS.md):
- 2026-11-24 (L7): owner report "for PRs and/or reruns of jobs, the build
  stops detecting a change and doesn't build the container." Scout
  decomposition (L12): **A** trigger over-fire from Forgejo's stale stored
  `merge_base` in PR path-filters + the by-design empty-PR no-vacuity warning
  — a wall of *legitimately-empty* runs that look like failure; **B** the
  Nov 23 06:36 batch that died at 0s in the runner-down era — a dead run
  consumes the payload's `before..sha` range and the lost build is "skipped
  forever" (delivery loss); **C** Nov 24 PRs that detected fine but failed IN
  the build (a separate auth-gated class).
- 2026-11-25 (L9): the owner re-integrated AD-133 commits onto main
  (rebase/replay + push) and container work landed "but nothing detected as
  needing a build"; the owner states the constraint: "would prefer something
  that supports my current workflow" (re-integrate + push, not PR/squash).
  Forensics verdict (L11): that specific event netted zero legitimately
  (add-then-remove within one range) — the real class is **DELIVERY LOSS**
  (research R1: dorny#314 / nx-set-shas describe the owner shape verbatim;
  R4: PR/squash do NOT fix it).
- Ruling (batched round, L14): **Q1 = O2 — last-built marker diff** ("every
  run diffs marker..sha — delivery loss heals on the NEXT push, the
  researcher's noted weakness being the accepted price"); **Q3 reframe: "the
  trigger is ok, what it detects is incorrect"** (the paths-filter wake
  stays; the *range input* changes); **Q2 = marker initialization via a
  one-time full publish** (order matters: publish → marker=tip); **Q4 = the
  Forgejo side is source of truth** — the marker ref lives on the Forgejo
  repo, Forgejo-local (main-sync mirrors `refs/heads/main` alone); **Q5 = no
  upstream Forgejo issue** (over-fire stays as noise; under marker semantics
  a spurious wake costs only one ref read + an info exit).
- **Re-run law audit** (plan design 7, `…-containers-built-marker.md:111-121`;
  DECISIONS L26): a re-run of a *fully succeeded* push run now diffs
  marker..sha with the marker advanced ⇒ empty info-exit — re-run
  idempotence is **REPLACED by marker-monotonicity** (verify, not
  republish); failure-class re-runs keep the old behavior exactly; the PR arm
  is byte-preserved. Owner-accepted-knowing.
- **Self-initialization law** (plan design 5, `:83-94`): the first green push
  run after the code merge **auto-creates the marker at its sha** (branch
  creation is trivially allowed; its own diff base was `before`, the old law
  — sound coverage); pre-merge the marker is inert (no accessor); post-merge
  pre-init the resolver finds it absent and runs the byte-exact shipped
  fallback ("EITHER ORDER IS SAFE — proved"; d18 is the regression pin).
- **"Adopt for other workflows" guidance: none exists.** The ruling is
  scoped to `containers-build` (Q1 is that pipeline's option; the x5 docs
  trio pins *that* pipeline's detection contract in SKILL.md /
  overview.md / AGENTS.md). The AGENTS.md hard rule states the marker law as
  `containers-build`'s detection (cf-55 r4, our DECISIONS.md 2026-11-26
  entry L82-87). Adopting the shape into the AD-56 pipeline is this round's
  owner instruction, with the cf-6 mechanism as the precedent — the planner
  is not bound by any cross-workflow adoption directive from cf-6.

### R2-Q4 — the `release.yaml` -> `build-charts.yaml` rename surface: exact stale references

Rename state at current branch (measured): `.forgejo/workflows/` contains
`build-charts.yaml` and **no** `release.yaml`; `tests/services/
forgejo-release.sh` is gone, replaced by `tests/services/
forgejo-build-charts.sh`; `tests/services/forgejo-ci-surface.sh:107` carries
the fence asserting `release.yaml` is absent from the GitHub workflows dir;
`tests/services/forgejo-containers-build.sh:2570` notes "releases moved to
.forgejo/workflows/release.yaml, since renamed build-charts.yaml"; the docs
trio (overview.md / AGENTS.md / container-creation SKILL.md) carries **zero**
`release.yaml` references (grep-measured 2026-11-26). `build-charts.yaml`
itself: the chart bump+publish pipeline (prod instance the single
chart-version authority; Y.M.N calendar `Chart.yaml` bumps committed to
Forgejo main; DUAL publish GitHub Releases + gh-pages index AND the instance
Helm package registry; narrow-on-unset ROLE guards, header `:1-31`, `:38`).

**Our four landed artifacts — stale references:**
1. `.forgejo/workflows/coder-template-push.yaml`
   - **L11**: "the `release.yaml` fail-safe class" → stale, now
     `build-charts.yaml`.
   - **L188**: "(the `release.yaml` class)" (the D43-posture comment on the
     `coder version` toolchain check) → stale, now `build-charts.yaml`.
   - **L31-43** (the `Detection.` header paragraph): accurate as a
     description of *our* detector today, but it describes the pre-marker
     convention and stays silent on the marker law — must be reworded in the
     same change set if the marker is adopted (the x5-parity shape: header +
     script doc header + docs reworded together).
2. `scripts/coder-template-detect.sh`
   - header **L6-13**: the input list has no `MARKER_SHA`; the doc carries no
     marker semantics — stale upon adoption.
   - the push arm **L37-58**: no marker branch, no `base=` echo token —
     stale upon adoption. (No `release.yaml` references in either script —
     grep-measured.)
3. `scripts/coder-template-push.sh` — **no stale references** (its
   `main-sync.yaml` unset-vault posture citation, L10-11, remains valid).
4. `.agents/notes/2026-11-25-coder-template-push.md` (runbook)
   - **L50**: "the `release.yaml` fail-safe class" → stale, now
     `build-charts.yaml`.
   - **L88-95** (§2 detection text: "the detect job … runs … and feeds the
     matrix; … the detector's own exemption arithmetic: a no-op ref update
     and an empty dispatch list stay silent, every other empty set warns")
     → describes the pre-marker contract — reword upon adoption (and the UA
     legs carry no marker-bootstrap section — see R2-Q5).
   - The other `containers-build.yaml` citations (L47, 67, 81, 166, 276)
     remain valid (the name is unchanged).

**Plan / DECISIONS / chunk / STATE text (historical surfaces):**
- plan file `2026-11-25-feat-forgejo-coder-template-pipeline.md` **L64**
  ("`release.yaml` fail-safe class") — historical; **superseded by the C04
  replan** (DECISIONS 2026-11-26: "`plan_status` -> needs-replan until the
  reworked plan lands"). No in-place fix required.
- `DECISIONS.md` **L49** ("the `release.yaml` posture") — append-only history;
  L82-88 already records the rename. No in-place fix.
- `chunks/C02.md` L42/L244, `chunks/C03.md` L25/L302, `STATE.json` L126 —
  historical records, superseded by the C04 rework. No in-place fix.
- This file's round-1 `Q3` (L100-101 file inventory incl. `release.yaml`;
  L121-124 the pre-merge `containers-build` detect description; the guard
  line numbers L95/152/359, now L110/208/415) — corrected by this section.

### R2-Q5 — What an ADAPTATION of coder-template detection would concretely need

**Marker ref name candidate, scheme-consistent.** `refs/heads/ci/
coder-templates-pushed` — following the upstream naming scheme
(`ci/` prefix under the `refs/heads` namespace — chosen in cf-6 over
`refs/ci/*` because custom-namespace push support on Forgejo 15.0.10 could
not be grounded at agent tier while `refs/heads` pushability is proven
in-repo; domain + past-tense verb, mirroring `ci/containers-built` with our
pipeline's own verb). The name must be named in **no other `.forgejo`
workflow** (upstream t16 asserts ref exclusivity; our candidate is unique —
grep-measured: `ci/containers-built` appears in no other workflow file).
Tags are rejected by the every-push-plain law (cf-6 plan design 1, `:32-39`).

**Multi-executor: the upstream scheme handles it by construction — the
marker is a branch of the LOCAL repo, and state is per-instance.**
- The marker is read `git ls-remote origin` and written `git push origin` —
  i.e. against the executing instance's own repository (header `:44-48`
  "Forgejo-local"; main-sync pushes `HEAD:refs/heads/main` only,
  `main-sync.yaml:67,88` — the marker is never mirrored to the other
  instance or to GitHub).
- Upstream in practice advances from a **single effective executor**:
  `advance-marker` requires `build-release` success, and `build-release` is
  prod-role-guarded (`:208`) — the dev-role instance runs only the PR arm,
  which the marker never feeds.
- Ours: **both** Forgejo instances execute the push leg (OQ1 ruling: the
  guard matches `dev` and `prod` alike, each pushes every changed template to
  its OWN Coder; `coder-template-push.yaml:107,159`). Adopting the scheme
  verbatim, each instance advances a marker in its own repo: the dev
  instance's marker = last green push to the dev Coder, the infra instance's
  marker = last green push to the gpu Coder. Since the two Coder servers are
  independent consumers, **per-instance "last published" state is the correct
  semantics** — no cross-instance mirror is needed or wanted. The dev
  instance receives main via the main-sync fan-out push (a normal push event
  on the dev repo, with its own `before` payload), so `marker..sha` on the
  dev repo works identically.
- Each instance's marker **self-initializes on its first green push run**
  (the cf-6 design-5 auto-creation property, `…-containers-built-marker.md:83-94`);
  until then the resolver finds it absent and runs the byte-exact current
  `before..sha` fallback (the d18 "fallback == today" shape). No full-fleet
  bootstrap is needed for us (the templates are already live on both Coders;
  cf-6's B1/B2 owner legs existed to initialize *containers-build* history,
  not a precondition we inherit).
- One asymmetry to name in the plan: an over-running stale queued run is
  "harmless" for image builds (a re-minted tag, gaps-by-design) but a
  template re-push mints a version and `--activate` re-points the ACTIVE
  version at the stale run's checked-out content. Under the capacity-1
  runner + FIFO queue + `cancel-in-progress: false`, the race is vanishing
  (cf-6 plan Risks: "capacity-1 serialization makes it vanishing. Never
  rewinds the marker (git-enforced)") — but it is not the same-harmless
  class, and a partial-failure re-run re-pushes every template in the range
  (re-minting versions, active re-pointed at identical content — churn on the
  Coder version list, no correctness loss).

**Write-permission needs.** The advance rides the checkout's automatic
same-repo credential (the Actions job token) — **no new secret, no
FORGE_PUSH_TOKEN** (header `:44-48`; cf-6 DECISIONS L23 "no new secret").
Residual (cf-6 plan Risks `:276-280`, OQ-2): the job credential's ability to
push a *non-main* `refs/heads` branch is near-proven, not proven (the proven
case is `refs/heads/main` — the build-charts/main-sync idiom; same ACL class
by reasoning, not by fact). The first live advance run is the proof leg;
fallback = a minted repo-write-scoped PAT with the main-sync URL idiom
(one-line change + suite re-pin).

**Dispatch interaction.** A dispatch fire **never advances the marker**
(`event_name == 'push'` guard; cf-6 plan out-of-scope L18: "the dispatch arm
— unchanged; it names its own set and NEVER advances the marker"). A
dispatch's `templates` input names its own push set — unchanged.

**The tfvars / paths-filter angle is unchanged.** The trigger's
`charts/coder/coder-templates/**` paths filter stays (the cf-6 Q3 reframe:
"the trigger is ok, what it detects is incorrect" — the wake stays, the
*RANGE INPUT* changes); the no-`--var` posture (values ride the in-repo
tfvars, OQ5 ruling) is untouched; the `workflow_dispatch` escape-hatch input
is untouched. Only the diff BASE changes, plus the advance job and its
bootstrap.

**Concrete change set if adopted** (mirroring the upstream shape):
1. a `resolve last-pushed marker` step in `detect-changes` (upstream
   `:133-165` verbatim shape: non-push → empty; `ls-remote`; absent →
   fallback; 40-hex validation; `cat-file -e` reachability with the
   reset-or-delete owner-verb loud fail) — needs the existing
   `fetch-depth: 0` checkout (already present, `:120`);
2. a 7th detect-step env accessor `MARKER_SHA` (upstream `:175`) + the
   `marker=` token in the verdict echo (`:186`);
3. the script: `MARKER_SHA` input + the marker-wins push-arm branch + the
   `base=` echo token (upstream `:63-66`, `:88-89`);
4. an `advance-marker` job: guard
   `forgejo.event_name == 'push' && needs.push.result == 'success'`,
   `needs: [detect-changes, push]`, `fetch-depth: 0` checkout, one plain
   `git push origin HEAD:refs/heads/ci/coder-templates-pushed`, no force, no
   ROLE vocabulary, no secrets (upstream `:464-483` shape);
5. the **warning-law location decision** (a genuine planner call, R2-OQ3):
   upstream moved the empty-set warning from script to workflow step so it
   can see `MARKER_SHA` (step-owned, `:190-205`); our C03 contract
   deliberately inverted that (script-owned `exempt` flag, the documented
   deviation in `STATE.json` L126). Adopt: (a) step-owned, marker-aware
   (retire the documented inversion, mirror the house shape + the t14
   behavioral test half) or (b) script-owned, extending the exemption with a
   marker-verified-empty → info case;
6. the x5-parity reword in ONE change set: workflow `Detection.` header
   paragraph, script doc header, runbook §2 detection text, suite pins.

### R2-Q6 — Upstream tests that pin the marker contract (`tests/services/forgejo-containers-build.sh`, 41→47 legs)

- **t13** (`:922-972`): the **seven** detect-step `env:` accessors are
  byte-exact (textual pin; the 7th = `MARKER_SHA`).
- **t14** (`:1058-1183`): detect-step text pin + a **behavioral half** that
  stages the step run body + the shipped detector into a scratch git repo
  and EXECUTES eight shapes: empty dispatch list (silent), before==sha push
  (silent), real empty push range (warns), real empty PR range (warns),
  non-empty set (silent), **marker-equals-sha** (info: no `::warning::`, no
  `::notice::`, a "verified empty" info line required, and the echo must
  name `marker=`), **marker-verified-empty** (same info posture). Job-log
  legibility only, no UI-chip claim.
- **t15** (`:1195-1239`): `set -eu` stands; no `|| true`, `2>/dev/null` or
  masking redirect on any git call in `detect()` (the `next-n` tolerated
  `grep || true` is the named exemption).
- **t16** (`:1244-1317`): `advance-marker` exists; `needs`
  detect+build-release; `if:` names the push event + build-release success
  (no ROLE vocabulary, no `secrets.`); checkout pins integer `fetch-depth 0`;
  the step body **byte-carries** `git push origin HEAD:refs/heads/ci/
  containers-built` with no force form on any push statement; the ref is
  named in **no other `.forgejo` workflow**.
- **t17** (`:1320-1477`): **executed offline** against a scratch bare remote —
  the resolver emits empty for an absent marker, emits the sha when
  present+reachable, fails LOUD naming the value (with the reset-or-delete
  owner note) for an orphaned marker and for non-hex garbage, and stays
  network-free on pull_request; the staged advance body **creates** the ref
  at HEAD, and the same push against a moved-ahead marker exits non-zero
  with the non-fast-forward refusal named and the ref unmoved
  ("monotonicity executed, not texted").
- **d16** (`:2297-2313`): `MARKER_SHA` set + a differing `before` → the push
  arm diffs marker..sha and the echo names `base=marker`.
- **d17** (`:2316-2331`): marker==sha answers `[]` with exit 0 and stdout
  exactly one JSON line (the quiet re-run semantics).
- **d18** (`:2334-2367`): an empty `MARKER_SHA` reproduces the shipped d9
  fallback **byte-for-byte** on every channel — the "fallback == today"
  pin, green at authoring.
- **d19** (`:2370-2384`): an unreachable `MARKER_SHA` propagates git 128
  with no JSON on stdout through the unmasked diff — the script stays
  independently loud about the new base.
- **x5** (`:2585-2658`): SKILL.md, overview.md and regenerated AGENTS.md
  carry the detection contract **by marker** (the `marker..sha` range law,
  the `before..sha` fallback, merge base, first push, tip-only, announced
  narrowing, `fetch-depth: 0`), with no line over-claiming an annotation
  render.
- **t5** (`:425`): the job set is the build trio **plus at most
  `advance-marker`**; the build jobs `needs` the detect, matrix `fromJSON`
  with `fail-fast: false`, short-circuit on `'[]'`.

**Our suite's current shape (the baseline C04's test wave extends):**
`tests/coder/coder-template-detect.sh` legs l1-l7 (push-range detection;
unrelated path → `[]` + the non-exempt empty-set warning; first-push
tip-only + warning; empty `EVENT_BEFORE` fatal + no `|| true`; dispatch list;
ungated/non-DNS-safe exclusion; the two exempted empties stay silent vs
every other empty set warns); `tests/coder/coder-template-push.sh` legs
w1-w6 (YAML parse; trigger shape; narrow-on-unset guards; concurrency +
matrix + no `container:`; env-only vault; detect/push invocation shape);
`tests/coder/coder-template-push-script.sh` legs p1-p7 (warn-and-skip
greens; the exact argv contract; unknown-template fatal; exit propagation;
the two tfvars pin sets); `tests/notes/coder-template-push-runbook.sh` legs
r1-r6 (runbook posture pins). The mirror shape for the adaptation:
extend l1 with the marker d-legs (d16-d19 analogs), add the
advance-job-shape leg (t16 analog) and the executed-offline monotonicity +
resolver-shapes leg (t17 analog), re-pin the accessor count (t13 analog),
and the behavioral warning-law shapes (t14 analog) if the step-owned shape
is adopted.

### Round-2 gotchas (corrections / new)

1. **Line-number drift after the merge**: round 1's `containers-build.yaml`
   citations (guards L95/152/359; on: L72-88; fork-head note L69-70) were
   against the pre-merge file; current-branch equivalents: guards
   L110/208/415, on: L87-103, the fork-head note L82-85.
2. **The upstream rename left one in-file comment behind**:
   `containers-build.yaml:46` still says "(the release.yaml idiom)" and
   `tests/services/forgejo-containers-build.sh:1285` textually pins that
   exact string — a frozen historical reference, not a live pointer; do not
   "fix" it in our artifacts' citations (it is upstream surface).
3. **Our dispatch empty-set semantics diverge from upstream**: a dispatch
   list whose names all fail the gate **warns** in our script
   (`coder-template-detect.sh:87-88`) but stays silent upstream (the
   dispatch is exempt wholesale, `containers-build.yaml:190-196`). The
   adaptation should keep this divergence or consciously align it — a
   planner decision, not a mechanical carry.
4. **A template over-push is not image-harmless**: see R2-Q5 — the
   queued-run-race asymmetry (`--activate` re-pointing at stale content) and
   the partial-failure re-run re-mint churn are new surface for the plan's
   Risks section; under the capacity-1 FIFO queue they are vanishing but
   should be named.
5. **The pre-init fallback is exactly today's behavior** (d18 shape): the
   adaptation is merge-order-independent-safe both ways — pre-marker runs
   fall back to `before..sha` byte-exactly, so the code can land before any
   live bootstrap, and each instance's first green push run self-initializes
   its marker (cf-6 design 5, "EITHER ORDER IS SAFE — proved").

### Round-2 open questions (for the planner/owner — not resolved here)

1. **Adopt-marker-vs-stay-range**: the owner instruction says "adapt … if
   not already done" — the C02 detector is the pre-marker shape, so
   adaptation is the directive; the residual decision is the scope: full
   mirror of the upstream law (marker + advance job + step-owned warning +
   the re-run-law shift, cf-6 design 7) vs a minimal marker-only backport
   keeping the script-owned warning. The re-run-law shift (a re-run of a
   fully-succeeded push run becomes a verify instead of re-minting a
   version) is user-visible on the Coder servers — confirm it is acceptable
   as the price (cf-6 accepted it knowing).
2. **Marker ref name**: `refs/heads/ci/coder-templates-pushed`
   (scheme-consistent candidate, R2-Q5) vs `refs/heads/ci/
   coder-templates-built` (mirroring the upstream `-built` suffix verbatim)
   vs another owner-chosen spelling (cf-6 OQ-1 pattern: owner-vetoable,
   one string + one pin).
3. **Warning-law location**: step-owned (mirror upstream, retire the C03
   documented inversion, enables the t14-behavioral test shape) vs
   script-owned (extend the `exempt` flag with a marker-verified-empty →
   info case; keeps the documented deviation).
4. **Runbook bootstrap leg**: no full-fleet bootstrap is needed (templates
   already live on both Coders; per-instance self-initialization, R2-Q5) —
   confirm the runbook gets a short "marker bootstrap" note (pre-init
   fallback = today's semantics; first green run auto-creates) instead of a
   cf-6-style B1/B2 owner leg.

## Round 3 (2026-11-26, delta scout) — main r5 merged; the law moved again

Grounded 2026-11-26 by `agent-explore` (read-only, delta round) on the merge
`01d2e3f45` (parents `16df8a38d` this-branch r4-era + `5f5762a19` main r5;
clean auto-merge, no conflicts; head `d68eefb41` the DECISIONS record).
Scope: the r5 delta to the marker law (C14 shared marker + C15
workflow_call orchestration) vs the r4 shape rounds 1–2 grounded, the
post-merge C01 regression facts, the stale-ref sweep, and the r5 suite
mirror shapes. Round 2's `R2-Q1`/`R2-Q2`/`R2-Q5` line citations against
`containers-build.yaml` describe the r4 shape and are superseded below where
r5 moved it.

### R3-Q1 — `main-sync.yaml` r5: the prod-main fan + the aggregate marker advance

**The fan** (`main-sync.yaml:57-60,105-119`): `on:` = push main +
`workflow_dispatch: {}` (no inputs). Jobs `push-gh` (`:63-82`), `push-dev`
(`:84-103`) unchanged in shape; the two builders are now **called**, not
push-triggered: `build-containers` (`:105-111`: `if: contains(vars.ROLE,
'prod')`, `runs-on: ubuntu-24.04`, `uses: ./.forgejo/workflows/
build-containers.yaml`, `secrets: inherit`) and `build-charts` (`:113-119`:
same triple, `uses: ./.forgejo/workflows/build-charts.yaml`; comment `:114-
115`: "Same for the chart builder (marker..sha detection inside replaces the
retired paths filter); its bump_sha output feeds the advance below"). No
`with:` inputs on either call — the called workflows need none (their
detection reads the event payload + the marker). `secrets: inherit` is the
only secret plumbing (the builders' `FORGE_PUSH_TOKEN`/`PUSH_TOKEN_GH`
resolve through the caller's scope; no new secret).

**The aggregate advance** (`:121-158`): `advance-marker` with
`needs: [build-containers, build-charts]` (`:125` — comment `:122-124`:
"needs IS the aggregate rule — both builders green or this job never runs; a
red fan leaves the marker put, so the next fan's marker..sha range still
carries the failed work (re-cover)"), `if: contains(vars.ROLE, 'prod')`
(`:126` — no `always()`, no result function: the plain `needs`-gate IS the
green-fire rule; D59 override of D54's recommendation, cf-55 DECISIONS
L1045-1052). Checkout `actions/checkout@v7` with **integer**
`fetch-depth: 0` (`:129-133`, comment "Push negotiation needs the real
history, not the single-commit default (the main-sync and builder precedent)").
The advance step (`:134-158`):
- `git fetch origin refs/heads/main:refs/remotes/origin/main` (`:145`) — the
  bump object must be pushable from this checkout;
- **endpoint**: `TARGET=${{ needs.build-charts.outputs.bump_sha }}` then
  `TARGET=${TARGET:-$GITHUB_SHA}` (`:146-147`) — the charts **bump commit**
  when this fan's range minted one (D53 — "an event-sha endpoint would
  re-enter the bump's own charts/** edits into the next detection forever"),
  else the event sha;
- **FF vs non-FF law (r5 change)**: one plain push first — `git push origin
  "${TARGET}:refs/heads/ci/last-built"` (`:148`) — no force form anywhere;
  on a refusal the step **CLASSIFIES** (C14/D54, `:152-158`): fetch the
  marker; `git merge-base --is-ancestor "${TARGET}" FETCH_HEAD` → "marker
  already advanced past this run's endpoint — consistent" `exit 0` (skip-
  green, `:153-156`); otherwise → RED naming both sides + the owner verbs
  ("reset the marker ref to a reachable commit or delete it to fall back to
  the payload chain", `:157`). **Non-FF refusal is no longer itself the
  signal** (cf-55 suite t16 comment L207-209: "non-FF is no longer itself
  the signal, D54") — the r4 shape (a queued/rewound run fails the advance
  loudly) became: endpoint already at-or-past the marker = calm green;
  diverged = loud red. Monotonicity still holds (a behind-marker endpoint
  that is not an ancestor is refused + red).
- **Credential**: NO `secrets.` reference in the job — the checkout's
  automatic same-repo credential (header `:47-55`: "the push wears no PAT
  (the same-repo credential … moved here with the job)"; "The marker stays
  Forgejo-local: this file mirrors refs/heads/main alone, so GitHub never
  receives it"). **Event kinds that advance**: push-main and dispatch on the
  prod-stage instance, when both called builders return green. **Partial
  fan failure**: one builder red → `advance-marker` SKIPPED (plain needs-
  gate) → marker put → next fan re-covers both domains; `sync-fanout`
  (`:160-197`, `needs: [push-gh, build-containers, build-charts]` `:174`,
  D59 hard gate: "a red release holds the fleet at the previous revision")
  skips too. **Dev-role instance**: every job's guard is false (header
  `:1-6` — "there the guard is false for both, so nothing fires on dev and
  the pushes cannot ping-pong"; unset ROLE renders empty and fires nothing)
  → **nothing fires; the dev repo never gets a marker** (cf-55 DECISIONS
  D53 L880-881: "dev instance carries NO marker — same fact, so the
  migration push is prod-only, UA-R5-1"). **Dispatch on prod**: a no-input
  `workflow_dispatch` re-fires the whole fan (push-gh/push-dev plain no-op
  re-pushes; the builders re-run detection over `marker..sha` or bootstrap
  tip-only; advance + fan-out follow the same green table) — a legitimate
  re-cover mechanism.

### R3-Q2 — `build-containers.yaml` (renamed) r5: the called-run contract

**Rename + trigger removal** (`:110-113`): "C15/D56: the push arm died with
owner directive 4 — main-sync.yaml calls this workflow on its prod-main fan;
path filtering lives in the marker..sha detection instead. PR and dispatch
lanes stay byte-frozen." `on:` (`:96-113`) = `pull_request` main + `paths:
['containers/**']` + `workflow_dispatch` (`containers` input, byte-frozen
`:100-109`) + **`workflow_call: {}` (`:113`)** — **no `push:` arm at all**.
`concurrency: cancel-in-progress: false` survives (`:115-116`).

**The marker is call-side only** (`:143-176` resolver, `id: marker`): gate
`if [ "$EVENT_NAME" != workflow_call ]` → emit empty `sha=` and exit 0
(`:154-157`, comment `:149-153`: "The marker is call-side (C15/D56 … the
push arm is gone). Non-marker-side events still emit the output key … an
empty MARKER_SHA is exactly the state the payload arms are specified
against"). Then `git ls-remote origin refs/heads/ci/last-built | cut -f1`
(`:158`); empty (ref absent) → empty `sha=` + exit 0 (`:159-163`, "No marker
yet: the before-chain answers, and main-sync's first aggregate green advance
creates it"); 40-hex validation with loud fail naming the value
(`:165-168`); `git cat-file -e "$marker^{commit}"` unreachable → `exit 1`
with the reset-or-delete owner verbs (`:169-175`). So **`marker..sha`
detection is ONLY for called runs** — the PR arm (merge-base, byte-frozen,
script `:44-55`) and the dispatch arm (list, `:38-41`) never read the
marker.

**The detect step** (`:177-216`): 7 env accessors (`:179-186` — the 7th
`MARKER_SHA: ${{ steps.marker.outputs.sha }}`); verdict echo names event,
endpoints and `marker=` (`:197`); **warning law** (`:210-216`):
`EVENT_NAME != workflow_dispatch && changed == '[]'` → if `MARKER_SHA`
non-empty → one plain info line "changed set verified empty: marker..sha
(marker=… sha=…) — nothing was missed between the marker and this run"
(`:211-212`); elif pull_request or (`EVENT_BEFORE` non-empty and `!= SHA`)
→ `::warning::changed set resolved empty … both build arms will skip`
(`:213-214`). **No-marker tip-only announce**: header `:57-62` — "With no
marker yet (the bootstrap state, and every state until main-sync's aggregate
first advances it) a called run narrows to the tip commit and announces it,
and a run that does carry a payload before falls back to its whole
before..sha range"; empty-set law `:70-77` (no-op `before == sha` + empty
dispatch silent; empty range from a present marker = the info line; nothing
reads `event.commits`/`total_commits`).

**The old advance-marker job is GONE from this file — it moved to main-sync**
(header `:45-50`: "The marker ref receives no write here (C15):
main-sync.yaml's aggregate job is its single writer, riding that caller's
own same-repo credential — no PAT … This workflow only READS the marker";
`:20-24`: "advanced by main-sync.yaml's aggregate job after the whole fan
builds green (C15/D54 — the single writer; this workflow only READS the
marker)"). The `build-release` guard is `forgejo.event_name != 'pull_request'
&& (vars.ROLE == null || contains(vars.ROLE, 'prod')) && … != '[]'`
(`:219`); `build-pr` the dev-role twin (`:426`).

### R3-Q3 — `scripts/forgejo-container-detect.sh` r5 (the 73-line change)

**Decision tree — the r4→r5 reorder + new arm** (`:56-99`): the r4 shape
(round-2 `R2-Q2`: "empty-before `die` first and unconditional; then marker
wins …") is **reordered and re-scoped** for the call era:
1. **`MARKER_SHA` non-empty → marker wins** (`a="$MARKER_SHA"`,
   `b="${SHA:-HEAD}"`, `base_src='marker'`, `:64-67`) — now FIRST, ahead of
   the payload die (comment `:58-63`: "Marker first (C15 call-aware): …
   Under workflow_call an empty before is EXPECTED (called runs carry no
   push payload), so the marker check — then the call bootstrap arm —
   precede the payload die; the die stays scoped to real pushes");
2. **NEW — `event == workflow_call` + no marker → tip-only + announced**
   (`:68-75`): `::warning::first called run (workflow_call, no marker):
   tip-only detection over HEAD^..HEAD`, `a='HEAD^'`, `b='HEAD'`,
   `base_src='tip-only'` ("First called run with no marker (bootstrap, or
   the owner has not migrated the ref yet)");
3. **empty `before` → `die`** (`:77-84`) — now **scoped to real pushes**
   ("A v15.0.10 push payload always carries before … the push arm still
   dies on it");
4. all-zero `before` → tip-only `HEAD^..HEAD` + `::warning::` (`:85-93`,
   unchanged);
5. otherwise `before..sha` (`:94-98`, unchanged).

**Header/env** (`:9-23`): `EVENT_NAME` vocabulary now
`push|pull_request|workflow_call|workflow_dispatch`; the `MARKER_SHA` doc
carries the call-aware posture (`:11-17`). **Echo** (`:107-108`): `detect:
range %s..%s (event %s${base_src:+, base=$base_src})` — the
`base=marker|tip-only|before` token, PR arm carries no token (`:104-106`).
**Warning/die law ownership**: the empty-set warning remains **step-owned**
(the workflow `:210-216`); the script's only warnings are the two tip-only
announces; `die()` exit-2 unchanged (`:30-33`); `next-n`/`sanitize`
unchanged.

**Delta vs our landed `scripts/coder-template-detect.sh` (decision trees, r5):**

| | upstream r5 | ours (C02, landed) |
|---|---|---|
| events | push, pull_request, **workflow_call**, workflow_dispatch (`:9-13`) | push, workflow_dispatch only (no PR arm, OQ2; header `:10-13`) |
| inputs | 7 env keys incl. `MARKER_SHA` (`:11-17`) | 4 env keys (`:10-13`) — **no `MARKER_SHA`** |
| non-PR/non-dispatch arm order | **marker → call bootstrap tip-only → empty-before die (scoped) → all-zero tip-only → before** (`:56-99`) | **empty-before die (first, unconditional) → all-zero tip-only → before** (`:37-58`) |
| `die` scope | real pushes only — a call run's empty `before` is expected, not fatal (`:60-63`, `:77-84`) | unconditional first (`:38-45`) |
| base echo | `base=marker|tip-only|before` token, PR none (`:107-108`) | no base token (`:63`) |
| empty-set warning | step-owned, marker-aware (YAML `:210-216`) | script-owned `exempt` flag (`:24-29`, `:35`, `:58`, `:86-92`) — the C03-documented inversion |
| dispatch all-ungated-list warning | absent (dispatch exempt wholesale) | present (`:87-88`) — the C02 divergence |
| path gate | `containers/` + `Dockerfile`, `cut -d/ -f2` (`:113-114`, `:120-126`) | `charts/coder/coder-templates/` + `main.tf`, `cut -d/ -f4` (`:68-69`, `:76-83`) |
| subcommands | `detect` \| `next-n` \| `sanitize` | `detect` only |
| die contract | exit 2, stderr-prefixed — identical shape | exit 2, stderr-prefixed |

**Consequence for the C04 re-ground**: the chunk's "empty-before `die` first
and unconditional" pin (C04 AC2, grounded against r4) must re-pin to the
r5 order **if the marker arm is adopted verbatim** — but the call bootstrap
arm (item 2) has no analog in our standalone push-trigger shape: for a
**standalone** workflow (push trigger, own ref, own writer) the die-stays-
first shape is the r4/cf-6 shape (a push payload always carries `before`; a
dispatch never reaches the push arm) and the call bootstrap arm is simply
not present. The r5 reorder exists because the push arm DIED upstream; ours
keeps its push arm (OQ2 trigger ruling), so the r4 order is not stale for
the standalone shape — the delta is the marker arm + the `base=` echo + the
`MARKER_SHA` header line (the r2 change set, minus the call arm).

### R3-Q4 — `build-charts.yaml` r5: the C14 adoption and the shared-marker model

**How it reads the same shared marker** (`:56-90`, `id: marker`): the gate
is **final-form** (`:68`: `if [ "$EVENT_NAME" != push ] && [ "$EVENT_NAME"
!= workflow_call ]` → empty `sha=` + exit 0; comment `:62-67`: "Marker-side
events: push now, workflow_call from C15 — the gate is written final so C15
removes the trigger, not this body"). Then the same ladder: `ls-remote
origin refs/heads/ci/last-built | cut -f1` (`:72`); absent → empty + exit 0
(`:73-77`); 40-hex validation loud (`:79-82`); `cat-file -e` unreachable →
reset-or-delete owner-verb fail (`:83-89`). The detect is **inline** (not a
script, `:91-147`): `EVENT_MARKER` non-empty → `git diff --name-only
"${EVENT_MARKER}" "${EVENT_SHA}" -- charts/ || true` (`:107-108`, **path
filter `-- charts/`**); all-zero `before` + no marker → `HEAD^` +
`::warning::` (`:109-111`); empty `before` + no marker → **fatal**
(`:112-114` — "the silent HEAD^-fallback that used to hide it is buried");
otherwise `before..sha` (`:115-117`). Name gate: `cut -d'/' -f2` + DNS-safe
+ `Chart.yaml` presence (`:120-127`). Warning law inline (`:134-141`):
marker-present + empty → the same verified-empty info line; empty on a real
`before..sha` (no marker, `before != sha`, all-zero excluded) →
`::warning::empty changed set on a real before..sha range`; `before == sha`
silent. Output: `CHARTS` JSON + `HAS_CHANGES`.

**The sharing model (C14/D54/D55 — cf-55 DECISIONS L872-951):** **one ref
per repo per instance: `refs/heads/ci/last-built`** (name **FINAL** per
owner F1, D59 L1043-1044; D53 L873-874: owner suggest adopted, veto slot
closed). **Readers**: `build-containers.yaml` resolver + `build-charts.yaml`
resolver — two consumers, one base. **Single writer**: `main-sync.yaml`
`advance-marker` (D54 L902-915 — per-builder advance on a shared multi-
owner branch is "structurally POISONED: one builder's green fire moves the
ref past the other builder's FAILED range, and those changes fall behind
the marker forever — destroying exactly the dead-run recovery"; rejected:
per-builder tolerance, event-sha endpoints, two branches). **Endpoint**:
bump commit if the charts leg minted one, else event sha (D53 L884-889 —
the bump commit itself edits `charts/*/Chart.yaml`, so an event-sha
endpoint "would re-enter it in the next detection and mint an eternal one-
extra-release-per-fire tail"; the containers builder "cannot hit this
because it creates no commits — the asymmetry is why the helm chain needed
its own analysis"; the target rule's event-sha fallback covers output-less
builders — D55 L940-941).

**Collision semantics (two consumers, different path filters, one marker):**
no ref collision is possible (one writer); the per-consumer path filter is
applied over the same shared base — `build-containers` diffs
`-- containers/` (script `:113`), `build-charts` diffs `-- charts/`
(`:108`). A consumer whose filtered set is empty does NOT block the
advance: its called run completes green (verified-empty info line), and
`needs` reads it as success — only a **red** consumer holds the marker
(main-sync `:122-124` re-cover law; cf-55 suite t17 truth table; D54
L928-929: "a skipped-by-ROLE builder reads success (empty called run) —
dev instance safe"). The aggregate advance therefore requires **BOTH
consumers green (or skipped)**; a partial-failure fan leaves the marker
put and the next fan re-covers **both** domains (D54 L916-919: "in a mixed
outcome BOTH builders re-cover next fire, so the green one may mint one
extra calendar version — containers: same-tag republish is idempotent;
helm: tree+1 walk — today's failed-then-re-run semantics, not a new class").
**Inherited filter decision (D55 L943-947, recorded for card #56 = this
ticket)**: "the `cut -d/ -f2` collapse of `charts/coder/coder-templates/**`
into charts/coder's bump set (live today, scout §E) — 'fixing' it here
would change helm's live release set for another card's concern (one branch
one concern); recorded in the plan's out-of-scope block so #56 inherits it
as its filter decision" — i.e. under r5, a template edit already rides the
fan and bumps the `charts/coder` wrapper chart (the packaging guard keeps
`coder-templates/` out of the tgz; the bump mints a version whose package
differs only in the `Chart.yaml` version line).

### R3-Q5 — Implications for the C04 re-ground (facts, not decisions)

**(a) Standalone own-workflow advance vs joining the fan.** The r5 tree
contains **no standalone push-trigger + own-marker workflow anymore** — both
builders moved into the fan under the shared ref (D56 L952-983; D58
L1024-1031: "from C15 on, a `charts/**` merge does NOT itself fire
build-charts — main-sync's next run calls it … fire timing = the fan,
contents = marker..sha"). The facts each shape carries:
- **Standalone (r4/cf-6 shape, what C04 was written for)**: keeps the OQ1
  per-instance semantics — both forges fire the push trigger, each pushes to
  its OWN Coder (the dev instance receives main via the fan-out push, a
  normal push event on the dev repo; round-2 `D16`), and each repo's own
  ref carries per-instance state. The D54 poison ruling does **not** reach
  it: the poison is per-builder advance on a **shared multi-owner** branch;
  a single-writer per-repo ref (only our workflow writes it) is the cf-6
  shape r2 grounded. The r4 plain non-FF advance shape (monotonicity =
  refusal) remains available; the r5 classify shape (already-advanced =
  skip-green) is what the shared-ref aggregate adopted. No upstream suite
  surface touches our ref: the upstream t16 walk is scoped to the
  `ci/last-built` token (R3-Q6), and the OQ11 candidate ref is named in no
  `.forgejo` workflow (grep-measured r3 — `ci/containers-built` appears in
  no other workflow file, as r2 measured; the rename keeps that true for
  `ci/last-built`'s two named readers + the writer).
- **Fan member (the D55 pre-built room, cf-55 DECISIONS L935-951 — "this
  round LEAVES ROOM for the third builder but does NOT build it (launch-
  brief law; card #56 owns it). Room = (1) the t16 allow-set … #56 joins
  by adding its file to the set; (2) the call pattern — #56 adds one
  `uses:` job + one `advance-marker` needs entry, the aggregate's target
  rule already handles a builder with no outputs (event-sha fallback); (3)
  naming — a `build-coder-templates.yaml` needs no marker-branch work, only
  the shared ref")**: the join is mechanically cheap (one `uses:` + one
  `needs` entry + one allow-set member in the upstream suite — a cross-
  ticket surface edit in our commit, the "one branch one concern" tension
  D55 itself names); the dispatch hatch survives the call (build-containers
  keeps `workflow_dispatch` byte-frozen beside `workflow_call` — the named
  rebuild hatch, "dispatch never advances the marker", D56 L963-965); we
  mint no commits, so the D53 bump-tail does not apply to us. **But the
  fan is prod-stage-instance only** (main-sync guard `contains(vars.ROLE,
  'prod')`; D53: "dev instance carries NO marker") — fan membership means
  the **dev Coder is never pushed by the pipeline**, a direct conflict with
  the 2026-11-25 OQ1 ruling (per-instance, both Coders, each executing
  Forgejo pushes to its own Coder; confirmed in the batched round,
  DECISIONS L125-126). The marker state becomes single-repo (the prod
  repo's `ci/last-built`).

**(b) Marker ref naming (standalone).** Live inventory at origin (the
prod-stage Forgejo, `git ls-remote origin 'refs/heads/ci/*'` read
2026-11-26): **exactly one ref — `refs/heads/ci/containers-built` @
`52d3b5c45`** (the r4-era ref; D58 L1031-1032: "Old-ref deletion after
C15 = UA-R5-3 (prod only)"). **`refs/heads/ci/last-built` is NOT yet
live** — the C14 migration pre-steps (UA-R5-1/UA-R5-2, cf-55 DECISIONS
L1017-1020) are owner-side and not visible on the remote yet. No
`ci/coder-templates-pushed` or any coder ref exists. The OQ11 candidate
`refs/heads/ci/coder-templates-pushed` is therefore **free**, and the
upstream single-writer fence cannot catch it (its walk is token-scoped to
the `ci/last-built` literal, R3-Q6). If the fan-join shape is chosen
instead, the ref is the shared `ci/last-built` itself (D55 room (3): "needs
no marker-branch work, only the shared ref").

**(c) Post-merge regression facts (C01 surface + UA3 pins).** The merge
touched exactly (first-parent diff `16df8a38d → 01d2e3f45`):
- `containers/forgejo-runner/Dockerfile` — **2 lines** = ONE header comment
  rename `containers-build` → `build-containers` (`:5`). The C01 bake is
  byte-intact: `FROM ghcr.io/coder/coder:v2.39.5@sha256:40fade40… AS
  codertool` (`:65`), `ARG CODER_VERSION=2.39.5` + renovate annotation
  (`:86-87`), `ARG CODER_BIN_SHA256=83431171…fe4` (`:105`), `COPY --from=
  codertool /opt/coder /usr/local/bin/coder` (`:130`), the single anchor
  RUN's `coder version | grep -q "v${CODER_VERSION}"` (`:144-147`), all cf-
  56 provenance comments.
- `tests/containers/forgejo-runner.sh` — **4 lines** = TWO comment renames
  (header `:12` + t8 `:369`, both `containers-build.yaml` →
  `build-containers.yaml`). The re-pinned contract is intact: **all nine
  legs t1..t9 present** (t1 four-FROM incl. the codertool tag/ARG pairing;
  t2 the CODER_VERSION floor + annotation + CODER_BIN_SHA256 provenance
  pins incl. the repaired `ver_ge` helper; t9 the coder stage-transport
  leg).
- `charts/forgejo-runner/values.yaml` — **9 lines** = the B1 comment block
  replaced by "Decision B1 AS AMENDED (owner ruling 2026-11-26, cf-55
  round-5): the DEFAULT stays one pod … while the ruling permits per-
  release scale-out to N poller pods sharing one (uuid, token)
  registration via the slice override. Job-count autoscaling stays OUT
  (Inbox card iaJq5bgWHHDHotcBY owns that dimension)" — `replicas: 1`
  unchanged; the four act-24.04-family label lines (`:149-153`) still pin
  `:26.11.1` (the act-22.04 ghcr line unchanged).
- **Beyond the three-file scope** (context for the risk wording): both
  runner slices gained `replicas: 10` (D57, `services/dev/prod/values.
  yaml:179-185`, `services/gpu/prod/values.yaml:274-280` — "10 poller pods
  share one (uuid, token) registration; capacity stays 1 per pod"; cf-55
  DECISIONS L996-1001: "10 pods × capacity 1 = 10 concurrent jobs, each
  pod's dind limits per-pod honest — a capacity>1 route would fake
  parallelism inside one 2cpu/4Gi envelope"). The dev slice's own
  five-entry label list (`:201-205`, incl. its bootstrap `:26.11.1` copy)
  is intact.
- **UA3 runbook facts survive**: the runbook's `:26.11.1` pins
  (`.agents/notes/2026-11-25-coder-template-push.md:176,204`) remain
  consistent with both label sites post-merge; the runbook's pointer to
  "the chart's own comment" for the Helm-wholesale-replacement law still
  resolves (the B1 comment exists, AMENDED). **Stale wording to re-pin in
  C04's risk reword**: the plan/chunk "capacity-1 runner + FIFO queue"
  phrasing (round-2 `R2-Q5`, plan Risks) now reads as **10 poller pods ×
  capacity-1 + FIFO + `cancel-in-progress: false`** (build-containers
  `:81-85` documents the 10-pod scale, D57) — the race remains vanishing
  (per-pod serialization), the label moves.
- **Suite regression (executed 2026-11-26 on the post-merge tree)**:
  `bash tests/containers/forgejo-runner.sh` → **9 ok, exit 0** (t1–t9; t8
  the designed `docker build => no-daemon, CI-deferred` shape). Note: the
  first execution in-session reported a false t6 "no deviation comment"
  (the two comment greps pass standalone; the full re-run is 9/9 green) —
  a session-flux artifact of the run that followed a dropped shell, not a
  tree defect; the re-run is the evidence.

**(d) Stale `containers-build.yaml` sweep (file:line, r3-measured).**
- `.forgejo/workflows/coder-template-push.yaml`: **L9** ("whose guards
  widen on unset"), **L25** ("the containers-build.yaml shape"), **L102**
  ("the containers-build rationale"), **L119** ("containers-build rationale
  comment"), **L180** ("(the containers-build" fetch-depth citation) — L9
  and L25 carry the bare `.yaml` token (sweep-catchable); L102/L119/L180
  carry the token **without** `.yaml` (prose form, passes the sweep, still
  stale).
- `tests/coder/coder-template-push.sh` (w-legs): **L113** (dispatch-hatch
  provenance), **L115** ("must carry the containers-build.yaml
  description"), **L121** ("the containers-build.yaml shape is type:
  string"), **L187** ("the containers-build.yaml rationale"), **L337**
  ("the containers-build rationale, the V-6-1 shallow-clone law") — L113/
  115/121/187 are the bare-token (sweep-catchable) lines; the w2 assertion
  string itself (`"Template names to push (comma/space separated)"`, our
  own wording, `:114`) is rename-untouched — only the failure-message
  provenance labels move (→ `build-containers.yaml`; the upstream dispatch
  description it paraphrases is `'Container names to build (comma/space
  separated)'`, build-containers `:106`).
- `.agents/notes/2026-11-25-coder-template-push.md` (runbook): **L47**
  ("Unlike `containers-build.yaml` (widens on unset)"), **L67** (UA3
  "merge's `containers-build.yaml` fire publishes the new calendar tag"),
  **L81** ("the `containers-build.yaml` shape). No PR leg"), **L166** (UA4
  "fire publishes the new `forgejo-runner` calendar"), **L276** ("The
  merge's `containers-build.yaml` fire plus the UA3 hand-bumped pin") —
  round-2 `R2-Q4` item 4 ("The other `containers-build.yaml` citations
  (L47, 67, 81, 166, 276) remain valid (the name is unchanged)") is
  **invalidated by r5**; the runbook is outside the t8 sweep (`.agents/`
  excluded) so these stay invisible to the upstream suite.
- **The release-era stale refs (pre-existing since the r4 rename; C04's
  known "two stale refs" task + two NEW findings)**:
  `.forgejo/workflows/coder-template-push.yaml` **L11** ("the `release.
  yaml` fail-safe class") and **L188** ("the `release.yaml` class") —
  already in the C04 plan/chunk; **NEW: `tests/coder/coder-template-
  push.sh` L158** (w3 failure message "the release.yaml fail-safe class,
  narrow on unset") and **L165** (w3 grep-fail message "the release.yaml
  fail-safe class for external-service publishes") — the w3 leg's own
  failure prose carries the stale token; round-2 `R2-Q4` did not sweep the
  suites, so these two are new surface for the C04 suite re-pin. The
  runbook L50 ref is the known third.
- **Upstream sweep posture (executed r3)**: `tests/services/forgejo-ci-
  surface.sh` **t1 is RED on this branch** (pre-existing, not merge-
  introduced — FJ_SET is the five-workflow family `{'main-sync.yaml',
  'renovate.yaml', 'build-containers.yaml', 'build-charts.yaml',
  'builder-bootstrap.yaml'}` both pre- and post-merge; our workflow is a
  sixth member, and the suite runs green on main, which does not carry
  our file). **t8 is RED** (standalone-executed r3; the fail-fast suite
  dies at t1 first): the containers-era sweep (armed by the rename,
  `history_free` D50.3 dated-history exemption) catches exactly the 6 bare-
  token lines — workflow L9, L25; tests L113, L115, L121, L187 — plus the
  4 release-era lines above. **C04's re-ground must re-point the stale
  lines** (the 2 known release-era workflow refs + the 2 new w3 release-
  era suite refs + the 5 containers-era workflow lines + the 5 suite lines
  + the 5 runbook lines fold into the same change set) **or the upstream
  ci-surface suite stays red on this ticket's branch** (it is a cf-55
  suite, green on main; the red-on-our-branch state is a cross-ticket
  surface the ticket's own commits should heal, the D50.3 pairing law:
  "docs + suite move in ONE commit set").
- Plan/EXPLORE/chunks/STATE/DECISIONS mentions (plan L29, L72, L133, L140,
  L183, L212, L216, L234; EXPLORE round-1/2 as listed in round 2 `R2-Q4`;
  `chunks/C04.md` L16, L171, L245, L326, L335; `STATE.json` L126, L133;
  DECISIONS append-only): historical records — no in-place fix; the plan's
  C04 section is re-grounded by the replan, this section corrects EXPLORE.

### R3-Q6 — The r5 suites (mirror shape for the C04 test wave)

`tests/services/forgejo-build-containers.sh` (renamed from `forgejo-
containers-build.sh`; full set 47 ok at run end; legs t1–t17, d1–d22, x1–
x5, r1–r5, g1):
- **t2** (`:307`): `on:` is exactly `{pull_request, workflow_dispatch,
  workflow_call}` — "no push arm (C15 re-aim; the merge-base PR posture
  and rebuild hatch byte-frozen)".
- **t5 / r1** (`:412-418`, `:1492-1499`): job set = the C02 trio
  (detect-changes + build-release + build-pr) **plus at most** `advance-
  marker` (the both-trees transition form).
- **t13** (carried): the **seven** detect-step env accessors byte-exact
  (the 7th = `MARKER_SHA`).
- **t14** (`:1203-1210`): the behavioral half now executes **nine** shapes
  — "empty push/PR ranges without a marker warn, the dispatch no-op, the
  before==sha no-op and non-empty sets stay silent, and the marker-verified-
  empty shapes (push **and workflow_call alike**, plus marker==sha) exit
  with the plain verified-empty info line and no annotation: the calm gate
  reads MARKER_SHA presence for any event" (round-5 C15 M1).
- **t16** (`:1292-1325`) — **inverted to the single-writer fence**: no
  `advance`-named job in the builder ("C15 deletes them … a per-builder
  advance on the SHARED branch is the poison D54 ruled out: one green
  fire would swallow the sibling failed range"); **zero** `git push`
  statements naming the marker ref in the file; the resolver still names
  `refs/heads/ci/last-built`; the ref lives in **no `.forgejo` workflow
  outside the allow-set `{'build-containers.yaml', 'build-charts.yaml',
  'main-sync.yaml'}`** — "a new builder joins the set in its own commit
  (card #56), it does not route around this leg"; of that set, **exactly
  `main-sync.yaml` carries a marker push** (`writers ==
  {'main-sync.yaml'}`).
- **t17** (`:1328-1454`): the resolver battery, now **call-side only** —
  staged with `forgejo.event_name` → `workflow_call` (and `→ pull_request`
  for the non-marker side), executed offline against a scratch bare remote:
  absent marker → `sha=` empty + exit 0; present+reachable → the marker
  oid; orphaned (advanced from a sibling clone) → LOUD fail naming the sha
  + reset-or-delete owner note; non-hex garbage (PATH-shimmed `ls-remote`)
  → fatal naming the value; `pull_request` on a dead origin → `sha=` +
  exit 0, no network. **The advance-exec half moved to `forgejo-main-
  sync.sh` t16** (header `:22-33`).
- **d20** (`:2364-2385`): `workflow_call` + marker set + **empty before** →
  diffs `marker..sha` (`base=marker`), exit 0 — "the marker check must
  precede the empty-before die (C15 call-aware reorder)".
- **d21** (`:2387-2407`): `workflow_call` + no marker + empty before →
  announced tip-only `HEAD^..HEAD` (`base=tip-only`), **never the push-
  payload die** (the C15 new arm).
- **d22** (`:2410-2422`): a REAL `push` event + empty before + no marker
  **still dies** (naming `before`) — "the die stayed scoped to real
  pushes, the marker arm moved ahead of it".
- **x5** (`:2637-2645`): the gated docs trio (`skills/container-creation/
  SKILL.md`, `.rulesync/rules/overview.md`, `AGENTS.md`) must carry the
  marker vocabulary — `before..sha`/whole pushed range, merge-base, tip-
  only, announce, `fetch-depth: 0`, **`marker..sha`** — with the first-
  push sentence pairing the event with its narrowing in one paragraph and
  no annotation-render over-claim. (The `AGENTS.md` r5 paragraph in this
  tree already carries it — "Pipeline specifics in this repo" — so our
  reworded citations can key on the same vocabulary.)

`tests/services/forgejo-main-sync.sh` (+362 lines r5; legs t1–t18):
- **t3** (`:94-137`): **exactly six jobs** `{push-gh, push-dev, build-
  containers, build-charts, advance-marker, sync-fanout}`, every one
  byte-guarded on `contains(vars.ROLE, 'prod')`.
- **t14** (`:580-614`): the two CALLED builder jobs byte-pinned (`uses:` +
  `secrets: inherit` + the prod guard).
- **t15** (`:615-665`): the aggregate `advance-marker` byte-pinned —
  `needs` exactly the two builders; `if:` **wears no result function**
  ("the plain needs-gate IS the green-fire rule; decoration reintroduces
  the per-builder poison (D54/D59)"); checkout present (full depth); the
  `outputs.bump_sha` + `TARGET=${TARGET:-$GITHUB_SHA}` chain; a plain
  `git push … $TARGET:refs/heads/ci/last-built`; the ancestor-tolerance
  body; no force; no secret.
- **t16** (`:667-775`): the **EXECUTED** aggregate-advance battery on a
  scratch bare remote — create (explicit `bump_sha` value, no marker yet);
  target==marker up-to-date green; **ancestor-ahead skip-green with the
  info line and the ref unmoved**; non-ancestor divergence **RED and
  naming it**; the empty-`bump_sha` fallback advancing at `$GITHUB_SHA` —
  "the advance law fully executed at its new home".
- **t17** (`:777-843`): the D59 truth table executed over the parsed needs
  graph — both-green **RUNS**; containers-red / charts-red / both-red /
  push-gh-failed all **SKIPPED** for sync-fanout AND the aggregate
  advance follows the same table; push-gh/push-dev unconditional siblings
  in every row.
- **t18** (`:845+`): comment line-anchor liveness (the scout §C anti-
  pattern killer).

`tests/services/forgejo-ci-surface.sh` (126 lines r5): `FJ_SET`/`WIDEN_OK`
re-aimed to `build-containers.yaml` (red-through-C13/C14 by design, pin 3:
"docs + suite move in ONE commit set at C15"); **t8 WIDENED** with a
second, containers-era stale-name sweep (bare `containers-build.yaml`
token ban on live surfaces, `history_free` D50.3 dated-history exemption)
beside the release-era one — the leg whose red state is measured in
R3-Q5(d).

### Round-3 gotchas (new since r2)

1. **The r5 reorder invalidates the chunk's die-first pin only for the fan
   shape**: the call bootstrap arm exists because the upstream push arm
   DIED (D56); a standalone push-trigger workflow (OQ2) has no call arm, so
   the r4 die-first order is not stale for it — the C04 task text "empty-
   before `die` first and unconditional (unchanged)" survives verbatim for
   the standalone shape, and becomes "marker first, die scoped" only if
   the fan-join shape is chosen (in which case the advance job is main-
   sync's, not ours, and the chunk's `advance-marker` task retires).
2. **The r5 advance shape changed the monotonicity contract**: r4's "a
   queued or rewound run fails this job loudly (non-FF refusal IS the
   signal)" became the C14/D54 **classify** (already-advanced = skip-
   green info; diverged = red). The C04 chunk's "executed-offline
   monotonicity leg" (t17 analog: "the same push against a moved-ahead
   marker exits non-zero with the non-fast-forward refusal named") must
   re-pin to the r5 battery shapes (up-to-date green / ancestor-ahead
   skip-green ref-unmoved / divergence red) **for the shared-ref shape** —
   for a single-writer own ref the r4 plain shape remains the defensible
   contract (there is no second owner to get ahead of).
3. **The `:26.11.1` UA3 pin is intact but the runner topology moved**
   (10 poller pods × capacity-1, D57) — any C04 risk text quoting "the
   capacity-1 runner" must reword, and the runbook's "the chart's own
   comment" pointer still resolves (B1 comment AMENDED, not deleted).
4. **The upstream ci-surface suite is red on this branch for two reasons**
   (t1 FJ_SET — pre-existing since C03; t8 — the 6 r5-introduced stale
   lines + the 4 release-era ones, 2 of them in our own suite's w3 prose)
   — C04's re-ground should fold the full stale-line re-point into its
   change set so the ticket's branch heals its own cross-ticket surface.
5. **`ci/last-built` is not yet live on the remote** (only the r4-era
   `ci/containers-built` @ `52d3b5c45`); the C14 migration pre-steps
   (UA-R5-1/UA-R5-2) are owner-side — a standalone-shape marker (a new
   ref) does not depend on them, a fan-join shape lands into a
   pre-migration shared-ref state (the first called fires would be
   bootstrap tip-only until the owner's pre-step + first aggregate green).

### Round-3 open questions (for the planner/owner — not resolved here)

1. **Fan member vs standalone own-workflow advance** (R3-Q5a): the D55
   room pre-builds the join (cheap: one `uses:` + one `needs` entry + one
   allow-set member), but the fan is **prod-stage-instance only** — fan
   membership strands the dev Coder (the OQ1 ruling: per-instance, both
   Coders). Standalone keeps OQ1 + per-instance refs + the r4 plain non-FF
   advance shape, at the cost of no longer matching the r5 house pattern.
   The OQ10–OQ13 batch (r2) re-issues in the r5 shapes; OQ11's ref
   candidate is free on the remote (R3-Q5b).
2. **Per-consumer marker collision if shared** (R3-Q4): one shared base +
   per-consumer path filters + a single aggregate writer = no ref
   collision is possible; the operative questions are (a) whether the
   inherited `charts/coder` bump-on-template-edit (D55's recorded filter
   decision) is acceptable to ride, and (b) whether an output-less builder
   (us) in the aggregate's `bump_sha-or-event-sha` chain needs any
   per-builder guard — D55 says the target rule already handles it
   (event-sha fallback), the t15/t16 battery pins that.
3. **Which advance shape pins the executed monotonicity leg** (round-3
   gotcha 2): r4 plain non-FF (single-writer own ref) vs the r5 classify
   (shared ref) — follows from open question 1; the chunk's leg text must
   re-pin accordingly.
4. **The stale-line re-point scope** (round-3 gotcha 4): confirm the full
   list folds into C04's change set (the 2 known release-era workflow refs
   were already planned; the 5 containers-era workflow lines, the 5 suite
   lines, the 2 new w3 release-era suite lines, and the 5 runbook lines
   are the delta).

## Round 4 (2026-11-27, live-state scout) — the "if necessary" verdict + pin-target facts

Grounded 2026-11-27 (~18:45–19:35 UTC) by `agent-explore` (read-only) on
`origin/main` @ `f3c6976c3` (post-merge, post the cf-55 r8 revert). Scope:
whether a post-bake tag containing the coder binary was already published
(which settles "rebuild if necessary"), the current pin-site facts on
origin/main (the r8 revert moved the runner surface — the ticket-branch
facts are stale), the CI run state on the clusters, the merge facts, the
rebuild-lane shapes (for the record), and the test-surface re-pin list.

### R4-Q1 — Merge facts (the "after this date, a tag is post-bake" anchor)

- C01 bake commit: `b7588d57d` "C01 AD-56: bake coder CLI v2.39.5 into
  `containers/forgejo-runner` - review APPROVED" (authored 2026-11-25
  05:30:45Z).
- Landed on `origin/main` via merge **`a91627e06`** "Merge branch
  'cf-56-feat-forgejo-coder-template-pipeline'" (commit date
  **2026-11-27 03:55:29Z**, parents `2a8cfe06d` + `87a1cb1f5`; `87a1cb1f5`
  is the ticket-branch head — `git merge-base --is-ancestor b7588d57d
  origin/main` = true).
- Post-merge pre-r8 events (all Chart.yaml calendar bumps by the
  build-charts fan; **none of them image-pin moves**): `e5a816295`
  (03:57:03, `charts/coder` + `charts/forgejo-runner` — the merge's own
  fan; the ticket changed `charts/coder/coder-templates/**`, so the D55
  inherited filter bumped the coder wrapper), `1d46d1c84` (04:28:56),
  `a72a513ef` (15:07:11 — the 14:39 r8-revert push's fan).
- `6ffeeb87e` (14:39:15) "cf-55 r8: restore pre-C17 runners": the chart-side
  revert (charts/forgejo-runner templates/values, custom-values, suite
  re-pins); its `services/*/prod/values.yaml` hunks were **comment-only**
  (the D61/C17 comment replaced by a D57-amends-B1 comment; `replicas: 10`
  intact on both slices). The r8 chart change is what rolled the runner
  release (R4-Q3).

### R4-Q2 — Published tags (instance registry — the anonymous-JWT flow answers)

**The instance registry v2 API answers to an anonymous JWT**: `GET
https://git.spencerslab.com/v2/token?service=container_registry&scope=…`
(no credentials) → 200 + JWT (payload `UserID:-1`); a direct unauthenticated
GET 401s with challenge `Bearer realm="https://git.spencerslab.com/
v2/token",service="container_registry",scope="*"`. (The runbook UA3's bare
curl line against the instance registry 401s as written — the realm-JWT is
the working anonymous shape; see Round-4 gotcha 6.)

`GET /v2/curatedforest/forgejo-runner/tags/list` (read 2026-11-27 ~19:15Z):
`26.11.1, 26.11.2, 26.11.3, 26.11.4, 26.11.5, latest, main,
pr-renovate-ghcr.io-catthehacker-ubuntu-act-24.04-5b4af52,
pr-renovate-ghcr.io-catthehacker-ubuntu-act-24.04-a1c0e5a`

- **`26.11.1` / `26.11.2` / `26.11.3` / `26.11.4` all resolve to the SAME
  amd64 manifest** `sha256:3bf08c36…` (9 layers; trailing layers built
  2026-11-23 18:01: helm 61,702,306 B + cr 68,509,897 B baked; **NO coder
  binary** — negative control, `tar -tvf` grep = 0 hits). Pre-bake image,
  calendar re-mints/re-points (mechanism not visible at agent tier — see
  gotcha 4).
- **`26.11.5` = the distinct amd64 manifest** `sha256:3da7aeb4…` (10
  layers; the first 6 layers shared with `3bf08c36`). Tail layers
  layer-verified (the C01 offline recipe): helm 61,702,306 B (2026-10-15),
  cr 68,509,897 B (2026-10-31), **`usr/local/bin/coder` 355,623,074 B,
  uid 1000, mtime 2026-11-24 23:18** (the coder release artifact), build
  dir mtimes **2026-11-27 03:52** — the merge fan's own build. `latest`
  and `main` both point at the 26.11.5 manifest (rolling-tag law holds).

**Verdict: a post-bake tag already exists — `26.11.5` contains the coder
binary. NO rebuild is required. Bump target = `26.11.5`.**

Corroboration: `ci/last-built` (live `git ls-remote` read 19:13Z) =
`b50a5395c` (17:12:52) and `a91627e06` IS an ancestor of it — the merge
fan (and every fan through 17:12) ran green, and the marker advances only
on a fully-green fan, so the merge fan's `build-containers` build (whose
`marker..sha`/tip-only bootstrap range carried the merge's Dockerfile
change) was green. The in-image anchor RUN (`coder version | grep -q
v2.39.5`) executes at build time, so a green build ⇒ the image carries a
working coder binary. (The layer check is the direct proof; the fan/green
chain is the belt-and-braces.)

The runbook UA3 warning materialized exactly as written — "a build that
predates the merge you ship can already occupy a higher N": 26.11.2–4 were
occupied by pre-bake re-mints, so the merge's own build is **26.11.5, not
26.11.2** (the runbook's `tag=26.11.2` expectation line is the pre-walk
assumption; the owner's UA3 verify leg is what confirms "it is the
merge's own build").

**ghcr.io (the C01-proven flow no longer answers):** `GET
https://ghcr.io/token?service=ghcr.io&scope=repository:ownyourio/
forgejo-runner:pull` → 401 "authentication required"; the control
`…scope=repository:catthehacker/ubuntu:pull` on the same flow → 200 +
token. So GHCR now denies anonymous pull for `ownyourio/forgejo-runner`
(visibility change or policy; the C01 proof was 2026-11-25) — the ghcr
tag list / manifest cannot be verified at agent tier. The dual-publish law
(same three tags pushed to ghcr + the instance registry on a prod-role
fan) makes the instance-registry list the available authority; the ghcr
side is the owner's UA3 UI confirmation.

**Dev registry (git.scifi.farm):** same realm-JWT flow (200, `UserID:-1`)
but `tags/list` → `{"errors":[{"code":"NAME_UNKNOWN"}]}` — the package
`curatedforest/forgejo-runner` is absent or anonymous-invisible there. The
dev slice pins `git.scifi.farm/curatedforest/forgejo-runner:26.11.1` and
the chart comment's bump law says "push the new tag to git.spencerslab.com
AND git.scifi.farm" — a 26.11.5 copy on the dev registry is an owner-side
manual leg (runbook UA leg 2) before the dev site can pull it.

### R4-Q3 — CI run state (clusters, readonly k8s MCP)

- **Infra cluster**: no `forge` namespace (namespaces: default, kube-*,
  system-upgrade); `infra-forgejo-55c7666785-5zbrl` (5d22h) + `pg-forgejo-1`
  are the git service; **no runner workload on infra** (the Q6 relocation
  law holds: the infra instance's runner = the gpu-cluster release).
- **Gpu cluster**: `gpu-forgejo-runner-gpu-0..9` (10 pods, the D57 scale) —
  **all created 2026-11-27 15:01:59–15:07:29Z** (StatefulSet age 3h54m at
  ~18:55Z) — the ArgoCD rollout forced by the 14:39 r8 chart revert.
  Runner daemon `data.forgejo.org/forgejo/runner:13.2.0`, dind
  `docker:29.9.2-dind`; the per-JOB image is not a pod container — it is
  the mounted config's act `labels` = still the `:26.11.1` pin (never
  bumped) ⇒ every post-15:01 job ran the pre-bake image.
- **Dev cluster**: **no forgejo-runner-dev workload at all** (no
  StatefulSet/Deployment, no pods, ~19:0xZ) — the appset entry is present
  (`services/dev/prod/values.yaml:116-119`, no `enabled` key ⇒
  default-enabled) and the slice says `replicas: 10`; the absence's cause
  is not visible at agent tier (no ArgoCD-state surface in the fleet). The
  OQ10 dev-side dispatch leg is therefore doubly inert at the moment (no
  runner pods + no dev-registry package, R4-Q1).
- **Runner log timeline (gpu pods — post-15:01 only; the pre-15:01 logs
  died with the rollout)**:
  - the 03:52–04:30 merge fan: **log lost** — the 26.11.5 layer mtime
    (03:52) + the green-marker progression carry the evidence.
  - 15:05–15:15 fan (the 14:39 r8 push): push-gh/push-dev + detect-changes
    + changes/test-build/bump/forgejo-publish/release + sync-fanout +
    advance-marker — the chart-side fan (bump `a72a513ef`); **no container
    build job** (`containers/` unchanged in that push).
  - 16:18 / 17:11 fans (cf-133 pushes): the audio-ad-detection chart legs +
    bumps (`d55dd88de`, `b50a5395c`) + advance-marker (17:19:43); no
    forgejo-runner container build.
  - 18:25 fan (the 18:22–24 pushes): push-gh/push-dev/detect-changes/
    changes/advance-marker (18:25:28)/sync-fanout — **the 18:25:28
    advance did NOT move the ref** (live read 19:13Z = still `b50a5395c`);
    the 18:22–24 commits sit behind the marker ⇒ the next green fan
    re-covers them (the designed re-cover law; the failure cause is not
    visible at agent tier — job consoles live on the forge server).
  - **18:36:42–18:36:57: a standalone coder-template-push run** —
    `detect-changes` (pod1, 18:36:49) + the **`push kubernetes-hardened`
    job (pod0, 18:36:57)**; no push-gh/push-dev in the window ⇒ not a
    main-sync fan — the owner's **first real dispatch** (an explicit
    template list; a called fan over `marker..sha` would have
    verified-empty: no template change since the 18:25 advance). That job
    ran on a 15:01 pod with the `:26.11.1` job image ⇒ `coder: command
    not found` (the reported failure; the console text is server-side, not
    in the pod log).
  - no `build <container>` job line anywhere in the post-15:01 logs ⇒ no
    post-15:01 build-containers dispatch and no 26.11.6 mint (consistent
    with the tag list ending at 26.11.5).

### R4-Q4 — Current pin sites on origin/main (post r8 revert — branch facts stale)

`git grep` on `origin/main` @ `f3c6976c3`:

| # | file | line | exact current value |
|---|---|---|---|
| 1 | `charts/forgejo-runner/values.yaml` | 149 | `- ubuntu-latest:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` |
| 2 | `charts/forgejo-runner/values.yaml` | 150 | `- ubuntu-24.04:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` |
| 3 | `charts/forgejo-runner/values.yaml` | 152 | `- docker:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` |
| 4 | `charts/forgejo-runner/values.yaml` | 153 | `- node22:docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` |
| 5 | `services/dev/prod/values.yaml` | 201 | `- ubuntu-latest:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1` |
| 6 | `services/dev/prod/values.yaml` | 202 | `- ubuntu-24.04:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1` |
| 7 | `services/dev/prod/values.yaml` | 204 | `- docker:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1` |
| 8 | `services/dev/prod/values.yaml` | 205 | `- node22:docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1` |

- **Dev-slice answer: five entries, four move.** Both label lists carry
  FIVE entries: the four calendar `:26.11.1` lines (the moving ones) + the
  `ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04` line
  (unchanged in both — chart L151, dev L203). The C04 review fact's
  "five lines total" is the five-entry shape; the runbook's "the dev
  slice's own four label lines" is the four that move. The dev-slice
  comment (L188-196) still says "must re-declare ALL FIVE entries … (t17
  pins the exact five-set)" — intact.
- **The gpu site carries NO pin** — `services/gpu/prod/values.yaml:271-280`
  (`forgejo-runner-gpu`) has `runner.url: https://git.spencerslab.com` +
  `replicas: 10` and **no `runner.labels` key** (gpu-forgejo-runner.sh g3
  asserts the absence) ⇒ the gpu release rides the chart default; the chart
  bump covers it.
- **No other image references**: `containers/` (Dockerfile header prose
  only), `.forgejo/` (build-charts:23 comment; builder-bootstrap:112/172 —
  the bootstrap lane's own target, not a pin), `custom-values/` none. The
  `:26.11.1` literal appears exactly in the 8 pin lines + the suite
  surfaces (R4-Q6) + the runbook text (R4-Q6).
- Chart comment law (L125-146, intact post-r8): the 26.11.1 bootstrap
  provenance ("owner-built and pushed to BOTH registries by hand
  2026-11-22" — note: the current 26.11.1 manifest's build mtime is
  11-23 18:01, so the tag's content was re-rolled/re-pointed at some
  point; the re-pointing mechanism is not visible at agent tier),
  immutable calendar tags, no renovate manager reads the pin lines, **the
  bump is manual across BOTH pin sites AND BOTH registries** (push the new
  tag to git.spencerslab.com and git.scifi.farm, then move the chart
  default and the dev slice together), rolling refs forbidden.

### R4-Q5 — Rebuild lanes (for the record — NOT required)

- **build-containers dispatch (the byte-frozen hatch)**:
  `.forgejo/workflows/build-containers.yaml` (origin/main) `on:` L96-113 =
  `pull_request` (main, `paths: ['containers/**']`) + `workflow_dispatch`
  (input **`containers`**, `description: 'Container names to build
  (comma/space separated)'`, `required: false`, `default: ''`,
  `type: string`, L103-109) + `workflow_call: {}` (L113). A rebuild = a
  forge UI/API dispatch with `containers: forgejo-runner`; it fires on the
  ROLE builder class (widens on unset), builds from the current tree, mints
  the next calendar tag (a hypothetical 26.11.6) + `latest` + `main` to
  both registries; it **never advances the marker**. The trigger is
  owner/UI-side (no anonymous trigger path at agent tier).
- **builder-bootstrap (the alternative lane)**: `workflow_dispatch` only (no
  inputs; the P1 ruling), narrow-on-unset ROLE (prod-only — a dev-role
  dispatch is inert by the guard), **target = the building instance's own
  registry ONLY** (no ghcr arm of any shape; the calendar number is walked
  from that registry alone; the FORGE push PAT is the only credential).
  A no-input dispatch from the prod-instance UI.

### R4-Q6 — Test surfaces that byte-pin the label lines (re-pin work list for the test session)

| suite | leg | what it pins (exact strings) |
|---|---|---|
| `tests/services/dev-forgejo-runner.sh` | **t2** (L526) | the `ACT_LABELS` five-set (L309-315): the four `git.spencerslab.com/…forgejo-runner:26.11.1` lines + `ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04` — the chart-default render |
| `tests/services/dev-forgejo-runner.sh` | **t17** (L1022) | the `DEV_LABELS` five-set (L992-998): the four `git.scifi.farm/…forgejo-runner:26.11.1` lines + the act-22.04 line — the dev slice override |
| `tests/services/gpu-forgejo-runner.sh` | **g2** (L310) | the same `ACT_LABELS` five-set (L264-270) — the gpu release rides the chart default |
| `tests/services/gpu-forgejo-runner.sh` | **g3** (L397-399) | the gpu slice carries **no** `runner.labels` key (a bump must not add one) |

- `tests/containers/forgejo-runner.sh` (9 legs, the bake contract) pins the
  **Dockerfile**, not the tag — unaffected by a pin bump.
- `tests/renovate/services-values-pins.sh` **v8** (L404-412): a **regex
  behavior table** (does the calendar versioning regex match the
  hypothetical `26.11.1`/`26.11.2` vs `v84`/`main`/`latest`) — not a
  live-line pin; unaffected.
- `tests/services/dev-mcp-fleet-t7-shape.sh` **s4** (L155-166): the same
  shape — a regex-shape test with `:26.11.1`/`:26.11.2` as calendar-form
  examples; unaffected.
- `.agents/notes/2026-11-25-coder-template-push.md` (runbook) UA3
  (L222-258): carries `26.11.1` as "the current pin" (L230, L258) and
  `tag=26.11.2` as "the expected next calendar tag" (L245) — **doc-level
  staleness after a bump to 26.11.5**; `tests/notes/
  coder-template-push-runbook.sh` pins postures, not the tag (grep-verified
  no `26.11` in the suite) — a runbook-text reword is an optional hygiene
  item, not a gate. The runbook UA3's ghcr one-liner and its instance-
  registry "anonymous pull" phrasing are both stale against this round's
  probes (the ghcr anonymous flow is denied; the instance registry wants
  the realm-JWT — a bare curl 401s).

## Round-4 gotchas

1. **The pre-15:01 runner logs are gone** — the 14:39 r8 chart revert's
   rollout (15:01–15:07) replaced all ten gpu runner pods, so the 03:52
   merge-fan build's console is unrecoverable at agent tier. The 26.11.5
   layer mtime + the green-marker progression carry the evidence.
2. **The 18:25 fan's marker non-advance** — the advance job ran (18:25:28,
   pod8) but the live ref (19:13Z) still sits at `b50a5395c`; the
   18:22–24 commits sit behind the marker (re-covered on the next green
   fan by design). The cause is not visible at agent tier.
3. **`ci/containers-built` (the r4-era ref) is still live** @ `52d3b5c45`
   (its UA-R5-3 deletion is owner-pending); `ci/last-built` is now live
   (the C14 pre-steps have landed — R3 recorded them as not-yet).
4. **The 26.11.2–4 tag identity** — same manifest as 26.11.1 (pre-bake,
   built 11-23 18:01); their minting mechanism (comment-only-Dockerfile
   fan re-mints, escape-hatch dispatches, or manual tag re-pointing) is
   not visible at agent tier. They are inert for the bump (the pin moves
   to 26.11.5 regardless).
5. **The dev side is doubly inert at the moment** — no dev runner workload
   on the dev cluster (appset entry default-enabled + slice `replicas:
   10`; the cause is not visible at agent tier) + the dev-registry package
   is `NAME_UNKNOWN`. The dev-slice pin bump still belongs in the bump
   (the law moves both sites together); the dev-registry 26.11.5 push is
   the UA-leg-2 owner job.
6. **The runbook UA3 instance-registry one-liner 401s as written** (a bare
   curl; the realm-JWT is required — this round's flow), and its ghcr
   flow is denied (R4-Q1) — a runbook hygiene follow-up, not this round's
   scope.

## Round-4 open questions (for coord/owner)

1. **The ghcr-side confirmation of 26.11.5** — the agent tier can no
   longer read ghcr for this package (the anonymous flow is denied; the
   control package works). Owner-side confirmation (forge/GH UI) that
   26.11.5 is on ghcr.io/ownyourio per the dual-publish law — the UA3
   leg's shape.
2. **The 18:25 fan's marker non-advance** — the owner may want that fan's
   run log from the forge UI (the job console is server-side). Not a
   delivery loss (the re-cover law), just unexplained at agent tier.
3. **The dev runner's absence** — the appset entry is default-enabled +
   the slice `replicas: 10`, yet the dev cluster carries no runner
   workload, and the dev-registry package is `NAME_UNKNOWN`. If the OQ10
   dev-side dispatch leg is still intended, the dev runner's deployment +
   the dev-registry copy are owner-side preconditions (neither is visible
   at agent tier).
