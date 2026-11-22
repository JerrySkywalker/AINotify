# Roadmap

## v0.1 prototype

| Checkpoint | Time budget | Outputs |
| --- | ---: | --- |
| Environment and contract | 45 min | Two booted AVDs and a shared event contract |
| Relay | 1 h 45 min | SQLite, writer/reader authentication, durable events, deduplication and cursor reads |
| Collector | 2 h 30 min | Codex and Claude Code Stop hooks, offline spool, Windows and Linux CLI |
| Windows desktop | 1 h 45 min | Tray, settings, test send and hook controls |
| Android | 1 h 45 min | Local foreground receiver, notifications, inbox and full reply |
| Wear OS | 1 h 15 min | Preview, notifications and paired/direct relay modes |
| Local integration CI | 1 h 15 min | Offline fixture tests, two AVDs, reports and screenshots |
| Fixes and documentation | 1 h | Repeatable results and quick start |

The local suite uses synthetic UTF-8 Stop payloads. It treats direct and paired Wear OS delivery as distinct test modes. A passing direct mode provides no evidence for pairing. Product-specific live Hook and real-device checks have their own evidence.

## After v0.1

- Add a push provider and verify screen-off reception, reconnect and background behavior on target phones.
- Add cursor-based foreground refresh and review retention, credential rotation and backups on a deployed relay.
- Verify paired phone-to-watch delivery on the intended devices and evaluate standalone background push.
- Add Cursor and other adapters against real versioned Hook captures. Add a separate event for finished background jobs.
- Package steady-state installers, launch-on-login and revocation.
