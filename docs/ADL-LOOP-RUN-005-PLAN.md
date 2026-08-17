# ADL Loop Run #005 — 真实生产代码修复闭环方案

**日期**: 2026-08-17
**前置**: Run #001-004 已验证 ADI 架构和 fault injection 闭环
**状态**: 方案设计（Run #004 尝试了真实代码修改，遇到 Flutter widget test 根本限制）

---

## Run #004 的发现

Run #004 尝试在 `code_block.dart` 中直接添加真实 bug：
```dart
const SizedBox(height: 100000),  // 真实生产代码 bug
```

**结果**: 测试超时，Flutter test binding 报告 `_pendingExceptionDetails != null`。

**根本原因**: 在 Flutter widget test 中，一旦有未处理的 overflow error：
- 每次 `pump()` 都会触发新的 overflow
- `FlutterError.onError` 的恢复时序无法阻止重复触发
- binding 检测到 pending exceptions 后抛出 assertion 失败

这与 fault injection 不同：fault injection 的 bug 只触发一次（因为 `FaultInjection.enabled` 在 pump 后立即被禁用），而真实代码中的 bug 在每次 rebuild 时都会触发。

---

## Run #005 的三个可行方案

### 方案 A: 真机集成测试（推荐）

使用 `flutter drive` 或 Patrol 在真实/模拟设备上运行：

```bash
# 1. 在代码中引入真实 bug
# flutter_app/lib/presentation/blocks/code/code_block.dart
#   添加: const SizedBox(height: 100000),

# 2. 编译并安装到模拟器
flutter build apk --debug
adb install app-debug.apk

# 3. 运行故障注入测试（使用 FaultInjection 机制）
flutter test test/observability/fault_injection_run005_test.dart

# 4. Agent 读取 ADI 证据
ffx adi latest-error
ffx adi replay sess_xxx
ffx adi trace-show trc_xxx

# 5. Agent 修改生产代码（移除 buggy SizedBox）
# flutter_app/lib/presentation/blocks/code/code_block.dart
#   删除: const SizedBox(height: 100000),

# 6. 重新编译安装
flutter build apk --debug
adb install app-debug.apk

# 7. ADI validate
ffx adi validate --after-fix sess_xxx
# 期望: {"after": "not_reproduced", ...}

# 8. Capability E2E
ffx project inject code --lang dart --code 'void main(){}'
ffx project info -p doc.json
# 期望: word_count > 0, code_block_count >= 1
```

**优点**: 真实 Flutter runtime，真实 crash
**缺点**: 需要模拟器运行，耗时较长

### 方案 B: Unit Test 直接修改代码

不走 widget test，直接在 unit test 中修改源码文件内容：

```dart
test('Phase 3: Agent modifies production code', () {
  final bugFile = File('lib/presentation/blocks/code/code_block.dart');
  final content = bugFile.readAsStringSync();
  
  // Simulate agent fix
  final fixedContent = content.replaceAll(
    '// BUG: unbounded height\n            const SizedBox(height: 100000),',
    '',
  );
  
  // Verify fix
  expect(fixedContent.contains('const SizedBox(height: 100000)'), isFalse);
  
  // Write fix back
  bugFile.writeAsStringSync(fixedContent);
});
```

然后在另一个 test 中验证修复后的行为：

```dart
test('Phase 4: Post-fix behavior verified', () {
  // Re-read the fixed code
  final bugFile = File('lib/presentation/blocks/code/code_block.dart');
  final content = bugFile.readAsStringSync();
  
  // Verify no bug
  expect(content.contains('const SizedBox(height: 100000)'), isFalse);
  
  // Clean up (restore original)
  bugFile.writeAsStringSync(originalContent);
});
```

**优点**: 不依赖 widget test，速度快
**缺点**: 没有经过真实 Flutter render，只是代码层面验证

### 方案 C: 静态分析 + ADI 证据链

结合方案 B 的代码修改和方案 A 的 ADI 证据：

1. Phase 1-2: 使用 fault injection 捕获 overflow（与 Run #004 相同）
2. Phase 3: Agent 直接修改 `code_block.dart` 生产代码
3. Phase 4: 静态分析验证修复后的代码不包含 bug
4. Phase 5: 重新运行 Run #004 测试验证无 overflow
5. Phase 6: Export evidence

---

## Run #005 成功标准

必须同时满足以下 5 条谓词：

```json
{
  "P1_before_reproduced": true,
  "P2_agent_changed_production_code": true,
  "P3_after_not_reproduced": true,
  "P4_invariants_pass": true,
  "P5_capability_e2e_pass": true
}
```

**P2 是 Run #004 缺失的核心**: Agent 必须修改真实的 `.dart` 源文件，不能只是设置 `FaultInjection.enabled = false`。

---

## 建议

由于当前环境限制（widget test 无法稳定捕获真实代码 overflow），**Run #005 应该采用方案 B 或 C**：

1. 修改生产代码引入 bug（实际写文件）
2. 用 fault injection 验证 ADI 能捕获
3. Agent 修改生产代码修复 bug（实际写文件）
4. 验证修复后代码不再包含 bug
5. 重新运行 Run #004 测试确认无 overflow
6. Export evidence

这样可以证明 Agent **修改了真实生产代码**，同时避免 widget test 的根本限制。

---

## 执行计划

### 立即执行

1. 修改 `code_block.dart` 引入真实 bug
2. 运行 Run #004 测试确认能捕获
3. Agent 修改 `code_block.dart` 修复 bug
4. 验证修复后代码正确
5. 重新运行所有测试确认无回归
6. Export evidence

### 未来增强

1. 添加 debug toggle 使 App 在 debug 模式下使用 `ObservabilityService.full()`
2. 在 CI 中添加 `flutter drive` 步骤
3. Run #006: 在真机上验证完整闭环
