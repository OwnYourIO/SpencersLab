#!/usr/bin/env bash
# C05 acceptance checks (2026-10-feat-forgejo-auth-support): the gpu coder
# server carries ONE gitea-type Coder External Auth Provider paired with the
# CANONICAL forge (git.spencerslab.com) plus at-rest token encryption, all
# provisioned through the coder-secrets ExternalSecret's v2 template and the
# envFrom the official chart already wires. The community license caps
# external-auth at one provider per coderd, so the pairing (gpu→canonical,
# dev→dev-forge) is a load-bearing decision: the dev twin asserts
# git.scifi.farm in dev-git-auth.sh c-sso-1, and g-sso-4 pins the canonical
# host here so a copy-paste of one server file into the other fails.
#
# Scope is the gpu leg only — dev-git-auth.sh stays single-cluster-scoped and
# is not extended here. The coder chart is external on gpu, so the real
# Deployment render runs against a copy pulled into /tmp/opencode; the
# worktree is never written (repo convention, same as infra-forgejo.sh).
#
# A helm binary is taken from HELM_BIN/C05_HELM_BIN, the PATH,
# /home/coder/.local/bin, or /tmp/opencode; failing that, helm v3.21.4 is
# downloaded there. Registry-unreachable renders SKIP (not fail), matching
# dev-git-auth.sh's c4 ladder discipline.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/services/gpu-coder-sso.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

GPU="services/gpu/prod"
GPU_TEMPLATE="$GPU/templates/secrets-coder.yaml"
GPU_VALUES="$GPU/values.yaml"
GPU_CUSTOM="custom-values/gpu/prod-values.yaml"
# Read-only twin comparison for the pairing guard; charts/coder belongs to
# C04, this suite never asserts its sentinel/UUID plumbing (that is c-sso-2).
DEV_TEMPLATE="charts/coder/templates/secret-coder.yaml"
RELOADER_KEY='reloader.stakater.com/auto'

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
# until indentation returns to the key's own level (dev-git-auth.sh's helper,
# duplicated so suites stay independent). Blank and comment lines are skipped
# so a comment cannot terminate a block early.
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

# Prints every `- secretKey:` list item of an ExternalSecret's spec.data as one
# flattened line (comments dropped — prose must not satisfy a structure check;
# blank lines dropped — they must not split an entry). Binding per-entry keeps
# "ea_secret reads coder-external-auth" from passing because the file mentions
# both somewhere: the property + store + key must sit inside the same entry.
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

# Extracts the double-quoted value of $2 (an awk-escaped key regex) from the
# target.template.data block — the provider-id / AUTH_URL literals this suite
# pairs across the two server files.
template_value() {
  local file="$1" key="$2"
  sed -nE "s/^[[:space:]]*${key}:[[:space:]]*\"([^\"]+)\".*/\1/p" "$file" | head -n 1
}

