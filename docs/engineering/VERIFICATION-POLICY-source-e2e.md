# Tafcm Editor E2E Test Plan（端到端验证计划）

> **状态**：Phase 3.6.1 完成，Phase 3.6.2 完成（2026-08-03）— Patrol 接入 + 4 Extended + 2 Patrol 测试，真机/模拟器运行验证通过  
> **来源**：UI_FIX_PLAN P0-P2 已全部完成合并，P3 颜色令牌守门已建立，经架构评审确认"最大风险不在单个模块，而在跨层协作链路"  
> **配套文档**：`docs/ROADMAP.md`（建议插入 Phase 3.6 Editor Reliability & Behavioral Verification）  
> **方法**：先定义框架与场景，审核通过后逐批实施

---

## 0. 为什么需要 E2E

当前测试体系覆盖了"零件正确性"：

```
单元测试 ── 每个 Command 的 apply/revert ✅
架构测试 ── 分层依赖 / 颜色守门 / 文件访问 ✅
集成测试 ── Transaction 历史 / Parser-Serializer 一致性 ✅
Golden    ── 视觉回归 ✅
```

但**不覆盖**用户真实路径：

```
用户手指
  ↓
软键盘 / Tap
  ↓
TextField（live state，Flutter 内部控制）
  ↓
Intent（onSubmitted / onChanged 等）
  ↓
Command（经 EditorCoordinator 或直接）
  ↓
Transaction（rollback / coalesce）
  ↓
AST（Document 模型）
  ↓
Renderer（BlockRenderer → Widget Tree）
  ↓
保存（FileService）
  ↓
重新打开（Parser → Document）
  ↓
状态恢复
```

**Phase 2 阶段踩过的坑**（回车分块不触发、删除后加粗复活、真机行为 ≠ 模拟器）——均为单元测试覆盖不到的全链路同步问题。E2E 的使命就是堵上这个缺口。

### 核心判断

> "Block Model 完成之后做 E2E，不是补测试，而是在验证架构设计是否真的成立。"

当前测试体系验证的是"组件正确 → 模块正确"。E2E 要推进到"用户行为经过完整系统后，最终状态正确"——这是编辑器项目非常关键的分界线。

---

## 1. 测试金字塔定位

```
             ⬆ 少
         E2E        ← 本计划覆盖
     Integration    ← 已有（Transaction / Parser / IME）
   Unit + Arch      ← 已有（Command / Operation / 守门）
Golden             ← 已有（UI_FIX_PLAN 完成）
             ⬇ 多
```

| 层 | 数量级 | 运行速度 | 覆盖目标 |
|----|--------|---------|---------|
| Unit | 数百 | ms 级 | 单个函数/类的正确性 |
| Architecture | 数十 | ms 级 | 分层依赖/编码规范 |
| Integration | 数十 | 秒级 | 模块间协作（Transaction/History） |
| Golden | 数十 | 秒级 | 视觉一致性 |
| **E2E** | **10-15** | **分钟级** | **用户真实路径完整闭环** |

E2E 不追求数量，追求**关键路径覆盖**。每个 E2E 测试验证一条完整用户场景，失败直接反映用户体验问题。

---

## 2. 测试框架选型

### 2.1 主框架：`integration_test`

Flutter 官方 `integration_test` 包（已在 `pubspec.yaml` 声明）：

```
integration_test:
  sdk: flutter
```

**能力**：
- 在真机/模拟器上运行完整 App
- `tester.enterText()` 模拟键盘输入
- `tester.tap()` 模拟点击
- `tester.binding.setSurfaceSize()` 控制屏幕尺寸

**定位**：验证 App 内部行为，不依赖外部系统交互。

**局限**：
- `enterText` 模拟的是 Flutter 的 TextInput 通道，不是真实键盘事件
- 无法模拟 IME 组合态输入（如中文拼音输入法）
- 无法模拟物理键盘快捷键

### 2.2 增强框架：`patrol`

`patrol`（leancode.co）在 Phase 3.6.2 引入，定位为：

```
integration_test: 验证 App 内部行为（Flutter 引擎可控）
Patrol:           验证 Flutter 无法模拟的系统交互
```

Patrol 覆盖：
- 真机键盘输入（native input events）
- IME 组合态输入
- 原生权限弹窗处理
- 系统返回、通知栏交互
- 外设键盘快捷键

