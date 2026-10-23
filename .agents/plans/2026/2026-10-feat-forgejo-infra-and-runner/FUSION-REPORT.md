# FUSION-REPORT — feat-forgejo-infra-and-runner (3 parallel runs)

Written by `agent-fuser` 2026-10-23. All claims below were re-verified from
live git state and by independently re-running every run's test suite on this
day — not taken from the runs' own summaries.

## Runs compared (user-confirmed set, 2026-10-23)

| tag | branch | ticket folder | commits (vs merge-base) | model |
|---|---|---|---|---|
| run 1 | `feat-forgejo-infra-and-dev-runner-3` | `2026/2026-10-feat-forgejo-infra-and-dev-runner/` | 26 (mb `abfbb6a2d`) | openrouter qwen3.8-flash |
| run 2 | `feat-forgejo-infra-and-runner-gpu-ai-qwen3-8-27b-q6-2` | `2026/2026-10-feat-forgejo-infra-and-runner/` | 6 (mb `b2aa2e4b2` — merged main into branch) | gpu-ai qwen3.8-27b q6/q4 |
| run 3 | `feat-forgejo-infra-and-runner-openrouter-qwen-qwen3-8-27b-1` | `2026/2026-10-feat-forgejo-infra-and-runner/` | 7 (mb `abfbb6a2d`) | openrouter qwen3.8-27b |

The three session-start branches `alright-so-we-recently-implemented-forgejo…/{1,2,3}`
sit at main's HEAD with zero commits — excluded by the user (nothing to fuse).

Independent validation on 2026-10-23 (fuser re-ran all suites from live code):
run 1 = 7 scripts, 142 checks, ALL PASS · run 2 = 3 scripts, 58 checks, ALL
PASS · run 3 = 3 scripts, 46 checks, ALL PASS.

## Planning quality across runs

**Run 1** — 4 chunks (C01 infra+gitea-cleanup / C02 proxy-local / C03 runner
chart / C04 dev wiring) with a hard research gate on the runner chunks,
explicit wave order with dependency rationale, 15 logged decisions (D1–D15,
7 user-flagged). Best-in-class STATE.json: every stage handoff recorded
verbatim; 2-round final review; every review re-ran validations independently.
Chunk acceptance criteria are concrete and render-verifiable; "User actions"
carry a complete Bitwarden item table incl. the runner's two-slot mechanism
(password=token, username=uuid). Weakest point: test scripts live at
`tests/c0N_*.sh` (root, chunk-named) instead of the repo's
`tests/services/<name>.sh` convention.

**Run 2** — 3 chunks, all wave 1; a clean question round (A1–A9, B1–B4, H1)
resolved BEFORE planning finished, so the plan went into dev with zero open
items. Only run that merged main into the branch (2 newer rulesync commits)
and only run that kept the STORM audit trail in the ticket folder. Weaker
STATE discipline (handoffs summarized, not verbatim); the plan's
sentinel-sweep command greps a non-existent root `values.yaml` (FRICTION-logged
typo the agents worked around). Notable planning strength: asked the user the
genuinely hard product questions (mailer on/off, chart parameterization,
StatefulSet vs Deployment, dind pin) instead of assuming.

**Run 3** — 4 chunks in 2 waves; good live-cluster plan findings (the
`<name>-cert` gap does NOT apply to plain subdomain entries — live-verified,
correcting a stale claim from the dev-plan handover). Good gate discipline:
three proven test-harness defects were routed back to the test session with
user confirmation rather than fixed by dev/review. Planning gaps: **missed the
hub forward-auth problem for git clients** (its C04 only retargets `git:` and
leaves the default crowdsec+userAuth chain, which 302s OIDC-less git clients —
runs 1 and 2 both got explicit user sign-off on crowdsec-only); plan text
references a non-existent `git.dev.scifi.farm` (dev's real host is
`git.scifi.farm`, verified in custom-values/dev); left the infra instance
displaying APP_NAME "SpencersLab Dev" (deferred as cosmetic).

Trust ranking: run 1 > run 2 > run 3 (rigor of plan/review trail and
survival of independent re-verification).

## Code differences between the branches

All three agree on the skeleton: `charts.forgejo` entry in
`services/infra/prod` (SSA "false", ns default), both hosts on infra's
generic-ingress → `infra-forgejo-http:3000`, 4× `OVERRIDE_NEEDED` infra
Bitwarden slots, gitea templates + `bitwardenIds.gitea*` deleted, new
`charts/forgejo-runner` v1.0.0 wired into `services/dev` with a documented
trio deviation. The deltas:

| Area | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| `charts/forgejo` | untouched (D1) | **parameterized** (A8): neutral APP_NAME/email, dev literals migrated to custom-values/dev, dev render byte-parity verified (878/878 lines) | untouched; infra shows "SpencersLab Dev" (deferred) |
| Infra mailer | deferred | **enabled** via `smtp-relay-mail`, FROM `git@spencerslab.com` (A6, service name live-verified) | absent |
| Infra ingress shape | one entry `git: {serviceName: forgejo}` → renders both hosts (template-verified; matches the old stub's own `serviceName:` intent) | two explicit entries | two explicit entries |
| proxy-local | `git` retargeted in place + `forgejo:` mirror, **both crowdsec-only** | `git` relocated to the crowdsec-only section + `forgejo:` entry, crowdsec-only | `git` retargeted **with default forward-auth chain** (breaks git-over-HTTPS); no forgejo entry |
| Runner chart | Deployment; hardened runner (uid 1000, drop ALL, RO rootfs) + privileged dind **sidecar container** over TLS tcp://127.0.0.1:2376 with nc-wait loop (caught a guaranteed crash-restart in review); static PVC templates 15Gi docker + 5Gi runner; grace 300; labels = catthehacker act images (GitHub parity); registers **dev instance only** | StatefulSet r=1; dind **sidecar initContainer** (`restartPolicy: Always`) over unix socket with socket probes; VCTs 2Gi+10Gi; grace 10800; config.yaml rendered in the ExternalSecret template; labels `node:lts` + `dev`; registers **dev instance only** | **Two** runner Deployments (dev + **infra registrations**); jobs as K8s pods via `runner-k8s-plugin` gRPC sidecar (alpha protocol); namespaced Roles; no privilege; third-party plugin registry + digest pins; rootful job pods (accepted) |
| Runner Bitwarden item(s) | `dev-forgejo-runner` + `runnerUuid` values slot | `forgejo-runner` (uuid flows through the ESO template) | `dev-forgejo-runner-dev` + `dev-forgejo-runner-infra` |
| dind pin | `docker:29.5.2-dind` | `docker:29.9.1-dind` (user-chosen B2) | n/a |
| Review-caught comment fixes | renovate-annotation mechanism corrected (built-in helm-values manager, dry-run-verified); dind-wait restored; runnerUuid-placement comment fixed | `.runner`-identity myth corrected (daemon never writes it; re-attach is via Bitwarden uuid+token); Keycloak-hosting claim fixed | podspec "non-root" claim fixed (rootful by image default) |

Verified fact that defuses one apparent conflict: external-dns does NOT run on
the infra cluster (no chart entry), so the infra-ingress label difference
between the one-entry and two-entry shapes is inert; the consequential
external-dns is proxy-local's, which all runs satisfy for both hosts.

## Research differences

All three runs commissioned `agent-research` (user-mandated) and converged on:
runner **v13.2.0** pinned, declarative `server.connections` registration (no
register CLI, no env-var registration), uuid+token pair in Bitwarden, no
maintained official chart → custom app-template chart, in-cluster URL viable,
tokens non-expiring.

Divergences:
- **Official chart existence**: run 1 live-probed
  `code.forgejo.org/forgejo-helm/forgejo-runner` (exists: v0.7.5 / appVersion
  12.7.3, zero tags, not OCI-published, hook-Job+kubectl RBAC) and rejected it
  on evidence. Runs 2 and 3 concluded "no official runner chart exists" —
  factually wrong, though immaterial (all three build custom).
- **Execution model**: runs 1 & 2 recommend privileged dind (run 1: upstream's
  own k8s example, TLS 2376, hardened runner, no SA/RBAC at all; run 2:
  gitea-example socket variant, sidecar initContainer). Run 3 recommends the
  **k8s plugin engine** (jobs as pods, namespaced Role, nothing
  resident-privileged), citing bjw-s home-ops as production precedent while
  acknowledging the protocol is **alpha** (plugin.v1alpha, no stability
  guarantees) and rides a third-party registry. Run 1's research explicitly
  weighed the plugin engine and rejected it as not production-grade. Both
  positions are defensible; this is a risk-appetite question, not an evidence
  question.
- **Registration scope**: runs 1/2 register only the dev instance (approved in
  those runs: D8/B3). Run 3 registers **both** instances from dev (approved in
  that run: global per instance), reading "the runner runs on dev, never moves
  to infra" as pod-location-only.
- Run 2's RESEARCH.md carries a known inaccuracy (`.runner`-file identity
  persistence) — formally corrected by a DECISIONS entry + fixed comments.
  Run 1's RESEARCH.md is the only one with a reliability self-rating and a
  resolved false-negative (dev cluster probe miss, re-proven by coord); it
  also uniquely captures the k3s MTU clone-failure warning
  (forgejo/runner#1779) and the ArgoCD-friendly timeout rationale (grace ≥
  shutdown_timeout but keep both short).

Best grounded: run 1's RESEARCH.md, with run 3's a close second on breadth
(different, complementary sources: bjw-s home-ops, plugin repos).

## Friction differences

Shared across all runs: helm off PATH (`~/.local/bin`); aislop vacuous for
YAML/MD diffs; code.forgejo.org Anubis bot-gating; PyYAML vs proxy-local's
duplicate `&port` anchors; app-template 5.0.1 subtree cannot see parent values
(no `common.yaml` loader).

Run-specific worth keeping: run 1 — global-renovate MCP unusable for local
worktrees (use the bundled renovate CLI recipe); dind readiness race (the
wait loop). Run 2 — ESO `template.data` entries must parse as YAML BEFORE
substitution (quote `{{ .uuid }}`); VCT schema is a list with singular
`accessMode`/`size`; `helm install --dry-run` unusable with readonly
kubeconfig. Run 3 — `<name>-cert` gap only applies to `domain:`-override hub
entries (live-verified); searxng parallel-search aborts.

Open items the fusion must respect: samba `samba-users OVERRIDE_NEEDED` wart
in the infra render (pre-existing; deferred by user ruling in runs 2/3); dev
node root-fs type check (`df -T /`) before DinD overlay2 (run 2 user action);
`services.infra.customValuesUrls` verified by inference only (run 2).

## Suggested base branch and why

The fuser suggested **run 1** (strongest plan/review discipline, most-verified
infra work, 142 green assertions, best research artifact). **The user chose
run 2 (`feat-forgejo-infra-and-runner-gpu-ai-qwen3-8-27b-q6-2`) as the base
instead** (2026-10-23, question tool) — it carries the user's own product
decisions (A8 chart parameterization, A6 mailer, B1 StatefulSet, B2 dind pin),
is closest to main, and its runner chart is the most self-contained. Port
candidates from the other branches (each subject to a user conflict ruling):
run 1's runner refinements (GitHub-parity label set, ArgoCD-friendly timeouts,
k3s-MTU warning), run 3's k8s-plugin execution model, run 3's
infra-instance registration.