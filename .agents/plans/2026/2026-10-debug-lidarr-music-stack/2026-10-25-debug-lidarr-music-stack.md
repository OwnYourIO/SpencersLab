# PLAN: Fix Lidarr on the media cluster + resolve the slskd stash conflict
feature: 2026/2026-10-debug-lidarr-music-stack

## Goal

Restore `media-lidarr` (media cluster, ns `default`) to a healthy GitOps state:
it has been `Available=False` since 2026-09-24 because a `subPath` file-mount of
the optional `betanin` Secret into the live `/config` PVC fails deterministically
at container creation (`StartError`, "not a directory"). Also finish the
worktree's unresolved stash-apply conflict in `charts/slskd/values.yaml` so the
branch is clean and ready to carry the fix.

## Diagnosis evidence (gathered 2026-10-25, read-only)

- WeKan AI-Dev board: **no lidarr card exists** (62 cards, titles + descriptions
  scanned). The failure report is the live state below.
- Deployment `media-lidarr`, image `lscr.io/linuxserver/lidarr:nightly-version-3.1.6.5078`
  (music-stack plan 2026-09-20, Phase 1, already merged to main). gen=6,
  `Available=False` since 2026-09-24T04:33Z, `Progressing=False:ProgressDeadlineExceeded`.
- Pod `media-lidarr-6df7456fb6-kg5hr` (created 2026-10-25T21:06Z): CrashLoopBackOff,
  14 restarts, every exit `StartError` code 128 — runc: `error mounting
  "…/volume-subpaths/betanin-secret/lidarr/3" to rootfs at
  "/config/secrets/betanin/api_key": … not a directory`.
- The mount (committed): `services/media/prod/values.yaml` `lidarr:` block —
  volume `betanin-secret` = `secret: {secretName: betanin, optional: true}`,
  `volumeMounts: subPath: BETANIN_API_KEY → /config/secrets/betanin/api_key`.
  While the `betanin` Secret did not exist (ES only reached Ready=True
  2026-10-25T19:48Z), `optional: true` let kubelet proceed with an empty volume;
  the file-subPath source was never materialized, and the placeholder path state
  left in the live `/config` PVC (and/or kubelet's subpath dir-vs-file flip once
  the key appeared) makes the bind mount fail deterministically. The same Secret's
  other subPath keys (`config.toml`, `beets-config.yaml`) mount fine for the
  running `media-betanin` pods — so the Secret is healthy; the fragile file-subPath
  into the app PVC is what breaks.
