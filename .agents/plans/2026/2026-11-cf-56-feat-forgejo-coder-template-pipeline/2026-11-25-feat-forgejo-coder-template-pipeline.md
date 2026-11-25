# PLAN: Forgejo pipeline for Coder templates
feature: 2026/2026-11-cf-56-feat-forgejo-coder-template-pipeline

## Goal
When a file under `charts/coder/coder-templates/**` changes on `main`, a Forgejo Actions
pipeline runs `coder templates push` for the changed template(s), deploying a new active
version to the Coder instance hosted by the executing Forgejo instance — endpoint from a
repo variable, token from a repo secret (the card's ask, the `main-sync.yaml`
instance-side doctrine: no URL or token literal in the file). The Coder CLI is baked
into the lab's job image `containers/forgejo-runner` (owner ruling, OQ3). Exactly one
var (`CODER_URL`) + one secret (`CODER_SESSION_TOKEN`) per instance (owner ruling,
OQ5 — "Just need to login and push the template"): every template input value comes
from the repo — `terraform.tfvars` per template + `main.tf` defaults — including
`namespace`, verified `default` on BOTH instances (both coderd releases sit in
`default`; the gpu `dev-shared` PVC is `default`; the dev git-auth secrets
`github-pat`/`forgejo-token` are `default`).

## Out of scope
- The user-owned `coder templates edit --default-ttl 168h` (2026-10-19 fusion plan) —
  the pipeline does not re-assert it (ruled OQ7).
- Server-side template deletion/rename — user action; the pipeline pushes tree names only (ruled OQ9).
- Bitwarden/ExternalSecret wiring — the card explicitly asks for the Forgejo vault
  (the CI-side twin of the in-cluster pattern).
- Chart/appset/proxy changes — the Coder instances already exist; this is CI-side only.
  The `charts/forgejo-runner` chart label pin is deliberately NOT a chunk task: the
  repo law is that no Renovate lane reads that pin — it is bumped by hand to the newest
  published calendar tag (AGENTS.md), and that bump is a runbook owner leg (UA4).
- Local `docker build` of the runner image — no daemon in agent sessions; the merge
  fire's `containers-build.yaml` run is the authoritative build (designed gate shape,
  cf-77 ruling 2026-10-28).

## Commands (all runnable in THIS environment)
- helm lint: `export PATH=$HOME/.local/bin:$PATH && helm lint charts/coder`
- helm render: `export PATH=$HOME/.local/bin:$PATH && helm template charts/coder`
- chart packaging guard (coder-templates must stay out of the published tgz):
  `export PATH=$HOME/.local/bin:$PATH && helm dependency build charts/coder >/dev/null && rm -rf /tmp/opencode/helm-pkg && helm package charts/coder -d /tmp/opencode/helm-pkg >/dev/null && tar -tzf /tmp/opencode/helm-pkg/coder-*.tgz | grep -c 'coder-templates/'` — expected `0`
- shell syntax: `bash -n scripts/coder-template-detect.sh && bash -n scripts/coder-template-push.sh`
- workflow YAML parse: `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .forgejo/workflows/coder-template-push.yaml`
- test (structural suites): `bash tests/coder/coder-template-push.sh && bash tests/coder/coder-template-detect.sh && bash tests/coder/coder-template-push-script.sh && bash tests/containers/forgejo-runner.sh && bash tests/notes/coder-template-push-runbook.sh`
- hadolint (Dockerfile contract, error threshold): `~/.local/bin/hadolint --failure-threshold error containers/forgejo-runner/Dockerfile`
- smoke: terraform validate, scratch copy — never `init` inside the repo, for BOTH `kubernetes` and `kubernetes-hardened` (verified working in-session 2026-11-25):
  `export PATH=$HOME/.local/bin:$PATH && export TF_PLUGIN_CACHE_DIR=/tmp/opencode/tf-plugin-cache && rm -rf /tmp/opencode/tf-validate-<tmpl> && mkdir -p /tmp/opencode/tf-validate-<tmpl> && cp charts/coder/coder-templates/<tmpl>/main.tf /tmp/opencode/tf-validate-<tmpl>/ && (cd /tmp/opencode/tf-validate-<tmpl> && terraform init -backend=false -input=false && terraform validate)`
