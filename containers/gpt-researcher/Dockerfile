# GPT Researcher backend (FastAPI research agent), built from upstream
# assafelovic/gpt-researcher at the pinned commit below. Upstream's Docker Hub
# images ship rarely (the `latest` there is from 2025-03) and lack what the
# lab deployment needs, so this repo builds its own from upstream master:
#   - sentence-transformers + a BAKED-IN embedding model — gpt-researcher's
#     context pipeline calls embeddings unconditionally; the lab llama-swap
#     endpoint serves no embedding model, so local embeddings keep research
#     runs self-contained (switch EMBEDDING to an OpenAI-compatible endpoint
#     if llama-swap ever gains one).
#   - a non-root runtime user.
#
# Consumed by charts/gpt-researcher as ghcr.io/ownyourio/gpt-researcher.
FROM python:3.15-slim-bookworm

# renovate: datasource=git-refs depName=assafelovic/gpt-researcher
ARG GPTR_VERSION=5cdad9cb434754188b78bd998df18dd8d502cf7e

RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/assafelovic/gpt-researcher.git . \
    && git checkout "$GPTR_VERSION"

# CPU-only torch wheel first (the PyPI default ships CUDA libs), then the app
# requirements plus the local embedding stack, then the gpt_researcher package
# itself. Upstream runs uvicorn from the repo root so the package resolves via
# CWD; this image runs from backend/ (see ENTRYPOINT below), so the package
# must be installed explicitly. --no-deps: dependencies are already pinned by
# requirements.txt above — don't let the resolver touch them.
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r requirements.txt sentence-transformers \
    && pip install --no-cache-dir --no-deps .

# Bake the embedding model into the image so research runs need no egress.
ENV HF_HOME=/app/.hf-cache
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')"

RUN groupadd --system --gid 65532 gpt-researcher \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false \
       --home /home/gpt-researcher --create-home gpt-researcher \
    && mkdir -p /app/backend/outputs /app/backend/logs \
    && chown -R gpt-researcher:gpt-researcher /app /home/gpt-researcher
USER gpt-researcher

# The server resolves outputs/ and logs/ relative to the CWD — upstream runs
# it from backend/ (see backend/run_server.py).
WORKDIR /app/backend
EXPOSE 8000
ENTRYPOINT ["uvicorn", "server.app:app", "--host", "0.0.0.0", "--port", "8000"]
