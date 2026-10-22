# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- "Tests" in this repo = validation scripts under `tests/` (structural/grep/bash), `helm lint`/`helm template` renders, sentinel sweeps, and service-trio grep checks. There is no unit-test suite (AGENTS.md "Pipeline specifics").
- Work happens on the feature branch in the coordinator's worktree; merge/push to main is the user's decision alone.
- Secrets: ExternalSecret + Bitwarden only. Sentinel `OVERRIDE_VIA_CUSTOM_VALUES` in chart/service values; real UUIDs only in `custom-values/<category>/prod-values.yaml`; `OVERRIDE_NEEDED` placeholders in custom-values until the user creates the items and pastes UUIDs (dev-plan round-3 precedent).
- New chart versions start at `1.0.0`; CI (release.yaml) bumps on merge — never hand-bump.
- Image tags pinned; never `latest` (repo image-tag rule).

## Decisions
- 2026-10-21 plan: RESEARCH.md (commissioned, 2026-10-21) is ground truth for item B (the runner). Its findings were re-verified against the live dev cluster via readonly MCP where cheap: dev-forgejo (15.0.9, chart forgejo-17.2.0) Running, Service `dev-forgejo-http:3000` ClusterIP, pg-forgejo-1 (CNPG) Running, CNPG operator present on dev.
- 2026-10-21 plan: Live infra cluster verified via readonly MCP — CNPG operator Running (pg-keycloak-1 on local-path proves the pattern), seaweedfs (master + 5 filers + 8 volumes + s3 + csi-driver) Running, 389ds/keycloakx/smtp-relay-mail Running, no forgejo present. The pre-existing seaweedfs PV+PVC `git` (RWX, 30Gi request, collection git, replication 002, Retain) is live in `default`.
- 2026-10-21 plan: Runner registers in-cluster against `http://dev-forgejo-http.default.svc:3000` (research implication #4) — the runner is a client; no ingress/proxy entry for it. Rejected: registering against the public host (adds a TLS/DNS dependency for an in-cluster client).
- 2026-10-21 plan: Runner labels = the default `docker:docker://data.forgejo.org/oci/node:lts` plus a `dev` label for `runs-on:` targeting (research implication #5).
- 2026-10-21 plan: `charts/forgejo-runner` new-chart `version: 1.0.0`; app-template dependency at the repo standard 5.0.1 (verified against charts/qdrant + the proxy-local umbrella); `ServerSideApply: "false"` on the dev `charts.forgejo-runner` entry (gpt-researcher precedent for app-template app workloads).
- 2026-10-21 plan: The infra Forgejo instance consumes the EXISTING `charts/forgejo` wrapper unchanged in code — its templates (CNPG cluster + 3 ExternalSecrets) ride with the chart; per-instance identity (DOMAIN/ROOT_URL, APP_NAME, admin email, storage, mailer) is layered in the infra tier, mirroring how dev's identity rides custom-values/dev. (Final shape depends on the user's answer to the chart-parameterization question.)
- 2026-10-21 plan: proxy-local `git` retarget = `target: infra` (ExternalName `infra.spencerslab.com` → infra traefik), the same apex-host convention as the live `grow`/`gpu`/`gpu-ai`/`home-lab` entries.
- 2026-10-21 plan: `services.infra.customValuesUrls` is assumed loaded (verified by inference — see FRICTION); the plan's User actions list carries the confirmation.
- 2026-10-21 plan: The untracked `storm-runs/forgejo-act-runner-on-kubernetes-for-spencerslab-dev-cluster/` audit trail at repo root is relocated into this feature folder (or dropped) per the user's answer; RESEARCH.md stays the distillation.

## User answers (2026-10-21, question round)
- 2026-10-21 human: A1 Auth = **OIDC only** (lab Keycloak, auto-registration; new client `infra-forgejo`). Rejected: LDAP-only (leftovers' untested intent), OIDC+LDAP (over-maintained for a lab instance).
- 2026-10-21 human: A2 Storage = **local-path PVC 10Gi (dev parity)**. Rejected: the pre-existing seaweedfs `git` RWX claim — it stays in place, now idle (follow-up notes it).
- 2026-10-21 human: A3 Canonical host = **git.spencerslab.com** (DOMAIN/ROOT_URL); forgejo.spencerslab.com is the alias. Keycloak client carries redirect URIs for both.
- 2026-10-21 human: A4 forgejo.spencerslab.com routing = **proxy-local hub entry** (public chain like git; external-dns auto-publishes). Rejected: user-owned split-horizon record only (LAN-only).
- 2026-10-21 human: A5 Hub middleware = **crowdsec-only** (paste/forms pattern) on both hosts. Rejected: hub Keycloak forward-auth (breaks git/token clients — the erp-documented tradeoff).
- 2026-10-21 human: A6 Mailer = **enabled via smtp-relay-mail** (FROM git@spencerslab.com). Rejected: off (dev parity).
- 2026-10-21 human: A7 Leftovers = **delete all** (dormant forgejo: block, secret-gitea*.yaml, bitwardenIds.gitea/gitea-admin + custom-values UUIDs, commented ingress).
- 2026-10-21 human: A8 Chart handling = **parameterize charts/forgejo** — neutral defaults (APP_NAME "Forgejo", admin email forgejo@example.com); dev literals migrate to custom-values/dev (render parity required); infra literals in custom-values/infra. Rejected (by the user, over the plan's recommendation): overrides-only with the chart code untouched.
- 2026-10-21 human: A9 Secrets plan confirmed (infra-forgejo / -admin / -pg / -sso items + lab Keycloak client infra-forgejo; OVERRIDE_NEEDED in custom-values/infra until filled).
- 2026-10-21 human: B1 Workload = **StatefulSet** replicas 1. Rejected: Deployment (plan recommendation). Consequence: app-template `statefulset.volumeClaimTemplates` own the 2 PVCs (no raw PVC templates); a headless service (`clusterIP: None`) is required.
- 2026-10-21 human: B2 DinD pin = **docker:29.9.1-dind**. Rejected: 28.3.0-dind.
- 2026-10-21 human: B3 Registration = **instance-admin runner created once via UI** on git.scifi.farm; uuid+token → new Bitwarden item. Rejected: API creation (the forgejo-token item is Coder-scoped in intent), repo-scoped runner.
- 2026-10-21 human: B4 Runner item name = **forgejo-runner** (LOGIN: username=uuid, password=token).
- 2026-10-21 human: H1 Audit trail = **moved into the feature folder**, lands in the first dev commit (→ C01 runs first). Rejected: dropping it.
- 2026-10-21 human: Plan approved as written; `plan_status` set to `approved` (recorded 2026-10-22).

## Test round (agent-test, 2026-10-22)
- 2026-10-22 cord: C01 audit trail = **13 files, not 11** (verified: `find storm-runs/ -type f | wc -l` = 13 — 3 top-level + 5 perspective notes + 5 source TSVs; the chunk text miscounted). The test's explicit 13-file list + exact-count check is the acceptance; the whole-directory move is intended. C01.md's "11" is stale — read the test as the contract.
- 2026-10-22 cord: C03 `templates/common.yaml` task **DROPPED** — app-template 5.0.1 render breaks with a parent-level `bjw-s.common.loader.all` include (rbac.roles nil pointer; agent-test reproduced in a sim repo), and no repo chart ships one (grep across charts/ = 0 hits; qdrant/gpt-researcher carry only extra-resource templates). The chart's templates/ holds only `secret-forgejo-runner.yaml` (+ optional NOTES.txt). C03.md's common.yaml bullet is stale — read the test as the contract.
- 2026-10-22 cord: Accepted test-contract deviations (agent-test RESULT): (1) C02 sentinel sweep matches by KEY under any bitwardenIds mapping (repo nesting differs between service values and custom-values), not strict path 1:1; top-level scalar sentinels match at custom top level; a matched value still being a sentinel fails. (2) C02 gitea-leftover checks are scoped to rendered manifests + services/infra/prod + secret references — `forgejo.forgejo.gitea:` as a values STRUCTURE key in custom-values/infra is legitimate (chart schema, per C02's own spec). (3) C02 dev-parity check (t5) passes pre-implementation by design — it guards the A8 migration, not an addition.
- 2026-10-22 cord: Test files are the immutable contract for C01–C03: `tests/services/audit-trail.sh` (4 checks), `tests/services/infra-forgejo.sh` (33), `tests/services/dev-forgejo-runner.sh` (21). All three verified red-for-the-right-reason in the worktree and green against a faithful sim implementation (/tmp/opencode/sim-fj).

## Deferred
- Forgejo 15.0.9 → 15.0.10 patch bump on dev (separate `dep` ticket; the OCI dependency is manually bumped per the Chart.yaml note).
- Renovate coverage for the OCI forgejo chart dependency (carried over from the dev plan's follow-ups; unchanged by this ticket).
- `services/backups/prod/Chart.yaml` still pins the gitea chart with a "TODO: Replace gitea with forgejo" (backups service, separate work).
- proxy-remote changes: explicitly out of scope this ticket (user directive).
- 2026-10-22 review(C02): pre-existing samba chart default `bitwardenIds.samba-users: OVERRIDE_NEEDED` appears in the infra appset values blob with no matching key in custom-values/infra — byte-identical pre/post this ticket (not introduced here); candidate follow-up ticket.
- 2026-10-22 cord: runner identity mechanism correction — the v13.2.0 daemon never writes a `.runner` file (source-verified by review(C03): only the deprecated register/create-runner-file CLIs do); restart re-attach works because the uuid+token pair persists in Bitwarden and re-arrives via the ExternalSecret-rendered config, and the server matches the runner record by uuid. The three shipped comment sites (charts/forgejo-runner values.yaml header + data VCT, NOTES.txt) were corrected in C03 dev round 2 (commit 9c90f0c89). RESEARCH.md (~lines 80/178/195) and chunks/C03.md "Notes for dev" still carry the stale gitea-era `.runner` framing — left as-is on purpose: both are historical artifacts of record; this entry is the correction.
