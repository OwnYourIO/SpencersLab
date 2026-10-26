#!/bin/sh
# Workspace bootstrap called by the Coder templates' startup_script: seed $HOME
# on first boot, provision the SSH key + known_hosts the git hosts need, bring
# up the OpenCode/OpenChamber pair the IDE talks to, wire optional git auth,
# and clone the repos selected via the template's "repos" parameter.
#
# It must return, because the Coder agent starts after this script exits. The
# servers therefore detach, and their output is funnelled into the container's
# stdout so `coder ssh` and pod logs keep showing it.
#
# code-server is deliberately NOT here: the Coder template's official
# code-server module installs and starts it as a separate startup step, so it
# tracks upstream without a pin in this image.
#
# Token git auth is optional and driven by env the template supplies. No env,
# no action: GITHUB_TOKEN, FORGEJO_TOKEN + FORGEJO_HOST (dev instance), and
# FORGEJO_OAUTH_ID (the coder external-auth provider id covering
# FORGEJO_HOST's instance).
# When FORGEJO_OAUTH_ID is set and its provider is approved, the per-user
# SSO token replaces the dev host's PAT helper for git-over-https: git
# consults credential helpers BEFORE the agent's GIT_ASKPASS, so the helper
# has to be absent for the per-user token to answer. Unset (or unapproved)
# keeps the pure PAT behavior. Git identity comes from CODER_USER /
# CODER_USER_EMAIL; the clone list from WORKSPACE_GIT_REPOS.
set -eu

log() {
  printf '[workspace-startup] %s\n' "$*"
}

# pid 1 is the Coder agent under the same uid, so its stdout is the container
# log; a launcher that cannot write there falls back to this script's stderr
# rather than silently losing both servers.
log_fd=/proc/1/fd/1
[ -w "$log_fd" ] || log_fd=/dev/stderr

# Each server is detached into its own session and tagged, so a crash of one
# leaves the other running and its output stays attributable in one stream.
# The outer sh's stdin/stdout/stderr must NOT stay attached to this script's
# own pipes: the coder agent marks the startup script failed ("output pipes
# were not closed") when a surviving child inherits them.
start_server() {
  label=$1
  shift
  nohup setsid sh -c "$* 2>&1 | sed -u \"s/^/[${label}] /\" >> \"$log_fd\"" </dev/null >>"$log_fd" 2>&1 &
}

# Polls until the URL answers or 60s pass. The caller decides what a timeout
# means; a workspace that boots without these servers is still usable over SSH.
wait_for_http() {
  url=$1
  deadline=$(( $(date +%s) + 60 ))
  until curl -fsS -u "opencode:${OPENCODE_SERVER_PASSWORD}" "$url" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      return 1
    fi
    sleep 1
  done
}

# The PVC shadows the /etc/skel copy useradd seeded at build time, so a fresh
# workspace starts with an empty home and needs the shell dotfiles. The marker
# keeps later boots from overwriting a user's own edits.
if [ ! -e "${HOME}/.init_done" ]; then
  if [ -d /etc/skel ]; then
    # --no-preserve=ownership,timestamps: plain cp -a also applies
    # /etc/skel's root-owned attributes to the $HOME mount point itself,
    # which uid 1000 cannot do (EPERM) — and set -eu would abort the whole
    # boot over a dotfile copy. The seed is best-effort: warn, keep booting.
    cp -a --no-preserve=ownership,timestamps /etc/skel/. "${HOME}/" \
      || log "WARN: /etc/skel seed hit errors; continuing"
  fi
  : > "${HOME}/.init_done"
  log "seeded ${HOME} from /etc/skel"
fi

# The OpenCode server's project root is its working directory, so the servers
# start from the home PVC rather than wherever the agent process happens to
# sit; set -eu makes a failed cd abort the boot instead of relocating silently.
cd "${HOME}"

# One key per home PVC, kept for its lifetime: regenerating it at every boot
# would invalidate the public half the user already registered with their git
# hosts. The public half is derivable from the private key, so a PVC that
# carries one without the other is repaired rather than treated as missing.
SSH_DIR=$HOME/.ssh
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$SSH_DIR/id_rsa" ]; then
  ssh-keygen -t rsa -b 4096 -N '' -C "coder-$(whoami)@$(hostname)" -f "$SSH_DIR/id_rsa" >/dev/null
