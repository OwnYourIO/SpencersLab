# PLAN: cf-139 — Pushes to main auto-sync every cluster (no manual `argocd sync`)
feature: 2026/2026-11-cf-139-feat-argocd-webhook-sync
card: AD-139 "Sync ArgoCD with Webhooks" (Y3vPeX4nhtDbsdwCg)
status: REOPENED⁴ 2026-11-26 (STATE `reopen4`, owner_decision + R8; card comment
rWTMRa4opbxwCP6jb). The owner ADOPTED the dynamic shape RESEARCH round 3 recommended —
and explicitly OVERRODE its probe gate: build without dispatch probes; the FIRST
dispatch smoke is the de-facto live validation (see Risks for the honest statement +
the one-commit fallback to `3f330df1a`'s static enumeration). Waves 10–12 (C09–C12,
closed at `3f330df1a`, 13/13 behavior + full-chain green) stand as DONE history: this
round deletes ONLY the 22-row enumeration — the fan-out core, both input lanes'
semantics, the warnings/RED strings, and the disposals are byte-untouched.
**plan_status: APPROVED 2026-11-26 — the one real call (OQ-A) answered PURE DISCOVERY
(option b, against the coordinator's oracle recommendation; DECISIONS 2026-11-26);
no open questions remain.** History: reopen1 2026-11-21 (R1–R4), reopen2 2026-11-23
(R5/R6 + OQ8–OQ10 batch), reopen3 2026-11-25 (R7 env-pair input, waves 10–12).

## Goal

A push to `main` lands on every cluster automatically, driven by the Forgejo
`main-sync` job after `push-gh` (R1 option (c) untouched). The job becomes
FLEET-BLIND: it carries no category rows at all. Instead two blob contexts —
`SECRETS_JSON: ${{ toJSON(secrets) }}` + `VARS_JSON: ${{ toJSON(vars) }}` (supported:
`toJSON` ungated in the act-lineage evaluator [40][41][49][50], and the server ships
EVERY job the complete merged org+repo maps with no reference scan [43][44][46]) — feed
ONE inline filter step that selects the `ARGOCD_SYNC_*_URL`/`_TOKEN` pair names and
serializes them to `$RUNNER_TEMP/pairs.json`; the fan-out step hands that file to
`scripts/argocd-fanout.py`, which applies its existing validation to the file map
instead of the environment. Per-cluster org keys stay exactly as the owner runs them
today (§2 of the runbook does not change).

## Scope decisions — R8 + pinned design

- **R8 (2026-11-26, STATE `reopen4.R8`):** dynamic adoption — 22 rows → two `toJSON`
  blobs + inline filter → `pairs.json`; script gains the `ARGOCD_PAIRS_FILE` channel,
  env scan stays the default; the ≈0-widening claim is documented and its real lever
  (`.forgejo/workflows/**` branch protection) is the follow-up card already created
  (`abkP2XsbuuPuuvri6`, Inbox). Supersedes: micro-call (2) consequence ("static
  enumeration rows"), micro-call (d) decommission lockstep (no rows exist to
  leave-behind), micro-call (g) alphabetical-row pins, and the (i-adj-1) envelope's
  "rows" vocabulary (re-reads as "discovered keys"). The premise it replaces — "Forgejo
  cannot index secrets dynamically [21][25]" — is SOURCE-REFUTED [43][44][46][49];
  DECISIONS 2026-11-26 records the refutation and the override.
- **Division of duty (pinned): the filter is a DUMB SERIALIZER; the script owns ALL
  integrity/kill/membership semantics.** The filter: regex-select pair-shape names from
  BOTH blobs (union; secrets-side wins a same-name collision), write flat
  `{NAME: value}` JSON (the SAME namespace as env — deviation from RESEARCH's
  `{cat:{url,token}}` phrasing, deliberate: one validator body serves both channels),
  `chmod 600`, print ONLY `filter: <N> keys selected` (count; never names-with-values,
  never the blob), treat missing/empty/unparseable-side blobs per the designed states
  below. It never validates a pair, never decides configured/kill lanes — those are
  the script's, identical across channels, which is what keeps C09's contract
  offline-testable and the strings byte-stable.
- **Channel (pinned):** env var `ARGOCD_PAIRS_FILE` (NOT a CLI flag — argparse surface
  frozen; a file path is not a secret so argv would be legal too [t12 context], but the
  env channel matches the tokens-arrive-by-env doctrine and the runbook recipe style).
  Set-and-non-empty ⇒ pairs load from the file and the env scan is SKIPPED ENTIRELY
  (precedence pinned: file wins when both exist; the file is the deliberate CI
  posture). Unset or empty ⇒ env scan byte-unchanged (local/manual posture, behavior
  t-arms preserved). File errors are config RED naming the PATH (missing/unreadable/
  non-JSON/non-dict/non-string-values); an empty JSON object `{}` is NOT an error — it
  is the all-absent discovery result ⇒ the normal warn-green lane.
- **The reachability envelope changes honestly (rule the new one):** the
  "enumerated-but-empty" (j)-class was CREATED by the static map — a deleted org key
  arrived as an empty string in env. With blob discovery a DELETED key is simply
  ABSENT from the map; a BLANKED key still arrives as `""`. So: blanked-both pair ⇒
  same (j) RED (names present, values empty — unchanged semantics, "present" now means
  "in the map"); deleted-TOKEN beside surviving tokens ⇒ half-pair RED (URL present,
  TOKEN absent) as before; **deleted-COMPLETE-pair ⇒ the category vanishes from
  discovery entirely** — RULED (OQ-A answered b, 2026-11-26): that is CLEAN INTENTIONAL
  DECOMMISSION — the category drops, the fleet count is the only signal, by design;
  making it loud would demand a repo edit per decommission and the owner declined the
  friction; the real lever shifts to org name-discipline + the branch-protection card.
  Malformed-name-with-value stays a
  pre-predicate RED short-circuit regardless of channel ((i-adj-2) order preserved).
  The kill lever (delete-or-blank ALL 11 TOKEN secrets ⇒ zero non-empty tokens ⇒
  NOT_CONFIGURED ⇒ the EXACT same §4 warning string — verified still-true phrasing,
  no text change anywhere) survives identically.
- **Security honesty (RESEARCH Agenda 4):** today every job of every workflow in the
  repo ALREADY receives all org+repo secrets (no reference filtering, `permissions:`
  ignored, no environments [42][43][44][46][57]) — the blob's widening delta is ≈0;
  the inline filter preserves the narrower invariant that the CHECKOUT-RUNNING
  process's env stays at the 22-value floor (step-2 sees only `ARGOCD_PAIRS_FILE` +
  refs; the blob lives only in step-1's process) — unlike the naive shape (blob
  straight into the script's env, which would hand a scripts-only attacker
  PUSH_TOKEN_* + the token aliases). `pairs.json` rests plaintext in the job container
  until cleanup — same trust zone as today's step env; chmod 600 belt; RUNNER_TEMP is
  per-job ephemeral (`runner.temp` ↔ `RUNNER_TEMP`, steps share one container
  [40][51] — this is a probe-conclusion the owner's override folds into the first
  dispatch). Masking: each delivered VALUE is registered independently and masks
  inside the serialized blob ([40]'s own `"token": "***"` example; edge: JSON-escaped
  values would not match — current JWT/URL charsets are escape-free [30][31], the
  §5 spot-check asserts it live).
