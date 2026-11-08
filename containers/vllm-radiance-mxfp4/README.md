# vllm-radiance-mxfp4 — thin re-export of the 0.30 Radiance stack (cf-131 C01)

A digest-pinned re-export of the upstream `magiccodingman/vllm-radiance`
0.30 image under the repo's `ghcr.io/ownyourio` namespace. The upstream
image is a self-contained terminal build (RESEARCH R3 L1.2): the 35
release overlays, the R4D/MXFP4 kernels and the RDNA4-tuned block-FP8 GEMM
configs are already baked, so the Dockerfile adds nothing and the CI build
is a minutes-class layer copy. The cluster pulls the in-repo artifact
because `docker-build.yaml`'s first-build `:v<run>` law needs one (D23);
the interface contract C02 builds against is below.

## Tag -> digest ledger (manual)

| What | Pin | Digest / SHA | Verified (probed 2026-11-08) |
|---|---|---|---|
| Radiance image | `docker.io/magiccodingman/vllm-radiance:1.0.397` (= `latest` = `1.0` = `sha-5b99d66c844f`) | `sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0` | Docker Hub tags API: `full_size` 4,079,863,554 B, `tag_last_pushed` 2026-10-18T06:35Z, `tag_status` active, amd64/linux; source commit `5b99d66c844fd0a54e4a7eb93b40a1ece009a53d` (config-blob `org.opencontainers.image.revision` label); engine vLLM **0.30.0 @ `ced6857afa0ea7b2e3f0846a62e1394e90f15607`** = the v0.30.0 tag commit |

Four-source corroboration of the pin (R3 L1.1), each re-verified at the dev
probe and re-run live by `tests/containers/vllm-radiance-mxfp4.sh` t6: the
Hub tags API `digest`; the registry manifest probe (anonymous pull-scope
token + manifest fetch — HTTP 200, single-arch docker manifest v2,
sha256-of-manifest-bytes equals the Hub digest); the sibling tags
`sha-5b99d66c844f` and `latest` resolving to the same digest; and the
config blob's OCI revision label naming the source commit.

Stack record baked inside the image (R3 L1.2, three-way agreement between
the repo README, `DOCKERHUB.md` and `.radiance/stack.yaml`): vLLM 0.30.0 ·
torch 2.12.0 · triton 3.7.1 · torchvision 0.27.1 · AITER 0.1.20 (built for
gfx1201, runtime JIT) · transformers 5.15.0 · xgrammar 0.2.3 · libr4d 0.5.0
@ `e8de4bc1` · ROCm userspace 7.14. Stack policy: "treat as a coordinated
compatibility stack; do not independently bump members" — a reason the pin
is the whole-image digest, never a rebuilt member.

## Lineage — what this pin continues and supersedes

- This line **continues** the stilldeadcode vLLM/R9700 story: magiccodingman
  tracks and credits DeadCode's vllm-radiance + libr4d work and additionally
  ports the native Quark MXFP4/W4A8 work (R3 L1.1).
- **SUPERSEDED base (record only, R3 L1.5):** the re-plan pinned
  `stilldeadcode/vllm-radiance:0.9.3` @
  `sha256:45694209177a55a1ab3ba6702fe6e978b1b66a6e66ae3fc066f8d579f7bc4c25`
  with the GGZ14 launcher — that line is deprecated, frozen, and its
  start-time patch machinery does not run against the 0.30 image (R3 L1.3).
  It survives as the runbook's recorded alternative, not a build input.
- **Predecessor in this repo:** the retired GGUF overlay built on
  `vllm/vllm-openai-rocm:v0.33.0-rocm100` @
  `sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba`
  (cf-105). The GGUF format and its plugin die with the 0.30 stack, which
  supersedes the whole engine story. The central Grafana vLLM dashboards
  stay pinned to the upstream repo tag `v0.33.0` — **stale by design**: the
  dashboards re-import is owner/central-stack territory (the recorded
  follow-up of the D-T2 disposition), and
  `tests/services/vllm-dashboards.sh` t4 keeps coupling that pin to this
  ledger row until the owner re-imports.
- The standalone stilldeadcode `radiance` successor engine stays **out of
  scope** — it is not an OpenAI-shaped surface, so it cannot sit behind the
  llama-swap hop this roster serves (R3 L1.1).

## Tag<->commit law and the release-branch watch

Publishes run on the `release` branch only (`$CI_COMMIT_BRANCH ==
"release"`): the job stamps `VERSION=1.0.<pipeline-IID>` and tags each
build `1.0.<n>` + `1.0` + `sha-<short commit>` + `latest`, labelling the
image `org.opencontainers.image.revision = <commit>` (R3 L1.1). So
`1.0.397` is pipeline #397 of the release line and pairs with
`sha-5b99d66c844f`.

