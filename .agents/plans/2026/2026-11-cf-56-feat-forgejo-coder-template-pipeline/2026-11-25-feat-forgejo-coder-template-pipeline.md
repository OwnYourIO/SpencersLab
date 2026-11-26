# PLAN: Forgejo pipeline for Coder templates
feature: 2026/2026-11-cf-56-feat-forgejo-coder-template-pipeline

## Goal
When a file under `charts/coder/coder-templates/**` changes on `main`, a Forgejo Actions
pipeline runs `coder templates push` for the changed template(s), deploying a new active
version to the Coder instance hosted by the executing Forgejo instance — endpoint from a
repo variable, token from a repo secret (the card's ask, the `main-sync.yaml`
instance-side doctrine: no URL or token literal in the file). The Coder CLI is baked
into the lab's job image `containers/forgejo-runner` (owner ruling, OQ3). Exactly one
var (`CODER_URL`) + one secret (`CODER_SESSION_TOKEN`) per instance (owner ruling,
OQ5 — "Just need to login and push the template"): every template input value comes
from the repo — `terraform.tfvars` per template + `main.tf` defaults — including
`namespace`, verified `default` on BOTH instances (both coderd releases sit in
`default`; the gpu `dev-shared` PVC is `default`; the dev git-auth secrets
`github-pat`/`forgejo-token` are `default`).

## Out of scope
- The user-owned `coder templates edit --default-ttl 168h` (2026-10-19 fusion plan) —
  the pipeline does not re-assert it (ruled OQ7).
- Server-side template deletion/rename — user action; the pipeline pushes tree names only (ruled OQ9).
- Bitwarden/ExternalSecret wiring — the card explicitly asks for the Forgejo vault
  (the CI-side twin of the in-cluster pattern).
- Chart/appset/proxy changes — the Coder instances already exist; this is CI-side only.
  The `charts/forgejo-runner` chart label pin is deliberately NOT a chunk task: the
  repo law is that no Renovate lane reads that pin — it is bumped by hand to the newest
  published calendar tag (AGENTS.md), and that bump is a runbook owner leg (UA4).
- Local `docker build` of the runner image — no daemon in agent sessions; the merge
  fire's `build-containers.yaml` run (called by `main-sync.yaml`'s prod-main fan, r5)
  is the authoritative build (designed gate shape, cf-77 ruling 2026-10-28).

## Commands (all runnable in THIS environment)
- helm lint: `export PATH=$HOME/.local/bin:$PATH && helm lint charts/coder`
- helm render: `export PATH=$HOME/.local/bin:$PATH && helm template charts/coder`
- chart packaging guard (coder-templates must stay out of the published tgz):
  `export PATH=$HOME/.local/bin:$PATH && helm dependency build charts/coder >/dev/null && rm -rf /tmp/opencode/helm-pkg && helm package charts/coder -d /tmp/opencode/helm-pkg >/dev/null && tar -tzf /tmp/opencode/helm-pkg/coder-*.tgz | grep -c 'coder-templates/'` — expected `0`
