# Behavior Audit 覆盖矩阵（CAP-BEH-001~009）

**日期**: 2026-08-19（更新：补齐 CAP-BEH-008 Paste + CAP-BEH-005 Selection）
**前置**: Phase 3.9 Behavior Audit（Batch 2 163 项 + 错块专项 + Paste/Selection 扩展）
**关联**: test/editing/cap_beh_audit_test.dart（11 项错块/Paste/Selection 专项）

---

## 1. 覆盖矩阵

| # | 审计项 | 覆盖来源 | 状态 |
|---|--------|---------|------|
| CAP-BEH-001 | Enter（split / 续行） | Batch 2 split 29 项 + input_handler 续行 | ✅ |
| CAP-BEH-002 | Backspace / Merge | Batch 2 merge 29 项 | ✅ |
| CAP-BEH-003 | Undo（错块专项） | cap_beh_audit：多块混合操作 undo 不串块 | ✅ |
| CAP-BEH-003b | Coalescing（错块专项） | cap_beh_audit：连续 op 合并后 undo 一次回起点 | ✅ |
| CAP-BEH-003c | Redo（错块专项） | cap_beh_audit：redo 后块身份恢复 | ✅ |
| CAP-BEH-004 | Redo 基础 | undo_redo 系列（round_trip / block_operations / fuzz） | ✅ |
| CAP-BEH-005 | **Selection 目标块确定性** | **cap_beh_audit：split 右块 index / merge 左块保留 / undo merge 身份恢复** | ✅ **本次补齐** |
| CAP-BEH-006 | Focus 异常（代理） | cap_beh_audit：插入块位置确定性 + undo 回收无悬空 | ✅ |
| CAP-BEH-007 | IME Composition | composing_controller/state + ime_mutation_forbidden（Batch 2 99 项） | ✅ |
| CAP-BEH-008 | **Paste 行为级** | **cap_beh_audit：单 Transaction / 不 coalescing / undo 完整 / 多行保真** | ✅ **本次补齐** |
| CAP-BEH-009 | Block Drag | block_drag_gesture_test | ✅ |

## 2. 本次新增（2026-08-19）

### CAP-BEH-008 Paste 行为审计（4 项）

| 用例 | 验证内容 | 结果 |
|------|---------|------|
| paste 多字符一次性提交 | 5 字符 = 单 Transaction（不逐字符拆分） | ✅ |
| paste 与 keyboard 不 coalescing | 不同 origin undo 独立（undoCount=3） | ✅ |
| paste undo 完整恢复 | 中文多字符回滚无半截残留 | ✅ |
| paste 多行内容保真 | 换行不丢失 + undo 完整回滚 | ✅ |

### CAP-BEH-005 Selection 目标块确定性（3 项）

| 用例 | 验证内容 | 结果 |
|------|---------|------|
| split 后右块 index = 左块 index+1 | 光标可确定性落位 | ✅ |
| merge 后左块保留、右块移除 | selection 目标块确定（indexOf 不悬空） | ✅ |
| undo merge 后块身份恢复 | 右块回到 index=1 | ✅ |

## 3. 验证基线（2026-08-19 实测）

```text
cap_beh_audit_test（11 项）+ undo_redo_fuzz + undo_redo_block_operations +
editor_history + block_operations + composing_controller +
ime_mutation_forbidden = 85 项全绿
flutter analyze 0 error / 0 warning
```

## 4. 剩余缺口（非当前主线）

```text
CAP-BEH-007 IME 真机行为：widget 测试层已覆盖（99 项），
  模拟器真实软键盘 composing 序列未覆盖 → P1 候选
CAP-BEH-006 Focus 真机：模型层代理已覆盖，真机焦点异常未覆盖 → P1 候选
selection_cursor_domain_test 的「光标位置契约」3 个 TODO
  （回车分块/Backspace 合并/Undo 后光标）→ presentation 层待实现
```
