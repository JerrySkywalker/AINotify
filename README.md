# AINotify

Send the final reply from coding agents on your computers and servers to one Android and Wear OS inbox. The relay runs on your own server.

| Repository | Responsibility |
| --- | --- |
| `AINotify` | Start here for the roadmap, component map and local end-to-end checks |
| `ai-notify-agent` | Rust collector for Windows and Linux. The Windows desktop app adds a tray and settings window |
| `ai-notify-relay` | Rust HTTP service that authenticates devices and stores events in SQLite |
| `ai-notify-android` | Android inbox and Wear OS preview app in one Gradle build |

Clone the four repositories as siblings. The names used by the local runner are recorded in [components/manifest.json](components/manifest.json).

## Try the prototype

1. Start the relay and configure one reader token and a distinct writer token per collector. See the relay README and its `docs/protocol.md`.
2. On Windows, keep `ai-notify-desktop.exe` next to `ai-notify-agent.exe`. Open Settings from the tray, enter the relay URL and writer token, choose whether to include the final reply, and install the Hooks you want. On Linux, use the headless collector.
3. In the Android app, enter the relay URL and reader token, then start receiving. On Wear OS, use the paired phone mode or enter the reader credentials for direct relay access.
4. Generate a test message from the desktop tray or by running `ai-notify-agent test`, then open the message on the phone.

## Local CI

Use PowerShell 7.4+, Rust, JDK 17, Android SDK Platform 36 and Build Tools 36.0.0. Boot a phone AVD and a Wear OS AVD and find their serials with `adb devices -l`. The command resets the `.dev` application data on the two specified AVDs and uses a local relay with synthetic events.

```powershell
./scripts/local-ci.ps1 -SdkRoot $env:ANDROID_HOME -JavaHome $env:JAVA_HOME -PhoneSerial emulator-5554 -WearSerial emulator-5556
```

Use `-WearMode paired` after pairing the AVDs in Android Studio. Use `-Linux` to build and test both Rust components in a local Linux container. `-Offline` uses the Gradle dependency cache. Reports and screenshots go to `build/ci/`. The desktop check runs in the interactive Windows session.

The Android prototype uses an explicitly enabled foreground receiver. It shows genuine Android notifications without a cloud push provider in the local demo. See [the roadmap](docs/ROADMAP.md) for the background push and device test scope.
