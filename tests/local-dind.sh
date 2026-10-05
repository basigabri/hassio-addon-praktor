#!/usr/bin/env bash
# Runs the smoke test inside a throwaway Docker-in-Docker daemon, so it can't
# touch a live Praktor (praktor-net, containers, volumes) on this machine.
# The gateway image is built inside from a local Praktor checkout.
#
#   PRAKTOR_DIR=../praktor tests/local-dind.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
PRAKTOR_DIR=$(cd "${PRAKTOR_DIR:?set PRAKTOR_DIR to a Praktor checkout}" && pwd)
NAME=praktor-smoke-dind
CACHE=praktor-smoke-dind-cache
OUT=${SMOKE_LOG_DIR:-$REPO/tests/logs}

cleanup() {
	local rc=$?
	rm -rf "$OUT"
	mkdir -p "$OUT"
	docker cp "$NAME:/logs/." "$OUT" >/dev/null 2>&1 || true
	docker rm -f "$NAME" >/dev/null 2>&1 || true
	if [[ -n ${SMOKE_DIND_CLEAN:-} ]]; then docker volume rm "$CACHE" >/dev/null 2>&1 || true; fi
	echo "logs in $OUT"
	exit "$rc"
}
trap cleanup EXIT

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --privileged --name "$NAME" -e DOCKER_TLS_CERTDIR= -v "$CACHE:/var/lib/docker" \
	-v "$REPO:/app:ro" -v "$PRAKTOR_DIR:/praktor:ro" docker:29-dind >/dev/null
for _ in $(seq 60); do
	docker exec "$NAME" docker info >/dev/null 2>&1 && break
	sleep 1
done
docker exec "$NAME" apk add --no-cache -q bash curl jq coreutils
docker exec "$NAME" docker build -q -t praktor-gateway:ci --build-arg VERSION=ci /praktor >/dev/null
docker exec -e SMOKE_LOG_DIR=/logs -e SMOKE_STRICT -e PRAKTOR_SRC_URL "$NAME" bash /app/tests/smoke.sh
