# argocd-hook

Stateless relay: GitHub push hook -> `X-Hub-Signature-256` HMAC verify ->
`allowed_refs` accept-list filter -> 202, then async fan-out of real ArgoCD
API syncs per target (root app first, then every still-Out-Of-Sync app whose
`repoURL == target.repo` and `spec.targetRevision` equals the fired ref tail;
`prune=false`, never force, 409-as-success, remote clusters first and the
`local: true` hub target last, per-target timeout and failure isolation).

Config contract (the chart mounts both paths; secrets are never env-carried):

- `--config /config/targets.json` — `{"allowed_refs": ["refs/heads/main"],
  "targets": [{"name", "url", "rootApp", "tokenKey", "repo", "local"?}]}`;
  absent or empty `allowed_refs` defaults to exactly `["refs/heads/main"]`
  (widening is one values PR, no code change; `refs/tags/*` never fire).
- `--secrets-dir /secrets` — flat files: `github-webhook` (shared HMAC key)
  plus one bearer-token file per `tokenKey` (per-cluster `mcp-bot` tokens).
- `--check` — offline self-test: config + secret-file validation and an HMAC
  round-trip, prints the target table, exits 0/1, never touches the network.
- `POST /` — webhook endpoint; `GET /health` — probe endpoint (200 = config
  loaded valid at start).
- Audit trail: exactly one `target=<name> result=ok|failed|skipped` line per
  target per push (missing/failed targets are visible in the log, not silent).
- Tunables via env: `SETTLE_SECONDS` (default 10, root-sync -> child re-list
  delay) and `TARGET_TIMEOUT_SECONDS` (default 60). Listen port 8080.

Missed deliveries are not replayed: a restart mid-fan-out drops that push's
tail; the fallback is the same manual sync this repo used before cf-139.
