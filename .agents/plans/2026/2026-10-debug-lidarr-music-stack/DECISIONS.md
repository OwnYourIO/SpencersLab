# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Repo has no unit-test suite; "tests" = the plan's validation Commands
  (`helm lint` / `helm template` renders + grep trio checks), per AGENTS.md.
- GitOps only — ArgoCD applies everything. No `kubectl apply`, no pod exec, no
  `admin-*` MCP from this pipeline. Cluster mutation is USER-owned.

## Decisions
- 2026-10-25 plan: Resolve `charts/slskd/values.yaml` by taking HEAD
  (`tag: "0.26.2"`, initContainer + main container). Rejected: the stashed
  `0.26.0` side — main bumped both tags to 0.26.2 via Renovate (`a60d11a0a`)
  after the IDE stash (`2026-10-25T22:31Z`) was taken; the stash is byte-identical
  to HEAD for the other 6 files it touched, so it carries no unique work. Taking
  0.26.0 would hand-revert a Renovate pin (forbidden). No merge/rebase is run:
  there is no `MERGE_HEAD` — this was a stash-apply, and branch tip == main.
- 2026-10-25 plan: Fix lidarr by directory-mounting the whole `betanin` Secret
  at `/betanin-secrets` (no `subPath`) and reading the key at
  `/betanin-secrets/BETANIN_API_KEY` in the ConfigMap script. Rejected: (a) just
  recreating the pod — the StartError is deterministic and root-caused to the
  file-subPath mechanism, not a transient; (b) making the Secret non-optional —
  still a file subPath into `/config`, and an absent Secret would then block the
  whole pod; (c) imperative PVC cleanup only — not GitOps and doesn't survive
  the next Secret gap. Evidence: every exit is StartError 128 "not a directory"
  on the `betanin-secret` subPath mount; ES `betanin` reached Ready at
  2026-10-25T19:48Z yet the pod recreated 21:06Z (14 restarts since) fails
  identically — the collision is persisted placeholder state in the live
  `/config` PVC, so no pod-level retry can clear it while a file subPath is used.
- 2026-10-25 plan: Split into 2 chunks (C01 conflict-resolution + one commit for
  the lidarr fix in C02). The kickoff asked for both a lidarr fix and a
  conflict-resolution chunk; the two share no files and merge independently, so
  per role-plan sizing (S tasks, distinct outcomes) they are separate chunks with
  C02 depending on C01 only to guarantee a clean index before committing.
- 2026-10-25 plan: Scope = get lidarr healthy via GitOps + resolve the conflict.
  Out of scope: all Lidarr UI/plugin configuration (music-stack plan Phase 8,
  USER steps), other music-stack services (healthy), chart version bumps (CI),
  pod-exec verification (no MCP tier grants it), and any second failure layer
  (e.g. LSIO `/ping` probe incompatibility) which becomes a new ticket.

## Deferred
- Post-merge cluster verification (app `media` → Healthy, pod 1/1, restarts
  stable) and the conditional PVC `/config/secrets` orphan-cleanup: USER steps
  + readonly-MCP checks, tracked in the plan file, not chunk tests.

## Coord rulings on agent-test open questions (2026-10-25)
- Test-file commits: `tests/services/media-{slskd-conflict,lidarr-betanin-mount}.sh` stay UNTRACKED for the whole run — c5 pins `main..HEAD` non-merge commits to exactly the two in-scope fix files, so committing tests mid-run would fail the suite by construction. After the final whole-plan review returns APPROVED, one agent-dev commit lands them (post-review commit #2); the user's PR then carries fix + tests. Not user-facing until then.
- Stash ordering: review/dev run both suites while `stash@{0}` and `stash@{1}` still exist (C01 t3 requires it). The USER step "drop stash@{0}" happens only AFTER this pipeline reports done — reminder included in the final report.
- Main advanced (87a01399c) after planning: agent-dev for C02 must `git merge main` into `add-music-to-media` BEFORE the fix commit (AGENTS.md-sanctioned; merge is plumbing, excluded by c5's `--no-merges`). C01 dev does not merge — keep the conflict-resolution commit minimal and clean.

## Deferred (from final whole-plan review, 2026-10-25)
- Final-review non-blocking observation: the whole-Secret directory mount exposes betanin's other keys (config.toml, beets-config.yaml) to the lidarr pod. Same low-sensitivity Secret already runs in the namespace; if least-visibility ever matters, narrow with a volume `items:` projection in a follow-up ticket. Not re-litigating the approved C02 choice.
