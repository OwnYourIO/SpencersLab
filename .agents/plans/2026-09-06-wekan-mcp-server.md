# Plan: Deploy wekan-mcp to the lab + align skill/container + MCP section in helm skill

## Goal

Ship the in-repo WeKan MCP server (`containers/wekan-mcp`) to the lab's ToolHive
platform (`charts/hivetools`), so agents can drive WeKan boards through
`https://mcp.spencerslab.com/wekan/mcp` with the bearer token fully isolated in
Bitwarden/ExternalSecret (never in model context). Along the way: fix the
container's code/policy gaps found in review, align the `wekan-api` skill with
the MCP server, enable `WITH_API` on the target WeKan instance, and add a
reusable "MCP servers" reference to the `helm-chart-creation` skill since many
more MCP servers will follow this exact path.

## Execution status (updated 2026-09-06, worktree `wekan-mcp-server-skill-v2`)

**All code changes are committed and merged.** Commit `87bc4193` ("Deploy
wekan-mcp via hivetools; harden container; align wekan-api skill") is on
`origin/main`; CI already bumped `containers/wekan-mcp/VERSION` to `0.0.2`
(`dc833915`), released the chart (`89c26507`), and published
`ghcr.io/ownyourio/wekan-mcp:0.0.2` (GHCR tags verified: `0.0.1`, `0.0.2`,
`latest`) — matching the image pin in `charts/hivetools/values.yaml`.

Verified in the final committed state:

- Steps 1–6 (container): `server.py` has 15 tools incl. `list_checklists` /
  `get_checklist`; Dockerfile copies `VERSION`, runs uid/gid 65532,
  `ENTRYPOINT`; `pyproject.toml` dynamic version; `__init__.py` hardcoded
  version removed; `k8s/` deleted; README rewritten. **Live smoke test PASS**
  (2026-09-06): package venv-installed from this tree (dynamic version
  resolves from `VERSION`), run against a mock WeKan — startup validation logs
  `connected to WeKan as user_id=...`; streamable-http `initialize` →
  `tools/list` returns exactly the 15 expected tools; `list_boards` and
  `get_checklist` tool calls succeed (get_checklist returns item ids);
  bad-token startup exits 1 with the sanitized 401/WITH_API message. Local
  `docker build` skipped (no daemon in this environment) — moot, since CI
  already built and pushed `0.0.2` from this exact Dockerfile.
- Steps 7–9 (chart): `WITH_API=true` on the `wekan` instance only;
  `charts/hivetools/values.yaml` has exactly ONE `bitwardenIds.wekan-mcp`
  sentinel and ONE `mcp.wekan` block (a transient duplicate observed during
  planning did not land in the commit); `secret-wekan-mcp.yaml` matches the
  sketch. `helm lint` passes; `helm template --set
  bitwardenIds.wekan-mcp=test-uuid` renders one wekan MCPServer + one
  ExternalSecret + one `/wekan` ingress path, no sentinel leak.
- Steps 11–14 (skills/docs): all present and committed.

### Remaining work

R3. **[Blocked on user — the only outstanding code item]
    `custom-values/gpu/prod-values.yaml`** — add `wekan-mcp: <UUID>` under
    `hivetools.bitwardenIds:`. The UUID is of a Bitwarden **login** item the
    user must create: username = dedicated password-based WeKan service user
    on `https://wekan.spencerslab.com`; password = bearer token from
    `POST /users/login` (JSON body). Until this lands, the `wekan-mcp`
    ExternalSecret cannot sync (same failure mode the cluster shows today for
    `qdrant`: `key: OVERRIDE_VIA_CUSTOM_VALUES → 400 Bad Request`) and
    ToolHive cannot start the wekan pod. Do not commit a placeholder UUID.

R5. **[Post-sync, after R3]** ArgoCD sync of gpu hivetools → confirm
    ExternalSecret `wekan-mcp` Ready, `wekan-0` + proxy pods Running, startup
    log `connected to WeKan as user_id=...`, then end-to-end `tools/list` +
    `list_boards` via `https://mcp.spencerslab.com/wekan/mcp` (Keycloak token,
    audience `wekan`). Home-cluster `WITH_API` confirmation needs the user or
    ArgoCD UI (home cluster is not reachable from the kubernetes MCP
    connection). As of 2026-09-06 the gpu cluster shows no `wekan-mcp`
    ExternalSecret and no wekan pods yet.

## Skills

Code agent must load (fresh session):

- `writing-plans` execution discipline aside, primarily:
- `helm-chart-creation` — hivetools values/template wiring, ExternalSecret +
  bitwardenIds + custom-values pattern, validation workflow
- `container-creation` — Dockerfile/ENTRYPOINT/uid conventions, docker-build
  workflow + VERSION auto-bump flow
- `wekan-api` — needed both as context for editing `skills/wekan-api/SKILL.md`
  and for the WeKan-side facts (WITH_API, /users/login, token semantics)

## MCP Servers

- `kubernetes` — verify pods/proxies after ArgoCD sync (note: this connection
  only reaches the **gpu** cluster; the WeKan instance lives in the home
  cluster and cannot be inspected from here)

## Verified context

Recon performed in this worktree (`wekan-mcp-server-skill-v2`, HEAD == origin/main):

- **Container exists and is functional (smoke-tested, was untested):**
  installed `containers/wekan-mcp` in a venv (fastmcp 3.4.7, httpx 0.28.1 —
  satisfy `pyproject.toml` pins), ran it against a mock WeKan API. Verified:
  startup validation via `GET /api/user`; streamable-http served at `/mcp`;
  MCP `initialize` → `tools/list` returns exactly the 13 documented tools;
  `tools/call` works for reads (`list_boards`) and writes (`create_card`);
  errors sanitized to `WeKan <status> on <path>: <reason>` (no token/traceback
  leak); bad token at startup → clean `exit 1` with the WITH_API hint.
- **Image already published:** `ghcr.io/ownyourio/wekan-mcp` tags
  `0.0.1`, `latest` exist in GHCR (docker-build workflow already ran; the
  `Bump wekan-mcp version to 0.0.1` commit is in history). Any change under
  `containers/wekan-mcp/` merged to main auto-bumps `VERSION` → next tag `0.0.2`.
- **MCP platform:** `charts/hivetools` (ToolHive operator + CRDs 0.34.0) is
  live in the gpu cluster (`toolhive-operator` pod Running; 8 MCP servers
  running). Servers are declared under `mcp:` in `charts/hivetools/values.yaml`
  and rendered by `templates/generic-mcpserver.yaml`
  (`toolhive.stacklok.dev/v1beta1 MCPServer`; required: `image`, `transport`,
  `mcpPort`; optional: `oidc` (shared Keycloak `MCPOIDCConfig` named
  `keycloak`, per-server `audience`), `env`, `secrets`
  (`{name, key, targetEnvName}` where `key` is a key in the ExternalSecret's
  *target* data), `resources`, `podTemplateSpec` (container MUST be named
  `mcp`)). Shared ingress `templates/generic-mcp-ingress.yaml` routes
  `mcp.<domain>/<name>` → `mcp-<name>-proxy:<mcpPort>` automatically for every
  enabled entry — no separate proxy wiring needed.
- **Secret pattern:** `templates/secret-github-mcp.yaml` (bitwarden-fields) and
  `templates/secret-homeassistant-mcp.yaml` (bitwarden-login `password` +
  bitwarden-uri) are the precedents; `bitwardenIds.<name>` sentinel in chart
  values + real UUID under `hivetools.bitwardenIds` in
  `custom-values/gpu/prod-values.yaml`.
- **WeKan target:** deployed from `services/home/prod` (external chart
  `wekan 9.18.0`, https://wekan.github.io/charts/) twice: `wekan`
  (root_url `https://wekan.spencerslab.com`, `OIDC_REDIRECTION_ENABLED=false`
  — the comment says "This allows a local bot to login", i.e. the bot/API
  instance) and alias `boards` (`https://boards.spencerslab.com`, OIDC
  redirect on, for humans). WeKan runs in the **home cluster** — no
  `home-wekan` Service exists in the gpu cluster, so the MCP server must use
  the public ingress URL.
- **WITH_API is NOT set:** not in the chart's default `env` (fetched
  `helm show values wekan --version 9.18.0`) and not in
  `services/home/prod/values.yaml`. Per `skills/wekan-api/references/config-reference.md`
  every REST endpoint 401s without it. Must be added.
- **Alignment check container ↔ skill:** env contract identical
  (`WEKAN_BASE_URL` site root without `/api`, `WEKAN_TOKEN` pre-obtained
  bearer); every endpoint/body in `wekan_mcp/server.py` matches
  `skills/wekan-api/scripts/*` and `references/rest-api-overview.md`
  (create-card body, move-via-PUT with `listId` in body against the CURRENT
  list URL, comment `{authorId, comment}`, checklist `{title, items}`,
  toggle `{isFinished}`).
- **Gaps found (drive the changes below):**
  1. No `get_checklist`/`list_checklists` tools → `toggle_checklist_item`
     cannot discover checklist/item IDs (skill scripts have both endpoints).
  2. `skills/wekan-api/SKILL.md` never mentions the MCP server.
  3. `containers/wekan-mcp/k8s/` contradicts repo hard rules: `kubectl apply`
     (vs "ArgoCD applies everything"), `v1alpha1` MCPServer (cluster runs
     `v1beta1`), manual Secret creation (vs ExternalSecret+Bitwarden),
     `toolhive-system` namespace (lab uses `default`).
  4. Dockerfile uses `CMD` (container-creation skill mandates `ENTRYPOINT`)
     and uid 10001 (repo convention 65532).
  5. Version drift: `VERSION`=0.0.1 (drives image tag) vs `pyproject.toml` /
     `__init__.py` 0.1.0.
- Render checks: not needed yet (no chart edits made during planning);
  validation commands are in the Verification section.

## Design decisions

1. **Deploy via `charts/hivetools` `mcp:` map — NOT a new chart, NOT the
   container's `k8s/` manifests.** Pattern applied: the 10 existing hivetools
   MCP servers. The `k8s/` dir is deleted because it teaches a workflow that
   violates this repo's hard rules.
2. **Target instance = `wekan` (https://wekan.spencerslab.com), not `boards`.**
   It is the bot-enabled instance (`OIDC_REDIRECTION_ENABLED=false`);
   `boards` is the human SSO instance. `WITH_API=true` is added only to
   `wekan` to keep the human instance's API surface off.
3. **Base URL = public ingress URL.** WeKan is in the home cluster; in-cluster
   DNS does not resolve across clusters. TLS is terminated by Traefik with the
   wildcard cert. Server-to-server calls mean CORS is irrelevant.
4. **Credential flow (user confirmed):** dedicated **password-based** WeKan
   service user (OIDC-only users cannot use `/users/login`), token obtained
   once via `POST /users/login`, stored as the **password field of a new
   Bitwarden login item** → `bitwarden-login` SecretStore → ExternalSecret
   `wekan-mcp` → injected by ToolHive as `WEKAN_TOKEN` via `spec.secrets`.
   Same shape as `homeassistant-mcp`. `WEKAN_BASE_URL` is a public URL, so it
   stays a plain (non-secret) `env` value like searxng's `SEARXNG_URL`.
5. **Transport = streamable-http, mcpPort 8080** (matches image default
   `WEKAN_MCP_PORT=8080` and the homeassistant/kubernetes precedent). OIDC
   audience `wekan` via the shared Keycloak config.
6. **Versioning:** make `pyproject.toml` read its version from the `VERSION`
   file (setuptools dynamic version) so the image tag and package version can
   never drift again. Image tag pinned in hivetools values (never `latest`).
7. **MCP section in the helm skill:** a new reference doc
   `skills/helm-chart-creation/references/mcp-servers.md` (user requested an
   MCP-specific portion since many MCP servers will follow). Adding an MCP
   server needs no ApplicationSet/proxy trio — hivetools is already wired in
   `services/gpu/prod` — so it is a reference doc, not a new skill.

## Changes

Ordered; dependency note: steps 1–6 merge first, the docker-build workflow
then bumps `VERSION` to `0.0.2` and pushes the image — step 9 pins that tag.

### Phase 1 — container fixes (`containers/wekan-mcp/`)

1. `containers/wekan-mcp/wekan_mcp/server.py` — [MODIFY] add two read tools so
   checklist/item IDs are discoverable (endpoints per
   `skills/wekan-api/references/rest-api-overview.md` lines 282–290):

   ```python
   @mcp.tool
   def list_checklists(board_id: str, card_id: str) -> list[dict]:
       """List the checklists on a card."""
       raw = _wekan.get(f"/api/boards/{board_id}/cards/{card_id}/checklists") or []
       return [{"id": c.get("_id"), "title": c.get("title")} for c in raw]


   @mcp.tool
   def get_checklist(board_id: str, card_id: str, checklist_id: str) -> dict:
       """Get a checklist with its items. Item ids are required by toggle_checklist_item."""
       raw = _wekan.get(
           f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}"
       ) or {}
       return {
           "id": raw.get("_id"),
           "title": raw.get("title"),
           "items": [
               {"id": i.get("_id"), "title": i.get("title"),
                "finished": i.get("isFinished", False)}
               for i in raw.get("items", []) if i
           ],
       }
   ```

2. `containers/wekan-mcp/Dockerfile` — [MODIFY]
   - `COPY pyproject.toml README.md ./` → `COPY pyproject.toml README.md VERSION ./`
   - non-root user per container-creation convention (uid 65532):
     ```dockerfile
     RUN groupadd --system --gid 65532 mcp \
         && useradd --system --uid 65532 --gid 65532 --shell /bin/false \
            --home /home/mcp --create-home mcp \
         && chown -R mcp:mcp /app
     USER 65532
     ```
   - `CMD ["wekan-mcp"]` → `ENTRYPOINT ["wekan-mcp"]`

3. `containers/wekan-mcp/pyproject.toml` — [MODIFY] dynamic version from
   `VERSION` (removes the 0.1.0 vs 0.0.1 drift permanently):
   ```toml
   [project]
   name = "wekan-mcp"
   dynamic = ["version"]
   ...
   [tool.setuptools.dynamic]
   version = {file = "VERSION"}
   ```

4. `containers/wekan-mcp/wekan_mcp/__init__.py` — [MODIFY] delete the
   hardcoded `__version__ = "0.1.0"` line (keep the docstring) to avoid a
   second drifting version source.

5. `containers/wekan-mcp/k8s/` — [DELETE] entire directory
   (`mcpserver.yaml`, `secret.yaml.example`, `client-setup.md`). Superseded by
   the hivetools wiring below; its `kubectl apply` workflow violates repo
   rules.

6. `containers/wekan-mcp/README.md` — [MODIFY]
   - Tool table: 13 → 15 tools (add `list_checklists`, `get_checklist`, both read).
   - Replace "End-to-end setup" (manual ToolHive/kubectl sections 1–5) with
     "Deployment in SpencersLab": image auto-built by
     `.github/workflows/docker-build.yaml` → `ghcr.io/ownyourio/wekan-mcp`;
     deployed as `mcp.wekan` in `charts/hivetools/values.yaml`; token via
     ExternalSecret `wekan-mcp` + Bitwarden; endpoint
     `https://mcp.spencerslab.com/wekan/mcp` behind Keycloak OIDC (audience
     `wekan`). Point at `skills/helm-chart-creation/references/mcp-servers.md`.
   - Keep "Local development", security notes, and the WeKan/FastMCP upgrade
     notes; drop the ToolHive CRD field-drift note (operator is pinned by the
     hivetools chart).

   **Merge checkpoint:** after steps 1–6 hit `main`, GitHub Actions bumps
   `VERSION` to `0.0.2` and pushes `ghcr.io/ownyourio/wekan-mcp:0.0.2`.
   Confirm the tag exists before step 9 (see Verification).

### Phase 2 — WeKan prerequisite (home cluster)

7. `services/home/prod/values.yaml` — [MODIFY] enable the REST API on the
   `wekan` instance only (first entry in its `env:` list):
   ```yaml
   wekan:
     root_url: OVERRIDE_VIA_CUSTOM_VALUES
     env:
       - name: WITH_API
         value: "true"
       - name: OIDC_REDIRECTION_ENABLED
         value: "false"
       ...
   ```
   Do NOT add it to the `boards` instance. This restarts the wekan pod in the
   home cluster (brief outage of wekan.spencerslab.com).

### Phase 3 — hivetools wiring (gpu cluster)

8. `charts/hivetools/values.yaml` — [MODIFY] two additions:
   - under `bitwardenIds:` add `wekan-mcp: OVERRIDE_VIA_CUSTOM_VALUES`
   - under `mcp:` (alphabetical position after `sequential-thinking` or
     grouped near `homeassistant`; follow existing comment style):
   ```yaml
   # WeKan MCP Server - kanban boards/lists/cards via the WeKan REST API.
   # In-repo image: containers/wekan-mcp (15 typed tools, no destructive ops).
   # Talks to the home cluster's bot-enabled WeKan instance through its public
   # ingress (WeKan is not in this cluster, so no in-cluster DNS). The token
   # belongs to a dedicated password-based service user — see skills/wekan-api.
   wekan:
     enabled: true
     image: ghcr.io/ownyourio/wekan-mcp:0.0.2
     transport: streamable-http
     mcpPort: 8080
     oidc:
       audience: wekan
     env:
       - name: WEKAN_BASE_URL
         value: "https://wekan.spencerslab.com"
     secrets:
       - name: wekan-mcp
         key: WEKAN_TOKEN
         targetEnvName: WEKAN_TOKEN
     resources:
       limits:
         cpu: '200m'
         memory: '256Mi'
       requests:
         cpu: '50m'
         memory: '64Mi'
     podTemplateSpec:
       spec:
         containers:
           - name: mcp
             securityContext:
               runAsUser: 65532
               runAsGroup: 65532
               runAsNonRoot: true
               allowPrivilegeEscalation: false
               capabilities:
                 drop:
                   - ALL
   ```
   (Tag `0.0.2` assumes exactly one merge of Phase 1; use whatever the
   auto-bump commit produces.)

9. `charts/hivetools/templates/secret-wekan-mcp.yaml` — [CREATE] modeled on
   `secret-homeassistant-mcp.yaml` (token-only variant):
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: wekan-mcp
     namespace: default
   spec:
     refreshInterval: 1h
     target:
       name: wekan-mcp
       creationPolicy: Owner
       template:
         engineVersion: v2
         data:
           WEKAN_TOKEN: "{{ `{{ .token }}` }}"
     data:
       - secretKey: token
         sourceRef:
           storeRef:
             name: bitwarden-login
             kind: SecretStore
         remoteRef:
           key: '{{ index .Values "bitwardenIds" "wekan-mcp" }}'
           property: password
           # Boiler plate needed for ArgoCD to not complain about a mismatch.
           conversionStrategy: Default
           decodingStrategy: None
           metadataPolicy: None
   ```

10. `custom-values/gpu/prod-values.yaml` — [MODIFY] under
    `hivetools.bitwardenIds:` add `wekan-mcp: <UUID>` — the UUID of the
    Bitwarden login item the user creates (username = WeKan service-account
    username, password = bearer token from `POST /users/login`). **User
    action; must exist before this step merges.**

### Phase 4 — skill alignment & docs

11. `skills/wekan-api/SKILL.md` — [MODIFY]
    - Frontmatter `description`: append that this skill also covers the
      `wekan-mcp` server (`containers/wekan-mcp`) exposing these operations as
      MCP tools.
    - Add a section after "When this skill applies":
      **"Prefer the wekan MCP server when it is available"** — in SpencersLab
      the `wekan` MCP server (ToolHive/hivetools, endpoint
      `https://mcp.spencerslab.com/wekan/mcp`, Keycloak OIDC audience `wekan`)
      exposes: `list_boards`, `get_board`, `list_lists`, `list_swimlanes`,
      `list_cards_in_list`, `get_card`, `list_comments`, `create_card`,
      `update_card`, `move_card`, `add_comment`, `add_checklist`,
      `list_checklists`, `get_checklist`, `toggle_checklist_item`. Using it
      keeps the bearer token out of model context. Fall back to this skill's
      raw REST workflow only for operations the MCP server intentionally omits
      (destructive ops, attachments, webhooks, admin/user management, imports)
      or when the MCP server is unavailable.

12. `skills/helm-chart-creation/references/mcp-servers.md` — [CREATE] the
    MCP-specific portion of the helm skill. Content outline (write it from the
    verified hivetools mechanics, citing real files):
    - When to use: adding any MCP server to the lab's ToolHive platform.
      **Do not create a standalone chart or kubectl-apply manifests** —
      `charts/hivetools` is the single home for MCP servers.
    - Architecture recap: `generic-mcpserver.yaml` renders one
      `toolhive.stacklok.dev/v1beta1 MCPServer` per enabled `mcp.<name>`
      entry; ToolHive creates the server StatefulSet (`<name>-0`) + proxy
      Deployment/Service (`mcp-<name>-proxy`); `generic-mcp-ingress.yaml`
      auto-routes `mcp.<domain>/<name>` → proxy; shared Keycloak OIDC via
      `MCPOIDCConfig keycloak` (`templates/mcpoidcconfig-keycloak.yaml`,
      client `mcp`, per-server `audience`); path normalization middleware.
    - Entry fields: `enabled`, `image` (pinned tag; upstream image or in-repo
      via `container-creation`), `transport` (`streamable-http` preferred for
      multi-client HTTP servers; `stdio` gets ToolHive's proxy wrapper),
      `mcpPort` (container port == proxy Service port), `oidc.audience`
      (unique, usually the server name; `oidc: {}`/absent opts out), `env`,
      `args`, `secrets` (`{name, key, targetEnvName}`; `key` = key in the
      ExternalSecret target data), `resources`, `serviceAccount`,
      `podTemplateSpec` (container MUST be named `mcp`; set runAsUser/Group to
      match the image).
    - Secrets recipe: `templates/secret-<name>.yaml` ExternalSecret
      (bitwarden-login `password` / bitwarden-fields / bitwarden-uri stores) +
      `bitwardenIds.<name>: OVERRIDE_VIA_CUSTOM_VALUES` in chart values + real
      UUID in `custom-values/gpu/prod-values.yaml` under `hivetools.bitwardenIds`.
    - What is NOT needed (vs a normal service): no ApplicationSet entry, no
      `ingress.subdomains` proxy entry, no custom-values entry unless secrets —
      hivetools is already wired in `services/gpu/prod/values.yaml`.
    - In-repo image gotchas: tag = `containers/<name>/VERSION` after the
      docker-build auto-bump; bump `mcp.<name>.image` tag on every container
      change.
    - Validation: `helm lint charts/hivetools`;
      `helm template hivetools charts/hivetools --set domain=test.example.com --set bitwardenIds.<name>=test-uuid --set keycloak.realm=test`
      (no `OVERRIDE_*` in output; MCPServer + ExternalSecret + ingress path
      all render); post-sync: `kubectl get pods -l toolhive-name=<name>`,
      server log, `tools/list` through the ingress with an OIDC token.

13. `skills/helm-chart-creation/SKILL.md` — [MODIFY] add
    `references/mcp-servers.md` to the deep-dive list at the top, and one line
    in "### 2. Decide custom vs external chart": MCP servers are neither —
    they are entries in `charts/hivetools` (see `references/mcp-servers.md`).

14. `AGENTS.md` — [MODIFY] add `wekan-api` to the skills registry table
    (load when: WeKan REST API or wekan-mcp work) per its own keep-current
    rule.

## Verification

1. **Container (before merge):** `docker build containers/wekan-mcp/` succeeds
   locally; re-run the smoke test used in planning: venv-install the package,
   run against a mock WeKan (`WEKAN_BASE_URL`/`WEKAN_TOKEN` env), expect
   `connected to WeKan as user_id=...`, then MCP `initialize` → `tools/list`
   → **15 tools** including `list_checklists`/`get_checklist`, and a
   `get_checklist` call returning item ids; bad-token startup exits 1.
2. **Chart:** `helm lint charts/hivetools` and
   `helm template hivetools charts/hivetools --set domain=test.example.com --set bitwardenIds.wekan-mcp=test-uuid --set keycloak.realm=test`
   — output contains the `wekan` MCPServer (image tag, env, secrets ref,
   oidcConfigRef audience `wekan`), the `wekan-mcp` ExternalSecret, and the
   `/wekan` ingress path; `grep -r OVERRIDE_` on the output finds nothing.
3. **Build pipeline:** after Phase 1 merges, confirm the
   `Bump wekan-mcp version to 0.0.2` commit and that
   `ghcr.io/ownyourio/wekan-mcp:0.0.2` exists before Phase 3 merges.
4. **Home cluster:** `wekan` pod restarts with `WITH_API=true`; from anywhere
   with the token: `curl -H "Authorization: Bearer <token>" https://wekan.spencerslab.com/api/user`
   returns the service user (proves WITH_API + token together).
5. **GPU cluster after sync:** ArgoCD `gpu` app Healthy;
   `kubectl get pods -l toolhive-name=wekan` shows `wekan-0` and the
   `wekan-*` proxy Running; `kubectl logs wekan-0` shows
   `connected to WeKan as user_id=...`; ExternalSecret `wekan-mcp` Ready and
   Secret `wekan-mcp` populated.
6. **End-to-end:** `tools/list` via `https://mcp.spencerslab.com/wekan/mcp`
   with a Keycloak token for client `mcp` (audience `wekan`) returns the 15
   tools; one real read (`list_boards`) succeeds.
7. **Trio-equivalent grep:** `grep -n wekan charts/hivetools/values.yaml`
   (mcp entry + bitwardenIds), `ls charts/hivetools/templates/secret-wekan-mcp.yaml`,
   `grep -n wekan-mcp custom-values/gpu/prod-values.yaml` (real UUID, no
   sentinel).

## Risks & open questions

- **User prerequisite (blocking for steps 4/10):** create the WeKan
  service user (password-based, least-privilege board member), obtain the
  token via `POST /users/login` (JSON body; form data is broken), create the
  Bitwarden login item, supply the UUID. Without it the ExternalSecret stays
  unready and the pod CrashLoops on startup validation (visible, not silent).
- `WITH_API=true` change restarts WeKan in the home cluster — brief outage of
  wekan.spencerslab.com; the home cluster is not visible from this kubernetes
  MCP connection, so step 4 verification may need the user's eyes or ArgoCD UI.
- Token rotation is weak by design (old tokens survive re-login, WeKan issue
  #1437); invalidation requires disabling the service user. Accept and
  document; already noted in the skill.
- fastmcp 4.x is out; pins stay `>=3.4,<4` — do not loosen without re-running
  the smoke test (streamable-http API may move).
- Prompt injection: card content is untrusted input to models; destructive
  tools remain intentionally absent from the MCP surface.
- If the image tag in step 8 doesn't match the auto-bumped VERSION (e.g. two
  container merges land first), use the actual tag — verify via the GHCR
  tags list, never guess.
