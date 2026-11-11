# EXPLORE — feat-seaweedfs-debug-skill

Scout grounding by `agent-explore`, 2026-11-11. Worktree:
`/home/coder/.local/share/opencode/worktree/e32e19/feat-seaweedfs-debug-skill`
(branch `feat-seaweedfs-debug-skill`, HEAD `a6e493b78` == `main` tip, `git status` clean).
Read-only throughout: repo reads, read-only git, `dev-boards` + `readonly-infra-kubernetes`
inspection calls. **Nothing was written — to the repo outside this file, to the board, or to the cluster.**

Every claim below carries the evidence it was read from. Facts that contradict the launch
brief are flagged **[CORRECTION]**.

---

## 1. Deliverable 1 — operational repair: what is already done, what is not

### 1.1 The three branches — content is ALREADY on `main` [CORRECTION]

The launch brief says the `WEED_MAINTENANCE_ERASURE_CODING_ENABLED` values change "sits
UNMERGED on branch `dep/seaweedfs-disable-ec-maintenance`". It does not. All three branch
*contents* are on `main`, landed under **different SHAs** (squash/cherry-pick), so the branch
refs are stale duplicates and the `Exploration`/`Deployment` work is about the *live cluster*,
not about the git branch.

Verified with two-dot content diffs (empty diff ⇒ identical tree):

| Branch | Branch tip | `git diff main <tip> -- <file>` | Landed on main as |
|---|---|---|---|
| `dep/seaweedfs-disable-ec-maintenance` | `b001af11e` (2026-11-10 14:09) | empty for `charts/seaweedfs/values.yaml` | `4b832237c dep(seaweedfs): keep admin maintenance ON; disable only EC proposals` |
| `fix/seaweedfs-filer-ingress-typo` | `21fd2bf05` (2026-11-10 13:44) | empty for `services/infra/prod/values.yaml` | `1e4c0f783 fix(services): seaweedfs-filer ingress backend service name typo seadweedfs->seaweedfs` |
| `debug/seaweedfs-incident-findings` | `13093f286` (2026-11-10 15:04) | empty for both the note and the runbook | `ff2bc876e docs: locate the live bad file — Loki TSDB index object on the lost chunk` |

```
$ git merge-base --is-ancestor dep/seaweedfs-disable-ec-maintenance main   -> NO
$ git rev-list --left-right --count main...dep/seaweedfs-disable-ec-maintenance -> 13  1
$ git diff main b001af11e -- charts/seaweedfs/values.yaml                  -> (empty)
$ git diff main 21fd2bf05 -- services/infra/prod/values.yaml               -> (empty)
$ git diff main 13093f286 -- .agents/notes/2026-11-10-seaweedfs-incident-findings.md \
      .agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md                 -> (empty)
```

`git diff main..<branch>` (two-dot against the *working* comparison the brief suggested) is
**misleading here** — it renders main's newer content as deletions (it re-shows the strata
q4/OOM work being "removed" and the `seadweedfs` typo being "re-added"). Use
`git show <branch>` + `git diff main <branch> -- <path>` instead. Also note
`debug/seaweedfs-incident-findings` is 5 behind / 1 ahead while the other two are 1 behind /
1 ahead — same stale-ancestor shape for all three.

Where the change actually lives (repo truth, current tree):

- `charts/seaweedfs/values.yaml:26-47` — `admin.extraEnvironmentVars:` with
  `WEED_MAINTENANCE_ERASURE_CODING_ENABLED: "false"` and the long why-comment
  (`WEED_MAINTENANCE_ENABLED` deliberately unset; `ec_balance` has no admin.toml/env key).
- `services/infra/prod/values.yaml:68-71` — `seaweedfs-filer:` ingress now
  `service: seaweedfs-filer` (typo gone). `grep -rn seadweed` hits only the two historical
  doc mentions (`.agents/notes/2026-11-10-seaweedfs-incident-findings.md:124,158`,
  `.agents/plans/2026-10-25-debug-seaweedfs-csi-vac-http.md:84`) — no live YAML.

### 1.2 Phase 0 is merged in git but NOT deployed to the cluster [KEY FACT]

Live probes (`readonly-infra-kubernetes`, all read-only):

1. `pods_get(name="seaweedfs-admin-0", namespace="default")` →
   `status.startTime = 2026-10-25T20:55:05Z`, phase Running. Container `seaweedfs` env
   carries **only** `WEED_CLUSTER_DEFAULT`, `WEED_CLUSTER_SW_FILER`, `WEED_CLUSTER_SW_MASTER`
   — **no `WEED_MAINTENANCE_ERASURE_CODING_ENABLED`**, and no restart since before the 11-10
   commit. The admin process is therefore still running the pre-Phase-0 config.
2. `resources_list(apiVersion="argoproj.io/v1alpha1", kind="Application", namespace="argocd")`
   → 12 apps; `infra-seaweedfs` **Sync=OutOfSync, Health=Healthy**; the umbrella `infra` app
   is also OutOfSync. Everything else Synced (incl. `infra-seaweedfs-csi-driver`).
