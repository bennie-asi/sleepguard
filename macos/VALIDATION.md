# 本机验证记录

日期：2026-10-10。环境：macOS 27.0.1 / arm64，Swift 6.4，Go 1.27.0。

## 已完成

- `make app GO=go`：生成 `dist/SleepGuard.app`，SwiftUI 与内置 Go 后台均编译成功，ad hoc 签名和严格签名验证通过，无编译警告。
- `make test check build GO=go`：Go 全套竞态测试、`go vet` 和独立 CLI 构建通过。
- 原生窗口读取真实电源来源、空闲时间、休眠配置、防休眠请求与系统诊断。
- 本机应用选择器按已启动、后台任务、未启动分类；搜索 `chrome` 后显示真实匹配项；选择已安装网易云应用得到 `com.netease.163music`。
- 只处理规则保存成功；通知与处理均关闭显示忽略；手动绝对路径规则支持两项同时勾选，相对路径被拒绝。
- 添加待接入 Webhook 渠道可保存，开关和测试不可启用。添加渠道不会保存其他页面未提交的规则草稿。
- 两个电报验收渠道分别启用、停用；其中一个测试失败后，另一渠道的开关和结果不受影响。测试使用未配置的独立环境变量，没有使用真实 Token、创建钥匙串凭据或发送外部消息。
- 初次验收在界面启动 Go LaunchAgent，回读其可执行文件及配置、状态目录；日志 `agent.log` 正常生成，从界面停止后台后 watcher 锁释放。本轮已将退出行为改为确认后同时停止后台。
- 在界面暂停一小时、立即恢复，状态及 SQLite 历史均回读一致。恢复会重新累计异常，测试覆盖通知尚未完成时恢复造成的竞态。
- 监控设置从 `grace = "5m"` 改为 `"6m"` 并保存，配置回读确认。处理等待、最终宽限期和强制结束选项使用实际配置。
- 初次验收的系统通知 helper 读到尚未授权；投递请求返回权限不足，没有自动申请或改变系统权限。之后用户已授权系统通知。
- 旧 SQLite 历史并发迁移、配置修订冲突、处理独立于通知、PID 复用、配置撤销和暂停保护均有 Go 测试覆盖。

初次功能验收使用独立配置和状态目录，自动处理与强制结束始终关闭。临时 LaunchAgent、配置、数据库和探针已清理；初次验收没有创建用户默认配置。之后用户已创建默认配置并启用后台。

## 本次 UI 优化验收

- 最终 `make app GO=go` 编译、ad hoc 签名和严格签名验证通过，无编译警告。
- `make check-ui` 通过：秒、分钟、小时，复合时间、小数、微秒和纳秒换算，非法输入与检查间隔下限；编译产生的临时检查程序自动清理。
- 原生设置页显示 `1 分钟`、`5 分钟`、`2 分钟`、`15 秒` 等数字与单位控件。无编辑时没有配置变化；输入 `abc` 显示错误并禁用保存；改为合法数值后可保存。
- 数字 `6` 切换小时后保持 `6 小时`；撤销后恢复原有 `5 分钟`，数值和单位一起恢复。
- 原生界面保存等待时间 `6 分钟` 后，TOML 回读为 `6m`；随后从界面恢复 `5 分钟` 并回读确认。其他检测时间、自动处理与强制结束选项没有因本次验收被启用。
- 原生界面停止、启动既有 Go LaunchAgent，界面分别显示“后台未运行”“后台运行中”；CLI watcher 锁与 `launchctl` PID 回读一致。启动仅在确认 watcher 已运行后提示成功。
- 权限读取独立执行，状态刷新不再等待通知权限读取返回；运行状态和最近检查时间正常刷新。
- 规则总开关卡片为全宽；通知开关和测试按钮显示正常，重复说明已精简；历史日志路径左对齐，事件中的暂停时间使用本地易读格式。
- 设置保存栏固定在底部，切换页面从顶部显示。本次没有主动申请系统通知权限或发送通知；用户手动启用的系统通知配置与权限保留。
- 菜单中的状态、规则、通知、历史、设置和应用行共用关闭菜单窗口再打开管理窗口的路径；捕获的是菜单自身的窗口。实际菜单入口的完整点击、收起及再次展开验证尚未完成，当前自动化工具未能稳定定位菜单栏图标，管理窗口不可见时工具无法继续读取窗口。

## 本轮交互与图标验收

