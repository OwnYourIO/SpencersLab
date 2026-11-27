---
name: container-creation
description: Add custom-built container images to the SpencersLab repo. Use this skill whenever adding or editing an image under containers/, writing or reviewing a Dockerfile for this repo, publishing to ghcr.io/ownyourio or the instance's own Forgejo registry (same tag set), working with the tag-based build-containers Forgejo workflow, or renovate ARG pins for git-pinned build sources — even if the user doesn't name this skill directly.
---

# Container Creation (SpencersLab)

Conventions for adding custom-built container images to SpencersLab. Pair it
with the `helm-chart-creation` skill — the chart consumes the image this
skill produces.

## When to create a container

Build a custom container when:

- **No upstream image exists** (e.g. you're packaging a project that only ships
  source — like `brother-ptouch-automation`).
- **The upstream image is unusable as-is**: needs different `ENTRYPOINT`, missing
  extras, doesn't run non-root, doesn't expose a `/health` endpoint, etc.
- **You need to bundle a small bit of glue code** (the
  `traefik-mqtt-allowlist` container is a single `main.py` script).

If a usable upstream image exists, **don't** build your own — just point your
chart at it.

## Directory layout

```
containers/
└── <container-name>/
    ├── Dockerfile          # REQUIRED
    ├── requirements.txt    # OPTIONAL — pip deps if you're shipping Python
    ├── main.py             # OPTIONAL — source files if you ship code in-repo
    └── ...                 # any other build-context files
```

The directory name is significant: it becomes the image name. The container
above publishes as `ghcr.io/ownyourio/<container-name>` and, with the same
tags, as `<instance-host>/curatedforest/<container-name>` on the building
instance's own Forgejo registry.

## Build pipeline

`.forgejo/workflows/build-containers.yaml` builds and pushes containers
automatically on lab Forgejo instances; what an instance publishes is
decided by its `ROLE` repo variable — a comma list without spaces over
`{dev, prod}` (e.g. `dev,prod`; unset defaults to both roles), never by an
instance URL. `on:` cannot be conditioned, so the role/event split lives in
job `if:` guards. Images are identified by tags.

**Triggers:** pushes to `main` that touch `containers/**`, pull requests
targeting `main` that touch `containers/**` (the forge is where PRs live),
plus `workflow_dispatch`.

**Per changed container directory:**

1. Detects changed container dirs over the event's commit range:
    - a push diffs `marker..sha` — from the last-built marker ref, a
      Forgejo-local branch the workflow itself advances to the sha of every
      fully-green push build. A change that a dead or cancelled run lost is
      therefore re-covered by the next push instead of staying skipped
      forever. With no marker yet (the bootstrap state) a push falls back to
      the whole `before..sha` range. Either way the diff is a tree diff, so
      every commit between the endpoints counts, not just the tip. The
      detect job's checkout therefore carries `fetch-depth: 0`: at the
      shallow default the range endpoints are absent locally and the diff
      dies on `bad object` (exit 128) — loud, never a silent partial set.
      The full fetch measured 21.23 MiB / 1,849 ms against the instance from
      a workspace clone; no run of this workflow has executed yet, so
      every number here is offline. Depth-0 is not a correctness verdict:
      a depth-1 checkout plus a targeted fetch of `before` measured
      correct as well (172 ms) and was declined by owner ruling, not by
      fact.
    - a pull request diffs `merge-base..head`, so a base that moved
      after the head branched contributes nothing. The merge base is
      resolved with a hand-rolled `git merge-base` call: the
      `git diff --merge-base` flag would need git ≥ 2.43 and the runner
      image's git version is unverified.
    - the first push to a branch carries an all-zero `before`. It is
      deliberately `tip-only` — `HEAD^..HEAD`, just the pushed commit —
      and announces itself with a `::warning::` line in the run log.
    - an empty `before` is fatal: no push payload sends one, so its
      arrival means a wrong accessor or a misrouted event. A range whose
      endpoints do not resolve fails the job loudly too.
    - every run echoes the resolved set with its event, endpoints and
      base source. An empty set on a real push or PR range warns with
      `::warning::`; a no-op push (its `before` equals its `sha`), an
      empty `workflow_dispatch` list and an empty range measured FROM the
      marker stay un-annotated — the first two because emptiness is their
      correct semantics by ruling, the last because a marker range that
      resolves empty PROVES nothing was missed, so it reads as one plain
      info line. These lines are run-log text; this Forgejo build
      surfaces nothing richer, and none of it is live-validated.
    - the marker advances only on a push run whose build matrix
      published fully green: a partial failure leaves it put, so the
      re-run re-diffs the same `marker..sha` and retries the residue.
      The advance is a plain push, and git's own non-fast-forward
      refusal is what keeps the marker from ever moving backwards.
    - `total_commits` reads 0 on Forgejo push payloads, so detection
      never counts commits: an empty commit list is not an empty range.
   Only strict DNS-safe names with a `Dockerfile` are accepted — the
   gate applies to every source, a dispatch's named list included.