- shell syntax: `bash -n scripts/coder-template-detect.sh && bash -n scripts/coder-template-push.sh`
- workflow YAML parse: `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .forgejo/workflows/coder-template-push.yaml`
- test (structural suites): `bash tests/coder/coder-template-push.sh && bash tests/coder/coder-template-detect.sh && bash tests/coder/coder-template-push-script.sh && bash tests/containers/forgejo-runner.sh && bash tests/notes/coder-template-push-runbook.sh`
- C04 (2026-11-26 marker rework, fan shape — batched round 2 ruled) additions — rerun the five suites INCLUDING the extended legs: `tests/coder/coder-template-detect.sh` (the l-legs re-pinned for the r5-house `base=` echo + the d-legs: d20-analog called + marker + empty before → `base=marker` ahead of the die, d21-analog the call bootstrap tip-only + announce (never the push-payload die), d22-analog a real push + empty before + no marker still dies, marker==sha quiet re-run, the d18 "fallback == today" pin (push channels byte-for-byte + the call-channel bootstrap announce), the d19 unmasked git-128 propagation), `tests/coder/coder-template-push.sh` (the w-legs + the 7-line re-fence + the `on:`-shape leg (exactly `workflow_dispatch` + `workflow_call`, no push arm, the dispatch input byte-frozen) + the resolver-step-shape leg (the call-side gate) + the no-advance-job / zero-marker-push fence shape + the 8-shape behavioral warning-law shapes under the step-owned law), `tests/notes/coder-template-push-runbook.sh` (re-pinned: the §2 reword, the fan-story note (no own-marker bootstrap; the dev-side dispatch leg), the asymmetry lines reworded to the 10-poller-pod topology (D57), the `build-charts.yaml`/`build-containers.yaml` needles, the UA1–UA5 set); the cross-ticket service-suite gates: `bash tests/services/forgejo-ci-surface.sh` must PASS on this branch (FJ_SET the six-workflow family — OQ14 full heal, ruled; t8's red state resolves from the 20-line re-fence in the same commit set — the D50.3 pairing; its teeth byte-identical), `bash tests/services/forgejo-main-sync.sh` re-pinned (t3 exactly seven jobs, t14 the three called builders, t15 the aggregate needs exactly the three builders + the no-result-function law, t17 the D59 truth table + the coder row), `bash tests/services/forgejo-build-containers.sh` re-pinned (t16 allow-set gains `coder-template-push.yaml`; the `writers == {'main-sync.yaml'}` check untouched) + re-run as regression parity; `bash -n` the changed scripts; the workflow YAML parse. **No new image/chart legs**: C04 touches no `containers/` or `charts/` file — the hadolint / helm lint+template / packaging-guard / terraform-validate legs carry over UNCHANGED and are recorded as such in `commands_run` (the terraform-validate smoke is skipped on the "no template files touched" ground, the C03 precedent).
- hadolint (Dockerfile contract, error threshold): `~/.local/bin/hadolint --failure-threshold error containers/forgejo-runner/Dockerfile`
- smoke: terraform validate, scratch copy — never `init` inside the repo, for BOTH `kubernetes` and `kubernetes-hardened` (verified working in-session 2026-11-25):
  `export PATH=$HOME/.local/bin:$PATH && export TF_PLUGIN_CACHE_DIR=/tmp/opencode/tf-plugin-cache && rm -rf /tmp/opencode/tf-validate-<tmpl> && mkdir -p /tmp/opencode/tf-validate-<tmpl> && cp charts/coder/coder-templates/<tmpl>/main.tf /tmp/opencode/tf-validate-<tmpl>/ && (cd /tmp/opencode/tf-validate-<tmpl> && terraform init -backend=false -input=false && terraform validate)`
- quality gate (aislop 0.18.1 accepts ONE path per invocation — the 4-argument form dies with "Expected 1 argument but got 4"): `npx --yes aislop@0.18.1 ci scripts/ && npx --yes aislop@0.18.1 ci .forgejo/ && npx --yes aislop@0.18.1 ci containers/forgejo-runner && npx --yes aislop@0.18.1 ci charts/coder/coder-templates` (record honest scope: 0.18.1 scores Python-class languages only — its `ci` runs on `.forgejo/` and the shell files return not-scored (0 files) by design; the workflow's substantive gate is its w1–w6 static suite, the Dockerfile's is hadolint, and the shell's is `bash -n` + the suites)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Bake the Coder CLI into `containers/forgejo-runner` (Dockerfile edit + existing suite extension) | M | 1 | [] | |
| C02 | Push engine: detect + push scripts, tfvars `namespace` supply, their suites | M | 1 | [] | independent of C01 — the scripts run inside the image at runtime; the fake-binary tests need no image |
| C03 | Workflow + owner-leg runbook + parity suites | M | 2 | [C01, C02] | data: the workflow invokes C02's scripts and relies on C01's baked CLI (the diag toolchain check); the runbook parity suite compares the runbook against the landed workflow + scripts + the image's label-pin leg |
| C04 | Marker adaptation (fan shape, batched round 2 ruled): the r5 called-run contract — `main-sync` fan entry + the shared `ci/last-built` marker law + step-owned warning law + the 20-line stale-ref sweep + the ci-surface/main-sync/build-containers suite legs (2026-11-26, the cf-55 r5 upstream law) | M | 3 | [C02, C03] | data: adapts the exact files C02/C03 landed (the detect script, the workflow, the runbook, the three suites) + the sanctioned cross-ticket surface (`main-sync.yaml` fan entry + the ci-surface suite heal) — both done, no open surface between them |

C01 and C02 are independent (wave 1 runs them in id order). C04 is the
2026-11-26 rework chunk (the r4 replan, then the r5 re-ground, then
the batched round 2 — ruled FAN MEMBER + shared `ci/last-built`) — it
adapts the landed C02/C03 artifacts to main's r5 marker law (the
called-run contract) and heals the cross-ticket service-suite red on
this branch (the sanctioned `main-sync.yaml` edit + the ci-surface
full heal); C01 is unaffected (post-merge regression 9 ok GREEN, the
UA3 pin facts re-verified).

## Wave order
1. C01, C02 (independent; run in id order)
2. C03
3. C04 (after C02 + C03 — adapts their landed artifacts; both done)

## Design (ruled — the batched plan-question round of 2026-11-25 settled every OQ)
- One endpoint per executing instance (OQ1 confirmed): instance-side repo var
  `CODER_URL` + repo secret `CODER_SESSION_TOKEN`; the dev instance pushes to its
  Coder, the prod-stage instance to its, each pushing the changed templates.
- Narrow-on-unset ROLE class, both role members (OQ2 confirmed): `if:
  contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')` (no null clause — the
  `build-charts.yaml` fail-safe class for external-service publishes).
- Trigger (OQ2 confirmed, OQ10 re-ruled 2026-11-26): `workflow_call` —
  a called run of `main-sync.yaml`'s prod-main fan (the fan's event
  scoping decides when we're called; the call is unconditional — no
  `with:` inputs, no path gate at the call site; path filtering lives
  in the `marker..sha` detection instead, the `build-containers.yaml`
  r5 contract) + `workflow_dispatch` with a `templates` escape-hatch
  input (byte-frozen beside `workflow_call` — the dev-side leg, the
  fan is prod-stage-instance only, ruled-accepted; the per-template
  escape hatch; dispatch never advances the shared marker). No PR leg
  (fork heads carry empty secrets; a PR would mint an active version).
