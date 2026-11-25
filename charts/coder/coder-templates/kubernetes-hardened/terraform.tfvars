# Resolved variable values for the kubernetes-hardened workspace template.
#
# Coder persists template-variable values server-side after the first push and
# re-uses them on every later version (resolved values always override the
# `default` in main.tf — see coder.com/docs/admin/templates/extending-templates/variables,
# "Resolved values vs. default values"). The coder CLI
# auto-loads terraform.tfvars on `coder templates push`, so this file is
# the GitOps single source of truth for those values.
#
# namespace is required in main.tf with no default, so it is supplied here.
# The template header requires it to name the namespace that holds the
# git-auth secrets (github-pat, forgejo-token — rendered by
# services/dev/prod): a workspace elsewhere starts with no git credentials,
# and its home PVC lands there too. They sit in `default` on the dev cluster
# (services/dev/prod/templates/secret-github.yaml,
# secret-forgejo-token.yaml), so "default" is the value.

namespace = "default"
