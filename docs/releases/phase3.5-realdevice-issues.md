# Phase 3.5 真机测试问题清单与根因分析

> **日期**：2026-07-29
> **设备**：Xiaomi（arm64，Android 16，MIUI）· Release APK `com.formulafix.formula_fix`
> **报告人**：Human Owner 真机验收 · AI Agent 根因定位
> **结论速览**：6 个问题中 **5 个属于「真机前就应发现」**（代码评审 / Widget 测试 / 手机视口 golden 可拦截），仅问题 6 的文件选择器空列表部分依赖真机才能确认。**问题 1 与 4 是编辑内核级缺陷（P0）**，比 UI 还原度问题严重。

---

## 问题 1：新建文档只有一个"边框"，回车不分块，无即点即插 ⚠️ P0

**现象**：新文档只有一个带边框输入区；连续写多行共享同一边框（同一格式）；无法插入新块；没有移动端「点击空白处插入新块」；插入新块时上一块也不渲染成预览。

**根因**（三层叠加，全部实锤）：

1. **回车分裂从未接入生产 UI**。`SplitBlockCommand` 只有骨架（`command_handler.dart:85,121` 定义+分发），**仅在 prototype demo 和测试中被构造，生产代码没有任何地方触发它**。块内 `TextField` 是多行模式，软键盘回车只是往同一块的 source 里塞 `\n`（`base_block_state.dart:357 _onTextChanged` 只做 live 同步 + 列表续行），所以所有行都留在同一个 ParagraphElement 里。
2. **无「点空白追加块」交互**。`editor_shell.dart:223` 的 GestureDetector 只处理缩放/双击（焦点模式），`workspace.dart` 没有 tap-empty-area 逻辑——移动端最基本的「即点即插」完全缺失。
3. **上一块不渲染是连带症状**。失焦→渲染（hot→cold）机制本身存在且工作正常（`RenderMode.rendered`），但因为 1/2 导致永远只有一个块、焦点从不转移，渲染路径永远走不到。**不是渲染 bug，是分块 bug 的下游表现**。

**新文档初始结构佐证**：`MarkdownParser.parse('')` 恰好产出 1 个空 ParagraphElement（`markdown_parser.dart:251,259`）——这就是那个唯一的边框。

**应在真机前发现？——是（严重失守）**。「回车分裂块」是块编辑器的第一交互，Widget 测试即可覆盖；`SplitBlockCommand` 定义了却无生产调用方，`flutter analyze` 虽不报，但代码评审和 E2E 用例设计阶段都应发现「13 个 E2E 里没有一个测回车分块」。

**修复方向**：① 块内 TextField 拦截 newline（检测 `\n` 插入）→ 派发 `SplitBlockCommand`；② workspace 尾部空白区加 GestureDetector → 追加新 Paragraph 块并聚焦（即点即插，同时旧块自动失焦→渲染，用户预期的「上一块同时渲染」随之满足）；③ 补 E2E：输入两行文字回车分块 → 断言两个块且第一块为渲染态。

**验收方法与标准**
- **方法**：
  1. 真机 / 模拟器（Android 16，手机视口 393×851）新建空白文档。
  2. 在块内输入「第一行内容」，光标置于末尾，触发**软键盘回车**（IME `newline`）。
  3. 继续观察：再键入第二块文字；随后点击工作区**尾部空白区域**。
  4. 点击第一块使其**失焦**，观察其形态。
  5. 跑 E2E：`输入两行 → 软键盘回车 → 断言`。
- **标准（可断言）**：
  - **AS-1.1** 软键盘回车后文档分裂为 **≥2 个块**，`TextField` 数量等于块数，光标落在**新块开头**，原块文本零丢失。
  - **AS-1.2** 桌面/硬键盘回车同样分裂（回归 `SplitBlockCommand`，非仅 IME 路径）。
  - **AS-1.3** 点击尾部空白 → **追加一个新 Paragraph 块并自动聚焦**（即点即插）。
  - **AS-1.4** 块失焦后进入 `RenderMode.rendered`（Markdown 预览态）——「上一块同时渲染」随之满足。
  - **AS-1.5** E2E 断言：回车后存在 2 个 `BlockWidget`，且第一个命中渲染态文本、非原始 `\n` 拼接。

---

## 问题 2：新建文档后没有返回首页的按钮 ⚠️ P1

**现象**：进入编辑器后无法回首页。

