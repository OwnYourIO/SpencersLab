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

---

# Replan v2 (2026-10-24): per-user SSO approval — Coder external-auth ↔ Forgejo

## Goal delta

C01–C03 shipped the shared/bot-PAT model and stay done and frozen. This replan
layers the user's actual ask on top: **per-user "SSO approval" git identity**,
implemented by the native Coder v2.35.2 External Auth Provider of type
`gitea` — the browser consent runs against Forgejo (backed by the existing
Keycloak session), coderd stores + auto-refreshes the per-user token, and the
workspace agent injects it over https via `GIT_ASKPASS`. One provider per Coder
instance (the community license caps external-auth at one; each instance
spends its slot on its paired forge), PAT plumbing stays as bootstrap /
fallback / OpenChamber floor / canonical-from-dev access.

## Topology verification (replan GATE — evidence, 2026-10-24)

The user's two-Coder claim **verifies**; the research's single-Coder assumption
is corrected, and the "single-Coder fallback" question (user-secrets Beta) is
moot:

| | dev | gpu |
|---|---|---|
| coder deployment | `default/coder` 1/1, `ghcr.io/coder/coder:v2.35.2`, age 11d | `default/coder` 1/1, `ghcr.io/coder/coder:v2.35.2`, age 386d |
| hosts | ingress `coder.dev.scifi.farm` + wildcard `*.dev.scifi.farm` | ingresses `coder.spencerslab.com`, `code.spencerslab.com`, wildcard `*.spencerslab.com` |
| access URL | `CODER_ACCESS_URL=https://coder.dev.scifi.farm` (`charts/coder/templates/secret-coder.yaml`: subDomain+domain) | `CODER_ACCESS_URL=https://coder.{{ .Values.domain }}` = `coder.spencerslab.com` (`services/gpu/prod/templates/secrets-coder.yaml`) |
| served via | internal wrapper chart `charts/coder` (appset `charts.coder`) | external chart `helm.coder.com/v2` pin `2.35.2` |
| secrets | `coder-secrets` ES in `charts/coder/templates/secret-coder.yaml` (envFrom verified live on both) | `coder-secrets` ES in `services/gpu/prod/templates/secrets-coder.yaml` |
| paired forge | git.scifi.farm (dev, same cluster) | git.spencerslab.com (canonical, infra) |
| workspaces today | `coder-1f725e1a…` running `ghcr.io/ownyourio/coder-workspace:main` (kubernetes-hardened, 174m) | `coder-9539094a…` running `codercom/enterprise-base:ubuntu` (legacy template lineage) |

Cluster source: readonly-dev/infra-kubernetes (+gpu) resource reads; repo
source: `services/{dev,gpu}/prod/values.yaml`, `custom-values/{dev,gpu}/
prod-values.yaml`, `charts/coder/**`. Infra cluster runs no coder.
Keycloak 26.7.2 (infra, realm SpencersLab) already backs both forges' login —
the consent click is a Keycloak session hop, not a new password prompt.

## Replan scope delta

**In:** per-Coder `gitea`-type provider env provisioning (both coder-secrets
templates), `CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS` at-rest encryption (user
ruling; keys via new Bitwarden items + ExternalSecrets), reloader
pod-annotations so coderd picks up the secret-change restart, workspace
polite-gate/banner + per-host OAuth-over-PAT layering (dev pair only),
kubernetes-hardened `FORGEJO_OAUTH_ID` literal, test extensions.

**Out (this replan):** Coder Premium multi-provider per instance (not needed —
one slot each); device flow (Forgejo issue #4830 open — endpoints 404, live-
verified); moving gpu workspaces off the legacy enterprise-base template to
`coder-workspace` (their OAuth works via agent askpass regardless; the gate/
banner story there is a follow-up ticket); `fj keys.json` laptop-bootstrap
per-user OAuth; retiring the legacy `kubernetes/` template; Coder User Secrets
fallback (moot — both forges get a slot); any change to OpenChamber's per-user
PAT cards (structurally PAT-bound).

**Consequence of the user's pairing ruling (assumption, not question):**
dev-cluster workspaces keep the **shared bot PAT** for canonical
(git.spencerslab.com) — the dev coder's single slot is spent on the dev forge.
Per-user identity for canonical exists only from gpu-coder workspaces. If the
user wants canonical per-user *in dev workspaces*, the slot flips to canonical
and dev-forge stays PAT — say so before approving.

## New chunks (C04–C06) — pending only; C01–C03 stay done/approved

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C04 | dev coder server: provider env + token encryption + reloader (charts/coder) | M | 3 | [] | layers on shipped files only as pure additions; dev-git-auth's C02/C03 checks are regressions, not deps |
| C05 | gpu coder server: same for the canonical pairing (services/gpu) | M | 3 | [] | independent of C04 — zero shared files (gpu umbrella + custom-values/gpu vs charts/coder + custom-values/dev) |
| C06 | workspace polite gate + banner + per-host layering + `FORGEJO_OAUTH_ID` env | M | 4 | [C04] | the c-sso-5 drift trap compares the provider-id literal across both files; with no C04 provider the probe only ever takes the fallback branch |

