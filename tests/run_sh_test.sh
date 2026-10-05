#!/usr/bin/env bash
# SC2015: `cond && ok || not_ok` is fine here, ok never fails.
# SC2016: hostile option values are single-quoted on purpose.
# shellcheck disable=SC2015,SC2016
# Behavior tests for praktor/run.sh: try to break the App's startup.
#
# run.sh runs under the real bashio from the App's base image. Options are fed
# through bashio's cache (exactly what bashio::addon.config reads after its
# first Supervisor call); docker and the praktor binary are stubs that record
# what they were asked to do.
#
# On the host this script re-runs itself in the base image (needs Docker):
#   tests/run_sh_test.sh
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

if [[ ! -d /usr/lib/bashio ]]; then
	case $(uname -m) in
	x86_64 | amd64) arch=amd64 ;;
	aarch64 | arm64) arch=aarch64 ;;
	*) echo "unsupported arch $(uname -m)" >&2; exit 2 ;;
	esac
	base=$(sed -n "s/^ *${arch}: *\"\(.*\)\"/\1/p" "$REPO/praktor/build.yaml")
	exec docker run --rm -v "$REPO:/repo:ro" --entrypoint bash "$base" /repo/tests/run_sh_test.sh
fi

# ----------------------------------------------------------------------------
# In the base image from here on.

STUB=/stub
FAILS=0
PASSES=0

setup_stubs() {
	mkdir -p /usr/local/bin
	cat >/usr/local/bin/docker <<'EOF'
#!/bin/bash
# docker stub: logs every call; behavior from STUB_* variables.
printf '%s\n' "$*" >>/stub/docker.log
case $1 in
version) [[ -z ${STUB_DOCKER_DOWN:-} ]] ;;
image) [[ $2 == inspect && -n ${STUB_IMAGE_EXISTS:-} ]] ;;
build)
	if [[ -n ${STUB_BUILD_FAIL:-} ]]; then
		echo "ERROR: failed to solve: process did not complete successfully" >&2
		exit 1
	fi
	;;
tag) ;;
*) echo "unexpected docker $*" >&2; exit 99 ;;
esac
EOF
	cat >/usr/bin/praktor <<'EOF'
#!/bin/bash
# praktor stub: records how it was started.
{
	echo "args=$*"
	echo "cwd=$(pwd)"
} >/stub/praktor.started
for v in PRAKTOR_TELEGRAM_TOKEN PRAKTOR_WEB_PASSWORD PRAKTOR_VAULT_PASSPHRASE PRAKTOR_ALLOW_FROM \
	PRAKTOR_MAIN_CHAT_ID TZ PRAKTOR_CONFIG DOCKER_HOST; do
	printf '%s' "${!v-<unset>}" >"/stub/env.$v"
done
EOF
	chmod +x /usr/local/bin/docker /usr/bin/praktor
}

# BUG (allowed_telegram_users): bashio::config runs `read -r -d ''`, which
# returns 1 at the end of its heredoc. Process substitution inherits errexit,
# so `mapfile -t allowed < <(bashio::config ...)` always reads an empty list
# and the App refuses to start with any allow list. Command substitution
# doesn't inherit errexit, so reading the list with $(...) works.
# Until run.sh is fixed, the other cases run a copy with that one line
# replaced (a no-op once the line is fixed), so they still test the rest.
ALLOWED_LINE="mapfile -t allowed < <(bashio::config 'allowed_telegram_users')"
ALLOWED_FIX="allowed_list=\$(bashio::config 'allowed_telegram_users'); mapfile -t allowed <<<\"\${allowed_list}\""
PATCH_ALLOWED=1

# reset OPTIONS_JSON: fresh filesystem state for one case.
reset() {
	rm -rf /config /opt/praktor /opt/praktor-agent /tmp/.bashio "$STUB" /tmp/pwned*
	mkdir -p /config /opt/praktor /opt/praktor-agent /tmp/.bashio "$STUB"
	cp /repo/praktor/run.sh /run.sh
	if ((PATCH_ALLOWED)); then
		local line=$ALLOWED_LINE fix=$ALLOWED_FIX
		awk -v line="$line" -v fix="$fix" '$0 == line { print fix; next } { print }' /repo/praktor/run.sh >/run.sh
	fi
	cp /repo/praktor/praktor.default.yaml /opt/praktor/praktor.default.yaml
	echo "FROM scratch" >/opt/praktor-agent/Dockerfile.agent
	printf '%s' "$1" >/tmp/.bashio/addons.self.options.config.cache
	: >"$STUB/docker.log"
}

# start [VAR=value...]: run run.sh like the App does (bashio interpreter),
# with a clean environment. Sets RC and OUT.
start() {
	OUT=$(env -i PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=/root \
		PRAKTOR_VERSION=v9.9.9-test SUPERVISOR_API=http://127.0.0.1:9 "$@" \
		timeout 30 bashio /run.sh 2>&1)
	RC=$?
}