3. `resources_get(kind="Application", name="infra-seaweedfs", namespace="default")` →
   - `spec.source(s)`: git `https://github.com/OwnYourIO/SpencersLab.git`,
     `targetRevision: main`, **`path: charts/seaweedfs`** (not a released tarball), plus a
     second `ref: services` source at `main`; helm params `domain=spencerslab.com`,
     `clusterName=infra`, `serviceName=infra`, `appName=seaweedfs`; inline
     `valuesObject: {seaweedfs: {volume: {replicas: 8}}}`; `valueFiles: [values.yaml]`.
   - `status.sync.comparedTo` revision = `a6e493b7884ec13e0f3733b86da3deddadee146d`
     (= current `main` tip) → ArgoCD is evaluating the commit that contains the env var and
     still calls the app OutOfSync.
   - `status.operationState`: phase `Succeeded`, message `successfully synced (all tasks run)`,
     `startedAt 2026-11-09T15:35:16Z` — i.e. the last applied sync predates the 11-10 change.
   - `status.conditions`: four `RepeatedResourceWarning`s —
     `Resource /Service/default/seaweedfs-{filer,master,s3,volume} appeared 2 times among
     application resources` (filer's stamp 2026-11-03, the other three 2026-11-11T00:15:40Z,
     so it is recurring on every refresh).
   - managed resources include `StatefulSet/seaweedfs-{admin,filer,master,volume}`,
     `Deployment/seaweedfs-s3`, 17 `Service` rows (the duplicated four among them).
   Because the chart is sourced from the **git path**, no chart release/tarball bump is needed
   to deploy Phase 0 — an ArgoCD sync of `infra-seaweedfs` (and the admin pod restart it
   implies) is the missing step. Whether the persistent OutOfSync + `RepeatedResourceWarning`
   pair means automated sync is *failing* rather than merely pending is **not** resolvable from
   read-only state → `open_questions` Q1. The sync policy is `automated: {prune: true,
   selfHeal: true}` unless a `services.<serviceName>[.<appName>].selfHeal="false"` annotation
   says otherwise — that gate is at `charts/base/templates/appset-charts.yaml:124-138`
   (the infra service also carries its own copy at
   `services/infra/prod/templates/appset.yaml:126-129`); no `selfHeal` value is set for
   seaweedfs in `services/infra/prod/values.yaml` (grep shows only the template lines).
   Agents cannot sync it: ArgoCD writes are outside every `readonly-*` grant and AGENTS.md
   forbids `kubectl apply` — sync is a human/`admin-*` action.

### 1.3 Live workload inventory for the runbook's `kubectl` lines (namespace `default`, infra cluster)

`resources_list(kind="Pod", namespace="default", labelSelector="app.kubernetes.io/name=seaweedfs")`:

```
seaweedfs-admin-0  seaweedfs-master-0  seaweedfs-s3-5ff9467785-wmhjl
seaweedfs-filer-0 … seaweedfs-filer-4          (5)
seaweedfs-volume-0 … seaweedfs-volume-7        (8)
```

- The runbook's `kubectl -n default logs deploy/seaweedfs-s3` target pod is
  `seaweedfs-s3-5ff9467785-wmhjl` (replica-hash churns — use the `deploy/` form, not this name).
- The Phase 3/4 `weed shell` host is `seaweedfs-master-0 -c seaweedfs`
  (container name is `seaweedfs`, single container — verified in the pod spec).
- Volume FQDN pattern in the runbook is confirmed by the headless-service inventory:
  `seaweedfs-volume-{0..7}.seaweedfs-volume.default:8080`; filer client
  `seaweedfs-filer-client.default:8888`; master `seaweedfs-master.default:9333`
  (all three from `charts/seaweedfs/values.yaml:21-23` env).
- **No agent tier grants pod exec** (AGENTS.md "No tier grants pod exec"), so Phases 1–4 are
  human-run; the skill and the chunk ACs must be written as pasteable command blocks, not as
  agent-executed steps.

### 1.4 Open operational items (from the two landed files, unchanged by this scout)

Evidence base: `.agents/notes/2026-11-10-seaweedfs-incident-findings.md` (165 lines) and
`.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md` (247 lines, Phases 0–5).

| Item | Where it is stated | State as grounded here |
|---|---|---|
| Phase 0 deploy (env var live) | runbook lines 35-60 | **pending** — merged, not synced (§1.2) |
| Split-brain pair `1982886` (v3 48 unique needles / v2 37) auto-repair refused | note lines 78-91; runbook Phase 3 lines 101-165 | `-nonRepairThreshold 1` is the documented answer (default 0.3 refuses at up-to-46% divergence) |
| **Wrong-collection fsck**: the user's `volume.fsck` ran with `-collection media`; `1982886` is in collection **`logs`** | runbook lines 156-158 + Phase 4 lines 210-223 (`-collection logs -volumeId 1982649 -v`) | fsck's `-collection` must match; `volume.check.disk -volumeId` is collection-free |
| Remaining read-only mark `1982649` | runbook lines 103-107, 227-229 | trim the Phase 3 mark list to `1982649` unless `volume.list` shows otherwise (idempotent lines are safe) |
| Live bad file `/buckets/logs/index/loki_index_20765/fake/1794147797505872010-compactor-1794085698030-1794147325922-a373bee8.tsdb.gz` + s3 restart | runbook Phase 4 lines 175-208 | `fs.meta.cat` then `fs.rm` then `rollout restart deploy seaweedfs-s3` block is pasteable as written |
| EC decode Phases 1-2 (recoverable 1/440/441/448/461; unrecoverable 4/5/446/447/449) | runbook lines 62-99 | untouched |
| Filer ingress typo | §1.1 | repo-fixed; still needs the sync + `helm template` re-render check |

Repo-side validation commands available for a chunk's `## Commands` (all local, no cluster):

```
export PATH=$HOME/.local/bin:$PATH     # helm lives here or pytest mass-skips helm-guarded tests
helm lint charts/seaweedfs
helm template charts/seaweedfs > /dev/null
helm template infra services/infra/prod --set domain=spencerslab.com --set clusterName=infra \
  -s templates/generic-ingress.yaml | grep -A3 'name: "seaweedfs-filer"'   # runbook line 31
git diff --stat main <branch> -- charts/seaweedfs/values.yaml
npx --yes aislop@0.20.0 scan skills/<new-skill>
```

---

## 2. Deliverable 2 — conventions for a NEW self-written skill in `skills/`

### 2.1 (a) Layout and conventions of the six existing self-written skills

Full inventory (`find skills -type f` — 17 files):

