---
name: boards
description: >-
  WeKan AI-Dev board flow for the agent-board-coord pipeline variant — card
  pickup (a given card id, else highest-sorted Rework, else Not Started), card
  lifecycle (claim on pickup, progress comments, final Ready for Review;
  Finished stays human-owned), and the batched question protocol that records
  every planning-phase question and asks the whole list in one round before the
  plan is finalized. MUST-loaded by agent-board-coord at run start; load it
  anywhere else when working the WeKan AI-Dev board card flow.
---
# Boards

Board-driven intake and exit for `agent-board-coord`. The pipeline machinery (plan folders, chunks, gates, RESULT handoffs) is unchanged from `pipeline-conventions` and `pipeline-role-coord`; this skill defines only the board surface — where work comes from, how a card moves, and how questions reach the user.

## Board facts

- Instance: `https://wekan.spencerslab.com`; board **AI-Dev**; swimlane **In Process**.
- Lists: **Not Started**, **Executing**, **Ready for Review**, **Rework**, **Finished**.
- Access: the `dev-boards` MCP server — the wekan-mcp tool set (`get_card`, `list_cards_in_list`, `move_card`, `add_comment`, `list_comments`, …), write-capable; it is the agent's single MCP permission.
- Tool behavior unclear → load the `wekan-api` skill for WeKan API semantics (on demand, never at run start).
- The board structure (board, swimlane, lists, bot membership) is a user-owned prerequisite; if it is missing the flow sees an empty board and stops cleanly per Card pickup.

## Card pickup

1. Card id given in the launch → `get_card` it; that card is the request.
2. Otherwise `list_cards_in_list` on **Rework** → pick the highest-sorted card (it is rework).
3. **Rework** empty → highest-sorted card from **Not Started**.
4. Both empty → report no work and stop cleanly: RESULT `status: NEEDS_INFO`, `open_questions: no cards on the AI-Dev board`. Never fabricate a request.

The card description is the request. Claim the card per the Card lifecycle before kickoff.

## Card lifecycle

Confirmed (plan OQ2): **Ready for Review** is the agent's final destination; **Finished** is human-owned.

- **Pickup** → `move_card` to **Executing** + `add_comment` claiming the card: session, model, plan folder path.
- **Plan approved** (after the question round) → `add_comment` that the plan is approved (plan path, worktree/branch).
- **Each chunk done** → `add_comment` with the chunk status (chunk id, dev/review verdict, commit).
- **All chunks done + final whole-plan review passed** → `move_card` to **Ready for Review** + summary comment: branch, commit range, validation results, plan path.
- **Never** `move_card` to **Finished** — a human moves Ready for Review → **Finished** (accept) or → **Rework** (send back).
- Card picked from **Rework**: read its full comment history (`list_comments`) first; the comments are the rework context.

## Batched question protocol

Until the plan is finalized, no one in this flow calls the `question` tool on the user:

- `agent-board-coord` AND every agent it launches for research/planning work MUST NOT ask the user questions.
- Every question is recorded in the plan file's **Open questions** section — the question, the best-guess answer taken, and its impact — and work continues on the best guess.
- When the plan is about to be written/finalized, `agent-plan` returns the accumulated questions: RESULT `open_questions` plus the plan's Open questions section.
- `agent-board-coord` then asks the user the ENTIRE built-up list in ONE `question` call — multiple questions, each with the recommended (best-guess) answer first — and re-launches the plan session with the answers to rework the plan before final approval.

This REPLACES per-question escalation during the planning phase: questions accumulate, they do not block. (`question` stays allowed in every agent's permissions — the protocol decides when the one batched round happens, it does not revoke the tool.)

## Launch prompt to agent-plan

When launching `agent-plan`, agent-board-coord MUST include this extra prompt text (in addition to the standard launch prompt):

> Card context: <card title, card description, and card comments> — the card description is the request; the feature folder is <path>.
> No-questions rule: until this plan is finalized you must NOT call the `question` tool. Record every question you would ask — question, the best-guess answer you take, and its impact — in the plan's Open questions section, and continue the work on the best guess.
> Question return: when the plan is about to be written/finalized, return ALL accumulated questions — in RESULT `open_questions` and in the plan's Open questions section. They go to the user in one batched question round, and the plan session is re-launched with the answers before final approval.