**根因**：返回按钮**其实存在**（`editor_app_bar.dart:107` leading 箭头），但它调用 `Navigator.of(context).maybePop()`（`:237`）。而所有进入编辑器的入口都用 **`context.go('/editor?...')`**（`home_screen.dart:56,66,73`、`file_manager_screen.dart:96`、`app_router.dart:182`）——go_router 的 `go()` 是**替换**导航栈而非压栈，栈里没有上一页，`maybePop()` 静默无操作 → 按钮点了没反应，等于没有。

**应在真机前发现？——是**。router 级 Widget 测试（go 进编辑器→点返回→断言回到 /home）即可拦截；这也正是 ADR-0018 v1.1 Decision 1「Editor 在 Shell 之外」要冻结导航语义的原因。

**修复方向**：进入编辑器统一改 `context.push('/editor?...')`（保留返回栈）；`_onBack` 兜底：`canPop ? pop() : context.go('/home')`。与 ADR-0018 Decision 4 的启动决策链一致。

**验收方法与标准**
- **方法**：
  1. 从 `/home` 点「最近文档」或 `/files` 打开任一文档 → 进入 `/editor`。
  2. 点击 AppBar 左侧 leading 箭头。
  3. 断言当前 route 回到来源屏；用 go_router 测试验证栈深度。
- **标准（可断言）**：
  - **AS-2.1** 进入编辑器走 `context.push`（保留返回栈），leading 箭头**可见且可点**。
  - **AS-2.2** 点击返回 → 精确回到进入前的屏（`/home` 或 `/files`），**不出现空白/卡死**。
  - **AS-2.3** 兜底：若直接 deep-link `/editor`（无栈），返回落到 `/home`（与 ADR-0018 Decision 4 启动决策链一致）。
  - **AS-2.4** router Widget 测试断言：`push('/editor') → tap(back) → route == '/home'`，且 `Navigator.canPop == false` 时不崩溃。

---

## 问题 3：块右上角多了一个无作用的菜单栏，影响视线 ⚠️ P1

**现象**：边框右上角悬浮一排小按钮，点了没用，遮挡内容。

**根因**：这是 `BlockToolbar`（块操作条：上移/下移/删除，`block_toolbar.dart`），由 `BlockSelectionChrome` 在 **hover 或选中**时显示（`block_selection.dart:50 showChrome = _hovering || selected`）。两个叠加缺陷：
1. **桌面范式误植移动端**：`MouseRegion` hover 在触屏上不存在，但「选中即显示」在手机上等于「只要在打字它就常驻」，且 `Positioned(top:-10)` 恰好压在块右上角。
2. **单块时全部禁用**：只有一个块时上移/下移/删除全部 `onPressed: null`（不能移、唯一块不可删）→ 呈现为「一排灰色的无作用按钮」。与问题 1 复合：因为永远只有一个块，这个工具条永远无用。

**应在真机前发现？——是**。设计评审阶段就该问「触屏没有 hover，这个 chrome 的移动端形态是什么」；单块全禁用状态 Widget 测试可断言。

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

## 问题 4：工具栏按钮把已删除的内容加回来 ⚠️ P0

**现象**：点加粗（B）等按钮，加粗生效的同时，之前删掉的文字复活；I/Code/H1 等同样；Link/Quote 无复活但行为异常。

**根因**（ADR-0012 双状态同步缺口，路径完整确认）：

- 打字/删除只更新 **live 层**（`base_block_state.dart:365 updateLiveSource`），**domain 层要到失焦才提交**（ADR-0012 设计）。
- 但工具栏命令在**聚焦态**执行：`_handleWrapOrInsert` 用实时 selection（`coordinator.focusedSelection`，§2.7.1）构造命令，而 `CommandHandler._handleWrapSelection/_handleInsertText`（`command_handler.dart:209/187`）读的是 `editor.getBlock` —— **过期的 domain 源**。
- 结果：命令在「删除前的旧文本」上做包裹 → 命令完成后 `reconcile` + `didUpdateWidget` 把 `textController.text` 覆盖为「旧文本+格式」→ 被删文字复活。
- **缺失环节**：工具栏执行前没有把 live 文本 flush 成 `UpdateBlockSourceCommand`。
- Link/Quote「无复活但异常」的差异：Quote/H1/OL 走 `_handleInsert`（行首前缀+块类型转换），路径不同但同样读过期 domain，症状表现为前缀插错位置/转换基于旧文本。

**应在真机前发现？——是（测试设计缺口）**。纯逻辑 bug，与设备无关；Widget 测试「输入→删除→立即点 B→断言文本」即可拦截。现有测试都是「干净文本上点按钮」，没有覆盖「编辑中途点按钮」这一真实序列。

