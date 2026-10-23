# PLAN: Second Forgejo instance on infra + Forgejo Actions runner on dev

feature: 2026/2026-10-feat-forgejo-infra-and-runner

## Goal

Stand up a second Forgejo instance on the **infra** cluster (served locally at
both `git.spencerslab.com` and `forgejo.spencerslab.com`, routed through the
proxy-local hub, wired to the lab Keycloak, replacing the dormant gitea-era
leftovers) and a new `charts/forgejo-runner` chart on the **dev** cluster that
runs a declaratively-registered Forgejo Actions runner with a privileged DinD
sidecar. RESEARCH.md (commissioned, in this folder) is ground truth for the
runner; all repo context below was re-verified 2026-10-21/22 at main
`abfbb6a2d` + live readonly MCP.

## Out of scope

- **proxy-remote** — untouched this ticket (user directive).
- Moving the runner to infra — user: "I don't expect to ever move the runner
  to infra"; dev-specific literals are acceptable for the runner.
- Forgejo 15.0.9 → 15.0.10 patch bump on dev (separate `dep` ticket; the OCI
  chart dependency is manually bumped per the `charts/forgejo/Chart.yaml` note).
- `services/backups/prod/Chart.yaml` gitea chart dependency (separate service).
- Unit tests — none in this repo; validation scripts + helm renders ARE the tests.
- The seaweedfs `git` PV/PVC: user chose local-path for the infra instance, so
  the pre-existing claim stays untouched (now unclaimed-by-design; noted in follow-ups).

## Decisions (user, 2026-10-21, question round)

| # | Question | Answer |
|---|---|---|
| A1 | Auth on infra | **OIDC only** (lab Keycloak realm SpencersLab, auto-registration — dev parity). No LDAP. |
| A2 | Data storage on infra | **local-path PVC 10Gi** (chart default, dev parity). SeaweedFS `git` claim not used. |
| A3 | Canonical host (DOMAIN/ROOT_URL) | **`git.spencerslab.com`**; `forgejo.spencerslab.com` serves as alias. |
| A4 | `forgejo.spencerslab.com` routing | **proxy-local hub entry** (same chain as git: external-dns → proxy-remote → hub → infra). |
| A5 | Hub middleware for the git hosts | **Crowdsec-only** (paste/forms pattern); Forgejo authenticates git clients itself. |
| A6 | Mailer on infra | **Enabled via `smtp-relay-mail`** (FROM `git@spencerslab.com`). |
| A7 | Leftovers cleanup | **Delete all** (dormant `forgejo:` values block, `secret-gitea*.yaml`, `bitwardenIds.gitea/gitea-admin` + custom-values UUIDs, commented ingress). |
| A8 | `charts/forgejo` handling | **Parameterize**: neutral chart defaults; per-instance literals move to each cluster's custom-values (dev values migrated so its render is unchanged). |
| A9 | Infra secrets plan | **Confirmed**: items `infra-forgejo`, `infra-forgejo-admin`, `infra-forgejo-pg`, `infra-forgejo-sso` + new lab Keycloak client `infra-forgejo` (redirect URIs for BOTH hosts). |
| B1 | Runner workload | **StatefulSet**, replicas 1 (per-ordinal identity; app-template `statefulset.volumeClaimTemplates`). |
| B2 | DinD pin | **`docker:29.9.1-dind`**. |
| B3 | Registration | **Instance-admin runner, created once via UI** on git.scifi.farm; uuid+token → new Bitwarden item. |
| B4 | Runner item name | **`forgejo-runner`** (LOGIN: username=uuid, password=token; must NOT reuse `forgejo-token`). |
| H1 | `storm-runs/` audit trail | **Move into the feature folder**; lands in the first dev commit. |

## Verified repo/cluster context (2026-10-21/22)

- `charts/forgejo` — wrapper around `oci://code.forgejo.org/forgejo-helm` 17.2.0
  (Chart.lock committed; `version: 1.0.4`, CI-bumped). Templates: `pg-forgejo.yaml`
  (CNPG Cluster, local-path 5Gi, SSA annotation), `secret-forgejo.yaml`
  (SECRET_KEY + OIDC key/secret from `forgejo`/`forgejo-sso` items),
  `secret-forgejo-admin.yaml`, `secret-forgejo-db.yaml`. Subchart ingress disabled;
  routed via the consumer's generic-ingress at `<fullname>-http:3000`. Dev-flavored
  literals: `APP_NAME: "SpencersLab Dev"`, `admin.email: forgejo@scifi.farm`.
  OIDC source: lab Keycloak `autoDiscoverUrl`.
