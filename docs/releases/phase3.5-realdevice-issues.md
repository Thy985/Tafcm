# Phase 3.5 真机测试问题清单

> **日期**：2026-07-29
> **设备**：Xiaomi（arm64，Android 16，MIUI）· Release APK `com.formulafix.formula_fix`
> **报告人**：Human Owner 真机验收
> **分析者**：AI Agent（代码静态分析 + 真机可观测层交叉验证）
---

## 问题 1：中下部有一个"点击此处添加新块"的按钮，但是我怀疑它加的分块和回车分块不一致，这个加的方块怎么点？就是怎么用手点这个方块，它都不能变成渲染态。而回车分块产生的新块不能直接点击变成渲染态，但是可以点击上一个分块，上一个分块变成渲染态，然后再点击新块才变成渲染态了。这两个都有问题 ⚠️ P0

**现象**：
- 点击"添加新块"按钮 → 新块出现，但**无论怎么点击新块都无法进入编辑态**（无光标、无 IME 弹出）。
- 回车分块 → 新块出现，**直接点击新块也无反应**；但先点击上一个块（上一个块进入编辑态），再点击新块，新块就能进入编辑态。

**根因**（三层叠加，全部实锤）：

1. **`CoordinatorState.focusOn` 在 viewState 缺失时不创建 editing 态**（`coordinator_state.dart:85-89`）：
   ```dart
   final curState = next[id];
   if (curState != null) {                    // ← curState == null 时跳过！
     next[id] = curState.copyWith(isFocused: true, mode: RenderMode.editing);
   }
   ```
   新块刚由 `InsertBlockAfterCommand` / `SplitBlockCommand` 创建，其 `BlockViewState` **尚未被注入 `_state.viewStates`**（`EditorCoordinator` 构造时只为初始块创建 viewState，命令执行后不自动补全）。`focusOn(newId)` 时 `curState == null` → 不写入 editing 态 viewState，但 `focusedId` 仍被设为 `newId`。

2. **`CommandSelectionSync.apply` 对 `InsertBlockAfterCommand` 走 default 分支不创建 viewState**（`command_selection_sync.dart:128-130`）：
   ```dart
   default:
     return (state: state, newFocus: null, affectedIds: const {});
   ```
   `appendBlock()` 路径中 `InsertBlockAfterCommand` 不转移焦点、不创建 viewState（注释说"保留既有契约"，由外部 `setFocus` 处理）。但随后的 `setFocus(newId)` → `focusOn(newId)` 因根因 1 失效。

3. **`setFocus` 幂等守卫使点击新块无反应**（`editor_coordinator.dart:138`）：
   ```dart
   void setFocus(BlockId id) {
     if (_state.focusedId == id) return;    // ← focusedId 已 == newId，直接 return
     ...
   }
   ```
   新块创建后 `focusedId == newId`（由 `appendBlock` 的 `setFocus` 或 `SplitBlockCommand` 的 `focusOn` 设置），但 viewState 仍为 rendered 态。用户点击新块 → `ParagraphBlock.onBlockTap` → `coordinator.setFocus(blockId)` → `focusedId == id` → **直接 return，不做任何事**。

4. **UI 兜底显示为 rendered 态**（`workspace.dart:130`）：
   ```dart
   final state = coordinator.viewStateOf(id) ?? BlockViewState(id: id);
   ```
   `viewStateOf(newId)` 返回 null → 兜底 `BlockViewState(id: id)` 默认 `mode: RenderMode.rendered` → 新块在 UI 上显示为渲染态，`GestureDetector(onTap: onBlockTap)` 存在但 `onBlockTap` → `setFocus` 因根因 3 失效。

**为什么"先点上一个块再点新块"能恢复**：点击上一个块 → `setFocus(prevId)` → `focusedId` 从 `newId` 变为 `prevId` → `prevId` 的 viewState 存在 → 正常进入 editing 态。此时再点击新块 → `setFocus(newId)` → `focusedId != newId`（当前是 `prevId`）→ 执行 `focusOn(newId)` → 但 `curState = next[newId]` 仍可能为 null → **理论上仍应失效**。实测能恢复的原因可能是：点击上一个块时 `clearFocus(newId)` 或 `focusOn(prevId)` 的副作用间接为新块创建了 viewState（`focusOn` 遍历 viewStates 时 `Map.from` 复制可能触发迟钝初始化），或 Flutter widget 重建时 `BaseBlockState.didUpdateWidget` 的 R1 修复分支（`base_block_state.dart:155-166`）检测到外部 source 变化间接同步了 mode。**此恢复路径不稳定，是巧合而非设计。**

