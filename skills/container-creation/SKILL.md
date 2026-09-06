---
name: container-creation
description: Add custom-built container images to the SpencersLab repo. Use this skill whenever adding or editing an image under containers/, writing or reviewing a Dockerfile for this repo, publishing to ghcr.io/ownyourio, working with the tag-based docker-build GitHub workflow, or renovate ARG pins for git-pinned build sources — even if the user doesn't name this skill directly.
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
above publishes as `ghcr.io/ownyourio/<container-name>`.

## Build pipeline

`.github/workflows/docker-build.yaml` builds and pushes containers
automatically; images are identified by tags.

**Triggers:** pushes to `main`/`dev` that touch `containers/**`, and PRs
targeting `main`/`dev` that touch `containers/**`.

**Per changed container directory:**

1. Detects changed container dirs (only strict DNS-safe names with a
   `Dockerfile` are accepted).
2. Builds `containers/<name>/Dockerfile` with Buildx + GHA cache.
3. **On CI (push to `main`/`dev`)** pushes two tags:
   - `:v<run_number>` — monotonic, immutable (the GitHub `run_number`; this is
     the GitHub Actions analog of ADO's `v$(Build.BuildId)`).
   - `:<branch>` — the mutable rolling tag (`:main` / `:dev`) that the cluster
     pulls.
4. **On PRs** it builds only — it never pushes, so a PR branch named e.g.
   `dev` cannot overwrite the mutable `:dev` tag the cluster pulls.

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
            # Pinned to the newest immutable :v<run> tag — the repo standard
            # (see "Image tag pinning" in helm-chart-creation). Renovate
            # proposes bumps when a newer :v<run> tag is published.
            tag: v123
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

Two ways to reference the image — **pin by default**:

- **`:v<run_number>`** (default) — an immutable point-in-time tag; pin to the
  newest published one. This is the repo standard: reproducible deploys and
  Renovate-managed upgrades (see the pinned-image rule in the
  `helm-chart-creation` skill). Grab the run number from the workflow run or
  `docker buildx imagetools inspect ghcr.io/ownyourio/<name>`.
- **`:main` + `pullPolicy: Always`** — the mutable rolling tag. Use it only for
  a brand-new container that has no pinned tag yet (or when explicitly asked),
  and leave a note to pin it once a versioned build exists.
  `brother-ptouch-automation` is the standing exception (active development —
  it tracks `latest` + `pullPolicy: Always` on purpose).

The change loop when pinned:

1. Edit `containers/<name>/Dockerfile` (or source).
2. Merge to `main` → the workflow rebuilds and repushes the rolling
   `ghcr.io/ownyourio/<name>:main` plus a fresh immutable `:v<run_number>`.
3. Bump `image.tag` in `charts/<name>/values.yaml` to the new `:v<run_number>`
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

- [ ] `containers/<name>/Dockerfile` exists and builds locally
      (`docker build containers/<name>/`)
- [ ] Runs as non-root user (UID 65532 or other non-zero uid)
- [ ] Has a clear `ENTRYPOINT`
- [ ] Exposes a `/health` (or equivalent) endpoint for chart probes if it's a service
- [ ] Renovate pin (if installing from a git URL or downloading a versioned binary)
- [ ] No secrets in the image
- [ ] Apt cleanup in the same RUN as the install
