# bug: coder external token encryption — removal, crash, and the keep-with-mute posture

Date: 2026-11-21 · Type: bug/config · Status: RESOLVED in bridge posture (keys kept, CLI nag muted); decrypt-before-remove caveat stands

## Timeline

- 2026-10-25 — Forgejo external-auth feature (2026-10-feat-forgejo-auth-support)
  wired `CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS` into both coder servers via the
  `coder-secrets` ExternalSecret target templates (dev:
  `charts/coder/templates/secret-coder.yaml`; gpu:
  `services/gpu/prod/templates/secrets-coder.yaml`), keys from per-cluster
  Bitwarden items (`coder-token-encryption`, UUIDs in `custom-values/`).
- 2026-11-19 — the "External Token Encryption ... not entitled ... Contact
  sales@coder.com" warning traced to those vars; coderd v2.38.2 SOFT-ENFORCES
  the paid feature (`enterprise/coderd/coderd.go`: keys really encrypt on a
  community license). Removal built (branch) and merged as 35a7df7ec.
- 2026-11-21 ~00:13 — the sync bricked gpu coderd: `database encrypted with
  unknown key` — the keys had already inserted an ACTIVE `dbcrypt_keys` row and
  encrypted rows (gpu: 1 external_auth_links, 1 user_links, 6 crypto_keys),
  and coderd refuses to start when those exist without the keys. Dev survived
  only via its in-memory keys — every future container start equally fatal.
  Recovery researched: `RESEARCH.md` in
  `.agents/plans/2026/2026-11-bug-coder-dbcrypt-recovery/` — official
  decrypt-then-remove flow plus the v2.38.2-specific gap (decrypt never clears
  `crypto_keys`, upstream #25381; the runbooks add the mandatory pre-wipe).
- 2026-11-21 (same day) — owner decision: RESTORE the keys (`a70f2ac12` reverted
  35a7df7ec on main — source files only; the suites never changed there and
  still pass) and keep them, muting the nag instead: this branch adds
  `CODER_NO_FEATURE_WARNING=true` to both coder env lists (the CLI-side
  suppression surface verified in RESEARCH §11; the UI banner is not affected —
  it stays visible to deployment-config readers only).

## Changes on this branch (relative to origin/main)

- `charts/coder/values.yaml` + `services/gpu/prod/values.yaml` — new
  `CODER_NO_FEATURE_WARNING: "true"` container env on both coderd pods, with
  the posture rationale. Inert on coderd itself (the server does not run the
  CLI warning transport); it silences every `coder` CLI invocation made from
  the pod (exec sessions, in-pod automation).
- This plan + `RESEARCH.md` (recovery runbooks, warning-suppression map).

Dropped from the branch's earlier history: the absence-pin test rework — void
once the owner restored the wiring; main's presence-asserting c-sso/g-sso
contract is again the correct description of the repo.

## Standing caveats (load-bearing)

1. Encryption is LIVE on both DBs and the rotator keeps writing encrypted rows.
   The ONLY safe way to ever remove the env again is the RESEARCH §5 sequence
   (pause Argo auto-sync → backup → scale coderd 0 → crypto_keys pre-wipe
   [#25381] → `coder server dbcrypt decrypt` → verify → scale up). A bare
   removal crashloops coderd (proven in production this week).
2. Keep both Bitwarden `coder-token-encryption` items — they are live key
   material AND the decrypt retry path.
3. `CODER_NO_FEATURE_WARNING` does not hide the UI banner (admins still see
   it) nor the 10-min coderd log line (`CODER_LOG_FILTER` gates DEBUG only).
   Fleet-wide CLI silencing option on the table: strip the
   `X-Coder-Entitlements-Warning` response header at the hub traefik (blunt —
   hides ALL entitlement warnings CLI-side).

## Commands (validation)

```bash
export PATH=$HOME/.local/bin:$PATH
bash tests/services/dev-git-auth.sh    # PASS (presence contract intact)
bash tests/services/gpu-coder-sso.sh   # PASS incl. real coder 2.38.2 chart render
# env landed: helm renders of both coderd Deployments carry CODER_NO_FEATURE_WARNING
npx aislop scan tests/services  # shell/yaml not scored — no findings
```
