# Plan: Fix SearXNG upstream engine rate-limiting (gpu) — image bump + GitOps engine policy

## Goal
Stop upstream search engines from suspending the lab's egress IP for up to 24h at
a time, which leaves SearXNG searches sparse or failing. The instance itself is
healthy and its own limiter is disabled — the block is upstream. Fix by: bumping
the image to `2026.10.9-f4822b3fc` (ships anti-bot solvers for startpage/DDG and
modernized brave handling), making engine policy GitOps-managed via the
ExternalSecret-rendered `settings.yml`, keeping brave/startpage/duckduckgo
enabled, disabling only still-IP-blocked engines, and adding mojeek/wiby as
resilient backends. The rollout also clears all cached engine suspensions.

## Skills
Skills the Code agent must load for the work (fresh session — nothing carries
over):
- `helm-chart-creation` — chart editing + ArgoCD wiring conventions
- `helm-bjw-s-chart` — bjw-s app-template values API (persistence/subPath mounts)

## MCP Servers
- `readonly-gpu-kubernetes` — post-sync verification only (pod status, image, logs).
- No `admin-*` servers needed: ArgoCD applies everything and the reloader
  annotation restarts the pod automatically.

## Verified context
Recon performed 2026-10-10 from the repo + live gpu cluster (read-only):

- `charts/searxng/` — chart v1.0.3, app-template 5.0.1 dependency; image pinned
  `searxng/searxng:2026.9.5-c7f3080aa`; redis sidecar in the same pod; PVC
  `searxng` (1Gi) mounted at `/etc/searxng`; ExternalSecret renders Secret
  `searxng` with `SEARXNG_SECRET_KEY` from Bitwarden item
  `b68399c2-ab7c-41fd-9ab0-b3c101672961` (already present in
  `custom-values/gpu/prod-values.yaml`).
- Wiring complete already: chart entry + ingress subdomain in
  `services/gpu/prod/values.yaml` (`searxng` → service `gpu-searxng:8080`),
  proxy hub entry; `mcp-searxng` consumes
  `http://gpu-searxng.default.svc.cluster.local:8080`. No wiring changes needed.
- Live cluster: pod `gpu-searxng-645d7cc6c6-4m42n` 2/2 Running; `/healthz` OK;
  `/config` shows `limiter.enabled: false` (instance is NOT blocking users) and
  84/229 engines enabled (stock defaults).
- Pod logs confirm upstream blocking: google 403 (suspended 86400s), startpage
  CAPTCHA (suspended 86400s), brave 429 (suspended 3600s), duckduckgo CAPTCHA
  (repeated), qwant CAPTCHA. Suspensions are cached in the pod-local Redis
  sidecar (ephemeral — cleared on pod restart).
- Live `/search?format=json` reproduced it: `unresponsive_engines` =
  brave/google/startpage; results only from Wikipedia/DuckDuckGo.
- The PVC's `settings.yml` is the stock auto-generated template (verified live
  config matches defaults — no user customizations to preserve).
- Image entrypoint verified at BOTH deployed commit `c7f3080aa` and target
  commit `f4822b3fc`: `setup()` copies the settings template **only if
  `/etc/searxng/settings.yml` is missing** and never writes to an existing file
  → mounting a Secret-rendered `settings.yml` over the PVC copy is safe.
- Image has **no env-based settings override** (checked
  `searx/settings_loader.py`) — the chart's `SEARXNG_SECRET_KEY` env var is
  never read by the app; the real secret was the random one in the PVC file.
  This plan wires the Bitwarden secret to where it belongs
  (`server.secret_key` in settings.yml).
- Docker Hub 2026-10-10: latest tag `2026.10.9-f4822b3fc` (pushed 2026-10-09,
  digest identical to `latest`). Repo pattern is immutable date-commit tags.
