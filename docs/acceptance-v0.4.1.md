# v0.4.1 Release Candidate Acceptance and Verification

The v0.4.1 release candidate advances the AI Notify platform across all four repositories: [`AINotify`](../), [`ai-notify-agent`](https://github.com/JerrySkywalker/ai-notify-agent), [`ai-notify-relay`](https://github.com/JerrySkywalker/ai-notify-relay), and [`ai-notify-android`](https://github.com/JerrySkywalker/ai-notify-android).

This milestone delivers end-to-end FCM HTTP v1 integration, Google ADC / OAuth 2.0 bearer credentials, Android WorkManager `SyncWorker` invocation, Firebase Installation ID (FID) management, token privacy hardening, Relay CLI operations (`backup`, `restore`, `prune`), and full-stack event synchronization across paired and direct environments.

---

## 1. Summary of Completed Capabilities

| Scope | Implementation & Verification |
| --- | --- |
| **Provider Delivery Regression Reproduction** | Added unit test `regression_provider_delivery_not_marked_dispatched_without_gateway` in `ai-notify-relay/src/store.rs`, proving that provider deliveries were prematurely recorded as `'dispatched'` without contacting any gateway. Fixed by recording initial provider deliveries as `'pending'`, transitioning to `'accepted'` only upon valid HTTP 200 gateway responses. |
| **Relay FCM HTTP v1 Dispatch & ADC Auth** | Implemented `fcm.rs` in `ai-notify-relay` supporting Google ADC (`GOOGLE_APPLICATION_CREDENTIALS`), short-term OAuth 2.0 bearer tokens (`AINOTIFY_FCM_TOKEN`), and custom gateways (`AINOTIFY_FCM_GATEWAY_URL`). Push payload is strictly restricted to `event_id` (`message.data.event_id`); notification body and previews are never sent over the wire and remain exclusively on the self-hosted Relay. |
| **FCM Resiliency, Retry & Token Cleanup** | Added automated retry on HTTP 429 / 5xx temporary failures with `retry_count` tracking in SQLite, preserved across Relay restarts. On HTTP 404 / `UNREGISTERED` / `NOT_FOUND` permanent failures, Relay automatically deletes the expired device from `push_devices` and marks the delivery record as `'unregistered'`. Verified via 4 dedicated Rust tests and live HTTP mock drill Step 7/7 in `drill-relay-v0.4.1.ps1`. |
| **Android WorkManager & FID Integration** | Integrated `androidx.work:work-runtime-ktx`, `com.google.firebase:firebase-messaging`, and `firebase-installations` in `mobile`. When FCM wakeup is received by `AinotifyFirebaseMessagingService`, it dispatches `SyncWorker` via WorkManager. `SyncWorker` invokes `PhoneSync.performSync`, merging fresh events using existing persistent cursors and deduplication, and forwards previews to paired Wear OS devices via the Data Layer. |
| **Android Opt-In & Zero-Firebase Build Safety** | Added user toggle in `SettingsScreen` managing FID registration and revocation. Wrapped Firebase calls in defensive `FirebaseManager` allowing local builds, Debug ADB simulation broadcasts (`PushReceiver`), and foreground polling (`ReceiveService`) to compile and run smoothly without requiring `google-services.json` or active Firebase configurations. |
| **Release Manifest Hardening & Privacy** | Segregated ADB simulation broadcast receiver (`PushReceiver`, `PUSH_WAKEUP`) to `mobile/src/debug/AndroidManifest.xml`. Validated via `ManifestTest.kt` and `:mobile:processReleaseMainManifest` that release APK manifests contain zero test broadcast entries. Configured `#[serde(skip_serializing)]` ensuring public APIs (`GET /v1/devices` and `GET /v1/push/deliveries`), server logs, and receipts expose only masked tokens (`token_mask`, e.g. `***1234`). |
| **Relay CLI Operations & Database Lifecycle Drill** | Implemented `clap` subcommands (`serve`, `backup`, `restore`, `prune`) in `ai-notify-relay`. Automated 7-step drill script `drill-relay-v0.4.1.ps1` runs in local CI, verifying online backups, historical pruning, in-place restore, rollback stream reset with client resynchronization, zero-downtime dual-key rotation, and live FCM mock dispatch. |
| **Multi-Repo Version Progression** | Synchronized versioning:<br>• `ai-notify-relay`: `0.4.1`<br>• `ai-notify-agent`: `0.4.1`<br>• `ai-notify-android/mobile`: `versionCode = 5`, `versionName = "0.4.1"`<br>• `ai-notify-android/wear`: `versionCode = 6`, `versionName = "0.4.1"` |

---

## 2. Source Revisions at Verification

All tests were executed against the working trees of the four repositories:

| Repository | Git Commit SHA | Tree Status | Version |
| --- | --- | --- | --- |
| `AINotify` | `c7871b72a4eb2e19679b9a32034d29b8d77b33cf` | dirty (CI scripts, drill, docs) | v0.4.1 RC |
| `ai-notify-relay` | `9e6eadbecc6b4f0d416a49970aa70da9c69ea9f6` | dirty (FCM dispatch, store retry, subcommands) | 0.4.1 |
| `ai-notify-agent` | `812bf4818f12985c9caa05258f1bc7a66cbfa2f0` | dirty (0.4.1 bump) | 0.4.1 |
| `ai-notify-android` | `61b28bf6e332f997a14e819e5c02af4434dce7c5` | dirty (WorkManager, FCM service, safe manager) | mobile: 5 (0.4.1), wear: 6 (0.4.1) |

---

## 3. Local Run Receipts & Evidence

### 3.1 Paired Mode CI Suite
- **Command**:
  ```powershell
  . .\Use-AINotifyDev.ps1
  .\AINotify\scripts\local-ci.ps1 -PhoneSerial emulator-5562 -WearSerial emulator-5558 -WearMode paired -SkipBuild
  ```
- **Receipt path**: [`AINotify/docs/evidence/20261125T200610292Z/receipt.json`](evidence/20261125T200610292Z/receipt.json)
- **Watch replacement relay screenshot**: [`AINotify/docs/evidence/20261125T200610292Z/wear-replacement-relay.png`](evidence/20261125T200610292Z/wear-replacement-relay.png)
- **Phone reply screenshot**: [`AINotify/docs/evidence/20261125T200610292Z/phone-reply.png`](evidence/20261125T200610292Z/phone-reply.png)
- **Phone settings & theme screenshots**:
  - [`phone-filters-graphite.png`](evidence/20261125T200610292Z/phone-filters-graphite.png)
  - [`phone-inbox-light.png`](evidence/20261125T200610292Z/phone-inbox-light.png)
  - [`phone-pending-graphite.png`](evidence/20261125T200610292Z/phone-pending-graphite.png)
  - [`phone-settings-amoled-zh.png`](evidence/20261125T200610292Z/phone-settings-amoled-zh.png)
  - [`phone-settings-graphite.png`](evidence/20261125T200610292Z/phone-settings-graphite.png)
  - [`phone-system-dark.png`](evidence/20261125T200610292Z/phone-system-dark.png)
  - [`phone-system-light.png`](evidence/20261125T200610292Z/phone-system-light.png)
- **Wear preview screenshot**: [`AINotify/docs/evidence/20261125T200610292Z/wear-preview.png`](evidence/20261125T200610292Z/wear-preview.png)
- **Desktop tray status**: `passed`
- **Passed checks (25/25)**:
  `hook-stdin`, `offline-retry`, `auth`, `sqlite-restart`, `dedup`, `cursor`, `phone-notification`, `phone-detail`, `wear-notification`, `wear-preview`, `frontend-identity`, `device-group-filters`, `phone-swipes`, `phone-undo`, `relay-inbox-auth`, `relay-inbox-idempotency`, `phone-offline-recovery`, `phone-trash-restore`, `phone-language-theme-accent`, `paired-relay-switch-first-event`, `relay-device-register`, `push-wakeup-screen-off`, `push-dedup`, `push-device-unregister`, `paired-push-wear-sync`.

### 3.2 Direct Mode & Linux Smoke CI Suite
- **Command**:
  ```powershell
  . .\Use-AINotifyDev.ps1
  .\AINotify\scripts\local-ci.ps1 -SkipBuild -PhoneSerial emulator-5562 -WearSerial emulator-5558 -WearMode direct -Linux
  ```
- **Receipt path**: [`AINotify/docs/evidence/20261125T201352296Z/receipt.json`](evidence/20261125T201352296Z/receipt.json)
- **Linux container receipt**: [`AINotify/docs/evidence/20261125T201352296Z/linux/receipt.txt`](evidence/20261125T201352296Z/linux/receipt.txt)
- **Desktop tray status**: `passed`
- **Passed checks (23/23)**:
  `hook-stdin`, `offline-retry`, `auth`, `sqlite-restart`, `dedup`, `cursor`, `phone-notification`, `phone-detail`, `wear-notification`, `wear-preview`, `frontend-identity`, `device-group-filters`, `phone-swipes`, `phone-undo`, `relay-inbox-auth`, `relay-inbox-idempotency`, `phone-offline-recovery`, `phone-trash-restore`, `phone-language-theme-accent`, `relay-device-register`, `push-wakeup-screen-off`, `push-dedup`, `push-device-unregister`.
- **Linux Verification Result**:
  - `cargo test --locked` passed for both `ai-notify-agent` and `ai-notify-relay` (including all 11 relay unit/integration tests).
  - `cargo build --locked --release` passed for both components.
  - Native Linux Stop hook execution, offline queueing, and UTF-8 recovery passed.

---

## 4. Recomputed Artifact SHA-256 Checksums

Computed from [`AINotify/docs/evidence/20261125T201352296Z/artifacts/SHA256SUMS`](evidence/20261125T201352296Z/artifacts/SHA256SUMS):

| Artifact | File Size | SHA-256 Checksum |
| --- | --- | --- |
| `ai-notify-agent-linux-x64` | 4,921,248 bytes | `5550ec1e1200ef9c215237a9abbda28298a94f58ad0000c4e49e09814f41477c` |
| `ai-notify-agent.exe` | 3,558,400 bytes | `7c65b3596e559de0709c84724c619c85e8f91bf17c14e427f60a58bf17550f36` |
| `ai-notify-desktop.exe` | 3,700,736 bytes | `087a2f4683daf3177bbd07e7cf830e651b5e275e655c3c383c7410a0147849aa` |
| `ai-notify-relay-linux-x64` | 5,618,296 bytes | `1bfd1c8a763bd26a31c39feefb6d2da0888f70e20e4a9da8dd96f80a22f2688f` |
| `ai-notify-relay.exe` | 4,213,248 bytes | `5e731b095ef8400eaa1c079097a83637b450cf7b90c69266457a3a1071aafeaa` |
| `mobile-debug.apk` | 34,705,821 bytes | `67ffdc522583d5c47cdb5fe6d461d279649cff74b241bb94793724eb187fed20` |
| `wear-debug.apk` | 25,599,565 bytes | `e2652290fe487935290fa77e2fa67df1cfda7932fdfca51c256efe153ea84293` |

---

## 5. Verification Status by Target Environment

### 5.1 Local Simulation Matrix (Verified & Automated)
- **Status**: PASSED (100% automated in `local-ci.ps1`).
- **Relay Dispatch Drill**: 7/7 checks passed in `drill-relay-v0.4.1.ps1`.
- **Rust Unit Tests**: 11/11 tests passed in `ai-notify-relay` (including regression test, ADC auth, 429 retry, token expiration, restart recovery, stream reset, and backup/pruning).
- **Android Manifest & WorkManager**: Merged release manifest contains zero test receivers; `SyncWorker` and `AinotifyFirebaseMessagingService` compiled cleanly; `ManifestTest.kt` passed.
- **Paired / Direct Topologies**: Verified Doze screen-off wakeup, deduplication, incremental pull, notification rendering, and Data Layer synchronization to paired watch.

### 5.2 FCM Gateway Accepted Drill (Verified & Automated)
- **Status**: PASSED.
- **Execution**: Rehearsed with compiled `ai-notify-relay.exe` against local HTTP mock gateway.
- **Wire Contract Assertions**:
  - `POST /v1/projects/{project_id}/messages:send` receives `Authorization: Bearer <token>`.
  - Wire JSON body carries ONLY `{"message": {"token": "...", "data": {"event_id": "..."}, "android": {"priority": "HIGH"}}}`.
  - Asserted zero notification text or sensitive payloads on the wire.
  - HTTP 200 responses record gateway receipt (`projects/.../messages/...`) and transition delivery status to `accepted`.
  - HTTP 429 responses trigger retry count increment and retain `pending` status.
  - HTTP 404 / `UNREGISTERED` responses trigger automatic device deletion from `push_devices` and delivery status transition to `unregistered`.

### 5.3 Physical Device & Production FCM Infrastructure (External Blocked Registry)
The following items require external hardware, live third-party cloud projects, or administrative signing authority, and are registered as pending external acceptance:

1. **Production FCM Cloud Project & Credentials**:
   - *Status*: Blocked pending authorized Google Cloud project setup.
   - *Requirements*:
     1. Place `google-services.json` in `ai-notify-android/mobile/` for Google Services plugin compilation.
     2. Set environment variables on the Relay server:
        ```bash
        export AINOTIFY_FCM_PROJECT="<gcp-project-id>"
        export GOOGLE_APPLICATION_CREDENTIALS="/etc/ainotify/fcm-service-account.json"
        # Or export short-term OAuth token:
        # export AINOTIFY_FCM_TOKEN="$(gcloud auth print-access-token)"
        ```
     3. Restart Relay service (`systemctl restart ai-notify-relay`).
   - *Re-run Command*: Once configured, send an event and verify `/v1/push/deliveries` records `channel: "provider"`, `status: "accepted"`, and the live `gateway_id` prefix `projects/.../messages/`.

2. **Physical Android Phone & Wear OS Watch Standby Validation**:
   - *Status*: Blocked pending physical test fleet availability.
   - *Requirements*: Physical phone and watch across diverse OEM power profiles (Samsung, Pixel, Xiaomi) under multi-day standby.
   - *Verification Step*: Send a live turn completion event, observe screen-off phone notification and simultaneous watch alert, verify single notification arrival with no duplicate alerts.

3. **Production Keystore Signing & App Store Publication**:
   - *Status*: Blocked pending administrative release authorization.
   - *Requirements*: Official upload keystore and Google Play Console developer account credentials.