### 2.3 框架选择理由

**Phase 3.6.1（Core E2E）只用 `integration_test`，Phase 3.6.2 再引入 `patrol`。**

原因：当前问题不是"真实手机输入"，而是"架构链路是否成立"。第一阶段聚焦验证：

```
Flutter Widget → Intent → Transaction → AST
```

第二阶段再处理：

```
Gboard / 中文输入 / IME composition
```

顺序正确。不要一开始引入 Patrol。Patrol 不是必须升级路线，而是按需补充。

### 2.4 目录结构

```
flutter_app/
├── integration_test/               ← 官方 integration_test 测试
│   ├── e2e/
│   │   └── editor/
│   │       ├── core/               ← Phase 3.6.1 Core E2E
│   │       │   ├── e2e_core_001_persistence_roundtrip_test.dart
│   │       │   ├── e2e_core_002_paragraph_split_test.dart
│   │       │   ├── e2e_core_003_block_merge_test.dart
│   │       │   ├── e2e_core_004_transaction_undo_test.dart
│   │       │   ├── e2e_core_005_format_roundtrip_test.dart
│   │       │   └── e2e_core_006_typing_coalescing_test.dart
│   │       ├── extended/           ← Phase 3.6.2 Extended
│   │       │   ├── e2e_ext_001_code_block_enter_test.dart
│   │       │   ├── e2e_ext_002_list_behavior_contract_test.dart
│   │       │   ├── e2e_ext_003_transaction_failure_recovery_test.dart
│   │       │   └── e2e_ext_004_dirty_state_test.dart
│   │       └── helpers/
│   │           ├── e2e_app.dart           ← pumpE2EApp 工具
│   │           ├── e2e_editor.dart        ← 编辑器操作封装
│   │           └── e2e_assertions.dart    ← 自定义断言
│   └── app_startup_test.dart              ← 已有
├── test/
│   └── e2e_domain/                        ← Domain 层验证（快速集成测试）
│       ├── split_merge_domain_test.dart
│       ├── format_domain_test.dart
│       └── selection_cursor_contract_test.dart  ← 新增：光标/选中/Selection 契约
└── patrol/                                 ← Phase 3.6.2 引入
    └── e2e/
        ├── ext_004_ime_composition_test.dart
        └── ext_005_physical_keyboard_test.dart
```

### 2.5 核心原则：E2E 与 Domain 层职责分离

**E2E 测试不过度依赖内部 AST 结构。** 遵循两层严格分离：

| 层 | 位置 | 验证内容 | 速度 |
|----|------|---------|------|
| **用户层（E2E）** | `integration_test/e2e/editor/` | 用户可观察行为（视觉上出现两个编辑区域、文字显示正确、加粗样式可见） | 分钟级 |
| **Domain 层** | `test/e2e_domain/` | 内部数据结构正确（`blocks.length == 2`、`cursor.blockId` 正确、AST inline 含 Bold） | 秒级 |

**原因**：E2E 太了解 AST 会导致 UI 改一点测试全部炸。E2E 应该测试"用户可观察行为"，不是"内部数据结构"。

**强制规则**：E2E 测试中禁止出现 `document.blocks`、`blocks[0].source`、`cursor.blockId` 等内部状态断言。这些全部归 Domain 层。

---

## 3. 测试场景设计

### 3.1 总体架构

```
Phase 3.6.1 Core E2E（6 个核心场景）
├── E2E-CORE-001 Persistence Roundtrip      ← 最高优先级
├── E2E-CORE-002 Paragraph Split            ← Block 核心
├── E2E-CORE-003 Block Merge                ← 缺失必补
├── E2E-CORE-004 Transaction Semantic Undo  ← 验证 D3 格式撤销
├── E2E-CORE-005 Format Roundtrip           ← 验证语义保持
└── E2E-CORE-006 Typing Session Coalescing  ← 验证输入合并撤销

Phase 3.6.2 Extended（扩展场景）
├── E2E-EXT-001 CodeBlock Enter
├── E2E-EXT-002 List Behavior Contract
├── E2E-EXT-003 Transaction Failure Recovery
├── E2E-EXT-004 Unsaved Mutation Isolation
├── E2E-EXT-005 IME Composition（Patrol）
└── E2E-EXT-006 Physical Keyboard Shortcut（Patrol）
```

---

### 3.2 Phase 3.6.1 Core E2E

