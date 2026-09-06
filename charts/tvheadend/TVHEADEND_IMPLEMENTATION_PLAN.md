# TVHeadend Implementation Plan for SpencersLab

## Executive Summary

**Decision: Create Custom App-Template Chart** ✅

While an official chart exists at `https://geek-cookbook.github.io/charts/`, we will create a custom app-template-based chart in `charts/tvheadend/` to match SpencersLab's patterns and ensure proper integration with the shared media mount for recordings.

**Integration Method**: Create custom chart in `charts/tvheadend/`, then reference in `services/media/prod/values.yaml` under `charts:` section

---

## Pre-Implementation Research

### Official Chart Analysis
- **Chart Repository**: https://geek-cookbook.github.io/charts/ (version 5.4.2)
- **Decision**: Create custom chart for better SpencersLab integration
- **Reference Implementation**: https://github.com/samip5/k8s-cluster/blob/main/k8s/nebula/apps/media/tvheadend/app/hr.yaml

### TVHeadend Information
- **Docker Image**: linuxserver/tvheadend (most common) or custom registry images
- **Application Type**: TV streaming and DVR service
- **Database**: None required (uses filesystem for configuration)
- **Ports**: 
  - 9981 (HTTP web interface)
  - 9982 (HTSP streaming protocol)
- **Hardware Requirements**: TV tuner device access (/dev/)

### Architecture Analysis
- **Container Type**: Single container
- **Storage**: 
  - Config storage (PVC for settings/database)
  - Recordings storage (shared media mount)
  - Timeshift buffer (emptyDir for temporary data)
- **Dependencies**: None (self-contained)
- **Secrets**: Optional (admin credentials if auth enabled)
- **Multi-container**: No (simple single container)
- **Special Requirements**: 
  - Privileged security context (hardware access)
  - Device mapping (/dev/)
  - Specific user/group IDs for hardware access

---

## Implementation Plan

### Phase 1: Custom Chart Creation

#### Step 1.1: Create Chart Directory
```bash
mkdir -p charts/tvheadend/templates
```

#### Step 1.2: Create Chart.yaml
**File**: `charts/tvheadend/Chart.yaml`

```yaml
apiVersion: v2
name: tvheadend
version: 1.0.0
appVersion: latest
dependencies:
- name: app-template
  version: 4.2.0
  repository: https://bjw-s-labs.github.io/helm-charts/
```

#### Step 1.3: Create Chart.lock
**File**: `charts/tvheadend/Chart.lock`

```yaml
dependencies:
- name: app-template
  repository: https://bjw-s-labs.github.io/helm-charts/
  version: 4.2.0
digest: sha256:951fb29739b425d834afdaff0327fc0ca307dae2f7a296cf832f749647446c35
generated: "2026-02-28T18:00:00Z"
```

#### Step 1.4: Create values.yaml
**File**: `charts/tvheadend/values.yaml`

```yaml
# bitwardenIds:
#   tvheadend: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName tvheadend

  controllers:
    tvheadend:
      annotations:
        reloader.stakater.com/auto: "true"
      pod:
        securityContext:
          runAsUser: &uid 1000
          runAsGroup: &gid 2000
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
          supplementalGroups:
            - 44    # video group
            - 109   # render group
            - 212   # Additional hardware group
      containers:
        main:
          image:
            repository: lscr.io/linuxserver/tvheadend
            tag: latest
          env:
            TZ: Etc/UTC
            PUID: *uid
            PGID: *gid
          # envFrom:
          #   - secretRef:
          #       name: *chartName
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 9981
                initialDelaySeconds: 30
                periodSeconds: 10
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 9981
                initialDelaySeconds: 30
                periodSeconds: 10
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 2Gi
          securityContext:
            privileged: true  # Required for TV tuner access
            allowPrivilegeEscalation: true
            capabilities:
              add:
                - SYS_ADMIN  # Required for device access

  service:
    tvheadend:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 9981
        htsp:
          port: 9982

  persistence:
    config:
      existingClaim: *chartName
    recordings:
      existingClaim: media
      globalMounts:
        - path: /recordings
          subPath: Recordings
    timeshift:
      type: emptyDir
      globalMounts:
        - path: /timeshift
    dev:
      type: hostPath
      hostPath: /dev
      globalMounts:
        - path: /dev
```

