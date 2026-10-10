# SleepGuard 项目记忆

本文件记录当前实现、发布方式和已验证结果；具体步骤见 [发布指南](releasing.md)，完整验收记录见 [macos/VALIDATION.md](../macos/VALIDATION.md)。

## 当前实现

- 原生 SwiftUI 菜单栏与管理窗口，保留 Go 后台；应用规则、系统通知、多 Telegram 渠道、历史、暂停/恢复、手动结束应用、所有屏幕黑屏、锁屏和快捷键已接入。
- `0.4.0` 加入 Sparkle 2.10.0 的版本页与应用内更新。按安装包架构读取 GitHub 最新 Release 的 `appcast-arm64.xml` 或 `appcast-x86_64.xml`；下载前校验清单、解压前校验安装包。
- `0.4.1` 菜单按内容高度收缩，最大 640 点，并限制在当前显示器可用高度内；超出后滚动，滚动条隐藏。
- `0.4.2` 在更新前检测运行中可执行文件的身份；文件被替换时自动重新启动并继续更新。构建前与替换前均拒绝覆盖运行中的 App / 内置后台，支持 `APP_OUTPUT` 独立构建目录。
- 本机默认构建为 ad-hoc 签名。后台使用关联应用的兼容 LaunchAgent；Developer ID 构建使用 `SMAppService`。退出确认后停止后台。
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

后续只有文档记忆更新时，主分支可以继续前进；`v0.4.1` 始终保留在上述发布提交。首次使用带更新器的公开版本需要安装 `0.4.1`，真实 `0.4.1 → N+1` 自动升级仍待下一次发布验收。

## 验收边界

本机 Go race/vet、Swift UI 检查、arm64 App 编译与严格包检查通过。菜单组件在原生临时窗口验证了短内容收缩、长内容滚动和恢复短内容高度；本轮未定位实际菜单栏窗口，多显示器切换也未实测。

当前公开包为 ad-hoc 签名，未做 Apple Developer ID 签名和公证。本机签名工具的钥匙串窗口由用户完成系统授权；这不替代应用跨版本授权的验收。真实跨版本升级、自动安装取消、升级失败恢复及 Intel 原生交互尚未验收；不能用编译或组件检查替代这些结论。

## 2026-10-10 自动更新现场修复

`dist/SleepGuard.app` 在旧 GUI 与 watcher 运行时被构建替换，导致两个进程 `proc_pidpath=ENOENT`。安装器获取 macOS 授权身份失败 `-60008`，下载本身成功。以后禁止覆盖仍运行的目标包；开发使用 `APP_OUTPUT` 独立目录。

`0.4.2` 自动重新进入有效 App 后继续更新，保留后台原本运行/停止状态，并显示错误所属阶段和底层原因。生产更新控制器的原生 Sparkle 用例已覆盖正常安装、运行文件被替换、后台保持停止，以及签名异常时保留旧版；使用独立临时后台，不接触真实通知或用户配置。

本机一次性恢复旧失效进程后，已从严格验证通过的公开 `0.4.1` 运行，位置为 `/Applications/SleepGuard.app`，真实 Go 后台已自动恢复；配置与暂停状态未改。`0.4.2` 的双架构发布与公开跨版本升级证据待最终验收后补充。