#### 3.2.1 E2E-CORE-001 持久化完整闭环

**场景**：用户创建文档 → 输入文字 → 保存 → 关闭 → 重新打开 → 验证内容一致。

**Failure indicates**：FileService 写入失败、Parser 序列化/反序列化不一致、AutoSave 时机错误、DocumentProvider 状态未正确恢复。

**测试步骤**：

```
1. pump App → 首页
2. 点击「新建文档」
3. 进入编辑器
4. 输入 "Hello Tafcm"
5. 触发保存（等待自动保存或 saveNow() 测试 hook）
6. 回到首页
7. 重新打开该文档
8. 验证编辑器内容为 "Hello Tafcm"
```

**验证点**（仅限用户可观察行为）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 首页显示新文档标题 | `find.text('未命名文档')` 存在 |
| 2 | 编辑器加载完成 | `find.byType(EditorPage)` 存在 |
| 3 | 输入内容正常显示 | `find.text('Hello Tafcm')` 存在 |
| 4 | 重新打开后内容一致 | `find.text('Hello Tafcm')` 仍存在 |

**Domain 层验证**（`test/e2e_domain/`）：

- 保存后文件存在：`FileService.exists(path)`
- 序列化/反序列化 round-trip：`Parser.parse(serializer.serialize(doc))` 等价

