# Storage & Secrets — Bitwarden Stores, Env Vars, Shared Storage

Reference material for the `helm-chart-creation` skill. Read the sections you
need.

## Bitwarden secret structure

SpencersLab uses two Bitwarden SecretStores. Which fields you read depends on
the store:

**`bitwarden-login` store** (Bitwarden Login-type items):

- `username` — database or service username
- `password` — database or service password

**`bitwarden-fields` store** (custom fields on any Bitwarden item):

- `api_key` — API authentication token
- `jwt_secret` — JWT signing key
- `encryption_key` — data encryption key
- `secret_key` — session/app secret
- `nextauth_secret` — NextAuth.js secret
- `salt` — password hashing salt
- (any other custom field name your app needs)

The `bitwardenIds` map in values.yaml maps a logical name (e.g.
`<service-name>`, `<service-name>-db`) to the UUID of the Bitwarden item. Both
stores can read from the SAME item — the store type just changes *which* part
of the item is accessed (login credentials vs custom fields).

Placeholder `OVERRIDE_VIA_CUSTOM_VALUES` in `services/<category>/prod/values.yaml`;
real UUIDs in `custom-values/<category>/prod-values.yaml`. Common patterns:

- **Single item** (e.g. n8n): one UUID holds app + db credentials.
- **Separate DB item** (e.g. langflow): `<svc>-db` UUID for the database login,
  `<svc>` UUID for app fields.
- **Shared infra secret**: one UUID (e.g. the cert-manager solver token)
  referenced by several categories' custom-values files.

## Common environment variables by application type

Use during the research phase to predict what env vars (and thus secrets) to
expect. Actual names vary — consult the app's Docker image docs.

**Database-backed applications:**

- `DATABASE_URL` (single connection string) or discrete
  `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`
- Connection pooling settings (pool size, timeouts)
- SSL/TLS configuration for DB connections

**Authentication-enabled applications:**

- `JWT_SECRET` / `JWT_SIGNING_KEY`
- `SECRET_KEY` / `SESSION_SECRET` for session management
- `NEXTAUTH_SECRET` / `NEXTAUTH_URL` for NextAuth.js apps
- User management / OAuth settings

**Web applications:**

- `HOST`, `PORT`, `PROTOCOL`
- `BASE_URL` / `SITE_URL` / `PUBLIC_URL`
- CORS origins, security headers, cookie domain

**Applications with file storage:**

- Storage backend selector (local vs S3 vs SeaweedFS)
- File size limits (`MAX_UPLOAD_SIZE`, etc.)
- Upload/download path configuration
- Object-storage credentials (access key / secret key / endpoint / bucket)

## Shared storage pattern (SeaweedFS)

Charts support both default local storage and shared storage backends through
configuration overrides:

1. **Default behavior**: charts create local PVCs (dev/testing).
2. **Production override**: service-level config switches to shared storage.
3. **Consistent naming**: PVCs keep the same name regardless of backing store.
4. **Conditional templates**: chart templates create PVCs only when no shared
   storage is configured.

### 1. Chart values

```yaml
# charts/<service>/values.yaml
shared-storage: {}  # empty by default — enables safe template access

# Documented override shape:
# shared-storage:
#   <storage-name>:
#     pvc-name: <storage-name>-shared
#     provider: seaweedfs
```

### 2. Conditional PVC template in the chart

```yaml
# charts/<service>/templates/pvc-<storage>-default.yaml
{{- if not (index .Values "shared-storage" "<storage-name>") }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <storage-name>-shared
  namespace: {{ .Values.namespace }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
{{- end }}
```

Use `index .Values "shared-storage" "<storage-name>"` — direct access
(`.Values.shared-storage.<name>`) fails when the parent is nil, and appsets run
with `missingkey=error`. Only create the PVC when shared-storage config is NOT
present; PVC names match across default and shared implementations.

### 3. Service-level override

```yaml
# services/<category>/prod/values.yaml
<chart-name>:
  shared-storage:
    <storage-name>:
      pvc-name: <storage-name>-shared
      provider: seaweedfs
```

This overrides the chart's empty `shared-storage: {}`, skips the default PVC,
and switches workloads to the service-provided shared PVC.

### 4. Service-level shared storage PV/PVC

```yaml
# services/<category>/prod/templates/pvc-<storage>-seaweedfs.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <storage-name>-shared
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 3000Gi
  csi:
    driver: seaweedfs-csi-driver
    volumeHandle: <storage-name>-shared
    volumeAttributes:
      collection: <collection-name>
      replication: "003"
      path: /buckets/<collection-name>/<storage-name>
    readOnly: false
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <storage-name>-shared
spec:
  storageClassName: ""
  volumeName: <storage-name>-shared
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 3000Gi
```

### Worked example: hivetools knowledge storage

Read these files:

- `charts/hivetools/values.yaml` — `shared-storage: {}` default
- `charts/hivetools/templates/pvc-knowledge-default.yaml` — conditional 10Gi PVC
- `services/gpu/prod/values.yaml` — `hivetools.shared-storage.knowledge` override
- `services/gpu/prod/templates/pvc-knowledge-seaweedfs.yaml` — 3000Gi SeaweedFS
  PV/PVC (`collection: documents`, `path: /buckets/documents/knowledge`)

Usage flow: default → chart creates local 10Gi PVC; production → service sets
`shared-storage.knowledge`, chart PVC is skipped, workloads mount the shared
3000Gi SeaweedFS PVC — always by the name `knowledge-shared`.
