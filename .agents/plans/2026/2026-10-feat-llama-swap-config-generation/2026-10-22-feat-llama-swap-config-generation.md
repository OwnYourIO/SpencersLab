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

---

# REPLAN ROUND 2 (CR5) — display/tag derivation (agent-plan, 2026-10-24)

All C01–C04 + CA1–CA4 stay done/APPROVED untouched; C05 stays the final user-gated wave.
This section extends the plan with the CR5 request (DECISIONS 2026-10-24 "CR5 replan
round"). Goldens stay byte-untouched.

## CR5 goal (two sentences)
Maximize Helm-template-side derivation of the per-rung display strings (`name:`/
`description:`) and image refs (`hf:` repo prefix + quant TAG) so the chart catalog's
rung bodies shrink to what is genuinely per-rung DATA (tag exceptions, tuned regimes,
sizes, prose), with the composition GRAMMAR living once in `_helpers-llama-swap.tpl`.
Out of scope: changing rendered bytes for golden-pinned survivors, renaming any model
ID, touching the scanned-half machinery (autogen image/entrypoint), and any
Path-B-fork revival (RESEARCH §1/§2 + DECISIONS 2026-10-22 stand: the stock tool is
disk-scan-only with a fixed `-m` cmd template and can never emit `-hf` or
name/description for the declared half — cited, not re-researched).

## Measured starting surface (HEAD 5faada77b, this replan)
- 58 rungs: 57 `hf:` full `repo:TAG` literals (57 distinct strings across 23 repos),
  58 `name:` + 58 `description:` lines; 43 rung bodies contain only display/ref lines
  + enablement. Family data (`enabled`, `use`, `ttl`, `flags`, `spec`, `draft`,
  `capabilities`, `aliases`) is real per-cluster/per-rung content and is NOT touched
  by any option.
- Golden-pinned display strings = the **42 survivors** = (gpu golden ∪ gpu-ai golden)
  − REMOVED (P2 `test_c02_2_per_model_fields_deep_equal` loops `golden ∩ fresh −
  REMOVED` and deep-equals EVERY non-cmd field INCLUDING on echo-shaped renders —
  enablement does not exempt). The **16 C04-new IDs** (ornith 35B×7 + 122B×4 +
  flash-next×4 + fn-orca×1) have NO golden anywhere → derivation there is free
  (roster tests pin their `-hf` REFS + ttl + matrix, never name/description text).
- Per-cluster pinning nuance (measured): gpu-ai's `models.` re-composition of
  qwen3.8-27b q4/q6/q8/bf16 + qwen3.6-35b-a3b-q8 + rana means the CHART RUNG text for
  those ids is pinned only by the GPU golden (the service-layer explicit strings keep
  riding the models layer untouched). qwen38/qwen36/embedding/q36-35b-q8-visual/
  q38-27b-q8-1m/-q8-visual are gpu-ai-local → pinned by the GPU-AI golden.
- Grammar fit vs the golden strings (byte-exact composition verified against the
  captured goldens this round):
  - NAME pattern `{dispName} ({TAG})`: fits 26/42 survivors + 11/16 new (ornith duo)
    = qwen3.8-27b {q4,q6,q8,bf16}, qwen3.6-27b×2, qwen3.6-35b-a3b {q6,q8,bf16},
    all 18 VL rungs (with family `descTail`), embedding name only.
  - DESC pattern `{descBase}, {TAG} quant` / `{descBase}, BF16 (no quant)` +
    optional family `descTail`: fits the same families' descriptions (qwen3.8-27b
    "…dense model", qwen3.6-27b "…general purpose model", qwen3.6-35b-a3b
    "Qwen 3.6 35B with 3B active parameters (MoE)", 6× VL families with their tails;
    the 1m rung's desc derives from its Q8_0 TAG — the golden 1m desc does NOT
    mention 1M, mechanically confirmed this round).
  - PROSE (no honest grammar): 14 survivor rungs — home×2, q8-visual×2, q8-1m name,
    qwen38×5, qwen36×2, whisper×1 — plus all 16 new ids' descriptions (they carry
    per-rung DATA: GiB sizes, over-budget warnings, MTP markers, SOLO notes) and
    flash-next×4 + fn-orca×1 names (embedded ", MTP"/"Orca" prose).
