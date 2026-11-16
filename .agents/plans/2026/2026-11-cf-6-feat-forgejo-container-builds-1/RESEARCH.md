# RESEARCH — cf-6 run -1 (card 6 rework: ROLE-split container builds)

TL;DR (read first):
1. On the deployed Forgejo 15.0.10 the job-level `if:` is evaluated by the **runner**, by
   the *same* expression engine as step `if:` — `contains`/`fromJSON`/`format` are valid
   there (source-proven; never yet *exercised* at job level in this lab).
2. An unset `vars.ROLE` evaluates as **null** (map miss) and coerces like `''`; `== null`
   and `== ''` are both **true** for unset, and `||` short-circuits, so
   `vars.ROLE == null || contains(vars.ROLE, 'prod')` is the one membership spelling that
   is unset-widest, malformed-input-tolerant and whitespace-tolerant at the source level.
   `fromJSON` **errors** (job fails) on unset/empty/non-JSON.
3. False guard ⇒ job **skipped** (not failed); a run of only-skipped jobs aggregates to
   `skipped`, and skipped jobs report the **success** commit status — skip-and-succeed is
   the platform default. `on:` itself cannot be conditioned (event/branch/path only).
4. Variable precedence in this build's code is **Repo > Org/User > instance-Global**; an
   instance-global scope EXISTS (admin UI only, no API, undocumented for v15) — two of
   EXPLORE.md's doc-derived claims need correcting (below).
5. The shipped `vars.ROLE == 'prod'` convention satisfies "prod-only fan-out" but is the
   exact opposite of the owner's "unset = widest"; one convention for both files requires
   either a scoped per-file polarity or changing the convention itself — owner decision.

## R1 — Forgejo Actions expression + variable semantics for a ROLE gate

Evidence keys (every claim cites one; "v15.0.10 source" = tag `v15.0.10`, commit
`17e1001d5e00e8ee3cbc1b6dd31be94ac38185f9`, fetched via the Codeberg API + source archive
`https://codeberg.org/forgejo/forgejo/archive/v15.0.10.tar.gz`; the deployed image is
`code.forgejo.org/forgejo/forgejo:15.0.10-rootless` and `/api/v1/version` says
`15.0.10+gitea-1.22.0` — the `+gitea` suffix is the base-lineage stamp of the long-lived
`v15.0/forgejo` series, the tree at that tag is Forgejo-versioned, Go 1.26, with the act
library vendored into the runner module — do not read it as "Gitea 1.22 code"):

- **[F15]** forgejo v15.0.10 source, file paths at that tag.
- **[R12]** runner `v12.10.2` (the act library the *server* pins —
  `code.forgejo.org/forgejo/runner/v12 v12.10.2` in F15 `go.mod`;
  `https://code.forgejo.org/forgejo/runner/archive/v12.10.2.tar.gz`).
- **[R13]** runner `v13.2.0` — the version BOTH lab runners declare (dev-runner per
  EXPLORE §6; gpu-runner live-checked this session 2026-11-11: `runner: gpu-runner, with
  version: v13.2.0 … declared successfully` 2026-11-09T23:26:13Z, readonly-gpu-kubernetes
  `pods_log(gpu-forgejo-runner-gpu-0, runner)` — and the gpu runner is what executes the
  infra jobs, so the deployed job-`if` evaluator is v13.2.0's act;
  `https://code.forgejo.org/forgejo/runner/archive/v13.2.0.tar.gz`).
- **[D15]** v15.0 docs branch `https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/{reference,basic-concepts}.md`
  (same copies EXPLORE cached; line numbers from my copies).
- **[E2E]** Forgejo's own conformance workflows,
  `https://code.forgejo.org/forgejo/end-to-end/raw/branch/main/actions/example-expression/.forgejo/workflows/test.yml`
  and `…/example-if/.forgejo/workflows/test.yml` (dir listing via
  `code.forgejo.org/api/v1/repos/forgejo/end-to-end/contents/actions`).
- **[GD]** Gitea docs, `https://docs.gitea.com/next/usage/actions/actions-variables/`.
- **[X]** EXPLORE.md in this folder (live-lab observations, not re-derived here).
- **[REPO]** this repo: `main` (= `a6e493b78`) files via `git show`.

### 1. Job-level expression power on the deployed build

**One engine, both levels.** Since Gitea-1.22-line Forgejo, expressions are evaluated by
`act/exprparser` (a hand-written interpreter over the `actionlint` AST, no govaluate).
The function dispatch is a single `switch` shared by every context:
`contains, startsWith, endsWith, format, join, toJSON, fromJSON, hashFiles, always,
success, failure, cancelled` — and **only `success()`/`failure()` branch on the
evaluation context** (`"job"` vs `"step"`), where `success()` at job level means "all
jobs in `needs` succeeded" [R12 `act/exprparser/interpreter.go` `evaluateFuncCall`
L744-837, `jobSuccess` `functions.go` L258-269]. A job-context condition with no status
function is auto-wrapped as `success() && <expr>` [R12 `interpreter.go` `Evaluate`
L101-122]. Therefore **`contains(fromJSON(vars.ROLE), 'prod')` is valid syntax in a
job-level `if:` on 15.0.10** — there is no function restriction between job and step
beyond `hashFiles` (needs a working dir: dead on the server side, runner-side only) and
the status functions' context switch. v13.2.0 adds a `case()` function the server's
v12.10.2 does not have — **version-skew trap: avoid `case()`** [R13 diff vs R12].

**Who evaluates the job `if:`** — not whom the docs-table reading in EXPLORE assumed.
The server at run creation does *not* evaluate job `if:`s: `notifier_helper.go` parses
the workflow with `jobparser.Parse(content, WithVars(vars), …)`, and that pass evaluates
only the matrix, `runs-on`, job `name` and workflow-call/concurrency templates; job `if`
is carried verbatim into the stored `WorkflowPayload` [F15
`services/actions/notifier_helper.go` L413-453; R12 `act/jobparser/jobparser.go` L102-103,
L156-186, L356-375 — no `If` evaluation there]. Jobs are inserted `Waiting`/`Blocked`
[F15 `models/actions/run.go` `InsertRunJobs` L416-476]. At dispatch the **runner**
evaluates the guard: `isEnabled()` = `EvalBool(…, job.IfClause(), DefaultStatusCheckSuccess)`;
false ⇒ `rc.result("skipped")`; **error ⇒ the task returns the error**
(`"❌ Error in if-expression: …"`), which `reporter.Close(runErr)` reports as a failed
job [R12 `act/runner/run_context.go` L1077-1094 + L987-991; R13 same mechanism at
L1416-1428; R13 `internal/app/run/runner.go` L167-175]. v13.2.0's semantic diff from the
server-pinned v12.10.2 is confined to composite-action env/secrets lockdown wrappers +
`case()` + error wrapping — map deref, comparison coercion, `contains`, `||`
short-circuit and the skip path are byte-identical modulo receiver renames [R12↔R13
`act/exprparser/*` diff].

**Where the job-level context comes from.** The server assembles a per-task wire
message (`runnerv1.Task`, protobuf from `code.forgejo.org/forgejo/actions-proto`):
`WorkflowPayload`, `Context` (github/forgejo context — incl. `ServerURL: setting.AppURL`,
which is why the pre-ROLE URL guards worked [F15 `services/actions/context.go` L68]),
`Secrets` (owner+repo merged, plus `FORGEJO_TOKEN`/`GITHUB_TOKEN`; **empty for fork PRs**
[F15 `services/actions/secret.go` L20-63; `models/secret/secret.go` `FetchActionSecrets`]),
`Vars` (see §3) and `Needs` [F15 `services/actions/task.go` L50-95, L112-145]. The
runner binds that into the interpreter as
`EvaluationEnvironment{Github, Secrets, Vars, Needs, Inputs, Steps…}` with
`Context:"job"` [R13 `act/runner/expression.go` L80-100 + `internal/app/run/runner.go`
L377 `Vars: task.Vars`]. So **both `vars` and `secrets` dereference fine in job `if:`** —
matching the docs availability row `jobs.<job-id>.if | env, forgejo, inputs, needs,
secrets, vars` [D15 reference.md availability table]. That table's *functions* column
lists only `always/cancelled/failure/success` for the job-`if` row and never marks
`contains/format/fromJSON` forbidden; it is an availability-of-contexts table copied from
GitHub conventions, and the source shows no such restriction — **docs are silent-to-
permissive; source is decisive.**

**Engine type handling** (both levels, [R12 `act/exprparser/interpreter.go`+`functions.go`]):
- `contains(search, item)`: string/number/bool/null search ⇒ **case-insensitive
  substring** after null→`''` coercion (`coerceToString(Invalid)=""`); slice search ⇒
  per-element **case-insensitive `==`**; anything else ⇒ false, never an error
  [functions.go L21-44; interpreter.go L590-625].
- Missing variable key: `vars` is a `map[string]string`; a missing key deref returns
  **null** (`getPropertyValue` map branch falls through to `nil` — interpreter.go
  L421-438). Map lookup is case-insensitive (L429 `EqualFold`) and names are stored
  uppercased anyway (F15 `models/actions/variable.go` L53 `strings.ToUpper`).
- Comparison: operands of different kinds are number-coerced — null→`0`, `''`→`0`,
  unparseable string→`NaN` (NaN==anything is false) — so `null == ''` is **true**,
  `null == 'prod'` is **false**, `null == null` is **true** (interpreter.go L515-588).
  String `==` lowercases both sides (case-insensitive, L529).
- `||`/`&&` **short-circuit**: left evaluated, and if already decisive the right operand
  is never evaluated (interpreter.go L715-742) — the mechanism that makes guarded
  fromJSON spelling safe on unset.
