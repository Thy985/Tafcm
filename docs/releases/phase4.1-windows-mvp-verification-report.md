# Phase 4.1 Windows MVP Verification Report

> **本文件为 Phase 4.1 M5 里程碑（本地手动冒烟验证）报告，对应 [ADR-0034](../decisions/ADR/0034-windows-desktop-platform.md) 的 D5 / M2-M5 验证项。**
>
> **版本**：v1.0（M1/M4 达成，M2/M3 部分达成，M5 关闭判据未满足）
> **生成日期**：2026-10-13
> **生成者**：AI Agent
> **审批状态**：⏳ 待 Human Owner 审批
> **关联 ADR**：[ADR-0034 Windows 桌面端首个平台决策](../decisions/ADR/0034-windows-desktop-platform.md)
> **关联 PR**：[#384 ADR-0034](https://github.com/Thy985/Tafcm/pull/384)（已合）· [#385 M1+M4 骨架与 CI](https://github.com/Thy985/Tafcm/pull/385)（已合）· [#386 复审修复](https://github.com/Thy985/Tafcm/pull/386)（已合）· [#387 CI runner pin](https://github.com/Thy985/Tafcm/pull/387)（OPEN，待评审）
> **关联分支**：`feat/phase4.1-windows-ci-runner-pin`（HEAD `a98f2d2`）

---

## 0. 结论摘要（TL;DR）

| 里程碑 | ADR 定义 | 本报告状态 |
|---|---|---|
| M1 | 生成 `windows/` 原生工程 + 首次构建通过 | ✅ **达成**（CI + 本地双验证） |
| M2 | WebView2 渲染链路验证（公式 SVG + Mermaid） | ⚠️ **部分达成**（挂载与加载通，MathJax 渲染 timeout） |
| M3 | `file_picker` / `share_plus` Windows 实测 | ⚠️ **部分达成**（代码级 + 构建级确认，运行时未测） |
| M4 | `build-windows` CI job（路径过滤 + 手动触发） | ✅ **达成**（CI 实测绿） |
| M5 | 本地手动冒烟验证报告 | ✅ **本报告**（但 MVP 关闭判据未满足） |

**Phase 4.1 MVP 关闭判据：⏳ 未满足。** 阻塞项为 **BUG-004**（见 §4）：Windows 上公式 Web
View 渲染 timeout，且 ADR-0034 D5 预设的降级兜底（`flutter_math_fork`）**在 Windows 上未生效**——用户实际看到的是公式源码文本而非渲染结果。这是独立缺陷，需单独修复，不属本阶段工程改动范围（ADR §6.3.3 禁止功能改动混入基础设施 PR）。

---

## 1. Scope（本次 Phase 4.1 涵盖范围）

Phase 4.1 只做"Windows 平台立项 + 骨架 + CI 链路"，不做功能对齐。明确**不涵盖**：macOS / Linux（ADR-0034 D1）、快捷键 / 打字机 / 多窗口（D4）、文件关联 / 全局搜索 / 自动更新（D4）。

| 任务 | ADR 依据 | 状态 | 证据 |
|------|---------|------|------|
| M1.1 `flutter create . --platforms=windows` 生成原生骨架 | D1 | ✅ | PR #385，21 个新文件 |
| M1.2 `.metadata` 追加 windows 平台条目 | D1 | ✅ | PR #385 + #386 修正 |
| M1.3 首次 `flutter build windows` 通过 | D1 | ✅ | CI run 38376257526 + 本地 335.7s |
| M1.4 `flutter_inappwebview_windows` override 锁定 | D5 | ✅ | PR #385（pubspec +4 行） |
| M2.1 WebView2 平台视图挂载 | D5 | ✅ | integration_test 日志 `attach_controller attached=true ready=true` |
| M2.2 `loadFile` 渲染宿主页面加载 | D5 | ✅ | 日志 `page_load_stop renderer_ready pageLoaded=true` |
| M2.3 MathJax SVG 渲染（`evaluateJavascript`） | D5 | ❌ | `LaTeX SVG render timeout`（BUG-004） |
| M2.4 Mermaid 图表渲染 | D5 | ❌ | 同上管线，同源缺陷 |
| M3.1 `file_picker` Windows 实现确认 | D4 | ⚠️ | 代码级 `dartPluginClass: FilePickerWindows`（纯 Dart），运行时未测 |
| M3.2 `share_plus` Windows 实现确认 | D4 | ⚠️ | 原生 C API 插件已产出 dll，运行时未测 |
| M4.1 `build-windows` job + `changes` windows filter | D2 | ✅ | CI run 38376257526 命中并绿 |
| M5 | D2/D5 | ✅ | 本报告 |

**交付率**：M1 4/4、M2 2/4、M3 2/2（代码级）、M4 1/1、M5 1/1。

---

## 2. 提交轨迹（Commits）

| commit / PR | 说明 | 关联任务 | 状态 |
|--------|------|---------|------|
| `931c0e1` / #384 | ADR-0034 + INDEX（33→34 篇） | 立项 | ✅ 已合 main |
| `0409526` / #385 | `flutter_app/windows/` 骨架 + `.metadata` + `build-windows` job + changes filter + inappwebview override | M1 / M4 | ✅ 已合 main |
| `482930c` / #386 | 复审修复：`.metadata` 平台记录 / `url_launcher_windows` 补锁 / CI filter 注释澄清 | M1 收尾 | ✅ 已合 main |
| `a98f2d2` / #387 | `build-windows` runner pin `windows-latest` → `windows-2022` 修复 STL1011 | M4 修复 | ⏳ OPEN |
| （本 PR） | 本报告 | M5 | ⏳ 待提交 |

---

## 3. M1 本地手动冒烟验证（ADR M5 核心）

### 3.1 构建与产物

`flutter build windows --debug` 实测 **335.7s** 成功（VS Build Tools 2022 / MSVC 14.44 + nuget 7.9.0）。

| 产物 | 体积 | 说明 |
|------|------|------|
| `tafcm.exe` | 0.98 MB | 主程序 |
| `flutter_windows.dll` | 43.44 MB | Flutter 引擎 |
| `flutter_inappwebview_windows_plugin.dll` | 5.22 MB | WebView2 平台插件 ✅ |
| `share_plus_plugin.dll` | 1.92 MB | 分享插件（原生 C API）✅ |
| `url_launcher_windows_plugin.dll` | 1.0 MB | 链接跳转插件 ✅ |
| `dartjni.dll` | 0.19 MB | JNI FFI 插件 |
| `WebView2Loader.dll` | 0.16 MB | WebView2 桥接 ✅ |

**NuGet 依赖下载正常**（`flutter_inappwebview_windows` 构建期经 `nuget install` 拉取 3 个包）：`Microsoft.Web.WebView2 1.0.2792.45`、`Microsoft.Windows.ImplementationLibrary 1.0.231216.1`、`nlohmann.json 3.11.2` → `build/windows/x64/packages/`。

**Asset bundle 打包验证**：`assets/mermaid_renderer.html`（2.8KB）、`assets/js/tex-svg.js`（2.1MB）、`assets/js/mermaid.min.js`（3.3MB）均已正确进入 `flutter_assets/assets/` 保留目录层级（排除了"asset 未打包"这一嫌疑方向）。

### 3.2 App 启动冒烟

`tafcm.exe` 直接运行：**进程稳定存活 20s+**，窗口标题 `tafcm`，工作集 317 MB，无 WerFault / 崩溃弹窗，无退出码异常。WYSIWYG 编辑面可打开。

### 3.3 integration_test 在 Windows 桌面端可跑（原限制已解除）

既有测试注释"仅模拟器可验"的前提是当时项目无 Windows runner。现在 runner 就绪后实测：

```
$ flutter test integration_test/smoke_test.dart -d windows
√ Built build\windows\x64\runner\Debug\tafcm.exe   (41.1s)
00:00 +1: All tests passed!
```

**结论**：ADR-0034 D3（Windows 不接管 CI integration_test）仍成立——CI 走 `changes` 路径过滤 + 手动触发，成本与收益不成比例；但"Windows 本地无法跑 integration_test"这一**工具链前提已失效**，后续 M2/M3 可改用 integration_test 自动验证，无需纯手工。这是本轮对 ADR-0034 D3 前提的**事实修正**，建议 ADR-0034 追加勘误。

---

## 4. M2 WebView2 渲染链路诊断（BUG-004）

### 4.1 实测命令与结果

```
$ flutter test integration_test/phase35_formula_test.dart -d windows
00:45 +1 -3: Some tests failed.
```

| 用例 | 结果 |
|------|------|
| T3-2 块级公式真实 MathJax SVG 渲染 | ❌ `lastErr=FormulaSvgException: LaTeX SVG render timeout` |
| T3-2 SVG 未就绪窗口期降级 `flutter_math_fork` | ❌ `Found 0 widgets with type "Math"` |
| T3-2 行内公式渲染 | ❌（同源） |
| T3-2 三主题公式颜色 | ✅ 通过 |

### 4.2 关键日志链（根因证据）

```
MermaidLc attach_controller attached=true ready=true pageLoaded=false   ← ① WebView2 挂载成功
MermaidLc page_load_start  pageLoaded=false
MermaidLc page_load_stop   renderer_ready pageLoaded=true                ← ② 页面加载完成
FormulaLc render_start id=l1 len=8 mode=block waiting=1 active=0
FormulaLc render_timeout id=l1                                            ← ③ evaluateJavascript 60s 未返回
[FormulaRenderer] fallback reason=FormulaRenderWebViewError (len=8, display=true)  ← ④ 降级通知已发
FormulaLc render_timeout id=l2
FormulaLc render_timeout id=l3
MermaidLc renderer_reset attached=false ready=false pageLoaded=false     ← ⑤ WebView 被重置
```

### 4.3 根因判定

| 嫌疑 | 结论 | 证据 |
|------|------|------|
| WebView2 Runtime 未装 | ❌ 排除 | 本机 `154.0.4258.62`；挂载与 `pageLoaded=true` 均成功 |
| NuGet 依赖缺失 | ❌ 排除 | 3 个包已下载并链接成功 |
| Asset 未打包 / 路径错 | ❌ 排除 | `flutter_assets/assets/js/` 层级完整 |
| **`evaluateJavascript` 在 Windows WebView2 上不返回结果** | ✅ **最可能** | ① 挂载 ② 加载均成功，唯 ③ JS 求值超时 |

**性质**：Windows 平台插件层缺陷（`flutter_inappwebview_windows 0.6.0` 与本机 WebView2 的组合行为），非本项目 Dart 层代码问题。与既有 `phase35_formula_test.dart:52` 注释记载的"integration_test 环境下 `onLoadStop` 回调不可靠"**同源**——Android 上 workaround 是手动轮询 JS 就绪状态再 `markPageLoaded()`；Windows 上连该 workaround 也走不通。

### 4.4 降级兜底同样失效（本报告最重要的发现）

ADR-0034 D5 预设：

> 若 `flutter_inappwebview_windows` 平台实现在本项目验证失败（如 `evaluateJavascript` 超时），MVP 降级路径为"公式行内走 `flutter_math_fork` 纯 Dart 渲染 + Mermaid 显示源码占位"。

**实测：降级路径的 UI 更新未生效。** 日志显示 `[FormulaRenderer] fallback reason=FormulaRenderWebViewError`（降级通知已发出），但紧接着的降级用例断言 `Found 0 widgets with type "Math"`——**没有 `flutter_math_fork` 的 `Math` widget 被挂载**。

含义：**Windows 用户实际看到的是公式源码文本（`$$E = mc^2$$`）而非渲染结果，且 ADR 承诺的 `flutter_math_fork` 兜底也不在工作**——即 Windows 上公式与 Mermaid 图表的可用度低于移动端。这使 Phase 4.1 MVP 的"打开 / 编辑 / 导出 / 公式 / Mermaid 图表"闭环在公式维度上不成立。

### 4.5 处置建议

- **不阻塞本 PR 合并**：本报告 PR 仅含文档，不含功能改动（ADR §6.3.3 禁止功能改动混入基础设施 PR）。
- **建议单开 BUG-004**：`windows-webview2-evaluatejavascript-timeout`，两个独立子项——(a) `evaluateJavascript` 无响应；(b) 降级 `Math` widget 未挂载。二者相互独立，可分别定位。
- **短期用户侧缓解**：Windows 上 Mermaid/公式仍显示源码占位，不影响编辑与导出（导出走独立管线，PDF/DOCX 的公式预渲染阶段同样依赖 WebView，需一并验证）。
- **候选修复方向**（不在本轮范围）：检查 `flutter_inappwebview_windows 0.6.0` 的 `evaluateJavascript` 实现在 Windows 上是否依赖未就绪的 callback channel；评估 0.7.0-beta+ 是否修复。

---

## 5. M3 插件 Windows 行为确认

### 5.1 代码级与构建级证据

| 插件 | 解析版本 | Windows 实现形态 | 证据 |
|------|---------|-----------------|------|
| `file_picker` | 8.3.7 | `dartPluginClass: FilePickerWindows`（**纯 Dart**，无原生层） | `pubspec.yaml` plugin 声明 + `.plugin_symlinks` 实际解析 |
| `share_plus` | 7.2.2 | `pluginClass: SharePlusWindowsPluginCApi`（**原生 C API**） | 构建产物 `share_plus_plugin.dll`（1.92 MB） |
| `url_launcher_windows` | 3.1.6 | 原生 C API 插件 | 构建产物 dll（1.0 MB），由 #386 补锁 override |
| `path_provider_windows` | 2.3.0 | 已注册原生插件 | `generated_plugins.cmake` |
| `shared_preferences_windows` | 2.4.1 | 已注册原生插件 | `generated_plugins.cmake` |
| `flutter_inappwebview_windows` | 0.6.0 | endorsed 原生插件 | 构建产物 dll（5.22 MB） |

### 5.2 运行时未验证项（诚实声明）

`file_picker` 与 `share_plus` 的 Windows 运行时行为（打开系统文件对话框、调起系统分享面板）**未在本轮验证**——二者的验证路径都会触发 Windows 原生 UI 交互（模态对话框 / 系统分享面板），依赖用户手动点选，非自动化可闭环；且当前 M2 的公式缺陷未修，优先序更低。

- **`file_picker` 风险较低**：纯 Dart 实现 + Windows 原生对话框 API，无跨平台行为差异预期。
- **`share_plus` 风险中等**：ADR-0034 D4 已登记"Windows 上可能不是用户期望的分享体验，MVP 阶段接受此降级"——本轮无新信息，维持该判断。

---

## 6. M4 CI 构建链路验证

### 6.1 首次运行失败与修复

| 轮次 | run | runner | 结果 | 根因 |
|------|-----|--------|------|------|
| 1 | 38322448267 | `windows-latest` | ❌ `Build Windows Release` failed | STL1011：VS 2026 / MSVC 14.51.36231 废弃 `<experimental/coroutine>`，`error C2338` |
| 2 | 38376257526 | `windows-2022`（pin 后） | ✅ **`Build Windows Release => success`** | — |

**根因**：`windows-latest` 已升级至 Visual Studio 2026（MSVC 14.51.36231）。`flutter_inappwebview_windows 0.6.0`（2024 stable）仍使用 C++11 老 `<experimental/coroutine>` 头，触发 STL1011 废弃静态断言。

**修复**：`runs-on: windows-latest` → `windows-2022`（VS2022 / MSVC 14.4x），与本地开发工具链一致，避免 CI 与本地漂移。见 PR #387。

**附加发现（CI 环境前置）**：`windows-2022` runner 需 `nuget.exe` 在 PATH——`flutter_inappwebview_windows` 构建期以 `NUGET-NOTFOUND install` 占位符下载 WebView2 SDK 等包。本地首次构建即因缺 nuget 失败（exit 9009）；`scoop install nuget`（7.9.0，用户级无需管理员）后本地与 CI 均通过，说明 `windows-2022` 镜像内置 NuGet。

### 6.2 CI 顶层结论说明

run 38376257526 顶层 `conclusion: failure`，但**唯一失败项为既有的 `Android Device Integration (emulator)`**（与本阶段无关的既有 flake）。其余 15 项全绿，含 `Build Windows Release`、`Build Android Debug APK`、`Build Web`、`Golden (compare)`、`Perf (ratchet gate)`、`Test`、`Analyze`、`ADI E2E`。

**结论**：`build-windows` job 的**功能性与可编译性已在 CI 上闭环验证**，M4 达成。PR #387 的 merge 阻塞仅取决于该既有 Android emulator flake 是否被 Owner 接受为无关项。

### 6.3 迁回 `windows-latest` 的前置条件

1. `flutter_inappwebview_windows` 升级到能过 MSVC 14.51 的版本（0.7.0-beta+ 或 stable 0.7.0）
2. 同步解除 `pubspec.yaml` 中 `flutter_inappwebview_windows: 0.6.0` 的 `dependency_overrides` 锁定
3. 重跑 `build-windows` 手动触发验证

---

## 7. 环境事实（本轮实测，供后续开发复用）

| 项 | 值 | 来源 |
|---|---|---|
| Flutter | 3.44.6 stable（channel stable，`ee80f08bbf`） | `flutter --version` |
| Dart | 3.12.2 | `flutter --version` |
| OS | Windows 11 26H2（10.0.26300.9550） | `flutter doctor` |
| Flutter SDK 路径 | `C:\Users\lenovo\SDK\flutter` | PATH |
| VS Build Tools | 2022 **17.14.41**（非标准路径 `D:\Microsoft`） | vswhere |
| MSVC | 14.44.35207（toolset **v143**） | `VC\Tools\MSVC` |
| CMake | 3.31.6-msvc6 | VS 内置 |
| NuGet | 7.9.0（scoop 用户级安装，无需管理员） | `scoop list` |
| WebView2 Runtime | **154.0.4258.62** ✅ | 注册表 `HKLM\...\EdgeUpdate\Clients\{F3017226-...}` |
| Edge WebView2 SDK | 1.0.2792.45（NuGet 构建期下载） | `build/windows/x64/packages/` |
| 已装 workload | `Workload.VCTools` + `Component.VC.CMake.Project` | vswhere |
| flutter doctor VS 项 | ✅ 通过 | `flutter doctor -v` |

### 7.1 关于"缺 MSVC v142"的勘误

初版诊断（基于 `flutter doctor` 报错文案）判断缺 v142 工具集。**该判断是假线索**：

1. **Flutter 显示文案是静态 bug**：`packages/flutter_tools/lib/src/visual_studio.dart:295-298` 的 `switch` 语句只有 `case 16:` 与 `default:`，无 `case 17`，因此 VS 2022 恒显示硬编码文案 `MSVC v142 - VS 2019...`。实际 v143（14.44）一直满足构建要求。
2. **vswhere 已正确注册**：实例位于 `D:\Program Files\Microsoft Visual Studio\Package\_Instances\0130e303`（非 `C:\ProgramData\...\_Instances` 那个 VS 2019 时代旧位置，后者为空易误判）。
3. **真实阻塞只有一个组件**：`Component.VC.CMake.Project`（外加 Flutter 检查的 `Workload.VCTools`）。补装后增量 1.7 GB（总 3.4 GB）。
4. **报错里的 "Windows 10 SDK" 同样是静态文本**：`packages/flutter_tools/lib/src/user_messages.dart:117` 硬编码，任何报错都带。

**教训**：`flutter doctor` 的 Windows 工具链报错文案不可直接采信，须以 `vswhere -requires` 三组件组合 + 实际 `flutter build windows` 编译结果为准。

---

## 8. 后续行动项

| # | 项 | 归属 | 阻塞性 |
|---|----|------|--------|
| 1 | 合并 PR #387（`windows-2022` pin） | Owner | 阻塞 M4 闭环 |
| 2 | 合并本 PR（M5 报告） | Owner | 阻塞 M5 归档 |
| 3 | 单开 **BUG-004**：`windows-webview2-evaluatejavascript-timeout`（含降级 `Math` widget 未挂载子项） | 后续 | **阻塞 Phase 4.1 MVP 关闭判据** |
| 4 | ADR-0034 D3 勘误：Windows integration_test 工具链前提已解除（本报告 §3.3） | 后续 | 文档 |
| 5 | 验证 `flutter_inappwebview_windows 0.7.0-beta+` 是否修复 evaluateJavascript 与 STL1011（一并解锁迁回 `windows-latest`） | 后续 | 可选 |
| 6 | Windows 运行时补测 `file_picker` / `share_plus`（人工点选，非自动化） | 后续 | 不阻塞 |

**Phase 4.1 MVP 关闭判据**：M1-M5 全部完成 + 公式/Mermaid 在 Windows 上可用或降级生效。当前 M2 两项未通过且降级未生效（§4.4），故 **⏳ 未满足**。

---

## 9. 与 ADR-0034 的对齐声明

| ADR 条目 | 本报告对齐情况 |
|---------|--------------|
| D1 平台范围（仅 Windows） | ✅ 未触碰 macOS / Linux |
| D2 CI 策略（`changes` + 手动触发） | ✅ 已实现并验证；`windows-2022` pin 为必要偏差，理由见 §6.1 |
| D3 E2E 分工（Windows 不接管 CI integration_test） | ✅ 策略成立；但"本地无法跑"的工具链前提已失效，见 §3.3 |
| D4 功能降级清单 | ✅ 未实现快捷键 / 多窗口等；`file_picker` / `share_plus` 维持登记状态 |
| D5 运行时依赖与降级路径 | ⚠️ WebView2 Runtime 已确认；**降级路径实测未生效**（§4.4），ADR 需补勘误 |
| D6 回滚策略 | ✅ 未触发回滚条件 |

---

## 10. 测试与门禁

- [x] 本地 `flutter build windows --debug` 成功（335.7s，产物清单见 §3.1）
- [x] 本地 `tafcm.exe` 启动冒烟通过（20s+ 稳定，见 §3.2）
- [x] 本地 `integration_test/smoke_test.dart -d windows` 通过（见 §3.3）
- [x] CI `Build Windows Release` 通过（run 38376257526，见 §6.2）
- [x] CI `changes` job 的 windows 路径过滤正确命中（ci.yml 变更触发 build-windows）
- [ ] `integration_test/phase35_formula_test.dart -d windows` **失败 3/4**（BUG-004，见 §4）
- [ ] `file_picker` / `share_plus` 运行时实测未做（见 §5.2，诚实声明）

本 PR 仅含文档改动，不触及 `lib/` / `test/` / 业务代码，不影响 CI 门禁。

---

## 11. 回滚计划

- 本报告为独立文档新增，回滚 = 删除本文件（无残留）。
- M1/M4 的工程改动回滚见 ADR-0034 D6（删 `windows/` + `.metadata` 移除 windows + 删 `build-windows` job），全部幂等。

---

**维护人**：AI Agent
**最后更新**：2026-10-13（v1.0，M1/M4 达成，BUG-004 登记为 Phase 4.1 MVP 关闭判据阻塞项）