- Repo/tag culture fit (Option 2): one-repo-per-family = 12/18 (all 6 VL, qwen3.6×2,
  home, embedding, 122b, flash-next, fn-orca… 13 counting q36-35b); mixed repos:
  qwen3.8-27b (+ggml-org bf16), ornith-1.5-35b-a3b (+bartowski iq2xxs/q3),
  qwen38 (4 repos), qwen36 (2). Quant-key→TAG cultures that are REGULAR:
  `standard` {q4:Q4_K_M,q5:Q5_K_M,q6:Q6_K,q8:Q8_0,bf16:BF16} covers 6 VL families×3 +
  qwen3.6-27b×2 + qwen3.6-35b-a3b {q8,bf16} + ornith-1.5-35b-a3b official×5 = 26
  rungs; `unsloth-ud` {q3..q6:UD-Q{q}_K_XL} covers flash-next×4 + 122b×4 + qwen3.8-27b
  {q4,q6} = 10 rungs. 21 rungs stay honest exceptions (variant keys 1m/visual/
  embedding-0.6b/home-cpu→Q4_K_M, qwen38/qwen36 per-repo tags, UD-Q6_K one-off) —
  NO universal regex is invented; per-repo culture is modeled as a data map.

## Options (user ruling at this gate)
### Option 1 — derive name+description only (template-composed)
Family vocab fields `dispName:`/`descBase:`/`descTail:`; rungs keep explicit
`name:`/`description:` wherever prose (derive-if-absent). Byte-exact vs goldens by
construction → P2 needs NO amendment; suite bar unchanged 0f/147p/12s. ~50 display
lines drop, ~20 vocab lines return; net ~−30. Recommended posture per family:
byte-exact derivation (zero contract churn) > values override > display-field
relaxation amendment — the LAST is not recommended (relaxing P2's non-cmd compare for
name/description would weaken the consumer-visible picker contract for 42 ids and
still could not honestly derive the 14 prose rungs: the vocabulary would just move
into new values fields).
### Option 2 — Option 1 + repo/tag shorthand (RECOMMENDED)
Adds family `hfRepo:` (+ optional `tagCulture:` preset name from a chart-level
`config.tagCultures:` map, filterPresets-style) with rung `tag:`/`repo:` exceptions and
the full literal `hf:` retained as the rung-level escape (qwen38/qwen36 keep today's
shape — honest: shorthand buys them nothing). Composition resolves BEFORE the
models-layer merge, so services' `models.<id>.hf:` full-ref overrides (gpu tuned
ornith/q36 rungs) keep today's exact precedence (family < rung < models, DECISIONS
2026-10-24 CA3 ruling). Rendered `-hf` tokens are byte-identical → cmd bars UNBENTED;
the two VALUE-SHAPE schema tests that read rung `hf` (offenders rule +
hf-refs-match-golden eff-compare) must be re-expressed to compute effective refs
through the same culture map — routed amendment = chunk CB1 (test session
ses_e9bdebccbffe7bYG46Fm9LO8FG, CA1-style). Best case the ladder collapses to
one-liners: `q4: { aliases: [qwen3-vl-4b] }` or bare `q6:`.
Representative DIFFs (measured, before → after):
1. golden-pinned unsloth-style `qwen3.8-27b` — before: 6 rungs × hf+name+desc (+
   tuned extras); after: +3 vocab lines (dispName/descBase/hfRepo),
   `q4:{tag:UD-Q4_K_XL} q6:{tag:UD-Q6_K_XL} q8:{tag:Q8_0}
   bf16:{repo:ggml-org/Qwen3.8-27B-GGUF,tag:BF16}`, q8-visual/q8-1m bodies keep
   explicit hf+name+description (prose). 12 display/ref lines → 0; 4 tag lines.
