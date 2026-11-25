# PLAN: cf-139 — Pushes to main auto-sync every cluster (no manual `argocd sync`)
feature: 2026/2026-11-cf-139-feat-argocd-webhook-sync
card: AD-139 "Sync ArgoCD with Webhooks" (Y3vPeX4nhtDbsdwCg)
status: REOPENED³ 2026-11-25 (STATE `reopen3`, card comment DM2pP35CGPbCjAWXu). Owner
ruling R7 re-cuts the VAULT INPUT MECHANISM only: no single-blob secret — per-cluster
org key PAIRS the script discovers from its environment. Waves 7–9 (C05–C08, shipped at
tip `6ed762140`, 38/38 suites) stay DONE history: the fan-out semantics, the job shape,
the disposals and the operator doc all stand — this round replaces the input layer
(`parse_vault` + roster `targets[]` + the single-secret env map + the runbook paste
mechanics) and nothing else. The ruling is COMPLETE: no batched round needed, residual
micro-calls are pinned below (DECISIONS 2026-11-25), plan stays APPROVED.
History: APPROVED 2026-11-17 (relay era, OQ1–OQ7); reopen1 2026-11-21 (R1–R4,
Forgejo-origin); reopen2 2026-11-23 (R5/R6 vault-direct; batched round newline/warn-skip/
indefinite/ORG-scope); reopen3 2026-11-25 (R7 per-cluster key pairs).

## Goal

A push to `main` lands on every cluster automatically, driven by the canonical Forgejo
repo's own CI: the `.forgejo/workflows/main-sync.yaml` `sync-fanout` job (after
`push-gh` — R1 option (c) untouched) runs `scripts/argocd-fanout.py`, which POSTs real
syncs to each cluster's ArgoCD REST API. Endpoints + credentials now come from the
**environment**: org Vars `ARGOCD_SYNC_<CAT>_URL` paired with org Secrets
`ARGOCD_SYNC_<CAT>_TOKEN` (category upper-snake: `gpu-ai`→`GPU_AI`,
`proxy-remote`→`PROXY_REMOTE`); the script BUILDS its target list by scanning its
environment for the `ARGOCD_SYNC_*` pairs — **no category list in code or JSON** (R7).
Kill-switch, appset gates, Bitwarden-free posture, zero in-cluster components: all
unchanged from reopen2.

## Scope decisions — R7 + the pinned consequences

