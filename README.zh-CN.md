# AINotify

[English](README.md)

把多台电脑和服务器上的 AI 工具完成事件和最后一条回复发到同一个 Android 和 Wear OS 收件箱。消息保存在你自己的 relay。

| 仓库 | 功能 |
| --- | --- |
| **AINotify** | 系列入口、路线图和全本地验收 |
| [ai-notify-agent](https://github.com/JerrySkywalker/ai-notify-agent) | Windows 和 Linux 的 Rust 采集端。Windows 提供托盘与原生设置窗口 |
| [ai-notify-relay](https://github.com/JerrySkywalker/ai-notify-relay) | Rust HTTP 服务、设备鉴权、SQLite、去重和全文查询 |
| [ai-notify-android](https://github.com/JerrySkywalker/ai-notify-android) | 在一个 Gradle 工程里构建 Android App 和 Wear OS App |

## v0.2.0 预发布

[GitHub 预发布](https://github.com/JerrySkywalker/AINotify/releases/tag/v0.2.0) · [手机 APK](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/mobile-debug.apk) · [手表 APK](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/wear-debug.apk) · [本地验收结果](docs/acceptance-v0.2.0.md)

Material 3 手机收件箱支持设备、设备组和 AI 前端组合筛选。左滑和右滑可以分别配置置顶、存档或移到回收站，支持撤销与恢复。语言可选简体中文、English 或跟随系统，主题可选浅色、深石墨、AMOLED 纯黑或跟随系统。配置收件箱令牌后，消息操作经 Relay 同步，断网操作在重连后补传。

[手机收件箱与配置](docs/phone-inbox.md) · [深石墨收件箱](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/phone-pending-graphite.png) · [中文 AMOLED 设置](https://github.com/JerrySkywalker/AINotify/releases/download/v0.2.0/phone-settings-amoled-zh.png)

## v0.1 原型

[原型 ZIP](https://github.com/JerrySkywalker/AINotify/releases/download/v0.1.0/AINotify-v0.1.0-local.zip) · [发布说明和附件](https://github.com/JerrySkywalker/AINotify/releases/tag/v0.1.0) · [本地验收结果](docs/acceptance-v0.1.0.md)

原型包包含 Windows 托盘程序、Windows 和 Linux 采集端与 relay、Android 和 Wear OS 调试 APK，以及 SHA-256 校验值。手机和手表均用 API 35 模拟器验收，手表走 relay 直连。模拟器使用前台服务收取事件。

把四个仓库检出为同级目录。项目清单见 [components/manifest.json](components/manifest.json)。安装步骤、双模拟器参数和本地 CI 命令见 [英文 README](README.md)。四个仓库均禁用 GitHub Actions，CI 继续在本机运行。后续计划见 [路线图](docs/ROADMAP.md)。

当前开发状态、验收证据和接续步骤见 [Goal Train](docs/GOAL-TRAIN-v0.4.0.md)。