**修复方向**：`markdown_toolbar` 每个 handler 开头先 flush：若 live source ≠ domain source，先派发 `UpdateBlockSourceCommand(liveText)` 再构造格式命令（或 coordinator 提供 `flushLiveSource(blockId)` 原子入口）。补「edit-then-format」E2E。

**验收方法与标准**
- **方法**：
  1. 在块内输入「abcdef」，选中「cde」删除（或退格）。
  2. **不先移焦**，立即点 B（加粗）/ I / Code / H1 任一格式按钮。
  3. 断言文本内容与已删文字状态；对 Link/Quote 同样测前缀/转换位置。
  4. 跑 Widget 测试：`输入→删除→立即点 B→断言文本`。
- **标准（可断言）**：
  - **AS-4.1** 编辑中途点**任何**格式按钮，已删除文本**不复活**（结果应为删后文本 + 格式）。
  - **AS-4.2** 格式命令基于**当前真实文本**（live 先 flush 成 domain 后构造），而非过期 domain 源。
  - **AS-4.3** Link/Quote 前缀插入与块类型转换位置正确，基于当前文本（不基于旧文本）。
  - **AS-4.4** Widget 测试断言：删后文本「abf」点 B → 渲染为 `**abf**`，无「cde」复活。
  - **AS-4.5** E2E「edit-then-format」序列执行后文档字符数**不膨胀**（无隐藏旧字符）。

---

## 问题 5：OL / UL / Task / 模板菜单按钮不存在 ⚠️ P2（实现在，可发现性差）

**现象**：工具栏只见 B/I/H1-H3/Code/Link/Quote，后面 4 个按钮没有。

**根因**：按钮**全部存在**（`markdown_toolbar.dart:189-208`），工具栏是 `SingleChildScrollView(horizontal)`。手机窄屏下 OL/UL/Task/+ 被推出屏幕右缘，而**没有任何「可横滑」提示**（无渐变遮罩/箭头/滚动条）→ 用户合理地认为不存在。全工程只有 `editor_shell.dart:251` 一处使用该工具栏，不存在手机精简版。

**应在真机前发现？——是**。Tier 2 golden 若用手机尺寸视口（如 393×851）截工具栏就会看到截断。此前 golden 多为桌面宽度，掩盖了溢出。

**修复方向**：右缘加渐变遮罩+箭头提示；或窄屏两行排布/收纳次级按钮进「⋯」。补手机视口 golden。

**验收方法与标准**
- **方法**：
  1. 真机（窄屏 393×851）打开编辑器，检查工具栏右缘是否可见后续按钮。
  2. 横向滑动工具栏，确认 OL/UL/Task/+ 可达。
  3. 桌面/模拟器手机视口跑 golden，截取工具栏全宽。
- **标准（可断言）**：
  - **AS-5.1** 所有声明按钮（B/I/H1-H3/Code/Link/Quote/OL/UL/Task/+）在窄屏**全部可达**（可横滑、或两行排布、或收纳进「⋯」）。
  - **AS-5.2** 提供明确「可横滑」提示（右缘渐变遮罩 / 箭头 / 滚动条），或次级按钮收纳后有可见入口。
  - **AS-5.3** 手机视口 golden 覆盖工具栏**全按钮**，无 offstage 隐藏的必需按钮。
  - **AS-5.4** Widget 测试断言：`MarkdownToolbar` 内含 OL/UL/Task/Template 四个按钮实例（非条件移除）。

---

## 问题 6：导入功能异常（选择器空列表 + 打开方式无本 APP）⚠️ P1

**现象 A**：APP 内导入弹出系统文件选择器，但里面看不到刚下载的 .md 文件。
**现象 B**：在其他应用里对 .md 用「打开方式」，列表里没有 FormulaFix。

**根因 A**：`home_screen.dart:60` / `file_service.dart:45` 用 `FileType.custom + allowedExtensions:['md'/'txt'/'tex']`。Android SAF 选择器**按 MIME 过滤**，file_picker 需把扩展名映射为 MIME；`.md` 在多数 Android 版本**没有系统注册的 MIME 映射**（下载的文件常被标为 `text/plain` 或 `application/octet-stream`），映射失败 → SAF 过滤条件对不上 → 文件被隐藏/置灰。这是 file_picker 的已知平台坑。

**根因 B**：`AndroidManifest.xml` 只有 `MAIN/LAUNCHER` 一个 intent-filter（`:23-26`），**完全没有声明 `ACTION_VIEW` + `text/markdown`/`text/plain`/`.md` 路径匹配**，系统当然不会把本 APP 列入「打开方式」。声明后还需接收 intent 的 Dart 侧处理（如 receive_sharing_intent 或 MethodChannel）。

