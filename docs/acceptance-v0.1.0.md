# v0.1.0 local acceptance

The release packages artifacts built and tested locally on 2026-11-22. GitHub Actions is disabled across the project family. The [release](https://github.com/JerrySkywalker/AINotify/releases/tag/v0.1.0) includes the machine-readable receipt, Linux smoke result and emulator screenshots.

| Check | Result |
| --- | --- |
| Collector and relay on Windows | Rust build, Clippy, and tests passed. Installed Hook commands consumed synthetic Codex and Claude Code Stop events with UTF-8 reply text. |
| Windows desktop | The native tray opened the settings window. Settings persisted, closing returned to the tray, and a test message sent while the window was hidden. |
| Reliability and access | Writer/reader roles, offline retry, restart recovery, event deduplication and cursor-based reads passed. |
| Linux | Local Linux container built both Rust release binaries. An installed shell Hook preserved the reply across an offline send and later delivered it. |
| Android | Local tests, Lint and APK build passed. On the API 35 phone AVD, tapping a system notification opened the complete Chinese reply. |
| Wear OS | Lint and APK build passed. The API 35 watch AVD connected directly to the relay, posted a notification and displayed its preview. |

## Coverage still pending

- Live Codex and Claude Code sessions. The integration uses sample payloads and the installed Hook commands.
- Phone-to-watch system pairing and Data Layer delivery. The recorded run used direct watch delivery.
- True push and background delivery on physical devices. The local prototype uses a foreground receiver.

## Source revisions

| Repository | Tested commit |
| --- | --- |
| AINotify | [a3d4bac](https://github.com/JerrySkywalker/AINotify/commit/a3d4bac3422bb8c0bcc52b21bfefe617b43ea934) |
| ai-notify-agent | [bb84eb4](https://github.com/JerrySkywalker/ai-notify-agent/commit/bb84eb43830ce46282d69261e180d16bee856eb6) |
| ai-notify-relay | [bb05bc6](https://github.com/JerrySkywalker/ai-notify-relay/commit/bb05bc63731387afe090596d31e8ee0370199ff0) |
| ai-notify-android | [146bf26](https://github.com/JerrySkywalker/ai-notify-android/commit/146bf267d7749b1bc8d6408190da955e7d88d544) |

The prototype ZIP has SHA-256 `48fd9bc95c9dafa5dd026aaabfd2f81c5ecf31f9a474092c9d02d22f45bac129`. Its bundled `SHA256SUMS` covers the individual binaries and APKs.
