# PLAN: Audio Ad Detection (cf-133)
feature: 2026/2026-11-cf-133-feat-audio-ad-detection

## Goal
A single headless container taps the home snapcast stream (a supervised
`snapclient` file-player child), fingerprints the audio in realtime with
SoundFingerprinting 18.0.0, and publishes ad events to Home Assistant over
MQTT (device discovery + `event` entity). The ad catalogue grows by
**auto-capture with auto-promote on recurrence** (owner override 2026-11-24):
non-matching spans of the stream are cut to candidate WAV segments on the
PVC; candidates that recur independently (≥2 sightings ≥24 h apart, proximity-
deduped, per-day cap) are fingerprinted into the live catalogue automatically
(`auto_promoted` flag — auditable/prunable via `list`/`prune`), with a manual
`promote` lane for single-shot candidates.

## Architecture (grounded in RESEARCH.md; batched-round answers of 2026-11-24 folded in)
- `containers/audio-ad-detection/` — multi-stage `mcr.microsoft.com/dotnet/sdk:10.0` →
  `dotnet/runtime:10.0` (both = 10.0.15 noble, amd64; R3), framework-dependent
  publish; the snapclient 0.35.0 bookworm `.deb` (GitHub release, renovate
  comment-above-ARG pin) installs in the runtime stage (R2 §4). Worker = .NET 10
  Generic-Host console: supervised snapclient child (argv per R2 implication 1:
  `--player file:filename=stdout --sampleformat 5512:16:* --logsink stderr
  --hostID <pinned> tcp://home-snapcast:1704` — Q6 answered as planned),
  stdout read loop (4-byte frame parity) + stderr drain thread, byte-cadence
  watchdog (R2 §2 #1563 posture — Q5 answered as planned), startup
  `Group.SetStream` (one-shot JSON-RPC `POST /jsonrpc` on
  `SNAP_RPC_URL` default `http://home-snapcast-snapcast-http:1780/jsonrpc`;
  `Server.GetStatus` finds the group containing the pinned `--hostID`, then
  `Group.SetStream` re-points the tap — R2 §5 mechanics; only when
  `SNAP_STREAM_ID` holds a real value, else config-order + logged marker),
  s16le→float + stereo→mono (NAudio.Core 3.3.0 low-level `WdlResampler`
  Sinc64 only when the input rate ≠ 5512 — R3 §2; Q6: snapclient-side
  `5512:16:*` is the default, 22 kB/s pipe), per-chunk RMS + last-match
  tracking, exactly 10,240-sample @5512 chunks → `BlockingRealtimeCollection`
  → `IRealtimeQueryCommand` (R1 §1; **pin SoundFingerprinting 18.0.0** — Q4;
  the realtime contract was source-verified by R1 at 17.4.0, 18.0.0 parity is
  the Post Research verification focus, recorded fallback pin 17.4.x),
  `InMemoryModelService` + `Snapshot()` on the PVC (R1 §3),
  **auto-capture** (Q3, owner override 2026-11-24): a non-matching span ≥
  `CAPTURE_MIN_SPAN_SECONDS` (default 30) with RMS above the floor (default
  −45 dBFS — TV-off silence must not fill the dir) is cut with 5 s pre/post
  roll from a ring buffer and written to
  `/models/candidates/<group>_<UTC-timestamp>_<duration>s.wav`; capped at
  `CAPTURE_MAX_SPAN_SECONDS` (default 300); retention `CAPTURE_RETENTION_DAYS`
  (default 14) / max 200 candidates, pruned on startup + periodically;
  **auto-promote on recurrence** (the owner override — supersedes the
  never-auto-promote posture): a candidate that recurs independently
  (`AUTO_PROMOTE_MIN_SIGHTINGS` 2 distinct sightings ≥
  `AUTO_PROMOTE_MIN_GAP_HOURS` 24 h apart — repetition across episodes/pods is
  the ad signal per R1's recurrence evidence), after fingerprint-proximity
  dedup (vs the existing catalogue and previously promoted candidates) and
  under the `AUTO_PROMOTE_MAX_PER_DAY` 20 per-day cap, is fingerprinted into
  the live catalogue with `kind=ad` + `auto_promoted: true` meta +
  `Snapshot()`; the manual `promote --file|--dir` lane STAYS (curated-dir
  capability survives as `promote --dir`); `list` (candidates + auto-promoted
  tracks — the human audit surface) and `prune` (retention + `--track <name>`
  for promoted entries); MQTTnet 5.2.x
  publisher (retained device discovery per R4 §3 sample, never-retained event
  state, LWT + `expire_after`, availability; anonymous by default — Q1 verdict
  (a)); `HttpListener` `/healthz` + `/readyz` + `/metrics` (R3 §1 shape A;
  hand-rolled text exposition: `aad_audio_rms_db`, `aad_capture_candidates_total`,
  `aad_snapclient_kills_total`), `readOnlyRootFilesystem` + writable set `/tmp`,
  `$HOME`, model dir (dev-time verify — R3 §1), SIGTERM ordering kills the
  child before closing the pipe read end (R3 implication 7).
- `charts/audio-ad-detection/` — bjw-s app-template **5.0.1** (repo standard,
  verified across all 55 charts), brand-new `version: 1.0.0` (never hand-bump
  after), Deployment strategy `Recreate`, 1 replica, **10Gi RWO PVC** (model
  snapshot + candidate dir), ClusterIP service (headless — no ingress), D-8
  scrape-annotation pair (`k8s.grafana.com/scrape` +
  `k8s.grafana.com/metrics.portNumber` = 8080, the health/metrics port,
  ternary on a `monitoring.annotations` gate, the charts/vllm idiom),
  probes: generous startup, liveness HTTP `/healthz` (process health only —
  **never on audio silence**; RMS is a capture gate and a metric, never a
  liveness/readiness input), readiness `/readyz` (model loaded + query loop
  running + MQTT connected + pipe data flowing; stream assignment does not
  block readiness — config-order is a working state); `SNAP_STREAM_ID` is a
  **required** value with the documented placeholder `TBD-owner` (Q2: family-TV
  group; the name is not yet supplied — worker runs config-order until then;
  name supply is C05 owner leg); standard security context +
  `createDefaultServiceAccount: false` (mosquitto shape); env/config surface:
  `SNAP_URL`, `SNAP_HOST_ID`, `SNAP_SAMPLE_FORMAT`, `SNAP_STREAM_ID`,
  `SNAP_RPC_URL`, `MQTT_BROKER_HOST/PORT` (no creds by default),
  `MQTT_USERNAME/PASSWORD` (optional code path only — see fallback note),
  thresholds (`NEW_OCCURRENCE_ABOVE` default 120, `COVERAGE_SECONDS` default 5,
  `OngoingEntryStalenessCeiling` 120 s, `CAPTURE_MIN_SPAN_SECONDS` 30,
  `CAPTURE_MAX_SPAN_SECONDS` 300, `CAPTURE_RMS_FLOOR_DB` −45,
  `CAPTURE_RETENTION_DAYS` 14, `AUTO_PROMOTE_MIN_SIGHTINGS` 2,
  `AUTO_PROMOTE_MIN_GAP_HOURS` 24, `AUTO_PROMOTE_MAX_PER_DAY` 20), `MODEL_DIR`,
  `HEALTH_PORT`.
- `services/home/prod/values.yaml` — `charts:`-key entry (variant (a), EXPLORE
  §2: no Chart.lock regen). **Proxy leg N/A by design**: headless worker, no
  UI, ClusterIP-only service, no ingress (documented precedent: dev mosquitto
  "the service trio's proxy leg is N/A by design, not an oversight"). **No
  `custom-values/` entry in this run** (Q1 verdict (a): the worker is
  anonymous against `home-mosquitto`).
- MQTT/HA leg — **verdict (a) confirmed (Q1)**: worker publishes to
  `home-mosquitto` (anonymous, ClusterIP 10.43.74.33:1883, no credentials);
  the re-point of HA's single `core-mosquitto` mqtt entry at it is an owner
  UI action (C05 owner leg L4; `supports_reconfigure: true`, no restarts).
  ClusterIP-reachability-from-HA-host stays a dev-time verification item.
  HA is single-broker (a second entry replaces the shared client) — the plan
  never ships a second entry or a bridge (R4 §2/§6). **Recorded fallback
  (c), deactivated for this run**: if the owner later rejects (a), the worker
  authenticates against the HAOS add-on broker (anonymous logins forbidden by
  the app — R4 §1) using its existing `MQTT_USERNAME/PASSWORD` code path
  (no code change) plus a zigbee2mqtt-shape ExternalSecret + a 1:1
  `custom-values/home` entry — no such plumbing is built or rendered in this
  run.
- Catalogue lifecycle (Q3, owner override 2026-11-24): bootstrap = capture →
  (recurrence → auto-promote | manual promote) → events; `ad_detected` fires
  only for `kind=ad` matches, so a brand-new catalogue emits no false events;
  candidate WAVs are 5512 Hz mono s16 (the worker's own resampled stream —
  `promote` decodes them directly, `promote --dir` for arbitrary formats uses
  `FFmpegAudioService`, the R1 §4 canonical insert shape); R1 §2's
  pre-seeded-catalogue design evidence (TVEyes) stays the design anchor:
  auto-promotion is recurrence-gated and human-auditable
  (`auto_promoted` flag + `list`/`prune` audit), the per-day cap bounds
  drift-feeding, and the manual lane covers single-shot curation.

## Out of scope
- HA dashboard UI (follow-up per card text + Q8 — see Deferred asks)
- HA automations beyond event exposure (event-only now — Q7 answered as
  planned; automations (mute clients / stream switching) are a follow-up;
  `event.received` is the HA-side trigger)
- snapserver 0.28.0 → 0.35.0 upgrade (first-boot group assignment works
  without it: config-order + `Group.SetStream` at startup — R2 §5)
- vendoring PR #1571 (watchdog-only default — Q5 answered as planned; revisit
  when it merges)
- Emy CE second-container lane (documented upgrade path, not this ticket —
  R1 §4; if ever taken: same-major pairing SF 18.0.0 ↔ Emy 18.0.3-community)
- auto-creation of follow-up cards (stage unchecked on this card — Q8)

## Deferred asks (for the final summary — coord carries to the owner)
- HA dashboard UI: a **follow-up card is wanted after this feature lands**
  (Q8). This run creates no cards (Follow-up cards stage unchecked); the
  coordinator's final report carries this ask to the owner.

## Commands
- test: `export PATH=$HOME/.local/bin:$PATH && bash tests/containers/audio-ad-detection.sh`
  (static contract + hadolint; repo norm for containers — no docker daemon in
  agent sessions; the script is written up-front by agent-test with sections
  for C01, C02a, C02b, C03, C04, C05)
- lint: `export PATH=$HOME/.local/bin:$PATH && helm lint charts/audio-ad-detection`
- template: `export PATH=$HOME/.local/bin:$PATH && helm template charts/audio-ad-detection`
  (no `OVERRIDE_*` sentinels in the render; no ExternalSecret / no creds;
  `SNAP_STREAM_ID: TBD-owner` placeholder present)
- smoke: `docker build containers/audio-ad-detection => no-daemon, CI-deferred`
  (designed passing gate shape, cf-77) + build-critical facts captured from the
  pinned base images' GHCR layer tar-listings / manifest digests
- integration: `grep -n "audio-ad-detection" services/home/prod/values.yaml`
  (the `charts:` entry present; the N/A proxy leg is documented in this plan)
- custom-values 1:1 `OVERRIDE_VIA_CUSTOM_VALUES` check: **not applicable in
  this run** (verdict (a) confirmed, Q1); it becomes required only if the
  recorded fallback (c) is later enabled
- snapclient `.deb` lib-compat (bookworm deb on noble): static facts (deb
  control stanza, `ldd` needs vs the noble runtime package set) +
  `snapclient --version` + a 10 s stdout capture = a dev-chunk verification
  item (the full runtime smoke rides the first CI build / first pod start;
  report honestly in `commands_run`)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Container + worker skeleton (Dockerfile, audio acquisition, watchdog, health/metrics, startup stream assignment) | M | 1 | [] | — |
| C02a | Fingerprint engine (resample → chunk → realtime query, Snapshot, RMS + last-match tracking, metrics) | M | 2 | [C01] | consumes C01's pipe interface (hot source) + config surface |
| C02b | Auto-capture + curator (candidate capture with roll buffers, promote/list/prune, retention, never-auto-promote) | M | 2 | [C02a] | consumes C02a's engine (no-match state, RMS, model service, snapshot) — intra-wave order |
| C03 | MQTT publisher + shutdown ordering + Snapshot on exit | M | 2 | [C01] | consumes C01's health/readyz surface; C02a's event sink is interface-first, C03 the consumer |
| C04 | Chart + home service wiring | M | 2 | [C01] | consumes C01's env names / ports / PVC path (the config contract) |
| C05 | Integration verification + tuning (live smoke, discovery, capture + promote, thresholds) | S | 3 | [C02a, C02b, C03, C04] | needs the full worker + chart + wiring to exist |
| C06 | Chart idiom conformance rework (test-arm fixes t27/t28 by the test session first, then values under `app-template:` nesting, hand-written PVC, D-8 pod-only, nameOverride) | M | 4 | [C04] | replaces the C04-delivered hybrid chart (C04 done; rework against the 62351fa17 baseline per the owner finding) |
| C07 | Skill codification (D-8 section + anti-hybrid guardrail + qualified `--set` gotcha + precedence rule in `skills/helm-chart-creation`) | S | 4 | [C06] | cites the post-C06 idiom tree as the in-repo exemplar; must land after the conformance shape exists |
| C08 | Forge-build compile fixes (the 10-error class sweep + volatile-DateTime/StopAsync/using/default-arg fixes + local dotnet attempt) + chart image switch to the instance registry | M | 5 | [C07] | the sweep must run on the post-C15 rebased tree (step 0) so the class sweep covers the exact source the next CI compile sees; the registry switch cites the post-rebase sibling cite |
| C09 | Detection hardening (build-charts `workflow_call` arm before the empty-before die + bootstrap no-marker full-set on both detect surfaces) + C05 runbook L1 reword for the post-C15 fan | M | 5 | [C08] | C09's runbook reword names the post-C08 registry pull story and the post-C15 file names that only exist after C08's step-0 rebase |
| C10 | Dockerfile fetch-leg fix (runtime-image tool assumption: `wget` absent from `dotnet/runtime:10.0`) + existence-proof AC + container-creation skill guardrail | M | 6 | [C09] | continues the deploy-incident chapter (C08 was the compile round; C10 is the runtime-image round) — the fix must land on the C08/C09-closed tree (registry + detection fixes in) so the owner's next re-dispatch exercises the whole stage-1 at once |

## Wave order
1. C01
2. C02a, then C02b (intra-wave: C02b consumes C02a's engine); C03, C04
   mutually independent of the C02a/C02b line (run in id order)
3. C05
4. C06, then C07 (intra-wave: C07 codifies the idiom shape C06 delivers)
5. C08, then C09 (intra-wave: C09's runbook reword and post-C15 workflow
   edits stand on C08's step-0 rebase and registry switch)
6. C10 (standalone — the runtime-image fetch-leg round; the CI build is
   again the authoritative proof, the layer-existence proof minimizes the
   surface)

## Risks / assumptions
- **SF 18.0.0 maturity (Q4)**: shipped 2026-11-20 (a week old at plan time);
  R1 source-verified the realtime contract + Snapshot directory form at
  **17.4.0**, not 18.0.0 — the plan assumes the same contract (18.0.0's
  library stays netstandard2.0; the 16.0.0 async contract is the shared
  baseline, R1 §1). This is a flagged research gap, not a silent guess:
  **Post Research verifies the 18.0.0 realtime-contract parity**; the recorded
  fallback pin is **17.4.x** (same API-surface family) — a one-line pin swap
  in the csproj if Post Research finds an 18.0.0 blocker.
- snapclient 0.35.0 bookworm `.deb` on the noble runtime: glibc compatibility
  unverifiable offline (no docker daemon) — the dev-chunk static check is the
  gate, the first CI build is authoritative; fallback is the in-repo cmake
  builder precedent (R2 §4).
- The first cold forge build (sdk:10.0 pull ≈250 MB+) risks the 30-min ceiling
  (R3 §5); the warm layer cache makes later builds fast.
- First image pin `:main` + `pullPolicy: Always` + pin-me comment (no calendar
  tag yet — EXPLORE §7.2); Renovate bumps to `:yy.mm.N` after the first prod
  build.
- Verdict (a) hinges on the HA host reaching `home-mosquitto`'s ClusterIP
  10.43.74.33:1883 (owner-side fact; k3s kube-proxy programs the node's own
  netfilter — R4 §1). Dev-time/owner verification item (C05 leg L4), not a
  blocker; the recorded fallback (c) is the escape hatch.
- `InMemoryModelService` "intended for testing purposes" caveat carried
  consciously; at O(100)–O(1,000) tracks both lanes fit RAM trivially (R1 §3) —
  Emy CE is the documented upgrade path.
- **Bootstrap period**: the catalogue starts empty — non-matching spans
  produce *candidate files*; a candidate **auto-promotes on recurrence**
  (guardrail defaults 2 sightings / 24 h gap / 20 per day — bounded,
  auditable) or via the manual `promote` lane; `ad_detected` fires only for
  `kind=ad` matches (auto- or manually promoted). Capture/retention/auto-
  promotion defaults (30 s / 300 s / −45 dBFS / 14 days / 200 files / 10Gi
  PVC; 2 sightings / 24 h / 20 per day) are plan-owned best guesses recorded
  in Open question 3.
- **Auto-promotion drift (owner override)**: a genuinely repeating non-ad
  (e.g. a program jingle, a station ident) can be auto-promoted — bounded by
  the per-day cap (20), fingerprint-proximity dedup, and the
  `auto_promoted` flag + `list`/`prune` audit surface; a Post Research thread
  is checking recurrence-promotion precedent — if its findings warrant
  threshold tweaks, that is a **value-only change** (the guardrails are env
  config, no code path change).
- Deployed snapserver is 0.28.0 (no `default_source`): group assignment =
  config-order + startup `Group.SetStream` once `SNAP_STREAM_ID` holds the
  owner's group name (R2 §5); no snapserver config churn (client-side tap
  verdict, R2 §5).
- .NET 10 SDK may be absent from agent sessions: .NET compile checks are
  CI-primary; a local `dotnet publish` is a bonus, not the gate (honest
  `=> unavailable, CI-deferred` shape).

## Open questions (batched round of 2026-11-24 — answers consumed; residual items below)
1. **Broker verdict — ANSWERED (a).** HA re-points its single mqtt entry at
   `home-mosquitto` (owner UI action, C05 leg L4); verdict (c) deactivated
   (no custom-values entry, no ExternalSecret, no creds in this run; recorded
   as a one-paragraph fallback above). Residual: ClusterIP-reachability-from-
   HA-host — dev-time/owner verification (C05 leg L4), not a blocker.
2. **Stream to tap — ANSWERED: family-TV group; name not yet supplied.**
   `SNAP_STREAM_ID` is a required chart value with the documented placeholder
   `TBD-owner`; startup `Group.SetStream` reads it (config-order + logged
   marker until then — no blocker on C01–C04). Name supply = C05 owner leg
   L2.5.
3. **Seeding source — ANSWERED: auto-capture from the stream; OWNER OVERRIDE
   2026-11-24: promotion is AUTO-PROMOTE ON RECURRENCE (supersedes the
   never-auto-promote posture recorded in the first rework; manual `promote`
   lane stays). Designed in as C02b.** Derived sub-decisions (best-guesses
   with impact — **not re-asked**):
   - `CAPTURE_MIN_SPAN_SECONDS` 30 — a non-match shorter than a standard 30 s
     spot is match jitter / gap noise; longer is capture-eligible (R1 §2
     spot lengths; the 120 s `NewOccurrenceAbove` ceiling is a seam control,
     not a span threshold).
   - `CAPTURE_MAX_SPAN_SECONDS` 300 — a non-match beyond 5 min is an
     off-air / program boundary, not a spot; the span is cut at the cap.
   - Pre/post roll 5 s each — covers the <1.5 s `MatchedAt` edge jitter (R1 §1)
     with margin; the ring buffer holds 10 s + margin of resampled mono audio.
   - `CAPTURE_RMS_FLOOR_DB` −45 — TV-off / source-off silence is far below;
     a real ad (or even program audio) is far above. RMS is exported as a
     metric; liveness is never on non-silence (R4 §3/§5 rule).
   - Retention: `CAPTURE_RETENTION_DAYS` 14, max 200 candidates (whichever
     trips first; oldest pruned on startup + periodically) — keeps the
     candidate dir bounded inside the 10Gi PVC (model + ≤2 Gi candidates).
   - **Auto-promotion guardrails (the owner override)**:
     `AUTO_PROMOTE_MIN_SIGHTINGS` 2 distinct recurrences — repetition is the
     ad signal (R1's `NewOccurrenceAbove` recurrence evidence; a single
     sighting never promotes, so one-off program audio is never promoted);
     `AUTO_PROMOTE_MIN_GAP_HOURS` 24 — qualifying sightings must be ≥24 h
     apart (cross-episode/cross-pod repetition, not back-to-back re-runs);
     fingerprint-proximity dedup before insert (vs the existing catalogue and
     previously promoted candidates — one entry per distinct ad, not one per
     re-airing); `AUTO_PROMOTE_MAX_PER_DAY` 20 — bounds drift-feeding (a
     genuinely repeating non-ad is a bounded, auditable exception);
     `auto_promoted: true` metadata flag + `list`/`prune` audit surface keep
     the human in the loop after the fact. All guardrails are env config —
     a Post Research threshold tweak is a value-only change.
4. **SF pin — ANSWERED 18.0.0.** R1 source-verified 17.4.0 specifics (incl.
   the Snapshot directory form); 18.0.0 realtime-contract parity is the
   **Post Research** verification focus (not re-verified here); recorded
   fallback pin 17.4.x (same API-surface family) if Post Research finds a
   blocker. Same-major pairing for the upgrade lane: SF 18.0.0 ↔ Emy
   18.0.3-community.
5. **#1563 mitigation — ANSWERED: watchdog-only** (as planned; revisit when
   PR #1571 merges).
6. **Resample boundary — ANSWERED: snapclient-side `5512:16:*`** (as planned;
   `WdlResampler` Sinc64 active only if raw 48k is ever chosen).
7. **HA automations — ANSWERED: event-only now** (as planned; automations are
   a follow-up).
8. **Dashboard — ANSWERED: follow-up card wanted AFTER this lands**; this run
   creates no cards (Follow-up cards stage unchecked) — recorded in the
   Deferred asks section; the coord's final report carries it to the owner.

## Open questions — rework round 2026-11-26 (batched; only genuine items)
9. **Idiom defaults — confirm the two scout recommendations** (both resolve to
   the sibling idiom; **recommended: yes to both**). (a) **Drop the D-8
   controller copy** (pod-only annotations; the `controllers.main.annotations`
   mirror is scraping-inert — k8s-monitoring v4 `annotationAutodiscovery`
   runs pod+service roles only; vllm/radiance carry the pair pod-only).
   (b) **Hand-written PVC** (`app-template.persistence.models:
   {existingClaim: audio-ad-detection}` + `templates/
   pvc-audio-ad-detection-default.yaml`, the 44-chart idiom, qdrant
   exemplar) instead of the library PVC render (`type:
   persistentVolumeClaim` + `size:` — 1/75). Plan-owned defaults wired into
   C06's ACs pending this confirmation.
10. **Commit shape** — fix commit on `cf-133-feat-audio-ad-detection` vs
    amend of 62351fa17 (unpushed → both clean; **recommended: the fix
    commit**, for the audit trail — the rework is a distinct owner-ruling
    event; 2026-11-25 posture: the coordinator is the sole committer, local
    commit, no push).

## Post Research scope (round runs after planning, per the card's Lifecycle timing — thread already in flight)
- **Recurrence-promotion precedent check** (in flight) — prior art for
  auto-promote-on-recurrence in audio-fingerprinting deployments; if the
  findings warrant threshold tweaks, those land as **value-only config
  changes** (the guardrails are env config in C02b)
- Verify the SF **18.0.0 realtime-contract parity** (chunk contract,
  `BlockingRealtimeCollection`, Task-returning callbacks, `NewOccurrenceAbove`,
  `InMemoryModelService.Snapshot` directory form) against 18.0.0 sources /
  release notes — R1's verification was at 17.4.0. Outcome: confirm 18.0.0 or
  flip the pin to the recorded 17.4.x fallback (one-line change).
- PR #1571 merge-status check (watchdog-only revisit trigger; in flight).
- No other deep research needed (R1–R4 cover the plan surface); the live
  verification items (snapclient on noble, `Server.GetRPCVersion` on 0.28.0,
  HA reachability, first forge build) ride C05's owner/dev legs, not research.

## Rework R1 (2026-11-26): chart idiom conformance

Owner finding (2026-11-26, final-review review): the C04 chart shipped in the
**hybrid shape** — parent-side `templates/common.yaml` loader + top-level
app-template library keys + D-8 double copy + library PVC render with the
self-describing `aad.io/size` label — and the owner **rejected** it: it is
1/75 charts. Authority for the rework: the chart-idiom re-exploration
(EXPLORE.md section "Chart idiom re-exploration (2026-11-26, owner review
finding)" — a 75-chart taxonomy + scratch renders, release name
`home-audio-ad-detection`). The owner's ruling inverts the conformance
direction: **the chart conforms to the repo idiom; the test arms that
encoded the hybrid get fixed**. This supersedes the C04 round-1 review's
"test-forced" acceptance (adjudications 1–3, MINOR-1) and the
`test-forced` ruling recorded in DECISIONS — see the 2026-11-26 human
entry. The third-party hash-pinned `helm-bjw-s-chart` skill is the mislead
source (its documented canonical shape is the standalone-`common`-dep +
parent-loader variant); it is provenance-locked and is NOT edited — the
codification lands in `skills/helm-chart-creation` (C07).

**Revised chart architecture** (replaces the chart's structural description
above; the functional surface — probes, env, security, service — is carried
verbatim):
- `charts/audio-ad-detection/` in the **majority idiom (55/55 app-template
  siblings)**: Chart.yaml dep stanza in the sibling spelling (`app-template`
  `5.0.1` from `https://bjw-s-labs.github.io/helm-charts/`, **no
  `catalogVersion`** — the stanza is already byte-identical to the
  siblings; C06 verifies against `charts/vllm/Chart.yaml:5-8` when writing),
  committed `Chart.lock` (digest `sha256:0ea7893a5c4e…` stable — the dep
  spec is unchanged), **all workload config nested under `app-template:`**,
  **`templates/common.yaml` deleted** (the single dep bundles the common
  chart internally; the workload renders from the `app-template:` values
  with no parent-side loader and no second dep — the
  `charts/vllm/Chart.yaml:5-8` idiom comment), secret-free root keys =
  `domain: OVERRIDE_VIA_APPSET` + `app-template:` only.
  - `app-template.global.nameOverride: audio-ad-detection` (the sibling
    norm — mosquitto/qdrant/vllm/radiance all set it to the chart name;
    required for `app.kubernetes.io/name` + the autodiscovery job name to
    stay identical to the current render) + `createDefaultServiceAccount:
    false`
  - `app-template.defaultPodOptions`: the 65532 pod securityContext
    (runAsUser/runAsGroup/fsGroup + runAsNonRoot) + the D-8 pair
    **pod-only** — the `controllers.main.annotations` mirror is **dropped**
    (vllm/radiance idiom; the mirror is scraping-inert — plan-owned default
    pending owner confirmation, rework OQ9a) — with the gate
    `app-template.monitoring: {annotations: true}` **nested in the same
    subtree** (the gate must live in the same values context as the map it
    gates — the radiance `values.yaml:243-250` comment)
  - `app-template.controllers.main` (strategy `Recreate`, 1 replica, the
    M1-verified probe windows — startup 30×10 s `/readyz`, liveness 12×10 s
    `/healthz`, readiness 3×10 s `/readyz`), `app-template.service.main`
    (ClusterIP, `health` 8080), `app-template.persistence.tmp/home`
    (emptyDir) — verbatim under the nested block; the `SNAP_STREAM_ID:
    "TBD-owner"` env line + its required-value comment (within 3 lines —
    t29's proximity pin) carried verbatim
  - PVC: **hand-written `templates/pvc-audio-ad-detection-default.yaml`**
    (static `name: audio-ad-detection`, `namespace: default`, RWO,
    `storage: 10Gi` — the 44-chart idiom, qdrant exemplar; plan-owned
    default pending owner confirmation, rework OQ9b) +
    `app-template.persistence.models: {existingClaim: audio-ad-detection,
    globalMounts: [{path: /models}]}`; the library PVC render + the
    `aad.io/size` label **disappear**
  - the `common:` / `rbac: {}` stubs and the inert `app-template:`
    stub-as-stub **disappear** (load-bearing only for the parent loader);
    `templates/NOTES.txt` reworded for the static PVC name
- `services/home/prod/values.yaml` wiring is **unchanged** — the appset
  consumption is chart-shape-agnostic (EXPLORE §3: the chart's own
  `values.yaml` carries the `app-template:` block; no appset change).

**Render-equivalence goal**: the reworked chart renders the same workload as
the committed baseline (62351fa17, release name `home-audio-ad-detection`) —
the scout's checklist (EXPLORE §4, scratch-verified) is the contract,
checked in C06 as an explicit AC against the baseline render: equal object
count/kinds/names, D-8 pod copy, gate-off shape, `SNAP_STREAM_ID` line,
pod/container security, `Recreate`/1 replica, PVC 10Gi RWO at `/models`,
emptyDir mounts, ClusterIP service, probe windows, 0 ServiceAccount,
`app.kubernetes.io/name: audio-ad-detection` (requires the nameOverride).
**Documented divergences** (the scout's list): the PVC object name (static
`audio-ad-detection` — sibling norm), the dropped D-8 controller copy,
`helm.sh/chart: app-template-5.0.1`, absent `app.kubernetes.io/version`,
boolean fields rendering `false` — all sibling shape (mosquitto
render-verified); the only functionally meaningful delta is the PVC name.

**Test-arm alignment** (executed FIRST inside C06, by the **test session** —
the coord routes it; dev never edits tests): only **t27** (top-level
`--set monitoring.annotations=false` → qualified `--set
app-template.monitoring.annotations=false`; the double-quote-only value
regexes widened to quote-tolerant `['\"]?true['\"]?` /
`['\"]?8080['\"]?` / gate-off `['\"]{2}`) and **t28** (`size: 10Gi` label
carrier → `storage: 10Gi` spec field, quote-tolerant grep) encode the
hybrid; the scout maps t25/t26/t29/t30/t31 as shape-agnostic, **unchanged**
— t31's ruled defaults pin no chart internals (verified in the mapping), so
t31 stands intact.

**Updated Commands** (delta on the plan's Commands section): the same suite
+ the gate-off helm arm now runs the qualified form —
`export PATH=$HOME/.local/bin:$PATH && helm template charts/
audio-ad-detection --set app-template.monitoring.annotations=false` (a
top-level `--set` cannot reach subchart values; the repo test convention is
the qualified `app-template.<path>` — `tests/services/
dev-forgejo-runner.sh:828-830`); t28's PVC arm greps `storage: 10Gi`.

## Rework R2 (2026-11-26): deployment-incident replan

**The incident** (2026-11-26 ~18:35Z): the owner ran the `workflow_dispatch`
hatch on merged main (the branch had been merged by the owner; the build ran
there). `dotnet publish` **FAILED with 10 errors**, verbatim:
`ModelService.cs(62,12) CS0246 'IModelService'`;
`AdEventSink.cs(36,22)+(38,31) CS0246 'ILogger<>'`;
`SnapClientSupervisor.cs(245,29) + MqttPublisher.cs(132,35) CS0507 StopAsync:
cannot change access modifiers`; `MqttPublisher.cs(39,29) CS0246
'MqttQualityOfServiceLevel'`; `SnapClientSupervisor.cs(63,31)+(64,31) CS0677
volatile DateTime illegal` (two fields); `CandidateWriter.cs(21,72) CS1736
default parameter 'utcNow' not a compile-time constant`;
`MqttPublisher.cs(379,30) CS0246 'TrackData'`.

**The compiler-oracle lesson** (DECISIONS): no-SDK sessions structurally
cannot catch C# *rule* violations. The Post-Research/dev API-source sweeps
verified API shapes against tags but catch none of these ten — access
modifiers, `volatile` on a non-primitive, default-argument constancy, missing
usings are all compile-time rules the source-reading oracle is blind to. **CI
is the authoritative compile.** The mitigation, codified as an AC in C08: a
local `dotnet-install.sh` channel-10.0 attempt into `~/.dotnet` (network
precedent: MCR/NuGet reachable); on install failure the report is honest and
the fix rests on the class sweep + the next CI round.

**The owner's registry ruling** (2026-11-26): the chart's image must
reference the **Forgejo instance registry** (`git.spencerslab.com`, public per
the owner) instead of `ghcr.io/ownyourio/audio-ad-detection` (a private
namespace the home cluster cannot pull). The convention was verified, never
invented: `charts/forgejo-runner/values.yaml:149-153` (main) cites
`git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` — the shape is
`<host>/<lowercase-owner>/<lowercase-image>`. The dual publish is unchanged
(the workflow pushes both registries under the same three tags); the home
cluster pulls the public one. C08 switches
`charts/audio-ad-detection/values.yaml` to
`git.spencerslab.com/curatedforest/audio-ad-detection`, keeps the
rolling-`:main` + `pullPolicy: Always` + PIN-ME story, and rewords the
adjacent comment (which still names the pre-C15 workflow) to the truth.

**The detection-hardening ruling** (owner, onto this ticket as C09) — the
**C15 asymmetry**: post-C15 (`build-containers.yaml` / `build-charts.yaml`,
the cf-55 r5 renames — the branch is pre-C15 and never touched the workflow
files, verified) the `main-sync.yaml` prod-main fan *calls* both builders
(push arm retired; PR + dispatch lanes byte-frozen) and seals the shared
`ci/last-built` marker (`advance-marker`, D54 single writer, `needs:` is the
aggregate gate). The `build-containers` detect script special-cases
`workflow_call` (an empty `before` is **EXPECTED** — a called run carries no
push payload; the die stays scoped to real pushes), but the `build-charts`
detect body still **dies on an empty `before` with no marker** — every
no-marker called run of build-charts is a dead run. And the **bootstrap
tip-only**: a first called run with no marker diffs `HEAD^..HEAD` (announced)
— directories introduced below a burst tip are invisible, both builders go
green, the marker seals at the tip, and the missed directories are never
built. **Chosen fix** (C09): on a no-marker first called run, a **wider-base
diff — the full set** (empty-tree base, announced) on *both* detect surfaces,
plus the build-charts `workflow_call` arm before the die. **Rejected fix
(documented)**: refusing to advance the marker on a multi-commit push — it
does not resolve the skip (the next no-marker called run is still tip-only;
deferral is not coverage), it defeats the marker's re-cover property
(C14/D53), and it cascades into the main-sync D54 single-writer job and its
test (cf-55 territory, outside this ticket).

**Runbook truth (C09)**: the C05 owner-leg runbook L1 describes the pre-C15
push-triggered `containers-build.yaml` run; post-C15 the push arm is
retired, `main-sync.yaml` calls the workflows, and the `workflow_dispatch`
hatch is the manual rebuild lane (the incident build was exactly that hatch).
L1 is reworded to the post-C15 fan + the post-C08 registry pull story;
historical records (EXPLORE/RESEARCH) keep the pre-C15 names — they are dated
scout records.

**Wave-5 topology**: C08 (compile fixes + registry switch) depends on C07
(the tree is complete and reviewed; the sweep runs on the rebased tree); C09
(depends on C08 — its reword cites the post-C08 pull story and its workflow
edits stand on the post-C15 names C08's step-0 rebase brings in). **Step 0
(rebase, C08 precondition)**: the branch is NOT an ancestor of `origin/main`
—the owner re-committed the three ticket commits as `6cad3667c` /
`a04a95860` / `889cd1329` — and post-fork main carries the C15 renames + the
`0ce0d4d8f` release bump (which touches our `Chart.yaml` — the branch lands
on main's version; no hand-bump). The branch never touched `.forgejo/` or
`scripts/` (verified), so the rebase takes main's post-C15 workflow shape
with no conflict; the suite re-verifies 31/31 after.

**t-sequence**: C08/C09 add **no new t-numbers**. Verified 2026-11-26: the
whole `tests/containers/audio-ad-detection.sh` (t1–t31) greps **no**
`ghcr`/`ownyourio`/`repository:` and none of the C08 source tokens
(`volatile`/`StopAsync`/`protected`/`using`); t25 (default render
sentinel/credential-free) and t26 (Recreate + replica + probes) pin render
shape only. No mod-in-place was needed; the gate stays 31/31.

**Open questions**: none new — OQ9 (idiom defaults: drop the D-8 controller
copy; hand-written PVC) and OQ10 (fix commit vs amend of the relocated
commit; fix commit recommended) stand for the coord's batched round;
`SNAP_STREAM_ID` stays TBD-owner (L2.5 owner leg). No user questions this
round — the C08/C09 scope is fully determined.

## Rework R3 (2026-11-27): the runtime-image fetch-leg incident

**Incident 2** (owner's `workflow_dispatch` log, 2026-11-27): the C08
compile fixes are **PROVEN ON CI** — build stage `[build 6/6] dotnet
publish DONE`, the dll + `/app/publish` emitted. The failure **moved to the
RUNTIME stage** `[stage-1 4/6]`, Dockerfile line 24:
`wget -q "https://github.com/snapcast/snapcast/releases/download/
v${SNAPCAST_VERSION}/snapclient_${SNAPCAST_VERSION}-1_amd64_bookworm.deb"
&& apt-get update && apt-get install ...` → `/bin/sh: 1: wget: not found`,
exit 127. `mcr.microsoft.com/dotnet/runtime:10.0` is a lean noble base
**without `wget`** — and, verified this round by MCR layer listings,
**without `curl` either**. **CLASS: runtime-image tool assumption** — the
last untested assumption class in the Dockerfile (the other legs are
proven: `apt-get`/`dpkg` via layer listing, `groupadd`/`useradd`/`chown`
present, `dotnet` present; the CI log only proved the WORKDIR/COPY legs ran
before the fetch died, so the apt legs were layer-proofed, not log-proofed).

**The lesson (DECISIONS):** every `RUN`-referenced binary in a final-stage
Dockerfile needs **existence-proof against the base image's actual layer
contents** — or a **zero-binary mechanism**. C01's capture recorded the 5
layers but not the tool inventory; the compile round proved the build
stage but left the runtime stage's fetch leg untested. CI is again the
authoritative proof (the owner's post-merge re-dispatch exercises the apt
legs for real; further base-image surprises remain possible) — the
layer-existence proof (C10 T2) is what minimizes the surface.

**Verified ground truth (planner, 2026-11-27):**
- `runtime:10.0` amd64 (tag → 10.0.15; 5 layers, manifest
  `sha256:f4ee1b92…`): `wget` **absent** (the incident), `curl` **absent**
  (the owner's suspicion, confirmed), `sh`/`apt-get`/`dpkg`/`groupadd`/
  `useradd`/`chown`/`dotnet` all present (full table in the C10 chunk).
- `sdk:10.0` amd64: layers 0–4 byte-identical to the runtime's; SDK tool
  layers add **both** `/usr/bin/wget` and `/usr/bin/curl` (candidate (b)
  is mechanically viable).
- The deb is **byte-exact** re-verified this round: size 591,928, sha256
  `b71575bcc2b4541f5004c73a0a1f43374e852bf5d5f2162aa1b230f3c209d9f3`.
- **Sibling idioms:** `containers/okd-enketo/Dockerfile:21-22` uses
  `ADD <url>` (BuildKit-native, zero-binary — built on this same forge
  workflow: the precedent); `containers/forgejo-runner/Dockerfile:49-50`
  bakes tools via **digest-pinned** `COPY --from` tool images (the repo
  tool idiom); `forgejo-host-runner` uses `curl` on a curl-bearing base;
  `music-assistant` uses `wget` on a wget-bearing custom base.
- **Candidate weighing** (dev decides on the evidence; the planner's lean is
  (a)): (a) `ADD <url> /tmp/snapclient.deb` — zero-binary, repo precedent,
  no new image dependency, no new renovate surface (the comment-above-ARG
  pin is the repo's canonical custom-manager pattern — untouched), the t3
  shape preserved exactly, hadolint `DL3020` is warning-level (t9 runs at
  the error threshold); cost: the 592 KB deb persists as a layer (plain
  `docker build`, no squash) — trivial at this image size. (b) stage the
  fetch in the build stage (has wget/curl, verified) — final image clean,
  but a runtime OS asset in the SDK stage + egress coupling to the publish
  cache + a larger diff. (c) apt-install curl then purge — defeats
  zero-binary (purged files persist), and separate apt legs are a named
  antipattern in the container-creation skill. (d)
  `COPY --from=ghcr.io/curlimages/curl:8.14.1 --link` — a new tag-pinned
  FROM (off-idiom: forgejo-runner pins digests) = a new renovate-tracked
  surface, more machinery than (a).
- **Test alignment (verified):** t3 pins the version-stable **URL string**
  (`grep -qF` over the flattened file) + `apt-get install -y
  --no-install-recommends.*\.deb` + the same-RUN apt cleanup — and does
  **NOT** pin the literal `wget`. t4's `groupadd`/`useradd --uid 65532`
  pins are base-present. t1/t2 (pinned FROMs, no `:latest`) are untouched
  by the fix. **No test change, no new t-numbers, no test-session step.**

**Wave-6 topology:** C10 (M, depends C09) — standalone; it continues the
deploy-incident chapter (C08 = the compile round, C10 = the runtime-image
round) and must land on the C08/C09-closed tree so the owner's next
re-dispatch exercises the whole stage-1 at once. **Commit shape:** another
fix-commit on the `bcc55ebdf` chain (the OQ10 fix-commit pattern,
confirmed). **Open questions:** none new — OQ9/OQ10 confirmed at close;
`SNAP_STREAM_ID` stays TBD-owner; no user questions this round (scope
fully determined).