**Bump trigger: the next release-branch `1.0.<n>`/`sha-...` pair.** GitHub
`main` movement is NOT the trigger — main carries test-only merges that
never reach an image (R3 conflict #4). Also do not conflate the two version
schemes: the source `VERSION` file tracks `1.1.0-rc1.vllm0.30.0` while the
published tags are the release line's `1.0.<n>` series.

## Manual-bump procedure

This dir carries **zero auto-update directives** by contract: the
release-branch sha-pair publishes have no datasource an auto-updater can
track (D12-amended), so the ledger is manual and the CI build is the
authority. Bumping is three steps; every edit lands together:

1. **Watch the Hub tags API** for the next release-branch publish:

   ```sh
   curl -s https://hub.docker.com/v2/repositories/magiccodingman/vllm-radiance/tags/1.0.397
   ```

   The `digest` field is the ledger value; record `full_size` and
   `tag_last_pushed` alongside it.
2. **Re-probe the registry before editing** — anonymous pull-scope token
   from `auth.docker.io`, then
   `GET /v2/magiccodingman/vllm-radiance/manifests/<tag>` with the manifest
   `Accept` types: expect HTTP 200 and sha256-of-manifest-bytes equal to
   the Hub `digest`. Then read the config blob's
   `org.opencontainers.image.revision` label (the fourth corroboration) and
   cross-check the `1.0.<n>` <-> `sha-<...>` pair against the `release`
   branch tip (pipeline-IID cross-check). A digest drift against the
   ledger means stop and re-record — never ship a drifted pin.
3. **Edit the three surfaces together, then re-bench on target**: the
   Dockerfile `FROM` line + the ledger comment, this table, and the chart's
   image comment (the values-side mirror in `charts/vllm/values.yaml`). The
   bump is not done until the runbook's first-serve step and benchmark step
   pass on the R9700.

## Interface contract (what C02 builds against)

- **Port 8000** — serve = health = metrics on one port; the chart probes
  `/health` and scrapes `/metrics` from it. The upstream image declares no
  ExposedPorts, so the record is the `EXPOSE 8000` line here.
- **Entrypoint** — `/opt/radiance_entrypoint.sh`, whose tail is
  `exec vllm serve "$@"` (R3 L1.3). The pod args START WITH THE MODEL PATH
  — no `vllm serve` tokens; that prefix would double the verb on this base.
- **`/models`** — read-only at serve time; the C03 setup init container is
  the only rw writer (weights staging lands there).
- **`/cache`** — mount expectation: the entrypoint defaults the cache vars
  to `/root/.cache/...` + `/tmp/torchinductor` unless re-declared
  (R3 L3.1), so C02's pod env re-declares the four `/cache/{vllm,inductor,
  triton,aiter}` targets onto the cache PVC.
- **Root posture** — the image config has `User: null` (runs as root). The
  pod's `runAsUser: 0` is the GID-486 device-group law, not the image's
  choice; the upstream compose records the same posture: "the image runs as
  root, so mapped devices do not require host-specific supplemental GIDs"
  (R3 L1.3). The writable root FS is intrinsic — AITER JIT-compiles inside
  the image.
- **First-use AITER JIT boot cost** — the release stage deliberately keeps
  the toolchain (g++/hipcc/Python.h) and there is NO pre-bake counterpart
  at 0.30 (the 0.9.3-era `bake_aiter_core.py` step has no successor, R3
  L1.2): the first boot pays the JIT, and a warm `/cache` amortizes it on
  re-boots.
- **Chat-template absence** — the 0.30 default is the checkpoint-native
  template; no jinja ships in the image (the release stage copies only the
  probe/preamble/entrypoint files). The enhanced templates are
  compose-side private overrides we do not mount (R3 L1.2).
- **Baked `RADIANCE_*` flag set** — the image ENV is the recipe baseline:
  the config-blob dump carries ~50 `RADIANCE_*` vars (the
  `RADIANCE_MXFP4*`, `RADIANCE_GDN_*`, `RADIANCE_FAST_DRAFT`,
  `RADIANCE_USE_R4D*`, `RADIANCE_QUARK_BF16_MTP` families +
  `RADIANCE_VERSION=1.0.397`, R3 L1.1). C02's env law re-declares only
  what the recipe varies — an unset flag means the baked value stands.

## Provenance

- cf-131 C01 — plan `2026-11-07-cf-131-feat-vllm-fp8-official.md`,
  DECISIONS D23 (the 0.30 pin set + thin-overlay collapse: round-2 Q10
  base move, round-3 R3-Q1 thin-overlay confirmation).
- RESEARCH R3 L1.1 (pin + four-source corroboration + tag<->commit law),
  L1.2 (terminal-build stack), L1.3 (pairing + entrypoint/args law),
  L1.5 (three-stack lineage table), L3.1 (what dies, what survives, cache
  defaults).
- Container contract suite: `tests/containers/vllm-radiance-mxfp4.sh`
  (t1-t6, incl. the live registry probes).
