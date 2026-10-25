# Friction — 2026-10-bug-llama-swap-echo-proxy-port

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Seeded from the sibling ticket (2026-10-feat-llama-swap-config-generation)
FRICTION.md — items still relevant to this ticket's surface:

- [open] `/tmp/opencode` tooling can vanish between sessions. Resolution: probe
  first. Verified 2026-10-25 (plan session): helm v3.16.4 present at
  `/tmp/opencode/bin/helm` (NOT on default PATH — use
  `PATH=/tmp/opencode/bin:$PATH`); app-template 5.0.1 tgz re-fetched via
  `helm dependency update charts/llama-swap`; llama-swap source tarballs
  v262–v266 present at /tmp/opencode/ls266/ (rebuild via GitHub codeload
  tarballs if cleaned).
- [open] `webfetch` to raw/API URLs can route through an expiring file-proxy
  returning 404s. Resolution: direct `curl` for GitHub/HF/ghcr API fetches.
  Used successfully at plan time for the ghcr registry enumeration.
- [open] ghcr tags/list is PAGINATED: `?n=1000` caps at 1000 tags and this repo
  has more (date tags + rootless variants). Follow the `Link: ...; rel="next"`
  header. A single-page query silently misses the `unified-vulkan-*` tags.
- [open] No docker daemon in this worktree env. Image-content questions (which
  llama.cpp rev is inside a tag, whisper-server presence) answer via registry
  manifest/config-blob GETs + upstream source grep, never `docker pull/inspect`.
- [open] `edit` tool flakes matching em-dashes in some YAML/doc files.
  Resolution: patch via shell python for those spots.
- [open] `aislop scan --changes`-style scoping finds 0 files on an unpushed
  worktree branch (no base ref). Resolution: directory-scoped `aislop scan
  charts/llama-swap` + grep evidence for changed files.
- [open] Declared-CM byte figures are Python len(str) CHARS vs UTF-8 bytes —
  compare by sha256 of the config.yaml data string, never by re-counting
  lengths. Baseline shas recorded in the plan file (gpu c3a8e3297c89...,
  gpu-ai 9f359249cee7..., default 4a8934101e35 — all pre-fix @90e660569).- [open] Server restarts wipe /tmp/opencode (helm + venvs gone mid-ticket). Recipe
  (re-run after any wipe): curl get.helm.sh/helm-v3.16.4-linux-amd64.tar.gz | tar xz
  -C /tmp/opencode && mv /tmp/opencode/linux-amd64/helm /tmp/opencode/bin/helm;
  helm dependency update charts/llama-swap (app-template tgz also gone). Suite
  ENV-SKIPS ~91 cases without helm - a post-wipe run is NOT a valid bar; always
  rebuild before reading counts.
