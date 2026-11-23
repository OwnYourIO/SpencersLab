# RESEARCH-r1 — TypeScript-authoring skills & tooling for `card-runner`

Ticket AD-140 (`cf-140-feat-agent-card-reconcile`) · research topic R1 · 2026-11-23
Scope (from the card): **what agent skills / tooling support exists for writing TypeScript well in this
repo**, ahead of a hand-written OpenCode plugin (`card-runner`, single `index.ts` under `.opencode/plugin/`).
OpenCode-plugin-API topics are a sibling research session's scope — not covered here.
Method: STORM (survey → 5 grounded perspectives → contradiction map → sourced briefing), run inline in one
session; repo grounding first (file evidence with `path:fact` refs), web outward second. Sources are
numbered; the trail's perspectives: skill-ecosystem curator, OpenCode-platform engineer, TS-toolchain
engineer, repo quality-gate owner, agent-skill author.

## TL;DR (≤5 lines)

Real installable TypeScript skills exist but every one is niche (≤4.4K installs); the only vendorable,
authoritative candidate is **microsoft/typescript-skills** (MIT, TS-team, `typescript-strict` = exactly the
type-error repair loop we want, low adoption + npm-project assumptions). The big ecosystems (anthropics,
vercel-labs) ship **nothing** TS-specific. OpenCode's own TS assists (LSP, formatters) are schema-valid in
V2 but **off and unreachable here** (both need project deps; we have none), and OpenCode's own docs
recommend the CLI-loop approach instead. The genuine gap in our gate stack is **type-checking** (Node
type-strips without checking; aislop is static, not type-aware) — fix it with a pinned `npx tsc --noEmit`
loop + a small vendored/authored skill; skip LSP, eslint, deno, bun.

## Reliability notes (peer review)

- **Confidence per key finding** (1–10): F1 repo baseline **9** (direct file probes + tool inventory);
  F2 ecosystem map **8** (live skills.sh pages + GitHub pages fetched 2026-11-23; install counts move);
  F3 OpenCode LSP/formatter status **9** (V2 docs + live schema fetch + config greps); F4 Node
  type-stripping constraints **9** (v26 API doc quoted); F5 TS 7.0 era facts **9** (official announcement +
  live npm registry); F6 `tsc`-needs-`@types/node` consequence **8** (see weakest claim).
- **Weakest claim**: "a bare `tsc --noEmit` over the plugin files fails without `@types/node` installed"
  (`import "node:fs/promises"` → TS2307-style module errors; TS 7 also defaults `types` to `[]` [7]).
  It follows from [6][7][8] but was **not executed** here (it would create an npx cache + resolve state in
  the worktree — the offline-suite law; plan should run the 10-second probe before committing to the shape).
- **Over-weighted perspective**: the toolchain engineer's (my own framing of the loop) — the repo may
  rationally decline any typecheck gate; the plan owner decides.
- **6th angle that could change conclusions**: OpenChamber-host-side behavior — agents editing TS on the
  OpenChamber server may already receive diagnostics through channels invisible to this repo's config
  (same unknown-process caveat as EXPLORE-plugins OQ-1). A live-host probe is the only check; not
  researchable from here.

## F1 — Repo baseline: what exists today (all file-verified)

- **Zero TS tooling in the repo**: no `package.json`, `tsconfig.json`, eslint/prettier/biome config at the
  root or anywhere relevant (`ls` probe at repo root, 2026-11-23; empty match); `.gitignore` has **no**
  `node_modules`/`package-lock` entry (`path:.gitignore` — only Python/Hugo/rulesync/pipeline entries), so
  any npm-style tooling surface is a *new* decision, not an ignored leftover.
