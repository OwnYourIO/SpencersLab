# Plan: Add ILIAS (LMS) to the grow cluster, exposed as `training` via proxy-local

## Goal

Deploy ILIAS 11 (srsolutions/ilias image + official MariaDB 11.4 sidecar) on the
grow cluster as a new custom chart `charts/ilias`, wired into the grow
ApplicationSet and reachable at `training.spencerslab.com` through the
proxy-local hub. No proxy-remote entry (mesh/LAN access only, per user).

## Skills

Code agent must load: `helm-chart-creation`, `helm-bjw-s-chart`,
`kubernetes-skill`, `gitops-workflows`.

## MCP Servers

- `readonly-grow-kubernetes` — verify pods/PVCs/services after sync.
- `admin-grow-kubernetes` — only if pod restarts/exec are needed; ask the user
  before use.

## Verified context

- **Repo patterns confirmed:** `charts/playsms` is the live PHP+MariaDB
  precedent (sidecar MariaDB in one pod, two ExternalSecrets `<release>` and
  `<release>-db`, chart PVCs referenced via `existingClaim`,
  `{{ .Release.Name }}` templated values). Cross-cluster proxy pattern
  confirmed via playsms: proxy-local `sms: target: playsms` + home
  `ingress.subdomains.sms` with `serviceName: playsms`.
- **Service naming verified by render test** (app-template 5.0.1): a service
  whose id equals `nameOverride` renders as `<release-name>` (`grow-ilias`);
  any other id renders as `<release-name>-<id>` (`grow-ilias-db`).
- **Full draft chart rendered successfully** in a temp dir: `helm lint` clean,
  Deployment strategy `Recreate` (bjw-s default — avoids RWO rollout
  deadlock), CronJob `*/10 * * * *` with `Forbid`, mounts scoped via
  `advancedMounts`, no `OVERRIDE_*` sentinels in output.
- **Image contract verified** from Docker Hub + `srsolutionsag/docker-ilias-base`
  entrypoint source: built-in DB wait loop (6×10s) covers sidecar startup;
  entrypoint regenerates `ilias.ini.php`/`client.ini.php` from env on every
  container start; auto-setup runs `php cli/setup.php install`; root login is
  user `root` with `ILIAS_ROOT_PASSWORD`; `ILIAS_HTTP_PATH` must be the public
  URL. Volumes: `/var/www/html/public/data` + `/var/iliasdata/ilias`.
  Latest patch-pinned tag: `11.3-php8.4-apache` (no 11.4 image published yet).
- **grow cluster state:** single node, k3s v1.36.2, `local-path` default SC
  (RWO, no expansion), ~2.3GiB RAM free, data disk already holds 431GiB CNPG
  sensors DB. app-template repo standard is 5.0.1 (all 34 charts).
- **Secrets plumbing proven on grow:** `custom-values/grow/prod-values.yaml`
  loads via cluster annotation (hivetools/assistant already work this way).

## Design decisions

1. **Custom chart, not the community `MBcom/ilias-helm`** — it defaults to
   ILIAS 9 and depends on Bitnami subcharts broken by the Bitnami catalog
   deletion. Repo rule: no official chart → custom app-template chart.
2. **MariaDB as sidecar container in the same pod** (playsms precedent),
   official `mariadb:11.4` image with `--character-set-server=utf8
   --collation-server=utf8_general_ci` (ILIAS requires 3-byte utf8). App
   connects via `127.0.0.1`. A second internal Service (`grow-ilias-db`,
   port 3306) exposes the sidecar so the cron CronJob pod can reach it.
