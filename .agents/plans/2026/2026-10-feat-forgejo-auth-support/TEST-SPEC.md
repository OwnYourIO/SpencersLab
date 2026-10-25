# Test spec — 2026-10-feat-forgejo-auth-support

Written by agent-test (2026-10-24, single session for all chunks). These suites
are the contract for `agent-dev` and the re-run set for `agent-review`; tests
are immutable to dev. No unit-test framework exists in this repo (AGENTS.md
"Pipeline specifics"), so every test is a deterministic shell validation script
in the established `tests/` style.
Replan v2 (C04–C06) traceability was appended by the replan test session
(2026-10-24) — the C01–C03 sections above it are frozen contract.

Run all from the repo root:

- `bash tests/coder-workspace/image-structure.sh`
- `bash tests/coder-workspace/startup-script.sh`
- `bash tests/renovate/dockerfile-pins.sh`
- `bash tests/services/dev-git-auth.sh`
- `bash tests/services/gpu-coder-sso.sh` (replan v2, C05)
- `bash tests/coder-workspace/startup-sso-behavior.sh` (replan v2, C06)

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
- `dev-git-auth.sh` EXIT=1 — c1..c6 all still `ok` (observable 15 ok lines + first FAIL under fail-fast ordering; "20" counted c4's helm-ladder ok lines, which move behind the c-canonical block — corrected per final review 2026-10-24), then
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

## Replan v2 — C04/C05/C06 (appended 2026-10-24 by the replan test session)

Two new suites plus extensions of the two established ones. The C01–C03 checks
frozen above stay unchanged and re-green as regressions in every state below.

### C04 — dev coder server (dev-git-auth.sh extended, `c-sso-1..4`)

New helper `data_entries()` (flattens each `- secretKey:` item of an ES's
`spec.data`, comments dropped — structure must not be satisfied by prose).
Checks continue the file's fail-fast ok/fail + helm-ladder style:

| Check | Asserts | Criterion (chunks/C04.md) |
|---|---|---|
| `c-sso-1` (5 ok lines, comment-inclusive) | `secret-coder.yaml` carries `CODER_EXTERNAL_AUTH_0_ID: "forgejo"` (the id embeds `/external-auth/<ID>/callback`), `_TYPE: "gitea"`, `_DISPLAY_NAME: "Forgejo"`, `_AUTH_URL` = dev-forge authorize path; CLIENT_ID/CLIENT_SECRET/ENCRYPTION_KEYS indirect through `ea_client_id`/`ea_secret`/`token_encryption_keys`; the three data entries pin bitwarden-login store + `bitwardenIds.coder-external-auth` (username+password) / `bitwardenIds.coder-token-encryption` (password) + the Default/None/None trio per entry; code-lines-only negative: no explicit `_REGEX/_TOKEN_URL/_VALIDATE_URL` (giteaDefaults owns them) | AC3, Tasks bullets 1–2 |
| `c-sso-2` (3 ok) | `charts/coder/values.yaml` `bitwardenIds` has both `OVERRIDE_VIA_CUSTOM_VALUES` sentinels; `custom-values/dev` `coder.bitwardenIds` has both keys, real UUID **or** `OVERRIDE_NEEDED` (t6 tolerance), never the service sentinel | Tasks bullets 2+4, AC5 |
| `c-sso-3` (2 ok, inside the helm ladder) | leg 1: `helm template coder <copy> --set domain --set all four bitwardenIds` → coder-secrets doc carries all seven keys, `forgejo`, the AUTH_URL, both test UUIDs, **no `OVERRIDE` substring**; leg 2: chart rendered with the `coder:` slice extracted from the real custom-values file → doc shows `OVERRIDE_NEEDED` remoteRef slots, no service sentinel | AC3 |
| `c-sso-4` (1 ok, render) | the coder Deployment pod template annotations == `reloader.stakater.com/auto: "true"` (python yaml walk of the leg-1 render) | AC4 |

### C05 — gpu coder server (NEW `tests/services/gpu-coder-sso.sh`, 15 ok)

Owns exactly the gpu leg so dev-git-auth stays single-cluster-scoped. Same
ok/fail + helm-skip discipline; coder chart pin is read from
`charts.coder.version` (no test-side version duplication beyond the AC5 pin).

| Check | Asserts | Criterion (chunks/C05.md) |
|---|---|---|
| `g-sso-1` (5 ok) | mirror of c-sso-1 on `services/gpu/prod/templates/secrets-coder.yaml` with the **canonical** AUTH_URL literal | AC2, Tasks bullet 1 |
| `g-sso-2` (4 ok) | gpu service values: both new sentinels + `coder.coder.podAnnotations` reloader key; custom-values/gpu: both keys UUID-or-`OVERRIDE_NEEDED`, never sentinel | Tasks bullets 2–3, AC4 |
| `g-sso-3` (4 ok, render ladder) | leg 1 umbrella render: coder-secrets doc seven keys + UUIDs + canonical URL, no OVERRIDE; leg 2: the ApplicationSet values blob (what ArgoCD feeds the external chart) carries the reloader annotation; leg 3: `helm pull coder <pin>` + render with the extracted `coder:` slice → **real Deployment pod template** carries it (registry-unreachable ⇒ skip, not fail); leg 4: `-f custom-values/gpu` render shows OVERRIDE_NEEDED, neither service nor legacy cluster-annotation sentinel | AC2, AC3 |
| `g-sso-4` (3 assertions, 2 ok lines emitted — per-row sum corrected 2026-10-24 per C05 review nit) | pairing guard: AUTH_URL host is `git.spencerslab.com` exactly; dev-forge host absent from it; the value differs from the dev twin's when defined — a copy-paste between the two server files fails HERE even when each file's own suite would pass | AC2 |

### C06 — workspace polite gate (startup-script.sh extended + NEW startup-sso-behavior.sh + c-sso-5..7)

`tests/coder-workspace/startup-script.sh` — +9 checks, code-lines only
(34 → 43):

| Check | Asserts |
|---|---|
| env loop += `FORGEJO_OAUTH_ID` | read as `$VAR`/`${VAR}` |
| `sso: probe` | a code line invokes `coder external-auth access-token "$FORGEJO_OAUTH_ID"` |
| `sso: unset` | a code line combines `--unset(-all)` with `credential.https://` |
| `sso: banner print` | the URL is captured via `X=$(coder external-auth` and an echo/log line prints `$X` (capture-variable binding, names free) |
| `sso: banner host` | an echo/log approval line names the forge host (`FORGEJO_HOST`/`sso…host`/literal) |
| `sso: gate` | the dev-pair `wire_forgejo` call carries a `no-helper` marker **or** an SSO-state guard within its 5-line window (4th-arg and equivalent-guard layouts both pass — DECISIONS: pattern allowed, not mandated) |
| `sso: canonical untouched` | the canonical call line and the line directly above it contain no SSO/no-helper reference (window is 1, not 5: a guard would sit directly above, while the dev block's own SSO lines must not false-positive it) |
| `no-disk: sso` | no coder-captured variable appears on a `>>` or `git config` line (vacuously green pre-implementation, like the C02 invariant regressions) |
| `clone: transient` | a `GIT_CONFIG_COUNT` or `git -c credential.helper` code line exists (env/`-c`-only credential carrier) |

NEW `tests/coder-workspace/startup-sso-behavior.sh` (22 ok) — dash-run matrix
against the **real committed script whole-file** (superset of the chunk's
"fragments": proves the gate in true boot order and that the rest of the boot
is unaffected), stub PATH shadowing `git`/`coder`/`fj`/`ssh-keygen`/
`ssh-keyscan` + isolated `HOME` (FRICTION review-C02 rule). `config` delegates
to REAL git against the scratch HOME (the on-disk helper state is the true
observable); `clone` is intercepted, recording url/dest + transient-credential
flags WITHOUT logging token values — real-network auth is plan User action 5,
not this harness:

| Check | Asserts |
|---|---|
| b-1 (5 ok) | approved + PAT pair ⇒ probe called with the id, dev-host helper NOT SET, stale-helper UNSET issued, fj still receives the bot PAT, SSO token in no HOME file and not on stdout |
| b-2 (1 ok) | pre-seeded stale helper in scratch `.gitconfig` is gone from the final real-git config dump |
| b-3 (4 ok) | unapproved ⇒ stdout has the exit-1 URL + host-naming approval banner, helper IS wired, dev-host repo still clones, exit 0 |
| b-4 (3 ok) | unapproved, no dev PAT ⇒ SSO-host clone SKIPPED with a pending-approval line (never raw fail), other-host repo proceeds, exit 0 |
| b-5 (5 assertions, 2 ok lines emitted — per-row sum corrected 2026-10-25 per final review nit) | `FORGEJO_OAUTH_ID` unset ⇒ zero coder calls, helper wired, no unset, no banner — the C02-shipped opt-out contract (already green pre-implementation: a regression pin, like the four C02 invariant checks) |
| b-6 (1 ok) | coder CLI absent from PATH ⇒ boot survives (exit 0), PAT fallback wired, warn/banner-ish line printed |
| b-7 (6 ok) | across ALL scenarios with the canonical pair present: canonical helper IS wired every time and never unset — dev-pair-only SSO layering |

`tests/services/dev-git-auth.sh` after the C04 block — +3 checks (47 ok total):

| Check | Asserts | Criterion (chunks/C06.md) |
|---|---|---|
| `c-sso-5` | exact string compare: `CODER_EXTERNAL_AUTH_0_ID` literal in `secret-coder.yaml` == `FORGEJO_OAUTH_ID` value literal in `kubernetes-hardened/main.tf` (missing either side fails naming the side) | AC4 |
| `c-sso-6` | c6 extension: the script reads `$FORGEJO_OAUTH_ID` (bound at the `$`-form, not a bare mention — the env-contract comment alone must not satisfy the drift trap) | AC4 |
| `c-sso-7` | main.tf value is bare `"forgejo"` — no scheme, no `var.`/`${` reference — and FORGEJO_HOST sits in the same container env family | AC4 |

### Replan-v2 contract notes / deliberate bindings

- Frozen-shape compliance: 4-arg `wire_forgejo` (marker as `$4`) keeps every
  C02 check (definition regex, `add-token`-in-body counts, `password=$`) green;
  provider id `forgejo` identical on both coders is pinned **per file** (g/c)
  and **across surfaces** only dev-chart↔main.tf (c-sso-5) — gpu has no
  workspace-side consumer in this ticket (DECISIONS: askpass-only there).
- Render-leg deviations from the plan's abbreviated Commands: the coder-secrets
  document also consumes the pre-existing `coder-sso-secret`/`coder-pg` keys,
  whose values-file defaults are sentinels (`OVERRIDE_VIA_CUSTOM_VALUES` on
  dev, `OVERRIDE_VIA_CLUSTER_ANNOTATION` on gpu). The AC "no OVERRIDE_* in that
  doc" clause is only satisfiable when the render resolves those too, so the
  ladders pass `--set` legs for them (exactly what the deploy-time layer does).
- AC3 "same render shows the pod annotation" is physically two proofs on gpu
  (umbrella values-blob leg + official-chart Deployment leg), since the coder
  chart is external and the umbrella alone never renders a coder Deployment.
- The behavioral harness runs the whole committed script under stubs rather
  than awk-extracted fragments: stronger than extraction (real ordering,
  untouched sections proven), same FRICTION-safety posture.

### Evidence (replan v2)

Baseline (before test edits): all four C01–C03 suites green on this branch
(dev-git-auth 33 ok · startup-script 34/0 · image-structure 46/0 · pins 8/0);
gpu umbrella + charts/coder renders already exit 0 with the coder-secrets doc
(AC2 feasibility claim re-verified, and `helm template … --set
coder.coder.podAnnotations=…` proven to land on the Deployment pod template in
both the wrapper and the standalone official chart 2.35.2).

Red-for-the-right-reason (after test edits, implementation absent — exit codes
captured without pipes):

- `dev-git-auth.sh` EXIT=1 — 26 ok (all c1..c6 + c-canonical static checks
  still green), then `FAIL: c-sso-1: CODER_EXTERNAL_AUTH_0_ID is not the
  literal "forgejo"`.
- `gpu-coder-sso.sh` EXIT=1 — first line
  `FAIL: g-sso-1: CODER_EXTERNAL_AUTH_0_ID is not the literal "forgejo"`.
- `startup-script.sh` EXIT=1 — 36 passed / 7 failed; the 7 fails are exactly
  the new SSO contract lines (env name, probe, unset, banner print, banner
  host, gate, transient clone); the 2 new invariant negatives (canonical
  untouched, no coder-var disk write) and all 34 pre-existing checks green.
- `startup-sso-behavior.sh` EXIT=1 — `FAIL: b-1: the probe never ran 'coder
  external-auth access-token forgejo' — the SSO gate has no input`.

Forward simulation (scratch clone at /tmp/opencode/fjsim-replan, per the three
chunks' Tasks, deleted after): **dev-git-auth 47 ok · gpu-coder-sso 15 ok ·
startup-script 43/0 · startup-sso-behavior 22 ok · image-structure + pins
green · sh/dash/bash -n green · terraform init+validate (scratch, coder
provider) green** — every new check satisfiable.

Drift probes (each red on exactly its target, then reverted):

- main.tf `FORGEJO_OAUTH_ID = "forgejo2"` → `FAIL c-sso-5: provider-id drift:
  … says "forgejo" … says "forgejo2" …`.
- dev twin `secret-coder.yaml` AUTH_URL copied to the canonical host → gpu
  suite `FAIL g-sso-4: gpu and dev provider AUTH_URL are identical (…)` — the
  pairing trap fires from the OTHER suite, which is the point.
- charts/coder values podAnnotations removed →
  `FAIL c-sso-4: the coderd pod template annotations are {…} — coder.coder.podAnnotations did not reach the pod`.
- `--unset-all` line deleted → behavior `FAIL b-1: approved ⇒ a stale dev-host
  credential.helper must be unset … none happened` AND static
  `fail: sso: no '--unset ... credential.https://' code line`.
- dev-pair wiring made unconditional → behavior `FAIL b-1: the dev-host PAT
  credential helper WAS wired while SSO is approved` AND static
  `fail: sso: the dev-pair wire_forgejo call is unconditional`.

Layout-agnosticism probe: a second legal C06 gate shape (no if/else at the
call site — `helper_mode_arg` set from an SSO guard one line above, passed as
the 4th arg) keeps startup-script 43/0, behavior 22 ok and dev-git-auth 47 ok.
(This probe is what pinned the canonical-negative window to 1 line: a wider
window false-positives on the dev block's own SSO lines preceding canonical.)

## Review runbook

1. `bash tests/coder-workspace/image-structure.sh` (C01 AC3)
2. `bash tests/renovate/dockerfile-pins.sh` (C01 AC4)
3. `bash tests/coder-workspace/startup-script.sh` (C02 AC2; AC1 via plan lint)
4. `bash tests/services/dev-git-auth.sh` (C03 AC1, includes c-canonical-5 render)
5. Plan Commands: `sh -n`/`dash -n` lint; `helm dependency build charts/coder &&
   helm lint && helm template`; the `--set bitwardenIds.forgejo-token-canonical=test-uuid`
   render (already inside suite 4).

Replan v2 (run after suites 1–4; C04/C05 land in wave 3, C06 in wave 4):

6. `bash tests/services/gpu-coder-sso.sh` (C05 AC1; includes the umbrella +
   custom-values + official-chart renders — the `helm pull coder` leg skips,
   not fails, when helm.coder.com is unreachable, then gate AC3 separately
   with the plan's render command)
7. `bash tests/services/dev-git-auth.sh` again (C04 AC1: c-sso-1..4; from
   wave 4 onward also the C06 c-sso-5..7 drift traps — C04-only state fails
   at c-sso-5, which is fail-as-expected for C06, not a C04 regression)
8. `bash tests/coder-workspace/startup-script.sh` again (C06 AC2: 43 checks)
9. `bash tests/coder-workspace/startup-sso-behavior.sh` (C06 AC3; needs dash,
   a real git to delegate `config` to, and /tmp/opencode writable — stubs are
   self-generated, no network)
10. C06 AC7 where terraform resolves: `/home/coder/.local/bin/terraform
    init -backend=false && validate` on a scratch copy of kubernetes-hardened
    (FRICTION: both binaries off-PATH; capture exit codes without pipes).