- **R7 (supersedes OQ8's MECHANICS, not its spirit):** the single-blob paste was ruled
  too error-prone. Per-cluster Actions keys per RESEARCH §2 option (2) — the strongest
  masking shape (each token is a native single-line secret; no [26] per-line claim, no
  multi-line-paste UI leg, no record grammar, no reversed-echo class). Costs taken
  knowingly: static enumeration rows in the workflow per fleet change, and no dynamic
  secret indexing (`${{ secrets[matrix] }}` unsupported [21][25]) — the second is why
  discovery lives IN THE SCRIPT's env scan, not in expressions.
- **Consequence (1), ruled — pair integrity (reversible):** the workflow passes every
  enumerated key, so an unset org key arrives as an EMPTY STRING — the script's
  empty-detection is the guard, no shell guard, no expression can catch it. Semantics:
  a fleet is **configured iff at least one non-empty `*_TOKEN` value exists** (token-side
  keying is what makes the §7 kill lever work: deleting the 11 token secrets ⇒
  all-absent). All-absent ⇒ designed warn-green skip: `::warning::sync-fanout not
  configured (no ARGOCD_SYNC_*_TOKEN keys with values) — fan-out skipped, manual sync or
  the next push covers it`, exit 0, zero sockets. Once configured, EVERY discovered
  category must be a complete valid pair — partial pair, empty-string residue, or
  malformed value ⇒ config RED: one aggregated `argocd-fanout config:` stderr line naming
  every offending CATEGORY (sorted, value-free), exit 1. Decommissioning a cluster =
  org keys + its 2 workflow enumeration rows in the SAME release (lockstep doctrine,
  mirrors [P §3]) — a deleted key alone leaves empty residue and reddens until the rows
  go.
- **Consequence (2), ruled — static enumeration:** the job's `env:` block grows exactly
  22 lines (11×URL via `vars.`, 11×TOKEN via `secrets.`), one pair per fleet category,
  plus `EVT_REF`/`GH_REF`. Adding a cluster = 2 org keys + 2 rows (PR-reviewable).
- **Consequence (3), ruled — roster shrinks to GLOBALS:** `scripts/argocd-fanout.json`
  keeps `allowed_refs`, `tracked_repo` (GLOBAL stays — one GitHub URL for all clusters,
  [P §3] lockstep law unchanged), `settle_seconds`, `target_timeout_seconds`,
  `parallel_workers`; the `targets[]` ARRAY DELETES — URLs come from env, and
  root_app == category == discovered name is a CODE convention (the fleet's roots are
  named by category, [E §2]). **Route-truth test duty relocates:** the repo can no
  longer test-pin 11 hosts (they are instance-side now); the verification surface moves
  to the runbook §6 table + the `--check` pair listing + the dispatch smoke — the
  doctrine's text ("live-verified, never guessed") transfers to the runbook.
- **Consequence (4), ruled — masking simplifies:** native per-secret masking [21][22];
  the runbook §5(c) [26]-verification leg and §2 multi-line-paste UI leg DROP; the
  comma/newline-tolerant parser and the M1 reversed-record arm DIE with the blob. The
  no-value-echo law (AC8) survives and matters MORE: pair errors must name categories,
  never the offending URL-adjacent values or tokens.
- **Category law (pinned, with its collision thought):** env segment ⇒ category is
  `lower()` + `_`→`-`. All 11 current categories are hyphen-only DNS labels, so the
  mapping is injective (`GPU_AI`→`gpu-ai`). The rule constrains the future: a category
  named with a literal underscore is NOT REPRESENTABLE (its env name is indistinguishable
  from a hyphenated sibling's — `foo_bar` and `foo-bar` would collide on one env key, and
  env uniqueness silently picks one winner, undetectable at scan time); dots are
  unrepresentable too (`vars.A.B` parses as property access). Enforcement (broad-catch,
  pinned): any key matching `^ARGOCD_SYNC_(.+)_(URL|TOKEN)$` whose segment violates
  `[A-Z0-9][A-Z0-9_]*[A-Z0-9]` (no leading/trailing/double `_`) or whose derived
  category fails `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` goes RED naming the raw key when its
  value is NON-empty (a typo'd enumeration row must never vanish silently — that is the
  silent-loss class again); empty malformed residue is ignored. If someone ever creates
  keys for a literal underscore category anyway, the derived hyphen name simply finds
  no matching root app — an honest `skipped`/`failed` line, never a silent success.
- **Unchanged, explicitly:** `needs: push-gh` + exact ROLE guard + checkout + bare
  invocation line; root-first→settle→sweep, byte `repoURL == tracked_repo` + live
  targetRevision match (OQ7), prune=false query+body non-force (OQ6), 409-as-success,
  per-target isolation + 60 s timeouts + ThreadPool(4), the audit/summary grammar, the
  all-skipped `::warning::` (column 0), the no-follow redirect opener (M2), the
  config-RED/runtime-green exit posture, ref gate, proxy-backup + proxy-local ruled
  expectations ([P2], OQ9, the 307 finding), the disposals (C07 closed), kill-switch
  annotations, charts/base, appset gates.

## Context — shipped facts this round re-cuts around (read tip `6ed762140`)

- `scripts/argocd-fanout.py` 440 L: `load_roster` (six-key schema incl. `targets`),
  `parse_vault` (blob `[,\s]+` records, first-colon split, M1 reversed arm, set-equality
  red), the fan-out core, `cmd_check` (prints the roster targets table + `vault: N
  records matched…` line). The core + `_NoRedirect` + `drive_target`/`fan_out` are NOT
  touched; `load_roster`/`parse_vault`/`main`'s wiring + `cmd_check`'s table ARE the
  redesign surface.
- `scripts/argocd-fanout.json`: globals + 11 targets (targets array dies; globals stay
  byte-true, `tracked_repo` unchanged).
- `.forgejo/workflows/main-sync.yaml` `sync-fanout`: env block `ARGOCD_SYNC_TOKENS` +
  `EVT_REF`/`GH_REF`; run block = shell `-z` unset guard (org-worded warning) → REF
  chain → unguarded python call. The guard LINE + the blob map die (posture moves into
  the script — consequence 1); the REF chain + invocation byte-true stay.
- Suites: `tests/argocd-fanout/behavior.sh` (12 legs, blob-parser matrix in t3/t4/t5,
  roster byte-pins incl. 11 targets in t2, vault env plumbing in the harness `run()`);
  `tests/services/forgejo-main-sync.sh` (t5 single-secret exactly-once + no-vars-twin +
  header org-sentence legs; t11 blob env-map + invocation; t12 shell-guard regex +
  pinned warning string; t13 roster `json.load`); `tests/notes/argocd-fanout-runbook.sh`
  (parity greps read LANDED files — hence its re-pin rides waves 10–11 completion).
- `tests/argocd-fanout/disposal.sh` untouched — nothing it pins changes.
- Runner/vault mechanics [21][22][25][27]: org secrets/vars inherit to repos with
  repo→org→user resolution (repo twin would silently WIN — the runbook's single-instance
  sentence survives); unset keys render EMPTY into the step env; values surface only via
  `${{ }}`-mapped env; native masking per secret value.

## Out of scope (unchanged from reopen2 + this round)

- Any fan-out SEMANTICS change (the ruling is input-mechanism only). Re-introducing any
  blob/record grammar. Re-creating relay-era surfaces. Annotation flips, `charts/base`,
  appset gates, argocd-notifications, per-cluster exposure, webhook creation. The
  proxy-local 307 remedy (separate owner call, recorded 2026-11-23). Backwards
  compatibility with `ARGOCD_SYNC_TOKENS`: NONE — the blob name is banned everywhere;
  the owner-side delete-check leg (§2.4) sweeps a possibly-created key.

## Commands (validation-first)

- `export PATH=$HOME/.local/bin:$PATH` (helm legs).
- C09: `python3 -m py_compile scripts/argocd-fanout.py`;
  `python3 -c "import json; r=json.load(open('scripts/argocd-fanout.json')); assert set(r)=={'allowed_refs','tracked_repo','settle_seconds','target_timeout_seconds','parallel_workers'}"`;
  `bash tests/argocd-fanout/behavior.sh` (re-pinned legs t1–t13);
  offline pair-discovery arms need NO network (fake-transport localhost only).
- C10: `bash tests/services/forgejo-main-sync.sh` (t5/t11/t12/t13 re-pinned; t9/t10
  byte-true; `bash -n` + py_compile + globals-schema parse legs) — THE `.forgejo`
  validation shape, no actionlint precedent.
- C11: `bash tests/notes/argocd-fanout-runbook.sh` (re-pinned for rewrite #4: per-pair
  creation legs, paste/composition/line-masking legs BANNED, kill-lever wording,
  three-key delete-check incl. `ARGOCD_SYNC_TOKENS`, parity greps against landed
  C09/C10 files).
- Chain regression: `bash tests/argocd-fanout/disposal.sh` (unchanged pins) +
  `git diff --name-only` scope law (no `services/*/templates/appset.yaml`, no
  `charts/base/**`, no `renovate.json`; this round touches exactly
  `scripts/argocd-fanout.py`, `scripts/argocd-fanout.json`,
  `.forgejo/workflows/main-sync.yaml`, the three suites, the runbook).
- `npx aislop ci --changes` clean on every touched file at review; no docker (none of
  this is container code); no helm trio (chart disposed, absence stays asserted by
  disposal.sh).

## Chunks (reopen3 table)

| id | title | size | wave | status | depends_on | why the dependency |
|----|-------|------|------|--------|------------|--------------------|
| C01…C08 | relay era + vault-direct waves 1–9 (input mechanics of C05/C06/C08 superseded at reopen3; fan-out semantics, disposals, docs spine stand) | — | 1–9 | **done-at-review history** | — | untouched |
| C09 | fan-out engine INPUT redesign: env pair discovery + category law + roster globals-only + `--check` from pairs + behavior.sh re-pin | M | 10 | pending | [] | the interface C10's env block and C11's docs consume; core fan-out semantics byte-untouched |
| C10 | main-sync.yaml: 22-line org key-pair env map, blob map + shell guard deleted, header/job comments reworded + forgejo-main-sync t5/t11/t12/t13 re-pin | S | 11 | pending | [C09] | the workflow hands env to the discovery contract C09 lands; the posture (warn-green) moved INTO the script, so the file must drop its guard in the same release |
| C11 | runbook rewrite #4: §2 org vars+secrets creation (no paste/composition), §2.4 three-key delete-check, §5 drop [26]/paste-UI legs → native masking spot-check, §7 kill lever = delete 11 org TOKEN secrets, §8 per-key rotation + decommission lockstep | S | 12 | pending | [C09, C10] | the suite's parity greps read the landed files (brief: rides their landing); docs-parity last, as every reopen has ordered it |

Test sessions (repo law — tests precede dev, TWO launches this round): **pre-wave-10**,
ONE session re-pins `tests/argocd-fanout/behavior.sh` (env-discovery matrix, globals
roster pins, harness env plumbing, dropped blob arms, new pair/kill-lane legs) and the
`forgejo-main-sync.sh` legs (t5 pair matrix, t11 env-map shape, t12 guard-ban +
script-owned posture cross-reference, t13 globals-schema leg) — designed-red until
C09/C10 land. **At wave-12 start**, a short test launch re-pins
`tests/notes/argocd-fanout-runbook.sh` to the rewrite-#4 contract (red until C11 lands);
it cannot ride the first session because its parity greps must quote the C09/C10-landed
files.

## Wave order

10. C09 → 11. C10 → 12. C11 (runbook-test re-pin executes first inside wave 12).
Serial; C10 depends on C09's discovery semantics (warning strings, RED aggregation,
category law) because the shell guard's removal transfers that duty; C11 depends on both
for parity. Chain-wide first all-green at C11 review (reopen1/reopen2 pattern: the
re-pinned suites stay designed-red mid-flight, each red naming its unlanded artifact).