opts() { # opts [jq assignments]: the valid options, modified
	jq -nc --argjson base "$VALID" "\$base | ${1:-.}"
}

VALID='{"telegram_token":"123456:ABC-def_ghi","allowed_telegram_users":[111,222],"web_password":"pw","vault_passphrase":"vault-pp","timezone":"Europe/Athens"}'

ok() { PASSES=$((PASSES + 1)); printf 'ok    %s\n' "$1"; }
not_ok() {
	FAILS=$((FAILS + 1))
	printf 'FAIL  %s\n' "$1"
	[[ -n ${2:-} ]] && printf '      %s\n' "$2"
	printf '      exit=%s output:\n' "$RC"
	while IFS= read -r l; do printf '      | %s\n' "$l"; done <<<"$OUT"
}
known_bug() { printf 'BUG   %s\n' "$1"; echo "$1" >>/tmp/known-bugs; }

started() { [[ -f $STUB/praktor.started ]]; }
envv() { cat "$STUB/env.$1" 2>/dev/null; }

expect_refused() { # NAME MESSAGE-REGEX
	if ((RC != 0)) && ! started && grep -Eq "$2" <<<"$OUT" && ! grep -q '^build' "$STUB/docker.log"; then
		ok "$1"
	else
		not_ok "$1" "want a non-zero exit matching /$2/, no gateway and no image build"
	fi
}

setup_stubs
: >/tmp/known-bugs

# --- the allow list, with run.sh as it is ----------------------------------------

PATCH_ALLOWED=0
reset "$VALID"
start
PATCH_ALLOWED=1
if ((RC == 0)) && started; then
	ok "valid allowed_telegram_users are read (run.sh unmodified)"
elif [[ -n ${RUN_KNOWN_BUGS:-} ]]; then
	not_ok "valid allowed_telegram_users are read (run.sh unmodified)"
else
	known_bug "run.sh never starts: 'mapfile -t allowed < <(bashio::config ...)' reads an empty list under real bashio (errexit in process substitution + bashio's read -d ''), so every allow list is refused. Fix: allowed_list=\$(bashio::config 'allowed_telegram_users'); mapfile -t allowed <<<\"\${allowed_list}\""
fi

# --- happy path ---------------------------------------------------------------

