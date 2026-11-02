# PLAN: Get Dev Forgejo Runner working
feature: 2026/2026-11-cf-97-bug-forgejo-runner
replan: 2026-11-02 r2 (C03 re-run cleared the uuid, exposed the docker-socket gate; C05 added) · `plan_status: needs-replan` — pending the user's C05 fix-shape choice

**Goal:** The dev runner (`dev-forgejo-runner-dev`) stops crash-looping and goes online against git.scifi.farm as the instance-admin runner (B3 scope). Two gates in sequence, both now evidence-characterised: **GATE 1 (uuid) is CLEARED** — C01's probe 2 confirmed V1 (`bw serve` snapshot lag, vault/mapping innocent), the corrected snapshot rendered at the 00:42:15Z refresh (Secret `config.yaml` 1232→1280 = the filled-uuid arithmetic), the pod bounced 00:46:35Z, and uuid+token validation passes. **GATE 2 (current)** — the daemon now dies at the next stage RESEARCH F2 predicted (`configCheck` requires a live Docker): `cannot ping the docker daemon … permission denied … unix:///var/run/docker.sock`. Root cause is a socket-group fact the chart never accounted for: `docker:29.9.2-dind` pre-adds group `docker` at **fixed gid 2375** (upstream `29/cli/Dockerfile`, `addgroup -g 2375 -S docker` — the base of the dind image), dockerd serves the socket `root:docker 0660`, and the uid-1000 runner holds no such group. The masked-gate lesson applies: this defect existed the chart's whole life; every start simply died at uuid validation first. C05 is the repo chunk; C04 (approved, pending) pins the `mergePolicy` intent.

