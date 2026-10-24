# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions

- Forgejo instance env naming in this ticket: the dev instance keeps the
  existing generic pair (`FORGEJO_TOKEN` / `FORGEJO_HOST`, host
  `git.scifi.farm`); the infra canonical instance gets the `_CANONICAL`
  suffix on every surface — Bitwarden item / Secret / ExternalSecret /
  `bitwardenIds` key `forgejo-token-canonical`, env
  `FORGEJO_TOKEN_CANONICAL` / `FORGEJO_HOST_CANONICAL` (host
  `git.spencerslab.com`).
- One Bitwarden item per concern (helm-chart-creation skill): a per-instance
  PAT is a separate item from the instance's own `forgejo*` admin items and
  from the runner-token items.
- Git-over-SSH URLs for lab forges stay `ssh://git@<host>:22222/...` (sibling
  decision from 2026-10-feat-forgejo-ssh, Q2: node sshd keeps :22). known_hosts
  entries therefore key on `[host]:22222`, the form ssh-keyscan emits for
  non-default ports.
- Validation = the four `tests/` suites + helm lint/template + sh/dash -n in
  the plan file's Commands; no unit-test framework exists.

## Decisions

- 2026-10-24 plan: Scope taken from the intake answers — git auth (tokens,
  credential helpers, repo URLs, fj wiring) for BOTH instances + OpenChamber's
  Forgejo feature. Explicitly OUT (user declined): OAuth/SSO wiring, Forgejo as
  ArgoCD repo source.