C05 is independent of both (no workspace leg on the gpu coder in this ticket;
gpu askpass works from the server config alone). Interface-first: C04/C05
create the provider slots, C06 consumes them. Each chunk = one reviewable
diff, no renumbering of done chunks; waves continue the existing numbering.

## Commands (additions to the replan section only)

- test: `bash tests/services/gpu-coder-sso.sh` (new, C05)
- test: `bash tests/coder-workspace/startup-sso-behavior.sh` (new, C06)
- test: `bash tests/services/dev-git-auth.sh` (extended c-sso-1..7)
- test: `bash tests/coder-workspace/startup-script.sh` (extended SSO statics)
- render: `helm template charts/coder --set domain=test.example.com --set bitwardenIds.coder-external-auth=test-uuid --set bitwardenIds.coder-token-encryption=test-uuid2` → coder-secrets doc carries the seven external-auth/encryption keys, test UUIDs resolved, no sentinel
- render: `helm template gpu services/gpu/prod --set domain=test.example.com --set bitwardenIds.coder-external-auth=test-uuid --set bitwardenIds.coder-token-encryption=test-uuid2` → same on the gpu umbrella (baseline render already proven exit-0)
- validate: `terraform init -backend=false && terraform validate` on a scratch copy of `kubernetes-hardened/` (`/home/coder/.local/bin/terraform`)

(`helm`/`terraform` off-PATH, exit-codes-without-pipes, stub-PATH git probes:
per FRICTION.)

## User actions (replan; post-merge, not agent-executable)

1. **OAuth app on each Forgejo** (v15.0.9 has no admin-scope API for this —
   UI `/admin/applications`, or user-scope `POST /api/v1/user/oauth2` with any
   PAT; source-verified route). Two apps:
   - on git.scifi.farm → redirect
     `https://coder.dev.scifi.farm/external-auth/forgejo/callback`, confidential,
     grants authorization_code + refresh_token;
   - on git.spencerslab.com → redirect
     `https://coder.spencerslab.com/external-auth/forgejo/callback`, same shape.
   The callback path embeds the provider id — a mismatch fails with
   "redirect URI is not valid" (v2.35.2 docs).
2. **Four new Bitwarden items**: per cluster, `coder-external-auth`
   (username = client id, password = client secret) and `coder-token-encryption`
   (password = fresh `dd if=/dev/urandom bs=32 count=1 | base64` output —
   a wrong-length key crashloops coderd on restart). Replace the four
   `OVERRIDE_NEEDED` slots (custom-values dev + gpu) with the UUIDs in a
   follow-up commit.
3. After ArgoCD syncs: confirm each coderd restarted (reloader) and shows the
   `Forgejo` external-auth provider (UI → External Auth Providers); the
   consent re-prompt cadence (access 1h / refresh ~30d rotating) is observable
   live at this step (research left it UNVERIFIED).
4. Dev cluster: push a new `kubernetes-hardened` template version
   (`coder templates push`) carrying `FORGEJO_OAUTH_ID`, restart workspaces.
5. Per-user approval: open the banner URL (or run
   `coder external-auth access-token forgejo` in a workspace terminal and open
   what it prints) → one Forgejo consent click via the Keycloak session.
   Verified state: next boot logs "per-user SSO"; terminal git runs as the
   user; the dev host's PAT helper is gone (git askpass answers instead).
6. Encryption key rotation later: prepend the new base64 key
   comma-separated (first encrypts, rest decrypt-only — v2.35.2 docs).

## Risks / assumptions (replan)

- OAuth grants are **full-account** on Forgejo (no OAuth scopes in v15 —
  docs verbatim); user explicitly accepted this as the price of per-user
  identity. Weaker containment than the shipped scoped PATs on the scope
  axis; stronger on the identity/blast-radius axis (1h TTL, per-user
  revocable grant, no shared secret).
- Until a user approves, boots run on the bot PAT — the transition to
  per-user identity is gradual and per-user by design.
- The new `coder-secrets` entries sit inert (ES unresolvable) until the
  Bitwarden items exist; during that window the whole `coder-secrets`
  target stops refreshing (OIDC rotation would lag) — keep the
  item→UUID→sync order tight.
- Consent-click count per approval UNVERIFIED (research §C7); refresh-token
  rotation is one-time-use (Forgejo default) — coderd is the only holder
  inside the workspace, no cross-device race expected, but laptop `fj auth
  login` chains would race the PVC story; out of scope here.
- code-server (module 1.6.0) historically overrode GIT_ASKPASS (2024-era
  fix reports) — live-verify per-user identity in code-server terminals at
  User-action 5; settings `git.terminalAuthentication=false` /
  `git.useIntegratedAskPass=false` are the documented mitigations.
- gpu workspaces on the legacy template gain per-user askpass for canonical
  automatically (server-side provider + agent injection) but no banner/fj
  gate there; that image move is a separate ticket.

