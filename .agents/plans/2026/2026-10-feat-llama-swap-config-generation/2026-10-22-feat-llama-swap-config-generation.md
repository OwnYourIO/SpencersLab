# PLAN: llama-swap config autogen adoption + desired-state roster (Path A)
feature: 2026/2026-10-feat-llama-swap-config-generation

## Goal
Stop hand-editing the llama-swap `config.yaml`: render the whole declared `-hf`
roster from compact per-model entries in Helm values (the desired-state half),
wire `shirayu/llama_swap_config_autogen` (pinned SHA, stock, no fork) as an
initContainer generating the disk-scanned half into an emptyDir, and merge both
via llama-swap v262 `-config` + `-config-dir`. Convert all existing models and
snippet-macros with zero model-ID changes, and add the flash-next / Ornith
1.5 122B / Ornith 1.5 35B / orcarouter-uncensored roster.

## Out of scope
- Path B (fork with `hf_models:`) — user chose stock tool (DECISIONS 2026-10-22).
- Renaming any existing model ID/alias (consumers: OpenWebUI, Pictaria, Immich, HA, agent routing).
- Serve-testing on gpu-ai (busy; config-level validation only there).
- Changing the llama-swap image (`unified-vulkan-262`) or chart version bumps (release.yaml owns).
- profiles/peers/apiKeys changes; tools sidecar; proxy wiring (already exists, unchanged).

## Architecture (locked, from DECISIONS.md + verified against v262 source)
Two config sources merged natively:
1. **Declared half** — ConfigMap `llama-swap-config`, key `config.yaml`, directory-
   mounted at `/app/config` (unchanged paths). Helm renders it from a compact
   roster schema in values (`config.models.<id>: {hf, draft, use[], flags, cmd,
   disabled, name, description, ttl, aliases, capabilities, filters,
   checkEndpoint, ...}`). Precedence `disabled > cmd > hf-composition`. All
   macros, matrix, hooks, filterPresets live ONLY here.
