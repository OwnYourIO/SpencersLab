# 2026-10-26 cluster-health follow-ups (uncommitted batch)

Type: bug — three follow-ups from the 2026-10-26 fleet crash/memory sweep.
Per user instruction all edits are **left uncommitted on `main` in the main
checkout**; landing (PR/merge) and the cluster-side remediation are user-owned.

## 1. Home postgres-MCP `DATABASE_URI` failures — diagnosis, no repo change

Symptom: `mcp-postgres-{home-rallly,immich,paperless,postiz}` pods
crashlooping ~25 h; events: `couldn't find key DATABASE_URI in Secret
default/postgres-mcp-*`.

Findings (readonly cluster inspection):

- The 2026-10-19 airman migration (`2026-10-19-feat-postgres-mcp-airman-adoption.md`,
  commit `d7dd2a52f`) renamed the secret key `DATABASE_URI` →
  `AIRMAN_MCP_DATABASE_URL` in one step; the repo currently renders exactly
  one `secrets:` entry (AIRMAN) per MCPServer.
- On home the ExternalSecrets re-rendered correctly (template keys =
  `AIRMAN_MCP_DATABASE_URL`, `secret synced`) — but the four MCPServer CRs
  carry **both** the stale `DATABASE_URI` and the new entry, and ArgoCD
  reports `home-hivetools` Synced/Healthy (the merge residue is invisible to
  selfHeal). The operator propagated the stale entry into the backend
  StatefulSet env, whose pod sits in `CreateContainerConfigError` and whose
  rollout is stuck (`currentRevision` ≠ `updateRevision`); the proxy pods
  crash behind it. The gpu cluster (same chart) shows the clean single-entry
  spec — the divergence is cluster-side only.
- Repo-side: **nothing to change**. Remediation is to delete the four stale
  MCPServer CRs so ArgoCD's automated sync recreates them from the repo
  spec (cascade GC removes the stuck child STS/Deployments). This is an
  `admin-home-kubernetes` mutation and was presented to the user for
  confirmation; it was NOT executed by this session.

## 2. `forgejo-token-canonical` removal (user ruling: no longer used)

Ticket context: `2026-10-feat-forgejo-auth-support` (C03 landed the wiring,
C04 was blocked on the never-created Bitwarden item). The user declared the
canonical PAT plumbing unused and ordered its removal — dev workspaces still
reach git.spencerslab.com via SSH keys and the gpu coder's external-auth
provider, so host pre-trust/banner stay.

Removed:

- `services/dev/prod/templates/secret-forgejo-token-canonical.yaml` (deleted —
  fixes the recurring `UpdateFailed` event; ArgoCD prunes the ES on merge,
  owner-GC removes the target Secret)
- `bitwardenIds.forgejo-token-canonical` sentinel — `services/dev/prod/values.yaml`
- `forgejo-token-canonical: OVERRIDE_NEEDED` must-fill slot — `custom-values/dev/prod-values.yaml`
- `FORGEJO_TOKEN_CANONICAL` + `FORGEJO_HOST_CANONICAL` env blocks —
  `charts/coder/coder-templates/kubernetes-hardened/main.tf`
- canonical `wire_forgejo` call + pair mentions — `containers/coder-workspace/workspace-startup.sh`
  (coder-workspace image rebuilds from `:main` on merge; running workspaces
  are unaffected because the pair was optional-guarded)

Contract tests updated in the same change (checks retired or inverted to pin
the wiring **absent**):

- `tests/services/dev-git-auth.sh` — c-canonical-1..4 deleted; c-canonical-5
  legs inverted (render must contain no canonical ES / no `OVERRIDE_NEEDED`);
  header/precedent comments fixed
- `tests/services/dev-forgejo-runner.sh` — t9 pinned-slot tolerance removed,
  blanket `OVERRIDE_*`-outside-appset ban restored
- `tests/services/dev-mcp-fleet.sh` — canonical UUID ladder leg + presence
  expectation replaced by an absence pin
