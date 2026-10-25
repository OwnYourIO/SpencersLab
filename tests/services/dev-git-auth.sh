#!/usr/bin/env bash
# Workspace git-auth wiring checks: a dev `forgejo-token` ExternalSecret
# (mirroring secret-github.yaml) plus the existing `github-pat` one feed
# GITHUB_TOKEN / FORGEJO_TOKEN / FORGEJO_HOST into the kubernetes-hardened
# workspace pods, and secret-github.yaml names the template as its in-repo
# consumer. The lab runs two Forgejo instances, so each pair exists per
# instance: `forgejo-token` (git.scifi.farm) and `forgejo-token-canonical`
# (git.spencerslab.com) -> FORGEJO_TOKEN_CANONICAL / FORGEJO_HOST_CANONICAL.
# No image change is needed: the baked startup script consumes those names.
# From replan v2 this suite also covers the DEV coder server itself: the
# coder-secrets ExternalSecret's gitea-type external-auth provider +
# CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS (c-sso-1..4), and — once C06 lands —
# the provider-id literal shared between that template, the kubernetes-hardened
# env and the workspace probe (c-sso-5..7). The gpu twin lives in
# tests/services/gpu-coder-sso.sh so this suite stays single-cluster-scoped.
#
# GREP CONVENTION: the secret-github.yaml check is deliberately
# COMMENT-INCLUSIVE. The claim this script forbids ("no in-repo consumer") lives
# in that file's header comment, so a code-lines-only grep could never see it.
# Every other check reads YAML/HCL structure, not prose.
#
# A helm binary is taken from C05_HELM_BIN, the PATH, /home/coder/.local/bin,
# or /tmp/opencode; failing that, helm v3.21.4 is downloaded there.
# charts/coder vendors no dependency, so `helm dependency build` runs on a COPY
# under /tmp/opencode — the downloaded .tgz never lands in the worktree.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/dev-git-auth.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SECRET_FORGEJO="services/dev/prod/templates/secret-forgejo-token.yaml"
SECRET_FORGEJO_CANONICAL="services/dev/prod/templates/secret-forgejo-token-canonical.yaml"
SECRET_GITHUB="services/dev/prod/templates/secret-github.yaml"
VALUES="services/dev/prod/values.yaml"
CUSTOM_VALUES="custom-values/dev/prod-values.yaml"
MAIN="charts/coder/coder-templates/kubernetes-hardened/main.tf"
CHART="charts/coder"
CHART_VALUES="$CHART/values.yaml"
SECRET_CODER="$CHART/templates/secret-coder.yaml"
SERVICE="services/dev/prod"
STARTUP="containers/coder-workspace/workspace-startup.sh"

UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
real_uuid=""

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

