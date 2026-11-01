# PLAN: Get Dev Forgejo Runner working
feature: 2026/2026-11-cf-97-bug-forgejo-runner

**Goal (reworked 2026-11-01 with the user's answers + fresh live evidence):** The dev runner (`dev-forgejo-runner-dev`) stops crash-looping on `connection "default" is invalid: 'uuid' is empty` and goes online against git.scifi.farm as the **instance-admin** runner the user has now located. The user has performed the record side (the instance runner record EXISTS — RESEARCH's "never created" sub-inference is superseded) and has put the uuid into vault item `d3dafd1a…` alongside the already-set token. The mapping question the user raised — "the secret doesn't do anything with it?" — is settled with evidence: **the ExternalSecret mapping is structurally sound; the populated fields CAN and DO reach the rendered config.** What remains live is only the write's landing (right item + login-username field) and the ≤1h ESO→reloader bounce, verified by C03. The repo-side work stays truthfulness-only: the "registration token" misnomer at the four shipped sites (instance-admin wording per the B3 ruling) + one stale dind test assertion.

**Architecture:** Three chunks, unchanged shape. Track A (C01, user) is now mostly done — what remains is a 2-minute landing-check (uuid in item **ID `d3dafd1a…`**, **login → username field** — see the bounce-window discriminator) and the bounce itself. Track B (C02) is repo-only: comment/NOTES wording at four sites + agent-test's mechanical t2 dind-pin repair. C03 verifies live via **read-only** cluster MCP after the bounce; depends on C01 (data: a populated, correctly-landed uuid is the precondition for `declared successfully`). No mapping-fix chunk: the mapping is proven sound below — adding one would be speculative.

**Tech Stack:** Forgejo 15.0.10 (Actions on by default, no app.ini change — RESEARCH F5), runner v13.2.0 declarative daemon, ESO via the **Vaultwarden-ESO webhook** SecretStore `bitwarden-login` (`http://bitwarden-cli:8087/object/item/{id}`), app-template 5.0.1 chart `charts/forgejo-runner`, ArgoCD ApplicationSet `charts.forgejo-runner-dev` alias, stakater reloader.

**Spec:** card #97 (`xJSxCDv3sqqgyHwDq`); `RESEARCH.md` is ground truth for the v13 registration contract and failure-mode tree; its "record was never created" sub-inference and the org-scope visibility reading are **superseded by the user's live find + answer** (DECISIONS rework entries). Citations `F1..F6`, `S1..S18` + this section's rework evidence.

## Verified facts (planning-round evidence, 2026-11-01, worktree @ branch `cf-97-bug-forgejo-runner` = main tip `6796aa50d`)

### Original round (unchanged)
- Baseline suite run (`bash tests/services/dev-forgejo-runner.sh`, `PATH=$HOME/.local/bin:$PATH`): t1 legs green; **suite aborts at the first FAIL of t2**: `dind image is 'docker:29.9.2-dind', expected docker:29.9.1-dind` (fail-fast `bad()` + `set -e` ⇒ all legs after t2 UNVERIFIED until the repair). Authority for 29.9.2: `values.yaml:95` + live pod + renovate `975b9d89d` (touched values only).
- Misnomer sites (four): `charts/forgejo-runner/values.yaml:35`, `templates/secret-runner.yaml:3`, `custom-values/dev/prod-values.yaml:84-85`, `templates/NOTES.txt:23`.

### Rework round — the user's "the secret doesn't do anything with it?" hypothesis: FALSE (evidence)
Repo side (chart→Secret chain, file:line):
1. `templates/secret-runner.yaml:62-68` maps `secretKey: uuid` ← `remoteRef.key: <bitwardenIds.runner-token>`, **`property: username`**; `:70-77` maps `token` ← same item, **`property: password`**. Per-key `data` — no `dataFrom.extract` anywhere. Live ESO spec confirms the rendered form: both entries carry key `d3dafd1a-3d88-454e-88d4-b4ec010ae2c2` — i.e. the `OVERRIDE_VIA_CUSTOM_VALUES` sentinel (`values.yaml:38`) → `custom-values/dev/prod-values.yaml:86` → deployed ESO flow is proven end-to-end; it points at the RIGHT item.
2. The target Secret template (`engineVersion: v2`, keys `config.yaml` + `token`) consumes exactly those data keys: `uuid: "{{ .uuid }}"` (`:51`), `token: "{{ .token }}"` (`:33`), `token_url: file:$CREDENTIALS_DIRECTORY/token` (`:52`) with `CREDENTIALS_DIRECTORY=/run/secrets/forgejo-runner` (`values.yaml:150-152`) and the whole Secret volume-mounted there under the release-exact name (`values.yaml:206-212`). Key names match 1:1.
3. `secretStoreRef: bitwarden-login` (`:23-25`) is the fleet's standard login store: live SecretStore `default/bitwarden-login` is a **webhook** provider with `url: http://bitwarden-cli:8087/object/item/{{ .remoteRef.key }}` (Vaultwarden's ESO endpoint; flat `username`/`password` properties). Repo-wide, **145** ExternalSecret templates use `bitwarden-login` with the same `property: username|password` spelling, including the forgejo chart's OWN working admin/db/token secrets (`charts/forgejo/templates/secret-forgejo-admin.yaml:10,19,27`) — the live server that the user is browsing is bootstrapped through this exact shape. The runner chart's mapping is the proven-correct pattern, not a variant.

