# TapAsk

按 ⌥空格，AI 聊天浮窗出现在所有窗口之上；再按一次收起，焦点回到你原来的 app。

支持 ChatGPT、Claude、Gemini、DeepSeek、Grok、豆包，用 ⌘1 到 ⌘6 切换。保留当前和最近使用的一家页面，短时间来回切换无需重新加载；打开第三家，或后台页面切走满 5 分钟后，会自动释放较久未用的页面。

## 下载与安装

要求 macOS 14 或更高版本，Apple 芯片和 Intel 芯片都能用。

1. 从 [Releases](https://github.com/Sure-Will/tap-ask/releases) 下载 `TapAsk-<版本>-macOS.dmg`，双击打开。
2. 在打开的窗口里，把 `TapAsk.app` 拖到“应用程序”。
3. 双击打开。TapAsk 还没有经过 Apple 公证，第一次打开会被 macOS 拦下，提示无法验证它是否安全。被拦下之后，用下面任一方法放行：
   - 打开 系统设置 › 隐私与安全性，在页面下方找到 TapAsk，点“仍要打开”；
   - 或者在终端里运行：

     ```bash
     xattr -dr com.apple.quarantine /Applications/TapAsk.app
     ```

装进“应用程序”文件夹后第一次打开，TapAsk 会把自己加为登录项，开机后在后台准备好，菜单栏图标常驻，Dock 里没有图标。不想开机启动，可以在 系统设置 › 通用 › 登录项 里关掉。

## 使用

| 操作 | 作用 |
|---|---|
| ⌥空格 | 呼出或收起浮窗 |
| ⌘1 到 ⌘6 | 切换服务商 |
| ⌘R | 重新加载当前页面 |
| 左键单击菜单栏图标 | 呼出或收起浮窗 |
| 右键单击菜单栏图标 | 打开菜单：切换服务商、服务商排序、重新加载、检查更新、自动更新、退出 |

在右键菜单的“服务商排序…”里拖动整行，或者选中一行按 ⌥↑ / ⌥↓，就能调整顺序，⌘ 编号会跟着变，“恢复默认”回到初始顺序。

网页铺到浮窗最上沿，顶部中央悬浮一根短白条，没有独立底色或分隔线。鼠标移到白条及周围留白时显示手形光标，可以从这里拖动窗口；其余顶部区域的点击仍交给网页。拖动边缘可以调整大小，位置和大小下次打开还在。

每家服务商都直接在浮窗里登录，登录状态保存在本机。重新打开时，会恢复各家上次停留的页面；服务商自家页面请求新窗口时，页面仍在主浮窗里打开。跳到 Google 等外部登录页时，浮窗顶部会显示当前所在的网站。网络不通时，浮窗会显示失败原因和“重试”按钮，切回加载失败的服务商也会自动重新加载。

自动释放不清除登录数据，切回时会重新加载上次的对话地址；未发送草稿、滚动位置和正在生成的回答可能丢失或中断。当前页面即使收起浮窗也会保留，登录弹窗不受自动释放影响。也可以在右键菜单选择“释放其他服务商页面”立即释放后台页。

自动更新默认开启，每天在后台检查并下载新版本，下载就绪后在下次正常退出 TapAsk 时安装，不主动中断聊天或重启。收起浮窗只会隐藏窗口，不会退出或安装更新。后台更新提醒显示在菜单里，不弹窗抢焦点；主动选择“检查更新…”会打开 Sparkle 的更新界面，也可以立即安装并重启。菜单里的“自动更新”可关闭后台检查和下载，选择在下次启动后仍然有效。更新保留本机登录数据、服务商顺序和窗口偏好，网页内未发送草稿等内存状态不保证在重启后恢复。

自动更新从 0.1.4 开始提供，0.1.3 及更早版本需要先手动替换一次。当前账户没有权限替换应用时，更新需要管理员授权。

如果按 ⌥空格 没有反应，可能是别的 app 也占用了这个组合键，在那个 app 里改掉即可。

TapAsk 本身不收集、不上传任何数据，写进本机系统日志的只有主机名，不含完整网址。浮窗里只会打开当前服务商和常见登录页的网站，你点击的其他链接会用系统默认浏览器打开。

## 从源码构建

需要 Xcode Command Line Tools（Swift 6）。自动更新使用 [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1)，由 Swift Package Manager 获取。

```bash
cd macos
swift test --disable-sandbox
scripts/build-app.sh
```

产物是 `macos/build/TapAsk.app`，同时包含 arm64 和 x86_64。`CODE_SIGN_IDENTITY` 指定签名身份，默认 `-`，沿用 ad-hoc 本机分发；此时主 app 的 Hardened Runtime 签名附带 `disable-library-validation` entitlement，以加载 Sparkle。使用证书签名时不添加这个 entitlement。目前没有 Developer ID 签名或 Apple 公证，更新包通过 Ed25519 签名验证，并在解包前验证。服务商列表在 `shared/providers.json`，导航规则的测试用例在 `shared/policy-cases.json`，行为约定和手工验收清单见 [docs/behavior.md](docs/behavior.md)。

在 `macos/` 下运行 `scripts/make-dmg.sh` 会先构建 app，再生成并校验 `build/TapAsk-<版本>-macOS.dmg`。打包使用系统自带的 `hdiutil`，不需要额外依赖。

发布更新前，在 `macos/Info.plist` 中递增 `CFBundleVersion`，并更新展示版本 `CFBundleShortVersionString`。Sparkle 的 Ed25519 私钥保存在登录钥匙串，账号为 `io.github.sure-will.tap-ask.updates`，公钥写入 app 的 `SUPublicEDKey`；私钥不进入仓库。沿用已有密钥，备份后妥善保存，丢失私钥会影响已有安装的后续更新。

在 `macos/` 下运行 `scripts/prepare-update.sh`，会调用 `make-dmg.sh`、签名 DMG，并在 `build/updates/` 生成 `appcast.xml`、DMG 和 SHA-256 校验文件。脚本只准备本地产物，不上传或发布。更新源固定为 [最新正式 Release 的 appcast](https://github.com/Sure-Will/tap-ask/releases/latest/download/appcast.xml)。每次正式 Release 都要附带同一批生成的 appcast、DMG 和 SHA-256 文件；先上传完整草稿并核对附件，再发布并设为 Latest，避免更新源指向缺少附件的版本。签名后不要再修改 DMG。

菜单栏图标和 App 图标的图形都定义在 `macos/Sources/TapAskCore/BrandMark.swift`，改动后运行 `scripts/make-icons.sh` 重新生成 App 图标。

`ChatPanelTests`、`NavigationDelegateTests`、`ProviderOrderWindowTests` 需要能打开窗口、启动 WebKit 的正常 macOS 会话，在沙盒里可以先跳过：

```bash
swift test --disable-sandbox --skip 'NavigationDelegateTests|ChatPanelTests|ProviderOrderWindowTests'
```

Windows 版还在计划中。

## 许可证

[GPL-3.0](LICENSE)
