ARG BUILD_FROM
# The gateway image, pinned by digest (build.yaml) and signature-checked in CI
# before this build. CI's smoke test points it at a locally built image.
ARG PRAKTOR_GATEWAY_REF

# The gateway binary.
FROM ${PRAKTOR_GATEWAY_REF} AS praktor

FROM $BUILD_FROM
ARG PRAKTOR_VERSION
# Sources for the agent image, from the same release, checked against a
# pinned SHA-256 (build.yaml): a changed tarball fails the build.
ARG PRAKTOR_SRC_URL=https://github.com/basigabri/praktor/archive/refs/tags/${PRAKTOR_VERSION}.tar.gz
ARG PRAKTOR_SRC_SHA256

# docker-cli builds the agent image on the device at first start: it bundles
# Claude Code, which can't be redistributed, so it is never published.
# GNU tar: the base image's busybox tar has no --wildcards.
# Alpine packages are signature-checked by apk; versions follow the pinned
# base image's Alpine release.
# hadolint ignore=DL3018
RUN apk add --no-cache docker-cli docker-cli-buildx tar

COPY --from=praktor /praktor /usr/bin/praktor
COPY --from=praktor /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Only what Dockerfile.agent needs. PRAKTOR_SRC_URL is a URL, which COPY
# can't fetch.
# hadolint ignore=DL3020
ADD --checksum=sha256:${PRAKTOR_SRC_SHA256} ${PRAKTOR_SRC_URL} /tmp/praktor-src.tar.gz
RUN mkdir -p /opt/praktor-agent \
    && tar -xzf /tmp/praktor-src.tar.gz -C /opt/praktor-agent --strip-components=1 \
        --wildcards '*/Dockerfile.agent' '*/agent-runner/*' \
    && rm /tmp/praktor-src.tar.gz

ENV PRAKTOR_VERSION=${PRAKTOR_VERSION}

COPY praktor.default.yaml /opt/praktor/praktor.default.yaml
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
