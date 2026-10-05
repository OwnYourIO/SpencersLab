# 2026-10-04 — dep: update opencode and openchamber in the Coder workspace template

## Request

Update the locally installed `opencode` and `openchamber` CLIs.

## Root cause (why a plain npm update didn't survive)

The workspace's **Coder template startup script** enforces version pins on
every boot:

```bash
install_pkg @opencode/cli     '${var.opencode_version}'     # was 2.0.16
install_pkg @openchamber/web  '${var.openchamber_version}'  # was 2.0.2
install_pkg @kilocode/cli     '${var.kilo_cli_version}'     # 7.7.7 (unchanged)
```

`installed()` checks for the exact pinned version, so any manual update is
downgraded back at the next container start. Evidence:
`/tmp/coder-agent.log` contains the full startup script;
`/tmp/coder-startup-script.log` shows the reinstall at boot. The install
target itself (`~/.nvm` on the home PVC) is persistent — only the pins
forced the revert. The template source lives server-side (coder.spencerslab.com),
not in any repo on the workspace PVC.

## Fix

Updated template `main.tf` (provided by the user, returned updated):

| Variable | Before | After |
|---|---|---|
| `opencode_version` | 2.0.16 | **2.0.22** |
| `openchamber_version` | 2.0.2 | **2.1.0** |
| `kilo_cli_version` | 7.7.7 | 7.7.7 (latest is 7.8.3 — not requested) |

Updated file written to `charts/coder/coder-templates/main.tf` in this repo
(folder created on purpose — the coder chart itself will be moved in later;
only the two `default` values changed). A working copy also sits at
`/tmp/opencode/coder-workspace-template/main.tf`.

## Second root cause (why the first template push didn't take effect)

Even with the corrected TF pushed (versions `healthy_cooper32`,
`bored_cummings12` on template `kubernetes`, verified in the Coder DB:
correct archive bytes + correct `default_value`s), workspace builds still
rendered the old pins. Cause: `template_version_variables` stores an
explicit `value` column that overrides `default_value`. Every version of
this template since 2026-09-26 has stored values `opencode_version=2.0.16`,
`openchamber_version=2.0.2`; Coder carries those forward to new versions on
push, so they kept overriding the new TF defaults. Diagnosis path:
`workspace_agent_scripts` (rendered script had old pins) →
`provisioner_jobs.file_id` + `files` archive (uploaded TF was correct) →
`template_version_variables` (`value` vs `default_value` mismatch).

Fix (user-owned): update/clear the stored variable values — Coder UI
Templates → kubernetes → Template settings → Variables, or re-push with
`--variable opencode_version=2.0.22 --variable openchamber_version=2.1.0`.
Long-term: keep stored values cleared so TF defaults are the single source
of truth.

## Validation

- Versions confirmed against npm: `@opencode/cli@2.0.22` (latest),
  `@openchamber/web@2.1.0` (latest).
- OpenChamber 2.x requires OpenCode >= 2.0.15 — satisfied.
- `terraform validate` not run (terraform not installed in the workspace);
  diff is two string literals.

## User-owned steps

1. Push the new template version (`coder templates push ...`) from wherever
   the template source is managed.
2. Restart the workspace — the startup script installs the new pins into
   `~/.nvm` automatically and restarts the opencode/openchamber servers.

## Notes

- npm blocked install scripts for `node-pty` / `msgpackr-extract`
  (allowScripts); `.npmrc` already allows `@opencode/cli`. No action needed
  unless OpenChamber terminal features misbehave.
- The earlier npm-only update in this session was superseded by this fix.