```
skills/container-creation/SKILL.md                                   263 ln / 10,730 B
skills/helm-chart-creation/SKILL.md                                  384 ln / 20,020 B
skills/helm-chart-creation/references/{chart-templates,mcp-servers,proxying,storage-and-secrets,values-and-appset}.md
skills/llama-swap/SKILL.md                                           196 ln / 10,484 B
skills/wekan-api/SKILL.md                                            223 ln / 18,535 B
skills/wekan-api/references/{api-py-cheatsheet,config-reference,rest-api-overview,webhook-data,wekan-mcp-ops}.md
skills/wekan-api/scripts/{attachments,auth,boards_crud,checklists_comments,lists_swimlanes_cards_crud,webhook_receiver}.py
skills/wekan-board-provision/SKILL.md                                150 ln /  8,778 B
skills/wekan-mcp/SKILL.md                                            238 ln / 14,647 B
skills/wekan-mcp/references/call-shapes.md
```

- **Frontmatter is exactly two keys, always: `name` and `description`.** No `license`,
  `version`, `allowed-tools`, `metadata`, or `disable-model-invocation` on any self-written
  skill (measured across all six; those keys appear only on the rulesync-managed
  `.rulesync/skills/*` — e.g. `aislop` carries `disable-model-invocation: true` +
  `metadata.opencode/autoinvoke: "false"`, `comment-slop` carries `license: MIT`).
  `name` == the directory name; `description` is a single long line (wekan-board-provision
  quotes it because of the leading/inline special chars — quote when in doubt).
- **The description is the trigger contract.** House pattern, every file: what the skill is
  for → "Use this skill whenever …" → concrete nouns/paths/symbols a session would actually
  contain → the closer "even if the user doesn't name this skill directly" (present in
  container-creation, helm-chart-creation, llama-swap, wekan-api). Include literal trigger
  tokens (`containers/`, `charts/`, `config.yaml` with a `models:` block, `/users/login`).
- **Body shape**: `# <Skill>` H1 → short orientation prose → task-shaped H2s. Real examples:
  container-creation: `When to create a container / Directory layout / Build pipeline /
  Dockerfile conventions / Consuming the image from a Helm chart / Worked example / Checklist`;
  helm-chart-creation: `Repo context locations / When to use–when not / Workflow /
  Known gotchas (CRITICAL) / Override sentinels / … / Anti-patterns / Reference charts (read
  these files, not stale docs)`; llama-swap: `Before answering config questions / Minimum
  viable config / Macros / … / Debugging checklist`; wekan-api: `When this skill applies /
  Prefer the wekan MCP server when it is available / Ground truth and version pinning /
  Standard workflow / Non-obvious facts to encode into any code you write / What lives in
  this skill / How to approach a new task / Local test instance / SpencersLab instances`;
  wekan-mcp: `Servers and tiers / Call-shape rules / Board context block schema / Card details
  block schema / Failure-mode playbook / Pointers — where the rest lives`;
  wekan-board-provision: `The spec the engine diffs against / Procedure / Invariants`.
  A `## Debugging checklist` (llama-swap:182) and a `## Failure-mode playbook`
  (wekan-mcp:211) are the two closest precedents for a debug skill.
- **`references/`** = deep dives "read on demand, not upfront" — declared in a `SKILL.md`
  section that names each file with a one-line *when to consult* hook
  (`skills/helm-chart-creation/SKILL.md:21-40`, `skills/wekan-api/SKILL.md:181-199` — the
  latter is the best model: `**references/** — read the one that matches the task; do not
  preload all of them.` then per-file bullets). AGENTS.md itself points there
  (`.rulesync/rules/overview.md:396` → `skills/helm-chart-creation/references/`).
- **`scripts/`** = runnable examples, self-contained, stdlib-only unless marked
  (`skills/wekan-api/scripts/`, documented at `SKILL.md:195-201`). Alternative precedent:
  `wekan-board-provision` vendors **no** script and instead points at the repo-owned engine
  `scripts/provision-board.py` + `SKILL.md:57 Procedure` (`skills/wekan-board-provision/SKILL.md:9`
  description says "the action plan of `scripts/provision-board.py`"). For a SeaweedFS debug
  skill the safe read-only posture is markdown + optional stdlib-python helpers.
- **Cross-skill pointers, no duplication**: `skills/wekan-mcp/SKILL.md:6` ends "Raw REST
  semantics and server internals live in the wekan-api skill", and `skills/wekan-api/SKILL.md:22`
  is "Prefer the wekan MCP server when it is available". A seaweedfs skill should likewise
  point at `skills/helm-chart-creation` for chart wiring and at
  `.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md` rather than restate the runbook.

### 2.2 (b) Discovery — where the new skill goes and what registers it

- **Right home: `skills/<name>/SKILL.md`** (top level). Confirmed by two independent config
  surfaces that already list it:
  - `.opencode/opencode.jsonc` → `"skills": ["/home/coder/CuratedForest.com/content/tech/home-assistant", "./.agents/skills", "skills/"]`
  - machine-global `~/.config/opencode/opencode.json` → `"skills": [ …CuratedForest…, "./.agents/skills", "./skill/", "skills/"]`
  Both resolve `skills/` relative to the project, so **adding a directory needs no config
  edit** and the skill is visible from the repo and from any Coder workspace path.
- **NOT `.rulesync/skills/`**: that directory is rulesync *source* for the pipeline/vendored
  skills and generates `.opencode/skills/` (23 entries there now: `agents-sync`, `boards`,
  `comment-slop`, `aislop`, the `pipeline-*`/`pipeline-role-*` set, the `role-*` set).
  Putting a repo skill there drags it into the CI drift gate
  (`.github/workflows/rulesync.yaml`: `npx --yes rulesync@37.0.0 generate --check`) and out of
  the self-written-skill convention. `rulesync.jsonc` `features: [rules, subagents, commands, skills]`,
  `targets: [opencode]`, `outputRoots: ["."]`, `delete: true`.