- `fromJSON(x)`: x must be a *string*, and valid JSON — `null`, `''` and `dev,prod` all
  **raise errors** (functions.go L167-180). In `run:` interpolation an error collapses
  to `""` [R13 `expression.go` `Interpolate` L377-395]; in a job `if:` it **fails the
  job** (§ above).

**Proven vs documented vs untested on *this* instance** (job-`if` unless stated):
- *Live-proven here*: `vars.X == 'literal'` (15/15 true branch, X §2), false-guard ⇒
  `skipped` via the pre-ROLE `startsWith(forgejo.server_url,…)` guard (18 skips, X),
  `==`-comparison truth table inferred from the same guard families.
- *Live-proven here, blocking branch*: `startsWith` (the pre-ROLE URL guard — the one
  guard ever observed to *block* a job, X §2).
- *Source-proven, lab-unexercised at job level*: `contains`, `endsWith`, `format`,
  `join`, `toJSON`, `fromJSON`, null-coercion comparisons (`== null` / `== ''`), `||`
  short-circuit — `contains` itself has never executed on this instance at any level.
  The same binary evaluates them at step level, and
  `contains(fromJSON('["one","two"]'),'one')==true` + `env.NULL==null==true` are
  Forgejo-CI-conformance-proven at step level [E2E example-expression] — but **no job
  `if:` using any function has ever run on either lab instance** (X §2 sharpener stands).
- *Documented only*: the availability-table per-field lists [D15]; the docs' step-level
  `format`/`contains` examples.
- *Unusable/avoid at job level*: `hashFiles` (runner-Node; server-side WorkingDir=""),
  `case()` (exists only in the deployed runner v13, not in the server's pinned
  evaluator — expressions the server evaluates would reject it), `jobs` context at job
  level (`Unavailable context: jobs` unless workflow-call [R12 interpreter.go L176-180]).

**Ranked safe membership spellings** (guard-clause first, evaluated left-to-right):

1. `if: vars.ROLE == null || contains(vars.ROLE, 'prod')` — comma list `dev,prod`,
   JSON-ish string, spaced `dev, prod`, `PROD` case: all membership-true; unset/`''` ⇒
   widest; **nothing in the grammar can make it error** (contains never errors; `== null`
   never errors). Substring is unambiguous *because* the vocabulary is {dev, prod}
   (`prod` never a substring of `dev` and vice versa) — a new role word like
   `production` would break it. Source-proven semantics, instance-unexercised at job level.
2. Same expression at **step** `if:` (job always runs) — identical semantics, and the
   conformance-proven evaluation path [E2E]; cost: job shows green-but-empty instead of
   a gray *skipped*.
3. `if: vars.ROLE == null || contains(format(',{0},', vars.ROLE), ',prod,')` — exact-token
   membership, null→`',,'` no error; **breaks on spaces inside the list**
   (`dev, prod` → `,dev, prod,` misses `,prod,`). Untested on this build.
4. `if: vars.ROLE == null || contains(fromJSON(vars.ROLE), 'prod')` — requires the
   variable to be exactly `["dev","prod"]` JSON; unset/`''` covered by the short-circuit,
   but a **non-JSON value (e.g. a plain `dev,prod` typed by hand) turns every guarded
   job red**. Untested; strictest input contract.
5. Gate job (job-level `if` avoided entirely): always-run `gate` job computes the verdict
   in shell (`ROLE=${ROLE:-dev,prod}` + `case ",${ROLE// /}," in *,prod,*)`), emits it via
   `$GITHUB_OUTPUT` [D15 reference.md matrix example L740-770 — documented+conformance-
   used], downstream `if: needs.gate.outputs.run_prod == 'true'`. Every construct is in
   the proven subset (`==` on a `needs.*.outputs` string — context row in D15; `needs`
   outputs demonstrably reach the server-side payload re-parser [F15
   `services/actions/job_emitter.go` L313-318, L581-590]); unset logic is pure bash. Costs
   an extra job + `needs` hop; no `needs`-gated job has ever run here (X: only main-sync's
   two independent jobs have executed).
6. The current `vars.ROLE == 'prod'` — proven subset, but **narrowest on unset** and
   broken for any list value (fails the owner's ruling).

### 2. Unset / absent variable semantics, and "unset = widest"

At **job level**, an absent variable is a map-miss ⇒ **null** (§1). Because the engine
number-coerces mismatched kinds (null→0, `''`→0): `vars.ROLE == null` and
`vars.ROLE == ''` are **both true for unset**, also for set-but-empty, and false for any
real value (`'prod'`→NaN≠0) [R12 interpreter.go L515-588]. A whitespace-only value
(`' '`) parses to NaN vs `''`→0 ⇒ `== null`/`== ''` are **false** — a lone space is
neither unset nor empty to this engine (guard it shell-side or keep the UI value tidy);
likewise `'prod '` (trailing space) fails `== 'prod'` but passes `contains`.
In `run:`/`env:`, unset interpolates to **empty string** (force-format coercion +
interpolate-error→`""`) [R13 `expression.go` L377-395] — so `env: ROLE: ${{ vars.ROLE }}`
+ `ROLE=${ROLE:-dev,prod}` is deterministic bash territory (X rank-1 note stands).

The idioms for "unset = widest (dev,prod)": the null-clause spellings ranked 1/3/4 above
(the clause may lead or trail for `contains`/`format` — order only matters for `fromJSON`,
whose right-hand error must be short-circuited *behind* the guard); and the shell-default
idiom (rank 5 / in-job `case`), which additionally absorbs whitespace. There is **no
`??`/coalescing operator and no default function** in the engine [R12 function switch].

"Unset = nothing runs" — what `vars.ROLE == 'prod'` actually gives: main's
`main-sync.yaml` header says "An unset ROLE renders empty and fires nothing too
(fail-safe)" [REPO `git show main:.forgejo/workflows/main-sync.yaml` L5-6]. Precisely:
the run is still *created* on matching triggers, the guarded job is dispatched as a
runner task, evaluates false, and is marked **`skipped`** — not failed, not silently
absent [R12 `run_context.go` L1091-1094; observed shape: the 18 `backup-proxy-merge`
skipped rows in the public tasks API, X fact 12]. A false `vars`-guard branch has never
been observed here (infra ROLE=prod ⇒ always true, X), but the skip mechanism is the
identical `isEnabled` path the URL guards used. Run-level aggregate: all-skipped ⇒
`skipped`; success+skipped ⇒ `success` [F15 `models/actions/run_job.go`
`AggregateJobStatus` L255-286]. So "nothing fires" is right about *effects* and wrong
about *artifacts* (a run row, a dispatched task, a green status all still happen) — and
its polarity is exactly what the owner overruled for ROLE.

### 3. Variable scope and precedence (v15.0.10 — two EXPLORE corrections)

Code merge order in `GetVariablesOfRun`: **instance-Global + Org/User + Repo, last-write
wins ⇒ Repo > Org/User > Global**, with an explicit source comment
`// Level precedence: Repo > Org / User > Global` [F15 `models/actions/variable.go`
L110-144]. Same shape for secrets (`append(ownerSecrets, repoSecrets...)` — repo wins;
no global secrets scope at all [F15 `models/secret/secret.go` `FetchActionSecrets`;
`routers/web/web.go` — the `/admin` Actions group gets runners+variables but **no**
secrets routes]). Consequences:

- **Correction to EXPLORE §2 rank-1**: an instance-global Actions-variable scope **does
  exist** on this build (introduced upstream by commit `d0f24ff4c` "Added instance-level
  variables", Gitea history 2023-12, unchanged since [Codeberg commits API on
  `models/actions/variable.go`]). It is editable **only** in the site-admin web UI —
  route group `/admin/actions` + variables (`routers/web/web.go` L745+/L847-852), i.e.
  `https://git.spencerslab.com/admin/actions/variables` (owner-leg; UI paths: user
  `/user/settings/actions/variables` L601+/L690-696, org `/org/{org}/settings/actions/variables`
  ~L999, repo `/{owner}/{repo}/settings/actions/variables` ~L1187) — there is **no REST
  endpoint for it** (swagger paths are only `/repos/{owner}/{repo}/actions/variables`,
  `/orgs/{org}/actions/variables`, `/user/actions/variables`, GET+CRUD-by-name
  [F15 `templates/swagger/v1_json.tmpl`; `routers/api/v1/api.go` L497, L662]) and the
  v15.0 docs list only the three non-global scopes [D15 basic-concepts L127-133].
- **Correction to EXPLORE §2** ("owner-level ROLE silently outranks a repo ROLE"): the
  code and Gitea's own doc page say the opposite — **repo beats org/user** [GD
  "A repository variable will always be chosen over an organization/user variable"].
  The v15.0 Forgejo doc sentence "A variable found in the settings of the owner … has
  precedence over … a repository" [D15 basic-concepts L155] is the outlier and matches
  no code path I can find; weigh it as a docs bug, but note it as a live contradiction
  (§Contradictions) and let the first probe settle it (set org+repo values, re-run a
  main-sync `workflow_dispatch`, read the diag echo — owner-leg, main-sync already has
  the echo step).
- Name rules are enforced in code at creation: pattern `^[A-Za-z_][A-Za-z0-9_]*$`,
  prefix ban `FORGEJO_|GITEA_|GITHUB_|digit`, `CI` banned, and the name is stored
  **uppercased** [F15 `services/actions/variables.go` `CreateVariable` L17-30;
  `models/secret/secret.go` L20-24; `models/actions/variable.go` L53]. `ROLE` is legal.
