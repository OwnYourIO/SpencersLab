# Values & ApplicationSets — Three-Tier Values, Appset Wiring, Go Template Safety

Reference material for the `helm-chart-creation` skill. Read the sections you
need.

## Three-tier value loading

SpencersLab merges values in this priority (low → high):

```yaml
1. Chart's built-in values.yaml             # chart defaults
2. services/<category>/prod/values.yaml     # service-wide defaults  ← REQUIRED tier
3. custom-values/...                        # per-cluster overrides (only via annotations)
```

The shared ApplicationSet templates already load the service values.yaml into
`valueFiles` — preserve that when touching appset templates. A missing service
tier silently drops every default (domain, ingress, bitwardenIds placeholders).

## Service values.yaml structure

Each `services/<category>/prod/values.yaml` provides defaults for ALL charts in
that category:

```yaml
bitwardenIds:
  <service-1>: OVERRIDE_VIA_CUSTOM_VALUES     # real UUID in custom-values/<category>/
  <service-2>-db: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET                   # injected from cluster annotations
clusterName: OVERRIDE_VIA_APPSET
subDomain: <category>-lab

# Charts deployed as separate Applications (see below)
charts:
  <appName>:
    namespace: default
    ServerSideApply: "true"

# Service-wide ingress/proxy configuration
ingress:
  dashboardProvider: homepage                  # optional, gpu uses this
  subdomains:
    <subdomain>:
      service: <category>-<appName>            # release name convention
      port: <port>
      # serviceName: <override>                # optional
      # domain: <other-domain>                 # optional, e.g. scifi.farm

# Chart-specific configuration (optional) — injected into the Application
<appName>:
  app-template:
    controllers: ...
```

## How the ApplicationSets fit together

Two layers:

1. **Per-service appset** — `services/<category>/prod/templates/appset.yaml`
   (matrix: clusters × the service itself). Deploys the service chart
   (`services/<category>/prod/` as a Helm chart path, with its Chart.yaml
   dependencies — the umbrella) plus the published `base` chart.
2. **Per-app appset** — `charts/base/templates/appset-charts.yaml`, rendered by
   the base chart as `<serviceName>-charts-appset`. It ranges over
   `.Values.charts` from the service values.yaml and generates one Application
   per entry:

   ```yaml
   {{- range $appName, $chartConfig := .Values.charts }}
   - appName: {{ $appName }}
     {{- if hasKey $chartConfig "version" }}
     version: {{ $chartConfig.version }}
     {{- end }}
     {{- if hasKey $chartConfig "repository" }}
     repository: {{ $chartConfig.repository }}
     {{- end }}
     {{- if hasKey $chartConfig "chart" }}
     chart: {{ $chartConfig.chart }}
     {{- end }}
     namespace: {{ $chartConfig.namespace | default "default" }}
     ServerSideApply: {{ $chartConfig.ServerSideApply | default "false" | quote }}
     values: {{ merge (dict "shared-storage" (index $.Values "shared-storage")) (index $.Values $appName) | toJson }}
   {{- end }}
   ```

   Source selection in the templatePatch:
   - `hasKey . "version"` → Helm repo source: `chart:`/`repoURL:` from the
     entry (`chart` defaults to `appName`).
   - no `version` → git path source: `<chart.repo.path>/<chart or appName>`
     (i.e. `charts/<name>` in this repo on `main`).

   Release names are `<serviceName>-<appName>` (e.g. `home-karakeep-app`,
   `gpu-n8n`). Proxy `service:` entries must match that name.

## Cluster-wide charts (base's `charts:` list)

A chart that must run on **every cluster** is added to the `charts:` map in
`charts/base/values.yaml` instead of (or in addition to) a service values.yaml.
The service's `charts:` map and base's `charts:` map coalesce per key during
the Helm valueFiles merge, so a key present in both still yields ONE
ApplicationSet element and ONE Application. Live example: `hivetools`
(ToolHive MCP platform, cluster-wide since 2026-09).

Rules for cluster-wide charts:

- **Chart defaults must be generic** — they render on every cluster, including
  small ones. Keep the default server/workload set minimal; per-cluster or
  per-service extras layer on top (below).
- **Per-cluster values/secrets** go in EVERY cluster's
  `custom-values/<category>/prod-values.yaml` under the app's top-level key
  (e.g. `hivetools: bitwardenIds: ...`). They merge into base's `.Values` and
  ride the charts-appset values slice into the Application. Chart-level
  sentinel keys (`OVERRIDE_VIA_CUSTOM_VALUES`) stay in the chart values.yaml —
  e.g. `keycloak.realm` in hivetools remains a sentinel and is set only via
  custom-values, never hardcoded in the chart or a service values.yaml.