2. Builds `containers/<name>/Dockerfile` with plain `docker build` (the
   runner's persistent dind layer store is the build cache).
3. **On a main/dispatch build with `prod` in `ROLE`** it pushes three tags
   — `:yy.mm.N`, `:latest`, `:main` — to **both** registries,
   `ghcr.io/ownyourio/<name>` and `<instance-host>/curatedforest/<name>`:
   - `:yy.mm.N` — the calendar release: one past the highest `yy.mm.*` tag
     across **both** registries, each side advanced past any manifest it
     already holds, every walk finished before the first push. Neither
     registry has tag immutability, so a re-run must not overwrite a
     published release — every successful build publishes the same N
     everywhere it pushed; failures leave gaps, never clobbers.
   - `:latest` and `:main` — the mutable rolling tags the cluster pulls,
     mirrored to both registries.
4. **On a PR with `dev` in `ROLE`** it pushes `pr-<branch>-<sha>` to the
   instance's own registry only — the `pr-` prefix and build hash can never
   shadow a rolling or calendar tag, and ghcr never sees a PR build.

Pushing takes human-minted PATs: `FORGE_PUSH_TOKEN` (non-admin,
`write:package`) for the instance registry — the Actions job token cannot
write packages — and `PUSH_TOKEN_GH` for ghcr (the instance's established GitHub-side secret — the
same name the chart-release and main-sync legs carry). The instance-registry host
is derived from the instance's own server URL inside the workflow; no URL
literals live in the file.

**Bootstrap lane (recovery).** `.forgejo/workflows/builder-bootstrap.yaml`
(rem)mints the lab's build image — `containers/forgejo-runner` — the
baked job image every other lane schedules on, which is exactly what is
missing when the automatic lanes cannot run. Its job therefore rides the
PUBLIC act-22.04 label instead of the baked image (that inversion is the
whole point: it is the bootstrap paradox the lane exists to break), fires
only on `workflow_dispatch` with no input at all (owner ruling
2026-11-22: the dispatch is the button; it mints exactly this one image),
stays confined to `prod`-role instances by a narrow ROLE guard, and
publishes the same three tags to the building instance's own registry
ONLY, walking that registry's calendar tags alone — a bare dispatch
(re)mints exactly this image and nothing reaches ghcr from this lane
(owner ruling 2026-11-22, R-B + OQ-1=B). A recovery lane, not a second
automatic publisher.

`.github/workflows/docker-build.yaml` is a `workflow_dispatch`-only manual
rebuild fallback on the GitHub side — its automatic trigger blocks are kept
commented in the file, so it fires on no push and no PR.

**There is no manual release process** — merging to `main` is the entire flow.
There is nothing to bump and nothing to tag by hand.

## Dockerfile conventions

Look at `containers/traefik-mqtt-allowlist/Dockerfile` and
`containers/brother-ptouch-automation/Dockerfile` as reference implementations.

### Base image

Prefer official slim variants:

- Python: `python:3.11-slim-bookworm` (or current LTS)
- Node: `node:20-bookworm-slim`
- Go: multi-stage with `golang:1.22` → `gcr.io/distroless/static:nonroot`

Pin to a major.minor; let renovate bump patches.

### Layer ordering

```dockerfile
FROM python:3.11-slim-bookworm

# 1. Build-time args / version pins (changes invalidate everything below)
ARG SOMETHING_VERSION=1.2.3

# 2. System deps (apt-get) — cleanup in the same RUN
RUN apt-get update && apt-get install -y --no-install-recommends \
        package1 \
        package2 \
    && rm -rf /var/lib/apt/lists/*

# 3. Language-level deps (pip / npm) — cached separately from app code
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Application code (changes most often — keep last)
COPY . .

# 5. Runtime user / filesystem prep
RUN useradd -u 65532 -r -m -d /home/app -s /bin/false app \
    && chown -R app:app /app /home/app
USER app

# 6. Interface declaration
EXPOSE 8080
ENTRYPOINT ["python3", "-u", "/app/main.py"]
```

### Non-root user

Run as **uid 65532** (matches the `nonroot` distroless convention). The chart
that consumes the image should:

- Drop `ALL` capabilities (`securityContext.capabilities.drop: ["ALL"]`).
- Set `allowPrivilegeEscalation: false`.
- Set `readOnlyRootFilesystem: true` when feasible (mount writable paths as PVCs/emptyDirs).

**⚠️ Username collisions**: some Debian-based images already have system users
that conflict with common app names. Notably, `python:*-slim-bookworm` ships
an `lp` user (uid 7) for the legacy LPR printer system. Use a unique
username and explicitly pin the uid:

```dockerfile
RUN groupadd --system --gid 65532 app \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false \
       --home /home/app --create-home app
USER app
```

If `useradd` fails with `user 'X' already exists`, pick a different name —
do not try to reuse the existing system user (its shell, home, and supplementary
groups are not what you want).

### Pinning upstream sources

If you're installing a Python package from a Git URL (because upstream hasn't
published to PyPI yet), or downloading a binary at build time, **pin the
version with an ARG + renovate comment**:

```dockerfile
# renovate: datasource=github-tags depName=harteWired/brother-ptouch-automation
ARG LABEL_PRINTER_VERSION=b3fa5f0b19f2a29ad4b88ae65fd6efc9e70117f4

RUN pip install --no-cache-dir \
    "label-printer @ git+https://github.com/harteWired/brother-ptouch-automation.git@${LABEL_PRINTER_VERSION}"
```

The renovate comment is parsed by the custom manager in `renovate.json` and
triggers automatic PRs when the upstream advances.

Supported `datasource` values for the ARG-pin pattern:
- `github-tags` — tracks release tags
- `github-releases` — tracks GitHub Releases
- `git-refs` — tracks branch heads (use for projects without tags/releases)

### Apt deps for common Python extras

When packaging a Python project, watch for these system libs:

| Extra | Apt packages needed |
|---|---|
| `cairosvg` | `libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 libffi8` |
| `pillow` (advanced) | `libjpeg62-turbo zlib1g libtiff6` |
| `psycopg2` (non-binary) | `libpq5 libpq-dev` (dev only at build time, drop after) |
| `pyusb` | `libusb-1.0-0` |
| `cryptography` (build) | `gcc libffi-dev libssl-dev` (build-only, drop after) |
| `lxml` | `libxml2 libxslt1.1` |
| `git+https://...` installs | `git` |

Use `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*` in the same `RUN`
to keep layers small.

### Antipatterns

- ❌ Running as root (UID 0). Always create a non-root user.
- ❌ `:latest` base images — pin to a specific minor at minimum.
- ❌ Mutable `apt-get install` without `rm -rf /var/lib/apt/lists/*`.
- ❌ Baking secrets into layers. Read from env / mounted secrets at runtime.
- ❌ Copying the entire repo with `COPY . .` from the project root —
  set the build context to `containers/<name>/` (the workflow already does this).
- ❌ Multiple `apt-get install` calls in separate `RUN` instructions
  (each one becomes a layer; consolidate).
- ❌ `CMD` over `ENTRYPOINT` for service containers. Use `ENTRYPOINT` so
  Kubernetes args are appended, not replaced.
- ❌ `RUN`-referenced fetcher binaries (`wget`/`curl`) on lean bases —
  prove every `RUN`-referenced binary against the base image's actual
  layer contents (MCR/GHCR anonymous v2 API, layer tar listings) or use
  a zero-binary mechanism (`ADD <url>`; digest-pinned `COPY --from` tool
  image, the forgejo-runner idiom). The dotnet `runtime:10.0` base
  carries neither (cf-133 incident 2, 2026-11-27, exit 127).