- Deployment meaning: a repo variable is a per-instance DB row (repo *content* syncs
  across the two servers via main-sync, variables do not), so "two servers, one role
  each" = set `ROLE=dev`/`ROLE=prod` as **repo variables on the respective instance**
  (the live cf-119 pattern, X), and "one server, both roles" = a single `ROLE` covering
  both (the owner's unset-default). The instance-global scope is the place to pin a
  whole-fleet default **only if** you want it overridden nowhere — but a repo-level ROLE
  always wins over it, so for a two-role *server* whose repos shouldn't all need a repo
  variable, the global scope holds the value and any repo variable silently overrides it.
  No mutation performed here (readonly posture + owner owns instance settings).

### 4. Trigger-vs-job reality

`on:` is not conditionable: the trigger-matching layer is pure event-kind + branch/tag/
path matching (`matchPushEvent`, `matchPullRequestEvent`, … in F15
`modules/actions/workflows.go` L231-748; the parsed `Event` is
`{Name, acts map[string][]string, schedules}` — no expression field [R12
`act/jobparser/model.go` L236-252]); the docs `on.push`/`on.pull_request` sections
document only `branches`/`paths`-style filters [D15 reference.md L67+]; and the
availability table has no `on.*` row except the two `on.workflow_call.*` ones [D15].
So both `push` and `pull_request` stay declared, and the ROLE split can only live in
job `if:` (optionally ANDed with `github.event_name == 'pull_request'` — `forgejo`/
`github` context is available in job `if:` per the same row). Consequences to design around:

- A PR run on the **prod-only** server *runs the workflow* and creates one runner task
  per gated job; each false guard costs a dispatch + a few seconds and lands **skipped**.
  It never "fails" and never "doesn't exist" — a run row with all-skipped jobs shows run
  status `skipped` [F15 `AggregateJobStatus`]. Same for a `push`-to-main on a **dev-only**
  server: the push publishes nothing and the run aggregates to `skipped` — i.e.
  **skip-and-succeed is exactly what the platform gives you for free**; the design choice
  is only *job-level skip* (gray "skipped", per-job commit status green) vs *in-job shell
  gate* (green-but-empty run).
- Required status checks exist on this build (`StatusCheckContexts` on protected
  branches, glob-matched, worst-status-wins, unmatched-required-context ⇒ *pending*
  [F15 `routers/web/repo/pull.go` L716-748; `services/pull/commit_status.go`
  `MergeRequiredContextsCommitStatus` L23+]). Actions report a per-job commit status
  `<workflow name> / <job name> (<event>)`, and the status mapping sends **`Skipped` →
  success** [F15 `services/actions/commit_status.go` context/format + `toCommitStatus`
  L153-165]. So a ROLE-skipped job *satisfies* a required check naming it — if the plan
  ever wants "the PR builder is required on dev servers", note the check goes green even
  when the job skipped; the check is Pending only if no job with that name ever appears.
- Fork PRs (not the lab's current flow — internal PRs): secrets arrive empty except the
  automatic token, so any PR-triggered publish job gated on a secret would fail, not
  skip [F15 `services/actions/secret.go` L45-49].
- **Runner dependency**: skipping happens *on the runner*. On an instance whose runner
  never picks up tasks (the dev instance's current zero-task state, X §6), false-gated
  jobs stay `Waiting` and the run never completes — the ROLE guard is not a way to make
  a runnerless server "skip cleanly"; the trigger still needs a runner to conclude
  anything.
- `concurrency` **can** use `vars` (evaluated at creation with only `forgejo`/`inputs`/
  `vars`, non-fatal on error) [F15 `notifier_helper.go` L419-422 + D15 concurrency row],
  so role-scoped concurrency groups remain available.

### 5. The in-repo precedent as a constraint

`main`'s shipped convention [REPO `git show main:.forgejo/workflows/main-sync.yaml`
(commit `b482935ed`)] — both push jobs guard the exact bytes `if: vars.ROLE == 'prod'`;
a diag step echoes `ROLE=${{ vars.ROLE }}`; destinations/credentials come from
instance-side `vars.PUSH_URL_{GH,DEV}` / `secrets.PUSH_TOKEN_{GH,DEV}`; zero URL
literals; header documents "unset ROLE … fires nothing (fail-safe)" and the ping-pong
rationale. The contract suite pins it byte-exactly: t2 `on:` == {push[main],
workflow_dispatch}; **t3** `GUARD = "vars.ROLE == 'prod'"` on *both* jobs via parsed-YAML
exact equality, an explicit ban on any `vars.ROLE == 'dev'` job ("the dev stage must
fire nothing") and a ban on `forgejo.server_url`; t4 no-force; t5 each `PUSH_URL_*`/
`PUSH_TOKEN_*` exactly once under its own job, no `https://` host literal, no
reserved-prefix keys, no automatic token for pushes; t6 `set -euo pipefail` everywhere;
t7 lab runner labels; t8 push-dev hygiene [REPO
`git show main:tests/services/forgejo-main-sync.sh` — t3 block L74-99, t5 L133-161,
236 lines total].

For the owner's "ONE repo-wide convention", the facts:
- Adopting `vars.ROLE == 'prod'` verbatim into `containers-build.yaml` **cannot** satisfy
  "ROLE list + unset=widest": `==` rejects every list value, and unset ⇒ narrowest
  (nothing publishes) — the documented opposite of the card's ruling.
- Adopting the widest spelling (`vars.ROLE == null || contains(vars.ROLE, 'prod')`,
  R1 §1 rank 1) into **both** files *does* satisfy the card for containers, but flips
  main-sync's deliberate fail-safe: on an instance with ROLE unset both push jobs would
  fire — `push-gh` to GitHub (wanted once, silently wrong anywhere else) and `push-dev`
  to whatever `PUSH_URL_DEV` happens to exist (or fail red if unset); the dev-stage
  ping-pong breaker that main-sync's header and t3 exist to enforce becomes "unset dev
  servers push main out". That is a real, owner-visible trade-off — a convention change
  for one file's convenience vs two documented safety properties; nothing here decides
  it.
- A middle path the facts support: **one spelling convention, per-file polarity
  documented** — e.g. every ROLE guard is a membership test with an explicit default
  clause chosen per file (`containers-build.yaml` widens on unset; `main-sync.yaml`
  keeps `vars.ROLE == 'prod'`, i.e. stays narrow on unset), with the polarity stated in
  each header and pinned by each suite (main-sync t3 unchanged; the containers suite pins
  its own guard bytes the way t3 pins main's). This keeps "one convention" true at the
  *shape* level (list-membership + explicit default clause + diag echo) while preserving
  cf-119's ruling; the strictest reading of "one convention" (identical default
  everywhere) costs the fail-safe above.
- `contains` is case-insensitive substring (R1 §1), so the substring spelling would make
  `ROLE=Production` pass a `prod` guard — if byte-exactness of the convention matters to
  the owner, the padded `format` form (rank 3) or the gate-job form (rank 5) is the
  exact-token option.
- Live caveat to carry into any convention: on this instance the ROLE-era guard's false
  branch has **never executed** (X fact 12), so whichever spelling lands, the first run
  after merge is the real test — the diag-echo step main-sync already ships is the
  pattern to replicate, and `workflow_dispatch` (used 5× on infra, X) is the cheap
  first-shot vehicle.

### Contradictions (docs vs source vs EXPLORE) — how to weigh

1. **Precedence**: Forgejo v15.0 docs say owner>repo [D15]; code says repo>owner>global
   [F15 variable.go L139], Gitea docs agree with the code [GD]. Weigh: **source** (it is
   what runs); confirm with the dispatch-echo probe before relying on overlapping scopes.
2. **Instance scope**: docs list 3 scopes, code+admin UI provide 4 (no API, no v15 docs).
   Weigh: source; EXPLORE's "no instance-global scope" is true only of the docs.
3. **Who evaluates job-`if`**: EXPLORE inferred the server; source shows the runner at
   dispatch, with the server evaluating only matrix/runs-on/name/concurrency/workflow-
   call templates. Weigh: source. Practical effect: a job-`if` expression *error* fails
   the dispatched job (red), whereas an error in `runs-on`/`name`/matrix fails the whole
   run at creation (`ErrorCodeJobParsingError`, run→failure [F15
   `notifier_helper.go` L444-452]).
4. **Cast table** (`null → ''`) vs source (`null` compares equal to `''` *and* to
   `null`; formats to `''`): consistent in effect; EXPLORE's `env.NULL == null` citation
   checked against the conformance file [E2E] ✓.

### §Options

- **O1 — Substring+null-guard everywhere with per-file polarity** (R1 §1 rank 1;
  containers widens, main-sync keeps `== 'prod'`).
  Cost: two guard spellings coexist (shape-convention, scoped polarity); substring
  semantics depend on the {dev,prod} vocabulary.
  Proves: unset-widest, list-, case-, whitespace-tolerant, **cannot error on any input**;
  every construct is source-proven in the single deployed engine, and its neighbours
  (`==` on vars, `startsWith` blocking) have live history on this instance — `contains`
  itself does not yet.
  Unverified: first job-level `contains` execution on v13.2.0 runner (one dispatch
  settles it); false-branch reporting of a *function* guard.
- **O2 — Gate job + shell `case` + outputs** (rank 5).
  Cost: extra job + `needs` hop in every workflow; `needs`-job gating never exercised
  here; two more payload hops that can each fail oddly.
  Proves: all unset/whitespace logic in bash (deterministic); guards themselves use only
  `needs.*.outputs == 'true'` (docs-listed context; conformance-adjacent via the matrix
  example); works even for future logic too complex for expressions.
  Unverified: `needs`-gated job skip behavior + commit-status shape on this build.
- **O3 — JSON-list convention (`ROLE='["dev","prod"]'` + short-circuited fromJSON)**.
  Cost: strictest input contract — a hand-typed `dev,prod` turns every guarded job red;
  org/repo variable values get uglier; two instances must agree on JSON.
  Proves: exact-token membership, no substring accidents.
  Unverified: fromJSON in job-`if` on this instance; the failure UX when the value is
  malformed (red job, not a hint — operators will trip).
- **O4 — Keep `vars.ROLE == 'prod'` repo-wide and accept unset=narrowest**.
  Cost: contradicts the card's explicit unset=widest ruling for containers-build
  (documented as such, or by a fresh owner ruling).
  Proves: byte-identical to the only convention with live execution history here
  (15/15 runs).
  Unverified: nothing new — but it simply doesn't meet the ask.
- **Probe (either way)**: one `workflow_dispatch` echo+guard workflow on infra printing
  `ROLE`, `[null]`, `contains`, `format-padding` and `fromJSON` verdicts into one diag
  step converts every "source-proven, instance-unexercised" row above into observed fact
  before the real workflow ships (dispatch is proven working: 5 dispatch runs, X; the
  step-level functions are conformance-proven [E2E]).

### §Open questions for planning

1. **Polarity unification**: does the owner want literally one identical guard semantics
   repo-wide (then main-sync's unset fail-safe + dev-stage breaker change — a
   cf-119-scoped decision) or one *shape* with per-file default clauses (O1 middle
   path)? Best guess: the latter; state the polarity per file in headers + suite legs.
2. **List syntax the owner will actually type** into the variables UI: `dev,prod` vs
   `dev, prod` vs `["dev","prod"]`? Best guess: `dev,prod` (no spaces) — which makes O1
   the safest spelling; if the owner prefers JSON, switch to O3 and add a header note
   that malformed values fail jobs.
3. Needs-research-sharpener (cheap probe settles): first execution on this instance of
   any function call inside a job `if:` — including whether the skipped rows appear
   identically in the tasks API (`skip` vs `skipped` shape is observed for the old
   guard; assume identical since the same `rc.result("skipped")` call emits it [R12]).
4. Needs-research-sharpener: the precedence contradiction (§Contradictions 1) — worth
   one org+repo overlapping-value dispatch before the plan *relies* on repo-over-org;
   if the plan never overlaps scopes for ROLE, skip it.
5. Should the ROLE guard ALSO cover `workflow_dispatch` runs (dispatch on a prod-only
   server currently runs *everything* — main-sync's guard applies to dispatch too:
   `if:` doesn't distinguish the event; the containers pre-ROLE design used the same
   guard for dispatch smoke)? Best guess: yes — guards stay event-blind; the event
   split (`event_name == 'pull_request'` for the dev/PR leg) is orthogonal and lives in
   the same guard clause family.
6. Whether instance-global variables should hold any ROLE at all: they are UI-only
   (no API), undocumented on v15, and repo-scoped values silently outrank them — best
   guess: keep ROLE at repo scope (the cf-119 pattern) and leave the global scope
   unused, so precedence can never surprise.
7. Does the owner consider the skipped-job green commit status acceptable under the
   "no direct URL references" + ROLE regime (a required context naming the container
   builder would pass vacuously on a server where it always skips)? Best guess: it is a
   note, not a blocker — no required status checks are known to be configured on the two
   forge repos (instance-side settings, owner-leg to confirm), so the vacuous-green
   effect is currently hypothetical.

## R2 — Forgejo registry push identity, package limits, and dual-registry tag derivation

TL;DR (R2, read first):
1. **The Actions job token cannot push containers on the deployed build.** `forgejo.token` IS accepted
   by the registry's Basic flow (it's the 40-hex task token, and `/v2` mounts the full Basic method),
   but it authenticates as the synthetic `forgejo-actions` user (ID −2), and the package access-mode
   function carries a literal `// TODO: ActionUser permission check` — no package write path exists
   (source below). A working push needs a **human-minted PAT** (unscoped `all`, or scoped to include
   `write:package`) owned by an identity with write access to the URL's owner (org member write/admin).
   **Deploy tokens are not wired into package auth at all on this tree.** `docker login -u` username
   is *ignored* by Forgejo (the identity is the token found in the password field).
2. **Naming**: `<host>/<owner>/<image>`, owner = user or org (never repo), owner segment looked up
   case-insensitively, image + tags stored lowercase; image names lowercase-only with `.`/`_`/`-`
   separators and nesting allowed. Pushing **auto-creates** the package; a package has **no own
   visibility** — readability inherits from the owner account's visibility (public org ⇒ anonymous
   pull works today via the ghost token; measured). `ownyourio` **does not exist as a user/org on
   either lab instance** (probed) — mirroring the ghcr name verbatim needs that account created, or
   use `CuratedForest` (exists, publicly visible via API).
3. **Limits are unlimited by default; over-limit fails the push, nothing is evicted** (403 quota
   errors on manifest/blob routes; a Forgejo `[quota]`-model middleware answers 413, disabled by
   default). The nightly `cleanup_packages` cron only GCs *unreferenced* data — **tagged versions,
   including `pr-*`, are deleted only by per-owner Cleanup Rules** (UI/DB regex policy; `latest` and
   digest refs protected by code). GHCR has **no** retention feature at all (deletion is manual UI/
   REST, restore 30 d). So both registries accumulate PR tags until a human arms a rule/action.
4. **Re-pushing an existing tag on Forgejo silently OVERWRITES** it — the old package version is
   *deleted* and the tag re-inserted (`DeletePackageVersionAndReferences` + re-`GetOrInsertVersion`,
   HTTP 201). Same hazard GHCR has (GHCR still has no tag-immutability feature — per-repo immutability
   exists only for GitHub Releases, not GHCR). Cross-registry tag identity therefore requires deriving
   N from the **union (max)** of both registries and existence-**walking both before pushing either**.
5. **Reachability**: gpu-runner egress to `git.scifi.farm:443` (the dev instance) is *proven* by the
   push-dev successes and shares host+port with the dev registry path; no NetworkPolicy on either
   cluster touches the runner pods; the dev node pulled its runner image from `data.forgejo.org`
   (internet egress exists). "Local registry" most naturally reads as *the executing instance's*
   registry (Reading A); pushing prod builds across into the dev registry (Reading B) is mechanically
   possible but needs a cross-instance PAT stored on the other server.
6. **Half-succeeded two-registry pushes never corrupt already-published tags IF (and only if)
   derivation sees both registries.** Deriving from the lagging side re-mints a tag the leading side
   already holds and silently overwrites it there — on GHCR by retarget, on Forgejo by delete+reinsert.
   With union-derive + walk-both, arm order cannot overwrite anything; it only decides which side a
   failure leaves a *gap* on (ghcr-first ⇒ the forge side lags; forge-first ⇒ ghcr can run ahead —
   which is the state that later ghcr-only derivations would clobber).

Evidence keys (R2) — every claim cites one of these:

- **[F15]** Forgejo v15.0.10 source at tag `v15.0.10` (same tree as R1: commit
  `17e1001d5e00e8ee3cbc1b6dd31be94ac38185f9`); re-fetched this session
  `https://codeberg.org/forgejo/forgejo/archive/v15.0.10.tar.gz`, sha256
  `4c859952ed3a31c5da92f694d40ca0b9af296afa1b9c72ed9686b800647e9614`. File+line refs below are in
  that tree.
- **[D-C]** `https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/packages/container.md`
  (fetched this session; 104 L). **[D-I]** `…/docs/user/packages/index.md` (172 L).
  **[D-CS]** `…/docs/admin/config-cheat-sheet.md` (1444 L; §“Packages (`packages`)” L1291+,
  §“Cron - Cleanup expired packages (`cron.cleanup_packages`)” L984+).
- **[SPEC]** OCI/distribution token-auth spec,
  `https://distribution.github.io/distribution/spec/auth/token/` (fetched this session).
- **[GH-R]** GitHub REST “packages” docs, `https://docs.github.com/en/rest/packages/packages`
  (delete/restore version semantics, `delete:packages` scope); **[GH-D]**
  `https://docs.github.com/en/packages/learn-github-packages/deleting-and-restoring-a-package`;
  **[GH-I]** community discussion #181783 “Immutable image tags in container registry”
  (`https://github.com/orgs/community/discussions/181783`, opened 2025-12: GHCR has no tag
  immutability, “a pushed tag can always be retargeted”; GitHub's own “immutable releases” GA
  (changelog 2025-10-28) covers Releases/assets, **not** GHCR container tags).
- **[LIVE]** read-only HTTP probes run 2026-11-11 in this session (anonymous; two of them against
  `/v2/token` with a fixed dummy/zero-scope credential — no mutation anywhere).
- **[K8S]** readonly cluster MCP observations this session (`readonly-{gpu,dev,infra}-kubernetes`
  `pods_get` / `resources_list` — namespace `default` throughout; **no pod exec performed** — the MCP
  tier forbids it, so runner-inside facts are owner-leg commands in §5).
- **[R1]** RESEARCH.md R1 in this folder; **[X]** EXPLORE.md in this folder; **[RUN0]** this branch's
  `.forgejo/workflows/containers-build.yaml` + `scripts/forgejo-container-detect.sh`;
  **[REPO]** `main`'s `.forgejo/workflows/main-sync.yaml`.

### 1. Push identity for the container registry from Actions

**The handshake (measured, source-conformed).** `GET /v2/` with no credential answers 401 with
`Docker-Distribution-Api-Version: registry/2.0` + `Www-Authenticate: Bearer realm="https://<host>/v2/token",
service="container_registry", scope="*"` ([X] fact 13; writer = `APIUnauthorizedError` [F15
`routers/api/packages/container/container.go:117-123`]). Per [SPEC] the docker client then re-sends
its stored credential **as Basic auth to the realm URL** (`/v2/token`) and uses the returned Bearer
JWT for the API calls. Forgejo's `Authenticate` [F15 container.go:148] **ignores the requested
`scope=` parameter**: it mints the JWT for `ctx.Doer` (anonymous → Ghost −1) via
`CreateAuthorizationToken(u, scope)` whose scope claim is the **credential's own API scope** (or
empty), never the requested repo scope [F15 `services/packages/auth.go:27-46` — HS256 on the general
token-signing secret, `exp = 24 h`, claims `{UserID, Scope}`]. Live: anonymous requests with
`scope=repository:…:pull` and with `…:pull,push` returned the *byte-identical*
`{"UserID":-1,"Scope":""}` JWT [LIVE], exactly as the source predicts (R1's scout had seen the
pull-side token; the push-scope equivalence was unmeasured). A **bad Basic credential at the token
endpoint yields 401 + the same Bearer challenge** [F15 `verifyContainerAuth`
`routers/api/packages/api.go:148-181`; measured [LIVE]] — invalid logins fail *before* any JWT,
and every subsequent `/v2/<owner>/<image>/...` request re-checks the access mode against the URL
owner (no scope narrowing happens in the JWT).

