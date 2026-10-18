# GPT Researcher frontend (Next.js production server), built from upstream
# assafelovic/gpt-researcher at the pinned commit below.
#
# The Next.js server (port 3000) serves the UI and reaches the backend pod at
# localhost:8000 two ways:
#   - app/api/* route handlers (chat, reports) read NEXT_PUBLIC_GPTR_API_URL
#     at RUNTIME (server-side code) — the chart sets http://localhost:8000
#   - next.config.mjs rewrites /outputs/* using NEXT_PUBLIC_BACKEND_URL
#     (runtime) — same value
# Deliberately built WITHOUT NEXT_PUBLIC_GPTR_API_URL: the env would be
# inlined into the browser bundle at build time, but the client falls back to
# same-origin (helpers/getHost.ts) — exactly what the chart's ingress wants
# (direct browser paths like /ws are routed to the backend service on the
# same host by charts/gpt-researcher/templates/ingress-backend.yaml).
#
# Consumed by charts/gpt-researcher as ghcr.io/ownyourio/gpt-researcher-frontend.
FROM node:20-bookworm-slim

# renovate: datasource=git-refs depName=assafelovic/gpt-researcher
ARG GPTR_VERSION=5cdad9cb434754188b78bd998df18dd8d502cf7e

# ca-certificates: node:*-slim ships no CA bundle, which git clone and npm
# install both need for HTTPS (python:slim includes one, the backend image
# doesn't have to install it).
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/assafelovic/gpt-researcher.git /src \
    && cd /src && git checkout "$GPTR_VERSION" \
    && cp -a /src/frontend/nextjs/. /app/ \
    && rm -rf /src

RUN npm install --legacy-peer-deps
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build && npm prune --production

RUN groupadd --system --gid 65532 gptr \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false \
       --home /home/gptr --create-home gptr \
    && chown -R gptr:gptr /app /home/gptr
USER gptr

EXPOSE 3000
ENTRYPOINT ["npm", "run", "start"]
