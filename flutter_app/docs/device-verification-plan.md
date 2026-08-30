# 真机验证计划（v0.1.1+2 · PR-1..5 修复链）

> 验证对象：Tafcm debug 包 `0.1.1+2`（versionCode 2，DEBUGGABLE）
> 代码基线：`main` = `a678cf1`（PR-1..5 全部合入：公式渲染可靠性 / Inline AST / Export Pipeline / 导出状态机 / Formula 性能 P0-3/4/5）
> 设备：`63cfc8cf`（zorn / HyperOS，1080×2400）
> 日期：2026-08-30
> 文档维护：AI 助手 + Human Owner 联合执行

---

## 0. 前置条件

| 项 | 状态 | 命令 |
|----|------|------|
| debug 包已安装 | 待装 | `adb install -r build/app/outputs/flutter-apk/app-debug.apk` |
| 设备连接 | ✅ | `adb devices` → `63cfc8cf device` |
| 测试样本已就位 | 待确认 | `/sdcard/Download/device_verify_bug12.md` |
| logcat 清理 | 每次用例前 | `adb logcat -c` |

**验证基线确认**（装包后必做）：
```bash
adb shell dumpsys package com.tafcm.app | grep -E "versionName|versionCode|DEBUGGABLE"
# 期望：versionName=0.1.1 / versionCode=2 / flags 含 DEBUGGABLE
```

---

## 1. 测试样本文档

样本路径：`flutter_app/test_assets/device_verify_bug12.md`（已推送至设备 `/sdcard/Download/`）

通过 App 首页「打开任意 .md 文件 即开即看」入口 → SAF 文件选择器 → `Download/device_verify_bug12.md` 打开。

```markdown
# 真机验证文档（PR-1..5 修复链）

## Bug1：引用内加粗与公式

> **加粗的引用文本** 与行内公式 $E=mc^2$ 并存，应分别渲染为粗体和公式。

> 第二段引用：混合 **粗体** 与 $a^2+b^2=c^2$ 公式，以及普通文本。

## Bug2：表格内加粗与公式

| 列 A | 列 B | 列 C |
|------|------|------|
| **粗体** | 普通文本 | $F=ma$ |
| $x_1$ | **粗体公式混合** | 123 |

## 标题内加粗与公式（PR-3 修复链）

### 标题含 **加粗** 与 $y=kx+b$

普通段落文本，包含行内代码 `var x = 1;` 与链接 [示例链接](https://example.com)。
```

> 样本覆盖矩阵：
> - 引用内加粗（Bug1 原始证据：渲染成字面 `**`）
> - 引用内行内公式（Bug1 原始证据：公式未渲染）
> - 表格 cell 内加粗 / 公式 / 混合（Bug2）
> - 标题内加粗 / 公式（Bug3-A 导出漏渲 + PR-3 修复验证）
> - 行内代码 / 链接（回归，确认 Inline AST 全类型不回归）

---

## 2. 逐 Bug 验证用例

### TC-B1 引用内加粗与公式（Bug1）

| 步骤 | 操作 | 预期 | 证据 |
|------|------|------|------|
| 1 | 打开样本文档，滚动到「Bug1」段落 | 引用块显示：**加粗文本**为粗体、`$E=mc^2$` 渲染为公式（非字面 `$`） | 截图 S1 |
| 2 | 观察第二段引用 | `**粗体**` 与 `$a^2+b^2=c^2$` 均正确渲染 | 截图 S2 |
| 3 | logcat 检查 | 无 `Fallback` 爆量；公式经 FormulaSvgService 或 flutter_math_fork 正常渲染 | logcat 过滤 `FormulaRenderer\|LATEX` |

**通过判据**：引用内不出现字面 `**` / `$` 标记；公式有视觉渲染结果（非纯文本源码）。

---

### TC-B2 表格内加粗与公式（Bug2）

| 步骤 | 操作 | 预期 | 证据 |
|------|------|------|------|
| 1 | 滚动到「Bug2」表格 | 表格 3 列 × 2 行正常布局；`**粗体**` 单元格为粗体、`$F=ma$` 渲染为公式 | 截图 S3 |
| 2 | 观察 `$x_1$` 与 `**粗体公式混合**` | 两个 cell 均正确渲染（公式非源码、粗体非字面 `**`） | 截图 S4 |
| 3 | logcat 检查 | 表格公式渲染无超时/错误爆量 | logcat |

**通过判据**：表格 cell 内 Inline AST 全类型（bold / formula）正确渲染。

---

### TC-B3 导出链路（Bug3 + PR-3/PR-4）

> 前置：编辑器内已打开样本文档；进入 App 导出菜单（编辑器右上角）。

| 步骤 | 操作 | 预期 | 证据 |
|------|------|------|------|
| 1 | 导出 PDF | 生成 PDF；标题/引用/表格内公式与加粗均正确呈现（非字面源码）；无 `Pre-render timed out` 刷屏 | 产物文件 + logcat |
| 2 | 导出 Word | 生成 .docx；公式以图片嵌入、加粗正确 | 产物文件 |
| 3 | 导出 Markdown（回归） | round-trip 后 AST 等价（引用/表格/标题 Inline 保留） | 产物 + `flutter test` 已覆盖 |

**通过判据**：三种导出产物中，标题/引用/表格内的 **加粗** 与公式不再以字符串源码形式出现（Bug3-A 修复验证）。

---

