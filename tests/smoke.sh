#!/usr/bin/env bash
# Supervisor-like smoke test: build the App image and start it the way the
# Supervisor does (s6 /init, options from a fake Supervisor API, the Docker
# socket at /run/docker.sock, /config and /data volumes, an App hostname on
# its own network), then check what it logs and serves.
#
# It needs a Docker daemon it may fill with test containers and refuses to
# run next to a live Praktor; on a workstation use tests/local-dind.sh.
#
# Env:
#   GATEWAY_IMAGE   gateway image to bundle, as name:tag (default praktor-gateway:ci;
#                   must exist on the daemon)
#   PRAKTOR_SRC_URL agent sources tarball (default: the fork's main branch)
#   SMOKE_STRICT=1  fail on known bugs instead of reporting them
#   SMOKE_LOG_DIR   where logs go (default tests/logs)
#   PRAKTOR_SRC_SHA256  checksum of PRAKTOR_SRC_URL (default: computed)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
LOG_DIR=${SMOKE_LOG_DIR:-$REPO/tests/logs}
GATEWAY_IMAGE=${GATEWAY_IMAGE:-praktor-gateway:ci}
PRAKTOR_SRC_URL=${PRAKTOR_SRC_URL:-https://github.com/basigabri/praktor/archive/refs/heads/main.tar.gz}
# The App's Dockerfile verifies the tarball's SHA-256. Releases pin it in
# build.yaml; for a branch tarball the test computes it here.
SRC_SHA256=${PRAKTOR_SRC_SHA256:-$(curl -fsSL "$PRAKTOR_SRC_URL" | sha256sum | cut -d' ' -f1)}
PORT=${SMOKE_PORT:-18090}
API="http://127.0.0.1:${PORT}"

APP=praktor-smoke-app
SUP=praktor-smoke-supervisor
NET=praktor-smoke-hassio
HOST=local-praktor
CFG_VOL=praktor-smoke-config
DATA_VOL=praktor-smoke-data
IMG=praktor-smoke-app:ci
VERSION=${GATEWAY_IMAGE##*:}
TOKEN=smoke-supervisor-token

mkdir -p "$LOG_DIR"
: >"$LOG_DIR/known-bugs.txt"
: >"$LOG_DIR/results.txt"
START=$(date +%s)

log() { printf '[%4ss] %s\n' "$(($(date +%s) - START))" "$*"; }
pass() { log "PASS  $*"; echo "PASS  $*" >>"$LOG_DIR/results.txt"; }
fail() {
	log "FAIL  $*"
	echo "FAIL  $*" >>"$LOG_DIR/results.txt"
	exit 1
}
known_bug() {
	log "KNOWN BUG  $*"
	echo "$*" >>"$LOG_DIR/known-bugs.txt"
	if [[ -n ${SMOKE_STRICT:-} ]]; then exit 1; fi
}

case $(docker version -f '{{.Server.Arch}}') in
amd64) arch=amd64 ;;
arm64) arch=aarch64 ;;
*) fail "unsupported daemon arch" ;;
esac
# The digest-pinned base image, as CI builds it.
BUILD_FROM=$(sed -n "s/^ *BASE_IMAGE_${arch^^}: *\"\(.*\)\"/\1/p" "$REPO/praktor/build.yaml")
[[ $BUILD_FROM == *@sha256:* ]] || fail "no digest-pinned BASE_IMAGE_${arch^^} in build.yaml"

purge() {
	{
		docker rm -f $APP $SUP
		docker ps -aq --filter 'label=praktor.managed=true' | xargs -r docker rm -f
		docker volume rm $CFG_VOL $DATA_VOL
		docker network rm $NET
	} >/dev/null 2>&1 || true
}
cleanup() {
	local rc=$?
	set +e
	log "cleanup (exit $rc)"
	docker logs $APP >"$LOG_DIR/app.log" 2>&1
	docker logs $SUP >"$LOG_DIR/supervisor.log" 2>&1
	docker ps -a >"$LOG_DIR/docker-ps.txt" 2>&1
	purge
	log "logs in $LOG_DIR"
	exit "$rc"
}

if [[ -z ${SMOKE_ALLOW_SHARED_DOCKER:-} ]] && docker ps -a --format '{{.Names}}' | grep -qx praktor; then
	echo "A container named 'praktor' exists: this looks like a live deployment. Use tests/local-dind.sh." >&2
	exit 2
