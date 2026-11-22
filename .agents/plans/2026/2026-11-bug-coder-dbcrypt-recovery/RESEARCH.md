# RESEARCH — Coder dbcrypt recovery after external-token-encryption key removal

- **Ticket:** 2026/2026-11-bug-coder-dbcrypt-recovery
- **Date:** 2026-11-21 · **Method:** every code claim read directly from the deployed tag
  [`coder/coder` v2.38.2](https://github.com/coder/coder/tree/v2.38.2) (raw + tag-pinned blob permalinks below),
  official docs (v2.38.2 tag copy + live v2.39), the live `ghcr.io/coder/coder:v2.38.2` image config via the
  registry API, the upstream issue tracker, and this repo's own chart/ApplicationSet files. Incident facts 1–9
  from the launch brief are taken as given and build on. Claims that could not be verified are marked
  **UNVERIFIED**.

## TL;DR

1. The official recovery is `coder server dbcrypt decrypt` with the old keys, then keys stay removed, then start
   coderd ([docs "Turn off encryption"](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L142-L167)).
   The command is standalone (no coderd, no NATS, no migrations) and runs fine while coderd is down/crash-looping.
2. **But at v2.38.2 decrypt is broken for our exact DB shape**: it never clears `crypto_keys` (and the two
   `mcp_server_*` tables), so its final "revoke key" step dies on a Postgres FK violation — known upstream bug
   [coder/coder#25381](https://github.com/coder/coder/issues/25381), still open; fix PR
   [#28341](https://github.com/coder/coder/pull/28341) closed **unmerged**; main has the same gap. The gpu DB has
   6 encrypted `crypto_keys` rows (live re-inventory 2026-11-21 via readonly-gpu-postgres-coder; the count grew
   from 2 on 2026-11-19 because the rotator kept writing against coderd's in-memory key until it died), so the
   runbook adds one pre-step (wipe those rows — they auto-regenerate).
3. The wipe costs almost nothing: every `crypto_keys` feature is a short-lived signing/CA key the rotator
   re-creates on coderd start (workspace-app tokens live 60 s, tailnet-resume 24 h). The 1 `external_auth_links`
   + 1 `user_links` rows **survive** decrypt as plaintext — no re-login, no re-approval (deleting them instead
   would force users to redo Forgejo consent / OIDC link).
4. Run decrypt on **gpu immediately (~5–10 min to restore service)** and on **dev within hours** in a small
   planned window; dev's "still running" state is luck — its key is in-memory only and any container restart
   re-reads the keyless Secret and dies identically (env-var-from-Secret semantics are start-time-fixed).
5. Keep both Bitwarden key items until both DBs verify decrypted+revoked; only then delete them.

## 1. Decision table — recovery options

| # | Option | Outcome | gpu downtime | dev downtime | Risk | Verdict |
|---|--------|---------|--------------|--------------|------|---------|
| 1 | **Run decrypt on gpu now; decrypt dev in a short window today** (official flow + the #25381 `crypto_keys` pre-wipe) | Terminal fix; warning gone; keys become deletable | ends after run (~5–10 min total; it is already down) | ~5–10 min planned | Low. Wrong-key failures are safe-aborts (see A6). Residual: unverified dev DB state → inventory step covers | **RECOMMENDED** |
| 2 | **Revert the config commit first** (keys back in `coder-secrets` → Reloader restarts gpu coderd *with* keys → both servers healthy, warning returns), decrypt later in a maintenance window | Fastest *guaranteed* gpu restore if Bitwarden/decrypt can't be done right now | ~2–5 min (git revert + Argo sync + Reloader restart) | none | Restores the soft-enforced warning on both; the DB **keeps encrypting new rows** (the crypto-key rotator writes every ≤10 min while keys are loaded — [rotate.go](https://github.com/coder/coder/blob/v2.38.2/coderd/cryptokeys/rotate.go#L94-L124)), so the later decrypt gets no smaller | Acceptable bridge if #1 can't run today; schedule the decrypt |
| 3 | Do nothing on dev (hope the pod lives) | — | stays down | crash at any uncontrolled restart | Rejected — see §C: env vars from a Secret are resolved at container start, the Secret is already keyless on both clusters | **Reject** |
| 4 | `coder server dbcrypt delete` ([docs "Delete encrypted data"](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L186-L203)) | DB starts, all tokens gone | ~10 min | ~10 min | Destroys the Forgejo approval + OIDC link rows (users re-approve / re-login). Same FK trap — its revoke loop is identical ([cliutil.go L501-L527](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go#L501-L527)), so it *also* needs the `crypto_keys` pre-wipe. Strictly worse than option 1 | Reject (key exists; decrypt preserves rows) |
| 5 | Hand-rolled SQL: decrypt `crypto_keys`/token columns offline with an AES-256-GCM script, clear `*_key_id`, revoke by hand | — | — | — | Re-implements the tool's internals; one mistake is silent corruption (see §F) | Reject |
| 6 | Buy a premium license to keep encryption | warning silenced | — | — | Moot for this incident (config already removed, gpu down); noted in the risk register | N/A now |
| 7 | Upgrade coder first, decrypt on the fixed version | — | — | — | No fixed version exists: main's `cliutil.go` still has zero `crypto_keys` handling (verified 2026-11-21 fetch) and the fix PR was closed unmerged | Reject |

## 2. A — The recovery path, verified against v2.38.2 source

### A1. Does decrypt work while coderd is NOT running? Does it check `replicas` / refuse when instances are live?

- The `decrypt` subcommand's handler does exactly four things: decode `--keys` → build ciphers → prompt (skippable)
  → `cli.ConnectToPostgres(..., nil)` → `dbcrypt.Decrypt(...)`
  ([server_dbcrypt.go L135-L177](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server_dbcrypt.go#L135-L177)).
  There is **no `replicas`-table check, no coderd-liveness check anywhere in that path** (also absent from
  [`Decrypt`](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go#L247-L462)). The only
  concurrency-awareness is a serialization-failure retry in `ensureEncryptedWithRetry`
  ([dbcrypt.go L1158-L1173](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/dbcrypt.go#L1158-L1173)),
  which handles row-lock races, not running servers.
- The "stop all active coderd instances" step in the docs is **preventive**: a live coderd keeps *writing* newly
  encrypted rows mid-run, and then the final revoke hits rows the walk already passed
  ([docs Turn-off + Troubleshooting bullets](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L142-L211)).
- A **crash-looping coderd cannot write encrypted data**: enterprise `coderd.New` fails inside its constructor —
  before tailnet, provisioner jobs, API serving, and the cron loops — at the unconditional `dbcrypt.New` call
  ([enterprise/coderd/coderd.go L130-L142](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L130-L142)).
  So gpu's crash-loop *satisfies the docs' requirement in substance*. The runbook still scales the Deployment to 0
  first (stops restart churn; formally matches the docs).

### A2. Exact flags / env names at v2.38.2 (ground truth: source; cross-checked against the live v2.39 CLI ref)

[`enterprise/cli/server_dbcrypt.go`](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server_dbcrypt.go) (decrypt flags at L320-L344):

| Purpose | Flag | Environment variable | Validation |
|---|---|---|---|
| Database | `--postgres-url` | **`CODER_PG_CONNECTION_URL`** (L322-L323) | non-empty (`valid()`) |
| Keys to decrypt with | `--keys` (string array, comma-separated) | **`CODER_EXTERNAL_TOKEN_ENCRYPTION_DECRYPT_KEYS`** (L336-L337) | each must base64-decode to exactly 32 bytes |
| Auth type | `--postgres-connection-auth` | `CODER_PG_CONNECTION_AUTH` (default `password`) | enum |
| Skip prompt | `-y` / `--yes` | — | [`cliui.SkipPromptOption`, shorthand `"y"`, flag `"yes"`](https://github.com/coder/coder/blob/v2.38.2/cli/cliui/prompt.go#L32-L44) |

- Command path is `coder server dbcrypt decrypt` — `dbcrypt` is registered as a subcommand of the server command
  ([enterprise/cli/server.go L134-L136](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server.go#L134-L136)),
  with subcommands `decrypt`, `delete`, `rotate`
  ([server_dbcrypt.go L31-L36](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server_dbcrypt.go#L31-L36)).
- The docs explicitly flag the env-name trap: decrypt uses
  `CODER_EXTERNAL_TOKEN_ENCRYPTION_DECRYPT_KEYS`, *not* the server's `CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS`
  ([v2.38.2 docs L156-L160](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L156-L160);
  [live page](https://coder.com/docs/admin/security/database-encryption)).
- The CLI ref page matches: [`coder server dbcrypt decrypt`](https://coder.com/docs/reference/cli/server/dbcrypt/decrypt/).
- Quirk worth knowing for log-matching: the decrypt handler wraps its failure message with the word *rotate* —
  `xerrors.Errorf("rotate ciphers: %w", err)`
  ([server_dbcrypt.go L173-L176](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server_dbcrypt.go#L173-L176))
  — exactly as shown in issue #25381's repro output.
- (Not used here, for completeness: the `delete` subcommand's DB flag reads env
  `CODER_EXTERNAL_TOKEN_ENCRYPTION_POSTGRES_URL` — **different** from decrypt's
  ([server_dbcrypt.go L373-L377](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server_dbcrypt.go#L373-L377));
  `rotate` uses `CODER_EXTERNAL_TOKEN_ENCRYPTION_ENCRYPT_NEW_KEY` / `..._ENCRYPT_OLD_KEYS` (L263-L277).)

### A3. What decrypt does — tables rewritten, key revocation, and why a later zero-key coderd start is safe

`Decrypt` ([cliutil.go L247-L462](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go#L247-L462)):

1. Wraps the store with the provided ciphers, then sets `primaryCipherDigest = ""` ("HACK … so that it will not
   encrypt anything", L254-L260) — every write during decrypt therefore lands as **plaintext with the `*_key_id`
   cleared to NULL** (the wrapper's `encryptField` is a no-op without a primary digest,
   [dbcrypt.go L1101-L1124](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/dbcrypt.go#L1101-L1124)).
2. Per-user loop (`GetUserLinksByUserID`, `GetExternalAuthLinksByUserID`, `ListUserSecretsWithValues`,
   `GetGitSSHKey`, `GetChatMCPServersByChatOwnerID`) rewrites, decrypting and clearing:
   `user_links.oauth_access_token_key_id/oauth_refresh_token_key_id`, `external_auth_links.oauth_*_key_id`,
   `user_secrets.value_key_id`, `gitsshkeys.private_key_key_id`, `chat_mcp_servers.headers_key_id`.
3. Non-user tables: `ai_providers.settings_key_id`, `ai_provider_keys.api_key_key_id`,
   `user_ai_provider_keys.api_key_key_id`.
4. **"Revoke _all_ keys"**: for each `--keys` cipher, `RevokeDBCryptKey(digest)`
   ([cliutil.go L453-L459](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go#L453-L459)).
   The revoke query moves the digest: `revoked_key_digest = active_key_digest; active_key_digest = NULL`
   ([queries/dbcrypt.sql](https://github.com/coder/coder/blob/v2.38.2/coderd/database/queries/dbcrypt.sql)).

**Zero-key coderd start after that is tolerated — proved from the fatal path itself:**
`ensureEncrypted` reads every `dbcrypt_keys` row; the wrapper's `GetDBCryptKeys` decrypts the `test` field of
each row **only when `active_key_digest` is non-NULL** and `continue`s past revoked rows
([dbcrypt.go L75-L95](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/dbcrypt.go#L75-L95));
with zero ciphers any *active* row ⇒ `DecryptFailedError("no cipher with digest …")` (L1126-L1156) ⇒ the fatal
wrap at [coderd.go L136-L141](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L130-L142)
(gpu's exact crash line). With all rows revoked, the loop finds no active digest and
`if activeCipherFound || len(db.ciphers) == 0 { return nil }`
([L1175-L1215](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/dbcrypt.go#L1175-L1215)) returns
clean — and **no new `dbcrypt_keys` row is inserted when no ciphers are configured** (same early return).
The left-behind revoked rows are inert. ✔

### A3b. THE CRITICAL v2.38.2 GAP — decrypt fails on `crypto_keys` (upstream #25381, open)

- Every `*_key_id` column is a plain, non-deferrable FK to `dbcrypt_keys(active_key_digest)` — `crypto_keys`
  included ([migration 000251 L11](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000251_crypto_keys.up.sql),
  [000154](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000154_dbcrypt_key_ids.up.sql),
  [000447](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000447_mcp_server_configs.up.sql),
  000460/000495/000503/000515/000598/000601 — all verified; nothing in any later v2.38.2 migration makes them
  deferrable or SET NULL — content-grepped all of `coderd/database/migrations/`).
- `cliutil.go` has **zero** `crypto_keys` / `mcp_server_configs` / `mcp_server_user_tokens` references (grep
  verified on v2.38.2 *and* main). The design intent is explicit in
  [doc.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/doc.go): *"a key cannot be revoked
  until all values encrypted with that key have been migrated"*.
- Consequence, reproduced exactly by the upstream reporter in
  [issue #25381](https://github.com/coder/coder/issues/25381) (open, `bug`, 2026-05-15): the handled tables get
  decrypted, then the revoke step dies with
  `pq: update or delete on table "dbcrypt_keys" violates foreign key constraint "crypto_keys_secret_key_id_fkey"`.
  Our gpu DB has 6 encrypted `crypto_keys` rows (live re-inventory 2026-11-21; all six carry
  `secret_key_id='e720c10'`: `workspace_apps_token`/`workspace_apps_api_key`/`oidc_convert`/`tailnet_resume`
  seq 16 + `nats_ca`/`chat_files_token` seq 1), so **plain decrypt WILL fail here**, leaving
  the tokens decrypted but the key active → coderd still won't start.
- The fix PR [#28341](https://github.com/coder/coder/pull/28341) was **closed unmerged** — upgrading first does
  not help.
- The issue's own sanctioned workaround (matches the product's `DeleteCryptoKey` query, which is exactly
  `UPDATE crypto_keys SET secret = NULL, secret_key_id = NULL` —
  [queries/crypto_keys.sql L27-L30](https://github.com/coder/coder/blob/v2.38.2/coderd/database/queries/crypto_keys.sql#L27-L30)):
  clear the unhandled rows first, then (re-)run decrypt. `Decrypt` is idempotent on the handled tables (rows with
  NULL key-id are skipped, L270-L274 et seq.), so a mid-failed first pass is recoverable by simply re-running.
- Crypto keys regenerate automatically — see B3.

### A4. Standalone requirements — none beyond Postgres

- `cli.ConnectToPostgres` opens + pings + asserts PostgreSQL ≥ 13, with a 30 s retry loop — **no migrations are
  run** (the dbcrypt handlers pass `nil` for the migrate hook), **no NATS, no coderd, no license check, no other
  `CODER_*` env required** ([cli/server.go L2696+](https://github.com/coder/coder/blob/v2.38.2/cli/server.go#L2696)).
- The `server` parent command defines no `PersistentPreRun*` that a subcommand inherits (verified by grep of
  `cli/server.go` and `enterprise/cli/`), and the dbcrypt handler never reads server options beyond its two
  flags — so extra keys in `coder-secrets` (OIDC config, access URL…) are simply ignored by the Job even when
  injected via `envFrom`.
- Same-image-tag guarantee: we run the Job from `ghcr.io/coder/coder:v2.38.2`, the exact coderd tag, so the
  tool's generated SQL matches the deployed schema.

### A5. Image layout / entrypoint gotcha (verified on the *pushed artifact*, not just the Dockerfile)

- Build definition at v2.38.2: `scripts/Dockerfile` — binary `COPY coder /opt/coder`,
  **`ENTRYPOINT [ "/opt/coder", "server" ]`**
  ([v2.38.2 scripts/Dockerfile](https://github.com/coder/coder/blob/v2.38.2/scripts/Dockerfile)).
- Live confirmation from the registry config blob of `ghcr.io/coder/coder:v2.38.2` (linux/amd64, digest
  `sha256:dd8cc2b1bd6c475ed48e8122ad1a72f4b301e2dd80a9db676e3effd689f18318`, fetched via the GHCR API 2026-11-21):
  `Entrypoint: ['/opt/coder','server']`, `Cmd: null`, `User: 1000:1000`, `WorkingDir: /home/coder`.
- **Consequence:** a container that sets only `args: ["dbcrypt","decrypt","-y"]` executes
  `/opt/coder server dbcrypt decrypt -y` — exactly what we want. If you prefer to pin the whole command, set
  `command: ["/opt/coder","server","dbcrypt","decrypt","-y"]` (overrides the entrypoint). `kubectl run … -- X Y`
  sets *args*, not command ([k8s: define command and arguments](https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/)).
- The image is non-root (uid 1000) and needs no writable mounts for this command; anonymous GHCR pull works
  (the deployment already pulls it).

### A6. Safety property: a wrong key cannot make things worse

`Decrypt` starts by `dbcrypt.New(ctx, db, ciphers...)`, whose `ensureEncrypted` decrypts the `test` column of
every **active** key row with the supplied keys
([cliutil.go L247-L251](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go#L247-L260) →
[dbcrypt.go L37-L55, L75-L95](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/dbcrypt.go#L37-L95)).
Feeding the dev key against the gpu DB (or a typo) fails *before any write* with
`create cryptdb: ensure encrypted database fields: decrypt failed: …`. The digests recorded in startup logs —
dev `133ab0d`, gpu `e720c10` — are precisely the `HexDigest()`s (first 7 hex chars of SHA-256 over
`"aes256gcm"‖key`, [cipher.go `cipherAES256`](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cipher.go#L46-L66))
that must appear in each DB's `dbcrypt_keys.active_key_digest`, so per-cluster key↔DB pairing is
pre-verifiable with the read-only SELECT in the runbook.

### A7. Why the keys really encrypted (context, incident facts 3–5, cited)

Soft-enforcement comment + start log: [enterprise/coderd/coderd.go L117-L129](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L117-L129);
entitlement warning ("External Token Encryption is enabled (due to setting external token encryption keys) but
your license is not entitled to this feature."): [L1215-L1222](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L1215-L1222).
The warning recomputes `Enabled = len(api.ExternalTokenEncryption) > 0` each sync — after decrypt + key removal
it goes away with zero config changes.

## 3. B — Impact on existing data

### B1. With decrypt (recommended): rows survive, values become plaintext

The gpu counts (fact 6) each take the "decrypt, keep row" path: **1** `external_auth_links` (Forgejo approval),
**1** `user_links` (OIDC tokens), **0** `user_secrets`, **0** `gitsshkeys`. Nothing user-visible changes —
tokens continue to work as plaintext at rest, which is exactly the pre-2026-10-25 state the community license
was in anyway.

### B2. If those rows were instead deleted (option 4 / `bcrypt delete`)

- `external_auth_links` (the Forgejo git approval): the user must re-approve in the browser
  (`/external-auth/forgejo` consent; Settings → Connections, or the template's
  `data.coder_external_auth` login prompt). Until re-approved: `GIT_ASKPASS` HTTPS git operations in
  workspaces lose the injected token, and template provision/`coder external-auth access-token` calls fail with
  a login-required error
  ([docs: Git Authentication in Workspaces / OAuth (external auth)](https://coder.com/docs/admin/external-auth)).
- `user_links` (OIDC): coderd *sessions* are `apikeys` rows — not in the encrypted-column set
  ([v2.38.2 docs field list](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L18-L40)) —
  so nobody is force-logged-out; but the stored provider tokens are gone, and the link row is recreated at the
  user's next OIDC callback ([coderd/userauth.go L1924 `InsertUserLink`](https://github.com/coder/coder/blob/v2.38.2/coderd/userauth.go#L1924)).
  Cost = one browser OIDC round-trip per user at next login (usually silent SSO), plus any feature that reads
  the stored id/access token before then (e.g. userinfo-based group sync at login is refreshed anyway).
- Both tables' losses are **avoided entirely** by decrypt — which is why option 4 stays rejected.

### B3. `crypto_keys` — wiped either way; impact is bounded and self-healing

The 6 rows (gpu, re-inventoried 2026-11-21) **cannot be decrypted by any v2.38.2+ tool** (A3b) and their
survival blocks the key revoke, so the runbook wipes them (`secret=NULL, secret_key_id=NULL` — the product's own
[`DeleteCryptoKey`](https://github.com/coder/coder/blob/v2.38.2/coderd/database/queries/crypto_keys.sql#L27-L30)
semantics, and the
[workaround prescribed in #25381](https://github.com/coder/coder/issues/25381)). Regeneration is automatic:

- `cryptokeys.StartRotator` runs **on every coderd start** — first pass immediately, then every 10 min — and
  "may insert a new key if it detects that a valid one does not exist for a feature"
  ([rotate.go L94-L124, L132-L190](https://github.com/coder/coder/blob/v2.38.2/coderd/cryptokeys/rotate.go#L94-L190),
  called from [coderd/coderd.go L655](https://github.com/coder/coder/blob/v2.38.2/coderd/coderd.go#L655)).
- Feature-level impact of wiping the current rows
  (enum values per migrations [000271](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000271_cryptokey_features.up.sql),
  [000533](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000533_nats_ca_crypto_key_feature.up.sql),
  [000572](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000572_chat_files_token_crypto_key_feature.up.sql);
  lifetimes per [rotate.go L21-L32](https://github.com/coder/coder/blob/v2.38.2/coderd/cryptokeys/rotate.go#L21-L32)):

| feature | what it signs | token lifetime | impact if row wiped |
|---|---|---|---|
| `workspace_apps_token` | workspace-app JWTs coderd mints per app session | 1 min | effectively none — re-mints on next request/page load |
| `workspace_apps_api_key` | encrypts workspace-app API keys (the only *encryption* feature) | — | previously stored app API keys unreadable → the app's key-provisioning/login runs again |
| `oidc_convert` | one-shot OIDC→password conversion tokens | 5 min | aborts at most an in-flight conversion |
| `tailnet_resume` | tailnet resume tokens (fast agent reconnect) | 24 h | agents do a fresh handshake instead of resume — brief tunnel reconnect |
| `chat_files_token` | chat file download URLs | 5 min | stale chat file links die (chat unused in lab → nil) |
| `nats_ca` | enterprise-build NATS client CA (HA coordination mTLS) | 30 min overlap | leaves re-mint after CA regeneration; agent coordination tunnels re-handshake once |

Which two features the gpu rows hold is unknown until the inventory SELECT (§runbook step 3) — record it
before wiping.

## 4. C — The dev time bomb

Mechanism, verified against k8s semantics: environment variables from a Secret (including `envFrom`) are
resolved **at container start**; a running container keeps its baked values and Secret edits never reach it
("ConfigMaps consumed as environment variables are not updated automatically and require a pod restart" —
[k8s ConfigMap concepts, Updates section](https://kubernetes.io/docs/concepts/configuration/configmap/);
Secrets follow the identical kubelet path,
[k8s Secrets — Using Secrets as environment variables](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables)).
Dev's coderd (started 2026-11-19, fact 7) holds `133ab0d…` only in process memory; `coder-secrets` on dev lost
the key when the ExternalSecret re-rendered after the 00:13 sync (gpu's crash proves the pipeline end-to-end —
gpu is the same chart, same Reloader annotation
([services/gpu/prod/values.yaml L506-L528](../../../services/gpu/prod/values.yaml), the coder entry carrying
`reloader.stakater.com/auto: "true"` + `envFrom: coder-secrets`).

Therefore: **every possible dev container start from now on is a fatal start** — Reloader on any future
`coder-secrets` rewrite, pod eviction, node rotation/drain, a template edit re-rendering the Deployment, OOM,
even a cluster reboot. Option C(a) vs C(b) from the brief:

- **(a) decrypt dev now within a controlled window** (scale 0 → Job → scale back; ~5–10 min): terminal, removes
  the landmine and the warning in one move. **Recommended.**
- **(b) rollback-revert then schedule:** valid (decision-table option 2) but it must be a *real revert that
  lands* — a half-revert leaves the same bomb; and meanwhile dev continues encrypting *new* rows (the crypto-key
  rotator writes with the in-memory key every ≤10 min, per A/B3) so the eventual decrypt grows slightly. Use
  (b) only if (a)'s window can't be secured today. **The state between "keys removed" and "DB decrypted" is the
  only unsafe state; don't park there** — that is the verified version of the brief's reasoning.
- Reloader caveat: we could not establish why dev has not restarted yet (its Reloader trigger presumably
  already fired at the Secret change; reloader may not be deployed/watching in the dev cluster the way it is on
  gpu — the values comment even says "Reloader (cluster-wide on **gpu**, deployed by base…)"). Either way the
  conclusion stands; see Open questions #2.

## 5. Runbooks (user-executed; agents have no pod-exec and ArgoCD owns the manifests — cf. AGENTS.md)

Shared facts: coderd Deployment name **`coder`**, namespace **`default`**, image **`ghcr.io/coder/coder:v2.38.2`**,
DSN at Secret **`coder-secrets`** key `CODER_PG_CONNECTION_URL` (embeds the DB password — keep it out of shell
history: prefix such lines with a space or `set +o history`; the `psql`/Job commands below also pass it as a
pod env, visible in `kubectl get pod -o yaml` while the pod lives — acceptable in this lab, delete the pod after
with `--rm`). DB host `pg-coder-rw` (CNPG) is cluster-internal, so every step runs **in the affected cluster**.
Both Bitwarden items still exist (fact 8). The whole op is ~5–10 min; do **one cluster at a time**.

> **Do not skip the backup (step 2)** — the docs repeat it on every procedure
> ([v2.38.2 docs Turn-off L146](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L142-L150)).
> If decrypt dies at the FK violation anyway (missed step 5), the fix is idempotent re-run — no data is lost by
> the failure itself except that already-decrypted rows simply decrypt cleanly.

### 5.1 GPU runbook (fully down — execute now)

**Inputs (gpu):** Bitwarden item `a59487dd-0a84-454f-8669-b4ee0034a69c` (password field = base64 key; expected
digest `e720c10`). Argo app for step 1b discovered in step 1a.

1. **Orient & freeze GitOps.**
   ```bash
   kubectl config current-context                      # must be the GPU cluster
   kubectl -n default get deploy coder -o wide
   kubectl -n default get deploy coder -o jsonpath='{.spec.replicas}'; echo     # note N (expected restart size)
   kubectl -n default get deploy coder -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/instance}'; echo  # → APP
   ```
   Disable auto-sync on that Application so ArgoCD's `selfHeal` (on by default —
   [services/gpu/prod/templates/appset.yaml L138-L143](../../../services/gpu/prod/templates/appset.yaml)
   renders `automated: {prune: true, selfHeal: true}` unless the `services.<svc>.selfHeal` annotation says
   otherwise) cannot resurrect the scale-down mid-op:
   ```bash
   argocd app set <APP> --sync-policy none     # or toggle AUTO-SYNC off in the UI
   ```
   *(Accepting a race instead of pausing is NOT recommended: selfHeal re-applies drift on every ~3-min sync.)*
2. **Backup.** Use the CNPG instance pod so client and server versions always match:
   ```bash
   POD=$(kubectl -n default get pod -l cnpg.io/cluster=pg-coder -o jsonpath='{.items[0].metadata.name}')
   DSN=$(kubectl -n default get secret coder-secrets -o jsonpath='{.data.CODER_PG_CONNECTION_URL}' | base64 -d)
   kubectl -n default exec "$POD" -c postgresql -- pg_dump "$DSN" --no-owner \
     > coder-gpu-backup-$(date -u +%Y%m%dT%H%M%SZ).sql
   wc -c coder-gpu-backup-*.sql                # must be non-trivial
   ```
3. **Open a psql session and take the inventory** (also tells you *which* `crypto_keys` features you are about
   to wipe, and confirms `active_key_digest = e720c10` matches the Bitwarden key):
   ```bash
   kubectl -n default run coder-sql --rm -it --restart=Never \
     --image=postgres:16-alpine --env="PGURL=$DSN" -- sh -c 'psql "$PGURL"'
   ```
   ```sql
   SELECT 'user_links' t, count(*) n FROM user_links
     WHERE oauth_access_token_key_id IS NOT NULL OR oauth_refresh_token_key_id IS NOT NULL
   UNION ALL SELECT 'external_auth_links', count(*) FROM external_auth_links
     WHERE oauth_access_token_key_id IS NOT NULL OR oauth_refresh_token_key_id IS NOT NULL
   UNION ALL SELECT 'user_secrets', count(*) FROM user_secrets WHERE value_key_id IS NOT NULL
   UNION ALL SELECT 'gitsshkeys', count(*) FROM gitsshkeys WHERE private_key_key_id IS NOT NULL
   UNION ALL SELECT 'chat_mcp_servers', count(*) FROM chat_mcp_servers WHERE headers_key_id IS NOT NULL
   UNION ALL SELECT 'ai_providers', count(*) FROM ai_providers WHERE settings_key_id IS NOT NULL
   UNION ALL SELECT 'ai_provider_keys', count(*) FROM ai_provider_keys WHERE api_key_key_id IS NOT NULL
   UNION ALL SELECT 'user_ai_provider_keys', count(*) FROM user_ai_provider_keys WHERE api_key_key_id IS NOT NULL
   UNION ALL SELECT 'crypto_keys', count(*) FROM crypto_keys WHERE secret_key_id IS NOT NULL
   UNION ALL SELECT 'mcp_server_configs', count(*) FROM mcp_server_configs
     WHERE oauth2_client_secret_key_id IS NOT NULL OR api_key_value_key_id IS NOT NULL
        OR custom_headers_key_id IS NOT NULL OR signing_secret_key_id IS NOT NULL
   UNION ALL SELECT 'mcp_server_user_tokens', count(*) FROM mcp_server_user_tokens
     WHERE access_token_key_id IS NOT NULL OR refresh_token_key_id IS NOT NULL;

   SELECT number, active_key_digest, revoked_key_digest, revoked_at, created_at
     FROM dbcrypt_keys ORDER BY number;

   SELECT feature, sequence, starts_at, deletes_at, secret_key_id
     FROM crypto_keys WHERE secret_key_id IS NOT NULL;   -- save this output!
   ```
   Expected on gpu: `crypto_keys = 6` (re-inventoried 2026-11-21; was 2 on 2026-11-19 — the rotator kept
   writing with coderd's in-memory key), one active key row `e720c10`; every other encrypted count is 0 except
   `user_links`=1 and `external_auth_links`=1. Pre-wipe crypto_keys record (all secret_key_id=e720c10):
   workspace_apps_token seq16, workspace_apps_api_key seq16, oidc_convert seq16, tailnet_resume seq16,
   nats_ca seq1, chat_files_token seq1
   ([#25381 proves decrypt would fail at revoke with these rows present](https://github.com/coder/coder/issues/25381)).
4. **Stop coderd** (already effectively dead; this stops the crash churn and satisfies "stop all active coderd",
   [docs Turn-off L148-L149](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L142-L167)):
   ```bash
   kubectl -n default scale deploy coder --replicas=0
   kubectl -n default get pods                                          # wait until no coderd pods remain
   ```
5. **Clear the rows decrypt forgot** (in the psql session — only while coderd is at 0; the crypto-key rotator
   would race you otherwise):
   ```sql
   UPDATE crypto_keys SET secret = NULL, secret_key_id = NULL
     WHERE secret_key_id IS NOT NULL;
   ```
   *If the inventory showed non-zero `mcp_server_configs` / `mcp_server_user_tokens` counts, STOP and route
   back through the pipeline — those clears were not needed here and their exact column-nullability was not
   rehearsed (see Open questions #5).*
6. **Run decrypt** (quick form; entrypoint `/opt/coder server` makes this `coder server dbcrypt decrypt -y`):
   ```bash
   # paste the base64 key from Bitwarden item a59487dd-0a84-454f-8669-b4ee0034a69c (Password field)
   KEY='<base64-key-from-bitwarden>'
   kubectl -n default run coder-dbcrypt-decrypt --rm -i --restart=Never \
     --image=ghcr.io/coder/coder:v2.38.2 \
     --env="CODER_PG_CONNECTION_URL=$DSN" \
     --env="CODER_EXTERNAL_TOKEN_ENCRYPTION_DECRYPT_KEYS=$KEY" \
     -- dbcrypt decrypt -y
   ```
   Success looks like: `connected to postgres` → `decrypting user tokens user_count=N` →
   (`revoked unused key digest=e720c10` →) `operation completed successfully`
   ([cliutil.go L453-L460](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go#L453-L462)).
   A `rotate ciphers: revoke key: pq … violates foreign key constraint` failure = leftover FK rows: redo
   step 5 and re-run this step (idempotent).

   Hardened variant (keeps the DSN out of the shell entirely): create
   `kubectl -n default create secret generic dbcrypt-decrypt-key --from-literal=CODER_EXTERNAL_TOKEN_ENCRYPTION_DECRYPT_KEYS="$KEY"`,
   run a Job with `args: ["dbcrypt","decrypt","-y"]` and `envFrom:` both `coder-secrets` (supplies
   `CODER_PG_CONNECTION_URL`) and that key Secret, then delete the key Secret. The unrelated `CODER_*` keys in
   `coder-secrets` are inert for this command (A4).
7. **Verify** (psql session again):
   ```sql
   -- re-run the step-3 inventory: EVERY count must now be 0, and:
   SELECT number, active_key_digest, revoked_key_digest, revoked_at FROM dbcrypt_keys;
   -- expect: active_key_digest NULL, revoked_key_digest 'e720c10', revoked_at set
   ```
8. **Bring coderd back** and check the three negative log assertions:
   ```bash
   kubectl -n default scale deploy coder --replicas=<N>     # from step 1
   kubectl -n default rollout status deploy/coder --timeout=180s
   kubectl -n default logs deploy/coder --since=10m \
     | grep -E 'database encryption enabled|unknown key|not entitled' || echo 'CLEAN'
   ```
   Expected: no matches (CLEAN). `database encryption enabled` must be gone
   ([coderd.go L123-L129](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L117-L129)),
   the fatal is gone, and the entitlement warning is gone
   ([coderd.go L1215-L1222](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L1215-L1222)).
   Then: log in to the gpu Coder UI (OIDC), open a workspace, confirm workspace apps + a tunnel connect
   (tailnet resume re-handshake expected once, B3).
9. **Unfreeze GitOps:**
   ```bash
   argocd app set <APP> --sync-policy automated --auto-prune --self-heal
   argocd app get <APP>          # Synced / Healthy
   ```
   Nothing in git needs touching — the repo already ships the keyless template with the rationale comment
   ([charts/coder/templates/secret-coder.yaml L57-L61](../../../charts/coder/templates/secret-coder.yaml)).

**Expected gpu downtime: the remainder of this runbook ≈ 5–10 minutes total** (it is already down; decrypt of
~4 rows is seconds; the coderd cold start + OIDC probe is the rest).

### 5.2 DEV runbook (scheduled window, same day)

**Inputs (dev):** Bitwarden item `4a7b0218-e9af-4205-9fe6-b4ee00347021` (expected digest `133ab0d` — fact 2's
startup log). DB `pg-coder-rw`, deploy `coder`, namespace `default` — everything below is the GPU runbook with
these substitutions. Do it *deliberately* (§C: dev is the ticking one); pick any quiet 10 minutes.

1. Same as gpu step 1 (context = **dev** cluster; note replicas `N`, find `<APP>`, `argocd app set <APP> --sync-policy none`).
2. Backup: `POD=$(kubectl -n default get pod -l cnpg.io/cluster=pg-coder …)`, `pg_dump "$DSN" --no-owner >
   coder-dev-backup-…sql`.
3. Inventory + `SELECT … FROM dbcrypt_keys` — dev's state is unverified (fact 7 says assume an active `133ab0d`
   row + encrypted rows); the query confirms it, and records which `crypto_keys`/other rows exist.
4. **Controlled stop** — this is the only step with real service impact on dev:
   `kubectl -n default scale deploy coder --replicas=0` and wait for pod exit. Announce in the lab channel if
   workspaces are mid-build; builds die with coderd anyway.
5. `UPDATE crypto_keys SET secret = NULL, secret_key_id = NULL WHERE secret_key_id IS NOT NULL;`
   (plus STOP-case for mcp tables, as gpu).
6. Decrypt Job with **dev's** key from item `4a7b0218-e9af-4205-9fe6-b4ee00347021`:
   ```bash
   kubectl -n default run coder-dbcrypt-decrypt --rm -i --restart=Never \
     --image=ghcr.io/coder/coder:v2.38.2 \
     --env="CODER_PG_CONNECTION_URL=$DSN" \
     --env="CODER_EXTERNAL_TOKEN_ENCRYPTION_DECRYPT_KEYS=$KEY_DEV" \
     -- dbcrypt decrypt -y
   ```
   Wrong-key pairing is a safe abort before any write (A6).
7. Verify: inventory all-zero, `dbcrypt_keys` shows `revoked_key_digest='133ab0d'`, `active_key_digest NULL`.
8. Scale back to `N`; log grep CLEAN; UI login + workspace check.
9. Re-enable automated sync; confirm ArgoCD Synced/Healthy.

**Expected dev downtime: ~3–7 minutes** (image is already on nodes as the coderd image; decrypt itself is
sub-second at lab row counts; coderd start + readiness dominates).

## 6. E — Hygiene afterwards

- **Bitwarden items:** delete `4a7b0218-…` / `a59487dd-…` only after **that cluster** verifies step-7 (both
  counts zero + key revoked) and step-8 (coderd CLEAN) — they are still the only way to retry decrypt if an
  early step misfires, and the revoked key must stay decryptable until its rows are gone (there are none left
  afterwards, so post-verification deletion is safe and loses nothing). Keep them at least until *both*
  clusters are done if you want one uniform rollback point.
- **Repo:** no further code change is required for recovery — the keyless `coder-secrets` template already
  landed on main with its rationale comments
  ([secret-coder.yaml L57-L61](../../../charts/coder/templates/secret-coder.yaml),
  [services/gpu/prod/templates/secrets-coder.yaml L44-L48](../../../services/gpu/prod/templates/secrets-coder.yaml)).
  Note for the coordinator: `tests/services/dev-git-auth.sh` (c-sso-1 block, ~L288-L337) and
  `tests/services/gpu-coder-sso.sh` still assert the *encryption wiring contract* and are being corrected in a
  follow-up branch — **do not touch them in this ticket** (verified in-worktree read-only).
- Optional follow-up for the pipeline: record in `DECISIONS.md` that the lab's chosen posture is
  "encryption off (community-license soft-enforcement is unacceptable), with decrypt + `crypto_keys` wipe per
  this runbook", so a future "just re-add the keys" suggestion has to fight an existing ruling instead of the
  warning.

## 7. F — Alternatives & risk register

| Alternative | Verdict | Why (grounded) |
|---|---|---|
| Hand-SQL the decrypt: offline AES-256-GCM per value, write plaintext, clear `*_key_id`, revoke by hand | **Against** | The wire format is real crypto code — `base64(nonce‖ciphertext‖tag)`, 12-byte GCM nonce prefix, key = raw 32 bytes ([cipher.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cipher.go)) — and every `*_key_id` is FK-guarded (A3b); a mistake (wrong column pair, missed table, bad base64) writes undetectable garbage into live token columns. The tool + the one sanctioned `DeleteCryptoKey`-style UPDATE (step 5) covers the same job inside product semantics. |
| `coder server dbcrypt delete` | Against here | Destructive by design ([docs](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L186-L203)), intended for a *lost* key (ours exist); its revoke loop hits the same #25381 FK wall; users would lose the Forgejo approval + OIDC link (B2). |
| Premium license | One line | Silences the warning and keeps encryption, but the config removal already happened and gpu is down — not a recovery path; revisit only as a future policy choice. |
| Wait for a coder release that fixes decrypt | Against | #25381 open, fix PR #28341 closed unmerged, main unchanged (verified 2026-11-21); and "leave gpu down" is a non-option for the lab. |
| Leave gpu crash-looping until a maintenance window | Against | Fully-down service; the decrypt is minutes and dev needs the same op anyway. |
| Restore keys (option 2) as the *permanent* answer | Against | Re-arms the paid-feature warning and re-arms the same removal-time landmine for the next operator; only acceptable as a bridge. |

## 8. Open questions / lab-specific unknowns

1. **Dev DB state unverified** (fact 7): exact row counts per table, whether its active digest is still
   `133ab0d`, and whether ESO has already rewritten dev's Secret. Dev runbook step 3 answers all three; run it
   *before* committing a window if read access to dev `coder-secrets` + a psql pod is available (the Secret
   content check does not need coderd at all).
2. **Why is dev's pod not restarted since 00:13?** Candidates: no Reloader deployed/watching in the dev cluster
   (gpu's values comment says Reloader is "cluster-wide on gpu, deployed by base"), or dev's Secret data hasn't
   actually changed yet. Check: `kubectl -n default get secret coder-secrets -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' | grep EXTERNAL_TOKEN`;
   `kubectl -n default get deploy coder -o jsonpath='{.spec.template.metadata.annotations}'`.
   Does not change the recommendation (the bomb is any restart either way) but calibrates urgency.
3. **Exact ArgoCD Application names** managing `deploy/coder` in each cluster — discovered at runbook step 1
   via the `argocd.argoproj.io/instance` label (the ApplicationSet matrix naming makes hardcoding risky;
   repo: [appset.yaml](../../../services/gpu/prod/templates/appset.yaml) renders one app per serviceName per
   cluster).
4. **Coder Deployment replica count** on each cluster (step 1 records it) — everything above assumes the
   standard single-replica coderd; a multi-replica dev/gpu would need *all* replicas stopped (docs' "all active
   coderd instances"), which scale-to-0 does regardless.
5. **mcp_server_configs / mcp_server_user_tokens rows** — the incident's per-table encrypted counts didn't
   include these (feature presumably unused); if step-3 inventory shows rows on either cluster, stop: the
   column-level clear statements for those two tables were deliberately not rehearsed here (exact nullability of
   `mcp_server_configs.oauth2_client_secret` etc. per
   [000447](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000447_mcp_server_configs.up.sql)
   needs a careful read + a test before anyone executes one).
6. **CNPG Postgres major version** — the `postgres:16-alpine` psql client used for queries is protocol-fine
   against PG 13–17, but **backup correctness** relies on `pg_dump` executed inside the CNPG pod itself (version
   matched); confirm `pg_coder` is the CNPG cluster label value in each cluster (`kubectl get cluster.postgresql.cnpg.io -n default`).
7. **Bitwarden fetch path** — via `bw get password <uuid>` or the web vault; agent sessions have no vault
   access, so this stays a human step (consistent with the runbook's "user runs it" contract).

## 9. Contradictions & doc-drift found during retrieval

- **docs vs code (revocation wall):** docs promise decrypt "will decrypt all encrypted user tokens and revoke
  all active encryption keys" ([v2.38.2 L151-L154](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md#L150-L155));
  at v2.38.2 that promise is false whenever the #25381 tables hold rows — the *code + issue* win. The
  "Turn off encryption" wording also changed from the older "Disabling encryption" anchor that the fatal error
  message itself still links
  ([coderd.go L139](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go#L130-L142) →
  `#disabling-encryption`), a small drift to expect when pasting the URL from logs.
- **docs field list vs Decrypt's walk:** the docs list `crypto_keys.secret` among encrypted fields
  ([live docs](https://coder.com/docs/admin/security/database-encryption)) — which is precisely what the
  decrypt/delete commands omit; both statements are simultaneously true (encryption wrapper covers it; the CLI
  walks don't).
- **digest wording:** `doc.go` says "first 7 bytes of the SHA256 digest"; the code takes **7 hex characters**
  of the digest string ([cipher.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cipher.go#L46-L66)).
  The incident's `keys=[e720c10]` style values are consistent with the code reading; cosmetic elsewhere.
- **issue #25381 body** references an older table roster (`user_chat_provider_keys`, `chat_providers`) matching
  their version; v2.38.2's actual handled/unhandled split is re-derived from source above — trust the source.

## 10. Implications for the plan (what the planner must encode)

1. The ticket's execution steps are exactly the two runbooks; the **`crypto_keys` pre-wipe is a first-class
   step**, not an error-handling footnote — decrypt provably fails without it at this tag.
2. Sequence: gpu runbook first (it's down; zero added impact), dev same day; Bitwarden item deletions last,
   per-cluster, after verification.
3. ArgoCD auto-sync pause is mandatory around each run (selfHeal default-on, repo-verified); the pipeline must
   flag it as user-executed (no pod-exec / no kubectl apply of managed resources for agents).
4. The follow-up test-alignment branch (dev-git-auth.sh / gpu-coder-sso.sh) is where the repo's assertions
   change — not this ticket.

## 11. Addendum (2026-11-21): hiding the warning while KEEPING encryption (revert posture)

> **Status: this IS the lab's settled posture.** main reverted the removal
> (a70f2ac12), the keys are loaded again on both clusters, and §11's CLI switch
> now ships as a coderd env var (`CODER_NO_FEATURE_WARNING=true`) on both coder
> values blocks. The §5 decrypt runbooks stay in the pocket — they are mandatory
> before any future removal of the keys, not optional reading.


Owner chose the bridge (keys restored, warning returns). Verified suppressability
surface-by-surface at the deployed v2.38.2:

- **CLI — official switch.** Global `--no-feature-warning` / env
  `CODER_NO_FEATURE_WARNING=true` ([docs](https://coder.com/docs/reference/cli), flag
  table + [cli/root.go](https://github.com/coder/coder/blob/v2.38.2/cli/root.go)):
  skips `wrapTransportWithEntitlementsCheck`, the transport that prints the
  `X-Coder-Entitlements-Warning` response header (`codersdk/client.go` L112) once per
  invocation. Per-machine setting (shell rc / dotfiles / workspace env), not deployment-wide.
- **UI banner — no switch, admins only.** `LicenseBanner` renders the ENTIRE
  `entitlements.warnings` array with a `mailto:sales@coder.com` link appended
  ("Contact sales@coder.com." is UI chrome, not the server string — explains the suffix in
  the owner's paste). No dismiss affordance, no config; mounted behind
  `canViewDeployment` ([DashboardLayout.tsx L16-L20](https://github.com/coder/coder/blob/v2.38.2/site/src/modules/dashboard/DashboardLayout.tsx)),
  so non-admin members never see it. Community-level hiding = per-user browser
  userscript/Stylus, cosmetic only.
- **Proxy trick.** The UI ignores the header (it reads `/api/v2/entitlements` body), but
  every CLI warning rides it — stripping `X-Coder-Entitlements-Warning` in the hub/ingress
  Traefik Headers middleware silences the CLI fleet-wide at once; blunt: it hides ALL
  entitlement warnings the same way.
- **Server log line — unsuppressable.** Emitted by `updateEntitlements` via
  `api.Logger.Warn` every 10 min; `CODER_LOG_FILTER` gates DEBUG-level output only
  ([deployment.go L1818-L1826](https://github.com/coder/coder/blob/v2.38.2/codersdk/deployment.go#L1818-L1826)),
  warn is unconditional.
- **Licensing.** Any entitled license (premium) removes the warning with zero config
  change; the built-in trial (`POST /api/v2/licenses/trial`, added in this tag) would too,
  but trial licenses carry `RequireTelemetry`, and the server hard-errors when telemetry
  is disabled ("license requires telemetry enabled") — dead end for this lab's posture.

Bottom line: the ONLY deployment-wide, supported ways to kill THIS warning are remove the
keys (⇒ the decrypt trap documented above) or buy the entitlement. Client-side:
`CODER_NO_FEATURE_WARNING` covers CLI; UI has no honest hide.

## Sources

Retrieved 2026-11-21. Code at tag `v2.38.2` via `https://raw.githubusercontent.com/coder/coder/v2.38.2/…`
(and a sparse git checkout of the same tag for cross-file greps); line links point at tag-pinned `…/blob/v2.38.2/…`
permalinks.

1. [enterprise/cli/server_dbcrypt.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server_dbcrypt.go) — decrypt/delete/rotate subcommands, flags, env names, prompts, `-y`.
2. [enterprise/dbcrypt/cliutil.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cliutil.go) — `Decrypt`/`Rotate`/`Delete` walks, handled tables, revoke-all tail, no `crypto_keys`.
3. [enterprise/dbcrypt/dbcrypt.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/dbcrypt.go) — `New`, `GetDBCryptKeys` (revoked skipped), `decryptField`/`encryptField`, `ensureEncrypted`.
4. [enterprise/dbcrypt/cipher.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/cipher.go) — AES-256-GCM, digest = 7 hex chars of SHA-256(`"aes256gcm"‖key`).
5. [enterprise/dbcrypt/doc.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/dbcrypt/doc.go) — table semantics; "cannot revoke until rotated".
6. [enterprise/coderd/coderd.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/coderd/coderd.go) — soft-enforce, start log, fatal unknown-key wrap, entitlement warning.
7. [enterprise/cli/server.go](https://github.com/coder/coder/blob/v2.38.2/enterprise/cli/server.go) — `dbcrypt` mounted under `coder server`; keys→ciphers.
8. [cli/server.go](https://github.com/coder/coder/blob/v2.38.2/cli/server.go) — `ConnectToPostgres` (no migrations/NATS; PG≥13).
9. [cli/cliui/prompt.go](https://github.com/coder/coder/blob/v2.38.2/cli/cliui/prompt.go) — `-y/--yes`.
10. [coderd/cryptokeys/rotate.go](https://github.com/coder/coder/blob/v2.38.2/coderd/cryptokeys/rotate.go) + [cache.go](https://github.com/coder/coder/blob/v2.38.2/coderd/cryptokeys/cache.go) — StartRotator immediate pass, insert-if-missing, features/lifetimes.
11. [coderd/database/queries/dbcrypt.sql](https://github.com/coder/coder/blob/v2.38.2/coderd/database/queries/dbcrypt.sql) / [crypto_keys.sql](https://github.com/coder/coder/blob/v2.38.2/coderd/database/queries/crypto_keys.sql) — revoke swap-trick; `DeleteCryptoKey`.
12. Migrations: [000154](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000154_dbcrypt_key_ids.up.sql), [000251](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000251_crypto_keys.up.sql), [000447](https://github.com/coder/coder/blob/v2.38.2/coderd/database/migrations/000447_mcp_server_configs.up.sql), 000460/000495/000503/000515/000598/000601 (all FKs plain, non-deferrable).
13. [docs/admin/security/database-encryption.md @ v2.38.2](https://github.com/coder/coder/blob/v2.38.2/docs/admin/security/database-encryption.md) and [live v2.39 page](https://coder.com/docs/admin/security/database-encryption) + [decrypt CLI ref](https://coder.com/docs/reference/cli/server/dbcrypt/decrypt/) + [external-auth docs](https://coder.com/docs/admin/external-auth).
14. [issue #25381](https://github.com/coder/coder/issues/25381) (open) / [PR #28341](https://github.com/coder/coder/pull/28341) (closed, unmerged).
15. `ghcr.io/coder/coder:v2.38.2` amd64 image config via registry API (digest `sha256:dd8cc2b1…`): `Entrypoint /opt/coder server`, `User 1000:1000`; [scripts/Dockerfile](https://github.com/coder/coder/blob/v2.38.2/scripts/Dockerfile).
16. Kubernetes: [ConfigMap concepts — Updates](https://kubernetes.io/docs/concepts/configuration/configmap/) (env values are start-time, pod restart required), [Secrets — Using as environment variables](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables), [Define a Command and Arguments](https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/).
17. Lab repo (this worktree, read-only): [charts/coder/templates/secret-coder.yaml](../../../charts/coder/templates/secret-coder.yaml), [services/gpu/prod/values.yaml](../../../services/gpu/prod/values.yaml), [services/gpu/prod/templates/appset.yaml](../../../services/gpu/prod/templates/appset.yaml), [services/dev/prod/values.yaml](../../../services/dev/prod/values.yaml), [tests/services/dev-git-auth.sh](../../../tests/services/dev-git-auth.sh).

### Explicitly UNVERIFIED

- Dev DB contents and dev `coder-secrets` current data (runbook step 3 resolves; fact 7's assumption stands until then).
- Whether Reloader is actually watching coderd in the **dev** cluster (explains Open question #2's timing oddity).
- Exact ArgoCD Application names and coder replica counts per cluster (discovered at runbook step 1).
- CNPG Postgres major version (backup uses in-pod `pg_dump`, so it is version-safe regardless).
- Whether the gpu `crypto_keys` rows include `nats_ca` or any MCP/chat feature — **RESOLVED 2026-11-21** by
  read-only re-inventory: six rows, including `nats_ca` and `chat_files_token` (seq 1) plus the four seq-16
  signing features; `mcp_server_configs`/`mcp_server_user_tokens`/`chat_mcp_servers`/`ai_*`/`user_secrets`/
  `gitsshkeys` encrypted counts are 0, so no STOP-case widening is needed.
- Real-world execution of the composite procedure (decrypt-after-wipe with `ensureEncrypted` passing on
  provided keys) — the individual facts are all source-verified, but no lab rehearsal exists.