### TC-B4 导出状态栏自动消失（Bug4）

| 步骤 | 操作 | 预期 | 证据 |
|------|------|------|------|
| 1 | 触发一次成功导出（如文本导出） | 进度条出现 → Completed SnackBar（~2s）→ 状态自动复位 Idle，进度条消失 | 录屏/截图 5s 内 |
| 2 | 触发一次失败导出（如无 WebView 时导出 PDF） | Failed SnackBar（~4s）→ 自动复位 Idle | 录屏/截图 8s 内 |
| 3 | 反复快速导出 3 次 | 每次结束状态栏必消失（terminal-state guarantee，无残留） | 录屏 |

**通过判据**：无论成功/失败，导出结束后状态栏与进度条**必然**消失（Bug4 核心：不再「导出成功但状态栏永久存在」）。

---

### TC-B5 公式渲染稳定性 + 性能（Bug5 + P0-3/4/5）

#### TC-B5-1 双态切换 keep state（P0-3）

| 步骤 | 操作 | 预期 | 证据 |
|------|------|------|------|
| 1 | 点击某块级公式（rendered 态）→ 进入编辑态（显示源码） | 切换过程无空白窗口；公式源码可编辑 | 录屏 |
| 2 | 失焦/点击别处 → 回 rendered 态 | 公式**立即**恢复渲染（缓存复用），无「再点变空白」 | 录屏 + logcat |
| 3 | 快速 3 次进出编辑态 | 每次回 rendered 都不重新触发 WebView 渲染（终态缓存命中） | logcat 无新增 `renderLatex` |

**通过判据**：双态切换不再重现「点击出现、再点变空白」循环（Bug5 原始现象）。

#### TC-B5-2 telemetry 采集（P0-5）

| 步骤 | 操作 | 预期 | 证据 |
|------|------|------|------|
| 1 | 打开含公式文档，观察若干公式渲染 | 无长时间空白（先测瓶颈再谈并发） | 录屏 |
| 2 | 通过 ADI/诊断导出读取 telemetry | `queueWaitMs / renderMs / totalMs / result` 有值；无 timeout 爆量 | `FormulaSvgService.telemetryEntries` |

**通过判据**：渲染链路无「大面积空白」；telemetry 数据可采集（瓶颈可量化）。

---

## 3. 证据采集方法

### 3.0 CLI 验收（实测bug1.md §5：补齐 cli-anything / adi 验收步骤）

> 每次真机/功能验收必跑以下 CLI 自检（AGENTS.md §13.1 验证基线）：

```bash
# 1. 环境健康（ffx diag health：dart/flutter/python/adi 全 available）
python tools/ffx-cli/cli_anything/ffx/ffx_cli.py diag health

# 2. ADI 自检（跑 ADI 前必做，AGENTS.md §13.1）
python tools/ffx-cli/cli_anything/ffx/ffx_cli.py adi doctor

# 3. 项目诊断（ffx diag version / environment）
python tools/ffx-cli/cli_anything/ffx/ffx_cli.py diag version

# 4. 功能验证（Verification Orchestrator：verify / diagnose）
python tools/ffx-cli/cli_anything/ffx/ffx_cli.py capability verify
```

**wpscli / office cli 状态**：当前环境 PATH 中未发现 `wpscli` / `office` CLI。
若验收目标包含 WPS/Office 产物（docx）校验，需先安装对应 CLI 或改用
docx 结构校验（unzip + word/media 公式图检查，见 §3.1）。

### 3.1 logcat 过滤词

```bash
# 公式渲染链路（成功/降级/超时）
adb logcat | grep -E "FormulaRenderer|LATEX|Pre-render|fallback"
# 崩溃 / 致命错误
adb logcat | grep -E "FATAL|AndroidRuntime.*Exception"
```

### 3.2 截图 / 录屏

```bash
adb shell screencap -p /data/local/tmp/s.png && adb pull /data/local/tmp/s.png
# 录屏（TC-B4/TC-B5 推荐）
adb shell screenrecord --time-limit 10 /data/local/tmp/v.mp4 && adb pull /data/local/tmp/v.mp4
```

### 3.3 telemetry 读取（P0-5）

- 编辑器内：通过「诊断导出」zip 获取（`editor_app_bar.dart` 已有入口）
- 调试期：`FormulaSvgService.telemetryEntries`（RingBuffer 512 条，含 formula_id / latex_length / queue_wait_ms / render_ms / total_ms / result）

---

## 4. 回归范围（防 PR-1..5 破坏）

| 用例 | 验证点 |
|------|--------|
| 行内代码 / 链接渲染 | Inline AST 全类型不回归 |
| 代码块 / Mermaid | 共享 WebView 链路不回归 |
| 暗色 / 亮色主题切换 | 公式颜色正常 |
| 大文档滚动 | 公式懒加载无卡死 |

---

## 5. 执行记录表

| 用例 | 结果（✅/❌/⚠️） | 证据文件 | 备注 |
|------|----------------|---------|------|
| TC-B1 引用加粗/公式 | | | |
| TC-B2 表格加粗/公式 | | | |
| TC-B3 导出 PDF/Word | | | |
| TC-B4 状态栏自动消失 | | | |
| TC-B5-1 双态切换 | | | |
| TC-B5-2 telemetry | | | |

> 每项失败需记录：logcat 关键行 + 截图 + 复现步骤，按 AGENTS.md §12 Bug Fix Protocol 回填实测bug.md。
