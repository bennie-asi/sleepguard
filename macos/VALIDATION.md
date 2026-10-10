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

当前公开包采用 ad-hoc 应用签名，未做 Apple 公证。以上结果覆盖构建、菜单组件及发布资产，不代表真实 `0.4.1 → N+1` 升级、自动安装撤销、失败恢复或 watcher 跨版本恢复已经通过；这些交互仍待验收。

## 0.4.2 自动安装修复（2026-10-10）

- 用户现场的 GUI PID `64423` 与 Go watcher PID `64442` 从 `dist/SleepGuard.app` 启动后，其文件被本机构建替换。两者 `proc_pidpath` 均返回 `ENOENT`；系统日志出现 `pidpathfailed 2`、`AuthorizationCreate -60008` 和 installer 启动失败。更新包下载 HTTP 200 成功，磁盘上的新包严格签名检查通过，问题在运行中旧进程的身份。
- 增加构建保护：编译前和最终替换前检查目标包内的运行进程，失去文件身份的进程也不会漏掉；独立临时进程测试覆盖正常运行、其他包、文件被删除及进程退出。`APP_OUTPUT` 支持独立构建目录。
- 更新前检测当前可执行文件的身份，必要时保存后台状态、等待重启 helper 就绪、退出旧进程，再从当前包启动并继续 Sparkle 更新。失败提示区分下载、验证和安装，并保留底层错误。
- 真实 Sparkle 原生测试使用生产更新控制器、独立测试 App、loopback 清单与安装包。签名私钥仅在内存中，后台为项目自有临时进程；没有访问用户配置、钥匙串或 Go 服务。
- 正常更新：旧 GUI `74175` 退出，新 GUI `74195` 启动为 build `4002`，临时后台恢复运行。运行文件被替换：`74232 → 74246 → 74253`，自动重新进入 build `4001` 后继续安装 build `4002`，临时后台恢复运行。后台原本停止：`74339 → 74351`，更新后仍停止。
- 修改签名后的安装包在退出前被拒绝：旧 GUI `75506` 保持存活，未进入后台停止/安装准备阶段，提示“验证更新失败”。本轮修复了 Sparkle 安装错误包装底层验证错误时的阶段识别。
- `make check-ui`、Go race/vet、arm64 编译、严格包检查、DMG 创建与镜像校验通过。
- 对已经失效且尚未包含新逻辑的本机旧版执行一次维护恢复：仅匹配同用户、同 Bundle ID、同旧路径、相同启动时间且 `proc_pidpath=ENOENT` 的进程；先停止后台，再发送 SIGTERM，启动严格签名验证通过的公开 `0.4.1`。应用现位于 `/Applications/SleepGuard.app`，GUI `75627` 和 Go watcher `75646` 的文件身份有效；旧进程 `64423` / `64442` 已退出。原生状态页显示“监控运行中”，配置 SHA-256 与暂停时间保持一致。

这些原生集成用例验证安装与重启机制；临时后台不能代替公开版本之间真实 Go watcher 恢复的结论。`0.4.2` 公开发布后的实际 `0.4.1 → 0.4.2` 更新仍待本轮最终验收。Developer ID、公证、Intel 原生交互、自动退出安装及其取消仍未验收。