find_helm() {
  local cand
  for envname in HELM_BIN C05_HELM_BIN; do
    cand=$(printenv "$envname" || true)
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done
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

download_helm() {
  local version=3.21.4 arch dir tar expected
  command -v curl >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  dir=/tmp/opencode/gpu-coder-sso-helm-download
  mkdir -p "$dir"
  tar="$dir/helm-v${version}-linux-${arch}.tar.gz"
  curl -fsSL --max-time 120 -o "$tar" \
    "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz" >/dev/null 2>&1 || return 1
  curl -fsSL --max-time 30 -o "${tar}.sha256sum" "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz.sha256sum" >/dev/null 2>&1 || return 1
  (cd "$dir" && sha256sum -c "$(basename "$tar").sha256sum" >/dev/null 2>&1) || return 1
  tar -xzf "$tar" -C "$dir" || return 1
  expected=$(find "$dir" -type f -name helm -perm -u+x | head -n 1 || true)
  [ -n "$expected" ] || return 1
  printf '%s' "$expected"
}

# --- g-sso-1: the gpu coder-secrets template carries the provider + keys ----
# Comment-inclusive presence checks per the chunk: the two server files differ
# in style but must agree in substance, and the header comment is where the
# "why" (per-user SSO approval; plaintext-by-default token storage) lives.
[ -f "$GPU_TEMPLATE" ] || fail "g-sso-1: $GPU_TEMPLATE is missing"

grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_ID:[[:space:]]*"forgejo"[[:space:]]*(#.*)?$' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_AUTH_0_ID is not the literal \"forgejo\" — the forge-side OAuth app whitelists /external-auth/<ID>/callback, so the id is contractual (v2.35.2)"
ok "g-sso-1: provider id literal is \"forgejo\" (callback path /external-auth/forgejo/callback)"

grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_TYPE:[[:space:]]*"gitea"[[:space:]]*(#.*)?$' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_AUTH_0_TYPE is not \"gitea\" (the only type whose giteaDefaults() derives TokenURL/ValidateURL/REGEX against Forgejo 15)"
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_DISPLAY_NAME:[[:space:]]*"Forgejo"[[:space:]]*(#.*)?$' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_AUTH_0_DISPLAY_NAME is not \"Forgejo\""
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_AUTH_URL:[[:space:]]*"https://git\.spencerslab\.com/login/oauth/authorize"[[:space:]]*(#.*)?$' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_AUTH_0_AUTH_URL is not the full authorize path on the CANONICAL forge (pairing ruling: gpu coder ↔ git.spencerslab.com)"
ok "g-sso-1: TYPE/DISPLAY_NAME/AUTH_URL literals match the canonical pairing"

# The three fetched-value template keys must indirect through the v2 escape
# ({{ \`{{ .x }}\` }}) like the existing CODER_OIDC_* lines, binding template
# key → secretKey wiring rather than just key presence.
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_CLIENT_ID:.*ea_client_id' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_AUTH_0_CLIENT_ID does not indirect through secretKey ea_client_id"
grep -qE '^[[:space:]]*CODER_EXTERNAL_AUTH_0_CLIENT_SECRET:.*ea_secret' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_AUTH_0_CLIENT_SECRET does not indirect through secretKey ea_secret"
grep -qE '^[[:space:]]*CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS:.*token_encryption_keys' "$GPU_TEMPLATE" ||
  fail "g-sso-1: CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS does not indirect through secretKey token_encryption_keys"
ok "g-sso-1: all seven target.template.data keys present with their secretKey wirings"

entries=$(data_entries "$GPU_TEMPLATE")
entry() {
  printf '%s\n' "$entries" | grep -E "secretKey:[[:space:]]*$1([^A-Za-z0-9_]|$)" | head -n 1 || true
}
ea_id_entry=$(entry ea_client_id)
ea_secret_entry=$(entry ea_secret)
keys_entry=$(entry token_encryption_keys)
[ -n "$ea_id_entry" ] || fail "g-sso-1: no '- secretKey: ea_client_id' data entry"
[ -n "$ea_secret_entry" ] || fail "g-sso-1: no '- secretKey: ea_secret' data entry"
[ -n "$keys_entry" ] || fail "g-sso-1: no '- secretKey: token_encryption_keys' data entry"
printf '%s' "$ea_id_entry" | grep -q 'bitwarden-login' ||
  fail "g-sso-1: the ea_client_id entry does not read through the bitwarden-login store"
printf '%s' "$ea_id_entry" | grep -q '"coder-external-auth"' ||
  fail "g-sso-1: the ea_client_id entry does not reference bitwardenIds.coder-external-auth"
printf '%s' "$ea_id_entry" | grep -qE 'property:[[:space:]]*username' ||
  fail "g-sso-1: ea_client_id does not read the OAuth client id from the item's username field"
printf '%s' "$ea_secret_entry" | grep -q 'bitwarden-login' ||
  fail "g-sso-1: the ea_secret entry does not read through the bitwarden-login store"
printf '%s' "$ea_secret_entry" | grep -q '"coder-external-auth"' ||
  fail "g-sso-1: the ea_secret entry does not reference bitwardenIds.coder-external-auth"
printf '%s' "$ea_secret_entry" | grep -qE 'property:[[:space:]]*password' ||
  fail "g-sso-1: ea_secret does not read the client secret from the item's password field"
printf '%s' "$keys_entry" | grep -q 'bitwarden-login' ||
  fail "g-sso-1: the token_encryption_keys entry does not read through the bitwarden-login store"
printf '%s' "$keys_entry" | grep -q '"coder-token-encryption"' ||
  fail "g-sso-1: the token_encryption_keys entry does not reference bitwardenIds.coder-token-encryption"
printf '%s' "$keys_entry" | grep -qE 'property:[[:space:]]*password' ||
  fail "g-sso-1: token_encryption_keys does not read the base64 key from the item's password field"
for trio in conversionStrategy decodingStrategy metadataPolicy; do
  for e in "$ea_id_entry" "$ea_secret_entry" "$keys_entry"; do
    printf '%s' "$e" | grep -q "$trio" ||
      fail "g-sso-1: an external-auth/encryption data entry is missing the ArgoCD $trio boilerplate (the file's existing entry shape)"
  done
done
ok "g-sso-1: three data entries carry store, bitwardenIds reference, property and the Default/None/None trio"

# giteaDefaults() derives REGEX/TOKEN_URL/VALIDATE_URL from the AUTH_URL host
# (v2.35.2 source); explicit copies would drift from the derivation. Code-line
# scan: a rationale comment naming these keys is legitimate prose.
bad_derived=$(grep -vE '^[[:space:]]*#' "$GPU_TEMPLATE" |
  grep -E '^[[:space:]]*CODER_EXTERNAL_AUTH_0_(REGEX|TOKEN_URL|VALIDATE_URL):' | head -n 1 || true)
[ -z "$bad_derived" ] ||
  fail "g-sso-1: explicit derived provider key re-added ($bad_derived) — giteaDefaults() must own it"
ok "g-sso-1: no explicit _REGEX/_TOKEN_URL/_VALIDATE_URL keys (giteaDefaults derivation trusted)"

# --- g-sso-2: sentinels, custom-values slots, podAnnotations -----------------
gpu_ids=$(yaml_block "$GPU_VALUES" '^bitwardenIds:')
printf '%s\n' "$gpu_ids" |
  grep -qE '^[[:space:]]*coder-external-auth:[[:space:]]*OVERRIDE_VIA_CUSTOM_VALUES[[:space:]]*(#.*)?$' ||
  fail "g-sso-2: $GPU_VALUES has no 'coder-external-auth: OVERRIDE_VIA_CUSTOM_VALUES' entry under bitwardenIds"
printf '%s\n' "$gpu_ids" |
  grep -qE '^[[:space:]]*coder-token-encryption:[[:space:]]*OVERRIDE_VIA_CUSTOM_VALUES[[:space:]]*(#.*)?$' ||
  fail "g-sso-2: $GPU_VALUES has no 'coder-token-encryption: OVERRIDE_VIA_CUSTOM_VALUES' entry under bitwardenIds"
ok "g-sso-2: gpu service values carry both new sentinels (current custom-values standard, not the legacy cluster-annotation mechanism)"

coder_blk=$(yaml_block "$GPU_VALUES" '^coder:')
inner_blk=$(yaml_block <(printf '%s\n' "$coder_blk") '^[[:space:]]*coder:')
printf '%s\n' "$inner_blk" | grep -qE '^[[:space:]]*podAnnotations:' ||
  fail "g-sso-2: no podAnnotations block under coder.coder in $GPU_VALUES (coderd reads provider/encryption env only at process start — without a secret-change restart the first sync sits inert)"
printf '%s\n' "$inner_blk" | grep -qE "^[[:space:]]*${RELOADER_KEY}:[[:space:]]*\"true\"[[:space:]]*(#.*)?$" ||
  fail "g-sso-2: coder.coder.podAnnotations does not set ${RELOADER_KEY}: \"true\""
ok "g-sso-2: coder.coder.podAnnotations requests the reloader restart"

[ -f "$GPU_CUSTOM" ] || fail "g-sso-2: $GPU_CUSTOM is missing"
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
gpu_custom_ids=$(yaml_block "$GPU_CUSTOM" '^bitwardenIds:')
for key in coder-external-auth coder-token-encryption; do
  custom_entry=$(printf '%s\n' "$gpu_custom_ids" | grep -E "^[[:space:]]*${key}:" | head -n 1 || true)
  [ -n "$custom_entry" ] || fail "g-sso-2: $GPU_CUSTOM has no ${key} entry (the sentinel would survive to the cluster)"
  if printf '%s' "$custom_entry" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
    fail "g-sso-2: the custom-values ${key} entry is still the service sentinel: $custom_entry"
  fi
  # OVERRIDE_NEEDED is the documented must-fill slot until the user creates
  # the per-cluster Bitwarden item (the infra-forgejo t6 precedent).
  printf '%s' "$custom_entry" |
    grep -qE "^[[:space:]]*${key}:[[:space:]]*(OVERRIDE_NEEDED|${UUID_RE})[[:space:]]*(#.*)?$" ||
    fail "g-sso-2: the custom-values ${key} value is neither a real UUID nor the documented OVERRIDE_NEEDED placeholder: $custom_entry"
  ok "g-sso-2: custom-values/gpu ${key} slot is a real UUID or the documented placeholder"
done

# --- g-sso-3: the render ladder ----------------------------------------------
helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || helm_bin=$(download_helm || true)

if [ -z "$helm_bin" ]; then
  skip "g-sso-3: no helm binary on PATH or in /tmp/opencode, and none could be downloaded; run the plan's gpu renders separately"
else
  WORK=$(mktemp -d /tmp/opencode/gpu-coder-sso.XXXXXX)

  # Leg 1 — umbrella render. The legacy coder-sso-secret/coder-pg keys still
  # resolve through OVERRIDE_VIA_CLUSTER_ANNOTATION in the shipped values, so
  # --set must cover them too or their sentinel strings land in the very
  # document the no-OVERRIDE contract reads (deploy-time, the cluster
  # annotation does this; the plan's command line abbreviated it).
  gpu_out="$WORK/gpu-render.yaml"
  gpu_err="$WORK/gpu-render.err"
  if ! "$helm_bin" template gpu "$GPU" \
    --set domain=test.example.com --set clusterName=gpu \
    --set bitwardenIds.coder-external-auth=test-uuid-ea \
    --set bitwardenIds.coder-token-encryption=test-uuid-key \
    --set bitwardenIds.coder-sso-secret=test-uuid-sso \
    --set bitwardenIds.coder-pg=test-uuid-pg \
    >"$gpu_out" 2>"$gpu_err"; then
    tail -n 30 "$gpu_err" >&2
    fail "g-sso-3: helm template of $GPU with the provider/encryption --set list failed"
  fi
  coder_doc=$(awk '
    function flush() {
      if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*coder-secrets([[:space:]]|$)/) print buf
    }
    /^---[[:space:]]*$/ { flush(); buf = ""; next }
    { buf = buf $0 "\n" }
    END { flush() }
  ' "$gpu_out")
  [ -n "$coder_doc" ] ||
    fail "g-sso-3: the gpu render carries no coder-secrets ExternalSecret"
  for key in CODER_EXTERNAL_AUTH_0_ID CODER_EXTERNAL_AUTH_0_TYPE CODER_EXTERNAL_AUTH_0_DISPLAY_NAME \
    CODER_EXTERNAL_AUTH_0_AUTH_URL CODER_EXTERNAL_AUTH_0_CLIENT_ID CODER_EXTERNAL_AUTH_0_CLIENT_SECRET \
    CODER_EXTERNAL_TOKEN_ENCRYPTION_KEYS; do
    printf '%s' "$coder_doc" | grep -q "$key" ||
      fail "g-sso-3: the rendered coder-secrets document lost the $key template key"
  done
  printf '%s' "$coder_doc" | grep -q 'forgejo' ||
    fail "g-sso-3: the rendered coder-secrets document has no forgejo provider id"
  printf '%s' "$coder_doc" | grep -q 'https://git.spencerslab.com/login/oauth/authorize' ||
    fail "g-sso-3: the rendered coder-secrets document lost the canonical AUTH_URL"
  printf '%s' "$coder_doc" | grep -q 'test-uuid-ea' ||
    fail "g-sso-3: the rendered coder-secrets document ignores --set bitwardenIds.coder-external-auth"
  printf '%s' "$coder_doc" | grep -q 'test-uuid-key' ||
    fail "g-sso-3: the rendered coder-secrets document ignores --set bitwardenIds.coder-token-encryption"
  if printf '%s' "$coder_doc" | grep -q 'OVERRIDE'; then
    fail "g-sso-3: the rendered coder-secrets document still carries an OVERRIDE_* sentinel"
  fi
  ok "g-sso-3: the coder-secrets render carries all seven keys, forgejo + canonical AUTH_URL, both test UUIDs, no sentinel"

  # Leg 2 — the umbrella's ApplicationSet values blob is what ArgoCD feeds the
  # external coder chart, so the annotation must be visible there.
  if python3 - "$gpu_out" "$RELOADER_KEY" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
key = sys.argv[2]
blob = None
for d in docs:
    if d.get('kind') != 'ApplicationSet':
        continue
    for e in d['spec']['generators'][0]['matrix']['generators'][1]['list']['elements']:
        v = e.get('values')
        if isinstance(v, dict) and 'coder' in v:
            blob = v['coder']
if blob is None:
    print('FAIL: g-sso-3: no gpu ApplicationSet generator element carries the coder chart values blob', file=sys.stderr)
    sys.exit(1)
ann = (((blob.get('coder') or {}).get('podAnnotations')) or {})
if ann.get(key) != 'true':
    print(f'FAIL: g-sso-3: the coder chart values blob ships podAnnotations {ann!r} — {key}="true" is not in the values ArgoCD passes to the external chart', file=sys.stderr)
    sys.exit(1)
PY
  then
    ok "g-sso-3: the gpu ApplicationSet values blob hands the coder chart ${RELOADER_KEY}=\"true\""
  else
    exit 1
  fi

  # Leg 3 — real Deployment proof: gpu consumes the official chart, so render
  # the pinned version itself (pulled to /tmp) with the chart's values slice
  # extracted from the service values. Proves coder.podAnnotations lands on
  # the coderd pod template — the values blob alone does not.
  coder_version=$(yaml_block "$GPU_VALUES" '^charts:' |
    awk '/^[[:space:]]*coder:/{f=1;next} f && /^[[:space:]]*version:/{print $2; exit}')
  if [ -z "$coder_version" ]; then
    fail "g-sso-3: no charts.coder.version pin in $GPU_VALUES (the AC5 pin vanished — external render impossible)"
  fi
  coder_pull_err="$WORK/coder-pull.err"
  if ! "$helm_bin" pull coder --repo https://helm.coder.com/v2 --version "$coder_version" \
    --untar --untardir "$WORK/official" >"$coder_pull_err" 2>&1; then
    skip "g-sso-3: helm pull coder $coder_version could not reach helm.coder.com here, so the coder Deployment render leg was not run (log kept at $coder_pull_err)"
  else
    coder_slice="$WORK/coder-slice.yaml"
    if ! printf '%s\n' "$coder_blk" | python3 -c 'import sys, yaml; yaml.safe_dump(yaml.safe_load(sys.stdin.read()), sys.stdout)' >"$coder_slice" 2>"$WORK/slice.err"; then
      tail -n 5 "$WORK/slice.err" >&2
      fail "g-sso-3: the coder values block of $GPU_VALUES is not parseable YAML (the ApplicationSet embeds it as JSON already — a python-parseable slice is a fair gate)"
    fi
    coder_render="$WORK/coder-chart-render.yaml"
    if ! "$helm_bin" template coder "$WORK/official/coder" -f "$coder_slice" >"$coder_render" 2>"$WORK/coder-render.err"; then
      tail -n 30 "$WORK/coder-render.err" >&2
      fail "g-sso-3: rendering the official coder chart $coder_version with the gpu values slice failed"
    fi
    if python3 - "$coder_render" "$RELOADER_KEY" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
key = sys.argv[2]
dep = [d for d in docs if d.get('kind') == 'Deployment' and d['metadata']['name'] == 'coder']
if not dep:
    print('FAIL: g-sso-3: the coder chart render has no Deployment named coder', file=sys.stderr)
    sys.exit(1)
ann = ((dep[0]['spec']['template'].get('metadata') or {}).get('annotations') or {})
if ann.get(key) != 'true':
    print(f'FAIL: g-sso-3: the coderd pod template annotations are {ann!r} — coder.coder.podAnnotations did not reach the pod', file=sys.stderr)
    sys.exit(1)
PY
    then
      ok "g-sso-3: the rendered coder $coder_version Deployment pod template carries ${RELOADER_KEY}=\"true\""
    else
      exit 1
    fi
  fi

  # Leg 4 — the real deploy path: custom-values/gpu over the umbrella. The
  # provider slots are wired (user decision 2026-10-25 supplied the item
  # UUIDs); this leg proves they resolve, and neither sentinel may render.
  gpu_f_out="$WORK/gpu-customvalues-render.yaml"
  if ! "$helm_bin" template gpu "$GPU" -f "$GPU_CUSTOM" \
    --set domain=test.example.com --set clusterName=gpu >"$gpu_f_out" 2>/dev/null; then
    fail "g-sso-3: helm template gpu $GPU -f $GPU_CUSTOM failed"
  fi
  coder_f_doc=$(awk '
    function flush() {
      if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*coder-secrets([[:space:]]|$)/) print buf
    }
    /^---[[:space:]]*$/ { flush(); buf = ""; next }
    { buf = buf $0 "\n" }
    END { flush() }
  ' "$gpu_f_out")
  [ -n "$coder_f_doc" ] ||
    fail "g-sso-3: the -f custom-values render lost the coder-secrets ExternalSecret"
  ea_uuid=$(printf '%s\n' "$gpu_custom_ids" |
    sed -nE "s/^[[:space:]]*coder-external-auth:[[:space:]]*(${UUID_RE})[[:space:]]*(#.*)?$/\1/p" | head -n 1)
  key_uuid=$(printf '%s\n' "$gpu_custom_ids" |
    sed -nE "s/^[[:space:]]*coder-token-encryption:[[:space:]]*(${UUID_RE})[[:space:]]*(#.*)?$/\1/p" | head -n 1)
  [ -n "$ea_uuid" ] ||
    fail "g-sso-3: custom-values/gpu coder-external-auth is not a real UUID (the slots were wired 2026-10-25 — this render leg proves the UUID resolves through the deploy path)"
  [ -n "$key_uuid" ] ||
    fail "g-sso-3: custom-values/gpu coder-token-encryption is not a real UUID (the slots were wired 2026-10-25 — this render leg proves the UUID resolves through the deploy path)"
  printf '%s' "$coder_f_doc" | grep -q "$ea_uuid" ||
    fail "g-sso-3: the custom-values render does not carry the coder-external-auth UUID $ea_uuid in the coder-secrets document"
  printf '%s' "$coder_f_doc" | grep -q "$key_uuid" ||
    fail "g-sso-3: the custom-values render does not carry the coder-token-encryption UUID $key_uuid in the coder-secrets document"
  if printf '%s' "$coder_f_doc" | grep -q 'OVERRIDE_VIA_CUSTOM_VALUES'; then
    fail "g-sso-3: the custom-values render did not resolve the service sentinel in the coder-secrets document"
  fi
  if printf '%s' "$coder_f_doc" | grep -q 'OVERRIDE_VIA_CLUSTER_ANNOTATION'; then
    fail "g-sso-3: the custom-values render did not resolve the legacy cluster-annotation sentinel in the coder-secrets document"
  fi
  ok "g-sso-3: the custom-values render resolves both provider slots to their UUIDs with no service or legacy-annotation sentinel"

  # --- g-sso-4: pairing guard (static) — each coder spends its single
  # provider slot on its OWN paired forge. Both files pinning the same host
  # is the signature of a copy-paste between the server twins.
  gpu_auth_url=$(template_value "$GPU_TEMPLATE" 'CODER_EXTERNAL_AUTH_0_AUTH_URL')
  dev_auth_url=$(template_value "$DEV_TEMPLATE" 'CODER_EXTERNAL_AUTH_0_AUTH_URL' || true)
  gpu_host=$(printf '%s' "$gpu_auth_url" | sed -nE 's#^https://([^/]+)/.*#\1#p')
  [ "$gpu_host" = "git.spencerslab.com" ] ||
    fail "g-sso-4: the gpu provider AUTH_URL host is '${gpu_host:-<unparsed>}', expected the canonical git.spencerslab.com (gpu workspaces approve against the canonical forge)"
  ok "g-sso-4: gpu provider pairs with the canonical forge host"
  if printf '%s' "$gpu_auth_url" | grep -q 'git\.scifi\.farm'; then
    fail "g-sso-4: the gpu provider AUTH_URL references the DEV forge host — the two coder servers would both point their one slot at git.scifi.farm"
  fi
  if [ -n "$dev_auth_url" ] && [ "$dev_auth_url" = "$gpu_auth_url" ]; then
    fail "g-sso-4: gpu and dev provider AUTH_URL are identical ($dev_auth_url) — copy-paste drift: the dev coder slot must pair git.scifi.farm (c-sso-1 pins it)"
  fi
  ok "g-sso-4: the gpu provider host differs from the dev twin's — the per-coder pairing is not a file copy"

  rm -rf "$WORK"
fi

printf 'PASS: gpu-coder-sso checks (%d ok)\n' "$checks"