2. official/standard-culture `qwen3-vl-4b` — before: 3 rungs × hf+name+desc,
   q4 also aliases; after: +4 vocab lines (dispName/descBase/descTail… descTail
   empty→omitted), ladder = `q4: { aliases: [qwen3-vl-4b] }` `q8:` `bf16:` —
   quant tags ALL derive from `tagCulture: standard`. 9 display/ref lines → 0.
3. bartowski/mixed `ornith-1.5-35b-a3b` (no golden) — before: 7 rungs ×
   hf+name+desc; after: +3 vocab (hfRepo: ornith-ai/…), `iq2xxs:
   {repo: bartowski/…, tag: IQ2_XXS}` `q3: {repo: bartowski/…, tag: Q3_K_XL}`
   `q4: {tag: Q4_K_M}`…(or bare under standard culture); names derive (11 free
   ids), descriptions stay prose (sizes are data) unless the user rules the
   `size:`-parameterized grammar (Q3 below).
### Option 3 — Option 2 + generated quant roster (probe → checked-in YAML) — NOT recommended
A probe enumerating each family repo's published quant tags live (reusing hf_check.py's
loader-mirror machinery, TEST_SPEC §7(F)) emitting a checked-in roster consumed via
values merge, with refresh ownership + churn policy. Honest strikes, all evidenced in
this ticket: (a) it does NOT remove authoring — the operator CHOSE 7/14 ornith rungs
for quality/regime reasons (DECISIONS 2026-10-22 35B-ladder ruling); enumeration
proposes, humans still select, and the generated artifact still lands in git;
(b) frozen-tag safety was an explicit contract: repos churned 2026-10-21, refs were
frozen precisely so auto-expansion cannot silently add routable models or break
`-config-dir` stability, and the C04 contract requires LIVE RE-VERIFICATION
(standing rule: frozen tables update ONLY via the test session); (c) gated repos
(orcarouter duo, 401 anonymously — C04 friction record) cannot be enumerated without
an HF_TOKEN in the probe runner; (d) GitOps self-commit loops (CI job writing to the
ArgoCD-synced repo) are a distinct architectural pattern with real sharp edges.
THIN VARIANT worth having regardless: keep hf_check.py as the live-verification gate
+ optionally a human-invoked `--suggest` mode listing available tags per family repo
(dev aid, NOT consumed by the chart; zero contract surface).
If the user picks Option 3 proper: this is a GENUINE RESEARCH GAP (probe design under
gating/rate limits; generated-artifact refresh patterns in ArgoCD GitOps — churn
policy, write-back loops, who owns the commit) → coord must commission agent-research
(STORM) BEFORE CB3+ chunking; this replan does not ad-hoc-solve it.

## CR5 in-scope answers (all options)
- Enablement lists: gpu's `enabled: true` flips stay exactly as landed (family-level
  3 + per-rung 31 = 34 enabled/24 echoes); per-rung overrides/tuned regimes MUST and
  DO stay representable — the models layer is untouched by derivation (precedence
  family < rung < models pinned by DECISIONS 2026-10-24 CA3 execution ruling;
  derivation is a family+rung-internal step). Services files get ZERO edits under
  Options 1/2 (CB2 acceptance proves it with an empty `git diff services/`).
- `home-3b-v3` `id:` override: unchanged (ID derivation is not display derivation).
- whisper/rana raw-cmd escape hatches: unchanged. whisper has no `hf` at all (grammar
  requires it — undecorated automatically); rana's inert documented hf/draft fields
  may shorten to the shorthand only cosmetically — its gpu-ai models-layer raw cmd +
  explicit name/description stay byte-pinned.
- Echo-shape default message (deviation 1): stays the static string "is not enabled
  on this cluster - see the chart catalog" — catalog growth does NOT change echo text
  (no interpolation today, none added); deviation-1 wording rule (values carry the
  full post-id message; template composes the byte-exact golden echo) is preserved
  verbatim. Derived name/description render on echo entries exactly as today.