- **NOT `.agents/skills/`**: that is third-party, git-tracked, integrity-hashed in root
  `skills-lock.json`.
- **AGENTS.md must be updated at the SOURCE, then regenerated**: the self-written-skill list is
  `.rulesync/rules/overview.md:46-47` — `` `skills/` — self-written skills (`helm-chart-creation`,
  `container-creation`, `llama-swap`, `wekan-mcp`, `wekan-api`, `wekan-board-provision`). `` —
  edit there, run `rulesync generate`, and commit source + generated `AGENTS.md` in one commit
  (AGENTS.md hard rule: never hand-edit `AGENTS.md`). Rulesync 37.0.0 is installed at
  `/home/coder/.nvm/versions/node/v26.5.0/bin/rulesync`; `aislop` runs via `npx` (0.20.0).
- `.kilo` is a tracked symlink to `.agents/`, so top-level `skills/` is NOT re-exposed through
  it; `.agents/skills/` is reached by the `skills` paths above, not by rulesync
  (`.rulesync/rules/overview.md:71-74` says so explicitly).

### 2.3 (c) Surfaces that must be touched when a skill is added

- **`skills-lock.json` — no.** 71 entries, all third-party `sourceType: github` with
  `computedHash`; no self-written skill appears in it (`helm-bjw-s-chart`,
  `container-security` are the similarly-named third-party ones). Do **not** add an entry —
  hand-editing it breaks the sync story for `.agents/skills/`.
- **AGENTS.md self-written list** — yes, via `.rulesync/rules/overview.md:46` + regenerate
  (§2.2). The wekan-mcp surface suite already enforces exactly this for its own skill:
  `tests/wekan-mcp/skill-surface.sh` header — "…and the **AGENTS.md self-written-skills
  line**" (its t6), i.e. the repo precedent is *each skill's own surface test asserts its
  AGENTS.md listing*, not a repo-wide enumerator.
- **No CI job runs `tests/**`** — `.github/workflows/` is `aislop.yaml`, `rulesync.yaml`,
  `docker-build.yaml`, `release.yaml`, `gpt-researcher-render-tests.yaml`,
  `llama-swap-tools-tests.yaml`, `vllm-render-tests.yaml`. `tests/<area>/surface.sh` files are
  the pipeline's chunk-`## Commands` validation, run manually:
  `bash tests/wekan-mcp/skill-surface.sh [t2 t4]` (usage block at
  `tests/wekan-mcp/skill-surface.sh:41-45`), statics-only by design — the header records
  "no network in suites". The repo has **no unit-test suite**; per AGENTS.md "tests" =
  `helm lint`/`helm template` + grep trio checks; helm-guarded pytest lives under
  `charts/*/tests/`.
- **A new skill can break an existing green suite** — `live_code_grep()`
  (`charts/llama-swap/tests/strata_testlib.py:820-835`) scans live surfaces including the
  **whole `skills/` tree** (roots: `services`, `custom-values`, `charts`, `containers`,
  `skills`, `.github`; it skips only `*/tests/*`, caches, `.tgz/.pyc/.gz`). Its negative pins
  assert needles are absent — e.g. `test_strata_c08_rung_shifts.py:142`
  `assert not S.live_code_grep("abliterated-iq3_xxs"), "the retired profile-file name survives"`
  and `test_strata_wiring.py:215,319`. So do not copy retired strata/model needles into the new
  skill's prose. It excludes `.agents/` ("plan folders are sanctioned history references").

### 2.4 (d) Quality gates applying to new content

- **aislop** (`.aislop/config.yml`): `engines: format/lint/code-quality/ai-slop/security` on,
  `architecture` off; `ci.failBelow: 80`; `exclude:` = `node_modules .git dist build coverage
  _bmad/** charts/llama-swap/scripts/gguf-py/**`. CI (`.github/workflows/aislop.yaml`):
  `npx --yes aislop@0.20.0 ci --changes --base origin/main --human` — **PR gates only files it
  changes**, floor + zero error-severity per touched file. CLI pin `0.20.0` is duplicated in
  `.opencode/plugin/aislop-gate/index.ts` and machine-guarded by
  `tests/opencode/aislop-pin-parity.test.ts:106`; never write a floating `npx aislop` in CI.
- **Measured behaviour on skill content** (this scout ran it):
  `aislop scan skills/wekan-board-provision --json` → `score: null, label: "not scored",
  scoreable: false, coverage.supportedFiles: 0`. So **markdown SKILL.md / references are not
  scored and cannot fail the CI floor** — but **Python helpers are**:
  `aislop scan skills/` → `score 47 Critical, 0 errors · 39 warnings`, all 39 in
  `skills/wekan-api/scripts/*.py` (`ai-slop/python-repetitive-dispatch`), `supportedFiles: 6`
  (the six scripts). Consequence: ship prose, or ship scripts ready to clear 80 with zero
  errors. Local scan also warns `Not fully checked: ruff not installed`.
  `aislop scan` takes a **directory**, not a file (`error: Not a directory: …/SKILL.md`).
- **comment-slop / AGENTS.md comment policy** (`.rulesync/rules/00-comments-and-slop.md:12-16`):
  comments state the *why* (constraints, invariants, trade-offs, issue links); never restate
  code, narrate history ("now we…", "updated to…"), or describe planned work. The three-clause
  test + delete-default is `.rulesync/skills/comment-slop/SKILL.md:10-24`. The `aislop-gate`
  plugin may append findings to your own edit results — fix them in the same turn. Apply the
  same discipline to skill prose: the house voice is imperative + evidence-stamped, and every
  "why" sentence in the existing skills names the constraint (compare
  `charts/seaweedfs/values.yaml:34-44`, which is a good model of why-only).
- Vendored-skill pin law (`.rulesync/rules/00-comments-and-slop.md:17`) does **not** apply to a
  new self-written skill — it is only for `comment-slop`/`aislop` updates.

---

