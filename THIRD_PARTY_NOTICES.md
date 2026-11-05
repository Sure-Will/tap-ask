# Third-party notices

TapAsk includes code adapted from [shuaibird/Quick-Chat](https://github.com/shuaibird/Quick-Chat), licensed under the MIT License. The read-only upstream checkout used for this implementation is `/tmp/codex-dispatch/ref/Quick-Chat`, revision `ee5c09842e4c3282fdfdf1fab777e54b687b31c0`.

Adapted areas include Carbon hotkey registration (`GlobalHotKey.swift` → `macos/Sources/TapAsk/HotKey.swift`), native panel and WebKit delegate behavior (`QuickChatPanel.swift` → `ChatPanel.swift`, `WebViewDelegate.swift`, and `Application.swift`), standard Edit menu routing (`EditMenu.swift` → `Application.swift`), and SwiftPM app assembly (`scripts/build-app.sh` → `macos/scripts/build-app.sh`). Unneeded upstream features were not imported.

The navigation policy, all assertions in `NavigationPolicyTests.swift` and `NavigationDelegateTests.swift`, Safari user-agent string, and origin formatting are adapted from the user's patched Quick-Chat snapshot at `/Users/sure/Library/Application Support/Quick Chat Local Build/20261104-171205/source-changes/`. Policy host data moved to `shared/providers.json`, pure assertions to `shared/policy-cases.json`, and WebKit-bound assertions remain in `macos/Tests/TapAskCoreTests/NavigationDelegateTests.swift`. The original 58 pure assertions and 3 delegate assertions are retained; additional cases cover existing policy branches.

The complete upstream license follows. This notice does not assign a license to TapAsk's original code; the project's own license has not yet been selected.

```text
MIT License

Copyright (c) 2026 shuaibird

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
