# Changelog

## 0.9.12-ha.1

First release, based on Praktor v0.9.12 plus changes proposed upstream:

- **Agent network:** the gateway joins the agent network itself when it isn't started by Docker Compose. This is needed to run as a Home Assistant App.
- **Chat API:** `POST /api/chat`, with a chat-only token for the Home Assistant integration.

Agents and defaults:

- Default agents: `deepseek` (Telegram default) and `claude` (`@claude`, and the only agent reachable from Home Assistant).
- Refuses to start without at least one allowed Telegram user. A chat token must be at least 32 characters.
- Mission Control's port is closed by default.
- No Home Assistant device control by agents in this version (see Documentation).

Security:

- Base images, the gateway and the agent base are pinned by digest.
- The gateway's cosign signature is verified before building.
- The agent sources and Claude Code are checksum-verified.
- GitHub Actions are pinned to commit SHAs.
