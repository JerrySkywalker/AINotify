# v0.3.0 local acceptance

The v0.3.0 milestone implements and validates phone background push wakeup, device registration orchestration, and unified incremental synchronization across all four repositories (`AINotify`, `ai-notify-agent`, `ai-notify-relay`, `ai-notify-android`).

## Scope & Architectural Contract

| Component | Responsibility & Verification |
| --- | --- |
| **Relay Push Orchestration** | SQLite persistence for push device registrations (`push_devices`) and delivery attempts (`push_deliveries`). Authenticated REST API endpoints: `POST /v1/devices/register`, `POST /v1/devices/unregister`, `GET /v1/devices`, `GET /v1/push/deliveries`. Automated event dispatch logging upon `POST /v1/events`. |
| **Lightweight Wakeup Contract** | Push payloads carry only lightweight synchronization pointers (`event_id`, `seq`, `stream_id`). Full notification details, assistant message text, and project metadata are never passed through third-party push providers. Instead, the phone securely pulls complete records from the self-hosted Relay over authenticated `GET /v1/events` or `GET /v1/events/{id}`. |
| **Unified Android Pipeline** | All synchronization entry points—background push receiver, foreground polling service, app launch, and offline reconnection—funnel through `PhoneSync.performSync`. It manages incremental cursor tracking, event deduplication by UUID, Wear Data Layer preview synchronization, and offline workspace mutation sync. |
| **Background Push Wakeup & Doze** | `PushReceiver` intercepts `io.github.jerryskywalker.ainotify.PUSH_WAKEUP` with `goAsync()` without requiring a persistent foreground service. Successfully wakes device from screen-off / Doze, performs background incremental pull, posts system notifications, and relays preview to paired Wear OS watch. |
| **Duplicate Deduplication** | Verifies duplicate push wakeup signals for identical events are deduplicated by sequence and event UUID, posting notifications exactly once. |
| **Paired Watch Synchronization** | Background push wakeup on phone propagates data items over Wearable Data Layer (`/ainotify/v1/inbox`) to paired Wear OS watch, triggering watch notifications and preview rendering. |

## External Dependencies and Blocked Items

- **Target Network FCM Dispatch**: Local CI validates push registration, wakeup lifecycle, background fetch, and deduplication using Android broadcast signals and local Relay delivery tracking. Verification over Google Firebase Cloud Messaging (FCM) production servers requires active FCM project credentials and Google Play Services push connectivity, which is blocked on production project credentials and external network registration.
- **Physical Device Validation**: Integration tests are executed on Android Studio virtual emulators (`emulator-5562` Phone API 35, `emulator-5558` Wear OS API 35). Physical hardware battery consumption and vendor background app kill behavior are scheduled for external device test runs.

## Local Run Receipts

- **Direct suite receipt**: `AINotify/docs/evidence/20261123T192737597Z/receipt.json`
- **Direct suite artifacts**: `AINotify/docs/evidence/20261123T192737597Z/artifacts/SHA256SUMS`
- **Paired attempt screenshot**: [phone inbox at failure](evidence/20261123T194140207Z/phone-inbox-failure.png)
- **Verified check items**:
  - `relay-device-register`: Device push token registration and validation
  - `push-wakeup-screen-off`: Wakeup from screen-off sleep without foreground service
  - `push-dedup`: Duplicate broadcast suppression
  - `push-device-unregister`: Clean token deregistration
  - `paired-push-wear-sync`: Phone-to-watch Data Layer sync on background wakeup