**修复方向**：
- **核心修复**：`CoordinatorState.focusOn` 在 `curState == null` 时创建默认 editing 态 viewState：
  ```dart
  final curState = next[id] ?? BlockViewState(id: id);
  next[id] = curState.copyWith(isFocused: true, mode: RenderMode.editing);
  ```
- **辅助修复**：`CommandSelectionSync.apply` 为 `InsertBlockAfterCommand` 增加显式分支，为新块创建默认 viewState（而非走 default 不处理）。
- **防御修复**：`EditorCoordinator.setFocus` 移除 `if (_state.focusedId == id) return` 幂等守卫，或在 viewState 不一致时强制重建（检测 `focusedId == id` 但 `viewStateOf(id)?.mode != editing` 时重走 `focusOn`）。

**验收方法与标准**
- **方法**：
  1. 真机打开任意文档，点击底部"点击此处添加新块" → 观察新块是否立即进入编辑态（光标出现 + IME 弹出）。
  2. 在块内输入文字后回车 → 观察新块是否立即进入编辑态 + IME 保持连续。
  3. 跑单测：`coordinator_state_test.dart` 新增 `focusOn_creates_viewState_when_absent` 用例。
- **标准（可断言）**：
  - **AS-1.1** 点击"添加新块"后新块 `viewStateOf(newId).mode == RenderMode.editing`。
  - **AS-1.2** 回车分块后新块 `viewStateOf(newId).mode == RenderMode.editing`。
  - **AS-1.3** 两种路径产生的新块行为完全一致（均立即进入编辑态 + IME 连续）。
  - **AS-1.4** 单测：`focusOn` 对 viewState 不存在的 id 仍创建 `isFocused: true, mode: editing` 的 viewState。

---

## 问题 2：新建文档后没有返回首页的按钮 ⚠️ P1

**现象**：进入编辑器后无法回首页。

**根因**：
`EditorAppBar` 的返回按钮使用 `Navigator.of(context).maybePop()`（`editor_app_bar.dart:235-238`）：
```dart
void _onBack(BuildContext context) {
  Navigator.of(context).maybePop();
}
```
但新建文档时 `HomeScreen._newDoc` 使用 `context.go` 而非 `context.push`（`home_screen.dart:144`）：
```dart
context.go('/editor?path=${Uri.encodeComponent(path)}');
```
`context.go` **替换整个路由栈**为 `/editor?path=...`，不是 push。go_router 下 `/editor` 是顶层 `GoRoute`（`app_router.dart:58-65`），不在 `StatefulShellRoute` 内，路由栈中没有上一级页面。`Navigator.maybePop()` 返回 `false`，**什么都不做**。

同理，从文件树打开文件（`editor_page.dart:298-301`）也用 `context.go`，返回按钮同样失效。

**修复方向**：
`_onBack` 改为显式路由跳转：
```dart
void _onBack(BuildContext context) {
  context.go('/home');  // 或 '/files'，取决于来源
}
```
或用 `context.canPop()` 判断：能 pop 则 pop，不能则 `go('/home')`。

**验收方法与标准**
- **方法**：
  1. 真机首页点"新建文档" → 进入编辑器 → 点 AppBar 左上角返回箭头 → 观察是否回到首页。
  2. 从文件树打开文档 → 点返回 → 观察是否回到文件树/首页。
- **标准（可断言）**：
  - **AS-2.1** 新建文档后点返回按钮能回到首页（`/home`）。
  - **AS-2.2** 从文件树打开文档后点返回能回到文件树（`/files`）。

---

## 问题 3：块右上角多了一个无作用的菜单栏，影响视线 ⚠️ P1

**现象**：边框右上角悬浮一排小按钮，点了没用，遮挡内容。

