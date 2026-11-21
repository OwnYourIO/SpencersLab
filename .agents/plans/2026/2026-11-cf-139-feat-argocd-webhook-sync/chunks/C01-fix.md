# C01-fix: relay — dual signature dialect (R3) + `hook-secret` rename (R4), docs reword
size: S   wave: 4   depends_on: []   fixes: C01 (done @ dae5bc5f4)

## Goal

Make `containers/argocd-hook` speak the C04 caller's language: accept
`X-Forgejo-Signature` plain-hex HMAC-SHA256 alongside `X-Hub-Signature-256` (`sha256=`
prefixed), constant-time either way over the raw body, and rename the HMAC key file from
`github-webhook` to `hook-secret` (semantics moved off GitHub — the caller is the
main-sync job). Update the module docstring, `--help` and README to match.

## Tasks

- [ ] `main.py`:
  - constant `GITHUB_SECRET_FILE = "github-webhook"` → `HOOK_SECRET_FILE = "hook-secret"`;
    `--secrets-dir` help text follows.
  - `verify_signature(key, header, body)` → dialect-aware: accept
    (a) prefixed form (`sha256=<64 hex>`, bytes-after-prefix compared constant-time —
    existing behavior preserved exactly) or (b) bare 64-hex form. One function, dialect
    chosen by shape; no `sha256=`-less hub-header ambiguity: the CALLER-side header name
    decides which dialect is expected (see handler bullet), the shape check is defense
    in depth.
  - handler: header selection = first present of `X-Hub-Signature-256` (hub dialect
    REQUIRED: value must carry the `sha256=` prefix) else `X-Forgejo-Signature` (plain-hex
    dialect REQUIRED) else 401. **No cross-dialect fallback** — a present-but-malformed
    hub header 401s even if a valid forgejo header rides along (signature-confusion
    hygiene, R3 wording "per-header verification over the raw body").
  - `build_state` `--check`: HMAC sign/verify round-trip runs BOTH dialects (prefixed +
    bare) and both forgery rejects; success line names both.
  - docstring: "GitHub push-hook relay" → "push-hook relay (canonical caller: Forgejo
    main-sync hook-relay job; GitHub-shaped webhooks also accepted)"; comment on the
    secret read follows the rename; comment at read_secret_file about "GitHub webhook
    secrets" reworded to HMAC-key-file semantics (strip-safe rationale unchanged).
- [ ] `containers/argocd-hook/README.md`: line 3 dialect sentence (both headers), line 16
  `hook-secret`, add one line "caller today: main-sync hook-relay job; the public edge
  also accepts GitHub-shaped deliveries (door, no webhook created)".

## Files in scope

- `containers/argocd-hook/main.py`
- `containers/argocd-hook/README.md`
- (test re-pin: `tests/containers/argocd-hook-relay.sh` — agent-test session, before dev)

## Acceptance criteria

1. Both dialects verify: `X-Hub-Signature-256: sha256=<hex>` and
   `X-Forgejo-Signature: <hex>` each yield 202+fan-out with correct signature, 401 with
   wrong/forged; `compare_digest` used on both paths (review reads code).
2. Selection rule pinned: hub header present → hub dialect ONLY (bare hex in hub header =
   401; malformed hub header + valid forgejo header = 401); no headers = 401.
3. Event/ref/sync semantics ZERO change: `X-GitHub-Event` handling, `allowed_refs`,
   fan-out, sync calls untouched (diff contains no changes outside signature/secret-file/
   docstring/help/README lines).
4. `github-webhook` string gone from `containers/` and `charts/argocd-hook/` (grep 0 hits
   after C02-fix lands; within C01-fix itself: 0 hits in containers/).
5. `py_compile` passes; `--check` exits 0 on the fixture with dual round-trip lines;
   re-pinned relay harness green. `docker build => no-daemon, CI-deferred` honest line
   (image rebuild is the Forgejo workflow's).
6. README + docstring/help describe the main-sync origin, the GitHub-shaped door, and the
   dual dialect — no stale GitHub-webhook-only framing.

## Tests (agent-test re-pins, review runs)

`tests/containers/argocd-hook-relay.sh` re-pinned legs (keep all existing t-series
behavior, re-sign deliveries in both dialects):
- t3 family: accept matrix — valid hub 202; valid forgejo plain-hex 202; forged either
  401; bare-hex in hub header 401; `sha256=`-prefixed in forgejo header 401; both headers
  present with valid forgejo + invalid hub → 401 (no fallback); no headers 401.
- t-series secret hygiene: fixture writes `hook-secret` filename (rename from
  `github-webhook`); grep the harness for no residual old filename.
- NEW forge-delivery e2e leg: body built EXACTLY as the main-sync job builds it (same
  key set incl. `before`/`after`/`repository.full_name`, same header family
  incl. `X-Forgejo-Event`/`X-GitHub-Event: push`) → 202 + fan-out audit lines (proves
  C04's contract end-to-end offline; C04 dev runs this leg too).
- `--check` leg asserts dual round-trip success text.

## Notes for dev

- Smallest correct change: do NOT restructure the handler; one dialect-selection helper.
- `read_secret_file` comment already justifies strip() for "secrets and tokens never
  contain whitespace" — keep, reword the GitHub clause.
- Harness re-pin lands BEFORE you (agent-test); run the re-pinned suite, fix code until
  green — the suite is the spec.
- comment-slop discipline; aislop; commit is coord's.

## Review notes (review agent fills)