**边界条件**：
- 空文档（只创建不输入 → 保存 → 打开）
- 含特殊字符（`# * _ [ ] ( ) > ` `` ` 等 Markdown 语法字符）
- 含 Unicode（中文、数学符号、emoji）

---

#### 3.2.2 E2E-CORE-002 回车分块

**场景**：用户输入多行文本，回车产生新 Block。

**Failure indicates**：SplitBlockCommand 与 EditorCoordinator 同步失败、光标未正确跳转到新 Block、Intent 管道未正确触发 Command。

**用户层验证**：

```
1. 进入编辑器（新文档）
2. 输入 "hello"
3. 按 Enter
4. 输入 "world"
5. 验证视觉上出现两个编辑区域，内容分别为 "hello" 和 "world"
```

**验证点**（用户层）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 两个可编辑区域出现 | 视觉上确认两个独立编辑区域 |
| 2 | 文本内容正确 | "hello" 和 "world" 分别出现在各自区域 |

**验证点**（光标）：
- 光标落在第二个编辑区域开头（"world" 之前）

**Domain 层验证**（`test/e2e_domain/split_merge_domain_test.dart`）：

```
1. 构造 Document 含 1 个 Paragraph("hello")
2. 执行 SplitBlockCommand(blockId, offset=5)
3. 验证 blocks.length == 2
4. 验证 blocks[0].source == "hello"
5. 验证 blocks[1].source == ""
6. 验证 cursor.blockId == blocks[1].id
```

**边界条件**：
- 空行回车（连续 Enter 3 次 → 3 个空 Paragraph）
- 开头回车（光标在第一行开头按 Enter → 上方空行）
- 末尾回车（光标在最后按 Enter → 下方空行）
- 中间回车（"he|llo" 按 Enter → "he" + "llo"）

---

#### 3.2.3 E2E-CORE-003 Block Merge

**场景**：两个 Block 之间按 Backspace 合并。

**Failure indicates**：MergeBlockCommand 未正确拼接 source、BlockId 生命周期管理错误（孤立 ID）、光标位置计算错误。

**用户层验证**：

```
1. 进入编辑器
2. 输入 "hello"
3. 按 Enter（分块）
4. 输入 "world"（两个 Block："hello" | "world"）
5. 将光标移到第二块开头
6. 按 Backspace
7. 验证视觉上合并为一个编辑区域，内容为 "helloworld"
```

**验证点**（用户层）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 合并为一个编辑区域 | 仅 1 个可编辑区域 |
| 2 | 内容拼接正确 | 文本显示 "helloworld" |

**验证点**（光标）：
- 光标在 "hello" 和 "world" 之间（"hello|world"）

**Domain 层验证**：

```
1. 构造 Document 含 2 个 Paragraph("hello", "world")
2. 执行 MergeBlockCommand(blockId=blocks[1].id)
3. 验证 blocks.length == 1
4. 验证 blocks[0].source == "helloworld"
5. 验证光标在 "hello" 之后（offset=5）
```

**重要性**：BlockId 生命周期——split 创建 ID，merge 销毁 ID。这是 D2 最容易出问题的地方，也是当前测试未覆盖的空白。

**边界条件**：
- 合并后总内容超长
- 合并带格式的 Block（如 Bold + Plain）
- 连续合并（3 个 Block 合并为 1 个）
- 首 Block 无法向前合并（Backspace 在第一个 Block 开头 → 无操作）

---

#### 3.2.4 E2E-CORE-004 Transaction Semantic Undo

**场景**：格式操作后 Undo/Redo，验证一个 Command = 一个历史节点。

**Failure indicates**：History 未正确记录 Transaction、Undo 粒度错误（逐字符而非语义操作）、Redo 后状态与预期不符、跨 session 持久化丢失。

**用户层验证**：

```
1. 进入编辑器
2. 输入 "hello"
3. 点击工具栏 Bold 按钮（加粗 "hello"）
4. 此时文本显示为加粗样式
5. 点击工具栏 Undo 按钮
6. 验证文本恢复为纯文本（无加粗）
7. 点击工具栏 Redo 按钮
8. 验证文本恢复加粗样式
9. 关闭文档
10. 重新打开
11. 验证最终状态为加粗（Redo 后的状态已保存）
```

**验证点**（用户层）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | Undo 后格式去除 | 文本无加粗样式 |
| 2 | Redo 后格式恢复 | 文本加粗样式 |
| 3 | 跨 session 状态一致 | 重新打开后加粗保持 |

**Domain 层验证**：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | Undo 粒度 = 语义操作 | 一次 Bold 操作回退，不是逐字符撤销 |
| 2 | 撤销后 AST 正确 | `blocks[0].inline` 无 Bold |
| 3 | Redo 后 AST 恢复 | `blocks[0].inline` 含 Bold |

**边界条件**：
- 空文档撤销 → 无变化
- 撤销后新输入截断历史 → 无法重做旧操作

> **注意**：Core E2E 只使用工具栏 Undo/Redo 按钮，不使用 Ctrl+Z/Ctrl+Shift+Z 快捷键。键盘快捷键归 E2E-EXT-006 Patrol 测试。

---

#### 3.2.5 E2E-CORE-005 Format Roundtrip

**场景**：输入文字 → 选中部分 → 加粗 → 保存 → 重新打开 → 验证 Markdown 语义保留。

**Failure indicates**：Selection 与加粗 Command 的交互错误、序列化后 AST 语义丢失、反序列化后加粗还原失败。

**用户层验证**：

```
1. 进入编辑器
2. 输入 "hello world"
3. 长按 → 拖动选择 "ell"（真实用户选择行为）
4. 点击加粗按钮（工具栏）
5. 验证视觉上 "ell" 变为加粗
6. 保存
7. 重新打开
8. 验证 "ell" 仍为加粗
```

**验证点**（用户层）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 选中部分加粗可见 | "ell" 显示为加粗样式 |
| 2 | 非选中部分未受影响 | "hello " 和 " world" 保持默认样式 |
| 3 | 跨 session 语义保持 | 重新打开后 "ell" 仍为加粗 |

**Domain 层验证**（`test/e2e_domain/format_domain_test.dart`）：

```
1. 构造 Document 含 Paragraph("hello world")
2. 构造 TextSelection(baseOffset: 6, extentOffset: 9)
3. 执行 ToggleBoldCommand(blockId, selection)
4. 验证 AST inline 含 Bold(Text("ell"))
5. 验证 serializer.serialize() 含 "**ell**"
6. 验证反序列化后 AST 等价
```

**不混层**：E2E 不直接构造 `TextSelection`，只测真实用户行为（长按拖动选择）。`TextSelection` 构造放 Domain 层集成测试。

**边界条件**：
- 选中整个单词（"hello" → `**hello**`）
- 选中跨空格（"hello wo" → 含空格，验证分割）
- 取消加粗（已加粗文本上再点 B → 去除 Bold）
- 嵌套格式（**加粗 _斜体_**）

---

#### 3.2.6 E2E-CORE-006 Typing Session Coalescing

**场景**：多次连续输入后的 Undo 应为一次语义操作，而非逐字符回退。

**Failure indicates**：Transaction Coalescing 未生效、History 将每个字符事件视为独立节点、Undo 后光标位置不正确。

**用户层验证**：

```
1. 进入编辑器
2. 输入 "hello"（连续输入事件经过 Transaction Coalescing 后，应形成一个用户级历史节点）
3. 点击工具栏 Undo 按钮
4. 验证所有文本全部消失，而非逐字符回退
```

**验证点**（用户层）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 撤销后文本全部消失 | 编辑区域为空 |
| 2 | 非逐字符撤销 | 中间状态（"hell"、"hel"）从未出现 |

**Domain 层验证**：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 5 次 insert = 1 个 TypingTransaction | `history.entries.length == 1` |
| 2 | 撤销后 blocks 为空 | `document.blocks.isEmpty` |

**边界条件**：
- 输入暂停超过 coalesce 窗口 → 产生新历史节点
- 输入 + 格式操作 → 不合并（格式操作独立成节点）
- 空文档撤销 → 无变化

---

### 3.3 Phase 3.6.2 Extended

#### 3.3.1 E2E-EXT-001 CodeBlock Enter

**场景**：代码块内 Enter 不产生新 Block，只换行。

**测试步骤**：

```
1. 进入编辑器
2. 输入 ``` 触发代码块
3. 输入 "hello"
4. 按 Enter
5. 输入 "world"
6. 验证代码块内有两个换行分隔的文本行
```

