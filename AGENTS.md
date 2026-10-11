# SleepGuard 项目上下文

项目记忆与已验证的发布记录见 [`docs/project-memory.md`](docs/project-memory.md)。验收证据见 [`macos/VALIDATION.md`](macos/VALIDATION.md)，发布步骤见 [`docs/releasing.md`](docs/releasing.md)。更新事实时区分已验证结果和待验收项。

- SwiftUI 菜单栏与管理窗口在 `macos/Sources/SleepGuard/`；保留 Go 采集、规则、SQLite 历史和后台监控。
- 根目录 `VERSION` 是版本来源，构建号为 `major * 1000000 + minor * 1000 + patch`。标签必须匹配版本，不移动已推送的发布标签或替换已公开的安装包。
- 发布前清理本次测试与打包临时文件；提交版本更新后直接推送版本标签触发发布，不先构建或等待 main。标签流水线仍须完成两种架构的测试、构建和包检查。
- 改动后运行相称的检查：`make test check check-ui`、`make app`、`python3 scripts/check-package.py`。DMG 和 Actions 成功不代表真实跨版本升级已通过。
- Apple 签名与 Sparkle 更新签名是独立环节。Apple 凭据可选；缺少 Sparkle Secret 时 Actions 仅创建草稿，用本机钥匙串签署同一批 CI 安装包的更新清单后发布。保留客户端清单和安装包签名校验。
- Sparkle 私钥由本机 Keychain 账户 `sleepguard` 保存。签名使用 `SPARKLE_KEYCHAIN_ACCOUNT=sleepguard scripts/build-appcast.sh`，无需导出密钥。配置、Token、私钥、数据库和日志不进入仓库或安装包。
- 本机验收保留用户现有规则和运行状态；手动结束与通知测试使用项目自有临时进程和独立配置，不发送真实 Telegram 消息或结束用户应用。
