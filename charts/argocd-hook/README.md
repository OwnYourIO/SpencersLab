# argocd-hook (chart)

Deploys the `containers/argocd-hook` push-hook relay on the proxy-local hub:
one Deployment + Service on 8080, the `targets.json` fan-out roster
ConfigMap, and the two Bitwarden ExternalSecrets. Stateless by design — no
PVC, no chart Ingress; the only public path is the hub's crowdsec-only
`proxy.subdomains.argocd-hook` entry in `services/proxy-local/prod/values.yaml`
(GitHub cannot pass SSO forward-auth, cf-139 OQ2 ruling).

## File contract (must match containers/argocd-hook/README.md)

- `/config/targets.json` — rendered by `templates/configmap-targets.yaml` as
  `{"allowed_refs": [...], "targets": [11 category entries]}`. `local: true`
  on proxy-local encodes the self-sync-last fan-out ordering; target hosts
  are the live-verified route set: the derived mesh form
  `cluster.<cat>.<domain>` for nine categories, fixed full hosts from the
  `clusterHosts` values map for dev (second apex scifi.farm) and home
  (cluster name home-lab), where the derived form does not resolve. Only
  the derived leg tracks the injected domain — no baked prod domain may
  reach a render.
- `/secrets` — one flat directory projected from both ES targets. Key shape
  is flat filenames, pinned here (the relay resolves
  `--secrets-dir/<tokenKey>`): `github-webhook` (the shared HMAC login item,
  its password field) plus one file per category carrying that cluster's
  `mcp-bot` API token (`argocd-hook-tokens` item custom fields, field name =
  category).

## Values knobs (top-level, consumed by the chart-owned templates)

- `allowedRefs` — ref accept-list (OQ7: widening for a future non-prod stage
  cluster is one values edit, no code change).
- `trackedRepo` — repoURL the relay matches live app sources against.
- `targetCategories` — fan-out roster; also drives the tokens ES keys.
- `clusterHosts` — category -> full route host, only where the live route
  name departs from the derived `cluster.<cat>.<domain>` shape.
- `domain` / `bitwardenIds.*` — injected by the appset / custom-values
  tiers (only `domain` is read by this chart); `bitwardenIds` ships
  `OVERRIDE_VIA_CUSTOM_VALUES`
  sentinels resolved through `custom-values/proxy-local/prod-values.yaml`
  (OQ5: `OVERRIDE_NEEDED` ships through the merge; crash-loop until the
  owner fills real UUIDs is ruled-in behavior).

`helm template proxy-local-argocd-hook charts/argocd-hook --set
domain=test.example.com --set bitwardenIds.argocd-hook-secret=test-uuid
--set bitwardenIds.argocd-hook-tokens=test-uuid` — the release name is what
the ApplicationSet deploys (`<serviceName>-<appName>`), and the hub subdomain
entry consumes exactly this release's Service.
