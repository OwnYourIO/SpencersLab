# Coder template push — operator runbook (AD-56)

Every command in this file is **human-executed**: this repo never applies
to a cluster (AGENTS.md law — ArgoCD is the sole apply surface), and the
pipeline never mints or authenticates: the workflow's only Coder verb is
the push itself, while the mints and the read-only checks are operator
legs (the plan's "Human-owned list", UA1–UA4). Background lives in the
ticket folder
`.agents/plans/2026/2026-11-cf-56-feat-forgejo-coder-template-pipeline/`
(plan of record; `DECISIONS.md` — the 2026-11-25 batched round answered
every OQ, so the postures in §7 are those answers, not open questions).

## 1. What this is / what it is not

- **Is**: `.forgejo/workflows/coder-template-push.yaml` — the sixth
  `.forgejo/workflows/` file — driving per-template `coder templates
  push` calls (`scripts/coder-template-push.sh`) for the changed template
  dirs under `charts/coder/coder-templates/` (the detect gate is
  `scripts/coder-template-detect.sh`), publishing a new active version to
  the Coder instance hosted by the executing Forgejo instance. The
  endpoint comes from the instance-side repo var `CODER_URL`, the token
  from the repo secret `CODER_SESSION_TOKEN` (the OQ5-minimal vault:
  exactly one var + one secret per instance) — the card's ask: the
  endpoint from a variable, the token from the vault.
- **The two Coder instances and their Forgejo hosts** (per-instance
  vault placement — the workflow file is identical-safe to host on both,
  the instance-side placement is what this runbook documents):

  | instance | Coder host | executing Forgejo | vault placement |
  |---|---|---|---|
  | dev | `https://coder.dev.scifi.farm` | the dev instance (git.scifi.farm) | repo var `CODER_URL` + repo secret `CODER_SESSION_TOKEN` on the dev repo |
  | prod-stage | `https://coder.spencerslab.com` | the infra/prod-stage instance (git.spencerslab.com) | the same var + secret on that repo |

  Each executing instance pushes every changed template to its own Coder
  (OQ1). The dev Coder hosts the `kubernetes-hardened` template's home
  (its git-auth secrets live there); the gpu Coder the `kubernetes` one
  (the legacy template is managed against it) — but the pipeline does
  not filter by affinity: every changed template goes to every
  configured instance (OQ1: each instance pushes every changed template
  to its own).
- **The guard arithmetic (narrow on unset)**: every job guards on
  `if: contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')` —
  `ROLE` is the AGENTS.md hard-rule membership variable (a repo-scoped
  comma list without spaces over `{dev, prod}`); `contains()` is a
  case-insensitive substring that never errors on a hand-typed value,
  where a guard expression that errors fails the job while a false one
  only skips it. Unlike `containers-build.yaml` (widens on unset), an
  unset `ROLE` renders empty and fires nothing here on purpose: this
  pipeline publishes to an external service, so it must never fire
  unconfigured (the `release.yaml` fail-safe class). Rollback is the
  same arithmetic in reverse (§8).
- **The value-var-free posture (OQ5)**: the script passes no `--var` of
  any kind — no `CODER_USE_KUBECONFIG` value var, no value env of any
  kind. Template input values ride the auto-loaded `terraform.tfvars`
  (the GitOps single source of truth, including the three version pins
  in `kubernetes/terraform.tfvars`) + the `main.tf` defaults, including
  `namespace = "default"` — added to both templates' tfvars by C02 and
  verified on both instances (both coderd releases sit in `default`; the
  gpu `dev-shared` PVC carries no namespace key → `default`; the dev
  git-auth secrets `github-pat`/`forgejo-token` are in `default` — the
  hardened template's own header requirement). `--ignore-lockfile` is
  pinned in the push script because neither template dir ships a
  `.terraform.lock.hcl`; a lockfile appearing later changes nothing (the
  flag is a no-op then, dropping it would re-noise the log).
- **The SEQUENCING consequence of the OQ3 ruling (owner: bake the Coder
  CLI into `containers/forgejo-runner`)**: the runner image rebuild (the
  merge's `containers-build.yaml` fire publishes the new calendar tag)
  AND the hand-bumped chart label pin (UA3) must land BEFORE the first
  template push fires. A first fire on the pre-bake image dies at the
  diag's plain `coder version` call with `command not found: coder` —
  that is the sequencing state, loud by design (the D43 class), not a
  pipeline bug.

## 2. Trigger and exit posture (nothing to create)

No webhook to add and nothing to enable — the jobs are the mechanism:

- Triggers: `push` on `main` filtered to
  `charts/coder/coder-templates/**`, plus `workflow_dispatch` with the
  `templates` escape-hatch input (an empty list pushes nothing — the
  `containers-build.yaml` shape). No PR leg: fork heads carry empty
  secrets and a read-only token, and a PR push would mint an active
  template version — every push mints one.
- Guard: `if: contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')`
  on both jobs — an unset `ROLE` or a value matching neither member fires
  nothing (narrow on unset, the fail-safe class for external-service
  publishes).
- The detect job (`fetch-depth: 0` checkout — detection diffs the whole
  `before..sha` range, the V-6-1 shallow-clone law) runs
  `scripts/coder-template-detect.sh detect` and feeds the `push` job's
  `fail-fast: false` matrix over
  `fromJSON(needs.detect-changes.outputs.changed-templates)`; an empty
  changed set skips the whole matrix (the designed no-op, with the
  detector's own exemption arithmetic: a no-op ref update and an empty
  dispatch list stay silent, every other empty set warns).
- The vault is mapped into the push job's `env` block ONLY —
  `CODER_URL` + `CODER_SESSION_TOKEN` — never interpolated into the run
  body or argv (the `argocd-fanout.py` doctrine); the script hands the
  token to the coder CLI as the environment variable only.
- Exit posture (the `main-sync.yaml` unset-vault class): an
  unconfigured instance (the var or the secret absent) warn-and-skip
  skips green per template — the script prints the missing key to a
  `::warning::` line and exits 0, designed, not an incident. A
  configured auth failure — a 401 from a stale or revoked token — fails
  the template's matrix cell red (loud by design); the warn-and-skip
  green is the unconfigured state only. Per-template isolation: one
  template's 401 does not cancel its siblings (fail-fast: false).
- The jobs run on the lab's job image exactly as today (`runs-on:
  ubuntu-24.04`, no `container:` field — the four non-renovate
  workflows' shape; the `renovate.yaml` container: job is the sole
  deviation, one tool with no upstream-lab fit); the Coder CLI is the
  forgejo-runner bake (C01) behind the label the label routes to, and
  the diag's plain `coder version` call is the toolchain check (D43).

## 3. UA1 — Mint the dev-Coder token + place the dev vault (human-executed)

For the dev Coder at `https://coder.dev.scifi.farm`, on the dev Forgejo
instance (git.scifi.farm):

1. Mint the CI token at the server's max allowed lifetime — the CLI's
   30-day default is the monthly-401 trap (OQ6; the server's
   `--max-token-lifetime` is the cap a mint may not exceed), named after
   its consumer:

   ```bash
   # human-executed — UA1: mint the dev-Coder CI token (server max
   # lifetime, OQ6 — the 30-day CLI default is the monthly-401 trap)
   export CODER_URL=https://coder.dev.scifi.farm
   coder login
   coder tokens create --name forgejo-coder-template-push --lifetime <server-max-lifetime>
   ```

2. Place the vault on the dev repo (Settings → Actions): the repo secret
   `CODER_SESSION_TOKEN` = the minted token; the repo var `CODER_URL` =
   `https://coder.dev.scifi.farm`. Confirm the instance's `ROLE` var
   contains `dev` (the guard arithmetic, §1) — a value matching neither
   member leaves the pipeline silent on that instance.

## 4. UA2 — Mint the gpu-Coder token + place the prod-stage vault (human-executed)

The same two steps for the gpu Coder at `https://coder.spencerslab.com`,
on the infra/prod-stage Forgejo instance (git.spencerslab.com):

1. Mint the CI token at the server's max allowed lifetime (OQ6), named
   after its consumer:

   ```bash
   # human-executed — UA2: mint the gpu-Coder CI token (server max
   # lifetime, OQ6 — the 30-day CLI default is the monthly-401 trap)
   export CODER_URL=https://coder.spencerslab.com
   coder login
   coder tokens create --name forgejo-coder-template-push --lifetime <server-max-lifetime>
   ```

2. Place the vault on the prod-stage repo (Settings → Actions): the repo
   secret `CODER_SESSION_TOKEN` = the minted token; the repo var
   `CODER_URL` = `https://coder.spencerslab.com`. Confirm the instance's
   `ROLE` var contains `prod` (the guard arithmetic, §1).

Until both vaults are placed, every fire warn-and-skip skips green per
template — designed, not an incident.

## 5. UA3 — Verify the published runner tag + hand-bump the chart label pin (human-executed)

The OQ3 ruling's bake lives in `containers/forgejo-runner`; the merge's
`containers-build.yaml` fire publishes the new `forgejo-runner` calendar
tag (dual: ghcr + the executing instance's own registry — the dev-role
builds only mint `pr-*` tags, so the dev registry's copy is manual, the
chart's own comment). The runner's chart label pin is the routing law:
the labels are how jobs route, no renovate manager reads these lines
(the chart's own comment: the pins are immutable calendar tags, a wrong
pin fails loudly as a pull error), so the bump is manual — the AGENTS.md
law.

1. After the merge fire, verify the new calendar tag is published — the
   next `yy.mm.N` past the current pin `26.11.1` (i.e. `26.11.2` or
   higher; check that the newest is YOURS — a build that predates the
   merge you ship can already occupy a higher N, the container-creation
   skill's warning). The registry-side read is the pull-scoped-token
   shape: `GET https://ghcr.io/token?scope=repository:ownyourio/forgejo-runner:pull`
   plus `GET https://ghcr.io/v2/ownyourio/forgejo-runner/tags/list`. Do
   NOT enumerate with an untagged `docker buildx imagetools inspect` —
   untagged, it resolves `:latest` (a rolling tag every main build
   repoints) and lists nothing (the skill's explicit warning). The same
   manifest read applies to the instance registry (anonymous pull):

   ```bash
   # human-executed — UA3: verify the new calendar tag on ghcr + the
   # instance registry (the pull-scoped-token shape; untagged imagetools
   # inspect resolves :latest and lists nothing — the skill's warning)
   tag=26.11.2   # the expected next calendar tag — confirm it is the merge's own build
   ghcr_token=$(curl -fsS "https://ghcr.io/token?scope=repository:ownyourio/forgejo-runner:pull" | jq -r .token)
   curl -fsS -o /dev/null -w 'ghcr %{http_code}\n' -H "Authorization: Bearer $ghcr_token" "https://ghcr.io/v2/ownyourio/forgejo-runner/manifests/$tag"
   # the instance registry (the infra forge host, the curatedforest owner, anonymous pull)
   curl -fsS -o /dev/null -w 'instance-registry %{http_code}\n' "https://git.spencerslab.com/v2/curatedforest/forgejo-runner/manifests/$tag"
   ```

2. Push the same new tag to the dev registry (git.scifi.farm) — the dev
   slice's pin rides it and the dev role's builds never mint calendar
   tags, so an unpushed registry copy freezes that site's runner on the
   old immutable tag forever, silently (the chart's own comment: a site
   or a registry left behind rides its old immutable tag forever).

3. Hand-bump the pin sites to the new tag, together: the four act-24.04-family label lines in `charts/forgejo-runner/values.yaml` (currently `:26.11.1`) AND the dev slice's own four label lines in `services/dev/prod/values.yaml` (`forgejo-runner-dev.runner.labels`) — Helm replaces label lists wholesale, so the dev site's list moves with the chart default (the chart's own comment). No renovate lane reads these pins — the bump is by hand, this is the AGENTS.md law.

4. ArgoCD syncs the runner releases (the sole apply surface — nothing
   here touches a cluster directly). Only after the runner pods run the
   new image may a template push fire; the UA4 watch is the proof.

## 6. UA4 — First-fire watch (human-executed)

1. Fire the first push on purpose: a `workflow_dispatch` run with the
   `templates` input naming one template (or a template edit on main).
   Watch the run log: the detect job's endpoints line, then the push
   job's diag — `ROLE`, event, `coder version` (the toolchain check: a
   pre-bake image dies here, the §1 sequencing state).
2. Verify auth + the new active version, per instance (human-executed;
   the token from the instance's vault secret — never argv):

   ```bash
   # human-executed — UA4: verify auth, then confirm the new active
   # version (the token from the instance's repo secret — never argv)
   export CODER_URL=https://coder.dev.scifi.farm
   export CODER_SESSION_TOKEN=<the instance's minted token>
   coder whoami
   coder templates versions list kubernetes
   ```

   (The prod-stage instance: the same two commands against
   `https://coder.spencerslab.com`; or the Coder UI — Templates →
   `<template>` → Versions: the new version active, named by the short
   sha, message `forgejo <event> <sha>`.)
3. Watch the egress assumption: the runner→coder-host API call is the
   watched assumption (the runner's egress lane has a history of
   targeted upstream filters, the D33 class); a red 401/network
   failure is loud by design — if the call cannot reach the host, the
   owner opens the lane, the pipeline is not at fault.
4. If the instance was still unconfigured, the run log carries the
   warn-and-skip lines (the script's `::warning::` naming the missing
   key, exit 0 green) — the designed state until the vault is placed.

## 7. Ruled postures (the answers, not open questions)

The 2026-11-25 batched round answered every OQ; these are those answers,
stated as answers:

- **A 401 is red.** A configured auth failure (a stale or revoked token)
  fails the template's matrix cell red — loud by design; the
  warn-and-skip green is the unconfigured state only, and the two states
  must read differently in the log, and they do.
- **Unconfigured = warn-and-skip green (per template).** An absent var
  or secret is a designed skip: the script names the missing key on a
  `::warning::` line and exits 0 (the `main-sync.yaml` unset-vault
  posture).
- **Per-template isolation.** The `fail-fast: false` matrix: one
  template's red does not cancel its siblings' pushes.
- **Tokens are minted at the server's max lifetime (OQ6).** The CLI's
  30-day default is the monthly-401 trap; rotation is the same move —
  re-mint (UA1/UA2) and overwrite the vault secret, the next run uses
  the new token immediately.
- **`--ignore-lockfile` is pinned (no lockfile shipped).** Neither
  template dir ships a `.terraform.lock.hcl`; the flag is a no-op if a
  lockfile appears later, so it stays.
- **The `--default-ttl 168h` edit stays user-owned (OQ7): the pipeline does not re-assert it** — the 2026-10-19 fusion plan's user edit is a separate `coder templates edit` action, a push does not reset template-level settings, and nothing in this pipeline re-asserts the default-TTL.
- **Template deletion and rename are user-owned (OQ9).** Server-side `coder templates delete` (a rename is a delete + a re-push under the new name) are operator actions: the pipeline pushes tree names only and mirrors neither — a server-side rename or deletion never fires it.
- **No `--var` ever; values ride the in-repo tfvars (OQ5).** The single
  residual mechanism, documented as an answer: if an instance's
  workspace namespace ever diverges from coderd's, the whole fix is one
  `--var namespace=...` fed from one instance-side var, added to the
  push script — a documented residual mechanism, not an open question.
- **The runner→coder-host egress is the watched assumption.** The runner
  egress lane has a history of targeted upstream filters (the D33 class,
  `get.helm.sh`); a red 401/network failure at push time is loud by
  design, UA4's watch covers it.
- **The runner image + the label pin are the sequencing legs (OQ3).**
  The merge's `containers-build.yaml` fire plus the UA3 hand-bumped pin
  must land before the first push — a first-fire `command not found:
  coder` is that sequencing state, not a pipeline bug.

## 8. Rollback

1. **Instant (no git):** delete — or overwrite with empty — the
   instance's repo secret `CODER_SESSION_TOKEN` (or unset the repo var
   `CODER_URL`): the next fire warn-and-skip skips green per template,
   and the script's `::warning::` line naming the missing key is the
   proof-of-unset. The instance reverts to manual template pushes, as
   before the ticket.
2. **The guard flip:** flip the instance's `ROLE` word out of the guard
   (remove the `dev`/`prod` membership): the jobs skip without firing,
   and the var + secret may stay in place for a later re-activation.
3. **Server-side:** when the pipeline is retired, remove the minted
   token (`coder tokens remove`, the mint name from UA1/UA2); while it
   lives, rotation is the same move — re-mint and overwrite the vault
   secret, the next run uses the new token immediately (no refresh
   window, no pod restart).

State plainly: nothing else changes anywhere — the template tree layout,
the tfvars, the chart, and the ArgoCD wiring are untouched by
rollback; a rolled-back instance simply stops receiving pipeline pushes,
and its last active template version stays active (a push only ever
added versions; rollback removes none).
