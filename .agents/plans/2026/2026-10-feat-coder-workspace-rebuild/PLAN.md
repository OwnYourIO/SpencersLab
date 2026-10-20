# PLAN: Rebuild the Coder workspace image + template restructure + shutdown convention
feature: 2026/2026-10-feat-coder-workspace-rebuild

## Goal
Rebuild `containers/coder-workspace` as a digest-pinned Debian 13 slim image (no pbir bits, plus the official Forgejo CLI `fj`, better comments) with full Renovate coverage for every pinned artifact. Restructure the Coder templates: move the existing one unchanged into `coder-templates/kubernetes/` and add a new `coder-templates/kubernetes-hardened/` (restricted PSS, the rebuilt image, baked startup contract) with Coder's native per-workspace TTL as the shutdown mechanism, defaulted to 1 week.

## Out of scope
- Pushing templates to the Coder server (`coder templates push`) and setting workspaces' TTLs — user-owned, documented per chunk.
- Building the image locally: no docker daemon in this environment; PR CI (`docker-build.yaml`) builds (never pushes on PRs) — local gates are structural.
- Any behavior change to the moved `kubernetes` template (it keeps `codercom/enterprise-base:ubuntu`, sudo, runtime installs, kilo, `prevent_destroy=true`).
- Per-workspace `shutdown_time` coder_parameter: superseded by Coder's native TTL (verified 2026-10-18, see DECISIONS #10 — the agent token cannot set TTLs).
- Bumping image tags or chart versions by hand (release.yaml / docker-build.yaml own that).

## Commands (all runnable in THIS environment)
- helm lint: `/home/coder/.local/bin/helm lint charts/coder`
- helm render: `/home/coder/.local/bin/helm template charts/coder`
- chart packaging guard (coder-templates must stay out of the published tgz):
  `rm -rf /tmp/opencode/helm-pkg && /home/coder/.local/bin/helm package charts/coder -d /tmp/opencode/helm-pkg >/dev/null && tar -tzf /tmp/opencode/helm-pkg/coder-*.tgz | grep -c 'coder-templates/' ;` expected: `0`
- shell syntax: `bash -n containers/coder-workspace/workspace-startup.sh`
- structural tests: `bash tests/coder-workspace/*.sh` (the test agent writes these; `renovate.json` has `ignoreTests: true`, so `tests/` is renovate-safe)
- renovate config schema:
  `export NVM_DIR=/home/coder/.nvm && . $NVM_DIR/nvm.sh >/dev/null 2>&1 && nvm use 24 >/dev/null 2>&1 && node /home/coder/.npm/_npx/c2637f3b1963bb95/node_modules/renovate/dist/config-validator.js renovate.json`
  (npx-cached renovate 44.115.13; a re2 module warning is non-fatal)
- terraform validate (scratch copy — never `init` inside the repo; `.terraform/` must not be committed):
  ```
  export TF_PLUGIN_CACHE_DIR=/tmp/opencode/tfbin/plugin-cache
  rm -rf /tmp/opencode/tf-validate-<tmpl> && mkdir -p /tmp/opencode/tf-validate-<tmpl>
  cp charts/coder/coder-templates/<tmpl>/main.tf /tmp/opencode/tf-validate-<tmpl>/
  cd /tmp/opencode/tf-validate-<tmpl>
  /tmp/opencode/tfbin/terraform init -backend=false -input=false && /tmp/opencode/tfbin/terraform validate
  ```
  (terraform 1.9.8 binary + provider cache verified working here on 2026-10-18)
- quality gate: `npx --yes aislop@0.18.1 ci containers/coder-workspace` (may report 0 files scanned — a legitimate no-op for this repo; record it)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Rebuild coder-workspace image (Dockerfile + startup script) | M | 1 | [] | |
| C02 | Renovate coverage for every pinned artifact | M | 2 | [C01] | data: the custom-manager regex + extraction tests run against C01's final Dockerfile text (comment/ARG contract) |
| C03 | Move existing template to `coder-templates/kubernetes/` (pure move) | S | 2 | [] | independent of C01/C02 — a `git mv` of untouched files |
| C04 | New `coder-templates/kubernetes-hardened/` template | M | 3 | [C01, C03] | interface: startup contract (`/usr/local/bin/workspace-startup.sh`, image ref, env names) is defined by C01's image; layout: the `kubernetes/` move (C03) must land first so the folder-per-template convention and paths are unambiguous |

C02 and C03 are independent of each other (wave 2 runs them in id order).

## Wave order
1. C01
2. C02, C03 (independent; run in id order)
3. C04

## Risks / assumptions
- No docker daemon here: the image's build proof is PR CI; if a C01 structural gap survives review, it surfaces as a red PR build. Keep C01's assertions (version tests, checksums) tight.
- `fj` sha256 is hardcoded (upstream publishes no checksum file): a renovate bump of `FJ_VERSION` fails the build until the hash is recomputed — deliberate, documented in the Dockerfile.
- Definitive proof that every renovate datasource resolves = the lab's own Renovate run after merge (user verifies); local gates are schema + regex-extraction tests (MCP `global-renovate` cannot see this filesystem — see friction.md).
- kubectl is pinned to the cluster minor (v1.36.x, k3s v1.36.5+k3s1) and helm to the v3 line via `packageRules` — a cluster upgrade must update both pins together.
- The hardened template's `prevent_destroy` is OFF (user decision): deleting a workspace deletes its home PVC. Documented in the template header.
- Autostop is a user-owned convention (1 week via `coder create --stop-after 168h` or the UI Schedule tab); nothing in the repo enforces it. The template header documents the supported durations (9h / 24h / 168h / 720h = 30-day Coder cap / manual = never).
