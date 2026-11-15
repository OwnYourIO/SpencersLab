# Radiance q27 lane — the owner's first-boot console note (gpu-ai, pod-swap)

> **Posture (read first).** This is the console document for the q27 lane's
> first boot: you are mid-swap, one engine is down, and every step runs in
> order without opening anything else. The lane is a POD-SWAP — a second
> `radiance` release, `gpu-ai-radiance-q27`, on the SAME single R9700, one
> engine live at a time (DECISIONS D54; RESEARCH §R19).
>
> **The resting state is fn 1 / q27 0, and it is idle BY DESIGN.** Git
> renders that pair (D54(1)); the lane is opt-in, nothing routes to it by
> default, and the catalog trio `qwen3.8-27b-radiance` + `-urgent`/`-low`
> are runner candidates only after measurement on this box — the pipeline
> runner-model literal does NOT move (D54(4)). What settles any number in
> this note is the boot print: the receipt decides, never the rate
> (§R8/D28(6) class law; §R19 Verdict).
>
> **OWNER-EXECUTED** marks every write-shaped line below; everything else
> is a read. The cluster's only input is git — ArgoCD applies everything and
> no step here applies manifests repo-side. No tier grants pod exec: the
> engine reads go through `port-forward` + `curl` (the fn runbook's idiom).

**Provenance.** cf-143 (`2026-11-11-feat-cf-143-feat-radiance-replaces-strata`),
chunk C16 — the owner-facing half of D54; the plumbing landed at C15.
Authorities: `DECISIONS.md` D54 (the four owner rulings), D56 (the plan
forks), D57 (the idle-code correction and the prefix-cache correction —
both written from those entries, not from chat memory); `RESEARCH.md` §R19
(cited here as `§R19`, `R19-Q<n>`, `R19-S<n>`, `R19-A`–`R19-F` — every
reference resolves in that file). The served truth is the shipped subtree:
`services/gpu-ai/prod/values.yaml`, `radiance-q27:` — Step 3's block is that
args list, parsed-equal to it. Sibling docs: the fn lane's runbook
(`.agents/notes/radiance-on-target-acceptance.md`), the post-boot tuning
loop (`.agents/notes/radiance-host-tuning.md`), the second-card plan
(`.agents/notes/radiance-second-gpu-tp2.md`). If this document disagrees
with the shipped subtree, the subtree is authority and this document is the
bug — the same tail law the fn runbook carries.

## Step 0 — What rest looks like (facts that change only via DECISIONS)

- Git renders the pair: `gpu-ai-radiance` at 1, `gpu-ai-radiance-q27` at 0.
  `0` is NOT a disable artifact — every byte of the lane is deploy-ready
  for your flip (D54(1)).
- The idle lane answers loudly. While q27 rests at replicas 0, the
  peers.radiance-q27 hop fails with a 502 peer proxy error (the Service has
  no endpoints; llama-swap neither health-checks nor hides peers) — loud,
  never silent (D57; the code's source is llama-swap's peer ErrorHandler,
  not anyone's chat memory). Routing a request here before you scale up is
  the lane refusing, by design, not an outage.
- Keyless posture (D54(2)): the lane is internal-only — reached solely
  through the outer llama-swap peer hop, no ingress, no host, no key. When
  someone asks "why isn't it authenticated?": that is the same posture fn
  ships (D8), the owner's recipe rider `--api-key "$RADIANCE_API_KEY"` was
  explicitly DROPPED, no such secret exists repo-wide, and adding a key is
  a DECISIONS change plus a custom-values leg — never a console edit.
  `/health` is key-exempt by the engine's own security chapter (R19-Q5).
- The catalog trio ranks 8/4/0 sit strictly below fn's 9/5/1 under the same
  higher-wins polarity (D56(5)); each pod schedules its own queue, so the
  ranks are this lane's internal class identity, not a cross-pod order.

## Step 1 — Space, then staging (the slow part is expected)

The pack stages onto the SHARED `llama-swap` 500Gi claim — fn's 113.6 GiB
plus the strata tables already live there, and q27 adds 18.05 GiB
(`qwen3.8-27b-mxfp4.rad`, 19,377,119,232 bytes, lfs `a4908940c568f5f9dd24e88f46aefe9ac2ae07dfec023a2eaa1d14dcaa3df4f8`,
ungated — the subtree's own ledger, R19-S1). Read the free space BEFORE
scaling up:

```bash
# OWNER-EXECUTED — host-side read on the ai-gpu node, free space on the shared claim:
df -h "$(ls -d /var/lib/rancher/k3s/storage/*llama-swap* | head -1)"
```

Paste back the available figure: the first boot needs ~18 GiB of free
space on top of fn's pack and the strata tables already on the claim —
the fetch resumes across retries, so tight-but-not-zero space recovers;
a full claim just loops the init.

First boot of the `.rad` is NOT a cold engine start — it is a download: the
`radiance-fetch` init pulls ~18 GiB (curl-resume), then runs the portable
`sha256sum` equality gate ONCE, before the engine container starts at all.
Expected class at the chart's 1000m single-threaded init: ~1–2 min for the
hash (DERIVED from §D4's ~5.8–13.6 min bound at 113.6 GiB, scaled by
18/113.6 — the boot prints the truth), plus the fetch. A slow first boot is
the download doing its job, not a failure: the chart's startupProbe gives
the engine a 30-minute envelope (`/health`, 10 s × 180) and the peer route
keeps `responseHeader: 1800` for the first byte.

Two staging laws, carried from the fn lane (the init script ships both):
the marker is written only AFTER the checksum passes — pack-on-disk without
its marker is download-complete at best, staged never; and a resumed
download that answers rc 33 ("the file is already completely retrieved")
is DONE, not a failure — the hash gate still runs before the marker lands.

These laws print their proof into the `radiance-fetch` init's log — and at
rest there is no such log: the q27 deployment renders at 0 replicas
(Step 0), so nothing can be read off a pod that does not exist yet. The
receipt itself is Step 2's first read.

## Step 2 — THE SWITCH, THEN THE STAGING RECEIPT (OWNER-EXECUTED; the order IS the discipline)

fn DOWN first, then q27 UP. Not etiquette — arithmetic. Both-up lands
**Pending, not OOM**, because three INDEPENDENT blockers exist and any one
of them is fatal (§R19-Q1/Q3, D54(1)):

1. The scheduler: `amd.com/gpu-r9700-1` is a capacity-1 pool and the
   chart-baked claim is non-subtractable (D26: overlays ADD, never REMOVE)
   — a second radiance pod Pends against the pool forever.
2. The card: fn TP1 holds ~28–30 of the ~31.86 GiB usable, while q27 wants
   18.07 weights + ~12.48 KV = 30.55 GiB > our 29.30 claimable (R19-Q1(i)
   — claimable is the ceiling that binds here, not usable).
3. The host: fn at its 110 pair leaves `125.08 − 110 − 4.125 − 1.158 =
   9.80 GiB` free — below this lane's own `limit − printed-pinned ≥ 4`
   slack law at any defensible number.

Down:

```bash
# OWNER-EXECUTED — operator runs this; the repo never scripts it (D54(1)):
kubectl -n default scale deploy/gpu-ai-radiance --replicas=0
```

Wait until fn's pod is actually gone — the card releases at pod termination
(the engine "finishes the step in flight and releases the cards on SIGTERM",
R19-S4):

```bash
kubectl -n default get pods | grep gpu-ai-radiance
```

Then up:

```bash
# OWNER-EXECUTED — only after the read above shows fn's pod gone:
kubectl -n default scale deploy/gpu-ai-radiance-q27 --replicas=1
```

The UP-scale creates the q27 pod — the first moment in this document where
any read against it can resolve. Its init runs first, and the `radiance`
engine container starts only once that init exits clean, so the staging
receipt below is also the wait-gate for Step 3's engine reads:

```bash
kubectl -n default logs deploy/gpu-ai-radiance-q27 -c radiance-fetch | tail -10
```

Expect `radiance-q27 staging: complete` (or the marker-skip line on later
boots). Until that line prints, an empty or partial read is Step 1's slow
first boot still running: wait, and do not delete the pod mid-hash. On a
`sha256 MISMATCH` line the init exits 1 and the pod restarts the fetch —
stop and report, do not retry past a second mismatch.

**The don't-sync law.** Any sync re-applies git over a hand-scale (D31/D32)
— the flip is a PARKED state that reverts at the next sync or a re-deploy
window; this box demonstrated the durability limit the hard way on
2026-11-14, when a parked scale-down did not survive the crash-and-reboot
round (D50/D51). OutOfSync across the window is EXPECTED — that marker IS
the parked swap, not a defect to chase. So: do not sync `gpu-ai-radiance-q27`
while the lane is in use, and do not sync `gpu-ai-llama-swap` during any
strata dance (the fn runbook's law, unchanged). The pod comes up on your
scale — not on a click; the click is how the parked state ends.

## Step 3 — THE READ (the load-bearing receipt; paste it back whole)

The first boot of the `.rad` on OUR card is the experiment §R19 handed up:
it prints whether one 200K session fits and what the served aggregate
actually is. Write nothing here — read and paste, and start only once
Step 2's staging receipt has printed.

The expectation first — this is the ONE shipped q27 profile, the landed
`radiance-q27:` subtree's args list verbatim (the contract script
parse-compares this block against the subtree; re-typed drift here is the
red class). `--host ::` is the lane's idiom as shipped, not the recipe's
literal (OQ-15 ruled), and no key flag rides it — the recipe's api-key
rider was DROPPED by D54(2) and lives only as the Step 0 prose:

```bash
radiance --model /models/radiance/qwen3.8-27b-mxfp4.rad --port 8000 --host :: \
  --tp 1 --max-model-len 200000 --max-num-seqs 8 --kv-cache-dtype fp8 \
  --prefix-cache-mib 4096 --served-model-name qwen3.8-27b-radiance
```

```bash
kubectl -n default logs deploy/gpu-ai-radiance-q27 -c radiance | head -120
kubectl -n default port-forward svc/gpu-ai-radiance-q27 8000:8000 &
curl -s http://127.0.0.1:8000/diagnostics
kill %1
```

If `port-forward` has no endpoint yet or `curl` refuses the connection,
the engine is still loading inside the 30-minute envelope Step 1 priced —
wait and re-run these lines rather than restarting anything.

Read, in order:

1. **The `/diagnostics` config print** — the flags the engine ACTUALLY has.
   It must equal the block above; the quick repo-side proof is the fn
   runbook's step-5 jsonpath read aimed at `gpu-ai-radiance-q27` —
   `kubectl -n default get deploy gpu-ai-radiance-q27 -o jsonpath='{.spec.template.spec.containers[?(@.name=="radiance")].args}' | tr ',' '\n'`
   (one command, read-only). A mismatch means the overlay drifted —
   git-class fix, stop.
2. **The VRAM-split block — `weights by tier` and the `kv cache` lines.**
   This is the pending receipt D54(4) named: the pool line reads
   `kv: the pool backs N% of the worst case … M full-length sessions`
   (R19-Q1(iv)) — M is how many full-length sessions the engine itself
   thinks it funds, and what it prints is the datum that decides whether
   the advertised `limit.context 200000` stays honest. Do not pre-empt it:
   "one 200K session fits" is written here as the thing the boot CONFIRMS
   or CORRECTS, never as a promise — the print, not Step 4's division, is
   the authority on the served aggregate.
3. **The `pinned by this process` line against the 24 Gi pair.** The lane
   law is `limit − printed-pinned ≥ 4` (R19-Q3, D54(3)) — at 24 that means
   printed pinned should stay at or under ~20 GiB. Read it together with
   the cgroup instruments, the way §R8/fn-runbook step 6 established: the
   pod's `memory.peak` and `memory.events` (`oom_kill` must read 0).
   UNVERIFIED-3: nobody has measured this pack's load-time host peak — the
   `memory.peak` at first boot IS the instrument. The 16–20 GiB figure in
   the subtree comment is the cgroup-TOTAL band and already CONTAINS the
   11.25 GiB slot store and the 4 GiB host tier — never add it to
   anything.
4. **The checkpoint-slot count print.** The startup log says what it chose
   (each slot 144 MiB on q27, R19-Q1(ii)); UNVERIFIED-4 covers the count
   at the shipped default interval — paste the line, expect it may differ
   from any plan arithmetic.
5. **The prefix-cache warning.** A warning that the host tier holds less
   than one `--max-model-len` conversation is EXPECTED and benign:
   `--prefix-cache-mib 4096` sits below one 200K fp8 conversation (~6.4
   GiB, DERIVED, R19-Q2); partial retention IS the config, and the 4096
   value is Wilde's operational patch, not the model card's. The law, as
   D57 sets the record straight (against a chat assertion that had it
   backwards): `--prefix-cache-mib 4096` does NOT eat conversation
   capacity — the 4 GiB tier is host-side, "neither taken out of the KV
   pool nor resident in VRAM" — so it does not shrink the ~335–409K
   aggregate; the first-boot receipt above stays the witness.
6. **The pool reads.** The node must still advertise
   `amd.com/gpu-r9700-1: 1` with the q27 pod holding it, and
   `amd.com/gpu-8060s` untouched — the router never moved:

   ```bash
   kubectl describe node ai-gpu | grep -E "amd\.com"
   kubectl -n default get deploy gpu-ai-radiance-q27 \
     -o jsonpath='{.spec.template.spec.containers[?(@.name=="radiance")].resources}'
   ```

   Expect the claim `amd.com/gpu-r9700-1: 1` and the 24Gi request==limit
   pair (cpu and the claim are chart-inherited — D26, the overlay cannot
   remove them).
7. **The `link` line.** The engine's own `link` row is the authoritative
   host↔card witness on this box (D50(2)); `/diagnostics` re-reads it
   live. Expect `16.0 GT/s x4` — the chapter is CLOSED (D44/D51). A lower
   read after a power event is the known re-latch class (D35/D43): report
   it into the tuning note's LINK chapter; this note fixes nothing.
8. **The `/dev/shm` footprint.** Round 7 named this unpriced line: the
   chart ships the lane a 2 GiB memory-backed `/dev/shm` (the `shm`
   persistence entry of `charts/radiance/values.yaml`) and neither §R19
   nor the plan prices it. Look at `/dev/shm` usage inside the pod across
   load and the Step 5 smoke, and at the engine's own complaint if it
   needs more room. What it decides: whether that 2 GiB chart default is
   sufficient for a dense 27B lane. UNVERIFIED — no measurement exists;
   this row fixes the receipt, claims no size, changes no value.

If any print contradicts `200000` or `24`: report it. Do NOT improvise a
fix — the repair is DECISIONS → values → arms in one wave (D36(4)), never
a silent retarget of a shipped number.

## Step 4 — The honest envelope (what to tell anyone who asks "how much context")

- Per-session ceiling: 200000 — `--max-model-len` is a ceiling, and per
  the docs it "reserves nothing per request; it is the worst case the pool
  is sized against" (R19-S2). One near-200K session plus short ones is the
  whale shape, pool-full at roughly 55–65% for the whale alone (§R19
  Contradictions 1).
- Aggregate: the band the division lands in is ~335–409K tokens at the
  shipped flags (DERIVED, R19-Q1(i): 12.48 GiB pool ÷ ~32 KiB/token fp8 ≈
  409K, less the per-sequence delta-net state toward ~335K). "8 at ~45K
  each" is that pool shape — 8×200K = 1.6M is IMPOSSIBLE, because q27 is
  dense and dense attention reads the whole history every step: context
  here is VRAM-only, ~11× fn's streamed per-token cost, and the engine
  refuses a host mirror outright (R19-Q1(iii)).
- The owner-quoted "370–400K" sentences are VERIFIED as that arithmetic
  and UNVERIFIED as quotations (they appear in no fetched surface — §R19
  UNVERIFIED-1); this note cites the division and never presents the band
  as documentation.
- `--prefix-cache-mib 4096` subtracts NOTHING from the above (Step 3.5).
- Over the ceiling the request is refused at the gate; queue overflow
  answers 429, and pressure is handled by queueing and
  preemption-by-recompute, not by silent truncation (R19-Q2). Step 3's
  print — not this division — is what pins the final wording here.

## Step 5 — Smoke through the peer hop

Only route: outer llama-swap → `peers.radiance-q27` → engine. The hop's
proxy base is the release Service on port 8000 —
`http://gpu-ai-radiance-q27.default.svc.cluster.local:8000`
No path suffix rides a peer proxy: request paths append verbatim, so a
`/v1` on that base would double-prefix every route. You smoke from the
public chain: `https://llama.spencerslab.com/v1`. Keyless — no
Authorization header exists to send.

```bash
curl -sS https://llama.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-radiance","max_tokens":8,"messages":[{"role":"user","content":"ack"}]}'
```

Priority live-check — this lane's 8/4/0 classes, same-body shape as the fn
runbook's step 8 (urgent first, low last; higher-wins):

```bash
curl -sS https://llama.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-radiance-urgent","priority":8,"max_tokens":8,"messages":[{"role":"user","content":"ack"}]}'
curl -sS https://llama.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-radiance-low","priority":0,"max_tokens":8,"messages":[{"role":"user","content":"ack"}]}'
```

The engine's priority-0 semantics are UNVERIFIED (plan OQ-16): this read IS
the receipt — paste back what the queue actually does to a priority-0
request. A correction re-pins via a DECISIONS line and the arms, never a
silent retarget.

Image leg (the Q8 pattern): the vision tower ships IN the `.rad` pack
(R19-S1), and the catalog rows advertise `input: [text, image]` on the
strength of that. Send one image-bearing body through the chain. PASS = a
parsed image response. FAIL retires the advertisement: flip the three
q27 rows to `["text"]` as a git change and file it — the engine still
serves text perfectly; the claim is what moves.

## Step 6 — Attribution table (every speed figure, with its condition)

| figure | exactly what it measures | source |
|---|---|---|
| 122 tok/s | the MODEL CARD (creator) TP1, SINGLE-stream mixed-prompt mean — prose leg 77, code leg 164; greedy, 768 tokens × 8 prompts, drafter auto; UNVERIFIED-2: the creator rig's host/link is NOT stated, so the GUIDE's Gen5 never rides onto this figure | R19-A |
| 280 tok/s | the same card's TP1 4-stream TOTAL (≈70/user) — the batch-shape row | R19-A/R19-C |
| 116 tok/s | Thomas Wilde, THIRD-PARTY, n=4 follow-up decode at 64K context on a Gen4 board (cold rows 126.9; 93.5 at 128K) | R19-B |
| 50/user, box 106 | the 8-lane serving reality at 64K on Wilde's TP2 rig — flat box total with more users, TTFT 10.2 s; the batch reality at 8 lanes looks like THIS class, not the single-stream rows | R19-D |
| 227/208 tok/s | the lucebox ENGINE on another stack — context only, never this lane's receipt | R19-E |
| 29.8 t/s | llama.cpp 4-bit, llama-bench class — different engine again | R19-F |

Law of this table, quoted from its third-party source: "quoting a
throughput number without its context length and headcount is meaningless"
(Wilde, R19-S7) — so a bare 122 never ships: the model card's TP1
single-stream mixed mean is only ever written with its prose leg 77 and
its 4-stream total 280 beside it. And the sentence that makes the two
lanes non-comparable by receipt: Flash-Next on a single R9700 in Radiance
has no published speed (§R19-Q4) — nothing here invents one.

## Step 7 — Swap back

Reverse the switch in the same single-device discipline — q27 DOWN first,
wait for the release read, THEN fn UP:

```bash
# OWNER-EXECUTED — swap-back, q27 down first (same order law, D54(1)):
kubectl -n default scale deploy/gpu-ai-radiance-q27 --replicas=0
```

```bash
# OWNER-EXECUTED — after the pods read shows q27 gone:
kubectl -n default scale deploy/gpu-ai-radiance --replicas=1
```

Expect the expensive direction: fn repays its minutes-class 113.6 GiB boot
and its eager ~71 GiB pin (printed 71.04 class, §R8) — the asymmetry is
why q27 is the nice swap citizen (§R19 Verdict: 18 GiB, sub-minute-class
load). Or let git restore the resting pair: syncing the two radiance
releases re-applies their rendered pair — fn 1 / q27 0 — and that click
is the restore moment, which also re-applies everything else (the Step 2
law cuts both ways). If the window was carved out of a strata
scale-down, the fn runbook's step 10 restore-back dance is unchanged by
this note.

## OPEN — what the first boot is expected to answer (named, not papered over)

- Load-time host peak — UNVERIFIED-3; the pod's `memory.peak` at first
  boot is the instrument.
- Checkpoint-slot count at the shipped default interval — UNVERIFIED-4;
  the startup log names it.
- Priority-0 semantics — plan OQ-16; Step 5's live check is the receipt.
- The image-input claim — Step 5's image leg retires it on failure.
- The aggregate band's provenance — verified arithmetic, unattributed
  quote (§R19 UNVERIFIED-1); Step 3's pool line replaces the prose.

*(end of note — every flag, byte count and sourced number here mirrors
the shipped `radiance-q27:` subtree and §R19 as landed at C15; if a
file disagrees with this document, the file is authority and this
document is the bug.)*