fi
trap cleanup EXIT
purge

docker image inspect "$GATEWAY_IMAGE" >/dev/null 2>&1 || fail "gateway image $GATEWAY_IMAGE not found"

# The App image as the HA builder builds it, plus our gateway image and
# agent sources. Known bugs in praktor/ are worked around in a copy (CTX), so
# the rest still gets tested; each workaround is a no-op once fixed.
CTX=$REPO/praktor
patch_ctx() {
	if [[ $CTX == "$REPO/praktor" ]]; then
		CTX=$(mktemp -d)
		cp -R "$REPO/praktor/." "$CTX"
	fi
}
build_app() {
	docker build -t $IMG \
		--build-arg BUILD_FROM="$BUILD_FROM" \
		--build-arg PRAKTOR_VERSION="$VERSION" \
		--build-arg PRAKTOR_GATEWAY_REF="$GATEWAY_IMAGE" \
		--build-arg PRAKTOR_SRC_URL="$PRAKTOR_SRC_URL" \
		--build-arg PRAKTOR_SRC_SHA256="$SRC_SHA256" \
		"$CTX" >"$LOG_DIR/app-build.log" 2>&1
}
log "building the App image ($arch, gateway $GATEWAY_IMAGE)"
build_app || fail "App image build failed: $(tail -5 "$LOG_DIR/app-build.log")"
pass "App image builds with BUILD_FROM/PRAKTOR_GATEWAY_REF/PRAKTOR_SRC_URL and a verified source checksum"
docker run --rm --entrypoint sh $IMG -c 'test -x /usr/bin/praktor && test -f /opt/praktor-agent/Dockerfile.agent && test -d /opt/praktor-agent/agent-runner && docker --version' >/dev/null ||
	fail "App image is missing the gateway, the agent sources or docker-cli"
pass "App image has the gateway, the agent sources and docker-cli"

# The agent image is normally built on the device at first start (minutes);
# a stand-in tag lets run.sh take its "already built" path.
docker image inspect "praktor-agent:$VERSION" >/dev/null 2>&1 || {
	docker pull -q busybox:latest >/dev/null
	docker tag busybox:latest "praktor-agent:$VERSION"
}

docker network create $NET >/dev/null
OPTS_DIR=$(mktemp -d)
chmod 755 "$OPTS_DIR"
# start_app OPTIONS_JSON: (re)start the fake Supervisor and the App.
start_app() {
	printf '%s' "$1" >"$OPTS_DIR/options.json"
	chmod 644 "$OPTS_DIR/options.json"
	docker rm -f $APP $SUP >/dev/null 2>&1 || true
	docker create --name $SUP --network $NET --network-alias supervisor python:3.13-alpine \
		python3 /fake_supervisor.py /options.json $TOKEN >/dev/null
	docker cp "$REPO/tests/fake_supervisor.py" $SUP:/fake_supervisor.py >/dev/null
	docker cp "$OPTS_DIR/options.json" $SUP:/options.json >/dev/null
	docker start $SUP >/dev/null
	# Wait until the fake Supervisor answers, or the App races it at startup.
	local i
	for i in $(seq 50); do
		docker exec $SUP python3 -c 'import socket; socket.create_connection(("127.0.0.1", 80), 1)' 2>/dev/null && break
		((i == 50)) && fail "fake Supervisor did not start"
		sleep 0.2
	done
	docker run -d --name $APP --hostname $HOST --network $NET \
		-p "127.0.0.1:${PORT}:8080" \
		-e SUPERVISOR_TOKEN=$TOKEN \
		-v /var/run/docker.sock:/run/docker.sock \
		-v $CFG_VOL:/config -v $DATA_VOL:/data \
		$IMG >/dev/null
}
app_logs() { docker logs $APP 2>&1; }
wait_log() { # PATTERN TIMEOUT
	local deadline=$(($(date +%s) + $2))
	until app_logs | grep -q "$1"; do
		if ! [[ $(docker inspect -f '{{.State.Running}}' $APP 2>/dev/null) == true ]]; then return 1; fi
		(($(date +%s) > deadline)) && return 1
		sleep 1
	done
}

VALID='{"telegram_token":"123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","allowed_telegram_users":[111111],"web_password":"smoke-pass","vault_passphrase":"smoke-vault","timezone":"Europe/Athens"}' # gitleaks:allow (fake test token)