**Architecture:** Five chunks. C01 **done** (V1 confirmed — user-run probes), C02 **done** (`e3b18c27f`). C04 (agent, wave 1, independent) pins `spec.target.template.mergePolicy: Merge` — intent + observability, no render-behaviour change. **C05 (agent, wave 1, independent)** gives the runner process the docker group (recommended shape: `pod.securityContext.supplementalGroups: [2375]` + explicit `containers.runner.securityContext.runAsUser: 1000`; **awaiting the user's fix-shape pick — Open question 1**). C03 (agent, wave 2, gates on [C01, C05]) is the closure read: `declared successfully` + STS Ready + user-eyeball online; cluster-side closure of C05 requires the user's PR/merge → ArgoCD apply → C03 re-run. Smoke test stays declined (Q6).

**Tech Stack:** Forgejo 15.0.10 (Actions on by default), runner v13.2.0 declarative daemon, ESO (operator chart v2.14.0, CRD `mergePolicy` default `Replace`) over SecretStore `bitwarden-login` = **official Bitwarden CLI in `bw serve`** (`tangowithfoxtrot/bw-cli:2025.1.2`, jsonPath `$.data.login.<property>`, `charts/external-secrets-bitwarden/templates/bitwarden-secret-store.yaml:10-14`) — NOT a Vaultwarden webhook (RESEARCH's attribution was wrong), app-template 5.0.1 chart `charts/forgejo-runner`, ArgoCD + stakater reloader.

**Spec:** card #97 (`xJSxCDv3sqqgyHwDq`); `RESEARCH.md` for the v13 daemon contract (still valid — F1/F2/F5/F6 stand; its store attribution and "record never created" inference are superseded, see DECISIONS); the coordinator's 2026-11-02 DECISIONS entries (audit verdict `ses_e666db943ffeyb72YaQIutK4rB`, C03 NEEDS_INFO `ses_e66ba4e07ffejesm4lkZNh6TtP`) carry the mapping evidence — cited here, not re-derived.

## Verified facts (cumulative; the re-plan blocks supersede what they contradict)

### Round 1 (2026-11-01) — still stands
- Suite baseline: fail-fast `bad()` aborted everything at the stale t2 dind leg (29.9.1 vs values/live 29.9.2, renovate `975b9d89d`) — repaired by agent-test; four misnomer sites (`values.yaml:35`, `secret-runner.yaml:3`, `custom-values/dev/prod-values.yaml:84-85`, `NOTES.txt:23`) — reworded by C02 (`e3b18c27f`), t11 is their contract leg.
- Misnomer/wording authority: runner token is the long-lived Token shown once at record creation; the `/registration-token` endpoints are deprecated (RESEARCH F1).

### Round 2 (2026-11-01 rework) — partially CORRECTED (see 2026-11-02 below)
- Mapping proof core stands: per-key `data` (`secret-runner.yaml:62-77`) with `property: username|password`, key names ↔ template refs, live ESO carries item ID `d3dafd1a…`. The bounce oracle (pod startTime vs write time) worked as designed.
- Claim "the template consumes exactly those keys" was **incomplete**, and the conclusion "all residual causes are vault-side" was **false** — see the audit facts below. Both superseded (DECISIONS 2026-11-02).

### Re-plan round (2026-11-02, from the coordinator log + audit, cited not re-derived)
- User-run keys-and-lengths read (no values exposed), ns **`default`** (not `dev`): Secret `dev-forgejo-runner-dev` carries `config.yaml=1232`, `token=56`, **no `uuid` key** (`jsonpath {.data.uuid}` → 0) while the user confirms the uuid IS in item `d3dafd1a…`'s login username field.
- Audit (1): `property: username` delivery is proven working — live counter-example ExternalSecret `forgejo-admin-secret` maps `username ← property: username` from item `47d1d689…` on the same store, consumer Deployment `dev-forgejo` runs 1/1; census 104× `property: password`, 62× `property: username`. The "username never lands" defect class is disproved.
- Audit (2): the missing-uuid-key observation is true but causally misread: **live `spec.target.template.mergePolicy: "Replace"`** (absent from the repo template — stamped at admission by the v2 CRD, enum Replace|Merge, default Replace) drops every fetched key the template does not re-emit. `template.data` re-emits `token` (and `config.yaml`) only ⇒ Secret keys `{config.yaml, token}` exactly.
- Audit (3): render inputs are NOT affected by Replace — the same ESO rendered the real 40-byte token — so **the uuid reached the render as an EMPTY string**: byte proof `uuid: ""` ⇒ 924 raw = 1232 b64 == the live length (a filled uuid would be 1280 b64). Corollary: `SecretSynced` green never excluded a delivered-empty value (it says "synced", not "non-empty").
- Store reality: `bitwarden-cli` Deployment image `tangowithfoxtrot/bw-cli:2025.1.2` = the official Bitwarden CLI in `bw serve`, answering from its **locally synced snapshot**; auto-resync freshness UNVERIFIED (upstream repo 404). ESO `refreshTime 2026-11-01T23:42:15Z` (~2h50m after the ~20:50Z write) produced no bounce and no content change — V1 (snapshot served stale) or V2 (write invisible to the CLI's account/vault view), unresolved.
- Probe 1 (user-run, 24 h of `deploy/bitwarden-cli` logs): only `Vault unlocked!` + session-key hint, **no sync/login/expiry errors** — weak evidence against V1.
- Probe 2 (pending, user-run): the item-shape read via `curl :18087/object/item/d3dafd1a… | jq {username_len,password_len,field_names,note_len}` requires port-forward mapping **`18087:8087`** (the user's `18087:18087` attempt → connection refused inside the pod netns; the CLI listens on 8087).

### Round 2, 2026-11-02 (C03 re-run at 02:47–02:52Z + planner upstream-image verification) — supersedes where it contradicts
- **The uuid defect is CLEARED** (C03 re-run handoff, STATE.json): pod bounced `startTime 2026-11-02T00:46:35Z` (anchor 15:40:13Z retired), STS revision `659f5b6b57 → 78c54694f4`, Secret `config.yaml` **1232 → 1280** b64 — exactly the filled-uuid arithmetic the audit predicted — reloader stamp `reloader.stakater.com/last-reloaded-from.observedAt 1793580135` = 2026-11-02T00:42:15Z (verified epoch conversion). C01 closed DONE: V1 confirmed (`bw serve` snapshot lag); pair provenance question closed (uuid+token validate ⇒ same record).
- **New blocker, stable across current AND previous logs:** `Error: cannot ping the docker daemon. is it running? permission denied while trying to connect to the docker API at unix:///var/run/docker.sock` — restarts 28→29 climbing. RESEARCH F2's `configCheck` gate, masked for the chart's whole life by the earlier uuid fail-fast.
- dind sidecar healthy (0 restarts, `Daemon has completed initialization`, `API listen on /var/run/docker.sock` + `[::]:2376` since 00:46:39Z); the socket reaches the runner via the `socket` emptyDir global-mounted at `/var/run` (`values.yaml:192-196`); runner has `DOCKER_HOST=unix:///var/run/docker.sock` (`:154`), `drop:[ALL]`, no supplemental groups (`:162-166`); pod `fsGroup: 1000` (`:177`).
- **Upstream socket-group fact (fetched 2026-11-02, raw.githubusercontent docker-library/docker master):** the dind image is `FROM docker:29-cli` and the cli Dockerfile **pre-adds group `docker` at fixed gid 2375** (`addgroup -g 2375 -S docker`, comment "pre-add a 'docker' group for socket usage") — NOT the old blog-era 999. dockerd's default `--group docker` then serves the socket `root:docker 0660`; uid-1000 runner holds no 2375 ⇒ EACCES. fsGroup (1000) cannot fix this: it chowns the volume at mount time, while the socket file is created *after* by dockerd with dockerd's own group.
- **Upstream entrypoint fact (same fetch, `29/dind/dockerd-entrypoint.sh`):** with the image-default `DOCKER_TLS_CERTDIR=/certs`, dockerd is started with `--host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2376 --tlsverify …` — the TCP leg binds **0.0.0.0**, and the plaintext fallback (empty certdir) is `--host=tcp://0.0.0.0:2375` unauthenticated. Pod IP is routable cluster-wide on k3s ⇒ the "plaintext localhost-only" framing of option (b) is FALSE as shipped (C05 Options-rejected + DECISIONS).
- Schema verification (vendored app-template 5.0.1 `values.schema.json`): `controllers.<c>.pod.securityContext` accepts `supplementalGroups` + `runAsUser`; `containers.<c>.securityContext` accepts `runAsUser`. The recommended fix renders; container-SC `supplementalGroups` does NOT exist (it is a pod-level field).
- **Dockerd-config surface: ABSENT, field name verified** (replan-2, 2026-11-02: repo grep + fresh `helm pull` of the exact Chart.lock dep — released app-template 5.0.1 has zero `dockerd`-named structures; no `dockerdConfigJson`/`config-docker.json` exists to use). The upstream daemon.json key to pin the socket group is **`group`** (moby `daemon/config/config.go` `SocketGroup` json-tagged `group`; default `docker` via `daemon/listeners/group_unix.go` `const defaultSocketGroup = "docker"`; socket `root:gid 0660` via go-connections `sockets/unix_socket_unix.go` `NewUnixSocket = WithChown(0, gid), WithChmod(0o660)`). Shape (a) needs none of it — dockerd's default lookup already resolves the image's `docker`→2375; a dockerd-side `--group` args override is the rejected M-sized variant. The brief's `fsGroup: 999` shape is falsified twice: wrong gid (2375 ships; 999 is folklore) and wrong mechanism (fsGroup chowns the volume at mount, not the socket dockerd creates afterwards). `docs.docker.com/reference/engine/dockerd/` returns 404 today — upstream code sources are the citations.
- Live socket mode (`ls -l` on the sock) is NOT agent-checkable (no pod-exec tier) — the 0660/root:docker read is upstream-Dockerfile + EACCES-consistent inference; C03's post-merge re-run is the mechanism proof, and a persistent EACCES after C05 falsifies it (then replan, per triage).

## Out of scope

- **Fleet-wide `mergePolicy: Replace` key-dropping sweep** (other templated ESOs may silently drop fetched keys since the v2 flip; one-line detector: templated ESO whose `template.data` omits a fetched `secretKey`) — **filed as board follow-up card `sLK4MmTxGiaCk3uLq` (Inbox)**; too big for this card by size, per the coordinator ruling.
- Custom-field contingency (`runner-uuid` field on item `d3dafd1a…` + uuid entry `sourceRef.storeRef: {kind: SecretStore, name: bitwarden-fields}` — store exists at `bitwarden-secret-store.yaml:29-31`): written as a **contingency, not a chunk**; promoted only by replan if probe 2 shows `username_len=0` with a healthy sync.
- Smoke test — DECLINED by the user (Q6); no workflow push anywhere.
- Runner pin 13.2.0→13.2.1, stale `charts/forgejo/Chart.yaml` appVersion — dep ticket (STATE `deferred[]`).
- Infra-runner relocation — stays out (Q5).
- 2026-10-24 recreation/SecretSyncedError debug — CLOSED as superseded (Q4).
- app.ini/topology/env changes (RESEARCH rec 6), the token leg, the uuid `data` entry's `property: username` spelling (sound — audit), `Chart.yaml version`, image pins, `bitwardenIds` — all explicitly untouched.
- Agent-side Bitwarden/cluster mutations; no `kubectl apply`; no push/merge (user-owned; commit-only coordinator).

## Commands (repo validation — AGENTS.md "Pipeline specifics")

```bash
export PATH=$HOME/.local/bin:$PATH          # MANDATORY: helm lives here
cd "$(git rev-parse --show-toplevel)"

bash tests/services/dev-forgejo-runner.sh   # THE runner contract suite, fail-fast; t11 is C02's
                                            # wording leg; agent-test adds t12 (mergePolicy pin)
helm lint charts/forgejo-runner             # standalone template needs the suite's
                                            # copy+dependency-update recipe (gitignored vendor)
helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml \
  --set domain=scifi.farm --set clusterName=dev | grep -c OVERRIDE_ || true   # exit 0, count 0
git diff --stat HEAD                          # C04: secret-runner.yaml (+ test file); C05: values.yaml (+ test file)
npx --yes aislop@0.18.1 ci --changes --base main
```

Service-trio: unchanged (client-only, proxy leg N/A-by-design). Cluster-side (C03): exact-name `resources_get`/`pods_get`/`pods_log` via `readonly-dev-kubernetes` (list/event shapes redact; re-confirmed). **Reloader-stamp oracle** (agent-readable; dates an RBAC-invisible Secret change — verified 2026-11-02: pod annotation `reloader.stakater.com/last-reloaded-from` carries `{SECRET dev-forgejo-runner-dev, observedAt 1793580135}` = 00:42:15Z, matching the bounce at 00:46:35Z): read `pods_get` annotations + `startTime` + STS `currentRevision/updateRevision` together before any "not synced / will never sync" call. Secret key dumps are **user-run** `kubectl -n default get secret dev-forgejo-runner-dev -o jsonpath …` (RBAC: agents cannot read Secrets) — presence/lengths only, never values.

## Chunks

| id  | title | size | wave | owner | depends_on | status |
|-----|-------|------|------|-------|------------|--------|
| C01 | Probe 2: settle V1 vs V2 on the bw-serve snapshot | S | 1 | **user** | [] | **done** — V1 confirmed 2026-11-02; uuid renders filled, pair validates |
| C02 | Comment/NOTES truthfulness (instance-admin wording) + test dind-pin repair | S | 1 | agent | [] | **done — `e3b18c27f`, APPROVED** |
| C03 | Live read-only verification of the online runner (no smoke test) | S | 2 | agent | [C01, C05] | blocked — re-gate: C05 landed + user merge → ArgoCD apply → socket gate clears |
| C04 | Pin `mergePolicy: Merge` on the runner ExternalSecret + why-comment | S | 1 | agent | [] | pending — approved ("Approve — mergePolicy: Merge"); test/dev rounds outstanding |
| C05 | Give the runner process the dind socket group (fix docker-socket EACCES) | S | 1 | agent | [] | pending — **fix shape awaits the user's pick** (Open question 1) |

C01 ∥ C04 ∥ C05 in wave 1; C03 runs when its gate closes (C01 done + C05's live effect via the user's merge). C04 changes no render behaviour (intent + observability); C05 changes pod securityContext only — the uuid gate is already cleared, so the post-merge C03 re-run tests the socket mechanism end-to-end. C04 vs C05 share no lines (template block vs controller/pod SC) — order-independent.

## Wave order

1. **C04 (agent)** — test round adds t12 (red-first), dev pins `mergePolicy: Merge`, suite green. **C05 (agent)** — after the user picks the fix shape: test round adds t13 (red-first), dev lands it, suite green. (C01 done, C02 done.)
2. **C03 (agent)** — gated on C05's live effect (user PR/merge → ArgoCD apply → reloader/revision bounce) plus C01's proven filled-uuid render; evidence sequence unchanged.

## Risks / assumptions

- **The socket-group read is upstream-verified but not agent-exec-verified** (no pod-exec tier): `root:docker(2375) 0660` is read from the pinned image's Dockerfile pre-add line + the observed EACCES. C03's post-merge re-run is the mechanism proof; a PERSISTENT EACCES after C05 lands falsifies the inference → replan, no improvised chart edits.
- **gid 2375 is a pin-coupled constant:** the dind image pre-adds `docker` at fixed gid 2375 today (verified upstream 2026-11-02; the blog-era 999 is WRONG for 29.x). A future renovate dind bump that moves the gid would silently re-break socket access while everything still renders — C05's why-comment names the authority and its suite leg pins the pairing so a bump forces a re-check at review.
- **Sequential-gate masking — this ticket's standing lesson:** each fail-fast stage of the daemon start (validate → configCheck → Declare) hid the next; the uuid gate masked the socket gate for the chart's whole life. After C05 clears configCheck, the Declare gate runs live for the first time (13.2.x ↔ 15.0.10 is the source-verified supported pairing, RESEARCH F2/F5) — budget honestly for one more C03 round if a new shape emerges.
- **ESO cadence ≤ `bw sync` freshness** (C01's V1 lesson): “no bounce after write” may mean the sidecar snapshot is stale, not the operator. The reloader-stamp oracle (`reloader.stakater.com/last-reloaded-from.observedAt` on the pod, agent-readable) dates an RBAC-invisible Secret change — use it before any “will never sync” call.
- C05's cluster effect rides the user's PR/merge (nothing in this repo applies). The rejected TCP shapes (C05 Notes) would need NetworkPolicy conversations; if the user nevertheless picks one, its posture question reopens.
- C04's deploy is post-merge user-owne­d; locally its proof is render-only. Under `Merge` the fetched `uuid` also appears as a Secret key (extra file at `CREDENTIALS_DIRECTORY` the daemon never reads — accepted; it is the accepted alternative to the rejected `uuid` re-emit).
- The live CRD-default stamping (`Replace`) is invisible to repo renders — anything asserting Secret *contents* indirectly (bounce oracle, byte lengths) is the compensating control; C03 keeps it.
- Pair provenance CLOSED by C01 (2026-11-02): uuid+token validate together → same record. `unregistered runner` is off the live-risk table; the branch stays in the C01/C03 playbooks only for a future record recreation.

## Open questions

Resolved by live evidence 2026-11-02: rounds 1–2 answers stand (scope instance-admin per B3; no smoke test; Q4 closed; Q5 out); landing + V1/V2 settled by C01 (the uuid was always in item `d3dafd1a…`'s login username; `bw serve` snapshot lag was the blocker; pair provenance closed).

Genuinely open — exactly one, and it blocks C05 dev only (C04 and the rest of the plan proceed regardless):

1. **C05 fix shape — a security-posture pick** (coordinator batches; recommendation = (a)):
   - **(a) RECOMMENDED — docker-group supplemental:** `controllers.runner.pod.securityContext.supplementalGroups: [2375]` + explicit `containers.runner.securityContext.runAsUser: 1000` (both schema-verified on app-template 5.0.1). Cost: the runner process joins gid 2375 = full control of the POD-LOCAL dind daemon — already the designed capability (`DOCKER_HOST` is wired precisely so the runner drives this daemon to spawn jobs); adds no listener, no world-writable object, no new mount; stays inside the pod's existing trust boundary.
   - (b1) plaintext TCP (`DOCKER_TLS_CERTDIR: ""` + `DOCKER_HOST=tcp://localhost:2375`) — REJECTED on fact: the entrypoint binds `tcp://0.0.0.0:2375`; pod IP is cluster-routable on k3s, so this is an unauthenticated cluster-reachable daemon port, NOT “localhost-only”.
   - (b2) TLS TCP 2376 (share sidecar-generated `/certs/client`, upstream 0644-key by design, via a new emptyDir + runner TLS env) — REJECTED: act_runner v13 TLS-env support UNVERIFIED (RESEARCH F2 env sweep confirmed only DOCKER_HOST), new mount pair, and cert-ready-vs-daemon-ready ordering the socket probe does not cover.
   - (a') initContainer chgrp/chmod the socket — REJECTED: races dockerd's socket lifecycle (recreated on daemon restart); consumer-side group membership is the race-free equivalent.
   - (d) `dockerd --group ""` (socket 0666) or the dind-rootless image variant — REJECTED: world-writable is broader than the need; rootless changes job-execution architecture and image family for a gid problem.
   Best guess if execution starts unanswered: **(a)**. Impact: C05 tasks + t13 leg shape; (a)/(a')/(d) are pod-SC/args-only, (b*) add env + mounts.
