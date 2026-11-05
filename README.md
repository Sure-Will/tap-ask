# tap-ask

按 ⌥空格呼出 ChatGPT 网页浮窗，再按一次收起，焦点由系统还给之前的 app。TapAsk 使用原生窗口和持久化 WebView，无 Dock 或菜单栏状态图标。

当前为 **Phase 1：Mac + ChatGPT**，要求 macOS 14+、Swift 6 / Xcode Command Line Tools，无第三方依赖。Windows 原生版在 Phase 2 实现；两端只共享 `shared/` 的两个 JSON 和 [行为约定](docs/behavior.md)，不共享代码。

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
```

产物为 `macos/build/TapAsk.app`，使用临时签名，bundle id 为 `io.github.sure-will.tap-ask`。打包脚本把 `shared/providers.json` 复制为 app 资源；裸跑 SwiftPM 可执行文件不具备该资源。缓存目录不可写时，可将 `CLANG_MODULE_CACHE_PATH` 和 `SWIFTPM_MODULECACHE_OVERRIDE` 设为 `$PWD/.build/ModuleCache`，并给 Swift 命令加 `--cache-path "$PWD/.build/cache"`。

使用时请先把 `TapAsk.app` 拷进 `/Applications` 再第一次打开，也支持安装到 `~/Applications`。仅在这两个安装目录下且尚未尝试注册时，app 才会尝试注册登录项并记录已尝试；从构建目录打开只记日志，不注册、不写标记，装好后仍可注册。之后尊重系统设置中的关闭操作；登录启动只后台预热。页面预热从进程启动时开始，不等待联网完成才显示窗口。下载、语音、多服务商切换、图标、公证和 Windows 实现在本阶段范围外。

自动化测试包含共享导航用例、窗口切换和实际 WebKit 委托回调；后者需要能连接 WindowServer 和启动 WebKit 子进程的 macOS 会话。输入法、登录、焦点及全屏体验按 [手动验收清单](docs/behavior.md) 检查。移植代码的许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