**Key Configuration Decisions**:
- **Image**: LinuxServer.io's TVHeadend (well-maintained, easy configuration)
- **User/Group**: 1000/2000 (matching media service pattern)
- **Supplemental Groups**: video(44), render(109), and 212 for hardware access
- **Security**: Privileged mode required for TV tuner device access
- **Config Storage**: Local PVC for configuration database
- **Recordings**: Existing shared media PVC with subPath `Recordings`
- **Timeshift**: emptyDir for temporary buffer (doesn't need persistence)
- **Device Access**: Host /dev/ mounted for TV tuner access
- **Secrets**: Disabled (commented out) - no authentication by default

### Phase 2: Chart Templates

#### Step 2.1: Create Config PVC Template
**File**: `charts/tvheadend/templates/pvc-tvheadend-default.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tvheadend
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClass: local-path
```

#### Step 2.2: Create Secret Template (Disabled)
**File**: `charts/tvheadend/templates/secret-tvheadend.yaml`

```yaml
# Secret template disabled by default - TVHeadend runs without authentication
# Uncomment and configure bitwardenIds in values.yaml to enable authentication
#
# apiVersion: external-secrets.io/v1
# kind: ExternalSecret
# metadata:
#   name: tvheadend
#   namespace: default
# spec:
#   refreshInterval: 1h
#   target:
#     name: tvheadend
#     creationPolicy: Owner
#     template:
#       engineVersion: v2
#       data:
#         # Admin credentials for TVHeadend web interface
#         TVHEADEND_ADMIN_USERNAME: "{{ `{{ .admin_username | default "" }}` }}"
#         TVHEADEND_ADMIN_PASSWORD: "{{ `{{ .admin_password | default "" }}` }}"
#   dataFrom:
#     - extract:
#         key: '{{ index .Values "bitwardenIds" "tvheadend" }}'
#       rewrite:
#         - regexp:
#             source: "(.*)"
#             target: "admin_$1"
```

**Note**: Secret is disabled by default. TVHeadend runs without authentication for internal use. Uncomment if you need web interface authentication.

### Phase 3: Service Integration

#### Step 3.1: Add to Media Service values.yaml
**File**: `services/media/prod/values.yaml`

Add to the `charts:` section:
```yaml
charts:
  # ... existing charts ...
  tvheadend:
    version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "false"
```

**Note**: No additional configuration needed - chart uses existing `media` PVC with `Recordings` subPath.

### Phase 4: Ingress and Proxy Configuration

#### Step 4.1: Add Ingress Configuration
**File**: `services/media/prod/values.yaml`

Add to the `ingress.subdomains:` section:
```yaml
ingress:
  subdomains:
    # ... existing routes ...
    
    tv:
      serviceName: tvheadend
      service: media-tvheadend
      port: 9981
```

#### Step 4.2: Add Proxy-Local Configuration  
**File**: `services/proxy-local/prod/values.yaml`

Add to the `proxy.subdomains:` section:
```yaml
proxy:
  subdomains:
    # ... existing routes ...
    
    tv:
      target: tvheadend
```

#### Step 4.3: Add Proxy-Remote Configuration
**File**: `services/proxy-remote/prod/values.yaml`

Add to the `proxy.subdomains:` section:
```yaml
proxy:
  subdomains:
    # ... existing routes ...
    
    tv:
      enabled: true
      middlewares: "kube-system-geoblock@kubernetescrd"
```

**Access URLs**:
- Primary: `https://tv.spencerslab.com`

### Phase 5: Optional Custom Values (Disabled)

**Note**: No custom values needed. Secrets are disabled by default for internal-only TVHeadend access. If authentication is needed in the future:

1. Uncomment `bitwardenIds` in `charts/tvheadend/values.yaml`
2. Uncomment secret template in `charts/tvheadend/templates/secret-tvheadend.yaml`
3. Uncomment `envFrom` in values.yaml to load secrets
4. Create `custom-values/tvheadend/prod-values.yaml` with Bitwarden UUID

---

## Implementation Checklist

### Phase 1: Custom Chart Creation
- [ ] Create `charts/tvheadend/` directory structure
- [ ] Create `charts/tvheadend/Chart.yaml`
- [ ] Create `charts/tvheadend/Chart.lock`
- [ ] Create `charts/tvheadend/values.yaml`
- [ ] Run `helm lint charts/tvheadend` to validate
- [ ] Run `helm template charts/tvheadend` to test rendering

### Phase 2: Chart Templates
- [ ] Create `charts/tvheadend/templates/pvc-tvheadend-default.yaml`
- [ ] Create `charts/tvheadend/templates/secret-tvheadend.yaml` (commented out/disabled)
- [ ] Verify templates follow SpencersLab patterns

### Phase 3: Service Integration
- [ ] Add tvheadend to `services/media/prod/values.yaml` under `charts:` section
- [ ] Verify configuration uses existing `media` PVC
- [ ] Verify no additional PVCs or storage configuration needed

### Phase 4: Ingress and Proxy
- [ ] Add ingress route to `services/media/prod/values.yaml`
- [ ] Add proxy route to `services/proxy-local/prod/values.yaml`
- [ ] Add proxy route to `services/proxy-remote/prod/values.yaml`
- [ ] Verify no naming conflicts with existing services

### Phase 5: Optional Custom Values (Disabled by Default)
- [ ] Skip creating custom-values (no secrets needed)
- [ ] If authentication needed in future: uncomment secret template and create custom-values

### Phase 5: Deployment
- [ ] Commit changes to git
- [ ] ArgoCD will automatically detect and deploy
- [ ] Monitor deployment: `kubectl get pods -n default | grep tvheadend`
- [ ] Check logs: `kubectl logs -n default -l app.kubernetes.io/name=tvheadend`
- [ ] Verify device access: `kubectl exec -it -n default <pod> -- ls -la /dev/`

### Phase 6: Configuration
- [ ] Access `https://tv.spencerslab.com`
- [ ] Complete initial TVHeadend setup wizard
- [ ] Configure TV tuner devices
- [ ] Set up channels and EPG
- [ ] Configure recording path to `/recordings` (maps to media/Recordings)
- [ ] Test live TV streaming
- [ ] Test recording functionality

### Phase 7: Testing
- [ ] Verify web interface accessible
- [ ] Test channel scanning
- [ ] Test live streaming (HTSP on port 9982)
- [ ] Test recording to shared media mount
- [ ] Verify recordings appear in `/media/Recordings`
- [ ] Test timeshift functionality

---

## File Changes Summary

### New Chart Files Created
1. **charts/tvheadend/Chart.yaml** - Chart metadata with app-template dependency
2. **charts/tvheadend/Chart.lock** - Dependency lock file
3. **charts/tvheadend/values.yaml** - Chart configuration (secrets commented out)
4. **charts/tvheadend/templates/pvc-tvheadend-default.yaml** - Config storage PVC (5Gi)
5. **charts/tvheadend/templates/secret-tvheadend.yaml** - Secret template (commented out/disabled)

### Modified Files
1. **services/media/prod/values.yaml** - Add tvheadend to `charts:` section + ingress route
2. **services/proxy-local/prod/values.yaml** - Add proxy route
3. **services/proxy-remote/prod/values.yaml** - Add proxy route with geoblocking

### No Additional Storage Needed
- Uses existing `media` PVC with `Recordings` subPath
- No custom-values files needed (secrets disabled)

### Custom Chart Created
- TVHeadend is a custom chart in `charts/tvheadend/`
- Uses app-template v4.2.0 as dependency
- Referenced in media service via `charts:` section in values.yaml
- Follows SpencersLab's custom chart pattern

---

## Storage Architecture

### Config Storage
- **PVC Name**: `tvheadend`
- **Size**: 5Gi
- **Storage Class**: `local-path`
- **Access Mode**: ReadWriteOnce
- **Mount Path**: `/config`
- **Contents**: TVHeadend configuration database, channel data, EPG cache

### Recordings Storage (Shared Media Mount)
- **PVC Name**: `media` (existing shared SeaweedFS PVC)
- **Size**: 50Ti (shared across all media services)
- **Storage Class**: SeaweedFS CSI
- **Access Mode**: ReadWriteMany
- **Mount Path**: `/recordings`
- **SubPath**: `Recordings`
- **Contents**: TV recordings saved by TVHeadend

### Timeshift Storage
- **Type**: emptyDir (temporary)
- **Mount Path**: `/timeshift`
- **Contents**: Live TV buffer for pause/rewind functionality
- **Lifecycle**: Cleared on pod restart

### Device Access
- **Type**: hostPath
- **Host Path**: `/dev`
- **Mount Path**: `/dev`
- **Purpose**: Access to TV tuner hardware devices

---

## Resource Allocation

### Compute Resources
- **CPU Request**: 100m (minimal for idle state)
- **Memory Request**: 256Mi (sufficient for basic operation)
- **Memory Limit**: 2Gi (allows for transcoding and buffering)
- **Special**: Privileged container required for hardware access

### Storage Resources
- **Config**: 5Gi local storage (channel database, EPG, settings)
- **Recordings**: Shared media mount (50Ti SeaweedFS volume)
- **Timeshift**: emptyDir (dynamically sized, typically 1-2GB)

### Network Resources
- **HTTP Port**: 9981 (web interface)
- **HTSP Port**: 9982 (streaming protocol for clients)
- **Service Type**: ClusterIP (internal access via ingress)

---

## Security Considerations

### Privileged Container Requirements
- ✅ Required for TV tuner device access
- ✅ Limited to specific pod (isolated from other services)
- ⚠️ Runs with elevated privileges (hardware access necessity)
- ✅ Supplemental groups configured for device permissions

### Access Control
- Web interface accessible via ingress (geoblock enabled)
- Optional: Configure authentication in TVHeadend
- Optional: Use Bitwarden for credential management
- HTSP streaming requires client configuration

### Hardware Security
- Device access limited to /dev/ mount
- Running as non-root user (1000:2000) where possible
- Video/render group membership for GPU access

### Network Security
- ClusterIP service (not exposed directly)
- Traefik ingress with geoblocking
- HTSP port not exposed externally by default

---

## Integration with Media Service

### Shared Media Mount Structure
```
media/                    (50Ti SeaweedFS volume)
├── Recordings/           (TVHeadend recordings - NEW)
├── Movies/               (Radarr)
├── TV Shows/             (Sonarr)
├── Music/                (Lidarr)
├── Audiobooks/           (Readarr)
└── ... (other media)
```

**Recordings Location**: `media/Recordings/` subfolder on existing shared media PVC

### Service Relationships
```
TVHeadend → Records → media/Recordings/
                          ↓
                      Jellyfin → Plays recordings
                      Sonarr → Can import recordings
```

### Workflow Integration
1. **Live TV**: TVHeadend streams live TV to clients
2. **Recording**: TVHeadend saves to `/recordings` (media/Recordings)
3. **Playback**: Jellyfin can access recordings via media mount
4. **Management**: Sonarr can detect and import recordings

---

## TVHeadend Configuration Guide

### Initial Setup (Post-Deployment)
1. Access `https://tv.spencerslab.com`
2. Complete setup wizard:
   - Set language and timezone
   - Configure admin account (or skip for internal use)
   - Accept license terms

### TV Tuner Configuration
1. Navigate to Configuration → DVB Inputs → TV Adapters
2. TVHeadend should auto-detect tuners in /dev/
3. Configure tuner parameters (frequency, modulation)
4. Scan for channels

### EPG Configuration
1. Configuration → Channel/EPG → EPG Grabber
2. Choose EPG source (OTA, XMLTV, etc.)
3. Configure schedule for EPG updates

### Recording Configuration
1. Configuration → Recording → Digital Video Recorder
2. Set recording path: `/recordings` (**Important**: This maps to media/Recordings)
3. Configure recording profiles:
   - File format (e.g., .mkv, .ts)
   - Quality settings
   - Post-processing options
4. Set file naming pattern:
   - Example: `%t/%t - S%sE%e - %e.%e`
   - This creates organized folders by show name

### Recommended Recording Settings
```
Recording Path: /recordings
File Pattern: %t/%t - S%sE%e - %e.%e
Format: Matroska (.mkv)
Container: Pass-through (no transcoding)
Priority: Normal
Retention: Based on disk space
```

---

## Monitoring & Maintenance

### Health Checks
```bash
# Check pod status
kubectl get pods -n default -l app.kubernetes.io/name=tvheadend

# Check service
kubectl get svc -n default media-tvheadend

# Check logs
kubectl logs -n default -l app.kubernetes.io/name=tvheadend

# Check PVC
kubectl get pvc -n default tvheadend

# Verify device access
kubectl exec -it -n default <tvheadend-pod> -- ls -la /dev/dvb/
```

### Metrics to Monitor
- Pod restarts (tuner disconnections)
- Storage usage (config and recordings)
- Recording failures
- EPG update status
- Stream quality and buffering

### Common Issues
1. **No tuners detected**: Check /dev/ mount and privileged mode
2. **Recording failures**: Verify /recordings path and disk space
3. **EPG not updating**: Check grabber configuration and network
4. **Streaming issues**: Check HTSP port and client configuration

### Backup Strategy
- **Config**: Backup tvheadend PVC (channel config, timers, EPG)
- **Recordings**: Already on shared media mount (included in media backups)
- **EPG**: Auto-regenerated, no backup needed

---

## Client Configuration

### Kodi with TVHeadend HTSP Client
1. Install TVHeadend HTSP Client addon
2. Configure connection:
   - Host: `media-tvheadend.default.svc.cluster.local`
   - Port: `9982`
   - Username/Password: (if configured)

### VLC Network Stream
- Protocol: `htsp://`
- Address: `tv.spencerslab.com:9982`
- Channel: (select from list)

### Web Interface
- Direct access: `https://tv.spencerslab.com`
- Features: Live TV, EPG, recording management

---

## Comparison to Other Media Services

| Service | Hardware Access | Recordings | Transcoding | Complexity |
|---------|----------------|------------|-------------|------------|
| TVHeadend | Required (tuner) | Yes (DVR) | Optional | Medium ⭐⭐⭐ |
| Jellyfin | Optional (GPU) | No | Yes | Medium ⭐⭐⭐ |
| Sonarr | No | No | No | Low ⭐⭐ |
| Plex | Optional (GPU) | No | Yes | Medium ⭐⭐⭐ |

**TVHeadend Complexity**: Medium due to hardware requirements and privileged container.

---

## Node Requirements

### Hardware Requirements
- **TV Tuner**: USB or PCIe TV tuner device
- **Node Affinity**: May need node selector if tuner only on specific node
- **GPU** (Optional): For transcoding (supplemental group 109)

### Node Selector (If Needed)
If TV tuner is only on specific nodes, add to values.yaml:
```yaml
tvheadend:
  controllers:
    tvheadend:
      pod:
        nodeSelector:
          feature.node.kubernetes.io/tuner: "true"
```

Or use affinity (like reference implementation):
```yaml
tvheadend:
  controllers:
    tvheadend:
      pod:
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
                - matchExpressions:
                    - key: hauppauge.feature.node.kubernetes.io/tuner
                      operator: In
                      values:
                        - "true"
```

---

## Advanced Features (Future Enhancements)

### Transcoding Support
- Add GPU access for hardware transcoding
- Configure transcoding profiles in TVHeadend
- May require Intel QuickSync or NVIDIA GPU

### External EPG Sources
- Configure XMLTV EPG source
- Set up automated EPG updates
- Integrate with third-party EPG providers

### Multi-Tuner Configuration
- Scale horizontally with multiple tuner nodes
- Configure priority and load balancing
- Set up tuner failover

### Integration with *arr Stack
- Sonarr can import TVHeadend recordings
- Automated post-processing of recordings
- Metadata enrichment via *arr services

---

## Next Steps

1. **Review this plan** - Confirm approach and configuration
2. **Implement Phase 1-3** - Add service configuration and storage
3. **Commit and deploy** - Let ArgoCD handle the deployment
4. **Configure TVHeadend** - Complete initial setup wizard
5. **Test functionality** - Verify tuner detection and recording
6. **Document usage** - Add to help documentation if needed

---

## Questions to Answer Before Implementation

1. **TV Tuner Hardware**: What type of tuner device? (USB/PCIe)
   - **Recommendation**: Document tuner model for troubleshooting

2. **Node Affinity**: Is tuner available on all nodes or specific node?
   - **Recommendation**: Add node selector if tuner is node-specific

3. **Authentication**: Enable TVHeadend authentication or open access?
   - **Recommendation**: Start without auth (internal only), add if needed

4. **Recording Retention**: Automatic cleanup or manual management?
   - **Recommendation**: Configure in TVHeadend based on disk space

5. **EPG Source**: Which EPG provider to use?
   - **Recommendation**: Start with OTA EPG, add XMLTV if needed

6. **Transcoding**: Enable hardware transcoding?
   - **Recommendation**: Start without, add GPU access if needed

---

## References

- **Reference Implementation**: https://github.com/samip5/k8s-cluster/blob/main/k8s/nebula/apps/media/tvheadend/app/hr.yaml
- **Official Chart**: https://github.com/geek-cookbook/charts/tree/main/charts/tvheadend
- **Docker Image**: https://docs.linuxserver.io/images/docker-tvheadend
- **TVHeadend Docs**: https://tvheadend.org/projects/tvheadend/wiki
- **SpencersLab chart workflow**: `skills/helm-chart-creation/` (SKILL.md + references/)
- **SpencersLab container workflow**: `skills/container-creation/SKILL.md`

---

**Status**: Ready for Implementation ✅  
**Estimated Effort**: 2-3 hours (including TVHeadend configuration)  
**Risk Level**: Medium (privileged container, hardware dependencies)  
**Maintenance**: Medium (EPG updates, recording management)

