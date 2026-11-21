# argocd-hook

Stateless relay: push hook -> HMAC verify over the raw body ->
`allowed_refs` accept-list filter -> 202, then async fan-out of real ArgoCD
API syncs per target (root app first, then every still-Out-Of-Sync app whose
`repoURL == target.repo` and `spec.targetRevision` equals the fired ref tail;
`prune=false`, never force, 409-as-success, remote clusters first and the
`local: true` hub target last, per-target timeout and failure isolation).

Canonical caller today: the Forgejo `main-sync` hook-relay job; the public
edge also accepts GitHub-shaped deliveries (door, no webhook created).
Signature dialects (R3): `X-Forgejo-Signature` carries plain lowercase hex,
`X-Hub-Signature-256` carries the `sha256=`-prefixed form. The first-present
header decides which dialect is required and only that header is verified —
no cross-dialect fallback: a malformed or forged first header is a 401 even
when the other header would check out. Deliveries gate on
`X-GitHub-Event: push`; the job sends that header family on purpose so the
event filter needs no second dialect.

Config contract (the chart mounts both paths; secrets are never env-carried):

- `--config /config/targets.json` — `{"allowed_refs": ["refs/heads/main"],
  "targets": [{"name", "url", "rootApp", "tokenKey", "repo", "local"?}]}`;
  absent or empty `allowed_refs` defaults to exactly `["refs/heads/main"]`
  (widening is one values PR, no code change; `refs/tags/*` never fire).
- `--secrets-dir /secrets` — flat files: `hook-secret` (the one shared HMAC
  key both dialects sign with) plus one bearer-token file per `tokenKey`
  (per-cluster `mcp-bot` tokens).
- `--check` — offline self-test: config + secret-file validation and HMAC
  round-trips in both dialects (hub and forgejo), prints the target table,
  exits 0/1, never touches the network.
- `POST /` — webhook endpoint; `GET /health` — probe endpoint (200 = config
  loaded valid at start).
- Audit trail: exactly one `target=<name> result=ok|failed|skipped` line per
  target per push (missing/failed targets are visible in the log, not silent).
- Tunables via env: `SETTLE_SECONDS` (default 10, root-sync -> child re-list
  delay) and `TARGET_TIMEOUT_SECONDS` (default 60). Listen port 8080.

Missed deliveries are not replayed: a restart mid-fan-out drops that push's
tail; the fallback is the same manual sync this repo used before cf-139. A
fan-out trigger failure (job death, relay down) lands that push nowhere —
no Actions redeliveries exist; the next push self-heals (fan-out is
SHA-agnostic) or a human syncs.