- 最终应用构建、严格签名校验、Go 全套竞态测试、`go vet`、独立 CLI 构建与 `make check-ui` 均通过。
- 所有页面的滚动条隐藏；历史页仍能滚动。菜单整行悬停呈蓝色高亮；暂停按钮呈黄色图标，通知渠道启用时显示蓝色图标。
- 状态页刷新后更新真实采样并显示“状态已更新”；运行中的刷新控件在辅助功能树中显示“正在刷新”的 busy indicator。菜单、状态、历史共用加载控件，菜单最近检查时间精确到秒。
- 日志与数据的展开区在标题右侧空白区域点击后也能展开，辅助功能值由“已折叠”变为“已展开”。系统诊断、通知与处理、配置文件使用同一展开组件。
- 页面切换、展开内容、悬停和通知图标状态使用短动画；代码读取系统 Reduce Motion 设置以停用过渡动画。
- 应用内置图标通过构建脚本生成，并声明 `CFBundleIconFile`。最终在系统“登录项”中显示 `SleepGuard.app` 和蓝色应用图标，系统“通知”设置也显示同一图标。构建脚本更新应用根目录时间，以使 Icon Services 刷新缓存。
- 原生后台通过 `SMAppService` 注册 `io.sleepguard.app.agent`，`launchctl` 回读 `parent bundle identifier = io.sleepguard.app`；实际进程通过 `execv` 运行内置 Go。旧 CLI 服务迁移后默认配置与数据库保留。
- 菜单退出和 `⌘Q` 共用二次确认。取消后应用与 watcher 保持运行；确认“退出并停止后台”后原生应用退出，两个服务标识均不在 `launchctl` 中，CLI 回读 `watcher_running=false`、`service_installed=false`。
- 最终重新打开应用并从界面启动后台，显示“后台运行中”；CLI 回读 `watcher_running=true`、`service_installed=true`，`launchctl` 显示新服务运行。用户的系统通知授权、默认规则及配置保留。
- 本轮未安装依赖、未发送 Telegram 消息、未启用新的自动处理规则；没有提交或推送仓库。

## 未执行

- 自动化未捕获真实 macOS 通知横幅；通知设置中的应用图标已验证。真实 Telegram 投递尚未执行，需要填写 Telegram 凭据后点击对应测试按钮。
- 结束真实应用、SIGKILL、跨夜休眠及重登录后的运行验证。信号发送和保护逻辑使用模拟进程、信号与采样测试。
- macOS 13–26、Intel Mac、Developer ID 签名和公证分发验证。

## 0.3.0 — native feature and packaging checks (2026-10-10)

Executed on Apple Silicon, macOS 27.0.1, Go 1.27.0 and Swift 6.4:

- Native SwiftUI app and bundled Go executable compile for macOS 13+.
- `go test -race ./...`, `go vet ./...` pass after control changes.
- Duration parsing/control checks pass.
- Real Carbon hotkey registration checks pass: system-reserved combination,
  duplicate binding, occupied registration and preservation of the old binding.
  Temporary test hotkeys are unregistered; user preferences are not changed.
- The app creates one disposable Keychain item, launches three independent
  native readers with interaction disabled, and removes the test item. All three
  reads succeed. The same diagnostic also passes from the mounted DMG app.
  No real Telegram credential is read or overwritten by this diagnostic.
- The compressed DMG passes `hdiutil verify`. Its visible root contains only
  `SleepGuard.app` and an `Applications -> /Applications` symlink. The app's
  nested and outer signatures verify. The deterministic Finder layout contains
  both icon positions and icon-view/window settings.

The signed app is ad-hoc signed. No Developer ID or Apple notarization has been
performed. Passing the disposable-item diagnostic does not prove an existing
item from an older signing identity is already authorized; the next explicit
channel test may require the native macOS Always Allow flow once.

Pending interactive acceptance: current-version native window layout, all-screen
blackout and input restoration, hot-plug display behavior, actual lock/unlock,
GUI application's graceful quit/save prompts, and installing/reopening via a
Finder drag to Applications. Browser/native UI control was unavailable during
this run, so these are not marked verified. Real Telegram delivery and older
macOS versions remain unverified.

Additional native process acceptance: a disposable, project-built IOPM assertion holder was started twice. A stale start-time request was rejected while it remained running; the valid normal request ended it with SIGTERM, and the valid force request ended a second fixture with SIGKILL. All four request/result events were read back from an isolated database. No user application was signalled. Zombie status is handled as exited after signal delivery, rather than reported as a timeout. The system lock symbol resolves on macOS 27; the lock action itself was not invoked.

## 刷新卡住修复与原型差异补齐（2026-10-10）

