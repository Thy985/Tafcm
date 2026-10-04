/// issue #322 回归测试：Mermaid 派发脚本的 JS 语法正确性。
///
/// 根因：`_evaluate` 把主题名以 **裸字符串** 插值进 eval 脚本，生成
/// `window._mermaidTheme!==default` —— `default` 是 ES 保留字，整个 eval
/// 脚本报 `SyntaxError: Unexpected token 'default'`，解析失败 → 每张图都走
/// 「Mermaid 渲染失败」回退卡片。
///
/// 对照：MathJax 通道插值的是 Dart `bool`（合法 JS 字面量），所以 LATEX_OK
/// 正常 —— 这正是「同一份 HTML 资产内公式能渲染、图表不能」的原因。
///
/// 本测试不依赖 WebView：直接断言生成的脚本文本形态。任何把主题参数改回裸
/// 插值的改动都会让它失败。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/services/mermaid_service.dart';

/// 与本缺陷相关的 JS 保留字最小子集（用于检测「裸插值的字符串字面量」）。
const _jsReservedWords = <String>['default', 'class', 'new', 'delete', 'in'];

void main() {
  group('Mermaid 派发脚本 JS 语法（issue #322）', () {
    test('light 主题：主题参数是带引号的字符串字面量', () {
      final script = MermaidService.buildRenderScript(
        requestId: 'm1',
        code: 'graph TD\n  A-->B',
        theme: MermaidTheme.light,
      );
      expect(script, contains("!=='default'"),
          reason: 'theme 必须以带引号的 JS 字符串字面量出现');
      expect(script, contains("_mermaidTheme='default'"));
      expect(script, contains("'m1'"));
      expect(script, endsWith('})()'));
    });

    test('dark 主题：主题参数是带引号的字符串字面量', () {
      final script = MermaidService.buildRenderScript(
        requestId: 'm7',
        code: 'sequenceDiagram\n  Alice->>John: Hi',
        theme: MermaidTheme.dark,
      );
      expect(script, contains("!=='dark'"));
      expect(script, contains("_mermaidTheme='dark'"));
      expect(script, contains("'m7'"));
      expect(script, endsWith('})()'));
    });

    test('任何主题都不产生裸保留字（issue #322 原始症状）', () {
      for (final theme in MermaidTheme.values) {
        final script = MermaidService.buildRenderScript(
          requestId: 'm1',
          code: 'graph TD\n  A-->B',
          theme: theme,
        );
        for (final word in _jsReservedWords) {
          expect(script, isNot(contains('==$word')),
              reason: "theme=$theme 生成了裸保留字 '$word'（缺引号）→ JS SyntaxError");
          expect(script, isNot(contains('=$word;')),
              reason: "theme=$theme 生成了裸保留字 '$word'（缺引号）→ JS SyntaxError");
          expect(script, isNot(contains(', $word)')),
              reason: "theme=$theme 生成了裸保留字 '$word'（缺引号）→ JS SyntaxError");
        }
      }
    });

    test('code 中的换行/单引号被转义，不会截断脚本', () {
      final script = MermaidService.buildRenderScript(
        requestId: 'm2',
        code: "graph LR\n  A[\"it's\"] --> B\n  B --> C",
        theme: MermaidTheme.light,
      );
      // 换行必须是两个字面字符 \n，而不是真实换行
      expect(script, contains(r'graph LR\n'));
      expect(script, contains(r"it\'s"));
      // 转义后 code 仍被包在一对单引号里（结尾是 ', 'default' 的形态）
      expect(script, endsWith(r"""B --> C', 'default');})()"""));
    });
  });
}