# tap-ask

按 ⌥空格呼出 ChatGPT / DeepSeek 网页浮窗，再按一次收起，焦点由系统还给之前的 app。用 ⌘1 / ⌘2 或菜单栏常驻图标的菜单切换服务商；菜单也提供显示 / 隐藏、重新加载和退出。TapAsk 使用原生窗口和持久化 WebView，无 Dock 图标。网页铺满浮窗，顶部 8pt 可拖动；访问外部登录页面时，顶部中央显示不拦截点击的来源胶囊。

当前为 **Phase 1：Mac + ChatGPT / DeepSeek**，要求 macOS 14+、Swift 6 / Xcode Command Line Tools，无第三方依赖。Windows 原生版在 Phase 2 实现；两端只共享 `shared/` 的两个 JSON 和 [行为约定](docs/behavior.md)，不共享代码。

在仓库内构建与验证（不安装、不启动）

```bash
cd macos
swift build --disable-sandbox
swift test --disable-sandbox
scripts/build-app.sh
codesign --verify --strict --verbose=2 build/TapAsk.app
plutil -lint build/TapAsk.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/TapAsk.app/Contents/Info.plist
test -f build/TapAsk.app/Contents/Resources/providers.json
test -f build/TapAsk.app/Contents/Resources/AppIcon.icns
```

产物为 `macos/build/TapAsk.app`，使用临时签名，bundle id 为 `io.github.sure-will.tap-ask`。打包脚本把 `shared/providers.json` 和已生成的 `macos/Resources/AppIcon.icns` 复制为 app 资源；裸跑 SwiftPM 可执行文件不具备服务商资源。菜单栏与 app 图标共用 `TapAskCore/BrandMark.swift` 的几何定义；修改后在 `macos/` 下运行 `scripts/make-icons.sh`（或 `swift run --disable-sandbox make-icons`），生成 `build/AppIcon.iconset` 与 `Resources/AppIcon.icns`，再重新打包，平时打包不重新生成图标。缓存目录不可写时，可将 `CLANG_MODULE_CACHE_PATH` 和 `SWIFTPM_MODULECACHE_OVERRIDE` 设为 `$PWD/.build/ModuleCache`，并给 Swift 命令加 `--cache-path "$PWD/.build/cache"`。

使用时请先把 `TapAsk.app` 拷进 `/Applications` 再第一次打开，也支持安装到 `~/Applications`。仅在这两个安装目录下且尚未尝试注册时，app 才会尝试注册登录项并记录已尝试；从构建目录打开只记日志，不注册、不写标记，装好后仍可注册。之后尊重系统设置中的关闭操作；登录启动只后台预热，菜单栏图标常驻。启动只预热上次使用的服务商，其他服务商首次切换时创建 WebView 并加载首页，切回来保留页面状态；不等待联网完成才显示窗口。下载、语音、公证和 Windows 实现在本阶段范围外。

自动化测试包含共享导航用例、窗口切换、品牌几何、菜单结构、顶部点击命中和实际 WebKit 委托回调；`ChatPanelTests` 与 `NavigationDelegateTests` 需要能连接 WindowServer 和启动 WebKit 子进程的 macOS 会话。沙盒中可先用 `swift test --disable-sandbox --skip 'NavigationDelegateTests|ChatPanelTests'` 执行其余测试，真实窗口和导航回调测试在沙盒外运行。输入法、登录、焦点及全屏体验按 [手动验收清单](docs/behavior.md) 检查。移植代码的许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