- **Single-service extensions**: one service can extend the cluster-wide
  chart via a top-level `<appName>:` block in its
  `services/<category>/prod/values.yaml` (same mechanism as any app config —
  it joins the values slice). Helm deep-merge semantics apply: **maps merge,
  lists replace**. Example: gpu adds 12 MCP servers + 5 Postgres DBs to
  hivetools this way; its `postgresMcp.databases` list fully replaces the
  chart's empty default. Service-specific secret templates belong in
  `services/<category>/prod/templates/` (umbrella level) and read the
  umbrella's TOP-LEVEL `.Values.bitwardenIds` — sentinels in the service
  values.yaml, UUIDs at the top level of the category's custom-values. This
  differs from chart-level templates, which read the chart's own
  `bitwardenIds` map (fed via the app's values slice).
- **Rollout / transitional duplicates**: clusters pin `baseChartVersion` and
  renovate bumps the pin after each base release, so there is a window where
  some clusters run an old base WITHOUT the new `charts:` entry. If the chart
  was previously deployed on a cluster through its service `charts:` entry,
  KEEP that service entry (marked with a "Transitional duplicate of base's
  charts.<name>; remove once every cluster's baseChartVersion includes it"
  comment) until all pins are bumped — otherwise the Application would be
  pruned mid-window. The duplicate key merges to one element, so there is no
  collision. Remove the service entry in a follow-up once all clusters are
  bumped.
- **Prerequisite check for every cluster**: a cluster-wide rollout inherits
  whatever the chart needs (certs, DNS, tokens) on ALL clusters. Verify each
  cluster's custom-values satisfies the gates before the base bump lands —
  e.g. hivetools' ingress needs `cluster-wildcard-cert`, which base only
  issues when `bitwardenIds.cert-manager-solver-token` is present;
  proxy-remote lacked it and needed the token added before rollout.

## subDomain propagation and cluster-scoped hostnames

`appset-charts.yaml` injects `subDomain` into every app's values slice when
the service values.yaml sets it (`subDomain: <category>-lab` is the usual
convention). Apps that need a cluster-scoped hostname — as opposed to the
global `*.<domain>` wildcard — use:

```
<name>.{{ if hasKey .Values "subDomain" }}{{ .Values.subDomain }}{{ else }}{{ .Values.clusterName }}{{ end }}.{{ .Values.domain }}
```

i.e. `mcp.gpu.spencerslab.com` on gpu, `mcp.home-lab.spencerslab.com` on
home. The base chart issues the matching wildcard as `cluster-wildcard-cert`
(`charts/base/templates/cert-manager-wildcard-cert.yaml`); ingresses using
cluster-scoped hosts must reference that secret, not `wildcard-cert`.
`clusterName`/`domain`/`serviceName` reach app charts as helm parameters in
the appset templatePatch; `subDomain` rides the values slice.

## Moving templates between a chart and a service umbrella

Templates that only matter to one service can move from `charts/<name>/templates/`
to `services/<category>/prod/templates/` (and vice versa). The mechanics:

- **`git mv`, no content change** — the template's `.Values` context changes,
  so first confirm every `.Values` reference resolves in the new home. The
  common shift: chart templates read the chart's `bitwardenIds` map (fed via
  the app's values slice); umbrella templates read the umbrella's TOP-LEVEL
  `bitwardenIds` (sentinels in the service values.yaml, UUIDs at the top
  level of the category's custom-values). Add the sentinels/UUIDs at the new
  level as part of the same change.
- **Ownership flips between ArgoCD Applications.** The old Application
  (path source tracking `main`, automated prune) prunes the resource at the
  merge that removes it; the new Application creates it. Cross-Application
  ordering is nondeterministic. For ExternalSecrets, check `deletionPolicy`:
  `Delete` means the target Secret is deleted if the prune lands before the
  adopt (real credential gap); the default `Retain` orphans the target Secret
  harmlessly until re-adoption. Mitigate by force-syncing the adopting app
  first (or disabling selfHeal on the pruning app around the merge).
- **Gated templates**: a template gated on a value the new home always sets
  (e.g. `pvc-knowledge-default.yaml` gated off by gpu's
  `shared-storage.knowledge`) renders nothing after the move — verify both
  gate states render as expected (`--show-only` errors on an empty render,
  which confirms the gate is closed).

## Controlling custom-values loading (cluster secret annotations)

Custom-values files are OPTIONAL and load only when the ArgoCD cluster secret
carries annotations:

```yaml
# Service-wide (ALL apps in the category) — JSON array of URLs:
services.<category>.customValuesUrls: '["https://raw.githubusercontent.com/OwnYourIO/SpencersLab/refs/heads/main/custom-values/<category>/prod-values.yaml"]'

# Per-app (single app):
services.<category>.<appName>.customValuesUrl: "$values/custom-values/<appName>/prod-values.yaml"

# Service-wide inline YAML overrides (merged into valuesObject):
services.<category>.customValues: 'replicas: 2'
services.<category>.base.customValues: 'replicas: 3'
```

Loading order (low → high): chart values → service values.yaml → service-wide
custom-values URL(s) → per-app custom-values URL → inline annotation
`customValues` (merged: base < service < generator values).

Default behavior (no annotations): only chart values + service values load.
Real Bitwarden UUIDs live in `custom-values/<category>/prod-values.yaml` — that
file is private/overridden per cluster; never commit real UUIDs elsewhere.

## The `chart:` field — multiple deployments of one chart

The `chart` field lets you deploy the same Helm chart multiple times with
different release names and configs.

Without `chart:`: `appName` is both release suffix and chart location
(`zigbee2mqtt` → release `<svc>-zigbee2mqtt`, chart `charts/zigbee2mqtt`).
With `chart:`: `appName` is the release suffix, `chart` is the chart location
(`zigbee2mqtt-remote` + `chart: zigbee2mqtt` → release
`<svc>-zigbee2mqtt-remote`, chart `charts/zigbee2mqtt`).

```yaml
# In services/<category>/prod/values.yaml
charts:
  zigbee2mqtt:                       # standard deployment
    namespace: default
    ServerSideApply: "true"

  zigbee2mqtt-remote:                # second instance of the same chart
    namespace: default
    ServerSideApply: "true"
    chart: zigbee2mqtt

  my-custom-deployment:              # works with Helm repos too
    version: 1.0.0
    repository: https://charts.example.com/
    namespace: default
    chart: actual-chart-name
```

Each deployment gets its own configuration via a matching top-level key:

```yaml
zigbee2mqtt:
  bitwardenIds:
    zigbee2mqtt: OVERRIDE_VIA_CUSTOM_VALUES
  app-template:
    controllers:
      zigbee2mqtt:
        containers:
          main:
            env:
              ZIGBEE2MQTT_CONFIG_SERIAL_PORT: /dev/ttyUSB1

zigbee2mqtt-remote:
  bitwardenIds:
    zigbee2mqtt: OVERRIDE_VIA_CUSTOM_VALUES
  app-template:
    controllers:
      zigbee2mqtt:
        containers:
          main:
            env:
              ZIGBEE2MQTT_CONFIG_SERIAL_PORT: /dev/ttyUSB2
```

Best practices:

- Descriptive release names: `zigbee2mqtt-remote` ✅, `zigbee2mqtt-2` ❌.
- Separate proxy subdomains per instance (`zigbee:`, `zigbee-remote:`) pointing
  at the distinct release names.
- Real-world example: `scifi-farm` in `services/home/prod/values.yaml` deploys
  `charts/hugo` as release `home-scifi-farm`.

Troubleshooting:

- `charts/<appName>: app path does not exist` — the `chart:` field isn't set or
  the change isn't committed/synced; ArgoCD looked for a chart named after the
  release.
- Both instances have the same config — missing separate top-level config keys
  matching each appName.
- Ingress conflicts — both instances claim the same subdomain; give each its own.

## Go template safety (ApplicationSets use missingkey=error)

Both appset templates run `goTemplate: true` with
`goTemplateOptions: ["missingkey=error"]` — accessing a missing field FAILS the
ApplicationSet. Always guard optional fields:

```yaml
# ❌ WRONG — errors if the field doesn't exist
{{- if .version }}
chart: "{{ .appName }}"

# ✅ CORRECT
{{- if hasKey . "version" }}
chart: "{{ .appName }}"
```

Common guards:

```yaml
# hasKey — field existence on the generator element
{{- if hasKey . "repository" }}
repoURL: "{{ .repository }}"
{{- end }}

# index — safe map/annotation access
{{- $url := index .metadata.annotations (printf "services.%s.%s.customValuesUrl" .serviceName .appName) }}
{{- if $url }}
- {{ $url }}
{{- end }}

# dig — nested access with default
{{ dig "version" "main" . }}

# default — fallback value
{{ .fieldName | default "fallback" }}
```

Why it matters: prevents ApplicationSet failures, enables optional fields,
keeps backward compatibility when fields are added. Reference implementation:
`charts/base/templates/appset-charts.yaml` and
`services/<category>/prod/templates/appset.yaml` — note the double-escaping
(`` {{ `...` }} ``) for templates rendered through the base chart.

## Integration points (summary)

```yaml
APPLICATIONSET:
  - charts: key in services/<category>/prod/values.yaml  (per-app Applications)
  - Chart.yaml dependencies in services/<category>/prod/ (umbrella)

PROXY:
  - ingress.subdomains in services/<category>/prod/values.yaml
  - service: <category>-<appName>, port: <port>

SECRETS:
  - bitwarden-login: username/password pairs
  - bitwarden-fields: custom fields (API keys, tokens)

DATABASE:
  - CloudNativePG; read-write endpoint pg-<service>-rw

VALUE HIERARCHY:
  - chart defaults < service values < custom-values (annotation-gated)
```