## 3. Deliverable 3 — dev-boards MCP surface (read-only; nothing written to the board)

### 3.1 Board structure ids (AI-Dev `TNQJ2BrXenZovngTS`)

`tools["dev-boards"].list_swimlanes` → 4 swimlanes:

```
jLzy39L7djCRr67SF | In Process     MoZHQz3C4dSW4Atya | Backlog
BkNBQgMLJBvmCgMAQ | Farm           hFgncuRJ8Pkvpt8ki | Planning
```

`tools["dev-boards"].list_lists({board_id:"TNQJ2BrXenZovngTS"})` → 35 rows
(`{id,title,swimlane_id}`). **The ids the prefetched board block was missing:**

- **Backlog swimlane = `MoZHQz3C4dSW4Atya`**
- **Inbox list = `PjEZ39rXBdpNcpncs`** (lives in Backlog)

All Backlog lists: `7Xb4kJHdZQYBdoaw4` Context · `qshjg8ET6jrPFdxEw` Features ·
`5WdhStBqrGTdX7Rkp` Research · `v2oSaFQe3kNgskDJh` Outside Process · `zCc6sKHL5wqJi2tGz`
Dev Env · `zETB7L5dSuupbcbtv` Home Assistant · `bZBRs2d7aw6nRyNBN` CICD · `Dmw5jhpq8Ari62iJd`
Wekan · `PH3xMsLkHqhbQAcwd` AI · `PjEZ39rXBdpNcpncs` Inbox.
In Process (for reference, already in the prefetch): `XhDyShvuwhGWzWH2z` Not Started ·
`qZ9CLZqCRbv7NQQ6R` Executing · `2B6wWGJ8Tetp5QWDJ` Review · `y9tsvb3AguKWhzCoF` Rework ·
`DHw56fMKy3qyfudz4` Finished · `M4JS9LfaypJbB97At` Low Priority · `jNYNdCPPkX8Bs95s4` Test ·
`52dS3k7Kdk9EB5cJj` Cancelled · `Hy9AEjEvxqh5ksRgC` Resume Later.
Note the Planning swimlane has **two** CICD lists (`BC5h6TJTiQpWWGxph`, `nwDa9GWcAuhxDKQBP`)
and Farm misspells `Outside Proccess` (`2jrdnQniMPficqcBr`) — resolve list ids per swimlane,
never by title alone.

### 3.2 Deployed-build capability probe (39 tools in the live catalog)

- **`set_card_labels` — PRESENT** on the deployed build. Shape as served:
  `set_card_labels({ board_id: string, card_ids: Array<string>, add_label_ids?: Array<string>|null, remove_label_ids?: Array<string>|null })`
  (note: it is *set*-style over `card_ids` arrays, not single-card).
- **`create_card` — ACCEPTS `default_checked`**:
  `create_card({ board_id, list_id, swimlane_id, title, description?: string = "",
  default_checked?: {} | null = null, parent_id?: string | null = null })` — required
  `board_id`+`list_id`+`swimlane_id`+`title` (all strings, no defaults).
  Same shape in the repo source that built the running image:
  `containers/wekan-mcp/wekan_mcp/server.py:1709` is `set_card_labels`; the `create_card`
  definition at `…/server.py` lists `default_checked: Optional[dict] = None` and the docstring
  pins the value type: a dict mapping **checklist TITLE → list of item titles**, e.g.
  `{"Model(s)": ["Qwen Flash", "Local (gpu-ai)"]}`, validated before creation
  (`_validate_default_checked` at `server.py:550`) and applied by bounded ~10 s polling
  (`_apply_default_checked` at `server.py:459`) because the board's `createCard` rules build
  the standard checklists asynchronously after the create response.
- Deployed image: `services/dev/prod/values.yaml:451-454` →
  `boards: {enabled: true, image: ghcr.io/ownyourio/wekan-mcp:v162, transport: streamable-http, mcpPort: 8080}`;
  bearer minted in-pod from the `wekan-mcp` Bitwarden LOGIN item
  (`services/dev/prod/templates/secret-wekan-mcp.yaml`, `custom-values/dev/prod-values.yaml:31-32`);
  dev is **not** read-only server-side (`WEKAN_MCP_READ_ONLY` deliberately unset).
  Registry parity is owned by `tests/wekan-mcp/tools.sh` + `tests/wekan-mcp/registry-parity.py`
  (reads the registry out of `server.py`; 18 reads / 21 writes = 39 distinct — matches the
  live catalog).

### 3.3 Labels available for the follow-up card

`dev-boards` has **no label-listing tool** (the 39: add_card_dependency, add_checklist,
add_checklist_item, add_comment, create_card, create_custom_field, create_label, create_list,
create_rule, create_swimlane, delete_checklist_item, edit_card_dependency, get_board, get_card,
get_card_details, get_checklist, get_custom_field, get_rule, list_board_dependencies,
list_board_members, list_boards, list_card_dependencies, list_cards_in_list, list_checklists,
list_comments, list_custom_fields, list_lists, list_rules, list_swimlanes, move_card,
preload_board, remove_card_dependency, remove_rule, set_card_custom_field, set_card_labels,
toggle_checklist_item, update_board, update_card, update_rule).
`tools["dev-boards"].get_board({board_id:"TNQJ2BrXenZovngTS"})` returns exactly
`[id, title, permission, color, archived, labels]` — the label map comes from there.
Title `AI-Dev`; 19 labels (5-char ids):

```
ysSmS5 Research              Nd5h6R Research: Parallel     mkbxeo Ready for Work
G7mzkC Pipeline: Local       NHvBk5 Pipeline: CICD         3PGnrD Pipeline: Context
urP8pR Pipeline: Home Assistant                            ezGduq Pipeline: AI
f3sKNX Provider: API         PnhFKk Provider: Local        yBfNJJ Bucket Color
m4EN6C Bucket: Features  jXX4GM Bucket: Context  CRWg9m Bucket: Research
eyqxPC Bucket: Outside Process  2tc8ds Bucket: Dev Env  s6xmDW Bucket: Home Assistant
25Mfu5 Bucket: CICD  z8hkS5 Bucket: Wekan
```