- ArgoCD: umbrella Application `media` = Synced/**Degraded** (the only degraded
  app on the cluster); `media-betanin`, `media-slskd`, `media-explo`, `media-spotdl`,
  `media-audiomuse-ai` all Synced/Healthy.
- Conflict: markers are `Updated upstream`/`Stashed changes` → a **stash-apply
  conflict** (`git stash pop`/`apply` of `stash@{0}` "On add-music-to-media:
  OpenChamber stash 2026-10-25T22:31Z"), NOT a merge — no `MERGE_HEAD` exists
  (only `AUTO_MERGE`, stash machinery). Branch tip == local main == origin/main
  (`4d4fcdacb`); the music stack already landed. The conflict is the single line
  initContainer `tag: "0.26.2"` (ours) vs `tag: "0.26.0"` (stash). Ours is correct:
  the stash's edits to the other 6 files are byte-identical to HEAD, and
  `a60d11a0a` (Renovate) bumped both slskd image refs to 0.26.2 in main after the
  stash was taken. Taking the stash side would revert a Renovate bump.

## Out of scope

- Lidarr UI/plugin steps (Tubifarry, Brainarr, custom-script enablement,
  root-folder, llama-swap connectivity test) — remain USER steps of the
  music-stack plan Phase 8.
- All other music-stack services (healthy), the bubylou lidarr subchart itself,
  chart version bumps (CI-owned), the `stash@{1}` (On main) entry, and any
  admin-tier cluster mutation (no tier grants pod exec; verification commands are
  handed to the user).
- If Lidarr starts but then fails probes/nightly boot (music-plan Phase 8a risk),
  that is a second failure layer → new ticket.

## Commands (validation — agent-test wraps these, review re-runs)

C01 (conflict):
- `grep -cE '^(<<<<<<<|=======|>>>>>>>)' charts/slskd/values.yaml` → `0`
- `test "$(git hash-object charts/slskd/values.yaml)" = "$(git rev-parse HEAD:charts/slskd/values.yaml)"` → exit 0
- `git status --porcelain -uno` → empty; `git ls-files -u` → empty
- regression trio still intact: `grep -c slskd services/media/prod/values.yaml`,
  `grep -c slskd services/proxy-local/prod/values.yaml`, `grep -c slskd custom-values/media/prod-values.yaml` → all ≥1

C02 (lidarr fix, run from worktree root; umbrella deps must be built):
- `helm dependency update services/media/prod`
- `helm lint services/media/prod` → pass
- `helm template media services/media/prod -f services/media/prod/values.yaml --set domain=spencerslab.com --set clusterName=media --set bitwardenIds.argocd-mcp=test-uuid --show-only charts/lidarr/templates/deployment.yaml`
  → contains `mountPath: /betanin-secrets` on the `betanin-secret` volumeMount and
  **no** `/config/secrets/betanin` string anywhere; image stays
  `lscr.io/linuxserver/lidarr:nightly-version-3.1.6.5078`; the
  `/config/scripts/betanin.sh` configMap mount is unchanged.
- `helm template media services/media/prod -f services/media/prod/values.yaml --set domain=spencerslab.com --set clusterName=media --set bitwardenIds.argocd-mcp=test-uuid --show-only templates/configmap-lidarr-betanin-script.yaml`
  → script reads `/betanin-secrets/BETANIN_API_KEY`.
- full render grep: no `OVERRIDE_` sentinel in output.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Resolve the slskd stash-apply conflict (take HEAD/0.26.2) | S | 1 | [] | |
| C02 | Lidarr fix: directory-mount the betanin Secret outside /config + script path | S | 2 | [C01] | git refuses any commit while the index holds unmerged paths; C02 ends in a commit on the same worktree |

## Wave order

1. C01 (git hygiene — restores a committable worktree)
2. C02 (the actual fix + validation + commit)

## Fix design (C02)

Two committed files change, both in the umbrella chart — no new services, no
secrets, no version bumps:

1. `services/media/prod/values.yaml` — `lidarr.volumeMounts`: replace the
   `betanin-secret` entry `mountPath: /config/secrets/betanin/api_key,
   subPath: BETANIN_API_KEY` with a whole-volume directory mount
   `mountPath: /betanin-secrets` (no subPath). Directory mounts of secret
   volumes succeed even when empty/optional and cannot collide with state in the
   `/config` PVC. Volume entry (`optional: true`) stays.
2. `services/media/prod/templates/configmap-lidarr-betanin-script.yaml` —
   `API_KEY="$(cat /betanin-secrets/BETANIN_API_KEY)"` (the whole-Secret mount
   exposes the key by its Secret key name; mode 0644 world-readable, the LSIO
   app user can read it).

After merge, ArgoCD syncs `media` → new ReplicaSet → the crashing pod is replaced
(no manual pod deletion needed).

## USER-owned steps (never agent-executed)

1. **Drop the stale stash** once C01 is done and verified: `git stash drop 'stash@{0}'`
   (destructive; `stash@{1}` is On main — leave it).
2. **Create/merge the PR** for `add-music-to-media` (repo rule: only the user
   lands work on main; branch currently equals main, the C02 commit is the PR diff).
3. **Post-merge verification** (agent may run the readonly-MCP checks once the
   user confirms the merge; the rest is user-side):
   - ArgoCD app `media` → Synced/Healthy; pod `media-lidarr-*` Running 1/1,
     restarts stable.
   - If (and only if) a new pod still StartErrors, inspect the PVC mount tree
     and clean the orphaned placeholder (commands for the user, no tier grants exec):
     ```bash
     kubectl -n default run lidarr-pvc-check --restart=Never --image=docker.io/library/alpine:3.21 \
       --overrides='{"apiVersion":"v1","spec":{"containers":[{"name":"c","image":"docker.io/library/alpine:3.21","command":["sleep","600"],"volumeMounts":[{"name":"v","mountPath":"/pvc"}]}],"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"lidarr"}}]}}'
     kubectl -n default exec lidarr-pvc-check -- sh -c 'ls -la /pvc /pvc/secrets /pvc/scripts 2>&1 || true'
     # If /pvc/secrets is a stray file, or /pvc/secrets/betanin/api_key is a directory
     # (leftover from the failed rollout), remove it:
     kubectl -n default exec lidarr-pvc-check -- sh -c 'rm -rf /pvc/secrets'
     kubectl -n default delete pod lidarr-pvc-check
     ```
4. **Betanin data check** (functional, not startup): confirm the Bitwarden
   `betanin` LOGIN item (`5b6a9f94-…`) has a non-empty password — it doubles as
   the betanin API key the script sends; empty would render an empty
   `BETANIN_API_KEY` and the betanin API would 401 at import time.

## Risks / assumptions

- The nightly image itself has never run on this cluster (Available=False since
  the migration). C02 removes the proven blocker; if a second layer appears
  (probes/`/ping` on LSIO, DB migration), it is out of scope → follow-up ticket.
- The `/config` PVC may hold an orphaned `/config/secrets` placeholder from the
  crashloop months; the fix sidesteps that path entirely, and step 3 cleans it.
- `helm dependency update services/media/prod` requires network (bjw-s + bubylou
  repos).
- No lidarr board ticket: acceptance = live-state recovery, as the kickoff's
  "examine the lidarr pod … fix it" request, not a card contract.
