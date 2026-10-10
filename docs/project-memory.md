# SleepGuard 项目记忆

本文件记录当前实现、发布方式和已验证结果；具体步骤见 [发布指南](releasing.md)，完整验收记录见 [macos/VALIDATION.md](../macos/VALIDATION.md)。

## 当前实现

- 原生 SwiftUI 菜单栏与管理窗口，保留 Go 后台；应用规则、系统通知、多 Telegram 渠道、历史、暂停/恢复、手动结束应用、所有屏幕黑屏、锁屏和快捷键已接入。
- `0.4.0` 加入 Sparkle 2.10.0 的版本页与应用内更新。按安装包架构读取 GitHub 最新 Release 的 `appcast-arm64.xml` 或 `appcast-x86_64.xml`；下载前校验清单、解压前校验安装包。
- `0.4.1` 菜单按内容高度收缩，最大 640 点，并限制在当前显示器可用高度内；超出后滚动，滚动条隐藏。
- 本机默认构建为 ad-hoc 签名。后台使用关联应用的兼容 LaunchAgent；Developer ID 构建使用 `SMAppService`。退出确认后停止后台。
- `VERSION` 为唯一发布版本来源，App 和 Go CLI 共享版本/构建号；两种架构的构建号相同。

## 2026-10-10 发布修复

`v0.4.0` 对应提交 `de4326ba5c8dbfef2d9230e95bb569c87f0fbb93`。双架构 [main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38051764287) 通过；[标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38052589535) 失败于 `Require signed release credentials`，日志为 `Missing CERTIFICATE for automatic-update release`。本机没有有效 Developer ID 证书。

修复后 Apple 签名和公证可选：配置证书时要求 Apple 凭据完整；没有证书则构建 ad-hoc 安装包。Sparkle 密钥独立配置，有 Secret 时自动签署并发布六份资产，没有时先创建含两个 DMG 和 SHA-256 的草稿。

草稿使用同一批 CI 安装包在本机签署清单，再上传和发布。Keychain 账户为 `sleepguard`，`scripts/build-appcast.sh` 支持 `SPARKLE_KEYCHAIN_ACCOUNT=sleepguard`；私钥不导出、不写入日志或仓库。只签署将实际上传的包，不能签署本机重建包后配上 CI 的下载地址。

保留失败的 `v0.4.0` 标签，修复使用 `v0.4.1`。发布完成后的提交、流水线、资产和验签结果在此补充。

## 验收边界

本机 Go race/vet、Swift UI 检查、arm64 App 编译与严格包检查通过。Apple Developer ID、公证、真实跨版本升级、自动安装取消、升级失败恢复及 Intel 原生交互尚未验收；不能用编译或模拟原型结果替代这些结论。