**验证点**：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 单个代码块保持 | 仅 1 个代码块编辑区域 |
| 2 | 换行后内容完整 | 文本显示 "hello\nworld" |

**边界条件**：
- 代码块内连续 Enter 4 次 → 多行文本
- 代码块末尾 Enter 后输入文字 → 同一个 Block
- 代码块外 Enter → 正常分块

---

#### 3.3.2 E2E-EXT-002 List Behavior Contract

**类型**：Behavior Contract Test（定义未来行为，List 未成熟时 skip）。

**场景**：用户输入列表项，Enter 延续列表。

**测试步骤**：

```
1. 进入编辑器
2. 输入 "- apple"
3. 按 Enter
4. 输入 "banana"
5. 验证行为符合契约
```

**验证点**（用户层）：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 两个列表项 | 视觉上两个列表项 |
| 2 | 空列表项退出列表 | 空行按 Enter → 变普通段落 |

**契约状态**：`skip: true` + `// TODO(E2E): List 就绪后启用`。契约保留，不阻塞测试进度。

---

#### 3.3.3 E2E-EXT-003 Transaction Failure Recovery

**场景**：Command 执行异常时 Transaction rollback，AST 不损坏。

**测试步骤**：

```
1. 进入编辑器
2. 输入稳定内容（如 "stable content"）
3. 触发一个会在 Command 执行中抛出异常的操作
4. 验证编辑器仍可继续正常编辑
5. 验证后续新输入正常生效
```

**验证点**：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 编辑器可继续编辑 | 后续输入正常显示 |
| 2 | 保存后文件正常 | 重新打开内容一致 |

**注意**：
- 本测试验证的是 **Transaction Failure Recovery**，不是 App Crash Recovery
- 需要注入 FakeCommand 或模拟异常触发点，不依赖真实崩溃
- 真正的 App Crash Recovery（被 kill → 重启 → autosave 恢复）留待后续 Phase 新增

---

#### 3.3.4 E2E-EXT-004 Unsaved Mutation Isolation

**场景**：修改后不保存退出，验证未保存的修改不会污染持久化状态。

**测试步骤**：

```
1. 打开文档
2. 输入 "A"
3. 退出（不保存）
4. 重新打开
5. 验证内容为上次保存的内容（非 "A"）
```

**验证点**：

| # | 验证项 | 检测方式 |
|---|--------|---------|
| 1 | 未保存内容不持久 | 重新打开后无 "A" |
| 2 | 原始内容保持 | 显示上次保存时的内容 |

---

#### 3.3.5 E2E-EXT-005 IME Composition（Patrol）

**场景**：中文拼音输入法组合态输入，验证不会产生错误 Transaction。

**IME 输入生命周期**：

```
Key Event
  ↓
Composition（组合态，如 "ni" → "ni" 高亮）
  ↓
Commit Text（确认，如 "你"）
  ↓
TextField
  ↓
Command
```

**测试步骤**（Patrol）：

