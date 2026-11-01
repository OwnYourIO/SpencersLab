# C06 staging contract tests (agent-test suite)

Run (repo root, hugo in PATH — plan Commands):

    export PATH="$HOME/.local/bin:$PATH"
    python3 -m pytest .agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/site-staging/tests/ -v

Scope: the artifacts C06 stages under `site-staging/` (workflows,
`sync-albums.yaml`, APPLY-INSTRUCTIONS). Tests are red-first — every leg
names the missing artifact. `test_t5_render_gate.py` builds scratch sites
under /tmp only; `/home/coder/CuratedForest.com` is read-only by contract
(plan Out-of-scope; a live `git status --porcelain` snapshot guards it).

Tier A of the render gate runs offline in agent sessions (module-free
shell site embedding the live `gallery.html`). Tier B rsyncs the full repo
and needs hugo modules — where the go binary/network are unavailable it
reports SKIP-BLOCKED per the chunk's rule ("never fake-pass"), green
condition: an environment with `go` + warm module cache (owner workstation
or the C07 clone).
