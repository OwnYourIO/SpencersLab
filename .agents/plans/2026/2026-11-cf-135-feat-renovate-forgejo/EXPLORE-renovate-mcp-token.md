# EXPLORE — the renovate-MCP GitHub PAT as RENOVATE_GITHUB_COM_TOKEN donor (cf-135 round 2)

`agent-explore` 2026-11-10, scoped to the owner's Q4 ("there is already a github PAT for this on the
renovate MCP server — explore that setup"). Repo reads + live readonly dev/gpu cluster probes (UTC).
No Secret values read (RBAC-forbidden by design). Complements EXPLORE §5/§7 OQ-6 and RESEARCH §3.

## §1 The dev renovate MCP server and its token chain
- MCPServer entry: `services/dev/prod/values.yaml:294-312` (inside `hivetools:` from :228) — server
  `renovate`, image `ghcr.io/ownyourio/renovate-mcp:v84`, streamable-http supergateway bridge
  (`:364-378`). It is the `dev-renovate`/`global-renovate` DESIGN-TIME tool (AGENTS.md table: dry-run/config
  validation), built in-repo: `containers/renovate-mcp/Dockerfile:34` pins `renovate-mcp@1.4.11` + bundled
  Renovate (`:27`, "Acceptable for design-time use" `:29-31`). It creates no PRs.
- The PAT touches ONLY the pod's `clone` initContainer (`values.yaml:330-350`): `git clone --depth 1
  --branch main https://x-access-token:${GITHUB_PERSONAL_ACCESS_TOKEN}@github.com/OwnYourIO/SpencersLab.git`
  — a read-only use. Live pod (probed): mcp container env = FASTMCP_*/MCP_*/RENOVATE_* only, zero secretRefs.
- Chain: `bitwardenIds.github-mcp` sentinel `services/dev/prod/values.yaml:69` →
  `custom-values/dev/prod-values.yaml:30` UUID `522b1cc4-2c74-4399-887d-b4e20014b2d2` → ExternalSecret
  `services/dev/prod/templates/secret-github-mcp.yaml` (`bitwarden-login` store, `property: password`,
  target key `GITHUB_PERSONAL_ACCESS_TOKEN`). Live dev: ES `github-mcp` Ready=SecretSynced (since
  2026-11-03T16:12Z); pod `mcp-renovate-0` Running 1/1, init `clone` Terminated/Completed ready=true.

## §2 The "github-mcp" entry: no server, a SHARED item
- The GitHub MCP server itself was dropped — both template headers say the name is historical
  (`services/dev/prod/templates/secret-github-mcp.yaml:1-2`, gpu twin `:1-2`); only the Secret remains.
  Live gpu MCPServer list (16 entries) confirms no `mcp-github` server exists.
- `github-mcp` and `github-pat` are the SAME Bitwarden item **`dev-github`** (password = PAT):
  `custom-values/dev/prod-values.yaml:23,26-30`; user ruling 2026-10-24 superseding the "new FIELDS item"
  intake assumption (dev-mcp-fleet `DECISIONS.md:93-99`, `FRICTION.md:25`, contract t9 re-ruled at
  `tests/services/dev-mcp-fleet.sh:564`).
- Same value, second consumer: Secret `github-pat` (`secret-github.yaml:1-6`) feeds the Coder
  `kubernetes-hardened` workspace env `GITHUB_TOKEN` (`charts/coder/coder-templates/kubernetes-hardened/main.tf:454-462`),
  documented purpose "clone/push OwnYourIO repos" (`secret-github.yaml:1-2`) — so docs CLAIM a write-capable
  PAT; live only proves read (the clone).

## §3 Scope claims: NONE exist repo-wide
- Searched plans/custom-values/templates for classic-vs-fine-grained/scope/repo-permission statements about
  `dev-github`/`github-mcp`: zero hits. The docs record item SHAPE only, never GitHub-side scopes, owning
  account, or expiry.
- dev-mcp-fleet `STATE.json:90` deferred still says "create dev github-token FIELDS item + paste UUID" —
  **stale**, superseded by DECISIONS:93-99 (flag for the owner, do not act on it).
- cf-86 strata: no GitHub PAT donor (HF legs are anonymous `hf_fetch.py`; its "tokens" are arena api-keys).
  cf-119's `PUSH_TOKEN_GH` is a DIFFERENT fine-grained PAT (Contents R/W + Workflows, cf-119
  `DECISIONS.md:55-57`, EXPLORE:201-206) minted for main-sync, instance-side.

## §4 gpu cluster + coder sides
- gpu twin: `services/gpu/prod/values.yaml:891-971` (same image/wiring), but its `github-mcp`
  (`custom-values/gpu/prod-values.yaml:32`) is a DISTINCT item `f4938da9-3260-42c7-9787-b38100023fc3` read via
  `bitwarden-fields` / custom field `token` (`services/gpu/prod/templates/secret-github-mcp.yaml:17-25`) —
  the pre-ruling original shape. Live: ES Ready=SecretSynced, `mcp-renovate-0` Running.
- gpu renders NO `github-pat` Secret (no `secret-github.yaml` in its templates, no bitwardenIds key) — gpu
  coder workspaces get no GITHUB_TOKEN; gpu's only GitHub env is the disabled OAuth login
  (`services/gpu/prod/values.yaml:501-504`).
- coder git-auth Forgejo leg: `FORGEJO_TOKEN` ← Secret `forgejo-token` = item `5488c4ba…` "Forgejo access
  token for git.scifi.farm" (`custom-values/dev/prod-values.yaml:24-25`; `main.tf:464-477`, host
  `git.scifi.farm`) — a pre-existing dev-instance PAT, scopes unclaimed in-repo; separate from OQ-5's
  PR-writable platform token.

## §5 Verdict
- **Owner's hunch is right and the reuse is sound.** A live, working GitHub PAT (`dev-github`, 522b1cc4) is
  already wired for this repo's renovate tooling. RESEARCH §3 requires only a READ-ONLY
  `RENOVATE_GITHUB_COM_TOKEN` — strictly less than what this item already does (docs claim clone+push on
  OwnYourIO repos). Recommended shape: the user copies that item's password into the Forgejo repo's Actions
  secret (instance-DB secret, not k8s/Bitwarden-synced — the cf-119 mint pattern, EXPLORE:191-198), name
  `RENOVATE_GITHUB_COM_TOKEN`; the workflow references only `secrets.RENOVATE_GITHUB_COM_TOKEN`, never a
  k8s Secret. No new repo-side credential wiring.
- Ownership: human-owned Bitwarden vault item; the repo carries UUIDs only; mint/attach stays user-owned.
- Unknown (owner check): (a) classic vs fine-grained, owning account, expiry — no repo claim (§3); (b) whether
  ONE identity should serve coder-workspaces + renovate-MCP-clone + the new bot datasource (shared rate-limit
  and blast radius: revocation/expiry breaks all three); (c) whether gpu's f4938da9 holds the same value —
  not verifiable repo-side; it is the natural donor if the owner wants a separate datasource identity.
