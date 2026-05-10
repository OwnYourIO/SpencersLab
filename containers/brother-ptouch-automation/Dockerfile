FROM python:3.11-slim-bookworm

# Pin upstream to a specific commit so builds are reproducible. The renovate
# comment below lets Renovate auto-bump this hash to track new commits on the
# upstream main branch (see custom manager in `renovate.json`).
# renovate: datasource=github-tags depName=harteWired/brother-ptouch-automation
ARG LABEL_PRINTER_VERSION=b3fa5f0b19f2a29ad4b88ae65fd6efc9e70117f4

WORKDIR /app

# Build deps for label_printer's optional extras:
#   service     → fastapi, uvicorn
#   barcode     → python-barcode, qrcode  (pure Python, no system deps)
#   icons       → cairosvg                (needs libcairo, libpango, libffi at runtime)
# git is required because we install directly from the GitHub repo (upstream
# isn't published to PyPI yet).
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        libcairo2 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libgdk-pixbuf-2.0-0 \
        libffi8 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "label-printer[service,barcode,icons] @ git+https://github.com/harteWired/brother-ptouch-automation.git@${LABEL_PRINTER_VERSION}"

# Non-root user (uid 65532). Note that the python:3.11-slim-bookworm base
# image already ships an `lp` system user (uid 7) for the legacy LPR printer
# system, so we use a different username and explicitly pin the uid we want.
RUN groupadd --system --gid 65532 labelprinter \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false --home /home/labelprinter --create-home labelprinter \
    && mkdir -p /home/labelprinter/.config/label-printer \
    && chown -R labelprinter:labelprinter /home/labelprinter

USER labelprinter
WORKDIR /home/labelprinter

EXPOSE 8765

# `lp serve` is the FastAPI entry point. Bind 0.0.0.0 so the k8s Service can reach it.
ENTRYPOINT ["lp", "serve", "--host", "0.0.0.0", "--port", "8765"]
