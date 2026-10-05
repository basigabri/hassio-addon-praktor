ARG BUILD_FROM
ARG PRAKTOR_VERSION

# The gateway binary, from the fork's published multi-arch image.
FROM ghcr.io/basigabri/praktor:${PRAKTOR_VERSION} AS praktor

FROM $BUILD_FROM
ARG PRAKTOR_VERSION

# docker-cli builds the agent image on the device at first start: it bundles
# Claude Code, which can't be redistributed, so it is never published.
RUN apk add --no-cache docker-cli docker-cli-buildx

COPY --from=praktor /praktor /usr/bin/praktor
COPY --from=praktor /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Only what Dockerfile.agent needs, from the same release.
ADD https://github.com/basigabri/praktor/archive/refs/tags/${PRAKTOR_VERSION}.tar.gz /tmp/praktor-src.tar.gz
RUN mkdir -p /opt/praktor-agent \
    && tar -xzf /tmp/praktor-src.tar.gz -C /opt/praktor-agent --strip-components=1 \
        --wildcards '*/Dockerfile.agent' '*/agent-runner/*' \
    && rm /tmp/praktor-src.tar.gz

ENV PRAKTOR_VERSION=${PRAKTOR_VERSION}

COPY praktor.default.yaml /opt/praktor/praktor.default.yaml
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
