/// E2E 用例：3.3.2 字号缩放（双指缩放 + 按钮 + 重置）。
///
/// 落地 Phase 3.3 Task Contract v1.5 §12 阶段级 E2E Exit Gate。优先级 P1。
///
/// **E2E 场景（来自 §1.2.1 验证矩阵）**：
/// ✅ E2E：打开文档 → 点击放大 → 文本字号变化 → 点击重置 →
///    恢复默认字号；移动端双指缩放手势验证
///
/// **必须验证三条链（§12.3）**：
/// - 链 1 用户操作链：点击缩放按钮 / 双指手势 → 更新 fontScale
/// - 链 2 状态同步链：fontScale 变更 → MediaQuery.textScaler → 文本字号变化
/// - 链 3 持久化链：本功能属纯 UI 状态（§9.1 边界）,**豁免链 3**
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

void main() {
  group('phase33.2 字号缩放 E2E', () {
    testWidgets('[链1+2] 点击放大 → 文本字号变化', (tester) async {
      await pumpEditorApp(tester);
      // TODO(phase33.2): 点击放大按钮 → 断言可见文本字号增大
      // 链 1：点击 → CoordinatorState.fontScale 更新
      // 链 2：fontScale → MediaQuery.textScaler → Text Widget 字号变化
    }, skip: true);

    testWidgets('[链1+2] 点击重置 → 恢复默认字号', (tester) async {
      await pumpEditorApp(tester);
      // TODO(phase33.2): 先放大 → 点击重置 → 断言字号恢复默认
      // 链 1+2：fontScale 重置 → Text Widget 字号复原
    }, skip: true);

    testWidgets('[链1] 双指缩放手势（移动端）', (tester) async {
      await pumpEditorApp(tester);
      // TODO(phase33.2): 模拟 ScaleUpdateGesture（双指）→ 断言 fontScale 变化
      // 链 1：GestureDetector.onScaleUpdate → CoordinatorState.fontScale
      // 注：真机双指手势需在设备上验证,本用例为集成层兜底
    }, skip: true);
  });
}
