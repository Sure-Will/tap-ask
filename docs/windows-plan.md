# TapAsk Windows 版开发方案

写于 2026-11-11，基于 `main` 的 `db11e59`（Mac 0.1.5）。目标是做出与 Mac 0.1.5 功能对齐的 Windows 原生版。

这是一份开发方案。Windows 版已开始覆盖 W1–W5 的功能，当前实现和已知缺口以 `docs/behavior.md` 的 Windows 列为准；外链直接点击自动转交、真实登录、安装升级及系统场景仍需完成和验收，不能将各阶段视为全部通过。

## 已经定下的事

以下是 2026-11-05 的决定，本方案沿用，不重新讨论。

- Windows 用 C# + WinForms + WebView2，与 Mac 各写各的原生实现，放在同一个仓库。
- 两端不共享代码，只共享 `shared/providers.json`、`shared/policy-cases.json` 和 `docs/behavior.md`。
- 默认呼出快捷键是 Alt+空格。隐藏时显示，可见时收起，收起后焦点回到原来的 app。
- 不显示任务栏图标，不出现在 Alt+Tab 里，支持开机自启。
- 在别的虚拟桌面呼出时，窗口出现在当前桌面，不把用户切走。
- 名字写 `TapAsk`，不写全小写连写。
- 两端首次启动、没有上次选择时默认打开 DeepSeek；已有有效选择仍然恢复，服务商排序不变。
- Windows 0.1.6 先发布；Mac 0.1.6 验证后补到同一个 Release，在此之前保留 Mac 0.1.5 的更新清单和安装包。

## 要做什么

一个常驻托盘的 Windows 程序。按 Alt+空格，AI 聊天浮窗出现在所有窗口之上，再按一次收起。功能范围就是 Mac 0.1.5 现有的全部：

- 六家服务商（ChatGPT、Claude、Gemini、DeepSeek、Grok、豆包），切换、自定义排序、记住上次的服务商和对话页面。
- 最多保留当前和最近一家页面，后台页满 300 秒自动释放，可手动释放。
- 导航规则：只在浮窗里打开当前服务商和常见登录页，其余点击交给默认浏览器，脚本跳转取消。
- 登录弹窗、来源提示、导航提示条、加载失败与重试、网页进程崩溃恢复。
- 窗口位置和大小记忆，跨屏适配，自定义呼出快捷键。
- 开机自启、自动更新。

## 不做什么

- 不做 Mac 还没有的功能。下载和麦克风在 Mac 上分别是之后的两步，Windows 先与 Mac 0.1.5 保持一致：下载取消并记日志，麦克风和摄像头拒绝。Mac 做完后 Windows 再跟。
- 不向网页注入脚本。对应到 WebView2，就是不调用 `ExecuteScriptAsync`、`AddScriptToExecuteOnDocumentCreatedAsync`，不用 WebMessage，也不读页面内容判断登录结果。
- 不放宽导航规则，不加后缀匹配，不改 `shared/`。
- 不做代码签名。Windows 会像 Mac 未公证一样在首次运行时提示风险，README 里写清放行方法。
- 不支持 ARM64 和 Windows 10 1809 以前的系统。先只出 x64。
- 不做 MSIX 和应用商店分发。

## 技术选型

| 项目 | 选择 | 理由 |
| --- | --- | --- |
| 运行时 | .NET 10（当前长期支持版），目标 `net10.0-windows` | 长期支持，WinForms 和 WebView2 都有官方支持 |
| 发布形态 | 自包含（self-contained）x64 | 用户不用另装 .NET 运行时，代价是安装包大几十 MB |
| 网页内核 | WebView2 Evergreen 运行时，NuGet 包 `Microsoft.Web.WebView2` | Windows 11 自带；缺失时启动提示并给出微软下载地址，不自动下载 |
| 测试 | xUnit | .NET 的常规选择 |
| 自动更新 | Velopack | 见下文“自动更新” |
| 全局快捷键 | Win32 `RegisterHotKey`，带 `MOD_NOREPEAT` | 不需要键盘钩子；被别的程序占用时注册会失败，可以如实提示 |

Windows 的授权依赖为 `Microsoft.Web.WebView2`、`xunit`（含测试运行器和 SDK，仅测试）、`Velopack`；根目录 `AGENTS.md` 已列明这些例外。

## 目录结构

```
windows/
  TapAsk.sln
  src/
    TapAsk.Core/        纯逻辑，net10.0，不引用 WinForms 和 WebView2
    TapAsk/             WinForms 程序，net10.0-windows
  tests/
    TapAsk.Core.Tests/  xUnit，读取 ../../shared/ 下的两个 JSON
  scripts/
    verify.ps1          构建 + 全部测试 + 发布包，对应 Mac 的 verify.sh
    build-app.ps1       生成发布目录
```

