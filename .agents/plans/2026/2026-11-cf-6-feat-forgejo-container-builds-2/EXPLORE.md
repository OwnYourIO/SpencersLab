# EXPLORE — cf-6 run -2: `fetch-depth: 0` and multi-commit change detection (card 6 follow-up)

Written by `agent-explore` 2026-11-13 (workspace clock), read-only scouting for run -2 of card 6.
Request = the owner's review comment, verbatim, on `.forgejo/workflows/containers-build.yaml` line 88
of the branch-vs-`main` diff (the line is `fetch-depth: 0`):

> Can you double check this? Most of the things that need to get built aren't the top commit, and I'm
> worried fetch-depth: 0 will mask those changes. A round of research on how others address this is needed.

Predecessors (not redone here): run 0 `…/2026-11-cf-6-feat-forgejo-container-builds/EXPLORE.md`
(instances/runner/registry + GitHub-precedent mechanics), run -1
`…/2026-11-cf-6-feat-forgejo-container-builds-1/EXPLORE.md` (ROLE/dual-registry ground) and its
`RESEARCH.md` (R1/R2). The detector was untouched by run -1 (`git log --follow --
scripts/forgejo-container-detect.sh` → one commit: `87ee443c9` run-0 C01); the `fetch-depth: 0` line
also predates run -1 — it is in C01's version of the workflow (L60 of `git show
87ee443c9:.forgejo/workflows/containers-build.yaml`) and run -1's diff (`87ee443c9..bb8952db9`) does
not touch it. Branch HEAD `a3e449e2a`; local `main` = `origin/main` = `de02e1884`.

## 0. Headline answer (facts, causality stated plainly)

In the shipped code, `fetch-depth: 0` **prevents** masking; it does not cause it. The push detector
diffs the **whole pushed range** `before..sha` (`git diff --name-only`, two endpoints), and that range
only resolves locally if the clone contains `before` — which at the checkout default (`fetch-depth: 1`,
shallow) it does not; I measured that a depth-1 clone makes push and PR detection **fail loudly**
(`fatal: bad object`, exit 128 → detect job red), never a silent empty set. A container changed in a
**middle** commit of a multi-commit push IS detected (proved by direct probe of the shipped detector,
§2). The one real silent-masking shape in the code is unrelated to depth: if `forgejo.event.before`
resolves **empty/missing** on a push (payload question, UNVERIFIED — §3), the detector falls into the
first-push `HEAD^..HEAD` fallback and **does** mask non-tip commits, green. That shape, plus the
absence of any test wider than one commit (§6) and the fact that **no leg pins `fetch-depth: 0`** (§6),
are what the research round should be pointed at.

## 1. Every checkout in `.forgejo/workflows/containers-build.yaml` (branch file, 369 L)

| # | Job / step | Action + version | Inputs set | Defaults in force | What it is for |
|---|---|---|---|---|---|
| 1 | `detect-changes` → `- uses: actions/checkout@v6` **L84**, `with:` L85-88, **`fetch-depth: 0` L88** | `actions/checkout@v6` | `fetch-depth: 0` only | `persist-credentials: true`, `ref` = "the reference or SHA for that event", `repository: ${{ github.repository }}`, `fetch-tags: false` (all per action.yml — cited below) | **Change detection.** The detector (L109) needs both diff endpoints (`before`, `sha`, `base.sha`, `head.sha`) present as objects. Its comment L86-87: "The detector diffs the pushed or PR commit range; both endpoints must exist in the clone." |
| 2 | `build-release` → L125 | `actions/checkout@v6` | **none (bare step)** | depth **1**, persist-credentials true, event ref | **Build context** — `docker build … "containers/${{ matrix.container }}"` (L311) and the `next-n` stdin reads (L175, L243). Never runs `detect`; no range needed. |
| 3 | `build-pr` → L332 | `actions/checkout@v6` | **none (bare step)** | depth 1 | **Build context** for the pr-tag arm + `git rev-parse --short HEAD` (L361). Verified by probe: `rev-parse --short HEAD` works fine in a depth-1 clone (exit 0). |

Line 88 context (L84-89, in job `detect-changes`, job `if:` L79 is ROLE-membership-only — it runs on
push, PR **and** dispatch):

```yaml
      - uses: actions/checkout@v6
        with:
          # The detector diffs the pushed or PR commit range; both endpoints
          # must exist in the clone.
          fetch-depth: 0
      - name: diag