**应在真机前发现？**
- **B：是** —— Manifest 里没有 VIEW intent-filter 是静态可见的，代码评审可拦截；「从外部打开 .md」写在产品目标里却从未声明。
- **A：部分豁免** —— `.md` MIME 映射行为随厂商/版本而异，模拟器上可能正常，这一条属于真机测试的正当产出。但「导入 E2E 从未在任何 Android 环境跑过」仍是流程缺口。

**修复方向**：A：改 `FileType.any` + 选后校验扩展名（弹提示），或传 MIME 白名单 `text/*`；B：Manifest 加 `ACTION_VIEW`（`text/markdown`、`text/plain`、`file`/`content` scheme + `\\.md` pathPattern）intent-filter + 接收链路。

**验收方法与标准**
- **A. APP 内导入选择器（现象 A）**
  - **方法**：真机下载一个 `.md` 到 `Downloads` → APP 内点导入 → 系统选择器应能看到并选中该文件。
  - **标准（可断言）**：
    - **AS-6A.1** 选择器**显示设备上真实存在的 `.md`/`.txt`/`.tex`**（不依赖系统 MIME 注册，改用 `FileType.any` + 选后扩展名校验）。
    - **AS-6A.2** 选中非白名单扩展名 → 给出**明确提示**而非静默失败 / 崩溃。
    - **AS-6A.3** 真机回归通过（因 MIME 行为设备相关，须真机验证，不仅靠模拟器）。
- **B. 系统「打开方式」入口（现象 B）**
  - **方法**：系统文件管理器对 `.md` 用「打开方式」→ 列表应包含 FormulaFix；选中后 APP 启动并加载该文件。
  - **标准（可断言）**：
    - **AS-6B.1** `AndroidManifest.xml` 含 `ACTION_VIEW` intent-filter，匹配 `text/markdown` / `text/plain` + `file`/`content` scheme + `\.md` `pathPattern`。
    - **AS-6B.2** 外部「打开方式」列表**出现 FormulaFix**。
    - **AS-6B.3** Dart 侧接收 intent 并加载文档，**不崩溃**、正确进入导入/预览。
    - **AS-6B.4** 静态 Manifest 评审 + 真机「打开方式」回归双通过。

---

## 汇总表

| # | 问题 | 严重度 | 层级 | 真机前应发现？ | 拦截手段（本应） |
|---|---|---|---|---|---|
| 1 | 回车不分块 / 无即点即插 / 上块不渲染 | **P0** | 编辑内核 | ✅ 是 | E2E 用例设计（分块是第一交互）；代码评审（SplitBlockCommand 无调用方） |
| 4 | 工具栏复活已删文本 | **P0** | 编辑内核 | ✅ 是 | Widget 测试「编辑中途点格式按钮」序列 |
| 2 | 编辑器无有效返回 | P1 | 导航 | ✅ 是 | router Widget 测试（go→back 断言） |
| 3 | 块右上角无作用工具条 | P1 | 交互设计 | ✅ 是 | 移动端设计评审（hover 范式）；单块全禁用断言 |
| 6B | 打开方式无本 APP | P1 | 平台集成 | ✅ 是 | Manifest 静态评审 |
| 5 | OL/UL/Task/+ 不可见 | P2 | 可发现性 | ✅ 是 | 手机视口 golden |
| 6A | 选择器不显示 .md | P1 | 平台坑 | ⭕ 部分豁免 | 真机测试正当产出（MIME 行为设备相关） |

## 流程反思（为什么 5/6 漏到了真机）

1. **测试视口失真**：Widget/golden 测试多用桌面尺寸与鼠标语义（hover），未建立「手机视口 + 触摸语义」基线 → 漏 3/5。
2. **E2E 用例覆盖的是「功能存在」而非「用户序列」**：13 个 E2E 验证渲染结果，没有「新建→打字→回车→删除→格式化→返回」这类真实操作流 → 漏 1/4/2。
3. **平台集成从未列入验收清单**：Manifest intent-filter、SAF 导入链路没有对应检查项 → 漏 6。
4. **建议**：在 ROADMAP 增补「Tier 3.5：手机视口交互序列测试」（Widget 层即可跑，无需真机），并把 Manifest/平台集成加入 release checklist 静态项。

## 与当前工作流的关系

- 问题 2 的修复归属 **PR #93 评审整改**（导航语义，ADR-0018 Decision 1/4 范围）。
- 问题 1/3/4/5 属**编辑内核缺陷**，建议独立 PR（against `fix/touch-chrome-and-tests` 或新分支），不与首页重构混淆。
- 问题 6 属**平台集成**，可单独小 PR（Manifest + picker 参数，改动面小）。
