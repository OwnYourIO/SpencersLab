# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored
(accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures,
stale docs/plans, forced repeats or workarounds — each with the resolution actually used.
Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-21 · explore(C00) · **stale pool name in the lineage**: the launch prompt's
  `amd.com/gpu-ai-pro-r9700` and cf-143 RESEARCH R6-Q4 row 1 carry the PRE-D24 name (C07-era);
  the shipped pool is `amd.com/gpu-r9700-1` — a chunk text or test string copying the stale name
  would render a Pending-forever claim. · resolution: EXPLORE gotcha 9 + DECISIONS convention
  (canonical constant sites: bash twin `tests/notes/radiance-tp2.sh:33-35`,
  `amd_gpu_testlib.py`, `radiance_testlib.py`); plan/chunk strings all use the shipped name;
  zero-stale grep in the Commands battery. · fixed
- 2026-11-21 · explore(C00) · **readonly-tier Application-CRD gap**: ArgoCD Application
  health/sync state is not exposed through `readonly-ai-gpu-kubernetes` here — the scout could
  not read the sync truth behind the parked swap. · resolution: live reads taken from the
  Deployment specs (which is what scheduling obeys); any Application-level sync-state check is
  an owner-side leg; FRICTION-level gap accepted, no admin tier used. · ignored
- 2026-11-21 · plan(C00) · **the card's Lifecycle generation carries no Session Rename /
  Worktree Creation items** (the two leading-gate stage names are absent from this card
  generation), so the stage-gate reading is ambiguous at the top of the checklist. · resolution:
  both legs ran from the blank-default posture anyway — the worktree
  `cf-144-feat-radiance-tp2-expansion` exists and the session slug matches the derived card
  slug; stages recorded as the checked set only (STATE `stages_basis`). · fixed
- 2026-11-21 · plan(C00) · **the launch-provided claim history is secondhand**: the AI claim
  8c6e1e0c reap stamp (18:13:03.491Z) and the owner-yes takeover are recorded from the card
  comments + launch block, not from a live `pipeline_status` read in this session; the
  preload/card_details stamps were not carried verbatim into the kickoff. · resolution: STATE
  records the facts as given with `at_note` where a stamp is coord-held; dev/test sessions
  must NOT treat those nulls as evidence of a missing preload. · open
- 2026-11-21 · fold(plan) · **exact-match edits failed twice on nested-list indentation in the
  chunk files**: the read tool's `N: ` line prefix renders 4-space continuation indents of
  `- [ ]`/`- ` sub-bullets as if they carried 5, so an oldString copied from the display
  missed by one space. · resolution: verify byte-exact indentation with
  `sed -n 'A,Bp' <file> | cat -A` before re-issuing the edit; both retries then matched.
  Fold-only artifact work — no content decision affected. · ignored
- 2026-11-21 · coord(close) · **heartbeat attribution flapped three times this run**: each
  banner (or `no_claim` answer) fired while `pipeline_status` showed the SAME setId LIVE under
  this session seconds later — twice without a reap record at all, once WITH a real reap the
  claim had genuinely lost (the owner's YES then gated the card-id takeover). The two surfaces
  disagree because the in-memory registration and the lock file are separate authorities. ·
  resolution: never act on the banner alone — re-read `pipeline_status` + `pipeline_heartbeat`
  before committing anything (this run paused commits until the engine answered live both
  times). Machinery fix belongs to the pipeline-locks surface, not this repo's contracts. ·
  open (follow-up-card candidate; second documented sighting in cf-144's own final-review
  record)
