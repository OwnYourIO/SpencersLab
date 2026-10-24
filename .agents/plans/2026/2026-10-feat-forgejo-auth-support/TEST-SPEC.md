# Test spec — 2026-10-feat-forgejo-auth-support

Written by agent-test (2026-10-24, single session for all chunks). These suites
are the contract for `agent-dev` and the re-run set for `agent-review`; tests
are immutable to dev. No unit-test framework exists in this repo (AGENTS.md
"Pipeline specifics"), so every test is a deterministic shell validation script
in the established `tests/` style.

Run all from the repo root:

- `bash tests/coder-workspace/image-structure.sh`
- `bash tests/coder-workspace/startup-script.sh`
- `bash tests/renovate/dockerfile-pins.sh`
- `bash tests/services/dev-git-auth.sh`

plus the plan file's Commands (lint `sh -n`/`dash -n`, `helm dependency build
charts/coder && helm lint && helm template`, the `services/dev` renders).

## C01 — image pins (expectations moved to the new floors)

| Check | Asserts | Criterion (chunks/C01.md) |
|---|---|---|
| `tests/coder-workspace/image-structure.sh` `PIN[OPENCODE_VERSION]=2.1.4`, `PIN[OPENCHAMBER_VERSION]=2.5.1` | the two Dockerfile ARGs are pinned to the plan's versions, each with its byte-identical renovate comment above (existing per-ARG machinery) | AC1, AC2, AC3 |
| `tests/renovate/dockerfile-pins.sh` `EXPECTED_NEW` npm tuples `2.1.4`/`2.5.1` | the renovate custom-manager extraction over the Dockerfile yields exactly the new pins | AC4 |

No new test files — the chunk mandates editing only these two expectation sets.
`COMMENT_RE`/manager regexes untouched. Pin currency re-verified at test time:
npm `latest` = `@openchamber/web` 2.5.1, `@opencode/cli` 2.1.4 (curl, 2026-10-24).
If dev takes a newer ≥-floor version per AC1/AC4's "or the newer chosen
versions, same values in the tests", it mirrors both expectation sets — that
mirroring is the plan's own sanctioned exception to test immutability, nothing else.

## C02 — workspace-startup.sh dual-host wiring (startup-script.sh extended)

New checks (all comment-stripped / code-lines only, in the file's existing
tally style); pre-existing checks all retained unchanged (AC2 "extended env
contract below" + AC6 byte-stability of the untouched sections):

| Check | Asserts | Criterion (chunks/C02.md) |
|---|---|---|
| env loop += `FORGEJO_TOKEN_CANONICAL`, `FORGEJO_HOST_CANONICAL` | both names are read as `$VAR`/`${VAR}` (AC3) | AC3 |
| `wire:` `-n` guard on `${FORGEJO_TOKEN_CANONICAL` (code line) | the canonical pair is optional-guarded — absent pair ⇒ no action | AC3 |
| `wire:` `wire_forgejo() {` definition present | single wiring path for both hosts | Tests bullet 4 |
| `helper:` canonical name referenced at the `wire_forgejo` call-site **or** as a literal `password=\$…CANONICAL` helper body | the helper echoes the token by env-var NAME (either legal layout) | AC4 |
| `fj:` every `add-token` call-site lives inside the `wire_forgejo` body | both hosts seed `fj` through the function, no inline copy drifting | Tests bullet 4 |
| `helper:` `password=\$` indirection present (regression) | use-time expansion survives the refactor | AC4 |
| `helper:` no `password=` + direct `${FORGEJO|GITHUB}` expansion | config time never expands the value | AC4 |
| `no-disk:` no `git-credentials`/`store` helper; no `>>` + token expansion | nothing written to disk (DECISIONS invariant, now for both pairs) | AC4 |
| `ssh:` `ssh-keyscan.*-p` in code; `22222` literal in code | forge SSH endpoint (node :22222) is the scanned port | AC5 |
| `ssh:` `git.scifi.farm` and `git.spencerslab.com` both appear in code | both lab hosts are pre-trusted/advertised | AC5, Tests bullet 6 |
| `ssh:` no `ssh-keyscan` line names a lab forge without `22222` | the old port-22 forge scan is gone | AC5 |
| `banner:` `git.spencerslab.com` named anywhere in the script | key-registration banner covers the canonical instance | Tests bullet 6 |

## C03 — canonical plumbing (dev-git-auth.sh extended)

New path var `SECRET_FORGEJO_CANONICAL`; fail-fast ordering matches the file's
existing style. Check ids follow the chunk's `c-canonical-N` naming:

| Check | Asserts | Criterion (chunks/C03.md) |
|---|---|---|
| `c-canonical-1` (8 ok lines) | `secret-forgejo-token-canonical.yaml` mirrors c1 verbatim: external-secrets.io/v1, name + `namespace: default`, bitwarden-login SecretStore, refreshInterval, conversion/decoding/metadataPolicy trio, template key `FORGEJO_TOKEN_CANONICAL`, remoteRef `property: password` reading `bitwardenIds.forgejo-token-canonical`; header comment (comment-inclusive, c5 convention) names `git.spencerslab.com` + `kubernetes-hardened` as consumers | AC1, Tasks bullet 1 |
| `c-canonical-2` | service values sentinel entry + custom-values slot that is a real UUID **or** the documented `OVERRIDE_NEEDED` placeholder (infra-forgejo t6 tolerance), never the service sentinel | AC1, AC5 |
| `c-canonical-3` | hardened main.tf: `FORGEJO_TOKEN_CANONICAL` env from `secret_key_ref` name `forgejo-token-canonical` key `FORGEJO_TOKEN_CANONICAL` `optional = true`; `FORGEJO_HOST_CANONICAL` literal bare `"git.spencerslab.com"` | AC1, AC4 (HCL structure asserted regardless of terraform availability) |
| `c-canonical-4` | c6 extension: the startup script reads both canonical names (drift trap between template and script) | AC6 |
| `c-canonical-5` (2 ok lines) | c4 extension: `--set bitwardenIds.forgejo-token-canonical=test-uuid` render produces the canonical ExternalSecret doc carrying `test-uuid` + the template key and no sentinel; the `-f custom-values` render leaves no service sentinel in that document | AC3 |

### Correction to an existing check (not a weakening)

dev-git-auth c4 split both rendered docs with `buf ~ /name:[[:space:]]*forgejo-token/`,
an unanchored prefix that — once C03 adds `forgejo-token-canonical` — captures
both ExternalSecret documents into `forgejo_doc`, making the *existing* c4 fail
for a false reason (the canonical doc's sentinel). Both selectors (the `--set`
render and the `-f custom-values` render) now require a boundary character:
`/name:[[:space:]]*forgejo-token[^A-Za-z0-9_-]/`. Behavior is identical while
only one doc exists (proven: baseline still green), and it strengthens document
isolation. Without it, AC1 ("original c1..c6 green") is unachievable.

## Evidence

### Baseline (before test edits, this branch)

All four suites green, matching DECISIONS' plan-time baseline:
image-structure 46/0 · startup-script 18/0 · dockerfile-pins 8/0 · dev-git-auth 20 ok.

### Red-for-the-right-reason (after test edits, implementation absent)

- `image-structure.sh` EXIT=1 — only 2 failures: `ARG OPENCODE_VERSION is pinned
  to '2.0.32', expected '2.1.4'`, `ARG OPENCHAMBER_VERSION is pinned to '2.4.0',
  expected '2.5.1'`; renovate-comment checks stay green.
- `dockerfile-pins.sh` EXIT=1 — only 1 failure: new-manager set diff
  `missing: npm|@opencode/cli||2.1.4 ; npm|@openchamber/web||2.5.1; unexpected: …2.0.32/2.4.0`.
- `startup-script.sh` EXIT=1 — 24 passed / 10 failed; all 10 fails target the
  new C02 contract (2 env names, guard, wire_forgejo def, canonical name ref,
  fj-through-function, `ssh-keyscan -p`, `22222`, `git.spencerslab.com`, banner);
  every pre-existing check + the 4 green new invariant-regressions
  (`password=\$`, no config-time expansion, no disk store, no default-port scan)
  pass.
- `dev-git-auth.sh` EXIT=1 — c1..c6 all still `ok` (20 lines), then
  `FAIL: c-canonical-1: services/dev/prod/templates/secret-forgejo-token-canonical.yaml is missing`
  — exactly the DECISIONS-predicted first red.

### Forward simulation (scratch repo at /tmp/opencode/fjsim, deleted after)

A simulated implementation of all three chunks (per the chunk Tasks, nothing
else) turns the whole set green: image-structure 46/0 · dockerfile-pins 8/0 ·
startup-script 34/0 · dev-git-auth **33 ok** — proving every new check is
satisfiable and the tightened c4 selectors survive the two-sibling-doc render.

Drift probes (fail-fast reaches each targeted check):

- no values sentinel → `FAIL c-canonical-2: … has no 'forgejo-token-canonical:
  OVERRIDE_VIA_CUSTOM_VALUES' entry`
- no main.tf env blocks → `FAIL c-canonical-3: no container env block sets
  FORGEJO_TOKEN_CANONICAL`
- C03 landed but startup reverted to pre-C02 → `FAIL c-canonical-4: … never
  reads FORGEJO_TOKEN_CANONICAL, so the template's canonical env name has no
  consumer`
- remoteRef near-miss key (`forgejo-token-canonical-lab`) passing the static
  substring check → `FAIL c-canonical-5: the rendered ExternalSecret ignores
  --set bitwardenIds.forgejo-token-canonical` — the render ladder is live, not
  decorative.

Layout-agnosticism probe: a second C02 implementation shape (explicit
per-host `add_known_forge … 22222` calls instead of the loop; helper string
inlined in `wire_forgejo` instead of reusing `configure_git_token`) keeps
startup-script 34/0 and dev-git-auth 33 ok — the checks bind the contract, not
dev's layout.

## Review runbook

1. `bash tests/coder-workspace/image-structure.sh` (C01 AC3)
2. `bash tests/renovate/dockerfile-pins.sh` (C01 AC4)
3. `bash tests/coder-workspace/startup-script.sh` (C02 AC2; AC1 via plan lint)
4. `bash tests/services/dev-git-auth.sh` (C03 AC1, includes c-canonical-5 render)
5. Plan Commands: `sh -n`/`dash -n` lint; `helm dependency build charts/coder &&
   helm lint && helm template`; the `--set bitwardenIds.forgejo-token-canonical=test-uuid`
   render (already inside suite 4).
