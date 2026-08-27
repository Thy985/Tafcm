# ADR-0015：主题架构迁移（Theme Architecture Migration）

> **状态**：Proposed（随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted）
> **版本**：v1.1
> **起草日期**：2026-07-26
> **起草人**：AI Agent 起草，Human Owner 评审决策
> **关联文档**：
> - [Phase 3.4 Task Contract v1.0](../../contracts/phase3.4-task-contract.md)（§3.2 / §9.2，3.4.3 主题切换）
> - [ADR-0009 UI Architecture Design](./0009-ui-architecture-design.md)（UI 层架构）
> - [Phase 3.3 Task Contract §9.1](../../contracts/phase3.3-task-contract.md)（TextSpan 缩放边界，同源问题）
>
> **审批路径**：Human Owner 在 Phase 3.4 契约评审中确认「ThemeExtension 方向正确，但迁移成本可能比预估高（TextSpan / CustomPainter / RenderObject 拿不到 context），故 inline 颜色边界留 Typography Refactor，不在本期顺手解决」。

---

## 版本修订记录

- **v1.0（2026-07-26）**：初版，冻结 `EditorTokens` → `ThemeExtension<EditorTokens>` 迁移；语义兼容 / API 迁移措辞（评审修正）。
- **v1.1（2026-07-26，评审补充）**：补 版本修订记录（与既有 ADR-0011/0012 格式对齐）；状态随 PR #68 合并后由 Proposed 转 Accepted（ADR-0011 审批模型）。
- **v1.2（2026-07-28，Typography 立场调整）**：本 ADR 原 "已知边界" 中 Typography Refactor = `wontfix` + `phase-3.4-typography` 延期 的立场，被 [ADR-0017](./0017-design-system-alignment.md) 覆盖——字体系统提升为 Phase 3.4.5 的 P0-2 一等公民（详见新增 §修订）。

## 修订（2026-07-28）：Typography 立场调整

Phase 3.4.5 Design System Alignment 规划 + [ADR-0017 Design System Token & Typography Alignment](./0017-design-system-alignment.md) 出台后，本 ADR 原 "已知边界" 中 **Typography Refactor = `wontfix` + `phase-3.4-typography` 延期** 的立场**被覆盖**：

- 字体系统（`AppTypography`：serif 文档/标题/公式 + mono 代码 + sans chrome）提升为 Phase 3.4.5 的 **P0-2 一等公民必交付项**，不再 `wontfix`。
- 本 ADR 仅负责主题**机制**（static const → ThemeExtension）；字体**系统**与颜色**值**的单一真相源由 ADR-0017 定义。
- **保留的技术边界**：`TextSpan` / `CustomPainter` / `RenderObject` 拿不到 `BuildContext`、无法运行时 `Theme.of` 查询——这部分仍受限，但字体族（serif / mono / sans）本身在 `TextStyle` 构造时即可绑定，不依赖运行时 theme 查询，因此字体系统落地不受此边界阻塞。

> 本修订不改变 ADR-0015 的"机制"决策（ThemeExtension 路线），仅撤回对 Typography 的 `wontfix` 延期立场。

## 背景

### 当前状态
`EditorTokens` 当前为 `static const` 类：

```dart
class EditorTokens {
  static const textPrimary = Color(0xFF1A1A1A);
  static const linkColor = Color(0xFF1A6FFF);
  // ...
}
```

调用方使用 `EditorTokens.textPrimary`。这是**静态设计变量**，无法随 Flutter `Theme` 动态切换——主题切换（3.4.3）需要运行时按主题取不同色值。

### 触发本 ADR 的事件
Phase 3.4 引入 3.4.3 主题切换（Night / Sepia / GitHub）。早期契约已倾向 `ThemeExtension<EditorTokens>`，但未固化。Human Owner 评审确认方向正确，并指出：

> 迁移成本可能比预估高——你不是只有 `Text()`，可能还有 `TextSpan` / `CustomPainter` / `RenderObject`，这些地方拿不到 context。所以 inline 颜色边界留 Typography Refactor，不要在 Phase 3.4 顺手解决，否则主题切换会膨胀。

### 现有约束
- [Phase 3.3 Task Contract §9.1](../../contracts/phase3.3-task-contract.md)：TextSpan 缩放边界（TextSpan 不支持运行时 `Theme.of`），同属「已知边界」，留 Typography Refactor。

---

## 决策

**`EditorTokens` 从 `static const` 改造为 `ThemeExtension<EditorTokens>`，由 `ThemeData.extensions` 注入；封装 `EditorTokens.of(context)`。所有颜色 token **名称保持一致（语义兼容）**；但 **API 不保证兼容**——调用方式由 `static const` 改为 `ThemeExtension.of(context)` 迁移，需逐文件改造。**

### 迁移形态

