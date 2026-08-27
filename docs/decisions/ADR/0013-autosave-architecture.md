# ADR-0013：自动保存架构（Autosave Architecture）

> **状态**：Proposed（随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted）
> **版本**：v1.1
> **起草日期**：2026-07-26
> **起草人**：AI Agent 起草，Human Owner 评审决策
> **关联文档**：
> - [Phase 3.4 Task Contract v1.0](../../contracts/phase3.4-task-contract.md)（§3.3 / §9.4，3.4.7 自动保存）
> - [ADR-0009 UI Architecture Design](./0009-ui-architecture-design.md)（Command Layer 强制）
> - [ADR-0012 Live Editing State](./0012-live-editing-state.md)（isDirty / Live vs Committed 双状态）
> - [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)（单一真相源）
>
> **审批路径**：Human Owner 在 Phase 3.4 契约评审中指出「自动保存必须定案，不能留 Coordinator 或 Service 二选一」，故独立成 ADR 冻结，避免 Coordinator 膨胀为 God Object。

---

## 版本修订记录

- **v1.0（2026-07-26）**：初版，冻结独立 `AutosaveService` + `DirtyStateSource` 抽象（去 Coordinator 耦合）。
- **v1.1（2026-07-26，评审补充）**：补 `dirtyChanges` Stream 构造来源（基于 ADR-0012 `LiveEditingState` 的 `ValueNotifier<bool>`）与背压/合并说明；明确并发保存竞态验证点（`markSaved` 异步打断后的状态一致性）。随 PR #68 提交，合并后状态由 Proposed 转 Accepted（ADR-0011 审批模型）。

## 背景

### 当前状态
Phase 3.3 已完成移动端编辑体验，`EditorCoordinator` 已具备：
- `isDirty` getter（Live/Committed 双状态，见 ADR-0012）
- `markSaved()` 方法（手动保存后重置 dirty）
- 手动保存路径（经 `DocumentRepository.save()`）

Phase 3.4 引入 3.4.7 自动保存：修改后定时（debounce）落盘，无需用户手动点保存。

### 触发本 ADR 的事件
Phase 3.4 Task Contract v0.1 将自动保存的实现位置列为二选一：

> `EditorCoordinator` 或独立 `AutosaveService` 持有 `Timer`（debounce，dirty 后 1.5s）。

Human Owner 评审（2026-07-26）明确反对保留二选一，理由：

> 自动保存会成为核心基础设施。未来云同步 / 多设备同步 / 崩溃恢复 / 历史版本都依赖它。如果放 Coordinator，很快变 God Object。必须定。

### 现有约束
- [ADR-0009 §3](./0009-ui-architecture-design.md)：所有文档修改经 Command Layer；自动保存**不是**绕过 Command 直接写文件，而是定时调用已有 save 路径。
- [ADR-0012](./0012-live-editing-state.md)：`isDirty` 计算位置在 Coordinator（Document State 层），自动保存只消费该信号。
- [AGENTS.md §2.3](../../../AGENTS.md)：services / facades 显式依赖注入，禁止全局静态单例承载业务状态。

---

## 决策

**新增独立的 `AutosaveService` 类，不把自动保存逻辑放进 `EditorCoordinator`。**

### 结构

```
DirtyStateSource（抽象）
   │  isDirty / dirtyChanges
   ▼
AutosaveService
   │  debounce（dirty 后 1.5s）
   │  触发 save
   ▼
DocumentRepository.save()   ← 与手动保存共用同一路径（幂等）
   │
   ▼
DirtyStateSource.markSaved()  ← 重置 dirty + timer
```

> **依赖抽象，不依赖具体 Coordinator（评审补充，不影响 ADR 通过）**：`AutosaveService` **不直接依赖 `EditorCoordinator`**，而是依赖抽象 `DirtyStateSource`。`EditorCoordinator` 实现该接口即可；未来 `BackgroundEditorSession` / `CloudDraftSession` 也可复用同一 Service，无需改动 Autosave 逻辑。

```dart
/// 脏状态来源抽象（AutosaveService 仅依赖此接口，不耦合具体 Coordinator）
abstract interface class DirtyStateSource {
  bool get isDirty;               // 当前是否脏
  Stream<bool> get dirtyChanges;  // 脏状态变化流
  void markSaved();               // 保存成功后重置 dirty + timer
}

// class EditorCoordinator implements DirtyStateSource { ... }
```

### dirtyChanges 构造来源与背压（评审补充）

**构造来源（与 ADR-0012 联动）**：`EditorCoordinator` 实现 `DirtyStateSource`，其 `isDirty` / `dirtyChanges` 复用 ADR-0012 的脏状态来源——底层是单一的 `ValueNotifier<bool> dirtyNotifier`（`true` = 当前 live 与 committed 任一不一致）。`dirtyChanges` 由该 notifier 派生：

```dart
// 在 EditorCoordinator 内
final ValueNotifier<bool> _dirtyNotifier = ValueNotifier(false);
// isDirty getter 计算见 ADR-0012（editor.isDirty || 任意 live ≠ committed）
Stream<bool> get dirtyChanges => _dirtyNotifier.stream; // 或 .asBroadcastStream()
```

即 Stream 的「源」只有一处（Coordinator 的 dirty notifier），而非任意编辑事件流，构造关系清晰、无多源竞态。

