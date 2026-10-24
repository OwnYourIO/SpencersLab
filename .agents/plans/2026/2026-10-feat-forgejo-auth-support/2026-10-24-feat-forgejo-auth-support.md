# PLAN: Forgejo auth support — Coder workspaces + OpenChamber (both instances)
feature: 2026/2026-10-feat-forgejo-auth-support

## Goal

Give Coder workspaces (and the OpenChamber UI inside them) authenticated git + API
access to BOTH lab Forgejo instances — the infra canonical `git.spencerslab.com`
and the dev instance `git.scifi.farm` — via per-instance PATs wired through the
existing ExternalSecret/env/credential-helper stack, and upgrade the workspace
image to the OpenChamber release that introduced Forgejo support.

OpenChamber's Forgejo feature is the connection: **v2.5.1** ("Tea time for git",
published 2026-10-23) added Gitea/Forgejo/Gerrit git hosts to Settings →
Integrations; it requires **OpenCode ≥ 2.1.0** (bundled 2.1.3). The workspace
image pins `@openchamber/web` 2.4.0 / `@opencode/cli` 2.0.32 — both must move.
Connection itself is a one-time UI step per user (paste instance URL + PAT); the
sign-in is stored on the OpenChamber server, i.e. under `~/.config/openchamber`
on the workspace home PVC, so it survives restarts (docs.openchamber.dev/integrations).

## Out of scope

- OAuth/SSO between Forgejo and Coder/OpenChamber (Keycloak already fronts both; user declined).
- Registering Forgejo as an ArgoCD GitOps repo source (user declined).
- The legacy `charts/coder/coder-templates/kubernetes/` template and its
  `terraform.tfvars` pins (superseded by `kubernetes-hardened`; see DECISIONS).
- `forgejo-runner` config (both runners already wired in the sibling ticket).
- Adding Forgejo repo URLs to the `repos` coder_parameter options — deferred until
  repos exist on the forges (the template comment already anticipates this).
- Public-internet git SSH (sibling decision: mesh/LAN only).

## Research basis (quick lookups, verified 2026-10-24 — no agent-research needed)

- OpenChamber v2.5.1 release notes (github.com/openchamber/openchamber/releases):
  "Git hosts: Gitea, Forgejo and Gerrit join GitHub and GitLab… Codeberg is ready
  on the Forgejo card"; "Bundled OpenCode updated to 2.1.3. OpenChamber now needs
  OpenCode 2.1.0 or later."
- docs.openchamber.dev/integrations (fetched): Forgejo card = instance address +
  personal access token with **`write:repository`, `write:issue`, `read:user`**
  scopes; needs **Forgejo ≥ 7.0 served from the root of its address**; sign-in
  stored on the OpenChamber server and shared across web/desktop/phone.
- npm dist-tags (fetched): `@openchamber/web` latest **2.5.1**; `@opencode/cli`
  latest **2.1.4**.
- Repo floor check: `charts/forgejo/Chart.yaml` appVersion **15.0.9** → both
  instances satisfy the ≥7.0 root requirement (ROOT_URLs are bare-host roots).
- Cross-cluster reachability from dev workspaces to the canonical instance is
  live-proven: `forgejo-runner` `runner-infra` dials `https://git.spencerslab.com`
  from dev (comment in `services/dev/prod/values.yaml`).

## Global constraints

- Secrets: ExternalSecret + Bitwarden only; `OVERRIDE_VIA_CUSTOM_VALUES` sentinel
  in `services/dev/prod/values.yaml`, UUID in `custom-values/dev/prod-values.yaml`
  (the documented `OVERRIDE_NEEDED` placeholder is acceptable until the user
  creates the Bitwarden item — infra-forgejo precedent).
- No new coder template VARIABLES with server-stored values (the 2026-10-04
  stored-values trap): hosts go in as literal container env, like the existing
  `FORGEJO_HOST`.
- Startup script stays POSIX `sh` (`set -eu`, runs under bash/dash -n); token env
  names stay a template↔script contract (`dev-git-auth.sh` c6 pattern).
- Renovate annotations in the Dockerfile must stay intact and unchanged
  (attribute order is part of the extraction contract).

## Commands