# Prints the lines nested under the first line matching $2 (an awk regex), i.e.
# until indentation returns to the key's own level. Blank and comment lines are
# skipped so a top-level comment cannot terminate a block early. Used instead of
# a bare grep where a same-named key elsewhere in the file would satisfy the
# check (e.g. `name:` in metadata vs target).
yaml_block() {
  local file="$1" keyrx="$2"
  awk -v keyrx="$keyrx" '
    !found {
      if ($0 ~ keyrx) { found = 1; match($0, /^[[:space:]]*/); base = RLENGTH }
      next
    }
    /^[[:space:]]*(#|$)/ { next }
    {
      match($0, /^[[:space:]]*/)
      if (RLENGTH <= base) exit
      print
    }
  ' "$file"
}

# Prints every block opened by $2 (an awk regex matching the opener line), one
# block per line with its newlines flattened, so each nested block can be
# grepped on its own. Indentation decides the end of a block, so HCL children
# (value_from -> secret_key_ref) stay inside their enclosing env block.
# Comment lines inside a block are dropped: prose must not satisfy a code check
# (a commented-out env block would otherwise look live), and a comment inside a
# block cannot break one either.
blocks() {
  local file="$1" opener="$2"
  awk -v opener="$opener" '
    !inblock {
      if ($0 ~ opener) {
        match($0, /^[[:space:]]*/)
        indent = RLENGTH
        buf = $0
        inblock = 1
      }
      next
    }
    {
      if ($0 ~ /^[[:space:]]*(#|\/\/)/) next
      buf = buf " " $0
      if ($0 ~ /^[[:space:]]*\}[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        if (RLENGTH == indent) {
          print buf
          buf = ""
          inblock = 0
        }
      }
    }
  ' "$file"
}

# Prints every `- secretKey:` item of an ExternalSecret's spec.data as one
# flattened line (comments and blank lines dropped). Binding per-entry keeps
# "the ea_secret entry reads coder-external-auth's password" from passing on
# file-wide mentions: store, remoteRef key and property must sit inside the
# same entry (C04's secret-coder.yaml carries five sibling entries already).
data_entries() {
  local file="$1"
  awk '
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*-[[:space:]]*secretKey:/ {
      if (buf != "") print buf
      match($0, /^[[:space:]]*/)
      base = RLENGTH
      buf = $0
      next
    }
    buf != "" {
      match($0, /^[[:space:]]*/)
      if (RLENGTH > base) { buf = buf " " $0; next }
      print buf
      buf = ""
    }
    END { if (buf != "") print buf }
  ' "$file"
}

# --- c1: the forgejo-token ExternalSecret mirrors secret-github.yaml --------
[ -f "$SECRET_FORGEJO" ] ||
  fail "c1: $SECRET_FORGEJO is missing (the forgejo-token ExternalSecret has not been added)"
ok "c1: $SECRET_FORGEJO exists"

grep -qE '^apiVersion:[[:space:]]*external-secrets\.io/v1[[:space:]]*(#.*)?$' "$SECRET_FORGEJO" ||
  fail "c1: $SECRET_FORGEJO is not external-secrets.io/v1 (secret-github.yaml's API version)"
grep -qE '^kind:[[:space:]]*ExternalSecret[[:space:]]*(#.*)?$' "$SECRET_FORGEJO" ||
  fail "c1: $SECRET_FORGEJO is not an ExternalSecret"
grep -qE '^[[:space:]]*name:[[:space:]]*forgejo-token[[:space:]]*(#.*)?$' "$SECRET_FORGEJO" ||
  fail "c1: no 'name: forgejo-token' in $SECRET_FORGEJO"
# The rendered Secret must live where the workspaces run; secret-github.yaml
# pins the same namespace for the same reason.
grep -qE '^[[:space:]]*namespace:[[:space:]]*default[[:space:]]*(#.*)?$' "$SECRET_FORGEJO" ||
  fail "c1: $SECRET_FORGEJO does not pin namespace: default (the workspace namespace; secret-github.yaml does)"
ok "c1: ExternalSecret v1 names forgejo-token in namespace default"

store=$(yaml_block "$SECRET_FORGEJO" '^[[:space:]]*secretStoreRef:')
printf '%s\n' "$store" | grep -qE '^[[:space:]]*name:[[:space:]]*bitwarden-login[[:space:]]*(#.*)?$' ||
  fail "c1: secretStoreRef does not use the bitwarden-login store"
printf '%s\n' "$store" | grep -qE '^[[:space:]]*kind:[[:space:]]*SecretStore[[:space:]]*(#.*)?$' ||
  fail "c1: secretStoreRef.kind is not SecretStore"
ok "c1: secretStoreRef is the bitwarden-login SecretStore"

grep -qE '^[[:space:]]*refreshInterval:[[:space:]]*[^[:space:]#]+' "$SECRET_FORGEJO" ||
  fail "c1: $SECRET_FORGEJO has no refreshInterval (secret-github.yaml refreshes every 1h)"
ok "c1: refreshInterval is set"

# Copied verbatim from secret-github.yaml: ArgoCD reports a field mismatch on
# the rendered Secret without them.
for key in conversionStrategy decodingStrategy metadataPolicy; do
  grep -qE "^[[:space:]]*${key}:[[:space:]]*[^[:space:]#]+" "$SECRET_FORGEJO" ||
    fail "c1: the remoteRef boilerplate field '$key' is missing (secret-github.yaml carries the Default/None/None trio)"
done
ok "c1: conversionStrategy/decodingStrategy/metadataPolicy boilerplate is present"

template_block=$(yaml_block "$SECRET_FORGEJO" '^[[:space:]]*template:')
printf '%s\n' "$template_block" | grep -qE '^[[:space:]]*FORGEJO_TOKEN:[[:space:]]*' ||
  fail "c1: target.template.data does not render a FORGEJO_TOKEN key"
ok "c1: the rendered Secret carries the FORGEJO_TOKEN key"

remote_ref=$(yaml_block "$SECRET_FORGEJO" '^[[:space:]]*remoteRef:')
printf '%s\n' "$remote_ref" | grep -qE '^[[:space:]]*property:[[:space:]]*password[[:space:]]*(#.*)?$' ||
  fail "c1: remoteRef does not read the item's password field (the dev-github convention)"
key_line=$(printf '%s\n' "$remote_ref" | grep -E '^[[:space:]]*key:' | head -n 1 || true)
[ -n "$key_line" ] || fail "c1: remoteRef has no key"
if ! printf '%s' "$key_line" | grep -q 'bitwardenIds' ||
  ! printf '%s' "$key_line" | grep -q 'forgejo-token'; then
  fail "c1: remoteRef.key does not read bitwardenIds.forgejo-token from the service values: $key_line"
fi
ok "c1: the token is the bitwardenIds.forgejo-token item's password"

# --- c2: sentinel in the service values, real UUID in custom-values --------
ids=$(yaml_block "$VALUES" '^bitwardenIds:')
printf '%s\n' "$ids" |
  grep -qE '^[[:space:]]*forgejo-token:[[:space:]]*OVERRIDE_VIA_CUSTOM_VALUES[[:space:]]*(#.*)?$' ||
  fail "c2: $VALUES has no 'forgejo-token: OVERRIDE_VIA_CUSTOM_VALUES' entry under bitwardenIds"
ok "c2: $VALUES carries the forgejo-token sentinel"

[ -f "$CUSTOM_VALUES" ] || fail "c2: $CUSTOM_VALUES is missing"
custom_ids=$(yaml_block "$CUSTOM_VALUES" '^bitwardenIds:')
entry=$(printf '%s\n' "$custom_ids" | grep -E '^[[:space:]]*forgejo-token:' | head -n 1 || true)
[ -n "$entry" ] || fail "c2: $CUSTOM_VALUES has no forgejo-token entry (the sentinel would survive to the cluster)"
if printf '%s' "$entry" | grep -qE 'OVERRIDE_VIA_CUSTOM_VALUES|OVERRIDE_NEEDED|OVERRIDE_VIA_APPSET'; then
  fail "c2: the custom-values forgejo-token entry is still a sentinel: $entry"
fi
printf '%s' "$entry" |
  grep -qE "^[[:space:]]*forgejo-token:[[:space:]]*${UUID_RE}[[:space:]]*(#.*)?$" ||
  fail "c2: the custom-values forgejo-token value is not UUID-shaped: $entry"
real_uuid=$(printf '%s' "$entry" | sed -E "s/.*forgejo-token:[[:space:]]*(${UUID_RE}).*/\1/")
ok "c2: the custom-values forgejo-token UUID is real ($real_uuid)"

# --- c3: the hardened template feeds the tokens to the workspace container ---
[ -f "$MAIN" ] || fail "c3: $MAIN is missing (C04 has not created the merged template)"
env_blocks=$(blocks "$MAIN" '^[[:space:]]*env[[:space:]]*\{')
[ -n "$env_blocks" ] || fail "c3: $MAIN has no container env blocks"

# The first flattened env block that sets name = "<var>".
env_block() {
  printf '%s\n' "$env_blocks" |
    grep -E "name[[:space:]]*=[[:space:]]*\"$1\"" | head -n 1 || true
}

token_block=$(env_block GITHUB_TOKEN)
[ -n "$token_block" ] || fail "c3: no container env block sets GITHUB_TOKEN"
printf '%s' "$token_block" | grep -qE 'secret_key_ref' ||
  fail "c3: GITHUB_TOKEN is not read from a secret_key_ref"
printf '%s' "$token_block" | grep -qE '"github-pat"' ||
  fail "c3: GITHUB_TOKEN does not reference the github-pat Secret"
printf '%s' "$token_block" | grep -qE '"GITHUB_PERSONAL_ACCESS_TOKEN"' ||
  fail "c3: GITHUB_TOKEN does not use the GITHUB_PERSONAL_ACCESS_TOKEN key"
printf '%s' "$token_block" | grep -qE 'optional[[:space:]]*=[[:space:]]*true' ||
  fail "c3: GITHUB_TOKEN's secret key ref is not optional = true (an absent Secret must not block workspace starts)"
ok "c3: GITHUB_TOKEN = github-pat/GITHUB_PERSONAL_ACCESS_TOKEN, optional"

forgejo_block=$(env_block FORGEJO_TOKEN)
[ -n "$forgejo_block" ] || fail "c3: no container env block sets FORGEJO_TOKEN"
printf '%s' "$forgejo_block" | grep -qE 'secret_key_ref' ||
  fail "c3: FORGEJO_TOKEN is not read from a secret_key_ref"
printf '%s' "$forgejo_block" | grep -qE '"forgejo-token"' ||
  fail "c3: FORGEJO_TOKEN does not reference the forgejo-token Secret"
printf '%s' "$forgejo_block" | grep -qE '"FORGEJO_TOKEN"' ||
  fail "c3: FORGEJO_TOKEN does not use the FORGEJO_TOKEN key"
printf '%s' "$forgejo_block" | grep -qE 'optional[[:space:]]*=[[:space:]]*true' ||
  fail "c3: FORGEJO_TOKEN's secret key ref is not optional = true (an absent Secret must not block workspace starts)"
ok "c3: FORGEJO_TOKEN = forgejo-token/FORGEJO_TOKEN, optional"

host_block=$(env_block FORGEJO_HOST)
[ -n "$host_block" ] || fail "c3: no container env block sets FORGEJO_HOST"
printf '%s' "$host_block" | grep -qE 'value[[:space:]]*=[[:space:]]*"git\.scifi\.farm"' ||
  fail "c3: FORGEJO_HOST is not the literal \"git.scifi.farm\" (no scheme, no trailing path — the startup script builds https://\$FORGEJO_HOST/)"
ok "c3: FORGEJO_HOST is the bare git.scifi.farm host"

# --- c5: secret-github.yaml no longer denies an in-repo consumer ------------
[ -f "$SECRET_GITHUB" ] || fail "c5: $SECRET_GITHUB is missing"
if grep -qi 'no in-repo consumer' "$SECRET_GITHUB"; then
  fail "c5: $SECRET_GITHUB still claims 'no in-repo consumer' (the kubernetes-hardened template consumes the Secret now)"
fi
ok "c5: the stale 'no in-repo consumer' claim is gone"
grep -q 'kubernetes-hardened' "$SECRET_GITHUB" ||
  fail "c5: $SECRET_GITHUB does not name the kubernetes-hardened template as its in-repo consumer"
ok "c5: $SECRET_GITHUB names the kubernetes-hardened template as its consumer"

# --- c6: the env names match what the baked image consumes -----------------
# No image change is part of this chunk; the names are C02's contract, so this
# catches a template that invents a variable the startup script never reads.
if [ -f "$STARTUP" ]; then
  for var in GITHUB_TOKEN FORGEJO_TOKEN FORGEJO_HOST; do
    grep -q "$var" "$STARTUP" ||
      fail "c6: $STARTUP never reads $var, so the template's env name has no consumer"
  done
  ok "c6: the baked startup script consumes GITHUB_TOKEN/FORGEJO_TOKEN/FORGEJO_HOST"
else
  skip "c6: $STARTUP is absent, so the env-name contract could not be cross-checked"
fi

# --- c-canonical-1: the canonical ExternalSecret mirrors c1's checks --------
[ -f "$SECRET_FORGEJO_CANONICAL" ] ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL is missing (the forgejo-token-canonical ExternalSecret has not been added)"
ok "c-canonical-1: $SECRET_FORGEJO_CANONICAL exists"

grep -qE '^apiVersion:[[:space:]]*external-secrets\.io/v1[[:space:]]*(#.*)?$' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL is not external-secrets.io/v1"
grep -qE '^kind:[[:space:]]*ExternalSecret[[:space:]]*(#.*)?$' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL is not an ExternalSecret"
grep -qE '^[[:space:]]*name:[[:space:]]*forgejo-token-canonical[[:space:]]*(#.*)?$' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: no 'name: forgejo-token-canonical' in $SECRET_FORGEJO_CANONICAL"
grep -qE '^[[:space:]]*namespace:[[:space:]]*default[[:space:]]*(#.*)?$' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL does not pin namespace: default (the workspace namespace)"
ok "c-canonical-1: ExternalSecret v1 names forgejo-token-canonical in namespace default"

store=$(yaml_block "$SECRET_FORGEJO_CANONICAL" '^[[:space:]]*secretStoreRef:')
printf '%s\n' "$store" | grep -qE '^[[:space:]]*name:[[:space:]]*bitwarden-login[[:space:]]*(#.*)?$' ||
  fail "c-canonical-1: secretStoreRef does not use the bitwarden-login store"
printf '%s\n' "$store" | grep -qE '^[[:space:]]*kind:[[:space:]]*SecretStore[[:space:]]*(#.*)?$' ||
  fail "c-canonical-1: secretStoreRef.kind is not SecretStore"
ok "c-canonical-1: secretStoreRef is the bitwarden-login SecretStore"

grep -qE '^[[:space:]]*refreshInterval:[[:space:]]*[^[:space:]#]+' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL has no refreshInterval"
ok "c-canonical-1: refreshInterval is set"

for key in conversionStrategy decodingStrategy metadataPolicy; do
  grep -qE "^[[:space:]]*${key}:[[:space:]]*[^[:space:]#]+" "$SECRET_FORGEJO_CANONICAL" ||
    fail "c-canonical-1: the remoteRef boilerplate field '$key' is missing (the ArgoCD Default/None/None trio)"
done
ok "c-canonical-1: conversionStrategy/decodingStrategy/metadataPolicy boilerplate is present"

template_block=$(yaml_block "$SECRET_FORGEJO_CANONICAL" '^[[:space:]]*template:')
printf '%s\n' "$template_block" | grep -qE '^[[:space:]]*FORGEJO_TOKEN_CANONICAL:[[:space:]]*' ||
  fail "c-canonical-1: target.template.data does not render a FORGEJO_TOKEN_CANONICAL key"
ok "c-canonical-1: the rendered Secret carries the FORGEJO_TOKEN_CANONICAL key"

remote_ref=$(yaml_block "$SECRET_FORGEJO_CANONICAL" '^[[:space:]]*remoteRef:')
printf '%s\n' "$remote_ref" | grep -qE '^[[:space:]]*property:[[:space:]]*password[[:space:]]*(#.*)?$' ||
  fail "c-canonical-1: remoteRef does not read the item's password field (the PASSWORD-field convention)"
key_line=$(printf '%s\n' "$remote_ref" | grep -E '^[[:space:]]*key:' | head -n 1 || true)
[ -n "$key_line" ] || fail "c-canonical-1: remoteRef has no key"
if ! printf '%s' "$key_line" | grep -q 'bitwardenIds' ||
  ! printf '%s' "$key_line" | grep -q 'forgejo-token-canonical'; then
  fail "c-canonical-1: remoteRef.key does not read bitwardenIds.forgejo-token-canonical from the service values: $key_line"
fi
ok "c-canonical-1: the token is the bitwardenIds.forgejo-token-canonical item's password"

# Comment-inclusive like the c5 github check: the consumers live only in the
# header, and with two near-identical forgejo-token secrets in one folder the
# header is what tells a reader which instance this one serves.
grep -q 'git\.spencerslab\.com' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL never names git.spencerslab.com (the instance it serves)"
grep -q 'kubernetes-hardened' "$SECRET_FORGEJO_CANONICAL" ||
  fail "c-canonical-1: $SECRET_FORGEJO_CANONICAL does not name the kubernetes-hardened template as its consumer"
ok "c-canonical-1: the header comment names the canonical instance and the kubernetes-hardened consumer"

# --- c-canonical-2: sentinel in the service values, UUID slot in custom ------
printf '%s\n' "$ids" |
  grep -qE '^[[:space:]]*forgejo-token-canonical:[[:space:]]*OVERRIDE_VIA_CUSTOM_VALUES[[:space:]]*(#.*)?$' ||
  fail "c-canonical-2: $VALUES has no 'forgejo-token-canonical: OVERRIDE_VIA_CUSTOM_VALUES' entry under bitwardenIds"

custom_entry=$(printf '%s\n' "$custom_ids" | grep -E '^[[:space:]]*forgejo-token-canonical:' | head -n 1 || true)
[ -n "$custom_entry" ] || fail "c-canonical-2: $CUSTOM_VALUES has no forgejo-token-canonical entry (the sentinel would survive to the cluster)"
if printf '%s' "$custom_entry" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
  fail "c-canonical-2: the custom-values forgejo-token-canonical entry is still the service sentinel: $custom_entry"
fi
# OVERRIDE_NEEDED is tolerated until User action 1 creates the Bitwarden item
# (the infra-forgejo t6 precedent); unlike the service sentinel it is a
# documented slot, not a value that would render as an item name forever.
printf '%s' "$custom_entry" |
  grep -qE "^[[:space:]]*forgejo-token-canonical:[[:space:]]*(OVERRIDE_NEEDED|${UUID_RE})[[:space:]]*(#.*)?$" ||
  fail "c-canonical-2: the custom-values forgejo-token-canonical value is neither a real UUID nor the documented OVERRIDE_NEEDED placeholder: $custom_entry"
custom_slot=$(printf '%s' "$custom_entry" | sed -E 's/.*forgejo-token-canonical:[[:space:]]*([^[:space:]#]+).*/\1/')
ok "c-canonical-2: the canonical sentinel is paired with a custom-values slot ($custom_slot)"

# --- c-canonical-3: the hardened template feeds the canonical pair to pods ----
token_can_block=$(env_block FORGEJO_TOKEN_CANONICAL)
[ -n "$token_can_block" ] || fail "c-canonical-3: no container env block sets FORGEJO_TOKEN_CANONICAL"
printf '%s' "$token_can_block" | grep -qE 'secret_key_ref' ||
  fail "c-canonical-3: FORGEJO_TOKEN_CANONICAL is not read from a secret_key_ref"
printf '%s' "$token_can_block" | grep -qE '"forgejo-token-canonical"' ||
  fail "c-canonical-3: FORGEJO_TOKEN_CANONICAL does not reference the forgejo-token-canonical Secret"
printf '%s' "$token_can_block" | grep -qE 'key[[:space:]]*=[[:space:]]*"FORGEJO_TOKEN_CANONICAL"' ||
  fail "c-canonical-3: FORGEJO_TOKEN_CANONICAL does not use the FORGEJO_TOKEN_CANONICAL Secret key"
printf '%s' "$token_can_block" | grep -qE 'optional[[:space:]]*=[[:space:]]*true' ||
  fail "c-canonical-3: FORGEJO_TOKEN_CANONICAL's secret key ref is not optional = true (the Secret only exists on-cluster after User action 1)"

host_can_block=$(env_block FORGEJO_HOST_CANONICAL)
[ -n "$host_can_block" ] || fail "c-canonical-3: no container env block sets FORGEJO_HOST_CANONICAL"
printf '%s' "$host_can_block" | grep -qE 'value[[:space:]]*=[[:space:]]*"git\.spencerslab\.com"' ||
  fail "c-canonical-3: FORGEJO_HOST_CANONICAL is not the literal \"git.spencerslab.com\" (no scheme, no trailing path — the startup script builds https://\$FORGEJO_HOST_CANONICAL/)"
ok "c-canonical-3: FORGEJO_TOKEN_CANONICAL (forgejo-token-canonical Secret, optional) + FORGEJO_HOST_CANONICAL bare host"

# --- c-canonical-4: c6 extension — the canonical names cross the script boundary
if [ -f "$STARTUP" ]; then
  for var in FORGEJO_TOKEN_CANONICAL FORGEJO_HOST_CANONICAL; do
    grep -q "$var" "$STARTUP" ||
      fail "c-canonical-4: $STARTUP never reads $var, so the template's canonical env name has no consumer"
  done
  ok "c-canonical-4: the baked startup script consumes the canonical pair too"
else
  skip "c-canonical-4: $STARTUP is absent, so the canonical env-name contract could not be cross-checked"
fi

# --- c-sso-1: the dev coder server carries the provider + encryption keys ---
# Comment-inclusive per the chunk: the header rationale (per-user SSO
# approval; coderd stores external tokens plaintext unless
# CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS is set) is part of the C04 contract,
# and the provider id is contractual, not cosmetic — the forge-side OAuth app
# whitelists /external-auth/<ID>/callback (v2.35.2 docs).
[ -f "$SECRET_CODER" ] || fail "c-sso-1: $SECRET_CODER is missing"

grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_ID:[[:space:]]*"forgejo"[[:space:]]*(#.*)?$' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_AUTH_0_ID is not the literal \"forgejo\" — the provider id embeds the callback path the dev forge's OAuth app must whitelist"
ok "c-sso-1: provider id literal is \"forgejo\""

grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_TYPE:[[:space:]]*"gitea"[[:space:]]*(#.*)?$' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_AUTH_0_TYPE is not \"gitea\" (giteaDefaults() derives TOKEN_URL/VALIDATE_URL/REGEX against Forgejo 15 from the AUTH_URL host)"
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_DISPLAY_NAME:[[:space:]]*"Forgejo"[[:space:]]*(#.*)?$' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_AUTH_0_DISPLAY_NAME is not \"Forgejo\""
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_AUTH_URL:[[:space:]]*"https://git\.scifi\.farm/login/oauth/authorize"[[:space:]]*(#.*)?$' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_AUTH_0_AUTH_URL is not the dev-forge authorize path (pairing ruling: the dev coder's one slot spends itself on git.scifi.farm)"
ok "c-sso-1: TYPE/DISPLAY_NAME/AUTH_URL literals match the dev pairing"

# v2-template indirection: the fetched values enter target.template.data
# through the {{ \`{{ .x }}\` }} escape like the existing CODER_OIDC_* lines —
# binding template key → secretKey, not just key presence.
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_CLIENT_ID:.*ea_client_id' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_AUTH_0_CLIENT_ID does not indirect through secretKey ea_client_id"
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_CLIENT_SECRET:.*ea_secret' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_AUTH_0_CLIENT_SECRET does not indirect through secretKey ea_secret"
grep -qE '^[[:space:]]*CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS:.*token_encryption_keys' "$SECRET_CODER" ||
  fail "c-sso-1: CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS does not indirect through secretKey token_encryption_keys"
ok "c-sso-1: all seven target.template.data keys present with their secretKey wirings"

entries=$(data_entries "$SECRET_CODER")
ea_client=$(printf '%s\n' "$entries" | grep -E 'secretKey:[[:space:]]*ea_client_id([^A-Za-z0-9_]|$)' | head -n 1 || true)
ea_secret=$(printf '%s\n' "$entries" | grep -E 'secretKey:[[:space:]]*ea_secret([^A-Za-z0-9_]|$)' | head -n 1 || true)
token_keys=$(printf '%s\n' "$entries" | grep -E 'secretKey:[[:space:]]*token_encryption_keys([^A-Za-z0-9_]|$)' | head -n 1 || true)
[ -n "$ea_client" ] || fail "c-sso-1: no '- secretKey: ea_client_id' data entry"
[ -n "$ea_secret" ] || fail "c-sso-1: no '- secretKey: ea_secret' data entry"
[ -n "$token_keys" ] || fail "c-sso-1: no '- secretKey: token_encryption_keys' data entry"
printf '%s' "$ea_client" | grep -q 'bitwarden-login' ||
  fail "c-sso-1: the ea_client_id entry does not read through the bitwarden-login store"
printf '%s' "$ea_client" | grep -q '"coder-external-auth"' ||
  fail "c-sso-1: the ea_client_id entry does not reference bitwardenIds.coder-external-auth"
printf '%s' "$ea_client" | grep -qE 'property:[[:space:]]*username' ||
  fail "c-sso-1: ea_client_id does not read the OAuth client id from the item's username field"
printf '%s' "$ea_secret" | grep -q 'bitwarden-login' ||
  fail "c-sso-1: the ea_secret entry does not read through the bitwarden-login store"
printf '%s' "$ea_secret" | grep -q '"coder-external-auth"' ||
  fail "c-sso-1: the ea_secret entry does not reference bitwardenIds.coder-external-auth"
printf '%s' "$ea_secret" | grep -qE 'property:[[:space:]]*password' ||
  fail "c-sso-1: ea_secret does not read the client secret from the item's password field"
printf '%s' "$token_keys" | grep -q 'bitwarden-login' ||
  fail "c-sso-1: the token_encryption_keys entry does not read through the bitwarden-login store"
printf '%s' "$token_keys" | grep -q '"coder-token-encryption"' ||
  fail "c-sso-1: the token_encryption_keys entry does not reference bitwardenIds.coder-token-encryption"
printf '%s' "$token_keys" | grep -qE 'property:[[:space:]]*password' ||
  fail "c-sso-1: token_encryption_keys does not read the base64 key from the item's password field"
for trio in conversionStrategy decodingStrategy metadataPolicy; do
  for e in "$ea_client" "$ea_secret" "$token_keys"; do
    printf '%s' "$e" | grep -q "$trio" ||
      fail "c-sso-1: an external-auth/encryption data entry is missing the ArgoCD $trio boilerplate (the file's existing entry shape)"
  done
done
ok "c-sso-1: three data entries carry store, bitwardenIds reference, property and the Default/None/None trio"

# giteaDefaults() owns the derivation (source-verified at the deployed tag);
# explicit copies would drift from it. Code-line scan — a comment explaining
# why they are ABSENT legitimately names them.
bad_derived=$(grep -vE '^[[:space:]]*#' "$SECRET_CODER" |
  grep -E '^[[:space:]]*CODER_EXTERNAL_AUTH_0_(REGEX|TOKEN_URL|VALIDATE_URL):' | head -n 1 || true)
[ -z "$bad_derived" ] ||
  fail "c-sso-1: explicit derived provider key re-added ($bad_derived) — giteaDefaults() must own it"
ok "c-sso-1: no explicit _REGEX/_TOKEN_URL/_VALIDATE_URL keys (giteaDefaults derivation trusted)"

# --- c-sso-2: chart sentinels + custom-values slots -------------------------
# The coder-external-auth/coder-token-encryption items are per-cluster (same
# bitwardenIds key, different item — the coder-pg precedent), so dev's UUIDs
# land under the coder: block's bitwardenIds here, not at the top level.
chart_ids=$(yaml_block "$CHART_VALUES" '^bitwardenIds:')
printf '%s\n' "$chart_ids" |
  grep -qE '^[[:space:]]*coder-external-auth:[[:space:]]*OVERRIDE_VIA_CUSTOM_VALUES[[:space:]]*(#.*)?$' ||
  fail "c-sso-2: $CHART_VALUES has no 'coder-external-auth: OVERRIDE_VIA_CUSTOM_VALUES' entry under bitwardenIds"
printf '%s\n' "$chart_ids" |
  grep -qE '^[[:space:]]*coder-token-encryption:[[:space:]]*OVERRIDE_VIA_CUSTOM_VALUES[[:space:]]*(#.*)?$' ||
  fail "c-sso-2: $CHART_VALUES has no 'coder-token-encryption: OVERRIDE_VIA_CUSTOM_VALUES' entry under bitwardenIds"
ok "c-sso-2: $CHART_VALUES carries both new sentinels"

coder_cv=$(yaml_block "$CUSTOM_VALUES" '^coder:')
coder_cv_ids=$(yaml_block <(printf '%s\n' "$coder_cv") '^[[:space:]]*bitwardenIds:')
for key in coder-external-auth coder-token-encryption; do
  custom_entry=$(printf '%s\n' "$coder_cv_ids" | grep -E "^[[:space:]]*${key}:" | head -n 1 || true)
  [ -n "$custom_entry" ] || fail "c-sso-2: $CUSTOM_VALUES coder.bitwardenIds has no ${key} entry (the sentinel would survive to the cluster)"
  if printf '%s' "$custom_entry" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
    fail "c-sso-2: the custom-values ${key} entry is still the service sentinel: $custom_entry"
  fi
  # OVERRIDE_NEEDED is the documented must-fill slot until the user creates
  # the Bitwarden item (the forgejo-token-canonical precedent above).
  printf '%s' "$custom_entry" |
    grep -qE "^[[:space:]]*${key}:[[:space:]]*(OVERRIDE_NEEDED|${UUID_RE})[[:space:]]*(#.*)?$" ||
    fail "c-sso-2: the custom-values ${key} value is neither a real UUID nor the documented OVERRIDE_NEEDED placeholder: $custom_entry"
  ok "c-sso-2: custom-values/dev ${key} slot is a real UUID or the documented placeholder"
done

# --- c4: helm lint/template and the rendered ExternalSecret ----------------
find_helm() {
  local cand
  if [ -n "${C05_HELM_BIN:-}" ] && [ -x "${C05_HELM_BIN}" ]; then
    printf '%s' "$C05_HELM_BIN"
    return 0
  fi
  if command -v helm >/dev/null 2>&1; then
    command -v helm
    return 0
  fi
  if [ -x /home/coder/.local/bin/helm ]; then
    printf '%s' "/home/coder/.local/bin/helm"
    return 0
  fi
  cand=$(find /tmp/opencode -maxdepth 4 -type f -name helm -perm -u+x 2>/dev/null | head -n 1 || true)
  if [ -n "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  return 1
}

# Pinned to the version PLAN.md names; the checksum asset ships with the tarball
# and carries the file name, so `sha256sum -c` validates it directly.
download_helm() {
  local version=3.21.4 arch dir tar expected
  command -v curl >/dev/null 2>&1 || { printf 'skip-note: curl is unavailable\n' >&2; return 1; }
  command -v tar >/dev/null 2>&1 || { printf 'skip-note: tar is unavailable\n' >&2; return 1; }
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) printf 'skip-note: unsupported architecture %s\n' "$(uname -m)" >&2; return 1 ;;
  esac
  dir=/tmp/opencode/c05-helm-download
  mkdir -p "$dir"
  tar="$dir/helm-v${version}-linux-${arch}.tar.gz"
  curl -fsSL --max-time 120 -o "$tar" \
    "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz" >/dev/null 2>&1 || {
    printf 'skip-note: helm %s download failed\n' "$version" >&2
    return 1
  }
  curl -fsSL --max-time 30 -o "${tar}.sha256sum" "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz.sha256sum" >/dev/null 2>&1 || {
    printf 'skip-note: helm %s checksum download failed\n' "$version" >&2
    return 1
  }
  (cd "$dir" && sha256sum -c "$(basename "$tar").sha256sum" >/dev/null 2>&1) || {
    printf 'skip-note: helm %s tarball failed checksum verification\n' "$version" >&2
    return 1
  }
  tar -xzf "$tar" -C "$dir" || { printf 'skip-note: helm tarball extraction failed\n' >&2; return 1; }
  expected=$(find "$dir" -type f -name helm -perm -u+x | head -n 1 || true)
  [ -n "$expected" ] || { printf 'skip-note: no helm binary in the extracted tarball\n' >&2; return 1; }
  printf '%s' "$expected"
}

helm_bin=$(find_helm || true)
if [ -z "$helm_bin" ]; then
  helm_bin=$(download_helm || true)
fi

if [ -z "$helm_bin" ]; then
  skip "c4: no helm binary on PATH or in /tmp/opencode, and none could be downloaded there; gate $CHART separately with helm dependency build + lint + template"
  skip "c-sso-3: coder-secrets render ladder not run (no helm binary)"
  skip "c-sso-4: pod-annotation render check not run (no helm binary)"
else
  helm_version=$("$helm_bin" version --short 2>/dev/null || true)
  chart_copy=$(mktemp -d /tmp/opencode/c05-helm-XXXXXX)
  cp -R "$CHART"/. "$chart_copy"/
  dep_log="$chart_copy/dependency-build.log"

  if ! (cd "$chart_copy" && "$helm_bin" dependency build .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "c4: helm dependency build could not reach helm.coder.com here, so lint/template were not run (log kept at $dep_log)"
      skip "c-sso-3: coder-secrets render ladder not run (dependency build unreachable)"
      skip "c-sso-4: pod-annotation render check not run (dependency build unreachable)"
    else
      tail -n 30 "$dep_log" >&2
      fail "c4: helm dependency build failed on a copy of $CHART (log kept at $dep_log)"
    fi
  else
    ok "c4: helm dependency build succeeds on a copy of $CHART ($helm_version)"

    lint_log="$chart_copy/lint.log"
    if (cd "$chart_copy" && "$helm_bin" lint .) >"$lint_log" 2>&1; then
      ok "c4: helm lint passes on $CHART"
    else
      tail -n 30 "$lint_log" >&2
      fail "c4: helm lint failed for $CHART (log kept at $lint_log)"
    fi

    template_log="$chart_copy/template.log"
    if (cd "$chart_copy" && "$helm_bin" template coder .) >"$template_log" 2>/dev/null; then
      [ -s "$template_log" ] || fail "c4: helm template rendered nothing for $CHART"
      ok "c4: helm template renders $CHART"
    else
      fail "c4: helm template failed for $CHART (log kept at $template_log)"
    fi

    # No custom-values file: the sentinel has to be replaced by the --set value,
    # which is exactly how the ApplicationSet injects it at deploy time.
    dev_out=$(mktemp /tmp/opencode/c05-dev-XXXXXX.yaml)
    dev_err=$(mktemp /tmp/opencode/c05-dev-XXXXXX.err)
    if "$helm_bin" template dev "$SERVICE" --set bitwardenIds.forgejo-token=test-uuid \
      >"$dev_out" 2>"$dev_err"; then
      # Split the multi-document stream; the target doc is the ExternalSecret
      # named forgejo-token (the github-pat one is a sibling, not a
      # substitute). The trailing [^A-Za-z0-9_-] keeps the sibling
      # forgejo-token-canonical doc out of a prefix-only match.
      forgejo_doc=$(awk '
        function flush() {
          if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*forgejo-token[^A-Za-z0-9_-]/) print buf
        }
        /^---[[:space:]]*$/ { flush(); buf = ""; next }
        { buf = buf $0 "\n" }
        END { flush() }
      ' "$dev_out")
      [ -n "$forgejo_doc" ] ||
        fail "c4: helm template dev $SERVICE --set bitwardenIds.forgejo-token=test-uuid renders no forgejo-token ExternalSecret"
      printf '%s' "$forgejo_doc" | grep -q 'FORGEJO_TOKEN' ||
        fail "c4: the rendered forgejo-token ExternalSecret has no FORGEJO_TOKEN key"
      printf '%s' "$forgejo_doc" | grep -q 'test-uuid' ||
        fail "c4: the rendered ExternalSecret ignores --set bitwardenIds.forgejo-token (the key is not taken from the values map)"
      if printf '%s' "$forgejo_doc" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
        fail "c4: the rendered forgejo-token ExternalSecret still carries OVERRIDE_VIA_CUSTOM_VALUES"
      fi
      ok "c4: the dev umbrella renders forgejo-token with the --set UUID and no unresolved sentinel"

      # c-canonical-5: the same ladder for the canonical ExternalSecret — the
      # template's secret_key_ref and the script's env names both key off this
      # document, so its name and template key are asserted at render time.
      dev_can_out=$(mktemp /tmp/opencode/c05-dev-XXXXXX.yaml)
      if "$helm_bin" template dev "$SERVICE" --set bitwardenIds.forgejo-token-canonical=test-uuid \
        >"$dev_can_out" 2>/dev/null; then
        canonical_doc=$(awk '
          function flush() {
            if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*forgejo-token-canonical/) print buf
          }
          /^---[[:space:]]*$/ { flush(); buf = ""; next }
          { buf = buf $0 "\n" }
          END { flush() }
        ' "$dev_can_out")
        [ -n "$canonical_doc" ] ||
          fail "c-canonical-5: helm template dev $SERVICE --set bitwardenIds.forgejo-token-canonical=test-uuid renders no forgejo-token-canonical ExternalSecret"
        printf '%s' "$canonical_doc" | grep -q 'FORGEJO_TOKEN_CANONICAL' ||
          fail "c-canonical-5: the rendered forgejo-token-canonical ExternalSecret has no FORGEJO_TOKEN_CANONICAL key"
        printf '%s' "$canonical_doc" | grep -q 'test-uuid' ||
          fail "c-canonical-5: the rendered ExternalSecret ignores --set bitwardenIds.forgejo-token-canonical (the key is not taken from the values map)"
        if printf '%s' "$canonical_doc" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
          fail "c-canonical-5: the rendered forgejo-token-canonical ExternalSecret still carries OVERRIDE_VIA_CUSTOM_VALUES"
        fi
        ok "c-canonical-5: the dev umbrella renders forgejo-token-canonical with the --set UUID and no unresolved sentinel"
      else
        fail "c-canonical-5: helm template dev $SERVICE --set bitwardenIds.forgejo-token-canonical=test-uuid failed"
      fi

      # Second render on the real deploy path: the custom-values file the
      # cluster annotation loads must resolve the sentinel to the real item.
      if [ -n "$real_uuid" ]; then
        devf_out=$(mktemp /tmp/opencode/c05-dev-XXXXXX.yaml)
        if "$helm_bin" template dev "$SERVICE" -f "$CUSTOM_VALUES" >"$devf_out" 2>/dev/null; then
          real_doc=$(awk '
            function flush() {
              if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*forgejo-token[^A-Za-z0-9_-]/) print buf
            }
            /^---[[:space:]]*$/ { flush(); buf = ""; next }
            { buf = buf $0 "\n" }
            END { flush() }
          ' "$devf_out")
          [ -n "$real_doc" ] ||
            fail "c4: helm template dev $SERVICE -f $CUSTOM_VALUES renders no forgejo-token ExternalSecret"
          if printf '%s' "$real_doc" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
            fail "c4: $CUSTOM_VALUES does not resolve the forgejo-token sentinel in the rendered ExternalSecret"
          fi
          printf '%s' "$real_doc" | grep -q "$real_uuid" ||
            fail "c4: the rendered ExternalSecret does not carry the custom-values UUID $real_uuid"
          ok "c4: $CUSTOM_VALUES resolves the sentinel to the real UUID at render time"

          # The canonical doc on the same real-deploy path: its custom-values
          # slot may legitimately hold OVERRIDE_NEEDED until User action 1,
          # but the service sentinel must never survive the layering.
          canonical_f_doc=$(awk '
            function flush() {
              if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*forgejo-token-canonical/) print buf
            }
            /^---[[:space:]]*$/ { flush(); buf = ""; next }
            { buf = buf $0 "\n" }
            END { flush() }
          ' "$devf_out")
          [ -n "$canonical_f_doc" ] ||
            fail "c-canonical-5: helm template dev $SERVICE -f $CUSTOM_VALUES renders no forgejo-token-canonical ExternalSecret"
          if printf '%s' "$canonical_f_doc" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
            fail "c-canonical-5: $CUSTOM_VALUES does not resolve the forgejo-token-canonical sentinel in the rendered ExternalSecret"
          fi
          ok "c-canonical-5: the custom-values render leaves the canonical document free of the service sentinel"
        else
          fail "c4: helm template dev $SERVICE -f $CUSTOM_VALUES failed (see the message above)"
        fi
      fi
    else
      tail -n 30 "$dev_err" >&2
      fail "c4: helm template dev $SERVICE --set bitwardenIds.forgejo-token=test-uuid failed"
    fi

    # --- c-sso-3: the coder-secrets render ladder (charts/coder) -----------
    # Every bitwardenIds key the coder-secrets document consumes is resolved
    # --set-style, including the pre-existing coder-sso-secret/coder-pg legs:
    # their sentinels render INTO THE SAME DOCUMENT the no-OVERRIDE contract
    # reads, and at deploy time the custom-values layer resolves them (the
    # plan's --set list abbreviated that).
    sso3_out=$(mktemp /tmp/opencode/c05-sso3-XXXXXX.yaml)
    sso3_err=$(mktemp /tmp/opencode/c05-sso3-XXXXXX.err)
    if "$helm_bin" template coder "$chart_copy" \
      --set domain=test.example.com \
      --set bitwardenIds.coder-external-auth=test-uuid-ea \
      --set bitwardenIds.coder-token-encryption=test-uuid-key \
      --set bitwardenIds.coder-sso-secret=test-uuid-sso \
      --set bitwardenIds.coder-pg=test-uuid-pg \
      >"$sso3_out" 2>"$sso3_err"; then
      coder_doc=$(awk '
        function flush() {
          if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*coder-secrets([[:space:]]|$)/) print buf
        }
        /^---[[:space:]]*$/ { flush(); buf = ""; next }
        { buf = buf $0 "\n" }
        END { flush() }
      ' "$sso3_out")
      [ -n "$coder_doc" ] ||
        fail "c-sso-3: the charts/coder render carries no coder-secrets ExternalSecret"
      for key in CODER_EXTERNAL_AUTH_0_ID CODER_EXTERNAL_AUTH_0_TYPE CODER_EXTERNAL_AUTH_0_DISPLAY_NAME \
        CODER_EXTERNAL_AUTH_0_AUTH_URL CODER_EXTERNAL_AUTH_0_CLIENT_ID CODER_EXTERNAL_AUTH_0_CLIENT_SECRET \
        CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS; do
        printf '%s' "$coder_doc" | grep -q "$key" ||
          fail "c-sso-3: the rendered coder-secrets document lost the $key template key"
      done
      printf '%s' "$coder_doc" | grep -q 'forgejo' ||
        fail "c-sso-3: the rendered coder-secrets document has no forgejo provider id"
      printf '%s' "$coder_doc" | grep -q 'https://git.scifi.farm/login/oauth/authorize' ||
        fail "c-sso-3: the rendered coder-secrets document lost the dev-forge AUTH_URL"
      printf '%s' "$coder_doc" | grep -q 'test-uuid-ea' ||
        fail "c-sso-3: the rendered coder-secrets document ignores --set bitwardenIds.coder-external-auth"
      printf '%s' "$coder_doc" | grep -q 'test-uuid-key' ||
        fail "c-sso-3: the rendered coder-secrets document ignores --set bitwardenIds.coder-token-encryption"
      if printf '%s' "$coder_doc" | grep -q 'OVERRIDE'; then
        fail "c-sso-3: the rendered coder-secrets document still carries an OVERRIDE_* sentinel"
      fi
      ok "c-sso-3: the coder-secrets render carries all seven keys, forgejo + dev AUTH_URL, both test UUIDs, no sentinel"

      # c-sso-4: coderd reads provider/encryption env at process start only —
      # without a secret-change restart the first sync would sit inert, so the
      # pod template must carry the reloader annotation (Reloader runs
      # cluster-wide on dev: dev-reloader-reloader 1/1, live-verified).
      if python3 - "$sso3_out" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
dep = [d for d in docs if d.get('kind') == 'Deployment' and d['metadata']['name'] == 'coder']
if not dep:
    print('FAIL: c-sso-4: the charts/coder render has no Deployment named coder', file=sys.stderr)
    sys.exit(1)
ann = ((dep[0]['spec']['template'].get('metadata') or {}).get('annotations') or {})
if ann.get('reloader.stakater.com/auto') != 'true':
    print(f'FAIL: c-sso-4: the coderd pod template annotations are {ann!r} — coder.coder.podAnnotations did not reach the pod', file=sys.stderr)
    sys.exit(1)
PY
      then
        ok "c-sso-4: the coder Deployment pod template carries reloader.stakater.com/auto=\"true\""
      else
        exit 1
      fi

      # Second leg: the real deploy path — the coder: slice of
      # custom-values/dev (what the ApplicationSet feeds the chart) must
      # resolve the wired provider slots to their UUIDs; the OVERRIDE_NEEDED
      # era ended when the user supplied the item UUIDs (2026-10-25).
      coder_slice="$sso3_out.coder-block.yaml"
      if ! printf '%s\n' "$coder_cv" | python3 -c 'import sys, yaml; yaml.safe_dump(yaml.safe_load(sys.stdin.read()), sys.stdout)' >"$coder_slice" 2>"$sso3_err"; then
        tail -n 5 "$sso3_err" >&2
        fail "c-sso-3: the coder: block of $CUSTOM_VALUES is not parseable YAML (the ApplicationSet embeds it as JSON already)"
      fi
      sso3f_out=$(mktemp /tmp/opencode/c05-sso3f-XXXXXX.yaml)
      if ! "$helm_bin" template coder "$chart_copy" -f "$coder_slice" --set domain=test.example.com >"$sso3f_out" 2>/dev/null; then
        fail "c-sso-3: helm template coder with the custom-values coder: slice failed"
      fi
      coder_f_doc=$(awk '
        function flush() {
          if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*coder-secrets([[:space:]]|$)/) print buf
        }
        /^---[[:space:]]*$/ { flush(); buf = ""; next }
        { buf = buf $0 "\n" }
        END { flush() }
      ' "$sso3f_out")
      [ -n "$coder_f_doc" ] ||
        fail "c-sso-3: the custom-values-slice render lost the coder-secrets ExternalSecret"
      ea_uuid=$(printf '%s\n' "$coder_cv_ids" |
        sed -nE "s/^[[:space:]]*coder-external-auth:[[:space:]]*(${UUID_RE})[[:space:]]*(#.*)?$/\1/p" | head -n 1)
      key_uuid=$(printf '%s\n' "$coder_cv_ids" |
        sed -nE "s/^[[:space:]]*coder-token-encryption:[[:space:]]*(${UUID_RE})[[:space:]]*(#.*)?$/\1/p" | head -n 1)
      [ -n "$ea_uuid" ] ||
        fail "c-sso-3: custom-values/dev coder.bitwardenIds.coder-external-auth is not a real UUID (the slots were wired 2026-10-25 — this render leg proves the UUID resolves through the deploy path)"
      [ -n "$key_uuid" ] ||
        fail "c-sso-3: custom-values/dev coder.bitwardenIds.coder-token-encryption is not a real UUID (the slots were wired 2026-10-25 — this render leg proves the UUID resolves through the deploy path)"
      printf '%s' "$coder_f_doc" | grep -q "$ea_uuid" ||
        fail "c-sso-3: the deploy-path render does not carry the custom-values coder-external-auth UUID $ea_uuid in the coder-secrets document"
      printf '%s' "$coder_f_doc" | grep -q "$key_uuid" ||
        fail "c-sso-3: the deploy-path render does not carry the custom-values coder-token-encryption UUID $key_uuid in the coder-secrets document"
      if printf '%s' "$coder_f_doc" | grep -q 'OVERRIDE'; then
        fail "c-sso-3: the custom-values coder: slice left an OVERRIDE_* string in the coder-secrets document (all four slots are wired — the deploy-path doc must be fully resolved)"
      fi
      ok "c-sso-3: the custom-values coder-slice render resolves both provider slots to their UUIDs and carries no OVERRIDE_* string"
    else
      tail -n 30 "$sso3_err" >&2
      fail "c-sso-3: helm template coder $chart_copy with the provider --set list failed"
    fi
  fi
fi

# --- c-sso-5: the provider id must not drift between chart and template -----
# `forgejo` is written twice on purpose — the coderd env (C04) and the
# workspace's probe argument (C06) — and the forge-side callback path embeds
# it (/external-auth/<ID>/callback), so a divergence silently breaks approval
# flows that otherwise render and lint clean. Exact-string comparison of the
# two extracted literals.
chart_ea_id=$(sed -nE 's/^[[:space:]]*CODER_EXTERNAL_AUTH_0_ID:[[:space:]]*"([^"]+)".*/\1/p' "$SECRET_CODER" | head -n 1)
[ -n "$chart_ea_id" ] || fail "c-sso-5: could not extract the CODER_EXTERNAL_AUTH_0_ID literal from $SECRET_CODER"
oauth_block=$(env_block FORGEJO_OAUTH_ID)
[ -n "$oauth_block" ] ||
  fail "c-sso-5: $MAIN has no container env block setting FORGEJO_OAUTH_ID — the workspace probe would have no provider id to pass"
tf_ea_id=$(printf '%s' "$oauth_block" | sed -nE 's/.*value[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)
[ -n "$tf_ea_id" ] || fail "c-sso-5: no quoted value literal in the FORGEJO_OAUTH_ID env block"
[ "$chart_ea_id" = "$tf_ea_id" ] ||
  fail "c-sso-5: provider-id drift: $SECRET_CODER says \"$chart_ea_id\", $MAIN says \"$tf_ea_id\" — coderd registers one callback path while the workspaces probe the other"
ok "c-sso-5: provider id \"$chart_ea_id\" is identical in the coder-secrets template and kubernetes-hardened"

# --- c-sso-6: c6 extension — the SSO env name crosses the script boundary ---
if [ -f "$STARTUP" ]; then
  grep -qE '\$\{?FORGEJO_OAUTH_ID' "$STARTUP" ||
    fail "c-sso-6: $STARTUP never reads \$FORGEJO_OAUTH_ID, so the template's provider-id env has no consumer"
  ok "c-sso-6: the baked startup script consumes FORGEJO_OAUTH_ID"
else
  skip "c-sso-6: $STARTUP is absent, so the provider-id env-name contract could not be cross-checked"
fi

# --- c-sso-7: FORGEJO_OAUTH_ID is a bare literal in the FORGEJO_HOST family --
# Same no-server-stored-values posture as the host literals (DECISIONS
# 2026-10-24): a coder_parameter or variable here would make the probe id
# user-editable per workspace and break the c-sso-5 drift pairing.
printf '%s' "$oauth_block" | grep -qE 'value[[:space:]]*=[[:space:]]*"forgejo"([[:space:]}]|$)' ||
  fail "c-sso-7: FORGEJO_OAUTH_ID is not the bare literal \"forgejo\": $oauth_block"
if printf '%s' "$oauth_block" | grep -qE 'var\.|\$\{|https?://'; then
  fail "c-sso-7: FORGEJO_OAUTH_ID env block references a variable or a URL — the provider id must be the bare literal (no scheme, no coder_parameter): $oauth_block"
fi
[ -n "$host_block" ] || fail "c-sso-7: the FORGEJO_HOST env block vanished — FORGEJO_OAUTH_ID must sit in the same container env family (the probe covers FORGEJO_HOST's instance)"
ok "c-sso-7: FORGEJO_OAUTH_ID = \"forgejo\" bare literal, same container env block family as FORGEJO_HOST"

# Everything above passed; the /tmp copies and render dumps are done with. A
# failed run keeps them so its "log kept at" pointer still resolves.
if [ -n "${chart_copy:-}" ]; then
  rm -rf "$chart_copy"
  for f in "${dev_out:-}" "${dev_err:-}" "${devf_out:-}" "${dev_can_out:-}" \
    "${sso3_out:-}" "${sso3_err:-}" "${coder_slice:-}" "${sso3f_out:-}"; do
    if [ -n "$f" ]; then
      rm -f "$f"
    fi
  done
fi

printf 'PASS: git auth checks (%d ok)\n' "$checks"