**The /v2 auth stack** is `verifyContainerAuth(r, [Basic, container.Auth])` [F15 api.go:839-841]:
`Basic` (the *full* API Basic method — enabled on `/v2` paths via `isContainerPath`, [F15
`services/auth/method/basic.go:44-46`]) plus the Bearer-JWT decoder [F15
`routers/api/packages/container/auth.go:43-71`]. The API's `OAuth2` bearer/token method is **not**
mounted for `/v2`, and `POST /v2/token` (the OAuth flavor) is a deliberate 404 stub [F15
container.go:174].

**What each credential does through `Basic.Verify`** [F15 basic.go:42-151, verified line-by-line]:

| Credential sent as Basic to `/v2/token` | Verdict on 15.0.10 |
|---|---|
| `<anything>:<PAT>` | ✅ authenticated — the **token is looked up in the password field; the username is never checked** (L59-90: `authToken = passwd`, `GetAccessTokenBySHA` → identity = token owner). Empty password with `<PAT>` as username also works. |
| `<anything>:<OAuth2 access-token JWT>` | ✅ via `CheckOAuthAccessToken` (L71-89; falls back to scope `all` when the grant has none) |
| `<user>:<password>` | ✅ only while `[service] ENABLE_BASIC_AUTH` (default true; L120-150) — TOTP can only ride the `X-Forgejo-OTP` header, WebAuthn users are rejected; **2FA/OTP users must use a PAT** [D-C: “If you are using 2FA or OAuth use a personal access token instead of the password”] |
| `<x>:<40-hex task token>` | ✅ authenticates — but as the **synthetic Actions user** (below) |
| deploy token (any form) | ❌ **not accepted**: `GetDeployTokenBySHA` has zero callers under `routers/`+`services/auth` in this tree (grep, [F15]); the package handlers contain no `DeployToken` logic either — deploy tokens exist for git here, **not for packages** |
| `Authorization: Bearer <forgejo.token>` | ❌ the /v2 stack has no OAuth2 method; `container.Auth` verifies HMAC against the *general* signing secret only → incorrect-credential → 401 |

