# containers/strata — `ghcr.io/ownyourio/strata`

Strata inference engine (Qwen3.8-Flash-Next host) + llama-swap supervisor,
bundled for the gpu-ai `strata` pod — the in-chart strata controller of
`charts/llama-swap` (cf-77). PID 1 is llama-swap; the engine runs as its
supervised child via the documented `strata serve` CLI and a run-config
JSON. The upstream launch path
(tini + `/opt/strata/entrypoint.sh run`) is deliberately NOT used —
[Niko1221/Strata issue #3421](https://github.com/Niko1221/Strata/issues/3421)
(engine-as-child without the wrapper is "a larger design", still open there)
is exactly why this image pins exact upstream builds and records their
digests below rather than trusting a mutable tag.

## Image contract — interface freeze (C02 chart + C05 fallback build against this)

| Surface | Value |
|---|---|
| Entrypoint | `llama-swap` (exec form); effective command `llama-swap -config /app/config/config.yaml` — the chart injects the args and mounts the rendered ConfigMap **as a directory** at `/app/config` (a `subPath` file mount never receives ConfigMap updates, so reloads would silently stop) |
| serve CLI entry (what the llama-swap `cmd` execs) | `/opt/strata/terminal/bin/strata` |
| Engine exe — primary (R9700 / gfx120x) | `/opt/strata/components/engine/0.1.52-linux-x86_64-hip-rx9070/strata` |
| Engine exe — fallback (Strix / gfx1151, C05) | `/opt/strata/components/engine/0.1.52-linux-x86_64-hip-halo/strata` |
| Engine root layout | both roots live under `/opt/strata/components/engine/<label>/` as **distinct dirs** (same-named binaries per flavor — never merge them) |
| Source checkout (headless provisioning) | `/opt/strata/src/Strata` — shallow clone at `v0.2.7`, `.git` removed. The packaged tree carries NO installer (`strata install` is a shim for the checkout's setup.py), and upstream's llama-swap doc is explicit: the integration "needs a source checkout, not the desktop installer" — so the chart's `model-fetch` init copies this tree to the claim and runs `./setup.sh` there |
| Compile toolchain (baked, not runtime-installed) | `build-essential` + `git` via apt in the runtime stage — setup.sh Step 4 compiles the checkout's AMD engine once onto the claim; the verify RUN fails the BUILD if either tool goes missing (owner ruling 2026-10-29: no pod-start apt) |

- The engine binaries are referenced **from each profile's run-config `exe`
  key, NOT from the `cmd`** — `serve` picks its engine from the run-config
  (RESEARCH §2), so switching flavor = switching profile file, not image.
  Post-transplant (2026-10-29): the PRIMARY profile points at the engine
  setup compiles into the claim-side checkout (`/models/strata/Strata/engine/
  strata`, gfx1201, venv ROCm SDK); the packaged rx9070 root above stays a
  documented image surface and the escalation reference, and the STRIX
  profile is the packaged-path consumer (halo root, gfx1151).
- Binary names are measured, not invented: captured from the pinned upstream
  layers via registry tar-listing (2026-10-27/28) and re-printed to every CI
  build log by the verify step in `Dockerfile`. `strata-vision` and
  `strata-vision-hip` sit beside `strata` in both dirs; vision is OFF for v1
  (R2 ruling) — the binaries' presence is not an invitation to enable it.
- `/usr/local/bin/strata` on PATH is the base image's own shim into the
  terminal; C02's cmd uses the explicit `/opt/strata/terminal/bin/strata`
  path above so the contract survives any upstream wrapper change.
- **`strata update` must never run inside this container**: the engine lives
  in the image, and an in-place update silently invalidates the pin ledger
  below and outlives no rebuild (RESEARCH §1, DOCKER.md says the same).
  Upgrading is a commit: change both FROM tags + the ledger, CI rebuilds.
- Not baked, by AC4: no secrets, no model weights, no prepared packs.
  Provisioning is runtime work on the shared claim: the `model-fetch` init
  container (charts/llama-swap, strata controller) copies the source checkout
  to `/models/strata/Strata` and runs the documented
  `./setup.sh --family qwen --model <id> --no-start --yes` per quant token —
  setup owns fetching shards, tokenizer, packs and draft data (into
  `Strata-data` beside the checkout) and writes `strata-<model>.json` run
  configs there. The serve profiles must then match those artifacts, not
  hand-seeded paths (the first deploy's seed-path failure is the evidence
  trail; reconcile with `strata models list --install-dir /data/install`).

## Pin ledger — literal tags + recorded digests (coord ruling shape (b))

The GHCR flavor tags are mutable and get rebuilt in place on occasion. The
2026-10-25 incident where `unified-vulkan-262` was rebuilt under everyone's
feet and crash-looped the gpu box (see the recorded post-mortem in
`charts/llama-swap/values.yaml`) is the class this ledger guards; #3421 (the
silent-engine-swap issue) is the same failure mode on this repo's side.
Every bump re-verifies the digest **before** it ships and re-benches after.

| FROM tag (literal in Dockerfile) | Manifest digest |
|---|---|
| `ghcr.io/niko1221/strata:0.2.7-rocm-gfx120x` | `sha256:703efd51c040152e9fceb993688b01ca0374535a5bfd86c14a60b5e60c96407a` (measured 2026-10-27, RESEARCH §1) |
| `ghcr.io/niko1221/strata:0.2.7-rocm-gfx1151` | `sha256:29ecd5cf8b0e21525dbb5c0191d7743d62fa356da646cb6aaf0546e5a31a8b3f` (measured 2026-10-27, RESEARCH §1) |

Supervisor stage: `ghcr.io/mostlygeek/llama-swap:unified-vulkan-266` =
`sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045`
(RESEARCH §3; re-verified 2026-10-28 against the registry manifest HEAD).

Source stage: `github.com/Niko1221/Strata` clone at tag `v0.2.7` — bump
WITH the flavor tags (same release line; `strata doctor`/setup expectations
assume checkout≈engine coherence). Alpine builder base `alpine:3.22` is a
build-time-only fetch, not a runtime surface.

Renovate posture under the ruling: **no `# renovate:` comment names the
strata depName** — no repo manager extracts a `datasource=docker` ARG-pin
comment (live-verified in both engines, DECISIONS coordination round; a
migration to a claiming shape goes through coord as its own ticket). The
built-in dockerfile manager still tracks the literal FROM tags, so update
PRs WILL fire with cross-flavor candidate bleed (a gfx1151 candidate
proposed against the gfx120x line, and vice versa) until a flavor-scoped
versioning rule or ignore lands — close/ignore those; bump only against this
ledger + a re-bench (plan human step 5). And never read the GitHub release
list as "shippable": releases 0.2.4–0.2.6 exist with **no images** — the tag
list is the only truth.

Bump procedure: `docker buildx imagetools inspect
ghcr.io/niko1221/strata:<new-tag>` (or manifest HEAD) → record tag + digest
as a pair above → same commit changes both FROM tags → on-target
`strata serve --plan` re-check → re-bench.

## Runtime contract — the chart carries this half (C02; upstream DOCKER.md)

Pod/spec side (an image cannot provide it):

- `memlock` ulimits unlimited (`--ulimit memlock=-1:-1` equivalent: the
  host/k3s `LimitMEMLOCK` + pod capability per the DECISIONS device-access
  ruling) — the arena page-locks ~47 GiB.
- shared memory `shm` 2 Gi (`--shm-size 2g` equivalent: emptyDir
  `sizeLimit` medium=Memory on the pod).
- stop window 120 s (`--stop-timeout 120`), and llama-swap's per-model
  `unloadTimeout` (default 10 s force-kill) must exceed that drain — the
  binding constraint pairing is RESEARCH §3, C02's config.
- NO container memory limit — the page-locked arena must size against real
  RAM; a cgroup cap breaks it (#1601 stays deferred while this holds).
- devices `/dev/kfd` + `/dev/dri` (hostPath + the pod's privileged shape,
  DECISIONS 2026-10-27) and process groups `video` + `render`.
- Root: the image keeps the upstream root user (no uid-65532 is created).
  Deviation from the repo non-root standard, approved in the plan and
  confined to this one pod by the architecture ruling.

Cmd side (lives in the llama-swap model `cmd`, not in the image or pod
spec): `ulimit -n 524288` **remains mandatory in the cmd wrapper** — no
0.2.x release self-raises the nofile soft limit (PR #2399 is still open,
#2398 closed unmerged; RESEARCH §2 contradiction #5), and `--kv-grow`/HIP
memory creation fails at ~1k FDs on the default 1024 limit.

Not in the image by design: the Vulkan llama.cpp stack, `run.sh`, and the
`/models` WORKDIR of the llama-swap base — only `/usr/local/bin/llama-swap`
is harvested. ROCm owns this container's GPU path; llama-swap's own image
machinery would collide with that.

## Escalation — guide-2B source build (deferred, RESEARCH §6)

Only if the bundled 2C image fails on-target. Facts so nobody re-derives
them: `therock-dist-linux-gfx120X-all-7.14.1.tar.gz` exists on
repo.amd.com (2.336 GB) but is published with **no sha256** — record the
digest on download. The Strata repo ships no gfx1201 hipBLASLt tuning table
for 100401 (7.14.1): a source build runs plain-dense prompt matmuls or
self-tunes with `tools/hip/tune_hipblaslt.cpp` (PR #3636 ran gfx1201 on
7.14.1/hipBLASLt 1.4.1 fine without one).

## Publishing — CI, not hand-releases

`.github/workflows/docker-build.yaml` detects this changed directory on PRs
(build-only, never pushes) and on merges to `main`/`dev` pushes
`:v<run_number>` (immutable, monotonic) + `:main` (rolling). There is no
version or tag to bump by hand here. The in-chart strata controller of
`charts/llama-swap` follows the repo's new-container rule: `:main` +
`pullPolicy: Always` with a pin-me note until the first `:v<run>` exists,
then Renovate-pinned `:v<run>`. Bundle size: the gfx120x base is ~2.8 GB
on disk and the added halo engine root measures
~0.65 GB uncompressed (layer-listing arithmetic, 2026-10-28) plus the
supervisor's single Go binary — the accepted price of one image serving
both flavors (splitting into two container dirs is only on "past
reasonable" per the C01 note).

Local gate `docker build containers/strata/` needs a daemon; the
authoritative build is the CI workflow on the pushed branch. The repo-side
surface checks are `python3 -m pytest containers/strata/tests/ -q`.
