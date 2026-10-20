# kubernetes-hardened: Coder workspace template on the rebuilt
# ghcr.io/ownyourio/coder-workspace image, with restricted Pod Security
# Standards. The existing kubernetes template (base image with runtime
# installs) is untouched; workspaces choose one or the other at creation.
#
# Image/startup contract: the image bakes every tool (node, go, helm,
# kubectl, uv, fj, opencode, openchamber). The baked script
# /usr/local/bin/workspace-startup.sh is the entire bootstrap: it seeds
# $HOME on first boot, provisions the workspace SSH key + known_hosts,
# starts OpenCode and OpenChamber, applies optional env-driven git auth
# (tokens over HTTPS, the key over SSH), and clones the repos selected via
# the "repos" parameter. code-server is deliberately NOT the script's job:
# the official Coder code-server module below installs and starts it as its
# own startup step, fetching the current upstream release on every start.
#
# Restricted PSS holds for the same reason. No runtime write targets the
# rootfs: the writable paths are the home PVC, the /tmp emptyDir (also the
# code-server module's install target), and /shared when the pushed template
# names a shared RWX PVC. The container therefore runs with a read-only root
# filesystem, all capabilities dropped, no privilege escalation, and no sudo.
#
# The image is public on GHCR and pulled with pullPolicy Always, so there
# are no pull secrets and no registry wiring of any kind.
#
# The home PVC sets lifecycle.prevent_destroy = false: deleting a workspace
# also deletes its home PVC and everything on it.
#
# SHUTDOWN: Coder's native autostop TTL, defaulted to 1 week. Set the
# template default once after the first push:
#     coder templates edit kubernetes-hardened --default-ttl 168h
# and keep --allow-user-autostop at its default (true) so each workspace can
# override the timer. The supported choices are 9 hours, 2 day, 1 week,
# 1 month and never, spelled as free-form durations: 9h, 24h, 168h, 720h
# (Coder's 30-day cap), and `manual` for never — passed at creation
# (e.g. coder create kubernetes-hardened <name> --stop-after 168h) or set
# afterwards in the UI Schedule tab / `coder schedule`. The TTL is stored per
# workspace: it survives stop/start and re-applies on each build. Template
# TF cannot set it: the coder provider has no TTL resource, and the TTL
# endpoint rejects the workspace agent token (verified 2027-10-18), so
# setting the TTL is a user action, not a template feature.
#
# namespace must name the namespace that holds the git-auth secrets
# (github-pat, forgejo-token — rendered by services/dev/prod): a workspace
# elsewhere starts with no git credentials, and its home PVC lands there too.

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
  description = "Name of a pre-existing shared RWX PVC to mount at /shared. Empty (the default) omits the mount entirely — dev has no such PVC (the dev-shared SeaweedFS claim lives on the gpu cluster), and a claim that does not exist leaves every workspace Pending."
  default     = ""
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

# SSH URLs because SpencersLab is private — anonymous HTTPS clone fails — and
# the baked startup script prints the key-registration banner the clone needs.
# More repos (including git@git.scifi.farm ones) are added as options at push
# time.
data "coder_parameter" "repos" {
  name         = "repos"
  display_name = "Git repositories"
  description  = "Repositories the startup script clones into the home dir on every start, leaving existing checkouts alone"
  type         = "list(string)"
  form_type    = "multi-select"
  default      = jsonencode(["git@github.com:OwnYourIO/SpencersLab.git"])
  mutable      = true
  option {
    name  = "SpencersLab"
    value = "git@github.com:OwnYourIO/SpencersLab.git"
  }
}

