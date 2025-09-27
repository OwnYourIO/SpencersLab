# Helm Chart Creation Guide for SpencersLab

This document provides a comprehensive guide for creating new Helm charts in the SpencersLab project, based on the Flowise chart pattern and the process used to create LangFlow, n8n, Qdrant, Neo4j, Langfuse, SearXNG, and Supabase charts.

## Overview

The SpencersLab project uses a standardized approach for deploying applications with:
- **App-template dependency** (v4.2.0 from bjw-s-labs)
- **External secrets management** via Bitwarden
- **PostgreSQL clusters** for database-backed applications
- **Multi-container setups** for complex applications
- **ArgoCD ApplicationSets** for deployment automation
- **Traefik ingress** for external access

## Step-by-Step Process

### 1. Research Phase

**Check Dependencies:**
```bash
# Research the application's requirements
curl -s https://hub.docker.com/v2/repositories/{org}/{app}/tags | head -20
# Look for latest stable version

# Check if Redis is needed (common for caching/sessions)
# Check if PostgreSQL is needed (most web apps require a database)
# Check if multi-container setup is needed (auth, storage, etc.)
```

**Key Questions to Answer:**
- What's the latest stable version?
- Does it need PostgreSQL? (Most web apps do)
- Does it need Redis? (For caching, sessions, queues)
- Does it need multiple containers? (Auth, API, Storage, etc.)
- What ports does it use?
- What environment variables are required?
- Does it support initial user/admin setup?

### 2. Directory Structure Creation

```bash
# Create chart directory structure
mkdir -p charts/{app-name}/templates

# Create custom-values directory
mkdir -p custom-values/{app-name}
```

### 3. Chart Metadata Files

**Chart.yaml Template:**
```yaml
apiVersion: v2
name: {app-name}
version: 1.0.0
appVersion: {latest-version}
dependencies:
- name: app-template
  version: 4.2.0
  repository: https://bjw-s-labs.github.io/helm-charts/
```

**Chart.lock Template:**
```yaml
dependencies:
- name: app-template
  repository: https://bjw-s-labs.github.io/helm-charts/
  version: 4.2.0
digest: sha256:951fb29739b425d834afdaff0327fc0ca307dae2f7a296cf832f749647446c35
generated: "{current-timestamp}"
```

### 4. Values.yaml Configuration

**Architecture Decision Matrix:**

| Application Type | PostgreSQL | Redis | Multi-Container | Example |
|-----------------|------------|-------|-----------------|---------|
| Simple Web App | ✅ | ❌ | ❌ | n8n |
| Vector Database | ❌ | ❌ | ❌ | Qdrant |
| Graph Database | ❌ | ❌ | ❌ | Neo4j |
| Complex Web App | ✅ | ✅ | ❌ | Langfuse |
| Search Engine | ❌ | ✅ | ❌ | SearXNG |
| Backend Platform | ✅ | ✅ | ✅ | Supabase |

**Single Container Template:**
```yaml
bitwardenIds:
  {app-name}: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName {app-name}

  controllers:
    {app-name}:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            repository: {org}/{app-name}
            tag: {version}
          env:
            # App-specific environment variables
            TZ: Etc/UTC
          envFrom:
            - secretRef:
                name: *chartName
          probes:
            liveness:
              enabled: true
            readiness:
              enabled: true
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 2Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
  service:
    {app-name}:
      controller: *chartName
      ports:
        http:
          port: {app-port}
  persistence:
    config:
      existingClaim: *chartName
```

**Multi-Container with Redis Template:**
```yaml
# Add Redis container to the containers section:
        redis:
          image:
            repository: redis
            tag: 8.2.0
          resources:
            requests:
              cpu: 10m
              memory: 50Mi
            limits:
              memory: 256Mi
```

**Multi-Container Complex Template (Supabase-style):**
```yaml
# Multiple named containers for different services:
        kong:          # API Gateway
        auth:          # Authentication service
        rest:          # REST API
        realtime:      # WebSocket service
        storage:       # File storage
        imgproxy:      # Image processing
        redis:         # Caching
```

### 5. Template Files

**Required Templates by Architecture:**

**Simple App (no database):**
- `pvc-{app-name}-default.yaml` - Persistent storage
- `secret-{app-name}.yaml` - Application secrets

**App with PostgreSQL:**
- `pg-{app-name}.yaml` - PostgreSQL cluster
- `pvc-{app-name}-default.yaml` - Application storage
- `secret-{app-name}.yaml` - Application secrets
- `secret-pg-{app-name}.yaml` - Database secrets

**PVC Template:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {app-name}
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {size}Gi  # 1Gi for config, 5-10Gi for apps, 20Gi+ for databases
```

**PostgreSQL Cluster Template:**
```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-{app-name}
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6-26
  primaryUpdateStrategy: unsupervised
  storage:
    size: 5Gi
    storageClass: local-path

  monitoring:
    enablePodMonitor: true

  postgresql:
    parameters:
      max_connections: "600"
      shared_buffers: 512MB

  bootstrap:
    initdb:
      database: {app-name}
      owner: {app-name}
      secret:
        name: pg-{app-name}-secret
