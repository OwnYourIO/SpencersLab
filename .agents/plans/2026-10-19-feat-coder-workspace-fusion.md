# 2026-10-19 feat: fuse three coder-workspace rebuild attempts

## Task
Rebuild `containers/coder-workspace` on digest-pinned Debian slim (no pbir, plus
the Forgejo CLI `fj`, better comments), renovate coverage for every pin, move the
existing Coder template into `coder-templates/kubernetes/`, and add a merged
`kubernetes-hardened/` template with a settable workspace shutdown time
(9 hours / 1 day / 1 week / 1 month / never). Three parallel attempts were fused
into one result; per-attempt user decisions conflicted on a few points — rulings
are recorded in `.agents/plans/2026/2026-10-feat-coder-workspace-rebuild/DECISIONS.md`
("Fusion round").

## Base and ports
- **Base: attempt 1** (`f23b9e7`) — completed 4-chunk pipeline, all suites green,
  renovate enforcement proven against the real dist, pinned+checksummed
  code-server PVC install, shutdown options documented 1:1 with the task.
- **From attempt 3** (`80fcb8cc`): C05 git-auth wiring (forgejo-token
  ExternalSecret + values/custom-values pair + optional secretKeyRef env blocks +
  secret-github.yaml consumer comment + its 20-check test suite, ported to
  `tests/services/dev-git-auth.sh`); Dockerfile loud `rm` of the PEP 668 marker,
  npm identity assertion, gnupg/lsb-release dropped, `cd "${HOME}"` in the
  startup script; post-review template comment fixes (kubeconfig one-liner,
  metadata preamble and `//Coder-specific labels.` deleted, `:v<run>` pin-later
  note).
- **From attempt 2** (`a26b1731`): `SHELL` bash+pipefail for the version asserts,
  `npm install -g --ignore-scripts` + `npm cache clean --force`, exact
  `fj version | grep -qx`, pod `run_as_group = 1000`, `/tmp` emptyDir
  `size_limit = "2Gi"`; SSH-keygen/known_hosts/clone-loop machinery and the
  `repos` multi-select parameter (kept per user directive 2026-10-20).
- **Rejected**: attempt 2's baked-into-image code-server + JSONata sha co-update
  datasources (contradicts this folder's DECISIONS #22 PVC-install ruling and
  adds three JSONata datasources; the PVC install stays pinned+checksummed in
  the startup script); attempt 2's header edit to the moved kubernetes/main.tf
  (move stays pure R100); attempt 3's modification of the existing git-pin
  renovate manager (attempt 1's separate narrowed manager + allowedVersions
  enforcement kept — proven against the real renovate dist); @kilocode/cli
  (dropped in attempts 1 and 3 by user decision; absent from the reference
  artifacts).

## 2026-10-20 user corrections (supersede initial fusion rulings)
- Home PVC: explicit `lifecycle { prevent_destroy = false }` — deleting a
  workspace frees its home PVC (matches the reference artifact and attempt 1's
  original call). coder-hardened.sh asserts the explicit false.
- SSH key + clone machinery KEPT (attempt 2's implementation): startup script
  provisions one SSH key per PVC (public half repaired from the private one),
  pre-trusts git.scifi.farm + github.com in known_hosts, prints the pubkey
  banner into the boot log, and clones the template's `repos` selection
  (WORKSPACE_GIT_REPOS agent env, CODER_USER/CODER_USER_EMAIL git identity).
  Token auth stays alongside: SSH serves git@ URLs, tokens serve HTTPS.

## Changes (worktree, uncommitted)
- `containers/coder-workspace/Dockerfile` — debian:13-slim digest pin, ARG-pinned
  node/go/helm/kubectl/uv/fj/opencode/openchamber with vendor-channel checksums
  and build-time assertions, pipefail SHELL, --ignore-scripts npm, single
  hardcoded hash (FJ_SHA256), uid/gid 1000, no sudo, no ENTRYPOINT.
- `containers/coder-workspace/workspace-startup.sh` (new, 755) — skel seed,
  SSH key + known_hosts provisioning with pubkey banner, OpenCode :4096 +
  OpenChamber :3000, env-driven GitHub/Forgejo token auth (+ `fj auth
  add-token`), git identity + clone loop for the `repos` parameter, pinned
  code-server v4.141.0 install into the PVC (sha256-verified), all writes to
  PVC//tmp.
- `renovate.json` — new custom manager for `containers/*/Dockerfile`
  (node-version|golang-version|forgejo-releases|npm, disjoint from the existing
  git-pin manager) + packageRules holding helm to v3 and kubectl to v1.36 via
  slash-wrapped `allowedVersions`.
- `charts/coder/coder-templates/{main.tf,terraform.tfvars}` →
  `kubernetes/` — pure R100 renames.
- `charts/coder/coder-templates/kubernetes-hardened/main.tf` (new) — merged
  template: restricted PSS, baked-image startup contract, shared PVC, git-auth
  env, `repos` multi-select + WORKSPACE_GIT_REPOS/CODER_USER agent env,
  explicit `prevent_destroy = false`, SHUTDOWN header (template
  `--default-ttl 168h` + per-workspace 9h/24h/168h/720h/manual).
- `services/dev/prod/templates/secret-forgejo-token.yaml` (new),
  `services/dev/prod/values.yaml`, `custom-values/dev/prod-values.yaml`,
  `services/dev/prod/templates/secret-github.yaml` — ExternalSecret + Bitwarden
  trio, real UUID only in custom-values.
- `tests/` (6 suites) + feature folder `.agents/plans/2026/2026-10-feat-coder-workspace-rebuild/`.

## Validation (all run in this worktree)
- `bash tests/coder-workspace/image-structure.sh` → 46/46
- `bash tests/coder-workspace/startup-script.sh` → 20/20
- `bash tests/renovate/dockerfile-pins.sh` → 8/8
- `bash tests/templates/coder-move.sh` → 10/10 (incl. scratch terraform validate)
- `bash tests/templates/coder-hardened.sh` → 40/40 (incl. terraform init+validate
  of the fused template, helm package guard: 0 coder-templates/ entries, lint, template)
- `bash tests/services/dev-git-auth.sh` → 20 ok (incl. both helm renders of the
  dev umbrella: sentinel replaced by --set UUID and by the custom-values UUID)
- `terraform fmt -check` on the fused template → clean
- renovate config-validator (renovate 44.115.13 dist) → "Config validated successfully"
- `bash -n` + `dash -n` on workspace-startup.sh → clean
- `npx aislop@0.18.1 ci --changes` → 0 errors / 0 warnings (25 files)
- Not runnable here: docker build (no daemon — PR CI `docker-build.yaml` is the
  build proof); live Renovate datasource resolution (post-merge).

## User-owned next steps
Commit + PR from this worktree; after merge: `coder templates push <name>
--directory charts/coder/coder-templates/kubernetes-hardened`, then
`coder templates edit <name> --default-ttl 168h`; pin the template image to the
first `:v<run>` tag; ArgoCD syncs the forgejo-token ExternalSecret.
