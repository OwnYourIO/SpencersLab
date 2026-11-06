---
targets:
  - '*'
name: code
description: >-
  Implementation agent for this GitOps/Helm repo. Edits charts, services,
  custom-values, and containers following repo patterns, validates with helm
  lint/template, and lets ArgoCD sync. Use after a plan exists or for small,
  well-scoped changes.
opencode:
  mode: all
  color: '#f59e0b'
  permissions:
    - action: read
      resource: '*'
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
    - action: todowrite
      resource: '*'
      effect: allow
    - action: todoread
      resource: '*'
      effect: allow
    - action: edit
      resource: '*'
      effect: ask
    - action: edit
      resource: .github/**
      effect: ask
    - action: edit
      resource: charts/**
      effect: allow
    - action: edit
      resource: services/**
      effect: allow
    - action: edit
      resource: custom-values/**
      effect: allow
    - action: edit
      resource: containers/**
      effect: allow
    - action: edit
      resource: skills/**
      effect: allow
    - action: edit
      resource: .agents/plans/**
      effect: allow
    - action: shell
      resource: '*'
      effect: ask
    - action: shell
      resource: git status*
      effect: allow
    - action: shell
      resource: git log*
      effect: allow
    - action: shell
      resource: git diff*
      effect: allow
    # Git writes (cf-106 OQ-10): a human supervises this role directly, so it
    # stages, commits and branches its own work. The pipeline implementer family
    # keeps add/commit denied — the coordinator stays its sole committer.
    - action: shell
      resource: git add*
      effect: allow
    - action: shell
      resource: git commit*
      effect: allow
    - action: shell
      resource: git checkout*
      effect: allow
    - action: shell
      resource: git switch*
      effect: allow
    - action: shell
      resource: git branch*
      effect: allow
    # main-advancing deny floor — narrower than the coord family's, not its
    # mirror: it enumerates the checkout/switch forms, update-ref, symbolic-ref,
    # branch on main with -f/--force/-d/-D/-m/-M, worktree add, pull, merge and
    # config alias. Unenumerated spellings still answer allow through the
    # `git branch*` row above (read through the matcher 2026-11-04: -B/-C/-c and
    # --move on main are allow here; -C/-c are deny on the coord family, which
    # also carries the broad `git * --force*` rows this floor lacks). Never move
    # main, whichever way the rows read. Order is load-bearing — last match wins,
    # so the floor sits AFTER the allows it closes, and each in-command rule
    # ships as a prefix form plus a `git *` twin because the matcher anchors at
    # the command start.
    - action: shell
      resource: git checkout main*
      effect: deny
    - action: shell
      resource: git * checkout main*
      effect: deny
    - action: shell
      resource: git checkout * main*
      effect: deny
    - action: shell
      resource: git * checkout * main*
      effect: deny
    - action: shell
      resource: git switch main*
      effect: deny
    - action: shell
      resource: git * switch main*
      effect: deny
    - action: shell
      resource: git switch * main*
      effect: deny
    - action: shell
      resource: git * switch * main*
      effect: deny
    - action: shell
      resource: git update-ref*
      effect: deny
    - action: shell
      resource: git * update-ref*
      effect: deny
    - action: shell
      resource: git symbolic-ref*
      effect: deny
    - action: shell
      resource: git * symbolic-ref*
      effect: deny
    - action: shell
      resource: git branch -f main*
      effect: deny
    - action: shell
      resource: git * branch -f main*
      effect: deny
    - action: shell
      resource: git branch --force main*
      effect: deny
    - action: shell
      resource: git * branch --force main*
      effect: deny
    - action: shell
      resource: git branch -d main*
      effect: deny
    - action: shell
      resource: git branch -d * main*
      effect: deny
    - action: shell
      resource: git * branch -d main*
      effect: deny
    - action: shell
      resource: git branch -D main*
      effect: deny
    - action: shell
      resource: git branch -D * main*
      effect: deny
    - action: shell
      resource: git * branch -D main*
      effect: deny
    - action: shell
      resource: git branch -m main*
      effect: deny
    - action: shell
      resource: git branch -m * main*
      effect: deny
    - action: shell
      resource: git * branch -m main*
      effect: deny
    - action: shell
      resource: git branch -M main*
      effect: deny
    - action: shell
      resource: git branch -M * main*
      effect: deny
    - action: shell
      resource: git * branch -M main*
      effect: deny
    - action: shell
      resource: git worktree add * main*
      effect: deny
    - action: shell
      resource: git * worktree add * main*
      effect: deny
    - action: shell
      resource: git pull*
      effect: deny
    - action: shell
      resource: git * pull*
      effect: deny
    # merge stays wholly denied here: unlike the coord family this role owns no
    # landing, so it needs no `git merge main`-into-work-branch exception.
    - action: shell
      resource: git merge *
      effect: deny
    - action: shell
      resource: git * merge *
      effect: deny
    - action: shell
      resource: git config alias*
      effect: deny
    - action: shell
      resource: git * config alias*
      effect: deny
    # The floor's exceptions: creating a branch FROM main is not main-advancing,
    # so the -b/-B/-c/-C forms re-allow after the floor.
    - action: shell
      resource: git checkout -b * main*
      effect: allow
    - action: shell
      resource: git * checkout -b * main*
      effect: allow
    - action: shell
      resource: git checkout -B * main*
      effect: allow
    - action: shell
      resource: git * checkout -B * main*
      effect: allow
    - action: shell
      resource: git switch -c * main*
      effect: allow
    - action: shell
      resource: git * switch -c * main*
      effect: allow
    - action: shell
      resource: git switch -C * main*
      effect: allow
    - action: shell
      resource: git * switch -C * main*
      effect: allow
    - action: shell
      resource: git worktree add -b * main*
      effect: allow
    - action: shell
      resource: git * worktree add -b * main*
      effect: allow
    # Push is NOT this role's route: `ask` keeps an interactive human as the only
    # one who can authorize an ad-hoc push, while an unattended run is blocked
    # (ask resolves to deny there). The main-leg and force forms are denied
    # outright, after the ask row so last-match-wins keeps them closed. The
    # `git *`-prefixed deny twins match the substring `push` anywhere in the
    # command string — paths and commit messages included, so `git commit -m
    # "fix push to main"` denies; keep that word out of git strings on a
    # ticket branch.
    - action: shell
      resource: git push*
      effect: ask
    - action: shell
      resource: git push*main*
      effect: deny
    - action: shell
      resource: git * push*main*
      effect: deny
    - action: shell
      resource: git push --force*
      effect: deny
    - action: shell
      resource: git push -f*
      effect: deny
    - action: shell
      resource: git push * --force*
      effect: deny
    - action: shell
      resource: git push * -f*
      effect: deny
    - action: shell
      resource: git * push --force*
      effect: deny
    - action: shell
      resource: git * push -f*
      effect: deny
    - action: shell
      resource: git * push * --force*
      effect: deny
    - action: shell
      resource: git * push * -f*
      effect: deny
    - action: shell
      resource: ls *
      effect: allow
    - action: shell
      resource: helm lint*
      effect: allow
    - action: shell
      resource: helm template*
      effect: allow
      # Workspace isolation surface: a run with no worktree can mint one and
      # move its session in via the opencode MCP tools (the native-tool path
      # executing-plans / using-git-worktrees expect). No execute row: this
      # role has no deny baseline, so Code Mode falls through to the global
      # ask — the interactive agent approves once per run.
    - action: opencode_worktree_create
      resource: '*'
      effect: allow
    - action: opencode_worktree_list
      resource: '*'
      effect: allow
    - action: opencode_session_move
      resource: '*'
      effect: allow
---
All repo layout, conventions, and hard rules live in `AGENTS.md` — read it first and follow it. Your role contract lives in the skills below — load it before doing anything else.

## Skills

The first thing you MUST always do is load the skills listed in the plan. If no skills are in your plan, evaluate your skills and load the top 5 relevant skills.

Before any other work, you MUST load these skills with the `/skill-name` slash command (or the `skill` tool) — no exceptions, not for "trivial" work:

/executing-plans
/role-code

Then evaluate the task against the skills available to you and load 3 more relevant skills dynamically at runtime, the same way (`/skill-name`).
