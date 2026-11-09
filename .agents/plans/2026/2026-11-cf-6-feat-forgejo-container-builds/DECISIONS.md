# DECISIONS — cf-6 feat forgejo-container-builds

Append-only log of decisions, rejected alternatives, conventions. Coord writes.

## 2026-11-09 — Flash+Local routes to the q4 Strata quant (owner ruling, detour)

- Ruling (in-session, 2026-11-09): subagents resolved from `Qwen Flash` +
  `Local` must run `gpu-ai/qwen3.8-flash-next-strata-q4` (UD-Q4_K_XL), not
  the IQ3_S `gpu-ai/qwen3.8-flash-next-strata`.
- Lands as: re-route of the three rule sources (`pipeline-models` combo
  bullet + favorited row, `pipeline-kickoff` derivation, `boards` kickoff
  combo clause), `rulesync generate`, AND the same-commit re-pin of
  `tests/pipeline-models/surface.sh` the `test_c05_default_route_flip...`
  guard demands. `qwen3.8-flash-next-q3` stays the documented explicit-request
  alternate; `-strata` (IQ3_S) is demoted to non-route (never agent-routable
  prose on the kickoff/boards pairs); `-strix` posture unchanged.
- The commit rode THIS ticket branch (the owner directed the detour mid-run);
  kept as its own single-purpose commit, not mixed with cf-6 chunks.
- Pre-existing reds on the base commit, NOT touched (owner eyes, separate
  work): `test_c05_hygiene_ids_registered`,
  `test_c05_no_phantom_catalog_entries`,
  `test_c05_ornith_strata_id_present_only_where_it_should_be`, and
  `pipeline-locks-tick.test.ts`'s loop-file model byte —
  `.agents/loops/pipeline-worker.md` ships
  `model: gpu-ai/qwen3.8-flash-next-strata-q4` while the test pins the
  cf-106 OQ-14 literal `gpu-ai/qwen3.8-27b-q4` (test comment: the literal
  moves only by a fresh owner ruling — loop-file-vs-test needs the owner's
  call, loop-file sync is OpenChamber-owned).
- Rejected alternative: widening the flip to the loop-file/runner literal —
  out of scope of the ruling (subagent routing only), and scheduler/model
  literals move only by an explicit owner ruling.