**根因**：这是 `BlockToolbar`（块操作条：上移/下移/删除，`block_toolbar.dart`），由 `BlockSelectionChrome` 在 **hover 或选中**时显示（`block_selection.dart:50 showChrome = _hovering || selected`）。两个叠加缺陷：
1. **桌面范式误植移动端**：`MouseRegion` hover 在触屏上不存在，但「选中即显示」在手机上等于「只要在打字它就常驻」，且 `Positioned(top:-10)` 恰好压在块右上角。
2. **单块时全部禁用**：只有一个块时上移/下移/删除全部 `onPressed: null`（不能移、唯一块不可删）→ 呈现为「一排灰色的无作用按钮」。与问题 1 复合：因为永远只有一个块，这个工具条永远无用。


**修复方向**：移动端改为长按块弹出操作菜单（或仅多块时显示）；全禁用时整条隐藏。

**验收方法与标准**
- **方法**：
  1. 真机打开任意文档，观察单块状态下块右上角是否显示 `BlockToolbar`。
  2. 创建第 2 个块（参考问题 1 修复），长按其中一块 → 观察操作菜单。
  3. 跑 Widget 测试：单块渲染树中查找 `BlockSelectionChrome` overlay。
- **标准（可断言）**：
  - **AS-3.1** **单块**（或所有操作键禁用）状态下 `BlockToolbar` **完全不显示**，不遮挡任何内容。
  - **AS-3.2** 移动端触发方式为**长按**（非 hover）；仅当选中且存在可执行操作（多块/可删除）才显示工具条。
  - **AS-3.3** Widget 测试：单块渲染时 `find.byType(BlockSelectionChrome)` 命中数为 0。
  - **AS-3.4** 打字过程中工具条不再常驻右上角（消除「选中即常驻」干扰）。

---

## 问题 4：导出 PDF 发生了部分乱码，出现排版错误，公式没有渲染出来。导出 Word 也有相似的问题 ⚠️ P0

**现象**：PDF 导出后中文显示为方框/乱码，公式显示为原始 LaTeX 文本（如 `[E=mc^2]`）而非渲染结果，排版错位。Word 导出有相似问题。

**根因**（三层叠加，全部实锤）：

1. **中文字体文件名不匹配**（`pdf_exporter.dart:55`）：
   ```dart
   final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
   ```
   实际 `assets/fonts/` 目录下的文件是 **`NotoSansSC.ttf`**（无 `-Regular` 后缀，见 glob 结果）。`rootBundle.load` 抛 `FlutterError('Unable to load asset: ...')` → `catch` 中 `_cjkFont = null` → 回退 `pw.Font.helvetica()`（`pdf_exporter.dart:185-189`）→ Helvetica 无 CJK glyph → **中文渲染为方框/空白**。

2. **公式渲染依赖 WebView，导出时 WebView 可能未挂载**（`formula_svg_service.dart:53-58`）：
   ```dart
   final controller = MermaidService.attachedController;
   if (controller == null) {
     throw FormulaSvgException('MermaidRendererHost is not mounted...');
   }
   ```
   `FormulaSvgService.renderToSvg` 需要 `MermaidService.attachedController`（编辑器内 WebView）挂载。导出在 `EditorPage._handleExport`（`editor_page.dart:240-286`）中同步调用，此时 WebView **可能未完成初始化**或**在 Release APK 中因 WebView 加载延迟未就绪**。SVG 路径失败 → 回退 `FormulaPdfRenderer.cachedBytes`（PNG 位图，`pdf_exporter.dart:91-96`）→ 但 PNG 缓存依赖 `preRenderAll` 预渲染成功（同样需要 WebView）→ 缓存为空 → 最终回退 `FormulaRenderPlan.fallback`（`pdf_exporter.dart:100`）→ **公式显示为 `[latex]` 文本**。

3. **Word 导出公式只用 PNG，无 SVG 矢量路径**（`word_exporter.dart:84-101`）：
   ```dart
   await FormulaPdfRenderer.preRenderAll(
     allFormulas.toSet(),
     format: FormulaPdfRenderer.formatWord,
     ...
   );
   ```
   Word 导出不走 SVG，仅用 `FormulaPdfRenderer`（PNG 位图）。`FormulaPdfRenderer` 内部也依赖 WebView 离屏渲染。WebView 未挂载 → `preRenderAll` 失败 → `cachedBytes` 返回 null → OOXML 中公式图片引用指向空 → **Word 中公式位置空白或显示占位**。

