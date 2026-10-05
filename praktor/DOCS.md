# Praktor

[Praktor](https://github.com/basigabri/praktor) is a personal multi-agent AI assistant. Each agent is Claude Code running in its own Docker container, with its own files, memory, model and secrets. You talk to the agents from Telegram and, with the [Praktor integration](https://github.com/basigabri/hacs-praktor), from Home Assistant Assist.

The App comes with two agents:

| Agent | Model | Used for |
|---|---|---|
| `deepseek` | DeepSeek (`deepseek-chat`) | every message by default |
| `claude` | Claude Sonnet 5 (your Claude subscription) | only messages starting with `@claude` |

## Before you install

- **Hardware:** Praktor needs about 60 MB of memory while idle and about 0.8 GB for each agent that is running. Agents stop after 10 idle minutes. A Raspberry Pi 5 with 8 GB is comfortable. Fast storage (SSD/NVMe) is strongly recommended.
- **Accounts:** a Telegram bot token from [@BotFather](https://t.me/BotFather), your Telegram user ID (send any message to [@userinfobot](https://t.me/userinfobot)), a [DeepSeek API key](https://platform.deepseek.com) and, for the `claude` agent, a Claude Code token (`claude setup-token` on any computer).

## Installation

1. Settings → Apps → App store → ⋮ → **Repositories** → add `https://github.com/basigabri/hassio-addon-praktor`.
2. Install **Praktor**.
3. On the **Info** tab, turn **Protection mode off**. Why: Praktor starts a separate Docker container for each agent, so it needs the Docker API, which Home Assistant only grants to Apps without protection mode. This gives the App control over the Docker containers on this machine. Keep the Telegram allow list (below) tight and the web password strong.
4. Fill in the **Configuration** tab (see Options) and start the App.
5. The first start builds the agent image on this device, which takes a few minutes. It is built locally because it contains Claude Code, which can't be redistributed. Watch the **Log** tab until `telegram bot started` appears.
6. Open Mission Control at `http://<home-assistant-ip>:8080`, log in with your web password, and add these under **Secrets**:
   - `deepseek-key`: your DeepSeek API key, assigned to agent `deepseek`
   - `claude-oauth`: your Claude Code token, assigned to agent `claude`
7. Send your bot a message on Telegram. `@claude …` goes to Claude.

**Only one Praktor can use a Telegram bot token at a time.** Stop any other copy (for example one on your computer) that uses the same token.

## Options

| Option | Required | Description |
|---|---|---|
| `telegram_token` | yes | Bot token from @BotFather. |
| `allowed_telegram_users` | yes | Telegram user IDs allowed to use the bot. The App refuses to start with an empty list, because an empty list lets anyone who finds the bot run your agents. The first ID also receives scheduled task results. |
| `web_password` | yes | Password for Mission Control and the API, including the chat API the integration uses. |
| `vault_passphrase` | yes | Encrypts the secrets vault (AES-256-GCM). Use a long random value and **don't change it later**: secrets stored with the old passphrase can't be decrypted. |
| `timezone` | no | For example `Europe/Athens`. Used for scheduled tasks. Default `UTC`. |

## Configuration file

On first start the App creates `praktor.yaml` in its config folder (`/addon_configs/<id>_praktor/`, reachable with the Samba or SSH App). Edit it to add agents, change models or tools. Changes apply without a restart. `${...}` values are filled in from the options above. See Praktor's [example config](https://github.com/basigabri/praktor/blob/main/config/praktor.example.yaml) for all settings.

## Talking to Praktor from Home Assistant

Install the [Praktor integration](https://github.com/basigabri/hacs-praktor) through HACS. When setting it up, use the URL the App prints in its log (`Home Assistant integration URL: http://<hostname>:8080`) and your web password. That traffic stays inside this machine. Then choose **Praktor** as the conversation agent in Settings → Voice assistants. Turn on **Prefer handling commands locally** there too, so simple device commands are handled by Home Assistant instantly and only other questions go to Praktor.

## Letting agents control Home Assistant

Agents can control the devices you expose to them through Home Assistant's built-in **Model Context Protocol Server** integration:

1. Settings → Devices & services → Add integration → **Model Context Protocol Server**.
2. Settings → Voice assistants → **Expose**: expose only what agents may control (for example lights). Don't expose locks or alarms unless you mean to.
3. Your profile → Security → create a **long-lived access token**. In Mission Control add a secret `ha-auth` whose value is `Bearer <your token>` (the word `Bearer`, a space, then the token), and assign it to agent `deepseek`.
4. In `praktor.yaml`, set `nix_enabled: true` on the `deepseek` agent. Then in Mission Control → Agents → deepseek → Extensions, add an MCP server:
   - type `http`, URL `http://<home-assistant-ip>:8123/api/mcp`
   - header `Authorization` with value `secret:ha-auth`. Praktor replaces a header value that starts with `secret:` with the secret, so the token never appears in the config.

Now "turn on the living room lights" on Telegram works. The agent only sees the exposed entities.

## Networking

Agents run on a Docker network called `praktor-net`. On start the App joins that network itself, so agents can reach it. This only joins an internal Docker network; your Home Assistant network settings are not changed. Port 8080 is published on your local network for Mission Control. Don't forward it on your router.

## Data and backups

The database (conversations, scheduled tasks, encrypted secrets) is in the App's data folder and is included in Home Assistant backups. Agent workspaces are Docker volumes named `praktor-wk-*` and `praktor-home-*`, which Home Assistant backups don't include. Use `praktor backup` from Praktor's CLI if you need them.

## Support

Issues with the App: <https://github.com/basigabri/hassio-addon-praktor/issues>. Praktor itself: <https://github.com/basigabri/praktor>.