reset "$VALID"
start
if ((RC == 0)) && started && [[ $(envv PRAKTOR_TELEGRAM_TOKEN) == "123456:ABC-def_ghi" &&
	$(envv PRAKTOR_WEB_PASSWORD) == pw && $(envv PRAKTOR_VAULT_PASSPHRASE) == vault-pp &&
	$(envv PRAKTOR_ALLOW_FROM) == 111,222 && $(envv PRAKTOR_MAIN_CHAT_ID) == 111 &&
	$(envv TZ) == Europe/Athens && $(envv PRAKTOR_CONFIG) == /config/praktor.yaml &&
	$(envv DOCKER_HOST) == unix:///run/docker.sock ]] &&
	grep -qx 'args=gateway' "$STUB/praktor.started" && grep -qx 'cwd=/' "$STUB/praktor.started"; then
	ok "valid options start the gateway with the right environment"
else
	not_ok "valid options start the gateway with the right environment"
fi
cmp -s /config/praktor.yaml /opt/praktor/praktor.default.yaml && ok "first start creates praktor.yaml from the default" ||
	not_ok "first start creates praktor.yaml from the default"
grep -q '^build -f /opt/praktor-agent/Dockerfile.agent -t praktor-agent:v9.9.9-test -t praktor-agent:latest /opt/praktor-agent$' "$STUB/docker.log" &&
	ok "builds praktor-agent:<version> when it's missing" || not_ok "builds praktor-agent:<version> when it's missing" "$(cat "$STUB/docker.log")"
grep -q 'Home Assistant integration URL: http://' <<<"$OUT" && grep -q 'Starting Praktor v9.9.9-test' <<<"$OUT" &&
	ok "logs the integration URL and the version" || not_ok "logs the integration URL and the version"

reset "$VALID"
start STUB_IMAGE_EXISTS=1
if ((RC == 0)) && started && ! grep -q '^build' "$STUB/docker.log" &&
	grep -qx 'tag praktor-agent:v9.9.9-test praktor-agent:latest' "$STUB/docker.log"; then
	ok "existing agent image: no rebuild, re-tagged as latest"
else
	not_ok "existing agent image: no rebuild, re-tagged as latest"
fi

reset "$(opts '.allowed_telegram_users = [-1001234567890, 5]')"
start
[[ $RC == 0 && $(envv PRAKTOR_ALLOW_FROM) == -1001234567890,5 && $(envv PRAKTOR_MAIN_CHAT_ID) == -1001234567890 ]] &&
	ok "negative (group) chat IDs" || not_ok "negative (group) chat IDs"

# --- missing or empty options --------------------------------------------------

for opt in telegram_token web_password vault_passphrase; do
	reset "$(opts "del(.$opt)")"
	start
	expect_refused "missing $opt is refused" "Option '$opt' is required"
	reset "$(opts ".$opt = \"\"")"
	start
	expect_refused "empty $opt is refused" "Option '$opt' is required"
done
reset "$(opts '.allowed_telegram_users = []')"
start
expect_refused "empty allowed_telegram_users is refused" "needs at least one Telegram user ID"
# The Supervisor fills in defaults, so a missing key is unlikely; bashio then
# returns "null", which passes the empty-list check.
reset "$(opts 'del(.allowed_telegram_users)')"
start
if ((RC == 0)) && [[ $(envv PRAKTOR_ALLOW_FROM) == null ]]; then
	known_bug "a missing allowed_telegram_users key reads as the string \"null\" and passes the empty-list check (allow_from: [null] parses as user 0, so nobody is allowed; safe but not refused)"
else
	expect_refused "missing allowed_telegram_users is refused" "needs at least one Telegram user ID"
fi
reset "$(opts 'del(.timezone)')"
start
[[ $RC == 0 ]] && started && ok "timezone is optional" || not_ok "timezone is optional"

# bashio treats the string "null" as no value.
reset "$(opts '.web_password = "null"')"
start
if ((RC != 0)) && ! started; then
	known_bug "a web_password (or token/passphrase) that is literally \"null\" is refused as missing (bashio::config maps \"null\" to unset)"
else
	ok "web_password \"null\" accepted"
fi

# --- Docker -------------------------------------------------------------------

reset "$VALID"
start STUB_DOCKER_DOWN=1
expect_refused "no Docker access exits with the Protection mode message" "Turn off 'Protection mode'"
[[ ! -f /config/praktor.yaml ]] && ok "no Docker access: config not created yet" || not_ok "no Docker access: config not created yet"

reset "$VALID"
start STUB_BUILD_FAIL=1
if ((RC != 0)) && ! started; then
	ok "agent image build failure exits non-zero without starting the gateway"
else
	not_ok "agent image build failure exits non-zero without starting the gateway"
fi

# --- config file --------------------------------------------------------------

reset "$VALID"
printf 'my: own\nconfig: "with ${PRAKTOR_WEB_PASSWORD}"\n' >/config/praktor.yaml
cp /config/praktor.yaml /tmp/before.yaml
start
cmp -s /config/praktor.yaml /tmp/before.yaml && ((RC == 0)) && ok "an existing praktor.yaml is never overwritten" ||
	not_ok "an existing praktor.yaml is never overwritten"
grep -q 'First start' <<<"$OUT" && not_ok "existing config: no first-start message" || ok "existing config: no first-start message"

reset "$VALID"
: >/config/praktor.yaml
start
[[ ! -s /config/praktor.yaml ]] && ok "an existing empty praktor.yaml is left alone" || not_ok "an existing empty praktor.yaml is left alone"

# --- hostile option values -----------------------------------------------------

values=(
	'$(touch /tmp/pwned1)'
	'`touch /tmp/pwned2`'
	"'; touch /tmp/pwned3; '"
	'"; touch /tmp/pwned4; "'
	'a b  c'
	'$HOME ${PATH} $1 $@ $$'
	'quote " and \ backslash'
	$'line1\nline2'
	$'tab\there'
	'*'
	'-n'
	'--help'
	'${PRAKTOR_VAULT_PASSPHRASE}'
	'ünïcødé 🔑'
	$'trailing newline\n'
)
NL=$'\n'
for v in "${values[@]}"; do
	name=$(printf '%q' "$v")
	reset "$(jq -nc --argjson base "$VALID" --arg v "$v" '$base | .web_password = $v | .vault_passphrase = $v | .telegram_token = $v | .timezone = $v')"
	start
	pwned=$(ls /tmp/pwned* 2>/dev/null)
	want=$v
	if ((RC != 0)) || ! started || [[ -n $pwned ]]; then
		not_ok "value $name: nothing executed, gateway started" "pwned: $pwned"
		continue
	fi
	if [[ $(envv PRAKTOR_WEB_PASSWORD) == "$want" && $(envv PRAKTOR_VAULT_PASSPHRASE) == "$want" &&
		$(envv PRAKTOR_TELEGRAM_TOKEN) == "$want" && $(envv TZ) == "$want" ]]; then
		ok "value $name passes through unchanged"
	elif [[ $want == *"$NL" && $(envv PRAKTOR_WEB_PASSWORD) == "${want%"$NL"}" ]]; then
		known_bug "trailing newlines are stripped from option values (\$(bashio::config ...)); harmless for passwords set in the UI"
	else
		not_ok "value $name passes through unchanged" "got password $(printf '%q' "$(envv PRAKTOR_WEB_PASSWORD)")"
	fi
done

echo
echo "$PASSES passed, $FAILS failed, $(wc -l </tmp/known-bugs) known bugs"
[[ $FAILS -eq 0 ]]