- **Tool inventory in the agent shell** (probe 2026-11-23): `node v26.5.0` (nvm) present;
  **absent**: `tsc`, `eslint`, `prettier`, `deno`, `bun`, `biome`, `oxlint`. npm registry is reachable
  (`npm view typescript version` → `7.0.2`), so the supply mode is **pinned npx**, exactly the precedent
  aislop runs on (`npx --yes aislop@0.20.0` in `.opencode/plugin/aislop-gate/index.ts` +
  `.github/workflows/aislop.yaml`, parity-guarded by `tests/opencode/aislop-pin-parity.test.ts`).
- **How the existing TS surfaces work**: the four plugins and the 10-file offline suite are `.ts` executed
  directly — `node --test tests/opencode/*.test.ts` rides Node's built-in **type stripping**:
  "no type checking is performed" [6]; suite header pins "no build step, no npm deps, no network"
  (`path:tests/opencode/aislop-pin-parity.test.ts`). The plugins already honor the erasable-syntax law
  (probe: zero `enum`/runtime-`namespace`/parameter-properties in `.opencode/plugin/*/index.ts`), use
  `node:`-prefixed imports, and local imports **with `.ts` extensions**
  (`import { localIso } from "../pipeline-locks/index.ts"` — board-context, the one sanctioned
  cross-plugin import, `path:EXPLORE-plugins.md §0`).
- **Quality gates that already touch TS**:
  - `aislop` (pinned npx): deterministic scanner over 7 languages incl. TypeScript; rule families relevant
    here: `as any` casts, swallowed exceptions, hallucinated imports, narrative comments, oversized
    functions; engines `format/lint/code-quality/ai-slop/security` on; CI gate = per-touched-file score
    floor 80 + no error-severity (`path:.aislop/config.yml`, `path:.rulesync/skills/aislop/SKILL.md`).
    **Static, never type-aware.**
  - `aislop-gate` plugin: runs `npx --yes aislop@<pin> scan --changes` after every edit/write to a
    code-extension file (regex includes `.ts`) and appends findings in-session
    (`path:.opencode/plugin/aislop-gate/index.ts`).
  - `comment-slop` skill (SHA-pinned vendor, `path:.rulesync/skills/comment-slop/VENDORED.md`): comment
    hygiene incl. docstring/doc-parity law for the plugin family.
  - The `node --test` suites + shell `surface.sh` greps pin behavior and text contracts — runtime pins
    only; a pure **type error** that never executes is invisible to every one of these gates.
- **Skill plumbing in the repo** (how any new skill lands): three homes with precedents —
  `.agents/skills/` third-party, git-tracked, integrity-hashed in root `skills-lock.json`
  (`sourceType: "github"`, `skillPath`, `computedHash`; sources include `obra/superpowers`,
  `bmad-code-org/BMAD-METHOD`); `.rulesync/skills/` for vendored skills with hand-applied deviations +
  `VENDORED.md` (the `aislop` / `comment-slop` pattern: source `owner/repo`, pinned commit, deviations
  list, re-apply on re-vendor); `skills/` for self-written skills. OpenCode V2 discovers
  `.opencode/skills` (project), `.agents/skills` (compat), plus the `skills` array in
  `opencode.jsonc` (`path:.opencode/opencode.jsonc` skills entry; discovery order per [5]).
  `rulesync fetch owner/repo` is the documented fetch primitive (`path:.agents/skills/rulesync/SKILL.md:47`).
- **`.opencode/opencode.jsonc` has NO `lsp` and NO `formatter` key** (grep, both project and
  machine-global `~/.config/opencode/opencode.json` — none in either).

## F2 — Published TypeScript-authoring skills: the real landscape

**The mainstream ecosystems ship nothing TS-specific.** `anthropics/skills` = 21 skills / 4.0M installs
(frontend-design, skill-creator, mcp-builder, webapp-testing, docs suite …) — no TypeScript skill [14].
`vercel-labs/agent-skills` = 16 skills / 3.4M installs — React/Next/design/deploy; the closest,
`vercel-react-best-practices` (926K installs), is framework work, not typed-Node plugin authoring [13].

The TS-specific field (all small; verified 2026-11-23):