## CR5 chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| CB1 | contract amendment (OPTION ≥2 ONLY): shorthand-aware effective-ref computation in the two value-shape schema tests + strip-list extension to the new schema keys — TEST SESSION ses_e9bdebccbffe7bYG46Fm9LO8FG ONLY | S | 6 | [user CR5 ruling] | tests immutable downstream; CB2 changes rung value-shape (`hf` literals → culture+tag) that CB1's tests read; CA1-first pattern (red set = CB2 names at handoff) |
| CB2 | template-side derivation machinery (`llama-swap.deriveDisplay`/`deriveHf` in _helpers) + chart values catalog conversion (vocab fields + shorthand); services untouched | M | 7 | [CB1 if Option≥2; none for Option 1] | amended contract must exist before the values-shape changes; under Option 1 CB2 is contract-neutral (amendment-less) and alone |
| C05 | (existing, unchanged tasking + runbook) — post-merge gpu verification, user-gated on PR landing | S | 8 | [C01–C04, CA1–CA4, CB1*, CB2] | ArgoCD syncs main only; final wave stays final |

Wave order after approval: 6 → CB1 (skipped under Option 1); 7 → CB2; 8 → C05 (user-gated).

## CR5 commands (plan Commands PLUS)
- RENDER-INVARIANCE SNAPSHOT (the controlling bar): before ANY CB2 edit, capture all
  three plan renders (default / gpu / gpu-ai extract-and-render) to /tmp/opencode/cr5-before;
  after the edit, re-render to /tmp/opencode/cr5-after; `diff -r` MUST be empty.
  (CA2-friction promotion: whole-section YAML surgery is proven safe only by
  before/after render diff, not by reading.)
- `pytest charts/llama-swap/tests -v` => Option 1: 0f/147p/12s UNCHANGED (zero
  amendments); Option 2: CB1 lands 2 amended value-shape tests + strip-list extension
  (name-identical red set naming CB2 at CB1 handoff), CB2 => full suite green again
  (gates 3p/5s unchanged; live `RUN_HF_CHECK=1` + direct `hf_check.py` still all-OK —
  render-invariance makes this a formality but run it).
- New-schema-key strip grep over all three rendered ConfigMaps:
  `grep -E '^\s*(dispName|descBase|descTail|hfRepo|tagCulture|tagCultures|tags|tag|repo|size):'`
  => zero hits (values-file-only keys; `tags` is also a matrix key — the grep scopes
  the ConfigMap data body only, where matrix lives at top level; reviewer scopes by
  section, the pytest strip-list assertion is the mechanical bar).
- Services-untouched proof: `git diff --name-only HEAD -- services/` empty in the CB2
  worktree after conversion (services files had no CR5 edit — Option 1/2 are
  chart+template only).
- Standing bars unchanged: helm dep/lint --strict, trio/sentinel greps, aislop on
  touched files, goldens `git diff` empty.

## CR5 risks / notes
- Derivation grammar duplicated template-side (helm) and — under Option 2 — one
  effective-ref computation in the CB1 test amendment. Mitigation: the render-invariance
  snapshot + P1–P6 prove equivalence of OUTPUT; the test-side mirror reads the SAME
  `config.tagCultures:` map from chart values (validates composition, not map content).
- Free-16 display text: default posture KEEPS every current string byte-identical
  (derivation reproduces them; prose stays prose). Any NORMALIZATION of new-id text
  (dropping ", MTP" from flash-next names, parameterizing ornith sizes) is a separate
  user ruling (Q3 below) — none is contract-required.
- Option 3 is not chunked past CB1/CB2 here BY DESIGN: picking it triggers a research
  commission first (plan rule: research via coord, never ad hoc).
- A–F/G1/G2 amendment precedent holds: any CB2-discovered validation_at_fault routes
  back to ses_e9bdebccbffe7bYG46Fm9LO8FG; dev never edits tests.

## CR5 user rulings (2026-10-24 question tool — THIS section supersedes the pre-ruling
## posture above where they differ; the option text stands as the presented record)

- **Depth: Option 2** — display grammar + repo/tag shorthand (chunks CB1→CB2, waves 6→7;
  C05 stays the final wave 8, user-gated).