```dart
// 改造后
class EditorTokens extends ThemeExtension<EditorTokens> {
  final Color textPrimary;
  final Color linkColor;
  // ... 常量搬为实例字段

  const EditorTokens({required this.textPrimary, required this.linkColor, /* ... */});

  /// 封装 Theme.of(context).extension<EditorTokens>()
  static EditorTokens of(BuildContext context) =>
      Theme.of(context).extension<EditorTokens>()!;

  @override
  EditorTokens copyWith(...) => ...;
  @override
  ThemeExtension<EditorTokens> lerp(...) => ...;
}

// 调用方改造：EditorTokens.textPrimary → EditorTokens.of(context).textPrimary
```

### 主题清单（Phase 3.4 落地）
- `light`（默认）
- `dark`（Night，移动端阅读价值最高）
- `sepia`

每个主题在 `ThemeData` 中提供对应的 `EditorTokens` 实例（经 `extensions: [EditorTokens(...)]`）。

### 已知边界（inline 颜色 / TextSpan 常量）
- `linkColor` 等 `TextSpan` 硬编码常量问题（`editor_tokens.dart` 注释已标注）：`TextSpan` 不支持运行时 `Theme.of(context)`。
- **本阶段边界**：仅保证 `Text` Widget 主题生效；inline 颜色一致性（同 Phase 3.3 §9.1 TextSpan 缩放边界）留后续处理。
- **字体系统不再 `wontfix`**：原 "Typography Refactor = `wontfix` + `phase-3.4-typography`" 立场已被 [ADR-0017](./0017-design-system-alignment.md) 撤回，字体系统（`AppTypography`）提升为 Phase 3.4.5 的 **P0-2 一等公民**（见本 ADR §修订）。字体族（serif / mono / sans）在 `TextStyle` 构造时即可绑定，不依赖运行时 theme 查询，故不受 TextSpan 边界阻塞。
- **不在 Phase 3.4 顺手解决**：主题切换切片不膨胀为全量渲染层重构；但字体系统作为独立 P0-2 任务在 Phase 3.4.5 落地。

### 语义兼容 / API 迁移守门（评审修正措辞）
- **语义兼容（保证）**：所有颜色 token **名称**保持一致（`textPrimary` / `linkColor` 等常量名不变），视觉契约不破。
- **API 不保证兼容（需迁移）**：调用方式由 `EditorTokens.textPrimary`（`static const`）改为 `EditorTokens.of(context).textPrimary`（`ThemeExtension`）。这是 **API 迁移，非向后兼容**；旧 `static const` 调用在改造后必须全部改写，不允许残留。
- 守门：grep `EditorTokens\.` 静态调用在迁移后无残留；守门测试全跑（逐步迁移，每切片 PR 不引入编译失败）。

---

## 替代方案

### 替代方案 B：Riverpod `themeProvider`（拒绝为本 ADR 主方案）
全局监听主题状态，Widget 通过 `ref.watch(themeProvider)` 取色。
**拒绝原因**：
1. 与现有 Provider 体系耦合，且 `TextSpan` / `CustomPainter` 仍拿不到 `ref` / context。
2. `ThemeExtension` 是 Flutter Material 3 标准做法，更解耦、与 `ThemeData` 天然联动。
**备注**：`themeProvider` 仍可用于「当前主题偏好（light/dark/sepia）的持久化与切换入口」，与 `ThemeExtension` 不冲突——前者管「选哪个主题」，后者管「主题色值注入」。

---

## 后果

### 正面后果
1. **动态主题系统**：`EditorTokens` 随 `Theme` 切换，支持 Night / Sepia / 未来自定义主题。
2. **与 Material 3 对齐**：标准 `ThemeExtension` 路线，IDE / 生态工具友好。
3. **扩展平滑**：新增主题只需提供 `EditorTokens` 实例，不改调用方。

### 负面后果
1. **迁移成本**：所有 `EditorTokens.xxx` 调用需改为 `EditorTokens.of(context).xxx`（需逐文件改造 + 守门）。
2. **TextSpan 边界暂未解**：inline 颜色一致性留 Typography Refactor（已知、已标记，不阻塞）。

---

## 验证计划

### 单元
- [ ] `EditorTokens.of(context)` 返回当前 `ThemeData` 注入的对应主题实例
- [ ] 切换 `ThemeData` 后 Widget 重建取到新色值
- [ ] 三个主题（light/dark/sepia）各提供合法 `EditorTokens` 实例

### 架构守门
- [ ] `EditorTokens.xxx` 静态调用在迁移后无残留（grep 守门）
- [ ] `editor_tokens.dart` 不再为纯 `static const`（改为 `ThemeExtension`）

### E2E（链 3 持久化强制，3.4.3 偏好需重开一致）
- [ ] 切换 Night → 关 App → 重开 → 主题偏好保持（SharedPreferences），Text Widget 整体换肤
- [ ] inline 颜色（TextSpan）在 Phase 3.4 允许不一致（已知边界，Issue `wontfix` + `phase-3.4-typography`）

---

## 参考文档
- [Phase 3.4 Task Contract v1.0](../../contracts/phase3.4-task-contract.md)
- [ADR-0009 UI Architecture Design](./0009-ui-architecture-design.md)
- [Phase 3.3 Task Contract §9.1](../../contracts/phase3.3-task-contract.md)（TextSpan 缩放边界）

---

**本 ADR 由 AI Agent 起草，v1.0，随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted。**
