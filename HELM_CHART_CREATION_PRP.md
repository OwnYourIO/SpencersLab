name: "Helm Chart Creation PRP for SpencersLab"
description: |

## Purpose
PRP template optimized for AI agents to create Helm charts for SpencersLab infrastructure with sufficient context and validation to achieve working deployments through iterative refinement.

## Core Principles
1. **Context is King**: Include ALL necessary documentation, examples, and caveats from existing charts
2. **Validation Loops**: Provide executable tests/lints the AI can run and fix
3. **Information Dense**: Use keywords and patterns from the SpencersLab codebase
4. **Progressive Success**: Start simple, validate, then enhance
5. **Follow SpencersLab Patterns**: Maintain consistency with existing infrastructure

---

## Goal
Create a new Helm chart for {SERVICE_NAME} that integrates seamlessly with SpencersLab's GitOps infrastructure, follows established patterns, and deploys successfully via ArgoCD ApplicationSets.

## Why
- **Infrastructure Consistency**: Maintain uniform deployment patterns across all services
- **GitOps Integration**: Enable automated deployment via ArgoCD ApplicationSets
- **Secret Management**: Integrate with Bitwarden-based secret management
- **Multi-cluster Support**: Deploy across development and production clusters

## What
A complete Helm chart package including Chart.yaml, values.yaml, templates, custom-values, and ApplicationSet integration that follows SpencersLab patterns.

### Success Criteria
- [ ] Chart validates with `helm lint charts/{service-name}`
- [ ] Chart renders without errors with `helm template charts/{service-name}`
- [ ] ApplicationSet includes the new service
- [ ] Proxy configuration routes traffic correctly
- [ ] Secrets integrate with Bitwarden
- [ ] Service deploys successfully in target namespace

## All Needed Context

### Documentation & References
```yaml
# MUST READ - Include these in your context window
- url: https://artifacthub.io/
  why: Check for official charts before creating custom ones
  
- url: https://kubesearch.dev/
  why: Alternative chart discovery platform
  
- file: charts/flowise/
  why: Reference implementation pattern for database-backed services
  
- file: charts/langfuse/
  why: Multi-container pattern with Redis sidecar
  
- file: charts/archon/
  why: Complex multi-container service with inter-service communication

- file: services/gpu/prod/templates/appset-dev-charts.yaml
  why: ApplicationSet integration pattern for AI/ML services
  
- file: services/home/prod/values.yaml
  why: Multi-container patterns (paperless example)
  
- doc: https://bjw-s-labs.github.io/helm-charts/docs/app-template/
  section: app-template usage patterns and configuration options
  critical: Understanding controller, service, and persistence patterns

- docfile: /tmp/bjw-s-helm-charts/charts/other/app-template/README.md
  why: Official app-template documentation and configuration examples
```

### Current SpencersLab Chart Structure
```bash
charts/
├── {23 existing charts analyzed}
├── 389ds/              # LDAP directory service
├── archon/             # Multi-container AI service (4 containers)
├── base/               # Core cluster services
├── external-secrets-bitwarden/  # Secret management
├── flowise/            # AI workflow builder (PostgreSQL + app)
├── langflow/           # AI workflow platform (PostgreSQL + app)
├── langfuse/           # LLM observability (PostgreSQL + Redis + app)
├── n8n/                # Workflow automation (PostgreSQL + app)
├── neo4j/              # Graph database (self-contained)
├── qdrant/             # Vector database (self-contained)
├── searxng/            # Search engine (Redis + app)
├── supabase/           # Backend-as-a-service (PostgreSQL + multi-container)
└── [10 other services]

services/
├── gpu/prod/           # AI/ML workloads ApplicationSets
├── home/prod/          # Home automation ApplicationSets
├── infra/prod/         # Infrastructure ApplicationSets
├── media/prod/         # Media services ApplicationSets
├── monitoring/prod/    # Monitoring ApplicationSets
└── [5 other categories]
```

### Desired Chart Structure for {SERVICE_NAME}
```bash
charts/{service-name}/
├── Chart.yaml          # Chart metadata with app-template dependency
├── Chart.lock          # Dependency lock file
├── values.yaml         # Main configuration with app-template structure
└── templates/
    ├── pg-{service}.yaml           # PostgreSQL cluster (if needed)
    ├── pvc-{service}-default.yaml  # Persistent storage (if needed)
    ├── secret-{service}.yaml       # External secret for app config
    └── secret-db-{service}.yaml    # Database credentials (if needed)

custom-values/{service-name}/
└── prod-values.yaml    # Bitwarden ID overrides

# ApplicationSet integration in appropriate service category
# Proxy configuration in corresponding values.yaml
```

### Known Gotchas of SpencersLab Infrastructure
```yaml
# CRITICAL: All charts use app-template v4.2.0 dependency
# CRITICAL: PostgreSQL clusters use CloudNativePG operator
# CRITICAL: All secrets use external-secrets with Bitwarden integration
# CRITICAL: Domain references must be in secret templates, not values.yaml
# CRITICAL: Use OVERRIDE_VIA_CUSTOM_VALUES pattern for Bitwarden IDs
# CRITICAL: ApplicationSet integration varies by service category
# CRITICAL: Service names must match chart names for proper routing
# CRITICAL: Multi-container services use localhost for intra-pod communication
# CRITICAL: PostgreSQL connection uses pg-{service}-rw for read-write access
# CRITICAL: Redis sidecars use standard redis:8.2.0 image
# CRITICAL: All containers drop ALL capabilities for security
# CRITICAL: Each chart MUST have a custom-values/{chart}/prod-values.yaml file (even if empty)
# CRITICAL: ApplicationSet valueFiles must include service values.yaml for defaults
# CRITICAL: Service values.yaml provides default configuration for all charts in that service
```

## Implementation Blueprint

### Pre-Creation Analysis (CRITICAL - DO THIS FIRST)

**STEP 1: Check for Official Charts**
Before creating any custom chart, you MUST check if an official chart already exists:

```yaml
Official Chart Sources:
  1. Artifact Hub: https://artifacthub.io/
     - Search for {service-name}
     - Check for official/verified publishers
     - Review chart quality and maintenance status
  
  2. KubeSearch: https://kubesearch.dev/
     - Alternative chart discovery
     - May find charts not on Artifact Hub
  
  3. Official Documentation:
     - Check {service-name} official docs
     - Look for Helm installation sections
     - Verify chart repository URLs

Decision Matrix:
  - Official chart EXISTS and maintained → USE IT (add to service values.yaml under charts: key)
  - Official chart outdated/unmaintained → Evaluate: fix official chart vs custom
  - No official chart → Proceed with custom app-template chart

IMPORTANT: Only proceed with custom chart creation if no suitable official chart exists.

Chart Dependency Location Rules:
  - Custom charts in charts/ folder → Add to service Chart.yaml as dependencies
  - External/official charts from remote repos → Add to service values.yaml under charts: key
  - Never mix: Don't add external charts to Chart.yaml, don't add local charts to values.yaml
```

**STEP 2: Architecture Analysis**
Once you've confirmed no official chart exists, analyze the service requirements:

```yaml
Architecture Analysis:
  - Single container: Simple app-template pattern
  - Multi-container: Complex app-template with multiple containers
  - Database requirement: PostgreSQL cluster needed?
  - Storage requirement: PVC needed for persistent data?
  - Dependencies: Redis, other services needed?

Environment Variables Research:
  - Check official Docker image documentation
  - Review docker-compose examples
  - Identify database connection patterns
  - Identify authentication/secret requirements
  - Identify service discovery configuration
```

### Architecture Decision Matrix

Use this table to quickly determine the shape of the chart based on the application type:

| Application Type    | PostgreSQL | Redis | Multi-Container | Example  |
|---------------------|------------|-------|-----------------|----------|
| Simple Web App      | ✅         | ❌    | ❌              | n8n      |
| Vector Database     | ❌         | ❌    | ❌              | Qdrant   |
| Graph Database      | ❌         | ❌    | ❌              | Neo4j    |
| Complex Web App     | ✅         | ✅    | ❌              | Langfuse |
| Search Engine       | ❌         | ✅    | ❌              | SearXNG  |
| Backend Platform    | ✅         | ✅    | ✅              | Supabase |

### Complexity Tiers (Reference Charts)

Charts tend to fall into one of four complexity tiers. Match your new service to the closest tier and use that chart as a starting reference:

- **Simple (Qdrant, Neo4j)**: Single container, no external dependencies, simple auth (API key or none).
- **Medium (n8n, LangFlow)**: Single container + PostgreSQL backend, user management, JWT/encryption secrets.
- **Complex (Langfuse, SearXNG)**: Multi-container (app + Redis sidecar), PostgreSQL backend, caching layer.
- **Very Complex (Supabase, Archon)**: Multiple specialized containers (5+), PostgreSQL backend, Redis, multiple service ports, complex secret management.


### Chart Dependency Configuration (CRITICAL DECISION POINT)

**BEFORE implementing tasks, decide:** Is this a custom chart or external chart?

#### Decision Tree:
```
Is there an official Helm chart?
├─ NO → Create custom chart
│  └─ Follow Implementation Tasks (Custom Chart Path)
│
└─ YES → Use external chart
   └─ Follow External Chart Integration (values.yaml Path)
```

### Implementation Path 1: Custom Charts (Create in `charts/` folder)

**When:** No official chart exists, you're creating a custom app-template-based chart

```yaml
Task 1 - Directory Structure:
CREATE charts/{service-name}/templates/

Task 2 - Core Chart Files:
CREATE charts/{service-name}/Chart.yaml:
  - PATTERN: Follow existing Chart.yaml structure
  - MODIFY: name, version (1.0.0), appVersion (latest)
  - PRESERVE: app-template dependency v4.2.0

CREATE charts/{service-name}/Chart.lock:
  - MIRROR: Existing Chart.lock files
  - MODIFY: generated timestamp
  - KEEP: app-template dependency and digest

Task 3 - Values Configuration:
CREATE charts/{service-name}/values.yaml:
  - PATTERN: Follow single or multi-container template
  - INJECT: Service-specific environment variables
  - PRESERVE: Standard security contexts and resource limits
  - MODIFY: Image repository, tag, and ports

Task 4 - Template Files (conditional):
IF PostgreSQL needed:
  CREATE charts/{service-name}/templates/pg-{service}.yaml
  CREATE charts/{service-name}/templates/secret-db-{service}.yaml

IF persistent storage needed:
  CREATE charts/{service-name}/templates/pvc-{service}-default.yaml

ALWAYS CREATE:
  CREATE charts/{service-name}/templates/secret-{service}.yaml

Task 5 - Service Integration:
ADD to service's Chart.yaml as dependency:
  - Location: services/{category}/prod/Chart.yaml
  - Add as app-template alias dependency
  - Update Chart.lock

Task 6 - Infrastructure Integration:
MODIFY corresponding proxy configuration:
  - ADD ingress subdomain configuration
  - SPECIFY service name and port mapping
```

### Implementation Path 2: External Charts (Add to values.yaml)

**When:** Official chart exists, using external Helm repository

```yaml
Task 1 - No Chart Creation:
SKIP creating charts/{service-name}/ directory
DO NOT create custom chart files

Task 2 - Service Values Configuration:
ADD to services/{category}/prod/values.yaml under charts: key:
  {chart-name}:
    version: {version} # renovate: datasource=helm registryUrl={repo-url}
    repository: {repo-url}
    namespace: default
    ServerSideApply: "true/false"

Task 3 - Chart-Specific Configuration (if needed):
ADD chart configuration under same chart-name key:
  {chart-name}:
    version: ...
    repository: ...
    # Chart-specific values below:
    config:
      # Chart-specific settings
    ingress:
      enabled: false  # Use SpencersLab's generic-ingress instead

Task 4 - Service-Level Resources (if needed):
CREATE in services/{category}/prod/templates/ if needed:
  - PostgreSQL clusters
  - External secrets
  - PVCs
  - ConfigMaps

Task 5 - Infrastructure Integration:
MODIFY corresponding proxy configuration:
  - ADD ingress subdomain configuration
  - SPECIFY service name and port mapping
```

### Comparison: Custom vs External Charts

| Aspect | Custom Chart | External Chart |
|--------|-------------|----------------|
| **Chart Files** | Create in `charts/{name}/` | No chart creation |
| **Location** | `charts/` directory | Remote repositories |
| **Service Chart.yaml** | Add as dependency with alias | No modification |
| **Service values.yaml** | Configure chart-specific settings | Add under `charts:` key + settings |
| **Templates** | Create all templates | Create only service-level resources |
| **Deployment** | Via Helm dependency | Via ApplicationSet chart reference |
| **Version Control** | Locked in `Chart.lock` | Inline version in `values.yaml` |
| **Renovate Support** | Automatic via `Chart.yaml` | Requires `# renovate:` comment annotation |
| **Use Case** | Custom app-template-based charts | Official/external charts |
| **Example** | paperless, karakeep, actualbudget | postiz, seaweedfs, mosquitto |