- GitHub compare `c7f3080aa...f4822b3fc` (105 commits) contains the fixes that
  motivate the bump: `[fix] engines: startpage anubis solver`,
  `[fix] engines: duckduckgo web bypass botdetection`,
  `[mod] brave - modernize response handling (#6742)` +
  `[fix] braveapi: set JSON Accept header (#6666)`,
  `[feat] mojeek: automatically solve altcha captchas` (+ generic altcha
  solver), yahoo/pinterest/bing fixes, and new indie engines (littlelayer,
  findborg, xprivo).
- All engine names used in the overrides below were verified to exist in the
  NEW version's default settings (352 engines).
- Repo pattern for single-file config mounts: `persistence.<x>.type:
  secret|configMap` + `globalMounts[].subPath` (see `charts/snapcast`,
  `charts/supabase`, `charts/slskd`).
- Render checks: not performed yet (no chart changes made during planning —
  verification section below covers them).

## Design decisions
1. **Bump image to `2026.10.9-f4822b3fc`** — new version has first-party
   solvers for startpage (Anubis bot wall) and duckduckgo, modernized brave
   response handling, and altcha-captcha-solving for mojeek. This is what makes
   keeping brave + startpage enabled viable.
2. **Keep brave, startpage, duckduckgo, bing-media, torrent engines enabled**
   (user decision). They run against the new solvers.
3. **Disable only engines with IP-reputation blocks and no upstream fix**:
   google family (403, no solver), qwant family (CAPTCHA), yahoo news, reuters,
   pinterest. Re-enabling later = one-line git change.
4. **Enable `mojeek` + `wiby`** — disabled by default upstream; mojeek is now
   captcha-resilient. New-version engines `littlelayer`/`findborg`/`xprivo` are
   candidate follow-ups if results feel thin (not enabled by default — new).
5. **Engine policy + secret_key rendered by the existing ExternalSecret**
   (`secret-searxng.yaml`) into a `settings.yml` key — keeps secrets out of
   ConfigMaps, reuses the existing Bitwarden item, and finally lands the
   Bitwarden secret where the app reads it.
6. **Mount rendered `settings.yml` from Secret `searxng` with subPath** over
   the PVC mount — GitOps-owned policy; the PVC's stock auto-generated copy
   becomes dormant (removing the mount restores it). subPath mounts refresh
   only on pod restart — the existing reloader annotation covers that.
7. **Suspension cache clears automatically**: Deployment spec change +
   secret-content change create a fresh pod → fresh ephemeral Redis sidecar →
   all cached 24h suspensions gone.
8. No chart `version` bump (CI-owned on merge); `appVersion` updated to match
   the new image.

## Changes
Ordered steps:

1. `charts/searxng/values.yaml` — [MODIFY] image tag bump:
   ```yaml
             image:
               repository: searxng/searxng
               # Immutable date-commit tag verified 2026-10-10 against Docker Hub
               # (digest matches searxng/searxng:latest at that time).
               tag: 2026.10.9-f4822b3fc
   ```
2. `charts/searxng/values.yaml` — [MODIFY] add the settings mount under
   `app-template.persistence` (alongside the existing `config` PVC entry):
   ```yaml
     persistence:
       config:
         existingClaim: *chartName
         globalMounts:
           - path: /etc/searxng
       settings:
         # GitOps-managed settings.yml rendered by the ExternalSecret
         # (secret-searxng.yaml): Bitwarden secret_key + engine policy.
         # The image entrypoint never writes to an existing settings.yml
         # (verified at image commit f4822b3fc), so shadowing the PVC copy
         # is safe. subPath mounts refresh only on pod restart — the
         # reloader annotation covers that.
         type: secret
         name: *chartName
         globalMounts:
           - path: /etc/searxng/settings.yml
             subPath: settings.yml
   ```
3. `charts/searxng/Chart.yaml` — [MODIFY] `appVersion: 2026.9.5` →
   `appVersion: 2026.10.9`. Leave `version: 1.0.3` untouched (CI bumps it).
