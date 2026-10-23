# PLAN (FUSION): feat-forgejo-infra-and-runner — fuse the 3 parallel runs

> **Consumption note** — This is a fusion plan written by `agent-fuser`
> 2026-10-23, confirmed by the user (base-branch choice + all 5 conflict
> rulings, each with follow-up confirmation; rulings recorded verbatim under
> "Base and ports"). It is executed by THIS branch's pipeline session as a
> replan through `agent-plan`: the base run's chunks (C01–C03) stay **done**
> and are not re-executed; the fusion chunks below (F01, F02) carry ONLY the
> deltas from the other branches plus the deltas the rulings require.
> Companion artifact: `FUSION-REPORT.md` in this folder (the full comparison).
> Source branches for ports: `feat-forgejo-infra-and-dev-runner-3` (run 1,
> worktree `/home/coder/.local/share/opencode/worktree/5e680f/feat-forgejo-infra-and-dev-runner-3`)
> and `feat-forgejo-infra-and-runner-openrouter-qwen-qwen3-8-27b-1` (run 3,
> worktree `/home/coder/.local/share/opencode/worktree/5e680f/feat-forgejo-infra-and-runner-openrouter-qwen-qwen3-8-27b-1`).
> Both worktrees exist locally; read ports from them, never merge the branches.

## Task

The ticket: (A) deploy the existing `charts/forgejo` wrapper as a second
Forgejo instance on the infra cluster, locally served at
`git.spencerslab.com` (canonical) + `forgejo.spencerslab.com` (alias), with
proxy-local hub routing for both hosts (proxy-remote untouched); (B) add a
separate `charts/forgejo-runner` chart running Forgejo Actions runners on the
dev cluster. Three parallel runs implemented this ticket; this fusion keeps
run 2's implementation as the base and folds in the user-chosen deltas from
runs 1 and 3.

## Base and ports

**Base: `feat-forgejo-infra-and-runner-gpu-ai-qwen3-8-27b-q6-2` (run 2)** —
user-confirmed 2026-10-23 (over the fuser's run-1 suggestion). Everything run
2 shipped stays: parameterized `charts/forgejo` (A8) with dev render
byte-parity, infra mailer via `smtp-relay-mail` (A6), two-entry infra ingress,
crowdsec-only proxy-local `git` + `forgejo` entries, gitea-leftovers deletion,
STORM audit trail in the ticket folder, all 58 checks green (fuser re-ran
2026-10-23).

**Ports from run 1 (`feat-forgejo-infra-and-dev-runner-3`):**

1. Runner label set (conflict ruling 3, confirmed + follow-up): both runner
   connections advertise run 1's GitHub-parity act-image labels (exact set in
   Changes F01).
2. Runner timeouts (conflict ruling 4, confirmed + follow-up):
   `runner.timeout: 30m`, `runner.shutdown_timeout: 5m`,
   `terminationGracePeriodSeconds: 300` on both controllers.
3. `pod.securityContext.fsGroup: 1000` (+ `fsGroupChangePolicy:
   OnRootMismatch`) — non-conflicted correctness port, grounds: run 1
   RESEARCH.md open Q2 (uid-1000 image vs node-owned local-path volumes) and
   run 3 RESEARCH F6 (a permission mismatch is a documented runner-failure
   cause). The base chart sets no fsGroup.
