# RESEARCH — cf-6 run -2 (card 6 owner rework: multi-commit detection round)

Written by `agent-research` 2026-11-13 (workspace clock), for run -2 of card 6. Scope: the
owner's verbatim ask — *"Can you double check this? Most of the things that need to get built
aren't the top commit, and I'm worried `fetch-depth: 0` will mask those changes. A round of
research on how others address this is needed"* — pointed at `.forgejo/workflows/containers-build.yaml`
L88. Builds on this folder's `EXPLORE.md` (run -2 scout — its measurements are taken as given and
relied on by number below, keyed **[X-2]**), run -1's `RESEARCH.md` R1/R2 and `EXPLORE.md` §7
(**[R-1]**), run 0's `EXPLORE.md` (**[X0]**). No code was changed; no question was asked
(launch rule — open items land in §Open questions with best guesses).

Evidence keys (every claim cites one; full list with access dates at the end):

- **[F15]** Forgejo **v15.0.10** source, tag commit `17e1001d5e00e8ee3cbc1b6dd31be94ac38185f9`
  (re-verified this session via `codeberg.org/api/v1/repos/forgejo/forgejo/git/refs/tags/v15.0.10`
  → same sha, matching run -1's record; archive
  `https://codeberg.org/forgejo/forgejo/archive/v15.0.10.tar.gz` downloaded 2026-11-13,
  11,406,426 B, extracted to `/tmp/opencode/cf6r2-res/forgejo/`). Deployed images are
  `forgejo:15.0.10-rootless`, `/api/v1/version` = `15.0.10+gitea-1.22.0` **[R-1]** — Gitea-1.22-line
  provenance is checked below where relevant **[G22]**.
- **[RUN13]** Forgejo runner **v13.2.0** source (the version BOTH lab runners declare, [R-1 R1];
  archive `https://code.forgejo.org/forgejo/runner/archive/v13.2.0.tar.gz`, extracted 2026-11-13).
- **[E2E]** `code.forgejo.org/forgejo/end-to-end` @ main (conformance workflows, fetched 2026-11-13).
- **[D15]** Forgejo v15.0 Actions docs (`codeberg.org/forgejo/docs` raw `v15.0` branch,
  `docs/user/actions/reference.md`, re-fetched 2026-11-13).
