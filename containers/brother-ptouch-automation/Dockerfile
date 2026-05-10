FROM python:3.11-slim-bookworm

# renovate: datasource=github-tags depName=harteWired/brother-ptouch-automation
ARG LABEL_PRINTER_VERSION=b3fa5f0b19f2a29ad4b88ae65fd6efc9e70117f4

WORKDIR /app

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

RUN useradd -u 65532 -r -m -d /home/lp -s /bin/false lp \
    && mkdir -p /home/lp/.config/label-printer \
    && chown -R lp:lp /home/lp

USER lp
WORKDIR /home/lp

EXPOSE 8765

ENTRYPOINT ["lp", "serve", "--host", "0.0.0.0", "--port", "8765"]
