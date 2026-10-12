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

## 0.3.3 — 后台启动与暂停恢复（2026-10-10）

- 点击启动后，旧版服务虽已注册，`launchctl` 回读 `OS_REASON_CODESIGNING`、`spawn failed`；系统日志确认 `Launch Constraint Violation`，Go watcher 锁未持有，运行日志未更新。应用与内置 Go 的严格签名校验仍通过。
- 独立测试的临时签名 SMAppService agent 首次可启动；更换 helper 签名后再次注册被相同约束拒绝。因此默认临时签名构建使用既有、关联 `io.sleepguard.app` 的 LaunchAgent；Developer ID 构建保留 SMAppService，并使用独立签名的 `SleepGuardMonitor`。没有重置系统全部后台记录或改动系统安全设置。
- 构建在新的目录完成编译、逐项签名和校验后才替换 `.app`；构建失败保留旧包。嵌套 monitor 入口在私有临时目录调用内置 Go 的配置查询成功，未写入默认配置或接触凭据。
- 最终修复版原生状态页点击“启动后台”成功；`launchctl` 确认服务运行及 PID，CLI 回读 `watcher_running=true`。运行日志新增真实采样。
- 原生状态页和菜单共用运行、暂停、未启动状态。暂停 30 分钟后立即显示黄色暂停图标、恢复时间、“立即恢复”，暂停按钮消失；点击恢复后显示绿色运行状态，只保留暂停操作。
- 暂停记录保留而后台停止时，页面仍显示暂停及“后台未运行，可恢复并启动”；点击“恢复并启动”后进程与提醒、处理一起恢复，暂停时间回读清空。
- 实测普通 LaunchAgent 使用兼容标识时，SMAppService.status 也可能返回启用，但直接注销报 `Requestor lacks required entitlement`。修复为仅注销实际由 ServiceManagement 托管的任务；修复版设置页“停止后台”成功，CLI 回读 `watcher_running=false`、`service_installed=false`。
- 菜单“查看完整状态”实测关闭菜单并打开管理窗口。菜单暂停显示及管理页恢复按钮均完成交互验收；本轮没有逐项重测其他导航入口。
- `make check-ui` 通过，新增暂停优先级、后台关闭时恢复、暂停到期检查；原有后台命令、时间与快捷键检查仍通过。Go race 与 vet 通过。

