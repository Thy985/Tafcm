# ADR-0022：Renderer Failure Policy（渲染层失败策略）

- **状态**：Accepted
- **日期**：2026-08-06
- **决策者**：Human Owner
- **关联**：[ADR-0009 UI Architecture](./0009-ui-architecture-design.md) / [ADR-0020 Block Model](./0020-block-model.md) / [ADR-0021 Editor Observability](./0021-editor-observability-system.md)
- **取代**：Phase 3.2 PR #3 中"`ListElement / TaskListItemElement / HorizontalRuleElement` 显式抛 `UnimplementedError`"的设计（无独立 ADR，散落在 `block_renderer.dart` docstring + `ui_exhaustive_switch_test.dart` 守门）

---

## 1. 背景

### 1.1 触发事件

2026-08-06 真机验收诊断 zip（`debug/snapshot.json`）首次捕获到生产崩溃：

```
GlobalError: UnimplementedError:
  BlockType TaskListItemElement not supported in Phase 3.2 PR #3
  at block_renderer.dart:111
```

`recentOperations` 回放显示：用户在编辑器中输入 `- [ ] 任务` 后，`command_handler.tryTransform`（Phase 2.7）自动把 `ParagraphElement` 升级为 `TaskListItemElement`，下一帧 `BlockRenderer.build` 抛 `UnimplementedError`，被 `FlutterError.onError` 捕获并写入 observability snapshot。

### 1.2 根因：跨层契约不一致

| 层 | 行为 | 设计阶段 |
|----|------|---------|
| `command_handler.tryTransform` | `- [ ]` / `- [x]` → 自动转换为 `TaskListItemElement` | Phase 2.7 |
| `MarkdownParser.parse` | `- [ ]` → `TaskListItemElement` | Phase 1.5 |
| `BlockRenderer.build` | 遇到 `TaskListItemElement` → `throw UnimplementedError` | Phase 3.2 PR #3 |

**Model 层会生产 `TaskListItemElement`，Renderer 层拒绝渲染。** 用户路径上必然崩溃。

### 1.3 Phase 3.2 PR #3 的原设计意图

原设计（无独立 ADR）要求 Renderer 对未实现类型显式抛 `UnimplementedError`，理由：

> 若有 fallback，新增 Block 类型时不会立刻暴露未实现，可能默默退化显示。
> 显式抛错让 Phase 3.5+ 实现新类型时立即被测试发现。

并配置了两个守门测试强制要求 `throw UnimplementedError`：

- `test/architecture/ui_exhaustive_switch_test.dart:102-109`
- `test/presentation/blocks/phase32_pr3_arch_test.dart:40-54`

### 1.4 原设计的失效场景

原设计**只在测试环境成立**——测试环境中"立即发现"等价于"CI 红灯 → 开发者补 case"。但生产环境中**用户先于 Phase 3.5 触发了未实现类型**，"立即发现"变成"立即崩溃"。

**架构原则**（本 ADR 确立）：

> 用户输入路径上的任何层，都不能因为未来能力缺失而 crash。

## 2. 决策

### 2.1 Renderer MUST NOT crash on unknown BlockElement

`BlockRenderer` 对未实现的 `DocumentElement` 子类型必须**降级渲染**，不允许抛 `UnimplementedError` 或任何异常。

### 2.2 Fallback 层级（Fallback Hierarchy）

```
Specific Renderer（Phase 3.X 实现）
        ↓ 未实现
FallbackBlockRenderer（本 ADR 引入）
        ↓ 渲染 markdown source
ParagraphBlock（已有）
        ↓
用户看到 raw source（可读、可编辑、不丢数据）
```

**`FallbackBlockRenderer` 实现策略**：

1. 调用 `block_serializer.fromElement(element)` 反向序列化为 markdown source 字符串
2. 构造 `ParagraphElement(children: [TextElement(source)])`
3. 委托给 `ParagraphBlock` 渲染

**用户可见效果**：

| Element | 用户看到 |
|---------|---------|
| `TaskListItemElement(checked: false, children: [Text("买牛奶")])` | `- [ ] 买牛奶` |
| `TaskListItemElement(checked: true, children: [Text("完成")])` | `- [x] 完成` |
| `ListElement(ordered: false, children: [Text("苹果")])` | `- 苹果` |
| `ListElement(ordered: true, children: [Text("第一")])` | `1. 第一` |
| `HorizontalRuleElement()` | `---` |

### 2.3 仍允许抛异常的边界

**仅当 Element 不应到达 Renderer 时**才允许抛异常：

- `EmptyLineElement`：BlockEditor 范围外（block separator），保持 `ArgumentError`

**未来新增的"不应到达"类型**：必须在 ADR 中说明为何不应到达，不能凭直觉抛错。

### 2.4 "未实现"检测责任转移

原设计用 Renderer 抛错检测未实现类型。本 ADR 把检测责任转移到：

| 检测层 | 机制 |
|-------|------|
| **测试时** | `unknown_block_fallback_test.dart` 扫描 `block_renderer.dart` 中 `FallbackBlockRenderer` 出现的 case，列出未实现类型清单 |
| **运行时** | `FallbackBlockRenderer` 内部调用 `observability.captureError(type: 'UnsupportedBlockFallback', message: element.runtimeType)` 记录降级事件（LIGHT 模式不阻塞，FULL 模式进 snapshot） |
| **CI 守门** | `ui_exhaustive_switch_test.dart` 更新：从"必须 throw UnimplementedError"改为"未实现类型必须经 FallbackBlockRenderer" |

