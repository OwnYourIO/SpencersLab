# Container Creation Guide for SpencersLab

This document covers the conventions for adding custom-built container images to
SpencersLab. Pair it with `HELM_CHART_CREATION_GUIDE.md` — the chart consumes
the image this guide produces.

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
    ├── VERSION             # REQUIRED — semver string, e.g. "0.0.0"
    ├── requirements.txt    # OPTIONAL — pip deps if you're shipping Python
    ├── main.py             # OPTIONAL — source files if you ship code in-repo
    └── ...                 # any other build-context files
```

The directory name is significant: it becomes the image name. The container
above publishes as `ghcr.io/ownyourio/<container-name>`.

## Build pipeline

`.github/workflows/docker-build.yaml` builds and pushes containers automatically.

**Trigger:** any push to `main` that touches `containers/**`.

**Per changed container directory, it:**

1. Reads `containers/<name>/VERSION` (creates `0.0.0` if missing).
2. **Bumps the patch version** (`1.2.3` → `1.2.4`) and commits the new
   `VERSION` back to `main` with the message
   `Bump <name> version to <version>`.
3. Builds `containers/<name>/Dockerfile` with Buildx + GHA cache.
4. Pushes to `ghcr.io/ownyourio/<name>` with three tags:
   - `:latest`
   - `:<version>` (e.g. `:1.2.4`)
   - `:v<version>` (semver-prefix variant)
5. Creates a git tag `<name>-v<version>` and pushes it.

The version bump happens **even on the first build** (initial `VERSION=0.0.0`
becomes `0.0.1` after the first successful build).

**There is no manual release process** — merging to main is the entire flow.

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
            # Pin to the version the docker-build workflow has bumped to.
            # Update this when you bump the container's VERSION file (or use
            # `:latest` + `pullPolicy: Always` during initial development).
            tag: 1.2.4
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

After the first successful build (which bumps `VERSION` 0.0.0 → 0.0.1),
update your chart's `image.tag` to that version. From then on, every
container change becomes:

1. Edit `containers/<name>/Dockerfile` (or source).
2. Merge to `main` → workflow auto-bumps `VERSION` and pushes
   `ghcr.io/ownyourio/<name>:<new-version>`.
3. Bump `image.tag` in `charts/<name>/values.yaml` to the new version.
4. Merge to `main` → `release.yaml` cuts a new chart release; ArgoCD picks it up.

## Worked example: brother-ptouch-automation

- **Container**: [`containers/brother-ptouch-automation/`](containers/brother-ptouch-automation/)
- **Chart**: [`charts/brother-ptouch-automation/`](charts/brother-ptouch-automation/)
- **Pattern**: Python project installed from a git pin, FastAPI service entrypoint,
  non-root uid 65532, single PVC for state, reaches a physical Brother label
  printer on the LAN over TCP:9100 + UDP:161.
- **Renovate**: tracks `harteWired/brother-ptouch-automation` via the
  `github-tags` custom manager + ARG comment in the Dockerfile.

## Checklist

Before merging a new container to `main`:

- [ ] `containers/<name>/Dockerfile` exists and builds locally
      (`docker build containers/<name>/`)
- [ ] `containers/<name>/VERSION` exists (`0.0.0` is fine for first build)
- [ ] Runs as non-root user (UID 65532 or other non-zero uid)
- [ ] Has a clear `ENTRYPOINT`
- [ ] Exposes a `/health` (or equivalent) endpoint for chart probes if it's a service
- [ ] Renovate pin (if installing from a git URL or downloading a versioned binary)
- [ ] No secrets in the image
- [ ] Apt cleanup in the same RUN as the install