2. **Scanned half** — initContainer runs `llama-swap-config-autogen generate`
   from a rendered `base.yaml` ConfigMap into emptyDir `/app/gen/10-scanned.yaml`;
   `LLAMA_SWAP_CONFIG_DIR=/app/gen`. Empty scan dir (today's steady state) →
   degrade to a comment-only file (skipped by the loader — verified in v262
   `merge.go` `parseSource`/`listYAMLFiles`).
Merge facts verified at `v262` (`internal/config/merge.go`, `matrix.go`, `docker/unified/run.sh`):
identical scalars across sources OK, differing scalars hard-error; `models`/
`groups`/`matrix` are identity maps — duplicate children hard-error, so
generated IDs (`<dir>:<QUANT>` namespace) never collide with declared dash-IDs;
`matrix` in two files = hard error (its children `vars`/`sets` are identity keys)
→ matrix in declared half only; `matrix.vars` referencing a missing model is a
load error (matrix.go:71); empty config-dir is valid when `-config` is set.
Refinement of RESEARCH §5: it proposed passing matrix/hooks through base.yaml —
invalid in the two-file world (see DECISIONS append).

## Commands
- `helm dependency update charts/llama-swap`
- `helm lint charts/llama-swap`
- `helm template llama-swap charts/llama-swap --set domain=spencerslab.com --set clusterName=gpu`
- per-cluster render (extract `llama-swap:` subtree from service values, render with `-f`,
  pattern in skills/helm-chart-creation/references/mcp-servers.md):
  `python3 -c "import yaml; d=yaml.safe_load(open('services/gpu/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpu-vals.yaml','w'))"`
  → `helm template llama-swap charts/llama-swap -f /tmp/gpu-vals.yaml --set domain=spencerslab.com --set clusterName=gpu`
  (same for `services/gpu-ai/prod/values.yaml` + `--set clusterName=gpu-ai`)
- golden capture (pre-conversion, for C02 parity):
  `mkdir -p charts/llama-swap/tests/golden && helm template llama-swap charts/llama-swap -f <extracted-gpu> --show-only templates/configmap-llama-swap.yaml > charts/llama-swap/tests/golden/gpu.config.yaml` (same gpu-ai)
- `pytest charts/llama-swap/tests -v` (existing CI harness, workflow llama-swap-tools-tests.yaml already triggers on all touched paths)
- autogen pinned install + runs (evidence for the "No models found" failure and for generate/validate against the rendered base.yaml, empty + synthetic GGUF fixture scan sets built with the chart's vendored `scripts/gguf-py`):
  `python3.12 -m venv /tmp/ag && /tmp/ag/bin/pip install "llama-swap-config-autogen @ https://github.com/shirayu/llama_swap_config_autogen/archive/c7357e68c755b54557f5b0f88b0507bf1c981500.tar.gz"`
  → `/tmp/ag/bin/llama-swap-config-autogen validate <rendered base.yaml>`; `generate --config base.yaml -o out.yaml`
- merged-config validation with the fleet image (run.sh execs args; `-validate` exists — llama-swap.go:126):
  `docker run --rm -v $PWD/rendered:/c ghcr.io/mostlygeek/llama-swap:unified-vulkan-262 -config /c/config.yaml -config-dir /c/gen -validate`
- `docker build containers/llama-swap-autogen` (PR CI also builds via docker-build.yaml)
- trio/sentinel greps: `grep -rn "OVERRIDE_VIA" charts/llama-swap/templates services/gpu*/prod/values.yaml | grep -v custom-values` renders empty for these keys via custom-values; `grep -n "llama-swap" services/gpu/prod/values.yaml services/gpu-ai/prod/values.yaml` chart entries intact; `grep -n "llama" services/gpu/prod/values.yaml services/gpu-ai/prod/values.yaml` proxy entries intact.
- cluster checks (post-merge, gpu box only): readonly-gpu-kubernetes — Application Synced/Healthy, initContainer Ready, pod logs show merged config load + model count; `GET /v1/models` completeness. NEVER kubectl apply; no gpu-ai disturbance; admin-* MCP only with explicit user approval.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | containers/llama-swap-autogen image (pinned SHA) | S | 1 | [] | — |
| C02 | declared-half render: roster schema + Helm templates + convert chart & gpu & gpu-ai values (golden parity) | L | 1 | [] | — |
| C03 | autogen wiring: base.yaml ConfigMap, initContainer, /app/gen emptyDir, degrade path, reload semantics | M | 2 | [C01, C02] | C01 supplies the image reference; C02 defines the values layout base.yaml renders from + the merged-config surface `-validate` checks |
| C04 | new model roster: flash-next q3–q6 + orca, Ornith-122B q3–q6 (gpu-ai), Ornith-35B ladder (chart, gpu-tuned), matrix/preload additions | M | 2 | [C02] | entries are data in the C02 schema; independent of C01/C03 machinery (new models all ride the declared half) |
| C05 | post-merge gpu-box verification + reload/rollback runbook (user-gated) | S | 3 | [C01–C04] | needs everything synced via ArgoCD (main); verification per AGENTS.md is GitOps-only |

## Wave order
1. C01, C02 (independent; C01 image, C02 config layer)
2. C03, C04 (C03 ⟂ C04; both need C02; C03 also needs C01)
3. C05 (after user lands the PR)

## Delivery decisions (summary; full log in DECISIONS.md)
- Autogen delivery = self-built `containers/llama-swap-autogen` (python:3.12.15-slim-bookworm,
  pip-install from the pinned tarball URL at build, renovate `git-refs` ARG pin, uid 65532).
  Rejected: runtime pip from tarball (boot egress/latency, non-immutable), vendored source
  ConfigMap (still needs pydantic/gguf/jsonschema from PyPI at boot). First chart reference:
  `:main` + `pullPolicy: Always` (no `:v<run>` exists pre-merge), pin to first immutable tag
  after landing — documented new-container exception.
- Degrade path: empty scan set OR generate failure → comment-only `10-scanned.yaml`, exit 0
  (fail-open, logged): the scanned half only ever adds models; crashing the pod costs the lab's
  live consumers (Immich/HA/OpenWebUI) against no upside.
- New IDs (gpu-ai-only): `qwen3.8-flash-next-q3/-q4/-q5/-q6`, `qwen3.8-flash-next-orca-q6`
  (gated, HF_TOKEN), `ornith-1.5-122b-q3/-q4/-q5/-q6`. Chart-wide: `ornith-1.5-35b-a3b-`
  `iq2xxs/q3/q4/q5/q6/q8/bf16`. flash-next q5/q6: declared ENABLED, no matrix membership
  (runs-alone semantics), never preloaded (user-accepted risk).
- 35B ladder proposed for approval: official 5 (Q4_K_M/Q5_K_M/Q6_K/Q8_0/BF16)
  + bartowski Q3_K_XL + bartowski IQ2_XXS; rejected Q*_K_L/IQ3/IQ4 tiers as redundant IDs.

## Risks / assumptions
- `${moe}`'s `-ot "\.ffn_.*_exps\.=CPU"` regex may not match the Qwen4Exp (flash-next)
  tensor naming → C04 must verify against real GGUF headers via HF range-fetch before wiring
  the macro (mismatch → new `fn-moe` macro with corrected regex).
- 122B/flash-next repos churn (122B GGUF updated 2026-10-21) → re-verify exact `repo:TAG`
  refs at implementation (C04 has an API-check step).
- gpu-ai RAM fit for q3/q4-class residents is measure-on-cluster territory (RESEARCH 7/10):
  mitigated by no preload + solo/absent-from-matrix for everything above the 35B tier.
- stakater reloader must pick up the new base.yaml ConfigMap (mounted volume → auto mode);
  if not, add `reloader.stakater.com/match`. C03 acceptance covers it.
- `hooks`/`filters`/`env` key shapes preserved verbatim through rendering — parity test is
  normalized-token equality (cmd flag sets), not byte equality (comments/anchors expand).

---

# REPLAN 2026-10-24 (agent-plan; user review of landed C01–C04, pre-C05)

C01–C04 are done/APPROVED and remain untouched below; this section extends the plan with the
five user change-requests (DECISIONS 2026-10-24). The goldens stay byte-untouched; the contract
changes enter through the test session (ses_e9bdebccbffe7bYG46Fm9LO8FG) as wave-0 (CA1).

## Replan goal (two sentences)
Convert the roster authoring to family-keyed model definitions with a built-in quant ladder
(rendered IDs `<family>-<quant>`), restructure chart values into a full catalog in which every
rung is default-DISABLED and each cluster enables its subset, remove the coder/qwen3.6(§Q)
families with matrix closure and a consumer-reference sweep, and relocate the initContainer's
inline degrade script into `containers/llama-swap-autogen` as the image entrypoint. C05 stays
user-gated; its checklist rebases onto the new expected per-cluster enabled sets + runbook
addenda (rebased in-place in chunks/C05.md as part of this replan — no separate CA5 chunk).

## CR1 — Family schema + expansion (CA2)
Schema (chart values, under `config:`):

```yaml
config:
  families:
    qwen3.8-27b:
      enabled: false              # catalog default: every rung renders the fail-fast echo
      ttl: 0                      # family fields merge down into each rung
      use: [threads, ctx-256k, flash-and-q8]
      quants:
        q4:   { hf: unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL, name: "Qwen 3.8 27B (UD-Q4_K_XL)", description: ... }
        q6:   { hf: unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_XL, ... }
        q8:   { hf: unsloth/Qwen3.8-27B-GGUF:Q8_0, ... }
        bf16: { hf: ggml-org/Qwen3.8-27B-GGUF:BF16, ... }
        # gpu-ai-only variant rungs live in the catalog too, default-disabled:
        q8-visual: { hf: ..., use: [q38-common], flags: "-c 262144", ... }
        q8-1m:     { hf: ..., use: [ctx-1m], flags: ..., ... }
```

Expansion rules (new `llama-swap.expandFamilies` step feeding the existing
`llama-swap.declaredConfig` loop — composition precedence `disabled > cmd > hf-composition`
UNCHANGED, deviation-1 wording UNCHANGED):

1. Rendered ID = `rung.id | <family-key> + "-" + <quant-key>`. `id:` overrides exist for the
   two continuity cases that don't derive cleanly (`home-3b-v3` base rung; everything else —
   `qwen38-orca`, `qwen3-embedding-0.6b`, `whisper-large-v3` (family `whisper` + rung
   `large-v3`), `home-3b-v3-gpu`, `qwen3.8-flash-next-orca-q6` (family
   `qwen3.8-flash-next-orca` + rung `q6`), `qwen3.6-35b-a3b-q8-visual`, `q36` rungs — derives).
   A duplicate rendered ID across families/rungs fails the render.
2. Per-rung entry deep-merges OVER family-shared fields (family < rung). Quant keys are ladder
   keys, not strictly quantizations (`orca`, `q8-1m`, `large-v3` are valid keys).
3. Enablement: effective-enabled = `rung.enabled OR family.enabled` (cluster values flip either
   via Helm deep-merge; gpu flips mixed families per-rung, whole families with one
   `enabled: true`; a rung's `disabled:` beats enablement — precedence is
   `disabled > enabled`, so gpu's legacy byte-pinned echoes keep working as
   `models.<id>.disabled:` overrides).
4. Not-enabled → echo `/bin/sh -c "echo '<id> <message>' >&2; exit 1"` with the chart-default
   message ("is not enabled on this cluster …") unless a `disabled:` message is supplied —
   the golden-pinned legacy echo messages stay byte-exact (they come from the cluster's
   `models.<id>.disabled:` blocks, which remain in place).
5. Raw `config.models.<id>` stays as the per-ID override/escape-hatch layer, deep-merged OVER
   the expansion (this is how per-quant overrides survive: gpu's tuned 35B-q8/q6 regimes, the
   vl30b-bf16 + bf16 echo messages, gpu-ai's tuned variants — same mechanism as today, only
   the base data moved into `families:`).
6. What stays per-cluster: enablement flips, tuned `use`/`flags`/`cmd`/`disabled`/
   `capabilities` overrides, `matrix` (vars still reference RENDERED IDs — closure rule
   unchanged), `hooks.preload`, cluster macros. What moves chart-side: every family's ladder
   data (hf refs, names, descriptions, ttl, vision caps), i.e. gpu-ai-local IDs become
   catalog rungs gpu-ai enables.

## CR2 — Catalog pattern + contract rebase (CA1 gates, CA2 implements)
Chart `values.yaml` defines ALL families (flash-next/orca/122B/35B-ladder/qwen38-derivatives/
visual+1m rungs + all existing kept families), every rung default-disabled; `services/gpu` and
`services/gpu-ai` enable their subset. Consequence: gpu renders contain ALL catalog IDs, most
as echoes; gpu-ai enables its full set (echoes only where today's `disabled:` overrides bite).
Accepted consequence to record in the C05 runbook: `/v1/models` grows to the full catalog on
both clusters (echoes are routable, they fail fast when requested) — consumers see more IDs.

Parity bars after CA1's rebase (goldens byte-untouched; the cmd-parity bar for LIVE models is
NOT bent):
- P1 (new, frozen in testlib): `renderedIDs(cluster) == CATALOG_IDS` exactly (superset
  semantics pinned mechanically; `CATALOG_IDS` = golden − removed + approved-new + derived
  catalog table).
- P2: for golden IDs surviving (∉ REMOVED) and ENABLED on the cluster — per-model cmd token
  multiset == golden cmd token multiset (the existing bar, unchanged); non-cmd fields
  deep-equal as today.
- P3: for golden IDs surviving and rendered as echo — cmd BYTE-identical to the golden echo
  (the legacy message path).
- P4: `REMOVED_IDS ∩ renderedIDs == ∅` both clusters, in any form.
- P5: catalog IDs absent from golden render as echo on clusters that don't enable them —
  fail-fast SHAPE only (`/bin/sh -c "echo '<id> ...' >&2; exit 1"`), message not golden-pinned.
- P6: matrix parity (amendment E) re-expressed "additive preservation **modulo REMOVED**" —
  CA3 removes vars (coder/kat/…), which literal E forbade; macros/hooks/top-level scalars
  assertions untouched (hooks.preload stays exactly `[qwen3.8-27b-q8, qwen3-embedding-0.6b]`
  on gpu-ai, `no_new_model_preloaded` unaffected).
- Isolation flips (roster): `gpu_ai_only_families_absent_from_gpu` → present-as-echo;
  every roster `-hf`-ref assertion for a rung disabled on gpu cross-reads gpu-ai (the
  ratified D per-ID routing generalized — this is already the pattern of ratified B/D).

## CR3 — Removals (CA3) — USER RULING 2026-10-24 (replan question tool), FROZEN SET OF 13
Certain (matched the user's words at HEAD):
- `qwen3-coder-next-q6`, `qwen3-coder-next-q8` (chart; live on both clusters today)
- `kat-coder-q4`, `kat-coder-q6`, `kat-coder-q8` (chart; gpu golden disabled-echoes + gpu-ai live)
- `kat-coder-q4-1m`, `kat-coder-q6-1m`, `kat-coder-q8-1m` (gpu-ai local)
Ruled (ambiguous — resolved by the user):
- `coder-next-ablit` (gpu-ai; a Qwen3-Coder-Next abliteration) — REMOVED with the coder family.
- "all non-vision-handling qwen3.5*": ZERO literal `qwen3.5*` IDs existed (grep-verified;
  `Qwen3.5` appears only in vendored conversion scripts, unrelated). RULING = **B: the older
  text-only Qwen3 line** — `qwen3-30b-a3b-q4`, `qwen3-30b-a3b-q8`, `qwen3-8b-q4`, `qwen3-8b-q8`.
  The qwen3.6 line SURVIVES IN FULL: qwen3.6-27b-q6/q8, qwen3.6-35b-a3b-q6/q8 (incl. gpu's
  golden-pinned tuned regime), -1m/-bf16 (gpu golden echoes), -q8-visual, qwen36-heretic,
  qwen36-huihui.
**Frozen REMOVED_IDS (13) = the 9 certain + coder-next-ablit + the 4 Qwen3 text-line IDs.**
Catalog consequence: catalog = 58 IDs (chart 47 − 9 + gpu-ai-local 24 − 4); gpu renders
34 live + 24 echoes; gpu-ai renders all 58 live (echoes only via surviving cluster `disabled:`
overrides — none on gpu-ai).
- Strip everywhere: `models`/family entries, `matrix.vars` + set alternation tokens
  (v262 matrix.go:71 hard-errors on dangling vars — closure test re-run after every edit).
  Chart vars cut: coderq6, coderq8, katq4, katq6, katq8, q30q4, q30q8, q8bq4, q8bq8 (+
  `main` alternation tokens); gpu-ai vars cut: katq41m, katq61m, katq81m, cnxabl (+ `solo`
  tokens); gpu's kat-trio disabled-echo overrides go with them (golden P3 survivors under
  ruling B: qwen3-vl-30b-a3b-bf16, qwen3.6-35b-a3b-1m, qwen3.6-35b-a3b-bf16 — 3, byte-pinned;
  plus the C04 ornith-bf16 echo pinned by roster tests). Preload unaffected (verified:
  qwen3.8-27b-q8 + qwen3-embedding-0.6b both survive).
- Consumer-reference sweep (CA3 executes; replan-time findings + USER RULING "fix both in
  this PR", re-read under ruling B):
  1. `charts/minuspod/values.yaml:39 OPENAI_MODEL: qwen3.6-27b-q6` — under B this ID SURVIVES
     (qwen3.6 line kept) → NO change required; CA3 verifies and records that (no silent edit).
  2. `.rulesync/skills/pipeline-models/SKILL.md` (+ generated `.opencode/skills/` mirror):
     rows `gpu-ai / kat-coder-q8` and `gpu-moe / kat-coder-q6` reference DEAD ids → removed
     IN THIS PR (source edit + `rulesync generate`, sources+generated committed together per
     AGENTS.md). Rows `qwen3.6-35b-a3b-q8` (both clusters) and `openrouter qwen/qwen3.6-35b-a3b`
     SURVIVE under B → untouched. Re-recording the local-code fallback routing to whatever
     surviving model the user wants is OUT of scope (the lab just deleted local coder models;
     the rows go, nothing is invented).
  3. Everything else must be ZERO in-repo hits; grep outputs recorded in chunks/CA3.md.
- Machine-global (OUT OF REPO — USER handles; C05 runbook enumerates exactly, verified
  2026-10-24 against `~/.config/opencode/opencode.json`): provider `gpu-ai` 13 dangling
  `modelID` entries (kat×6, coder-next×2, coder-next-ablit, qwen3-30b-a3b×2, qwen3-8b×2…
  exact list in CA3) + provider `gpu-moe` 9 + the kilo twin
  (`~/.config/kilo/kilo.jsonc`) + coder-workspace flows. All qwen3.6 provider entries
  SURVIVE under B.

## CR4 — Entrypoint relocation (CA4)
`containers/llama-swap-autogen/entrypoint.sh` (new, COPY'd, executable, `#!/bin/sh`) becomes
the image ENTRYPOINT; it carries the generate/degrade/fail-open logic VERBATIM-equivalent in
behavior (fail-open rc0; comment-only 10-scanned.yaml; never clobber a successful generate;
tool stderr stays on the container log; `-iname '*.gguf'` quick-find). Args (flags):
`--scan-dir DIR` (repeatable) `--base FILE` `--out FILE` `--home DIR`; `--home` exports HOME
before invoking `generate` (makes C03 finding-#1's writable-cache contract explicit — the
init-only emptyDir mount stays); missing/duplicate required flags → usage error exit ≠0
(a wiring bug must surface loudly; degrade rc0 stays reserved for scan-empty/generate-fail).
Chart values keep image + args + mounts ONLY — no shell in k8s yaml. Drift guard re-expressed,
still failing fast on disagreement: the `llama-swap.autogenBase` helper now parses the
rendered initContainer `args` — `--scan-dir` set must equal `autogen.scanPaths` (both
directions) and any initContainer `command:` (especially one containing `/bin/sh`) fails the
render (shell-reintroduction tripwire).
Contract route (CA1): `test_autogen_wiring`'s `_init_script`/`_sandbox` degrade trio
re-expressed to execute the REPO-side `entrypoint.sh` file directly (daemon-free:
`sh containers/llama-swap-autogen/entrypoint.sh --scan-dir <sb>/models/scanned --base
<sb>/app/autogen/base.yaml --out <sb>/app/gen/10-scanned.yaml --home <tmp-home>` with the
stub CLI on PATH) + the same three contracts (empty-scan → comment-only + rc0; stub rc1 →
degrade file + rc0; stub rc0 → generated content preserved); wiring assertions flip from
"command script exists" to "no command, args match values"; `test_autogen_image` pins flip
from `ENTRYPOINT ["llama-swap-config-autogen"]` to the entrypoint.sh contract (Dockerfile
COPY + chmod +x + shebang + ENTRYPOINT exec-form; the gated docker checks keep proving the
console script via `--entrypoint` override — the script must still be on PATH).

## Replan chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| CA1 | contract rebase: superset parity + removals subtraction, family-schema tests, isolation flip, entrypoint/wiring/image test re-expression, frozen tables (CATALOG/REMOVED/ENABLEMENT) — TEST SESSION ONLY (ses_e9bdebccbffe7bYG46Fm9LO8FG) | M | 3 | [user approval of this replan] | frozen removal/enablement tables are the plan's input; tests immutable downstream |
| CA3 | removals: strip families/vars/sets/overrides + matrix closure + repo-wide consumer sweep record | M | 4 | [CA1] | needs P4/REMOVED expectations green-first; edits the CURRENT models-shape (before conversion) to keep CA2's diff clean |
| CA4 | entrypoint relocation: image entrypoint.sh + chart args + arg-driven drift guard + command tripwire | M | 4 | [CA1] | wiring/image contract re-expressed first; files disjoint from CA2/CA3 (containers/**, values app-template/autogen section, autogenBase helper) — same-wave parallel OK, coord may serialize (shared values.yaml, disjoint sections) |
| CA2 | family schema + expansion + full catalog conversion + per-cluster enables (chart, biggest) | L | 5 | [CA1, CA3, CA4] | converts the post-removal surface into families; CA1 expectations must exist; CA3/CA4 precede to leave one stable surface (CA4 is a file-conflict dep only: shared _helpers + values.yaml sections, no semantic coupling) |
| C05 | (existing, rebased in place) post-merge gpu verification + runbook — user-gated on PR landing | S | 6 | [C01–C04, CA1–CA4] | unchanged gating: ArgoCD syncs main only |

Wave order after approval: 3 → CA1; 4 → CA3 ∥ CA4; 5 → CA2; 6 → C05 (user-gated).
Post-CA2 review expects the full suite green (0f); between chunks, the reds are exactly the
later chunk's rebased tests (documented per-chunk bars below).

## Commands — replan additions (same bars as above PLUS)
- Superset parity bar: `pytest charts/llama-swap/tests/test_config_parity.py` under the
  rebased P1–P6 contract (goldens byte-untouched; live-model cmd multiset equality unweakened).
- Catalog render shape: default `helm template` (no cluster values) → EVERY catalog ID present,
  EVERY one an echo (`grep -c 'exit 1'` == catalog size in the rendered ConfigMap data); gpu
  render → enabled-set IDs carry real cmds, echo count == catalog − gpu-enabled.
- Entrypoint sandbox (CA1/CA4, daemon-free): the degrade trio runs
  `sh containers/llama-swap-autogen/entrypoint.sh --scan-dir … --base … --out … --home …`
  with a stub `llama-swap-config-autogen` on PATH (pytest does this; manual invocation
  equivalent).
- Drift-guard probes: initContainer `command` reintroduced → render fails; args
  `--scan-dir` set ≠ `autogen.scanPaths` → render fails ("disagree - edit both or neither").
- Consumer sweep (CA3): `grep -rn "<REMOVED_ID>" services/ custom-values/ charts/ skills/
  .rulesync/ .opencode/ containers/ .github/ --exclude-dir=golden` after stripping — zero
  in-repo hits (post ruling: the two pipeline-models kat rows are deleted in-PR and the
  generated mirror regenerated; minuspod's qwen3.6-27b-q6 survives ruling B and is verified,
  not edited); machine-global `~/.config/opencode/opencode.json` (13) + `gpu-moe` (9) + kilo
  twin dangling lists handed to the user (runbook).
- Matrix closure (unchanged test, new expectation): every `matrix.vars` value + set token in
  both renders exists in the merged `models` map (v262 matrix.go:71).
- Everything in the original Commands section stays, EXCEPT C02's literal golden-ID-equality
  wording, superseded by P1–P6 (goldens themselves byte-untouched, per user).

## Replan risks / notes
- Family expansion is chart-side Helm logic; v262 sees only rendered IDs — zero new upstream
  risk. All CRs verified feasible against v262 semantics (echo-model listing in /v1/models is
  the established kat pattern, scaled up).
- Enlarged gpu model list: OpenWebUI/Immich/HA pickers will show the full catalog (echoes
  fail-fast on request). Accepted consequence of CR2 — runbook note, no code change.
- CA1 must not weaken the live-model cmd bar while expressing superset semantics (P2/P3/P4
  above are the exact bars the test writer encodes; review re-runs and audits the amendment
  diff for assertion deletions, as done for A–F).