4. Research supplement: copy run 1's `RESEARCH.md` into this folder as
   `RESEARCH-dind-supplement.md` (byte-identical, path references in it are
   historical run-1-folder paths — prepend a 2-line header noting provenance
   and that THIS folder's `RESEARCH.md` remains the ticket's primary
   research), and add a one-line pointer at the top of `RESEARCH.md`.
   Carries the k3s MTU clone-failure warning (forgejo/runner#1779), the
   ArgoCD-timeout rationale, and the reliability self-rating.
5. Values-comment port: the k3s MTU warning ("first suspect when workflows
   die during 'checking out actions': forgejo/runner#1779 — mitigation: dind
   `--mtu` dockerd flag or job `network: host`") into
   `charts/forgejo-runner/values.yaml` header (why-style, citable).

**Ports from run 3 (`feat-forgejo-infra-and-runner-openrouter-qwen-qwen3-8-27b-1`):**

6. Runner registration scope CONCEPT only (conflict ruling 2, confirmed +
   follow-up): a second runner controller registered with the new infra
   instance — implemented as NEW chart work on top of run 2's design (run 3's
   k8s-plugin code is NOT ported).

**Rejected (dropped, with rulings):**

- Run 3's entire runner implementation — `runner-k8s-plugin` gRPC sidecar,
  namespaced Roles/RoleBindings/ServiceAccounts, podspec ConfigMaps, job-image
  digest pins, `runners:` two-controller Deployment templates (conflict ruling
  1, confirmed + follow-up: DinD sidecar wins; alpha protocol + third-party
  registry dropped).
- Run 3's proxy-local `git` shape (bare retarget keeping the default
  crowdsec+userAuth chain) — fuser-verified functional defect: hub
  forward-auth 302s OIDC-less git-over-HTTPS clients. Base's crowdsec-only
  stays. (No user ruling needed — the base shape is strictly better and the
  user's own run-2 session approved it as A5.)
- Run 3's `git.dev.scifi.farm` hostname (factual error; dev instance is
  `git.scifi.farm`, verified in `custom-values/dev/prod-values.yaml:52`).
- Run 3's deferred-APP_NAME posture — moot, base's A8 parameterization already
  fixes the infra display name (`SpencersLab` in custom-values/infra).
- Run 1's runner chart implementation (Deployment + TLS-2376 dind sidecar
  container + nc-wait loop + static PVC templates) — superseded by ruling 1's
  keep-base decision; the wait loop is UNNEEDED on the base design (base dind
  is a sidecar initContainer with a socket startup probe — kubelet holds the
  runner container until the probe passes, so run 1's race does not exist
  here).
- Run 1's single-entry `serviceName: forgejo` infra ingress shape (conflict
  ruling 5, confirmed + follow-up: two explicit entries stay).
- Run 1's `tests/c0N_*.sh` naming (repo convention is `tests/services/`; base
  already conforms).
- Run 1's 15Gi/5Gi static PVC templates and `dev-forgejo-runner` item rename —
  base keeps VCTs (2Gi/10Gi) and the `forgejo-runner` dev item name (B4); the
  NEW infra item is named `dev-forgejo-runner-infra` (ruling-2 follow-up
  wording, user-confirmed).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| F01 | forgejo-runner chart → two controllers (dev + infra), act labels, short timeouts, fsGroup, research-supplement docs | L | 1 | [] | chart-owned surface; consumes no other fusion chunk |
| F02 | dev service wiring delta — infra-runner sentinel + URL pins | S | 2 | [F01] | consumes F01's chart interface (sentinel key names, values keys) |

### F01 — `charts/forgejo-runner` two-controller rework + doc ports

Files in scope: `charts/forgejo-runner/values.yaml`,
`charts/forgejo-runner/templates/secret-forgejo-runner.yaml` (split into
`secret-runner-dev.yaml` + `secret-runner-infra.yaml`),
`charts/forgejo-runner/templates/NOTES.txt`, and the ticket-folder doc ports
(`RESEARCH-dind-supplement.md`, `RESEARCH.md` pointer line, `FRICTION.md`
append by coord).

Contract changes (all values-driven, keeping run 2's established mechanics —
backtick-escaped ESO placeholders, quoted `uuid` for pre-substitution YAML
parseability per base FRICTION):

