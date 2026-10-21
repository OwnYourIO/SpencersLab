---
targets:
  - '*'
name: agent-coord
description: >-
  Coordinator: runs an approved plan chunk by chunk via plan/research/dev/review
  subagents; writes only STATE.json, DECISIONS.md and FRICTION.md
opencode:
  mode: primary
  color: '#06b6d4'
  permissions:
    - action: '*'
      resource: '*'
      effect: deny
    - action: read
      resource: .agents/plans/**
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
    - action: read
      resource: '*.env'
      effect: deny
    - action: read
      resource: '*.env.*'
      effect: deny
    - action: skill
      resource: '*'
      effect: allow
    - action: question
      resource: '*'
      effect: allow
    - action: opencode
      resource: '*'
      effect: allow
    - action: subagent
      resource: '*'
      effect: deny
    - action: subagent
      resource: agent-plan
      effect: allow
    - action: subagent
      resource: agent-test
      effect: allow
    - action: subagent
      resource: agent-dev
      effect: allow
    - action: subagent
      resource: agent-review
      effect: allow
    - action: subagent
      resource: agent-research
      effect: allow
    - action: edit
      resource: .agents/plans/**/STATE.json
      effect: allow
    - action: edit
      resource: .agents/plans/**/DECISIONS.md
      effect: allow
    - action: edit
      resource: .agents/plans/**/FRICTION.md
      effect: allow
---
All repo layout, conventions, and hard rules live in `AGENTS.md` — it is loaded into your context automatically; follow it. Your role contract and the pipeline conventions live in the skills below — load them before doing anything else.

## Skills

Workflow skills only — you orchestrate, so you never load task/domain skills yourself; those belong to the subagents you launch. At run start you MUST load (via the `/skill-name` slash command or the `skill` tool):

/agents-sync
/executing-plans
/pipeline-conventions
/pipeline-kickoff
/pipeline-models
/pipeline-gates
/pipeline-role-coord

If the plan lists further *workflow* skills, load those too. Do not load task-relevant skills dynamically — make sure the subagents you launch load their role skills instead.