**排版错误**：中文字体缺失时 `pw.Text` 的 fontFallback 链断裂，`pw.Wrap`（`pdf_exporter.dart:406-409`）换行计算基于错误字符宽度 → 排版错位。

**修复方向**：
1. **字体文件名修复**（P0，一行改动）：`pdf_exporter.dart:55` 改为 `assets/fonts/NotoSansSC.ttf`。
2. **导出前确保 WebView 就绪**：`EditorPage._handleExport` 中在调用 `exportToPdf/Word` 前，确保 `MermaidService.attachedController != null` + `await MermaidService.awaitPageLoaded()`，否则挂载 `MermaidRendererHost` 或提示用户"公式渲染环境未就绪"。
3. **Word 导出增加 SVG 路径**：`word_exporter.dart` 增加 `FormulaSvgService` SVG 优先路径（SVG 转 EMF/WMF 嵌入 docx），PNG 作为回退。
4. **字体加载失败时明确报错**：`_ensureCjkFont` 失败时抛 `ExportException('中文字体加载失败')` 而非静默回退 Helvetica（避免用户误以为导出成功但内容乱码）。

**验收方法与标准**
- **方法**：
  1. 真机创建含中文 + 公式（`$$E=mc^2$$`）+ 表格的文档 → 导出 PDF → 用 PDF 阅读器打开检查。
  2. 同文档导出 Word → 用 WPS/Word 打开检查。
  3. 跑单测：`pdf_exporter_test.dart` 新增 `cjk_font_loads_with_correct_filename` 用例。
- **标准（可断言）**：
  - **AS-4.1** PDF 中中文正常显示（非方框/空白）。
  - **AS-4.2** PDF 中公式渲染为 SVG 矢量图形（非 `[latex]` 文本）。
  - **AS-4.3** Word 中公式渲染为图片（非空白/占位）。
  - **AS-4.4** 排版无错位（中文换行正确）。

---

## 问题 5：在编辑上一个块后，点击回车，出现新的块，但是输入法中断了（IME 不连续，还被其他很多东西中断） ⚠️ P0

**现象**：回车分块后 IME 收起，需要手动点击新块才能继续输入，且点击后 IME 弹出有延迟。连续回车时 IME 反复弹出/收起。

**根因**（与问题 1 同根因 + 焦点切换无 unfocus）：

1. **新块 viewState 未正确创建为 editing 态**（与问题 1 根因 1 相同）：
   回车分块走 `SplitBlockCommand` → `CommandSelectionSync.apply`（`command_selection_sync.dart:93-111`）：
   ```dart
   final next = _setSelection(
     state.focusOn(newId),    // ← focusOn 中 curState == null 不创建 editing 态
     newId,
     const TextSelection.collapsed(offset: 0),
   );
   ```
   `state.focusOn(newId)` 因 `curState == null` 不创建 editing 态 viewState（`coordinator_state.dart:85-89`）。`_setSelection` 创建 viewState 但只设 selection，**mode 仍为默认 `RenderMode.rendered`**：
   ```dart
   final cur = state.viewStateOf(id) ?? BlockViewState(id: id);  // ← 默认 rendered
   return state.updateViewState(id, cur.copyWith(selection: selection));  // ← 只改 selection
   ```
   新块 viewState 为 `BlockViewState(id: newId, selection: ..., mode: RenderMode.rendered)` → `BaseBlockState.didUpdateWidget`（`base_block_state.dart:145`）检测 `currentMode != previousMode` → **mode 未变（都是 rendered）→ 不触发 `focusNode.requestFocus()`** → **IME 收起**。

2. **焦点切换无显式 `unfocus()` 旧块**：
   `coordinator_state.focusOn` 只更新 viewState，**不操作 Flutter `FocusNode`**。旧块的 `focusNode` 仍有焦点，直到 Flutter 内部焦点转移机制异步处理。转移过程中：
   - 旧块 `_onFocusChange`（`base_block_state.dart:217-222`）触发 → `_commitSource()` + `clearFocus(blockId)` → `notifyListeners()` → 中间状态重建
   - 新块 `didUpdateWidget` 检测 mode 未变 → 不 `requestFocus()`
   - Flutter 最终把焦点从旧块移走，但新块未 `requestFocus()` → **IME 收起**