## Consuming the image from a Helm chart

In your `charts/<name>/values.yaml`:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          image:
            repository: ghcr.io/ownyourio/<container-name>
            # Pinned to the newest immutable :yy.mm.N calendar tag — the repo
            # standard (see "Image tag pinning" in helm-chart-creation).
            # Renovate proposes bumps when a newer calendar tag is published.
            tag: 26.11.1
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

Two ways to reference the image — **pin by default**:

- **`:yy.mm.N`** (default) — an immutable calendar-release tag; pin to the
  newest published one — but check that the newest is YOURS: the registry
  maximum is not automatically the right bump target, because a build that
  predates the merge you ship can already occupy a higher N. Name
  your own build's tag. This is the repo standard: reproducible deploys
  and Renovate-managed upgrades (see the pinned-image rule in the
  `helm-chart-creation` skill). Grab the tag from the Forgejo run that
  built your merge, or registry-side anonymously: the pull-scoped token
  (`GET https://ghcr.io/token?scope=repository:ownyourio/<name>:pull`) plus
  `GET https://ghcr.io/v2/ownyourio/<name>/tags/list`. Do NOT enumerate
  with an untagged `docker buildx imagetools inspect` — untagged, it
  resolves `:latest` (a rolling tag every main build repoints) and lists
  nothing. Charts still on a legacy `:v<run_number>` pin stay there until
  the one-time bump PR moves them onto `:yy.mm.N`; meanwhile the calendar
  versioning rule in `renovate.json` makes Renovate skip those deps
  silently (no downgrade PRs).
- **`:main` + `pullPolicy: Always`** — the mutable rolling tag. Use it only for
  a brand-new container that has no pinned tag yet (or when explicitly asked),
  and leave a note to pin it once a versioned build exists.
  `brother-ptouch-automation` is the standing exception (active development —
  it tracks `latest` + `pullPolicy: Always` on purpose).

The instance registries mirror the same tag set 1:1 as
`<instance-host>/curatedforest/<name>` and allow anonymous pull (the
`curatedforest` org is public) — a valid manual pull source for debugging.
Pins stay on ghcr `:yy.mm.N`: the calendar rule in `renovate.json` tracks
`ghcr.io/ownyourio/*` only, so a forge-registry pin would sit outside the
rule until that rule widens.

The change loop when pinned:

1. Edit `containers/<name>/Dockerfile` (or source).
2. Merge to `main` → a `prod`-role instance rebuilds and repushes the
   rolling `ghcr.io/ownyourio/<name>:main` and `:latest` plus a fresh
   calendar `:yy.mm.N` — to ghcr and the instance's own registry alike.
3. Bump `image.tag` in `charts/<name>/values.yaml` to the new `:yy.mm.N`
   (Renovate opens this PR for you once the tag is published).

## Worked example: brother-ptouch-automation

- **Container**: `containers/brother-ptouch-automation/`
- **Chart**: `charts/brother-ptouch-automation/`
- **Pattern**: Python project installed from a git pin, FastAPI service entrypoint,
  non-root uid 65532, single PVC for state, reaches a physical Brother label
  printer on the LAN over TCP:9100 + UDP:161.
- **Renovate**: tracks `harteWired/brother-ptouch-automation` via the
  `github-tags` custom manager + ARG comment in the Dockerfile.

## Checklist

Before merging a new container to `main`:

- [ ] `containers/<name>/Dockerfile` exists; the build gate is CI — agent
      sessions have no docker daemon, so the Forgejo
      `build-containers.yaml` run on the merged main (via the main-sync fan) is authoritative, and
      build-critical facts (base image layout, binary paths, digests) are
      verified locally from the pinned images' GHCR layer tar-listings
      instead
- [ ] Runs as non-root user (UID 65532 or other non-zero uid)
- [ ] Has a clear `ENTRYPOINT`
- [ ] Exposes a `/health` (or equivalent) endpoint for chart probes if it's a service
- [ ] Renovate pin (if installing from a git URL or downloading a versioned binary)
- [ ] No secrets in the image
- [ ] Apt cleanup in the same RUN as the install
