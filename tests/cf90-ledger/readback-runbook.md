# C07 read-back runbook — deferred-cards ledger on AI-Dev (cf-90)

Executor: the COORDINATOR (board writes are the coord's surface — boards-skill
friction-follow-up precedent; no dev subagent, no repo files beyond the
coord-written DECISIONS.md id table). Timing: right after the post-research
round and BEFORE the agent-test session for the other chunks (the card's own
rule). This runbook is what agent-review executes as C07's "tests" — a live
board read-back, the only cf-90 surface that touches the board at all, and
read-only besides (the creations themselves are the chunk's action; the
read-back never mutates).

## Preconditions (stop-before-acting checks)

1. C03's boards-skill Follow-up cards protocol is landed (the run follows it:
   destination, timing, parent-label rule).
2. Resolve the destination live: `list_lists` on AI-Dev → the **Inbox** list
   id in the **Backlog** swimlane. It postdates the prefetch board-context
   block — NEVER use a cached/prefetched id (plan Risks). If Inbox is absent:
   STOP and report — list creation belongs to /wekan-board-provision (C01),
   never to this chunk.
3. Re-list the cite-target lists (`Not Started`, `Test`, `Review`,
   Backlog/CICD) and `get_card` each ledger candidate BEFORE citing — the
   by-list projection omits cardNumber/custom fields/labels, and titles
   drift (pickup rule 3). Existing cards are CITE-ONLY: no move, no edit,
   no comment on them (AC2).

## Creation contract (per CREATE entry; plan appendix is the content authority)

- Title `[cf-90 ledger L<n>] <card title>`; destination Inbox.
- Body carries the THREE required lines (AC3):
  1. the appendix content verbatim-ish;
  2. `Parent card: #90 agent-board-coord improvements`;
  3. `Parent labels (apply once a label tool lands — see the label-tool
     card): <#90's labels at creation time, MINUS Research>` — the
     deployed surface cannot set labels (F5), so inheritance is a body
     note citing the label-tool ledger card; the Research label NEVER
     carries (the research-only flow shape must not leak).
- Five standard checklists arrive via the board's createCard rule — NEVER
  `add_checklist` (it duplicates them; proven on cards #64–67). Checklist
  answers via `create_card` `default_checked` when the deployed build
  accepts it — probe once on the FIRST card, then use the working shape for
  the rest; fallback is `toggle_checklist_item`. Services per entry per the
  plan appendix (the appendix is the card-content authority — C07's Tasks
  line conflicts on L4/L7, appendix `dev` vs Tasks `agent context`; the
  coord rules this BEFORE creating those cards and records the ruling in
  the ledger comment). Type per entry (L1–L3 `chore`, L4 `dep`,
  L7/L10–L12 `feat`), Model(s) default `Qwen Flash`.
- L7/L10/L11/L12 bodies add the ledger cross-references (L8/L9) and the
  -pr-flow pointer (pipeline-push-pr's assumed-flow section). Wave order
  runs C07 FIRST in wave 2 (the card's timing rule), so C05 has NOT landed
  at execution time: cite the ledger cards by number and point at the plan
  appendix, never at a section that does not exist yet — record the
  forward-reference as a deviation.
- If `create_card` times out mid-write: verify board state FIRST (the
  wekan-mcp failure-mode playbook), never repost blindly.
- AFTER all creations: exactly ONE `add_comment` on card #90 — the full
  ledger table (L1..L12 → created id / cited id). That comment is AC4's
  audit trail and AC5's RESULT source.

## Read-back checks (what Review runs, in order)

1. `list_cards_in_list` on Inbox: every expected title (the eight CREATE
   entries, `grep '^[-*] \*\*L[0-9]+ \(CREATE\)'` of the plan appendix)
   present EXACTLY ONCE; no duplicates of any CITE-list card anywhere on
   the board scan-back.
2. `get_card` the FIRST and LAST created card (samples): body carries the
   three required lines; the parent-labels line lacks Research; the
   L7/L10/L11/L12 samples carry the ledger cross-references.
3. `list_checklists` + `get_checklist` on the samples: the five standard
   checklists exist (Services/Type/Model(s)/Lifecycle/Human in the Loop)
   with the chunk's answers CHECKED (Services per entry, Type per entry,
   Model(s) = Qwen Flash).
4. `list_comments` on card #90: the single ledger comment exists and its
   id table covers all twelve rows (created ids for the eight CREATEs,
   cited ids for L5/L6/L8/L9).
5. CITE-list cards (L5×2, L6, L8, L9×2): untouched — no move (still in
   their original list), no edit, no new comment. Compare against the
   precondition re-list.

## Reporting

RESULT `commands_run` lists each MCP read with its verdict; the id table
rides RESULT (AC5) and the coord writes it into DECISIONS.md under the
chunk line after the run. A found-already-carded CREATE entry is CITED
instead, with the deviation recorded (AC1's recomputation rule).