| Skill / source | What it does | Health | Vendorable? |
| --- | --- | --- | --- |
| **`microsoft/typescript-skills`** (`typescript-strict`, `typescript-project-setup`, `typescript-update`, `typescript-build-references`, `typescript-publish-types`) [9][10] | strict-mode activation + **type-error repair loop with anti-loophole law**: baseline-first, "Do not add opt-outs to get green: no `strict: false`, … `@ts-expect-error` is preferred over `@ts-ignore` — it fails if the error goes away"; warns the bare-`npx tsc` stub trap [12] | Official TS team, **MIT**, agentskills.io format, 47 commits, **5 stars / 124 installs total** (young, created ~2026) | **Yes** (MIT; needs adaptation — assumes package.json/npm-CI projects) |
| `marius-townhouse/effective-typescript-skills` — 83 skills, 4.4K installs, one per Effective TypeScript (2nd ed, Dan Vanderkam) item (`tsconfig-options`, `prefer-unknown-over-any`, `tagged-unions`, …) [15] | granular per-item best practices | 3 stars, solo author, **license "Other"** (book-derived text) | **No** as-is — license/derivation risk for vendoring; browsable as reference |
| `metabase/metabase` `typescript-review` [19] | org code-standards review | ~2.2K installs, **no license** stated | **No** (unlicensed) |
| `aiagentskills/skills` `typescript-review` [16]; `cr0wg4n/dev-skills` `ts-code-review` (offline bundled guidelines file — good pattern) [17]; `jamie-bitflight/claude_skills` `code-review-typescript` (strict-mode inspection rules) [18]; `mihailtd/skills` `typescript-best-practices` [21]; `Kong/ksai-public` `typescript-code-review` (adversarial, "80 TS/JS mistakes" catalog, 0-star repo) [20] | review-oriented skills, mixed quality | all single-digit-hundreds installs, unknown authors | **Skip** — overlapping aislop + the two vendored review skills we already run; supply-chain posture (find-skills skill itself: be skeptical <100 installs / <100-star repos, `path:~/.claude/skills/find-skills/SKILL.md`) |

**Contradiction C1 — install-count heuristic vs reality.** The repo's own `find-skills` skill says prefer
1K+ installs, distrust <100. *Every* purpose-built TS skill fails that bar except the unlicensed Metabase
one. Weighting: for a **vendored-and-audited** adoption (the lab's `VENDORED.md` pattern already pins
commits and diffs deviations), source authority (the actual TypeScript team) + MIT license outrank the
install heuristic — but the heuristic stays valid for the anonymous review-skill tail, which we do skip.

## F3 — OpenCode's own TS support: configured? No. Reachable? Not without deps.

