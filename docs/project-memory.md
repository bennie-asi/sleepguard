# SleepGuard 项目记忆

本文件记录当前实现、发布方式和已验证结果；具体步骤见 [发布指南](releasing.md)，完整验收记录见 [macos/VALIDATION.md](../macos/VALIDATION.md)。

## 当前实现

- `0.4.3` 已正式发布：汇总子进程生命周期、独立登录开关、旧服务移除与四项可靠性修复；发布与签名证据见本文件末尾。

- 旧服务移除（2026-10-11，已包含于 0.4.3）：移除 LaunchAgent、独立 helper、CLI `service`、`--run-monitor` 和启动迁移入口；GUI 统一称“监控”，继续由 AppMonitor 管理 Go 子进程，登录项开关独立保留。用户授权删除的本机旧 `agent-settings.json` 已清理，现有配置、规则、历史与登录项未改。

- 可靠性修复（2026-10-11，已包含于 0.4.3）：自动信号与暂停/恢复/黑屏控制共用短时锁；未发信号的复核失败会退避重试；规则与设置保存检查编辑起点；状态页区分界面快照与后台成功采样，并显示后台超时和最近错误。验证范围见 `macos/VALIDATION.md` 同日记录。

- 原生 SwiftUI 菜单栏与管理窗口，保留 Go 后台；应用规则、系统通知、多 Telegram 渠道、历史、暂停/恢复、手动结束应用、所有屏幕黑屏、锁屏和快捷键已接入。
- `0.4.0` 加入 Sparkle 2.10.0 的版本页与应用内更新。按安装包架构读取 GitHub 最新 Release 的 `appcast-arm64.xml` 或 `appcast-x86_64.xml`；下载前校验清单、解压前校验安装包。
- `0.4.1` 菜单按内容高度收缩，最大 640 点，并限制在当前显示器可用高度内；超出后滚动，滚动条隐藏。
- `0.4.2` 在更新前检测运行中可执行文件的身份；文件被替换时自动重新启动并继续更新。构建前与替换前均拒绝覆盖运行中的 App / 内置后台，支持 `APP_OUTPUT` 独立构建目录。
- 本机默认构建为 ad-hoc 签名。工作区的登录启动修复使用 `SMAppService.mainApp` 管理独立开关，GUI 直接管理包内 Go 子进程，不额外注册 LaunchAgent；退出确认后停止后台但保留登录项。历史公开版 `0.4.2` 使用旧后台注册方案；上述变更从 `0.4.3` 开始发布。
- `VERSION` 为唯一发布版本来源，App 和 Go CLI 共享版本/构建号；两种架构的构建号相同。

## 2026-10-10 发布修复

`v0.4.0` 对应提交 `de4326ba5c8dbfef2d9230e95bb569c87f0fbb93`。双架构 [main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38051764287) 通过；[标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38052589535) 失败于 `Require signed release credentials`，日志为 `Missing CERTIFICATE for automatic-update release`。本机没有有效 Developer ID 证书。

修复后 Apple 签名和公证可选：配置证书时要求 Apple 凭据完整；没有证书则构建 ad-hoc 安装包。Sparkle 密钥独立配置，有 Secret 时自动签署并发布六份资产，没有时先创建含两个 DMG 和 SHA-256 的草稿。

草稿使用同一批 CI 安装包在本机签署清单，再上传和发布。Keychain 账户为 `sleepguard`，`scripts/build-appcast.sh` 支持 `SPARKLE_KEYCHAIN_ACCOUNT=sleepguard`；私钥不导出、不写入日志或仓库。只签署将实际上传的包，不能签署本机重建包后配上 CI 的下载地址。

保留失败的 `v0.4.0` 标签，修复使用 `v0.4.1`，不重写既有标签。

## v0.4.1 正式发布证据