No `Repo:` label exists on this board (so `Repo: SpencersLab` semantics from the boards skill
are not currently expressible via a label id here), and there is **no `Pipeline: API`/`Pipeline: Wekan`**
— a `Pipeline:` label set is what the locks plugin derives claims from, so a card without one
takes the single `default` pipeline.

---

## 4. Plan-folder boilerplate the planner copies

`.agents/plans/templates/` = 5 files: `PLAN.md` (26 ln), `STATE.json`, `DECISIONS.md`,
`FRICTION.md`, `chunks/C01.md`.

- `PLAN.md` skeleton (verbatim): `# PLAN: <title>` / `feature: <yyyy>/<yyyy-mm>-<type>-<slug>`
  / `## Goal <two sentences>` / `## Out of scope` / `## Commands` with `test:` `lint:`
  `typecheck:` `smoke:` (optional) / `## Chunks` table
  `| id | title | size | wave | depends_on | why the dependency |` seeded `C01 … S … 1 … []` /
  `## Wave order` / `## Risks / assumptions`.
- `STATE.json` shape: `{feature, plan_status:"draft", coord_session, test_session, current_wave:1,
  updated_at, chunks:{C01:{status:"pending", wave:1, depends_on:[], dev_rounds:0,
  review_rounds:0, last_verdict, handoffs:[]}}, blocked:[], deferred:[]}`.
  `updated_at` must be workspace-local ISO-8601 **with offset** (UTC `Z` if `$TZ` unresolvable),
  never epoch ms (`/pipeline-conventions`).
- Target folder (this scout created it + this file):
  `.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/`. Plan file name:
  `2026-11-11-feat-seaweedfs-debug-skill.md` (dated, `yyyy-mm-dd-<type>-<slug>.md`).
  No `RESEARCH.md` here yet — `agent-research` writes it next to the plan file.
  Precedent for this scout's own output format, worth mirroring:
  `.agents/plans/2026/2026-11-cf-119-feat-forgejo-push-main/EXPLORE.md` and
  `.agents/plans/2026/2026-11-cf-104-feat-forgejo-lfs/EXPLORE.md`.

---

## 5. Other SeaweedFS context on disk worth citing (grep -ril seaweed)

Highest-value besides the two landed files:

- `.agents/plans/2026-10-25-debug-seaweedfs-csi-vac-http.md` — previous SeaweedFS debug run:
  chart 4.35→4.50 / csi-driver 0.2.27→0.2.42 upgrade broke every CSI mount
  (`/.csi/vac/… connection refused`), plus the **filer ingress typo** first recorded there
  (line 84) and the admin-server bind fix (chart `allowInsecureBind: true`,
  `charts/seaweedfs/values.yaml:28-31`, branch `fix/seaweedfs-admin` tip `00f6503c5`).
  This is the natural precedent chapter for a debug skill (upgrade-induced failure mode).
- `.agents/plans/2026-09-07-debug-immich-seaweedfs-empty-coredns-rewrites.md` — FUSE/CSI
  CoreDNS-rewrite outage class (immich `EIO: i/o error, read`); fix validated in worktree
  `seaweed-troubleshooting`, not committed.
- `.agents/plans/2026-09-13-debug-home-node-io-crash.md` — host-I/O angle on the same storage.
- StorageClass / PVC wiring (Phase 5 "never EC again" surface):
  `services/infra/prod/templates/pvc-storage-classes.yaml` defines
  `seaweedfs-extra` (l.4), `seaweedfs-important` (l.15), `seaweedfs-backups` (l.26),
  `seaweedfs-backup-important` (l.38) — **none carries a `collection` parameter**, which is
  exactly why their data lands in the unnamed/`default` EC-eligible pool (note lines 49-52);
  `services/infra/prod/templates/seaweedfs-filer-{0..4}-grpc-service.yaml` (per-filer gRPC
  services the CSI driver dials), plus `pvc-*.yaml` per cluster (gpu/home/media/proxy-local/
  proxy-backup/…) and `services/{gpu,home,media,proxy-local,proxy-backup}/prod/values.yaml`
  references.
- Live-instance endpoints an operator uses (all `https://`, cluster infra, ns `default`):
  `seaweedfs-master.infra.spencerslab.com` (`/` = volume table + Up Time),
  `seaweedfs-admin.infra.spencerslab.com` (`/storage/ec-shards`,
  `/api/files/properties?path=…` URL-encode the path, `/plugin` = EC Shard Balance toggle),
  `seaweedfs-filer.infra.spencerslab.com` (now un-typoed). `custom-values/infra/prod-values.yaml:18-19`
  holds the seaweedfs private overrides; `…:79` shows the in-cluster S3 endpoint
  `seaweedfs-s3.default.svc.cluster.local:8333`; `…:16` the CSI filer endpoint list
  `seaweedfs-filer.{0..4}.infra.spencerslab.com:888{0..4}`.
- Renovate churn touching SeaweedFS right now (branch tips, not merged):
  `upstream/renovate/seaweedfs-4.x` → `3c55befcf "Update Helm release seaweedfs to v4.53.0"`;
  `upstream/renovate/seaweedfs-csi-driver-0.x` → `7b93b89e5 v0.2.45`. Chart dep is
  `seaweedfs 4.50.0` (`charts/seaweedfs/Chart.yaml`, local chart `version: 1.0.37`), server
  image `weed v4.50 ec8f97935` (note line 6) — any source-verified command shape in the new
  skill stays pinned to 4.50 unless a chunk deliberately moves the pin.

---

## 6. Gotchas

