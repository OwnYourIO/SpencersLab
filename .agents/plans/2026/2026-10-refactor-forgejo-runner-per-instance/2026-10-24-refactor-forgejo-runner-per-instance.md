# PLAN: forgejo-runner → one single-runner chart deployed twice (one Application per Forgejo instance)
feature: 2026/2026-10-refactor-forgejo-runner-per-instance

## Goal
Rework `charts/forgejo-runner` from one chart holding two app-template
controllers (`runner-dev` + `runner-infra`) into a single-instance chart that
the dev ApplicationSet deploys TWICE via the existing `chart:` alias mechanism
(`charts.forgejo-runner-dev` / `charts.forgejo-runner-infra`, both
`chart: forgejo-runner`) — one ArgoCD Application per target Forgejo instance.
The runner's full behavioral contract (image pins, dind sidecar shape, act
label set, timeouts, declarative registration via uuid+token from Bitwarden)
is preserved unchanged; only the deployment topology and the values shape
change.

## Out of scope
- Moving the runners off the dev cluster (original user decision — unchanged;
  both pods keep running on dev, one dialing the infra instance via mesh URL).
- Any change to the Forgejo instances themselves, the proxy legs, or the
  Bitwarden items (same items/UUIDs are reused).
- A PVC-preservation scheme (user accepted the cache loss — and the PVCs were
  already re-provisioned live today ~16:46 UTC, so the caches are already
  empty; see Risks).
- Debugging today's live incident (runners DOWN since ~16:46 UTC:
  SecretSyncedError on both ESOs + unexplained whole-app recreation) — user
  ruled the item failure transient (items exist); recorded as a follow-up.
- Renovate wiring changes (the built-in helm-values manager keeps tracking
  both pins in the single values.yaml — asserted by a test).

## Commands
- helm binary: `~/.local/bin/helm` (not on every session's PATH)
- test: `bash tests/services/dev-forgejo-runner.sh` (agent-test rewrites it red-first to the new contract)
- regression: `bash tests/services/audit-trail.sh && bash tests/services/infra-forgejo.sh && bash tests/services/dev-git-auth.sh && bash tests/services/forgejo-ssh-gateway.sh && bash tests/services/forgejo-ssh-audit-trail.sh`
- lint: `~/.local/bin/helm lint charts/forgejo-runner && ~/.local/bin/helm lint services/dev/prod`
- chart render (per release): `~/.local/bin/helm template dev-forgejo-runner-dev charts/forgejo-runner --set bitwardenIds.runner-token=00000000-0000-0000-0000-000000000000` (and the same for release `dev-forgejo-runner-infra`) — expect 0 `OVERRIDE_` and all resources named exactly after the release name
- umbrella render: `~/.local/bin/helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml --set domain=scifi.farm --set clusterName=dev` — expect 0 `OVERRIDE_VIA_CUSTOM_VALUES`
- sentinel sweep: `grep -rn 'OVERRIDE_' charts/forgejo-runner services/dev/prod custom-values/dev` — 1 chart sentinel ↔ 2 real UUIDs in custom-values
- trio grep: `grep -n 'forgejo-runner' services/dev/prod/values.yaml custom-values/dev/prod-values.yaml charts/forgejo-runner/values.yaml`
- aislop gate: `npx --yes aislop@0.18.1 ci --changes --base main --human`

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Single-instance chart + dev service/custom-values rewire (atomic) | L | 1 | [] | — |

## Wave order
1. C01 (the only chunk). Chart rework and service/custom-values rewire cannot
   ship separately: chart-alone breaks the live app's value keys
   (sentinel/url key renames), rewire-alone renders the old two-controller
   chart twice into one namespace (ExternalSecret/target-Secret name
   collisions). One atomic merge; the runners are already down live (see
   Risks), so there is no live stability to protect with a bridge.

## Risks / assumptions
- **PVC recreation (accepted, already realized):** new STS names → new VCT PVC
  names → the old `data`/`docker-data` volumes are dropped (act cache + docker
  image cache; one-time re-pull on first job). Live-verified 2026-10-24: the
  whole `dev-forgejo-runner` app was recreated ~16:46 UTC today and the
  current PVCs are already fresh — the loss already happened. Runner identity
  is unaffected (uuid+token live in Bitwarden). Post-sync: check the old PVCs
  (`data-dev-forgejo-runner-runner-{dev,infra}-0`,
  `docker-data-dev-forgejo-runner-runner-{dev,infra}-0`) were pruned with the
  old app; if any survive orphaned, delete manually.
- **Live incident (runners DOWN since ~16:46 UTC):** both ESOs
  `runner-dev`/`runner-infra` are in `SecretSyncedError` ("could not get
  secret data from provider") with correct UUIDs in spec; all other
  bitwarden-login ESOs sync fine; target Secrets were deleted in the app
  recreation, pods stuck on `FailedMount`. User confirmed both Bitwarden items
  exist → treated as transient. The refactor reuses the same items/UUIDs, so
  post-sync the new ESOs must reach Ready/Synced — if the error persists,
  nudge (delete the ESO pod-side trigger or re-sync) or investigate the
  bitwarden backend (separate debug ticket).
- **ArgoCD prune ordering during cutover:** old app pruned, two new apps
  created in the same sync; old ESO cleanup finalizers delete the old target
  Secrets; names are disjoint (old `runner-{dev,infra}` vs new
  `dev-forgejo-runner-{dev,infra}`), so no ownership fight. Brief overlap of
  old terminating pods + new starting pods is possible — both use the same
  uuid per instance, so the Forgejo side may show a momentary flap;
  self-resolves when the old pods exit (no jobs are running while the runners
  are down).
- **Appset values-flow landmine (guarded by test):** per-app values flow ONLY
  from the TOP-LEVEL `<appName>:` slice in services/dev/prod/values.yaml
  (`appset-charts.yaml` line ~33: `merge $extraValues (index $.Values
  $appName)`) — NOT from the `charts.<appName>` entry. The current URL pins
  under `charts.forgejo-runner.runners` are inert (predecessor F02 finding);
  the new design puts the URLs in the top-level slices, making the pins
  actually load-bearing. The base-chart ground-truth render test guards this.
- **No hand version bump:** `version: 1.0.1` stays; release.yaml bumps on
  merge. Chart.yaml `description` is updated in-chunk.
- Worktree starts on detached HEAD at main tip; the dev chunk creates+attaches
  branch `refactor-forgejo-runner-per-instance-apps` (established pattern).

## User actions
- Before/at merge: none blocking (Bitwarden items exist; UUIDs unchanged).
- Post-sync watch: new Applications `dev-forgejo-runner-dev` +
  `dev-forgejo-runner-infra` created, old `dev-forgejo-runner` pruned; both
  ESOs Ready/Synced (SecretSyncedError must not persist — see incident risk);
  both pods pass the dind socket probe, runner container starts; runners
  re-attach (same uuid — NOT new registrations) and show online in each
  Forgejo instance (Admin → Actions → Runners); first job re-pulls images.

## Follow-ups
- Debug ticket: root-cause today's ~16:46 UTC whole-app recreation +
  SecretSyncedError (user ruled the item failure transient; the recreation
  trigger — something in/after the forgejo-ssh merge (#719) — is unexplained).
- Predecessor deferred cleanup: provenance tags in shipped comments
  ("conflict ruling 2/3/4", "(decision B1)") may be dropped keeping the why.