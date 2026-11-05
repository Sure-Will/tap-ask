# TapAsk

按 ⌥空格，AI 聊天浮窗出现在所有窗口之上；再按一次收起，焦点回到你原来的 app。

支持 ChatGPT、Claude、Gemini、DeepSeek、Grok、豆包，用 ⌘1 到 ⌘6 切换。每家服务商的页面各自常驻，切走再切回来，对话还在原处。

## 下载与安装

要求 macOS 14 或更高版本，Apple 芯片和 Intel 芯片都能用。

1. 从 [Releases](https://github.com/Sure-Will/tap-ask/releases) 下载 `TapAsk-<版本>-macOS.zip`，解压。
2. 把 `TapAsk.app` 拖进“应用程序”文件夹。
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
| 右键单击菜单栏图标 | 打开菜单：切换服务商、服务商排序、重新加载、退出 |

在右键菜单的“服务商排序…”里拖动整行，或者选中一行按 ⌥↑ / ⌥↓，就能调整顺序，⌘ 编号会跟着变，“恢复默认”回到初始顺序。

网页铺满整个浮窗。拖动浮窗最上沿约 8pt 的那一条可以移动窗口，拖动边缘可以调整大小，位置和大小下次打开还在。

每家服务商都直接在浮窗里登录，登录状态保存在本机。跳到 Google 等外部登录页时，浮窗顶部会显示当前所在的网站。网络不通时，浮窗会显示失败原因和“重试”按钮，切回加载失败的服务商也会自动重新加载。

如果按 ⌥空格 没有反应，可能是别的 app 也占用了这个组合键，在那个 app 里改掉即可。

TapAsk 本身不收集、不上传任何数据，写进本机系统日志的只有主机名，不含完整网址。浮窗里只会打开当前服务商和常见登录页的网站，你点击的其他链接会用系统默认浏览器打开。

## 从源码构建

需要 Xcode Command Line Tools（Swift 6），没有第三方依赖。

```bash
cd macos
swift test --disable-sandbox
scripts/build-app.sh
```

产物是 `macos/build/TapAsk.app`，同时包含 arm64 和 x86_64，使用临时签名。服务商列表在 `shared/providers.json`，导航规则的测试用例在 `shared/policy-cases.json`，行为约定和手工验收清单见 [docs/behavior.md](docs/behavior.md)。

菜单栏图标和 App 图标的图形都定义在 `macos/Sources/TapAskCore/BrandMark.swift`，改动后运行 `scripts/make-icons.sh` 重新生成 App 图标。

`ChatPanelTests`、`NavigationDelegateTests`、`ProviderOrderWindowTests` 需要能打开窗口、启动 WebKit 的正常 macOS 会话，在沙盒里可以先跳过：

```bash
swift test --disable-sandbox --skip 'NavigationDelegateTests|ChatPanelTests|ProviderOrderWindowTests'
```

Windows 版还在计划中。

## 许可证

[GPL-3.0](LICENSE)
