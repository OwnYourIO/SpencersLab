#!/usr/bin/env bash
# Workspace git-auth wiring checks: a dev `forgejo-token` ExternalSecret
# (mirroring secret-github.yaml) plus the existing `github-pat` one feed
# GITHUB_TOKEN / FORGEJO_TOKEN / FORGEJO_HOST into the kubernetes-hardened
# workspace pods, and secret-github.yaml names the template as its in-repo
# consumer. No image change is needed: the baked startup script already
# consumes those three names.
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
SECRET_GITHUB="services/dev/prod/templates/secret-github.yaml"
VALUES="services/dev/prod/values.yaml"
CUSTOM_VALUES="custom-values/dev/prod-values.yaml"
MAIN="charts/coder/coder-templates/kubernetes-hardened/main.tf"
CHART="charts/coder"
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
else
  helm_version=$("$helm_bin" version --short 2>/dev/null || true)
  chart_copy=$(mktemp -d /tmp/opencode/c05-helm-XXXXXX)
  cp -R "$CHART"/. "$chart_copy"/
  dep_log="$chart_copy/dependency-build.log"

  if ! (cd "$chart_copy" && "$helm_bin" dependency build .) >"$dep_log" 2>&1; then
    if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
      skip "c4: helm dependency build could not reach helm.coder.com here, so lint/template were not run (log kept at $dep_log)"
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
      # named forgejo-token (the github-pat one is a sibling, not a substitute).
      forgejo_doc=$(awk '
        function flush() {
          if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*forgejo-token/) print buf
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

      # Second render on the real deploy path: the custom-values file the
      # cluster annotation loads must resolve the sentinel to the real item.
      if [ -n "$real_uuid" ]; then
        devf_out=$(mktemp /tmp/opencode/c05-dev-XXXXXX.yaml)
        if "$helm_bin" template dev "$SERVICE" -f "$CUSTOM_VALUES" >"$devf_out" 2>/dev/null; then
          real_doc=$(awk '
            function flush() {
              if (buf ~ /kind:[[:space:]]*ExternalSecret/ && buf ~ /name:[[:space:]]*forgejo-token/) print buf
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
        else
          fail "c4: helm template dev $SERVICE -f $CUSTOM_VALUES failed (see the message above)"
        fi
      fi
    else
      tail -n 30 "$dev_err" >&2
      fail "c4: helm template dev $SERVICE --set bitwardenIds.forgejo-token=test-uuid failed"
    fi
  fi
fi

# Everything above passed; the /tmp copies and render dumps are done with. A
# failed run keeps them so its "log kept at" pointer still resolves.
if [ -n "${chart_copy:-}" ]; then
  rm -rf "$chart_copy"
  for f in "${dev_out:-}" "${dev_err:-}" "${devf_out:-}"; do
    if [ -n "$f" ]; then
      rm -f "$f"
    fi
  done
fi

printf 'PASS: git auth checks (%d ok)\n' "$checks"