- **dev live** (MCP): `dev-forgejo-*` Running (15.0.9), Service
  `dev-forgejo-http` ClusterIP :3000, `pg-forgejo-1` (CNPG pg18) Running, CNPG
  operator Running. Dev umbrella has NO Chart.yaml dependencies (direct
  `helm template` works).
- **infra live** (MCP): CNPG operator Running (`pg-keycloak-1` on local-path
  proves the pattern), seaweedfs full stack Running, `389ds`/`keycloakx`/
  `smtp-relay-mail-0` Running, **no forgejo present**. The `git` seaweedfs
  PV/PVC (RWX 30Gi, collection git, repl 2) exists and is idle. `smtp-relay`
  chart `fullnameOverride: smtp-relay-mail` → in-cluster SMTP service name.
  Infra ArgoCD is v3.4.5 (chart argo-cd-10.1.4) — OCI chart sources supported.
  `services.infra.customValuesUrls` verified by inference only (MCP cannot read
  argocd secrets; live synced secrets + real UUIDs in the file) — user-confirms.
- `services/infra/prod` — umbrella deps: cloudnative-pg 0.27.1 + samba 1.0.15
  (Chart.lock present, deps NOT vendored → `helm dependency build` first).
  Dormant: `forgejo:` values block (old gitea schema — NOT in the `charts:` map,
  so it renders nothing), `secret-gitea*.yaml` (TODO-marked, never tested),
  `bitwardenIds.gitea/gitea-admin`, commented `git:` ingress block.
- `services/proxy-local/prod` — `proxy.subdomains.git: {target: gitea}` (dead;
  default middleware chain = crowdsec + `userAuth`). Templates (verified by
  reading): explicit `middlewares:` + `ingressRoute.middlewares` override the
  default chain on both the Ingress and the LAN IngressRoute (priority 100);
  `target` → ExternalName `<target>.<domain>`; non-clusterBase entries get
  `external-dns: enabled` + target `proxy-remote.<domain>` (public record is
  auto-published — `forms`→grow and `llama`→gpu-ai are the live apex-target
  precedents). `wildcard-cert` covers both hosts (top-level, non-clusterBase).
- `custom-values/{dev,infra}/prod-values.yaml` — real UUIDs present; dev's
  `forgejo.bitwardenIds.*` + `forgejo.forgejo.gitea.config.server.{DOMAIN,ROOT_URL}`
  are the shape to mirror. `OVERRIDE_NEEDED` = user-fill placeholder precedent.
- app-template **5.0.1** (repo standard; charts/qdrant + proxy-local umbrella).
  Verified against the common library source: `initContainers` render through
  the shared container spec → **`restartPolicy: Always` sidecar initContainers
  are expressible** (required for the DinD sidecar; dev k3s 1.36.5 ≥ 1.29);
  `controllers.<id>.type: statefulset` + `statefulset.volumeClaimTemplates`
  (per-entry `globalMounts`/`advancedMounts`, `storageClass`) are supported;
  headless service via `clusterIP: None`.
- ExternalSecret engineVersion v2 templates are repo-proven
  (`services/dev/prod/templates/secret-forgejo-token.yaml` uses
  `data: FORGEJO_TOKEN: "{{ .token }}"`) — the runner's config.yaml is composed
  the same way.

## Commands

Dependency builds first (vendored charts are not committed for these paths):

```
helm dependency build charts/forgejo            # OCI pull (anonymous, public)
helm dependency build services/infra/prod
helm dependency build services/proxy-local/prod
helm dependency update charts/forgejo-runner    # new chart — writes Chart.lock + vendored tgz
```

Chart-level:

```
helm lint charts/forgejo
helm template charts/forgejo --debug
helm lint charts/forgejo-runner
helm template charts/forgejo-runner --set bitwardenIds.forgejo-runner-token=00000000-0000-0000-0000-000000000000 --debug
```