- **V2 (installed: `opencode v2.3.2`) still exposes both keys**: live fetch of `https://opencode.ai/config.json`
  shows `lsp` and `formatter` in the schema properties [4]. **Neither the project nor the machine-global
  config sets either** (F1 grep) → both default off ("Formatters are disabled by default" [3]; "LSP is
  disabled by default" [1]).
- **Enabling them buys nothing in their current shape**: the documented TS entries are dependency-gated —
  typescript LSP requires "typescript dependency in project", eslint/oxlint LSPs require the dep, prettier
  formatter requires "prettier dependency in `package.json`", biome requires `biome.json` + installed binary
  [1][3]. This repo has **no package.json at all** → `lsp: true`/`formatter: true` alone would start
  nothing for TS files.
- **OpenCode's own docs side the debate for us**: the LSP page's Best Practices says language servers "can
  get out of sync, use significant memory … In many projects it is better to have the agent run lint,
  typecheck, or other diagnostic CLI tools directly, so errors are fed back into the agent loop …
  Document those commands in instruction files such as `AGENTS.md` **or skills**" [1]. That sentence is
  literally the shape of this ticket's recommendation.
- **Contradiction C2 — V1 vs V2 docs**: the LSP page is labeled "docs for OpenCode V1"; the V2 docs index
  lists **no LSP page at all** (Formatters is there; `lsp` remains in the machine-readable schema) [2][4].
  Weighting: the feature evidently exists in V2 (schema + running server) but its V2 semantics are
  under-documented — a second reason to build the CLI loop and not bet the workflow on LSP.

## F4 — Node's built-in TypeScript runtime: the contract the plugin already lives under

From the Node v26 API doc ("Modules: TypeScript", Stability 2 Stable) [6]:

- Type stripping "replaces TypeScript syntax with whitespace, **and no type checking is performed**".
- Node **ignores `tsconfig.json`** entirely (no paths, no downleveling); `.tsx` unsupported.
- **Erasable-syntax-only law**: `enum`, runtime `namespace`, parameter properties, import aliases,
  decorators → `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX`. (Probe: the existing four plugins are clean.)
- **File extensions are mandatory in imports** (`import './file.ts'`) — the reason `board-context` imports
  `../pipeline-locks/index.ts`; and "the tsconfig.json option **`allowImportingTsExtensions`** will allow
  `tsc` to type-check files with import specifiers that include the `.ts` extension" [6].
- **`type` keyword is mandatory** for type-only imports (`import type` / `import { fn, type X }`) or the
  strip leaves a value import that fails at runtime; tsconfig mirror: `verbatimModuleSyntax` [6].
- Node's own recommended tsconfig for type-stripped code:
  `{ noEmit, target "esnext", module "nodenext", rewriteRelativeImportExtensions, erasableSyntaxOnly, verbatimModuleSyntax }` [6].
- Node ≥ 22.18 runs TS CLIs directly — the MS setup skill: "`tsx` is no longer necessary … Enable
  `erasableSyntaxOnly` and `rewriteRelativeImportExtensions` … run `node src/index.ts`" [11].

## F5 — The TypeScript 7.0 era changes the economics of the checker loop

- TS 7.0 (npm `latest` = **7.0.2**, live probe; announced 2026-07-08) is the **native Go port, 8–12×
  faster full builds** (vs code: vscode 125.7s→10.6s) — a ~1s full `tsc --noEmit` over a four-plugin repo,
  cheap enough for a per-edit/per-chunk loop [7]. 7.0 ships `tsc`; the API is absent until 7.1 (types-only
  use here, fine); `@typescript/typescript6` (6.0.2, live probe) is the API bridge for tools like
  typescript-eslint [7].
- **7.0 hard-defaults that hit a fresh tsconfig**: `strict: true`, `module: esnext`, `types: []` (must list
  `["node"]` explicitly to get Node globals), plus hard errors for legacy flags (`moduleResolution:
  node10`, `baseUrl`, `target: es5`, …) and "command line builds cannot take file paths when the current
  directory contains a `tsconfig.json` unless `--ignoreConfig`" — i.e. drive it with `-p <config>` [7][8].
- **The `npx tsc` trap is real**: the npm `tsc` package is a deprecated 2.0.4 stub ("A deprecated release
  of the TypeScript compiler", live probe); the MS skill warns the same ("Never use bare interactive
  `npx tsc` … it can offer to install the unrelated npm package `tsc`") [12]. The correct invocation for
  this repo's zero-dep supply chain: **`npx --yes --package=typescript@<pin> -- tsc --noEmit -p <tsconfig>`**
  (same pinned-npx law as aislop).
- `deno check` / `bun` — both binaries **absent** in the agent shell (F1 probe); installing a second runtime
  to type-check is out of proportion: skip.

**Contradiction C3 — checker needs deps, repo ethos is zero-deps.** A *real* type-check needs ambient
types for `node:fs`/`process` etc. — i.e. `@types/node` resolvable from the checked tree (TS 7's `types:
[]` default makes even more explicit [7]). The repo's tests law says "no npm deps"; there is no
`node_modules` gitignore line. Weighting: the options, cheapest first —
(a) **No typecheck** (status quo): type errors stay invisible until runtime; acceptable but that's exactly
the gap R1 was asked about.
(b) **Check what's checkable**: `tsc --noEmit` with `types: []` and `SkipLibCheck`-free lib-only run —
catches intra-file/inter-file structural errors inside our own code, but every `node:*` import errors;
needs per-file triage → practically noisy, not recommended.
(c) **One small dev-tooling surface** (recommended if the owner wants the gate): a `tools/ts/` (or root)
`package.json` + `tsconfig.json` pinning `typescript@7` + `@types/node` (+ optionally the plugin type
package), `npm ci` once, `.gitignore` gains `node_modules/`, loop = pinned local `tsc`. This is the MS
skill's shape minus the app-project parts; it is a **plan/owner decision** (first npm surface in the repo),
not an agent default.

**Contradiction C4 — MS skill flow vs Node doc flow for the tsconfig.** The MS skill starts at
`tsc --init` (a generated compat-flavored config); Node's doc prints an explicit minimal config tuned to
type-stripping [6][11]. Weighting: for a noEmit-only, Node-run repo, **hand-write the Node-doc config**
(plus `allowImportingTsExtensions` [6], `types: ["node"]`, `strict`); never generate it.

## F6 — What a `card-runner` author-loop should look like (synthesis)

Per edit/chunk, in order, all commands npx-pinned or repo-local:

1. `node --test tests/opencode/<file>.test.ts` — existing runtime pin (works today).
2. **NEW:** pinned `tsc --noEmit -p <tsconfig>` (option C3c) — the only surface that catches type errors
   before runtime; TS7 makes it ~free [7].
3. `npx --yes aislop@<pin> scan --changes` — already automatic via `aislop-gate` after edits.
4. `comment-slop` discipline on the diff — already repo law.
Optional middle: `npx --yes --package=oxlint@<pin> -- oxlint` as a zero-config lint pass — skip unless the
plan wants lint beyond aislop; **skip eslint** (config+plugin dep tree), **skip prettier-via-OpenCode**
(dep-gated and our formatting is governed by aislop's format engine + the pin families' byte expectations
— auto-reflowing pinned test fixtures is a hazard).

## Contradictions and how to weigh them (summary)

- **C1** install-count heuristic vs TS-skill reality → vendor with audit beats count; count still vetoes
  the anonymous tail.
- **C2** V1 LSP docs vs V2 silence → don't build on LSP; build the CLI loop OpenCode's own docs recommend.
- **C3** typecheck needs deps vs zero-dep ethos → owner decision; recommend the smallest `tools/` surface
  only if the gate is wanted; the skill must encode whichever posture the plan picks.
- **C4** `tsc --init` (MS) vs hand-written Node-shaped tsconfig → hand-write; never generate.

## Implications for the plan — adopt vs skip

**ADOPT**
1. **Vendor `microsoft/typescript-skills@<pin> --skill typescript-strict`** via the established vendoring
   pattern (`.rulesync/skills/` + `VENDORED.md` if adapted for the npx/no-package.json posture — the
   aislop precedent; or `.agents/skills/` + `skills-lock.json` entry if taken unmodified). MIT clears it;
   record a deviation note either way. Its repair-loop law (baseline first; no opt-outs to get green;
   `@ts-expect-error` over `@ts-ignore`; the `npx tsc` stub warning) is the highest-value imported text.
2. **Author one small repo-local skill** (self-written `skills/` home, following `writing-skills` SDO
   rules): "TypeScript in the plugin lanes" — the F4 contract (erasable-only, `type`-keyword law, `.ts`
   extension imports, `node:` prefixes), the pinned-tsc command + hand-written tsconfig flags (F5/C4), the
   F6 loop, and the repo's supply posture (pinned npx only; no new runtime). Keep <500 words;
   consider `disable-model-invocation` if it should run only when explicitly launched (aislop precedent).
3. **If the owner wants the typecheck gate** (single plan question): add `tools/ts/package.json` +
   `tsconfig.json` (`typescript@7.0.x`, `@types/node`, `allowImportingTsExtensions`+`noEmit`,
   `erasableSyntaxOnly`, `verbatimModuleSyntax`, `module/moduleResolution nodenext`, `types:["node"]`),
   `.gitignore` `node_modules/`, and the tsc line into every card-runner chunk's Commands list. Verify the
   C3-weak-claim probe (bare tsc without @types/node) before finalizing the chunk list.
4. **Keep the existing gates** unchanged: `aislop-gate` (auto), `aislop ci --changes` (CI floor 80),
   `node --test` suite, `comment-slop` — the skill must tell agents these exist (prevention-first).

**SKIP**
- OpenCode `lsp`/`formatter` enablement for TS (dep-gated, V2-doc-silent, docs themselves recommend CLI
  loops [1][3]); eslint (dep tree + config churn); prettier auto-formatting (byte-pin hazard + dep);
  `deno check`/`bun` (binaries absent); the anonymous review-skill tail (Kong/aiagentskills/cr0wg4n/
  jamie-bitflight/mihailtd — overlap with aislop, unvetted supply); `marius-townhouse` per-item pack and
  `metabase/typescript-review` (license "Other"/none → fails the vendoring bar); `vercel-react-best-practices`
  (wrong domain).

## Open questions (for coord / plan / owner)

1. **Owner ruling needed**: adopt the typecheck gate (C3c — the repo's first npm dev surface, +2 lines
   .gitignore) or keep the zero-dep no-typecheck posture and let the skill only encode the constraints +
   runtime loop? Both are defensible; the plan must not decide silently.
2. **Vendoring home** for `typescript-strict`: `.rulesync/skills/` + VENDORED (adapted, Claude-mentions
   likely need removal — the aislop precedent) vs `.agents/skills/` + `skills-lock.json` (unmodified)?
3. Where should the new skill's Commands live for CI-parity: plan Commands per chunk is the established
   runner for the offline suites (EXPLORE-plugins §5.4) — should `tsc --noEmit` join `.github/workflows/
   aislop.yaml`, stay plan-Commands-only, or become an `aislop-gate`-style second in-session check?
4. Adjacent fact to schedule: the aislop pin is drifting (repo pins 0.20.0; npm latest 0.22.3, live
   probe) — a bump touches exactly the 3 homes the parity test names; worth a follow-up card, not AD-140.

## Sources

- [1] https://opencode.ai/docs/lsp — OpenCode LSP Servers (V1-labeled page; built-in table, defaults-off, Best Practices)
- [2] https://opencode.ai/docs/llms.txt — OpenCode V2 documentation index (no LSP page; Formatters present)
- [3] https://opencode.ai/docs/formatters/ — OpenCode V2 Formatters (disabled by default; prettier/biome/oxfmt dep requirements)
- [4] https://opencode.ai/config.json — OpenCode config schema, fetched live 2026-11-23 (`lsp`, `formatter` properties present)
- [5] https://opencode.ai/docs/skills — OpenCode V2 Skills (discovery sources incl. `.agents/skills`, precedence, autoinvoke frontmatter)
- [6] https://nodejs.org/api/typescript.html — Node.js v26 "Modules: TypeScript" (no type checking; tsconfig ignored; erasable-only; mandatory extensions; `allowImportingTsExtensions`; recommended tsconfig)
- [7] https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/ — TypeScript 7.0 announcement, 2026-07-08 (native port, 8–12×, strict/types defaults, `tsc --ignoreConfig` rule, 7.1-API timeline)
- [8] https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/ — TypeScript 6.0 announcement, 2026-03-23 (deprecation bridge list inherited as 7.0 hard errors)
- [9] https://www.skills.sh/microsoft/typescript-skills — listing: 6 skills / 124 installs (typescript-strict 39 …)
- [10] https://github.com/microsoft/typescript-skills — repo: MIT, 5 stars, 47 commits, plugin/skill layout (agentskills.io)
- [11] https://raw.githubusercontent.com/microsoft/typescript-skills/main/plugins/typescript/skills/typescript-project-setup/SKILL.md — setup recipe (types:["node"]+@types/node; erasableSyntaxOnly; node≥22.18 runs TS directly)
- [12] https://www.skills.sh/microsoft/typescript-skills/typescript-strict — strict-mode repair-loop SKILL.md (baseline-first; no-opt-out law; `npx tsc` stub warning)
- [13] https://www.skills.sh/vercel-labs/agent-skills — 16 skills / 3.4M installs; no TS-authoring skill
- [14] https://www.skills.sh/anthropics/skills — 21 skills / 4.0M installs; no TS-authoring skill
- [15] https://www.skills.sh/marius-townhouse/effective-typescript-skills + https://github.com/marius-townhouse/effective-typescript-skills — 83 skills / 4.4K installs; Vanderkam book-derived; license "Other"; 3 stars
- [16] https://www.skills.sh/aiagentskills/skills/typescript-review
- [17] https://www.skills.sh/cr0wg4n/dev-skills/ts-code-review
- [18] https://www.skills.sh/jamie-bitflight/claude_skills/code-review-typescript
- [19] https://deska.dev/skills/metabase/metabase/typescript-review — ~2.2K installs, no license
- [20] https://skillsmp.com/creators/kong/ksai-public/plugins-kreview-skills-typescript-code-review — 0-star repo, adversarial-review catalog
- [21] https://github.com/mihailtd/skills — typescript-best-practices (personal collection, MIT)
- [22] Live npm-registry probes, 2026-11-23 (agent shell): `typescript` latest 7.0.2 / next 7.1.0-dev; `tsc` = deprecated 2.0.4 stub; `@typescript/typescript6` = 6.0.2; `aislop` latest 0.22.3; `@opencode-ai/plugin` 1.19.6; local tool inventory (node v26.5.0 only)
- In-repo evidence (no URL): `AGENTS.md`; `.opencode/opencode.jsonc`; `~/.config/opencode/opencode.json`; `skills-lock.json`; `.aislop/config.yml`; `.rulesync/skills/aislop/{SKILL.md,VENDORED.md}`; `.rulesync/skills/comment-slop/VENDORED.md`; `.opencode/plugin/aislop-gate/index.ts`; `.opencode/plugin/board-context/index.ts`; `tests/opencode/*` (import shapes, offline-suite law); `.gitignore`; `EXPLORE-plugins.md` (sibling scout file, this folder); `~/.claude/skills/find-skills/SKILL.md` (machine-level install-heuristic skill)

---

RESULT
status: DONE
chunk: R1
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/RESEARCH-r1-typescript-skills.md]
commands_run: [repo/tool inventory probes => pass, npm registry probes (typescript/tsc/aislop/@typescript/typescript6) => pass, V2 config schema fetch+jq => pass, web survey (opencode docs, node docs, TS 6/7 blogs, skills.sh/GitHub) => pass]
deviations: no RESEARCH.md written per launch instruction — own sibling file RESEARCH-r1-typescript-skills.md; storm run trail embedded in the file (sources + perspectives) instead of a storm-runs/ dir, to avoid polluting the folder during the parallel-research round
friction: two webfetch round-trips through a rewriting proxy 403'd (re-fetched direct URLs OK); skills.sh pages are JS-heavy but rendered via the fetch pipeline fine
open_questions: (1) owner ruling on typecheck gate = repo's first npm dev surface vs zero-dep posture; (2) vendoring home for typescript-strict (.rulesync/skills+VENDORED vs .agents/skills+skills-lock); (3) whether tsc joins CI or stays plan-Commands; (4) aislop pin drift 0.20.0→0.22.3 — follow-up card
next_suggested: plan consumes R1 with the plugin-skills + sibling RESEARCH files; if the typecheck gate is wanted, add a plan question (owner) and the 10-second bare-tsc probe before freezing chunk Commands