与 Mac 的分法相同：能放进 `TapAsk.Core` 的纯逻辑都放进去，窗口和 WebView2 相关的留在 `TapAsk`。`TapAsk.Core` 的内容与 Mac 的 `TapAskCore` 一一对应：

| Mac（`macos/Sources/TapAskCore/`） | Windows（`TapAsk.Core`） |
| --- | --- |
| `Provider.swift` | 服务商目录加载与校验 |
| `NavigationPolicy.swift` | 导航判定，四种结果 allow / download / browser / cancel |
| `LastPage.swift` | 页面记忆的保存与恢复校验 |
| `ProviderOrder.swift`、`ProviderSelection.swift` | 排序与选择 |
| `SessionRetentionPolicy.swift` | 两页缓存 + 300 秒到期 |
| `PageLoadState.swift`、`PageReload.swift`、`WebContentTermination.swift` | 加载状态机、刷新目标、进程终止处理 |
| `NavigationNotice.swift` | 提示文案与 10 秒去重 |
| `ChatPanelPlacement.swift`、`LoginPopupPlacement.swift` | 窗口几何（注意 Windows 的 y 轴向下） |
| `GlobalShortcut.swift` | 快捷键模型、校验和保留键 |

`shared/policy-cases.json` 里有 258 个用例（`isPanelURL` 80、`actions` 91、`responses` 63、`origins` 24）。Windows 的测试必须把它们全部跑过，这是两端导航规则一致的唯一硬保证。

## Mac 到 Windows 的对应