Service umbrellas (sentinels resolved via --set for render checks; the test
scripts pin the exact --set lists):

```
helm template services/dev/prod --set domain=scifi.farm --set subDomain=dev --set clusterName=dev \
  --set bitwardenIds.cert-manager-solver-token=u --set bitwardenIds.argocd-sso-secret=u \
  --set bitwardenIds.github-pat=u --set bitwardenIds.forgejo-token=u \
  --set hivetools.bitwardenIds.mcp-sso=u --debug
helm template services/infra/prod --set domain=spencerslab.com --set clusterName=infra \
  --set bitwardenIds.keycloak=u --set bitwardenIds.keycloak-pg=u --set bitwardenIds.smtp=u \
  --set hivetools.bitwardenIds.mcp-pg-keycloak=u \
  --set forgejo.bitwardenIds.forgejo=u --set forgejo.bitwardenIds.forgejo-admin=u \
  --set forgejo.bitwardenIds.forgejo-pg=u --set forgejo.bitwardenIds.forgejo-sso=u --debug
helm template services/proxy-local/prod --set domain=spencerslab.com --set clusterName=proxy-local \
  --set bitwardenIds.argocd-sso-secret=u --set bitwardenIds.autossh-secret=u \
  --set bitwardenIds.traefik-mqtt=u --set authRealm=SpencersLab --debug
```

Sentinel sweep (every `OVERRIDE_VIA_CUSTOM_VALUES` in touched chart/service
values matched 1:1 by a key in the category's `custom-values/<cat>/prod-values.yaml`;
values are real UUIDs or the documented `OVERRIDE_NEEDED` placeholder; NO
`OVERRIDE_*` may appear in any rendered output):

```
grep -rn 'OVERRIDE_VIA_CUSTOM_VALUES' charts/forgejo charts/forgejo-runner services/infra/prod values.yaml services/proxy-local/prod/values.yaml services/dev/prod/values.yaml
grep -rn 'OVERRIDE_NEEDED' custom-values/
```

Service-trio greps (chart entry + ApplicationSet values entry + proxy entry
where applicable; the runner is client-only → its "trio" deliberately has NO
ingress entry):

