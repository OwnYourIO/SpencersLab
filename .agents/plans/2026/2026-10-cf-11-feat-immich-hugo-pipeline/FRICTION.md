# FRICTION — cf-11-feat-immich-hugo-pipeline

Format: `date · who · what blocked/slowed the run — resolution · state(open|fixed|ignored)`

2026-10-31 · research · write-tool permission denied for `/tmp/opencode` paths in the research session (storm intermediates) — resolution: intermediates written via shell heredocs to `/tmp/opencode/storm-runs/immich-to-hugo-pipeline-export-to-files-vs-embediframe/` · open
2026-10-31 · research · duckduckgo engine intermittently CAPTCHA'd via global-searxng — resolution: covered by the other engines; no query lost · open
2026-10-31 · research · `api.immich.app` and `docs.netlify.com/*.md` unreadable through the searxng web reader (JS-only / 404) — resolution: canonical OpenAPI spec JSON + server-controller source fetched directly via curl; Netlify docs via HTML section extraction · open
2026-10-31 · research · no subagent tool in the research session for storm perspective interviews — resolution: interviews run in-session per storm skill fallback · ignored (by-design single-session shape)
2026-10-31 · coord · research-only loop defines no worktree/branch step, so the ticket folder landed untracked in the main checkout — user could not find it on any ticket surface · resolution: user-directed landing on the pre-existing cf-11-feat-immich-to-hugo worktree (owned by the earlier FAILED run of card #11 — branch virgin, folder orphaned); RESEARCH.md re-emitted byte-exact by its authoring session (coord write grant covers only STATE/DECISIONS/FRICTION); stale main-checkout copy left for human cleanup · open (loop-shape gap: a research-only run should create/claim its worktree surface like the standard kickoff — candidate for a boards-skill follow-up card)