**The job-token verdict — authenticates, cannot write (this resolves the repo-vs-owner-scoped doc
conflict from source).** The value behind `${{ forgejo.token }}`/`github.token` is the task's DB
token: `secrets["FORGEJO_TOKEN"] = task.Token` [F15 `services/actions/secret.go:24`], generated as
`hex(CryptoRandomBytes(20))` — a 40-hex string [F15 `models/actions/utils.go:20-25`] — exactly the
shape `GetRunningTaskByToken` requires [F15 `models/actions/task.go:196-235`, which also filters
`status = StatusRunning` — the credential dies with the job]. `Basic.Verify`'s task branch
[basic.go:113-120] accepts it and returns the identity **`user_model.NewActionsUser()`** — a synthetic
non-DB user ID **−2**, name `forgejo-actions` [F15 `models/user/user_system.go:55-79`]. From there:

- package context resolution runs `UserAssignmentWeb → PackageAssignment → DeterminePackageAccessMode`
  [F15 api.go:1010; `services/context/package.go:57-66`, `services/context/user.go`
  (`UserAssignmentWeb`/`userAssignment` → `user_model.GetUserByName`, lowercase ⇒ case-insensitive)];
- `DeterminePackageAccessMode` [F15 `services/packages/perm.go:18-77`] contains the literal comment
  **`// TODO: ActionUser permission check`** (L27) and has **no branch granting the Actions user
  anything**: for an org owner it queries `org_user`/teams for `doer.ID = −2` (none exist) and falls
  back to *public-visibility read*; for a user owner, only `doer.ID == owner.ID` (impossible) or the
  owner's public visibility → read.
- writes additionally pass `reqPackageAccess(AccessModeWrite)` [F15 api.go:48-92]: the task-token
  result carries **no scope** [F15 `services/auth/method/auth_result_actionstask.go:21-23`] so the
  scope gate is skipped, then `ctx.Package.AccessMode < write && !IsUserSiteAdmin()` (api.go:89) →
  **401** (`Basic realm="Gitea Package API"`).

So the docs' “the automatic token … has write permission to the repository” [X fact 11, docs
basic-concepts] is about the **git/API repo surface**; packages are owner-scoped objects [D-I access
table] and the Actions identity has *no* repository-derived package privilege at all — it can at most
**pull** what is publicly visible (read via ghost-equivalent visibility rules). The conflict is not
“repo-scoped vs owner-scoped packages” — the job token is simply **not a package credential on
v15.0.10**. (It is a *pull* credential for public images, incidentally.)

**What a working push needs.** A regular access token (PAT) owned by a user who can write the target
namespace [D-I “Access Restrictions”: org packages → “org members with admin or write access to the
org” [X fact 17]; enforced per-request through `DeterminePackageAccessMode`]. The PAT's scope must
satisfy `write:package` when the token is scoped [F15 api.go:52-70 +
`models/auth/access_token_scope.go:74-75`, where `all` contains every scope (test L57)]; an
unscoped/legacy-all token passes trivially (Basic falls back to `AccessTokenScopeAll` for grants
without scope, basic.go:83-87). **Do not use a site-admin token**: `reqPackageAccess` lets site
admins bypass the access-mode check entirely (api.go:89) — an admin PAT would be able to write any
namespace on the instance. There is no deploy-token or job-token route, and no config knob changes
any of this (`ENABLED` only turns the registry off [F15 `routers/init.go:188-192`]).

**Concrete login shapes** (mirroring [RUN0]'s ghcr step L113-119 and [REPO]'s secrets convention —
instance-side secrets, zero literals):

```sh
printf '%s' '${{ secrets.FORGE_PUSH_TOKEN }}' | docker login "$forge_host" -u <token-owner-name> --password-stdin
# ghcr side unchanged:
printf '%s' '${{ secrets.GHCR_PUSH_PAT }}'    | docker login ghcr.io -u OwnYourIO --password-stdin
```

`-u` is **cosmetic on the forge side** (ignored — see table); use the token owner's name for readable
logs. GHCR *does* require the PAT owner's username, and the existing step already ships it [RUN0].
`$forge_host` must be derived, not literal — `${{ forgejo.server_url }}` is documented + source-backed
(server sets `ServerURL: setting.AppURL` [R1 §“job context”, F15 `services/actions/context.go:68`]),
so `rest="${forgejo.server_url#https://}"` in a step mirrors [REPO]'s `rest="${PUSH_URL#https://}"`
pattern; the alternative is a per-instance `vars.REGISTRY_HOST` following the `PUSH_URL_*` convention
(§Options O5).

### 2. Image naming, package creation, visibility

- **Form** `{registry}/{owner}/{image}[:tag]`; registry = the instance domain; `{owner}` is a **user
  or org, never a repository** [D-C §naming; D-I access table; X fact 17]. Image segment regex
  `\A[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*\z` [F15 container.go:32
  `imageNamePattern`, enforced by `VerifyImageName` L132-136] — **lowercase only**, single-char
  `.`/`_`/`-` separators, nesting allowed (`testuser/my/image` is a documented valid example [D-C]).
  Our container-dir names (`wekan-mcp` …) are exactly this shape (the [RUN0] detector gate is
  strictly narrower — good).
- **Owner segment**: resolved by `GetUserByName` on the lowercase name [F15
  `services/context/user.go` `userAssignment`] — case-insensitive; `CuratedForest` and `curatedforest`
  are the same owner (docker clients lowercase anyway).
- **Tags**: accepted as `[A-Za-z0-9_][A-Za-z0-9._-]{0,127}` **or a digest** [F15
  `services/packages/container/manifest.go:39,76-90`], but **stored lowercase**
  (`Version/LowerVersion = strings.ToLower(reference)`, manifest.go `_pv` block ~L446-452; docs: “The
  registry only supports case-insensitive tag names” [D-C]). Our tags (`26.11.1`, `latest`, `main`,
  `pr-*`) are already lowercase.
- **Push auto-creates the package**: the manifest upload calls `TryInsertPackage` and continues on
  duplicate [F15 manifest.go:388-410 (`createPackageAndVersion`, container flavor)] — first push to
  `…/curatedforest/wekan-mcp:26.11.1` creates the org's `wekan-mcp` container package. No
  pre-creation step is needed (and none exists in the UI for containers).
