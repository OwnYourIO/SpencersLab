# forgejo-runner

The act job image behind the four act-24.04-family Forgejo runner labels
(`ubuntu-latest`, `ubuntu-24.04`, `docker`, `node22` in
`charts/forgejo-runner/values.yaml`) — every Forgejo CI job that requests
one of them runs in this image. `ubuntu-22.04` deliberately stays on the
plain upstream `act-22.04` (no job requests it and a 24.04-content image
behind a 22.04 label would lie about its OS).

Why it exists: the release pipeline's first fire on Forgejo died inside a
job's `Set up helm` step on a read `ECONNRESET` from get.helm.sh (owner
ruling D33). The fix bakes the toolchain at image build time — on the
`containers-build` egress lane production already proves — so workflow
jobs install nothing at run time.

## Base + digest

`FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:<digest>` — a
derivative, not a rebuild. The act image's inventory (git/git-lfs, jq,
python3, node with tool caches, yq, docker CLI + buildx + compose, apt)
is what all four `.forgejo/workflows/` already assume; rebuilding it on a
slim base was rejected because a too-thin image silently breaks the other
pipelines sharing the runner. The upstream tag is rolling, so the digest
is the authority and the tag is the human label; refreshing it is a
deliberate, upstream-verified edit (re-check the live manifest digest
before pinning). Job containers run as the base's root user on purpose —
the non-root law in `skills/container-creation` serves service
containers; a job shell that dropped to non-root would regress the
apt-getting, system-path-writing jobs that run today (D36).

## Baked tools

| Tool | Pin | Tracked by |
|---|---|---|
| helm | `v3.22.1` (`ARG HELM_VERSION`) | renovate `github-releases` annotation → `helm/helm` |
| cr (chart-releaser) | `1.10.1` + sha256 (`ARG CR_VERSION`/`CR_SHA256`) | annotation → `helm/chart-releaser`; the digest line is a manual pin that must bump with the version |

Both install to `/usr/local/bin` at build time with a `sha256sum -c`
verification and a version assert, so a mis-baked tool fails the image
build, not the next release fire. `tests/containers/forgejo-runner.sh`
is the static contract for this Dockerfile (pins included — a renovate
version bump must re-pin the suite's literals in the same commit); the
release-workflow suite contract (`tests/services/forgejo-release.sh`)
forbids the workflows from ever installing tools at run time again.

## Bump law

Edit `Dockerfile` → PR → merge to `main` → the `containers-build`
workflow publishes `:yy.mm.N` + `:main` + `:latest` to
`ghcr.io/ownyourio/forgejo-runner` and the instance registry. The runner
labels are **manual pins**: no renovate manager reads
`charts/forgejo-runner/values.yaml` label lines, and the runners never
re-pull a tag they already cached, so a rolling ref would freeze silently
— after a new image builds, bump the four label refs to the new calendar
tag by hand.

First-merge note (D42): this image's first build IS the merge fire's own
`containers-build` run, and a brand-new image's first calendar tag is
deterministic — both registry walks see no tags, so it publishes
`<yy.mm>.1` of the merge month (`26.11.1` for the November landing); the
C06 label pins predict exactly that literal. If the merge crosses into the
next month, the owner amends the one label-pin line (UA-8).
