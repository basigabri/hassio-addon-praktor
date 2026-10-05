# Changelog

## 0.9.12-ha.1

- First release, based on Praktor v0.9.12 plus two changes proposed upstream:
  - the gateway joins the agent network itself when it isn't started by Docker Compose, which is needed to run as a Home Assistant App;
  - `POST /api/chat`, used by the Home Assistant integration.
- Default agents: `deepseek` (default) and `claude` (`@claude` only).
- Refuses to start without at least one allowed Telegram user.
