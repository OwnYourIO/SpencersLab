# ActualBudget SSO Secret Implementation Plan

## Overview
Create a new `secret-actualbudget-sso.yaml` ExternalSecret template to support ActualBudget's new OAuth/OpenID Connect authentication method, replacing the current proxy-based SSO redirect approach.

## Background
ActualBudget has changed their OAuth implementation. Based on the [official documentation](https://actualbudget.org/docs/config/oauth-auth/), the new method uses environment variables for OpenID configuration instead of the previous proxy-based redirect approach.

## Current State
- **Chart**: `charts/actualbudget/` (single-container app-template based)
- **Service Integration**: `services/home/prod/values.yaml` (lines 817-876)
- **Proxy Config**: `services/proxy-local/prod/values.yaml` (line 163) - currently uses `ssoRedirectPath`
- **No existing SSO secret** for actualbudget

## Required Changes

### 1. Create `secret-actualbudget-sso.yaml`

**Location**: `services/home/prod/templates/secret-actualbudget-sso.yaml`

**Purpose**: ExternalSecret to inject OpenID Connect configuration as environment variables

**Environment Variables Needed** (from ActualBudget docs):
- `ACTUAL_OPENID_DISCOVERY_URL` - OpenID provider discovery URL
- `ACTUAL_OPENID_CLIENT_ID` - OAuth client ID
- `ACTUAL_OPENID_CLIENT_SECRET` - OAuth client secret
- `ACTUAL_OPENID_SERVER_HOSTNAME` - Public URL of Actual server
- `ACTUAL_OPENID_ENFORCE` - Force OpenID as only auth method (optional, default: false)
- `ACTUAL_USER_CREATION_MODE` - Auto-create users on first login (optional, default: manual)

**Bitwarden Structure**:
- **Secret Name**: `actualbudget-sso-secret`
- **Fields**:
  - `username` → `ACTUAL_OPENID_CLIENT_ID`
  - `password` → `ACTUAL_OPENID_CLIENT_SECRET`
  - Custom field `discovery_url` → `ACTUAL_OPENID_DISCOVERY_URL`

### 2. Update `services/home/prod/values.yaml`

**Add Bitwarden ID**:
```yaml
bitwardenIds:
  # ... existing entries ...
  actualbudget-sso-secret: OVERRIDE_VIA_CUSTOM_VALUES
```

**Update actualbudget configuration** to use the secret via `envFrom`:
```yaml
actualbudget:
  global:
    nameOverride: actualbudget
  controllers:
    actual:
      type: deployment
      containers:
        main:
          image: &img
            repository: ghcr.io/actualbudget/actual-server
            tag: 26.7.0@sha256:e18b7fbfec6157a368fad4146563f397502e9da70a120aeaeac63b4977405d1c
          env: &env
            TZ: America/Denver
            ACTUAL_PORT: &http 5006
            ACTUAL_DATA_DIR: &pvc /data
            ACTUAL_MULTIUSER: "true"
          envFrom:
            - secretRef:
                name: actualbudget-sso-secret
          # ... rest of config
```

### 3. Create `custom-values/actualbudget/prod-values.yaml`

**Location**: `custom-values/actualbudget/prod-values.yaml`

**Purpose**: Override Bitwarden ID with actual UUID

```yaml
bitwardenIds:
  actualbudget-sso-secret: <actual-bitwarden-uuid-here>
```

### 4. Update Proxy Configuration (Optional Cleanup)

**File**: `services/proxy-local/prod/values.yaml`

**Remove** the `ssoRedirectPath` for budget (line 163) since ActualBudget now handles OAuth internally:
```yaml
budget:
  target: budget
  # Remove: ssoRedirectPath: "/realms/..."
  loginSubDomain: "login"
```

## Implementation Steps

1. **Create ExternalSecret Template**
   - File: `services/home/prod/templates/secret-actualbudget-sso.yaml`
   - Use `bitwarden-login` SecretStore for client_id/client_secret
   - Use `bitwarden-fields` SecretStore for discovery_url
   - Template environment variables for OpenID configuration

2. **Update Service Values**
   - Add `actualbudget-sso-secret` to `bitwardenIds` in `services/home/prod/values.yaml`
   - Add `envFrom` reference to the secret in the actualbudget container config

3. **Create Custom Values Override**
   - File: `custom-values/actualbudget/prod-values.yaml`
   - Add actual Bitwarden UUID for `actualbudget-sso-secret`

4. **Update Proxy Config** (Optional)
   - Remove `ssoRedirectPath` from budget entry in `services/proxy-local/prod/values.yaml`

5. **Validation**
   - Run `helm lint charts/actualbudget`
   - Run `helm template charts/actualbudget --debug`
   - Verify secret template renders correctly
   - Check that environment variables are properly injected

## Template Structure

The `secret-actualbudget-sso.yaml` should follow this pattern (based on wekan-sso):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: actualbudget-sso-secret
spec:
  refreshInterval: 1h
  target:
    name: actualbudget-sso-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        ACTUAL_OPENID_DISCOVERY_URL: "{{ `{{ .discovery_url }}` }}"
        ACTUAL_OPENID_CLIENT_ID: "{{ `{{ .client_id }}` }}"
        ACTUAL_OPENID_CLIENT_SECRET: "{{ `{{ .client_secret }}` }}"
        ACTUAL_OPENID_SERVER_HOSTNAME: "https://budget.{{ .Values.domain }}"
        ACTUAL_OPENID_ENFORCE: "true"
        ACTUAL_USER_CREATION_MODE: "login"
  data:
    - secretKey: client_id
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "actualbudget-sso-secret" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: client_secret
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "actualbudget-sso-secret" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: discovery_url
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "actualbudget-sso-secret" }}'
        property: discovery_url
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

## Bitwarden Setup Required

Before deployment, create a Bitwarden item with:
- **Name**: `actualbudget-sso-secret` (or similar)
- **Username**: OAuth client ID from your OpenID provider
- **Password**: OAuth client secret from your OpenID provider
- **Custom Field**: `discovery_url` = OpenID provider discovery URL (e.g., `https://your-idp.com/.well-known/openid-configuration`)

## Notes

- The `ACTUAL_OPENID_SERVER_HOSTNAME` is constructed using the domain from values
- The initContainer `01-enable-openid` may no longer be needed with the new env-based config
- Setting `ACTUAL_OPENID_ENFORCE: "true"` forces SSO-only authentication
- Setting `ACTUAL_USER_CREATION_MODE: "login"` allows automatic user creation on first SSO login
- All environment variables are injected via the secret, not hardcoded in values.yaml

## Validation Checklist

- [ ] ExternalSecret template created and validates
- [ ] Service values.yaml updated with bitwardenId
- [ ] Custom values file created with actual UUID
- [ ] Secret renders correctly with `helm template`
- [ ] Environment variables properly referenced via `envFrom` in deployment
- [ ] Proxy configuration updated (if removing old SSO redirect)
- [ ] Bitwarden item created with correct fields
- [ ] Test deployment in dev environment
