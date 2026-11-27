# RESEARCH — cf-133 Audio Ad Detection

## R1 — SoundFingerprinting realtime pipeline + storage

Grounded 2026-11-23 (Pre Research, thread R1). Method: live web research (SearXNG + direct fetch of
NuGet/GitHub/Docker-Hub APIs, the project wiki, raw sources at v17.4.0/master, emysound.com +
readme.io docs). All version facts verified against primary sources the day of research; the
maintainer's release notes (NuGet) are the canonical changelog (GitHub release bodies are empty).

### TL;DR

- 17.x is current-but-one: SF **18.0.0 shipped 2026-11-20** (3 days old; tests on .NET 11, library
  stays netstandard2.0) [1][5]. The 17.x line ends at **17.4.0** (2026-11-10); the 16.0.0 async
  storage contract (2026-10-18) is the breaking baseline the card targets [1][6].
- Realtime contract confirmed: `BuildRealtimeQueryCommand().From(IAsyncEnumerable<AudioSamples>)`
  with **exactly 10,240-sample mono float chunks at 5512 Hz (1.857 s)**, `BlockingRealtimeCollection`
  adapter, `IRealtimeQueryCommand.Query(token)`, Task-returning callbacks awaited before the next
  chunk, `OngoingEntryStalenessCeiling`, and **`SeamJumpPolicy.NewOccurrenceAbove(120)` is exactly
  the documented ad-spot-in-repeating-program control** (the wiki's worked example is an ad pod) [1][10][11][12][18].
- The intake claim "snapshot/serialisation API unverified" is **refuted**: `InMemoryModelService.Snapshot(dir)`
  + `new InMemoryModelService(dir)` exist **in v17.4.0** (source-verified) and are integration-tested;
  restart is a file load, not a re-fingerprint — rebuild cost is one-time seed cost [15][16][17].
- Storage lane for O(100)–O(1000) tracks: RAM is trivial either way (≈50 MB per audio-hour, FAQ:
  100 h ≈ 5 GB). **InMemoryModelService + Snapshot on a PVC is the simple single-container default**;
  **Emy CE** (server image `17.4.13-community` for the 17.x line, `18.0.3-community` current) buys a
  JSON-API/UI ingestion surface and the "hundreds of thousands of tracks in commodity RAM" headroom,
  at the cost of a second container + version-pairing. Emy CE is free for non-commercial use [1][9][22].
- "0.75 MiB/track" RAM rule and any published CPU-seconds-per-audio-hour figure: **no public source
  found** (searched NuGet notes, wiki, emysound.com, readme.io, Docker Hub, web) [26].

### 1. Realtime API contract (verified Nov 2026 state)

**Version landscape.** NuGet (fetched 2026-11-23): SF 18.0.0 (2026-11-20) > 17.4.0 (2026-11-10) >
17.1.1/17.1.0 (2026-11-02/10) > 17.0.0 (2026-10-31) > 16.2.0 (2026-10-29) > 16.0.7/16.0.1/16.0.0
(2026-10-18/20/21) [1][2][6]. 18.0.0: "Target .NET 11: the test project builds on net11.0 … the
library itself stays netstandard2.0" [1]. 17.0.0: "Pairs with SoundFingerprinting.Emy 17.x, which
binds FFmpeg 9.x; no code change" [1].

**The 16.0.0 async contract (confirmed, as the card states)** [1]:
- `IModelService`/`IQueryService` async-only (`InsertAsync`, `QueryEfficientlyAsync`,
  `ReadTracksByReferencesAsync`, `GetInfoAsync`, `UpdateTrackAsync`, `DeleteTrackAsync`,
  `ReadHashesByTrackIdAsync`, `ReadTrackByIdAsync`, `GetTrackIdsAsync`), all take
  `CancellationToken`, list results are `IReadOnlyList`.
- `IQueryCommand.Query()`/`Query(DateTime)` take an optional token; **`IRealtimeQueryCommand.Query(token)`**.
- **Realtime `SuccessCallback`, `DidNotPassFilterCallback` and `OngoingCallback` return `Task` and are
  awaited** — source-confirmed in `RealtimeQueryConfiguration`: "The realtime command awaits the
  returned task before it consumes the next query result, so a callback that performs I/O does not
  block a thread and does not run concurrently with itself" [18]. Every `await` is
  `ConfigureAwait(false)`; the realtime loop starts on the thread pool [1].
- `InMemoryModelService` "still computes synchronously and returns completed tasks" [1].
- 16.0.1/16.0.7 added `ModelServiceInfo.Sequence` (server-reported last-applied sequence, nullable;
  proto member 5) and renamed `InsertOutcome.Undecided → SnapshotStale` — a **server-side** snapshot
  consistency concept, distinct from the client file snapshot in §3 [1][20].

**Feeding the realtime query** (wiki edited 2026-10-15 + maintainer sample) [10][11]:
- `QueryCommandBuilder.Instance.BuildRealtimeQueryCommand().From(<source>).WithRealtimeQueryConfig(cfg => …).UsingServices(modelService [, mediaService]).Query(cancellationToken)`; runs until cancellation.
- `From` overloads: `IAsyncEnumerable<AudioSamples>`, `IAsyncEnumerable<string>` files (+`MediaType`), `IAsyncEnumerable<StreamingFile>` (path + capture time), `IAsyncEnumerable<AVTrack>`, `IAsyncEnumerable<AVHashes>`, and `(url, chunkLength, mediaType)` [10][19].
- **Chunk contract (confirmed):** "each chunk has to contain 10240 samples, at 5512Hz, meaning each sample has to be 1.857 seconds length" — `float[10240]` → `new AudioSamples(audioSamples, "", 5512)` → `producer.Add(chunk, token)`; "Since samples are captured in an event-driven way, an adapter class **BlockingRealtimeCollection** is provided to facilitate their consumption via IAsyncEnumerable" [10][11]. Wiki: "Make sure the audio samples adhere to the format required by the algorithm: mono audio, sampled at 5512 Hz" [10]. (Fingerprint granularity: 8192 samples = 1.48 s, 64-sample overlap [23].)
- **Hot-source requirement (confirmed):** "After a non-cancellation error the realtime query command re-enumerates the provided source and continues querying. Sources … have to be **hot** (i.e., emitting live data, resuming from where they left off when re-enumerated). A cold async enumerable that replays its elements from the beginning will produce duplicate queries after an error occurs" — documented on `IRealtimeSource` [19]; 15.9.0 release notes: "Realtime sources must be hot … documented on IRealtimeSource", and the aggregator "survives source re-enumeration after transient errors, preserving the buffered chunk tail" [1]. For a snapclient pipe this means the worker (R2's supervision) must be able to **resume the stream at the current position** on re-enumeration.
- 15.15.0 added a standalone `RealtimeFingerprintCommand` (`BuildRealtimeFingerprintCommand()`) — realtime hashing without a query, if the pipeline wants to separate hash generation from querying [1].

**Filters and ongoing control (17.x surface, from source + notes)** [1][18]:
- `ResultEntryFilter` (`IRealtimeResultEntryFilter`): `QueryMatchLengthFilter(lengthOfASuccessfulMatch)` [11], `TrackCoverageLengthEntryFilter(seconds, waitTillCompletion)` [10][18], `TrackRelativeCoverageEntryFilter(ratio, waitTillCompletion)` [18], `CompletedRealtimeMatchResultEntryFilter` (holds the entry until it can't continue — prevents a 3-min track partitioning into three 1-min entries) [18], `PassThroughRealtimeResultEntryFilter`, `NoPassRealtimeResultEntryFilter`, `ChainedRealtimeEntryFilter` (11.1.0) [1].
- `OngoingResultEntryFilter` + `OngoingCallback(string streamId, IEnumerable<AVResultEntry>)` — "what is playing right now" (stream id passed since 11.4.0) [1][18].
- `RealtimeQueryConfiguration.OngoingEntryStalenessCeiling` (added 15.7.0, default `double.MaxValue`): caps the longest non-matching stretch, in seconds, an ongoing entry may bridge while waiting for the track to resume; "With a capped ceiling such entries complete shortly after they stop extending" — the knob for promptly closing an ad-spot entry on a continuous stream [1].
- `IsFullMatch` on `ResultEntry` since 11.3.0 (duplicate vs partial) [1]. False-positive filtering exists at config level since 12.6.0; `TruePositivesFilter` since 12.8.0 [1].
- `ErrorCallback` + backoff policy + optional `IOfflineStorage`; error handling fixed in 15.9.0 (exceptions no longer reroute already-consumed hashes; `ErrorCallback` invoked after backoff registration) [1].

**`SeamJumpPolicy` — the ad-spot-in-continuous-program control (confirmed with worked example)** [1][12]:
- `Stitch` (default, historical): stitch whatever the jump — wrong when a stored track repeats its own audio.
- `SourceSkip`: source seeks (player); formerly `AutomaticSkipDetection = true` (now obsolete shorthand) [1][18].
- `NewOccurrenceAbove(seconds)`: "For a continuous source, such as a broadcast, matched against tracks that can repeat their own audio. A jump up to the ceiling is an edit or a glitch of the same playing and the match continues … A larger jump is another occurrence of the audio and the incoming chunk starts a new result entry" [12].
- **The wiki's worked example is an ad pod**: "A 28-minute paid program contains its 30, 60 and 120 second advertising spots several times. When one spot airs on its own, consecutive chunks of that airing match copies of the spot that are minutes apart inside the program. Under `Stitch` … a 35 second airing reported a track span of 1,495 seconds. Worse, a real airing of the program that reaches a repeated region can jump to a late copy … the default policy registered 217 seconds of 1,709." **120 s is "the value used by the broadcast monitoring agents"**; measured on a day of broadcast matches vs standard spots: track position ran ahead of stream by >10 s in 0.9% of matches, >60 s in 0.2% — all cut-down edits, all under 120 s [12].
- Companion candidate-selection rule (always active, 15.17.0): among candidates for one track, the aggregator prefers the one whose track advance matches the stream advance (smallest seam drift, ties by coverage) — "a real playing … keeps accumulating through repeated regions instead of hopping to a copy"; replay of the full program against itself: 1,708.5/1,709 s covered with both mechanisms vs 217 s default [1][12].
- Backwards jumps are never stitched (always a new entry) [12].

**`MatchedAt` accuracy history (from the release notes)** [1]:
- ≤15.7.x: realtime matches stamped **late by the chunk-overlap prefix** (~1.8 s with default configuration) because `Hashes.TimeOffset` was never applied when deriving absolute match time.
- 15.8.0: fixed — match time now `RelativeTo + TimeOffset + QueryMatchStartsAt`; producers cutting overlapping chunks must stamp `TimeOffset` with the negative overlap length (a non-zero producer-stamped offset is authoritative) — i.e., **our worker should feed non-overlapping 10,240-sample chunks** and let the library's internal prefix handle FFT continuity, or else stamp the offset [1].
- 15.9.0: fixed the inverse (stitched sequence numbers stamped *ahead* of match times by the overlap length; negative offsets now applied in signed arithmetic) [1].
- 15.13.0: `Hashes.MergeWith` applies the earlier operand's `TimeOffset` once — "folding realtime chunks no longer moves the window start back or stretches the duration" [1].
- Production evidence: TVEyes (see §2) reports match-start **accuracy kept under 1.5 s** [22].

### 2. Catalogue strategy for AD detection

- **The maintainer's own FAQ:** "Can I use SoundFingerprinting to detect ads in radio streams? **Yes. Actually this is the most frequent use-case where SoundFingerprinting was successfully used**" [1].
- **Dominant real-world design = pre-seeded ad catalog + stream monitoring + coverage threshold.** TVEyes (Emysound case study, fetched live): "Emysound helps TVEyes to identify **pre-inserted ads** on more than 1,500 TV stations … At peak times, TVEyes has more than **300,000 ads monitored in real-time** … 1.7 million [matches] every day with the match starting time accuracy kept under 1.5 seconds. The delay between the air time and match getting detected … no more than 2 minutes. … only those commercials that report **40% coverage** are emitted" [22]. Emy's marketing states the same at scale: 1.7M matches/day, 36,000 h audio fingerprinted daily, 500,000 tracks searched concurrently [7].
- **Emy also ships the reverse/self-discovery mode as a product feature:** "Emy discovers new ads on its own by spotting content that repeats across your monitored streams. Discovered ads are tagged automatically with advertiser and brand metadata using AI" [7] — the catalog builds itself from what airs. The Emy *client* historically carried the ad-detection building blocks: `AVStationQueryService` (sets `SeamJumpPolicy.NewOccurrenceAbove(AdLengthStrategy.StandardAdLengthCeiling)`), `IAdLengthStrategy` (standard vs long-form), `LongFormCoverageFloorEntryFilter`, `PodGapsDetectionStrategy` (measures airtime a match occupies on the stream via `QueryDiscreteCoverageLength`), `Advertisement.Transcript` (17.2.0) [4]. **In 17.4.0 these client-side realtime query/match-selection types were removed** — "a recorder publishes hashes with `AVStreamingPublishService`" — i.e., ad detection moved server-side in the newest client; for 17.4.0/18.0.0 the client-side building blocks are the plain `RealtimeQueryConfiguration` settings in §1 (same mechanisms, no wrapper) [4].
- **The "fingerprint known program, non-match = ad" inverse approach is not a documented pattern for this library.** It is a positive-matching engine: "no ad" is the *absence* of a result entry, not an emitted event; building on it means the worker maintains its own matched/unmatched timeline from the ongoing/success callbacks. No public project using the inverse approach with this library was found (GitHub ecosystem scan: 17 repos referencing it, none a radio-ad detector [26]). The Seam wiki's example shows the *failure mode* of the complementary approach (cataloguing whole programs containing repeated spots) and `NewOccurrenceAbove` as the fix — i.e., whole-program cataloguing is supported with the right policy, but **cataloguing the spots themselves is the cleaner design** (the 35 s airing vs 1,495 s span example is the concrete cost of not doing so) [12].
- Practical shape for this ticket (input for the plan): pre-seed an **ad-spot catalog** (O(100) 30–60 s spots, optional O(1000) program entries); run `RealtimeQueryCommand` over the snapcast stream; emit ad events on `SuccessCallback` entries whose track meta says "ad" (or on any entry, with the ongoing filter for "what's playing"); use `NewOccurrenceAbove(120)` if program tracks are in the catalog; a `QueryMatchLengthFilter`/`TrackCoverageLengthEntryFilter` of ~5 s or a 40%-of-track relative coverage threshold mirrors the TVEyes emission bar [11][12][18][22].

### 3. Storage decision evidence

**InMemoryModelService (the 17.x bundled lane)** [1][14][15][16][17]:
- Class remark: "intended to be used for testing purposes only. Every operation computes synchronously … returns a completed task" [15] — a scope caution, not a functional limit.
- **Snapshot/serialisation API — VERIFIED in 17.x (refutes the intake "unverified"):** source at tag `v17.4.0` shows `public void Snapshot(string path)` (writes the store to a *directory*) and `public InMemoryModelService(string loadFrom, …)` (loads a previously stored instance from a directory; "Previous to v8, path parameter was path to a file. Since v8 it has to be path to a directory") [16][15]. Integration-tested: insert → `Snapshot(tempDir)` → `new InMemoryModelService(tempDir)` → query round-trips with `Confidence > 0.9`, and the next-id sequence continues across snapshot [17].
- Distinct from the *server-side* "snapshot sequence" (`ModelServiceInfo.Sequence`, `InsertOutcome.SnapshotStale`, 16.0.1/16.0.7) [1][20] — do not conflate in the plan.
- **RAM sizing (official FAQ):** "100 hours of content with `DefaultFingerprintingConfiguration` will consume ~5GB of RAM" [1] → ≈50 MB per audio-hour ≈ 0.83 MiB per audio-minute. So O(100) 30-s ad spots ≈ 40–45 MiB; O(1,000) 30–60 s ≈ 0.4–0.8 GB; O(1,000) long program tracks (5–30 min each) adds ≈ 0.1–5 GB.
- **Rebuild cost:** *no published CPU-seconds-per-audio-hour figure exists* (checked NuGet release notes, wiki, emysound.com, readme.io, Docker Hub, web search — none) [26]. What is verifiable: because of `Snapshot()`, re-fingerprinting happens **once** (seed); every restart is a file load + index build, not a re-fingerprint. Order-of-magnitude anchors for ingest throughput: Emy at broadcast scale fingerprints 36,000 audio-hours/day [7] and TVEyes searches 26,000 h of daily audio content [22]; a homelab seed of ≤1000 short tracks is a one-time offline step (budget it as such — do not hard-code a CPU figure in the plan).

**Emy community edition (the persistent-server lane)** [4][6][8][9][13][27]:
- **Current image tag (fetched 2026-11-23):** `addictedcs/soundfingerprinting.emy:18.0.3-community` (pushed 2026-11-21; amd64 + arm64; ≈589 MB; `latest` = same digest). Latest 17.x-line image: `17.4.13-community` (2026-11-20) [6].
- **Client↔server compatibility:** official version matrix "SF 17.x ↔ SoundFingerprinting.Emy 17.x ↔ FFmpeg 9.x" (16.x ↔ 16.x ↔ FFmpeg 8.x) [1]. The Emy client 16.1.0 note states "Wire protocol unchanged: 16.0.x servers and 16.1.0 clients interoperate in both directions" (minor-pair interop, 16.x era) [4]. **Cross-major (17.x client ↔ 18.x server) is not documented → pin client and server to the same major:** SF 17.4.0 + Emy client 17.4.0 + image `17.4.13-community` (or the 18.0.0/18.0.3 pair). The Emy client 17.0.0 note: "Upgrade to FFmpeg 9.x (FFmpeg.AutoGen 9.0.1.1); the loaded FFmpeg build must include **libsoxr**" [4] — the worker image's FFmpeg must carry libsoxr if `FFmpegAudioService` is used (R3 input).
- **Licence:** "Community Edition … free for **non-commercial** [and evaluation] use. Full fingerprinting engine, audio and video, Single Docker container, backoffice UI included, JSON API and .NET client" [8][9][13]; Enterprise = commercial license, flat, no per-query fees, adds replication/HA + support [8][9]. **Homelab = non-commercial → CE is the lawful lane.** Note: CE sends an anonymous telemetry pulse every 30 min (version, OS, CPU/mem size, track counts; country/carrier derived server-side, IP not stored, no track data); **opt out with `EMY_TELEMETRY_DISABLED=true` or `DO_NOT_TRACK=1`** [9][13].
- **K8s deployment shape (confirmed from official quick-start):** single container, `docker run -d -v /persistent-dir:/app/data -p 3399:3399 -p 3340:3340 addictedcs/soundfingerprinting.emy:<tag>` — **port 3399 = binary protocol used by the .NET client; port 3340 = JSON API + backoffice UI (Swagger at `:3340/docs`); fingerprints persist under mounted `/app/data`** [9][13]. CE default credentials: application ID `Admin`, empty API key (generate your own in the backoffice) [9]. StatefulSet + RWO PVC at `/app/data` is the correct shape (CE is single-instance; replication is Enterprise-only) [9].
- **"0.75 MiB per track" RAM rule: NOT VERIFIED** — no public source found as of 2026-11-23 (checked wiki, emysound.com home/developers/pricing, readme.io, Docker Hub, web search) [26]. Verified anchors instead: Emy's index is an in-memory min-hash, "lookups touch packed, block-compressed postings at roughly **21 bits per entry, so catalogs of hundreds of thousands of tracks fit in commodity RAM**" [9]; the InMemoryModelService FAQ figure above [1]. For O(100)–O(1,000) tracks both lanes' fingerprint RAM is a rounding error next to process/container overhead (Emy image ≈589 MB [6]).
- **Emy's own stream-ingestion alternative (know, don't adopt here):** Emy can ingest HTTP/HLS streams itself (`POST /api/v1.1/streams {streamId, streamUrl, savePlaybackTrack}`) and match them against the catalog, with matches retrievable via `GET /api/v1.1/matches` [9][24]. **Snapcast is not an HTTP stream**, so the card's design (worker feeds chunks via the .NET client) stands; this alternative matters only if the tap point ever becomes an HTTP/icecast stream.
- Runtime ingestion surfaces: Emy = JSON API multipart upload `POST /api/v1.1/tracks` (id/title/artist/metaFields/mediaType/file), URL ingest (PUT with `encodedMediaUrl`), backoffice UI, or the .NET client (`EmyModelService.NewInstance(host, 3399)` + `Insert(track, hashes)` + `RegisterMatches`) [9][13]. InMemory lane = worker-side `InsertAsync` + `Snapshot()` (e.g. on an HTTP sidecar endpoint or an MQTT-triggered file drop).

### 4. Concrete recommendation inputs (O(100) ads vs O(1,000) program)

- **RAM fits both lanes trivially** (≤ ~5–6 GB worst case, typically ≪1 GB for a rotating radio catalog) — so the decision is about **operability, not capacity**.
- **Default lane (recommended input): `InMemoryModelService` + `Snapshot()` on a PVC in the worker container.** Rationale: one container, MIT-licensed [1], zero extra services, `Snapshot()` makes restarts a cheap file load (the §3 point that changes the "rebuild cost" calculus), and at O(1000) the store is <1 GB. The "testing purposes only" remark is the one caveat to carry consciously; the FAQ's 5 GB/100 h figure shows the maintainer treats it as a real storage option [1][15].
- **Upgrade path: Emy CE** when the owner wants (a) a UI/JSON surface to add ad audio without touching the worker, (b) server-side match history/dedup, or (c) a catalog that will grow toward 10⁴–10⁵ tracks [9]. Then: StatefulSet, PVC at `/app/data`, ports 3399+3340, pin `17.4.13-community` with SF 17.4.0 + Emy client 17.4.0, `EMY_TELEMETRY_DISABLED=true`, generate a JSON API key after first boot [6][9][13].
- **Pre-seed/ingestion pipeline (either lane):** (1) owner curates a directory of ad audio files (source = open question below); (2) a one-time seed step (job or first-run of the worker) decodes + fingerprints each file (`FingerprintCommandBuilder…From(file).UsingServices(FFmpegAudioService).Hash()` — the Emy-client wiki's canonical insert shape [13][9]) and inserts it, tagging `TrackInfo` meta (e.g. `kind=ad`, `spot=30s`); (3) `Snapshot()` to the PVC (InMemory lane) or done (Emy lane — server persists under `/app/data` [9]); (4) runtime additions: `InsertAsync` + `Snapshot()` (InMemory) or `POST /api/v1.1/tracks` / backoffice (Emy). Dedup guard: skip if `ReadTrackById`/`GetTrackById` already knows the id (the wiki's insert loop does exactly this [13]).

### Contradictions & how to weigh them

1. **Intake claim "snapshot/serialisation API in 17.x — unverified" vs source: refuted.** `Snapshot()` + load-from-directory ctor exist at tag `v17.4.0` and are integration-tested [16][17]. Weigh: use the API; the only real caveat is the "testing purposes only" remark, which the README's own storage guidance partially contradicts by pointing "small projects" at it while pointing persistent use at Emy [14].
2. **"Testing purposes only" (InMemoryModelService remark) vs production use at O(1000)** [15]: a scope caution, not a functional limit — but the README explicitly calls Emy "the preferred choice" for external persistent storage [1]. If the owner is risk-averse about storage durability/operability, Emy is the sanctioned lane; at this scale the technical delta is small.
3. **Card's "17.x" premise vs 18.0.0 shipping 2026-11-20** [1][5][6]: 18.0.0 is 3 days old at research time; the 17.x line (17.4.0) is the conservative pin, and the Emy server line tracks it (`17.4.13-community`). Flag to the plan: pin 17.4.0 unless the owner wants bleeding-edge; the library is netstandard2.0 either way, so a .NET 10 worker runs both.
4. **Wiki staleness:** "Save fingerprints" and "Emy Storage" wiki pages date from 2021 (pre-16.0.0 sync API) while the Realtime/Seam pages were re-edited 2026-10-15 and the NuGet notes carry the canonical 2026 changelog. Weigh: source at `v17.4.0` + 2026-10-15 wiki pages + NuGet notes > 2021 wiki text (used here only for the run command shape, which matches the 2026 emysound.com docs).

### Implications for the plan

1. Chunking is a hard contract: exactly 10,240 mono float samples at 5512 Hz per chunk (1.857 s), fed as `IAsyncEnumerable<AudioSamples>` (via `BlockingCollection` + `BlockingRealtimeCollection`); do **not** add producer-side chunk overlap — the library's internal prefix handles FFT continuity, and if the worker ever does overlap it must stamp `Hashes.TimeOffset` with the negative overlap length (15.8.0/15.13.0 rules) [1][10][11].
2. 16.0.0+ shapes: drive `IRealtimeQueryCommand.Query(token)`; publish the HA MQTT event **inside the awaited `SuccessCallback`** (backpressure is natural — the command waits for the callback's task before the next chunk) [1][18].
3. Set `SeamJumpPolicy.NewOccurrenceAbove(120)` whenever program tracks that repeat ad spots are in the catalog (the library's own broadcast agents use 120 s); consider `OngoingEntryStalenessCeiling` (e.g. 60–120 s) so stale ongoing entries close promptly [1][12].
4. The realtime source must be **hot** — the snapclient pipe supervisor (R2) must support resuming at the current position on re-enumeration after a transient error, or accept duplicate-query behaviour [1][19].
5. `Snapshot()` on the PVC means restart ≠ re-fingerprint; budget the ad-catalog seed as a one-time offline step, with no published CPU figure to hard-code (none exists) [1][16][17][26].
6. If Emy is chosen: pin **same-major** client/server (17.4.x client + `17.4.13-community` image), StatefulSet + PVC at `/app/data`, ports 3399/3340, telemetry opt-out env, generated API key; the worker's FFmpeg build must include **libsoxr** [1][4][6][9].
7. Emy's server-side stream ingestion (HTTP/HLS only) does **not** fit a snapcast tap — do not design the architecture around it [9][24].

### Open questions for the batched round

1. **Ad-catalogue seeding source (EXPLORE.md OQ3):** pre-seeded DB yes/no — and if yes, who/what supplies the ad audio files (owner-curated directory? auto-capture of newly-recognized unknown audio? a public radio-ad corpus?)? Owner decision.
2. **Storage lane:** `InMemoryModelService` + `Snapshot()` (single container, §4 default) vs Emy CE (second container, JSON-API ingestion + backoffice UI) — §4's inputs lean InMemory at O(100)–O(1,000); owner tie-break on operability preference.
3. **If program content is catalogued (the "reverse approach" or whole-program entries):** what program window (recent N hours? full day?) — drives catalog growth, RAM, and the `NewOccurrenceAbove` configuration.
4. **Pin 17.4.0 vs adopt 18.0.0** (3 days old at research time; no 18.x Emy client/server pairing caveat beyond the version matrix) — plan decision, owner informed.
5. **Telemetry posture** if Emy is chosen (recommend `EMY_TELEMETRY_DISABLED=true` for homelab hygiene).

### Adjacent (out of R1 core scope, recorded for R2/R3)

- FFmpeg for `FFmpegAudioService` (the canonical decode+downsample path in the Emy wiki's insert sample [13]) must be an FFmpeg 9.x build **with libsoxr** when paired with Emy client ≥17.0.0 [4]; the 48 kHz stereo → 5512 Hz mono float resample can equally be done worker-side before chunking — either satisfies the §1 contract.
- `RealtimeFingerprintCommand` (15.15.0) exists if the worker wants fingerprint-only mode or an edge/worker split [1].
- Playback-speed compensation exists for queries (`sourcePlaybackSpeedPercentage`, 15.10.0) — relevant if the tapped stream's clock drifts [1].

### Sources

[1] NuGet `SoundFingerprinting` 18.0.0 package page — full release notes 9.4.2→18.0.0, FAQ, version matrix (fetched 2026-11-23). https://www.nuget.org/packages/SoundFingerprinting/18.0.0
[2] NuGet flat-container API, `soundfingerprinting` version list. https://api.nuget.org/v3-flatcontainer/soundfingerprinting/index.json
[3] NuGet flat-container API, `soundfingerprinting.emy` version list. https://api.nuget.org/v3-flatcontainer/soundfingerprinting.emy/index.json
[4] NuGet `SoundFingerprinting.Emy` 18.0.0 package page — client release notes (17.4.0/17.3.4/17.2.0/17.0.0/16.1.0/16.0.0/15.17.0). https://www.nuget.org/packages/SoundFingerprinting.Emy/18.0.0
[5] GitHub releases API, `AddictedCS/soundfingerprinting` (publication dates). https://api.github.com/repos/AddictedCS/soundfingerprinting/releases
[6] Docker Hub tags API, `addictedcs/soundfingerprinting.emy` (18.0.3-community 2026-11-21; 17.4.13-community 2026-11-20; amd64+arm64). https://hub.docker.com/v2/repositories/addictedcs/soundfingerprinting.emy/tags
[7] Emysound landing (scale stats, ad self-discovery claim). https://emysound.com/
[8] Emysound pricing/licensing page. https://emysound.com/pricing/
[9] Emysound developer docs (ports, /app/data, CE default creds, JSON API v1.1, .NET client sample, "under the hood", quick start). https://emysound.com/developers/
[10] Project wiki "Realtime Query Command" (edited 2026-10-15). https://github.com/AddictedCS/soundfingerprinting/wiki/Realtime-Query-Command
[11] Maintainer gist "Realtime Command usage for SoundFingerprinting" (10,240 samples @ 5512 Hz = 1.857 s). https://gist.github.com/AddictedCS/8ce2ec2614f1f7ef70b68dbf6b38e331
[12] Project wiki "Realtime Seam Jump Policy" (worked ad-pod example, 120 s ceiling, measurements). https://github.com/AddictedCS/soundfingerprinting/wiki/Realtime-Seam-Jump-Policy
[13] Project wiki "Emy Storage" (run command, .NET insert/query samples — 2021 text, consistent with [9]). https://github.com/AddictedCS/soundfingerprinting/wiki/Emy-Storage
[14] Project wiki "Save fingerprints and identify tracks" (InMemoryModelService "testing … and other small projects"). https://github.com/AddictedCS/soundfingerprinting/wiki/Save-fingerprints-and-identify-tracks
[15] `InMemoryModelService.cs`, master (Snapshot(path), loadFrom directory ctor, "testing purposes only" remark). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/master/src/SoundFingerprinting/InMemory/InMemoryModelService.cs
[16] `InMemoryModelService.cs` at tag **v17.4.0** (Snapshot + loadFrom verified present). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/v17.4.0/src/SoundFingerprinting/InMemory/InMemoryModelService.cs
[17] `InMemoryModelServiceSerializationTest.cs` (Snapshot→reload→query round-trip, id increment). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/master/src/SoundFingerprinting.Tests/Integration/InMemoryModelServiceSerializationTest.cs
[18] `RealtimeQueryConfiguration.cs`, master (Task-returning callbacks, filter list). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/master/src/SoundFingerprinting/Configuration/RealtimeQueryConfiguration.cs
[19] `IRealtimeSource.cs`, master (From overloads, hot-source requirement). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/master/src/SoundFingerprinting/Command/IRealtimeSource.cs
[20] `ModelServiceInfo.cs`, master (Sequence, proto member 5, nullable). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/master/src/SoundFingerprinting/ModelServiceInfo.cs
[21] Docker Hub repository page, `addictedcs/soundfingerprinting.emy` (full description: CE licence, telemetry + opt-out env, run command). https://hub.docker.com/v2/repositories/addictedcs/soundfingerprinting.emy/
[22] Emysound case study "Search ads over 1,500 TV stations" (TVEyes: pre-inserted ads, 300k ads, <1.5 s start accuracy, ≤2 min delay, 40% coverage emission). https://emysound.com/case-studies/audio/
[23] Emysound blog "How does Audio Fingerprinting work" (8192 samples/fingerprint = 1.48 s, 64 overlap). https://emysound.com/blog/open-source/2020-06-12/how-audio-fingerprinting-works.html
[24] Emysound docs index (JSON API v1.0/v1.1 surface: streams, tracks, matches, media). https://emysound.readme.io/
[25] Emysound "Run Emy Community in Docker" doc (volume, ports, CE licence line). https://emysound.readme.io/reference/run-emy-community-in-docker.md
[26] Negative results (searched 2026-11-23, no source found): "0.75 MiB/track" RAM rule; any published InMemoryModelService CPU-seconds-per-audio-hour figure — across NuGet notes, wiki, emysound.com (home/pricing/developers/case-studies/blog), readme.io, Docker Hub, and web search.
[27] GitHub repo `AddictedCS/soundfingerprinting` (MIT licence, 1,046 stars). https://github.com/AddictedCS/soundfingerprinting
[28] GitHub repo search `soundfingerprinting` (ecosystem scan: 17 repos, no well-known open-source radio-ad-detection project). https://api.github.com/search/repositories?q=soundfingerprinting

## R3 — .NET 10 worker: base image, resampling, pipe mechanics, MQTT client, CI build

Grounded 2026-11-23 (Pre Research, thread R3). Method: direct fetch of primary sources (dotnet-docker
READMEs + 10.0 Dockerfiles, NAudio raw source at `v3.3.0` and `main`, SoundFingerprinting raw source at
`develop`, snapcast README + raw file-player source, NuGet nuspecs, man7) + SearXNG searches + direct
reads of repo files (`.forgejo/workflows/containers-build.yaml`, `renovate.json`,
`containers/snapcast/Dockerfile`). Cross-checked against R1 and EXPLORE.md.

### TL;DR

- Base images: `mcr.microsoft.com/dotnet/sdk:10.0` → `dotnet/runtime:10.0` multi-stage. Both `10.0`
  images = servicing **10.0.15 on Ubuntu 24.04 (noble)**, amd64 (repo is single-arch amd64).
  **`runtime:10.0` does NOT carry the ASP.NET Core shared framework** (Dockerfile-verified);
  `aspnet:10.0` = `runtime:10.0` + the AspNetCore framework layer [1][2][3][4].
- Resampling: **NAudio.Core 3.3.0 (stable) + the low-level `NAudio.Dsp.WdlResampler` used directly in
  Sinc64 mode** (`SetMode(false, 0, true, 64)`). The 3.3.0 *provider wrapper* is IIR-filter mode with
  no quality selector (weak anti-alias for an 8.7× downsample); the quality enum +
  `HoldBackOnShortReads` are 3.4.0-preview-only — do not take the preview [6][7][8]. s16le→float and
  stereo→mono are plain math; the whole WDL chain lives in NAudio.Core (net9.0, cross-platform) — do
  **not** take the NAudio meta-package (Windows-only sub-packages) [11][12].
- Pipe: snapclient's `file` player is a **writer/recorder** — README: "Write audio to file",
  `filename=stdout` is a first-class value; source: `kDescription = "Raw PCM file output"` — raw 48k
  stereo s16le PCM, no header, 50 ms writes with `fflush`, **silence written on stream underrun** so
  the byte stream stays time-continuous even under backpressure [20][21]. Kernel pipe = 65,536 B
  (≈0.34 s of 48k stereo s16 at 192,000 B/s), blocking write when full → backpressure = brief source
  gaps (silence) + detection delay, **not silent data loss** [23].
- MQTT: **MQTTnet 5.2.0.1603** — nuspec targets **net10.0** + net8.0, MQTT 3.1.0/3.1.1/5.0.0,
  client + broker in one package, .NET Foundation [25].
- CI: CI-primary via `containers-build.yaml` (plain `docker build`, in-pod dind on ubuntu-24.04,
  `docker-data` volume persists the layer store across jobs, 30-min ceiling — a **cold first build**
  (image pulls) is the risk; warm builds fast; dual publish + PR arm as verified). Renovate: `FROM`
  lines + csproj `PackageReference`s are auto-managed; the custom tool-ARG manager covers only
  node/golang/forgejo/npm — pin the snapclient `.deb` with the comment-above-ARG `github-releases`
  shape [30][31][32].
- Footprint (estimates — no published figures exist, R1 [26]): steady-state CPU ≪1 of a core (per-chunk
  fingerprint math + 64-tap resampler are trivial); RAM is model-dominated (≈50 MB/audio-hour, R1 [1])
  → O(100) ad spots ≈ 512 Mi/1 Gi, O(1,000) ≈ 1.5–2 Gi.

### 1. Base image + build shape

- .NET 10 GA 2025-11-11, **LTS** (to Nov 2028); .NET 11 = standard-support line. dotnet-docker featured
  tags: `11.0` (Standard Support), `10.0` (LTS) [1][26].
- 10.0 images = **10.0.15 on Ubuntu 24.04 (noble)**; amd64 + arm64 tags upstream; this repo's build is
  single-arch amd64 (EXPLORE §1), so the plain `10.0` tag is correct. Variants (alpine, alpine-extra,
  azurelinux, distroless) exist for 10.0 but are not needed [2][5].
- **runtime vs aspnet (Dockerfile ground truth)** [3][4]: `runtime:10.0` = `runtime-deps:10.0.15-noble`
  + the sha512-verified .NET runtime tarball **only**; `aspnet:10.0` = `runtime:10.0` + the
  `dotnet-aspnetcore` shared-framework layer. Consequence: a console worker on the runtime image has no
  ASP.NET Core shared framework — Kestrel needs the aspnet image (or a manual framework reference with
  the framework installed).
- Multi-stage shape (repo conventions: no `:latest` bases, non-root **uid 65532** with explicit
  useradd, `ENTRYPOINT`, layer ordering per skills/container-creation):
  - build stage: `FROM mcr.microsoft.com/dotnet/sdk:10.0` → `dotnet publish -c Release -r linux-x64
    --self-contained false` (framework-dependent — keeps the runtime image small).
  - runtime stage: `FROM mcr.microsoft.com/dotnet/runtime:10.0` → COPY publish output; `wget` the pinned
    snapclient `.deb` from the GitHub release + `apt-get install -y ./snapclient.deb` (the in-repo
    `containers/snapcast/Dockerfile` pattern) [32]; create non-root user; `ENTRYPOINT`.
- snapclient `.deb`: latest release **v0.35.0** (2026-03-10; org now `snapcast/snapcast`):
  `snapclient_0.35.0-1_amd64_bookworm.deb` (591,928 B, sha256
  `b71575bcc2b4541f5004c73a0a1f43374e852bf5d5f2162aa1b230f3c209d9f3`) — base player, **no pulse/pipewire
  dependencies** (with-pulse/with-pipewire variants exist) [22]. bookworm `.deb` on the noble runtime:
  glibc compatibility not verifiable in research (no docker daemon) — dev-time verification item (§6
  open questions).
- `readOnlyRootFilesystem`: **no official dotnet-docker read-only-root-filesystem doc exists** (searched
  2026-11-23 — web + repo README/FAQ: nothing) [29]. Expected writable surfaces: `/tmp` (TMPDIR), the
  non-root user's `$HOME`, the model directory (PVC). Shape: `readOnlyRootFilesystem: true` + emptyDir
  mounts (`/tmp`, home dir) + PVC (model dir); verify on first RO-root boot (dev time).
- Health endpoints (`/healthz` liveness, `/readyz` = model loaded + query loop running + MQTT connected
  + pipe data flowing) — two viable shapes:
  - **A (recommended, lean):** console Worker Service (Generic Host) on `dotnet/runtime:10.0` +
    `System.Net.HttpListener` (BCL, no extra package; the managed listener works on Linux, bind
    `0.0.0.0:<port>`).
  - **B:** `dotnet/aspnet:10.0` + Kestrel minimal API (+ optional AspNetCore.HealthChecks) — if the
    middleware/ecosystem is wanted; costs the extra shared-framework layer [3][4].

### 2. Resampling (48k stereo s16le → 5512 Hz mono float)

- **Library contract (confirmed):** "It's the responsability of the caller to provide mono audio samples
  at 5512 frequency rate. If this condition is met, the algorithm will not invoke any methods from
  NAudio." [27] — the library never resamples; `FingerprintService` throws on
  `samples.SampleRate != configuration.SampleRate` (5512 is a hard check) [14].
  `DefaultFingerprintConfiguration.SampleRate = 5512` (TopWavelets 200, ComputeSpectralProfile = true)
  [15]; default strides: fingerprint 512, query 256–512 [16]. 5512 is the documented input contract, not
  an arbitrary choice [27].
- NAudio layout: current repo splits into per-API packages under `src/`; the cross-platform core is
  **NAudio.Core** (latest stable **3.3.0**; 3.4.0-preview.1 is the next line; Windows-only sub-packages:
  Wasapi/WinMM/Asio/Dmo/WinForms/MacOS — not needed). NAudio.Core 3.3.0 targets **net9.0** (AOT-friendly,
  Windows/Linux/macOS) [11][12] → runs on the .NET 10 worker with zero friction. The conversion providers
  (Pcm16BitToSampleProvider, StereoToMonoSampleProvider), the WDL resampler and the Wdl provider all live
  in NAudio.Core — one managed package covers the whole chain.
- **NAudio 3.3.0 WDL surface (source-verified)**:
  - `WdlResamplingSampleProvider(source, newSampleRate)` — the constructor takes **no quality parameter**;
    internally `resampler.SetMode(true, 2, false)` = interpolation + **2 IIR filters** (a 2nd-order IIR
    anti-alias — weak stopband for an 8.7× downsample). No `HoldBackOnShortReads` in 3.3.0 [6].
  - The low-level `WdlResampler` (NAudio.Dsp) **is present in 3.3.0 stable** with
    `SetMode(bool interp, int filtercnt, bool sinc, int sinc_size = 64, int sinc_interpsize = 32)` +
    `SetFeedMode(bool wantInputDriven)` + `SetRates(in, out)` + `ResamplePrepare`/`ResampleOut` →
    **Sinc64 (64-tap windowed sinc, flat band) is available on stable** via `SetMode(false, 0, true, 64)`
    [7].
  - On `main` (3.4.0-preview.1) the provider gained `WdlResamplerQuality` (Linear/LinearHighQuality/
    Sinc16/Sinc64, **Sinc64 default**) + `HoldBackOnShortReads` (the documented fix for mid-stream short
    reads — exactly the pipe case); the enum remarks call Linear "the algorithm used before NAudio 3.4" [8].
- **Recommendation: NAudio.Core 3.3.0 + `WdlResampler` used directly (Sinc64, feed mode)**:
  - per pipe read: s16le→float (`v / 32768.0f`) + stereo→mono (`(L + R) * 0.5f`) — plain math (or the
    NAudio.Core providers); feed `WdlResampler` (`SetRates(48000, 5512)`, `SetFeedMode(true)`,
    `SetMode(false, 0, true, 64)`), pull output into a 10,240-float accumulator →
    `new AudioSamples(chunk, "", 5512)` [19].
  - The 3.3.0 `HoldBackOnShortReads` is absent at the low level — handle it yourself: a short read on a
    *blocking* pipe is never end-of-stream (reads return ≥1 byte until the writer closes); treat
    read-EOF (child death) as stream end and re-enumerate per the hot-source rule (R1 §1).
  - Alternatives: (a) NAudio 3.4.0-preview.1 provider (Sinc64 default + HoldBackOnShortReads) — avoid
    preview packages in production; revisit when 3.4 stabilizes (drop-in, no architecture change).
    (b) ~100-line inline windowed-sinc resampler (zero dependency) — viable, but WDL is battle-tested
    (Cockos WDL, permission-granted port, per the source header) [7]. (c) the 3.3.0 provider wrapper
    (IIR mode) — **not recommended**: a 2nd-order IIR anti-alias at 8.7× downsample leaks HF energy and
    risks match-quality degradation.
- 10,240 samples at 5512 Hz = **1.8578 s** — consistent with the library's "≈1.8 s chunk-overlap prefix
  with default configurations" MatchedAt note (R1 §1). Feed **non-overlapping** chunks (R1 implication 1).

### 3. Pipe mechanics (snapclient → worker)

- **Direction confirmed from source**: the snapcast `file` player is a recorder — README:
  "file | All | Write audio to file | `filename` = `stdout`, `stderr`, `null` or a filename; `mode=[w|a]`"
  [20]; source `kDescription = "Raw PCM file output"` — raw PCM, no header [21].
- Write behavior (source-verified [21]): `requestAudio()` every 50 ms (`kDefaultBuffer`):
  `numFrames = 48000 × 0.05 = 2,400 frames × 4 B (stereo s16) = 9,600 B` per `fwrite` + `fflush`;
  `getPlayerChunkOrSilence(buffer, 10 ms, numFrames)` — **silence is written on stream underrun**, so the
  byte stream stays time-continuous (no offset drift under backpressure); `adjustVolume` is applied
  **before** the write (keep snapclient volume at 100%); `needsThread() = false` (runs on the asio
  context).
- Pipe semantics [23][24]: kernel buffer default **65,536 B** (16 pages, Linux ≥2.6.11; tunable via
  `F_SETPIPE_SZ`); a write **blocks** when full (default, without `O_NONBLOCK`); a pipe is a **byte
  stream with no message boundaries** (frame parity must be tracked across reads); closing the read end
  → SIGPIPE/EPIPE to the writer.
- Backpressure: pipe full (65,536 B ≈ **0.34 s** of 48k stereo s16 at 192,000 B/s) → snapclient's
  `fwrite` blocks → the 50 ms pacing loop stalls → incoming stream accumulates in snapclient's internal
  buffer → underrun/resync on overflow (silence frames written). Net effect: **detection delay + brief
  source gaps (silence), not silent data loss**; the worker always receives a continuous, time-aligned
  PCM stream.
- Worker read loop (recommended): launch
  `snapclient --host home-snapcast --stream <id> --player file:filename=stdout` as a **foreground** child
  (no `--daemon 1` — a daemonized child detaches from kill); `RedirectStandardOutput` +
  `RedirectStandardError`; tight `Stream.Read` loop (64 KiB buffer) with a **4-byte frame-parity
  accumulator** (stereo s16 frame = 4 B); **drain stderr on a background thread** (the classic
  child-process deadlock — a full stderr pipe blocks the child); do NOT log stdout (it is the audio).
- `System.IO.Pipelines` is not needed: 192 KB/s is low-rate and the processing is synchronous chunking —
  a plain `Stream.Read` + accumulator is simpler and sufficient.
- Chunking: accumulate 10,240 resampled mono floats (1.8578 s) → `AudioSamples` → `BlockingCollection` →
  `BlockingRealtimeCollection` (present on current `develop`; `IAsyncEnumerable` adapter over
  `BlockingCollection`, 30 s default delay) → `IRealtimeQueryCommand` [17][18][19]. Hot-source rule (R1
  §1): on re-enumeration the supervisor must resume at the current position — a snapcast reconnect
  re-attaches to the live stream (naturally hot; R2 owns the restart semantics).
- Shutdown ordering: kill the snapclient child **before** closing the pipe read end (avoids the SIGPIPE
  race); see §4.

### 4. Process plumbing: health, logging, MQTT, configuration, shutdown

- **MQTT client — MQTTnet 5.2.0.1603**: nuspec targets **net10.0 + net8.0**; MQTT 3.1.0/3.1.1/5.0.0;
  client and broker in one package; .NET Foundation [25]. Publish ad events **inside the awaited
  `SuccessCallback`** (R1 implication 2: natural backpressure — the command awaits the callback's task
  before the next chunk); QoS/at-least-once, clean-session and reconnect-with-backoff choices stay plan
  decisions.
- **Logging:** `Microsoft.Extensions.Logging` + console provider (structured JSON). SoundFingerprinting
  18.0.0 is **netstandard2.0** and depends on **Microsoft.Extensions.Logging.Abstractions 11.0.0** +
  Microsoft.Bcl.AsyncInterfaces 11.0.0 + protobuf-net 3.4.40 [13] — "logging is a dep" is precisely the
  Abstractions package (runs on the .NET 10 worker); add `Microsoft.Extensions.Logging` 10.x + console
  provider explicitly.
- **Configuration:** plain env vars (Generic Host env provider): snapcast host/stream id, MQTT URI +
  topic prefix, model dir, health port. No secrets for the anonymous in-cluster broker (EXPLORE §5:
  `home-mosquitto` is `allow_anonymous true`, no Bitwarden item needed); the ExternalSecret shape
  (zigbee2mqtt precedent, EXPLORE §7.4) only if the target broker requires credentials.
- **Graceful shutdown:** Generic Host + `PosixSignalRegistration` (SIGTERM) → cancel the
  `IRealtimeQueryCommand` token (runs until cancellation — R1 §1) → stop the read loop → SIGTERM the
  snapclient child (≈5 s grace, then SIGKILL; `Process.Kill(entireProcessTree)`) → MQTT graceful
  disconnect → `Snapshot()` (model lane, R1 §3) → exit 0. Everything lands well inside the 30 s K8s
  grace — there is no long job to drain, the realtime loop just stops.

### 5. CI build + Renovate (repo facts, direct read)

- `.forgejo/workflows/containers-build.yaml` [30]: plain `docker build` (no buildx/`--platform`) on the
  `ubuntu-24.04` runner with in-pod dind; the `forgejo-runner` image (act-24.04, helm+cr baked in —
  **no dotnet**). The **`docker-data` volume persists the layer store across jobs** (lines 345–347) →
  warm layer cache after the first build; **30-min job ceiling** (line 62) → a cold first build (sdk:10.0
  ≈250 MB+ pull + runtime:10.0 + `.deb`) is the risk; warm builds are fast (the `dotnet restore` layer
  caches while the csproj is unchanged).
- Detection: a push diffs the whole `before..sha` range (checkout `fetch-depth: 0`); a PR diffs
  merge-base→head; a new container dir is picked up by name (`^[a-z0-9]+(-[a-z0-9]+)*$` + a Dockerfile —
  `audio-ad-detection` is collision-free, EXPLORE §1).
- Publish: main/dispatch (prod role) → `:yy.mm.N` + `:latest` + `:main` to **both**
  `ghcr.io/ownyourio` and `<instance-host>/curatedforest` (lines 337–356); PR (dev role) →
  `pr-<branch>-<sha>` to the instance registry only (lines 399–405).
- Agent-session gate: no docker daemon — `docker build => no-daemon, CI-deferred` is the designed
  passing-gate shape (cf-77, ruled 2026-10-28); build-critical facts come from the pinned base images'
  GHCR layer tar-listings/manifest digests.
- Renovate [31]: `FROM mcr.microsoft.com/dotnet/...` lines are tracked by the built-in dockerfile
  manager (auto, no comment needed); csproj `PackageReference`s are tracked by the built-in dotnet
  (csproj) manager (NAudio.Core, SoundFingerprinting, MQTTnet, M.E.Logging — all update automatically).
  The custom tool-ARG manager covers **only node-version|golang-version|forgejo-releases|npm** (lines
  136–143) — a "dotnet tool" ARG pin would be inert (and unneeded: the tool version is baked into the
  `sdk:10.0` image). snapclient `.deb`: pin with a
  `# renovate: datasource=github-releases depName=snapcast/snapcast` comment line directly above
  `ARG SNAPCAST_VERSION=0.35.0` + `wget .../releases/download/v${SNAPCAST_VERSION}/...` (fits the
  comment-above-ARG manager shape, lines 112–169; the `containers/snapcast/Dockerfile` wget-`.deb`
  pattern) [32]. Calendar-tag rule (`ghcr.io/ownyourio/*`, `^\d+\.\d+\.\d+$`, lines 308–316) manages the
  repo's own image pins once calendar tags exist — first chart pin `:main` + `pullPolicy: Always` +
  pin-me comment (EXPLORE §7.2).

### 6. CPU/RAM footprint (estimates — no published figures exist, R1 [26])

- CPU (per 1.8578 s chunk, 5512 Hz mono): fingerprint chain ≈ 20–40 × (Lomont FFT 1024 + log spectrum +
  Haar wavelet + top-200 descriptor + 6-point hash) plus ≈6 O(1) dictionary lookups per query frame →
  single-digit ms per chunk on a modern x64 → **≪1% of one core in steady state**; the 64-tap WDL sinc
  resample of 48k mono input ≈ 5,512 × 64 × 2 ≈ 7×10⁵ flops/s → <1%. A 1-core limit has large headroom;
  suggest **request 0.5 / limit 1.0** (EXPLORE §7.14: the single home node is the sizing constraint —
  this estimate says headroom is large, but verify against first dev-run metrics; no published figure
  exists to hard-code).
- RAM: model ≈ **50 MB/audio-hour** (R1 [1] FAQ: 100 h ≈ 5 GB) — O(100) 30-s spots ≈ 40 MiB,
  O(1,000) tracks ≈ 0.4–0.8 GB (R1 §3); worker .NET runtime + libs ≈ 50–100 MB; pipe buffer <64 KiB;
  the 10,240-float chunk = 40 KiB; snapclient ≈ 20–50 MB. Totals: **O(100) spots → 512 MiB request /
  1 Gi limit; O(1,000) → 1.5–2 Gi**.

### Contradictions & how to weigh them

1. **Earlier session note vs source (NAudio WDL):** the pre-research note "on stable 3.3.0 the worker
   must explicitly pass `WdlResamplerQuality.Sinc64"` is **wrong for the provider** — the 3.3.0 provider
   has *no quality parameter at all*; it is IIR-filter mode (`SetMode(true, 2, false)`) [6][7]. Refined
   truth: **Sinc64 is available on stable 3.3.0 via the low-level `WdlResampler`**
   (`SetMode(false, 0, true, 64)`) [7]; the quality enum (Sinc64 default) + `HoldBackOnShortReads` are
   3.4.0-preview only [8]. Weigh: use the low-level resampler on stable; do not chase the preview.
2. **"Linear only" (mid-session statement) vs source:** also refined — it is interpolation + a 2nd-order
   IIR filter, not raw linear; still not recommended for an 8.7× downsample (weak anti-alias stopband)
   [6][7].
3. **snapclient file player read-vs-write:** the common mental model ("the file player reads a file")
   vs README "Write audio to file" + source `kDescription = "Raw PCM file output"` — **it is a writer
   (recorder)** [20][21]. The whole pipe design (snapclient → pipe → worker) is sound.
4. **`BlockingRealtimeCollection` (suspected legacy name) vs current `develop`:** present and is the
   documented adapter [17] — the earlier open question is resolved.
5. **Fingerprint granularity figures:** 1.48 s (8192-sample fingerprint window, R1 [23]) vs 512-sample
   stride (≈93 ms/frame [16]) vs 1.8578 s producer chunks — different quantities (window vs stride vs
   chunk), no contradiction; the 1.8578 s chunk is consistent with the library's "≈1.8 s" MatchedAt
   prefix note (R1 §1).

### Implications for the plan

1. Dockerfile: two stages `sdk:10.0` → `runtime:10.0` (both = 10.0.15 noble, amd64); framework-dependent
   `dotnet publish -r linux-x64`; snapclient v0.35.0 bookworm `.deb` via wget+apt (the in-repo
   pattern) [2][3][22][32]; non-root uid 65532; `ENTRYPOINT`; no `:latest` bases.
2. Package set (csproj): SoundFingerprinting (17.4.0 or 18.0.0 per R1 OQ4), **NAudio.Core 3.3.0 only**
   (no NAudio meta-package), MQTTnet 5.2.x, `Microsoft.Extensions.Logging` 10.x + console [11][13][25].
3. Resampler: `NAudio.Dsp.WdlResampler`, `SetRates(48000, 5512)`, `SetMode(false, 0, true, 64)` (Sinc64),
   `SetFeedMode(true)`; s16le→float + stereo→mono inline; **do not use** the 3.3.0
   `WdlResamplingSampleProvider` wrapper (IIR mode) [6][7].
4. Pipe: foreground child `snapclient … --player file:filename=stdout`; tight stdout read loop with
   4-byte frame-parity accounting; stderr drain thread; volume 100%; the stream is time-continuous even
   under backpressure (silence frames) [20][21][23].
5. Chunking: non-overlapping 10,240-float @ 5512 chunks → `BlockingCollection` →
   `BlockingRealtimeCollection` → `IRealtimeQueryCommand.Query(token)`; hot-source restart via snapcast
   reconnect [17][18][19] + R1 implication 1.
6. Health: `/healthz` + `/readyz` on `HttpListener` (runtime image, lean default) or Kestrel (aspnet
   image) [3][4].
7. Shutdown: SIGTERM → cancel query → stop reader → TERM/KILL the snapclient child **before** closing
   the pipe read end → MQTT disconnect → `Snapshot()` → exit 0 [17][19][23].
8. Sizing: CPU 0.5/1.0 core; RAM 512 Mi/1 Gi (O(100)) or 1.5–2 Gi (O(1,000));
   `readOnlyRootFilesystem: true` + emptyDir `/tmp` + home + PVC (model dir) — verify RO-root on first
   boot (no official dotnet-docker RO-FS doc exists) [29].
9. CI/PR: CI-primary build gate; the first **cold** build risks the 30-min ceiling (watch the first forge
   run); first chart pin `:main` + `pullPolicy: Always` + pin-me comment, then `:yy.mm.N` (EXPLORE §7.2);
   Renovate: FROM + csproj auto-managed, `# renovate: datasource=github-releases
   depName=snapcast/snapcast` above `ARG SNAPCAST_VERSION` [30][31][32].

### Open questions for the batched round

1. **Bookworm `.deb` on the noble runtime** — `snapclient_0.35.0-1_amd64_bookworm.deb` on Ubuntu 24.04
   (noble): the base deb has no pulse/pipewire deps, but its shared-library needs on noble are not
   verifiable in research (no docker daemon). Dev-time verification: `snapclient --version` + a 10 s
   stdout capture. Fallback if it fails: build snapclient from source (the `containers/snapcast/Dockerfile`
   cmake builder precedent exists in-repo) [22][32].
2. **RO-root first boot** — the exact writable set for the dotnet runtime + snapclient (expected: `/tmp`,
   `$HOME`, model dir); no official dotnet-docker read-only-root-filesystem doc was found [29].
3. **Snapclient underrun policy at the 700 ms `Spencer` buffer** — the exact resync/drop behavior when
   pipe backpressure stalls the file player (this thread verified the file player's silence-writing path
   [21]; the client's buffer-overflow policy belongs to R2).
4. **MQTT target broker + credentials** — EXPLORE §5 / R4 territory (`home-mosquitto` anonymous in-cluster
   vs the HA `hassio` add-on broker); decides whether an ExternalSecret (zigbee2mqtt shape) is needed.
5. **NAudio 3.4.0 stabilization timing** (note, not a user question): when 3.4 stabilizes (Sinc64
   provider default + `HoldBackOnShortReads`), switching to the provider is a drop-in — track as a future
   simplification, not a blocker [8].

### Sources

[1] dotnet-docker `README.runtime.md` (featured tags: 11.0 Standard Support, 10.0 LTS; image variants). https://raw.githubusercontent.com/dotnet/dotnet-docker/main/README.runtime.md
[2] dotnet-docker `README.aspnet.md` — 10.0 tag table (10.0.15; noble/amd64 + alpine + azurelinux variants; amd64+arm64). https://raw.githubusercontent.com/dotnet/dotnet-docker/main/README.aspnet.md
[3] dotnet-docker `src/runtime/10.0/noble/amd64/Dockerfile` (runtime-deps:10.0.15-noble + runtime tarball only — no ASP.NET Core shared framework). https://raw.githubusercontent.com/dotnet/dotnet-docker/main/src/runtime/10.0/noble/amd64/Dockerfile
[4] dotnet-docker `src/aspnet/10.0/noble/amd64/Dockerfile` (runtime:10.0 + AspNetCore shared-framework layer). https://raw.githubusercontent.com/dotnet/dotnet-docker/main/src/aspnet/10.0/noble/amd64/Dockerfile
[5] dotnet-docker `documentation/image-variants.md`. https://raw.githubusercontent.com/dotnet/dotnet-docker/main/documentation/image-variants.md
[6] NAudio `v3.3.0` `WdlResamplingSampleProvider.cs` (no quality parameter; `SetMode(true, 2, false)` = interpolation + 2 IIR filters). https://raw.githubusercontent.com/naudio/NAudio/v3.3.0/src/NAudio.Core/Wave/SampleProviders/WdlResamplingSampleProvider.cs
[7] NAudio `v3.3.0` `WdlResampler.cs` (`SetMode(interp, filtercnt, sinc, sinc_size = 64, sinc_interpsize = 32)`, `SetFeedMode`, `SetRates`, `ResamplePrepare`/`ResampleOut` — Sinc64 available on stable; Cockos WDL port header). https://raw.githubusercontent.com/naudio/NAudio/v3.3.0/src/NAudio.Core/Dsp/WdlResampler.cs
[8] NAudio `main` (3.4.0-preview.1) `WdlResamplingSampleProvider.cs` + `WdlResamplerQuality.cs` (Sinc64 default; "the algorithm used before NAudio 3.4" = Linear; `HoldBackOnShortReads`). https://github.com/naudio/NAudio/blob/main/src/NAudio.Core/Wave/SampleProviders/WdlResamplingSampleProvider.cs
[9] NAudio issue #1005 (`BufferedWaveProvider` → `ToSampleProvider()` → `WdlResamplingSampleProvider`; fully managed, cross-platform real-time resampling pattern). https://github.com/naudio/NAudio/issues/1005
[10] NAudio issue #1077 (cross-platform confirmation). https://github.com/naudio/NAudio/issues/1077
[11] NuGet `NAudio.Core` (3.3.0 latest stable; "targets plain net9.0 … Windows, Linux, and macOS"; AOT-friendly). https://www.nuget.org/packages/NAudio.Core/
[12] NAudio `v3.3.0` `NAudio.Core.csproj` (net9.0 target). https://raw.githubusercontent.com/naudio/NAudio/v3.3.0/src/NAudio.Core/NAudio.Core.csproj
[13] NuGet `SoundFingerprinting` 18.0.0 nuspec (netstandard2.0; Microsoft.Bcl.AsyncInterfaces 11.0.0, Microsoft.Extensions.Logging.Abstractions 11.0.0, protobuf-net 3.4.40). https://api.nuget.org/v3-flatcontainer/soundfingerprinting/18.0.0/soundfingerprinting.nuspec
[14] SoundFingerprinting `develop` `FingerprintService.cs` (hard `samples.SampleRate != configuration.SampleRate` check; LomontFFT + Haar + descriptor + spectral-profile pipeline). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/develop/src/SoundFingerprinting/FingerprintService.cs
[15] SoundFingerprinting `develop` `DefaultFingerprintConfiguration.cs` (SampleRate = 5512, TopWavelets 200, ComputeSpectralProfile = true). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/develop/src/SoundFingerprinting/Configuration/DefaultFingerprintConfiguration.cs
[16] SoundFingerprinting `develop` `Configs.cs` (default strides: fingerprint 512; query 256–512). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/develop/src/SoundFingerprinting/Configuration/Configs.cs
[17] SoundFingerprinting `develop` `BlockingRealtimeCollection.cs` (`IAsyncEnumerable` adapter over `BlockingCollection`, 30 s default delay). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/develop/src/SoundFingerprinting/Command/BlockingRealtimeCollection.cs
[18] SoundFingerprinting `develop` `IRealtimeSource.cs` (`From` overloads; hot-source requirement). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/develop/src/SoundFingerprinting/Command/IRealtimeSource.cs
[19] SoundFingerprinting `develop` `AudioSamples.cs` (`float[]` + origin + sampleRate). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/develop/src/SoundFingerprinting/Audio/AudioSamples.cs
[20] snapcast `develop` `README.md` (file player: "Write audio to file"; `filename` = `stdout`/`stderr`/`null`/filename; `mode=[w|a]`). https://raw.githubusercontent.com/snapcast/snapcast/develop/README.md
[21] snapcast `develop` `client/player/file_player.cpp` (`kDescription = "Raw PCM file output"`; 50 ms `fwrite`+`fflush` loop; `getPlayerChunkOrSilence`; `adjustVolume` before write; `needsThread() = false`). https://raw.githubusercontent.com/snapcast/snapcast/develop/client/player/file_player.cpp
[22] snapcast v0.35.0 release (2026-03-10; org `snapcast/snapcast`; `snapclient_0.35.0-1_amd64_bookworm.deb` 591,928 B, sha256 `b71575bcc2b4541f5004c73a0a1f43374e852bf5d5f2162aa1b230f3c209d9f3`; base player, no pulse/pipewire deps). https://github.com/snapcast/snapcast/releases/tag/v0.35.0
[23] man7 `pipe(7)` (default capacity 65,536 B = 16 pages; write blocks when full without `O_NONBLOCK`; byte stream, no message boundaries; SIGPIPE/EPIPE; `F_GETPIPE_SZ`/`F_SETPIPE_SZ`). https://man7.org/linux/man-pages/man7/pipe.7.html
[24] man7 `pipe(2)` (kernel-buffered; see pipe(7)). https://man7.org/linux/man-pages/man2/pipe.2.html
[25] NuGet `MQTTnet` 5.2.0.1603 nuspec (targets net10.0 + net8.0; MQTT 3.1.0/3.1.1/5.0.0; client + broker; .NET Foundation). https://api.nuget.org/v3-flatcontainer/mqttnet/5.2.0.1603/mqttnet.nuspec
[26] .NET 10 download page (GA 2025-11-11; LTS). https://dotnet.microsoft.com/en-us/download/dotnet/10.0
[27] SoundFingerprinting repo README FAQ ("responsability of the caller to provide mono audio samples at 5512 frequency rate … will not invoke any methods from NAudio"; ad detection in radio streams = "the most frequent use-case"; 100 h ≈ 5 GB `InMemoryModelService`). https://github.com/AddictedCS/soundfingerprinting
[28] dotnet-docker `README.md` (support lifecycle; image update/CVE policy). https://raw.githubusercontent.com/dotnet/dotnet-docker/main/README.md
[29] Negative result (searched 2026-11-23): no official dotnet-docker read-only-root-filesystem documentation found (web search + dotnet-docker README/FAQ surfaces).
[30] Repo `.forgejo/workflows/containers-build.yaml` (direct read: plain `docker build` on ubuntu-24.04 in-pod dind; `docker-data` volume persists layer store, lines 345–347; 30-min job ceiling, line 62; dual publish ghcr.io/ownyourio + instance registry, lines 337–356; PR arm `pr-<branch>-<sha>` forge-only, lines 399–405; push range `before..sha` with `fetch-depth: 0`, PR merge-base→head).
[31] Repo `renovate.json` (direct read: custom tool-ARG manager covers only node-version|golang-version|forgejo-releases|npm, lines 136–143; comment-above-ARG pin shape, lines 112–169; calendar-tag rule for `ghcr.io/ownyourio/*` `^\d+\.\d+\.\d+$`, lines 308–316).
[32] Repo `containers/snapcast/Dockerfile` (direct read: wget `.deb` from GitHub release + `apt-get install -y ./x.deb` pattern; rust/cmake builder precedent).

## R2 — snapclient file-player acquisition + supervision + packaging

Grounded 2026-11-23 (Pre Research, thread R2). Method: live web research (SearXNG + direct fetch of
github.com/snapcast/snapcast source at the **v0.35.0 tag** — downloaded and grepped the release
tarball; the published debs, the release-asset API, issue/PR API, and the Debian package index).
Caveat recorded up front: the repo `master` branch is NOT the v0.35.0 source (master's CMakeLists
is VERSION 0.34.0 and lacks the SDL2 player + server `default_source` that the v0.35.0 tag has)
[R2-24][R2-3] — the v0.35.0 tag is what the published deb contains and is the authority here.

### TL;DR

- The ticket's exact command shape is valid: `snapclient --player file:filename=stdout --logsink
  stderr tcp://home-snapcast:1704` (+ `--hostID <stable>`). 50 ms tick, `fwrite`+`fflush` per tick,
  always writes exactly `needed` bytes (starvation = zero-filled silence, cadence unchanged) [R2-1][R2-5].
- **`--sampleformat 5512:16:1` FAILS AT STARTUP** — v0.35.0 CLI throws "sampleformat channels must be
  * (= same as the source)" for any numeric channel; SOXR resamples rate/bits only, **no downmix**.
  Use `--sampleformat 5512:16:*` and downmix in the .NET worker. (Option only exists in SOXR builds —
  the plain official deb IS a SOXR build: `libsoxr0` in its Depends) [R2-3][R2-9][R2-14].
- **Issue #1563 (file player use-after-free on CodecHeader: hang at 100% CPU or SIGSEGV 139) is OPEN
  and UNFIXED in v0.35.0** (opened 2026-10-30; PR #1571 with the 5-line fix still unmerged as of
  2026-11-23). Every server restart / pod restart / stream switch is an exposure event; the server
  shows `connected:true` + frozen `lastSeen` — only a client-side byte-cadence watchdog catches it [R2-15][R2-16].
- Plain official Debian deb suffices for the file player: zero audio-server deps (verified on the actual
  artifact: 592 KB, ships only `/usr/bin/snapclient`; no pulse/pipewire in ldd). **No official apt repo,
  no static binary — the GitHub-release deb is the canonical Dockerfile leg.** arm64 debs DO exist
  upstream, but this node is amd64 and the repo pipeline is single-arch amd64 [R2-11][R2-12][R2-14].
- Verdict on server-side tee: **client-side snapclient file player wins** — snapcast has no
  stream-export API (audio only leaves via 1704 client sessions); a meta-stream "tap" still needs the
  same client AND adds Helm config churn + server CPU. Stream choice is exposed via JSON-RPC on 1780
  (open access without `[auth]`; `Server.GetStatus` enumerates groups/streams, `Group.SetStream`
  re-points the tap) [R2-17][R2-18][R2-19].

### 1. `--player file` backend (ask 1)

**CLI spelling (verified in v0.35.0 source + man page + README):** `--player file[:<options>]` with
options `filename=<filename>` (`stdout` | `stderr` | `null` | a real file) and `mode=[w|a]`
(`w` = write/replace, `a` = append; any other mode throws "Mode must be w (write) or a (append)")
[R2-1][R2-3]. Default filename when absent = `stdout`. So `--player file:filename=stdout` (or simply
`--player file`) is the pipe form.

**Emission (file_player.cpp, v0.35.0 == master byte-identical for this file):**
- `kDefaultBuffer = 50ms`; the tick runs on the **single io_context thread** (`needsThread()` false)
  — network reads, decode, resample and the `fwrite` share one thread [R2-1].
- Per tick: `numFrames = uint32(msRate * 50ms)`; `stream_->getPlayerChunkOrSilence(buf, 10ms,
  numFrames)`; then `fwrite(buf, 1, needed, file_)` + `fflush(file_)`. **Always writes exactly
  `needed` bytes every 50 ms** — when the stream is starved the buffer is zero-filled
  (`Stream::getSilentPlayerChunk`) and still written: **starvation = silence at full cadence, never
  a gap** [R2-1][R2-5].
- Late-tick catch-up: `if (next_request_ < now) next_request_ = now + 1ms;` — missed ticks are
  dropped (no backfill burst) [R2-1].
- The `.hpp` class comment ("doesn't even write the received audio to file ... just discards it")
  is STALE — the code writes; 0.25.0 changelog confirms the old stdout-polluting log line for the
  file backend was removed (Issue #681) [R2-22][R2-1].
- **`--sampleformat` interaction:** the option exists only under `#ifdef HAS_SOXR` (v0.35.0
  snapclient.cpp). Parsing: `SampleFormat("rate:bits:channels")` with `*`→0; **validation throws for
  any numeric channels** ("sampleformat channels must be * (= same as the source)") and allows bits
  0|16|24|32 only. The SOXR resampler is created with the INPUT channel count — channel count is a
  no-op passthrough, so **`--sampleformat 5512:16:1` is rejected at startup and no downmix exists in
  snapclient**; use `5512:16:*` (README's own example uses the `*` form: `--sampleformat 48000:16:*`)
  and downmix to mono in the .NET worker. Without SOXR the Resampler ctor throws "Resampling
  requested, but not supported" (client dies at stream setup) [R2-3][R2-4][R2-9][R2-22].
  Tick math at the odd rate: 5512 → 5.512 frames/ms × 50 ms = 275.6 → truncates to **275 frames ×
  4 B (2ch×16bit) = 1,100 B/tick = 22,000 B/s** (nominal 22,048; 0.22% per-tick truncation,
  absorbed by the stream sync logic). 48000:16:2 → exactly **9,600 B/tick = 192,000 B/s** [R2-1][R2-4].
- **`--logsink` separation:** default sink = `stdout` when not daemonized (v0.35.0 source:
  `settings.logging.sink = "stdout"` unless `--daemon`), so **`--logsink stderr` is required** for the
  stdout-pipe pattern; `--logfilter` defaults to `*:info`. Sinks: null, system, stdout, stderr,
  file:<path> [R2-3][R2-2].
- Consequence for the supervisor: a blocked pipe reader (consumer stops draining) blocks the `fwrite`
  → freezes the single io thread (network reads stop too) → process alive, stdout silent, no
  internal reconnect possible. Distinct from the #1563 hang; same observable (silent stdout) [R2-1].

### 2. Issue #1563 + supervisor design (ask 2)

**Status (verified 2026-11-23 via GitHub API + source):**
- Issue #1563, opened 2026-10-30, **OPEN**: "snapclient file player hangs or crashes on a stream
  change". Symptom: on a stream change the client "occasionally stops completely": stops writing to
  the file, stops time sync (server `lastSeen` freezes **while `connected` stays true**), then either
  spins at 100% CPU (state R, no syscalls) or exits with SIGSEGV (code 139). Repro: file-player
  client + `Group.SetStream` ~10×/sec; hung at 199 / 899 / 1799 / 3099 switches across 4 runs.
  Env: Debian trixie container, 0.31.0 deb; "file_player.cpp is unchanged on develop"; also
  repro'd with self-compiled develop. **=> the bug is present in v0.35.0** (v0.35.0's
  file_player.cpp is byte-identical to the unpatched master version; the destructor still only
  calls `timer_.cancel()` with no alive token) [R2-15][R2-1].
- Root cause (reporter, gdb-confirmed): `FilePlayer::loop()` arms the 50 ms tick with a lambda
  capturing `this`; the controller destroys and recreates the player on **every CodecHeader**
  (stream switch, reconnect); a handler already queued on the io_context cannot be cancelled → when a
  tick and a CodecHeader land in the same event-loop iteration the tick runs on the freed player and
  re-arms a timer in freed memory (use-after-free) [R2-15][R2-1].
- **Fix: PR #1571 (opened 2026-11-09, last updated 2026-11-16) is OPEN, NOT merged** (base=develop,
  1 commit, mergeable_state=unstable). The 5-line patch: a `shared_ptr<bool> alive_` member cleared
  in the destructor; the tick lambda captures `alive` and returns early on `ec || !*alive`.
  Reporter's fork (commit c209249): "with it the client ran 31000 switches without a fault". Maintainer
  badaix endorsed a PR (2026-11-04) but it is unmerged as of 2026-11-23 [R2-15][R2-16].
- Exposure events (server sends a CodecHeader to a client session in exactly three places, v0.35.0
  source): (1) session connect (server.cpp:402 — every (re)connect), (2) `Group.SetStream`
  (control_requests.cpp:478), (3) `Group.SetClients` (control_requests.cpp:555). **Source-side
  flapping (LMS/roc/MusicAssistant restarts) does NOT re-send a header** — the PcmStream persists,
  the reader retries (pipe: 200 ms reopen loop; tcp client mode: 1 s reconnect) and emits silence
  chunks meanwhile; the per-source `idle_threshold` (default 100 ms, URI param) only flips the
  stream status flag (idle vs playing in RPC/UI), it is not a silence cutoff [R2-18][R2-20][R2-21].
  Normal-usage frequency of real CodecHeader events in this cluster: snapserver/pod restarts + owner
  or Music-Assistant stream switches — a few per day at most (the 10×/s repro is adversarial), but
  each event carries a small non-zero race window.

**Supervisor design (evidence-grounded input for the plan):**
- Expected healthy cadence: a burst (≥1 byte) every 50 ms — 9,600 B/tick (48k) or 1,100 B/tick
  (5512); starved/dead upstream sources do NOT change cadence (silence is written) [R2-1][R2-5][R2-18].
- Failure-mode map: (a) crash — child exit 139, trivial; (b) **#1563 hang — process alive (state R),
  stdout + stderr silent, server shows connected:true / frozen lastSeen: detectable ONLY by a
  client-side byte-cadence watchdog** (server-side health checks cannot see it); (c) pipe backpressure
  freeze (consumer stopped reading) — same observable; (d) **server outage — legitimate:
  `reconnect()` destroys the player (stdout fully silent) and retries connect every 1 s forever
  (no backoff, no give-up); stderr shows "Reconnecting" — must NOT kill the client in this window;
  distinguish via stderr log lines or an external snapserver liveness check** [R2-6][R2-15].
- Recommended watchdog shape: startup grace ~10–30 s (connect + hello + ServerSettings + CodecHeader
  before the first tick); kill threshold ~500 ms (10 ticks) of zero bytes, extended to minutes when
  stderr recently logged "Reconnecting"/"Connecting to host" or the snapserver pod/service is
  known-down; **SIGKILL** (a #1563-hung process spins — SIGTERM's io_context stop may never run);
  respawn with the same args (the client self-reconnects to the server in ~1 s internally, so a few
  seconds of respawn delay is plenty); no backoff per-kill (the 1 s internal retry exists), but an
  escalation counter (e.g. ≥3 kills in 5 min → alert + 30–60 s respawn delay) against hot loops;
  secondary signal: tail stderr for "Version " / "Connected to" / "Reconnecting" / "Snapclient
  terminated." [R2-6][R2-15].
- Long-term mitigation options (plan decision): (i) track PR #1571 and adopt the fixed release when
  it ships; (ii) vendor the 5-line patch (it touches only client/player/file_player.{cpp,hpp}) when
  building snapclient from source in the Dockerfile — but the default packaging recommendation below
  is the prebuilt deb, so (i) or a patched side-build is the realistic paths; (iii) rely on the
  watchdog only. Note the 5-line patch is a clean candidate if the plan chooses a source build.

### 3. Identity + connection (ask 3)

- **`--hostID` pinning (verified in v0.35.0 controller.cpp + utils.hpp):** `if (settings_.host_id.empty())
  settings_.host_id = ::getHostId(macAddress);` — default id = the CONNECTED SOCKET's MAC
  (`getMacAddress` on the fd), falling back to hostname; `getHostId` returns the `--hostID` value as-is
  when set. The server keys persistent client state (group membership, volume, latency — server.json)
  by that id. **k8s pod MACs are random per pod → without a pinned `--hostID`, every pod recreation =
  a brand-new client = a fresh auto-created group.** Pin e.g. `--hostID audio-ad-detection`.
  (`--instance N` gives the `#N` id suffix for multiple instances per host.) [R2-6][R2-23]
- **URL-form server arg:** positional `[url]` = `<tcp|ws|wss>://<host or IP or mDNS name>[:port]`;
  `--host`/`--port` are deprecated since v0.32.0 (changelog: "Command line arguments '--host' and
  '--port' are deprecated"; man page marks them "(deprecated, use [url])"); missing port defaults
  tcp→1704, ws→1780, wss→1788; URL userinfo → Basic auth; no URL + no mDNS = hard error. So the
  in-cluster form is `tcp://home-snapcast:1704` (the nameOverride-collapsed DNS name, EXPLORE §4).
  The URL form has existed since v0.32.0 (which also added the ws/wss client, Issue #1325) [R2-2][R2-22].
- **Ports (v0.35.0 server_settings.hpp defaults; control_server.cpp multiplexes one acceptor):**
  1704 = tcp stream (the ONLY port the audio client needs), 1705 = raw-TCP JSON-RPC, 1780 = HTTP
  JSON-RPC (+snapweb UI), 1788 = HTTPS/WSS. 0.33.0 added an option to disable 1704 TCP streaming —
  not set here. For the worker: 1704 for audio; 1780 (or 1705) additionally only if the worker/HA
  uses JSON-RPC to enumerate/choose streams. The live `home-snapcast` LB already exposes
  1704/1705/1953→4953 and a separate 1780 service (EXPLORE §4) [R2-25][R2-17].
- **Reconnection when snapserver restarts (v0.35.0 controller.cpp):** any read/send error or failed
  connect/hello → `reconnect()`: disconnect, player_/stream_/decoder_ reset (file player destroyed →
  stdout fully silent), then `worker()` after a FIXED 1 s delay — no backoff, infinite retries. On
  re-hello a fresh CodecHeader arrives → FilePlayer rebuilt from scratch (a #1563 exposure event) →
  audio resumes after the ~500 ms client buffer fills (server buffer here is 700 ms, EXPLORE §4);
  silence is written in the gap, so the pipe cadence shows a silent-but-alive stretch only in the
  (d)-case above. Clean shutdown: SIGHUP/SIGINT/SIGTERM → io_context.stop() → "Snapclient
  terminated.", exit 0 [R2-6][R2-26].

### 4. Packaging (ask 4)

**Release v0.35.0 (published 2026-03-10; repo moved to github.com/snapcast/snapcast in this release,
Issue #1458; 46 assets per the GitHub API — 27 snapclient debs + 18 snapserver debs + win zip):**
- Asset naming (exact, verified via the releases API): `snapclient_0.35.0-1_<arch>_<debian>.deb` and
  `_with-pulse` / `_with-pipewire` variants for arch ∈ {amd64, arm64, armhf} × debian ∈
  {bullseye, bookworm, trixie} — **arm64 debs exist in the official release for all three debian
  releases and all three flavors** (the intake's arm64 claim is TRUE at upstream level; what actually
  matters here: the home node is amd64 and the repo build pipeline is single-arch amd64 (EXPLORE
  §1/§7.7), so use the amd64 deb — arm64 is future-proofing only) [R2-10][R2-11].
- The in-repo `containers/snapcast` image (serving home-snapcast) pins **snapserver 0.28.0**
  (wget of the v0.28.0 release zip) — the deployed server is 0.28.0, not 0.35.0. Consequences: no
  `default_source` server feature (a 0.35.0 feature, PR #1494 merged 2026-02-27); a new client's
  auto-created group is assigned the FIRST non-null-codec source in config order
  (`StreamManager::getDefaultStream` with no `default_source`). The JSON-RPC surface (Groups since
  0.11.0, HTTP RPC since 0.16.0) predates 0.28.0, so the control methods in §5 exist in the deployed
  server. The snapclient side is a separate binary — its 0.35.0 (worker) vs 0.28.0 (server) pairing
  is fine: the wire protocol is stable (the 0.31.0+ RPC-only changes are server-side) [R2-11][R2-27].
- **Flavors (`.github/workflows/package.yml` matrix, workflow_dispatch-only builds):** per
  (debian, arch) three builds — plain (default CMake), `_with-pulse` (`-DBUILD_WITH_PULSE=ON`),
  `_with-pipewire` (`-DBUILD_WITH_PIPEWIRE=ON`); the build env installs libsoxr-dev + all decoder
  libs in every flavor, and CMake auto-detects SOXR (`pkg_search_module(SOXR soxr)`, non-required)
  → **every published deb, plain included, is a SOXR build** → `--sampleformat` is available in the
  plain package [R2-12][R2-13].
- **The plain package (verified by downloading the actual artifact):**
  `snapclient_0.35.0-1_amd64_bookworm.deb` (591,928 B): `Depends: libasound2, libavahi-client3,
  libavahi-common3, libc6, libflac12, libgcc-s1, libogg0, libopus0, libsoxr0, libssl3, libstdc++6,
  libvorbis0a, adduser`; `Recommends: avahi-daemon`; contents = `/usr/bin/snapclient` (1.85 MB,
  dynamically linked — ldd shows no libpulse/libpipewire) + inert init/systemd files. **Plain
  suffices for the file player and pulls no audio-server dependencies** (libasound is a library, not
  a daemon, and only the alsa player would use it; avahi-daemon is a Recommends for mDNS browsing,
  unneeded with an explicit URL — use `--no-install-recommends`) [R2-14].
- **Distro/apt/static availability:** `snapcast` is NOT in Debian bookworm/trixie/sid
  (packages.debian.org: "No such package"); upstream doc/install.md says to download the package from
  the latest release page and `apt install </path/to/deb>`; no static binary in the release (debs +
  win zip only). **The clean Dockerfile leg: `debian:bookworm-slim` + wget
  `https://github.com/snapcast/snapcast/releases/download/v0.35.0/snapclient_0.35.0-1_amd64_bookworm.deb`
  + `apt-get install -y --no-install-recommends ./snapclient_*.deb`** (auto-resolves the 10 shlibs
  from bookworm apt). The deb's version string is `<ver>-1`, so the URL is version-stable for
  Renovate pinning (github-releases datasource, the repo's ARG-pin comment shape). Building from
  source is possible but heavy (boost 1.89 + soxr + decoder stack) and only worth it to vendor the
  #1563 patch [R2-12][R2-14][R2-28].
- The in-repo `containers/snapcast` image contains **snapserver only — no snapclient** (EXPLORE §4);
  the worker image is a separate container (new `containers/<name>/` per EXPLORE §1 conventions) and
  does not reuse that image.

### 5. Server-side tap alternative + JSON-RPC surface (ask 5)

**One comparative verdict: client-side snapclient file player (the ticket's design) wins for this
cluster.** Grounds (v0.35.0 source): snapcast has NO "mirror/tee" source type and NO API that
exposes a stream's raw PCM to an external reader — audio leaves the server ONLY through 1704 client
sessions (or the ws/wss equivalents). A `tcp` source is an INPUT (mode=server: external device pushes
PCM in on 4953; mode=client: the server pulls from a remote source). The only server-side variant is
a `meta:///<target>` stream (mixes other streams into a new stream without draining the originals) +
a dedicated group — which (a) needs the same snapclient file player on the worker anyway, (b) adds a
mix path (server CPU on the home node), and (c) requires a `snapserver.conf` change via Helm values
(server restart on change). It avoids nothing: the worker IS the consumer, and a single extra 1704
client session is negligible. Client-side tap = no server config churn, works on the deployed 0.28.0
server as-is, independently supervised pod [R2-18][R2-20][R2-21][R2-19].

**JSON-RPC control surface (what exists, for the owner's stream-choice decision — EXPLORE OQ2):**
- Transport: raw TCP 1705, HTTP(S) 1780/1788, WebSockets (long-lived sessions receive Notifications);
  JSON-RPC 2.0; self-describing via `General.GetRPCCommands`; RPC version 23.0.0 in v0.35.0
  (`Server.GetRPCVersion`) — the deployed 0.28.0 reports an earlier version; verify at runtime in the
  Test phase (all methods below predate 0.28.0, except noted) [R2-17][R2-25].
- **Auth is opt-in** (`authinfo.cpp`: `if (!auth_settings_.enabled) return true;`): with no `[auth]`
  section in snapserver.conf (the live home config has none — EXPLORE §4), **all methods are open, no
  token needed**. If the owner ever enables `[auth]`: `Server.Authenticate` (Basic/Plain/Bearer) or
  URL-embedded Basic on the stream side [R2-19].
- Methods (control_requests.cpp): `Server.GetStatus` → `{groups:[{id,name,muted,stream_id,
  clients:[{id,connected,lastSeen,config…}]}], streams:[{id,status,uri{…}}]}` (the enumeration call —
  stream `status` is idle/playing, `uri.raw` shows e.g. `pipe:///tmp/snapfifo?name=…`);
  `Client.GetStatus/SetVolume/SetLatency/SetName`; `Group.GetStatus/SetName/SetMute/SetClients`;
  **`Group.SetStream {id, stream_id}`** — re-points a group at a stream, sending the fresh
  CodecHeader to its connected client sessions (our file player rebuilds — a #1563 exposure event,
  and the PCM stream is briefly silent until the ~500 ms client buffer refills — do it
  deliberately, not in a hot loop); `Stream.Control` (play/pause/stop/playPause/next/previous/
  seek/setPosition); `Stream.SetProperty` (loopStatus/shuffle/volume/mute/rate);
  `Stream.AddStream`/`Stream.RemoveStream` — **re-added in 0.31.0 after the CVE-2023-36177 removal
  in 0.30.0, so NOT available on the deployed 0.28.0 server** (streams are config-defined here
  anyway); `Server.DeleteClient`; `Server.Authenticate`; `General.GetRPCCommands` [R2-17].
- **Worker/HA stream-choice mechanics:** (1) `Server.GetStatus` → find the group whose `clients[]`
  contains the pinned `--hostID`, read its `stream_id`; inspect `streams[]` (status/uri) for
  candidates; (2) `Group.SetStream` to re-point the tap (owner/HA decision per EXPLORE OQ2 — which
  of the live streams — LMS / Roc `SpencersStream` / TCP `MusicAssistant` / fifo `default` /
  combined `Spencer` meta (EXPLORE §4) — to tap is an OWNER decision: it sets the false-positive
  surface, music-only vs all-sources); (3) on the deployed 0.28.0 server a first-ever client
  (pinned hostID) lands in a fresh group playing the FIRST non-null-codec source in config order —
  so the worker should expect a `Group.SetStream` (or config-order reliance) on first boot;
  (4) optional: subscribe to `Group.OnStreamChanged`/`Server.OnUpdate` notifications (ws/1705) or
  poll `Server.GetStatus` every few seconds — polling is simpler and the 0.28.0 server sends the
  same notifications it has always sent [R2-17][R2-18][R2-27].

### Contradictions & how to weigh them

1. **Docs vs code on channels:** man page says `--sampleformat <rate>:<bits>:<channels>` (implying
   channel conversion); the v0.35.0 CLI throws for any numeric channels and the SOXR resampler is
   created with the INPUT channel count (no downmix possible). README's own example uses
   `48000:16:*`. **Weigh: code wins** — `5512:16:*` + downmix in the .NET worker [R2-3][R2-9].
2. **Stale `file_player.hpp` comment** ("doesn't even write the received audio to file … just
   discards it") vs the code (writes + flushes per tick) and the 0.22.0/0.25.0 changelog entries.
   Weigh: code + changelog win [R2-1][R2-22].
3. **Release page HTML "Assets 48" vs GitHub API 46 assets** — the API is the authoritative
   enumeration [R2-11].
4. **`master` branch ≠ v0.35.0 tag** (master CMakeLists VERSION 0.34.0; lacks the tag's SDL2 player
   + `default_source`; GitHub shows "31 commits to develop since this release"). Weigh: cite the
   v0.35.0 tag for release behavior; master for direction only [R2-24][R2-3].
5. **`--host`/`--port` in the man page vs deprecation** (0.32.0 changelog + man page
   "(deprecated, use [url])") — use the URL form; `tcp://host:1704` is the correct 0.35.0 spelling
   [R2-2][R2-22].
6. **Intake/EXPLORE "1704 stream only"** — correct for the audio leg, but the stream-CHOICE feature
   needs 1780 (or 1705) JSON-RPC; the live LB already exposes both (EXPLORE §4) [R2-25].
7. **Server `connected:true` vs actual health** — #1563's signature (frozen `lastSeen`, alive
   client) means the server-side state is NOT a health signal for the client; the supervisor must
   watch the client's pipe, not the server's flags [R2-15].

### Implications for the plan

1. **Command line (verified shape):** `snapclient --player file:filename=stdout
   --sampleformat 5512:16:* --logsink stderr --hostID <stable-id> tcp://home-snapcast:1704`.
   Do NOT write `5512:16:1` (rejected at startup); the .NET worker receives **5512 Hz / 16-bit /
   STEREO** PCM in 1,100-byte-per-50 ms bursts (22,000 B/s) and must downmix to mono float itself.
   (Or omit `--sampleformat` and take 48k/16/2 = 9,600 B/50 ms = 192,000 B/s and resample fully in
   .NET — both cadences are exact integers of the 50 ms tick.) [R2-1][R2-3][R2-4][R2-9]
2. **Supervision is mandatory, not optional** — v0.35.0 ships the #1563 use-after-free (unfixed,
   PR #1571 open). The .NET worker must run snapclient as a child with: stdout byte-cadence watchdog
   (~500 ms kill threshold, startup grace ~10–30 s, outage-tolerance via stderr "Reconnecting"
   lines / external snapserver liveness), SIGKILL+respawn, escalation counter, stderr log tailing
   ("Version " / "Connected to" / "Reconnecting" / "Snapclient terminated."). Plan decision: track
   PR #1571 → adopt the fixed release, or vendor the 5-line patch in a source build, or watchdog-only.
   [R2-15][R2-16]
3. **Pinning is required:** `--hostID <stable>` (else group membership is lost on every pod
   recreation — random pod MACs); the group's initial stream on the deployed 0.28.0 server is the
   first valid source in config order (no `default_source`), so first-boot stream assignment needs a
   `Group.SetStream` or config-order reliance — coupled to the owner's stream-choice decision.
   [R2-6][R2-23][R2-27]
4. **Dockerfile:** `debian:bookworm-slim` + the official `snapclient_0.35.0-1_amd64_bookworm.deb`
   from the GitHub release (`--no-install-recommends`); pin the URL with the repo's renovate
   github-releases ARG-pin comment shape; no audio-server deps are pulled; no apt repo or static
   binary exists upstream. [R2-12][R2-14]
5. **The realtime-source hot-resume requirement from R1** (the SoundFingerprinting realtime command
   re-enumerates the source after transient errors — the source must be hot) intersects the
   supervisor: on a snapclient respawn the pipe restarts from the NEW audio position (silence
   gap); the worker should treat a respawn as a stream discontinuity (flush/advance the realtime
   source rather than replaying), consistent with R1's §1 hot-source contract. [R2-1][R2-6]
6. **Chart/network:** the worker pod needs 1704 (audio) + optionally 1780 (JSON-RPC) to
   `home-snapcast` / `home-snapcast-snapcast-http` — both already exposed by the live services
   (EXPLORE §4); no new server-side surface, no snapserver config change (the tee verdict, §5).
   [R2-17][R2-25]

### Open questions (for the batched round / owner)

1. **Which stream to tap** (EXPLORE OQ2, owner decision): which of the live streams (LMS / Roc
   `SpencersStream` / TCP `MusicAssistant` / fifo `default` / combined `Spencer` meta) should the
   fingerprinter consume — sets the ad false-positive surface (music-only vs all-sources). The
   mechanism to change it at runtime (`Group.SetStream` over 1780, open access on the current
   auth-less server) is documented in §5.
2. **First-boot group assignment on the 0.28.0 server** (no `default_source` feature): rely on
   config-order (first valid source) + a `Group.SetStream` at worker startup, or upgrade the
   in-repo snapcast image to 0.35.0 (new chart value, `default_source` becomes available)? Owner
   call — an upgrade also pulls the SDL2-player build and the 0.33/0.35 server fixes.
3. **#1563 mitigation depth:** watchdog-only (ship now) vs vendor the 5-line PR #1571 patch in a
   source build (Dockerfile complexity) vs wait for the fix to land upstream — plan/owner decision.
4. **Resample boundary:** `--sampleformat 5512:16:*` in snapclient (SOXR in-process, 22,000 B/s
   pipe, .NET downmixes to mono) vs raw 48k/16/2 (192,000 B/s pipe, .NET does rate+bis+channel
   conversion) — CPU trade-off on the single home node (EXPLORE §7.14) vs pipe bandwidth; the
   cadence numbers in §1/Implication-1 are the input.
5. **JSON-RPC version on the deployed 0.28.0 server** — confirm at runtime with
   `Server.GetRPCVersion` in the Test phase (methods used predate 0.28.0; `Stream.Add/RemoveStream`
   is the only 0.28.0 gap, and it is not needed).

### Adjacent (out of R2 core scope, recorded for R3/plan)

- 0.35.0 adds a **SDL2 client player** (`#ifdef HAS_SDL2`, in the tag; absent from `master`) — the
  published plain deb's `ldd` shows NO libSDL2, i.e. the deb build leaves it out; irrelevant to the
  file-player path, recorded to avoid confusion when reading the release notes [R2-10][R2-24].
- `Stream.AddStream`/`Stream.RemoveStream` (dynamic streams via RPC) are absent on the deployed
  0.28.0 server (removed in 0.30.0 for CVE-2023-36177, re-added 0.31.0) — do not plan around them
  on the current server [R2-17][R2-22].
- Adjacent open upstream issue #1570 (2026-11-07): a slow `server.json` write (Config::save holds
  Config::mutex_ after every JSON-RPC request) can stall audio + time sync for ALL clients — a
  server-side stall mode distinct from #1563; relevant to "why did the pipe go quiet" triage
  [R2-29].
- `--daemon`/`--user` exist but are unneeded (k8s runs the process in the foreground; the deb's
  systemd unit is inert in the container) [R2-3][R2-14].

### Sources (R2-local keys)

- [R2-1] `file_player.cpp` at v0.35.0 (downloaded tag tarball; byte-identical to master): 50 ms tick, `getPlayerChunkOrSilence` + `fwrite`+`fflush`, w/a mode check, stdout/stderr/null handling, catch-up skip. https://raw.githubusercontent.com/snapcast/snapcast/v0.35.0/client/player/file_player.cpp
- [R2-2] `snapclient.1` man page (Sep 2025): URL form, `--host`/`--port` deprecation, `--hostID`, `--sampleformat`, `--logsink` values. https://raw.githubusercontent.com/snapcast/snapcast/master/client/snapclient.1
- [R2-3] `snapclient.cpp` at v0.35.0 (fetched at both tag and master — identical for R2-relevant lines): SOXR-gated `--sampleformat`, channels-must-be-`*` validation, bits 16/24/32 check, URL scheme/port defaults (1704/1780/1788), `--hostID` parse, logsink default stdout. https://raw.githubusercontent.com/snapcast/snapcast/v0.35.0/client/snapclient.cpp
- [R2-4] `sample_format.cpp` (v0.35.0 tag via tarball): `*`→0 parsing, frameSize. https://raw.githubusercontent.com/snapcast/snapcast/master/common/sample_format.cpp
- [R2-5] `stream.cpp` (v0.35.0 == master): `getPlayerChunkOrSilence` zero-fill, `addChunk` resample path, 500 ms client buffer. https://raw.githubusercontent.com/snapcast/snapcast/master/client/stream.cpp
- [R2-6] `controller.cpp` (v0.35.0 == master): `reconnect()` fixed 1 s, player reset, `getHostId(macAddress)` default, Hello with host_id, CodecHeader → player rebuild, 50-quick time-sync. https://raw.githubusercontent.com/snapcast/snapcast/master/client/controller.cpp
- [R2-7] `client_connection.cpp` (v0.35.0 == master): synchronous TCP connect, MAC from socket fd, ws/wss variants. https://raw.githubusercontent.com/snapcast/snapcast/master/client/client_connection.cpp
- [R2-8] `resampler.cpp` (v0.35.0 == master): SOXR rate/bits only, `soxr_create(…, in_channels)`, no-SOXR throw. https://raw.githubusercontent.com/snapcast/snapcast/master/common/resampler.cpp
- [R2-9] README.md (v0.35.0 tag): file-player row (filename/mode options), `--sampleformat 48000:16:*` example, JSON-RPC "over plain TCP, HTTP(S), or Websockets", package install pointer. https://github.com/snapcast/snapcast/blob/v0.35.0/README.md
- [R2-10] v0.35.0 release page (published 2026-03-10; release notes: SDL2 client PR #1460, default source PR #1494, repo move Issue #1458). https://github.com/snapcast/snapcast/releases/tag/v0.35.0
- [R2-11] GitHub releases API v0.35.0 asset list (46 assets; exact deb names incl. arm64 across bullseye/bookworm/trixie × plain/with-pulse/with-pipewire). https://api.github.com/repos/snapcast/snapcast/releases/tags/v0.35.0
- [R2-12] `.github/workflows/package.yml` (master): matrix debian{bullseye,bookworm,trixie} × arch{amd64,armhf,arm64}, three flavor builds, workflow_dispatch-only, build-env deps incl. libsoxr-dev. https://raw.githubusercontent.com/snapcast/snapcast/master/.github/workflows/package.yml
- [R2-13] `CMakeLists.txt` (master): `BUILD_WITH_PULSE`/`BUILD_WITH_PIPEWIRE` OFF by default, SOXR `pkg_search_module` (optional, non-REQUIRED), alsa/ssl/flac/vorbis/opus/avahi defaults. https://raw.githubusercontent.com/snapcast/snapcast/master/CMakeLists.txt
- [R2-14] `snapclient_0.35.0-1_amd64_bookworm.deb` — **downloaded and inspected 2026-11-23** (591,928 B; `dpkg-deb -I` control stanza + `ldd` of `/usr/bin/snapclient`; contents list). https://github.com/snapcast/snapcast/releases/download/v0.35.0/snapclient_0.35.0-1_amd64_bookworm.deb
- [R2-15] Issue #1563 (OPEN, opened 2026-10-30): symptom, gdb root cause, repro (199–3099 switches), environment, log shape, fix description. https://github.com/snapcast/snapcast/issues/1563
- [R2-16] PR #1571 (OPEN, created 2026-11-09, updated 2026-11-16, 1 commit, base=develop, mergeable_state=unstable) + its diff (alive_ shared-token patch). https://github.com/snapcast/snapcast/pull/1571 and https://patch-diff.githubusercontent.com/raw/snapcast/snapcast/pull/1571.diff
- [R2-17] `control_requests.cpp` (v0.35.0 == master): full JSON-RPC method list, Group.SetStream mechanics (header send + setPcmStream), GetStatus shapes, Stream.Add/RemoveStream. https://raw.githubusercontent.com/snapcast/snapcast/master/server/control_requests.cpp
- [R2-18] `pipe_stream.cpp` / `tcp_stream.cpp` / `asio_stream.hpp` (v0.35.0 == master): pipe 200 ms reopen loop, tcp 1 s reconnect, `idle_threshold` (default 100 ms) = status flag only, silence-chunk continuation, stream object persistence. https://raw.githubusercontent.com/snapcast/snapcast/master/server/streamreader/pipe_stream.cpp
- [R2-19] `authinfo.cpp` (v0.35.0 == master): `hasPermission` returns true when `auth_settings_.enabled` is false (RPC open without `[auth]`). https://raw.githubusercontent.com/snapcast/snapcast/master/server/authinfo.cpp
- [R2-20] `snapserver.1` man page (Sep 2025) + `server/etc/snapserver.conf` sample (v0.35.0 tag). https://raw.githubusercontent.com/snapcast/snapcast/master/server/snapserver.1
- [R2-21] `doc/configuration.md` (v0.35.0 tag): pipe/tcp/meta source URI syntax + parameters. https://github.com/snapcast/snapcast/blob/v0.35.0/doc/configuration.md
- [R2-22] `changelog.md` (master, through 0.34.0; 0.35.0 section per the release notes): 0.22.0 file backend (Issue #681), 0.23.0 pipe-silence-idle, 0.25.0 file-backend stdout log removal, 0.30.0/0.31.0 AddStream CVE removal/re-add, 0.32.0 `--host`/`--port` deprecation + ws/wss client, 0.33.0 1704-disable option. https://raw.githubusercontent.com/snapcast/snapcast/master/changelog.md
- [R2-23] `common/utils.hpp` `getHostId` (v0.35.0 tag): hostID as-is when set, else socket MAC, else hostname. https://raw.githubusercontent.com/snapcast/snapcast/v0.35.0/common/utils.hpp
- [R2-24] v0.35.0 tag tree vs master tree (GitHub git trees API): tag has `client/player/sdl2_player.{cpp,hpp}` + `default_source` (server/config.cpp, server_settings.hpp, snapserver.cpp, stream_manager.cpp); master (CMakeLists VERSION 0.34.0) lacks them. https://api.github.com/repos/snapcast/snapcast/git/trees/v0.35.0?recursive=1 and https://api.github.com/repos/snapcast/snapcast/git/trees/master?recursive=1
- [R2-25] `server_settings.hpp` port defaults (1780/1788/1705/1704) + `control_server.cpp` acceptor multiplexing + `stream_server.cpp` 1704 acceptor (v0.35.0 == master). https://raw.githubusercontent.com/snapcast/snapcast/master/server/control_server.cpp
- [R2-26] `snapserver.1` FILES section (server.json persistence path) + `server.cpp:402` (CodecHeader on session connect). https://raw.githubusercontent.com/snapcast/snapcast/master/server/server.cpp
- [R2-27] PR #1494 "Add option for a default source" (merged 2026-02-27 → in v0.35.0 only) + `StreamManager::getDefaultStream` (v0.35.0 tag): first non-null-codec stream without `default_source`. https://api.github.com/repos/snapcast/snapcast/pulls/1494
- [R2-28] `doc/install.md` (v0.35.0 tag): "download the package for your CPU architecture from the latest release page" + `apt install </path/to/deb>` (no official apt repo). https://github.com/snapcast/snapcast/blob/v0.35.0/doc/install.md
- [R2-29] Issue #1570 (OPEN, 2026-11-07): slow server.json write stalls audio + time sync (Config::save holds Config::mutex_). https://github.com/snapcast/snapcast/issues/1570
- Negative results (searched 2026-11-23): `snapcast` absent from Debian bookworm/trixie/sid (packages.debian.org "No such package" ×3); no official apt repository; no static binary in the release (debs + win zip only); no other open file-player hang/crash issue besides #1563 (GitHub issue search, "file player").

## R4 — Home Assistant-over-MQTT integration model + broker topology + repo wiring

Grounded 2026-11-23 (Pre Research, thread R4). Method: STORM — 5-perspective survey
(broker topology / MQTT event model / HA automation surface / GitOps repo wiring /
auth & secrets), grounded against primary docs (HA mqtt / event.mqtt / event /
binary_sensor pages, 2024.4 release notes + changelog, Mosquitto app DOCS + manifest,
mosquitto.conf man page, Snapcast README + JSON-RPC control docs, HA core
`mqtt/__init__.py`, k3s Networking Services docs, community threads) plus live probes
(`readonly-global-homeassistant`, `readonly-home-kubernetes`). Inline `[n]` keys refer
to the source list at the end of this section.

### TL;DR

- Prod HA (`home.spencerslab.com`, 2026.10.4) is **outside** the home k3s cluster
  (no pod/service/ingress for it; the node runs openSUSE MicroOS, not HAOS) and is
  today listening on its own `core-mosquitto` add-on broker [5][6][20]. The in-cluster
  `home-mosquitto` (ClusterIP 10.43.74.33:1883, anonymous, mosquitto 2.0.15) does
  **not** reach HA today — the worker must publish to the broker HA actually listens on,
  or the mqtt entry must be re-pointed.
- The MQTT event entity and the `event.mqtt` platform have existed since HA **2023.8**,
  not 2024.4 (the 2024.4 changelog only adds the event platform to rfxtrx) [2][3][4].
  Live-proven on this HA: 10 of 14 `event.*` entities are `platform: mqtt` on the
  `core-mosquitto` entry [20].
- **HA is single-broker**: core keeps one shared `DATA_MQTT` client; a second config
  entry *replaces* the shared client rather than opening a second connection [7].
  "Multiple brokers" means a mosquitto bridge, not multiple HA entries [8].
- Recommended topology: **re-point the existing `core-mosquitto` mqtt entry at
  in-cluster `home-mosquitto`** (one-time HA UI action — the entry reports
  `supports_reconfigure: true`; no HA restart, no broker restart) — contingent on the
  HA host being able to reach 10.43.74.33:1883 (owner-side fact; k3s kube-proxy
  programs service IPs into the node's own netfilter, so a host on home-lab can reach
  ClusterIPs) [7][12][20]. Fallback: keep the add-on broker and give the worker
  Bitwarden/ExternalSecret credentials (zigbee2mqtt precedent shape) [5][6][18].
- Repo wiring: new headless chart + `charts:` key in `services/home/prod/values.yaml`
  (appset-charts matrix pattern; no Chart.lock regen), proxy leg N/A by design
  (commented `#mqtt` trace + documented dev-cluster precedent), no `custom-values/`
  entry unless credentials appear; monitoring via k8s-monitoring (alloy) — both
  discovery paths are live, repo precedent is scrape annotations (radiance D-8);
  liveness via LWT + `expire_after`, never via silence [14]–[19][20].

### Findings

#### 1. Broker topology (live-verified)

- HA 2026.10.4 is RUNNING at `home.spencerslab.com` but there is **no** HA pod,
  service, or ingress in the home k3s cluster (37 cluster ingresses, none matching;
  node `home-lab` is openSUSE MicroOS, not HAOS) [20]. Where HA physically runs is an
  owner-side fact — every topology verdict below is conditional on it (open question 1).
- HA has exactly one mqtt config entry: `core-mosquitto` (`source=hassio`,
  `state=loaded`, entry id `2a63670a676459744b6ff8dea7d209ef`,
  `supports_reconfigure: true`) [20]. Re-pointing it at another broker is therefore a
  one-time HA UI action — no HA restart and no broker restart.
- The in-cluster broker `home-mosquitto` is ClusterIP 10.43.74.33:1883 (mosquitto
  2.0.15, pod Running; configmap `home-mosquitto-config`, 1 key; **anonymous** — no
  Bitwarden item exists for it and none is needed if it wins) [14][20]. It is
  ClusterIP-only: `services/home/prod/values.yaml` carries a commented
  `#mqtt: serviceName: mosquitto / service: home-mosquitto` trace in the
  `ingress.subdomains` block (lines 153–156), i.e. no ingress by design [15].
- HA is not connected to `home-mosquitto` today: the loaded entry points at the
  `core-mosquitto` add-on broker. A worker publishing to `home-mosquitto` is invisible
  to HA until the entry is re-pointed (option a) or the worker is given credentials
  against the add-on broker (option c).
- HAOS Mosquitto app facts (the add-on behind `core-mosquitto`): **no anonymous
  logins** ("This app does not support anonymous logins; all connections must use a
  username/password to connect. allow_anonymous true nor any anonymous ACLs will not
  work with this app"), a `logins` config option, reserved `homeassistant`/`addons`
  users with unrestricted readwrite when no ACL file is present, and ports 1883/1884
  (plus 8883/8884 TLS) exposed on the host by default (the app manifest maps them 1:1;
  "Remove the ports from the app page network card (set them as blank) to disable them")
  [5][6].

#### 2. Why not a second broker entry (option d — invalid)

- The current core code is decisive: `homeassistant/components/mqtt/__init__.py` keeps
  one shared `hass.data[DATA_MQTT]` client; on a second config entry's setup,
  `mqtt_data.client` is **replaced**, not a second connection opened — one shared
  availability future, one global discovery start/stop [7]. A second entry does not
  give HA a second broker.
- Community corroboration (treated as user reports; the code is the authority): "You
  can't [have multiple brokers]. You need to setup a mqtt bridge" [8]. (The 2023.6
  changelog lists mqtt fixes but no multiple-broker feature [13].)
- Consequence: one HA instance = one broker. The only supported way to serve two
  brokers to one HA is a mosquitto **bridge** (option b — rejected below).

#### 3. Event model (MQTT → HA)

- Version claim: the event entity and the MQTT event platform were both introduced in
  HA **2023.8** [2][3]; the 2024.4 release notes/changelog contain only "Add event
  platform to rfxtrx" [4]. The brief's "2024.4+ event platform" framing is off by a
  release — the capability is real and older, and live-proven here: 10 of 14 `event.*`
  entities on this HA are `platform: mqtt` on the `core-mosquitto` entry [20].
- **Device discovery** (the way the worker should register its entities): publish a
  retained JSON payload to `homeassistant/device/<object_id>/config` with `dev`
  (ids/name/mf/mdl/sw), `o` (origin, required), and `cmps` (per component `p` +
  `uniq_id`) [1]. For the event entity per component: `p: "event"`, `stat_t` (state
  topic, required; the payload must be a JSON object with `event_type`), `evt_typ`
  (optional event_types filter), `av_t` (availability topic; default payloads
  `online`/`offline`, mode `latest`), `exp_aft` (expire_after, seconds) [1][2]. The
  event entity's state is the timestamp of the last event [3].
- **QoS / retain rules**: a discovery payload may be sent retained and is checked like
  a config.yaml entry; a retained discovery message that is never removed "can create
  ghost entities that keep coming back" — removal = send an empty retained payload to
  the same topic [1]. Event **state messages must never be retained** — "replayed
  retained messages will be discarded" [2]. MQTT protocol version 5 is required for the
  integration [1].
- Event device classes are limited to `button`, `doorbell`, `motion` [3] — none fits
  "ad detected", so the event entity needs no device class (it carries
  `event_type: ad_detected` instead).
- `binary_sensor` device classes: there is **no `ad` class; `sound` exists** (on =
  sound detected). Use `dev_cla: "sound"` (an ad playing is a detected sound) or omit
  the class; do not invent one [21].
- **Sample discovery payload** (worker → broker, retained once at startup):

```json
{
  "dev": { "ids": "audio-ad-detector-01", "name": "Audio Ad Detector",
           "mf": "SpencersLab", "mdl": "audio-ad-detector", "sw": "<version>" },
  "o": { "sw": "audio-ad-detector/<version>", "via": "homeassistant" },
  "cmps": [
    { "p": "binary_sensor", "uniq_id": "ad_playing", "name": "Ad playing",
      "dev_cla": "sound", "stat_t": "audio-ad-detector/status",
      "av_t": "audio-ad-detector/lwt", "exp_aft": 300 },
    { "p": "sensor", "uniq_id": "last_ad", "name": "Last ad",
      "stat_t": "audio-ad-detector/last-ad", "av_t": "audio-ad-detector/lwt",
      "exp_aft": 300 },
    { "p": "event", "uniq_id": "ad_event", "name": "Ad event",
      "stat_t": "audio-ad-detector/ad-event", "evt_typ": ["ad_detected"],
      "av_t": "audio-ad-detector/lwt", "exp_aft": 300 }
  ]
}
```

- **Liveness model**: the worker sets a broker-side LWT on
  `audio-ad-detector/lwt` (payload `offline`, retain, QoS 1) and publishes `online` on
  connect; `exp_aft` (expire_after) is the second liveness mechanism — the entity
  expires N seconds after the last state. Never rely on silence for liveness (same
  rule as the monitoring findings below).

#### 4. HA automation surface

- **`event.received` trigger** (event integration, 2023.8): target `entity_id` plus
  optional `event_type` filter; the docs' own example is a doorbell-notification
  automation — the direct pattern for "on `event.audio_ad_detector_ad_event` received
  `ad_detected` → …" [3].
- **Mute**: all 10 snapcast clients are `media_player` entities (alongside
  `media_player.big_tv`, `media_player.lms`); `media_player.mute` works on any of
  them [20]. The HA `snapcast` integration (custom, loaded, `source=user`) exposes only
  `restore` / `set_latency` / `snapshot` services — no stream control [20].
- **Stream switching**: the snapcast control plane is **JSON-RPC 2.0** — plain TCP 1705
  (ndjson frames), HTTP 1780 `POST /jsonrpc` (one-shot), or WebSocket [10][11]. The
  methods needed exist: `Group.SetMute` `{"mute": true}`, `Group.SetStream`
  `{"stream_id": ...}`, `Client.SetVolume` `{"muted": bool, "percent": n}`,
  `Stream.Control` [11]. `home-snapcast` is a LoadBalancer at 10.0.3.78 (1704/1705/4953)
  plus the 1780 HTTP service — routable from the cluster and from the host [20].
- **Gap**: this HA has no `rest` / `rest_command` config entries (live-verified) [20].
  If HA-side automation must call the JSON-RPC endpoint, the automation needs a
  rest_command service — or the worker itself performs the mute/stream switch and
  publishes the resulting event (recommended split: **worker acts, HA reacts**).

#### 5. Repo wiring (GitOps)

- **Headless chart pattern**: new `charts/<name>/` chart + a `charts:` entry in
  `services/home/prod/values.yaml`. The `charts:` key drives one ArgoCD Application per
  appName (matrix generator; per-app config = top-level `<appName>:` block; release name
  `<serviceName>-<appName>` → `home-<appName>`, namespace `default`) [17][15]. This is
  the pattern-a path — no Chart.yaml dependency, hence **no Chart.lock regen**. (Contrast:
  the dev cluster wires its mosquitto via a Chart.yaml dependency (pattern b) —
  `lmatfy/mosquitto 0.1.1` — which is why `home-mosquitto` uses the external chart and
  the in-repo `charts/mosquitto` chart is the headless shape to copy) [14][15][16].
- **Proxy leg N/A by design**: the commented `#mqtt` trace in
  `services/home/prod/values.yaml` ingress.subdomains (lines 153–156) and the documented
  dev posture ("ClusterIP-only, no ingress.subdomains entry … the service trio's proxy
  leg is N/A by design, not an oversight (OQ-C2)") — the worker is a ClusterIP-only
  service, no ingress entry [15][16].
- **Secrets**: none if `home-mosquitto` (anonymous) wins. If the add-on broker wins,
  follow the repo hard rule (ExternalSecret + Bitwarden only): `bitwardenIds.<key>` UUID
  in `custom-values/home/prod-values.yaml` (sentinel in chart values) + an
  `external-secrets.io/v1` ExternalSecret in the chart (`spec.target.name:
  <release>-secret`, `creationPolicy: Owner`, template engineVersion v2,
  `bitwarden-uri` whole item + `bitwarden-login` username/password properties) — the
  canonical shape is `charts/zigbee2mqtt/templates/secret-zigbee2mqtt.yaml` [18].
- **Monitoring**: the home cluster runs k8s-monitoring v4 (alloy) with **both**
  discovery paths enabled — `prometheusOperatorObjects.enabled: true` (ServiceMonitor /
  PodMonitor CRDs via the prometheus-operator-crds 32.0.2 dependency) and
  `annotationAutodiscovery.enabled: true` — either works. The repo precedent is
  annotation-only (charts/radiance tests, D-8: radiance may use only `prometheus.io/*`
  annotations; no ServiceMonitor/PodMonitor) — follow it: expose worker metrics on a
  port with `prometheus.io/scrape` annotations. Liveness: LWT + `expire_after` (MQTT
  side) and standard k8s probes (chart side); **never** silence-based [19][20].

#### 6. Broker-topology verdict

- **(a) Re-point the existing `core-mosquitto` mqtt entry at in-cluster
  `home-mosquitto` — recommended.** One-time HA UI action (`supports_reconfigure:
  true`; no HA restart, no broker restart); zero new credentials (home-mosquitto is
  anonymous); all future mqtt discovery from any in-cluster worker converges on one
  GitOps-managed broker. Contingent on open question 1 (HA host reachability to
  10.43.74.33:1883) [5][7][14][15][20].
- **(c) Keep the add-on broker + worker credentials — fallback.** HA stays on
  `core-mosquitto`; the worker authenticates against it (username/password mandatory —
  the app forbids anonymous), credential via Bitwarden item + ExternalSecret
  (zigbee2mqtt shape) + `custom-values/` entry [5][6][18]. Requires the add-on's 1883
  to be exposed on the host (default) and a Bitwarden item created.
- **(b) Mosquitto bridge — rejected.** The `mosquitto.conf` bridge stanza is real
  (`connection`/`address`/`topic <pattern> [in|out|both] [qos] [local-prefix]
  [remote-prefix]`, `remote_username`/`remote_password`, `start_type automatic`, LWT
  notifications to `$SYS/broker/connection/<id>/state`), but the in-repo chart templates
  no bridge stanza and the broker config is a GitOps-managed ConfigMap — bridging would
  add an out-of-repo moving part for a problem (a) solves directly [9][14].
- **(d) Multiple mqtt config entries — invalid.** Single shared client in core; the
  second entry replaces the first [7][8].

### Contradictions (and how to weigh them)

1. **"HA 2024.4 added the event platform" (brief) vs docs footers "introduced in
   2023.8"** [2][3][4] — the docs win; the capability is real, older than the brief
   claims, and live-proven on this HA [20]. The plan can rely on it without a 2024.4+
   version caveat.
2. **Community "one broker only" (2023–2024 threads) vs "HA supports multiple broker
   entries"** [8][13] — the current core code is the tie-breaker: single shared
   `DATA_MQTT` client, second entry replaces it [7]. Treat one HA instance = one broker.
3. **"HA runs on node home-lab (HAOS-style)" (EXPLORE hypothesis) vs live evidence**
   [20] — no HA in the cluster, MicroOS node. HA's physical location is owner-side;
   topology verdicts are conditional on it.
4. **Anonymous vs authenticated broker regimes** — in-cluster broker anonymous [14][20];
   HAOS app forbids anonymous [5][6]. The worker's credential requirement flips on which
   broker wins (open questions 2/3).
5. **No `ad` binary device class; `sound` exists** [21] — use `dev_cla: "sound"`
   (on = ad playing is a detected sound) or no class; do not invent one.

### Implications for the plan

- Plan the worker to publish to `home-mosquitto` on topics `audio-ad-detector/*` by
  default (verdict a); make broker host/port and optional username/password config so
  fallback (c) costs no code change.
- Do **not** plan a second HA mqtt entry or a bridge; do **not** wait on 2024.4+ —
  2023.8+ suffices and the live HA (2026.10.4) is proven.
- Include in the plan: the retained device-discovery payload (sample above), LWT `offline`
  on `audio-ad-detector/lwt`, `exp_aft`, non-retained event state, `event.received`-
  triggered HA automations (owner to choose: mute clients vs switch the group stream vs
  notify), and — if HA-side stream switching is wanted — a rest_command service or
  worker-side JSON-RPC `Group.SetStream` / `Group.SetMute` at 10.0.3.78:1705/1780.
- Repo-side plan items: new headless chart + `charts:` entry (no Chart.lock regen, no
  proxy entry), a `custom-values/` entry only if fallback (c) is chosen, and
  scrape-annotation monitoring per radiance D-8.

### Open questions (owner side)

1. Where does HA run, and can its host reach 10.43.74.33:1883? (Decides verdict (a)
   viability; if HA is on home-lab, k3s kube-proxy makes the node's ClusterIP reachable
   [12].)
2. Broker verdict: (a) re-point the HA entry at `home-mosquitto` vs (c) keep the add-on
   broker with credentials — and if (c), is the add-on's 1883 exposed on the LAN
   (default is yes [5][6])?
3. Which snapcast stream to tap for fingerprinting (meta mix vs a specific source).
4. Which HA automations to build: mute the snapcast clients, switch the group stream,
   or notify only.
5. If (c) is chosen: who creates the mosquitto `logins` entry / Bitwarden item for the
   worker credential.

### Sources (this section)

1. HA MQTT integration docs — https://www.home-assistant.io/integrations/mqtt/ (platform
   table Event | YAML ✅ | Discovery ✅; discovery topic scheme; device-discovery payload
   `dev`+`o`+`cmps`; retain/ghost warning; birth/will defaults; availability options;
   abbreviations incl. `stat_t`, `uniq_id`, `av_t`, `exp_aft`, `dev_cla`; empty-payload
   removal; MQTT v5 required; `mqtt.publish` / `mqtt` trigger)
2. HA MQTT Event docs — https://www.home-assistant.io/integrations/event.mqtt/
   ("introduced in Home Assistant 2023.8"; `state_topic` + JSON payload with required
   `event_type`; extra keys → attributes; "replayed retained messages will be discarded";
   discovery via device discovery `"platform": "event"`; `qos` default 0)
3. HA Event integration docs — https://www.home-assistant.io/integrations/event/
   ("introduced in Home Assistant 2023.8"; state = timestamp of last event; device
   classes button/doorbell/motion; `event.received` trigger with `event_type` filter;
   doorbell notification example)
4. HA 2024.4 release notes + changelog — https://www.home-assistant.io/blog/2024/04/03/release-20244/
   and https://www.home-assistant.io/changelogs/core-2024.4/ (only event-platform entry:
   "Add event platform to rfxtrx (#111526)")
5. HA Mosquitto app DOCS.md — https://raw.githubusercontent.com/home-assistant/hassio-addons/master/mosquitto/DOCS.md
   (no anonymous logins; 1883/1884 exposed by default, removable via the app network
   card; `logins` option; reserved `homeassistant`/`addons` users)
6. HA Mosquitto app manifest — https://raw.githubusercontent.com/home-assistant/app-mosquitto/main/mosquitto/config.yaml
   (ports 1883/tcp:1883, 1884/tcp:1884, 8883/tcp:8883, 8884/tcp:8884 mapped to the
   host; `auth_api: true`; `discovery: [mqtt]`)
7. HA core `homeassistant/components/mqtt/__init__.py` (dev) —
   https://raw.githubusercontent.com/home-assistant/core/dev/homeassistant/components/mqtt/__init__.py
   (single shared `hass.data[DATA_MQTT]` client; a second config entry replaces
   `mqtt_data.client`; shared availability future; global discovery start/stop)
8. HA community threads — https://community.home-assistant.io/t/connecting-ha-to-multiple-mqtt-brokers/610680
   and https://community.home-assistant.io/t/please-support-two-or-more-brokers-for-mqtt-integration/692613
   ("You can't [have multiple brokers]. You need to setup a mqtt bridge" — user reports;
   [7] is the authority)
9. mosquitto.conf man page — https://mosquitto.org/man/mosquitto-conf-5.html (bridge
   stanzas: `connection`/`address`/`topic <pattern> [in|out|both] [qos] [local-prefix]
   [remote-prefix]`, `remote_username`/`remote_password`, `start_type automatic|lazy|once`,
   LWT notifications to `$SYS/broker/connection/<id>/state`; `allow_anonymous` semantics)
10. Snapcast README — https://github.com/snapcast/snapcast (control via JSON-RPC API over
   plain TCP 1705, HTTP(S) 1780, or Websockets; `meta` stream source)
11. Snapcast JSON-RPC control API docs —
   https://raw.githubusercontent.com/snapcast/snapcast/develop/doc/json_rpc_api/control.md
   (`Client.SetVolume {"muted","percent"}`, `Group.SetMute {"mute"}`,
   `Group.SetStream {"stream_id"}`, `Group.GetStatus`, `Server.GetStatus`,
   `Stream.Control`; one-shot `POST /jsonrpc` on 1780)
12. k3s Networking Services docs — https://docs.k3s.io/networking/networking-services
   (ServiceLB hostPort model; traffic arriving at the LoadBalancer address is intercepted
   by kube-proxy iptables/ipvs and forwarded to the ClusterIP; service IPs are programmed
   into the node's own netfilter, so the node host can reach service IPs)
13. HA 2023.6 changelog — https://www.home-assistant.io/changelogs/core-2023.6/ (mqtt
   fixes; no multiple-broker feature — weak source, [7] is the authority)
14. Repo `charts/mosquitto/{Chart.yaml,values.yaml,templates/configmap-mosquitto.yaml}` +
   `services/home/prod/Chart.yaml` (lmatfy/mosquitto 0.1.1 dependency; in-repo broker
   chart shape: anonymous, ClusterIP, no ingress/secrets)
15. Repo `services/home/prod/values.yaml` (`charts:` entries incl. headless
   `k8s-monitoring` line 76; commented `#mqtt` ingress trace lines 153–156)
16. Repo `services/dev/prod/values.yaml` (documented N/A-by-design proxy leg: dev mosquitto
   "ClusterIP-only, no ingress.subdomains entry … the service trio's proxy leg is N/A by
   design, not an oversight (OQ-C2)"; cf-93 dev pair dev-home-assistant + dev-mosquitto)
17. Repo `charts/base/templates/appset-charts.yaml` (`charts:` key → one Application per
   appName; release `{{ serviceName }}-{{ appName }}`; per-app top-level `<appName>:`
   block; namespace default `default`)
18. Repo `charts/zigbee2mqtt/templates/secret-zigbee2mqtt.yaml` (ExternalSecret canonical
   shape: `external-secrets.io/v1`, `spec.target.name: <release>-secret`,
   `creationPolicy: Owner`, template engineVersion v2, `bitwarden-uri` whole item +
   `bitwarden-login` username/password properties, keyed by `bitwardenIds.<key>`)
19. Repo `charts/k8s-monitoring/values.yaml` + `Chart.yaml` + `services/monitoring/prod/values.yaml`
   + `charts/radiance/tests/test_scrape_annotations.py` (both discovery paths enabled:
   `prometheusOperatorObjects.enabled: true` with prometheus-operator-crds 32.0.2 and
   `annotationAutodiscovery.enabled: true`; radiance D-8 annotation-only precedent)
20. Live probes 2026-11-23 (`readonly-global-homeassistant`, `readonly-home-kubernetes`):
   HA 2026.10.4 RUNNING (home.spencerslab.com); exactly one mqtt entry `core-mosquitto`
   (source=hassio, loaded, supports_reconfigure); 14 event entities, 10 `platform: mqtt`
   on it; 34 mqtt binary_sensors; 18 media_players (10 snapcast clients, big_tv/vizio,
   lms/squeezebox, 3 mqtt_media_player, 2 companion); `snapcast` entry (source=user,
   loaded; only restore/set_latency/snapshot services); no rest/rest_command entries; 83
   automations. Home cluster: k3s v1.37.1, single node home-lab (10.0.3.78, openSUSE
   MicroOS); `home-mosquitto` ClusterIP 10.43.74.33:1883 (mosquitto 2.0.15, running,
   anonymous config); `home-snapcast` LoadBalancer 10.0.3.78 (1704/1705/4953) + 1780 HTTP
   + roc LB; no HA pod/service/ingress in the cluster (37 ingresses, none matching)
21. HA binary_sensor docs — https://www.home-assistant.io/integrations/binary_sensor/
   (device class list: no `ad`; `sound` present)

## Post Research — 18.0.0 parity, #1571 status, recurrence-promotion precedent

Grounded 2026-11-24 (Post Research round, single session). Scope: (1) SF 18.0.0 parity
vs R1's 17.4.0-verified contract; (2) snapcast issue #1563 / PR #1571 current status;
(3) recurrence-based auto-promotion precedent and an assessment of the owner-ruled C02b
guardrail defaults (value-only). Method: tag-to-tag raw source diff (v17.4.0 vs v18.0.0),
NuGet 17.4.0/18.0.0 package pages for both packages (dependency floors + release notes +
version matrix), GitHub release/issue APIs (soundfingerprinting + snapcast), Docker Hub
tags, SearXNG sweeps. Inline [Pn] keys refer to the sources at the end of this section.

### TL;DR

- **18.0.0 is pin-safe.** The core realtime/storage files (`RealtimeQueryConfiguration.cs`,
  `IRealtimeSource.cs`, `InMemoryModelService.cs`) are **byte-identical** between tag
  v17.4.0 and tag v18.0.0 [P3]; the entire 17.4.0→18.0.0 delta is one release-note line —
  a netstandard2.0 library with 11.0.0 dependency floors [P1][P4][P5]. No blocker found:
  confirm the 18.0.0 pin; the recorded 17.4.x fallback stays as the one-line rollback.
- **PR #1571 is still open / unmerged** (no review activity since 2026-11-16); issue
  #1563 is open; v0.35.0 is still the newest release — the owner's watchdog-only posture
  stands, the "revisit when #1571 merges" trigger has not fired [P12][P13][P14].
- Recurrence-based ad self-discovery is a **shipped vendor feature** ("Emy discovers new
  ads on its own by spotting content that repeats" [P15]; "repeating content detection"
  is a listed Emy use case [P16]) with a production-scale cross-day fingerprint-DB
  precedent [P18], but **no published recurrence thresholds exist** — the owner's
  guardrail defaults (2 sightings / 24 h gap / proximity dedup / 20 per day / audit flag /
  manual lane) are sane as recorded; **no value changes recommended** [P21].

### 1. SF 18.0.0 parity (subject 1)

**Verdict: pin-safe — confirm the 18.0.0 pin.** R1's 17.4.0-verified contract holds
verbatim at 18.0.0:

- **Tag-to-tag source diff (raw fetches, 2026-11-24):** `RealtimeQueryConfiguration.cs`,
  `IRealtimeSource.cs` and `InMemoryModelService.cs` at tag `v18.0.0` are **byte-identical**
  to tag `v17.4.0` [P3]. Consequently every R1 contract item — the Task-returning awaited
  realtime callbacks, the hot-source requirement with all six `From` overloads,
  `Snapshot(string path)` + the load-from-directory ctor, `OngoingEntryStalenessCeiling`
  (default `double.MaxValue`), `SeamJumpPolicy` incl. `NewOccurrenceAbove` — exists at
  18.0.0 exactly as R1 verified it at 17.4.0. The 10,240-sample @5512 chunk rule and the
  `BlockingRealtimeCollection` adapter ride on the wiki/gist (R1 [10][11]); the wiki is
  unchanged and `IRealtimeSource` is byte-identical, so nothing there moved.
- **The whole 17.4.0→18.0.0 delta is a dependency floor.** The 18.0.0 release note is a
  single line: "Target .NET 11: the test project builds on net11.0 and the package
  references the 11.0 Microsoft.Bcl.AsyncInterfaces and Microsoft.Extensions.Logging.
  Abstractions; the library itself stays netstandard2.0" [P1]. Both tags' csproj:
  `TargetFramework` netstandard2.0 [P1][P2]. NuGet floors: 17.4.0 = Bcl ≥ 10.0.0,
  M.E.Logging.Abstractions ≥ 10.0.0, protobuf-net ≥ 3.4.40 [P4]; 18.0.0 = Bcl ≥ 11.0.0,
  M.E.Logging.Abstractions ≥ 11.0.0, protobuf-net ≥ 3.4.40 (unchanged) [P5]; protobuf-net
  3.4.40 has been the floor since 16.2.0 [P4]. On a .NET 10 worker the 11.0.0 floors are
  API-compatible assembly-version bumps of in-box packages (`Bcl.AsyncInterfaces`'
  `IAsyncEnumerable` surface is in-box since .NET 5, so that floor is inert on net10) —
  no runtime blocker [P1][P5].
- **Release hygiene:** the v18.0.0 GitHub release (published 2026-11-20T15:46:27Z) has an
  empty body and no assets [P8] — reconfirming R1's "NuGet notes are canonical". The
  post-release window is clean: no new issues/PRs since the 18.0.0 release — the newest
  is #244 (created 2026-11-08, closed 2026-11-10, the 17.1.1/17.4.0 `RemainingDelay`
  backoff fix R1 already covered); #243/#242 predate 18.0.0 and are closed [P11]. 18.0.0
  is still the latest in both the SF and SF.Emy flat-container indexes [P9]; the Emy
  image line is `18.0.3-community` (2026-11-21, amd64+arm64, = `latest`) > 18.0.2/18.0.1
  (11-21) > 18.0.0 (11-20), with `17.4.13-community` the latest 17-line image [P10] — the
  18 line is live and maintained on a 48 h fix cadence.
- **Emy client pairing (fills the version-matrix gap):** the 18.0.0 README's version matrix
  still lists rows only up to 17.x ↔ 17.x ↔ FFmpeg 9.x (no 18 row — identical on the
  17.4.0 page) [P4][P5]. The same-major rule instead holds from the package itself: the
  Emy client 18.0.0 **depends on SoundFingerprinting ≥ 18.0.0** (its only 17.4.0→18.0.0
  delta is that floor plus the Channels floor 10.0.0→11.0.0; its release-notes section is
  empty — topmost entry is 17.4.0) [P6][P7]. So the upgrade-lane pairing is
  **SF 18.0.0 ↔ Emy client 18.0.0 ↔ image 18.0.3-community**, the same shape as R1 §3's
  17 pair.
- **Fallback remains valid:** 17.4.0 (2026-11-10) stays in the version list [P4][P5]; a
  flip is a one-line csproj change (SF 17.4.0 + Emy client 17.4.0 +
  `17.4.13-community`), per DECISIONS 2026-11-24 (Q4).

### 2. snapcast #1563 / PR #1571 (subject 2)

- **PR #1571: still open, unmerged** — `state=open`, `merged_at=null`,
  `mergeable_state=unstable`, base=develop, 1 commit, 0 comments; created 2026-11-09,
  **last updated 2026-11-16** (8 days before this check; zero review activity since)
  [P12]. Title: "Client: file player skips a timer tick queued for a destroyed player" —
  the same 5-line `alive_` token fix R2 documented [R2-16].
- **Issue #1563: still open** (2 comments; created 2026-10-30, updated 2026-11-09 when
  the PR was linked) [P13].
- **No release since v0.35.0** (published 2026-03-10; newest of the ten newest releases
  is still v0.35.0) [P14] — the fix is in no published artifact.
- No change from R2's 2026-11-23 baseline. The owner's **watchdog-only posture stands**;
  the "revisit when #1571 merges" trigger (DECISIONS / plan OQ5) has not fired. No plan
  action.

### 3. Recurrence auto-promotion: precedent + guardrail defaults (subject 3)

**The precedent is real and vendor-sanctioned — the numbers are not published.**

- **Emy (the vendor of this very library) ships self-discovery as a product feature:**
  "Emy discovers new ads on its own by spotting content that repeats across your monitored
  streams. Discovered ads are tagged automatically with advertiser and brand metadata
  using AI" (re-verified 2026-11-24; the same claim as R1 [7]) [P15]. The Emy README
  (both the 18.0.0 and 17.4.0 NuGet pages, and the repo README) lists "broadcast content
  monitoring" and "**repeating content detection**" among its use cases [P16]. C02b's
  auto-promote-on-recurrence is therefore the vendor's own documented mode — not an
  ad-hoc extension.
- **Production-scale cross-day fingerprint comparison:** a large-scale TV monitoring
  deployment "generates new fingerprints from daily recordings, and compared with the
  database of past fingerprints" (10 channels) — the compare-new-against-history shape
  that our proximity-dedup + recurrence gate implement, at production scale
  (abstract-level citation) [P18]. ARGOS (repeating-object extraction from multimedia
  streams; audio fingerprinting applied to radio broadcast on-line segmentation) and
  Fluendo's on-edge "audio fingerprinting and intelligent segmentation" ad detector round
  out the fingerprint-based ad/repetition precedent (marketing/abstract level) [P19][P20].
- **No published recurrence thresholds exist** — a five-query SearXNG sweep (some engines
  degraded, recorded per FRICTION) found no vendor or academic source publishing a
  recurrence count, a time separation, or a dedup value for auto-cataloguing ads [P21].
  Emy states the mechanism without numbers [P15][P16]; TVEyes' 40% coverage bar (R1 [22])
  is a per-occurrence emission bar, not a catalogue decision; RadIA (arXiv:2403.03538,
  submitted 2024-03-06) is a catalogue-free ASR + text-classification prototype
  ("eliminating the need for prior knowledge of the broadcast content"; detects
  "impromptu and newly introduced advertisements"; F1-macro 87.76 vs a theoretical
  maximum of 89.33) — a validating alternative modality, not a self-hosted turnkey
  [P17].
- **Why recurrence is the right signal (grounded in R1):** the SF maintainer's FAQ calls
  radio-ad detection "the most frequent use-case" [P4][P16]; the SF wiki's
  `NewOccurrenceAbove(120)` is the documented broadcast-monitoring control distinguishing
  "another occurrence of the audio" from "an edit or a glitch of the same playing"
  (R1 §1, worked ad-pod example) — the library itself treats cross-occurrence repetition
  as the ad signal [R1-12].

**Assessment of the owner-ruled C02b defaults (values only):**

- `AUTO_PROMOTE_MIN_SIGHTINGS` = **2** — **sane.** The vendor's own self-discovery is
  "content that repeats" (≥2 sightings) [P15]; a single sighting would be drift-feeding
  and no source uses 1.
- `AUTO_PROMOTE_MIN_GAP_HOURS` = **24** — **sane.** Ad rotation repeats the same spot
  within a day (pod schedules), so same-day sightings do not prove rotation recurrence; a
  24 h separation makes the recurrence a cross-day/rotation signal, matching the daily
  new-fingerprints-vs-past-database comparison of [P18] and broadcast per-day airing
  measurement practice.
- Fingerprint-proximity dedup (vs catalogue + previously promoted) — **sane.** One entry
  per distinct ad, not one per re-airing; the same compare-against-history shape as
  [P18] and the SF occurrence controls (R1 §1).
- `AUTO_PROMOTE_MAX_PER_DAY` = **20** — **sane as a circuit breaker, not a semantic
  value.** No published precedent caps unique new ads per day; 20 bounds drift-feeding
  (e.g. a daily-recurring theme block that passes the recurrence gate) to a bounded,
  auditable exception — >20 unique new "ads" on one tapped stream means a non-stop
  commercial block or a false-positive loop, and a human should look.
- `auto_promoted` flag + `list`/`prune` audit surface + manual lane — **sane.** The
  vendor does the same (auto-discover + auto-tag + human backoffice catalogue
  management [P15][P16]); the manual lane covers single-shot candidates.

**Failure modes the guardrails address:** same-day pod repetition (3–6×/day — the 24 h gap
treats it as one sighting); a syndicated program embedding recurring spots (R1 [12]'s
28-minute program example — proximity dedup keeps one entry per distinct ad, not per
airing); theme music / jingles / station IDs that recur daily (the per-day cap bounds
them; the audit flag + `prune --track` removes them); a non-catalogued song repeating
across days (the ≥30 s non-matching span + 2-sighting gate; the cap + audit is the
backstop); a known ad re-airing (proximity dedup against the existing catalogue — no new
entry).

**Verdict: no value changes recommended.** The owner's defaults are the minimum defensible
set consistent with the vendor's documented mechanism. The one knob to relax, if the owner
later wants faster cataloguing on a heavy-ad stream, is `AUTO_PROMOTE_MIN_GAP_HOURS`
(e.g. 12 h — a 3×/day rotating ad then qualifies from its day-2 airing pair instead of
≈1 day after entering rotation); `AUTO_PROMOTE_MIN_SIGHTINGS` stays at 2 (1 is
drift-feeding, no published source uses it) and the 20/day cap is unchanged. Semantics to
record: with the 24 h gap, a 3×/day recurring ad qualifies on day 2 (its first two
sightings ≥24 h apart) → time-to-catalogue ≈ 1 day after the ad enters rotation. All of
this is value-only — the C02b guardrails are already env config with exactly these
defaults.

### Contradictions (and how to weigh them)

1. **TVEyes' deployed design (pre-seeded catalogue + 40% coverage bar, 300k ads) vs
   Emy's marketing (self-discovery via repetition)** [P15][P16][R1-22]: both are the
   same vendor's — the pre-seeded catalogue is the TVEyes revenue product; self-discovery
   is the Emy platform feature. C02b runs the self-discovery mode on the same matching
   engine, so it is vendor-sanctioned; the two are complementary (seed the known,
   auto-capture the rest).
2. **18.0.0 release silence (empty GitHub release body, empty Emy client notes, no 18 row
   in the version matrix) vs "18.0.0 is a real, maintained release"** [P4][P5][P6][P8]:
   the NuGet note + the client dependency floor + the image line (18.0.0→18.0.3 within
   48 h) [P10] weigh for "live and maintained"; the matrix gap is a documentation lag,
   not a compatibility signal. The tag-to-tag byte-identical diff of the core files [P3]
   resolves the actual parity question.
3. **No published recurrence thresholds anywhere vs the owner's guardrail values** [P21]:
   the values are our recorded best-guesses, not vendor-specified; the guardrail shape
   (min sightings + separation + dedup + cap + audit) follows the vendor's documented
   mechanism [P15][P16] and the SF's own occurrence/dedup controls (R1 §1), and the 24 h
   gap + per-day cap align with broadcast per-day measurement practice [P18]. The values
   stand; being env config, a post-launch tweak costs nothing.

### Implications for the plan

1. **Confirm the 18.0.0 pin** (plan Post Research item 2 resolved: confirm, not flip).
   Keep the recorded 17.4.x fallback line (one-line csproj rollback; no code-path
   change) [P1][P4][P5].
2. **#1571 still open** → the watchdog-only posture stands; no plan change; the
   "revisit when merged" trigger has not fired [P12][P14].
3. **C02b threshold guidance: no value changes** — the owner-ruled defaults (2 / 24 h /
   proximity dedup / 20 per day / `auto_promoted` flag / manual lane) are confirmed sane;
   the one recorded relaxation path is `AUTO_PROMOTE_MIN_GAP_HOURS` (e.g. 12 h) for a
   heavy-ad stream. No C02b task/test changes — t15–t19 already pin these values as the
   env defaults.
4. Minor, non-blocking, record only: (a) the 11.0.0 package floors are API-compatible
   assembly bumps on a net10 worker [P1][P5]; (b) the Emy 18.0.0 client's empty note
   makes R1 §3's same-major rule the pairing authority (SF 18.0.0 ↔ Emy 18.0.3-community)
   [P6][P7][P10]; (c) the 18-row gap in the version matrix is a vendor documentation lag —
   no action.

### Open questions

- None — no finding materially threatens the plan (subject 1: pin-safe; subject 2: no
  change; subject 3: values confirmed).

### Sources (Post Research; all fetched 2026-11-24 unless noted)

- [P1] `SoundFingerprinting.csproj` at tag **v18.0.0** (raw; the 18.0.0 release-note line; TargetFramework netstandard2.0). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/v18.0.0/src/SoundFingerprinting/SoundFingerprinting.csproj
- [P2] `SoundFingerprinting.csproj` at tag **v17.4.0** (raw; TargetFramework netstandard2.0; 17.4.0 note). https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/v17.4.0/src/SoundFingerprinting/SoundFingerprinting.csproj
- [P3] Tag-to-tag raw source diff (fetched 2026-11-24, byte-identical at both tags): `RealtimeQueryConfiguration.cs`, `IRealtimeSource.cs`, `InMemoryModelService.cs`. https://raw.githubusercontent.com/AddictedCS/soundfingerprinting/v18.0.0/src/SoundFingerprinting/Configuration/RealtimeQueryConfiguration.cs (+ `Command/IRealtimeSource.cs`, `InMemory/InMemoryModelService.cs`, same paths at v17.4.0)
- [P4] NuGet `SoundFingerprinting` 17.4.0 package page — dependency floors (Bcl ≥10.0.0, M.E.Logging.Abstractions ≥10.0.0, protobuf-net ≥3.4.40), release notes 17.4.0→9.4.2, version matrix (rows 12.x–17.x, no 18 row), FAQ (ad detection = most frequent use-case; 5 GB/100 h). https://www.nuget.org/packages/SoundFingerprinting/17.4.0
- [P5] NuGet `SoundFingerprinting` 18.0.0 package page — dependency floors (Bcl ≥11.0.0, M.E.Logging.Abstractions ≥11.0.0, protobuf-net ≥3.4.40), 18.0.0 note = the single dependency-floor line, version list (18.0.0 2026-11-20 newest), version matrix (no 18 row). (First fetched 2026-11-23 as R1 [1]; floors re-verified 2026-11-24.) https://www.nuget.org/packages/SoundFingerprinting/18.0.0
- [P6] NuGet `SoundFingerprinting.Emy` 18.0.0 package page — dependencies (SF ≥18.0.0, Channels ≥11.0.0, FFmpeg.AutoGen ≥9.0.1.1, …), release notes (no 18.0.0 entry; topmost 17.4.0), README use cases (incl. repeating content detection), version list (18.0.0 2026-11-20 newest). https://www.nuget.org/packages/SoundFingerprinting.Emy/18.0.0
- [P7] NuGet `SoundFingerprinting.Emy` 17.4.0 package page — dependencies (SF ≥17.4.0, Channels ≥10.0.0, …) for the two-line 17.4.0→18.0.0 delta. https://www.nuget.org/packages/SoundFingerprinting.Emy/17.4.0
- [P8] GitHub releases API `AddictedCS/soundfingerprinting` — v18.0.0 published 2026-11-20T15:46:27Z, body empty, no assets. https://api.github.com/repos/AddictedCS/soundfingerprinting/releases
- [P9] NuGet flat-container indexes — `soundfingerprinting` + `soundfingerprinting.emy`: 18.0.0 newest in both. https://api.nuget.org/v3-flatcontainer/soundfingerprinting/index.json (and `…/soundfingerprinting.emy/index.json`)
- [P10] Docker Hub tags API `addictedcs/soundfingerprinting.emy` — 18.0.3-community (2026-11-21, amd64+arm64, = `latest`) > 18.0.2/18.0.1 (11-21) > 18.0.0 (11-20); 17.4.13-community latest 17-line image. https://hub.docker.com/v2/repositories/addictedcs/soundfingerprinting.emy/tags
- [P11] GitHub issues API `AddictedCS/soundfingerprinting` (newest-first) — newest issue #244 (created 2026-11-08, closed 2026-11-10; the 17.1.1/17.4.0 `RemainingDelay` backoff fix); #243/#242 predate 18.0.0 and are closed → no new issues in the 4-day post-release window. https://api.github.com/repos/AddictedCS/soundfingerprinting/issues?sort=created&direction=desc
- [P12] GitHub API snapcast **PR #1571** — state=open, merged_at=null, mergeable_state=unstable, base=develop, 1 commit, 0 comments, created 2026-11-09, updated 2026-11-16; title "Client: file player skips a timer tick queued for a destroyed player". https://api.github.com/repos/snapcast/snapcast/pulls/1571
- [P13] GitHub API snapcast **issue #1563** — open (state_reason null), 2 comments, created 2026-10-30, updated 2026-11-09. https://api.github.com/repos/snapcast/snapcast/issues/1563
- [P14] GitHub API snapcast releases (ten newest) — newest is v0.35.0 (published 2026-03-10); no release since. https://api.github.com/repos/snapcast/snapcast/releases?per_page=10
- [P15] Emysound landing (re-verified 2026-11-24 via SearXNG; same claim as R1 [7]): "Emy discovers new ads on its own by spotting content that repeats across your monitored streams. Discovered ads are tagged automatically with advertiser and brand metadata using AI." https://emysound.com/
- [P16] Emy README (the NuGet pages [P6][P7] + the repo README, raw): use cases incl. "broadcast content monitoring" + "repeating content detection"; the FAQ "most frequent use-case" line. https://raw.githubusercontent.com/akolaarthurali/soundfingerprinting-emysound/master/README.md
- [P17] arXiv:2403.03538 "RADIA — Radio Advertisement Detection with Intelligent Analytics" (abstract page; submitted 2024-03-06): ASR + text classification, no prior knowledge of the broadcast content required, detects impromptu/newly introduced ads, F1-macro 87.76 vs theoretical maximum 89.33. https://arxiv.org/abs/2403.03538
- [P18] "A Large-Scale Audio and Video Fingerprints-Generated Database of TV Contents and Soundtracks" (SearXNG hit, abstract-level): daily new fingerprints from recordings compared with the database of past fingerprints, 10 channels. https://hal.science/hal-01017118/document
- [P19] "ARGOS: Automatically extracting repeating objects from multimedia streams" (SearXNG hit, abstract-level): redundancy/musical-repetition detection; audio fingerprinting applied to radio broadcast on-line segmentation (QUAERO). https://www.researchgate.net/publication/3424374
- [P20] Fluendo "AI ad detector" (SearXNG hit, marketing-level): on-edge ad detection using audio fingerprinting + intelligent segmentation. https://fluendo.com/blog/ai-ad-detector/
- [P21] Negative sweep (SearXNG, five queries, 2026-11-24; some engines degraded — duckduckgo CAPTCHA, wikidata/wolfram/yahoo unavailable, per FRICTION's known workaround): no published recurrence count / time-separation / dedup value for auto-cataloguing ads in the Emy, TVEyes, or academic sources.
