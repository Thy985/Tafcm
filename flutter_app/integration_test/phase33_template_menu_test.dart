/// E2E 用例：3.3.10 Markdown 模板插入菜单（P1）。
///
/// 落地 Phase 3.3 Task Contract v1.5 §12 阶段级 E2E Exit Gate。优先级 P1。
///
/// **E2E 场景（来自 §1.2.1 验证矩阵）**：
/// ✅ E2E：点击 + → 选择模板 → 插入对应 Markdown →
///    Parser 转换 Block → 保存后重新打开保持一致
///
/// **必须验证三条链（§12.3,链 3 强制范围）**：
/// - 链 1 用户操作链：点击 + → 选择模板 → InsertTemplateCommand → Coordinator.handle()
/// - 链 2 状态同步链：Command 应用 → 文档变更 → Parser 转换对应 Block 渲染
/// - 链 3 持久化链（强制）：模板插入后 → 保存 → 重新打开文档一致
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

void main() {
  group('phase33.10 模板插入菜单 E2E', () {
    testWidgets('[链1+2] 选择模板 → 插入对应 Markdown + Block 转换', (tester) async {
      await pumpEditorApp(tester);
      // TODO(phase33.10): 点击 + → 选择「表格」/「Mermaid」/「代码块」→
      //   断言文档插入对应 Markdown 源且 Parser 转换为 TableBlock / MermaidBlock / CodeBlock
      // 链 1：选择模板 → InsertTemplateCommand → Coordinator.handle()
      // 链 2：Command 应用 → 文档变更 → Parser 重渲染 Block
    }, skip: true);

    testWidgets('[链1] CodeBlock 内 + 按钮禁用', (tester) async {
      await pumpEditorApp(tester);
      // TODO(phase33.10): 进入 CodeBlock → 断言 + 按钮禁用（代码内容原样保留）
      // 链 1：CodeBlock 例外（§2.7）禁用模板插入
    }, skip: true);

    testWidgets('[链3] 模板插入后保存 → 重新打开一致', (tester) async {
      await pumpEditorApp(tester);
      // TODO(phase33.10): 插入模板 → 保存 → Reload →
      //   断言文档（含模板生成的 Block）一致
      // 链 3（强制）：Save → Reload → Document 恢复
    }, skip: true);
  });
}