## Fan-out INPUT contract (pinned; C09 implements, C10 wires, C11 documents)

- CLI UNCHANGED: `python3 scripts/argocd-fanout.py [--config PATH] [--ref FULLREF]
  [--check] [--dry-run]`; config default `scripts/argocd-fanout.json`.
- Discovery: env keys matching broadly `^ARGOCD_SYNC_(.+)_(URL|TOKEN)$` — segment then
  STRICT-validates (`[A-Z0-9][A-Z0-9_]*[A-Z0-9]`, no leading/trailing/double `_`, no
  dots; derived category matches `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`); strict-fail with a
  non-empty value ⇒ violation naming the RAW KEY (a typo'd enumeration row must never
  silently vanish — that would re-open the silent-loss class), strict-fail empty ⇒
  ignored; segment → category by `lower()` + `_`→`-`. `ARGOCD_SYNC_TOKENS` (the dead
  blob) matches nothing and is ignored by construction.
- Configured predicate: any non-empty `*_TOKEN` value. Not configured ⇒ pinned
  column-0 warning line + exit 0 (no table, no sockets). Configured ⇒ every discovered
  category must have non-empty URL (scheme `https://`/`http://`, no `@`, no `?`, rstrip
  `/`) + non-empty JWT-shaped TOKEN (`JWT_RE` survives); every violation collected, one
  aggregated `argocd-fanout config:` stderr line listing categories sorted (each
  violation phrase pinned: `category "x" missing URL value` / `… missing TOKEN value` /
  `… token is not JWT-shaped` / `… URL must start with http(s)://`), exit 1.