- [main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38047868908) 的 macOS 15 / arm64 和 macOS 15 Intel / x86_64 均通过测试、Swift 编译、包内后台入口检查、严格签名验证及 DMG 打包。对应提交为 `320341abf06caf0b83938e9e947d32329f2ff416`。
- 本机最终 0.3.3、build 13 的 DMG 挂载后确认 Applications 链接、包内版本、完整签名和 monitor → Go 配置查询；已卸载测试镜像。最终包再次启动成功，确认退出时两个 watcher/service 标志均回读为 false；测试暂停已清除。
- [v0.3.3 发布构建](https://github.com/bennie-asi/sleepguard/actions/runs/38048270462) 的 Apple Silicon、Intel 与 release job 均成功。[正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.3.3) 公开，含两个 DMG 与对应 SHA-256 文件，四个资产状态均回读为 uploaded。

本轮未验证 Developer ID 下的实际服务注册、Intel 原生交互、重新登录和跨夜休眠；没有结束用户应用或发送 Telegram 消息。

## 0.4.1 菜单高度与发布修复

- 菜单布局向内容提出有上限的高度，短内容自然收缩，长内容选择隐藏滚动条的滚动区域。上限为 640 点，且不超过当前显示器可用高度减 16 点；显示器变化时重新计算。
- 使用实际 `MenuPanel` 编译临时原生验收窗口：短内容无滚动区域；加入 40 行临时文字后出现滚动区域，实际滚动到末尾；清除临时文字后窗口恢复短内容高度。临时窗口没有启动后台、更新器或读取用户配置。该结果验证菜单组件；本轮自动化未能定位运行中的 SleepGuard 菜单窗口，实际菜单栏入口和多显示器切换仍需验收。
- 本机 `make check-ui`、Go race/vet、arm64 App 编译、严格包检查和工作流 YAML 解析通过。`v0.4.0` 的双架构 main 构建通过；标签发布被新增的 Apple 证书必填检查阻止。已改为 Apple 凭据可选、缺少 Sparkle Secret 时生成待签署清单的草稿。
- `v0.4.0` 标签保留不移动；新的菜单及发布修复使用 `v0.4.1`。提交 `63a7aeead69bd99fd150d7452a3cbac0917d49d4` 的 [main 验证](https://github.com/bennie-asi/sleepguard/actions/runs/38054300957) 和 [标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38054674149) 均成功，Apple Silicon 与 Intel 均完成测试、应用构建、严格签名检查及 DMG 打包。
- [v0.4.1 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.1) 已公开并成为最新正式版本。API 回读六份上传资产全部为 `uploaded`；版本为 `0.4.1`、build `4001`。公开下载的两份 DMG 与标签 CI 安装包逐字节一致，SHA-256 sidecar 和 GitHub digest 均匹配。
- 使用本机 Keychain 签署同一批 CI DMG 的两个 appcast，用户完成签名工具的系统授权。公开下载和 latest 入口返回的 XML 与签署原件一致；使用应用内置公钥独立验证清单和安装包 Ed25519 签名，两种架构均通过。私钥没有导出、写入仓库或日志。

该次 `0.4.1` 发布采用 ad-hoc 应用签名，未做 Apple 公证。当时的结果覆盖构建、菜单组件及发布资产，真实跨版本升级和 Go watcher 恢复的后续验收见下方 `0.4.2` 记录。

## 0.4.2 自动安装修复（2026-10-10）

- 用户现场的 GUI PID `64423` 与 Go watcher PID `64442` 从 `dist/SleepGuard.app` 启动后，其文件被本机构建替换。两者 `proc_pidpath` 均返回 `ENOENT`；系统日志出现 `pidpathfailed 2`、`AuthorizationCreate -60008` 和 installer 启动失败。更新包下载 HTTP 200 成功，磁盘上的新包严格签名检查通过，问题在运行中旧进程的身份。
- 增加构建保护：编译前和最终替换前检查目标包内的运行进程，失去文件身份的进程也不会漏掉；独立临时进程测试覆盖正常运行、其他包、文件被删除及进程退出。`APP_OUTPUT` 支持独立构建目录。
- 更新前检测当前可执行文件的身份，必要时保存后台状态、等待重启 helper 就绪、退出旧进程，再从当前包启动并继续 Sparkle 更新。失败提示区分下载、验证和安装，并保留底层错误。
- 真实 Sparkle 原生测试使用生产更新控制器、独立测试 App、loopback 清单与安装包。签名私钥仅在内存中，后台为项目自有临时进程；没有访问用户配置、钥匙串或 Go 服务。
- 正常更新：旧 GUI `74175` 退出，新 GUI `74195` 启动为 build `4002`，临时后台恢复运行。运行文件被替换：`74232 → 74246 → 74253`，自动重新进入 build `4001` 后继续安装 build `4002`，临时后台恢复运行。后台原本停止：`74339 → 74351`，更新后仍停止。
- 修改签名后的安装包在退出前被拒绝：旧 GUI `75506` 保持存活，未进入后台停止/安装准备阶段，提示“验证更新失败”。本轮修复了 Sparkle 安装错误包装底层验证错误时的阶段识别。
- `make check-ui`、Go race/vet、arm64 编译、严格包检查、DMG 创建与镜像校验通过。
- 对已经失效且尚未包含新逻辑的本机旧版执行一次维护恢复：仅匹配同用户、同 Bundle ID、同旧路径、相同启动时间且 `proc_pidpath=ENOENT` 的进程；先停止后台，再发送 SIGTERM，启动严格签名验证通过的公开 `0.4.1`。应用现位于 `/Applications/SleepGuard.app`，GUI `75627` 和 Go watcher `75646` 的文件身份有效；旧进程 `64423` / `64442` 已退出。原生状态页显示“监控运行中”，配置 SHA-256 与暂停时间保持一致。

这些原生集成用例验证安装与重启机制；实际公开版本之间的 Go watcher 恢复另外验收如下。Developer ID、公证、Intel 原生交互、退出时自动安装及其取消仍未验收。

## 0.4.2 正式发布与本机跨版本升级（2026-10-10）

- 发布源提交 `4d31f60afe8fee9ce4f5c28d075e6817484652c1`；[main 构建](https://github.com/bennie-asi/sleepguard/actions/runs/38058923364) 与 [标签发布](https://github.com/bennie-asi/sleepguard/actions/runs/38059258230) 完成且均为 `success`。arm64 / x86_64 的应用、Go 后台架构、版本 `0.4.2` / build `4002`、严格签名、固定更新公钥和 DMG 的 Applications 链接均检查通过。
- [v0.4.2 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.2) 于 22:45（Asia/Shanghai）公开且为 latest。网页和 API 均回读正式发布，六份资产为 `uploaded`；公开下载与标签 CI 包、签署原件逐字节一致，SHA-256 sidecar 和 GitHub digest 均匹配。
- 用户分别完成两次签名工具的 Keychain 系统授权；没有导出私钥。两个 latest appcast 与签署原件相同；使用内置公钥独立验证 XML 和 DMG 的 Ed25519 签名，两种架构均通过。
- 本机原先运行公开 `0.4.1` / build `4001`，GUI `75627`、Go watcher `75646`。22:49 在应用内点击“立即更新”，界面进入“正在下载更新”；22:50 自动安装后 GUI `78527` 与真实 Go watcher `78547` 从 `/Applications/SleepGuard.app` 启动，旧进程均已退出。升级期间没有手工复制 `0.4.2` 包或启动新 GUI。
- 新版状态页实际显示“已更新到 0.4.2，后台已按原状态恢复。”及“监控运行中”；点击刷新后显示“状态已更新”，检查时间到 `22:51:07`。版本页显示 `SleepGuard 0.4.2`、build `4002`，更新器恢复可检查状态。
- 升级后 GUI 与 watcher 的 `proc_pidpath` 均有效；安装后的严格签名检查通过，CLI 回读 `SleepGuard 0.4.2 (4002)`。配置 SHA-256、暂停时间、watcher 运行状态和服务安装状态与升级前一致；原有 43 条 SQLite 事件按相同序列化方式逐条哈希回读一致。

已完成 Apple Silicon 本机真实 `0.4.1 → 0.4.2` 下载、校验、安装、退出旧进程、自动重启及 Go watcher 状态恢复。Intel 的结果覆盖 CI 打包与签名校验，尚未在 Intel 硬件上运行升级；当前包仍为 ad-hoc 签名，未做 Apple 公证。


## 登录启动与后台注销修复（2026-10-11，工作区修复构建）

以下保留第一轮修复的验收记录；其中会话级 LaunchAgent 和真实临时登录项测试已由下一节的单应用实现及 fake 测试替换。

### 原因与行为

- 09:33 系统日志确认旧 `io.sleepguard.agent` 原生后台注册在登录时启动主可执行文件，被 AMFI 以 ad-hoc 签名启动约束拒绝。09:35 崩溃栈落在 `BackgroundAgent.stop()` 的注销完成回调；系统在默认后台队列调用继承了 MainActor 的闭包，触发 Swift executor 断言。
- 完成回调改为显式 nonisolated / Sendable。设置页新增“登录时自动启动”，直接使用 `SMAppService.mainApp` 并回读系统状态，显示等待授权和错误；开关即时生效。
- GUI 监控通过 `service start --session-only` 加载临时 LaunchAgent，不留永久后台自启文件。关闭登录开关不停止当前监控；退出停止监控但保留登录项。CLI 默认 install/start 仍保持持久服务语义。
- 启动时迁移旧后台注册，保留监控原运行/停止状态；以设置中的主应用登录项为下次登录启动依据，不从旧隐式后台注册自动开启新开关。登录 Apple Event 在应用完成启动回调中同步捕获，只由菜单入口启动模型；管理窗口不再抢先用默认参数启动。

### 已验证

- `make test check check-ui GO=/Users/bennieliu/sdk/go1.27.0/bin/go` 通过。覆盖后台线程成功/失败注销回调、原始错误传递和 MainActor 恢复；Go 隔离测试覆盖会话服务迁移、临时文件清理、加载失败和 CLI 默认持久化。
- 独立 `APP_OUTPUT` 应用编译、`scripts/check-package.py` 和严格签名校验通过。
- `scripts/check-login-item.py` 使用唯一临时 bundle ID 和生产控制器完成启用、独立进程回读、重复设置、重新 ad-hoc 签名、关闭及再次回读；退出后注销并删除临时应用。
- `scripts/check-login-startup.py` 使用生产 GuardModel 和独立 mock CLI，9 个场景通过：普通打开、登录项关闭、登录启用、已有监控避免重复、有效更新保持停止、过期/损坏更新标记、关闭登录项保持监控、退出保留登录项。其后台操作是隔离 mock，不能当作真实后台启动证明。
- 另用真实 Go 后台和独立配置完成会话级启停：watcher_running/service_installed 回读符合预期，未生成用户 LaunchAgents 永久 plist；用户配置与 SQLite 文件哈希保持一致。
- 本机 `/Applications/SleepGuard.app` 在独立配置（通知与自动动作关闭）下，经原生设置页连续两轮“启动后台 → 停止后台”，均成功且无崩溃；退出确认正常结束应用。该操作包含实际 BackgroundAgent 与 Go 服务完整调用链。
- 最终修复构建已替换到 `/Applications/SleepGuard.app`，从用户原配置正常打开并显示新设置；登录项开关与后台均保持关闭。用户配置与 SQLite 文件哈希回读一致；本次测试副本和临时数据已删除，LaunchServices 注册表仅剩这一个 SleepGuard 应用；这一检查没有覆盖 BTM 后台活动记录，遗漏见下方纠正。版本号仍为工作区 `0.4.2`，不代表同版本公开安装包已经更新。

### 验收边界

尚未执行真实注销登录或重启；已验证登录项注册、登录事件识别和启动路径，但不能将其写作真实开机验收通过。没有修改公开 Release、标签或安装包；代码尚未提交或发布。


## 单应用后台收敛与测试记录纠正（2026-10-11）

### 已确认的问题

- 上一轮真实登录项测试留下了 `LoginAudit`、`LoginCheck`、`LoginStartupCheck` 三条 BTM 记录。它们虽然已经注销且测试文件已删除，系统“后台 App 活动”仍显示为允许。这些是测试污染，不是三个仍运行的后台。此前“测试项清理完成”的说法没有覆盖此系统界面，现予纠正。
- 已在系统设置将三条测试项全部关闭，并回读开关为 off。macOS 公开接口没有提供按 bundle ID 删除 BTM 历史的方法；不能将停用写作历史记录已删除。没有全量重置 BTM 或改动其他应用的登录设置。

### 当前实现

- SleepGuard 主应用直接管理内置 Go `watch --exit-on-stdin-close` 子进程，不再通过临时或持久 LaunchAgent 启动 GUI 监控。唯一新注册入口是设置开关控制的 `SMAppService.mainApp`；旧 agent 代码只负责迁移清理。
- 主应用保留 stdin 管道写端，退出时关闭；意外崩溃也由系统关闭该描述符，Go watcher 取消 context 并释放进程锁和数据库。关闭管理窗口不退出主应用，因此继续监控；异常子进程退出按原 30 秒间隔重启。
- 移除上一轮新增的 `service start --session-only` 路径，独立 CLI 原服务语义不变。
- 登录项测试改用构造注入的 fake 系统服务，不再创建临时 UUID 登录注册；mock 验证与真实系统登记严格区分。

### 已验证

- `make test check check-ui`、独立目录 `make app`、`scripts/check-package.py` 和安装后的严格签名校验通过。Go 测试覆盖 stdin EOF 中断采集/长间隔、释放锁、保留配置和历史，以及默认 CLI 不读取 stdin。
- `scripts/check-app-monitor.py` 使用无 App bundle 的私有父子进程，验证启动幂等、停止/重启、异常重试、等待重试时停止、正常退出清除监控请求，以及父进程 SIGKILL 后子进程收到 EOF 并退出。常规检查不访问 BTM；本机显式比对的 63 个 BTM Identifier 前后相同，没有新增记录。
- 更新准备改为始终取消监控和重试任务，恢复标记包含等待重试中的监控请求。生产 GuardModel 的独立 mock 检查共 11 个场景通过，包括更新前后台已停/运行中及失败恢复；这些不能作为真实重新登录的证据。
- 安装到 `/Applications/SleepGuard.app` 后，使用通知与自动动作关闭的独立配置，从原生设置页启动真实 Go 监控：GUI `17603` 直接持有子进程 `17660`；`watcher_running=true`、`service_installed=false`。`io.sleepguard.agent` / `io.sleepguard.app.agent` 均未加载，也没有旧 LaunchAgents plist。
- 关闭管理窗口后监控继续运行；重新打开后可停止、再次启动，并在退出确认后结束 GUI 和子进程、释放 watcher 锁。安装后完整启停/退出前后的 BTM 标识字段集合相同，新增 0 条。
- 已恢复使用用户原配置，后台和登录启动开关保留关闭状态；配置与 SQLite 文件 SHA-256 前后一致。系统设置回读 `LoginAudit`、`LoginCheck`、`LoginStartupCheck` 都是 off，历史名称仍显示，不能声称已从 BTM 历史删除。
- 本次安装备份、测试 App 副本和隔离数据均已删除；另清理了 11 条指向已不存在升级测试 App/Updater 的 LaunchServices 登记。回读仅剩 `/Applications/SleepGuard.app` 与其内置 Sparkle Updater，没有开发副本。

本机已安装工作区修复构建，版本仍为 `0.4.2`；公开安装包和标签未改动。尚未执行真实注销登录或重启验收。

## 测试记录清理与操作失误（2026-10-11 10:04）

- 用户要求彻底删除三个测试后台项。调查时误将 `sfltool resetbtm --help` 当作帮助查询；当前系统忽略不支持的 `--help` 后执行了全量重置。系统日志和 v18 数据库文件确认登录项及后台记录均被重置。这不是定向删除，属于操作失误，已向用户说明。
- 已通过系统设置恢复重置前的五个“登录时打开”应用：CC Switch、OneClip、PixPin、Scroll Reverser、uTools，并回读确认。未能确认其他后台权限已完整恢复；用户说明正在自行调整登录项后，停止了对登录项和后台开关的写操作。不能声称此次清理没有影响其他应用的设置。
- 只读检查全部当前 `BackgroundItems-v18*.btm`：三个测试 bundle ID / 名称均为零条。另注销了两条指向已删除 `LoginStartupCheck.app` 的 LaunchServices 缓存，回读三种测试 App 路径均不存在。
- `check-login-startup.py` 增加退出清理：在删除临时 App 前按准确路径注销 LaunchServices，包括测试失败路径；仍使用 fake 登录服务，不注册真实登录项。
- 后续恢复尚未完成：已保存重置前 26 组正常后台项的开关状态、当前数据库副本和 18 份服务配置的只读清单到本机忽略目录 `work/btm-recovery.noindex/`；其中 15 个服务仍已加载。`check-background.py` 用于只读核对记录和开关，不能自动覆盖用户随后调整的状态。用户选择保存工作后自行重启，待重启后继续逐项核对和恢复后台登记，不能将五个登录应用恢复视为整组后台权限恢复。

## 重启后的恢复核对（2026-10-11）

- 系统启动时间为 `10:12:14`。18 份原有 LaunchAgents / LaunchDaemons 文件的 SHA-256 全部与重启前一致；原先加载的 15 个服务均重新加载，MySQL、Redis、Clash、iStat 和 UU 远程等原运行服务仍为 running。三个原来未加载的 Google 服务仍未加载。
- 首次完成重启核对时，26 组基线中已有 23 组重新出现在 BTM：22 组开关与原来一致，Apifox 按用户本轮明确选择保留关闭。库乐队、GoogleUpdater、WPS 曾以开启状态重新出现，已按用户确认逐项恢复关闭，并通过系统设置和 BTM 双重回读。
- DataGrip、iTerm、Visual Studio Code 的历史后台活动记录尚未重新出现，不能称整组恢复完成。重新打开应用不保证立即重建历史后台记录；未将这些应用添加为登录启动项。iTerm 的原生控制被工具安全限制拒绝，需要用户自行打开；DataGrip 的退出确认界面保留给用户处理。
- 三个测试项的名称及标识未重新出现。SleepGuard 仅有主应用 `2.io.sleepguard.app` 一项，两个旧 LaunchAgent 均未加载；GUI `5468` 直接管理 Go 子进程 `5523`。用户重新启用了主应用登录项；日志显示登记发生于本次登录之后的 `10:13:38`，因此此次重启不能作为该登录开关已自动启动成功的证据。
- 本次状态和服务清单保存于本机忽略目录 `work/btm-recovery.noindex/after-reboot-comparison.json`、`after-reboot-service-inventory.json`，保留用于后续补全。未运行任何全量 BTM 重置；登录测试清理脚本的 Python 语法检查通过，未再次运行会启动测试 App 的验收。
- 用户指出核对时主动打开 Apifox 和 DataGrip 打断了使用；已说明还打开过 VS Code，并停止主动启动其他应用。后续只读确认 DataGrip、iTerm、VS Code 都未运行，应用文件仍存在，包内及系统/用户启动目录均没有归属于它们的独立 LaunchAgent、LaunchDaemon 或 LoginItem；缺失的三条历史记录仍待应用实际后台活动重新登记，其中 DataGrip 原为禁止后台运行，另外两项原为允许。
- 后续发现两条更早的 LaunchServices 测试缓存，分别指向已不存在的 `work/menu-sizing-probe/MenuSizingProbe.app` 与 `work/agent-probe/Probe.app`；确认没有相关进程后按准确路径注销，回读均已消失。聚焦仅返回 `/Applications/SleepGuard.app`，相关主应用登记只剩正式 SleepGuard。
- 最新系统设置回读：UU 远程后台已关闭，两个 UU 服务均未加载；SleepGuard 已从“登录时打开”列表移除，当前监控仍在运行。保留这些随后变化，不覆盖为早先状态。18 份启动配置文件仍全部一致，当前加载 13 项。最新差异及服务状态分别写入 `after-reboot-comparison.json` 和 `latest-service-inventory.json`；不能以首次核对的 15 项服务或 SleepGuard 登录启用状态代表当前设置。


## 监控可靠性四项修复（2026-10-11，工作区未发布）

- 在已有 AppMonitor 子进程与登录启动改动上修复，不替换既有修改。桌面端继续直接管理 Go 子进程；该阶段暂时保留旧 LaunchAgent 清理和独立 CLI service 入口，后续按用户要求删除，见下节。该阶段未注册、卸载或修改本机登录项、LaunchAgent 和现有监控状态。
- 自动处理在耗时复采集之后检查当前规则、暂停和控制版本，并在最终发信号阶段与暂停、恢复、黑屏开始/结束共用 `control.lock`。新增回归分别覆盖 SIGTERM / SIGKILL 复采集期间的四类控制操作、配置撤销、上下文取消；信号均为 mock。跨 Store 句柄检查互斥、锁等待取消和已确认暂停的可见性。
- 复核失败不再提前记录 ActionAttempted；未发送信号的事件在至少一分钟或两个采样间隔后重试，等待期间仍可通知。测试覆盖持久化重试期限、新 Runner 接管、后续成功及已尝试 SIGTERM 后的失败不重复发信号。
- 规则/设置保存将最新页面字段与编辑起点比较，再通过原有 revision 检查保存。Swift 检查覆盖外部新增规则、总开关修改、四类设置冲突、跨页面变更保留、显式重新加载后的保存。冲突保留草稿，撤销使用最近读到的持久化配置；保存期间的过时状态刷新被丢弃。
- Go watcher 独立写入启动、尝试、成功与错误记录；UI 实时采集不更新这些时间。首轮超过 30 秒无完成、后续超过 max(30 秒, 3 个采样间隔) 无完成时标记超时。Go 测试覆盖首次卡住、后续卡住、失败记录、重启保留错误和原成功时间但重新等待首次完成、正常退出不覆盖真实错误。
- 真实 Go CLI 隔离验证通过：默认关闭通知和自动操作，以一秒间隔启动项目自有临时子进程；健康后仅 SIGSTOP 此子进程并等待 31 秒。`ui status` 仍返回新的界面快照及 watcher_running=true，但 watcher_health.status=stale，last_success 不变。SIGCONT 后恢复 healthy；关闭 stdin 后正常退出，回读 stopped。临时配置、数据库和进程均已清理，没有发送通知或结束用户应用。
- `make test check check-ui` 通过，使用现有 Go 1.27.0，包含 race、vet、Swift 配置冲突检查及既有子进程生命周期检查。独立 APP_OUTPUT 下的 arm64 `make app`、严格签名与 `scripts/check-package.py` 通过；临时测试包已清理。

本轮未安装到 /Applications，未提交或推送，版本仍为 0.4.2。结果覆盖自动化检查、真实隔离 CLI 和完整 App 构建；没有新增真实 GUI 交互、登录重启或公开跨版本升级验收。


## 移除旧服务与界面同步（2026-10-11，工作区未发布）

- 按用户要求删除旧 LaunchAgent 注册/迁移逻辑、两份 plist、SleepGuardMonitor helper、`--run-monitor`、CLI `service` 命令和 `service_installed` 状态字段，不保留兼容入口。所有桌面启动路径统一调用 AppMonitor，包括指定外部 backend 的隔离测试。
- 菜单、设置页、状态提示、退出确认及更新恢复文案统一使用“监控”；HTML 设计原型同步清理。监控仍可启动/停止，关闭窗口继续运行，退出主应用停止子进程。“登录时自动启动”继续单独管理主应用登录项。
- 本机精确查询 `io.sleepguard.agent` 和 `io.sleepguard.app.agent`：launchctl 均返回未加载，两份用户 LaunchAgents plist 均不存在。确认旧专用设置文件结构后删除 `~/Library/Application Support/sleepguard/agent-settings.json`；未删除现有配置、规则、历史或运行日志。只读 `sfltool dumpbtm` 超时，未据此宣称系统缓存无旧记录，未执行注册表重置或更改任何登录项。
- `make test check check-ui` 通过（现有 Go 1.27.0，race、vet、Swift 检查与子进程生命周期检查）。独立 APP_OUTPUT 的 arm64 `make app`、严格签名及 `check-package.py` 通过；包内没有 LaunchAgents 和 SleepGuardMonitor，CLI 对 `service` 返回 unknown command。
- `check-login-startup.py` 的 11 个场景全部通过：手动启动、登录禁用/启用、已运行去重、更新恢复记录三种状态、关闭登录开关保留监控、退出保留登录设置、更新前停止与失败后恢复。使用生产 GuardModel/GoBackend/AppMonitor、fake 登录注册表和实际通过 stdin 管道启停的私有 mock 子进程；没有调用旧 service 入口，没有注册或删除系统登录项。临时 App 的 LaunchServices 记录按准确路径清理，临时进程与文件已清理。

以上为工作区构建和隔离自动化验证；未覆盖本轮真实界面交互、重新登录或发布升级，未替换 /Applications 中的应用，未提交或推送。


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

## 2026-10-11 日志轮转与菜单高度回归（随后随 v0.4.4 发布）

- `make test check check-ui` 通过：Go race/vet、原生配置草稿冲突、子进程生命周期及既有检查通过。新增日志配置验证覆盖旧 TOML 默认值、保存回读和非法范围；新增字段也参与同页草稿冲突检测。
- `MonitorLogChecks` 在临时目录验证超限分块不丢字节、跨日期归档、动态保留天数/份数、重启追加、0600 权限，以及其他文件和符号链接不被清理。`check-app-monitor.py` 让独立子进程在退出时分别输出 10,000 行 stdout/stderr，连续两次启动后完整回读各 20,000 行；正常停止、异常重试与父进程退出测试均通过。
- `MenuPanelSizeChecks` 使用生产菜单容器与原生 NSHostingView，实际测量依次为 `320×180 → 320×400 → 320×220 → 320×150 → 320×220`，覆盖短内容、900 点长内容受限滚动、恢复短内容、降低并恢复屏幕高度上限。
- 独立原生预览应用使用生产设置页与真实 Go 配置接口，配置和数据库均位于测试目录，登录项使用内存替身。界面将日志保留从 7 天/10 份改为 8 天/9 份，点击“保存并应用”后显示未修改；CLI 回读为 8/9，事件历史仍为 30 天。
- `APP_OUTPUT=.../work/log-rotation/SleepGuard.app make app` 和相同路径的 `scripts/check-package.py` 通过，未覆盖运行中的安装包。11 个独立登录启动/更新准备场景通过。
- 实际菜单栏入口的视觉验收未完成；未将容器测量等同于真实菜单弹窗、多显示器切换或 Intel 验收。本次未修改版本号、推送或发布安装包。

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

## v0.4.8 监控误报、状态提示与发布验收（2026-10-12）

- 用原生回归检查覆盖 `IOPMCopyAssertionsByProcess` 成功码 `0` 且空字典，以及非零错误码。`make test check check-ui`、`make app` 和 `scripts/check-package.py` 通过；构建使用 Go 1.27.0。
- 隔离 Bundle ID、配置和历史的原生预览应用中，注入最近错误后叉号可同时隐藏状态页横幅及停止监控时的详情；刷新和重启后仍隐藏，新时间戳错误重新显示。手动刷新成功提示悬浮在管理窗口右下角，内容未移位；预览应用、注册和测试偏好已清理。
- 发布提交 `d47f34ee3ef96a7257df4d757f48a5e7633c0e3a`；推送标签时 `main` 与 `v0.4.8` 均指向该提交，验收记录随后单独提交到 `main`。[标签流水线](https://github.com/bennie-asi/sleepguard/actions/runs/38204533557) 的 arm64 与 x86_64 测试、构建和包检查通过。首次 Intel 上传制品遇到 GitHub DNS `ENOTFOUND`，仅重跑失败任务后两架构及 release job 均成功。
- CI artifacts `11726194310`（arm64）、`11726454916`（x86_64）下载哈希通过。本机 Keychain 账户 `sleepguard` 对同批 CI 安装包生成更新清单，并用 `sign_update --verify` 验证签名；本机公钥与应用内 `SUPublicEDKey` 一致。[正式 Release](https://github.com/bennie-asi/sleepguard/releases/tag/v0.4.8) 已公开、标记 Latest，六份公开资产哈希与本机签署及校验的文件一致，两份 `/releases/latest/download/` 清单也逐字节一致。
- 正式安装 `/Applications/SleepGuard.app` 目前仍为 0.4.7。应用内检查更新已发现 0.4.8；点击“立即更新”提示必须先结束当前全屏黑屏。未改动黑屏及运行状态，正式安装的跨版本升级、历史保留与新版本实际运行待验收。

| 架构 | 公开 DMG SHA-256 |
| --- | --- |
| arm64 | `91410b4e181e20b573586d5a10a75238c9e6b77db1fb5642544435e32879d853` |
| x86_64 | `1a80a168339c95ac61f8f79f2e67272efc1aa4b154405a8540a25699e5221f35` |

## 2026-10-13 本机启动与退出修复验收

- 环境：Apple Silicon，macOS 27.0.1（26A434），原正式安装 0.4.8 / 4008。
- 原版现场复现：状态页显示“无法确定全局休眠开关”；确认退出后显示“未能退出 SleepGuard / 无法确定全局休眠开关”。进程采样显示主线程处于正常 AppKit 事件循环，没有死锁。
- 系统 `pmset -g` 含全局设置标题而省略 `SleepDisabled`；Apple 开源 `pmset/pmset.m` 的 `show_system_power_settings` 只在字典包含该可选覆盖时输出字段。
- Go 回归覆盖显式 0/1、覆盖未设置、全局字典含其他键、空输出、缺少全局标题、字段缺值和非法值。`make test check check-ui`、`make app`、`python3 scripts/check-package.py` 均通过。
- `python3 scripts/check-login-startup.py` 的 13 个生产 GuardModel 场景全部通过；新增监控停止和运行两种状态下的状态查询失败退出场景。使用私有配置、假登录项适配器和自有临时后台，不修改系统登录项。
- `/Applications/SleepGuard.app` 安装本机修复构建后，原生界面显示当前电源、休眠时间、应用请求；点击“启动监控”显示“监控运行中”及成功采样时间；确认“退出并停止监控”后，GUI 与真实 Go 后台全部退出。最终保持应用关闭。
- 用户配置 SHA-256 不变；原有两条历史及既有 incidents/snoozes/temporary_holds/control_resets 行逐条一致，数据库 quick_check 为 ok。原版已备份；未发布新版本。多显示器、Intel 原生交互及未来正式版本升级未验收。