```
1. 进入编辑器
2. 通过 Patrol 真机键盘输入拼音 "ni"
3. 选择候选词 "你"
4. 继续输入 "hao"
5. 选择候选词 "好"
6. 验证编辑器显示 "你好"
7. 撤销
8. 验证文本全部消失
```

**注意**：IME 组合态期间不应产生中间 Transaction。只有 Commit 后才产生完整的 Command。

---

#### 3.3.6 E2E-EXT-006 Physical Keyboard Shortcut（Patrol）

**场景**：连接物理键盘时 Ctrl+Z / Ctrl+Shift+Z 等快捷键生效。

**测试步骤**（Patrol）：

```
1. 进入编辑器
2. 输入 "hello"
3. 通过 Patrol 模拟 Ctrl+Z 键盘事件
4. 验证撤销生效
5. 通过 Patrol 模拟 Ctrl+Shift+Z 键盘事件
6. 验证重做生效
```

---

### 3.4 光标/Selection 契约（跨场景验证）

编辑器真正的难点不是文字，而是 **Text + Selection + Block Identity + Transaction History** 的组合。每个 Core E2E 场景必须附带光标/Selection 状态验证。

**跨场景光标契约**：

| 操作 | 期望光标位置 |
|------|------------|
| 回车分块 | 光标在新建 Block 开头 |
| Backspace 合并 | 光标在合并点（前 Block 末尾） |
| Undo 格式操作 | 光标在撤销影响的 Block 内合理位置 |
| Undo 输入合并 | 光标回到输入前的位置 |
| 选中加粗 | 选中范围保持，加粗后 selection 不跳变 |
| 保存后重新打开 | 光标在文档开头（或上次保存位置） |

**Domain 层验证**（`test/e2e_domain/selection_cursor_contract_test.dart`）：

```
每个操作后验证：
1. cursor.blockId 指向存在的 Block
2. cursor.offset 在 Block source 长度范围内
3. Merge 后不存在孤立的 BlockId
4. Split 后新 BlockId 在 document 中唯一
```

---

## 4. 测试验收标准（Pass/Fail Criteria）

### 4.1 通用标准

- 测试在 Android 真机（API 33+）和模拟器（API 33）上均通过
- 测试在 `--release` 模式下运行通过（非 debug-only）
- 测试不依赖外部网络（图片/公式等可离线）
- 测试不依赖特定时区/语言环境

### 4.2 场景特定标准

| 场景 | 硬性要求 | 软性要求 |
|------|---------|---------|
| E2E-CORE-001 | 创建 → 保存 → 重新打开内容一致 | 跨 session 内容正确 |
| E2E-CORE-002 | Enter 后视觉上出现两个编辑区域 | 光标在正确 Block |
| E2E-CORE-003 | Backspace 后合并为一个编辑区域，内容拼接正确 | BlockId 生命周期正确 |
| E2E-CORE-004 | Undo 工具栏 → 格式去除；Redo → 格式恢复；跨 session 保持 | 撤销粒度 = 语义操作 |
| E2E-CORE-005 | 真实选中 → 加粗 → 保存 → 重新打开，语义保持 | 其他格式同理 |
| E2E-CORE-006 | 连续输入后一次撤销清空所有文本 | 非逐字符撤销 |
| E2E-EXT-001 | 代码块内 Enter 不产生新 Block | 换行后内容完整 |
| E2E-EXT-002 | ListItem 行为符合契约（skip 允许） | 空项退出列表 |
| E2E-EXT-003 | 异常后编辑器可继续编辑 | 保存后文件正常 |
| E2E-EXT-004 | 未保存内容不持久 | 原始内容保持 |
| E2E-EXT-005 | IME 输入不产生错误 Transaction | 撤销正确 |
| E2E-EXT-006 | 物理键盘快捷键生效 | 与工具栏 Undo 行为一致 |

### 4.3 测试隔离

- 每个测试使用独立临时目录（`Directory.systemTemp` + 随机子目录）
- 测试之间不共享任何状态
- 每个测试独立 `ProviderScope` 实例
- 测试结束后清理临时目录

---

## 5. 实施计划

### 实施优先级