- **Header wording fix (queued from round 3, rides C13):** the vars-precedence half is
  wrong per `GetVariablesOfRun` (Repo > Org/User > Global [45], docs sentence stale
  [41]; secrets repo-over-owner [44]) — reword to the source truth, moot either way
  under the no-repo-twin rule; the "static enumeration IS the discovery surface /
  cannot index dynamically" sentences RETIRE with the rows.
- **Unchanged, explicitly (byte-locked):** fan-out core + `t13`-style function locks
  from C09/C12; `needs: [push-gh, build-containers, build-charts]` (grown by the D59
  owner ruling on the rebased line — main's builder fan kept, the cf-139 job shape
  replayed onto it; R1(c) ordering survives), exact ROLE guard, diag step, bare
  `actions/checkout@v7`, REF fallback chain, the invocation line
  `python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF"`;
  all script strings (`WARN_NOT_CONFIGURED`, `pair integrity:` aggregation, malformed
  preemption, `pairs: N targets discovered (values never printed)`), exit doctrine
  (0/1/2), `--check`/`--dry-run` modes, JWT/URL/segment/category regex laws,
  `tracked_repo` + `allowed_refs` globals, disposals, runbook path.

## Context — verified facts

- [R3] Landed at `b828bd725` (tip; reopen3 closed `3f330df1a`): `discover_targets(env)`
  is dict-shaped (a file map drops in with ZERO validation divergence — the one
  structural change is `load_pairs_file()` + channel branch in `main`/cmd flows);
  `ROSTER_KEYS` = the five globals; roster JSON = five keys; workflow = 22 enumerated
  rows with placement bans; suites green (behavior 13/13, main-sync t1–t13, runbook
  parity legs; C12 = the ruling-(j) both-empty RED + kill-lane boundaries, t13
  core byte-locked).
