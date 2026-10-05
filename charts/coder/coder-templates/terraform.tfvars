# Resolved variable values for the kubernetes workspace template.
#
# Coder persists template-variable values server-side after the first push and
# re-uses them on every later version (resolved values always override the
# `default` in main.tf — see coder.com/docs/admin/templates/extending-templates/variables,
# "Resolved values vs. default values"). The coder CLI auto-loads
# terraform.tfvars on `coder templates push`, so this file is the GitOps single
# source of truth for those values.
#
# To bump opencode/openchamber/kilo: edit here, push a new template version,
# then update + restart the workspaces.

opencode_version    = "2.0.22"
openchamber_version = "2.1.0"
kilo_cli_version    = "7.7.7"