- [正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.1) 于 2026-10-10 21:20（Asia/Shanghai）公开；API 回读为 `draft=false`、`prerelease=false`，同时是 `releases/latest`。
- 发布提交为 `63a7aeead69bd99fd150d7452a3cbac0917d49d4`，版本 `0.4.1`、build `4001`。[main 验证](https://github.com/bennie-asi/sleepguard/actions/runs/38054300957) 和 [标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38054674149) 均成功，两种架构完成测试、应用编译、签名检查和 DMG 打包。
- 六份发布资产全部回读为 `uploaded`：两种架构的 DMG、各自 `.sha256` 和 `appcast-arm64.xml` / `appcast-x86_64.xml`。网页另外显示 GitHub 自动生成的两个源码归档，不计入这六份上传资产。
- 本机下载的是上述标签流水线的安装包，并通过原有 Keychain 账户签署清单。公开下载包与 CI 包逐字节一致，六份公开资产的 SHA-256 与 GitHub digest 一致；两个 `releases/latest/download/appcast-*.xml` 与签署原件一致。
- 使用 `macos/Info.plist` 中固定的 `SUPublicEDKey` 独立验证清单和 DMG 的 Ed25519 签名，两种架构均通过。没有导出私钥，也没有放宽客户端签名校验。

| 架构 | DMG SHA-256 |
| --- | --- |
| arm64 | `adf312c0a01816362a1fa072cd79b8deed2ce32e800e4b4cfb9a54175cf9f4fb` |
| x86_64 | `e7345e4cc809ee446f81ffa8f8af6d4c80d180912dd585404142635b21f59ad6` |

后续只有文档记忆更新时，主分支可以继续前进；`v0.4.1` 始终保留在上述发布提交。`0.4.1` 是首个公开可用的更新器版本；真实 `0.4.1 → 0.4.2` 升级结果见下方记录。

## 验收边界

本机 Go race/vet、Swift UI 检查、arm64 App 编译与严格包检查通过。菜单组件在原生临时窗口验证了短内容收缩、长内容滚动和恢复短内容高度；本轮未定位实际菜单栏窗口，多显示器切换也未实测。

当前公开包为 ad-hoc 签名，未做 Apple Developer ID 签名和公证。本机签名工具的钥匙串窗口由用户完成系统授权；客户端校验只使用公钥。Apple Silicon 的公开跨版本升级和真实 Go 后台恢复已通过；异常签名保留旧版、后台保持停止及失效进程重启使用独立原生集成用例验证。Developer ID、公证、Intel 原生交互、退出时自动安装及其取消尚未验收。

## 2026-10-10 自动更新现场修复

`dist/SleepGuard.app` 在旧 GUI 与 watcher 运行时被构建替换，导致两个进程 `proc_pidpath=ENOENT`。安装器获取 macOS 授权身份失败 `-60008`，下载本身成功。以后禁止覆盖仍运行的目标包；开发使用 `APP_OUTPUT` 独立目录。

`0.4.2` 自动重新进入有效 App 后继续更新，保留后台原本运行/停止状态，并显示错误所属阶段和底层原因。生产更新控制器的原生 Sparkle 用例已覆盖正常安装、运行文件被替换、后台保持停止，以及签名异常时保留旧版；使用独立临时后台，不接触真实通知或用户配置。

本机一次性恢复旧失效进程后，从严格验证通过的公开 `0.4.1` 运行，位置为 `/Applications/SleepGuard.app`，真实 Go 后台自动恢复；配置与暂停状态未改。随后通过应用内更新升级到公开 `0.4.2`，没有手工复制新包代替升级。

## v0.4.2 正式发布与实际升级证据

- [正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.2) 于 2026-10-10 22:45（Asia/Shanghai）公开；API 回读 `draft=false`、`prerelease=false`，且为最新正式版本，六份上传资产全部为 `uploaded`。
- 发布提交及不可变标签 `v0.4.2` 指向 `4d31f60afe8fee9ce4f5c28d075e6817484652c1`，版本 `0.4.2`、build `4002`。[main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38058923364) 与 [标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38059258230) 均成功，两种架构的包检查通过。
- 两份更新清单在本机 Keychain 签署同一批标签 CI 的 DMG；公开下载的六份资产与 CI 包、签署原件及 GitHub digest 一致。两个 latest 清单入口返回 `0.4.2` 的签署原件；使用固定公钥独立验证两种架构的清单和 DMG 签名通过。
- 22:49 从 `/Applications/SleepGuard.app` 的 `0.4.1` 版本页点击“立即更新”，实际下载 GitHub 正式包并自动安装、退出旧版和重新打开。22:50 界面显示“已更新到 0.4.2，后台已按原状态恢复。”，版本页回读 `0.4.2` / `4002`，状态页显示“监控运行中”，手动刷新正常。
- 旧 GUI `75627`、Go watcher `75646` 已退出；新 GUI `78527`、真实 Go watcher `78547` 均从 `/Applications/SleepGuard.app` 运行，`proc_pidpath` 有效。安装后的严格签名检查通过，内置 CLI 回读 `SleepGuard 0.4.2 (4002)`。
- 配置 SHA-256、暂停时间、后台原本运行状态及服务安装状态保持一致；升级前的 43 条 SQLite 事件逐条哈希回读一致。

| 架构 | DMG SHA-256 |
| --- | --- |
| arm64 | `9a465c30610430448c45bf998f2b5529d611d117b2d6336aa01932ccb17c93d5` |
| x86_64 | `96bfd6c898e521f7f5c337a13b9b3d264b62dffe75a02814cd9ab98633617eea` |


## v0.4.3 正式发布证据

- 2026-10-11 10:56（Asia/Shanghai）回读 [正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.3)：已公开、标记 Latest，包含六份上传资产（另外两份为 GitHub 自动生成的源码归档）。本机未安装该版本，未将构建成功视为真实升级通过。
- 发布提交 `f85f24780976222853f06cafa2bcd82b45adc90a`，版本 `0.4.3` / build `4003`；远端 `v0.4.3` 指向同一提交。[main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38106060255) 与 [标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38106378996) 的 Apple Silicon / Intel 测试、签名、DMG 与包检查均成功。
- Actions 未配置 Sparkle Secret，先生成包含两份 DMG 和校验文件的草稿。下载的标签 CI artifacts（arm64 `11689682135`、x86_64 `11689827937`）通过 ZIP digest 和 DMG checksum 校验后，使用 Keychain 账户 `sleepguard` 签署同一批 CI 安装包，上传两份清单再发布；没有导出私钥或替换安装包。
- 使用客户端内置 `SUPublicEDKey`，通过 CryptoKit 独立验证两份 DMG 和两份清单的 Ed25519 签名均通过；清单版本为 `0.4.3` / `4003`，下载地址和文件长度正确。六份公开下载资产逐字节与 CI 包及签署原件一致，也与 GitHub 页面显示的 SHA-256 一致；两种架构的 `releases/latest/download/appcast-*.xml` 均回读为本次签署原件。
- 仍使用 ad-hoc Apple 签名，未做 Developer ID 和公证。真实 `0.4.2 → 0.4.3` 自动升级、登录/重启及 Intel 原生交互尚未验收。

| 架构 | DMG SHA-256 |
| --- | --- |
| arm64 | `bf2bdbadcc361cb0fe39788df03c95609f8ec9f1f931ad4d2e7610d20b3d6328` |
| x86_64 | `2c98afcd4162f2e1368b04384e864e7fa5bbb0d2e92c7f11d675b7c7999238aa` |

## 2026-10-11 日志轮转与菜单高度（随后随 v0.4.4 发布）

- 桌面监控的 stdout/stderr 通过管道交给应用写入 `agent.log`；按本地日期变化或 10 MiB 大小轮转。归档命名为 `agent-<毫秒时间戳>-<UUID>.log`，文件权限为 0600。只清理符合该命名的普通归档文件，不删除数据库、当前日志、其他文件或符号链接。
- `[monitor].log_retention_days` 默认 7，范围 1–365；`log_retention_count` 默认 10，范围 1–100，份数不含当前日志。超出任一限制即删除最旧归档。应用内保存立即应用，外部配置修改在界面自动刷新时读取；监控停止期间的清理在下次启动执行。事件历史仍由 `retention_days` 单独管理。
- 菜单改为测量内容的自然高度，窗口高度取内容与当前屏幕上限的较小值；超长内容保留滚动。移除原来的 `ViewThatFits` 加自定义有界布局组合，避免窗口沿用较大的建议高度。
- 自动化检查、arm64 独立构建和包检查通过。原生设置页编辑和保存已回读；菜单容器的短/长/恢复短内容及屏幕高度上限变化已通过原生 NSHostingView 验证。实际菜单栏入口、多显示器切换与新版本发布尚未验收。详见 `macos/VALIDATION.md`。

## v0.4.4 正式发布证据

- 2026-10-11 11:21（Asia/Shanghai）回读 [正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.4)：已公开、标记 Latest，六份上传资产齐全。发布提交 `89bc2d141c94455616c88d5b6be02a2877e9af3c`，版本 `0.4.4` / build `4004`；远端 `v0.4.4` 指向同一提交。
- 按用户要求，main 不再触发重复构建，提交后直接推送版本标签；[标签流水线](https://github.com/bennie-asi/sleepguard/actions/runs/38107826517) 的 Apple Silicon、Intel 和 release 三个任务均成功。两种架构完成 Go race/vet、Swift 检查、构建、严格签名包检查及 DMG 打包。PR 与手动构建保留。
- 标签 CI artifacts：arm64 `11690393585`，x86_64 `11689654207`；下载 ZIP digest 和 DMG 校验和均通过。Actions 缺少 Sparkle Secret，先创建草稿；随后使用本机 Keychain 账户 `sleepguard` 对同一批 CI 安装包生成签名清单，未导出私钥或替换 CI 安装包。
- CryptoKit 使用客户端内置公钥独立验证两份 DMG 和两份 appcast 的 Ed25519 签名通过；六份公开下载资产与 CI 包/签署原件逐字节一致，也与 GitHub 页面 digest 一致。两个 `releases/latest/download/appcast-*.xml` 均回读为 `0.4.4 / 4004` 的签署原件。
- 本机运行的 `0.4.3 / 4003` 版本页已显示“可用版本 0.4.4”。此次只确认更新发现，不将其视为跨版本安装或真实菜单栏视觉验收通过。
- 预览应用及其测试偏好/注册、测试二进制、独立本地构建、下载的 ZIP/DMG、清单及签名验证临时目录均已清理。保留可复用依赖/编译缓存与既有验收证据，未改动用户安装包、规则、配置、数据库或运行日志。

| 架构 | DMG SHA-256 |
| --- | --- |
| arm64 | `f393e6ac6176d66236bdc5c9357a34c402b6e1abf360d30aa5464c8e84bd3cd1` |
| x86_64 | `90d6c99be85dcbfbe9c5bd10e41410f26c9bc2317bb9308ff62e67612667cd9f` |


## 2026-10-11 v0.4.5 菜单无响应修复

- 更新到 0.4.4 后，现场 GUI 29105 的主线程停在 `GoBackend.configuration → AppMonitor.configureLog → MonitorLog.configure → __psynch_mutexwait`；日志回调持锁停在 `NSFileHandle.read(upToCount:) → read`。短日志不足 64 KiB 时等待更多数据，导致主线程无法刷新和处理菜单。真实 Go 子进程 29120 当时仍运行；根因是日志读取阻塞。
- 改为非阻塞 POSIX 管道读取，区分暂时无数据与 EOF，重试 EINTR，退出时分块排空剩余输出。保留日志轮转、保留策略和菜单自然高度。
- 新增独立子进程回归：写入短 stdout/stderr 后保持存活，主线程等待 700 ms 后修改日志配置、读取错误状态与已落盘短日志，再正常停止。Python 外部 15 秒超时可捕获主线程卡死，失败清理只针对测试进程。另将 v0.4.4 的原始 MonitorLog 与同一测试编译运行：旧生命周期检查通过，新增短输出用例稳定超时；修复版通过。
- `make test check check-ui`、独立 arm64 App 构建及严格包检查通过；既有大输出完整性、异常重试、父进程退出、轮转和菜单高度检查通过。现场升级和实际菜单入口验收待发布后执行。


## v0.4.5 正式发布与现场恢复

- 2026-10-11 11:38（Asia/Shanghai）确认 [正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.5) 已公开、标记 Latest，六份上传资产齐全。发布提交 `80c0858c30c9807c0b9f5208f8e616a28369f40d`，版本 `0.4.5` / build `4005`，远端 main 与不可变 `v0.4.5` 标签在发布时指向同一提交。
- 直接推送标签触发 [发布流水线](https://github.com/bennie-asi/sleepguard/actions/runs/38108331118)。arm64 首次测试和编译通过，但 hdiutil 创建 DMG 报 Resource busy；仅重试失败任务及 release，未移动标签。最终 arm64 `114379757442`、保留成功结果的 Intel `114379758317` 和 release `114380190129` 均成功。
- 同一标签的 CI artifacts：arm64 `11691521049`，x86_64 `11690735950`。ZIP digest、DMG checksum 均通过；本机 Keychain 账户 `sleepguard` 签署原始 CI DMG 的清单。使用客户端固定公钥通过 CryptoKit 独立验证两种架构的清单和安装包签名，六份公开资产均与签署原件逐字节一致，两个 latest feed 回读为 `0.4.5 / 4005`。
- 现场先对仍运行的 0.4.4 监控子进程 `29120` 发送 SIGTERM，正常退出关闭输出管道后，GUI `29105` 解除日志锁阻塞，真实菜单能够展开并进入版本页。点击“检查更新”发现 0.4.5，再点击“立即更新”完成 GitHub 正式包的下载、校验、安装和重开，未覆盖运行中的 App。
- 新版本页回读 `0.4.5 / 4005`；恢复原本开启的监控后，GUI `31013` 与真实 Go 子进程 `31080` 均从 `/Applications/SleepGuard.app` 运行，启动后主界面可继续响应。当前日志已立即落盘；再次采样确认主线程处于正常事件循环，没有等待 MonitorLog 锁。安装后严格签名验证通过，配置与控制状态哈希相同，升级前 46 条事件逐条哈希一致。新版真实菜单弹窗待用户点击后直接检查；多显示器及 Intel 原生交互未验收。
- 发布过程中由错误编辑入口自动生成的重复临时草稿 `untagged-e5571589dff96cb0375f` 已撤销；保留 CI 正式发布。临时测试进程、独立本地构建、进程采样、下载包、签名清单及验证辅助文件均已清理，未残留本次挂载镜像。

| 架构 | DMG SHA-256 |
| --- | --- |
| arm64 | `31ea8fca4532aa615fda3d06c449d3b01f131e94534320d5393b6de08844227e` |
| x86_64 | `5936340a96e348687d445a0674694959933d33669b67db292d58de73bd0ab43f` |


## 2026-10-11 v0.4.7 菜单宿主窗口高度修复

- 用户在公开 0.4.5 中再次反馈菜单上下留白。旧检查只验证 NSHostingView.fittingSize，未检查宿主窗口及内容视图的实际高度；0.4.5 现场恢复验证不能当作菜单高度验收。
- 菜单容器将自然内容高度交给 MenuPresentation，同步调整自己捕获的 NSWindow 内容尺寸。保持顶部锚点，长内容继续受屏幕高度上限约束；菜单成为 key window 时重新匹配高度，屏幕变化时同步更新。管理窗口不参与这个调整。
- 扩展原生检查，使用生产 MenuWindowReader 捕获窗口，断言 fittingSize、实际内容视图和窗口高度一致，并检查顶部位置不变。短/长/短、屏幕高度变化的实测为 320×180 → 320×640 → 320×220 → 320×150 → 320×220；宿主恢复旧 640 高度后重新适配到 220 的检查也通过。
- make test check check-ui、独立 arm64 App 构建及严格包检查通过。正式 /Applications/SleepGuard.app 和真实监控保持 0.4.5，用户配置与运行状态未改。
- 用户点击独立验收应用的尺子菜单后，已直接检查真实 MenuBarExtra 弹窗：短内容截图为 640×360 像素（320×180 点），长内容为 640×1280 像素（320×640 点），可滚动到底部；恢复短内容后再次收缩为 320×180 点，没有额外上下留白。此验收复用生产菜单容器和窗口控制器；正式应用更新后的完整菜单、多显示器和 Intel 原生交互仍待验收。
- 测试应用已退出，生成源、二进制、测试偏好和精确 LaunchServices 注册均已清理。未改动正式应用、监控或用户配置。
- v0.4.6 标签 CI 的 arm64 菜单检查在 macOS 15 上失败：实际窗口已经是 320×180，但未显示的窗口被 AppKit 首次布局重新定位，导致以布局前位置为基准的顶部断言失败。保留不可变 v0.4.6 标签，不发布该版本；v0.4.7 将尺寸检查与控制器的顶部锚点检查分开，仍完整断言实际内容视图和窗口高度，并在显式恢复旧尺寸后验证顶部不变。生产修复不变。


## v0.4.7 正式发布与升级验收

- 2026-10-11 12:50（Asia/Shanghai）确认 [正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.7) 已公开并标记 Latest，六份上传资产齐全。发布提交 `09c4365641f1c98df0b887aba353aed5cef91a97`，版本 `0.4.7` / build `4007`；不可变标签对应同一提交。v0.4.6 保留为未发布的失败检查标签。
- 直接推送版本标签触发 [发布流水线](https://github.com/bennie-asi/sleepguard/actions/runs/38112539559)，不先构建 main。arm64 `114390912292`、Intel `114390912226` 和 release `114391553813` 均成功；两种架构的 Go race/vet、Swift 检查、构建、签名包检查及 DMG 打包通过。
- CI artifacts：arm64 `11691933205`、x86_64 `11692416142`。下载 ZIP digest 和安装包 checksum 通过，本机 Keychain 账户 `sleepguard` 签署同一批 CI 原始安装包的更新清单。使用客户端固定公钥，通过 CryptoKit 独立验证两份安装包和两份清单的 Ed25519 签名；六份公开资产与原件逐字节一致，两个 latest feed 也与 `0.4.7 / 4007` 签署原件一致。
- 0.4.5 应用内“检查更新”发现 0.4.7，“立即更新”完成下载、校验、安装和重开。回读 `/Applications/SleepGuard.app` 为 0.4.7，GUI `8886` 和其 Go 监控子进程 `8902` 均从正式安装路径运行，监控自动恢复且界面正常响应。配置哈希不变，升级前 48 条事件逐条哈希一致，当前日志正常落盘，安装后的严格签名验证通过。
- 真实 MenuBarExtra 测试弹窗已通过短/长/短及滚动验收。用户展开正式 SleepGuard 菜单后，直接读取 `/Applications/SleepGuard.app` 的真实弹窗并截图检查：底部显示 v0.4.7，顶部标题、状态、操作区、导航项及底部版本/刷新/退出均完整可见，菜单上下额外留白已消除，无内容裁切；辅助功能树确认当前为菜单 system dialog，监控运行中。本机正式菜单视觉验收通过；多显示器和 Intel 原生交互未验收。
- 本次测试应用、注册和偏好、下载 ZIP/DMG、签名清单、哈希快照及验证辅助文件均已清理；无残留测试进程或挂载镜像。保留依赖缓存和既有验收证据。

| 架构 | DMG SHA-256 |
| --- | --- |
| arm64 | `55510c08c25c325774b0fc7ee7c0c1a2134d0ac2bcdbdcaa47a433835067c037` |
| x86_64 | `acb91a5c62860b87b54eb5c8a0c57befc404e4b47bef98de49793ec29297665f` |


## 2026-10-11 搜索重复应用条目清理

- 用户反馈搜索中出现两个 SleepGuard。现场 Spotlight 文件索引只返回 `/Applications/SleepGuard.app`，但 LaunchServices 仍保留已不存在的 `work/log-rotation/SleepGuard.app`（0.4.3）及正式安装（0.4.7）两条同名应用记录。此前删除测试文件时漏清了旧注册项；先前“已清理”不应被理解为所有历史注册项都已回读确认。
- 使用 `lsregister -u` 精确移除旧日志轮转预览路径，同时移除已不存在的 `sleepguard-build-guard-zx0nlp3p/Fixture.app` 注册及被误识别为应用的 `~/Library/HTTPStorages/io.sleepguard.app` 注册。HTTP 缓存目录本身保留，正式应用、配置、历史和运行状态均未修改；未重建全局注册库或后台项目数据库。
- 清理后直接回读 LaunchServices，`io.sleepguard.app` 只剩 `/Applications/SleepGuard.app`，版本 0.4.7；发布清理步骤已补充“删除前取消精确路径注册，删除后回读应用列表和文件索引”。搜索界面的视觉复查未完成，界面工具未能打开 Spotlight。