1. **The three "open branches" are stale duplicates — their content is already on `main`.**
   Do not plan to merge/cherry-pick them; plan the *deploy* and the *ops* remainder. Verify
   with `git diff main <sha> -- <path>` (empty = identical), never with
   `git diff main..<sha> --stat` (two-dot renders main's newer work as deletions).
2. **`git diff main..dep/seaweedfs-disable-ec-maintenance` prints ~1,600 lines of unrelated
   strata/prowlarr churn** (it is the inverse of 13 commits main gained). Use `git show <sha>`.
3. **Phase 0 is NOT live**: admin pod is from 10-25 and lacks the env var; `infra-seaweedfs`
   is OutOfSync at main tip with four recurring `RepeatedResourceWarning`s and last successful
   sync 11-09. Merging ≠ deployed here; verify with
   `pods_get(seaweedfs-admin-0).spec.containers[].env` or the runbook's
   `grep "Applied [maintenance.erasure_coding] settings from admin.toml"` log check.
4. **Duplicate Service resources are structural**: `charts/seaweedfs/templates/seaweedfs-{master,s3,filer-http,volume-http}-service.yaml`
   hard-name `seaweedfs-{master,s3,filer,volume}` (`name:` at line 4 of each) and the upstream
   subchart emits the same names → ArgoCD's repeated-resource warnings. Any chunk that touches
   these templates must treat that collision as known, pre-existing debt (filer's warning dates
   to 11-03), not as its own regression.
5. **No pod exec in any agent tier** — every Phase 1–4 command is human-run pasteable text;
   write ACs as "command block + expected output", not as agent-executed steps.
6. **aislop cannot score the skill's prose** (`scoreable: false` for markdown) — the floor only
   bites if the skill ships `.py` helpers, and `skills/` currently sits at 47/100 on exactly
   that account (39 `python-repetitive-dispatch` warnings in `skills/wekan-api/scripts/`).
   `aislop scan` needs a directory argument.
7. **Never add the new skill to `skills-lock.json`** (third-party integrity file) and **never
   put it in `.rulesync/skills/`** (rulesync-owned → `rulesync generate --check` CI drift).
8. **AGENTS.md is generated** — list the skill in `.rulesync/rules/overview.md:46-47` and run
   `rulesync generate`; hand-editing `AGENTS.md` fails the drift gate.
9. **`live_code_grep` spans `skills/`** — retired llama-swap/strata needles embedded in the new
   skill turn `charts/llama-swap/tests/` arms red (`test_strata_c08_rung_shifts.py:142` etc.).
10. **`helm` needs `export PATH=$HOME/.local/bin:$PATH`** or helm-guarded pytest silently
    mass-skips (AGENTS.md "Agent-shell tooling recipes").
11. **List ids are per-swimlane**: Planning has two `CICD` lists; Farm's list is titled
    `Outside Proccess` (misspelled). Match on `(swimlane_id, id)`, not on title.
12. **`set_card_labels` takes `card_ids` (array) + `add_label_ids`/`remove_label_ids`** — and
    there is **no label-listing tool** on dev-boards: get label ids from `get_board().labels`
    (measured above) or from raw REST via the `wekan-api` skill.
13. **The `:v60` comment above the `boards.image` line is stale** (`services/dev/prod/values.yaml:453`
    says ":v60 = the 25-tool custom-field build" while line 454 pins `v162` = 39 tools). Don't
    cite the comment as evidence of the deployed build.
14. **The board has no `Repo:` label and no `Pipeline: Wekan`/`Pipeline: API`** — a spec card
    that needs a specific pipeline must use one of `G7mzkC/NHvBk5/3PGnrD/urP8pR/ezGduq` or take
    the `default` pipeline by carrying none.
15. **Prefetched board block only enumerates In Process** — the `board-context` plugin block is
    not the whole board; anything Backlog-side needs `list_lists` (done here).

---

## 7. Unresolved (handing back)

- **Q1 (cluster, needs the human or an `admin-*` session)** — is `infra-seaweedfs`'s
  OutOfSync a *failing* automated sync (repeated-resource warning blocking the apply) or merely
  a pending diff? Evidence in hand: `operationState.phase=Succeeded` dated 11-09, conditions
  re-stamped 11-11T00:15:40Z, automated+prune+selfHeal default-on, no `selfHeal=false` value
  for seaweedfs in `services/infra/prod/values.yaml`. Deciding this needs an ArgoCD UI/API read
  or a sync attempt — outside a scout's grants. (Also: is the umbrella `infra` app's OutOfSync
  related, or the cf-122 SSA flip?)
- **Q2** — whether `-nonRepairThreshold 1` + `-syncDeleted` actually heals `1982886`
  (v3 48 / v2 37 unique needles), i.e. whether the divergence is pure append or a genuine
  split-brain with conflicting writes at the same needle key. The runbook asserts mutual-append;
  needs weed 4.50 `check_disk.go` source. → research R1.
- **Q3** — the correct `volume.fsck` collection/volumeId scoping discipline, and whether
  `ec.decode -collection=default` is exact for the unnamed pool (runbook itself hedges:
  "if 'no matches', retry with `-collection=''`"). → research R1.
- **Q4** — the seaweedfs-mcp spec card's UNVERIFIED items (which weed 4.50 HTTP endpoints are
  stable and auth-free, e.g. `/storage/ec-shards`, `/api/files/properties`, `/status` payload
  size — note the ~1,709 lines/hour `error writing JSON status /status` churn at note
  lines 120-122 means a `/status`-shaped MCP tool will be slow/large). → research R2.
- **Q5** — whether the new skill should be a *debug-methodology* skill (like llama-swap's
  "Debugging checklist") or an *operations runbook* skill, and whether the split-brain/readonly/
  vacuum repair knowledge belongs in the skill or stays a pointer into the dated runbook + note
  (repo precedent for "single normative home" is strong: `tests/wekan-mcp/skill-surface.sh`
  enforces one-owner prose). This is a plan decision for `agent-plan`/user, not a fact.