```

**Default if the line were absent: `fetch-depth: 1`.** Cited from the pinned action's own definition —
upstream `raw.githubusercontent.com/actions/checkout/v6/action.yml` (ref `v6`, fetched 2026-11-13):
`fetch-depth: description: 'Number of commits to fetch. 0 indicates all history for all branches and
tags.'` with `default: 1`. Same file: `persist-credentials` `default: true`; `ref` "defaults to the
reference or SHA for that event"; `repository` `default: ${{ github.repository }}`; `fetch-tags`
`default: false`. Caveat: the runner resolves `uses:` through `DEFAULT_ACTIONS_URL =
https://data.forgejo.org` (run 0 EXPLORE §4, proven by runner log), and my `raw/tag/v6/action.yml`
probe of that mirror 404'd on the path form tried — **the mirrored copy's byte-equality to upstream v6
is UNVERIFIED** (contents are mirrored upstream; a research/owner-leg check of
`data.forgejo.org/actions/checkout` ref `v6` is the exact follow-up).

## 2. How the changed set is computed — `scripts/forgejo-container-detect.sh` (119 L, run-0 C01 code)

Env inputs mapped by the workflow at L96-102: `EVENT_NAME ← ${{ forgejo.event_name }}` (L97),
`EVENT_BEFORE ← ${{ forgejo.event.before }}` (L98), `SHA ← ${{ forgejo.sha }}` (L99),
`BASE_SHA ← ${{ forgejo.event.pull_request.base.sha }}` (L100), `HEAD_SHA ←
${{ forgejo.event.pull_request.head.sha }}` (L101), `MANUAL_CONTAINERS ←
${{ forgejo.event.inputs.containers }}` (L102). The detector consumes nothing else (no `head_ref`,
no `commits[]` — `sanitize` reads `forgejo.head_ref` at workflow L356, unrelated to detection).

`detect()` (script L24-66) per event:

