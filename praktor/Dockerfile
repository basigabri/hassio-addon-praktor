ARG BUILD_FROM
ARG PRAKTOR_VERSION
# Where the gateway comes from: the fork's published multi-arch image by
# default. CI points it at a locally built image (PRAKTOR_IMAGE=praktor-gateway
# with PRAKTOR_VERSION as its tag).
ARG PRAKTOR_IMAGE=ghcr.io/basigabri/praktor

# The gateway binary.
FROM ${PRAKTOR_IMAGE}:${PRAKTOR_VERSION} AS praktor

FROM $BUILD_FROM
ARG PRAKTOR_VERSION
# Sources for the agent image, from the same release by default.
ARG PRAKTOR_SRC_URL=https://github.com/basigabri/praktor/archive/refs/tags/${PRAKTOR_VERSION}.tar.gz

# docker-cli builds the agent image on the device at first start: it bundles
# Claude Code, which can't be redistributed, so it is never published.
# Versions come from the pinned base image's Alpine release.
# hadolint ignore=DL3018
RUN apk add --no-cache docker-cli docker-cli-buildx

COPY --from=praktor /praktor /usr/bin/praktor
COPY --from=praktor /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Only what Dockerfile.agent needs, from the same release. PRAKTOR_SRC_URL
# is a URL, which COPY can't fetch.
# hadolint ignore=DL3020
ADD ${PRAKTOR_SRC_URL} /tmp/praktor-src.tar.gz
RUN mkdir -p /opt/praktor-agent \
    && tar -xzf /tmp/praktor-src.tar.gz -C /opt/praktor-agent --strip-components=1 \
        --wildcards '*/Dockerfile.agent' '*/agent-runner/*' \
    && rm /tmp/praktor-src.tar.gz

ENV PRAKTOR_VERSION=${PRAKTOR_VERSION}

COPY praktor.default.yaml /opt/praktor/praktor.default.yaml
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
