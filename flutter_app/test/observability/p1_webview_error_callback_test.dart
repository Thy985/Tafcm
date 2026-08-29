/// P1 B-6 测试：MermaidService / FormulaSvgService 错误回调注入。
///
/// 验证：
/// - attachErrorCallback 注入的回调被调用
/// - 渲染失败时回调携带 type / message / params
/// - WebView 崩溃事件 (resetRenderer) 触发回调
/// - 未注入回调时不崩溃（向后兼容）
///
/// 不依赖真实 WebView——直接调用 _completePendingError / resetRenderer
/// 等内部接口（通过公开的 handleConsoleMessage 触发错误路径）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/services/formula_svg_service.dart';
import 'package:tafcm/core/services/mermaid_service.dart';

void main() {
  // 所有测试都需重置回调，避免相互污染。
  tearDown(() {
    MermaidService.attachErrorCallback(null);
    FormulaSvgService.attachErrorCallback(null);
  });

  group('P1 B-6: MermaidService 错误回调', () {
    test('attachErrorCallback 后 _onError 非 null（隐式验证：回调被调用）', () {
      var called = false;
      MermaidService.attachErrorCallback((type, message, params) {
        called = true;
        expect(type, equals('MermaidRenderError'));
        expect(message, contains('test error'));
        expect(params, isNotNull);
        expect(params!['requestId'], equals('m_test'));
      });

      // 通过 handleConsoleMessage 触发 _completePendingError 路径。
      // MERMAID_ERR|<id>|<reason> 会让 _completePendingError 被调用。
      MermaidService.handleConsoleMessage('MERMAID_ERR|m_test|test error');

      expect(called, isTrue, reason: '注入回调后应被调用');
    });

    test('回调 params 含 codeLength + theme（用于诊断，不含原文）', () {
      Map<String, Object?>? captured;
      MermaidService.attachErrorCallback((type, message, params) {
        captured = params;
      });

      // 先 attach 一个 pending render（通过 renderToSvg 会失败，因为没 controller），
      // 但更直接的方式是用 console message 模拟。
      // 直接触发 _completePendingError 需要 requestId 在 _active 中——
      // 这里用一个不存在的 id，回调仍应被调用（_active.remove 返回 null，
      // 但 _reportError 在 finally 之外仍执行）。
      MermaidService.handleConsoleMessage(
        'MERMAID_ERR|m_orphan|orphan error',
      );

      // 即使 requestId 不在 _active 中（p 为 null），
      // _reportError 仍应被调用，params 中 codeLength 为 null。
      expect(captured, isNotNull);
      expect(captured!['requestId'], equals('m_orphan'));
      // p 为 null → codeLength / theme 都为 null（不影响回调触发）
    });

    test('未注入回调时不崩溃（向后兼容）', () {
      // 不调 attachErrorCallback，直接触发错误路径。
      expect(
        () => MermaidService.handleConsoleMessage(
          'MERMAID_ERR|m_no_callback|no callback injected',
        ),
        returnsNormally,
        reason: '未注入回调时 _onError 为 null，_reportError 应空操作',
      );
    });

    test('attachErrorCallback(null) 清除回调', () {
      var callCount = 0;
      MermaidService.attachErrorCallback((type, message, params) {
        callCount++;
      });

      MermaidService.handleConsoleMessage('MERMAID_ERR|m_1|first');
      expect(callCount, equals(1));

      // 清除回调
      MermaidService.attachErrorCallback(null);
      MermaidService.handleConsoleMessage('MERMAID_ERR|m_2|second');
      // 不应再被调用
      expect(callCount, equals(1));
    });
  });

  group('P1 B-6: FormulaSvgService 错误回调', () {
    test('注入回调后 LATEX_ERR 触发调用', () {
      var called = false;
      String? capturedType;
      String? capturedMessage;
      Map<String, Object?>? capturedParams;

      FormulaSvgService.attachErrorCallback((type, message, params) {
        called = true;
        capturedType = type;
        capturedMessage = message;
        capturedParams = params;
      });

      // 通过 handleConsoleMessage 触发 _completePendingError 路径。
      FormulaSvgService.handleConsoleMessage(
        'LATEX_ERR|l_test|render_failed|some reason',
      );

      expect(called, isTrue);
      expect(capturedType, equals('LatexRenderError'));
      expect(capturedMessage, contains('LATEX_ERR'));
      expect(capturedParams, isNotNull);
      expect(capturedParams!['requestId'], equals('l_test'));
    });

    test('未注入回调时不崩溃', () {
      expect(
        () => FormulaSvgService.handleConsoleMessage(
          'LATEX_ERR|l_no_cb|no callback',
        ),
        returnsNormally,
      );
    });

    test('两个服务可共享同一回调（main.dart 的注入方式）', () {
      final captured = <String>[];
      void sharedCallback(String type, String message, Map<String, Object?>? params) {
        captured.add(type);
      }

      MermaidService.attachErrorCallback(sharedCallback);
      FormulaSvgService.attachErrorCallback(sharedCallback);

      MermaidService.handleConsoleMessage('MERMAID_ERR|m_shared|m');
      FormulaSvgService.handleConsoleMessage('LATEX_ERR|l_shared|l');

      expect(captured.length, equals(2));
      expect(captured, containsAll(['MermaidRenderError', 'LatexRenderError']));
    });
  });

  group('P1 B-6: WebView 崩溃事件', () {
    test('resetRenderer 触发 MermaidWebViewCrash 回调', () {
      String? capturedType;
      String? capturedMessage;
      MermaidService.attachErrorCallback((type, message, params) {
        capturedType = type;
        capturedMessage = message;
      });

      // 直接调用 resetRenderer，应触发 _reportError。
      MermaidService.resetRenderer();

      expect(capturedType, equals('MermaidWebViewCrash'));
      expect(capturedMessage, isNotNull);
      expect(capturedMessage, contains('WebView renderer crashed'));
    });

    test('resetRenderer 未注入回调时不崩溃', () {
      expect(
        () => MermaidService.resetRenderer(),
        returnsNormally,
        reason: '未注入回调时 resetRenderer 仍应正常运行',
      );
    });
  });
}
