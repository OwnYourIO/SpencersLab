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

RUN git clone https://github.com/harteWired/brother-ptouch-automation.git /opt/label-printer \
    && git -C /opt/label-printer checkout ${LABEL_PRINTER_VERSION}

RUN pip install --no-cache-dir -e \
    "/opt/label-printer[service,barcode,icons]"

RUN groupadd --system --gid 65532 labelprinter \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false --home /home/labelprinter --create-home labelprinter \
    && mkdir -p /home/labelprinter/.config/label-printer \
    && chown -R labelprinter:labelprinter /home/labelprinter

USER labelprinter
WORKDIR /home/labelprinter
EXPOSE 8765
ENTRYPOINT ["lp", "serve", "--host", "0.0.0.0", "--port", "8765"]