- **`workflow_dispatch`** (L27-30): no git at all. `names` = `MANUAL_CONTAINERS` split on `, `;
  an empty input yields nothing → `[]` ("A dispatch names its rebuild list outright … an empty list
  builds nothing", L28-29; workflow header L63-65 agrees).
- **`pull_request`** (L33-35): `a="${BASE_SHA:-}"`, `b="${HEAD_SHA:-}"` — **direct two-endpoint tree
  diff `base.sha head.sha`**, NOT merge-base / three-dot. No merge-base computation anywhere in the
  script.
- **`push` (and any other event — `event` defaults to `push`, L25)**:
  `before="${EVENT_BEFORE:-}"` (L37); if the before consists only of `0` chars — i.e. **all-zero OR
  empty** (`[ -z "${before//[0]/}" ]`, L38) — fallback `a='HEAD^' b='HEAD'` (L41-42);
  otherwise `a="$before"` and `b="${SHA:-HEAD}"` (L44-45).
  Then the single git command, **L52**: `changed=$(git diff --name-only "$a" "$b" -- containers/)` —
  two-dot, endpoint-to-endpoint; L53 `cut -d/ -f2` → container names; L59-64 gates (DNS-safe name
  regex + `containers/<n>/Dockerfile` existence); `json_array` (L102-109) emits `[…]`.
  No `git log`, no `HEAD^..HEAD` outside the first-push fallback, no `...` triple-dot.
  Deliberate posture, script L48-50: "No `|| true` and no masking pipe on the git call itself: a range
  that fails to resolve must fail the job, not be reported as 'nothing changed'."

**The decisive question (multi-commit push):** with `before` = previous branch tip and `sha` = pushed
tip, `git diff --name-only A B` compares the two **trees** — every file that differs between the
pre-push state and the post-push state is reported, regardless of which commit in between changed it.
So a push of N commits DOES detect changes from commits other than the top one. (Exception: a file
changed mid-range and then reverted to the pre-push content nets zero — semantically the built tree is
unchanged, so not a masking bug.) **No path reduces the range to the tip commit EXCEPT the
all-zero/empty-`before` fallback L38-42** — quoted above.

Proven live against the shipped script (scratch fixture in `/tmp/opencode/cf6r2-exp/fix`, repo
untouched): commits A (creates `containers/alpha`+`beta`) → B (changes **`beta` only**, the middle
commit) → C (tip, touches only `README`); `git diff --name-only A C -- containers/` →
`containers/beta/Dockerfile`; `EVENT_NAME=push EVENT_BEFORE=A SHA=C bash detect` → `["beta"]` exit 0.
The change in the non-tip commit is detected.

## 3. Degenerate inputs — measured exit codes (shipped detector, full clone unless noted)

| Input shape | Code path | Measured behaviour |
|---|---|---|
| all-zero `before` (40 `0`) — first push | L38 true → `HEAD^..HEAD` | full clone: exit 0, tip-commit range only. **Any** all-`0` string (any length) hits the same branch (`${before//[0]/}` strips every `0`, not a length-40 equality test). |
| `before` **absent/empty** (payload field unresolved) | L37 `:-` default + L38 (`"" // [0]` = `""` → true) → `HEAD^..HEAD` | exit 0, **tip-only** — in my fixture `[]` (tip touched no container). This is the dangerous shape: a normal multi-commit push whose `before` failed to arrive is silently treated as a first push. Green, masked, indistinguishable in the log. |
| `before == sha` (empty push) | L44 → `git diff C C` | exit 0 `[]` → builds skip. Correct semantics. |
| `before` unreachable / garbage sha (force-push lost object) | L44 → `git diff 000…1 C` | `fatal: bad object …`, detector exit **128** (git's 128 propagates through the `changed=$(…)` assignment under `set -eu` L17). Workflow step (L104 `set -euo pipefail`, L109 assignment) fails → **detect job red, builds never start** (loud). |
| PR with `base.sha` present/absent | L34-35, L52 | `BASE_SHA`+`HEAD_SHA` both present: works (`["beta"]` on A..C). `BASE_SHA` empty (field missing): `fatal: bad revision ''`, exit **128** → red. The push-side empty-guard L38 has **no PR counterpart** — a PR event with a missing payload sha dies loudly rather than falling back. |
| shallow clone (depth 1) + real `before` | L44 → `git diff A C` with A absent | `fatal: bad object A`, exit 128 → red (exact step-shape emulation under `set -euo pipefail` reproduced: exit 128, message on stderr). |
| shallow clone + all-zero `before` | L41-42 → `HEAD^` absent | `fatal: bad revision 'HEAD^'`, exit 128 → red. Even the first-push fallback needs depth ≥ 2. |

**All-zero sentinel comparison (the run -1 finding):** `main`'s `.github/workflows/docker-build.yaml`
tests the exact string — L67 `if [ "$EVENT_BEFORE" = "0000000000000000000000000000000000000000" ]` —
so an **empty** (unset) `before` on the GitHub builder fell to the else arm and `git diff --name-only
"" $GITHUB_SHA … || true` (L70) → **silent `[]` green, no fallback**. The forge detector widened the
test (L38 zero-strip) so empty/absent joins the all-zero branch → first-push fallback → tip-only. Same
masking shape (multi-commit + missing before ⇒ non-tip commits dropped), reached by a different
mechanism; the forge version additionally *detects the tip* where the GitHub version detected nothing.
Whether Forgejo's push event payload even contains `before` is the open payload question —
`reference.md` v15.0 documents `forgejo.event` as "JSON object containing event details … **details
vary depending on the event**" (L1331 of the fetched doc) and explicitly defers to a `toJSON(forgejo)`
debug job (L1353-1373); no push-payload example is shown, and **no containers-build run has ever
executed here** (§8) — **UNVERIFIED live**.

## 4. Does `fetch-depth: 0` cause or prevent masking?

**The shipped code is the "prevents" shape.** `git diff --name-only before sha` is a two-endpoint tree
diff; full history is what makes those objects exist locally after checkout (action.yml: `0` = "all
history for all branches and tags"). At the **default `fetch-depth: 1`** the measured outcome per event:

- **push**: `before` absent → `fatal: bad object` → step exit 128 → `detect-changes` **fails red** →
  `build-release`/`build-pr` don't run (both `needs: detect-changes`, L116/L323). Loud, not silent.
  NOT a green-empty set — the dangerous shape cannot arise from shallow-ness here because the script
  deliberately dropped the predecessor's `|| true` (script L48-52).
- **pull_request**: `base.sha` absent (it is not the event ref) → same red. (My shallow probe: exit
  128 `fatal: bad object <base>`.)
- **workflow_dispatch**: no git call in `detect` → depth is irrelevant; empty input → green `[]`,
  named input → green builds — identical at any depth (probed both at depth 1).
- The **first-push fallback** (`HEAD^..HEAD`) at depth 1 also dies red (depth ≥ 2 needed) — so removing
  L88 breaks even the degenerate branch that does not consult `before`.

Conclusion for the coordinator: a *reduction* of `fetch-depth` (or deleting L88) converts correct
multi-commit detection into a **red failure**, and can only produce a *silent nothing-built* if someone
also re-adds a `|| true` / masking pipe. Conversely, keeping L88 is what makes the owner's desired
outcome ("things not in the top commit get built") work in the first place. The only live masking
candidate is the empty-`before` payload fallthrough (§3 row 2), which is a **Forgejo payload
availability question, not a depth question** — routed to research below.

## 5. What the workflow does with an EMPTY changed set

Trace: detector emits `[]` (exit 0) → assigned at L109 → `changed-containers=[]` written to
`$GITHUB_OUTPUT`/`$FORGEJO_OUTPUT` (L112) → detect job **succeeds green** → both build jobs' `if:`
contain `&& needs.detect-changes.outputs.changed-containers != '[]'` (L115 release, L322 pr) → jobs
report **`skipped`**. Run outcome: green workflow, zero builds. There is no explicit guard/annotation
step: the loudness is (a) the visible `skipped` status of both matrixed jobs (the mechanism is proven
observable in this lab — run -1 §2 counted 18 `skipped` reports from job `if:`s via the tasks API) and
(b) nothing in the log otherwise. Note the port dropped the predecessor's only echo: GitHub builder
L85 `echo "Changed containers: $RESULT"` has **no counterpart** in the forge step (L103-112 emits the
value to the output file without echoing it) — an empty run is therefore *quieter* than it used to be.
The `!= '[]'` posture is pinned by legs (t5, r1 — §6).

## 6. Test coverage — pinned vs merely present (`tests/services/forgejo-containers-build.sh`, 1656 L, 29 ok exit 0 re-run this session at `a3e449e2a`)

- **`fetch-depth` itself: ZERO legs.** The string `fetch-depth` does not occur in the suite (grep:
  'fetch' appears twice, L697/L1170, both unrelated prose). t6 (L335-351) pins only `uses ==
  {'actions/checkout@v6'}` — it never reads any step's `with:`. **Deleting L85-88 keeps all 29 legs
  green.** The behaviour is *present*, not *pinned*.
- **Diff-range shape**: no leg greps the detector's git invocation (t1 only runs `bash -n`). Behaviour
  pins are the d-legs on scratch fixtures (fixture1 L1217-1233: A→B→C):
  - d1 (L1270-1276) `EVENT_BEFORE=SHA_B SHA=SHA_C` → `["alpha","traefik-mqtt-allowlist"]` — **adjacent
    endpoints only**.
  - d2 (L1278-1286) all-zero → fallback to `HEAD^..HEAD`, endpoint-adjacent again.
  - d3 (L1288-1294) PR `BASE_SHA=SHA_B HEAD_SHA=SHA_C` — adjacent.
  - d4 (L1296-1302) `EVENT_BEFORE=SHA_A SHA=SHA_B` → `[]` — adjacent, container-clean range.
  - **No leg ever spans 2+ commits** (every push/PR fixture range is one commit wide).
- **Mutation analysis (would it go red?):**
  - *Narrow the push range to the tip as `$SHA~1..$SHA`*: every d-leg's fixture already has `before ==
    sha~1`, so outputs are byte-identical → **all 29 stay GREEN**. Nothing pins "the range spans the
    whole push"; only my ad-hoc probe (§2) exercised a 2-commit range. This is the suite's real blind
    spot for the owner's worry.
  - *Narrow to worktree `HEAD^..HEAD` unconditionally*: d4 goes **red** (fixture tip C ≠ event range
    A..B; `HEAD^..HEAD` yields `[alpha,traefik]` vs expected `[]`). So worktree-anchored narrowing is
    pinned, event-sha-anchored narrowing is not.
  - *Remove the all-zero/empty fallback (L38-42)*: d2 red (bad revision → `detect_in` L1262-1265
    requires exit 0). Pinned.
  - *Re-add `|| true` to the detector's git call (silent empty)*: no leg reads detector text for it —
    r3's `|| true` ban (L971-979) scans only the **workflow file's run statements** (`docker login|
    docker push|curl|next-n`), not `scripts/`. **All legs stay green.** The loud-fail posture is pinned
    only indirectly at the emit site (t10, L585-619: "assign first, emit after" so a detector exit 128
    propagates) — the script comment L48-50 is the sole written guard.
- **Degenerate-input handling**: only d2 (all-zero) has a leg; empty-`before`, garbage-`before`,
  `before==sha`, shallow boundaries: **no legs** (measured here instead, §3).
- **Empty-set posture**: pinned — t5 L310-311 (`"!= '[]'" in if_expr` for both build jobs) and r1
  L788-790 byte-exact `RELEASE_IF`/`PR_IF` constants including the suffix; green-empty behaviour is
  d4 (`[]` from a real range) and d6 (empty dispatch ⇒ `[]`).
- Summary sentence for the plan: the checkout depth and the multi-commit *width* of the range are
  **unpinned**; the endpoints *are* respected-vs-worktree (d4), the fallback (d2), the loud-emit shape
  (t10) and the `'[]'` short-circuit (t5/r1) are pinned.

## 7. Predecessor comparison — `git show main:.github/workflows/docker-build.yaml` (current main `de02e1884` still carries the pre-cutover, live-trigger form)

- Checkouts: detect job `actions/checkout@v7` **with `fetch-depth: 0`** (L42-44) — same fix for the same
  problem; build job bare `@v7` (L100-101, default depth 1). So the forge file **inherited** the
  fetch-depth posture, from the same shape: depth-0 where the range is diffed, default elsewhere.
- Changed set (L46-85 inline, before the run-0 rewrite moved it into the script): PR =
  `git diff --name-only "$BASE_SHA" "$HEAD_SHA" || true` (L62-63); push = `git diff --name-only
  "$EVENT_BEFORE" "$GITHUB_SHA" || true` (L70) with exact-40-zero first-push check → `HEAD^ HEAD` (L67-
  68). Same two-endpoint range math as the forge detector (Q2's structure was inherited verbatim; the
  multi-commit behaviour existed on GitHub too).
- Named differences forge-vs-predecessor: (1) forge **removes all three `|| true`** (git-call silence)
  and fails loud instead (script L48-52); (2) first-push test widened from exact-string (L67) to
  any-length all-zeros **or empty** (L38) — changing the missing-`before` failure mode from "silent
  empty" (GitHub: `git diff "" sha || true` → `[]`) to "tip-only fallback" (forge); (3) dispatch with
  empty input **inverted** — GitHub auto-detected (L57 `-n "$MANUAL_CONTAINERS"` gate falls through to
  the range), forge builds nothing (script L27-30, workflow L63-65); (4) `jq` → pure-shell JSON emit
  (no-runner-tool constraint, script header L3-5); (5) checkout pinned `v6` not `v7` (mirror-proven
  action set, workflow header L51-54, t6).

## 8. Live ground truth (read-only; no `admin-*`, no pod exec used)

- Both instances' public tasks APIs (`GET https://<host>/api/v1/repos/CuratedForest/SpencersLab/actions/tasks?limit=200`, anonymous 200, 2026-11-13):
  infra **84 tasks, none with `containers-build` anywhere in the run object** (all titles map to
  `main-sync.yaml` runs and commits that touched other workflows); dev **0 tasks** (unchanged from run
  -1 §6). Consistent with run -1 verified-fact 4: neither instance has ever executed
  `containers-build.yaml` — **no live changed-set output exists to inspect.**
- `git ls-remote origin` → heads `main` only (plus other refs): **`cf-6-feat-forgejo-container-builds`
  is NOT pushed** — the owner reviewed the branch-vs-main diff locally, so even the workflow's
  *triggering* has never fired anywhere. `before`-payload behaviour (§3) therefore has zero live
  evidence either way; settle it only post-merge/first-PR or via the research round (a
  `toJSON(forgejo)` dispatch probe per reference.md L1353-1373 is the owner-leg that would decide it).
- No `kubectl exec` needed for anything above; nothing found requires one.

## §Open questions for research

1. **Does Forgejo v15 (15.0.10)'s push **Actions** event payload carry `before` (and is it the
   previous branch tip)?** reference.md documents `forgejo.event` only as "details vary depending on
   the event" (L1331) with no push example; the webhook PushPayload lineage (Gitea/Forgejo `modules/
   webhook` — my raw fetches of `…/v15.0/modules/webhook/push.go` 404'd, path/branch naming unknown)
   carries `before`/`after`. **Best guess: yes** — Forgejo action payloads are derived from the same
   webhook models, and GitHub does the same — **but if no, the shipped empty-fallback silently narrows
   every push to the tip commit (§3 row 2): that is the one true masking scenario, and it is
   depth-independent.** Needs research: yes.
2. **How does the ecosystem do multi-commit push detection?** Standard shapes to verify: raw
   `before..sha` (ours, GitHub's own `github-script`/on-push examples); `dorny/paths-filter`
   (event-range aware, falls back to merge-base / last-available commit when `before` is unreachable,
   supports the first-push case by diffing `sha` against an empty tree); `tj-actions/changed-files`
   (documented `before`-unreachable handling via fetching the missing commit `git fetch origin
   "$before" --depth=1`, fallback `HEAD~1`). **Best guess: the hardened pattern is
   before..sha-first + explicit fetch-of-before + loud-or-loud-fallback, and ours already has the
   first + last.** Needs research: yes (this is the owner's literal ask).
3. **PR checkout shape on Forgejo**: what does `actions/checkout` with `fetch-depth: 0` actually fetch
   on a `pull_request` event (head vs merge commit — does `forgejo.sha` point at a merge ref?), and do
   `base.sha`/`head.sha` resolve as objects? For same-repo PRs (the only supported case, workflow
   header L53-54) both shas are tips of `refs/heads/*` branches, which "all history for all branches
   and tags" (action.yml) should bring — **UNVERIFIED here** (mirror action.yml contents, and no live
   run). Also confirm whether Forgejo's diff of two endpoint trees matches user expectations for a PR
   whose base moved after branch creation (our direct `base.sha head.sha` two-endpoint diff flags
   files changed on *base* as changed-against-base too → over-detects, never masks; three-dot/
   merge-base would not). Best guess: over-detection is the current, benign-by-design behaviour.
4. **`fetch-depth: 0` costs on this repo**: full-clone time/disk on the capacity-1 runner for a repo
   carrying `.agents/plans` + chart history (hundreds of MB?). Alternatives worth pricing: `fetch-depth:
   2` is NOT sufficient for arbitrary N-commit pushes; targeted `git fetch origin <before> --depth=1`
   after a default checkout; partial clone (`filter: blob:none` — checkout's own input). **Best guess:
   depth-0 stays correct and the fetch is fine at lab scale; the mirror's version skew (§1) is the more
   urgent unknown.**
5. **`before` unreachable (force-push/rebase/squash-merge into main) convention**: ours = red fail
   (§3). Should there be a loud fallback (e.g. tip-only detect *after* attempting
   `git fetch origin <before> --depth=1`, with a warning in the log), or keep fail-only? **Best guess:
   keep fail-loud** (matches script L48-50 intent and r3's no-`|| true` invariant), but the ecosystem
   answer is a research fact.
6. **Does `on.push.paths: ['containers/**']` on Forgejo v15 filter over the whole push range or only
   the tip commit?** If the *trigger* itself only tests the top commit's diff, a push whose non-tip
   commits touch containers never starts the workflow — the detector would never get to be right.
   (GitHub fixed an early tip-only paths-filter bug in 2020.) **Best guess: range-correct (before..sha
   per Gitea's push-event handling), but nothing in this lab has observed it.** Needs research: yes —
   it is the owner's exact worry expressed one layer above fetch-depth.
7. **First-push multi-commit narrowing** (all-zero `before` → `HEAD^..HEAD`, script L41-42, inherited
   from the GitHub builder L67-68): on a brand-new/renamed branch pushing N commits, only the tip's
   container changes build. Alternative ecosystem answers: diff `sha` against the empty tree
   (`git diff --name-only $(git hash-object -t tree /dev/null) sha`-style) or union `event.commits[]`
   paths. Best guess: low practical impact (main already exists; the case is branch-bootstrap only),
   but worth stating to the owner as the one *designed* tip-narrowing.

## §Verified facts (each with its citation)

1. Three checkouts in `.forgejo/workflows/containers-build.yaml`: L84-88 (detect, `fetch-depth: 0`),
   L125 (build-release, bare), L332 (build-pr, bare); file read in full — file is the branch copy at
   `a3e449e2a`, 369 L.
2. Line 88 is `fetch-depth: 0` inside the `detect-changes` job (step L84 `uses: actions/checkout@v6`,
   comment L86-87) — exactly what the owner commented on (branch-vs-`main` diff adds the whole file).
3. `actions/checkout@v6` defaults: `fetch-depth: 1` ("0 indicates all history for all branches and
   tags"), `persist-credentials: true`, `ref` = event ref, `repository = ${{ github.repository }}`,
   `fetch-tags: false` — `raw.githubusercontent.com/actions/checkout/v6/action.yml` fetched
   2026-11-13; runtime resolves via `data.forgejo.org` mirror (run 0 EXPLORE §4; mirrored bytes
   UNVERIFIED, §1).
4. Detector diff shapes: push `git diff --name-only "$before" "$sha" -- containers/` (script L44-45,
   L52); PR `"$BASE_SHA" "$HEAD_SHA"` (L33-35, L52); first-push/empty `HEAD^..HEAD` (L38-42);
   dispatch = no git (L27-30); no merge-base/three-dot/`git log` anywhere in the file (read L1-119).
5. Multi-commit detection: probe on scratch fixture (A→B→C, `beta` changed in middle commit B):
   `EVENT_BEFORE=A SHA=C bash scripts/forgejo-container-detect.sh detect` → `["beta"]` exit 0.
6. Degenerate exits measured with the same script: empty-`before` push (full clone) → `[]` exit 0
   (fallback to tip; fixture tip touched no container); garbage `before` → `fatal: bad object`, exit
   128; `before==sha` → `[]` exit 0; PR with empty `BASE_SHA` → `fatal: bad revision ''`, exit 128;
   short `"00"` before → same L38 zero-strip fallback as all-zero/empty (measured in the depth-1 clone:
   `fatal: bad revision 'HEAD^'` exit 128; the full-clone output of that branch is the same tip-only
   range the empty case produced).
7. Shallow (depth-1) behaviour: push → `fatal: bad object <before>` exit 128; all-zero →
   `fatal: bad revision 'HEAD^'` exit 128; PR → `fatal: bad object <base>` exit 128; dispatch →
   unaffected (named ⇒ `["alpha","beta"]`, empty ⇒ `[]`, exit 0); `git rev-parse --short HEAD` (the
   build-pr dependency, workflow L361) works at depth 1. Workflow-step emulation
   (`set -euo pipefail; changed=$(… detect)`) reproduced exit 128 + stderr — fails red, never silent.
8. Empty-set flow: `[]` output ⇒ both build jobs `if:`-skip (workflow L115, L322) ⇒ run green with 0
   builds; no log echo of the value (compare predecessor's `echo "Changed containers: $RESULT"`,
   `main:.github/workflows/docker-build.yaml` L85 — absent in the forge port).
9. Suite posture at branch HEAD: `bash tests/services/forgejo-containers-build.sh` → **29 ok, exit 0**
   (re-run this session). `fetch-depth` unpinned (zero textual matches; t6 L335-351 reads `uses`
   values only). All d-leg push/PR fixture ranges are one-commit-adjacent (L1217-1233 + L1270-1302);
   d4 pins endpoint-awareness against worktree-narrowing; d2 pins the all-zero fallback; t10
   (L585-619) pins the exit-propagating emit; t5 L310-311 + r1 L788-790 pin the `!= '[]'` guard; r3
   (L971-979) bans `|| true` **on workflow run lines only** — nothing pins the detector's own no-`||
   true` comment-intent (script L48-50).
10. Predecessor at current `main` (`de02e1884`, `git show main:.github/workflows/docker-build.yaml`):
    detect checkout `@v7 fetch-depth: 0` (L42-44), build checkout bare (L100-101); same
    `before..sha` / `base.sha..head.sha` ranges with `|| true` (L62-72); exact-40-zero sentinel L67;
    dispatch-empty ⇒ auto-detect (L57); build gate `!= '[]'` (L89). Forge detector inherits the ranges
    and drops the silencing (per §7 diff points).
11. `fetch-depth: 0` line is run-0 C01 original: present at `87ee443c9` L60; the run-1 C02 diff
    (`87ee443c9..bb8952db9`) shows no fetch-depth hunk; detector file has exactly one commit
    (`git log --oneline --follow -- scripts/forgejo-container-detect.sh` → `87ee443c9`).
12. No live execution: infra tasks API → 84 tasks, 0 containers-build-related; dev tasks API → 0;
    `git ls-remote origin` → cf-6 branch absent (not pushed). Nothing on `main` carries
    `containers-build.yaml` (`git ls-tree -r --name-only main -- .forgejo` → `main-sync.yaml` only).
13. reference.md v15.0: `forgejo.event` = "JSON object containing event details … details vary
    depending on the event" (fetched copy L1331); documented debug route = `toJSON(forgejo)` job
    (L1353-1373); `forgejo.sha` = "the commit SHA that triggered the workflow … depends on the event"
    (context table); push-payload `before` field is **not** shown (UNVERIFIED live, §3/§OQ1).

## §What would have to change (code sites only — if research says the range is wrong)

- `scripts/forgejo-container-detect.sh` L37-46 (`before` parsing + all-zero/empty fallback) and L52
  (the single `git diff` call) — any narrower/wider range semantics lands here; the empty-`before`
  fall-through branch (L38) is the masking site §3 row 2 names.
- `.forgejo/workflows/containers-build.yaml` L84-88 (checkout inputs) and L96-102 (payload-field →
  env mapping; if `forgejo.event.before` is not the right accessor, the fix is an env line, not the
  detector).
- `tests/services/forgejo-containers-build.sh`: fixture1 builder L1217-1233 (needs a non-adjacent,
  ≥2-commit push range + a middle-commit container change), d-legs L1270-1302 (new range-width leg),
  t6 L335-351 (if the plan decides to *pin* the checkout depth, read `with:` there), and a
  detector-text or exit-code leg if the no-`|| true` intent of script L48-50 must become pinned.
- No other consumer of the changed set exists (both matrices read
  `needs.detect-changes.outputs.changed-containers` only — L115/L123, L322/L330).

RESULT
status: DONE
chunk: exploration (cf-6 run -2)
files_changed: [.agents/plans/2026/2026-11-cf-6-feat-forgejo-container-builds-2/EXPLORE.md]
commands_run: [read workflow+detector+tests+predecessor EXPLOREs => pass, git log/show/diff/ls-tree/ls-remote (read-only) => pass, curl https://<infra|dev>/api/v1/.../actions/tasks => pass (84/0 tasks, 0 containers-build), webfetch raw.githubusercontent.com/actions/checkout/v6/action.yml => pass (fetch-depth default: 1), webfetch data.forgejo.org mirror raw action.yml => fail-404 (mirror content UNVERIFIED), git scratch probes in /tmp/opencode/cf6r2-exp (multi-commit detect, 6 degenerate shapes, depth-1 shallow battery, step-shape emulation) => pass, bash tests/services/forgejo-containers-build.sh => pass (29 ok, exit 0)]
deviations: none — wrote only EXPLORE.md at the launch path; scratch fixtures confined to /tmp/opencode; no admin-* servers, no pod exec, nothing pushed/committed.
open_questions: 7 routed to research (§Open questions): OQ1 Forgejo push payload really carries event.before (else the shipped empty-fallback silently narrows pushes to the tip commit — the one live masking shape, UNVERIFIED because the workflow has zero executions and the branch was never pushed); OQ2 ecosystem multi-commit-detection patterns (dorny/paths-filter, tj-actions/changed-files, fetch-of-before); OQ3 Forgejo PR checkout ref shape + two-endpoint diff over-detection; OQ4 fetch-depth:0 clone cost on the capacity-1 runner; OQ5 force-push before-unreachable convention; OQ6 whether on.push.paths filters over the whole range or only the tip on Forgejo v15 (the owner's worry one layer above depth); OQ7 first-push multi-commit narrowing. Also needs-research: byte-equality of data.forgejo.org's actions/checkout v6 mirror (cheap owner-leg: `git ls-remote https://data.forgejo.org/actions/checkout v6*`). Coordinator summary for the owner: shipped code = fetch-depth: 0 PREVENTS masking (depth 1 measured to fail LOUD, red, never a silent empty); the concern lands only on (a) the empty/missing-`before` fallback and (b) unpinned test coverage — neither is caused by depth 0.
next_suggested: Launch agent-research on the §Open questions (OQ1+OQ6 first — they decide whether the concern is real), then a plan round adding a fetch-depth/with: pin leg + a ≥2-commit detector fixture leg before touching the shipped files.