3. **Cron as a bjw-s CronJob controller** (guide recommendation): schedule
   `*/10 * * * *` (matches the image's own cron.d), runs
   `su www-data -s /bin/sh -c "exec php /var/www/html/cli/cron.php run-jobs root default"`
   (same user/args as the image's cron.d, avoiding root-owned file creation).
   Self-healing: each job pod's entrypoint regenerates the ini files; jobs
   simply fail until first install completes. `ILIAS_DB_HOST` is overridden to
   `{{ .Release.Name }}-db` (env beats envFrom).
4. **Storage (user-confirmed):** 10Gi `ilias-mysql` PVC + 30Gi `ilias-data`
   PVC (subPaths `webdata` → `/var/www/html/public/data`, `iliasdata` →
   `/var/iliasdata/ilias`). local-path cannot expand PVCs — sizes are final.
5. **Deployment strategy Recreate** (bjw-s default) — RWO PVCs would deadlock
   a rolling update.
6. **No restrictive securityContext on ilias/mariadb containers** — the ILIAS
   image runs apache as root (port 80 + setup chowns), the mariadb entrypoint
   needs root to bootstrap before gosu. Precedent: playsms (commented out).
7. **Secrets:** two Bitwarden login items → two ExternalSecrets (playsms
   pattern). `ILIAS_HTTP_PATH` is constructed in the secret template as
   `https://{{ .Values.publicSubdomain }}.{{ $.Values.domain }}`
   (`publicSubdomain: training`) — domain refs belong in secret templates.
8. **Exposure:** grow ingress `training.spencerslab.com` (+ mesh-facing
   `ilias.spencerslab.com` via `serviceName: ilias`) → proxy-local
   `proxy.subdomains.training: target: ilias` with default middlewares
   (crowdsec + Keycloak forward-auth; ILIAS does its own login — same stance
   as pictaria). **No proxy-remote entry** → not reachable from the public
   internet (external-dns still publishes the CNAME; requests 404 at the edge).

## Changes

### 1. Create `charts/ilias/Chart.yaml`

```yaml
apiVersion: v2
name: ilias
version: 1.0.0
appVersion: "11.3"
dependencies:
- name: app-template
  version: 5.0.1
  repository: https://bjw-s-labs.github.io/helm-charts/
```

Then `helm dependency update charts/ilias` (generates `Chart.lock`).

### 2. Create `charts/ilias/values.yaml`

```yaml
bitwardenIds:
  ilias: OVERRIDE_VIA_CUSTOM_VALUES
  ilias-db: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

# Public subdomain under which ILIAS is reachable via the proxy-local hub
# (proxy.subdomains.training -> target: ilias). Used to build ILIAS_HTTP_PATH
# in templates/secret-ilias.yaml.
publicSubdomain: training

app-template:
  global:
    nameOverride: &chartName ilias

  controllers:
    ilias:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        ilias:
          image:
            repository: srsolutions/ilias
            # renovate: datasource=docker depName=srsolutions/ilias
            tag: 11.3-php8.4-apache
          env:
            TZ: America/Denver
            ILIAS_AUTO_SETUP: "1"
            ILIAS_AUTO_UPDATE: "1"
            ILIAS_CLIENT_NAME: default
            ILIAS_TIMEZONE: America/Denver
            ILIAS_MAX_UPLOAD_SIZE: 256M
            ILIAS_MEMORY_LIMIT: 512M
            # MariaDB runs as a sidecar container in this same pod.
            ILIAS_DB_HOST: 127.0.0.1
          envFrom:
            - secretRef:
                name: "{{ .Release.Name }}"
          probes:
            liveness: &iliasProbes
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 80
                initialDelaySeconds: 30
                periodSeconds: 30
                timeoutSeconds: 5
                failureThreshold: 5
            readiness: *iliasProbes
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 2Gi
          # No restrictive securityContext: the image runs apache as root
          # (binds port 80, chowns files during setup). Precedent: charts/playsms.

        mariadb:
          image:
            repository: mariadb
            # renovate: datasource=docker depName=mariadb
            tag: "11.4"
          args:
            # ILIAS requires a 3-byte utf8 (utf8mb3) collation.
            - --character-set-server=utf8
            - --collation-server=utf8_general_ci
          env:
            TZ: Etc/UTC
            MARIADB_RANDOM_ROOT_PASSWORD: "1"
            MARIADB_DATABASE: ilias
          envFrom:
            - secretRef:
                name: "{{ .Release.Name }}-db"
          probes:
            liveness: &mariadbProbes
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 3306
                initialDelaySeconds: 30
                periodSeconds: 10
                timeoutSeconds: 5
                failureThreshold: 5
            readiness: *mariadbProbes
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 1Gi
          # No restrictive securityContext: the official mariadb entrypoint
          # starts as root and drops privileges itself (gosu).

    ilias-cron:
      type: cronjob
      cronjob:
        # Matches the image's own /etc/cron.d/ilias schedule.
        schedule: "*/10 * * * *"
        concurrencyPolicy: Forbid
        successfulJobsHistory: 3
        failedJobsHistory: 3
      containers:
        cron:
          image:
            repository: srsolutions/ilias
            # renovate: datasource=docker depName=srsolutions/ilias
            tag: 11.3-php8.4-apache
          # Run as the webserver user, exactly like the image's own cron.d entry.
          command:
            - su
            - www-data
            - -s
            - /bin/sh
            - -c
            - exec php /var/www/html/cli/cron.php run-jobs root default
          env:
            TZ: America/Denver
            ILIAS_CLIENT_NAME: default
            # Reach the MariaDB sidecar through the ilias pod's db Service;
            # overrides the 127.0.0.1 that comes from the shared Secret.
            ILIAS_DB_HOST: "{{ .Release.Name }}-db"
          envFrom:
            - secretRef:
                name: "{{ .Release.Name }}"
          resources:
            requests:
              cpu: 10m
              memory: 128Mi
            limits:
              memory: 512Mi

  service:
    # id must equal the nameOverride so the Service renders as <release-name>
    ilias:
      controller: ilias
      ports:
        http:
          port: 80
    # Internal-only endpoint so the cron job can reach the MariaDB sidecar.
    db:
      controller: ilias
      ports:
        mysql:
          port: 3306

  persistence:
    mysql-data:
      existingClaim: ilias-mysql
      advancedMounts:
        ilias:
          mariadb:
            - path: /var/lib/mysql
    ilias-webdata:
      existingClaim: ilias-data
      advancedMounts:
        ilias:
          ilias:
            - path: /var/www/html/public/data
              subPath: webdata
        ilias-cron:
          cron:
            - path: /var/www/html/public/data
              subPath: webdata
    ilias-iliasdata:
      existingClaim: ilias-data
      advancedMounts:
        ilias:
          ilias:
            - path: /var/iliasdata/ilias
              subPath: iliasdata
        ilias-cron:
          cron:
            - path: /var/iliasdata/ilias
              subPath: iliasdata
```

### 3. Create `charts/ilias/templates/secret-ilias.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .Release.Name }}
spec:
  refreshInterval: 1h
  target:
    name: {{ .Release.Name }}
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # ILIAS root user password (Bitwarden login item, username: root).
        ILIAS_ROOT_PASSWORD: "{{ `{{ .root_password }}` }}"
        # MariaDB sidecar lives in the same pod; the cron CronJob overrides
        # ILIAS_DB_HOST with the db Service via its own env.
        ILIAS_DB_HOST: "127.0.0.1"
        ILIAS_DB_USER: "{{ `{{ .db_username }}` }}"
        ILIAS_DB_PASSWORD: "{{ `{{ .db_password }}` }}"
        ILIAS_DB_NAME: "ilias"
        # Public URL through the proxy-local hub (domain injected by the appset).
        ILIAS_HTTP_PATH: "https://{{ .Values.publicSubdomain }}.{{ $.Values.domain }}"
  data:
    - secretKey: root_password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "ilias" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: db_username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "ilias-db" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: db_password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "ilias-db" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 4. Create `charts/ilias/templates/secret-ilias-db.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: "{{ .Release.Name }}-db"
spec:
  refreshInterval: 1h
  target:
    name: "{{ .Release.Name }}-db"
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # MariaDB configuration
        MARIADB_USER: "{{ `{{ .db_username }}` }}"
        MARIADB_PASSWORD: "{{ `{{ .db_password }}` }}"
  data:
    - secretKey: db_username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "ilias-db" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: db_password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "ilias-db" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 5. Create `charts/ilias/templates/pvc-ilias-data.yaml` and `pvc-ilias-mysql.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ilias-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ilias-mysql
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

### 6. Modify `services/grow/prod/values.yaml`

Under `charts:` (internal-chart pattern, after `external-secrets-bitwarden`):

```yaml
  ilias:
    #version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "true"
```

Under `ingress.subdomains:` (after `traefik`):

```yaml
    training:
      serviceName: ilias
      service: grow-ilias
      port: 80
```

### 7. Modify `services/proxy-local/prod/values.yaml`

Under `proxy.subdomains:` (near `pictaria`, own-auth apps section):

```yaml
    # Own auth (ILIAS login) + hub Keycloak forward-auth (default userAuth).
    training:
      target: ilias
```

### 8. Modify `custom-values/grow/prod-values.yaml` (needs user-provided UUIDs)

```yaml
ilias:
  bitwardenIds:
    ilias: <UUID of Bitwarden login item "ilias" (username: root, password: ILIAS root password)>
    ilias-db: <UUID of Bitwarden login item "ilias-db" (username: ilias, password: DB password)>
```

**User prerequisite:** create the two Bitwarden login items before merge and
supply the UUIDs. Without them the ExternalSecrets stay unready.

## Verification

1. `helm lint charts/ilias` and
   `helm template grow-ilias charts/ilias --set domain=spencerslab.com --set bitwardenIds.ilias=test --set bitwardenIds.ilias-db=test`
   — must pass; grep output for `OVERRIDE` (must be zero hits).
2. Trio grep: `grep -rn "ilias" services/grow/prod/values.yaml services/proxy-local/prod/values.yaml custom-values/grow/prod-values.yaml`
   — charts entry, grow ingress entry, proxy entry, custom-values entry all present.
3. After merge + ArgoCD sync (`readonly-grow-kubernetes`):
   - Application `grow-ilias` Synced/Healthy; PVCs `ilias-data`, `ilias-mysql` Bound.
   - Deployment `grow-ilias` Ready (both containers); Service `grow-ilias` (80) and `grow-ilias-db` (3306) exist.
   - `kubectl logs` of the ilias container show `Database connection established`,
     then `ILIAS installed successfully!` on first boot.
   - CronJob `grow-ilias-ilias-cron` exists; first successful job after install completes.
   - Browse `https://training.spencerslab.com` from mesh/LAN → Keycloak login →
     ILIAS login → log in as `root` with the Bitwarden item's password.
   - MariaDB collation check (optional, via admin exec):
     `SHOW VARIABLES LIKE 'collation_server';` → `utf8_general_ci`.

## Risks & open questions

- **Bitwarden UUIDs are a manual prerequisite** (step 8) — the user must create
  the items; until then ExternalSecrets report errors (harmless but noisy).
- **No public access by design** — without a proxy-remote entry,
  `training.spencerslab.com` 404s from the internet (DNS is still published by
  proxy-local's external-dns). Reversible later by adding `training: enabled: true`
  to proxy-remote's `proxy.subdomains`.
- **Disk headroom:** 40GiB of new PVCs on a data disk already holding 431GiB;
  user confirmed sizing. local-path does not enforce size, so monitor actual growth.
- **Memory:** grow node has ~2.3GiB free; combined requests are 1GiB — fits,
  but watch OOM pressure if other workloads grow.
- **Future major upgrades (ILIAS 12):** renovate will offer new image tags.
  ILIAS forbids skipping majors — review ILIAS release notes before accepting
  a major bump; `ILIAS_AUTO_UPDATE` only runs `setup.php update`.
- **`ILIAS_HTTP_PATH` is coupled to the `training` subdomain** — renaming the
  proxy entry requires updating `publicSubdomain` in the chart values.