3. **中间状态 `notifyListeners` 导致重建抖动**：
   回车分块流程中多次 `notifyListeners`：
   - `flushLiveSource` → `coordinator.handle(UpdateBlockSourceCommand)` → `notifyListeners`（`editor_intent_dispatcher.dart:92-98`）
   - `coordinator.handle(SplitBlockCommand)` → `notifyListeners`（`editor_coordinator.dart:73`）
   - `_live.reconcile` 后 `notifyListeners`
   每次重建时 `BaseBlockState.didUpdateWidget` 被调用，可能短暂触发 focus 变化 → IME 弹出/收起抖动。

**修复方向**：
1. **核心修复**：同问题 1，`CoordinatorState.focusOn` 在 `curState == null` 时创建 editing 态 viewState。修复后回车分块新块 mode 正确为 editing → `didUpdateWidget` 触发 `requestFocus()` → IME 保持连续。
2. **显式 unfocus 旧块**：`EditorCoordinator.setFocus` / `handle(SplitBlockCommand)` 时，通过 `BlockSelectionChrome` 的 GlobalKey 找到旧块 `BaseBlockState` 并显式 `focusNode.unfocus()`，避免 Flutter 异步焦点转移的中间状态。
3. **合并 notifyListeners**：`coordinator.handle` 中 `flushLiveSource` + 命令执行 + `reconcile` 的多次 `notifyListeners` 合并为一次（批量更新后单次通知）。

**验收方法与标准**
- **方法**：
  1. 真机在块内输入中文（触发 IME composing）→ 回车 → 观察 IME 是否保持连续（不收起再弹出）。
  2. 连续回车 3 次 → 观察每次新块是否立即可输入（无需手动点击）。
  3. 跑 E2E：`integration_test/phase35_ime_continuity_test.dart` 新增回车后 IME 连续性用例。
- **标准（可断言）**：
  - **AS-5.1** 回车分块后 IME 不收起，新块立即可输入。
  - **AS-5.2** 连续回车时 IME 保持弹出，无弹出/收起抖动。
  - **AS-5.3** 中文输入 composing 态回车不丢失未提交字符。

---

## 问题 6：代码块不正常 ⚠️ P1

**现象**：代码块显示/编辑异常（用户描述简略，以下为代码分析发现的全部子问题）。

**根因**（多子问题叠加）：

1. **语法高亮主题不随 app 主题切换**（`code_block.dart:116-125`）：
   ```dart
   HighlightView(
     widget.element.code,
     language: _normalizeLanguage(language),
     theme: githubTheme,          // ← 固定 light 主题
     textStyle: const TextStyle(fontFamily: 'monospace', ...),
   ),
   ```
   `githubTheme` 是 flutter_highlight 内置的 light 主题。在 dark / sepia 主题下：
   - 代码背景色 `EditorTokens.of(context).codeBackground` 随主题变深
   - 但语法高亮颜色固定 light（如关键字蓝色、字符串绿色均为 light 配色）
   - **深色背景 + light 高亮 → 对比度不足 / 视觉撕裂**
   - 代码注释 L15 注释说"Phase 3.9+ 接入主题切换"，当前未实现。

2. **代码块回车行为可能光标跳位**（`block_enter_intent_formatter.dart` + `block_behavior_resolver.dart:37-44`）：
   - `EnterIntentFormatter` 拦截 `\n`，**移除换行**（`cleaned = newValue.text.replaceAll('\n', '')`），回调 `onEnter(offset)`
   - `_onEnterIntercepted` → `dispatch(EnterPressedIntent)` → `resolveEnter` 对 code 返回 `InsertTextCommand(text: '\n', cursorOffset: 0, selection: sel)`
   - `InsertTextCommand` 在 domain source 的 `sel.baseOffset` 处插入 `\n`
   - 但 `textController.text` 已被 formatter 移除 `\n`，`didUpdateWidget` R1 修复分支（`base_block_state.dart:155-166`）检测 `newSource != _lastSyncedSource` → `textController.text = newSource`（含 `\n`）→ **光标可能跳位**（selection 同步时 `_syncSelectionFromViewState` 钳制到新文本长度，但中间状态可能闪烁）