- [43][44][45][46] delivery/merge source-reads; [49][50] evaluator (toJSON ungated,
  secrets first-class, index op works); [52] GitHub divergence (there unseal-on-
  reference; here always delivered); [54][55] production precedent incl. the
  branch-protection lesson (mitosis #16) → follow-up card; [40][41][51][53] docs +
  runner-v13 breaking-change context (expression failures RED the job — the fallback
  trip-wire is loud, not silent); probe legs A–E defined in RESEARCH Agenda 6 are NOT
  run first (owner override) — their assertions become the first dispatch's
  expectations.
- Org inventory claim under test by the smoke: `CuratedForest` org holds the 22
  ARGOCD_SYNC_* keys (and `ROLE`/`PUSH_URL_*` vars); PUSH_TOKEN_* repo-side [R3] —
  Agenda-4's owner-API inventory shells stay an optional owner leg (doc honesty only).
- FRICTION/precedents: helm PATH export; offline static suites (no actionlint);
  column-0 `::warning::` annotation grammar; argv secret-ban law; aislop gate.

## Out of scope

- Everything reopen2/reopen3 ruled out that is still ruled out (relay/door/flip/
  Bitwarden/webhooks/notifications/per-cluster exposure).
- Branch protection on `.forgejo/workflows/**` — follow-up card `abkP2XsbuuPuuvri6`
  (org-settings leg, owner-executed; NOT a chunk here).
- Probing first: ruled out by the owner (the override IS the accepted risk — Risks
  row 1). Mechanism 2 (matrix-from-outputs chain) and 3 (REST-API discovery) per
  RESEARCH Agenda 5 scoring. Retro-fitting the env channel: it stays exactly as
  landed (local/manual default; under pure discovery NO channel has a membership
  concept — there is nothing to diff).

## Commands (validation-first)

- C13: `bash tests/services/forgejo-main-sync.sh` (re-pinned: blob-expression legs,
  fleet-blind ban — zero `ARGOCD_SYNC_<SEG>_(URL|TOKEN)` name strings in the file,
  filter-contract legs incl. no-print grep + `bash -n` of the
  filter run block, pairs-path wiring; t13 roster leg parse-only PERMANENTLY — the
  five-globals schema pin lives in behavior t2 and changes NOT at all this round) + `git diff --name-only` keep-outs
  (`needs: [push-gh, build-containers, build-charts]` per D59 on the rebased line, ROLE guard, push jobs byte-zero).
- C14: `python3 -m py_compile scripts/argocd-fanout.py`; `bash tests/argocd-fanout/behavior.sh`
  (file-channel arms + precedence + env-unchanged legs; roster schema legs UNCHANGED —
  the five globals as landed, zero schema churn under pure discovery).
- C15: `bash tests/notes/argocd-fanout-runbook.sh` (re-pinned for rewrite #5: §4
  filter anatomy, §5 first-dispatch-as-validation leg list + fallback sentence greps,
  §7 lever strings byte-true (`WARN_NOT_CONFIGURED` parity), §8 envelope reword,
  stale-vocabulary ban: no "enumeration row(s)" claims outside history lines).
- Chain: `bash tests/argocd-fanout/disposal.sh` untouched; `npx aislop ci --changes`
  clean per touched file; no helm/docker legs (no chart/container surface this round).

## Chunks (reopen4 table)

| id | title | size | wave | status | depends_on | why the dependency |
|----|-------|------|------|--------|------------|--------------------|
| C01…C12 | relay → vault-direct → env-pairs waves 1–12 | — | 1–12 | **done-at-review history** (C09/C10/C12 input-mechanics legs superseded at reopen4; fan-out core + lanes + strings live on unchanged) | — | untouched |
| C13 | main-sync.yaml fleet-blind rework: 22 rows → `toJSON` blobs + inline filter step → `$RUNNER_TEMP/pairs.json`; fan-out step gains `ARGOCD_PAIRS_FILE`; header comment fix (precedence halves, enumeration retirement) + main-sync suite re-pin | M | 13 | pending | [] | the workflow is the new channel's PRODUCER; its filter contract is pinned by this plan so C14's reader matches |
| C14 | script `ARGOCD_PAIRS_FILE` channel (load → same `discover_targets` body, UNCHANGED — no oracle, no schema churn: pure discovery is ruled; precedence; path-error REDs; `{}` ⇒ warn-green) + behavior.sh re-pin | M | 14 | pending | [C13] | implements the reader for the producer's exact file shape + env name; landing together-in-branch keeps CI coherent (mid-branch the script warn-greens — inert, never wrong) |
| C15 | runbook rewrite #5 (§2 vault work UNCHANGED + fleet-blind sentence; §4 filter anatomy; §5 first dispatch = the live engine-claims validation, legs enumerated, fallback sentence, fleet-drift honesty line; §7 decommission = delete BOTH org keys — no repo edit; §8 pure-discovery envelope/escape/masking honesty) + second test launch (runbook suite re-pin) | S | 15 | pending | [C13, C14] | parity greps read both landed files, as every prior docs chunk has |

Test sessions (law: tests precede dev): **pre-wave-13 ONE session** re-pins
`tests/services/forgejo-main-sync.sh` (blob/filter/fleet-blind legs; t13 roster leg
relaxed to parse-only) and `tests/argocd-fanout/behavior.sh` (file-channel arms
designed-red until C14; env-scan legs byte-kept). **At wave-15 start** the short second
launch re-pins `tests/notes/argocd-fanout-runbook.sh` (reads C13/C14 landed bytes).

## Wave order

13. C13 → 14. C14 → 15. C15 (runbook-test launch first inside wave 15). Serial per the
brief's sequencing; C14 could parallel-run C13 on disjoint files but the shape pins
(file format, env name) are C13-published, and reopen4 keeps the strict test-first-
then-consumer order for a clean designed-red story. The batched round ANSWERED OQ-A
(2026-11-26, option b — pure discovery, the oracle recommendation declined); the plan
is APPROVED and every micro-call below stands as pinned.

## Fan-out INPUT contract v3 (pinned; C13 produces, C14 consumes, C15 documents)

- Filter step (C13): `name: resolve fan-out pairs`; `env: VARS_JSON: ${{ toJSON(vars)
  }}` + `SECRETS_JSON: ${{ toJSON(secrets) }}` [40][41][49]; run block (one
  `python3 -c`, stdlib json/re/os): each blob env value → `json.loads(... or "{}")`
  (missing/empty side ⇒ `{}`; non-JSON ⇒ RED-style exception exits nonzero — engine
  surprise must be loud, message names the blob NAME only); select keys matching the
  SAME broad pair regex `^ARGOCD_SYNC_(.+)_(URL|TOKEN)$` from both maps (union,
  secrets-wins on collision); `mkdir -p "$RUNNER_TEMP"`; write
  `$RUNNER_TEMP/pairs.json` (flat `{NAME: value}` map, `sort_keys=True`), `chmod 0600`;
  print exactly `filter: <N> keys selected`; NEVER print values, names-with-values,
  counts-of-others, or the blobs. Zero pair keys ⇒ empty `{}` file, green (the script's
  lanes decide everything downstream).
- Fan-out step (C13): `env: ARGOCD_PAIRS_FILE: ${{ runner.temp }}/pairs.json` +
  `EVT_REF`/`GH_REF`; run block = `set -euo pipefail`, REF chain bytes, invocation
  bytes, unguarded.
- Script (C14): `main` branch: `pairs_file = os.environ.get("ARGOCD_PAIRS_FILE")`;
  truthy ⇒ `load_pairs_file(pairs_file)` (existence/read/JSON/dict/value-str checks →
  ConfigError naming the path only) and `discover_targets(that_map)`; else
  `discover_targets(os.environ)` unchanged. `discover_targets` body: ZERO changes —
  no params, no oracle, no membership concept (RULED, OQ-A answered b: the delivered
  map IS the fleet); malformed-preemption and TOKEN-side predicate order are already
  channel-agnostic by construction. Roster: the FIVE globals exactly as landed — zero
  schema churn. `--check` derives from whichever channel; output lines unchanged.
- Strings pinned UNCHANGED: `WARN_NOT_CONFIGURED`, `pair integrity: …` aggregation,
  `malformed ARGOCD_SYNC_* … keys with values: …` (the phrase "enumeration keys" stays
  byte-true — the script re-types nothing; runbook §8 notes it now reads "delivered
  vault keys"), `pairs: N targets
  discovered (values never printed)`, fan-out core entirely (C09/C12 t13 byte-lock
  doctrine extended: C14's AC includes a zero-hunk proof for
  `ref_tail…fan_out`/`_NoRedirect`/`drive_target`).

## Human-owned list (delta only — everything else in runbook #4 stands)

- Vault work **unchanged**: 11 mints, 11 org vars, 11 org secrets, trio delete-check —
  literally the same legs; the only difference is the owner NEVER touches the workflow
  again for fleet membership.
- **Fleet ops are vault-only now (OQ-A ruled, pure discovery):** cluster ADD = create
  the org pair — zero PRs, joins at the next run; decommission = DELETE BOTH org keys —
  zero PRs, vanishes at the next run, the `fan-out summary: targets=N` count is the
  roster audit (fleet-drift honesty line, runbook §5/§8); a half-delete (one key gone)
  surfaces config-RED naming the category until the twin follows — by design. The
  owner declined the repo-edit-per-decommission friction; the branch-protection card
  is the accepted weight for org-write-equals-fleet-config.
- **The first dispatch smoke gains its true role (override consequence):** it is the
  live validation of the engine claims RESEARCH could not close without probes — legs
  enumerated in runbook §5 (expression green ⇒ toJSON+delivery; `filter: 22 keys` ⇒
  merge-complete; step-2 reads the file ⇒ RUNNER_TEMP persistence; log search finds no
  raw values ⇒ blob-internal masking [40]; the two RULED failed rows unchanged:
  proxy-local 307, proxy-backup). A red smoke on any CLAIM ⇒ the probes' conclusions
  were wrong ⇒ documented fallback: revert the branch to `3f330df1a`'s static
  enumeration (one commit, zero cluster impact — the standing rule, not agent-owned).

## Risks / assumptions

- **NO PROBE GATE (owner-ruled, stated plainly):** the design's engine claims rest on
  source-reads + production precedent [43–46][49][54][55] but NOT on a run against
  prod's exact fork build (the method note's admitted gap). Mitigations: v13 doctrine
  makes unsupported expressions fail LOUD at job start [53] (mirror pushes are
  unaffected — push jobs complete independently); the first dispatch is scheduled as
  the acceptance leg with the one-commit revert prepared. This risk is the direct,
  accepted cost of the override.
- **Blob exposure surface:** every value in the org+repo merged maps serializes into
  step-1's env; the filter's never-print law + step-2's file-only env keep the
  checkout-running process at today's floor; the real boundary is PR review, and the
  branch-protection lever is carded (`abkP2XsbuuPuuvri6`). Honest delta: ≈0 vs today
  [43][46] — but "≈0" assumes the org inventory (Agenda-4 note) — the optional owner
  API shells complete that claim.
- Masking edge: JSON-escaped values wouldn't match the masker — current fleet
  escape-free [30][31]; §8 states the charset rule for future keys.
- Empty-string-vs-absent semantics hinge on `toJSON` including created-but-blank keys
  (source says the map carries what exists — blanks included [44]); the smoke's
  filter-count line discriminates.
- **org-write = fleet-config (RULED consequence of pure discovery):** a stray COMPLETE
  valid pair silently JOINS the fleet and a fully-deleted pair silently DROPS it — the
  only signals are the summary count and the log. Half-states were and stay RED-loud;
  malformed names with values stay RED-loud ((i-adj-1) re-read for vault-delivered
  keys). Mitigations accepted on the owner's word: name discipline (§8), and the
  branch-protection lever carded at `abkP2XsbuuPuuvri6` — that card now carries the
  drift story the oracle would have closed in-code.
- Carried: gpu self-restart window, dind DNS (dispatch is its leg too), mirror lag,
  home Unknown, proxy-local 307 owner decision.

## Open questions — RESOLVED BY RULING 2026-11-26 (OQ-A answered: plan APPROVED)

1. **OQ-A — categories oracle: ANSWERED (b) PURE DISCOVERY — against the coordinator's
   recommendation.** The org vault map alone IS fleet membership: no `categories` list
   anywhere, no membership diffing in any channel, the roster stays the five globals
   byte-unchanged. Consequences stated precisely: one-sided delete ⇒ half-pair ⇒ config
   RED (existing class, untouched); BOTH keys deleted ⇒ clean intentional decommission
   ⇒ the category vanishes, fleet−1, the summary count is the only signal — by design,
   because making it loud would demand a repo edit per decommission and the owner
   declined the friction; blanked-token (present-but-`""` in the blob) ⇒ still (j)-RED.
   Weight shifts to the branch-protection card (`abkP2XsbuuPuuvri6`) + org name
   discipline (§8). The main-sync t13 parse-only relaxation becomes PERMANENT (reworded
   in C13), not OQ-conditional.
2. Pinned micro-calls (NOT questions — best guesses, reversible one-liners): filter
   prints `filter: N keys selected` only; secrets-wins collision order; `PAIRS_FILE`
   set-and-non-empty ⇒ env scan skipped entirely (strict precedence); `{}` file is the
   all-absent lane, a missing/invalid file is RED naming the path; chmod 600 is the
   filter's duty, the script does not stat modes; `ARGOCD_PAIRS_FILE=""` ⇒ unset;
   malformed-lane message keeps its landed "enumeration keys" wording byte-true
   (documents re-read it as "delivered vault keys"; the script retypes nothing); the
   header precedence fix ships with C13 as queued.

## Rejected alternatives

All prior rejections stand (blob secret #4-style [ruled dead twice], 11-row static
enumeration (the owner's reopen4 ask — and its premise refuted [43][44][46]), relay,
door, flips, notifs, public exposure). NEW: **probe-gated adoption** — RESEARCH's
recommendation, explicitly OVERRIDDEN by the owner 2026-11-26 (the probe legs'
assertions become the first dispatch's expectations instead); mechanism 2
(matrix-from-outputs chain — engine-feasible, re-pays the fan-out topology,
outputs-carrying-secrets hazard [56]); mechanism 3 (REST API discovery — secrets are
names-only via API [47][48], tokens would need an org PAT crown jewel); naive shape
(blob into the script's env — scripts-only attacker gains PUSH_TOKEN_* + token aliases,
RESEARCH Agenda-4(b)); nested `{cat:{url,token}}` pairs file (second grammar — the
flat env-namespace map keeps ONE validator body for both channels); a CLI `--pairs-file`
flag (argparse surface churn for zero gain over the env channel); **the membership
`categories` oracle — coordinator-RECOMMENDED, owner-DECLINED 2026-11-26 (OQ-A answered
b)**: the loudness it bought (clean-delete RED, stray-pair RED) was priced at a repo
edit per decommission, and the owner chose zero-file fleet ops + the protection card
instead; deleting the runbook's §2
legs (the owner's vault work literally did not change).