- `tests/services/forgejo-ssh-gateway.sh` — `--set bitwardenIds.forgejo-token-canonical`
  leg dropped from the t8 render ladder
- `tests/coder-workspace/startup-script.sh` — 4 canonical env/wire/helper
  checks retired
- `tests/coder-workspace/startup-sso-behavior.sh` — b-7 flipped to "no
  CAN_HOST credential call may reappear"; harness stops exporting the pair
- `tests/services/gpu-coder-sso.sh` — stale "canonical precedent" comment →
  infra-forgejo t6 precedent (assertions untouched)

## 3. karakeep meilisearch CrashLoopBackOff

`docker.io/getmeili/meilisearch` pinned `v1.55.0` while args still passed
`--experimental-dumpless-upgrade`; upstream **renamed the flag to
`--upgrade-db` in v1.51.0** (dumpless upgrade stabilized; "exactly the same
behavior"), so clap exits 2 — Renovate bumps the tag but not the args, hence
the crash started at the 1.35.1→1.55.0 jump.

Fix in `services/home/prod/values.yaml`: args now
`["/bin/meilisearch", "--upgrade-db"]` + why-comment. Image facts verified
from the upstream Dockerfile: `ENTRYPOINT ["tini","--"]` with shell CMD
(args replace CMD wholesale), `WORKDIR /meili_data` (the DB path default
lands on the existing `subPath: meilisearch` mount), and the DB is currently
v1.35-format → the upgrade flag is required, matching the prior posture.

## Validation

- Suites: `dev-git-auth.sh` PASS 36 ok · `gpu-coder-sso.sh` PASS ·
  `startup-script.sh` 38/0 · `startup-sso-behavior.sh` 22 ok PASS ·
  `dev-forgejo-runner.sh` / `dev-mcp-fleet.sh` / `forgejo-ssh-gateway.sh` —
  only pre-existing-at-HEAD failures remain (t2 dind pin `29.9.2≠29.9.1`,
  t7 playwright `v0.0.83≠v0.0.78`, gateway t1 storm-runs move + t11
  audit-trail), each proven red on an unmodified `HEAD` worktree;
  `image-structure.sh` (4 fail) and `dockerfile-pins.sh` (2 fail) likewise
  pre-existing renovate-drift, not in this batch's scope.
- `bash -n` all touched suites; `dash -n` + `sh -n` workspace-startup.sh.
- `helm lint` `services/dev/prod`, `services/home/prod` — 0 failed; coder
  chart copy `dependency build`/`lint`/`template` — OK, 0 canonical refs,
  sentinel classes unchanged; home umbrella render — `--upgrade-db` present,
  `--experimental-dumpless-upgrade` absent.
- `terraform init -backend=false` + `validate` on a scratch copy of
  `kubernetes-hardened` — "Success! The configuration is valid."
- `npx aislop scan --changes` — 100/100, 0 findings.

## Deferred to the user

- Commit/PR these changes (left uncommitted on `main` per instruction).
- After merge: ArgoCD prunes `forgejo-token-canonical` (dev), re-renders
  karakeep (home), and the coder-workspace image rebuilds.
- Home MCPServer CR cleanup (item 1 remediation): the agent attempted
  `admin-home-kubernetes` `resources_delete` on the four CRs (user-approved)
  and got `Forbidden` — that is the documented RBAC boundary
  (`rbac-kubernetes-mcp.yaml`: admin tier has no CR write/delete, no
  argoproj.io writes). User action, either:
  - ArgoCD UI → `home-hivetools` → Sync with `Replace=true` (plain re-sync
    won't do: SSA leaves other managers' fields, which is why selfHeal shows
    the app Synced over the residue), or
  - `kubectl delete mcpservers.toolhive.stacklok.dev -n default
     mcp-postgres-home-rallly mcp-postgres-immich
     mcp-postgres-paperless mcp-postgres-postiz`
    (automated sync recreates them from the repo spec within seconds).