Live side (readonly-dev-kubernetes, 2026-11-01 ~20:45Z, presence/emptiness posture — no secret values read):
4. ExternalSecret `dev-forgejo-runner-dev`: `refreshInterval: 1h`, Ready=True `SecretSynced` (condition transitioned 2026-11-01T00:55:28Z and held — the webhook path is healthy all day).
5. Pod `dev-forgejo-runner-dev-0`: `startTime 15:40:13Z`, runner container `restartCount 63`, last termination `20:39:48Z`, current log line still `invalid configuration: ... 'uuid' is empty`; dind sidecar Running. StatefulSet `dev-forgejo-runner-dev`: single revision (`currentRevision == updateRevision == …-659f5b6b57`), `availableReplicas 0`.
6. **Bounce oracle (the decisive discriminator):** the 15:40:13Z pod replacement was itself an ESO→Secret→reloader bounce (RESEARCH S17: old pod killed 15:40:12, "secret-change bounce consistent with the user editing the vault"). Since then the pod has NOT been replaced (same startTime, same STS revision) ⇒ the target Secret's rendered content has not changed since ~15:40. The hourly refresh guarantees a fetch within ≤1h, so either (i) the uuid write landed LESS than ~1h ago (pending — the bounce WILL come), or (ii) it landed earlier but changed nothing the ESO reads — i.e. the uuid is NOT in item `d3dafd1a…`'s **login → username** field (wrong similar-named item — the repo's own item-name comments disagree, see DECISIONS 2026-10-24 "the UUIDs are the truth" — or a custom field/notes/URI instead of username).
7. The instance-scope runner record EXISTS (user find) — so RESEARCH's "record never created" is superseded; the uuid-empty fail-fast call stands (log line, live). Pair-match risk: the token was set in the vault earlier ("I've confirmed the secret has the token set") — if it belongs to a DIFFERENT record than the found runner's uuid, the post-bounce failure shape changes from `uuid is empty` to `unregistered runner` on Declare (RESEARCH F2). C01/C03's playbooks handle both.

## Out of scope

- **Smoke test — DECLINED by the user (2026-11-01 answer Q6):** no workflow push, agent- or user-runnable; C03 acceptance is read-only evidence only. (Prior draft's optional smoke AC removed.)
- Runner image bump 13.2.0→13.2.1 and stale `appVersion: 15.0.9` in `charts/forgejo/Chart.yaml:13` — dep-ticket hygiene (RESEARCH rec 5).
- Infra-instance runner relocation (item `b1add65b…`) — stays out (user answer Q5).
- The 2026-10-24 recreation/SecretSyncedError debug — **closed as superseded by user decision Q4**; recorded in STATE `deferred[]` as user-owned, nothing executes it.
- Org-scoped runner setup anywhere — **superseded: scope = instance-admin** per the user's answer (B3 ruling reaffirmed; the user's own find).
- app.ini/queue/redis, chart topology, `.runner` PVC, `GITHUB_SERVER_ADDRESS`/`RUNNER_CONFIG` env — verified-not-the-fix (RESEARCH rec 6).
- Any Bitwarden or cluster mutation by an agent; no `kubectl apply` — ArgoCD owns applies; no chart `version:` bumps; no push/merge to `main` (user-owned).

## Commands (repo validation — AGENTS.md "Pipeline specifics")

```bash
export PATH=$HOME/.local/bin:$PATH          # MANDATORY: helm lives here; without it helm-guarded legs misshape
cd "$(git rev-parse --show-toplevel)"

bash tests/services/dev-forgejo-runner.sh   # THE runner contract suite (fail-fast — green == every leg ran)
helm lint charts/forgejo-runner
helm template dev-forgejo-runner-dev charts/forgejo-runner            # standalone render (sentinels stand in)
helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml \
  --set domain=scifi.farm --set clusterName=dev | grep -c OVERRIDE_ || true
  # umbrella render must exit 0 and print count 0 (grep exits 1 on zero matches — the
  # COUNT is the signal, not grep's status)

# C02 blast radius: only comments + NOTES.txt change — every YAML diff hunk touches comment
# lines only (template-file comments DO ride raw helm-template output; semantic identity is
# asserted by the suite's ESO legs, not byte equality):
git diff --stat main
npx --yes aislop@0.18.1 ci --changes --base main   # quality gate (YAML/MD-only diffs scope 0 — known no-op, FRICTION-ported)
```

Service-trio check (AGENTS.md): chart entry ✓ + ApplicationSet values entry ✓ + proxy leg N/A-BY-DESIGN (client-only dials-out, documented at `services/dev/prod/values.yaml` runner comment) — C02 adds no service, no-change confirmation only.

Cluster-side verification (C03 only, `readonly-dev-kubernetes` MCP — no shell equivalent, labelled cluster-only): `resources_get` ExternalSecret/StatefulSet `dev-forgejo-runner-dev`, `pods_get`/`pods_log` `dev-forgejo-runner-dev-0` (container `runner`). Exact-name reads only — `pods_list`/`events_list`/`resources_list` shapes come back empty/redacted for agent sessions (re-confirmed this round; carried FRICTION).

## Chunks

| id  | title | size | wave | owner | depends_on | why the dependency |
|-----|-------|------|------|-------|------------|--------------------|
| C01 | Confirm the uuid's landing + the bounce (record side already done by user) | S | 1 | **user** | [] | — (starts immediately; independent of repo chunks) |
| C02 | Comment/NOTES truthfulness (instance-admin wording) + test dind-pin repair | S | 1 | agent | [] | independent of C01: pure repo wording + contract sync |
| C03 | Live read-only verification of the online runner (no smoke test) | S | 2 | agent | [C01] | data: `declared successfully` requires the correctly-landed uuid + a bounce; C02 does not affect runtime |

C01 ∥ C02 in wave 1 (run in id order); C03 gates on C01 only.

## Wave order

1. **C01 (user, minutes away)** — landing-check + bounce window. **C02 (agent)** — after the agent-test round, dev runs the amended suite green.
2. **C03 (agent)** — read-only MCP evidence that the runner declared; user-eyeball AC: the runner shows **online** under Admin → Actions → Runners.

## Risks / assumptions

- **Pair mismatch is the top live risk:** token set earlier + uuid from the found record may belong to different records → post-bounce `unregistered runner` instead of success. Handled by C01's playbook (recreate/verify one record, copy its shown-once pair as a set). Not a plan change.
- If the landing-check finds the uuid in a custom field / the wrong item, the fix is vault-side (re-paste to item `d3dafd1a…` login-username); still no repo change. If — after a confirmed correct landing >1h old with no bounce — the crash line persists, the structural verdict above is wrong; that outcome reopens this plan (NEEDS_INFO) instead of ad-hoc chart edits.
- ESO refresh ≤1h + reloader bounce means C03 must not conclude failure before the bounce window elapsed (check pod `startTime` vs the reported write time first).
- Scope wording in NOTES.txt follows instance-admin as the only path (user answer) — the org alternative is dropped, not demoted.

## Open questions

Resolved by the 2026-11-01 batched round: Q2 → **instance-admin** (B3 reaffirmed, user find); Q3 → moot (`git.scifi.farm`, no org); Q4 → closed-superseded (deferred[]); Q5 → out; Q6 → **no smoke test**; Q1/Q7 → accepted/obsolete (vault state now user-confirmed: token set, uuid written).

Still open (must reach the user before/at C01 completion — none block PLAN APPROVAL):

1. **Where and when did the uuid write land?** Item **ID `d3dafd1a-3d88-454e-88d4-b4ec010ae2c2`** (not a similar-named item), **login → username** field (not a custom field/notes/URI), and at what UTC time? The pod has not bounced since 15:40:13Z: a write older than ~1h that changed nothing the ESO reads means wrong item or wrong field — re-paste accordingly. A write within the last hour needs only the ≤1h wait (or a forced ESO resync). Best guess: within the last hour OR a similar-named item's username. Impact: C01 completion timestamp only; chunk shape unchanged either way.
2. **Token provenance** (only if C03 later sees `unregistered runner`): does the vault token come from the SAME instance-runner record whose uuid was copied? If not: delete/recreate the record, copy the shown-once uuid+token as one pair. Impact: a second pass through C01, no repo change.