- **Display regime: RELAX P2 for display fields.** Routed CB1 amendment removes
  `name`/`description` from the golden deep-compare in
  `test_c02_2_per_model_fields_deep_equal`; cmd-token multiset equality and every OTHER
  non-cmd field (ttl/proxy/aliases/capabilities/filters/checkEndpoint/env) stay
  golden-pinned UNBENTED. The relaxation REPLACES the golden pin with a compensating
  contract (CB1): display presence on all 58 rungs both clusters + the per-id
  before/after display-text table the user reviews pre-PR. NOT a bare deletion — review
  audits the amendment diff assertion-for-assertion (§A–O precedent). Consequence the
  user accepted: picker text for golden-pinned survivors CAN change (IDs/aliases — the
  programmatic contract — cannot).
- **Free-16: A + full normalization.** flash-next/122B/fn-orca names+descriptions adopt
  the uniform grammar; rung `size:` (GiB) + rung `descTail` overrides carry the real
  data; the ", MTP" marker DERIVES from draft/spec presence (auto), variant/word
  prefixes inside parentheses normalize away.
- **Option 3 declined** (no research commission, no CB3+). The thin
  `hf_check.py --suggest` dev-aid mode: post-wave hardening-chore candidate only.

### CR5 grammar (outcome-level interface; dev owns spelling)
- NAME: `{disp | fam.dispName} ({TAG}{, MTP if draft or spec}){ - {suffix}}` —
  `disp`/`suffix`/`variant` are optional rung/family DATA fields; explicit rung
  `name:` always beats derived (derive-if-absent); raw-cmd rungs without `hf` are never
  decorated (whisper keeps explicit text by construction).
- DESCRIPTION: `{descBase}, {TAG} quant` / `{descBase}, {TAG} (no quant)` for BF16/F16
  + optional family `descTail` / rung `descTail` override (+ `{size}` interpolation for
  the normalized new families); explicit `description:` beats derived.
- HF: rung `hf:` literal > compose `{repo | fam.hfRepo}` + `:` +
  (`tag` | `config.tagCultures[fam.tagCulture][quant-key]`). The two culture maps are
  VALUES DATA (standard: Q4_K_M/Q5_K_M/Q6_K/Q8_0/BF16; unsloth-ud: UD-Q{n}_K_XL), not a
  regex — the 21 irregular rungs keep per-rung `tag:`/full `hf:` honestly (qwen38/qwen36
  stay full-literal families: 4- and 2-repo fan-out, shorthand buys them nothing).
  `draft:` refs stay full literals. Resolution order: compose hf → derive display from
  that rung-level hf → THEN merge raw `config.models` over the top (precedence
  family < rung < models stays pinned by DECISIONS 2026-10-24 CA3 ruling; models-layer
  `hf`/`name`/`description` overrides beat derivation exactly as today).
- All new keys (dispName/descBase/descTail/size/disp/suffix/hfRepo/tagCulture/
  tagCultures/tag/repo) are chart-values concepts — stripped from every render.

### CR5 controlling bars — ADJUSTED (supersedes the byte-empty render-invariance bar)
1. Rendered output diff vs HEAD touches ONLY model `name`/`description` VALUES:
   mechanically, both-cluster + default renders compared with those keys excised MUST
   be byte-equal (the CB2 snapshot check, rest-class invariance).
2. A per-id display-text before/after table (all 58, both clusters) recorded in
   chunks/CB2.md dev-findings + RESULT — USER-APPROVED before the PR (C05 prerequisite;
   the table is the human review that replaced the golden display pin).
3. P1 exact-ID, P2-cmd multiset, P3 byte-echo strings, P4, P5, P6, alias/VL/matrix/
   closure/preload tests, trio/sentinel greps, gates 3p/5s, live hf_check: ALL run with
   today's semantics, unbent.
4. Suite: CB1 handoff = red set exactly the CB2-owned names (shorthand-aware +
   compensating presence tests) per CA1 pattern; CB2 completion = full green
   (147 + CB1's new tests, 12 evidence skips) with `helm lint --strict` + 3 renders.
