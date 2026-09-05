# ActualBudget SSO Secret Implementation Summary

## Changes Implemented

### 1. Created ExternalSecret Template
**File**: `services/home/prod/templates/secret-actualbudget-sso.yaml`

This ExternalSecret template creates a Kubernetes secret with the following OpenID Connect environment variables:
- `ACTUAL_OPENID_DISCOVERY_URL` - OpenID provider discovery URL
- `ACTUAL_OPENID_CLIENT_ID` - OAuth client ID
- `ACTUAL_OPENID_CLIENT_SECRET` - OAuth client secret
- `ACTUAL_OPENID_SERVER_HOSTNAME` - Public URL of Actual server (constructed from domain)
- `ACTUAL_OPENID_ENFORCE` - Set to "true" to force SSO-only authentication
- `ACTUAL_USER_CREATION_MODE` - Set to "login" to auto-create users on first SSO login

The secret pulls values from Bitwarden using:
- `bitwarden-login` SecretStore for client_id (username) and client_secret (password)
- `bitwarden-fields` SecretStore for discovery_url (custom field)

### 2. Updated Service Values
**File**: `services/home/prod/values.yaml`

- Added `actualbudget-sso-secret: OVERRIDE_VIA_CUSTOM_VALUES` to `bitwardenIds` section
- Added `envFrom` configuration to the actualbudget container to inject the secret:
  ```yaml
  envFrom:
    - secretRef:
        name: actualbudget-sso-secret
  ```

### 3. Created Custom Values Override
**File**: `custom-values/actualbudget/prod-values.yaml`

This file needs to be updated with the actual Bitwarden UUID:
```yaml
bitwardenIds:
  actualbudget-sso-secret: OVERRIDE_WITH_ACTUAL_BITWARDEN_UUID
```

### 4. Updated Proxy Configuration
**File**: `services/proxy-local/prod/values.yaml`

Removed the `ssoRedirectPath` from the budget entry since ActualBudget now handles OAuth internally:
```yaml
budget:
  target: budget
  loginSubDomain: "login"
```

## Bitwarden Setup Required

Before deployment, create a Bitwarden item with:
- **Name**: `actualbudget-sso-secret` (or similar)
- **Username**: OAuth client ID from your OpenID provider
- **Password**: OAuth client secret from your OpenID provider
- **Custom Field**: `discovery_url` = OpenID provider discovery URL (e.g., `https://your-idp.com/.well-known/openid-configuration`)

Then update `custom-values/actualbudget/prod-values.yaml` with the actual UUID of this Bitwarden item.

## Validation Results

✓ Chart lints successfully (`helm lint charts/actualbudget`)
✓ Service template renders correctly with all OpenID environment variables
✓ Secret is properly referenced via `envFrom` in the deployment
✓ Domain substitution works correctly in `ACTUAL_OPENID_SERVER_HOSTNAME`

## Next Steps

1. Create the Bitwarden item with your OpenID provider credentials
2. Update `custom-values/actualbudget/prod-values.yaml` with the actual Bitwarden UUID
3. Commit and push changes to trigger ArgoCD sync
4. Verify the deployment in your cluster
5. Test SSO login to ActualBudget

## Notes

- The initContainer `01-enable-openid` is still present but may no longer be needed with the new env-based config
- `ACTUAL_OPENID_ENFORCE: "true"` forces SSO-only authentication (no password login)
- `ACTUAL_USER_CREATION_MODE: "login"` allows automatic user creation on first SSO login
- The old proxy-based SSO redirect has been removed in favor of ActualBudget's native OAuth support