| 优先级 | 测试 | 原因 |
|--------|------|------|
| P0 | E2E-CORE-001 Persistence | 基础闭环，阻塞其他 |
| P0 | E2E-CORE-002 Split | Block 核心操作 |
| P0 | E2E-CORE-003 Merge | Block 核心操作，当前测试空白 |
| P0 | E2E-CORE-006 Typing Coalescing | 输入撤销基础行为 |
| P1 | E2E-CORE-005 Format Roundtrip | 语义保持，依赖选中能力 |
| P1 | E2E-CORE-004 Transaction Undo | 格式撤销，依赖历史系统 |
| P1 | E2E-EXT-004 Unsaved Mutation Isolation | 数据安全，编辑器最常见灾难 |
| P2 | E2E-EXT-001 CodeBlock | 块类型边界 |
| P2 | E2E-EXT-002 List Contract | 契约定义，可 skip |
| P2 | E2E-EXT-003 Transaction Failure | 异常恢复 |
| P3 | E2E-EXT-005 IME (Patrol) | 真机系统交互 |
| P3 | E2E-EXT-006 Keyboard (Patrol) | 真机外设 |

### Phase 3.6.1 Core E2E（首批 6 个）

| 任务 | 预计产出 | 依赖 |
|------|---------|------|
| E2E 测试基础设施 | `integration_test/e2e/editor/helpers/` 工具集 | 当前 Flutter 版本 |
| Domain 层测试骨架 | `test/e2e_domain/` 目录 + 3 个文件 | 当前 Flutter 版本 |
| E2E-CORE-001 持久化闭环 | 测试通过 | 编辑器入口路由 + FileService |
| E2E-CORE-002 回车分块 | 测试通过（用户层 + Domain 层 + 光标契约） | SplitBlockCommand 就绪 |
| E2E-CORE-003 Block Merge | 测试通过（用户层 + Domain 层 + 光标契约） | MergeBlockCommand 就绪 |
| E2E-CORE-004 Transaction Undo | 测试通过（工具栏路径 + 跨 session） | EditorHistory + Transaction 就绪 |
| E2E-CORE-005 Format Roundtrip | 测试通过（真实选中 + 语义 round-trip） | BoldCommand 就绪 |
| E2E-CORE-006 Typing Coalescing | 测试通过（工具栏 Undo 路径） | Transaction coalesce 就绪 |

### Phase 3.6.2 Extended — 扩展场景 + Patrol 接入

| 任务 | 预计产出 | 依赖 |
|------|---------|------|
| patrol 接入 | `patrol/` 目录 + 示例测试 | `patrol` pub 依赖 |
| E2E-EXT-001 代码块内回车 | 测试通过 | CodeBlock 就绪 |
| E2E-EXT-002 列表行为契约 | 测试跳过（skip + TODO），契约保留 | ListBlock 就绪时启用 |
| E2E-EXT-003 Transaction Failure Recovery | 测试通过 | Transaction rollback + 测试 hook |
| E2E-EXT-004 Unsaved Mutation Isolation | 测试通过 | 编辑器退出路径 |
| E2E-EXT-005 IME Composition | 测试通过（Patrol） | patrol 就绪 |
| E2E-EXT-006 Physical Keyboard | 测试通过（Patrol） | patrol 就绪 |

### Phase 3.6.3：真机验证矩阵

| 设备 | 系统 | 键盘 | 屏幕尺寸 |
|------|------|------|---------|
| Android 真机 | API 35+ | Gboard | 6.7" |
| Android 模拟器 | API 33 | 默认 | 6.0" |
| Android 模拟器 | API 33 | 默认 | 4.7"（小屏） |

---

## 6. E2E 不覆盖的范围

明确不属于 E2E 测试范围：

1. **公式渲染正确性**（标记数学公式能否正确渲染为 SVG — 属 FormulaSvgService 单元测试/集成测试范畴）
2. **Mermaid 图表渲染**（同上）
3. **性能基准**（已有 `performance_baseline_test.dart` 集成测试）
4. **视觉像素级对比**（已有 Golden 测试）
5. **网络异常处理**（本 App 核心功能离线可用）
6. **第三方集成**（分享/导出格式 — 已有导出单元测试）
7. **App Crash Recovery**（被 kill → 重启 → autosave 恢复，留待后续 Phase 新增）

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| `integration_test` 在 CI 中运行不稳定 | 测试假阳性 | 每个测试最多重试 2 次；失败时截图上传 |
| 真机键盘行为与模拟器不一致 | E2E-CORE-002 在真机失败 | Phase 3.6.2 引入 patrol 覆盖真机键盘 |
| 自动保存时机不确定 | E2E-CORE-001 验证保存 | 提供 `saveNow()` 测试 hook 手动触发保存 |
| List 未就绪导致 E2E-EXT-002 阻塞 | 测试进度 | 允许 skip + 标注 TODO，契约保留 |
| 测试执行时间过长 | CI 超时 | Core 6 个 E2E 预估 < 5 分钟；并行化 |

