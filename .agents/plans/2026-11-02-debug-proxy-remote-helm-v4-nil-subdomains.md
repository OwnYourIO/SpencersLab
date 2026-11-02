# 2026-11-02 debug: proxy-remote manifest generation fails under ArgoCD 3.5's helm v4

## Symptom

`services/proxy-remote` Application stuck in ComparisonError since the late-Oct
update round; refresh/sync fails with:

```
Manifest generation error (cached): failed to execute helm template command:
proxy-remote/templates/proxy-ingress.yaml:3:14
  executing ... at <$config.clusterBase>:
  nil pointer evaluating interface {}.clusterBase
```

## Root cause (verified)

Three subdomain keys in `services/proxy-remote/prod/values.yaml` are
value-less (nil) placeholders — `documents:`, `music-player:`, `git:`
(present since 78cdf98ba, 2024-12-21) — and
`templates/proxy-ingress.yaml` dereferences `$config.clusterBase` inside
`range .Values.proxy.subdomains` without a nil guard.

Why it never broke before: ArgoCD passes the same values.yaml again via
`--values`; helm v3's coalescing **deletes** keys whose override value is nil
(`coalesceValues`: "When the YAML value is null, we remove the value's key"),
so the loop never saw them. Timeline of the trigger:

- 2026-10-08 `e07866aee`: argo-cd chart 10.1.4 -> 10.10.0 (base chart;
  baseChartVersion staged to gpu-ai + proxy-backup only).
- 2026-10-25 `8e6482ab2` + `18976eb7f` (base v1.0.202): argo-cd chart
  -> 10.11.1 for all clusters, incl. proxy-remote.
- argo-cd chart 10.10.0/10.11.1 = ArgoCD v3.5.4/v3.5.6 (vs 10.1.4 = v3.4.5).
  ArgoCD 3.5 switched repo-server from helm v3 to **helm v4**
  (`util/helm/cmd.go`: "We now support v4 only"; `hack/tool-versions.sh`:
  `helm4_version=4.2.1`). Helm v4 preserves nil values as literal nulls
  (helm/helm #31644, #32530), so `$config` is nil -> template crash.

Evidence: reproduced ArgoCD's error byte-for-byte with helm v4.2.1 against
the unmodified chart + the same values/custom-values inputs; helm v3.16.4
renders the same inputs fine (nil keys dropped, no ingresses for
documents/music-player/git — the live cluster state since Dec 2024).

## Change

`services/proxy-remote/prod/templates/proxy-ingress.yaml` — skip non-map
entries in the subdomains loop (`{{- if kindIs "map" $config }}` + matching
`{{- end }}`), with a comment explaining the helm v3/v4 nil-merge difference.
`kindIs "map"` (not `typeIs`/`kindIs "map[string]interface {}"` — the latter
matches nothing and silently renders zero ingresses; caught in validation).

Behavioral choice: nil placeholders render **nothing**, exactly like helm v3
did. Giving them `{}` instead would newly render 3 ingresses
(documents/music-player/git.spencerslab.com -> tunnel) — a traffic change,
deliberately avoided.

## Validation

Repo-wide sweep: rendered every `services/*/prod` umbrella chart with both
helm 3.16.4 and 4.2.1 using ArgoCD's exact flag shape (values.yaml +
custom-values + `--set serviceName/domain/clusterName`):

- proxy-remote was the ONLY service broken under helm v4; after the fix it
  renders under both versions.
- post-fix render is byte-identical to pre-fix under helm v3.16.4.
- under helm 4.2.1: 30 Ingresses, none for the nil keys; the only residual
  v3-vs-v4 diffs are renderer artifacts (blank lines) plus three `null`s now
  appearing in the appset's embedded `values:` JSON — proven inherent to
  helm v4 by rendering the HEAD chart with nil keys stripped (identical
  except that one line). base chart v1.0.202 (source 4) also renders clean
  under helm 4.2.1 with the same values; neither base nor traefik-zerotrust
  iterates `proxy.subdomains`, so the nulls are inert.
- `helm lint` passes under 3.16.4 and 4.2.1 (pre-existing sentinel-name
  WARNING without appset params is unrelated).
- backups' local dep-build failure was missing local repo definitions only
  (dl.gitea.com); with repos added it renders clean under helm 4.2.1.

Commands (from repo root):

```sh
# bug reproduction with the ArgoCD-bundled helm
curl -sfL https://get.helm.sh/helm-v4.2.1-linux-amd64.tar.gz | tar xz
(cd services/proxy-remote/prod && helm dependency build . && \
 /path/to/helm-4.2.1 template . --name-template proxy-remote --namespace default \
   --set serviceName=proxy-remote --set domain=spencerslab.com \
   --set clusterName=proxy-remote \
   --values $PWD/values.yaml \
   --values $OLDPWD/../../../custom-values/proxy-remote/prod-values.yaml)
helm lint services/proxy-remote/prod
```

## Landing (user-owned)

Fix must reach `main` to take effect (source 3 targets `targetRevision: main`).
Left uncommitted for review; branch + PR at the user's discretion. After
merge: hard-refresh the `proxy-remote` Application in that cluster's ArgoCD
to clear the cached ComparisonError, then sync. Expect a small diff on
`proxy-remote-appset` (the three `null`s in the embedded values JSON).

## Follow-up (optional, not done)

