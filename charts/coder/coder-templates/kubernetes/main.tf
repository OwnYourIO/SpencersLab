terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "coder" {
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
}

variable "shared_pvc_name" {
  type        = string
  description = "Name of the pre-existing SeaweedFS RWX PVC shared by all workspaces"
  default     = "dev-shared"
}

variable "opencode_version" {
  type        = string
  description = "Pinned OpenCode 2 version (npm @opencode/cli; the old opencode-ai package is V1-only). OpenChamber 2.x requires >= 2.0.15."
  default     = "2.0.22"
}

variable "openchamber_version" {
  type        = string
  description = "Pinned OpenChamber version (npm @openchamber/web)."
  default     = "2.1.0"
}

variable "kilo_cli_version" {
  type        = string
  description = "Pinned Kilo CLI version (npm @kilocode/cli)."
  default     = "7.7.7"
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "12"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 GB"
    value = "2"
  }
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "12 GB"
    value = "12"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 99999
  }
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Password for the workspace's OpenCode server. OpenCode 2 always requires one
# (it generates a random one if unset), so we pin a stable value per workspace.
# Stored in the workspace's Terraform state; survives stop/start.
resource "random_password" "opencode_server" {
  length  = 32
  special = false
  keepers = {
    workspace_id = data.coder_workspace.me.id
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  # Point OpenChamber at the pinned OpenCode binary.
  # Don't set PATH here: it would replace the agent's PATH and hide the `coder` binary.
  # OPENCODE_SERVER_PASSWORD is set by the agent on every process it launches
  # (startup script, code-server + its extension host, terminals, `coder ssh`), so the
  # OpenChamber extension and OpenChamber server can both authenticate to OpenCode.
  env = {
    OPENCODE_BINARY          = "/usr/local/bin/opencode"
    OPENCODE_SERVER_USERNAME = "opencode"
    OPENCODE_SERVER_PASSWORD = random_password.opencode_server.result
  }

  startup_script = <<-EOT
    set -e

    # Service output goes to the container's stdout/stderr (PID 1) so it shows
    # up in `kubectl logs`, prefixed so the streams can be told apart.
    CONTAINER_OUT=/proc/1/fd/1

    if [ ! -f ~/.init.done ]; then
      cp -rT /etc/skel ~ || echo "WARN: skel copy failed"
      touch ~/.bashrc ~/.profile
      touch ~/.init.done
    fi

    sudo apt-get update
    sudo apt-get -y install git-lfs 

    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi
    . "$NVM_DIR/nvm.sh"

    if ! nvm ls 26 >/dev/null 2>&1; then
      nvm install 26
      nvm alias default 26
    fi
    nvm use 26 >/dev/null

    if ! grep -q 'NVM_DIR' ~/.bashrc; then
      cat >> ~/.bashrc <<'RC'
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    RC
    fi

    # Install pinned OpenCode, OpenChamber and Kilo CLI (skipped if already at that version).
    # Each install is independent: a failure is logged but doesn't stop the rest of the script.
    installed() { npm ls -g --depth=0 "$1@$2" >/dev/null 2>&1; }
    install_pkg() {
      installed "$1" "$2" && return 0
      npm install -g "$1@$2" || echo "ERROR: npm install -g $1@$2 failed" >&2
    }
    install_pkg @opencode/cli     '${var.opencode_version}'
    install_pkg @openchamber/web  '${var.openchamber_version}'
    install_pkg @kilocode/cli     '${var.kilo_cli_version}'

    # npm 12 (Node 26) blocks install scripts by default, which leaves @opencode/cli's
    # native binary unlinked. Run its postinstall directly if that happened.
    if ! opencode --version >/dev/null 2>&1; then
      OC_PKG="$(npm root -g)/@opencode/cli"
      [ -f "$OC_PKG/postinstall.mjs" ] && (cd "$OC_PKG" && node postinstall.mjs) || true
    fi
    opencode --version || echo "ERROR: opencode is not runnable" >&2

    # Put node and the pinned CLIs on the default PATH for every shell,
    # `coder ssh`, and non-interactive SSH (Emdash). /usr/local/bin is in the
    # container image, so this is recreated on every start.
    for bin in node npm npx opencode openchamber kilo; do
      path="$(command -v "$bin" || true)"
      if [ -n "$path" ]; then
        sudo ln -sf "$path" "/usr/local/bin/$bin"
      else
        echo "WARN: $bin not found, not linked" >&2
      fi
    done

    # One long-lived OpenCode server shared by OpenChamber and the VS Code extension.
    # Its password comes from OPENCODE_SERVER_PASSWORD in coder_agent.env.
    if [ -z "$OPENCODE_SERVER_PASSWORD" ]; then
      echo "ERROR: OPENCODE_SERVER_PASSWORD is not set in the agent environment" >&2
    fi

    # Start OpenCode in the background, from the home dir (not some tool's storage dir).
    # (No pkill here: the pod is fresh on every start, and `pkill -f` would match this
    # startup script's own command line and kill it.)
    ( cd "$HOME" && nohup setsid sh -c 'opencode serve --hostname 127.0.0.1 --port 4096 2>&1 | sed -u "s/^/[opencode] /"' \
      >"$CONTAINER_OUT" 2>&1 </dev/null & )

    OC_UP=0
    for _ in $(seq 1 60); do
      if curl -fsS -u "opencode:$OPENCODE_SERVER_PASSWORD" http://127.0.0.1:4096/global/health >/dev/null 2>&1; then
        OC_UP=1; break
      fi
      sleep 1
    done
    [ "$OC_UP" = 1 ] && echo "OpenCode server is up on 127.0.0.1:4096" \
      || echo "ERROR: OpenCode server not healthy on 127.0.0.1:4096 after 60s" >&2

    # Start OpenChamber in the background, attached to that OpenCode server
    # instead of spawning its own. Loopback only, no UI password: Coder's app proxy handles auth.
    nohup setsid sh -c 'OPENCODE_HOST=http://127.0.0.1:4096 OPENCODE_SKIP_START=true openchamber serve --port 3000 --host 127.0.0.1 --foreground 2>&1 | sed -u "s/^/[openchamber] /"' \
      >"$CONTAINER_OUT" 2>&1 </dev/null &

    # Install the latest code-server.
    # Append "--version x.x.x" to install a specific version of code-server.
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
    
    # Give's cline's heap enough room to work with.
    # (Scoped to code-server only so it isn't inherited by OpenChamber/OpenCode.)
    # Start code-server in the background. It inherits OPENCODE_SERVER_PASSWORD so the
    # OpenChamber extension can authenticate to http://127.0.0.1:4096.
    nohup setsid sh -c 'NODE_OPTIONS="--max-old-space-size=6144" /tmp/code-server/bin/code-server --auth none --port 13337 2>&1 | sed -u "s/^/[code-server] /"' \
      >"$CONTAINER_OUT" 2>&1 </dev/null &
  EOT

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://127.0.0.1:13337?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://127.0.0.1:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

# OpenChamber
# Must be a subdomain app: OpenChamber can't be served under a path prefix.
# Requires CODER_WILDCARD_ACCESS_URL on the Coder server (e.g. *-coder.spencerslab.com).
resource "coder_app" "openchamber" {
  agent_id     = coder_agent.main.id
  slug         = "openchamber"
  display_name = "OpenChamber"
  icon         = "https://openchamber.dev/logo-dark.svg"
  url          = "http://127.0.0.1:3000"
  subdomain    = true
  share        = "owner"
  open_in      = "tab"

  healthcheck {
    url       = "http://127.0.0.1:3000/health"
    interval  = 5
    threshold = 60
  }
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      //Coder-specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace_owner.me.id
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home
  ]
  wait_for_rollout = false
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
        "app.kubernetes.io/part-of"  = "coder"
        "com.coder.resource"         = "true"
        "com.coder.workspace.id"     = data.coder_workspace.me.id
        "com.coder.workspace.name"   = data.coder_workspace.me.name
        "com.coder.user.id"          = data.coder_workspace_owner.me.id
        "com.coder.user.username"    = data.coder_workspace_owner.me.name
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
          "app.kubernetes.io/part-of"  = "coder"
          "com.coder.resource"         = "true"
          "com.coder.workspace.id"     = data.coder_workspace.me.id
          "com.coder.workspace.name"   = data.coder_workspace.me.name
          "com.coder.user.id"          = data.coder_workspace_owner.me.id
          "com.coder.user.username"    = data.coder_workspace_owner.me.name
        }
      }
      spec {
        security_context {
          run_as_user     = 1000
          fs_group        = 1000
          run_as_non_root = true
          # Only chown/chmod the volume when its root doesn't already match fs_group,
          # instead of walking every file (nvm, node_modules, repos) on each start.
          fs_group_change_policy = "OnRootMismatch"
        }

        container {
          name              = "dev"
          image             = "codercom/enterprise-base:ubuntu"
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
          volume_mount {
            mount_path = "/shared"
            name       = "shared"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata.0.name
            read_only  = false
          }
        }

        volume {
          name = "shared"
          persistent_volume_claim {
            claim_name = var.shared_pvc_name
            read_only  = false
          }
        }

        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