- Roster globals (exactly five keys, extras red): `allowed_refs` `["refs/heads/main"]`
  (full-ref/`refs/tags` validation ported), `tracked_repo` byte-true,
  `settle_seconds` 10.0, `target_timeout_seconds` 60.0, `parallel_workers` 4
  (finiteness/whole-number guards ported). Missing/extra keys ⇒ ConfigError.
- Targets = discovered pairs; `root_app` = category; URL = the env value. `--check`
  prints: `argocd-fanout --check: OK`, allowed_refs, tunables, the table
  (`NAME`/`URL` from pairs), and `pairs: N targets discovered (values never printed)`.
- Behavior/audit/summary/exit codes/all-skipped/M2/M1-spirit(no echo): byte-unchanged
  from the shipped script; summary's `targets=%d` now carries the DISCOVERED count.
- Job wiring (C10): 22 enumerated `env:` entries (the pinned order: alphabetical by
  category, URL then TOKEN per pair, `EVT_REF`/`GH_REF` last); run block =
  `set -euo pipefail` + REF fallback chain + unguarded python call ONLY (no `-z` guard,
  no warning echo — the script owns both lanes); header + job comments: org-scope
  single-instance sentence now covers BOTH vars and secrets, static-enumeration cost
  sentence, decommission lockstep sentence, the unset-lane pointer moves to the script.