- CLI acquisition (OQ3 RULED — owner override, supersedes the prior D2): the Coder CLI
  is baked into `containers/forgejo-runner` — a digest-pinned stage over the official
  `coder/coder` image (ghcr pull — the proven lane, the run-4 "change the source, not
  the path" posture), sha256-anchored per the repo's bump recipe, renovate-annotated
  like the existing helm/cr pins. The runner's calendar tag is hand-bumped (AGENTS.md
  law — no Renovate lane reads that pin; the chart label pin bump is a runbook owner
  leg). Rejected by the ruling: a separate `containers/coder-cli` image and run-time
  fetch (the D33 flaky-egress class).
- Jobs run on the lab's job image exactly as today: `runs-on: ubuntu-24.04` with no
  `container:` field — the same shape as the other four non-renovate workflows; the
  CLI is behind the label the labels already route to. The diag step's plain
  `coder version` call is the toolchain check (the D43 class).
- `CODER_SESSION_TOKEN` env name (OQ4 confirmed, supersedes D4's uncertainty): the
  script reads exactly `CODER_URL` + `CODER_SESSION_TOKEN`, token env-only, never argv
  (the `argocd-fanout.py` doctrine); the runbook verifies auth with `coder whoami`
  before first use.
- Minimal vault (OQ5 RULED, supersedes D5): exactly one var + one secret. Template
  input values come from the repo — `terraform.tfvars` (auto-loaded on push) +
  `main.tf` defaults. Verified against the actual template files: the ONLY required
  variable without a repo-side value in both templates is `namespace` (required, no
  default, absent from tfvars today); every other variable has a `main.tf` default,
  and the three version pins already live in `kubernetes/terraform.tfvars`.
  `namespace = "default"` is valid for BOTH instances (coderd `default` on dev AND gpu;
  the gpu `dev-shared` PVC unnamespaced → `default`; the dev git-auth secrets
  `default` — the hardened template's own header requirement). Settled: C02 adds
  `namespace = "default"` to both templates' tfvars (the hardened one is created).
  The single residual mechanism, documented as a runbook answer, not a question: if an
  instance's workspace namespace ever diverges from coderd's, one `--var
  namespace=...` from one instance-side var is the whole fix.
- Token lifetime (OQ6 confirmed): mint at the server's max allowed lifetime (the
  30-day default is a monthly-401 trap); rotate by vault overwrite.
- `--default-ttl 168h` NOT re-asserted (OQ7 confirmed); rename/delete not mirrored
  (OQ9 confirmed); the prior OQ8 retags onto the forgejo-runner calendar-tag story —
  the runbook's verify-the-published-tag leg (UA4).
- Push semantics: `-y --ignore-lockfile --name <short-sha> --message "forgejo <event>
  <sha>"`; `--activate` default true = the card's "deploy on change". A detection job
  (modeled on `scripts/forgejo-container-detect.sh`) limits pushes to the templates
  that actually changed — every push mints a version (EXPLORE gotcha 7), so unchanged
  siblings must not churn.
- Exit posture (the `main-sync.yaml` doctrine): unconfigured instance (URL or token
  absent) → `::warning::` + skip green; a configured 401/auth failure → red; per-template
  isolation via `fail-fast: false` matrix.

## Rulings (settled in the batched plan-question round, 2026-11-25 — recorded in DECISIONS.md)
| # | Question | Ruling | Plan effect |
|---|----------|--------|-------------|
| OQ1 | Push target | Confirmed: per-instance, both Coders; each executing Forgejo pushes every changed template to its own instance | instance-side `CODER_URL`/`CODER_SESSION_TOKEN`, both instances fire |
| OQ2 | Trigger + ROLE class | Confirmed: main-push + paths filter + dispatch escape hatch; narrow-on-unset `contains(vars.ROLE,'dev') \|\| contains(vars.ROLE,'prod')`; no PR leg | the workflow trigger/guard shape |
| OQ3 | CLI acquisition | RULED: bake into `containers/forgejo-runner` (supersedes D2) | C01 re-scoped to the runner Dockerfile edit; the hand-bumped chart label pin becomes a runbook owner leg; the image-rebuild-before-first-push sequencing lands in UA4 + Risks |
| OQ4 | Token env name | Confirmed: `CODER_SESSION_TOKEN` (+ `CODER_URL`); runbook verifies with `coder whoami` | the script's env contract |
| OQ5 | Vault minimalism | RULED: exactly one var + one secret; values from in-repo tfvars/templates (supersedes D5) | the four value vars dropped; `namespace = "default"` added to both templates' tfvars (verified both instances) |
| OQ6 | Token lifetime | Confirmed: server max lifetime; rotate by vault overwrite | runbook UA1/UA2 |
| OQ7 | `--default-ttl 168h` | Confirmed: stays user-owned, not re-asserted | runbook posture |
| OQ8 | coder-cli first tag | Moot as posed (no coder-cli image) — folded into the forgejo-runner calendar-tag story | runbook UA4 verify-the-published-tag leg |
| OQ9 | Rename/delete | Confirmed: not mirrored | runbook posture |

## C04 — marker adaptation (2026-11-26 r5 re-ground; batched round 2 ANSWERED — the rulings are recorded in DECISIONS.md and pin the plan)

The catch-up merge `01d2e3f45` (2026-11-26) carried main's r5 law
(cf-55 C14/C15) into this branch: `containers-build.yaml` is RENAMED
`build-containers.yaml` and its push arm DIED (C15) — it is now a
`workflow_call` CALLED run from `main-sync.yaml`'s prod-main fan, whose
AGGREGATE `advance-marker` job advances the SHARED `ci/last-built`
marker once the whole fan's builders publish green (D54 — a per-builder
advance on a shared multi-owner ref is structurally poisoned; the
advance CLASSIFIES a non-FF refusal: already-advanced = skip-green,
diverged = red); a called run with no marker narrows tip-only and
announces; the detect script re-ordered marker-first + gained the call
bootstrap arm; the empty-set warning is step-owned in the workflow
(`:210-216`, marker-aware); `release.yaml` is `build-charts.yaml`.
Owner instruction (standing): "Checkout containers-build.yaml for how it
works there and adapt for coder templates if not already done" — the
landed C02 detector models the OLD shape, so the adaptation is the
directive. The batched round 2 (2026-11-26, r5 shapes — DECISIONS.md
'batched round 2 — owner rulings, r5 shapes' is authoritative) ANSWERED
OQ10–OQ14: **OQ10 RULED FAN MEMBER** (supersedes the standalone best
guess, D19), **OQ11 RULED SHARE `ci/last-built`** (supersedes the own-
ref best guess, D20 — no own ref, no own advance), OQ12 confirmed step-
owned, OQ13 confirmed short note + D57 topology + UA3 re-verified, OQ14
confirmed FULL HEAL; the cross-ticket surface (C04 edits
`main-sync.yaml` + the ci-surface suite) is explicitly sanctioned by
owner choice. Grounding: `EXPLORE.md` Round 3 (L801–1386 — R3-Q1..Q6
+ the r5 mirror shapes), verified in-session against the r5 files. C01
is unaffected — the marker work touches no image/chart surface (no new
image, no new pin, no new secret); post-merge regression 9 ok GREEN,
the bake byte-intact, the UA3 pin facts re-verified (D22). The 2026-11-
25 OQ1–OQ9 rulings stand unchanged EXCEPT the automation-reach part of
OQ1 (the fan is prod-stage-instance only — the dev Coder is not
auto-covered; the dev-side pushes ride the `workflow_dispatch` hatch,
ruled-accepted — the per-instance ENDPOINT story is untouched).

