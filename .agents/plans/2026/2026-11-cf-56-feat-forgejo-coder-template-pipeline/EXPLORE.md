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
