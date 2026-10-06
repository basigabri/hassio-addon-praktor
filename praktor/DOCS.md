# Praktor

[Praktor](https://github.com/basigabri/praktor) is a personal multi-agent AI assistant. Each agent is Claude Code running in its own Docker container, with its own files, memory, model and secrets. You talk to the agents from Telegram and, with the [Praktor integration](https://github.com/basigabri/hacs-praktor), from Home Assistant Assist.

| Agent | Model | Used for |
|---|---|---|
| `deepseek` | DeepSeek (`deepseek-chat`) | Telegram messages by default. **Never** used for Home Assistant (see Privacy) |
| `claude` | Claude Sonnet 5 (your Claude subscription) | Telegram messages starting with `@claude`, and Home Assistant Assist |

## Read this first: what this App can do to your system

This App runs in your home, next to everything Home Assistant controls, so understand its access before installing:

- **It needs Protection mode off.** Praktor starts a Docker container for each agent, so it needs the Docker API. Docker access is effectively **root on the host**: a compromised App could read every Home Assistant integration's credentials and backups, and reach your whole network. Only install it if you accept that. Keep the allow list tight and the passwords strong.
- **Agents can be steered by what they read.** Agents browse the web and read files. Text on a web page can try to instruct them ("prompt injection"). That is why this version gives agents **no control over Home Assistant devices** (see "Device control" below).
- **Your messages go to the model providers.** Telegram messages go to DeepSeek (servers in China) or Anthropic. Assist requests go to Anthropic only. See Privacy.

## Before you install

- **Hardware:** about 60 MB of memory while idle, plus about 0.8 GB for each running agent. Agents stop after 10 idle minutes. A Raspberry Pi 5 with 8 GB is comfortable; use SSD/NVMe storage.
- **Accounts and keys:**
  - a Telegram bot token from [@BotFather](https://t.me/BotFather);
  - your Telegram user ID (send any message to [@userinfobot](https://t.me/userinfobot));
  - a [DeepSeek API key](https://platform.deepseek.com);
  - a Claude Code token (`claude setup-token` on any computer).
- **Installation type:** Home Assistant OS, or Supervised. Supervised is deprecated by Home Assistant (support ended with 2025.12); plan a move to Home Assistant OS.

## Installation

1. Settings → Apps → App store → ⋮ → **Repositories** → add `https://github.com/basigabri/hassio-addon-praktor`.
2. Install **Praktor**. Leave **Auto update off**: update by hand after reading the changelog (see "Updates").
3. On the **Info** tab, turn **Protection mode off** (see above for what that means).
4. Fill in the **Configuration** tab (see Options) and start the App.
5. The first start builds the agent image on this device, which takes a few minutes. It is built locally because it contains Claude Code, which can't be redistributed. Every input to that build is pinned and checksummed. Wait for `telegram bot started` on the **Log** tab.
6. Open Mission Control. Its port is closed by default: on the **Network** tab, set port `8080` while you set things up, then clear it again. Open `http://<home-assistant-ip>:8080` and log in with your web password. Under **Secrets**, add:
   - `deepseek-key`: your DeepSeek API key, assigned to agent `deepseek`;
   - `claude-oauth`: your Claude Code token, assigned to agent `claude`.
7. Send your bot a message on Telegram. `@claude …` goes to Claude.

**Only one Praktor can use a Telegram bot token at a time.** Stop any other copy (for example one on your computer) that uses the same token.

## Options

| Option | Required | Description |
|---|---|---|
| `telegram_token` | yes | Bot token from @BotFather. |
| `allowed_telegram_users` | yes | Telegram user IDs allowed to use the bot. The App refuses to start with an empty list: an empty list lets anyone who finds the bot run your agents. The first ID also receives scheduled task results. |
| `web_password` | yes | Admin password for Mission Control and the API. Use a long random value (e.g. `openssl rand -hex 24`). |
| `chat_token` | for the integration | Token for the Home Assistant integration, at least 32 characters (`openssl rand -hex 32`). It can **only** send chat messages to the agents in `web.chat_agents` (default: `claude`). It can't open Mission Control, read secrets or change settings, so the integration never holds your admin password. |
| `vault_passphrase` | yes | Encrypts the secrets vault. Use a long random value and **don't change it later**: secrets stored with the old passphrase can't be decrypted. |
| `timezone` | no | For example `Europe/Athens`. Used for scheduled tasks. Default `UTC`. |

## Configuration file

On first start the App creates `praktor.yaml` in its config folder (`/addon_configs/<id>_praktor/`). Edit it to add agents or change models. Changes apply without a restart.
- Secrets are **not** in this file: the App passes them to Praktor directly.
- `${...}` values are filled in from the options above.
- See Praktor's [example config](https://github.com/basigabri/praktor/blob/main/config/praktor.example.yaml) for all settings.

## Talking to Praktor from Home Assistant

1. Set `chat_token` in the options and restart the App.
2. Install the [Praktor integration](https://github.com/basigabri/hacs-praktor) through HACS. Use:
   - the URL the App prints in its log (`Home Assistant integration URL: http://<hostname>:8080`), which stays inside this machine and needs no published port;
   - the chat token.
3. Choose **Praktor** as the conversation agent in Settings → Voice assistants. Turn on **Prefer handling commands locally** there too, so device commands are handled by Home Assistant itself and only questions go to Praktor.

Assist messages go to the `claude` agent only. Agents keep one conversation each, so Assist and Telegram share the `claude` agent's context. If you don't want that, add a separate agent (e.g. `home`) in `praktor.yaml` and list only it in `web.chat_agents`.

## Device control (not enabled in this version)

This version deliberately gives agents **no access to your Home Assistant devices**:
- A Home Assistant long-lived token always carries its user's full rights. Even a non-admin user can control every entity through the REST API.
- An agent that reads untrusted text could be tricked into using it to unlock a door, disarm the alarm or turn off cameras.

Device control is planned through a proxy that only allows specific, exposed tools, for the `claude` agent only, with your confirmation for anything security-related. Until then:
- **Don't give agents a Home Assistant token.**
- **Never expose** locks, alarm panels, garage/gate covers, cameras, people/device trackers, presence sensors, sirens or shut-off valves to Assist. Exposed entities' states are sent to the model provider.
- For dangerous actions, expose a **script** that asks for confirmation on your phone (an actionable notification) instead of the device itself.

## Privacy

- **DeepSeek** (servers in China) gets your Telegram messages to the `deepseek` agent and their content. It never gets Home Assistant requests or data. Don't send it anything about your household you wouldn't publish.
- **Anthropic** gets Telegram messages to `claude`, Assist requests, and the states of entities you expose to Assist.
- **Hygiene:** use `/reset` in Telegram to clear an agent's conversation, and delete old memories in Mission Control.

## Updates

- **Turn auto-update off** for this App.
- **Every App image** is built by GitHub Actions from pinned inputs and signed with [cosign](https://docs.sigstore.dev/). You can check an image before updating:
  ```sh
  cosign verify ghcr.io/basigabri/aarch64-addon-praktor:<version> \
    --certificate-identity-regexp '^https://github\.com/basigabri/hassio-addon-praktor/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```
- **The Praktor gateway** inside the App is pinned by digest, and its signature is verified before every App build.

## Networking

- **Agent network:** agents run on a Docker network called `praktor-net`. On start the App joins that network itself so agents can reach it. That's an internal Docker network: your Home Assistant network settings are not changed.
- **Port 8080:** closed by default. If you open it for Mission Control, keep it on your LAN and **never forward it on your router**.

## Backups

- **Encrypt your Home Assistant backups and keep the key offline.**
- **Why:** this App's backup contains its options (the bot token, web password, chat token and vault passphrase) in plain text, next to the encrypted vault.
- **Not included:** agent workspaces (`praktor-wk-*`, `praktor-home-*` Docker volumes) aren't in Home Assistant backups.

## If something goes wrong (kill switch)

In this order:
1. **Stop the App:** Settings → Apps → Praktor → **Stop**. Its agent containers stop with it.
2. **Revoke and rotate:**
   - the Telegram bot token (@BotFather `/revoke`);
   - the DeepSeek key;
   - the Claude token (create a new one with `claude setup-token`, and revoke the old one in your account);
   - the web password and chat token;
   - in Home Assistant, delete the integration entry.
3. **Check for strangers:** check Mission Control → Tasks for scheduled tasks you didn't create.
4. **If you see unknown containers or changes to the host,** treat the machine as compromised:
   - rotate every Home Assistant integration credential and your Wi-Fi keys;
   - reinstall;
   - restore from a backup made before the incident.

## Support

Issues with the App: <https://github.com/basigabri/hassio-addon-praktor/issues>. Praktor itself: <https://github.com/basigabri/praktor>.
