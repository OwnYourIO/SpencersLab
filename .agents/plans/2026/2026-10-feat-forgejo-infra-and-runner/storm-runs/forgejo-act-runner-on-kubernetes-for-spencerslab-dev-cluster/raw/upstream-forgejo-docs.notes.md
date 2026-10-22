# Interview — Forgejo upstream documentation

Interviewed 2026-10-21 (inline, single session); claims re-verified against
sources on 2026-10-21.

## Q1: How does a runner register, and what does the server require?

The runner's identity is a **(uuid, token) pair**. It is created either in the
admin UI (Admin → Actions → Runners) or via the admin API. On the v15 server,
the create form is name + description only; the setup screen then shows the
UUID and token one last time plus a config snippet
(`runner_create.tmpl` / `runner_setup.tmpl`) [8]. The API equivalent is
`POST /api/v1/admin/actions/runners` with `{Name, Description, Ephemeral}`
returning 201 `{ID, UUID, Token}`; `GET`/`DELETE /admin/actions/runners/{id}`
exist, and `GET /admin(/actions)/runners/jobs?labels=` lists pending jobs [8].

The global registration-token endpoint
`GET /api/v1/admin/actions/runners/registration-token` is **deprecated in
Forgejo 15** (scoped user/org/repo variants still exist); token endpoints are
reusable — the server keeps returning the latest token for a runner
(`GetLatestRunnerToken`) [8]. The UI also offers per-runner
`reset_registration_token` and delete (`runner_list.tmpl`) [8].

**Actions is enabled by default** on the server (since v1.21). The `[actions]`
defaults are ENABLED=true, DEFAULT_ACTIONS_URL=https://data.forgejo.org,
ARTIFACT_RETENTION_DAYS=90, LOG_RETENTION_DAYS=365, ZOMBIE_TASK_TIMEOUT=10m,
ENDLESS_TASK_TIMEOUT=3h, ABANDONED_JOB_TIMEOUT=24h [6]. An instance that sets
no `[actions]` keys works out of the box with runners.

## Q2: What does the dev server actually run, and is it compatible?

The dev cluster's Forgejo is **15.0.9** (released 2026-09-17) per the
repo's wrapper chart (`charts/forgejo` appVersion 15.0.9, wrapping
`oci://code.forgejo.org/forgejo-helm` 17.2.0) and confirmed on the live pod
[18][19]. Current server releases: v15.0.10 (2026-10-12, latest 15.x LTS
patch), v16.0.6 (2026-10-12), v17.0.0 (2026-10-15) [9]. The v15.0 branch has
the gRPC actions API (`routers/api/actions/`, added 2026-01-15), so a v13
runner registering over gRPC is compatible with 15.0.9 [4][8]. Ephemeral
runners require Forgejo 15+ [4] — dev supports them, but they are not
supported in daemon mode [4].

Registration and runner-config docs are identical in content between the 15.0
and latest (17.x) doc trees, so findings hold for both.

## Q3: What env vars does the image honor?

None for registration. The v13 image's Dockerfile has a bare binary CMD
(`/bin/forgejo-runner` under dumb-init) with no auto-registration entrypoint
[4]. The `FORGEJO_INSTANCE_URL` / `FORGEJO_RUNNER_REGISTRATION_TOKEN`
pattern belongs to Gitea's `act_runner` — community pages that show it for
Forgejo are wrong (wiki.serversatho.me warns about exactly this) [15]. The
v13 blog post confirms all `GITEA_*` env vars are now ignored [3].