### Why This Separation?

1. **Custom charts** are treated as first-class dependencies that need to be built with the service (they live alongside the service's other Helm dependencies in `Chart.yaml`).
2. **External charts** are referenced at deployment time by ApplicationSet, so they don't need to be pulled during `helm dependency update`.
3. **Helm limitations** prevent mixing local chart paths (relative `file://` refs) with remote chart dependencies in a clean, portable way inside `Chart.yaml`.
4. **ArgoCD ApplicationSet** can dynamically reference external charts (via `chart:` + `repoURL:` fields generated from `values.yaml`) without requiring them as Helm dependencies at all.


### Real-World Examples

#### Example 1: Custom Chart (Karakeep)
```yaml
# services/home/prod/Chart.yaml
dependencies:
- name: app-template
  version: 4.3.0
  repository: https://bjw-s-labs.github.io/helm-charts/
  alias: karakeep

# services/home/prod/values.yaml
karakeep:
  # Chart configuration for karakeep
  global:
    nameOverride: karakeep
  controllers:
    karakeep:
      containers:
        main:
          image:
            repository: ghcr.io/karakeep-app/karakeep
            tag: 0.28.0
```

#### Example 2: External Chart (Postiz)
```yaml
# services/home/prod/Chart.yaml
dependencies:
- name: app-template
  version: 4.3.0
  repository: https://bjw-s-labs.github.io/helm-charts/
  alias: paperless
- name: postiz
  version: 1.0.5
  repository: https://charts.rock8s.com
# ^ Added to Chart.yaml

# services/home/prod/values.yaml
charts:
  postiz:
    version: 1.0.5 # renovate: datasource=helm registryUrl=https://charts.rock8s.com
    repository: https://charts.rock8s.com
    namespace: default
    ServerSideApply: "false"

postiz:
  # Chart-specific configuration
  config:
    postiz:
      baseUrl: OVERRIDE_VIA_CUSTOM_VALUES
      hostname: OVERRIDE_VIA_CUSTOM_VALUES
    postgres:
      hostname: pg-postiz-rw
      database: postiz
      username: postiz
      password: OVERRIDE_VIA_SECRET

# services/home/prod/templates/pg-postiz.yaml
# Service-level PostgreSQL cluster for postiz
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-postiz
...
```

### Per Task Implementation Details

```yaml
# Task 1 - Directory Structure
mkdir -p charts/{service-name}/templates

# Task 2 - Chart.yaml Pattern
apiVersion: v2
name: {service-name}
version: 1.0.0
appVersion: {latest-version}  # Research from Docker Hub
dependencies:
- name: app-template
  version: 4.2.0
  repository: https://bjw-s-labs.github.io/helm-charts/

# Task 3 - Values.yaml Core Structure (Full Single-Container Template)
bitwardenIds:
  {service-name}: OVERRIDE_VIA_CUSTOM_VALUES
  {service-name}-db: OVERRIDE_VIA_CUSTOM_VALUES  # Only if database

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName {service-name}

  controllers:
    {service-name}:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            repository: {docker-image}
            tag: {version}
          env:
            # RESEARCH: Service-specific environment variables
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
    {service-name}:
      controller: *chartName
      ports:
        http:
          port: {app-port}

  persistence:
    config:
      existingClaim: *chartName
```

**Redis Sidecar (add another container alongside `main`):**
```yaml
containers:
  main:
    # ... main app container above ...
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
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
```
Main container connects to Redis via `localhost:6379` (same pod).

**Complex Multi-Container Layout (Supabase-style):**
```yaml
containers:
  kong:          # API Gateway
  auth:          # Authentication service (GoTrue)
  rest:          # PostgREST REST API
  realtime:      # WebSocket / realtime service
  storage:       # File storage service
  imgproxy:      # Image processing
  redis:         # Caching / queues
```
Each container has its own `image`, `env`, `envFrom`, `resources`, and `securityContext` blocks. Inter-container comms use `localhost:{port}` since they share a pod.

### Full Template YAML Bodies

#### PVC Template — `templates/pvc-{service-name}-default.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {service-name}
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {size}Gi  # 1Gi for config, 5-10Gi for apps, 20Gi+ for databases
```

#### PostgreSQL Cluster Template — `templates/pg-{service-name}.yaml`
```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-{service-name}
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
      database: {service-name}
      owner: {service-name}
      secret:
        name: db-{service-name}-secret
```

#### Application ExternalSecret Template — `templates/secret-{service-name}.yaml`
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {service-name}
spec:
  refreshInterval: 1h
  target:
    name: {service-name}
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # App-specific environment variables (constructed from remoteRef values below)
        DATABASE_HOST: "pg-{service-name}-rw"          # If PostgreSQL is used
        DATABASE_NAME: "{service-name}"
        DATABASE_USER: "{{ `{{ .db_username }}` }}"
        DATABASE_PASSWORD: "{{ `{{ .db_password }}` }}"
        # Add other computed values here (URLs, JWT payloads, etc.)
  data:
    # Database credentials (only include if PostgreSQL is used)
    - secretKey: db_username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "{service-name}-db" }}'
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
        key: '{{ index .Values "bitwardenIds" "{service-name}-db" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    # Application-specific field secrets (API keys, JWT secrets, etc.)
    - secretKey: api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "{service-name}" }}'
        property: api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

**Note on Go template escaping:** The pattern `"{{ `{{ .db_username }}` }}"` escapes the outer Helm template so the inner `{{ .db_username }}` is passed through as an ExternalSecrets v2 template literal (evaluated at secret assembly time, not at Helm render time).

#### PostgreSQL Credentials ExternalSecret — `templates/secret-db-{service-name}.yaml`
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-{service-name}-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: db-{service-name}-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: {{ index .Values "bitwardenIds" "{service-name}-db" }}
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      remoteRef:
        key: {{ index .Values "bitwardenIds" "{service-name}-db" }}
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```


### Integration Points
```yaml
APPLICATIONSET:
  - file: services/{category}/prod/templates/appset-{type}.yaml
  - pattern: Add appName entry to list generator elements
  
PROXY:
  - file: services/{category}/prod/values.yaml
  - pattern: Add ingress subdomain configuration
  
SECRETS:
  - bitwarden-login: For username/password pairs
  - bitwarden-fields: For custom fields (API keys, tokens)
  
DATABASE:
  - CloudNativePG: For PostgreSQL clusters
  - pattern: pg-{service}-rw for read-write access

SERVICE_VALUES:
  - file: services/{category}/prod/values.yaml
  - purpose: Service-wide default configuration for all charts
  - pattern: Must be included in ApplicationSet valueFiles
  - hierarchy: Chart defaults < Service values < Custom values
```

## Service Values Pattern (CRITICAL)

### Three-Tier Value Loading System

SpencersLab uses a three-tier value hierarchy to manage configuration:

```yaml
Priority (Low to High):
1. Chart's built-in values.yaml        # Chart defaults
2. Service's values.yaml                # Service-wide defaults ← CRITICAL
3. custom-values/{chart}/prod-values.yaml  # Chart-specific overrides
```

### Service Values.yaml Structure

Each service category has a values.yaml file that provides defaults for ALL charts in that service:

```yaml
Reference File: services/gpu/prod/values.yaml
Purpose: 
  - Provide service-wide defaults (domain, ingress, resources)
  - Configure chart-specific settings (ollama GPU config, coder env vars)
  - Define proxy/ingress routing for all services
  - Set Bitwarden ID placeholders

Structure:
# Global service configuration
domain: OVERRIDE_VIA_APPSET
clusterName: OVERRIDE_VIA_APPSET
bitwardenIds:
  {service-1}: OVERRIDE_VIA_CLUSTER_ANNOTATION
  {service-2}: OVERRIDE_VIA_CLUSTER_ANNOTATION

# Service-wide ingress configuration
ingress:
  subdomains:
    {service-1}:
      serviceName: {name}
      service: {service-name}
      port: {port}

# Chart-specific configuration (optional)
{chart-name}:
  # Chart-specific settings that apply to this chart
  # Example: ollama GPU configuration, coder environment variables
```

### ApplicationSet ValueFiles Configuration

**CRITICAL:** ApplicationSet templates MUST include the service values.yaml:

```yaml
# CORRECT - Three-tier hierarchy (default)
valueFiles:
  - values.yaml                    # Chart's default values
  - $services/.../gpu/prod/values.yaml   # Service defaults ← REQUIRED
  - $values/.../gpu/prod-values.yaml     # Custom overrides

# INCORRECT - Missing service values
valueFiles:
  - values.yaml
  - $values/.../gpu/prod-values.yaml  # ← Missing service tier!

# OPTIONAL - Disable custom-values via annotation
# Set cluster annotation: metadata.annotations.services.gpu.includeCustomValues: "false"
# This will skip loading the custom-values file (useful for charts that don't need overrides)
valueFiles:
  - values.yaml
  - $services/.../gpu/prod/values.yaml
  # custom-values file skipped when includeCustomValues="false"
```

### Controlling Custom-Values Loading

The custom-values files are OPTIONAL and only loaded when explicitly set via cluster annotations. There are TWO levels of custom-values:

1. **Service-Wide**: Applies to ALL apps in the service
2. **Per-App**: Applies to specific app (can override service-wide)

```yaml
# Cluster Secret Annotation Patterns
metadata:
  annotations:
    # Service-wide custom-values URL (applies to ALL apps)
    services.gpu.customValuesUrl: "$values/custom-values/gpu/prod-values.yaml"
    
    # Per-app custom-values URL (for specific apps)
    services.gpu.<appName>.customValuesUrl: "$values/custom-values/<appName>/prod-values.yaml"
    
# Default Behavior (no annotations):
# NO custom-values files are loaded
# Only loads: chart values → service values

# Value Loading Order:
# 1. Chart's values.yaml (lowest priority)
# 2. Service's values.yaml (services/gpu/prod/values.yaml)
# 3. Service-wide custom-values (if services.gpu.customValuesUrl is set)
# 4. Per-app custom-values (if services.gpu.<appName>.customValuesUrl is set)

# Use Case Examples:

# 1. No custom-values (default - most common)
# No annotations needed
# Loads: chart values → service values only
# Use when: Service-wide defaults are sufficient

# 2. Service-wide custom-values (for ALL apps)
metadata:
  annotations:
    services.gpu.customValuesUrl: "$values/custom-values/gpu/prod-values.yaml"
# All apps load: chart values → service values → gpu/prod-values.yaml
# Use when: All apps in service need same cluster-specific overrides

# 3. Per-app custom-values only
metadata:
  annotations:
    services.gpu.ollama.customValuesUrl: "$values/custom-values/ollama/prod-values.yaml"
# Ollama loads: chart values → service values → ollama/prod-values.yaml
# Other apps load: chart values → service values only
# Use when: Single app needs cluster-specific overrides

# 4. Both service-wide AND per-app custom-values
metadata:
  annotations:
    services.gpu.customValuesUrl: "$values/custom-values/gpu/prod-values.yaml"
    services.gpu.ollama.customValuesUrl: "$values/custom-values/ollama/prod-values.yaml"
# Ollama loads: chart → service → gpu/prod-values.yaml → ollama/prod-values.yaml
# Other apps load: chart → service → gpu/prod-values.yaml
# Use when: Common overrides for all apps + specific overrides for some apps

# 5. Custom locations
metadata:
  annotations:
    services.gpu.customValuesUrl: "$values/shared/gpu-common.yaml"
    services.gpu.ollama.customValuesUrl: "$values/overrides/ollama-prod.yaml"

# Implementation in ApplicationSet:
# Service-wide custom values URL (applies to ALL apps in this service):
# metadata.annotations.services.gpu.customValuesUrl
{{- $serviceCustomValuesUrl := index .metadata.annotations "services.gpu.customValuesUrl" }}
{{- if $serviceCustomValuesUrl }}
- {{ $serviceCustomValuesUrl }}
{{- end }}

# Per-app custom values URL (overrides service-wide for specific app):
# metadata.annotations.services.gpu.<appName>.customValuesUrl
{{- $appCustomValuesUrl := index .metadata.annotations (printf "services.gpu.%s.customValuesUrl" .appName) }}
{{- if $appCustomValuesUrl }}
- {{ $appCustomValuesUrl }}
{{- end }}
```

### Required Files for Each Chart

Every chart MUST have these files:

```bash
# Chart files (in charts/{chart}/)
Chart.yaml
Chart.lock
values.yaml
templates/

# Service integration
services/{category}/prod/values.yaml    # Service defaults

### Level 1: Chart Validation
```bash
# Run these FIRST - fix any errors before proceeding
helm lint charts/{service-name}
helm template charts/{service-name} --debug

# Expected: No errors, clean template output
# If errors: READ the error message and fix YAML syntax/structure
```

### Level 2: Template Rendering
```bash
# Test with sample values
helm template {service-name} charts/{service-name} \
  --set domain=test.example.com \
  --set bitwardenIds.{service-name}=test-uuid

# Expected: Valid Kubernetes manifests
# If errors: Check template syntax and value references
```

### Level 3: Integration Validation
```bash
# Verify ApplicationSet includes new service
grep -r "{service-name}" services/*/prod/templates/

# Verify proxy configuration exists
grep -r "{service-name}" services/*/prod/values.yaml

# Expected: Service found in appropriate ApplicationSet and proxy config
```

### Level 4: Deployment Readiness
```bash
# Check all required files exist
ls -la charts/{service-name}/
ls -la charts/{service-name}/templates/
ls -la custom-values/{service-name}/

# Expected: All required files present
# Chart.yaml, Chart.lock, values.yaml, templates/, custom-values/
```

## Final Validation Checklist
- [ ] Chart validates: `helm lint charts/{service-name}`
- [ ] Templates render: `helm template charts/{service-name}`
- [ ] ApplicationSet integration complete
- [ ] Proxy configuration added
- [ ] Bitwarden secret structure documented
- [ ] Storage requirements properly configured
- [ ] Multi-container communication (if applicable) uses correct service names
- [ ] Security contexts follow SpencersLab standards
- [ ] Resource limits appropriate for service type

## Service Category Decision Matrix

### AI/ML Services (GPU Category)
- **Characteristics**: Require GPU resources, AI/ML workloads
- **ApplicationSet**: `services/gpu/prod/templates/appset-dev-charts.yaml`
- **Examples**: flowise, langflow, n8n, langfuse, archon
- **Resource Pattern**: Higher CPU/memory limits

### Home Automation (Home Category)
- **Characteristics**: IoT, personal productivity, home management
- **ApplicationSet**: `services/home/prod/templates/appset.yaml`
- **Examples**: zigbee2mqtt, paperless, karakeep
- **Resource Pattern**: Moderate resource requirements

### Infrastructure Services (Infra Category)
- **Characteristics**: Core cluster services, foundational components
- **ApplicationSet**: `services/infra/prod/templates/appset-base.yaml`
- **Examples**: base, external-secrets-bitwarden, monitoring-agent
- **Resource Pattern**: Lightweight, high availability

### Media Services (Media Category)
- **Characteristics**: Streaming, media processing, entertainment
- **ApplicationSet**: `services/media/prod/templates/appset.yaml`
- **Examples**: jellyfin, hyperion, logitech-media-server
- **Resource Pattern**: Variable based on media processing needs

## Common Environment Variables by Application Type

Use this reference during the research phase to know what env vars to expect (and thus what secrets to create). Actual variable names vary by application — consult the app's official Docker image docs.

**Database-backed Applications:**
- `DATABASE_URL` (single connection string) or discrete `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`
- Connection pooling settings (pool size, timeouts)
- SSL/TLS configuration for DB connections

**Authentication-enabled Applications:**
- `JWT_SECRET` / `JWT_SIGNING_KEY`
- `SECRET_KEY` / `SESSION_SECRET` for session management
- `NEXTAUTH_SECRET` / `NEXTAUTH_URL` for NextAuth.js apps
- User management / OAuth settings

**Web Applications:**
- `HOST`, `PORT`, `PROTOCOL`
- `BASE_URL` / `SITE_URL` / `PUBLIC_URL`
- CORS origins, security headers, cookie domain

**Applications with File Storage:**
- Storage backend selector (local vs S3 vs SeaweedFS)
- File size limits (`MAX_UPLOAD_SIZE`, etc.)
- Upload/download path configuration
- Object-storage credentials (access key / secret key / endpoint / bucket)

## Bitwarden Secret Structure

SpencersLab uses two Bitwarden SecretStores. Fields expected in each Bitwarden item depend on the store type it's referenced from:

**`bitwarden-login` store** (Bitwarden Login-type items):
- `username` — Database or service username
- `password` — Database or service password

**`bitwarden-fields` store** (Bitwarden Custom Fields on any item):
- `api_key` — API authentication token
- `jwt_secret` — JWT signing key
- `encryption_key` — Data encryption key
- `secret_key` — Session/app secret
- `nextauth_secret` — NextAuth.js secret
- `salt` — Password hashing salt
- (any other custom field name your app needs)

The `bitwardenIds` map in `values.yaml` maps a logical name (e.g. `{service-name}`, `{service-name}-db`) to the UUID of the Bitwarden item. Both stores can read from the same item — the store type just changes *which* part of the item is accessed (login credentials vs custom fields).

## Resource Allocation Guidelines

Use these tiers as starting values. Tune based on actual observed usage.

**CPU Requests:**
- Simple apps: `10m`–`100m`
- Database / complex apps: `100m`–`200m`
- Sidecar containers (Redis, small helpers): `10m`

**Memory:**
- Simple apps: request `140Mi`–`256Mi`, limit `1Gi`–`2Gi`
- Databases: request `1Gi`+, limit `4Gi`+
- Redis sidecars: request `50Mi`, limit `256Mi`

**Storage (PVCs):**
- Config-only: `1Gi`
- Application data: `5Gi`–`10Gi`
- Database storage: `10Gi`–`20Gi`+ (grow as needed)

## Standard Security Context

Every container MUST include this security context (or an equivalent). Add it under each container in `app-template.controllers.<name>.containers.<name>.securityContext`:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

For containers that don't need to write to the root filesystem, also consider adding:
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```
(Only enable `readOnlyRootFilesystem` if the app tolerates it — many apps write temp files at runtime.)

## Override Sentinel Patterns

Three placeholder strings are used throughout `values.yaml` files to signal *how* a value gets its real content at deploy time. Never leave these strings in a rendered manifest — each must be resolved before the chart deploys.

| Sentinel                       | Resolved By                                         | Typical Use                                            |
|--------------------------------|-----------------------------------------------------|--------------------------------------------------------|
| `OVERRIDE_VIA_APPSET`          | ArgoCD ApplicationSet at deploy time (via generator/annotations) | Cluster-specific values like `domain`, `clusterName`   |
| `OVERRIDE_VIA_CUSTOM_VALUES`   | `custom-values/{chart}/prod-values.yaml`            | Per-cluster secrets/IDs like Bitwarden item UUIDs      |
| `OVERRIDE_NEEDED`              | Developer must edit before merging                  | Placeholder that MUST be filled in during chart creation |

If you see any of these strings in `helm template` output, the chart is not ready to deploy.

## Anti-Patterns to Avoid

- ❌ Don't create charts when official ones exist
- ❌ Don't put domain references directly in values.yaml (use secrets)
- ❌ Don't use localhost for inter-service communication (use service names)
- ❌ Don't skip PVC evaluation (not all services need persistent storage)
- ❌ Don't hardcode Bitwarden UUIDs in base charts (use OVERRIDE patterns)
- ❌ Don't ignore existing ApplicationSet categories (choose appropriate one)
- ❌ Don't create new patterns when existing ones work
- ❌ Don't skip security contexts (always drop ALL capabilities)
- ❌ Don't use sync database drivers (use async: postgresql+psycopg)
- ❌ Don't forget to add proxy configuration for web-accessible services
- ❌ Don't access optional fields directly in Go templates without checking existence first

## Go Template Best Practices for ApplicationSets

### Safe Field Access with hasKey

When working with ApplicationSet Go templates, always use `hasKey` to check for optional fields before accessing them:

```yaml
# ❌ WRONG - Will error if field doesn't exist (with goTemplateOptions: ["missingkey=error"])
{{- if .version }}
chart: "{{ .appName }}"
{{- else }}
path: "charts/{{ .appName }}"
{{- end }}

# ✅ CORRECT - Safe check that won't error
{{- if hasKey . "version" }}
chart: "{{ .appName }}"
{{- else }}
path: "charts/{{ .appName }}"
{{- end }}
```

### Common Patterns

**Checking for Optional Generator Fields:**
```yaml
# Check if a field exists before using it
{{- if hasKey . "repository" }}
repoURL: "{{ .repository }}"
{{- else }}
repoURL: "{{ index .metadata.annotations \"charts.repo\" }}"
{{- end }}

# Check for optional values injection
{{- if hasKey . "values" }}
valuesObject: {{ .values | toYaml | nindent 14 }}
{{- end }}

# Check for optional alias field
{{- $valuesKey := .appName }}
{{- if hasKey . "alias" }}
  {{- $valuesKey = .alias }}
{{- end }}
```

**Checking for Annotation Keys:**
```yaml
# Check if annotation exists before accessing
{{- $customValuesUrl := index .metadata.annotations (printf "services.gpu.%s.customValuesUrl" .appName) }}
{{- if $customValuesUrl }}
- {{ $customValuesUrl }}
{{- end }}
```

### Why This Matters

1. **Error Prevention**: With `goTemplateOptions: ["missingkey=error"]`, accessing non-existent fields causes ApplicationSet failures
2. **Optional Features**: Allows charts to have optional fields without breaking deployments
3. **Conditional Logic**: Enables different behavior based on field presence (e.g., git vs Helm chart repos)
4. **Backward Compatibility**: New fields can be added without breaking existing configurations

### Related Functions

```yaml
# hasKey - Check if key exists
{{- if hasKey . "fieldName" }}...{{- end }}

# dig - Access nested fields with default fallback
{{ dig "key1" "key2" "default" . }}

# index - Access map/annotation values
{{ index .metadata.annotations "key.name" }}

# default - Provide fallback value
{{ .fieldName | default "fallback" }}
```

### Reference Implementation

See `services/gpu/prod/templates/appset-dev-charts.yaml` for production examples of:
- Using `hasKey` to distinguish git vs Helm chart sources
- Safe access to optional `version`, `repository`, and `values` fields
- Conditional custom-values loading with annotation checks

## Shared Storage Pattern

### Overview

SpencersLab implements a flexible shared storage pattern that allows charts to support both default local storage and shared storage backends (like SeaweedFS) through configuration overrides. This pattern enables:

1. **Default Behavior**: Charts create local PVCs for development/testing
2. **Production Override**: Service-level configuration can switch to shared storage backends
3. **Consistent Naming**: PVCs use the same name regardless of backing storage
4. **Conditional Templates**: Chart templates conditionally create PVCs based on configuration

### Implementation Pattern

#### 1. Chart Values Configuration

Charts define a `shared-storage` configuration section:

```yaml
# charts/{service-name}/values.yaml
shared-storage: {}  # Empty by default

# Example override configuration:
# shared-storage:
#   {storage-name}:
#     pvc-name: {pvc-name}-shared
#     provider: seaweedfs
```

**Key Points:**
- Default to empty dict `{}` to enable safe template access
- Document the override structure in comments
- Specify the PVC name and provider type

#### 2. Conditional PVC Template

Charts create PVCs conditionally based on shared-storage configuration:

```yaml
# charts/{service-name}/templates/pvc-{storage}-default.yaml
{{- if not (index .Values "shared-storage" "{storage-name}") }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {storage-name}-shared
  namespace: {{ .Values.namespace }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
{{- end }}
```

**Critical Template Logic:**
- Use `index .Values "shared-storage" "{storage-name}"` for safe nested access
- This handles cases where `shared-storage` might be empty/nil
- Only create PVC when shared-storage configuration is NOT present
- PVC names should match across default and shared storage implementations

#### 3. Service-Level Shared Storage Configuration

Service values.yaml configures chart to use shared storage:

```yaml
# services/{category}/prod/values.yaml
{chart-name}:
  shared-storage:
    {storage-name}:
      pvc-name: {storage-name}-shared
      provider: seaweedfs
```

**Effect:**
- Overrides the chart's default empty `shared-storage: {}`
- Triggers conditional logic in chart templates
- Prevents default PVC creation
- Enables use of service-provided shared storage PVC

#### 4. Service-Level Shared Storage PVC

Services create the shared storage PVC separately:

```yaml
# services/{category}/prod/templates/pvc-{storage}-seaweedfs.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: {storage-name}-shared
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 3000Gi
  csi:
    driver: seaweedfs-csi-driver
    volumeHandle: {storage-name}-shared
    volumeAttributes:
      collection: {collection-name}
      replication: "003"
      path: /buckets/{collection-name}/{storage-name}
    readOnly: false
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {storage-name}-shared
spec:
  storageClassName: ""
  volumeName: {storage-name}-shared
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 3000Gi
```

### Complete Example: hivetools Knowledge Storage

**Reference Files:**
- `charts/hivetools/values.yaml` - Chart configuration
- `charts/hivetools/templates/pvc-knowledge-default.yaml` - Default PVC
- `services/gpu/prod/values.yaml` - Service override
- `services/gpu/prod/templates/pvc-knowledge-seaweedfs.yaml` - Shared PVC

#### Chart Configuration (charts/hivetools/values.yaml)
```yaml
# Shared storage configuration
# When set, overrides the default PVC for knowledge storage
# Example:
# shared-storage:
#   knowledge:
#     pvc-name: knowledge-shared
#     provider: seaweedfs
shared-storage: {}
```

#### Default PVC Template (charts/hivetools/templates/pvc-knowledge-default.yaml)
```yaml
{{- if not (index .Values "shared-storage" "knowledge") }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: knowledge-shared
  namespace: {{ .Values.namespace }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
{{- end }}
```

#### Service Override (services/gpu/prod/values.yaml)
```yaml
hivetools:
  shared-storage:
    knowledge:
      pvc-name: knowledge-shared
      provider: seaweedfs
```

#### Shared Storage PVC (services/gpu/prod/templates/pvc-knowledge-seaweedfs.yaml)
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: knowledge-shared
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 3000Gi
  csi:
    driver: seaweedfs-csi-driver
    volumeHandle: knowledge-shared
    volumeAttributes:
      collection: documents
      replication: "003"
      path: /buckets/documents/knowledge
    readOnly: false
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: knowledge-shared
spec:
  storageClassName: ""
  volumeName: knowledge-shared
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 3000Gi
```

### Usage Flow

1. **Development/Default**: Chart deploys with `shared-storage: {}`, creates local 10Gi PVC
2. **Production**: Service sets `shared-storage.knowledge`, skips chart PVC, uses shared 3000Gi SeaweedFS PVC
3. **Consumption**: Workloads reference PVC by name `knowledge-shared` regardless of backing storage

### Key Benefits

- **Flexibility**: Easy transition between local and shared storage
- **Consistency**: Same PVC name in all environments
- **Scalability**: Shared storage for production, local for dev
- **Configuration**: Declarative via values, no code changes
- **Transparency**: Conditional templates make behavior explicit

### Template Logic Best Practices

**✅ CORRECT - Use index for nested field access:**
```yaml
{{- if not (index .Values "shared-storage" "knowledge") }}
# Create default PVC
{{- end }}
```

**❌ INCORRECT - Direct access fails when parent is nil:**
```yaml
{{- if not .Values.shared-storage.knowledge }}
# Will error if shared-storage is nil/undefined
{{- end }}
```

**Why index is required:**
- Safely handles nil parent values
- Works even when `shared-storage: {}` is empty
- Prevents template rendering errors
- Required for proper Go template evaluation with `goTemplateOptions: ["missingkey=error"]`

## Template Examples from SpencersLab

### Simple Self-Contained Service Pattern (Qdrant)
```yaml
# No PostgreSQL cluster
# API key authentication only
# Single container
# Vector storage on PVC
# Port 6333 (HTTP), 6334 (GRPC)
```

### Database-Backed Service Pattern (n8n)
```yaml
# PostgreSQL cluster required
# JWT and encryption secrets
# User management capabilities
# Webhook configuration
# Port 5678
```

### Multi-Container Pattern (LangFuse)
```yaml
# Main app + Redis sidecar
# PostgreSQL cluster for persistence
# NextAuth authentication
# Port 3000
```

### Complex Multi-Container Pattern (Archon)
```yaml
# 4 containers: Server + MCP + Agents + Frontend
# Inter-service communication via service names
# Shared secrets across all containers
# Multiple ports: 3737, 8181, 8051, 8052
```

## Known Good Examples (Reference These Files)

### Complete Chart Examples Created in This Session

#### Simple Self-Contained Service: Qdrant
```yaml
Reference Files:
- charts/qdrant/Chart.yaml          # Basic chart metadata
- charts/qdrant/Chart.lock          # Standard dependency lock
- charts/qdrant/values.yaml         # Single container with API key auth
- charts/qdrant/templates/pvc-qdrant-default.yaml    # 10Gi storage for vectors
- charts/qdrant/templates/secret-qdrant.yaml         # API key from Bitwarden
- custom-values/qdrant/prod-values.yaml              # Bitwarden override pattern

Key Patterns:
- No PostgreSQL cluster needed (self-contained)
- API key authentication via Bitwarden fields
- Dual ports: 6333 (HTTP), 6334 (GRPC)
- Vector storage requires larger PVC (10Gi)
```

#### Database-Backed Service: n8n
```yaml
Reference Files:
- charts/n8n/Chart.yaml                    # Chart with latest version research
- charts/n8n/values.yaml                   # PostgreSQL integration pattern
- charts/n8n/templates/pg-n8n.yaml         # PostgreSQL cluster template
- charts/n8n/templates/secret-n8n.yaml     # App secrets with DB connection
- charts/n8n/templates/secret-db-n8n.yaml  # Database credentials
- charts/n8n/templates/pvc-n8n-default.yaml # Application storage
- custom-values/n8n/prod-values.yaml       # Single Bitwarden item pattern

Key Patterns:
- PostgreSQL cluster required for production
- JWT and encryption secrets for user management
- Single Bitwarden item for all credentials
- Webhook configuration support
- Port 5678 standard for n8n
```

#### Multi-Container with Redis: LangFuse
```yaml
Reference Files:
- charts/langfuse/Chart.yaml                      # Multi-container chart
- charts/langfuse/values.yaml                     # App + Redis sidecar pattern
- charts/langfuse/templates/pg-langfuse.yaml      # PostgreSQL for persistence
- charts/langfuse/templates/secret-langfuse.yaml  # Complex secret template
- charts/langfuse/templates/secret-db-langfuse.yaml # Separate DB credentials
- charts/langfuse/templates/pvc-langfuse-default.yaml # App storage

Key Patterns:
- Main app + Redis sidecar in same pod
- PostgreSQL cluster for data persistence
- NextAuth secrets for authentication
- Separate Bitwarden items for app vs database
- Redis connection via localhost:6379
```

#### Complex Multi-Container: Archon
```yaml
Reference Files:
- charts/archon/Chart.yaml                    # 4-container service
- charts/archon/values.yaml                   # Inter-service communication
- charts/archon/templates/secret-archon.yaml  # Domain refs in secrets
- charts/archon/templates/pvc-archon-default.yaml # Shared storage
- custom-values/archon/prod-values.yaml       # Single Bitwarden pattern

Key Patterns:
- 4 containers: Server, MCP, Agents, Frontend
- Service-to-service communication via service names
- Domain references constructed in secret template
- Multiple ports exposed: 3737, 8181, 8051, 8052
- Shared secrets across all containers
```

#### Complex Backend Service: Supabase
```yaml
Reference Files:
- charts/supabase/Chart.yaml                      # Backend-as-a-service
- charts/supabase/values.yaml                     # 6-container setup
- charts/supabase/templates/pg-supabase.yaml      # PostgreSQL cluster
- charts/supabase/templates/secret-supabase.yaml  # Complex secret structure
- charts/supabase/templates/pvc-supabase-default.yaml # Large storage (20Gi)

Key Patterns:
- Multiple specialized containers (Kong, GoTrue, PostgREST, Realtime, Storage, ImgProxy, Redis)
- Complex authentication setup with multiple JWT secrets
- Large storage requirements for file storage
- Multiple Bitwarden secret sources
```

### ApplicationSet Integration Examples

#### Values Injection Pattern (Optional)
```yaml
Purpose: Inject Helm values into ApplicationSet generator elements for use in templatePatch
Reference File: services/gpu/prod/templates/appset-dev-charts.yaml

Pattern - Basic (appName as values key):
- appName: ollama
  version: 1.26.0
  repository: https://helm.otwld.com/
  namespace: default
  ServerSideApply: "false"
  {{- if index .Values "ollama" }}
  values: {{ index .Values "ollama" | toJson }}
  {{- end }}

Pattern - With Optional Alias (custom values key):
- appName: my-service
  version: 1.0.0
  repository: https://example.com/helm
  namespace: default
  ServerSideApply: "false"
  {{- if index .Values "myCustomKey" }}
  alias: myCustomKey  # Optional - only if values key differs from appName
  values: {{ index .Values "myCustomKey" | toJson }}
  {{- end }}

TemplatePatch Logic (handles fallback):
templatePatch: |
  {{- $valuesKey := .appName }}
  {{- if hasKey . "alias" }}
    {{- $valuesKey = .alias }}
  {{- end }}
  ...
  {{- if hasKey . "values" }}
  valuesObject: {{ .values | toYaml | nindent 14 }}
  {{- end }}

Key Points:
- Use index .Values "" for consistency (handles hyphens in names)
- alias field is optional - defaults to appName if not specified
- Values are injected as JSON at Helm template time
- templatePatch accesses pre-injected values (not .Values directly)
- Allows nested structures like coder: { coder: { env: ... } }

Example values.yaml structure:
coder:          # <- Top-level key (used as alias or appName)
  coder:        # <- Nested structure
    env:
      - name: CODER_VERBOSE
        value: "true"
```

#### GPU Service Integration
```yaml
Reference File: services/gpu/prod/templates/appset-dev-charts.yaml
Pattern: AI/ML services with development/experimental charts

Example Addition - Simple:
- appName: {new-ai-service}
  namespace: default
  ServerSideApply: "false"

Example Addition - With Values Injection:
- appName: {new-ai-service}
  namespace: default
  ServerSideApply: "false"
  {{- if index .Values "{new-ai-service}" }}
  values: {{ index .Values "{new-ai-service}" | toJson }}
  {{- end }}
```

#### Home Service Integration
```yaml
Reference File: services/home/prod/templates/appset.yaml
Pattern: Home automation and personal productivity
Example Addition:
- appName: {new-home-service}
  namespace: default
```

#### Infrastructure Service Integration
```yaml
Reference File: services/infra/prod/templates/appset-base.yaml
Pattern: Core cluster services with version management
Example Addition:
- appName: {new-infra-service}
  version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
  ServerSideApply: "false"
```

### Proxy Configuration Examples

#### GPU Services Proxy
```yaml
Reference File: services/gpu/prod/values.yaml
Current Services: flowise, langflow, n8n, qdrant, neo4j, langfuse, searxng, supabase, archon
Pattern:
{service-name}:
  serviceName: {service-name}
  service: {service-name}
  port: {service-port}
```

#### Home Services Proxy
```yaml
Reference File: services/home/prod/values.yaml
Current Services: wekan, paperless, zigbee2mqtt, snapcast, etc.
Pattern:
{service-name}:
  serviceName: {service-name}
  service: home-{service-name}
  port: {service-port}
```

### Secret Management Examples

#### Single Bitwarden Item Pattern (n8n)
```yaml
Reference File: custom-values/n8n/prod-values.yaml
Content:
bitwardenIds:
  n8n: 94cc6ec2-5c62-407b-a04a-b34a0166d615

Usage: All credentials in one Bitwarden item
```

#### Separate Database Credentials Pattern (LangFlow)
```yaml
Reference File: custom-values/langflow/prod-values.yaml
Content:
bitwardenIds:
  langflow-db: c2f26e5d-84fc-404d-93b7-b34a0157b6a0
  langflow: f7b628ec-2544-4c28-a476-b1a501487d99

Usage: Separate items for app vs database credentials
```

#### Shared Infrastructure Secret Pattern
```yaml
Reference Files: Multiple custom-values files
Shared Secret: cert-manager-solver-token: 0f8504eb-1339-4a32-861b-af440002801e
Used In: base, gpu, monitoring, media, cherry services
Usage: Infrastructure secrets shared across multiple services
```

### Template File Examples

#### PostgreSQL Cluster Template
```yaml
Reference File: charts/langflow/templates/pg-langflow.yaml
Key Elements:
- CloudNativePG operator usage
- Standard storage class: local-path
- Monitoring enabled: enablePodMonitor: true
- Connection parameters: max_connections, shared_buffers
- Bootstrap with initdb for database creation
```

#### External Secret Template
```yaml
Reference File: charts/langfuse/templates/secret-langfuse.yaml
Key Elements:
- Template engine v2 for complex variable construction
- Domain references: "https://{{ .Values.domain }}"
- Database URL construction in template
- Multiple secret sources: bitwarden-login, bitwarden-fields
- Standard boilerplate for ArgoCD compatibility
```

#### Multi-Container Values Pattern
```yaml
Reference File: charts/archon/values.yaml
Key Elements:
- Multiple containers in single controller
- Inter-service communication configuration
- Shared environment variables via envFrom
- Multiple service ports exposed
- Resource allocation per container
```

This PRP should be used as a comprehensive guide when creating new Helm charts to ensure consistency and successful deployment in the SpencersLab infrastructure.
</content>
</replace_in_file>

[Response interrupted by a tool use result. Only one tool may be used at a time and should be placed at the end of the message.]
