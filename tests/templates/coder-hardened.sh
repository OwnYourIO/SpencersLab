#!/usr/bin/env bash
# C04 acceptance checks (2026-10-feat-coder-workspace-rebuild): the new
# charts/coder/coder-templates/kubernetes-hardened/ template — the rebuilt
# ghcr.io/ownyourio/coder-workspace image, restricted PSS, the single baked
# startup line, no Azure/ACR wiring, no prevent_destroy, and the documented
# 1-week autostop header.
#
# This repo has no unit-test suite (AGENTS.md "Pipeline specifics"); these
# checks are the local gate for C04. Each check prints one pass/fail line;
# any fail makes the script exit non-zero.
#
# Criterion 1 runs PLAN.md's scratch-copy terraform recipe verbatim (init in
# a copy under /tmp/opencode, never inside the repo: .terraform/ must not be
# committed). Criterion 4 re-runs C03's packaging guard: .helmignore already
# excludes coder-templates/ and its subfolders, so the guard is the
# published-tgz entry count, not a chart edit.
#
# Criterion 2 is encoded point by point: each sub-item of chunks/C04.md gets
# its own pass/fail line. Forbidden-token scans run on comment-stripped views
# (CODE_VIEW / STARTUP_CODE below), because C04's mandated header explains
# what was deliberately omitted ("no sudo", "no pull secrets", the
# prevent_destroy removal) and keeps the existing rationale comment naming
# nvm/node_modules — matching that prose would fail a correct implementation
# (C01 ruling: forbidden checks scan code, not comments).
#
# Usage: bash tests/templates/coder-hardened.sh
#   REPO_ROOT=<abs path> bash tests/templates/coder-hardened.sh
# REPO_ROOT defaults to the git toplevel of the current directory; the
# override exists to run the same contract against a scratch checkout,
# without touching the real worktree.

set -u

if [ -n "${REPO_ROOT:-}" ]; then
  :
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "fail: cannot resolve repo root via git; set REPO_ROOT explicitly"; exit 2; }
fi
[ -d "$REPO_ROOT" ] || { echo "fail: REPO_ROOT '$REPO_ROOT' is not a directory"; exit 2; }
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "fail: REPO_ROOT '$REPO_ROOT' is not a git worktree"; exit 2; }

HELM=/home/coder/.local/bin/helm
TF_BIN="${TF_BIN:-/tmp/opencode/tfbin/terraform}"
TF_PLUGIN_CACHE=/tmp/opencode/tfbin/plugin-cache
TPL=charts/coder/coder-templates
MAIN_TF="$REPO_ROOT/$TPL/kubernetes-hardened/main.tf"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'pass: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'fail: %s\n' "$1"; }

EXISTS=1
[ -f "$MAIN_TF" ] || EXISTS=0
NOTE=" (main.tf absent)"
[ "$EXISTS" -eq 1 ] && NOTE=""

# CODE_VIEW: comment lines (first non-whitespace '#' or '//') removed. Both
# HCL comment lines and the shell comment lines inside the startup_script
# heredoc are prose, not wiring.
if [ "$EXISTS" -eq 1 ]; then
  CODE_VIEW=$(grep -vE '^[[:space:]]*(#|//)' "$MAIN_TF" || true)
else
  CODE_VIEW=""
fi

