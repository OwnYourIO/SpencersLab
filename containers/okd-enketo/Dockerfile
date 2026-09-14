# ODK Central Enketo. getodk publishes no enketo image (only
# central-service/central-nginx/pyxform-http on GHCR), so this reproduces
# getodk/central's enketo.dockerfile at the pinned Central commit. Consumed by
# charts/okd. When bumping CENTRAL_VERSION, also check that commit's
# enketo.dockerfile FROM line and bump the base image below if it changed.
FROM ghcr.io/enketo/enketo:7.6.4

# Pinned to the immutable commit SHA of getodk/central v2026.3.0 (mutable
# tags could be re-pointed; raw.githubusercontent accepts SHAs).
# renovate: datasource=github-tags depName=getodk/central
ARG CENTRAL_VERSION=c008e6904efdb3d2b2ac6a84f4ba18b74c310dda

ENV ENKETO_SRC_DIR=/srv/src/enketo/packages/enketo-express
WORKDIR ${ENKETO_SRC_DIR}

# The three files getodk/central's enketo.dockerfile copies. The chart mounts
# its own config.json.template over the baked one at runtime (redis sidecar
# hosts); start-enketo.sh regenerates config/config.json from the template at
# every boot, so no config.json is baked here (upstream's cp serves a client
# build step this image does not run).
ADD https://raw.githubusercontent.com/getodk/central/${CENTRAL_VERSION}/files/shared/envsub.awk /scripts/envsub.awk
ADD https://raw.githubusercontent.com/getodk/central/${CENTRAL_VERSION}/files/enketo/config.json.template ${ENKETO_SRC_DIR}/config/config.json.template
ADD https://raw.githubusercontent.com/getodk/central/${CENTRAL_VERSION}/files/enketo/start-enketo.sh ${ENKETO_SRC_DIR}/start-enketo.sh

RUN chmod +x /scripts/envsub.awk start-enketo.sh

EXPOSE 8005
ENTRYPOINT ["./start-enketo.sh"]
