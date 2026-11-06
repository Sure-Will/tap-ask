# TapAsk 开发约定

给在这个仓库里写代码的 agent 看。任务单只写这一次要做什么；下面这些每次都适用，任务单不再重复。

## 先读

- `docs/behavior.md`：行为约定，以它为准。改了用户能看到的行为，同一次改动里把它同步更新。
- `README.md`：构建和发布说明。

## 不能做

- 不向网页注入脚本：不用 `evaluateJavaScript`、`WKUserScript`，也不读取页面内容来判断登录结果。
- 不放宽导航规则：不改 `NavigationPolicy` 的判断逻辑，不加后缀匹配。新增允许主机只能是精确主机，而且要有真机日志作依据，由任务单明确给出。
- 不改 `shared/`，除非任务单写了可以改。
- 不加依赖。
- 不提交、不推送、不切换分支。分支和提交由调度方负责。
- 不启动、不安装 TapAsk.app，不往 `/Applications` 拷东西，不改系统或其他 app 的设置。真机验收由用户做。
- 日志只记主机名、阶段和结果，不记完整 URL、路径、查询参数、令牌或网页标题。

## 构建和测试

在 `macos/` 下：

```
swift build --disable-sandbox
swift test --disable-sandbox
scripts/build-app.sh
```

- 需要窗口或 WebKit 的测试在 Codex 沙盒里会超时。在沙盒里能编译就行，调度方会在沙盒外运行 `macos/scripts/verify.sh` 跑全量。
- 缓存目录写不进去时，把缓存路径指到 `macos/.build/` 下（`build-app.sh` 里有现成写法）。
- 新行为要有测试。修 bug 时，测试必须能在修之前的代码上失败；在最后的总结里写明你怎么确认了这一点。

## 写法

- 名字写 `TapAsk`。
- 能放进 `TapAskCore` 的纯逻辑放进去，方便单元测试；AppKit 和 WebKit 相关的留在 `TapAsk`。
- 沿用现有结构。要做大范围的架构调整，先在总结里提出来，不要直接改。
