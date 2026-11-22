# AINotify

把多台电脑和服务器上的 AI 工具完成事件和最后一条回复，发到一个 Android 和 Wear OS 收件箱。消息保存在你自己的 relay。

| 仓库 | 功能 |
| --- | --- |
| `AINotify` | 顶层入口、路线图和全本地验收 |
| `ai-notify-agent` | Windows 和 Linux Rust 采集端。Windows 提供托盘与原生设置窗口 |
| `ai-notify-relay` | Rust HTTP 服务、设备认证、SQLite、去重与历史查询 |
| `ai-notify-android` | 在一个 Gradle 工程里构建 Android App 和 Wear OS App |

把四个仓库检出为同级目录。项目清单见 [components/manifest.json](components/manifest.json)。安装路径、本地 CI 命令和双 AVD 参数见 [README](README.md)。进度与验收边界见 [路线图](docs/ROADMAP.md)。