# STARTUP_BLOCK: the coder_agent startup_script value — the lines between the
# 'startup_script =' line and its heredoc terminator ('<<-' allows an
# indented terminator), or the rest of the line for a single-line form.
# STARTUP_CODE: that block minus shell comment lines (a rationale comment
# naming the dropped machinery is legitimate; the commands are not).
if [ "$EXISTS" -eq 1 ]; then
  STARTUP_BLOCK=$(awk '
    !inblock && /startup_script[ \t]*=/ {
      if ($0 ~ /<<-?[A-Za-z_]+/) {
        inblock = 1
        delim = $0
        sub(/^.*<<-?/, "", delim)
        sub(/[^A-Za-z0-9_].*$/, "", delim)
      } else {
        val = $0
        sub(/^.*startup_script[ \t]*=[ \t]*/, "", val)
        if (val != $0) print val
      }
      next
    }
    inblock {
      t = $0
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      if (t == delim) exit
      print
    }
  ' "$MAIN_TF")
  STARTUP_CODE=$(printf '%s\n' "$STARTUP_BLOCK" | grep -vE '^[[:space:]]*#' || true)
else
  STARTUP_BLOCK=""
  STARTUP_CODE=""
fi

# HDR: the leading run of comment/blank lines at the very top of the file.
# C04's better-comments mandate puts the template contract (including the
# SHUTDOWN section) there, so the mentions below must live in that block.
if [ "$EXISTS" -eq 1 ]; then
  HDR=$(awk '
    {
      t = $0
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      if (t == "" || t ~ /^#/ || t ~ /^\/\//) { print; next }
      exit
    }
  ' "$MAIN_TF")
else
  HDR=""
fi

var_block() { # $1 = variable name; prints the variable "name" { ... } block
  [ -f "$MAIN_TF" ] || return 0
  awk -v name="$1" '
    !invar && $0 ~ ("variable[ \t]+\"" name "\"") { invar = 1 }
    invar { print }
    invar && /^[ \t]*\}/ { exit }
  ' "$MAIN_TF"
}

# --- criterion 1: scratch-copy terraform validate --------------------------
if [ "$EXISTS" -eq 0 ]; then
  fail "c1: nothing to validate — $TPL/kubernetes-hardened/main.tf is missing"
elif [ ! -x "$TF_BIN" ]; then
  fail "c1: terraform binary missing at $TF_BIN — re-provision per PLAN.md (terraform 1.9.8 into /tmp/opencode/tfbin, TF_PLUGIN_CACHE_DIR=/tmp/opencode/tfbin/plugin-cache with coder/kubernetes/random providers), then re-run"
else
  scratch=/tmp/opencode/tf-validate-kubernetes-hardened
  rm -rf "$scratch" && mkdir -p "$scratch" && cp "$MAIN_TF" "$scratch/"
  if tf_out=$(cd "$scratch" && TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE" "$TF_BIN" init -backend=false -input=false && "$TF_BIN" validate 2>&1); then
    pass "c1: scratch-copy terraform init -backend=false + validate passes on kubernetes-hardened/main.tf"
  else
    fail "c1: terraform init/validate failed in scratch copy; last lines: $(printf '%s' "$tf_out" | tail -n 3 | tr '\n' '|')"
  fi
fi

# --- criterion 2: structural contract, point by point ----------------------
if [ "$EXISTS" -eq 1 ]; then
  pass "c2: $TPL/kubernetes-hardened/main.tf exists"
else
  fail "c2: $TPL/kubernetes-hardened/main.tf is missing"
fi

# The criterion allows "image + tag main (or equivalent single reference)";
# the single reference is the only satisfiable form: the kubernetes provider
# has no container 'tag' argument (terraform validate on a probe: 'An
# argument named "tag" is not expected here').
img_line=$(printf '%s\n' "$CODE_VIEW" | grep -E '^[[:space:]]*image[[:space:]]*=' | head -n 1 || true)
img_val=$(printf '%s' "$img_line" | sed -E 's/^[[:space:]]*image[[:space:]]*=[[:space:]]*//; s/^[[:space:]]*"//; s/"[[:space:]]*$//')
if [ "$img_val" = 'ghcr.io/ownyourio/coder-workspace:main' ]; then
  pass "c2: container image is ghcr.io/ownyourio/coder-workspace:main"
else
  fail "c2: container image is not ghcr.io/ownyourio/coder-workspace:main, found: '${img_val:-<none>}'$NOTE"
fi

if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'image_pull_policy[[:space:]]*=[[:space:]]*"Always"'; then
  pass "c2: image_pull_policy = \"Always\""
else
  fail "c2: no image_pull_policy = \"Always\"$NOTE"
fi

if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$STARTUP_CODE" | grep -qF '/usr/local/bin/workspace-startup.sh'; then
  pass "c2: startup_script calls /usr/local/bin/workspace-startup.sh"
else
  fail "c2: startup_script does not call /usr/local/bin/workspace-startup.sh$NOTE"
fi

# Plain case-insensitive substring is safe for these six: unlike the
# file-wide tokens below, none is a legitimate substring of any identifier
# in this template (NVM_DIR is nvm wiring, install.sh is the code-server
# bootstrap the rebuild replaces), so no word-boundary forms are needed.
for tok in sudo apt-get nvm 'npm install' install.sh kilocode; do
  hit=$(printf '%s\n' "$STARTUP_CODE" | grep -inF -- "$tok" | head -n 1 || true)
  if [ "$EXISTS" -eq 1 ] && [ -z "$hit" ]; then
    pass "c2: startup_script contains no '$tok'"
  else
    fail "c2: startup_script must not contain '$tok' ($([ "$EXISTS" -eq 1 ] && echo "found: $hit" || echo 'main.tf absent'))"
  fi
done

# File-wide forbidden wiring. codercom/, image_pull_secrets and
# service_account are exact HCL attribute/host names, so literal. azure and
# acr are ambiguous substrings, so word boundaries: "across" must not fail,
# while <name>.azurecr.io, acr-pull-* and an ACR_* variable are the wiring
# the criterion bans (DECISIONS #13: public GHCR image, no pull secrets).
fw() { # $1 = ERE; prints the first matching 'line: text' or nothing
  printf '%s\n' "$CODE_VIEW" | grep -inE -- "$1" | head -n 1 || true
}
hit=$(fw 'codercom/')
if [ "$EXISTS" -eq 1 ] && [ -z "$hit" ]; then
  pass "c2: no 'codercom/' reference (the old base image is gone)"
else
  fail "c2: 'codercom/' present in kubernetes-hardened ($([ "$EXISTS" -eq 1 ] && echo "$hit" || echo 'main.tf absent'))"
fi
hit=$(fw 'image_pull_secrets')
if [ "$EXISTS" -eq 1 ] && [ -z "$hit" ]; then
  pass "c2: no image_pull_secrets (public image, no pull secrets)"
else
  fail "c2: image_pull_secrets present in kubernetes-hardened ($([ "$EXISTS" -eq 1 ] && echo "$hit" || echo 'main.tf absent'))"
fi
hit=$(fw '(^|[^a-zA-Z0-9])azure([_-]|[^a-zA-Z0-9]|$)')
if [ "$EXISTS" -eq 1 ] && [ -z "$hit" ]; then
  pass "c2: no azure reference anywhere"
else
  fail "c2: azure reference present in kubernetes-hardened ($([ "$EXISTS" -eq 1 ] && echo "$hit" || echo 'main.tf absent'))"
fi
hit=$(fw 'azurecr|(^|[^a-zA-Z0-9])acr([_-]|[^a-zA-Z0-9]|$)')
if [ "$EXISTS" -eq 1 ] && [ -z "$hit" ]; then
  pass "c2: no acr reference anywhere (whole-word + azurecr forms)"
else
  fail "c2: acr reference present in kubernetes-hardened ($([ "$EXISTS" -eq 1 ] && echo "$hit" || echo 'main.tf absent'))"
fi
hit=$(fw 'service_account')
if [ "$EXISTS" -eq 1 ] && [ -z "$hit" ]; then
  pass "c2: no service_account wiring"
else
  fail "c2: service_account present in kubernetes-hardened ($([ "$EXISTS" -eq 1 ] && echo "$hit" || echo 'main.tf absent'))"
fi

if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'allow_privilege_escalation[[:space:]]*=[[:space:]]*false'; then
  pass "c2: restricted PSS — allow_privilege_escalation = false"
else
  fail "c2: no allow_privilege_escalation = false$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'drop[[:space:]]*=[[:space:]]*\[[[:space:]]*"ALL"[[:space:]]*\]'; then
  pass "c2: restricted PSS — capabilities drop = [\"ALL\"]"
else
  fail "c2: no capabilities drop = [\"ALL\"]$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qF 'RuntimeDefault'; then
  pass "c2: restricted PSS — seccomp RuntimeDefault"
else
  fail "c2: no seccomp RuntimeDefault$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'read_only_root_filesystem[[:space:]]*=[[:space:]]*true'; then
  pass "c2: restricted PSS — read_only_root_filesystem = true"
else
  fail "c2: no read_only_root_filesystem = true$NOTE"
fi

# The /tmp mount must be backed by the emptyDir volume; the two facts are
# joined on the volume name, because a /tmp mount on some other volume would
# still terraform-validate but defeat the read-only-rootfs design.
tmp_vol=$(printf '%s\n' "$CODE_VIEW" | awk '
  /^[[:space:]]*volume_mount[ \t]*\{/ { invm = 1; mname = ""; mp = "" }
  invm && /mount_path[ \t]*=/ { mp = $0; sub(/^[^=]*=[ \t]*/, "", mp); gsub(/[" \t]/, "", mp) }
  invm && /^[ \t]*name[ \t]*=/ { mname = $0; sub(/^[^=]*=[ \t]*/, "", mname); gsub(/[" \t]/, "", mname) }
  invm && /\}/ { if (mp == "/tmp") print mname; invm = 0 }
')
emptydir_vols=$(printf '%s\n' "$CODE_VIEW" | awk '
  /^[[:space:]]*volume[ \t]*\{/ { invol = 1; vname = ""; ed = 0 }
  invol && /^[ \t]*name[ \t]*=/ { vname = $0; sub(/^[^=]*=[ \t]*/, "", vname); gsub(/[" \t]/, "", vname) }
  invol && /empty_dir/ { ed = 1 }
  invol && /^[ \t]*\}/ { if (ed) print vname; invol = 0 }
')
if [ "$EXISTS" -eq 1 ] && [ -n "$tmp_vol" ] && printf '%s\n' "$emptydir_vols" | grep -qx "$tmp_vol"; then
  pass "c2: /tmp is mounted from an empty_dir volume (volume: $tmp_vol)"
else
  fail "c2: no empty_dir volume backs the /tmp mount, mount vol: '${tmp_vol:-<none>}'$NOTE"
fi

if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'mount_path[[:space:]]*=[[:space:]]*"/home/coder"'; then
  pass "c2: home PVC is mounted at /home/coder"
else
  fail "c2: no /home/coder volume mount$NOTE"
fi
# No shared-volume mount: the legacy template's /shared referenced
# dev-shared, a SeaweedFS claim that exists only on the gpu cluster. No
# cluster this template deploys to has it, a missing claim leaves every
# workspace Pending (dev, 2026-10-20), and Coder carries stored variable
# values across template versions — so the variable must not exist either.
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'shared_pvc_name|mount_path[[:space:]]*=[[:space:]]*"/shared"'; then
  fail "c2: shared-volume wiring survived (shared_pvc_name or a /shared mount) — it must be absent"
else
  pass "c2: no shared-volume wiring (no shared_pvc_name variable, no /shared mount)"
fi

# The fused contract follows the reference artifact: prevent_destroy is
# explicitly false, so deleting a workspace frees its home PVC (the header
# documents the consequence). The code view must carry the explicit false and
# never `= true`.
pd_false=$(printf '%s\n' "$CODE_VIEW" | grep -nE 'prevent_destroy[[:space:]]*=[[:space:]]*false' | head -n 1 || true)
pd_true=$(printf '%s\n' "$CODE_VIEW" | grep -nE 'prevent_destroy[[:space:]]*=[[:space:]]*true' | head -n 1 || true)
if [ "$EXISTS" -eq 1 ] && [ -n "$pd_false" ] && [ -z "$pd_true" ]; then
  pass "c2: home PVC sets lifecycle prevent_destroy = false (explicit, not true)"
else
  fail "c2: home PVC must set prevent_destroy = false explicitly ($([ "$EXISTS" -eq 1 ] && echo "false found: ${pd_false:-no}; true found: ${pd_true:-no}" || echo 'main.tf absent'))"
fi

if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'wait_until_bound[[:space:]]*=[[:space:]]*false'; then
  pass "c2: home PVC keeps wait_until_bound = false"
else
  fail "c2: no wait_until_bound = false on the home PVC$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qF 'kubernetes_persistent_volume_claim_v1'; then
  pass "c2: home PVC resource (kubernetes_persistent_volume_claim_v1) is declared"
else
  fail "c2: no kubernetes_persistent_volume_claim_v1 resource$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qF '"coder-pvc"'; then
  pass "c2: home PVC keeps the existing coder-pvc label set"
else
  fail "c2: the coder-pvc label set is missing from the home PVC$NOTE"
fi

# The repos multi-select feeds WORKSPACE_GIT_REPOS in the agent env; the baked
# startup script clones the selection on every start. CODER_USER/EMAIL give
# the clones' commits the workspace owner's identity.
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'data[[:space:]]+"coder_parameter"[[:space:]]+"repos"'; then
  pass "c2: repos coder_parameter is declared"
else
  fail "c2: no repos coder_parameter$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'WORKSPACE_GIT_REPOS[[:space:]]*='; then
  pass "c2: agent env sets WORKSPACE_GIT_REPOS from the repos parameter"
else
  fail "c2: agent env does not set WORKSPACE_GIT_REPOS$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'CODER_USER[[:space:]]*=[[:space:]]*data\.coder_workspace_owner\.me\.name'; then
  pass "c2: agent env sets CODER_USER from the workspace owner"
else
  fail "c2: agent env does not set CODER_USER$NOTE"
fi
# OpenChamber exits rather than bind outside loopback without a UI password;
# the template supplies one so devices can reach the pod-IP listener.
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'OPENCHAMBER_UI_PASSWORD[[:space:]]*=[[:space:]]*random_password\.openchamber_ui\.result'; then
  pass "c2: agent env sets OPENCHAMBER_UI_PASSWORD from random_password.openchamber_ui"
else
  fail "c2: agent env does not set OPENCHAMBER_UI_PASSWORD (OpenChamber would refuse the non-loopback bind)$NOTE"
fi

# code-server comes from the official Coder module — no repo-side pin to
# maintain; every workspace start fetches the current upstream release. The
# module also creates its own coder_app, so the template must declare none.
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'module[[:space:]]+"code-server"[[:space:]]*\{'; then
  pass "c2: code-server is provided by a module \"code-server\" block"
else
  fail "c2: no module \"code-server\" block$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qF 'registry.coder.com/coder/code-server/coder'; then
  pass "c2: the code-server module is the official registry.coder.com one"
else
  fail "c2: the code-server module source is not registry.coder.com/coder/code-server/coder$NOTE"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -q 'CODE_SERVER_VERSION'; then
  fail "c2: CODE_SERVER_VERSION is back — code-server must stay unpinned (the module owns it)"
else
  pass "c2: no CODE_SERVER_VERSION pin survives in the template"
fi
if [ "$EXISTS" -eq 1 ] && printf '%s\n' "$CODE_VIEW" | grep -qE 'resource[[:space:]]+"coder_app"[[:space:]]+"code-server"'; then
  fail "c2: a hand-rolled coder_app \"code-server\" would collide with the module's own app"
else
  pass "c2: no hand-rolled code-server coder_app (the module creates it)"
fi

if [ "$EXISTS" -eq 1 ] && [ -z "$HDR" ]; then
  fail "c2: no header comment block at the top of the file (the better-comments mandate)"
fi
if [ -n "$HDR" ] && printf '%s\n' "$HDR" | grep -qF -- '--stop-after 168h'; then
  pass "c2: header documents the 1-week autostop convention (--stop-after 168h)"
else
  fail "c2: header does not document '--stop-after 168h'$NOTE"
fi
if [ -n "$HDR" ] && printf '%s\n' "$HDR" | grep -qF '720h'; then
  pass "c2: header documents the 30-day TTL cap (720h)"
else
  fail "c2: header does not document the 720h/30-day TTL cap$NOTE"
fi
if [ -n "$HDR" ] && printf '%s\n' "$HDR" | grep -qiE '(^|[^a-zA-Z0-9_])manual([^a-zA-Z0-9_]|$)'; then
  pass "c2: header documents the manual (= never) TTL mapping"
else
  fail "c2: header does not document the manual TTL mapping$NOTE"
fi

# --- criterion 4: chart packaging guard + lint/template ---------------------
# helm dependency build is the documented fresh-worktree precondition
# (friction #16); it only writes the gitignored dep tarball and leaves
# Chart.lock untouched.
if (cd "$REPO_ROOT" && "$HELM" dependency build charts/coder >/dev/null 2>&1); then
  pass "precondition: helm dependency build charts/coder ok"
else
  fail "precondition: helm dependency build charts/coder failed (registry unreachable?) — helm checks below may be unreliable"
fi

if [ ! -x "$HELM" ]; then
  fail "c4: helm missing at $HELM — packaging guard not runnable"
  fail "c4: helm missing at $HELM — helm lint not runnable"
  fail "c4: helm missing at $HELM — helm template not runnable"
else
  pkgdir=/tmp/opencode/helm-pkg
  rm -rf "$pkgdir"
  if (cd "$REPO_ROOT" && "$HELM" package charts/coder -d "$pkgdir" >/dev/null 2>&1); then
    tgz=$(ls "$pkgdir"/coder-*.tgz 2>/dev/null | head -n 1)
    if [ -z "$tgz" ]; then
      fail "c4: helm package produced no coder-*.tgz in $pkgdir"
    else
      # grep -c exits 1 on a zero count, which is the PASSING outcome here.
      count=$(tar -tzf "$tgz" | grep -c 'coder-templates/' || true)
      if [ "${count:-0}" -eq 0 ]; then
        pass "c4: packaged chart contains 0 coder-templates/ entries (.helmignore still covers the new subfolder)"
      else
        fail "c4: packaged chart contains $count coder-templates/ entries (expected 0): $(tar -tzf "$tgz" | grep 'coder-templates/' | head -n 3 | tr '\n' '|')"
      fi
    fi
  else
    fail "c4: helm package charts/coder failed"
  fi

  if (cd "$REPO_ROOT" && "$HELM" lint charts/coder >/dev/null 2>&1); then
    pass "c4: helm lint charts/coder passes"
  else
    fail "c4: helm lint charts/coder failed: $(cd "$REPO_ROOT" && "$HELM" lint charts/coder 2>&1 | grep -iE 'error|fail' | head -n 2 | tr '\n' '|')"
  fi
  if (cd "$REPO_ROOT" && "$HELM" template charts/coder >/dev/null 2>&1); then
    pass "c4: helm template charts/coder renders"
  else
    fail "c4: helm template charts/coder failed: $(cd "$REPO_ROOT" && "$HELM" template charts/coder 2>&1 | tail -n 2 | tr '\n' '|')"
  fi
fi

echo "=== coder-hardened: $PASS passed, $FAIL failed (REPO_ROOT=$REPO_ROOT) ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
