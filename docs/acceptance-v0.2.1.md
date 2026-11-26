# v0.2.1 local acceptance

The v0.2.1 release stabilizes Relay switching, event stream tracking, and paired phone-to-watch delivery across all four components. It includes verification receipts, screenshot artifacts, and SHA-256 checksums from local CI runs.

| Check | Coverage |
| --- | --- |
| Relay stream identity | Persistent `stream_id` in SQLite metadata. Feed query supports `stream_id` and legacy anchor `cursor_event_id`. Replacing database resets cursor to 0 with `reset_cursor: true`, allowing clean recovery without lost notifications. |
| Paired Wear OS delivery | Verified on paired emulator suite. Paired watch with previous high cursor (cursor = 5) successfully receives sequence 1 from an empty replacement Relay, updates its mailbox, and renders the reply preview. |
| Reconnect & deduplication | Android core verifies v0.2.0 unscoped cache migration, Relay restart, empty replacement database at same URL, and catch-up after network gap without duplicate notifications or lost events. |
| Direct Wear OS delivery | Standalone Wear OS foreground receiver polls Relay directly, creates system notifications, and displays reply preview. |
| Windows collector & tray | Local Rust build, clippy, unit tests, and tray integration. Native tray handles click-to-open, settings persistence, close-to-tray, and test message delivery while hidden. |
| Linux collector & Relay | Rust 1.97 Bookworm container smoke suite: native CLI builds, shell Stop Hook installation, offline queuing, and UTF-8 recovery over loopback Relay. |

## External dependencies and blocked items

- **Physical device validation**: The local integration runs on Android Studio virtual emulators (`emulator-5562` Phone API 35, `emulator-5558` Wear OS API 35). Verification on physical hardware (physical phone and watch devices) is blocked on external physical hardware access and is scheduled for external acceptance.
- **Live AI session Stop Hook triggers**: Local testing uses synthetic UTF-8 Codex and Claude Code Stop payloads. Testing against interactive Codex and Claude Code sessions requiring paid external API subscriptions or interactive OAuth credentials is delegated to external production environments.

## Local run receipts

- **Paired suite receipt**: `AINotify/docs/evidence/20261123T161244199Z/receipt.json`
- **Direct & Linux smoke receipt**: `AINotify/docs/evidence/20261123T174049744Z/receipt.json`
- **Watch replacement screenshot**: `AINotify/docs/evidence/20261123T161244199Z/wear-replacement-relay.png`
- **Linux smoke receipt**: `AINotify/docs/evidence/20261123T174049744Z/linux/receipt.txt`
- **Artifact checksums**: `AINotify/docs/evidence/20261123T174049744Z/artifacts/SHA256SUMS`