---

## 8. CI 分层策略

E2E 测试按执行频率分层，避免每次 PR 都跑全量导致 CI 过慢：

| 触发时机 | 执行范围 | 预估时间 | 说明 |
|---------|---------|---------|------|
| **PR** | CORE 6 个 | ~5 分钟 | 每次提交自动触发，验证核心状态机 |
| **Nightly** | CORE + EXT（不含 Patrol） | ~15 分钟 | 每日凌晨自动触发，覆盖全场景 |
| **Release** | CORE + EXT + Patrol + 真机矩阵 | ~30 分钟 | 发版前手动触发，含 3 台真机 |

**PR 阶段不跑 Patrol**，原因：
- Patrol 依赖真机或特殊模拟器配置
- 每次 PR 跑 Patrol 会严重拖慢开发节奏
- Patrol 验证的是系统交互，不是架构正确性

**Nightly 失败处理**：自动通知归档，标记为"待修复但不阻塞 PR"。

---

## 9. 附录

### 9.1 未来 AI 扩展路径（预留，不入正文架构）

当前阶段不上 AI。以下场景留待 Phase 4+ 实施，仅做架构预留标注：

```
AI Agent
  ↓
Intent
  ↓
Command
  ↓
Transaction
  ↓
AST
```

**未来 E2E 场景预留**：

```
E2E-AI-001 AI Multi Block Replacement
  - AI 生成内容替换多个 Block
  - 验证 Transaction 合并/回滚
  - 验证 Undo 可回退 AI 操作

E2E-AI-002 AI 内容 + 用户编辑冲突
  - AI 正在写入时用户输入
  - 验证冲突处理 / 状态一致性
```

### 9.2 现有测试资产清单

测试分类 | 文件 | 数量 | 覆盖内容
--- | --- | --- | ---
Unit | `test/` 各目录 | 600+ | 每 Command/Operation/Model 的 apply/revert 和 state 验证
Architecture | `test/architecture/` | 20 个 | 分层依赖/颜色守门/文件访问/Block 类型扩展等
Integration | `test/integration/` | 6 个 | Transaction 历史/Parser-Serializer 一致性/IME Transaction/CRUD 流程等
Golden | `test/golden/` | 31 张 | 首页/编辑器/各 Block 三主题视觉
E2E（已有） | `integration_test/app_startup_test.dart` | 1 个 | App 启动 → EditorPage 加载
E2E（本计划 Core） | `integration_test/e2e/editor/core/` | 6 个 | 持久化/分块/合并/格式 Undo/格式化圆环/输入合并
E2E（本计划 Extended） | `integration_test/e2e/editor/extended/` | 6 个 | 代码块/列表契约/Transaction 恢复/Dirty State/IME/键盘快捷键
Domain 验证（新增） | `test/e2e_domain/` | 3 个 | 分块合并/格式化/Selection+光标契约

---

*本文档由首席架构工程师维护，版本 v4，生效日期 2026-08-02。*

**v4 变更记录**（基于三轮架构审计）：

| # | 问题 | 修改 |
|---|------|------|
| 1 | CORE-006 描述绑定实现细节 | 改为"连续输入事件经过 Transaction Coalescing 后，应形成一个用户级历史节点" |
| 2 | EXT-004 命名过宽 | 改为 "Unsaved Mutation Isolation"，验证未保存修改不污染持久化 |
| 3 | 光标契约遗漏 Selection | 文件改名 `selection_cursor_contract_test.dart`，覆盖 Cursor + Selection + Block Identity |
| 4 | 缺少 Failure indicates | 每个 Core E2E 增加 "Failure indicates" 失败归因指向 |
| 5 | 缺少 CI 分层策略 | 新增 §8：PR → CORE only，Nightly → CORE+EXT，Release → 全量+真机矩阵 |
| 6 | EXT-004 优先级偏低 | 从 P2 提升至 P1（数据安全，编辑器最常见灾难） |
| 7 | Patrol 文档残留错误字符 | 删除 `$(...)`，改为 "native input events" |