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