4. `charts/searxng/templates/secret-searxng.yaml` — [MODIFY] add a
   `settings.yml` key to `target.template.data` (keep the existing
   `SEARXNG_SECRET_KEY` line; same backtick-escaping style):
   ```yaml
         data:
           SEARXNG_SECRET_KEY: "{{ `{{ .secret_key }}` }}"
           settings.yml: |
             # GitOps-managed SearXNG settings, merged over built-in defaults.
             # Image 2026.10.9 has solvers for startpage (anubis) and mojeek
             # (altcha), plus a duckduckgo botdetection bypass — keep those
             # enabled. Engines disabled below are IP-blocked with no upstream
             # fix (verified 2026-10-10). See plan
             # 2026-10-10-bug-fix-searxng-upstream-ratelimits.md before
             # re-enabling anything.
             use_default_settings: true
             server:
               secret_key: "{{ `{{ .secret_key }}` }}"
               image_proxy: true
             engines:
               # Resilient web-search backends (disabled by default upstream)
               - name: mojeek
                 disabled: false
               - name: wiby
                 disabled: false
               # --- upstream engines that IP-block us, no solver available ---
               - name: google
                 disabled: true
               - name: google images
                 disabled: true
               - name: google news
                 disabled: true
               - name: google videos
                 disabled: true
               - name: google scholar
                 disabled: true
               - name: qwant news
                 disabled: true
               - name: qwant images
                 disabled: true
               - name: qwant videos
                 disabled: true
               - name: yahoo news
                 disabled: true
               - name: reuters
                 disabled: true
               - name: pinterest
                 disabled: true
   ```
   Note: `brave*`, `startpage*`, `duckduckgo`, `bing images/news/videos`, and
   the torrent engines are intentionally NOT in this list → remain enabled at
   stock defaults.
5. No other files change. Do not touch `services/gpu/prod/values.yaml`,
   `custom-values/gpu/prod-values.yaml`, proxy entries, or Chart `version`.

## Verification
Before finishing (Code agent):
1. `helm lint charts/searxng`
2. `helm template charts/searxng --set domain=searxng.example.com --set bitwardenIds.searxng=00000000-0000-0000-0000-000000000000`
   — confirm:
   - ExternalSecret contains the `settings.yml` key with the
     `{{ .secret_key }}` placeholders left intact (escaped through Helm).
   - Deployment shows image `searxng/searxng:2026.10.9-f4822b3fc`.
   - Pod spec mounts the PVC at `/etc/searxng` AND the secret `searxng` file
     at `/etc/searxng/settings.yml` (subPath).
3. After merge + ArgoCD sync (via `readonly-gpu-kubernetes`):
   - gpu app Synced/Healthy; `gpu-searxng-*` pod 2/2 Running, both containers
     on the new image tag.
4. Instance checks:
   - `https://searxng.spencerslab.com/healthz` → `OK`
   - `https://searxng.spencerslab.com/config` → brave / startpage /
     duckduckgo / mojeek `enabled: true`; google / qwant `enabled: false`.
   - `https://searxng.spencerslab.com/search?q=kubernetes&format=json` → 200
     with results; `unresponsive_engines` must not list brave/google/startpage
     suspensions (fresh Redis + new solvers).

## Risks & open questions
- brave/startpage post-bump is a live experiment: the solvers are new. If they
  still get suspended from this IP, re-disable via a one-line git change —
  policy is now GitOps-managed, so iterating is cheap.
- No Google results (IP-reputation block; no solver exists). Web search =
  brave + startpage + duckduckgo + mojeek/wiby + knowledge engines. If that
  feels thin, follow-up options: enable new-version engines
  `littlelayer`/`findborg`/`xprivo`, or configure a Brave Search API key for
  the brave engine.
- The PVC's old `settings.yml` stays dormant. Verified stock (no
  customizations); removing the `settings` mount restores it.
- `missing config file: /etc/searxng/limiter.toml` log warning persists —
  harmless, limiter stays disabled.
- No new secrets committed; Bitwarden UUID already lives in custom-values.