## Human-owned list (delta vs reopen2's — nothing else moves)

- **§2 creation legs rewrite:** 11 mints unchanged (same table, same hosts) → then 11
  org VARS `ARGOCD_SYNC_<CAT>_URL` (values = the §6 hosts) AND 11 org SECRETS
  `ARGOCD_SYNC_<CAT>_TOKEN` (value = that cluster's JWT) in prod-instance ORG Settings →
  Actions; no composition/paste step; single-instance discipline (repo twins WIN
  silently — never create repo-side); pre-verify `--check` via a locally-sourced pairs
  env file (NEVER `env KEY=value` — argv leak; the source-then-run recipe gets pinned in
  the runbook).
- **§2.4 delete-check grows to three:** `vars.ARGOCD_HOOK_URL`, `secrets.ARGOCD_HOOK_SECRET`,
  and `secrets.ARGOCD_SYNC_TOKENS` (the reopen2 blob — the waves-7–9 vault leg may or may
  not have run; absence-or-delete either way).
- **§5 smoke:** dispatch unchanged; expected rows now include the two RULED `failed`
  lines (proxy-local 307, proxy-backup) and the summary's discovered count; masking
  spot-check keeps as a native single-secret sanity grep, not a [26] verification.
- **§7 kill lever:** delete (or blank) the 11 org TOKEN secrets — token-side predicate
  ⇒ all-absent warn-green; URL vars may stay populated (the warning line is the
  proof-of-off). Full removal stays PR-revert.
- Rotation (§8): per-cluster — re-mint → `argocd account delete-token` old → overwrite
  that ONE org secret row. Decommission: org pair + 2 workflow rows in one release
  (lockstep, else config-red by design).
- Unchanged: org-scope hygiene ownership, proxy-backup vantage check, PR/merge, card.

## Risks / assumptions

- **Decommission/rotation transient reddens are BY DESIGN** (configured + residue ⇒ red):
  a delete-then-create rotation window that catches a push shows one red job, then
  self-clears; the alternative (silent drop) was the ruled-out class. Reversible via the
  aggregated message naming the category.
- **Enumeration drift:** workflow rows and org keys drift silently in the SAFE direction
  only (missing key ⇒ RED); EXTRA rows (fleet shrunk, file not updated) also RED —
  both directions are visible, none silent. The cost RESEARCH §2 named, accepted.
- **Category-law constraint is future-facing:** a future cluster category with
  underscore/dot literally cannot be onboarded without breaking discovery — the red
  names the raw key, and the runbook §8 sentence is the mitigation. No current category
  touches it.
- Kill-lever depends on the token-side configured predicate (pinned); if a URL-side
  keying had been chosen, blanking tokens would RED instead — recorded so a future
  reader sees why token-side.
- Shipped risks survive unchanged (gpu self-restart window, dind DNS acceptance leg,
  mirror lag, home Unknown, proxy-local 307 structural finding — owner leg).

## Open questions — R7 COMPLETE; NONE (no batched round this time)

The owner ruling answered the only design-space question (input mechanism); the four
pinned consequences came from coord with the ruling and the residual micro-calls are all
best-guesses recorded in DECISIONS 2026-11-25, each a reversible one-liner or a wording
row: token-side configured predicate (forced by the ruled kill lever), aggregated
multi-category config-red, alphabetical 22-row enumeration, category charset law + raw
key naming, the source-file `--check` recipe, `pairs: N targets discovered` check-line
wording, decomposition lockstep wording. If the owner disagrees with any, none cascades
beyond C09's parse matrix + one suite leg.

## Rejected alternatives

Prior-round rejections all stand. NEW this round: keeping the blob secret with a
newline grammar (OQ8's mechanics — ruled error-prone, superseded), 11 secrets WITHOUT
env discovery (the `${{ secrets[matrix] }}` wall [21][25] + expression-per-name — the
ruling resolves it by moving discovery into the script), keeping `targets[]` in the
roster as the category list (contradicts "no category list in code or JSON" — discovery
is the point), shell-side pair-completeness guards (22 emptiness tests in YAML — the
script's empty-detection is the guard, ruled), URL-side configured predicate (would turn
the ruled kill lever into a red-storm), warn-and-exclude for empty residue once
configured (the silent-partial-fleet class, ruled RED since reopen2), repo-scoped key
placement (reopen2's ruling stands: org-level, inherited, referenced identically).