- **Q6** — does `1982649`'s read-only flag and the diverged-pair set still stand after the
  11-10 12:58 restarts *plus* anything that happened since (last check was 11-10 15:30)? Needs
  a fresh `volume.list` / Loki NoSuchKey sweep the user runs.

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/EXPLORE.md]
commands_run: [
  git branch -a --format … | grep seaweed => pass;
  git log --oneline <3 branches> -1 => pass;
  git merge-base --is-ancestor <br> main => pass (NO for all three);
  git rev-list --left-right --count main...<br> => pass (13/1, 13/1, 13/5);
  git diff main..<br> --stat => pass (misleading, see gotcha 2);
  git diff main <sha> -- <file> => pass (all three empty: content already on main);
  git show --stat <branch> => pass;
  git log --oneline main -- charts/seaweedfs/values.yaml services/infra/prod/values.yaml <note+plan> => pass (4b832237c / 1e4c0f783 / ff2bc876e);
  grep -rn seadweed . => pass;
  grep -n MAINTENANCE charts/seaweedfs/values.yaml => pass (line 47 present);
  find skills -type f; awk frontmatter + grep '^## ' over skills/*/SKILL.md => pass;
  cat .opencode/opencode.jsonc + read global opencode.json skills paths => pass;
  python3 skills-lock.json inventory => pass (71 third-party, no self-written);
  grep -rln skills/ tests charts => pass; sed strata_testlib live_code_grep => pass;
  cat .github/workflows/{aislop,rulesync}.yaml; cat .aislop/config.yml => pass;
  npx aislop@0.20.0 scan skills/wekan-board-provision --json => pass (scoreable:false, md not scored);
  npx aislop@0.20.0 scan skills/ [--json] => pass (47 Critical, 39 py warnings, 6 supported files);
  npx aislop@0.20.0 scan skills/…/SKILL.md => fail (needs a directory — noted as gotcha);
  rulesync --version => pass (37.0.0); npx aislop --version => pass (0.20.0);
  execute: search dev-boards (39 tools) => pass;
  execute: tools["dev-boards"].list_lists/list_swimlanes/get_board => pass (read-only);
  execute: tools["readonly-infra-kubernetes"].pods_get(seaweedfs-admin-0) => pass;
  execute: resources_list(Pod, ns=default, labelSelector app.kubernetes.io/name=seaweedfs) => pass;
  execute: resources_list/get(argoproj.io/v1alpha1 Application infra-seaweedfs) => pass (OutOfSync)
]
deviations: "Went slightly past the three named probe sets to ground the ticket's own claim that the env-var change is UNMERGED (it is merged; content-identical on main) and to check whether Phase 0 is actually deployed — both are deliverable-1 facts the planner cannot get right without them. All work stayed read-only; no board writes, no cluster writes, no commits."
friction: "The launch brief's suggested `git diff main..<branch> --stat`/full-diff renders 1,600 lines of inverse churn and reads as if the branch deletes main's work — resolved by `git show` + two-dot content diffs against the merge-base (documented in §1.1/gotcha 2). `aislop scan` rejects file arguments (`error: Not a directory`) — pass directories. `dev-boards` has no label-listing tool — `get_board().labels` supplies them. readonly-kubernetes `resources_list` uses `apiVersion`+`kind` (not `group`/`plural`/`resource`) and returns a projected item shape (`Name`/`Sync Status`/`Health Status`) for lists, while `resources_get` returns the full CR."
open_questions: [
  "Q1 needs a decision/action outside agent grants: is infra-seaweedfs OutOfSync because automated sync is failing on the repeated-Service warnings, or merely pending? (Needs ArgoCD UI/API read or an admin-tier sync attempt; also: is the umbrella `infra` app's OutOfSync related?) Needs research: no — this is a live-cluster/decision item for the human or an admin session.",
  "Q5 is a plan-shape decision only the user/coord can make: debug-methodology skill vs operations runbook skill, and whether the repair knowledge lives in the skill or stays a pointer into the dated runbook + note (repo's single-normative-home precedent argues for the pointer). Needs research: no.",
  "R1 — Needs research: yes. SeaweedFS debugging methodology + split-brain / read-only-mark / vacuum-repair procedures against weed 4.50 sources: whether `-nonRepairThreshold 1` + `-syncDeleted` heals 1982886's 48-vs-37 unique-needle divergence or whether same-key conflicting writes make it a true split-brain; the exact `-collection`/`-volumeId` scoping discipline for volume.fsck (incl. the wrong-collection `media`-vs-`logs` failure the user hit) and whether `ec.decode -collection=default` is exact for the unnamed pool; `volume.mark -writable`/`check.disk -fixReadOnly`/`deleteEmpty` read-only-skip semantics; `volume.check.disk` non-repairable/needle-key behavior and post-run verification surfaces.",
  "R2 — Needs research: yes. Verification of the seaweedfs-mcp server spec's UNVERIFIED items against weed 4.50: which master/admin/volume HTTP endpoints are stable, auth-free and cheap (`/status` size/churn — ~1,709 `error writing JSON status` lines/hour; `/storage/ec-shards`; `/api/files/properties`; volume list/replica endpoints), which shell verbs are MCP-safe to expose as read-only vs mutation, and the container/MCP-server precedent shape (`containers/wekan-mcp`, `docker-build.yaml` tag law, `services/dev/prod/values.yaml` `boards:` block, `mcp.dev.scifi.farm/<name>/mcp` ingress)."
]
next_suggested: "Coordinator: run R1 + R2 as two `agent-research` rounds into `.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/RESEARCH.md`, then `agent-plan` — the plan should treat deliverable 1 as (a) Phase-0 deploy verification of an already-merged chart change and (b) human-run pasteable ops blocks (Phases 1-4, 1982649 mark, 1982886 check.disk with `-collection logs`, the tsdb.gz `fs.rm` + s3 restart), not as branch merges."