The same unguarded `range ... $config.clusterBase` pattern exists in the
sibling templates: `services/proxy-local/prod/templates/proxy/proxy-ingress.yaml`
and the ten `services/*/prod/templates/generic-ingress.yaml` files. None of
their values files contain nil entries today (verified by the sweep), so
nothing else is broken — but a future value-less key would take that cluster
down the same way. One-line `kindIs "map"` guards would harden the family.

---

# Update 2026-11-02 (part 2): ESO discovery error after the helm-v4 fix landed

## Symptom

With source 3 rendering again (fix above merged as `1dab94e7d`), sync fails:

```
one or more synchronization tasks are not valid: failed to discover server
resources for group version external-secrets.io/v1
```

## Root cause (verified)

The ExternalSecret comes from source 4 (base chart). Base gates its
external-secrets/cert-manager-DNS01 resources on the presence of
`bitwardenIds.cert-manager-solver-token` — the knob that makes them optional.
History:

- 2025-12-21 `0da74e01a` "Remove externalsecrets from proxy-remote": the
  UUIDs were deliberately removed from `custom-values/proxy-remote/` — this
  cluster runs WITHOUT the external-secrets operator (zero-trust edge; base
  does not install ESO, it arrives per-cluster via `external-secrets*` chart
  entries, which proxy-remote has never had).
- 2026-09-06 `bea8128cd` "Add MCP platform to base" (bot, blanket edit across
  all clusters) re-added `bitwardenIds.cert-manager-solver-token` + a
  `hivetools:` block to proxy-remote's custom-values, re-opening the gate.
- Syncs since then applied everything EXCEPT the undiscoverable
  ExternalSecret task: ArgoCD 3.5.6 (helm 4.2.1) is live on the cluster, and
  the two wildcard Certificates + DNS-01 ClusterIssuer (cert-manager APIs
  exist) were applied and are tracked — the Certificates permanently NotReady
  since their solver secret can never materialize without ESO.
- Base's default `charts:` map (`hivetools`, `reloader`) also feeds
  `appset-charts.yaml`, which had NO disable knob: a `proxy-remote-hivetools`
  child app would deploy ToolHive + the default `kubernetes` MCP server to the
  public edge, with an UNCONDITIONAL ExternalSecret
  (`charts/hivetools/templates/secret-mcp-keycloak-oidc.yaml`) and, per the
  chart's own NOTE, no OIDC on the MCP servers yet.

Audit: proxy-remote is the only umbrella cluster with the solver-token gate
open and no ESO installed (all of dev/gpu/gpu-ai/grow/home/infra/media/
monitoring/proxy-backup/proxy-local install `external-secrets*`; backups/
personal carry no token). `custom-values/cherry` also carries a token but has
no service in this repo.

## Changes (part 2)

1. `custom-values/proxy-remote/prod-values.yaml` — removed the `bitwardenIds:`
   and `hivetools:` blocks (restores the `0da74e01a` intent); comment records
   the invariant so the next blanket sweep doesn't re-add them.
2. `charts/base/templates/appset-charts.yaml` — per-entry opt-out gate
   `{{- if and $chartConfig (ne ($chartConfig.enabled | toString) "false") }}`
   (same nil-safe pattern as hivetools' `generic-mcpserver.yaml`).
3. `services/proxy-remote/prod/values.yaml` — `charts.hivetools.enabled: false`
   (overrides base's default entry for this cluster only).

## Validation (part 2)

- Base render (helm 4.2.1 AND 3.16.4) with edited values: 0 occurrences of
  `external-secrets.io`; no `appName: hivetools` element (`reloader` +
  `traefik-zerotrust` intact); no wildcard Certificates; ClusterIssuer
  letsencrypt-prod falls back to the HTTP-01 branch (`else if` in
  cert-manager-issuer.yaml) — the exact shape live from 2025-12 to 2026-09.
- No-op proof: published base 1.0.202 vs gated local chart render
  BYTE-IDENTICAL for gpu, home, proxy-local, monitoring, infra.
- Before→after resource census (proxy-remote): exactly −2 Certificate,
  −1 ExternalSecret, issuer DNS-01→HTTP-01, −hivetools element.
- Source 3 re-render (both helms): passes; only diff = embedded appset values
  JSON (token gone, hivetools.enabled added).
- `helm lint`: charts/base and services/proxy-remote/prod both pass.

## Landing (user-owned)

1. Merge the three-file change; `release.yaml` publishes base v1.0.203.
2. Merge the renovate "Update Helm release base to v1.0.203" pin bump (same
   flow as `18976eb7f`). Until then the umbrella syncs on 1.0.202 — valid
   (no ESO resources), but the old charts-appset still creates the child
   `proxy-remote-hivetools` app, which sits unsyncable-but-inert (its
   ExternalSecret can't apply) until the bump removes the element and the
   appset controller prunes it.
3. First successful sync will prune the 2 NotReady Certificates and rewrite
   the ClusterIssuer to HTTP-01 — restoring the Dec-2025 steady state; edge
   TLS is unaffected (it never depended on those).

## Follow-up (optional, not done)

- Gate `charts/hivetools/templates/secret-mcp-keycloak-oidc.yaml` on the
  presence of `bitwardenIds.mcp-sso` (it is unconditional today — any
  ESO-less cluster hosting hivetools hits the same discovery failure).
- Part-1 follow-up above (nil guards in the sibling ingress templates) stands.