Run from repo root; `helm` resolves to `/home/coder/.local/bin/helm`.
All four suites pass at plan time on this branch (baseline recorded in DECISIONS).

- test: `bash tests/coder-workspace/image-structure.sh`
- test: `bash tests/coder-workspace/startup-script.sh`
- test: `bash tests/renovate/dockerfile-pins.sh`
- test: `bash tests/services/dev-git-auth.sh`
- lint: `sh -n containers/coder-workspace/workspace-startup.sh && dash -n containers/coder-workspace/workspace-startup.sh`
- render: `helm dependency build charts/coder && helm lint charts/coder && helm template charts/coder`
  (dependency build first — fresh-worktree gotcha from the rebuild ticket's friction log)
- render: `helm template dev services/dev/prod --set bitwardenIds.forgejo-token-canonical=test-uuid` → the `forgejo-token-canonical` ExternalSecret renders, no `OVERRIDE_*` sentinel in it
- currency: `curl -fsS https://registry.npmjs.org/@openchamber/web/latest` (pin floor check at implementation time)

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | OpenChamber/Forgejo-capable image pins (2.5.1 + OpenCode 2.1.4) | S | 1 | [] | — |
| C02 | workspace-startup.sh: dual-host Forgejo auth + :22222 known_hosts | M | 1 | [] | — |
| C03 | canonical token plumbing: ExternalSecret + custom-values + template env | M | 2 | [C02] | the template emits the exact env names C02's script consumes; dev-git-auth's c6 cross-check compares them |

C01 and C02 are independent (different files, no shared interface); run in id
order. C01 is also independently revertable (a version bump nothing else reads).

## Wave order

1. C01, C02 (independent; run in id order)
2. C03

## User actions (post-merge, not agent-executable)

1. Create a PAT on **git.spencerslab.com** (a dedicated account is fine) with
   scopes `write:repository`, `write:issue`, `read:user` → new Bitwarden item
   `forgejo-token-canonical` (token in the PASSWORD field, per the
   `forgejo-token` convention) → replace `OVERRIDE_NEEDED` in
   `custom-values/dev/prod-values.yaml` with the item UUID and push.
2. Check the existing `forgejo-token` (git.scifi.farm) PAT carries those same
   three scopes; recreate if not (OpenChamber's card needs them on both hosts).
3. After ArgoCD syncs services/dev + the CI image rebuild: push a new
   `kubernetes-hardened` template version (`coder templates push`) and restart
   workspaces so they pick up the new image + env.
4. In each workspace: OpenChamber → Settings → Integrations → **Forgejo** card →
   add `https://git.spencerslab.com` and `https://git.scifi.farm`, pasting the
   matching PAT into each. The connection persists on the home PVC.
5. Live-verify from a workspace: `git clone`/`push` over https to both hosts;
   `git clone ssh://git@<host>:22222/...` (register the printed SSH key on both
   instances first); `fj auth list` shows both hosts; an OpenChamber PR/issue
   board row loads from each Forgejo card.

## Risks / assumptions

- Pin currency: 2.5.1 / 2.1.4 are latest as of 2026-10-24; if newer exist at
  implementation, use the newest ≥ floor and mirror it into the three test
  expectations (C01 criterion 4).
- OpenChamber Forgejo connection has no documented env/file bootstrap — UI paste
  only. If a headless seeding surface appears later, it is a follow-up ticket.
- `ssh-keyscan -p 22222` from a dev pod to the infra node presumes mesh/LAN
  reachability of the ServiceLB port; the script's existing warning-only pattern
  keeps a miss non-fatal (manual host-key acceptance as fallback).
- The shared Bitwarden PAT model (one token item consumed by all workspaces on
  dev) inherits the posture of the existing `forgejo-token` item — per-user
  tokens would need a Coder external-git-auth redesign, out of scope here.
- `OVERRIDE_NEEDED` in custom-values must NOT ship as-is to the cluster forever;
  the ExternalSecret would fail at the store. User action 1 closes it; the test
  keeps the sentinel-free contract honest.
- Bumping OpenChamber may change other UI behaviors; the waiver/bind posture
  (`OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true`, 0.0.0.0:3000) stays exactly as
  ruled 2026-10-21 — C01 touches no startup wiring, C02 keeps it intact.