- **Visibility defaults**: the package model has **no visibility field** — access is the *owner's*
  visibility (org public ⇒ anonymous read; org private ⇒ members only) [D-I access table; F15
  perm.go:53-56]. Consequence measured live: with the zero-scope ghost token, `GET
  /v2/CuratedForest/probe/tags/list` returned **404 `NAME_UNKNOWN`** (absent package, *auth passed*),
  and the org is publicly visible via API (`/api/v1/orgs/CuratedForest` → 200 both instances) [LIVE]
  — so a pushed `CuratedForest/…` image will be **pullable without credentials by anything that can
  reach the host** (subject to `service.REQUIRE_SIGNIN_VIEW`, unset in this repo's chart values [X
  §3]; app.ini itself is owner-leg-readonly-unreachable, [X] §3).
- **User vs org owner**: pushing into a *user* namespace requires being that user (or the account
  being public for reads); an *org* namespace requires org write/admin membership [D-I]. User-owner
  quirk: read for strangers hinges on the user account's *profile visibility* (`public`/`limited`
  branches, perm.go:59-70), which defaults private-ish — orgs are the predictable choice.
- **Mirroring the ghcr name `ownyourio/<image>`**: `ownyourio` **does not exist as a user or org on
  either instance** (API 404 + web 404 on infra, API 404 on dev [LIVE]). Either the owner creates an
  `ownyourio` account (registration is open: `DISABLE_REGISTRATION: false` [X fact 13] — a user
  signup, or an org via admin UI), or the forge side lives under **`CuratedForest/<image>`** (org
  exists, publicly visible [LIVE]) — then the two registries' *paths* differ (`ownyourio/…` vs
  `CuratedForest/…`) even with identical image/tag sets. Nothing in the forge registry constrains
  the *image* name otherwise.
- **Repo auto-link** (cosmetic, but affects the “Packages” tab and any future repo-scoped view):
  only on *first* creation, via `org.opencontainers.image.source` **whose host must equal the
  instance's AppURL** or via image-name-equals-repo-name [F15 manifest.go:588-663 —
  `tryAutolinkByLabel` host check ~L631-634, `tryAutolinkByImageName` ~L656+; D-C §“Linking an image
  to a repository”]. Our Dockerfiles carry **no such label** (grep `containers/*/Dockerfile` — zero
  hits), and there is no repo named `wekan-mcp`/`strata`/… under `CuratedForest` — so pushes land
  **unlinked**. (Unlinked is *not* deleted by anything — see §3.)

### 3. Package limits and retention on 15.0.10

- **`[packages]` keys** [D-CS §Packages L1291+; F15 `modules/setting/packages.go:13-49`]: `ENABLED`
  (default **true**; false unmounts `/v2` and the package UI [F15 `routers/init.go:188-192`]),
  `CHUNKED_UPLOAD_PATH`, `LIMIT_TOTAL_OWNER_COUNT` (**−1** = unlimited; max **versions** per owner,
  checked at version creation [F15 `services/packages/packages.go:368-387`
  `CheckCountQuotaExceeded`]), `LIMIT_TOTAL_OWNER_SIZE` and per-type `LIMIT_SIZE_CONTAINER` (**−1** =
  unlimited; missing key ⇒ `mustBytes` → −1 [F15 `modules/setting/config_provider.go:326-333`]).
  Both limit families are **skipped for site admins** (packages.go:369-371/393-395). Whether lab
  `app.ini` sets them is owner-leg ([X] §3 gives the read command) — defaults are unlimited.
- **Over-limit = push fails; nothing is evicted.** Version-creation quota errors map to **403** on
  the container routes [F15 container.go `UploadManifest` quota switch, `ErrQuotaTotalCount/
  ErrQuotaTypeSize/ErrQuotaTotalSize` → `StatusForbidden` (case at L551); same mapping in the blob
  upload routes, L278/L418]. Separately, every write route is wrapped by Forgejo's quota-model
  middleware, which evaluates against the **package owner** and answers **413** [F15 api.go:94-115
  `enforcePackagesQuota`]; that model is inert unless `[quota] ENABLED = true` (default **false**
  [F15 `modules/setting/quota.go` — `Enabled: false`], `EvaluateForUser` short-circuits true [F15
  `models/quota/quota.go:20-23`]). No config path silently deletes existing packages to make room.
- **Storage location**: default = instance `APP_DATA_PATH` (the PVC), not S3 — the repo keeps LFS-only
  S3 and warns that a `[storage]` section would move packages too [X fact 24]; no `[packages]`/
  `[storage]` storage keys in `services/{infra,dev}/prod/values.yaml` [X fact 24]. So forge-side
  bytes land on the forge PVC forever unless deleted.
- **What the nightly cron actually does** (`[cron.cleanup_packages]` ENABLED **true**, `@midnight`,
  `OLDER_THAN: 24h` [D-CS L984+; F15 `services/cron/tasks_basic.go:146-155`]) — two jobs in one
  [F15 `services/packages/cleanup/cleanup.go` `CleanupTask` ~L29-36]:
  1. `ExecuteCleanupRules` — deletes **versions** matched by per-owner **Cleanup Rules**;
  2. `CleanupExpiredData` — GC: expired/incomplete blob uploads, blobs not referenced by a manifest,
     dangling container manifests older than `OLDER_THAN` (`CleanupSHA256`), and *packages with zero
     remaining versions* (`FindUnreferencedPackages` = `package_version.id IS NULL`, [F15
     `models/packages/package.go:317-327`]).
  **This is what EXPLORE §3 meant by “unreferenced data only” — correct — but its “version deletion
  is a human UI action only” needs correcting: a version-deletion policy EXISTS, as owner-configured
  Cleanup Rules** (`PackageCleanupRule{Type, KeepCount, KeepPattern, RemoveDays, RemovePattern,
  MatchFullName}`, anchored case-insensitive regexes `\A…\z`, evaluated by the same cron, with a
  preview UI) [F15 `models/packages/package_cleanup_rule.go:25-38`, cleanup.go `GetCleanupTargets`
  ~L107-180; D-I §“Cleanup Rules” incl. regex examples]. For **containers**, rules skip only the
  literal `latest` version and digest/untagged refs — **every other tagged version, `pr-*` and
  calendar tags included, is deletable by a rule** [F15 `services/packages/container/cleanup.go`
  `ShouldBeSkipped` ~L83-95]. Rules are created per owner in the web UI (org/user Packages → Cleanup
  rules) — owner-leg; e.g. a rule Type=Container, RemovePattern `pr-.*`, RemoveDays 14 would reap PR
  builds nightly while `KeepCount` protects the newest few of anything.
- **Anonymous pull / `_catalog`**: no instance-wide anonymous switch exists [X §3]; but with the
  zero-scope ghost JWT, **`GET /v2/_catalog` returned 200 `{"repositories":[]}` on both instances**
  [LIVE] — the earlier “no catalog enumeration” measurement [X fact 14] held only for *tokenless*
  requests (which correctly 401-challenge). `GetRepositories` lists `<owner>/<image>` entries whose
  owner is *visible to the caller* (ghost ⇒ public owners) [F15
  `models/packages/container/search.go:250-290`]. So once pushed, our public-org images **will be
  enumerable and pullable anonymously** — including by the workflow's own tag-derivation reads without
  any credential (§4), and by anyone on any network that can reach the host.

**Consequence for the tag set**: `yy.mm.N` + `:latest` + `:main` on main and `pr-<branch>-<sha>` on
PRs will, over time, accumulate **without bound in both registries**: GHCR has *no* retention feature
(deleting a version is manual UI/REST with `delete:packages`; deleted versions are restorable for 30
days; public versions with >5000 downloads can't be deleted at all [GH-R][GH-D]) — the third-party
`container-retention-policy` Action ecosystem exists precisely because of this. Forgejo's default
cron **won't touch any of it** (all our tags are referenced; only `latest` is even protected — the
rest just need no rule). PR tags are currently GC-less *by design on both sides*; the new lever run
-1 can pin as an owner leg is a forge-side Cleanup Rule (§Options O6).

### 4. Two registries, one calendar tag

**Re-push semantics of each registry (the overwrite question):**

- **GHCR**: no immutability anywhere for container tags — “GitHub's immutable releases” (GA 2025-10)
  locks *Release assets + git tags*, not GHCR; community confirms “on GHCR … a pushed tag can always
  be retargeted” [GH-I]. Run 0 recorded the same [RUN0 header L9-15; X §4.4].
- **Forgejo 15.0.10** [F15 manifest.go:446-467 `createPackageAndVersion`]: on `GetOrInsertVersion`
  → `ErrDuplicatePackageVersion` it **deletes the existing version**
  (`DeletePackageVersionAndReferences` — “keep download count on overwrite”) and re-inserts the same
  tag; the handler returns **201 Created** [F15 container.go:516]. So a re-push of a taken tag is a
  **silent overwrite** (old version destroyed, tag now names the new digest), *not* a rejection and
  *not* an append-a-new-version. The docs sentence “You cannot edit a package after you have
  published it” [D-I] is generic-package prose that this code path plainly contradicts for
  containers — weigh source.