```
grep -n 'forgejo' services/infra/prod/values.yaml            # charts.forgejo + ingress.subdomains.git + .forgejo
grep -n 'forgejo' services/proxy-local/prod/values.yaml      # proxy.subdomains.git + .forgejo
grep -n 'forgejo-runner' services/dev/prod/values.yaml       # charts.forgejo-runner only
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Relocate research audit trail into the feature folder | S | 1 | [] | — |
| C02 | Item A: infra Forgejo instance + proxy-local routing + leftovers cleanup | L | 1 | [] | independent subsystem (infra/proxy-local/custom-values/infra); shares no files with C03 |
| C03 | Item B: `charts/forgejo-runner` + dev service wiring | L | 1 | [] | independent subsystem (new chart + services/dev + custom-values/dev); registers against the existing dev forgejo, which C02 does not touch |

## Wave order

1. C01, C02, C03 — all wave 1, all independent; run in id order. C01 first so
   its commit is the feature's first dev commit (coordinator instruction).
   C02 ∥ C03 would be safe in parallel; the pipeline runs them sequentially.

## Fusion (2026-10-23)

Three parallel runs of this ticket were fused by `agent-fuser` (2026-10-23)
onto this branch — **base: run 2
(`feat-forgejo-infra-and-runner-gpu-ai-qwen3-8-27b-q6-2`), user-confirmed
2026-10-23 over the fuser's run-1 suggestion**. All 5 conflict rulings were
confirmed by the user with follow-up confirmation and are recorded verbatim
in the fusion plan under "Base and ports" (and in DECISIONS.md). This section
is the plan of record for the fusion deltas: **C01–C03 stay done and are not
re-executed**; F01/F02 carry ONLY the deltas from the other branches plus the
deltas the rulings require.

- Fusion plan (the single sanctioned second plan file):
  `2026-10-21-feat-forgejo-infra-and-runner-fusion.md` — ports 1–10,
  rejections with rulings, F01/F02 specs.
- Full comparison: `FUSION-REPORT.md` (planning quality, code/research/
  friction diffs, independent re-verification on 2026-10-23).
- Source branches (local worktrees — READ ONLY, never merge, never write):
  - run 1 `feat-forgejo-infra-and-dev-runner-3` —
    `/home/coder/.local/share/opencode/worktree/5e680f/feat-forgejo-infra-and-dev-runner-3`
  - run 3 `feat-forgejo-infra-and-runner-openrouter-qwen-qwen3-8-27b-1` —
    `/home/coder/.local/share/opencode/worktree/5e680f/feat-forgejo-infra-and-runner-openrouter-qwen-qwen3-8-27b-1`

### Chunks (fusion state)

| id  | title | size | wave | depends_on | status | why the dependency |
|-----|-------|------|------|------------|--------|--------------------|
| C01 | Relocate research audit trail into the feature folder | S | 1 | [] | **done** | — |
| C02 | Item A: infra Forgejo instance + proxy-local routing + leftovers cleanup | L | 1 | [] | **done** | independent subsystem (infra/proxy-local/custom-values/infra); shares no files with C03 |
| C03 | Item B: `charts/forgejo-runner` + dev service wiring | L | 1 | [] | **done** | independent subsystem (new chart + services/dev + custom-values/dev); registers against the existing dev forgejo, which C02 does not touch |
| F01 | forgejo-runner chart → two controllers (dev + infra), act labels, short timeouts, fsGroup, research-supplement docs | L | 1 | [] | pending | chart-owned surface; consumes no other fusion chunk |
| F02 | dev service wiring delta — infra-runner sentinel + URL pins | S | 2 | [F01] | pending | consumes F01's chart interface (sentinel key names, values keys) |

Wave order: C01–C03 done (wave 1, historical). **F01** runs alone in wave 1;
**F02** runs in wave 2 after F01 — F02's service slice sets
`runners.dev.url`/`runners.infra.url` and the second sentinel slot, both of
which are F01 chart surface (values keys +
`bitwardenIds.forgejo-runner-infra-token`), so F02 cannot render or validate
before F01 lands.

Test contract for the fusion: `tests/services/dev-forgejo-runner.sh` is
REWRITTEN red-first to the fused two-controller contract before F01 dev
(agent-test); F02 EXTENDS the same script — one script stays the runner
contract. `tests/services/infra-forgejo.sh`, `tests/services/audit-trail.sh`
and the pre-existing `tests/services/dev-git-auth.sh` stay untouched and
green as regression.

### User actions (consolidated: base plan + ruling 2 — complete list; supersedes the base "User actions" section below)

**Before sync (blocking):**

1. **Bitwarden items (org vault):** `infra-forgejo` (password =
   `openssl rand -hex 32` SECRET_KEY), `infra-forgejo-admin`,
   `infra-forgejo-pg` (password = DB password; username irrelevant — the
   ExternalSecret hardcodes `forgejo`), `infra-forgejo-sso` (username =
   client-id, password = client-secret). Paste UUIDs into
   `custom-values/infra/prod-values.yaml` (4× `OVERRIDE_NEEDED`).
2. **Lab Keycloak** (login.spencerslab.com, realm `SpencersLab`): new client
   `infra-forgejo`, redirects `https://git.spencerslab.com/*` +
   `https://forgejo.spencerslab.com/*`; creds → `infra-forgejo-sso`.
3. **DNS (mesh/split-horizon):** confirm `infra.spencerslab.com` → infra
   traefik LB (hub ExternalName depends on it). Public records for
   git/forgejo are auto-published by proxy-local's external-dns (point at
   proxy-remote; external access stays dead until future proxy-remote work —
   out of scope).
4. **Dev node filesystem:** `df -T /` on the dev node — root fs must NOT be
   overlay for DinD overlay2 over local-path PVs (btrfs/xfs/ext4 fine); if
   overlay, the dind containers need `storage-driver: vfs` (surface before
   sync).
5. **Runner registration — DEV instance:** git.scifi.farm → Admin → Actions
   → Runners → create instance-admin runner; uuid+token → Bitwarden item
   `forgejo-runner` (LOGIN: username=uuid, password=token; NEVER the
   `forgejo-token` item); UUID → `custom-values/dev/prod-values.yaml`
   (`forgejo-runner.bitwardenIds.forgejo-runner-token`).
