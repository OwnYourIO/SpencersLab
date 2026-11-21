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

### Round 1 — 2026-11-21 (review agent) — verdict: CHANGES_REQUESTED (one text-only major; security walk clean)

Validations (run fresh in review session):

- `CHUNK_BASE=b7a81c3de bash tests/containers/argocd-hook-relay.sh` => PASS 7/7 (t1..t7)
- `python3 -m py_compile containers/argocd-hook/main.py` => PASS
- `npx aislop ci --changes` => PASS — score 100 Healthy, 0 errors, 1 warning
  (`complexity/file-too-large`: base main.py was 441 lines = exactly the flag
  threshold, dev's +17 crosses it). Not auto-fixable; splitting the module
  contradicts the chunk's "smallest correct change" note and AC3's line
  whitelist, and the single-file stdlib container is the repo convention
  (`traefik-mqtt-allowlist`). Gate policy is errors+score-floor => CI-green.
  Explained, not fixed here.
- Direct `--check` on a scratch hook-secret fixture => exit 0, prints
  `hmac round-trip: verified (hub + forgejo dialects)` (AC5)
- Adversarial probe battery: 15 raw-socket cases against the real handler
  (exact header casing / duplicates / empties), all behaved per spec — detail below.

Findings, severity order:

1. **major — `main.py:446` argparse description is stale GitHub-only framing**
   (`description="GitHub push-hook relay for ArgoCD sync fan-out"`). AC6: "README +
   docstring/help … no stale GitHub-webhook-only framing". Rendered `--help` confirms
   the summary line; the same phrase was replaced in the module docstring but this
   line was missed. Fix (one line, text-only):
   `description="push-hook relay for ArgoCD sync fan-out (canonical caller: Forgejo main-sync hook-relay job)"`
   — then re-run t7 + `--help`. No other AC6 surface missed.

Per-AC trace:

- AC1 ✓ — both dialects verify (hub t3-good + probe E3/E5; forgejo t3 positive legs
  + probe E7/C04-e2e leg → 202 + fan-out classified ok on live stub); forged/bad
  401s; `compare_digest` is the ONLY byte comparison of key-derived material, on
  both paths (`main.py:193`).
- AC2 ✓ — selection law holds empirically: bare-hex-in-hub 401 (E2b, harness
  hub-bare), sha256=-in-forgejo 401 (E10, harness), forged-hub-first + valid-
  forgejo 401 (E2/E4, harness mixed), none 401 (E11). Present-but-empty hub does
  NOT fall through — the `is not None` selection (not `or ""` truthiness) is the
  load-bearing detail; correct.
- AC3 ✓ — every hunk is within signature/secret-file/docstring/help/comment/
  README lines; event gate, allowed_refs, fan-out, sync calls byte-unchanged.
- AC4 ✓ (chunk-scoped) — `grep -rn github-webhook containers/` => 0 hits.
  `charts/` retains `secretKey: github-webhook` (secret-argocd-hook.yaml:18 +
  chart README:23) — C02-fix scope, expected. NB the other charts "hook-secret"
  hits are the `argocd-hook-secret` bitwardenIds/ES store-key name — a different
  identifier, NOT part of the R4 rename.
- AC5 ✓ — as commands above; `docker` CLI present, daemon down ⇒ `docker build =>
  no-daemon, CI-deferred` honest-line shape (cf-77), build is
  `.forgejo/workflows/containers-build.yaml` on the pushed branch.
- AC6 ✗ — major 1 (argparse description). Docstring ✓, README ✓, --secrets-dir
  help ✓, --check dual-dialect naming ✓.

Bypass ideas walked (each closed; probe id where empirically tested):

- forged/present-hub + valid-forgejo fallthrough => 401 always (E1 empty-hub,
  E2/E2b casing'd hub, E4 dup-hub garbage-first; hub branch never reaches the
  forgejo branch — the if/else split is exclusive, no code path re-checks).
- header-name casing games => `http.server` headers are an `email.message.Message`
  (case-insensitive `get`), so any-cased hub header still selects hub dialect (E2,
  E13 also proves the unchanged event gate is case-insensitive). Casing can only
  cause REJECTS, never accept: acceptance requires compare_digest equality with
  HMAC(secret, full raw body).
- duplicate headers => `get` returns first in document order (E4 401 garbage-first,
  E5 202 valid-first). Attacker-injectable dupes can only block (DoS, pre-existing
  crowdsec edge), never bypass.
- cross-shape replay (`sha256=`+valid digest in forgejo header, bare valid digest
  in hub header) => both 401 (E2b, E10 `SHA256=` case-variant prefix too —
  startswith is case-sensitive and the compare rejects regardless).
- verify-vs-parse ordering => HMAC verified over the raw bytes before any
  `json.loads`/event gate (E9: forged sig + non-JSON body answers 401, not 400).
- constant-time => compare_digest over the raw body on both paths; early returns
  (missing/empty/short/wrong-shape header) depend only on attacker-supplied shape
  bytes, never secret bytes; expected is fixed 64-byte hex so length-timing is
  constant.
- hex-case => lowercase-only acceptance == exactly what `openssl dgst -hmac` (C04,
  AC4 token `awk '{print $NF}'`) and GitHub emit; E7 lowercase 202 (no
  false-reject of the sanctioned caller), E6 uppercase 401; prefix strip is an
  exact 7-byte literal slice.
- `--check` failure modes => ConfigError texts carry file paths, field names and
  dialect labels only; t2 asserts SENTINEL/`tok-` never echo; direct run clean.

R4 rename completeness + parity-rule check:

- containers/ fully renamed (constant, --check, help, README, harness fixtures,
  and harness self-greps for the retired literal — t7).
- Intermediate inconsistent state (new image filename vs old chart ES secretKey)
  exists ONLY inside this branch: `git ls-remote` shows the branch unpushed, no
  PR, and both publish paths that produce consumable artifacts
  (`containers-build.yaml` main-push :yy.mm.N/:latest/:main; `release.yaml` chart
  publish) fire only from main — after the single PR that also contains C02-fix
  (wave 5, same plan). Same-release parity is therefore satisfiable. Even a
  hypothetical half-land fails loud and visible: missing `hook-secret` at
  startup is a ConfigError refuse-to-start (proven by t2's rename leg).

Docs-vs-code truth (README): every claim verified against behavior, including
the first-present/exclusive sentence (probe battery) and the "door, no webhook
created" line (R2 wording, also t7's grep gate). **R1 limitation clause added
beyond the task list: KEEP** — without it the pre-existing "Missed deliveries
are not replayed" sentence becomes misleading under R1 (no webhook, no Actions
redeliveries, at-most-once job); the added text is exactly DECISIONS'
ruled-in-documented-limitation and is true against C04's pinned
warn-and-continue posture. Docs-only, in file scope, not slop (external-system
fact the code cannot state).

Nits (non-blocking, no rework required):

- `main.py:407` "GitHub's 10s delivery budget" comment — still true for the R2
  door and the async design; fine to leave or fold a "(and C04's --max-time 15)"
  into C03-fix's doc sweep. Not part of major 1's one-line fix.
- `R3` decision-tags in docstring/README/comment: consistent with the repo's
  established decision-tag precedent (cf-139 OQ1/OQ6/OQ7 tags in approved code);
  keep as-is.

Deferred (out of C01-fix scope, informational):

- dev's bare `python3 -m py_compile` left `containers/argocd-hook/__pycache__/`
  — gitignored (`.gitignore:14`), invisible to the Dockerfile (`COPY main.py`),
  never in the image. Future runs: use `PYTHONPYCACHEPREFIX` like the harness.
- Test-surface observations for the next re-pin (agent-test, not dev): t6's
  allow-list `containers/argocd-hook/` would also admit a NON-ignored artifact
  inside the scope dir; the harness header's AC labels follow C01's numbering
  (t4=AC4 etc.) rather than C01-fix's 1–6 — traceability comment only, legs are
  correct.

STATE handoff text (for coord — reviewer writes no STATE): dev_rounds 1,
review_rounds 1, last_verdict CHANGES_REQUESTED; event line: "dev DONE
(dual-dialect R3 + hook-secret R4; harness 7/7, py_compile, aislop 0-error) +
review CHANGES_REQUESTED (1 major: argparse --help description stale GitHub
framing, AC6 — one-line text fix; security walk 15/15 probes clean, parity
verified satisfiable)".
