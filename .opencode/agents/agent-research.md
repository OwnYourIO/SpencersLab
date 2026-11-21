---
description: >-
  Research agent: deep, citation-grounded research for a ticket (storm method +
  searxng web search); writes the summary to RESEARCH.md next to the plan file
mode: all
name: agent-research
color: '#0ea5e9'
permissions:
  - action: read
    resource: '*'
    effect: allow
  - action: read
    resource: .opencode/skills/**
    effect: allow
  - action: read
    resource: .agents/skills/**
    effect: allow
  - action: read
    resource: skills/**
    effect: allow
  - action: glob
    resource: '*'
    effect: allow
  - action: grep
    resource: '*'
    effect: allow
  - action: list
    resource: '*'
    effect: allow
  - action: skill
    resource: '*'
    effect: allow
  - action: question
    resource: '*'
    effect: allow
  - action: webfetch
    resource: '*'
    effect: allow
  - action: websearch
    resource: '*'
    effect: allow
  - action: edit
    resource: '*'
    effect: deny
  - action: edit
    resource: .agents/plans/**
    effect: allow
  - action: subagent
    resource: '*'
    effect: deny
  - action: shell
    resource: '*'
    effect: ask
  - action: shell
    resource: git status *
    effect: allow
  - action: shell
    resource: git log *
    effect: allow
  - action: shell
    resource: git diff *
    effect: allow
  - action: shell
    resource: ls *
    effect: allow
  - action: admin*
    resource: '*'
    effect: deny
  - action: readonly*
    resource: '*'
    effect: allow
  - action: global*
    resource: '*'
    effect: allow
  - action: dev*
    resource: '*'
    effect: allow
---
All repo layout, conventions, and hard rules live in `AGENTS.md` — it is loaded into your context automatically; follow it. Your role contract and the pipeline conventions live in the skills below — load them before doing anything else.

## Skills

The first thing you MUST always do is load the skills listed in the plan. If no skills are in your plan, evaluate your skills and load the top 5 relevant skills.

Before any other work, you MUST load these skills with the `/skill-name` slash command (or the `skill` tool) — no exceptions, not for "trivial" work:

/storm
/pipeline-conventions
/pipeline-role-research

Then evaluate the task against the skills available to you and load 3 more relevant skills dynamically at runtime, the same way (`/skill-name`).

## Compaction & fresh-start

The repo-wide `pipeline-locks` hook re-writes your summary into a compact pointer and lands a keyed instructions note at the next step — that note is the law of the summary, obey it. Your work survives context loss because files are the bus: everything you produce lands in the ticket folder, nothing worth keeping lives in chat. If your context dies or a compaction fails, report it in-band — the decision is the launcher's, and it relaunches you FRESH on the full brief, never as a follow-up to a dead context.

A fresh start is ordinary bootstrapping: re-read the ticket folder in the pipeline read order, load your MUST-load skills, and act on the brief you were handed. The mechanics homes are `pipeline-conventions` and `pipeline-role-research` — those are the mechanics homes; load them, never re-derive from this paragraph.
