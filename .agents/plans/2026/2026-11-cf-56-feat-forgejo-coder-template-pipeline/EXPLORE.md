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
