# C02-fix: chart — ExternalSecret secretKey rename ripple + docs parity
size: S   wave: 5   depends_on: [C01-fix]   fixes: C02 (done @ 0cf6e5338/19cc8f504)

## Goal

Follow the `hook-secret` rename into the chart so the rendered K8s secret data key (the
flat filename the relay reads from `--secrets-dir`) matches the C01-fix constant
byte-for-byte, and refresh the chart docs/comments to the main-sync origin framing.
Bitwarden item content and the custom-values UUID block stay untouched.

## Tasks

- [ ] `charts/argocd-hook/templates/secret-argocd-hook.yaml`: `- secretKey:
      github-webhook` → `secretKey: hook-secret`; header comment: "Shared
      GitHub<->fleet HMAC" → shared forge-main-sync<->fleet HMAC (one key for the whole
      fleet, OQ2 unchanged) stored as the `argocd-hook` login-item password; note the
      flat-filename contract lives in the relay README.
- [ ] `charts/argocd-hook/README.md` (line ~23 surface list): `github-webhook` →
      `hook-secret`; caller framing = main-sync hook job (GitHub-shaped door note if the
      README describes who sends it).
- [ ] `charts/argocd-hook/values.yaml`: `trackedRepo` comment — pin the WHY it stays the
      GitHub URL under ruling (c): apps' live `spec.targetRevision`/`repoURL` still read
      GitHub 9/9 (probe [P §1]) and `app_matches` byte-matches THAT, never the payload's
      `repository` field; flipping it before the fleet's annotations flip would be the
      silent skipped×N no-op trap [P §3]. No value change.
- [ ] Confirm (grep) nothing else in `charts/argocd-hook/` references the old key.

## Files in scope

- `charts/argocd-hook/templates/secret-argocd-hook.yaml`
- `charts/argocd-hook/README.md`
- `charts/argocd-hook/values.yaml` (comment only)
- (test re-pin: `tests/services/argocd-hook-wiring.sh` t2 HMAC-secret leg key name —
  agent-test session, before dev)

## Acceptance criteria

1. `helm lint` + `helm template` (test --set values per plan Commands) green; rendered
   ExternalSecret carries `secretKey: hook-secret` and the `bitwarden-login` store +
   `password` property mapping is otherwise byte-identical.
2. K8s Secret target name, ES name, tokens ExternalSecret, custom-values 1:1, trio
   entries, `clusterHosts` map, `allowedRefs`, `trackedRepo` VALUE: all unchanged (review
   diffs — only the rename + comment lines move).
3. Rendered key == C01-fix filename: `grep -c hook-secret` ≥ 1 in the render;
   `github-webhook` 0 hits repo-wide under `charts/argocd-hook/` and
   `containers/argocd-hook/`.
4. Re-pinned `tests/services/argocd-hook-wiring.sh` green (t2 reads the new key);
   base-chart regression legs unaffected.

## Tests (agent-test re-pins, review runs)

`tests/services/argocd-hook-wiring.sh`:
- t2: HMAC ExternalSecret leg — expect `secretKey hook-secret` (and only that) in
  `es_info`; the old-name assertion removed (renamed, not deleted: the leg still proves
  exactly ONE ES maps the login-item password and nothing else does).
- t5 diff-scope: allowed-files list updated to this chunk's 3 files.
- all other t-series unchanged and still green (the parity pins for Service name,
  targets.json, trio, crowdsec entry must not drift).

## Notes for dev

- This is a rename ripple, nothing more: no new values keys, no wiring changes, no
  Bitwarden content change (owner already holds the password in the item — the RENAME
  moves the rendered key name only; no re-mint, no vault edit).
- The rendered key name IS the on-disk filename in the mounted secret dir (flat `keys
  land verbatim` comment at template top explains it — keep).
- comment-slop/aislop; commit is coord's.

## Review notes (review agent fills)
