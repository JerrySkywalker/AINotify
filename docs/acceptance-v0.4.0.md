# v0.4.0 Deployment, Maintenance, and Release Acceptance

The v0.4.0 milestone delivers a production-ready, self-hostable, upgradable, and recoverable AI Notify release across all four repositories: [`AINotify`](../), [`ai-notify-agent`](https://github.com/JerrySkywalker/ai-notify-agent), [`ai-notify-relay`](https://github.com/JerrySkywalker/ai-notify-relay), and [`ai-notify-android`](https://github.com/JerrySkywalker/ai-notify-android).

## Summary of Completed Capabilities

| Scope | Implementation & Verification |
| --- | --- |
| **Relay Maintenance & Consistency** | SQLite online backup API (`Store::backup`) ensuring lock-free point-in-time snapshots during active streaming. Snapshot restoration (`Store::restore`) with configurable `stream_id` reset or retention. Historical event pruning (`Store::prune`) with cascading push delivery cleanup. Tested in `store::tests::backups_restores_resets_stream_and_prunes`. |
| **Zero-Downtime Credential Rotation** | Multi-token authentication supporting comma- and semicolon-separated bearer token sets for `readers`, `inboxes`, and `writers`. Allows side-by-side transition to new credentials and subsequent revocation of old tokens without service interruption or downtime. Tested in `api::tests::credential_rotation_allows_parallel_transition_and_revocation`. |
| **Production Deployment Architecture** | Comprehensive production deployment guide ([`deployment-v0.4.0.md`](deployment-v0.4.0.md)) detailing reverse proxy topologies (Caddy / Nginx), automated ACME TLS certificate lifecycle, systemd user services, health checks (`/healthz`, `/v1/events`), and automated backup/pruning runbooks. |
| **Agent Linux Services & Setup** | Systemd user service unit (`systemd/ai-notify-agent.service`) and automated installation/management script (`scripts/install-systemd.sh`) in `ai-notify-agent`. |
| **Multi-Repo Version Progression** | Synchronized v0.4.0 bumps across all components:<br>• `ai-notify-android/mobile`: `versionCode = 4`, `versionName = "0.4.0"`<br>• `ai-notify-android/wear`: `versionCode = 5`, `versionName = "0.4.0"`<br>• `ai-notify-relay`: `version = "0.4.0"`<br>• `ai-notify-agent`: `version = "0.4.0"` |
| **Multi-Platform Release Packaging** | Automated compilation and packaging of release binaries and APKs:<br>• `ai-notify-agent.exe`<br>• `ai-notify-desktop.exe`<br>• `ai-notify-relay.exe`<br>• `mobile-debug.apk`<br>• `wear-debug.apk`<br>• Linux x86_64 binaries (`ai-notify-agent-linux-x64`, `ai-notify-relay-linux-x64`) via local container runner. |

## Local Run Receipts & Evidence

### 1. Paired Mode Local CI Run
- **Receipt path**: `AINotify/docs/evidence/20261124T035805991Z/receipt.json`
- **Watch replacement screenshot**: `AINotify/docs/evidence/20261124T035805991Z/wear-replacement-relay.png`
- **Phone reply screenshot**: `AINotify/docs/evidence/20261124T035805991Z/phone-reply.png`
- **Phone settings screenshots**: `phone-filters-graphite.png`, `phone-settings-amoled-zh.png`, `phone-system-dark.png`
- **Artifact checksums**: `AINotify/docs/evidence/20261124T035805991Z/artifacts/SHA256SUMS`
- **Passed checks (25/25)**:
  `hook-stdin`, `offline-retry`, `auth`, `sqlite-restart`, `dedup`, `cursor`, `phone-notification`, `phone-detail`, `wear-notification`, `wear-preview`, `frontend-identity`, `device-group-filters`, `phone-swipes`, `phone-undo`, `relay-inbox-auth`, `relay-inbox-idempotency`, `phone-offline-recovery`, `phone-trash-restore`, `phone-language-theme-accent`, `paired-relay-switch-first-event`, `relay-device-register`, `push-wakeup-screen-off`, `push-dedup`, `push-device-unregister`, `paired-push-wear-sync`.

### 2. Direct Mode & Linux Smoke Run
- **Receipt path**: `AINotify/docs/evidence/20261124T041318931Z/receipt.json`
- **Linux container receipt**: `AINotify/docs/evidence/20261124T041318931Z/linux/receipt.txt`
- **Artifact checksums**: `AINotify/docs/evidence/20261124T041318931Z/artifacts/SHA256SUMS`
- **Passed checks (23/23)**:
  `hook-stdin`, `offline-retry`, `auth`, `sqlite-restart`, `dedup`, `cursor`, `phone-notification`, `phone-detail`, `wear-notification`, `wear-preview`, `frontend-identity`, `device-group-filters`, `phone-swipes`, `phone-undo`, `relay-inbox-auth`, `relay-inbox-idempotency`, `phone-offline-recovery`, `phone-trash-restore`, `phone-language-theme-accent`, `relay-device-register`, `push-wakeup-screen-off`, `push-dedup`, `push-device-unregister`.

### 3. Release Artifact SHA-256 Checksums
```
dff5d4e35dabf74a1f4ba66826668e780d734a24c18f76325405bc5e92499e2b  ai-notify-agent-linux-x64
d3b99c2976d92a77303047a4bce67457271d8fd1f4d01efe19ad79197de43b87  ai-notify-agent.exe
2c41f2124f54d9633b7a6eeee61dad1a5c3aca96683caa838948b53aac8e806c  ai-notify-desktop.exe
6029fd35b029ece3b8909bfe9aed31537d7cc6a399408bb15a43cb971abf43b2  ai-notify-relay-linux-x64
4a075bd64fa5575bd7ca46581ea82907118ea97d0830cb3ab2aeb39beb35df2a  ai-notify-relay.exe
fe9463cc21b5a1be3a7f0b403dc217554918b112a2cb274da0bb94aa5e518eff  mobile-debug.apk
bb0722dc679473122d5673385fdb2207acf8e48f4668e7ef7d5c235cc1582d47  wear-debug.apk
```

## External Dependencies & Blockage Registry

Only dependencies requiring external hardware, paid credentials, or administrative release authority are marked as blocked:

1. **Production TLS & Domain Delegation**: Real production Let's Encrypt / ACME TLS provisioning requires a publicly routed DNS domain and listening ports (80/443). Validated locally using reverse proxy simulation and test certificates documented in `deployment-v0.4.0.md`.
2. **Production Release Keystore & App Store Publishing**: Official production APK release signing keys and Google Play Console publication credentials require release authority and proprietary keystores. Verified locally using debug keystores with aligned package namespaces and incremented `versionCode` values (`mobile: 4`, `wear: 5`).
3. **Physical Hardware Multi-Day Standby**: Virtual emulator matrix (`emulator-5562` API 35 + `emulator-5558` Wear OS API 35) validates Doze and background wakeup. True physical multi-day battery impact and vendor OEM power-saving profiles require physical fleet test benches.
4. **Live External AI Assistant Sessions**: Hook execution validated with native UTF-8 stdin and full JSON payloads for Codex and Claude Code. Testing requiring paid external API subscriptions or interactive OAuth login is delegated to external production environments.