```

**Application Secret Template:**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {app-name}
spec:
  refreshInterval: 1h
  target:
    name: {app-name}
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # App-specific environment variables
        DATABASE_HOST: "pg-{app-name}-rw"  # If PostgreSQL needed
        DATABASE_NAME: "{app-name}"
        DATABASE_USER: "{{ `{{ .pg_username }}` }}"
        DATABASE_PASSWORD: "{{ `{{ .pg_password }}` }}"
        # Add other secrets as needed
  data:
    # Database credentials (if needed)
    - secretKey: pg_username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "{app-name}-pg" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    # Application-specific secrets
    - secretKey: api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "{app-name}" }}'
        property: api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

**PostgreSQL Secret Template:**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pg-{app-name}-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: pg-{app-name}-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: {{ index .Values "bitwardenIds" "{app-name}-pg" }}
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      remoteRef:
        key: {{ index .Values "bitwardenIds" "{app-name}-pg" }}
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 6. Custom Values Configuration

**custom-values/{app-name}/prod-values.yaml:**
```yaml
bitwardenIds:
  {app-name}: OVERRIDE_NEEDED
  {app-name}-pg: OVERRIDE_NEEDED  # Only if PostgreSQL needed
```

### 7. Infrastructure Updates

**ApplicationSet Update:**
Add to `services/gpu/prod/templates/appset-dev-charts.yaml`:
```yaml
- appName: {app-name}
  namespace: default
  ServerSideApply: "false"
```

**Proxy Configuration Update:**
Add to `services/gpu/prod/values.yaml`:
```yaml
{app-name}:
  serviceName: {app-name}
  service: {app-name}
  port: {app-port}
```

### 8. Common Environment Variables by Application Type

**Database Applications:**
- `DATABASE_URL` or `DB_*` variables
- Connection pooling settings
- SSL/TLS configuration

**Authentication-enabled Applications:**
- `JWT_SECRET` or similar
- `SECRET_KEY` for session management
- User management settings

**Web Applications:**
- `HOST`, `PORT`, `PROTOCOL`
- `BASE_URL` or `SITE_URL`
- CORS and security headers

**Applications with File Storage:**
- Storage backend configuration
- File size limits
- Upload/download paths

### 9. Bitwarden Secret Structure

**Login Secrets (bitwarden-login store):**
- `username` - Database or service username
- `password` - Database or service password

**Field Secrets (bitwarden-fields store):**
- `api_key` - API authentication
- `jwt_secret` - JWT signing key
- `encryption_key` - Data encryption
- `secret_key` - Session management
- `nextauth_secret` - NextAuth.js secret
- `salt` - Password hashing salt

### 10. Port Assignments

**Common Port Patterns:**
- **3000**: Web applications (Langfuse, Supabase)
- **5678**: n8n
- **6333/6334**: Qdrant (HTTP/GRPC)
- **7474/7687**: Neo4j (HTTP/Bolt)
- **7860**: LangFlow
- **8080**: SearXNG, web UIs
- **5432**: PostgreSQL (internal)
- **6379**: Redis (internal)

### 11. Resource Allocation Guidelines

**CPU Requests:**
- Simple apps: 10-100m
- Database/complex apps: 100-200m
- Sidecar containers (Redis): 10m

**Memory:**
- Simple apps: 140-256Mi request, 1-2Gi limit
- Databases: 1Gi+ request, 4Gi+ limit
- Redis sidecars: 50Mi request, 256Mi limit

**Storage:**
- Config only: 1Gi
- Application data: 5-10Gi
- Database storage: 10-20Gi+

### 12. Security Considerations

**Always Include:**
```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

**For Database Applications:**
- Use separate Bitwarden items for app and database credentials
- Construct database URLs in secret templates
- Use read-only root filesystem when possible

### 13. Common Patterns

**Override Patterns:**
- `OVERRIDE_VIA_APPSET` - Set by ApplicationSet (domain, cluster info)
- `OVERRIDE_VIA_CUSTOM_VALUES` - Set in custom-values files
- `OVERRIDE_NEEDED` - Placeholder for actual values

**Naming Conventions:**
- Chart name: lowercase, hyphenated
- Service names: match chart name
- Secret names: `{app-name}` and `pg-{app-name}-secret`
- PVC names: `{app-name}`

### 14. Validation Checklist

**Before Deployment:**
- [ ] Chart.yaml has correct version and appVersion
- [ ] Chart.lock matches app-template version
- [ ] Values.yaml uses proper override patterns
- [ ] All required templates created
- [ ] Bitwarden secret structure documented
- [ ] ApplicationSet updated
- [ ] Proxy configuration added
- [ ] Resource limits appropriate
- [ ] Security contexts configured
- [ ] Probes configured for health checks

### 15. Examples by Complexity

**Simple (Qdrant, Neo4j):**
- Single container
- No external dependencies
- Simple authentication

**Medium (n8n, LangFlow):**
- Single container
- PostgreSQL backend
- User management

**Complex (Langfuse, SearXNG):**
- Multi-container (app + Redis)
- PostgreSQL backend
- Caching layer

**Very Complex (Supabase):**
- Multi-container (5+ services)
- PostgreSQL backend
- Redis caching
- Multiple service ports
- Complex secret management

This guide provides the foundation for creating any new chart following the established SpencersLab patterns.