log "starting the App with valid options"
start_app "$VALID"
wait_log 'Starting Praktor' 60 || fail "the App did not start: $(app_logs | tail -5)"
pass "run.sh starts the gateway"
app_logs | grep -q "First start: creating /config/praktor.yaml" || fail "no first-start message"
app_logs | grep -q "Home Assistant integration URL: http://$HOST:8080" || fail "no integration URL with the App hostname"
pass "run.sh logs the first start and the integration URL"
wait_log 'web server listening' 60 || fail "gateway did not start: $(app_logs | tail -5)"
pass "gateway web server listening"
wait_log 'attached gateway to agent network' 60 || fail "gateway did not attach itself to praktor-net: $(app_logs | tail -5)"
aliases=$(docker inspect $APP -f '{{json (index .NetworkSettings.Networks "praktor-net").Aliases}}')
[[ $aliases == *"$HOST"* ]] || fail "App on praktor-net without alias $HOST: $aliases"
pass "gateway joined praktor-net as $HOST"
grep -q "GET /addons/self/options/config" <(docker logs $SUP 2>&1) || fail "the App never asked the Supervisor for its options"
pass "options read from the Supervisor API"

[[ $(curl -sS -o /dev/null -w '%{http_code}' "$API/api/status") == 401 ]] || fail "/api/status without auth is not 401"
[[ $(curl -sS -o /dev/null -w '%{http_code}' -u "x:smoke-pass" "$API/api/status") == 200 ]] || fail "/api/status with the web_password is not 200"
pass "web_password protects the API"
[[ $(curl -sS -o /dev/null -w '%{http_code}' -u "x:smoke-pass" -H 'Content-Type: application/json' \
	--data '{"message":"hi","agent":"nope"}' "$API/api/chat") == 404 ]] || fail "/api/chat unknown agent is not 404"
pass "/api/chat is served"

log "restart: an edited praktor.yaml is kept"
docker run --rm -v $CFG_VOL:/config alpine:3.23 sh -c 'echo "# edited by the user" >> /config/praktor.yaml'
docker restart -t 30 $APP >/dev/null
sleep 3
wait_log 'web server listening' 60 || true
docker run --rm -v $CFG_VOL:/config alpine:3.23 grep -q "edited by the user" /config/praktor.yaml || fail "praktor.yaml was overwritten on restart"
pass "praktor.yaml survives a restart"

log "a web_password with a double quote"
docker rm -f $APP >/dev/null
docker volume rm -f $CFG_VOL >/dev/null # first start again, so the default config is used
start_app "$(jq -c '.web_password = "pa\"ss"' <<<"$VALID")"
wait_log 'web server listening' 60 || fail "a password with a double quote stopped the gateway: $(app_logs | tail -5)"
[[ $(curl -sS -o /dev/null -w '%{http_code}' -u 'x:pa"ss' "$API/api/status") == 200 ]] || fail "the password with a double quote doesn't log in"
pass "a password with a double quote works"

log "the chat token grants /api/chat only"
docker rm -f $APP >/dev/null
CHAT_TOKEN=smoke-chat-token-0123456789abcdef0123456789
start_app "$(jq -c --arg t "$CHAT_TOKEN" '.chat_token = $t' <<<"$VALID")"
wait_log 'web server listening' 60 || fail "gateway did not start with a chat_token: $(app_logs | tail -5)"
[[ $(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $CHAT_TOKEN" "$API/api/status") == 401 ]] || fail "the chat token opened /api/status"
[[ $(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $CHAT_TOKEN" -H 'Content-Type: application/json' \
	--data '{"message":"hi","agent":"deepseek"}' "$API/api/chat") == 403 ]] || fail "the chat token reached deepseek (chat_agents is [claude])"
pass "the chat token is limited to /api/chat and chat_agents"
docker rm -f $APP >/dev/null
start_app "$(jq -c '.chat_token = "short"' <<<"$VALID")"
sleep 5
app_logs | grep -q "must be at least 32 characters" || fail "a short chat_token was accepted"
pass "a short chat_token is refused"

if app_logs | grep -Eq 'panic:|http: panic serving'; then fail "gateway panicked"; fi
pass "no panics"
log "done in $(($(date +%s) - START))s; known bugs: $(wc -l <"$LOG_DIR/known-bugs.txt")"