## 3. 动机

### 3.1 用户数据安全优先于开发便利

Editor 类应用的第一原则：**用户输入不丢**。崩溃 → 自动保存中断 → 用户数据丢失。Phase 3.5 的开发便利不能以生产用户数据为代价。

### 3.2 Model 与 Renderer 演进速度不同

Model 层（`MarkdownParser` / `command_handler`）演化快——新增 markdown 语法支持通常只需解析层改动。Renderer 层演化慢——每个新 Element 类型需要专门的 Block widget（State + 编辑协议 + 渲染协议）。

强制两层同步演进会拖慢 Model 层，或逼迫 Renderer 写半成品。Fallback 解耦两层演进速度。

### 3.3 与 ADR-0021 Observability 协同

`FallbackBlockRenderer` 触发 `captureError`，observability 系统能告诉开发者：

- 哪些未实现类型**实际**被用户触发了（数据驱动优先级）
- 触发频率（用于排 Phase 3.5+ 实现顺序）

比"测试时强制 throw"获得更精准的优先级信号。

### 3.4 与 VS Code / Typora 行为对齐

- VS Code：未知语言插件 → 纯文本显示，不崩溃
- Typora：未支持 markdown 扩展 → source 显示，不崩溃

FormulaFix 作为"移动端 Typora"，应对齐此基线。

## 4. 后果

### 4.1 正面

- ✅ 用户路径不再因未实现 Element 类型而崩溃
- ✅ Model 层新增类型不阻塞 Renderer 层（解耦演进）
- ✅ 未实现类型的实际触发频率可观测（数据驱动 Phase 3.5+ 优先级）
- ✅ 用户看到 raw markdown source，仍可编辑、不丢数据
- ✅ Phase 3.5+ 实现新 Renderer 时只需替换 `block_renderer.dart` 中对应 case，删除 fallback 分支

### 4.2 负面

- ❌ "默默 fallback"可能让开发者忘记实现 Renderer——通过 observability `UnsupportedBlockFallback` 事件 + 测试守门缓解
- ❌ 用户看到 raw source 体验不如专用 Renderer——但比崩溃好，且 Phase 3.5+ 会替换

### 4.3 替代方案

| 方案 | 否决理由 |
|------|---------|
| A. 保持 throw + 让 Phase 3.5 提前实现 | 用户已崩溃，不能等 |
| B. 阻止 `tryTransform` 转换为 `TaskListItemElement` | 违反 Phase 2.7 设计意图，且 `MarkdownParser.parse` 仍会生产该类型 |
| C. Fallback 到 `Container(child: Text(source))` | 不可编辑，用户数据被锁定 |
| D. Fallback 到 `ParagraphBlock` 但显示空内容 | 丢数据 |
| E. **Fallback 到 `ParagraphBlock` + source 字符串**（本 ADR） | 可编辑、不丢数据、实现最简 ✅ |

## 5. 实施清单

### 5.1 代码改动

- [x] `lib/presentation/blocks/fallback_block_renderer.dart`：新建 widget
- [x] `lib/presentation/blocks/block_renderer.dart`：3 种类型改为 `FallbackBlockRenderer(...)`
- [x] `lib/presentation/blocks/fallback_block_renderer.dart`：内部调用 `observability.captureError`

### 5.2 测试改动

- [x] `test/presentation/blocks/fallback_block_renderer_test.dart`：新建，验证 3 种类型的 fallback 行为
- [x] `test/architecture/ui_exhaustive_switch_test.dart`：更新守门规则
  - 删除 "必须 throw `UnimplementedError`" 断言
  - 新增 "未实现类型必须经 `FallbackBlockRenderer`" 断言
- [x] `test/presentation/blocks/phase32_pr3_arch_test.dart`：更新守门规则
  - 删除 "3 种类型必须 throw `UnimplementedError`" 断言
  - 新增 "3 种类型必须经 `FallbackBlockRenderer`" 断言

### 5.3 文档同步

- [x] 本 ADR
- [ ] `docs/ROADMAP.md` Phase 3.5：标注"实现 TaskListItem / List / HorizontalRule 专用 Renderer，移除 fallback 分支"（待 Human Owner 同步）
- [ ] `AGENTS.md` §6.5 Phase 2 禁止事项：补充"Renderer 不允许 throw `UnimplementedError`，必须经 `FallbackBlockRenderer`"（待 Human Owner 同步）

## 6. 验证

### 6.1 真机诊断 zip 回放

修复后，2026-08-06 snapshot 中的崩溃路径（`InsertTextCommand(text: "> ")` → `tryTransform` → `TaskListItemElement` → `BlockRenderer.build`）不再崩溃，用户看到 `> ` 字符以段落形式显示并可编辑。

### 6.2 测试覆盖

- `fallback_block_renderer_test.dart`：3 种元素类型的 fallback 行为
- `ui_exhaustive_switch_test.dart`：守门规则更新后通过
- `phase32_pr3_arch_test.dart`：守门规则更新后通过

### 6.3 observability 验证

修复后，若用户再次触发未实现类型，`snapshot.json` 中 `type` 字段为 `UnsupportedBlockFallback`（而非 `GlobalError`），`message` 包含 element runtimeType。