| Mac | Windows | 说明 |
| --- | --- | --- |
| ⌥空格 | Alt+空格 | 默认值，可自定义 |
| ⌘1 到 ⌘6、⌘R、⌘, | Ctrl+1 到 Ctrl+6、Ctrl+R、Ctrl+, | 焦点在网页里时 WinForms 收不到按键，要在 WebView2 的 `AcceleratorKeyPressed` 里处理 |
| ⌘Q 退出 | 托盘菜单“退出” | Alt+F4 在主浮窗上的作用是收起，不退出 |
| 菜单栏图标，左键切换、右键菜单 | 托盘图标，左键切换、右键菜单 | 菜单项顺序与 Mac 相同 |
| `NSPanel` 置顶、跨 Space | `TopMost` + `WS_EX_TOOLWINDOW` | 后者同时让窗口不进任务栏和 Alt+Tab |
| `.canJoinAllSpaces` | `IVirtualDesktopManager` | 呼出前检查窗口是否在当前虚拟桌面，不在就移过来 |
| 顶部白色短条拖动 | 无边框窗口 + 顶部同样的短条 | 在短条周围的命中区返回 `HTCAPTION`，边缘返回缩放命中值 |
| `WKWebsiteDataStore.default()` | 固定的 WebView2 用户数据目录 | 所有服务商共用一个环境，登录数据持久化 |
| UserDefaults | `%APPDATA%\TapAsk\settings.json` | 键名与 Mac 相同：`PanelFrame`、`LastProviderID`、`LastPage.<id>`、`ProviderOrder`、`GlobalShortcut` |
| 系统日志（os_log） | `%LOCALAPPDATA%\TapAsk\logs\` 下的文本日志，限制大小 | 格式和 Mac 相同，只记主机名、阶段和结果 |
| `SMAppService` 登录项 | 注册表 `HKCU\...\Run`，带后台启动参数 | 用户在任务管理器里关掉自启后，不重新打开 |
| Sparkle | Velopack | 行为对齐：后台下载，正常退出时安装 |
| 修补版 Safari UA | WebView2 默认 UA（与 Edge 相同） | 不伪装，见“最容易出问题的假设” |
| `decidePolicyFor` 动作与响应 | `NavigationStarting`、`FrameNavigationStarting`、`NewWindowRequested` | 见下条 |

**导航判定有一处对不上。** Mac 的规则分“动作”和“响应”两步，响应那一步能看到 `Content-Disposition` 和能否显示。WebView2 在导航阶段拿不到响应头，对应的情况会变成 `DownloadStarting` 事件。所以 Windows 的做法是：动作规则接在 `NavigationStarting`、`FrameNavigationStarting` 和 `NewWindowRequested` 上；所有 `DownloadStarting` 一律取消并记日志（与 Mac 现在的结果相同）；`responses` 那 63 个用例只在 `TapAsk.Core` 里作为纯逻辑通过测试，运行时暂不接线。这一点要写进 `docs/behavior.md` 的 Windows 列。

**“用户点击”的判断也不完全一样。** Mac 用 `navigationType == .linkActivated`，WebView2 提供的是 `IsUserInitiated`。两者在“脚本触发的跳转”上语义接近但不保证相同，W1 的真机验收要专门测：脚本整页跳到外站被取消，点击外链交给默认浏览器。

WebView2 另外要关掉的默认行为：开发者工具、状态栏、浏览器自带加速键（`AreBrowserAcceleratorKeysEnabled = false`，这样 Ctrl+R、F5、Ctrl+P 等由 TapAsk 自己决定），权限请求全部拒绝。

## 阶段

每个阶段做完都是一个能日常使用的程序，后面的阶段不做也不影响前面的可用。

### W1：能用的单服务商浮窗

- 建解决方案和三个项目，`verify.ps1` 能跑通。
- `TapAsk.Core`：服务商目录、导航判定、页面记忆，258 个共享用例全部通过。
- 程序：Alt+空格呼出和收起，置顶浮窗，不进任务栏和 Alt+Tab，托盘图标带“显示/隐藏”和“退出”，单实例（再次启动时显示已有窗口）。
- 一个 WebView2，首次加载 DeepSeek，登录状态退出重开后保留，导航规则生效，外链交默认浏览器。
- 按每台显示器 DPI 感知（Per-Monitor V2）。

验收：从别的程序按 Alt+空格能直接打字、第一个字不丢；中文输入法候选框正常；再按一次收起，焦点回到原程序；连按 10 次状态不乱；DeepSeek 能登录且重开后仍登录；脚本跳外站被取消。

### W2：六家服务商

- Ctrl+1 到 Ctrl+6 切换，托盘菜单列出服务商并打勾。
- 每家独立的 WebView2，首次使用才创建；最多保留两家，后台 300 秒释放，“释放其他服务商页面”。
- 记住上次的服务商和各家的对话页面，恢复失败回退首页一次。
- 服务商排序窗口（拖动和 Alt+↑/↓，恢复默认）。
- 加载超过 0.4 秒显示“正在打开”，失败显示原因和“重试”，Ctrl+R 重新加载。
- 网页进程崩溃（`ProcessFailed`）：可见时立即恢复，后台或隐藏时等到显示再恢复。

验收：`docs/behavior.md` 手动验收清单里关于切换、缓存、释放、页面记忆、排序、断网重试的条目，逐条在 Windows 上走一遍。

### W3：登录弹窗和提示

- 共享登录主机（Google、Apple、Microsoft）的新窗口请求开登录弹窗，保留与发起页面的关系；自家主机的新窗口请求直接在主浮窗里打开。
- 弹窗底部工具栏显示当前主机名和“完成，回到主窗口”；只有“完成”会刷新发起的服务商。
- 弹窗位置不超出屏幕，可直接打字；切换服务商时关闭旧弹窗；同一时间只有一个弹窗。
- 主浮窗离开自家主机时显示来源提示；拦截和交给浏览器时显示提示条，10 秒内同主机不重复。
- 弹窗的加载失败、重试和崩溃恢复只用 GET 重新打开初始登录地址。

验收：六家服务商各自完成一次登录，包括 Google 登录；清单里登录弹窗相关的条目逐条通过。

### W4：窗口细节和系统集成

- 无边框外观，顶部短条拖动，边缘缩放，保留圆角和阴影。
- 记住位置和大小；从隐藏状态呼出时跟随鼠标所在显示器，窗口过大时缩小、越界时移回工作区。
- 在别的虚拟桌面呼出时出现在当前桌面；在全屏程序上方能呼出。
- 快捷键设置窗口：录制、保存、恢复默认、保留键拒绝、注册失败保留原设置。
- 开机自启：安装后首次运行注册一次，后台启动只预热不弹窗。

验收：清单里窗口、跨屏、快捷键设置、自启相关的条目；另外加 Windows 特有的三项：不同缩放比例的两块屏之间切换、虚拟桌面、全屏程序上方呼出。

### W5：分发和自动更新

- Velopack 打包，安装到 `%LocalAppData%`，不需要管理员权限。
- 每天在后台检查并下载；仅在用户正常退出时调用 `WaitExitThenApplyUpdates` 安装，不主动重启。Velopack 的等待有 60 秒上限，不能在下载后立即调用，否则可能中断长时间聊天。托盘菜单有“检查更新…”和“自动更新”开关。
- README 加 Windows 的下载、安装和首次运行放行说明；`docs/behavior.md` 的 Windows 列改成实际行为。
- 加一个 GitHub Actions 工作流，在 Windows 环境跑 `verify.ps1`，这样在 Mac 这边改了 `shared/` 或文档也能知道 Windows 测试有没有坏。

用户于 2026-11-11 允许 Velopack 的安装器、启动器和更新器在本机诊断日志中记录安装路径；更新源的日志不会写入网址或异常详情。源码运行版跳过更新组件初始化，安装版及 Velopack 便携版启用更新；实际安装与升级仍需验收。

验收：装一个旧版本，发布一个新版本，旧版本后台下载、正常退出后装上新版本，登录数据和设置保留。

## 自动更新为什么选 Velopack

Mac 的行为是“后台下载，下次正常退出时安装，不打断聊天”，这是你 11 月 6 日明确选的。Velopack 的 `WaitExitThenApplyUpdates` 正好是这个行为，而且安装在用户目录、不需要管理员权限，更新源可以直接用 GitHub Release。

另一个选择是 WinSparkle，它能读 Mac 现在用的同一种 appcast，但它的流程是弹窗让用户运行安装程序，做不到退出时静默安装，还要另外做一个安装包。所以不选。

**发版方式会受影响。** Mac 的更新源固定指向“最新正式 Release”里的 `appcast.xml`，所以每个 Latest Release 都必须带 Mac 的更新文件。Windows 加进来后，方案是两端共用同一个版本号和同一个 Release：先建草稿，Mac 和 Windows 各自把附件传上去，核对齐全后再发布。只有一端有改动时，另一端的附件从上一个 Release 原样带过来。W5 开工时要先核对一件事：Velopack 的 `GithubSource` 在这种“两端附件放一起”的 Release 里能否正确找到 Windows 的更新清单；不行就改用指向固定下载地址的 `SimpleWebSource`。

## 最容易出问题的假设

1. **Google 登录在 WebView2 里能用。** Google 的政策不欢迎内嵌浏览器。Mac 靠改成 Safari 的 UA 通过了，WebView2 的默认 UA 与 Edge 相同，实际中很多程序可以正常登录，但没有保证。如果 Google 拦截，Gemini 完全不可用，Claude 等只能用邮箱登录。所以 Google 登录是 W1 做完后第一件要在真机上试的事，早于其他验收。它不通过的话，后面的阶段照做，但要先和你确认是否接受这个缺口。
2. **Alt+空格注册得上。** 这个组合键是系统的窗口菜单快捷键，也常被 PowerToys Run、ChatGPT 桌面版占用。注册失败时提示一次并照常显示窗口，用户可以在 W4 的设置里换键；W4 之前只能先退出占用它的程序。
3. **`IsUserInitiated` 与 Mac 的“点击链接”足够接近。** 不一致时不能靠放宽规则解决，要回来改判定的接线方式。
4. **无边框窗口在不同缩放比例的屏幕之间表现正常。** WinForms 的多屏缩放一直是麻烦点，放在 W4 专门验收。

## 开发方式

- **只在 Windows 那台机器上开发**，仓库在 `D:\Projects\tap-ask`。Mac 上没有 .NET SDK，也跑不了 WinForms 和 WebView2 的测试，所以 Mac 这边不改 `windows/` 下的代码。
- 两端通过 `main` 同步。Windows 实现主要放在 `windows/`，需要同步的行为写入 `docs/behavior.md` 和 README；本次两端首次默认服务商的共同修改也涉及 Mac 纯逻辑与测试。
- `shared/` 仍然不改。Windows 发现需要新增允许主机时，和 Mac 一样要有真机日志作依据。
- W1 开工时在根目录 `AGENTS.md` 里加一节 Windows 的构建和测试命令、授权依赖，以及“不调用脚本注入接口”在 WebView2 上的具体含义。

## Windows 机器上的准备

2026-11-11 在当前 Windows 机器已完成以下开发准备：

1. .NET 10 SDK 安装在仓库忽略的 `private/dotnet/`，未修改系统 PATH。
2. 已确认 WebView2 Runtime 存在。
3. 仓库位于 `D:\Projects\tap-ask`；本轮改动尚未提交或推送。
4. 本机可生成 Velopack 安装包和便携包，发布状态以 GitHub Release 为准。

不需要任何账号、密钥或付费服务。W5 用到的 GitHub Release 权限沿用现有的。

## 待你决定

- **与 Mac 后续功能的先后**：Mac 的下载和麦克风原本排在 Windows 之前。两条线在不同机器上，可以同时推进；本方案按“同时推进，Windows 对齐 0.1.5”写。
