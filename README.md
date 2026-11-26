# AINotify

[简体中文](README.zh-CN.md)

Send the final reply from coding agents on your computers and servers to one Android and Wear OS inbox. The relay runs on your own server.

| Repository | Responsibility |
| --- | --- |
| **AINotify** | Start here for the roadmap, component map and local end-to-end checks |
| [ai-notify-agent](https://github.com/JerrySkywalker/ai-notify-agent) | Rust collector for Windows and Linux. The Windows desktop app adds a tray and settings window |
| [ai-notify-relay](https://github.com/JerrySkywalker/ai-notify-relay) | Rust HTTP service that authenticates devices and stores events in SQLite |
| [ai-notify-android](https://github.com/JerrySkywalker/ai-notify-android) | Android inbox and Wear OS preview app in one Gradle build |

Clone the four repositories as siblings. See the [component manifest](components/manifest.json) and the [development handoff and acceptance checklist](docs/GOAL-TRAIN-v0.4.0.md).

## v0.2.0 preview

[GitHub prerelease](https://github.com/JerrySkywalker/AINotify/releases/tag/v0.2.0) · [Android APK](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/mobile-debug.apk) · [Wear OS APK](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/wear-debug.apk) · [Local acceptance](docs/acceptance-v0.2.0.md)

The Material 3 phone inbox adds filters for devices, device groups and AI frontends. Each swipe direction can pin, archive or move a reply to Trash, with undo and restore available. Choose English, Simplified Chinese or the system language, plus light, dark graphite, AMOLED black or the system theme. An optional inbox token enables Relay sync for reply actions, including recovery after going offline.

[Phone inbox and setup](docs/phone-inbox.md) · [Dark graphite inbox](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/phone-pending-graphite.png) · [AMOLED settings](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/phone-settings-amoled-zh.png)

## v0.1 prototype

[Download the prototype ZIP](https://github.com/JerrySkywalker/AINotify/releases/download/v0.1.0/AINotify-v0.1.0-local.zip) · [Release and assets](https://github.com/JerrySkywalker/AINotify/releases/tag/v0.1.0) · [Local acceptance results](docs/acceptance-v0.1.0.md)

The archive contains the Windows tray app, Windows and Linux collectors and relays, Android and Wear OS debug APKs, and SHA-256 checksums. Local tests exercised installed Hook handlers with sample events, relay restart and retry, the Windows tray, and Android and Wear OS API 35 emulators. The watch connected directly to the relay in this run.

## Try the prototype

1. Start the relay and configure one reader token and a distinct writer token per collector. See the [relay guide](https://github.com/JerrySkywalker/ai-notify-relay#readme) and [protocol](https://github.com/JerrySkywalker/ai-notify-relay/blob/main/docs/protocol.md).
2. On Windows, keep `ai-notify-desktop.exe` next to `ai-notify-agent.exe`. Open Settings from the tray, enter the relay URL and writer token, choose whether to include the final reply, and install the Hooks you want. On Linux, use the [headless collector](https://github.com/JerrySkywalker/ai-notify-agent#linux-or-headless-windows).
3. In the Android app, enter the relay URL and a reader token, or configure an optional inbox token in the Relay to sync reply actions across phones. Start receiving in the app. On Wear OS, use the paired phone mode or enter the reader credentials for direct relay access.
4. Generate a test message from the desktop tray or by running `ai-notify-agent test`, then open the message on the phone.

## Local CI

CI runs locally. GitHub Actions is disabled for all four repositories.

Use PowerShell 7.4+, Rust, JDK 17, Android SDK Platform 36 and Build Tools 36.0.0. Boot a phone AVD and a Wear OS AVD and find their serials with `adb devices -l`. The command resets the `.dev` application data on the two specified AVDs and uses a local relay with synthetic events.

```powershell
./scripts/local-ci.ps1 -SdkRoot $env:ANDROID_HOME -JavaHome $env:JAVA_HOME -PhoneSerial emulator-5554 -WearSerial emulator-5556
```

Use `-WearMode paired` after pairing the AVDs in Android Studio. Use `-Linux` to build and test both Rust components in a local Linux container. `-Offline` uses the Gradle dependency cache. Reports and screenshots go to `build/ci/`. The desktop check runs in the interactive Windows session.

The Android prototype uses an explicitly enabled foreground receiver. See the [roadmap](docs/ROADMAP.md) for background push and device testing.