- 现场进程采样显示 Swift 后台线程卡在 `NSConcreteTask.waitUntilExit`；此时没有仍在运行的 Go 子进程。独立 CLI 的状态、配置、历史查询都在 0.1 秒内完成。问题来自 async 任务恢复到不同线程后等待 NSTask 的退出通知。
- 后台命令移除 `waitUntilExit`，改为有截止时间的异步退出检查；取消会结束本次子进程，忽略 SIGTERM 的子进程也不会让超时清理永久等待。状态查询最多等待 12 秒后恢复刷新按钮；错误显示在页内，保留上次成功读取的状态。
- `make check-ui` 通过。新增检查连续启动 40 次命令、512 KiB 输入输出、命令失败、忽略 SIGTERM 的超时、取消后的子进程清理，以及失败后的再次成功查询。快捷键检查覆盖功能键、重复组合、系统保留组合和被占用时保留旧组合。
- 重启前确认没有运行中的 watcher。新版本实际点击状态页刷新后显示“状态已更新”，时间更新到秒，刷新按钮恢复可点击；后台定期刷新也持续更新时间。没有修改用户的规则、时间配置或自动处理选项。
- 快捷键与原型一致，直接在行内录入。界面录入 `⌃⌥⇧F19` 成功；录入锁屏快捷键时再次按该组合显示重复错误，未触发黑屏；Esc 取消。测试组合随后清除，三个快捷键均恢复未设置。
- 新增规则默认打开搜索列表并聚焦搜索框。分类与搜索固定在顶部；输入 Windows、按方向键再回车后选择 Windows App，列表收起并显示其 Bundle ID。Esc 先收起列表，再取消对话框；规则页仍显示“未修改”。目录扫描包括 Applications 内的子目录，并跳过 app 包内的辅助程序。
- 设置页显示实际连接的内置 Retina 显示器和 2490W1。点击黑屏后捕获到纯黑遮罩，按 Esc 直接恢复管理窗口，无需解锁。CLI 回读确认黑屏相关 IOPM assertion 为 0，历史记录包含 `blackout_started` 与 `blackout_ended`。未逐屏单独采集像素，也未执行热插拔验收。
- 历史页滚动到底部后，点击“日志与数据”标题右侧的空白区域可展开；没有滚动条。正常结束 Windows App 的确认显示 Bundle ID、PID 与退出说明，点击取消后该应用仍在运行，没有发送信号。
- 菜单快捷操作使用两行标题与说明；过高的菜单可滚动且隐藏滚动条。状态页将受保护的系统请求放在诊断展开区，保留应用卡片的手动操作和调整规则入口。菜单整条导航的关闭逻辑仍共用 `MenuPresentation.dismiss`。

本轮原生窗口控制恢复，但系统菜单栏清单查询仍超时，菜单图标无法稳定定位。因此完整菜单展开、各入口关闭与再次展开尚未重新实测。实际锁屏、真实 GUI 应用退出保存提示、显示器热插拔、Finder 拖拽安装、Telegram 真实发送、Intel 与旧版 macOS 仍按未验证记录。

## 0.3.2 — GitHub 发布验证（2026-10-10）

- 最终本机应用为 0.3.2、build 10。退出确认后重新打开，点击刷新显示“状态已更新”，时间更新到秒，按钮恢复可用；未出现钥匙串授权弹窗。后台仍按本轮开始时的状态保持关闭，用户的规则与通知配置没有改变。
- 修复 macOS 15 SDK 的 Swift 6 并发兼容问题：`SMAppService` 在主 actor 调用回调版本的注销方法，通知权限只跨 actor 传递状态值；没有关闭并发检查或添加不安全的 Sendable 声明。
- [main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38044853965) 的 `macos-15` / arm64 与 `macos-15-intel` / x86_64 均通过 Go race、Go vet、Swift 时间与快捷键、后台命令检查，完成应用签名验证、DMG 校验和产物上传。
- 两个 main 构建安装包已下载核对 SHA-256 sidecar，挂载后验证 `.app` 与 `/Applications` 链接。外层与嵌套签名通过；Swift 与 Go 可执行文件的架构分别为 arm64 / x86_64，版本均为 0.3.2、build 5。临时下载和挂载已清理。
- [v0.3.2 发布构建](https://github.com/bennie-asi/sleepguard/actions/runs/38045200525) 的两种架构构建与 release job 均成功。[正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.3.2) 已公开，含两个 DMG 与各自 SHA-256 文件；四个资产回读为 uploaded。
- 源码、MIT License、README 与手动触发 `Build DMG` 的 Actions 工作流已发布到 [bennie-asi/sleepguard](https://github.com/bennie-asi/sleepguard)。发布标签对应 `eb2a15046f6489cef3084a4532b6ce33ef43dbe9`。

CI 已覆盖 macOS 15 上的 Apple Silicon 与 Intel 构建及上述检查，尚未执行 Intel 原生窗口与 macOS 13–14 的交互验收。Developer ID、公证和真实 Telegram 投递仍未配置或执行；临时签名更新后的旧钥匙串条目可能仍需一次原生授权。菜单栏完整点击验收、逐屏像素与热插拔、真实锁屏和 Finder 拖拽安装保持前述未验证范围。