1. Two controllers `runner-dev` and `runner-infra` (both `type: statefulset`,
   `replicas: 1` — one (uuid, token) pair maps to exactly one pod; scaling
   means more runner records). Each keeps run 2's pod shape: dind sidecar
   initContainer (`docker:29.9.1-dind`, privileged, socket startup+liveness
   probes), hardened runner container (drop ALL, no privilege escalation,
   explicit dumb-init command), socket emptyDir, per-controller VCTs
   (`data` 2Gi, `docker-data` 10Gi, local-path).
2. NEW values keys `runners.dev.url` / `runners.infra.url` (chart defaults:
   `http://dev-forgejo-http.default.svc:3000` and
   `https://git.spencerslab.com`) consumed by the two ExternalSecrets'
   config.yaml templates (helm-level templating into the ESO manifest; the
   uuid/token placeholders stay ESO-level). Connection names in config stay
   `dev` / `infra`.
3. NEW sentinel `bitwardenIds.forgejo-runner-infra-token:
   OVERRIDE_VIA_CUSTOM_VALUES` next to the existing
   `forgejo-runner-token`; second ExternalSecret `runner-infra` (target
   Secret `forgejo-runner-infra`, store `bitwarden-login`, uuid←username,
   token←password, same boilerplate as the dev one). The dev ExternalSecret
   is renamed `runner-dev` (target Secret `forgejo-runner-dev`) — update the
   `persistence.runner-creds` mounts accordingly (advancedMounts per
   controller/container; `CREDENTIALS_DIRECTORY` paths distinct per pod —
   pods are separate so identical paths are fine, mounts just reference the
   right secret name).
4. Labels per connection (ruling 3): both connections get
   ```
   - ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04
   - ubuntu-24.04:docker://ghcr.io/catthehacker/ubuntu:act-24.04
   - ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04
   - docker:docker://ghcr.io/catthehacker/ubuntu:act-24.04
   - node22:docker://docker.io/library/node:22-bookworm
   ```
   (run 1 RESEARCH Q9; only LTS-based act tags exist; `node:lts`+`dev` labels
   dropped). Labels may be a chart-level default consumed by both
   connections; dev-service slice may override.
5. Timeouts (ruling 4): config.yaml for BOTH connections gains
   `runner.timeout: 30m` + `runner.shutdown_timeout: 5m`; BOTH pods
   `terminationGracePeriodSeconds: 300`. Update the grace comment (the old
   ">= shutdown_timeout (3h)" claim and 10800 value go; new comment states
   the ArgoCD-sync trade-off per run 1 RESEARCH Q8).
6. fsGroup (port 3): both pods gain `securityContext.fsGroup: 1000` +
   `fsGroupChangePolicy: OnRootMismatch` with the why-comment (uid-1000 image
   vs node-owned local-path VCTs).
7. Values header: add the k3s MTU warning (port 5) and update the
   single-replica/identity comments to the two-controller reality; keep the
   truthful identity-mechanism comments from base round 2 (uuid+token via
   ESO, no `.runner` file).
8. NOTES.txt: add the infra registration user action alongside the dev one
   (both: UI → Admin → Actions → Runners, instance scope; uuid+token →
   Bitwarden items `forgejo-runner` and `dev-forgejo-runner-infra`).
9. Renovate verification (port of run 1's corrected mechanism, non-regression
   task): run the bundled renovate CLI dry-run against the chart
   (run-1 FRICTION recipe: renovate 44.115.13 via npx cache on node 24,
   minimal /tmp repo) and confirm the built-in `helm-values` manager extracts
   the runner + dind pins. If the `# renovate:` comment annotations prove
   inert (run 1 proved this for its shapes), rewrite them to truthful
   why-comments per run 1's option-a (do NOT add a custom manager in this
   chunk).
