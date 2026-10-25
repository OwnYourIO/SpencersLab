# bug: traefik chart v42 values schema rejects `logs:`

## Symptom

After renovate's traefik dependency bump 39.0.9 → 42.1.3 (PR #803, merged
2026-10-25), ArgoCD failed to generate manifests for the traefik chart apps:

```
Error: values don't meet the specifications of the schema(s) in the following chart(s):
traefik:
- at '': additional properties 'logs' not allowed
```

The running traefik pods were unaffected (ArgoCD stays on last synced state),
but the apps were stuck in ComparisonError and could not sync anything new.

## Root cause

Traefik chart v42 ships a strict `values.schema.json`
(`additionalProperties: false` at the top level) and split the old `logs`
value: general log config moved to `log` and access logs moved to a
top-level `accessLog` key. Both wrapper charts still passed the old shape:

- `charts/traefik/values.yaml` — `traefik.logs.access.enabled: true`
- `charts/traefik-zerotrust/values.yaml` — same

## Fix

Migrate both to the v42 shape (behavior-preserving: access logs stay on,
the commented-out DEBUG hint is kept under the new `log` key):

```yaml
# log:
#   level: DEBUG
accessLog:
  enabled: true
```

No other wrapper values violate the v42 schema (verified by rendering);
`custom-values/proxy-local/prod-values.yaml` only sets wrapper-level keys
(`keycloak.realm`, `bitwardenIds`) which never reach the subchart.

## Validation

- `helm lint charts/traefik charts/traefik-zerotrust` → 0 failed.
- `helm template` for both wrappers (replicating the ArgoCD invocation:
  `--name-template`, `--namespace kube-system`, `--set clusterName/…`,
  `--include-crds --api-versions monitoring.coreos.com/v1`) → exit 0;
  rendered deployment args include `--accesslog=true`.
- The ServiceMonitor lint note ("deploy monitoring.coreos.com/v1 first") is
  environmental; ArgoCD passes the CRD via `--api-versions`.

## After merge

ArgoCD regenerates manifests on the next poll (the generation error is
cached); force-refresh the app if it doesn't clear. The sync will then apply
the v42 chart — expect a traefik rollout (chart 39 → 42 crosses several
upstream versions) and watch the pod startup, since plugins are re-downloaded
from plugins.traefik.io at boot (`--experimental.abortonpluginfailure=true`
makes that a crashloop-until-egress-works by design).