- 2026-10-24 plan: Research is resolved by quick lookups, agent-research NOT
  needed. Findings (sources in the plan file's Research basis): OpenChamber
  v2.5.1 (2026-10-23) adds the Forgejo/Gitea/Gerrit host cards; the Forgejo
  card takes instance URL + PAT with `write:repository`, `write:issue`,
  `read:user`, requires Forgejo ≥7.0 served at the address root; sign-ins are
  stored server-side (→ home PVC `~/.config/openchamber`), shared across
  devices; OpenChamber ≥2.5.1 requires OpenCode ≥2.1.0 (it bundles 2.1.3);
  npm latests 2026-10-24: @openchamber/web 2.5.1, @opencode/cli 2.1.4. The
  lab's charts/forgejo appVersion 15.0.9 clears the ≥7.0 floor.
- 2026-10-24 plan: Manual pin bump to 2.5.1/2.1.4 in
  `containers/coder-workspace/Dockerfile` (C01), NOT "wait for renovate".
  The feature itself demands a version floor (2.4.0 has no Forgejo host;
  OpenCode 2.0.32 is below OpenChamber 2.5.1's 2.1.0 minimum) — a floor is a
  requirement, not a routine bump; renovate keeps the pins current afterwards.
  Precedent: 2026-10-04-dep-update-opencode-openchamber.md, and the rebuild
  ticket pinning exact versions. Renovate annotations stay untouched.
- 2026-10-24 plan: Dual-instance auth via a second explicit env pair
  (`FORGEJO_TOKEN_CANONICAL`/`FORGEJO_HOST_CANONICAL`) consumed by a looped
  `wire_forgejo` function in workspace-startup.sh. Rejected: comma-separated
  `FORGEJO_HOSTS`/`FORGEJO_TOKENS` positional pairing (fragile, and breaks the
  established single-name contract dev-git-auth.sh c6 checks); a full git
  credential-store file (the current design's stated invariant is "nothing
  written to disk" — the home PVC outlives the Secret); Coder
  `coder_git_auth`/external git auth (per-user redesign, out of scope).
- 2026-10-24 plan: `FORGEJO_HOST_CANONICAL` is a literal container env in the
  template (mirroring the existing `FORGEJO_HOST = "git.scifi.farm"`), NOT a
  new coder_parameter — avoids the server-stored-template-variable trap
  documented in 2026-10-04-dep-update-opencode-openchamber.md (DECISIONS of
  coder-workspace-rebuild too).
- 2026-10-24 plan: New custom-values entry ships as the documented
  `OVERRIDE_NEEDED` placeholder until the user creates the Bitwarden item
  (infra-forgejo t6 precedent), with a real UUID following in a user-action
  commit. Rejected: fabricating a UUID (renders an ExternalSecret pointing at
  nothing) and blocking the whole ticket on the manual step.
- 2026-10-24 plan: known_hosts pre-trust for the lab forges moves to port
  22222 (`ssh-keyscan -p 22222`, `[host]:22222` entries) for BOTH hosts and
  github.com stays scanned at 22. The current port-22 `git.scifi.farm` scan
  captures the NODE's sshd key (sshd kept on :22 by sibling decision), which
  is the wrong key for forgejo ssh:// URLs anyway.
- 2026-10-24 plan: OpenChamber's per-instance connection stays a UI paste
  (User action 4) — the docs describe no env/file/policy bootstrap for
  integration tokens. The repo-side enabler is only the version bump; the
  token's persistence is the home PVC. Rejected: scripting the UI or
  inventing a config drop-path against undocumented internals.
- 2026-10-24 plan: The legacy `charts/coder/coder-templates/kubernetes/`
  template and `terraform.tfvars` (openchamber 2.1.0 / opencode 2.0.22
  runtime-install lineage) stay untouched. `kubernetes-hardened` is the
  git-auth-consumed template (dev-git-auth.sh names it); giving the legacy
  template Forgejo support would mean runtime-install changes the rebuild
  deliberately deleted. Retiring the legacy template is a separate cleanup.
- 2026-10-24 plan: chunking = C01 pins (S) / C02 script (M) wave 1; C03 secret
  plumbing + template env (M) wave 2. Interface-first: C02 defines the env
  contract, C03 produces matching env. C01 merges alone (consumers of the
  image are env-name-stable). Rejected: one mega-chunk (mixes an image-pin
  revert concern with plumbing); splitting C03's service-side and chart-side
  legs (a half-landed pair renders a Secret no template consumes — breaks
  "chunk merges without breaking the software").
- 2026-10-24 plan: Baseline validation recorded — on this branch
  image-structure.sh, startup-script.sh, dockerfile-pins.sh, dev-git-auth.sh
  (20 ok) and sh/dash -n all PASS before any change. Red-for-the-right-reason
  targets for agent-test: image-structure + dockerfile-pins go red the moment
  they expect the NEW pins while the Dockerfile still has the old ones;
  dev-git-auth goes red on the missing `forgejo-token-canonical`
  ExternalSecret/env; startup-script on the missing `_CANONICAL` names.

## Deferred

- Adding lab Forgejo repos as `repos` coder_parameter options once repos exist
  on the forges (template comment anticipates it).
- Retiring the legacy `kubernetes/` workspace template + tfvars.
- Per-user git auth (Coder external git auth) if workspaces ever stop sharing
  one lab token.
- Re-checking for a headless OpenChamber integration seed at each major bump.

## Test round (2026-10-24, coord from agent-test RESULT, commit e520df0b2)
- Ruled (deviations accepted, contract preserved): (1) two pre-existing c4 document selectors in tests/services/dev-git-auth.sh tightened prefix→boundary-terminated so C03's `forgejo-token-canonical` doc can't collide with the original `forgejo-token` checks (c1..c6 stay green; strengthens isolation, nothing weakened); (2) the C02 helper-pattern check accepts EITHER legal layout (3-arg `wire_forgejo` called with the env-var name, or literal helper body) — binds the contract, not dev's style; (3) traceability spec lives at TEST-SPEC.md (ticket root).
- Test suite is now the immutable contract for C01–C03; fixes route back to test_session ses_e908a206dffeJJZ7J97KEzUmVP.

## C02 ownership reconciliation (2026-10-24, coord)
- The coord launch summary for C02 wrongly included the kubernetes-hardened/main.tf env pass-through; chunks/C03.md mandates both canonical env blocks (c-canonical-3). Dev correctly followed the chunk files. Ruling: chunk files are the ownership ground truth; no plan change; C03 lands the template env blocks.

## Deferred hygiene note (C03 review round 1, 2026-10-24)
- One non-blocking hygiene note recorded by the C03 reviewer in chunks/C03.md ("Deferred" section) — does not gate the ticket.

## Replan: SSO (Coder external-auth via Forgejo/Keycloak) — user rulings 2026-10-24
- User confirmed TWO Coder deployments intended to each carry one external-auth provider: coder.spencerslab.com ↔ git.spencerslab.com, coder.dev.scifi.farm ↔ git.scifi.farm. The community one-provider cap binds per instance. PLANNER MUST verify the two-Coder topology against repo/cluster before chunking (research assumed one Coder).
- Existing dev forgejo-token = bot account (bootstrap/fallback retained).
- Forgejo full-account (scopeless) OAuth grants: accepted.
- Coder external-token DB encryption: enable (--external-token-encryption-keys, key via Bitwarden ExternalSecret).
- Non-OAuth forge fallback (if any): Coder user-secrets (Beta) per-user PATs.
- First-boot UX: polite gate + banner around `coder external-auth access-token` (no raw clone failure until consent).
- OpenChamber path unchanged (per-user PAT card; C03 canonical plumbing stays as its token source).

## Replan v2 planning decisions (2026-10-24, plan agent)
- **GATE PASSED — two-Coder topology verified with evidence.** Live: gpu
  `default/coder` v2.35.2 (386d, ingress hosts `coder.spencerslab.com` /
  `code.spencerslab.com` / wildcard `*.spencerslab.com`, active
  enterprise-base workspace) + dev `default/coder` v2.35.2 (11d, hosts
  `coder.dev.scifi.farm` + wildcard, active `coder-workspace:main`
  workspace); infra runs no coder. Repo: `services/gpu/prod/values.yaml`
  (external chart pin 2.35.2) + `services/gpu/prod/templates/secrets-coder.yaml`
  (`CODER_ACCESS_URL=https://coder.{{ .Values.domain }}`) and
  `services/dev` + `charts/coder` (wrapper, `https://coder.dev.scifi.farm`).
  The user's premise holds → no blocking question; the single-Coder
  fallback (user-secrets Beta) ruling is MOOT.
- Pairing follows the user ruling exactly: dev coder slot → git.scifi.farm
  (kubernetes-hardened workspaces gain per-user dev-forge identity), gpu
  coder slot → git.spencerslab.com. Recorded CONSEQUENCE (flagged to the
  user, not a blocker): dev-cluster workspaces keep the shared bot PAT for
  canonical — per-user canonical identity exists only from gpu-coder
  workspaces. Reversible by flipping the dev coder's AUTH_URL if the user
  objects before approval.
- Provider config lands fully GitOps via **env provisioning**
  (`CODER_EXTERNAL_AUTH_0_*` on coderd — no TF resource exists for
  providers; the coder TF provider only has a data source). Mechanism per
  cluster: dev → `charts/coder/templates/secret-coder.yaml` coder-secrets
  ES (the existing OIDC env pattern); gpu → the twin
  `services/gpu/prod/templates/secrets-coder.yaml`. Provider id `forgejo`
  on both; the callback path `/external-auth/forgejo/callback` embeds it
  (v2.35.2 docs: mismatch ⇒ "redirect URI is not valid"). No explicit
  REGEX/TOKEN_URL/VALIDATE_URL — `giteaDefaults()` derives all three from
  the AUTH_URL host (source-verified at the deployed tag, v2.35.2,
  coderd/externalauth/externalauth.go:1210+).
- Rejected build-time `data.coder_external_auth` token injection (docs:
  does not auto-refresh; conflicts with the no-server-stored-values rule)
  and Coder device-flow (Forgejo 404s it — issue #4830 open).
- Encryption env form `CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS` (docs-verified
  at v2.35.2; comma-separated base64 32-byte, first key encrypts). Key
  items: `coder-token-encryption` per cluster (password field = the key).
  Wrong-length key ⇒ coderd crashloop on restart — generation command is
  documented in the custom-values comment; tests only assert presence.
- New Bitwarden items named `coder-external-auth` (login item: username =
  OAuth client id, password = secret) and `coder-token-encryption`, one
  per cluster. **Same bitwardenIds key, different item per cluster** —
  the existing `coder-sso-secret`/`coder-pg` precedent (per-cluster
  custom-values files carry different UUIDs under identical keys) beats
  `_CANONICAL` suffixes here, because the `_CANONICAL` convention names
  FORGE-side concerns, and this item pairs coder↔forge on that coder's
  cluster. Slots ship `OVERRIDE_NEEDED` until the user creates the items
  (forgejo-token-canonical precedent). Gpu's new sentinels use the current
  `OVERRIDE_VIA_CUSTOM_VALUES` standard, NOT the legacy cluster-annotation
  mechanism of gpu's older coder keys — no migration of those in scope.
- Reloader pod annotations (`reloader.stakater.com/auto: "true"`) added on
  both coder deployments (charts/coder/values.yaml `coder.coder`;
  services/gpu `coder.coder` — the external chart is one level shallower)
  because coderd reads provider/encryption env only at process start.
  Reloader controllers live-verified on both clusters (base chart-wide
  deploy; dev `dev-reloader-reloader` 1/1). Rejected: manual restart ritual
  as the documented path (secret updates would silently not apply).
- Forge-side OAuth app registration is a **user action, honestly labeled**:
  no admin-scope OAuth API in v15.0.9 (no routers/api/v1/admin/oauth.go —
  source-checked), user-scope `/api/v1/user/oauth2` exists (route table
  verified) but its output (client secret) must reach Bitwarden by hand —
  no repo mechanism writes TO the vault. UI or curl both fine; redirect
  URIs are deterministic and listed in the plan's User actions.
- Workspace layering (C06) resolves the PAT-shadow race deterministically
  per research §E (helpers answer before askpass): probe at boot —
  approved ⇒ unset any stale dev-host PAT helper (PVC persists it across
  boots — load-bearing) and DON'T re-wire (askpass answers per-user);
  unapproved ⇒ banner prints the CLI's approval URL (exit-1 contract,
  docs-verified) and the bot PAT fallback wires exactly as C02 shipped.
  `wire_forgejo` grows a 4th helper-mode arg rather than relocating the
  `fj` call, keeping C02's frozen "add-token only inside wire_forgejo"
  contract green; the 4th-arg layout is pinned in the tests as an allowed
  pattern, not mandated.
- `fj` keeps the bot PAT even when git is approved: Forgejo access tokens
  live ~1h and fj's `add-token` store is static (no self-refresh like its
  OAuth `keys.json` chain) — seeding an hour-lived token would rot
  mid-session. Per-user identity is the GIT story; the fj/OpenChamber
  floors stay bot/user-PAT per the user's "bootstrap/fallback stays"
  ruling. Alternative rejected: fj `auth login` laptop bootstrap
  (laptop-only loopback + refresh-rotation races the PVC copy).
- Boot-time clones under approved SSO get the token via transient process
  env only (`GIT_CONFIG_COUNT`-injected helper or `git -c`, in-memory,
  per-URL host-matched so it can't leak the credential to other hosts) —
  the no-disk invariant extends to the OAuth token. Rejected: wiring the
  global helper with the literal token (persists to the PVC + expires in
  1h); rejected: helper echoing a boot-only var name (git helpers expand
  at use time — an empty password would shadow askpass in terminals with
  a broken credential).
- Gated-clone reading of the "polite gate" ruling: gate = never a raw
  credential failure — with the bot PAT present the clone proceeds
  (fallback per ruling); with neither approval nor PAT present the
  matching-host clone is SKIPPED with an explicit pending-approval log
  next to the banner. Recorded because the two user rulings (gate vs
  fallback) intersect here.
- Chunking: C04 dev-server + C05 gpu-server wave 3 (independent — zero
  shared files), C06 workspace gate wave 4 depends [C04] (provider-id
  literal drift trap + live-probe semantics). Rejected: one server chunk
  for both clusters (two subsystems, ~8 files, and the gpu leg is
  independently revertable); rejected: merging C06 into C04 (script +
  HCL consumers must land behind the interface, and each diff stays
  under one review). Rejected: a separate chunk for the reloader
  annotation (same file, same commit, meaningless alone).
- Tests: two new suites (`tests/services/gpu-coder-sso.sh`,
  `tests/coder-workspace/startup-sso-behavior.sh` — the latter a
  dash/stub-PATH/isolated-HOME behavioral matrix per the FRICTION
  git-probe rule) plus extensions of the two established suites.
  Behavioral (not grep-only) coverage is mandated for the gate logic —
  grep cannot prove "helper NOT wired when approved".
- Replan numbering continues C01–C03 without renumbering them; done-chunk
  contracts (startup-script, dev-git-auth c1..c-canonical) stay green as
  regressions in every new chunk.

