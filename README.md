# Praktor for Home Assistant

A Home Assistant App repository with [Praktor](https://github.com/basigabri/praktor), a personal multi-agent AI assistant. Each agent is Claude Code running in its own Docker container, reachable from Telegram and from Home Assistant Assist (with the [Praktor integration](https://github.com/basigabri/hacs-praktor)).

## Install

Settings → Apps → App store → ⋮ → **Repositories** → add:

```
https://github.com/basigabri/hassio-addon-praktor
```

Then install **Praktor** and follow its Documentation tab.

## Why a fork of Praktor

The App uses [basigabri/praktor](https://github.com/basigabri/praktor), upstream Praktor plus two changes needed for Home Assistant. Both are proposed upstream:

- **The gateway joins the agent network itself.** Agents reach the gateway over a Docker network that Docker Compose sets up. A Home Assistant App isn't started by Compose, so without this change the agents couldn't connect.
- **`POST /api/chat`** with a chat-only token. Lets the Home Assistant integration send a message to an agent and get the reply, without holding the admin password.

Once upstream has both, the App will switch to upstream images.

## Security

- **Pinned inputs:**
  - App images are built by GitHub Actions from pinned inputs: base images and the Praktor gateway by digest, agent sources and Claude Code by SHA-256, actions by commit SHA.
  - The gateway's cosign signature is verified before every build.
  - App images are signed with cosign.
- **Docker access:** the App needs Protection mode off (Docker access). Read the Documentation tab before installing.
- **Device control:** agents get no control over Home Assistant devices in this version.

## Images

- App images: `ghcr.io/basigabri/{aarch64,amd64}-addon-praktor`, built by GitHub Actions on pushes to `main`.
- The agent image is **never published**: it contains Claude Code, which can't be redistributed, so the App builds it on your device at first start.