**`next-n` is registry-agnostic** (stdin = `{"name":…,"tags":[…]}` body; keeps `^yy\.[0-9]+\.[0-9]+$`
entries; `pr-*`/rolling/foreign months can't corrupt N) [RUN0 detect.sh:68-91]. Forgejo's `tags/list`
is body-compatible: `TagList{Name: ownerLower+"/"+image, Tags: […]}` marshalled compactly by
`jsonResponse` [F15 tags.go:16-37, container.go:668] — the detector's sed extracts the `tags` array
the same way; the `name` differs in style (`curatedforest/img` vs ghcr's `ownyourio/img`) which
`next-n` ignores. Still unexercised until a real package exists [X §4.2]. **Status codes**: absent
package ⇒ 404 `NAME_UNKNOWN` (already measured, ghost-token, [LIVE]) — and the shipped derivation
*only computes N from a 200 list and only walks inside that branch*, treating 401/403/404 as “no
readable tags → N=1, no walk” [RUN0 L158-191, t11 leg]. That tolerance is exactly what makes a
**forge-side read useless as overwrite protection** if it ever answers non-200 (§6).

**Policies the planner can actually choose** (registry behaviour from source + [X] §4):

| Policy | Mechanics | Keeps “main ⇒ same N in both” | Overwrite risk | Cost |
|---|---|---|---|---|
| P1 derive ghcr-only (run 0 as-is), push both | current `api=`/`token=` code once, forge arm reuses N | ✔ per *successful* build — until forge ever runs ahead of ghcr | **clobbers forge** in exactly that state (forge ahead ⇔ ghcr arm failed first) | free; both reads anonymous-capable |
| P2 derive forge-only | mirror of P1 | same | **clobbers ghcr** whenever ghcr runs ahead (the common half-fail if ghcr is pushed first) | free |
| **P3 derive union-max, walk both, then push** | `N = max(ghcr tags/list, forge tags/list) + 1`, then per registry `HEAD manifests/<month>.<N>` advance while 200 (tolerate 401/403/404 *per registry* only as “no tags here” when computing the max, but the walk must run wherever the list answered 200) | ✔ per successful build; failures leave **gaps** (N missing on one side), never clobbers | none (walk-before-push) | + one token/tags-list/walk per registry per image; reads work unauthenticated for public sides (ghcr pull-token path unchanged; forge ghost-JWT works while the org stays public — else reuse the push PAT for reads) |
| P4 per-registry independent N | derive+walk each side separately | ✘ — same digest gets different tags; Renovate pins ghcr, the forge UI shows another number | none | same cost as P3 but violates the owner ruling |

- **Race window**: same-workflow runs queue per instance (`concurrency.cancel-in-progress: false`
  [RUN0 L46-47]); the *cross-instance* race is dev-vs-infra writing the same forge-registry owner —
  under the owner's design only the **prod** instance runs the versioned arm, so each registry has a
  single writer workflow; the remaining window is dispatch-vs-push on the same instance, which the
  queue serializes [RUN0 header L17-21]. Two registries never disagree *because of a race* if
  P3 is used; they disagree only across a **failed** build (see §6).
- **Tag-set equality vs tag-identity equality**: nothing two-registry can do makes the tag *sets*
  equal after a half-succeeded run (no transaction across registries); the guarantee P3 buys is
  “every build that reports success published the *same* N everywhere it pushed.” Say this precisely
  in the plan/leg text.

### 5. Reachability and cross-instance pushes

Confirmed from the readonly cluster MCPs only ([K8S]; no exec):

- **Runner topology**: both runner pods are ordinary (non-`hostNetwork`) pods in `default`:
  `gpu-forgejo-runner-gpu-0` on node `gpu`, `dev-forgejo-runner-dev-0` on node `dev`, each
  `containers=[runner=data.forgejo.org/forgejo/runner:13.2.0]` + native-sidecar
  `initContainers=[dind=docker:29.9.2-dind]` (the k8s API lists dind under initContainers — that's
  why `kubectl` shows “2/2” while `containerStatuses` shows one [K8S]; EXPLORE fact 19's
  “2/2 = dind + runner” is consistent). Job steps run as sibling containers on the dind daemon →
  same pod netns → same egress path.
- **No NetworkPolicy touches the runners**: the 12 policies per cluster are the same ArgoCD set +
  `external-secret-2-bw-cli` on both gpu and dev (`argocd-*` names/selectors); none selects
  forgejo-runner pods and there is no namespace-wide default-deny [K8S `resources_list NetworkPolicy`
  per cluster]. So pod egress is unrestricted by policy on both clusters.
- **gpu runner (infra jobs)**: `git.scifi.farm:443` **proven reachable from job egress** (push-dev
  succeeded in runs 24-28, 31 [X fact 12]) — host+port identical to the dev registry path
  (`https://git.scifi.farm/v2/…`, the registry is a path on the same service [X fact 5]), so the
  dev-registry push from the prod runner is the same TCP path; app-level (`/v2/` handshake through
  that ingress) still **UNVERIFIED until first push** — same caveat EXPLORE §3/§5 gave for the
  instance's own registry. `ghcr.io` pull egress proven (job images) [X fact 22]; ghcr *push*
  unverified.
- **dev runner**: zero job history [X §6], so no job-egress fact exists — **but the dev node pulled
  `data.forgejo.org/forgejo/runner:13.2.0`** (an external registry) at pod start [K8S], i.e. node
  internet egress exists (pod egress typically SNATs through the same node network). The dev-role
  **PR arm needs no internet except the instance's own public host** (registry = `git.scifi.farm`,
  which the runner already dials successfully for registration/polling [X fact 20]) — unless
  Reading B / ghcr-from-dev is ever wanted.
- **Owner-leg commands** (I can't exec from the readonly tier; expected: `401` for every `/v2/`,
  proving reachability+registry response; the runner image has curl, else run the same in `-c dind`):

  ```sh
  kubectl --context gpu -n default exec -it gpu-forgejo-runner-gpu-0 -c runner -- \
    sh -c 'for u in https://git.spencerslab.com/v2/ https://git.scifi.farm/v2/ https://ghcr.io/v2/; do printf "%s -> " "$u"; curl -sS -o /dev/null -w "%{http_code}\n" "$u"; done'
  kubectl --context dev -n default exec -it dev-forgejo-runner-dev-0 -c runner -- \
    sh -c 'for u in https://git.scifi.farm/v2/ https://ghcr.io/v2/; do printf "%s -> " "$u"; curl -sS -o /dev/null -w "%{http_code}\n" "$u"; done'
  ```

**Reading A vs Reading B of “push to GitHub AND the local registry”:**

- **A — “local” = the executing instance's registry** (recommended reading). Mechanics: registry host
  derived from `forgejo.server_url` (§1) or an instance-side `vars.REGISTRY_HOST`; each instance's
  jobs hold **only that instance's** push PAT (`secrets.FORGE_PUSH_TOKEN` per instance — exactly the
  `PUSH_TOKEN_{GH,DEV}` per-destination-secret convention [REPO]); dev-instance PR builds land in the
  dev registry; infra main builds land in the infra registry + ghcr. Zero cross-instance secrets,
  zero hostname literals, symmetric single file — and the ROLE guard already keeps each leg on its
  server: under A the synced main-push on the dev instance re-fires the dev copy's jobs, but the
  versioned arm's `prod`-membership guard is false there and the dev arm is additionally
  event-gated to `pull_request` — both land `skipped` (R1 §2/§4), so nothing publishes on dev from a
  main sync.
- **B — prod fan-out also into the dev registry** (literal “both registries everywhere”). Mechanics:
  infra job pushes to `git.scifi.farm` too → needs the **dev instance's PAT stored as a secret on
  the infra instance** (cross-instance credential custody; a dev-PAT leak on prod is a prod-side
  compromise of dev writes), plus `vars.PUSH_URL_*`-style destination for the *other* host, plus the
  unverified `/v2` reachability above (the network path is proven). Then the dev registry's calendar
  tags are written by *two* writers (prod builds + dev dispatches), which breaks P3's single-writer
  race assumption unless the dev side stops minting calendar tags.
  The word “local” in the owner's ruling reads naturally as A (it is exactly the contrast the same
  sentence draws against `ghcr.io`); B costs a cross-instance secret and a second writer for no
  tag the dev cluster can't get otherwise. Present both; recommend the planner ask for a one-line
  ruling.

### 6. Failure semantics worth pinning in tests

- `docker push` exits non-zero on any registry rejection (401/403 quota/404 transport), the step runs
  under `set -euo pipefail` → **step fails → job fails → run fails** ([RUN0] L122-123 pattern; the
  same “any error exits the step and fails the job, so a target is never overwritten” reasoning is
  the stated convention in [REPO]'s header). A quota 403/413 or an auth 401 therefore *fails loudly*
  — no silent partial success inside one push invocation. Within [RUN0]'s per-image flow, the
  multi-tag push loop (L207-210) can already half-succeed **inside one registry** (calendar lands,
  `latest` push dies) — run 0 accepted that (concurrency queue + re-run mints next N).
- **Two-registry half-success under each derivation policy** (the load-bearing analysis):
  - **P3 (union-max + walk-both):** build *i* mints N=max+1, walks both clear, pushes ghcr N ✔,
    forge push ✘ (say the PAT is missing ⇒ 401). Registry state: ghcr holds N, forge holds ≤N−1.
    Next run: `max(ghcr, forge) = N` ⇒ N+1, walks both (ghcr N+1 free, forge N+1 free) ⇒ **both
    publish N+1**. No tag is ever retargeted; the forge side simply **skipped N** (gap), ghcr side
    kept its N. Same reasoning with the arms swapped. So with P3, arm order cannot corrupt anything;
    it only decides which side gaps.
  - **P1 (derive ghcr-only) with forge pushed *second*:** forge can never run ahead ⇒ ghcr-only
    derivation is overwrite-safe against the forge side; a forge failure gaps forge (self-healing
    next run). **This is the one narrow case where a single-source derivation is safe — and its
    safety is entirely an artifact of arm order** (ghcr-first). One rebase that swaps the arms (or a
    manual forge push, or a dispatch) reintroduces silent forge-side overwrite.
  - **P1 with forge first** (or P2 generally): the leading side (forge) holds N, lagging ghcr
    re-mints N and **retargets ghcr's N silently** (GHCR mutability [GH-I]) — exactly the D3 hazard,
    now cross-registry. Symmetrically P2 clobbers GHCR.
  - **`next-n`-tolerance trap**: if the forge read answers 401/404 (private org after a visibility
    flip, `REQUIRE_SIGNIN_VIEW`, or a transient) the tolerated branch computes N=1 with **no walk**
    (shipped shape, [X] §4.3) — under P3 that's benign (ghcr's list still dominates the max and the
    ghcr-side walk still runs where its list answered 200); under a forge-only policy it publishes
    N=1 over a taken tag. **Pin in a leg**: the advance-walk must run against every registry whose
    *own* list returned 200; a registry whose list returned 200 but manifest HEAD answers a non-200/
    404 code stays fatal.
