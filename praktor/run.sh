#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -eo pipefail

readonly config_file="/config/praktor.yaml"
readonly agent_src="/opt/praktor-agent"

# --- Options -> environment (read by Praktor and expanded in praktor.yaml) ---
for opt in telegram_token web_password vault_passphrase; do
    if ! bashio::config.has_value "${opt}"; then
        bashio::exit.nok "Option '${opt}' is required. Set it on the Configuration tab."
    fi
done
mapfile -t allowed < <(bashio::config 'allowed_telegram_users')
if [[ ${#allowed[@]} -eq 0 || -z "${allowed[0]}" ]]; then
    # An empty allow list lets anyone who finds the bot run your agents.
    bashio::exit.nok "Option 'allowed_telegram_users' needs at least one Telegram user ID."
fi

PRAKTOR_TELEGRAM_TOKEN="$(bashio::config 'telegram_token')"
PRAKTOR_WEB_PASSWORD="$(bashio::config 'web_password')"
PRAKTOR_VAULT_PASSPHRASE="$(bashio::config 'vault_passphrase')"
PRAKTOR_ALLOW_FROM="$(IFS=,; echo "${allowed[*]}")"
PRAKTOR_MAIN_CHAT_ID="${allowed[0]}"
TZ="$(bashio::config 'timezone')"
export PRAKTOR_TELEGRAM_TOKEN PRAKTOR_WEB_PASSWORD PRAKTOR_VAULT_PASSPHRASE \
    PRAKTOR_ALLOW_FROM PRAKTOR_MAIN_CHAT_ID TZ
export PRAKTOR_CONFIG="${config_file}"
export DOCKER_HOST="unix:///run/docker.sock"

# --- Docker access ---
if ! docker version >/dev/null 2>&1; then
    bashio::exit.nok "No access to Docker. Turn off 'Protection mode' on the Info tab, then restart."
fi

# --- Config ---
if ! bashio::fs.file_exists "${config_file}"; then
    bashio::log.info "First start: creating ${config_file} (agents deepseek + claude)."
    cp /opt/praktor/praktor.default.yaml "${config_file}"
fi

# --- Agent image (built locally; tagged per release so updates rebuild it) ---
if ! docker image inspect "praktor-agent:${PRAKTOR_VERSION}" >/dev/null 2>&1; then
    bashio::log.info "Building the agent image praktor-agent:${PRAKTOR_VERSION}. The first time takes a few minutes."
    docker build -f "${agent_src}/Dockerfile.agent" \
        -t "praktor-agent:${PRAKTOR_VERSION}" -t praktor-agent:latest "${agent_src}"
    bashio::log.info "Agent image built."
else
    docker tag "praktor-agent:${PRAKTOR_VERSION}" praktor-agent:latest
fi

bashio::log.info "Home Assistant integration URL: http://$(hostname):8080"
bashio::log.info "Starting Praktor ${PRAKTOR_VERSION}"
# Praktor keeps its database under ./data, so run from / to use /data,
# the App's persistent storage.
cd /
exec /usr/bin/praktor gateway
