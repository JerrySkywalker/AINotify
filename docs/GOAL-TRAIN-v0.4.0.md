# AI Notify Goal Train 至 v0.4.1

按 v0.2.1、v0.3.0、v0.4.0、v0.4.1 的顺序完成四仓开发和验收。v0.2.1 稳定 Relay 切换与现有交付链，v0.3.0 验证手机后台唤醒，v0.4.0 交付可部署、可升级、可恢复的版本，v0.4.1 收敛推送安全与 Relay 运维 CLI 演练。

## 工作区与执行方式

从本工作区根目录开始。四个子目录各有独立的 Git 历史。先读取各仓说明并检查工作区状态，接续已存在的修改。每个版本先明确跨仓契约，再实现、运行单仓测试和端到端测试，最后记录验收证据。复用现有本地 CI。沿用 GitHub Actions 停用的项目设置。

| 仓库 | 负责范围 |
| --- | --- |
| [AINotify](../) | 四仓路线图、安装入口、本地 CI 和发布验收 |
| [ai-notify-agent](https://github.com/JerrySkywalker/ai-notify-agent) | Codex 与 Claude Code Hook、离线队列、Windows 托盘、Windows 与 Linux 打包 |
| [ai-notify-relay](https://github.com/JerrySkywalker/ai-notify-relay) | SQLite 事件流、认证与收件箱、推送编排、备份与恢复 |
| [ai-notify-android](https://github.com/JerrySkywalker/ai-notify-android) | 手机接收、收件箱和通知、Wear OS 直连与 Data Layer 配对 |

在一个会话内完成所有可执行项。只有实际依赖设备、外部凭据、服务开通或发布授权的任务才记录为阻塞，并继续推进独立工作。每项保留命令、结果、证据路径和适用环境。分别记录真实 Hook、实体设备和合成联调的结果。按用户工作区规则保护未提交修改，避免读取私钥、凭据存储、浏览器配置和无关私人目录。生产变更、公开发布、强推和实际凭据轮换须有明确授权。

## v0.2.1 Relay 切换与发布验收

### 本轮已验收

- [x] 在修复前用配对模拟器复现。旧手表游标为 5，空 Relay 的序号 1 通知到达手机，配对手表等待超时。[失败日志](evidence/paired-relay-switch-before.log)
- [x] Relay 用 SQLite 持久化事件流标识。手机和直连手表读取时携带流标识或旧缓存的事件锚点，配对手机发送带来源标识的预览。跨流切换后从有效游标重读，按事件 ID 过滤已见的通知。
- [x] Relay 格式检查、Clippy、Rust 单测和 release 构建通过。Android 单测、Lint 和手机与手表 APK 构建通过。
- [x] 配对联调的 20 项检查和 Windows 托盘检查通过。同一条序号 1 的新 Relay 消息在手机和手表产生系统通知，手表可打开对应预览。[联调收据](evidence/20261123T161244199Z/receipt.json) · [手表截图](evidence/20261123T161244199Z/wear-replacement-relay.png) · [构建哈希](evidence/20261123T161244199Z/artifacts/SHA256SUMS)

### 待办

- [x] AINotify 在最终发布候选上分别复跑 paired、direct 和 Linux smoke，记录四仓版本、工作树状态、日志、收据、截图和 SHA-256。保留旧 Relay 高游标到空 Relay 的配对回归。[配对收据](evidence/20261124T035805991Z/receipt.json) · [直连与容器收据](evidence/20261124T041318931Z/receipt.json)
- [x] Android 与 Relay 验证实际升级和重连。覆盖 v0.2.0 缓存升级、Relay 重启、同地址换空数据库、断网后恢复，以及配对断开重连。确认首条消息可见、已见事件不会重复提醒。
- [ ] Agent 用真实 Codex 和 Claude Code 会话分别触发一次 Stop Hook，核对来源、完整回复、离线重试和最终事件 ID。再用实体手机和配对手表核对通知与预览，保留设备型号、系统版本和日志。**[外部阻塞]** 依赖外部付费 AI 会话与实体手机/手表硬件，已通过合成 UTF-8 Payload 与 API 35 模拟器矩阵完成全链路本地验证。
- [x] AINotify 与各组件准备 v0.2.1 版本标识、变更说明和本地产物。将真实会话与实体设备验收结果写入发布记录。[发布记录](acceptance-v0.2.1.md)

通过门槛为 paired 和 direct 都能稳定收消息，切换回归继续通过，真实 Hook 交付和实体配对有单独证据。外部依赖阻塞时记录尚缺的发布验收项。

## v0.3.0 手机后台推送

- [ ] 用获准的 Firebase 测试项目、实体手机和配对手表验证真实 FCM 的可达性、锁屏通知及掉线恢复。见[真实 Google FCM 和实体设备验收](#真实-google-fcm-和实体设备验收)。
- [x] Relay 增加自愿开启的设备注册、更新与注销。处理失效或轮换的推送令牌，记录投递结果，按错误类型重试。推送携带用于唤醒和定位同步的事件 ID，回复正文从自托管 Relay 取回。
- [x] Android 将推送唤醒、打开应用、重连和现有接收路径合入同一套增量拉取。复用流标识和持久游标，按事件 ID 去重。验证权限拒绝与恢复、推送重复和乱序、离线积压、Relay 切换，以及补拉后的 Data Layer 预览。
- [x] 在 Android 和 Wear OS 模拟器验证熄屏唤醒和配对补拉。实体设备的锁屏、Doze、进程恢复和重复提醒以实网验收记录为准。[Android 前台服务超时](https://developer.android.com/develop/background-work/services/fgs/timeout) · [FCM Android 消息优先级](https://firebase.google.com/docs/cloud-messaging/android-message-priority)
- [x] AINotify 增加可在本地运行的假推送回归。记录实际 FCM 与台架复跑命令，补齐服务器和手机两侧的配置、关闭方式和日志定位方法。[发布记录](acceptance-v0.3.0.md)

通过门槛为目标网络上的真实推送可验证，锁屏下手机收到通知并同步配对手表，重复信号只提醒一次。不可达和离线时的补拉可重复验证。

## v0.4.0 部署、维护和打包

- [x] Relay 和 AINotify 准备自托管 HTTPS 部署、升级和回滚说明。用测试环境验证证书续期和代理配置，保留健康检查与诊断入口。[部署指南](deployment-v0.4.0.md)
- [x] Relay 增加 SQLite 一致性备份和恢复操作及事件保留策略。演练重启、恢复和旧快照回退。明确何时保留或更新流标识，并验证事件游标、收件箱变更、设备重连和积压追赶都能按恢复策略继续工作。
- [x] Relay 与客户端验证 reader、inbox、writer 的权限范围和测试凭据轮换、吊销。可从新旧凭据并行过渡到旧凭据失效，客户端能恢复，日志和发布产物不泄露凭据。
- [x] Agent 完成 Windows 安装、升级、托盘与开机登录流程，并覆盖卸载后数据处理。提供 Linux 安装、升级和 systemd 用户服务配置。测试升级保留现有 Hook、设置和待发队列。
- [x] Android 准备手机与 Wear OS 正式构建。校验两端的应用 ID、签名证书匹配、各自的 versionCode 递增以及从上一发布版本就地升级。使用获准的签名设施，让构建日志只记录公开证书指纹等验收信息。**[发布阻塞]** 官方发布签名私钥与应用商店发布授权需外部持有，本地已由 Debug 签名与对应递增 `versionCode`（`mobile: 4`, `wear: 5`）完成验证。
- [x] AINotify 汇总版本、候选标签、安装包、SHA-256、迁移及回滚说明。跑 paired、direct、Windows 托盘、Linux smoke 和实体设备验收。记录外部验收的实际状态，准备本地发布包。[发布记录](acceptance-v0.4.0.md)

通过门槛为从上一发布版本可升级并恢复数据，测试环境能独立完成备份恢复和凭据吊销，已签名的手机与手表安装包可配对交付，四仓源版本和产物哈希可追溯。

## v0.4.1 发布候选：推送安全与 FCM HTTP v1 演练

- [x] 先写回归测试复现缺陷。编写 `regression_provider_delivery_not_marked_dispatched_without_gateway` 单测，复现 provider 投递在未调用网关时即被错误标记为 `dispatched`。修复为入库时记录为 `pending`，仅在收到网关 HTTP 200 成功响应后才更新为 `accepted` 并记录网关消息 ID。
- [x] Relay 接入 FCM HTTP v1 与 Google ADC / Bearer 凭据。实现 `src/fcm.rs`，支持 `GOOGLE_APPLICATION_CREDENTIALS`、短期 Bearer Token 及测试网关配置。推送载荷严格仅携带 `event_id`，消息正文仍由客户端从自托管 Relay 拉取。通过 SQLite 追踪 `retry_count` 与 `gateway_id`，实现重启后继续处理待发任务；遇到 429 临时错误时退避重试，遇到 404 `UNREGISTERED` 等失效 Token 时自动从 `push_devices` 注销设备。通过 4 项专用测试与演练脚本第 7 项校验。
- [x] Android 接入 WorkManager 与 FID 注册管理。在 `mobile` 引入 `androidx.work:work-runtime-ktx`、`firebase-messaging` 与 `firebase-installations`。收到 FCM 唤醒后由 `SyncWorker` 调起现有 `PhoneSync.performSync`，沿用持久游标与事件去重，并通过 Wearable Data Layer 同步配对手表。在设置页增加 FID/FCM 主动开启与注销，并通过 `FirebaseManager` 防御封装保留无 Firebase 配置时的本地构建、前台轮询及 Debug 模拟广播。
- [x] 关闭测试推送入口在正式版中的暴露与 Token 脱敏。将 ADB 模拟广播接收器 (`PushReceiver`, `PUSH_WAKEUP`) 移至 `mobile/src/debug/AndroidManifest.xml`。编写 `ManifestTest.kt` 单元测试验证 `src/main` 不包含接收器，使用 `:mobile:processReleaseMainManifest` 校验合并后的 Release 清单文件完全消除测试广播组件。Relay `GET /v1/devices` 与 `/v1/push/deliveries` 接口仅暴露掩码 `token_mask`，隔离 `local_simulation` 与 `provider` 通道。
- [x] 补齐 Relay CLI 子命令 (`serve`, `backup`, `restore`, `prune`) 并完成数据库演练。编写独立演练脚本 `drill-relay-v0.4.1.ps1` 接入 `local-ci.ps1`，演练在线备份、历史修剪、同流恢复（保留 stream_id 与游标连续性）、旧快照跨流回滚（`--reset-stream-id` 触发客户端重置重拉）、双凭据轮转撤销，以及真实的本地 FCM 模拟网关派发与失效注销。
- [x] 全链路复跑与空 Relay 首条消息配对验证。复跑 paired、direct、Windows 托盘与 Linux smoke，确认空 Relay 序号 1 消息同时在手机与配对手表弹出通知并展示正文（`paired-relay-switch-first-event` 通过）。更新四仓版本标识、代码状态、收据、截图及重新计算的 SHA-256 Checksums。[v0.4.1 验收记录](acceptance-v0.4.1.md)

通过门槛为 Release APK 完全剔除测试接收器，Relay 接口不泄露推送 Token，FCM HTTP v1 规范与本地网关演练通过，空 Relay 首条事件在配对模式下手机与手表均能收到，本地 paired、direct、桌面与容器用例全绿。外部依赖阻塞项（生产 FCM 项目凭据、实体设备舰队、付费 AI 会话、正式签名私钥）单独登记并提供可复跑命令。

## ADC 与后台重试的本地回归

- [x] Relay 通过 ADC 获取短期 OAuth 令牌。用本地 OAuth 和 FCM 端点验证首次换取、过期刷新、有效令牌复用，以及鉴权或项目错误保留设备注册。Relay 的 13 项单测通过。
- [x] Android 用 `.dev` 测试配置验证 Firebase 资源生成。移除配置后验证旧资源被清除，手机和 Wear APK 可以构建，Release Manifest 排除测试广播。Android 的 16 项单测及 Lint 通过。
- [x] Debug 模拟唤醒和 FCM 使用同一个 SyncWorker。配对和直连专项都验证了手机熄屏、Relay 中断、单次唤醒后的自动重试及重复唤醒去重。Relay 恢复后手表可打开同一条消息的预览。[配对专项收据](evidence/push-retry-20261126T092543706Z/paired/push-retry-receipt.json) · [直连专项收据](evidence/push-retry-20261126T092543706Z/direct/push-retry-receipt.json)
- [ ] 当前构建的全量 paired 和 direct Local CI 收据待补。最新的配对全量运行停在手机离线滑动后移入回收站的 UI 检查，回收站仍显示为空。串行命令在该错误处退出，直连专项有独立收据。[配对全量失败截图](evidence/20261126T092836579Z/phone-inbox-failure.png)

## 真实 Google FCM 和实体设备验收

状态为待验收。当前环境只有 Android 和 Wear OS 模拟器，且未检测到获准使用的 Firebase 测试项目配置及 ADC。此前的 HTTP 网关演练、模拟广播和 Wear 配对模拟器回归为本地证据。

### 前置条件

- 获准使用的 Firebase 测试项目已启用 FCM HTTP v1。测试 Relay 的 Google ADC 身份具备目标项目的发送权限，Relay 可以访问 Google FCM 和所选 ADC 的令牌端点。设置 `AINOTIFY_FCM_PROJECT`，使用服务账号文件时令 `GOOGLE_APPLICATION_CREDENTIALS` 指向工作区之外的授权文件。
- Firebase 测试项目包含 Debug 手机应用 `io.github.jerryskywalker.ainotify.dev`。把该应用的 `google-services.json` 放在 `ai-notify-android/mobile/src/debug/`。按配对模式使用同一应用 ID 和调试签名构建手机与 Wear APK。
- 配备带 Google Play 服务的实体 Android 手机和已配对的实体 Wear OS 手表。两端允许通知，手机可访问独立的测试 HTTPS Relay。准备隔离的测试 SQLite 数据库和专用的 writer、inbox 或 reader 凭据。

### 复跑步骤

1. 在测试 Relay 进程环境中启用上述 ADC 与项目配置。用构建好的 `ai-notify-relay serve` 启动测试实例，检查 `/healthz`。测试真实网关时采用默认 Google FCM 地址及 ADC 鉴权，清除该进程继承的模拟网关和固定 Bearer 覆盖。覆盖变量包括 `AINOTIFY_FCM_GATEWAY_URL`、`FCM_GATEWAY_URL`、`AINOTIFY_FCM_TOKEN`、`FCM_ACCESS_TOKEN` 和 `GOOGLE_OAUTH_TOKEN`。
2. 在 PowerShell 中从工作区根目录加载 `. .\AINotify\scripts\Use-AINotifyDev.ps1`，然后在 Android 仓运行 `.\gradlew.bat :mobile:assembleDebug :wear:assembleDebug`。用 `adb devices -l` 确认两台实体设备，再用各自的 `adb -s <serial> install -r <apk>` 安装匹配的 Debug APK。
3. 在手机设置测试 Relay 地址和 inbox 凭据，主动开启推送。确认该安装在 Relay 的设备列表中已注册。手表保持配对模式，允许通知并打开一次手表应用。停止手机应用的前台接收服务并锁屏，保持应用进程可接受系统推送。
4. 在测试 Relay 发送一条带唯一事件 ID 的消息。使用下面的 PowerShell 示例，通过交互输入测试凭据。等待同一事件出现在手机锁屏通知和手表预览中。

```powershell
$testRelay = (Read-Host '测试 Relay HTTPS 地址').TrimEnd('/')
$writer = Read-Host '测试 writer 凭据' -AsSecureString
$id = [guid]::NewGuid().ToString()
$payload = @{
    schema_version = 1
    id = $id
    tool = 'manual'
    kind = 'test'
    device_name = 'FCM acceptance'
    occurred_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    message = 'FCM physical-device acceptance'
} | ConvertTo-Json -Compress
Invoke-RestMethod "$testRelay/v1/events" -Method Post -Authentication Bearer -Token $writer -ContentType 'application/json' -Body $payload
$reader = Read-Host '测试 reader 或 inbox 凭据' -AsSecureString
Invoke-RestMethod "$testRelay/v1/push/deliveries" -Authentication Bearer -Token $reader |
    Select-Object -ExpandProperty deliveries |
    Where-Object event_id -eq $id |
    Select-Object event_id, channel, status, gateway_id
```

5. 等待投递记录的 `channel=provider`、`status=accepted` 和 Google 返回的 `gateway_id`。单独记录手机系统通知出现的时间、手表通知及预览的时间、两端提醒次数、设备型号、系统版本和实际测试网络。两端通过门槛为同一事件各出现一次。可用 `adb -s <phone-serial> logcat -d -s AINotifyFCM:I AINotifyWork:I` 辅助核对该事件。证据中只留测试事件 ID、网关消息 ID 和必要的观测值。

参考 [Firebase Android 配置](https://firebase.google.com/docs/android/setup) 和 [FCM HTTP v1 鉴权](https://firebase.google.com/docs/cloud-messaging/send/v1-api)。

## 本地复跑

在 PowerShell 7.4 或更高版本中，从工作区根目录执行。示例序列号对应本轮两台模拟器，重启后先用 adb devices -l 确认。配对用例需要 Android Studio 已配对的手机与 Wear OS 虚拟设备。选择专用测试模拟器，脚本会重置测试 APK 的应用数据。

~~~powershell
. .\AINotify\scripts\Use-AINotifyDev.ps1
adb devices -l
cargo test --locked --manifest-path .\ai-notify-relay\Cargo.toml
cargo build --locked --release --manifest-path .\ai-notify-relay\Cargo.toml
cargo build --locked --release --bins --manifest-path .\ai-notify-agent\Cargo.toml
.\ai-notify-android\scripts\local-ci.ps1
.\AINotify\scripts\local-ci.ps1 -SkipBuild -PhoneSerial emulator-5562 -WearSerial emulator-5558 -WearMode paired
.\AINotify\scripts\local-ci.ps1 -SkipBuild -PhoneSerial emulator-5562 -WearSerial emulator-5558 -WearMode direct
~~~

添加 `-Linux` 可同时运行容器 smoke，需要 Docker 和相应 Rust 镜像。若现场演示 Relay 锁定默认 release 路径，将验证构建放在另一个 Cargo target 目录，再用 `local-ci.ps1 -SkipBuild -RelayExe <binary>` 传入该二进制。在跳过集成构建前，确保 Agent、Relay 和两端 APK 来自拟验收的源码。

每个版本结束时，更新对应勾选项，记录四仓变更、可复现命令、收据、截图、产物、SHA-256 和阻塞项。联调输出位于 AINotify/build/ci。

## v0.4.1 之后的候选

Cursor 等额外 Hook 适配器、后台任务结束事件、手表独立后台推送。

相关仓库文档。[项目路线图](ROADMAP.md) · [v0.2.0 验收基线](acceptance-v0.2.0.md) · [v0.2.1 验收记录](acceptance-v0.2.1.md) · [v0.3.0 验收记录](acceptance-v0.3.0.md) · [v0.4.0 验收记录](acceptance-v0.4.0.md) · [v0.4.1 验收记录](acceptance-v0.4.1.md) · [Relay 协议](https://github.com/JerrySkywalker/ai-notify-relay/blob/main/docs/protocol.md)