The ruled shape (OQ10 fan member, OQ11 shared ref — the D55 pre-built
room, "card #56 owns it"): the `coder-template-push.yaml` workflow
RETIRES its own `push:` trigger arm (the build-containers r5 contract —
head `:110-113`: "the push arm died … main-sync.yaml calls this
workflow on its prod-main fan; path filtering lives in the marker..sha
detection instead. PR and dispatch lanes stay byte-frozen") and joins
`main-sync.yaml`'s prod-main fan as a `workflow_call` called run.
Verified call contract (the paths-filter question, settled from the r5
files): the fan calls **unconditionally** — `main-sync.yaml:105-111`
(`build-containers`) and `:113-119` (`build-charts`) are
`if: contains(vars.ROLE, 'prod')` + `runs-on: ubuntu-24.04` + `uses:` +
`secrets: inherit`, with NO `with:` inputs and NO path gate at the call
site (R3-Q1: "the called workflows need none — their detection reads
the event payload + the marker") — so our detect job does the
`charts/coder/coder-templates/` path work over `marker..sha`, and a
called run whose filtered set is empty of coder-templates is the
designed informational no-op (the verified-empty info line, green — it
never blocks the fan's aggregate advance; a RED coder leg blocks it —
the needs-gate, the coupling accepted by the ruling; a red SIBLING
holds the shared marker and the next fan re-covers all three domains —
the law's designed behavior, D54/D55). The `workflow_dispatch` hatch
stays byte-frozen beside `workflow_call` (the build-containers r5
shape) — it is the **DEV-SIDE leg** (the fan runs on the prod-stage
instance only — the stranding consequence, ruled-accepted: the runbook
states the manual dispatch loud) and the per-template escape hatch; a
dispatch never advances the shared marker (the fan law — main-sync's
aggregate is the single writer). We mint no commits (the D53 bump-tail
does not apply). The cross-ticket surface is sanctioned: C04 edits
`main-sync.yaml` (the fan entry + the `advance-marker` needs list) and
the ci-surface suite — cf-55/cf-139 territory by ownership, ruled here
by explicit owner choice.

Design (pinned to the r5 law, the RULED fan shape — full detail in
`chunks/C04.md`):
- The script re-pins to the r5 VERBATIM decision tree (the
  `forgejo-container-detect.sh:56-99` shape — the standalone delta is
  retired): the dispatch arm first (list parse, both gates — unchanged)
  → **`MARKER_SHA` non-empty wins** (`a="$MARKER_SHA"`,
  `b="${SHA:-HEAD}"`, `base_src='marker'`) — FIRST, ahead of the
  payload die (a called run's empty `before` is EXPECTED — called runs
  carry no push payload; that is the whole reason for the reorder) →
  **NEW — `event == workflow_call` + no marker → tip-only
  `HEAD^..HEAD` + the announced `::warning::` line** (the call
  bootstrap arm — the bootstrap state: "With no marker yet (the
  bootstrap state, and every state until main-sync's aggregate first
  advances it) a called run narrows to the tip commit and announces
  it", `build-containers.yaml:57-62`) → empty `before` → `die`
  (**scoped to real pushes** — a v15.0.10 push payload always carries
  `before`; the die stays as the defensive contract even though our
  `on:` block carries no push trigger) → all-zero `before` → tip-only
  + `::warning::` (defensive — reachable only via a real push arm) →
  otherwise `before..sha` (`base_src='before'`). The echo is the r5
  house form (upstream `:107-108`): `detect: range %s..%s (event
  %s${base_src:+, base=$base_src})` — the push/call arm names
  `base=marker|tip-only|before`, the dispatch arm echoes no range. The
  header's `MARKER_SHA` doc carries the call-aware posture (upstream
  `:11-17`); the event vocabulary is `push|workflow_call|
  workflow_dispatch` (the upstream four-event vocabulary minus the PR
  arm — the OQ2 ruling; no PR key anywhere). An empty `MARKER_SHA`
  reproduces C02's shipped behavior **byte-for-byte on the push
  channels** (the d18 "fallback == today" pin — die/all-zero
  tip-only/`before..sha`) and answers the announced tip-only on the
  call channel (the new bootstrap arm) — merge-order-independent-safe:
  the code lands before the marker exists; main-sync's first green fan
  creates it.
- The workflow re-pins to the called-run contract: the `on:` block
  RETIRES the `push:` arm and gains `workflow_call: {}` — `on:` is
  exactly `{workflow_dispatch, workflow_call}` (no PR arm, OQ2), with
  the `templates` dispatch input BYTE-FROZEN (the named rebuild hatch —
  the dev-side leg + the per-template escape hatch; dispatch never
  advances the shared marker, the fan law); `concurrency: cancel-
  in-progress: false` survives (the build-containers `:115-116` shape).
  The `resolve last-pushed marker` step, `id: marker`, inside
  `detect-changes` BEFORE the detect step — the upstream
  `build-containers.yaml:143-176` shape verbatim, gate `if [
  "$EVENT_NAME" != workflow_call ]`: non-call events emit empty `sha=`
  and exit 0 (a missing output key would reach the script *unset*
  rather than empty; empty `MARKER_SHA` is exactly the state the
  payload arms are specified against; a dispatch never reads the
  marker); `marker=$(git ls-remote origin refs/heads/ci/last-built |
  cut -f1)` — the SHARED ref (OQ11 ruling; no own ref); empty (ref
  absent) → empty `sha=` + exit 0 (the bootstrap fallback — "No marker
  yet: the before-chain answers, and main-sync's first aggregate green
  advance creates it"); non-40-hex → fail naming the value; `git cat-
  file -e "$marker^{commit}"` unreachable (orphaned) → `exit 1` with
  the reset-or-delete owner verbs (a silent downgrade is refused). The
  detect step gains the 5th env accessor `MARKER_SHA: ${{ steps.
  marker.outputs.sha }}` and the verdict echo names `marker=` (the
  `:197` shape); the existing `fetch-depth: 0` checkout already covers
  the resolver's reachability check. **NO `advance-marker` job in our
  file** (retired — main-sync's aggregate is the single marker writer,
  the D54 poison ruling; the upstream t16 fence shape: no `advance`-
  named job in the builder, zero `git push` statements naming the
  marker ref in the file — we are a READER, like `build-charts.yaml`).
- The fan entry (the sanctioned cross-ticket edit, `main-sync.yaml`):
  a `push-coder-templates` job (the name follows the house pattern —
  `push-gh`/`push-dev` are push verbs, the builders are `build-*`, we
  publish; one-string veto slot) byte-pinned to the sibling shape
  (`main-sync.yaml:105-111`/`:113-119`): `if: contains(vars.ROLE,
  'prod')`, `runs-on: ubuntu-24.04`, `uses: ./.forgejo/workflows/
  coder-template-push.yaml`, `secrets: inherit`, NO `with:` inputs.
  The `advance-marker` job's `needs` GAINS `push-coder-templates` (the
  plain `needs`-gate IS the green-fire rule — no result function, the
  D59 override; a red fan leaves the marker put, so the next fan's
  `marker..sha` range still carries the failed work — the re-cover law;
  the coupling accepted by the ruling: our red blocks the aggregate's
  advance, a red sibling holds the shared marker → the next fan re-
  covers all three domains). `sync-fanout`'s `needs` is UNCHANGED —
  the fleet release must not hold over an external-service publish
  (D59's hard gate is about the registry releases; the D55 room names
  exactly "one `uses:` job + one `advance-marker` needs entry"). The
  aggregate's target rule already handles a builder with no outputs
  (the event-sha fallback, D55) — we mint no commits.
- Empty/warning/exemption semantics align to the step-owned law (OQ12
  confirmed): the empty-set decision lives in the detect step, marker-
  aware (the `build-containers.yaml:210-216` shape minus the PR
  branch): a called run (or defensive push) with a PRESENT marker +
  empty set → one plain info line (the marker *proves* nothing was
  missed; no `::warning::`, no `::notice::` — the runner does not
  interpret it — the designed informational no-op that never blocks the
  aggregate); no-op `before == sha` + ANY dispatch (the all-ungated-
  list C02 warning retires — dispatch exempt wholesale, the upstream
  law) stay silent; a real empty `before..sha` (no marker, `before !=
  sha`) → `::warning::` (defensive); a called run with no marker is
  silent at step level (the script's bootstrap ANNOUNCE is the
  signal); the two tip-only announces stay in the script (the script's
  only warnings); an orphaned marker fails loud (the reset-or-delete
  owner verb); an unreachable one propagates git 128 through the
  unmasked diff.
- The 20-line stale-ref sweep (D24) in ONE change set with the ci-
  surface suite heal (OQ14 FULL HEAL, ruled): the workflow's 7 lines
  (L9, L11, L25, L102, L119, L180, L188) → `build-containers.yaml`/
  `build-charts.yaml`; the w-suite's 7 (L113, L115, L121, L158, L165,
  L187, L337); the runbook's 6 (L47, L50, L67, L81, L166, L276) — the
  r5 rename + the release-era rename re-fenced in the SAME commit set
  as the heal, so the cross-ticket suite goes green on this branch
  (its t8 teeth are token-based; FJ_SET re-aims to the six-workflow
  family naming `coder-template-push.yaml`). Plus the `Detection.` +
  `Trigger.` header paragraph reword to the FAN story (the build-
  containers `:110-113` head idiom — the push arm died, the fan calls
  us, path filtering lives in the `marker..sha` detection, the
  dispatch hatch byte-frozen as the dev-side leg + escape hatch; the
  `main-sync.yaml:105-119` fan-entry citations for the unconditional-
  call / no-`with:` / no-path-gate law), the script doc header, the
  runbook §2 detection text (the x5-parity shape), and the
  `concurrency` comment reword to the r5 runner topology (10 poller
  pods × capacity-1, D57).
- The runbook (OQ13 confirmed) — the marker story becomes the FAN
  story: NO own-marker bootstrap (the shared `ci/last-built` is
  advanced by main-sync's aggregate alone, once all three builders are
  green; the pre-state — `ci/last-built` not yet live, only
  `ci/containers-built` exists, the UA-R5-1/UA-R5-2 pre-steps are
  owner-side — means every called run before the first green fan is
  the announced tip-only; the templates are already live, no full-
  fleet legs; no new secret — the fan's advance rides main-sync's
  credential, never ours) + the DEV-SIDE DISPATCH LEG STATED LOUD (the
  fan is prod-stage-instance only — the dev Coder is not auto-
  covered, ruled-accepted: HOW — a `workflow_dispatch` on the dev
  instance with the `templates` input naming the template(s); WHEN —
  post-merge (the migration leg) and on every template edit that must
  reach the dev Coder; and THAT a dispatch does not advance the shared
  marker per the fan law — the aggregate is the single writer) + the
  NAMED ASYMMETRIES reworded to the r5 topology (the Risks below,
  incl. the re-cover law: a mixed-outcome fan re-covers all three
  domains next fire — a green leg re-pushes its range, re-minting
  versions — churn, no correctness loss) + the UA3 pin facts re-
  verified post-merge (D22) + a NEW owner leg (UA5 — the fan-shape
  migration leg: verify the first `main-sync` fan fire includes our
  called job green AND run the post-merge dev-side dispatch to catch
  the dev Coder up to the tree state).
- The suite heal + parity legs (the test wave lands before dev; suite
  bytes test-session-owned): the ci-surface FULL HEAL (OQ14 — FJ_SET
  six + t1 prose; t8 green via the same-commit re-fence, its teeth
  byte-identical) + the `forgejo-main-sync.sh` re-pin (t3 exactly
  SEVEN jobs, t14 the three CALLED builder jobs, t15 the aggregate
  `needs` exactly the three builders + the no-result-function law,
  t17 the D59 truth table + the coder row: a red coder leg skips the
  aggregate but does NOT skip `sync-fanout` — it is not in that
  needs) + the `forgejo-build-containers.sh` t16 re-pin (the allow-set
  GAINS `coder-template-push.yaml` — "a new builder joins the set in
  its own commit (card #56), it does not route around this leg"; the
  `writers == {'main-sync.yaml'}` check is untouched — we are a
  reader, zero marker pushes in our file).

| # | Question | Ruling (2026-11-26 round 2, DECISIONS.md) | Plan effect |
|---|----------|---------------------------------------------|-------------|
| OQ10 | C04 shape | **RULED FAN MEMBER** (overrides the standalone best guess): the workflow joins main-sync's prod-main fan as a `workflow_call` run — own push arm retired, marker-first + call-bootstrap arms, advance job retired (main-sync's aggregate is the single marker writer). Accepted consequence, spelled and ruled anyway: the fan is prod-stage-instance only — automated coverage is the gpu Coder; DEV-SIDE pushes ride the `workflow_dispatch` hatch (manual leg — the runbook states it). Supersedes OQ1's automation reach, not its per-instance endpoint story | the fan-shape C04 (this section); the runbook's dev-side dispatch leg + UA5 |
| OQ11 | Marker ref | **RULED SHARE `ci/last-built`**: one shared per-repo-per-instance marker ref, read `marker..sha` on called runs, NO own ref, NO own advance. Coupling accepted: a red coder leg blocks the aggregate's advance (needs-gate); a red sibling holds the marker (re-covered next fan — the law's designed behavior). Remote pre-state noted: `ci/last-built` not yet live (the first green fan creates it); only `ci/containers-built` exists | the resolver reads the shared ref; no advance job in our file; the t16 allow-set join lands in our commit via the test session |
| OQ12 | Warning-law location | **Confirmed step-owned** (retire the C03 inversion) | the `:210-216` shape minus the PR branch, in the detect step; the 8-shape behavioral legs |
| OQ13 | Runbook note scope | **Confirmed short note** + asymmetries reworded to D57 topology + UA3 re-verified (the four `:26.11.1` pins intact; the C01 suite 9 ok green post-merge) | the fan-story note (no own-marker bootstrap; the dev-side dispatch leg loud); the fan shape adds ONE UA leg — UA5, the migration leg (the first-fan-fire watch incl. our called job green + the post-merge dev-side dispatch catch-up) |
| OQ14 | The ci-surface suite heal scope | **Confirmed FULL HEAL in C04** of `tests/services/forgejo-ci-surface.sh` (FJ_SET six-workflow re-aim + t1 prose; t8 green via the same-commit stale-ref re-fence; the D50.3 pairing; suite bytes test-session-owned) | the heal task + the cross-ticket gate; the main-sync + build-containers suite parity legs land with it |

## Risks / assumptions
- SEQUENCING (the OQ3-ruling consequence): the runner image rebuild (merge →
  `build-containers.yaml` (the `main-sync` fan call) → new calendar tag) AND the owner's hand bump of the
  `charts/forgejo-runner` chart label pin (the four act-label lines, AGENTS.md law —
  no Renovate lane reads that pin) must land BEFORE the first template push fires —
  otherwise the first fire runs on the pre-bake image and dies at the `coder version`
  diag. The runbook's UA4 + UA5 own this; a first-fire `command not found: coder` is
  a sequencing state, not a pipeline bug.
- Runner egress has a history of targeted upstream filters (D33, `get.helm.sh`): the
  image BUILD pulls the `coder/coder` stage over the ghcr lane (proven); the
  runner→coder-host API call at push time is an assumption — the runbook's first-fire
  watch (UA5) covers it, and a red 401/network failure is loud by design.
- `terraform validate` here needs egress to registry.terraform.io (verified
  2026-11-25); the test suites themselves are offline (house shape) — validate is a
  plan/dev smoke. The tfvars edit changes what a push RESOLVES (namespace becomes a
  persisted resolved value instead of a workspace-creation prompt) — that is the
  intended GitOS-ification of the value, verified `default` on both instances.
- Every push mints a version (gotcha 7) — the detection job is what keeps unchanged
  siblings from churning; a dispatch with an empty list is a designed no-op.
- No docker daemon in agent sessions: the runner-image build proof is the merge fire's
  `build-containers.yaml` run (the `main-sync` fan call); local gates are the static
  contract suite + hadolint + the container-creation skill's sanctioned GHCR layer-
  tar-listing verification of the binary path/digest.
- RE-RUN-LAW SHIFT (C04 — the fan-shape re-pin of the cf-6 accepted law):
  a re-fire of a *fully succeeded* fan run (the `main-sync` no-input
  `workflow_dispatch` re-fires the whole fan — the legitimate re-cover
  mechanism) now re-diffs `marker..sha` with the marker advanced ⇒
  empty verified-info-exit — it becomes a **verify, not a re-mint**:
  the re-fire no longer re-points the active version at identical
  content (no version re-minted). **User-visible on the Coder servers**
  (the version list stays put instead of gaining a duplicate entry).
  Failure-class re-fires keep the old behavior exactly (marker put ⇒
  same range ⇒ the same full set re-pushed, succeeded legs included —
  identical churn to today). The owner accepted it knowing (the round 2
  ruling confirms it as the acceptable price of fan membership).
- ACCEPTED COUPLING (the fan-shape consequence, ruled): a RED coder leg
  blocks the fan's aggregate advance (the plain `needs`-gate) — the
  shared marker stays put; a red SIBLING holds the shared marker, and
  the next fan re-covers ALL THREE domains (the D54/D55 re-cover law)
  — a green leg re-pushes its range (for us: re-minted versions — churn
  on the Coder version list, no correctness loss; a green leg that
  already published re-mints one extra version, the containers "same-
  tag republish is idempotent" analog). Both directions are the law's
  designed behavior, named in the runbook, not assumed harmless.
- STRANDING CONSEQUENCE (the fan-shape consequence, ruled-accepted):
  the fan runs on the PROD-STAGE instance only (the `main-sync`
  guard; the dev instance carries no marker) — the dev Coder is NOT
  auto-covered. Dev-side pushes ride the `workflow_dispatch` hatch on
  the dev instance (a manual leg — the runbook states it loud: how,
  when, and that a dispatch does not advance the shared marker per the
  fan law); UA5 owns the post-merge dev-side catch-up dispatch. A
  template edit that must reach the dev Coder before the next manual
  dispatch rides on the operator's judgment — named, not hidden.
- PRE-MIGRATION STATE (the remote pre-state, scout-verified):
  `ci/last-built` is NOT yet live (only `ci/containers-built` exists;
  the C14 migration pre-steps UA-R5-1/UA-R5-2 are owner-side) — the
  first green fan creates it. Until then EVERY called run is the
  announced tip-only bootstrap (the `build-containers.yaml:57-62`
  law); the dispatch leg is unaffected (it never reads the marker).
  Our landing is merge-order-independent-safe: the code can land
  before the ref exists — the pre-state is the designed bootstrap.
- STALE-QUEUED OVER-PUSH ASYMMETRY (C04, named in the runbook note): a
  queued run that over-runs the marker re-pushes the range's templates — a
  re-minted version with `--activate` re-pointing the ACTIVE version at the
  stale run's checked-out content. NOT the image-harmless re-mint class (gaps-
  by-design); a partial-failure re-run re-pushes every template in the range
  (re-minting versions, active re-pointed at identical content — churn on the
  Coder version list, no correctness loss). Under the 10-poller-pod × capacity-1
  runner + FIFO queue + `cancel-in-progress: false` the race is vanishing (per-
  pod serialization, D57 — the r5 topology reword, R3-Q5c), the marker is never
  rewound (the aggregate's non-FF refusal + the classify law, git-enforced),
  but the class is named, not assumed harmless.
- MARKER-WRITE is NOT OURS (C04 fan-shape): our workflow carries no
  marker write at all (the advance job retired — main-sync's aggregate is
  the single writer, the D54 poison ruling; the t16 fence shape: zero
  `git push` statements naming the marker ref in our file). The
  aggregate's non-main `refs/heads` push capability (near-proven, not
  proven per cf-6 OQ-2) is the FAN's own leg — cf-55's UA-R5-1/2 pre-
  steps + the first green fan's advance are its proof; the fallback
  (a repo-write-scoped minted PAT) is cf-55's, not a C04 surface.

## Human-owned (owner) legs — runbook, C03 + C04 (UA5)
UA1 mint a dev-Coder token (server max lifetime) → dev Forgejo repo secret
`CODER_SESSION_TOKEN` + repo var `CODER_URL`; UA2 the same for the gpu Coder on the
prod-stage Forgejo; UA3 verify the new `forgejo-runner` calendar tag is published and
hand-bump the chart label pin to it (the AGENTS.md law); UA4 watch the first fire
(a dispatch — the escape hatch / dev-side leg) + `coder whoami` / `coder templates
versions` check. C04 (the 2026-11-26 rework, FAN SHAPE — batched round 2 ruled)
adds ONE UA leg — UA5, the fan-shape migration leg: verify the first `main-sync`
fan fire includes our called job green (the prod-stage Coder is auto-covered from
the first green fan; a red sibling holds the shared marker — the next fan re-covers,
the accepted coupling) AND run the post-merge DEV-SIDE `workflow_dispatch` to catch
the dev Coder up to the tree state (the fan is prod-stage-instance only — the dev
Coder is not auto-covered, ruled-accepted; a dispatch does not advance the shared
`ci/last-built` marker per the fan law — the aggregate is the single writer). The
runbook's fan-story note is a short NON-leg note (no own-marker bootstrap — the
templates are already live; no new secret — the fan's advance rides main-sync's
credential, never ours). The UA3 pin facts are re-verified post-merge (D22: the
four `:26.11.1` label lines unchanged, the dev-slice list intact, the B1 comment
AMENDED; the C01 regression 9 ok GREEN).