- quality gate (aislop 0.18.1 accepts ONE path per invocation — the 4-argument form dies with "Expected 1 argument but got 4"): `npx --yes aislop@0.18.1 ci scripts/ && npx --yes aislop@0.18.1 ci .forgejo/ && npx --yes aislop@0.18.1 ci containers/forgejo-runner && npx --yes aislop@0.18.1 ci charts/coder/coder-templates` (record honest scope: 0.18.1 scores shell/YAML and does not score Dockerfiles — `containers/forgejo-runner`'s Dockerfile is hadolint's territory, the hadolint line above)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Bake the Coder CLI into `containers/forgejo-runner` (Dockerfile edit + existing suite extension) | M | 1 | [] | |
| C02 | Push engine: detect + push scripts, tfvars `namespace` supply, their suites | M | 1 | [] | independent of C01 — the scripts run inside the image at runtime; the fake-binary tests need no image |
| C03 | Workflow + owner-leg runbook + parity suites | M | 2 | [C01, C02] | data: the workflow invokes C02's scripts and relies on C01's baked CLI (the diag toolchain check); the runbook parity suite compares the runbook against the landed workflow + scripts + the image's label-pin leg |

C01 and C02 are independent (wave 1 runs them in id order).

## Wave order
1. C01, C02 (independent; run in id order)
2. C03

## Design (ruled — the batched plan-question round of 2026-11-25 settled every OQ)
- One endpoint per executing instance (OQ1 confirmed): instance-side repo var
  `CODER_URL` + repo secret `CODER_SESSION_TOKEN`; the dev instance pushes to its
  Coder, the prod-stage instance to its, each pushing the changed templates.
- Narrow-on-unset ROLE class, both role members (OQ2 confirmed): `if:
  contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')` (no null clause — the
  `release.yaml` fail-safe class for external-service publishes).
- Trigger (OQ2 confirmed): `push` main + `paths: ['charts/coder/coder-templates/**']`
  + `workflow_dispatch` with a `templates` escape-hatch input (the
  `containers-build.yaml` shape). No PR leg (fork heads carry empty secrets; a PR
  would mint an active version).
- CLI acquisition (OQ3 RULED — owner override, supersedes the prior D2): the Coder CLI
  is baked into `containers/forgejo-runner` — a digest-pinned stage over the official
  `coder/coder` image (ghcr pull — the proven lane, the run-4 "change the source, not
  the path" posture), sha256-anchored per the repo's bump recipe, renovate-annotated
  like the existing helm/cr pins. The runner's calendar tag is hand-bumped (AGENTS.md
  law — no Renovate lane reads that pin; the chart label pin bump is a runbook owner
  leg). Rejected by the ruling: a separate `containers/coder-cli` image and run-time
  fetch (the D33 flaky-egress class).
- Jobs run on the lab's job image exactly as today: `runs-on: ubuntu-24.04` with no
  `container:` field — the same shape as the other four non-renovate workflows; the
  CLI is behind the label the labels already route to. The diag step's plain
  `coder version` call is the toolchain check (the D43 class).
