/// 3.3.3 焦点模式 E2E（纯 UI 状态，豁免 §12.3 持久化链）。
///
/// 覆盖 §12.3 三条链（持久化链豁免）：
/// - 链 1（用户操作）：点击 AppBar 全屏图标 → _toggleFocus
/// - 链 2（状态同步）：_focusMode → Scaffold appBar / bottomNavigationBar /
///   MarkdownToolbar 置 null → 三处 chrome 隐藏
/// - 退出：双击编辑区（_focusMode 下 onDoubleTap 绑定）恢复 chrome
///
/// **退出双击的 E2E 降级说明**（见 Human Owner 对 gesture E2E 的
/// 「可以降级，不建议继续消耗时间」决策）：
/// DoubleTapGestureRecognizer 在 flutter_test 中不可靠模拟（同一 TestPointer
/// 派发 down/up×2、间隔落在有效窗口内仍偶发不触发；与 zoom 双指
/// 同属「多事件手势识别」的模拟限制）。已在诊断中验证退出状态机
/// 正确（单次 tap 命中祖先 GestureDetector 即调用 _toggleFocus 并恢复
/// chrome），故 E2E 不再以 flaky 的「双击」手势作硬断言，避免阻断
/// E2E 门。§3.3.3 核心（进入即隐藏 chrome）由下方用例确定性覆盖。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/presentation/chrome/markdown_toolbar.dart';
import 'package:tafcm/presentation/chrome/editor_app_bar.dart';
import 'package:tafcm/presentation/chrome/editor_status_bar.dart';
import 'helpers/test_fixture.dart';

void main() {
  group('3.3.3 焦点模式', () {
    testWidgets('点击全屏图标进入焦点模式 → AppBar/Toolbar/StatusBar 隐藏',
        (tester) async {
      await pumpEditorApp(tester);

      // 进入前：三处 chrome 均存在
      expect(find.byType(EditorAppBar), findsOneWidget);
      expect(find.byType(MarkdownToolbar), findsOneWidget);
      expect(find.byType(EditorStatusBar), findsOneWidget);

      // 链 1：点击全屏图标（tooltip '焦点模式'）
      await tester.tap(find.byTooltip('焦点模式'));
      await tester.pumpAndSettle();

      // 链 2：三处 chrome 隐藏（§3.3.3 核心，确定性覆盖）
      expect(find.byType(EditorAppBar), findsNothing);
      expect(find.byType(MarkdownToolbar), findsNothing);
      expect(find.byType(EditorStatusBar), findsNothing);
    });
  });
}