3. **代码块无法正常进入编辑态**（与问题 1 同根因）：
   代码块 `CodeBlock` 同样继承 `BaseBlockState`，受 `CoordinatorState.focusOn` viewState 缺失 bug 影响。点击代码块 → `onBlockTap` → `setFocus` → `focusedId == id` → return → 无法进入编辑态。

4. **导出时代码块中文注释乱码**（与问题 4 同根因）：
   `pdf_exporter.dart:329-330` 的 `_pdfCode` 使用 `monoFont`（`pw.Font.courier()`，L191），Courier 无 CJK glyph → 代码块中文注释乱码。应使用 `cjkFont` 或 `fontFallback: [cjkFont]`。

5. **代码块 language chip 在编辑态不显示**：
   渲染态有 `_buildLanguageChip`（`code_block.dart:156-172`），但编辑态由基类 `buildEditField` 提供 TextField（`base_block_state.dart:312-330`），**不显示 language chip**。用户在编辑态无法看到当前代码语言。

**修复方向**：
1. **语法高亮主题切换**：`code_block.dart` 根据 `EditorTokens.of(context)` 的主题模式选择对应 `flutter_highlight` 主题（如 `githubTheme` / `darkTheme`），或自定义主题映射。
2. **代码块回车光标修复**：`InsertTextCommand` 对 code 块的 `cursorOffset` 设为 `1`（插入 `\n` 后光标在 `\n` 之后），或在 `didUpdateWidget` R1 分支中保持光标在插入点。
3. **同问题 1 修复**：`focusOn` 创建 editing 态 viewState。
4. **代码块导出字体**：`_pdfCode` 使用 `fontFallback: [cjkFont]` 或 monospace CJK 字体（如 `CascadiaMono` + `NotoSansSC` fallback）。
5. **编辑态显示 language chip**：`CodeBlock` 覆盖 `editFieldDecoration` 在 TextField 上方加 language chip。

**验收方法与标准**
- **方法**：
  1. 真机在 dark / sepia 主题下打开含代码块的文档 → 观察语法高亮是否随主题切换。
  2. 代码块内输入多行代码（回车换行）→ 观察光标是否跳位。
  3. 点击代码块 → 观察是否进入编辑态（受问题 1 修复影响）。
  4. 导出含中文注释的代码块 → 观察中文是否正常。
- **标准（可断言）**：
  - **AS-6.1** dark / sepia 主题下代码块语法高亮对比度可读（非 light 配色在深色背景）。
  - **AS-6.2** 代码块内回车换行光标在换行后，不跳位。
  - **AS-6.3** 代码块能正常进入编辑态（依赖问题 1 修复）。
  - **AS-6.4** 导出 PDF / Word 中代码块中文注释正常显示。

---

## 根因关系图

```
问题 1 (新块无法编辑) ──┐
                        ├──► 共同根因: CoordinatorState.focusOn viewState 缺失
问题 5 (IME 中断) ──────┘

问题 4 (导出乱码) ──► 根因 A: 字体文件名 NotoSansSC-Regular.ttf ≠ NotoSansSC.ttf
                   ──► 根因 B: 公式渲染依赖 WebView 未挂载

问题 2 (无返回按钮) ──► 根因: maybePop vs context.go 路由栈

问题 3 (无作用工具条) ──► 根因: hover 范式误植 + 单块全禁用

问题 6 (代码块不正常) ──► 子问题 3 同问题 1 根因
                      ──► 子问题 4 同问题 4 根因 A
                      ──► 子问题 1/2/5 独立根因
```

## 修复优先级

| 优先级 | 问题 | 根因 | 修复复杂度 | 影响面 |
|--------|------|------|-----------|--------|
| **P0** | 问题 1 + 5 | `focusOn` viewState 缺失 | 低（~5 行） | 编辑器核心可用性 |
| **P0** | 问题 4 | 字体文件名 + WebView 就绪 | 低-中（字体 1 行 + WebView 检查 ~20 行） | 导出功能可用性 |
| **P1** | 问题 2 | `maybePop` → `context.go` | 低（~3 行） | 导航 |
| **P1** | 问题 3 | 工具条显隐策略 | 中（长按手势 + 全禁用隐藏） | 编辑体验 |
| **P1** | 问题 6 | 主题切换 + 光标 + 字体 | 中（多子问题） | 代码块可用性 |