6. **Confirm** the infra ArgoCD cluster secret carries
   `services.infra.customValuesUrls` (verified by inference only).

**After infra boots (ruling 2 adds this):**

7. **Runner registration — INFRA instance (NEW):** git.spencerslab.com →
   Admin → Actions → Runners → create instance-admin runner; uuid+token →
   Bitwarden item `dev-forgejo-runner-infra` (LOGIN: username=uuid,
   password=token); UUID → `custom-values/dev/prod-values.yaml`
   (`forgejo-runner.bitwardenIds.forgejo-runner-infra-token`).

**Post-sync verification:**

8. infra: `infra-forgejo-*` + `pg-forgejo-1` Running; ExternalSecrets
   SecretSynced; both hosts serve over LAN; OIDC login works; mailer event
   flows through smtp-relay.
9. dev: BOTH runner pods Running; runner-dev **online** in git.scifi.farm's
   admin UI and runner-infra **online** in git.spencerslab.com's admin UI; a
   trivial workflow (`runs-on: ubuntu-latest`, e.g. echo step) completes on
   each instance. First-run pulls are ~2 GB per act image — expect a slow
   first job. If a job dies during "checking out actions", suspect
   forgejo/runner#1779 (k3s MTU) first — mitigations: dind `--mtu 1450`
   dockerd flag or per-job `network: host` (see RESEARCH-dind-supplement.md).

### Validation (fusion-level, on top of the chunks')

```
export PATH="$HOME/.local/bin:$PATH"
helm dependency update charts/forgejo-runner && helm lint charts/forgejo-runner
helm template charts/forgejo-runner --set bitwardenIds.forgejo-runner-token=00000000-0000-0000-0000-000000000000 --set bitwardenIds.forgejo-runner-infra-token=00000000-0000-0000-0000-000000000001
helm dependency update services/dev/prod && helm lint services/dev/prod
helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml --set domain=scifi.farm --set clusterName=dev --set forgejo-runner.bitwardenIds.forgejo-runner-token=00000000-0000-0000-0000-000000000000 --set forgejo-runner.bitwardenIds.forgejo-runner-infra-token=00000000-0000-0000-0000-000000000001
bash tests/services/dev-forgejo-runner.sh   # rewritten contract
bash tests/services/infra-forgejo.sh        # regression, unchanged
bash tests/services/audit-trail.sh          # regression, unchanged
bash tests/services/dev-git-auth.sh         # regression, unchanged
grep -rn OVERRIDE_ charts/forgejo-runner services/dev/prod custom-values/dev/   # sentinels only in values files
npx --yes aislop@0.18.1 ci --changes --base main   # plus manual comment-slop pass (YAML is outside aislop's gateable set)
```

### Follow-ups (carried from all three runs; NOT this ticket; supersedes the base "Follow-ups" section)