10. Doc ports (ports 4/5 + coord bookkeeping): `RESEARCH-dind-supplement.md`
    (byte-identical copy of run 1's RESEARCH.md + 2-line provenance header),
    one-line pointer in `RESEARCH.md`, coord appends FRICTION.md with the
    run-1 friction items worth keeping (renovate-CLI recipe; dind-wait race
    marked "not applicable here — sidecar-initContainer startup probe";
    fsGroup/local-path note).

Acceptance criteria (agent-test writes the updated suite BEFORE dev):

1. `helm dependency update charts/forgejo-runner && helm lint
   charts/forgejo-runner` passes.
2. `helm template charts/forgejo-runner --set
   bitwardenIds.forgejo-runner-token=<u1> --set
   bitwardenIds.forgejo-runner-infra-token=<u2>` renders: exactly TWO
   StatefulSets (`runner-dev`, `runner-infra`), each with one privileged dind
   sidecar initContainer (socket probes) + one hardened runner container; two
   ExternalSecrets (dev + infra, correct remoteRef keys); BOTH configs carry
   the act label set, `timeout: 30m`, `shutdown_timeout: 5m`; both pods grace
   300 + fsGroup 1000; the two connection URLs are the chart defaults; ZERO
   `OVERRIDE_*`; no Ingress/ClusterRole; exactly the privileged-dind count =
   2 (one per pod).
3. URL override probe: `--set runners.infra.url=https://example.test` changes
   the rendered infra config (values-driven proof).
4. Renovate extraction: dry-run reports both image pins extracted (output
   attached to the chunk's review notes).
5. `tests/services/infra-forgejo.sh` + `tests/services/audit-trail.sh`
   unchanged and green (no infra-surface regression).

### F02 — dev service wiring delta

Files in scope: `services/dev/prod/values.yaml`,
`custom-values/dev/prod-values.yaml`.

1. `custom-values/dev/prod-values.yaml` — under the existing
   `forgejo-runner.bitwardenIds`, add
   `forgejo-runner-infra-token: OVERRIDE_NEEDED` (comment: item
   `dev-forgejo-runner-infra`, username=uuid, password=token; created AFTER
   the infra instance boots).
2. `services/dev/prod/values.yaml` — extend the `forgejo-runner:` slice to
   pin BOTH connection URLs explicitly (deployed-target decisions,
   live-verified co-location for dev; mesh URL for infra):
   `runners.dev.url: http://dev-forgejo-http:3000`, `runners.infra.url:
   https://git.spencerslab.com`; update the trio-deviation comment to cover
   both controllers (still headless, still no ingress entry).
3. Sentinel parity: 2 chart sentinels ⇔ 2 custom-values slots.

Acceptance criteria:

1. `helm lint services/dev/prod` passes (after dependency update).
2. `helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml
   --set domain=scifi.farm --set clusterName=dev --set
   forgejo-runner.bitwardenIds.forgejo-runner-token=<u> --set
   forgejo-runner.bitwardenIds.forgejo-runner-infra-token=<u>` renders the
   appset element with both URLs + resolved UUIDs; no `OVERRIDE_` outside
   appset-generator resources.
3. `tests/services/dev-forgejo-runner.sh` (rewritten by agent-test for the
   fused contract, red-first) passes; `tests/services/dev-git-auth.sh`
   regression green.
4. `ingress.subdomains` still has no runner entry (deviation comment
   present).

## Validation (fusion-level, on top of the chunks')

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

## User actions (consolidated: base plan + ruling 2 — complete list)

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

7. **Runner registration — INFRA instance:** git.spencerslab.com → Admin →
   Actions → Runners → create instance-admin runner; uuid+token → Bitwarden
   item `dev-forgejo-runner-infra` (LOGIN: username=uuid, password=token);
   UUID → `custom-values/dev/prod-values.yaml`
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

## Follow-ups (carried from all three runs; NOT this ticket)

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

## User-owned next steps (outside the pipeline)

- Review the PR for this branch (branch stays local until the user
  pushes/PRs — the pipeline never pushes).
- Items 1–9 above (Bitwarden, Keycloak, DNS, registrations, verification).
- Merging to main is the user's decision alone.