- **[CKO6]** upstream `actions/checkout` ref `v6` = tag object `d23441a48e516b6c34aea4fa41551a30e30af803`
  (action.yml / README.md / src/*.ts fetched 2026-11-13) — see §6: the mirror question from [X-2 §1]
  is **resolved** (the `data.forgejo.org` mirror's `v6` is the same tag object).
- **[GHW]** docs.github.com workflow-syntax (fetched 2026-11-13, effective URL
  `.../workflows-and-actions/workflow-syntax`); **[GHE]** events-that-trigger-workflows;
  **[GHH]** webhooks/webhook-events-and-payloads; **[GHC]** contexts; **[GHCW]** workflow-commands.
- **[DOR]** dorny/paths-filter @ master README + src/{main,git}.ts; **[TJA]** tj-actions/changed-files
  @ main README + src/{commitSha,utils}.ts; **[AHM]** ahmadnassri/action-changed-files @ master
  (README + action.yml + scripts/index.sh) — the marketplace listing *"Git Changed Files"*
  v1.2.2; **[NXS]** nrwl/nx-set-shas README @ main.
- **[GSD]** git-scm.com docs: git-diff-tree, git-log, git-config (fetched 2026-11-13).
- **[G22]** go-gitea/gitea tag `v1.22.6` raw files (provenance checks).
- **[CVE]** GitHub Advisory GHSA-mrrh-fwg8-r2c3 / CVE-2025-30066 (fetched 2026-11-13).
- **[ME]** read-only measurements taken this session (clone-size battery in `/tmp/opencode/cf6r2-res/clonetests`,
  read-only git on this worktree) — numbers inline.

Confidence labels used throughout: **proven** = source read at the deployed version/commit
(and, where noted, additionally live-tested against the serving instance); **documented** = only
the vendor's own docs state it; **unverified** = plausible, not established here.

## R1 — Multi-commit changed-file detection in Forgejo/GitHub Actions: payload reality, masking shapes, and ecosystem patterns

### TL;DR (5 lines)

1. **OQ1 settled from source: yes** — a Forgejo v15.0.10 Actions `push` run always carries
   `forgejo.event.before`; it is the previous branch tip, or the all-zero OID for a branch
   creation, or (branch deletion) no run at all [F15]. No producer in the tree can make it an
   *empty* string — the "silent tip-only narrowing" shape [X-2 §3 row 2] survives only if the
   template accessor itself resolves empty (typo/regression), not from payload reality.
2. **OQ6 settled from source: the trigger's `paths:` filter walks the whole push** —
   `diff-tree --name-only --root -r <before> <head>` [F15]; GitHub's own docs state the same
   policy (two-dot for pushes, three-dot for PRs) [GHW]. Forgejo's *prose* doc line ("the pushed
   commit") is misleading, not authoritative [D15] — §Contradictions.
3. The remaining real ranges gap is the **first push**: the trigger goes fail-wide (every file
   counts, `--root`), while our detector's fallback is fail-narrow (tip-only) — designed,
   low-impact for a `branches: [main]`-triggered workflow, but asymmetric and untested [X-2 §6].
4. Ecosystem posture taxonomy (dorny / tj / ahmadnassri / nx): nobody green-lights a *silent*
   empty. Missing/invalid `before` → warn-then-tip-only (tj), loud throw (dorny), or fail-wide
   (ahmadnassri empty-tree diff). Our red-fail posture on unreachable `before` matches precedent.
5. `fetch-depth: 0` here costs a measured **~21 MiB / ~1.9 s** from this workspace against the
   canonical instance; a targeted `git fetch --depth 1 origin <before>` fill costs **~172 ms** and
   is *server-enabled* (`uploadpack.allowAnySHA1InWant=true`) [F15][ME] — but removing depth-0
   re-breaks multi-commit detection [X-2 §4].

---

### 1. OQ1 — does a Forgejo v15 Actions `push` event carry `before`? **PROVEN: yes, always, and it is the previous tip (or all-zero).**

The full chain, every link read at tag `v15.0.10`:

1. **Wire entry.** The post-receive hook parses git's pkt-line
   `<old-oid> <new-oid> <ref>` records into `HookOptions.OldCommitIDs[i]` verbatim —
   *"note: … `t := strings.SplitN(string(rs.Data), " ", 3)` …
   `hookOptions.OldCommitIDs = append(..., t[0])`"* [F15 `cmd/hook.go` L570-586]. Per git's
   receive protocol, for a newly created ref the old-oid is the all-zero OID; it is a full OID
   otherwise — never an empty string.
2. **Options object.** `HookPostReceive` copies `opts.OldCommitIDs[i]` into
   `repo_module.PushUpdateOptions.OldCommitID` per branch/tag ref [F15
   `routers/private/hook_post_receive.go` L56-80].
3. **Actions notifier.** `actionsNotifier.PushCommits` builds the payload
   `api.PushPayload{Ref: …, Before: opts.OldCommitID, After: opts.NewCommitID, …}` and notifies
   [F15 `services/actions/notifier.go` L582-596]; `SyncPushCommits` (mirror-sourced pushes) is
   the same with `Before: opts.OldCommitID` (L652-667). **A push whose `NewCommitID` is empty**
   (branch deletion) returns before any notify [L560-563] — deletion pushes never create a run.
   The mirror path only ever passes either a real old OID or
   `objectFormat.EmptyObjectID().String()` (creation) [F15 `services/mirror/mirror_pull.go`
   L567-571, L613-617]. **Exhaustive-producer sweep (proven):** every construction of
   `PushUpdateOptions` in the tree — hook post-receive, mirror-sync, branch create/delete
   (`routers/web/repo/branch.go` L152-157, `services/repository/branch.go` L483-488), release
   create/delete (`services/release/release.go` L103-107, L408-412) — sets `OldCommitID` to a
   real commit ID or the all-zero `EmptyObjectID().String()`; no producer sets `""`.
4. **Struct shape.** `PushPayload` serializes `Before string \`json:"before"\`` (+ `After`,
   `Ref`, `Commits[]`, `TotalCommits`, `HeadCommit`) [F15 `modules/structs/hook.go` L258-269].
   Go marshals the struct with all fields — a push payload therefore always contains a `before`
   key with a non-empty value (a 40-char sha or 40+ zeros / 64 for sha256 repos).
5. **Storage.** `handleWorkflows` does `p, _ := json.Marshal(input.Payload)` and writes
   `EventPayload: string(p)` on the `ActionRun` [F15 `services/actions/notifier_helper.go`
   L363-381].
6. **Context exposure.** `generateGiteaContextForRun` starts with
   `event := map[string]any{…}; json.Unmarshal([]byte(run.EventPayload), &event)` and sets
   `GithubContext.Event = event`, with the comment *"for a workflow run triggered by the push
   event, this object contains the contents of the push webhook payload"* [F15
   `services/actions/context.go` L22-23, L53]. `forgejo`/`github`/`forge` are aliases of this one
   context map [D15; X0 §4].

**`forgejo.sha` vs `forgejo.event.before` availability differs as designed:** `forgejo.sha` =
`run.CommitSHA` — for push it is the head commit the notifier supplied (`WithCommit(headCommit)`
— the push protocol's `commits.HeadCommit.Sha1`), falling back to a ref-tip re-discovery when
absent [F15 `notifier.go` L577-584; `notifier_helper.go` L222-227 — with the upstream comment
warning that re-discovery "might end up with a newer commit" under racing pushes]. `before`
exists **only** on push payloads (not PR/dispatch). `event_path` is documented and points at the
same payload file on the runner [D15 L1286, L1333].

**What an empty value would mean.** Our detector's L38 (`[ -z "${before//[0]/}" ]`) treats
empty ≙ all-zero ≙ first-push, and falls to `HEAD^..HEAD` — the shape [X-2 §3 row 2] correctly
names as dangerous *if it could fire mid-life*. Per this chain, under git-push and mirror-sync
events on v15.0.10 it cannot fire unless the template expression itself resolves empty (accessor
typo, a runner-side context regression, or an event kind without `before` routed into the push
arm — the detector's `event` default is `push` [X-2 §2]). **Verdict: OQ1 = proven; the masking
risk survives only as a defensive-coding question (separate `""` from all-zero — §Options A5),
not a payload-reality question.**

**One-source residual, stated honestly:** the chain is proven at source; it has **not** been
exercised live here because no `containers-build.yaml` run has ever executed on either instance
[X-2 §8]. The decisive one-dispatch probe, if the owner wants live confirmation (owner leg, not
run here): add a temporary job to any throwaway workflow on a scratch repo, or reuse the
documented debug recipe — a step printing `cat <<'EOF' ${{ toJSON(forgejo) }} EOF` [D15
L1353-1373] — push ≥2 commits touching `containers/` to a branch, and read
`"before": "<pre-push tip>"` out of the dump. Forgejo's own conformance pushes a `toJSON(github)`
dump on every `push` run of `example-push` in the same shape [E2E
`actions/example-push/.forgejo/workflows/test.yml`].

### 2. OQ6 — does `on.push.paths: ['containers/**']` filter over the whole range or only the tip? **PROVEN: whole range; PR side merge-base; tag pushes exempt.**

When a push lands, the server decides which workflows to trigger in
`modules/actions/workflows.go`. At tag `v15.0.10`:

- `detectMatched` routes push events to `matchPushEvent(commit, payload, evt)` [F15 L231-252].
- The `paths` case: `filesChanged, err := commit.GetFilesChangedSinceCommit(pushPayload.Before)`
  — *the payload's `before`, not `commit^`* — then the pattern list is matched against those
  files [F15 L361-377]; `paths-ignore` mirrors it [L378-395]. Tag refs skip the path test
  (`if refName.IsTag() { matchTimes++; break }`), exactly matching GitHub's documented
  "Path filters are not evaluated for pushes of tags" [F15 L362-364; GHW].
- `GetFilesChangedSinceCommit(past)` = `repo.GetFilesChangedBetween(past, c.ID)` [F15
  `modules/git/commit.go` L303-306], which runs
  `git diff-tree --name-only --root --no-commit-id -r -z <base> <head>` — two endpoints — and
  special-cases `base == emptyObjectID` (the all-zero sentinel) down to `git diff-tree … <head>`
  with `--root`, which git defines as *"the initial commit will be shown as a big creation event.
  This is equivalent to a diff against the NULL tree"* → **every file in the pushed tree is
  "changed"** on a new-branch push [F15 `modules/git/repo_compare.go` L322-344; GSD
  git-diff-tree].
- On git error (unreachable `before` — possible only if the object was GC'd between update and
  match, or a corrupt sha): `log.Error` and `matchTimes` is *not* incremented → the workflow is
  **not triggered** — a fail-closed trigger decision [F15 workflows.go L366-368].
- **PR side:** `matchPullRequestEvent`'s `paths` case computes
  `headCommit.GetFilesChangedSinceCommit(prPayload.PullRequest.MergeBase)` — merge-base→head,
  i.e. three-dot semantics [F15 L520-545]. Default activity types: only `opened`, `reopened`,
  `synchronized` trigger [F15 L449-455].
- **Gitea-lineage provenance:** Gitea v1.22.6 has the identical lines
  (`GetFilesChangedSinceCommit(pushPayload.Before)` at workflows.go L314/L327; the same
  `diff-tree --name-only --root --no-commit-id -r -z` at repo_compare.go L290) [G22] — this
  behavior is inherited from the 1.22 line, not invented in Forgejo v15.

GitHub's current docs state the same policy for their own triggers: *"The filter determines if a
workflow should run by evaluating the changed files and running them against the
`paths-ignore` or `paths` list. **If there are no files changed, the workflow will not run.**
GitHub generates the list of changed files using **two-dot diffs for pushes** and **three-dot
diffs for pull requests**: … Pushes to existing branches: A two-dot diff compares the head and
base SHAs directly … Pushes to new branches: A two-dot diff against the parent of the ancestor
of the deepest commit pushed"* [GHW].

**Consequence for the launch's worry** ("a run dispatched for changes it will not rebuild —
silent no-op green run"): on **push**, trigger range and our detector range are computed from
the same `before..sha` endpoints — a container touched by any commit in the push both triggers
and is detected (proved behaviourally for middle commits by [X-2 §2] live probe). The two
genuine asymmetries are:
1. **First push** (all-zero `before`): trigger = whole tree (fail-wide), detector = tip-only
   (fail-narrow). A new-branch push whose *older* commits touched `containers/**` triggers a run
   that rebuilds nothing → green no-op. With our `push.branches: [main]` the only live shape is
   delete-then-recreate of `main` — remote-certain, near-zero practical — but it is exactly the
   class the owner fears, one layer up. (Also: on a repo-creation push of the whole `containers/`
   tree to `main`, the detector would build only the tip commit's containers — the rest ride in
   as unchanged.)
2. **PR**: trigger = merge-base→head (three-dot), detector = `base.sha ↔ head.sha` two-endpoint
   (two-dot) — see §4; divergence is mostly over-detection (benign) with one rare
   under-detection shape (§4).

### 3. The masking taxonomy as others treat it (per-surface: range, missing-`before` handling, loud vs silent)

All sources below read in full at the linked versions, 2026-11-13. The payload facts they share
(`before` = previous tip; all-zero ⇒ branch creation) match what [F15] proves for Forgejo, so
these idioms transplant.

| Approach | Push range computed | PR basis | Missing `before` | Unreachable `before` | First push | Failure mode |
|---|---|---|---|---|---|---|
| **Native `on.push.paths`** (GitHub) | two-dot before↔head (documented); Forgejo: `diff-tree before head` (proven) | three-dot (documented); Forgejo: merge-base→head (proven) | n/a (server always has both) | trigger does not match → **no run created** (proven F15; GitHub "will not run", GHW) | all files (proven F15 `--root`) / parent-of-ancestor (documented GHW) | no run at all — *nothing to see in the runs list* |
| **dorny/paths-filter** v4 | same-branch pushes: `payload.before`↔head (`getChanges`, `git diff --no-renames --name-status -z base..head` [DOR git.ts L56-65, main.ts L144, L200]) | REST `pulls.listFiles` via API (no git, no checkout needed) [DOR README "Pull requests", main.ts L221 area] | `::warning 'before' field is missing in event payload - changes will be detected from last commit` then **tip-only** `git log … -n 1` [DOR main.ts L169-176, git.ts L43-54] | targeted `git fetch --depth=1 origin <base>` (then `--tags`) — if still unfetchable **`throw new Error("Could not determine what is …")`** → action red [DOR git.ts L270-281; main.ts L57-58 catch→setFailed] | `before == NULL_SHA`: default-branch push → **all files listed as added** (`git ls-files`); feature branch → merge-base vs default branch [DOR main.ts L180-196, git.ts L181-193] | **loud** (REST/git errors fail the action); the one degrade (missing-before→tip) is annotated |
| **tj-actions/changed-files** v47-era | `payload.before`↔sha two-dot, **but only when `!payload.forced`**; forced pushes never consult `before` [TJA commitSha.ts L270-277]; shallow clone → `git fetch --deepen` loop first [L112-180] | three-dot (`'...'`) preferred; base = `payload.pull_request.base.sha`, else remote-branch head [L550-557]; merge-base missing on shallow → fetch `+refs/heads/<target>` `--deepen=fetch_depth` up to N retries [L560-608]; still undiffable → **downgrade to `'..'`** [L617-626] or **throw** `Unable to determine a difference between …` [L636-645] | `before` missing/zeros → `getParentSha` = `git rev-list -n 1 HEAD^` — **tip-only fallback** [L279-285, utils L794-809]; `before` present but unverifiable (`git rev-parse --verify <sha>^{commit}` fails) → `::warning Previous commit … is not valid. Using parent commit.` → tip-only [L286-298, utils L812-845]; no parent at all → `::warning Initial commit detected no previous commit found.` → diff `previousSha==currentSha` ⇒ *all files as added* path (`initialCommit=true`) [L300-309] | deepens then throws; `before==sha` (same sha) → **`throw 'Similar commit hashes detected'`** unless `skip_same_sha` [L200-222, L650-690] | same as missing (`HEAD^` → warning → all-added) | **loud by default** (multiple `throw`s; `core.error` advisories name `fetch_depth` as the fix); degrades only with explicit `::warning` rows; README instructs `fetch-depth: 0` **or `2`** + `persist-credentials: true` [TJA README L88-91] |
| **ahmadnassri/action-changed-files** v1.2.2 ("Git Changed Files") | `before`↔HEAD via `git diff --name-only $BASE_SHA HEAD -- <pathspec>`; `BASE_SHA` read straight from the payload **file**: `jq -r '.before' "$GITHUB_EVENT_PATH"` [AHM scripts/index.sh L13, L41] | `base.sha` (env-mapped in action.yml) ↔ HEAD, same command [AHM action.yml runs; README "PR vs push"] | on push `BASE_SHA` is empty → jq fills it, so this route can't see empty; unsupported event → `::warning title=unsupported::…` + `exit 0` [L5-8] | `before` zeros/absent → `HEAD~<n>` where `n = jq '.commits | length'` — *verified* with `git rev-parse --verify --quiet`, and if the ancestor is missing (repo's own first push) → diff against the **empty tree `4b825dc642cb6eb9a060e54bf8d69288fbee4904`** ⇒ all files as changed [L15-30] | all files via empty-tree diff | **green but legible**: outputs `changed=false`, `json=[]`, and prints `❌ no files were changed` [L57-61]; README: *"when running on push events, a `fetch-depth` of 0 higher is required"* [AHM README] |
| **base-ref checkout idiom** (`git diff --name-only origin/$BASE...HEAD`) | n/a for push (PR idiom) | three-dot = merge-base→head [GSD gitrevisions; the diff `...` operator]; requires the base branch refs locally → `fetch-depth: 0` or explicit fetch of base | — | `git` exits 128 on unknown endpoint → step red (loud) — the same posture our script deliberately holds [X-2 §2, script L48-50] | new branch: merge-base fails → loud 128 unless guarded | loud (raw git); automated by dorny's `getChangesSinceMergeBase` (doubling `--deepen` fetches until merge-base found, `::warning No merge base found - … direct <commit>..<commit> comparison` degrade [DOR git.ts L88-156]) |
| **merge-commit traversal school** | neither two-dot nor tip: walk *commits*, not trees — `git log --first-parent` ("follow only the first parent commit upon seeing a merge commit" [GSD git-log]) and/or `--no-merges`, unioning each commit's files; `nx-set-shas` picks BASE = **last successful run's commit** on the main branch (API-driven; `per-commit` mode *"walks the first-parent git history before HEAD and queries the runs of each commit"*) [NXS README L129, L204-221] | PR: head↔branch-origin commit [NXS L214] | API query failure → action errors (loud) | unaffected (never uses `before`) | first run has no successful predecessor → falls back to branch default / full diff [NXS usage] | loud; the *semantic* difference vs two-dot: a fast-forward push is identical, but a merge-heavy main makes `--no-merges` first-parent walks skip what merges brought — on a linear-flow repo (ours: PR merges into main with squash/rebase possible) two-dot before↔sha equals the union of pushed commits anyway (§1, X-2 §2) |

What each pins about `before`: GitHub-trigger and ahmadnassri trust `before` as *the* base;
dorny trusts it but annotates its absence; tj *distrusts* it on forced pushes (payload `forced`
flag) and treats unverifiable `before` as a warning-then-HEAD^ degrade; Forgejo's trigger never
needs recovery idioms because the server diffs inside the repo itself (objects exist until GC,
error = no trigger); nx ignores `before` entirely and pins "last known-good" instead. Nobody in
this survey produces a **silent, unannotated** tip-only narrowing — tj's and dorny's narrowings
carry `::warning`s, ahmadnassri's empty case prints and outputs `false`, the triggers simply
don't run.

Adjacent (supply-chain, why the ecosystem now reads like this): tj-actions/changed-files was
compromised 2025-03-14→15 (retroactively retagged versions ran a memory-dumping Python script;
≤ 45.0.7, patched 46.0.1, "over 23,000 repositories", CVE-2025-30066 / GHSA-mrrh-fwg8-r2c3)
[CVE]. Its README's current examples pin by full commit SHA
(`tj-actions/changed-files@9426d40962ed… # v47.0.6`) [TJA README L284], which is the same
SHA-pinning convention run 0 recorded for this repo's action mirror [X0 §4]. Our workflow uses
zero third-party detection actions (plain shell + one mirror-pinned checkout) — the failure
class that burned 23k repos cannot burn us here, and that is a design point worth telling the
owner.

### 4. PR-side ref shape (OQ3) — Forgejo checks out the **HEAD**, not a merge commit; `base.sha`/`head.sha` exist and mean what our detector assumes

- `forgejo.ref` for a `pull_request` run: `run.Ref` ← `input.Ref` ← `pr.GetGitRefName()` =
  `refs/pull/<index>/head` [F15 `notifier_helper.go` L122; `models/issues/pull.go` L450-452].
  `forgejo.sha` = the PR head commit (`WithCommit(pull.HeadCommitID)`, opened path [F15
  `notifier.go` L387-389]; synchronize the same; merged/`closed` events use
  `WithRef(pr.MergedCommitID)` [L555-556]). The `GithubContext.Ref` field *comment* still carries
  GitHub's "pull request merge branch `refs/pull/<pr_number>/merge`" text [F15 `context.go` L59]
  — that is a copied doc-comment, contradicted by the wiring; weigh the wiring (see
  §Contradictions). Contrast **GitHub Actions proper**, where the contexts docs do state
  `github.ref` "for `pull_request` … the pull request merge branch" [GHC].
- What `actions/checkout` v6 then fetches with `fetch-depth: 0`: refspec
  `+refs/heads/*:refs/remotes/origin/*` + all tags, plus — for `refs/pull/*` event refs — an
  explicit `+<commit>:refs/remotes/pull/N` fetch [CKO6 `src/ref-helper.ts` L69-77]; `ref` defaults
  to `github.context.ref`/`.sha` for the workflow's own repository [CKO6 `src/input-helper.ts`
  L78-91]. So the checkout is detached at the PR **head commit**; base-tip objects arrive via the
  all-branches refspec (current tips), and `base.sha` resolves as an object whenever it is an
  ancestor of the current base tip — true for any branch that has not been rewritten since the PR
  event fired. (That fetch-by-SHA is exactly the capability the Forgejo server enables — §6 — and
  it was exercised successfully against the instance.)
- **Payload availability:** `event.pull_request.base.sha` / `.head.sha` exist and are populated:
  `PRBranchInfo.Sha json:"sha"` [F15 `modules/structs/pull.go` L65-71]; `Base.Sha` = the base
  branch's **current tip when the payload is generated** [F15 `services/convert/pull.go`
  L147-162]; `Head.Sha` = head-branch commit, else `refs/pull/N/head` resolution, else (AGit
  flow) the pull-ref commit [L213-260, 236-242]. Nested `event.pull_request.*` accessor chains
  are exercised by Forgejo's own conformance (`forgejo.event.pull_request.base.repo.full_name`
  and the saved-context assertions `jq -r .event.action`) [E2E `actions/example-pull-request/
  .forgejo/workflows/test.yml` + `assert-contexts.sh` L7-11]. **Caveat (proven, edge):** if the
  base branch does not exist at payload time, `Base.Sha` stays empty — our detector then dies
  `fatal: bad revision ''` exit 128 → red (measured [X-2 §3]) — the loud shape; the push-side
  empty-guard L38 has no PR counterpart by design.
- **Our PR diff semantics** (two-endpoint `base.sha head.sha`, script L33-35+L52):
  - *Over-detection* (dominant): base tip moved ahead since branch point → files changed **on
    base** appear in `diff base head` → containers only base touched are (re)built for the PR →
    wasted CI time, never a missed build. [X-2 §OQ3 best guess confirmed true; design intent
    stated by run 0 [X0 §1].]
    `build-pr` checks out the PR head and builds `containers/<n>` from the head tree —
    building an over-detected container publishes `pr-<branch>-<sha>` of the head state, which
    is exactly what a PR tag is.
  - *Under-detection* (rare, symmetric to the trigger): a container changed by the branch and
    later given **identical content** on base (cherry-picked / duplicate commit) nets zero in
    `diff base head`, while Forgejo's merge-base trigger filter still matches → dispatched run
    with `[]` → green skip. Same "dispatch-but-skip" shape as §2's first-push asymmetry;
    rarer still.
  - *Merge-base alternative*: `git merge-base $BASE_SHA $HEAD_SHA` then diff that↔head — or the
    modern one-shot `git diff --merge-base $BASE_SHA $HEAD_SHA` [GSD git-diff-tree: *"Instead of
    comparing the <tree-ish>s directly, use the merge base between the two <tree-ish>s as the
    'before' side"*] — eliminates both over-detection and the duplicate-content under-detection,
    matches the trigger's three-dot policy [F15 L520-545] and GitHub's [GHW]. Cost: needs the
    merge-base to be resolvable (history rewrite on the branch → `--merge-base` fails → red,
    where today's two-endpoint diff still succeeds), and `--merge-base` requires git ≥ 2.43
    (**unverified** which git the act-24.04 runner image ships).
- The classic traps, stated with their mechanism: merge-commit checkout (GitHub) drags base's
  new files into every PR build — Forgejo's head checkout avoids the class entirely; squash
  merge makes the *pre-squash* main tip unreachable only if main is force-moved (squash-merges
  fast-forward-append, so the push `before` stays reachable — the dangerous rewrite is
  force-push/rebase of main, §5); `--unshallow`-style needs: at depth-1 endpoints don't exist
  and everything dies red 128 [X-2 §3 rows 6-7] — the ecosystem handles this with deepen-loops
  ([TJA L112-180, 560-608], [DOR git.ts L104-136]) or by demanding `fetch-depth: 0` up front
  ([TJA README L88], [AHM README], [NXS L38]); multi-commit payloads are range-described on both
  platforms — GitHub's `commits[]` *"includes all commits that are included in the compare
  between the before commit and the after commit … maximum of 2048 commits"* [GHH], and the
  Forgejo struct likewise carries the pushed list (`Commits []*PayloadCommit` with per-commit
  `added/removed/modified` arrays [F15 `modules/structs/hook.go` L258-269 + PayloadCommit]) —
  so the *event.commits[] union* school works range-wise too, bounded by that cap (GitHub
  documents 2048; Forgejo's cap in the hook reader was **not located** this session — and one
  real quirk is **proven**: the Actions-side `PushCommits` construction never sets
  `TotalCommits` [F15 `notifier.go` L585-595 — only `SyncPushCommits` L661 does], so
  `forgejo.event.total_commits` reads `0` on ordinary pushes here. Anyone building detection on
  `total_commits`/`commits.length` — as ahmadnassri's `HEAD~n` idiom does — would compute
  `HEAD~0` on Forgejo unless they count `commits | length` instead. Note before copying that
  idiom).

### 5. `before` unreachable (force-push / rebase / squash) — the ecosystem's recovery idioms, and our red posture's precedent

Recovery idioms observed, each with its silent-partial verdict:

1. **Bounded targeted fetch of the missing endpoint**: `git fetch --depth 1 origin <before>` —
   dorny does exactly this before giving up ([DOR git.ts L270-275]); tj deepens instead
   ([TJA L112-180]); the Forgejo server has the capability switched on (§6: proven config +
   **live-tested: 172 ms for an off-history commit** [ME]). *Silent-partial risk: none* —
   either the commit arrives (diff runs correctly over the true range) or git errors → red.
2. **Warn-then-parent** (tj): invalid `before` → `::warning … Using parent commit.` → tip-only
   [TJA L286-298]. dorny's missing-`before` variant: `::warning 'before' field is missing …`
   → `git log -n 1` tip-only [DOR]. *Silent-partial risk: yes by design* — a multi-commit push
   whose `before` vanished **will** rebuild only the tip; made *legible* by the annotation, not
   corrected. Both are documented, deliberate degradations (READMEs carry the `fetch-depth: 0`
   requirement precisely to keep this case rare [TJA L88]).
3. **Merge-base against the default branch**: re-derive a sane base (`git merge-base HEAD
   origin/<default>` — dorny's feature-branch mode; tj's PR path) [DOR git.ts L88-156; TJA
   L450-626]. *Silent-partial risk: low but nonzero* — after a force-push, the merge-base of head
   and the (also rewritten) default tip is fine if the default branch wasn't rewritten; if the
   whole event history moved, merge-base itself fails → their loop deepens then `throw` [TJA
   L636-645]. Loud.
4. **N-commit window** (fallback `HEAD~k`): the GitHub predecessor's *empty*-before shape was
   exactly a 1-commit window (`git diff "" $GITHUB_SHA || true` → silent nothing [X-2 §7]; and
   the all-zero → `HEAD^ HEAD` narrow design [main `.github/workflows/docker-build.yaml` L67-68
   via `git show`, read this session]) — the survey shows this class produces the *silent green
   partial* the owner fears whenever paired with `|| true`/no annotation. tj restricts the
   parent-window to its warning-annotated degrade; nobody recommends a silent one.
5. **Deliberate fail-red**: our posture — no `|| true`, `set -eu`, exit 128 propagates, detect
   job fails before any publish [X-2 §3, script L48-52, workflow L104-112 + t10 leg pinning
   "assign-then-emit" [X-2 §6]]. Precedent: dorny throws on unfetchable base [DOR]; tj throws on
   undiffable endpoints and on same-sha ambiguity [TJA]; the *server-side trigger* itself fails
   closed on a diff error (§2) [F15]; nx derives base from run history, and API failures surface
   as action errors [NXS]. Nothing in the surveyed ecosystem prefers green-over-red for
   "detection couldn't compute a range" — red is the majority posture for exactly the
   "would silently under-build" class.

**Judgement (facts → not a decision): keep fail-red for unreachable `before`.** A publish
pipeline must not report green when it did not verify it built everything it should — the
asymmetry is: a red detect job costs one re-run; a green-but-narrow run can strand an image at a
stale tag until noticed, and `:latest`/`:main` roll forward from whatever built. Two cheap
improvements precedent supports (§Options): a **bounded targeted fetch first** (idiom 1 — turns
most force-push cases fully correct instead of red, 172 ms measured), and one **log line naming
the endpoints** so a red run is diagnosable without the context dump (every surveyed actor
prints its chosen base/head pair before diffing: `[DOR main.ts L198-200 "Changes will be
detected between …"]`, `[TJA core.debug Previous SHA]`, `[AHM prints the diff outcome]`).
**Unreachable-but-still-in-server caveat (proven, why red may persist):** orphaned commits leave
the instance on `gc` (default grace ~2 weeks; the targeted fetch simply errors again → still
loud — no silent path).

### 6. `fetch-depth: 0` — measured cost on this repo/runner shape, alternatives, and whether depth 0 hides anything

**Real numbers (measured this session against the canonical instance from this Coder workspace —
the runner's act-24.04 container runs in-cluster and will differ in absolute time, the ratio
holds [ME]):**

| Shape (refspecs exactly as checkout v6 issues them) | Wall time | Pack received | Objects |
|---|---|---|---|
| `fetch-depth: 0` all branches + tags (what L88 does today) | **1,849 ms** | **21.23 MiB** | 60,988 |
| `fetch-depth: 1` single branch tip (checkout's default) | 743 ms | ~12 MiB `.git` | (1 commit + 1 tree-snapshot) |
| `fetch-depth: 0` + `filter: blob:none` (partial clone) | **765 ms** | **5.8 MiB** | (commits+trees only) |
| `git fetch --depth 1 origin <pre-push-orphan sha>` (targeted fill) | **172 ms** | ~single commit + trees | 1 commit |

For contrast, *this workspace's* gitdir holds 151.44 MiB packed / 96,206 objects / 15,573
commits across all refs incl. worktrees and history the servers don't carry (`git
count-objects -vH`, `git rev-list --count HEAD` = 8,252; tracked working tree = 27.5 MB across
2,603 files) — the repo is not big; a full-history clone of the *served* refs is the 21 MiB
row. Runner-side consequence per the chart's capacity-1 shape [X0 §3]: one queued job at a
time, so `fetch-depth: 0` adds ~1-2 s per detect-job and ~10 MiB of per-job container disk
against the runner's 2 Gi workdir / 10 Gi docker-data volumes [X0 §3]. **Cost is a non-issue at
lab scale; this confirms [X-2 §OQ4] best guess (now measured).**

**Is there a *silent* hazard at depth 0?** Surveyed, one *loud* surprise and nothing silent:

- checkout v6's own drift guard (proven, upstream source): after the all-history fetch it
  re-tests the event ref; if the ref moved (push/force-push raced the trigger) it re-fetches the
  recorded commit by SHA, and if the ref *still* doesn't match it **throws**
  `The ref '<ref>' does not point to the expected commit '<commit>'. The ref may have been
  updated after the workflow was triggered.` [CKO6 `src/git-source-provider.ts` L188-212]. That
  is a *red* failure mode, not a silent wrong-checkout — the historical silent-stale-commit bug
  class is closed in v6 by design. **Unverified here:** that the deployed runner actually pulls
  this v6 (see mirror resolution below) and that the guard fires as described on act containers.
- Detached HEAD: checkout detaches at the event SHA (`ref` defaults to `github.context.ref` +
  `commit` = `github.context.sha` [CKO6 `input-helper.ts` L78-97]; README *"In a pull request
  trigger, ref is required as GitHub Actions checks out in detached HEAD mode"* [CKO6 README
  L346]). `build-pr`'s only git read is `git rev-parse --short HEAD` — works in a depth-1 clone
  and hence in depth-0 [X-2 §7 probed].
- Stale remote refs: each job runs in a fresh container from the pristine working directory (act
  behavior; workspace is per-job [X0 §3]) — no cross-run ref-cache to go stale. (Mechanism
  proven upstream only for checkout itself — the "checkout in fresh workspace" property — the
  per-job-container part is lab ground from run 0, **not re-derived here**.)
- `fetch-tags: false` default means tags aren't force-refreshed per fetch, but the all-history
  refspec *includes* `+refs/tags/*:refs/tags/*` [CKO6 ref-helper L6, L70] — harmless, and the
  `next-n` tag math never reads local tags (it queries the registry over HTTP — script L68-91).

**Alternatives priced:**
- `fetch-depth: <N>`: **cannot work** — an N-commit push needs endpoint at distance k ≤ N, k is
  unbounded; even N=2 breaks any 3+-commit push, and the fallback `HEAD^` needs ≥ 2 [X-2 §4].
- **default (1) + targeted fill** (`git fetch --depth 1 origin "$before"` after a depth-1
  checkout): 172 ms measured, correct range for arbitrary N, *loud* on failure (fetch error →
  set -e → red). For PRs, fill both `base.sha` and `head.sha`. Needs the server's
  sha-in-want: **proven on** — Forgejo writes `uploadpack.allowfilter=true` +
  `uploadpack.allowAnySHA1InWant=true` into every repo unless `[git].DISABLE_PARTIAL_CLONE` is
  set, whose default is `false` [F15 `modules/git/git.go` L311-322; `modules/setting/git.go`
  L30/L52; GSD git-config: *"Allow upload-pack to accept a fetch request that asks for any object
  at all"*], and live-tested end-to-end against `git.spencerslab.com` (fetched a commit reachable
  from no ref the client had — [ME]). **Not exercised:** the runner container's network path to
  the instance over the ingress (jobs clone over HTTPS the same way main-sync's did — run 0 saw
  real clones [X0 §3] — so the capability route exists, but the *combination*
  depth-1+fill-on-this-runner is unproven here).
- **`filter: blob:none` at depth 0**: halves bytes 5.8 vs 21 MiB measured (server permits it,
  same config block). Caveat (proven shape, unverified on-platform): `git diff --name-only` with
  the default rename detection (`diff.renames=true` since git 2.9) may lazily fetch blob
  *contents* for add/delete pairs to score similarity — extra round-trips, and if lazy fetch
  fails the command errors (loud). Suppressing with `-c diff.renames=false` or `--no-renames`
  keeps name-only diffs tree-local (trees are present in a blobless clone). **Unverified
  behavior against Forgejo's filter support — treat as lab experiment, not recommendation.**
- **Mirror byte-equality question from [X-2 §1] — RESOLVED (proven):**
  `git ls-remote https://data.forgejo.org/actions/checkout` answers
  `refs/tags/v6 → d23441a48e516b6c34aea4fa41551a30e30af803` and GitHub upstream
  `refs/tags/v6 → d23441a…` — the *same tag object sha* on both hosts (content-addressed ⇒
  identical tag → identical commit → identical trees/blobs; also equals the mirror's `v6.1.0`
  and upstream `v6.1.0`, `d23441a`/`d23441a` [ME]). The action.yml inputs the scout quoted
  (`fetch-depth: default 1`) therefore apply verbatim on this platform. One residual: the runner
  resolving `uses:` *through* `DEFAULT_ACTIONS_URL = data.forgejo.org` is proven for this lab by
  runner log [X0 §4], so the whole path is grounded; what remains untested is only whether
  checkout's drift-guard throws as written on the act containers.

**Bottom line for the owner's literal sentence:** `fetch-depth: 0` cannot mask non-tip changes —
it is the only setting that makes non-tip changes *visible* offline [X-2 §4 + this §6's source
chain]; a cheaper *correct* alternative exists (depth-1 + targeted fill) but re-implements
checkout's own ref-race handling inside the workflow and stays red-only on orphaned-GC cases.

### 7. What the loud version of "nothing detected" looks like (precedents for legible empty sets)

The two shipped quiet spots first: the port dropped the predecessor's only trace — GitHub
builder printed `echo "Changed containers: $RESULT"` (verified at `main` L85 via `git show`;
the forge step L103-112 writes only to `$GITHUB_OUTPUT` [X-2 §5]) — and `!= '[]'` skip-without-log
leaves the run green with zero builds [X-2 §5, L115/L322]. What the ecosystem treats as legible:

1. **Echo the computed set and its endpoints** — near-universal and free: ahmadnassri prints
   `✅ files were changed` / `❌ no files were changed` and groups the file list [AHM L57-66];
   dorny logs `Changes will be detected between <base> and <head>` [DOR main.ts L198-200]; tj
   `core.debug('Previous SHA: …')` plus info-lines through its fetch loop [TJA]. The predecessor
   did it at L85. This is the *documented ecosystem norm*; cost: one line of shell.
2. **Workflow-command annotations** — GitHub: `::warning file=…::message` / `::notice …::`
   "creates … an annotation" rendered on the run page [GHCW]. **Platform reality check (proven
   at deployed runner/server):** runner v13.2.0 interprets `warning` and `error` (log-level
   lines with the raw `::warning::` text preserved for the server) [RUN13
   `act/runner/command.go` L54-83] but has **no `notice` case** — `::notice::` falls to
   `default:` → plain info-log [L81-82]; and Forgejo v15.0.10 has **no annotation store/render**
   at all (zero grep hits in `routers/web/actions/`, `models/actions/`, `services/actions/`,
   templates) [F15, ME-grep]. So on this platform `::warning::` buys a 🚨-prefixed line in the
   **job log**, nothing UI-chip-level like GitHub. Treat as log decoration with meaning, not
   GitHub-grade annotation.
3. **Job summaries** — GitHub renders `$GITHUB_STEP_SUMMARY` markdown on the run page [GHCW].
   Runner v13.2.0 *does* collect the summary file (`processRunnerSummaryCommand`, size-capped,
   `rm` discards) and logs it (`⚙ Summary - <content>`) [RUN13 `step.go` L70-113]; Forgejo's own
   conformance exercises append/mask/remove [E2E `example-step-summary`]. But v15.0.10's server
   code carries **no summary model/render** (same greps) [F15, ME] — on this instance summaries
   are a **log-text** affordance, not a run-page widget. Documented-for-GitHub; log-only-here.
4. **`skipped` status is the platform's own "did nothing" badge** — false-guard jobs report
   *skipped* and count as success [R-1 R1 §2/§4 with F15 cites]; the lab *observed* 18 such
   skipped rows via the public tasks API [R-1]. So our `!= '[]'` skip already yields a gray,
   API-visible skipped job per arm [X-2 §5] — visible-but-subtle; the log body is where the
   "why" should go.
5. **GitHub's trigger-level precedent: "no changed files ⇒ no run at all"** [GHW] — the green
   no-op run doesn't exist to look quiet. Forgejo replicates fail-closed (§2). This repo can't
   use that affordance *inside* a dispatched run, but it is the reason both platforms' actions
   print their bases (4.1): once you *are* running, silence is ambiguous, so the ecosystem's
   answer is "state the verdict in the log and/or fail red."
6. **Distinguishing "no changes" from "detection failed": the surveyed line is exit status.**
   "no changes" = green run + `[]`/`false` outputs + a log line; "failed detection" = **red**:
   tj throws on undiffable endpoints [TJA L636-645], dorny `setFailed` on every internal error
   [DOR main.ts L57-58], ahmadnassri prints `::warning` and *exits 0 only for unsupported
   events*, never for diff errors [AHM L5-8]. Our shipped design matches the principle (assign
   before emit, 128 propagates — script L48-52 + t10 pin [X-2 §6]); what it lacks is (1)'s echo
   and a `::warning` when the empty came from the *fallback* branch (distinguishing first-push
   narrowing from true empty).
7. **Scheduled/manual full rebuild fallback** — GitHub documents `workflow_dispatch` inputs as
   the manual escape hatch [GHE/GHW dispatch docs]; our header already documents
   *"Rebuild escape hatch: name the containers to (re)build when their sources did not change
   but a publish is due (a failed or cancelled earlier run). An empty list builds nothing."*
   [workflow L63-65]. Precedent for a periodic "just rebuild everything" cron exists around but
   nothing in the surveyed actions implements it — it's a workflow authoring choice, listed as
   Option B6.

---

### §Options (facts and mechanisms only — planner/owner decide)

### Surface A — the detector's fallback range (`scripts/forgejo-container-detect.sh` L37-46, L52)

- **A1. Status quo** (empty-or-zeros → `HEAD^..HEAD`). Cost 0. Proves: the owner-visible
  multi-commit shape is already correct for non-first pushes (§1-2 payload chain).
  Stays unverified: nothing new. Failure posture under bad payload: **silent tip-only** for the
  (source-proven-unreachable-by-git-push) empty case, designed tip-only for the first push.
- **A2. Fail-wide first push**: zeros → diff against the empty tree
  (`git diff --name-only <emptytree-or-oid> "$b" -- containers/`; ahmadnassri's verified idiom
  [AHM L26-30]; equals Forgejo's own trigger `--root` behavior [F15 repo_compare L328-332]).
  Cost: a repo/branch-creation push enqueues up to 13 matrix builds (queue on capacity-1 —
  minutes each; bounded). Proves: trigger-vs-detector first-push asymmetry (§2.1) gone.
  Failure posture: loud (a bad tree diff errors); never silent-narrow. Unverified: nothing else.
- **A3. Merge-base first push against default branch** (dorny's feature-branch mode [DOR
  main.ts L180-188]): zeros → `git merge-base "$SHA" origin/main` then diff. Cost: needs the
  base branch history (depth-0 has it) and dies red when there's no common ancestor (unrelated
  tree) unless guarded → then fall back to A2. Proves: first pushes rebuild exactly what the
  branch adds vs main. Failure: loud. Unverified: none.
- **A4. Annotate the fallback**: keep the range, add `echo "::warning::first push or missing
  before — only the tip commit was scanned ($SHA^..$SHA)"` (and the endpoints echo, §7.1).
  Cost: 2 shell lines. Proves: the narrowing event is never silent — the dorny/tj posture
  ([DOR L169-171], [TJA L293-295]). Failure: loud-by-log. Unverified: rendering of the raw
  `::warning::` text in the Forgejo UI beyond the log line (§7.2 platform facts).
- **A5. Distinguish empty from all-zero**: empty `before` → **exit non-zero** (a payload/path
  anomaly — per §1 unreachable on git-push/mirror events), all-zero → A1/A2/A3 behavior.
  Mechanism: split L38's zero-strip test into `[ -z "$before" ]` (die, with message) vs
  all-`0`-length check (first-push path). Cost: nothing at runtime. Proves: the owner's fear
  shape becomes structurally red instead of green-tipped even for hypothetical producers
  (future API-triggered pushes, hand-built runs, other event kinds defaulting into the push
  arm). Failure: loud. Unverified: whether any non-git event can route a push-arm `before`
  empty on this build (source found none in push/mirror paths; none *searched* exhaustively —
  schedule/dispatch/PR don't carry before and our workflow never fires those into this arm).

### Surface B — the workflow checkout + empty-set posture (`.forgejo/workflows/containers-build.yaml` L84-88, L103-112, L115/L322)

- **B1. Keep `fetch-depth: 0`** — measured cheap (§6 table: 21 MiB/1.8 s), required for every
  N-commit shape, kills the whole shallow-recovery-idiom class tj/dorny carry. Cost: the
  measured per-job bytes/time; container-disk headroom check vs 2 Gi workdir [X0 §3] (21 MiB →
  fine). Failure: v6 drift-guard is loud (§6).
- **B2. Depth-1 + targeted fill**: bare checkout + `git fetch --depth 1 origin "$EVENT_BEFORE"`
  (and for PRs both endpoint SHAs) before the diff. Proven capability (sha-in-want, §6 + live
  172 ms). Cost: ~4 workflow lines of bespoke git logic; re-implements part of checkout v6's
  guard; the PR fetch-by-sha also depends on the server keeping allowAnySHA1InWant enabled
  (admin-flippable `DISABLE_PARTIAL_CLONE`). Failure: loud (fetch or diff error → red; no `||
  true`). Proves: detection cost stops scaling with repo history. Unverified: runner-internal
  network/auth path for the extra fetches (same credentials checkout used fine on main-sync —
  [X0 §3] — so low risk, unproven here).
- **B3. `fetch-depth: 0` + `filter: blob:none`**: halves bytes; tree-level diff works on
  blobless clones; must pin `--no-renames`/`-c diff.renames=false` to avoid lazy blob fetches
  (§6). Failure: loud (server filter config proven; lazy-fetch failure = git error).
  Unverified: the rename/lazy-fetch interaction against *this* git/runner combination — lab
  experiment before adopting.
- **B4. Empty-set legibility** (independent of A's choice): add `echo "changed-containers
  $changed (range $before..$sha / $base..$head)"` to the detect step (§7.1, predecessor-parity)
  and optionally a `::warning::` line when `[]` arrived from a push/PR (not from dispatch).
  Both arms' `skipped` status then has a log reason. Cost: 1-3 lines; proves: green-no-op runs
  self-explain; failure posture: log-loud by construction. Unverified: nothing behavioral.
- **B5. PR arm → merge-base diff** (`git diff --merge-base …` or explicit merge-base + two-dot):
  aligns detector with the trigger's three-dot policy [F15 L520-545; GHW] and kills both the
  over-detection waste and the §4 rare under-detection. Cost: one command change; new failure
  mode: merge-base unresolvable after branch history rewrite → red where two-dot "worked" (loud);
  requires git ≥ 2.43 for `--merge-base` or hand-rolled `git merge-base` (version of runner
  image's git **unverified**). Base-object availability: proven at depth 0; at B2/B3 needs the
  base.sha fill too.
- **B6. Cadence escape hatch**: keep dispatch-with-names (already documented), optionally add
  a *manual* "all" convention (`containers=all` → emit all 13 names) rather than a scheduled
  rebuild — a scheduled full rebuild on capacity-1 would starve real work; nothing surveyed
  recommends one for this shape (adjacent fact [X0 §4 concurrency trap note]).

### §Test-pinnable invariants (new legs the suite currently cannot express)

Baseline from [X-2 §6]: 29/29 green without any of these; a tip-narrowing mutation
(`$SHA~1..$SHA`) survives all of them. Invariants to pin (leg names suggestable; planner
decides):

1. **Checkout depth pin** — parse the detect job's checkout `with:` map; assert
   `fetch-depth == 0`. (t6 today reads only `uses:` [X-2 §6]; deleting L88 keeps the suite green —
   this closes exactly that.)
2. **Range-width fixture leg** — extend fixture1 to a **≥3-commit push** whose *middle* commit
   changes a container and whose tip touches only non-container files; assert the middle
   container IS in the output. (The d-legs are all one-commit-adjacent [X-2 §6]; this is the
   direct regression net for the owner's stated fear, offline.)
3. **Endpoint-identity leg** — push leg asserting the diff base equals `EVENT_BEFORE` even when
   `EVENT_BEFORE == sha~1` is NOT true (guards future `$SHA~1` refactorings in either direction;
   complements existing d4 worktree-narrowing pin).
4. **Fallback-shape leg** — all-zero (and, if A5, empty-string) before on the multi-commit
   fixture, asserting the *chosen* first-push posture (A1: tip-only exact output; A2: full
   container set; A4/A5: the warning/failure lines) — today only d2's adjacent tip fallback is
   pinned, so any change of fallback shape is invisible.
5. **Loud-failure pin** — unreachable/garbage `before` on a scratch fixture → detector exit 128
   AND the workflow-step emulation (red), plus extend the r3 no-`|| true` scan to
   `scripts/forgejo-container-detect.sh` (currently bans silencing on workflow run-lines only
   [X-2 §6]).
6. **Legibility pin** — assert the detect step echoes the changed set (and the `::warning::` on
   empty, if B4) — pins the *log shape* against re-dropping the echo (run-2 EXPLORE §5 shows a
   port silently dropped the predecessor's exactly this line).
7. **Accessor byte-pin** — the `env:` mapping lines L96-102 (`forgejo.event.before`,
   `forgejo.event.pull_request.base.sha`, `…head.sha`) asserted byte-exact, the way r1 pins the
   job `if:` strings — a typo'd accessor currently renders detection silently empty-green
   (the §1 masking shape) with zero test teeth. *(Textual only — it cannot prove the payload
   carries the field; the source chain in §1 does that, and the owner-leg probe can do it live.)*
8. **PR-shape legs** — PR fixture asserting the chosen posture (two-dot over-detect expectation,
   or if B5: merge-base equality leg with base-moved-after-branch fixture) + empty
   `BASE_SHA` ⇒ exit 128 red (today measured only [X-2 §3], no legs).

### §Open questions for planning (best guesses attached)

- **OQ-a (first-push posture)**: adopt A2/A3 (fail-wide/merge-base) or keep A1 + A4 annotation?
  *Best guess: A4 now (+A5 split), A2/A3 only if the owner wants branch-bootstrap pushes to
  publish images; with `push.branches: [main]` the case is remote-today — but A5 is free
  insurance.*
- **OQ-b (PR arm two-dot → merge-base, B5)?** *Best guess: keep two-dot — over-detection is
  benign for PR tags, and B5 trades a proven-benign waste for a new (loud) failure mode plus a
  runner-git version unknown; planner may reverse with the test-leg 8 evidence.*
- **OQ-c (checkout shape)**: keep depth 0 (B1) vs depth-1+fill (B2)? *Best guess: keep B1 —
  measured 21 MiB/1.8 s, zero bespoke git; B2's extra fetch surface only pays off if history
  grows ~10×.*
- **OQ-d (blob:none)** worth a lab experiment later? *Best guess: park; the `--no-renames`
  dependency makes it a correctness-coupled cost trick, and 15 MiB saved is nothing at this
  scale.*
- **OQ-e (echo/warning shape)**: plain echo only, or echo + `::warning::` on empty? *Best guess:
  echo (predecessor parity, test-pinnable, always-true) + `::warning::` on the fallback branch
  only; no annotation for a plain `before==sha` empty (correct semantics).*
- **OQ-f (live payload probe)**: run the §1 one-dispatch `toJSON(forgejo)` probe before or after
  merge? *Best guess: owner-leg, post-merge on a scratch branch — everything the probe would
  confirm is source-proven (§1); the probe upgrades "proven at tag" to "proven on this instance,"
  nice but not blocking.*
- **OQ-g (runner git version for `--merge-base`)** — if B5 chosen: measure once in a throwaway
  job (`git version`). *Best guess: act-24.04 (Ubuntu 24.04) ships git 2.43.x+ — fits B5 —
  unverified.*
- **OQ-h (`total_commits`=0 quirk, §4)**: worth a docs/notes line so nobody builds detection on
  it later? *Best guess: yes, one line in the plan's facts section.*
- **OQ-i (mirror `v6` equality)**: [X-2 §1]'s "byte-equality UNVERIFIED" is now resolved
  (identical tag object sha §6) — carry the correction into the plan's facts; residual unknown
  is only runner-side use of v6's drift guard on act containers.

### §Contradictions (docs vs source vs EXPLORE guesses) — how to weigh

1. **[D15] v15.0 reference.md L73: "`paths` … only triggered if *the pushed commit* modifies
   one of the path in the list"** vs **[F15] source: the server diffs `before`↔head (whole
   range; whole tree on first push)** — source decides (behavior provable in code; the sentence
   is loose prose that predates/ignores the range mechanics). Same class as the
   `context.go` L59 merge-branch comment vs the wired `refs/pull/N/head` ref (source wins,
   §4). Weighting note: docs are not evidence here; both quotes still go to the plan so nobody
   re-reads the doc line as a tip-only trigger.
2. **[X-2 §OQ2 best guess]** "the hardened pattern is before..sha-first + explicit
   fetch-of-before + loud-or-loud-fallback, ours already has first + last" — **refined**:
   dorny = fetch-then-**throw** (no fallback), tj = **warning-then-tip-only** fallback (the
   *narrowing degrade exists in the wild by design*), ahmadnassri = **fail-wide** via empty
   tree. There is no single ecosystem consensus posture; the shared floor is "never silent"
   (§5). Ours is loud-fail but silent *fallback-branch* (A4 gap).
3. **[X-2 §0/§3]** the "empty `before` falls through to tip-only" shape — **downgraded by §1's
   source chain**: it is unreachable via git-push/mirror events on this build (the field is
   always a real OID or all-zeros). It survives as a defensive-coding option (A5), not a live
   payload risk. The scout's measurement stands (L38 *does* treat empty as first-push — that's
   what the code says); what changed is the *reachability* premise.
4. **[GHW] GitHub push docs "maximum of 2048 commits" vs older secondary claims of 20** — the
   current official page says 2048 [GHH]; older blog/answer text saying 20 is stale. (Surfaced
   because the `commits[]`-union school's range-trust depends on the cap.)
5. **`example-step-summary` conformance exists** [E2E] **but v15.0.10 server has no summary
   model** [F15, greps] — reconcile: the runner extracts and log-emits summaries [RUN13]; the
   run-page render this lab has is *the log*. Job summaries as a GitHub-style UI surface =
   **documented-upstream-only, not platform-proven here** (§7.3).

### Adjacents (not asked; found on the way — one line each)

- The Actions-side push payload also omits `TotalCommits` (§4 last block) — `0` in
  `forgejo.event.total_commits` for ordinary pushes.
- `receive.hideRefs = refs/pull/` [F15 `modules/git/git.go` L308] hides PR refs from
  advertisement; checkout v6's PR fetch-by-commit sidesteps it (§4) — but any hand-rolled
  `git fetch origin refs/pull/...` would still work server-side once the sha is wanted.
- Force-push *to main while the detect job is queued*: checkout v6's guard re-fetches the
  recorded commit (allowAnySHA1InWant makes that work on this server) or fails red — the
  detector then diffs against a `before` that may no longer even exist as a ref tip; the range
  itself stays computed. Loud everywhere.
- No `.forgejo` conformance repo test asserts `event.before` on push [E2E, ME-grep] — the probe
  in §1 would be new information to the platform, not a re-run of theirs.

### Sources (keys → provenance; all accessed 2026-11-13 unless noted)

F15 files read (tag commit `17e1001d…`): services/actions/context.go; services/actions/notifier.go;
services/actions/notifier_helper.go; modules/actions/workflows.go; modules/git/commit.go;
modules/git/repo_compare.go; modules/git/object_id.go; modules/git/git.go; modules/structs/hook.go;
modules/structs/pull.go; services/convert/pull.go; cmd/hook.go; routers/private/hook_post_receive.go;
modules/setting/git.go; models/issues/pull.go; services/mirror/mirror_pull.go;
routers/web/repo/branch.go; services/repository/branch.go; services/release/release.go — plus the tag
verification API call and the two negative greps (annotation/summary absence).
RUN13: act/runner/command.go; act/runner/step.go.
E2E: example-push, example-pull-request (test.yml + assert-contexts.sh), example-step-summary,
example-checkout, actions.sh context-save hook.
D15: reference.md (v15.0 branch).
CKO6: action.yml; README.md; src/git-source-provider.ts; src/ref-helper.ts; src/input-helper.ts
(all @ `v6` = `d23441a…`), + ls-remote on data.forgejo.org and github.com.
GHW/GHE/GHH/GHC/GHCW: workflow-syntax; events-that-trigger; webhook-events-and-payloads;
contexts; workflow-commands.
DOR: README.md, src/main.ts, src/git.ts. TJA: README.md, src/commitSha.ts, src/utils.ts.
AHM: README.md (via marketplace page), action.yml, scripts/index.sh. NXS: README.md.
GSD: git-diff-tree, git-log, git-config (gitrevisions covered via GHW three-dot definition).
G22: workflows.go + repo_compare.go @ v1.22.6. CVE: GHSA-mrrh-fwg8-r2c3.
LAB: [X-2] run -2 EXPLORE (measurements reused, not redone); [R-1]; [X0]; this worktree's
detector/workflow/tests and `git show main:.github/workflows/docker-build.yaml`; [ME] the
clonetests battery (4 fetches) + repo-size counts + greps.