- SeaweedFS `git` PV/PVC on infra stays idle (user chose local-path; A2).
- Forgejo 15.0.9 → 15.0.10 patch on dev (OCI dep, manual bump; `dep` ticket).
- Renovate coverage for the OCI forgejo chart dependency.
- `services/backups/prod/Chart.yaml` gitea chart dependency ("TODO: Replace
  gitea with forgejo").
- samba `samba-users: OVERRIDE_NEEDED` wart in the infra render
  (pre-existing; user deferred to a separate ticket).
- Watch the runner k8s-native backend (gRPC plugin; run 3's RESEARCH.md F4
  documents the bjw-s precedent) as the long-term DinD replacement — do not
  depend on it (alpha).
- Optional: postgres-MCP entry for the new infra `pg-forgejo` DB.
- Open friction items from the base FRICTION.md (aislop YAML/MD scope,
  plan-file sentinel-sweep typo) — coord offers follow-up planning per
  AGENTS.md convention after this fusion lands.

### User-owned next steps (outside the pipeline)

- Review the PR for this branch (branch stays local until the user
  pushes/PRs — the pipeline never pushes).
- Items 1–9 above (Bitwarden, Keycloak, DNS, registrations, verification).
- Merging to main is the user's decision alone.

## User actions

> **Superseded by "Fusion (2026-10-23)"** — the consolidated list 1–9 there is
> the canonical one (item 7, infra-instance runner registration, is new via
> conflict ruling 2; items 8–9 are the consolidated post-sync verifications).
> Kept as the historical record of the pre-fusion plan.

**Before the infra/dev apps sync (blocking):**

1. **Bitwarden items (org vault):** `infra-forgejo` (LOGIN, password =
   `openssl rand -hex 32` SECRET_KEY), `infra-forgejo-admin` (LOGIN, initial
   admin user+password), `infra-forgejo-pg` (LOGIN, password = DB password;
   username irrelevant — the ExternalSecret hardcodes `forgejo`),
   `infra-forgejo-sso` (LOGIN, username = client-id, password = client-secret).
   Paste UUIDs into `custom-values/infra/prod-values.yaml` replacing
   `OVERRIDE_NEEDED`.
2. **Lab Keycloak** (login.spencerslab.com, realm `SpencersLab`): new client
   `infra-forgejo` (standard flow) with redirect URIs
   `https://git.spencerslab.com/*` and `https://forgejo.spencerslab.com/*`;
   store client-id/secret in `infra-forgejo-sso`.
3. **DNS (mesh/split-horizon, user-owned):** confirm `infra.spencerslab.com`
   resolves to the infra cluster's traefik LB (apex-host convention — same
   record shape as the working `grow.spencerslab.com` / `gpu.spencerslab.com` /
   `gpu-ai.spencerslab.com`); the hub's ExternalName depends on it. Internet
   DNS for `git.spencerslab.com` / `forgejo.spencerslab.com` needs NO action —
   proxy-local's external-dns publishes/updates both records automatically.
4. **Dev node filesystem:** run `df -T /` (or `stat -f -c %T /`) on the dev
   node. Root fs must NOT be overlay for DinD overlay2 over local-path PVs
   (btrfs/xfs/ext4 fine). If it is overlay, the runner needs
   `storage-driver: vfs` or a different node — surface before sync.
5. **Runner registration (UI):** on `https://git.scifi.farm` → Admin → Actions
   → Runners: create instance-admin runner (e.g. name `dev-runner-1`, default
   `docker` label); the setup screen shows uuid+token one last time. Create
   Bitwarden item `forgejo-runner` (LOGIN: username = uuid, password = token);
   paste the UUID into `custom-values/dev/prod-values.yaml` replacing
   `OVERRIDE_NEEDED`.
6. **Confirm** the infra ArgoCD cluster secret carries
   `services.infra.customValuesUrls` pointing at
   `custom-values/infra/prod-values.yaml` (verified by inference only — see
   FRICTION.md).

**After sync (verification):**

7. infra: `infra-forgejo-*` + `pg-forgejo-1` Running; ExternalSecrets
   SecretSynced; `curl -sI https://git.spencerslab.com` and
   `https://forgejo.spencerslab.com` (LAN) serve the instance; OIDC login works;
   admin user from `infra-forgejo-admin`; a test issue triggers a mailer event
   through smtp-relay.
8. dev: runner StatefulSet pod Running (dind sidecar + runner), runner shows
   **online** in git.scifi.farm Admin → Actions → Runners; a trivial Actions
   workflow job completes.

## Follow-ups (not in this ticket)

> **Superseded by "Fusion (2026-10-23)"** — the consolidated follow-ups there
> (carried from all three runs) are canonical. Kept as the historical record
> of the pre-fusion plan.

- The seaweedfs `git` PV/PVC remains idle after this ticket (user chose
  local-path) — candidate for a future LFS/attachment store or other RWX need.
- Forgejo 15.0.9 → 15.0.10 patch bump on dev (OCI dep, manual bump; `dep` ticket).
- Renovate coverage for the OCI forgejo chart dependency (carried over from the
  dev plan's follow-ups).
- `services/backups/prod/Chart.yaml`: replace the gitea chart dependency
  ("TODO: Replace gitea with forgejo").
- Watch the experimental runner K8s-native backend (gRPC plugin, PR #1472
  unmerged, issue #1773) as the long-term DinD replacement — do not depend on it.
- Optional: postgres-MCP entry for the new infra `pg-forgejo` DB (hivetools
  `postgresMcp.databases`, infra custom-values).
