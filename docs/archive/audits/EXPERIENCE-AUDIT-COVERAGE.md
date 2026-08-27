# Experience Audit 覆盖报告（Phase 3.9）

**日期**: 2026-08-19
**前置**: Behavior Audit（CAP-BEH-001~009 全绿）+ Word Export 收口
**状态**: ✅ Experience/IME 线首轮审计完成

---

## 1. 覆盖盘点（2026-08-19 实测）

| 维度 | 现有覆盖 | 状态 |
|------|---------|------|
| **IME 真机** | **cap_ime_composing_test（模拟器 integration_test，2 项）——本次新增** | ✅ 本次补齐 |
| **输入延迟** | block_perf_test（median < 10/32ms 阈值）+ **cap_exp_audit CAP-EXP-003（输入→渲染同步 smoke）——本次新增** | ✅ 本次补齐 |
| **主题** | golden matrix（dark @800 / light @834 / dark @834 / textScale 1.3 / light @800）+ cap_exp_audit CAP-EXP-004（light/dark 渲染无异常） | ✅ 已有 + 本次补 |
| **Golden** | 14 个 golden 测试（code_block / editor_shell / formula_block light/dark/sepia / paragraph / heading / inline_formula / toolbar / home / file_manager / matrix / narrow） | ✅ 已有 |
| **手势** | block_drag_gesture_test（拖拽上移/下移/回原位 3 项） | ✅ 已有 |

## 2. 本次新增

### E2E-IME-001：模拟器 IME composing 序列（integration_test）

```text
文件：integration_test/cap_ime_composing_test.dart（2 项）
在真实 Flutter runtime（模拟器 emulator-5554）验证 IME 组合态：
1. 组合中文本显示 + 提交后正确（TestTextInput.updateEditingValue
   注入 composing 范围模拟中文拼音组合中状态 → 提交后中文正确）
2. composing 期间 Undo 不破坏块结构（铁律 1 代理）

验证：模拟器 2 项全绿 ✅
说明：integration_test 无法触发真实 Android 软键盘（tester 走
TestTextInput 通道），本测试验证「真实 runtime 下的 IME composing
状态流」；真实软键盘按键由人工验收覆盖。
```

### CAP-EXP-003/004：输入延迟 + 主题（widget 测试）

```text
文件：test/presentation/cap_exp_audit_test.dart（2 项）
CAP-EXP-003 输入延迟 smoke：连续 20 次输入后 echo 即时渲染
  （每帧同步断言 + pumpAndSettle 收敛 = 无挂起帧/无卡顿）
CAP-EXP-004 主题切换：light/dark 下渲染无异常

验证：2 项全绿 ✅
```

## 3. 验证基线（2026-08-19 实测）

```text
模拟器：cap_ime_composing_test 2 项全绿
widget ：cap_exp_audit_test 2 项 + cap_beh_audit_test 11 项 = 13 项全绿
flutter analyze 0 error / 0 warning
```

## 4. 剩余缺口（声明，非当前主线）

```text
真实 Android 软键盘 IME 按键（tester 无法模拟）→ 人工验收
真机（非模拟器）体验：Golden 已在测试层覆盖，真机物理渲染待
  Experience Audit 后续轮
输入延迟量化基准：block_perf 有阈值，但无「真实设备帧时间」采集
  （可后续接 FrameTiming / integration_test 性能采集）
```

## 5. 结论

```text
Experience/IME 线首轮完成：
  IME composing（模拟器真实 runtime） ✅ 新增
  输入延迟 smoke                         ✅ 新增
  主题 light/dark                        ✅ 新增验证 + golden 已有
  Golden 14 项                           ✅ 已有
  手势（拖拽）                           ✅ 已有

Phase 3.9 审计累计：
  Capability（Batch 1）   ✅
  Behavior（Batch 2 + 扩展）✅（CAP-BEH-001~009，85+ 项）
  Word Export（L1-L6）    ✅（含解析器级 XML 验证）
  DOCX QA Pipeline        ✅（ffx export audit + officecli）
  Experience / IME        ✅ 本次
```
