# SleepGuard 版本与自动更新设计

状态：2026-10-10 已完成本地代码接入与 arm64 构建检查；尚未发布 `v0.4.0`，也未验证两份正式签名安装包之间的真实升级。

## 用户流程

“版本与更新”位于管理窗口和菜单栏，展示当前版本、构建号、运行架构、可用版本、检查结果与进度。“立即更新”一次点击启动 Sparkle 检查，发现可安装版本后直接下载、校验、安装并重新打开应用。正常应用内更新没有打开 DMG 或再次确认安装的步骤；macOS 在安装位置需要授权时仍可能显示系统授权窗口。

自动检查默认开启，每 24 小时由运行中的 GUI 进程调度。关闭自动检查后仍可手动检查或点击“立即更新”。“自动下载并安装”默认关闭；开启后，Sparkle 在后台下载更新，在退出应用时安装。两项偏好由 Sparkle 存入应用 UserDefaults，不写入 Go 配置。关闭自动检查会同时关闭自动下载，但重新开启检查不会替用户开启自动下载。

自动下载已经排队后关闭对应开关，应用会通过 Sparkle 的用户回调尝试撤销退出时安装。如果撤销尚未确认，普通退出被拦住并显示重试入口，以免开关已关闭却悄悄安装。此路径已通过编译，仍需真实 N → N+1 更新验收。

## 版本与更新源

根目录 `VERSION` 是发布版本来源，当前为 `0.4.0`。`scripts/build-app.sh` 将其写入 App 的 `CFBundleShortVersionString` 和 Go CLI `version`，构建号由 `major×1000000 + minor×1000 + patch` 生成，同时写入 `CFBundleVersion` 和 CLI。当前构建号为 `4000`，两种架构共享相同版本和构建号。发布标签必须与 `VERSION` 一致，且高于最新正式 Release。Sparkle 使用 bundle 构建号选择更新。

按运行包架构分别读取 GitHub 最新正式 Release 中的 `appcast-arm64.xml` 或 `appcast-x86_64.xml`；清单引用同一 Release 的对应 DMG。客户端不请求 GitHub API，也不让用户编辑任意更新 URL。Intel 版在 Rosetta 下仍读取 Intel 清单。旧版没有更新器时，首次安装 `0.4.0` 仍需按既有安装方式完成；此后才可在应用内一键更新。

固定 Sparkle `2.10.0` 预构建 framework 和 SHA-256。构建脚本下载校验后，把 framework 嵌入 App，并逐一签名嵌套程序、helper、Go CLI 和主应用。正式发布使用 Developer ID、公证及 Sparkle Ed25519 私钥。公钥在 `macos/Info.plist`；私钥只放本机 Keychain 和发布环境 Secret，不入库。发布流水线给两种架构生成带包签名及清单签名的 appcast，连同 DMG、SHA-256 上传到 GitHub Release。`releases/latest/download` 指向当前正式清单。

## 安装与后台边界

下载阶段保持监控运行。主动安装前，检查黑屏保护、未保存设置及正在进行的操作；随后读取最新 watcher 状态，停止并确认后台进程，写入权限为 `0600` 的恢复标记，再允许 Sparkle 替换应用。Sparkle 发起的退出跳过普通退出确认。新 App 启动时，30 分钟内的标记用于按原有状态恢复 watcher；原来未运行则继续保持停止。安装失败时旧 App 尝试恢复后台和状态刷新。配置、数据库、暂停截止时间和 Keychain 保持在原位置。

后台自动下载后的普通退出遵循现有“退出并停止后台”流程；更新在退出后完成，应用保持退出。下次用户启动时，不因自动安装而擅自启动已停止的 watcher。黑屏、未保存设置和停止后台失败都会暂缓主动安装，不强制覆盖 App。

## 已验证与待验收

已验证：arm64 App 编译、Sparkle Swift 接口、嵌套 framework 与整包签名、内置 Go CLI 版本一致性、本地 DMG 构建；使用临时合成密钥和对应测试包验证 appcast 生成与双重签名结构。交互原型验证了单击后直接完成模拟安装、取消和错误状态，但不执行实际更新。

待验收：GitHub Actions 双架构构建、正式 Developer ID 签名和公证、实际 GitHub Release 资产、`0.4.0 → 0.4.1` 一键升级、自动安装排队后关开关、安装失败恢复、watcher 跨版本恢复及 Intel/macOS 13 实机行为。没有这些结果前，不把本地编译当作真实自动更新通过。

发布准备和 Secret 配置见 [`docs/releasing.md`](releasing.md)。交互原型在本次 Codex 可视化目录中的 `sleepguard-updates.html`。