- **Test-pinnable invariants for the plan** (all static, greppable in the workflow file, mirroring
  [X] §7.1 legs t8/t11): (1) derivation reads **both** registries' `tags/list` before any
  `docker push`; (2) the existence walk runs per-registry before any push (no “walk ghcr then push
  forge with the same N without a forge HEAD” shape); (3) the forge login step exists under its own
  guard/step and uses `secrets.FORGE_PUSH_TOKEN` exactly once (t7-style counting); (4) a registry-arm
  failure cannot be swallowed (`|| true` banned on push/login/token lines); (5) the derivation token
  path tolerates the *documented* absence codes per side (ghcr token 403 DENIED for never-pushed,
  forge 404 NAME_UNKNOWN) without failing, and everything else stays fatal.

### Contradictions (R2) — how to weigh

1. **Docs vs source on registry login identity**: [D-C] implies “`docker login <host>` then your
   forgejo username+password”; source shows the Basic username is discarded whenever the password is
   a token [F15 basic.go:59-90]. Weigh: **source** (the docs describe the username+password path and
   are silent on the ignored-username behaviour). Practical effect: none for the workflow (`-u` is
   cosmetic), but it means a *mislabelled* secret (dev PAT under a ghcr name) fails **as the dev
   user**, with a confusing 401 — diag should echo *which* identity each login minted (the token
   endpoint's JWT can be base64-decoded for the diag step: `cut -d. -f2 | base64 -d`).
2. **“You cannot edit a package after you have published it” [D-I] vs container tag overwrite
   [F15 manifest.go:453-467]**. Weigh: source; the docs line is generic-package prose.
3. **EXPLORE “version deletion is a human UI action” [X §3] vs Cleanup Rules [F15
   package_cleanup_rule.go + cleanup.go; D-I]**. EXPLORE was right about *config keys* (no app.ini
   retention key exists) but missed the UI/DB rule mechanism. Correction stands: **v15.0.10 does
   have a retention mechanism, owner-UI-owned, cron-executed, container-aware (`latest` protected)**.
4. **EXPLORE “no catalog enumeration on either instance” [X fact 14] vs measured ghost-token `_catalog`
   → 200 [LIVE]**. Both true at their own auth level: tokenless → 401 challenge; *with* the anonymous
   zero-scope JWT (which every OCI client fetches by default) → 200 list of publicly-visible owners.
   Consequence: forge-side N derivation needs **no secret** while the org stays public — but a plan
   that *depends* on that couples tag derivation to org visibility; prefer reading with the push PAT
   (works public or private).
5. **GitHub “immutable releases” GA (2025-10)** reads like GHCR gained immutability; it didn't —
   Releases/assets/git-tags only; GHCR container tags remain retargetable [GH-I]. The plan's D3
   premise survives, verbatim, for GHCR — and now for Forgejo too (§4).

### §Options

- **O1 — Push identity: per-instance `secrets.FORGE_PUSH_TOKEN` = non-admin PAT** (owner = a user
  with write/admin in the target org; scope `all` or granular `read:package`+`write:package`; stored
  in Bitwarden → entered on *that* instance, mirroring `GHCR_PUSH_PAT`/`PUSH_TOKEN_*`). Login step per
  §1. Cost: 2 human legs (mint + enter, infra & dev; PATs are per-instance [X §3]). Proves: the only
  route the source leaves open. Unverified: live first push (hairpin ingress body-size/k3s-MTU [X §5,
  §7]).
- **O2 — job token / deploy token** — **closed, do not plan for it**: source-proven no package write
  for `forgejo.token` (TODO-branch), zero deploy-token wiring; revisit only if a future Forgejo
  implements the ActionUser permission check.
- **O3 — Namespace**: (a) `CuratedForest/<image>` — zero new accounts, org already publicly visible;
  forge path ≠ ghcr path (`ownyourio/<image>`); (b) create `ownyourio` user/org on **both** instances
  (registration open; org needs site admin) and push there — verbatim `ownyourio/<image>` parity, one
  extra human leg, and the *pushing* PAT owner must be an `ownyourio` member (if org) or `ownyourio`
  itself (user). The “same image name in both registries” reading of the owner's note favours (b);
  least-moving-parts favours (a). Owner ruling.
- **O4 — N policy: P3 (union-max + walk both), arms ghcr-then-forge.** Cost: one extra token+list+walk
  per image (reads possible with the push PAT or anonymously-ghost). Reads: keep the shipped
  tolerance table per side (ghcr token 401/403/404, forge 401/403/404 → contributes nothing to max;
  200-list → max + mandatory walk). Unverified: forge `tags/list` body byte-compat with `next-n`
  (one dispatch after the first push settles it). Fallback if the planner wants one less HTTP leg:
  P1 **with the leg pinning “forge push strictly after ghcr push”** — safe by arm order, brittle by
  construction.
- **O5 — Registry host without literals**: derive `${{ forgejo.server_url }}` (source-proven = AppURL)
  inside the step (`host=${FORGE_SERVER_URL#https://}` via `env:`), *or* per-instance
  `vars.REGISTRY_HOST` per the `PUSH_URL_*` precedent. Derivation adds a `server_url` reference that
  run 0's t9 diag/guard legs treated as NOTE-3-collision material [X §7.1] — a test leg must bless
  `forgejo.server_url` as a *derived host*, not a destination literal; the `vars.` route sidesteps
  that argument entirely at the cost of one variable per instance. Both satisfy “no hostname
  literals”.
- **O6 — PR-tag retention**: owner-leg forge Cleanup Rule per instance org (Container; full-name
  off; KeepCount e.g. 20; RemovePattern `pr-.*` + RemoveDays e.g. 14 — `latest` is code-protected
  anyway [F15 cleanup.go ShouldBeSkipped]) + an explicit decision that GHCR-side `pr-*` stays
  unpruned (no platform feature; [GH-R][GH-D]) unless the owner later wants a manual/Action pass.
  The forge cron itself (`OLDER_THAN 24h`) only ever reaps garbage/overwritten versions, never tags —
  so the rule is the *only* forge-side reaper and must be created, or PR tags accumulate on the PVC.
- **O7 — Arm order** = ghcr first, forge second (recommended): any half-failure leaves the forge
  side behind ghcr, which keeps even the cheap single-source derivation (P1) overwrite-free and keeps
  the gap on the registry that has *no* external pinned consumers. The reverse order makes ghcr the
  clobber-prone side. (With full P3 the choice is belt-and-braces, not load-bearing.)

### §Open questions for planning

1. **Namespace ruling** (O3 a/b): `CuratedForest/<image>` or mint an `ownyourio` account on both
   instances? Best guess: (a) `CuratedForest` now, revisit if the owner wants path parity — the
   *pinning* consumers (charts + Renovate) only ever reference ghcr anyway [X §7.1 x2].
2. **PAT ownership**: whose user account mints the push PATs (must be org write/admin member of the
   chosen namespace on that instance), and are they Bitwarden-stored like `GHCR_PUSH_PAT` (cf-119
   OQ-5 pattern)? Best guess: the owner's admin-normal user on each instance, vault item
   `forgejo-registry-token-{infra,dev}`; keep them non-admin so the site-admin bypass
   [F15 api.go:89] is not the grant path.
3. **Reading A vs B** (§5): confirm “local Forgejo registry” = the executing instance's registry
   (A). Best guess: A — B needs a cross-instance PAT and creates a second calendar-writer for the
   dev registry.
4. **Rolling tags on forge?** Keep [X] OQ-6 with this new fact: a forge Cleanup Rule can never delete
   `latest` (code-protected) but *can* delete `main`/calendar tags if a RemovePattern is sloppy
   (`.*`) — if `main`/`:latest` do land on forge, the retention rule must keep-pattern them. Best
   guess unchanged: calendar-only on forge; `:latest`/`:main` stay the ghcr cluster contract.
5. **Org visibility**: keep the org public (anonymous pull + anonymous forge-side tag reads work, but
   images are publicly enumerable via `_catalog` [LIVE]) or flip private and make the workflow's
   forge-side reads use the push PAT (and add pull secrets if the cluster ever pulls from forge)?
   Best guess: stay public + read with the PAT anyway, so a future visibility flip can't turn the
   derivation into “404 → N=1 with no walk” (§6 trap).
6. **Owner-leg egress confirmations** (§5 kubectl commands): gpu-runner→ghcr-push, gpu-runner→
   dev-registry `/v2/`, dev-runner→anything. Best guess: all 401-challenge OK; pin nothing on these
   until run, treat failures as new facts.
7. **`REQUIRE_SIGNIN_VIEW` + lab `[packages]`/`[quota]` app.ini state** stays unreadable from a
   readonly session ([X] §3 command); one owner read of `[packages]`/`[quota]`/`[service]` settles
   whether the §3 limits are truly unlimited here. Best guess: untouched defaults (all unlimited,
   `REQUIRE_SIGNIN_VIEW` unset).