- `CODER_SESSION_TOKEN` env name (OQ4 confirmed, supersedes D4's uncertainty): the
  script reads exactly `CODER_URL` + `CODER_SESSION_TOKEN`, token env-only, never argv
  (the `argocd-fanout.py` doctrine); the runbook verifies auth with `coder whoami`
  before first use.
- Minimal vault (OQ5 RULED, supersedes D5): exactly one var + one secret. Template
  input values come from the repo — `terraform.tfvars` (auto-loaded on push) +
  `main.tf` defaults. Verified against the actual template files: the ONLY required
  variable without a repo-side value in both templates is `namespace` (required, no
  default, absent from tfvars today); every other variable has a `main.tf` default,
  and the three version pins already live in `kubernetes/terraform.tfvars`.
  `namespace = "default"` is valid for BOTH instances (coderd `default` on dev AND gpu;
  the gpu `dev-shared` PVC unnamespaced → `default`; the dev git-auth secrets
  `default` — the hardened template's own header requirement). Settled: C02 adds
  `namespace = "default"` to both templates' tfvars (the hardened one is created).
  The single residual mechanism, documented as a runbook answer, not a question: if an
  instance's workspace namespace ever diverges from coderd's, one `--var
  namespace=...` from one instance-side var is the whole fix.
- Token lifetime (OQ6 confirmed): mint at the server's max allowed lifetime (the
  30-day default is a monthly-401 trap); rotate by vault overwrite.
- `--default-ttl 168h` NOT re-asserted (OQ7 confirmed); rename/delete not mirrored
  (OQ9 confirmed); the prior OQ8 retags onto the forgejo-runner calendar-tag story —
  the runbook's verify-the-published-tag leg (UA4).
- Push semantics: `-y --ignore-lockfile --name <short-sha> --message "forgejo <event>
  <sha>"`; `--activate` default true = the card's "deploy on change". A detection job
  (modeled on `scripts/forgejo-container-detect.sh`) limits pushes to the templates
  that actually changed — every push mints a version (EXPLORE gotcha 7), so unchanged
  siblings must not churn.
- Exit posture (the `main-sync.yaml` doctrine): unconfigured instance (URL or token
  absent) → `::warning::` + skip green; a configured 401/auth failure → red; per-template
  isolation via `fail-fast: false` matrix.

## Rulings (settled in the batched plan-question round, 2026-11-25 — recorded in DECISIONS.md)
| # | Question | Ruling | Plan effect |
|---|----------|--------|-------------|
| OQ1 | Push target | Confirmed: per-instance, both Coders; each executing Forgejo pushes every changed template to its own instance | instance-side `CODER_URL`/`CODER_SESSION_TOKEN`, both instances fire |
| OQ2 | Trigger + ROLE class | Confirmed: main-push + paths filter + dispatch escape hatch; narrow-on-unset `contains(vars.ROLE,'dev') \|\| contains(vars.ROLE,'prod')`; no PR leg | the workflow trigger/guard shape |
| OQ3 | CLI acquisition | RULED: bake into `containers/forgejo-runner` (supersedes D2) | C01 re-scoped to the runner Dockerfile edit; the hand-bumped chart label pin becomes a runbook owner leg; the image-rebuild-before-first-push sequencing lands in UA4 + Risks |
| OQ4 | Token env name | Confirmed: `CODER_SESSION_TOKEN` (+ `CODER_URL`); runbook verifies with `coder whoami` | the script's env contract |
| OQ5 | Vault minimalism | RULED: exactly one var + one secret; values from in-repo tfvars/templates (supersedes D5) | the four value vars dropped; `namespace = "default"` added to both templates' tfvars (verified both instances) |
| OQ6 | Token lifetime | Confirmed: server max lifetime; rotate by vault overwrite | runbook UA1/UA2 |
| OQ7 | `--default-ttl 168h` | Confirmed: stays user-owned, not re-asserted | runbook posture |
| OQ8 | coder-cli first tag | Moot as posed (no coder-cli image) — folded into the forgejo-runner calendar-tag story | runbook UA4 verify-the-published-tag leg |
| OQ9 | Rename/delete | Confirmed: not mirrored | runbook posture |

## Risks / assumptions
- SEQUENCING (the OQ3-ruling consequence): the runner image rebuild (merge →
  `containers-build.yaml` → new calendar tag) AND the owner's hand bump of the
  `charts/forgejo-runner` chart label pin (the four act-label lines, AGENTS.md law —
  no Renovate lane reads that pin) must land BEFORE the first template push fires —
  otherwise the first fire runs on the pre-bake image and dies at the `coder version`
  diag. The runbook's UA4 + UA5 own this; a first-fire `command not found: coder` is
  a sequencing state, not a pipeline bug.
- Runner egress has a history of targeted upstream filters (D33, `get.helm.sh`): the
  image BUILD pulls the `coder/coder` stage over the ghcr lane (proven); the
  runner→coder-host API call at push time is an assumption — the runbook's first-fire
  watch (UA5) covers it, and a red 401/network failure is loud by design.
- `terraform validate` here needs egress to registry.terraform.io (verified
  2026-11-25); the test suites themselves are offline (house shape) — validate is a
  plan/dev smoke. The tfvars edit changes what a push RESOLVES (namespace becomes a
  persisted resolved value instead of a workspace-creation prompt) — that is the
  intended GitOS-ification of the value, verified `default` on both instances.
- Every push mints a version (gotcha 7) — the detection job is what keeps unchanged
  siblings from churning; a dispatch with an empty list is a designed no-op.
- No docker daemon in agent sessions: the runner-image build proof is the merge fire's
  containers-build run; local gates are the static contract suite + hadolint + the
  container-creation skill's sanctioned GHCR layer-tar-listing verification of the
  binary path/digest.

## Human-owned (owner) legs — runbook, C03
UA1 mint a dev-Coder token (server max lifetime) → dev Forgejo repo secret
`CODER_SESSION_TOKEN` + repo var `CODER_URL`; UA2 the same for the gpu Coder on the
prod-stage Forgejo; UA3 verify the new `forgejo-runner` calendar tag is published and
hand-bump the chart label pin to it (the AGENTS.md law); UA4 watch the first fire
(dispatch or a template edit) + `coder whoami` / `coder templates versions` check.
