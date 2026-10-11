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

## 2026-10-11 日志轮转与菜单高度（未发布）

- 桌面监控的 stdout/stderr 通过管道交给应用写入 `agent.log`；按本地日期变化或 10 MiB 大小轮转。归档命名为 `agent-<毫秒时间戳>-<UUID>.log`，文件权限为 0600。只清理符合该命名的普通归档文件，不删除数据库、当前日志、其他文件或符号链接。
- `[monitor].log_retention_days` 默认 7，范围 1–365；`log_retention_count` 默认 10，范围 1–100，份数不含当前日志。超出任一限制即删除最旧归档。应用内保存立即应用，外部配置修改在界面自动刷新时读取；监控停止期间的清理在下次启动执行。事件历史仍由 `retention_days` 单独管理。
- 菜单改为测量内容的自然高度，窗口高度取内容与当前屏幕上限的较小值；超长内容保留滚动。移除原来的 `ViewThatFits` 加自定义有界布局组合，避免窗口沿用较大的建议高度。
- 自动化检查、arm64 独立构建和包检查通过。原生设置页编辑和保存已回读；菜单容器的短/长/恢复短内容及屏幕高度上限变化已通过原生 NSHostingView 验证。实际菜单栏入口、多显示器切换与新版本发布尚未验收。详见 `macos/VALIDATION.md`。
