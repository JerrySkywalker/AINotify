# v0.2.0 local acceptance

The [v0.2.0 prerelease](https://github.com/JerrySkywalker/AINotify/releases/tag/v0.2.0) includes the APKs, test receipts, screenshots and SHA-256 checksums. The receipt records the four source commits used in the run.

| Check | Coverage |
| --- | --- |
| Android phone, API 35 | Notification tap opened the full reply. Combined device, device-group and AI-frontend filters matched the selected sources. Native left and right swipes, a short swipe, disabled swipes, undo and trash recovery were exercised. |
| Appearance and language | English, Simplified Chinese and system locale selection. Theme and accent persisted after an app restart. Screenshots verified the dark graphite, AMOLED black and system light and dark backgrounds. |
| Relay and offline recovery | Reader, inbox and writer access. A repeated action ID applied once. Separate folder and pin changes preserved each other. An offline action survived an app restart, reached the Relay after reconnection and cleared its pending indicator. |
| Wear OS, API 35 | The watch received a notification through direct Relay access and displayed its reply preview. |
| Windows collector and tray | Local Rust build, Clippy and tests. Installed Codex and Claude Code Stop hooks accepted synthetic UTF-8 payloads. The native tray opened Settings, retained its configuration and sent a test message while the window was hidden. |
| Linux collector and Relay | Local container builds and tests, a native shell Hook with frontend metadata, and delivery of the queued UTF-8 reply after an offline send. |

The local run used synthetic Hook payloads and a loopback Relay. Live AI sessions, physical devices and phone-to-watch pairing remain outside this run. GitHub Actions is disabled across all four repositories.

[Machine-readable CI receipt](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/local-ci-receipt.json) · [Linux smoke receipt](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/linux-receipt.txt) · [Artifact checksums](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/SHA256SUMS)
