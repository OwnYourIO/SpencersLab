# forgejo-runner

The act job image behind the four act-24.04-family Forgejo runner labels
(`ubuntu-latest`, `ubuntu-24.04`, `docker`, `node22` in
`charts/forgejo-runner/values.yaml`) — every Forgejo CI job that requests
one of them runs in this image. `ubuntu-22.04` deliberately stays on the
plain upstream `act-22.04`: the only lane requesting it is the
builder-bootstrap recovery lane below, which must not depend on this
image because it exists to (re)mint it (and a 24.04-content image behind
a 22.04 label would lie about its OS anyway).

Why it exists: the release pipeline's first fire on Forgejo died inside a
job's `Set up helm` step on a read `ECONNRESET` from get.helm.sh (owner
ruling D33). The fix bakes the toolchain at image build time — on the
`build-containers` egress lane production already proves — so workflow
jobs install nothing at run time.

## Base + digest

`FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:<digest>` — a
derivative, not a rebuild. The act image's inventory (git/git-lfs, jq,
python3, node with tool caches, yq, docker CLI + buildx + compose, apt)
is what the `.forgejo/workflows/` family already assumes — five files
since 2026-11-22 (cf-6-feat-builder-bootstrap), the newest being
`builder-bootstrap.yaml`, the dispatch recovery lane; it deliberately
rides the public act-22.04 image rather than this one, because it is what
mints this image when the baked reference is missing, so it must never
depend on it. Rebuilding the baked image on a slim base was rejected
because a too-thin image silently breaks the other pipelines sharing the
runner. The upstream tag is rolling, so the digest
is the authority and the tag is the human label; refreshing it is a
deliberate, upstream-verified edit (re-check the live manifest digest
before pinning). Job containers run as the base's root user on purpose —
the non-root law in `skills/container-creation` serves service
containers; a job shell that dropped to non-root would regress the
apt-getting, system-path-writing jobs that run today (D36).

## Baked tools

Both tools arrive by `COPY --from` of a digest-pinned tool image, not by a
download. Run -4 (2026-11-23, `cf-6-feat-builder-bootstrap-4`) made that
change after three lane dispatches died identically on a filtered
`get.helm.sh` fetch; the retry hardening of run -3 changed nothing because
the path was never the fault — the host was.

| Tool | Version pin | Arrives from | Anchored by |
|---|---|---|---|
| helm | `v3.22.1` (`ARG HELM_VERSION`) | `docker.io/alpine/helm:3.22.1` stage (`AS helmtool`) | `ARG HELM_BIN_SHA256`, a manual pin that bumps with the version |
| cr (chart-releaser) | `1.10.1` (`ARG CR_VERSION`) | `ghcr.io/helm/chart-releaser:v1.10.1-amd64` stage (`AS crtool`) | `ARG CR_BIN_SHA256`, a manual pin that bumps with the version |

The version ARGs carry the renovate `github-releases` annotations
(`helm/helm`, `helm/chart-releaser`); the stage `FROM` lines need none,
because renovate's built-in dockerfile manager tracks them. The anchors are
deliberately unannotated: each is the sha256 of the **extracted binary**,
measured 2026-11-23 byte-identical to the binary inside the official
release tarball (helm `46aeab5e…`, cr `ca45e76c…`) — the archive hashes the
retired `CR_SHA256` pin carried are different numbers, because a tarball and
the file inside it never hash alike. A hash that auto-bumped with the
version would remove the human step that makes the build the supply-chain
gate. `alpine/helm` is a community image that rehosts the official binary
rather than rebuilding it; the official helm-org image publishes cr.

Each build hashes the copied binaries against those anchors and asserts the
version each tool reports, so a mis-baked tool fails the image build, not
the next release fire. `tests/containers/forgejo-runner.sh`
is the static contract for this Dockerfile (pins included — a renovate
version bump must re-pin the suite's literals in the same commit); the
release-workflow suite contract (`tests/services/forgejo-build-charts.sh`)
forbids the workflows from ever installing tools at run time again.

## Bump law

Edit `Dockerfile` → PR → merge to `main` → the `build-containers`
workflow publishes `:yy.mm.N` + `:main` + `:latest` to
`ghcr.io/ownyourio/forgejo-runner` and the instance registry. The runner
labels are **manual pins**: no renovate manager reads
`charts/forgejo-runner/values.yaml` label lines, and the runners never
re-pull a tag they already cached, so a rolling ref would freeze silently
— after a new image builds, bump the four label refs to the new calendar
tag by hand.

First-merge note (D42): this image's first build IS the merge fire's own
`build-containers` run, and a brand-new image's first calendar tag is
deterministic — both registry walks see no tags, so it publishes
`<yy.mm>.1` of the merge month (`26.11.1` for the November landing); the
C06 label pins predict exactly that literal. If the merge crosses into the
next month, the owner amends the one label-pin line (UA-8).
