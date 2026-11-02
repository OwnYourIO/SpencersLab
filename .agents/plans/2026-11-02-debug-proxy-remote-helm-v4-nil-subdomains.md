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
