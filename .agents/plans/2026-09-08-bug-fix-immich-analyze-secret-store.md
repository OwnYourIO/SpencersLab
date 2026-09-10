# Plan: Fix immich-analyze ExternalSecret store (bitwarden-fields → bitwarden-login)

## Goal
Fix the `home-immich-analyze` deployment failure (`CreateContainerConfigError`)
caused by the ExternalSecret being unable to fetch the Immich API key from
Bitwarden.

## Problem (observed 2026-09-08)
- ArgoCD Application `home-immich-analyze` Degraded.
- Pod `home-immich-analyze-*` in `CreateContainerConfigError`:
  `Error: secret "immich-analyze" not found`.
- ExternalSecret `immich-analyze` condition
  `Ready=False / SecretSyncedError: could not get secret data from provider`.
- The Bitwarden item `8ef66a15-3efb-4854-85b1-b4bf0030a214` stores the Immich
  API key in its **password** field (login item), not in a custom `api_key`
  field. Confirmed by the working `pictaria` ExternalSecret, which reads the
  same item via `bitwarden-login` + `property: password` and syncs
  successfully (`Ready=True / SecretSynced`).

## Changes

### `charts/immich-analyze/templates/secret-immich-analyze.yaml` — MODIFY
- `sourceRef.storeRef.name`: `bitwarden-fields` → `bitwarden-login`
- `remoteRef.property`: `api_key` → `password`
- `secretKey` remains `api_key`, so the Deployment's
  `IMMICH_API_KEY secretKeyRef (name: immich-analyze, key: api_key)` is
  unchanged.

## Verification
- `helm lint charts/immich-analyze` — passes.
- `helm template charts/immich-analyze --set bitwardenIds.immich-analyze=<uuid>` —
  ExternalSecret renders with `storeRef: bitwarden-login` and
  `property: password`; no sentinels.
- Post-sync (ArgoCD): ExternalSecret should report `Ready=True / SecretSynced`,
  Secret `immich-analyze` created, pod restarted by reloader and Running.

## Notes
- No values/custom-values changes needed; the UUID was already correct.
- The earlier assumption (plan 2026-09-08-feat-add-immich-analyze.md, design
  decision 8) that the key lives in a custom field `api_key` on the
  `bitwarden-fields` store was wrong for this item.
