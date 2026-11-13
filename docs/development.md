# 开发与发布

TapAsk 的 macOS 和 Windows 版本分别使用原生实现。服务商列表在 `shared/providers.json`，导航规则的测试用例在 `shared/policy-cases.json`。具体行为和手工验收清单见 [行为约定](behavior.md)，Windows 开发方案见 [Windows 开发方案](windows-plan.md)。

## macOS

### 构建与测试

需要 Xcode Command Line Tools（Swift 6）。自动更新使用 [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1)，由 Swift Package Manager 获取。

在仓库根目录运行：

```bash
cd macos
swift build --disable-sandbox
swift test --disable-sandbox
scripts/build-app.sh
```

产物是 `macos/build/TapAsk.app`，同时包含 arm64 和 x86_64。在能打开窗口并运行 WebKit 的正常 macOS 会话中，也可以运行 `scripts/verify.sh` 完成全量检查。

`ChatPanelTests`、`NavigationDelegateTests` 和 `ProviderOrderWindowTests` 需要窗口与 WebKit；在沙盒中可以先跳过：

```bash
swift test --disable-sandbox --skip 'NavigationDelegateTests|ChatPanelTests|ProviderOrderWindowTests'
```

### 打包与签名

在 `macos/` 下运行 `scripts/make-dmg.sh`，会先构建应用，再生成并校验 `build/TapAsk-<版本>-macOS.dmg`。打包使用系统自带的 `hdiutil`。

构建脚本通过 `CODE_SIGN_IDENTITY` 指定签名身份，默认使用 ad-hoc 签名。此时主应用的 Hardened Runtime 签名包含 `disable-library-validation` entitlement，以便加载 Sparkle；使用证书签名时不添加该 entitlement。当前发布包没有 Developer ID 签名或 Apple 公证。

菜单栏图标和应用图标的图形定义在 `macos/Sources/TapAskCore/BrandMark.swift`。修改后运行 `scripts/make-icons.sh` 重新生成应用图标。

### 准备自动更新

发布更新前，递增 `macos/Info.plist` 中的 `CFBundleVersion`，并更新 `CFBundleShortVersionString`。Sparkle 的 Ed25519 私钥保存在登录钥匙串，账号为 `io.github.sure-will.tap-ask.updates`；公钥写入应用的 `SUPublicEDKey`，并用于在解包前验证更新签名。私钥不进入仓库，应沿用并妥善备份现有密钥；丢失后会影响已有安装的后续更新。

在 `macos/` 下运行：

```bash
scripts/prepare-update.sh
```

脚本生成并签名 DMG，在 `build/updates/` 中准备 `appcast.xml`、DMG 和 SHA-256 校验文件，不会上传或发布。签名后不要修改 DMG。更新源是 [最新正式 Release 的 appcast](https://github.com/Sure-Will/tap-ask/releases/latest/download/appcast.xml)。

## Windows

### 构建与测试

需要 Windows x64、.NET 10 SDK 和 [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)。在 Windows 上运行：

```powershell
cd windows
.\scripts\verify.ps1
```

脚本会构建、测试并生成自包含的 x64 程序到 `windows/build/app/`，也会查找仓库 `private/dotnet/` 下的 SDK。如果程序正在运行，可以换一个输出目录：

```powershell
.\scripts\verify.ps1 -OutputDirectory "$PWD\build\verify"
```

### 打包

本地打包需要 Velopack 的 `vpk` 1.2.161，可将它放在 PATH 中或安装到仓库的 `private/vpk/`。以下命令只生成本地产物，不上传或发布：

```powershell
.\scripts\pack.ps1 -Version 0.1.9
```

产物位于 `windows/build/releases/`，包括 `TapAsk-win-Setup.exe`、便携包、Windows 更新清单和更新包。安装升级及开机自启仍需实机验收。

## 正式发布

macOS 和 Windows 共用一个正式 Release。发布前，先上传并核对同一批 Mac 的 appcast、DMG 和校验文件，以及 Windows 的更新清单、更新包和安装包；确认附件齐全后，再发布并设为 Latest。如果只更新一端，也需要确保另一端的下载和更新文件仍然可用。

README 的平台下载链接指向具体版本。发布新版本时，一并核对这些链接和页面中标注的版本号。