**背压 / 合并策略**：`dirtyChanges` 由单一 `ValueNotifier<bool>` 转换而来，**每次 isDirty 翻转最多发射一次事件**（不是每次按键一次），本身无高频喷射；其上 `AutosaveService` 再经 debounce(1.5s) 合并连续 dirty 窗口，故无背压/内存风险。若未来需更细信号（如「具体哪块脏」），应另开 `Stream<Set<BlockId>>`，不混用 `dirtyChanges`。

### 职责边界

**`AutosaveService` 负责**：
- 监听 `coordinator.isDirty` 变化（或接受 Coordinator 推送的 dirty 事件）
- debounce（dirty 后 1.5s，连续编辑只触发一次）
- 调用已有 save 路径（与手动保存共用，保证幂等）
- 保存成功后回调 `coordinator.markSaved()` 重置计时与 dirty

**`AutosaveService` 不负责**：
- 文档状态管理（仍属 Coordinator / Document State）
- Command 构造（自动保存不绕过 Command Layer，仅触发落盘，见 ADR-0009）
- UI 渲染（不持有 Widget；「已保存」轻提示由 `chrome/` 订阅服务状态后展示）

**依赖注入（AGENTS.md §2.3）**：`AutosaveService` 由 provider 显式注入，`EditorCoordinator` 持有其引用；禁止全局静态单例。

### Out of Scope（明确不在此 ADR，避免后续误解）
- **崩溃恢复（Crash Recovery）**：App 被杀且 dirty 未保存时的恢复 → 留 Phase 4+，依赖本地事务日志 / WAL。
- **云同步 / 多设备同步**：依赖本服务的 save 抽象，未来接入。
- **历史版本 / 快照**：未来在 save 成功之后追加版本记录，不在本期。

---

## 替代方案

### 替代方案 A：自动保存逻辑放进 EditorCoordinator（拒绝）
```dart
class EditorCoordinator {
  Timer? _autosaveTimer;
  void _onDirty() { _autosaveTimer?.cancel(); _autosaveTimer = Timer(1.5s, _save); }
}
```
**拒绝原因**：
1. Coordinator 已承载 selection / focus / commands / live-state；再加 autosave timer + 生命周期会迅速膨胀为 God Object（违反 Phase 3.0 Hard Rule、Phase 3.3 God Object 守门 ≤200 行）。
2. 未来云同步 / 版本快照接口若堆进 Coordinator，膨胀不可逆。

### 替代方案 B：Riverpod timer provider 自管（可与本 ADR 并存）
provider 持有 `AutosaveService` 实例并管理其生命周期，业务逻辑仍在 service 内。
**采纳为兼容项**：provider 仅作注入容器，不承载 debounce / save 逻辑。

---

## 后果

### 正面后果
1. **Coordinator 不膨胀**：自动保存与文档状态解耦，God Object 守门持续有效。
2. **未来扩展平滑**：云同步 / 版本快照只需扩展 `AutosaveService`（或在其后追加同步层），不碰 Coordinator。
3. **单测友好**：mock save 回调即可验证 debounce / 重试，无需 Widget。

### 负面后果
1. 多一个类与生命周期管理（dirty 订阅的注册 / 注销）。
2. Coordinator 与 Service 需约定 dirty 通知机制（事件 / 流）。

---

## 验证计划

### 单元
- [ ] `dirty` 置 true 后 1.5s 触发 `save` 恰好一次
- [ ] 连续编辑（多次 dirty）在窗口内只 `save` 一次（debounce 合并）
- [ ] `markSaved()` 后 timer 重置，不再重复 save
- [ ] `save` 失败不崩溃，下次 dirty 重新触发（重试）
- [ ] **并发保存保护（`autosave_concurrency_test`）**：`t0` 修改 → `t1` debounce 触发 save A（进行中）→ `t2` 用户继续输入 → `t3` 第二次 debounce 触发 save B 时，必须**串行化**（B 等 A 完成，或 A 完成后基于最新 source 保存），禁止 A 与 B 交错导致 `A 覆盖 B` 把旧内容回写。
- [ ] **保存中 `markSaved` 异步打断的状态一致性（`autosave_concurrency_test` 扩展）**：save A 进行中、`markSaved()` 尚未回调时用户继续输入使 dirty 再次变 true，必须保证——① 新 dirty 触发新的 debounce（不被 A 的 `markSaved` 误清）；② A 落盘的是「触发 A 时的 source 快照」，而非进行中的实时 live（避免回退/未完成内容写盘）；③ A 与 B 各自基于「触发时刻的 source 快照」独立保存，最终落盘内容 = 最后一次成功 save 的 source。

### 架构守门
- [ ] `editor_coordinator.dart` 不含 `Timer` / debounce 逻辑（grep 守门）
- [ ] `AutosaveService` 不 import `blocks/` / `chrome/`（仅依赖 coordinator 接口 + repository）

### E2E（链 3 持久化强制）
- [ ] 修改文档 → 不手动保存 → 等待 >1.5s → 关 App → 重开 → 内容一致（自动保存落盘生效）

---

## 参考文档
- [Phase 3.4 Task Contract v1.0](../../contracts/phase3.4-task-contract.md)
- [ADR-0009 UI Architecture Design](./0009-ui-architecture-design.md)
- [ADR-0012 Live Editing State](./0012-live-editing-state.md)
- [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)

---

**本 ADR 由 AI Agent 起草，v1.0，随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted。**
