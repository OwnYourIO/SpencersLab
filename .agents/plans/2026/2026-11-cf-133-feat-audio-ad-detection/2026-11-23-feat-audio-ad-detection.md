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

## Wave order
1. C01
2. C02a, then C02b (intra-wave: C02b consumes C02a's engine); C03, C04
   mutually independent of the C02a/C02b line (run in id order)
3. C05
4. C06, then C07 (intra-wave: C07 codifies the idiom shape C06 delivers)

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
