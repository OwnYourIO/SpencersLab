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
    └── secret-pg-{service}.yaml    # PostgreSQL credentials (if needed)

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
# CRITICAL: ApplicationSet valueFiles must include service values.yaml for defaults
# CRITICAL: Service values.yaml provides default configuration for all charts in that service
```

## Implementation Blueprint

### Pre-Creation Analysis

Research and validate the service requirements:
```yaml
Official Chart Check:
  - Search Artifact Hub for {service-name}
  - Search KubeSearch.dev for {service-name}
  - Check official documentation for Helm charts
  - Decision: Use official chart OR proceed with app-template

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

### Implementation Tasks

```yaml
Task 1 - Directory Structure:
CREATE charts/{service-name}/templates/
CREATE custom-values/{service-name}/

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
  CREATE charts/{service-name}/templates/secret-pg-{service}.yaml

IF persistent storage needed:
  CREATE charts/{service-name}/templates/pvc-{service}-default.yaml

ALWAYS CREATE:
  CREATE charts/{service-name}/templates/secret-{service}.yaml

Task 5 - Custom Values:
CREATE custom-values/{service-name}/prod-values.yaml:
  - PATTERN: Use OVERRIDE_NEEDED for Bitwarden IDs
  - INCLUDE: All required Bitwarden secret references

Task 6 - Infrastructure Integration:
MODIFY appropriate ApplicationSet file:
  - GPU services: services/gpu/prod/templates/appset-dev-charts.yaml
  - Home services: services/home/prod/templates/default-application-set.yaml
  - Infrastructure: services/infra/prod/templates/appset-base.yaml

MODIFY corresponding proxy configuration:
  - ADD ingress subdomain configuration
  - SPECIFY service name and port mapping
```

### Per Task Implementation Details

```yaml
# Task 1 - Directory Structure
mkdir -p charts/{service-name}/templates
mkdir -p custom-values/{service-name}

# Task 2 - Chart.yaml Pattern
apiVersion: v2
name: {service-name}
version: 1.0.0
appVersion: {latest-version}  # Research from Docker Hub
dependencies:
- name: app-template
  version: 4.2.0
  repository: https://bjw-s-labs.github.io/helm-charts/

# Task 3 - Values.yaml Core Structure
bitwardenIds:
  {service-name}: OVERRIDE_VIA_CUSTOM_VALUES
  {service-name}-pg: OVERRIDE_VIA_CUSTOM_VALUES  # Only if PostgreSQL

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
          # PATTERN: Standard probes, resources, security
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

The custom-values file is OPTIONAL and only loaded when explicitly set via cluster annotation:

```yaml
# Cluster Secret Annotation Pattern
metadata:
  annotations:
    # Set custom-values URL for specific app (OPTIONAL)
    services.gpu.<appName>.customValuesUrl: "$values/custom-values/<appName>/prod-values.yaml"
    
# Default Behavior (no annotation):
# NO custom-values file is loaded
# Only loads: chart values → service values

# Use Case Examples:

# 1. No custom-values (default - most common)
# No annotation needed
# Loads: chart values → service values only
# Use when: Service-wide defaults are sufficient

# 2. Load custom-values for specific app
metadata:
  annotations:
    services.gpu.ollama.customValuesUrl: "$values/custom-values/ollama/prod-values.yaml"
# Loads: chart values → service values → custom-values/ollama/prod-values.yaml
# Use when: App needs cluster-specific overrides

# 3. Custom location
metadata:
  annotations:
    services.gpu.ollama.customValuesUrl: "$values/overrides/ollama-prod.yaml"
# Loads: chart values → service values → overrides/ollama-prod.yaml

# 4. Shared custom-values for multiple apps
metadata:
  annotations:
    services.gpu.ollama.customValuesUrl: "$values/shared/ai-tools.yaml"
    services.gpu.coder.customValuesUrl: "$values/shared/ai-tools.yaml"
# Both apps load: chart values → service values → shared/ai-tools.yaml

# Implementation in ApplicationSet:
# Custom values URL can be set per-app via cluster annotation:
# metadata.annotations.services.gpu.<appName>.customValuesUrl
# If not set, no custom-values file is loaded (only chart + service values)
{{- $customValuesUrl := index .metadata.annotations (printf "services.gpu.%s.customValuesUrl" .appName) }}
{{- if $customValuesUrl }}
- {{ $customValuesUrl }}
{{- end }}
```

### Required Files for Each Chart

Every chart MUST have these files to prevent errors:

```bash
# Chart files (in charts/{chart}/)
Chart.yaml
Chart.lock
values.yaml
templates/

# Custom values (REQUIRED even if empty)
custom-values/{chart}/prod-values.yaml  # Must exist, can be empty

# Service integration
services/{category}/prod/values.yaml    # Service defaults
services/{category}/prod/templates/appset-*.yaml  # ApplicationSet entry

## Validation Loop

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
- **ApplicationSet**: `services/home/prod/templates/default-application-set.yaml`
- **Examples**: zigbee2mqtt, paperless, karakeep
- **Resource Pattern**: Moderate resource requirements

### Infrastructure Services (Infra Category)
- **Characteristics**: Core cluster services, foundational components
- **ApplicationSet**: `services/infra/prod/templates/appset-base.yaml`
- **Examples**: base, external-secrets-bitwarden, monitoring-agent
- **Resource Pattern**: Lightweight, high availability

### Media Services (Media Category)
- **Characteristics**: Streaming, media processing, entertainment
- **ApplicationSet**: `services/media/prod/templates/default-application-set.yaml`
- **Examples**: jellyfin, hyperion, logitech-media-server
- **Resource Pattern**: Variable based on media processing needs

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
- charts/n8n/templates/secret-pg-n8n.yaml  # PostgreSQL credentials
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
- charts/langfuse/templates/secret-pg-langfuse.yaml # Separate DB credentials
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
Reference File: services/home/prod/templates/default-application-set.yaml
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
  langflow-pg: c2f26e5d-84fc-404d-93b7-b34a0157b6a0
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