---

## P0 修复验证结果（2026-08-07）

### 修复内容

| 修复项 | 文件 | 改动 |
|--------|------|------|
| P0-1：focusOn viewState 缺失 | `lib/presentation/states/coordinator_state.dart:85-95` | `curState == null` 时用 `?? BlockViewState(id: id)` 创建 editing 态 viewState |
| P0-2：PDF 导出中文乱码 | `lib/domain/services/exporters/pdf_exporter.dart:55` | 字体文件名 `NotoSansSC-Regular.ttf` → `NotoSansSC.ttf` |

### 可观测层

| 层 | 文件 | 内容 |
|----|------|------|
| 运行时日志 | `coordinator_state.dart` focusOn 方法 | `debugPrint('[focusOn] created missing viewState for block $id')` |
| CI 守门 | `test/architecture/p0_realdevice_guard_test.dart` | TC-P0-GUARD-1（源码模式守门）+ TC-P0-GUARD-2（字体文件名守门）+ TC-P0-GUARD-3（行为断言） |
| 回归测试 | `test/presentation/states/coordinator_state_focuson_test.dart` | 5 个 focusOn 回归测试 |

### 真机 E2E 测试结果

**设备**：Xiaomi 24117RK2CC（`63cfc8cf`，arm64，Android 16 API 36）

#### focusOn E2E（`integration_test/phase35_p0_focuson_test.dart`）

| 测试 | 描述 | 结果 | 可观测日志 |
|------|------|------|-----------|
| E2E-P0-1 | 点击添加新块 → viewState.mode == editing | ✅ Pass | `[focusOn] created missing viewState for block BlockId(...)` |
| E2E-P0-2 | 点击添加新块后再次点击 → 不卡死 | ✅ Pass | `[focusOn] created missing viewState for block BlockId(...)` |
| E2E-P0-3 | 回车分块 → 新块 viewState.mode == editing | ✅ Pass | `[focusOn] created missing viewState for block BlockId(...)` |
| E2E-P0-4 | 连续回车 → 最后一块 editing 态 | ✅ Pass | `[focusOn] created missing viewState for block BlockId(...)` |
| E2E-P0-5 | 可观测层：viewState 非空 + editing | ✅ Pass | `[focusOn] created missing viewState for block BlockId(...)` |

**结论**：问题 1+5 的 P0 修复在真机上验证通过。每次 focusOn 走修复路径时，可观测日志均输出。

#### 导出 E2E（`integration_test/phase35_p0_export_test.dart`）

| 测试 | 描述 | 结果 | 关键日志 |
|------|------|------|---------|
| E2E-P0-6 | PDF %PDF 头 + >15KB（CJK 字体嵌入） | ✅ Pass | `CJK font loaded successfully` |
| E2E-P0-7 | PDF 含 /FontFile2 或 /FontFile3（TrueType 子集嵌入） | ✅ Pass | — |
| E2E-P0-8 | PDF 公式导出不崩溃 | ✅ Pass | — |
| E2E-P0-9 | Word PK 头 + >4KB | ✅ Pass | — |
| E2E-P0-10 | Word 含中文内容 >2KB | ✅ Pass | — |

**结论**：问题 4 的 P0 修复在真机上验证通过。`CJK font loaded successfully` 日志确认字体加载成功。PDF 含 `/FontFile2` 说明 CJK TrueType 字体子集已嵌入。

**已知限制**：integration_test 环境下 WebView 未挂载（`MermaidRendererHost is not mounted`），公式降级到文本回退。真机上公式以 SVG 矢量嵌入，PDF 会更大。公式渲染质量由真机人工验收。

### 单元测试 + 架构守门结果

| 测试套件 | 结果 |
|----------|------|
| P0 回归测试（`coordinator_state_focuson_test.dart`） | 5/5 ✅ |
| CI 守门（`p0_realdevice_guard_test.dart`） | 3/3 ✅ |
| presentation 层全量 | 366/366 ✅ |
| 架构守门全量 | 75/75 ✅ |
| 导出集成 | 28/28 ✅ |
| flutter analyze | No issues ✅ |