provider "kubernetes" {
  # config_path = null makes the provider use the in-cluster config (the Coder pod's ServiceAccount).
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

  # OPENCODE_BINARY: the image bakes its npm globals into /usr/local/bin
  # (no nvm), which is where OpenChamber looks.
  # Don't set PATH here: it would replace the agent's PATH and hide the `coder` binary.
  # OPENCODE_SERVER_PASSWORD is set by the agent on every process it launches
  # (startup script, code-server + its extension host, terminals, `coder ssh`), so the
  # OpenChamber extension and OpenChamber server can both authenticate to OpenCode.
  env = {
    OPENCODE_BINARY          = "/usr/local/bin/opencode"
    OPENCODE_SERVER_USERNAME = "opencode"
    OPENCODE_SERVER_PASSWORD = random_password.opencode_server.result
    # Git identity for the baked startup script (git config --global),
    # sourced explicitly from the workspace owner.
    CODER_USER       = data.coder_workspace_owner.me.name
    CODER_USER_EMAIL = data.coder_workspace_owner.me.email
    # coder_parameter.value stays a string even for list(string) params, so
    # decode the multi-select JSON array and flatten it to the comma-separated
    # form the baked startup script splits on.
    WORKSPACE_GIT_REPOS = join(",", jsondecode(data.coder_parameter.repos.value))
  }

  startup_script = <<-EOT
    set -e

    # One line is the entire bootstrap: the image bakes every tool, so
    # nothing here may install into the read-only root filesystem.
    /usr/local/bin/workspace-startup.sh
  EOT

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

# code-server via the official Coder module instead of a repo pin: its
# run_on_start script runs code-server.dev/install.sh on EVERY workspace
# start (no install_version set), so every start picks up the current
# upstream release — freshness over the pinned-tarball approach this
# replaced. Accepted costs: a ~240 MB download per start into the /tmp
# emptyDir, and no scoped NODE_OPTIONS (the module's launcher takes none),
# so the old 6 GB Cline heap is gone. The module also creates the
# coder_app (path-based, port 13337, ?folder=/home/coder), which is why
# this template declares none.
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.6.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
}

# OpenChamber
# Must be a subdomain app: OpenChamber can't be served under a path prefix.
# Requires CODER_WILDCARD_ACCESS_URL on the Coder server (e.g. *-coder.example.com).
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
    prevent_destroy = false
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
          run_as_group    = 1000
          fs_group        = 1000
          run_as_non_root = true
          # Only chown/chmod the volume when its root doesn't already match fs_group,
          # instead of walking every file (node_modules, code-server install,
          # repos) on each start.
          fs_group_change_policy = "OnRootMismatch"
        }

        container {
          name  = "dev"
          image = "ghcr.io/ownyourio/coder-workspace:main"
          # Rolling :main until the first CI build of this image publishes an
          # immutable :v<run> tag; pin that tag here (and drop Always) when it
          # exists.
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user                = "1000"
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
            seccomp_profile {
              type = "RuntimeDefault"
            }
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          # Both Secrets are read from var.namespace (a secretKeyRef cannot
          # cross namespaces); optional keeps a missing one from blocking the
          # workspace start — the startup script then leaves that host
          # unauthenticated. FORGEJO_HOST accepts a bare host or a URL; the
          # script strips the scheme itself.
          env {
            name = "GITHUB_TOKEN"
            value_from {
              secret_key_ref {
                name     = "github-pat"
                key      = "GITHUB_PERSONAL_ACCESS_TOKEN"
                optional = true
              }
            }
          }
          env {
            name = "FORGEJO_TOKEN"
            value_from {
              secret_key_ref {
                name     = "forgejo-token"
                key      = "FORGEJO_TOKEN"
                optional = true
              }
            }
          }
          env {
            name  = "FORGEJO_HOST"
            value = "git.scifi.farm"
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
          dynamic "volume_mount" {
            for_each = var.shared_pvc_name != "" ? [1] : []
            content {
              mount_path = "/shared"
              name       = "shared"
              read_only  = false
            }
          }
          volume_mount {
            mount_path = "/tmp"
            name       = "tmp"
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

        dynamic "volume" {
          for_each = var.shared_pvc_name != "" ? [var.shared_pvc_name] : []
          content {
            name = "shared"
            persistent_volume_claim {
              claim_name = volume.value
              read_only  = false
            }
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "2Gi"
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