fi
chmod 600 "$SSH_DIR/id_rsa"
if [ ! -f "$SSH_DIR/id_rsa.pub" ]; then
  ssh-keygen -y -f "$SSH_DIR/id_rsa" > "$SSH_DIR/id_rsa.pub"
fi
chmod 644 "$SSH_DIR/id_rsa.pub"

touch "$SSH_DIR/known_hosts"
chmod 600 "$SSH_DIR/known_hosts"

# Pre-trusting the hosts keeps the clone job non-interactive: an unknown host
# key stops git with a prompt nobody can answer during a boot. The lab forges
# serve ssh:// at the node's forgejo port 22222 (sibling forgejo-ssh ruling:
# node sshd keeps :22), so they are scanned there — a port-22 scan of a forge
# host would pin the node's sshd key under the wrong name, useless for those
# URLs. ssh-keyscan emits non-default-port entries as [host]:port, exactly the
# name ssh looks up for ssh://git@<host>:22222/... URLs. Hosts already listed
# are skipped so a key rotation stays visible instead of being silently
# re-pinned. A failed scan is a warning only — one unreachable host must not
# stop the boot.
for ssh_spec in git.scifi.farm:22222 git.spencerslab.com:22222 github.com:22; do
  ssh_host=${ssh_spec%:*}
  ssh_port=${ssh_spec##*:}
  if [ "$ssh_port" = 22 ]; then
    ssh_entry=$ssh_host
  else
    ssh_entry="[$ssh_host]:$ssh_port"
  fi
  if ssh-keygen -F "$ssh_entry" -f "$SSH_DIR/known_hosts" >/dev/null 2>&1; then
    continue
  fi
  # ssh-keyscan can time out or find no key and still exit 0, so the captured
  # output decides whether the host was added, not the exit status.
  scanned=$(ssh-keyscan -t rsa,ecdsa,ed25519 -p "$ssh_port" "$ssh_host" 2>/dev/null || true)
  if [ -n "$scanned" ]; then
    printf '%s\n' "$scanned" >>"$SSH_DIR/known_hosts"
    log "known_hosts: added $ssh_entry"
  else
    log "WARN: ssh-keyscan $ssh_entry failed; git over SSH to it may need a manual host-key acceptance"
  fi
done

# The private key never leaves the workspace, so the startup log is the only
# place a user can read the public half to register it. The lab Forgejos lead
# the list — canonical first, then dev — because the lab's own repos live
# there; GitHub carries the external ones.
echo "=============================================================="
echo "Workspace SSH public key:"
cat "$SSH_DIR/id_rsa.pub"
echo "Add it to your git hosts before the clone job can succeed:"
echo "  1. Forgejo  (git.spencerslab.com)  -> Settings -> SSH/GPG Keys"
echo "  2. Forgejo  (git.scifi.farm)       -> Settings -> SSH/GPG Keys"
echo "  3. GitHub   (github.com)           -> Settings -> SSH and GPG Keys"
echo "=============================================================="

# The password is mandatory here rather than defaulted: the server binds
# loopback, and anything else in the pod that reached an unauthenticated agent
# API could drive the workspace.
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  log 'OPENCODE_SERVER_PASSWORD is not set; not starting the OpenCode and OpenChamber servers'
else
  start_server opencode opencode serve --hostname 127.0.0.1 --port 4096
  if wait_for_http 'http://127.0.0.1:4096/global/health'; then
    log 'OpenCode server is up on 127.0.0.1:4096'
    # --foreground so OpenChamber does not daemonize away from the log pipe;
    # OPENCODE_SKIP_START keeps it off its own managed OpenCode instance,
    # which would compete with the one above for the workspace.
    #
    # --host 0.0.0.0 because devices reach OpenChamber via the pod IP.
    # OpenChamber refuses a non-loopback bind without UI authentication;
    # OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true is the explicit waiver
    # (user decision 2026-10-21). Accepted exposure: anything on the cluster
    # network can drive the UI on :3000. The OpenCode agent API behind it
    # stays loopback-only.
    start_server openchamber env OPENCODE_HOST=http://127.0.0.1:4096 OPENCODE_SKIP_START=true \
      OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true \
      openchamber serve --foreground --host 0.0.0.0 --port 3000
  else
    log 'OpenCode server did not answer within 60s; not starting OpenChamber (it proxies to that server)'
  fi
fi

# The helper echoes the token from the environment at use time. Nothing is
# written to disk: the home PVC outlives the pod, so a stored token would
# outlive the secret that set it.
configure_git_token() {
  host=$1
  env_var=$2
  git config --global "credential.https://${host}.helper" \
    "!f() { echo username=token; echo \"password=\$${env_var}\"; }; f"
}

# Wires one Forgejo host. Arguments: the token value, the NAME of the env var
# holding it (the helper above must keep echoing $<NAME> so git expands it at
# use time — nothing secret is ever persisted to the home PVC), the
# host-or-URL, and an optional
# fourth "no-helper" mode for hosts whose per-user SSO token should answer
# through the agent's GIT_ASKPASS instead (a wired helper is consulted first
# and would shadow it forever on the PVC). fj keeps the bot PAT in every
# mode: its token store does not refresh, so a ~1h OAuth token seeded there
# would rot mid-session.
wire_forgejo() {
  token_value=$1
  token_var=$2
  forgejo_ref=$3
  wire_mode=${4:-helper}
  # Accept a bare host or a full URL: git needs the host, fj accepts either.
  forgejo_host=${forgejo_ref#https://}
  forgejo_host=${forgejo_host%%/*}
  # Git config runs first: a Forgejo API outage below must not cost the user
  # their working https push path.
  if [ "$wire_mode" != no-helper ]; then
    configure_git_token "${forgejo_host}" "${token_var}"
  fi
  # fj keeps its own token store and ignores git credentials, so the same token
  # is seeded there for `fj` subcommands. A failure is logged, not fatal: a
  # Forgejo outage at boot must not stop the workspace from starting.
  if fj auth add-token --host "https://${forgejo_host}" "${token_value}" >/dev/null 2>&1; then
    log "fj token seeded for ${forgejo_host}"
  else
    log "fj auth add-token failed for ${forgejo_host}; git over https still works"
  fi
}

if [ -n "${GITHUB_TOKEN:-}" ]; then
  configure_git_token github.com GITHUB_TOKEN
  log 'git credential helper configured for github.com'
fi

# Optional per-user SSO for the dev instance (FORGEJO_OAUTH_ID is the coder
# external-auth provider id for FORGEJO_HOST's coder server; absent => today's
# PAT-only behavior unchanged). v2.35.2 CLI contract: `coder external-auth
# access-token <id>` prints a validated token on stdout with exit 0, else the
# authentication URL on stdout with exit 1. The `if VAR=$(...)` form absorbs
# the exit 1 — a bare assignment under set -eu would abort the boot exactly
# when the approval URL is produced. Probe failure of ANY kind (unapproved,
# CLI missing, coderd unreachable) is the unapproved path: the boot must
# never die because of SSO. On approval the PAT helper must not answer for
# this host: git consults credential helpers before GIT_ASKPASS, and the
# home PVC persists ~/.gitconfig across boots, so a helper wired before the
# user approved would shadow the per-user token forever — the unset below is
# load-bearing, not cosmetic.
sso_approved=0
sso_host=""
if [ -n "${FORGEJO_OAUTH_ID:-}" ] && [ -n "${FORGEJO_HOST:-}" ]; then
  sso_host=${FORGEJO_HOST#https://}
  sso_host=${sso_host%%/*}
  if sso_probe=$(coder external-auth access-token "$FORGEJO_OAUTH_ID" 2>/dev/null); then
    sso_approved=1
    # git exits 5 when the key is already absent; a missing entry is the
    # common case (first approval), not an error.
    git config --global --unset-all "credential.https://${sso_host}.helper" 2>/dev/null || true
    log "SSO approved: git over https to ${sso_host} runs as your own account via the agent's askpass"
  elif [ -n "$sso_probe" ]; then
    log "SSO not approved for ${sso_host} yet — approve here to get per-user git identity, the shared PAT is used until then: $sso_probe"
  else
    log "WARN: no approval URL from 'coder external-auth access-token' (CLI missing or coderd unreachable); shared PAT stays active for ${sso_host} until SSO approval works"
  fi
fi

# The Forgejo pair is optional — no env, no action for the host. An approved
# dev host keeps the call (fj still needs the bot PAT) but in no-helper mode,
# so only the SSO token answers git. This coder server has one external-auth
# provider slot and it serves the dev instance (pairing ruling 2026-10-24);
# the canonical forge stays reachable over SSH keys via the host pre-trust
# above — its PAT plumbing (forgejo-token-canonical) was removed unused.
sso_wire_mode=
if [ "$sso_approved" = 1 ]; then
  sso_wire_mode=no-helper
fi
if [ -n "${FORGEJO_TOKEN:-}" ] && [ -n "${FORGEJO_HOST:-}" ]; then
  wire_forgejo "${FORGEJO_TOKEN}" FORGEJO_TOKEN "${FORGEJO_HOST}" "$sso_wire_mode"
fi

# Git rejects commits from a process with no identity; the template passes the
# workspace owner's details through the agent environment.
if [ -n "${CODER_USER:-}" ]; then
  git config --global user.name "$CODER_USER"
fi
if [ -n "${CODER_USER_EMAIL:-}" ]; then
  git config --global user.email "$CODER_USER_EMAIL"
fi

# WORKSPACE_GIT_REPOS is the comma-separated list of clone URLs selected via
# the template's "repos" parameter. Repos land directly under $HOME so they
# sit on the PVC and survive a restart. An existing checkout is left alone:
# the work in it outweighs a fresh clone. Each failure is a warning, because
# one bad URL must not stop the remaining repos or the servers already
# running.
if [ -n "${WORKSPACE_GIT_REPOS:-}" ]; then
  # The value is documented as comma-separated; splitting on spaces too
  # absorbs the ", " a hand-edited environment variable usually ends up with.
  SAVED_IFS=$IFS
  IFS=' ,'
  # The unquoted split is also a pathname-expansion point: glob characters in
  # a repo URL must stay literal, not match filenames in the current directory.
  set -f
  for repo_url in $WORKSPACE_GIT_REPOS; do
    if [ -z "$repo_url" ]; then
      continue
    fi
    dest=$HOME/$(basename "$repo_url" .git)
    if [ -d "$dest/.git" ]; then
      log "SKIP: $dest already holds a checkout"
      continue
    fi
    # Per-host SSO layering on the clone path. Only https URLs consult
    # credentials, so the host comparison is limited to them (ssh:// and
    # scp-style URLs keep the key-based path untouched).
    clone_host=
    case $repo_url in
      https://*)
        clone_host=${repo_url#https://}
        clone_host=${clone_host%%/*}
        ;;
    esac
    if [ "$sso_approved" = 1 ] && [ "$clone_host" = "$sso_host" ]; then
      # The per-user token rides on this git PROCESS only — the value is
      # expanded into the environment here, so nothing lands in
      # ~/.gitconfig or any file (the no-disk invariant extended to the
      # OAuth token, and a helper naming a boot-only var would answer an
      # empty password from later terminals).
      if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper \
        GIT_CONFIG_VALUE_0="!f() { echo username=token; echo \"password=$sso_probe\"; }; f" \
        GIT_TERMINAL_PROMPT=0 git clone "$repo_url" "$dest"; then
        log "Cloned $repo_url into $dest"
      else
        log "WARN: cloning $repo_url failed; check the SSH key registration above and repo access"
      fi
      continue
    fi
    # Polite gate: without approval AND without the shared PAT there is no
    # credential left for this host — skip with a visible reason instead of
    # a raw auth failure (the fallback PAT, when present, clones normally).
    if [ -n "$sso_host" ] && [ "$clone_host" = "$sso_host" ] && [ -z "${FORGEJO_TOKEN:-}" ]; then
      log "SKIP: $repo_url is pending SSO approval for ${sso_host} and no shared PAT is set — see the approval banner above"
      continue
    fi
    if GIT_TERMINAL_PROMPT=0 git clone "$repo_url" "$dest"; then
      log "Cloned $repo_url into $dest"
    else
      log "WARN: cloning $repo_url failed; check the SSH key registration above and repo access"
    fi
  done
  set +f
  IFS=$SAVED_IFS
fi
